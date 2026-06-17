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

public struct CompatibilityMilestone: Decodable, Equatable {
    public let file: String
    public let mediaType: CompatibilityMediaType?
    public let machineProfile: CompatibilityMachineProfile?
    public let commands: [String]
    public let maxCycles: Int?
    public let pcStart: Int?
    public let pcEnd: Int?
    public let minGCRReads: Int?
    public let minByteReady: Int?
    public let driveStatus: CompatibilityDriveStatus?
    public let ramSignatures: [CompatibilityRAMSignature]
    public let screenRAMHash: String?
    public let screenshotName: String?

    private enum CodingKeys: String, CodingKey {
        case file
        case mediaType
        case machineProfile
        case command
        case commands
        case maxCycles
        case pcStart
        case pcEnd
        case minGCRReads
        case minByteReady
        case driveStatus
        case ramSignatures
        case screenRAMHash
        case screenshotName
    }

    public init(
        file: String,
        mediaType: CompatibilityMediaType? = nil,
        machineProfile: CompatibilityMachineProfile? = nil,
        command: String,
        maxCycles: Int? = nil,
        pcStart: Int? = nil,
        pcEnd: Int? = nil,
        minGCRReads: Int? = nil,
        minByteReady: Int? = nil,
        driveStatus: CompatibilityDriveStatus? = nil,
        ramSignatures: [CompatibilityRAMSignature] = [],
        screenRAMHash: String? = nil,
        screenshotName: String? = nil
    ) {
        self.file = file
        self.mediaType = mediaType
        self.machineProfile = machineProfile
        self.commands = [command]
        self.maxCycles = maxCycles
        self.pcStart = pcStart
        self.pcEnd = pcEnd
        self.minGCRReads = minGCRReads
        self.minByteReady = minByteReady
        self.driveStatus = driveStatus
        self.ramSignatures = ramSignatures
        self.screenRAMHash = screenRAMHash
        self.screenshotName = screenshotName
    }

    public init(
        file: String,
        mediaType: CompatibilityMediaType? = nil,
        machineProfile: CompatibilityMachineProfile? = nil,
        commands: [String],
        maxCycles: Int? = nil,
        pcStart: Int? = nil,
        pcEnd: Int? = nil,
        minGCRReads: Int? = nil,
        minByteReady: Int? = nil,
        driveStatus: CompatibilityDriveStatus? = nil,
        ramSignatures: [CompatibilityRAMSignature] = [],
        screenRAMHash: String? = nil,
        screenshotName: String? = nil
    ) {
        self.file = file
        self.mediaType = mediaType
        self.machineProfile = machineProfile
        self.commands = commands
        self.maxCycles = maxCycles
        self.pcStart = pcStart
        self.pcEnd = pcEnd
        self.minGCRReads = minGCRReads
        self.minByteReady = minByteReady
        self.driveStatus = driveStatus
        self.ramSignatures = ramSignatures
        self.screenRAMHash = screenRAMHash
        self.screenshotName = screenshotName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        file = try container.decode(String.self, forKey: .file)
        mediaType = try container.decodeIfPresent(CompatibilityMediaType.self, forKey: .mediaType)
        machineProfile = try container.decodeIfPresent(CompatibilityMachineProfile.self, forKey: .machineProfile)
        if let commandSequence = try container.decodeIfPresent([String].self, forKey: .commands) {
            guard !commandSequence.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .commands,
                    in: container,
                    debugDescription: "Command sequence must not be empty"
                )
            }
            commands = commandSequence
        } else {
            commands = [try container.decode(String.self, forKey: .command)]
        }
        maxCycles = try container.decodeIfPresent(Int.self, forKey: .maxCycles)
        pcStart = try container.decodeIfPresent(Int.self, forKey: .pcStart)
        pcEnd = try container.decodeIfPresent(Int.self, forKey: .pcEnd)
        minGCRReads = try container.decodeIfPresent(Int.self, forKey: .minGCRReads)
        minByteReady = try container.decodeIfPresent(Int.self, forKey: .minByteReady)
        driveStatus = try container.decodeIfPresent(CompatibilityDriveStatus.self, forKey: .driveStatus)
        ramSignatures = try container.decodeIfPresent([CompatibilityRAMSignature].self, forKey: .ramSignatures) ?? []
        screenRAMHash = try container.decodeIfPresent(String.self, forKey: .screenRAMHash)
        screenshotName = try container.decodeIfPresent(String.self, forKey: .screenshotName)
    }

    public var command: String {
        commands.first ?? ""
    }

    public var pcRange: ClosedRange<UInt16>? {
        guard let pcStart, let pcEnd else { return nil }
        return UInt16(pcStart)...UInt16(pcEnd)
    }
}

public struct CompatibilityDriveStatus: Decodable, Equatable {
    public let minGCRReads: Int?
    public let minByteReady: Int?
    public let minSyncDetections: Int?
    public let track: Int?
    public let halfTrack: Int?
    public let motorOn: Bool?
    public let ledOn: Bool?
    public let writeProtected: Bool?
    public let hasDisk: Bool?
    public let hasNativeLowLevelImage: Bool?
    public let lastIECCommandContains: String?

    public init(
        minGCRReads: Int? = nil,
        minByteReady: Int? = nil,
        minSyncDetections: Int? = nil,
        track: Int? = nil,
        halfTrack: Int? = nil,
        motorOn: Bool? = nil,
        ledOn: Bool? = nil,
        writeProtected: Bool? = nil,
        hasDisk: Bool? = nil,
        hasNativeLowLevelImage: Bool? = nil,
        lastIECCommandContains: String? = nil
    ) {
        self.minGCRReads = minGCRReads
        self.minByteReady = minByteReady
        self.minSyncDetections = minSyncDetections
        self.track = track
        self.halfTrack = halfTrack
        self.motorOn = motorOn
        self.ledOn = ledOn
        self.writeProtected = writeProtected
        self.hasDisk = hasDisk
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

public enum CompatibilityHash {
    public static func screenRAM(_ ram: [UInt8]) -> String {
        let start = 0x0400
        let end = min(ram.count, start + 1000)
        return fnv1a64(ram[start..<end])
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
