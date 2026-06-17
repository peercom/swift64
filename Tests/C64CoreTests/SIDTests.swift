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

    func testOscillatorAndEnvelope3RegistersReadVoice3State() {
        let sid = SID()
        sid.voices[2].control = 0x40
        sid.voices[2].pulseWidth = 0x400
        sid.voices[2].accumulator = 0x400000
        sid.voices[2].envelopeLevel = 0x6A

        XCTAssertEqual(sid.readRegister(0x1B), 0xFF)
        XCTAssertEqual(sid.readRegister(0x1C), 0x6A)

        sid.voices[2].accumulator = 0x3FFFFF

        XCTAssertEqual(sid.readRegister(0x1B), 0x00)
    }

    func testOscillatorAndEnvelope3AreMemoryMappedThroughSIDIOArea() {
        let memory = MemoryMap()
        let sid = SID()
        memory.sid = sid
        sid.voices[2].control = 0x10
        sid.voices[2].accumulator = 0x400000
        sid.voices[2].envelopeLevel = 0x42

        XCTAssertEqual(memory.read(0xD41B), 0x80)
        XCTAssertEqual(memory.read(0xD41C), 0x42)
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

    func testOscillatorSyncResetsOnSourceMSBRisingEdge() {
        let sid = SID()
        sid.voices[0].control = 0x02
        sid.voices[0].accumulator = 0x123456
        sid.voices[0].frequency = 0
        sid.voices[2].accumulator = 0x7FFFFF
        sid.voices[2].frequency = 1

        sid.tick()

        XCTAssertEqual(sid.voices[0].accumulator, 0)
    }

    func testOscillatorSyncDoesNotResetWhileSourceMSBStaysHigh() {
        let sid = SID()
        sid.voices[0].control = 0x02
        sid.voices[0].accumulator = 0x123456
        sid.voices[0].frequency = 0
        sid.voices[2].accumulator = 0x800000
        sid.voices[2].frequency = 1

        sid.tick()

        XCTAssertEqual(sid.voices[0].accumulator, 0x123456)
    }

    func testTestBitImmediatelyResetsOscillatorState() {
        let sid = SID()
        sid.voices[2].control = 0x20
        sid.voices[2].accumulator = 0xFFFFFF
        sid.voices[2].shiftRegister = 0x123456
        sid.oscillatorMSBRose[2] = true

        sid.writeRegister(0x12, value: 0x08)

        XCTAssertEqual(sid.voices[2].accumulator, 0)
        XCTAssertEqual(sid.voices[2].shiftRegister, 0)
        XCTAssertFalse(sid.oscillatorMSBRose[2])
        XCTAssertEqual(sid.readRegister(0x1B), 0)
    }
}
