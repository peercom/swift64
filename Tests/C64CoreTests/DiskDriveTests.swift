import XCTest
@testable import C64Core

final class DiskDriveTests: XCTestCase {

    /// Build a minimal 35-track D64 image with a known disk name, ID, and one PRG file entry.
    func makeMinimalD64(diskName: String = "TEST DISK", diskID: String = "AB", fileName: String = "HELLO", fileBlocks: UInt16 = 5) -> Data {
        let totalBytes = 174848
        var image = [UInt8](repeating: 0, count: totalBytes)

        // --- BAM (track 18, sector 0) ---
        let bamOffset = DiskDrive.trackOffset[18]

        // First directory sector pointer
        image[bamOffset + 0] = 18   // directory track
        image[bamOffset + 1] = 1    // directory sector

        // DOS version
        image[bamOffset + 2] = 0x41 // 'A'

        // BAM entries for tracks 1-35 (4 bytes each, starting at offset 4)
        for t in 1...35 {
            let off = bamOffset + t * 4
            if t == 18 {
                image[off] = 0  // no free sectors on directory track
            } else {
                image[off] = UInt8(DiskDrive.sectorsPerTrack[t])  // all free
            }
        }

        // Disk name at offset $90 (16 bytes, padded with $A0)
        let nameBytes = Array(diskName.utf8)
        for i in 0..<16 {
            if i < nameBytes.count {
                // Convert ASCII to PETSCII uppercase
                var b = nameBytes[i]
                if b >= 0x61 && b <= 0x7A { b -= 32 }
                image[bamOffset + 0x90 + i] = b
            } else {
                image[bamOffset + 0x90 + i] = 0xA0
            }
        }

        // Disk ID at offset $A2 (2 bytes)
        let idBytes = Array(diskID.utf8)
        for i in 0..<2 {
            if i < idBytes.count {
                image[bamOffset + 0xA2 + i] = idBytes[i]
            }
        }

        // DOS type at $A5-$A6
        image[bamOffset + 0xA5] = 0x32  // '2'
        image[bamOffset + 0xA6] = 0x41  // 'A'

        // --- Directory (track 18, sector 1) ---
        let dirOffset = DiskDrive.trackOffset[18] + 1 * 256

        // No next directory sector
        image[dirOffset + 0] = 0
        image[dirOffset + 1] = 0xFF

        // First entry at offset 0 within sector (but entry data starts at byte 2 of 32-byte slot)
        let entryBase = dirOffset + 0  // first 32-byte slot
        image[entryBase + 2] = 0x82   // PRG, closed

        // File first track/sector (we'll put dummy data at track 1, sector 0)
        image[entryBase + 3] = 1   // first track
        image[entryBase + 4] = 0   // first sector

        // Filename at entry+5 (16 bytes padded with $A0)
        let fnBytes = Array(fileName.utf8)
        for i in 0..<16 {
            if i < fnBytes.count {
                var b = fnBytes[i]
                if b >= 0x61 && b <= 0x7A { b -= 32 }
                image[entryBase + 5 + i] = b
            } else {
                image[entryBase + 5 + i] = 0xA0
            }
        }

        // File size in sectors
        image[entryBase + 30] = UInt8(fileBlocks & 0xFF)
        image[entryBase + 31] = UInt8(fileBlocks >> 8)

        return Data(image)
    }

    func testMountAndParseDirectory() {
        let drive = DiskDrive()
        let d64 = makeMinimalD64()
        XCTAssertTrue(drive.mount(d64))
        XCTAssertTrue(drive.isMounted)
        XCTAssertEqual(drive.directory.count, 1, "Should find 1 directory entry")
        XCTAssertEqual(drive.directory.first?.filename, "hello")  // petsciiToChar lowercases PETSCII uppercase
        XCTAssertEqual(drive.directory.first?.typeName, "PRG")
    }

    func testGenerateDirectoryListing() {
        let drive = DiskDrive()
        let d64 = makeMinimalD64()
        XCTAssertTrue(drive.mount(d64))

        let prg = drive.generateDirectoryListing()

        // Must start with load address $0801
        XCTAssertGreaterThanOrEqual(prg.count, 4, "PRG must have at least load address + end marker")
        XCTAssertEqual(prg[0], 0x01, "Load address lo should be $01")
        XCTAssertEqual(prg[1], 0x08, "Load address hi should be $08")

        // Walk the BASIC program (skip 2-byte load address)
        let base = 0x0801
        var offset = 2  // skip load address
        var lineCount = 0

        while offset + 1 < prg.count {
            let nextPtrLo = Int(prg[offset])
            let nextPtrHi = Int(prg[offset + 1])
            let nextPtr = nextPtrLo | (nextPtrHi << 8)

            if nextPtr == 0 {
                // End of program
                break
            }

            // Line number
            let lineNumLo = Int(prg[offset + 2])
            let lineNumHi = Int(prg[offset + 3])
            let lineNum = lineNumLo | (lineNumHi << 8)

            // Find end of line (0x00 terminator)
            var textStart = offset + 4
            var textEnd = textStart
            while textEnd < prg.count && prg[textEnd] != 0 {
                textEnd += 1
            }

            let textBytes = Array(prg[textStart..<textEnd])
            let text = textBytes.map { b -> Character in
                if b >= 0x20 && b <= 0x7E { return Character(UnicodeScalar(b)) }
                if b == 0x12 { return Character("®") }  // reverse on placeholder
                return Character("?")
            }
            let textStr = String(text)

            print("Line \(lineCount): num=\(lineNum) nextPtr=$\(String(nextPtr, radix: 16)) text=[\(textStr)]")

            // Verify next pointer = base + (textEnd + 1 - 2) = points to byte after terminator
            let expectedNextPtr = base + (textEnd + 1 - 2)
            XCTAssertEqual(nextPtr, expectedNextPtr,
                "Next line pointer should point to byte after 0x00 terminator (line \(lineCount))")

            lineCount += 1

            // Advance to next line
            let nextLineOffset = nextPtr - base + 2  // +2 for load address prefix
            XCTAssertGreaterThan(nextLineOffset, offset, "Must advance forward")
            offset = nextLineOffset
        }

        XCTAssertGreaterThanOrEqual(lineCount, 2, "Should have at least header + footer lines")
        print("Total lines: \(lineCount), total bytes: \(prg.count)")

        // Verify the program ends with 0x00 0x00
        XCTAssertEqual(prg[offset], 0x00, "End marker lo")
        XCTAssertEqual(prg[offset + 1], 0x00, "End marker hi")

        // Simulate what handleLoad does
        let payload = Array(prg[2...])
        let endAddr = 0x0801 + payload.count
        print("Payload size: \(payload.count), endAddr: $\(String(endAddr, radix: 16))")
        print("First 20 payload bytes: \(payload.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " "))")

        // Verify first 2 bytes at $0801 (next-line pointer) are non-zero
        XCTAssertFalse(payload[0] == 0 && payload[1] == 0,
            "First line's next-line pointer at $0801 must NOT be $0000")
    }

    func testEmptyDirectoryListing() {
        // D64 with no files
        let drive = DiskDrive()
        let d64 = makeMinimalD64(fileName: "")
        // Override: clear the file entry
        var image = [UInt8](d64)
        let dirOffset = DiskDrive.trackOffset[18] + 1 * 256
        image[dirOffset + 2] = 0  // clear file type = empty entry
        XCTAssertTrue(drive.mount(Data(image)))
        XCTAssertEqual(drive.directory.count, 0)

        let prg = drive.generateDirectoryListing()
        XCTAssertGreaterThan(prg.count, 4)

        // Should still have header + footer
        let payload = Array(prg[2...])
        XCTAssertFalse(payload[0] == 0 && payload[1] == 0,
            "Even empty directory should have non-zero first pointer")
    }
}
