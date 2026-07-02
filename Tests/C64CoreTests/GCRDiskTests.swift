import XCTest
@testable import C64Core

final class GCRDiskTests: XCTestCase {
    func testG64LoadRejectsUnsupportedVersion() {
        var g64 = makeEmptyG64Header(version: 1)

        let offsetTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))
        let rawTrack: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
        let trackOffset = g64.count
        g64.append(UInt8(rawTrack.count & 0xFF))
        g64.append(UInt8(rawTrack.count >> 8))
        g64.append(contentsOf: rawTrack)
        g64[offsetTableStart] = UInt8(trackOffset & 0xFF)
        g64[offsetTableStart + 1] = UInt8((trackOffset >> 8) & 0xFF)
        g64[offsetTableStart + 2] = UInt8((trackOffset >> 16) & 0xFF)
        g64[offsetTableStart + 3] = UInt8((trackOffset >> 24) & 0xFF)

        let disk = GCRDisk()

        XCTAssertFalse(disk.loadG64(Data(g64)))
        XCTAssertFalse(disk.hasDisk)
    }

    func testG64LoadRejectsImagesWithoutTrackData() {
        var g64 = makeEmptyG64Header(version: 0)
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 8))

        let disk = GCRDisk()

        XCTAssertFalse(disk.loadG64(Data(g64)))
        XCTAssertFalse(disk.hasDisk)
        XCTAssertNil(disk.image)
    }

    func testG64FailedLoadKeepsPreviouslyMountedTracks() {
        let disk = GCRDisk()
        let d64 = makeBlankD64()
        XCTAssertTrue(disk.loadD64(d64))
        let originalTrack = disk.trackInfo(halfTrack: 34)?.bytes
        var badG64 = makeEmptyG64Header(version: 0)
        badG64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 8))

        XCTAssertFalse(disk.loadG64(Data(badG64)))

        XCTAssertTrue(disk.hasDisk)
        XCTAssertEqual(disk.image?.format, .d64)
        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.bytes, originalTrack)
    }

    func testG64LoadPreservesNativeHalfTrackBytesAndSpeedZone() {
        var g64 = [UInt8]()
        g64.append(contentsOf: Array("GCR-1541".utf8))
        g64.append(0x00) // version
        g64.append(84)   // half-tracks
        g64.append(0x04) // max track size
        g64.append(0x00)

        let offsetTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))
        let speedTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))

        let rawTrack: [UInt8] = [0xDE, 0xAD, 0xBE, 0xEF]
        let trackOffset = g64.count
        g64.append(UInt8(rawTrack.count & 0xFF))
        g64.append(UInt8(rawTrack.count >> 8))
        g64.append(contentsOf: rawTrack)

        let halfTrack = 34
        let offsetPos = offsetTableStart + halfTrack * 4
        g64[offsetPos] = UInt8(trackOffset & 0xFF)
        g64[offsetPos + 1] = UInt8((trackOffset >> 8) & 0xFF)
        g64[offsetPos + 2] = UInt8((trackOffset >> 16) & 0xFF)
        g64[offsetPos + 3] = UInt8((trackOffset >> 24) & 0xFF)

        let speedPos = speedTableStart + halfTrack * 4
        g64[speedPos] = 0x02

        let disk = GCRDisk()
        XCTAssertTrue(disk.loadG64(Data(g64)))

        let info = disk.trackInfo(halfTrack: halfTrack)
        XCTAssertEqual(info?.bytes, rawTrack)
        XCTAssertEqual(info?.bitLength, rawTrack.count * 8)
        XCTAssertEqual(info?.speedZone, 2)
        XCTAssertEqual(info?.isNativeLowLevel, true)
        XCTAssertEqual(disk.image?.format, .g64)
        XCTAssertTrue(disk.hasNativeLowLevelImage)
        XCTAssertEqual(disk.image?.capabilities.nativeLowLevelTrackCount, 1)
        XCTAssertEqual(disk.image?.capabilities.syntheticGCRTrackCount, 0)
        XCTAssertEqual(disk.image?.capabilities.maxTrackSize, 4)
        XCTAssertFalse(disk.image?.capabilities.preservesHalfTracks == true)
        XCTAssertTrue(disk.image?.capabilities.preservesRawTrackLengths == true)
        XCTAssertTrue(disk.image?.capabilities.preservesSpeedZones == true)
        XCTAssertFalse(disk.image?.capabilities.preservesVariableSpeedZones == true)
        XCTAssertEqual(disk.image?.capabilities.variableSpeedZoneByteCount, 0)
        XCTAssertEqual(disk.image?.capabilities.weakBitRangeCount, 0)
        XCTAssertEqual(disk.image?.capabilities.weakBitTotalBitCount, 0)
        XCTAssertTrue(disk.image?.capabilities.supportsWraparoundReads == true)
        XCTAssertTrue(disk.image?.capabilities.unsupportedFeatures.contains("Weak/random bits") == true)
    }

    func testG64LoadFloorsMaxTrackSizeToActualTrackPayload() {
        var g64 = makeSingleTrackG64(halfTrack: 34, rawTrack: [0xDE, 0xAD, 0xBE, 0xEF])
        g64[10] = 0x01
        g64[11] = 0x00
        let disk = GCRDisk()

        XCTAssertTrue(disk.loadG64(Data(g64)))

        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.bytes.count, 4)
        XCTAssertEqual(disk.image?.capabilities.maxTrackSize, 4)
    }

    func testNIBLoadPreservesNativeHalfTracksAndSpeedZones() {
        let firstTrack = [UInt8](repeating: 0xAA, count: 0x2000)
        let halfTrack = [UInt8](repeating: 0x55, count: 0x2000)
        let nib = makeNIB(entries: [
            (nibHalfTrack: 2, density: 0x13, bytes: firstTrack),
            (nibHalfTrack: 3, density: 0x11, bytes: halfTrack),
        ])
        let disk = GCRDisk()

        XCTAssertTrue(disk.loadNIB(Data(nib)))

        XCTAssertEqual(disk.image?.format, .nib)
        XCTAssertEqual(disk.trackInfo(halfTrack: 0)?.bytes, firstTrack)
        XCTAssertEqual(disk.trackInfo(halfTrack: 0)?.speedZone, 3)
        XCTAssertEqual(disk.trackInfo(halfTrack: 0)?.bitLength, 0x2000 * 8)
        XCTAssertEqual(disk.trackInfo(halfTrack: 0)?.isNativeLowLevel, true)
        XCTAssertEqual(disk.trackInfo(halfTrack: 1)?.bytes, halfTrack)
        XCTAssertEqual(disk.trackInfo(halfTrack: 1)?.speedZone, 1)
        XCTAssertTrue(disk.hasNativeLowLevelImage)
        XCTAssertEqual(disk.image?.capabilities.populatedHalfTrackCount, 2)
        XCTAssertEqual(disk.image?.capabilities.nativeLowLevelTrackCount, 2)
        XCTAssertEqual(disk.image?.capabilities.syntheticGCRTrackCount, 0)
        XCTAssertEqual(disk.image?.capabilities.maxTrackSize, 0x2000)
        XCTAssertEqual(disk.image?.capabilities.preservesHalfTracks, true)
        XCTAssertEqual(disk.image?.capabilities.preservesRawTrackLengths, true)
        XCTAssertEqual(disk.image?.capabilities.preservesSpeedZones, true)
        XCTAssertTrue(disk.image?.capabilities.unsupportedFeatures.contains("Flux-level timing") == true)
        XCTAssertTrue(disk.image?.capabilities.unsupportedFeatures.contains("P64 metadata") == true)
        XCTAssertTrue(disk.image?.capabilities.unsupportedFeatures.contains("Weak/random bits") == true)
    }

    func testNIBLoadRejectsBadMagicOutOfRangeHalfTrackAndTruncatedPayload() {
        let disk = GCRDisk()
        var badMagic = makeNIB(entries: [
            (nibHalfTrack: 2, density: 0x03, bytes: [UInt8](repeating: 0xAA, count: 0x2000)),
        ])
        badMagic[0] = 0x00
        XCTAssertFalse(disk.loadNIB(Data(badMagic)))
        XCTAssertFalse(disk.hasDisk)

        let outOfRange = makeNIB(entries: [
            (nibHalfTrack: 1, density: 0x03, bytes: [UInt8](repeating: 0xAA, count: 0x2000)),
        ])
        XCTAssertFalse(disk.loadNIB(Data(outOfRange)))
        XCTAssertFalse(disk.hasDisk)

        var truncated = makeNIB(entries: [
            (nibHalfTrack: 2, density: 0x03, bytes: [UInt8](repeating: 0xAA, count: 0x2000)),
        ])
        truncated.removeLast()
        XCTAssertFalse(disk.loadNIB(Data(truncated)))
        XCTAssertFalse(disk.hasDisk)
    }

    func testNIBLoadRejectsDuplicateHalfTrackEntries() {
        let disk = GCRDisk()
        let duplicate = makeNIB(entries: [
            (nibHalfTrack: 2, density: 0x03, bytes: [UInt8](repeating: 0xAA, count: 0x2000)),
            (nibHalfTrack: 2, density: 0x02, bytes: [UInt8](repeating: 0x55, count: 0x2000)),
        ])

        XCTAssertFalse(disk.loadNIB(Data(duplicate)))
        XCTAssertFalse(disk.hasDisk)
    }

    func testNBZLoadDecompressesNIBPayloadAndPreservesFormat() {
        var firstTrack = [UInt8](repeating: 0xAA, count: 0x2000)
        firstTrack[123] = 0xFE
        let nib = makeNIB(entries: [
            (nibHalfTrack: 2, density: 0x13, bytes: firstTrack),
        ])
        let nbz = makeLiteralNBZ(from: nib, marker: 0xFE)
        let disk = GCRDisk()

        XCTAssertTrue(disk.loadNBZ(Data(nbz)))

        XCTAssertEqual(disk.image?.format, .nbz)
        XCTAssertEqual(disk.trackInfo(halfTrack: 0)?.bytes, firstTrack)
        XCTAssertEqual(disk.trackInfo(halfTrack: 0)?.speedZone, 3)
        XCTAssertEqual(disk.image?.capabilities.maxTrackSize, 0x2000)
        XCTAssertTrue(disk.image?.capabilities.preservesRawTrackLengths == true)
        XCTAssertTrue(disk.image?.capabilities.unsupportedFeatures.contains("P64 metadata") == true)
    }

    func testNBZLoadRejectsMalformedCompressedStreams() {
        let disk = GCRDisk()

        XCTAssertFalse(disk.loadNBZ(Data()))
        XCTAssertFalse(disk.loadNBZ(Data([0xFE, 0xFE])))
        XCTAssertFalse(disk.loadNBZ(Data([0xFE, 0x41, 0xFE, 0x02, 0x08])))
        XCTAssertFalse(disk.hasDisk)
    }

    func testNBZLoadRejectsDuplicateHalfTrackEntries() {
        let duplicate = makeNIB(entries: [
            (nibHalfTrack: 2, density: 0x03, bytes: [UInt8](repeating: 0xAA, count: 0x2000)),
            (nibHalfTrack: 2, density: 0x02, bytes: [UInt8](repeating: 0x55, count: 0x2000)),
        ])
        let nbz = makeLiteralNBZ(from: duplicate, marker: 0xFE)
        let disk = GCRDisk()

        XCTAssertFalse(disk.loadNBZ(Data(nbz)))
        XCTAssertFalse(disk.hasDisk)
    }

    func testP64LoadDecodesFluxPulsesIntoNativeGCRTrack() {
        let sourcePrefix: [UInt8] = [0x00, 0xA5, 0x3C, 0x7E]
        let p64 = makeP64(halfTrack: 0, gcrPrefix: sourcePrefix)
        let disk = GCRDisk()

        XCTAssertTrue(disk.loadP64(Data(p64)))

        let info = disk.trackInfo(halfTrack: 0)
        XCTAssertEqual(disk.image?.format, .p64)
        XCTAssertEqual(info?.bytes.prefix(sourcePrefix.count), sourcePrefix[...])
        XCTAssertEqual(info?.speedZone, 3)
        XCTAssertEqual(info?.bitLength, 61_539)
        XCTAssertEqual(info?.isNativeLowLevel, true)
        XCTAssertEqual(disk.image?.capabilities.nativeLowLevelTrackCount, 1)
        XCTAssertEqual(disk.image?.capabilities.maxTrackSize, 7_693)
        XCTAssertEqual(disk.image?.capabilities.preservesRawTrackLengths, true)
        XCTAssertTrue(disk.image?.capabilities.unsupportedFeatures.contains("Flux timing quantized to GCR bit cells") == true)
    }

    func testP64LoadAnnotatesWeakPulseStrengths() {
        let p64 = makeP64(
            halfTrack: 1,
            gcrPrefix: [0x00, 0x80],
            weakBitIndexes: [8]
        )
        let disk = GCRDisk()

        XCTAssertTrue(disk.loadP64(Data(p64)))

        let info = disk.trackInfo(halfTrack: 1)
        XCTAssertEqual(disk.image?.format, .p64)
        XCTAssertEqual(info?.bytes.prefix(2), [0x00, 0x80])
        XCTAssertEqual(info?.weakBitRanges.first, DiskImage.Track.WeakBitRange(startBit: 7, endBit: 9))
        XCTAssertEqual(disk.image?.capabilities.weakBitRangeCount, 1)
        XCTAssertEqual(disk.image?.capabilities.preservesWeakBitRanges, true)
    }

    func testP64LoadRejectsMalformedImages() {
        let disk = GCRDisk()

        XCTAssertFalse(disk.loadP64(Data()))
        XCTAssertFalse(disk.loadP64(Data(Array("P64-1541".utf8))))

        var missingDone = makeP64(halfTrack: 0, gcrPrefix: [0x00, 0x80])
        missingDone.removeLast(12)
        missingDone[16] = UInt8((missingDone.count - 24) & 0xFF)
        missingDone[17] = UInt8(((missingDone.count - 24) >> 8) & 0xFF)
        XCTAssertFalse(disk.loadP64(Data(missingDone)))
        XCTAssertFalse(disk.hasDisk)
    }

    func testP64LoadRejectsCRCAndUnsupportedSideMismatches() {
        let disk = GCRDisk()

        var badStreamCRC = makeP64(halfTrack: 0, gcrPrefix: [0x00, 0x80])
        badStreamCRC[20] ^= 0x01
        XCTAssertFalse(disk.loadP64(Data(badStreamCRC)))

        var badChunkCRC = makeP64(halfTrack: 0, gcrPrefix: [0x00, 0x80])
        badChunkCRC[32] ^= 0x01
        XCTAssertFalse(disk.loadP64(Data(badChunkCRC)))

        var doubleSided = makeP64(halfTrack: 0, gcrPrefix: [0x00, 0x80])
        doubleSided[12] |= 0x02
        XCTAssertFalse(disk.loadP64(Data(doubleSided)))

        var sideBChunk = makeP64(halfTrack: 0, gcrPrefix: [0x00, 0x80])
        sideBChunk[27] |= 0x80
        recomputeP64CRCs(&sideBChunk)
        XCTAssertFalse(disk.loadP64(Data(sideBChunk)))
        XCTAssertFalse(disk.hasDisk)
    }

    func testP64LoadRejectsDuplicateHalfTrackChunks() {
        let disk = GCRDisk()
        let duplicate = makeP64WithDuplicatedFirstTrackChunk(halfTrack: 0, gcrPrefix: [0x00, 0x80])

        XCTAssertFalse(disk.loadP64(Data(duplicate)))
        XCTAssertFalse(disk.hasDisk)
    }

    func testP64LoadRejectsChunksAfterDone() {
        let disk = GCRDisk()
        var trailing = makeP64(halfTrack: 0, gcrPrefix: [0x00, 0x80])
        trailing.append(contentsOf: Array("JUNK".utf8))
        appendLittleEndian32(0, to: &trailing)
        appendLittleEndian32(0, to: &trailing)
        let streamSize = littleEndian32(from: trailing, at: 16) + 12
        writeLittleEndian32(streamSize, into: &trailing, at: 16)
        recomputeP64CRCs(&trailing)

        XCTAssertFalse(disk.loadP64(Data(trailing)))
        XCTAssertFalse(disk.hasDisk)
    }

    func testG64LoadReportsDuplicateSectorHeaders() {
        let rawTrack = Self.g64HeaderBlock(track: 18, sector: 0)
            + [UInt8](repeating: 0x55, count: 8)
            + Self.g64HeaderBlock(track: 18, sector: 0)
            + [UInt8](repeating: 0x55, count: 8)
            + Self.g64HeaderBlock(track: 18, sector: 1)
        let g64 = makeSingleTrackG64(halfTrack: 34, rawTrack: rawTrack)
        let disk = GCRDisk()

        XCTAssertTrue(disk.loadG64(Data(g64)))

        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.duplicateSectorHeaderCount, 1)
        XCTAssertEqual(disk.image?.capabilities.duplicateSectorHeaderCount, 1)
        XCTAssertEqual(disk.image?.capabilities.hasDuplicateSectorHeaders, true)
    }

    func testG64LoadReportsNativeHalfTrackPreservation() {
        var g64 = [UInt8]()
        g64.append(contentsOf: Array("GCR-1541".utf8))
        g64.append(0x00)
        g64.append(84)
        g64.append(0x04)
        g64.append(0x00)

        let offsetTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))
        let speedTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))

        let rawTrack: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        let trackOffset = g64.count
        g64.append(UInt8(rawTrack.count & 0xFF))
        g64.append(UInt8(rawTrack.count >> 8))
        g64.append(contentsOf: rawTrack)

        let halfTrack = 35
        let offsetPos = offsetTableStart + halfTrack * 4
        g64[offsetPos] = UInt8(trackOffset & 0xFF)
        g64[offsetPos + 1] = UInt8((trackOffset >> 8) & 0xFF)
        g64[offsetPos + 2] = UInt8((trackOffset >> 16) & 0xFF)
        g64[offsetPos + 3] = UInt8((trackOffset >> 24) & 0xFF)

        let speedPos = speedTableStart + halfTrack * 4
        g64[speedPos] = 0x02

        let disk = GCRDisk()
        XCTAssertTrue(disk.loadG64(Data(g64)))

        XCTAssertEqual(disk.trackInfo(halfTrack: halfTrack)?.bytes, rawTrack)
        XCTAssertTrue(disk.image?.capabilities.preservesHalfTracks == true)
        XCTAssertTrue(disk.image?.capabilities.preservesRawTrackLengths == true)
        XCTAssertTrue(disk.image?.capabilities.preservesSpeedZones == true)
    }

    func testG64LoadPreservesPerByteSpeedZoneBlock() {
        var g64 = [UInt8]()
        g64.append(contentsOf: Array("GCR-1541".utf8))
        g64.append(0x00)
        g64.append(84)
        g64.append(0x08)
        g64.append(0x00)

        let offsetTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))
        let speedTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))

        let rawTrack: [UInt8] = [0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80]
        let trackOffset = g64.count
        g64.append(UInt8(rawTrack.count & 0xFF))
        g64.append(UInt8(rawTrack.count >> 8))
        g64.append(contentsOf: rawTrack)

        let speedBlockOffset = g64.count
        g64.append(0b00_01_10_11)
        g64.append(0b11_10_01_00)

        let halfTrack = 34
        let offsetPos = offsetTableStart + halfTrack * 4
        g64[offsetPos] = UInt8(trackOffset & 0xFF)
        g64[offsetPos + 1] = UInt8((trackOffset >> 8) & 0xFF)
        g64[offsetPos + 2] = UInt8((trackOffset >> 16) & 0xFF)
        g64[offsetPos + 3] = UInt8((trackOffset >> 24) & 0xFF)

        let speedPos = speedTableStart + halfTrack * 4
        g64[speedPos] = UInt8(speedBlockOffset & 0xFF)
        g64[speedPos + 1] = UInt8((speedBlockOffset >> 8) & 0xFF)
        g64[speedPos + 2] = UInt8((speedBlockOffset >> 16) & 0xFF)
        g64[speedPos + 3] = UInt8((speedBlockOffset >> 24) & 0xFF)

        let disk = GCRDisk()
        XCTAssertTrue(disk.loadG64(Data(g64)))

        let info = disk.trackInfo(halfTrack: halfTrack)
        XCTAssertEqual(info?.speedZoneMap, [0, 1, 2, 3, 3, 2, 1, 0])
        XCTAssertEqual(info?.speedZone, 0)
        XCTAssertEqual(disk.image?.capabilities.preservesSpeedZones, true)
        XCTAssertEqual(disk.image?.capabilities.preservesVariableSpeedZones, true)
        XCTAssertEqual(disk.image?.capabilities.variableSpeedZoneByteCount, 8)
    }

    func testG64LoadRejectsMalformedPerByteSpeedZoneBlock() {
        var g64 = makeSingleTrackG64(
            halfTrack: 34,
            rawTrack: [0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80]
        )
        let speedTableStart = 12 + 84 * 4
        let malformedSpeedBlockOffset = UInt32(g64.count - 1)
        writeLittleEndian32(malformedSpeedBlockOffset, into: &g64, at: speedTableStart + 34 * 4)

        let disk = GCRDisk()

        XCTAssertFalse(disk.loadG64(Data(g64)))
        XCTAssertFalse(disk.hasDisk)
    }

    func testG64LoadRejectsPerByteSpeedZoneBlockOverlaps() {
        var headerOverlap = makeSingleTrackG64(
            halfTrack: 34,
            rawTrack: [0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80]
        )
        let speedTableStart = 12 + 84 * 4
        writeLittleEndian32(4, into: &headerOverlap, at: speedTableStart + 34 * 4)
        XCTAssertFalse(GCRDisk().loadG64(Data(headerOverlap)))

        var trackOverlap = makeSingleTrackG64(
            halfTrack: 34,
            rawTrack: [0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80]
        )
        let trackOffset = Int(littleEndian32(from: trackOverlap, at: 12 + 34 * 4))
        writeLittleEndian32(UInt32(trackOffset + 2), into: &trackOverlap, at: speedTableStart + 34 * 4)
        XCTAssertFalse(GCRDisk().loadG64(Data(trackOverlap)))
    }

    func testG64LoadRejectsOverlappingTrackPayloads() {
        var g64 = makeSingleTrackG64(
            halfTrack: 34,
            rawTrack: [0x10, 0x20, 0x30, 0x40]
        )
        let trackOffset = littleEndian32(from: g64, at: 12 + 34 * 4)
        writeLittleEndian32(trackOffset, into: &g64, at: 12 + 35 * 4)

        let disk = GCRDisk()

        XCTAssertFalse(disk.loadG64(Data(g64)))
        XCTAssertFalse(disk.hasDisk)
    }

    func testExportedG64ImagePreservesModifiedNativeTrackBytesAndSpeedMap() throws {
        var g64 = [UInt8]()
        g64.append(contentsOf: Array("GCR-1541".utf8))
        g64.append(0x00)
        g64.append(84)
        g64.append(0x08)
        g64.append(0x00)

        let offsetTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))
        let speedTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))

        let rawTrack: [UInt8] = [0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80]
        let trackOffset = g64.count
        g64.append(UInt8(rawTrack.count & 0xFF))
        g64.append(UInt8(rawTrack.count >> 8))
        g64.append(contentsOf: rawTrack)

        let speedBlockOffset = g64.count
        g64.append(0b00_01_10_11)
        g64.append(0b11_10_01_00)

        let halfTrack = 34
        let offsetPos = offsetTableStart + halfTrack * 4
        g64[offsetPos] = UInt8(trackOffset & 0xFF)
        g64[offsetPos + 1] = UInt8((trackOffset >> 8) & 0xFF)
        g64[offsetPos + 2] = UInt8((trackOffset >> 16) & 0xFF)
        g64[offsetPos + 3] = UInt8((trackOffset >> 24) & 0xFF)

        let speedPos = speedTableStart + halfTrack * 4
        g64[speedPos] = UInt8(speedBlockOffset & 0xFF)
        g64[speedPos + 1] = UInt8((speedBlockOffset >> 8) & 0xFF)
        g64[speedPos + 2] = UInt8((speedBlockOffset >> 16) & 0xFF)
        g64[speedPos + 3] = UInt8((speedBlockOffset >> 24) & 0xFF)

        let disk = GCRDisk()
        XCTAssertTrue(disk.loadG64(Data(g64)))
        disk.writeProtected = false
        XCTAssertTrue(disk.writeByte(0xA5, halfTrack: halfTrack, byteIndex: 2))

        let exported = try XCTUnwrap(disk.exportedG64Image)
        let reloaded = GCRDisk()
        XCTAssertTrue(reloaded.loadG64(exported))

        XCTAssertEqual(reloaded.trackInfo(halfTrack: halfTrack)?.bytes, [0x10, 0x20, 0xA5, 0x40, 0x50, 0x60, 0x70, 0x80])
        XCTAssertEqual(reloaded.trackInfo(halfTrack: halfTrack)?.speedZoneMap, [0, 1, 2, 3, 3, 2, 1, 0])
        XCTAssertEqual(reloaded.image?.capabilities.preservesVariableSpeedZones, true)
        XCTAssertTrue(disk.hasUnsavedLowLevelWrites)
        disk.markLowLevelWritesSaved()
        XCTAssertFalse(disk.hasUnsavedLowLevelWrites)
    }

    func testDiskImageWithWeakBitRangesDoesNotReportWeakBitsUnsupported() {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [0x00, 0x00],
            speedZone: 2,
            weakBitRanges: [DiskImage.Track.WeakBitRange(startBit: 0, endBit: 15)],
            isNativeLowLevel: true
        )
        let image = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 2)

        XCTAssertFalse(image.capabilities.unsupportedFeatures.contains("Weak/random bits"))
        XCTAssertTrue(image.capabilities.unsupportedFeatures.contains("Flux-level timing"))
        XCTAssertEqual(image.capabilities.weakBitRangeCount, 1)
        XCTAssertEqual(image.capabilities.weakBitTotalBitCount, 16)
        XCTAssertEqual(image.capabilities.preservesWeakBitRanges, true)
    }

    func testExportedG64PreservesWeakBitAnnotationsInSwift64Extension() throws {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [0xAA, 0x55],
            speedZone: 2,
            weakBitRanges: [DiskImage.Track.WeakBitRange(startBit: 0, endBit: 7)],
            isNativeLowLevel: true
        )
        let disk = GCRDisk()
        disk.tracks = tracks.map { $0?.bytes }
        disk.trackInfos = tracks
        disk.image = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 2)

        let exported = try XCTUnwrap(disk.exportedG64Image)
        let reloaded = GCRDisk()
        XCTAssertTrue(reloaded.loadG64(exported))

        XCTAssertEqual(disk.image?.capabilities.weakBitRangeCount, 1)
        XCTAssertEqual(disk.image?.capabilities.preservesWeakBitRanges, true)
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 34)?.weakBitRanges, [
            DiskImage.Track.WeakBitRange(startBit: 0, endBit: 7),
        ])
        XCTAssertEqual(reloaded.image?.capabilities.weakBitRangeCount, 1)
        XCTAssertEqual(reloaded.image?.capabilities.preservesWeakBitRanges, true)
    }

    func testSetWeakBitRangesAnnotatesLoadedTrackAndUpdatesCapabilities() {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [0x00, 0x00],
            speedZone: 2,
            isNativeLowLevel: true
        )
        let disk = GCRDisk()
        let image = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 2)
        disk.tracks = image.tracks.map { $0?.bytes }
        disk.trackInfos = image.tracks
        disk.image = image

        XCTAssertTrue(disk.setWeakBitRanges(
            [DiskImage.Track.WeakBitRange(startBit: 0, endBit: 15)],
            forHalfTrack: 34
        ))

        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.weakBitRanges, [
            DiskImage.Track.WeakBitRange(startBit: 0, endBit: 15),
        ])
        XCTAssertFalse(disk.image?.capabilities.unsupportedFeatures.contains("Weak/random bits") == true)
        XCTAssertEqual(disk.image?.capabilities.weakBitRangeCount, 1)
        XCTAssertEqual(disk.image?.capabilities.weakBitTotalBitCount, 16)
        XCTAssertEqual(disk.image?.capabilities.preservesWeakBitRanges, true)
    }

    func testSetWeakBitRangesRejectsMissingOrOutOfRangeTracks() {
        let disk = GCRDisk()

        XCTAssertFalse(disk.setWeakBitRanges(
            [DiskImage.Track.WeakBitRange(startBit: 0, endBit: 15)],
            forHalfTrack: 34
        ))

        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [0x00],
            speedZone: 2,
            isNativeLowLevel: true
        )
        let image = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 1)
        disk.tracks = image.tracks.map { $0?.bytes }
        disk.trackInfos = image.tracks
        disk.image = image
        XCTAssertFalse(disk.setWeakBitRanges(
            [DiskImage.Track.WeakBitRange(startBit: 0, endBit: 8)],
            forHalfTrack: 34
        ))
        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.weakBitRanges, [])
    }

    func testWritableTrackByteUpdatesLowLevelImageAndDirtyFlag() {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [0x00, 0x11, 0x22],
            speedZone: 2,
            weakBitRanges: [DiskImage.Track.WeakBitRange(startBit: 8, endBit: 23)],
            isNativeLowLevel: true
        )
        let disk = GCRDisk()
        disk.tracks = tracks.map { $0?.bytes }
        disk.trackInfos = tracks
        disk.image = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 3)
        disk.writeProtected = false

        XCTAssertTrue(disk.writeByte(0xA5, halfTrack: 34, byteIndex: 1))

        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.bytes, [0x00, 0xA5, 0x22])
        XCTAssertEqual(disk.tracks[34], [0x00, 0xA5, 0x22])
        XCTAssertEqual(disk.image?.tracks[34]?.bytes, [0x00, 0xA5, 0x22])
        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.weakBitRanges, [
            DiskImage.Track.WeakBitRange(startBit: 16, endBit: 23),
        ])
        XCTAssertTrue(disk.hasUnsavedLowLevelWrites)
    }

    func testByteWriteAnnotatesWrittenByteWithActiveSpeedZone() throws {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [0x00, 0x11, 0x22, 0x33],
            speedZone: 2,
            isNativeLowLevel: true
        )
        let disk = GCRDisk()
        disk.tracks = tracks.map { $0?.bytes }
        disk.trackInfos = tracks
        disk.image = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 4)
        disk.writeProtected = false

        XCTAssertTrue(disk.writeByte(0xA5, halfTrack: 34, byteIndex: 1, speedZone: 0))

        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.bytes, [0x00, 0xA5, 0x22, 0x33])
        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.speedZoneMap, [2, 0, 2, 2])
        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.speedZone, 2)

        let exported = try XCTUnwrap(disk.exportedG64Image)
        let reloaded = GCRDisk()
        XCTAssertTrue(reloaded.loadG64(exported))
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 34)?.bytes, [0x00, 0xA5, 0x22, 0x33])
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 34)?.speedZoneMap, [2, 0, 2, 2])
    }

    func testWriteByteAtBitPositionWrapsAndHonorsWriteProtect() {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[2] = DiskImage.Track(
            halfTrack: 2,
            bytes: [0x10, 0x20],
            speedZone: 3,
            isNativeLowLevel: false
        )
        let disk = GCRDisk()
        disk.tracks = tracks.map { $0?.bytes }
        disk.trackInfos = tracks
        disk.image = DiskImage(format: .d64, tracks: tracks)

        XCTAssertFalse(disk.writeByteAtBitPosition(0x99, halfTrack: 2, bitPosition: 16))

        disk.writeProtected = false
        XCTAssertTrue(disk.writeByteAtBitPosition(0x99, halfTrack: 2, bitPosition: 16))
        XCTAssertEqual(disk.trackInfo(halfTrack: 2)?.bytes, [0x99, 0x20])
        XCTAssertEqual(disk.image?.maxTrackSize, nil)
    }

    func testWriteByteAtUnalignedBitPositionSplicesAcrossBytesAndSplitsWeakRanges() {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[2] = DiskImage.Track(
            halfTrack: 2,
            bytes: [0x00, 0x00],
            speedZone: 3,
            weakBitRanges: [DiskImage.Track.WeakBitRange(startBit: 0, endBit: 15)],
            isNativeLowLevel: false
        )
        let disk = GCRDisk()
        disk.tracks = tracks.map { $0?.bytes }
        disk.trackInfos = tracks
        disk.image = DiskImage(format: .d64, tracks: tracks)
        disk.writeProtected = false

        XCTAssertTrue(disk.writeByteAtBitPosition(0b1010_1010, halfTrack: 2, bitPosition: 4))

        XCTAssertEqual(disk.trackInfo(halfTrack: 2)?.bytes, [0x0A, 0xA0])
        XCTAssertEqual(disk.trackInfo(halfTrack: 2)?.weakBitRanges, [
            DiskImage.Track.WeakBitRange(startBit: 0, endBit: 3),
            DiskImage.Track.WeakBitRange(startBit: 12, endBit: 15),
        ])
    }

    func testUnalignedByteWriteAnnotatesTouchedBytesWithActiveSpeedZone() throws {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [0x00, 0x00, 0x00, 0x00],
            speedZone: 3,
            isNativeLowLevel: true
        )
        let disk = GCRDisk()
        disk.tracks = tracks.map { $0?.bytes }
        disk.trackInfos = tracks
        disk.image = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 4)
        disk.writeProtected = false

        XCTAssertTrue(disk.writeByteAtBitPosition(0b1010_1010, halfTrack: 34, bitPosition: 4, speedZone: 1))

        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.bytes, [0x0A, 0xA0, 0x00, 0x00])
        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.speedZoneMap, [1, 1, 3, 3])
        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.speedZone, 1)

        let exported = try XCTUnwrap(disk.exportedG64Image)
        let reloaded = GCRDisk()
        XCTAssertTrue(reloaded.loadG64(exported))
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 34)?.bytes, [0x0A, 0xA0, 0x00, 0x00])
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 34)?.speedZoneMap, [1, 1, 3, 3])
    }

    func testWriteByteAtUnalignedBitPositionWrapsAroundTrackEnd() {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[2] = DiskImage.Track(
            halfTrack: 2,
            bytes: [0x00, 0x00],
            speedZone: 3,
            isNativeLowLevel: false
        )
        let disk = GCRDisk()
        disk.tracks = tracks.map { $0?.bytes }
        disk.trackInfos = tracks
        disk.image = DiskImage(format: .d64, tracks: tracks)
        disk.writeProtected = false

        XCTAssertTrue(disk.writeByteAtBitPosition(0b0011_1100, halfTrack: 2, bitPosition: 12))

        XCTAssertEqual(disk.trackInfo(halfTrack: 2)?.bytes, [0xC0, 0x03])
    }

    func testWriteBitAtBitPositionUpdatesSingleBitAndSplitsWeakRange() {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[2] = DiskImage.Track(
            halfTrack: 2,
            bytes: [0x00],
            speedZone: 3,
            weakBitRanges: [DiskImage.Track.WeakBitRange(startBit: 0, endBit: 7)],
            isNativeLowLevel: false
        )
        let disk = GCRDisk()
        disk.tracks = tracks.map { $0?.bytes }
        disk.trackInfos = tracks
        disk.image = DiskImage(format: .d64, tracks: tracks)
        disk.writeProtected = false

        XCTAssertTrue(disk.writeBitAtBitPosition(true, halfTrack: 2, bitPosition: 3))

        XCTAssertEqual(disk.trackInfo(halfTrack: 2)?.bytes, [0x10])
        XCTAssertEqual(disk.trackInfo(halfTrack: 2)?.weakBitRanges, [
            DiskImage.Track.WeakBitRange(startBit: 0, endBit: 2),
            DiskImage.Track.WeakBitRange(startBit: 4, endBit: 7),
        ])
        XCTAssertTrue(disk.hasUnsavedLowLevelWrites)
    }

    func testSingleBitWriteUpdatesNativeG64ExportWithoutRebuildingMountedImagePerBit() throws {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [0x00],
            speedZone: 2,
            isNativeLowLevel: true
        )
        let disk = GCRDisk()
        disk.tracks = tracks.map { $0?.bytes }
        disk.trackInfos = tracks
        disk.image = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 1)
        disk.writeProtected = false

        XCTAssertTrue(disk.writeBitAtBitPosition(true, halfTrack: 34, bitPosition: 3))

        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.bytes, [0x10])
        XCTAssertEqual(disk.tracks[34], [0x10])
        XCTAssertEqual(disk.image?.tracks[34]?.bytes, [0x00])

        let exported = try XCTUnwrap(disk.exportedG64Image)
        let reloaded = GCRDisk()
        XCTAssertTrue(reloaded.loadG64(exported))
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 34)?.bytes, [0x10])
        XCTAssertTrue(disk.hasUnsavedLowLevelWrites)
    }

    func testSingleBitWriteAnnotatesWrittenByteWithActiveSpeedZone() throws {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [0x00, 0x00, 0x00, 0x00],
            speedZone: 2,
            isNativeLowLevel: true
        )
        let disk = GCRDisk()
        disk.tracks = tracks.map { $0?.bytes }
        disk.trackInfos = tracks
        disk.image = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 4)
        disk.writeProtected = false

        XCTAssertTrue(disk.writeBitAtBitPosition(true, halfTrack: 34, bitPosition: 19, speedZone: 3))

        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.speedZoneMap, [2, 2, 3, 2])
        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.speedZone, 2)

        let exported = try XCTUnwrap(disk.exportedG64Image)
        let reloaded = GCRDisk()
        XCTAssertTrue(reloaded.loadG64(exported))
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 34)?.speedZoneMap, [2, 2, 3, 2])
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 34)?.bytes[2], 0x10)
    }

    func testAddWeakBitRangeMergesAndWrapsAroundTrackEnd() {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[2] = DiskImage.Track(
            halfTrack: 2,
            bytes: [0x00, 0x00],
            speedZone: 3,
            weakBitRanges: [DiskImage.Track.WeakBitRange(startBit: 2, endBit: 4)],
            isNativeLowLevel: true
        )
        let disk = GCRDisk()
        disk.tracks = tracks.map { $0?.bytes }
        disk.trackInfos = tracks
        disk.image = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 2)

        XCTAssertTrue(disk.addWeakBitRange(startBit: 14, bitCount: 5, forHalfTrack: 2))

        XCTAssertEqual(disk.trackInfo(halfTrack: 2)?.weakBitRanges, [
            DiskImage.Track.WeakBitRange(startBit: 0, endBit: 4),
            DiskImage.Track.WeakBitRange(startBit: 14, endBit: 15),
        ])
        XCTAssertTrue(disk.hasUnsavedLowLevelWrites)
    }

    func testEnsureWritableTrackCreatesNativeG64TrackForLowLevelFormatting() {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [0xFF, 0xFF],
            speedZone: 2,
            isNativeLowLevel: true
        )
        let disk = GCRDisk()
        disk.tracks = tracks.map { $0?.bytes }
        disk.trackInfos = tracks
        disk.image = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 2)

        XCTAssertTrue(disk.ensureWritableTrack(halfTrack: 35, speedZone: 3))

        let created = disk.trackInfo(halfTrack: 35)
        XCTAssertEqual(created?.bytes.count, GCRDisk.trackLengths[3])
        XCTAssertEqual(created?.speedZone, 3)
        XCTAssertEqual(created?.isNativeLowLevel, true)
        XCTAssertEqual(created?.bytes.first, 0x55)
        XCTAssertTrue(disk.hasUnsavedLowLevelWrites)
        XCTAssertEqual(disk.image?.maxTrackSize, GCRDisk.trackLengths[3])
    }

    func testEnsureWritableTrackCreatesNativeNIBHalfTrackForLowLevelFormatting() throws {
        let nib = makeNIB(entries: [
            (nibHalfTrack: 2, density: 0x13, bytes: [UInt8](repeating: 0xAA, count: 0x2000)),
        ])
        let disk = GCRDisk()
        XCTAssertTrue(disk.loadNIB(Data(nib)))

        XCTAssertTrue(disk.ensureWritableTrack(halfTrack: 1, speedZone: 1, fillByte: 0x33))

        let created = try XCTUnwrap(disk.trackInfo(halfTrack: 1))
        XCTAssertEqual(created.bytes.count, GCRDisk.trackLengths[1])
        XCTAssertEqual(created.speedZone, 1)
        XCTAssertEqual(created.bytes.first, 0x33)
        XCTAssertTrue(created.isNativeLowLevel)
        XCTAssertTrue(disk.hasUnsavedLowLevelWrites)
        XCTAssertEqual(disk.image?.format, .nib)
        XCTAssertEqual(disk.image?.maxTrackSize, 0x2000)

        let exported = try XCTUnwrap(disk.exportedG64Image)
        let reloaded = GCRDisk()
        XCTAssertTrue(reloaded.loadG64(exported))
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 1)?.bytes.count, GCRDisk.trackLengths[1])
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 1)?.speedZone, 1)
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 1)?.bytes.first, 0x33)
    }

    func testEnsureWritableTrackCreatesNativeP64HalfTrackForLowLevelFormatting() throws {
        let p64 = makeP64(halfTrack: 0, gcrPrefix: [0x00, 0xA5])
        let disk = GCRDisk()
        XCTAssertTrue(disk.loadP64(Data(p64)))

        XCTAssertTrue(disk.ensureWritableTrack(halfTrack: 1, speedZone: 0, fillByte: 0x44))

        let created = try XCTUnwrap(disk.trackInfo(halfTrack: 1))
        XCTAssertEqual(created.bytes.count, GCRDisk.trackLengths[0])
        XCTAssertEqual(created.speedZone, 0)
        XCTAssertEqual(created.bytes.first, 0x44)
        XCTAssertTrue(created.isNativeLowLevel)
        XCTAssertTrue(disk.hasUnsavedLowLevelWrites)
        XCTAssertEqual(disk.image?.format, .p64)
        XCTAssertEqual(disk.image?.maxTrackSize, 7_693)
    }

    func testEnsureWritableTrackRejectsD64AndOutOfRangeHalfTracks() {
        let disk = GCRDisk()
        XCTAssertTrue(disk.loadD64(makeBlankD64()))

        XCTAssertFalse(disk.ensureWritableTrack(halfTrack: 1, speedZone: 3))
        XCTAssertFalse(disk.ensureWritableTrack(halfTrack: GCRDisk.maxHalfTracks, speedZone: 3))
    }

    func testDecodedD64ImagePatchesCleanlyDecodedLowLevelSectorWrites() throws {
        var base = [UInt8](makeBlankD64())
        let geometry = try XCTUnwrap(DiskDrive.d64Geometry(forByteCount: base.count))
        let sectorOffset = geometry.trackOffsets[1]
        base[sectorOffset + 2] = 0x11

        let disk = GCRDisk()
        XCTAssertTrue(disk.loadD64(Data(base)))

        var sectors = trackSectors(from: base, track: 1, geometry: geometry)
        sectors[0][2] = 0x7E
        let replacementTrack = disk.encodeTrack(
            trackNum: 1,
            sectors: sectors,
            diskID: (0x41, 0x42)
        )
        try applyTrackByteDiffs(to: disk, halfTrack: 0, replacement: replacementTrack)

        let decoded = try XCTUnwrap(disk.decodedD64Image(patching: Data(base)))
        let patched = [UInt8](decoded.image)

        XCTAssertGreaterThan(decoded.decodedSectorCount, 0)
        XCTAssertEqual(decoded.changedSectorCount, 1)
        XCTAssertTrue(decoded.incompleteTracks.isEmpty)
        XCTAssertEqual(patched[sectorOffset + 2], 0x7E)
        XCTAssertTrue(disk.hasUnsavedLowLevelWrites)
    }

    func testDecodedD64ImageRejectsNativeG64Images() {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[0] = DiskImage.Track(
            halfTrack: 0,
            bytes: [0xFF, 0x55],
            speedZone: 3,
            isNativeLowLevel: true
        )
        let disk = GCRDisk()
        disk.tracks = tracks.map { $0?.bytes }
        disk.trackInfos = tracks
        disk.image = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 2)

        XCTAssertNil(disk.decodedD64Image(patching: makeBlankD64()))
    }

    func testSetSpeedZoneRangesAnnotatesLoadedTrackAndUpdatesCapabilities() {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [UInt8](repeating: 0x00, count: 8),
            speedZone: 2,
            isNativeLowLevel: true
        )
        let disk = GCRDisk()
        let image = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 8)
        disk.tracks = image.tracks.map { $0?.bytes }
        disk.trackInfos = image.tracks
        disk.image = image

        XCTAssertTrue(disk.setSpeedZoneRanges([
            DiskImage.Track.SpeedZoneRange(startByte: 0, endByte: 1, zone: 0),
            DiskImage.Track.SpeedZoneRange(startByte: 6, endByte: 7, zone: 3),
        ], forHalfTrack: 34))

        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.speedZoneMap, [0, 0, 2, 2, 2, 2, 3, 3])
        XCTAssertEqual(disk.trackInfo(halfTrack: 34)?.speedZone, 2)
        XCTAssertEqual(disk.image?.capabilities.variableSpeedZoneByteCount, 8)
        XCTAssertEqual(disk.image?.capabilities.preservesVariableSpeedZones, true)
    }

    func testSetSpeedZoneRangesRejectsMissingOrOutOfRangeTracks() {
        let disk = GCRDisk()

        XCTAssertFalse(disk.setSpeedZoneRanges([
            DiskImage.Track.SpeedZoneRange(startByte: 0, endByte: 1, zone: 1),
        ], forHalfTrack: 34))

        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [0x00],
            speedZone: 2,
            isNativeLowLevel: true
        )
        let image = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 1)
        disk.tracks = image.tracks.map { $0?.bytes }
        disk.trackInfos = image.tracks
        disk.image = image

        XCTAssertFalse(disk.setSpeedZoneRanges([
            DiskImage.Track.SpeedZoneRange(startByte: 0, endByte: 1, zone: 1),
        ], forHalfTrack: 34))
        XCTAssertFalse(disk.setSpeedZoneRanges([
            DiskImage.Track.SpeedZoneRange(startByte: 0, endByte: 0, zone: 4),
        ], forHalfTrack: 34))
        XCTAssertNil(disk.trackInfo(halfTrack: 34)?.speedZoneMap)
    }

    func testD64LoadCreatesSyntheticLowLevelTracks() {
        let d64 = makeBlankD64()
        let disk = GCRDisk()

        XCTAssertTrue(disk.loadD64(d64))

        let info = disk.trackInfo(halfTrack: 34)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.speedZone, GCRDisk.speedZone(for: 18))
        XCTAssertEqual(info?.isNativeLowLevel, false)
        XCTAssertEqual(disk.image?.format, .d64)
        XCTAssertFalse(disk.hasNativeLowLevelImage)
        XCTAssertEqual(disk.image?.capabilities.syntheticGCRTrackCount, 35)
        XCTAssertTrue(disk.image?.capabilities.hasSyntheticGCR == true)
        XCTAssertFalse(disk.image?.capabilities.preservesVariableSpeedZones == true)
        XCTAssertFalse(disk.image?.capabilities.preservesSectorErrorInfo == true)
        XCTAssertTrue(disk.image?.capabilities.unsupportedFeatures.contains("Native copy-protection bitstream") == true)
    }

    func testLowLevelLoadsSetWriteProtectDefaultsByMediaFormat() {
        let disk = GCRDisk()

        XCTAssertTrue(disk.loadD64(makeBlankD64()))
        XCTAssertFalse(disk.writeProtected)

        let g64 = makeSingleTrackG64(halfTrack: 34, rawTrack: [0x55, 0xAA])
        XCTAssertTrue(disk.loadG64(Data(g64)))
        XCTAssertTrue(disk.writeProtected)

        let writableP64 = makeP64(halfTrack: 0, gcrPrefix: [0x00, 0xA5], flags: 0)
        XCTAssertTrue(disk.loadP64(Data(writableP64)))
        XCTAssertFalse(disk.writeProtected)

        let protectedP64 = makeP64(halfTrack: 0, gcrPrefix: [0x00, 0xA5], flags: 1)
        XCTAssertTrue(disk.loadP64(Data(protectedP64)))
        XCTAssertTrue(disk.writeProtected)
    }

    func testD64LoadPreservesSectorErrorTableMetadata() throws {
        var d64 = [UInt8](makeBlankD64())
        d64.append(contentsOf: [UInt8](repeating: 0x01, count: 683))
        let geometry = try XCTUnwrap(DiskDrive.d64Geometry(forByteCount: d64.count))
        let errorOffset = try XCTUnwrap(geometry.errorInfoOffset)
        d64[errorOffset] = 0x05
        d64[errorOffset + 358] = 0x0B

        let disk = GCRDisk()
        XCTAssertTrue(disk.loadD64(Data(d64)))

        XCTAssertEqual(disk.image?.sectorErrorCodes?.count, 683)
        XCTAssertEqual(disk.image?.sectorErrorCodes?.first, 0x05)
        XCTAssertEqual(disk.image?.sectorErrorCodes?[358], 0x0B)
        XCTAssertTrue(disk.image?.capabilities.preservesSectorErrorInfo == true)
        XCTAssertEqual(disk.image?.capabilities.sectorErrorCodeCount, 683)
        XCTAssertEqual(disk.image?.capabilities.nonDefaultSectorErrorCodeCount, 2)
    }

    func testD64SectorDataChecksumErrorCorruptsSyntheticGCRDataBlock() throws {
        var d64 = [UInt8](makeBlankD64())
        d64.append(contentsOf: [UInt8](repeating: 0x01, count: 683))
        let geometry = try XCTUnwrap(DiskDrive.d64Geometry(forByteCount: d64.count))
        let errorOffset = try XCTUnwrap(geometry.errorInfoOffset)
        d64[errorOffset] = 23

        let disk = GCRDisk()
        XCTAssertTrue(disk.loadD64(Data(d64)))
        let track1 = try XCTUnwrap(disk.trackInfo(halfTrack: 0)?.bytes)
        let decoded = G64Parser.decodeSectors(from: track1, track: 1, expectedSectors: 21)

        XCTAssertFalse(decoded.contains { $0.0 == 0 })
        XCTAssertTrue(decoded.contains { $0.0 == 1 })
    }

    func testD64SectorHeaderChecksumErrorCorruptsSyntheticGCRHeaderBlock() throws {
        var d64 = [UInt8](makeBlankD64())
        d64.append(contentsOf: [UInt8](repeating: 0x01, count: 683))
        let geometry = try XCTUnwrap(DiskDrive.d64Geometry(forByteCount: d64.count))
        let errorOffset = try XCTUnwrap(geometry.errorInfoOffset)
        d64[errorOffset] = 27

        let disk = GCRDisk()
        XCTAssertTrue(disk.loadD64(Data(d64)))
        let track1 = try XCTUnwrap(disk.trackInfo(halfTrack: 0)?.bytes)
        let decoded = G64Parser.decodeSectors(from: track1, track: 1, expectedSectors: 21)

        XCTAssertFalse(decoded.contains { $0.0 == 0 })
        XCTAssertTrue(decoded.contains { $0.0 == 1 })
    }

    func testD64SectorHeaderNotFoundErrorSuppressesSyntheticGCRSector() throws {
        let decoded = try decodedTrack1Sectors(d64ErrorCode: 20)

        XCTAssertFalse(decoded.contains { $0.0 == 0 })
        XCTAssertTrue(decoded.contains { $0.0 == 1 })
    }

    func testD64SectorNoSyncErrorSuppressesSyntheticGCRSector() throws {
        let decoded = try decodedTrack1Sectors(d64ErrorCode: 21)

        XCTAssertFalse(decoded.contains { $0.0 == 0 })
        XCTAssertTrue(decoded.contains { $0.0 == 1 })
    }

    func testD64SectorDataBlockNotPresentErrorSuppressesSyntheticGCRSector() throws {
        let decoded = try decodedTrack1Sectors(d64ErrorCode: 22)

        XCTAssertFalse(decoded.contains { $0.0 == 0 })
        XCTAssertTrue(decoded.contains { $0.0 == 1 })
    }

    func testD64SectorByteDecodeErrorCorruptsSyntheticGCRDataBytes() throws {
        let decoded = try decodedTrack1Sectors(d64ErrorCode: 24)

        XCTAssertFalse(decoded.contains { $0.0 == 0 })
        XCTAssertTrue(decoded.contains { $0.0 == 1 })
    }

    func testD64SectorLongDataBlockErrorExtendsSyntheticGCRDataBlock() throws {
        let track1 = try syntheticTrack1(d64ErrorCode: 28)
        let dataBlockOffset = 5 + 10 + 9 + 5
        let decodedDataBlock = G64Parser.decodeGCRBlock(
            Array(track1[dataBlockOffset..<(dataBlockOffset + 330)]),
            count: 264
        )
        let decodedSectors = G64Parser.decodeSectors(from: track1, track: 1, expectedSectors: 21)

        XCTAssertEqual(decodedDataBlock[0], 0x07)
        XCTAssertEqual(decodedDataBlock[257], 0xFF)
        XCTAssertEqual(decodedDataBlock[258], 0x00)
        XCTAssertFalse(decodedSectors.contains { $0.0 == 0 })
        XCTAssertTrue(decodedSectors.contains { $0.0 == 1 })
    }

    func testD64SectorDiskIDMismatchErrorWritesMismatchedSyntheticGCRHeaderID() throws {
        let track1 = try syntheticTrack1(d64ErrorCode: 29)
        let header = G64Parser.decodeGCRBlock(Array(track1[5..<15]), count: 8)
        let decoded = G64Parser.decodeSectors(from: track1, track: 1, expectedSectors: 21)

        XCTAssertEqual(header[0], 0x08)
        XCTAssertEqual(header[2], 0)
        XCTAssertEqual(header[3], 1)
        XCTAssertEqual(header[4], 0xBD)
        XCTAssertEqual(header[5], 0xBE)
        XCTAssertTrue(decoded.contains { $0.0 == 0 })
    }

    func testUnknownD64SectorErrorCodePreservesMetadataWithoutCorruptingSyntheticGCR() throws {
        let decoded = try decodedTrack1Sectors(d64ErrorCode: 0x0F)

        XCTAssertTrue(decoded.contains { $0.0 == 0 })
        XCTAssertTrue(decoded.contains { $0.0 == 1 })
    }

    func testExtendedD64LoadPreservesTrack41SectorErrorTableMetadata() throws {
        var d64 = [UInt8](makeBlankD64())
        d64.append(contentsOf: [UInt8](repeating: 0, count: 200704 - d64.count))
        d64.append(contentsOf: [UInt8](repeating: 0x01, count: 784))
        let geometry = try XCTUnwrap(DiskDrive.d64Geometry(forByteCount: d64.count))
        let errorOffset = try XCTUnwrap(geometry.errorInfoOffset)
        d64[errorOffset + 783] = 0x0F

        let disk = GCRDisk()
        XCTAssertTrue(disk.loadD64(Data(d64)))

        XCTAssertEqual(disk.image?.sectorErrorCodes?.count, 784)
        XCTAssertEqual(disk.image?.sectorErrorCodes?[783], 0x0F)
        XCTAssertTrue(disk.image?.capabilities.preservesSectorErrorInfo == true)
        XCTAssertEqual(disk.image?.capabilities.sectorErrorCodeCount, 784)
        XCTAssertEqual(disk.image?.capabilities.nonDefaultSectorErrorCodeCount, 1)
    }

    func testExtendedD64LoadCreatesSyntheticLowLevelTracks() {
        var image = [UInt8](makeBlankD64())
        image.append(contentsOf: [UInt8](repeating: 0, count: 200704 - image.count))

        let disk = GCRDisk()
        XCTAssertTrue(disk.loadD64(Data(image)))
        XCTAssertNotNil(disk.trackInfo(halfTrack: 34))
    }

    func testExtendedD64LoadCreatesSyntheticLowLevelTracksBeyond35() {
        var image = [UInt8](makeBlankD64())
        image.append(contentsOf: [UInt8](repeating: 0, count: 205312 - image.count))

        let disk = GCRDisk()
        XCTAssertTrue(disk.loadD64(Data(image)))

        let track42 = disk.trackInfo(halfTrack: 82)
        XCTAssertNotNil(track42)
        XCTAssertEqual(track42?.speedZone, GCRDisk.speedZone(for: 42))
        XCTAssertEqual(track42?.isNativeLowLevel, false)
        XCTAssertEqual(disk.image?.capabilities.syntheticGCRTrackCount, 42)
    }

    func testC64DataMountPreservesG64FormatFromFilename() {
        var g64 = [UInt8]()
        g64.append(contentsOf: Array("GCR-1541".utf8))
        g64.append(0x00)
        g64.append(84)
        g64.append(0x04)
        g64.append(0x00)

        let offsetTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))
        let speedTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))

        let rawTrack: [UInt8] = [0xFF, 0xFF, 0x52, 0xA5]
        let trackOffset = g64.count
        g64.append(UInt8(rawTrack.count & 0xFF))
        g64.append(UInt8(rawTrack.count >> 8))
        g64.append(contentsOf: rawTrack)

        let halfTrack = 34
        let offsetPos = offsetTableStart + halfTrack * 4
        g64[offsetPos] = UInt8(trackOffset & 0xFF)
        g64[offsetPos + 1] = UInt8((trackOffset >> 8) & 0xFF)
        g64[offsetPos + 2] = UInt8((trackOffset >> 16) & 0xFF)
        g64[offsetPos + 3] = UInt8((trackOffset >> 24) & 0xFF)

        let speedPos = speedTableStart + halfTrack * 4
        g64[speedPos] = 0x02

        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(Data(g64), fileName: "selected.g64"))
        XCTAssertEqual(c64.emulationStatus.mountedDiskName, "selected.g64")
        XCTAssertEqual(c64.emulationStatus.mountedDiskFormat, .g64)
        XCTAssertNil(c64.emulationStatus.highLevelDiskFormat)
        XCTAssertFalse(c64.emulationStatus.diskHasUnsavedChanges)
        XCTAssertFalse(c64.emulationStatus.canExportModifiedD64)
        XCTAssertTrue(c64.emulationStatus.canExportModifiedG64)
        XCTAssertFalse(c64.diskDrive.isMounted)
        XCTAssertEqual(c64.emulationStatus.drive.hasNativeLowLevelImage, true)
    }

    func testC64DataMountPreservesNIBFormatFromFilename() {
        let nib = makeNIB(entries: [
            (nibHalfTrack: 2, density: 0x03, bytes: [UInt8](repeating: 0xAA, count: 0x2000)),
        ])
        let c64 = C64()

        XCTAssertTrue(c64.mountDisk(Data(nib), fileName: "selected.nib"))

        XCTAssertEqual(c64.emulationStatus.mountedDiskName, "selected.nib")
        XCTAssertEqual(c64.emulationStatus.mountedDiskFormat, .nib)
        XCTAssertNil(c64.emulationStatus.highLevelDiskFormat)
        XCTAssertFalse(c64.diskDrive.isMounted)
        XCTAssertEqual(c64.emulationStatus.drive.hasDisk, true)
        XCTAssertEqual(c64.emulationStatus.drive.hasNativeLowLevelImage, true)
        XCTAssertEqual(c64.emulationStatus.drive.writeProtected, true)
        XCTAssertFalse(c64.emulationStatus.canExportModifiedD64)
        XCTAssertTrue(c64.emulationStatus.canExportModifiedG64)
        XCTAssertFalse(c64.emulationStatus.diskHasUnsavedChanges)
        XCTAssertEqual(c64.emulationStatus.mediaCapabilities?.format, .nib)
    }

    func testC64DataMountPreservesNBZFormatFromFilename() {
        let nib = makeNIB(entries: [
            (nibHalfTrack: 2, density: 0x03, bytes: [UInt8](repeating: 0xAA, count: 0x2000)),
        ])
        let nbz = makeLiteralNBZ(from: nib, marker: 0xFE)
        let c64 = C64()

        XCTAssertTrue(c64.mountDisk(Data(nbz), fileName: "selected.nbz"))

        XCTAssertEqual(c64.emulationStatus.mountedDiskName, "selected.nbz")
        XCTAssertEqual(c64.emulationStatus.mountedDiskFormat, .nbz)
        XCTAssertNil(c64.emulationStatus.highLevelDiskFormat)
        XCTAssertFalse(c64.diskDrive.isMounted)
        XCTAssertEqual(c64.emulationStatus.drive.hasNativeLowLevelImage, true)
        XCTAssertEqual(c64.emulationStatus.drive.writeProtected, true)
        XCTAssertFalse(c64.emulationStatus.canExportModifiedD64)
        XCTAssertTrue(c64.emulationStatus.canExportModifiedG64)
        XCTAssertFalse(c64.emulationStatus.diskHasUnsavedChanges)
        XCTAssertEqual(c64.emulationStatus.mediaCapabilities?.format, .nbz)
    }

    func testC64DataMountPreservesP64FormatFromFilename() {
        let p64 = makeP64(halfTrack: 0, gcrPrefix: [0x00, 0xA5])
        let c64 = C64()

        XCTAssertTrue(c64.mountDisk(Data(p64), fileName: "selected.p64"))

        XCTAssertEqual(c64.emulationStatus.mountedDiskName, "selected.p64")
        XCTAssertEqual(c64.emulationStatus.mountedDiskFormat, .p64)
        XCTAssertNil(c64.emulationStatus.highLevelDiskFormat)
        XCTAssertFalse(c64.diskDrive.isMounted)
        XCTAssertEqual(c64.emulationStatus.drive.hasNativeLowLevelImage, true)
        XCTAssertEqual(c64.emulationStatus.drive.writeProtected, true)
        XCTAssertFalse(c64.emulationStatus.canExportModifiedD64)
        XCTAssertTrue(c64.emulationStatus.canExportModifiedG64)
        XCTAssertFalse(c64.emulationStatus.diskHasUnsavedChanges)
        XCTAssertEqual(c64.emulationStatus.mediaCapabilities?.format, .p64)
    }

    func testC64DataMountPreservesWritableP64Flag() {
        let p64 = makeP64(halfTrack: 0, gcrPrefix: [0x00, 0xA5], flags: 0)
        let c64 = C64()

        XCTAssertTrue(c64.mountDisk(Data(p64), fileName: "writable.p64"))

        XCTAssertEqual(c64.emulationStatus.mountedDiskFormat, .p64)
        XCTAssertFalse(c64.diskDrive.isMounted)
        XCTAssertEqual(c64.emulationStatus.drive.hasNativeLowLevelImage, true)
        XCTAssertEqual(c64.emulationStatus.drive.writeProtected, false)
        XCTAssertTrue(c64.emulationStatus.canExportModifiedG64)
    }

    func testC64NativeG64LowLevelWritesExportModifiedG64() throws {
        let rawTrack: [UInt8] = [0xFF, 0xFF, 0x52, 0xA5]
        let g64 = makeSingleTrackG64(halfTrack: 34, rawTrack: rawTrack)
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(Data(g64), fileName: "native.g64"))
        c64.setMountedDiskWriteProtected(false)

        XCTAssertTrue(c64.drive1541.disk.writeByte(0x7C, halfTrack: 34, byteIndex: 2))
        XCTAssertTrue(c64.emulationStatus.diskHasUnsavedChanges)
        XCTAssertFalse(c64.emulationStatus.canExportModifiedD64)
        XCTAssertTrue(c64.emulationStatus.canExportModifiedG64)

        let exported = try XCTUnwrap(c64.exportedG64Image)
        let reloaded = GCRDisk()
        XCTAssertTrue(reloaded.loadG64(exported))
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 34)?.bytes, [0xFF, 0xFF, 0x7C, 0xA5])

        c64.markExportedG64ImageSaved()
        XCTAssertFalse(c64.emulationStatus.diskHasUnsavedChanges)
    }

    func testImportedNIBLowLevelWritesExportAsG64() throws {
        var firstTrack = [UInt8](repeating: 0xAA, count: 0x2000)
        firstTrack[2] = 0x55
        let nib = makeNIB(entries: [
            (nibHalfTrack: 2, density: 0x13, bytes: firstTrack),
        ])
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(Data(nib), fileName: "native.nib"))
        c64.setMountedDiskWriteProtected(false)

        XCTAssertTrue(c64.drive1541.disk.writeByte(0x7C, halfTrack: 0, byteIndex: 2))

        XCTAssertTrue(c64.emulationStatus.diskHasUnsavedChanges)
        XCTAssertTrue(c64.emulationStatus.canExportModifiedG64)
        let exported = try XCTUnwrap(c64.exportedG64Image)
        let reloaded = GCRDisk()
        XCTAssertTrue(reloaded.loadG64(exported))
        XCTAssertEqual(reloaded.image?.format, .g64)
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 0)?.bytes[2], 0x7C)
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 0)?.speedZone, 3)
    }

    func testImportedP64LowLevelWritesExportAsG64() throws {
        let p64 = makeP64(halfTrack: 0, gcrPrefix: [0x00, 0xA5])
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(Data(p64), fileName: "native.p64"))
        c64.setMountedDiskWriteProtected(false)

        XCTAssertTrue(c64.drive1541.disk.writeByte(0x5A, halfTrack: 0, byteIndex: 1))

        XCTAssertTrue(c64.emulationStatus.diskHasUnsavedChanges)
        XCTAssertTrue(c64.emulationStatus.canExportModifiedG64)
        let exported = try XCTUnwrap(c64.exportedG64Image)
        let reloaded = GCRDisk()
        XCTAssertTrue(reloaded.loadG64(exported))
        XCTAssertEqual(reloaded.image?.format, .g64)
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 0)?.bytes[1], 0x5A)
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 0)?.weakBitRanges, [])
    }

    func testC64MountRejectsUnsupportedG64Version() {
        var g64 = makeEmptyG64Header(version: 1)
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 8))

        let c64 = C64()

        XCTAssertFalse(c64.mountDisk(Data(g64), fileName: "unsupported.g64"))
        XCTAssertNil(c64.emulationStatus.mountedDiskName)
        XCTAssertNil(c64.emulationStatus.mountedDiskFormat)
        XCTAssertNil(c64.emulationStatus.highLevelDiskFormat)
        XCTAssertFalse(c64.emulationStatus.diskHasUnsavedChanges)
        XCTAssertFalse(c64.emulationStatus.canExportModifiedD64)
        XCTAssertFalse(c64.emulationStatus.canExportModifiedG64)
        XCTAssertFalse(c64.emulationStatus.drive.hasDisk)
    }

    func testC64MountRejectsG64WithoutTrackData() {
        var g64 = makeEmptyG64Header(version: 0)
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 8))

        let c64 = C64()

        XCTAssertFalse(c64.mountDisk(Data(g64), fileName: "empty.g64"))
        XCTAssertNil(c64.emulationStatus.mountedDiskName)
        XCTAssertNil(c64.emulationStatus.mountedDiskFormat)
        XCTAssertNil(c64.emulationStatus.highLevelDiskFormat)
        XCTAssertFalse(c64.emulationStatus.diskHasUnsavedChanges)
        XCTAssertFalse(c64.emulationStatus.canExportModifiedD64)
        XCTAssertFalse(c64.emulationStatus.canExportModifiedG64)
        XCTAssertFalse(c64.emulationStatus.drive.hasDisk)
    }

    func testC64FailedG64MountKeepsPreviouslyMountedDiskStatus() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankD64(), fileName: "good.d64"))

        let before = c64.emulationStatus
        XCTAssertEqual(before.mountedDiskName, "good.d64")
        XCTAssertEqual(before.mountedDiskFormat, .d64)
        XCTAssertEqual(before.highLevelDiskFormat, .d64)
        XCTAssertFalse(before.diskHasUnsavedChanges)
        XCTAssertTrue(before.canExportModifiedD64)
        XCTAssertEqual(before.mediaCapabilities?.hasSyntheticGCR, true)
        XCTAssertEqual(before.drive.hasNativeLowLevelImage, false)

        var badG64 = makeEmptyG64Header(version: 0)
        badG64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 8))

        XCTAssertFalse(c64.mountDisk(Data(badG64), fileName: "bad.g64"))

        let after = c64.emulationStatus
        XCTAssertEqual(after.mountedDiskName, "good.d64")
        XCTAssertEqual(after.mountedDiskFormat, .d64)
        XCTAssertEqual(after.highLevelDiskFormat, .d64)
        XCTAssertFalse(after.diskHasUnsavedChanges)
        XCTAssertTrue(after.canExportModifiedD64)
        XCTAssertFalse(after.canExportModifiedG64)
        XCTAssertEqual(after.mediaCapabilities?.hasSyntheticGCR, true)
        XCTAssertEqual(after.drive.hasDisk, true)
        XCTAssertEqual(after.drive.hasNativeLowLevelImage, false)
    }

    private func decodedTrack1Sectors(d64ErrorCode: UInt8) throws -> [(Int, [UInt8])] {
        let track1 = try syntheticTrack1(d64ErrorCode: d64ErrorCode)
        return G64Parser.decodeSectors(from: track1, track: 1, expectedSectors: 21)
    }

    private func syntheticTrack1(d64ErrorCode: UInt8) throws -> [UInt8] {
        var d64 = [UInt8](makeBlankD64())
        d64.append(contentsOf: [UInt8](repeating: 0x01, count: 683))
        let geometry = try XCTUnwrap(DiskDrive.d64Geometry(forByteCount: d64.count))
        let errorOffset = try XCTUnwrap(geometry.errorInfoOffset)
        d64[errorOffset] = d64ErrorCode

        let disk = GCRDisk()
        XCTAssertTrue(disk.loadD64(Data(d64)))
        return try XCTUnwrap(disk.trackInfo(halfTrack: 0)?.bytes)
    }

    private func trackSectors(from image: [UInt8], track: Int, geometry: DiskDrive.D64Geometry) -> [[UInt8]] {
        let trackOffset = geometry.trackOffsets[track]
        return (0..<geometry.sectorsPerTrack[track]).map { sector in
            let offset = trackOffset + sector * 256
            return Array(image[offset..<(offset + 256)])
        }
    }

    private func applyTrackByteDiffs(to disk: GCRDisk, halfTrack: Int, replacement: [UInt8]) throws {
        let current = try XCTUnwrap(disk.trackInfo(halfTrack: halfTrack)?.bytes)
        XCTAssertEqual(current.count, replacement.count)
        disk.writeProtected = false

        var changed = 0
        for index in current.indices where current[index] != replacement[index] {
            XCTAssertTrue(disk.writeByte(replacement[index], halfTrack: halfTrack, byteIndex: index))
            changed += 1
        }
        XCTAssertGreaterThan(changed, 0)
    }

    private func makeBlankD64() -> Data {
        var image = [UInt8](repeating: 0, count: 174848)
        let bamOffset = DiskDrive.trackOffset[18]
        image[bamOffset + 0] = 18
        image[bamOffset + 1] = 1
        image[bamOffset + 2] = 0x41
        image[bamOffset + 0xA2] = 0x41
        image[bamOffset + 0xA3] = 0x42
        return Data(image)
    }

    private func makeEmptyG64Header(version: UInt8) -> [UInt8] {
        var g64 = [UInt8]()
        g64.append(contentsOf: Array("GCR-1541".utf8))
        g64.append(version)
        g64.append(84)
        g64.append(0x04)
        g64.append(0x00)
        return g64
    }

    private func makeSingleTrackG64(halfTrack: Int, rawTrack: [UInt8]) -> [UInt8] {
        var g64 = [UInt8]()
        g64.append(contentsOf: Array("GCR-1541".utf8))
        g64.append(0x00)
        g64.append(84)
        g64.append(UInt8(rawTrack.count & 0xFF))
        g64.append(UInt8(rawTrack.count >> 8))

        let offsetTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))
        let speedTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))

        let trackOffset = g64.count
        g64.append(UInt8(rawTrack.count & 0xFF))
        g64.append(UInt8(rawTrack.count >> 8))
        g64.append(contentsOf: rawTrack)

        let offsetPos = offsetTableStart + halfTrack * 4
        g64[offsetPos] = UInt8(trackOffset & 0xFF)
        g64[offsetPos + 1] = UInt8((trackOffset >> 8) & 0xFF)
        g64[offsetPos + 2] = UInt8((trackOffset >> 16) & 0xFF)
        g64[offsetPos + 3] = UInt8((trackOffset >> 24) & 0xFF)

        let speedPos = speedTableStart + halfTrack * 4
        g64[speedPos] = 0x02
        return g64
    }

    private func makeNIB(entries: [(nibHalfTrack: UInt8, density: UInt8, bytes: [UInt8])]) -> [UInt8] {
        var nib = [UInt8](repeating: 0, count: 0x100)
        nib.replaceSubrange(0..<13, with: Array("MNIB-1541-RAW".utf8))
        nib[13] = 1
        for (index, entry) in entries.enumerated() {
            let headerOffset = 0x10 + index * 2
            nib[headerOffset] = entry.nibHalfTrack
            nib[headerOffset + 1] = entry.density
        }
        for entry in entries {
            precondition(entry.bytes.count == 0x2000)
            nib.append(contentsOf: entry.bytes)
        }
        return nib
    }

    private func makeLiteralNBZ(from nib: [UInt8], marker: UInt8) -> [UInt8] {
        var nbz = [marker]
        for byte in nib {
            if byte == marker {
                nbz.append(marker)
                nbz.append(0)
            } else {
                nbz.append(byte)
            }
        }
        return nbz
    }

    private func makeP64(
        halfTrack: Int,
        gcrPrefix: [UInt8],
        weakBitIndexes: Set<Int> = [],
        flags: UInt32 = 1
    ) -> [UInt8] {
        let ticksPerBit = 52 // Speed zone 3, 26 drive cycles per byte at 16 MHz.
        let p64HalfTrack = UInt8(halfTrack + 2)
        var pulses: [(position: UInt32, strength: UInt32)] = []
        for bitIndex in 0..<(gcrPrefix.count * 8) {
            let byte = gcrPrefix[bitIndex / 8]
            let mask = UInt8(1 << (7 - (bitIndex % 8)))
            guard byte & mask != 0 else { continue }
            let strength: UInt32 = weakBitIndexes.contains(bitIndex) ? 0x0000_1000 : 0xFFFF_FFFF
            pulses.append((position: UInt32(bitIndex * ticksPerBit), strength: strength))
        }

        let encoded = P64FixtureRangeEncoder.encode(pulses: pulses)
        var chunkData: [UInt8] = []
        appendLittleEndian32(UInt32(pulses.count), to: &chunkData)
        appendLittleEndian32(UInt32(encoded.count), to: &chunkData)
        chunkData.append(contentsOf: encoded)

        var chunks: [UInt8] = []
        chunks.append(contentsOf: [UInt8(ascii: "H"), UInt8(ascii: "T"), UInt8(ascii: "P"), p64HalfTrack])
        appendLittleEndian32(UInt32(chunkData.count), to: &chunks)
        appendLittleEndian32(crc32(chunkData), to: &chunks)
        chunks.append(contentsOf: chunkData)
        chunks.append(contentsOf: Array("DONE".utf8))
        appendLittleEndian32(0, to: &chunks)
        appendLittleEndian32(0, to: &chunks)

        var p64: [UInt8] = []
        p64.append(contentsOf: Array("P64-1541".utf8))
        appendLittleEndian32(0, to: &p64)
        appendLittleEndian32(flags, to: &p64)
        appendLittleEndian32(UInt32(chunks.count), to: &p64)
        appendLittleEndian32(crc32(chunks), to: &p64)
        p64.append(contentsOf: chunks)
        return p64
    }

    private func makeP64WithDuplicatedFirstTrackChunk(halfTrack: Int, gcrPrefix: [UInt8]) -> [UInt8] {
        var p64 = makeP64(halfTrack: halfTrack, gcrPrefix: gcrPrefix)
        let firstChunkOffset = 24
        let firstChunkSize = Int(littleEndian32(from: p64, at: firstChunkOffset + 4))
        let firstChunkEnd = firstChunkOffset + 12 + firstChunkSize
        let duplicateChunk = Array(p64[firstChunkOffset..<firstChunkEnd])
        p64.insert(contentsOf: duplicateChunk, at: firstChunkEnd)
        let streamSize = littleEndian32(from: p64, at: 16) + UInt32(duplicateChunk.count)
        writeLittleEndian32(streamSize, into: &p64, at: 16)
        recomputeP64CRCs(&p64)
        return p64
    }

    private func appendLittleEndian32(_ value: UInt32, to bytes: inout [UInt8]) {
        bytes.append(UInt8(value & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 24) & 0xFF))
    }

    private func writeLittleEndian32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private func littleEndian32(from bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private func recomputeP64CRCs(_ p64: inout [UInt8]) {
        let streamStart = 24
        let streamSize = Int(littleEndian32(from: p64, at: 16))
        let streamEnd = streamStart + streamSize
        var offset = streamStart
        while offset + 12 <= streamEnd {
            let chunkSize = Int(littleEndian32(from: p64, at: offset + 4))
            let chunkDataStart = offset + 12
            let chunkDataEnd = chunkDataStart + chunkSize
            guard chunkDataEnd <= streamEnd else { break }
            writeLittleEndian32(crc32(Array(p64[chunkDataStart..<chunkDataEnd])), into: &p64, at: offset + 8)
            offset = chunkDataEnd
        }
        writeLittleEndian32(crc32(Array(p64[streamStart..<streamEnd])), into: &p64, at: 20)
    }

    private func crc32(_ bytes: [UInt8]) -> UInt32 {
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

    private struct P64FixtureRangeEncoder {
        var bytes: [UInt8] = []
        var low: UInt64 = 0
        var high: UInt64 = 0xFFFF_FFFF
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

        static func encode(pulses: [(position: UInt32, strength: UInt32)]) -> [UInt8] {
            var encoder = P64FixtureRangeEncoder()
            var lastPosition: UInt32 = 0
            var previousDeltaPosition: UInt32 = 0
            var lastStrength: UInt32 = 0

            for pulse in pulses {
                let deltaPosition = pulse.position - lastPosition
                if previousDeltaPosition != deltaPosition {
                    previousDeltaPosition = deltaPosition
                    encoder.encodeBit(model: 8, bit: 1)
                    encoder.encodeDWord(model: 0, value: deltaPosition)
                } else {
                    encoder.encodeBit(model: 8, bit: 0)
                }
                lastPosition = pulse.position

                if lastStrength != pulse.strength {
                    encoder.encodeBit(model: 9, bit: 1)
                    encoder.encodeDWord(model: 4, value: pulse.strength &- lastStrength)
                    lastStrength = pulse.strength
                } else {
                    encoder.encodeBit(model: 9, bit: 0)
                }
            }

            encoder.encodeBit(model: 8, bit: 1)
            encoder.encodeDWord(model: 0, value: 0)
            encoder.flush()
            return encoder.bytes
        }

        mutating func encodeDWord(model: Int, value: UInt32) {
            for byteIndex in 0..<4 {
                let byteValue = (value >> UInt32(byteIndex * 8)) & 0xFF
                var context: UInt16 = 1
                for bitIndex in stride(from: 7, through: 0, by: -1) {
                    let bit = (byteValue >> UInt32(bitIndex)) & 0x01
                    let probabilityIndex = offsets[model + byteIndex]
                        + Int(((states[model + byteIndex] << 8) | context) & 0xFFFF)
                    encodeRawBit(probabilityIndex: probabilityIndex, bit: bit)
                    context = (context << 1) | UInt16(bit)
                }
                states[model + byteIndex] = UInt16(byteValue)
            }
        }

        mutating func encodeBit(model: Int, bit: UInt32) {
            let probabilityIndex = offsets[model] + Int(states[model])
            encodeRawBit(probabilityIndex: probabilityIndex, bit: bit)
            states[model] = UInt16(bit)
        }

        mutating func encodeRawBit(probabilityIndex: Int, bit: UInt32) {
            let middle = low + (((high - low) >> 12) * UInt64(probabilities[probabilityIndex]))
            if bit != 0 {
                probabilities[probabilityIndex] += (0x0FFF - probabilities[probabilityIndex]) >> 4
                high = middle
            } else {
                probabilities[probabilityIndex] -= probabilities[probabilityIndex] >> 4
                low = middle + 1
            }
            normalize()
        }

        mutating func normalize() {
            while ((low ^ high) & 0xFF00_0000) == 0 {
                bytes.append(UInt8((high >> 24) & 0xFF))
                low = (low << 8) & 0xFFFF_FFFF
                high = ((high << 8) | 0xFF) & 0xFFFF_FFFF
            }
        }

        mutating func flush() {
            for _ in 0..<4 {
                bytes.append(UInt8((high >> 24) & 0xFF))
                high = (high << 8) & 0xFFFF_FFFF
            }
        }
    }

    private static let gcrEncode: [UInt8] = [
        0x0A, 0x0B, 0x12, 0x13, 0x0E, 0x0F, 0x16, 0x17,
        0x09, 0x19, 0x1A, 0x1B, 0x0D, 0x1D, 0x1E, 0x15,
    ]

    private static func encodeGCR(_ bytes: [UInt8]) -> [UInt8] {
        precondition(bytes.count == 4)
        let values = [
            gcrEncode[Int(bytes[0] >> 4)], gcrEncode[Int(bytes[0] & 0x0F)],
            gcrEncode[Int(bytes[1] >> 4)], gcrEncode[Int(bytes[1] & 0x0F)],
            gcrEncode[Int(bytes[2] >> 4)], gcrEncode[Int(bytes[2] & 0x0F)],
            gcrEncode[Int(bytes[3] >> 4)], gcrEncode[Int(bytes[3] & 0x0F)],
        ].map(UInt64.init)
        let packed = (values[0] << 35) | (values[1] << 30) | (values[2] << 25) | (values[3] << 20)
            | (values[4] << 15) | (values[5] << 10) | (values[6] << 5) | values[7]
        return [
            UInt8((packed >> 32) & 0xFF),
            UInt8((packed >> 24) & 0xFF),
            UInt8((packed >> 16) & 0xFF),
            UInt8((packed >> 8) & 0xFF),
            UInt8(packed & 0xFF),
        ]
    }

    private static func encodeGCRBytes(_ bytes: [UInt8]) -> [UInt8] {
        var padded = bytes
        while padded.count % 4 != 0 { padded.append(0) }
        var encoded: [UInt8] = []
        for index in stride(from: 0, to: padded.count, by: 4) {
            encoded.append(contentsOf: encodeGCR(Array(padded[index..<(index + 4)])))
        }
        return encoded
    }

    private static func g64HeaderBlock(track: UInt8, sector: UInt8) -> [UInt8] {
        let id1: UInt8 = 0x41
        let id2: UInt8 = 0x42
        let checksum = sector ^ track ^ id2 ^ id1
        let header: [UInt8] = [0x08, checksum, sector, track, id2, id1, 0x0F, 0x0F]
        return [UInt8](repeating: 0xFF, count: 5) + encodeGCRBytes(header)
    }
}
