import Foundation

/// Parses G64 (GCR-encoded 1541 disk) images and decodes them to raw sector data.
///
/// G64 files store the actual GCR bitstream for each track, preserving
/// sync marks, gaps, headers, and timing information. This parser decodes
/// the GCR data back to standard 256-byte sectors so the existing
/// DiskDrive infrastructure can serve files via Kernal traps.
private func g64log(_ msg: String) {
    let line = msg + "\n"
    let path = "/tmp/c64_debug.log"
    if let data = line.data(using: .utf8) {
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
    }
}

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

        // Build D64-compatible image: 35 tracks, standard sector counts
        let d64Size = 174848
        var d64 = [UInt8](repeating: 0, count: d64Size)
        var totalDecoded = 0

        // Process whole tracks (indices 0, 2, 4, ... = tracks 1, 2, 3, ...)
        for trackNum in 1...35 {
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
            let expectedSectors = DiskDrive.sectorsPerTrack[trackNum]
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
                let d64Offset = DiskDrive.trackOffset[trackNum] + sectorNum * 256
                guard d64Offset + 256 <= d64Size else { continue }
                for i in 0..<256 {
                    d64[d64Offset + i] = sectorData[i]
                }
            }
        }

        g64log("G64: decoded \(totalDecoded)/683 total sectors")

        // Sanity check: did we get any sectors at all?
        if totalDecoded == 0 {
            g64log("G64: WARNING — no sectors decoded, file may use non-standard format")
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
            let headerBytes = decodeGCRFromBits(bits, from: afterSync, count: 8)

            if track == 18 && syncCount <= 5 {
                let dec = headerBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                g64log("G64: T\(track) sync#\(syncCount) @bit \(afterSync) → [\(dec)]")
            }

            if headerBytes.count >= 6 && headerBytes[0] == 0x08 {
                let sectorNum = Int(headerBytes[2])
                let trackNum = Int(headerBytes[3])

                if trackNum == track && sectorNum < expectedSectors &&
                   !foundSectors.contains(sectorNum) {

                    // Find next sync for data block
                    let dataSyncBit = findSyncBit(in: bits, from: afterSync + 80)
                    // Data block: 260 bytes = 2600 bits of GCR
                    if dataSyncBit >= 0 && dataSyncBit + 2600 <= bits.count {
                        let dataBytes = decodeGCRFromBits(bits, from: dataSyncBit, count: 260)

                        if dataBytes.count >= 258 && dataBytes[0] == 0x07 {
                            let sectorData = Array(dataBytes[1...256])
                            sectors.append((sectorNum, sectorData))
                            foundSectors.insert(sectorNum)
                        } else {
                            dataFails += 1
                            if track == 18 && dataFails <= 3 {
                                let marker = dataBytes.isEmpty ? "empty" : String(format: "%02X", dataBytes[0])
                                g64log("G64: T\(track) S\(sectorNum) data fail: marker=\(marker) count=\(dataBytes.count)")
                            }
                        }
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
        var result = [UInt8]()
        result.reserveCapacity(expectedBytes)
        var pos = bitPos

        while result.count < expectedBytes && pos + 10 <= bits.count {
            // Read high nybble (5 bits)
            var hi: UInt8 = 0
            for i in 0..<5 { hi = (hi << 1) | bits[pos + i] }
            // Read low nybble (5 bits)
            var lo: UInt8 = 0
            for i in 0..<5 { lo = (lo << 1) | bits[pos + 5 + i] }

            result.append((gcrDecode[Int(hi)] << 4) | gcrDecode[Int(lo)])
            pos += 10
        }

        return result
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
