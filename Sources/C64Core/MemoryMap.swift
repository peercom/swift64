import Foundation
import Emu6502

/// C64 memory map implementing the Bus protocol.
/// Handles RAM, ROM banking, Color RAM, and I/O chip dispatch.
public final class MemoryMap: Bus {
    public struct CPUPortSnapshot: Equatable {
        public let direction: UInt8
        public let data: UInt8
        public let effective: UInt8
        public let loram: Bool
        public let hiram: Bool
        public let charen: Bool
    }

    // MARK: - Memory arrays

    /// 64K main RAM
    public var ram = [UInt8](repeating: 0, count: 0x10000)

    /// Color RAM (1K, only lower 4 bits significant)
    public var colorRAM = [UInt8](repeating: 0, count: 1024)

    /// BASIC ROM (8K, mapped at $A000-$BFFF)
    public var basicROM = [UInt8](repeating: 0, count: 8192)

    /// Kernal ROM (8K, mapped at $E000-$FFFF)
    public var kernalROM = [UInt8](repeating: 0, count: 8192)

    /// Character ROM (4K, mapped at $D000-$DFFF when CHAREN=0 and I/O visible)
    public var charROM = [UInt8](repeating: 0, count: 4096)

    /// Mounted cartridge ROM, if any.
    public var cartridge: Cartridge?

    /// Called when cartridge I/O may have changed expansion-port interrupt lines.
    public var onCartridgeNMIChange: ((Bool) -> Void)?

    // MARK: - CPU port

    /// CPU port data direction register ($0000)
    public var portDirection: UInt8 = 0x2F

    /// CPU port data register ($0001)
    /// Bits: 0=LORAM, 1=HIRAM, 2=CHAREN, 3=cassette write, 4=cassette sense, 5=cassette motor
    public var portData: UInt8 = 0x37

    /// External cassette sense input. High means no datasette key is pressed.
    public var cassetteSenseLineHigh: Bool = true

    /// Raw cassette write output level driven by CPU port bit 3.
    public var cassetteWriteLineHigh: Bool {
        effectivePort & 0x08 != 0
    }

    /// Raw cassette motor-control output level driven by CPU port bit 5.
    public var cassetteMotorLineHigh: Bool {
        effectivePort & 0x20 != 0
    }

    /// The datasette motor is active when the C64 drives the motor-control line low.
    public var cassetteMotorEnabled: Bool {
        !cassetteMotorLineHigh
    }

    /// Called when the effective cassette write output level changes.
    public var onCassetteWriteLineChange: ((Bool) -> Void)?

    /// Called when the effective cassette motor-control output level changes.
    public var onCassetteMotorLineChange: ((Bool) -> Void)?

    /// Called after CPU writes to the internal 6510 port registers at $0000/$0001.
    public var onCPUPortWrite: ((UInt16, UInt8, CPUPortSnapshot) -> Void)?

    /// Called after a normal CPU RAM write has been committed.
    public var onRAMWrite: ((UInt16, UInt8) -> Void)?

    /// Called after a CPU memory read has produced its visible value.
    public var onCPURead: ((UInt16, UInt8) -> Void)?

    /// Called after a CPU-visible SID register write, with the normalized 5-bit register.
    public var onSIDRegisterWrite: ((UInt16, UInt8) -> Void)?

    /// Called when the CPU writes to the SID address window while RAM/ROM is banked in.
    public var onBankedOutSIDAddressWrite: ((UInt16, UInt8) -> Void)?

    /// Last value driven on the shared VIC/CPU data bus, used for floating reads.
    var cpuDataBus: UInt8 = 0xFF

    /// Number of C64 cycles that a recently driven CPU data-bus value remains
    /// observable before floating lines return high in the simplified model.
    public var cpuDataBusDecayDelay: Int = 64

    private var cpuDataBusDecayCounter: Int = 0

    /// Effective port value considering direction bits
    var effectivePort: UInt8 {
        // For input bits (direction=0), exposed lines read pulled high unless
        // an external input such as cassette sense pulls them low.
        let inputHighMask: UInt8 = cassetteSenseLineHigh ? 0x37 : 0x27
        return (portData & portDirection) | (~portDirection & inputHighMask)
    }

    /// LORAM: BASIC ROM visible at $A000-$BFFF
    var loram: Bool { effectivePort & 0x01 != 0 }
    /// HIRAM: Kernal ROM visible at $E000-$FFFF
    var hiram: Bool { effectivePort & 0x02 != 0 }
    /// CHAREN: Character ROM vs I/O at $D000-$DFFF
    var charen: Bool { effectivePort & 0x04 != 0 }

    public var cpuPortSnapshot: CPUPortSnapshot {
        CPUPortSnapshot(
            direction: portDirection,
            data: portData,
            effective: effectivePort,
            loram: loram,
            hiram: hiram,
            charen: charen
        )
    }

    // MARK: - Chip references (set by C64 machine)

    public weak var vic: VIC?
    public weak var sid: SID?
    public weak var cia1: CIA?
    public weak var cia2: CIA?
    public weak var debugger: Debugger?
    /// Attached RAM expansion, answering IO2 reads and writes and $FF00 triggers.
    public weak var reu: REU?

    /// While the REU holds /DMA the 6510 is disconnected from the bus: its
    /// reads stall on RDY and its writes never reach memory.
    public var cpuWritesDisconnected = false

    // MARK: - Init

    public init() {}

    /// Load ROMs from Data objects.
    public func loadROMs(basic: Data, kernal: Data, charset: Data) {
        basicROM = [UInt8](basic)
        kernalROM = [UInt8](kernal)
        charROM = [UInt8](charset)
    }

    public func resetCPUPort() {
        let previousWriteLine = cassetteWriteLineHigh
        let previousMotorLine = cassetteMotorLineHigh
        portDirection = 0x2F
        portData = 0x37
        cpuDataBus = 0xFF
        cpuDataBusDecayCounter = 0
        notifyCassetteOutputChanges(
            previousWriteLine: previousWriteLine,
            previousMotorLine: previousMotorLine
        )
    }

    public func resetCartridge() {
        cartridge?.reset()
        onCartridgeNMIChange?(cartridge?.nmiLineActive == true)
    }

    // MARK: - Bus protocol

    public func read(_ address: UInt16) -> UInt8 {
        let addr = Int(address)

        // CPU port registers
        if addr == 0x0000 { return finishRead(address, value: portDirection) }
        if addr == 0x0001 {
            // Input bits are pulled high for the lines this model exposes;
            // bit 4 represents no cassette key pressed.
            return finishRead(address, value: effectivePort)
        }

        return finishRead(address, value: bankedRead(address))
    }

    /// A DMA read by an expansion-port bus master: it sees the PLA banking
    /// but not the 6510's internal port (`cpuport` probe), drives the shared
    /// data bus, and raises no CPU watchpoints.
    ///
    /// The PLA's I/O read terms include BA, so a read performed while the VIC
    /// holds BA low (AEC still high) falls through to the RAM under I/O; its
    /// write terms do not. Pass `ioDeselected` for such a cycle (the
    /// `reutiming2` references read the marker under `$DC04` there).
    public func dmaRead(_ address: UInt16, ioDeselected: Bool = false) -> UInt8 {
        let value: UInt8
        if address <= 0x0001 {
            value = ram[Int(address)]
        } else if ioDeselected, address >= 0xD000, address <= 0xDFFF,
                  cartridge?.usesUltimaxMemoryMap != true, hiram || loram, charen {
            value = ram[Int(address)]
        } else {
            value = bankedRead(address)
        }
        driveCPUDataBus(value)
        return value
    }

    /// A DMA write by an expansion-port bus master; see `dmaRead`.
    public func dmaWrite(_ address: UInt16, value: UInt8) {
        driveCPUDataBus(value)
        if address <= 0x0001 {
            ram[Int(address)] = value
            return
        }
        bankedWrite(address, value: value)
    }

    /// The PLA-decoded read for everything except the 6510 port.
    func bankedRead(_ address: UInt16) -> UInt8 {
        let addr = Int(address)
        if cartridge?.usesUltimaxMemoryMap == true {
            return readUltimax(address)
        }

        let value: UInt8
        switch addr {
        case 0x8000...0x9FFF:
            cartridge?.observeRead(address)
            value = cartridge?.read(address) ?? ram[addr]

        case 0xA000...0xBFFF:
            // BASIC ROM or RAM
            if let cartridgeValue = cartridge?.read(address) {
                value = cartridgeValue
            } else if loram && hiram {
                value = basicROM[addr - 0xA000]
            } else {
                value = ram[addr]
            }

        case 0xD000...0xDFFF:
            // I/O or Char ROM or RAM
            if hiram || loram {
                if charen {
                    // I/O area
                    value = readIO(UInt16(addr))
                } else {
                    // Character ROM
                    value = charROM[addr - 0xD000]
                }
            } else {
                value = ram[addr]
            }

        case 0xE000...0xFFFF:
            // Kernal ROM or RAM
            if cartridge?.kernalWindowRequiresHIRAM == true && !hiram {
                value = ram[addr]
            } else if let cartridgeValue = cartridge?.read(address) {
                value = cartridgeValue
            } else if hiram {
                value = kernalROM[addr - 0xE000]
            } else {
                value = ram[addr]
            }

        default:
            value = ram[addr]
        }

        return value
    }

    public func write(_ address: UInt16, value: UInt8) {
        let addr = Int(address)
        // A disconnected CPU still goes through its write cycle, but nothing
        // reaches the bus (`rmw-trigger`: the second write of INC $FF00 is lost).
        guard !cpuWritesDisconnected else { return }

        // The 6510 runs a bus write cycle for its internal port registers
        // but does not drive the data bus, so the RAM under $0000/$0001
        // latches whatever the bus holds: the VIC's phi1 fetch of that cycle
        // (the public `cpuport` probe reads it back through REU DMA).
        if addr <= 0x0001 {
            ram[addr] = cpuDataBus
        } else {
            driveCPUDataBus(value)
        }

        if let dbg = debugger, !dbg.watchpoints.isEmpty {
            dbg.notifyWrite(address, value: value)
        }

        // CPU port registers
        if addr == 0x0000 {
            let previousWriteLine = cassetteWriteLineHigh
            let previousMotorLine = cassetteMotorLineHigh
            portDirection = value
            notifyCassetteOutputChanges(
                previousWriteLine: previousWriteLine,
                previousMotorLine: previousMotorLine
            )
            onCPUPortWrite?(address, value, cpuPortSnapshot)
            return
        }
        if addr == 0x0001 {
            let previousWriteLine = cassetteWriteLineHigh
            let previousMotorLine = cassetteMotorLineHigh
            portData = value
            notifyCassetteOutputChanges(
                previousWriteLine: previousWriteLine,
                previousMotorLine: previousMotorLine
            )
            onCPUPortWrite?(address, value, cpuPortSnapshot)
            return
        }

        bankedWrite(address, value: value)
    }

    /// The PLA-decoded write for everything except the 6510 port.
    func bankedWrite(_ address: UInt16, value: UInt8) {
        let addr = Int(address)
        if cartridge?.usesUltimaxMemoryMap == true {
            writeUltimax(UInt16(addr), value: value)
            if address == 0xFF00 { reu?.writeFF00() }
            return
        }

        // I/O area — writes go to chips if I/O is banked in
        if addr >= 0xD000 && addr <= 0xDFFF && (hiram || loram) && charen {
            writeIO(UInt16(addr), value: value)
            return
        }

        if addr >= 0x8000 && addr <= 0xBFFF, cartridge?.write(address, value: value) == true {
            return
        }

        if addr >= 0xD400 && addr <= 0xD7FF {
            onBankedOutSIDAddressWrite?(address & 0x1F, value)
        }

        // All writes go to RAM underneath
        ram[addr] = value
        onRAMWrite?(address, value)
        // The REC watches the address bus for the $FF00 trigger whatever is banked in.
        if address == 0xFF00 { reu?.writeFF00() }
    }

    func finishRead(_ address: UInt16, value: UInt8) -> UInt8 {
        driveCPUDataBus(value)
        if let dbg = debugger, !dbg.watchpoints.isEmpty {
            dbg.notifyRead(address, value: value)
        }
        onCPURead?(address, value)
        return value
    }

    func driveCPUDataBus(_ value: UInt8) {
        cpuDataBus = value
        cpuDataBusDecayCounter = max(0, cpuDataBusDecayDelay)
    }

    public func tickBus(cycles: Int = 1) {
        guard cycles > 0, cpuDataBusDecayCounter > 0 else { return }
        if cycles >= cpuDataBusDecayCounter {
            cpuDataBusDecayCounter = 0
            cpuDataBus = 0xFF
        } else {
            cpuDataBusDecayCounter -= cycles
        }
    }

    func notifyCassetteOutputChanges(previousWriteLine: Bool, previousMotorLine: Bool) {
        let currentWriteLine = cassetteWriteLineHigh
        if currentWriteLine != previousWriteLine {
            onCassetteWriteLineChange?(currentWriteLine)
        }

        let currentMotorLine = cassetteMotorLineHigh
        if currentMotorLine != previousMotorLine {
            onCassetteMotorLineChange?(currentMotorLine)
        }
    }

    func readUltimax(_ address: UInt16) -> UInt8 {
        let addr = Int(address)
        switch addr {
        case 0x0000...0x0FFF, 0xC000...0xCFFF:
            return ram[addr]
        case 0x8000...0x9FFF:
            cartridge?.observeRead(address)
            return cartridge?.read(address) ?? cpuDataBus
        case 0xE000...0xFFFF:
            return cartridge?.read(address) ?? cpuDataBus
        case 0xD000...0xDFFF:
            return readIO(address)
        default:
            return cpuDataBus
        }
    }

    func writeUltimax(_ address: UInt16, value: UInt8) {
        let addr = Int(address)
        switch addr {
        case 0x0000...0x0FFF, 0xC000...0xCFFF:
            ram[addr] = value
        case 0x8000...0x9FFF:
            _ = cartridge?.write(address, value: value)
        case 0xD000...0xDFFF:
            writeIO(address, value: value)
        default:
            break
        }
    }

    // MARK: - I/O dispatch

    func readIO(_ address: UInt16) -> UInt8 {
        switch address {
        case 0xD000...0xD3FF:
            return vic?.readRegister(address & 0x3F) ?? cpuDataBus

        case 0xD400...0xD7FF:
            return readSIDRegister(address & 0x1F)

        case 0xD800...0xDBFF:
            return (cpuDataBus & 0xF0) | (colorRAM[Int(address - 0xD800)] & 0x0F)

        case 0xDC00...0xDCFF:
            return cia1?.readRegister(address & 0x0F) ?? cpuDataBus

        case 0xDD00...0xDDFF:
            return cia2?.readRegister(address & 0x0F) ?? cpuDataBus

        case 0xDE00...0xDEFF:
            return cartridge?.readIO(address) ?? cpuDataBus

        case 0xDF00...0xDFFF:
            if let reu { return reu.readRegister(Int(address & 0x1F)) }
            return cartridge?.readIO(address) ?? cpuDataBus

        default:
            return cpuDataBus
        }
    }

    func readSIDRegister(_ reg: UInt16) -> UInt8 {
        switch reg {
        case 0x19...0x1C:
            return sid?.readRegister(reg) ?? cpuDataBus
        default:
            return cpuDataBus
        }
    }

    func writeIO(_ address: UInt16, value: UInt8) {
        switch address {
        case 0xD000...0xD3FF:
            vic?.writeRegister(address & 0x3F, value: value)

        case 0xD400...0xD7FF:
            let register = address & 0x1F
            sid?.writeRegister(register, value: value)
            onSIDRegisterWrite?(register, value)

        case 0xD800...0xDBFF:
            colorRAM[Int(address - 0xD800)] = value & 0x0F

        case 0xDC00...0xDCFF:
            cia1?.writeRegister(address & 0x0F, value: value)

        case 0xDD00...0xDDFF:
            cia2?.writeRegister(address & 0x0F, value: value)

        case 0xDE00...0xDEFF:
            cartridge?.writeIO1(address, value: value)
            onCartridgeNMIChange?(cartridge?.nmiLineActive == true)

        case 0xDF00...0xDFFF:
            if let reu {
                reu.writeRegister(Int(address & 0x1F), value: value)
                return
            }
            cartridge?.writeIO2(address, value: value)
            onCartridgeNMIChange?(cartridge?.nmiLineActive == true)

        default:
            break
        }
    }

    func tickCartridge(cycles: Int = 1) {
        cartridge?.tick(cycles: cycles)
    }

    // MARK: - VIC memory access

    /// VIC-II address mapping bypasses CPU banking, but drives the shared data bus.
    public func vicRead(_ address: UInt16) -> UInt8 {
        vicRead(address, portA: cia2?.portAOut ?? 0x03)
    }

    func vicRead(_ address: UInt16, portA: UInt8) -> UInt8 {
        let addr = Int(address & 0x3FFF)  // VIC sees 16K bank
        let bank = Int(~portA & 0x03) * 0x4000
        let physAddr = bank + addr

        let value: UInt8
        if cartridge?.usesUltimaxMemoryMap == true {
            // Ultimax disables character ROM. VIC $3000-$3FFF selects ROMH;
            // pulled-up CPU address lines select its upper 4K in every CIA bank.
            value = addr >= 0x3000
                ? cartridge?.read(UInt16(0xF000 | (addr & 0x0FFF))) ?? cpuDataBus
                : ram[physAddr]
        } else if (physAddr >= 0x1000 && physAddr < 0x2000) || (physAddr >= 0x9000 && physAddr < 0xA000) {
            // Normal cartridge modes leave the VIC character-ROM windows intact.
            value = charROM[physAddr & 0x0FFF]
        } else {
            value = ram[physAddr]
        }
        // A floating CPU read in phi2 observes the preceding VIC phi1 fetch,
        // not the CPU's previous operand byte. Do not emit CPU watchpoints.
        driveCPUDataBus(value)
        return value
    }

    /// VIC bank base address (set by CIA2 port A bits 0-1, inverted)
    public func vicBank() -> Int {
        let bits = ~(cia2?.portAOut ?? 0x03) & 0x03
        return Int(bits) * 0x4000
    }
}

// MARK: - Snapshot state

extension MemoryMap {
    public static let snapshotStoredPropertyCount = 27

    /// ROMs, the cartridge, and callbacks are not part of the memory state.
    func saveState(to w: inout StateWriter) {
        w.write(ram); w.write(colorRAM)
        w.write(portDirection); w.write(portData); w.write(cassetteSenseLineHigh)
        w.write(cpuDataBus); w.write(cpuDataBusDecayDelay); w.write(cpuDataBusDecayCounter)
    }

    func restoreState(from r: inout StateReader) throws {
        let ramBytes: [UInt8] = try r.read()
        let colorBytes: [UInt8] = try r.read()
        guard ramBytes.count == 0x10000, colorBytes.count == 1024 else {
            throw MachineStateError.invalidValue("RAM size")
        }
        ram = ramBytes; colorRAM = colorBytes
        portDirection = try r.read(); portData = try r.read(); cassetteSenseLineHigh = try r.read()
        cpuDataBus = try r.read(); cpuDataBusDecayDelay = try r.read(); cpuDataBusDecayCounter = try r.read()
    }
}
