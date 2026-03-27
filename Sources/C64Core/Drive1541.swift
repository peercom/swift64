import Foundation
import Emu6502

/// Full cycle-accurate 1541 disk drive emulation.
///
/// Contains its own 6502 CPU, 2KB RAM, 16KB ROM, two VIA 6522 chips,
/// and a GCR read/write head. Communicates with the C64 via the IEC serial bus.
public final class Drive1541 {

    // MARK: - Components

    public let cpu: CPU6502
    public let memory: DriveMemoryMap
    public let via1: VIA6522  // $1800 — serial bus interface
    public let via2: VIA6522  // $1C00 — disk controller
    public let disk: GCRDisk

    /// Reference to the shared IEC bus
    public weak var iecBus: IECBus?

    // MARK: - Drive state

    /// Current half-track position (0-83, where 0 = track 1.0, 1 = track 1.5, etc.)
    public var halfTrack: Int = 36  // Start on track 18 (directory)

    /// Current track number (1-based)
    public var track: Int { (halfTrack / 2) + 1 }

    /// Head position within the current track's GCR data
    public var headPosition: Int = 0

    /// Stepper motor phase (0-3)
    var stepperPhase: Int = 0

    /// Drive motor is spinning
    public var motorOn: Bool = false

    /// Drive LED state (directly from VIA2 PB3 typically, but also error flash)
    public var ledOn: Bool = false

    /// Byte counter for GCR byte timing
    var byteReadyCycles: Int = 0

    /// SYNC detected flag (10+ consecutive 1-bits under head)
    var syncDetected: Bool = false

    /// Number of consecutive 1-bits seen
    var consecutiveOnes: Int = 0

    /// Current GCR byte being shifted in
    var currentByte: UInt8 = 0
    var bitsShifted: Int = 0

    /// Whether the drive is powered on / enabled
    public var enabled: Bool = true

    /// Debug: cycle counter for periodic logging
    var debugCycleCount: UInt64 = 0
    var bus_atn_was_seen = false
    var driveTraceStart: UInt64 = 0

    // MARK: - Init

    public init() {
        memory = DriveMemoryMap()
        cpu = CPU6502(bus: memory)
        via1 = VIA6522()
        via2 = VIA6522()
        disk = GCRDisk()

        memory.via1 = via1
        memory.via2 = via2

        // VIA1 → CPU IRQ
        via1.onInterrupt = { [weak self] active in
            self?.updateIRQ()
        }

        // VIA2 → CPU IRQ
        via2.onInterrupt = { [weak self] active in
            self?.updateIRQ()
        }

        // VIA1 PB write → immediately update bus state
        via1.onPortBWrite = { [weak self] in
            self?.updateBusFromVIA1()
        }
    }

    // MARK: - ROM loading

    public func loadROM(_ data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count == 16384 else {
            driveLog("[1541] ROM load failed: expected 16384 bytes, got \(bytes.count)")
            return
        }
        memory.rom = bytes
        let resetLo = bytes[0x3FFC]
        let resetHi = bytes[0x3FFD]
        driveLog("[1541] ROM loaded: \(bytes.count) bytes, reset vector=$\(String(format: "%02X%02X", resetHi, resetLo))")
    }

    /// Load ROM from two 8KB halves (common split: c000.bin + e000.bin).
    public func loadROM(c000: Data, e000: Data) {
        var rom = [UInt8](c000)
        rom.append(contentsOf: [UInt8](e000))
        loadROM(Data(rom))
    }

    // MARK: - Disk operations

    public func insertDisk(_ data: Data, isG64: Bool = false) -> Bool {
        if isG64 {
            return disk.loadG64(data)
        } else {
            return disk.loadD64(data)
        }
    }

    public func ejectDisk() {
        disk.tracks = Array(repeating: nil, count: GCRDisk.maxHalfTracks)
    }

    // MARK: - Power on

    public func powerOn() {
        guard memory.rom.count == 16384 else {
            driveLog("[1541] cannot power on — ROM not loaded (size=\(memory.rom.count))")
            return
        }
        let resetLo = memory.rom[0x3FFC]  // $FFFC - $C000 = $3FFC
        let resetHi = memory.rom[0x3FFD]
        driveLog("[1541] powerOn: ROM reset vector = $\(String(format: "%02X%02X", resetHi, resetLo))")

        cpu.powerOn()
        halfTrack = 36  // Track 18
        headPosition = 0
        motorOn = false
        enabled = true
        debugCycleCount = 0

        // Wire the ATN ack recalculation callback
        iecBus?.recalcAtnAck = { [weak self] in
            self?.recalcAtnAck()
        }

        driveLog("[1541] powerOn complete: PC=$\(String(format: "%04X", cpu.pc))")
    }

    public func reset() {
        cpu.reset()
    }

    // MARK: - Tick (one drive clock cycle)

    public func tick() {
        guard enabled else { return }

        debugCycleCount += 1
        // Trace: start when the drive CPU enters the ATN handler at $E85B
        if !bus_atn_was_seen && cpu.pc == 0xE85B && cpu.cycle == 0 {
            bus_atn_was_seen = true
            driveTraceStart = debugCycleCount
            driveLog("[DRV] === ATN handler entered at cyc=\(debugCycleCount) ===")
        }
        if bus_atn_was_seen && debugCycleCount < driveTraceStart + 5000 && cpu.cycle == 0 {
            let bus = iecBus
            driveLog("[DRV] PC=$\(String(format:"%04X",cpu.pc)) A=$\(String(format:"%02X",cpu.a)) PB=$\(String(format:"%02X",via1.portB)) c64Clk=\(bus?.c64Clk ?? false) drvClk=\(bus?.driveClk ?? false) c64Dat=\(bus?.c64Data ?? false) drvDat=\(bus?.driveData ?? false) ack=\(bus?.driveAtnAck ?? false)")
        }

        // Update IEC bus → VIA1 inputs
        updateVIA1FromBus()

        // Tick VIAs
        via1.tick()
        via2.tick()

        // Update bus from VIA1 outputs
        updateBusFromVIA1()

        // Read VIA2 port B for motor/stepper control
        updateDriveControl()

        // GCR head: advance and feed bytes to VIA2
        if motorOn {
            tickGCRHead()
        }

        // Tick CPU
        cpu.tick()
    }

    // MARK: - IEC bus interface (VIA1)

    func updateVIA1FromBus() {
        guard let bus = iecBus else { return }

        // VIA1 Port B inputs:
        // Bit 0: DATA IN (1 when DATA is low on bus)
        // Bit 2: CLK IN (1 when CLK is low on bus)
        // Bit 4: ATN sense (directly, active high when ATN is low)
        // Bit 7: ATN IN (directly, 1 when ATN is low)
        // Bits 1,3,5,6 are outputs (DATA OUT, CLK OUT, etc.) — don't touch
        // Clear all bus-related bits, then set from actual bus state.
        // Bits 0,2,4,7 are inputs from bus. Bits 1,3 are outputs (DATA/CLK OUT).
        // Bits 5,6 are device number (directly from hardware, typically $60 for device 8).
        var pb: UInt8 = 0x60  // Device 8: bits 5,6 high
        if bus.driveDataIn { pb |= 0x01 }   // DATA IN
        if bus.driveClkIn { pb |= 0x04 }    // CLK IN
        if !bus.atn { pb |= 0x10 }          // ATN sense (bit 4: 1 when ATN low)
        if bus.driveAtnIn { pb |= 0x80 }    // ATN IN
        via1.portBInput = pb

        // VIA1 CA1 receives ATN through a hardware inverter.
        // ATN low on bus → CA1 = HIGH; ATN high on bus → CA1 = LOW.
        let newCA1 = !bus.atn
        if newCA1 != via1.ca1 && debugCycleCount <= 20_000_000 {
            driveLog("[1541] CA1: \(via1.ca1)→\(newCA1) ATN=\(bus.atn) ca1Prev(VIA)=\(via1.ca1) PCR=$\(String(format:"%02X",via1.pcr)) IER=$\(String(format:"%02X",via1.ier)) IFR=$\(String(format:"%02X",via1.ifr))")
        }
        via1.ca1 = newCA1

        // ATN auto-acknowledge: when ATN goes low, hardware pulls DATA low
        if bus.checkAtnEdge() {
            bus.driveAtnAck = true
        }

        // VIA1 Port A: device number (bits 0-1, active low for device 8)
        // Device 8 = DIP switches both open = $FF (bits 0-1 = 1,1 → inverted = 0,0 → device 8)
        via1.portAInput = 0xFF
    }

    var prevDriveData: Bool = false
    var prevDriveClk: Bool = false
    var busChangeLog: Int = 0

    func updateBusFromVIA1() {
        guard let bus = iecBus else { return }

        let ddrb = via1.ddrb
        let drivenPB = via1.portB & ddrb

        // Update bus: DATA OUT (bit 1) and CLK OUT (bit 3)
        let newDriveData = drivenPB & 0x02 != 0
        let newDriveClk = drivenPB & 0x08 != 0

        if (newDriveData != prevDriveData || newDriveClk != prevDriveClk) && busChangeLog < 100 {
            busChangeLog += 1
            driveLog("[1541] BUS OUT: DATA=\(newDriveData) CLK=\(newDriveClk) PB=$\(String(format:"%02X",via1.portB)) DDRB=$\(String(format:"%02X",ddrb)) atnAck=\(bus.driveAtnAck)")
        }
        prevDriveData = newDriveData
        prevDriveClk = newDriveClk

        bus.driveData = newDriveData
        bus.driveClk = newDriveClk

        // Recalculate ATN acknowledge
        recalcAtnAck()
    }

    // MARK: - Disk controller (VIA2)

    func updateDriveControl() {
        let pb = via2.portB

        // Motor control (PB2)
        motorOn = pb & 0x04 != 0

        // LED (PB3)
        ledOn = pb & 0x08 != 0

        // Stepper motor (PB0-PB1)
        let newPhase = Int(pb & 0x03)
        if newPhase != stepperPhase {
            let delta = (newPhase - stepperPhase + 4) % 4
            if delta == 1 {
                // Step outward (higher track)
                if halfTrack < GCRDisk.maxHalfTracks - 1 { halfTrack += 1 }
            } else if delta == 3 {
                // Step inward (lower track)
                if halfTrack > 0 { halfTrack -= 1 }
            }
            // delta == 2 means two-phase jump, ignored (shouldn't happen in normal operation)
            stepperPhase = newPhase
        }

        // Speed zone from PB5-PB6
        // (Used for byte timing in tickGCRHead)

        // Write protect sense on PB4 (active low: 0 = protected)
        var pbInput = via2.portBInput & 0x6F  // Clear bits 4 and 7
        if !disk.writeProtected {
            pbInput |= 0x10  // WP tab = not protected
        }
        // Bit 7: SYNC (0 when sync detected)
        if !syncDetected {
            pbInput |= 0x80  // No sync — bit 7 = 1
        }
        via2.portBInput = pbInput
    }

    // MARK: - GCR head simulation

    func tickGCRHead() {
        let zone = GCRDisk.speedZone(for: track)
        let cyclesNeeded = GCRDisk.cyclesPerByte[zone]

        byteReadyCycles += 1

        if byteReadyCycles >= cyclesNeeded {
            byteReadyCycles = 0

            // Read next byte from track
            guard let trackData = disk.tracks[halfTrack], !trackData.isEmpty else {
                via2.portAInput = 0x00
                syncDetected = false
                return
            }

            let byte = trackData[headPosition % trackData.count]
            headPosition = (headPosition + 1) % trackData.count

            // SYNC detection: check for $FF bytes (in real hardware this is bit-level,
            // but at the byte level, a run of $FF bytes = sync)
            if byte == 0xFF {
                consecutiveOnes += 8
                if consecutiveOnes >= 10 {
                    syncDetected = true
                }
                // During sync, the byte is NOT loaded into the shift register
                return
            } else {
                if syncDetected {
                    // First non-$FF byte after sync — this is the first GCR byte
                    syncDetected = false
                    consecutiveOnes = 0
                }
                consecutiveOnes = 0
            }

            // Load the GCR byte into VIA2 port A
            via2.portAInput = byte

            // Signal byte ready (VIA2 CA1 triggers interrupt)
            via2.ca1 = true
            // Pulse: CA1 goes high then low (edge-triggered)
            via2.tick()  // Process the edge
            via2.ca1 = false
        }
    }

    // MARK: - IRQ management

    /// Recalculate ATN ack based on current bus + VIA1 state.
    /// Called both from the drive tick and from IECBus when C64 changes the bus.
    var ackDebugCount = 0
    func recalcAtnAck() {
        guard let bus = iecBus else { return }
        let ddrb = via1.ddrb
        let atnState: UInt8 = bus.atn ? 1 : 0
        // 1541C ATN acknowledge logic:
        // DATA is pulled low when ATN is low (asserted) AND PB4 is low (not set).
        // The firmware sets PB4=1 to release the ack so it can read DATA bits.
        // No CLK gate — the ack stays until firmware explicitly releases via PB4.
        let pb4High: Bool
        if ddrb & 0x10 != 0 {
            pb4High = via1.portB & 0x10 != 0
        } else {
            pb4High = false  // Input: default low for 1541C
        }
        let newAck = !bus.atn && !pb4High  // ATN low AND PB4 low
        if newAck != bus.driveAtnAck && ackDebugCount < 30 {
            ackDebugCount += 1
            driveLog("[1541] atnAck: \(bus.driveAtnAck)→\(newAck) ATN=\(bus.atn) PB=$\(String(format:"%02X",via1.portB)) PB4=\(pb4High) DDRB=$\(String(format:"%02X",ddrb)) c64Atn=\(bus.c64Atn)")
        }
        bus.driveAtnAck = newAck
    }

    func updateIRQ() {
        cpu.irqLine = (via1.ifr & VIA6522.IRQ.any != 0) || (via2.ifr & VIA6522.IRQ.any != 0)
    }

    func driveLog(_ msg: String) {
        let line = msg + "\n"
        let path = "/tmp/c64_debug.log"
        if let data = line.data(using: .utf8) {
            if let fh = FileHandle(forWritingAtPath: path) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }
}

// MARK: - Drive Memory Map

/// 1541 drive memory map implementing the Bus protocol.
public final class DriveMemoryMap: Bus {

    /// 2KB RAM (mirrored through $0000-$07FF)
    public var ram = [UInt8](repeating: 0, count: 2048)

    /// 16KB ROM ($C000-$FFFF)
    public var rom = [UInt8](repeating: 0, count: 16384)

    /// VIA chip references
    weak var via1: VIA6522?
    weak var via2: VIA6522?

    public init() {}

    public func read(_ address: UInt16) -> UInt8 {
        let addr = Int(address)

        switch addr {
        case 0x0000...0x07FF:
            return ram[addr]

        case 0x0800...0x0FFF:
            return ram[addr & 0x07FF]  // RAM mirror

        case 0x1800...0x180F:
            return via1?.readRegister(address & 0x0F) ?? 0

        case 0x1810...0x1BFF:
            return via1?.readRegister(address & 0x0F) ?? 0  // VIA1 mirrors

        case 0x1C00...0x1C0F:
            return via2?.readRegister(address & 0x0F) ?? 0

        case 0x1C10...0x1FFF:
            return via2?.readRegister(address & 0x0F) ?? 0  // VIA2 mirrors

        case 0xC000...0xFFFF:
            return rom[addr - 0xC000]

        default:
            return 0  // Unmapped regions
        }
    }

    public func write(_ address: UInt16, value: UInt8) {
        let addr = Int(address)

        switch addr {
        case 0x0000...0x07FF:
            ram[addr] = value

        case 0x0800...0x0FFF:
            ram[addr & 0x07FF] = value  // RAM mirror

        case 0x1800...0x180F:
            via1?.writeRegister(address & 0x0F, value: value)

        case 0x1810...0x1BFF:
            via1?.writeRegister(address & 0x0F, value: value)

        case 0x1C00...0x1C0F:
            via2?.writeRegister(address & 0x0F, value: value)

        case 0x1C10...0x1FFF:
            via2?.writeRegister(address & 0x0F, value: value)

        default:
            break  // ROM and unmapped — writes ignored
        }
    }
}
