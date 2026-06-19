import Foundation

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// MOS 6581 SID (Sound Interface Device) emulation.
/// Simplified but functional: 3 voices with waveforms, ADSR, and filter.
public final class SID {

    public enum Model: String, Equatable {
        case mos6581
        case mos8580
    }

    // MARK: - Constants

    public var model: Model = .mos6581
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
        Int32(volume) * (model == .mos6581 ? 220 : 20)
    }
    var normalizedFilterCutoff: Double {
        let normalized = Double(filterCutoff) / 2047.0
        switch model {
        case .mos6581:
            return 0.003 + pow(normalized, 1.7) * 0.18
        case .mos8580:
            return 0.004 + normalized * 0.28
        }
    }
    var filterDamping: Double {
        max(0.35, 1.35 - Double(filterResonance) * 0.055)
    }

    /// Latched analog paddle values read through POTX/POTY ($D419/$D41A).
    var paddleX: UInt8 = 0xFF
    var paddleY: UInt8 = 0xFF
    /// Last value observed on the SID-local data bus for direct chip reads.
    var dataBusLatch: UInt8 = 0
    /// Remaining cycles before the floating SID-local data bus decays.
    var dataBusLatchCyclesRemaining: Int = 0

    // Filter state
    var filterLow: Double = 0
    var filterBand: Double = 0
    var filterHigh: Double = 0

    /// Audio sample accumulator
    var sampleCycleCounter: Double = 0

    /// Per-cycle oscillator MSB rising-edge flags used for hard sync.
    var oscillatorMSBRose = [Bool](repeating: false, count: 3)
    /// Per-cycle accumulator bit-19 rising-edge flags used to clock noise LFSRs.
    var noiseClockRose = [Bool](repeating: false, count: 3)

    /// Ring buffer for audio output
    public var sampleBuffer = [Float](repeating: 0, count: 8192)
    public var sampleWritePos: Int = 0
    public var sampleReadPos: Int = 0

    // MARK: - ADSR rate table (cycles per increment)

    static let attackRates: [UInt16] = [
        9, 32, 63, 95, 149, 220, 267, 313,
        392, 977, 1954, 3126, 3907, 11720, 19532, 31251
    ]

    static let decayReleaseRates: [UInt16] = [
        9, 32, 63, 95, 149, 220, 267, 313,
        392, 977, 1954, 3126, 3907, 11720, 19532, 31251
    ]

    static let dataBusLatchHoldCycles = 0x2000
    static let envelopeRateCounterMask: UInt16 = 0x7FFF

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
        dataBusLatch = 0
        dataBusLatchCyclesRemaining = 0
        filterLow = 0
        filterBand = 0
        filterHigh = 0
        sampleCycleCounter = 0
        oscillatorMSBRose = [Bool](repeating: false, count: 3)
        noiseClockRose = [Bool](repeating: false, count: 3)
        sampleWritePos = 0
        sampleReadPos = 0
        sampleBuffer = [Float](repeating: 0, count: sampleBuffer.count)
    }

    // MARK: - Tick

    /// Advance one system clock cycle.
    public func tick() {
        ageDataBusLatch()

        // Update all oscillators before applying sync so source edges are
        // independent of voice iteration order.
        for i in 0..<3 {
            clockOscillator(i)
        }
        applyOscillatorSync()

        for i in 0..<3 {
            clockEnvelope(i)
        }

        // Generate audio sample at the right rate
        sampleCycleCounter += 1
        if sampleCycleCounter >= cyclesPerSample {
            sampleCycleCounter -= cyclesPerSample
            generateSample()
        }
    }

    func clockOscillator(_ v: Int) {
        let prevMSB = voices[v].accumulator & 0x800000
        let prevNoiseClock = voices[v].accumulator & 0x080000

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
        }
    }

    func applyOscillatorSync() {
        for v in 0..<3 where voices[v].sync {
            let syncSource = (v + 2) % 3
            if oscillatorMSBRose[syncSource] {
                voices[v].accumulator = 0
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
            voices[v].exponentialPeriod = SID.exponentialPeriod(for: voices[v].envelopeLevel)
        }
        voices[v].gate = gateOn

        if voices[v].envelopeState == .sustain {
            if voices[v].envelopeLevel > sustainLevel(for: v) {
                voices[v].envelopeState = .decay
                voices[v].exponentialCounter = 0
                voices[v].exponentialPeriod = SID.exponentialPeriod(for: voices[v].envelopeLevel)
            } else {
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
            if voices[v].envelopeLevel == 0xFF {
                voices[v].envelopeState = .decay
                voices[v].exponentialCounter = 0
                voices[v].exponentialPeriod = SID.exponentialPeriod(for: voices[v].envelopeLevel)
            } else {
                voices[v].envelopeLevel &+= 1
                voices[v].exponentialPeriod = SID.exponentialPeriod(for: voices[v].envelopeLevel)
            }
        case .decay:
            if voices[v].envelopeLevel <= sustainLevel(for: v) {
                voices[v].envelopeState = .sustain
                break
            }
            clockExponentialDecayStep(v)
        case .sustain:
            break
        case .release:
            clockExponentialDecayStep(v)
        }
    }

    func sustainLevel(for v: Int) -> UInt8 {
        voices[v].sustain * 17  // 0-15 -> 0-255
    }

    func clockExponentialDecayStep(_ v: Int) {
        guard !voices[v].holdZero else { return }

        voices[v].exponentialCounter &+= 1
        guard voices[v].exponentialCounter >= voices[v].exponentialPeriod else { return }
        voices[v].exponentialCounter = 0

        if voices[v].envelopeLevel > 0 {
            voices[v].envelopeLevel -= 1
            voices[v].exponentialPeriod = SID.exponentialPeriod(for: voices[v].envelopeLevel)
        }
        if voices[v].envelopeLevel == 0 {
            voices[v].holdZero = true
            voices[v].exponentialPeriod = 1
        }
    }

    // MARK: - Waveform generation

    func oscillatorOutput(_ v: Int) -> UInt16 {
        let noiseOutput = voices[v].waveNoise ? noiseWaveformOutput(v) : nil

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

        if let noiseOutput {
            return hasOutput ? noiseOutput & output : noiseOutput
        }

        return output
    }

    func triangleWaveformOutput(_ v: Int) -> UInt16 {
        let acc = voices[v].accumulator
        let msb = acc >> 23
        var triangle: UInt16
        if msb != 0 {
            triangle = UInt16((~acc >> 11) & 0xFFF)
        } else {
            triangle = UInt16(acc >> 11) & 0xFFF
        }
        if voices[v].ringMod {
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
        let pulseWidth = min(voices[v].pulseWidth, 0x0FFF)
        if pulseWidth == 0 {
            return 0
        }
        if pulseWidth == 0x0FFF {
            return 0xFFF
        }
        let phase = UInt16(voices[v].accumulator >> 12)
        return phase >= pulseWidth ? 0xFFF : 0
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

    func waveformOutput(_ v: Int) -> Int16 {
        guard voices[v].hasWaveform else { return 0 }

        let centeredOutput = Int32(oscillatorOutput(v)) - 2048

        // Apply envelope after centering the 12-bit waveform. With a zero
        // envelope the voice contributes silence, not a DC offset.
        let envelope = UInt32(voices[v].envelopeLevel)
        let mixed = centeredOutput * Int32(envelope) * 16 / 255

        return Int16(clamping: mixed)
    }

    func generateSample() {
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

        if externalInputFiltered {
            filterInput += externalAudioInput
        } else {
            directOutput += externalAudioInput
        }

        var output = directOutput + applyFilter(input: filterInput)
        output = Int32(Double(output) * voiceOutputScale)
        output += volumeDACOffset

        // Apply master volume (0-15)
        output = (output * Int32(volume)) / 15

        // Clamp and convert to float
        let clamped = max(-32768, min(32767, output))
        let sample = Float(clamped) / 32768.0

        // Write to ring buffer
        sampleBuffer[sampleWritePos] = sample
        sampleWritePos = (sampleWritePos + 1) % sampleBuffer.count
    }

    func applyFilter(input: Int32) -> Int32 {
        guard filterInputEnabled || filterLP || filterBP || filterHP else { return input }

        let inputDouble = Double(input)
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

    var filterInputEnabled: Bool {
        filterControl & 0x0F != 0
    }

    // MARK: - Register access

    public func setExternalAudioInput(_ value: Int32) {
        externalAudioInput = Int32(max(-32768, min(32767, value)))
    }

    public func setPaddle(x: UInt8, y: UInt8) {
        paddleX = x
        paddleY = y
    }

    func latchDataBus(_ value: UInt8) {
        dataBusLatch = value
        dataBusLatchCyclesRemaining = Self.dataBusLatchHoldCycles
    }

    func ageDataBusLatch() {
        guard dataBusLatchCyclesRemaining > 0 else { return }
        dataBusLatchCyclesRemaining -= 1
        if dataBusLatchCyclesRemaining == 0 {
            dataBusLatch = 0
        }
    }

    public func readRegister(_ reg: UInt16) -> UInt8 {
        let value: UInt8
        switch reg {
        case 0x19:
            value = paddleX
        case 0x1A:
            value = paddleY
        case 0x1B:
            value = UInt8((oscillatorOutput(2) >> 4) & 0xFF)  // OSC3
        case 0x1C:
            value = voices[2].envelopeLevel  // ENV3
        default:
            value = dataBusLatch
        }
        latchDataBus(value)
        return value
    }

    public func writeRegister(_ reg: UInt16, value: UInt8) {
        latchDataBus(value)

        let voice = Int(reg / 7)
        let voiceReg = Int(reg % 7)

        if reg < 21 && voice < 3 {
            switch voiceReg {
            case 0: voices[voice].frequency = (voices[voice].frequency & 0xFF00) | UInt16(value)
            case 1: voices[voice].frequency = (voices[voice].frequency & 0x00FF) | (UInt16(value) << 8)
            case 2: voices[voice].pulseWidth = (voices[voice].pulseWidth & 0xF00) | UInt16(value)
            case 3: voices[voice].pulseWidth = (voices[voice].pulseWidth & 0x0FF) | (UInt16(value & 0x0F) << 8)
            case 4: writeControlRegister(voice: voice, value: value)
            case 5: voices[voice].attackDecay = value
            case 6: voices[voice].sustainRelease = value
            default: break
            }
        } else {
            switch reg {
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

    func writeControlRegister(voice: Int, value: UInt8) {
        let wasTestSet = voices[voice].testBit
        voices[voice].control = value
        let isTestSet = value & 0x08 != 0

        if isTestSet {
            voices[voice].accumulator = 0
            voices[voice].shiftRegister = 0
            oscillatorMSBRose[voice] = false
            noiseClockRose[voice] = false
        } else if wasTestSet && voices[voice].shiftRegister == 0 {
            voices[voice].shiftRegister = 0x7FFFF8
        }
    }
}
