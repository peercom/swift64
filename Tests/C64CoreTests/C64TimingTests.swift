import XCTest
@testable import C64Core

final class C64TimingTests: XCTestCase {
    func testBadLineStallsCPUWhileVICTicks() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 0
        c64.vic.badLineDENLatched = true

        for _ in 0..<15 {
            c64.tickOneCycle()
        }

        XCTAssertTrue(c64.vic.badLine)
        XCTAssertEqual(c64.vic.rasterCycle, 15)
        let cyclesBeforeStall = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 16)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeStall + 1)
    }

    func testBadLineBAWarningDoesNotStallCPUBeforeAEC() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 0
        c64.vic.badLineDENLatched = true

        for _ in 0..<12 {
            c64.tickOneCycle()
        }

        XCTAssertTrue(c64.vic.badLine)
        XCTAssertTrue(c64.vic.baLineLow)
        XCTAssertFalse(c64.vic.aecLineLow)
        XCTAssertEqual(c64.vic.busOwner, .cpu)
        let cyclesAtBAWarning = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 13)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesAtBAWarning + 1)

        c64.tickOneCycle()
        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 15)
        XCTAssertTrue(c64.vic.aecLineLow)
        XCTAssertEqual(c64.vic.busOwner, .vicBadLine)
        let cyclesBeforeAECStall = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 16)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeAECStall + 1)
    }

    func testBadLineCPUStallEndsAfterCharacterFetchWindow() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 0
        c64.vic.badLineDENLatched = true

        for _ in 0..<15 {
            c64.tickOneCycle()
        }

        let cyclesBeforeStall = c64.cpu.totalCycles
        for _ in 0..<40 {
            c64.tickOneCycle()
        }

        XCTAssertEqual(c64.vic.rasterCycle, 55)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeStall + 40)

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 56)
        XCTAssertTrue(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeStall + 41)
    }

    func testActiveSpriteDMASlotStallsCPU() {
        let c64 = C64()
        c64.vic.rasterLine = 12
        c64.vic.rasterCycle = 58
        c64.vic.spriteEnabled = 0x01
        c64.vic.spriteY[0] = 12

        XCTAssertEqual(c64.vic.busPhase, .spriteDMA(sprite: 0))
        let cyclesBeforeSpriteDMA = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 59)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSpriteDMA + 1)

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 60)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSpriteDMA + 2)

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 61)
        XCTAssertTrue(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSpriteDMA + 3)
    }

    func testLateSpriteEnableAfterDMACheckDoesNotStallCPU() {
        let c64 = C64()
        c64.vic.rasterLine = 12
        c64.vic.rasterCycle = 55
        c64.vic.spriteEnabled = 0x00
        c64.vic.spriteY[0] = 12

        c64.tickOneCycle()
        c64.tickOneCycle()
        c64.vic.spriteEnabled = 0x01
        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 58)
        XCTAssertEqual(c64.vic.busPhase, .cpu)
        XCTAssertFalse(c64.vic.aecLineLow)
        let cyclesBeforeLateSlot = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 59)
        XCTAssertTrue(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeLateSlot + 1)
    }

    func testSpriteEnableBeforeSecondDMACheckWarnsAndThenStallsCPU() {
        let c64 = C64()
        c64.vic.rasterLine = 12
        c64.vic.rasterCycle = 55
        c64.vic.spriteEnabled = 0x00
        c64.vic.spriteY[0] = 12

        c64.tickOneCycle()
        c64.vic.spriteEnabled = 0x01

        XCTAssertEqual(c64.vic.rasterCycle, 56)
        XCTAssertEqual(c64.vic.busPhase, .cpu)
        XCTAssertFalse(c64.vic.baLineLow)

        let cyclesBeforeSecondCheck = c64.cpu.totalCycles
        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 57)
        XCTAssertEqual(c64.vic.busPhase, .spriteBAWarning(sprite: 0))
        XCTAssertTrue(c64.vic.baLineLow)
        XCTAssertFalse(c64.vic.aecLineLow)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSecondCheck + 1)

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 58)
        XCTAssertEqual(c64.vic.busPhase, .spriteDMA(sprite: 0))
        XCTAssertTrue(c64.vic.aecLineLow)
        let cyclesBeforeDMA = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 59)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeDMA + 1)
    }

    func testSpriteYMatchBeforeSecondDMACheckWarnsAndThenStallsCPU() {
        let c64 = C64()
        c64.vic.rasterLine = 12
        c64.vic.rasterCycle = 55
        c64.vic.spriteEnabled = 0x01
        c64.vic.spriteY[0] = 11

        c64.tickOneCycle()
        c64.vic.spriteY[0] = 12

        XCTAssertEqual(c64.vic.rasterCycle, 56)
        XCTAssertEqual(c64.vic.busPhase, .cpu)
        XCTAssertFalse(c64.vic.baLineLow)

        let cyclesBeforeSecondCheck = c64.cpu.totalCycles
        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 57)
        XCTAssertEqual(c64.vic.busPhase, .spriteBAWarning(sprite: 0))
        XCTAssertTrue(c64.vic.baLineLow)
        XCTAssertFalse(c64.vic.aecLineLow)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSecondCheck + 1)

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 58)
        XCTAssertEqual(c64.vic.busPhase, .spriteDMA(sprite: 0))
        XCTAssertTrue(c64.vic.aecLineLow)
        let cyclesBeforeDMA = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 59)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeDMA + 1)
    }

    func testLatchedSpriteDMAStallsCPUEvenIfEnableClearsBeforeFetch() {
        let c64 = C64()
        c64.vic.rasterLine = 12
        c64.vic.rasterCycle = 55
        c64.vic.spriteEnabled = 0x01
        c64.vic.spriteY[0] = 12

        c64.tickOneCycle()
        c64.tickOneCycle()
        c64.vic.spriteEnabled = 0x00
        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 58)
        XCTAssertEqual(c64.vic.busPhase, .spriteDMA(sprite: 0))
        XCTAssertTrue(c64.vic.aecLineLow)
        let cyclesBeforeLatchedSlot = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 59)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeLatchedSlot + 1)
    }

    func testSpriteDMAContinuationStallsCPUOnSecondSpriteRow() {
        let c64 = C64()
        c64.vic.rasterLine = 7
        c64.vic.rasterCycle = 55
        c64.vic.spriteEnabled = 0x01
        c64.vic.spriteY[0] = 7

        while !(c64.vic.rasterLine == 8 && c64.vic.rasterCycle == 58) {
            c64.tickOneCycle()
        }

        XCTAssertEqual(c64.vic.busPhase, .spriteDMA(sprite: 0))
        XCTAssertTrue(c64.vic.aecLineLow)
        let cyclesBeforeSecondRowDMA = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 59)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSecondRowDMA + 1)
    }

    func testSpriteTwoDMAStallsCPUAcrossRasterlineWrap() {
        let c64 = C64()
        c64.vic.rasterLine = 12
        c64.vic.rasterCycle = 62
        c64.vic.spriteEnabled = 0x04
        c64.vic.spriteY[2] = 12

        XCTAssertEqual(c64.vic.busPhase, .spriteDMA(sprite: 2))
        XCTAssertTrue(c64.vic.aecLineLow)
        let cyclesBeforeSpriteDMA = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterLine, 13)
        XCTAssertEqual(c64.vic.rasterCycle, 0)
        XCTAssertEqual(c64.vic.busPhase, .spriteDMA(sprite: 2))
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSpriteDMA + 1)

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 1)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSpriteDMA + 2)

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 2)
        XCTAssertTrue(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSpriteDMA + 3)
    }

    func testSpriteTwoDMAStallsCPUAcrossRasterlineWrapAfterFinalSpriteRow() {
        let c64 = C64()
        c64.vic.rasterLine = 32
        c64.vic.rasterCycle = 62
        c64.vic.spriteEnabled = 0x04
        c64.vic.spriteY[2] = 12

        XCTAssertEqual(c64.vic.spriteLineRow(for: 2), 20)
        XCTAssertEqual(c64.vic.busPhase, .spriteDMA(sprite: 2))
        let cyclesBeforeSpriteDMA = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterLine, 33)
        XCTAssertEqual(c64.vic.rasterCycle, 0)
        XCTAssertNil(c64.vic.spriteLineRow(for: 2))
        XCTAssertEqual(c64.vic.busPhase, .spriteDMA(sprite: 2))
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSpriteDMA + 1)

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 1)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSpriteDMA + 2)

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 2)
        XCTAssertTrue(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSpriteDMA + 3)
    }

    func testNTSCSpriteThreeDMAStallsCPUAcrossRasterlineWrap() {
        let c64 = C64()
        c64.machineProfile = .ntscC64
        c64.vic.rasterLine = 12
        c64.vic.rasterCycle = 64
        c64.vic.spriteEnabled = 0x08
        c64.vic.spriteY[3] = 12

        XCTAssertEqual(c64.vic.busPhase, .spriteDMA(sprite: 3))
        XCTAssertTrue(c64.vic.aecLineLow)
        let cyclesBeforeSpriteDMA = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterLine, 13)
        XCTAssertEqual(c64.vic.rasterCycle, 0)
        XCTAssertEqual(c64.vic.busPhase, .spriteDMA(sprite: 3))
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSpriteDMA + 1)

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 1)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSpriteDMA + 2)

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 2)
        XCTAssertTrue(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeSpriteDMA + 3)
    }

    func testVICStealAllowsCPUWriteCycleToCompleteThroughRDY() {
        let c64 = C64()
        c64.cpu.pc = 0x0600
        c64.memory.ram[0x0600] = 0xA9  // LDA #$42
        c64.memory.ram[0x0601] = 0x42
        c64.memory.ram[0x0602] = 0x85  // STA $10
        c64.memory.ram[0x0603] = 0x10

        for _ in 0..<4 {
            c64.tickOneCycle()
        }

        XCTAssertEqual(c64.cpu.a, 0x42)
        XCTAssertEqual(c64.cpu.cycle, 2)
        XCTAssertEqual(c64.memory.ram[0x0010], 0x00)

        c64.vic.rasterLine = 12
        c64.vic.rasterCycle = 58
        c64.vic.spriteEnabled = 0x01
        c64.vic.spriteY[0] = 12

        XCTAssertTrue(c64.vic.aecLineLow)
        c64.tickOneCycle()

        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.memory.ram[0x0010], 0x42)
        XCTAssertEqual(c64.cpu.cycle, 0)
    }

    func testC64TicksDecayMemoryMapOpenBus() {
        let c64 = C64()
        c64.memory.cpuDataBusDecayDelay = 2
        c64.cpu.pc = 0x0600
        c64.memory.ram[0x0600] = 0x02  // KIL

        for _ in 0..<11 {
            c64.tickOneCycle()
        }
        XCTAssertTrue(c64.cpu.jammed)

        c64.memory.ram[0xC000] = 0x61

        XCTAssertEqual(c64.memory.read(0xC000), 0x61)
        XCTAssertEqual(c64.memory.read(0xDE00), 0x61)

        c64.tickOneCycle()
        c64.tickOneCycle()
        XCTAssertEqual(c64.memory.read(0xDE00), 0xFF)
    }

    func testSpriteBAWarningDoesNotStallCPUBeforeDMA() {
        let c64 = C64()
        c64.vic.rasterLine = 12
        c64.vic.rasterCycle = 55
        c64.vic.spriteEnabled = 0x01
        c64.vic.spriteY[0] = 12

        XCTAssertEqual(c64.vic.busPhase, .spriteBAWarning(sprite: 0))
        XCTAssertTrue(c64.vic.baLineLow)
        XCTAssertFalse(c64.vic.aecLineLow)
        let cyclesAtBAWarning = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 56)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesAtBAWarning + 1)

        c64.tickOneCycle()
        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 58)
        XCTAssertEqual(c64.vic.busPhase, .spriteDMA(sprite: 0))
        let cyclesBeforeDMA = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 59)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeDMA + 1)
    }

    func testVICLowPhaseRefreshAndDisplayDoNotStallCPU() {
        let c64 = C64()
        c64.vic.rasterLine = 20
        c64.vic.rasterCycle = 10

        let cyclesBefore = c64.cpu.totalCycles

        for index in 0..<5 {
            XCTAssertEqual(c64.vic.lowPhaseAccess, .refresh(index: index))
            XCTAssertFalse(c64.vic.aecLineLow)
            c64.tickOneCycle()
        }

        XCTAssertEqual(c64.vic.rasterCycle, 15)
        XCTAssertEqual(c64.vic.lowPhaseAccess, .displayData(column: 0))
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBefore + 5)

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 16)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBefore + 6)
    }

    func testDisplayDisabledPreventsBadLineCPUStall() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 0
        c64.vic.writeRegister(0x11, value: 0x0B) // Same y-scroll as default, DEN off.

        let cyclesBefore = c64.cpu.totalCycles
        for _ in 0..<56 {
            c64.tickOneCycle()
        }

        XCTAssertFalse(c64.vic.badLine)
        XCTAssertEqual(c64.vic.rasterCycle, 56)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBefore + 56)
    }

    func testDENOnFirstBadLineArmsLaterBadLinesEvenIfDisplayIsDisabled() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.firstBadLine)
        c64.vic.rasterCycle = 0
        c64.vic.writeRegister(0x11, value: 0x18)

        c64.tickOneCycle()

        XCTAssertTrue(c64.vic.badLineDENLatched)

        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 0
        c64.vic.writeRegister(0x11, value: 0x03)

        for _ in 0..<15 {
            c64.tickOneCycle()
        }

        XCTAssertTrue(c64.vic.badLine)
        XCTAssertEqual(c64.vic.rasterCycle, 15)
        let cyclesBeforeStall = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 16)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeStall + 1)
    }

    func testDENOffOnFirstBadLineSuppressesLaterBadLinesEvenIfDisplayIsEnabled() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.firstBadLine)
        c64.vic.rasterCycle = 0
        c64.vic.writeRegister(0x11, value: 0x08)

        c64.tickOneCycle()

        XCTAssertFalse(c64.vic.badLineDENLatched)

        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 0
        c64.vic.writeRegister(0x11, value: 0x1B)

        let cyclesBefore = c64.cpu.totalCycles
        for _ in 0..<56 {
            c64.tickOneCycle()
        }

        XCTAssertFalse(c64.vic.badLine)
        XCTAssertEqual(c64.vic.rasterCycle, 56)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBefore + 56)
    }

    func testYScrollWriteCanStartBadLineBusStealDuringFetchWindow() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 20
        c64.vic.badLineDENLatched = true
        c64.vic.writeRegister(0x11, value: 0x10)

        XCTAssertFalse(c64.vic.badLine)

        let cyclesBefore = c64.cpu.totalCycles
        c64.vic.writeRegister(0x11, value: 0x13)
        c64.tickOneCycle()

        XCTAssertTrue(c64.vic.badLine)
        XCTAssertEqual(c64.vic.rasterCycle, 21)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBefore + 1)
    }

    func testYScrollWriteStartingBadLineLatchesUnstableStartupDataBeforeMatrixFetches() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 20
        c64.vic.badLineDENLatched = true
        c64.vic.writeRegister(0x11, value: 0x10)
        c64.memory.ram[0x0405] = 0x41
        c64.memory.ram[0x0408] = 0x42

        c64.vic.writeRegister(0x11, value: 0x13)
        c64.tickOneCycle()

        XCTAssertTrue(c64.vic.badLine)
        XCTAssertEqual(c64.vic.badLineFetchMask, UInt64(1) << 5)
        XCTAssertFalse(c64.vic.displayLineBufferValid)
        XCTAssertEqual(c64.vic.displayLineBufferBase, 0)
        XCTAssertEqual(c64.vic.lineBuffer[5], 0xFF)
        XCTAssertEqual(c64.vic.colorBuffer[5], 0x0F)

        c64.tickOneCycle()
        c64.tickOneCycle()
        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.badLineFetchMask, (UInt64(1) << 5) | (UInt64(1) << 6) | (UInt64(1) << 7) | (UInt64(1) << 8))
        XCTAssertEqual(c64.vic.lineBuffer[6], 0xFF)
        XCTAssertEqual(c64.vic.lineBuffer[7], 0xFF)
        XCTAssertEqual(c64.vic.lineBuffer[8], 0x42)
    }

    func testYScrollWriteCanStartBadLineAtLastFetchCycleWithUnstableStartupData() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 54
        c64.vic.badLineDENLatched = true
        c64.vic.writeRegister(0x11, value: 0x10)
        c64.memory.ram[0x0427] = 0x5A

        c64.vic.writeRegister(0x11, value: 0x13)
        c64.tickOneCycle()

        XCTAssertTrue(c64.vic.badLine)
        XCTAssertEqual(c64.vic.rasterCycle, 55)
        XCTAssertEqual(c64.vic.badLineFetchMask, UInt64(1) << 39)
        XCTAssertEqual(c64.vic.lineBuffer[39], 0xFF)
        XCTAssertEqual(c64.vic.colorBuffer[39], 0x0F)
    }

    func testYScrollWriteCannotStartBadLineAfterLastFetchCycle() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 55
        c64.vic.badLineDENLatched = true
        c64.vic.writeRegister(0x11, value: 0x10)

        c64.vic.writeRegister(0x11, value: 0x13)
        c64.tickOneCycle()

        XCTAssertFalse(c64.vic.badLine)
        XCTAssertEqual(c64.vic.rasterCycle, 56)
        XCTAssertEqual(c64.vic.badLineFetchMask, 0)
    }

    func testYScrollWriteDuringActiveBadLineDoesNotRestartRowOrFetchState() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 20
        c64.vic.badLineDENLatched = true
        c64.vic.badLine = true
        c64.vic.rowCounter = 5
        c64.vic.displayLineBufferBase = 80
        c64.vic.badLineFetchMask = 0x03
        c64.vic.lineBuffer[0] = 0x41
        c64.vic.lineBuffer[1] = 0x42

        c64.vic.writeRegister(0x11, value: 0x13)

        XCTAssertTrue(c64.vic.badLine)
        XCTAssertEqual(c64.vic.rowCounter, 5)
        XCTAssertEqual(c64.vic.displayLineBufferBase, 80)
        XCTAssertEqual(c64.vic.badLineFetchMask, 0x03)
        XCTAssertEqual(c64.vic.lineBuffer[0], 0x41)
        XCTAssertEqual(c64.vic.lineBuffer[1], 0x42)
    }

    func testYScrollWriteCanSuppressBadLineBusStealDuringFetchWindow() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 20
        c64.vic.badLineDENLatched = true
        c64.vic.writeRegister(0x11, value: 0x13)

        XCTAssertTrue(c64.vic.badLine)

        let cyclesBefore = c64.cpu.totalCycles
        c64.vic.writeRegister(0x11, value: 0x10)
        c64.tickOneCycle()

        XCTAssertFalse(c64.vic.badLine)
        XCTAssertEqual(c64.vic.rasterCycle, 21)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBefore + 1)
    }

    func testYScrollWriteAfterFetchWindowCannotStartBadLine() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 56
        c64.vic.badLineDENLatched = true
        c64.vic.writeRegister(0x11, value: 0x10)

        XCTAssertFalse(c64.vic.badLine)

        let cyclesBefore = c64.cpu.totalCycles
        c64.vic.writeRegister(0x11, value: 0x13)
        c64.tickOneCycle()

        XCTAssertFalse(c64.vic.badLine)
        XCTAssertEqual(c64.vic.rasterCycle, 57)
        XCTAssertTrue(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBefore + 1)
        XCTAssertEqual(c64.vic.badLineFetchMask, 0)
    }

    func testLateYScrollWriteDoesNotResetExistingDisplayRowState() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 56
        c64.vic.badLineDENLatched = true
        c64.vic.writeRegister(0x11, value: 0x10)
        c64.vic.rowCounter = 5
        c64.vic.displayLineBufferBase = 80
        c64.vic.badLineFetchMask = 0x03
        c64.vic.lineBuffer[0] = 0x41
        c64.vic.lineBuffer[1] = 0x42

        c64.vic.writeRegister(0x11, value: 0x13)

        XCTAssertFalse(c64.vic.badLine)
        XCTAssertEqual(c64.vic.rowCounter, 5)
        XCTAssertEqual(c64.vic.displayLineBufferBase, 80)
        XCTAssertEqual(c64.vic.badLineFetchMask, 0x03)
        XCTAssertEqual(c64.vic.lineBuffer[0], 0x41)
        XCTAssertEqual(c64.vic.lineBuffer[1], 0x42)
    }

    func testRasterOutsideDisplayAreaDoesNotStallCPU() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop - 1)
        c64.vic.rasterCycle = 0

        let cyclesBefore = c64.cpu.totalCycles
        for _ in 0..<56 {
            c64.tickOneCycle()
        }

        XCTAssertFalse(c64.vic.badLine)
        XCTAssertEqual(c64.vic.rasterCycle, 56)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBefore + 56)
    }

    func testBadLineCanOccurBeforeVisibleDisplayTop() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.firstBadLine)
        c64.vic.rasterCycle = 0
        c64.vic.writeRegister(0x11, value: 0x18)

        for _ in 0..<15 {
            c64.tickOneCycle()
        }

        XCTAssertTrue(c64.vic.badLine)
        XCTAssertEqual(c64.vic.rasterCycle, 15)
        let cyclesBeforeStall = c64.cpu.totalCycles

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 16)
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeStall + 1)
    }

    func testRasterAfterBadLineRangeDoesNotStallCPU() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.lastBadLine + 1)
        c64.vic.rasterCycle = 0
        c64.vic.writeRegister(0x11, value: 0x18)

        let cyclesBefore = c64.cpu.totalCycles
        for _ in 0..<56 {
            c64.tickOneCycle()
        }

        XCTAssertFalse(c64.vic.badLine)
        XCTAssertEqual(c64.vic.rasterCycle, 56)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBefore + 56)
    }
}
