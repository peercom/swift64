import Foundation

/// NES APU stub — enough to handle register writes and frame counter IRQ.
public final class APU {

    var registers = [UInt8](repeating: 0, count: 0x18)

    /// Frame counter IRQ
    public var irqPending: Bool = false

    var frameCounter: Int = 0
    var frameMode: Int = 0  // 0 = 4-step, 1 = 5-step
    var irqInhibit: Bool = false

    /// Audio sample buffer (44100 Hz mono)
    public var sampleBuffer = [Float](repeating: 0, count: 2048)
    public var sampleIndex: Int = 0

    // Pulse channel state
    var pulse1Period: UInt16 = 0
    var pulse1Volume: UInt8 = 0
    var pulse1Enabled: Bool = false
    var pulse2Period: UInt16 = 0
    var pulse2Volume: UInt8 = 0
    var pulse2Enabled: Bool = false
    var trianglePeriod: UInt16 = 0
    var triangleEnabled: Bool = false

    var cpuCycleCount: Int = 0

    public init() {}

    public func readRegister(_ address: UInt16) -> UInt8 {
        if address == 0x4015 {
            var status: UInt8 = 0
            if irqPending { status |= 0x40 }
            irqPending = false
            return status
        }
        return 0
    }

    public func writeRegister(_ address: UInt16, value: UInt8) {
        let reg = Int(address - 0x4000)
        guard reg >= 0 && reg < 0x18 else { return }
        registers[reg] = value

        switch address {
        case 0x4000:
            pulse1Volume = value & 0x0F
        case 0x4002:
            pulse1Period = (pulse1Period & 0x700) | UInt16(value)
        case 0x4003:
            pulse1Period = (pulse1Period & 0xFF) | (UInt16(value & 7) << 8)
        case 0x4004:
            pulse2Volume = value & 0x0F
        case 0x4006:
            pulse2Period = (pulse2Period & 0x700) | UInt16(value)
        case 0x4007:
            pulse2Period = (pulse2Period & 0xFF) | (UInt16(value & 7) << 8)
        case 0x4008:
            break // triangle linear counter
        case 0x400A:
            trianglePeriod = (trianglePeriod & 0x700) | UInt16(value)
        case 0x400B:
            trianglePeriod = (trianglePeriod & 0xFF) | (UInt16(value & 7) << 8)
        case 0x4015:
            pulse1Enabled = value & 1 != 0
            pulse2Enabled = value & 2 != 0
            triangleEnabled = value & 4 != 0
        case 0x4017:
            frameMode = Int(value >> 7)
            irqInhibit = (value & 0x40) != 0
            if irqInhibit { irqPending = false }
        default:
            break
        }
    }

    /// Called once per CPU cycle
    public func tick() {
        cpuCycleCount += 1

        // Generate a sample roughly every 40 CPU cycles (1789773 / 44100 ≈ 40.6)
        if cpuCycleCount % 41 == 0 {
            let sample = mixSample()
            if sampleIndex < sampleBuffer.count {
                sampleBuffer[sampleIndex] = sample
                sampleIndex += 1
            }
        }

        // Frame counter (every ~7457 CPU cycles = quarter frame)
        if cpuCycleCount % 7457 == 0 {
            frameCounter += 1
            if frameMode == 0 && frameCounter >= 4 {
                frameCounter = 0
                if !irqInhibit { irqPending = true }
            } else if frameMode == 1 && frameCounter >= 5 {
                frameCounter = 0
            }
        }
    }

    func mixSample() -> Float {
        var output: Float = 0

        // Simple pulse wave approximation
        if pulse1Enabled && pulse1Period > 8 {
            output += Float(pulse1Volume) / 15.0 * 0.3
        }
        if pulse2Enabled && pulse2Period > 8 {
            output += Float(pulse2Volume) / 15.0 * 0.3
        }
        if triangleEnabled && trianglePeriod > 2 {
            output += 0.15
        }

        return output * 0.5
    }
}
