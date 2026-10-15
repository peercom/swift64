import XCTest
@testable import C64Core

final class VICGraphicsColorLatchTests: XCTestCase {
    private let standards: [C64VideoStandard] = [.pal, .ntsc]
    // Shared reference crop; NTSC's skipped X=392...395 output mapping is a
    // separate open issue, not part of this graphics color-latch proof.
    private let borderCropWidth = 376

    private func machine(_ standard: C64VideoStandard) -> VIC {
        let vic = VIC()
        vic.videoStandard = standard
        vic.rasterLine = 100
        vic.controlReg1 = 0x3B
        vic.controlReg2 = 0x08
        vic.memoryPointers = 0x18
        vic.backgroundColor = [6, 3, 4, 5]
        vic.borderColor = 14
        vic.displayActive = true
        vic.verticalBorderActive = false
        vic.verticalBorderClosePending = false
        vic.horizontalBorderActive = false
        vic.lineBuffer = [UInt8](repeating: 0x21, count: 40)
        vic.lineBuffer[39] = 0xA7
        vic.readMemory = { _ in 0 }
        vic.readColorRAM = { _ in 0 }
        vic.recordsBusAccessTraces = false
        return vic
    }

    private func finishOpenLine(_ vic: VIC, write: (cycle: Int, register: UInt16, value: UInt8)? = nil) {
        let line = vic.rasterLine
        while vic.rasterLine == line {
            // Miss both right-border CSEL comparisons without changing XSCROLL.
            if vic.rasterCycle == 55 { vic.controlReg2 |= 8 }
            if vic.rasterCycle == 56 { vic.controlReg2 &= ~8 }
            vic.beginCycle()
            if let write, vic.rasterCycle == write.cycle {
                vic.writeRegister(write.register, value: write.value)
            }
            vic.endCycle()
        }
        vic.controlReg2 |= 8
    }

    private func pixel(_ vic: VIC, line: Int, x: Int) -> UInt32 {
        vic.framebuffer[(line - VIC.firstVisibleLine) * VIC.screenWidth + x]
    }

    func testBitmapBackgroundSurvivesRightBorderAndNextLinesLeftBorder() {
        for standard in standards {
            let vic = machine(standard)
            finishOpenLine(vic)
            XCTAssertEqual(vic.graphicsOutputMatrix, 0xA7)
            for x in 344..<borderCropWidth {
                XCTAssertEqual(pixel(vic, line: 100, x: x), ColorPalette.rgba[7])
            }
            vic.lineBuffer[0] = 0x23
            finishOpenLine(vic)
            for x in 0..<24 { XCTAssertEqual(pixel(vic, line: 101, x: x), ColorPalette.rgba[7]) }
            for x in 24..<32 { XCTAssertEqual(pixel(vic, line: 101, x: x), ColorPalette.rgba[3]) }
        }
    }

    func testIdleMatrixZeroReachesOutputOnlyAtScrolledFirstCell() {
        for standard in standards {
            for scroll in 0...7 {
                let vic = machine(standard)
                finishOpenLine(vic)
                vic.displayActive = false
                vic.controlReg2 = 8 | UInt8(scroll)
                finishOpenLine(vic)
                for x in 0..<24 + scroll {
                    XCTAssertEqual(pixel(vic, line: 101, x: x), ColorPalette.rgba[7], "\(standard) scroll \(scroll) x \(x)")
                }
                for x in 24 + scroll..<borderCropWidth {
                    XCTAssertEqual(pixel(vic, line: 101, x: x), ColorPalette.rgba[0])
                }
                XCTAssertEqual(vic.graphicsOutputMatrix, 0)
            }
        }
    }

    func testVerticalBorderStopsColorLoadsWithoutStoppingMemoryFetches() {
        for standard in standards {
            let vic = machine(standard)
            finishOpenLine(vic)
            vic.displayActive = false
            vic.verticalBorderClosePending = true
            var reads = 0
            vic.readMemory = { _ in reads += 1; return 0 }
            finishOpenLine(vic)
            XCTAssertGreaterThanOrEqual(reads, 40)
            XCTAssertEqual(vic.graphicsOutputMatrix, 0xA7)
            for x in 0..<borderCropWidth {
                XCTAssertEqual(pixel(vic, line: 101, x: x), ColorPalette.rgba[7])
            }
        }
    }

    func testOutputLatchesFetchedMatrixNotCurrentBufferAndRenderingDoesNotClockIt() {
        for standard in standards {
            let vic = machine(standard)
            finishOpenLine(vic)
            vic.controlReg2 = 15
            vic.lineBuffer[0] = 0x24
            while vic.rasterCycle < 16 { vic.tick() }
            XCTAssertEqual(vic.graphicsBufferScreenBytes[0], 0x24)
            XCTAssertEqual(vic.graphicsOutputMatrix, 0xA7)
            vic.lineBuffer[0] = 0x56
            vic.renderRasterline()
            let frame = vic.framebuffer
            vic.renderRasterline()
            XCTAssertEqual(vic.framebuffer, frame)
            XCTAssertEqual(vic.graphicsOutputMatrix, 0xA7)
            vic.tick()
            XCTAssertEqual(vic.graphicsOutputMatrix, 0x24)
        }
    }

    func testHeldColorSelectionRespectsAllEightGraphicsModes() {
        for standard in standards {
            for mode in 0..<8 {
                let vic = machine(standard)
                finishOpenLine(vic)
                vic.verticalBorderClosePending = true
                vic.controlReg1 = 0x1B | UInt8((mode & 6) << 4)
                vic.controlReg2 = 8 | UInt8((mode & 1) << 4)
                finishOpenLine(vic)
                let expected = mode == 2 ? 7 : mode == 4 ? 4 : mode >= 5 ? 0 : 6
                for x in 0..<borderCropWidth {
                    XCTAssertEqual(pixel(vic, line: 101, x: x), ColorPalette.rgba[expected], "\(standard) mode \(mode) x \(x)")
                }
            }
        }
    }

    func testBackgroundRegisterWritesDoNotRecolorHeldBitmapMatrix() {
        for standard in standards {
            for bitmap in [false, true] {
                let vic = machine(standard)
                finishOpenLine(vic)
                vic.verticalBorderClosePending = true
                if !bitmap { vic.controlReg1 = 0x1B }
                finishOpenLine(vic, write: (27, 0x21, 5))
                for x in 0..<borderCropWidth {
                    let expected = bitmap ? 7 : x < 113 ? 6 : 5
                    XCTAssertEqual(pixel(vic, line: 101, x: x), ColorPalette.rgba[expected])
                }
                XCTAssertEqual(vic.graphicsOutputMatrix, 0xA7)
            }
        }
    }

    func testColorLatchClocksOutsideFramebufferAndSurvivesFrameWrapUntilReset() {
        for standard in standards {
            let vic = machine(standard)
            vic.rasterLine = UInt16(VIC.firstVisibleLine - 1)
            finishOpenLine(vic)
            XCTAssertEqual(vic.graphicsOutputMatrix, 0xA7)
            vic.rasterLine = UInt16(vic.rasterLinesPerFrame - 1)
            vic.lineBuffer[39] = 0xB9
            finishOpenLine(vic)
            XCTAssertEqual(vic.rasterLine, 0)
            XCTAssertEqual(vic.graphicsOutputMatrix, 0xB9)
            vic.reset()
            XCTAssertEqual(vic.graphicsOutputMatrix, 0)
        }
    }

    func testCPUScrollWriteAfterFetchDelaysThatBytesOutputAndColorLatch() {
        for standard in standards {
            let vic = machine(standard)
            vic.lineBuffer = [UInt8](repeating: 0x01, count: 40)
            vic.lineBuffer[10] = 0x02
            vic.readMemory = { _ in 0x88 }
            finishOpenLine(vic, write: (25, 0x16, 15))
            for x in 104..<111 {
                XCTAssertEqual(pixel(vic, line: 100, x: x), ColorPalette.rgba[1])
            }
            XCTAssertEqual(pixel(vic, line: 100, x: 111), ColorPalette.rgba[0])
            for x in 112..<115 {
                XCTAssertEqual(pixel(vic, line: 100, x: x), ColorPalette.rgba[2])
            }
            XCTAssertEqual(pixel(vic, line: 100, x: 115), ColorPalette.rgba[0])
            for x in 116..<119 {
                XCTAssertEqual(pixel(vic, line: 100, x: x), ColorPalette.rgba[2])
            }
            XCTAssertEqual(vic.graphicsBufferControlReg2[9] & 7, 0)
            XCTAssertEqual(vic.graphicsBufferControlReg2[10] & 7, 7)
        }
    }
}
