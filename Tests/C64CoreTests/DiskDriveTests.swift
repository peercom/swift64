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

    func testDirectoryParsingStopsOnCyclicSectorChain() {
        let drive = DiskDrive()
        var image = [UInt8](makeMinimalD64())
        let dirOffset = DiskDrive.trackOffset[18] + 1 * 256
        image[dirOffset] = 18
        image[dirOffset + 1] = 1

        XCTAssertTrue(drive.mount(Data(image)))

        XCTAssertEqual(drive.directory.count, 1)
        XCTAssertEqual(drive.directory.first?.filename, "hello")
    }

    func testMountExtendedD64SizeWithStandardDirectory() {
        let drive = DiskDrive()
        var image = [UInt8](makeMinimalD64())
        image.append(contentsOf: [UInt8](repeating: 0, count: 200704 - image.count))

        XCTAssertTrue(drive.mount(Data(image)))
        XCTAssertTrue(drive.isMounted)
        XCTAssertEqual(drive.directory.first?.filename, "hello")
    }

    func testD64GeometryRecognizesExtendedImagesWithErrorTables() throws {
        let cases: [(size: Int, dataSize: Int, tracks: Int, sectorCount: Int, errorOffset: Int?)] = [
            (174848, 174848, 35, 683, nil),
            (175531, 174848, 35, 683, 174848),
            (196608, 196608, 40, 768, nil),
            (197376, 196608, 40, 768, 196608),
            (200704, 200704, 41, 784, nil),
            (201488, 200704, 41, 784, 200704),
            (205312, 205312, 42, 802, nil),
            (206114, 205312, 42, 802, 205312),
        ]

        for geometryCase in cases {
            let geometry = try XCTUnwrap(
                DiskDrive.d64Geometry(forByteCount: geometryCase.size),
                "Expected \(geometryCase.size)-byte D64 geometry"
            )
            let sectorCount = geometry.sectorsPerTrack[1...geometry.trackCount].reduce(0, +)

            XCTAssertEqual(geometry.dataSize, geometryCase.dataSize)
            XCTAssertEqual(geometry.trackCount, geometryCase.tracks)
            XCTAssertEqual(sectorCount, geometryCase.sectorCount)
            XCTAssertEqual(geometry.errorInfoOffset, geometryCase.errorOffset)
        }
    }

    func testExtendedD64CanReadFileDataFromTrack36() throws {
        let drive = DiskDrive()
        var image = [UInt8](makeMinimalD64(fileBlocks: 1))
        image.append(contentsOf: [UInt8](repeating: 0, count: 196608 - image.count))
        let geometry = try XCTUnwrap(DiskDrive.d64Geometry(forByteCount: image.count))

        let dirOffset = DiskDrive.trackOffset[18] + 1 * 256
        image[dirOffset + 3] = 36
        image[dirOffset + 4] = 0

        let fileOffset = geometry.trackOffsets[36]
        image[fileOffset + 0] = 0
        image[fileOffset + 1] = 4
        image[fileOffset + 2] = 0xA9
        image[fileOffset + 3] = 0x2A

        XCTAssertTrue(drive.mount(Data(image)))
        let entry = try XCTUnwrap(drive.findFile("HELLO"))

        XCTAssertEqual(drive.readFileData(entry), [0xA9, 0x2A])
    }

    func testFileReadStopsOnCyclicSectorChain() throws {
        let drive = DiskDrive()
        var image = [UInt8](makeMinimalD64(fileBlocks: 1))

        let fileOffset = DiskDrive.trackOffset[1]
        image[fileOffset] = 1
        image[fileOffset + 1] = 0
        image[fileOffset + 2] = 0x01
        image[fileOffset + 3] = 0x08
        image[fileOffset + 4] = 0xA9
        image[fileOffset + 5] = 0x2A

        XCTAssertTrue(drive.mount(Data(image)))
        let entry = try XCTUnwrap(drive.findFile("HELLO"))
        let data = drive.readFileData(entry)

        XCTAssertEqual(data.count, 254)
        XCTAssertEqual(Array(data.prefix(4)), [0x01, 0x08, 0xA9, 0x2A])
    }

    func testPlainD64DoesNotExposeSectorErrorInfo() {
        let drive = DiskDrive()

        XCTAssertTrue(drive.mount(makeMinimalD64()))

        XCTAssertFalse(drive.hasSectorErrorInfo)
        XCTAssertNil(drive.readSectorErrorCode(track: 1, sector: 0))
    }

    func testD64WithSectorErrorBytesPreservesErrorCodes() throws {
        let drive = DiskDrive()
        var image = [UInt8](makeMinimalD64())
        image.append(contentsOf: [UInt8](repeating: 0x01, count: 683))
        let geometry = try XCTUnwrap(DiskDrive.d64Geometry(forByteCount: image.count))
        let errorOffset = try XCTUnwrap(geometry.errorInfoOffset)
        image[errorOffset] = 0x05
        image[errorOffset + 358] = 0x0B // Track 18, sector 1.

        XCTAssertTrue(drive.mount(Data(image)))

        XCTAssertTrue(drive.hasSectorErrorInfo)
        XCTAssertEqual(drive.readSectorErrorCode(track: 1, sector: 0), 0x05)
        XCTAssertEqual(drive.readSectorErrorCode(track: 18, sector: 1), 0x0B)
        XCTAssertNil(drive.readSectorErrorCode(track: 36, sector: 0))
    }

    func testExtendedD64WithSectorErrorBytesPreservesTrack41ErrorCodes() throws {
        let drive = DiskDrive()
        var image = [UInt8](makeMinimalD64())
        image.append(contentsOf: [UInt8](repeating: 0, count: 200704 - image.count))
        image.append(contentsOf: [UInt8](repeating: 0x01, count: 784))
        let geometry = try XCTUnwrap(DiskDrive.d64Geometry(forByteCount: image.count))
        let errorOffset = try XCTUnwrap(geometry.errorInfoOffset)
        image[errorOffset + 783] = 0x0F

        XCTAssertTrue(drive.mount(Data(image)))

        XCTAssertTrue(drive.hasSectorErrorInfo)
        XCTAssertEqual(drive.readSectorErrorCode(track: 41, sector: 15), 0x0F)
        XCTAssertNil(drive.readSectorErrorCode(track: 41, sector: 16))
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
            let textStart = offset + 4
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

    func testFindFileAcceptsDrivePrefixAndFileOptions() throws {
        let drive = DiskDrive()
        XCTAssertTrue(drive.mount(makeMinimalD64()))

        XCTAssertNotNil(drive.findFile("0:HELLO"))
        XCTAssertNotNil(drive.findFile(":HELLO,P,R"))
        XCTAssertNotNil(drive.findFile("HEL*,P"))
        XCTAssertTrue(drive.isDirectoryListingRequest("$0"))
        XCTAssertTrue(drive.isDirectoryListingRequest("0:$"))
    }

    func testSavePRGWritesDirectoryBAMAndReadableSectorChain() throws {
        let drive = DiskDrive()
        XCTAssertTrue(drive.mount(makeBlankWritableD64()))
        XCTAssertEqual(drive.mountedFormat, .d64)
        XCTAssertFalse(drive.hasUnsavedChanges)
        let initialFreeBlocks = drive.freeBlocks()
        let payload = [0x01, 0x08] + Array((0..<300).map { UInt8($0 & 0xFF) })

        XCTAssertTrue(drive.savePRG(filename: "NEWFILE", data: payload))

        let entry = try XCTUnwrap(drive.findFile("NEWFILE"))
        XCTAssertEqual(entry.filename, "newfile")
        XCTAssertEqual(entry.typeName, "PRG")
        XCTAssertEqual(entry.fileSize, 2)
        XCTAssertEqual(drive.readFileData(entry), payload)
        XCTAssertEqual(drive.freeBlocks(), initialFreeBlocks - 2)
        XCTAssertTrue(drive.hasUnsavedChanges)
        drive.markChangesSaved()
        XCTAssertFalse(drive.hasUnsavedChanges)

        let firstSector = drive.readSector(track: Int(entry.firstTrack), sector: Int(entry.firstSector))
        XCTAssertEqual(firstSector?[0], 1)
        XCTAssertEqual(firstSector?[1], 1)
    }

    func testSavedD64ExportsModifiedImageThatCanBeRemounted() throws {
        let drive = DiskDrive()
        XCTAssertTrue(drive.mount(makeBlankWritableD64()))
        XCTAssertTrue(drive.savePRG(filename: "EXPORT", data: [0x00, 0x20, 0xA9, 0x7F, 0x60]))
        let exported = try XCTUnwrap(drive.exportedD64Image)

        let remounted = DiskDrive()
        XCTAssertTrue(remounted.mount(exported))
        XCTAssertFalse(remounted.hasUnsavedChanges)
        let entry = try XCTUnwrap(remounted.findFile("EXPORT"))
        XCTAssertEqual(remounted.readFileData(entry), [0x00, 0x20, 0xA9, 0x7F, 0x60])
    }

    func testSavePRGRejectsDecodedG64ReadPath() {
        let drive = DiskDrive()
        XCTAssertTrue(drive.mountG64(makeMinimalReadableG64()))
        XCTAssertEqual(drive.mountedFormat, .g64)

        XCTAssertFalse(drive.savePRG(filename: "NOPE", data: [0x01, 0x08, 0x60]))

        XCTAssertFalse(drive.hasUnsavedChanges)
        XCTAssertNil(drive.exportedD64Image)
    }

    func testSavePRGRejectsDuplicateFilenameWithoutChangingFreeBlocks() throws {
        let drive = DiskDrive()
        XCTAssertTrue(drive.mount(makeBlankWritableD64()))
        XCTAssertTrue(drive.savePRG(filename: "ONCE", data: [0x01, 0x08, 0xA9, 0x2A]))
        let freeAfterFirstSave = drive.freeBlocks()

        XCTAssertFalse(drive.savePRG(filename: "ONCE", data: [0x01, 0x08, 0xEA]))

        XCTAssertEqual(drive.freeBlocks(), freeAfterFirstSave)
        let entry = try XCTUnwrap(drive.findFile("ONCE"))
        XCTAssertEqual(drive.readFileData(entry), [0x01, 0x08, 0xA9, 0x2A])
    }

    func testSavePRGReplaceSyntaxReusesDirectoryEntryAndFreesOldChain() throws {
        let drive = DiskDrive()
        XCTAssertTrue(drive.mount(makeBlankWritableD64()))
        let initialFreeBlocks = drive.freeBlocks()
        XCTAssertTrue(drive.savePRG(filename: "ONCE", data: [0x01, 0x08, 0xA9, 0x2A]))
        XCTAssertEqual(drive.freeBlocks(), initialFreeBlocks - 1)

        let replacement = [0x01, 0x08] + Array((0..<300).map { UInt8(($0 &+ 3) & 0xFF) })
        XCTAssertTrue(drive.savePRG(filename: "@0:ONCE,P", data: replacement))

        XCTAssertEqual(drive.directory.count, 1)
        let entry = try XCTUnwrap(drive.findFile("0:ONCE"))
        XCTAssertEqual(entry.fileSize, 2)
        XCTAssertEqual(drive.readFileData(entry), replacement)
        XCTAssertEqual(drive.freeBlocks(), initialFreeBlocks - 2)
        XCTAssertTrue(drive.hasUnsavedChanges)
    }

    func testCommandChannelScratchDeletesFileAndReportsStatus() throws {
        let drive = DiskDrive()
        XCTAssertTrue(drive.mount(makeBlankWritableD64()))
        let initialFreeBlocks = drive.freeBlocks()
        XCTAssertTrue(drive.savePRG(filename: "DELETE", data: [0x01, 0x08, 0xA9, 0x2A]))
        XCTAssertEqual(drive.freeBlocks(), initialFreeBlocks - 1)

        XCTAssertTrue(drive.openFile(channel: 15, filename: "S:DELETE"))

        XCTAssertNil(drive.findFile("DELETE"))
        XCTAssertEqual(drive.directory.count, 0)
        XCTAssertEqual(drive.freeBlocks(), initialFreeBlocks)
        XCTAssertTrue(drive.hasUnsavedChanges)
        XCTAssertTrue(readChannelString(drive, channel: 15).hasPrefix("01, FILES SCRATCHED"))
    }

    func testCommandChannelScratchWildcardDeletesMatchingFiles() throws {
        let drive = DiskDrive()
        XCTAssertTrue(drive.mount(makeBlankWritableD64()))
        XCTAssertTrue(drive.savePRG(filename: "ONE", data: [0x01, 0x08, 0x01]))
        XCTAssertTrue(drive.savePRG(filename: "TWO", data: [0x01, 0x08, 0x02]))
        XCTAssertTrue(drive.savePRG(filename: "THREE", data: [0x01, 0x08, 0x03]))

        XCTAssertTrue(drive.openFile(channel: 15, filename: "S:T*"))

        XCTAssertNotNil(drive.findFile("ONE"))
        XCTAssertNil(drive.findFile("TWO"))
        XCTAssertNil(drive.findFile("THREE"))
        XCTAssertTrue(readChannelString(drive, channel: 15).hasPrefix("02, FILES SCRATCHED"))
    }

    func testCommandChannelScratchMissingFileReportsFileNotFound() {
        let drive = DiskDrive()
        XCTAssertTrue(drive.mount(makeBlankWritableD64()))

        XCTAssertTrue(drive.openFile(channel: 15, filename: "S:MISSING"))

        XCTAssertEqual(readChannelString(drive, channel: 15), "62, FILE NOT FOUND,00,00\r")
        XCTAssertFalse(drive.hasUnsavedChanges)
    }

    func testCommandChannelRenameUpdatesDirectoryOnly() throws {
        let drive = DiskDrive()
        XCTAssertTrue(drive.mount(makeBlankWritableD64()))
        XCTAssertTrue(drive.savePRG(filename: "OLD", data: [0x01, 0x08, 0xA9, 0x2A]))
        let freeAfterSave = drive.freeBlocks()

        XCTAssertTrue(drive.openFile(channel: 15, filename: "R:NEW=OLD"))

        XCTAssertNil(drive.findFile("OLD"))
        let entry = try XCTUnwrap(drive.findFile("0:NEW"))
        XCTAssertEqual(drive.readFileData(entry), [0x01, 0x08, 0xA9, 0x2A])
        XCTAssertEqual(drive.freeBlocks(), freeAfterSave)
        XCTAssertEqual(readChannelString(drive, channel: 15), "00, OK,00,00\r")
    }

    func testCommandChannelRenameReportsMissingAndDuplicateErrors() {
        let drive = DiskDrive()
        XCTAssertTrue(drive.mount(makeBlankWritableD64()))
        XCTAssertTrue(drive.savePRG(filename: "ONE", data: [0x01, 0x08, 0x01]))
        XCTAssertTrue(drive.savePRG(filename: "TWO", data: [0x01, 0x08, 0x02]))

        XCTAssertTrue(drive.openFile(channel: 15, filename: "R:THREE=MISSING"))
        XCTAssertEqual(readChannelString(drive, channel: 15), "62, FILE NOT FOUND,00,00\r")

        XCTAssertTrue(drive.openFile(channel: 15, filename: "R:ONE=TWO"))
        XCTAssertEqual(readChannelString(drive, channel: 15), "63, FILE EXISTS,00,00\r")
        XCTAssertNotNil(drive.findFile("ONE"))
        XCTAssertNotNil(drive.findFile("TWO"))
    }

    func testSavePRGTooLargeFailsWithoutConsumingFreeBlocks() {
        let drive = DiskDrive()
        XCTAssertTrue(drive.mount(makeBlankWritableD64()))
        let initialFreeBlocks = drive.freeBlocks()
        let oversizedPayload = [UInt8](repeating: 0xEA, count: 200_000)

        XCTAssertFalse(drive.savePRG(filename: "TOO BIG", data: oversizedPayload))

        XCTAssertEqual(drive.directory.count, 0)
        XCTAssertEqual(drive.freeBlocks(), initialFreeBlocks)
    }

    private func makeBlankWritableD64() -> Data {
        let totalBytes = 174848
        var image = [UInt8](repeating: 0, count: totalBytes)
        let bamOffset = DiskDrive.trackOffset[18]

        image[bamOffset + 0] = 18
        image[bamOffset + 1] = 1
        image[bamOffset + 2] = 0x41

        for track in 1...35 {
            let entryOffset = bamOffset + track * 4
            let sectors = DiskDrive.sectorsPerTrack[track]
            var bitmap = [UInt8](repeating: 0, count: 3)
            for sector in 0..<sectors {
                bitmap[sector / 8] |= 1 << UInt8(sector % 8)
            }

            if track == 18 {
                bitmap[0] &= ~UInt8(0x03)
                image[entryOffset] = UInt8(sectors - 2)
            } else {
                image[entryOffset] = UInt8(sectors)
            }

            image[entryOffset + 1] = bitmap[0]
            image[entryOffset + 2] = bitmap[1]
            image[entryOffset + 3] = bitmap[2]
        }

        let name = Array("WRITE TEST".utf8)
        for i in 0..<16 {
            image[bamOffset + 0x90 + i] = i < name.count ? name[i] : 0xA0
        }
        image[bamOffset + 0xA2] = 0x53
        image[bamOffset + 0xA3] = 0x57
        image[bamOffset + 0xA5] = 0x32
        image[bamOffset + 0xA6] = 0x41

        let dirOffset = DiskDrive.trackOffset[18] + 256
        image[dirOffset + 0] = 0
        image[dirOffset + 1] = 0xFF

        return Data(image)
    }

    private func readChannelString(_ drive: DiskDrive, channel: Int) -> String {
        var bytes: [UInt8] = []
        while true {
            let result = drive.readByte(channel: channel)
            bytes.append(result.byte)
            if result.eof { break }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func makeMinimalReadableG64() -> Data {
        var sector = [UInt8](repeating: 0, count: 256)
        sector[0] = 18
        sector[1] = 1
        sector[2] = 0x41
        return Data(buildG64(trackSectors: [18: [(0, sector)]]))
    }

    private func buildG64(trackSectors: [Int: [(Int, [UInt8])]]) -> [UInt8] {
        let numTracks = 84
        var g64 = [UInt8]()

        g64.append(contentsOf: [0x47, 0x43, 0x52, 0x2D, 0x31, 0x35, 0x34, 0x31])
        g64.append(0x00)
        g64.append(UInt8(numTracks))
        g64.append(0x00)
        g64.append(0x1E)

        let offsetTablePosition = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: numTracks * 4))
        g64.append(contentsOf: [UInt8](repeating: 0, count: numTracks * 4))

        for track in trackSectors.keys.sorted() {
            let halfTrack = (track - 1) * 2
            guard let sectors = trackSectors[track] else { continue }
            let trackDataOffset = g64.count
            let trackGCR = buildGCRTrack(track: track, sectors: sectors)
            g64.append(UInt8(trackGCR.count & 0xFF))
            g64.append(UInt8(trackGCR.count >> 8))
            g64.append(contentsOf: trackGCR)

            let offsetPosition = offsetTablePosition + halfTrack * 4
            g64[offsetPosition] = UInt8(trackDataOffset & 0xFF)
            g64[offsetPosition + 1] = UInt8((trackDataOffset >> 8) & 0xFF)
            g64[offsetPosition + 2] = UInt8((trackDataOffset >> 16) & 0xFF)
            g64[offsetPosition + 3] = UInt8((trackDataOffset >> 24) & 0xFF)
        }

        return g64
    }

    private func buildGCRTrack(track: Int, sectors: [(Int, [UInt8])]) -> [UInt8] {
        var gcr = [UInt8]()

        for (sectorNumber, sectorData) in sectors {
            gcr.append(contentsOf: [UInt8](repeating: 0xFF, count: 5))
            let id1: UInt8 = 0x41
            let id2: UInt8 = 0x42
            let headerChecksum = UInt8(sectorNumber) ^ UInt8(track) ^ id2 ^ id1
            let header: [UInt8] = [0x08, headerChecksum, UInt8(sectorNumber), UInt8(track), id2, id1, 0x0F, 0x0F]
            gcr.append(contentsOf: encodeGCRBytes(header))
            gcr.append(contentsOf: [UInt8](repeating: 0x55, count: 9))
            gcr.append(contentsOf: [UInt8](repeating: 0xFF, count: 5))

            var dataBlock = [UInt8]()
            dataBlock.append(0x07)
            dataBlock.append(contentsOf: sectorData)
            dataBlock.append(sectorData.reduce(0, ^))
            dataBlock.append(0x00)
            dataBlock.append(0x00)
            gcr.append(contentsOf: encodeGCRBytes(dataBlock))
            gcr.append(contentsOf: [UInt8](repeating: 0x55, count: 8))
        }

        return gcr
    }

    private func encodeGCRBytes(_ data: [UInt8]) -> [UInt8] {
        var padded = data
        while padded.count % 4 != 0 { padded.append(0) }
        var result = [UInt8]()
        for index in stride(from: 0, to: padded.count, by: 4) {
            result.append(contentsOf: encodeGCR(Array(padded[index..<index + 4])))
        }
        return result
    }

    private func encodeGCR(_ bytes: [UInt8]) -> [UInt8] {
        let encode: [UInt8] = [0x0A, 0x0B, 0x12, 0x13, 0x0E, 0x0F, 0x16, 0x17, 0x09, 0x19, 0x1A, 0x1B, 0x0D, 0x1D, 0x1E, 0x15]
        let g0 = UInt64(encode[Int(bytes[0] >> 4)])
        let g1 = UInt64(encode[Int(bytes[0] & 0x0F)])
        let g2 = UInt64(encode[Int(bytes[1] >> 4)])
        let g3 = UInt64(encode[Int(bytes[1] & 0x0F)])
        let g4 = UInt64(encode[Int(bytes[2] >> 4)])
        let g5 = UInt64(encode[Int(bytes[2] & 0x0F)])
        let g6 = UInt64(encode[Int(bytes[3] >> 4)])
        let g7 = UInt64(encode[Int(bytes[3] & 0x0F)])
        let bits = (g0 << 35) | (g1 << 30) | (g2 << 25) | (g3 << 20) | (g4 << 15) | (g5 << 10) | (g6 << 5) | g7

        return [
            UInt8((bits >> 32) & 0xFF),
            UInt8((bits >> 24) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8(bits & 0xFF),
        ]
    }
}
