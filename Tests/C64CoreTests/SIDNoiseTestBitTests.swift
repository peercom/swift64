import XCTest
@testable import C64Core

/// Noise shift register behaviour around the TEST bit, derived from the
/// public `noisetest` and `oscsample` programs (verified on a C64 with a 6581
/// and a C64C with an 8580) and their included hardware dumps:
///
/// - a TEST hold freezes the register; two PAL frames leave every bit intact;
/// - a long hold pulls every bit to one;
/// - the TEST release clocks the register once with TEST ORed into the
///   bit-22 feedback input (bit 0 = NOT bit 17);
/// - output bits 11..4 come from register bits 20, 18, 14, 11, 9, 5, 2, 0.
final class SIDNoiseTestBitTests: XCTestCase {
    private static let twoPALFrames = 2 * 19_656

    private func makeSID(_ model: SID.Model) -> SID {
        let sid = SID()
        sid.model = model
        sid.accuracyMode = .fast
        return sid
    }

    private func tick(_ sid: SID, cycles: Int) {
        for _ in 0..<cycles { sid.tick() }
    }

    func testLongTestHoldPullsNoiseRegisterToAllOnesAtModelThreshold() {
        for model in [SID.Model.mos6581, .mos8580] {
            let sid = makeSID(model)
            sid.voices[0].shiftRegister = 0x123456
            sid.writeRegister(0x04, value: 0x08)
            let resetCycles = SID.noiseShiftRegisterResetCycles(for: model)

            tick(sid, cycles: resetCycles - 1)
            XCTAssertEqual(sid.voices[0].shiftRegister, 0x123456, "\(model) one cycle before the threshold")

            tick(sid, cycles: 1)
            XCTAssertEqual(sid.voices[0].shiftRegister, 0x7FFFFF, "\(model) at the threshold")

            tick(sid, cycles: 1000)
            XCTAssertEqual(sid.voices[0].shiftRegister, 0x7FFFFF, "\(model) stays all ones")
        }
        XCTAssertGreaterThan(SID.noiseShiftRegisterResetCycles(for: .mos6581), Self.twoPALFrames)
        XCTAssertGreaterThan(SID.noiseShiftRegisterResetCycles(for: .mos8580), SID.noiseShiftRegisterResetCycles(for: .mos6581))
        XCTAssertLessThan(SID.noiseShiftRegisterResetCycles(for: .mos8580), 23_592_960, "the programs' long hold")
    }

    func testTwoFrameTestHoldKeepsEveryNoiseRegisterBitAndTheReadback() {
        for model in [SID.Model.mos6581, .mos8580] {
            let sid = makeSID(model)
            sid.voices[2].frequency = 0x1000
            sid.voices[2].shiftRegister = 0x2A5C93
            sid.writeRegister(0x12, value: 0x80)
            tick(sid, cycles: 2)
            let readableBefore = sid.readRegister(0x1B)
            XCTAssertNotEqual(readableBefore, 0)

            sid.writeRegister(0x12, value: 0x88)
            tick(sid, cycles: 4)
            XCTAssertEqual(sid.readRegister(0x1B), readableBefore, "\(model): OSC3 unchanged right after setting TEST")

            tick(sid, cycles: Self.twoPALFrames)
            XCTAssertEqual(sid.voices[2].accumulator, 0)
            XCTAssertEqual(sid.voices[2].shiftRegister, 0x2A5C93, "\(model): the hold does not alter the register")
            XCTAssertEqual(sid.readRegister(0x1B), readableBefore, "\(model): still readable through the hold")

            // Release: one shift with bit 0 = (bit 22 OR 1) XOR bit 17.
            sid.writeRegister(0x12, value: 0x80)
            let expected = ((UInt32(0x2A5C93) << 1) | (1 ^ ((0x2A5C93 >> 17) & 1))) & 0x7FFFFF
            XCTAssertEqual(sid.voices[2].shiftRegister, expected, "\(model)")
            XCTAssertEqual(sid.voices[2].testHoldCycles, 0)
        }
    }

    /// `noisetest`: after the long hold the program's reference register is all
    /// ones, and every short TEST pulse shifts it once with bit 0 = NOT bit 17.
    /// The first twelve OSC3 values of that model are pinned here.
    func testShortTestPulsesFollowTheNoisetestReferenceModel() {
        let expected: [UInt8] = [0xFE, 0xFE, 0xFC, 0xFC, 0xFC, 0xF8, 0xF8, 0xF8, 0xF8, 0xF0, 0xF0, 0xE0]
        for model in [SID.Model.mos6581, .mos8580] {
            let sid = makeSID(model)
            sid.writeRegister(0x12, value: 0x88)
            tick(sid, cycles: 100)
            XCTAssertEqual(sid.voices[2].shiftRegister, 0x7FFFFF)

            var observed: [UInt8] = []
            for _ in expected.indices {
                let before = sid.readRegister(0x1B)
                sid.writeRegister(0x12, value: 0x88)
                tick(sid, cycles: 4)
                XCTAssertEqual(sid.readRegister(0x1B), before, "\(model): no shift when TEST is set")
                sid.writeRegister(0x12, value: 0x80)
                tick(sid, cycles: 60)
                observed.append(sid.readRegister(0x1B))
            }
            XCTAssertEqual(observed, expected, "\(model)")
        }
    }

    /// `oscsample` run 1 (after the 23.6-million-cycle hold): FREQ $1000 shifts
    /// the register every 256 cycles from cycle 128 after the release. The dump
    /// reads $FE, then $FC from the 2nd shift, $F8 from the 5th, $F0 from the
    /// 9th, $E0 from the 11th and $C0 from the 14th: zeros fed into bit 0 of
    /// an all-ones register reaching taps 2, 5, 9, 11 and 14.
    func testFirstOscsampleNoiseRunAfterLongHold() {
        let expectedAfterShift: [UInt8] = [
            0xFE, 0xFC, 0xFC, 0xFC, 0xF8, 0xF8, 0xF8, 0xF8, 0xF0, 0xF0, 0xE0, 0xE0, 0xE0, 0xC0, 0xC0, 0xC0,
        ]
        for model in [SID.Model.mos6581, .mos8580] {
            let sid = makeSID(model)
            sid.voices[2].shiftRegister = 0x2A5C93
            sid.writeRegister(0x12, value: 0x88)
            tick(sid, cycles: SID.noiseShiftRegisterResetCycles(for: model) + 10)
            sid.writeRegister(0x12, value: 0x08)
            sid.writeRegister(0x0E, value: 0x00)
            sid.writeRegister(0x0F, value: 0x10)
            tick(sid, cycles: 1000)
            XCTAssertEqual(sid.voices[2].shiftRegister, 0x7FFFFF, "\(model)")

            sid.writeRegister(0x12, value: 0x80)
            XCTAssertEqual(sid.voices[2].shiftRegister, 0x7FFFFE, "\(model)")
            tick(sid, cycles: 4)
            XCTAssertEqual(sid.readRegister(0x1B), 0xFE, "\(model): first sample")
            tick(sid, cycles: 120)
            XCTAssertEqual(sid.readRegister(0x1B), 0xFE, "\(model): just before the first shift")

            var observed: [UInt8] = []
            for _ in expectedAfterShift.indices {
                tick(sid, cycles: 256)
                observed.append(sid.readRegister(0x1B))
            }
            XCTAssertEqual(observed, expectedAfterShift, "\(model)")
        }
    }

    /// `oscsample` run 2: the register carried out of run 1 (248 shifts after
    /// its release) survives the two-frame hold and the release shift turns it
    /// into the state whose first dump byte is $48, followed by $FB after the
    /// next accumulator-driven shift.
    func testSecondOscsampleNoiseRunContinuesTheRegisterThroughTheHold() {
        for model in [SID.Model.mos6581, .mos8580] {
            let sid = makeSID(model)
            sid.writeRegister(0x0E, value: 0x00)
            sid.writeRegister(0x0F, value: 0x10)
            sid.writeRegister(0x12, value: 0x08)
            tick(sid, cycles: 10)
            sid.writeRegister(0x12, value: 0x80)
            XCTAssertEqual(sid.voices[2].shiftRegister, 0x7FFFFE, "\(model)")

            // 248 shifts at cycles 128 + 256 k, k = 0...247, then stop before the 249th.
            tick(sid, cycles: 128 + 247 * 256 + 100)
            XCTAssertEqual(sid.voices[2].shiftRegister, 0x079BC1, "\(model): state entering the hold")

            sid.writeRegister(0x12, value: 0x08)
            tick(sid, cycles: Self.twoPALFrames)
            XCTAssertEqual(sid.voices[2].shiftRegister, 0x079BC1, "\(model)")
            sid.writeRegister(0x12, value: 0x80)
            XCTAssertEqual(sid.voices[2].shiftRegister, 0x0F3782, "\(model)")
            tick(sid, cycles: 4)
            XCTAssertEqual(sid.readRegister(0x1B), 0x48, "\(model): first byte of run 2")
            tick(sid, cycles: 200)
            XCTAssertEqual(sid.readRegister(0x1B), 0xFB, "\(model): after the first shift of run 2")
        }
    }

    func testTestHoldCountSurvivesSaveState() throws {
        let c64 = C64()
        c64.sid.writeRegister(0x04, value: 0x08)
        for _ in 0..<1234 { c64.sid.tick() }
        XCTAssertEqual(c64.sid.voices[0].testHoldCycles, 1234)

        let data = try c64.saveState()
        c64.sid.voices[0].testHoldCycles = 0
        try c64.restoreState(from: data)

        XCTAssertEqual(c64.sid.voices[0].testHoldCycles, 1234)
    }
}

extension SIDNoiseTestBitTests {
    /// The shift lands two cycles after the bit-19 edge on the 6581 and one
    /// cycle after it on the 8580 (the `oscsample` runs with delays 5 and 6
    /// straddle the first shift on both chips in their own sample layout).
    func testNoiseShiftPipelineLengthPerModel() {
        for model in [SID.Model.mos6581, .mos8580] {
            let sid = SID()
            sid.model = model
            sid.voices[0].control = 0x80
            sid.voices[0].accumulator = 0x07FFFF
            sid.voices[0].frequency = 1
            sid.voices[0].shiftRegister = 0x400000

            sid.clockOscillator(0)
            XCTAssertTrue(sid.noiseClockRose[0], "\(model)")
            XCTAssertEqual(sid.voices[0].shiftRegister, 0x400000, "\(model)")
            if model == .mos6581 {
                sid.clockOscillator(0)
                XCTAssertEqual(sid.voices[0].shiftRegister, 0x400000, "\(model): still pending")
            }
            sid.clockOscillator(0)
            XCTAssertEqual(sid.voices[0].shiftRegister, 1, "\(model)")
        }
    }
}
