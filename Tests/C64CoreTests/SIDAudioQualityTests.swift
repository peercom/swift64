import XCTest
@testable import C64Core

final class SIDAudioQualityTests: XCTestCase {
    func testSpeakerStatisticsDetectDroppedSourceSamplesAndReset() {
        let sid = SID()
        let output = SIDAudioOutput(sid: sid, startupTarget: 0)
        let capacity = sid.sampleBuffer.count
        for _ in 0..<capacity { sid.writeSample(0) }
        XCTAssertEqual(output.statistics.overrunFrames, 0)
        for _ in 0..<17 { sid.writeSample(0) }
        XCTAssertEqual(output.statistics.overrunFrames, 17)
        var block = [Float](repeating: 0, count: 32)
        block.withUnsafeMutableBufferPointer { output.render(into: $0) }
        for _ in 0..<32 { sid.writeSample(0) }
        XCTAssertEqual(output.statistics.overrunFrames, 17)
        XCTAssertEqual(output.statistics.underrunFrames, 0)
        sid.reset()
        XCTAssertEqual(output.statistics.overrunFrames, 0)
    }

    func testPacingRefillsAfterSchedulingGapWithoutPermanentOverspeed() {
        var pacer = AudioFramePacer(now: 0)
        XCTAssertEqual(pacer.delay(now: 0.010, frameDuration: 0.020, bufferedSamples: 3000,
                                   targetSamples: 2048, playbackStarted: true), 0.010, accuracy: 0.000001)
        XCTAssertEqual(pacer.delay(now: 0.050, frameDuration: 0.020, bufferedSamples: 1000,
                                   targetSamples: 2048, playbackStarted: true), 0)
        XCTAssertEqual(pacer.delay(now: 0.060, frameDuration: 0.020, bufferedSamples: 1800,
                                   targetSamples: 2048, playbackStarted: true), 0)
        XCTAssertEqual(pacer.delay(now: 0.070, frameDuration: 0.020, bufferedSamples: 2600,
                                   targetSamples: 2048, playbackStarted: true), 0.010, accuracy: 0.000001)
        pacer.reset(now: 1)
        XCTAssertEqual(pacer.delay(now: 1.010, frameDuration: 0.020, bufferedSamples: 0,
                                   targetSamples: 2048, playbackStarted: false), 0.010, accuracy: 0.000001)
    }

    func testOriginalMusicProgramProducesChangingThreeVoiceAudio() {
        for model in [SID.Model.mos6581, .mos8580] {
            for mode in [SID.AccuracyMode.fast, .compatibility] {
                let c64 = C64()
                c64.vic.recordsBusAccessTraces = false
                c64.sidModelOverride = model
                c64.sid.accuracyMode = mode
                c64.powerOn()
                c64.loadPRG(SIDSoundCheck.program(kind: .music, clockRate: c64.sid.clockRate))
                c64.cpu.powerOn()
                c64.cpu.pc = SIDSoundCheck.entryPoint
                var frequencyWrites = [Int](repeating: 0, count: 3)
                c64.onSIDRegisterWriteTrace = { event in
                    if [0, 7, 14].contains(event.register) { frequencyWrites[Int(event.register) / 7] += 1 }
                }
                let output = SIDAudioOutput(sid: c64.sid, startupTarget: 256)
                var samples = [Float](repeating: 0, count: 1024)
                var squares = 0.0
                for _ in 0..<36 {
                    XCTAssertTrue(c64.runFrame())
                    let available = c64.sid.availableAudioSamplesForPlayback()
                    XCTAssertLessThanOrEqual(available, samples.count)
                    samples.withUnsafeMutableBufferPointer {
                        output.render(into: UnsafeMutableBufferPointer(rebasing: $0.prefix(min(available, $0.count))))
                    }
                    for sample in samples.prefix(min(available, samples.count)) { squares += Double(sample * sample) }
                }
                XCTAssertTrue(frequencyWrites.allSatisfy { $0 >= 4 }, "\(model) \(mode): \(frequencyWrites)")
                XCTAssertGreaterThan(sqrt(squares / Double(output.statistics.sourceFrames)), 0.05)
                XCTAssertEqual(output.statistics.underrunFrames, 0)
                XCTAssertEqual(output.statistics.clippedFrames, 0)
                XCTAssertGreaterThanOrEqual(c64.cpu.pc, SIDSoundCheck.entryPoint)
                XCTAssertLessThan(c64.cpu.pc, SIDSoundCheck.entryPoint + 1024)
            }
        }
    }

    func testKnownTonePitchAndHeadroomAcrossModelsAndModes() {
        for model in [SID.Model.mos6581, .mos8580] {
            for mode in [SID.AccuracyMode.fast, .compatibility] {
                for control: UInt8 in [0x11, 0x21, 0x41] {
                    for frequency in [110.0, 440.0, 1760.0] {
                        let sid = SID()
                        sid.model = model
                        sid.accuracyMode = mode
                        let word = UInt16((frequency * 16_777_216 / sid.clockRate).rounded())
                        sid.writeRegister(0, value: UInt8(truncatingIfNeeded: word))
                        sid.writeRegister(1, value: UInt8(word >> 8))
                        sid.writeRegister(3, value: 8)
                        sid.writeRegister(5, value: 0)
                        sid.writeRegister(6, value: 0xF0)
                        sid.writeRegister(4, value: control)
                        sid.writeRegister(0x18, value: 15)
                        var samples: [Float] = []
                        sid.onSampleGenerated = { samples.append($0) }
                        for _ in 0..<Int(sid.clockRate * 0.15) { sid.tick() }
                        sid.onSampleGenerated = nil
                        let stable = Array(samples.dropFirst(2205))
                        let mean = stable.reduce(0.0) { $0 + Double($1) } / Double(stable.count)
                        var crossings = 0
                        for index in 1..<stable.count where Double(stable[index - 1]) < mean && Double(stable[index]) >= mean {
                            crossings += 1
                        }
                        let measured = Double(crossings) * SID.sampleRate / Double(stable.count)
                        let context = "\(model) \(mode) control=\(control) requested=\(frequency) measured=\(measured)"
                        XCTAssertEqual(measured, frequency, accuracy: 11, context)
                        XCTAssertGreaterThan(stable.max()! - stable.min()!, 0.15, context)
                        XCTAssertLessThan(stable.map { abs($0) }.max()!, 0.95, context)
                    }
                }
            }
        }
    }

    func testFastFilterPreservesCyclePathFrequencyResponse() {
        for model in [SID.Model.mos6581, .mos8580] {
            for cutoff: UInt8 in [16, 64, 128, 255] {
                for resonance: UInt8 in [0, 15] {
                    for frequency in [200.0, 2000.0, 6000.0] {
                        let fast = SID()
                        let cycle = SID()
                        for sid in [fast, cycle] {
                            sid.model = model
                            sid.writeRegister(0x16, value: cutoff)
                            sid.writeRegister(0x17, value: (resonance << 4) | 8)
                            sid.writeRegister(0x18, value: 0x1F)
                        }
                        var fastSquares = 0.0
                        var cycleSquares = 0.0
                        var elapsed = 0.0
                        for sample in 0..<2205 {
                            let input = Int32(2000 * sin(2 * .pi * frequency * Double(sample) / SID.sampleRate))
                            let fastValue = fast.applyFilter(input: input, elapsedCycles: fast.cyclesPerSample)
                            elapsed += cycle.cyclesPerSample
                            var cycleValue: Int32 = 0
                            while elapsed >= 1 {
                                cycleValue = cycle.applyFilter(input: input)
                                elapsed -= 1
                            }
                            if sample > 1102 {
                                fastSquares += Double(fastValue) * Double(fastValue)
                                cycleSquares += Double(cycleValue) * Double(cycleValue)
                            }
                        }
                        let ratio = sqrt(fastSquares / max(1, cycleSquares))
                        XCTAssertEqual(ratio, 1, accuracy: 0.25, "\(model) cutoff=\(cutoff) resonance=\(resonance) tone=\(frequency) ratio=\(ratio)")
                    }
                }
            }
        }
    }

    func testSpeakerOutputRecoversWithoutRepeatedPrebufferAndFadesEmptyCallbacks() {
        let sid = SID()
        let output = SIDAudioOutput(sid: sid, startupTarget: 128)
        var block = [Float](repeating: 1, count: 128)
        block.withUnsafeMutableBufferPointer { output.render(into: $0) }
        XCTAssertTrue(block.allSatisfy { $0 == 0 })
        XCTAssertEqual(output.statistics.underrunFrames, 0)
        for index in 0..<128 { sid.writeSample(Int32(index * 100)) }
        block.withUnsafeMutableBufferPointer { output.render(into: $0) }
        let tail = block.last!
        XCTAssertGreaterThan(tail, 0.1)
        block.withUnsafeMutableBufferPointer { output.render(into: $0) }
        XCTAssertEqual(block[0], tail * 63 / 64, accuracy: 0.0001)
        XCTAssertEqual(block[63], 0)
        XCTAssertEqual(output.statistics.underrunEvents, 1)
        for index in 0..<96 { sid.writeSample(Int32(index * 100)) }
        block.withUnsafeMutableBufferPointer { output.render(into: $0) }
        XCTAssertGreaterThan(block[80], 0)
        XCTAssertEqual(output.statistics.sourceFrames, 224)
        XCTAssertEqual(output.statistics.startupFrames, 128)
    }

    func testShortUnderrunAndImmediateRecoveryStayContinuous() {
        let sid = SID()
        let output = SIDAudioOutput(sid: sid, startupTarget: 0)
        var block = [Float](repeating: 0, count: 128)
        for index in 0..<128 { sid.writeSample(Int32(index * 100)) }
        block.withUnsafeMutableBufferPointer { output.render(into: $0) }
        let tail = block.last!
        var gap: Float = 0
        withUnsafeMutablePointer(to: &gap) {
            output.render(into: UnsafeMutableBufferPointer(start: $0, count: 1))
        }
        XCTAssertEqual(gap, tail * 63 / 64, accuracy: 0.0001)
        for _ in 0..<128 { sid.writeSample(-8000) }
        block.withUnsafeMutableBufferPointer { output.render(into: $0) }
        XCTAssertEqual(block[0], gap, accuracy: 0.0001)
        XCTAssertLessThan(block[127], 0)
        XCTAssertEqual(output.statistics.underrunEvents, 1)
        XCTAssertEqual(output.statistics.underrunFrames, 1)
    }

    func testUnderrunPreservesDCFilterHistoryWithoutRecoveryClipping() {
        let continuousSID = SID()
        let interruptedSID = SID()
        let continuous = SIDAudioOutput(sid: continuousSID, startupTarget: 0)
        let interrupted = SIDAudioOutput(sid: interruptedSID, startupTarget: 0)
        for index in 0..<4160 {
            let sample: Int32 = index % 128 < 64 ? 20000 : -20000
            continuousSID.writeSample(sample)
            interruptedSID.writeSample(sample)
        }
        var warmup = [Float](repeating: 0, count: 4160)
        warmup.withUnsafeMutableBufferPointer { continuous.render(into: $0) }
        warmup.withUnsafeMutableBufferPointer { interrupted.render(into: $0) }
        var gap = [Float](repeating: 0, count: 127)
        gap.withUnsafeMutableBufferPointer { interrupted.render(into: $0) }
        for index in 4160..<4672 {
            let sample: Int32 = index % 128 < 64 ? 20000 : -20000
            continuousSID.writeSample(sample)
            interruptedSID.writeSample(sample)
        }
        var reference = [Float](repeating: 0, count: 512)
        var recovered = reference
        reference.withUnsafeMutableBufferPointer { continuous.render(into: $0) }
        recovered.withUnsafeMutableBufferPointer { interrupted.render(into: $0) }
        for index in 64..<512 {
            XCTAssertEqual(recovered[index], reference[index], accuracy: 0.000001)
        }
        XCTAssertEqual(interrupted.statistics.underrunFrames, 127)
        XCTAssertEqual(interrupted.statistics.clippedFrames, continuous.statistics.clippedFrames)
    }

    func testFilterAndEnvelopeLookupTablesPreserveTheAnalogApproximation() {
        let sid = SID()
        for level in 0...255 {
            let expected = UInt16((pow(Double(level) / 255, 0.92) * 255).rounded())
            XCTAssertEqual(sid.envelopeDACLevel(UInt8(level)), expected)
        }
        for cutoff in 0...2047 {
            sid.filterCutoff = UInt16(cutoff)
            XCTAssertEqual(sid.normalizedFilterCutoff, 0.003 + pow(Double(cutoff) / 2047, 1.7) * 0.18)
        }
    }
}
