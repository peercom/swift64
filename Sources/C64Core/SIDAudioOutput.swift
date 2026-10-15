import Foundation

/// Single-consumer speaker path shared by Core Audio and offline validation.
public final class SIDAudioOutput {
    public struct Statistics: Codable {
        public var renderedFrames: UInt64 = 0
        public var sourceFrames: UInt64 = 0
        public var startupFrames: UInt64 = 0
        public var underrunFrames: UInt64 = 0
        public var underrunEvents: UInt64 = 0
        public var overrunFrames: UInt64 = 0
        public var clippedFrames: UInt64 = 0
    }

    private let sid: SID
    public let startupTarget: Int
    private var waitingForStartup = true
    private var hasSourceHistory = false
    private var recovering = true
    private var fadeInRemaining = 64
    private var fadeOutRemaining = 0
    private var recoveryOrigin: Float = 0
    private var previousInput: Float = 0
    private var previousOutput: Float = 0
    private var lastOutput: Float = 0
    private var counters = Statistics()
    private let statisticsLock = NSLock()

    public init(sid: SID, startupTarget: Int = 4096) {
        self.sid = sid
        self.startupTarget = min(max(0, startupTarget), sid.sampleBuffer.count)
    }

    public var statistics: Statistics {
        statisticsLock.lock()
        var result = counters
        statisticsLock.unlock()
        result.overrunFrames = sid.audioOverrunFrames
        return result
    }

    /// Call from one audio consumer only. No allocation or file I/O occurs here.
    public func render(into output: UnsafeMutableBufferPointer<Float>) {
        guard !output.isEmpty else { return }
        var delta = Statistics()
        delta.renderedFrames = UInt64(output.count)
        if waitingForStartup && sid.availableAudioSamplesForPlayback() < startupTarget {
            output.update(repeating: 0)
            delta.startupFrames = UInt64(output.count)
            record(delta)
            return
        }
        waitingForStartup = false
        let readCount = sid.readAudioSamplesForPlayback(into: output)
        delta.sourceFrames = UInt64(readCount)

        if recovering && readCount > 0 {
            // A starved queue does not advance the SID. Its next samples still
            // follow the previous source samples; reseeding at an arbitrary
            // waveform phase creates a false DC step and can clip on recovery.
            if !hasSourceHistory {
                previousInput = output[0]
                previousOutput = 0
                hasSourceHistory = true
            }
            recoveryOrigin = lastOutput
            fadeInRemaining = 64
            recovering = false
        }
        for index in 0..<readCount {
            let input = output[index]
            let coupled = input - previousInput + 0.995 * previousOutput
            previousInput = input
            previousOutput = coupled
            if abs(coupled) > 0.95 { delta.clippedFrames += 1 }
            let gain = Float(64 - fadeInRemaining) / 64
            lastOutput = recoveryOrigin * (1 - gain) + min(max(coupled, -0.95), 0.95) * gain
            output[index] = lastOutput
            fadeInRemaining = max(0, fadeInRemaining - 1)
        }

        if readCount < output.count {
            if !recovering {
                delta.underrunEvents = 1
                fadeOutRemaining = 64
            }
            delta.underrunFrames = UInt64(output.count - readCount)
            for index in readCount..<output.count {
                if fadeOutRemaining > 0 {
                    lastOutput *= Float(fadeOutRemaining - 1) / Float(fadeOutRemaining)
                    fadeOutRemaining -= 1
                } else {
                    lastOutput = 0
                }
                output[index] = lastOutput
            }
            recovering = true
        }
        record(delta)
    }

    private func record(_ delta: Statistics) {
        statisticsLock.lock()
        counters.renderedFrames += delta.renderedFrames
        counters.sourceFrames += delta.sourceFrames
        counters.startupFrames += delta.startupFrames
        counters.underrunFrames += delta.underrunFrames
        counters.underrunEvents += delta.underrunEvents
        counters.clippedFrames += delta.clippedFrames
        statisticsLock.unlock()
    }
}
