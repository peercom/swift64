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
            successPC: "$3469",
            maxCycles: 100_000_000,
            passed: false,
            jammed: true,
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
        XCTAssertEqual(decoded.successPC, "$3469")
        XCTAssertEqual(decoded.maxCycles, 100_000_000)
        XCTAssertEqual(decoded.passed, false)
        XCTAssertEqual(decoded.jammed, true)
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
                maxCycles: 64
            ),
            CPUFunctionalFixture(
                id: "jam",
                name: "Synthetic KIL",
                path: jamURL.lastPathComponent,
                loadAddress: "$0400",
                startPC: "$0400",
                successPC: "$0400",
                maxCycles: 64
            ),
        ])

        let summary = try runCPUFunctionalManifest(manifest, relativeTo: directory)

        XCTAssertEqual(summary.total, 2)
        XCTAssertEqual(summary.passed, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.jammed, 1)
        XCTAssertEqual(summary.timedOut, 0)
        XCTAssertEqual(summary.records.map(\.fixtureID), ["self-loop", "jam"])
        XCTAssertEqual(summary.records[0].passed, true)
        XCTAssertEqual(summary.records[0].reason, "success self-loop reached")
        XCTAssertEqual(summary.records[1].passed, false)
        XCTAssertEqual(summary.records[1].jammed, true)
        XCTAssertEqual(summary.records[1].reason, "CPU jammed")
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
            maxCycles: maxCycles
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

        XCTAssertEqual(summary.failed, 0, summary.failureSummary)
    }
}

private struct CPUFunctionalManifest: Codable, Equatable {
    let fixtures: [CPUFunctionalFixture]
}

private struct CPUFunctionalFixture: Codable, Equatable {
    let id: String?
    let name: String?
    let path: String
    let loadAddress: String?
    let startPC: String?
    let successPC: String
    let maxCycles: Int?

    func binaryURL(relativeTo baseURL: URL?) -> URL {
        if (path as NSString).isAbsolutePath {
            return URL(fileURLWithPath: path)
        }
        return (baseURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .appendingPathComponent(path)
    }
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
    let successPC: String
    let maxCycles: Int
    let passed: Bool
    let jammed: Bool
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
    let total: Int
    let passed: Int
    let failed: Int
    let jammed: Int
    let timedOut: Int
    let totalElapsedCycles: Int
    let records: [CPUFunctionalRunRecord]

    var failureSummary: String {
        let failures = records.filter { !$0.passed }
        guard !failures.isEmpty else {
            return "No CPU functional failures."
        }
        return failures.map { record in
            let idText = record.fixtureID.map { "\($0) " } ?? ""
            return "\(idText)\(record.binaryPath) pc=\(record.finalPC) cycles=\(record.elapsedCycles) reason=\(record.reason)"
        }.joined(separator: "\n")
    }
}

private func runCPUFunctionalManifest(
    _ manifest: CPUFunctionalManifest,
    relativeTo baseURL: URL?
) throws -> CPUFunctionalRunSummary {
    var records: [CPUFunctionalRunRecord] = []
    records.reserveCapacity(manifest.fixtures.count)

    for fixture in manifest.fixtures {
        let binaryURL = fixture.binaryURL(relativeTo: baseURL)
        let data = try Data(contentsOf: binaryURL)
        let loadAddress = try parseHex16(fixture.loadAddress, default: 0x0000, field: "loadAddress")
        let startPC = try parseOptionalHex16(fixture.startPC, field: "startPC")
        let successPC = try parseRequiredHex16(fixture.successPC, field: "successPC")
        let maxCycles = fixture.maxCycles ?? 100_000_000

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
            maxCycles: maxCycles
        ))
    }

    return CPUFunctionalRunSummary(
        total: records.count,
        passed: records.filter(\.passed).count,
        failed: records.filter { !$0.passed }.count,
        jammed: records.filter(\.jammed).count,
        timedOut: records.filter { !$0.passed && !$0.jammed }.count,
        totalElapsedCycles: records.reduce(0) { $0 + $1.elapsedCycles },
        records: records
    )
}

private func runCPUFunctionalBinary(
    fixtureID: String?,
    fixtureName: String?,
    binaryPath: String,
    data: Data,
    loadAddress: UInt16,
    startPC: UInt16?,
    successPC: UInt16,
    maxCycles: Int
) -> CPUFunctionalRunRecord {
    let bus = ConformanceRAMBus()
    bus.loadBinary(data, at: loadAddress)
    let cpu = CPU6502(bus: bus)
    if let startPC {
        cpu.pc = startPC
        cpu.sp = 0xFD
        cpu.p = Flags.unused | Flags.interrupt
    } else {
        cpu.powerOn()
    }

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
                passed: false,
                cpu: cpu,
                elapsedCycles: cycle + 1,
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
                return cpuFunctionalRunRecord(
                    fixtureID: fixtureID,
                    fixtureName: fixtureName,
                    binaryPath: binaryPath,
                    data: data,
                    loadAddress: loadAddress,
                    startPC: startPC,
                    successPC: successPC,
                    maxCycles: maxCycles,
                    passed: true,
                    cpu: cpu,
                    elapsedCycles: cycle + 1,
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
        passed: false,
        cpu: cpu,
        elapsedCycles: maxCycles,
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
    passed: Bool,
    cpu: CPU6502,
    elapsedCycles: Int,
    reason: String
) -> CPUFunctionalRunRecord {
    CPUFunctionalRunRecord(
        fixtureID: fixtureID,
        fixtureName: fixtureName,
        binaryPath: binaryPath,
        binarySize: data.count,
        binaryFNV1A64: fnv1a64(data),
        loadAddress: hex16(loadAddress),
        startPC: startPC.map(hex16),
        successPC: hex16(successPC),
        maxCycles: maxCycles,
        passed: passed,
        jammed: cpu.jammed,
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
