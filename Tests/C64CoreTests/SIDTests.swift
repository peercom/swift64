import XCTest
@testable import C64Core

final class SIDTests: XCTestCase {
    func testResetClearsVoiceFilterPaddleAndAudioStateButKeepsModelAndClock() {
        let sid = SID()
        sid.model = .mos8580
        sid.accuracyMode = .compatibility
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
        sid.lastDirectOutput = 1
        sid.lastFilterInput = 2
        sid.lastFilterOutput = 3
        sid.lastMixedOutput = 4
        sid.oscillatorMSBRose[1] = true
        sid.noiseClockRose[2] = true
        sid.startPaddleScan(x: 0x40, y: 0x80)

        sid.reset()

        XCTAssertEqual(sid.dataBusLatch, 0)
        XCTAssertEqual(sid.dataBusLatchCyclesRemaining, 0)
        XCTAssertEqual(sid.model, .mos8580)
        XCTAssertEqual(sid.accuracyMode, .compatibility)
        XCTAssertEqual(sid.clockRate, 1_022_727)
        XCTAssertEqual(sid.voices[0].frequency, 0)
        XCTAssertEqual(sid.voices[0].control, 0)
        XCTAssertEqual(sid.voices[0].accumulator, 0)
        XCTAssertEqual(sid.voices[0].shiftRegister, 0x7FFFF8)
        XCTAssertEqual(sid.voices[2].envelopeLevel, 0)
        XCTAssertEqual(sid.readRegister(0x19), 0xFF)
        XCTAssertEqual(sid.readRegister(0x1A), 0xFF)
        XCTAssertEqual(sid.paddleTargetX, 0xFF)
        XCTAssertEqual(sid.paddleTargetY, 0xFF)
        XCTAssertNil(sid.paddleScanCounter)
        XCTAssertEqual(sid.volumeFilter, 0)
        XCTAssertEqual(sid.externalAudioInput, 0)
        XCTAssertEqual(sid.dataBusLatch, 0xFF)
        XCTAssertEqual(sid.dataBusLatchCyclesRemaining, SID.dataBusLatchHoldCycles)
        XCTAssertEqual(sid.oscillator3Readback, 0)
        XCTAssertFalse(sid.oscillator3ReadbackValid)
        XCTAssertEqual(sid.envelope3Readback, 0)
        XCTAssertFalse(sid.envelope3ReadbackValid)
        XCTAssertEqual(sid.sampleBuffer[0], 0)
        XCTAssertEqual(sid.sampleWritePos, 0)
        XCTAssertEqual(sid.lastDirectOutput, 0)
        XCTAssertEqual(sid.lastFilterInput, 0)
        XCTAssertEqual(sid.lastFilterOutput, 0)
        XCTAssertEqual(sid.lastMixedOutput, 0)
        XCTAssertFalse(sid.oscillatorMSBRose.contains(true))
        XCTAssertFalse(sid.noiseClockRose.contains(true))
    }

    func testRecentAudioSignatureSummarizesRecentSamples() {
        let sid = SID()
        sid.sampleBuffer[0] = -0.5
        sid.sampleBuffer[1] = -0.25
        sid.sampleBuffer[2] = 0
        sid.sampleBuffer[3] = 0.25
        sid.sampleBuffer[4] = 0.5
        sid.sampleBuffer[5] = -0.125
        sid.sampleWritePos = 6

        let signature = sid.recentAudioSignature(sampleCount: 6)

        XCTAssertEqual(signature.sampleCount, 6)
        XCTAssertEqual(signature.minimum, -0.5)
        XCTAssertEqual(signature.maximum, 0.5)
        XCTAssertEqual(signature.sum, -0.125, accuracy: 0.000_001)
        XCTAssertEqual(signature.absoluteSum, 1.625, accuracy: 0.000_001)
        XCTAssertEqual(signature.mean, -0.020_833_333, accuracy: 0.000_001)
        XCTAssertEqual(signature.rootMeanSquare, 0.326_758_07, accuracy: 0.000_001)
        XCTAssertEqual(signature.zeroCrossings, 2)
    }

    func testRecentAudioSignatureWrapsAroundRingBuffer() {
        let sid = SID()
        sid.sampleBuffer[sid.sampleBuffer.count - 2] = 0.25
        sid.sampleBuffer[sid.sampleBuffer.count - 1] = -0.25
        sid.sampleBuffer[0] = 0.5
        sid.sampleWritePos = 1

        let signature = sid.recentAudioSignature(sampleCount: 3)

        XCTAssertEqual(signature.sampleCount, 3)
        XCTAssertEqual(signature.minimum, -0.25)
        XCTAssertEqual(signature.maximum, 0.5)
        XCTAssertEqual(signature.sum, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(signature.absoluteSum, 1.0, accuracy: 0.000_001)
        XCTAssertEqual(signature.mean, 0.166_666_667, accuracy: 0.000_001)
        XCTAssertEqual(signature.rootMeanSquare, 0.353_553_391, accuracy: 0.000_001)
        XCTAssertEqual(signature.zeroCrossings, 2)
    }

    func testRecentAudioSignatureBoundsRequestedSampleCount() {
        let sid = SID()

        XCTAssertEqual(
            sid.recentAudioSignature(sampleCount: 0),
            SID.AudioSignature(
                sampleCount: 0,
                minimum: 0,
                maximum: 0,
                sum: 0,
                absoluteSum: 0,
                mean: 0,
                rootMeanSquare: 0,
                zeroCrossings: 0
            )
        )
        XCTAssertEqual(
            sid.recentAudioSignature(sampleCount: sid.sampleBuffer.count + 1).sampleCount,
            sid.sampleBuffer.count
        )
    }

    func testSampleGeneratedCallbackReceivesGeneratedSamples() {
        let sid = SID()
        sid.clockRate = SID.sampleRate
        sid.writeRegister(0x18, value: 0x0F)
        var captured: [Float] = []
        sid.onSampleGenerated = { captured.append($0) }

        sid.tick()

        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured[0], sid.sampleBuffer[0])
    }

    func testPlaybackAudioRingBufferReadsGeneratedSamplesInOrder() {
        let sid = SID()

        sid.writeSample(-32768)
        sid.writeSample(16384)

        XCTAssertEqual(sid.availableAudioSamplesForPlayback(), 2)
        XCTAssertEqual(try XCTUnwrap(sid.readAudioSampleForPlayback()), -1.0, accuracy: 0.000_001)
        XCTAssertEqual(sid.availableAudioSamplesForPlayback(), 1)
        XCTAssertEqual(try XCTUnwrap(sid.readAudioSampleForPlayback()), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(sid.availableAudioSamplesForPlayback(), 0)
        XCTAssertNil(sid.readAudioSampleForPlayback())
    }

    func testPlaybackAudioRingBufferReadsBatchedSamplesAcrossWrap() {
        let sid = SID()
        let capacity = sid.sampleBuffer.count

        for index in 0..<capacity {
            sid.writeSample(Int32(index))
        }
        for _ in 0..<capacity - 3 {
            _ = sid.readAudioSampleForPlayback()
        }
        sid.writeSample(10_000)
        sid.writeSample(12_000)

        var samples = [Float](repeating: 0, count: 5)
        let readCount = samples.withUnsafeMutableBufferPointer {
            sid.readAudioSamplesForPlayback(into: $0)
        }

        XCTAssertEqual(readCount, 5)
        XCTAssertEqual(samples[0], Float(capacity - 3) / 32768.0, accuracy: 0.000_001)
        XCTAssertEqual(samples[1], Float(capacity - 2) / 32768.0, accuracy: 0.000_001)
        XCTAssertEqual(samples[2], Float(capacity - 1) / 32768.0, accuracy: 0.000_001)
        XCTAssertEqual(samples[3], Float(10_000) / 32768.0, accuracy: 0.000_001)
        XCTAssertEqual(samples[4], Float(12_000) / 32768.0, accuracy: 0.000_001)
        XCTAssertEqual(sid.availableAudioSamplesForPlayback(), 0)
    }

    func testPlaybackAudioRingBufferKeepsFullStateDistinctFromEmpty() {
        let sid = SID()

        for index in 0..<sid.sampleBuffer.count {
            sid.writeSample(Int32(index % 256))
        }

        XCTAssertEqual(sid.sampleWritePos, sid.sampleReadPos)
        XCTAssertEqual(sid.availableAudioSamplesForPlayback(), sid.sampleBuffer.count)
        XCTAssertNotNil(sid.readAudioSampleForPlayback())
        XCTAssertEqual(sid.availableAudioSamplesForPlayback(), sid.sampleBuffer.count - 1)
    }

    func testPlaybackAudioRingBufferDropsOldestSampleWhenOverfilled() {
        let sid = SID()
        let capacity = sid.sampleBuffer.count

        for index in 0...capacity {
            sid.writeSample(Int32(index))
        }

        XCTAssertEqual(sid.availableAudioSamplesForPlayback(), capacity)
        XCTAssertEqual(try XCTUnwrap(sid.readAudioSampleForPlayback()), Float(1) / 32768.0, accuracy: 0.000_001)
    }

    func testC64EmitsSIDRegisterWriteTraceEvents() {
        let c64 = C64(machineProfile: .palC64)
        c64.sid.accuracyMode = .compatibility
        c64.powerOn()
        var events: [SIDRegisterWriteTraceEvent] = []
        c64.onSIDRegisterWriteTrace = { events.append($0) }

        c64.memory.write(0xD418, value: 0x0F)
        c64.memory.write(0xD404, value: 0x21)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].register, 0x18)
        XCTAssertEqual(events[0].value, 0x0F)
        XCTAssertTrue(events[0].reachedChip)
        XCTAssertEqual(events[0].sidModel, .mos6581)
        XCTAssertEqual(events[0].sidAccuracyMode, .compatibility)
        XCTAssertEqual(events[0].cpuPortDirection, 0x2F)
        XCTAssertEqual(events[0].cpuPortData, 0x37)
        XCTAssertEqual(events[0].cpuPortEffective, 0x37)
        XCTAssertEqual(events[0].loram, true)
        XCTAssertEqual(events[0].hiram, true)
        XCTAssertEqual(events[0].charen, true)
        XCTAssertEqual(events[1].register, 0x04)
        XCTAssertEqual(events[1].value, 0x21)
    }

    func testC64SIDRegisterWriteTraceEventsIncludeBankedOutPortState() {
        let c64 = C64(machineProfile: .palC64)
        c64.powerOn()
        var events: [SIDRegisterWriteTraceEvent] = []
        c64.onSIDRegisterWriteTrace = { events.append($0) }

        c64.memory.write(0x0000, value: 0x2F)
        c64.memory.write(0x0001, value: 0x30)
        c64.memory.write(0xD404, value: 0x21)

        let event = try! XCTUnwrap(events.last)
        XCTAssertFalse(event.reachedChip)
        XCTAssertEqual(event.register, 0x04)
        XCTAssertEqual(event.value, 0x21)
        XCTAssertEqual(event.cpuPortDirection, 0x2F)
        XCTAssertEqual(event.cpuPortData, 0x30)
        XCTAssertEqual(event.cpuPortEffective, 0x30)
        XCTAssertEqual(event.loram, false)
        XCTAssertEqual(event.hiram, false)
        XCTAssertEqual(event.charen, false)
    }

    func testSIDRegisterTracePlayerReplaysWritesAndProducesAudioSignature() throws {
        let events = [
            SIDRegisterWriteTraceEvent(
                cycle: 100,
                pc: 0x2000,
                rasterLine: 10,
                rasterCycle: 5,
                register: 0x00,
                value: 0x00,
                sidModel: .mos6581,
                sidAccuracyMode: .compatibility
            ),
            SIDRegisterWriteTraceEvent(
                cycle: 100,
                pc: 0x2000,
                rasterLine: 10,
                rasterCycle: 5,
                register: 0x01,
                value: 0x20,
                sidModel: .mos6581,
                sidAccuracyMode: .compatibility
            ),
            SIDRegisterWriteTraceEvent(
                cycle: 100,
                pc: 0x2000,
                rasterLine: 10,
                rasterCycle: 5,
                register: 0x05,
                value: 0x00,
                sidModel: .mos6581,
                sidAccuracyMode: .compatibility
            ),
            SIDRegisterWriteTraceEvent(
                cycle: 100,
                pc: 0x2000,
                rasterLine: 10,
                rasterCycle: 5,
                register: 0x06,
                value: 0xF0,
                sidModel: .mos6581,
                sidAccuracyMode: .compatibility
            ),
            SIDRegisterWriteTraceEvent(
                cycle: 100,
                pc: 0x2000,
                rasterLine: 10,
                rasterCycle: 5,
                register: 0x18,
                value: 0x0F,
                sidModel: .mos6581,
                sidAccuracyMode: .compatibility
            ),
            SIDRegisterWriteTraceEvent(
                cycle: 100,
                pc: 0x2000,
                rasterLine: 10,
                rasterCycle: 5,
                register: 0x04,
                value: 0x21,
                sidModel: .mos6581,
                sidAccuracyMode: .compatibility
            ),
        ]

        let result = try SIDRegisterTracePlayer().replay(
            events,
            tailCycles: UInt64(SID.attackRates[0] * 4),
            signatureSampleCount: 4
        )

        XCTAssertEqual(result.eventCount, events.count)
        XCTAssertGreaterThan(result.samplesGenerated, 0)
        XCTAssertEqual(result.audioState.volume, 0x0F)
        XCTAssertEqual(result.voiceStates[0].frequency, 0x2000)
        XCTAssertEqual(result.voiceStates[0].control, 0x21)
        XCTAssertGreaterThan(result.voiceStates[0].envelopeLevel, 0)
        XCTAssertGreaterThan(result.signature.absoluteSum, 0)
        XCTAssertTrue(result.capturedSamples.isEmpty)
    }

    func testSIDRegisterTracePlayerCanCaptureBoundedReplaySamples() throws {
        let jsonl = """
        {"cycle":100,"pc":4096,"rasterCycle":5,"rasterLine":10,"reachedChip":true,"register":0,"sidAccuracyMode":"compatibility","sidModel":"mos6581","value":0}
        {"cycle":100,"pc":4096,"rasterCycle":5,"rasterLine":10,"reachedChip":true,"register":1,"sidAccuracyMode":"compatibility","sidModel":"mos6581","value":32}
        {"cycle":100,"pc":4096,"rasterCycle":5,"rasterLine":10,"reachedChip":true,"register":5,"sidAccuracyMode":"compatibility","sidModel":"mos6581","value":0}
        {"cycle":100,"pc":4096,"rasterCycle":5,"rasterLine":10,"reachedChip":true,"register":6,"sidAccuracyMode":"compatibility","sidModel":"mos6581","value":240}
        {"cycle":100,"pc":4096,"rasterCycle":5,"rasterLine":10,"reachedChip":true,"register":24,"sidAccuracyMode":"compatibility","sidModel":"mos6581","value":15}
        {"cycle":100,"pc":4096,"rasterCycle":5,"rasterLine":10,"reachedChip":true,"register":4,"sidAccuracyMode":"compatibility","sidModel":"mos6581","value":33}
        """.data(using: .utf8)!
        let player = SIDRegisterTracePlayer()
        let events = try player.decodeJSONLines(jsonl)

        let result = try player.replay(
            events,
            tailCycles: UInt64(SID.attackRates[0]) * 64,
            signatureSampleCount: 32,
            captureSampleLimit: 5
        )

        XCTAssertGreaterThan(result.samplesGenerated, result.capturedSamples.count)
        XCTAssertEqual(result.capturedSamples.count, 5)
        XCTAssertTrue(result.capturedSamples.contains { abs($0) > 0 })
        XCTAssertEqual(result.capturedAudioSummary.sampleCount, 5)
        XCTAssertGreaterThan(result.capturedAudioSummary.rootMeanSquare, 0)
        XCTAssertGreaterThanOrEqual(result.capturedAudioSummary.crestFactor, 1)
    }

    func testSIDRegisterTracePlayerCanStartCaptureAtNonSilentSample() throws {
        let events = [
            SIDRegisterWriteTraceEvent(
                cycle: 0,
                pc: 0x2000,
                rasterLine: 0,
                rasterCycle: 0,
                register: 0x18,
                value: 0x00,
                sidModel: .mos6581,
                sidAccuracyMode: .compatibility
            ),
            SIDRegisterWriteTraceEvent(
                cycle: 2_000,
                pc: 0x2000,
                rasterLine: 0,
                rasterCycle: 0,
                register: 0x18,
                value: 0x0F,
                sidModel: .mos6581,
                sidAccuracyMode: .compatibility
            ),
        ]

        let result = try SIDRegisterTracePlayer().replay(
            events,
            tailCycles: 1_000,
            captureSampleLimit: 4,
            captureStartWhenAbsoluteSampleAtLeast: 0.001
        )

        XCTAssertEqual(result.capturedSamples.count, 4)
        XCTAssertGreaterThanOrEqual(abs(try XCTUnwrap(result.capturedSamples.first)), 0.001)
        XCTAssertGreaterThan(result.capturedAudioSummary.rootMeanSquare, 0)
    }

    func testSIDRegisterTracePlayerFindsBestAudioTextureWindow() throws {
        let events = [
            SIDRegisterWriteTraceEvent(
                cycle: 0,
                pc: 0x2000,
                rasterLine: 0,
                rasterCycle: 0,
                register: 0x18,
                value: 0x0F,
                sidModel: .mos6581,
                sidAccuracyMode: .compatibility
            ),
            SIDRegisterWriteTraceEvent(
                cycle: 4_000,
                pc: 0x2000,
                rasterLine: 0,
                rasterCycle: 0,
                register: 0x00,
                value: 0x00,
                sidModel: .mos6581,
                sidAccuracyMode: .compatibility
            ),
            SIDRegisterWriteTraceEvent(
                cycle: 4_000,
                pc: 0x2000,
                rasterLine: 0,
                rasterCycle: 0,
                register: 0x01,
                value: 0x40,
                sidModel: .mos6581,
                sidAccuracyMode: .compatibility
            ),
            SIDRegisterWriteTraceEvent(
                cycle: 4_000,
                pc: 0x2000,
                rasterLine: 0,
                rasterCycle: 0,
                register: 0x05,
                value: 0x00,
                sidModel: .mos6581,
                sidAccuracyMode: .compatibility
            ),
            SIDRegisterWriteTraceEvent(
                cycle: 4_000,
                pc: 0x2000,
                rasterLine: 0,
                rasterCycle: 0,
                register: 0x06,
                value: 0xF0,
                sidModel: .mos6581,
                sidAccuracyMode: .compatibility
            ),
            SIDRegisterWriteTraceEvent(
                cycle: 4_000,
                pc: 0x2000,
                rasterLine: 0,
                rasterCycle: 0,
                register: 0x04,
                value: 0x21,
                sidModel: .mos6581,
                sidAccuracyMode: .compatibility
            ),
        ]

        let result = try SIDRegisterTracePlayer().replay(
            events,
            tailCycles: 8_000,
            textureWindowSampleCount: 32,
            textureWindowStride: 8
        )

        XCTAssertGreaterThan(result.bestAudioTextureWindow.startSample, 0)
        XCTAssertGreaterThan(result.bestAudioTextureWindow.score, 0)
        XCTAssertGreaterThan(result.bestAudioTextureWindow.summary.rootMeanSquare, 0)
        XCTAssertGreaterThan(
            result.bestAudioTextureWindow.summary.midBandRootMeanSquare +
            result.bestAudioTextureWindow.summary.highBandRootMeanSquare,
            0
        )
    }

    func testSIDTraceAudioSummaryReportsSilence() {
        let summary = SIDTraceAudioSummary(samples: [], sampleRate: SID.sampleRate)

        XCTAssertEqual(summary.sampleCount, 0)
        XCTAssertEqual(summary.rootMeanSquare, 0)
        XCTAssertEqual(summary.lowBandRootMeanSquare, 0)
        XCTAssertEqual(summary.midBandRootMeanSquare, 0)
        XCTAssertEqual(summary.highBandRootMeanSquare, 0)
        XCTAssertEqual(summary.crestFactor, 0)
    }

    func testSIDTraceAudioSummarySeparatesLowAndHighTexture() {
        let sampleRate = 44_100.0
        let lowTone = (0..<4096).map { index in
            Float(sin(2 * Double.pi * 110 * Double(index) / sampleRate) * 0.6)
        }
        let highTone = (0..<4096).map { index in
            Float(sin(2 * Double.pi * 6_000 * Double(index) / sampleRate) * 0.6)
        }

        let lowSummary = SIDTraceAudioSummary(samples: lowTone, sampleRate: sampleRate)
        let highSummary = SIDTraceAudioSummary(samples: highTone, sampleRate: sampleRate)

        XCTAssertGreaterThan(lowSummary.lowBandRootMeanSquare, lowSummary.highBandRootMeanSquare)
        XCTAssertGreaterThan(highSummary.highBandRootMeanSquare, highSummary.lowBandRootMeanSquare)
        XCTAssertGreaterThan(highSummary.zeroCrossingRate, lowSummary.zeroCrossingRate)
    }

    func testSIDRegisterTracePlayerDecodesJSONLines() throws {
        let data = """
        {"cycle":10,"pc":4096,"rasterCycle":2,"rasterLine":3,"reachedChip":true,"register":24,"sidAccuracyMode":"compatibility","sidModel":"mos6581","value":15}
        {"cycle":12,"pc":4098,"rasterCycle":4,"rasterLine":3,"reachedChip":false,"register":36,"sidAccuracyMode":"compatibility","sidModel":"mos6581","value":33}

        """.data(using: .utf8)!

        let events = try SIDRegisterTracePlayer().decodeJSONLines(data)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].cycle, 10)
        XCTAssertEqual(events[0].register, 0x18)
        XCTAssertTrue(events[0].reachedChip)
        XCTAssertEqual(events[1].register, 0x04)
        XCTAssertFalse(events[1].reachedChip)
    }

    func testSIDRegisterTracePlayerReportsInvalidJSONLine() {
        let data = """
        {"cycle":10,"pc":4096,"rasterCycle":2,"rasterLine":3,"reachedChip":true,"register":24,"sidAccuracyMode":"compatibility","sidModel":"mos6581","value":15}
        nope
        """.data(using: .utf8)!

        XCTAssertThrowsError(try SIDRegisterTracePlayer().decodeJSONLines(data)) { error in
            XCTAssertEqual(error as? SIDRegisterTraceDecodeError, .invalidJSONLine(2))
        }
    }

    func testLocalSIDTraceReplayWhenEnabled() throws {
        guard let path = ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_JSONL"],
              !path.isEmpty else {
            throw XCTSkip("Set SWIFT64_LOCAL_SID_TRACE_REPLAY_JSONL to replay a local SID trace")
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let player = SIDRegisterTracePlayer()
        let events = try player.decodeJSONLines(data)
        let tailCycles = UInt64(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_TAIL_CYCLES"] ?? "") ?? 0
        let captureLimit = Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_CAPTURE_SAMPLES"] ?? "") ?? 4096
        let captureThreshold = Float(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_CAPTURE_THRESHOLD"] ?? "") ?? 0
        let captureSkip = Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_CAPTURE_SKIP"] ?? "") ?? 0
        let textureWindow = Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_TEXTURE_WINDOW"] ?? "") ?? 0
        let textureStride = Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_TEXTURE_STRIDE"] ?? "") ?? 0
        let requiredCapturedRMS = Double(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_REQUIRE_CAPTURED_RMS"] ?? "")
        let requiredCapturedLowRMS = Double(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_REQUIRE_CAPTURED_LOW_RMS"] ?? "")
        let requiredCapturedMidRMS = Double(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_REQUIRE_CAPTURED_MID_RMS"] ?? "")
        let requiredCapturedHighRMS = Double(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_REQUIRE_CAPTURED_HIGH_RMS"] ?? "")
        let requiredCapturedZeroCrossingRate = Double(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_REQUIRE_CAPTURED_ZCR"] ?? "")
        let requiredBestTextureRMS = Double(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_REQUIRE_TEXTURE_RMS"] ?? "")
        let requiredBestTextureMidRMS = Double(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_REQUIRE_TEXTURE_MID_RMS"] ?? "")
        let requiredBestTextureHighRMS = Double(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_REQUIRE_TEXTURE_HIGH_RMS"] ?? "")
        let requiredBestTextureZeroCrossingRate = Double(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_SID_TRACE_REPLAY_REQUIRE_TEXTURE_ZCR"] ?? "")
        let result = try player.replay(
            events,
            tailCycles: tailCycles,
            signatureSampleCount: 4096,
            captureSampleLimit: captureLimit,
            captureStartAfterGeneratedSamples: captureSkip,
            captureStartWhenAbsoluteSampleAtLeast: captureThreshold,
            textureWindowSampleCount: textureWindow,
            textureWindowStride: textureStride
        )

        print(
            "SID trace replay path=\(path) events=\(result.eventCount) finalCycle=\(result.finalCycle) " +
            "samples=\(result.samplesGenerated) captured=\(result.capturedSamples.count) " +
            "rms=\(result.signature.rootMeanSquare) zeroCrossings=\(result.signature.zeroCrossings) " +
            "capturedRMS=\(result.capturedAudioSummary.rootMeanSquare) " +
            "lowRMS=\(result.capturedAudioSummary.lowBandRootMeanSquare) " +
            "midRMS=\(result.capturedAudioSummary.midBandRootMeanSquare) " +
            "highRMS=\(result.capturedAudioSummary.highBandRootMeanSquare) " +
            "zcr=\(result.capturedAudioSummary.zeroCrossingRate) " +
            "bestTextureStart=\(result.bestAudioTextureWindow.startSample) " +
            "bestTextureScore=\(result.bestAudioTextureWindow.score) " +
            "bestTextureRMS=\(result.bestAudioTextureWindow.summary.rootMeanSquare) " +
            "bestTextureLowRMS=\(result.bestAudioTextureWindow.summary.lowBandRootMeanSquare) " +
            "bestTextureMidRMS=\(result.bestAudioTextureWindow.summary.midBandRootMeanSquare) " +
            "bestTextureHighRMS=\(result.bestAudioTextureWindow.summary.highBandRootMeanSquare) " +
            "bestTextureZCR=\(result.bestAudioTextureWindow.summary.zeroCrossingRate) " +
            "volume=\(result.audioState.volume) mixed=\(result.audioState.mixedOutput)"
        )
        XCTAssertFalse(events.isEmpty)
        XCTAssertGreaterThan(result.samplesGenerated, 0)
        XCTAssertGreaterThan(result.signature.rootMeanSquare, 0)
        if let requiredCapturedRMS {
            XCTAssertGreaterThanOrEqual(result.capturedAudioSummary.rootMeanSquare, requiredCapturedRMS)
        }
        if let requiredCapturedLowRMS {
            XCTAssertGreaterThanOrEqual(result.capturedAudioSummary.lowBandRootMeanSquare, requiredCapturedLowRMS)
        }
        if let requiredCapturedMidRMS {
            XCTAssertGreaterThanOrEqual(result.capturedAudioSummary.midBandRootMeanSquare, requiredCapturedMidRMS)
        }
        if let requiredCapturedHighRMS {
            XCTAssertGreaterThanOrEqual(result.capturedAudioSummary.highBandRootMeanSquare, requiredCapturedHighRMS)
        }
        if let requiredCapturedZeroCrossingRate {
            XCTAssertGreaterThanOrEqual(result.capturedAudioSummary.zeroCrossingRate, requiredCapturedZeroCrossingRate)
        }
        if let requiredBestTextureRMS {
            XCTAssertGreaterThanOrEqual(result.bestAudioTextureWindow.summary.rootMeanSquare, requiredBestTextureRMS)
        }
        if let requiredBestTextureMidRMS {
            XCTAssertGreaterThanOrEqual(result.bestAudioTextureWindow.summary.midBandRootMeanSquare, requiredBestTextureMidRMS)
        }
        if let requiredBestTextureHighRMS {
            XCTAssertGreaterThanOrEqual(result.bestAudioTextureWindow.summary.highBandRootMeanSquare, requiredBestTextureHighRMS)
        }
        if let requiredBestTextureZeroCrossingRate {
            XCTAssertGreaterThanOrEqual(result.bestAudioTextureWindow.summary.zeroCrossingRate, requiredBestTextureZeroCrossingRate)
        }
    }

    func testResetClearsCompatibilityAudioAccumulator() {
        let sid = SID()
        sid.accuracyMode = .compatibility
        sid.audioAccumulator = 123
        sid.audioAccumulatorCount = 4
        sid.audioOutputState = 456

        sid.reset()

        XCTAssertEqual(sid.audioAccumulator, 0)
        XCTAssertEqual(sid.audioAccumulatorCount, 0)
        XCTAssertEqual(sid.audioOutputState, 0)
    }

    func testPaddleRegistersReadLatchedAnalogValues() {
        let sid = SID()

        XCTAssertEqual(sid.readRegister(0x19), 0xFF)
        XCTAssertEqual(sid.readRegister(0x1A), 0xFF)

        sid.setPaddle(x: 0x34, y: 0xA5)

        XCTAssertEqual(sid.readRegister(0x19), 0x34)
        XCTAssertEqual(sid.readRegister(0x1A), 0xA5)
    }

    func testPaddleScanRampsTowardTargetOverSIDCycles() {
        let sid = SID()

        sid.startPaddleScan(x: 0x40, y: 0xC0)

        XCTAssertEqual(sid.readRegister(0x19), 0x00)
        XCTAssertEqual(sid.readRegister(0x1A), 0x00)
        XCTAssertEqual(sid.paddleScanCounter, 0)

        for _ in 0..<128 {
            sid.tick()
        }

        XCTAssertEqual(sid.readRegister(0x19), 0x40)
        XCTAssertEqual(sid.readRegister(0x1A), 0x40)
        XCTAssertEqual(sid.paddleScanCounter, 128)

        for _ in 0..<256 {
            sid.tick()
        }

        XCTAssertEqual(sid.readRegister(0x19), 0x40)
        XCTAssertEqual(sid.readRegister(0x1A), 0xC0)
        XCTAssertEqual(sid.paddleScanCounter, 384)

        for _ in 0..<128 {
            sid.tick()
        }

        XCTAssertEqual(sid.readRegister(0x19), 0x40)
        XCTAssertEqual(sid.readRegister(0x1A), 0xC0)
        XCTAssertNil(sid.paddleScanCounter)
    }

    func testDirectPaddleSetCancelsActivePaddleScan() {
        let sid = SID()
        sid.startPaddleScan(x: 0x40, y: 0xC0)

        for _ in 0..<32 {
            sid.tick()
        }
        sid.setPaddle(x: 0x12, y: 0x34)

        XCTAssertEqual(sid.readRegister(0x19), 0x12)
        XCTAssertEqual(sid.readRegister(0x1A), 0x34)
        XCTAssertNil(sid.paddleScanCounter)

        for _ in 0..<SID.paddleScanCycles {
            sid.tick()
        }

        XCTAssertEqual(sid.readRegister(0x19), 0x12)
        XCTAssertEqual(sid.readRegister(0x1A), 0x34)
    }

    func testContinuousPaddleScanRestartsFromLatchedTargetOnTick() {
        let sid = SID()
        sid.continuousPaddleScanEnabled = true
        sid.setPaddle(x: 0x40, y: 0xC0)

        XCTAssertNil(sid.paddleScanCounter)
        XCTAssertEqual(sid.readRegister(0x19), 0x40)
        XCTAssertEqual(sid.readRegister(0x1A), 0xC0)

        sid.tick()

        XCTAssertEqual(sid.paddleScanCounter, 0)
        XCTAssertEqual(sid.readRegister(0x19), 0x00)
        XCTAssertEqual(sid.readRegister(0x1A), 0x00)

        for _ in 0..<128 {
            sid.tick()
        }

        XCTAssertEqual(sid.paddleScanCounter, 128)
        XCTAssertEqual(sid.readRegister(0x19), 0x40)
        XCTAssertEqual(sid.readRegister(0x1A), 0x40)

        for _ in 0..<384 {
            sid.tick()
        }

        XCTAssertNil(sid.paddleScanCounter)
        XCTAssertEqual(sid.readRegister(0x19), 0x40)
        XCTAssertEqual(sid.readRegister(0x1A), 0xC0)

        sid.tick()

        XCTAssertEqual(sid.paddleScanCounter, 0)
        XCTAssertEqual(sid.readRegister(0x19), 0x00)
        XCTAssertEqual(sid.readRegister(0x1A), 0x00)
    }

    func testC64TicksDriveContinuousSIDPaddleScan() {
        let c64 = C64()
        c64.sid.setPaddle(x: 0x40, y: 0xC0)

        XCTAssertNil(c64.sid.paddleScanCounter)

        c64.tickOneCycle()

        XCTAssertEqual(c64.sid.paddleScanCounter, 0)
        XCTAssertEqual(c64.sid.readRegister(0x19), 0x00)
        XCTAssertEqual(c64.sid.readRegister(0x1A), 0x00)
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

    func testDebugRegisterSnapshotReportsEffectiveSIDRegisterState() {
        let sid = SID()
        sid.writeRegister(0x00, value: 0x34)
        sid.writeRegister(0x01, value: 0x12)
        sid.writeRegister(0x02, value: 0x78)
        sid.writeRegister(0x03, value: 0x5F)
        sid.writeRegister(0x04, value: 0x21)
        sid.writeRegister(0x18, value: 0x8F)
        sid.voices[2].control = 0x20
        sid.voices[2].accumulator = 0xAB0000
        sid.voices[2].envelopeLevel = 0x56
        sid.setPaddle(x: 0x12, y: 0x34)

        let snapshot = sid.debugRegisterSnapshot()

        XCTAssertEqual(snapshot.count, 0x20)
        XCTAssertEqual(snapshot[0x00], 0x34)
        XCTAssertEqual(snapshot[0x01], 0x12)
        XCTAssertEqual(snapshot[0x02], 0x78)
        XCTAssertEqual(snapshot[0x03], 0x0F)
        XCTAssertEqual(snapshot[0x04], 0x21)
        XCTAssertEqual(snapshot[0x18], 0x8F)
        XCTAssertEqual(snapshot[0x19], 0x12)
        XCTAssertEqual(snapshot[0x1A], 0x34)
        XCTAssertEqual(snapshot[0x1B], 0xAB)
        XCTAssertEqual(snapshot[0x1C], 0x56)
    }

    func testReadableRegisterSnapshotReportsChipReadableStateWithoutMutatingBusLatch() {
        let sid = SID()
        sid.writeRegister(0x00, value: 0x34)
        sid.writeRegister(0x18, value: 0x8F)
        sid.voices[2].control = 0x20
        sid.voices[2].accumulator = 0xAB_CDEF
        sid.voices[2].envelopeLevel = 0x56
        sid.setPaddle(x: 0x12, y: 0x34)
        sid.sampleVoice3Readbacks()
        sid.dataBusLatch = 0xA5
        sid.dataBusLatchCyclesRemaining = 7

        let snapshot = sid.readableRegisterSnapshot()

        XCTAssertEqual(snapshot.count, 0x20)
        XCTAssertEqual(snapshot[0x00], 0xA5)
        XCTAssertEqual(snapshot[0x18], 0xA5)
        XCTAssertEqual(snapshot[0x19], 0x12)
        XCTAssertEqual(snapshot[0x1A], 0x34)
        XCTAssertEqual(snapshot[0x1B], 0xAB)
        XCTAssertEqual(snapshot[0x1C], 0x56)
        XCTAssertEqual(sid.dataBusLatch, 0xA5)
        XCTAssertEqual(sid.dataBusLatchCyclesRemaining, 7)
    }

    func testReadableRegisterSnapshotDiffersFromDebugSnapshotForWriteOnlyRegisters() {
        let sid = SID()
        sid.writeRegister(0x04, value: 0x21)
        sid.writeRegister(0x18, value: 0x8F)
        sid.writeRegister(0x1F, value: 0x5A)

        let debugSnapshot = sid.debugRegisterSnapshot()
        let readableSnapshot = sid.readableRegisterSnapshot()

        XCTAssertEqual(debugSnapshot[0x04], 0x21)
        XCTAssertEqual(debugSnapshot[0x18], 0x8F)
        XCTAssertEqual(readableSnapshot[0x04], 0x5A)
        XCTAssertEqual(readableSnapshot[0x18], 0x5A)
        XCTAssertEqual(readableSnapshot[0x1F], 0x5A)
    }

    func testDebugAudioStateReportsCompatibilityAudioPipelineState() {
        let sid = SID()
        sid.accuracyMode = .compatibility
        sid.sampleCycleCounter = 3.5
        sid.audioAccumulator = 123.5
        sid.audioAccumulatorCount = 4
        sid.audioOutputState = 456.25
        sid.lastDirectOutput = -1024
        sid.lastFilterInput = 2048
        sid.lastFilterOutput = 512
        sid.lastMixedOutput = 1536
        sid.setExternalAudioInput(12_000)
        sid.writeRegister(0x15, value: 0x07)
        sid.writeRegister(0x16, value: 0xFF)
        sid.writeRegister(0x17, value: 0xF0)
        sid.startPaddleScan(x: 0x40, y: 0xC0)
        for _ in 0..<64 {
            sid.tickPaddleScan()
        }
        sid.latchDataBus(0xA5)
        sid.oscillator3Readback = 0xC3
        sid.oscillator3ReadbackValid = true
        sid.envelope3Readback = 0x5A
        sid.envelope3ReadbackValid = true
        sid.filterLow = 1.5
        sid.filterBand = -2.5
        sid.filterHigh = 3.5
        sid.sampleWritePos = 7

        let state = sid.debugAudioState()

        XCTAssertEqual(state.accuracyMode, .compatibility)
        XCTAssertEqual(state.sampleCycleCounter, 3.5)
        XCTAssertEqual(state.cyclesPerSample, sid.cyclesPerSample, accuracy: 0.000_001)
        XCTAssertEqual(state.audioAccumulator, 123.5)
        XCTAssertEqual(state.audioAccumulatorCount, 4)
        XCTAssertEqual(state.audioOutputState, 456.25)
        XCTAssertEqual(state.directOutput, -1024)
        XCTAssertEqual(state.filterInput, 2048)
        XCTAssertEqual(state.filterOutput, 512)
        XCTAssertEqual(state.mixedOutput, 1536)
        XCTAssertEqual(state.externalAudioInput, 12_000)
        XCTAssertEqual(state.externalAudioPathInput, 13_440)
        XCTAssertEqual(state.filterCutoff, 0x07FF)
        XCTAssertEqual(state.filterResonance, 0x0F)
        XCTAssertEqual(state.filterControl, 0)
        XCTAssertEqual(state.volumeFilter, 0)
        XCTAssertEqual(state.volume, 0)
        XCTAssertEqual(state.normalizedFilterCutoffValue, 0x07FF)
        XCTAssertEqual(state.normalizedFilterCutoff, 0.183, accuracy: 0.000_001)
        XCTAssertEqual(state.filterDamping, 0.775, accuracy: 0.000_001)
        XCTAssertFalse(state.voice1FilterEnabled)
        XCTAssertFalse(state.voice2FilterEnabled)
        XCTAssertFalse(state.voice3FilterEnabled)
        XCTAssertFalse(state.externalInputFiltered)
        XCTAssertFalse(state.filterLowPassEnabled)
        XCTAssertFalse(state.filterBandPassEnabled)
        XCTAssertFalse(state.filterHighPassEnabled)
        XCTAssertFalse(state.voice3Off)
        XCTAssertEqual(state.dataBusLatch, 0xA5)
        XCTAssertEqual(state.dataBusLatchCyclesRemaining, SID.dataBusLatchHoldCycles)
        XCTAssertEqual(state.oscillator3Readback, 0xC3)
        XCTAssertTrue(state.oscillator3ReadbackValid)
        XCTAssertEqual(state.envelope3Readback, 0x5A)
        XCTAssertTrue(state.envelope3ReadbackValid)
        XCTAssertEqual(state.paddleX, 0x20)
        XCTAssertEqual(state.paddleY, 0x20)
        XCTAssertEqual(state.paddleTargetX, 0x40)
        XCTAssertEqual(state.paddleTargetY, 0xC0)
        XCTAssertTrue(state.paddleScanActive)
        XCTAssertEqual(state.paddleScanCounter, 64)
        XCTAssertEqual(state.filterLow, 1.5)
        XCTAssertEqual(state.filterBand, -2.5)
        XCTAssertEqual(state.filterHigh, 3.5)
        XCTAssertEqual(state.sampleWritePosition, 7)
    }

    func testMixedAudioOutputRecordsLastMixComponents() {
        let sid = SID()
        sid.model = .mos6581
        sid.setExternalAudioInput(12_000)
        sid.writeRegister(0x18, value: 0x0F)

        let output = sid.mixedAudioOutput()

        XCTAssertEqual(sid.lastDirectOutput, 12_000)
        XCTAssertEqual(sid.lastFilterInput, 0)
        XCTAssertEqual(sid.lastFilterOutput, 0)
        XCTAssertEqual(sid.lastMixedOutput, output)
        XCTAssertEqual(output, 12_000 + SID.volumeDAC6581[15])
    }

    func testDebugVoiceStatesReportOscillatorAndEnvelopeState() {
        let sid = SID()
        sid.voices[0].frequency = 0x1234
        sid.voices[0].pulseWidth = 0x0ABC
        sid.voices[0].control = 0x21
        sid.voices[0].attackDecay = 0xAD
        sid.voices[0].sustainRelease = 0xF6
        sid.voices[0].accumulator = 0xABCDEF
        sid.voices[0].shiftRegister = 0x123456
        sid.voices[0].envelopeLevel = 0x7F
        sid.voices[0].envelopeState = .decay
        sid.voices[0].exponentialCounter = 12
        sid.voices[0].exponentialPeriod = 30
        sid.voices[0].holdZero = true
        sid.voices[0].gate = true
        sid.voices[0].rateCounter = 456
        sid.voices[0].waveformDACOutput = 0x0FED
        sid.voices[0].waveformDACHoldCyclesRemaining = 64

        let voices = sid.debugVoiceStates()

        XCTAssertEqual(voices.count, 3)
        XCTAssertEqual(voices[0].frequency, 0x1234)
        XCTAssertEqual(voices[0].pulseWidth, 0x0ABC)
        XCTAssertEqual(voices[0].control, 0x21)
        XCTAssertEqual(voices[0].attackDecay, 0xAD)
        XCTAssertEqual(voices[0].sustainRelease, 0xF6)
        XCTAssertEqual(voices[0].accumulator, 0xABCDEF)
        XCTAssertEqual(voices[0].shiftRegister, 0x123456)
        XCTAssertEqual(voices[0].envelopeLevel, 0x7F)
        XCTAssertEqual(voices[0].envelopeOutput, UInt8(sid.envelopeDACLevel(0x7F)))
        XCTAssertEqual(voices[0].sustainLevel, 0xFF)
        XCTAssertEqual(voices[0].envelopeState, "decay")
        XCTAssertEqual(voices[0].exponentialCounter, 12)
        XCTAssertEqual(voices[0].exponentialPeriod, 30)
        XCTAssertTrue(voices[0].holdZero)
        XCTAssertTrue(voices[0].gate)
        XCTAssertTrue(voices[0].controlGate)
        XCTAssertFalse(voices[0].sync)
        XCTAssertFalse(voices[0].ringMod)
        XCTAssertFalse(voices[0].testBit)
        XCTAssertFalse(voices[0].waveTriangle)
        XCTAssertTrue(voices[0].waveSawtooth)
        XCTAssertFalse(voices[0].wavePulse)
        XCTAssertFalse(voices[0].waveNoise)
        XCTAssertTrue(voices[0].hasWaveform)
        XCTAssertFalse(voices[0].oscillatorMSBRose)
        XCTAssertFalse(voices[0].noiseClockRose)
        XCTAssertEqual(voices[0].rateCounter, 456)
        XCTAssertEqual(voices[0].selectedRatePeriod, SID.decayReleaseRates[0x0D])
        XCTAssertEqual(voices[0].oscillatorOutput, sid.oscillatorOutput(0))
        XCTAssertEqual(voices[0].waveformOutput, sid.waveformOutput(0))
        XCTAssertEqual(voices[0].waveformDACOutput, 0x0FED)
        XCTAssertEqual(voices[0].waveformDACHoldCyclesRemaining, 64)
    }

    func testDebugVoiceStatesNormalizePulseWidthToTwelveBits() {
        let sid = SID()
        sid.voices[0].pulseWidth = 0xFABC

        let voices = sid.debugVoiceStates()

        XCTAssertEqual(voices[0].pulseWidth, 0x0ABC)
    }

    func testDebugVoiceStatesReportSelectedEnvelopeRatePeriodByState() {
        let sid = SID()
        sid.voices[0].attackDecay = 0xA3
        sid.voices[0].sustainRelease = 0xB6

        sid.voices[0].envelopeState = .attack
        XCTAssertEqual(sid.debugVoiceStates()[0].selectedRatePeriod, SID.attackRates[0x0A])

        sid.voices[0].envelopeState = .decay
        XCTAssertEqual(sid.debugVoiceStates()[0].selectedRatePeriod, SID.decayReleaseRates[0x03])

        sid.voices[0].envelopeState = .sustain
        XCTAssertEqual(sid.debugVoiceStates()[0].sustainLevel, 0xBB)
        XCTAssertEqual(sid.debugVoiceStates()[0].selectedRatePeriod, SID.decayReleaseRates[0x03])

        sid.voices[0].envelopeState = .release
        XCTAssertEqual(sid.debugVoiceStates()[0].selectedRatePeriod, SID.decayReleaseRates[0x06])
    }

    func testDirectSIDRegisterAccessMirrorsOnFiveBitAddressBus() {
        let sid = SID()

        sid.writeRegister(0xD400, value: 0x34)
        sid.writeRegister(0xD401 + 0x20, value: 0x12)
        sid.writeRegister(0xD403, value: 0x5F)
        sid.writeRegister(0xD418, value: 0x8F)

        XCTAssertEqual(sid.debugRegisterValue(0x00), 0x34)
        XCTAssertEqual(sid.debugRegisterValue(0x21), 0x12)
        XCTAssertEqual(sid.debugRegisterValue(0x03), 0x0F)
        XCTAssertEqual(sid.debugRegisterValue(0x18), 0x8F)
        XCTAssertEqual(sid.volumeFilter, 0x8F)
    }

    func testDirectReadableSIDRegisterMirrorsReturnChipState() {
        let sid = SID()
        sid.setPaddle(x: 0x12, y: 0x34)
        sid.voices[2].control = 0x20
        sid.voices[2].accumulator = 0xAB0000
        sid.voices[2].envelopeLevel = 0x56

        XCTAssertEqual(sid.readRegister(0x39), 0x12)
        XCTAssertEqual(sid.readRegister(0x3A), 0x34)
        XCTAssertEqual(sid.readRegister(0x3B), 0xAB)
        XCTAssertEqual(sid.readRegister(0x3C), 0x56)
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

    func testSIDDataBusLatchLeaksBitsAfterHoldWindow() {
        let sid = SID()

        sid.writeRegister(0x00, value: 0x34)
        for _ in 0..<(SID.dataBusLatchHoldCycles - 1) {
            sid.tick()
        }

        XCTAssertEqual(sid.dataBusLatch, 0x34)
        XCTAssertEqual(sid.dataBusLatchCyclesRemaining, 1)

        sid.tick()

        XCTAssertEqual(sid.dataBusLatch, 0x30)
        XCTAssertEqual(sid.dataBusLatchCyclesRemaining, SID.dataBusLatchLeakStepCycles)
        XCTAssertEqual(sid.readRegister(0x00), 0x30)
    }

    func testSIDDataBusLatchEventuallySettlesToZero() {
        let sid = SID()

        sid.writeRegister(0x00, value: 0x34)

        for _ in 0..<10_000 {
            sid.tick()
        }

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

    func testSIDDataBusLatchRefreshesDuringLeakWindow() {
        let sid = SID()

        sid.writeRegister(0x00, value: 0x34)
        for _ in 0..<SID.dataBusLatchHoldCycles {
            sid.tick()
        }
        XCTAssertEqual(sid.dataBusLatch, 0x30)

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

    func testEnvelope3ReadbackUsesSampledFirstPhaseValueAfterTick() {
        let sid = SID()
        sid.voices[2].control = 0x01
        sid.voices[2].gate = true
        sid.voices[2].envelopeState = .attack
        sid.voices[2].envelopeLevel = 0x10
        sid.voices[2].attackDecay = 0x00
        sid.voices[2].rateCounter = SID.attackRates[0] - 1

        sid.tick()

        XCTAssertEqual(sid.envelope3Readback, 0x10)
        XCTAssertTrue(sid.envelope3ReadbackValid)
        XCTAssertEqual(sid.voices[2].envelopeLevel, 0x11)
        XCTAssertEqual(sid.readRegister(0x1C), 0x10)
        XCTAssertEqual(sid.debugRegisterValue(0x1C), 0x11)

        sid.tick()

        XCTAssertEqual(sid.envelope3Readback, 0x11)
        XCTAssertEqual(sid.readRegister(0x1C), 0x11)
    }

    func testVoice3EnvelopeRegisterWritesKeepSampledEnvelope3ReadbackUntilTick() {
        let sid = SID()
        sid.voices[2].envelopeLevel = 0x20
        sid.sampleVoice3Readbacks()

        sid.writeRegister(0x13, value: 0x0F)
        sid.writeRegister(0x14, value: 0xF0)

        XCTAssertTrue(sid.envelope3ReadbackValid)
        XCTAssertEqual(sid.readRegister(0x1C), 0x20)
        XCTAssertEqual(sid.debugRegisterValue(0x1C), 0x20)
    }

    func testVoice3EnvelopeReadbackSamplesBeforeEnvelopeClockAfterRegisterWrite() {
        let sid = SID()
        sid.voices[2].control = 0x01
        sid.voices[2].gate = true
        sid.voices[2].envelopeState = .attack
        sid.voices[2].envelopeLevel = 0x20
        sid.writeRegister(0x13, value: 0x00)
        sid.voices[2].rateCounter = SID.attackRates[0] - 1
        sid.sampleVoice3Readbacks()

        sid.tick()

        XCTAssertEqual(sid.envelope3Readback, 0x20)
        XCTAssertEqual(sid.voices[2].envelopeLevel, 0x21)
        XCTAssertEqual(sid.readRegister(0x1C), 0x20)
        XCTAssertEqual(sid.debugRegisterValue(0x1C), 0x21)
    }

    func testOscillator3ReadbackUsesSampledFirstPhaseValueAfterTick() {
        let sid = SID()
        sid.voices[2].control = 0x20
        sid.voices[2].accumulator = 0x40FFFF
        sid.voices[2].frequency = 1

        sid.tick()

        XCTAssertEqual(sid.oscillator3Readback, 0x40)
        XCTAssertTrue(sid.oscillator3ReadbackValid)
        XCTAssertEqual(UInt8((sid.oscillatorReadbackOutput(2) >> 4) & 0xFF), 0x41)
        XCTAssertEqual(sid.readRegister(0x1B), 0x40)
        XCTAssertEqual(sid.debugRegisterValue(0x1B), 0x41)

        sid.tick()

        XCTAssertEqual(sid.oscillator3Readback, 0x41)
        XCTAssertEqual(sid.readRegister(0x1B), 0x41)
    }

    func testVoice3TestWriteInvalidatesSampledOscillator3Readback() {
        let sid = SID()
        sid.voices[2].control = 0x20
        sid.voices[2].accumulator = 0xF0_0000
        sid.voices[2].envelopeLevel = 0x5A
        sid.sampleVoice3Readbacks()

        XCTAssertEqual(sid.readRegister(0x1B), 0xF0)
        XCTAssertEqual(sid.readRegister(0x1C), 0x5A)

        sid.writeRegister(0x12, value: 0x28)

        XCTAssertFalse(sid.oscillator3ReadbackValid)
        XCTAssertEqual(sid.readRegister(0x1B), 0)
        XCTAssertEqual(sid.readRegister(0x1C), 0x5A)
        XCTAssertEqual(sid.debugRegisterValue(0x1B), 0)
        XCTAssertEqual(sid.debugRegisterValue(0x1C), 0x5A)
    }

    func testVoice3ControlWriteInvalidatesSampledOscillator3Readback() {
        let sid = SID()
        sid.voices[2].control = 0x20
        sid.voices[2].pulseWidth = 0x0800
        sid.voices[2].accumulator = 0xA0_0000
        sid.voices[2].envelopeLevel = 0x5A
        sid.sampleVoice3Readbacks()

        XCTAssertEqual(sid.readRegister(0x1B), 0xA0)
        XCTAssertEqual(sid.readRegister(0x1C), 0x5A)

        sid.writeRegister(0x12, value: 0x40)

        XCTAssertFalse(sid.oscillator3ReadbackValid)
        XCTAssertEqual(sid.readRegister(0x1B), 0xFF)
        XCTAssertEqual(sid.readRegister(0x1C), 0x5A)
        XCTAssertEqual(sid.debugRegisterValue(0x1B), 0xFF)
        XCTAssertEqual(sid.debugRegisterValue(0x1C), 0x5A)
    }

    func testVoice3GateOnlyControlWriteKeepsSampledOscillator3Readback() {
        let sid = SID()
        sid.voices[2].control = 0x20
        sid.voices[2].accumulator = 0xA0_0000
        sid.voices[2].envelopeLevel = 0x5A
        sid.sampleVoice3Readbacks()

        XCTAssertEqual(sid.readRegister(0x1B), 0xA0)
        XCTAssertEqual(sid.readRegister(0x1C), 0x5A)

        sid.writeRegister(0x12, value: 0x21)

        XCTAssertTrue(sid.oscillator3ReadbackValid)
        XCTAssertEqual(sid.readRegister(0x1B), 0xA0)
        XCTAssertEqual(sid.readRegister(0x1C), 0x5A)
        XCTAssertEqual(sid.debugRegisterValue(0x1B), 0xA0)
        XCTAssertEqual(sid.debugRegisterValue(0x1C), 0x5A)
    }

    func testVoice3RingModControlWriteInvalidatesSampledOscillator3Readback() {
        let sid = SID()
        sid.voices[1].accumulator = 0x80_0000
        sid.voices[2].control = 0x10
        sid.voices[2].accumulator = 0x40_0000
        sid.voices[2].envelopeLevel = 0x5A
        sid.sampleVoice3Readbacks()

        XCTAssertEqual(sid.readRegister(0x1B), 0x80)
        XCTAssertEqual(sid.readRegister(0x1C), 0x5A)

        sid.writeRegister(0x12, value: 0x14)

        XCTAssertFalse(sid.oscillator3ReadbackValid)
        XCTAssertEqual(sid.readRegister(0x1B), 0x7F)
        XCTAssertEqual(sid.readRegister(0x1C), 0x5A)
        XCTAssertEqual(sid.debugRegisterValue(0x1B), 0x7F)
        XCTAssertEqual(sid.debugRegisterValue(0x1C), 0x5A)
    }

    func testVoice3PulseWidthWriteInvalidatesSampledOscillator3Readback() {
        let sid = SID()
        sid.voices[2].control = 0x40
        sid.voices[2].pulseWidth = 0x0800
        sid.voices[2].accumulator = 0x50_0000
        sid.voices[2].envelopeLevel = 0x5A
        sid.sampleVoice3Readbacks()

        XCTAssertEqual(sid.readRegister(0x1B), 0x00)
        XCTAssertEqual(sid.readRegister(0x1C), 0x5A)

        sid.writeRegister(0x10, value: 0x00)
        sid.writeRegister(0x11, value: 0x04)

        XCTAssertFalse(sid.oscillator3ReadbackValid)
        XCTAssertEqual(sid.readRegister(0x1B), 0xFF)
        XCTAssertEqual(sid.readRegister(0x1C), 0x5A)
        XCTAssertEqual(sid.debugRegisterValue(0x1B), 0xFF)
        XCTAssertEqual(sid.debugRegisterValue(0x1C), 0x5A)
    }

    func testVoice3NonPulseWidthWriteKeepsSampledOscillator3Readback() {
        let sid = SID()
        sid.voices[2].control = 0x20
        sid.voices[2].pulseWidth = 0x0800
        sid.voices[2].accumulator = 0xA0_0000
        sid.sampleVoice3Readbacks()

        sid.writeRegister(0x10, value: 0x00)
        sid.writeRegister(0x11, value: 0x04)

        XCTAssertTrue(sid.oscillator3ReadbackValid)
        XCTAssertEqual(sid.readRegister(0x1B), 0xA0)
    }

    func testEnvelope3SampledReadbackUpdatesLocalDataBusLatch() {
        let sid = SID()
        sid.voices[2].envelopeLevel = 0x42
        sid.tick()
        sid.voices[2].envelopeLevel = 0x99

        XCTAssertEqual(sid.readRegister(0x1C), 0x42)
        XCTAssertEqual(sid.readRegister(0x00), 0x42)
    }

    func testOscillator3SampledReadbackUpdatesLocalDataBusLatch() {
        let sid = SID()
        sid.voices[2].control = 0x20
        sid.voices[2].accumulator = 0xA0FFFF
        sid.voices[2].frequency = 1

        sid.tick()

        XCTAssertEqual(sid.readRegister(0x1B), 0xA0)
        XCTAssertEqual(sid.readRegister(0x00), 0xA0)
    }

    func testOscillator3ReadbackReflectsFloatingWaveformDAC() {
        let sid = SID()
        sid.voices[2].control = 0x20
        sid.voices[2].accumulator = 0xF00000
        sid.voices[2].frequency = 0

        sid.clockOscillator(2)
        sid.voices[2].control = 0

        XCTAssertEqual(sid.readRegister(0x1B), 0xF0)
        XCTAssertEqual(sid.debugRegisterValue(0x1B), 0xF0)
    }

    func testOscillator3ReadbackHonorsTestBitDACBehavior() {
        let sid = SID()
        sid.voices[2].control = 0x20
        sid.voices[2].accumulator = 0xF00000
        sid.voices[2].frequency = 0

        sid.clockOscillator(2)
        sid.voices[2].control = 0x28
        sid.clockOscillator(2)

        XCTAssertEqual(sid.readRegister(0x1B), 0xF0)

        sid.writeRegister(0x12, value: 0x28)

        XCTAssertEqual(sid.readRegister(0x1B), 0)
        XCTAssertEqual(sid.debugRegisterValue(0x1B), 0)
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

    func test8580NoiseWithTriangleSawUsesDigitalBaseBeforeNoiseMask() {
        let sid = SID()
        sid.model = .mos8580
        sid.voices[0].control = 0xB0
        sid.voices[0].shiftRegister = (1 << 22) | (1 << 20) | (1 << 16) | (1 << 13) |
            (1 << 11) | (1 << 7) | (1 << 4) | (1 << 2)
        sid.voices[0].accumulator = 0x700000

        XCTAssertEqual(sid.triangleWaveformOutput(0) & sid.sawtoothWaveformOutput(0), 0x600)
        XCTAssertEqual(sid.noiseWaveformOutput(0), 0xFF0)
        XCTAssertEqual(sid.oscillatorOutput(0), 0x600)
    }

    func test6581NoiseWithTriangleSawUsesAnalogBaseBeforeNoiseMask() {
        let sid = SID()
        sid.model = .mos6581
        sid.voices[0].control = 0xB0
        sid.voices[0].shiftRegister = (1 << 22) | (1 << 20) | (1 << 16) | (1 << 13) |
            (1 << 11) | (1 << 7) | (1 << 4) | (1 << 2)
        sid.voices[0].accumulator = 0x700000

        XCTAssertEqual(sid.triangleWaveformOutput(0) & sid.sawtoothWaveformOutput(0), 0x600)
        XCTAssertEqual(sid.combined6581TriangleSawtoothOutput(0), 0x200)
        XCTAssertEqual(sid.noiseWaveformOutput(0), 0xFF0)
        XCTAssertEqual(sid.oscillatorOutput(0), 0x200)
    }

    func test6581NoiseWithTrianglePulseUsesAnalogBaseBeforeNoiseMask() {
        let sid = SID()
        sid.model = .mos6581
        sid.voices[0].control = 0xD0
        sid.voices[0].pulseWidth = 0x0800
        sid.voices[0].shiftRegister = (1 << 22) | (1 << 20) | (1 << 16) | (1 << 13) |
            (1 << 11) | (1 << 7) | (1 << 4) | (1 << 2)
        sid.voices[0].accumulator = 0x900000

        XCTAssertEqual(sid.triangleWaveformOutput(0) & sid.pulseWaveformOutput(0), 0xDFF)
        XCTAssertEqual(sid.combined6581TrianglePulseOutput(0), 0x4FF)
        XCTAssertEqual(sid.noiseWaveformOutput(0), 0xFF0)
        XCTAssertEqual(sid.oscillatorOutput(0), 0x4F0)
    }

    func test6581NoiseWithTriangleSawPulseUsesAnalogBaseBeforeNoiseMask() {
        let sid = SID()
        sid.model = .mos6581
        sid.voices[0].control = 0xF0
        sid.voices[0].pulseWidth = 0x0800
        sid.voices[0].shiftRegister = (1 << 22) | (1 << 20) | (1 << 16) | (1 << 13) |
            (1 << 11) | (1 << 7) | (1 << 4) | (1 << 2)
        sid.voices[0].accumulator = 0x900000

        XCTAssertEqual(sid.triangleWaveformOutput(0) & sid.sawtoothWaveformOutput(0) & sid.pulseWaveformOutput(0), 0x900)
        XCTAssertEqual(sid.combined6581TriangleSawtoothPulseOutput(0), 0x100)
        XCTAssertEqual(sid.noiseWaveformOutput(0), 0xFF0)
        XCTAssertEqual(sid.oscillatorOutput(0), 0x100)
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

    func testPulseWaveformMasksPulseWidthToTwelveBits() {
        let sid = SID()
        sid.voices[0].control = 0x40
        sid.voices[0].pulseWidth = 0xFABC
        sid.voices[0].accumulator = 0xB00000

        XCTAssertEqual(sid.oscillatorOutput(0), 0xFFF)

        sid.voices[0].accumulator = 0xA00000

        XCTAssertEqual(sid.oscillatorOutput(0), 0)
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

    func testRingModBitDoesNotAffect6581SawPulseWithoutTriangle() {
        let plain = SID()
        plain.model = .mos6581
        plain.voices[0].control = 0x60
        plain.voices[0].pulseWidth = 0x0800
        plain.voices[0].accumulator = 0x300000
        plain.voices[2].accumulator = 0x800000

        let ring = SID()
        ring.model = .mos6581
        ring.voices[0].control = 0x64
        ring.voices[0].pulseWidth = 0x0800
        ring.voices[0].accumulator = 0x300000
        ring.voices[2].accumulator = 0x800000

        XCTAssertEqual(plain.oscillatorOutput(0), 0x200)
        XCTAssertEqual(ring.oscillatorOutput(0), plain.oscillatorOutput(0))
    }

    func testCombinedTriangleSawMasksTriangleWithSawtoothOutput() {
        let sid = SID()
        sid.model = .mos8580
        sid.voices[0].control = 0x30
        sid.voices[0].accumulator = 0x180000

        XCTAssertEqual(sid.oscillatorOutput(0), 0x100)
    }

    func test6581TriangleSawUsesAnalogPullDownApproximation() {
        let sid = SID()
        sid.model = .mos6581
        sid.voices[0].control = 0x30
        sid.voices[0].accumulator = 0x700000

        XCTAssertEqual(sid.triangleWaveformOutput(0), 0xE00)
        XCTAssertEqual(sid.sawtoothWaveformOutput(0), 0x700)
        XCTAssertEqual(sid.triangleWaveformOutput(0) & sid.sawtoothWaveformOutput(0), 0x600)
        XCTAssertEqual(sid.oscillatorOutput(0), 0x200)
    }

    func testCombinedTrianglePulseMasksTriangleWithPulseOutput() {
        let sid = SID()
        sid.model = .mos8580
        sid.voices[0].control = 0x50
        sid.voices[0].pulseWidth = 0x0800

        sid.voices[0].accumulator = 0x100000
        XCTAssertEqual(sid.oscillatorOutput(0), 0)

        sid.voices[0].accumulator = 0x900000
        XCTAssertEqual(sid.oscillatorOutput(0), 0xDFF)
    }

    func test6581TrianglePulseUsesAnalogPullDownApproximation() {
        let sid = SID()
        sid.model = .mos6581
        sid.voices[0].control = 0x50
        sid.voices[0].pulseWidth = 0x0800
        sid.voices[0].accumulator = 0x900000

        XCTAssertEqual(sid.triangleWaveformOutput(0), 0xDFF)
        XCTAssertEqual(sid.pulseWaveformOutput(0), 0xFFF)
        XCTAssertEqual(sid.triangleWaveformOutput(0) & sid.pulseWaveformOutput(0), 0xDFF)
        XCTAssertEqual(sid.oscillatorOutput(0), 0x4FF)
    }

    func testCombinedTriangleSawPulseUsesDigitalMaskingOn8580() {
        let sid = SID()
        sid.model = .mos8580
        sid.voices[0].control = 0x70
        sid.voices[0].pulseWidth = 0x0800
        sid.voices[0].accumulator = 0x900000

        XCTAssertEqual(sid.triangleWaveformOutput(0), 0xDFF)
        XCTAssertEqual(sid.sawtoothWaveformOutput(0), 0x900)
        XCTAssertEqual(sid.pulseWaveformOutput(0), 0xFFF)
        XCTAssertEqual(sid.oscillatorOutput(0), 0x900)
    }

    func test6581TriangleSawPulseUsesAnalogPullDownApproximation() {
        let sid = SID()
        sid.model = .mos6581
        sid.voices[0].control = 0x70
        sid.voices[0].pulseWidth = 0x0800
        sid.voices[0].accumulator = 0x900000

        XCTAssertEqual(sid.triangleWaveformOutput(0), 0xDFF)
        XCTAssertEqual(sid.sawtoothWaveformOutput(0), 0x900)
        XCTAssertEqual(sid.pulseWaveformOutput(0), 0xFFF)
        XCTAssertEqual(sid.triangleWaveformOutput(0) & sid.sawtoothWaveformOutput(0) & sid.pulseWaveformOutput(0), 0x900)
        XCTAssertEqual(sid.oscillatorOutput(0), 0x100)
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

    func testAttackFromMaximumWrapsEnvelopeToZeroAndFreezes() {
        let sid = SID()
        sid.voices[0].control = 0x01
        sid.voices[0].gate = true
        sid.voices[0].envelopeState = .attack
        sid.voices[0].envelopeLevel = 0xFF
        sid.voices[0].holdZero = false
        sid.voices[0].attackDecay = 0x00
        sid.voices[0].exponentialCounter = 12
        sid.voices[0].exponentialPeriod = 30
        sid.voices[0].rateCounter = SID.attackRates[0] - 1

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].rateCounter, 0)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0)
        XCTAssertEqual(sid.voices[0].envelopeState, .attack)
        XCTAssertTrue(sid.voices[0].holdZero)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
        XCTAssertEqual(sid.voices[0].exponentialPeriod, 1)

        sid.voices[0].rateCounter = SID.attackRates[0] - 1
        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeLevel, 0)
        XCTAssertEqual(sid.voices[0].envelopeState, .attack)
        XCTAssertTrue(sid.voices[0].holdZero)
    }

    func testGateCycleUnlocksAttackWrapFreeze() {
        let sid = SID()
        sid.voices[0].control = 0x00
        sid.voices[0].gate = true
        sid.voices[0].envelopeState = .attack
        sid.voices[0].envelopeLevel = 0
        sid.voices[0].holdZero = true

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeState, .release)
        XCTAssertTrue(sid.voices[0].holdZero)

        sid.voices[0].control = 0x01
        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeState, .attack)
        XCTAssertFalse(sid.voices[0].holdZero)
    }

    func testEnvelopeExponentialPeriodChangesAtSIDThresholds() {
        XCTAssertEqual(SID.exponentialPeriod(for: 0xFF), 1)
        XCTAssertEqual(SID.exponentialPeriod(for: 0x5D), 2)
        XCTAssertEqual(SID.exponentialPeriod(for: 0x36), 4)
        XCTAssertEqual(SID.exponentialPeriod(for: 0x1A), 8)
        XCTAssertEqual(SID.exponentialPeriod(for: 0x0E), 16)
        XCTAssertEqual(SID.exponentialPeriod(for: 0x06), 30)
        XCTAssertEqual(SID.exponentialPeriod(for: 0x00), 1)

        XCTAssertEqual(SID.loadedExponentialPeriod(at: 0xFF), 1)
        XCTAssertEqual(SID.loadedExponentialPeriod(at: 0x5D), 2)
        XCTAssertEqual(SID.loadedExponentialPeriod(at: 0x36), 4)
        XCTAssertEqual(SID.loadedExponentialPeriod(at: 0x1A), 8)
        XCTAssertEqual(SID.loadedExponentialPeriod(at: 0x0E), 16)
        XCTAssertEqual(SID.loadedExponentialPeriod(at: 0x06), 30)
        XCTAssertEqual(SID.loadedExponentialPeriod(at: 0x00), 1)
        XCTAssertNil(SID.loadedExponentialPeriod(at: 0xFE))
        XCTAssertNil(SID.loadedExponentialPeriod(at: 0x5C))
    }

    func testDecayKeepsLatchedExponentialPeriodBetweenThresholds() {
        let sid = SID()
        sid.voices[0].envelopeState = .decay
        sid.voices[0].envelopeLevel = 0x5D
        sid.voices[0].exponentialPeriod = 2
        sid.voices[0].sustainRelease = 0x00
        sid.voices[0].attackDecay = 0x00
        sid.voices[0].rateCounter = SID.decayReleaseRates[0] - 1

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeLevel, 0x5D)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 1)
        XCTAssertEqual(sid.voices[0].exponentialPeriod, 2)

        sid.voices[0].rateCounter = SID.decayReleaseRates[0] - 1
        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeLevel, 0x5C)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
        XCTAssertEqual(sid.voices[0].exponentialPeriod, 2)
    }

    func testDecayLoadsExponentialPeriodOnlyAtExactThresholds() {
        let sid = SID()
        sid.voices[0].envelopeState = .decay
        sid.voices[0].envelopeLevel = 0x37
        sid.voices[0].exponentialPeriod = 2
        sid.voices[0].exponentialCounter = 1
        sid.voices[0].sustainRelease = 0x00
        sid.voices[0].attackDecay = 0x00
        sid.voices[0].rateCounter = SID.decayReleaseRates[0] - 1

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeLevel, 0x36)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
        XCTAssertEqual(sid.voices[0].exponentialPeriod, 4)
    }

    func testSustainStateHoldsWhenEnvelopeIsAtCurrentSustainLevel() {
        let sid = SID()
        sid.voices[0].envelopeState = .sustain
        sid.voices[0].envelopeLevel = 0x88
        sid.voices[0].sustainRelease = 0x80
        sid.voices[0].attackDecay = 0x00
        sid.voices[0].rateCounter = SID.decayReleaseRates[0] - 1

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeState, .sustain)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0x88)
        XCTAssertEqual(sid.voices[0].rateCounter, 0)
    }

    func testSustainStateAdvancesRateCounterWithoutChangingEnvelope() {
        let sid = SID()
        sid.voices[0].envelopeState = .sustain
        sid.voices[0].envelopeLevel = 0x88
        sid.voices[0].sustainRelease = 0x80
        sid.voices[0].attackDecay = 0x00
        sid.voices[0].rateCounter = 3

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeState, .sustain)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0x88)
        XCTAssertEqual(sid.voices[0].rateCounter, 4)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
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
        sid.voices[0].exponentialPeriod = 1
        sid.voices[0].sustainRelease = 0x70
        sid.voices[0].attackDecay = 0x00
        sid.voices[0].rateCounter = SID.decayReleaseRates[0] - 1

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeState, .decay)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0x87)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
        XCTAssertEqual(sid.voices[0].exponentialPeriod, 1)

        sid.voices[0].rateCounter = SID.decayReleaseRates[0] - 1
        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeState, .decay)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0x86)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
        XCTAssertEqual(sid.voices[0].exponentialPeriod, 1)
    }

    func testLoweringSustainAtExactThresholdLoadsExponentialPeriod() {
        let sid = SID()
        sid.voices[0].envelopeState = .sustain
        sid.voices[0].envelopeLevel = 0x5D
        sid.voices[0].exponentialPeriod = 1
        sid.voices[0].sustainRelease = 0x50
        sid.voices[0].attackDecay = 0x00
        sid.voices[0].rateCounter = SID.decayReleaseRates[0] - 1

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeState, .decay)
        XCTAssertEqual(sid.voices[0].envelopeLevel, 0x5D)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 1)
        XCTAssertEqual(sid.voices[0].exponentialPeriod, 2)
    }

    func testReleaseHoldsZeroAfterEnvelopeReachesSilence() {
        let sid = SID()
        sid.voices[0].envelopeState = .release
        sid.voices[0].envelopeLevel = 1
        sid.voices[0].exponentialPeriod = 1
        sid.voices[0].sustainRelease = 0x00
        sid.voices[0].rateCounter = SID.decayReleaseRates[0] - 1

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeLevel, 0)
        XCTAssertTrue(sid.voices[0].holdZero)

        sid.voices[0].rateCounter = SID.decayReleaseRates[0] - 1
        sid.voices[0].exponentialCounter = 0
        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeLevel, 0)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
    }

    func testGateReleaseAtZeroImmediatelyLatchesHoldZero() {
        let sid = SID()
        sid.voices[0].control = 0x00
        sid.voices[0].gate = true
        sid.voices[0].envelopeState = .attack
        sid.voices[0].envelopeLevel = 0
        sid.voices[0].holdZero = false
        sid.voices[0].exponentialCounter = 12
        sid.voices[0].exponentialPeriod = 30

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeState, .release)
        XCTAssertTrue(sid.voices[0].holdZero)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
        XCTAssertEqual(sid.voices[0].exponentialPeriod, 1)
    }

    func testGateReleasePreservesLatchedExponentialPeriod() {
        let sid = SID()
        sid.voices[0].control = 0x00
        sid.voices[0].gate = true
        sid.voices[0].envelopeState = .attack
        sid.voices[0].envelopeLevel = 0x5C
        sid.voices[0].exponentialCounter = 12
        sid.voices[0].exponentialPeriod = 4

        sid.clockEnvelope(0)

        XCTAssertEqual(sid.voices[0].envelopeState, .release)
        XCTAssertEqual(sid.voices[0].exponentialCounter, 0)
        XCTAssertEqual(sid.voices[0].exponentialPeriod, 4)
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

    func testWaveformDACLatchDecaysAfterFloatingWindow() {
        let sid = SID()
        sid.model = .mos6581
        sid.voices[0].control = 0x20
        sid.voices[0].accumulator = 0xF00000
        sid.voices[0].frequency = 0
        sid.voices[0].envelopeLevel = 0xFF

        sid.clockOscillator(0)
        sid.voices[0].control = 0

        for _ in 0..<SID.waveformDACHoldCycles {
            sid.clockOscillator(0)
        }

        XCTAssertEqual(sid.voices[0].waveformDACOutput, 0xF00)
        XCTAssertEqual(sid.voices[0].waveformDACHoldCyclesRemaining, 0)
        XCTAssertGreaterThan(sid.waveformOutput(0), 0)

        sid.clockOscillator(0)

        XCTAssertLessThan(sid.voices[0].waveformDACOutput, 0xF00)
        XCTAssertGreaterThan(sid.voices[0].waveformDACOutput, 0)
        XCTAssertEqual(sid.voices[0].waveformDACHoldCyclesRemaining, SID.waveformDACLeakStepCycles)
        XCTAssertGreaterThan(sid.waveformOutput(0), 0)
    }

    func testWaveformDACLeakRateDiffersBySIDModel() {
        let sid6581 = SID()
        sid6581.model = .mos6581
        sid6581.voices[0].waveformDACOutput = 0xF00

        let sid8580 = SID()
        sid8580.model = .mos8580
        sid8580.voices[0].waveformDACOutput = 0xF00

        sid6581.clockOscillator(0)
        sid8580.clockOscillator(0)

        XCTAssertGreaterThan(sid6581.voices[0].waveformDACOutput, sid8580.voices[0].waveformDACOutput)
        XCTAssertEqual(sid6581.voices[0].waveformDACHoldCyclesRemaining, SID.waveformDACLeakStepCycles)
        XCTAssertEqual(sid8580.voices[0].waveformDACHoldCyclesRemaining, SID.waveformDACLeakStepCycles)
    }

    func testFloatingWaveformDACEventuallySettlesToSilence() {
        let sid = SID()
        sid.voices[0].waveformDACOutput = 0xF00
        sid.voices[0].envelopeLevel = 0xFF

        for _ in 0..<20_000 {
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
        XCTAssertGreaterThan(sid.waveformOutput(0), 0)
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

    func testEnvelopeDACOutputDiffersBySIDModel() {
        let sid6581 = SID()
        sid6581.model = .mos6581

        let sid8580 = SID()
        sid8580.model = .mos8580

        XCTAssertEqual(sid6581.envelopeDACLevel(0), 0)
        XCTAssertEqual(sid8580.envelopeDACLevel(0), 0)
        XCTAssertEqual(sid6581.envelopeDACLevel(0xFF), 0xFF)
        XCTAssertEqual(sid8580.envelopeDACLevel(0xFF), 0xFF)
        XCTAssertGreaterThan(sid6581.envelopeDACLevel(0x80), sid8580.envelopeDACLevel(0x80))
        XCTAssertEqual(sid8580.envelopeDACLevel(0x80), 0x80)
    }

    func testEnvelopeDACModelAffectsVoiceOutputAtMidEnvelopeLevels() {
        let sid6581 = SID()
        sid6581.model = .mos6581
        sid6581.voices[0].control = 0x20
        sid6581.voices[0].accumulator = 0xFFFFFF
        sid6581.voices[0].envelopeLevel = 0x80

        let sid8580 = SID()
        sid8580.model = .mos8580
        sid8580.voices[0].control = 0x20
        sid8580.voices[0].accumulator = 0xFFFFFF
        sid8580.voices[0].envelopeLevel = 0x80

        XCTAssertGreaterThan(sid6581.waveformOutput(0), sid8580.waveformOutput(0))

        sid6581.voices[0].envelopeLevel = 0xFF
        sid8580.voices[0].envelopeLevel = 0xFF

        XCTAssertEqual(sid6581.waveformOutput(0), sid8580.waveformOutput(0))
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

    func testVolumeDACOffsetIsNotScaledTwiceByMasterVolume() {
        let sid = SID()
        sid.model = .mos6581
        sid.writeRegister(0x18, value: 0x08)

        sid.generateSample()

        let expected = Float(SID.volumeDAC6581[8]) / 32768.0
        XCTAssertEqual(sid.sampleBuffer[0], expected, accuracy: 0.000_001)
        XCTAssertGreaterThan(sid.sampleBuffer[0], Float(SID.volumeDAC6581[8] * 8 / 15) / 32768.0)
    }

    func testCompatibilityAccuracyModeAveragesAudioAcrossCycles() {
        let sid = SID()
        sid.model = .mos6581
        sid.accuracyMode = .compatibility
        sid.clockRate = SID.sampleRate * 4

        sid.writeRegister(0x18, value: 0x00)
        sid.tick()
        sid.writeRegister(0x18, value: 0x01)
        sid.tick()
        sid.writeRegister(0x18, value: 0x02)
        sid.tick()
        sid.writeRegister(0x18, value: 0x03)
        sid.tick()

        let lastInstant = Float(sid.applyOutputStage(input: SID.volumeDAC6581[3])) / 32768.0
        XCTAssertEqual(sid.sampleWritePos, 1)
        XCTAssertGreaterThan(sid.sampleBuffer[0], 0)
        XCTAssertLessThan(sid.sampleBuffer[0], lastInstant)
        XCTAssertEqual(sid.audioAccumulatorCount, 0)
    }

    func testFastAccuracyModeSamplesInstantaneousAudioOnTick() {
        let sid = SID()
        sid.model = .mos6581
        sid.accuracyMode = .fast
        sid.clockRate = SID.sampleRate * 4

        sid.writeRegister(0x18, value: 0x00)
        sid.tick()
        sid.writeRegister(0x18, value: 0x01)
        sid.tick()
        sid.writeRegister(0x18, value: 0x02)
        sid.tick()
        sid.writeRegister(0x18, value: 0x03)
        sid.tick()

        let lastInstant = Float(SID.volumeDAC6581[3]) / 32768.0
        XCTAssertEqual(sid.sampleWritePos, 1)
        XCTAssertEqual(sid.sampleBuffer[0], lastInstant, accuracy: 0.000_001)
        XCTAssertEqual(sid.audioAccumulatorCount, 0)
    }

    func testFastAccuracyModeLeavesOutputStageLinear() {
        let sid = SID()
        sid.accuracyMode = .fast

        XCTAssertEqual(sid.applyOutputStage(input: 16_000), 16_000)
        XCTAssertEqual(sid.applyOutputStage(input: -16_000), -16_000)
    }

    func testCompatibilityAccuracyModeShapesOutputStageBySIDModel() {
        let sid6581 = SID()
        sid6581.model = .mos6581
        sid6581.accuracyMode = .compatibility

        let sid8580 = SID()
        sid8580.model = .mos8580
        sid8580.accuracyMode = .compatibility

        let shaped6581 = sid6581.applyOutputStage(input: 16_000)
        let shaped8580 = sid8580.applyOutputStage(input: 16_000)

        XCTAssertNotEqual(shaped6581, 16_000)
        XCTAssertNotEqual(shaped8580, 16_000)
        XCTAssertGreaterThan(shaped6581, 16_000)
        XCTAssertLessThan(shaped8580, 16_000)
        XCTAssertGreaterThan(shaped6581, shaped8580)
    }

    func testSIDAnalogCompatibilityProfilesAreModelSpecific() {
        let sid6581 = SID()
        sid6581.model = .mos6581

        let sid8580 = SID()
        sid8580.model = .mos8580

        XCTAssertGreaterThan(sid6581.analogProfile.outputPositiveDrive, sid8580.analogProfile.outputPositiveDrive)
        XCTAssertLessThan(sid6581.analogProfile.outputNegativeDrive, 1.0)
        XCTAssertGreaterThan(sid6581.analogProfile.filterInputDrive, sid8580.analogProfile.filterInputDrive)
        XCTAssertGreaterThan(sid6581.analogProfile.filterInputDCBleed, sid8580.analogProfile.filterInputDCBleed)
        XCTAssertGreaterThan(sid6581.analogProfile.externalInputGain, sid8580.analogProfile.externalInputGain)
        XCTAssertLessThan(sid6581.analogProfile.outputSmoothingCoefficient, sid8580.analogProfile.outputSmoothingCoefficient)
    }

    func testCompatibilityAccuracyModeAffectsGeneratedSamples() {
        let fast = SID()
        fast.model = .mos6581
        fast.accuracyMode = .fast
        fast.setExternalAudioInput(16_000)
        fast.writeRegister(0x18, value: 0x0F)

        let compatibility = SID()
        compatibility.model = .mos6581
        compatibility.accuracyMode = .compatibility
        compatibility.setExternalAudioInput(16_000)
        compatibility.writeRegister(0x18, value: 0x0F)

        fast.generateSample()
        compatibility.generateSample()

        XCTAssertNotEqual(compatibility.sampleBuffer[0], fast.sampleBuffer[0])
    }

    func testFastAccuracyModeLeavesSampleOutputInstantaneous() {
        let sid = SID()
        sid.accuracyMode = .fast

        XCTAssertEqual(sid.sampleOutput(20_000), 20_000)
        XCTAssertEqual(sid.audioOutputState, 0)
    }

    func testCompatibilityAccuracyModeSmoothsSampleOutputBySIDModel() {
        let sid6581 = SID()
        sid6581.model = .mos6581
        sid6581.accuracyMode = .compatibility

        let sid8580 = SID()
        sid8580.model = .mos8580
        sid8580.accuracyMode = .compatibility

        let output6581 = sid6581.sampleOutput(20_000)
        let output8580 = sid8580.sampleOutput(20_000)

        XCTAssertGreaterThan(output6581, 0)
        XCTAssertLessThan(output6581, 20_000)
        XCTAssertGreaterThan(output8580, output6581)
        XCTAssertEqual(sid6581.audioOutputState, Double(output6581), accuracy: 0.5)
        XCTAssertEqual(sid8580.audioOutputState, Double(output8580), accuracy: 0.5)
    }

    func testFastAccuracyModeLeavesFilterInputLinear() {
        let sid = SID()
        sid.accuracyMode = .fast
        sid.writeRegister(0x18, value: 0x0F)

        XCTAssertEqual(sid.filterInputDrive(16_000), 16_000, accuracy: 0.0001)
        XCTAssertEqual(sid.filterInputDrive(-16_000), -16_000, accuracy: 0.0001)
    }

    func testCompatibilityAccuracyModeShapesFilterInputBySIDModel() {
        let sid6581 = SID()
        sid6581.model = .mos6581
        sid6581.accuracyMode = .compatibility
        sid6581.writeRegister(0x18, value: 0x0F)

        let sid8580 = SID()
        sid8580.model = .mos8580
        sid8580.accuracyMode = .compatibility
        sid8580.writeRegister(0x18, value: 0x0F)

        let shaped6581 = sid6581.filterInputDrive(16_000)
        let shaped8580 = sid8580.filterInputDrive(16_000)

        XCTAssertGreaterThan(shaped6581, 16_000)
        XCTAssertLessThan(shaped8580, 16_000)
        XCTAssertGreaterThan(shaped6581, shaped8580)
        XCTAssertEqual(sid6581.filterInputDrive(0), 0)
    }

    func testCompatibilityAccuracyModeAffectsFilteredAudioSignature() {
        func configuredSID(_ mode: SID.AccuracyMode) -> SID {
            let sid = SID()
            sid.model = .mos6581
            sid.accuracyMode = mode
            sid.voices[0].control = 0x20
            sid.voices[0].accumulator = 0xFFFFFF
            sid.voices[0].envelopeLevel = 0xFF
            sid.writeRegister(0x15, value: 0x00)
            sid.writeRegister(0x16, value: 0x18)
            sid.writeRegister(0x17, value: 0x01)
            sid.writeRegister(0x18, value: 0x1F)
            return sid
        }

        let fast = configuredSID(.fast)
        let compatibility = configuredSID(.compatibility)

        for _ in 0..<16 {
            fast.generateSample()
            compatibility.generateSample()
        }

        let fastSignature = fast.recentAudioSignature(sampleCount: 16)
        let compatibilitySignature = compatibility.recentAudioSignature(sampleCount: 16)

        XCTAssertNotEqual(fastSignature.sum, compatibilitySignature.sum)
        XCTAssertGreaterThan(compatibilitySignature.absoluteSum, fastSignature.absoluteSum)
    }

    func test6581FilterDoesNotSelfChargeFromVolumeDACWhenNoInputIsRouted() {
        let sid = SID()
        sid.model = .mos6581
        sid.accuracyMode = .compatibility
        sid.writeRegister(0x18, value: 0x1F)

        for _ in 0..<64 {
            _ = sid.mixedAudioOutput()
        }

        XCTAssertEqual(sid.lastDirectOutput, 0)
        XCTAssertEqual(sid.lastFilterInput, 0)
        XCTAssertEqual(sid.lastFilterOutput, 0)
        XCTAssertEqual(sid.filterLow, 0)
        XCTAssertEqual(sid.filterBand, 0)
        XCTAssertEqual(sid.filterHigh, 0)
        XCTAssertGreaterThan(sid.lastMixedOutput, 0)
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

    func testFilterCutoffMasksToElevenBits() {
        let sid = SID()
        sid.model = .mos8580
        sid.filterCutoff = 0xFFFF

        XCTAssertEqual(sid.normalizedFilterCutoffValue(sid.filterCutoff), 0x07FF)
        XCTAssertEqual(sid.normalizedFilterCutoff, 0.284, accuracy: 0.000_001)

        sid.model = .mos6581
        sid.filterCutoff = 0x0800

        XCTAssertEqual(sid.normalizedFilterCutoffValue(sid.filterCutoff), 0)
        XCTAssertEqual(sid.normalizedFilterCutoff, 0.003, accuracy: 0.000_001)
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

    func testRoutedVoiceChargesFilterStateBeforeOutputModeIsEnabled() {
        let sid = SID()
        sid.model = .mos8580
        sid.voices[0].control = 0x20
        sid.voices[0].accumulator = 0xFFFFFF
        sid.voices[0].envelopeLevel = 0xFF
        sid.writeRegister(0x15, value: 0x00)
        sid.writeRegister(0x16, value: 0x30)
        sid.writeRegister(0x17, value: 0x01)
        sid.writeRegister(0x18, value: 0x0F)

        for _ in 0..<16 {
            _ = sid.mixedAudioOutput()
        }

        XCTAssertFalse(sid.filterModeSelected)
        XCTAssertEqual(sid.lastFilterOutput, 0)
        XCTAssertNotEqual(sid.filterBand, 0)
        let chargedLow = sid.filterLow
        let chargedBand = sid.filterBand

        sid.writeRegister(0x18, value: 0x1F)
        let output = sid.mixedAudioOutput()

        XCTAssertTrue(sid.filterModeSelected)
        XCTAssertNotEqual(sid.filterLow, chargedLow)
        XCTAssertNotEqual(sid.filterBand, chargedBand)
        XCTAssertGreaterThan(sid.lastFilterOutput, 0)
        XCTAssertGreaterThan(output, 0)
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

    func testFastAccuracyModeLeavesExternalAudioPathLinear() {
        let sid = SID()
        sid.accuracyMode = .fast
        sid.setExternalAudioInput(12_000)

        XCTAssertEqual(sid.externalAudioPathInput(), 12_000)
    }

    func testCompatibilityAccuracyModeShapesExternalAudioInputBySIDModel() {
        let sid6581 = SID()
        sid6581.model = .mos6581
        sid6581.accuracyMode = .compatibility
        sid6581.setExternalAudioInput(12_000)

        let sid8580 = SID()
        sid8580.model = .mos8580
        sid8580.accuracyMode = .compatibility
        sid8580.setExternalAudioInput(12_000)

        XCTAssertEqual(sid6581.externalAudioPathInput(), 13_440)
        XCTAssertEqual(sid8580.externalAudioPathInput(), 8_640)
        XCTAssertGreaterThan(sid6581.externalAudioPathInput(), sid8580.externalAudioPathInput())

        sid6581.setExternalAudioInput(32_767)
        XCTAssertEqual(sid6581.externalAudioPathInput(), 32_767)
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

    func testExternalAudioRoutingUsesModelShapedInput() {
        let direct = SID()
        direct.model = .mos6581
        direct.accuracyMode = .compatibility
        direct.setExternalAudioInput(12_000)
        direct.writeRegister(0x18, value: 0x0F)

        let filtered = SID()
        filtered.model = .mos6581
        filtered.accuracyMode = .compatibility
        filtered.setExternalAudioInput(12_000)
        filtered.writeRegister(0x15, value: 0x00)
        filtered.writeRegister(0x16, value: 0x08)
        filtered.writeRegister(0x17, value: 0x08)
        filtered.writeRegister(0x18, value: 0x1F)

        _ = direct.mixedAudioOutput()
        _ = filtered.mixedAudioOutput()

        XCTAssertEqual(direct.lastDirectOutput, direct.externalAudioPathInput())
        XCTAssertEqual(direct.lastFilterInput, 0)
        XCTAssertEqual(filtered.lastDirectOutput, 0)
        XCTAssertEqual(filtered.lastFilterInput, filtered.externalAudioPathInput())
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

    func testOscillatorSyncRefreshesDestinationWaveformDACFromResetPhase() {
        let sid = SID()
        sid.voices[0].control = 0x22
        sid.voices[0].accumulator = 0xF00000
        sid.voices[0].frequency = 0
        sid.voices[2].accumulator = 0x7FFFFF
        sid.voices[2].frequency = 1

        sid.tick()

        XCTAssertEqual(sid.voices[0].accumulator, 0)
        XCTAssertEqual(sid.voices[0].waveformDACOutput, 0)
        XCTAssertEqual(sid.voices[0].waveformDACHoldCyclesRemaining, SID.waveformDACHoldCycles)
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

    func testTestBitControlWriteClearsFloatingWaveformDAC() {
        let sid = SID()
        sid.voices[1].control = 0x20
        sid.voices[1].accumulator = 0xF00000
        sid.voices[1].frequency = 0
        sid.voices[1].envelopeLevel = 0xFF

        sid.clockOscillator(1)

        XCTAssertEqual(sid.voices[1].waveformDACOutput, 0xF00)
        XCTAssertEqual(sid.voices[1].waveformDACHoldCyclesRemaining, SID.waveformDACHoldCycles)

        sid.writeRegister(0x0B, value: 0x28)

        XCTAssertEqual(sid.voices[1].accumulator, 0)
        XCTAssertEqual(sid.voices[1].shiftRegister, 0)
        XCTAssertEqual(sid.voices[1].waveformDACOutput, 0)
        XCTAssertEqual(sid.voices[1].waveformDACHoldCyclesRemaining, 0)
        XCTAssertEqual(sid.waveformOutput(1), 0)
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
