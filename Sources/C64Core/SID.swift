import Foundation

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// MOS 6581 SID (Sound Interface Device) emulation.
/// Simplified but functional: 3 voices with waveforms, ADSR, and filter.
public final class SID {

    public enum Model: String, Codable, Equatable {
        case mos6581
        case mos8580
    }

    public enum AccuracyMode: String, Codable, Equatable {
        case fast
        case compatibility
    }

    public struct AudioSignature: Equatable {
        public let sampleCount: Int
        public let minimum: Float
        public let maximum: Float
        public let sum: Double
        public let absoluteSum: Double
        public let mean: Double
        public let rootMeanSquare: Double
        public let zeroCrossings: Int
    }

    public struct AudioDebugState: Equatable {
        public let accuracyMode: AccuracyMode
        public let sampleCycleCounter: Double
        public let cyclesPerSample: Double
        public let audioAccumulator: Double
        public let audioAccumulatorCount: Int
        public let audioOutputState: Double
        public let directOutput: Int32
        public let filterInput: Int32
        public let filterOutput: Int32
        public let mixedOutput: Int32
        public let externalAudioInput: Int32
        public let externalAudioPathInput: Int32
        public let filterCutoff: UInt16
        public let filterResonance: UInt8
        public let filterControl: UInt8
        public let volumeFilter: UInt8
        public let volume: UInt8
        public let normalizedFilterCutoffValue: UInt16
        public let normalizedFilterCutoff: Double
        public let filterDamping: Double
        public let voice1FilterEnabled: Bool
        public let voice2FilterEnabled: Bool
        public let voice3FilterEnabled: Bool
        public let externalInputFiltered: Bool
        public let filterLowPassEnabled: Bool
        public let filterBandPassEnabled: Bool
        public let filterHighPassEnabled: Bool
        public let voice3Off: Bool
        public let dataBusLatch: UInt8
        public let dataBusLatchCyclesRemaining: Int
        public let oscillator3Readback: UInt8
        public let oscillator3ReadbackValid: Bool
        public let envelope3Readback: UInt8
        public let envelope3ReadbackValid: Bool
        public let paddleX: UInt8
        public let paddleY: UInt8
        public let paddleTargetX: UInt8
        public let paddleTargetY: UInt8
        public let paddleScanActive: Bool
        public let paddleScanCounter: Int?
        public let filterLow: Double
        public let filterBand: Double
        public let filterHigh: Double
        public let sampleWritePosition: Int
    }

    public struct VoiceDebugState: Equatable {
        public let frequency: UInt16
        public let pulseWidth: UInt16
        public let control: UInt8
        public let attackDecay: UInt8
        public let sustainRelease: UInt8
        public let accumulator: UInt32
        public let shiftRegister: UInt32
        public let envelopeLevel: UInt8
        public let envelopeOutput: UInt8
        public let sustainLevel: UInt8
        public let envelopeState: String
        public let exponentialCounter: UInt16
        public let exponentialPeriod: UInt16
        public let holdZero: Bool
        public let gate: Bool
        public let controlGate: Bool
        public let sync: Bool
        public let ringMod: Bool
        public let testBit: Bool
        public let waveTriangle: Bool
        public let waveSawtooth: Bool
        public let wavePulse: Bool
        public let waveNoise: Bool
        public let hasWaveform: Bool
        public let oscillatorMSBRose: Bool
        public let noiseClockRose: Bool
        public let rateCounter: UInt16
        public let selectedRatePeriod: UInt16
        public let oscillatorOutput: UInt16
        public let waveformOutput: Int16
        public let waveformDACOutput: UInt16
        public let waveformDACHoldCyclesRemaining: Int
    }

    struct AnalogProfile: Equatable {
        let outputPositiveDrive: Double
        let outputNegativeDrive: Double
        let outputPostDrive: Double
        let filterInputDrive: Double
        let filterInputDCBleed: Double
        let externalInputGain: Double
        let outputSmoothingCoefficient: Double
    }

    // MARK: - Constants

    public var model: Model = .mos6581
    public var accuracyMode: AccuracyMode = .fast
    public var clockRate: Double = 985_248.0  // PAL
    public static let sampleRate: Double = 44100.0
    var cyclesPerSample: Double { clockRate / Self.sampleRate }

    // MARK: - Voice

    public struct Voice {
        var frequency: UInt16 = 0       // $D400/$D401
        var pulseWidth: UInt16 = 0      // $D402/$D403
        var control: UInt8 = 0          // $D404
        var attackDecay: UInt8 = 0      // $D405
        var sustainRelease: UInt8 = 0   // $D406

        // Internal state
        var accumulator: UInt32 = 0
        var shiftRegister: UInt32 = 0x7FFFF8
        var envelopeCounter: UInt32 = 0
        var envelopeLevel: UInt8 = 0
        var envelopeState: EnvelopeState = .release
        var exponentialCounter: UInt16 = 0
        var exponentialPeriod: UInt16 = 1
        var holdZero: Bool = false
        var gate: Bool = false
        var rateCounter: UInt16 = 0
        var waveformDACOutput: UInt16 = 0
        var waveformDACHoldCyclesRemaining: Int = 0

        var waveTriangle: Bool { control & 0x10 != 0 }
        var waveSawtooth: Bool { control & 0x20 != 0 }
        var wavePulse: Bool { control & 0x40 != 0 }
        var waveNoise: Bool { control & 0x80 != 0 }
        var hasWaveform: Bool { control & 0xF0 != 0 }
        var ringMod: Bool { control & 0x04 != 0 }
        var sync: Bool { control & 0x02 != 0 }
        var testBit: Bool { control & 0x08 != 0 }

        var attack: UInt8 { attackDecay >> 4 }
        var decay: UInt8 { attackDecay & 0x0F }
        var sustain: UInt8 { sustainRelease >> 4 }
        var releaseVal: UInt8 { sustainRelease & 0x0F }
    }

    enum EnvelopeState {
        case attack, decay, sustain, release
    }

    // MARK: - State

    public var voices = [Voice(), Voice(), Voice()]

    /// Filter
    var filterCutoff: UInt16 = 0     // $D415/$D416 (11-bit)
    var filterResonance: UInt8 = 0   // $D417
    var filterControl: UInt8 = 0     // $D418 low nibble: voice routing
    var volumeFilter: UInt8 = 0      // $D418
    var externalAudioInput: Int32 = 0

    var volume: UInt8 { volumeFilter & 0x0F }
    var filterLP: Bool { volumeFilter & 0x10 != 0 }
    var filterBP: Bool { volumeFilter & 0x20 != 0 }
    var filterHP: Bool { volumeFilter & 0x40 != 0 }
    var voice3Off: Bool { volumeFilter & 0x80 != 0 }
    var externalInputFiltered: Bool { filterControl & 0x08 != 0 }
    var voiceOutputScale: Double {
        model == .mos6581 ? 1.0 : 0.82
    }
    var volumeDACOffset: Int32 {
        switch model {
        case .mos6581:
            return Self.volumeDAC6581[Int(volume)]
        case .mos8580:
            return Self.volumeDAC8580[Int(volume)]
        }
    }
    var analogProfile: AnalogProfile {
        switch model {
        case .mos6581:
            return AnalogProfile(
                outputPositiveDrive: 1.18,
                outputNegativeDrive: 0.94,
                outputPostDrive: 1.20,
                filterInputDrive: 1.35,
                filterInputDCBleed: 0.10,
                externalInputGain: 1.12,
                outputSmoothingCoefficient: 0.90
            )
        case .mos8580:
            return AnalogProfile(
                outputPositiveDrive: 1.0,
                outputNegativeDrive: 1.0,
                outputPostDrive: 1.03,
                filterInputDrive: 1.05,
                filterInputDCBleed: 0,
                externalInputGain: 0.72,
                outputSmoothingCoefficient: 0.96
            )
        }
    }
    var normalizedFilterCutoff: Double {
        let normalized = Double(normalizedFilterCutoffValue(filterCutoff)) / 2047.0
        switch model {
        case .mos6581:
            return 0.003 + pow(normalized, 1.7) * 0.18
        case .mos8580:
            return 0.004 + normalized * 0.28
        }
    }

    func normalizedFilterCutoffValue(_ cutoff: UInt16) -> UInt16 {
        cutoff & 0x07FF
    }
    var filterDamping: Double {
        let resonance = Double(filterResonance)
        switch model {
        case .mos6581:
            return max(0.42, 1.45 - resonance * 0.045)
        case .mos8580:
            return max(0.25, 1.25 - resonance * 0.065)
        }
    }
    var filterModeSelected: Bool {
        filterLP || filterBP || filterHP
    }

    /// Latched analog paddle values read through POTX/POTY ($D419/$D41A).
    var paddleX: UInt8 = 0xFF
    var paddleY: UInt8 = 0xFF
    var paddleTargetX: UInt8 = 0xFF
    var paddleTargetY: UInt8 = 0xFF
    var paddleScanCounter: Int?
    public var continuousPaddleScanEnabled = false
    /// Last value observed on the SID-local data bus for direct chip reads.
    var dataBusLatch: UInt8 = 0
    /// Remaining cycles before the floating SID-local data bus decays.
    var dataBusLatchCyclesRemaining: Int = 0

    // Filter state
    var filterLow: Double = 0
    var filterBand: Double = 0
    var filterHigh: Double = 0
    var oscillator3Readback: UInt8 = 0
    var oscillator3ReadbackValid = false
    var envelope3Readback: UInt8 = 0
    var envelope3ReadbackValid = false

    /// Audio sample accumulator
    var sampleCycleCounter: Double = 0
    var audioAccumulator: Double = 0
    var audioAccumulatorCount: Int = 0
    var audioOutputState: Double = 0
    var lastDirectOutput: Int32 = 0
    var lastFilterInput: Int32 = 0
    var lastFilterOutput: Int32 = 0
    var lastMixedOutput: Int32 = 0

    /// Per-cycle oscillator MSB rising-edge flags used for hard sync.
    var oscillatorMSBRose = [Bool](repeating: false, count: 3)
    /// Per-cycle accumulator bit-19 rising-edge flags used to clock noise LFSRs.
    var noiseClockRose = [Bool](repeating: false, count: 3)

    /// Ring buffer for audio output
    public var sampleBuffer = [Float](repeating: 0, count: 8192)
    public var sampleWritePos: Int = 0
    public var sampleReadPos: Int = 0
    var sampleBufferedCount: Int = 0
    public var onSampleGenerated: ((Float) -> Void)?
    private let sampleBufferLock = NSLock()

    // MARK: - ADSR rate table (cycles per increment)

    // Measured SID envelope rate-counter comparison periods at a 1 MHz PHI2
    // reference clock. The programmed ADSR times describe a full 256-step
    // sweep, so the per-step comparison periods are the rounded cycle counts
    // below rather than the previously used off-by-one periods.
    static let attackRates: [UInt16] = [
        8, 31, 62, 94, 148, 219, 266, 312,
        391, 976, 1953, 3125, 3906, 11719, 19531, 31250
    ]

    static let decayReleaseRates: [UInt16] = [
        8, 31, 62, 94, 148, 219, 266, 312,
        391, 976, 1953, 3125, 3906, 11719, 19531, 31250
    ]

    static let dataBusLatchHoldCycles = 0x2000
    static let dataBusLatchLeakStepCycles = 0x0200
    static let envelopeRateCounterMask: UInt16 = 0x7FFF
    static let waveformDACHoldCycles = 128
    static let waveformDACLeakStepCycles = 32
    static let paddleScanCycles = 512

    static func loadedExponentialPeriod(at envelopeLevel: UInt8) -> UInt16? {
        switch envelopeLevel {
        case 0xFF:
            return 1
        case 0x5D:
            return 2
        case 0x36:
            return 4
        case 0x1A:
            return 8
        case 0x0E:
            return 16
        case 0x06:
            return 30
        case 0x00:
            return 1
        default:
            return nil
        }
    }

    static let volumeDAC6581: [Int32] = [
        0, 80, 170, 285, 425, 590, 780, 1_000,
        1_245, 1_515, 1_805, 2_115, 2_450, 2_805, 3_175, 3_560
    ]

    static let volumeDAC8580: [Int32] = [
        0, 18, 37, 57, 78, 100, 122, 144,
        166, 188, 210, 232, 253, 274, 294, 314
    ]

    func envelopeDACLevel(_ level: UInt8) -> UInt16 {
        switch model {
        case .mos6581:
            guard level != 0 else { return 0 }
            guard level != 0xFF else { return 0xFF }
            // The 6581 envelope DAC is not a perfectly terminated linear DAC.
            // This bounded curve is a deterministic approximation until we
            // replace it with measured chip tables.
            let normalized = Double(level) / 255.0
            return UInt16((pow(normalized, 0.92) * 255.0).rounded().clamped(to: 0...255))
        case .mos8580:
            return UInt16(level)
        }
    }

    static func exponentialPeriod(for envelopeLevel: UInt8) -> UInt16 {
        switch envelopeLevel {
        case 0xFF:
            return 1
        case 0x5D...0xFE:
            return 2
        case 0x36...0x5C:
            return 4
        case 0x1A...0x35:
            return 8
        case 0x0E...0x19:
            return 16
        case 0x06...0x0D:
            return 30
        default:
            return 1
        }
    }

    // MARK: - Init

    public init() {}

    public func reset() {
        voices = [Voice(), Voice(), Voice()]
        filterCutoff = 0
        filterResonance = 0
        filterControl = 0
        volumeFilter = 0
        externalAudioInput = 0
        paddleX = 0xFF
        paddleY = 0xFF
        paddleTargetX = 0xFF
        paddleTargetY = 0xFF
        paddleScanCounter = nil
        dataBusLatch = 0
        dataBusLatchCyclesRemaining = 0
        filterLow = 0
        filterBand = 0
        filterHigh = 0
        oscillator3Readback = 0
        oscillator3ReadbackValid = false
        envelope3Readback = 0
        envelope3ReadbackValid = false
        sampleCycleCounter = 0
        audioAccumulator = 0
        audioAccumulatorCount = 0
        audioOutputState = 0
        lastDirectOutput = 0
        lastFilterInput = 0
        lastFilterOutput = 0
        lastMixedOutput = 0
        oscillatorMSBRose = [Bool](repeating: false, count: 3)
        noiseClockRose = [Bool](repeating: false, count: 3)
        sampleBufferLock.lock()
        sampleWritePos = 0
        sampleReadPos = 0
        sampleBufferedCount = 0
        for index in sampleBuffer.indices {
            sampleBuffer[index] = 0
        }
        sampleBufferLock.unlock()
    }

    // MARK: - Tick

    /// Advance one system clock cycle.
    public func tick() {
        ageDataBusLatch()
        tickPaddleScan()
        sampleVoice3Readbacks()

        // Update all oscillators before applying sync so source edges are
        // independent of voice iteration order.
        for i in 0..<3 {
            clockOscillator(i)
        }
        applyOscillatorSync()

        for i in 0..<3 {
            clockEnvelope(i)
        }

        if accuracyMode == .compatibility {
            accumulateAudioOutput()
        }

        // Generate audio sample at the right rate
        sampleCycleCounter += 1
        if sampleCycleCounter >= cyclesPerSample {
            sampleCycleCounter -= cyclesPerSample
            if accuracyMode == .compatibility {
                generateAccumulatedSample()
            } else {
                generateSample()
            }
        }
    }

    func sampleVoice3Readbacks() {
        oscillator3Readback = UInt8((oscillatorReadbackOutput(2) >> 4) & 0xFF)
        oscillator3ReadbackValid = true
        envelope3Readback = voices[2].envelopeLevel
        envelope3ReadbackValid = true
    }

    public func recentAudioSignature(sampleCount requestedCount: Int) -> AudioSignature {
        sampleBufferLock.lock()
        let sampleWritePos = self.sampleWritePos
        let sampleBuffer = self.sampleBuffer
        sampleBufferLock.unlock()

        let sampleCount = min(max(requestedCount, 0), sampleBuffer.count)
        guard sampleCount > 0 else {
            return AudioSignature(
                sampleCount: 0,
                minimum: 0,
                maximum: 0,
                sum: 0,
                absoluteSum: 0,
                mean: 0,
                rootMeanSquare: 0,
                zeroCrossings: 0
            )
        }

        var minimum = Float.infinity
        var maximum = -Float.infinity
        var sum = 0.0
        var absoluteSum = 0.0
        var sumOfSquares = 0.0
        var zeroCrossings = 0
        var previousNonZeroSign: Int?
        let start = (sampleWritePos - sampleCount + sampleBuffer.count) % sampleBuffer.count

        for offset in 0..<sampleCount {
            let sample = sampleBuffer[(start + offset) % sampleBuffer.count]
            minimum = min(minimum, sample)
            maximum = max(maximum, sample)
            sum += Double(sample)
            absoluteSum += Double(abs(sample))
            sumOfSquares += Double(sample) * Double(sample)

            let sign = sample < 0 ? -1 : (sample > 0 ? 1 : 0)
            if sign != 0 {
                if let previousNonZeroSign, previousNonZeroSign != sign {
                    zeroCrossings += 1
                }
                previousNonZeroSign = sign
            }
        }

        return AudioSignature(
            sampleCount: sampleCount,
            minimum: minimum,
            maximum: maximum,
            sum: sum,
            absoluteSum: absoluteSum,
            mean: sum / Double(sampleCount),
            rootMeanSquare: sqrt(sumOfSquares / Double(sampleCount)),
            zeroCrossings: zeroCrossings
        )
    }

    public func recentAudioSummary(sampleCount requestedCount: Int) -> SIDTraceAudioSummary {
        sampleBufferLock.lock()
        let sampleWritePos = self.sampleWritePos
        let sampleBuffer = self.sampleBuffer
        sampleBufferLock.unlock()

        let sampleCount = min(max(requestedCount, 0), sampleBuffer.count)
        guard sampleCount > 0 else {
            return .empty
        }

        let start = (sampleWritePos - sampleCount + sampleBuffer.count) % sampleBuffer.count
        let samples = (0..<sampleCount).map { offset in
            sampleBuffer[(start + offset) % sampleBuffer.count]
        }
        return SIDTraceAudioSummary(samples: samples, sampleRate: Self.sampleRate)
    }

    public func debugRegisterSnapshot() -> [UInt8] {
        (0..<0x20).map { debugRegisterValue(UInt16($0)) }
    }

    public func readableRegisterSnapshot() -> [UInt8] {
        (0..<0x20).map { peekReadableRegisterValue(UInt16($0)) }
    }

    public func debugAudioState() -> AudioDebugState {
        AudioDebugState(
            accuracyMode: accuracyMode,
            sampleCycleCounter: sampleCycleCounter,
            cyclesPerSample: cyclesPerSample,
            audioAccumulator: audioAccumulator,
            audioAccumulatorCount: audioAccumulatorCount,
            audioOutputState: audioOutputState,
            directOutput: lastDirectOutput,
            filterInput: lastFilterInput,
            filterOutput: lastFilterOutput,
            mixedOutput: lastMixedOutput,
            externalAudioInput: externalAudioInput,
            externalAudioPathInput: externalAudioPathInput(),
            filterCutoff: filterCutoff,
            filterResonance: filterResonance,
            filterControl: filterControl,
            volumeFilter: volumeFilter,
            volume: volume,
            normalizedFilterCutoffValue: normalizedFilterCutoffValue(filterCutoff),
            normalizedFilterCutoff: normalizedFilterCutoff,
            filterDamping: filterDamping,
            voice1FilterEnabled: filterControl & 0x01 != 0,
            voice2FilterEnabled: filterControl & 0x02 != 0,
            voice3FilterEnabled: filterControl & 0x04 != 0,
            externalInputFiltered: externalInputFiltered,
            filterLowPassEnabled: filterLP,
            filterBandPassEnabled: filterBP,
            filterHighPassEnabled: filterHP,
            voice3Off: voice3Off,
            dataBusLatch: dataBusLatch,
            dataBusLatchCyclesRemaining: dataBusLatchCyclesRemaining,
            oscillator3Readback: oscillator3Readback,
            oscillator3ReadbackValid: oscillator3ReadbackValid,
            envelope3Readback: envelope3Readback,
            envelope3ReadbackValid: envelope3ReadbackValid,
            paddleX: paddleX,
            paddleY: paddleY,
            paddleTargetX: paddleTargetX,
            paddleTargetY: paddleTargetY,
            paddleScanActive: paddleScanCounter != nil,
            paddleScanCounter: paddleScanCounter,
            filterLow: filterLow,
            filterBand: filterBand,
            filterHigh: filterHigh,
            sampleWritePosition: sampleWritePos
        )
    }

    public func debugVoiceStates() -> [VoiceDebugState] {
        voices.indices.map { index in
            let voice = voices[index]
            return VoiceDebugState(
                frequency: voice.frequency,
                pulseWidth: normalizedPulseWidth(voice.pulseWidth),
                control: voice.control,
                attackDecay: voice.attackDecay,
                sustainRelease: voice.sustainRelease,
                accumulator: voice.accumulator,
                shiftRegister: voice.shiftRegister,
                envelopeLevel: voice.envelopeLevel,
                envelopeOutput: UInt8(envelopeDACLevel(voice.envelopeLevel)),
                sustainLevel: sustainLevel(for: index),
                envelopeState: String(describing: voice.envelopeState),
                exponentialCounter: voice.exponentialCounter,
                exponentialPeriod: voice.exponentialPeriod,
                holdZero: voice.holdZero,
                gate: voice.gate,
                controlGate: voice.control & 0x01 != 0,
                sync: voice.sync,
                ringMod: voice.ringMod,
                testBit: voice.testBit,
                waveTriangle: voice.waveTriangle,
                waveSawtooth: voice.waveSawtooth,
                wavePulse: voice.wavePulse,
                waveNoise: voice.waveNoise,
                hasWaveform: voice.hasWaveform,
                oscillatorMSBRose: oscillatorMSBRose[index],
                noiseClockRose: noiseClockRose[index],
                rateCounter: voice.rateCounter,
                selectedRatePeriod: selectedEnvelopeRatePeriod(for: index),
                oscillatorOutput: oscillatorOutput(index),
                waveformOutput: waveformOutput(index),
                waveformDACOutput: voice.waveformDACOutput,
                waveformDACHoldCyclesRemaining: voice.waveformDACHoldCyclesRemaining
            )
        }
    }

    func clockOscillator(_ v: Int) {
        let prevMSB = voices[v].accumulator & 0x800000
        let prevNoiseClock = voices[v].accumulator & 0x080000
        let wasNoiseCombined = voices[v].waveNoise &&
            (voices[v].waveTriangle || voices[v].waveSawtooth || voices[v].wavePulse)

        if voices[v].testBit {
            voices[v].accumulator = 0
            voices[v].shiftRegister = 0
        } else {
            voices[v].accumulator = (voices[v].accumulator + UInt32(voices[v].frequency)) & 0xFFFFFF
        }

        let newMSB = voices[v].accumulator & 0x800000
        oscillatorMSBRose[v] = prevMSB == 0 && newMSB != 0

        // Noise shift register clock on accumulator bit 19 rising edge.
        let newNoiseClock = voices[v].accumulator & 0x080000
        noiseClockRose[v] = prevNoiseClock == 0 && newNoiseClock != 0
        if noiseClockRose[v] {
            let bit22 = (voices[v].shiftRegister >> 22) & 1
            let bit17 = (voices[v].shiftRegister >> 17) & 1
            let newBit = bit22 ^ bit17
            voices[v].shiftRegister = ((voices[v].shiftRegister << 1) | newBit) & 0x7FFFFF
            if wasNoiseCombined && model == .mos6581 {
                age6581CombinedNoiseRegister(v)
            }
        }

        updateWaveformDACLatch(v)
    }

    func age6581CombinedNoiseRegister(_ v: Int) {
        // The 6581's combined noise waveforms feed analog pull-down effects
        // back into the noise generator. This deterministic approximation
        // drains the DAC-tapped bits, so repeated clocks can lock the LFSR at
        // zero until TEST reseeds it.
        let dacTappedBits: UInt32 =
            (1 << 22) | (1 << 20) | (1 << 16) | (1 << 13) |
            (1 << 11) | (1 << 7) | (1 << 4) | (1 << 2)
        voices[v].shiftRegister &= ~dacTappedBits
    }

    func updateWaveformDACLatch(_ v: Int) {
        if voices[v].hasWaveform && !voices[v].testBit {
            refreshWaveformDACLatch(v)
        } else if voices[v].waveformDACHoldCyclesRemaining > 0 {
            voices[v].waveformDACHoldCyclesRemaining -= 1
        } else if voices[v].waveformDACOutput > 0 {
            voices[v].waveformDACOutput = leakedWaveformDACOutput(voices[v].waveformDACOutput)
            if voices[v].waveformDACOutput > 0 {
                voices[v].waveformDACHoldCyclesRemaining = Self.waveformDACLeakStepCycles
            }
        }
    }

    func refreshWaveformDACLatch(_ v: Int) {
        voices[v].waveformDACOutput = oscillatorOutput(v)
        voices[v].waveformDACHoldCyclesRemaining = Self.waveformDACHoldCycles
    }

    func leakedWaveformDACOutput(_ output: UInt16) -> UInt16 {
        let divisor = model == .mos6581 ? 32 : 16
        let decrement = max(1, Int(output) / divisor)
        return UInt16(max(0, Int(output) - decrement))
    }

    func applyOscillatorSync() {
        for v in 0..<3 where voices[v].sync {
            let syncSource = (v + 2) % 3
            if oscillatorMSBRose[syncSource] {
                voices[v].accumulator = 0
                if voices[v].hasWaveform && !voices[v].testBit {
                    refreshWaveformDACLatch(v)
                }
            }
        }
    }

    func clockEnvelope(_ v: Int) {
        let gateOn = voices[v].control & 0x01 != 0

        // Gate transition
        if gateOn && !voices[v].gate {
            voices[v].envelopeState = .attack
            voices[v].holdZero = false
            voices[v].exponentialCounter = 0
            voices[v].exponentialPeriod = 1
        } else if !gateOn && voices[v].gate {
            voices[v].envelopeState = .release
            voices[v].exponentialCounter = 0
            if voices[v].envelopeLevel == 0 {
                voices[v].holdZero = true
                voices[v].exponentialPeriod = 1
            }
        }
        voices[v].gate = gateOn

        if voices[v].envelopeState == .sustain {
            if voices[v].envelopeLevel > sustainLevel(for: v) {
                voices[v].envelopeState = .decay
                voices[v].exponentialCounter = 0
                loadExponentialPeriodIfNeeded(v)
            } else {
                clockSustainRateCounter(v)
                return
            }
        }

        voices[v].rateCounter = (voices[v].rateCounter &+ 1) & Self.envelopeRateCounterMask

        let rate: UInt16
        switch voices[v].envelopeState {
        case .attack:
            rate = SID.attackRates[Int(voices[v].attack)]
        case .decay:
            rate = SID.decayReleaseRates[Int(voices[v].decay)]
        case .sustain:
            return  // No change during sustain
        case .release:
            rate = SID.decayReleaseRates[Int(voices[v].releaseVal)]
        }

        guard voices[v].rateCounter == rate else { return }
        voices[v].rateCounter = 0

        switch voices[v].envelopeState {
        case .attack:
            guard !voices[v].holdZero else { break }
            if voices[v].envelopeLevel == 0xFF {
                voices[v].envelopeLevel = 0
                voices[v].holdZero = true
                voices[v].exponentialCounter = 0
                voices[v].exponentialPeriod = 1
                break
            }
            voices[v].envelopeLevel &+= 1
            loadExponentialPeriodIfNeeded(v)
            if voices[v].envelopeLevel == 0xFF {
                voices[v].envelopeState = .decay
                voices[v].exponentialCounter = 0
            }
        case .decay:
            if voices[v].envelopeLevel <= sustainLevel(for: v) {
                voices[v].envelopeState = .sustain
                break
            }
            clockExponentialDecayStep(v)
            if voices[v].envelopeLevel <= sustainLevel(for: v) {
                voices[v].envelopeState = .sustain
            }
        case .sustain:
            break
        case .release:
            clockExponentialDecayStep(v)
        }
    }

    func sustainLevel(for v: Int) -> UInt8 {
        voices[v].sustain * 17  // 0-15 -> 0-255
    }

    func clockSustainRateCounter(_ v: Int) {
        voices[v].rateCounter = (voices[v].rateCounter &+ 1) & Self.envelopeRateCounterMask
        let rate = SID.decayReleaseRates[Int(voices[v].decay)]
        if voices[v].rateCounter == rate {
            voices[v].rateCounter = 0
        }
    }

    func selectedEnvelopeRatePeriod(for v: Int) -> UInt16 {
        switch voices[v].envelopeState {
        case .attack:
            return SID.attackRates[Int(voices[v].attack)]
        case .decay, .sustain:
            return SID.decayReleaseRates[Int(voices[v].decay)]
        case .release:
            return SID.decayReleaseRates[Int(voices[v].releaseVal)]
        }
    }

    func clockExponentialDecayStep(_ v: Int) {
        guard !voices[v].holdZero else { return }

        voices[v].exponentialCounter &+= 1
        guard voices[v].exponentialCounter >= voices[v].exponentialPeriod else { return }
        voices[v].exponentialCounter = 0

        if voices[v].envelopeLevel > 0 {
            voices[v].envelopeLevel -= 1
            loadExponentialPeriodIfNeeded(v)
        }
        if voices[v].envelopeLevel == 0 {
            voices[v].holdZero = true
        }
    }

    func loadExponentialPeriodIfNeeded(_ v: Int) {
        guard let period = SID.loadedExponentialPeriod(at: voices[v].envelopeLevel) else { return }
        voices[v].exponentialPeriod = period
    }

    // MARK: - Waveform generation

    func oscillatorOutput(_ v: Int) -> UInt16 {
        let noiseOutput = voices[v].waveNoise ? noiseWaveformOutput(v) : nil

        if let noiseOutput {
            guard let nonNoiseOutput = nonNoiseWaveformOutput(v) else {
                return noiseOutput
            }
            return noiseOutput & nonNoiseOutput
        }

        return nonNoiseWaveformOutput(v) ?? 0
    }

    func nonNoiseWaveformOutput(_ v: Int) -> UInt16? {
        if model == .mos6581 &&
            voices[v].waveTriangle &&
            voices[v].waveSawtooth &&
            voices[v].wavePulse {
            return combined6581TriangleSawtoothPulseOutput(v)
        }

        if model == .mos6581 &&
            voices[v].waveSawtooth &&
            voices[v].wavePulse &&
            !voices[v].waveTriangle {
            return combined6581SawtoothPulseOutput(v)
        }

        if model == .mos6581 &&
            voices[v].waveTriangle &&
            voices[v].waveSawtooth &&
            !voices[v].wavePulse {
            return combined6581TriangleSawtoothOutput(v)
        }

        if model == .mos6581 &&
            voices[v].waveTriangle &&
            voices[v].wavePulse &&
            !voices[v].waveSawtooth {
            return combined6581TrianglePulseOutput(v)
        }

        var output: UInt16 = 0
        var hasOutput = false

        if voices[v].waveTriangle {
            let triangle = triangleWaveformOutput(v)
            output = triangle
            hasOutput = true
        }

        if voices[v].waveSawtooth {
            let sawtooth = sawtoothWaveformOutput(v)
            output = hasOutput ? output & sawtooth : sawtooth
            hasOutput = true
        }

        if voices[v].wavePulse {
            let pulse = pulseWaveformOutput(v)
            output = hasOutput ? output & pulse : pulse
            hasOutput = true
        }

        return hasOutput ? output : nil
    }

    func triangleWaveformOutput(_ v: Int, applyRingMod: Bool = true) -> UInt16 {
        let acc = voices[v].accumulator
        let msb = acc >> 23
        var triangle: UInt16
        if msb != 0 {
            triangle = UInt16((~acc >> 11) & 0xFFF)
        } else {
            triangle = UInt16(acc >> 11) & 0xFFF
        }
        if applyRingMod && voices[v].ringMod {
            let syncSource = (v + 2) % 3
            if voices[syncSource].accumulator & 0x800000 != 0 {
                triangle ^= 0xFFF
            }
        }
        return triangle
    }

    func sawtoothWaveformOutput(_ v: Int) -> UInt16 {
        UInt16(voices[v].accumulator >> 12)
    }

    func pulseWaveformOutput(_ v: Int) -> UInt16 {
        let pulseWidth = normalizedPulseWidth(voices[v].pulseWidth)
        if pulseWidth == 0 {
            return 0
        }
        if pulseWidth == 0x0FFF {
            return 0xFFF
        }
        let phase = UInt16(voices[v].accumulator >> 12)
        return phase >= pulseWidth ? 0xFFF : 0
    }

    func normalizedPulseWidth(_ pulseWidth: UInt16) -> UInt16 {
        pulseWidth & 0x0FFF
    }

    func noiseWaveformOutput(_ v: Int) -> UInt16 {
        let sr = voices[v].shiftRegister
        var noiseBits: UInt32 = 0
        noiseBits |= ((sr >> 22) & 1) << 11
        noiseBits |= ((sr >> 20) & 1) << 10
        noiseBits |= ((sr >> 16) & 1) << 9
        noiseBits |= ((sr >> 13) & 1) << 8
        noiseBits |= ((sr >> 11) & 1) << 7
        noiseBits |= ((sr >> 7) & 1) << 6
        noiseBits |= ((sr >> 4) & 1) << 5
        noiseBits |= ((sr >> 2) & 1) << 4
        return UInt16(noiseBits)
    }

    func combined6581SawtoothPulseOutput(_ v: Int) -> UInt16 {
        sawtoothWaveformOutput(v) & triangleWaveformOutput(v, applyRingMod: false)
    }

    func combined6581TriangleSawtoothOutput(_ v: Int) -> UInt16 {
        let triangle = triangleWaveformOutput(v)
        let sawtooth = sawtoothWaveformOutput(v)
        let digital = triangle & sawtooth
        let analogPullDownMask = (triangle >> 2) | (sawtooth >> 1)
        return digital & analogPullDownMask
    }

    func combined6581TrianglePulseOutput(_ v: Int) -> UInt16 {
        let triangle = triangleWaveformOutput(v)
        let pulse = pulseWaveformOutput(v)
        let digital = triangle & pulse
        let analogPullDownMask = (triangle >> 1) | 0x010
        return digital & analogPullDownMask
    }

    func combined6581TriangleSawtoothPulseOutput(_ v: Int) -> UInt16 {
        let triangle = triangleWaveformOutput(v)
        let sawtooth = sawtoothWaveformOutput(v)
        let pulse = pulseWaveformOutput(v)
        let digital = triangle & sawtooth & pulse
        let triangleSaw = combined6581TriangleSawtoothOutput(v)
        let trianglePulse = combined6581TrianglePulseOutput(v)
        let analogPullDownMask = (triangleSaw >> 1) | (trianglePulse >> 2) | (sawtooth >> 3)
        return digital & analogPullDownMask
    }

    func oscillatorReadbackOutput(_ v: Int) -> UInt16 {
        if voices[v].testBit {
            return voices[v].waveformDACOutput
        }
        if voices[v].hasWaveform {
            return oscillatorOutput(v)
        }
        return voices[v].waveformDACOutput
    }

    func waveformOutput(_ v: Int) -> Int16 {
        let rawOutput: UInt16
        if voices[v].testBit {
            guard voices[v].waveformDACOutput > 0 else { return 0 }
            rawOutput = voices[v].waveformDACOutput
        } else if voices[v].hasWaveform {
            rawOutput = oscillatorOutput(v)
        } else if voices[v].waveformDACOutput > 0 {
            rawOutput = voices[v].waveformDACOutput
        } else {
            return 0
        }

        let centeredOutput = Int32(rawOutput) - 2048

        // Apply envelope after centering the 12-bit waveform. With a zero
        // envelope the voice contributes silence, not a DC offset.
        let envelope = UInt32(envelopeDACLevel(voices[v].envelopeLevel))
        let mixed = centeredOutput * Int32(envelope) * 16 / 255

        return Int16(clamping: mixed)
    }

    func mixedAudioOutput() -> Int32 {
        var directOutput: Int32 = 0
        var filterInput: Int32 = 0

        for v in 0..<3 {
            let voiceOut = Int32(waveformOutput(v))
            let filtered = filterControl & (1 << v) != 0

            if filtered {
                filterInput += voiceOut
            } else if !(v == 2 && voice3Off) {
                directOutput += voiceOut
            }
        }

        let externalInput = externalAudioPathInput()
        if externalInputFiltered {
            filterInput += externalInput
        } else {
            directOutput += externalInput
        }

        let filterOutput = applyFilter(input: filterInput)
        var output = directOutput + filterOutput
        output = Int32(Double(output) * voiceOutputScale)

        // Apply master volume to the audio path, then add the model-specific
        // volume DAC bias. On the 6581 this DC step is observable and is used
        // by volume-register sample playback tricks.
        output = (output * Int32(volume)) / 15
        output += volumeDACOffset
        output = applyOutputStage(input: output)
        lastDirectOutput = directOutput
        lastFilterInput = filterInput
        lastFilterOutput = filterOutput
        lastMixedOutput = output
        return output
    }

    func generateSample() {
        writeSample(mixedAudioOutput())
    }

    func accumulateAudioOutput() {
        audioAccumulator += Double(mixedAudioOutput())
        audioAccumulatorCount += 1
    }

    func generateAccumulatedSample() {
        guard audioAccumulatorCount > 0 else {
            writeSample(mixedAudioOutput())
            return
        }

        let averagedOutput = Int32((audioAccumulator / Double(audioAccumulatorCount)).rounded())
        audioAccumulator = 0
        audioAccumulatorCount = 0
        writeSample(averagedOutput)
    }

    func writeSample(_ rawOutput: Int32) {
        let output = sampleOutput(rawOutput)

        // Clamp and convert to float
        let clamped = max(-32768, min(32767, output))
        let sample = Float(clamped) / 32768.0

        // Write to ring buffer
        sampleBufferLock.lock()
        sampleBuffer[sampleWritePos] = sample
        sampleWritePos = (sampleWritePos + 1) % sampleBuffer.count
        if sampleBufferedCount == sampleBuffer.count {
            sampleReadPos = sampleWritePos
        } else {
            sampleBufferedCount += 1
        }
        sampleBufferLock.unlock()
        onSampleGenerated?(sample)
    }

    public func availableAudioSamplesForPlayback() -> Int {
        sampleBufferLock.lock()
        defer { sampleBufferLock.unlock() }

        return sampleBufferedCount
    }

    public func readAudioSampleForPlayback() -> Float? {
        sampleBufferLock.lock()
        defer { sampleBufferLock.unlock() }

        guard sampleBufferedCount > 0 else { return nil }

        let sample = sampleBuffer[sampleReadPos]
        sampleReadPos = (sampleReadPos + 1) % sampleBuffer.count
        sampleBufferedCount -= 1
        return sample
    }

    @discardableResult
    public func readAudioSamplesForPlayback(into output: UnsafeMutableBufferPointer<Float>) -> Int {
        sampleBufferLock.lock()
        defer { sampleBufferLock.unlock() }

        guard sampleBufferedCount > 0, output.count > 0 else { return 0 }

        let readCount = min(output.count, sampleBufferedCount)
        var remaining = readCount
        var outputOffset = 0
        while remaining > 0 {
            let contiguousCount = min(remaining, sampleBuffer.count - sampleReadPos)
            if let outputBase = output.baseAddress {
                sampleBuffer.withUnsafeBufferPointer { buffer in
                    outputBase.advanced(by: outputOffset).update(
                        from: buffer.baseAddress!.advanced(by: sampleReadPos),
                        count: contiguousCount
                    )
                }
            }
            sampleReadPos = (sampleReadPos + contiguousCount) % sampleBuffer.count
            sampleBufferedCount -= contiguousCount
            outputOffset += contiguousCount
            remaining -= contiguousCount
        }
        return readCount
    }

    func sampleOutput(_ input: Int32) -> Int32 {
        guard accuracyMode == .compatibility else { return input }

        let target = Double(input).clamped(to: -32768...32767)
        audioOutputState += (target - audioOutputState) * analogProfile.outputSmoothingCoefficient
        return Int32(audioOutputState.rounded().clamped(to: -32768...32767))
    }

    func applyOutputStage(input: Int32) -> Int32 {
        guard accuracyMode == .compatibility else { return input }

        let normalized = Double(input).clamped(to: -32768...32767) / 32768.0
        let shaped: Double
        let profile = analogProfile
        switch model {
        case .mos6581:
            // A bounded approximation of the 6581's less-linear output stage.
            // It intentionally gives positive and negative excursions slightly
            // different gain so audio signatures can distinguish the model.
            let asymmetricDrive = normalized >= 0
                ? normalized * profile.outputPositiveDrive
                : normalized * profile.outputNegativeDrive
            shaped = tanh(asymmetricDrive * profile.outputPostDrive)
        case .mos8580:
            // The 8580 output stage is cleaner; retain a mild soft limit so
            // compatibility signatures are deterministic near the rails.
            shaped = tanh(normalized * profile.outputPostDrive)
        }
        return Int32((shaped * 32768.0).clamped(to: -32768...32767))
    }

    func applyFilter(input: Int32) -> Int32 {
        guard filterInputEnabled || filterModeSelected else { return input }

        let inputDouble = filterInputDrive(input)
        let cutoff = normalizedFilterCutoff
        let damping = filterDamping

        filterLow += cutoff * filterBand
        filterHigh = inputDouble - filterLow - damping * filterBand
        filterBand += cutoff * filterHigh

        filterLow = filterLow.clamped(to: -32768...32767)
        filterBand = filterBand.clamped(to: -32768...32767)
        filterHigh = filterHigh.clamped(to: -32768...32767)

        var output = 0.0
        if filterLP { output += filterLow }
        if filterBP { output += filterBand }
        if filterHP { output += filterHigh }
        return Int32(output.clamped(to: -32768...32767))
    }

    func filterInputDrive(_ input: Int32) -> Double {
        let clamped = Double(input).clamped(to: -32768...32767)
        guard clamped != 0 else { return 0 }
        guard accuracyMode == .compatibility else { return clamped }

        let normalized = clamped / 32768.0
        let profile = analogProfile
        switch model {
        case .mos6581:
            // The 6581 filter input is intentionally rougher than the 8580.
            // Keep this bounded and deterministic until we can calibrate it
            // against measured chip captures.
            let driven = tanh(normalized * profile.filterInputDrive) * 32768.0
            let dcBleed = Double(volumeDACOffset) * profile.filterInputDCBleed
            return (driven + dcBleed).clamped(to: -32768...32767)
        case .mos8580:
            let driven = tanh(normalized * profile.filterInputDrive) * 32768.0
            return driven.clamped(to: -32768...32767)
        }
    }

    var filterInputEnabled: Bool {
        filterControl & 0x0F != 0
    }

    // MARK: - Register access

    public func setExternalAudioInput(_ value: Int32) {
        externalAudioInput = Int32(max(-32768, min(32767, value)))
    }

    func externalAudioPathInput() -> Int32 {
        guard accuracyMode == .compatibility else { return externalAudioInput }
        let scaled = Double(externalAudioInput) * analogProfile.externalInputGain
        return Int32(scaled.rounded().clamped(to: -32768...32767))
    }

    public func setPaddle(x: UInt8, y: UInt8) {
        paddleX = x
        paddleY = y
        paddleTargetX = x
        paddleTargetY = y
        paddleScanCounter = nil
    }

    public func startPaddleScan(x: UInt8, y: UInt8) {
        paddleTargetX = x
        paddleTargetY = y
        paddleX = 0
        paddleY = 0
        paddleScanCounter = 0
    }

    func tickPaddleScan() {
        guard let counter = paddleScanCounter else {
            if continuousPaddleScanEnabled {
                paddleX = 0
                paddleY = 0
                paddleScanCounter = 0
            }
            return
        }
        let nextCounter = min(counter + 1, Self.paddleScanCycles)
        paddleScanCounter = nextCounter >= Self.paddleScanCycles ? nil : nextCounter
        paddleX = paddleScanValue(target: paddleTargetX, counter: nextCounter)
        paddleY = paddleScanValue(target: paddleTargetY, counter: nextCounter)
    }

    func paddleScanValue(target: UInt8, counter: Int) -> UInt8 {
        let rampValue = min(255, max(0, counter * 256 / Self.paddleScanCycles))
        return UInt8(min(Int(target), rampValue))
    }

    func latchDataBus(_ value: UInt8) {
        dataBusLatch = value
        dataBusLatchCyclesRemaining = Self.dataBusLatchHoldCycles
    }

    func ageDataBusLatch() {
        if dataBusLatchCyclesRemaining > 0 {
            dataBusLatchCyclesRemaining -= 1
            if dataBusLatchCyclesRemaining > 0 {
                return
            }
        }

        guard dataBusLatch != 0 else { return }
        dataBusLatch &= dataBusLatch &- 1
        if dataBusLatch != 0 {
            dataBusLatchCyclesRemaining = Self.dataBusLatchLeakStepCycles
        }
    }

    public func readRegister(_ reg: UInt16) -> UInt8 {
        let value = peekReadableRegisterValue(reg)
        latchDataBus(value)
        return value
    }

    public func peekReadableRegisterValue(_ reg: UInt16) -> UInt8 {
        let normalizedReg = reg & 0x1F
        switch normalizedReg {
        case 0x19:
            return paddleX
        case 0x1A:
            return paddleY
        case 0x1B:
            return oscillator3ReadbackValid
                ? oscillator3Readback
                : UInt8((oscillatorReadbackOutput(2) >> 4) & 0xFF)  // OSC3
        case 0x1C:
            return envelope3ReadbackValid ? envelope3Readback : voices[2].envelopeLevel  // ENV3
        default:
            return dataBusLatch
        }
    }

    public func debugRegisterValue(_ reg: UInt16) -> UInt8 {
        let normalizedReg = reg & 0x1F
        let voice = Int(normalizedReg / 7)
        let voiceReg = Int(normalizedReg % 7)

        if normalizedReg < 21 && voice < 3 {
            switch voiceReg {
            case 0: return UInt8(voices[voice].frequency & 0x00FF)
            case 1: return UInt8(voices[voice].frequency >> 8)
            case 2: return UInt8(voices[voice].pulseWidth & 0x00FF)
            case 3: return UInt8((voices[voice].pulseWidth >> 8) & 0x0F)
            case 4: return voices[voice].control
            case 5: return voices[voice].attackDecay
            case 6: return voices[voice].sustainRelease
            default: break
            }
        }

        switch normalizedReg {
        case 0x15:
            return UInt8(filterCutoff & 0x0007)
        case 0x16:
            return UInt8((filterCutoff >> 3) & 0x00FF)
        case 0x17:
            return (filterResonance << 4) | (filterControl & 0x0F)
        case 0x18:
            return volumeFilter
        case 0x19:
            return paddleX
        case 0x1A:
            return paddleY
        case 0x1B:
            return UInt8((oscillatorReadbackOutput(2) >> 4) & 0xFF)
        case 0x1C:
            return voices[2].envelopeLevel
        default:
            return dataBusLatch
        }
    }

    public func writeRegister(_ reg: UInt16, value: UInt8) {
        let normalizedReg = reg & 0x1F
        latchDataBus(value)

        let voice = Int(normalizedReg / 7)
        let voiceReg = Int(normalizedReg % 7)

        if normalizedReg < 21 && voice < 3 {
            switch voiceReg {
            case 0: voices[voice].frequency = (voices[voice].frequency & 0xFF00) | UInt16(value)
            case 1: voices[voice].frequency = (voices[voice].frequency & 0x00FF) | (UInt16(value) << 8)
            case 2:
                let oldPulseWidth = normalizedPulseWidth(voices[voice].pulseWidth)
                voices[voice].pulseWidth = (voices[voice].pulseWidth & 0xF00) | UInt16(value)
                invalidateVoice3OscillatorReadbackIfPulseWidthChanged(
                    voice: voice,
                    oldPulseWidth: oldPulseWidth
                )
            case 3:
                let oldPulseWidth = normalizedPulseWidth(voices[voice].pulseWidth)
                voices[voice].pulseWidth = (voices[voice].pulseWidth & 0x0FF) | (UInt16(value & 0x0F) << 8)
                invalidateVoice3OscillatorReadbackIfPulseWidthChanged(
                    voice: voice,
                    oldPulseWidth: oldPulseWidth
                )
            case 4: writeControlRegister(voice: voice, value: value)
            case 5: voices[voice].attackDecay = value
            case 6: voices[voice].sustainRelease = value
            default: break
            }
        } else {
            switch normalizedReg {
            case 0x15: filterCutoff = (filterCutoff & 0x7F8) | UInt16(value & 0x07)
            case 0x16: filterCutoff = (filterCutoff & 0x007) | (UInt16(value) << 3)
            case 0x17:
                filterResonance = value >> 4
                filterControl = value & 0x0F
            case 0x18: volumeFilter = value
            default: break
            }
        }
    }

    func invalidateVoice3OscillatorReadbackIfPulseWidthChanged(voice: Int, oldPulseWidth: UInt16) {
        guard voice == 2 else { return }
        guard normalizedPulseWidth(voices[voice].pulseWidth) != oldPulseWidth else { return }
        guard voices[voice].wavePulse else { return }

        oscillator3ReadbackValid = false
    }

    func writeControlRegister(voice: Int, value: UInt8) {
        let oldControl = voices[voice].control
        let wasTestSet = voices[voice].testBit
        voices[voice].control = value
        let isTestSet = value & 0x08 != 0

        let oscillatorReadbackAffectingControlMask: UInt8 = 0xFE
        if voice == 2 && (value ^ oldControl) & oscillatorReadbackAffectingControlMask != 0 {
            oscillator3ReadbackValid = false
        }

        if isTestSet {
            voices[voice].accumulator = 0
            voices[voice].shiftRegister = 0
            voices[voice].waveformDACOutput = 0
            voices[voice].waveformDACHoldCyclesRemaining = 0
            oscillatorMSBRose[voice] = false
            noiseClockRose[voice] = false
            if voice == 2 { oscillator3Readback = 0 }
        } else if wasTestSet && voices[voice].shiftRegister == 0 {
            voices[voice].shiftRegister = 0x7FFFF8
        }
    }
}
