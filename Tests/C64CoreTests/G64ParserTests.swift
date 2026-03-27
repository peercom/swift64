import XCTest
@testable import C64Core

final class G64ParserTests: XCTestCase {

    // MARK: - GCR encoding helpers for building test data

    /// GCR encode table: 4-bit nybble → 5-bit GCR value (1541 standard)
    static let gcrEncode: [UInt8] = [
        0x0A, 0x0B, 0x12, 0x13, 0x0E, 0x0F, 0x16, 0x17,
        0x09, 0x19, 0x1A, 0x1B, 0x0D, 0x1D, 0x1E, 0x15,
    ]

    /// Encode 4 data bytes → 5 GCR bytes
    static func encodeGCR(_ b: [UInt8]) -> [UInt8] {
        precondition(b.count == 4)
        // 8 nybbles → 8 GCR 5-bit values → pack into 5 bytes (40 bits)
        let g0 = UInt64(gcrEncode[Int(b[0] >> 4)])
        let g1 = UInt64(gcrEncode[Int(b[0] & 0x0F)])
        let g2 = UInt64(gcrEncode[Int(b[1] >> 4)])
        let g3 = UInt64(gcrEncode[Int(b[1] & 0x0F)])
        let g4 = UInt64(gcrEncode[Int(b[2] >> 4)])
        let g5 = UInt64(gcrEncode[Int(b[2] & 0x0F)])
        let g6 = UInt64(gcrEncode[Int(b[3] >> 4)])
        let g7 = UInt64(gcrEncode[Int(b[3] & 0x0F)])

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

    /// Encode an arbitrary number of bytes using GCR (padding to multiple of 4).
    static func encodeGCRBytes(_ data: [UInt8]) -> [UInt8] {
        var padded = data
        while padded.count % 4 != 0 { padded.append(0) }
        var result = [UInt8]()
        for i in stride(from: 0, to: padded.count, by: 4) {
            result.append(contentsOf: encodeGCR(Array(padded[i..<i+4])))
        }
        return result
    }

    // MARK: - Test: GCR round-trip

    func testGCRRoundTrip() {
        let original: [UInt8] = [0x08, 0xAB, 0x03, 0x01]
        let encoded = Self.encodeGCR(original)
        XCTAssertEqual(encoded.count, 5)

        let decoded = G64Parser.decodeGCRBlock(encoded, count: 4)
        XCTAssertEqual(decoded, original)
    }

    func testGCRMultipleBlocks() {
        let original: [UInt8] = [0x07, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47]
        let encoded = Self.encodeGCRBytes(original)
        XCTAssertEqual(encoded.count, 10) // 8 bytes → 2 groups of 4 → 10 GCR bytes

        let decoded = G64Parser.decodeGCRBlock(encoded, count: 8)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Test: G64 signature detection

    func testInvalidSignature() {
        let data = Data([0x47, 0x43, 0x52, 0x2D, 0x31, 0x35, 0x34, 0x30, // "GCR-1540" (wrong)
                         0x00, 0x54, 0x00, 0x00])
        XCTAssertNil(G64Parser.decode(data))
    }

    func testTooSmall() {
        let data = Data([0x47, 0x43, 0x52])
        XCTAssertNil(G64Parser.decode(data))
    }

    // MARK: - Test: Minimal G64 with one track

    func testMinimalG64Decode() {
        // Build a minimal G64 with track 18, sector 0 containing known BAM data
        let g64 = buildMinimalG64()
        guard let decoded = G64Parser.decode(Data(g64)) else {
            XCTFail("G64 decode returned nil")
            return
        }

        // Check that we got a D64-sized output
        XCTAssertEqual(decoded.count, 174848)

        // Verify track 18 sector 0 contains our test BAM data
        let bamOffset = DiskDrive.trackOffset[18]
        // The first byte we wrote was 18 (directory track pointer)
        XCTAssertEqual(decoded[bamOffset], 18, "BAM track pointer should be 18")
        XCTAssertEqual(decoded[bamOffset + 1], 1, "BAM sector pointer should be 1")
    }

    // MARK: - Test: Mount G64 via DiskDrive

    func testMountG64() {
        let g64 = buildMinimalG64()
        let drive = DiskDrive()
        XCTAssertTrue(drive.mountG64(Data(g64)))
        XCTAssertTrue(drive.isMounted)
    }

    // MARK: - Test helper: build a minimal G64

    func buildMinimalG64() -> [UInt8] {
        // We'll create a G64 with just track 18 (half-track index 34) containing
        // a BAM sector (sector 0) with directory pointer to 18/1.

        let numTracks = 84  // standard
        var g64 = [UInt8]()

        // Signature
        g64.append(contentsOf: [0x47, 0x43, 0x52, 0x2D, 0x31, 0x35, 0x34, 0x31]) // "GCR-1541"
        g64.append(0x00)  // version
        g64.append(UInt8(numTracks))
        g64.append(0x00)  // max track size lo
        g64.append(0x1E)  // max track size hi (7680)

        // Track offset table (84 entries × 4 bytes)
        let offsetTablePos = g64.count
        for _ in 0..<numTracks {
            g64.append(contentsOf: [0, 0, 0, 0])
        }

        // Speed zone table (84 entries × 4 bytes)
        for _ in 0..<numTracks {
            g64.append(contentsOf: [0, 0, 0, 0])
        }

        // Build track 18 data (half-track index 34)
        let trackDataOffset = g64.count

        // Build a GCR-encoded sector 0 for track 18
        let sectorData = buildBAMSector()
        let trackGCR = buildGCRTrack(track: 18, sectors: [(0, sectorData)])

        // Track data: 2-byte length + GCR data
        let trackLen = trackGCR.count
        g64.append(UInt8(trackLen & 0xFF))
        g64.append(UInt8(trackLen >> 8))
        g64.append(contentsOf: trackGCR)

        // Patch the track offset for half-track 34 (track 18)
        let halfTrack34 = 34
        let offsetPos = offsetTablePos + halfTrack34 * 4
        g64[offsetPos] = UInt8(trackDataOffset & 0xFF)
        g64[offsetPos + 1] = UInt8((trackDataOffset >> 8) & 0xFF)
        g64[offsetPos + 2] = UInt8((trackDataOffset >> 16) & 0xFF)
        g64[offsetPos + 3] = UInt8((trackDataOffset >> 24) & 0xFF)

        return g64
    }

    func buildBAMSector() -> [UInt8] {
        var sector = [UInt8](repeating: 0, count: 256)
        sector[0] = 18   // directory track
        sector[1] = 1    // directory sector
        sector[2] = 0x41 // DOS version 'A'
        return sector
    }

    func buildGCRTrack(track: Int, sectors: [(Int, [UInt8])]) -> [UInt8] {
        var gcr = [UInt8]()

        for (sectorNum, data) in sectors {
            // Sync mark for header
            gcr.append(contentsOf: [UInt8](repeating: 0xFF, count: 5))

            // Sector header: $08, checksum, sector, track, id2, id1, $0F, $0F
            let id1: UInt8 = 0x41
            let id2: UInt8 = 0x42
            let checksum = UInt8(sectorNum) ^ UInt8(track) ^ id2 ^ id1
            let header: [UInt8] = [0x08, checksum, UInt8(sectorNum), UInt8(track),
                                    id2, id1, 0x0F, 0x0F]
            gcr.append(contentsOf: Self.encodeGCRBytes(header))

            // Gap between header and data
            gcr.append(contentsOf: [UInt8](repeating: 0x55, count: 9))

            // Sync mark for data block
            gcr.append(contentsOf: [UInt8](repeating: 0xFF, count: 5))

            // Data block: $07, 256 data bytes, checksum, 0, 0 = 260 bytes
            var dataBlock = [UInt8]()
            dataBlock.append(0x07)  // data block marker
            dataBlock.append(contentsOf: data)
            var dataChecksum: UInt8 = 0
            for b in data { dataChecksum ^= b }
            dataBlock.append(dataChecksum)
            dataBlock.append(0x00)
            dataBlock.append(0x00)
            // Pad to multiple of 4 for GCR encoding
            while dataBlock.count % 4 != 0 { dataBlock.append(0x00) }

            gcr.append(contentsOf: Self.encodeGCRBytes(dataBlock))

            // Inter-sector gap
            gcr.append(contentsOf: [UInt8](repeating: 0x55, count: 8))
        }

        return gcr
    }
}
