import Foundation
import Emu6502

/// Full cycle-accurate 1541 disk drive emulation.
///
/// Contains its own 6502 CPU, 2KB RAM, 16KB ROM, two VIA 6522 chips,
/// and a GCR read/write head. Communicates with the C64 via the IEC serial bus.
public final class Drive1541 {

    public enum DriveModel: Equatable {
        case model1541
        case model1541C
        case model1541II
    }

    public struct StatusSnapshot: Equatable {
        public let enabled: Bool
        public let model: DriveModel
        public let motorOn: Bool
        public let ledOn: Bool
        public let halfTrack: Int
        public let track: Int
        public let readHalfTrack: Int?
        public let readTrack: Int?
        public let usingHalfTrackFallback: Bool
        public let headBitPosition: Int
        public let syncDetected: Bool
        public let byteReady: Bool
        public let byteReadyCount: UInt64
        public let via2PortAReadCount: UInt64
        public let syncDetectionCount: UInt64
        public let weakBitReadCount: UInt64
        public let lastWeakBitHalfTrack: Int?
        public let lastWeakBitPosition: Int?
        public let variableSpeedZoneSampleCount: UInt64
        public let variableSpeedZoneMask: UInt8
        public let lastVariableSpeedZoneHalfTrack: Int?
        public let lastVariableSpeedZoneByteIndex: Int?
        public let lastVariableSpeedZone: Int?
        public let gcrWriteByteCount: UInt64
        public let gcrWriteEraseBitCount: UInt64
        public let gcrWriteModeActive: Bool
        public let gcrWriteGateActive: Bool
        public let gcrWriteSpliceCount: UInt64
        public let writeProtected: Bool
        public let hasDisk: Bool
        public let mediaChanged: Bool
        public let mediaChangeCount: UInt64
        public let hasNativeLowLevelImage: Bool
        public let cpuPC: UInt16
        public let cpuJammed: Bool
        public let cycleCount: UInt64
        public let lastIECCommandSummary: String
        public let noProgressCycleCount: UInt64
        public let lastFailureReason: String?
        public let iec: IECBus.Snapshot?
    }

    // MARK: - Components

    public let cpu: CPU6502
    public let memory: DriveMemoryMap
    public let via1: VIA6522  // $1800 — serial bus interface
    public let via2: VIA6522  // $1C00 — disk controller
    public let disk: GCRDisk

    /// Reference to the shared IEC bus
    public weak var iecBus: IECBus?

    public var driveModel: DriveModel = .model1541 {
        didSet {
            is1541C = driveModel == .model1541C
        }
    }

    // MARK: - Drive state

    /// Whether this drive is emulating a 1541C hardware revision (enables track 0 sensor on PA0).
    public var is1541C: Bool = false

    /// Emulates the J3 jumper on 1541C drives. True = jumper open (sensor enabled), False = jumper closed (sensor grounded/disabled).
    public var track0SensorEnabled: Bool = true

    /// Current half-track position (0-83, where 0 = track 1.0, 1 = track 1.5, etc.)
    public var halfTrack: Int = 34  // Start on track 18 (directory)

    /// Current track number (1-based)
    public var track: Int { (halfTrack / 2) + 1 }

    /// Head position within the current track's GCR data (in bits)
    public var headBitPosition: Int = 0

    /// Stepper motor phase (0-3)
    var stepperPhase: Int = 0

    /// Drive motor is spinning
    public var motorOn: Bool = false
    var motorCommandOn: Bool = false
    var motorSpinDownCyclesRemaining: Int = 0

    /// Drive LED state (directly from VIA2 PB3 typically, but also error flash)
    public var ledOn: Bool = false

    /// SYNC detected flag (10-bit shift register == 0x3FF)
    var syncDetected: Bool = false

    /// 10-bit shift register (GCR read head hardware)
    var shiftRegister: UInt16 = 0

    /// Bits collected since last aligned byte output
    var bitCounter: Int = 0

    /// Deterministic pseudo-random state used when reading weak/random bit regions.
    var weakBitLFSR: UInt16 = 0xACE1

    /// UE7 4-bit counter (clocked at 16 MHz, resets at speed-zone value)
    var ue7Counter: Int = 0

    /// UF4 4-bit counter (clocked by UE7 carry)
    var uf4Counter: Int = 0

    /// Byte-ready edge flag (one-shot, drives SO pin on CPU)
    var byteReadyEdge: Bool = false

    /// Byte-ready level flag (cleared when VIA2 PA is read)
    var byteReadyLevel: Bool = false

    /// SO delay in 16 MHz sub-ticks (aligned to 16-cycle boundary, range 10-25)
    var soDelay: Int = 0

    /// Byte-ready generation enabled (controlled by VIA2 CA2 output state)
    var byteReadyActive: Bool = true

    /// Total byte-ready pulses generated since power-on/reset.
    public private(set) var byteReadyCount: UInt64 = 0

    /// Total reads from VIA2 Port A since power-on/reset.
    public private(set) var via2PortAReadCount: UInt64 = 0

    /// Bytes consumed from VIA2 Port A by the 1541 ROM read path.
    public private(set) var via2PortAReadBytes: [UInt8] = []

    /// Total SYNC detections since power-on/reset.
    public private(set) var syncDetectionCount: UInt64 = 0

    /// Total unstable weak/random media bits consumed by the GCR head.
    public private(set) var weakBitReadCount: UInt64 = 0
    public private(set) var lastWeakBitHalfTrack: Int?
    public private(set) var lastWeakBitPosition: Int?

    /// Total UE7 speed samples that used a per-byte variable speed-zone map.
    public private(set) var variableSpeedZoneSampleCount: UInt64 = 0

    /// Bit mask of variable speed zones sampled from per-byte G64 speed maps.
    public private(set) var variableSpeedZoneMask: UInt8 = 0
    public private(set) var lastVariableSpeedZoneHalfTrack: Int?
    public private(set) var lastVariableSpeedZoneByteIndex: Int?
    public private(set) var lastVariableSpeedZone: Int?

    /// Total low-level GCR bytes written through the emulated drive head.
    public private(set) var gcrWriteByteCount: UInt64 = 0
    /// Total low-level bits cleared while the write gate is active without a fresh data byte.
    public private(set) var gcrWriteEraseBitCount: UInt64 = 0
    var gcrWriteBitOffset: Int = 0
    var gcrWriteFreshBitsRemaining: Int = 0
    public private(set) var gcrWriteSpliceCount: UInt64 = 0
    var previousGCRWriteGateActive: Bool = false

    /// Decoded IEC command bytes observed by the 1541 ROM ATN handler.
    /// This is a compact acceptance-test/debug aid; the ROM remains authoritative.
    public private(set) var decodedIECCommandBytes: [UInt8] = []

    /// Decoded IEC listener data bytes observed by the 1541 ROM receive path.
    public private(set) var decodedIECDataBytes: [UInt8] = []

    /// Diagnostic fields populated by the host C64 progress monitor.
    public var noProgressCycleCount: UInt64 = 0
    public var lastFailureReason: String?
    public private(set) var mediaChanged: Bool = false
    public private(set) var mediaChangeCount: UInt64 = 0

    var debugBytesRead: Int = 0
    var gcrTraceLog: Int = 0

    /// Whether the drive is powered on / enabled
    public var enabled: Bool = true

    /// Debug: cycle counter for periodic logging
    var debugCycleCount: UInt64 = 0

    /// IEC trace log counter (limits output)
    var iecTraceLog: Int = 0
    /// Drive PC trace log counter (separate limit)
    var drvPCLog: Int = 0
    var diskPCTraceLog: Int = 0
    static let motorSpinDownCycles = 2_000
    static let writeSpliceBitCount = 16

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
            if let pc = self?.cpu.pc {
                let pbVal = self?.via1.portB ?? 0
                self?.driveLog("[DRV-VIA1] onPortBWrite PC=$\(String(format:"%04X", pc)) PB=$\(String(format:"%02X", pbVal))")
                if pbVal == 0x10 {
                    self?.driveLog("[DRV-10] WRITE OF $10 AT PC=$\(String(format:"%04X", pc))")
                }
            }
            self?.updateBusFromVIA1()
        }

        // VIA1 DDRB write also affects driven outputs
        // (already handled by onPortBWrite which fires on case 0x02 too)

        // VIA2 CA2 output → byte-ready gating (per VICE: set_ca2 in via2d.c)
        via2.onCA2Change = { [weak self] state in
            self?.byteReadyActive = state
            // If CA2 goes high while byte_ready_edge is pending, fire SO now
            if state, let s = self, s.byteReadyEdge {
                s.cpu.pulseSO()
                s.byteReadyEdge = false
            }
        }

        // VIA2 port A read → clear byte-ready signals (per VICE: read_pra in via2d.c)
        via2.onPortARead = { [weak self] in
            guard let s = self else { return }
            s.via2PortAReadCount += 1
            if s.via2PortAReadBytes.count < 512 {
                s.via2PortAReadBytes.append(s.via2.portAInput)
            }
            s.byteReadyLevel = false
            s.byteReadyEdge = false
            s.via2.ca1 = true  // release byte-ready line to idle high
        }

        // VIA2 port A is the disk data register. In write mode the 1541 ROM
        // presents a GCR byte here; the rotating write head serializes it.
        via2.onPortAWrite = { [weak self] reason in
            self?.loadGCRWriteByteFromVIA2PortA(reason: reason)
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
        
        is1541C = detect1541C(rom: bytes)
        driveModel = is1541C ? .model1541C : .model1541
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
        return foundCheck
    }

    /// Load ROM from two 8KB halves (common split: c000.bin + e000.bin).
    public func loadROM(c000: Data, e000: Data) {
        var rom = [UInt8](c000)
        rom.append(contentsOf: [UInt8](e000))
        loadROM(Data(rom))
    }

    // MARK: - Disk operations

    public func insertDisk(_ data: Data, isG64: Bool = false) -> Bool {
        insertDisk(data, format: isG64 ? .g64 : .d64)
    }

    public func insertDisk(_ data: Data, format: DiskImage.Format) -> Bool {
        let loadedDisk = GCRDisk()
        let mounted: Bool
        switch format {
        case .d64:
            mounted = loadedDisk.loadD64(data)
        case .g64:
            mounted = loadedDisk.loadG64(data)
        case .nib:
            mounted = loadedDisk.loadNIB(data)
        case .nbz:
            mounted = loadedDisk.loadNBZ(data)
        case .p64:
            mounted = loadedDisk.loadP64(data)
        }
        guard mounted else { return false }

        closeGCRWriteGateIfActive()
        replaceMountedDisk(with: loadedDisk)
        markMediaChanged()
        resetGCRReadPipeline()
        updateVIA2Inputs()
        return true
    }

    public func insertDiskImage(_ image: DiskImage) -> Bool {
        let mounted = image.tracks.contains { $0 != nil }
        guard mounted else { return false }

        closeGCRWriteGateIfActive()
        disk.tracks = image.tracks.map { $0?.bytes }
        disk.trackInfos = image.tracks
        disk.image = image
        disk.hasUnsavedLowLevelWrites = false
        disk.writeProtected = true
        markMediaChanged()
        resetGCRReadPipeline()
        updateVIA2Inputs()
        return true
    }

    public func ejectDisk() {
        closeGCRWriteGateIfActive()
        let hadDisk = disk.hasDisk || disk.image != nil
        disk.tracks = Array(repeating: nil, count: GCRDisk.maxHalfTracks)
        disk.trackInfos = Array(repeating: nil, count: GCRDisk.maxHalfTracks)
        disk.image = nil
        if hadDisk {
            markMediaChanged()
        }
        resetGCRReadPipeline()
        updateVIA2Inputs()
    }

    public func setWriteProtected(_ protected: Bool) {
        disk.writeProtected = protected
        updateGCRWriteGateSpliceState()
        updateVIA2Inputs()
    }

    public func exportedG64Image(finalizingActiveWriteGate: Bool = true) -> Data? {
        guard finalizingActiveWriteGate,
              previousGCRWriteGateActive else {
            return disk.exportedG64Image
        }

        let exportDisk = GCRDisk()
        exportDisk.tracks = disk.tracks
        exportDisk.trackInfos = disk.trackInfos
        exportDisk.image = disk.image
        exportDisk.writeProtected = disk.writeProtected
        exportDisk.hasUnsavedLowLevelWrites = disk.hasUnsavedLowLevelWrites
        _ = exportDisk.addWeakBitRange(
            startBit: headBitPosition,
            bitCount: Self.writeSpliceBitCount,
            forHalfTrack: halfTrack
        )
        return exportDisk.exportedG64Image
    }

    public var hasPendingGCRWriteGateSplice: Bool {
        previousGCRWriteGateActive
    }

    @discardableResult
    public func markExportedG64ImageSaved() -> Bool {
        guard !previousGCRWriteGateActive else {
            return false
        }
        disk.markLowLevelWritesSaved()
        return true
    }

    public func acknowledgeMediaChange() {
        mediaChanged = false
    }

    public var statusSnapshot: StatusSnapshot {
        let readTrackResolution = resolvedReadTrack(forHalfTrack: halfTrack)
        return StatusSnapshot(
            enabled: enabled,
            model: driveModel,
            motorOn: motorOn,
            ledOn: ledOn,
            halfTrack: halfTrack,
            track: track,
            readHalfTrack: readTrackResolution?.halfTrack,
            readTrack: readTrackResolution.map { ($0.halfTrack / 2) + 1 },
            usingHalfTrackFallback: readTrackResolution.map { $0.halfTrack != halfTrack } ?? false,
            headBitPosition: headBitPosition,
            syncDetected: syncDetected,
            byteReady: byteReadyLevel || byteReadyEdge,
            byteReadyCount: byteReadyCount,
            via2PortAReadCount: via2PortAReadCount,
            syncDetectionCount: syncDetectionCount,
            weakBitReadCount: weakBitReadCount,
            lastWeakBitHalfTrack: lastWeakBitHalfTrack,
            lastWeakBitPosition: lastWeakBitPosition,
            variableSpeedZoneSampleCount: variableSpeedZoneSampleCount,
            variableSpeedZoneMask: variableSpeedZoneMask,
            lastVariableSpeedZoneHalfTrack: lastVariableSpeedZoneHalfTrack,
            lastVariableSpeedZoneByteIndex: lastVariableSpeedZoneByteIndex,
            lastVariableSpeedZone: lastVariableSpeedZone,
            gcrWriteByteCount: gcrWriteByteCount,
            gcrWriteEraseBitCount: gcrWriteEraseBitCount,
            gcrWriteModeActive: gcrWriteModeActive,
            gcrWriteGateActive: gcrWriteGateActive,
            gcrWriteSpliceCount: gcrWriteSpliceCount,
            writeProtected: disk.writeProtected,
            hasDisk: disk.hasDisk,
            mediaChanged: mediaChanged,
            mediaChangeCount: mediaChangeCount,
            hasNativeLowLevelImage: disk.hasNativeLowLevelImage,
            cpuPC: cpu.pc,
            cpuJammed: cpu.jammed,
            cycleCount: debugCycleCount,
            lastIECCommandSummary: Self.hexSummary(decodedIECCommandBytes.suffix(12)),
            noProgressCycleCount: noProgressCycleCount,
            lastFailureReason: lastFailureReason,
            iec: iecBus?.snapshot
        )
    }

    public var progressSignature: UInt64 {
        var value = UInt64(cpu.pc)
        value = value &* 1099511628211 &+ UInt64(headBitPosition)
        value = value &* 1099511628211 &+ UInt64(halfTrack)
        value = value &* 1099511628211 &+ byteReadyCount
        value = value &* 1099511628211 &+ via2PortAReadCount
        value = value &* 1099511628211 &+ syncDetectionCount
        value = value &* 1099511628211 &+ gcrWriteByteCount
        value = value &* 1099511628211 &+ gcrWriteEraseBitCount
        value = value &* 1099511628211 &+ gcrWriteSpliceCount
        value = value &* 1099511628211 &+ UInt64(decodedIECCommandBytes.count)
        value = value &* 1099511628211 &+ UInt64(decodedIECDataBytes.count)
        if gcrWriteGateActive { value &+= 0x0800_0000 }
        if motorOn { value &+= 0x1000_0000 }
        if ledOn { value &+= 0x2000_0000 }
        if let iec = iecBus?.snapshot {
            if iec.atnLine { value &+= 1 }
            if iec.clockLine { value &+= 2 }
            if iec.dataLine { value &+= 4 }
            if iec.c64Atn { value &+= 8 }
            if iec.c64Clock { value &+= 16 }
            if iec.c64Data { value &+= 32 }
            if iec.driveClock { value &+= 64 }
            if iec.driveData { value &+= 128 }
            if iec.driveAtn { value &+= 256 }
        }
        return value
    }

    private func markMediaChanged() {
        mediaChanged = true
        mediaChangeCount &+= 1
    }

    private func replaceMountedDisk(with source: GCRDisk) {
        disk.tracks = source.tracks
        disk.trackInfos = source.trackInfos
        disk.image = source.image
        disk.writeProtected = source.writeProtected
        disk.hasUnsavedLowLevelWrites = source.hasUnsavedLowLevelWrites
    }

    private static func hexSummary<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        let values = bytes.map { String(format: "%02X", $0) }
        return values.isEmpty ? "none" : values.joined(separator: " ")
    }

    // MARK: - Power on

    public func powerOn() {
        guard memory.rom.count == 16384 else {
            driveLog("[1541] cannot power on — ROM not loaded (size=\(memory.rom.count))")
            return
        }
        C64Trace.resetLog()
        iecTraceLog = 0
        drvPCLog = 0
        gcrTraceLog = 0
        diskPCTraceLog = 0
        memory.via1WriteLog = 0
        resetHardwareState(resetCPU: false)

        let resetLo = memory.rom[0x3FFC]  // $FFFC - $C000 = $3FFC
        let resetHi = memory.rom[0x3FFD]
        driveLog("[1541] powerOn: ROM reset vector = $\(String(format: "%02X%02X", resetHi, resetLo))")

        cpu.powerOn()
        enabled = true


        // Note: onBusUpdate is NOT wired to updateVIA1FromBus.
        // The drive's VIA1 inputs are updated once per drive tick, not on
        // every C64 bus change. This prevents rapid C64 bus toggles from
        // overwriting portBInput before the drive CPU can read it.
        // The C64 side reads bus state via computed properties (dataLine, etc.)
        // which always reflect the latest drive outputs.
        driveLog("[1541] powerOn complete: PC=$\(String(format: "%04X", cpu.pc))")

        // Dump key ROM routines for debugging
        let irqVec = UInt16(memory.rom[0x3FFE]) | (UInt16(memory.rom[0x3FFF]) << 8)
        driveLog("[ROM] IRQ vector = $\(String(format:"%04X", irqVec))")
        // Dump ATN handler area ($E85B-$E8F0)
        var dump = "[ROM] $E850: "
        for addr in 0xE850...0xE8F0 {
            dump += String(format: "%02X ", memory.rom[addr - 0xC000])
            if (addr & 0x0F) == 0x0F {
                driveLog(dump)
                dump = "[ROM] $\(String(format:"%04X", addr+1)): "
            }
        }
        if !dump.hasSuffix(": ") { driveLog(dump) }
        // Dump receive byte routine ($E9C0-$E9F0)
        dump = "[ROM] $E9C0: "
        for addr in 0xE9C0...0xE9F0 {
            dump += String(format: "%02X ", memory.rom[addr - 0xC000])
            if (addr & 0x0F) == 0x0F {
                driveLog(dump)
                dump = "[ROM] $\(String(format:"%04X", addr+1)): "
            }
        }
        if !dump.hasSuffix(": ") { driveLog(dump) }
    }

    public func reset() {
        resetHardwareState(resetCPU: true)
        enabled = true
    }

    private func resetHardwareState(resetCPU: Bool) {
        closeGCRWriteGateIfActive()
        via1.reset()
        via2.reset()

        if resetCPU {
            cpu.powerOn()
        }

        halfTrack = 34  // Track 18
        headBitPosition = 0
        stepperPhase = 0
        motorOn = false
        motorCommandOn = false
        motorSpinDownCyclesRemaining = 0
        ledOn = false
        resetGCRReadPipeline()
        byteReadyActive = true
        via2.ca1 = true
        via2.portAInput = 0xFF
        updateVIA2Inputs()
        updateBusFromVIA1()

        debugCycleCount = 0
        byteReadyCount = 0
        via2PortAReadCount = 0
        via2PortAReadBytes.removeAll(keepingCapacity: true)
        syncDetectionCount = 0
        weakBitReadCount = 0
        lastWeakBitHalfTrack = nil
        lastWeakBitPosition = nil
        variableSpeedZoneSampleCount = 0
        variableSpeedZoneMask = 0
        lastVariableSpeedZoneHalfTrack = nil
        lastVariableSpeedZoneByteIndex = nil
        lastVariableSpeedZone = nil
        gcrWriteByteCount = 0
        gcrWriteEraseBitCount = 0
        gcrWriteBitOffset = 0
        gcrWriteFreshBitsRemaining = 0
        gcrWriteSpliceCount = 0
        previousGCRWriteGateActive = false
        decodedIECCommandBytes.removeAll(keepingCapacity: true)
        decodedIECDataBytes.removeAll(keepingCapacity: true)
        noProgressCycleCount = 0
        lastFailureReason = nil
        debugBytesRead = 0
        debugLogCount = 0
    }

    private func resetGCRReadPipeline() {
        headBitPosition = 0
        syncDetected = false
        shiftRegister = 0
        bitCounter = 0
        weakBitLFSR = 0xACE1
        ue7Counter = 0
        uf4Counter = 0
        byteReadyEdge = false
        byteReadyLevel = false
        soDelay = 0
        via2.ca1 = true
        gcrWriteBitOffset = 0
        gcrWriteFreshBitsRemaining = 0
        previousGCRWriteGateActive = false
    }

    private func clearGCRReadPresentation() {
        syncDetected = false
        shiftRegister = 0
        bitCounter = 0
        byteReadyEdge = false
        byteReadyLevel = false
        soDelay = 0
        via2.portAInput = 0x00
        via2.ca1 = true
    }

    // MARK: - Tick (one drive clock cycle)

    var debugLogCount = 0
    public func tick() {
        debugLogCount += 1
        if debugLogCount % 200000 == 0 {
            driveLog("[1541] PC=$\(String(cpu.pc, radix: 16, uppercase: true)) flags=$\(String(cpu.p, radix: 16)) A=$\(String(cpu.a, radix: 16)) X=$\(String(cpu.x, radix: 16)) Y=$\(String(cpu.y, radix: 16))")
        }
        guard enabled else { return }

        debugCycleCount += 1

        // Log key serial bus events in the drive
        if cpu.cycle == 0 {
            let pc = cpu.pc
            // Log all instruction executions in the ATN handler range ($E850-$E910)
            if pc >= 0xE850 && pc <= 0xE910 && drvPCLog < 500 {
                drvPCLog += 1
                let pbRead = (pc >= 0xE870 && pc <= 0xE890) ? via1.readRegister(0x00) : 0
                driveLog("[DRV-PC] @\(debugCycleCount) PC=$\(String(format:"%04X",pc)) A=$\(String(format:"%02X",cpu.a)) X=$\(String(format:"%02X",cpu.x)) Y=$\(String(format:"%02X",cpu.y)) P=$\(String(format:"%02X",cpu.p))\(pbRead != 0 ? " PB=$\(String(format:"%02X",pbRead))" : "")")
            }
            // Log receive byte routine ($E990-$E9F0)
            if pc >= 0xE990 && pc <= 0xE9F0 && drvPCLog < 500 {
                drvPCLog += 1
                driveLog("[DRV-RX] @\(debugCycleCount) PC=$\(String(format:"%04X",pc)) A=$\(String(format:"%02X",cpu.a)) P=$\(String(format:"%02X",cpu.p))")
            }
            if C64Trace.isEnabled(.gcr),
               ((pc >= 0xD000 && pc <= 0xDFFF) || pc >= 0xF000),
               diskPCTraceLog < 1000 {
                diskPCTraceLog += 1
                C64Trace.log(.gcr, "[DRV-DOS] @\(debugCycleCount) PC=$\(String(format:"%04X",pc)) A=$\(String(format:"%02X",cpu.a)) X=$\(String(format:"%02X",cpu.x)) Y=$\(String(format:"%02X",cpu.y)) P=$\(String(format:"%02X",cpu.p)) PB2=$\(String(format:"%02X",via2.portB)) PA2=$\(String(format:"%02X",via2.portAInput)) V=\(cpu.getFlag(Flags.overflow)) BR=\(byteReadyCount) PAreads=\(via2PortAReadCount)")
            }
        }

        // --- IEC bus trace: capture state before updates ---
        let prevCA1 = via1.ca1
        let prevIRQ = cpu.irqLine
        let prevVIA1PB = via1.portB
        let prevVIA1DDRB = via1.ddrb

        // Update IEC bus → VIA1 inputs
        updateVIA1FromBus()

        // Log CA1 state change (ATN edge at drive)
        if via1.ca1 != prevCA1 && iecTraceLog < 500 {
            iecTraceLog += 1
            driveLog("[IEC-TRACE] @\(debugCycleCount) CA1: \(prevCA1)→\(via1.ca1) (atnLine=\(iecBus?.atnLine ?? true)) VIA1: PCR=$\(String(format:"%02X",via1.pcr)) IER=$\(String(format:"%02X",via1.ier)) IFR=$\(String(format:"%02X",via1.ifr)) ca1_int_enabled=\(via1.ier & VIA6522.IRQ.ca1 != 0)")
        }

        // Tick VIAs (timers, edge detection)
        via1.tick()
        via2.tick()

        // Log if IRQ line changed after VIA tick
        if cpu.irqLine != prevIRQ && iecTraceLog < 500 {
            iecTraceLog += 1
            driveLog("[IEC-TRACE] @\(debugCycleCount) IRQ: \(prevIRQ)→\(cpu.irqLine) PC=$\(String(format:"%04X",cpu.pc)) cycle=\(cpu.cycle) VIA1.IFR=$\(String(format:"%02X",via1.ifr)) VIA2.IFR=$\(String(format:"%02X",via2.ifr))")
        }

        // Update bus from VIA1 outputs
        updateBusFromVIA1()

        // Log if drive changed its bus output
        if (via1.portB != prevVIA1PB || via1.ddrb != prevVIA1DDRB) && iecTraceLog < 500 {
            let driven = via1.portB & via1.ddrb
            let prevDriven = prevVIA1PB & prevVIA1DDRB
            if driven != prevDriven {
                iecTraceLog += 1
                driveLog("[IEC-TRACE] @\(debugCycleCount) DRV output changed: PB=$\(String(format:"%02X",via1.portB)) DDRB=$\(String(format:"%02X",via1.ddrb)) driven=$\(String(format:"%02X",driven)) (was $\(String(format:"%02X",prevDriven))) → bus DATA=\(iecBus?.dataLine ?? true) CLK=\(iecBus?.clockLine ?? true)")
            }
        }

        // Read motor/stepper from VIA2 PB (before GCR head)
        updateMotorAndStepper()
        updateGCRWriteGateSpliceState()

        // GCR head: advance disk and feed bytes to VIA2
        if motorOn {
            tickGCRHead()
        } else if soDelay > 0 {
            // Drain pending byte-ready even if motor just stopped
            soDelay = 0
            fireByteReady()
        }

        // Update VIA2 PB input (sync, WP) after GCR head so sync state is current
        updateVIA2Inputs()

        // Tick CPU
        cpu.tick()

        if cpu.cycle == 0 && cpu.pc == 0xE887 && decodedIECCommandBytes.count < 64 {
            decodedIECCommandBytes.append(cpu.a)
            driveLog("[DRV-CMD] @\(debugCycleCount) byte=$\(String(format:"%02X", cpu.a))")
        }
        if cpu.cycle == 0 && cpu.pc == 0xEA47 && decodedIECDataBytes.count < 256 {
            decodedIECDataBytes.append(cpu.a)
            driveLog("[DRV-DATA] @\(debugCycleCount) byte=$\(String(format:"%02X", cpu.a))")
        }
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

    /// Read motor, LED, and stepper state from VIA2 PB (called before GCR head)
    func updateMotorAndStepper() {
        let pb = via2.portB
        let wasMotorOn = motorOn
        let wasLEDOn = ledOn

        let commandedMotorOn = pb & 0x04 != 0
        if commandedMotorOn {
            motorOn = true
            motorSpinDownCyclesRemaining = Self.motorSpinDownCycles
        } else {
            if motorCommandOn {
                motorSpinDownCyclesRemaining = Self.motorSpinDownCycles
            }
            if motorSpinDownCyclesRemaining > 0 {
                motorSpinDownCyclesRemaining -= 1
                motorOn = motorSpinDownCyclesRemaining > 0
            } else {
                motorOn = false
            }
        }
        motorCommandOn = commandedMotorOn
        ledOn = pb & 0x08 != 0

        if (motorOn != wasMotorOn || ledOn != wasLEDOn) && gcrTraceLog < 200 {
            gcrTraceLog += 1
            C64Trace.log(.gcr, "[GCR-MOTOR] @\(debugCycleCount) motor=\(motorOn) led=\(ledOn) PB=$\(String(format:"%02X", pb)) track=\(track)")
        }

        // Stepper motor (PB0-PB1)
        let newPhase = Int(pb & 0x03)
        if newPhase != stepperPhase {
            let delta = (newPhase - stepperPhase + 4) % 4
            let oldTrack = track
            if delta == 1 {
                if halfTrack < GCRDisk.maxHalfTracks - 1 { halfTrack += 1 }
            } else if delta == 3 {
                if halfTrack > 0 { halfTrack -= 1 }
            }
            if track != oldTrack {
                debugBytesRead = 0
            }
            if track != oldTrack && gcrTraceLog < 200 {
                gcrTraceLog += 1
                C64Trace.log(.gcr, "[GCR-STEP] @\(debugCycleCount) halfTrack=\(halfTrack) track=\(track) phase=\(stepperPhase)->\(newPhase)")
            }
            stepperPhase = newPhase
        }
    }

    /// Update VIA2 PB input with sync and write-protect state (called after GCR head)
    func updateVIA2Inputs() {
        var pbInput = via2.portBInput & 0x6F  // Clear bits 4 and 7
        if !disk.writeProtected {
            pbInput |= 0x10
        }
        if !syncDetected {
            pbInput |= 0x80
        }
        via2.portBInput = pbInput
    }

    // MARK: - GCR head simulation (16 MHz sub-tick model per VICE rotation.c)

    /// Fire the byte-ready signal: SO pin + VIA2 CA1 level
    func fireByteReady() {
        byteReadyEdge = true
        byteReadyLevel = true
        byteReadyCount += 1
        if gcrTraceLog < 200 {
            gcrTraceLog += 1
            C64Trace.log(.gcr, "[GCR-BYTE] @\(debugCycleCount) count=\(byteReadyCount) PA=$\(String(format:"%02X", via2.portAInput)) track=\(track) bit=\(headBitPosition)")
        }
        cpu.pulseSO()
        via2.ca1 = false  // active-low byte-ready pulse, released when VIA2 PA is read
    }

    /// Simulate disk head at 16 MHz granularity (16 sub-ticks per 1 MHz drive cycle).
    ///
    /// UE7 is a 4-bit counter clocked at 16 MHz that resets to the speed-zone value (0-3).
    /// UF4 is a 4-bit counter clocked by UE7 carry. A bit is shifted from the disk
    /// on the rising edge of UF4 bit 1 (transitions at counts 2, 6, 10, 14).
    /// This gives 4 bits per 16 UF4 steps, yielding the correct byte rates:
    ///   Zone 3: 26 cycles/byte, Zone 2: 28, Zone 1: 30, Zone 0: 32
    func tickGCRHead() {
        let viaSpeedZone = Int((via2.portB >> 5) & 0x03)
        updateGCRWriteGateSpliceState()

        if gcrWriteModeActive {
            tickGCRWriteHead(viaSpeedZone: viaSpeedZone)
            return
        }

        guard let resolvedTrack = resolvedReadTrack(forHalfTrack: halfTrack) else {
            clearGCRReadPresentation()
            return
        }
        let trackInfo = resolvedTrack.info
        let trackData = resolvedTrack.bytes

        let totalBits = trackInfo?.bitLength ?? trackData.count * 8

        // Process 16 sub-ticks (one 1 MHz drive cycle = 16 × 16 MHz ticks)
        for subTick in 0..<16 {
            // SO delay countdown (16 MHz granularity per VICE)
            if soDelay > 0 {
                soDelay -= 1
                if soDelay == 0 {
                    fireByteReady()
                }
            }

            // UE7 counter: counts 0-15, resets to zone value on carry
            ue7Counter += 1
            if ue7Counter >= 16 {
                let zone = speedZoneForCurrentHeadPosition(
                    trackInfo: trackInfo,
                    halfTrack: resolvedTrack.halfTrack,
                    fallbackZone: viaSpeedZone,
                    totalBits: totalBits
                )
                ue7Counter = zone

                // UF4 counter: clocked by UE7 carry
                let prevUF4 = uf4Counter
                uf4Counter = (uf4Counter + 1) & 0x0F

                // Shift a bit on rising edge of UF4 bit 1 (at counts 2, 6, 10, 14)
                if (uf4Counter & 2) != 0 && (prevUF4 & 2) == 0 {
                    // Read next bit from track
                    if headBitPosition >= totalBits { headBitPosition = 0 }
                    let byteIdx = headBitPosition / 8
                    let bitIdx = 7 - (headBitPosition % 8)
                    let bit = readTrackBit(
                        trackData: trackData,
                        trackInfo: trackInfo,
                        halfTrack: resolvedTrack.halfTrack,
                        byteIndex: byteIdx,
                        bitIndex: bitIdx,
                        bitPosition: headBitPosition
                    )
                    headBitPosition += 1

                    // 10-bit shift register (per VICE: last_read_data)
                    shiftRegister = ((shiftRegister << 1) | bit) & 0x3FF

                    // SYNC detection: 10 consecutive 1-bits in shift register
                    if shiftRegister == 0x3FF {
                        if !syncDetected {
                            syncDetectionCount += 1
                            if gcrTraceLog < 200 {
                                gcrTraceLog += 1
                                C64Trace.log(.gcr, "[GCR-SYNC] @\(debugCycleCount) count=\(syncDetectionCount) track=\(track) bit=\(headBitPosition)")
                            }
                        }
                        syncDetected = true
                        bitCounter = 0  // hold byte framing in reset during sync
                    } else {
                        syncDetected = false
                        bitCounter += 1

                        if bitCounter >= 8 {
                            bitCounter = 0

                            // Complete byte: present lower 8 bits to VIA2 PA
                            via2.portAInput = UInt8(shiftRegister & 0xFF)

                            // Schedule byte-ready with SO delay (aligned to 16-cycle boundary)
                            if byteReadyActive {
                                soDelay = 16 - subTick
                                if soDelay < 10 { soDelay += 16 }
                            }
                        }
                    }
                }
            }
        }
    }

    private func updateGCRWriteGateSpliceState() {
        let writeGateActive = gcrWriteGateActive
        if writeGateActive != previousGCRWriteGateActive {
            if writeGateActive {
                markGCRWriteSplice(startBitOffset: -Self.writeSpliceBitCount)
            } else {
                markGCRWriteSplice(startBitOffset: 0)
            }
            previousGCRWriteGateActive = writeGateActive
        }
    }

    private func closeGCRWriteGateIfActive() {
        guard previousGCRWriteGateActive else { return }
        markGCRWriteSplice(startBitOffset: 0)
        previousGCRWriteGateActive = false
    }

    private func markGCRWriteSplice(startBitOffset: Int) {
        guard let target = resolvedWritableTrack(forHalfTrack: halfTrack) else { return }
        let totalBits = target.info?.bitLength ?? target.bytes.count * 8
        guard totalBits > 0 else { return }

        let startBit = ((headBitPosition + startBitOffset) % totalBits + totalBits) % totalBits
        guard disk.addWeakBitRange(
            startBit: startBit,
            bitCount: Self.writeSpliceBitCount,
            forHalfTrack: target.halfTrack
        ) else { return }
        gcrWriteSpliceCount += 1
    }

    private func tickGCRWriteHead(viaSpeedZone: Int) {
        guard motorOn,
              !disk.writeProtected,
              let target = resolvedWritableTrack(forHalfTrack: halfTrack) else {
            clearGCRReadPresentation()
            return
        }

        let totalBits = target.info?.bitLength ?? target.bytes.count * 8
        guard totalBits > 0 else {
            clearGCRReadPresentation()
            return
        }

        clearGCRReadPresentation()
        for _ in 0..<16 {
            ue7Counter += 1
            if ue7Counter >= 16 {
                ue7Counter = viaSpeedZone

                let prevUF4 = uf4Counter
                uf4Counter = (uf4Counter + 1) & 0x0F

                if (uf4Counter & 2) != 0 && (prevUF4 & 2) == 0 {
                    if headBitPosition >= totalBits { headBitPosition = 0 }
                    let hasFreshDataBit = gcrWriteFreshBitsRemaining > 0
                    let sourceBitIndex = 7 - gcrWriteBitOffset
                    let bit = hasFreshDataBit
                        ? (via2.portAOut >> UInt8(sourceBitIndex)) & 0x01 != 0
                        : false
                    if disk.writeBitAtBitPosition(
                        bit,
                        halfTrack: target.halfTrack,
                        bitPosition: headBitPosition,
                        speedZone: viaSpeedZone
                    ) {
                        headBitPosition += 1
                        if hasFreshDataBit {
                            gcrWriteFreshBitsRemaining -= 1
                            gcrWriteBitOffset = (gcrWriteBitOffset + 1) & 0x07
                            if gcrWriteBitOffset == 0 {
                                gcrWriteByteCount += 1
                                if gcrTraceLog < 200 {
                                    gcrTraceLog += 1
                                    C64Trace.log(.gcr, "[GCR-WRITE] @\(debugCycleCount) count=\(gcrWriteByteCount) PA=$\(String(format:"%02X", via2.portAOut)) halfTrack=\(target.halfTrack) bit=\(headBitPosition)")
                                }
                            }
                        } else {
                            gcrWriteEraseBitCount += 1
                        }
                    }
                }
            }
        }
    }

    private func resolvedReadTrack(
        forHalfTrack halfTrack: Int
    ) -> (halfTrack: Int, bytes: [UInt8], info: DiskImage.Track?)? {
        func track(at index: Int) -> (halfTrack: Int, bytes: [UInt8], info: DiskImage.Track?)? {
            guard index >= 0 && index < GCRDisk.maxHalfTracks else { return nil }
            let info = disk.trackInfo(halfTrack: index)
            guard let bytes = info?.bytes ?? disk.tracks[index], !bytes.isEmpty else { return nil }
            return (index, bytes, info)
        }

        if let exact = track(at: halfTrack) {
            return exact
        }

        // Real heads can still pick up adjacent full-track flux when parked on
        // an unwritten halftrack. Preserve explicit halftrack data when present.
        guard halfTrack % 2 == 1 else { return nil }
        return track(at: halfTrack - 1) ?? track(at: halfTrack + 1)
    }

    private func readTrackBit(
        trackData: [UInt8],
        trackInfo: DiskImage.Track?,
        halfTrack: Int,
        byteIndex: Int,
        bitIndex: Int,
        bitPosition: Int
    ) -> UInt16 {
        if let trackInfo,
           trackInfo.weakBitRanges.contains(where: { $0.contains(bitPosition) }) {
            weakBitReadCount += 1
            lastWeakBitHalfTrack = halfTrack
            lastWeakBitPosition = bitPosition
            return nextWeakBit()
        }
        return UInt16((trackData[byteIndex] >> bitIndex) & 1)
    }

    private func nextWeakBit() -> UInt16 {
        let feedback = ((weakBitLFSR >> 0) ^ (weakBitLFSR >> 2) ^ (weakBitLFSR >> 3) ^ (weakBitLFSR >> 5)) & 1
        weakBitLFSR = (weakBitLFSR >> 1) | (feedback << 15)
        return UInt16(weakBitLFSR & 1)
    }

    private func speedZoneForCurrentHeadPosition(
        trackInfo: DiskImage.Track?,
        halfTrack: Int,
        fallbackZone: Int,
        totalBits: Int
    ) -> Int {
        guard let trackInfo else { return fallbackZone }
        guard let speedZoneMap = trackInfo.speedZoneMap, !speedZoneMap.isEmpty, totalBits > 0 else {
            return trackInfo.speedZone
        }

        let byteIndex = (headBitPosition % totalBits) / 8
        guard byteIndex < speedZoneMap.count else {
            return trackInfo.speedZone
        }
        variableSpeedZoneSampleCount += 1
        let zone = Int(speedZoneMap[byteIndex])
        variableSpeedZoneMask |= UInt8(1 << zone)
        lastVariableSpeedZoneHalfTrack = halfTrack
        lastVariableSpeedZoneByteIndex = byteIndex
        lastVariableSpeedZone = zone
        return zone
    }

    private func loadGCRWriteByteFromVIA2PortA(reason: VIA6522.PortAChangeReason) {
        guard reason != .reset else {
            gcrWriteFreshBitsRemaining = 0
            return
        }
        gcrWriteBitOffset = 0
        switch reason {
        case .outputRegister, .outputRegisterNoHandshake:
            gcrWriteFreshBitsRemaining = 8
        case .dataDirection, .reset:
            gcrWriteFreshBitsRemaining = 0
        }
        syncDetected = false
        shiftRegister = 0
        bitCounter = 0
        byteReadyEdge = false
        byteReadyLevel = false
        soDelay = 0
        via2.ca1 = true
    }

    private func resolvedWritableTrack(
        forHalfTrack halfTrack: Int
    ) -> (halfTrack: Int, bytes: [UInt8], info: DiskImage.Track?)? {
        guard halfTrack >= 0 && halfTrack < GCRDisk.maxHalfTracks else { return nil }
        let info = disk.trackInfo(halfTrack: halfTrack)
        if let bytes = info?.bytes ?? disk.tracks[halfTrack], !bytes.isEmpty {
            return (halfTrack, bytes, info)
        }

        guard disk.hasDisk else { return nil }
        let speedZone = Int((via2.portB >> 5) & 0x03)
        guard disk.ensureWritableTrack(halfTrack: halfTrack, speedZone: speedZone),
              let bytes = disk.tracks[halfTrack],
              !bytes.isEmpty else {
            return nil
        }
        return (halfTrack, bytes, disk.trackInfo(halfTrack: halfTrack))
    }

    private var gcrWriteModeActive: Bool {
        via2.ddra == 0xFF
    }

    private var gcrWriteGateActive: Bool {
        motorOn && gcrWriteModeActive && !disk.writeProtected && disk.hasDisk
    }

    // MARK: - IRQ management

    func updateIRQ() {
        cpu.irqLine = (via1.ifr & VIA6522.IRQ.any != 0) || (via2.ifr & VIA6522.IRQ.any != 0)
    }

    func driveLog(_ msg: String) {
        C64Trace.log(.drive, msg)
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

    var via1WriteLog: Int = 0
    var driveDataBus: UInt8 = 0xFF

    public init() {}

    private func memLog(_ msg: String) {
        C64Trace.log(.drive, msg)
    }

    public func read(_ address: UInt16) -> UInt8 {
        let addr = Int(address)

        let value: UInt8
        switch addr {
        case 0x0000...0x07FF:
            value = ram[addr]

        case 0x0800...0x17FF:
            value = ram[addr & 0x07FF]  // RAM mirrors up to the VIA window

        case 0x1800...0x180F:
            value = via1?.readRegister(address & 0x0F) ?? driveDataBus

        case 0x1810...0x1BFF:
            value = via1?.readRegister(address & 0x0F) ?? driveDataBus  // VIA1 mirrors

        case 0x1C00...0x1C0F:
            value = via2?.readRegister(address & 0x0F) ?? driveDataBus

        case 0x1C10...0x1FFF:
            value = via2?.readRegister(address & 0x0F) ?? driveDataBus  // VIA2 mirrors

        case 0xC000...0xFFFF:
            value = rom[addr - 0xC000]

        default:
            value = driveDataBus
        }

        driveDataBus = value
        return value
    }

    public func write(_ address: UInt16, value: UInt8) {
        let addr = Int(address)
        driveDataBus = value

        switch addr {
        case 0x0000...0x07FF:
            ram[addr] = value

        case 0x0800...0x17FF:
            ram[addr & 0x07FF] = value  // RAM mirrors up to the VIA window

        case 0x1800...0x180F:
            let reg = address & 0x0F
            // Log VIA1 PCR, IER, PB, DDRB writes (IEC bus configuration)
            if via1WriteLog < 500 {
                switch reg {
                case 0x00: via1WriteLog += 1; memLog("[VIA1-WR] @$\(String(format:"%04X",address)) ORB=$\(String(format:"%02X",value))")
                case 0x02: via1WriteLog += 1; memLog("[VIA1-WR] @$\(String(format:"%04X",address)) DDRB=$\(String(format:"%02X",value))")
                case 0x0C: via1WriteLog += 1; memLog("[VIA1-WR] @$\(String(format:"%04X",address)) PCR=$\(String(format:"%02X",value)) → CA1edge=\(value & 0x01 != 0 ? "pos" : "neg") CA2mode=\((value >> 1) & 0x07)")
                case 0x0E: via1WriteLog += 1; memLog("[VIA1-WR] @$\(String(format:"%04X",address)) IER=$\(String(format:"%02X",value)) \(value & 0x80 != 0 ? "SET" : "CLR") bits=$\(String(format:"%02X",value & 0x7F)) → CA1_int=\(value & 0x02 != 0)")
                default: break
                }
            }
            via1?.writeRegister(reg, value: value)

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
