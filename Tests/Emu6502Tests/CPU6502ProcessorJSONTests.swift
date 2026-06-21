import XCTest
import Emu6502
import Foundation

private final class ProcessorJSONRAMBus: Bus {
    var memory = [UInt8](repeating: 0, count: 0x10000)

    func read(_ address: UInt16) -> UInt8 {
        memory[Int(address)]
    }

    func write(_ address: UInt16, value: UInt8) {
        memory[Int(address)] = value
    }
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
        XCTAssertTrue(aggregate.failureSummary.contains("second-fails"))
        XCTAssertTrue(aggregate.summaries[0].sourcePath.hasSuffix("a9.json"))
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
            failFast: failFast
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

private struct ProcessorJSONAggregateSummary: Codable, Equatable {
    var formatVersion: Int = 1
    var runnerName: String = "CPU6502ProcessorJSONTests"
    let files: Int
    let totalInFiles: Int
    let executed: Int
    let passed: Int
    let failed: Int
    let summaries: [ProcessorJSONRunSummary]

    init(summaries: [ProcessorJSONRunSummary]) {
        self.files = summaries.count
        self.totalInFiles = summaries.reduce(0) { $0 + $1.totalInFile }
        self.executed = summaries.reduce(0) { $0 + $1.executed }
        self.passed = summaries.reduce(0) { $0 + $1.passed }
        self.failed = summaries.reduce(0) { $0 + $1.failed }
        self.summaries = summaries
    }

    var failureSummary: String {
        let failures = summaries.compactMap(\.firstFailure)
        guard !failures.isEmpty else {
            return "No ProcessorTests JSON failures."
        }
        return failures.map { failure in
            "\(failure.sourcePath) \(failure.index) \(failure.name): \(failure.mismatches.joined(separator: "; "))"
        }.joined(separator: "\n")
    }
}

private struct ProcessorJSONRunSummary: Codable, Equatable {
    var formatVersion: Int = 1
    var runnerName: String = "CPU6502ProcessorJSONTests"
    let sourcePath: String
    let totalInFile: Int
    let startIndex: Int
    let limit: Int?
    let strictCycleCount: Bool
    let recordPassingCases: Bool
    let executed: Int
    let passed: Int
    let failed: Int
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

    if opcodeList.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "all" {
        return try processorJSONAllInputFiles(in: URL(fileURLWithPath: directory))
    }

    return opcodeList
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
        .map { opcode in
            let fileName = opcode.hasSuffix(".json") ? opcode : "\(opcode).json"
            return URL(fileURLWithPath: directory).appendingPathComponent(fileName)
        }
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

private func decodeProcessorJSONCases(at url: URL) throws -> [ProcessorJSONCase] {
    try JSONDecoder().decode([ProcessorJSONCase].self, from: Data(contentsOf: url))
}

private func runProcessorJSONInputs(
    urls: [URL],
    startIndex: Int,
    limit: Int?,
    strictCycleCount: Bool,
    recordPassingCases: Bool,
    failFast: Bool
) throws -> ProcessorJSONAggregateSummary {
    var summaries: [ProcessorJSONRunSummary] = []
    summaries.reserveCapacity(urls.count)

    for url in urls {
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

    return ProcessorJSONAggregateSummary(summaries: summaries)
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
    let bus = ProcessorJSONRAMBus()
    try applyProcessorJSONRAM(test.initial.ram, to: bus)

    let cpu = CPU6502(bus: bus)
    cpu.pc = try UInt16(processorJSONValue: test.initial.pc, field: "initial.pc")
    cpu.sp = try UInt8(processorJSONValue: test.initial.s, field: "initial.s")
    cpu.a = try UInt8(processorJSONValue: test.initial.a, field: "initial.a")
    cpu.x = try UInt8(processorJSONValue: test.initial.x, field: "initial.x")
    cpu.y = try UInt8(processorJSONValue: test.initial.y, field: "initial.y")
    cpu.p = try UInt8(processorJSONValue: test.initial.p, field: "initial.p")

    let elapsedCycles = runOneProcessorJSONInstruction(cpu)
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

private func runOneProcessorJSONInstruction(_ cpu: CPU6502) -> Int {
    var elapsedCycles = 0
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

    return mismatches
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
