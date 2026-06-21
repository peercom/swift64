import XCTest
@testable import Emu6502

/// Simple 64K RAM bus for testing.
final class RAMBus: Bus {
    var memory = [UInt8](repeating: 0, count: 0x10000)

    func read(_ address: UInt16) -> UInt8 {
        return memory[Int(address)]
    }

    func write(_ address: UInt16, value: UInt8) {
        memory[Int(address)] = value
    }

    /// Load a program at the given address and set the reset vector to point there.
    func loadProgram(_ bytes: [UInt8], at address: UInt16 = 0x0600) {
        for (i, byte) in bytes.enumerated() {
            memory[Int(address) + i] = byte
        }
        // Set reset vector
        memory[0xFFFC] = UInt8(address & 0xFF)
        memory[0xFFFD] = UInt8(address >> 8)
    }
}

/// Helper to create a CPU, load a program, power on, and run until BRK or N cycles.
func makeCPU(_ bytes: [UInt8], at address: UInt16 = 0x0600) -> (CPU6502, RAMBus) {
    let bus = RAMBus()
    bus.loadProgram(bytes, at: address)
    let cpu = CPU6502(bus: bus)
    cpu.powerOn()
    return (cpu, bus)
}

/// Run until BRK (opcode 0x00) is fetched or maxCycles is reached.
func runUntilBRK(_ cpu: CPU6502, maxCycles: Int = 10000) {
    for _ in 0..<maxCycles {
        cpu.tick()
        // After tick, if cycle==1 and opcode==0x00, we just fetched BRK
        if cpu.cycle == 0 && cpu.opcode == 0x00 {
            break
        }
    }
}

/// Run a fixed number of instructions (not cycles).
func runInstructions(_ cpu: CPU6502, count: Int, maxCycles: Int = 100000) {
    var instructionCount = 0
    for _ in 0..<maxCycles {
        cpu.tick()
        if cpu.cycle == 0 {
            instructionCount += 1
            if instructionCount >= count { break }
        }
    }
}

final class CPU6502Tests: XCTestCase {

    // MARK: - LDA

    func testLDAImmediate() {
        let (cpu, _) = makeCPU([0xA9, 0x42])  // LDA #$42
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.a, 0x42)
        XCTAssertFalse(cpu.getFlag(Flags.zero))
        XCTAssertFalse(cpu.getFlag(Flags.negative))
    }

    func testLDAImmediateZero() {
        let (cpu, _) = makeCPU([0xA9, 0x00])  // LDA #$00
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.a, 0x00)
        XCTAssertTrue(cpu.getFlag(Flags.zero))
        XCTAssertFalse(cpu.getFlag(Flags.negative))
    }

    func testLDAImmediateNegative() {
        let (cpu, _) = makeCPU([0xA9, 0x80])  // LDA #$80
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.a, 0x80)
        XCTAssertFalse(cpu.getFlag(Flags.zero))
        XCTAssertTrue(cpu.getFlag(Flags.negative))
    }

    func testLDAZeroPage() {
        let (cpu, bus) = makeCPU([0xA5, 0x10])  // LDA $10
        bus.memory[0x10] = 0x37
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.a, 0x37)
    }

    func testLDAAbsolute() {
        let (cpu, bus) = makeCPU([0xAD, 0x00, 0x20])  // LDA $2000
        bus.memory[0x2000] = 0xAB
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.a, 0xAB)
    }

    func testLDAAbsoluteX() {
        let (cpu, bus) = makeCPU([0xA2, 0x05, 0xBD, 0x00, 0x20])  // LDX #$05; LDA $2000,X
        bus.memory[0x2005] = 0xCD
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.a, 0xCD)
    }

    func testLDAIndirectY() {
        // LDY #$03; LDA ($40),Y
        let (cpu, bus) = makeCPU([0xA0, 0x03, 0xB1, 0x40])
        bus.memory[0x40] = 0x00
        bus.memory[0x41] = 0x20
        bus.memory[0x2003] = 0xEF
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.a, 0xEF)
    }

    // MARK: - STA

    func testSTAZeroPage() {
        let (cpu, bus) = makeCPU([0xA9, 0x55, 0x85, 0x10])  // LDA #$55; STA $10
        runInstructions(cpu, count: 2)
        XCTAssertEqual(bus.memory[0x10], 0x55)
    }

    func testSTAAbsolute() {
        let (cpu, bus) = makeCPU([0xA9, 0xAA, 0x8D, 0x00, 0x30])  // LDA #$AA; STA $3000
        runInstructions(cpu, count: 2)
        XCTAssertEqual(bus.memory[0x3000], 0xAA)
    }

    // MARK: - LDX, LDY, STX, STY

    func testLDXImmediate() {
        let (cpu, _) = makeCPU([0xA2, 0x99])
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.x, 0x99)
    }

    func testLDYImmediate() {
        let (cpu, _) = makeCPU([0xA0, 0x77])
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.y, 0x77)
    }

    func testSTXZeroPage() {
        let (cpu, bus) = makeCPU([0xA2, 0x33, 0x86, 0x20])
        runInstructions(cpu, count: 2)
        XCTAssertEqual(bus.memory[0x20], 0x33)
    }

    func testSTYZeroPage() {
        let (cpu, bus) = makeCPU([0xA0, 0x44, 0x84, 0x20])
        runInstructions(cpu, count: 2)
        XCTAssertEqual(bus.memory[0x20], 0x44)
    }

    // MARK: - Transfers

    func testTAX() {
        let (cpu, _) = makeCPU([0xA9, 0x42, 0xAA])  // LDA #$42; TAX
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.x, 0x42)
    }

    func testTAY() {
        let (cpu, _) = makeCPU([0xA9, 0x42, 0xA8])  // LDA #$42; TAY
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.y, 0x42)
    }

    func testTXA() {
        let (cpu, _) = makeCPU([0xA2, 0x55, 0x8A])  // LDX #$55; TXA
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.a, 0x55)
    }

    func testTSX() {
        let (cpu, _) = makeCPU([0xBA])  // TSX
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.x, cpu.sp)
    }

    // MARK: - ADC

    func testADCNoCarry() {
        let (cpu, _) = makeCPU([0xA9, 0x10, 0x69, 0x20])  // LDA #$10; ADC #$20
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.a, 0x30)
        XCTAssertFalse(cpu.getFlag(Flags.carry))
        XCTAssertFalse(cpu.getFlag(Flags.overflow))
    }

    func testADCWithCarry() {
        let (cpu, _) = makeCPU([0xA9, 0xFF, 0x69, 0x01])  // LDA #$FF; ADC #$01
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.a, 0x00)
        XCTAssertTrue(cpu.getFlag(Flags.carry))
        XCTAssertTrue(cpu.getFlag(Flags.zero))
    }

    func testADCOverflow() {
        // 0x50 + 0x50 = 0xA0, positive + positive = negative → overflow
        let (cpu, _) = makeCPU([0xA9, 0x50, 0x69, 0x50])
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.a, 0xA0)
        XCTAssertTrue(cpu.getFlag(Flags.overflow))
    }

    // MARK: - SBC

    func testSBCNoBorrow() {
        // SEC; LDA #$30; SBC #$10
        let (cpu, _) = makeCPU([0x38, 0xA9, 0x30, 0xE9, 0x10])
        runInstructions(cpu, count: 3)
        XCTAssertEqual(cpu.a, 0x20)
        XCTAssertTrue(cpu.getFlag(Flags.carry)) // no borrow
    }

    func testSBCWithBorrow() {
        // SEC; LDA #$10; SBC #$20
        let (cpu, _) = makeCPU([0x38, 0xA9, 0x10, 0xE9, 0x20])
        runInstructions(cpu, count: 3)
        XCTAssertEqual(cpu.a, 0xF0)
        XCTAssertFalse(cpu.getFlag(Flags.carry)) // borrow occurred
    }

    // MARK: - AND, ORA, EOR

    func testAND() {
        let (cpu, _) = makeCPU([0xA9, 0xFF, 0x29, 0x0F])  // LDA #$FF; AND #$0F
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.a, 0x0F)
    }

    func testORA() {
        let (cpu, _) = makeCPU([0xA9, 0xF0, 0x09, 0x0F])  // LDA #$F0; ORA #$0F
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.a, 0xFF)
    }

    func testEOR() {
        let (cpu, _) = makeCPU([0xA9, 0xFF, 0x49, 0xAA])  // LDA #$FF; EOR #$AA
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.a, 0x55)
    }

    // MARK: - Shifts and rotates

    func testASLAccumulator() {
        let (cpu, _) = makeCPU([0xA9, 0x40, 0x0A])  // LDA #$40; ASL A
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.a, 0x80)
        XCTAssertFalse(cpu.getFlag(Flags.carry))
    }

    func testASLCarry() {
        let (cpu, _) = makeCPU([0xA9, 0x80, 0x0A])  // LDA #$80; ASL A
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.a, 0x00)
        XCTAssertTrue(cpu.getFlag(Flags.carry))
    }

    func testLSR() {
        let (cpu, _) = makeCPU([0xA9, 0x02, 0x4A])  // LDA #$02; LSR A
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.a, 0x01)
        XCTAssertFalse(cpu.getFlag(Flags.carry))
    }

    func testROLWithCarry() {
        // SEC; LDA #$00; ROL A → should be 0x01
        let (cpu, _) = makeCPU([0x38, 0xA9, 0x00, 0x2A])
        runInstructions(cpu, count: 3)
        XCTAssertEqual(cpu.a, 0x01)
    }

    func testROR() {
        // SEC; LDA #$00; ROR A → should be 0x80
        let (cpu, _) = makeCPU([0x38, 0xA9, 0x00, 0x6A])
        runInstructions(cpu, count: 3)
        XCTAssertEqual(cpu.a, 0x80)
    }

    // MARK: - INC, DEC

    func testINCZeroPage() {
        let (cpu, bus) = makeCPU([0xE6, 0x10])  // INC $10
        bus.memory[0x10] = 0x41
        runInstructions(cpu, count: 1)
        XCTAssertEqual(bus.memory[0x10], 0x42)
    }

    func testDECZeroPage() {
        let (cpu, bus) = makeCPU([0xC6, 0x10])  // DEC $10
        bus.memory[0x10] = 0x42
        runInstructions(cpu, count: 1)
        XCTAssertEqual(bus.memory[0x10], 0x41)
    }

    func testINX() {
        let (cpu, _) = makeCPU([0xA2, 0xFE, 0xE8])  // LDX #$FE; INX
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.x, 0xFF)
    }

    func testDEY() {
        let (cpu, _) = makeCPU([0xA0, 0x01, 0x88])  // LDY #$01; DEY
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.y, 0x00)
        XCTAssertTrue(cpu.getFlag(Flags.zero))
    }

    // MARK: - Compare

    func testCMPEqual() {
        let (cpu, _) = makeCPU([0xA9, 0x42, 0xC9, 0x42])  // LDA #$42; CMP #$42
        runInstructions(cpu, count: 2)
        XCTAssertTrue(cpu.getFlag(Flags.zero))
        XCTAssertTrue(cpu.getFlag(Flags.carry))
    }

    func testCMPGreater() {
        let (cpu, _) = makeCPU([0xA9, 0x50, 0xC9, 0x42])  // LDA #$50; CMP #$42
        runInstructions(cpu, count: 2)
        XCTAssertFalse(cpu.getFlag(Flags.zero))
        XCTAssertTrue(cpu.getFlag(Flags.carry))
    }

    func testCMPLess() {
        let (cpu, _) = makeCPU([0xA9, 0x30, 0xC9, 0x42])  // LDA #$30; CMP #$42
        runInstructions(cpu, count: 2)
        XCTAssertFalse(cpu.getFlag(Flags.zero))
        XCTAssertFalse(cpu.getFlag(Flags.carry))
    }

    // MARK: - BIT

    func testBIT() {
        let (cpu, bus) = makeCPU([0xA9, 0xFF, 0x24, 0x10])  // LDA #$FF; BIT $10
        bus.memory[0x10] = 0xC0
        runInstructions(cpu, count: 2)
        XCTAssertFalse(cpu.getFlag(Flags.zero))  // $FF & $C0 != 0
        XCTAssertTrue(cpu.getFlag(Flags.negative))  // bit 7 of $C0
        XCTAssertTrue(cpu.getFlag(Flags.overflow))  // bit 6 of $C0
    }

    // MARK: - Branches

    func testBEQTaken() {
        // LDA #$00; BEQ +2; LDA #$FF; (target) LDX #$42
        let (cpu, _) = makeCPU([0xA9, 0x00, 0xF0, 0x02, 0xA9, 0xFF, 0xA2, 0x42])
        runInstructions(cpu, count: 3)
        XCTAssertEqual(cpu.a, 0x00)  // second LDA should be skipped
        XCTAssertEqual(cpu.x, 0x42)
    }

    func testBNENotTaken() {
        // LDA #$00; BNE +2; LDA #$42
        let (cpu, _) = makeCPU([0xA9, 0x00, 0xD0, 0x02, 0xA9, 0x42])
        runInstructions(cpu, count: 3)
        XCTAssertEqual(cpu.a, 0x42)  // branch not taken, so second LDA executes
    }

    func testBranchBackward() {
        // Loop: INX; CPX #$03; BNE Loop
        // At $0600: E8 E0 03 D0 FB
        let (cpu, _) = makeCPU([0xE8, 0xE0, 0x03, 0xD0, 0xFB])
        runInstructions(cpu, count: 9) // 3 iterations × 3 instructions
        XCTAssertEqual(cpu.x, 0x03)
    }

    // MARK: - JMP

    func testJMPAbsolute() {
        // JMP $0605; NOP; NOP; NOP; NOP; NOP; LDA #$42
        let (cpu, _) = makeCPU([0x4C, 0x05, 0x06, 0xEA, 0xEA, 0xA9, 0x42])
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.a, 0x42)
    }

    func testJMPIndirectPageBug() {
        // JMP ($20FF) — should wrap within page (read $20FF and $2000, not $2100)
        let (cpu, bus) = makeCPU([0x6C, 0xFF, 0x20])
        bus.memory[0x20FF] = 0x00
        bus.memory[0x2000] = 0x08  // should read from $2000, not $2100
        bus.memory[0x2100] = 0xFF  // wrong value if bug not emulated
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.pc, 0x0800)
    }

    // MARK: - JSR / RTS

    func testJSRRTS() {
        // $0600: JSR $0606
        // $0603: LDX #$FF  (return point)
        // $0605: BRK
        // $0606: LDA #$42  (subroutine)
        // $0608: RTS
        let (cpu, _) = makeCPU([
            0x20, 0x06, 0x06,   // JSR $0606
            0xA2, 0xFF,         // LDX #$FF
            0x00,               // BRK
            0xA9, 0x42,         // LDA #$42
            0x60                // RTS
        ])
        runInstructions(cpu, count: 4) // JSR, LDA, RTS, LDX
        XCTAssertEqual(cpu.a, 0x42)
        XCTAssertEqual(cpu.x, 0xFF)
    }

    // MARK: - Stack

    func testPHAPLA() {
        let (cpu, _) = makeCPU([0xA9, 0x42, 0x48, 0xA9, 0x00, 0x68])
        // LDA #$42; PHA; LDA #$00; PLA
        runInstructions(cpu, count: 4)
        XCTAssertEqual(cpu.a, 0x42)
    }

    func testPHPPLP() {
        // SEC; PHP; CLC; PLP
        let (cpu, _) = makeCPU([0x38, 0x08, 0x18, 0x28])
        runInstructions(cpu, count: 4)
        XCTAssertTrue(cpu.getFlag(Flags.carry))
    }

    // MARK: - BRK / RTI

    func testBRKRTI() {
        // Set up IRQ vector to point to handler at $0700
        // BRK skips the signature byte after it, so we need a padding byte
        let (cpu, bus) = makeCPU([0xA9, 0x42, 0x00, 0xEA, 0xA9, 0xFF])
        //                        LDA #$42   BRK  sig   LDA #$FF
        bus.memory[0xFFFE] = 0x00
        bus.memory[0xFFFF] = 0x07
        // Handler at $0700: LDX #$99; RTI
        bus.memory[0x0700] = 0xA2
        bus.memory[0x0701] = 0x99
        bus.memory[0x0702] = 0x40  // RTI
        runInstructions(cpu, count: 5)  // LDA, BRK, LDX, RTI, LDA
        XCTAssertEqual(cpu.a, 0xFF)  // continued after BRK+signature byte
        XCTAssertEqual(cpu.x, 0x99)
    }

    func testBRKPushesStatusWithBreakFlagSet() {
        let (cpu, bus) = makeCPU([0x00, 0xEA])
        bus.memory[0xFFFE] = 0x00
        bus.memory[0xFFFF] = 0x07

        runInstructions(cpu, count: 1)

        XCTAssertEqual(bus.memory[0x01FB] & Flags.brk, Flags.brk)
        XCTAssertEqual(bus.memory[0x01FB] & Flags.unused, Flags.unused)
    }

    func testIRQPushesStatusWithBreakFlagClear() {
        let (cpu, bus) = makeCPU([0xEA])
        bus.memory[0xFFFE] = 0x00
        bus.memory[0xFFFF] = 0x07
        cpu.setFlag(Flags.interrupt, false)
        cpu.irqLine = true

        runInstructions(cpu, count: 1)

        XCTAssertEqual(bus.memory[0x01FB] & Flags.brk, 0)
        XCTAssertEqual(bus.memory[0x01FB] & Flags.unused, Flags.unused)
    }

    func testNMIPushesStatusWithBreakFlagClear() {
        let (cpu, bus) = makeCPU([0xEA])
        bus.memory[0xFFFA] = 0x00
        bus.memory[0xFFFB] = 0x07
        cpu.setNMILine(high: true)

        runInstructions(cpu, count: 1)

        XCTAssertEqual(bus.memory[0x01FB] & Flags.brk, 0)
        XCTAssertEqual(bus.memory[0x01FB] & Flags.unused, Flags.unused)
    }

    func testNMIDuringBRKBeforeVectorFetchHijacksToNMIVectorWithBreakFlagSet() {
        let (cpu, bus) = makeCPU([0x00, 0xEA])
        bus.memory[0xFFFA] = 0x00
        bus.memory[0xFFFB] = 0x07
        bus.memory[0xFFFE] = 0x10
        bus.memory[0xFFFF] = 0x07
        bus.memory[0x0700] = 0xE8  // INX
        bus.memory[0x0710] = 0xC8  // INY

        for _ in 0..<5 { cpu.tick() }  // BRK fetch through pushed status.
        XCTAssertEqual(cpu.cycle, 5)

        cpu.setNMILine(high: true)
        cpu.tick()  // vector low, hijacked by NMI
        cpu.tick()  // vector high

        XCTAssertEqual(cpu.pc, 0x0700)
        XCTAssertEqual(bus.memory[0x01FB] & Flags.brk, Flags.brk)
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.x, 0x01)
        XCTAssertEqual(cpu.y, 0x00)
    }

    func testNMIAfterBRKVectorLowDoesNotHalfHijackAndRunsAfterFirstHandlerOpcode() {
        let (cpu, bus) = makeCPU([0x00, 0xEA])
        bus.memory[0xFFFA] = 0x00
        bus.memory[0xFFFB] = 0x07
        bus.memory[0xFFFE] = 0x34
        bus.memory[0xFFFF] = 0x12
        bus.memory[0x0700] = 0xC8  // INY
        bus.memory[0x1234] = 0xE8  // INX
        bus.memory[0x1235] = 0xEA  // NOP

        for _ in 0..<5 { cpu.tick() }  // BRK fetch through pushed status.
        XCTAssertEqual(cpu.cycle, 5)
        cpu.tick()  // IRQ/BRK vector low has already been fetched.
        XCTAssertEqual(cpu.cycle, 6)

        cpu.setNMILine(high: true)
        cpu.tick()  // vector high remains IRQ/BRK, not NMI.

        XCTAssertEqual(cpu.pc, 0x1234)
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.x, 0x01)
        XCTAssertEqual(cpu.y, 0x00)

        runInstructions(cpu, count: 1)  // deferred NMI sequence.
        XCTAssertEqual(cpu.pc, 0x0700)
        XCTAssertEqual(cpu.y, 0x00)
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.y, 0x01)
    }

    func testTransientNMIAfterBRKVectorLowIsMissedBeforeFirstHandlerOpcode() {
        let (cpu, bus) = makeCPU([0x00, 0xEA])
        bus.memory[0xFFFA] = 0x00
        bus.memory[0xFFFB] = 0x07
        bus.memory[0xFFFE] = 0x34
        bus.memory[0xFFFF] = 0x12
        bus.memory[0x0700] = 0xC8  // INY
        bus.memory[0x1234] = 0xE8  // INX
        bus.memory[0x1235] = 0xEA  // NOP

        for _ in 0..<5 { cpu.tick() }  // BRK fetch through pushed status.
        cpu.tick()  // IRQ/BRK vector low has already been fetched.

        cpu.setNMILine(high: true)
        cpu.setNMILine(high: false)
        cpu.tick()  // vector high remains IRQ/BRK.

        XCTAssertEqual(cpu.pc, 0x1234)
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.x, 0x01)
        XCTAssertEqual(cpu.y, 0x00)
        XCTAssertFalse(cpu.nmiPending)
    }

    func testNMIDuringIRQBeforeVectorFetchHijacksToNMIVectorWithBreakFlagClear() {
        let (cpu, bus) = makeCPU([0xEA])
        bus.memory[0xFFFA] = 0x00
        bus.memory[0xFFFB] = 0x07
        bus.memory[0xFFFE] = 0x10
        bus.memory[0xFFFF] = 0x07
        bus.memory[0x0700] = 0xE8  // INX
        bus.memory[0x0710] = 0xC8  // INY
        cpu.setFlag(Flags.interrupt, false)
        cpu.irqLine = true

        for _ in 0..<5 { cpu.tick() }  // IRQ start through pushed status.
        XCTAssertEqual(cpu.cycle, 5)

        cpu.setNMILine(high: true)
        cpu.tick()  // vector low, hijacked by NMI
        cpu.tick()  // vector high

        XCTAssertEqual(cpu.pc, 0x0700)
        XCTAssertEqual(bus.memory[0x01FB] & Flags.brk, 0)
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.x, 0x01)
        XCTAssertEqual(cpu.y, 0x00)
    }

    func testIRQRemainsPendingAfterNMIHijacksIRQVectorFetch() {
        let (cpu, bus) = makeCPU([0xEA])
        bus.memory[0xFFFA] = 0x00
        bus.memory[0xFFFB] = 0x07
        bus.memory[0xFFFE] = 0x10
        bus.memory[0xFFFF] = 0x07
        bus.memory[0x0700] = 0xE8  // INX
        bus.memory[0x0701] = 0x40  // RTI
        bus.memory[0x0710] = 0xC8  // INY
        cpu.setFlag(Flags.interrupt, false)
        cpu.irqLine = true

        for _ in 0..<5 { cpu.tick() }  // IRQ start through pushed status.
        cpu.setNMILine(high: true)
        cpu.tick()  // vector low, hijacked by NMI
        cpu.tick()  // vector high

        XCTAssertEqual(cpu.pc, 0x0700)

        runInstructions(cpu, count: 2)  // NMI handler INX, then RTI.
        XCTAssertEqual(cpu.x, 0x01)
        XCTAssertEqual(cpu.y, 0x00)

        runInstructions(cpu, count: 1)  // IRQ is still level-asserted.
        XCTAssertEqual(cpu.pc, 0x0710)
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.y, 0x01)
    }

    // MARK: - Flag instructions

    func testSECCLC() {
        let (cpu, _) = makeCPU([0x38, 0x18])  // SEC; CLC
        runInstructions(cpu, count: 1)
        XCTAssertTrue(cpu.getFlag(Flags.carry))
        runInstructions(cpu, count: 1)
        XCTAssertFalse(cpu.getFlag(Flags.carry))
    }

    func testSEICLI() {
        let (cpu, _) = makeCPU([0x58, 0x78])  // CLI; SEI
        runInstructions(cpu, count: 1)
        XCTAssertFalse(cpu.getFlag(Flags.interrupt))
        runInstructions(cpu, count: 1)
        XCTAssertTrue(cpu.getFlag(Flags.interrupt))
    }

    func testSEDCLD() {
        let (cpu, _) = makeCPU([0xF8, 0xD8])  // SED; CLD
        runInstructions(cpu, count: 1)
        XCTAssertTrue(cpu.getFlag(Flags.decimal))
        runInstructions(cpu, count: 1)
        XCTAssertFalse(cpu.getFlag(Flags.decimal))
    }

    // MARK: - NMI

    func testNMI() {
        let (cpu, bus) = makeCPU([0xEA, 0xEA, 0xEA])  // NOP; NOP; NOP
        bus.memory[0xFFFA] = 0x00
        bus.memory[0xFFFB] = 0x07
        bus.memory[0x0700] = 0xA9  // LDA #$42
        bus.memory[0x0701] = 0x42
        bus.memory[0x0702] = 0x40  // RTI

        runInstructions(cpu, count: 1)  // first NOP
        cpu.triggerNMI()
        // Next instruction boundary should service the NMI
        runInstructions(cpu, count: 3)  // NMI handler: LDA #$42, RTI, then NOP
        XCTAssertEqual(cpu.a, 0x42)
    }

    func testNMIHeldHighTriggersOnlyOnceUntilLineFallsAndRisesAgain() {
        let (cpu, bus) = makeCPU([0xEA, 0xEA, 0xEA, 0xEA, 0xEA])  // NOPs
        bus.memory[0xFFFA] = 0x00
        bus.memory[0xFFFB] = 0x07
        bus.memory[0x0700] = 0xE8  // INX
        bus.memory[0x0701] = 0x40  // RTI

        runInstructions(cpu, count: 1)

        cpu.setNMILine(high: true)
        cpu.run(cycles: 30)

        XCTAssertEqual(cpu.x, 0x01)
        XCTAssertTrue(cpu.nmiLine)

        cpu.run(cycles: 60)

        XCTAssertEqual(cpu.x, 0x01)

        cpu.setNMILine(high: false)
        cpu.setNMILine(high: true)
        cpu.run(cycles: 30)

        XCTAssertEqual(cpu.x, 0x02)
    }

    func testNMITakesPriorityOverSimultaneousIRQAndPendingIRQRunsAfterRTI() {
        let (cpu, bus) = makeCPU([0xEA, 0xEA, 0xEA])  // NOPs
        bus.memory[0xFFFA] = 0x00
        bus.memory[0xFFFB] = 0x07
        bus.memory[0xFFFE] = 0x10
        bus.memory[0xFFFF] = 0x07
        bus.memory[0x0700] = 0xE8  // INX
        bus.memory[0x0701] = 0x40  // RTI
        bus.memory[0x0710] = 0xC8  // INY
        bus.memory[0x0711] = 0x40  // RTI
        cpu.setFlag(Flags.interrupt, false)

        runInstructions(cpu, count: 1)
        cpu.setNMILine(high: true)
        cpu.irqLine = true

        runInstructions(cpu, count: 1)  // NMI sequence wins arbitration.
        XCTAssertEqual(cpu.pc, 0x0700)
        XCTAssertEqual(cpu.x, 0x00)
        XCTAssertEqual(cpu.y, 0x00)

        runInstructions(cpu, count: 2)  // NMI handler INX, then RTI.
        XCTAssertEqual(cpu.x, 0x01)
        XCTAssertEqual(cpu.y, 0x00)

        runInstructions(cpu, count: 1)  // IRQ sequence runs after RTI restores I clear.
        XCTAssertEqual(cpu.pc, 0x0710)

        runInstructions(cpu, count: 1)  // IRQ handler INY.
        XCTAssertEqual(cpu.x, 0x01)
        XCTAssertEqual(cpu.y, 0x01)
    }

    // MARK: - IRQ

    func testIRQ() {
        let (cpu, bus) = makeCPU([0x58, 0xEA, 0xEA])  // CLI; NOP; NOP
        bus.memory[0xFFFE] = 0x00
        bus.memory[0xFFFF] = 0x07
        bus.memory[0x0700] = 0xA2  // LDX #$99
        bus.memory[0x0701] = 0x99
        bus.memory[0x0702] = 0x40  // RTI

        runInstructions(cpu, count: 1)  // CLI
        cpu.irqLine = true
        runInstructions(cpu, count: 3)  // IRQ handler: LDX, RTI, NOP
        XCTAssertEqual(cpu.x, 0x99)
    }

    func testIRQAfterCLIDelaysUntilAfterFollowingInstruction() {
        let (cpu, bus) = makeCPU([0x58, 0xA9, 0x42, 0xEA])  // CLI; LDA #$42; NOP
        bus.memory[0xFFFE] = 0x00
        bus.memory[0xFFFF] = 0x07
        bus.memory[0x0700] = 0xA2  // LDX #$99
        bus.memory[0x0701] = 0x99
        bus.memory[0x0702] = 0x40  // RTI

        cpu.irqLine = true
        runInstructions(cpu, count: 1)  // CLI
        runInstructions(cpu, count: 1)  // delayed slot: LDA #$42

        XCTAssertEqual(cpu.a, 0x42)
        XCTAssertEqual(cpu.x, 0x00)

        runInstructions(cpu, count: 2)  // IRQ sequence, then handler LDX

        XCTAssertEqual(cpu.x, 0x99)
    }

    func testIRQAfterSEIUsesPreviousClearMaskAtNextBoundary() {
        let (cpu, bus) = makeCPU([0x78, 0xA9, 0x42])  // SEI; LDA #$42
        bus.memory[0xFFFE] = 0x00
        bus.memory[0xFFFF] = 0x07
        bus.memory[0x0700] = 0xA2  // LDX #$99
        bus.memory[0x0701] = 0x99
        bus.memory[0x0702] = 0x40  // RTI
        cpu.setFlag(Flags.interrupt, false)

        runInstructions(cpu, count: 1)  // SEI
        XCTAssertTrue(cpu.getFlag(Flags.interrupt))

        cpu.irqLine = true
        runInstructions(cpu, count: 2)  // IRQ sequence, then handler LDX

        XCTAssertEqual(cpu.a, 0x00)
        XCTAssertEqual(cpu.x, 0x99)
    }

    func testIRQAfterPLPClearingInterruptDelaysUntilAfterFollowingInstruction() {
        let (cpu, bus) = makeCPU([0x28, 0xA9, 0x42, 0xEA])  // PLP; LDA #$42; NOP
        bus.memory[0x01FE] = Flags.unused
        bus.memory[0xFFFE] = 0x00
        bus.memory[0xFFFF] = 0x07
        bus.memory[0x0700] = 0xA2  // LDX #$99
        bus.memory[0x0701] = 0x99
        bus.memory[0x0702] = 0x40  // RTI

        cpu.irqLine = true
        runInstructions(cpu, count: 1)  // PLP clears I late
        XCTAssertFalse(cpu.getFlag(Flags.interrupt))

        runInstructions(cpu, count: 1)  // delayed slot: LDA #$42

        XCTAssertEqual(cpu.a, 0x42)
        XCTAssertEqual(cpu.x, 0x00)

        runInstructions(cpu, count: 2)  // IRQ sequence, then handler LDX

        XCTAssertEqual(cpu.x, 0x99)
    }

    // MARK: - Undocumented opcodes

    func testLAX() {
        let (cpu, bus) = makeCPU([0xA7, 0x10])  // LAX $10
        bus.memory[0x10] = 0x42
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.a, 0x42)
        XCTAssertEqual(cpu.x, 0x42)
    }

    func testLXAImmediateUsesAccumulatorMagicConstantModel() {
        let (cpu, _) = makeCPU([
            0xA9, 0x11,  // LDA #$11
            0xAB, 0xF0   // LXA #$F0
        ])

        runInstructions(cpu, count: 2)

        XCTAssertEqual(cpu.a, 0xF0)
        XCTAssertEqual(cpu.x, 0xF0)
        XCTAssertTrue(cpu.getFlag(Flags.negative))
        XCTAssertFalse(cpu.getFlag(Flags.zero))
    }

    func testLXAImmediateCanMaskBitsThatPlainLAXWouldLoad() {
        let (cpu, _) = makeCPU([
            0xA9, 0x00,  // LDA #$00
            0xAB, 0x11   // LXA #$11
        ])

        runInstructions(cpu, count: 2)

        XCTAssertEqual(cpu.a, 0x00)
        XCTAssertEqual(cpu.x, 0x00)
        XCTAssertTrue(cpu.getFlag(Flags.zero))
        XCTAssertFalse(cpu.getFlag(Flags.negative))
    }

    func testSAX() {
        // LDA #$FF; LDX #$0F; SAX $10
        let (cpu, bus) = makeCPU([0xA9, 0xFF, 0xA2, 0x0F, 0x87, 0x10])
        runInstructions(cpu, count: 3)
        XCTAssertEqual(bus.memory[0x10], 0x0F)  // $FF & $0F = $0F
    }

    func testDCP() {
        // LDA #$05; DCP $10  (DEC $10 then CMP result)
        let (cpu, bus) = makeCPU([0xA9, 0x05, 0xC7, 0x10])
        bus.memory[0x10] = 0x06
        runInstructions(cpu, count: 2)
        XCTAssertEqual(bus.memory[0x10], 0x05)  // decremented
        XCTAssertTrue(cpu.getFlag(Flags.zero))   // A == result
        XCTAssertTrue(cpu.getFlag(Flags.carry))
    }

    func testISC() {
        // SEC; LDA #$10; ISC $10  (INC $10 then SBC result)
        let (cpu, bus) = makeCPU([0x38, 0xA9, 0x10, 0xE7, 0x10])
        bus.memory[0x10] = 0x04
        runInstructions(cpu, count: 3)
        XCTAssertEqual(bus.memory[0x10], 0x05)  // incremented
        XCTAssertEqual(cpu.a, 0x0B)             // $10 - $05 = $0B
    }

    func testSLO() {
        // LDA #$00; SLO $10  (ASL $10 then ORA result)
        let (cpu, bus) = makeCPU([0xA9, 0x00, 0x07, 0x10])
        bus.memory[0x10] = 0x40
        runInstructions(cpu, count: 2)
        XCTAssertEqual(bus.memory[0x10], 0x80)  // shifted left
        XCTAssertEqual(cpu.a, 0x80)             // ORA'd into A
    }

    func testRLA() {
        // SEC; LDA #$FF; RLA $10 (ROL $10 then AND result)
        let (cpu, bus) = makeCPU([0x38, 0xA9, 0xFF, 0x27, 0x10])
        bus.memory[0x10] = 0x40
        runInstructions(cpu, count: 3)
        XCTAssertEqual(bus.memory[0x10], 0x81)  // ROL with carry in
        XCTAssertEqual(cpu.a, 0x81)             // AND'd with $FF
    }

    func testSRE() {
        // LDA #$00; SRE $10 (LSR $10 then EOR result)
        let (cpu, bus) = makeCPU([0xA9, 0x00, 0x47, 0x10])
        bus.memory[0x10] = 0x02
        runInstructions(cpu, count: 2)
        XCTAssertEqual(bus.memory[0x10], 0x01)
        XCTAssertEqual(cpu.a, 0x01)
    }

    func testRRA() {
        // CLC; LDA #$10; RRA $10 (ROR $10 then ADC result)
        let (cpu, bus) = makeCPU([0x18, 0xA9, 0x10, 0x67, 0x10])
        bus.memory[0x10] = 0x02
        runInstructions(cpu, count: 3)
        XCTAssertEqual(bus.memory[0x10], 0x01)  // ROR'd
        XCTAssertEqual(cpu.a, 0x11)             // $10 + $01
    }

    func testANC() {
        let (cpu, _) = makeCPU([0xA9, 0x80, 0x0B, 0x80])  // LDA #$80; ANC #$80
        runInstructions(cpu, count: 2)
        XCTAssertEqual(cpu.a, 0x80)
        XCTAssertTrue(cpu.getFlag(Flags.carry))
    }

    func testARRImmediateBinaryModeUsesRotatedBitsForCarryAndOverflow() {
        let (cpu, _) = makeCPU([0x6B, 0x9A])
        cpu.a = 0xAE
        cpu.p = Flags.unused

        runInstructions(cpu, count: 1)

        XCTAssertEqual(cpu.a, 0x45)
        XCTAssertTrue(cpu.getFlag(Flags.carry))
        XCTAssertTrue(cpu.getFlag(Flags.overflow))
        XCTAssertFalse(cpu.getFlag(Flags.zero))
        XCTAssertFalse(cpu.getFlag(Flags.negative))
    }

    func testARRImmediateDecimalModeAppliesNMOSBCDAdjustmentWithHighCarry() {
        let (cpu, _) = makeCPU([0x6B, 0xF8])
        cpu.a = 0xDA
        cpu.p = Flags.unused | Flags.decimal | Flags.negative | Flags.overflow

        runInstructions(cpu, count: 1)

        XCTAssertEqual(cpu.a, 0xC2)
        XCTAssertTrue(cpu.getFlag(Flags.carry))
        XCTAssertFalse(cpu.getFlag(Flags.overflow))
        XCTAssertFalse(cpu.getFlag(Flags.zero))
        XCTAssertFalse(cpu.getFlag(Flags.negative))
    }

    func testARRImmediateDecimalModeCanClearCarryAfterAdjustment() {
        let (cpu, _) = makeCPU([0x6B, 0x39])
        cpu.a = 0x30
        cpu.p = Flags.unused | Flags.decimal | Flags.carry | Flags.zero

        runInstructions(cpu, count: 1)

        XCTAssertEqual(cpu.a, 0x98)
        XCTAssertFalse(cpu.getFlag(Flags.carry))
        XCTAssertFalse(cpu.getFlag(Flags.overflow))
        XCTAssertFalse(cpu.getFlag(Flags.zero))
        XCTAssertTrue(cpu.getFlag(Flags.negative))
    }

    func testARRImmediateDecimalModeHighCorrectionUsesWideComparison() {
        let (cpu, _) = makeCPU([0x6B, 0xFD])
        cpu.a = 0xF6
        cpu.p = 0x2C

        runInstructions(cpu, count: 1)

        XCTAssertEqual(cpu.a, 0xDA)
        XCTAssertEqual(cpu.p, 0x2D)
    }

    func testAXSImmediateSubtractsFromAAndXAndSetsCarry() {
        let (cpu, _) = makeCPU([
            0xA9, 0xF0,  // LDA #$F0
            0xA2, 0x3C,  // LDX #$3C
            0xCB, 0x10   // AXS #$10
        ])

        runInstructions(cpu, count: 3)

        XCTAssertEqual(cpu.a, 0xF0)
        XCTAssertEqual(cpu.x, 0x20)
        XCTAssertTrue(cpu.getFlag(Flags.carry))
        XCTAssertFalse(cpu.getFlag(Flags.zero))
        XCTAssertFalse(cpu.getFlag(Flags.negative))
    }

    func testAXSImmediateBorrowClearsCarryAndSetsNegative() {
        let (cpu, _) = makeCPU([
            0xA9, 0x0F,  // LDA #$0F
            0xA2, 0x03,  // LDX #$03
            0xCB, 0x04   // AXS #$04
        ])

        runInstructions(cpu, count: 3)

        XCTAssertEqual(cpu.x, 0xFF)
        XCTAssertFalse(cpu.getFlag(Flags.carry))
        XCTAssertFalse(cpu.getFlag(Flags.zero))
        XCTAssertTrue(cpu.getFlag(Flags.negative))
    }

    func testAHXAbsoluteYStoresAXAndHighBytePlusOne() {
        let (cpu, bus) = makeCPU([
            0xA9, 0xFF,        // LDA #$FF
            0xA2, 0xFF,        // LDX #$FF
            0xA0, 0x01,        // LDY #$01
            0x9F, 0xFE, 0x20   // AHX $20FE,Y
        ])

        runInstructions(cpu, count: 4)

        XCTAssertEqual(bus.memory[0x20FF], 0x21)
    }

    func testAHXAbsoluteYPageCrossUsesUnstableAddressHighByte() {
        let (cpu, bus) = makeCPU([
            0xA9, 0xFF,        // LDA #$FF
            0xA2, 0xFF,        // LDX #$FF
            0xA0, 0x01,        // LDY #$01
            0x9F, 0xFF, 0x20   // AHX $20FF,Y
        ])

        runInstructions(cpu, count: 4)

        XCTAssertEqual(bus.memory[0x2100], 0x21)
        XCTAssertEqual(bus.memory[0x2200], 0x00)
    }

    func testAHXIndirectYPageCrossUsesUnstableAddressHighByte() {
        let (cpu, bus) = makeCPU([
            0xA9, 0xFF,  // LDA #$FF
            0xA2, 0xFF,  // LDX #$FF
            0xA0, 0x01,  // LDY #$01
            0x93, 0x40   // AHX ($40),Y
        ])
        bus.memory[0x40] = 0xFF
        bus.memory[0x41] = 0x20

        runInstructions(cpu, count: 4)

        XCTAssertEqual(bus.memory[0x2100], 0x21)
        XCTAssertEqual(bus.memory[0x2200], 0x00)
    }

    func testAHXIndirectYPageCrossUsesOriginalPointerHighForUnstableMask() {
        let (cpu, bus) = makeCPU([
            0x93, 0x61   // AHX ($61),Y
        ])
        cpu.a = 0xA5
        cpu.x = 0x77
        cpu.y = 0xC7
        bus.memory[0x61] = 0xD0
        bus.memory[0x62] = 0x33

        runInstructions(cpu, count: 1)

        XCTAssertEqual(bus.memory[0x2497], 0x24)
        XCTAssertEqual(bus.memory[0x2597], 0x00)
    }

    func testTASAbsoluteYUpdatesStackPointerAndStoresMaskedValue() {
        let (cpu, bus) = makeCPU([
            0xA9, 0xF7,        // LDA #$F7
            0xA2, 0x3F,        // LDX #$3F
            0xA0, 0x01,        // LDY #$01
            0x9B, 0xFE, 0x20   // TAS $20FE,Y
        ])

        runInstructions(cpu, count: 4)

        XCTAssertEqual(cpu.sp, 0x37)
        XCTAssertEqual(bus.memory[0x20FF], 0x21)
    }

    func testSHXAbsoluteYStoresXAndHighBytePlusOne() {
        let (cpu, bus) = makeCPU([
            0xA2, 0x7F,        // LDX #$7F
            0xA0, 0x02,        // LDY #$02
            0x9E, 0x01, 0x20   // SHX $2001,Y
        ])

        runInstructions(cpu, count: 3)

        XCTAssertEqual(bus.memory[0x2003], 0x21)
    }

    func testSHYAbsoluteXStoresYAndHighBytePlusOne() {
        let (cpu, bus) = makeCPU([
            0xA0, 0x7F,        // LDY #$7F
            0xA2, 0x02,        // LDX #$02
            0x9C, 0x01, 0x20   // SHY $2001,X
        ])

        runInstructions(cpu, count: 3)

        XCTAssertEqual(bus.memory[0x2003], 0x21)
    }

    func testLASAbsoluteYLoadsAAndXAndStackFromMemoryAndStackMask() {
        let (cpu, bus) = makeCPU([
            0xA2, 0xF0,        // LDX #$F0
            0x9A,              // TXS
            0xA0, 0x01,        // LDY #$01
            0xBB, 0xFE, 0x20   // LAS $20FE,Y
        ])
        bus.memory[0x20FF] = 0x3C

        runInstructions(cpu, count: 4)

        XCTAssertEqual(cpu.a, 0x30)
        XCTAssertEqual(cpu.x, 0x30)
        XCTAssertEqual(cpu.sp, 0x30)
        XCTAssertFalse(cpu.getFlag(Flags.zero))
        XCTAssertFalse(cpu.getFlag(Flags.negative))
    }

    func testKILJam() {
        let (cpu, _) = makeCPU([0x02])  // KIL
        runInstructions(cpu, count: 1)
        XCTAssertTrue(cpu.jammed)
        XCTAssertEqual(cpu.pc, 0x0601)
        XCTAssertEqual(cpu.totalCycles, 18)
        // Further ticks should return false
        XCTAssertFalse(cpu.tick())
    }

    func testResetRecoversFromKILJamAndFetchesResetVector() {
        let (cpu, bus) = makeCPU([0x02])  // KIL
        runInstructions(cpu, count: 1)
        XCTAssertTrue(cpu.jammed)

        bus.memory[0xFFFC] = 0x34
        bus.memory[0xFFFD] = 0x12
        cpu.reset()
        for _ in 0..<7 {
            XCTAssertTrue(cpu.tick())
        }

        XCTAssertFalse(cpu.jammed)
        XCTAssertEqual(cpu.pc, 0x1234)
    }

    func testResetDiscardsPendingNMIEdgeAndDoesNotRetriggerHeldLine() {
        let (cpu, bus) = makeCPU([0xEA])  // NOP at reset vector
        bus.memory[0xFFFC] = 0x00
        bus.memory[0xFFFD] = 0x06
        bus.memory[0xFFFA] = 0x34
        bus.memory[0xFFFB] = 0x12

        cpu.setNMILine(high: true)
        XCTAssertTrue(cpu.nmiPending)

        cpu.reset()
        for _ in 0..<7 {
            XCTAssertTrue(cpu.tick())
        }

        XCTAssertEqual(cpu.pc, 0x0600)
        XCTAssertFalse(cpu.nmiPending)

        XCTAssertTrue(cpu.tick())

        XCTAssertEqual(cpu.pc, 0x0601)
        XCTAssertEqual(cpu.cycle, 1)
        XCTAssertFalse(cpu.servicingInterrupt)
    }

    // MARK: - External CPU pins

    func testRDYLowStallsOpcodeFetchUntilReleased() {
        let (cpu, _) = makeCPU([0xEA])
        let beforeCycles = cpu.totalCycles

        cpu.setRDYLine(high: false)
        XCTAssertTrue(cpu.tick())

        XCTAssertEqual(cpu.pc, 0x0600)
        XCTAssertEqual(cpu.cycle, 0)
        XCTAssertEqual(cpu.totalCycles, beforeCycles + 1)

        cpu.setRDYLine(high: true)
        XCTAssertTrue(cpu.tick())

        XCTAssertEqual(cpu.pc, 0x0601)
        XCTAssertEqual(cpu.cycle, 1)
    }

    func testRDYLowStallsReadCycleUntilReleased() {
        let (cpu, _) = makeCPU([0xA9, 0x42])

        XCTAssertTrue(cpu.tick())
        XCTAssertEqual(cpu.pc, 0x0601)
        XCTAssertEqual(cpu.cycle, 1)

        cpu.setRDYLine(high: false)
        XCTAssertTrue(cpu.tick())

        XCTAssertEqual(cpu.pc, 0x0601)
        XCTAssertEqual(cpu.cycle, 1)
        XCTAssertEqual(cpu.a, 0x00)

        cpu.setRDYLine(high: true)
        XCTAssertTrue(cpu.tick())

        XCTAssertEqual(cpu.a, 0x42)
        XCTAssertEqual(cpu.pc, 0x0602)
        XCTAssertEqual(cpu.cycle, 0)
    }

    func testRDYLowDoesNotStallWriteCycleInProgress() {
        let (cpu, bus) = makeCPU([0xA9, 0x42, 0x85, 0x10])
        runInstructions(cpu, count: 1)

        XCTAssertTrue(cpu.tick())
        XCTAssertEqual(cpu.opcode, 0x85)
        XCTAssertTrue(cpu.tick())
        XCTAssertEqual(cpu.cycle, 2)

        cpu.setRDYLine(high: false)
        XCTAssertTrue(cpu.tick())

        XCTAssertEqual(bus.memory[0x0010], 0x42)
        XCTAssertEqual(cpu.cycle, 0)
    }

    func testResetAndPowerOnReleaseRDYLine() {
        let (cpu, _) = makeCPU([0xEA])

        cpu.setRDYLine(high: false)
        cpu.reset()
        XCTAssertTrue(cpu.rdyLine)

        cpu.setRDYLine(high: false)
        cpu.powerOn()
        XCTAssertTrue(cpu.rdyLine)
    }

    func testSOPinSetsOverflowForBranchPollingLoops() {
        let (cpu, _) = makeCPU([
            0x70, 0x02, // BVS +2
            0xA9, 0x00, // LDA #$00 (skipped when SO has set V)
            0xA9, 0x42  // LDA #$42
        ])

        XCTAssertFalse(cpu.getFlag(Flags.overflow))

        cpu.pulseSO()
        runInstructions(cpu, count: 2)

        XCTAssertTrue(cpu.getFlag(Flags.overflow))
        XCTAssertEqual(cpu.a, 0x42)
    }

    func testCLVClearsOverflowSetBySOPin() {
        let (cpu, _) = makeCPU([
            0xB8,       // CLV
            0x50, 0x02, // BVC +2
            0xA9, 0x00, // LDA #$00 (skipped after CLV clears V)
            0xA9, 0x24  // LDA #$24
        ])

        cpu.pulseSO()
        XCTAssertTrue(cpu.getFlag(Flags.overflow))

        runInstructions(cpu, count: 3)

        XCTAssertFalse(cpu.getFlag(Flags.overflow))
        XCTAssertEqual(cpu.a, 0x24)
    }

    // MARK: - BCD mode

    private struct DecimalExpectation {
        let result: UInt8
        let carry: Bool
        let zero: Bool
        let negative: Bool
        let overflow: Bool
    }

    private func add8(_ lhs: UInt8, _ rhs: UInt8, carry: Bool) -> (result: UInt8, carry: Bool, overflow: Bool) {
        let sum = UInt16(lhs) + UInt16(rhs) + UInt16(carry ? 1 : 0)
        let result = UInt8(sum & 0xFF)
        let overflow = (~(UInt16(lhs) ^ UInt16(rhs)) & (UInt16(lhs) ^ UInt16(result)) & 0x80) != 0
        return (result, sum > 0xFF, overflow)
    }

    private func subtract8(_ lhs: UInt8, _ rhs: UInt8, carry: Bool) -> (result: UInt8, carry: Bool) {
        let diff = UInt16(lhs) &- UInt16(rhs) &- UInt16(carry ? 0 : 1)
        return (UInt8(diff & 0xFF), diff < 0x100)
    }

    private func expectedNMOSDecimalADC(lhs: UInt8, rhs: UInt8, carryIn: Bool) -> DecimalExpectation {
        let binarySum = UInt16(lhs) + UInt16(rhs) + UInt16(carryIn ? 1 : 0)

        var partial = lhs & 0x0F
        var carry = carryIn
        (partial, carry, _) = add8(partial, rhs & 0x0F, carry: carry)

        let highCorrection: UInt8
        if partial >= 0x0A {
            highCorrection = 0x0F
            (partial, carry, _) = add8(partial, 0x05, carry: true)
            partial &= 0x0F
            carry = true
        } else {
            highCorrection = 0
        }

        partial |= lhs & 0xF0
        let intermediate: UInt8
        let highCarry: Bool
        let highOverflow: Bool
        (intermediate, highCarry, highOverflow) = add8(partial, (rhs & 0xF0) | highCorrection, carry: carry)

        var result = intermediate
        var finalCarry = false
        if highCarry || intermediate >= 0xA0 {
            (result, _, _) = add8(intermediate, 0x5F, carry: true)
            finalCarry = true
        }

        return DecimalExpectation(
            result: result,
            carry: finalCarry,
            zero: UInt8(binarySum & 0xFF) == 0,
            negative: intermediate & 0x80 != 0,
            overflow: highOverflow
        )
    }

    private func expectedNMOSDecimalSBC(lhs: UInt8, rhs: UInt8, carryIn: Bool) -> DecimalExpectation {
        let binaryDiff = UInt16(lhs) &- UInt16(rhs) &- UInt16(carryIn ? 0 : 1)
        let binaryResult = UInt8(binaryDiff & 0xFF)

        var partial = lhs & 0x0F
        var carry: Bool
        (partial, carry) = subtract8(partial, rhs & 0x0F, carry: carryIn)

        let highCorrection: UInt8
        if carry {
            highCorrection = 0
        } else {
            highCorrection = 0x0F
            (partial, _) = subtract8(partial, 0x05, carry: false)
            partial &= 0x0F
            carry = false
        }

        partial |= lhs & 0xF0
        var result: UInt8
        let highCarry: Bool
        (result, highCarry) = subtract8(partial, (rhs & 0xF0) | highCorrection, carry: carry)

        if !highCarry {
            (result, _) = subtract8(result, 0x5F, carry: false)
        }

        return DecimalExpectation(
            result: result,
            carry: binaryDiff < 0x100,
            zero: binaryResult == 0,
            negative: binaryResult & 0x80 != 0,
            overflow: ((UInt16(lhs) ^ UInt16(rhs)) & (UInt16(lhs) ^ UInt16(binaryResult)) & 0x80) != 0
        )
    }

    private func assertDecimalState(
        _ cpu: CPU6502,
        _ expected: DecimalExpectation,
        operation: String,
        lhs: UInt8,
        rhs: UInt8,
        carryIn: Bool
    ) -> Bool {
        guard cpu.a == expected.result,
              cpu.getFlag(Flags.carry) == expected.carry,
              cpu.getFlag(Flags.zero) == expected.zero,
              cpu.getFlag(Flags.negative) == expected.negative,
              cpu.getFlag(Flags.overflow) == expected.overflow
        else {
            XCTFail("\(operation) decimal mismatch lhs=$\(String(lhs, radix: 16)) rhs=$\(String(rhs, radix: 16)) carry=\(carryIn)")
            return false
        }
        return true
    }

    func testADCBCD() {
        // SED; LDA #$15; ADC #$27 → should be $42 in BCD
        let (cpu, _) = makeCPU([0xF8, 0x18, 0xA9, 0x15, 0x69, 0x27])
        runInstructions(cpu, count: 4)
        XCTAssertEqual(cpu.a, 0x42)
        XCTAssertFalse(cpu.getFlag(Flags.carry))
    }

    func testADCBCDUsesBinarySumForZeroFlag() {
        let (cpu, _) = makeCPU([0xF8, 0x18, 0xA9, 0x50, 0x69, 0x50])
        runInstructions(cpu, count: 4)

        XCTAssertEqual(cpu.a, 0x00)
        XCTAssertTrue(cpu.getFlag(Flags.carry))
        XCTAssertTrue(cpu.getFlag(Flags.overflow))
        XCTAssertTrue(cpu.getFlag(Flags.negative))
        XCTAssertFalse(cpu.getFlag(Flags.zero))
    }

    func testADCBCDUsesAdjustedIntermediateForNegativeAndOverflowFlags() {
        let (cpu, _) = makeCPU([0xF8, 0x38, 0xA9, 0x79, 0x69, 0x00])
        runInstructions(cpu, count: 4)

        XCTAssertEqual(cpu.a, 0x80)
        XCTAssertFalse(cpu.getFlag(Flags.carry))
        XCTAssertTrue(cpu.getFlag(Flags.overflow))
        XCTAssertTrue(cpu.getFlag(Flags.negative))
        XCTAssertFalse(cpu.getFlag(Flags.zero))
    }

    func testADCBCDZeroFlagSetFromZeroBinarySum() {
        let (cpu, _) = makeCPU([0xF8, 0x18, 0xA9, 0x00, 0x69, 0x00])
        runInstructions(cpu, count: 4)

        XCTAssertEqual(cpu.a, 0x00)
        XCTAssertFalse(cpu.getFlag(Flags.carry))
        XCTAssertFalse(cpu.getFlag(Flags.overflow))
        XCTAssertFalse(cpu.getFlag(Flags.negative))
        XCTAssertTrue(cpu.getFlag(Flags.zero))
    }

    func testADCBCDMatchesNMOS6502PredictionForAllOperandsAndCarryInputs() {
        let cpu = CPU6502(bus: RAMBus())

        for carryIn in [false, true] {
            for lhsValue in 0...255 {
                for rhsValue in 0...255 {
                    let lhs = UInt8(lhsValue)
                    let rhs = UInt8(rhsValue)
                    let expected = expectedNMOSDecimalADC(lhs: lhs, rhs: rhs, carryIn: carryIn)

                    cpu.a = lhs
                    cpu.p = Flags.unused | Flags.decimal
                    cpu.setFlag(Flags.carry, carryIn)
                    cpu.adcBCD(rhs)

                    if !assertDecimalState(cpu, expected, operation: "ADC", lhs: lhs, rhs: rhs, carryIn: carryIn) {
                        return
                    }
                }
            }
        }
    }

    func testSBCBCD() {
        // SED; SEC; LDA #$42; SBC #$15 → should be $27
        let (cpu, _) = makeCPU([0xF8, 0x38, 0xA9, 0x42, 0xE9, 0x15])
        runInstructions(cpu, count: 4)
        XCTAssertEqual(cpu.a, 0x27)
        XCTAssertTrue(cpu.getFlag(Flags.carry))
    }

    func testSBCBCDMatchesNMOS6502PredictionForAllOperandsAndCarryInputs() {
        let cpu = CPU6502(bus: RAMBus())

        for carryIn in [false, true] {
            for lhsValue in 0...255 {
                for rhsValue in 0...255 {
                    let lhs = UInt8(lhsValue)
                    let rhs = UInt8(rhsValue)
                    let expected = expectedNMOSDecimalSBC(lhs: lhs, rhs: rhs, carryIn: carryIn)

                    cpu.a = lhs
                    cpu.p = Flags.unused | Flags.decimal
                    cpu.setFlag(Flags.carry, carryIn)
                    cpu.sbcBCD(rhs)

                    if !assertDecimalState(cpu, expected, operation: "SBC", lhs: lhs, rhs: rhs, carryIn: carryIn) {
                        return
                    }
                }
            }
        }
    }

    // MARK: - Cycle counting

    func testLDAImmediateTakes2Cycles() {
        let (cpu, _) = makeCPU([0xA9, 0x42])
        let before = cpu.totalCycles
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.totalCycles - before, 2)
    }

    func testAbsoluteReadTakes4Cycles() {
        let (cpu, _) = makeCPU([0xAD, 0x00, 0x20])  // LDA $2000
        let before = cpu.totalCycles
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.totalCycles - before, 4)
    }

    func testBranchNotTakenTakes2Cycles() {
        let (cpu, _) = makeCPU([0xA9, 0x01, 0xF0, 0x02])  // LDA #$01; BEQ +2 (not taken)
        runInstructions(cpu, count: 1) // LDA
        let before = cpu.totalCycles
        runInstructions(cpu, count: 1) // BEQ not taken
        XCTAssertEqual(cpu.totalCycles - before, 2)
    }

    func testBranchTakenSamePageTakes3Cycles() {
        let (cpu, _) = makeCPU([0xA9, 0x00, 0xF0, 0x00])  // LDA #$00; BEQ +0 (taken, no page cross)
        runInstructions(cpu, count: 1) // LDA
        let before = cpu.totalCycles
        runInstructions(cpu, count: 1) // BEQ taken, same page
        XCTAssertEqual(cpu.totalCycles - before, 3)
    }

    // MARK: - ASL/LSR/ROL/ROR memory

    func testASLZeroPage() {
        let (cpu, bus) = makeCPU([0x06, 0x10])
        bus.memory[0x10] = 0x81
        runInstructions(cpu, count: 1)
        XCTAssertEqual(bus.memory[0x10], 0x02)
        XCTAssertTrue(cpu.getFlag(Flags.carry))
    }

    func testLSRAbsolute() {
        let (cpu, bus) = makeCPU([0x4E, 0x00, 0x20])
        bus.memory[0x2000] = 0x03
        runInstructions(cpu, count: 1)
        XCTAssertEqual(bus.memory[0x2000], 0x01)
        XCTAssertTrue(cpu.getFlag(Flags.carry))
    }

    // MARK: - Page crossing penalty

    func testAbsoluteXPageCrossTakes5Cycles() {
        // LDX #$FF; LDA $2001,X → crosses page ($2001+$FF = $2100)
        let (cpu, _) = makeCPU([0xA2, 0xFF, 0xBD, 0x01, 0x20])
        runInstructions(cpu, count: 1) // LDX
        let before = cpu.totalCycles
        runInstructions(cpu, count: 1) // LDA abs,X with page cross
        XCTAssertEqual(cpu.totalCycles - before, 5)
    }

    func testAbsoluteXNoPageCrossTakes4Cycles() {
        // LDX #$01; LDA $2000,X → no page cross
        let (cpu, _) = makeCPU([0xA2, 0x01, 0xBD, 0x00, 0x20])
        runInstructions(cpu, count: 1) // LDX
        let before = cpu.totalCycles
        runInstructions(cpu, count: 1) // LDA abs,X no page cross
        XCTAssertEqual(cpu.totalCycles - before, 4)
    }

    // MARK: - Integration: simple program

    func testCountToTen() {
        // LDX #$00
        // loop: INX
        //       CPX #$0A
        //       BNE loop
        let (cpu, _) = makeCPU([
            0xA2, 0x00,         // LDX #$00
            0xE8,               // INX
            0xE0, 0x0A,         // CPX #$0A
            0xD0, 0xFB,         // BNE -5 (back to INX)
        ])
        runInstructions(cpu, count: 31) // 1 + 10*(INX+CPX+BNE)
        XCTAssertEqual(cpu.x, 0x0A)
    }

    func testMemoryCopy() {
        // Copy 4 bytes from $2000 to $3000 using indexed addressing
        // LDX #$00
        // loop: LDA $2000,X
        //       STA $3000,X
        //       INX
        //       CPX #$04
        //       BNE loop
        let (cpu, bus) = makeCPU([
            0xA2, 0x00,                 // LDX #$00
            0xBD, 0x00, 0x20,           // LDA $2000,X
            0x9D, 0x00, 0x30,           // STA $3000,X
            0xE8,                       // INX
            0xE0, 0x04,                 // CPX #$04
            0xD0, 0xF5,                 // BNE -11
        ])
        bus.memory[0x2000] = 0xDE
        bus.memory[0x2001] = 0xAD
        bus.memory[0x2002] = 0xBE
        bus.memory[0x2003] = 0xEF

        runInstructions(cpu, count: 100)
        XCTAssertEqual(bus.memory[0x3000], 0xDE)
        XCTAssertEqual(bus.memory[0x3001], 0xAD)
        XCTAssertEqual(bus.memory[0x3002], 0xBE)
        XCTAssertEqual(bus.memory[0x3003], 0xEF)
    }
}
