import XCTest
@testable import C64Core

final class SIDTests: XCTestCase {
    func testResetClearsVoiceFilterPaddleAndAudioStateButKeepsModelAndClock() {
        let sid = SID()
        sid.model = .mos8580
        sid.clockRate = 1_022_727
        sid.voices[0].frequency = 0x1234
        sid.voices[0].control = 0x21
        sid.voices[0].accumulator = 0xABCDEF
        sid.voices[2].envelopeLevel = 0x77
        sid.writeRegister(0x18, value: 0x0F)
        sid.setExternalAudioInput(0x1234)
        sid.setPaddle(x: 0x12, y: 0x34)
        sid.sampleBuffer[0] = 0.5
        sid.sampleWritePos = 10
        sid.oscillatorMSBRose[1] = true
        sid.noiseClockRose[2] = true

        sid.reset()

        XCTAssertEqual(sid.dataBusLatch, 0)
        XCTAssertEqual(sid.dataBusLatchCyclesRemaining, 0)
        XCTAssertEqual(sid.model, .mos8580)
        XCTAssertEqual(sid.clockRate, 1_022_727)
        XCTAssertEqual(sid.voices[0].frequency, 0)
        XCTAssertEqual(sid.voices[0].control, 0)
        XCTAssertEqual(sid.voices[0].accumulator, 0)
        XCTAssertEqual(sid.voices[0].shiftRegister, 0x7FFFF8)
        XCTAssertEqual(sid.voices[2].envelopeLevel, 0)
        XCTAssertEqual(sid.readRegister(0x19), 0xFF)
        XCTAssertEqual(sid.readRegister(0x1A), 0xFF)
        XCTAssertEqual(sid.volumeFilter, 0)
        XCTAssertEqual(sid.externalAudioInput, 0)
        XCTAssertEqual(sid.dataBusLatch, 0xFF)
        XCTAssertEqual(sid.dataBusLatchCyclesRemaining, SID.dataBusLatchHoldCycles)
        XCTAssertEqual(sid.sampleBuffer[0], 0)
        XCTAssertEqual(sid.sampleWritePos, 0)
        XCTAssertFalse(sid.oscillatorMSBRose.contains(true))
        XCTAssertFalse(sid.noiseClockRose.contains(true))
    }

    func testPaddleRegistersReadLatchedAnalogValues() {
        let sid = SID()

        XCTAssertEqual(sid.readRegister(0x19), 0xFF)
        XCTAssertEqual(sid.readRegister(0x1A), 0xFF)

        sid.setPaddle(x: 0x34, y: 0xA5)

        XCTAssertEqual(sid.readRegister(0x19), 0x34)
        XCTAssertEqual(sid.readRegister(0x1A), 0xA5)
    }

    func testDebugRegisterValueReportsEffectiveSIDWriteState() {
        let sid = SID()

        sid.writeRegister(0x00, value: 0x34)
        sid.writeRegister(0x01, value: 0x12)
        sid.writeRegister(0x02, value: 0x78)
        sid.writeRegister(0x03, value: 0x5F)
        sid.writeRegister(0x04, value: 0x21)
        sid.writeRegister(0x05, value: 0xAD)
        sid.writeRegister(0x06, value: 0xF6)
        sid.writeRegister(0x15, value: 0x07)
        sid.writeRegister(0x16, value: 0xAB)
        sid.writeRegister(0x17, value: 0xF5)
        sid.writeRegister(0x18, value: 0x8F)

        XCTAssertEqual(sid.debugRegisterValue(0x00), 0x34)
        XCTAssertEqual(sid.debugRegisterValue(0x01), 0x12)
        XCTAssertEqual(sid.debugRegisterValue(0x02), 0x78)
        XCTAssertEqual(sid.debugRegisterValue(0x03), 0x0F)
        XCTAssertEqual(sid.debugRegisterValue(0x04), 0x21)
        XCTAssertEqual(sid.debugRegisterValue(0x05), 0xAD)
        XCTAssertEqual(sid.debugRegisterValue(0x06), 0xF6)
        XCTAssertEqual(sid.debugRegisterValue(0x15), 0x07)
        XCTAssertEqual(sid.debugRegisterValue(0x16), 0xAB)
        XCTAssertEqual(sid.debugRegisterValue(0x17), 0xF5)
        XCTAssertEqual(sid.debugRegisterValue(0xD418), 0x8F)
    }

    func testDirectWriteOnlySIDReadsReturnLocalDataBusLatch() {
        let sid = SID()

        XCTAssertEqual(sid.readRegister(0x00), 0x00)

        sid.writeRegister(0x00, value: 0x34)
        XCTAssertEqual(sid.readRegister(0x00), 0x34)
        XCTAssertEqual(sid.dataBusLatchCyclesRemaining, SID.dataBusLatchHoldCycles)

        sid.writeRegister(0x18, value: 0x8F)
        XCTAssertEqual(sid.readRegister(0x05), 0x8F)
    }

    func testSIDDataBusLatchDecaysAfterHoldWindow() {
        let sid = SID()

        sid.writeRegister(0x00, value: 0x34)
        for _ in 0..<(SID.dataBusLatchHoldCycles - 1) {
            sid.tick()
        }

        XCTAssertEqual(sid.dataBusLatch, 0x34)
        XCTAssertEqual(sid.dataBusLatchCyclesRemaining, 1)

        sid.tick()

        XCTAssertEqual(sid.dataBusLatch, 0)
        XCTAssertEqual(sid.dataBusLatchCyclesRemaining, 0)
        XCTAssertEqual(sid.readRegister(0x00), 0)
    }

    func testSIDDataBusLatchRefreshesBeforeDecay() {
        let sid = SID()

        sid.writeRegister(0x00, value: 0x12)
        for _ in 0..<32 {
            sid.tick()
        }

        sid.writeRegister(0x01, value: 0xAB)

        XCTAssertEqual(sid.dataBusLatch, 0xAB)
        XCTAssertEqual(sid.dataBusLatchCyclesRemaining, SID.dataBusLatchHoldCycles)
        XCTAssertEqual(sid.readRegister(0x00), 0xAB)
    }

    func testReadableSIDRegistersUpdateLocalDataBusLatch() {
        let sid = SID()
        sid.setPaddle(x: 0x12, y: 0x34)

        XCTAssertEqual(sid.readRegister(0x19), 0x12)
        XCTAssertEqual(sid.readRegister(0x00), 0x12)

        XCTAssertEqual(sid.readRegister(0x1A), 0x34)
        XCTAssertEqual(sid.readRegister(0x00), 0x34)
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

    func testNoiseWaveformMapsSIDShiftRegisterOutputBits() {
        let sid = SID()
        sid.voices[0].control = 0x80
        sid.voices[0].shiftRegister = (1 << 22) | (1 << 20) | (1 << 16) | (1 << 13) |
            (1 << 11) | (1 << 7) | (1 << 4) | (1 << 2)

        XCTAssertEqual(sid.oscillatorOutput(0), 0xFF0)

        sid.voices[0].shiftRegister = (1 << 22) | (1 << 11) | (1 << 2)

        XCTAssertEqual(sid.oscillatorOutput(0), 0x890)
    }

    func testCombinedNoiseSawMasksNoiseWithSawtoothOutput() {
        let sid = SID()
        sid.voices[0].control = 0xA0
        sid.voices[0].shiftRegister = (1 << 22) | (1 << 20) | (1 << 16) | (1 << 13) |
            (1 << 11) | (1 << 7) | (1 << 4) | (1 << 2)
        sid.voices[0].accumulator = 0x0F0000

        XCTAssertEqual(sid.oscillatorOutput(0), 0x0F0)
    }

    func testCombinedNoiseTriangleMasksNoiseWithTriangleOutput() {
        let sid = SID()
        sid.voices[0].control = 0x90
        sid.voices[0].shiftRegister = (1 << 22) | (1 << 20) | (1 << 16) | (1 << 13) |
            (1 << 11) | (1 << 7) | (1 << 4) | (1 << 2)
        sid.voices[0].accumulator = 0x100000

        XCTAssertEqual(sid.oscillatorOutput(0), 0x200)
    }

    func testCombinedNoisePulseMasksNoiseWithPulseOutput() {
        let sid = SID()
        sid.voices[0].control = 0xC0
        sid.voices[0].shiftRegister = (1 << 22) | (1 << 20) | (1 << 16) | (1 << 13) |
            (1 << 11) | (1 << 7) | (1 << 4) | (1 << 2)
        sid.voices[0].pulseWidth = 0x0800

        sid.voices[0].accumulator = 0x700000
        XCTAssertEqual(sid.oscillatorOutput(0), 0)

        sid.voices[0].accumulator = 0x900000
        XCTAssertEqual(sid.oscillatorOutput(0), 0xFF0)
    }

    func test6581CombinedNoiseClockDrainsDACBitsTowardLockup() {
        let sid = SID()
        sid.model = .mos6581
        sid.voices[0].control = 0xA0
        sid.voices[0].accumulator = 0x07FFFF
        sid.voices[0].frequency = 1
        sid.voices[0].shiftRegister = (1 << 22) | (1 << 20) | (1 << 16) | (1 << 13) |
            (1 << 11) | (1 << 7) | (1 << 4) | (1 << 2)

        sid.clockOscillator(0)

        XCTAssertTrue(sid.noiseClockRose[0])
        XCTAssertEqual(sid.noiseWaveformOutput(0), 0)
        XCTAssertNotEqual(sid.voices[0].shiftRegister, 0)
    }

    func test8580CombinedNoiseClockPreservesDigitalNoiseBits() {
        let sid = SID()
        sid.model = .mos8580
        sid.voices[0].control = 0xA0
        sid.voices[0].accumulator = 0x07FFFF
        sid.voices[0].frequency = 1
        sid.voices[0].shiftRegister = (1 << 21) | (1 << 19) | (1 << 15) | (1 << 12) |
            (1 << 10) | (1 << 6) | (1 << 3) | (1 << 1)

        sid.clockOscillator(0)

        XCTAssertTrue(sid.noiseClockRose[0])
        XCTAssertEqual(sid.noiseWaveformOutput(0), 0xFF0)
    }

    func testTestBitReseeds6581CombinedNoiseLockup() {
        let sid = SID()
        sid.model = .mos6581
        sid.voices[0].control = 0xA0
        sid.voices[0].shiftRegister = 0

        sid.writeRegister(0x04, value: 0xA8)
        XCTAssertEqual(sid.voices[0].shiftRegister, 0)

        sid.writeRegister(0x04, value: 0xA0)

        XCTAssertEqual(sid.voices[0].shiftRegister, 0x7FFFF8)
        XCTAssertNotEqual(sid.noiseWaveformOutput(0), 0)
    }

    func testPulseWaveformWidthZeroIsSilentAndMaxIsHigh() {
        let sid = SID()
        sid.voices[0].control = 0x40
        sid.voices[0].accumulator = 0xFFFFFF
        sid.voices[0].pulseWidth = 0

        XCTAssertEqual(sid.oscillatorOutput(0), 0)

        sid.voices[0].accumulator = 0
        sid.voices[0].pulseWidth = 0x0FFF

        XCTAssertEqual(sid.oscillatorOutput(0), 0xFFF)
    }

    func testPulseWaveformComparesTopTwelveAccumulatorBits() {
        let sid = SID()
        sid.voices[0].control = 0x40
        sid.voices[0].pulseWidth = 0x0800

        sid.voices[0].accumulator = 0x7FFFFF
        XCTAssertEqual(sid.oscillatorOutput(0), 0)

        sid.voices[0].accumulator = 0x800000
        XCTAssertEqual(sid.oscillatorOutput(0), 0xFFF)
    }

    func testCombinedSawPulseMasksSawtoothWithPulseOutput() {
        let sid = SID()
        sid.model = .mos8580
        sid.voices[0].control = 0x60
        sid.voices[0].pulseWidth = 0x0800
        sid.voices[0].accumulator = 0x700000

        XCTAssertEqual(sid.oscillatorOutput(0), 0)

        sid.voices[0].accumulator = 0x900000

        XCTAssertEqual(sid.oscillatorOutput(0), 0x900)
    }

    func test6581SawPulseUsesSawAndTriangleDACMixInsteadOfPulseGate() {
        let sid = SID()
        sid.model = .mos6581
        sid.voices[0].control = 0x60
        sid.voices[0].pulseWidth = 0x0800
        sid.voices[0].accumulator = 0x300000

        XCTAssertEqual(sid.sawtoothWaveformOutput(0), 0x300)
        XCTAssertEqual(sid.triangleWaveformOutput(0), 0x600)
        XCTAssertEqual(sid.pulseWaveformOutput(0), 0)
        XCTAssertEqual(sid.oscillatorOutput(0), 0x200)
    }

    func testCombinedTriangleSawMasksTriangleWithSawtoothOutput() {
        let sid = SID()
        sid.voices[0].control = 0x30
        sid.voices[0].accumulator = 0x180000

        XCTAssertEqual(sid.oscillatorOutput(0), 0x100)
    }

    func testCombinedTrianglePulseMasksTriangleWithPulseOutput() {
        let sid = SID()
        sid.voices[0].control = 0x50
        sid.voices[0].pulseWidth = 0x0800

        sid.voices[0].accumulator = 0x100000
        XCTAssertEqual(sid.oscillatorOutput(0), 0)

        sid.voices[0].accumulator = 0x900000
        XCTAssertEqual(sid.oscillatorOutput(0), 0xDFF)
    }

    func testTriangleRingModInvertsWhenSyncSourceMSBIsHigh() {
        let sid = SID()
        sid.voices[0].control = 0x14
        sid.voices[0].accumulator = 0x100000
        sid.voices[2].accumulator = 0x800000

        XCTAssertEqual(sid.oscillatorOutput(0), 0xDFF)
    }

    func testTriangleRingModDoesNotInvertWhenSyncSourceMSBIsLow() {
        let sid = SID()
        sid.voices[0].control = 0x14
        sid.voices[0].accumulator = 0x100000
        sid.voices[2].accumulator = 0x7FFFFF

        XCTAssertEqual(sid.oscillatorOutput(0), 0x200)
    }

    func testRingModBitDoesNotAffectSawtoothWithoutTriangle() {
        let sid = SID()
        sid.voices[0].control = 0x24
        sid.voices[0].accumulator = 0x100000
        sid.voices[2].accumulator = 0x800000

        XCTAssertEqual(sid.oscillatorOutput(0), 0x100)
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

    func testEnvelopeRateCounterUsesEqualityForADSRDelayBug() {
        let sid = SID()
        sid.voices[0].control = 0x01
        sid.voices[0].envelopeState = .release
        sid.voices[0].attackDecay = 0x00
        sid.voices[0].rateCounter = SID.attackRates[0] + 1

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeState, .attack)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0)
        XCTAssertEqual(sid.voices[0].rateCounter, SID.attackRates[0] + 2)

        sid.voices[0].rateCounter = SID.envelopeRateCounterMask - 1
        sid.clockEnvelope(0)
        XCTAssertEqual(sid.voices[0].rateCounter, SID.envelopeRateCounterMask)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0)

        sid.clockEnvelope(0)
        XCTAssertEqual(sid.voices[0].rateCounter, 0)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0)

        for _ in 0..<Int(SID.attackRates[0]) {
            sid.clockEnvelope(0)
        }

        XCTAssertEqual(sid.voices[0].rateCounter, 0)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 1)
    }

    func testAttackStepToMaximumImmediatelyEntersDecayState() {
        let sid = SID()
        sid.voices[0].control = 0x01
        sid.voices[0].gate = true
        sid.voices[0].envelopeState = .attack
        sid.voices[0].envelopeLevel = 0xFE
        sid.voices[0].attackDecay = 0x00
        sid.voices[0].rateCounter = SID.attackRates[0] - 1

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].rateCounter, 0)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0xFF)
        XCTAssertEqual(sid.voices[0].envelopeState, .decay)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
        XCTAssertEqual(sid.voices[0].exponentialPeriod, SID.exponentialPeriod(for: 0xFF))
    }

    func testEnvelopeExponentialPeriodChangesAtSIDThresholds() {
        XCTAssertEqual(SID.exponentialPeriod(for: 0xFF), 1)
        XCTAssertEqual(SID.exponentialPeriod(for: 0x5D), 2)
        XCTAssertEqual(SID.exponentialPeriod(for: 0x36), 4)
        XCTAssertEqual(SID.exponentialPeriod(for: 0x1A), 8)
        XCTAssertEqual(SID.exponentialPeriod(for: 0x0E), 16)
        XCTAssertEqual(SID.exponentialPeriod(for: 0x06), 30)
        XCTAssertEqual(SID.exponentialPeriod(for: 0x00), 1)
    }

    func testDecayUsesExponentialCounterBelowThreshold() {
        let sid = SID()
        sid.voices[0].envelopeState = .decay
        sid.voices[0].envelopeLevel = 0x5D
        sid.voices[0].exponentialPeriod = SID.exponentialPeriod(for: 0x5D)
        sid.voices[0].sustainRelease = 0x00
        sid.voices[0].attackDecay = 0x00
        sid.voices[0].rateCounter = 8

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeLevel, 0x5D)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 1)

        sid.voices[0].rateCounter = 8
        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeLevel, 0x5C)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
        XCTAssertEqual(sid.voices[0].exponentialPeriod, 4)
    }

    func testSustainStateHoldsWhenEnvelopeIsAtCurrentSustainLevel() {
        let sid = SID()
        sid.voices[0].envelopeState = .sustain
        sid.voices[0].envelopeLevel = 0x88
        sid.voices[0].sustainRelease = 0x80
        sid.voices[0].attackDecay = 0x00
        sid.voices[0].rateCounter = 8

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeState, .sustain)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0x88)
        XCTAssertEqual(sid.voices[0].rateCounter, 8)
    }

    func testDecayStepToSustainLevelImmediatelyEntersSustainState() {
        let sid = SID()
        sid.voices[0].envelopeState = .decay
        sid.voices[0].envelopeLevel = 0x89
        sid.voices[0].sustainRelease = 0x80
        sid.voices[0].attackDecay = 0x00
        sid.voices[0].exponentialPeriod = 1
        sid.voices[0].rateCounter = SID.decayReleaseRates[0] - 1

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].rateCounter, 0)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0x88)
        XCTAssertEqual(sid.voices[0].envelopeState, .sustain)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
    }

    func testLoweringSustainLevelResumesDecayFromSustainState() {
        let sid = SID()
        sid.voices[0].envelopeState = .sustain
        sid.voices[0].envelopeLevel = 0x88
        sid.voices[0].sustainRelease = 0x70
        sid.voices[0].attackDecay = 0x00
        sid.voices[0].rateCounter = 8

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeState, .decay)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0x88)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 1)
        XCTAssertEqual(sid.voices[0].exponentialPeriod, 2)

        sid.voices[0].rateCounter = 8
        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeState, .decay)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0x87)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
        XCTAssertEqual(sid.voices[0].exponentialPeriod, 2)
    }

    func testReleaseHoldsZeroAfterEnvelopeReachesSilence() {
        let sid = SID()
        sid.voices[0].envelopeState = .release
        sid.voices[0].envelopeLevel = 1
        sid.voices[0].exponentialPeriod = 1
        sid.voices[0].sustainRelease = 0x00
        sid.voices[0].rateCounter = 8

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeLevel, 0)
        XCTAssertTrue(sid.voices[0].holdZero)

        sid.voices[0].rateCounter = 8
        sid.voices[0].exponentialCounter = 0
        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeLevel, 0)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
    }

    func testGateAttackClearsHoldZeroAndExponentialDelay() {
        let sid = SID()
        sid.voices[0].control = 0x01
        sid.voices[0].holdZero = true
        sid.voices[0].envelopeState = .release
        sid.voices[0].exponentialCounter = 12
        sid.voices[0].exponentialPeriod = 30

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeState, .attack)
        XCTAssertFalse(sid.voices[0].holdZero)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
        XCTAssertEqual(sid.voices[0].exponentialPeriod, 1)
    }

    func testZeroEnvelopeVoiceContributesSilenceToWaveformOutput() {
        let sid = SID()
        sid.voices[0].control = 0x20
        sid.voices[0].accumulator = 0xFFFFFF
        sid.voices[0].envelopeLevel = 0

        XCTAssertEqual(sid.waveformOutput(0), 0)
    }

    func testVoiceWithNoWaveformSelectedContributesSilence() {
        let sid = SID()
        sid.voices[0].control = 0x01
        sid.voices[0].accumulator = 0xFFFFFF
        sid.voices[0].envelopeLevel = 0xFF

        XCTAssertEqual(sid.waveformOutput(0), 0)
    }

    func testNoWaveformVoiceDoesNotCreateNegativeMixedSample() {
        let sid = SID()
        sid.model = .mos8580
        sid.voices[0].control = 0x01
        sid.voices[0].accumulator = 0xFFFFFF
        sid.voices[0].envelopeLevel = 0xFF
        sid.writeRegister(0x18, value: 0x0F)

        sid.generateSample()

        XCTAssertGreaterThanOrEqual(sid.sampleBuffer[0], 0)
        XCTAssertLessThan(sid.sampleBuffer[0], 0.02)
    }

    func testWaveformDACLatchHoldsLastOutputBrieflyAfterWaveformDisabled() {
        let sid = SID()
        sid.voices[0].control = 0x20
        sid.voices[0].accumulator = 0xF00000
        sid.voices[0].frequency = 0
        sid.voices[0].envelopeLevel = 0xFF

        sid.clockOscillator(0)

        XCTAssertEqual(sid.voices[0].waveformDACOutput, 0xF00)
        XCTAssertEqual(sid.voices[0].waveformDACHoldCyclesRemaining, SID.waveformDACHoldCycles)

        sid.voices[0].control = 0
        XCTAssertGreaterThan(sid.waveformOutput(0), 0)

        sid.clockOscillator(0)

        XCTAssertEqual(sid.voices[0].waveformDACOutput, 0xF00)
        XCTAssertEqual(sid.voices[0].waveformDACHoldCyclesRemaining, SID.waveformDACHoldCycles - 1)
        XCTAssertGreaterThan(sid.waveformOutput(0), 0)
    }

    func testWaveformDACLatchExpiresAfterFloatingWindow() {
        let sid = SID()
        sid.voices[0].control = 0x20
        sid.voices[0].accumulator = 0xF00000
        sid.voices[0].frequency = 0
        sid.voices[0].envelopeLevel = 0xFF

        sid.clockOscillator(0)
        sid.voices[0].control = 0

        for _ in 0..<SID.waveformDACHoldCycles {
            sid.clockOscillator(0)
        }

        XCTAssertEqual(sid.voices[0].waveformDACOutput, 0)
        XCTAssertEqual(sid.voices[0].waveformDACHoldCyclesRemaining, 0)
        XCTAssertEqual(sid.waveformOutput(0), 0)
    }

    func testTestBitDoesNotRefreshWaveformDACLatch() {
        let sid = SID()
        sid.voices[0].control = 0x20
        sid.voices[0].accumulator = 0xF00000
        sid.voices[0].frequency = 0
        sid.voices[0].envelopeLevel = 0xFF

        sid.clockOscillator(0)
        sid.voices[0].control = 0x28
        sid.clockOscillator(0)

        XCTAssertEqual(sid.voices[0].accumulator, 0)
        XCTAssertEqual(sid.voices[0].waveformDACOutput, 0xF00)
        XCTAssertEqual(sid.voices[0].waveformDACHoldCyclesRemaining, SID.waveformDACHoldCycles - 1)
    }

    func test6581VolumeDACUsesNonLinearSteps() {
        let lowStep = SID.volumeDAC6581[2] - SID.volumeDAC6581[1]
        let highStep = SID.volumeDAC6581[15] - SID.volumeDAC6581[14]

        XCTAssertEqual(SID.volumeDAC6581.first, 0)
        XCTAssertTrue(zip(SID.volumeDAC6581, SID.volumeDAC6581.dropFirst()).allSatisfy { $0 < $1 })
        XCTAssertGreaterThan(highStep, lowStep * 4)
    }

    func test8580VolumeDACIsNearLinearAndSmallerThan6581() {
        let steps = zip(SID.volumeDAC8580, SID.volumeDAC8580.dropFirst()).map { $1 - $0 }

        XCTAssertEqual(SID.volumeDAC8580.first, 0)
        XCTAssertTrue(steps.allSatisfy { (18...22).contains($0) })
        XCTAssertLessThan(SID.volumeDAC8580[15], SID.volumeDAC6581[15] / 10)
    }

    func testSIDModelsUseDifferentVolumeDACOffsets() {
        let sid6581 = SID()
        sid6581.model = .mos6581
        sid6581.writeRegister(0x18, value: 0x0F)

        let sid8580 = SID()
        sid8580.model = .mos8580
        sid8580.writeRegister(0x18, value: 0x0F)

        sid6581.generateSample()
        sid8580.generateSample()

        let sample6581 = sid6581.sampleBuffer[0]
        let sample8580 = sid8580.sampleBuffer[0]
        XCTAssertGreaterThan(sample6581, 0)
        XCTAssertGreaterThan(sample8580, 0)
        XCTAssertGreaterThan(sample6581, sample8580 * 5)
    }

    func testFilterRoutingProcessesSelectedVoicesInsteadOfPassingThrough() {
        let direct = SID()
        direct.voices[0].control = 0x20
        direct.voices[0].accumulator = 0xFFFFFF
        direct.voices[0].envelopeLevel = 0xFF
        direct.writeRegister(0x18, value: 0x0F)

        let filtered = SID()
        filtered.voices[0].control = 0x20
        filtered.voices[0].accumulator = 0xFFFFFF
        filtered.voices[0].envelopeLevel = 0xFF
        filtered.writeRegister(0x15, value: 0x00)
        filtered.writeRegister(0x16, value: 0x08)
        filtered.writeRegister(0x17, value: 0x01)
        filtered.writeRegister(0x18, value: 0x1F)

        direct.generateSample()
        filtered.generateSample()

        XCTAssertGreaterThan(direct.sampleBuffer[0], 0.9)
        XCTAssertLessThan(filtered.sampleBuffer[0], direct.sampleBuffer[0] * 0.25)
        XCTAssertNotEqual(filtered.filterBand, 0)
    }

    func testFilterCutoffResponseDiffersBySIDModel() {
        let sid6581 = SID()
        sid6581.model = .mos6581
        sid6581.writeRegister(0x15, value: 0x00)
        sid6581.writeRegister(0x16, value: 0x40)
        sid6581.writeRegister(0x17, value: 0x01)
        sid6581.writeRegister(0x18, value: 0x20)

        let sid8580 = SID()
        sid8580.model = .mos8580
        sid8580.writeRegister(0x15, value: 0x00)
        sid8580.writeRegister(0x16, value: 0x40)
        sid8580.writeRegister(0x17, value: 0x01)
        sid8580.writeRegister(0x18, value: 0x20)

        let response6581 = sid6581.applyFilter(input: 20_000)
        let response8580 = sid8580.applyFilter(input: 20_000)

        XCTAssertGreaterThan(response8580, response6581)
    }

    func testFilterResonanceDampingDiffersBySIDModel() {
        let sid6581 = SID()
        sid6581.model = .mos6581
        sid6581.writeRegister(0x17, value: 0xF1)

        let sid8580 = SID()
        sid8580.model = .mos8580
        sid8580.writeRegister(0x17, value: 0xF1)

        XCTAssertGreaterThan(sid6581.filterDamping, sid8580.filterDamping)
        XCTAssertEqual(sid6581.filterDamping, 0.775, accuracy: 0.0001)
        XCTAssertEqual(sid8580.filterDamping, 0.275, accuracy: 0.0001)
    }

    func testRoutedVoiceIsSilentWhenNoFilterModeIsSelected() {
        let sid = SID()
        sid.model = .mos8580
        sid.voices[0].control = 0x20
        sid.voices[0].accumulator = 0xFFFFFF
        sid.voices[0].envelopeLevel = 0xFF
        sid.writeRegister(0x17, value: 0x01)
        sid.writeRegister(0x18, value: 0x0F)

        sid.generateSample()

        XCTAssertLessThan(sid.sampleBuffer[0], 0.02)
        XCTAssertNotEqual(sid.filterBand, 0)
        XCTAssertFalse(sid.filterModeSelected)
    }

    func testVoice3OffMutesDirectVoiceButNotFilteredVoice3Path() {
        let mutedDirect = SID()
        mutedDirect.model = .mos8580
        mutedDirect.voices[2].control = 0x20
        mutedDirect.voices[2].accumulator = 0xFFFFFF
        mutedDirect.voices[2].envelopeLevel = 0xFF
        mutedDirect.writeRegister(0x18, value: 0x8F)

        let filteredVoice3 = SID()
        filteredVoice3.model = .mos8580
        filteredVoice3.voices[2].control = 0x20
        filteredVoice3.voices[2].accumulator = 0xFFFFFF
        filteredVoice3.voices[2].envelopeLevel = 0xFF
        filteredVoice3.writeRegister(0x17, value: 0x04)
        filteredVoice3.writeRegister(0x18, value: 0xCF)

        mutedDirect.generateSample()
        filteredVoice3.generateSample()

        XCTAssertLessThan(mutedDirect.sampleBuffer[0], 0.02)
        XCTAssertGreaterThan(filteredVoice3.sampleBuffer[0], 0.8)
    }

    func testExternalAudioInputMixesDirectWhenNotFiltered() {
        let sid = SID()
        sid.model = .mos8580
        sid.setExternalAudioInput(12_000)
        sid.writeRegister(0x18, value: 0x0F)

        sid.generateSample()

        XCTAssertGreaterThan(sid.sampleBuffer[0], 0.25)
    }

    func testExternalAudioInputIsClampedToAudioRange() {
        let sid = SID()

        sid.setExternalAudioInput(100_000)
        XCTAssertEqual(sid.externalAudioInput, 32767)

        sid.setExternalAudioInput(-100_000)
        XCTAssertEqual(sid.externalAudioInput, -32768)
    }

    func testExternalAudioInputRoutesThroughFilterWhenEnabled() {
        let direct = SID()
        direct.model = .mos8580
        direct.setExternalAudioInput(12_000)
        direct.writeRegister(0x18, value: 0x0F)

        let filtered = SID()
        filtered.model = .mos8580
        filtered.setExternalAudioInput(12_000)
        filtered.writeRegister(0x15, value: 0x00)
        filtered.writeRegister(0x16, value: 0x08)
        filtered.writeRegister(0x17, value: 0x08)
        filtered.writeRegister(0x18, value: 0x1F)

        direct.generateSample()
        filtered.generateSample()

        XCTAssertLessThan(filtered.sampleBuffer[0], direct.sampleBuffer[0] * 0.25)
        XCTAssertNotEqual(filtered.filterBand, 0)
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

    func testNoiseShiftRegisterClocksOnAccumulatorBit19RisingEdge() {
        let sid = SID()
        sid.voices[0].accumulator = 0x07FFFF
        sid.voices[0].frequency = 1
        sid.voices[0].shiftRegister = 0x400000

        sid.clockOscillator(0)

        XCTAssertTrue(sid.noiseClockRose[0])
        XCTAssertEqual(sid.voices[0].shiftRegister, 1)
        XCTAssertFalse(sid.oscillatorMSBRose[0])
    }

    func testNoiseShiftRegisterDoesNotClockOnAccumulatorMSBOnly() {
        let sid = SID()
        sid.voices[0].accumulator = 0x7FFFFF
        sid.voices[0].frequency = 1
        sid.voices[0].shiftRegister = 0x400000

        sid.clockOscillator(0)

        XCTAssertTrue(sid.oscillatorMSBRose[0])
        XCTAssertFalse(sid.noiseClockRose[0])
        XCTAssertEqual(sid.voices[0].shiftRegister, 0x400000)
    }

    func testTestBitImmediatelyResetsOscillatorState() {
        let sid = SID()
        sid.voices[2].control = 0x20
        sid.voices[2].accumulator = 0xFFFFFF
        sid.voices[2].shiftRegister = 0x123456
        sid.oscillatorMSBRose[2] = true
        sid.noiseClockRose[2] = true

        sid.writeRegister(0x12, value: 0x08)

        XCTAssertEqual(sid.voices[2].accumulator, 0)
        XCTAssertEqual(sid.voices[2].shiftRegister, 0)
        XCTAssertFalse(sid.oscillatorMSBRose[2])
        XCTAssertFalse(sid.noiseClockRose[2])
        XCTAssertEqual(sid.readRegister(0x1B), 0)
    }

    func testHoldingTestBitKeepsNoiseShiftRegisterCleared() {
        let sid = SID()
        sid.voices[0].frequency = 0xFFFF
        sid.writeRegister(0x04, value: 0x88)

        sid.clockOscillator(0)
        sid.clockOscillator(0)

        XCTAssertEqual(sid.voices[0].accumulator, 0)
        XCTAssertEqual(sid.voices[0].shiftRegister, 0)
        XCTAssertEqual(sid.oscillatorOutput(0), 0)
    }

    func testReleasingTestBitSeedsNoiseShiftRegister() {
        let sid = SID()
        sid.writeRegister(0x04, value: 0x88)
        XCTAssertEqual(sid.voices[0].shiftRegister, 0)

        sid.writeRegister(0x04, value: 0x80)

        XCTAssertEqual(sid.voices[0].shiftRegister, 0x7FFFF8)
        XCTAssertNotEqual(sid.oscillatorOutput(0), 0)
    }
}
