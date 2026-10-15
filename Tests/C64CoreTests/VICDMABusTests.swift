import XCTest
@testable import C64Core

final class VICDMABusTests: XCTestCase {
    private func machine(_ profile: MachineProfile) -> C64 {
        let c64 = C64(machineProfile: profile)
        c64.trueDriveEmulationMode = .off
        c64.kernalTraps.enabled = false
        c64.vic.recordsBusAccessTraces = false
        c64.vic.rasterLine = 51
        c64.vic.badLineDENLatched = true
        c64.vic.controlReg1 = 0x18
        return c64
    }

    func testLateDMAUsesHeldOpcodeColorUntilAECGrantsTheBus() {
        for profile in [MachineProfile.palC64, .ntscC64] {
            for opcode: UInt8 in [0xA0, 0xA9, 0xEA] {
                let c64 = machine(profile)
                c64.vic.rasterCycle = 17
                c64.cpu.pc = 0x0600
                c64.cpu.a = 0x13
                c64.memory.ram.replaceSubrange(0x0600..<0x0604, with: [0x8D, 0x11, 0xD0, opcode])
                c64.memory.ram[0x0403] = 0x42
                c64.memory.colorRAM[3] = 7
                var heldReadCycles: [Int] = []
                c64.memory.onCPURead = { [weak c64] address, _ in
                    guard address == 0x0603, let c64 else { return }
                    heldReadCycles.append(c64.vic.rasterCycle)
                    XCTAssertFalse(c64.vic.aecLineLow)
                    XCTAssertEqual(c64.vic.busOwner, .cpu)
                }
                for _ in 0..<4 { c64.tickOneCycle() }
                XCTAssertFalse(c64.vic.badLine)
                for _ in 0..<3 { c64.tickOneCycle() }
                XCTAssertEqual(heldReadCycles, [21, 22, 23])
                XCTAssertEqual(Array(c64.vic.lineBuffer[0..<3]), [0xFF, 0xFF, 0xFF])
                XCTAssertEqual(Array(c64.vic.colorBuffer[0..<3]), Array(repeating: opcode & 15, count: 3))
                XCTAssertTrue(c64.vic.aecLineLow)
                XCTAssertEqual(c64.vic.busOwner, .vicBadLine)
                c64.tickOneCycle()
                XCTAssertEqual(heldReadCycles.count, 3)
                XCTAssertEqual(c64.vic.lineBuffer[3], 0x42)
                XCTAssertEqual(c64.vic.colorBuffer[3], 7)
                XCTAssertEqual(c64.cpu.pc, 0x0603)
                XCTAssertEqual(c64.cpu.cycle, 0)
            }
        }
    }

    func testHeldOperandReadSuppliesColorRatherThanPeekingAtPC() {
        let c64 = machine(.palC64)
        c64.cpu.pc = 0x0600
        c64.memory.ram.replaceSubrange(0x0600..<0x0604, with: [0xAD, 0x00, 0x20, 0xEA])
        c64.memory.ram[0x2000] = 0xB5
        for _ in 0..<3 { c64.cpu.tick() }
        c64.vic.rasterCycle = 14
        c64.vic.writeRegister(0x11, value: 0x1B)
        for _ in 0..<3 { c64.tickOneCycle() }
        XCTAssertEqual(c64.vic.colorBuffer[0], 5)
        XCTAssertEqual(c64.cpu.cycle, 3)
        XCTAssertEqual(c64.cpu.a, 0)
    }
}
