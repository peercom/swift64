import AppKit
import AVFoundation
import C64Core

/// Opt-in, bounded capture of the actual Core Audio source buffer. No media/ROM
/// dependency, preference changes, or callback file I/O. Inactive in normal use.
final class AudioPlaybackValidation {
    let seconds: Double
    let name: String
    private let kind: SIDSoundCheck.Kind
    private let standard: String
    private let toneFrequency: Double
    private let frameRate: Double
    private let started = ProcessInfo.processInfo.systemUptime
    private let lowPowerModeAtStart = ProcessInfo.processInfo.isLowPowerModeEnabled
    private let thermalStateAtStart = ProcessInfo.processInfo.thermalState.rawValue
    private var capture = [Float](repeating: 0, count: Int(SID.sampleRate * 12))
    private var tail = [Float](repeating: 0, count: Int(SID.sampleRate * 12))
    private var tailPosition = 0
    private var captured = 0
    private var frames: UInt64 = 0
    private var sumSquares = 0.0
    private var peak: Float = 0
    private var invalidSamples: UInt64 = 0
    private var silentRun: UInt64 = 0
    private var longestSilentRun: UInt64 = 0
    private var firstSignalFrame: UInt64?
    private var longestPostOnsetSilentRun: UInt64 = 0
    private var firstCallbackTime: Double?
    private var lastCallbackEndTime: Double = 0

    private init(seconds: Double, name: String, kind: SIDSoundCheck.Kind,
                 standard: String, toneFrequency: Double, frameRate: Double) {
        self.seconds = seconds
        self.name = name
        self.kind = kind
        self.standard = standard
        self.toneFrequency = toneFrequency
        self.frameRate = frameRate
    }

    static func fromEnvironment(c64: C64) -> AudioPlaybackValidation? {
        let env = ProcessInfo.processInfo.environment
        guard let value = env["SWIFT64_AUDIO_CHECK_SECONDS"], let seconds = Double(value), seconds.isFinite else { return nil }
        let kind = SIDSoundCheck.Kind(rawValue: env["SWIFT64_AUDIO_CHECK_KIND"] ?? "music") ?? .music
        let model: SID.Model = env["SWIFT64_AUDIO_CHECK_MODEL"] == "mos8580" ? .mos8580 : .mos6581
        let mode: SID.AccuracyMode = env["SWIFT64_AUDIO_CHECK_MODE"] == "fast" ? .fast : .compatibility
        let standard = env["SWIFT64_AUDIO_CHECK_STANDARD"] == "ntsc" ? "ntsc" : "pal"
        let requestedFrequency = Double(env["SWIFT64_AUDIO_CHECK_HZ"] ?? "440") ?? 440
        let frequency = requestedFrequency.isFinite ? min(10_000, max(20, requestedFrequency)) : 440
        c64.trueDriveEmulationMode = .off
        c64.machineProfile = standard == "ntsc" ? .ntscC64 : .palC64
        c64.sidModelOverride = model
        c64.sid.accuracyMode = mode
        c64.powerOn()
        c64.loadPRG(SIDSoundCheck.program(kind: kind, clockRate: c64.sid.clockRate, toneFrequency: frequency))
        c64.cpu.powerOn()
        c64.cpu.pc = SIDSoundCheck.entryPoint
        let toneSuffix = kind == .tone ? "-\(String(format: "%.3f", frequency))Hz" : ""
        return AudioPlaybackValidation(seconds: min(300, max(3, seconds)),
                                       name: "\(kind)-\(standard)-\(model)-\(mode)\(toneSuffix)", kind: kind,
                                       standard: standard, toneFrequency: frequency,
                                       frameRate: c64.machineProfile.displayFrameRateHz)
    }

    // Single audio-callback producer. Read only after engine.stop() returns.
    func record(_ samples: UnsafeMutableBufferPointer<Float>) {
        let now = ProcessInfo.processInfo.systemUptime
        if firstCallbackTime == nil { firstCallbackTime = now }
        lastCallbackEndTime = now + Double(samples.count) / SID.sampleRate
        for sample in samples {
            if captured < capture.count {
                capture[captured] = sample
                captured += 1
            }
            tail[tailPosition] = sample
            tailPosition += 1
            if tailPosition == tail.count { tailPosition = 0 }
            frames += 1
            guard sample.isFinite else { invalidSamples += 1; continue }
            sumSquares += Double(sample) * Double(sample)
            peak = max(peak, abs(sample))
            silentRun = abs(sample) < 0.00001 ? silentRun + 1 : 0
            longestSilentRun = max(longestSilentRun, silentRun)
            if silentRun == 0 && firstSignalFrame == nil { firstSignalFrame = frames - 1 }
            if firstSignalFrame != nil {
                longestPostOnsetSilentRun = max(longestPostOnsetSilentRun, silentRun)
            }
        }
    }

    func scheduleReport(controller: EmulatorController) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak controller, self] in
            guard let controller else { return }
            controller.audioEngine?.stop()
            controller.renderer?.stop()
            do {
                try save(statistics: controller.audioOutput?.statistics)
            } catch {
                print("AUDIO_VALIDATION_ERROR \(error)")
            }
            NSApplication.shared.terminate(nil)
        }
    }

    private func save(statistics: SIDAudioOutput.Statistics?) throws {
        let wallSeconds = ProcessInfo.processInfo.systemUptime - started
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Swift64/AudioValidation", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name + ".wav")
        try writeWAV(Array(capture.prefix(captured)), to: url)
        let tailCount = Int(min(frames, UInt64(tail.count)))
        let orderedTail = frames >= UInt64(tail.count)
            ? Array(tail[tailPosition...] + tail[..<tailPosition]) : Array(tail.prefix(tailCount))
        try writeWAV(orderedTail, to: directory.appendingPathComponent(name + "-tail.wav"))
        struct Report: Encodable {
            let version: Int
            let lowPowerModeAtStart: Bool
            let lowPowerModeAtEnd: Bool
            let thermalStateAtStart: Int
            let thermalStateAtEnd: Int
            let name: String
            let kind: String
            let standard: String
            let requestedSeconds: Double
            let sampleRate: Double
            let frameRate: Double
            let toneFrequency: Double?
            let wallSeconds: Double
            let callbackWallSeconds: Double
            let audioSeconds: Double
            let capturedSeconds: Double
            let tailStartSeconds: Double
            let tailCapturedSeconds: Double
            let rms: Double
            let peak: Float
            let invalidSamples: UInt64
            let longestSilenceSeconds: Double
            let firstSignalSeconds: Double?
            let longestPostOnsetSilenceSeconds: Double
            let playback: SIDAudioOutput.Statistics?
        }
        let report = Report(version: 2, lowPowerModeAtStart: lowPowerModeAtStart,
                            lowPowerModeAtEnd: ProcessInfo.processInfo.isLowPowerModeEnabled,
                            thermalStateAtStart: thermalStateAtStart,
                            thermalStateAtEnd: ProcessInfo.processInfo.thermalState.rawValue,
                            name: name, kind: kind.rawValue, standard: standard,
                            requestedSeconds: seconds, sampleRate: SID.sampleRate, frameRate: frameRate,
                            toneFrequency: kind == .tone ? toneFrequency : nil,
                            wallSeconds: wallSeconds,
                            callbackWallSeconds: firstCallbackTime.map { lastCallbackEndTime - $0 } ?? 0,
                            audioSeconds: Double(frames) / SID.sampleRate,
                            capturedSeconds: Double(captured) / SID.sampleRate,
                            tailStartSeconds: Double(frames - UInt64(tailCount)) / SID.sampleRate,
                            tailCapturedSeconds: Double(tailCount) / SID.sampleRate,
                            rms: sqrt(sumSquares / Double(max(1, frames))), peak: peak,
                            invalidSamples: invalidSamples,
                            longestSilenceSeconds: Double(longestSilentRun) / SID.sampleRate,
                            firstSignalSeconds: firstSignalFrame.map { Double($0) / SID.sampleRate },
                            longestPostOnsetSilenceSeconds: Double(longestPostOnsetSilentRun) / SID.sampleRate,
                            playback: statistics)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: directory.appendingPathComponent(name + ".json"), options: .atomic)
        print("AUDIO_VALIDATION \(url.path)\n\(String(decoding: data, as: UTF8.self))")
    }

    private func writeWAV(_ samples: [Float], to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: SID.sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count)))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress {
                buffer.floatChannelData![0].update(from: base, count: samples.count)
            }
        }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: SID.sampleRate,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
        ])
        try file.write(from: buffer)
    }
}
