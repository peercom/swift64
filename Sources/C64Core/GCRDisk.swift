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
        let maxTrackSize = Int(bytes[10]) | (Int(bytes[11]) << 8)

        var newTracks: [[UInt8]?] = Array(repeating: nil, count: GCRDisk.maxHalfTracks)
        var newTrackInfos: [DiskImage.Track?] = Array(repeating: nil, count: GCRDisk.maxHalfTracks)

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
            let sectorHeaderStats = G64Parser.sectorHeaderStats(from: trackBytes, track: i / 2 + 1)
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
                isNativeLowLevel: true,
                duplicateSectorHeaderCount: sectorHeaderStats.duplicateSectorHeaderCount
            )
            newTracks[i] = info.bytes
            newTrackInfos[i] = info
        }

        guard newTracks.contains(where: { $0 != nil }) else { return false }

        tracks = newTracks
        trackInfos = newTrackInfos
        image = DiskImage(format: .g64, tracks: newTrackInfos, maxTrackSize: maxTrackSize)
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
            rebuildImage: true
        )
        hasUnsavedLowLevelWrites = true
        return true
    }

    @discardableResult
    public func writeByteAtBitPosition(_ value: UInt8, halfTrack: Int, bitPosition: Int) -> Bool {
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
            rebuildImage: true
        )
        hasUnsavedLowLevelWrites = true
        return true
    }

    @discardableResult
    public func writeBitAtBitPosition(_ bit: Bool, halfTrack: Int, bitPosition: Int) -> Bool {
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
            rebuildImage: false
        )
        hasUnsavedLowLevelWrites = true
        return true
    }

    /// Ensure a native low-level track stream exists for write-head activity.
    ///
    /// D64-backed synthetic tracks are pre-populated for full tracks. Creating
    /// new low-level tracks is reserved for native G64 media because D64 cannot
    /// represent arbitrary halftracks or raw bitstreams.
    @discardableResult
    public func ensureWritableTrack(
        halfTrack: Int,
        speedZone: Int,
        fillByte: UInt8 = 0x55
    ) -> Bool {
        guard image?.format == .g64,
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
    public func decodedD64Image(patching baseImage: Data) -> D64DecodeResult? {
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
                if !output[offset..<(offset + 256)].elementsEqual(sectorData) {
                    output.replaceSubrange(offset..<(offset + 256), with: sectorData)
                    clearSectorErrorCode(track: trackNum, sector: sectorNum, in: &output, geometry: geometry)
                    changedSectorCount += 1
                }
            }
        }

        guard decodedSectorCount > 0 else { return nil }
        return D64DecodeResult(
            image: Data(output),
            decodedSectorCount: decodedSectorCount,
            changedSectorCount: changedSectorCount,
            incompleteTracks: incompleteTracks
        )
    }

    public var exportedG64Image: Data? {
        guard image?.format == .g64 else { return nil }
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

        return Data(data)
    }

    public func markLowLevelWritesSaved() {
        hasUnsavedLowLevelWrites = false
    }

    private func updateTrackAfterWrite(
        halfTrack: Int,
        bytes: [UInt8],
        writtenBitRanges: [ClosedRange<Int>],
        rebuildImage: Bool
    ) {
        let existing = trackInfos[halfTrack]
        let weakBitRanges = writtenBitRanges.reduce(existing?.weakBitRanges ?? []) { ranges, writtenRange in
            ranges.flatMap { Self.removingBits(writtenRange, from: $0) }
        }
        let updated = DiskImage.Track(
            halfTrack: existing?.halfTrack ?? halfTrack,
            bytes: bytes,
            bitLength: existing?.bitLength ?? bytes.count * 8,
            speedZone: existing?.speedZone ?? Self.speedZone(for: halfTrack / 2 + 1),
            speedZoneMap: existing?.speedZoneMap,
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

    private func clearSectorErrorCode(track: Int, sector: Int, in image: inout [UInt8], geometry: DiskDrive.D64Geometry) {
        guard let errorInfoOffset = geometry.errorInfoOffset,
              let ordinal = sectorOrdinal(track: track, sector: sector, geometry: geometry) else {
            return
        }

        let errorOffset = errorInfoOffset + ordinal
        if errorOffset < image.count {
            image[errorOffset] = 0x01
        }
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
