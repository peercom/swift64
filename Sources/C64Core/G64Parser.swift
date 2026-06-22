import Foundation

/// Parses G64 (GCR-encoded 1541 disk) images and decodes them to raw sector data.
///
/// G64 files store the actual GCR bitstream for each track, preserving
/// sync marks, gaps, headers, and timing information. This parser decodes
/// the GCR data back to standard 256-byte sectors so the existing
/// DiskDrive infrastructure can serve files via Kernal traps.
private func g64log(_ msg: String) {
    C64Trace.log(.gcr, msg)
}

public enum G64Parser {
    struct SectorHeaderStats: Equatable {
        let validHeaderCount: Int
        let duplicateSectorHeaderCount: Int
    }

    // MARK: - G64 header constants

    static let signature = "GCR-1541"
    static let headerSize = 12  // 8 signature + 1 version + 1 tracks + 2 maxTrackSize

    // MARK: - GCR decode table (5-bit GCR → 4-bit nybble)

    /// Maps a 5-bit GCR value (0-31) to a 4-bit nybble. 0xFF = invalid.
    static let gcrDecode: [UInt8] = {
        var table = [UInt8](repeating: 0xFF, count: 32)
        // 1541 GCR encoding: nybble → 5-bit GCR pattern
        let encode: [(nybble: UInt8, gcr: UInt8)] = [
            (0x0, 0x0A), (0x1, 0x0B), (0x2, 0x12), (0x3, 0x13),
            (0x4, 0x0E), (0x5, 0x0F), (0x6, 0x16), (0x7, 0x17),
            (0x8, 0x09), (0x9, 0x19), (0xA, 0x1A), (0xB, 0x1B),
            (0xC, 0x0D), (0xD, 0x1D), (0xE, 0x1E), (0xF, 0x15),
        ]
        for pair in encode {
            table[Int(pair.gcr)] = pair.nybble
        }
        return table
    }()

    // MARK: - Public API

    /// Parse a G64 file and return decoded sector data as a flat byte array
    /// compatible with D64 format.
    /// Returns nil if the file is not a valid G64.
    public static func decode(_ data: Data) -> [UInt8]? {
        let bytes = [UInt8](data)
        guard bytes.count >= headerSize else { return nil }

        // Check signature
        let sig = String(bytes: Array(bytes[0..<8]), encoding: .ascii)
        guard sig == signature else { return nil }

        let version = bytes[8]
        let numTracks = Int(bytes[9])
        // bytes[10..11] = max track size (little-endian), not needed for decoding

        guard version == 0 else {
            g64log("G64: unsupported version \(version)")
            return nil
        }
        guard numTracks > 0 && numTracks <= 84 else {
            g64log("G64: invalid track count \(numTracks)")
            return nil
        }

        // Parse track offset table (starts at byte 12)
        let offsetTableStart = headerSize
        let speedTableStart = offsetTableStart + numTracks * 4

        guard bytes.count >= speedTableStart + numTracks * 4 else { return nil }

        var trackOffsets = [Int](repeating: 0, count: numTracks)
        for i in 0..<numTracks {
            let pos = offsetTableStart + i * 4
            trackOffsets[i] = Int(bytes[pos])
                | (Int(bytes[pos + 1]) << 8)
                | (Int(bytes[pos + 2]) << 16)
                | (Int(bytes[pos + 3]) << 24)
        }

        let maxWholeTrack = min(42, (numTracks + 1) / 2)
        var highestWholeTrackWithData = 0
        if maxWholeTrack > 0 {
            for trackNum in 1...maxWholeTrack {
                let halfTrackIndex = (trackNum - 1) * 2
                if halfTrackIndex < numTracks && trackOffsets[halfTrackIndex] > 0 {
                    highestWholeTrackWithData = trackNum
                }
            }
        }

        let decodedTrackCount: Int
        switch max(35, highestWholeTrackWithData) {
        case ...35:
            decodedTrackCount = 35
        case 36...40:
            decodedTrackCount = 40
        case 41:
            decodedTrackCount = 41
        default:
            decodedTrackCount = 42
        }

        let d64Size: Int
        switch decodedTrackCount {
        case 35: d64Size = 174848
        case 40: d64Size = 196608
        case 41: d64Size = 200704
        default: d64Size = 205312
        }
        guard let geometry = DiskDrive.d64Geometry(forByteCount: d64Size) else { return nil }

        // Build D64-compatible image sized to the whole tracks present in the G64.
        var d64 = [UInt8](repeating: 0, count: d64Size)
        var totalDecoded = 0

        // Process whole tracks (indices 0, 2, 4, ... = tracks 1, 2, 3, ...)
        for trackNum in 1...decodedTrackCount {
            let halfTrackIndex = (trackNum - 1) * 2  // G64 stores half-tracks
            guard halfTrackIndex < numTracks else { continue }

            let offset = trackOffsets[halfTrackIndex]
            guard offset > 0 && offset + 2 <= bytes.count else {
                g64log("G64: track \(trackNum) no data (offset=\(offset))")
                continue
            }

            // Track data: 2-byte little-endian length + GCR data
            let trackLen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            guard trackLen > 0 && offset + 2 + trackLen <= bytes.count else {
                g64log("G64: track \(trackNum) invalid length \(trackLen)")
                continue
            }

            let trackData = Array(bytes[(offset + 2)..<(offset + 2 + trackLen)])

            // Dump first bytes and FF count for track 18
            if trackNum == 18 {
                let first40 = trackData.prefix(40).map { String(format: "%02X", $0) }.joined(separator: " ")
                let ffCount = trackData.filter { $0 == 0xFF }.count
                g64log("G64: T18 raw first 40: \(first40)")
                g64log("G64: T18 total $FF bytes: \(ffCount) / \(trackLen)")

                var maxRun = 0; var curRun = 0
                for b in trackData {
                    if b == 0xFF { curRun += 1; maxRun = max(maxRun, curRun) }
                    else { curRun = 0 }
                }
                g64log("G64: T18 longest FF run: \(maxRun)")
            }

            // After decoding, dump T18/S0 (BAM) for verification
            if trackNum == 18 {
                // Will be filled after sector decode below
            }

            // Decode all sectors from this track's GCR data
            let expectedSectors = geometry.sectorsPerTrack[trackNum]
            let sectors = decodeSectors(from: trackData, track: trackNum,
                                        expectedSectors: expectedSectors)

            if sectors.count != expectedSectors {
                g64log("G64: track \(trackNum): decoded \(sectors.count)/\(expectedSectors) sectors from \(trackLen) GCR bytes")
            }

            // Dump BAM sector (T18/S0) for debugging
            if trackNum == 18 {
                for sn in [0, 1, 9] {
                    if let s = sectors.first(where: { $0.0 == sn }) {
                        let d = s.1
                        let first16 = d.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
                        g64log("G64: T18/S\(sn) first 16: \(first16)")
                    } else {
                        g64log("G64: T18/S\(sn) NOT FOUND")
                    }
                }
                // Disk name at offset $90 in S0
                if let s0 = sectors.first(where: { $0.0 == 0 }) {
                    let nameBytes = Array(s0.1[0x90..<0xA0])
                    let nameHex = nameBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                    g64log("G64: T18/S0 diskname @$90: \(nameHex)")
                }
            }

            totalDecoded += sectors.count

            // Copy decoded sectors into the D64 image
            for (sectorNum, sectorData) in sectors {
                guard sectorNum >= 0 && sectorNum < expectedSectors else { continue }
                let d64Offset = geometry.trackOffsets[trackNum] + sectorNum * 256
                guard d64Offset + 256 <= d64Size else { continue }
                for i in 0..<256 {
                    d64[d64Offset + i] = sectorData[i]
                }
            }
        }

        let expectedTotalSectors = geometry.sectorsPerTrack[1...geometry.trackCount].reduce(0, +)
        g64log("G64: decoded \(totalDecoded)/\(expectedTotalSectors) total sectors")

        // Sanity check: did we get any sectors at all?
        if totalDecoded == 0 {
            g64log("G64: WARNING — no sectors decoded, file may use non-standard format")
            return nil
        }

        return d64
    }

    // MARK: - GCR sector decoding

    /// Decode sectors from a GCR bitstream for a given track.
    /// Returns array of (sectorNumber, 256-byte data) pairs.
    static func decodeSectors(from gcrData: [UInt8], track: Int,
                               expectedSectors: Int) -> [(Int, [UInt8])] {
        var sectors: [(Int, [UInt8])] = []
        let len = gcrData.count
        guard len > 20 else { return [] }

        // Convert to bits for bit-level sync detection.
        // Duplicate the data to handle wrap-around (track is circular).
        let bits = toBits(gcrData + gcrData)
        let maxBit = len * 8  // Only scan through original data length

        var bitPos = 0
        var foundSectors = Set<Int>()
        var syncCount = 0
        var headerFails = 0
        var dataFails = 0

        while bitPos < maxBit && foundSectors.count < expectedSectors {
            // Find next sync mark (10+ consecutive 1-bits)
            let afterSync = findSyncBit(in: bits, from: bitPos)
            guard afterSync >= 0 && afterSync < maxBit + len * 8 - 200 else { break }

            syncCount += 1

            // Decode sector header: 8 bytes = 80 bits of GCR after sync
            guard afterSync + 80 <= bits.count else { break }
            let headerDecode = decodeGCRFromBitsWithValidity(bits, from: afterSync, count: 8)
            let headerBytes = headerDecode.bytes

            if track == 18 && syncCount <= 5 {
                let dec = headerBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                g64log("G64: T\(track) sync#\(syncCount) @bit \(afterSync) → [\(dec)]")
            }

            if headerDecode.isValid && headerBytes.count >= 6 && headerBytes[0] == 0x08 && headerChecksumIsValid(headerBytes) {
                let sectorNum = Int(headerBytes[2])
                let trackNum = Int(headerBytes[3])

                if trackNum == track && sectorNum < expectedSectors &&
                   !foundSectors.contains(sectorNum) {

                    if let dataBytes = decodeDataBlockAfterHeader(
                        bits: bits,
                        startBit: afterSync + 80,
                        maxBit: min(bits.count, afterSync + 80 + 7000),
                        dataFails: &dataFails,
                        track: track,
                        sectorNum: sectorNum
                    ) {
                        let sectorData = Array(dataBytes[1...256])
                        sectors.append((sectorNum, sectorData))
                        foundSectors.insert(sectorNum)
                    }
                }

                bitPos = afterSync + 80
                if bitPos >= maxBit { break }
            } else {
                headerFails += 1
                // Skip past this sync + a few bits
                bitPos = afterSync + 10
                if bitPos >= maxBit { break }
            }
        }

        if sectors.count < expectedSectors {
            g64log("G64: T\(track) syncs=\(syncCount) headerFails=\(headerFails) dataFails=\(dataFails) decoded=\(sectors.count)/\(expectedSectors)")
        }

        return sectors
    }

    static func sectorHeaderStats(from gcrData: [UInt8], track: Int) -> SectorHeaderStats {
        let len = gcrData.count
        guard len > 20 else {
            return SectorHeaderStats(validHeaderCount: 0, duplicateSectorHeaderCount: 0)
        }

        let bits = toBits(gcrData + gcrData)
        let maxBit = len * 8
        var bitPos = 0
        var sectorHeaderCounts: [Int: Int] = [:]

        while bitPos < maxBit {
            let afterSync = findSyncBit(in: bits, from: bitPos)
            guard afterSync >= 0 && afterSync < maxBit else { break }

            let headerDecode = decodeGCRFromBitsWithValidity(bits, from: afterSync, count: 8)
            let headerBytes = headerDecode.bytes
            if headerDecode.isValid &&
                headerBytes.count >= 6 &&
                headerBytes[0] == 0x08 &&
                headerChecksumIsValid(headerBytes) &&
                Int(headerBytes[3]) == track {
                let sectorNum = Int(headerBytes[2])
                sectorHeaderCounts[sectorNum, default: 0] += 1
            }

            bitPos = afterSync + 80
        }

        let duplicateCount = sectorHeaderCounts.values.reduce(0) { partial, count in
            partial + max(0, count - 1)
        }
        return SectorHeaderStats(
            validHeaderCount: sectorHeaderCounts.values.reduce(0, +),
            duplicateSectorHeaderCount: duplicateCount
        )
    }

    private static func decodeDataBlockAfterHeader(
        bits: [UInt8],
        startBit: Int,
        maxBit: Int,
        dataFails: inout Int,
        track: Int,
        sectorNum: Int
    ) -> [UInt8]? {
        var searchBit = startBit
        var attempts = 0
        let boundedMaxBit = min(maxBit, bits.count)

        while attempts < 4 && searchBit < boundedMaxBit {
            let dataSyncBit = findSyncBit(in: bits, from: searchBit)
            guard dataSyncBit >= 0,
                  dataSyncBit < boundedMaxBit,
                  dataSyncBit + 2600 <= bits.count else {
                return nil
            }

            let headerCandidate = decodeGCRFromBitsWithValidity(bits, from: dataSyncBit, count: 8)
            if headerCandidate.isValid && headerCandidate.bytes.count >= 8 &&
                headerCandidate.bytes[0] == 0x08 && headerChecksumIsValid(headerCandidate.bytes) {
                return nil
            }

            let dataDecode = decodeGCRFromBitsWithValidity(bits, from: dataSyncBit, count: 260)
            let dataBytes = dataDecode.bytes

            if dataDecode.isValid && dataBytes.count >= 258 &&
                dataBytes[0] == 0x07 && dataChecksumIsValid(dataBytes) {
                return dataBytes
            }

            dataFails += 1
            if track == 18 && dataFails <= 3 {
                let marker = dataBytes.isEmpty ? "empty" : String(format: "%02X", dataBytes[0])
                g64log("G64: T\(track) S\(sectorNum) data fail: marker=\(marker) count=\(dataBytes.count)")
            }

            searchBit = dataSyncBit + 10
            attempts += 1
        }

        return nil
    }

    private static func headerChecksumIsValid(_ header: [UInt8]) -> Bool {
        guard header.count >= 6 else { return false }
        return header[1] == (header[2] ^ header[3] ^ header[4] ^ header[5])
    }

    private static func dataChecksumIsValid(_ dataBlock: [UInt8]) -> Bool {
        guard dataBlock.count >= 258 else { return false }
        var checksum: UInt8 = 0
        for byte in dataBlock[1...256] {
            checksum ^= byte
        }
        return checksum == dataBlock[257]
    }

    // MARK: - Bit-level sync detection and GCR decoding

    /// Find the bit position after a sync mark (10+ consecutive one-bits).
    /// The 1541 hardware detects sync by looking for 10+ consecutive 1-bits
    /// in the GCR bitstream — NOT aligned to byte boundaries.
    /// After sync, data is byte-aligned starting from the first 0-bit.
    /// Returns the bit index of the first 0-bit after sync, or -1.
    static func findSyncBit(in bits: [UInt8], from start: Int) -> Int {
        var pos = start
        let len = bits.count

        while pos < len {
            // Skip zeros
            while pos < len && bits[pos] == 0 { pos += 1 }

            // Count consecutive 1-bits
            var oneCount = 0
            while pos < len && bits[pos] == 1 {
                oneCount += 1
                pos += 1
            }

            // 1541 needs 10+ one-bits for sync
            if oneCount >= 10 && pos < len {
                return pos  // First 0-bit after sync — data starts here
            }
            // If we hit end of data or not enough ones, keep scanning
            if pos >= len { break }
        }
        return -1
    }

    /// Decode GCR data from a bit array starting at a given bit position.
    /// Every 10 bits (two 5-bit GCR nybbles) decode to 1 byte.
    static func decodeGCRFromBits(_ bits: [UInt8], from bitPos: Int, count expectedBytes: Int) -> [UInt8] {
        decodeGCRFromBitsWithValidity(bits, from: bitPos, count: expectedBytes).bytes
    }

    private static func decodeGCRFromBitsWithValidity(
        _ bits: [UInt8],
        from bitPos: Int,
        count expectedBytes: Int
    ) -> (bytes: [UInt8], isValid: Bool) {
        var result = [UInt8]()
        result.reserveCapacity(expectedBytes)
        var pos = bitPos
        var isValid = true

        while result.count < expectedBytes && pos + 10 <= bits.count {
            // Read high nybble (5 bits)
            var hi: UInt8 = 0
            for i in 0..<5 { hi = (hi << 1) | bits[pos + i] }
            // Read low nybble (5 bits)
            var lo: UInt8 = 0
            for i in 0..<5 { lo = (lo << 1) | bits[pos + 5 + i] }

            let decodedHi = gcrDecode[Int(hi)]
            let decodedLo = gcrDecode[Int(lo)]
            if decodedHi == 0xFF || decodedLo == 0xFF {
                isValid = false
                result.append(0xFF)
            } else {
                result.append((decodedHi << 4) | decodedLo)
            }
            pos += 10
        }

        return (result, isValid && result.count == expectedBytes)
    }

    /// Legacy byte-aligned GCR decode (used by tests that build synthetic GCR data).
    static func decodeGCRBlock(_ gcr: [UInt8], count expectedBytes: Int) -> [UInt8] {
        let bits = toBits(gcr)
        return decodeGCRFromBits(bits, from: 0, count: expectedBytes)
    }

    /// Convert byte array to bit array.
    private static func toBits(_ data: [UInt8]) -> [UInt8] {
        var bits = [UInt8]()
        bits.reserveCapacity(data.count * 8)
        for byte in data {
            for shift in stride(from: 7, through: 0, by: -1) {
                bits.append((byte >> shift) & 1)
            }
        }
        return bits
    }
}
