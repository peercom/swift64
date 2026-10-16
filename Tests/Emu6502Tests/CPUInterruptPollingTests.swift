import XCTest
@testable import Emu6502

final class CPUInterruptPollingTests: XCTestCase {
    private final class IRQBus: Bus {
        let ram = RAMBus()
        var onRead: ((UInt16) -> Void)?
        var onWrite: ((UInt16, UInt8) -> Void)?

        func read(_ address: UInt16) -> UInt8 {
            let value = ram.read(address)
            onRead?(address)
            return value
        }

        func write(_ address: UInt16, value: UInt8) {
            ram.write(address, value: value)
            onWrite?(address, value)
        }
    }

    func testRMWAcknowledgementCannotEraseTheSameCycleIRQSample() {
        // VIC $D019 is write-one-to-clear. Both official and undocumented
        // RMW instructions must retain an IRQ sampled before the dummy write.
        for opcode: UInt8 in [0x0E, 0x2E, 0x4E, 0x6E, 0xCE, 0xEE,
                              0x0F, 0x2F, 0x4F, 0x6F, 0xCF, 0xEF] {
            let bus = IRQBus()
            bus.ram.loadProgram([opcode, 0x00, 0x20, 0xEA, 0xEA])
            let cpu = CPU6502(bus: bus)
            cpu.powerOn()
            cpu.setFlag(Flags.interrupt, false)
            var writes = 0
            bus.onWrite = { [weak cpu] address, _ in
                guard address == 0x2000 else { return }
                writes += 1
                cpu?.irqLine = false
            }
            for _ in 0..<4 { cpu.tick() }
            cpu.irqLine = true
            cpu.tick() // Penultimate cycle: dummy write acknowledges the IRQ.
            XCTAssertFalse(cpu.irqLine)
            cpu.tick()
            XCTAssertEqual(writes, 2)
            cpu.tick()
            XCTAssertTrue(cpu.servicingInterrupt, String(format: "RMW %02X lost its polled IRQ", opcode))
        }
    }

    func testIRQAssertedByDummyWriteDoesNotRetroactivelyEnterItsPollingWindow() {
        let bus = IRQBus()
        bus.ram.loadProgram([0xEE, 0x00, 0x20, 0xEA, 0xEA])
        let cpu = CPU6502(bus: bus)
        cpu.powerOn()
        cpu.setFlag(Flags.interrupt, false)
        bus.onWrite = { [weak cpu] address, _ in
            if address == 0x2000 { cpu?.irqLine = true }
        }
        for _ in 0..<6 { cpu.tick() }
        cpu.tick()
        XCTAssertFalse(cpu.servicingInterrupt)
        XCTAssertEqual(cpu.pc, 0x0604)
        cpu.tick()
        cpu.tick()
        XCTAssertTrue(cpu.servicingInterrupt)
    }

    func testReadToClearSideEffectCannotEraseThePenultimateCycleIRQSample() {
        let bus = IRQBus()
        bus.ram.loadProgram([0xBD, 0xFF, 0x20, 0xEA])
        let cpu = CPU6502(bus: bus)
        cpu.powerOn()
        cpu.x = 1
        cpu.setFlag(Flags.interrupt, false)
        bus.onRead = { [weak cpu] address in
            if address == 0x2000 { cpu?.irqLine = false }
        }
        for _ in 0..<3 { cpu.tick() }
        cpu.irqLine = true
        cpu.tick() // Wrong-page read, before the final data read at $2100.
        XCTAssertFalse(cpu.irqLine)
        cpu.tick()
        cpu.tick()
        XCTAssertTrue(cpu.servicingInterrupt)
    }

    func testIRQPinMustReachPenultimateCycleToInterruptNextOpcode() {
        let programs: [([UInt8], Int)] = [
            ([0xEA], 2),                       // NOP
            ([0xAD, 0x00, 0x20], 4),           // LDA absolute
            ([0x8D, 0x00, 0x20], 4),           // STA absolute
            ([0xEE, 0x00, 0x20], 6),           // INC absolute
            ([0xBD, 0xFF, 0x20], 5)            // LDA absolute,X crossing page
        ]
        for (program, count) in programs {
            for arrival in 0...count {
                let (cpu, _) = makeCPU(program + [0xEA, 0xEA])
                cpu.setFlag(Flags.interrupt, false)
                cpu.x = 1
                for clock in 0..<count {
                    if clock == arrival { cpu.irqLine = true }
                    cpu.tick()
                }
                XCTAssertEqual(cpu.cycle, 0)
                if arrival == count { cpu.irqLine = true }
                cpu.tick()
                XCTAssertEqual(cpu.servicingInterrupt, arrival <= count - 2,
                               "opcode \(program[0]), IRQ arrival \(arrival)")
            }
        }
    }

    func testPolledIRQSurvivesPinReleaseBeforeOpcodeBoundary() {
        let (cpu, _) = makeCPU([0xEA, 0xEA])
        cpu.setFlag(Flags.interrupt, false)
        cpu.irqLine = true
        cpu.tick()
        cpu.irqLine = false
        cpu.tick()
        cpu.tick()
        XCTAssertTrue(cpu.servicingInterrupt)
    }

    func testLateIRQWaitsForNextInstruction() {
        let (cpu, _) = makeCPU([0xEA, 0xA9, 0x42, 0xEA])
        cpu.setFlag(Flags.interrupt, false)
        cpu.tick()
        cpu.irqLine = true
        cpu.tick()
        cpu.tick()
        XCTAssertFalse(cpu.servicingInterrupt)
        cpu.tick()
        XCTAssertEqual(cpu.a, 0x42)
        cpu.tick()
        XCTAssertTrue(cpu.servicingInterrupt)
    }

    func testBranchPollingWindows() {
        for taken in [false, true] {
            for crossPage in [false, true] {
                let count = taken ? (crossPage ? 4 : 3) : 2
                for arrival in 0...count {
                    let address: UInt16 = crossPage ? 0x06FC : 0x0600
                    let (cpu, bus) = makeCPU([0xD0, 4, 0xEA, 0xEA], at: address)
                    bus.memory[Int(address) + 6] = 0xEA
                    cpu.setFlag(Flags.zero, !taken)
                    cpu.setFlag(Flags.interrupt, false)
                    for clock in 0..<count {
                        if clock == arrival { cpu.irqLine = true }
                        cpu.tick()
                    }
                    XCTAssertEqual(cpu.cycle, 0)
                    if arrival == count { cpu.irqLine = true }
                    cpu.tick()
                    let expected = arrival == 0 || (taken && crossPage && arrival <= 2)
                    XCTAssertEqual(cpu.servicingInterrupt, expected,
                                   "taken=\(taken), pageCross=\(crossPage), arrival=\(arrival)")
                }
            }
        }
    }

    func testIRQPollingContinuesDuringRDYStallBeforeFinalCycle() {
        let (cpu, _) = makeCPU([0xEA, 0xEA])
        cpu.setFlag(Flags.interrupt, false)
        cpu.tick()
        cpu.setRDYLine(high: false)
        cpu.irqLine = true
        for _ in 0..<4 { cpu.tick() }
        XCTAssertEqual(cpu.cycle, 1)
        cpu.setRDYLine(high: true)
        cpu.tick()
        cpu.tick()
        XCTAssertTrue(cpu.servicingInterrupt)
    }

    func testCommittedIRQSurvivesRDYStallAtOpcodeBoundary() {
        let (cpu, _) = makeCPU([0xEA, 0xEA])
        cpu.setFlag(Flags.interrupt, false)
        cpu.irqLine = true
        cpu.tick()
        cpu.tick()
        cpu.irqLine = false
        cpu.setRDYLine(high: false)
        for _ in 0..<4 { cpu.tick() }
        XCTAssertEqual(cpu.cycle, 0)
        cpu.setRDYLine(high: true)
        cpu.tick()
        XCTAssertTrue(cpu.servicingInterrupt)
    }

    func testSEIIgnoresIRQThatArrivesAfterItsPollingWindow() {
        let (cpu, _) = makeCPU([0x78, 0xEA, 0xEA])
        cpu.setFlag(Flags.interrupt, false)
        cpu.tick()
        cpu.irqLine = true
        cpu.tick()
        for _ in 0..<4 { cpu.tick() }
        XCTAssertFalse(cpu.servicingInterrupt)
        XCTAssertEqual(cpu.pc, 0x0603)
    }
}
