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
        public let supportsWraparoundReads: Bool
        public let maxTrackSize: Int?
        public let unsupportedFeatures: [String]

        public var isNativeLowLevel: Bool { nativeLowLevelTrackCount > 0 }
        public var hasSyntheticGCR: Bool { syntheticGCRTrackCount > 0 }
    }

    public struct Track: Equatable {
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
        /// True when the source is a native low-level stream rather than a
        /// synthetic D64 sector encoding.
        public let isNativeLowLevel: Bool

        public init(
            halfTrack: Int,
            bytes: [UInt8],
            bitLength: Int? = nil,
            speedZone: Int,
            speedZoneMap: [UInt8]? = nil,
            isNativeLowLevel: Bool
        ) {
            self.halfTrack = halfTrack
            self.bytes = bytes
            self.bitLength = bitLength ?? bytes.count * 8
            self.speedZone = speedZone
            self.speedZoneMap = speedZoneMap
            self.isNativeLowLevel = isNativeLowLevel
        }
    }

    public let format: Format
    public let tracks: [Track?]
    public let maxTrackSize: Int?

    public var hasNativeLowLevelTracks: Bool {
        tracks.contains { $0?.isNativeLowLevel == true }
    }

    public var capabilities: Capabilities {
        let populated = tracks.compactMap { $0 }
        let nativeCount = populated.filter(\.isNativeLowLevel).count
        let syntheticCount = populated.count - nativeCount
        let hasHalfTrackData = populated.contains { $0.halfTrack % 2 == 1 }
        let hasVariableLengths = Set(populated.map(\.bitLength)).count > 1
        let hasSpeedZones = populated.contains { $0.speedZoneMap != nil } ||
            (!populated.isEmpty && Set(populated.map(\.speedZone)).count > 1)
        var unsupported: [String] = []

        switch format {
        case .d64:
            unsupported.append("Native copy-protection bitstream")
        case .g64:
            unsupported.append("Weak/random bits")
            unsupported.append("Flux-level timing")
            unsupported.append("Write-back")
        }

        return Capabilities(
            format: format,
            populatedHalfTrackCount: populated.count,
            nativeLowLevelTrackCount: nativeCount,
            syntheticGCRTrackCount: syntheticCount,
            preservesHalfTracks: format == .g64 && hasHalfTrackData,
            preservesRawTrackLengths: format == .g64 && hasVariableLengths,
            preservesSpeedZones: format == .g64 && hasSpeedZones,
            supportsWraparoundReads: true,
            maxTrackSize: maxTrackSize,
            unsupportedFeatures: unsupported
        )
    }

    public init(format: Format, tracks: [Track?], maxTrackSize: Int? = nil) {
        self.format = format
        self.tracks = tracks
        self.maxTrackSize = maxTrackSize
    }
}
