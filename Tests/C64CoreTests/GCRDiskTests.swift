import XCTest
@testable import C64Core

final class GCRDiskTests: XCTestCase {
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
        XCTAssertTrue(disk.image?.capabilities.supportsWraparoundReads == true)
        XCTAssertTrue(disk.image?.capabilities.unsupportedFeatures.contains("Weak/random bits") == true)
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
        XCTAssertTrue(disk.image?.capabilities.unsupportedFeatures.contains("Native copy-protection bitstream") == true)
    }

    func testExtendedD64LoadCreatesSyntheticLowLevelTracks() {
        var image = [UInt8](makeBlankD64())
        image.append(contentsOf: [UInt8](repeating: 0, count: 200704 - image.count))

        let disk = GCRDisk()
        XCTAssertTrue(disk.loadD64(Data(image)))
        XCTAssertNotNil(disk.trackInfo(halfTrack: 34))
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
}
