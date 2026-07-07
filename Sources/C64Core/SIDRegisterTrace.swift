import Foundation

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

public struct SIDRegisterWriteTraceEvent: Codable, Equatable {
    public let cycle: UInt64
    public let pc: UInt16
    public let rasterLine: Int
    public let rasterCycle: Int
    public let register: UInt8
    public let value: UInt8
    public let reachedChip: Bool
    public let sidModel: SID.Model
    public let sidAccuracyMode: SID.AccuracyMode
    public let cpuPortDirection: UInt8?
    public let cpuPortData: UInt8?
    public let cpuPortEffective: UInt8?
    public let loram: Bool?
    public let hiram: Bool?
    public let charen: Bool?

    private enum CodingKeys: String, CodingKey {
        case cycle
        case pc
        case rasterLine
        case rasterCycle
        case register
        case value
        case reachedChip
        case sidModel
        case sidAccuracyMode
        case cpuPortDirection
        case cpuPortData
        case cpuPortEffective
        case loram
        case hiram
        case charen
    }

    public init(
        cycle: UInt64,
        pc: UInt16,
        rasterLine: Int,
        rasterCycle: Int,
        register: UInt8,
        value: UInt8,
        reachedChip: Bool = true,
        sidModel: SID.Model,
        sidAccuracyMode: SID.AccuracyMode,
        cpuPortDirection: UInt8? = nil,
        cpuPortData: UInt8? = nil,
        cpuPortEffective: UInt8? = nil,
        loram: Bool? = nil,
        hiram: Bool? = nil,
        charen: Bool? = nil
    ) {
        self.cycle = cycle
        self.pc = pc
        self.rasterLine = rasterLine
        self.rasterCycle = rasterCycle
        self.register = register & 0x1F
        self.value = value
        self.reachedChip = reachedChip
        self.sidModel = sidModel
        self.sidAccuracyMode = sidAccuracyMode
        self.cpuPortDirection = cpuPortDirection
        self.cpuPortData = cpuPortData
        self.cpuPortEffective = cpuPortEffective
        self.loram = loram
        self.hiram = hiram
        self.charen = charen
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cycle: try container.decode(UInt64.self, forKey: .cycle),
            pc: try container.decode(UInt16.self, forKey: .pc),
            rasterLine: try container.decode(Int.self, forKey: .rasterLine),
            rasterCycle: try container.decode(Int.self, forKey: .rasterCycle),
            register: try container.decode(UInt8.self, forKey: .register),
            value: try container.decode(UInt8.self, forKey: .value),
            reachedChip: try container.decode(Bool.self, forKey: .reachedChip),
            sidModel: try container.decode(SID.Model.self, forKey: .sidModel),
            sidAccuracyMode: try container.decode(SID.AccuracyMode.self, forKey: .sidAccuracyMode),
            cpuPortDirection: try container.decodeIfPresent(UInt8.self, forKey: .cpuPortDirection),
            cpuPortData: try container.decodeIfPresent(UInt8.self, forKey: .cpuPortData),
            cpuPortEffective: try container.decodeIfPresent(UInt8.self, forKey: .cpuPortEffective),
            loram: try container.decodeIfPresent(Bool.self, forKey: .loram),
            hiram: try container.decodeIfPresent(Bool.self, forKey: .hiram),
            charen: try container.decodeIfPresent(Bool.self, forKey: .charen)
        )
    }
}

public struct SIDRegisterTraceReplayResult: Equatable {
    public let eventCount: Int
    public let finalCycle: UInt64
    public let samplesGenerated: Int
    public let capturedSamples: [Float]
    public let capturedAudioSummary: SIDTraceAudioSummary
    public let bestAudioTextureWindow: SIDTraceAudioTextureWindow
    public let signature: SID.AudioSignature
    public let audioState: SID.AudioDebugState
    public let voiceStates: [SID.VoiceDebugState]
}

public struct SIDTraceAudioTextureWindow: Equatable {
    public let startSample: Int
    public let score: Double
    public let summary: SIDTraceAudioSummary

    public static let empty = SIDTraceAudioTextureWindow(
        startSample: 0,
        score: 0,
        summary: .empty
    )
}

public struct SIDTraceAudioSummary: Equatable {
    public let sampleCount: Int
    public let sampleRate: Double
    public let minimum: Float
    public let maximum: Float
    public let mean: Double
    public let rootMeanSquare: Double
    public let absoluteMean: Double
    public let zeroCrossings: Int
    public let zeroCrossingRate: Double
    public let lowBandRootMeanSquare: Double
    public let midBandRootMeanSquare: Double
    public let highBandRootMeanSquare: Double
    public let crestFactor: Double

    public static let empty = SIDTraceAudioSummary(samples: [], sampleRate: SID.sampleRate)

    public init(samples: [Float], sampleRate: Double = SID.sampleRate) {
        self.sampleCount = samples.count
        self.sampleRate = sampleRate

        guard !samples.isEmpty else {
            minimum = 0
            maximum = 0
            mean = 0
            rootMeanSquare = 0
            absoluteMean = 0
            zeroCrossings = 0
            zeroCrossingRate = 0
            lowBandRootMeanSquare = 0
            midBandRootMeanSquare = 0
            highBandRootMeanSquare = 0
            crestFactor = 0
            return
        }

        var minSample = Float.infinity
        var maxSample = -Float.infinity
        var sum = 0.0
        var absoluteSum = 0.0
        var sumSquares = 0.0
        var lowSquares = 0.0
        var midSquares = 0.0
        var highSquares = 0.0
        var zeroCrossings = 0
        var previousNonZeroSign: Int?
        var lowPass200 = 0.0
        var lowPass2000 = 0.0
        let lowAlpha = Self.lowPassAlpha(cutoff: 200, sampleRate: sampleRate)
        let midHighAlpha = Self.lowPassAlpha(cutoff: 2_000, sampleRate: sampleRate)

        for sample in samples {
            let value = Double(sample)
            minSample = min(minSample, sample)
            maxSample = max(maxSample, sample)
            sum += value
            absoluteSum += abs(value)
            sumSquares += value * value

            lowPass200 += lowAlpha * (value - lowPass200)
            lowPass2000 += midHighAlpha * (value - lowPass2000)
            let low = lowPass200
            let mid = lowPass2000 - lowPass200
            let high = value - lowPass2000
            lowSquares += low * low
            midSquares += mid * mid
            highSquares += high * high

            let sign = value < 0 ? -1 : (value > 0 ? 1 : 0)
            if sign != 0 {
                if let previousNonZeroSign, previousNonZeroSign != sign {
                    zeroCrossings += 1
                }
                previousNonZeroSign = sign
            }
        }

        let count = Double(samples.count)
        let rms = sqrt(sumSquares / count)
        minimum = minSample
        maximum = maxSample
        mean = sum / count
        rootMeanSquare = rms
        absoluteMean = absoluteSum / count
        self.zeroCrossings = zeroCrossings
        zeroCrossingRate = sampleRate > 0 ? Double(zeroCrossings) / (count / sampleRate) : 0
        lowBandRootMeanSquare = sqrt(lowSquares / count)
        midBandRootMeanSquare = sqrt(midSquares / count)
        highBandRootMeanSquare = sqrt(highSquares / count)
        let peak = max(abs(Double(minSample)), abs(Double(maxSample)))
        crestFactor = rms > 0 ? peak / rms : 0
    }

    private static func lowPassAlpha(cutoff: Double, sampleRate: Double) -> Double {
        guard cutoff > 0, sampleRate > 0 else { return 1 }
        return (1 - exp(-2 * Double.pi * cutoff / sampleRate)).clamped(to: 0...1)
    }
}

public enum SIDRegisterTraceReplayError: Error, Equatable {
    case emptyTrace
    case nonMonotonicCycle(previous: UInt64, next: UInt64)
}

public enum SIDRegisterTraceDecodeError: Error, Equatable {
    case invalidUTF8
    case invalidJSONLine(Int)
}

public final class SIDRegisterTracePlayer {
    public init() {}

    public func decodeJSONLines(_ data: Data) throws -> [SIDRegisterWriteTraceEvent] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SIDRegisterTraceDecodeError.invalidUTF8
        }

        let decoder = JSONDecoder()
        var events: [SIDRegisterWriteTraceEvent] = []
        for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8),
                  let event = try? decoder.decode(SIDRegisterWriteTraceEvent.self, from: lineData) else {
                throw SIDRegisterTraceDecodeError.invalidJSONLine(offset + 1)
            }
            events.append(event)
        }
        return events
    }

    public func replay(
        _ events: [SIDRegisterWriteTraceEvent],
        model: SID.Model? = nil,
        accuracyMode: SID.AccuracyMode? = nil,
        clockRate: Double = 985_248,
        normalizeToFirstEvent: Bool = true,
        tailCycles: UInt64 = 0,
        signatureSampleCount: Int = 2048,
        captureSampleLimit: Int = 0,
        captureStartAfterGeneratedSamples: Int = 0,
        captureStartWhenAbsoluteSampleAtLeast: Float = 0,
        textureWindowSampleCount: Int = 0,
        textureWindowStride: Int = 0
    ) throws -> SIDRegisterTraceReplayResult {
        guard let firstEvent = events.first else {
            throw SIDRegisterTraceReplayError.emptyTrace
        }

        let sid = SID()
        sid.model = model ?? firstEvent.sidModel
        sid.accuracyMode = accuracyMode ?? firstEvent.sidAccuracyMode
        sid.clockRate = clockRate
        sid.reset()

        var currentCycle = normalizeToFirstEvent ? firstEvent.cycle : 0
        var samplesGenerated = 0
        let maxCapturedSamples = max(0, captureSampleLimit)
        let samplesToSkipBeforeCapture = max(0, captureStartAfterGeneratedSamples)
        let captureThreshold = max(0, captureStartWhenAbsoluteSampleAtLeast)
        var captureGateOpened = captureThreshold == 0
        var capturedSamples: [Float] = []
        if maxCapturedSamples > 0 {
            capturedSamples.reserveCapacity(min(maxCapturedSamples, 65_536))
        }
        let analyzedWindowSampleCount = max(0, textureWindowSampleCount)
        let analyzedWindowStride = max(1, textureWindowStride > 0 ? textureWindowStride : analyzedWindowSampleCount)
        var textureRing = analyzedWindowSampleCount > 0
            ? [Float](repeating: 0, count: analyzedWindowSampleCount)
            : []
        var textureWriteIndex = 0
        var textureSamplesSeen = 0
        var nextTextureEvaluationSample = analyzedWindowSampleCount
        var bestTextureWindow = SIDTraceAudioTextureWindow.empty
        sid.onSampleGenerated = { sample in
            samplesGenerated += 1
            if !captureGateOpened && abs(sample) >= captureThreshold {
                captureGateOpened = true
            }
            if captureGateOpened &&
                samplesGenerated > samplesToSkipBeforeCapture &&
                capturedSamples.count < maxCapturedSamples {
                capturedSamples.append(sample)
            }
            if analyzedWindowSampleCount > 0 {
                textureRing[textureWriteIndex] = sample
                textureWriteIndex = (textureWriteIndex + 1) % analyzedWindowSampleCount
                textureSamplesSeen += 1
                if textureSamplesSeen >= analyzedWindowSampleCount &&
                    samplesGenerated >= nextTextureEvaluationSample {
                    let windowSamples = (0..<analyzedWindowSampleCount).map { offset in
                        textureRing[(textureWriteIndex + offset) % analyzedWindowSampleCount]
                    }
                    let summary = SIDTraceAudioSummary(samples: windowSamples, sampleRate: SID.sampleRate)
                    let score = Self.audioTextureScore(summary)
                    if score > bestTextureWindow.score {
                        bestTextureWindow = SIDTraceAudioTextureWindow(
                            startSample: samplesGenerated - analyzedWindowSampleCount,
                            score: score,
                            summary: summary
                        )
                    }
                    nextTextureEvaluationSample += analyzedWindowStride
                }
            }
        }
        defer { sid.onSampleGenerated = nil }

        var previousEventCycle = firstEvent.cycle
        for event in events {
            guard event.cycle >= previousEventCycle else {
                throw SIDRegisterTraceReplayError.nonMonotonicCycle(
                    previous: previousEventCycle,
                    next: event.cycle
                )
            }
            previousEventCycle = event.cycle

            while currentCycle < event.cycle {
                sid.tick()
                currentCycle += 1
            }
            if event.reachedChip {
                sid.writeRegister(UInt16(event.register), value: event.value)
            }
        }

        let targetCycle = currentCycle + tailCycles
        while currentCycle < targetCycle {
            sid.tick()
            currentCycle += 1
        }

        return SIDRegisterTraceReplayResult(
            eventCount: events.count,
            finalCycle: currentCycle,
            samplesGenerated: samplesGenerated,
            capturedSamples: capturedSamples,
            capturedAudioSummary: SIDTraceAudioSummary(
                samples: capturedSamples,
                sampleRate: SID.sampleRate
            ),
            bestAudioTextureWindow: bestTextureWindow,
            signature: sid.recentAudioSignature(sampleCount: signatureSampleCount),
            audioState: sid.debugAudioState(),
            voiceStates: sid.debugVoiceStates()
        )
    }

    private static func audioTextureScore(_ summary: SIDTraceAudioSummary) -> Double {
        guard summary.sampleCount > 0 else { return 0 }
        let brightness = summary.midBandRootMeanSquare + summary.highBandRootMeanSquare
        let crossingWeight = min(summary.zeroCrossingRate / 4_000.0, 1.0)
        return brightness + summary.rootMeanSquare * crossingWeight * 0.1
    }
}
