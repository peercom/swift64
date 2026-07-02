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
        public let mountedTapeName: String?
        public let mountedCartridgeName: String?
        public let mountedDiskFormat: DiskImage.Format?
        public let highLevelDiskFormat: DiskImage.Format?
        public let diskHasUnsavedChanges: Bool
        public let highLevelDiskWriteProtected: Bool
        public let canExportModifiedD64: Bool
        public let canExportModifiedG64: Bool
        public let d64ExportBlockedByLowLevelWrites: Bool
        public let tapeHasCapturedWritePulses: Bool
        public let canExportCapturedTAP: Bool
        public let tapeHasUnsavedChanges: Bool
        public let canExportSavedT64: Bool
        public let tapeDecodeStatus: TapeUnit.TAPDecodeStatus
        public let tapeRawPlaybackActive: Bool
        public let tapeReadSignalHigh: Bool
        public let cassetteSenseLineHigh: Bool
        public let cassetteMotorEnabled: Bool
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

    /// Optional SID chip override for compatibility runs and app preferences.
    /// When nil, the active machine profile selects the SID model.
    public var sidModelOverride: SID.Model? {
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

    /// Display name of the mounted tape image, if any.
    public private(set) var mountedTapeName: String?

    /// Display name of the mounted cartridge image, if any.
    public private(set) var mountedCartridgeName: String?

    /// Last detected emulator failure/hang reason for diagnostics.
    public private(set) var lastFailureReason: String?

    /// Count of CPU writes that reached the SID register window.
    public private(set) var sidChipWriteCount: UInt64 = 0

    /// Count of CPU writes to $D400-$D7FF while RAM/ROM was banked in instead of SID I/O.
    public private(set) var sidRAMWindowWriteCount: UInt64 = 0

    /// Per-register histogram of CPU writes that reached the SID chip.
    public private(set) var sidChipRegisterWriteCounts = [UInt64](repeating: 0, count: 32)

    /// Per-register histogram of CPU writes to $D400-$D7FF while SID I/O was banked out.
    public private(set) var sidRAMWindowRegisterWriteCounts = [UInt64](repeating: 0, count: 32)

    /// Optional clean-room SID write stream hook for local audio reference captures.
    public var onSIDRegisterWriteTrace: ((SIDRegisterWriteTraceEvent) -> Void)?

    private var pcFFFFCycleCount: UInt64 = 0
    private var loadNoProgressCycleCount: UInt64 = 0
    private var lastProgressSignature: UInt64 = 0
    private var lastFailureWasClearedAtCycle: UInt64 = 0
    private var pendingTypedText: [Character] = []
    private var sidTraceWriteCount = 0
    private let sidTraceWriteLimit = C64.sidTraceLimitFromEnvironment()
    private let machineLock = NSLock()

    /// Cycle counter within the current rasterline
    var lineCycle: Int = 0

    // MARK: - Init

    public init(machineProfile: MachineProfile = .palC64) {
        memory = MemoryMap()
        cpu = CPU6502(bus: memory)
        vic = VIC()
        sid = SID()
        sid.continuousPaddleScanEnabled = true
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
        diskDrive.onD64ImageChanged = { [weak self] data in
            self?.refreshTrueDriveD64Image(afterHighLevelMutation: data)
        }

        // Wire up chip references
        memory.vic = vic
        memory.sid = sid
        memory.cia1 = cia1
        memory.cia2 = cia2
        memory.onSIDRegisterWrite = { [weak self] register, value in
            guard let self else { return }
            self.sidChipWriteCount += 1
            self.sidChipRegisterWriteCounts[Int(register & 0x1F)] += 1
            self.onSIDRegisterWriteTrace?(self.sidRegisterWriteTraceEvent(
                register: register,
                value: value,
                reachedChip: true
            ))
            self.traceSIDRegisterWrite(register: register, value: value, reachedChip: true)
        }
        memory.onBankedOutSIDAddressWrite = { [weak self] register, value in
            guard let self else { return }
            self.sidRAMWindowWriteCount += 1
            self.sidRAMWindowRegisterWriteCounts[Int(register & 0x1F)] += 1
            self.onSIDRegisterWriteTrace?(self.sidRegisterWriteTraceEvent(
                register: register,
                value: value,
                reachedChip: false
            ))
            self.traceSIDRegisterWrite(register: register, value: value, reachedChip: false)
        }

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
            self?.updateNMI()
        }

        // Expansion-port cartridges can drive NMI too.
        memory.onCartridgeNMIChange = { [weak self] _ in
            self?.updateNMI()
        }

        // CPU port cassette outputs → datasette write capture.
        memory.onCassetteWriteLineChange = { [weak self] high in
            guard let self = self else { return }
            self.tapeUnit.observeCassetteWriteLine(
                high: high,
                atCycle: self.cpu.totalCycles,
                motorEnabled: self.memory.cassetteMotorEnabled
            )
        }
        memory.onCassetteMotorLineChange = { [weak self] _ in
            guard let self = self else { return }
            self.tapeUnit.observeCassetteMotor(enabled: self.memory.cassetteMotorEnabled)
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
        sid.model = sidModelOverride ?? machineProfile.sidModel
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
        configureDriveForCurrentMode()
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

    public var exportedD64Image: Data? {
        guard !drive1541.hasPendingGCRWriteGateSplice else {
            return nil
        }
        if drive1541.disk.hasUnsavedLowLevelWrites,
           !synchronizeLowLevelD64WritesIfPossible() {
            return nil
        }
        return diskDrive.exportedD64Image
    }

    public var exportedG64Image: Data? {
        drive1541.exportedG64Image()
    }

    private var canExportD64ImageWithoutSynchronizing: Bool {
        guard diskDrive.mountedFormat == .d64,
              !drive1541.hasPendingGCRWriteGateSplice else {
            return false
        }

        guard drive1541.disk.hasUnsavedLowLevelWrites else {
            return diskDrive.exportedD64Image != nil
        }

        guard let baseImage = diskDrive.exportedD64Image,
              let decoded = drive1541.disk.decodedD64Image(
                patching: baseImage,
                refreshingMetadata: false
              ) else {
            return false
        }
        return decoded.changedSectorCount > 0
    }

    @discardableResult
    private func refreshTrueDriveD64Image(afterHighLevelMutation data: Data) -> Bool {
        guard diskDrive.mountedFormat == .d64,
              drive1541.insertDisk(data, isG64: false) else {
            return false
        }
        drive1541.setWriteProtected(diskDrive.isWriteProtected)
        return true
    }

    @discardableResult
    private func synchronizeLowLevelD64WritesIfPossible() -> Bool {
        guard diskDrive.mountedFormat == .d64,
              !drive1541.hasPendingGCRWriteGateSplice,
              drive1541.disk.hasUnsavedLowLevelWrites,
              let baseImage = diskDrive.exportedD64Image,
              let decoded = drive1541.disk.decodedD64Image(patching: baseImage),
              decoded.changedSectorCount > 0,
              diskDrive.replaceMountedD64ImageAfterLowLevelWrite(decoded.image, notifyChange: false),
              refreshTrueDriveD64Image(afterHighLevelMutation: decoded.image) else {
            return false
        }

        drive1541.disk.markLowLevelWritesSaved()
        return true
    }

    @discardableResult
    public func markExportedD64ImageSaved() -> Bool {
        guard diskDrive.mountedFormat == .d64,
              !drive1541.hasPendingGCRWriteGateSplice else {
            return false
        }
        if drive1541.disk.hasUnsavedLowLevelWrites,
           !synchronizeLowLevelD64WritesIfPossible() {
            return false
        }
        diskDrive.markChangesSaved()
        return true
    }

    @discardableResult
    public func markExportedG64ImageSaved() -> Bool {
        drive1541.markExportedG64ImageSaved()
    }

    public func setMountedDiskWriteProtected(_ protected: Bool) {
        diskDrive.setWriteProtected(protected)
        drive1541.setWriteProtected(protected)
    }

    public func exportedCapturedTAPImage(version: UInt8 = 1) -> Data? {
        tapeUnit.capturedWriteTAP(version: version)
    }

    public func clearCapturedTapeWritePulses() {
        tapeUnit.clearWriteCapture()
    }

    public var exportedT64Image: Data? {
        tapeUnit.exportedT64Image
    }

    public func markExportedT64ImageSaved() {
        tapeUnit.markChangesSaved()
    }

    public var emulationStatus: EmulationStatus {
        let canExportD64Image = canExportD64ImageWithoutSynchronizing
        let d64ExportBlockedByLowLevelWrites = diskDrive.mountedFormat == .d64
            && drive1541.disk.hasUnsavedLowLevelWrites
            && !canExportD64Image
        return EmulationStatus(
            running: running,
            trueDriveMode: trueDriveEmulationMode,
            cpuPC: cpu.pc,
            cpuJammed: cpu.jammed,
            totalCycles: cpu.totalCycles,
            mountedDiskName: mountedDiskName,
            mountedTapeName: effectiveMountedTapeName,
            mountedCartridgeName: mountedCartridgeName,
            mountedDiskFormat: mountedDiskImage?.format,
            highLevelDiskFormat: diskDrive.mountedFormat,
            diskHasUnsavedChanges: diskDrive.hasUnsavedChanges
                || drive1541.disk.hasUnsavedLowLevelWrites
                || drive1541.hasPendingGCRWriteGateSplice,
            highLevelDiskWriteProtected: diskDrive.isWriteProtected,
            canExportModifiedD64: canExportD64Image,
            canExportModifiedG64: drive1541.disk.exportedG64Image != nil,
            d64ExportBlockedByLowLevelWrites: d64ExportBlockedByLowLevelWrites,
            tapeHasCapturedWritePulses: !tapeUnit.writePulses.isEmpty,
            canExportCapturedTAP: tapeUnit.capturedWriteTAP() != nil,
            tapeHasUnsavedChanges: tapeUnit.hasUnsavedChanges,
            canExportSavedT64: tapeUnit.exportedT64Image != nil,
            tapeDecodeStatus: tapeUnit.tapDecodeStatus,
            tapeRawPlaybackActive: tapeUnit.rawPlaybackActive,
            tapeReadSignalHigh: tapeUnit.readSignalHigh,
            cassetteSenseLineHigh: memory.cassetteSenseLineHigh,
            cassetteMotorEnabled: memory.cassetteMotorEnabled,
            mediaCapabilities: mountedDiskImage?.capabilities,
            drive: drive1541.statusSnapshot,
            lastFailureReason: lastFailureReason ?? drive1541.lastFailureReason
        )
    }

    // MARK: - Media loading

    /// Mount a D64, G64, NIB, or NBZ disk image.
    public func mountDisk(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return mountDisk(data, fileName: url.lastPathComponent)
    }

    /// Mount a disk image from data, using the filename extension and known
    /// low-level signatures to detect D64, G64, NIB, NBZ, or P64.
    public func mountDisk(_ data: Data, fileName: String) -> Bool {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let format: DiskImage.Format
        if ext == "g64" || (ext != "d64" && data.starts(with: Array("GCR-1541".utf8))) {
            format = .g64
        } else if ext == "nib" || (ext != "d64" && data.starts(with: Array("MNIB-1541-RAW".utf8))) {
            format = .nib
        } else if ext == "nbz" {
            format = .nbz
        } else if ext == "p64" || (ext != "d64" && data.starts(with: Array("P64-1541".utf8))) {
            format = .p64
        } else {
            format = .d64
        }

        let highLevelResult: Bool
        switch format {
        case .d64:
            highLevelResult = diskDrive.mount(data)
        case .g64:
            highLevelResult = diskDrive.mountG64(data)
        case .nib:
            highLevelResult = false
        case .nbz:
            highLevelResult = false
        case .p64:
            highLevelResult = false
        }
        var lowLevelResult = false

        // Also load into the 1541's GCR disk for true drive emulation.
        lowLevelResult = drive1541.insertDisk(data, format: format)
        if lowLevelResult {
            drive1541.setWriteProtected(highLevelResult ? diskDrive.isWriteProtected : drive1541.disk.writeProtected)
        }

        if highLevelResult && !lowLevelResult {
            drive1541.ejectDisk()
        } else if !highLevelResult && lowLevelResult {
            diskDrive.unmount()
        }

        if highLevelResult || lowLevelResult {
            mountedDiskName = fileName
            clearFailureStatus()
        }
        return highLevelResult || lowLevelResult
    }

    /// Mount a D64 disk image from data.
    public func mountDisk(_ data: Data) -> Bool {
        mountDisk(data, fileName: "memory.d64")
    }

    /// Mount a T64/TAP tape image.
    public func mountTape(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return mountTape(data, fileName: url.lastPathComponent)
    }

    /// Mount a T64/TAP tape image from data.
    @discardableResult
    public func mountTape(_ data: Data, fileName: String? = nil) -> Bool {
        guard tapeUnit.mount(data) else { return false }
        mountedTapeName = fileName ?? defaultTapeName(for: tapeUnit.format)
        prepareMountedTape()
        clearFailureStatus()
        return true
    }

    public func unmountTape() {
        tapeUnit.unmount()
        mountedTapeName = nil
        memory.cassetteSenseLineHigh = true
        cia1.setFlagLine(high: true)
        clearFailureStatus()
    }

    @discardableResult
    public func startTapePlayback() -> Bool {
        guard tapeUnit.format == .tap, tapeUnit.startRawPlayback() else { return false }
        memory.cassetteSenseLineHigh = false
        cia1.setFlagLine(high: true)
        clearFailureStatus()
        return true
    }

    public func stopTapePlayback() {
        tapeUnit.stopRawPlayback()
        memory.cassetteSenseLineHigh = true
        cia1.setFlagLine(high: true)
        clearFailureStatus()
    }

    func prepareMountedTape() {
        memory.cassetteSenseLineHigh = true
        cia1.setFlagLine(high: true)

        _ = startTapePlayback()
    }

    private var effectiveMountedTapeName: String? {
        if let mountedTapeName {
            return mountedTapeName
        }
        if tapeUnit.format == .t64 {
            return "saved-tape.t64"
        }
        return defaultTapeName(for: tapeUnit.format)
    }

    private func defaultTapeName(for format: TapeUnit.Format?) -> String? {
        switch format {
        case .t64: return "memory.t64"
        case .tap: return "memory.tap"
        case nil: return nil
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
        updateNMI()
        clearFailureStatus()
        return true
    }

    public func unmountCartridge() {
        memory.cartridge = nil
        mountedCartridgeName = nil
        updateNMI()
        clearFailureStatus()
    }

    public func pressCartridgeFreezeButton() {
        memory.cartridge?.pressFreezeButton()
        updateNMI()
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
        machineLock.lock()
        defer { machineLock.unlock() }

        vic.reset()
        sid.reset()
        cia1.reset()
        cia2.reset()
        restoreKeyDown = false
        pendingTypedText.removeAll(keepingCapacity: true)
        driveClockAccumulator = 0
        sidTraceWriteCount = 0
        sidChipWriteCount = 0
        sidRAMWindowWriteCount = 0
        sidChipRegisterWriteCounts = [UInt64](repeating: 0, count: 32)
        sidRAMWindowRegisterWriteCounts = [UInt64](repeating: 0, count: 32)

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
        memory.resetCPUPort()
        tapeUnit.clearWriteCapture()
        memory.resetCartridge()

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
        machineLock.lock()
        defer { machineLock.unlock() }

        vic.reset()
        sid.reset()
        cia1.reset()
        cia2.reset()
        memory.resetCPUPort()
        tapeUnit.clearWriteCapture()
        memory.resetCartridge()
        updateIRQ()
        updateNMI()
        cpu.reset()
        pendingTypedText.removeAll(keepingCapacity: true)
        driveClockAccumulator = 0
        sidTraceWriteCount = 0
        sidChipWriteCount = 0
        sidRAMWindowWriteCount = 0
        sidChipRegisterWriteCounts = [UInt64](repeating: 0, count: 32)
        sidRAMWindowRegisterWriteCounts = [UInt64](repeating: 0, count: 32)

        if trueDriveEmulationMode != .off {
            iecBus.updateFromC64(cia2.portA, ddra: cia2.ddra)
            drive1541.reset()
        }

        clearFailureStatus()
    }

    // MARK: - Execution

    /// Run one complete frame for the active VIC-II video standard.
    /// Returns true when a frame is ready for display.
    public func runFrame() -> Bool {
        machineLock.lock()
        defer { machineLock.unlock() }

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
        cpu.setRDYLine(high: !cpuStalledByVIC)

        // At instruction boundaries: trace, check traps and breakpoints
        if !cpuStalledByVIC && cpu.cycle == 0 {
            debugger.traceInstruction()
            if !debugger.checkBreakpoint() { return }
            if shouldUseKernalTrapAtCurrentInstruction() {
                _ = kernalTraps.checkTrap()
            }
        }

        monitorCPUFailureState()
        feedKeyboardBufferIfPossible()

        cpu.tick()

        // VIC tick
        vic.tick()

        // CIA ticks
        cia1.tick()
        cia2.tick()

        // SID tick
        sid.tick()

        memory.tickBus()
        memory.tickCartridge()

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

    func shouldUseKernalTrapAtCurrentInstruction() -> Bool {
        switch trueDriveEmulationMode {
        case .off:
            return true
        case .compat1541:
            return diskDrive.isMounted && kernalTraps.isDiskIORequest()
        case .standard1541:
            return false
        }
    }

    func updateNMI() {
        cpu.setNMILine(high: cia2.interruptActive || memory.cartridge?.nmiLineActive == true)
    }

    func updateTapeSignal() {
        guard tapeUnit.rawPlaybackActive, memory.cassetteMotorEnabled else {
            cia1.setFlagLine(high: true)
            return
        }

        tapeUnit.tickRawPlayback()
        cia1.setFlagLine(high: tapeUnit.readSignalHigh)
        if !tapeUnit.rawPlaybackActive {
            memory.cassetteSenseLineHigh = true
        }
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
        } else {
            pcFFFFCycleCount = 0
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

    private func hex8(_ value: UInt8) -> String {
        String(format: "%02X", value)
    }

    private static func sidTraceLimitFromEnvironment() -> Int {
        guard let rawValue = ProcessInfo.processInfo.environment["C64_TRACE_SID_LIMIT"],
              let limit = Int(rawValue) else {
            return 100_000
        }
        return max(1, limit)
    }

    private func traceSIDRegisterWrite(register: UInt16, value: UInt8, reachedChip: Bool) {
        guard C64Trace.isEnabled(.sid) else { return }

        if sidTraceWriteCount >= sidTraceWriteLimit {
            if sidTraceWriteCount == sidTraceWriteLimit {
                C64Trace.log(
                    .sid,
                    "[SID-WR] limit \(sidTraceWriteLimit) reached; set C64_TRACE_SID_LIMIT to capture more writes"
                )
            }
            sidTraceWriteCount += 1
            return
        }

        sidTraceWriteCount += 1
        let marker = reachedChip ? "SID-WR" : "SID-RAM"
        let port = memory.cpuPortSnapshot
        let banking = "portDir=$\(hex8(port.direction)) portData=$\(hex8(port.data)) portEff=$\(hex8(port.effective)) L=\(port.loram ? 1 : 0) H=\(port.hiram ? 1 : 0) C=\(port.charen ? 1 : 0)"
        C64Trace.log(
            .sid,
            "[\(marker)] #\(sidTraceWriteCount) @\(cpu.totalCycles) PC=$\(hex16(cpu.pc)) R=$D4\(hex8(UInt8(register & 0x1F))) V=$\(hex8(value)) raster=\(vic.rasterLine):\(vic.rasterCycle) A=$\(hex8(cpu.a)) X=$\(hex8(cpu.x)) Y=$\(hex8(cpu.y)) SP=$\(hex8(cpu.sp)) P=$\(hex8(cpu.p)) IRQ=\(cpu.irqLine ? 1 : 0) NMI=\(cpu.nmiLine ? 1 : 0) RDY=\(cpu.rdyLine ? 1 : 0) \(banking) model=\(sid.model.rawValue) accuracy=\(sid.accuracyMode.rawValue)"
        )
    }

    private func sidRegisterWriteTraceEvent(register: UInt16, value: UInt8, reachedChip: Bool) -> SIDRegisterWriteTraceEvent {
        SIDRegisterWriteTraceEvent(
            cycle: cpu.totalCycles,
            pc: cpu.pc,
            rasterLine: Int(vic.rasterLine),
            rasterCycle: vic.rasterCycle,
            register: UInt8(register & 0x1F),
            value: value,
            reachedChip: reachedChip,
            sidModel: sid.model,
            sidAccuracyMode: sid.accuracyMode
        )
    }

    // MARK: - IRQ management

    func updateIRQ() {
        // IRQ is active if any source is asserting it
        cpu.irqLine = cia1.interruptActive || (vic.interruptRegister & 0x80 != 0)
    }
}
