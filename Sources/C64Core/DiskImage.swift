import Foundation

/// Low-level disk media consumed by true 1541 emulation.
public struct DiskImage {
    public enum Format: Equatable {
        case d64
        case g64

        public var displayName: String {
            switch self {
            case .d64: return "D64"
            case .g64: return "G64"
            }
        }
    }

    public struct Capabilities: Equatable {
        public let format: Format
        public let populatedHalfTrackCount: Int
        public let nativeLowLevelTrackCount: Int
        public let syntheticGCRTrackCount: Int
        public let preservesHalfTracks: Bool
        public let preservesRawTrackLengths: Bool
        public let preservesSpeedZones: Bool
        public let preservesVariableSpeedZones: Bool
        public let preservesSectorErrorInfo: Bool
        public let sectorErrorCodeCount: Int
        public let nonDefaultSectorErrorCodeCount: Int
        public let weakBitRangeCount: Int
        public let weakBitTotalBitCount: Int
        public let variableSpeedZoneByteCount: Int
        public let supportsWraparoundReads: Bool
        public let maxTrackSize: Int?
        public let unsupportedFeatures: [String]

        public var isNativeLowLevel: Bool { nativeLowLevelTrackCount > 0 }
        public var hasSyntheticGCR: Bool { syntheticGCRTrackCount > 0 }
    }

    public struct Track: Equatable {
        public struct WeakBitRange: Equatable {
            public let startBit: Int
            public let endBit: Int

            public init(startBit: Int, endBit: Int) {
                self.startBit = startBit
                self.endBit = endBit
            }

            public func contains(_ bitPosition: Int) -> Bool {
                startBit <= bitPosition && bitPosition <= endBit
            }
        }

        public struct SpeedZoneRange: Equatable {
            public let startByte: Int
            public let endByte: Int
            public let zone: UInt8

            public init(startByte: Int, endByte: Int, zone: UInt8) {
                self.startByte = startByte
                self.endByte = endByte
                self.zone = zone
            }
        }

        /// Half-track index, where 0 is track 1.0 and 1 is track 1.5.
        public let halfTrack: Int
        /// Raw bytes as seen by the 1541 read shift logic.
        public let bytes: [UInt8]
        /// Exact bit length represented by `bytes`; G64 tracks are byte-length
        /// based today, while this field leaves room for odd bit lengths later.
        public let bitLength: Int
        /// 1541 speed zone selected for this track.
        public let speedZone: Int
        /// Optional per-GCR-byte speed map decoded from a G64 speed block.
        /// Entries are 0...3 and indexed by byte position in `bytes`.
        public let speedZoneMap: [UInt8]?
        /// Bit ranges that should read back as unstable media rather than
        /// fixed stored bits. Used by low-level protected-media importers.
        public let weakBitRanges: [WeakBitRange]
        /// True when the source is a native low-level stream rather than a
        /// synthetic D64 sector encoding.
        public let isNativeLowLevel: Bool

        public init(
            halfTrack: Int,
            bytes: [UInt8],
            bitLength: Int? = nil,
            speedZone: Int,
            speedZoneMap: [UInt8]? = nil,
            weakBitRanges: [WeakBitRange] = [],
            isNativeLowLevel: Bool
        ) {
            self.halfTrack = halfTrack
            self.bytes = bytes
            self.bitLength = bitLength ?? bytes.count * 8
            self.speedZone = speedZone
            self.speedZoneMap = speedZoneMap
            self.weakBitRanges = weakBitRanges
            self.isNativeLowLevel = isNativeLowLevel
        }
    }

    public let format: Format
    public let tracks: [Track?]
    public let maxTrackSize: Int?
    public let sectorErrorCodes: [UInt8]?

    public var hasNativeLowLevelTracks: Bool {
        tracks.contains { $0?.isNativeLowLevel == true }
    }

    public var capabilities: Capabilities {
        let populated = tracks.compactMap { $0 }
        let nativeCount = populated.filter(\.isNativeLowLevel).count
        let syntheticCount = populated.count - nativeCount
        let hasHalfTrackData = populated.contains { $0.halfTrack % 2 == 1 }
        let hasVariableSpeedZones = populated.contains { track in
            track.speedZoneMap?.isEmpty == false
        }
        let hasWeakBitRanges = populated.contains { !$0.weakBitRanges.isEmpty }
        let weakBitRangeCount = populated.reduce(0) { partial, track in
            partial + track.weakBitRanges.count
        }
        let weakBitTotalBitCount = populated.reduce(0) { partial, track in
            partial + track.weakBitRanges.reduce(0) { rangePartial, range in
                rangePartial + (range.endBit - range.startBit + 1)
            }
        }
        let variableSpeedZoneByteCount = populated.reduce(0) { partial, track in
            partial + (track.speedZoneMap?.count ?? 0)
        }
        let sectorErrorCodeCount = sectorErrorCodes?.count ?? 0
        let nonDefaultSectorErrorCodeCount = sectorErrorCodes?.filter { code in
            code != 0x00 && code != 0x01
        }.count ?? 0
        var unsupported: [String] = []

        switch format {
        case .d64:
            unsupported.append("Native copy-protection bitstream")
        case .g64:
            unsupported.append("Flux-level timing")
            unsupported.append("Write-back")
            if !hasWeakBitRanges {
                unsupported.append("Weak/random bits")
            }
        }

        return Capabilities(
            format: format,
            populatedHalfTrackCount: populated.count,
            nativeLowLevelTrackCount: nativeCount,
            syntheticGCRTrackCount: syntheticCount,
            preservesHalfTracks: format == .g64 && hasHalfTrackData,
            preservesRawTrackLengths: format == .g64 && nativeCount > 0,
            preservesSpeedZones: format == .g64 && nativeCount > 0,
            preservesVariableSpeedZones: format == .g64 && hasVariableSpeedZones,
            preservesSectorErrorInfo: sectorErrorCodes != nil,
            sectorErrorCodeCount: sectorErrorCodeCount,
            nonDefaultSectorErrorCodeCount: nonDefaultSectorErrorCodeCount,
            weakBitRangeCount: weakBitRangeCount,
            weakBitTotalBitCount: weakBitTotalBitCount,
            variableSpeedZoneByteCount: variableSpeedZoneByteCount,
            supportsWraparoundReads: true,
            maxTrackSize: maxTrackSize,
            unsupportedFeatures: unsupported
        )
    }

    public init(
        format: Format,
        tracks: [Track?],
        maxTrackSize: Int? = nil,
        sectorErrorCodes: [UInt8]? = nil
    ) {
        self.format = format
        self.tracks = tracks
        self.maxTrackSize = maxTrackSize
        self.sectorErrorCodes = sectorErrorCodes
    }
}
