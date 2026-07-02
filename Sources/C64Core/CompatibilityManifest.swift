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
    case nib
    case nbz
    case p64
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

public enum CompatibilityFailureCategory: String, Decodable, Equatable {
    case cpu
    case drive
    case media
    case protectedMedia
    case cartridge
    case app
    case pc
    case ram
    case screen
    case tape
    case video
    case audio
    case cia
    case emulator
    case timeout
}

public struct CompatibilityExpectedFailure: Decodable, Equatable {
    public let category: CompatibilityFailureCategory
    public let reasonContains: [String]
    public let note: String?

    private enum CodingKeys: String, CodingKey {
        case category
        case reasonContains
        case reason
        case note
    }

    public init(
        category: CompatibilityFailureCategory,
        reasonContains: [String] = [],
        note: String? = nil
    ) {
        self.category = category
        self.reasonContains = reasonContains
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decode(CompatibilityFailureCategory.self, forKey: .category)
        if let reasonList = try? container.decode([String].self, forKey: .reasonContains) {
            reasonContains = reasonList
        } else if let reason = try? container.decode(String.self, forKey: .reasonContains) {
            reasonContains = [reason]
        } else if let reason = try? container.decode(String.self, forKey: .reason) {
            reasonContains = [reason]
        } else {
            reasonContains = []
        }
        note = try container.decodeIfPresent(String.self, forKey: .note)
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
    public let id: String?
    public let name: String?
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
    public let speedZoneRanges: [CompatibilitySpeedZoneRange]
    public let tapeStatus: CompatibilityTapeStatus?
    public let ramSignatures: [CompatibilityRAMSignature]
    public let colorRAMSignatures: [CompatibilityRAMSignature]
    public let cpuRegisters: CompatibilityCPURegisters?
    public let sidModel: SID.Model?
    public let sidAccuracyMode: SID.AccuracyMode?
    public let sidRegisters: [CompatibilitySIDRegisterExpectation]
    public let sidAudioSignature: CompatibilitySIDAudioSignature?
    public let sidAudioState: CompatibilitySIDAudioState?
    public let sidVoiceStates: [CompatibilitySIDVoiceState]
    public let vicRegisters: [CompatibilityVICRegisterExpectation]
    public let cia1Registers: [CompatibilityCIARegisterExpectation]
    public let cia2Registers: [CompatibilityCIARegisterExpectation]
    public let screenTextContains: [String]
    public let screenRAMHash: String?
    public let colorRAMHash: String?
    public let framebufferHash: String?
    public let screenshotName: String?
    public let expectedFailure: CompatibilityExpectedFailure?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
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
        case speedZoneRanges
        case tapeStatus
        case ramSignatures
        case colorRAMSignatures
        case cpuRegisters
        case sidModel
        case sidAccuracyMode
        case sidRegisters
        case sidAudioSignature
        case sidAudioState
        case sidVoiceStates
        case vicRegisters
        case cia1Registers
        case cia2Registers
        case screenTextContains
        case screenRAMHash
        case colorRAMHash
        case framebufferHash
        case screenshotName
        case expectedFailure
    }

    public init(
        id: String? = nil,
        name: String? = nil,
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
        speedZoneRanges: [CompatibilitySpeedZoneRange] = [],
        tapeStatus: CompatibilityTapeStatus? = nil,
        ramSignatures: [CompatibilityRAMSignature] = [],
        colorRAMSignatures: [CompatibilityRAMSignature] = [],
        cpuRegisters: CompatibilityCPURegisters? = nil,
        sidModel: SID.Model? = nil,
        sidAccuracyMode: SID.AccuracyMode? = nil,
        sidRegisters: [CompatibilitySIDRegisterExpectation] = [],
        sidAudioSignature: CompatibilitySIDAudioSignature? = nil,
        sidAudioState: CompatibilitySIDAudioState? = nil,
        sidVoiceStates: [CompatibilitySIDVoiceState] = [],
        vicRegisters: [CompatibilityVICRegisterExpectation] = [],
        cia1Registers: [CompatibilityCIARegisterExpectation] = [],
        cia2Registers: [CompatibilityCIARegisterExpectation] = [],
        screenTextContains: [String] = [],
        screenRAMHash: String? = nil,
        colorRAMHash: String? = nil,
        framebufferHash: String? = nil,
        screenshotName: String? = nil,
        expectedFailure: CompatibilityExpectedFailure? = nil
    ) {
        self.id = id
        self.name = name
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
        self.speedZoneRanges = speedZoneRanges
        self.tapeStatus = tapeStatus
        self.ramSignatures = ramSignatures
        self.colorRAMSignatures = colorRAMSignatures
        self.cpuRegisters = cpuRegisters
        self.sidModel = sidModel
        self.sidAccuracyMode = sidAccuracyMode
        self.sidRegisters = sidRegisters
        self.sidAudioSignature = sidAudioSignature
        self.sidAudioState = sidAudioState
        self.sidVoiceStates = sidVoiceStates
        self.vicRegisters = vicRegisters
        self.cia1Registers = cia1Registers
        self.cia2Registers = cia2Registers
        self.screenTextContains = screenTextContains
        self.screenRAMHash = screenRAMHash
        self.colorRAMHash = colorRAMHash
        self.framebufferHash = framebufferHash
        self.screenshotName = screenshotName
        self.expectedFailure = expectedFailure
    }

    public init(
        id: String? = nil,
        name: String? = nil,
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
        speedZoneRanges: [CompatibilitySpeedZoneRange] = [],
        tapeStatus: CompatibilityTapeStatus? = nil,
        ramSignatures: [CompatibilityRAMSignature] = [],
        colorRAMSignatures: [CompatibilityRAMSignature] = [],
        cpuRegisters: CompatibilityCPURegisters? = nil,
        sidModel: SID.Model? = nil,
        sidAccuracyMode: SID.AccuracyMode? = nil,
        sidRegisters: [CompatibilitySIDRegisterExpectation] = [],
        sidAudioSignature: CompatibilitySIDAudioSignature? = nil,
        sidAudioState: CompatibilitySIDAudioState? = nil,
        sidVoiceStates: [CompatibilitySIDVoiceState] = [],
        vicRegisters: [CompatibilityVICRegisterExpectation] = [],
        cia1Registers: [CompatibilityCIARegisterExpectation] = [],
        cia2Registers: [CompatibilityCIARegisterExpectation] = [],
        screenTextContains: [String] = [],
        screenRAMHash: String? = nil,
        colorRAMHash: String? = nil,
        framebufferHash: String? = nil,
        screenshotName: String? = nil,
        expectedFailure: CompatibilityExpectedFailure? = nil
    ) {
        self.id = id
        self.name = name
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
        self.speedZoneRanges = speedZoneRanges
        self.tapeStatus = tapeStatus
        self.ramSignatures = ramSignatures
        self.colorRAMSignatures = colorRAMSignatures
        self.cpuRegisters = cpuRegisters
        self.sidModel = sidModel
        self.sidAccuracyMode = sidAccuracyMode
        self.sidRegisters = sidRegisters
        self.sidAudioSignature = sidAudioSignature
        self.sidAudioState = sidAudioState
        self.sidVoiceStates = sidVoiceStates
        self.vicRegisters = vicRegisters
        self.cia1Registers = cia1Registers
        self.cia2Registers = cia2Registers
        self.screenTextContains = screenTextContains
        self.screenRAMHash = screenRAMHash
        self.colorRAMHash = colorRAMHash
        self.framebufferHash = framebufferHash
        self.screenshotName = screenshotName
        self.expectedFailure = expectedFailure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
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
        speedZoneRanges = try container.decodeIfPresent([CompatibilitySpeedZoneRange].self, forKey: .speedZoneRanges) ?? []
        tapeStatus = try container.decodeIfPresent(CompatibilityTapeStatus.self, forKey: .tapeStatus)
        ramSignatures = try container.decodeIfPresent([CompatibilityRAMSignature].self, forKey: .ramSignatures) ?? []
        colorRAMSignatures = try container.decodeIfPresent([CompatibilityRAMSignature].self, forKey: .colorRAMSignatures) ?? []
        cpuRegisters = try container.decodeIfPresent(CompatibilityCPURegisters.self, forKey: .cpuRegisters)
        sidModel = try container.decodeIfPresent(SID.Model.self, forKey: .sidModel)
        sidAccuracyMode = try container.decodeIfPresent(SID.AccuracyMode.self, forKey: .sidAccuracyMode)
        sidRegisters = try container.decodeIfPresent([CompatibilitySIDRegisterExpectation].self, forKey: .sidRegisters) ?? []
        sidAudioSignature = try container.decodeIfPresent(CompatibilitySIDAudioSignature.self, forKey: .sidAudioSignature)
        sidAudioState = try container.decodeIfPresent(CompatibilitySIDAudioState.self, forKey: .sidAudioState)
        sidVoiceStates = try container.decodeIfPresent([CompatibilitySIDVoiceState].self, forKey: .sidVoiceStates) ?? []
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
        framebufferHash = try container.decodeIfPresent(String.self, forKey: .framebufferHash)
        screenshotName = try container.decodeIfPresent(String.self, forKey: .screenshotName)
        expectedFailure = try container.decodeIfPresent(CompatibilityExpectedFailure.self, forKey: .expectedFailure)
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

public struct CompatibilitySpeedZoneRange: Decodable, Equatable {
    public let halfTrack: Int
    public let startByte: Int
    public let endByte: Int
    public let zone: Int

    public var diskRange: DiskImage.Track.SpeedZoneRange {
        DiskImage.Track.SpeedZoneRange(startByte: startByte, endByte: endByte, zone: UInt8(clamping: zone))
    }

    public init(halfTrack: Int, startByte: Int, endByte: Int, zone: Int) {
        self.halfTrack = halfTrack
        self.startByte = startByte
        self.endByte = endByte
        self.zone = zone
    }

    private enum CodingKeys: String, CodingKey {
        case halfTrack
        case startByte
        case endByte
        case zone
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        halfTrack = try container.decode(Int.self, forKey: .halfTrack)
        startByte = try container.decode(Int.self, forKey: .startByte)
        endByte = try container.decode(Int.self, forKey: .endByte)
        zone = try container.decode(Int.self, forKey: .zone)
        guard halfTrack >= 0 && halfTrack < GCRDisk.maxHalfTracks else {
            throw DecodingError.dataCorruptedError(
                forKey: .halfTrack,
                in: container,
                debugDescription: "Speed-zone halftrack must be in the GCR halftrack table"
            )
        }
        guard startByte >= 0 && startByte <= endByte else {
            throw DecodingError.dataCorruptedError(
                forKey: .startByte,
                in: container,
                debugDescription: "Speed-zone byte range must be ordered and non-negative"
            )
        }
        guard (0...3).contains(zone) else {
            throw DecodingError.dataCorruptedError(
                forKey: .zone,
                in: container,
                debugDescription: "Speed-zone value must be 0...3"
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
    public let preservesWeakBitRanges: Bool?
    public let sectorErrorCodeCount: Int?
    public let nonDefaultSectorErrorCodeCount: Int?
    public let weakBitRangeCount: Int?
    public let weakBitTotalBitCount: Int?
    public let hasDuplicateSectorHeaders: Bool?
    public let duplicateSectorHeaderCount: Int?
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
        case preservesWeakBitRanges
        case sectorErrorCodeCount
        case nonDefaultSectorErrorCodeCount
        case weakBitRangeCount
        case weakBitTotalBitCount
        case hasDuplicateSectorHeaders
        case duplicateSectorHeaderCount
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
        preservesWeakBitRanges: Bool? = nil,
        sectorErrorCodeCount: Int? = nil,
        nonDefaultSectorErrorCodeCount: Int? = nil,
        weakBitRangeCount: Int? = nil,
        weakBitTotalBitCount: Int? = nil,
        hasDuplicateSectorHeaders: Bool? = nil,
        duplicateSectorHeaderCount: Int? = nil,
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
        self.preservesWeakBitRanges = preservesWeakBitRanges
        self.sectorErrorCodeCount = sectorErrorCodeCount
        self.nonDefaultSectorErrorCodeCount = nonDefaultSectorErrorCodeCount
        self.weakBitRangeCount = weakBitRangeCount
        self.weakBitTotalBitCount = weakBitTotalBitCount
        self.hasDuplicateSectorHeaders = hasDuplicateSectorHeaders
        self.duplicateSectorHeaderCount = duplicateSectorHeaderCount
        self.variableSpeedZoneByteCount = variableSpeedZoneByteCount
        self.supportsWraparoundReads = supportsWraparoundReads
        self.maxTrackSize = maxTrackSize
        self.unsupportedFeaturesContains = unsupportedFeaturesContains
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        populatedHalfTrackCount = try Self.decodeNonNegativeIfPresent(container, forKey: .populatedHalfTrackCount)
        nativeLowLevelTrackCount = try Self.decodeNonNegativeIfPresent(container, forKey: .nativeLowLevelTrackCount)
        syntheticGCRTrackCount = try Self.decodeNonNegativeIfPresent(container, forKey: .syntheticGCRTrackCount)
        hasSyntheticGCR = try container.decodeIfPresent(Bool.self, forKey: .hasSyntheticGCR)
        isNativeLowLevel = try container.decodeIfPresent(Bool.self, forKey: .isNativeLowLevel)
        preservesHalfTracks = try container.decodeIfPresent(Bool.self, forKey: .preservesHalfTracks)
        preservesRawTrackLengths = try container.decodeIfPresent(Bool.self, forKey: .preservesRawTrackLengths)
        preservesSpeedZones = try container.decodeIfPresent(Bool.self, forKey: .preservesSpeedZones)
        preservesVariableSpeedZones = try container.decodeIfPresent(Bool.self, forKey: .preservesVariableSpeedZones)
        preservesSectorErrorInfo = try container.decodeIfPresent(Bool.self, forKey: .preservesSectorErrorInfo)
        preservesWeakBitRanges = try container.decodeIfPresent(Bool.self, forKey: .preservesWeakBitRanges)
        sectorErrorCodeCount = try Self.decodeNonNegativeIfPresent(container, forKey: .sectorErrorCodeCount)
        nonDefaultSectorErrorCodeCount = try Self.decodeNonNegativeIfPresent(container, forKey: .nonDefaultSectorErrorCodeCount)
        weakBitRangeCount = try Self.decodeNonNegativeIfPresent(container, forKey: .weakBitRangeCount)
        weakBitTotalBitCount = try Self.decodeNonNegativeIfPresent(container, forKey: .weakBitTotalBitCount)
        hasDuplicateSectorHeaders = try container.decodeIfPresent(Bool.self, forKey: .hasDuplicateSectorHeaders)
        duplicateSectorHeaderCount = try Self.decodeNonNegativeIfPresent(container, forKey: .duplicateSectorHeaderCount)
        variableSpeedZoneByteCount = try Self.decodeNonNegativeIfPresent(container, forKey: .variableSpeedZoneByteCount)
        supportsWraparoundReads = try container.decodeIfPresent(Bool.self, forKey: .supportsWraparoundReads)
        maxTrackSize = try Self.decodeNonNegativeIfPresent(container, forKey: .maxTrackSize)
        unsupportedFeaturesContains = try container.decodeIfPresent([String].self, forKey: .unsupportedFeaturesContains) ?? []
    }

    private static func decodeNonNegativeIfPresent(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Int? {
        guard let value = try container.decodeIfPresent(Int.self, forKey: key) else {
            return nil
        }
        guard value >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "\(key.stringValue) must be non-negative"
            )
        }
        return value
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
    public let minVariableSpeedZoneSamples: Int?
    public let minGCRWrites: Int?
    public let minGCRWriteSplices: Int?
    public let minGCRWriteEraseBits: Int?
    public let requiredVariableSpeedZones: [Int]
    public let track: Int?
    public let halfTrack: Int?
    public let headBitPosition: Int?
    public let readTrack: Int?
    public let readHalfTrack: Int?
    public let usingHalfTrackFallback: Bool?
    public let motorOn: Bool?
    public let ledOn: Bool?
    public let gcrWriteModeActive: Bool?
    public let writeProtected: Bool?
    public let hasDisk: Bool?
    public let mediaChanged: Bool?
    public let minMediaChangeCount: Int?
    public let hasNativeLowLevelImage: Bool?
    public let d64ExportBlockedByLowLevelWrites: Bool?
    public let lastIECCommandContains: String?

    private enum CodingKeys: String, CodingKey {
        case minGCRReads
        case minByteReady
        case minSyncDetections
        case minWeakBitReads
        case minVariableSpeedZoneSamples
        case minGCRWrites
        case minGCRWriteSplices
        case minGCRWriteEraseBits
        case requiredVariableSpeedZones
        case track
        case halfTrack
        case headBitPosition
        case readTrack
        case readHalfTrack
        case usingHalfTrackFallback
        case motorOn
        case ledOn
        case gcrWriteModeActive
        case writeProtected
        case hasDisk
        case mediaChanged
        case minMediaChangeCount
        case hasNativeLowLevelImage
        case d64ExportBlockedByLowLevelWrites
        case lastIECCommandContains
    }

    public init(
        minGCRReads: Int? = nil,
        minByteReady: Int? = nil,
        minSyncDetections: Int? = nil,
        minWeakBitReads: Int? = nil,
        minVariableSpeedZoneSamples: Int? = nil,
        minGCRWrites: Int? = nil,
        minGCRWriteSplices: Int? = nil,
        minGCRWriteEraseBits: Int? = nil,
        requiredVariableSpeedZones: [Int] = [],
        track: Int? = nil,
        halfTrack: Int? = nil,
        headBitPosition: Int? = nil,
        readTrack: Int? = nil,
        readHalfTrack: Int? = nil,
        usingHalfTrackFallback: Bool? = nil,
        motorOn: Bool? = nil,
        ledOn: Bool? = nil,
        gcrWriteModeActive: Bool? = nil,
        writeProtected: Bool? = nil,
        hasDisk: Bool? = nil,
        mediaChanged: Bool? = nil,
        minMediaChangeCount: Int? = nil,
        hasNativeLowLevelImage: Bool? = nil,
        d64ExportBlockedByLowLevelWrites: Bool? = nil,
        lastIECCommandContains: String? = nil
    ) {
        self.minGCRReads = minGCRReads
        self.minByteReady = minByteReady
        self.minSyncDetections = minSyncDetections
        self.minWeakBitReads = minWeakBitReads
        self.minVariableSpeedZoneSamples = minVariableSpeedZoneSamples
        self.minGCRWrites = minGCRWrites
        self.minGCRWriteSplices = minGCRWriteSplices
        self.minGCRWriteEraseBits = minGCRWriteEraseBits
        self.requiredVariableSpeedZones = requiredVariableSpeedZones
        self.track = track
        self.halfTrack = halfTrack
        self.headBitPosition = headBitPosition
        self.readTrack = readTrack
        self.readHalfTrack = readHalfTrack
        self.usingHalfTrackFallback = usingHalfTrackFallback
        self.motorOn = motorOn
        self.ledOn = ledOn
        self.gcrWriteModeActive = gcrWriteModeActive
        self.writeProtected = writeProtected
        self.hasDisk = hasDisk
        self.mediaChanged = mediaChanged
        self.minMediaChangeCount = minMediaChangeCount
        self.hasNativeLowLevelImage = hasNativeLowLevelImage
        self.d64ExportBlockedByLowLevelWrites = d64ExportBlockedByLowLevelWrites
        self.lastIECCommandContains = lastIECCommandContains
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minGCRReads = try Self.decodeNonNegativeIfPresent(container, forKey: .minGCRReads)
        minByteReady = try Self.decodeNonNegativeIfPresent(container, forKey: .minByteReady)
        minSyncDetections = try Self.decodeNonNegativeIfPresent(container, forKey: .minSyncDetections)
        minWeakBitReads = try Self.decodeNonNegativeIfPresent(container, forKey: .minWeakBitReads)
        minVariableSpeedZoneSamples = try Self.decodeNonNegativeIfPresent(container, forKey: .minVariableSpeedZoneSamples)
        minGCRWrites = try Self.decodeNonNegativeIfPresent(container, forKey: .minGCRWrites)
        minGCRWriteSplices = try Self.decodeNonNegativeIfPresent(container, forKey: .minGCRWriteSplices)
        minGCRWriteEraseBits = try Self.decodeNonNegativeIfPresent(container, forKey: .minGCRWriteEraseBits)
        requiredVariableSpeedZones = try container.decodeIfPresent([Int].self, forKey: .requiredVariableSpeedZones) ?? []
        for zone in requiredVariableSpeedZones where !(0...3).contains(zone) {
            throw DecodingError.dataCorruptedError(
                forKey: .requiredVariableSpeedZones,
                in: container,
                debugDescription: "Required variable speed zones must be 0...3"
            )
        }
        track = try Self.decodeNonNegativeIfPresent(container, forKey: .track)
        halfTrack = try Self.decodeNonNegativeIfPresent(container, forKey: .halfTrack)
        headBitPosition = try Self.decodeNonNegativeIfPresent(container, forKey: .headBitPosition)
        readTrack = try Self.decodeNonNegativeIfPresent(container, forKey: .readTrack)
        readHalfTrack = try Self.decodeNonNegativeIfPresent(container, forKey: .readHalfTrack)
        usingHalfTrackFallback = try container.decodeIfPresent(Bool.self, forKey: .usingHalfTrackFallback)
        motorOn = try container.decodeIfPresent(Bool.self, forKey: .motorOn)
        ledOn = try container.decodeIfPresent(Bool.self, forKey: .ledOn)
        gcrWriteModeActive = try container.decodeIfPresent(Bool.self, forKey: .gcrWriteModeActive)
        writeProtected = try container.decodeIfPresent(Bool.self, forKey: .writeProtected)
        hasDisk = try container.decodeIfPresent(Bool.self, forKey: .hasDisk)
        mediaChanged = try container.decodeIfPresent(Bool.self, forKey: .mediaChanged)
        minMediaChangeCount = try Self.decodeNonNegativeIfPresent(container, forKey: .minMediaChangeCount)
        hasNativeLowLevelImage = try container.decodeIfPresent(Bool.self, forKey: .hasNativeLowLevelImage)
        d64ExportBlockedByLowLevelWrites = try container.decodeIfPresent(Bool.self, forKey: .d64ExportBlockedByLowLevelWrites)
        lastIECCommandContains = try container.decodeIfPresent(String.self, forKey: .lastIECCommandContains)
    }

    private static func decodeNonNegativeIfPresent(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Int? {
        guard let value = try container.decodeIfPresent(Int.self, forKey: key) else {
            return nil
        }
        guard value >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "\(key.stringValue) must be non-negative"
            )
        }
        return value
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

public enum CompatibilitySIDRegisterReadMode: String, Decodable, Equatable {
    case debug
    case chip
}

public struct CompatibilitySIDRegisterExpectation: Decodable, Equatable {
    public let register: Int
    public let value: UInt8
    public let mask: UInt8
    public let readMode: CompatibilitySIDRegisterReadMode

    public init(
        register: Int,
        value: UInt8,
        mask: UInt8 = 0xFF,
        readMode: CompatibilitySIDRegisterReadMode = .debug
    ) {
        self.register = register
        self.value = value
        self.mask = mask
        self.readMode = readMode
    }

    private enum CodingKeys: String, CodingKey {
        case register
        case value
        case mask
        case readMode
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
        readMode = try container.decodeIfPresent(CompatibilitySIDRegisterReadMode.self, forKey: .readMode) ?? .debug

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

public struct CompatibilitySIDAudioSignature: Decodable, Equatable {
    public let sampleCount: Int
    public let minimum: Float?
    public let maximum: Float?
    public let sum: Double?
    public let absoluteSum: Double?
    public let mean: Double?
    public let rootMeanSquare: Double?
    public let zeroCrossings: Int?
    public let zeroCrossingRate: Double?
    public let lowBandRootMeanSquare: Double?
    public let midBandRootMeanSquare: Double?
    public let highBandRootMeanSquare: Double?
    public let crestFactor: Double?
    public let tolerance: Double

    public init(
        sampleCount: Int,
        minimum: Float? = nil,
        maximum: Float? = nil,
        sum: Double? = nil,
        absoluteSum: Double? = nil,
        mean: Double? = nil,
        rootMeanSquare: Double? = nil,
        zeroCrossings: Int? = nil,
        zeroCrossingRate: Double? = nil,
        lowBandRootMeanSquare: Double? = nil,
        midBandRootMeanSquare: Double? = nil,
        highBandRootMeanSquare: Double? = nil,
        crestFactor: Double? = nil,
        tolerance: Double = 0.000_001
    ) {
        self.sampleCount = sampleCount
        self.minimum = minimum
        self.maximum = maximum
        self.sum = sum
        self.absoluteSum = absoluteSum
        self.mean = mean
        self.rootMeanSquare = rootMeanSquare
        self.zeroCrossings = zeroCrossings
        self.zeroCrossingRate = zeroCrossingRate
        self.lowBandRootMeanSquare = lowBandRootMeanSquare
        self.midBandRootMeanSquare = midBandRootMeanSquare
        self.highBandRootMeanSquare = highBandRootMeanSquare
        self.crestFactor = crestFactor
        self.tolerance = tolerance
    }

    private enum CodingKeys: String, CodingKey {
        case sampleCount
        case minimum
        case maximum
        case sum
        case absoluteSum
        case mean
        case rootMeanSquare
        case zeroCrossings
        case zeroCrossingRate
        case lowBandRootMeanSquare
        case midBandRootMeanSquare
        case highBandRootMeanSquare
        case crestFactor
        case tolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        minimum = try container.decodeIfPresent(Float.self, forKey: .minimum)
        maximum = try container.decodeIfPresent(Float.self, forKey: .maximum)
        sum = try container.decodeIfPresent(Double.self, forKey: .sum)
        absoluteSum = try container.decodeIfPresent(Double.self, forKey: .absoluteSum)
        mean = try container.decodeIfPresent(Double.self, forKey: .mean)
        rootMeanSquare = try container.decodeIfPresent(Double.self, forKey: .rootMeanSquare)
        zeroCrossings = try container.decodeIfPresent(Int.self, forKey: .zeroCrossings)
        zeroCrossingRate = try container.decodeIfPresent(Double.self, forKey: .zeroCrossingRate)
        lowBandRootMeanSquare = try container.decodeIfPresent(Double.self, forKey: .lowBandRootMeanSquare)
        midBandRootMeanSquare = try container.decodeIfPresent(Double.self, forKey: .midBandRootMeanSquare)
        highBandRootMeanSquare = try container.decodeIfPresent(Double.self, forKey: .highBandRootMeanSquare)
        crestFactor = try container.decodeIfPresent(Double.self, forKey: .crestFactor)
        tolerance = try container.decodeIfPresent(Double.self, forKey: .tolerance) ?? 0.000_001

        guard sampleCount >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .sampleCount,
                in: container,
                debugDescription: "SID audio sampleCount must be non-negative"
            )
        }
        guard tolerance >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .tolerance,
                in: container,
                debugDescription: "SID audio tolerance must be non-negative"
            )
        }
        if let absoluteSum, absoluteSum < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .absoluteSum,
                in: container,
                debugDescription: "SID audio absoluteSum must be non-negative"
            )
        }
        if let rootMeanSquare, rootMeanSquare < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .rootMeanSquare,
                in: container,
                debugDescription: "SID audio rootMeanSquare must be non-negative"
            )
        }
        try Self.validateNonNegative(zeroCrossingRate, key: .zeroCrossingRate, container: container, name: "zeroCrossingRate")
        try Self.validateNonNegative(lowBandRootMeanSquare, key: .lowBandRootMeanSquare, container: container, name: "lowBandRootMeanSquare")
        try Self.validateNonNegative(midBandRootMeanSquare, key: .midBandRootMeanSquare, container: container, name: "midBandRootMeanSquare")
        try Self.validateNonNegative(highBandRootMeanSquare, key: .highBandRootMeanSquare, container: container, name: "highBandRootMeanSquare")
        try Self.validateNonNegative(crestFactor, key: .crestFactor, container: container, name: "crestFactor")
        if let zeroCrossings, zeroCrossings < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .zeroCrossings,
                in: container,
                debugDescription: "SID audio zeroCrossings must be non-negative"
            )
        }
        if let minimum, let maximum, minimum > maximum {
            throw DecodingError.dataCorruptedError(
                forKey: .minimum,
                in: container,
                debugDescription: "SID audio minimum must not exceed maximum"
            )
        }
    }

    private static func validateNonNegative(
        _ value: Double?,
        key: CodingKeys,
        container: KeyedDecodingContainer<CodingKeys>,
        name: String
    ) throws {
        guard let value, value < 0 else { return }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "SID audio \(name) must be non-negative"
        )
    }
}

public struct CompatibilitySIDAudioState: Decodable, Equatable {
    public let accuracyMode: SID.AccuracyMode?
    public let sampleCycleCounter: Double?
    public let cyclesPerSample: Double?
    public let audioAccumulator: Double?
    public let audioAccumulatorCount: Int?
    public let audioOutputState: Double?
    public let directOutput: Int?
    public let filterInput: Int?
    public let filterOutput: Int?
    public let mixedOutput: Int?
    public let externalAudioInput: Int?
    public let externalAudioPathInput: Int?
    public let filterCutoff: Int?
    public let filterResonance: Int?
    public let filterControl: Int?
    public let volumeFilter: Int?
    public let volume: Int?
    public let normalizedFilterCutoffValue: Int?
    public let normalizedFilterCutoff: Double?
    public let filterDamping: Double?
    public let voice1FilterEnabled: Bool?
    public let voice2FilterEnabled: Bool?
    public let voice3FilterEnabled: Bool?
    public let externalInputFiltered: Bool?
    public let filterLowPassEnabled: Bool?
    public let filterBandPassEnabled: Bool?
    public let filterHighPassEnabled: Bool?
    public let voice3Off: Bool?
    public let dataBusLatch: Int?
    public let dataBusLatchCyclesRemaining: Int?
    public let oscillator3Readback: Int?
    public let oscillator3ReadbackValid: Bool?
    public let envelope3Readback: Int?
    public let envelope3ReadbackValid: Bool?
    public let paddleX: Int?
    public let paddleY: Int?
    public let paddleTargetX: Int?
    public let paddleTargetY: Int?
    public let paddleScanActive: Bool?
    public let paddleScanCounter: Int?
    public let filterLow: Double?
    public let filterBand: Double?
    public let filterHigh: Double?
    public let sampleWritePosition: Int?
    public let tolerance: Double

    public init(
        accuracyMode: SID.AccuracyMode? = nil,
        sampleCycleCounter: Double? = nil,
        cyclesPerSample: Double? = nil,
        audioAccumulator: Double? = nil,
        audioAccumulatorCount: Int? = nil,
        audioOutputState: Double? = nil,
        directOutput: Int? = nil,
        filterInput: Int? = nil,
        filterOutput: Int? = nil,
        mixedOutput: Int? = nil,
        externalAudioInput: Int? = nil,
        externalAudioPathInput: Int? = nil,
        filterCutoff: Int? = nil,
        filterResonance: Int? = nil,
        filterControl: Int? = nil,
        volumeFilter: Int? = nil,
        volume: Int? = nil,
        normalizedFilterCutoffValue: Int? = nil,
        normalizedFilterCutoff: Double? = nil,
        filterDamping: Double? = nil,
        voice1FilterEnabled: Bool? = nil,
        voice2FilterEnabled: Bool? = nil,
        voice3FilterEnabled: Bool? = nil,
        externalInputFiltered: Bool? = nil,
        filterLowPassEnabled: Bool? = nil,
        filterBandPassEnabled: Bool? = nil,
        filterHighPassEnabled: Bool? = nil,
        voice3Off: Bool? = nil,
        dataBusLatch: Int? = nil,
        dataBusLatchCyclesRemaining: Int? = nil,
        oscillator3Readback: Int? = nil,
        oscillator3ReadbackValid: Bool? = nil,
        envelope3Readback: Int? = nil,
        envelope3ReadbackValid: Bool? = nil,
        paddleX: Int? = nil,
        paddleY: Int? = nil,
        paddleTargetX: Int? = nil,
        paddleTargetY: Int? = nil,
        paddleScanActive: Bool? = nil,
        paddleScanCounter: Int? = nil,
        filterLow: Double? = nil,
        filterBand: Double? = nil,
        filterHigh: Double? = nil,
        sampleWritePosition: Int? = nil,
        tolerance: Double = 0.000_001
    ) {
        self.accuracyMode = accuracyMode
        self.sampleCycleCounter = sampleCycleCounter
        self.cyclesPerSample = cyclesPerSample
        self.audioAccumulator = audioAccumulator
        self.audioAccumulatorCount = audioAccumulatorCount
        self.audioOutputState = audioOutputState
        self.directOutput = directOutput
        self.filterInput = filterInput
        self.filterOutput = filterOutput
        self.mixedOutput = mixedOutput
        self.externalAudioInput = externalAudioInput
        self.externalAudioPathInput = externalAudioPathInput
        self.filterCutoff = filterCutoff
        self.filterResonance = filterResonance
        self.filterControl = filterControl
        self.volumeFilter = volumeFilter
        self.volume = volume
        self.normalizedFilterCutoffValue = normalizedFilterCutoffValue
        self.normalizedFilterCutoff = normalizedFilterCutoff
        self.filterDamping = filterDamping
        self.voice1FilterEnabled = voice1FilterEnabled
        self.voice2FilterEnabled = voice2FilterEnabled
        self.voice3FilterEnabled = voice3FilterEnabled
        self.externalInputFiltered = externalInputFiltered
        self.filterLowPassEnabled = filterLowPassEnabled
        self.filterBandPassEnabled = filterBandPassEnabled
        self.filterHighPassEnabled = filterHighPassEnabled
        self.voice3Off = voice3Off
        self.dataBusLatch = dataBusLatch
        self.dataBusLatchCyclesRemaining = dataBusLatchCyclesRemaining
        self.oscillator3Readback = oscillator3Readback
        self.oscillator3ReadbackValid = oscillator3ReadbackValid
        self.envelope3Readback = envelope3Readback
        self.envelope3ReadbackValid = envelope3ReadbackValid
        self.paddleX = paddleX
        self.paddleY = paddleY
        self.paddleTargetX = paddleTargetX
        self.paddleTargetY = paddleTargetY
        self.paddleScanActive = paddleScanActive
        self.paddleScanCounter = paddleScanCounter
        self.filterLow = filterLow
        self.filterBand = filterBand
        self.filterHigh = filterHigh
        self.sampleWritePosition = sampleWritePosition
        self.tolerance = tolerance
    }

    private enum CodingKeys: String, CodingKey {
        case accuracyMode
        case sampleCycleCounter
        case cyclesPerSample
        case audioAccumulator
        case audioAccumulatorCount
        case audioOutputState
        case directOutput
        case filterInput
        case filterOutput
        case mixedOutput
        case externalAudioInput
        case externalAudioPathInput
        case filterCutoff
        case filterResonance
        case filterControl
        case volumeFilter
        case volume
        case normalizedFilterCutoffValue
        case normalizedFilterCutoff
        case filterDamping
        case voice1FilterEnabled
        case voice2FilterEnabled
        case voice3FilterEnabled
        case externalInputFiltered
        case filterLowPassEnabled
        case filterBandPassEnabled
        case filterHighPassEnabled
        case voice3Off
        case dataBusLatch
        case dataBusLatchCyclesRemaining
        case oscillator3Readback
        case oscillator3ReadbackValid
        case envelope3Readback
        case envelope3ReadbackValid
        case paddleX
        case paddleY
        case paddleTargetX
        case paddleTargetY
        case paddleScanActive
        case paddleScanCounter
        case filterLow
        case filterBand
        case filterHigh
        case sampleWritePosition
        case tolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accuracyMode = try container.decodeIfPresent(SID.AccuracyMode.self, forKey: .accuracyMode)
        sampleCycleCounter = try container.decodeIfPresent(Double.self, forKey: .sampleCycleCounter)
        cyclesPerSample = try container.decodeIfPresent(Double.self, forKey: .cyclesPerSample)
        audioAccumulator = try container.decodeIfPresent(Double.self, forKey: .audioAccumulator)
        audioAccumulatorCount = try container.decodeIfPresent(Int.self, forKey: .audioAccumulatorCount)
        audioOutputState = try container.decodeIfPresent(Double.self, forKey: .audioOutputState)
        directOutput = try container.decodeIfPresent(Int.self, forKey: .directOutput)
        filterInput = try container.decodeIfPresent(Int.self, forKey: .filterInput)
        filterOutput = try container.decodeIfPresent(Int.self, forKey: .filterOutput)
        mixedOutput = try container.decodeIfPresent(Int.self, forKey: .mixedOutput)
        externalAudioInput = try container.decodeIfPresent(Int.self, forKey: .externalAudioInput)
        externalAudioPathInput = try container.decodeIfPresent(Int.self, forKey: .externalAudioPathInput)
        filterCutoff = try Self.decodeOptionalInteger(container, forKey: .filterCutoff)
        filterResonance = try Self.decodeOptionalInteger(container, forKey: .filterResonance)
        filterControl = try Self.decodeOptionalInteger(container, forKey: .filterControl)
        volumeFilter = try Self.decodeOptionalInteger(container, forKey: .volumeFilter)
        volume = try Self.decodeOptionalInteger(container, forKey: .volume)
        normalizedFilterCutoffValue = try Self.decodeOptionalInteger(container, forKey: .normalizedFilterCutoffValue)
        normalizedFilterCutoff = try container.decodeIfPresent(Double.self, forKey: .normalizedFilterCutoff)
        filterDamping = try container.decodeIfPresent(Double.self, forKey: .filterDamping)
        voice1FilterEnabled = try container.decodeIfPresent(Bool.self, forKey: .voice1FilterEnabled)
        voice2FilterEnabled = try container.decodeIfPresent(Bool.self, forKey: .voice2FilterEnabled)
        voice3FilterEnabled = try container.decodeIfPresent(Bool.self, forKey: .voice3FilterEnabled)
        externalInputFiltered = try container.decodeIfPresent(Bool.self, forKey: .externalInputFiltered)
        filterLowPassEnabled = try container.decodeIfPresent(Bool.self, forKey: .filterLowPassEnabled)
        filterBandPassEnabled = try container.decodeIfPresent(Bool.self, forKey: .filterBandPassEnabled)
        filterHighPassEnabled = try container.decodeIfPresent(Bool.self, forKey: .filterHighPassEnabled)
        voice3Off = try container.decodeIfPresent(Bool.self, forKey: .voice3Off)
        dataBusLatch = try Self.decodeOptionalInteger(container, forKey: .dataBusLatch)
        dataBusLatchCyclesRemaining = try container.decodeIfPresent(Int.self, forKey: .dataBusLatchCyclesRemaining)
        oscillator3Readback = try Self.decodeOptionalInteger(container, forKey: .oscillator3Readback)
        oscillator3ReadbackValid = try container.decodeIfPresent(Bool.self, forKey: .oscillator3ReadbackValid)
        envelope3Readback = try Self.decodeOptionalInteger(container, forKey: .envelope3Readback)
        envelope3ReadbackValid = try container.decodeIfPresent(Bool.self, forKey: .envelope3ReadbackValid)
        paddleX = try Self.decodeOptionalInteger(container, forKey: .paddleX)
        paddleY = try Self.decodeOptionalInteger(container, forKey: .paddleY)
        paddleTargetX = try Self.decodeOptionalInteger(container, forKey: .paddleTargetX)
        paddleTargetY = try Self.decodeOptionalInteger(container, forKey: .paddleTargetY)
        paddleScanActive = try container.decodeIfPresent(Bool.self, forKey: .paddleScanActive)
        paddleScanCounter = try container.decodeIfPresent(Int.self, forKey: .paddleScanCounter)
        filterLow = try container.decodeIfPresent(Double.self, forKey: .filterLow)
        filterBand = try container.decodeIfPresent(Double.self, forKey: .filterBand)
        filterHigh = try container.decodeIfPresent(Double.self, forKey: .filterHigh)
        sampleWritePosition = try container.decodeIfPresent(Int.self, forKey: .sampleWritePosition)
        tolerance = try container.decodeIfPresent(Double.self, forKey: .tolerance) ?? 0.000_001

        if let audioAccumulatorCount, audioAccumulatorCount < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .audioAccumulatorCount,
                in: container,
                debugDescription: "SID audio state accumulator count must be non-negative"
            )
        }
        if let sampleCycleCounter, sampleCycleCounter < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .sampleCycleCounter,
                in: container,
                debugDescription: "SID audio state sample cycle counter must be non-negative"
            )
        }
        if let cyclesPerSample, cyclesPerSample <= 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .cyclesPerSample,
                in: container,
                debugDescription: "SID audio state cycles per sample must be positive"
            )
        }
        if let sampleWritePosition, sampleWritePosition < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .sampleWritePosition,
                in: container,
                debugDescription: "SID audio state sample write position must be non-negative"
            )
        }
        let outputRange = Int(Int32.min)...Int(Int32.max)
        for (key, value) in [
            (CodingKeys.directOutput, directOutput),
            (CodingKeys.filterInput, filterInput),
            (CodingKeys.filterOutput, filterOutput),
            (CodingKeys.mixedOutput, mixedOutput),
            (CodingKeys.externalAudioInput, externalAudioInput),
            (CodingKeys.externalAudioPathInput, externalAudioPathInput)
        ] where value.map({ !outputRange.contains($0) }) == true {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "SID audio state output must fit in 32 bits"
            )
        }
        if let filterCutoff, !(0...0xFFFF).contains(filterCutoff) {
            throw DecodingError.dataCorruptedError(
                forKey: .filterCutoff,
                in: container,
                debugDescription: "SID audio state filter cutoff must fit in 16 bits"
            )
        }
        try Self.validateOptional(filterResonance, forKey: .filterResonance, in: container, range: 0...0x0F, debugDescription: "SID audio state filter resonance must fit in 4 bits")
        try Self.validateOptional(filterControl, forKey: .filterControl, in: container, range: 0...0x0F, debugDescription: "SID audio state filter control must fit in 4 bits")
        try Self.validateOptional(volumeFilter, forKey: .volumeFilter, in: container, range: 0...0xFF, debugDescription: "SID audio state volume/filter register must fit in 8 bits")
        try Self.validateOptional(volume, forKey: .volume, in: container, range: 0...0x0F, debugDescription: "SID audio state volume must fit in 4 bits")
        try Self.validateOptional(dataBusLatch, forKey: .dataBusLatch, in: container, range: 0...0xFF, debugDescription: "SID audio state data bus latch must fit in 8 bits")
        try Self.validateOptional(dataBusLatchCyclesRemaining, forKey: .dataBusLatchCyclesRemaining, in: container, range: 0...Int.max, debugDescription: "SID audio state data bus latch cycles must be non-negative")
        try Self.validateOptional(oscillator3Readback, forKey: .oscillator3Readback, in: container, range: 0...0xFF, debugDescription: "SID audio state oscillator 3 readback must fit in 8 bits")
        try Self.validateOptional(envelope3Readback, forKey: .envelope3Readback, in: container, range: 0...0xFF, debugDescription: "SID audio state envelope 3 readback must fit in 8 bits")
        try Self.validateOptional(paddleX, forKey: .paddleX, in: container, range: 0...0xFF, debugDescription: "SID audio state paddle X must fit in 8 bits")
        try Self.validateOptional(paddleY, forKey: .paddleY, in: container, range: 0...0xFF, debugDescription: "SID audio state paddle Y must fit in 8 bits")
        try Self.validateOptional(paddleTargetX, forKey: .paddleTargetX, in: container, range: 0...0xFF, debugDescription: "SID audio state paddle target X must fit in 8 bits")
        try Self.validateOptional(paddleTargetY, forKey: .paddleTargetY, in: container, range: 0...0xFF, debugDescription: "SID audio state paddle target Y must fit in 8 bits")
        try Self.validateOptional(paddleScanCounter, forKey: .paddleScanCounter, in: container, range: 0...Int.max, debugDescription: "SID audio state paddle scan counter must be non-negative")
        if let normalizedFilterCutoffValue, !(0...0x07FF).contains(normalizedFilterCutoffValue) {
            throw DecodingError.dataCorruptedError(
                forKey: .normalizedFilterCutoffValue,
                in: container,
                debugDescription: "SID audio state normalized filter cutoff must fit in 11 bits"
            )
        }
        guard tolerance >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .tolerance,
                in: container,
                debugDescription: "SID audio state tolerance must be non-negative"
            )
        }
    }

    private static func validateOptional(
        _ value: Int?,
        forKey key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>,
        range: ClosedRange<Int>,
        debugDescription: String
    ) throws {
        guard let value, !range.contains(value) else { return }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: debugDescription
        )
    }

    private static func decodeOptionalInteger(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) {
            return value
        }
        guard let rawValue = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let radix = normalized.hasPrefix("$") || normalized.lowercased().hasPrefix("0x") ? 16 : 10
        let digits = normalized
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "0x", with: "", options: [.caseInsensitive])
        guard let value = Int(digits, radix: radix) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Expected decimal integer or hexadecimal string"
            )
        }
        return value
    }
}

public struct CompatibilitySIDVoiceState: Decodable, Equatable {
    public let voice: Int
    public let frequency: Int?
    public let pulseWidth: Int?
    public let control: Int?
    public let attackDecay: Int?
    public let sustainRelease: Int?
    public let accumulator: Int?
    public let shiftRegister: Int?
    public let envelopeLevel: Int?
    public let envelopeOutput: Int?
    public let sustainLevel: Int?
    public let envelopeState: String?
    public let exponentialCounter: Int?
    public let exponentialPeriod: Int?
    public let holdZero: Bool?
    public let gate: Bool?
    public let controlGate: Bool?
    public let sync: Bool?
    public let ringMod: Bool?
    public let testBit: Bool?
    public let waveTriangle: Bool?
    public let waveSawtooth: Bool?
    public let wavePulse: Bool?
    public let waveNoise: Bool?
    public let hasWaveform: Bool?
    public let oscillatorMSBRose: Bool?
    public let noiseClockRose: Bool?
    public let rateCounter: Int?
    public let selectedRatePeriod: Int?
    public let oscillatorOutput: Int?
    public let waveformOutput: Int?
    public let waveformDACOutput: Int?
    public let waveformDACHoldCyclesRemaining: Int?

    public init(
        voice: Int,
        frequency: Int? = nil,
        pulseWidth: Int? = nil,
        control: Int? = nil,
        attackDecay: Int? = nil,
        sustainRelease: Int? = nil,
        accumulator: Int? = nil,
        shiftRegister: Int? = nil,
        envelopeLevel: Int? = nil,
        envelopeOutput: Int? = nil,
        sustainLevel: Int? = nil,
        envelopeState: String? = nil,
        exponentialCounter: Int? = nil,
        exponentialPeriod: Int? = nil,
        holdZero: Bool? = nil,
        gate: Bool? = nil,
        controlGate: Bool? = nil,
        sync: Bool? = nil,
        ringMod: Bool? = nil,
        testBit: Bool? = nil,
        waveTriangle: Bool? = nil,
        waveSawtooth: Bool? = nil,
        wavePulse: Bool? = nil,
        waveNoise: Bool? = nil,
        hasWaveform: Bool? = nil,
        oscillatorMSBRose: Bool? = nil,
        noiseClockRose: Bool? = nil,
        rateCounter: Int? = nil,
        selectedRatePeriod: Int? = nil,
        oscillatorOutput: Int? = nil,
        waveformOutput: Int? = nil,
        waveformDACOutput: Int? = nil,
        waveformDACHoldCyclesRemaining: Int? = nil
    ) {
        self.voice = voice
        self.frequency = frequency
        self.pulseWidth = pulseWidth
        self.control = control
        self.attackDecay = attackDecay
        self.sustainRelease = sustainRelease
        self.accumulator = accumulator
        self.shiftRegister = shiftRegister
        self.envelopeLevel = envelopeLevel
        self.envelopeOutput = envelopeOutput
        self.sustainLevel = sustainLevel
        self.envelopeState = envelopeState
        self.exponentialCounter = exponentialCounter
        self.exponentialPeriod = exponentialPeriod
        self.holdZero = holdZero
        self.gate = gate
        self.controlGate = controlGate
        self.sync = sync
        self.ringMod = ringMod
        self.testBit = testBit
        self.waveTriangle = waveTriangle
        self.waveSawtooth = waveSawtooth
        self.wavePulse = wavePulse
        self.waveNoise = waveNoise
        self.hasWaveform = hasWaveform
        self.oscillatorMSBRose = oscillatorMSBRose
        self.noiseClockRose = noiseClockRose
        self.rateCounter = rateCounter
        self.selectedRatePeriod = selectedRatePeriod
        self.oscillatorOutput = oscillatorOutput
        self.waveformOutput = waveformOutput
        self.waveformDACOutput = waveformDACOutput
        self.waveformDACHoldCyclesRemaining = waveformDACHoldCyclesRemaining
    }

    private enum CodingKeys: String, CodingKey {
        case voice
        case frequency
        case pulseWidth
        case control
        case attackDecay
        case sustainRelease
        case accumulator
        case shiftRegister
        case envelopeLevel
        case envelopeOutput
        case sustainLevel
        case envelopeState
        case exponentialCounter
        case exponentialPeriod
        case holdZero
        case gate
        case controlGate
        case sync
        case ringMod
        case testBit
        case waveTriangle
        case waveSawtooth
        case wavePulse
        case waveNoise
        case hasWaveform
        case oscillatorMSBRose
        case noiseClockRose
        case rateCounter
        case selectedRatePeriod
        case oscillatorOutput
        case waveformOutput
        case waveformDACOutput
        case waveformDACHoldCyclesRemaining
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        voice = try container.decode(Int.self, forKey: .voice)
        frequency = try Self.decodeOptionalInteger(forKey: .frequency, in: container)
        pulseWidth = try Self.decodeOptionalInteger(forKey: .pulseWidth, in: container)
        control = try Self.decodeOptionalInteger(forKey: .control, in: container)
        attackDecay = try Self.decodeOptionalInteger(forKey: .attackDecay, in: container)
        sustainRelease = try Self.decodeOptionalInteger(forKey: .sustainRelease, in: container)
        accumulator = try Self.decodeOptionalInteger(forKey: .accumulator, in: container)
        shiftRegister = try Self.decodeOptionalInteger(forKey: .shiftRegister, in: container)
        envelopeLevel = try Self.decodeOptionalInteger(forKey: .envelopeLevel, in: container)
        envelopeOutput = try Self.decodeOptionalInteger(forKey: .envelopeOutput, in: container)
        sustainLevel = try Self.decodeOptionalInteger(forKey: .sustainLevel, in: container)
        envelopeState = try container.decodeIfPresent(String.self, forKey: .envelopeState)
        exponentialCounter = try Self.decodeOptionalInteger(forKey: .exponentialCounter, in: container)
        exponentialPeriod = try Self.decodeOptionalInteger(forKey: .exponentialPeriod, in: container)
        holdZero = try container.decodeIfPresent(Bool.self, forKey: .holdZero)
        gate = try container.decodeIfPresent(Bool.self, forKey: .gate)
        controlGate = try container.decodeIfPresent(Bool.self, forKey: .controlGate)
        sync = try container.decodeIfPresent(Bool.self, forKey: .sync)
        ringMod = try container.decodeIfPresent(Bool.self, forKey: .ringMod)
        testBit = try container.decodeIfPresent(Bool.self, forKey: .testBit)
        waveTriangle = try container.decodeIfPresent(Bool.self, forKey: .waveTriangle)
        waveSawtooth = try container.decodeIfPresent(Bool.self, forKey: .waveSawtooth)
        wavePulse = try container.decodeIfPresent(Bool.self, forKey: .wavePulse)
        waveNoise = try container.decodeIfPresent(Bool.self, forKey: .waveNoise)
        hasWaveform = try container.decodeIfPresent(Bool.self, forKey: .hasWaveform)
        oscillatorMSBRose = try container.decodeIfPresent(Bool.self, forKey: .oscillatorMSBRose)
        noiseClockRose = try container.decodeIfPresent(Bool.self, forKey: .noiseClockRose)
        rateCounter = try Self.decodeOptionalInteger(forKey: .rateCounter, in: container)
        selectedRatePeriod = try Self.decodeOptionalInteger(forKey: .selectedRatePeriod, in: container)
        oscillatorOutput = try Self.decodeOptionalInteger(forKey: .oscillatorOutput, in: container)
        waveformOutput = try Self.decodeOptionalInteger(forKey: .waveformOutput, in: container)
        waveformDACOutput = try Self.decodeOptionalInteger(forKey: .waveformDACOutput, in: container)
        waveformDACHoldCyclesRemaining = try Self.decodeOptionalInteger(forKey: .waveformDACHoldCyclesRemaining, in: container)

        try Self.validate(voice, forKey: .voice, in: container, range: 0...2, description: "SID voice index must be 0, 1, or 2")
        try Self.validateOptional(frequency, forKey: .frequency, in: container, range: 0...0xFFFF)
        try Self.validateOptional(pulseWidth, forKey: .pulseWidth, in: container, range: 0...0x0FFF)
        try Self.validateOptional(control, forKey: .control, in: container, range: 0...0xFF)
        try Self.validateOptional(attackDecay, forKey: .attackDecay, in: container, range: 0...0xFF)
        try Self.validateOptional(sustainRelease, forKey: .sustainRelease, in: container, range: 0...0xFF)
        try Self.validateOptional(accumulator, forKey: .accumulator, in: container, range: 0...0xFFFFFF)
        try Self.validateOptional(shiftRegister, forKey: .shiftRegister, in: container, range: 0...0x7FFFFF)
        try Self.validateOptional(envelopeLevel, forKey: .envelopeLevel, in: container, range: 0...0xFF)
        try Self.validateOptional(envelopeOutput, forKey: .envelopeOutput, in: container, range: 0...0xFF)
        try Self.validateOptional(sustainLevel, forKey: .sustainLevel, in: container, range: 0...0xFF)
        try Self.validateOptional(exponentialCounter, forKey: .exponentialCounter, in: container, range: 0...0xFFFF)
        try Self.validateOptional(exponentialPeriod, forKey: .exponentialPeriod, in: container, range: 0...0xFFFF)
        try Self.validateOptional(rateCounter, forKey: .rateCounter, in: container, range: 0...0xFFFF)
        try Self.validateOptional(selectedRatePeriod, forKey: .selectedRatePeriod, in: container, range: 0...0xFFFF)
        try Self.validateOptional(oscillatorOutput, forKey: .oscillatorOutput, in: container, range: 0...0x0FFF)
        try Self.validateOptional(waveformOutput, forKey: .waveformOutput, in: container, range: Int(Int16.min)...Int(Int16.max))
        try Self.validateOptional(waveformDACOutput, forKey: .waveformDACOutput, in: container, range: 0...0x0FFF)
        try Self.validateOptional(waveformDACHoldCyclesRemaining, forKey: .waveformDACHoldCyclesRemaining, in: container, range: 0...Int.max)
    }

    private static func decodeOptionalInteger<K: CodingKey>(
        forKey key: K,
        in container: KeyedDecodingContainer<K>
    ) throws -> Int? {
        guard container.contains(key) else { return nil }
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

    private static func validate<K: CodingKey>(
        _ value: Int,
        forKey key: K,
        in container: KeyedDecodingContainer<K>,
        range: ClosedRange<Int>,
        description: String? = nil
    ) throws {
        guard range.contains(value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: description ?? "\(key.stringValue) is out of range"
            )
        }
    }

    private static func validateOptional<K: CodingKey>(
        _ value: Int?,
        forKey key: K,
        in container: KeyedDecodingContainer<K>,
        range: ClosedRange<Int>
    ) throws {
        guard let value else { return }
        try validate(value, forKey: key, in: container, range: range)
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

    public static func framebuffer(_ framebuffer: [UInt32], width: Int, height: Int) -> String {
        let pixelCount = min(framebuffer.count, max(0, width * height))
        let bytes = framebuffer.prefix(pixelCount).flatMap { pixel in
            [
                UInt8(pixel & 0x000000FF),
                UInt8((pixel & 0x0000FF00) >> 8),
                UInt8((pixel & 0x00FF0000) >> 16),
                UInt8((pixel & 0xFF000000) >> 24)
            ]
        }
        return fnv1a64(bytes)
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
