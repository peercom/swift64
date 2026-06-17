import XCTest
@testable import C64Core

final class DriveMemoryMapTests: XCTestCase {
    func testUnmappedReadReturnsLastDriveCPUReadValue() {
        let memory = DriveMemoryMap()
        memory.ram[0x0004] = 0x6B

        XCTAssertEqual(memory.read(0x0004), 0x6B)
        XCTAssertEqual(memory.read(0x1000), 0x6B)
        XCTAssertEqual(memory.read(0xBFFF), 0x6B)
    }

    func testUnmappedReadReturnsLastDriveCPUWriteValue() {
        let memory = DriveMemoryMap()

        memory.write(0x0400, value: 0xC7)

        XCTAssertEqual(memory.read(0x1000), 0xC7)
    }

    func testAbsentVIAMapReadsOpenBus() {
        let memory = DriveMemoryMap()
        memory.rom[0] = 0xA2

        XCTAssertEqual(memory.read(0xC000), 0xA2)
        XCTAssertEqual(memory.read(0x1800), 0xA2)
        XCTAssertEqual(memory.read(0x1C00), 0xA2)
    }
}
