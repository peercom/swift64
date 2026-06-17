import XCTest
@testable import C64Core

final class SIDTests: XCTestCase {
    func testPaddleRegistersReadLatchedAnalogValues() {
        let sid = SID()

        XCTAssertEqual(sid.readRegister(0x19), 0xFF)
        XCTAssertEqual(sid.readRegister(0x1A), 0xFF)

        sid.setPaddle(x: 0x34, y: 0xA5)

        XCTAssertEqual(sid.readRegister(0x19), 0x34)
        XCTAssertEqual(sid.readRegister(0x1A), 0xA5)
    }

    func testPaddleRegistersAreMemoryMappedThroughSIDIOArea() {
        let memory = MemoryMap()
        let sid = SID()
        memory.sid = sid
        sid.setPaddle(x: 0x12, y: 0xEF)

        XCTAssertEqual(memory.read(0xD419), 0x12)
        XCTAssertEqual(memory.read(0xD41A), 0xEF)
    }

    func testEnvelopeRateCounterWrapsInsteadOfCrashing() {
        let sid = SID()
        sid.voices[0].rateCounter = UInt16.max
        sid.voices[0].envelopeState = .release
        sid.voices[0].sustainRelease = 0x00

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].rateCounter, 0)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0)
    }
}
