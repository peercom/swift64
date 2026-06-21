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
            binaryPath: "/tmp/6502_functional_test.bin",
            binarySize: 0x1000,
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
        XCTAssertEqual(decoded.binaryPath, "/tmp/6502_functional_test.bin")
        XCTAssertEqual(decoded.binarySize, 0x1000)
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
                try writeCPUFunctionalRunRecord(
                    cpuFunctionalRunRecord(
                        binaryPath: binaryPath,
                        binarySize: data.count,
                        loadAddress: loadAddress,
                        startPC: startPC,
                        successPC: successPC,
                        maxCycles: maxCycles,
                        passed: false,
                        cpu: cpu,
                        elapsedCycles: cycle + 1,
                        reason: "CPU jammed"
                    ),
                    to: resultURL
                )
                XCTFail("CPU jammed at PC=$\(String(cpu.pc, radix: 16)) after \(cycle + 1) cycles")
                return
            }

            if cpu.cycle == 0 {
                if cpu.pc == previousPC {
                    samePCCount += 1
                } else {
                    previousPC = cpu.pc
                    samePCCount = 0
                }

                if cpu.pc == successPC && samePCCount >= 2 {
                    try writeCPUFunctionalRunRecord(
                        cpuFunctionalRunRecord(
                            binaryPath: binaryPath,
                            binarySize: data.count,
                            loadAddress: loadAddress,
                            startPC: startPC,
                            successPC: successPC,
                            maxCycles: maxCycles,
                            passed: true,
                            cpu: cpu,
                            elapsedCycles: cycle + 1,
                            reason: "success self-loop reached"
                        ),
                        to: resultURL
                    )
                    return
                }
            }
        }

        try writeCPUFunctionalRunRecord(
            cpuFunctionalRunRecord(
                binaryPath: binaryPath,
                binarySize: data.count,
                loadAddress: loadAddress,
                startPC: startPC,
                successPC: successPC,
                maxCycles: maxCycles,
                passed: false,
                cpu: cpu,
                elapsedCycles: maxCycles,
                reason: "success self-loop not reached"
            ),
            to: resultURL
        )
        XCTFail("Functional binary did not reach success self-loop PC=$\(String(successPC, radix: 16)) within \(maxCycles) cycles; final PC=$\(String(cpu.pc, radix: 16))")
    }
}

private struct CPUFunctionalRunRecord: Codable, Equatable {
    static let currentFormatVersion = 1

    var formatVersion: Int = CPUFunctionalRunRecord.currentFormatVersion
    var runnerName: String = "CPU6502ConformanceTests"
    let binaryPath: String
    let binarySize: Int
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

private func cpuFunctionalRunRecord(
    binaryPath: String,
    binarySize: Int,
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
        binaryPath: binaryPath,
        binarySize: binarySize,
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

private func writeCPUFunctionalRunRecord(_ record: CPUFunctionalRunRecord, to url: URL?) throws {
    guard let url else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try encoder.encode(record).write(to: url, options: .atomic)
}

private func hex16(_ value: UInt16) -> String {
    "$" + String(format: "%04X", value)
}

private func hex8(_ value: UInt8) -> String {
    "$" + String(format: "%02X", value)
}

private extension UInt16 {
    init?(hexEnvironment value: String?) {
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
