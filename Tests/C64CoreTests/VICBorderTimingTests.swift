import XCTest
@testable import C64Core

final class VICBorderTimingTests: XCTestCase {
    func testFourCycleCPURSELPulsesSelectTheCorrectClosingLine() {
        // Boundary cases exercised by the public vborder2 programs. Cycles
        // here are zero-based and refer to the actual STA bus-write phase.
        let cases = [(246, 58, 251), (246, 59, 247), (247, 15, 247),
                     (247, 16, 248), (247, 61, 248), (247, 62, 251)]
        for (startLine, writeCycle, closingLine) in cases {
            let c64 = C64()
            c64.trueDriveEmulationMode = .off
            c64.kernalTraps.enabled = false
            let vic = c64.vic
            vic.rasterLine = UInt16(startLine)
            vic.controlReg1 = 0x1B
            vic.memoryPointers = 0x18
            vic.verticalBorderActive = false
            vic.verticalBorderClosePending = false
            vic.displayActive = true
            vic.rowCounter = startLine - 243
            vic.lineBuffer = [UInt8](repeating: 1, count: 40)
            vic.colorBuffer = [UInt8](repeating: 1, count: 40)
            vic.borderColor = 14
            vic.backgroundColor[0] = 6
            for address in 0x2008..<0x2010 { c64.memory.ram[address] = 0xFF }
            while vic.rasterCycle < writeCycle - 3 { vic.tick() }
            c64.cpu.pc = 0x0600
            c64.cpu.a = 0x13
            c64.cpu.x = 0x1B
            // STA $D011; STX $D011; JMP $0606. No ROM or forced VIC writes.
            for (offset, byte) in [UInt8(0x8D), 0x11, 0xD0, 0x8E, 0x11, 0xD0, 0x4C, 0x06, 0x06].enumerated() {
                c64.memory.ram[0x0600 + offset] = byte
            }
            while vic.rasterLine <= 251 { c64.tickOneCycle() }
            XCTAssertFalse(c64.cpu.jammed)
            for line in 247...251 {
                let pixel = vic.framebuffer[(line - VIC.firstVisibleLine) * VIC.screenWidth + 100]
                XCTAssertEqual(pixel, ColorPalette.rgba[line < closingLine ? 1 : 14],
                               "write=\(startLine):\(writeCycle), line=\(line)")
            }
        }
    }

    func testLateVerticalCloseIsLatchedWithoutBlankingTheCurrentLine() {
        for standard in [C64VideoStandard.pal, .ntsc] {
            let vic = VIC()
            vic.videoStandard = standard
            vic.rasterLine = 247
            vic.verticalBorderActive = false
            vic.verticalBorderClosePending = false
            while vic.rasterCycle < 20 { vic.tick() }
            vic.beginCycle()
            vic.writeRegister(0x11, value: 0x13)
            vic.endCycle()
            vic.tick()
            XCTAssertTrue(vic.verticalBorderClosePending)
            XCTAssertFalse(vic.verticalBorderActive)
            vic.writeRegister(0x11, value: 0x1B)
            while vic.rasterLine == 247 { vic.tick() }
            XCTAssertFalse(vic.verticalBorderActive)
            vic.tick()
            XCTAssertTrue(vic.verticalBorderActive)
        }
    }

    func testBorderLatchesSurviveFrameWrapUntilAnotherComparison() {
        for standard in [C64VideoStandard.pal, .ntsc] {
            for closed in [false, true] {
                let vic = VIC()
                vic.videoStandard = standard
                vic.rasterLine = UInt16(vic.rasterLinesPerFrame - 1)
                vic.verticalBorderActive = closed
                vic.verticalBorderClosePending = closed
                while vic.rasterLine != 0 { vic.tick() }
                XCTAssertEqual(vic.verticalBorderActive, closed)
                while vic.rasterLine < VIC.firstVisibleLine { vic.tick() }
                XCTAssertEqual(vic.verticalBorderActive, closed)
                XCTAssertEqual(vic.verticalBorderClosePending, closed)
                vic.reset()
                XCTAssertTrue(vic.verticalBorderActive)
                XCTAssertTrue(vic.verticalBorderClosePending)
            }
        }
    }

    func testExpandedFinalSpriteRowFinishesAfterDisplayEnableIsCleared() {
        for standard in [C64VideoStandard.pal, .ntsc] {
            let vic = VIC()
            vic.videoStandard = standard
            vic.rasterLine = 100
            vic.verticalBorderActive = false
            vic.verticalBorderClosePending = false
            vic.horizontalBorderActive = false
            vic.backgroundColor[0] = 6
            vic.spriteEnabled = 0xC0
            vic.spriteExpandX = 0xC0
            for sprite in 6...7 {
                vic.spriteY[sprite] = 100
                vic.spriteX[sprite] = 328
                vic.spriteColors[sprite] = 1
            }
            vic.readMemory = { address in
                if (0x07F8...0x07FF).contains(address) { return 0x20 }
                return (0x0800..<0x083F).contains(address) ? 0xA0 : 0
            }
            while vic.rasterLine <= 122 {
                if vic.rasterCycle == 0 { vic.writeRegister(0x16, value: 8) }
                if vic.rasterCycle == 56 { vic.writeRegister(0x16, value: 0) }
                if vic.rasterLine == 121 && vic.rasterCycle == 57 {
                    _ = vic.readRegister(0x1E)
                }
                vic.tick()
            }
            let lastRow = (121 - VIC.firstVisibleLine) * VIC.screenWidth
            let following = lastRow + VIC.screenWidth
            for x in 328..<376 {
                let white = [0, 1, 4, 5].contains((x - 328) % 16)
                XCTAssertEqual(vic.framebuffer[lastRow + x], ColorPalette.rgba[white ? 1 : 6], "\(standard) x=\(x)")
                XCTAssertEqual(vic.framebuffer[following + x], ColorPalette.rgba[6])
            }
            XCTAssertEqual(vic.readRegister(0x1E), 0xC0, "The final byte still participates in collisions")
            XCTAssertFalse(vic.spriteDisplay[7])
            XCTAssertEqual(vic.spriteShifters[7].remainingBits, 0)
        }
    }

    func testInactiveSpriteCannotBeginShiftingAfterItsDisplayLatchCloses() {
        for standard in [C64VideoStandard.pal, .ntsc] {
            let vic = VIC()
            vic.videoStandard = standard
            vic.rasterLine = 100
            vic.verticalBorderActive = false
            vic.verticalBorderClosePending = false
            vic.horizontalBorderActive = false
            vic.backgroundColor[0] = 6
            vic.spriteDisplay[7] = true
            // After both PAL's and NTSC's display-latch sample, before the
            // NTSC X-counter discontinuity outside the normal display.
            vic.spriteX[7] = 368
            vic.spriteColors[7] = 1
            vic.seedSpriteRow(7, bytes: [0xFF, 0xFF, 0xFF])
            while vic.rasterLine == 100 {
                if vic.rasterCycle == 56 { vic.writeRegister(0x16, value: 0) }
                vic.tick()
            }
            for x in 368..<392 {
                XCTAssertEqual(vic.framebuffer[(100 - VIC.firstVisibleLine) * VIC.screenWidth + x], ColorPalette.rgba[6], "\(standard) x=\(x)")
            }
            XCTAssertEqual(vic.spriteShifters[7].remainingBits, 0)
        }
    }
}
