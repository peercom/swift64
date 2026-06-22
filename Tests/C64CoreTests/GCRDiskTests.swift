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
        XCTAssertFalse(c64.diskDrive.isMounted)
        XCTAssertEqual(c64.emulationStatus.drive.hasNativeLowLevelImage, true)
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
