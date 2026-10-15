import XCTest
@testable import Emu6502

final class CPUHeldReadTests: XCTestCase {
    private final class RecordingBus: Bus {
        var memory = [UInt8](repeating: 0xFF, count: 65536)
        var reads: [UInt16] = []
        func read(_ address: UInt16) -> UInt8 {
            reads.append(address)
            return memory[Int(address)]
        }
        func write(_ address: UInt16, value: UInt8) { memory[Int(address)] = value }
    }

    func testEveryOpcodeHeldReadUsesSameAddressAsItsUnstalledMicrocycle() {
        for index: UInt8 in [0, 1] {
            for status: UInt8 in [0x20, 0xEF] {
                for opcode in UInt8.min...UInt8.max {
                    let bus = RecordingBus()
                    let cpu = CPU6502(bus: bus)
                    cpu.pc = 0x06FD
                    cpu.x = index
                    cpu.y = index
                    cpu.p = status
                    bus.memory[0x06FD] = opcode
                    for _ in 0..<12 {
                        checkHeldRead(cpu, bus: bus, context: String(format: "opcode=%02X cycle=%d", opcode, cpu.cycle))
                        if cpu.cycle == 0 || cpu.jammed { break }
                    }
                }
            }
        }
    }

    func testHeldInterruptAndResetReadsPreserveStackAndVectorAddresses() {
        for kind: CPU6502.InterruptKind in [.irq, .nmi, .reset] {
            let bus = RecordingBus()
            let cpu = CPU6502(bus: bus)
            cpu.pc = 0x0600
            cpu.beginInterrupt(kind)
            for _ in 1...6 { checkHeldRead(cpu, bus: bus, context: "interrupt cycle=\(cpu.cycle)") }
            XCTAssertFalse(cpu.servicingInterrupt)
        }
    }

    private func checkHeldRead(_ cpu: CPU6502, bus: RecordingBus, context: String) {
        guard cpu.currentCycleIsRead() else { cpu.tick(); return }
        let before = [Int(cpu.pc), Int(cpu.sp), Int(cpu.p), Int(cpu.a), Int(cpu.x), Int(cpu.y),
                      cpu.cycle, Int(cpu.addr), Int(cpu.data), Int(cpu.pointer), Int(cpu.baseAddr)]
        cpu.setRDYLine(high: false)
        bus.reads.removeAll(keepingCapacity: true)
        cpu.tick(busAvailable: false)
        XCTAssertTrue(bus.reads.isEmpty, context)
        cpu.tick()
        cpu.tick()
        let held = bus.reads
        XCTAssertEqual(held.count, 2, context)
        XCTAssertEqual([Int(cpu.pc), Int(cpu.sp), Int(cpu.p), Int(cpu.a), Int(cpu.x), Int(cpu.y),
                        cpu.cycle, Int(cpu.addr), Int(cpu.data), Int(cpu.pointer), Int(cpu.baseAddr)], before, context)
        cpu.setRDYLine(high: true)
        bus.reads.removeAll(keepingCapacity: true)
        cpu.tick()
        XCTAssertEqual(bus.reads.count, 1, context)
        XCTAssertEqual(held, Array(repeating: bus.reads.first ?? 0, count: 2), context)
    }
}
