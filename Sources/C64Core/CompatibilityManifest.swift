import Foundation

public struct CompatibilityManifest: Decodable, Equatable {
    public let milestones: [CompatibilityMilestone]

    public init(milestones: [CompatibilityMilestone]) {
        self.milestones = milestones
    }
}

public enum CompatibilityMediaType: String, Decodable, Equatable {
    case prg
    case d64
    case g64
    case t64
    case tap
    case crt
}

public enum CompatibilityMachineProfile: String, Decodable, Equatable {
    case palC64
    case palC64C
    case palC64With1541II
    case palC64CWith1541II
    case ntscC64
    case ntscC64C
    case ntscC64With1541II
    case ntscC64CWith1541II

    public var profile: MachineProfile {
        switch self {
        case .palC64: return .palC64
        case .palC64C: return .palC64C
        case .palC64With1541II: return .palC64With1541II
        case .palC64CWith1541II: return .palC64CWith1541II
        case .ntscC64: return .ntscC64
        case .ntscC64C: return .ntscC64C
        case .ntscC64With1541II: return .ntscC64With1541II
        case .ntscC64CWith1541II: return .ntscC64CWith1541II
        }
    }
}

public enum CompatibilityDriveMode: String, Decodable, Equatable {
    case fastLoad
    case compat1541
    case standard1541

    public var trueDriveMode: TrueDriveEmulationMode {
        switch self {
        case .fastLoad: return .off
        case .compat1541: return .compat1541
        case .standard1541: return .standard1541
        }
    }
}

public enum CompatibilityJoystickControl: String, Decodable, Equatable {
    case up
    case down
    case left
    case right
    case fire
}

public enum CompatibilityKey: Equatable, Decodable {
    case space
    case returnKey
    case runStop
    case restore
    case home
    case delete
    case cursorUp
    case cursorDown
    case cursorLeft
    case cursorRight
    case f1
    case f3
    case f5
    case f7
    case leftShift
    case rightShift
    case control
    case commodore

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "/", with: "") {
        case "space": self = .space
        case "return", "enter": self = .returnKey
        case "runstop", "stop": self = .runStop
        case "restore": self = .restore
        case "home", "clearhome": self = .home
        case "delete", "del", "backspace", "instdel": self = .delete
        case "cursorup", "up": self = .cursorUp
        case "cursordown", "down": self = .cursorDown
        case "cursorleft", "left": self = .cursorLeft
        case "cursorright", "right": self = .cursorRight
        case "f1": self = .f1
        case "f3": self = .f3
        case "f5": self = .f5
        case "f7": self = .f7
        case "leftshift", "shift": self = .leftShift
        case "rightshift": self = .rightShift
        case "control", "ctrl": self = .control
        case "commodore", "cbm": self = .commodore
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown compatibility key '\(rawValue)'"
            )
        }
    }
}

public enum CompatibilityAction: Decodable, Equatable {
    case typeText(String)
    case waitCycles(Int)
    case joystickDown(CompatibilityJoystickControl)
    case joystickUp(CompatibilityJoystickControl)
    case keyDown(CompatibilityKey)
    case keyUp(CompatibilityKey)
    case startTape
    case stopTape

    private enum CodingKeys: String, CodingKey {
        case type
        case action
        case text
        case command
        case cycles
        case control
        case button
        case key
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(String.self, forKey: .type)
            ?? container.decode(String.self, forKey: .action)
        switch kind {
        case "text", "typeText":
            let text = try container.decodeIfPresent(String.self, forKey: .text)
                ?? container.decode(String.self, forKey: .command)
            self = .typeText(text)
        case "wait", "waitCycles":
            self = .waitCycles(try container.decode(Int.self, forKey: .cycles))
        case "joystickDown", "joystickPress", "pressJoystick":
            let control = try container.decodeIfPresent(CompatibilityJoystickControl.self, forKey: .control)
                ?? container.decode(CompatibilityJoystickControl.self, forKey: .button)
            self = .joystickDown(control)
        case "joystickUp", "joystickRelease", "releaseJoystick":
            let control = try container.decodeIfPresent(CompatibilityJoystickControl.self, forKey: .control)
                ?? container.decode(CompatibilityJoystickControl.self, forKey: .button)
            self = .joystickUp(control)
        case "keyDown", "keyPress", "pressKey":
            self = .keyDown(try container.decode(CompatibilityKey.self, forKey: .key))
        case "keyUp", "keyRelease", "releaseKey":
            self = .keyUp(try container.decode(CompatibilityKey.self, forKey: .key))
        case "startTape", "tapeStart", "pressPlay", "playTape":
            self = .startTape
        case "stopTape", "tapeStop", "pressStop":
            self = .stopTape
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown compatibility action type '\(kind)'"
            )
        }
    }
}

public struct CompatibilityMilestone: Decodable, Equatable {
    public let file: String
    public let mediaType: CompatibilityMediaType?
    public let machineProfile: CompatibilityMachineProfile?
    public let driveMode: CompatibilityDriveMode?
    public let commands: [String]
    public let actions: [CompatibilityAction]
    public let maxCycles: Int?
    public let pcStart: Int?
    public let pcEnd: Int?
    public let pcRanges: [CompatibilityPCRange]
    public let minGCRReads: Int?
    public let minByteReady: Int?
    public let driveStatus: CompatibilityDriveStatus?
    public let mediaStatus: CompatibilityMediaStatus?
    public let weakBitRanges: [CompatibilityWeakBitRange]
    public let tapeStatus: CompatibilityTapeStatus?
    public let ramSignatures: [CompatibilityRAMSignature]
    public let colorRAMSignatures: [CompatibilityRAMSignature]
    public let cpuRegisters: CompatibilityCPURegisters?
    public let sidRegisters: [CompatibilitySIDRegisterExpectation]
    public let vicRegisters: [CompatibilityVICRegisterExpectation]
    public let cia1Registers: [CompatibilityCIARegisterExpectation]
    public let cia2Registers: [CompatibilityCIARegisterExpectation]
    public let screenTextContains: [String]
    public let screenRAMHash: String?
    public let colorRAMHash: String?
    public let screenshotName: String?

    private enum CodingKeys: String, CodingKey {
        case file
        case mediaType
        case machineProfile
        case driveMode
        case command
        case commands
        case actions
        case maxCycles
        case pcStart
        case pcEnd
        case pcRanges
        case minGCRReads
        case minByteReady
        case driveStatus
        case mediaStatus
        case weakBitRanges
        case tapeStatus
        case ramSignatures
        case colorRAMSignatures
        case cpuRegisters
        case sidRegisters
        case vicRegisters
        case cia1Registers
        case cia2Registers
        case screenTextContains
        case screenRAMHash
        case colorRAMHash
        case screenshotName
    }

    public init(
        file: String,
        mediaType: CompatibilityMediaType? = nil,
        machineProfile: CompatibilityMachineProfile? = nil,
        driveMode: CompatibilityDriveMode? = nil,
        command: String,
        maxCycles: Int? = nil,
        pcStart: Int? = nil,
        pcEnd: Int? = nil,
        pcRanges: [CompatibilityPCRange] = [],
        minGCRReads: Int? = nil,
        minByteReady: Int? = nil,
        driveStatus: CompatibilityDriveStatus? = nil,
        mediaStatus: CompatibilityMediaStatus? = nil,
        weakBitRanges: [CompatibilityWeakBitRange] = [],
        tapeStatus: CompatibilityTapeStatus? = nil,
        ramSignatures: [CompatibilityRAMSignature] = [],
        colorRAMSignatures: [CompatibilityRAMSignature] = [],
        cpuRegisters: CompatibilityCPURegisters? = nil,
        sidRegisters: [CompatibilitySIDRegisterExpectation] = [],
        vicRegisters: [CompatibilityVICRegisterExpectation] = [],
        cia1Registers: [CompatibilityCIARegisterExpectation] = [],
        cia2Registers: [CompatibilityCIARegisterExpectation] = [],
        screenTextContains: [String] = [],
        screenRAMHash: String? = nil,
        colorRAMHash: String? = nil,
        screenshotName: String? = nil
    ) {
        self.file = file
        self.mediaType = mediaType
        self.machineProfile = machineProfile
        self.driveMode = driveMode
        self.commands = [command]
        self.actions = [.typeText(command)]
        self.maxCycles = maxCycles
        self.pcStart = pcStart
        self.pcEnd = pcEnd
        self.pcRanges = pcRanges
        self.minGCRReads = minGCRReads
        self.minByteReady = minByteReady
        self.driveStatus = driveStatus
        self.mediaStatus = mediaStatus
        self.weakBitRanges = weakBitRanges
        self.tapeStatus = tapeStatus
        self.ramSignatures = ramSignatures
        self.colorRAMSignatures = colorRAMSignatures
        self.cpuRegisters = cpuRegisters
        self.sidRegisters = sidRegisters
        self.vicRegisters = vicRegisters
        self.cia1Registers = cia1Registers
        self.cia2Registers = cia2Registers
        self.screenTextContains = screenTextContains
        self.screenRAMHash = screenRAMHash
        self.colorRAMHash = colorRAMHash
        self.screenshotName = screenshotName
    }

    public init(
        file: String,
        mediaType: CompatibilityMediaType? = nil,
        machineProfile: CompatibilityMachineProfile? = nil,
        driveMode: CompatibilityDriveMode? = nil,
        commands: [String],
        actions: [CompatibilityAction]? = nil,
        maxCycles: Int? = nil,
        pcStart: Int? = nil,
        pcEnd: Int? = nil,
        pcRanges: [CompatibilityPCRange] = [],
        minGCRReads: Int? = nil,
        minByteReady: Int? = nil,
        driveStatus: CompatibilityDriveStatus? = nil,
        mediaStatus: CompatibilityMediaStatus? = nil,
        weakBitRanges: [CompatibilityWeakBitRange] = [],
        tapeStatus: CompatibilityTapeStatus? = nil,
        ramSignatures: [CompatibilityRAMSignature] = [],
        colorRAMSignatures: [CompatibilityRAMSignature] = [],
        cpuRegisters: CompatibilityCPURegisters? = nil,
        sidRegisters: [CompatibilitySIDRegisterExpectation] = [],
        vicRegisters: [CompatibilityVICRegisterExpectation] = [],
        cia1Registers: [CompatibilityCIARegisterExpectation] = [],
        cia2Registers: [CompatibilityCIARegisterExpectation] = [],
        screenTextContains: [String] = [],
        screenRAMHash: String? = nil,
        colorRAMHash: String? = nil,
        screenshotName: String? = nil
    ) {
        self.file = file
        self.mediaType = mediaType
        self.machineProfile = machineProfile
        self.driveMode = driveMode
        self.commands = commands
        self.actions = actions ?? commands.map { .typeText($0) }
        self.maxCycles = maxCycles
        self.pcStart = pcStart
        self.pcEnd = pcEnd
        self.pcRanges = pcRanges
        self.minGCRReads = minGCRReads
        self.minByteReady = minByteReady
        self.driveStatus = driveStatus
        self.mediaStatus = mediaStatus
        self.weakBitRanges = weakBitRanges
        self.tapeStatus = tapeStatus
        self.ramSignatures = ramSignatures
        self.colorRAMSignatures = colorRAMSignatures
        self.cpuRegisters = cpuRegisters
        self.sidRegisters = sidRegisters
        self.vicRegisters = vicRegisters
        self.cia1Registers = cia1Registers
        self.cia2Registers = cia2Registers
        self.screenTextContains = screenTextContains
        self.screenRAMHash = screenRAMHash
        self.colorRAMHash = colorRAMHash
        self.screenshotName = screenshotName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        file = try container.decode(String.self, forKey: .file)
        mediaType = try container.decodeIfPresent(CompatibilityMediaType.self, forKey: .mediaType)
        machineProfile = try container.decodeIfPresent(CompatibilityMachineProfile.self, forKey: .machineProfile)
        driveMode = try container.decodeIfPresent(CompatibilityDriveMode.self, forKey: .driveMode)
        let decodedActions = try container.decodeIfPresent([CompatibilityAction].self, forKey: .actions)
        if let commandSequence = try container.decodeIfPresent([String].self, forKey: .commands) {
            guard !commandSequence.isEmpty || decodedActions?.isEmpty == false else {
                throw DecodingError.dataCorruptedError(
                    forKey: .commands,
                    in: container,
                    debugDescription: "Command sequence must not be empty"
                )
            }
            commands = commandSequence
        } else if container.contains(.command) {
            commands = [try container.decode(String.self, forKey: .command)]
        } else if let decodedActions, !decodedActions.isEmpty {
            commands = decodedActions.compactMap { action in
                if case let .typeText(text) = action {
                    return text
                }
                return nil
            }
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.command,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Expected command, commands, or actions"
                )
            )
        }
        actions = decodedActions ?? commands.map { .typeText($0) }
        maxCycles = try container.decodeIfPresent(Int.self, forKey: .maxCycles)
        pcStart = try container.decodeIfPresent(Int.self, forKey: .pcStart)
        pcEnd = try container.decodeIfPresent(Int.self, forKey: .pcEnd)
        pcRanges = try container.decodeIfPresent([CompatibilityPCRange].self, forKey: .pcRanges) ?? []
        minGCRReads = try container.decodeIfPresent(Int.self, forKey: .minGCRReads)
        minByteReady = try container.decodeIfPresent(Int.self, forKey: .minByteReady)
        driveStatus = try container.decodeIfPresent(CompatibilityDriveStatus.self, forKey: .driveStatus)
        mediaStatus = try container.decodeIfPresent(CompatibilityMediaStatus.self, forKey: .mediaStatus)
        weakBitRanges = try container.decodeIfPresent([CompatibilityWeakBitRange].self, forKey: .weakBitRanges) ?? []
        tapeStatus = try container.decodeIfPresent(CompatibilityTapeStatus.self, forKey: .tapeStatus)
        ramSignatures = try container.decodeIfPresent([CompatibilityRAMSignature].self, forKey: .ramSignatures) ?? []
        colorRAMSignatures = try container.decodeIfPresent([CompatibilityRAMSignature].self, forKey: .colorRAMSignatures) ?? []
        cpuRegisters = try container.decodeIfPresent(CompatibilityCPURegisters.self, forKey: .cpuRegisters)
        sidRegisters = try container.decodeIfPresent([CompatibilitySIDRegisterExpectation].self, forKey: .sidRegisters) ?? []
        vicRegisters = try container.decodeIfPresent([CompatibilityVICRegisterExpectation].self, forKey: .vicRegisters) ?? []
        cia1Registers = try container.decodeIfPresent([CompatibilityCIARegisterExpectation].self, forKey: .cia1Registers) ?? []
        cia2Registers = try container.decodeIfPresent([CompatibilityCIARegisterExpectation].self, forKey: .cia2Registers) ?? []
        if let screenText = try? container.decode([String].self, forKey: .screenTextContains) {
            screenTextContains = screenText
        } else if let screenText = try? container.decode(String.self, forKey: .screenTextContains) {
            screenTextContains = [screenText]
        } else {
            screenTextContains = []
        }
        screenRAMHash = try container.decodeIfPresent(String.self, forKey: .screenRAMHash)
        colorRAMHash = try container.decodeIfPresent(String.self, forKey: .colorRAMHash)
        screenshotName = try container.decodeIfPresent(String.self, forKey: .screenshotName)
    }

    public var command: String {
        commands.first ?? ""
    }

    public var pcRange: ClosedRange<UInt16>? {
        guard let pcStart,
              let pcEnd,
              let start = UInt16(exactly: pcStart),
              let end = UInt16(exactly: pcEnd),
              start <= end else {
            return nil
        }
        return start...end
    }

    public var expectedPCRanges: [ClosedRange<UInt16>] {
        var ranges = pcRanges.map(\.range)
        if let pcRange {
            ranges.append(pcRange)
        }
        return ranges
    }
}

public struct CompatibilityPCRange: Decodable, Equatable {
    public let start: Int
    public let end: Int

    public var range: ClosedRange<UInt16> {
        UInt16(start)...UInt16(end)
    }

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    private enum CodingKeys: String, CodingKey {
        case start
        case end
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(Int.self, forKey: .start)
        end = try container.decode(Int.self, forKey: .end)
        guard start >= 0, end <= 0xFFFF, start <= end else {
            throw DecodingError.dataCorruptedError(
                forKey: .start,
                in: container,
                debugDescription: "PC range must be ordered and fit in 16 bits"
            )
        }
    }
}

public struct CompatibilityWeakBitRange: Decodable, Equatable {
    public let halfTrack: Int
    public let startBit: Int
    public let endBit: Int

    public var diskRange: DiskImage.Track.WeakBitRange {
        DiskImage.Track.WeakBitRange(startBit: startBit, endBit: endBit)
    }

    public init(halfTrack: Int, startBit: Int, endBit: Int) {
        self.halfTrack = halfTrack
        self.startBit = startBit
        self.endBit = endBit
    }

    private enum CodingKeys: String, CodingKey {
        case halfTrack
        case startBit
        case endBit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        halfTrack = try container.decode(Int.self, forKey: .halfTrack)
        startBit = try container.decode(Int.self, forKey: .startBit)
        endBit = try container.decode(Int.self, forKey: .endBit)
        guard halfTrack >= 0 && halfTrack < GCRDisk.maxHalfTracks else {
            throw DecodingError.dataCorruptedError(
                forKey: .halfTrack,
                in: container,
                debugDescription: "Weak-bit halftrack must be in the GCR halftrack table"
            )
        }
        guard startBit >= 0 && startBit <= endBit else {
            throw DecodingError.dataCorruptedError(
                forKey: .startBit,
                in: container,
                debugDescription: "Weak-bit range must be ordered and non-negative"
            )
        }
    }
}

public struct CompatibilityMediaStatus: Decodable, Equatable {
    public let populatedHalfTrackCount: Int?
    public let nativeLowLevelTrackCount: Int?
    public let syntheticGCRTrackCount: Int?
    public let hasSyntheticGCR: Bool?
    public let isNativeLowLevel: Bool?
    public let preservesHalfTracks: Bool?
    public let preservesRawTrackLengths: Bool?
    public let preservesSpeedZones: Bool?
    public let preservesVariableSpeedZones: Bool?
    public let preservesSectorErrorInfo: Bool?
    public let sectorErrorCodeCount: Int?
    public let nonDefaultSectorErrorCodeCount: Int?
    public let weakBitRangeCount: Int?
    public let weakBitTotalBitCount: Int?
    public let variableSpeedZoneByteCount: Int?
    public let supportsWraparoundReads: Bool?
    public let maxTrackSize: Int?
    public let unsupportedFeaturesContains: [String]

    private enum CodingKeys: String, CodingKey {
        case populatedHalfTrackCount
        case nativeLowLevelTrackCount
        case syntheticGCRTrackCount
        case hasSyntheticGCR
        case isNativeLowLevel
        case preservesHalfTracks
        case preservesRawTrackLengths
        case preservesSpeedZones
        case preservesVariableSpeedZones
        case preservesSectorErrorInfo
        case sectorErrorCodeCount
        case nonDefaultSectorErrorCodeCount
        case weakBitRangeCount
        case weakBitTotalBitCount
        case variableSpeedZoneByteCount
        case supportsWraparoundReads
        case maxTrackSize
        case unsupportedFeaturesContains
    }

    public init(
        populatedHalfTrackCount: Int? = nil,
        nativeLowLevelTrackCount: Int? = nil,
        syntheticGCRTrackCount: Int? = nil,
        hasSyntheticGCR: Bool? = nil,
        isNativeLowLevel: Bool? = nil,
        preservesHalfTracks: Bool? = nil,
        preservesRawTrackLengths: Bool? = nil,
        preservesSpeedZones: Bool? = nil,
        preservesVariableSpeedZones: Bool? = nil,
        preservesSectorErrorInfo: Bool? = nil,
        sectorErrorCodeCount: Int? = nil,
        nonDefaultSectorErrorCodeCount: Int? = nil,
        weakBitRangeCount: Int? = nil,
        weakBitTotalBitCount: Int? = nil,
        variableSpeedZoneByteCount: Int? = nil,
        supportsWraparoundReads: Bool? = nil,
        maxTrackSize: Int? = nil,
        unsupportedFeaturesContains: [String] = []
    ) {
        self.populatedHalfTrackCount = populatedHalfTrackCount
        self.nativeLowLevelTrackCount = nativeLowLevelTrackCount
        self.syntheticGCRTrackCount = syntheticGCRTrackCount
        self.hasSyntheticGCR = hasSyntheticGCR
        self.isNativeLowLevel = isNativeLowLevel
        self.preservesHalfTracks = preservesHalfTracks
        self.preservesRawTrackLengths = preservesRawTrackLengths
        self.preservesSpeedZones = preservesSpeedZones
        self.preservesVariableSpeedZones = preservesVariableSpeedZones
        self.preservesSectorErrorInfo = preservesSectorErrorInfo
        self.sectorErrorCodeCount = sectorErrorCodeCount
        self.nonDefaultSectorErrorCodeCount = nonDefaultSectorErrorCodeCount
        self.weakBitRangeCount = weakBitRangeCount
        self.weakBitTotalBitCount = weakBitTotalBitCount
        self.variableSpeedZoneByteCount = variableSpeedZoneByteCount
        self.supportsWraparoundReads = supportsWraparoundReads
        self.maxTrackSize = maxTrackSize
        self.unsupportedFeaturesContains = unsupportedFeaturesContains
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        populatedHalfTrackCount = try container.decodeIfPresent(Int.self, forKey: .populatedHalfTrackCount)
        nativeLowLevelTrackCount = try container.decodeIfPresent(Int.self, forKey: .nativeLowLevelTrackCount)
        syntheticGCRTrackCount = try container.decodeIfPresent(Int.self, forKey: .syntheticGCRTrackCount)
        hasSyntheticGCR = try container.decodeIfPresent(Bool.self, forKey: .hasSyntheticGCR)
        isNativeLowLevel = try container.decodeIfPresent(Bool.self, forKey: .isNativeLowLevel)
        preservesHalfTracks = try container.decodeIfPresent(Bool.self, forKey: .preservesHalfTracks)
        preservesRawTrackLengths = try container.decodeIfPresent(Bool.self, forKey: .preservesRawTrackLengths)
        preservesSpeedZones = try container.decodeIfPresent(Bool.self, forKey: .preservesSpeedZones)
        preservesVariableSpeedZones = try container.decodeIfPresent(Bool.self, forKey: .preservesVariableSpeedZones)
        preservesSectorErrorInfo = try container.decodeIfPresent(Bool.self, forKey: .preservesSectorErrorInfo)
        sectorErrorCodeCount = try container.decodeIfPresent(Int.self, forKey: .sectorErrorCodeCount)
        nonDefaultSectorErrorCodeCount = try container.decodeIfPresent(Int.self, forKey: .nonDefaultSectorErrorCodeCount)
        weakBitRangeCount = try container.decodeIfPresent(Int.self, forKey: .weakBitRangeCount)
        weakBitTotalBitCount = try container.decodeIfPresent(Int.self, forKey: .weakBitTotalBitCount)
        variableSpeedZoneByteCount = try container.decodeIfPresent(Int.self, forKey: .variableSpeedZoneByteCount)
        supportsWraparoundReads = try container.decodeIfPresent(Bool.self, forKey: .supportsWraparoundReads)
        maxTrackSize = try container.decodeIfPresent(Int.self, forKey: .maxTrackSize)
        unsupportedFeaturesContains = try container.decodeIfPresent([String].self, forKey: .unsupportedFeaturesContains) ?? []
    }
}

public struct CompatibilityTapeStatus: Decodable, Equatable {
    public let mountedTapeNameContains: String?
    public let decodeStatus: CompatibilityTapeDecodeStatusKind?
    public let pulseCount: Int?
    public let programCount: Int?
    public let blockCount: Int?
    public let decodeFailureReason: CompatibilityTapeDecodeFailureReason?
    public let rawPlaybackActive: Bool?
    public let readSignalHigh: Bool?
    public let cassetteSenseLineHigh: Bool?
    public let cassetteMotorEnabled: Bool?
    public let hasCapturedWritePulses: Bool?
    public let canExportCapturedTAP: Bool?
    public let hasUnsavedChanges: Bool?
    public let canExportSavedT64: Bool?

    public init(
        mountedTapeNameContains: String? = nil,
        decodeStatus: CompatibilityTapeDecodeStatusKind? = nil,
        pulseCount: Int? = nil,
        programCount: Int? = nil,
        blockCount: Int? = nil,
        decodeFailureReason: CompatibilityTapeDecodeFailureReason? = nil,
        rawPlaybackActive: Bool? = nil,
        readSignalHigh: Bool? = nil,
        cassetteSenseLineHigh: Bool? = nil,
        cassetteMotorEnabled: Bool? = nil,
        hasCapturedWritePulses: Bool? = nil,
        canExportCapturedTAP: Bool? = nil,
        hasUnsavedChanges: Bool? = nil,
        canExportSavedT64: Bool? = nil
    ) {
        self.mountedTapeNameContains = mountedTapeNameContains
        self.decodeStatus = decodeStatus
        self.pulseCount = pulseCount
        self.programCount = programCount
        self.blockCount = blockCount
        self.decodeFailureReason = decodeFailureReason
        self.rawPlaybackActive = rawPlaybackActive
        self.readSignalHigh = readSignalHigh
        self.cassetteSenseLineHigh = cassetteSenseLineHigh
        self.cassetteMotorEnabled = cassetteMotorEnabled
        self.hasCapturedWritePulses = hasCapturedWritePulses
        self.canExportCapturedTAP = canExportCapturedTAP
        self.hasUnsavedChanges = hasUnsavedChanges
        self.canExportSavedT64 = canExportSavedT64
    }
}

public enum CompatibilityTapeDecodeStatusKind: String, Decodable, Equatable {
    case none
    case rawPulsesOnly
    case decodedPrograms
    case standardCBMNoPrograms
}

public enum CompatibilityTapeDecodeFailureReason: String, Decodable, Equatable {
    case noStandardBlocks
    case malformedStandardBlocks
    case incompleteHeaderData
    case conflictingDuplicateData
}

public struct CompatibilityDriveStatus: Decodable, Equatable {
    public let minGCRReads: Int?
    public let minByteReady: Int?
    public let minSyncDetections: Int?
    public let minWeakBitReads: Int?
    public let track: Int?
    public let halfTrack: Int?
    public let readTrack: Int?
    public let readHalfTrack: Int?
    public let usingHalfTrackFallback: Bool?
    public let motorOn: Bool?
    public let ledOn: Bool?
    public let writeProtected: Bool?
    public let hasDisk: Bool?
    public let mediaChanged: Bool?
    public let minMediaChangeCount: Int?
    public let hasNativeLowLevelImage: Bool?
    public let lastIECCommandContains: String?

    public init(
        minGCRReads: Int? = nil,
        minByteReady: Int? = nil,
        minSyncDetections: Int? = nil,
        minWeakBitReads: Int? = nil,
        track: Int? = nil,
        halfTrack: Int? = nil,
        readTrack: Int? = nil,
        readHalfTrack: Int? = nil,
        usingHalfTrackFallback: Bool? = nil,
        motorOn: Bool? = nil,
        ledOn: Bool? = nil,
        writeProtected: Bool? = nil,
        hasDisk: Bool? = nil,
        mediaChanged: Bool? = nil,
        minMediaChangeCount: Int? = nil,
        hasNativeLowLevelImage: Bool? = nil,
        lastIECCommandContains: String? = nil
    ) {
        self.minGCRReads = minGCRReads
        self.minByteReady = minByteReady
        self.minSyncDetections = minSyncDetections
        self.minWeakBitReads = minWeakBitReads
        self.track = track
        self.halfTrack = halfTrack
        self.readTrack = readTrack
        self.readHalfTrack = readHalfTrack
        self.usingHalfTrackFallback = usingHalfTrackFallback
        self.motorOn = motorOn
        self.ledOn = ledOn
        self.writeProtected = writeProtected
        self.hasDisk = hasDisk
        self.mediaChanged = mediaChanged
        self.minMediaChangeCount = minMediaChangeCount
        self.hasNativeLowLevelImage = hasNativeLowLevelImage
        self.lastIECCommandContains = lastIECCommandContains
    }
}

public struct CompatibilityRAMSignature: Decodable, Equatable {
    public let address: Int
    public let bytes: [UInt8]

    public init(address: Int, bytes: [UInt8]) {
        self.address = address
        self.bytes = bytes
    }

    private enum CodingKeys: String, CodingKey {
        case address
        case bytes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(Int.self, forKey: .address)
        if let byteValues = try? container.decode([UInt8].self, forKey: .bytes) {
            bytes = byteValues
        } else {
            let hex = try container.decode(String.self, forKey: .bytes)
            bytes = try Self.decodeHexBytes(hex)
        }
    }

    static func decodeHexBytes(_ value: String) throws -> [UInt8] {
        let compact = value.filter { !$0.isWhitespace && $0 != "," && $0 != "$" }
        guard compact.count % 2 == 0 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Hex byte string must contain an even number of digits")
            )
        }

        var result: [UInt8] = []
        var index = compact.startIndex
        while index < compact.endIndex {
            let next = compact.index(index, offsetBy: 2)
            guard let byte = UInt8(compact[index..<next], radix: 16) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: [], debugDescription: "Invalid hex byte in RAM signature")
                )
            }
            result.append(byte)
            index = next
        }
        return result
    }
}

public struct CompatibilityCPURegisters: Decodable, Equatable {
    public let pc: Int?
    public let a: UInt8?
    public let x: UInt8?
    public let y: UInt8?
    public let sp: UInt8?
    public let p: UInt8?
    public let pMask: UInt8

    public init(
        pc: Int? = nil,
        a: UInt8? = nil,
        x: UInt8? = nil,
        y: UInt8? = nil,
        sp: UInt8? = nil,
        p: UInt8? = nil,
        pMask: UInt8 = 0xFF
    ) {
        self.pc = pc
        self.a = a
        self.x = x
        self.y = y
        self.sp = sp
        self.p = p
        self.pMask = pMask
    }

    private enum CodingKeys: String, CodingKey {
        case pc
        case a
        case x
        case y
        case sp
        case p
        case status
        case pMask
        case statusMask
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pc = try Self.decodeOptional16(forKey: .pc, in: container)
        a = try Self.decodeOptional8(forKey: .a, in: container)
        x = try Self.decodeOptional8(forKey: .x, in: container)
        y = try Self.decodeOptional8(forKey: .y, in: container)
        sp = try Self.decodeOptional8(forKey: .sp, in: container)

        if container.contains(.p) {
            p = try Self.decodeOptional8(forKey: .p, in: container)
        } else {
            p = try Self.decodeOptional8(forKey: .status, in: container)
        }

        let decodedMask: UInt8?
        if container.contains(.pMask) {
            decodedMask = try Self.decodeOptional8(forKey: .pMask, in: container)
        } else {
            decodedMask = try Self.decodeOptional8(forKey: .statusMask, in: container)
        }
        pMask = decodedMask ?? 0xFF
    }

    private static func decodeOptional16<K: CodingKey>(
        forKey key: K,
        in container: KeyedDecodingContainer<K>
    ) throws -> Int? {
        guard container.contains(key) else { return nil }
        let value = try decodeInteger(forKey: key, in: container)
        guard (0...0xFFFF).contains(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "CPU register value must fit in 16 bits"
            )
        }
        return value
    }

    private static func decodeOptional8<K: CodingKey>(
        forKey key: K,
        in container: KeyedDecodingContainer<K>
    ) throws -> UInt8? {
        guard container.contains(key) else { return nil }
        let value = try decodeInteger(forKey: key, in: container)
        guard (0...0xFF).contains(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "CPU register value must fit in 8 bits"
            )
        }
        return UInt8(value)
    }

    private static func decodeInteger<K: CodingKey>(forKey key: K, in container: KeyedDecodingContainer<K>) throws -> Int {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        let rawValue = try container.decode(String.self, forKey: key)
        let compact = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
        guard let value = Int(compact, radix: 16) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Expected decimal integer or hexadecimal string"
            )
        }
        return value
    }
}

public struct CompatibilitySIDRegisterExpectation: Decodable, Equatable {
    public let register: Int
    public let value: UInt8
    public let mask: UInt8

    public init(register: Int, value: UInt8, mask: UInt8 = 0xFF) {
        self.register = register
        self.value = value
        self.mask = mask
    }

    private enum CodingKeys: String, CodingKey {
        case register
        case value
        case mask
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        register = try Self.decodeInteger(forKey: .register, in: container)
        let decodedValue = try Self.decodeInteger(forKey: .value, in: container)
        let decodedMask: Int
        if container.contains(.mask) {
            decodedMask = try Self.decodeInteger(forKey: .mask, in: container)
        } else {
            decodedMask = 0xFF
        }

        guard (0...0xFFFF).contains(register) else {
            throw DecodingError.dataCorruptedError(
                forKey: .register,
                in: container,
                debugDescription: "SID register must fit in 16 bits"
            )
        }
        guard (0...0xFF).contains(decodedValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "SID register value must fit in 8 bits"
            )
        }
        guard (0...0xFF).contains(decodedMask) else {
            throw DecodingError.dataCorruptedError(
                forKey: .mask,
                in: container,
                debugDescription: "SID register mask must fit in 8 bits"
            )
        }

        value = UInt8(decodedValue)
        mask = UInt8(decodedMask)
    }

    private static func decodeInteger<K: CodingKey>(forKey key: K, in container: KeyedDecodingContainer<K>) throws -> Int {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        let rawValue = try container.decode(String.self, forKey: key)
        let compact = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
        guard let value = Int(compact, radix: 16) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Expected decimal integer or hexadecimal string"
            )
        }
        return value
    }
}

public struct CompatibilityVICRegisterExpectation: Decodable, Equatable {
    public let register: Int
    public let value: UInt8
    public let mask: UInt8

    public init(register: Int, value: UInt8, mask: UInt8 = 0xFF) {
        self.register = register
        self.value = value
        self.mask = mask
    }

    public init(from decoder: Decoder) throws {
        let expectation = try CompatibilitySIDRegisterExpectation(from: decoder)
        register = expectation.register
        value = expectation.value
        mask = expectation.mask
    }
}

public struct CompatibilityCIARegisterExpectation: Decodable, Equatable {
    public let register: Int
    public let value: UInt8
    public let mask: UInt8

    public init(register: Int, value: UInt8, mask: UInt8 = 0xFF) {
        self.register = register
        self.value = value
        self.mask = mask
    }

    public init(from decoder: Decoder) throws {
        let expectation = try CompatibilitySIDRegisterExpectation(from: decoder)
        register = expectation.register
        value = expectation.value
        mask = expectation.mask
    }
}

public enum CompatibilityHash {
    public static func screenRAM(_ ram: [UInt8]) -> String {
        let start = 0x0400
        let end = min(ram.count, start + 1000)
        return fnv1a64(ram[start..<end])
    }

    public static func colorRAM(_ colorRAM: [UInt8]) -> String {
        let end = min(colorRAM.count, 1000)
        return fnv1a64(colorRAM[..<end].map { $0 & 0x0F })
    }

    static func fnv1a64<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
