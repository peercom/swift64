import Foundation
import Emu6502

/// C64 memory map implementing the Bus protocol.
/// Handles RAM, ROM banking, Color RAM, and I/O chip dispatch.
public final class MemoryMap: Bus {

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

    /// Last value driven on the CPU data bus, used for simple open-bus reads.
    var cpuDataBus: UInt8 = 0xFF

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

    // MARK: - Chip references (set by C64 machine)

    public weak var vic: VIC?
    public weak var sid: SID?
    public weak var cia1: CIA?
    public weak var cia2: CIA?
    public weak var debugger: Debugger?

    // MARK: - Init

    public init() {}

    /// Load ROMs from Data objects.
    public func loadROMs(basic: Data, kernal: Data, charset: Data) {
        basicROM = [UInt8](basic)
        kernalROM = [UInt8](kernal)
        charROM = [UInt8](charset)
    }

    public func resetCPUPort() {
        portDirection = 0x2F
        portData = 0x37
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

        if cartridge?.usesUltimaxMemoryMap == true {
            return finishRead(address, value: readUltimax(address))
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
            if let cartridgeValue = cartridge?.read(address) {
                value = cartridgeValue
            } else if hiram {
                value = kernalROM[addr - 0xE000]
            } else {
                value = ram[addr]
            }

        default:
            value = ram[addr]
        }

        return finishRead(address, value: value)
    }

    public func write(_ address: UInt16, value: UInt8) {
        let addr = Int(address)
        cpuDataBus = value

        if let dbg = debugger, !dbg.watchpoints.isEmpty {
            dbg.notifyWrite(address, value: value)
        }

        // CPU port registers
        if addr == 0x0000 {
            portDirection = value
            return
        }
        if addr == 0x0001 {
            portData = value
            return
        }

        if cartridge?.usesUltimaxMemoryMap == true {
            writeUltimax(UInt16(addr), value: value)
            return
        }

        // I/O area — writes go to chips if I/O is banked in
        if addr >= 0xD000 && addr <= 0xDFFF && (hiram || loram) && charen {
            writeIO(UInt16(addr), value: value)
            return
        }

        if addr >= 0x8000 && addr <= 0x9FFF, cartridge?.write(address, value: value) == true {
            return
        }

        // All writes go to RAM underneath
        ram[addr] = value
    }

    func finishRead(_ address: UInt16, value: UInt8) -> UInt8 {
        cpuDataBus = value
        if let dbg = debugger, !dbg.watchpoints.isEmpty {
            dbg.notifyRead(address, value: value)
        }
        return value
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

        case 0xDE00...0xDFFF:
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
            sid?.writeRegister(address & 0x1F, value: value)

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

    /// VIC-II reads memory through its own bus (no ROM banking, sees char ROM at $1000/$9000)
    public func vicRead(_ address: UInt16) -> UInt8 {
        let addr = Int(address & 0x3FFF)  // VIC sees 16K bank
        let bank = vicBank()
        let physAddr = bank + addr

        // Character ROM is visible to VIC at $1000-$1FFF and $9000-$9FFF
        if (physAddr >= 0x1000 && physAddr < 0x2000) || (physAddr >= 0x9000 && physAddr < 0xA000) {
            return charROM[physAddr & 0x0FFF]
        }
        return ram[physAddr]
    }

    /// VIC bank base address (set by CIA2 port A bits 0-1, inverted)
    public func vicBank() -> Int {
        let bits = ~(cia2?.portAOut ?? 0x03) & 0x03
        return Int(bits) * 0x4000
    }
}
