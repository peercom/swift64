import XCTest
@testable import C64Core

final class PerformanceBenchmarkTests: XCTestCase {
    private let cycleCount = 250_000
    private let frameCount = 30

    private func requireBenchmarksEnabled() throws {
        guard ProcessInfo.processInfo.environment["SWIFT64_PERF_BENCHMARKS"] == "1" else {
            throw XCTSkip("Set SWIFT64_PERF_BENCHMARKS=1 to run performance benchmarks.")
        }
    }

    private func time(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000_000.0
    }

    private func report(_ name: String, elapsed: Double, units: Int, unitName: String) {
        let rate = elapsed > 0 ? Double(units) / elapsed : 0
        print(String(format: "[Swift64Perf] %@: %.4fs, %.0f %@/s", name, elapsed, rate, unitName))
    }

    func testRunFrameThroughputFastLoad() throws {
        try requireBenchmarksEnabled()
        let c64 = C64()
        c64.trueDriveEmulationMode = .off
        c64.vic.recordsBusAccessTraces = false
        c64.powerOn()

        let elapsed = time {
            for _ in 0..<frameCount {
                _ = c64.runFrame()
            }
        }
        report("runFrame fast-load", elapsed: elapsed, units: frameCount, unitName: "frames")
    }

    func testRunFrameThroughputCompatTrueDrive() throws {
        try requireBenchmarksEnabled()
        let c64 = C64()
        c64.trueDriveEmulationMode = .compat1541
        c64.vic.recordsBusAccessTraces = false
        c64.powerOn()

        let elapsed = time {
            for _ in 0..<frameCount {
                _ = c64.runFrame()
            }
        }
        report("runFrame compat true-drive", elapsed: elapsed, units: frameCount, unitName: "frames")
    }

    func testRunFrameThroughputStrictTrueDrive() throws {
        try requireBenchmarksEnabled()
        let c64 = C64()
        c64.trueDriveEmulationMode = .standard1541
        c64.vic.recordsBusAccessTraces = false
        c64.powerOn()

        let elapsed = time {
            for _ in 0..<frameCount {
                _ = c64.runFrame()
            }
        }
        report("runFrame strict true-drive", elapsed: elapsed, units: frameCount, unitName: "frames")
    }

    func testTickOneCycleThroughputWithVICTraceModes() throws {
        try requireBenchmarksEnabled()

        for recordsTraces in [false, true] {
            let c64 = C64()
            c64.vic.recordsBusAccessTraces = recordsTraces
            c64.powerOn()

            let elapsed = time {
                for _ in 0..<cycleCount {
                    c64.tickOneCycle()
                }
            }
            report(
                "tickOneCycle VIC traces \(recordsTraces ? "on" : "off")",
                elapsed: elapsed,
                units: cycleCount,
                unitName: "cycles"
            )
        }
    }

    func testSIDFastVersusCompatibilityThroughput() throws {
        try requireBenchmarksEnabled()

        for mode in [SID.AccuracyMode.fast, .compatibility] {
            let sid = SID()
            sid.accuracyMode = mode
            sid.writeRegister(0x00, value: 0x11)
            sid.writeRegister(0x01, value: 0x25)
            sid.writeRegister(0x05, value: 0x00)
            sid.writeRegister(0x06, value: 0xF8)
            sid.writeRegister(0x04, value: 0x21)
            sid.writeRegister(0x18, value: 0x0F)

            let elapsed = time {
                for _ in 0..<cycleCount {
                    sid.tick()
                }
            }
            report("SID \(mode.rawValue)", elapsed: elapsed, units: cycleCount, unitName: "cycles")
        }
    }

    func testSIDPlaybackDrainThroughputSingleSampleVersusBatch() throws {
        try requireBenchmarksEnabled()
        let batchSize = 512
        let rounds = 200

        let singleSID = SID()
        let samplesPerRound = singleSID.sampleBuffer.count
        let totalSamples = samplesPerRound * rounds
        let singleElapsed = time {
            for round in 0..<rounds {
                for index in 0..<samplesPerRound {
                    singleSID.writeSample(Int32((round + index) & 0x7FFF))
                }
                var drained = 0
                while drained < samplesPerRound, singleSID.readAudioSampleForPlayback() != nil {
                    drained += 1
                }
            }
        }
        report("SID playback drain single", elapsed: singleElapsed, units: totalSamples, unitName: "samples")

        let batchSID = SID()
        var buffer = [Float](repeating: 0, count: batchSize)
        let batchElapsed = time {
            for round in 0..<rounds {
                for index in 0..<samplesPerRound {
                    batchSID.writeSample(Int32((round + index) & 0x7FFF))
                }
                var drained = 0
                while drained < samplesPerRound {
                    let readCount = buffer.withUnsafeMutableBufferPointer {
                        batchSID.readAudioSamplesForPlayback(into: $0)
                    }
                    if readCount == 0 { break }
                    drained += readCount
                }
            }
        }
        report("SID playback drain batch", elapsed: batchElapsed, units: totalSamples, unitName: "samples")
    }

    func testFramebufferCopyCost() throws {
        try requireBenchmarksEnabled()
        let pixelCount = VIC.screenWidth * VIC.screenHeight
        let source = [UInt32](repeating: 0xFF123456, count: pixelCount)
        var destination = [UInt32](repeating: 0, count: pixelCount)
        let copies = 1_000

        let elapsed = time {
            for _ in 0..<copies {
                destination.withUnsafeMutableBufferPointer { dst in
                    source.withUnsafeBufferPointer { src in
                        dst.baseAddress?.update(from: src.baseAddress!, count: pixelCount)
                    }
                }
            }
        }
        XCTAssertEqual(destination.last, source.last)
        report("framebuffer buffer copy", elapsed: elapsed, units: copies, unitName: "copies")
    }
}
