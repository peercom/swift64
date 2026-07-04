import XCTest
import Emu6502
import Foundation

private final class ProcessorJSONRAMBus: Bus {
    var memory = [UInt8](repeating: 0, count: 0x10000)
    var isRecording = false
    var cycles: [ProcessorJSONBusCycle] = []

    func read(_ address: UInt16) -> UInt8 {
        let value = memory[Int(address)]
        if isRecording {
            cycles.append(ProcessorJSONBusCycle(address: address, value: value, operation: "read"))
        }
        return value
    }

    func write(_ address: UInt16, value: UInt8) {
        if isRecording {
            cycles.append(ProcessorJSONBusCycle(address: address, value: value, operation: "write"))
        }
        memory[Int(address)] = value
    }
}

private struct ProcessorJSONBusCycle: Equatable {
    let address: UInt16
    let value: UInt8
    let operation: String
}

final class CPU6502ProcessorJSONTests: XCTestCase {
    func testSyntheticProcessorJSONPassesAndReportsSummary() throws {
        let tests = [
            ProcessorJSONCase(
                name: "lda-immediate",
                initial: ProcessorJSONState(
                    pc: 0x0400,
                    s: 0xFD,
                    a: 0x00,
                    x: 0x12,
                    y: 0x34,
                    p: 0x24,
                    ram: [
                        [0x0400, 0xA9],
                        [0x0401, 0x42],
                    ]
                ),
                final: ProcessorJSONState(
                    pc: 0x0402,
                    s: 0xFD,
                    a: 0x42,
                    x: 0x12,
                    y: 0x34,
                    p: 0x24,
                    ram: [
                        [0x0400, 0xA9],
                        [0x0401, 0x42],
                    ]
                ),
                cycles: [
                    ProcessorJSONCycle(address: 0x0400, value: 0xA9, operation: "read"),
                    ProcessorJSONCycle(address: 0x0401, value: 0x42, operation: "read"),
                ]
            ),
        ]

        let summary = try runProcessorJSONCases(
            tests,
            sourcePath: "/tmp/processor-json/lda.json",
            startIndex: 0,
            limit: nil,
            strictCycleCount: true,
            recordPassingCases: true
        )

        XCTAssertEqual(summary.totalInFile, 1)
        XCTAssertEqual(summary.executed, 1)
        XCTAssertEqual(summary.passed, 1)
        XCTAssertEqual(summary.failed, 0)
        XCTAssertEqual(summary.outcome, "passed")
        XCTAssertEqual(summary.acceptanceFailures, 0)
        XCTAssertNil(summary.firstFailure)
        XCTAssertEqual(summary.strictCycleCount, true)
    }

    func testSyntheticProcessorJSONReportsRegisterMemoryAndCycleMismatch() throws {
        let tests = [
            ProcessorJSONCase(
                name: "sta-zero-page-mismatch",
                initial: ProcessorJSONState(
                    pc: 0x0400,
                    s: 0xFE,
                    a: 0x77,
                    x: 0x00,
                    y: 0x00,
                    p: 0x24,
                    ram: [
                        [0x0400, 0x85],
                        [0x0401, 0x20],
                    ]
                ),
                final: ProcessorJSONState(
                    pc: 0x0402,
                    s: 0xFE,
                    a: 0x76,
                    x: 0x00,
                    y: 0x00,
                    p: 0x24,
                    ram: [
                        [0x0020, 0x76],
                    ]
                ),
                cycles: [
                    ProcessorJSONCycle(address: 0x0400, value: 0x85, operation: "read"),
                    ProcessorJSONCycle(address: 0x0401, value: 0x20, operation: "read"),
                ]
            ),
        ]

        let summary = try runProcessorJSONCases(
            tests,
            sourcePath: "/tmp/processor-json/sta.json",
            startIndex: 0,
            limit: nil,
            strictCycleCount: true,
            recordPassingCases: true
        )

        XCTAssertEqual(summary.passed, 0)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.firstFailure?.name, "sta-zero-page-mismatch")
        XCTAssertEqual(summary.firstFailure?.index, 0)
        XCTAssertTrue(summary.firstFailure?.mismatches.contains("A expected $76 got $77") == true)
        XCTAssertTrue(summary.firstFailure?.mismatches.contains("$0020 expected $76 got $77") == true)
        XCTAssertTrue(summary.firstFailure?.mismatches.contains("cycles expected 2 got 3") == true)
    }

    func testSyntheticProcessorJSONReportsBusCycleMismatchInStrictMode() throws {
        let tests = [
            ProcessorJSONCase(
                name: "nop-bus-value-mismatch",
                initial: ProcessorJSONState(
                    pc: 0x0400,
                    s: 0xFD,
                    a: 0x00,
                    x: 0x00,
                    y: 0x00,
                    p: 0x24,
                    ram: [[0x0400, 0xEA]]
                ),
                final: ProcessorJSONState(
                    pc: 0x0401,
                    s: 0xFD,
                    a: 0x00,
                    x: 0x00,
                    y: 0x00,
                    p: 0x24,
                    ram: [[0x0400, 0xEA]]
                ),
                cycles: [
                    ProcessorJSONCycle(address: 0x0400, value: 0xEA, operation: "read"),
                    ProcessorJSONCycle(address: 0x0401, value: 0xFF, operation: "read"),
                ]
            ),
        ]

        let strict = try runProcessorJSONCases(
            tests,
            sourcePath: "/tmp/processor-json/ea.json",
            startIndex: 0,
            limit: nil,
            strictCycleCount: true,
            recordPassingCases: true
        )
        XCTAssertEqual(strict.failed, 1)
        XCTAssertTrue(strict.firstFailure?.mismatches.contains("cycle 1 read $0401 expected $FF got read $0401 $00") == true)

        let loose = try runProcessorJSONCases(
            tests,
            sourcePath: "/tmp/processor-json/ea.json",
            startIndex: 0,
            limit: nil,
            strictCycleCount: false,
            recordPassingCases: true
        )
        XCTAssertEqual(loose.failed, 0)
    }

    func testProcessorJSONRejectsInvalidCycleOperationBeforeExecution() throws {
        let test = ProcessorJSONCase(
            name: "bad-operation",
            initial: ProcessorJSONState(
                pc: 0x0400,
                s: 0xFD,
                a: 0x00,
                x: 0x00,
                y: 0x00,
                p: 0x24,
                ram: [[0x0400, 0xEA]]
            ),
            final: ProcessorJSONState(
                pc: 0x0401,
                s: 0xFD,
                a: 0x00,
                x: 0x00,
                y: 0x00,
                p: 0x24,
                ram: [[0x0400, 0xEA]]
            ),
            cycles: [
                ProcessorJSONCycle(address: 0x0400, value: 0xEA, operation: "fetch"),
            ]
        )

        XCTAssertThrowsError(try runProcessorJSONCase(
            test,
            sourcePath: "/tmp/processor-json/ea.json",
            index: 7,
            strictCycleCount: true
        )) { error in
            XCTAssertTrue(String(describing: error).contains("bad-operation"))
            XCTAssertTrue(String(describing: error).contains("cycle 0"))
            XCTAssertTrue(String(describing: error).contains("fetch"))
        }
    }

    func testProcessorJSONRejectsInvalidFinalRAMBeforeExecution() throws {
        let test = ProcessorJSONCase(
            name: "bad-final-ram",
            initial: ProcessorJSONState(
                pc: 0x0400,
                s: 0xFD,
                a: 0x00,
                x: 0x00,
                y: 0x00,
                p: 0x24,
                ram: [[0x0400, 0xEA]]
            ),
            final: ProcessorJSONState(
                pc: 0x0401,
                s: 0xFD,
                a: 0x00,
                x: 0x00,
                y: 0x00,
                p: 0x24,
                ram: [[0x10000, 0x00]]
            ),
            cycles: [
                ProcessorJSONCycle(address: 0x0400, value: 0xEA, operation: "read"),
            ]
        )

        XCTAssertThrowsError(try runProcessorJSONCase(
            test,
            sourcePath: "/tmp/processor-json/ea.json",
            index: 8,
            strictCycleCount: true
        )) { error in
            XCTAssertTrue(String(describing: error).contains("bad-final-ram"))
            XCTAssertTrue(String(describing: error).contains("final.ram[0].address"))
            XCTAssertTrue(String(describing: error).contains("not a 16-bit address"))
        }
    }

    func testProcessorJSONStartAndLimitBoundExecution() throws {
        let tests = [
            processorJSONNOPCase(name: "skip", pc: 0x0400),
            processorJSONNOPCase(name: "run", pc: 0x0500),
        ]

        let summary = try runProcessorJSONCases(
            tests,
            sourcePath: "/tmp/processor-json/ea.json",
            startIndex: 1,
            limit: 1,
            strictCycleCount: true,
            recordPassingCases: true
        )

        XCTAssertEqual(summary.totalInFile, 2)
        XCTAssertEqual(summary.startIndex, 1)
        XCTAssertEqual(summary.limit, 1)
        XCTAssertEqual(summary.executed, 1)
        XCTAssertEqual(summary.passed, 1)
        XCTAssertEqual(summary.records.map(\.name), ["run"])
    }

    func testProcessorJSONDirectoryAllDiscoversSortedFilesAndFailFastStopsAfterFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try writeProcessorJSONFixture(
            [processorJSONNOPCase(name: "first", pc: 0x0400)],
            to: directory.appendingPathComponent("ea.json")
        )
        try writeProcessorJSONFixture(
            [
                ProcessorJSONCase(
                    name: "second-fails",
                    initial: ProcessorJSONState(
                        pc: 0x0500,
                        s: 0xFD,
                        a: 0x00,
                        x: 0x00,
                        y: 0x00,
                        p: 0x24,
                        ram: [[0x0500, 0xA9], [0x0501, 0x42]]
                    ),
                    final: ProcessorJSONState(
                        pc: 0x0502,
                        s: 0xFD,
                        a: 0x41,
                        x: 0x00,
                        y: 0x00,
                        p: 0x24,
                        ram: [[0x0500, 0xA9], [0x0501, 0x42]]
                    ),
                    cycles: [
                        ProcessorJSONCycle(address: 0x0500, value: 0xA9, operation: "read"),
                        ProcessorJSONCycle(address: 0x0501, value: 0x42, operation: "read"),
                    ]
                ),
            ],
            to: directory.appendingPathComponent("a9.json")
        )
        try writeProcessorJSONFixture(
            [processorJSONNOPCase(name: "third-not-reached", pc: 0x0600)],
            to: directory.appendingPathComponent("ff.json")
        )

        let aggregate = try runProcessorJSONInputs(
            urls: processorJSONInputFiles(from: [
                "SWIFT64_PROCESSOR_JSON_TEST_DIR": directory.path,
                "SWIFT64_PROCESSOR_JSON_OPCODES": "all",
            ]),
            startIndex: 0,
            limit: nil,
            strictCycleCount: true,
            recordPassingCases: false,
            failFast: true
        )

        XCTAssertEqual(aggregate.files, 1)
        XCTAssertEqual(aggregate.executed, 1)
        XCTAssertEqual(aggregate.failed, 1)
        XCTAssertEqual(aggregate.outcome, "failed")
        XCTAssertEqual(aggregate.acceptanceFailures, 1)
        XCTAssertEqual(aggregate.category, "cpu")
        XCTAssertEqual(aggregate.roadmapPhase, "phase2CPUMemoryBus")
        XCTAssertEqual(aggregate.failureDetails.count, 1)
        XCTAssertEqual(aggregate.failureDetails[0].name, "second-fails")
        XCTAssertEqual(aggregate.failureDetails[0].category, "cpu")
        XCTAssertEqual(aggregate.failureDetails[0].roadmapPhase, "phase2CPUMemoryBus")
        XCTAssertEqual(aggregate.failedFiles, ["a9.json"])
        XCTAssertEqual(aggregate.failedOpcodes, ["A9"])
        XCTAssertEqual(aggregate.opcodeSummaries["A9"], ProcessorJSONOpcodeSummary(
            files: 1,
            executed: 1,
            passed: 0,
            failed: 1,
            category: "cpu",
            roadmapPhase: "phase2CPUMemoryBus",
            outcome: "failed"
        ))
        XCTAssertTrue(aggregate.failureSummary.contains("second-fails"))
        XCTAssertTrue(aggregate.summaries[0].sourcePath.hasSuffix("a9.json"))
    }

    func testProcessorJSONInputFilesCanSelectDeterministicShard() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for opcode in ["00", "01", "02", "03", "04"] {
            try writeProcessorJSONFixture(
                [processorJSONNOPCase(name: opcode, pc: 0x0400)],
                to: directory.appendingPathComponent("\(opcode).json")
            )
        }

        let urls = try processorJSONInputFiles(from: [
            "SWIFT64_PROCESSOR_JSON_TEST_DIR": directory.path,
            "SWIFT64_PROCESSOR_JSON_OPCODES": "all",
            "SWIFT64_PROCESSOR_JSON_SHARD_INDEX": "1",
            "SWIFT64_PROCESSOR_JSON_SHARD_COUNT": "2",
        ])

        XCTAssertEqual(urls.map { $0.deletingPathExtension().lastPathComponent }, ["01", "03"])
    }

    func testProcessorJSONInputFilesRejectInvalidShardSelection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try writeProcessorJSONFixture(
            [processorJSONNOPCase(name: "nop", pc: 0x0400)],
            to: directory.appendingPathComponent("ea.json")
        )

        XCTAssertThrowsError(try processorJSONInputFiles(from: [
            "SWIFT64_PROCESSOR_JSON_TEST_DIR": directory.path,
            "SWIFT64_PROCESSOR_JSON_OPCODES": "all",
            "SWIFT64_PROCESSOR_JSON_SHARD_INDEX": "2",
            "SWIFT64_PROCESSOR_JSON_SHARD_COUNT": "2",
        ])) { error in
            XCTAssertTrue(String(describing: error).contains("SHARD_INDEX"))
        }
    }

    func testProcessorJSONRunConfigurationCapturesShardAndOpcodeSelection() {
        let configuration = processorJSONRunConfiguration(from: [
            "SWIFT64_PROCESSOR_JSON_TEST_DIR": "/tmp/6502/v1",
            "SWIFT64_PROCESSOR_JSON_OPCODES": "ea,a9",
            "SWIFT64_PROCESSOR_JSON_SHARD_INDEX": "1",
            "SWIFT64_PROCESSOR_JSON_SHARD_COUNT": "4",
        ], failFast: true)

        XCTAssertEqual(configuration.testDirectory, "/tmp/6502/v1")
        XCTAssertEqual(configuration.opcodeSelection, "ea,a9")
        XCTAssertEqual(configuration.shardIndex, 1)
        XCTAssertEqual(configuration.shardCount, 4)
        XCTAssertTrue(configuration.failFast)
    }

    func testProcessorJSONAggregateSummaryFingerprintsSelectedInputFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("ea.json")
        let second = directory.appendingPathComponent("a9.json")
        try writeProcessorJSONFixture([processorJSONNOPCase(name: "first", pc: 0x0400)], to: first)
        try writeProcessorJSONFixture([processorJSONNOPCase(name: "second", pc: 0x0500)], to: second)

        let summary = try runProcessorJSONInputs(
            urls: [second, first],
            startIndex: 0,
            limit: nil,
            strictCycleCount: false,
            recordPassingCases: false,
            failFast: false
        )

        XCTAssertEqual(summary.selectedInputFiles, ["a9.json", "ea.json"])
        XCTAssertEqual(summary.inputFNV1A64.count, 16)
        XCTAssertEqual(summary.inputFNV1A64, try processorJSONInputFingerprint(urls: [first, second]))
        XCTAssertEqual(summary.category, "cpu")
        XCTAssertEqual(summary.roadmapPhase, "phase2CPUMemoryBus")
        XCTAssertEqual(summary.opcodeSummaries["A9"]?.outcome, "passed")
        XCTAssertEqual(summary.opcodeSummaries["EA"]?.outcome, "passed")
    }

    func testOptInProcessorJSONSingleStepVectors() throws {
        let environment = ProcessInfo.processInfo.environment
        let resultURL = environment["SWIFT64_PROCESSOR_JSON_RESULT_JSON"].flatMap { path -> URL? in
            path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
        let startIndex = Int(environment["SWIFT64_PROCESSOR_JSON_START_INDEX"] ?? "") ?? 0
        let limit = Int(environment["SWIFT64_PROCESSOR_JSON_LIMIT"] ?? "")
        let strictCycleCount = environment["SWIFT64_PROCESSOR_JSON_STRICT_CYCLES"] == "1"
        let recordPassingCases = environment["SWIFT64_PROCESSOR_JSON_RECORD_PASSING"] == "1"
        let failFast = environment["SWIFT64_PROCESSOR_JSON_FAIL_FAST"] == "1"

        let aggregate = try runProcessorJSONInputs(
            urls: processorJSONInputFiles(from: environment),
            startIndex: startIndex,
            limit: limit,
            strictCycleCount: strictCycleCount,
            recordPassingCases: recordPassingCases,
            failFast: failFast,
            configuration: processorJSONRunConfiguration(from: environment, failFast: failFast)
        )
        try writeProcessorJSONAggregateSummary(aggregate, to: resultURL)

        XCTAssertEqual(aggregate.failed, 0, aggregate.failureSummary)
    }
}

private struct ProcessorJSONCase: Codable, Equatable {
    let name: String
    let initial: ProcessorJSONState
    let final: ProcessorJSONState
    let cycles: [ProcessorJSONCycle]
}

private struct ProcessorJSONState: Codable, Equatable {
    let pc: Int
    let s: Int
    let a: Int
    let x: Int
    let y: Int
    let p: Int
    let ram: [[Int]]
}

private struct ProcessorJSONCycle: Codable, Equatable {
    let address: Int
    let value: Int
    let operation: String

    init(address: Int, value: Int, operation: String) {
        self.address = address
        self.value = value
        self.operation = operation
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        address = try container.decode(Int.self)
        value = try container.decode(Int.self)
        operation = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(address)
        try container.encode(value)
        try container.encode(operation)
    }
}

private let processorJSONFailureCategory = "cpu"
private let processorJSONRoadmapPhase = "phase2CPUMemoryBus"

private struct ProcessorJSONAggregateSummary: Codable, Equatable {
    var formatVersion: Int = 9
    var runnerName: String = "CPU6502ProcessorJSONTests"
    var category: String = processorJSONFailureCategory
    var roadmapPhase: String = processorJSONRoadmapPhase
    let configuration: ProcessorJSONRunConfiguration
    let inputFNV1A64: String
    let selectedInputFiles: [String]
    let files: Int
    let totalInFiles: Int
    let executed: Int
    let passed: Int
    let failed: Int
    let outcome: String
    let acceptanceFailures: Int
    let failureDetails: [ProcessorJSONFailure]
    let failedFiles: [String]
    let failedOpcodes: [String]
    let opcodeSummaries: [String: ProcessorJSONOpcodeSummary]
    let summaries: [ProcessorJSONRunSummary]

    init(
        summaries: [ProcessorJSONRunSummary],
        configuration: ProcessorJSONRunConfiguration = ProcessorJSONRunConfiguration(),
        inputFNV1A64: String = processorJSONFNV1A64([]),
        selectedInputFiles: [String] = []
    ) {
        self.configuration = configuration
        self.inputFNV1A64 = inputFNV1A64
        self.selectedInputFiles = selectedInputFiles
        self.files = summaries.count
        self.totalInFiles = summaries.reduce(0) { $0 + $1.totalInFile }
        self.executed = summaries.reduce(0) { $0 + $1.executed }
        self.passed = summaries.reduce(0) { $0 + $1.passed }
        self.failed = summaries.reduce(0) { $0 + $1.failed }
        self.outcome = self.failed == 0 ? "passed" : "failed"
        self.acceptanceFailures = self.failed
        self.failureDetails = summaries.compactMap(\.firstFailure)
        self.failedFiles = summaries
            .filter { $0.failed > 0 }
            .map { URL(fileURLWithPath: $0.sourcePath).lastPathComponent }
        self.failedOpcodes = summaries
            .filter { $0.failed > 0 }
            .compactMap { processorJSONOpcodeName(from: $0.sourcePath) }
        self.opcodeSummaries = processorJSONOpcodeSummaries(from: summaries)
        self.summaries = summaries
    }

    var failureSummary: String {
        guard !failureDetails.isEmpty else {
            return "No ProcessorTests JSON failures."
        }
        return failureDetails.map { failure in
            "\(failure.sourcePath) \(failure.index) \(failure.name): \(failure.mismatches.joined(separator: "; "))"
        }.joined(separator: "\n")
    }
}

private struct ProcessorJSONOpcodeSummary: Codable, Equatable {
    let files: Int
    let executed: Int
    let passed: Int
    let failed: Int
    let category: String
    let roadmapPhase: String
    let outcome: String
}

private struct ProcessorJSONRunConfiguration: Codable, Equatable {
    let testPath: String?
    let testDirectory: String?
    let opcodeSelection: String?
    let shardIndex: Int?
    let shardCount: Int?
    let failFast: Bool

    init(
        testPath: String? = nil,
        testDirectory: String? = nil,
        opcodeSelection: String? = nil,
        shardIndex: Int? = nil,
        shardCount: Int? = nil,
        failFast: Bool = false
    ) {
        self.testPath = testPath
        self.testDirectory = testDirectory
        self.opcodeSelection = opcodeSelection
        self.shardIndex = shardIndex
        self.shardCount = shardCount
        self.failFast = failFast
    }
}

private struct ProcessorJSONRunSummary: Codable, Equatable {
    var formatVersion: Int = 2
    var runnerName: String = "CPU6502ProcessorJSONTests"
    var category: String = processorJSONFailureCategory
    var roadmapPhase: String = processorJSONRoadmapPhase
    let sourcePath: String
    let totalInFile: Int
    let startIndex: Int
    let limit: Int?
    let strictCycleCount: Bool
    let recordPassingCases: Bool
    let executed: Int
    let passed: Int
    let failed: Int
    let outcome: String
    let acceptanceFailures: Int
    let firstFailure: ProcessorJSONFailure?
    let records: [ProcessorJSONRecord]
}

private struct ProcessorJSONRecord: Codable, Equatable {
    let index: Int
    let name: String
    let passed: Bool
    let elapsedCycles: Int
    let expectedCycles: Int
    let finalPC: String
    let mismatches: [String]
}

private struct ProcessorJSONFailure: Codable, Equatable {
    var category: String = processorJSONFailureCategory
    var roadmapPhase: String = processorJSONRoadmapPhase
    let sourcePath: String
    let index: Int
    let name: String
    let elapsedCycles: Int
    let expectedCycles: Int
    let finalPC: String
    let mismatches: [String]
}

private func processorJSONInputFiles(from environment: [String: String]) throws -> [URL] {
    if let path = environment["SWIFT64_PROCESSOR_JSON_TEST_PATH"], !path.isEmpty {
        return [URL(fileURLWithPath: path)]
    }

    guard let directory = environment["SWIFT64_PROCESSOR_JSON_TEST_DIR"], !directory.isEmpty else {
        throw XCTSkip("Set SWIFT64_PROCESSOR_JSON_TEST_PATH or SWIFT64_PROCESSOR_JSON_TEST_DIR to run local ProcessorTests JSON vectors.")
    }
    guard let opcodeList = environment["SWIFT64_PROCESSOR_JSON_OPCODES"], !opcodeList.isEmpty else {
        throw XCTSkip("Set SWIFT64_PROCESSOR_JSON_OPCODES to a comma-separated opcode list, such as 69,EA.")
    }

    let urls: [URL]
    if opcodeList.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "all" {
        urls = try processorJSONAllInputFiles(in: URL(fileURLWithPath: directory))
    } else {
        urls = opcodeList
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .map { opcode in
                let fileName = opcode.hasSuffix(".json") ? opcode : "\(opcode).json"
                return URL(fileURLWithPath: directory).appendingPathComponent(fileName)
            }
    }

    return try processorJSONShard(urls, environment: environment)
}

private func processorJSONShard(_ urls: [URL], environment: [String: String]) throws -> [URL] {
    guard environment["SWIFT64_PROCESSOR_JSON_SHARD_INDEX"] != nil ||
        environment["SWIFT64_PROCESSOR_JSON_SHARD_COUNT"] != nil else {
        return urls
    }

    guard let shardIndexString = environment["SWIFT64_PROCESSOR_JSON_SHARD_INDEX"],
          let shardCountString = environment["SWIFT64_PROCESSOR_JSON_SHARD_COUNT"],
          let shardIndex = Int(shardIndexString),
          let shardCount = Int(shardCountString),
          shardCount > 0,
          shardIndex >= 0,
          shardIndex < shardCount else {
        throw ProcessorJSONError("SWIFT64_PROCESSOR_JSON_SHARD_INDEX must be zero-based and less than SWIFT64_PROCESSOR_JSON_SHARD_COUNT")
    }

    return urls.enumerated()
        .filter { offset, _ in offset % shardCount == shardIndex }
        .map(\.element)
}

private func processorJSONRunConfiguration(
    from environment: [String: String],
    failFast: Bool
) -> ProcessorJSONRunConfiguration {
    ProcessorJSONRunConfiguration(
        testPath: nonEmptyEnvironmentValue("SWIFT64_PROCESSOR_JSON_TEST_PATH", in: environment),
        testDirectory: nonEmptyEnvironmentValue("SWIFT64_PROCESSOR_JSON_TEST_DIR", in: environment),
        opcodeSelection: nonEmptyEnvironmentValue("SWIFT64_PROCESSOR_JSON_OPCODES", in: environment),
        shardIndex: Int(environment["SWIFT64_PROCESSOR_JSON_SHARD_INDEX"] ?? ""),
        shardCount: Int(environment["SWIFT64_PROCESSOR_JSON_SHARD_COUNT"] ?? ""),
        failFast: failFast
    )
}

private func nonEmptyEnvironmentValue(_ key: String, in environment: [String: String]) -> String? {
    guard let value = environment[key], !value.isEmpty else { return nil }
    return value
}

private func processorJSONAllInputFiles(in directory: URL) throws -> [URL] {
    let urls = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )
    let jsonFiles = urls
        .filter { $0.pathExtension.lowercased() == "json" }
        .filter { UInt8($0.deletingPathExtension().lastPathComponent, radix: 16) != nil }
        .sorted { lhs, rhs in
            let lhsOpcode = UInt8(lhs.deletingPathExtension().lastPathComponent, radix: 16) ?? 0
            let rhsOpcode = UInt8(rhs.deletingPathExtension().lastPathComponent, radix: 16) ?? 0
            return lhsOpcode < rhsOpcode
        }
    guard !jsonFiles.isEmpty else {
        throw ProcessorJSONError("No hex-named JSON files found in \(directory.path)")
    }
    return jsonFiles
}

private func processorJSONOpcodeName(from sourcePath: String) -> String? {
    let name = URL(fileURLWithPath: sourcePath).deletingPathExtension().lastPathComponent
    guard let opcode = UInt8(name, radix: 16) else { return nil }
    return String(format: "%02X", opcode)
}

private func processorJSONOpcodeSummaries(
    from summaries: [ProcessorJSONRunSummary]
) -> [String: ProcessorJSONOpcodeSummary] {
    var totals: [String: (files: Int, executed: Int, passed: Int, failed: Int)] = [:]
    for summary in summaries {
        guard let opcode = processorJSONOpcodeName(from: summary.sourcePath) else { continue }
        var total = totals[opcode] ?? (files: 0, executed: 0, passed: 0, failed: 0)
        total.files += 1
        total.executed += summary.executed
        total.passed += summary.passed
        total.failed += summary.failed
        totals[opcode] = total
    }

    return totals.mapValues { total in
        ProcessorJSONOpcodeSummary(
            files: total.files,
            executed: total.executed,
            passed: total.passed,
            failed: total.failed,
            category: processorJSONFailureCategory,
            roadmapPhase: processorJSONRoadmapPhase,
            outcome: total.failed == 0 ? "passed" : "failed"
        )
    }
}

private func decodeProcessorJSONCases(at url: URL) throws -> [ProcessorJSONCase] {
    try JSONDecoder().decode([ProcessorJSONCase].self, from: Data(contentsOf: url))
}

private func runProcessorJSONInputs(
    urls: [URL],
    startIndex: Int,
    limit: Int?,
    strictCycleCount: Bool,
    recordPassingCases: Bool,
    failFast: Bool,
    configuration: ProcessorJSONRunConfiguration = ProcessorJSONRunConfiguration()
) throws -> ProcessorJSONAggregateSummary {
    let sortedURLs = urls.sorted { lhs, rhs in
        lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
    }
    let inputFNV1A64 = try processorJSONInputFingerprint(urls: sortedURLs)
    let selectedInputFiles = sortedURLs.map(\.lastPathComponent)

    var summaries: [ProcessorJSONRunSummary] = []
    summaries.reserveCapacity(sortedURLs.count)

    for url in sortedURLs {
        let cases = try decodeProcessorJSONCases(at: url)
        let summary = try runProcessorJSONCases(
            cases,
            sourcePath: url.path,
            startIndex: startIndex,
            limit: limit,
            strictCycleCount: strictCycleCount,
            recordPassingCases: recordPassingCases
        )
        summaries.append(summary)
        if failFast && summary.failed > 0 {
            break
        }
    }

    return ProcessorJSONAggregateSummary(
        summaries: summaries,
        configuration: configuration,
        inputFNV1A64: inputFNV1A64,
        selectedInputFiles: selectedInputFiles
    )
}

private func processorJSONInputFingerprint(urls: [URL]) throws -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        for byte in url.lastPathComponent.utf8 {
            processorJSONFNV1A64Update(&hash, byte)
        }
        processorJSONFNV1A64Update(&hash, 0)
        for byte in try Data(contentsOf: url) {
            processorJSONFNV1A64Update(&hash, byte)
        }
        processorJSONFNV1A64Update(&hash, 0)
    }
    return String(format: "%016llX", hash)
}

private func runProcessorJSONCases(
    _ cases: [ProcessorJSONCase],
    sourcePath: String,
    startIndex: Int,
    limit: Int?,
    strictCycleCount: Bool,
    recordPassingCases: Bool
) throws -> ProcessorJSONRunSummary {
    guard startIndex >= 0 else {
        throw ProcessorJSONError("startIndex must be non-negative")
    }
    if let limit, limit <= 0 {
        throw ProcessorJSONError("limit must be positive")
    }

    let endIndex = min(cases.count, startIndex + (limit ?? cases.count))
    guard startIndex <= endIndex else {
        throw ProcessorJSONError("startIndex \(startIndex) exceeds case count \(cases.count)")
    }

    var retainedRecords: [ProcessorJSONRecord] = []
    if recordPassingCases {
        retainedRecords.reserveCapacity(endIndex - startIndex)
    }
    var executed = 0
    var passed = 0
    var failed = 0
    var firstFailure: ProcessorJSONFailure?

    for index in startIndex..<endIndex {
        let record = try runProcessorJSONCase(
            cases[index],
            sourcePath: sourcePath,
            index: index,
            strictCycleCount: strictCycleCount
        )
        executed += 1
        if record.passed {
            passed += 1
            if recordPassingCases {
                retainedRecords.append(record)
            }
        } else {
            failed += 1
            retainedRecords.append(record)
            if firstFailure == nil {
                firstFailure = ProcessorJSONFailure(
                    sourcePath: sourcePath,
                    index: record.index,
                    name: record.name,
                    elapsedCycles: record.elapsedCycles,
                    expectedCycles: record.expectedCycles,
                    finalPC: record.finalPC,
                    mismatches: record.mismatches
                )
            }
        }
    }

    return ProcessorJSONRunSummary(
        sourcePath: sourcePath,
        totalInFile: cases.count,
        startIndex: startIndex,
        limit: limit,
        strictCycleCount: strictCycleCount,
        recordPassingCases: recordPassingCases,
        executed: executed,
        passed: passed,
        failed: failed,
        outcome: failed == 0 ? "passed" : "failed",
        acceptanceFailures: failed,
        firstFailure: firstFailure,
        records: retainedRecords
    )
}

private func runProcessorJSONCase(
    _ test: ProcessorJSONCase,
    sourcePath: String,
    index: Int,
    strictCycleCount: Bool
) throws -> ProcessorJSONRecord {
    try validateProcessorJSONCase(test, sourcePath: sourcePath, index: index)

    let bus = ProcessorJSONRAMBus()
    try applyProcessorJSONRAM(test.initial.ram, to: bus)

    let cpu = CPU6502(bus: bus)
    cpu.pc = try UInt16(processorJSONValue: test.initial.pc, field: "initial.pc")
    cpu.sp = try UInt8(processorJSONValue: test.initial.s, field: "initial.s")
    cpu.a = try UInt8(processorJSONValue: test.initial.a, field: "initial.a")
    cpu.x = try UInt8(processorJSONValue: test.initial.x, field: "initial.x")
    cpu.y = try UInt8(processorJSONValue: test.initial.y, field: "initial.y")
    cpu.p = try UInt8(processorJSONValue: test.initial.p, field: "initial.p")

    let elapsedCycles = runOneProcessorJSONInstruction(cpu, bus: bus)
    let mismatches = try processorJSONMismatches(
        test,
        cpu: cpu,
        bus: bus,
        elapsedCycles: elapsedCycles,
        strictCycleCount: strictCycleCount
    )

    return ProcessorJSONRecord(
        index: index,
        name: test.name,
        passed: mismatches.isEmpty,
        elapsedCycles: elapsedCycles,
        expectedCycles: test.cycles.count,
        finalPC: hex16(cpu.pc),
        mismatches: mismatches
    )
}

private func validateProcessorJSONCase(
    _ test: ProcessorJSONCase,
    sourcePath: String,
    index: Int
) throws {
    let prefix = "\(sourcePath) case \(index) \(test.name)"
    _ = try UInt16(processorJSONValue: test.initial.pc, field: "\(prefix) initial.pc")
    _ = try UInt8(processorJSONValue: test.initial.s, field: "\(prefix) initial.s")
    _ = try UInt8(processorJSONValue: test.initial.a, field: "\(prefix) initial.a")
    _ = try UInt8(processorJSONValue: test.initial.x, field: "\(prefix) initial.x")
    _ = try UInt8(processorJSONValue: test.initial.y, field: "\(prefix) initial.y")
    _ = try UInt8(processorJSONValue: test.initial.p, field: "\(prefix) initial.p")
    _ = try UInt16(processorJSONValue: test.final.pc, field: "\(prefix) final.pc")
    _ = try UInt8(processorJSONValue: test.final.s, field: "\(prefix) final.s")
    _ = try UInt8(processorJSONValue: test.final.a, field: "\(prefix) final.a")
    _ = try UInt8(processorJSONValue: test.final.x, field: "\(prefix) final.x")
    _ = try UInt8(processorJSONValue: test.final.y, field: "\(prefix) final.y")
    _ = try UInt8(processorJSONValue: test.final.p, field: "\(prefix) final.p")

    try validateProcessorJSONRAM(test.initial.ram, label: "\(prefix) initial.ram")
    try validateProcessorJSONRAM(test.final.ram, label: "\(prefix) final.ram")

    for (cycleIndex, cycle) in test.cycles.enumerated() {
        let operation = cycle.operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard operation == "read" || operation == "write" else {
            throw ProcessorJSONError("\(prefix) cycle \(cycleIndex) has invalid operation \(cycle.operation)")
        }
        _ = try UInt16(processorJSONValue: cycle.address, field: "\(prefix) cycles[\(cycleIndex)].address")
        _ = try UInt8(processorJSONValue: cycle.value, field: "\(prefix) cycles[\(cycleIndex)].value")
    }
}

private func validateProcessorJSONRAM(_ ram: [[Int]], label: String) throws {
    for (entryIndex, pair) in ram.enumerated() {
        guard pair.count == 2 else {
            throw ProcessorJSONError("\(label)[\(entryIndex)] must contain address and value")
        }
        _ = try UInt16(processorJSONValue: pair[0], field: "\(label)[\(entryIndex)].address")
        _ = try UInt8(processorJSONValue: pair[1], field: "\(label)[\(entryIndex)].value")
    }
}

private func runOneProcessorJSONInstruction(_ cpu: CPU6502, bus: ProcessorJSONRAMBus) -> Int {
    var elapsedCycles = 0
    bus.cycles.removeAll(keepingCapacity: true)
    bus.isRecording = true
    defer { bus.isRecording = false }
    repeat {
        _ = cpu.tick()
        elapsedCycles += 1
    } while cpu.cycle != 0 && !cpu.jammed && elapsedCycles < 32
    return elapsedCycles
}

private func processorJSONMismatches(
    _ test: ProcessorJSONCase,
    cpu: CPU6502,
    bus: ProcessorJSONRAMBus,
    elapsedCycles: Int,
    strictCycleCount: Bool
) throws -> [String] {
    var mismatches: [String] = []
    let expectedPC = try UInt16(processorJSONValue: test.final.pc, field: "final.pc")
    let expectedSP = try UInt8(processorJSONValue: test.final.s, field: "final.s")
    let expectedA = try UInt8(processorJSONValue: test.final.a, field: "final.a")
    let expectedX = try UInt8(processorJSONValue: test.final.x, field: "final.x")
    let expectedY = try UInt8(processorJSONValue: test.final.y, field: "final.y")
    let expectedP = try UInt8(processorJSONValue: test.final.p, field: "final.p")

    appendMismatch("PC", expected: hex16(expectedPC), actual: hex16(cpu.pc), to: &mismatches)
    appendMismatch("SP", expected: hex8(expectedSP), actual: hex8(cpu.sp), to: &mismatches)
    appendMismatch("A", expected: hex8(expectedA), actual: hex8(cpu.a), to: &mismatches)
    appendMismatch("X", expected: hex8(expectedX), actual: hex8(cpu.x), to: &mismatches)
    appendMismatch("Y", expected: hex8(expectedY), actual: hex8(cpu.y), to: &mismatches)
    appendMismatch("P", expected: hex8(expectedP), actual: hex8(cpu.p), to: &mismatches)

    for pair in test.final.ram {
        guard pair.count == 2 else {
            throw ProcessorJSONError("final.ram entries must contain address and value")
        }
        let address = try UInt16(processorJSONValue: pair[0], field: "final.ram.address")
        let expected = try UInt8(processorJSONValue: pair[1], field: "final.ram.value")
        let actual = bus.memory[Int(address)]
        if actual != expected {
            mismatches.append("\(hex16(address)) expected \(hex8(expected)) got \(hex8(actual))")
        }
    }

    if cpu.jammed && !processorJSONExpectsJammedCPU(test) {
        mismatches.append("CPU jammed")
    }
    if elapsedCycles >= 32 && cpu.cycle != 0 {
        mismatches.append("instruction did not finish within 32 cycles")
    }
    if strictCycleCount && elapsedCycles != test.cycles.count {
        mismatches.append("cycles expected \(test.cycles.count) got \(elapsedCycles)")
    }
    if strictCycleCount {
        try appendProcessorJSONBusCycleMismatches(
            expectedCycles: test.cycles,
            actualCycles: bus.cycles,
            to: &mismatches
        )
    }

    return mismatches
}

private func appendProcessorJSONBusCycleMismatches(
    expectedCycles: [ProcessorJSONCycle],
    actualCycles: [ProcessorJSONBusCycle],
    to mismatches: inout [String]
) throws {
    let comparedCount = min(expectedCycles.count, actualCycles.count)
    for index in 0..<comparedCount {
        let expected = expectedCycles[index]
        let actual = actualCycles[index]
        let expectedAddress = try UInt16(processorJSONValue: expected.address, field: "cycles.address")
        let expectedValue = try UInt8(processorJSONValue: expected.value, field: "cycles.value")
        let expectedOperation = processorJSONCycleOperation(expected.operation)
        if actual.address != expectedAddress ||
            actual.value != expectedValue ||
            actual.operation != expectedOperation {
            mismatches.append(
                "cycle \(index) \(expectedOperation) \(hex16(expectedAddress)) expected \(hex8(expectedValue)) got \(actual.operation) \(hex16(actual.address)) \(hex8(actual.value))"
            )
        }
    }

    if actualCycles.count > expectedCycles.count {
        for index in expectedCycles.count..<actualCycles.count {
            let actual = actualCycles[index]
            mismatches.append("cycle \(index) unexpected \(actual.operation) \(hex16(actual.address)) \(hex8(actual.value))")
        }
    }
    if expectedCycles.count > actualCycles.count {
        for index in actualCycles.count..<expectedCycles.count {
            let expected = expectedCycles[index]
            let expectedAddress = try UInt16(processorJSONValue: expected.address, field: "cycles.address")
            let expectedValue = try UInt8(processorJSONValue: expected.value, field: "cycles.value")
            mismatches.append("cycle \(index) missing \(processorJSONCycleOperation(expected.operation)) \(hex16(expectedAddress)) \(hex8(expectedValue))")
        }
    }
}

private func processorJSONCycleOperation(_ operation: String) -> String {
    operation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func processorJSONExpectsJammedCPU(_ test: ProcessorJSONCase) -> Bool {
    guard let opcode = processorJSONOpcode(test) else {
        return false
    }
    return processorJSONKILOpcodes.contains(opcode)
}

private func processorJSONOpcode(_ test: ProcessorJSONCase) -> UInt8? {
    guard let pc = UInt16(exactly: test.initial.pc) else {
        return nil
    }
    return test.initial.ram.first { pair in
        pair.count == 2 && pair[0] == Int(pc)
    }.flatMap { pair in
        UInt8(exactly: pair[1])
    }
}

private let processorJSONKILOpcodes: Set<UInt8> = [
    0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72,
    0x92, 0xB2, 0xD2, 0xF2,
]

private func appendMismatch(
    _ label: String,
    expected: String,
    actual: String,
    to mismatches: inout [String]
) {
    guard expected != actual else { return }
    mismatches.append("\(label) expected \(expected) got \(actual)")
}

private func applyProcessorJSONRAM(_ ram: [[Int]], to bus: ProcessorJSONRAMBus) throws {
    for pair in ram {
        guard pair.count == 2 else {
            throw ProcessorJSONError("initial.ram entries must contain address and value")
        }
        let address = try UInt16(processorJSONValue: pair[0], field: "initial.ram.address")
        let value = try UInt8(processorJSONValue: pair[1], field: "initial.ram.value")
        bus.memory[Int(address)] = value
    }
}

private func writeProcessorJSONAggregateSummary(
    _ summary: ProcessorJSONAggregateSummary,
    to url: URL?
) throws {
    guard let url else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try encoder.encode(summary).write(to: url, options: .atomic)
}

private func writeProcessorJSONFixture(_ cases: [ProcessorJSONCase], to url: URL) throws {
    let encoder = JSONEncoder()
    try encoder.encode(cases).write(to: url, options: .atomic)
}

private func processorJSONFNV1A64<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in bytes {
        processorJSONFNV1A64Update(&hash, byte)
    }
    return String(format: "%016llX", hash)
}

private func processorJSONFNV1A64Update(_ hash: inout UInt64, _ byte: UInt8) {
    hash ^= UInt64(byte)
    hash = hash &* 0x100000001b3
}

private func processorJSONNOPCase(name: String, pc: Int) -> ProcessorJSONCase {
    ProcessorJSONCase(
        name: name,
        initial: ProcessorJSONState(
            pc: pc,
            s: 0xFD,
            a: 0x00,
            x: 0x00,
            y: 0x00,
            p: 0x24,
            ram: [
                [pc, 0xEA],
            ]
        ),
        final: ProcessorJSONState(
            pc: pc + 1,
            s: 0xFD,
            a: 0x00,
            x: 0x00,
            y: 0x00,
            p: 0x24,
            ram: [
                [pc, 0xEA],
            ]
        ),
        cycles: [
            ProcessorJSONCycle(address: pc, value: 0xEA, operation: "read"),
            ProcessorJSONCycle(address: pc + 1, value: 0x00, operation: "read"),
        ]
    )
}

private struct ProcessorJSONError: Error, CustomStringConvertible, LocalizedError {
    let description: String

    init(_ description: String) {
        self.description = description
    }

    var errorDescription: String? {
        description
    }
}

private extension UInt8 {
    init(processorJSONValue value: Int, field: String) throws {
        guard (0...0xFF).contains(value) else {
            throw ProcessorJSONError("\(field) value \(value) is not a byte")
        }
        self = UInt8(value)
    }
}

private extension UInt16 {
    init(processorJSONValue value: Int, field: String) throws {
        guard (0...0xFFFF).contains(value) else {
            throw ProcessorJSONError("\(field) value \(value) is not a 16-bit address")
        }
        self = UInt16(value)
    }
}

private func hex16(_ value: UInt16) -> String {
    "$" + String(format: "%04X", value)
}

private func hex8(_ value: UInt8) -> String {
    "$" + String(format: "%02X", value)
}
