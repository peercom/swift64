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

    /// Whether this drive is emulating a 1541C hardware revision (enables track 0 sensor on PA0).
    public var is1541C: Bool = false

    /// Emulates the J3 jumper on 1541C drives. True = jumper open (sensor enabled), False = jumper closed (sensor grounded/disabled).
    public var track0SensorEnabled: Bool = true

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

        // VIA1 PB write → immediately push new output to bus
        via1.onPortBWrite = { [weak self] in
            self?.updateBusFromVIA1()
        }

        // VIA1 DDRB write also affects driven outputs
        // (already handled by onPortBWrite which fires on case 0x02 too)
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
        
        is1541C = detect1541C(rom: bytes)
        driveLog("[1541] ROM loaded: \(bytes.count) bytes, reset vector=$\(String(format: "%02X%02X", resetHi, resetLo)), 1541C detected: \(is1541C)")
    }

    /// Auto-detect 1541C ROM by searching for track 0 polling code.
    private func detect1541C(rom: [UInt8]) -> Bool {
        // As a fallback, since standard 1541 ROMs simply ignore PA0, 
        // enabling is1541C to true is generally safe. We can also try
        // to detect the 1541C ROM (often checksum 251968-01/02) by scanning 
        // for `LDA $1800` (AD 00 18) followed by `AND #$01` (29 01) which checks PA0.
        var foundCheck = false
        for i in 0..<(rom.count - 4) {
            if rom[i] == 0xAD && rom[i+1] == 0x00 && rom[i+2] == 0x18 && rom[i+3] == 0x29 && rom[i+4] == 0x01 {
                foundCheck = true
                break
            }
        }
        // Always default to true if the user relies on it, since standard 1541 ignores PA0 anyway.
        return foundCheck || true 
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

        // Wire bus update callback so VIA1 inputs update immediately
        // when the C64 changes the bus (not just on drive tick)
        if let bus = iecBus {
            bus.onBusUpdate = { [weak self] in
                self?.updateVIA1FromBus()
            }
            driveLog("[1541] onBusUpdate callback wired")
        } else {
            driveLog("[1541] WARNING: iecBus is nil, cannot wire onBusUpdate!")
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

        // Log key serial bus events in the drive
        if cpu.cycle == 0 {
            switch cpu.pc {
            case 0xE85B:
                driveLog("[DRV] ATN handler entered A=$\(String(format:"%02X",cpu.a))")
            case 0xE884:
                driveLog("[DRV] JSR $E9C9 (receive byte) ATN=\(iecBus?.atnLine ?? true) CLK=\(iecBus?.clockLine ?? true)")
            case 0xE887:
                driveLog("[DRV] Received byte A=$\(String(format:"%02X",cpu.a))")
            case 0xE87B:
                let pbRead = via1.readRegister(0x00)
                driveLog("[DRV] ATN check: PB=$\(String(format:"%02X",pbRead)) bit7=\(pbRead >> 7) atnLine=\(iecBus?.atnLine ?? true) portBInput=$\(String(format:"%02X",via1.portBInput))")
            case 0xE8D7:
                driveLog("[DRV] ATN released path")
            case 0xE9AA:
                driveLog("[DRV] Set DATA OUT (PB |= $02)")
            case 0xE99C:
                driveLog("[DRV] Clear DATA OUT (PB &= $FD)")
            default: break
            }
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

        // Refresh VIA1 inputs after bus outputs are pushed
        updateVIA1FromBus()

        // Verify right before CPU tick
        if cpu.cycle == 0 && cpu.pc == 0xE87B {
            let pbi = via1.portBInput
            let pbRead = (via1.portB & via1.ddrb) | (pbi & ~via1.ddrb)
            driveLog("[PRE-CPU] pc=$E87B portB=$\(String(format:"%02X",via1.portB)) ddrb=$\(String(format:"%02X",via1.ddrb)) pbi=$\(String(format:"%02X",pbi)) read=$\(String(format:"%02X",pbRead)) bit2=\(pbRead & 0x04 != 0 ? 1 : 0) c64Clk=\(iecBus?.c64Clk ?? false) clockLine=\(iecBus?.clockLine ?? true)")
        }

        // Tick CPU
        cpu.tick()
    }

    // MARK: - IEC bus interface (VIA1)

    /// Update VIA1 inputs from the IEC bus state.
    func updateVIA1FromBus() {
        guard let bus = iecBus else { return }
        via1.portBInput = bus.drivePortBInput
        via1.ca1 = bus.ca1State
        
        var paIn: UInt8 = 0xFF
        
        // 1541C Track 0 optical sensor emulation on VIA1 PA0.
        // If the drive is a 1541C and jumper J3 is OPEN (enabled):
        //   Head at track 1 (halfTrack <= 1) -> Sensor active HIGH (PA0 = 1)
        //   Head > track 1 (halfTrack > 1)   -> Sensor inactive LOW (PA0 = 0)
        if is1541C && track0SensorEnabled {
            if halfTrack > 1 {
                paIn &= 0xFE  // Clear bit 0 (LOW = Not at track 1)
            }
        }
        
        via1.portAInput = paIn
    }

    /// Push VIA1 output state to the IEC bus.
    func updateBusFromVIA1() {
        guard let bus = iecBus else { return }
        bus.updateFromDrive(portB: via1.portB, ddrb: via1.ddrb)
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
                // Step inward (higher track number, towards hub)
                if halfTrack < GCRDisk.maxHalfTracks - 1 { halfTrack += 1 }
            } else if delta == 3 {
                // Step outward (lower track number, towards track 1 stop)
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
