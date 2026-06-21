import XCTest
import Emu6502
import Foundation

private final class ConformanceRAMBus: Bus {
    var memory = [UInt8](repeating: 0, count: 0x10000)

    func read(_ address: UInt16) -> UInt8 {
        memory[Int(address)]
    }

    func write(_ address: UInt16, value: UInt8) {
        memory[Int(address)] = value
    }

    func loadBinary(_ data: Data, at address: UInt16) {
        let start = Int(address)
        let count = min(data.count, memory.count - start)
        for offset in 0..<count {
            memory[start + offset] = data[offset]
        }
    }
}

final class CPU6502ConformanceTests: XCTestCase {
    func testCPUFunctionalRunRecordWritesJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("cpu-functional.json")
        let record = CPUFunctionalRunRecord(
            fixtureID: "functional",
            fixtureName: "Functional test",
            binaryPath: "/tmp/6502_functional_test.bin",
            binarySize: 0x1000,
            binaryFNV1A64: "1234567890ABCDEF",
            loadAddress: "$0000",
            startPC: "$0400",
            initialRegisters: CPUFunctionalRegisterValues(a: "$10", x: "$20", y: "$30", sp: "$FD", p: "$24"),
            successPC: "$3469",
            maxCycles: 100_000_000,
            expectedElapsedCycles: 12340,
            elapsedCycleTolerance: 2,
            elapsedCycleDelta: -2,
            passed: false,
            jammed: true,
            outcome: "cpuJam",
            failureCategory: "cpu",
            expectedFailureCategory: "cpu",
            expectedFailureReasonContains: ["CPU jammed"],
            expectedFailureNote: "Known local fixture",
            expectationStatus: "expectedFailure",
            finalRegisterMismatches: [],
            finalMemoryMismatches: [],
            finalPC: "$02A3",
            finalA: "$10",
            finalX: "$20",
            finalY: "$30",
            finalSP: "$FD",
            finalP: "$24",
            finalInstructionCycle: 0,
            totalCycles: 12345,
            elapsedCycles: 12338,
            reason: "CPU jammed"
        )

        try writeCPUFunctionalRunRecord(record, to: url)

        let decoded = try JSONDecoder().decode(CPUFunctionalRunRecord.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.formatVersion, CPUFunctionalRunRecord.currentFormatVersion)
        XCTAssertEqual(decoded.runnerName, "CPU6502ConformanceTests")
        XCTAssertEqual(decoded.fixtureID, "functional")
        XCTAssertEqual(decoded.fixtureName, "Functional test")
        XCTAssertEqual(decoded.binaryPath, "/tmp/6502_functional_test.bin")
        XCTAssertEqual(decoded.binarySize, 0x1000)
        XCTAssertEqual(decoded.binaryFNV1A64, "1234567890ABCDEF")
        XCTAssertEqual(decoded.loadAddress, "$0000")
        XCTAssertEqual(decoded.startPC, "$0400")
        XCTAssertEqual(decoded.initialRegisters?.a, "$10")
        XCTAssertEqual(decoded.initialRegisters?.x, "$20")
        XCTAssertEqual(decoded.initialRegisters?.y, "$30")
        XCTAssertEqual(decoded.initialRegisters?.sp, "$FD")
        XCTAssertEqual(decoded.initialRegisters?.p, "$24")
        XCTAssertEqual(decoded.successPC, "$3469")
        XCTAssertEqual(decoded.maxCycles, 100_000_000)
        XCTAssertEqual(decoded.expectedElapsedCycles, 12340)
        XCTAssertEqual(decoded.elapsedCycleTolerance, 2)
        XCTAssertEqual(decoded.elapsedCycleDelta, -2)
        XCTAssertEqual(decoded.passed, false)
        XCTAssertEqual(decoded.jammed, true)
        XCTAssertEqual(decoded.outcome, "cpuJam")
        XCTAssertEqual(decoded.failureCategory, "cpu")
        XCTAssertEqual(decoded.expectedFailureCategory, "cpu")
        XCTAssertEqual(decoded.expectedFailureReasonContains, ["CPU jammed"])
        XCTAssertEqual(decoded.expectedFailureNote, "Known local fixture")
        XCTAssertEqual(decoded.expectationStatus, "expectedFailure")
        XCTAssertEqual(decoded.finalRegisterMismatches, [])
        XCTAssertEqual(decoded.finalMemoryMismatches, [])
        XCTAssertEqual(decoded.finalPC, "$02A3")
        XCTAssertEqual(decoded.finalA, "$10")
        XCTAssertEqual(decoded.finalX, "$20")
        XCTAssertEqual(decoded.finalY, "$30")
        XCTAssertEqual(decoded.finalSP, "$FD")
        XCTAssertEqual(decoded.finalP, "$24")
        XCTAssertEqual(decoded.finalInstructionCycle, 0)
        XCTAssertEqual(decoded.totalCycles, 12345)
        XCTAssertEqual(decoded.elapsedCycles, 12338)
        XCTAssertEqual(decoded.reason, "CPU jammed")
    }

    func testCPUFunctionalManifestRunsFixturesSequentially() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let passURL = directory.appendingPathComponent("pass.bin")
        try Data([0x4C, 0x00, 0x04]).write(to: passURL)
        let jamURL = directory.appendingPathComponent("jam.bin")
        try Data([0x02]).write(to: jamURL)

        let manifest = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "self-loop",
                name: "Synthetic self loop",
                path: passURL.lastPathComponent,
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64,
                initialRegisters: CPUFunctionalRegisterValues(
                    a: "$11",
                    x: "$22",
                    y: "$33",
                    sp: "$F0",
                    p: "$A5"
                ),
                expectedElapsedCycles: 6,
                elapsedCycleTolerance: 0,
                finalRegisters: CPUFunctionalRegisterExpectations(
                    a: CPUFunctionalByteExpectation(value: "$11"),
                    x: CPUFunctionalByteExpectation(value: "$22"),
                    y: CPUFunctionalByteExpectation(value: "$33"),
                    sp: CPUFunctionalByteExpectation(value: "$F0"),
                    p: CPUFunctionalByteExpectation(value: "$A5")
                )
            ),
            CPUFunctionalFixture(
                id: "jam",
                name: "Synthetic KIL",
                path: jamURL.lastPathComponent,
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64,
                expectedFailure: CPUFunctionalExpectedFailure(
                    category: "cpu",
                    reasonContains: ["CPU jammed"],
                    note: "Synthetic expected failure"
                )
            ),
        ])

        let summary = try runCPUFunctionalManifest(manifest, relativeTo: directory)

        XCTAssertEqual(summary.manifestFNV1A64, fnv1a64(canonicalCPUFunctionalManifestData(manifest)))
        XCTAssertEqual(summary.total, 2)
        XCTAssertEqual(summary.passed, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.jammed, 1)
        XCTAssertEqual(summary.timedOut, 0)
        XCTAssertEqual(summary.expectedFailures, 1)
        XCTAssertEqual(summary.unexpectedFailures, 0)
        XCTAssertEqual(summary.expectedFailureDrift, 0)
        XCTAssertEqual(summary.acceptanceFailures, 0)
        XCTAssertEqual(summary.records.map { $0.fixtureID }, ["self-loop", "jam"])
        XCTAssertEqual(summary.records[0].passed, true)
        XCTAssertEqual(summary.records[0].outcome, "passed")
        XCTAssertNil(summary.records[0].failureCategory)
        XCTAssertEqual(summary.records[0].elapsedCycles, 6)
        XCTAssertEqual(summary.records[0].expectedElapsedCycles, 6)
        XCTAssertEqual(summary.records[0].elapsedCycleTolerance, 0)
        XCTAssertEqual(summary.records[0].elapsedCycleDelta, 0)
        XCTAssertEqual(summary.records[0].initialRegisters?.a, "$11")
        XCTAssertEqual(summary.records[0].initialRegisters?.x, "$22")
        XCTAssertEqual(summary.records[0].initialRegisters?.y, "$33")
        XCTAssertEqual(summary.records[0].initialRegisters?.sp, "$F0")
        XCTAssertEqual(summary.records[0].initialRegisters?.p, "$A5")
        XCTAssertEqual(summary.records[0].finalA, "$11")
        XCTAssertEqual(summary.records[0].finalX, "$22")
        XCTAssertEqual(summary.records[0].finalY, "$33")
        XCTAssertEqual(summary.records[0].finalSP, "$F0")
        XCTAssertEqual(summary.records[0].finalP, "$A5")
        XCTAssertEqual(summary.records[0].finalRegisterMismatches, [])
        XCTAssertEqual(summary.records[0].expectationStatus, "passed")
        XCTAssertEqual(summary.records[0].reason, "success self-loop reached")
        XCTAssertEqual(summary.records[1].passed, false)
        XCTAssertEqual(summary.records[1].jammed, true)
        XCTAssertEqual(summary.records[1].outcome, "cpuJam")
        XCTAssertEqual(summary.records[1].failureCategory, "cpu")
        XCTAssertEqual(summary.records[1].expectedFailureCategory, "cpu")
        XCTAssertEqual(summary.records[1].expectedFailureReasonContains, ["CPU jammed"])
        XCTAssertEqual(summary.records[1].expectationStatus, "expectedFailure")
        XCTAssertEqual(summary.records[1].reason, "CPU jammed")
    }

    func testCPUFunctionalManifestReportsUnexpectedFailuresAndDrift() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let passURL = directory.appendingPathComponent("pass.bin")
        try Data([0x4C, 0x00, 0x04]).write(to: passURL)
        let spinURL = directory.appendingPathComponent("spin.bin")
        try Data([0xEA, 0xEA, 0xEA, 0xEA]).write(to: spinURL)

        let manifest = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "drift",
                name: "Expected failure that now passes",
                path: passURL.lastPathComponent,
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64,
                expectedFailure: CPUFunctionalExpectedFailure(
                    category: "cpu",
                    reasonContains: ["CPU jammed"],
                    note: "This should now be reviewed"
                )
            ),
            CPUFunctionalFixture(
                id: "timeout",
                name: "Unexpected timeout",
                path: spinURL.lastPathComponent,
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$5000",
                maxCycles: 8
            ),
        ])

        let summary = try runCPUFunctionalManifest(manifest, relativeTo: directory)

        XCTAssertEqual(summary.manifestFNV1A64.count, 16)
        XCTAssertEqual(summary.total, 2)
        XCTAssertEqual(summary.passed, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.timedOut, 1)
        XCTAssertEqual(summary.expectedFailures, 0)
        XCTAssertEqual(summary.unexpectedFailures, 1)
        XCTAssertEqual(summary.expectedFailureDrift, 1)
        XCTAssertEqual(summary.acceptanceFailures, 2)
        XCTAssertEqual(summary.records[0].expectationStatus, "expectedFailureDrift")
        XCTAssertEqual(summary.records[1].outcome, "timeout")
        XCTAssertEqual(summary.records[1].failureCategory, "timeout")
        XCTAssertEqual(summary.records[1].expectationStatus, "unexpectedFailure")
        XCTAssertTrue(summary.failureSummary.contains("drift"))
        XCTAssertTrue(summary.failureSummary.contains("timeout"))
        XCTAssertEqual(summary.failureDetails.map(\.fixtureID), ["drift", "timeout"])
        XCTAssertEqual(summary.failureDetails.map(\.expectationStatus), ["expectedFailureDrift", "unexpectedFailure"])

        let summaryURL = directory.appendingPathComponent("summary.json")
        try writeCPUFunctionalRunSummary(summary, to: summaryURL)
        let decoded = try JSONDecoder().decode(CPUFunctionalRunSummary.self, from: Data(contentsOf: summaryURL))
        XCTAssertEqual(decoded.manifestFNV1A64, summary.manifestFNV1A64)
        XCTAssertEqual(decoded.acceptanceFailures, 2)
        XCTAssertEqual(decoded.failureDetails.count, 2)
        XCTAssertEqual(decoded.failureDetails[0].fixtureID, "drift")
        XCTAssertEqual(decoded.failureDetails[1].fixtureID, "timeout")
    }

    func testCPUFunctionalManifestReportsTimingMismatch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let passURL = directory.appendingPathComponent("pass.bin")
        try Data([0x4C, 0x00, 0x04]).write(to: passURL)

        let manifest = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "timing",
                name: "Synthetic timing mismatch",
                path: passURL.lastPathComponent,
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64,
                expectedElapsedCycles: 7,
                elapsedCycleTolerance: 0
            ),
        ])

        let summary = try runCPUFunctionalManifest(manifest, relativeTo: directory)

        XCTAssertEqual(summary.total, 1)
        XCTAssertEqual(summary.passed, 0)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.unexpectedFailures, 1)
        XCTAssertEqual(summary.acceptanceFailures, 1)
        XCTAssertEqual(summary.records[0].outcome, "timingMismatch")
        XCTAssertEqual(summary.records[0].failureCategory, "timing")
        XCTAssertEqual(summary.records[0].elapsedCycles, 6)
        XCTAssertEqual(summary.records[0].expectedElapsedCycles, 7)
        XCTAssertEqual(summary.records[0].elapsedCycleTolerance, 0)
        XCTAssertEqual(summary.records[0].elapsedCycleDelta, -1)
        XCTAssertTrue(summary.records[0].reason.contains("expected success self-loop at 7 cycles"))
        XCTAssertEqual(summary.failureDetails[0].outcome, "timingMismatch")
        XCTAssertEqual(summary.failureDetails[0].failureCategory, "timing")
    }

    func testCPUFunctionalManifestReportsFinalRegisterMismatch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let passURL = directory.appendingPathComponent("pass.bin")
        try Data([0xA9, 0x42, 0x4C, 0x02, 0x04]).write(to: passURL)

        let manifest = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "registers",
                name: "Synthetic register mismatch",
                path: passURL.lastPathComponent,
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0402",
                maxCycles: 64,
                finalRegisters: CPUFunctionalRegisterExpectations(
                    a: CPUFunctionalByteExpectation(value: "$41"),
                    x: nil,
                    y: nil,
                    sp: nil,
                    p: CPUFunctionalByteExpectation(value: "$24", mask: "$EF")
                )
            ),
        ])

        let summary = try runCPUFunctionalManifest(manifest, relativeTo: directory)

        XCTAssertEqual(summary.total, 1)
        XCTAssertEqual(summary.passed, 0)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.unexpectedFailures, 1)
        XCTAssertEqual(summary.records[0].outcome, "registerMismatch")
        XCTAssertEqual(summary.records[0].failureCategory, "cpu")
        XCTAssertEqual(summary.records[0].finalA, "$42")
        XCTAssertEqual(summary.records[0].finalRegisterMismatches, ["A expected $41 got $42"])
        XCTAssertTrue(summary.records[0].reason.contains("A expected $41 got $42"))
        XCTAssertEqual(summary.failureDetails[0].outcome, "registerMismatch")
    }

    func testCPUFunctionalManifestReportsFinalMemoryMismatch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let passURL = directory.appendingPathComponent("pass.bin")
        try Data([
            0xA9, 0x42,        // LDA #$42
            0x8D, 0x00, 0x20,  // STA $2000
            0x4C, 0x05, 0x04   // JMP $0405
        ]).write(to: passURL)

        let manifest = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "memory",
                name: "Synthetic memory mismatch",
                path: passURL.lastPathComponent,
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0405",
                maxCycles: 64,
                finalMemory: [
                    CPUFunctionalMemoryExpectation(
                        address: "$2000",
                        value: CPUFunctionalByteExpectation(value: "$41")
                    ),
                ]
            ),
        ])

        let summary = try runCPUFunctionalManifest(manifest, relativeTo: directory)

        XCTAssertEqual(summary.total, 1)
        XCTAssertEqual(summary.passed, 0)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.unexpectedFailures, 1)
        XCTAssertEqual(summary.records[0].outcome, "memoryMismatch")
        XCTAssertEqual(summary.records[0].failureCategory, "ram")
        XCTAssertEqual(summary.records[0].finalMemoryMismatches, ["$2000 expected $41 got $42"])
        XCTAssertTrue(summary.records[0].reason.contains("$2000 expected $41 got $42"))
        XCTAssertEqual(summary.failureDetails[0].outcome, "memoryMismatch")
        XCTAssertEqual(summary.failureDetails[0].finalMemoryMismatches, ["$2000 expected $41 got $42"])
    }

    func testCPUFunctionalManifestAppliesInitialMemoryAndChecksRangeHash() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let passURL = directory.appendingPathComponent("pass.bin")
        try Data([
            0xAD, 0x00, 0x20,  // LDA $2000
            0x8D, 0x01, 0x20,  // STA $2001
            0x4C, 0x06, 0x04   // JMP $0406
        ]).write(to: passURL)

        let expectedRange = Data([0x37, 0x37])
        let manifest = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "memory-range",
                name: "Initial memory and range hash",
                path: passURL.lastPathComponent,
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0406",
                maxCycles: 64,
                initialMemory: [
                    CPUFunctionalMemoryPatch(address: "$2000", value: "$37"),
                ],
                finalMemoryRanges: [
                    CPUFunctionalMemoryRangeExpectation(
                        start: "$2000",
                        length: 2,
                        fnv1a64: fnv1a64(expectedRange)
                    ),
                ]
            ),
        ])

        let summary = try runCPUFunctionalManifest(manifest, relativeTo: directory)

        XCTAssertEqual(summary.total, 1)
        XCTAssertEqual(summary.passed, 1)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.records[0].finalMemoryMismatches, [])
        XCTAssertEqual(summary.records[0].outcome, "passed")
    }

    func testCPUFunctionalManifestReportsFinalMemoryRangeHashMismatch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let passURL = directory.appendingPathComponent("pass.bin")
        try Data([0x4C, 0x00, 0x04]).write(to: passURL)

        let manifest = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "range-mismatch",
                name: "Final range mismatch",
                path: passURL.lastPathComponent,
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64,
                finalMemoryRanges: [
                    CPUFunctionalMemoryRangeExpectation(
                        start: "$2000",
                        length: 2,
                        fnv1a64: "0000000000000000"
                    ),
                ]
            ),
        ])

        let summary = try runCPUFunctionalManifest(manifest, relativeTo: directory)

        XCTAssertEqual(summary.total, 1)
        XCTAssertEqual(summary.passed, 0)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.records[0].outcome, "memoryMismatch")
        XCTAssertEqual(summary.records[0].failureCategory, "ram")
        XCTAssertTrue(summary.records[0].finalMemoryMismatches[0].contains("$2000..$2001 expected FNV1A64 0000000000000000"))
    }

    func testCPUFunctionalManifestRejectsDuplicateFixtureIDs() throws {
        let manifest = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "duplicate",
                name: "First",
                path: "first.bin",
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64
            ),
            CPUFunctionalFixture(
                id: "duplicate",
                name: "Second",
                path: "second.bin",
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64
            ),
        ])

        XCTAssertThrowsError(try runCPUFunctionalManifest(manifest, relativeTo: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("duplicate fixture id duplicate"))
        }
    }

    func testCPUFunctionalManifestRejectsNonPositiveCycleLimits() throws {
        let manifest = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "bad-limit",
                name: "Bad limit",
                path: "bad.bin",
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 0
            ),
        ])

        XCTAssertThrowsError(try runCPUFunctionalManifest(manifest, relativeTo: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("maxCycles must be positive"))
        }
    }

    func testCPUFunctionalManifestRejectsNegativeTimingExpectations() throws {
        let negativeExpected = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "negative-expected",
                name: "Negative expected cycle",
                path: "bad.bin",
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64,
                expectedElapsedCycles: -1
            ),
        ])

        XCTAssertThrowsError(try runCPUFunctionalManifest(negativeExpected, relativeTo: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("expectedElapsedCycles must be non-negative"))
        }

        let negativeTolerance = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "negative-tolerance",
                name: "Negative tolerance",
                path: "bad.bin",
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64,
                expectedElapsedCycles: 6,
                elapsedCycleTolerance: -1
            ),
        ])

        XCTAssertThrowsError(try runCPUFunctionalManifest(negativeTolerance, relativeTo: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("elapsedCycleTolerance must be non-negative"))
        }
    }

    func testCPUFunctionalManifestRejectsInvalidFinalRegisterExpectations() throws {
        let manifest = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "bad-register",
                name: "Bad register",
                path: "bad.bin",
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64,
                finalRegisters: CPUFunctionalRegisterExpectations(
                    a: CPUFunctionalByteExpectation(value: "$123"),
                    x: nil,
                    y: nil,
                    sp: nil,
                    p: nil
                )
            ),
        ])

        XCTAssertThrowsError(try runCPUFunctionalManifest(manifest, relativeTo: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("finalRegisters.A"))
        }
    }

    func testCPUFunctionalManifestRejectsInvalidInitialRegisterValues() throws {
        let manifest = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "bad-initial-register",
                name: "Bad initial register",
                path: "bad.bin",
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64,
                initialRegisters: CPUFunctionalRegisterValues(a: "$123")
            ),
        ])

        XCTAssertThrowsError(try runCPUFunctionalManifest(manifest, relativeTo: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("initialRegisters.A"))
        }
    }

    func testCPUFunctionalManifestDecodesMinimalFixtureWithDefaultCollections() throws {
        let json = """
        {
          "fixtures": [
            {
              "id": "minimal",
              "path": "minimal.bin",
              "successPC": "$0400"
            }
          ]
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(CPUFunctionalManifest.self, from: json)

        XCTAssertEqual(manifest.fixtures.count, 1)
        XCTAssertEqual(manifest.fixtures[0].id, "minimal")
        XCTAssertEqual(manifest.fixtures[0].path, "minimal.bin")
        XCTAssertNil(manifest.fixtures[0].initialRegisters)
        XCTAssertEqual(manifest.fixtures[0].initialMemory, [])
        XCTAssertNil(manifest.fixtures[0].finalRegisters)
        XCTAssertEqual(manifest.fixtures[0].finalMemory, [])
        XCTAssertEqual(manifest.fixtures[0].finalMemoryRanges, [])
    }

    func testCPUFunctionalManifestRejectsInvalidFinalMemoryExpectations() throws {
        let badAddress = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "bad-memory-address",
                name: "Bad memory address",
                path: "bad.bin",
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64,
                finalMemory: [
                    CPUFunctionalMemoryExpectation(
                        address: "$10000",
                        value: CPUFunctionalByteExpectation(value: "$00")
                    ),
                ]
            ),
        ])

        XCTAssertThrowsError(try runCPUFunctionalManifest(badAddress, relativeTo: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("finalMemory[0].address"))
        }

        let badValue = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "bad-memory-value",
                name: "Bad memory value",
                path: "bad.bin",
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64,
                finalMemory: [
                    CPUFunctionalMemoryExpectation(
                        address: "$2000",
                        value: CPUFunctionalByteExpectation(value: "$123")
                    ),
                ]
            ),
        ])

        XCTAssertThrowsError(try runCPUFunctionalManifest(badValue, relativeTo: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("finalMemory[0].value"))
        }
    }

    func testCPUFunctionalManifestRejectsInvalidInitialMemoryAndRangeExpectations() throws {
        let badPatch = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "bad-patch",
                name: "Bad patch",
                path: "bad.bin",
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64,
                initialMemory: [
                    CPUFunctionalMemoryPatch(address: "$2000", value: "$123"),
                ]
            ),
        ])

        XCTAssertThrowsError(try runCPUFunctionalManifest(badPatch, relativeTo: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("initialMemory[0].value"))
        }

        let badRange = CPUFunctionalManifest(fixtures: [
            CPUFunctionalFixture(
                id: "bad-range",
                name: "Bad range",
                path: "bad.bin",
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64,
                finalMemoryRanges: [
                    CPUFunctionalMemoryRangeExpectation(
                        start: "$FFFF",
                        length: 2,
                        fnv1a64: "0000000000000000"
                    ),
                ]
            ),
        ])

        XCTAssertThrowsError(try runCPUFunctionalManifest(badRange, relativeTo: nil)) { error in
            XCTAssertTrue(String(describing: error).contains("finalMemoryRanges[0] exceeds 64K RAM"))
        }
    }



    func testOptInFunctionalBinaryReachesSuccessSelfLoop() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let binaryPath = environment["SWIFT64_CPU_FUNCTIONAL_TEST_PATH"], !binaryPath.isEmpty else {
            throw XCTSkip("Set SWIFT64_CPU_FUNCTIONAL_TEST_PATH to run a local public 6502 functional-test binary.")
        }
        guard let successPC = UInt16(hexEnvironment: environment["SWIFT64_CPU_FUNCTIONAL_SUCCESS_PC"]) else {
            throw XCTSkip("Set SWIFT64_CPU_FUNCTIONAL_SUCCESS_PC to the binary's success self-loop address.")
        }

        let loadAddress = UInt16(hexEnvironment: environment["SWIFT64_CPU_FUNCTIONAL_LOAD_ADDRESS"]) ?? 0x0000
        let startPC = UInt16(hexEnvironment: environment["SWIFT64_CPU_FUNCTIONAL_START_PC"])
        let maxCycles = Int(environment["SWIFT64_CPU_FUNCTIONAL_MAX_CYCLES"] ?? "") ?? 100_000_000
        let expectedElapsedCycles = Int(environment["SWIFT64_CPU_FUNCTIONAL_EXPECTED_ELAPSED_CYCLES"] ?? "")
        let elapsedCycleTolerance = Int(environment["SWIFT64_CPU_FUNCTIONAL_ELAPSED_CYCLE_TOLERANCE"] ?? "") ?? 0
        let initialRegisters = try cpuFunctionalInitialRegisters(from: environment)
        let resultURL = environment["SWIFT64_CPU_FUNCTIONAL_RESULT_JSON"].flatMap { path -> URL? in
            path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
        let binaryURL = URL(fileURLWithPath: binaryPath)
        let data = try Data(contentsOf: binaryURL)

        XCTAssertLessThanOrEqual(Int(loadAddress) + data.count, 0x10000, "Functional binary does not fit in 64K RAM at requested load address")

        let record = runCPUFunctionalBinary(
            fixtureID: nil,
            fixtureName: nil,
            binaryPath: binaryPath,
            data: data,
            loadAddress: loadAddress,
            startPC: startPC,
            successPC: successPC,
            maxCycles: maxCycles,
            initialRegisters: initialRegisters,
            expectedElapsedCycles: expectedElapsedCycles,
            elapsedCycleTolerance: elapsedCycleTolerance,
            initialMemory: [],
            finalRegisters: nil,
            finalMemory: [],
        finalMemoryRanges: [],
        expectedFailure: nil
        )
        try writeCPUFunctionalRunRecord(record, to: resultURL)

        XCTAssertTrue(record.passed, "\(record.reason) at PC=\(record.finalPC) after \(record.elapsedCycles) cycles")
    }

    func testOptInFunctionalManifestRunsSequentially() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let manifestPath = environment["SWIFT64_CPU_FUNCTIONAL_MANIFEST_JSON"], !manifestPath.isEmpty else {
            throw XCTSkip("Set SWIFT64_CPU_FUNCTIONAL_MANIFEST_JSON to run a local public 6502 functional-test manifest.")
        }

        let manifestURL = URL(fileURLWithPath: manifestPath)
        let manifest = try JSONDecoder().decode(CPUFunctionalManifest.self, from: Data(contentsOf: manifestURL))
        let summary = try runCPUFunctionalManifest(manifest, relativeTo: manifestURL.deletingLastPathComponent())
        let summaryURL = environment["SWIFT64_CPU_FUNCTIONAL_SUMMARY_JSON"].flatMap { path -> URL? in
            path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
        try writeCPUFunctionalRunSummary(summary, to: summaryURL)

        XCTAssertEqual(summary.acceptanceFailures, 0, summary.failureSummary)
    }
}

private struct CPUFunctionalManifest: Codable, Equatable {
    let fixtures: [CPUFunctionalFixture]
}

private struct CPUFunctionalExpectedFailure: Codable, Equatable {
    let category: String
    let reasonContains: [String]
    let note: String?

    private enum CodingKeys: String, CodingKey {
        case category
        case reasonContains
        case reason
        case note
    }

    init(category: String, reasonContains: [String] = [], note: String? = nil) {
        self.category = category
        self.reasonContains = reasonContains
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decode(String.self, forKey: .category)
        if let values = try? container.decode([String].self, forKey: .reasonContains) {
            reasonContains = values
        } else if let value = try? container.decode(String.self, forKey: .reasonContains) {
            reasonContains = [value]
        } else if let value = try? container.decode(String.self, forKey: .reason) {
            reasonContains = [value]
        } else {
            reasonContains = []
        }
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(category, forKey: .category)
        try container.encode(reasonContains, forKey: .reasonContains)
        try container.encodeIfPresent(note, forKey: .note)
    }
}

private struct CPUFunctionalFixture: Codable, Equatable {
    let id: String?
    let name: String?
    let path: String
    let loadAddress: String?
    let startPC: String?
    let successPC: String
    let maxCycles: Int?
    let initialRegisters: CPUFunctionalRegisterValues?
    let expectedElapsedCycles: Int?
    let elapsedCycleTolerance: Int?
    let initialMemory: [CPUFunctionalMemoryPatch]
    let finalRegisters: CPUFunctionalRegisterExpectations?
    let finalMemory: [CPUFunctionalMemoryExpectation]
    let finalMemoryRanges: [CPUFunctionalMemoryRangeExpectation]
    let expectedFailure: CPUFunctionalExpectedFailure?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case loadAddress
        case startPC
        case successPC
        case maxCycles
        case initialRegisters
        case expectedElapsedCycles
        case elapsedCycleTolerance
        case initialMemory
        case finalRegisters
        case finalMemory
        case finalMemoryRanges
        case expectedFailure
    }

    init(
        id: String?,
        name: String?,
        path: String,
        loadAddress: String?,
        startPC: String?,
        successPC: String,
        maxCycles: Int?,
        initialRegisters: CPUFunctionalRegisterValues? = nil,
        expectedElapsedCycles: Int? = nil,
        elapsedCycleTolerance: Int? = nil,
        initialMemory: [CPUFunctionalMemoryPatch] = [],
        finalRegisters: CPUFunctionalRegisterExpectations? = nil,
        finalMemory: [CPUFunctionalMemoryExpectation] = [],
        finalMemoryRanges: [CPUFunctionalMemoryRangeExpectation] = [],
        expectedFailure: CPUFunctionalExpectedFailure? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.loadAddress = loadAddress
        self.startPC = startPC
        self.successPC = successPC
        self.maxCycles = maxCycles
        self.initialRegisters = initialRegisters
        self.expectedElapsedCycles = expectedElapsedCycles
        self.elapsedCycleTolerance = elapsedCycleTolerance
        self.initialMemory = initialMemory
        self.finalRegisters = finalRegisters
        self.finalMemory = finalMemory
        self.finalMemoryRanges = finalMemoryRanges
        self.expectedFailure = expectedFailure
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        loadAddress = try container.decodeIfPresent(String.self, forKey: .loadAddress)
        startPC = try container.decodeIfPresent(String.self, forKey: .startPC)
        successPC = try container.decode(String.self, forKey: .successPC)
        maxCycles = try container.decodeIfPresent(Int.self, forKey: .maxCycles)
        initialRegisters = try container.decodeIfPresent(CPUFunctionalRegisterValues.self, forKey: .initialRegisters)
        expectedElapsedCycles = try container.decodeIfPresent(Int.self, forKey: .expectedElapsedCycles)
        elapsedCycleTolerance = try container.decodeIfPresent(Int.self, forKey: .elapsedCycleTolerance)
        initialMemory = try container.decodeIfPresent([CPUFunctionalMemoryPatch].self, forKey: .initialMemory) ?? []
        finalRegisters = try container.decodeIfPresent(CPUFunctionalRegisterExpectations.self, forKey: .finalRegisters)
        finalMemory = try container.decodeIfPresent([CPUFunctionalMemoryExpectation].self, forKey: .finalMemory) ?? []
        finalMemoryRanges = try container.decodeIfPresent([CPUFunctionalMemoryRangeExpectation].self, forKey: .finalMemoryRanges) ?? []
        expectedFailure = try container.decodeIfPresent(CPUFunctionalExpectedFailure.self, forKey: .expectedFailure)
    }

    func binaryURL(relativeTo baseURL: URL?) -> URL {
        if (path as NSString).isAbsolutePath {
            return URL(fileURLWithPath: path)
        }
        return (baseURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .appendingPathComponent(path)
    }
}

private struct CPUFunctionalRegisterValues: Codable, Equatable {
    let a: String?
    let x: String?
    let y: String?
    let sp: String?
    let p: String?

    init(
        a: String? = nil,
        x: String? = nil,
        y: String? = nil,
        sp: String? = nil,
        p: String? = nil
    ) {
        self.a = a
        self.x = x
        self.y = y
        self.sp = sp
        self.p = p
    }
}

private struct CPUFunctionalRegisterExpectations: Codable, Equatable {
    let a: CPUFunctionalByteExpectation?
    let x: CPUFunctionalByteExpectation?
    let y: CPUFunctionalByteExpectation?
    let sp: CPUFunctionalByteExpectation?
    let p: CPUFunctionalByteExpectation?
}

private struct CPUFunctionalByteExpectation: Codable, Equatable {
    let value: String
    let mask: String?

    private enum CodingKeys: String, CodingKey {
        case value
        case mask
    }

    init(value: String, mask: String? = nil) {
        self.value = value
        self.mask = mask
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            if let stringValue = try? container.decode(String.self, forKey: .value) {
                value = stringValue
            } else if let intValue = try? container.decode(Int.self, forKey: .value) {
                value = "$" + String(format: "%02X", intValue & 0xFF)
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "Expected byte value as string or integer"
                )
            }

            if let stringMask = try? container.decode(String.self, forKey: .mask) {
                mask = stringMask
            } else if let intMask = try? container.decode(Int.self, forKey: .mask) {
                mask = "$" + String(format: "%02X", intMask & 0xFF)
            } else {
                mask = nil
            }
            return
        }

        let single = try decoder.singleValueContainer()
        if let stringValue = try? single.decode(String.self) {
            value = stringValue
            mask = nil
        } else {
            let intValue = try single.decode(Int.self)
            value = "$" + String(format: "%02X", intValue & 0xFF)
            mask = nil
        }
    }
}

private struct CPUFunctionalMemoryPatch: Codable, Equatable {
    let address: String
    let value: String
}

private struct CPUFunctionalMemoryExpectation: Codable, Equatable {
    let address: String
    let value: CPUFunctionalByteExpectation

    init(address: String, value: CPUFunctionalByteExpectation) {
        self.address = address
        self.value = value
    }
}

private struct CPUFunctionalMemoryRangeExpectation: Codable, Equatable {
    let start: String
    let length: Int
    let fnv1a64: String
}

private struct CPUFunctionalRunRecord: Codable, Equatable {
    static let currentFormatVersion = 1

    var formatVersion: Int = CPUFunctionalRunRecord.currentFormatVersion
    var runnerName: String = "CPU6502ConformanceTests"
    let fixtureID: String?
    let fixtureName: String?
    let binaryPath: String
    let binarySize: Int
    let binaryFNV1A64: String
    let loadAddress: String
    let startPC: String?
    var initialRegisters: CPUFunctionalRegisterValues? = nil
    let successPC: String
    let maxCycles: Int
    let expectedElapsedCycles: Int?
    let elapsedCycleTolerance: Int?
    let elapsedCycleDelta: Int?
    let passed: Bool
    let jammed: Bool
    let outcome: String
    let failureCategory: String?
    let expectedFailureCategory: String?
    let expectedFailureReasonContains: [String]
    let expectedFailureNote: String?
    let expectationStatus: String
    let finalRegisterMismatches: [String]
    let finalMemoryMismatches: [String]
    let finalPC: String
    let finalA: String
    let finalX: String
    let finalY: String
    let finalSP: String
    let finalP: String
    let finalInstructionCycle: Int
    let totalCycles: UInt64
    let elapsedCycles: Int
    let reason: String
}

private struct CPUFunctionalRunSummary: Codable, Equatable {
    var formatVersion: Int = 1
    var runnerName: String = "CPU6502ConformanceTests"
    var resultRecordFormatVersion: Int = CPUFunctionalRunRecord.currentFormatVersion
    let manifestFNV1A64: String
    let total: Int
    let passed: Int
    let failed: Int
    let jammed: Int
    let timedOut: Int
    let expectedFailures: Int
    let unexpectedFailures: Int
    let expectedFailureDrift: Int
    let acceptanceFailures: Int
    let totalElapsedCycles: Int
    let failureDetails: [CPUFunctionalFailureDetail]
    let records: [CPUFunctionalRunRecord]

    var failureSummary: String {
        guard !failureDetails.isEmpty else {
            return "No unexpected CPU functional failures."
        }
        return failureDetails.map { detail in
            let idText = detail.fixtureID.map { "\($0) " } ?? ""
            return "\(idText)\(detail.binaryPath) status=\(detail.expectationStatus) category=\(detail.failureCategory ?? "none") pc=\(detail.finalPC) cycles=\(detail.elapsedCycles) reason=\(detail.reason)"
        }.joined(separator: "\n")
    }
}

private struct CPUFunctionalFailureDetail: Codable, Equatable {
    let fixtureID: String?
    let fixtureName: String?
    let binaryPath: String
    let outcome: String
    let failureCategory: String?
    let expectationStatus: String
    let finalPC: String
    let elapsedCycles: Int
    let reason: String
    let expectedFailureCategory: String?
    let expectedFailureNote: String?
    let finalRegisterMismatches: [String]
    let finalMemoryMismatches: [String]

    init(record: CPUFunctionalRunRecord) {
        fixtureID = record.fixtureID
        fixtureName = record.fixtureName
        binaryPath = record.binaryPath
        outcome = record.outcome
        failureCategory = record.failureCategory
        expectationStatus = record.expectationStatus
        finalPC = record.finalPC
        elapsedCycles = record.elapsedCycles
        reason = record.reason
        expectedFailureCategory = record.expectedFailureCategory
        expectedFailureNote = record.expectedFailureNote
        finalRegisterMismatches = record.finalRegisterMismatches
        finalMemoryMismatches = record.finalMemoryMismatches
    }
}

private func runCPUFunctionalManifest(
    _ manifest: CPUFunctionalManifest,
    relativeTo baseURL: URL?
) throws -> CPUFunctionalRunSummary {
    try validateCPUFunctionalManifest(manifest)
    let manifestFNV1A64 = fnv1a64(canonicalCPUFunctionalManifestData(manifest))

    var records: [CPUFunctionalRunRecord] = []
    records.reserveCapacity(manifest.fixtures.count)

    for fixture in manifest.fixtures {
        let binaryURL = fixture.binaryURL(relativeTo: baseURL)
        let data = try Data(contentsOf: binaryURL)
        let loadAddress = try parseHex16(fixture.loadAddress, default: 0x0000, field: "loadAddress")
        let startPC = try parseOptionalHex16(fixture.startPC, field: "startPC")
        let successPC = try parseRequiredHex16(fixture.successPC, field: "successPC")
        let maxCycles = fixture.maxCycles ?? 100_000_000
        let elapsedCycleTolerance = fixture.elapsedCycleTolerance ?? 0

        guard Int(loadAddress) + data.count <= 0x10000 else {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) does not fit in 64K RAM at loadAddress \(hex16(loadAddress))")
        }

        records.append(runCPUFunctionalBinary(
            fixtureID: fixture.id,
            fixtureName: fixture.name,
            binaryPath: binaryURL.path,
            data: data,
            loadAddress: loadAddress,
            startPC: startPC,
            successPC: successPC,
            maxCycles: maxCycles,
            initialRegisters: fixture.initialRegisters,
            expectedElapsedCycles: fixture.expectedElapsedCycles,
            elapsedCycleTolerance: elapsedCycleTolerance,
            initialMemory: fixture.initialMemory,
            finalRegisters: fixture.finalRegisters,
            finalMemory: fixture.finalMemory,
            finalMemoryRanges: fixture.finalMemoryRanges,
            expectedFailure: fixture.expectedFailure
        ))
    }

    let failureDetails = records
        .filter { $0.expectationStatus == "unexpectedFailure" || $0.expectationStatus == "expectedFailureDrift" }
        .map(CPUFunctionalFailureDetail.init)

    return CPUFunctionalRunSummary(
        manifestFNV1A64: manifestFNV1A64,
        total: records.count,
        passed: records.filter(\.passed).count,
        failed: records.filter { !$0.passed }.count,
        jammed: records.filter(\.jammed).count,
        timedOut: records.filter { $0.outcome == "timeout" }.count,
        expectedFailures: records.filter { $0.expectationStatus == "expectedFailure" }.count,
        unexpectedFailures: records.filter { $0.expectationStatus == "unexpectedFailure" }.count,
        expectedFailureDrift: records.filter { $0.expectationStatus == "expectedFailureDrift" }.count,
        acceptanceFailures: failureDetails.count,
        totalElapsedCycles: records.reduce(0) { $0 + $1.elapsedCycles },
        failureDetails: failureDetails,
        records: records
    )
}

private func canonicalCPUFunctionalManifestData(_ manifest: CPUFunctionalManifest) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(manifest)) ?? Data()
}

private func validateCPUFunctionalManifest(_ manifest: CPUFunctionalManifest) throws {
    var seenIDs: Set<String> = []
    for fixture in manifest.fixtures {
        if let id = fixture.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            guard seenIDs.insert(id).inserted else {
                throw CPUFunctionalManifestError("duplicate fixture id \(id)")
            }
        }

        if let maxCycles = fixture.maxCycles, maxCycles <= 0 {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) maxCycles must be positive")
        }

        if let expectedElapsedCycles = fixture.expectedElapsedCycles, expectedElapsedCycles < 0 {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) expectedElapsedCycles must be non-negative")
        }

        if let elapsedCycleTolerance = fixture.elapsedCycleTolerance, elapsedCycleTolerance < 0 {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) elapsedCycleTolerance must be non-negative")
        }

        try validateCPUFunctionalInitialMemory(fixture.initialMemory, fixture: fixture)
        try validateCPUFunctionalInitialRegisters(fixture.initialRegisters, fixture: fixture)
        try validateCPUFunctionalRegisterExpectations(fixture.finalRegisters, fixture: fixture)
        try validateCPUFunctionalMemoryExpectations(fixture.finalMemory, fixture: fixture)
        try validateCPUFunctionalMemoryRangeExpectations(fixture.finalMemoryRanges, fixture: fixture)
    }
}

private func runCPUFunctionalBinary(
    fixtureID: String?,
    fixtureName: String?,
    binaryPath: String,
    data: Data,
    loadAddress: UInt16,
    startPC: UInt16?,
    successPC: UInt16,
    maxCycles: Int,
    initialRegisters: CPUFunctionalRegisterValues?,
    expectedElapsedCycles: Int?,
    elapsedCycleTolerance: Int,
    initialMemory: [CPUFunctionalMemoryPatch],
    finalRegisters: CPUFunctionalRegisterExpectations?,
    finalMemory: [CPUFunctionalMemoryExpectation],
    finalMemoryRanges: [CPUFunctionalMemoryRangeExpectation],
    expectedFailure: CPUFunctionalExpectedFailure?
) -> CPUFunctionalRunRecord {
    let bus = ConformanceRAMBus()
    bus.loadBinary(data, at: loadAddress)
    applyCPUFunctionalInitialMemory(initialMemory, to: bus)
    let cpu = CPU6502(bus: bus)
    if let startPC {
        cpu.pc = startPC
        cpu.sp = 0xFD
        cpu.p = Flags.unused | Flags.interrupt
    } else {
        cpu.powerOn()
    }
    applyCPUFunctionalInitialRegisters(initialRegisters, to: cpu)

    var previousPC = cpu.pc
    var samePCCount = 0
    for cycle in 0..<maxCycles {
        _ = cpu.tick()

        if cpu.jammed {
            return cpuFunctionalRunRecord(
                fixtureID: fixtureID,
                fixtureName: fixtureName,
                binaryPath: binaryPath,
                data: data,
                loadAddress: loadAddress,
                startPC: startPC,
                successPC: successPC,
                maxCycles: maxCycles,
                initialRegisters: initialRegisters,
                expectedElapsedCycles: expectedElapsedCycles,
                elapsedCycleTolerance: elapsedCycleTolerance,
                finalRegisterMismatches: [],
                finalMemoryMismatches: [],
                passed: false,
                cpu: cpu,
                elapsedCycles: cycle + 1,
                outcome: "cpuJam",
                failureCategory: "cpu",
                expectedFailure: expectedFailure,
                reason: "CPU jammed"
            )
        }

        if cpu.cycle == 0 {
            if cpu.pc == previousPC {
                samePCCount += 1
            } else {
                previousPC = cpu.pc
                samePCCount = 0
            }

            if cpu.pc == successPC && samePCCount >= 2 {
                let elapsedCycles = cycle + 1
                if let timingFailure = cpuFunctionalTimingFailure(
                    elapsedCycles: elapsedCycles,
                    expectedElapsedCycles: expectedElapsedCycles,
                    elapsedCycleTolerance: elapsedCycleTolerance
                ) {
                    return cpuFunctionalRunRecord(
                        fixtureID: fixtureID,
                        fixtureName: fixtureName,
                        binaryPath: binaryPath,
                        data: data,
                        loadAddress: loadAddress,
                        startPC: startPC,
                        successPC: successPC,
                        maxCycles: maxCycles,
                        initialRegisters: initialRegisters,
                        expectedElapsedCycles: expectedElapsedCycles,
                        elapsedCycleTolerance: elapsedCycleTolerance,
                        finalRegisterMismatches: [],
                        finalMemoryMismatches: [],
                        passed: false,
                        cpu: cpu,
                        elapsedCycles: elapsedCycles,
                        outcome: "timingMismatch",
                        failureCategory: "timing",
                        expectedFailure: expectedFailure,
                        reason: timingFailure
                    )
                }

                let registerMismatches = cpuFunctionalRegisterMismatches(finalRegisters, cpu: cpu)
                if !registerMismatches.isEmpty {
                    return cpuFunctionalRunRecord(
                        fixtureID: fixtureID,
                        fixtureName: fixtureName,
                        binaryPath: binaryPath,
                        data: data,
                        loadAddress: loadAddress,
                        startPC: startPC,
                        successPC: successPC,
                        maxCycles: maxCycles,
                        initialRegisters: initialRegisters,
                        expectedElapsedCycles: expectedElapsedCycles,
                        elapsedCycleTolerance: elapsedCycleTolerance,
                        finalRegisterMismatches: registerMismatches,
                        finalMemoryMismatches: [],
                        passed: false,
                        cpu: cpu,
                        elapsedCycles: elapsedCycles,
                        outcome: "registerMismatch",
                        failureCategory: "cpu",
                        expectedFailure: expectedFailure,
                        reason: "final register mismatch: \(registerMismatches.joined(separator: "; "))"
                    )
                }

                let memoryMismatches = cpuFunctionalMemoryMismatches(finalMemory, bus: bus)
                    + cpuFunctionalMemoryRangeMismatches(finalMemoryRanges, bus: bus)
                if !memoryMismatches.isEmpty {
                    return cpuFunctionalRunRecord(
                        fixtureID: fixtureID,
                        fixtureName: fixtureName,
                        binaryPath: binaryPath,
                        data: data,
                        loadAddress: loadAddress,
                        startPC: startPC,
                        successPC: successPC,
                        maxCycles: maxCycles,
                        initialRegisters: initialRegisters,
                        expectedElapsedCycles: expectedElapsedCycles,
                        elapsedCycleTolerance: elapsedCycleTolerance,
                        finalRegisterMismatches: [],
                        finalMemoryMismatches: memoryMismatches,
                        passed: false,
                        cpu: cpu,
                        elapsedCycles: elapsedCycles,
                        outcome: "memoryMismatch",
                        failureCategory: "ram",
                        expectedFailure: expectedFailure,
                        reason: "final memory mismatch: \(memoryMismatches.joined(separator: "; "))"
                    )
                }

                return cpuFunctionalRunRecord(
                    fixtureID: fixtureID,
                    fixtureName: fixtureName,
                    binaryPath: binaryPath,
                    data: data,
                    loadAddress: loadAddress,
                    startPC: startPC,
                    successPC: successPC,
                    maxCycles: maxCycles,
                    initialRegisters: initialRegisters,
                    expectedElapsedCycles: expectedElapsedCycles,
                    elapsedCycleTolerance: elapsedCycleTolerance,
                    finalRegisterMismatches: [],
                    finalMemoryMismatches: [],
                    passed: true,
                    cpu: cpu,
                    elapsedCycles: elapsedCycles,
                    outcome: "passed",
                    failureCategory: nil,
                    expectedFailure: expectedFailure,
                    reason: "success self-loop reached"
                )
            }
        }
    }

    return cpuFunctionalRunRecord(
        fixtureID: fixtureID,
        fixtureName: fixtureName,
        binaryPath: binaryPath,
        data: data,
        loadAddress: loadAddress,
        startPC: startPC,
        successPC: successPC,
        maxCycles: maxCycles,
        initialRegisters: initialRegisters,
        expectedElapsedCycles: expectedElapsedCycles,
        elapsedCycleTolerance: elapsedCycleTolerance,
        finalRegisterMismatches: [],
        finalMemoryMismatches: [],
        passed: false,
        cpu: cpu,
        elapsedCycles: maxCycles,
        outcome: "timeout",
        failureCategory: "timeout",
        expectedFailure: expectedFailure,
        reason: "success self-loop not reached"
    )
}

private func cpuFunctionalRunRecord(
    fixtureID: String?,
    fixtureName: String?,
    binaryPath: String,
    data: Data,
    loadAddress: UInt16,
    startPC: UInt16?,
    successPC: UInt16,
    maxCycles: Int,
    initialRegisters: CPUFunctionalRegisterValues?,
    expectedElapsedCycles: Int?,
    elapsedCycleTolerance: Int,
    finalRegisterMismatches: [String],
    finalMemoryMismatches: [String],
    passed: Bool,
    cpu: CPU6502,
    elapsedCycles: Int,
    outcome: String,
    failureCategory: String?,
    expectedFailure: CPUFunctionalExpectedFailure?,
    reason: String
) -> CPUFunctionalRunRecord {
    let expectationStatus = cpuFunctionalExpectationStatus(
        passed: passed,
        failureCategory: failureCategory,
        reason: reason,
        expectedFailure: expectedFailure
    )
    return CPUFunctionalRunRecord(
        fixtureID: fixtureID,
        fixtureName: fixtureName,
        binaryPath: binaryPath,
        binarySize: data.count,
        binaryFNV1A64: fnv1a64(data),
        loadAddress: hex16(loadAddress),
        startPC: startPC.map(hex16),
        initialRegisters: initialRegisters,
        successPC: hex16(successPC),
        maxCycles: maxCycles,
        expectedElapsedCycles: expectedElapsedCycles,
        elapsedCycleTolerance: expectedElapsedCycles == nil ? nil : elapsedCycleTolerance,
        elapsedCycleDelta: expectedElapsedCycles.map { elapsedCycles - $0 },
        passed: passed,
        jammed: cpu.jammed,
        outcome: outcome,
        failureCategory: failureCategory,
        expectedFailureCategory: expectedFailure?.category,
        expectedFailureReasonContains: expectedFailure?.reasonContains ?? [],
        expectedFailureNote: expectedFailure?.note,
        expectationStatus: expectationStatus,
        finalRegisterMismatches: finalRegisterMismatches,
        finalMemoryMismatches: finalMemoryMismatches,
        finalPC: hex16(cpu.pc),
        finalA: hex8(cpu.a),
        finalX: hex8(cpu.x),
        finalY: hex8(cpu.y),
        finalSP: hex8(cpu.sp),
        finalP: hex8(cpu.p),
        finalInstructionCycle: cpu.cycle,
        totalCycles: cpu.totalCycles,
        elapsedCycles: elapsedCycles,
        reason: reason
    )
}

private func cpuFunctionalExpectationStatus(
    passed: Bool,
    failureCategory: String?,
    reason: String,
    expectedFailure: CPUFunctionalExpectedFailure?
) -> String {
    guard let expectedFailure else {
        return passed ? "passed" : "unexpectedFailure"
    }
    if passed {
        return "expectedFailureDrift"
    }
    guard expectedFailure.category == failureCategory else {
        return "unexpectedFailure"
    }
    let reasonMatches = expectedFailure.reasonContains.allSatisfy { reason.contains($0) }
    return reasonMatches ? "expectedFailure" : "unexpectedFailure"
}

private func cpuFunctionalTimingFailure(
    elapsedCycles: Int,
    expectedElapsedCycles: Int?,
    elapsedCycleTolerance: Int
) -> String? {
    guard let expectedElapsedCycles else { return nil }
    let delta = elapsedCycles - expectedElapsedCycles
    guard abs(delta) > elapsedCycleTolerance else { return nil }
    return "expected success self-loop at \(expectedElapsedCycles) cycles +/- \(elapsedCycleTolerance), reached at \(elapsedCycles) cycles"
}

private func validateCPUFunctionalInitialRegisters(
    _ registers: CPUFunctionalRegisterValues?,
    fixture: CPUFunctionalFixture
) throws {
    guard let registers else { return }
    for (name, value) in cpuFunctionalInitialRegisterPairs(registers) {
        guard UInt8(hexString: value) != nil else {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) initialRegisters.\(name) has invalid value \(value)")
        }
    }
}

private func applyCPUFunctionalInitialRegisters(
    _ registers: CPUFunctionalRegisterValues?,
    to cpu: CPU6502
) {
    guard let registers else { return }
    if let value = registers.a.flatMap(UInt8.init(hexString:)) {
        cpu.a = value
    }
    if let value = registers.x.flatMap(UInt8.init(hexString:)) {
        cpu.x = value
    }
    if let value = registers.y.flatMap(UInt8.init(hexString:)) {
        cpu.y = value
    }
    if let value = registers.sp.flatMap(UInt8.init(hexString:)) {
        cpu.sp = value
    }
    if let value = registers.p.flatMap(UInt8.init(hexString:)) {
        cpu.p = value
    }
}

private func cpuFunctionalInitialRegisters(from environment: [String: String]) throws -> CPUFunctionalRegisterValues? {
    let a = try cpuFunctionalInitialRegisterEnvironmentValue(environment, key: "SWIFT64_CPU_FUNCTIONAL_INITIAL_A")
    let x = try cpuFunctionalInitialRegisterEnvironmentValue(environment, key: "SWIFT64_CPU_FUNCTIONAL_INITIAL_X")
    let y = try cpuFunctionalInitialRegisterEnvironmentValue(environment, key: "SWIFT64_CPU_FUNCTIONAL_INITIAL_Y")
    let sp = try cpuFunctionalInitialRegisterEnvironmentValue(environment, key: "SWIFT64_CPU_FUNCTIONAL_INITIAL_SP")
    let p = try cpuFunctionalInitialRegisterEnvironmentValue(environment, key: "SWIFT64_CPU_FUNCTIONAL_INITIAL_P")
    guard a != nil || x != nil || y != nil || sp != nil || p != nil else {
        return nil
    }
    return CPUFunctionalRegisterValues(a: a, x: x, y: y, sp: sp, p: p)
}

private func cpuFunctionalInitialRegisterEnvironmentValue(
    _ environment: [String: String],
    key: String
) throws -> String? {
    guard let value = environment[key], !value.isEmpty else {
        return nil
    }
    guard UInt8(hexString: value) != nil else {
        throw CPUFunctionalManifestError("Invalid \(key): \(value)")
    }
    return value
}

private func cpuFunctionalInitialRegisterPairs(
    _ registers: CPUFunctionalRegisterValues
) -> [(String, String)] {
    [
        registers.a.map { ("A", $0) },
        registers.x.map { ("X", $0) },
        registers.y.map { ("Y", $0) },
        registers.sp.map { ("SP", $0) },
        registers.p.map { ("P", $0) },
    ].compactMap { $0 }
}

private func validateCPUFunctionalRegisterExpectations(
    _ expectations: CPUFunctionalRegisterExpectations?,
    fixture: CPUFunctionalFixture
) throws {
    guard let expectations else { return }
    for (name, expectation) in cpuFunctionalRegisterExpectationPairs(expectations) {
        guard UInt8(hexString: expectation.value) != nil else {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) finalRegisters.\(name) has invalid value \(expectation.value)")
        }
        if let mask = expectation.mask, UInt8(hexString: mask) == nil {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) finalRegisters.\(name) has invalid mask \(mask)")
        }
    }
}

private func cpuFunctionalRegisterMismatches(
    _ expectations: CPUFunctionalRegisterExpectations?,
    cpu: CPU6502
) -> [String] {
    guard let expectations else { return [] }
    let actualValues: [String: UInt8] = [
        "A": cpu.a,
        "X": cpu.x,
        "Y": cpu.y,
        "SP": cpu.sp,
        "P": cpu.p,
    ]

    return cpuFunctionalRegisterExpectationPairs(expectations).compactMap { name, expectation in
        guard let expected = UInt8(hexString: expectation.value),
              let actual = actualValues[name] else {
            return nil
        }
        let mask = expectation.mask.flatMap(UInt8.init(hexString:)) ?? 0xFF
        guard (actual & mask) != (expected & mask) else {
            return nil
        }
        let maskText = mask == 0xFF ? "" : " mask \(hex8(mask))"
        return "\(name) expected \(hex8(expected))\(maskText) got \(hex8(actual))"
    }
}

private func cpuFunctionalRegisterExpectationPairs(
    _ expectations: CPUFunctionalRegisterExpectations
) -> [(String, CPUFunctionalByteExpectation)] {
    [
        expectations.a.map { ("A", $0) },
        expectations.x.map { ("X", $0) },
        expectations.y.map { ("Y", $0) },
        expectations.sp.map { ("SP", $0) },
        expectations.p.map { ("P", $0) },
    ].compactMap { $0 }
}

private func validateCPUFunctionalInitialMemory(
    _ patches: [CPUFunctionalMemoryPatch],
    fixture: CPUFunctionalFixture
) throws {
    for (index, patch) in patches.enumerated() {
        guard UInt16(hexString: patch.address) != nil else {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) initialMemory[\(index)].address has invalid value \(patch.address)")
        }
        guard UInt8(hexString: patch.value) != nil else {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) initialMemory[\(index)].value has invalid value \(patch.value)")
        }
    }
}

private func applyCPUFunctionalInitialMemory(
    _ patches: [CPUFunctionalMemoryPatch],
    to bus: ConformanceRAMBus
) {
    for patch in patches {
        guard let address = UInt16(hexString: patch.address),
              let value = UInt8(hexString: patch.value) else {
            continue
        }
        bus.memory[Int(address)] = value
    }
}

private func validateCPUFunctionalMemoryExpectations(
    _ expectations: [CPUFunctionalMemoryExpectation],
    fixture: CPUFunctionalFixture
) throws {
    for (index, expectation) in expectations.enumerated() {
        guard UInt16(hexString: expectation.address) != nil else {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) finalMemory[\(index)].address has invalid value \(expectation.address)")
        }
        guard UInt8(hexString: expectation.value.value) != nil else {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) finalMemory[\(index)].value has invalid value \(expectation.value.value)")
        }
        if let mask = expectation.value.mask, UInt8(hexString: mask) == nil {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) finalMemory[\(index)].mask has invalid value \(mask)")
        }
    }
}

private func validateCPUFunctionalMemoryRangeExpectations(
    _ expectations: [CPUFunctionalMemoryRangeExpectation],
    fixture: CPUFunctionalFixture
) throws {
    for (index, expectation) in expectations.enumerated() {
        guard let start = UInt16(hexString: expectation.start) else {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) finalMemoryRanges[\(index)].start has invalid value \(expectation.start)")
        }
        guard expectation.length >= 0 else {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) finalMemoryRanges[\(index)].length must be non-negative")
        }
        guard Int(start) + expectation.length <= 0x10000 else {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) finalMemoryRanges[\(index)] exceeds 64K RAM")
        }
        guard isCPUFunctionalHash(expectation.fnv1a64) else {
            throw CPUFunctionalManifestError("fixture \(fixture.id ?? fixture.path) finalMemoryRanges[\(index)].fnv1a64 has invalid value \(expectation.fnv1a64)")
        }
    }
}

private func cpuFunctionalMemoryMismatches(
    _ expectations: [CPUFunctionalMemoryExpectation],
    bus: ConformanceRAMBus
) -> [String] {
    expectations.compactMap { expectation in
        guard let address = UInt16(hexString: expectation.address),
              let expected = UInt8(hexString: expectation.value.value) else {
            return nil
        }
        let actual = bus.memory[Int(address)]
        let mask = expectation.value.mask.flatMap(UInt8.init(hexString:)) ?? 0xFF
        guard (actual & mask) != (expected & mask) else {
            return nil
        }
        let maskText = mask == 0xFF ? "" : " mask \(hex8(mask))"
        return "\(hex16(address)) expected \(hex8(expected))\(maskText) got \(hex8(actual))"
    }
}

private func cpuFunctionalMemoryRangeMismatches(
    _ expectations: [CPUFunctionalMemoryRangeExpectation],
    bus: ConformanceRAMBus
) -> [String] {
    expectations.compactMap { expectation in
        guard let start = UInt16(hexString: expectation.start),
              expectation.length >= 0,
              Int(start) + expectation.length <= bus.memory.count else {
            return nil
        }
        let startIndex = Int(start)
        let endIndex = startIndex + expectation.length
        let data = Data(bus.memory[startIndex..<endIndex])
        let actual = fnv1a64(data)
        guard actual != expectation.fnv1a64.uppercased() else {
            return nil
        }
        let last: UInt16 = expectation.length == 0 ? start : UInt16(startIndex + expectation.length - 1)
        return "\(hex16(start))..\(hex16(last)) expected FNV1A64 \(expectation.fnv1a64.uppercased()) got \(actual)"
    }
}

private func isCPUFunctionalHash(_ value: String) -> Bool {
    let hexDigits = Set("0123456789abcdefABCDEF")
    return value.count == 16 && value.allSatisfy { hexDigits.contains($0) }
}

private struct CPUFunctionalManifestError: Error, CustomStringConvertible, LocalizedError {
    let description: String

    init(_ description: String) {
        self.description = description
    }

    var errorDescription: String? {
        description
    }
}

private func writeCPUFunctionalRunRecord(_ record: CPUFunctionalRunRecord, to url: URL?) throws {
    guard let url else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try encoder.encode(record).write(to: url, options: .atomic)
}

private func writeCPUFunctionalRunSummary(_ summary: CPUFunctionalRunSummary, to url: URL?) throws {
    guard let url else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try encoder.encode(summary).write(to: url, options: .atomic)
}

private func parseRequiredHex16(_ value: String, field: String) throws -> UInt16 {
    guard let parsed = UInt16(hexString: value) else {
        throw CPUFunctionalManifestError("Invalid \(field): \(value)")
    }
    return parsed
}

private func parseOptionalHex16(_ value: String?, field: String) throws -> UInt16? {
    guard let value else { return nil }
    guard let parsed = UInt16(hexString: value) else {
        throw CPUFunctionalManifestError("Invalid \(field): \(value)")
    }
    return parsed
}

private func parseHex16(_ value: String?, default defaultValue: UInt16, field: String) throws -> UInt16 {
    guard let value else { return defaultValue }
    guard let parsed = UInt16(hexString: value) else {
        throw CPUFunctionalManifestError("Invalid \(field): \(value)")
    }
    return parsed
}

private func fnv1a64(_ data: Data) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in data {
        hash ^= UInt64(byte)
        hash &*= 0x100000001b3
    }
    return String(format: "%016llX", hash)
}

private func hex16(_ value: UInt16) -> String {
    "$" + String(format: "%04X", value)
}

private func hex8(_ value: UInt8) -> String {
    "$" + String(format: "%02X", value)
}

private extension UInt16 {
    init?(hexEnvironment value: String?) {
        self.init(hexString: value)
    }

    init?(hexString value: String?) {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("$") {
            text.removeFirst()
        } else if text.lowercased().hasPrefix("0x") {
            text.removeFirst(2)
        }
        guard let parsed = UInt16(text, radix: 16) else {
            return nil
        }
        self = parsed
    }
}

private extension UInt8 {
    init?(hexString value: String?) {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.hasPrefix("$") {
            text.removeFirst()
        } else if text.lowercased().hasPrefix("0x") {
            text.removeFirst(2)
        }
        guard let parsed = UInt8(text, radix: 16) else {
            return nil
        }
        self = parsed
    }
}
