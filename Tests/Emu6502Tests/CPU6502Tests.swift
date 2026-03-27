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

    // MARK: - Undocumented opcodes

    func testLAX() {
        let (cpu, bus) = makeCPU([0xA7, 0x10])  // LAX $10
        bus.memory[0x10] = 0x42
        runInstructions(cpu, count: 1)
        XCTAssertEqual(cpu.a, 0x42)
        XCTAssertEqual(cpu.x, 0x42)
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

    func testKILJam() {
        let (cpu, _) = makeCPU([0x02])  // KIL
        runInstructions(cpu, count: 1)
        XCTAssertTrue(cpu.jammed)
        // Further ticks should return false
        XCTAssertFalse(cpu.tick())
    }

    // MARK: - BCD mode

    func testADCBCD() {
        // SED; LDA #$15; ADC #$27 → should be $42 in BCD
        let (cpu, _) = makeCPU([0xF8, 0x18, 0xA9, 0x15, 0x69, 0x27])
        runInstructions(cpu, count: 4)
        XCTAssertEqual(cpu.a, 0x42)
        XCTAssertFalse(cpu.getFlag(Flags.carry))
    }

    func testSBCBCD() {
        // SED; SEC; LDA #$42; SBC #$15 → should be $27
        let (cpu, _) = makeCPU([0xF8, 0x38, 0xA9, 0x42, 0xE9, 0x15])
        runInstructions(cpu, count: 4)
        XCTAssertEqual(cpu.a, 0x27)
        XCTAssertTrue(cpu.getFlag(Flags.carry))
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
