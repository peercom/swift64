import XCTest
@testable import C64Core

/// Regressions for the measurement-derived SID filter model: per-model cutoff
/// curves, resonance peaking, routing bits, the 6581's chip-range parameter
/// and level-dependent cutoff, and the C64 board output network.
final class SIDFilterCalibrationTests: XCTestCase {
    private func configuredSID(model: SID.Model, mode: SID.AccuracyMode = .fast, cutoff: UInt16, resonance: UInt8, volumeFilter: UInt8) -> SID {
        let sid = SID()
        sid.model = model
        sid.accuracyMode = mode
        sid.writeRegister(0x15, value: UInt8(cutoff & 0x07))
        sid.writeRegister(0x16, value: UInt8(cutoff >> 3))
        sid.writeRegister(0x17, value: (resonance << 4) | 0x01)
        sid.writeRegister(0x18, value: volumeFilter)
        return sid
    }

    /// Drives the filter cycle by cycle with a sine and returns the ratio of
    /// output to input AC RMS after the filter has settled. The output mean is
    /// removed so the 6581's routed-voice DC does not count as gain.
    private func measuredGain(_ sid: SID, toneHz: Double, amplitude: Double = 4_000) -> Double {
        let cyclesPerPeriod = sid.clockRate / toneHz
        let settleCycles = Int(max(20 * cyclesPerPeriod, 40_000))
        let measureCycles = Int(max(20 * cyclesPerPeriod, 40_000))
        var inputSquares = 0.0
        var outputSquares = 0.0
        var outputSum = 0.0
        for cycle in 0..<(settleCycles + measureCycles) {
            let input = amplitude * sin(2 * .pi * toneHz * Double(cycle) / sid.clockRate)
            let output = Double(sid.applyFilter(input: Int32(input.rounded())))
            if cycle >= settleCycles {
                inputSquares += input * input
                outputSquares += output * output
                outputSum += output
            }
        }
        let count = Double(measureCycles)
        let outputVariance = max(0, outputSquares / count - pow(outputSum / count, 2))
        return (outputVariance / (inputSquares / count)).squareRoot()
    }

    func testCutoffTablesHitPublishedAnchorsAndStayMonotonic() {
        for model in [SID.Model.mos6581, .mos8580] {
            let sid = SID()
            sid.model = model
            let anchors = model == .mos6581 ? SID.cutoffAnchors6581 : SID.cutoffAnchors8580
            for anchor in anchors {
                XCTAssertEqual(sid.filterCutoffFrequency(for: UInt16(anchor.fc)), anchor.hz, accuracy: 0.001, "\(model) FC \(anchor.fc)")
            }
            var previous = 0.0
            for fc in 0...2047 {
                let frequency = sid.filterCutoffFrequency(for: UInt16(fc))
                XCTAssertGreaterThanOrEqual(frequency, previous, "\(model) FC \(fc)")
                previous = frequency
            }
        }

        // 6581: flat floor below FC 512, steep knee, published 220 Hz-18 kHz span.
        let sid6581 = SID()
        sid6581.model = .mos6581
        XCTAssertEqual(sid6581.filterCutoffFrequency(for: 0), 220)
        XCTAssertLessThan(sid6581.filterCutoffFrequency(for: 512) / sid6581.filterCutoffFrequency(for: 0), 2)
        XCTAssertGreaterThan(sid6581.filterCutoffFrequency(for: 1024) / sid6581.filterCutoffFrequency(for: 512), 10)
        XCTAssertEqual(sid6581.filterCutoffFrequency(for: 2047), 18_000)

        // 8580: near-linear 11-bit control up to 12.5 kHz, 30 Hz datasheet floor.
        let sid8580 = SID()
        sid8580.model = .mos8580
        XCTAssertEqual(sid8580.filterCutoffFrequency(for: 0), 30)
        XCTAssertEqual(sid8580.filterCutoffFrequency(for: 2047), 12_500)
        let slopeLow = sid8580.filterCutoffFrequency(for: 512) - sid8580.filterCutoffFrequency(for: 256)
        let slopeHigh = sid8580.filterCutoffFrequency(for: 1792) - sid8580.filterCutoffFrequency(for: 1536)
        XCTAssertEqual(slopeHigh / slopeLow, 1, accuracy: 0.35, "8580 slope stays within a third of linear")
        XCTAssertGreaterThan(sid8580.filterCutoffFrequency(for: 512), sid6581.filterCutoffFrequency(for: 512) * 5)
    }

    func testLowPassCutoffFrequencyMatchesTableAtSeveralRegisterValues() {
        // At RES 0 the filter is Butterworth: -3 dB at the cutoff and
        // 1/sqrt(17) (about -12.3 dB) one octave above it.
        let cases: [(SID.Model, UInt16)] = [
            (.mos6581, 512), (.mos6581, 1024), (.mos6581, 1536),
            (.mos8580, 256), (.mos8580, 1024), (.mos8580, 2047)
        ]
        for (model, cutoff) in cases {
            let sid = configuredSID(model: model, cutoff: cutoff, resonance: 0, volumeFilter: 0x1F)
            let fc = sid.filterCutoffFrequency
            XCTAssertEqual(measuredGain(sid, toneHz: fc), 1 / 2.0.squareRoot(), accuracy: 0.04, "\(model) FC \(cutoff) at \(fc) Hz")
            XCTAssertEqual(measuredGain(sid, toneHz: fc * 2), 1 / 17.0.squareRoot(), accuracy: 0.04, "\(model) FC \(cutoff) at \(2 * fc) Hz")
            XCTAssertEqual(measuredGain(sid, toneHz: fc / 4), 1, accuracy: 0.04, "\(model) FC \(cutoff) passband")
        }
    }

    func testHighPassMirrorsLowPassAroundCutoff() {
        for model in [SID.Model.mos6581, .mos8580] {
            let sid = configuredSID(model: model, cutoff: 1024, resonance: 0, volumeFilter: 0x4F)
            let fc = sid.filterCutoffFrequency
            XCTAssertEqual(measuredGain(sid, toneHz: fc), 1 / 2.0.squareRoot(), accuracy: 0.04, "\(model)")
            XCTAssertEqual(measuredGain(sid, toneHz: fc / 2), 1 / 17.0.squareRoot(), accuracy: 0.04, "\(model)")
            XCTAssertEqual(measuredGain(sid, toneHz: fc * 4), 1, accuracy: 0.04, "\(model)")
        }
    }

    func testBandPassGainAtCutoffEqualsModelQ() {
        // The band-pass output of a two-integrator loop peaks at Q times the
        // input at the cutoff: 0.707 at RES 0 on both chips, 1.7 (6581) and
        // 4.0 (8580) at RES 15.
        for model in [SID.Model.mos6581, .mos8580] {
            for resonance: UInt8 in [0, 8, 15] {
                let sid = configuredSID(model: model, cutoff: 1024, resonance: resonance, volumeFilter: 0x2F)
                let gain = measuredGain(sid, toneHz: sid.filterCutoffFrequency, amplitude: 2_000)
                XCTAssertEqual(gain, sid.filterQ, accuracy: sid.filterQ * 0.06, "\(model) RES \(resonance)")
            }
        }
        let sid6581 = configuredSID(model: .mos6581, cutoff: 1024, resonance: 15, volumeFilter: 0x2F)
        let sid8580 = configuredSID(model: .mos8580, cutoff: 1024, resonance: 15, volumeFilter: 0x2F)
        XCTAssertEqual(sid6581.filterQ, 1.7, accuracy: 0.0001)
        XCTAssertEqual(sid8580.filterQ, 4.0, accuracy: 0.0001)
        XCTAssertGreaterThan(sid8580.filterQ, sid6581.filterQ)
    }

    func testResonanceSharpensLowPassPeakNearCutoff() {
        for model in [SID.Model.mos6581, .mos8580] {
            let flat = configuredSID(model: model, cutoff: 1024, resonance: 0, volumeFilter: 0x1F)
            let peaked = configuredSID(model: model, cutoff: 1024, resonance: 15, volumeFilter: 0x1F)
            let fc = flat.filterCutoffFrequency
            XCTAssertGreaterThan(measuredGain(peaked, toneHz: fc), 1.3, "\(model) RES 15 peaks above unity")
            XCTAssertLessThan(measuredGain(flat, toneHz: fc), 0.75, "\(model) RES 0 does not peak")
            XCTAssertEqual(measuredGain(peaked, toneHz: fc / 8), 1, accuracy: 0.05, "\(model) low passband unchanged")
        }
    }

    func testFilterRoutingBitsSelectEachSourceIndependently() {
        for bit in 0..<3 {
            let sid = SID()
            sid.model = .mos8580
            for voice in 0..<3 {
                sid.voices[voice].control = 0x20
                sid.voices[voice].accumulator = 0xFFFFFF
                sid.voices[voice].envelopeLevel = 0xFF
            }
            sid.setExternalAudioInput(0)
            sid.writeRegister(0x17, value: UInt8(1 << bit))
            sid.writeRegister(0x18, value: 0x1F)

            _ = sid.mixedAudioOutput()

            let voiceOut = Int32(sid.waveformOutput(bit)) / SID.voiceMixDivisor
            XCTAssertEqual(sid.lastFilterInput, voiceOut, "FILT\(bit + 1) routes only voice \(bit + 1)")
            XCTAssertEqual(sid.lastDirectOutput, 3 * voiceOut - voiceOut, "the other two voices stay direct")
        }

        let external = SID()
        external.model = .mos8580
        external.setExternalAudioInput(9_000)
        external.writeRegister(0x17, value: 0x08)
        external.writeRegister(0x18, value: 0x1F)
        _ = external.mixedAudioOutput()
        XCTAssertEqual(external.lastFilterInput, 9_000)
        XCTAssertEqual(external.lastDirectOutput, 0)
    }

    func test6581ChipRangeParameterRescalesTheCurveOnTheMeasuredFloor() {
        let sid = SID()
        sid.model = .mos6581
        let referenceMid = sid.filterCutoffFrequency(for: 1024)

        sid.filterMaximumCutoff6581 = 9_000
        XCTAssertEqual(sid.filterCutoffFrequency(for: 0), 220, accuracy: 0.001)
        XCTAssertEqual(sid.filterCutoffFrequency(for: 2047), 9_000, accuracy: 0.001)
        XCTAssertLessThan(sid.filterCutoffFrequency(for: 1024), referenceMid)
        XCTAssertGreaterThan(sid.filterCutoffFrequency(for: 1024), 1_000)

        sid.filterMaximumCutoff6581 = 20_000
        XCTAssertEqual(sid.filterCutoffFrequency(for: 2047), 20_000, accuracy: 0.001)
        XCTAssertGreaterThan(sid.filterCutoffFrequency(for: 1024), referenceMid)

        sid.filterMaximumCutoff6581 = 1
        XCTAssertEqual(sid.filterMaximumCutoff6581, SID.filterMaximumCutoff6581Range.lowerBound)
        sid.filterMaximumCutoff6581 = 1_000_000
        XCTAssertEqual(sid.filterMaximumCutoff6581, SID.filterMaximumCutoff6581Range.upperBound)

        // The 8580 curve is fixed; the parameter is a 6581 property.
        sid.model = .mos8580
        XCTAssertEqual(sid.filterCutoffFrequency(for: 2047), 12_500)

        // Reset keeps the chip parameter like the model and clock.
        sid.filterMaximumCutoff6581 = 9_000
        sid.reset()
        XCTAssertEqual(sid.filterMaximumCutoff6581, 9_000)
    }

    func test6581ChipRangeAndBoardFilterStateSurviveSnapshots() throws {
        let source = C64()
        source.sid.accuracyMode = .compatibility
        source.sid.filterMaximumCutoff6581 = 12_000
        source.sid.externalFilterLowPassState = 123.5
        source.sid.externalFilterHighPassState = -45.25
        source.sid.filterLevelState = 678.125
        let data = try source.saveState()

        let restored = C64()
        try restored.restoreState(from: data)
        XCTAssertEqual(restored.sid.filterMaximumCutoff6581, 12_000)
        XCTAssertEqual(restored.sid.filterCutoffFrequency(for: 2047), 12_000, accuracy: 0.001)
        XCTAssertEqual(restored.sid.externalFilterLowPassState, 123.5)
        XCTAssertEqual(restored.sid.externalFilterHighPassState, -45.25)
        XCTAssertEqual(restored.sid.filterLevelState, 678.125)

        source.sid.reset()
        XCTAssertEqual(source.sid.filterLevelState, 0)
        XCTAssertEqual(source.sid.externalFilterLowPassState, 0)
    }

    func test6581CompatibilityCutoffRisesWithIntegratorLevel() {
        // Above the cutoff a louder signal passes more low-pass energy on the
        // 6581 because the FET resistors let the cutoff drift upward. The
        // 8580 filter is linear, so fast and compatibility agree.
        for model in [SID.Model.mos6581, .mos8580] {
            let fast = configuredSID(model: model, mode: .fast, cutoff: 1024, resonance: 0, volumeFilter: 0x1F)
            let compatibility = configuredSID(model: model, mode: .compatibility, cutoff: 1024, resonance: 0, volumeFilter: 0x1F)
            let tone = fast.filterCutoffFrequency * 2
            let fastGain = measuredGain(fast, toneHz: tone, amplitude: 24_000)
            let compatibilityGain = measuredGain(compatibility, toneHz: tone, amplitude: 24_000)
            switch model {
            case .mos6581:
                XCTAssertGreaterThan(compatibilityGain, fastGain * 1.10, "6581 cutoff rises with level")
                XCTAssertGreaterThan(compatibility.filterLevelState, 3_000)
            case .mos8580:
                XCTAssertEqual(compatibilityGain, fastGain, accuracy: 0.002, "8580 filter stays linear")
                XCTAssertEqual(compatibility.filterLevelState, 0)
            }
        }

        // Small signals leave the 6581 cutoff essentially where the table says.
        let quiet = configuredSID(model: .mos6581, mode: .compatibility, cutoff: 1024, resonance: 0, volumeFilter: 0x1F)
        XCTAssertEqual(measuredGain(quiet, toneHz: quiet.filterCutoffFrequency, amplitude: 500), 1 / 2.0.squareRoot(), accuracy: 0.05)
    }

    func test6581RoutedVoiceCarriesDCThroughLowPassButNotHighPass() {
        let lowPass = configuredSID(model: .mos6581, mode: .compatibility, cutoff: 1024, resonance: 0, volumeFilter: 0x1F)
        let highPass = configuredSID(model: .mos6581, mode: .compatibility, cutoff: 1024, resonance: 0, volumeFilter: 0x4F)
        let perVoice = lowPass.analogProfile.filterInputDCOffsetPerSource
        var lowPassOutput: Int32 = 0
        var highPassOutput: Int32 = 0
        for _ in 0..<20_000 {
            lowPassOutput = lowPass.applyFilter(input: 0)
            highPassOutput = highPass.applyFilter(input: 0)
        }
        XCTAssertEqual(Double(lowPassOutput), perVoice, accuracy: 2)
        XCTAssertEqual(highPassOutput, 0)

        let unrouted = SID()
        unrouted.model = .mos6581
        unrouted.accuracyMode = .compatibility
        unrouted.writeRegister(0x18, value: 0x1F)
        for _ in 0..<2_000 { _ = unrouted.mixedAudioOutput() }
        XCTAssertEqual(unrouted.lastFilterInput, 0)
        XCTAssertEqual(unrouted.filterLow, 0)
    }

    func testBoardOutputNetworkCornersFollowTheRCValues() {
        XCTAssertEqual(SID.externalFilterLowPassCorner, 15_915.5, accuracy: 0.1)
        XCTAssertEqual(SID.externalFilterHighPassCorner, 15.9155, accuracy: 0.001)

        func gain(toneHz: Double) -> Double {
            let sid = SID()
            sid.accuracyMode = .compatibility
            let cyclesPerPeriod = sid.clockRate / toneHz
            let settle = Int(max(4 * cyclesPerPeriod, 200_000))
            let measure = Int(max(4 * cyclesPerPeriod, 100_000))
            var inputSquares = 0.0
            var outputSquares = 0.0
            for cycle in 0..<(settle + measure) {
                let input = 8_000 * sin(2 * .pi * toneHz * Double(cycle) / sid.clockRate)
                let output = Double(sid.applyExternalFilter(input: Int32(input.rounded())))
                if cycle >= settle {
                    inputSquares += input * input
                    outputSquares += output * output
                }
            }
            return (outputSquares / inputSquares).squareRoot()
        }

        XCTAssertEqual(gain(toneHz: SID.externalFilterLowPassCorner), 1 / 2.0.squareRoot(), accuracy: 0.03)
        XCTAssertEqual(gain(toneHz: 1_000), 1, accuracy: 0.03)
        XCTAssertEqual(gain(toneHz: SID.externalFilterHighPassCorner), 1 / 2.0.squareRoot(), accuracy: 0.05)
        XCTAssertLessThan(gain(toneHz: 4), 0.3)
    }

    func testFastModeSkipsCompatibilityOnlyAnalogStages() {
        let sid = configuredSID(model: .mos6581, mode: .fast, cutoff: 1024, resonance: 15, volumeFilter: 0x1F)
        XCTAssertEqual(sid.applyExternalFilter(input: 5_000, elapsedCycles: sid.cyclesPerSample), 5_000)
        XCTAssertEqual(sid.filterInputDrive(5_000), 5_000)
        XCTAssertEqual(sid.externalFilterLowPassState, 0)
        XCTAssertEqual(sid.externalFilterHighPassState, 0)
    }
}
