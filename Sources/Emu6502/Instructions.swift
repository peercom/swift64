// MARK: - Instruction execution (true per-cycle stepping)
//
// Each tick() performs exactly ONE bus read or write. The CPU advances
// through the current instruction one cycle at a time using template
// functions that correspond to addressing mode + operation type combos.

extension CPU6502 {

    // MARK: - Instruction template enum

    enum InstructionTemplate {
        case implied          // 2 cycles: NOP, TAX, etc.
        case accumulator      // 2 cycles: ASL A, LSR A, ROL A, ROR A
        case immediate        // 2 cycles: LDA #, ADC #, etc.
        case zpRead           // 3 cycles
        case zpWrite          // 3 cycles
        case zpRMW            // 5 cycles
        case zpxRead          // 4 cycles
        case zpxWrite         // 4 cycles
        case zpxRMW           // 6 cycles
        case zpyRead          // 4 cycles
        case zpyWrite         // 4 cycles
        case absRead          // 4 cycles
        case absWrite         // 4 cycles
        case absRMW           // 6 cycles
        case absxRead         // 4-5 cycles
        case absxWrite        // 5 cycles
        case absxRMW          // 7 cycles
        case absyRead         // 4-5 cycles
        case absyWrite        // 5 cycles
        case absyRMW          // 7 cycles
        case indxRead         // 6 cycles
        case indxWrite        // 6 cycles
        case indxRMW          // 8 cycles
        case indyRead         // 5-6 cycles
        case indyWrite        // 6 cycles
        case indyRMW          // 8 cycles
        case branch           // 2-4 cycles
        case jmpAbs           // 3 cycles
        case jmpInd           // 5 cycles
        case jsr              // 6 cycles
        case rts              // 6 cycles
        case rti              // 6 cycles
        case brk              // 7 cycles
        case push             // 3 cycles: PHA, PHP
        case pull             // 4 cycles: PLA, PLP
        case kill             // halts
    }

    // MARK: - Opcode → template lookup table

    static let templateTable: [InstructionTemplate] = {
        var t = [InstructionTemplate](repeating: .kill, count: 256)

        // LDA
        t[0xA9] = .immediate; t[0xA5] = .zpRead; t[0xB5] = .zpxRead
        t[0xAD] = .absRead; t[0xBD] = .absxRead; t[0xB9] = .absyRead
        t[0xA1] = .indxRead; t[0xB1] = .indyRead

        // LDX
        t[0xA2] = .immediate; t[0xA6] = .zpRead; t[0xB6] = .zpyRead
        t[0xAE] = .absRead; t[0xBE] = .absyRead

        // LDY
        t[0xA0] = .immediate; t[0xA4] = .zpRead; t[0xB4] = .zpxRead
        t[0xAC] = .absRead; t[0xBC] = .absxRead

        // STA
        t[0x85] = .zpWrite; t[0x95] = .zpxWrite; t[0x8D] = .absWrite
        t[0x9D] = .absxWrite; t[0x99] = .absyWrite
        t[0x81] = .indxWrite; t[0x91] = .indyWrite

        // STX
        t[0x86] = .zpWrite; t[0x96] = .zpyWrite; t[0x8E] = .absWrite

        // STY
        t[0x84] = .zpWrite; t[0x94] = .zpxWrite; t[0x8C] = .absWrite

        // ADC
        t[0x69] = .immediate; t[0x65] = .zpRead; t[0x75] = .zpxRead
        t[0x6D] = .absRead; t[0x7D] = .absxRead; t[0x79] = .absyRead
        t[0x61] = .indxRead; t[0x71] = .indyRead

        // SBC
        t[0xE9] = .immediate; t[0xE5] = .zpRead; t[0xF5] = .zpxRead
        t[0xED] = .absRead; t[0xFD] = .absxRead; t[0xF9] = .absyRead
        t[0xE1] = .indxRead; t[0xF1] = .indyRead

        // AND
        t[0x29] = .immediate; t[0x25] = .zpRead; t[0x35] = .zpxRead
        t[0x2D] = .absRead; t[0x3D] = .absxRead; t[0x39] = .absyRead
        t[0x21] = .indxRead; t[0x31] = .indyRead

        // ORA
        t[0x09] = .immediate; t[0x05] = .zpRead; t[0x15] = .zpxRead
        t[0x0D] = .absRead; t[0x1D] = .absxRead; t[0x19] = .absyRead
        t[0x01] = .indxRead; t[0x11] = .indyRead

        // EOR
        t[0x49] = .immediate; t[0x45] = .zpRead; t[0x55] = .zpxRead
        t[0x4D] = .absRead; t[0x5D] = .absxRead; t[0x59] = .absyRead
        t[0x41] = .indxRead; t[0x51] = .indyRead

        // CMP
        t[0xC9] = .immediate; t[0xC5] = .zpRead; t[0xD5] = .zpxRead
        t[0xCD] = .absRead; t[0xDD] = .absxRead; t[0xD9] = .absyRead
        t[0xC1] = .indxRead; t[0xD1] = .indyRead

        // CPX
        t[0xE0] = .immediate; t[0xE4] = .zpRead; t[0xEC] = .absRead

        // CPY
        t[0xC0] = .immediate; t[0xC4] = .zpRead; t[0xCC] = .absRead

        // BIT
        t[0x24] = .zpRead; t[0x2C] = .absRead

        // ASL
        t[0x0A] = .accumulator; t[0x06] = .zpRMW; t[0x16] = .zpxRMW
        t[0x0E] = .absRMW; t[0x1E] = .absxRMW

        // LSR
        t[0x4A] = .accumulator; t[0x46] = .zpRMW; t[0x56] = .zpxRMW
        t[0x4E] = .absRMW; t[0x5E] = .absxRMW

        // ROL
        t[0x2A] = .accumulator; t[0x26] = .zpRMW; t[0x36] = .zpxRMW
        t[0x2E] = .absRMW; t[0x3E] = .absxRMW

        // ROR
        t[0x6A] = .accumulator; t[0x66] = .zpRMW; t[0x76] = .zpxRMW
        t[0x6E] = .absRMW; t[0x7E] = .absxRMW

        // INC
        t[0xE6] = .zpRMW; t[0xF6] = .zpxRMW; t[0xEE] = .absRMW; t[0xFE] = .absxRMW

        // DEC
        t[0xC6] = .zpRMW; t[0xD6] = .zpxRMW; t[0xCE] = .absRMW; t[0xDE] = .absxRMW

        // INX, INY, DEX, DEY
        t[0xE8] = .implied; t[0xC8] = .implied; t[0xCA] = .implied; t[0x88] = .implied

        // Transfers
        t[0xAA] = .implied; t[0xA8] = .implied; t[0x8A] = .implied
        t[0x98] = .implied; t[0xBA] = .implied; t[0x9A] = .implied

        // Branches
        t[0x10] = .branch; t[0x30] = .branch; t[0x50] = .branch; t[0x70] = .branch
        t[0x90] = .branch; t[0xB0] = .branch; t[0xD0] = .branch; t[0xF0] = .branch

        // JMP
        t[0x4C] = .jmpAbs; t[0x6C] = .jmpInd

        // JSR / RTS / RTI
        t[0x20] = .jsr; t[0x60] = .rts; t[0x40] = .rti

        // Stack
        t[0x48] = .push; t[0x08] = .push  // PHA, PHP
        t[0x68] = .pull; t[0x28] = .pull  // PLA, PLP

        // Flags
        t[0x18] = .implied; t[0x38] = .implied  // CLC, SEC
        t[0x58] = .implied; t[0x78] = .implied  // CLI, SEI
        t[0xB8] = .implied; t[0xD8] = .implied; t[0xF8] = .implied  // CLV, CLD, SED

        // NOP
        t[0xEA] = .implied

        // BRK
        t[0x00] = .brk

        // --- Undocumented ---

        // NOP variants (1-byte, implied, 2 cycles)
        for op: UInt8 in [0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA] { t[Int(op)] = .implied }

        // NOP variants (2-byte, immediate, 2 cycles)
        for op: UInt8 in [0x80, 0x82, 0x89, 0xC2, 0xE2] { t[Int(op)] = .immediate }

        // NOP variants (2-byte, ZP read, 3 cycles)
        for op: UInt8 in [0x04, 0x44, 0x64] { t[Int(op)] = .zpRead }

        // NOP variants (2-byte, ZP,X read, 4 cycles)
        for op: UInt8 in [0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4] { t[Int(op)] = .zpxRead }

        // NOP (3-byte, absolute read, 4 cycles)
        t[0x0C] = .absRead

        // NOP (3-byte, absoluteX read, 4-5 cycles)
        for op: UInt8 in [0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC] { t[Int(op)] = .absxRead }

        // LAX
        t[0xA7] = .zpRead; t[0xB7] = .zpyRead; t[0xAF] = .absRead
        t[0xBF] = .absyRead; t[0xA3] = .indxRead; t[0xB3] = .indyRead
        t[0xAB] = .immediate  // LAX immediate (unstable)

        // SAX
        t[0x87] = .zpWrite; t[0x97] = .zpyWrite; t[0x8F] = .absWrite
        t[0x83] = .indxWrite

        // SBC unofficial
        t[0xEB] = .immediate

        // DCP
        t[0xC7] = .zpRMW; t[0xD7] = .zpxRMW; t[0xCF] = .absRMW
        t[0xDF] = .absxRMW; t[0xDB] = .absyRMW; t[0xC3] = .indxRMW; t[0xD3] = .indyRMW

        // ISC
        t[0xE7] = .zpRMW; t[0xF7] = .zpxRMW; t[0xEF] = .absRMW
        t[0xFF] = .absxRMW; t[0xFB] = .absyRMW; t[0xE3] = .indxRMW; t[0xF3] = .indyRMW

        // SLO
        t[0x07] = .zpRMW; t[0x17] = .zpxRMW; t[0x0F] = .absRMW
        t[0x1F] = .absxRMW; t[0x1B] = .absyRMW; t[0x03] = .indxRMW; t[0x13] = .indyRMW

        // RLA
        t[0x27] = .zpRMW; t[0x37] = .zpxRMW; t[0x2F] = .absRMW
        t[0x3F] = .absxRMW; t[0x3B] = .absyRMW; t[0x23] = .indxRMW; t[0x33] = .indyRMW

        // SRE
        t[0x47] = .zpRMW; t[0x57] = .zpxRMW; t[0x4F] = .absRMW
        t[0x5F] = .absxRMW; t[0x5B] = .absyRMW; t[0x43] = .indxRMW; t[0x53] = .indyRMW

        // RRA
        t[0x67] = .zpRMW; t[0x77] = .zpxRMW; t[0x6F] = .absRMW
        t[0x7F] = .absxRMW; t[0x7B] = .absyRMW; t[0x63] = .indxRMW; t[0x73] = .indyRMW

        // ANC
        t[0x0B] = .immediate; t[0x2B] = .immediate

        // ALR
        t[0x4B] = .immediate

        // ARR
        t[0x6B] = .immediate

        // XAA (ANE)
        t[0x8B] = .immediate

        // AHX (SHA)
        t[0x9F] = .absyWrite; t[0x93] = .indyWrite

        // TAS (SHS)
        t[0x9B] = .absyWrite

        // SHX (SXA)
        t[0x9E] = .absyWrite

        // SHY (SYA)
        t[0x9C] = .absxWrite

        // LAS (LAR)
        t[0xBB] = .absyRead

        // KIL / JAM
        for op: UInt8 in [0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72,
                          0x92, 0xB2, 0xD2, 0xF2] { t[Int(op)] = .kill }

        return t
    }()

    // MARK: - Per-cycle dispatch

    func executeCycle() {
        let template = CPU6502.templateTable[Int(opcode)]
        switch template {
        case .implied:      cycleImplied()
        case .accumulator:  cycleAccumulator()
        case .immediate:    cycleImmediate()
        case .zpRead:       cycleZpRead()
        case .zpWrite:      cycleZpWrite()
        case .zpRMW:        cycleZpRMW()
        case .zpxRead:      cycleZpxRead()
        case .zpxWrite:     cycleZpxWrite()
        case .zpxRMW:       cycleZpxRMW()
        case .zpyRead:      cycleZpyRead()
        case .zpyWrite:     cycleZpyWrite()
        case .absRead:      cycleAbsRead()
        case .absWrite:     cycleAbsWrite()
        case .absRMW:       cycleAbsRMW()
        case .absxRead:     cycleAbsxRead()
        case .absxWrite:    cycleAbsxWrite()
        case .absxRMW:      cycleAbsxRMW()
        case .absyRead:     cycleAbsyRead()
        case .absyWrite:    cycleAbsyWrite()
        case .absyRMW:      cycleAbsyRMW()
        case .indxRead:     cycleIndxRead()
        case .indxWrite:    cycleIndxWrite()
        case .indxRMW:      cycleIndxRMW()
        case .indyRead:     cycleIndyRead()
        case .indyWrite:    cycleIndyWrite()
        case .indyRMW:      cycleIndyRMW()
        case .branch:       cycleBranch()
        case .jmpAbs:       cycleJmpAbs()
        case .jmpInd:       cycleJmpInd()
        case .jsr:          cycleJsr()
        case .rts:          cycleRts()
        case .rti:          cycleRti()
        case .brk:          cycleBrk()
        case .push:         cyclePush()
        case .pull:         cyclePull()
        case .kill:         cycleKill()
        }
    }

    // MARK: - ALU dispatch (for read instructions)

    func executeALU(_ value: UInt8) {
        switch opcode {
        // LDA
        case 0xA9, 0xA5, 0xB5, 0xAD, 0xBD, 0xB9, 0xA1, 0xB1:
            lda(value)
        // LDX
        case 0xA2, 0xA6, 0xB6, 0xAE, 0xBE:
            ldx(value)
        // LDY
        case 0xA0, 0xA4, 0xB4, 0xAC, 0xBC:
            ldy(value)
        // ADC
        case 0x69, 0x65, 0x75, 0x6D, 0x7D, 0x79, 0x61, 0x71:
            adc(value)
        // SBC (including unofficial 0xEB)
        case 0xE9, 0xE5, 0xF5, 0xED, 0xFD, 0xF9, 0xE1, 0xF1, 0xEB:
            sbc(value)
        // AND
        case 0x29, 0x25, 0x35, 0x2D, 0x3D, 0x39, 0x21, 0x31:
            andOp(value)
        // ORA
        case 0x09, 0x05, 0x15, 0x0D, 0x1D, 0x19, 0x01, 0x11:
            ora(value)
        // EOR
        case 0x49, 0x45, 0x55, 0x4D, 0x5D, 0x59, 0x41, 0x51:
            eor(value)
        // CMP
        case 0xC9, 0xC5, 0xD5, 0xCD, 0xDD, 0xD9, 0xC1, 0xD1:
            cmp(a, value)
        // CPX
        case 0xE0, 0xE4, 0xEC:
            cmp(x, value)
        // CPY
        case 0xC0, 0xC4, 0xCC:
            cmp(y, value)
        // BIT
        case 0x24, 0x2C:
            bit(value)
        // LAX
        case 0xA7, 0xB7, 0xAF, 0xBF, 0xA3, 0xB3, 0xAB:
            a = value; x = value; setZN(value)
        // ANC
        case 0x0B, 0x2B:
            a &= value; setZN(a); setFlag(Flags.carry, a & 0x80 != 0)
        // ALR
        case 0x4B:
            a &= value
            setFlag(Flags.carry, a & 0x01 != 0)
            a >>= 1
            setZN(a)
        // ARR
        case 0x6B:
            a &= value
            let c: UInt8 = getFlag(Flags.carry) ? 0x80 : 0
            a = (a >> 1) | c
            setZN(a)
            setFlag(Flags.carry, a & 0x40 != 0)
            setFlag(Flags.overflow, ((a & 0x40) ^ ((a & 0x20) << 1)) != 0)
        // XAA (ANE)
        case 0x8B:
            a = (a | 0xEE) & x & value; setZN(a)
        // LAS (LAR)
        case 0xBB:
            let v = value & sp; a = v; x = v; sp = v; setZN(v)
        // NOP variants (immediate/zpRead/zpxRead/absRead/absxRead/absyRead) - do nothing
        case 0x80, 0x82, 0x89, 0xC2, 0xE2,
             0x04, 0x44, 0x64,
             0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4,
             0x0C,
             0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC:
            break
        default:
            break
        }
    }

    // MARK: - RMW dispatch

    func executeRMW(_ value: UInt8) -> UInt8 {
        switch opcode {
        case 0x06, 0x16, 0x0E, 0x1E: return aslMem(value)
        case 0x46, 0x56, 0x4E, 0x5E: return lsrMem(value)
        case 0x26, 0x36, 0x2E, 0x3E: return rolMem(value)
        case 0x66, 0x76, 0x6E, 0x7E: return rorMem(value)
        case 0xE6, 0xF6, 0xEE, 0xFE: return incMem(value)
        case 0xC6, 0xD6, 0xCE, 0xDE: return decMem(value)
        // DCP
        case 0xC7, 0xD7, 0xCF, 0xDF, 0xDB, 0xC3, 0xD3: return dcpOp(value)
        // ISC
        case 0xE7, 0xF7, 0xEF, 0xFF, 0xFB, 0xE3, 0xF3: return iscOp(value)
        // SLO
        case 0x07, 0x17, 0x0F, 0x1F, 0x1B, 0x03, 0x13: return sloOp(value)
        // RLA
        case 0x27, 0x37, 0x2F, 0x3F, 0x3B, 0x23, 0x33: return rlaOp(value)
        // SRE
        case 0x47, 0x57, 0x4F, 0x5F, 0x5B, 0x43, 0x53: return sreOp(value)
        // RRA
        case 0x67, 0x77, 0x6F, 0x7F, 0x7B, 0x63, 0x73: return rraOp(value)
        default: return value
        }
    }

    // MARK: - Write value dispatch

    func writeValue() -> UInt8 {
        switch opcode {
        // STA
        case 0x85, 0x95, 0x8D, 0x9D, 0x99, 0x81, 0x91:
            return a
        // STX
        case 0x86, 0x96, 0x8E:
            return x
        // STY
        case 0x84, 0x94, 0x8C:
            return y
        // SAX
        case 0x87, 0x97, 0x8F, 0x83:
            return a & x
        // AHX (SHA) — A & X & (high byte + 1)
        case 0x9F, 0x93:
            return a & x & (UInt8((addr >> 8) & 0xFF) &+ 1)
        // TAS (SHS) — SP = A & X, then store SP & (high + 1)
        case 0x9B:
            sp = a & x
            return sp & (UInt8((addr >> 8) & 0xFF) &+ 1)
        // SHX (SXA) — X & (high byte + 1)
        case 0x9E:
            return x & (UInt8((addr >> 8) & 0xFF) &+ 1)
        // SHY (SYA) — Y & (high byte + 1)
        case 0x9C:
            return y & (UInt8((addr >> 8) & 0xFF) &+ 1)
        default:
            return 0
        }
    }

    // MARK: - Implied operation dispatch

    func executeImplied() {
        switch opcode {
        case 0xAA: x = a; setZN(x)       // TAX
        case 0xA8: y = a; setZN(y)       // TAY
        case 0x8A: a = x; setZN(a)       // TXA
        case 0x98: a = y; setZN(a)       // TYA
        case 0xBA: x = sp; setZN(x)      // TSX
        case 0x9A: sp = x                 // TXS
        case 0xE8: x &+= 1; setZN(x)    // INX
        case 0xC8: y &+= 1; setZN(y)    // INY
        case 0xCA: x &-= 1; setZN(x)    // DEX
        case 0x88: y &-= 1; setZN(y)    // DEY
        case 0x18: setFlag(Flags.carry, false)      // CLC
        case 0x38: setFlag(Flags.carry, true)       // SEC
        case 0x58: setFlag(Flags.interrupt, false)  // CLI
        case 0x78: setFlag(Flags.interrupt, true)   // SEI
        case 0xB8: setFlag(Flags.overflow, false)   // CLV
        case 0xD8: setFlag(Flags.decimal, false)    // CLD
        case 0xF8: setFlag(Flags.decimal, true)     // SED
        case 0xEA: break                             // NOP
        // Undocumented 1-byte NOPs
        case 0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA: break
        default: break
        }
    }

    // MARK: - Accumulator operation dispatch

    func executeAccumulator() {
        switch opcode {
        case 0x0A:  // ASL A
            setFlag(Flags.carry, a & 0x80 != 0)
            a <<= 1; setZN(a)
        case 0x4A:  // LSR A
            setFlag(Flags.carry, a & 0x01 != 0)
            a >>= 1; setZN(a)
        case 0x2A:  // ROL A
            let c: UInt8 = getFlag(Flags.carry) ? 1 : 0
            setFlag(Flags.carry, a & 0x80 != 0)
            a = (a << 1) | c; setZN(a)
        case 0x6A:  // ROR A
            let c: UInt8 = getFlag(Flags.carry) ? 0x80 : 0
            setFlag(Flags.carry, a & 0x01 != 0)
            a = (a >> 1) | c; setZN(a)
        default: break
        }
    }

    // MARK: - Branch condition

    func branchCondition() -> Bool {
        switch opcode {
        case 0x10: return !getFlag(Flags.negative)   // BPL
        case 0x30: return getFlag(Flags.negative)     // BMI
        case 0x50: return !getFlag(Flags.overflow)    // BVC
        case 0x70: return getFlag(Flags.overflow)     // BVS
        case 0x90: return !getFlag(Flags.carry)       // BCC
        case 0xB0: return getFlag(Flags.carry)        // BCS
        case 0xD0: return !getFlag(Flags.zero)        // BNE
        case 0xF0: return getFlag(Flags.zero)         // BEQ
        default: return false
        }
    }

    // MARK: - Template cycle functions

    // Implied: 2 cycles total
    // C0: fetch opcode (done)
    // C1: dummy read, execute op
    func cycleImplied() {
        // cycle 1: dummy read of next byte, execute
        _ = bus.read(pc)
        executeImplied()
        cycle = 0
    }

    // Accumulator: 2 cycles total (same timing as implied)
    func cycleAccumulator() {
        _ = bus.read(pc)
        executeAccumulator()
        cycle = 0
    }

    // Immediate: 2 cycles total
    // C0: fetch opcode
    // C1: read operand, execute
    func cycleImmediate() {
        let value = bus.read(pc)
        pc &+= 1
        executeALU(value)
        cycle = 0
    }

    // ZeroPage Read: 3 cycles
    // C1: read ZP addr from PC
    // C2: read data from ZP, execute ALU
    func cycleZpRead() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))
            pc &+= 1
            cycle = 2
        case 2:
            let value = bus.read(addr)
            executeALU(value)
            cycle = 0
        default: cycle = 0
        }
    }

    // ZeroPage Write: 3 cycles
    func cycleZpWrite() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))
            pc &+= 1
            cycle = 2
        case 2:
            bus.write(addr, value: writeValue())
            cycle = 0
        default: cycle = 0
        }
    }

    // ZeroPage RMW: 5 cycles
    func cycleZpRMW() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))
            pc &+= 1
            cycle = 2
        case 2:
            data = bus.read(addr)
            cycle = 3
        case 3:
            bus.write(addr, value: data)  // dummy write original value
            data = executeRMW(data)
            cycle = 4
        case 4:
            bus.write(addr, value: data)
            cycle = 0
        default: cycle = 0
        }
    }

    // ZeroPageX Read: 4 cycles
    func cycleZpxRead() {
        switch cycle {
        case 1:
            pointer = bus.read(pc)
            pc &+= 1
            cycle = 2
        case 2:
            _ = bus.read(UInt16(pointer))  // dummy read
            addr = UInt16((pointer &+ x) & 0xFF)
            cycle = 3
        case 3:
            let value = bus.read(addr)
            executeALU(value)
            cycle = 0
        default: cycle = 0
        }
    }

    // ZeroPageX Write: 4 cycles
    func cycleZpxWrite() {
        switch cycle {
        case 1:
            pointer = bus.read(pc)
            pc &+= 1
            cycle = 2
        case 2:
            _ = bus.read(UInt16(pointer))  // dummy read
            addr = UInt16((pointer &+ x) & 0xFF)
            cycle = 3
        case 3:
            bus.write(addr, value: writeValue())
            cycle = 0
        default: cycle = 0
        }
    }

    // ZeroPageX RMW: 6 cycles
    func cycleZpxRMW() {
        switch cycle {
        case 1:
            pointer = bus.read(pc)
            pc &+= 1
            cycle = 2
        case 2:
            _ = bus.read(UInt16(pointer))  // dummy read
            addr = UInt16((pointer &+ x) & 0xFF)
            cycle = 3
        case 3:
            data = bus.read(addr)
            cycle = 4
        case 4:
            bus.write(addr, value: data)  // dummy write
            data = executeRMW(data)
            cycle = 5
        case 5:
            bus.write(addr, value: data)
            cycle = 0
        default: cycle = 0
        }
    }

    // ZeroPageY Read: 4 cycles
    func cycleZpyRead() {
        switch cycle {
        case 1:
            pointer = bus.read(pc)
            pc &+= 1
            cycle = 2
        case 2:
            _ = bus.read(UInt16(pointer))  // dummy read
            addr = UInt16((pointer &+ y) & 0xFF)
            cycle = 3
        case 3:
            let value = bus.read(addr)
            executeALU(value)
            cycle = 0
        default: cycle = 0
        }
    }

    // ZeroPageY Write: 4 cycles
    func cycleZpyWrite() {
        switch cycle {
        case 1:
            pointer = bus.read(pc)
            pc &+= 1
            cycle = 2
        case 2:
            _ = bus.read(UInt16(pointer))  // dummy read
            addr = UInt16((pointer &+ y) & 0xFF)
            cycle = 3
        case 3:
            bus.write(addr, value: writeValue())
            cycle = 0
        default: cycle = 0
        }
    }

    // Absolute Read: 4 cycles
    func cycleAbsRead() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))  // low byte
            pc &+= 1
            cycle = 2
        case 2:
            addr |= UInt16(bus.read(pc)) << 8  // high byte
            pc &+= 1
            cycle = 3
        case 3:
            let value = bus.read(addr)
            executeALU(value)
            cycle = 0
        default: cycle = 0
        }
    }

    // Absolute Write: 4 cycles
    func cycleAbsWrite() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))
            pc &+= 1
            cycle = 2
        case 2:
            addr |= UInt16(bus.read(pc)) << 8
            pc &+= 1
            cycle = 3
        case 3:
            bus.write(addr, value: writeValue())
            cycle = 0
        default: cycle = 0
        }
    }

    // Absolute RMW: 6 cycles
    func cycleAbsRMW() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))
            pc &+= 1
            cycle = 2
        case 2:
            addr |= UInt16(bus.read(pc)) << 8
            pc &+= 1
            cycle = 3
        case 3:
            data = bus.read(addr)
            cycle = 4
        case 4:
            bus.write(addr, value: data)  // dummy write
            data = executeRMW(data)
            cycle = 5
        case 5:
            bus.write(addr, value: data)
            cycle = 0
        default: cycle = 0
        }
    }

    // AbsoluteX Read: 4-5 cycles (5 if page cross)
    func cycleAbsxRead() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))  // BAL
            pc &+= 1
            cycle = 2
        case 2:
            let hi = UInt16(bus.read(pc))  // BAH
            pc &+= 1
            baseAddr = (hi << 8) | addr
            addr = baseAddr &+ UInt16(x)
            pageCrossed = (baseAddr ^ addr) & 0xFF00 != 0
            cycle = 3
        case 3:
            if pageCrossed {
                // Read from wrong address (BAH, BAL+X)
                _ = bus.read((baseAddr & 0xFF00) | (addr & 0x00FF))
                cycle = 4
            } else {
                let value = bus.read(addr)
                executeALU(value)
                cycle = 0
            }
        case 4:
            let value = bus.read(addr)
            executeALU(value)
            cycle = 0
        default: cycle = 0
        }
    }

    // AbsoluteX Write: 5 cycles (always)
    func cycleAbsxWrite() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))
            pc &+= 1
            cycle = 2
        case 2:
            let hi = UInt16(bus.read(pc))
            pc &+= 1
            baseAddr = (hi << 8) | addr
            addr = baseAddr &+ UInt16(x)
            cycle = 3
        case 3:
            // Always read from potentially wrong address
            _ = bus.read((baseAddr & 0xFF00) | (addr & 0x00FF))
            cycle = 4
        case 4:
            // Handle SHY page-cross fixup
            if opcode == 0x9C && (baseAddr ^ addr) & 0xFF00 != 0 {
                let value = writeValue()
                let finalAddr = (UInt16(value) << 8) | (addr & 0x00FF)
                bus.write(finalAddr, value: value)
            } else {
                bus.write(addr, value: writeValue())
            }
            cycle = 0
        default: cycle = 0
        }
    }

    // AbsoluteX RMW: 7 cycles
    func cycleAbsxRMW() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))
            pc &+= 1
            cycle = 2
        case 2:
            let hi = UInt16(bus.read(pc))
            pc &+= 1
            baseAddr = (hi << 8) | addr
            addr = baseAddr &+ UInt16(x)
            cycle = 3
        case 3:
            // Always dummy read from potentially wrong address
            _ = bus.read((baseAddr & 0xFF00) | (addr & 0x00FF))
            cycle = 4
        case 4:
            data = bus.read(addr)
            cycle = 5
        case 5:
            bus.write(addr, value: data)  // dummy write
            data = executeRMW(data)
            cycle = 6
        case 6:
            bus.write(addr, value: data)
            cycle = 0
        default: cycle = 0
        }
    }

    // AbsoluteY Read: 4-5 cycles
    func cycleAbsyRead() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))
            pc &+= 1
            cycle = 2
        case 2:
            let hi = UInt16(bus.read(pc))
            pc &+= 1
            baseAddr = (hi << 8) | addr
            addr = baseAddr &+ UInt16(y)
            pageCrossed = (baseAddr ^ addr) & 0xFF00 != 0
            cycle = 3
        case 3:
            if pageCrossed {
                _ = bus.read((baseAddr & 0xFF00) | (addr & 0x00FF))
                cycle = 4
            } else {
                let value = bus.read(addr)
                executeALU(value)
                cycle = 0
            }
        case 4:
            let value = bus.read(addr)
            executeALU(value)
            cycle = 0
        default: cycle = 0
        }
    }

    // AbsoluteY Write: 5 cycles (always)
    func cycleAbsyWrite() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))
            pc &+= 1
            cycle = 2
        case 2:
            let hi = UInt16(bus.read(pc))
            pc &+= 1
            baseAddr = (hi << 8) | addr
            addr = baseAddr &+ UInt16(y)
            cycle = 3
        case 3:
            _ = bus.read((baseAddr & 0xFF00) | (addr & 0x00FF))
            cycle = 4
        case 4:
            // Handle AHX/TAS/SHX page-cross fixup
            if (opcode == 0x9F || opcode == 0x9B || opcode == 0x9E) && (baseAddr ^ addr) & 0xFF00 != 0 {
                let value = writeValue()
                let finalAddr = (UInt16(value) << 8) | (addr & 0x00FF)
                bus.write(finalAddr, value: value)
            } else {
                bus.write(addr, value: writeValue())
            }
            cycle = 0
        default: cycle = 0
        }
    }

    // AbsoluteY RMW: 7 cycles
    func cycleAbsyRMW() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))
            pc &+= 1
            cycle = 2
        case 2:
            let hi = UInt16(bus.read(pc))
            pc &+= 1
            baseAddr = (hi << 8) | addr
            addr = baseAddr &+ UInt16(y)
            cycle = 3
        case 3:
            _ = bus.read((baseAddr & 0xFF00) | (addr & 0x00FF))
            cycle = 4
        case 4:
            data = bus.read(addr)
            cycle = 5
        case 5:
            bus.write(addr, value: data)  // dummy write
            data = executeRMW(data)
            cycle = 6
        case 6:
            bus.write(addr, value: data)
            cycle = 0
        default: cycle = 0
        }
    }

    // IndirectX Read: 6 cycles
    func cycleIndxRead() {
        switch cycle {
        case 1:
            pointer = bus.read(pc)
            pc &+= 1
            cycle = 2
        case 2:
            _ = bus.read(UInt16(pointer))  // dummy read
            pointer = (pointer &+ x) & 0xFF
            cycle = 3
        case 3:
            addr = UInt16(bus.read(UInt16(pointer)))  // low byte
            cycle = 4
        case 4:
            addr |= UInt16(bus.read(UInt16((pointer &+ 1) & 0xFF))) << 8  // high byte
            cycle = 5
        case 5:
            let value = bus.read(addr)
            executeALU(value)
            cycle = 0
        default: cycle = 0
        }
    }

    // IndirectX Write: 6 cycles
    func cycleIndxWrite() {
        switch cycle {
        case 1:
            pointer = bus.read(pc)
            pc &+= 1
            cycle = 2
        case 2:
            _ = bus.read(UInt16(pointer))  // dummy read
            pointer = (pointer &+ x) & 0xFF
            cycle = 3
        case 3:
            addr = UInt16(bus.read(UInt16(pointer)))
            cycle = 4
        case 4:
            addr |= UInt16(bus.read(UInt16((pointer &+ 1) & 0xFF))) << 8
            cycle = 5
        case 5:
            bus.write(addr, value: writeValue())
            cycle = 0
        default: cycle = 0
        }
    }

    // IndirectX RMW: 8 cycles
    func cycleIndxRMW() {
        switch cycle {
        case 1:
            pointer = bus.read(pc)
            pc &+= 1
            cycle = 2
        case 2:
            _ = bus.read(UInt16(pointer))
            pointer = (pointer &+ x) & 0xFF
            cycle = 3
        case 3:
            addr = UInt16(bus.read(UInt16(pointer)))
            cycle = 4
        case 4:
            addr |= UInt16(bus.read(UInt16((pointer &+ 1) & 0xFF))) << 8
            cycle = 5
        case 5:
            data = bus.read(addr)
            cycle = 6
        case 6:
            bus.write(addr, value: data)  // dummy write
            data = executeRMW(data)
            cycle = 7
        case 7:
            bus.write(addr, value: data)
            cycle = 0
        default: cycle = 0
        }
    }

    // IndirectY Read: 5-6 cycles
    func cycleIndyRead() {
        switch cycle {
        case 1:
            pointer = bus.read(pc)
            pc &+= 1
            cycle = 2
        case 2:
            addr = UInt16(bus.read(UInt16(pointer)))  // low byte of base
            cycle = 3
        case 3:
            let hi = UInt16(bus.read(UInt16((pointer &+ 1) & 0xFF)))
            baseAddr = (hi << 8) | addr
            addr = baseAddr &+ UInt16(y)
            pageCrossed = (baseAddr ^ addr) & 0xFF00 != 0
            cycle = 4
        case 4:
            if pageCrossed {
                _ = bus.read((baseAddr & 0xFF00) | (addr & 0x00FF))
                cycle = 5
            } else {
                let value = bus.read(addr)
                executeALU(value)
                cycle = 0
            }
        case 5:
            let value = bus.read(addr)
            executeALU(value)
            cycle = 0
        default: cycle = 0
        }
    }

    // IndirectY Write: 6 cycles
    func cycleIndyWrite() {
        switch cycle {
        case 1:
            pointer = bus.read(pc)
            pc &+= 1
            cycle = 2
        case 2:
            addr = UInt16(bus.read(UInt16(pointer)))
            cycle = 3
        case 3:
            let hi = UInt16(bus.read(UInt16((pointer &+ 1) & 0xFF)))
            baseAddr = (hi << 8) | addr
            addr = baseAddr &+ UInt16(y)
            cycle = 4
        case 4:
            _ = bus.read((baseAddr & 0xFF00) | (addr & 0x00FF))  // always dummy read
            cycle = 5
        case 5:
            // Handle AHX (SHA) indirect Y page-cross fixup
            if opcode == 0x93 && (baseAddr ^ addr) & 0xFF00 != 0 {
                let value = writeValue()
                let finalAddr = (UInt16(value) << 8) | (addr & 0x00FF)
                bus.write(finalAddr, value: value)
            } else {
                bus.write(addr, value: writeValue())
            }
            cycle = 0
        default: cycle = 0
        }
    }

    // IndirectY RMW: 8 cycles
    func cycleIndyRMW() {
        switch cycle {
        case 1:
            pointer = bus.read(pc)
            pc &+= 1
            cycle = 2
        case 2:
            addr = UInt16(bus.read(UInt16(pointer)))
            cycle = 3
        case 3:
            let hi = UInt16(bus.read(UInt16((pointer &+ 1) & 0xFF)))
            baseAddr = (hi << 8) | addr
            addr = baseAddr &+ UInt16(y)
            cycle = 4
        case 4:
            _ = bus.read((baseAddr & 0xFF00) | (addr & 0x00FF))
            cycle = 5
        case 5:
            data = bus.read(addr)
            cycle = 6
        case 6:
            bus.write(addr, value: data)  // dummy write
            data = executeRMW(data)
            cycle = 7
        case 7:
            bus.write(addr, value: data)
            cycle = 0
        default: cycle = 0
        }
    }

    // Branch: 2-4 cycles
    func cycleBranch() {
        switch cycle {
        case 1:
            data = bus.read(pc)  // offset
            pc &+= 1
            if !branchCondition() {
                cycle = 0  // not taken, 2 cycles total
            } else {
                cycle = 2
            }
        case 2:
            // Branch taken — dummy read while adding offset
            _ = bus.read(pc)
            let oldPC = pc
            if data & 0x80 != 0 {
                pc = pc &- UInt16(~data &+ 1)
            } else {
                pc = pc &+ UInt16(data)
            }
            if (oldPC ^ pc) & 0xFF00 != 0 {
                // Page cross — need extra cycle
                baseAddr = oldPC  // save for wrong-address read
                cycle = 3
            } else {
                cycle = 0  // 3 cycles total
            }
        case 3:
            // Page cross fixup cycle
            _ = bus.read((baseAddr & 0xFF00) | (pc & 0x00FF))
            cycle = 0  // 4 cycles total
        default: cycle = 0
        }
    }

    // JMP absolute: 3 cycles
    func cycleJmpAbs() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))
            pc &+= 1
            cycle = 2
        case 2:
            addr |= UInt16(bus.read(pc)) << 8
            pc = addr
            cycle = 0
        default: cycle = 0
        }
    }

    // JMP indirect: 5 cycles
    func cycleJmpInd() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))  // pointer low
            pc &+= 1
            cycle = 2
        case 2:
            addr |= UInt16(bus.read(pc)) << 8  // pointer high
            cycle = 3
        case 3:
            data = bus.read(addr)  // target low byte
            cycle = 4
        case 4:
            // 6502 page boundary bug: wraps within page
            let hiAddr = (addr & 0xFF00) | ((addr &+ 1) & 0x00FF)
            let hi = UInt16(bus.read(hiAddr))
            pc = (hi << 8) | UInt16(data)
            cycle = 0
        default: cycle = 0
        }
    }

    // JSR: 6 cycles
    func cycleJsr() {
        switch cycle {
        case 1:
            addr = UInt16(bus.read(pc))  // low byte of target
            pc &+= 1
            cycle = 2
        case 2:
            _ = bus.read(0x0100 | UInt16(sp))  // internal cycle
            cycle = 3
        case 3:
            bus.write(0x0100 | UInt16(sp), value: UInt8(pc >> 8))  // push PCH
            sp &-= 1
            cycle = 4
        case 4:
            bus.write(0x0100 | UInt16(sp), value: UInt8(pc & 0xFF))  // push PCL
            sp &-= 1
            cycle = 5
        case 5:
            addr |= UInt16(bus.read(pc)) << 8  // high byte of target
            pc = addr
            cycle = 0
        default: cycle = 0
        }
    }

    // RTS: 6 cycles
    func cycleRts() {
        switch cycle {
        case 1:
            _ = bus.read(pc)  // dummy read
            cycle = 2
        case 2:
            _ = bus.read(0x0100 | UInt16(sp))  // dummy stack read
            sp &+= 1
            cycle = 3
        case 3:
            addr = UInt16(bus.read(0x0100 | UInt16(sp)))  // pull PCL
            sp &+= 1
            cycle = 4
        case 4:
            addr |= UInt16(bus.read(0x0100 | UInt16(sp))) << 8  // pull PCH
            cycle = 5
        case 5:
            pc = addr &+ 1
            _ = bus.read(pc)  // increment PC cycle
            cycle = 0
        default: cycle = 0
        }
    }

    // RTI: 6 cycles
    func cycleRti() {
        switch cycle {
        case 1:
            _ = bus.read(pc)  // dummy read
            cycle = 2
        case 2:
            _ = bus.read(0x0100 | UInt16(sp))  // dummy stack read
            sp &+= 1
            cycle = 3
        case 3:
            p = (bus.read(0x0100 | UInt16(sp)) & ~Flags.brk) | Flags.unused
            sp &+= 1
            cycle = 4
        case 4:
            addr = UInt16(bus.read(0x0100 | UInt16(sp)))  // PCL
            sp &+= 1
            cycle = 5
        case 5:
            addr |= UInt16(bus.read(0x0100 | UInt16(sp))) << 8  // PCH
            pc = addr
            cycle = 0
        default: cycle = 0
        }
    }

    // BRK: 7 cycles
    func cycleBrk() {
        switch cycle {
        case 1:
            _ = bus.read(pc)  // read and discard (padding byte)
            pc &+= 1
            cycle = 2
        case 2:
            bus.write(0x0100 | UInt16(sp), value: UInt8(pc >> 8))  // push PCH
            sp &-= 1
            cycle = 3
        case 3:
            bus.write(0x0100 | UInt16(sp), value: UInt8(pc & 0xFF))  // push PCL
            sp &-= 1
            cycle = 4
        case 4:
            bus.write(0x0100 | UInt16(sp), value: p | Flags.brk | Flags.unused)  // push P
            sp &-= 1
            setFlag(Flags.interrupt, true)
            cycle = 5
        case 5:
            addr = UInt16(bus.read(Vector.irq))  // vector low
            cycle = 6
        case 6:
            addr |= UInt16(bus.read(Vector.irq + 1)) << 8  // vector high
            pc = addr
            cycle = 0
        default: cycle = 0
        }
    }

    // PHA/PHP: 3 cycles
    func cyclePush() {
        switch cycle {
        case 1:
            _ = bus.read(pc)  // dummy read
            cycle = 2
        case 2:
            let value: UInt8
            switch opcode {
            case 0x48: value = a                              // PHA
            case 0x08: value = p | Flags.brk | Flags.unused   // PHP
            default: value = 0
            }
            bus.write(0x0100 | UInt16(sp), value: value)
            sp &-= 1
            cycle = 0
        default: cycle = 0
        }
    }

    // PLA/PLP: 4 cycles
    func cyclePull() {
        switch cycle {
        case 1:
            _ = bus.read(pc)  // dummy read
            cycle = 2
        case 2:
            _ = bus.read(0x0100 | UInt16(sp))  // dummy stack read
            sp &+= 1
            cycle = 3
        case 3:
            let value = bus.read(0x0100 | UInt16(sp))
            switch opcode {
            case 0x68: a = value; setZN(a)                            // PLA
            case 0x28: p = (value & ~Flags.brk) | Flags.unused       // PLP
            default: break
            }
            cycle = 0
        default: cycle = 0
        }
    }

    // KIL/JAM: halts
    func cycleKill() {
        jammed = true
        pc &-= 1  // stay on the JAM opcode
        cycle = 0
    }

    // MARK: - Interrupt per-cycle execution

    func executeInterruptCycle() {
        switch cycle {
        case 1:
            if interruptType == .reset {
                _ = bus.read(pc)  // dummy
            } else {
                _ = bus.read(pc)  // dummy read
            }
            cycle = 2
        case 2:
            if interruptType == .reset {
                _ = bus.read(0x0100 | UInt16(sp))  // dummy
                sp &-= 1
            } else {
                bus.write(0x0100 | UInt16(sp), value: UInt8(pc >> 8))  // push PCH
                sp &-= 1
            }
            cycle = 3
        case 3:
            if interruptType == .reset {
                _ = bus.read(0x0100 | UInt16(sp))
                sp &-= 1
            } else {
                bus.write(0x0100 | UInt16(sp), value: UInt8(pc & 0xFF))  // push PCL
                sp &-= 1
            }
            cycle = 4
        case 4:
            if interruptType == .reset {
                _ = bus.read(0x0100 | UInt16(sp))
                sp &-= 1
            } else {
                bus.write(0x0100 | UInt16(sp), value: p & ~Flags.brk | Flags.unused)
                sp &-= 1
            }
            setFlag(Flags.interrupt, true)
            cycle = 5
        case 5:
            let vector: UInt16
            switch interruptType {
            case .nmi:   vector = Vector.nmi
            case .irq:   vector = Vector.irq
            case .reset: vector = Vector.reset
            case .none:  vector = Vector.irq  // shouldn't happen
            }
            addr = UInt16(bus.read(vector))
            cycle = 6
        case 6:
            let vector: UInt16
            switch interruptType {
            case .nmi:   vector = Vector.nmi
            case .irq:   vector = Vector.irq
            case .reset: vector = Vector.reset
            case .none:  vector = Vector.irq
            }
            addr |= UInt16(bus.read(vector + 1)) << 8
            pc = addr
            interruptType = .none
            servicingInterrupt = false
            cycle = 0
        default:
            cycle = 0
        }
    }

    // MARK: - ALU functions (unchanged)

    func lda(_ v: UInt8) { a = v; setZN(a) }
    func ldx(_ v: UInt8) { x = v; setZN(x) }
    func ldy(_ v: UInt8) { y = v; setZN(y) }

    func adc(_ v: UInt8) {
        if getFlag(Flags.decimal) {
            adcBCD(v)
        } else {
            let c: UInt16 = getFlag(Flags.carry) ? 1 : 0
            let sum = UInt16(a) + UInt16(v) + c
            setFlag(Flags.carry, sum > 0xFF)
            setFlag(Flags.overflow, (~(UInt16(a) ^ UInt16(v)) & (UInt16(a) ^ sum) & 0x80) != 0)
            a = UInt8(sum & 0xFF)
            setZN(a)
        }
    }

    func adcBCD(_ v: UInt8) {
        let c: UInt8 = getFlag(Flags.carry) ? 1 : 0
        var lo = (a & 0x0F) + (v & 0x0F) + c
        var hi = (a >> 4) + (v >> 4)
        if lo > 9 { lo -= 10; hi += 1 }

        let sum = UInt16(a) + UInt16(v) + UInt16(c)
        setFlag(Flags.overflow, (~(UInt16(a) ^ UInt16(v)) & (UInt16(a) ^ sum) & 0x80) != 0)
        setFlag(Flags.zero, UInt8(sum & 0xFF) == 0)

        if hi > 9 { hi -= 10; setFlag(Flags.carry, true) } else { setFlag(Flags.carry, false) }
        a = ((hi & 0x0F) << 4) | (lo & 0x0F)
        setFlag(Flags.negative, a & 0x80 != 0)
    }

    func sbc(_ v: UInt8) {
        if getFlag(Flags.decimal) {
            sbcBCD(v)
        } else {
            let c: UInt16 = getFlag(Flags.carry) ? 1 : 0
            let diff = UInt16(a) &- UInt16(v) &- (1 - c)
            setFlag(Flags.carry, diff < 0x100)
            setFlag(Flags.overflow, ((UInt16(a) ^ UInt16(v)) & (UInt16(a) ^ diff) & 0x80) != 0)
            a = UInt8(diff & 0xFF)
            setZN(a)
        }
    }

    func sbcBCD(_ v: UInt8) {
        let c: UInt8 = getFlag(Flags.carry) ? 1 : 0
        var lo = Int(a & 0x0F) - Int(v & 0x0F) - Int(1 - c)
        var hi = Int(a >> 4) - Int(v >> 4)
        if lo < 0 { lo += 10; hi -= 1 }

        let diff = UInt16(a) &- UInt16(v) &- UInt16(1 - c)
        setFlag(Flags.overflow, ((UInt16(a) ^ UInt16(v)) & (UInt16(a) ^ diff) & 0x80) != 0)
        setFlag(Flags.zero, UInt8(diff & 0xFF) == 0)
        setFlag(Flags.negative, diff & 0x80 != 0)

        if hi < 0 { hi += 10; setFlag(Flags.carry, false) } else { setFlag(Flags.carry, true) }
        a = UInt8(((hi & 0x0F) << 4) | (lo & 0x0F))
    }

    func andOp(_ v: UInt8) { a &= v; setZN(a) }
    func ora(_ v: UInt8)   { a |= v; setZN(a) }
    func eor(_ v: UInt8)   { a ^= v; setZN(a) }

    func cmp(_ reg: UInt8, _ v: UInt8) {
        let result = UInt16(reg) &- UInt16(v)
        setFlag(Flags.carry, reg >= v)
        setFlag(Flags.zero, reg == v)
        setFlag(Flags.negative, result & 0x80 != 0)
    }

    func bit(_ v: UInt8) {
        setFlag(Flags.zero, (a & v) == 0)
        setFlag(Flags.overflow, v & 0x40 != 0)
        setFlag(Flags.negative, v & 0x80 != 0)
    }

    // -- Shift/rotate (memory) — used by executeRMW --

    func aslMem(_ v: UInt8) -> UInt8 {
        setFlag(Flags.carry, v & 0x80 != 0)
        let r = v << 1
        setZN(r)
        return r
    }

    func lsrMem(_ v: UInt8) -> UInt8 {
        setFlag(Flags.carry, v & 0x01 != 0)
        let r = v >> 1
        setZN(r)
        return r
    }

    func rolMem(_ v: UInt8) -> UInt8 {
        let c: UInt8 = getFlag(Flags.carry) ? 1 : 0
        setFlag(Flags.carry, v & 0x80 != 0)
        let r = (v << 1) | c
        setZN(r)
        return r
    }

    func rorMem(_ v: UInt8) -> UInt8 {
        let c: UInt8 = getFlag(Flags.carry) ? 0x80 : 0
        setFlag(Flags.carry, v & 0x01 != 0)
        let r = (v >> 1) | c
        setZN(r)
        return r
    }

    func incMem(_ v: UInt8) -> UInt8 {
        let r = v &+ 1
        setZN(r)
        return r
    }

    func decMem(_ v: UInt8) -> UInt8 {
        let r = v &- 1
        setZN(r)
        return r
    }

    // MARK: - Undocumented RMW combo ops

    func dcpOp(_ v: UInt8) -> UInt8 {
        let r = v &- 1
        cmp(a, r)
        return r
    }

    func iscOp(_ v: UInt8) -> UInt8 {
        let r = v &+ 1
        sbc(r)
        return r
    }

    func sloOp(_ v: UInt8) -> UInt8 {
        let r = aslMem(v)
        a |= r
        setZN(a)
        return r
    }

    func rlaOp(_ v: UInt8) -> UInt8 {
        let r = rolMem(v)
        a &= r
        setZN(a)
        return r
    }

    func sreOp(_ v: UInt8) -> UInt8 {
        let r = lsrMem(v)
        a ^= r
        setZN(a)
        return r
    }

    func rraOp(_ v: UInt8) -> UInt8 {
        let r = rorMem(v)
        adc(r)
        return r
    }
}
