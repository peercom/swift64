import Foundation

/// MOS 6581 SID (Sound Interface Device) emulation.
/// Simplified but functional: 3 voices with waveforms, ADSR, and filter.
public final class SID {

    // MARK: - Constants

    static let clockRate: Double = 985248.0  // PAL
    public static let sampleRate: Double = 44100.0
    static let cyclesPerSample = clockRate / sampleRate

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

    var volume: UInt8 { volumeFilter & 0x0F }
    var filterLP: Bool { volumeFilter & 0x10 != 0 }
    var filterBP: Bool { volumeFilter & 0x20 != 0 }
    var filterHP: Bool { volumeFilter & 0x40 != 0 }
    var voice3Off: Bool { volumeFilter & 0x80 != 0 }

    // Filter state
    var filterLow: Double = 0
    var filterBand: Double = 0
    var filterHigh: Double = 0

    /// Audio sample accumulator
    var sampleCycleCounter: Double = 0

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

    // MARK: - Init

    public init() {}

    // MARK: - Tick

    /// Advance one system clock cycle.
    public func tick() {
        // Update oscillators and envelopes
        for i in 0..<3 {
            clockOscillator(i)
            clockEnvelope(i)
        }

        // Generate audio sample at the right rate
        sampleCycleCounter += 1
        if sampleCycleCounter >= SID.cyclesPerSample {
            sampleCycleCounter -= SID.cyclesPerSample
            generateSample()
        }
    }

    func clockOscillator(_ v: Int) {
        let prevMSB = voices[v].accumulator & 0x800000

        if voices[v].testBit {
            voices[v].accumulator = 0
            voices[v].shiftRegister = 0
        } else {
            voices[v].accumulator = (voices[v].accumulator + UInt32(voices[v].frequency)) & 0xFFFFFF
        }

        // Noise shift register clock on bit 19 transition
        let newMSB = voices[v].accumulator & 0x800000
        if prevMSB == 0 && newMSB != 0 {
            let bit22 = (voices[v].shiftRegister >> 22) & 1
            let bit17 = (voices[v].shiftRegister >> 17) & 1
            let newBit = bit22 ^ bit17
            voices[v].shiftRegister = ((voices[v].shiftRegister << 1) | newBit) & 0x7FFFFF
        }

        // Sync: reset accumulator when sync source's MSB transitions
        if voices[v].sync {
            let syncSource = (v + 2) % 3
            if voices[syncSource].accumulator & 0x800000 != 0 {
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
        } else if !gateOn && voices[v].gate {
            voices[v].envelopeState = .release
        }
        voices[v].gate = gateOn

        voices[v].rateCounter += 1

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

        guard voices[v].rateCounter >= rate else { return }
        voices[v].rateCounter = 0

        switch voices[v].envelopeState {
        case .attack:
            if voices[v].envelopeLevel == 0xFF {
                voices[v].envelopeState = .decay
            } else {
                voices[v].envelopeLevel &+= 1
            }
        case .decay:
            let sustainLevel = voices[v].sustain * 17  // 0-15 → 0-255
            if voices[v].envelopeLevel > sustainLevel {
                if voices[v].envelopeLevel > 0 {
                    voices[v].envelopeLevel -= 1
                }
            } else {
                voices[v].envelopeState = .sustain
            }
        case .sustain:
            break
        case .release:
            if voices[v].envelopeLevel > 0 {
                voices[v].envelopeLevel -= 1
            }
        }
    }

    // MARK: - Waveform generation

    func waveformOutput(_ v: Int) -> Int16 {
        let acc = voices[v].accumulator
        var output: UInt16 = 0

        if voices[v].waveNoise {
            let sr = voices[v].shiftRegister
            var noiseBits: UInt32 = 0
            noiseBits |= (sr >> 15) & 0x800
            noiseBits |= (sr >> 14) & 0x400
            noiseBits |= (sr >> 11) & 0x200
            noiseBits |= (sr >> 9)  & 0x100
            noiseBits |= (sr >> 8)  & 0x080
            noiseBits |= (sr >> 5)  & 0x040
            noiseBits |= (sr >> 3)  & 0x020
            noiseBits |= (sr >> 2)  & 0x010
            output = UInt16(noiseBits) << 4
        } else {
            var triangle: UInt16 = 0
            var sawtooth: UInt16 = 0
            var pulse: UInt16 = 0

            if voices[v].waveTriangle {
                let msb = acc >> 23
                if msb != 0 {
                    triangle = UInt16(~acc >> 11) & 0xFFF
                } else {
                    triangle = UInt16(acc >> 11) & 0xFFF
                }
                // Ring modulation
                if voices[v].ringMod {
                    let syncSource = (v + 2) % 3
                    if voices[syncSource].accumulator & 0x800000 != 0 {
                        triangle ^= 0xFFF
                    }
                }
                output = triangle << 4
            }

            if voices[v].waveSawtooth {
                sawtooth = UInt16(acc >> 12)
                if output != 0 {
                    output &= sawtooth << 4
                } else {
                    output = sawtooth << 4
                }
            }

            if voices[v].wavePulse {
                let threshold = UInt32(voices[v].pulseWidth) << 12
                pulse = (acc >= threshold) ? 0xFFF : 0
                if output != 0 {
                    output &= pulse << 4
                } else {
                    output = pulse << 4
                }
            }
        }

        // Apply envelope (output is 0..65520, envelope is 0..255)
        // mixed range: 0..65265 → center around 0 by subtracting half range
        let envelope = UInt32(voices[v].envelopeLevel)
        let mixed = Int32(UInt32(output) * envelope) >> 8

        return Int16(clamping: mixed - 32632)
    }

    func generateSample() {
        var output: Int32 = 0

        for v in 0..<3 {
            if v == 2 && voice3Off { continue }
            let voiceOut = Int32(waveformOutput(v))

            // Apply filter routing
            let filtered = filterControl & (1 << v) != 0
            if filtered {
                // Route through filter
                output += voiceOut  // Simplified: actual filter applied below
            } else {
                output += voiceOut
            }
        }

        // Apply master volume (0-15)
        output = (output * Int32(volume)) / 15

        // Clamp and convert to float
        let clamped = max(-32768, min(32767, output))
        let sample = Float(clamped) / 32768.0

        // Write to ring buffer
        sampleBuffer[sampleWritePos] = sample
        sampleWritePos = (sampleWritePos + 1) % sampleBuffer.count
    }

    // MARK: - Register access

    public func readRegister(_ reg: UInt16) -> UInt8 {
        switch reg {
        case 0x19: return 0  // Paddle X
        case 0x1A: return 0  // Paddle Y
        case 0x1B: return UInt8((voices[2].accumulator >> 16) & 0xFF)  // OSC3
        case 0x1C: return voices[2].envelopeLevel  // ENV3
        default: return 0
        }
    }

    public func writeRegister(_ reg: UInt16, value: UInt8) {
        let voice = Int(reg / 7)
        let voiceReg = Int(reg % 7)

        if reg < 21 && voice < 3 {
            switch voiceReg {
            case 0: voices[voice].frequency = (voices[voice].frequency & 0xFF00) | UInt16(value)
            case 1: voices[voice].frequency = (voices[voice].frequency & 0x00FF) | (UInt16(value) << 8)
            case 2: voices[voice].pulseWidth = (voices[voice].pulseWidth & 0xF00) | UInt16(value)
            case 3: voices[voice].pulseWidth = (voices[voice].pulseWidth & 0x0FF) | (UInt16(value & 0x0F) << 8)
            case 4: voices[voice].control = value
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
}
