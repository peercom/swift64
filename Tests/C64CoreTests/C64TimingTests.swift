import XCTest
@testable import C64Core

final class C64TimingTests: XCTestCase {
    func testBadLineStallsCPUWhileVICTicks() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 0

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
}
