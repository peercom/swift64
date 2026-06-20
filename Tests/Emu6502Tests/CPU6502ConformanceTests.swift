import XCTest
import Emu6502

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
                    return
                }
            }
        }

        XCTFail("Functional binary did not reach success self-loop PC=$\(String(successPC, radix: 16)) within \(maxCycles) cycles; final PC=$\(String(cpu.pc, radix: 16))")
    }
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
