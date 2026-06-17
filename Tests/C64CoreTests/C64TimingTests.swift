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
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeStall)
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
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeStall)

        c64.tickOneCycle()

        XCTAssertEqual(c64.vic.rasterCycle, 56)
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeStall + 1)
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
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeStall)
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
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBefore)
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
        XCTAssertEqual(c64.cpu.totalCycles, cyclesBeforeStall)
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
