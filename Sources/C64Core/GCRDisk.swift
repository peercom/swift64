import Foundation

/// Manages GCR-encoded track data for the 1541 disk drive emulation.
/// Stores raw GCR byte streams per track, as read by the drive head.
public final class GCRDisk {

    // MARK: - Constants

    /// Number of half-tracks (84 = tracks 1-42, each with 2 half-tracks)
    public static let maxHalfTracks = 84

    /// Standard track lengths in GCR bytes per speed zone
    static let trackLengths = [6250, 6666, 7142, 7692]

    /// Speed zone for each track (1-35). Zones 3,2,1,0 correspond to increasing byte rates.
    public static func speedZone(for track: Int) -> Int {
        switch track {
        case 1...17: return 3
        case 18...24: return 2
        case 25...30: return 1
        case 31...42: return 0
        default: return 0
        }
    }

    /// Cycles per GCR byte for each speed zone (at 1 MHz drive clock).
    /// Zone 3 = 26 cycles, Zone 2 = 28, Zone 1 = 30, Zone 0 = 32
    public static let cyclesPerByte = [32, 30, 28, 26]

    // MARK: - GCR encode table

    static let gcrEncode: [UInt8] = [
        0x0A, 0x0B, 0x12, 0x13, 0x0E, 0x0F, 0x16, 0x17,
        0x09, 0x19, 0x1A, 0x1B, 0x0D, 0x1D, 0x1E, 0x15,
    ]

    // MARK: - Track data

    /// Raw GCR byte streams per half-track (index 0 = half-track 0 = track 1).
    /// nil = no data for that half-track.
    public var tracks: [[UInt8]?] = Array(repeating: nil, count: maxHalfTracks)

    /// Low-level metadata for each half-track.
    public internal(set) var trackInfos: [DiskImage.Track?] = Array(repeating: nil, count: maxHalfTracks)

    /// The currently mounted low-level image, if any.
    public internal(set) var image: DiskImage?

    /// Whether a disk is inserted.
    public var hasDisk: Bool { tracks.contains { $0 != nil } }

    /// True when the inserted disk was mounted from native low-level data.
    public var hasNativeLowLevelImage: Bool {
        image?.hasNativeLowLevelTracks == true
    }

    /// Write protect tab (true = protected)
    public var writeProtected: Bool = true

    // MARK: - Init

    public init() {}

    // MARK: - Load from G64

    /// Load directly from G64 data (tracks are already GCR-encoded).
    public func loadG64(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 12 else { return false }

        let sig = String(bytes: Array(bytes[0..<8]), encoding: .ascii)
        guard sig == "GCR-1541" else { return false }

        let numTracks = Int(bytes[9])
        guard numTracks > 0 && numTracks <= 84 else { return false }

        let offsetTableStart = 12
        let speedTableStart = offsetTableStart + numTracks * 4
        guard bytes.count >= speedTableStart + numTracks * 4 else { return false }
        let maxTrackSize = Int(bytes[10]) | (Int(bytes[11]) << 8)

        // Clear existing data
        tracks = Array(repeating: nil, count: GCRDisk.maxHalfTracks)
        trackInfos = Array(repeating: nil, count: GCRDisk.maxHalfTracks)

        for i in 0..<numTracks {
            let pos = offsetTableStart + i * 4
            let offset = Int(bytes[pos])
                | (Int(bytes[pos + 1]) << 8)
                | (Int(bytes[pos + 2]) << 16)
                | (Int(bytes[pos + 3]) << 24)

            guard offset > 0 && offset + 2 <= bytes.count else { continue }

            let trackLen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            guard trackLen > 0 && offset + 2 + trackLen <= bytes.count else { continue }

            let trackBytes = Array(bytes[(offset + 2)..<(offset + 2 + trackLen)])
            let speedInfo = Self.g64SpeedInfo(
                from: bytes,
                speedTableStart: speedTableStart,
                trackIndex: i,
                trackLength: trackLen
            )
            let info = DiskImage.Track(
                halfTrack: i,
                bytes: trackBytes,
                speedZone: speedInfo?.dominantZone ?? Self.speedZone(for: i / 2 + 1),
                speedZoneMap: speedInfo?.speedZoneMap,
                isNativeLowLevel: true
            )
            tracks[i] = info.bytes
            trackInfos[i] = info
        }

        image = DiskImage(format: .g64, tracks: trackInfos, maxTrackSize: maxTrackSize)
        return true
    }

    // MARK: - Load from D64 (encode to GCR)

    /// Load from D64 data by GCR-encoding each track.
    public func loadD64(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard DiskDrive.supportedD64Sizes.contains(bytes.count) else {
            return false
        }

        tracks = Array(repeating: nil, count: GCRDisk.maxHalfTracks)
        trackInfos = Array(repeating: nil, count: GCRDisk.maxHalfTracks)

        for trackNum in 1...35 {
            let halfTrack = (trackNum - 1) * 2
            let sectorsPerTrack = DiskDrive.sectorsPerTrack[trackNum]
            let trackOffset = DiskDrive.trackOffset[trackNum]

            // Read all sectors for this track
            var sectors: [[UInt8]] = []
            for s in 0..<sectorsPerTrack {
                let offset = trackOffset + s * 256
                guard offset + 256 <= bytes.count else {
                    sectors.append([UInt8](repeating: 0, count: 256))
                    continue
                }
                sectors.append(Array(bytes[offset..<offset + 256]))
            }

            // GCR-encode this track
            let encoded = encodeTrack(
                trackNum: trackNum,
                sectors: sectors,
                diskID: extractDiskID(from: bytes)
            )
            let info = DiskImage.Track(
                halfTrack: halfTrack,
                bytes: encoded,
                speedZone: Self.speedZone(for: trackNum),
                isNativeLowLevel: false
            )
            tracks[halfTrack] = info.bytes
            trackInfos[halfTrack] = info
        }

        image = DiskImage(format: .d64, tracks: trackInfos)
        return true
    }

    public func trackInfo(halfTrack: Int) -> DiskImage.Track? {
        guard halfTrack >= 0 && halfTrack < trackInfos.count else { return nil }
        return trackInfos[halfTrack]
    }

    // MARK: - GCR encoding

    private static func g64SpeedInfo(
        from bytes: [UInt8],
        speedTableStart: Int,
        trackIndex: Int,
        trackLength: Int
    ) -> (dominantZone: Int, speedZoneMap: [UInt8]?)? {
        let pos = speedTableStart + trackIndex * 4
        guard pos + 4 <= bytes.count else { return nil }
        let value = Int(bytes[pos])
            | (Int(bytes[pos + 1]) << 8)
            | (Int(bytes[pos + 2]) << 16)
            | (Int(bytes[pos + 3]) << 24)
        if value < 4 {
            return (value, nil)
        }

        guard value > 0 && value < bytes.count else { return nil }

        let speedBlockLength = (trackLength + 3) / 4
        guard value + speedBlockLength <= bytes.count else { return nil }

        var speedZoneMap: [UInt8] = []
        speedZoneMap.reserveCapacity(trackLength)
        for speedByte in bytes[value..<(value + speedBlockLength)] {
            for shift in stride(from: 6, through: 0, by: -2) {
                speedZoneMap.append((speedByte >> UInt8(shift)) & 0x03)
                if speedZoneMap.count == trackLength { break }
            }
        }

        var counts = [Int](repeating: 0, count: 4)
        for zone in speedZoneMap {
            counts[Int(zone)] += 1
        }
        let dominantZone = counts.enumerated().max { lhs, rhs in
            lhs.element == rhs.element ? lhs.offset > rhs.offset : lhs.element < rhs.element
        }?.offset ?? 0

        return (dominantZone, speedZoneMap)
    }

    /// Extract disk ID bytes from D64 BAM (track 18, sector 0, offset $A2-$A3).
    private func extractDiskID(from d64: [UInt8]) -> (UInt8, UInt8) {
        let bamOffset = DiskDrive.trackOffset[18]
        guard bamOffset + 0xA4 <= d64.count else { return (0x41, 0x42) }
        return (d64[bamOffset + 0xA2], d64[bamOffset + 0xA3])
    }

    /// GCR-encode an entire track.
    func encodeTrack(trackNum: Int, sectors: [[UInt8]], diskID: (UInt8, UInt8)) -> [UInt8] {
        let zone = GCRDisk.speedZone(for: trackNum)
        let targetLen = GCRDisk.trackLengths[zone]

        var gcr = [UInt8]()
        gcr.reserveCapacity(targetLen)

        for (sectorNum, sectorData) in sectors.enumerated() {
            // Sync mark (5 bytes of $FF = 40 one-bits)
            gcr.append(contentsOf: [UInt8](repeating: 0xFF, count: 5))

            // Header block: $08, checksum, sector, track, id2, id1, $0F, $0F
            let checksum = UInt8(sectorNum) ^ UInt8(trackNum) ^ diskID.1 ^ diskID.0
            let header: [UInt8] = [
                0x08, checksum, UInt8(sectorNum), UInt8(trackNum),
                diskID.1, diskID.0, 0x0F, 0x0F
            ]
            gcr.append(contentsOf: encodeGCRBytes(header))

            // Header gap (9 bytes of $55)
            gcr.append(contentsOf: [UInt8](repeating: 0x55, count: 9))

            // Data sync mark
            gcr.append(contentsOf: [UInt8](repeating: 0xFF, count: 5))

            // Data block: $07, 256 data bytes, checksum, $00, $00
            var dataBlock = [UInt8]()
            dataBlock.reserveCapacity(260)
            dataBlock.append(0x07)
            dataBlock.append(contentsOf: sectorData)
            var dataChecksum: UInt8 = 0
            for b in sectorData { dataChecksum ^= b }
            dataBlock.append(dataChecksum)
            dataBlock.append(0x00)
            dataBlock.append(0x00)
            gcr.append(contentsOf: encodeGCRBytes(dataBlock))

            // Inter-sector gap (varies, fill remaining space)
            let gapSize = 8
            gcr.append(contentsOf: [UInt8](repeating: 0x55, count: gapSize))
        }

        // Pad or trim to target track length
        if gcr.count < targetLen {
            gcr.append(contentsOf: [UInt8](repeating: 0x55, count: targetLen - gcr.count))
        } else if gcr.count > targetLen {
            gcr = Array(gcr.prefix(targetLen))
        }

        return gcr
    }

    /// GCR-encode a byte array (must be multiple of 4; padded if not).
    func encodeGCRBytes(_ data: [UInt8]) -> [UInt8] {
        var padded = data
        while padded.count % 4 != 0 { padded.append(0) }

        var result = [UInt8]()
        result.reserveCapacity(padded.count * 5 / 4)

        for i in stride(from: 0, to: padded.count, by: 4) {
            result.append(contentsOf: encode4Bytes(
                padded[i], padded[i + 1], padded[i + 2], padded[i + 3]
            ))
        }
        return result
    }

    /// Encode 4 data bytes → 5 GCR bytes.
    func encode4Bytes(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> [UInt8] {
        let g0 = UInt64(GCRDisk.gcrEncode[Int(b0 >> 4)])
        let g1 = UInt64(GCRDisk.gcrEncode[Int(b0 & 0x0F)])
        let g2 = UInt64(GCRDisk.gcrEncode[Int(b1 >> 4)])
        let g3 = UInt64(GCRDisk.gcrEncode[Int(b1 & 0x0F)])
        let g4 = UInt64(GCRDisk.gcrEncode[Int(b2 >> 4)])
        let g5 = UInt64(GCRDisk.gcrEncode[Int(b2 & 0x0F)])
        let g6 = UInt64(GCRDisk.gcrEncode[Int(b3 >> 4)])
        let g7 = UInt64(GCRDisk.gcrEncode[Int(b3 & 0x0F)])

        let bits: UInt64 = (g0 << 35) | (g1 << 30) | (g2 << 25) | (g3 << 20)
                         | (g4 << 15) | (g5 << 10) | (g6 << 5) | g7

        return [
            UInt8((bits >> 32) & 0xFF),
            UInt8((bits >> 24) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8(bits & 0xFF),
        ]
    }
}
