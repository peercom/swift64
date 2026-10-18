import XCTest
@testable import C64Core
@testable import Emu6502

final class REUTests: XCTestCase {
    private func makeMachine(_ model: REU.Model = .reu1750) -> C64 {
        let c64 = C64()
        c64.attachREU(model)
        c64.memory.portData = 0x37
        return c64
    }

    private func setupTransfer(_ c64: C64, c64Address: UInt16, reuAddress: UInt32, length: UInt16, control: UInt8 = 0) {
        let m = c64.memory
        m.write(0xDF02, value: UInt8(c64Address & 0xFF)); m.write(0xDF03, value: UInt8(c64Address >> 8))
        m.write(0xDF04, value: UInt8(reuAddress & 0xFF)); m.write(0xDF05, value: UInt8((reuAddress >> 8) & 0xFF))
        m.write(0xDF06, value: UInt8((reuAddress >> 16) & 0xFF))
        m.write(0xDF07, value: UInt8(length & 0xFF)); m.write(0xDF08, value: UInt8(length >> 8))
        m.write(0xDF0A, value: control)
    }

    /// Run the bus until the controller releases it, counting cycles.
    @discardableResult
    private func runDMA(_ c64: C64, limit: Int = 1_000_000) -> Int {
        var cycles = 0
        while c64.reu!.dmaActive && cycles < limit { c64.tickOneCycle(); cycles += 1 }
        return cycles
    }

    // MARK: - Registers

    func testRegistersReadBackWithUnusedBitsHighAndMirrorThroughIO2() {
        let c64 = makeMachine()
        let m = c64.memory
        XCTAssertEqual(m.read(0xDF00), 0x10, "1750: size bit set, no flags")
        XCTAssertEqual(m.read(0xDF01), 0x10, "FF00 bit reads set after reset")
        XCTAssertEqual(m.read(0xDF06), 0xF8, "bank bits 3-7 read as 1")
        XCTAssertEqual(m.read(0xDF07), 0xFF); XCTAssertEqual(m.read(0xDF08), 0xFF)
        XCTAssertEqual(m.read(0xDF09), 0x1F); XCTAssertEqual(m.read(0xDF0A), 0x3F)
        for register in 0x0B...0x1F { XCTAssertEqual(m.read(UInt16(0xDF00 + register)), 0xFF, "$DF\(String(format: "%02X", register))") }
        m.write(0xDF26, value: 0x05)
        XCTAssertEqual(m.read(0xDF06), 0xFD, "registers mirror every 32 bytes")
        XCTAssertEqual(m.read(0xDFE6), 0xFD)
        m.write(0xDF09, value: 0xFF); XCTAssertEqual(m.read(0xDF09), 0xFF)
        m.write(0xDF0A, value: 0x80); XCTAssertEqual(m.read(0xDF0A), 0xBF)

        let small = makeMachine(.reu1700)
        XCTAssertEqual(small.memory.read(0xDF00), 0x00, "1700: size bit clear")
        let big = makeMachine(.reu16MB)
        big.memory.write(0xDF06, value: 0x5A)
        XCTAssertEqual(big.memory.read(0xDF06), 0x5A, "16 MB units use all bank bits")
        let mid = makeMachine(.reu2MB)
        mid.memory.write(0xDF06, value: 0x00)
        XCTAssertEqual(mid.memory.read(0xDF06), 0xE0, "2 MB units use five bank bits")
    }

    func testPowerOnPatternAndResetKeepRAM() {
        let c64 = makeMachine()
        let reu = c64.reu!
        XCTAssertEqual(Array(reu.ram[0..<8]), [0xFF, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF])
        XCTAssertEqual(Array(reu.ram[0x20000..<0x20004]), [0x00, 0xFF, 0xFF, 0x00], "second 128K half is inverted")
        reu.ram[0x1234] = 0x42
        c64.reset()
        XCTAssertEqual(reu.ram[0x1234], 0x42)
        XCTAssertEqual(c64.memory.read(0xDF01), 0x10)
    }

    // MARK: - Transfers

    func testStashFetchSwapAndVerifyMoveDataAndTakeTheDocumentedCycles() {
        let c64 = makeMachine()
        let m = c64.memory
        for offset in 0..<256 { m.ram[0x2000 + offset] = UInt8(offset ^ 0x5A) }
        for offset in 0..<256 { m.ram[0x3000 + offset] = UInt8(255 - offset) }

        // Stash: 256 bytes, one per cycle.
        setupTransfer(c64, c64Address: 0x2000, reuAddress: 0x010000, length: 256)
        m.write(0xDF01, value: 0x90)
        XCTAssertTrue(c64.reu!.dmaActive)
        XCTAssertEqual(runDMA(c64), 256)
        XCTAssertEqual(Array(c64.reu!.ram[0x10000..<0x10100]), Array(m.ram[0x2000..<0x2100]))
        XCTAssertEqual(m.read(0xDF00) & 0x40, 0x40, "end of block")
        XCTAssertEqual(m.read(0xDF00) & 0x40, 0x00, "status read cleared it")

        // Fetch it back somewhere else.
        setupTransfer(c64, c64Address: 0x4000, reuAddress: 0x010000, length: 256)
        m.write(0xDF01, value: 0x91)
        XCTAssertEqual(runDMA(c64), 256)
        XCTAssertEqual(Array(m.ram[0x4000..<0x4100]), Array(m.ram[0x2000..<0x2100]))

        // Swap: two cycles per byte.
        setupTransfer(c64, c64Address: 0x3000, reuAddress: 0x010000, length: 256)
        m.write(0xDF01, value: 0x92)
        XCTAssertEqual(runDMA(c64), 512)
        XCTAssertEqual(Array(m.ram[0x3000..<0x3100]), Array(m.ram[0x2000..<0x2100]))
        XCTAssertEqual(Array(c64.reu!.ram[0x10000..<0x10100]), (0..<256).map { UInt8(255 - $0) })

        // Verify: equal data passes, a mismatch faults and stops. Stash the
        // swapped buffer first so both sides hold the same bytes.
        setupTransfer(c64, c64Address: 0x3000, reuAddress: 0x010000, length: 256)
        m.write(0xDF01, value: 0x90)
        runDMA(c64)
        setupTransfer(c64, c64Address: 0x3000, reuAddress: 0x010000, length: 256)
        m.write(0xDF01, value: 0x93)
        XCTAssertEqual(runDMA(c64), 256)
        XCTAssertEqual(m.read(0xDF00) & 0x60, 0x40, "no fault")
        m.ram[0x3000 + 100] ^= 0xFF
        setupTransfer(c64, c64Address: 0x3000, reuAddress: 0x010000, length: 256)
        m.write(0xDF01, value: 0x93)
        XCTAssertEqual(runDMA(c64), 101, "stops after the mismatching byte")
        XCTAssertEqual(m.read(0xDF00) & 0x60, 0x20, "fault without end of block")
        XCTAssertEqual(m.read(0xDF02), 0x65); XCTAssertEqual(m.read(0xDF03), 0x30)
        XCTAssertEqual(UInt16(m.read(0xDF07)) | UInt16(m.read(0xDF08)) << 8, 155, "remaining length after the fault")

        // A fault on the second-to-last or last byte also sets END OF BLOCK and
        // leaves the length at 1 (`twoblocks` rows with status $70).
        for faultOffset in [254, 255] {
            setupTransfer(c64, c64Address: 0x3000, reuAddress: 0x010000, length: 256)
            m.write(0xDF01, value: 0x90)
            runDMA(c64)
            m.ram[0x3000 + faultOffset] ^= 0xFF
            setupTransfer(c64, c64Address: 0x3000, reuAddress: 0x010000, length: 256)
            m.write(0xDF01, value: 0x93)
            XCTAssertEqual(runDMA(c64), faultOffset + 1)
            XCTAssertEqual(m.read(0xDF00) & 0x60, 0x60, "fault at offset \(faultOffset)")
            XCTAssertEqual(m.read(0xDF07), 1); XCTAssertEqual(m.read(0xDF08), 0)
            m.ram[0x3000 + faultOffset] ^= 0xFF
        }
    }

    func testRegisterDumpAfterStashMatchesTwoblocksHardwareReference() {
        // `misc/twoblocks` first line on a 1750: 16 bytes from $0680 to REU 0.
        let c64 = makeMachine()
        let m = c64.memory
        setupTransfer(c64, c64Address: 0x0680, reuAddress: 0, length: 0x10)
        m.write(0xDF09, value: 0); m.write(0xDF0A, value: 0)
        m.write(0xDF01, value: 0x90)
        runDMA(c64)
        let dump = (0..<16).map { m.read(UInt16(0xDF00 + $0)) }
        XCTAssertEqual(dump, [0x50, 0x10, 0x90, 0x06, 0x10, 0x00, 0xF8, 0x01, 0x00, 0x1F, 0x3F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
    }

    func testLengthZeroTransfersSixtyFourKAndFixedAddressesRepeat() {
        let c64 = makeMachine()
        let m = c64.memory
        for address in 0..<0x10000 { m.ram[address] = UInt8(truncatingIfNeeded: address &* 7) }
        c64.vic.writeRegister(0x11, value: 0x0B)  // display off: no bad lines steal cycles
        setupTransfer(c64, c64Address: 0x0000, reuAddress: 0x020000, length: 0)
        m.write(0xDF01, value: 0x90)
        XCTAssertEqual(runDMA(c64), 0x10000, "length 0 moves 65,536 bytes")
        // RAM is visible to the DMA below BASIC ROM and in the $C000 block; the
        // rest is ROM and I/O under the default banking.
        XCTAssertEqual(Array(c64.reu!.ram[0x20000..<0x2A000]), Array(m.ram[0x0000..<0xA000]))
        XCTAssertEqual(Array(c64.reu!.ram[0x2C000..<0x2D000]), Array(m.ram[0xC000..<0xD000]))
        XCTAssertEqual(m.read(0xDF02), 0x00); XCTAssertEqual(m.read(0xDF03), 0x00, "the C64 address wrapped")
        XCTAssertEqual(m.read(0xDF06), 0xFB, "bank 3 after the wrap")

        // Fixed REU address: every byte lands in one cell; fixed C64 address: one source byte repeats.
        setupTransfer(c64, c64Address: 0x5000, reuAddress: 0x000100, length: 8, control: 0x40)
        for offset in 0..<8 { m.ram[0x5000 + offset] = UInt8(0xA0 + offset) }
        m.write(0xDF01, value: 0x90)
        runDMA(c64)
        XCTAssertEqual(c64.reu!.ram[0x100], 0xA7)
        XCTAssertEqual(c64.reu!.ram[0x101], 0x00)
        XCTAssertEqual(m.read(0xDF04), 0x00, "fixed REU address does not advance")
        setupTransfer(c64, c64Address: 0x5000, reuAddress: 0x000200, length: 8, control: 0x80)
        m.write(0xDF01, value: 0x90)
        runDMA(c64)
        XCTAssertEqual(Array(c64.reu!.ram[0x200..<0x208]), [UInt8](repeating: 0xA0, count: 8))
        XCTAssertEqual(m.read(0xDF02), 0x00); XCTAssertEqual(m.read(0xDF03), 0x50)
    }

    func testAutoloadReloadsCountersAndFF00TriggerWaits() {
        let c64 = makeMachine()
        let m = c64.memory
        setupTransfer(c64, c64Address: 0x6000, reuAddress: 0x000300, length: 4)
        m.write(0xDF01, value: 0xB0)  // execute, autoload, immediate, stash
        runDMA(c64)
        XCTAssertEqual(m.read(0xDF02), 0x00); XCTAssertEqual(m.read(0xDF03), 0x60)
        XCTAssertEqual(m.read(0xDF04), 0x00); XCTAssertEqual(m.read(0xDF05), 0x03)
        XCTAssertEqual(m.read(0xDF07), 0x04)

        // FF00 bit clear: the transfer waits for a write to $FF00.
        m.ram[0x6000] = 0x77
        setupTransfer(c64, c64Address: 0x6000, reuAddress: 0x000400, length: 1)
        m.write(0xDF01, value: 0x80)
        XCTAssertFalse(c64.reu!.dmaActive)
        XCTAssertTrue(c64.reu!.waitingForFF00)
        for _ in 0..<10 { c64.tickOneCycle() }
        XCTAssertFalse(c64.reu!.dmaActive)
        m.write(0xFF00, value: 0x00)
        XCTAssertTrue(c64.reu!.dmaActive)
        runDMA(c64)
        XCTAssertEqual(c64.reu!.ram[0x400], 0x77)
        XCTAssertEqual(m.read(0xDF01), 0x10, "execute cleared, FF00 bit set")

        // Writing the command without EXECUTE disarms a pending FF00 trigger.
        m.write(0xDF01, value: 0x80)
        m.write(0xDF01, value: 0x00)
        m.write(0xFF00, value: 0x00)
        XCTAssertFalse(c64.reu!.dmaActive)
    }

    // MARK: - Bus arbitration

    func testDMAHaltsTheCPUAndRMWTriggerLosesItsSecondWrite() {
        // `rmw-trigger`: INC $FF00 arms with the dummy write; the real write is lost.
        let c64 = makeMachine()
        let m = c64.memory
        m.portData = 0x35
        m.ram[0xFF00] = 0x10
        m.ram[0x7000] = 0x33
        setupTransfer(c64, c64Address: 0x7000, reuAddress: 0x000500, length: 3)
        m.write(0xDF01, value: 0x80)
        // Program: INC $FF00 ; LDA #$42 ; STA $7100
        let program: [UInt8] = [0xEE, 0x00, 0xFF, 0xA9, 0x42, 0x8D, 0x00, 0x71]
        for (offset, byte) in program.enumerated() { m.ram[0x1000 + offset] = byte }
        c64.cpu.pc = 0x1000
        for _ in 0..<5 { c64.tickOneCycle() }  // through the dummy write
        XCTAssertTrue(c64.reu!.dmaActive, "the dummy write triggered the transfer")
        XCTAssertEqual(m.ram[0xFF00], 0x10)
        c64.tickOneCycle()  // the CPU's second write cycle, disconnected
        XCTAssertEqual(m.ram[0xFF00], 0x10, "the incremented value never reaches RAM")
        XCTAssertEqual(c64.cpu.cycle, 0, "the CPU finished the instruction internally")
        let cyclesHeld = runDMA(c64)
        XCTAssertEqual(cyclesHeld, 2, "three bytes, one already moved in the disconnected cycle")
        XCTAssertEqual(Array(c64.reu!.ram[0x500..<0x503]), [0x33, m.ram[0x7001], m.ram[0x7002]])
        XCTAssertEqual(c64.cpu.pc, 0x1003, "the CPU did not fetch while halted")
        for _ in 0..<6 { c64.tickOneCycle() }
        XCTAssertEqual(m.ram[0x7100], 0x42, "execution resumes afterwards")
    }

    func testDMAPausesWhileVICHoldsBALow() {
        let c64 = makeMachine()
        let m = c64.memory
        setupTransfer(c64, c64Address: 0x2000, reuAddress: 0, length: 200)
        // Bad line: lines $30-$F7 with YSCROLL match and DEN; the VIC takes 40 cycles plus 3 of warning.
        c64.vic.writeRegister(0x11, value: 0x1B)
        c64.vic.badLineDENLatched = true
        c64.vic.rasterLine = 0x33
        c64.vic.rasterCycle = 0  // the bad-line check runs at the next tick
        m.write(0xDF01, value: 0x90)
        let cycles = runDMA(c64)
        XCTAssertGreaterThanOrEqual(cycles, 200 + 43, "the transfer waited for the bad-line fetches")
        XCTAssertEqual(Array(c64.reu!.ram[0..<200]), Array(m.ram[0x2000..<0x2000 + 200]))

        let quiet = makeMachine()
        setupTransfer(quiet, c64Address: 0x2000, reuAddress: 0, length: 200)
        quiet.vic.writeRegister(0x11, value: 0x0B)  // display off: no bad lines
        quiet.vic.rasterLine = 0x33
        quiet.vic.rasterCycle = 0
        quiet.memory.write(0xDF01, value: 0x90)
        XCTAssertEqual(runDMA(quiet), 200)
    }

    func testDMABypassesTheCPUPortAndReachesIORegisters() {
        let c64 = makeMachine()
        let m = c64.memory
        // `cpuport`: the REU reads RAM under $0000/$0001, not the 6510 port.
        m.ram[0x0000] = 0x11; m.ram[0x0001] = 0x22
        setupTransfer(c64, c64Address: 0x0000, reuAddress: 0x000600, length: 2)
        m.write(0xDF01, value: 0x90)
        runDMA(c64)
        XCTAssertEqual(Array(c64.reu!.ram[0x600..<0x602]), [0x11, 0x22])
        c64.reu!.ram[0x700] = 0x44; c64.reu!.ram[0x701] = 0x55
        setupTransfer(c64, c64Address: 0x0000, reuAddress: 0x000700, length: 2)
        m.write(0xDF01, value: 0x91)
        runDMA(c64)
        XCTAssertEqual(m.ram[0x0000], 0x44); XCTAssertEqual(m.ram[0x0001], 0x55)
        XCTAssertEqual(m.portDirection, 0x2F); XCTAssertEqual(m.portData, 0x37, "the port itself is untouched")

        // `ioglitch`/`xfertiming`: a fetch into $D020 recolours the border.
        c64.reu!.ram[0x800] = 0x05
        setupTransfer(c64, c64Address: 0xD020, reuAddress: 0x000800, length: 1)
        m.write(0xDF01, value: 0x91)
        runDMA(c64)
        XCTAssertEqual(c64.vic.borderColor, 0x05)
        // Colour RAM keeps only the low nibble.
        c64.reu!.ram[0x801] = 0xF7
        setupTransfer(c64, c64Address: 0xD800, reuAddress: 0x000801, length: 1)
        m.write(0xDF01, value: 0x91)
        runDMA(c64)
        XCTAssertEqual(m.colorRAM[0], 0x07)
    }

    func testEndOfBlockInterruptFollowsTheMaskAndClearsOnStatusRead() {
        let c64 = makeMachine()
        let m = c64.memory
        setupTransfer(c64, c64Address: 0x2000, reuAddress: 0, length: 2)
        m.write(0xDF09, value: 0xC0)  // enable + end of block
        m.write(0xDF01, value: 0x90)
        runDMA(c64)
        XCTAssertTrue(c64.reu!.interruptActive)
        XCTAssertTrue(c64.cpu.irqLine)
        XCTAssertEqual(m.read(0xDF00), 0xD0, "pending + end of block + size")
        XCTAssertFalse(c64.reu!.interruptActive)
        XCTAssertFalse(c64.cpu.irqLine)

        // Enabling the mask after the flag is set raises the line at once.
        m.write(0xDF09, value: 0x00)
        setupTransfer(c64, c64Address: 0x2000, reuAddress: 0, length: 2)
        m.write(0xDF01, value: 0x90)
        runDMA(c64)
        XCTAssertFalse(c64.cpu.irqLine)
        m.write(0xDF09, value: 0xC0)
        XCTAssertTrue(c64.cpu.irqLine)
        _ = m.read(0xDF00)
        XCTAssertFalse(c64.cpu.irqLine)
    }

    func testBankWrapFollowsTheInstalledMemory() {
        let unit1700 = makeMachine(.reu1700)
        unit1700.reu!.ram[0x100] = 0x99
        unit1700.memory.ram[0x2000] = 0
        setupTransfer(unit1700, c64Address: 0x2000, reuAddress: 0x020100, length: 1)  // bank 2 mirrors bank 0
        unit1700.memory.write(0xDF01, value: 0x91)
        runDMA(unit1700)
        XCTAssertEqual(unit1700.memory.ram[0x2000], 0x99)

        // `floatingbus`: an unpopulated bank reads the last byte on the unit's bus.
        let unit1764 = makeMachine(.reu1764)
        unit1764.memory.ram[0x2000] = 0x00
        setupTransfer(unit1764, c64Address: 0x2000, reuAddress: 0x050000, length: 1)  // bank 5 is not populated
        unit1764.memory.write(0xDF01, value: 0x90)  // write 0 into the void
        runDMA(unit1764)
        setupTransfer(unit1764, c64Address: 0x2001, reuAddress: 0x050000, length: 1)
        unit1764.memory.write(0xDF01, value: 0x91)
        runDMA(unit1764)
        XCTAssertEqual(unit1764.memory.ram[0x2001], 0x00, "reads back the value just written")
        unit1764.reu!.ram[0x1234] = 0x5C
        setupTransfer(unit1764, c64Address: 0x2002, reuAddress: 0x001234, length: 1)
        unit1764.memory.write(0xDF01, value: 0x91)
        runDMA(unit1764)
        setupTransfer(unit1764, c64Address: 0x2003, reuAddress: 0x050000, length: 1)
        unit1764.memory.write(0xDF01, value: 0x91)
        runDMA(unit1764)
        XCTAssertEqual(unit1764.memory.ram[0x2003], 0x5C, "a valid read refreshes the floating value")

        let unit1750 = makeMachine(.reu1750)
        unit1750.reu!.ram[0x7FFFF] = 0x66
        setupTransfer(unit1750, c64Address: 0x2000, reuAddress: 0x07FFFF, length: 2)  // wraps to bank 0
        unit1750.reu!.ram[0] = 0x67
        unit1750.memory.write(0xDF01, value: 0x91)
        runDMA(unit1750)
        XCTAssertEqual(Array(unit1750.memory.ram[0x2000..<0x2002]), [0x66, 0x67])
        XCTAssertEqual(unit1750.memory.read(0xDF06), 0xF8, "bank counter wrapped to 0")
    }

    func testDetachRestoresCartridgeIO2AndSnapshotCarriesTheUnit() throws {
        let c64 = makeMachine(.reu1700)
        c64.reu!.ram[0x1000] = 0xAB
        setupTransfer(c64, c64Address: 0x2000, reuAddress: 0x001000, length: 300)
        c64.memory.write(0xDF01, value: 0x91)
        for _ in 0..<100 { c64.tickOneCycle() }
        XCTAssertTrue(c64.reu!.dmaActive)
        let snapshot = try c64.saveState()

        let restored = C64()
        try restored.restoreState(from: snapshot)
        XCTAssertEqual(restored.reu?.model, .reu1700)
        XCTAssertTrue(restored.reu!.dmaActive)
        runDMA(c64); runDMA(restored)
        XCTAssertEqual(restored.memory.ram[0x2000..<0x2000 + 300], c64.memory.ram[0x2000..<0x2000 + 300])
        XCTAssertEqual(restored.reu!.ram, c64.reu!.ram)

        c64.detachREU()
        XCTAssertNil(c64.reu)
        XCTAssertEqual(c64.memory.read(0xDF00), c64.memory.cpuDataBus, "IO2 is open bus again")
        let detachedSnapshot = try c64.saveState()
        try restored.restoreState(from: detachedSnapshot)
        XCTAssertNil(restored.reu, "a snapshot without a unit detaches it")
    }

    func testStoredPropertyCountMatchesSnapshotCode() {
        XCTAssertEqual(Mirror(reflecting: REU(model: .reu1700)).children.count, REU.snapshotStoredPropertyCount)
    }
}
