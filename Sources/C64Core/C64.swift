import Foundation
import Emu6502

public enum TrueDriveEmulationMode: Equatable {
    case off
    case standard1541
    case compat1541

    public var displayName: String {
        switch self {
        case .off: return "Fast Load"
        case .standard1541: return "True Drive 1541"
        case .compat1541: return "True Drive 1541 Compat"
        }
    }
}

public enum C64ROMValidationError: Error, Equatable, LocalizedError {
    case invalidSize(name: String, expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidSize(name, expected, actual):
            return "\(name) ROM must be \(expected) bytes; got \(actual)."
        }
    }
}

/// Complete C64 machine emulation.
/// Orchestrates CPU, VIC-II, SID, CIAs, and memory.
public final class C64 {
    public static let basicROMSize = 8_192
    public static let kernalROMSize = 8_192
    public static let characterROMSize = 4_096
    public static let drive1541ROMSize = 16_384

    public struct EmulationStatus: Equatable {
        public let running: Bool
        public let trueDriveMode: TrueDriveEmulationMode
        public let cpuPC: UInt16
        public let cpuJammed: Bool
        public let totalCycles: UInt64
        public let mountedDiskName: String?
        public let mountedCartridgeName: String?
        public let mountedDiskFormat: DiskImage.Format?
        public let mediaCapabilities: DiskImage.Capabilities?
        public let drive: Drive1541.StatusSnapshot
        public let lastFailureReason: String?
    }

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

    /// Machine/chip timing profile. PAL C64 + 1541C is the default compatibility target.
    public var machineProfile: MachineProfile = .palC64 {
        didSet {
            applyMachineProfile()
        }
    }

    /// Selects between Kernal traps and hardware-level 1541 emulation.
    public var trueDriveEmulationMode: TrueDriveEmulationMode = .off {
        didSet {
            configureDriveForCurrentMode()
        }
    }

    /// Compatibility wrapper for older UI/tests.
    public var trueDriveEmulation: Bool {
        get { trueDriveEmulationMode != .off }
        set { trueDriveEmulationMode = newValue ? .compat1541 : .off }
    }

    /// Drive CPU clocks per C64 clock. PAL default: 1 MHz / 985248 Hz.
    public var driveClockRatio: Double = MachineProfile.palC64.standardDriveClockRatio

    /// Fractional clock accumulator for drive timing.
    var driveClockAccumulator: Double = 0.0
    /// Debug counter for CIA2 PA reads
    var cia2ReadLog: Int = 0

    // MARK: - State

    /// Whether the machine is running
    public var running: Bool = false
    /// RESTORE key input state. Pressing RESTORE raises a CPU NMI edge.
    public private(set) var restoreKeyDown: Bool = false

    /// Display name of the most recently mounted disk image, if any.
    public private(set) var mountedDiskName: String?

    /// Display name of the mounted cartridge image, if any.
    public private(set) var mountedCartridgeName: String?

    /// Last detected emulator failure/hang reason for diagnostics.
    public private(set) var lastFailureReason: String?

    private var pcFFFFCycleCount: UInt64 = 0
    private var loadNoProgressCycleCount: UInt64 = 0
    private var lastProgressSignature: UInt64 = 0
    private var lastFailureWasClearedAtCycle: UInt64 = 0
    private var pendingTypedText: [Character] = []

    /// Cycle counter within the current rasterline
    var lineCycle: Int = 0

    // MARK: - Init

    public init(machineProfile: MachineProfile = .palC64) {
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
            self?.cpu.setNMILine(high: active)
        }

        // VIC → CPU IRQ
        vic.onIRQ = { [weak self] active in
            self?.updateIRQ()
        }

        // CIA2 → IEC bus (only output-configured pins drive the bus)
        cia2.onPortAWrite = { [weak self] portA in
            guard let self = self else { return }
            self.iecBus.updateFromC64(portA, ddra: self.cia2.ddra)
        }
        cia2.readPortAExternal = { [weak self] in
            guard let self = self else { return 0xFF }
            let result = 0x3F | self.iecBus.c64ReadClk | self.iecBus.c64ReadData
            // Log reads in Kernal serial bus code regions
            if self.trueDriveEmulationMode != .off && self.cia2ReadLog < 500 {
                let pc = self.cpu.pc
                // Kernal serial routines: $ED00-$EEFF, also $F4-$F7 (LOAD/SAVE/OPEN)
                if (pc >= 0xED00 && pc <= 0xEEB5) || (pc >= 0xF49E && pc <= 0xF7FF) {
                    self.cia2ReadLog += 1
                    C64Trace.log(.iec, "[C64-RD] @\(self.cpu.totalCycles) PC=$\(String(format:"%04X",pc)) CIA2_PA=$\(String(format:"%02X",result)) ATN=\(self.iecBus.atnLine) CLK=\(self.iecBus.clockLine) DATA=\(self.iecBus.dataLine) [c64: atn=\(self.iecBus.c64Atn) clk=\(self.iecBus.c64Clk) data=\(self.iecBus.c64Data)] [drv: clk=\(self.iecBus.driveClk) data=\(self.iecBus.driveData) atn=\(self.iecBus.driveAtn)]")
                }
            }
            return result
        }

        // Keyboard → CIA1
        keyboard.cia = cia1

        // Kernal traps wiring
        kernalTraps.cpu = cpu
        kernalTraps.memory = memory
        kernalTraps.diskDrive = diskDrive
        kernalTraps.tapeUnit = tapeUnit

        self.machineProfile = machineProfile
        applyMachineProfile()
    }

    func applyMachineProfile() {
        vic.videoStandard = machineProfile.videoStandard
        sid.model = machineProfile.sidModel
        sid.clockRate = machineProfile.sidClockHz
        cia1.configureTOD(
            fiftyHzCyclesPerTenth: machineProfile.ciaTod50HzCyclesPerTenth,
            sixtyHzCyclesPerTenth: machineProfile.ciaTod60HzCyclesPerTenth,
            selectedCyclesPerTenth: machineProfile.ciaTodCyclesPerTenth
        )
        cia2.configureTOD(
            fiftyHzCyclesPerTenth: machineProfile.ciaTod50HzCyclesPerTenth,
            sixtyHzCyclesPerTenth: machineProfile.ciaTod60HzCyclesPerTenth,
            selectedCyclesPerTenth: machineProfile.ciaTodCyclesPerTenth
        )
        configureDriveForCurrentMode()
    }

    func configureDriveForCurrentMode() {
        switch trueDriveEmulationMode {
        case .off:
            drive1541.enabled = false
        case .standard1541:
            driveClockAccumulator = 0
            drive1541.driveModel = .model1541
            driveClockRatio = machineProfile.standardDriveClockRatio
        case .compat1541:
            driveClockAccumulator = 0
            drive1541.driveModel = machineProfile.driveModel
            driveClockRatio = 1.0
        }
    }

    // MARK: - ROM loading

    /// Load ROMs from file paths.
    public func loadROMs(basicPath: String, kernalPath: String, charsetPath: String) throws {
        let basic = try Data(contentsOf: URL(fileURLWithPath: basicPath))
        let kernal = try Data(contentsOf: URL(fileURLWithPath: kernalPath))
        let charset = try Data(contentsOf: URL(fileURLWithPath: charsetPath))
        try loadROMsValidated(basic: basic, kernal: kernal, charset: charset)
    }

    /// Load ROMs from Data objects.
    public func loadROMs(basic: Data, kernal: Data, charset: Data) {
        memory.loadROMs(basic: basic, kernal: kernal, charset: charset)
    }

    /// Load ROMs after validating expected stock C64 ROM sizes.
    public func loadROMsValidated(basic: Data, kernal: Data, charset: Data) throws {
        try validateROMSize(basic, name: "BASIC", expected: Self.basicROMSize)
        try validateROMSize(kernal, name: "Kernal", expected: Self.kernalROMSize)
        try validateROMSize(charset, name: "Character", expected: Self.characterROMSize)
        loadROMs(basic: basic, kernal: kernal, charset: charset)
    }

    /// Load 1541 drive ROM (16KB).
    public func loadDriveROM(_ data: Data) {
        drive1541.loadROM(data)
    }

    /// Load 1541 drive ROM after validating the expected 16KB size.
    public func loadDriveROMValidated(_ data: Data) throws {
        try validateROMSize(data, name: "1541 drive", expected: Self.drive1541ROMSize)
        loadDriveROM(data)
    }

    private func validateROMSize(_ data: Data, name: String, expected: Int) throws {
        guard data.count == expected else {
            throw C64ROMValidationError.invalidSize(name: name, expected: expected, actual: data.count)
        }
    }

    public var mountedDiskImage: DiskImage? {
        drive1541.disk.image
    }

    public var mountedDiskIsLowLevelCapable: Bool {
        drive1541.disk.hasNativeLowLevelImage
    }

    public var emulationStatus: EmulationStatus {
        EmulationStatus(
            running: running,
            trueDriveMode: trueDriveEmulationMode,
            cpuPC: cpu.pc,
            cpuJammed: cpu.jammed,
            totalCycles: cpu.totalCycles,
            mountedDiskName: mountedDiskName,
            mountedCartridgeName: mountedCartridgeName,
            mountedDiskFormat: mountedDiskImage?.format,
            mediaCapabilities: mountedDiskImage?.capabilities,
            drive: drive1541.statusSnapshot,
            lastFailureReason: lastFailureReason ?? drive1541.lastFailureReason
        )
    }

    // MARK: - Media loading

    /// Mount a D64 disk image.
    public func mountDisk(_ url: URL) -> Bool {
        let highLevelResult = diskDrive.mountFromFile(url)
        var lowLevelResult = false

        // Also load into the 1541's GCR disk for true drive emulation
        if let data = try? Data(contentsOf: url) {
            let ext = url.pathExtension.lowercased()
            if ext == "g64" {
                lowLevelResult = drive1541.insertDisk(data, isG64: true)
            } else {
                lowLevelResult = drive1541.insertDisk(data, isG64: false)
            }
        }

        if highLevelResult || lowLevelResult {
            mountedDiskName = url.lastPathComponent
            clearFailureStatus()
        }
        return highLevelResult || lowLevelResult
    }

    /// Mount a D64 disk image from data.
    public func mountDisk(_ data: Data) -> Bool {
        let result = diskDrive.mount(data)
        let lowLevelResult = drive1541.insertDisk(data, isG64: false)
        if result || lowLevelResult {
            mountedDiskName = "memory.d64"
            clearFailureStatus()
        }
        return result || lowLevelResult
    }

    /// Mount a T64/TAP tape image.
    public func mountTape(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return mountTape(data)
    }

    /// Mount a T64/TAP tape image from data.
    @discardableResult
    public func mountTape(_ data: Data) -> Bool {
        guard tapeUnit.mount(data) else { return false }
        prepareMountedTape()
        clearFailureStatus()
        return true
    }

    public func unmountTape() {
        tapeUnit.unmount()
        memory.cassetteSenseLineHigh = true
        cia1.setFlagLine(high: true)
        clearFailureStatus()
    }

    func prepareMountedTape() {
        memory.cassetteSenseLineHigh = true
        cia1.setFlagLine(high: true)

        if tapeUnit.format == .tap && tapeUnit.startRawPlayback() {
            memory.cassetteSenseLineHigh = false
        }
    }

    /// Mount a CRT cartridge image.
    @discardableResult
    public func mountCartridge(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        if mountCartridge(data) {
            mountedCartridgeName = url.lastPathComponent
            return true
        }
        return false
    }

    /// Mount a CRT cartridge image from data.
    @discardableResult
    public func mountCartridge(_ data: Data) -> Bool {
        guard let cartridge = Cartridge.parseCRT(data) else { return false }
        memory.cartridge = cartridge
        mountedCartridgeName = cartridge.name
        clearFailureStatus()
        return true
    }

    public func unmountCartridge() {
        memory.cartridge = nil
        mountedCartridgeName = nil
        clearFailureStatus()
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
        clearFailureStatus()
    }

    /// Load a PRG from data.
    public func loadPRG(_ data: Data, autoRun: Bool = false) {
        guard let prg = PRGLoader.parse(data) else { return }
        kernalTraps.injectPRG(prg, memory: memory)

        if autoRun {
            typeText("RUN\r")
        }
        clearFailureStatus()
    }

    /// Type text into the C64 keyboard buffer.
    public func typeText(_ text: String) {
        pendingTypedText.append(contentsOf: text)
        feedKeyboardBufferIfPossible()
    }

    @discardableResult
    public func pressRestoreKey() -> Bool {
        guard !restoreKeyDown else { return false }
        restoreKeyDown = true
        cpu.triggerNMI()
        return true
    }

    public func releaseRestoreKey() {
        restoreKeyDown = false
    }

    private func feedKeyboardBufferIfPossible() {
        guard !pendingTypedText.isEmpty else { return }
        guard memory.ram[0x00C6] == 0 else { return }

        // The C64 keyboard buffer is at $0277-$0280 (10 bytes max)
        // Buffer length is at $00C6
        let bufferAddr = 0x0277
        let bufferLenAddr = 0x00C6
        let maxLen = 10

        let chars = Array(pendingTypedText.prefix(maxLen))
        for (i, char) in chars.enumerated() {
            memory.ram[bufferAddr + i] = charToPetscii(char)
        }
        memory.ram[bufferLenAddr] = UInt8(chars.count)
        pendingTypedText.removeFirst(chars.count)
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
        clearFailureStatus()

        // Power on 1541 drive if ROM is loaded
        if trueDriveEmulationMode != .off {
            // Sync bus state from current CIA2 output (respecting DDR)
            iecBus.updateFromC64(cia2.portA, ddra: cia2.ddra)
            drive1541.powerOn()
        }
    }

    public func reset() {
        cpu.reset()
        clearFailureStatus()
    }

    // MARK: - Execution

    /// Run one complete frame for the active VIC-II video standard.
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
        let cpuStalledByVIC = vic.isStealingCPU

        // At instruction boundaries: trace, check traps and breakpoints
        if !cpuStalledByVIC && cpu.cycle == 0 {
            debugger.traceInstruction()
            if !debugger.checkBreakpoint() { return }
            if trueDriveEmulationMode == .off {
                _ = kernalTraps.checkTrap()
            }
        }

        monitorCPUFailureState()
        feedKeyboardBufferIfPossible()

        if !cpuStalledByVIC {
            cpu.tick()
        }

        // VIC tick
        vic.tick()

        // CIA ticks
        cia1.tick()
        cia2.tick()

        // SID tick
        sid.tick()

        updateTapeSignal()

        // Update joystick state on CIA1
        cia1.joystickPort2 = joystick.port2
        cia1.joystickPort1 = joystick.port1

        // 1541 drive ticks AFTER C64 — it sees the bus state the C64 just wrote.
        // The drive's VIA1 inputs are updated at the start of its tick().
        if trueDriveEmulationMode != .off && drive1541.enabled {
            driveClockAccumulator += driveClockRatio
            if driveClockAccumulator >= 1.0 {
                while driveClockAccumulator >= 1.0 {
                    driveClockAccumulator -= 1.0
                    drive1541.tick()
                }
            }
        }

        monitorEmulationProgress()
    }

    func updateTapeSignal() {
        guard tapeUnit.rawPlaybackActive else {
            cia1.setFlagLine(high: true)
            return
        }

        if memory.cassetteMotorEnabled {
            tapeUnit.tickRawPlayback()
        }

        cia1.setFlagLine(high: tapeUnit.readSignalHigh)
    }

    private func clearFailureStatus() {
        lastFailureReason = nil
        drive1541.lastFailureReason = nil
        drive1541.noProgressCycleCount = 0
        pcFFFFCycleCount = 0
        loadNoProgressCycleCount = 0
        lastProgressSignature = progressSignature
        lastFailureWasClearedAtCycle = cpu.totalCycles
    }

    private func monitorEmulationProgress() {
        monitorCPUFailureState()

        guard trueDriveEmulationMode != .off, drive1541.enabled, isLoadActivityLikely else {
            loadNoProgressCycleCount = 0
            drive1541.noProgressCycleCount = 0
            lastProgressSignature = progressSignature
            return
        }

        let currentSignature = progressSignature
        if currentSignature == lastProgressSignature {
            loadNoProgressCycleCount += 1
        } else {
            loadNoProgressCycleCount = 0
            lastProgressSignature = currentSignature
        }

        drive1541.noProgressCycleCount = loadNoProgressCycleCount
        if loadNoProgressCycleCount > 1_500_000 {
            recordFailure("No IEC/GCR progress during true-drive LOAD")
        }
    }

    private func monitorCPUFailureState() {
        if cpu.jammed {
            recordFailure("C64 CPU JAM/KIL at $\(hex16(cpu.pc))")
            return
        }
        if drive1541.cpu.jammed {
            recordFailure("1541 CPU JAM/KIL at $\(hex16(drive1541.cpu.pc))")
            return
        }

        if cpu.pc == 0xFFFF {
            pcFFFFCycleCount += 1
            if pcFFFFCycleCount > 20_000 {
                recordFailure("C64 PC stuck at $FFFF")
            }
        }
    }

    private var isLoadActivityLikely: Bool {
        let pc = cpu.pc
        let inKernalSerial = (pc >= 0xED00 && pc <= 0xEEFF) || (pc >= 0xF49E && pc <= 0xF7FF)
        return inKernalSerial || drive1541.motorOn || drive1541.ledOn
    }

    private var progressSignature: UInt64 {
        var value = UInt64(cpu.pc)
        value = value &* 1099511628211 &+ UInt64(cpu.cycle)
        value = value &* 1099511628211 &+ drive1541.progressSignature
        value = value &* 1099511628211 &+ UInt64(memory.ram[0x90])
        value = value &* 1099511628211 &+ UInt64(memory.ram[0xAE])
        value = value &* 1099511628211 &+ UInt64(memory.ram[0xAF])
        return value
    }

    private func recordFailure(_ reason: String) {
        guard cpu.totalCycles >= lastFailureWasClearedAtCycle else { return }
        if lastFailureReason == nil {
            lastFailureReason = reason
            drive1541.lastFailureReason = reason
        }
    }

    private func hex16(_ value: UInt16) -> String {
        String(format: "%04X", value)
    }

    // MARK: - IRQ management

    func updateIRQ() {
        // IRQ is active if any source is asserting it
        cpu.irqLine = cia1.interruptActive || (vic.interruptRegister & 0x80 != 0)
    }
}
