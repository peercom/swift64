import Foundation

/// Manages GCR-encoded track data for the 1541 disk drive emulation.
/// Stores raw GCR byte streams per track, as read by the drive head.
public final class GCRDisk {
    public struct D64DecodeResult: Equatable {
        public let image: Data
        public let decodedSectorCount: Int
        public let changedSectorCount: Int
        public let incompleteTracks: [Int]
    }

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
    private static let weakBitExtensionMagic = Array("SW64WKB1".utf8)
    private static let nibMagic = Array("MNIB-1541-RAW".utf8)
    private static let nibHeaderSize = 0x100
    private static let nibTrackLength = 0x2000
    private static let maxNIBPayloadSize = nibHeaderSize + maxHalfTracks * nibTrackLength
    private static let p64Magic = Array("P64-1541".utf8)
    private static let p64HeaderSize = 24
    private static let p64ChunkHeaderSize = 12
    private static let p64RotationTicks = 3_200_000
    private static let p64StrongPulseStrength: UInt32 = 0x8000_0000

    private struct P64Pulse {
        let position: Int
        let strength: UInt32
    }

    private enum D64SectorErrorEffect {
        case ok
        case headerNotFound
        case noSync
        case dataBlockNotPresent
        case dataChecksum
        case byteDecode
        case headerChecksum
        case longDataBlock
        case diskIDMismatch

        init(code: UInt8) {
            switch code {
            case 20: self = .headerNotFound
            case 21: self = .noSync
            case 22: self = .dataBlockNotPresent
            case 23: self = .dataChecksum
            case 24: self = .byteDecode
            case 27: self = .headerChecksum
            case 28: self = .longDataBlock
            case 29: self = .diskIDMismatch
            default: self = .ok
            }
        }
    }

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

    /// True after the in-memory low-level track stream has been changed by the
    /// emulated write head. Export/write-back is tracked separately.
    public internal(set) var hasUnsavedLowLevelWrites: Bool = false

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

        let version = bytes[8]
        guard version == 0 else { return false }

        let numTracks = Int(bytes[9])
        guard numTracks > 0 && numTracks <= 84 else { return false }

        let offsetTableStart = 12
        let speedTableStart = offsetTableStart + numTracks * 4
        guard bytes.count >= speedTableStart + numTracks * 4 else { return false }
        var maxTrackSize = Int(bytes[10]) | (Int(bytes[11]) << 8)

        var newTracks: [[UInt8]?] = Array(repeating: nil, count: GCRDisk.maxHalfTracks)
        var newTrackInfos: [DiskImage.Track?] = Array(repeating: nil, count: GCRDisk.maxHalfTracks)
        var trackLengths = [Int](repeating: 0, count: numTracks)
        var trackBytesByIndex: [[UInt8]?] = Array(repeating: nil, count: numTracks)
        var trackBlockRanges: [Range<Int>] = []
        var standardPayloadEnd = speedTableStart + numTracks * 4

        for i in 0..<numTracks {
            let pos = offsetTableStart + i * 4
            let offset = Int(bytes[pos])
                | (Int(bytes[pos + 1]) << 8)
                | (Int(bytes[pos + 2]) << 16)
                | (Int(bytes[pos + 3]) << 24)

            guard offset > 0 && offset + 2 <= bytes.count else { continue }

            let trackLen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            guard trackLen > 0 && offset + 2 + trackLen <= bytes.count else { continue }
            let trackBlockRange = offset..<(offset + 2 + trackLen)
            guard !trackBlockRanges.contains(where: { Self.rangesOverlap(trackBlockRange, $0) }) else {
                return false
            }
            trackLengths[i] = trackLen
            maxTrackSize = max(maxTrackSize, trackLen)
            trackBlockRanges.append(trackBlockRange)
            standardPayloadEnd = max(standardPayloadEnd, offset + 2 + trackLen)
            trackBytesByIndex[i] = Array(bytes[(offset + 2)..<(offset + 2 + trackLen)])
        }

        for i in 0..<numTracks {
            guard let trackBytes = trackBytesByIndex[i] else { continue }
            let trackLen = trackLengths[i]
            let sectorHeaderStats = G64Parser.sectorHeaderStats(from: trackBytes, track: i / 2 + 1)
            guard let speedInfo = Self.g64SpeedInfo(
                from: bytes,
                speedTableStart: speedTableStart,
                speedTableEnd: speedTableStart + numTracks * 4,
                trackIndex: i,
                trackLength: trackLen,
                reservedRanges: trackBlockRanges
            ) else { return false }
            let info = DiskImage.Track(
                halfTrack: i,
                bytes: trackBytes,
                speedZone: speedInfo.dominantZone,
                speedZoneMap: speedInfo.speedZoneMap,
                isNativeLowLevel: true,
                duplicateSectorHeaderCount: sectorHeaderStats.duplicateSectorHeaderCount
            )
            newTracks[i] = info.bytes
            newTrackInfos[i] = info
        }

        guard newTracks.contains(where: { $0 != nil }) else { return false }

        standardPayloadEnd = max(
            standardPayloadEnd,
            Self.g64StandardPayloadEnd(
                from: bytes,
                speedTableStart: speedTableStart,
                trackLengths: trackLengths
            )
        )
        if let weakRanges = Self.g64WeakBitExtension(
            from: bytes,
            startingAt: standardPayloadEnd,
            trackInfos: newTrackInfos
        ) {
            for (halfTrack, ranges) in weakRanges {
                guard let existing = newTrackInfos[halfTrack] else { continue }
                let updated = DiskImage.Track(
                    halfTrack: existing.halfTrack,
                    bytes: existing.bytes,
                    bitLength: existing.bitLength,
                    speedZone: existing.speedZone,
                    speedZoneMap: existing.speedZoneMap,
                    weakBitRanges: ranges,
                    isNativeLowLevel: existing.isNativeLowLevel,
                    duplicateSectorHeaderCount: existing.duplicateSectorHeaderCount
                )
                newTracks[halfTrack] = updated.bytes
                newTrackInfos[halfTrack] = updated
            }
        }

        tracks = newTracks
        trackInfos = newTrackInfos
        image = DiskImage(format: .g64, tracks: newTrackInfos, maxTrackSize: maxTrackSize)
        writeProtected = true
        hasUnsavedLowLevelWrites = false
        return true
    }

    // MARK: - Load from NIB

    /// Load raw NIBTOOLS `MNIB-1541-RAW` images as native low-level tracks.
    ///
    /// NIB stores 8192 bytes per captured halftrack, with header entries using
    /// nibtools' two-based halftrack numbering: 2 is track 1.0, 3 is track 1.5.
    public func loadNIB(_ data: Data) -> Bool {
        loadNIBPayload(data, format: .nib)
    }

    /// Load compressed NIBTOOLS NBZ images as native low-level tracks.
    ///
    /// NBZ is a NIB image compressed with the NIBTOOLS LZ77 marker stream
    /// (`LZ_Uncompress` in nibtools), not gzip/zlib.
    public func loadNBZ(_ data: Data) -> Bool {
        guard let decompressed = Self.nibtoolsLZUncompressed(
            [UInt8](data),
            maxOutputBytes: Self.maxNIBPayloadSize
        ) else {
            return false
        }
        return loadNIBPayload(Data(decompressed), format: .nbz)
    }

    /// Load VICE/Micro64 P64 NRZI flux-pulse images as native low-level tracks.
    ///
    /// P64 stores transition positions at 16 MHz resolution. The current 1541
    /// head consumes GCR bit cells, so this importer range-decodes the flux
    /// pulses and quantizes them onto the closest standard 1541 speed-zone bit
    /// cells. Sub-maximum pulse strengths are kept as weak-bit annotations.
    public func loadP64(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= Self.p64HeaderSize,
              Array(bytes[0..<8]) == Self.p64Magic,
              Self.littleEndian32(from: bytes, at: 8) == 0,
              let flags = Self.littleEndian32(from: bytes, at: 12),
              let chunkStreamSizeValue = Self.littleEndian32(from: bytes, at: 16),
              let expectedStreamCRC = Self.littleEndian32(from: bytes, at: 20) else {
            return false
        }

        guard flags & 0x02 == 0 else { return false }
        let chunkStreamSize = Int(chunkStreamSizeValue)
        let chunkStreamStart = Self.p64HeaderSize
        guard chunkStreamSize >= 0,
              chunkStreamStart + chunkStreamSize == bytes.count else {
            return false
        }
        guard Self.crc32(Array(bytes[chunkStreamStart..<bytes.count])) == expectedStreamCRC else {
            return false
        }

        var newTracks: [[UInt8]?] = Array(repeating: nil, count: GCRDisk.maxHalfTracks)
        var newTrackInfos: [DiskImage.Track?] = Array(repeating: nil, count: GCRDisk.maxHalfTracks)
        var offset = chunkStreamStart
        let streamEnd = chunkStreamStart + chunkStreamSize
        var sawDone = false

        while offset < streamEnd {
            guard offset + Self.p64ChunkHeaderSize <= streamEnd else { return false }
            let signature = Array(bytes[offset..<(offset + 4)])
            guard let chunkSizeValue = Self.littleEndian32(from: bytes, at: offset + 4),
                  let expectedChunkCRC = Self.littleEndian32(from: bytes, at: offset + 8) else {
                return false
            }
            let chunkSize = Int(chunkSizeValue)
            let chunkDataStart = offset + Self.p64ChunkHeaderSize
            let chunkDataEnd = chunkDataStart + chunkSize
            guard chunkSize >= 0, chunkDataEnd <= streamEnd else { return false }
            let chunkData = Array(bytes[chunkDataStart..<chunkDataEnd])
            guard Self.crc32(chunkData) == expectedChunkCRC else { return false }

            if signature == Array("DONE".utf8) {
                guard chunkSize == 0 else { return false }
                sawDone = true
                offset = chunkDataEnd
                break
            }

            if signature.count == 4,
               signature[0] == UInt8(ascii: "H"),
               signature[1] == UInt8(ascii: "T"),
               signature[2] == UInt8(ascii: "P") {
                guard signature[3] & 0x80 == 0 else { return false }
                let p64HalfTrack = Int(signature[3] & 0x7F)
                let halfTrack = p64HalfTrack - 2
                guard halfTrack >= 0 && halfTrack < Self.maxHalfTracks else {
                    return false
                }
                guard newTrackInfos[halfTrack] == nil else {
                    return false
                }
                guard chunkSize >= 8 else { return false }

                guard let pulseCountValue = Self.littleEndian32(from: bytes, at: chunkDataStart),
                      let encodedSizeValue = Self.littleEndian32(from: bytes, at: chunkDataStart + 4) else {
                    return false
                }
                let pulseCount = Int(pulseCountValue)
                let encodedSize = Int(encodedSizeValue)
                let encodedStart = chunkDataStart + 8
                let encodedEnd = encodedStart + encodedSize
                guard pulseCount >= 0, encodedSize >= 0, encodedEnd <= chunkDataEnd else {
                    return false
                }

                let encoded = Array(bytes[encodedStart..<encodedEnd])
                guard let pulses = Self.decodeP64Pulses(encoded, pulseCount: pulseCount) else {
                    return false
                }
                let speedZone = Self.speedZone(for: halfTrack / 2 + 1)
                let converted = Self.p64Track(from: pulses, halfTrack: halfTrack, speedZone: speedZone)
                guard !converted.bytes.isEmpty else { return false }

                let sectorHeaderStats = G64Parser.sectorHeaderStats(
                    from: converted.bytes,
                    track: halfTrack / 2 + 1
                )
                let info = DiskImage.Track(
                    halfTrack: halfTrack,
                    bytes: converted.bytes,
                    bitLength: converted.bitLength,
                    speedZone: speedZone,
                    weakBitRanges: converted.weakBitRanges,
                    isNativeLowLevel: true,
                    duplicateSectorHeaderCount: sectorHeaderStats.duplicateSectorHeaderCount
                )
                newTracks[halfTrack] = info.bytes
                newTrackInfos[halfTrack] = info
            }

            offset = chunkDataEnd
        }

        guard sawDone,
              offset == streamEnd,
              newTracks.contains(where: { $0 != nil }) else {
            return false
        }

        tracks = newTracks
        trackInfos = newTrackInfos
        image = DiskImage(
            format: .p64,
            tracks: newTrackInfos,
            maxTrackSize: newTrackInfos.compactMap { $0?.bytes.count }.max()
        )
        writeProtected = (flags & 0x01) != 0
        hasUnsavedLowLevelWrites = false
        return true
    }

    private func loadNIBPayload(_ data: Data, format: DiskImage.Format) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= Self.nibHeaderSize,
              bytes.starts(with: Self.nibMagic) else {
            return false
        }

        var newTracks: [[UInt8]?] = Array(repeating: nil, count: GCRDisk.maxHalfTracks)
        var newTrackInfos: [DiskImage.Track?] = Array(repeating: nil, count: GCRDisk.maxHalfTracks)
        var entryOffset = 0x10
        var payloadOffset = Self.nibHeaderSize
        var populated = 0

        while entryOffset + 1 < Self.nibHeaderSize {
            let nibHalfTrack = Int(bytes[entryOffset])
            if nibHalfTrack == 0 { break }
            let rawDensity = bytes[entryOffset + 1]
            let halfTrack = nibHalfTrack - 2
            guard halfTrack >= 0 && halfTrack < GCRDisk.maxHalfTracks else {
                return false
            }
            guard newTrackInfos[halfTrack] == nil else {
                return false
            }
            guard payloadOffset + Self.nibTrackLength <= bytes.count else {
                return false
            }

            let trackBytes = Array(bytes[payloadOffset..<(payloadOffset + Self.nibTrackLength)])
            let speedZone = Int(rawDensity % 0x10) & 0x03
            let sectorHeaderStats = G64Parser.sectorHeaderStats(
                from: trackBytes,
                track: halfTrack / 2 + 1
            )
            let info = DiskImage.Track(
                halfTrack: halfTrack,
                bytes: trackBytes,
                speedZone: speedZone,
                isNativeLowLevel: true,
                duplicateSectorHeaderCount: sectorHeaderStats.duplicateSectorHeaderCount
            )
            newTracks[halfTrack] = trackBytes
            newTrackInfos[halfTrack] = info
            populated += 1
            entryOffset += 2
            payloadOffset += Self.nibTrackLength
        }

        guard populated > 0 else { return false }
        tracks = newTracks
        trackInfos = newTrackInfos
        image = DiskImage(format: format, tracks: newTrackInfos, maxTrackSize: Self.nibTrackLength)
        writeProtected = true
        hasUnsavedLowLevelWrites = false
        return true
    }

    // MARK: - Load from D64 (encode to GCR)

    /// Load from D64 data by GCR-encoding each track.
    public func loadD64(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard let geometry = DiskDrive.d64Geometry(forByteCount: bytes.count) else {
            return false
        }

        tracks = Array(repeating: nil, count: GCRDisk.maxHalfTracks)
        trackInfos = Array(repeating: nil, count: GCRDisk.maxHalfTracks)
        let sectorErrorCodes = d64SectorErrorCodes(from: bytes, geometry: geometry)

        for trackNum in 1...geometry.trackCount {
            let halfTrack = (trackNum - 1) * 2
            let sectorsPerTrack = geometry.sectorsPerTrack[trackNum]
            let trackOffset = geometry.trackOffsets[trackNum]

            // Read all sectors for this track
            var sectors: [[UInt8]] = []
            for s in 0..<sectorsPerTrack {
                let offset = trackOffset + s * 256
                guard offset + 256 <= geometry.dataSize, offset + 256 <= bytes.count else {
                    sectors.append([UInt8](repeating: 0, count: 256))
                    continue
                }
                sectors.append(Array(bytes[offset..<offset + 256]))
            }

            // GCR-encode this track
            let encoded = encodeTrack(
                trackNum: trackNum,
                sectors: sectors,
                diskID: extractDiskID(from: bytes),
                sectorErrorCodes: sectorErrorCodesForTrack(trackNum, geometry: geometry, allCodes: sectorErrorCodes)
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

        image = DiskImage(
            format: .d64,
            tracks: trackInfos,
            sectorErrorCodes: sectorErrorCodes
        )
        writeProtected = false
        hasUnsavedLowLevelWrites = false
        return true
    }

    public func trackInfo(halfTrack: Int) -> DiskImage.Track? {
        guard halfTrack >= 0 && halfTrack < trackInfos.count else { return nil }
        return trackInfos[halfTrack]
    }

    /// Annotate an already-loaded low-level track with weak/random bit ranges.
    /// This is used by protected-media importers that can identify unstable
    /// regions separately from the raw byte stream.
    @discardableResult
    public func setWeakBitRanges(
        _ ranges: [DiskImage.Track.WeakBitRange],
        forHalfTrack halfTrack: Int
    ) -> Bool {
        guard halfTrack >= 0 && halfTrack < trackInfos.count,
              let existing = trackInfos[halfTrack] else {
            return false
        }
        guard ranges.allSatisfy({ $0.startBit >= 0 && $0.startBit <= $0.endBit && $0.endBit < existing.bitLength }) else {
            return false
        }

        let updated = DiskImage.Track(
            halfTrack: existing.halfTrack,
            bytes: existing.bytes,
            bitLength: existing.bitLength,
            speedZone: existing.speedZone,
            speedZoneMap: existing.speedZoneMap,
            weakBitRanges: ranges,
            isNativeLowLevel: existing.isNativeLowLevel,
            duplicateSectorHeaderCount: existing.duplicateSectorHeaderCount
        )
        trackInfos[halfTrack] = updated
        tracks[halfTrack] = updated.bytes
        if let image {
            self.image = DiskImage(
                format: image.format,
                tracks: trackInfos,
                maxTrackSize: image.maxTrackSize,
                sectorErrorCodes: image.sectorErrorCodes
            )
        }
        return true
    }

    /// Add weak/random bit annotations to an existing track, splitting around
    /// track wrap and merging with any existing weak ranges.
    @discardableResult
    public func addWeakBitRange(startBit: Int, bitCount: Int, forHalfTrack halfTrack: Int) -> Bool {
        guard halfTrack >= 0 && halfTrack < trackInfos.count,
              let existing = trackInfos[halfTrack],
              existing.bitLength > 0,
              bitCount > 0 else {
            return false
        }

        let wrappedStart = ((startBit % existing.bitLength) + existing.bitLength) % existing.bitLength
        let addedRanges = Self.bitRanges(
            start: wrappedStart,
            count: bitCount,
            totalBits: existing.bitLength
        ).map {
            DiskImage.Track.WeakBitRange(startBit: $0.lowerBound, endBit: $0.upperBound)
        }
        let weakBitRanges = Self.mergedWeakBitRanges(existing.weakBitRanges + addedRanges)
        let updated = DiskImage.Track(
            halfTrack: existing.halfTrack,
            bytes: existing.bytes,
            bitLength: existing.bitLength,
            speedZone: existing.speedZone,
            speedZoneMap: existing.speedZoneMap,
            weakBitRanges: weakBitRanges,
            isNativeLowLevel: existing.isNativeLowLevel,
            duplicateSectorHeaderCount: existing.duplicateSectorHeaderCount
        )
        trackInfos[halfTrack] = updated
        tracks[halfTrack] = updated.bytes
        if let image {
            self.image = DiskImage(
                format: image.format,
                tracks: trackInfos,
                maxTrackSize: image.maxTrackSize,
                sectorErrorCodes: image.sectorErrorCodes
            )
        }
        hasUnsavedLowLevelWrites = true
        return true
    }

    /// Annotate an already-loaded track with per-byte speed-zone ranges.
    /// Ranges are expanded into a full speed map so the GCR head can vary UE7
    /// timing while reading protected-media regions.
    @discardableResult
    public func setSpeedZoneRanges(
        _ ranges: [DiskImage.Track.SpeedZoneRange],
        forHalfTrack halfTrack: Int
    ) -> Bool {
        guard halfTrack >= 0 && halfTrack < trackInfos.count,
              let existing = trackInfos[halfTrack] else {
            return false
        }
        guard ranges.allSatisfy({
            $0.startByte >= 0
                && $0.startByte <= $0.endByte
                && $0.endByte < existing.bytes.count
                && $0.zone <= 3
        }) else {
            return false
        }

        var speedZoneMap = existing.speedZoneMap ?? [UInt8](repeating: UInt8(clamping: existing.speedZone), count: existing.bytes.count)
        for range in ranges {
            for byteIndex in range.startByte...range.endByte {
                speedZoneMap[byteIndex] = range.zone
            }
        }
        var counts = [Int](repeating: 0, count: 4)
        for zone in speedZoneMap {
            counts[Int(zone)] += 1
        }
        let dominantZone = counts.enumerated().max { lhs, rhs in
            lhs.element == rhs.element ? lhs.offset > rhs.offset : lhs.element < rhs.element
        }?.offset ?? existing.speedZone

        let updated = DiskImage.Track(
            halfTrack: existing.halfTrack,
            bytes: existing.bytes,
            bitLength: existing.bitLength,
            speedZone: dominantZone,
            speedZoneMap: speedZoneMap,
            weakBitRanges: existing.weakBitRanges,
            isNativeLowLevel: existing.isNativeLowLevel,
            duplicateSectorHeaderCount: existing.duplicateSectorHeaderCount
        )
        trackInfos[halfTrack] = updated
        tracks[halfTrack] = updated.bytes
        if let image {
            self.image = DiskImage(
                format: image.format,
                tracks: trackInfos,
                maxTrackSize: image.maxTrackSize,
                sectorErrorCodes: image.sectorErrorCodes
            )
        }
        return true
    }

    @discardableResult
    public func writeByte(_ value: UInt8, halfTrack: Int, byteIndex: Int) -> Bool {
        writeByte(value, halfTrack: halfTrack, byteIndex: byteIndex, speedZone: nil)
    }

    @discardableResult
    public func writeByte(_ value: UInt8, halfTrack: Int, byteIndex: Int, speedZone: Int?) -> Bool {
        guard !writeProtected,
              halfTrack >= 0 && halfTrack < tracks.count,
              var bytes = tracks[halfTrack],
              byteIndex >= 0 && byteIndex < bytes.count else {
            return false
        }

        bytes[byteIndex] = value
        tracks[halfTrack] = bytes
        updateTrackAfterWrite(
            halfTrack: halfTrack,
            bytes: bytes,
            writtenBitRanges: [byteIndex * 8...(byteIndex * 8 + 7)],
            writtenSpeedZone: speedZone,
            rebuildImage: true
        )
        hasUnsavedLowLevelWrites = true
        return true
    }

    @discardableResult
    public func writeByteAtBitPosition(_ value: UInt8, halfTrack: Int, bitPosition: Int) -> Bool {
        writeByteAtBitPosition(value, halfTrack: halfTrack, bitPosition: bitPosition, speedZone: nil)
    }

    @discardableResult
    public func writeByteAtBitPosition(_ value: UInt8, halfTrack: Int, bitPosition: Int, speedZone: Int?) -> Bool {
        guard !writeProtected,
              halfTrack >= 0 && halfTrack < tracks.count,
              var bytes = tracks[halfTrack],
              !bytes.isEmpty else {
            return false
        }

        let totalBits = (trackInfos[halfTrack]?.bitLength ?? bytes.count * 8)
        guard totalBits > 0 else { return false }
        let wrappedBitPosition = ((bitPosition % totalBits) + totalBits) % totalBits
        let writtenBitRanges = Self.bitRanges(start: wrappedBitPosition, count: 8, totalBits: totalBits)

        for sourceBitOffset in 0..<8 {
            let targetBit = (wrappedBitPosition + sourceBitOffset) % totalBits
            let byteIndex = targetBit / 8
            let bitIndex = 7 - (targetBit % 8)
            guard byteIndex >= 0 && byteIndex < bytes.count else { return false }

            let mask = UInt8(1 << bitIndex)
            let sourceBit = (value >> UInt8(7 - sourceBitOffset)) & 0x01
            if sourceBit == 0 {
                bytes[byteIndex] &= ~mask
            } else {
                bytes[byteIndex] |= mask
            }
        }

        tracks[halfTrack] = bytes
        updateTrackAfterWrite(
            halfTrack: halfTrack,
            bytes: bytes,
            writtenBitRanges: writtenBitRanges,
            writtenSpeedZone: speedZone,
            rebuildImage: true
        )
        hasUnsavedLowLevelWrites = true
        return true
    }

    @discardableResult
    public func writeBitAtBitPosition(_ bit: Bool, halfTrack: Int, bitPosition: Int) -> Bool {
        writeBitAtBitPosition(bit, halfTrack: halfTrack, bitPosition: bitPosition, speedZone: nil)
    }

    @discardableResult
    public func writeBitAtBitPosition(_ bit: Bool, halfTrack: Int, bitPosition: Int, speedZone: Int?) -> Bool {
        guard !writeProtected,
              halfTrack >= 0 && halfTrack < tracks.count,
              var bytes = tracks[halfTrack],
              !bytes.isEmpty else {
            return false
        }

        let totalBits = (trackInfos[halfTrack]?.bitLength ?? bytes.count * 8)
        guard totalBits > 0 else { return false }
        let wrappedBitPosition = ((bitPosition % totalBits) + totalBits) % totalBits
        let byteIndex = wrappedBitPosition / 8
        let bitIndex = 7 - (wrappedBitPosition % 8)
        guard byteIndex >= 0 && byteIndex < bytes.count else { return false }

        let mask = UInt8(1 << bitIndex)
        if bit {
            bytes[byteIndex] |= mask
        } else {
            bytes[byteIndex] &= ~mask
        }

        tracks[halfTrack] = bytes
        updateTrackAfterWrite(
            halfTrack: halfTrack,
            bytes: bytes,
            writtenBitRanges: [wrappedBitPosition...wrappedBitPosition],
            writtenSpeedZone: speedZone,
            rebuildImage: false
        )
        hasUnsavedLowLevelWrites = true
        return true
    }

    /// Ensure a native low-level track stream exists for write-head activity.
    ///
    /// D64-backed synthetic tracks are pre-populated for full tracks. Creating
    /// new low-level tracks is reserved for native media because D64 cannot
    /// represent arbitrary halftracks or raw bitstreams.
    @discardableResult
    public func ensureWritableTrack(
        halfTrack: Int,
        speedZone: Int,
        fillByte: UInt8 = 0x55
    ) -> Bool {
        guard image?.hasNativeLowLevelTracks == true,
              halfTrack >= 0 && halfTrack < tracks.count else {
            return false
        }
        if let existing = tracks[halfTrack], !existing.isEmpty {
            return true
        }

        let zone = max(0, min(3, speedZone))
        let byteCount = Self.trackLengths[zone]
        let bytes = [UInt8](repeating: fillByte, count: byteCount)
        let track = DiskImage.Track(
            halfTrack: halfTrack,
            bytes: bytes,
            speedZone: zone,
            isNativeLowLevel: true
        )

        tracks[halfTrack] = bytes
        trackInfos[halfTrack] = track
        if let image {
            let maxTrackSize = image.maxTrackSize.map { max($0, byteCount) } ?? byteCount
            self.image = DiskImage(
                format: image.format,
                tracks: trackInfos,
                maxTrackSize: maxTrackSize,
                sectorErrorCodes: image.sectorErrorCodes
            )
        }
        hasUnsavedLowLevelWrites = true
        return true
    }

    /// Decode the current whole-track GCR streams back into a D64-shaped image.
    ///
    /// This is intentionally conservative: it only patches sectors that decode
    /// with valid headers, data markers, and checksums. Native protected G64
    /// features remain in the low-level image; this bridge is for D64-backed
    /// synthetic tracks whose modified bytes can be represented as sectors.
    public func decodedD64Image(
        patching baseImage: Data,
        refreshingMetadata: Bool = true
    ) -> D64DecodeResult? {
        guard image?.format == .d64,
              let geometry = DiskDrive.d64Geometry(forByteCount: baseImage.count) else {
            return nil
        }

        var output = [UInt8](baseImage)
        var decodedSectorCount = 0
        var changedSectorCount = 0
        var incompleteTracks: [Int] = []

        for trackNum in 1...geometry.trackCount {
            let halfTrack = (trackNum - 1) * 2
            guard halfTrack >= 0 && halfTrack < tracks.count,
                  let trackBytes = tracks[halfTrack],
                  !trackBytes.isEmpty else {
                incompleteTracks.append(trackNum)
                continue
            }

            let expectedSectors = geometry.sectorsPerTrack[trackNum]
            let decodedSectors = G64Parser.decodeSectors(
                from: trackBytes,
                track: trackNum,
                expectedSectors: expectedSectors
            )
            if decodedSectors.count < expectedSectors {
                incompleteTracks.append(trackNum)
            }
            decodedSectorCount += decodedSectors.count

            for (sectorNum, sectorData) in decodedSectors {
                guard sectorNum >= 0,
                      sectorNum < expectedSectors,
                      sectorData.count == 256 else {
                    continue
                }
                let offset = geometry.trackOffsets[trackNum] + sectorNum * 256
                guard offset + 256 <= geometry.dataSize,
                      offset + 256 <= output.count else {
                    continue
                }
                var sectorChanged = false
                if !output[offset..<(offset + 256)].elementsEqual(sectorData) {
                    output.replaceSubrange(offset..<(offset + 256), with: sectorData)
                    sectorChanged = true
                }
                if clearSectorErrorCode(track: trackNum, sector: sectorNum, in: &output, geometry: geometry) {
                    sectorChanged = true
                }
                if sectorChanged {
                    changedSectorCount += 1
                }
            }
        }

        guard decodedSectorCount > 0 else { return nil }
        if refreshingMetadata && changedSectorCount > 0 {
            refreshD64SectorErrorMetadata(from: output, geometry: geometry)
        }
        return D64DecodeResult(
            image: Data(output),
            decodedSectorCount: decodedSectorCount,
            changedSectorCount: changedSectorCount,
            incompleteTracks: incompleteTracks
        )
    }

    public var exportedG64Image: Data? {
        guard image?.hasNativeLowLevelTracks == true else { return nil }
        let populatedHalfTrackIndexes = trackInfos.indices.filter { trackInfos[$0] != nil }
        guard !populatedHalfTrackIndexes.isEmpty else { return nil }

        let numTracks = min(Self.maxHalfTracks, max(Self.maxHalfTracks, (populatedHalfTrackIndexes.max() ?? 0) + 1))
        var offsetTable = [UInt32](repeating: 0, count: numTracks)
        var speedEntries = [UInt32](repeating: 0, count: numTracks)
        var speedBlocks: [(trackIndex: Int, bytes: [UInt8])] = []
        let maxTrackSize = max(
            image?.maxTrackSize ?? 0,
            populatedHalfTrackIndexes.map { trackInfos[$0]?.bytes.count ?? 0 }.max() ?? 0
        )
        guard maxTrackSize <= Int(UInt16.max) else { return nil }

        var data: [UInt8] = []
        data.append(contentsOf: Array("GCR-1541".utf8))
        data.append(0x00)
        data.append(UInt8(numTracks))
        data.append(UInt8(maxTrackSize & 0xFF))
        data.append(UInt8((maxTrackSize >> 8) & 0xFF))

        let offsetTableStart = data.count
        data.append(contentsOf: [UInt8](repeating: 0, count: numTracks * 4))
        let speedTableStart = data.count
        data.append(contentsOf: [UInt8](repeating: 0, count: numTracks * 4))

        for trackIndex in 0..<numTracks {
            guard let track = trackInfos[trackIndex] else { continue }
            guard track.bytes.count <= Int(UInt16.max) else { return nil }
            offsetTable[trackIndex] = UInt32(data.count)
            data.append(UInt8(track.bytes.count & 0xFF))
            data.append(UInt8((track.bytes.count >> 8) & 0xFF))
            data.append(contentsOf: track.bytes)

            if let speedZoneMap = track.speedZoneMap, !speedZoneMap.isEmpty {
                speedBlocks.append((trackIndex: trackIndex, bytes: Self.packedG64SpeedBlock(speedZoneMap, byteCount: track.bytes.count)))
            } else {
                speedEntries[trackIndex] = UInt32(max(0, min(3, track.speedZone)))
            }
        }

        for speedBlock in speedBlocks {
            speedEntries[speedBlock.trackIndex] = UInt32(data.count)
            data.append(contentsOf: speedBlock.bytes)
        }

        for trackIndex in 0..<numTracks {
            Self.writeLittleEndian32(offsetTable[trackIndex], into: &data, at: offsetTableStart + trackIndex * 4)
            Self.writeLittleEndian32(speedEntries[trackIndex], into: &data, at: speedTableStart + trackIndex * 4)
        }

        Self.appendWeakBitExtension(from: trackInfos, to: &data)
        return Data(data)
    }

    public func markLowLevelWritesSaved() {
        hasUnsavedLowLevelWrites = false
    }

    private func updateTrackAfterWrite(
        halfTrack: Int,
        bytes: [UInt8],
        writtenBitRanges: [ClosedRange<Int>],
        writtenSpeedZone: Int? = nil,
        rebuildImage: Bool
    ) {
        let existing = trackInfos[halfTrack]
        let weakBitRanges = writtenBitRanges.reduce(existing?.weakBitRanges ?? []) { ranges, writtenRange in
            ranges.flatMap { Self.removingBits(writtenRange, from: $0) }
        }
        let baseSpeedZone = existing?.speedZone ?? Self.speedZone(for: halfTrack / 2 + 1)
        let updatedSpeedZone = Self.updatedSpeedZoneState(
            existingMap: existing?.speedZoneMap,
            baseSpeedZone: baseSpeedZone,
            byteCount: bytes.count,
            writtenBitRanges: writtenBitRanges,
            writtenSpeedZone: writtenSpeedZone
        )
        let updated = DiskImage.Track(
            halfTrack: existing?.halfTrack ?? halfTrack,
            bytes: bytes,
            bitLength: existing?.bitLength ?? bytes.count * 8,
            speedZone: updatedSpeedZone.zone,
            speedZoneMap: updatedSpeedZone.map,
            weakBitRanges: weakBitRanges,
            isNativeLowLevel: existing?.isNativeLowLevel ?? (image?.format == .g64),
            duplicateSectorHeaderCount: existing?.duplicateSectorHeaderCount ?? 0
        )
        trackInfos[halfTrack] = updated
        guard rebuildImage else { return }
        rebuildMountedImage(maxTrackSizeFloor: bytes.count)
    }

    private func rebuildMountedImage(maxTrackSizeFloor: Int? = nil) {
        guard let image else { return }
        let maxTrackSize: Int?
        if let floor = maxTrackSizeFloor {
            maxTrackSize = image.maxTrackSize.map { max($0, floor) }
        } else {
            maxTrackSize = image.maxTrackSize
        }
        self.image = DiskImage(
            format: image.format,
            tracks: trackInfos,
            maxTrackSize: maxTrackSize,
            sectorErrorCodes: image.sectorErrorCodes
        )
    }

    private static func bitRanges(start: Int, count: Int, totalBits: Int) -> [ClosedRange<Int>] {
        guard count > 0, totalBits > 0 else { return [] }
        let cappedCount = min(count, totalBits)
        let end = start + cappedCount - 1
        if end < totalBits {
            return [start...end]
        }
        return [start...(totalBits - 1), 0...(end % totalBits)]
    }

    private static func updatedSpeedZoneState(
        existingMap: [UInt8]?,
        baseSpeedZone: Int,
        byteCount: Int,
        writtenBitRanges: [ClosedRange<Int>],
        writtenSpeedZone: Int?
    ) -> (zone: Int, map: [UInt8]?) {
        let baseZone = max(0, min(3, baseSpeedZone))
        guard byteCount > 0,
              let writtenSpeedZone else {
            return (baseZone, existingMap)
        }

        let zone = UInt8(max(0, min(3, writtenSpeedZone)))
        guard existingMap != nil || Int(zone) != baseZone else {
            return (baseZone, nil)
        }

        var speedZoneMap = existingMap ?? [UInt8](repeating: UInt8(baseZone), count: byteCount)
        if speedZoneMap.count < byteCount {
            speedZoneMap.append(contentsOf: [UInt8](repeating: UInt8(baseZone), count: byteCount - speedZoneMap.count))
        } else if speedZoneMap.count > byteCount {
            speedZoneMap = Array(speedZoneMap.prefix(byteCount))
        }

        for range in writtenBitRanges {
            let startByte = max(0, range.lowerBound / 8)
            let endByte = min(byteCount - 1, range.upperBound / 8)
            guard startByte <= endByte else { continue }
            for byteIndex in startByte...endByte {
                speedZoneMap[byteIndex] = zone
            }
        }

        var counts = [Int](repeating: 0, count: 4)
        for zone in speedZoneMap {
            counts[Int(min(zone, 3))] += 1
        }
        let dominantZone = counts.enumerated().max { lhs, rhs in
            lhs.element == rhs.element ? lhs.offset > rhs.offset : lhs.element < rhs.element
        }?.offset ?? baseZone
        return (dominantZone, speedZoneMap)
    }

    private static func removingBits(
        _ removed: ClosedRange<Int>,
        from range: DiskImage.Track.WeakBitRange
    ) -> [DiskImage.Track.WeakBitRange] {
        if removed.upperBound < range.startBit || removed.lowerBound > range.endBit {
            return [range]
        }

        var ranges: [DiskImage.Track.WeakBitRange] = []
        if range.startBit < removed.lowerBound {
            ranges.append(DiskImage.Track.WeakBitRange(
                startBit: range.startBit,
                endBit: removed.lowerBound - 1
            ))
        }
        if range.endBit > removed.upperBound {
            ranges.append(DiskImage.Track.WeakBitRange(
                startBit: removed.upperBound + 1,
                endBit: range.endBit
            ))
        }
        return ranges
    }

    private static func mergedWeakBitRanges(
        _ ranges: [DiskImage.Track.WeakBitRange]
    ) -> [DiskImage.Track.WeakBitRange] {
        let sorted = ranges
            .filter { $0.startBit <= $0.endBit }
            .sorted { lhs, rhs in
                lhs.startBit == rhs.startBit ? lhs.endBit < rhs.endBit : lhs.startBit < rhs.startBit
            }
        guard var current = sorted.first else { return [] }

        var merged: [DiskImage.Track.WeakBitRange] = []
        for range in sorted.dropFirst() {
            if range.startBit <= current.endBit + 1 {
                current = DiskImage.Track.WeakBitRange(
                    startBit: current.startBit,
                    endBit: max(current.endBit, range.endBit)
                )
            } else {
                merged.append(current)
                current = range
            }
        }
        merged.append(current)
        return merged
    }

    @discardableResult
    private func clearSectorErrorCode(track: Int, sector: Int, in image: inout [UInt8], geometry: DiskDrive.D64Geometry) -> Bool {
        guard let errorInfoOffset = geometry.errorInfoOffset,
              let ordinal = sectorOrdinal(track: track, sector: sector, geometry: geometry) else {
            return false
        }

        let errorOffset = errorInfoOffset + ordinal
        guard errorOffset < image.count,
              image[errorOffset] != 0x01 else {
            return false
        }
        image[errorOffset] = 0x01
        return true
    }

    private func sectorOrdinal(track: Int, sector: Int, geometry: DiskDrive.D64Geometry) -> Int? {
        guard track >= 1 && track <= geometry.trackCount,
              sector >= 0 && sector < geometry.sectorsPerTrack[track] else {
            return nil
        }

        var ordinal = sector
        if track > 1 {
            for previousTrack in 1..<track {
                ordinal += geometry.sectorsPerTrack[previousTrack]
            }
        }
        return ordinal
    }

    private func refreshD64SectorErrorMetadata(from bytes: [UInt8], geometry: DiskDrive.D64Geometry) {
        guard let current = image,
              current.format == .d64 else {
            return
        }

        self.image = DiskImage(
            format: current.format,
            tracks: trackInfos,
            maxTrackSize: current.maxTrackSize,
            sectorErrorCodes: d64SectorErrorCodes(from: bytes, geometry: geometry)
        )
    }

    private static func packedG64SpeedBlock(_ speedZoneMap: [UInt8], byteCount: Int) -> [UInt8] {
        var zones = Array(speedZoneMap.prefix(byteCount))
        if zones.count < byteCount {
            zones.append(contentsOf: [UInt8](repeating: zones.last ?? 0, count: byteCount - zones.count))
        }

        var packed: [UInt8] = []
        packed.reserveCapacity((byteCount + 3) / 4)
        for index in stride(from: 0, to: byteCount, by: 4) {
            let z0 = zones[index] & 0x03
            let z1 = index + 1 < zones.count ? zones[index + 1] & 0x03 : z0
            let z2 = index + 2 < zones.count ? zones[index + 2] & 0x03 : z1
            let z3 = index + 3 < zones.count ? zones[index + 3] & 0x03 : z2
            packed.append((z0 << 6) | (z1 << 4) | (z2 << 2) | z3)
        }
        return packed
    }

    private static func writeLittleEndian32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        guard offset >= 0 && offset + 4 <= bytes.count else { return }
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private static func appendLittleEndian16(_ value: UInt16, to bytes: inout [UInt8]) {
        bytes.append(UInt8(value & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendLittleEndian32(_ value: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8(value & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 24) & 0xFF))
    }

    private static func littleEndian16(from bytes: [UInt8], at offset: Int) -> UInt16? {
        guard offset >= 0 && offset + 2 <= bytes.count else { return nil }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func littleEndian32(from bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0 && offset + 4 <= bytes.count else { return nil }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func decodeP64Pulses(_ encoded: [UInt8], pulseCount: Int) -> [P64Pulse]? {
        guard pulseCount >= 0 else { return nil }
        var decoder = P64RangeDecoder(bytes: encoded)
        guard decoder.start() else { return nil }

        var probabilities = [UInt32](repeating: 2048, count: 8 * 65_536 + 4)
        var states = [UInt16](repeating: 0, count: 10)
        let offsets = [
            0,
            65_536,
            131_072,
            196_608,
            262_144,
            327_680,
            393_216,
            458_752,
            524_288,
            524_290,
        ]

        func decodeBit(model: Int) -> UInt32? {
            let index = offsets[model] + Int(states[model])
            guard index >= 0 && index < probabilities.count else { return nil }
            guard let bit = decoder.decodeBit(probability: &probabilities[index], shift: 4) else {
                return nil
            }
            states[model] = UInt16(bit)
            return bit
        }

        func decodeDWord(model: Int) -> UInt32? {
            var value: UInt32 = 0
            for byteIndex in 0..<4 {
                var byteValue: UInt32 = 0
                var context: UInt16 = 1
                for bitIndex in stride(from: 7, through: 0, by: -1) {
                    let probabilityIndex = offsets[model + byteIndex]
                        + Int(((states[model + byteIndex] << 8) | context) & 0xFFFF)
                    guard probabilityIndex >= 0 && probabilityIndex < probabilities.count,
                          let bit = decoder.decodeBit(probability: &probabilities[probabilityIndex], shift: 4) else {
                        return nil
                    }
                    byteValue |= bit << UInt32(bitIndex)
                    context = (context << 1) | UInt16(bit)
                }
                states[model + byteIndex] = UInt16(byteValue)
                value |= byteValue << UInt32(byteIndex * 8)
            }
            return value
        }

        var pulses: [P64Pulse] = []
        pulses.reserveCapacity(min(pulseCount, 100_000))
        var lastPosition: UInt32 = 0
        var previousDeltaPosition: UInt32 = 0
        var lastStrength: UInt32 = 0

        for _ in 0..<pulseCount {
            let deltaPosition: UInt32
            guard let positionFlag = decodeBit(model: 8) else { return nil }
            if positionFlag != 0 {
                guard let decodedDelta = decodeDWord(model: 0) else { return nil }
                if decodedDelta == 0 { break }
                previousDeltaPosition = decodedDelta
                deltaPosition = decodedDelta
            } else {
                deltaPosition = previousDeltaPosition
            }

            let (newPosition, positionOverflow) = lastPosition.addingReportingOverflow(deltaPosition)
            guard !positionOverflow,
                  newPosition < UInt32(Self.p64RotationTicks) else {
                return nil
            }
            lastPosition = newPosition

            guard let strengthFlag = decodeBit(model: 9) else { return nil }
            if strengthFlag != 0 {
                guard let strengthDelta = decodeDWord(model: 4) else { return nil }
                lastStrength = lastStrength &+ strengthDelta
            }

            pulses.append(P64Pulse(position: Int(lastPosition), strength: lastStrength))
        }

        return pulses
    }

    private static func p64Track(
        from pulses: [P64Pulse],
        halfTrack: Int,
        speedZone: Int
    ) -> (bytes: [UInt8], bitLength: Int, weakBitRanges: [DiskImage.Track.WeakBitRange]) {
        let zone = max(0, min(3, speedZone))
        let ticksPerBit = max(1, cyclesPerByte[zone] * 2)
        let bitCount = max(1, (Self.p64RotationTicks + ticksPerBit - 1) / ticksPerBit)
        let byteCount = max(trackLengths[zone], (bitCount + 7) / 8)
        var bytes = [UInt8](repeating: 0, count: byteCount)
        var weakRanges: [DiskImage.Track.WeakBitRange] = []

        for pulse in pulses where pulse.strength > 0 {
            let cell = ((pulse.position + ticksPerBit / 2) / ticksPerBit) % bitCount
            let byteIndex = cell / 8
            let bitIndex = 7 - (cell % 8)
            bytes[byteIndex] |= UInt8(1 << bitIndex)

            if pulse.strength < Self.p64StrongPulseStrength {
                let start = max(0, cell - 1)
                let end = min(bitCount - 1, cell + 1)
                weakRanges.append(DiskImage.Track.WeakBitRange(startBit: start, endBit: end))
            }
        }

        return (bytes, bitCount, mergedWeakBitRanges(weakRanges))
    }

    private struct P64RangeDecoder {
        let bytes: [UInt8]
        var offset = 0
        var code: UInt64 = 0
        var low: UInt64 = 0
        var high: UInt64 = 0xFFFF_FFFF

        mutating func start() -> Bool {
            guard bytes.count >= 4 else { return false }
            code = 0
            low = 0
            high = 0xFFFF_FFFF
            for _ in 0..<4 {
                code = ((code << 8) | UInt64(readByte())) & 0xFFFF_FFFF
            }
            return true
        }

        mutating func decodeBit(probability: inout UInt32, shift: UInt32) -> UInt32? {
            guard probability > 0 else { return nil }
            let middle = low + (((high - low) >> 12) * UInt64(probability))
            let bit: UInt32
            if code <= middle {
                probability += (0x0FFF - probability) >> shift
                high = middle
                bit = 1
            } else {
                probability -= probability >> shift
                low = middle + 1
                bit = 0
            }
            normalize()
            return bit
        }

        private mutating func normalize() {
            while ((low ^ high) & 0xFF00_0000) == 0 {
                low = (low << 8) & 0xFFFF_FFFF
                high = ((high << 8) | 0xFF) & 0xFFFF_FFFF
                code = ((code << 8) | UInt64(readByte())) & 0xFFFF_FFFF
            }
        }

        private mutating func readByte() -> UInt8 {
            guard offset < bytes.count else { return 0 }
            let byte = bytes[offset]
            offset += 1
            return byte
        }
    }

    private static func appendWeakBitExtension(from trackInfos: [DiskImage.Track?], to data: inout [UInt8]) {
        let records = trackInfos.enumerated().flatMap { halfTrack, track -> [(Int, DiskImage.Track.WeakBitRange)] in
            guard let track else { return [] }
            return track.weakBitRanges.map { (halfTrack, $0) }
        }
        guard !records.isEmpty, records.count <= Int(UInt16.max) else { return }

        data.append(contentsOf: weakBitExtensionMagic)
        appendLittleEndian16(UInt16(records.count), to: &data)
        for (halfTrack, range) in records {
            guard halfTrack <= UInt8.max,
                  range.startBit >= 0,
                  range.endBit >= range.startBit,
                  range.endBit <= Int(UInt32.max) else {
                continue
            }
            data.append(UInt8(halfTrack))
            appendLittleEndian32(UInt32(range.startBit), to: &data)
            appendLittleEndian32(UInt32(range.endBit), to: &data)
        }
    }

    private static func g64StandardPayloadEnd(
        from bytes: [UInt8],
        speedTableStart: Int,
        trackLengths: [Int]
    ) -> Int {
        var end = speedTableStart + trackLengths.count * 4
        for trackIndex in trackLengths.indices {
            let pos = speedTableStart + trackIndex * 4
            guard let value = littleEndian32(from: bytes, at: pos) else { continue }
            guard value >= 4 else { continue }
            let start = Int(value)
            let length = (trackLengths[trackIndex] + 3) / 4
            guard length > 0, start + length <= bytes.count else { continue }
            end = max(end, start + length)
        }
        return min(end, bytes.count)
    }

    private static func g64WeakBitExtension(
        from bytes: [UInt8],
        startingAt offset: Int,
        trackInfos: [DiskImage.Track?]
    ) -> [Int: [DiskImage.Track.WeakBitRange]]? {
        guard offset >= 0,
              offset + weakBitExtensionMagic.count + 2 <= bytes.count else {
            return nil
        }
        guard Array(bytes[offset..<(offset + weakBitExtensionMagic.count)]) == weakBitExtensionMagic else {
            return nil
        }

        var cursor = offset + weakBitExtensionMagic.count
        guard let recordCount = littleEndian16(from: bytes, at: cursor) else { return nil }
        cursor += 2
        guard cursor + Int(recordCount) * 9 <= bytes.count else { return nil }

        var rangesByHalfTrack: [Int: [DiskImage.Track.WeakBitRange]] = [:]
        for _ in 0..<recordCount {
            let halfTrack = Int(bytes[cursor])
            cursor += 1
            guard let startBit = littleEndian32(from: bytes, at: cursor),
                  let endBit = littleEndian32(from: bytes, at: cursor + 4) else {
                return nil
            }
            cursor += 8

            guard halfTrack >= 0,
                  halfTrack < trackInfos.count,
                  let track = trackInfos[halfTrack],
                  startBit <= endBit,
                  endBit < UInt32(track.bitLength) else {
                continue
            }

            rangesByHalfTrack[halfTrack, default: []].append(DiskImage.Track.WeakBitRange(
                startBit: Int(startBit),
                endBit: Int(endBit)
            ))
        }

        return rangesByHalfTrack.mapValues(Self.mergedWeakBitRanges)
    }

    /// Bounded Swift decoder for the NBZ compression stream used by NIBTOOLS.
    ///
    /// The format is Marcus Geelnard's small LZ77 marker-byte stream as used
    /// by NIBTOOLS `LZ_Uncompress`: byte 0 chooses the marker, marker+0 emits
    /// a literal marker, and marker+varLength+varOffset copies from history.
    private static func nibtoolsLZUncompressed(_ bytes: [UInt8], maxOutputBytes: Int) -> [UInt8]? {
        guard !bytes.isEmpty, maxOutputBytes > 0 else { return nil }
        let marker = bytes[0]
        var inputIndex = 1
        var output: [UInt8] = []
        output.reserveCapacity(min(maxOutputBytes, bytes.count * 2))

        while inputIndex < bytes.count {
            let symbol = bytes[inputIndex]
            inputIndex += 1

            if symbol != marker {
                guard output.count < maxOutputBytes else { return nil }
                output.append(symbol)
                continue
            }

            guard inputIndex < bytes.count else { return nil }
            if bytes[inputIndex] == 0 {
                inputIndex += 1
                guard output.count < maxOutputBytes else { return nil }
                output.append(marker)
                continue
            }

            guard let length = readNBZVariableSize(bytes, index: &inputIndex),
                  let offset = readNBZVariableSize(bytes, index: &inputIndex),
                  length > 0,
                  offset > 0,
                  offset <= output.count,
                  output.count + length <= maxOutputBytes else {
                return nil
            }

            for _ in 0..<length {
                output.append(output[output.count - offset])
            }
        }

        return output
    }

    private static func readNBZVariableSize(_ bytes: [UInt8], index: inout Int) -> Int? {
        var value = 0
        var byteCount = 0

        while true {
            guard index < bytes.count, byteCount < 5 else { return nil }
            let byte = bytes[index]
            index += 1
            byteCount += 1
            value = (value << 7) | Int(byte & 0x7F)
            if byte & 0x80 == 0 {
                return value
            }
        }
    }

    // MARK: - GCR encoding

    private static func g64SpeedInfo(
        from bytes: [UInt8],
        speedTableStart: Int,
        speedTableEnd: Int,
        trackIndex: Int,
        trackLength: Int,
        reservedRanges: [Range<Int>] = []
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

        let speedBlockLength = (trackLength + 3) / 4
        let speedBlockEnd = value + speedBlockLength
        guard value >= speedTableEnd,
              value < bytes.count,
              speedBlockEnd <= bytes.count,
              !reservedRanges.contains(where: { Self.rangesOverlap(value..<speedBlockEnd, $0) }) else {
            return nil
        }

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

    private static func rangesOverlap(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
        lhs.lowerBound < rhs.upperBound && rhs.lowerBound < lhs.upperBound
    }

    private func d64SectorErrorCodes(from bytes: [UInt8], geometry: DiskDrive.D64Geometry) -> [UInt8]? {
        guard let errorInfoOffset = geometry.errorInfoOffset,
              errorInfoOffset < bytes.count else {
            return nil
        }

        let expectedCount = geometry.sectorsPerTrack[1...geometry.trackCount].reduce(0, +)
        guard bytes.count >= errorInfoOffset + expectedCount else { return nil }
        return Array(bytes[errorInfoOffset..<(errorInfoOffset + expectedCount)])
    }

    private func sectorErrorCodesForTrack(
        _ track: Int,
        geometry: DiskDrive.D64Geometry,
        allCodes: [UInt8]?
    ) -> [UInt8]? {
        guard let allCodes,
              track >= 1,
              track <= geometry.trackCount else {
            return nil
        }

        var start = 0
        if track > 1 {
            for previousTrack in 1..<track {
                start += geometry.sectorsPerTrack[previousTrack]
            }
        }
        let count = geometry.sectorsPerTrack[track]
        guard start + count <= allCodes.count else { return nil }
        return Array(allCodes[start..<(start + count)])
    }

    /// Extract disk ID bytes from D64 BAM (track 18, sector 0, offset $A2-$A3).
    private func extractDiskID(from d64: [UInt8]) -> (UInt8, UInt8) {
        let bamOffset = DiskDrive.trackOffset[18]
        guard bamOffset + 0xA4 <= d64.count else { return (0x41, 0x42) }
        return (d64[bamOffset + 0xA2], d64[bamOffset + 0xA3])
    }

    /// GCR-encode an entire track.
    func encodeTrack(
        trackNum: Int,
        sectors: [[UInt8]],
        diskID: (UInt8, UInt8),
        sectorErrorCodes: [UInt8]? = nil
    ) -> [UInt8] {
        let zone = GCRDisk.speedZone(for: trackNum)
        let targetLen = GCRDisk.trackLengths[zone]

        var gcr = [UInt8]()
        gcr.reserveCapacity(targetLen)

        for (sectorNum, sectorData) in sectors.enumerated() {
            let errorEffect: D64SectorErrorEffect
            if let sectorErrorCodes, sectorNum < sectorErrorCodes.count {
                errorEffect = D64SectorErrorEffect(code: sectorErrorCodes[sectorNum])
            } else {
                errorEffect = .ok
            }

            // Sync mark (5 bytes of $FF = 40 one-bits)
            let headerSyncByte: UInt8 = errorEffect == .noSync ? 0x55 : 0xFF
            gcr.append(contentsOf: [UInt8](repeating: headerSyncByte, count: 5))

            // Header block: $08, checksum, sector, track, id2, id1, $0F, $0F
            var checksum = UInt8(sectorNum) ^ UInt8(trackNum) ^ diskID.1 ^ diskID.0
            if errorEffect == .headerChecksum {
                checksum ^= 0xFF
            }
            let headerMarker: UInt8 = errorEffect == .headerNotFound ? 0x00 : 0x08
            let headerID1 = errorEffect == .diskIDMismatch ? diskID.0 ^ 0xFF : diskID.0
            let headerID2 = errorEffect == .diskIDMismatch ? diskID.1 ^ 0xFF : diskID.1
            if errorEffect == .diskIDMismatch {
                checksum = UInt8(sectorNum) ^ UInt8(trackNum) ^ headerID2 ^ headerID1
            }
            let header: [UInt8] = [
                headerMarker, checksum, UInt8(sectorNum), UInt8(trackNum),
                headerID2, headerID1, 0x0F, 0x0F
            ]
            gcr.append(contentsOf: encodeGCRBytes(header))

            // Header gap (9 bytes of $55)
            gcr.append(contentsOf: [UInt8](repeating: 0x55, count: 9))

            // Data sync mark
            gcr.append(contentsOf: [UInt8](repeating: 0xFF, count: 5))

            // Data block: $07, 256 data bytes, checksum, $00, $00
            var dataBlock = [UInt8]()
            dataBlock.reserveCapacity(260)
            dataBlock.append(errorEffect == .dataBlockNotPresent ? 0x00 : 0x07)
            dataBlock.append(contentsOf: sectorData)
            var dataChecksum: UInt8 = 0
            for b in sectorData { dataChecksum ^= b }
            if errorEffect == .dataChecksum {
                dataChecksum ^= 0xFF
            }
            if errorEffect == .longDataBlock {
                dataBlock.append(dataChecksum ^ 0xFF)
            }
            dataBlock.append(dataChecksum)
            dataBlock.append(0x00)
            dataBlock.append(0x00)
            var encodedDataBlock = encodeGCRBytes(dataBlock)
            if errorEffect == .byteDecode && encodedDataBlock.count > 6 {
                encodedDataBlock[6] = 0x00
            }
            gcr.append(contentsOf: encodedDataBlock)

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
