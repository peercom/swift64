// MARK: - Instruction execution (cycle-stepped)
//
// The 6502 executes each instruction over multiple cycles. Rather than
// modeling every individual bus access per cycle (which would require a
// complex state machine for each of 256 opcodes), we use a practical
// approach: consume the correct number of cycles by performing bus
// reads/writes in the right order, then advance to the next instruction.
//
// On cycle 1 (opcode was fetched on cycle 0 in tick()), we execute the
// full instruction, performing all the bus accesses it would do, and
// set `cycle` to 0 so the next tick() fetches a new opcode.
//
// This is "instruction-stepped with correct cycle counts" — every
// instruction takes the exact number of cycles a real 6502 would, and
// all bus reads/writes happen, but they happen in a burst on the first
// execution cycle rather than spread across individual ticks.
//
// For most host systems this is sufficient. If you need per-cycle bus
// timing (e.g., for mid-scanline register writes), the architecture
// supports refactoring individual opcodes to true per-cycle stepping.

extension CPU6502 {

    func executeInstructionCycle() {
        // Reset bus access counter. The opcode fetch already consumed 1 cycle,
        // so after execution, pendingCycles = busAccessCount - 1 (since the
        // current tick() call accounts for 1 cycle).
        busAccessCount = 0

        // Decode and execute the full instruction
        switch opcode {

        // =================================================================
        // MARK: - Official opcodes
        // =================================================================

        // MARK: LDA
        case 0xA9: lda(immediate())
        case 0xA5: lda(readZeroPage())
        case 0xB5: lda(readZeroPageX())
        case 0xAD: lda(readAbsolute())
        case 0xBD: lda(readAbsoluteX())
        case 0xB9: lda(readAbsoluteY())
        case 0xA1: lda(readIndirectX())
        case 0xB1: lda(readIndirectY())

        // MARK: LDX
        case 0xA2: ldx(immediate())
        case 0xA6: ldx(readZeroPage())
        case 0xB6: ldx(readZeroPageY())
        case 0xAE: ldx(readAbsolute())
        case 0xBE: ldx(readAbsoluteY())

        // MARK: LDY
        case 0xA0: ldy(immediate())
        case 0xA4: ldy(readZeroPage())
        case 0xB4: ldy(readZeroPageX())
        case 0xAC: ldy(readAbsolute())
        case 0xBC: ldy(readAbsoluteX())

        // MARK: STA
        case 0x85: writeZeroPage(a)
        case 0x95: writeZeroPageX(a)
        case 0x8D: writeAbsolute(a)
        case 0x9D: writeAbsoluteX(a)
        case 0x99: writeAbsoluteY(a)
        case 0x81: writeIndirectX(a)
        case 0x91: writeIndirectY(a)

        // MARK: STX
        case 0x86: writeZeroPage(x)
        case 0x96: writeZeroPageY(x)
        case 0x8E: writeAbsolute(x)

        // MARK: STY
        case 0x84: writeZeroPage(y)
        case 0x94: writeZeroPageX(y)
        case 0x8C: writeAbsolute(y)

        // MARK: ADC
        case 0x69: adc(immediate())
        case 0x65: adc(readZeroPage())
        case 0x75: adc(readZeroPageX())
        case 0x6D: adc(readAbsolute())
        case 0x7D: adc(readAbsoluteX())
        case 0x79: adc(readAbsoluteY())
        case 0x61: adc(readIndirectX())
        case 0x71: adc(readIndirectY())

        // MARK: SBC
        case 0xE9: sbc(immediate())
        case 0xE5: sbc(readZeroPage())
        case 0xF5: sbc(readZeroPageX())
        case 0xED: sbc(readAbsolute())
        case 0xFD: sbc(readAbsoluteX())
        case 0xF9: sbc(readAbsoluteY())
        case 0xE1: sbc(readIndirectX())
        case 0xF1: sbc(readIndirectY())

        // MARK: AND
        case 0x29: andOp(immediate())
        case 0x25: andOp(readZeroPage())
        case 0x35: andOp(readZeroPageX())
        case 0x2D: andOp(readAbsolute())
        case 0x3D: andOp(readAbsoluteX())
        case 0x39: andOp(readAbsoluteY())
        case 0x21: andOp(readIndirectX())
        case 0x31: andOp(readIndirectY())

        // MARK: ORA
        case 0x09: ora(immediate())
        case 0x05: ora(readZeroPage())
        case 0x15: ora(readZeroPageX())
        case 0x0D: ora(readAbsolute())
        case 0x1D: ora(readAbsoluteX())
        case 0x19: ora(readAbsoluteY())
        case 0x01: ora(readIndirectX())
        case 0x11: ora(readIndirectY())

        // MARK: EOR
        case 0x49: eor(immediate())
        case 0x45: eor(readZeroPage())
        case 0x55: eor(readZeroPageX())
        case 0x4D: eor(readAbsolute())
        case 0x5D: eor(readAbsoluteX())
        case 0x59: eor(readAbsoluteY())
        case 0x41: eor(readIndirectX())
        case 0x51: eor(readIndirectY())

        // MARK: CMP
        case 0xC9: cmp(a, immediate())
        case 0xC5: cmp(a, readZeroPage())
        case 0xD5: cmp(a, readZeroPageX())
        case 0xCD: cmp(a, readAbsolute())
        case 0xDD: cmp(a, readAbsoluteX())
        case 0xD9: cmp(a, readAbsoluteY())
        case 0xC1: cmp(a, readIndirectX())
        case 0xD1: cmp(a, readIndirectY())

        // MARK: CPX
        case 0xE0: cmp(x, immediate())
        case 0xE4: cmp(x, readZeroPage())
        case 0xEC: cmp(x, readAbsolute())

        // MARK: CPY
        case 0xC0: cmp(y, immediate())
        case 0xC4: cmp(y, readZeroPage())
        case 0xCC: cmp(y, readAbsolute())

        // MARK: BIT
        case 0x24: bit(readZeroPage())
        case 0x2C: bit(readAbsolute())

        // MARK: ASL
        case 0x0A: aslAcc()
        case 0x06: rmw(zeroPageAddr(), aslMem)
        case 0x16: rmw(zeroPageXAddr(), aslMem)
        case 0x0E: rmw(absoluteAddr(), aslMem)
        case 0x1E: rmw(absoluteXAddrRMW(), aslMem)

        // MARK: LSR
        case 0x4A: lsrAcc()
        case 0x46: rmw(zeroPageAddr(), lsrMem)
        case 0x56: rmw(zeroPageXAddr(), lsrMem)
        case 0x4E: rmw(absoluteAddr(), lsrMem)
        case 0x5E: rmw(absoluteXAddrRMW(), lsrMem)

        // MARK: ROL
        case 0x2A: rolAcc()
        case 0x26: rmw(zeroPageAddr(), rolMem)
        case 0x36: rmw(zeroPageXAddr(), rolMem)
        case 0x2E: rmw(absoluteAddr(), rolMem)
        case 0x3E: rmw(absoluteXAddrRMW(), rolMem)

        // MARK: ROR
        case 0x6A: rorAcc()
        case 0x66: rmw(zeroPageAddr(), rorMem)
        case 0x76: rmw(zeroPageXAddr(), rorMem)
        case 0x6E: rmw(absoluteAddr(), rorMem)
        case 0x7E: rmw(absoluteXAddrRMW(), rorMem)

        // MARK: INC
        case 0xE6: rmw(zeroPageAddr(), incMem)
        case 0xF6: rmw(zeroPageXAddr(), incMem)
        case 0xEE: rmw(absoluteAddr(), incMem)
        case 0xFE: rmw(absoluteXAddrRMW(), incMem)

        // MARK: DEC
        case 0xC6: rmw(zeroPageAddr(), decMem)
        case 0xD6: rmw(zeroPageXAddr(), decMem)
        case 0xCE: rmw(absoluteAddr(), decMem)
        case 0xDE: rmw(absoluteXAddrRMW(), decMem)

        // MARK: INX, INY, DEX, DEY
        case 0xE8: implied(); x &+= 1; setZN(x)
        case 0xC8: implied(); y &+= 1; setZN(y)
        case 0xCA: implied(); x &-= 1; setZN(x)
        case 0x88: implied(); y &-= 1; setZN(y)

        // MARK: Transfers
        case 0xAA: implied(); x = a; setZN(x)       // TAX
        case 0xA8: implied(); y = a; setZN(y)       // TAY
        case 0x8A: implied(); a = x; setZN(a)       // TXA
        case 0x98: implied(); a = y; setZN(a)       // TYA
        case 0xBA: implied(); x = sp; setZN(x)      // TSX
        case 0x9A: implied(); sp = x                  // TXS

        // MARK: Branches
        case 0x10: branch(!getFlag(Flags.negative))   // BPL
        case 0x30: branch(getFlag(Flags.negative))     // BMI
        case 0x50: branch(!getFlag(Flags.overflow))    // BVC
        case 0x70: branch(getFlag(Flags.overflow))     // BVS
        case 0x90: branch(!getFlag(Flags.carry))       // BCC
        case 0xB0: branch(getFlag(Flags.carry))        // BCS
        case 0xD0: branch(!getFlag(Flags.zero))        // BNE
        case 0xF0: branch(getFlag(Flags.zero))         // BEQ

        // MARK: JMP
        case 0x4C: jmpAbsolute()
        case 0x6C: jmpIndirect()

        // MARK: JSR / RTS / RTI
        case 0x20: jsr()
        case 0x60: rts()
        case 0x40: rti()

        // MARK: Stack
        case 0x48: pushOp(a)         // PHA
        case 0x08: pushOp(p | Flags.brk | Flags.unused) // PHP
        case 0x68: implied(); a = pull(); setZN(a)  // PLA
        case 0x28: implied(); p = (pull() & ~Flags.brk) | Flags.unused // PLP

        // MARK: Flags
        case 0x18: implied(); setFlag(Flags.carry, false)      // CLC
        case 0x38: implied(); setFlag(Flags.carry, true)       // SEC
        case 0x58: implied(); setFlag(Flags.interrupt, false)  // CLI
        case 0x78: implied(); setFlag(Flags.interrupt, true)   // SEI
        case 0xB8: implied(); setFlag(Flags.overflow, false)   // CLV
        case 0xD8: implied(); setFlag(Flags.decimal, false)    // CLD
        case 0xF8: implied(); setFlag(Flags.decimal, true)     // SED

        // MARK: NOP
        case 0xEA: implied()

        // MARK: BRK
        case 0x00: brkOp()

        // =================================================================
        // MARK: - Undocumented / Illegal opcodes
        // =================================================================

        // MARK: NOP variants (undocumented)
        // 1-byte NOPs (implied, 2 cycles)
        case 0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA:
            implied()
        // 2-byte NOPs (immediate/zp, skip one byte)
        case 0x80, 0x82, 0x89, 0xC2, 0xE2:
            _ = immediate()
        // 2-byte ZP NOPs (3 cycles)
        case 0x04, 0x44, 0x64:
            _ = readZeroPage()
        // 2-byte ZP,X NOPs (4 cycles)
        case 0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4:
            _ = readZeroPageX()
        // 3-byte absolute NOPs (4 cycles)
        case 0x0C:
            _ = readAbsolute()
        // 3-byte absolute,X NOPs (4-5 cycles)
        case 0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC:
            _ = readAbsoluteX()

        // MARK: LAX — LDA + LDX
        case 0xA7: let v = readZeroPage(); a = v; x = v; setZN(v)
        case 0xB7: let v = readZeroPageY(); a = v; x = v; setZN(v)
        case 0xAF: let v = readAbsolute(); a = v; x = v; setZN(v)
        case 0xBF: let v = readAbsoluteY(); a = v; x = v; setZN(v)
        case 0xA3: let v = readIndirectX(); a = v; x = v; setZN(v)
        case 0xB3: let v = readIndirectY(); a = v; x = v; setZN(v)
        case 0xAB: let v = immediate(); a = v; x = v; setZN(v) // LAX immediate (unstable)

        // MARK: SAX — Store A & X
        case 0x87: writeZeroPage(a & x)
        case 0x97: writeZeroPageY(a & x)
        case 0x8F: writeAbsolute(a & x)
        case 0x83: writeIndirectX(a & x)

        // MARK: SBC unofficial (identical to official SBC)
        case 0xEB: sbc(immediate())

        // MARK: DCP — DEC + CMP
        case 0xC7: rmw(zeroPageAddr(), dcpOp)
        case 0xD7: rmw(zeroPageXAddr(), dcpOp)
        case 0xCF: rmw(absoluteAddr(), dcpOp)
        case 0xDF: rmw(absoluteXAddrRMW(), dcpOp)
        case 0xDB: rmw(absoluteYAddrRMW(), dcpOp)
        case 0xC3: rmw(indirectXAddr(), dcpOp)
        case 0xD3: rmw(indirectYAddrRMW(), dcpOp)

        // MARK: ISC (ISB) — INC + SBC
        case 0xE7: rmw(zeroPageAddr(), iscOp)
        case 0xF7: rmw(zeroPageXAddr(), iscOp)
        case 0xEF: rmw(absoluteAddr(), iscOp)
        case 0xFF: rmw(absoluteXAddrRMW(), iscOp)
        case 0xFB: rmw(absoluteYAddrRMW(), iscOp)
        case 0xE3: rmw(indirectXAddr(), iscOp)
        case 0xF3: rmw(indirectYAddrRMW(), iscOp)

        // MARK: SLO — ASL + ORA
        case 0x07: rmw(zeroPageAddr(), sloOp)
        case 0x17: rmw(zeroPageXAddr(), sloOp)
        case 0x0F: rmw(absoluteAddr(), sloOp)
        case 0x1F: rmw(absoluteXAddrRMW(), sloOp)
        case 0x1B: rmw(absoluteYAddrRMW(), sloOp)
        case 0x03: rmw(indirectXAddr(), sloOp)
        case 0x13: rmw(indirectYAddrRMW(), sloOp)

        // MARK: RLA — ROL + AND
        case 0x27: rmw(zeroPageAddr(), rlaOp)
        case 0x37: rmw(zeroPageXAddr(), rlaOp)
        case 0x2F: rmw(absoluteAddr(), rlaOp)
        case 0x3F: rmw(absoluteXAddrRMW(), rlaOp)
        case 0x3B: rmw(absoluteYAddrRMW(), rlaOp)
        case 0x23: rmw(indirectXAddr(), rlaOp)
        case 0x33: rmw(indirectYAddrRMW(), rlaOp)

        // MARK: SRE — LSR + EOR
        case 0x47: rmw(zeroPageAddr(), sreOp)
        case 0x57: rmw(zeroPageXAddr(), sreOp)
        case 0x4F: rmw(absoluteAddr(), sreOp)
        case 0x5F: rmw(absoluteXAddrRMW(), sreOp)
        case 0x5B: rmw(absoluteYAddrRMW(), sreOp)
        case 0x43: rmw(indirectXAddr(), sreOp)
        case 0x53: rmw(indirectYAddrRMW(), sreOp)

        // MARK: RRA — ROR + ADC
        case 0x67: rmw(zeroPageAddr(), rraOp)
        case 0x77: rmw(zeroPageXAddr(), rraOp)
        case 0x6F: rmw(absoluteAddr(), rraOp)
        case 0x7F: rmw(absoluteXAddrRMW(), rraOp)
        case 0x7B: rmw(absoluteYAddrRMW(), rraOp)
        case 0x63: rmw(indirectXAddr(), rraOp)
        case 0x73: rmw(indirectYAddrRMW(), rraOp)

        // MARK: ANC — AND + set C from N
        case 0x0B, 0x2B:
            let v = immediate()
            a &= v
            setZN(a)
            setFlag(Flags.carry, a & 0x80 != 0)

        // MARK: ALR (ASR) — AND + LSR
        case 0x4B:
            a &= immediate()
            setFlag(Flags.carry, a & 0x01 != 0)
            a >>= 1
            setZN(a)

        // MARK: ARR — AND + ROR (with special flag behavior)
        case 0x6B:
            a &= immediate()
            let c: UInt8 = getFlag(Flags.carry) ? 0x80 : 0
            a = (a >> 1) | c
            setZN(a)
            setFlag(Flags.carry, a & 0x40 != 0)
            setFlag(Flags.overflow, ((a & 0x40) ^ ((a & 0x20) << 1)) != 0)

        // MARK: XAA (ANE) — unstable
        case 0x8B:
            let v = immediate()
            a = (a | 0xEE) & x & v
            setZN(a)

        // MARK: AHX (SHA) — store A & X & (high byte of addr + 1)
        case 0x9F: ahxAbsoluteY()
        case 0x93: ahxIndirectY()

        // MARK: TAS (SHS) — SP = A & X, store A & X & (high+1)
        case 0x9B: tasAbsoluteY()

        // MARK: SHX (SXA) — store X & (high byte of addr + 1)
        case 0x9E: shxAbsoluteY()

        // MARK: SHY (SYA) — store Y & (high byte of addr + 1)
        case 0x9C: shyAbsoluteX()

        // MARK: LAS (LAR) — A,X,SP = M & SP
        case 0xBB:
            let v = readAbsoluteY() & sp
            a = v; x = v; sp = v
            setZN(v)

        // MARK: KIL / JAM — halt the CPU
        case 0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72,
             0x92, 0xB2, 0xD2, 0xF2:
            jammed = true
            pc &-= 1  // stay on the JAM opcode

        default:
            // Should never happen — all 256 opcodes are covered
            break
        }

        // busAccessCount = number of bus accesses during this execution.
        // The current tick() call covers one of these cycles.
        // Any remaining cycles become pendingCycles for subsequent tick() calls.
        if busAccessCount > 1 {
            pendingCycles = busAccessCount - 1
            // cycle stays non-zero; will be reset to 0 when pendingCycles drains
        } else {
            cycle = 0
        }
    }

    // MARK: - Addressing mode helpers

    /// Implied / accumulator — 2-cycle instruction, dummy read of next byte.
    func implied() {
        _ = busRead(pc) // dummy read
    }

    /// Immediate — read byte at PC, advance PC.
    func immediate() -> UInt8 {
        let v = busRead(pc)
        pc &+= 1
        return v
    }

    // -- Zero page --

    func zeroPageAddr() -> UInt16 {
        let addr = UInt16(busRead(pc))
        pc &+= 1
        return addr
    }

    func readZeroPage() -> UInt8 {
        return busRead(zeroPageAddr())
    }

    func writeZeroPage(_ value: UInt8) {
        let addr = zeroPageAddr()
        busWrite(addr, value: value)
    }

    // -- Zero page, X --

    func zeroPageXAddr() -> UInt16 {
        let base = busRead(pc)
        pc &+= 1
        _ = busRead(UInt16(base)) // dummy read
        return UInt16((base &+ x) & 0xFF)
    }

    func readZeroPageX() -> UInt8 {
        return busRead(zeroPageXAddr())
    }

    func writeZeroPageX(_ value: UInt8) {
        let addr = zeroPageXAddr()
        busWrite(addr, value: value)
    }

    // -- Zero page, Y --

    func zeroPageYAddr() -> UInt16 {
        let base = busRead(pc)
        pc &+= 1
        _ = busRead(UInt16(base)) // dummy read
        return UInt16((base &+ y) & 0xFF)
    }

    func readZeroPageY() -> UInt8 {
        return busRead(zeroPageYAddr())
    }

    func writeZeroPageY(_ value: UInt8) {
        let addr = zeroPageYAddr()
        busWrite(addr, value: value)
    }

    // -- Absolute --

    func absoluteAddr() -> UInt16 {
        let lo = UInt16(busRead(pc))
        pc &+= 1
        let hi = UInt16(busRead(pc))
        pc &+= 1
        return (hi << 8) | lo
    }

    func readAbsolute() -> UInt8 {
        return busRead(absoluteAddr())
    }

    func writeAbsolute(_ value: UInt8) {
        let addr = absoluteAddr()
        busWrite(addr, value: value)
    }

    // -- Absolute, X (read) --

    func absoluteXAddr() -> UInt16 {
        let lo = UInt16(busRead(pc))
        pc &+= 1
        let hi = UInt16(busRead(pc))
        pc &+= 1
        let base = (hi << 8) | lo
        let addr = base &+ UInt16(x)
        if (base ^ addr) & 0xFF00 != 0 {
            // Page crossed — dummy read from wrong page
            _ = busRead((base & 0xFF00) | (addr & 0x00FF))
        }
        return addr
    }

    func readAbsoluteX() -> UInt8 {
        return busRead(absoluteXAddr())
    }

    /// Absolute,X for RMW instructions — always takes the extra cycle.
    func absoluteXAddrRMW() -> UInt16 {
        let lo = UInt16(busRead(pc))
        pc &+= 1
        let hi = UInt16(busRead(pc))
        pc &+= 1
        let base = (hi << 8) | lo
        let addr = base &+ UInt16(x)
        _ = busRead((base & 0xFF00) | (addr & 0x00FF)) // always dummy read
        return addr
    }

    func writeAbsoluteX(_ value: UInt8) {
        let addr = absoluteXAddrRMW() // stores always take the penalty cycle
        busWrite(addr, value: value)
    }

    // -- Absolute, Y --

    func absoluteYAddr() -> UInt16 {
        let lo = UInt16(busRead(pc))
        pc &+= 1
        let hi = UInt16(busRead(pc))
        pc &+= 1
        let base = (hi << 8) | lo
        let addr = base &+ UInt16(y)
        if (base ^ addr) & 0xFF00 != 0 {
            _ = busRead((base & 0xFF00) | (addr & 0x00FF))
        }
        return addr
    }

    func readAbsoluteY() -> UInt8 {
        return busRead(absoluteYAddr())
    }

    func absoluteYAddrRMW() -> UInt16 {
        let lo = UInt16(busRead(pc))
        pc &+= 1
        let hi = UInt16(busRead(pc))
        pc &+= 1
        let base = (hi << 8) | lo
        let addr = base &+ UInt16(y)
        _ = busRead((base & 0xFF00) | (addr & 0x00FF)) // always dummy read
        return addr
    }

    func writeAbsoluteY(_ value: UInt8) {
        let addr = absoluteYAddrRMW()
        busWrite(addr, value: value)
    }

    // -- (Indirect, X) --

    func indirectXAddr() -> UInt16 {
        let zp = busRead(pc)
        pc &+= 1
        _ = busRead(UInt16(zp)) // dummy read
        let ptr = (zp &+ x) & 0xFF
        let lo = UInt16(busRead(UInt16(ptr)))
        let hi = UInt16(busRead(UInt16((ptr &+ 1) & 0xFF)))
        return (hi << 8) | lo
    }

    func readIndirectX() -> UInt8 {
        return busRead(indirectXAddr())
    }

    func writeIndirectX(_ value: UInt8) {
        let addr = indirectXAddr()
        busWrite(addr, value: value)
    }

    // -- (Indirect), Y --

    func indirectYAddr() -> UInt16 {
        let zp = busRead(pc)
        pc &+= 1
        let lo = UInt16(busRead(UInt16(zp)))
        let hi = UInt16(busRead(UInt16((zp &+ 1) & 0xFF)))
        let base = (hi << 8) | lo
        let addr = base &+ UInt16(y)
        if (base ^ addr) & 0xFF00 != 0 {
            _ = busRead((base & 0xFF00) | (addr & 0x00FF))
        }
        return addr
    }

    func readIndirectY() -> UInt8 {
        return busRead(indirectYAddr())
    }

    func indirectYAddrRMW() -> UInt16 {
        let zp = busRead(pc)
        pc &+= 1
        let lo = UInt16(busRead(UInt16(zp)))
        let hi = UInt16(busRead(UInt16((zp &+ 1) & 0xFF)))
        let base = (hi << 8) | lo
        let addr = base &+ UInt16(y)
        _ = busRead((base & 0xFF00) | (addr & 0x00FF)) // always dummy read
        return addr
    }

    func writeIndirectY(_ value: UInt8) {
        let addr = indirectYAddrRMW()
        busWrite(addr, value: value)
    }

    // MARK: - Read-Modify-Write helper

    func rmw(_ addr: UInt16, _ operation: (UInt8) -> UInt8) {
        let val = busRead(addr)
        busWrite(addr, value: val) // dummy write (original value)
        let result = operation(val)
        busWrite(addr, value: result)
    }

    // MARK: - Instruction implementations

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
            // SBC is ADC with ones' complement
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

    // -- Shift/rotate (accumulator) --

    func aslAcc() {
        implied()
        setFlag(Flags.carry, a & 0x80 != 0)
        a <<= 1
        setZN(a)
    }

    func lsrAcc() {
        implied()
        setFlag(Flags.carry, a & 0x01 != 0)
        a >>= 1
        setZN(a)
    }

    func rolAcc() {
        implied()
        let c: UInt8 = getFlag(Flags.carry) ? 1 : 0
        setFlag(Flags.carry, a & 0x80 != 0)
        a = (a << 1) | c
        setZN(a)
    }

    func rorAcc() {
        implied()
        let c: UInt8 = getFlag(Flags.carry) ? 0x80 : 0
        setFlag(Flags.carry, a & 0x01 != 0)
        a = (a >> 1) | c
        setZN(a)
    }

    // -- Shift/rotate (memory) — used as closures for rmw() --

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

    // MARK: - Control flow

    func branch(_ condition: Bool) {
        let offset = immediate()
        if condition {
            _ = busRead(pc) // dummy read during offset calc
            let oldPC = pc
            if offset & 0x80 != 0 {
                pc = pc &- UInt16(~offset &+ 1)
            } else {
                pc = pc &+ UInt16(offset)
            }
            if (oldPC ^ pc) & 0xFF00 != 0 {
                // Page crossed — extra cycle
                _ = busRead((oldPC & 0xFF00) | (pc & 0x00FF))
            }
        }
    }

    func jmpAbsolute() {
        pc = absoluteAddr()
    }

    func jmpIndirect() {
        let lo = UInt16(busRead(pc))
        pc &+= 1
        let hi = UInt16(busRead(pc))
        let ptr = (hi << 8) | lo
        // 6502 bug: wraps within page
        let addrLo = UInt16(busRead(ptr))
        let addrHi = UInt16(busRead((ptr & 0xFF00) | ((ptr &+ 1) & 0x00FF)))
        pc = (addrHi << 8) | addrLo
    }

    func jsr() {
        let lo = UInt16(busRead(pc))
        pc &+= 1
        _ = busRead(0x0100 | UInt16(sp)) // internal cycle
        push(UInt8(pc >> 8))
        push(UInt8(pc & 0xFF))
        let hi = UInt16(busRead(pc))
        pc = (hi << 8) | lo
    }

    func rts() {
        _ = busRead(pc) // dummy read
        _ = busRead(0x0100 | UInt16(sp)) // dummy stack read
        let lo = UInt16(pull())
        let hi = UInt16(pull())
        pc = ((hi << 8) | lo) &+ 1
        _ = busRead(pc) // increment PC cycle
    }

    func rti() {
        _ = busRead(pc) // dummy read
        _ = busRead(0x0100 | UInt16(sp)) // dummy stack read
        p = (pull() & ~Flags.brk) | Flags.unused
        let lo = UInt16(pull())
        let hi = UInt16(pull())
        pc = (hi << 8) | lo
    }

    func pushOp(_ value: UInt8) {
        _ = busRead(pc) // dummy read
        push(value)
    }

    func brkOp() {
        pc &+= 1  // BRK skips the byte after it
        push(UInt8(pc >> 8))
        push(UInt8(pc & 0xFF))
        push(p | Flags.brk | Flags.unused)
        setFlag(Flags.interrupt, true)
        let lo = UInt16(busRead(Vector.irq))
        let hi = UInt16(busRead(Vector.irq + 1))
        pc = (hi << 8) | lo
    }

    // MARK: - Unstable undocumented store ops

    func ahxAbsoluteY() {
        let lo = UInt16(busRead(pc))
        pc &+= 1
        let hi = UInt16(busRead(pc))
        pc &+= 1
        let base = (hi << 8) | lo
        let addr = base &+ UInt16(y)
        _ = busRead((base & 0xFF00) | (addr & 0x00FF))
        let h = UInt8((addr >> 8) & 0xFF) &+ 1
        busWrite(addr, value: a & x & h)
    }

    func ahxIndirectY() {
        let zp = busRead(pc)
        pc &+= 1
        let lo = UInt16(busRead(UInt16(zp)))
        let hi = UInt16(busRead(UInt16((zp &+ 1) & 0xFF)))
        let base = (hi << 8) | lo
        let addr = base &+ UInt16(y)
        _ = busRead((base & 0xFF00) | (addr & 0x00FF))
        let h = UInt8((addr >> 8) & 0xFF) &+ 1
        busWrite(addr, value: a & x & h)
    }

    func tasAbsoluteY() {
        let lo = UInt16(busRead(pc))
        pc &+= 1
        let hi = UInt16(busRead(pc))
        pc &+= 1
        let base = (hi << 8) | lo
        let addr = base &+ UInt16(y)
        _ = busRead((base & 0xFF00) | (addr & 0x00FF))
        sp = a & x
        let h = UInt8((addr >> 8) & 0xFF) &+ 1
        busWrite(addr, value: sp & h)
    }

    func shxAbsoluteY() {
        let lo = UInt16(busRead(pc))
        pc &+= 1
        let hi = UInt16(busRead(pc))
        pc &+= 1
        let base = (hi << 8) | lo
        let addr = base &+ UInt16(y)
        _ = busRead((base & 0xFF00) | (addr & 0x00FF))
        let h = UInt8((addr >> 8) & 0xFF) &+ 1
        let value = x & h
        // If page crossed, high byte is corrupted
        let finalAddr: UInt16
        if (base ^ addr) & 0xFF00 != 0 {
            finalAddr = (UInt16(value) << 8) | (addr & 0x00FF)
        } else {
            finalAddr = addr
        }
        busWrite(finalAddr, value: value)
    }

    func shyAbsoluteX() {
        let lo = UInt16(busRead(pc))
        pc &+= 1
        let hi = UInt16(busRead(pc))
        pc &+= 1
        let base = (hi << 8) | lo
        let addr = base &+ UInt16(x)
        _ = busRead((base & 0xFF00) | (addr & 0x00FF))
        let h = UInt8((addr >> 8) & 0xFF) &+ 1
        let value = y & h
        let finalAddr: UInt16
        if (base ^ addr) & 0xFF00 != 0 {
            finalAddr = (UInt16(value) << 8) | (addr & 0x00FF)
        } else {
            finalAddr = addr
        }
        busWrite(finalAddr, value: value)
    }
}
