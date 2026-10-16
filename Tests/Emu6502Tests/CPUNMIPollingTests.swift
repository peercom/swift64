import XCTest
@testable import Emu6502

final class CPUNMIPollingTests: XCTestCase {
    func testNMIUsesThePenultimateCycleInsteadOfTheNextOpcodeBoundary() {
        let programs: [([UInt8], Int)] = [
            ([0xEA], 2),
            ([0x4C, 0x03, 0x06], 3),
            ([0xAD, 0, 0x20], 4),
            ([0x8D, 0, 0x20], 4),
            ([0xEE, 0, 0x20], 6),
            ([0xBD, 0xFF, 0x20], 5)
        ]
        for (program, clocks) in programs {
            for arrival in 0...clocks {
                let (cpu, _) = makeCPU(program + [0xEA, 0xEA])
                cpu.setFlag(Flags.interrupt, true) // NMI ignores the I flag.
                cpu.x = 1
                for clock in 0..<clocks {
                    if clock == arrival { cpu.setNMILine(high: true) }
                    cpu.tick()
                }
                XCTAssertEqual(cpu.cycle, 0)
                if arrival == clocks { cpu.setNMILine(high: true) }
                cpu.tick()
                XCTAssertEqual(cpu.servicingInterrupt, arrival <= clocks - 2,
                               "opcode \(program[0]), arrival \(arrival)")
            }
        }
    }

    func testLateTransientNMIRemainsLatchedThroughTheNextInstruction() {
        let (cpu, _) = makeCPU([0xEA, 0xA9, 0x42, 0xEA])
        cpu.tick()
        cpu.setNMILine(high: true)
        cpu.tick()
        cpu.setNMILine(high: false)
        cpu.tick()
        XCTAssertFalse(cpu.servicingInterrupt)
        cpu.tick()
        XCTAssertEqual(cpu.a, 0x42)
        cpu.tick()
        XCTAssertTrue(cpu.servicingInterrupt)
    }

    func testNMIBranchPollingWindows() {
        for taken in [false, true] {
            for crossing in [false, true] {
                let clocks = taken ? (crossing ? 4 : 3) : 2
                for arrival in 0...clocks {
                    let address: UInt16 = crossing ? 0x06FC : 0x0600
                    let (cpu, bus) = makeCPU([0xD0, 4, 0xEA, 0xEA], at: address)
                    bus.memory[Int(address) + 6] = 0xEA
                    cpu.setFlag(Flags.zero, !taken)
                    for clock in 0..<clocks {
                        if clock == arrival { cpu.setNMILine(high: true) }
                        cpu.tick()
                    }
                    if arrival == clocks { cpu.setNMILine(high: true) }
                    cpu.tick()
                    XCTAssertEqual(cpu.servicingInterrupt,
                                   arrival == 0 || (taken && crossing && arrival <= 2),
                                   "taken=\(taken), crossing=\(crossing), arrival=\(arrival)")
                }
            }
        }
    }

    func testNMIPollingContinuesDuringHeldReads() {
        let (cpu, _) = makeCPU([0xEA, 0xEA])
        cpu.tick()
        cpu.setRDYLine(high: false)
        cpu.setNMILine(high: true)
        for _ in 0..<4 { cpu.tick() }
        cpu.setNMILine(high: false)
        cpu.setRDYLine(high: true)
        cpu.tick()
        cpu.tick()
        XCTAssertTrue(cpu.servicingInterrupt)
    }

    func testPolledNMISurvivesHeldOpcodeFetch() {
        let (cpu, _) = makeCPU([0xEA, 0xEA])
        cpu.setNMILine(high: true)
        cpu.tick()
        cpu.tick()
        cpu.setNMILine(high: false)
        cpu.setRDYLine(high: false)
        for _ in 0..<4 { cpu.tick() }
        cpu.setRDYLine(high: true)
        cpu.tick()
        XCTAssertTrue(cpu.servicingInterrupt)
    }
}
