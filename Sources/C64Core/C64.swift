import Foundation
import Emu6502

/// Complete C64 machine emulation.
/// Orchestrates CPU, VIC-II, SID, CIAs, and memory.
public final class C64 {

    // MARK: - Components

    public let cpu: CPU6502
    public let memory: MemoryMap
    public let vic: VIC
    public let sid: SID
    public let cia1: CIA
    public let cia2: CIA
    public let keyboard: Keyboard
    public let joystick: Joystick
    public let diskDrive: DiskDrive
    public let tapeUnit: TapeUnit
    public let kernalTraps: KernalTraps
    public let debugger: Debugger
    public let drive1541: Drive1541
    public let iecBus: IECBus

    /// Toggle between true drive emulation and Kernal trap mode.
    /// When true, the 1541 CPU runs and serial bus communication is used.
    /// When false, disk access is handled via Kernal traps (faster but less compatible).
    public var trueDriveEmulation: Bool = false

    /// Fractional clock accumulator for drive timing (1541 runs slightly faster than C64)
    var driveClockAccumulator: Double = 0.0
    /// Fraction of extra drive cycles per C64 cycle: (1000000 - 985248) / 985248
    let driveClockFraction: Double = 14752.0 / 985248.0

    // MARK: - State

    /// Whether the machine is running
    public var running: Bool = false

    /// Cycle counter within the current rasterline
    var lineCycle: Int = 0

    // MARK: - Init

    public init() {
        memory = MemoryMap()
        cpu = CPU6502(bus: memory)
        vic = VIC()
        sid = SID()
        cia1 = CIA(isCIA1: true)
        cia2 = CIA(isCIA1: false)
        keyboard = Keyboard()
        joystick = Joystick()
        diskDrive = DiskDrive()
        tapeUnit = TapeUnit()
        kernalTraps = KernalTraps()
        debugger = Debugger()
        drive1541 = Drive1541()
        iecBus = IECBus()

        // Debugger wiring
        debugger.cpu = cpu
        debugger.memory = memory
        memory.debugger = debugger

        // 1541 drive wiring
        drive1541.iecBus = iecBus

        // Wire up chip references
        memory.vic = vic
        memory.sid = sid
        memory.cia1 = cia1
        memory.cia2 = cia2

        // VIC memory access through the memory map
        vic.readMemory = { [weak self] address in
            self?.memory.vicRead(address) ?? 0
        }

        // VIC color RAM access
        vic.readColorRAM = { [weak self] address in
            self?.memory.colorRAM[Int(address & 0x03FF)] ?? 0
        }

        // CIA1 → CPU IRQ
        cia1.onInterrupt = { [weak self] active in
            self?.updateIRQ()
        }

        // CIA2 → CPU NMI
        cia2.onInterrupt = { [weak self] active in
            if active {
                self?.cpu.triggerNMI()
            }
        }

        // VIC → CPU IRQ
        vic.onIRQ = { [weak self] active in
            self?.updateIRQ()
        }

        // CIA2 → IEC bus
        cia2.onPortAWrite = { [weak self] portA in
            self?.iecBus.updateFromC64(portA)
        }
        cia2.readPortAExternal = { [weak self] in
            guard let self = self else { return 0xFF }
            var result: UInt8 = 0x3F  // Bits 0-5 default high (input pull-up)
            if !self.iecBus.c64ClkIn { result |= 0x40 }   // CLK high → bit 6 = 1
            if !self.iecBus.c64DataIn { result |= 0x80 }   // DATA high → bit 7 = 1
            return result
        }

        // Keyboard → CIA1
        keyboard.cia = cia1

        // Kernal traps wiring
        kernalTraps.cpu = cpu
        kernalTraps.memory = memory
        kernalTraps.diskDrive = diskDrive
        kernalTraps.tapeUnit = tapeUnit
    }

    // MARK: - ROM loading

    /// Load ROMs from file paths.
    public func loadROMs(basicPath: String, kernalPath: String, charsetPath: String) throws {
        let basic = try Data(contentsOf: URL(fileURLWithPath: basicPath))
        let kernal = try Data(contentsOf: URL(fileURLWithPath: kernalPath))
        let charset = try Data(contentsOf: URL(fileURLWithPath: charsetPath))
        memory.loadROMs(basic: basic, kernal: kernal, charset: charset)
    }

    /// Load ROMs from Data objects.
    public func loadROMs(basic: Data, kernal: Data, charset: Data) {
        memory.loadROMs(basic: basic, kernal: kernal, charset: charset)
    }

    /// Load 1541 drive ROM (16KB).
    public func loadDriveROM(_ data: Data) {
        drive1541.loadROM(data)
    }

    // MARK: - Media loading

    /// Mount a D64 disk image.
    public func mountDisk(_ url: URL) -> Bool {
        let result = diskDrive.mountFromFile(url)

        // Also load into the 1541's GCR disk for true drive emulation
        if let data = try? Data(contentsOf: url) {
            let ext = url.pathExtension.lowercased()
            if ext == "g64" {
                _ = drive1541.insertDisk(data, isG64: true)
            } else {
                _ = drive1541.insertDisk(data, isG64: false)
            }
        }

        return result
    }

    /// Mount a D64 disk image from data.
    public func mountDisk(_ data: Data) -> Bool {
        let result = diskDrive.mount(data)
        _ = drive1541.insertDisk(data, isG64: false)
        return result
    }

    /// Mount a T64/TAP tape image.
    public func mountTape(_ url: URL) -> Bool {
        return tapeUnit.mountFromFile(url)
    }

    /// Load a PRG file directly into RAM.
    /// If autoRun is true, types RUN + RETURN after loading.
    public func loadPRG(_ url: URL, autoRun: Bool = false) {
        guard let prg = PRGLoader.loadFromFile(url) else { return }
        kernalTraps.injectPRG(prg, memory: memory)

        if autoRun {
            // Type RUN\r into the keyboard buffer
            typeText("RUN\r")
        }
    }

    /// Load a PRG from data.
    public func loadPRG(_ data: Data, autoRun: Bool = false) {
        guard let prg = PRGLoader.parse(data) else { return }
        kernalTraps.injectPRG(prg, memory: memory)

        if autoRun {
            typeText("RUN\r")
        }
    }

    /// Type text into the C64 keyboard buffer.
    public func typeText(_ text: String) {
        // The C64 keyboard buffer is at $0277-$0280 (10 bytes max)
        // Buffer length is at $00C6
        let bufferAddr = 0x0277
        let bufferLenAddr = 0x00C6
        let maxLen = 10

        let chars = Array(text.prefix(maxLen))
        for (i, char) in chars.enumerated() {
            memory.ram[bufferAddr + i] = charToPetscii(char)
        }
        memory.ram[bufferLenAddr] = UInt8(chars.count)
    }

    func charToPetscii(_ char: Character) -> UInt8 {
        guard let ascii = char.asciiValue else { return 0x20 }
        switch ascii {
        case 0x0D: return 0x0D  // Return
        case 0x20...0x40: return ascii
        case 0x41...0x5A: return ascii  // Uppercase
        case 0x61...0x7A: return ascii - 32  // lowercase → uppercase PETSCII
        default: return 0x20
        }
    }

    // MARK: - Power on / Reset

    public func powerOn() {
        // Initialize RAM with typical power-on pattern
        for i in stride(from: 0, to: 0x10000, by: 128) {
            for j in 0..<64 {
                if i + j < 0x10000 {
                    memory.ram[i + j] = 0x00
                }
            }
            for j in 64..<128 {
                if i + j < 0x10000 {
                    memory.ram[i + j] = 0xFF
                }
            }
        }

        // Set default CPU port
        memory.portDirection = 0x2F
        memory.portData = 0x37

        // Reset CPU
        cpu.powerOn()
        running = true

        // Power on 1541 drive if ROM is loaded
        if trueDriveEmulation {
            // Sync bus state from current CIA2 output
            iecBus.updateFromC64(cia2.portAOut)
            drive1541.powerOn()
        }
    }

    public func reset() {
        cpu.reset()
    }

    // MARK: - Execution

    /// Run one complete frame (312 rasterlines × 63 cycles = 19656 cycles).
    /// Returns true when a frame is ready for display.
    public func runFrame() -> Bool {
        vic.frameReady = false

        while !vic.frameReady {
            if debugger.paused { return false }
            tickOneCycle()
        }

        return true
    }

    /// Run a single system clock cycle.
    func tickOneCycle() {
        // At instruction boundaries: trace, check traps and breakpoints
        if cpu.cycle == 0 {
            debugger.traceInstruction()
            if !debugger.checkBreakpoint() { return }
            // Only use Kernal traps when true drive emulation is off
            if !trueDriveEmulation {
                _ = kernalTraps.checkTrap()
            }
        }

        // CPU tick
        cpu.tick()

        // VIC tick
        vic.tick()

        // CIA ticks
        cia1.tick()
        cia2.tick()

        // SID tick
        sid.tick()

        // Update joystick state on CIA1
        cia1.joystickPort2 = joystick.port2
        cia1.joystickPort1 = joystick.port1

        // 1541 drive tick (runs at ~1 MHz vs C64's ~985 kHz)
        if trueDriveEmulation && drive1541.enabled {
            drive1541.tick()
            // Extra ticks to compensate for clock difference
            driveClockAccumulator += driveClockFraction
            if driveClockAccumulator >= 1.0 {
                driveClockAccumulator -= 1.0
                drive1541.tick()
            }
        }
    }

    // MARK: - IRQ management

    func updateIRQ() {
        // IRQ is active if any source is asserting it
        cpu.irqLine = cia1.interruptActive || (vic.interruptRegister & 0x80 != 0)
    }
}
