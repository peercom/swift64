import Foundation

/// Parses G64 (GCR-encoded 1541 disk) images and decodes them to raw sector data.
///
/// G64 files store the actual GCR bitstream for each track, preserving
/// sync marks, gaps, headers, and timing information. This parser decodes
/// the GCR data back to standard 256-byte sectors so the existing
/// DiskDrive infrastructure can serve files via Kernal traps.
public enum G64Parser {

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
    /// compatible with D64 format (174848 bytes for 35 tracks).
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
            print("G64: unsupported version \(version)")
            return nil
        }
        guard numTracks > 0 && numTracks <= 84 else {
            print("G64: invalid track count \(numTracks)")
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

        // Build D64-compatible image: 35 tracks, standard sector counts
        let d64Size = 174848
        var d64 = [UInt8](repeating: 0, count: d64Size)

        // Process whole tracks (indices 0, 2, 4, ... = tracks 1, 2, 3, ...)
        for trackNum in 1...35 {
            let halfTrackIndex = (trackNum - 1) * 2  // G64 stores half-tracks
            guard halfTrackIndex < numTracks else { continue }

            let offset = trackOffsets[halfTrackIndex]
            guard offset > 0 && offset + 2 <= bytes.count else { continue }

            // Track data: 2-byte little-endian length + GCR data
            let trackLen = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            guard trackLen > 0 && offset + 2 + trackLen <= bytes.count else { continue }

            let trackData = Array(bytes[(offset + 2)..<(offset + 2 + trackLen)])

            // Decode all sectors from this track's GCR data
            let expectedSectors = DiskDrive.sectorsPerTrack[trackNum]
            let sectors = decodeSectors(from: trackData, track: trackNum,
                                        expectedSectors: expectedSectors)

            // Copy decoded sectors into the D64 image
            for (sectorNum, sectorData) in sectors {
                guard sectorNum >= 0 && sectorNum < expectedSectors else { continue }
                let d64Offset = DiskDrive.trackOffset[trackNum] + sectorNum * 256
                guard d64Offset + 256 <= d64Size else { continue }
                for i in 0..<256 {
                    d64[d64Offset + i] = sectorData[i]
                }
            }
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

        // Scan for sync marks (5+ consecutive $FF bytes) followed by sector headers
        var pos = 0
        var foundSectors = Set<Int>()

        // We may need to wrap around (track data is circular)
        let extendedData = gcrData + gcrData  // Duplicate to handle wrap-around
        let maxPos = len  // Only scan through original data length

        while pos < maxPos && foundSectors.count < expectedSectors {
            // Find sync mark: 5+ bytes of $FF
            let syncPos = findSync(in: extendedData, from: pos)
            guard syncPos >= 0 && syncPos < maxPos + len - 20 else { break }

            let afterSync = syncPos

            // Decode 10 GCR bytes → 8 data bytes (sector header)
            guard afterSync + 10 <= extendedData.count else { break }
            let headerGCR = Array(extendedData[afterSync..<(afterSync + 10)])
            let headerBytes = decodeGCRBlock(headerGCR, count: 8)

            if headerBytes.count >= 6 && headerBytes[0] == 0x08 {
                // This is a sector header
                let sectorNum = Int(headerBytes[2])
                let trackNum = Int(headerBytes[3])

                if trackNum == track && sectorNum < expectedSectors &&
                   !foundSectors.contains(sectorNum) {

                    // Now find the data block: skip gap, find next sync, then data
                    let dataSync = findSync(in: extendedData, from: afterSync + 10)
                    if dataSync >= 0 && dataSync + 325 <= extendedData.count {
                        let dataGCR = Array(extendedData[dataSync..<(dataSync + 325)])
                        let dataBytes = decodeGCRBlock(dataGCR, count: 260)

                        if dataBytes.count >= 258 && dataBytes[0] == 0x07 {
                            let sectorData = Array(dataBytes[1...256])
                            sectors.append((sectorNum, sectorData))
                            foundSectors.insert(sectorNum)
                        }
                    }
                }

                // Advance past this header
                pos = afterSync + 10
                if pos >= maxPos { break }
            } else {
                // Not a header, advance past sync
                pos = afterSync + 1
                if pos >= maxPos { break }
            }
        }

        return sectors
    }

    /// Find the position after a sync mark (5+ consecutive $FF bytes).
    /// Returns the index of the first non-$FF byte after the sync, or -1.
    static func findSync(in data: [UInt8], from start: Int) -> Int {
        var pos = start
        let len = data.count

        // Find start of sync ($FF bytes)
        while pos < len && data[pos] != 0xFF {
            pos += 1
        }

        // Count consecutive $FF bytes (need at least 5)
        var syncLen = 0
        while pos < len && data[pos] == 0xFF {
            syncLen += 1
            pos += 1
        }

        if syncLen >= 5 && pos < len {
            return pos
        }
        return -1
    }

    /// Decode a GCR byte stream into data bytes.
    /// Every 5 GCR bytes decode to 4 data bytes (8 nybbles from 40 bits).
    static func decodeGCRBlock(_ gcr: [UInt8], count expectedBytes: Int) -> [UInt8] {
        var result = [UInt8]()
        result.reserveCapacity(expectedBytes)

        // Process in groups of 5 GCR bytes → 4 data bytes
        var gcrPos = 0
        while result.count < expectedBytes && gcrPos + 5 <= gcr.count {
            let b0 = UInt64(gcr[gcrPos])
            let b1 = UInt64(gcr[gcrPos + 1])
            let b2 = UInt64(gcr[gcrPos + 2])
            let b3 = UInt64(gcr[gcrPos + 3])
            let b4 = UInt64(gcr[gcrPos + 4])

            // Pack 5 bytes into 40 bits
            let bits: UInt64 = (b0 << 32) | (b1 << 24) | (b2 << 16) | (b3 << 8) | b4

            // Extract 8 GCR nybbles (5 bits each)
            let g0 = gcrDecode[Int((bits >> 35) & 0x1F)]
            let g1 = gcrDecode[Int((bits >> 30) & 0x1F)]
            let g2 = gcrDecode[Int((bits >> 25) & 0x1F)]
            let g3 = gcrDecode[Int((bits >> 20) & 0x1F)]
            let g4 = gcrDecode[Int((bits >> 15) & 0x1F)]
            let g5 = gcrDecode[Int((bits >> 10) & 0x1F)]
            let g6 = gcrDecode[Int((bits >> 5) & 0x1F)]
            let g7 = gcrDecode[Int(bits & 0x1F)]

            // Combine nybble pairs into bytes
            if result.count < expectedBytes { result.append((g0 << 4) | g1) }
            if result.count < expectedBytes { result.append((g2 << 4) | g3) }
            if result.count < expectedBytes { result.append((g4 << 4) | g5) }
            if result.count < expectedBytes { result.append((g6 << 4) | g7) }

            gcrPos += 5
        }

        return result
    }
}
