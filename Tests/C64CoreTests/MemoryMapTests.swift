import XCTest
@testable import C64Core

final class MemoryMapTests: XCTestCase {
    func testUnmappedExpansionAreaReturnsLastCPUReadValue() {
        let memory = MemoryMap()
        memory.ram[0xC000] = 0xA7

        XCTAssertEqual(memory.read(0xC000), 0xA7)
        XCTAssertEqual(memory.read(0xDE00), 0xA7)
        XCTAssertEqual(memory.read(0xDFFF), 0xA7)
    }

    func testUnmappedExpansionAreaReturnsLastCPUWriteValue() {
        let memory = MemoryMap()

        memory.write(0x2000, value: 0x5C)

        XCTAssertEqual(memory.read(0xDF00), 0x5C)
    }

    func testSIDWriteOnlyRegistersReturnOpenBus() {
        let memory = MemoryMap()
        let sid = SID()
        memory.sid = sid
        sid.setPaddle(x: 0x44, y: 0x55)

        memory.ram[0xC000] = 0xA9
        XCTAssertEqual(memory.read(0xC000), 0xA9)

        XCTAssertEqual(memory.read(0xD400), 0xA9)
        XCTAssertEqual(memory.read(0xD418), 0xA9)
        XCTAssertEqual(memory.read(0xD419), 0x44)
        XCTAssertEqual(memory.read(0xD41A), 0x55)
    }

    func testColorRAMReadsLowNibbleWithOpenBusHighNibble() {
        let memory = MemoryMap()
        memory.ram[0xC000] = 0xA3
        memory.write(0xD800, value: 0x5E)

        XCTAssertEqual(memory.colorRAM[0], 0x0E)

        XCTAssertEqual(memory.read(0xC000), 0xA3)
        XCTAssertEqual(memory.read(0xD800), 0xAE)
    }

    func testAbsentVICAndCIAReadsReturnOpenBus() {
        let memory = MemoryMap()
        memory.ram[0xC000] = 0x72

        XCTAssertEqual(memory.read(0xC000), 0x72)

        XCTAssertEqual(memory.read(0xD000), 0x72)
        XCTAssertEqual(memory.read(0xDC00), 0x72)
        XCTAssertEqual(memory.read(0xDD00), 0x72)
    }
}
