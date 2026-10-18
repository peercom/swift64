import Foundation
import Emu6502

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

    /// Compatibility-mode analog behaviour that differs between the two chips.
    /// Values marked "model parameter" are not measurements; see TESTING.md.
    struct AnalogProfile: Equatable {
        /// DC entering the filter for every voice routed into it, in mixer
        /// units. The published 6581 mixer offset is about -1/18 of one voice's
        /// range in total; splitting it evenly over three voices is ours.
        let filterInputDCOffsetPerSource: Double
        /// Relative cutoff rise when the low-pass integrator sits at full
        /// scale. Published descriptions of the 6581 agree the cutoff drifts
        /// upward with signal level; the magnitude is a model parameter.
        let filterCutoffDistortion: Double
        /// EXT IN gain into the mixer (approximation, not measured).
        let externalInputGain: Double
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
        /// Direct assignment (register-level tests, snapshot restore, sync and
        /// TEST resets) also re-latches `previousPhase`; only `clockOscillator`
        /// leaves the one-cycle-old phase in place.
        var accumulator: UInt32 = 0 {
            didSet { previousPhase = UInt16(accumulator >> 12) }
        }
        /// 23-bit noise LFSR. All ones is the state a long TEST hold pulls it to
        /// (the public `noisetest`/`oscsample` programs start from it), so a
        /// fresh voice starts there too.
        var shiftRegister: UInt32 = 0x7FFFFF
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
        /// Top 12 accumulator bits before this cycle's increment. The 6581
        /// pulse comparator works from this one-cycle-old phase; after a sync
        /// or TEST reset it is the reset phase (a model choice, not measured).
        var previousPhase: UInt16 = 0
        /// Cycles TEST has been held since its rising edge, saturating at
        /// `SID.noiseShiftRegisterResetCycles`; the noise register is pulled to
        /// all ones when the count reaches that threshold.
        var testHoldCycles: Int = 0
        /// Cycles until a detected bit-19 edge shifts the noise register
        /// (`SID.noiseShiftPipelineCycles(for:)` when the edge is seen, 0 when idle).
        var noiseShiftCyclesRemaining: UInt8 = 0

        var waveTriangle: Bool { control & 0x10 != 0 }
        var waveSawtooth: Bool { control & 0x20 != 0 }
        var wavePulse: Bool { control & 0x40 != 0 }
        var waveNoise: Bool { control & 0x80 != 0 }
        var hasWaveform: Bool { control & 0xF0 != 0 }
        var waveNoiseOnly: Bool { control & 0xF0 == 0x80 }
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
            // One voice spans 2 * 32768 / voiceMixDivisor mixer units; the
            // published total mixer offset (-0.06 V of a 1.05 V voice range,
            // measured between volume 0 and 15) is about -1/18 of that.
            let voiceRange = 2.0 * 32768.0 / Double(Self.voiceMixDivisor)
            return AnalogProfile(
                filterInputDCOffsetPerSource: -voiceRange / 18 / 3,
                filterCutoffDistortion: 0.6,
                externalInputGain: 1.12
            )
        case .mos8580:
            // "No DC offsets in the MOS8580"; its filter behaves near-ideally.
            return AnalogProfile(
                filterInputDCOffsetPerSource: 0,
                filterCutoffDistortion: 0,
                externalInputGain: 0.72
            )
        }
    }

    // MARK: - Filter calibration
    //
    // The SID filter is a two-integrator-loop biquad (confirmed by its
    // designer). Its cutoff is set by FETs used as voltage-controlled
    // resistors driven by the 11-bit FC DAC, so the FC-to-frequency curve is
    // an analog property that differs per chip. The anchors below are
    // published measurements; interpolation, the 6581 range scaling and the
    // 8580 resonance endpoint are this project's own model choices.

    /// Published 6581 cutoff measurement (Dag Lem, reSID 0.16 documentation):
    /// a 6581 R4AR with 470 pF filter capacitors runs from about 220 Hz at
    /// FC 0 to about 18 kHz at FC 2047, tanh-shaped on a logarithmic frequency
    /// axis. That chip's FC DAC also steps from 6.0 kHz to 4.6 kHz at FC 1024;
    /// the kink is chip-specific and averaged out here.
    static let cutoffAnchors6581: [(fc: Int, hz: Double)] = [
        (0, 220), (256, 250), (512, 420), (640, 780), (768, 1_600), (896, 3_200),
        (1_024, 5_300), (1_152, 7_200), (1_280, 9_500), (1_408, 12_000),
        (1_536, 14_500), (1_664, 16_000), (1_792, 17_100), (2_047, 18_000)
    ]

    /// Published 8580 cutoff measurement (reSID 0.16 documentation): close to
    /// the datasheet's linear 11-bit control, reaching about 12.5 kHz at
    /// FC 2047. The datasheet's 30 Hz lower bound replaces the measured
    /// near-zero floor so the integrators never freeze.
    static let cutoffAnchors8580: [(fc: Int, hz: Double)] = [
        (0, 30), (128, 800), (256, 1_600), (512, 3_300), (768, 4_800),
        (1_024, 6_500), (1_280, 8_400), (1_536, 9_800), (1_792, 11_000),
        (2_047, 12_500)
    ]

    static let minimumCutoff6581 = 220.0
    static let referenceMaximumCutoff6581 = 18_000.0
    /// Published 6581 curves top out anywhere from about 8.6 kHz to over
    /// 20 kHz at FC 2047; this is the supported range for
    /// `filterMaximumCutoff6581`.
    public static let filterMaximumCutoff6581Range: ClosedRange<Double> = 8_000...20_000

    /// 6581 cutoff in Hz at FC 2047. The default is the published reference
    /// chip; lower values model "darker" chips, higher values "brighter" ones.
    /// The whole curve is rescaled on a logarithmic axis so FC 0 stays at the
    /// measured 220 Hz floor.
    public var filterMaximumCutoff6581: Double = SID.referenceMaximumCutoff6581 {
        didSet {
            let clamped = filterMaximumCutoff6581.clamped(to: Self.filterMaximumCutoff6581Range)
            if clamped != filterMaximumCutoff6581 { filterMaximumCutoff6581 = clamped }
            cutoffTable6581 = Self.cutoffTable6581(maximumCutoff: filterMaximumCutoff6581)
        }
    }
    /// Cutoff in Hz per FC value for the current `filterMaximumCutoff6581`.
    var cutoffTable6581 = SID.cutoffTable6581(maximumCutoff: SID.referenceMaximumCutoff6581)

    static let referenceCutoffTable6581 = interpolatedCutoffTable(cutoffAnchors6581, logarithmic: true)
    static let cutoffTable8580 = interpolatedCutoffTable(cutoffAnchors8580, logarithmic: false)

    static func cutoffTable6581(maximumCutoff: Double) -> [Double] {
        let exponent = log(maximumCutoff / minimumCutoff6581)
            / log(referenceMaximumCutoff6581 / minimumCutoff6581)
        return referenceCutoffTable6581.map { minimumCutoff6581 * pow($0 / minimumCutoff6581, exponent) }
    }

    /// Piecewise interpolation of measured anchors over all 2048 FC values,
    /// linear in frequency for the 8580 and linear in log-frequency for the
    /// 6581's exponential FET response.
    static func interpolatedCutoffTable(_ anchors: [(fc: Int, hz: Double)], logarithmic: Bool) -> [Double] {
        var table = [Double](repeating: anchors[0].hz, count: 2048)
        for pair in zip(anchors, anchors.dropFirst()) {
            let (start, end) = pair
            for fc in start.fc...end.fc {
                let position = Double(fc - start.fc) / Double(max(1, end.fc - start.fc))
                table[fc] = logarithmic
                    ? start.hz * pow(end.hz / start.hz, position)
                    : start.hz + (end.hz - start.hz) * position
            }
        }
        return table
    }

    /// Current filter cutoff frequency in Hz.
    public var filterCutoffFrequency: Double {
        filterCutoffFrequency(for: filterCutoff)
    }

    /// Filter cutoff frequency in Hz for an FC register value on this model.
    public func filterCutoffFrequency(for cutoff: UInt16) -> Double {
        let index = Int(normalizedFilterCutoffValue(cutoff))
        switch model {
        case .mos6581:
            return cutoffTable6581[index]
        case .mos8580:
            return Self.cutoffTable8580[index]
        }
    }

    /// Integrator coefficient per SID clock cycle for the state-variable
    /// filter in `applyFilter`: 2 sin(pi f / fclk), which places the filter's
    /// resonant frequency at `filterCutoffFrequency`.
    var normalizedFilterCutoff: Double {
        2 * sin(.pi * filterCutoffFrequency / clockRate)
    }

    func normalizedFilterCutoffValue(_ cutoff: UInt16) -> UInt16 {
        cutoff & 0x07FF
    }

    /// Q at RES 15. Both chips are Butterworth (Q = 1/sqrt 2) at RES 0. The
    /// 6581 endpoint is the published approximate range [0.707, 1.7] with 1/Q
    /// linear in RES. The 8580's far stronger peak is widely reported but no
    /// published numeric measurement was found, so Q = 4 is a model parameter.
    static let maximumQ6581 = 1.7
    static let maximumQ8580 = 4.0

    /// 1/Q of the filter, linear in RES between the Butterworth value and
    /// the model's maximum Q.
    var filterDamping: Double {
        let maximumQ = model == .mos6581 ? Self.maximumQ6581 : Self.maximumQ8580
        let maximumDamping = 2.0.squareRoot()
        let minimumDamping = 1 / maximumQ
        return maximumDamping - (maximumDamping - minimumDamping) * Double(filterResonance & 0x0F) / 15
    }

    public var filterQ: Double { 1 / filterDamping }

    /// C64 board output network, identical for both chips: a 10 kOhm /
    /// 1000 pF low-pass (about 16 kHz) buffered into a 1 kOhm / 10 uF
    /// high-pass (about 16 Hz). Rates are 1/RC in radians per second.
    static let externalFilterLowPassRate = 1 / (10_000.0 * 1_000e-12)
    static let externalFilterHighPassRate = 1 / (1_000.0 * 10e-6)
    public static var externalFilterLowPassCorner: Double { externalFilterLowPassRate / (2 * .pi) }
    public static var externalFilterHighPassCorner: Double { externalFilterHighPassRate / (2 * .pi) }
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
    /// Board output network state (compatibility mode), in mixer units.
    var externalFilterLowPassState: Double = 0
    var externalFilterHighPassState: Double = 0
    /// Tracked magnitude of the low-pass integrator voltage that drives the
    /// 6581's level-dependent cutoff (compatibility mode), in mixer units.
    var filterLevelState: Double = 0
    /// Time constant of that level tracker in seconds (model parameter).
    static let filterLevelTimeConstant = 0.005
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
    /// Per-cycle accumulator bit-19 rising-edge flags; the noise LFSR shifts
    /// `noiseShiftPipelineCycles(for:)` after the flag is set.
    var noiseClockRose = [Bool](repeating: false, count: 3)

    /// Ring buffer for audio output
    public var sampleBuffer = [Float](repeating: 0, count: 8192)
    public var sampleWritePos: Int = 0
    public var sampleReadPos: Int = 0
    var sampleBufferedCount: Int = 0
    private var sampleOverrunCount: UInt64 = 0
    public var onSampleGenerated: ((Float) -> Void)?
    private let sampleBufferLock = NSLock()

    // MARK: - ADSR rate table (cycles per increment)

    // Measured SID envelope rate-counter comparison periods at a 1 MHz PHI2
    // reference clock. These are the values observed by the public reSID/VICE
    // envrate program on both 6581 and 8580 hardware.
    static let attackRates: [UInt16] = [
        9, 32, 63, 95, 149, 220, 267, 313,
        392, 977, 1954, 3126, 3907, 11720, 19532, 31251
    ]

    static let decayReleaseRates: [UInt16] = [
        9, 32, 63, 95, 149, 220, 267, 313,
        392, 977, 1954, 3126, 3907, 11720, 19532, 31251
    ]

    static let dataBusLatchHoldCycles = 0x2000
    static let dataBusLatchLeakStepCycles = 0x0200
    static let envelopeRateCounterMask: UInt16 = 0x7FFF
    static let waveformDACHoldCycles = 128
    /// Cycles between leak steps of a floating waveform DAC (no waveform
    /// selected, TEST clear). With the per-step decrements in
    /// `leakedWaveformDACOutput` the full-scale value drains in about 2.2 s
    /// on the 6581 and 15 s on the 8580. The public `osc3-wave0` program
    /// bounds these: the 6581 must read zero within 256 PAL frames, the
    /// 8580 variant allows six times that. The exact curves are not measured.
    static func waveformDACLeakStepCycles(for model: Model) -> Int {
        model == .mos6581 ? 12_000 : 150_000
    }
    /// Cycles of a TEST hold after which the noise shift register reads all
    /// ones. The public `oscsample` dumps show every register bit surviving
    /// a hold of two PAL frames on both chips, and the `noisetest`/`oscsample`
    /// programs find all ones after a hold of 23.6 million cycles with the
    /// 8580 described as taking much longer than the 6581; the values inside
    /// that window are model parameters, not measurements.
    static func noiseShiftRegisterResetCycles(for model: Model) -> Int {
        model == .mos6581 ? 0x10_0000 : 0x100_0000
    }
    /// Shift-register bits that drive noise output bits 11 (first) to 4
    /// (last); the mapping of the public `noisetest` program.
    static let noiseOutputTaps = [20, 18, 14, 11, 9, 5, 2, 0]
    /// Cycles between a bit-19 rising edge and the noise register shift. The
    /// `oscsample` noise dumps place every OSC3 change in the same cycle on
    /// both chips, while the 6581 reads the accumulator-driven waveforms one
    /// cycle earlier than the 8580, so relative to its own readback the 6581
    /// shifts one cycle later.
    static func noiseShiftPipelineCycles(for model: Model) -> UInt8 {
        model == .mos6581 ? 2 : 1
    }
    static let paddleScanCycles = 512
    static let voiceMixDivisor: Int32 = 4

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

    // Exact tabulation of the existing approximation, not a new chip model.
    // This curve depends only on register values, never on elapsed cycles.
    private static let envelopeDAC6581 = (0...255).map {
        UInt16((pow(Double($0) / 255, 0.92) * 255).rounded())
    }

    func envelopeDACLevel(_ level: UInt8) -> UInt16 {
        switch model {
        case .mos6581:
            // The 6581 envelope DAC is not a perfectly terminated linear DAC.
            // This bounded curve is a deterministic approximation until we
            // replace it with measured chip tables.
            return Self.envelopeDAC6581[Int(level)]
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
        externalFilterLowPassState = 0
        externalFilterHighPassState = 0
        filterLevelState = 0
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
        sampleOverrunCount = 0
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
        sampleEnvelope3Readback()
        // The public `oscsample` programs detect the chip by reading OSC3
        // four cycles after releasing TEST with FREQ $4000: the 6581 reads
        // $01, the 8580 $00 ("the MOS8580 waveform is delayed one cycle").
        // The 8580 readback therefore samples the oscillator before this
        // cycle's clock, the 6581 after it.
        if model == .mos8580 { sampleOscillator3Readback() }

        // Update all oscillators before applying sync so source edges are
        // independent of voice iteration order.
        for i in 0..<3 {
            clockOscillator(i)
        }
        applyOscillatorSync()
        if model == .mos6581 { sampleOscillator3Readback() }

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
        sampleOscillator3Readback()
        sampleEnvelope3Readback()
    }

    func sampleOscillator3Readback() {
        oscillator3Readback = UInt8((oscillatorReadbackOutput(2) >> 4) & 0xFF)
        oscillator3ReadbackValid = true
    }

    func sampleEnvelope3Readback() {
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
        var voice = voices[v]
        let phaseBeforeClock = UInt16(voice.accumulator >> 12)
        let prevMSB = voice.accumulator & 0x800000
        let prevNoiseClock = voice.accumulator & 0x080000
        // A detected bit-19 rising edge shifts the register
        // `noiseShiftPipelineCycles` later.
        var shiftNoiseRegisterNow = false
        if voice.noiseShiftCyclesRemaining > 0 {
            voice.noiseShiftCyclesRemaining -= 1
            shiftNoiseRegisterNow = voice.noiseShiftCyclesRemaining == 0
        }
        let wasNoiseCombined = voice.waveNoise &&
            (voice.waveTriangle || voice.waveSawtooth || voice.wavePulse)

        if voice.testBit {
            // TEST holds the accumulator at zero, so bit 19 never rises and
            // the noise register keeps its state; only a long hold pulls
            // every bit to one.
            voice.accumulator = 0
            let resetCycles = Self.noiseShiftRegisterResetCycles(for: model)
            if voice.testHoldCycles < resetCycles {
                voice.testHoldCycles += 1
                if voice.testHoldCycles == resetCycles {
                    voice.shiftRegister = 0x7FFFFF
                }
            }
        } else {
            voice.accumulator = (voice.accumulator + UInt32(voice.frequency)) & 0xFFFFFF
        }
        voice.previousPhase = phaseBeforeClock

        let newMSB = voice.accumulator & 0x800000
        oscillatorMSBRose[v] = prevMSB == 0 && newMSB != 0

        // Noise shift register clock on accumulator bit 19 rising edge,
        // applied through the pipeline.
        let newNoiseClock = voice.accumulator & 0x080000
        noiseClockRose[v] = prevNoiseClock == 0 && newNoiseClock != 0
        if noiseClockRose[v] {
            voice.noiseShiftCyclesRemaining = Self.noiseShiftPipelineCycles(for: model)
        }
        if shiftNoiseRegisterNow {
            voice.shiftRegister = Self.clockedNoiseShiftRegister(voice.shiftRegister, testBit: false)
        }
        voices[v] = voice
        if shiftNoiseRegisterNow && wasNoiseCombined && model == .mos6581 {
            age6581CombinedNoiseRegister(v)
        }

        updateWaveformDACLatch(v)
    }

    /// One shift of the noise LFSR: bit 0 receives bit 22 XOR bit 17, with
    /// TEST ORed into the bit-22 input. The public `noisetest` program
    /// verifies the forced feedback on a TEST release (bit 0 = NOT bit 17)
    /// on both chips.
    static func clockedNoiseShiftRegister(_ shiftRegister: UInt32, testBit: Bool) -> UInt32 {
        let bit22 = ((shiftRegister >> 22) & 1) | (testBit ? 1 : 0)
        let bit17 = (shiftRegister >> 17) & 1
        return ((shiftRegister << 1) | (bit22 ^ bit17)) & 0x7FFFFF
    }

    func age6581CombinedNoiseRegister(_ v: Int) {
        // The 6581's combined noise waveforms feed analog pull-down effects
        // back into the noise generator. This deterministic approximation
        // drains the DAC-tapped bits, so repeated clocks can lock the LFSR at
        // zero until a TEST release feeds a one back in.
        let dacTappedBits = Self.noiseOutputTaps.reduce(UInt32(0)) { $0 | (1 << UInt32($1)) }
        voices[v].shiftRegister &= ~dacTappedBits
    }

    func updateWaveformDACLatch(_ v: Int) {
        // Under TEST the accumulator-driven waveforms are silent, but the
        // noise register keeps its state and stays readable (`noisetest`
        // reads OSC3 unchanged right after setting TEST).
        if voices[v].hasWaveform && (!voices[v].testBit || voices[v].waveNoiseOnly) {
            refreshWaveformDACLatch(v)
        } else if voices[v].waveformDACHoldCyclesRemaining > 0 {
            voices[v].waveformDACHoldCyclesRemaining -= 1
        } else if voices[v].waveformDACOutput > 0 {
            voices[v].waveformDACOutput = leakedWaveformDACOutput(voices[v].waveformDACOutput)
            if voices[v].waveformDACOutput > 0 {
                voices[v].waveformDACHoldCyclesRemaining = Self.waveformDACLeakStepCycles(for: model)
            }
        }
    }

    func refreshWaveformDACLatch(_ v: Int) {
        let output = oscillatorOutput(v)
        voices.withUnsafeMutableBufferPointer { buffer in
            buffer[v].waveformDACOutput = output
            buffer[v].waveformDACHoldCyclesRemaining = Self.waveformDACHoldCycles
        }
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
        let voice = voices[v]
        // Single-wave voices are common in music; combined-wave chip-model
        // shaping is irrelevant for these selections.
        switch voice.control & 0x70 {
        case 0: return nil
        case 0x10: return triangleWaveformOutput(v)
        case 0x20: return sawtoothWaveformOutput(v)
        case 0x40: return pulseWaveformOutput(v)
        default: break
        }
        if model == .mos6581 &&
            voice.waveTriangle &&
            voice.waveSawtooth &&
            voice.wavePulse {
            return combined6581TriangleSawtoothPulseOutput(v)
        }

        if model == .mos6581 &&
            voice.waveSawtooth &&
            voice.wavePulse &&
            !voice.waveTriangle {
            return combined6581SawtoothPulseOutput(v)
        }

        if model == .mos6581 &&
            voice.waveTriangle &&
            voice.waveSawtooth &&
            !voice.wavePulse {
            return combined6581TriangleSawtoothOutput(v)
        }

        if model == .mos6581 &&
            voice.waveTriangle &&
            voice.wavePulse &&
            !voice.waveSawtooth {
            return combined6581TrianglePulseOutput(v)
        }

        var output: UInt16 = 0
        var hasOutput = false

        if voice.waveTriangle {
            let triangle = triangleWaveformOutput(v)
            output = triangle
            hasOutput = true
        }

        if voice.waveSawtooth {
            let sawtooth = sawtoothWaveformOutput(v)
            output = hasOutput ? output & sawtooth : sawtooth
            hasOutput = true
        }

        if voice.wavePulse {
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

    /// The pulse comparator outputs all ones while the accumulator's top 12
    /// bits are at or above the pulse width. PW 0 is therefore a constant
    /// high and PW $FFF a constant low except for the single top phase; the
    /// public `osc3-wave0` program verifies both levels on real 6581 and 8580
    /// chips (OSC3 reads $FF for PW 0 and $00 for PW $FFF at phase 0).
    ///
    /// The public `oscsample1` OSC3 dumps show the 6581 pulse edge one cycle
    /// after the sawtooth reaches the pulse width, while the 8580 edge is in
    /// the same cycle, so the 6581 compares the previous cycle's phase.
    func pulseWaveformOutput(_ v: Int) -> UInt16 {
        let pulseWidth = normalizedPulseWidth(voices[v].pulseWidth)
        let phase = model == .mos6581 ? voices[v].previousPhase : UInt16(voices[v].accumulator >> 12)
        return phase >= pulseWidth ? 0xFFF : 0
    }

    func normalizedPulseWidth(_ pulseWidth: UInt16) -> UInt16 {
        pulseWidth & 0x0FFF
    }

    func noiseWaveformOutput(_ v: Int) -> UInt16 {
        let sr = voices[v].shiftRegister
        var noiseBits: UInt32 = 0
        for (index, tap) in Self.noiseOutputTaps.enumerated() {
            noiseBits |= ((sr >> UInt32(tap)) & 1) << UInt32(11 - index)
        }
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

    func mixedAudioOutput(filterElapsedCycles: Double = 1) -> Int32 {
        var directOutput: Int32 = 0
        var filterInput: Int32 = 0

        for v in 0..<3 {
            // Preserve enough headroom for all three voices and the filter.
            // Saturating a single voice near full scale masks quieter melody
            // voices whenever a bass or noise voice is also active.
            let voiceOut = Int32(waveformOutput(v)) / Self.voiceMixDivisor
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

        let filterOutput = applyFilter(input: filterInput, elapsedCycles: filterElapsedCycles)
        var output = directOutput + filterOutput
        output = Int32(Double(output) * voiceOutputScale)

        // Apply master volume to the audio path, then add the model-specific
        // volume DAC bias. On the 6581 this DC step is observable and is used
        // by volume-register sample playback tricks.
        output = (output * Int32(volume)) / 15
        output += volumeDACOffset
        output = applyOutputStage(input: output)
        output = applyExternalFilter(input: output, elapsedCycles: filterElapsedCycles)
        lastDirectOutput = directOutput
        lastFilterInput = filterInput
        lastFilterOutput = filterOutput
        lastMixedOutput = output
        return output
    }

    func generateSample() {
        // Fast mode evaluates the mixer once per host sample. Advance the
        // filter by the SID cycles represented by that sample so its cutoff
        // does not collapse by clockRate/sampleRate.
        writeSample(mixedAudioOutput(filterElapsedCycles: cyclesPerSample))
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
        audioOutputState = Double(clamped)
        let sample = Float(clamped) / 32768.0

        // Write to ring buffer
        sampleBufferLock.lock()
        sampleBuffer[sampleWritePos] = sample
        sampleWritePos = (sampleWritePos + 1) % sampleBuffer.count
        if sampleBufferedCount == sampleBuffer.count {
            sampleReadPos = sampleWritePos
            sampleOverrunCount += 1
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

    /// Drop every buffered sample without touching synthesis state. Used when
    /// playback resumes after warp mode so stale audio is not replayed.
    public func discardBufferedAudioSamples() {
        sampleBufferLock.lock()
        defer { sampleBufferLock.unlock() }
        sampleReadPos = sampleWritePos
        sampleBufferedCount = 0
    }

    /// Samples overwritten before the speaker consumed them, since SID reset.
    public var audioOverrunFrames: UInt64 {
        sampleBufferLock.lock()
        defer { sampleBufferLock.unlock() }
        return sampleOverrunCount
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

    /// The host-sample stage is a plain pass-through: the board's output
    /// network is modelled per cycle in `applyExternalFilter`, and the speaker
    /// path adds its own DC removal.
    func sampleOutput(_ input: Int32) -> Int32 {
        input
    }

    /// AUDIO OUT is an open-source buffer into the board's 1 kOhm load,
    /// rated at about 3 V peak-to-peak around a 6 V DC level. Published
    /// measurements place the 6581's audible nonlinearity in the filter
    /// integrators and describe the 8580 output as near-ideal, so neither
    /// model applies extra waveshaping here; the signal only clamps at the
    /// rails.
    func applyOutputStage(input: Int32) -> Int32 {
        max(-32768, min(32767, input))
    }

    /// C64 board output network (compatibility mode only): the 16 kHz RC
    /// low-pass followed by the 16 Hz coupling high-pass, integrated in steps
    /// of at most one SID cycle.
    func applyExternalFilter(input: Int32, elapsedCycles: Double = 1) -> Int32 {
        guard accuracyMode == .compatibility else { return input }

        let inputDouble = Double(input)
        let boundedElapsedCycles = max(1, elapsedCycles)
        let substepCount = Int(ceil(boundedElapsedCycles))
        let secondsPerSubstep = boundedElapsedCycles / Double(substepCount) / clockRate
        let lowPassStep = Self.externalFilterLowPassRate * secondsPerSubstep
        let highPassStep = Self.externalFilterHighPassRate * secondsPerSubstep

        for _ in 0..<substepCount {
            externalFilterLowPassState += lowPassStep * (inputDouble - externalFilterLowPassState)
            externalFilterHighPassState += highPassStep * (externalFilterLowPassState - externalFilterHighPassState)
        }

        let output = externalFilterLowPassState - externalFilterHighPassState
        return Int32(output.rounded().clamped(to: -32768...32767))
    }

    func applyFilter(input: Int32, elapsedCycles: Double = 1) -> Int32 {
        guard filterInputEnabled || filterModeSelected else { return input }

        let inputDouble = filterInputDrive(input)
        let cutoff = normalizedFilterCutoff
        let damping = filterDamping
        // 6581 only, compatibility mode: the FET voltage-controlled resistors
        // and NMOS-inverter op-amps let the effective cutoff drift upward as
        // the signal level grows (published qualitative mechanism). The level
        // is the tracked magnitude of the low-pass integrator voltage; the
        // gain `AnalogProfile.filterCutoffDistortion` and the tracker's time
        // constant are model parameters, not measurements.
        let distortion = accuracyMode == .compatibility ? analogProfile.filterCutoffDistortion : 0

        let boundedElapsedCycles = max(1, elapsedCycles)
        // A resonant two-integrator filter cannot use the exponential shortcut
        // for a one-pole RC filter. Keep each integration step <= one SID cycle.
        let substepCount = Int(ceil(boundedElapsedCycles))
        let cyclesPerSubstep = boundedElapsedCycles / Double(substepCount)
        let substepCutoff = cutoff * cyclesPerSubstep
        let levelStep = cyclesPerSubstep / (Self.filterLevelTimeConstant * clockRate)

        for _ in 0..<substepCount {
            var stepCutoff = substepCutoff
            if distortion != 0 {
                filterLevelState += (abs(filterLow) - filterLevelState) * levelStep
                stepCutoff *= 1 + distortion * min(1, filterLevelState / 32768)
            }
            filterLow += stepCutoff * filterBand
            filterHigh = inputDouble - filterLow - damping * filterBand
            filterBand += stepCutoff * filterHigh

            filterLow = filterLow.clamped(to: -32768...32767)
            filterBand = filterBand.clamped(to: -32768...32767)
            filterHigh = filterHigh.clamped(to: -32768...32767)
        }

        var output = 0.0
        if filterLP { output += filterLow }
        if filterBP { output += filterBand }
        if filterHP { output += filterHigh }
        return Int32(output.clamped(to: -32768...32767))
    }

    /// Signal entering the filter. In compatibility mode every voice routed
    /// through FILT1-3 also brings its DC level with it (6581 only), so
    /// low-pass output carries that offset and routing changes click as on
    /// the chip. The mixer path itself is linear; the 6581's level-dependent
    /// behaviour is the cutoff modulation in `applyFilter`.
    func filterInputDrive(_ input: Int32) -> Double {
        let clamped = Double(input).clamped(to: -32768...32767)
        guard accuracyMode == .compatibility else { return clamped }

        let routedVoices = Double((filterControl & 0x07).nonzeroBitCount)
        let offset = routedVoices * analogProfile.filterInputDCOffsetPerSource
        return (clamped + offset).clamped(to: -32768...32767)
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
            if !wasTestSet { voices[voice].testHoldCycles = 0 }
            // An edge still in the pipeline is dropped (model choice).
            voices[voice].noiseShiftCyclesRemaining = 0
            // The noise register is not touched: it keeps its state until a
            // long hold pulls it to all ones (see `clockOscillator`).
            let noiseOutput = voices[voice].waveNoiseOnly ? noiseWaveformOutput(voice) : 0
            voices[voice].waveformDACOutput = noiseOutput
            voices[voice].waveformDACHoldCyclesRemaining = 0
            oscillatorMSBRose[voice] = false
            noiseClockRose[voice] = false
            if voice == 2 { oscillator3Readback = UInt8((noiseOutput >> 4) & 0xFF) }
        } else if wasTestSet {
            // The TEST release clocks the noise register once with TEST still
            // in the feedback (`noisetest`; the `oscsample` noise runs each
            // continue from the previous run's register through exactly this
            // one shift).
            voices[voice].shiftRegister = Self.clockedNoiseShiftRegister(voices[voice].shiftRegister, testBit: true)
            voices[voice].testHoldCycles = 0
        }
    }
}

// MARK: - Snapshot state

extension SID {
    public static let snapshotStoredPropertyCount = 46

    /// The audio sample queue is not part of the state; it is flushed on restore.
    func saveState(to w: inout StateWriter) {
        w.write(model.rawValue); w.write(accuracyMode.rawValue); w.write(clockRate)
        w.write(UInt8(voices.count))
        for voice in voices { voice.saveState(to: &w) }
        w.write(filterCutoff); w.write(filterResonance); w.write(filterControl); w.write(volumeFilter)
        w.write(externalAudioInput)
        w.write(paddleX); w.write(paddleY); w.write(paddleTargetX); w.write(paddleTargetY)
        w.write(paddleScanCounter); w.write(continuousPaddleScanEnabled)
        w.write(dataBusLatch); w.write(dataBusLatchCyclesRemaining)
        w.write(filterLow); w.write(filterBand); w.write(filterHigh)
        w.write(externalFilterLowPassState); w.write(externalFilterHighPassState); w.write(filterLevelState)
        w.write(filterMaximumCutoff6581)
        w.write(oscillator3Readback); w.write(oscillator3ReadbackValid)
        w.write(envelope3Readback); w.write(envelope3ReadbackValid)
        w.write(sampleCycleCounter); w.write(audioAccumulator); w.write(audioAccumulatorCount); w.write(audioOutputState)
        w.write(lastDirectOutput); w.write(lastFilterInput); w.write(lastFilterOutput); w.write(lastMixedOutput)
        w.write(oscillatorMSBRose); w.write(noiseClockRose)
    }

    func restoreState(from r: inout StateReader) throws {
        guard let savedModel = Model(rawValue: try r.read()) else { throw MachineStateError.invalidValue("SID model") }
        guard let savedMode = AccuracyMode(rawValue: try r.read()) else { throw MachineStateError.invalidValue("SID accuracy mode") }
        model = savedModel; accuracyMode = savedMode; clockRate = try r.read()
        let voiceCount: UInt8 = try r.read()
        guard voiceCount == 3 else { throw MachineStateError.invalidValue("SID voice count") }
        for index in 0..<3 { try voices[index].restoreState(from: &r) }
        filterCutoff = try r.read(); filterResonance = try r.read(); filterControl = try r.read(); volumeFilter = try r.read()
        externalAudioInput = try r.read()
        paddleX = try r.read(); paddleY = try r.read(); paddleTargetX = try r.read(); paddleTargetY = try r.read()
        paddleScanCounter = try r.read(); continuousPaddleScanEnabled = try r.read()
        dataBusLatch = try r.read(); dataBusLatchCyclesRemaining = try r.read()
        filterLow = try r.read(); filterBand = try r.read(); filterHigh = try r.read()
        externalFilterLowPassState = try r.read(); externalFilterHighPassState = try r.read(); filterLevelState = try r.read()
        let savedMaximumCutoff: Double = try r.read()
        guard Self.filterMaximumCutoff6581Range.contains(savedMaximumCutoff) else {
            throw MachineStateError.invalidValue("SID 6581 filter range")
        }
        filterMaximumCutoff6581 = savedMaximumCutoff  // rebuilds the cutoff table
        oscillator3Readback = try r.read(); oscillator3ReadbackValid = try r.read()
        envelope3Readback = try r.read(); envelope3ReadbackValid = try r.read()
        sampleCycleCounter = try r.read(); audioAccumulator = try r.read(); audioAccumulatorCount = try r.read(); audioOutputState = try r.read()
        lastDirectOutput = try r.read(); lastFilterInput = try r.read(); lastFilterOutput = try r.read(); lastMixedOutput = try r.read()
        let msb: [Bool] = try r.read(); let noise: [Bool] = try r.read()
        guard msb.count == 3, noise.count == 3 else { throw MachineStateError.invalidValue("SID oscillator flags") }
        oscillatorMSBRose = msb; noiseClockRose = noise
        discardBufferedAudioSamples()
    }
}

extension SID.Voice {
    func saveState(to w: inout StateWriter) {
        w.write(frequency); w.write(pulseWidth); w.write(control); w.write(attackDecay); w.write(sustainRelease)
        w.write(accumulator); w.write(shiftRegister); w.write(envelopeCounter); w.write(envelopeLevel)
        w.write(envelopeState.snapshotValue)
        w.write(exponentialCounter); w.write(exponentialPeriod); w.write(holdZero); w.write(gate)
        w.write(rateCounter); w.write(waveformDACOutput); w.write(waveformDACHoldCyclesRemaining)
        w.write(previousPhase); w.write(testHoldCycles); w.write(noiseShiftCyclesRemaining)
    }

    mutating func restoreState(from r: inout StateReader) throws {
        frequency = try r.read(); pulseWidth = try r.read(); control = try r.read(); attackDecay = try r.read(); sustainRelease = try r.read()
        accumulator = try r.read(); shiftRegister = try r.read(); envelopeCounter = try r.read(); envelopeLevel = try r.read()
        envelopeState = try SID.EnvelopeState(snapshotValue: try r.read())
        exponentialCounter = try r.read(); exponentialPeriod = try r.read(); holdZero = try r.read(); gate = try r.read()
        rateCounter = try r.read(); waveformDACOutput = try r.read(); waveformDACHoldCyclesRemaining = try r.read()
        previousPhase = try r.read(); testHoldCycles = try r.read(); noiseShiftCyclesRemaining = try r.read()
    }
}

extension SID.EnvelopeState {
    var snapshotValue: UInt8 {
        switch self {
        case .attack: return 0
        case .decay: return 1
        case .sustain: return 2
        case .release: return 3
        }
    }

    init(snapshotValue: UInt8) throws {
        switch snapshotValue {
        case 0: self = .attack
        case 1: self = .decay
        case 2: self = .sustain
        case 3: self = .release
        default: throw MachineStateError.invalidValue("SID envelope state")
        }
    }
}
