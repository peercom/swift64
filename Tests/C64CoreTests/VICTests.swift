import XCTest
@testable import C64Core

final class VICTests: XCTestCase {
    func testDebugRegisterValueReportsEffectiveVICStateWithoutReadSideEffects() {
        let vic = VIC()
        vic.writeRegister(0x00, value: 0x34)
        vic.writeRegister(0x01, value: 0x56)
        vic.writeRegister(0x10, value: 0x01)
        vic.writeRegister(0x11, value: 0x3B)
        vic.writeRegister(0x16, value: 0x18)
        vic.writeRegister(0x18, value: 0x14)
        vic.writeRegister(0x20, value: 0x06)
        vic.writeRegister(0x21, value: 0x0E)
        vic.spriteSpriteCollision = 0x03
        vic.spriteDataCollision = 0x01

        XCTAssertEqual(vic.debugRegisterValue(0xD000), 0x34)
        XCTAssertEqual(vic.debugRegisterValue(0xD001), 0x56)
        XCTAssertEqual(vic.debugRegisterValue(0xD010), 0x01)
        XCTAssertEqual(vic.debugRegisterValue(0xD011), 0x3B)
        XCTAssertEqual(vic.debugRegisterValue(0xD016), 0xF8)
        XCTAssertEqual(vic.debugRegisterValue(0xD018), 0x15)
        XCTAssertEqual(vic.debugRegisterValue(0xD020), 0xF6)
        XCTAssertEqual(vic.debugRegisterValue(0xD021), 0xFE)
        XCTAssertEqual(vic.debugRegisterValue(0xD01E), 0x03)
        XCTAssertEqual(vic.debugRegisterValue(0xD01F), 0x01)
        XCTAssertEqual(vic.spriteSpriteCollision, 0x03)
        XCTAssertEqual(vic.spriteDataCollision, 0x01)
    }

    func testRegisterReadWriteMirrorsUseLowSixAddressBits() {
        let vic = VIC()

        vic.writeRegister(0xD020, value: 0x05)
        vic.writeRegister(0xD021 + 0x40, value: 0x06)
        vic.writeRegister(0xD027 + 0x80, value: 0x07)
        vic.writeRegister(0xD000 + 0xC0, value: 0x34)
        vic.writeRegister(0xD010 + 0x40, value: 0x01)

        XCTAssertEqual(vic.borderColor, 0x05)
        XCTAssertEqual(vic.backgroundColor[0], 0x06)
        XCTAssertEqual(vic.spriteColors[0], 0x07)
        XCTAssertEqual(vic.readRegister(0xD020), 0xF5)
        XCTAssertEqual(vic.readRegister(0xD021 + 0x40), 0xF6)
        XCTAssertEqual(vic.readRegister(0xD027 + 0x80), 0xF7)
        XCTAssertEqual(vic.readRegister(0xD000), 0x34)
        XCTAssertEqual(vic.readRegister(0xD010 + 0x40), 0x01)
    }

    func testMirroredCollisionReadsKeepReadClearSideEffects() {
        let vic = VIC()
        vic.spriteSpriteCollision = 0x03
        vic.spriteDataCollision = 0x01

        XCTAssertEqual(vic.readRegister(0xD01E + 0x40), 0x03)
        XCTAssertEqual(vic.debugRegisterValue(0xD01E), 0x00)
        XCTAssertEqual(vic.readRegister(0xD01F + 0x80), 0x01)
        XCTAssertEqual(vic.debugRegisterValue(0xD01F), 0x00)
    }

    func testMirroredInterruptRegistersKeepRaiseAndAcknowledgeSideEffects() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        vic.rasterLine = 0x0034

        vic.writeRegister(0xD01A + 0x40, value: 0x01)
        vic.writeRegister(0xD012 + 0x80, value: 0x34)

        XCTAssertEqual(vic.readRegister(0xD019 + 0x40), 0xF1)
        XCTAssertEqual(irqStates, [true])

        vic.writeRegister(0xD019 + 0xC0, value: 0x01)

        XCTAssertEqual(vic.readRegister(0xD019), 0x70)
        XCTAssertEqual(irqStates, [true, false])
    }

    func testResetClearsRegistersRasterStateAndDeassertsIRQ() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        vic.rasterLine = 0x0134
        vic.rasterCycle = 12
        vic.writeRegister(0x1A, value: 0x09)
        vic.writeRegister(0x12, value: 0x34)
        vic.writeRegister(0x11, value: 0x9B)
        vic.writeRegister(0x15, value: 0xFF)
        vic.writeRegister(0x20, value: 0x02)
        vic.triggerLightPen(x: 200, y: 100)

        XCTAssertTrue(vic.readRegister(0x19) & 0x80 != 0)

        vic.reset()

        XCTAssertEqual(vic.rasterLine, 0)
        XCTAssertEqual(vic.rasterCycle, 0)
        XCTAssertEqual(vic.readRegister(0x11), 0x1B)
        XCTAssertEqual(vic.readRegister(0x12), 0)
        XCTAssertEqual(vic.readRegister(0x15), 0)
        XCTAssertEqual(vic.readRegister(0x19), 0x70)
        XCTAssertEqual(vic.readRegister(0x1A), 0xF0)
        XCTAssertEqual(vic.readRegister(0x20), 0xFE)
        XCTAssertFalse(vic.frameReady)
        XCTAssertEqual(irqStates.last, false)
    }

    func testEndOfLineRendersLastVisibleRasterline() {
        let vic = VIC()
        let borderColor = ColorPalette.rgba[2]
        let fbY = VIC.lastVisibleLine - VIC.firstVisibleLine

        vic.rasterLine = UInt16(VIC.lastVisibleLine)
        vic.borderColor = 0x02

        vic.endOfLine()

        XCTAssertEqual(vic.framebuffer[fbY * VIC.screenWidth], borderColor)
    }

    func testRenderRasterlineKeepsNominalDisplayBorderedWhenDisplayIsInactive() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)
        let fbY = VIC.displayTop - VIC.firstVisibleLine

        vic.rasterLine = line
        vic.displayActive = false
        vic.controlReg1 = 0x1B
        vic.borderColor = 0x02
        vic.backgroundColor[0] = 0x01
        vic.readMemory = { _ in 0x00 }
        vic.readColorRAM = { _ in 0x07 }

        vic.renderRasterline()

        XCTAssertEqual(vic.framebuffer[fbY * VIC.screenWidth + VIC.displayLeft + 20], ColorPalette.rgba[2])
    }

    func testRenderRasterlineKeepsNominalDisplayBorderedWhenDisplayIsDisabled() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)
        let fbY = VIC.displayTop - VIC.firstVisibleLine

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg1 = 0x0B
        vic.borderColor = 0x02
        vic.backgroundColor[0] = 0x01
        vic.readMemory = { _ in 0x00 }
        vic.readColorRAM = { _ in 0x07 }

        vic.renderRasterline()

        XCTAssertEqual(vic.framebuffer[fbY * VIC.screenWidth + VIC.displayLeft + 20], ColorPalette.rgba[2])
    }

    func testRenderRasterlineDoesNotAdvanceDisplayRowWhenDisplayIsInactive() {
        let vic = VIC()

        vic.rasterLine = UInt16(VIC.displayTop)
        vic.displayActive = false
        vic.controlReg1 = 0x1B
        vic.rowCounter = 3
        vic.videoCounterBase = 80

        vic.renderRasterline()

        XCTAssertEqual(vic.rowCounter, 3)
        XCTAssertEqual(vic.videoCounterBase, 80)
    }

    func testRenderRasterlineDoesNotAdvanceDisplayRowWhenDisplayIsDisabled() {
        let vic = VIC()

        vic.rasterLine = UInt16(VIC.displayTop)
        vic.displayActive = true
        vic.controlReg1 = 0x0B
        vic.rowCounter = 3
        vic.videoCounterBase = 80

        vic.renderRasterline()

        XCTAssertEqual(vic.rowCounter, 3)
        XCTAssertEqual(vic.videoCounterBase, 80)
    }

    func testRenderRasterlineAdvancesDisplayRowWhenBeamTraceOpenedDisplay() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg1 = 0x1B
        vic.rowCounter = 3
        vic.displayLineBufferBase = 0
        vic.badLineFetchMask = 0x01
        vic.rasterTraceLine = line
        vic.rasterTraceHasSamples = true
        vic.rasterTraceHasDisplayOpen = true
        vic.rasterTraceValid[VIC.displayLeft] = true
        vic.rasterTraceDisplayOpen[VIC.displayLeft] = true
        vic.readMemory = { _ in 0x00 }
        vic.readColorRAM = { _ in 0x07 }

        vic.renderRasterline()

        XCTAssertEqual(vic.rowCounter, 4)
    }

    func testMidlineBorderColorWriteIsLatchedAtRasterPosition() {
        let vic = VIC()
        let line = UInt16(VIC.firstVisibleLine)
        let splitCycle = 31

        vic.rasterLine = line
        vic.borderColor = 0x02

        while vic.rasterCycle < splitCycle {
            vic.tick()
        }
        vic.writeRegister(0x20, value: 0x05)
        while vic.rasterLine == line {
            vic.tick()
        }

        let splitPixel = splitCycle * VIC.screenWidth / VIC.palCyclesPerLine
        XCTAssertEqual(vic.framebuffer[splitPixel - 1], ColorPalette.rgba[2])
        XCTAssertEqual(vic.framebuffer[splitPixel + 1], ColorPalette.rgba[5])
    }

    func testMidlineBackgroundColorWriteIsLatchedInsideDisplayArea() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.backgroundColor[0] = 0x01
        vic.readMemory = { _ in 0x00 }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 30 {
            vic.tick()
        }
        vic.writeRegister(0x21, value: 0x06)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 20], ColorPalette.rgba[1])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayRight - 20], ColorPalette.rgba[6])
    }

    func testMidlineBackgroundColorWriteDoesNotOverrideBitmapScreenBackground() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg1 = 0x3B
        vic.backgroundColor[0] = 0x01
        vic.readMemory = { address in
            switch address {
            case 0x0400...0x0427: return 0x37
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x0E }

        while vic.rasterCycle < 30 {
            vic.tick()
        }
        vic.writeRegister(0x21, value: 0x06)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 20], ColorPalette.rgba[7])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayRight - 20], ColorPalette.rgba[7])
    }

    func testMidlineBackgroundColorWriteStillAppliesToMulticolorBitmapBackgroundZero() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg1 = 0x3B
        vic.controlReg2 = 0xD8
        vic.backgroundColor[0] = 0x01
        vic.readMemory = { address in
            switch address {
            case 0x0400...0x0427: return 0x37
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x0E }

        while vic.rasterCycle < 30 {
            vic.tick()
        }
        vic.writeRegister(0x21, value: 0x06)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 20], ColorPalette.rgba[1])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayRight - 20], ColorPalette.rgba[6])
    }

    func testMidlineBackgroundColorWriteDoesNotOverrideECMAlternateBackground() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg1 = 0x5B
        vic.backgroundColor[0] = 0x01
        vic.backgroundColor[1] = 0x02
        vic.readMemory = { address in
            switch address {
            case 0x0400...0x0427: return 0x40
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 30 {
            vic.tick()
        }
        vic.writeRegister(0x21, value: 0x06)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 20], ColorPalette.rgba[2])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayRight - 20], ColorPalette.rgba[2])
    }

    func testMidlineBackgroundColorOneWriteIsLatchedForMulticolorText() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg2 = 0xD8
        vic.backgroundColor[1] = 0x02
        vic.readMemory = { address in
            switch address {
            case 0x0400...0x0427: return 0x01
            default: return 0b01010101
            }
        }
        vic.readColorRAM = { _ in 0x08 }

        while vic.rasterCycle < 30 {
            vic.tick()
        }
        vic.writeRegister(0x22, value: 0x05)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 20], ColorPalette.rgba[2])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayRight - 20], ColorPalette.rgba[5])
    }

    func testMidlineBackgroundColorTwoWriteIsLatchedForMulticolorText() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg2 = 0xD8
        vic.backgroundColor[2] = 0x03
        vic.readMemory = { address in
            switch address {
            case 0x0400...0x0427: return 0x01
            default: return 0b10101010
            }
        }
        vic.readColorRAM = { _ in 0x08 }

        while vic.rasterCycle < 30 {
            vic.tick()
        }
        vic.writeRegister(0x23, value: 0x06)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 20], ColorPalette.rgba[3])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayRight - 20], ColorPalette.rgba[6])
    }

    func testMidlineBackgroundColorThreeWriteIsLatchedForECMBackground() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg1 = 0x5B
        vic.backgroundColor[3] = 0x04
        vic.readMemory = { address in
            switch address {
            case 0x0400...0x0427: return 0xC0
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 30 {
            vic.tick()
        }
        vic.writeRegister(0x24, value: 0x07)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 20], ColorPalette.rgba[4])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayRight - 20], ColorPalette.rgba[7])
    }

    func testMidlineBackgroundColorWriteDoesNotOverrideInvalidECMMulticolorBlack() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg1 = 0x5B
        vic.controlReg2 = 0xD8
        vic.backgroundColor[0] = 0x01
        vic.readMemory = { address in
            switch address {
            case 0x0400...0x0427: return 0x01
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x0F }

        while vic.rasterCycle < 30 {
            vic.tick()
        }
        vic.writeRegister(0x21, value: 0x06)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 20], ColorPalette.rgba[0])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayRight - 20], ColorPalette.rgba[0])
    }

    func testMidlineBackgroundColorWriteDoesNotOverrideInvalidECMBitmapBlack() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg1 = 0x7B
        vic.controlReg2 = 0xC8
        vic.backgroundColor[0] = 0x01
        vic.readMemory = { address in
            switch address {
            case 0x0400...0x0427: return 0x37
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x0E }

        while vic.rasterCycle < 30 {
            vic.tick()
        }
        vic.writeRegister(0x21, value: 0x06)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 20], ColorPalette.rgba[0])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayRight - 20], ColorPalette.rgba[0])
    }

    func testMidlineColumnModeWriteKeepsAlreadyScannedLeftEdgeOpen() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg2 = 0xC8
        vic.borderColor = 0x02
        vic.readMemory = { address in
            switch address {
            case 0x0400: return 0x01
            case 0x1008: return 0xFF
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 8 {
            vic.tick()
        }
        vic.writeRegister(0x16, value: 0xC0)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 4], ColorPalette.rgba[7])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 7], ColorPalette.rgba[7])
    }

    func testMidlineDisplayDisableKeepsAlreadyScannedGraphicsVisible() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.borderColor = 0x02
        vic.readMemory = { address in
            switch address {
            case 0x0400: return 0x01
            case 0x1008: return 0xFF
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 8 {
            vic.tick()
        }
        vic.writeRegister(0x11, value: 0x0B)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 4], ColorPalette.rgba[7])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayRight - 20], ColorPalette.rgba[2])
    }

    func testMidlineDisplayEnableOpensOnlyLaterGraphicsPixels() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg1 = 0x0B
        vic.borderColor = 0x02
        vic.readMemory = { address in
            switch address {
            case 0x0400...0x0427: return 0x01
            case 0x1008: return 0xFF
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 30 {
            vic.tick()
        }
        vic.writeRegister(0x11, value: 0x1B)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 20], ColorPalette.rgba[2])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayRight - 20], ColorPalette.rgba[7])
    }

    func testMidlineTwentyFourRowModeWriteKeepsAlreadyScannedTopLineVisible() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.borderColor = 0x02
        vic.backgroundColor[0] = 0x01
        vic.controlReg1 = 0x1B
        vic.readMemory = { address in
            switch address {
            case 0x0400: return 0x01
            case 0x1008: return 0xFF
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 8 {
            vic.tick()
        }
        vic.writeRegister(0x11, value: 0x13)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 4], ColorPalette.rgba[7])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayRight - 20], ColorPalette.rgba[1])
    }

    func testTopBorderStaysClosedWhenRowModeWriteMissesOpenComparison() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg1 = 0x13
        vic.borderColor = 0x02
        vic.backgroundColor[0] = 0x01
        vic.readMemory = { _ in 0x00 }
        vic.readColorRAM = { _ in 0x07 }

        vic.tick()
        vic.writeRegister(0x11, value: 0x1B)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 20], ColorPalette.rgba[2])
    }

    func testRightBorderStaysOpenWhenColumnModeMissesCloseComparison() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg2 = 0xC8
        vic.backgroundColor[0] = 0x01
        vic.borderColor = 0x02
        vic.readMemory = { _ in 0x00 }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 53 {
            vic.tick()
        }
        vic.writeRegister(0x16, value: 0xC0)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayRight + 16], ColorPalette.rgba[1])
    }

    func testLeftBorderStaysClosedWhenColumnModeWriteMissesOpenComparison() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg2 = 0xC0
        vic.backgroundColor[0] = 0x01
        vic.borderColor = 0x02
        vic.readMemory = { _ in 0x00 }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 4 {
            vic.tick()
        }
        vic.writeRegister(0x16, value: 0xC8)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 20], ColorPalette.rgba[2])
    }

    func testBottomBorderClosesDisplayWhenComparisonIsNotSkipped() {
        let vic = VIC()
        let line = UInt16(VIC.displayBottom)

        vic.rasterLine = line
        vic.displayActive = true
        vic.verticalBorderActive = false
        vic.backgroundColor[0] = 0x01
        vic.borderColor = 0x02
        vic.readMemory = { _ in 0x00 }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayBottom - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 20], ColorPalette.rgba[2])
    }

    func testBottomBorderStaysOpenWhenRowModeMissesCloseComparison() {
        let vic = VIC()
        let startLine = UInt16(VIC.displayBottom - 4)
        let openedLine = UInt16(VIC.displayBottom + 1)

        vic.rasterLine = startLine
        vic.displayActive = true
        vic.verticalBorderActive = false
        vic.controlReg1 = 0x1B
        vic.backgroundColor[0] = 0x01
        vic.borderColor = 0x02
        vic.readMemory = { address in
            switch address {
            case 0x07E8: return 0x01
            case 0x1009: return 0x00
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterLine < UInt16(VIC.displayBottom - 1) {
            vic.tick()
        }
        vic.writeRegister(0x11, value: 0x13)
        while vic.rasterLine <= openedLine {
            vic.tick()
        }

        let fbY = Int(openedLine) - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 20], ColorPalette.rgba[1])
    }

    func testOpenBottomBorderContinuesLowPhaseDisplayFetches() {
        let vic = VIC()
        var reads: [UInt16] = []

        vic.rasterLine = UInt16(VIC.displayBottom + 1)
        vic.rasterCycle = 15
        vic.displayActive = true
        vic.verticalBorderActive = false
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x07E8: return 0x01
            case 0x1009: return 0x80
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        vic.performLowPhaseAccess()

        XCTAssertEqual(vic.graphicsBuffer[0], 0x80)
        XCTAssertEqual(vic.graphicsBufferBase, 1000)
        XCTAssertEqual(vic.graphicsBufferPixelRow, 1)
        XCTAssertTrue(reads.contains(0x07E8))
        XCTAssertTrue(reads.contains(0x1009))
    }

    func testLowPhaseGraphicsModeLatchesPerColumnDuringRasterSplit() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg2 = 0xC8
        vic.backgroundColor[0] = 0x00
        vic.backgroundColor[1] = 0x02
        vic.backgroundColor[2] = 0x03
        vic.readMemory = { address in
            switch address {
            case 0x0400...0x0427: return 0x01
            case 0x1008: return 0x40
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x0F }

        while vic.rasterCycle < 16 {
            vic.tick()
        }
        vic.writeRegister(0x16, value: 0xD8)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth
        let firstColumnX = VIC.displayLeft + 1
        let laterColumnX = VIC.displayLeft + 2 * 8

        XCTAssertEqual(vic.framebuffer[rowOffset + firstColumnX], ColorPalette.rgba[0x0F])
        XCTAssertEqual(vic.framebuffer[rowOffset + laterColumnX], ColorPalette.rgba[0x02])
    }

    func testLowPhaseHorizontalScrollLatchesPerColumnDuringRasterSplit() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg2 = 0xC8
        vic.readMemory = { address in
            switch address {
            case 0x0400...0x0427: return 0x01
            case 0x1008: return 0x80
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 16 {
            vic.tick()
        }
        vic.writeRegister(0x16, value: 0xCC)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth

        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft], ColorPalette.rgba[7])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 4], ColorPalette.rgba[0])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 2 * 8 + 4], ColorPalette.rgba[7])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 2 * 8], ColorPalette.rgba[0])
    }

    func testLowPhaseMemoryPointerLatchesCharacterBasePerColumnDuringRasterSplit() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)
        var reads: [UInt16] = []

        vic.rasterLine = line
        vic.displayActive = true
        vic.writeRegister(0x18, value: 0x14)
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x0400...0x0427: return 0x01
            case 0x1008: return 0x80
            case 0x1808: return 0x40
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 16 {
            vic.tick()
        }
        vic.writeRegister(0x18, value: 0x16)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth

        XCTAssertTrue(reads.contains(0x1008))
        XCTAssertTrue(reads.contains(0x1808))
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft], ColorPalette.rgba[7])
        XCTAssertEqual(vic.framebuffer[rowOffset + 2 * 8 + VIC.displayLeft + 1], ColorPalette.rgba[7])
        XCTAssertEqual(vic.framebuffer[rowOffset + 2 * 8 + VIC.displayLeft], ColorPalette.rgba[0])
    }

    func testLowPhaseControlReg1LatchesBitmapModePerColumnDuringRasterSplit() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg1 = 0x1B
        vic.backgroundColor[0] = 0x00
        vic.readMemory = { address in
            switch address {
            case 0x0400...0x0427: return 0x01
            case 0x1008: return 0x80
            case 0x0010: return 0x40
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 16 {
            vic.tick()
        }
        vic.writeRegister(0x11, value: 0x3B)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth

        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft], ColorPalette.rgba[7])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 2 * 8], ColorPalette.rgba[1])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 2 * 8 + 1], ColorPalette.rgba[0])
    }

    func testLowPhaseControlReg1LatchesExtendedBackgroundModePerColumnDuringRasterSplit() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)
        var reads: [UInt16] = []

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg1 = 0x1B
        vic.backgroundColor[1] = 0x02
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x0400...0x0427: return 0x41
            case 0x1208: return 0x80
            case 0x1008: return 0x40
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 16 {
            vic.tick()
        }
        vic.writeRegister(0x11, value: 0x5B)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth

        XCTAssertTrue(reads.contains(0x1208))
        XCTAssertTrue(reads.contains(0x1008))
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft], ColorPalette.rgba[7])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 2 * 8], ColorPalette.rgba[2])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 2 * 8 + 1], ColorPalette.rgba[7])
    }

    func testLowPhaseMemoryPointerLatchesBitmapBasePerColumnDuringRasterSplit() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)
        var reads: [UInt16] = []

        vic.rasterLine = line
        vic.displayActive = true
        vic.controlReg1 = 0x3B
        vic.writeRegister(0x18, value: 0x10)
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x0400...0x0427: return 0x71
            case 0x0000: return 0x80
            case 0x2010: return 0x40
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 16 {
            vic.tick()
        }
        vic.writeRegister(0x18, value: 0x18)
        while vic.rasterLine == line {
            vic.tick()
        }

        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let rowOffset = fbY * VIC.screenWidth

        XCTAssertTrue(reads.contains(0x0000))
        XCTAssertTrue(reads.contains(0x2010))
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft], ColorPalette.rgba[7])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 2 * 8], ColorPalette.rgba[1])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 2 * 8 + 1], ColorPalette.rgba[7])
    }

    func testLowPhaseDisplayDataUsesCurrentScreenBaseForUnlatchedMatrixColumn() {
        let vic = VIC()
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rasterCycle = 15
        vic.displayActive = true
        vic.memoryPointers = 0x24
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x0800: return 0x03
            case 0x1018: return 0x80
            default: return 0
            }
        }

        vic.performLowPhaseAccess()

        XCTAssertEqual(vic.graphicsBuffer[0], 0x80)
        XCTAssertEqual(vic.graphicsBufferMemoryPointers[0], 0x24)
        XCTAssertEqual(reads, [0x0800, 0x1018])
        XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x0800, 0x1018])
    }

    func testPALTimingUsesSixtyThreeCyclesAndThreeHundredTwelveLines() {
        let vic = VIC()

        XCTAssertEqual(vic.videoStandard, .pal)
        XCTAssertEqual(vic.rasterCyclesPerLine, 63)
        XCTAssertEqual(vic.rasterLinesPerFrame, 312)
        XCTAssertEqual(vic.activeCyclesPerFrame, 19_656)

        vic.rasterLine = 311
        vic.rasterCycle = 62
        vic.tick()

        XCTAssertEqual(vic.rasterLine, 0)
        XCTAssertEqual(vic.rasterCycle, 0)
        XCTAssertTrue(vic.frameReady)
    }

    func testNTSCTimingUsesSixtyFiveCyclesAndTwoHundredSixtyThreeLines() {
        let vic = VIC()
        vic.videoStandard = .ntsc

        XCTAssertEqual(vic.rasterCyclesPerLine, 65)
        XCTAssertEqual(vic.rasterLinesPerFrame, 263)
        XCTAssertEqual(vic.activeCyclesPerFrame, 17_095)

        vic.rasterLine = 262
        vic.rasterCycle = 64
        vic.tick()

        XCTAssertEqual(vic.rasterLine, 0)
        XCTAssertEqual(vic.rasterCycle, 0)
        XCTAssertTrue(vic.frameReady)
    }

    func testSpritesRenderOverVisibleBorderArea() {
        let vic = VIC()
        let spriteColor = ColorPalette.rgba[1]
        let borderColor = ColorPalette.rgba[2]

        vic.rasterLine = UInt16(VIC.firstVisibleLine)
        vic.borderColor = 0x02
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = 10
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]

        vic.renderRasterline()

        XCTAssertEqual(vic.framebuffer[10], spriteColor)
        XCTAssertEqual(vic.framebuffer[9], borderColor)
    }

    func testTwentyFourRowModeHidesTopGraphicsWithoutShiftingCharacterRow() {
        let vic = VIC()
        let fgColor = ColorPalette.rgba[7]
        let fbY = VIC.displayTop + 4 - VIC.firstVisibleLine
        var readAddresses: [UInt16] = []

        vic.rasterLine = UInt16(VIC.displayTop + 4)
        vic.displayActive = true
        vic.controlReg1 = 0x13
        vic.readMemory = { address in
            readAddresses.append(address)
            switch address {
            case 0x0400: return 0x01
            case 0x100C: return 0x80
            default: return 0
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        vic.renderRasterline()

        XCTAssertTrue(readAddresses.contains(0x100C))
        XCTAssertFalse(readAddresses.contains(0x1008))
        XCTAssertEqual(vic.framebuffer[fbY * VIC.screenWidth + VIC.displayLeft], fgColor)
    }

    func testThirtyEightColumnModeHidesLeftPixelsWithoutShiftingGraphics() {
        let vic = VIC()
        let borderColor = ColorPalette.rgba[2]
        let fgColor = ColorPalette.rgba[7]
        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let firstVisible38ColumnPixel = VIC.displayLeft + 7

        vic.rasterLine = UInt16(VIC.displayTop)
        vic.displayActive = true
        vic.borderColor = 0x02
        vic.controlReg2 = 0xC0
        vic.readMemory = { address in
            switch address {
            case 0x0400: return 0x01
            case 0x1008: return 0x01
            default: return 0
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        vic.renderRasterline()

        XCTAssertEqual(vic.framebuffer[fbY * VIC.screenWidth + firstVisible38ColumnPixel - 1], borderColor)
        XCTAssertEqual(vic.framebuffer[fbY * VIC.screenWidth + firstVisible38ColumnPixel], fgColor)
    }

    func testPrioritySpriteInBorderIgnoresHiddenDisplayForegroundMask() {
        let vic = VIC()
        let spriteColor = ColorPalette.rgba[1]
        let borderColor = ColorPalette.rgba[2]
        let fbY = VIC.displayTop - VIC.firstVisibleLine
        let borderX = VIC.displayRight

        vic.rasterLine = UInt16(VIC.displayTop)
        vic.displayActive = true
        vic.borderColor = 0x02
        vic.controlReg2 = 0xCF
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spritePriority = 0x01
        vic.spriteX[0] = UInt16(borderX)
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]
        vic.readMemory = { address in
            if address == 0x0427 { return 0x01 }
            if address == 0x1008 { return 0xFF }
            return 0
        }
        vic.readColorRAM = { _ in 0x07 }

        vic.renderRasterline()

        XCTAssertEqual(vic.framebuffer[fbY * VIC.screenWidth + borderX], spriteColor)
        XCTAssertEqual(vic.framebuffer[fbY * VIC.screenWidth + borderX + 1], borderColor)
        XCTAssertEqual(vic.readRegister(0x1F), 0x00)
    }

    func testExtendedBackgroundModeMasksCharacterCodeForGlyphFetch() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)
        var readAddresses: [UInt16] = []

        vic.controlReg1 = 0x5B
        vic.readMemory = { address in
            readAddresses.append(address)
            switch address {
            case 0x0400: return 0xC1
            case 0x1008: return 0x80
            default: return 0
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertTrue(readAddresses.contains(0x1008))
        XCTAssertFalse(readAddresses.contains(0x1608))
        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[7])
        XCTAssertTrue(foregroundMask[VIC.displayLeft])
    }

    func testStandardBitmapModeUsesScreenByteNibblesForPixelColors() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)

        vic.renderBitmapChar(
            line: &line,
            foregroundMask: &foregroundMask,
            xPos: VIC.displayLeft,
            pixelData: 0x80,
            screenByte: 0x37,
            colorByte: 0x0E
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[3])
        XCTAssertEqual(line[VIC.displayLeft + 1], ColorPalette.rgba[7])
        XCTAssertTrue(foregroundMask[VIC.displayLeft])
        XCTAssertFalse(foregroundMask[VIC.displayLeft + 1])
    }

    func testMulticolorBitmapModeUsesAllFourColorSources() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)

        vic.backgroundColor[0] = 0x01
        vic.controlReg2 = 0xD8
        vic.renderBitmapChar(
            line: &line,
            foregroundMask: &foregroundMask,
            xPos: VIC.displayLeft,
            pixelData: 0b00011011,
            screenByte: 0x23,
            colorByte: 0x04
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[1])
        XCTAssertEqual(line[VIC.displayLeft + 2], ColorPalette.rgba[2])
        XCTAssertEqual(line[VIC.displayLeft + 4], ColorPalette.rgba[3])
        XCTAssertEqual(line[VIC.displayLeft + 6], ColorPalette.rgba[4])
        XCTAssertFalse(foregroundMask[VIC.displayLeft])
        XCTAssertTrue(foregroundMask[VIC.displayLeft + 2])
        XCTAssertTrue(foregroundMask[VIC.displayLeft + 4])
        XCTAssertTrue(foregroundMask[VIC.displayLeft + 6])
    }

    func testMulticolorTextModeUsesBackgroundsAndColorRamLowBits() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)

        vic.backgroundColor[0] = 0x01
        vic.backgroundColor[1] = 0x02
        vic.backgroundColor[2] = 0x03
        vic.renderMulticolorChar(
            line: &line,
            foregroundMask: &foregroundMask,
            xPos: VIC.displayLeft,
            pixelData: 0b00011011,
            colorByte: 0x0C
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[1])
        XCTAssertEqual(line[VIC.displayLeft + 2], ColorPalette.rgba[2])
        XCTAssertEqual(line[VIC.displayLeft + 4], ColorPalette.rgba[3])
        XCTAssertEqual(line[VIC.displayLeft + 6], ColorPalette.rgba[4])
        XCTAssertFalse(foregroundMask[VIC.displayLeft])
        XCTAssertTrue(foregroundMask[VIC.displayLeft + 2])
        XCTAssertTrue(foregroundMask[VIC.displayLeft + 4])
        XCTAssertTrue(foregroundMask[VIC.displayLeft + 6])
    }

    func testMulticolorModeFallsBackToStandardTextWhenColorRamHighBitIsClear() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)
        var readAddresses: [UInt16] = []

        vic.controlReg2 = 0xD8
        vic.readMemory = { address in
            readAddresses.append(address)
            switch address {
            case 0x0400: return 0x01
            case 0x1008: return 0x80
            default: return 0
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertTrue(readAddresses.contains(0x1008))
        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[7])
        XCTAssertEqual(line[VIC.displayLeft + 1], ColorPalette.rgba[0])
        XCTAssertTrue(foregroundMask[VIC.displayLeft])
        XCTAssertFalse(foregroundMask[VIC.displayLeft + 1])
    }

    func testInvalidECMMulticolorTextModeRendersBlackButKeepsForegroundMask() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[1], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)

        vic.controlReg1 = 0x5B
        vic.controlReg2 = 0xD8
        vic.readMemory = { address in
            switch address {
            case 0x0400: return 0x01
            case 0x1008: return 0x80
            default: return 0
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[0])
        XCTAssertEqual(line[VIC.displayLeft + 1], ColorPalette.rgba[0])
        XCTAssertTrue(foregroundMask[VIC.displayLeft])
        XCTAssertFalse(foregroundMask[VIC.displayLeft + 1])
    }

    func testInvalidECMBitmapModeRendersBlackButKeepsForegroundMask() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[1], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)

        vic.controlReg1 = 0x7B
        vic.controlReg2 = 0xC8
        vic.readMemory = { address in
            switch address {
            case 0x0400: return 0xF2
            case 0x0000: return 0x80
            default: return 0
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[0])
        XCTAssertEqual(line[VIC.displayLeft + 1], ColorPalette.rgba[0])
        XCTAssertTrue(foregroundMask[VIC.displayLeft])
        XCTAssertFalse(foregroundMask[VIC.displayLeft + 1])
    }

    func testControlRegisterRasterHighBitUpdatesCompareButReadbackUsesCurrentRaster() {
        let vic = VIC()
        vic.rasterLine = 42

        vic.writeRegister(0x12, value: 0x34)
        vic.writeRegister(0x11, value: 0x9B)

        XCTAssertEqual(vic.rasterCompare, 0x134)
        XCTAssertEqual(vic.readRegister(0x11), 0x1B)

        vic.rasterLine = 300

        XCTAssertEqual(vic.readRegister(0x11), 0x9B)
    }

    func testRasterCompareWriteToCurrentLineRaisesIRQImmediately() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        vic.rasterLine = 0x0134

        vic.writeRegister(0x1A, value: 0x01)
        vic.writeRegister(0x12, value: 0x34)
        vic.writeRegister(0x11, value: 0x9B)

        XCTAssertEqual(vic.rasterCompare, 0x0134)
        XCTAssertEqual(vic.readRegister(0x19), 0xF1)
        XCTAssertEqual(irqStates, [true])
    }

    func testPendingRasterCompareWriteAssertsWhenIRQIsEnabled() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        vic.rasterLine = 0x0034

        vic.writeRegister(0x12, value: 0x34)

        XCTAssertEqual(vic.readRegister(0x19), 0x71)
        XCTAssertEqual(irqStates, [])

        vic.writeRegister(0x1A, value: 0x01)

        XCTAssertEqual(vic.readRegister(0x19), 0xF1)
        XCTAssertEqual(irqStates, [true])
    }

    func testEnablingRasterIRQOnCurrentCompareLineAssertsImmediately() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        vic.rasterLine = 0x0034

        vic.writeRegister(0x12, value: 0x34)

        XCTAssertEqual(vic.debugRegisterValue(0xD019), 0x71)
        XCTAssertEqual(irqStates, [])

        vic.writeRegister(0x1A, value: 0x01)

        XCTAssertEqual(vic.readRegister(0x19), 0xF1)
        XCTAssertEqual(irqStates, [true])
    }

    func testRasterHighBitWriteToCurrentLineRaisesIRQImmediately() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        vic.rasterLine = 0x0134

        vic.writeRegister(0x1A, value: 0x01)
        vic.writeRegister(0x12, value: 0x34)
        vic.writeRegister(0x19, value: 0x01)
        irqStates.removeAll()

        vic.writeRegister(0x11, value: 0x9B)

        XCTAssertEqual(vic.rasterCompare, 0x0134)
        XCTAssertEqual(vic.readRegister(0x19), 0xF1)
        XCTAssertEqual(irqStates, [true])
    }

    func testLightPenLatchReadsCoordinatesAndRaisesIRQ() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }

        vic.writeRegister(0x1A, value: 0x08)
        vic.triggerLightPen(x: 101, y: 251)

        XCTAssertEqual(vic.readRegister(0x13), 50)
        XCTAssertEqual(vic.readRegister(0x14), 251)
        XCTAssertEqual(vic.readRegister(0x19), 0xF8)
        XCTAssertEqual(irqStates, [true])

        vic.writeRegister(0x19, value: 0x08)

        XCTAssertEqual(vic.readRegister(0x19), 0x70)
        XCTAssertEqual(irqStates, [true, false])
    }

    func testLightPenLatchSetsPendingInterruptWithoutEnable() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }

        vic.triggerLightPen(x: 101, y: 251)

        XCTAssertEqual(vic.readRegister(0x13), 50)
        XCTAssertEqual(vic.readRegister(0x14), 251)
        XCTAssertEqual(vic.readRegister(0x19), 0x78)
        XCTAssertEqual(irqStates, [])

        vic.writeRegister(0x1A, value: 0x08)

        XCTAssertEqual(vic.readRegister(0x19), 0xF8)
        XCTAssertEqual(irqStates, [true])
    }

    func testAcknowledgingDisabledLightPenInterruptDoesNotPulseIRQ() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }

        vic.triggerLightPen(x: 101, y: 251)
        vic.writeRegister(0x19, value: 0x08)

        XCTAssertEqual(vic.readRegister(0x19), 0x70)
        XCTAssertEqual(irqStates, [])
    }

    func testLightPenLatchCanUseCurrentPALBeamPosition() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        vic.rasterLine = 251
        vic.rasterCycle = 31

        vic.writeRegister(0x1A, value: 0x08)
        vic.triggerLightPenAtCurrentBeam()

        let expectedBeamX = 31 * 512 / VIC.palCyclesPerLine
        XCTAssertEqual(vic.readRegister(0x13), UInt8((expectedBeamX >> 1) & 0xFF))
        XCTAssertEqual(vic.readRegister(0x14), 251)
        XCTAssertEqual(vic.readRegister(0x19), 0xF8)
        XCTAssertEqual(irqStates, [true])
    }

    func testLightPenLatchUsesCurrentNTSCBeamPosition() {
        let vic = VIC()
        vic.videoStandard = .ntsc
        vic.rasterLine = 250
        vic.rasterCycle = 64

        vic.triggerLightPenAtCurrentBeam()

        let expectedBeamX = 64 * 512 / VIC.ntscCyclesPerLine
        XCTAssertEqual(vic.readRegister(0x13), UInt8((expectedBeamX >> 1) & 0xFF))
        XCTAssertEqual(vic.readRegister(0x14), 250)
    }

    func testLightPenLatchCapturesOnlyFirstTriggerUntilNextFrame() {
        let vic = VIC()

        vic.triggerLightPen(x: 100, y: 50)
        vic.triggerLightPen(x: 300, y: 60)

        XCTAssertEqual(vic.readRegister(0x13), 50)
        XCTAssertEqual(vic.readRegister(0x14), 50)

        vic.rasterLine = UInt16(VIC.totalLines - 1)
        vic.endOfLine()
        vic.triggerLightPen(x: 300, y: 316)

        XCTAssertEqual(vic.readRegister(0x13), 150)
        XCTAssertEqual(vic.readRegister(0x14), 60)
    }

    func testLightPenLatchResetsAtNTSCFrameBoundary() {
        let vic = VIC()
        vic.videoStandard = .ntsc

        vic.triggerLightPen(x: 100, y: 50)
        vic.triggerLightPen(x: 300, y: 60)

        XCTAssertEqual(vic.readRegister(0x13), 50)
        XCTAssertEqual(vic.readRegister(0x14), 50)

        vic.rasterLine = UInt16(vic.rasterLinesPerFrame - 1)
        vic.endOfLine()
        vic.triggerLightPen(x: 300, y: 316)

        XCTAssertEqual(vic.readRegister(0x13), 150)
        XCTAssertEqual(vic.readRegister(0x14), 60)
    }

    func testRasterCompareWriteDoesNotRetriggerOnSameRasterline() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        vic.rasterLine = 0x0034

        vic.writeRegister(0x1A, value: 0x01)
        vic.writeRegister(0x12, value: 0x34)
        vic.writeRegister(0x19, value: 0x01)
        vic.writeRegister(0x12, value: 0x34)

        XCTAssertEqual(vic.readRegister(0x19), 0x70)
        XCTAssertEqual(irqStates, [true, false])
    }

    func testRasterInterruptFiresWhenEnteringCompareLine() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        vic.rasterLine = 0x0033
        vic.rasterCycle = vic.rasterCyclesPerLine - 1

        vic.writeRegister(0x12, value: 0x34)
        vic.writeRegister(0x1A, value: 0x01)
        vic.tick()

        XCTAssertEqual(vic.rasterLine, 0x0034)
        XCTAssertEqual(vic.rasterCycle, 0)
        XCTAssertEqual(vic.readRegister(0x19), 0xF1)
        XCTAssertEqual(irqStates, [true])
    }

    func testRasterInterruptDoesNotWaitUntilEndOfCompareLine() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        vic.rasterLine = 0x0034
        vic.rasterCycle = vic.rasterCyclesPerLine - 1

        vic.writeRegister(0x12, value: 0x34)
        vic.writeRegister(0x19, value: 0x01)
        irqStates.removeAll()
        vic.tick()

        XCTAssertEqual(vic.rasterLine, 0x0035)
        XCTAssertEqual(vic.readRegister(0x19), 0x70)
        XCTAssertEqual(irqStates, [])
    }

    func testMemoryPointerRegisterUnusedBitReadsHighButDoesNotAffectCharacterFetch() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)
        var readAddresses: [UInt16] = []

        vic.writeRegister(0x18, value: 0x14)
        XCTAssertEqual(vic.readRegister(0x18), 0x15)

        vic.writeRegister(0x18, value: 0x15)
        vic.readMemory = { address in
            readAddresses.append(address)
            switch address {
            case 0x0400: return 0x01
            case 0x1008: return 0x80
            default: return 0
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertTrue(readAddresses.contains(0x0400))
        XCTAssertTrue(readAddresses.contains(0x1008))
        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[7])
    }

    func testControlRegister2UnusedBitsReadHigh() {
        let vic = VIC()

        vic.writeRegister(0x16, value: 0x1B)

        XCTAssertEqual(vic.readRegister(0x16), 0xFB)
    }

    func testSpriteXPositionUsesHorizontalCoordinateOnly() {
        let vic = VIC()
        let background = ColorPalette.rgba[0]
        let spriteColor = ColorPalette.rgba[1]
        var line = [UInt32](repeating: background, count: VIC.screenWidth)

        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = UInt16(VIC.displayLeft)
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]

        vic.renderSprites(&line, fbY: 0)

        XCTAssertEqual(line[VIC.displayLeft], spriteColor)
        XCTAssertEqual(line[VIC.displayLeft - VIC.firstVisibleLine], background)
    }

    func testSpritePixelsWrapAroundNineBitHorizontalCounter() {
        let vic = VIC()
        let background = ColorPalette.rgba[0]
        let spriteColor = ColorPalette.rgba[1]
        var line = [UInt32](repeating: background, count: VIC.screenWidth)

        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = 508
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0xFF, 0x00, 0x00]

        vic.renderSprites(&line, fbY: 0)

        XCTAssertEqual(line[0], spriteColor)
        XCTAssertEqual(line[3], spriteColor)
        XCTAssertEqual(line[4], background)
        XCTAssertEqual(line[VIC.screenWidth - 1], background)
    }

    func testExpandedSpritePixelsWrapAroundNineBitHorizontalCounter() {
        let vic = VIC()
        let background = ColorPalette.rgba[0]
        let spriteColor = ColorPalette.rgba[1]
        var line = [UInt32](repeating: background, count: VIC.screenWidth)

        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteExpandX = 0x01
        vic.spriteX[0] = 508
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0xF0, 0x00, 0x00]

        vic.renderSprites(&line, fbY: 0)

        XCTAssertEqual(line[0], spriteColor)
        XCTAssertEqual(line[3], spriteColor)
        XCTAssertEqual(line[4], background)
        XCTAssertEqual(line[VIC.screenWidth - 1], background)
    }

    func testMulticolorSpritePixelsWrapAroundNineBitHorizontalCounter() {
        let vic = VIC()
        let background = ColorPalette.rgba[0]
        var line = [UInt32](repeating: background, count: VIC.screenWidth)

        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteMulticolor = 0x01
        vic.spriteX[0] = 510
        vic.spriteMulticolor0 = 0x02
        vic.spriteColors[0] = 0x03
        vic.spriteMulticolor1 = 0x04
        vic.spriteLineData[0] = [0b01101100, 0x00, 0x00]

        vic.renderSprites(&line, fbY: 0)

        XCTAssertEqual(line[0], ColorPalette.rgba[3])
        XCTAssertEqual(line[1], ColorPalette.rgba[3])
        XCTAssertEqual(line[2], ColorPalette.rgba[4])
        XCTAssertEqual(line[3], ColorPalette.rgba[4])
        XCTAssertEqual(line[4], background)
    }

    func testMulticolorSpriteUsesSharedAndIndividualColorsWithExpansion() {
        let vic = VIC()
        let background = ColorPalette.rgba[0]
        var line = [UInt32](repeating: background, count: VIC.screenWidth)

        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteMulticolor = 0x01
        vic.spriteExpandX = 0x01
        vic.spriteX[0] = UInt16(VIC.displayLeft)
        vic.spriteMulticolor0 = 0x02
        vic.spriteColors[0] = 0x03
        vic.spriteMulticolor1 = 0x04
        vic.spriteLineData[0] = [0b00011011, 0x00, 0x00]

        vic.renderSprites(&line, fbY: 0)

        XCTAssertEqual(line[VIC.displayLeft], background)
        XCTAssertEqual(line[VIC.displayLeft + 4], ColorPalette.rgba[2])
        XCTAssertEqual(line[VIC.displayLeft + 8], ColorPalette.rgba[3])
        XCTAssertEqual(line[VIC.displayLeft + 12], ColorPalette.rgba[4])
        XCTAssertEqual(line[VIC.displayLeft + 15], ColorPalette.rgba[4])
    }

    func testBeamSpriteTraceLatchesMidlineColorChangesByRasterPosition() {
        let vic = VIC()
        let line = UInt16(VIC.firstVisibleLine)

        vic.rasterLine = line
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = 0
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0xFF, 0xFF, 0xFF]

        while vic.rasterCycle < 2 {
            vic.tick()
        }
        vic.writeRegister(0x27, value: 0x05)
        while vic.rasterLine == line {
            vic.tick()
        }

        XCTAssertEqual(vic.framebuffer[8], ColorPalette.rgba[1])
        XCTAssertEqual(vic.framebuffer[16], ColorPalette.rgba[5])
    }

    func testBeamSpriteTraceWrapsAroundNineBitHorizontalCounter() {
        let vic = VIC()
        let line = UInt16(VIC.firstVisibleLine)

        vic.rasterLine = line
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = 508
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0xFF, 0x00, 0x00]

        while vic.rasterLine == line {
            vic.tick()
        }

        XCTAssertEqual(vic.framebuffer[0], ColorPalette.rgba[1])
        XCTAssertEqual(vic.framebuffer[3], ColorPalette.rgba[1])
        XCTAssertEqual(vic.framebuffer[4], ColorPalette.rgba[14])
    }

    func testBeamSpriteTraceLatchesMidlineSharedMulticolorChangesByRasterPosition() {
        let vic = VIC()
        let line = UInt16(VIC.firstVisibleLine)

        vic.rasterLine = line
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteMulticolor = 0x01
        vic.spriteX[0] = 0
        vic.spriteMulticolor0 = 0x02
        vic.spriteColors[0] = 0x03
        vic.spriteMulticolor1 = 0x04
        vic.spriteLineData[0] = [0b01010101, 0b01010101, 0b01010101]

        while vic.rasterCycle < 2 {
            vic.tick()
        }
        vic.writeRegister(0x25, value: 0x05)
        while vic.rasterLine == line {
            vic.tick()
        }

        XCTAssertEqual(vic.framebuffer[8], ColorPalette.rgba[2])
        XCTAssertEqual(vic.framebuffer[16], ColorPalette.rgba[5])
    }

    func testBeamSpriteTraceLatchesMidlineSharedMulticolorOneChangesByRasterPosition() {
        let vic = VIC()
        let line = UInt16(VIC.firstVisibleLine)

        vic.rasterLine = line
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteMulticolor = 0x01
        vic.spriteX[0] = 0
        vic.spriteMulticolor0 = 0x02
        vic.spriteColors[0] = 0x03
        vic.spriteMulticolor1 = 0x04
        vic.spriteLineData[0] = [0b11111111, 0b11111111, 0b11111111]

        while vic.rasterCycle < 2 {
            vic.tick()
        }
        vic.writeRegister(0x26, value: 0x06)
        while vic.rasterLine == line {
            vic.tick()
        }

        XCTAssertEqual(vic.framebuffer[8], ColorPalette.rgba[4])
        XCTAssertEqual(vic.framebuffer[16], ColorPalette.rgba[6])
    }

    func testBeamSpriteTraceHonorsMidlineMulticolorModeChangesByRasterPosition() {
        let vic = VIC()
        let line = UInt16(VIC.firstVisibleLine)

        vic.rasterLine = line
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = 0
        vic.spriteMulticolor0 = 0x02
        vic.spriteColors[0] = 0x03
        vic.spriteMulticolor1 = 0x04
        vic.spriteLineData[0] = [0b01010101, 0b01010101, 0b01010101]

        while vic.rasterCycle < 2 {
            vic.tick()
        }
        vic.writeRegister(0x1C, value: 0x01)
        while vic.rasterLine == line {
            vic.tick()
        }

        XCTAssertEqual(vic.framebuffer[8], ColorPalette.rgba[Int(vic.borderColor & 0x0F)])
        XCTAssertEqual(vic.framebuffer[16], ColorPalette.rgba[2])
    }

    func testBeamSpriteTraceHonorsMidlineXExpansionChangesByRasterPosition() {
        let vic = VIC()
        let line = UInt16(VIC.firstVisibleLine)

        vic.rasterLine = line
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = 0
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0xFF, 0x00, 0x00]

        while vic.rasterCycle < 2 {
            vic.tick()
        }
        vic.writeRegister(0x1D, value: 0x01)
        while vic.rasterLine == line {
            vic.tick()
        }

        XCTAssertEqual(vic.framebuffer[7], ColorPalette.rgba[1])
        XCTAssertEqual(vic.framebuffer[15], ColorPalette.rgba[1])
        XCTAssertEqual(vic.framebuffer[16], ColorPalette.rgba[Int(vic.borderColor & 0x0F)])
    }

    func testBeamSpriteTraceHonorsMidlineXMSBChangesByRasterPosition() {
        let vic = VIC()
        let line = UInt16(VIC.firstVisibleLine)

        vic.rasterLine = line
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = 0
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0xFF, 0xFF, 0xFF]

        while vic.rasterCycle < 2 {
            vic.tick()
        }
        vic.writeRegister(0x10, value: 0x01)
        while vic.rasterLine == line {
            vic.tick()
        }

        XCTAssertEqual(vic.framebuffer[8], ColorPalette.rgba[1])
        XCTAssertEqual(vic.framebuffer[32], ColorPalette.rgba[Int(vic.borderColor & 0x0F)])
        XCTAssertEqual(vic.framebuffer[256], ColorPalette.rgba[1])
    }

    func testBeamSpriteTraceRaisesSpriteCollisionDuringRasterCycle() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }

        vic.rasterLine = UInt16(VIC.firstVisibleLine)
        vic.spriteEnabled = 0x03
        vic.spriteDisplay[0] = true
        vic.spriteDisplay[1] = true
        vic.spriteX[0] = 0
        vic.spriteX[1] = 0
        vic.spriteColors[0] = 0x01
        vic.spriteColors[1] = 0x02
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]
        vic.spriteLineData[1] = [0x80, 0x00, 0x00]
        vic.writeRegister(0x1A, value: 0x04)

        vic.tick()

        XCTAssertEqual(vic.readRegister(0x19), 0xF4)
        XCTAssertEqual(irqStates, [true])
        XCTAssertEqual(vic.readRegister(0x1E), 0x03)
    }

    func testBeamSpriteTraceRaisesExpandedSpriteCollisionDuringRasterCycle() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }

        vic.rasterLine = UInt16(VIC.firstVisibleLine)
        vic.spriteEnabled = 0x03
        vic.spriteDisplay[0] = true
        vic.spriteDisplay[1] = true
        vic.spriteExpandX = 0x01
        vic.spriteX[0] = 0
        vic.spriteX[1] = 1
        vic.spriteColors[0] = 0x01
        vic.spriteColors[1] = 0x02
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]
        vic.spriteLineData[1] = [0x80, 0x00, 0x00]
        vic.writeRegister(0x1A, value: 0x04)

        vic.tick()

        XCTAssertEqual(vic.readRegister(0x19), 0xF4)
        XCTAssertEqual(irqStates, [true])
        XCTAssertEqual(vic.readRegister(0x1E), 0x03)
    }

    func testBeamSpriteTraceRaisesMulticolorSpriteCollisionDuringRasterCycle() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }

        vic.rasterLine = UInt16(VIC.firstVisibleLine)
        vic.spriteEnabled = 0x03
        vic.spriteDisplay[0] = true
        vic.spriteDisplay[1] = true
        vic.spriteMulticolor = 0x03
        vic.spriteX[0] = 0
        vic.spriteX[1] = 1
        vic.spriteMulticolor0 = 0x04
        vic.spriteColors[0] = 0x01
        vic.spriteColors[1] = 0x02
        vic.spriteLineData[0] = [0b01000000, 0x00, 0x00]
        vic.spriteLineData[1] = [0b01000000, 0x00, 0x00]
        vic.writeRegister(0x1A, value: 0x04)

        vic.tick()

        XCTAssertEqual(vic.readRegister(0x19), 0xF4)
        XCTAssertEqual(irqStates, [true])
        XCTAssertEqual(vic.readRegister(0x1E), 0x03)
    }

    func testBeamSpriteSpriteCollisionCanRelatchAfterMidlineReadClear() {
        let vic = VIC()

        vic.rasterLine = UInt16(VIC.firstVisibleLine)
        vic.spriteEnabled = 0x03
        vic.spriteDisplay[0] = true
        vic.spriteDisplay[1] = true
        vic.spriteX[0] = 0
        vic.spriteX[1] = 0
        vic.spriteColors[0] = 0x01
        vic.spriteColors[1] = 0x02
        vic.spriteLineData[0] = [0xC0, 0x00, 0x00]
        vic.spriteLineData[1] = [0xC0, 0x00, 0x00]
        vic.rasterTraceLine = vic.rasterLine
        vic.rasterTraceValid[0] = true
        vic.rasterTraceValid[1] = true
        vic.rasterTraceDisplayOpen[0] = false
        vic.rasterTraceDisplayOpen[1] = false
        vic.spriteTraceLine = vic.rasterLine

        vic.captureSpriteTrace(startPixel: 0, endPixel: 1)
        XCTAssertEqual(vic.readRegister(0x1E), 0x03)
        XCTAssertEqual(vic.debugRegisterValue(0xD01E), 0x00)

        vic.captureSpriteTrace(startPixel: 1, endPixel: 2)
        XCTAssertEqual(vic.debugRegisterValue(0xD01E), 0x03)
    }

    func testBeamSpriteTraceRaisesSpriteDataCollisionDuringRasterCycle() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }

        vic.rasterLine = UInt16(VIC.displayTop)
        vic.displayActive = true
        vic.writeRegister(0x1A, value: 0x02)
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = UInt16(VIC.displayLeft)
        vic.spriteY[0] = UInt8(VIC.displayTop)
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]
        vic.readMemory = { address in
            switch address {
            case 0x0400: return 0x01
            case 0x1008: return 0x80
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 3 {
            vic.tick()
        }
        XCTAssertEqual(vic.debugRegisterValue(0xD01F), 0x00)

        vic.tick()

        XCTAssertEqual(vic.debugRegisterValue(0xD01F), 0x01)
        XCTAssertEqual(vic.readRegister(0x19), 0xF2)
        XCTAssertEqual(irqStates, [true])
        XCTAssertEqual(vic.readRegister(0x1F), 0x01)
        XCTAssertEqual(vic.readRegister(0x1F), 0x00)

        while vic.rasterLine == UInt16(VIC.displayTop) {
            vic.tick()
        }

        XCTAssertEqual(vic.readRegister(0x1F), 0x00)
    }

    func testBeamSpriteTraceRaisesExpandedSpriteDataCollisionDuringRasterCycle() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }

        vic.rasterLine = UInt16(VIC.displayTop)
        vic.displayActive = true
        vic.writeRegister(0x1A, value: 0x02)
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteExpandX = 0x01
        vic.spriteX[0] = UInt16(VIC.displayLeft - 1)
        vic.spriteY[0] = UInt8(VIC.displayTop)
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]
        vic.readMemory = { address in
            switch address {
            case 0x0400: return 0x01
            case 0x1008: return 0x80
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 3 {
            vic.tick()
        }
        XCTAssertEqual(vic.debugRegisterValue(0xD01F), 0x00)

        vic.tick()

        XCTAssertEqual(vic.readRegister(0x19), 0xF2)
        XCTAssertEqual(irqStates, [true])
        XCTAssertEqual(vic.readRegister(0x1F), 0x01)
    }

    func testBeamSpriteTraceRaisesMulticolorSpriteDataCollisionDuringRasterCycle() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }

        vic.rasterLine = UInt16(VIC.displayTop)
        vic.displayActive = true
        vic.writeRegister(0x1A, value: 0x02)
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteMulticolor = 0x01
        vic.spriteX[0] = UInt16(VIC.displayLeft - 1)
        vic.spriteY[0] = UInt8(VIC.displayTop)
        vic.spriteMulticolor0 = 0x04
        vic.spriteColors[0] = 0x01
        vic.spriteMulticolor1 = 0x02
        vic.spriteLineData[0] = [0b01000000, 0x00, 0x00]
        vic.readMemory = { address in
            switch address {
            case 0x0400: return 0x01
            case 0x1008: return 0x80
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 3 {
            vic.tick()
        }
        XCTAssertEqual(vic.debugRegisterValue(0xD01F), 0x00)

        vic.tick()

        XCTAssertEqual(vic.readRegister(0x19), 0xF2)
        XCTAssertEqual(irqStates, [true])
        XCTAssertEqual(vic.readRegister(0x1F), 0x01)
    }

    func testBeamSpriteDataCollisionUsesLowPhaseLatchedTextColorMode() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }

        let x = VIC.displayLeft
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.displayActive = true
        vic.rasterTraceLine = vic.rasterLine
        vic.rasterTraceValid[x] = true
        vic.rasterTraceDisplayOpen[x] = true
        vic.spriteTraceLine = vic.rasterLine
        vic.writeRegister(0x1A, value: 0x02)

        vic.graphicsBufferBase = 0
        vic.graphicsBufferPixelRow = 0
        vic.graphicsFetchMask = 0x01
        vic.graphicsBuffer[0] = 0b01000000
        vic.graphicsBufferControlReg1[0] = vic.controlReg1
        vic.graphicsBufferControlReg2[0] = 0xD8
        vic.graphicsBufferMemoryPointers[0] = vic.memoryPointers
        vic.graphicsBufferBackgroundColors[0] = vic.backgroundColor
        vic.graphicsBufferScreenBytes[0] = 0x01
        vic.graphicsBufferColorData[0] = 0x08

        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = UInt16(x)
        vic.spriteY[0] = UInt8(VIC.displayTop)
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]
        vic.readMemory = { _ in 0x00 }
        vic.readColorRAM = { _ in 0x00 }

        vic.captureSpriteTrace(startPixel: x, endPixel: x + 1)

        XCTAssertEqual(vic.debugRegisterValue(0xD01F), 0x01)
        XCTAssertEqual(vic.readRegister(0x19), 0xF2)
        XCTAssertEqual(irqStates, [true])
    }

    func testBeamSpriteDataCollisionCanRelatchAfterMidlineReadClear() {
        let vic = VIC()

        let x = VIC.displayLeft
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.displayActive = true
        vic.rasterTraceLine = vic.rasterLine
        vic.rasterTraceValid[x] = true
        vic.rasterTraceValid[x + 1] = true
        vic.rasterTraceDisplayOpen[x] = true
        vic.rasterTraceDisplayOpen[x + 1] = true
        vic.spriteTraceLine = vic.rasterLine

        vic.graphicsBufferBase = 0
        vic.graphicsBufferPixelRow = 0
        vic.graphicsFetchMask = 0x01
        vic.graphicsBuffer[0] = 0b11000000
        vic.graphicsBufferControlReg1[0] = vic.controlReg1
        vic.graphicsBufferControlReg2[0] = vic.controlReg2
        vic.graphicsBufferMemoryPointers[0] = vic.memoryPointers
        vic.graphicsBufferBackgroundColors[0] = vic.backgroundColor
        vic.graphicsBufferScreenBytes[0] = 0x01
        vic.graphicsBufferColorData[0] = 0x07

        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = UInt16(x)
        vic.spriteY[0] = UInt8(VIC.displayTop)
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0xC0, 0x00, 0x00]
        vic.readMemory = { _ in 0x00 }
        vic.readColorRAM = { _ in 0x00 }

        vic.captureSpriteTrace(startPixel: x, endPixel: x + 1)
        XCTAssertEqual(vic.readRegister(0x1F), 0x01)
        XCTAssertEqual(vic.debugRegisterValue(0xD01F), 0x00)

        vic.captureSpriteTrace(startPixel: x + 1, endPixel: x + 2)
        XCTAssertEqual(vic.debugRegisterValue(0xD01F), 0x01)
    }

    func testBeamSpriteTraceHonorsMidlineEnableChangesByRasterPosition() {
        let vic = VIC()
        let line = UInt16(VIC.firstVisibleLine)

        vic.rasterLine = line
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = 0
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0xFF, 0xFF, 0xFF]

        while vic.rasterCycle < 2 {
            vic.tick()
        }
        vic.writeRegister(0x15, value: 0x00)
        while vic.rasterLine == line {
            vic.tick()
        }

        XCTAssertEqual(vic.framebuffer[8], ColorPalette.rgba[1])
        XCTAssertEqual(vic.framebuffer[24], ColorPalette.rgba[Int(vic.borderColor & 0x0F)])
    }

    func testBeamSpriteTraceHonorsMidlineXPositionChangesByRasterPosition() {
        let vic = VIC()
        let line = UInt16(VIC.firstVisibleLine)

        vic.rasterLine = line
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = 0
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0xFF, 0xFF, 0xFF]

        while vic.rasterCycle < 2 {
            vic.tick()
        }
        vic.writeRegister(0x00, value: 40)
        while vic.rasterLine == line {
            vic.tick()
        }

        XCTAssertEqual(vic.framebuffer[8], ColorPalette.rgba[1])
        XCTAssertEqual(vic.framebuffer[32], ColorPalette.rgba[Int(vic.borderColor & 0x0F)])
        XCTAssertEqual(vic.framebuffer[40], ColorPalette.rgba[1])
    }

    func testBeamSpriteTraceHonorsMidlinePriorityChangesByRasterPosition() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = UInt16(VIC.displayLeft)
        vic.spriteY[0] = UInt8(VIC.displayTop)
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0xFF, 0xFF, 0xFF]
        vic.readMemory = { address in
            switch address {
            case 0x0400...0x0427: return 0x01
            case 0x1008: return 0xFF
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterCycle < 5 {
            vic.tick()
        }
        vic.writeRegister(0x1B, value: 0x01)
        while vic.rasterLine == line {
            vic.tick()
        }

        let rowOffset = (VIC.displayTop - VIC.firstVisibleLine) * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 1], ColorPalette.rgba[1])
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 16], ColorPalette.rgba[7])
    }

    func testBeamSpriteTracePriorityUsesForegroundSampledAtRasterPosition() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)
        let x = VIC.displayLeft

        vic.rasterLine = line
        vic.displayActive = true
        vic.verticalBorderActive = false
        vic.horizontalBorderActive = false
        vic.rasterTraceLine = line
        vic.rasterTraceHasSamples = true
        vic.rasterTraceHasDisplayOpen = true
        vic.rasterTraceValid[x] = true
        vic.rasterTraceDisplayOpen[x] = true
        vic.spriteTraceLine = line

        vic.graphicsBufferBase = 0
        vic.graphicsBufferPixelRow = 0
        vic.graphicsFetchMask = 0x01
        vic.graphicsBuffer[0] = 0x00
        vic.graphicsBufferControlReg1[0] = vic.controlReg1
        vic.graphicsBufferControlReg2[0] = vic.controlReg2
        vic.graphicsBufferMemoryPointers[0] = vic.memoryPointers
        vic.graphicsBufferBackgroundColors[0] = vic.backgroundColor
        vic.graphicsBufferScreenBytes[0] = 0x01
        vic.graphicsBufferColorData[0] = 0x07

        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spritePriority = 0x01
        vic.spriteX[0] = UInt16(x)
        vic.spriteY[0] = UInt8(VIC.displayTop)
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]
        vic.readMemory = { _ in 0x00 }
        vic.readColorRAM = { _ in 0x00 }

        vic.captureSpriteTrace(startPixel: x, endPixel: x + 1)
        vic.graphicsBuffer[0] = 0x80
        vic.renderRasterline()

        let rowOffset = (VIC.displayTop - VIC.firstVisibleLine) * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + x], ColorPalette.rgba[1])
    }

    func testBeamSpriteTracePriorityIsNotRevealedByLaterForegroundClear() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)
        let x = VIC.displayLeft

        vic.rasterLine = line
        vic.displayActive = true
        vic.verticalBorderActive = false
        vic.horizontalBorderActive = false
        vic.rasterTraceLine = line
        vic.rasterTraceHasSamples = true
        vic.rasterTraceHasDisplayOpen = true
        vic.rasterTraceValid[x] = true
        vic.rasterTraceDisplayOpen[x] = true
        vic.spriteTraceLine = line

        vic.graphicsBufferBase = 0
        vic.graphicsBufferPixelRow = 0
        vic.graphicsFetchMask = 0x01
        vic.graphicsBuffer[0] = 0x80
        vic.graphicsBufferControlReg1[0] = vic.controlReg1
        vic.graphicsBufferControlReg2[0] = vic.controlReg2
        vic.graphicsBufferMemoryPointers[0] = vic.memoryPointers
        vic.graphicsBufferBackgroundColors[0] = vic.backgroundColor
        vic.graphicsBufferScreenBytes[0] = 0x01
        vic.graphicsBufferColorData[0] = 0x07

        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spritePriority = 0x01
        vic.spriteX[0] = UInt16(x)
        vic.spriteY[0] = UInt8(VIC.displayTop)
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]
        vic.readMemory = { _ in 0x00 }
        vic.readColorRAM = { _ in 0x00 }

        vic.captureSpriteTrace(startPixel: x, endPixel: x + 1)
        vic.graphicsBuffer[0] = 0x00
        vic.renderRasterline()

        let rowOffset = (VIC.displayTop - VIC.firstVisibleLine) * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + x], ColorPalette.rgba[0])
    }

    func testBeamSpriteTraceKeepsLowerSpriteVisibleWhenTopSpriteIsBehindForeground() {
        let vic = VIC()
        let line = UInt16(VIC.displayTop)

        vic.rasterLine = line
        vic.displayActive = true
        vic.spriteEnabled = 0x03
        vic.spriteDisplay[0] = true
        vic.spriteDisplay[1] = true
        vic.spritePriority = 0x01
        vic.spriteX[0] = UInt16(VIC.displayLeft)
        vic.spriteX[1] = UInt16(VIC.displayLeft)
        vic.spriteY[0] = UInt8(VIC.displayTop)
        vic.spriteY[1] = UInt8(VIC.displayTop)
        vic.spriteColors[0] = 0x01
        vic.spriteColors[1] = 0x02
        vic.spriteLineData[0] = [0xFF, 0xFF, 0xFF]
        vic.spriteLineData[1] = [0xFF, 0xFF, 0xFF]
        vic.readMemory = { address in
            switch address {
            case 0x0400...0x0427: return 0x01
            case 0x1008: return 0xFF
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        while vic.rasterLine == line {
            vic.tick()
        }

        let rowOffset = (VIC.displayTop - VIC.firstVisibleLine) * VIC.screenWidth
        XCTAssertEqual(vic.framebuffer[rowOffset + VIC.displayLeft + 1], ColorPalette.rgba[2])
        XCTAssertEqual(vic.readRegister(0x1E), 0x03)
        XCTAssertEqual(vic.readRegister(0x1F), 0x03)
    }

    func testSpriteDataFetchRunsDuringEarlyRasterCycles() {
        let vic = VIC()
        vic.rasterLine = 0
        vic.rasterCycle = 58
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 0
        vic.spritePointers[0] = 0x02
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x07FB: return 0x05
            case 0x0080: return 0xAA
            case 0x0081: return 0xBB
            case 0x0082: return 0xCC
            default: return 0
            }
        }

        vic.tick()

        XCTAssertTrue(vic.spriteDisplay[0])
        XCTAssertEqual(vic.spriteLineData[0], [0xAA, 0xBB, 0xCC])
        XCTAssertEqual(reads, [0x07FB, 0x0080, 0x0081, 0x0082])
        XCTAssertEqual(vic.lastHighPhaseMemoryReads, [0x0080, 0x0081, 0x0082])
        XCTAssertEqual(vic.lastHighPhaseColorRAMReads, [])
    }

    func testSpriteDMABusPhaseUsesPerSpriteSlots() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 58
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7

        XCTAssertEqual(vic.activeSpriteDMASlot, 0)
        XCTAssertEqual(vic.busPhase, .spriteDMA(sprite: 0))
        XCTAssertTrue(vic.baLineLow)
        XCTAssertTrue(vic.aecLineLow)
        XCTAssertEqual(vic.busOwner, .vicSpriteDMA)

        vic.tick()

        XCTAssertEqual(vic.rasterCycle, 59)
        XCTAssertEqual(vic.activeSpriteDMASlot, 0)
        XCTAssertEqual(vic.busPhase, .spriteDMA(sprite: 0))
        XCTAssertTrue(vic.baLineLow)
        XCTAssertTrue(vic.aecLineLow)

        vic.tick()

        XCTAssertEqual(vic.rasterCycle, 60)
        XCTAssertNil(vic.activeSpriteDMASlot)
        XCTAssertEqual(vic.busPhase, .cpu)
        XCTAssertFalse(vic.baLineLow)
        XCTAssertFalse(vic.aecLineLow)
    }

    func testSpriteDMABusPhaseWrapsAcrossRasterlineForSpriteTwo() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 62
        vic.spriteEnabled = 0x04
        vic.spriteY[2] = 7

        XCTAssertEqual(vic.activeSpriteDMASlot, 2)
        XCTAssertEqual(vic.busPhase, .spriteDMA(sprite: 2))
        XCTAssertTrue(vic.baLineLow)
        XCTAssertTrue(vic.aecLineLow)

        vic.tick()

        XCTAssertEqual(vic.rasterLine, 8)
        XCTAssertEqual(vic.rasterCycle, 0)
        XCTAssertEqual(vic.activeSpriteDMASlot, 2)
        XCTAssertEqual(vic.busPhase, .spriteDMA(sprite: 2))
        XCTAssertTrue(vic.baLineLow)
        XCTAssertTrue(vic.aecLineLow)

        vic.tick()

        XCTAssertEqual(vic.rasterCycle, 1)
        XCTAssertNil(vic.activeSpriteDMASlot)
        XCTAssertEqual(vic.busPhase, .cpu)
        XCTAssertFalse(vic.baLineLow)
        XCTAssertFalse(vic.aecLineLow)
    }

    func testSpriteTwoDMAWrapKeepsSecondCycleActiveAfterFinalSpriteRow() {
        let vic = VIC()
        vic.rasterLine = 27
        vic.rasterCycle = 62
        vic.spriteEnabled = 0x04
        vic.spriteY[2] = 7

        XCTAssertEqual(vic.spriteLineRow(for: 2), 20)
        XCTAssertEqual(vic.activeSpriteDMASlot, 2)
        XCTAssertEqual(vic.busPhase, .spriteDMA(sprite: 2))
        XCTAssertTrue(vic.baLineLow)
        XCTAssertTrue(vic.aecLineLow)

        vic.tick()

        XCTAssertEqual(vic.rasterLine, 28)
        XCTAssertEqual(vic.rasterCycle, 0)
        XCTAssertNil(vic.spriteLineRow(for: 2))
        XCTAssertEqual(vic.activeSpriteDMASlot, 2)
        XCTAssertEqual(vic.busPhase, .spriteDMA(sprite: 2))
        XCTAssertTrue(vic.baLineLow)
        XCTAssertTrue(vic.aecLineLow)

        vic.tick()

        XCTAssertEqual(vic.rasterCycle, 1)
        XCTAssertNil(vic.activeSpriteDMASlot)
        XCTAssertEqual(vic.busPhase, .cpu)
        XCTAssertFalse(vic.baLineLow)
        XCTAssertFalse(vic.aecLineLow)
    }

    func testWrappedSpriteDMAMiddleByteUsesFetchedByteOffset() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 62
        vic.spriteEnabled = 0x04
        vic.spriteY[2] = 7
        vic.spritePointers[2] = 0x02
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x0080: return 0x11
            case 0x0081: return 0x22
            case 0x0082: return 0x33
            default: return 0x00
            }
        }

        vic.tick()

        XCTAssertEqual(vic.rasterLine, 8)
        XCTAssertEqual(vic.rasterCycle, 0)
        XCTAssertEqual(vic.activeSpriteDMASlot, 2)
        XCTAssertEqual(vic.lowPhaseAccess, .spriteMiddleByte(sprite: 2))
        XCTAssertEqual(vic.spriteLastFetchedByteOffset[2], 0)

        reads.removeAll()
        vic.performLowPhaseAccess()

        XCTAssertEqual(reads, [0x0081])
        XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x0081])
        XCTAssertEqual(vic.spriteLineData[2], [0x11, 0x22, 0x33])
    }

    func testWrappedFinalSpriteRowMiddleByteDoesNotFallBackToNewRasterLineRange() {
        let vic = VIC()
        vic.rasterLine = 27
        vic.rasterCycle = 62
        vic.spriteEnabled = 0x04
        vic.spriteY[2] = 7
        vic.spritePointers[2] = 0x02
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x0080 + 60: return 0x11
            case 0x0080 + 61: return 0x22
            case 0x0080 + 62: return 0x33
            default: return 0x00
            }
        }

        XCTAssertEqual(vic.spriteLineRow(for: 2), 20)

        vic.tick()

        XCTAssertEqual(vic.rasterLine, 28)
        XCTAssertEqual(vic.rasterCycle, 0)
        XCTAssertNil(vic.spriteLineRow(for: 2))
        XCTAssertEqual(vic.activeSpriteDMASlot, 2)
        XCTAssertEqual(vic.lowPhaseAccess, .spriteMiddleByte(sprite: 2))
        XCTAssertEqual(vic.spriteLastFetchedByteOffset[2], 60)

        reads.removeAll()
        vic.performLowPhaseAccess()

        XCTAssertEqual(reads, [0x0080 + 61])
        XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x0080 + 61])
        XCTAssertEqual(vic.spriteLineData[2], [0x11, 0x22, 0x33])
    }

    func testNTSCSpriteTwoDMAUsesCycleSixtyThreeInsteadOfRasterWrap() {
        let vic = VIC()
        vic.videoStandard = .ntsc
        vic.rasterLine = 7
        vic.rasterCycle = 62
        vic.spriteEnabled = 0x04
        vic.spriteY[2] = 7

        XCTAssertEqual(vic.activeSpriteDMASlot, 2)
        XCTAssertEqual(vic.busPhase, .spriteDMA(sprite: 2))

        vic.tick()

        XCTAssertEqual(vic.rasterLine, 7)
        XCTAssertEqual(vic.rasterCycle, 63)
        XCTAssertEqual(vic.activeSpriteDMASlot, 2)
        XCTAssertEqual(vic.busPhase, .spriteDMA(sprite: 2))

        vic.tick()

        XCTAssertEqual(vic.rasterLine, 7)
        XCTAssertEqual(vic.rasterCycle, 64)
        XCTAssertNil(vic.activeSpriteDMASlot)
        XCTAssertEqual(vic.busPhase, .cpu)
    }

    func testNTSCSpriteThreeDMAWrapsFromCycleSixtyFourToNextRasterline() {
        let vic = VIC()
        vic.videoStandard = .ntsc
        vic.rasterLine = 7
        vic.rasterCycle = 64
        vic.spriteEnabled = 0x08
        vic.spriteY[3] = 7

        XCTAssertEqual(vic.activeSpriteDMASlot, 3)
        XCTAssertEqual(vic.busPhase, .spriteDMA(sprite: 3))
        XCTAssertTrue(vic.aecLineLow)

        vic.tick()

        XCTAssertEqual(vic.rasterLine, 8)
        XCTAssertEqual(vic.rasterCycle, 0)
        XCTAssertEqual(vic.activeSpriteDMASlot, 3)
        XCTAssertEqual(vic.busPhase, .spriteDMA(sprite: 3))
        XCTAssertTrue(vic.aecLineLow)

        vic.tick()

        XCTAssertEqual(vic.rasterCycle, 1)
        XCTAssertNil(vic.activeSpriteDMASlot)
        XCTAssertEqual(vic.busPhase, .cpu)
    }

    func testSpriteBAWarningDropsBeforeDMASlotWithoutAEC() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 55
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7

        XCTAssertEqual(vic.activeSpriteBAWarningSlot, 0)
        XCTAssertEqual(vic.busPhase, .spriteBAWarning(sprite: 0))
        XCTAssertTrue(vic.baLineLow)
        XCTAssertFalse(vic.aecLineLow)
        XCTAssertFalse(vic.isStealingCPU)
        XCTAssertEqual(vic.busOwner, .cpu)

        vic.tick()
        XCTAssertEqual(vic.rasterCycle, 56)
        XCTAssertEqual(vic.busPhase, .spriteBAWarning(sprite: 0))

        vic.tick()
        XCTAssertEqual(vic.rasterCycle, 57)
        XCTAssertEqual(vic.busPhase, .spriteBAWarning(sprite: 0))

        vic.tick()
        XCTAssertEqual(vic.rasterCycle, 58)
        XCTAssertEqual(vic.busPhase, .spriteDMA(sprite: 0))
        XCTAssertTrue(vic.aecLineLow)
        XCTAssertEqual(vic.busOwner, .vicSpriteDMA)
    }

    func testLatchedSpriteBAWarningSurvivesEnableClearBeforeDMASlot() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 55
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7

        vic.tick()
        vic.spriteEnabled = 0x00

        XCTAssertEqual(vic.rasterCycle, 56)
        XCTAssertEqual(vic.spriteDMACheckMask & 0x01, 0x01)
        XCTAssertEqual(vic.activeSpriteBAWarningSlot, 0)
        XCTAssertEqual(vic.busPhase, .spriteBAWarning(sprite: 0))
        XCTAssertTrue(vic.baLineLow)
        XCTAssertFalse(vic.aecLineLow)

        vic.tick()

        XCTAssertEqual(vic.rasterCycle, 57)
        XCTAssertEqual(vic.activeSpriteBAWarningSlot, 0)
        XCTAssertEqual(vic.busPhase, .spriteBAWarning(sprite: 0))
        XCTAssertTrue(vic.baLineLow)
        XCTAssertFalse(vic.aecLineLow)

        vic.tick()

        XCTAssertEqual(vic.rasterCycle, 58)
        XCTAssertEqual(vic.activeSpriteDMASlot, 0)
        XCTAssertEqual(vic.busPhase, .spriteDMA(sprite: 0))
        XCTAssertTrue(vic.aecLineLow)
    }

    func testSpriteEnableBeforeSecondDMACheckStillAssertsBAWarning() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 55
        vic.spriteEnabled = 0x00
        vic.spriteY[0] = 7

        vic.tick()
        vic.spriteEnabled = 0x01

        XCTAssertEqual(vic.rasterCycle, 56)
        XCTAssertEqual(vic.spriteDMACheckMask & 0x01, 0)
        XCTAssertNil(vic.activeSpriteBAWarningSlot)
        XCTAssertEqual(vic.busPhase, .cpu)
        XCTAssertFalse(vic.baLineLow)

        vic.tick()

        XCTAssertEqual(vic.rasterCycle, 57)
        XCTAssertEqual(vic.spriteDMACheckMask & 0x01, 0x01)
        XCTAssertEqual(vic.activeSpriteBAWarningSlot, 0)
        XCTAssertEqual(vic.busPhase, .spriteBAWarning(sprite: 0))
        XCTAssertTrue(vic.baLineLow)
    }

    func testSpriteBAWarningCanTargetSpriteOnNextRasterline() {
        let vic = VIC()
        vic.rasterLine = 10
        vic.rasterCycle = 61
        vic.spriteEnabled = 0x08
        vic.spriteY[3] = 11

        XCTAssertEqual(vic.activeSpriteBAWarningSlot, 3)
        XCTAssertEqual(vic.busPhase, .spriteBAWarning(sprite: 3))
        XCTAssertTrue(vic.baLineLow)
        XCTAssertFalse(vic.aecLineLow)

        vic.tick()
        XCTAssertEqual(vic.rasterCycle, 62)
        XCTAssertEqual(vic.busPhase, .spriteBAWarning(sprite: 3))

        vic.tick()
        XCTAssertEqual(vic.rasterLine, 11)
        XCTAssertEqual(vic.rasterCycle, 0)
        XCTAssertEqual(vic.busPhase, .spriteBAWarning(sprite: 3))
    }

    func testSpriteDMASlotIgnoresInactiveVerticalRange() {
        let vic = VIC()
        vic.rasterLine = 10
        vic.rasterCycle = 58
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 42

        XCTAssertNil(vic.activeSpriteDMASlot)
        XCTAssertEqual(vic.busPhase, .cpu)
        XCTAssertFalse(vic.baLineLow)
        XCTAssertFalse(vic.aecLineLow)
    }

    func testSpriteBAWarningIgnoresInactiveVerticalRange() {
        let vic = VIC()
        vic.rasterLine = 10
        vic.rasterCycle = 55
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 42

        XCTAssertNil(vic.activeSpriteBAWarningSlot)
        XCTAssertEqual(vic.busPhase, .cpu)
        XCTAssertFalse(vic.baLineLow)
        XCTAssertFalse(vic.aecLineLow)
    }

    func testSpriteDMAEligibilityLatchesAtCycleFiftyFive() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 55
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7

        vic.tick()

        XCTAssertEqual(vic.spriteDMACheckLine, 7)
        XCTAssertEqual(vic.spriteDMACheckMask & 0x01, 0x01)
        XCTAssertEqual(vic.spriteExpansionLine[0], 7)
        XCTAssertEqual(vic.spriteMCBase[0], 0)

        vic.rasterCycle = 58
        XCTAssertEqual(vic.activeSpriteDMASlot, 0)
        XCTAssertEqual(vic.busPhase, .spriteDMA(sprite: 0))
    }

    func testEnablingSpriteAfterCycleFiftySixDoesNotStartCurrentLineDMA() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 55
        vic.spriteEnabled = 0x00
        vic.spriteY[0] = 7

        vic.tick()
        vic.tick()
        vic.spriteEnabled = 0x01
        vic.tick()

        XCTAssertEqual(vic.rasterCycle, 58)
        XCTAssertEqual(vic.spriteDMACheckLine, 7)
        XCTAssertEqual(vic.spriteDMACheckMask & 0x01, 0)
        XCTAssertNil(vic.activeSpriteDMASlot)
        XCTAssertEqual(vic.busPhase, .cpu)
    }

    func testChangingSpriteYAfterCycleFiftySixDoesNotStartCurrentLineDMA() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 55
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 8

        vic.tick()
        vic.tick()
        vic.spriteY[0] = 7
        vic.tick()

        XCTAssertEqual(vic.rasterCycle, 58)
        XCTAssertEqual(vic.spriteDMACheckLine, 7)
        XCTAssertEqual(vic.spriteDMACheckMask & 0x01, 0)
        XCTAssertNil(vic.activeSpriteDMASlot)
        XCTAssertEqual(vic.busPhase, .cpu)
    }

    func testLatchedSpriteDMARunsAfterSpriteEnableIsCleared() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 55
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7
        vic.readMemory = { address in
            switch address {
            case 0x07F8: return 0x02
            case 0x0080: return 0xAA
            case 0x0081: return 0xBB
            case 0x0082: return 0xCC
            default: return 0
            }
        }

        vic.tick()
        vic.tick()
        vic.spriteEnabled = 0x00
        vic.tick()

        XCTAssertEqual(vic.rasterCycle, 58)
        XCTAssertEqual(vic.activeSpriteDMASlot, 0)

        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x0080: return 0xAA
            case 0x0081: return 0xBB
            case 0x0082: return 0xCC
            default: return 0
            }
        }

        vic.fetchSpriteData(sprite: 0)

        XCTAssertEqual(reads, [0x0080, 0x0081, 0x0082])
        XCTAssertEqual(vic.spriteLineData[0], [0xAA, 0xBB, 0xCC])
    }

    func testSpriteDisplayLatchesAtCycleFiftyEightAfterDMACheck() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 55
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7
        vic.spritePointers[0] = 0x02
        vic.readMemory = { address in
            switch address {
            case 0x07F8: return 0x02
            case 0x07F9: return 0x09
            case 0x07FA: return 0x0A
            case 0x07FB: return 0x0B
            case 0x0080: return 0xAA
            case 0x0081: return 0xBB
            case 0x0082: return 0xCC
            default: return 0
            }
        }

        while vic.rasterCycle < 58 {
            vic.tick()
        }

        XCTAssertFalse(vic.spriteDisplay[0])

        vic.tick()

        XCTAssertTrue(vic.spriteDisplay[0])
        XCTAssertEqual(vic.spriteLineData[0], [0xAA, 0xBB, 0xCC])
        XCTAssertEqual(vic.spriteMC[0], 3)
    }

    func testSpriteDMAContinuesOnSecondSpriteRowAfterInitialYCompare() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 55
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7
        vic.spritePointers[0] = 0x02
        vic.readMemory = { address in
            switch address {
            case 0x07F8...0x07FF: return 0x02
            case 0x0080: return 0xAA
            case 0x0081: return 0xBB
            case 0x0082: return 0xCC
            case 0x0083: return 0xDD
            case 0x0084: return 0xEE
            case 0x0085: return 0xFF
            default: return 0
            }
        }

        while !(vic.rasterLine == 8 && vic.rasterCycle == 58) {
            vic.tick()
        }

        XCTAssertTrue(vic.spriteDisplay[0])
        XCTAssertEqual(vic.spriteDMACheckLine, 8)
        XCTAssertEqual(vic.spriteDMACheckMask & 0x01, 0x01)
        XCTAssertEqual(vic.activeSpriteDMASlot, 0)

        vic.tick()

        XCTAssertEqual(vic.spriteLineData[0], [0xDD, 0xEE, 0xFF])
        XCTAssertEqual(vic.spriteMC[0], 6)
        XCTAssertEqual(vic.lastHighPhaseMemoryReads, [0x0083, 0x0084, 0x0085])
    }

    func testSpriteYChangeAfterDMACheckPreventsCycleFiftyEightDisplayButKeepsDMA() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 55
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7
        vic.spritePointers[0] = 0x02
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x07F8: return 0x02
            case 0x07F9: return 0x09
            case 0x07FA: return 0x0A
            case 0x07FB: return 0x0B
            case 0x0080: return 0xAA
            case 0x0081: return 0xBB
            case 0x0082: return 0xCC
            default: return 0
            }
        }

        while vic.rasterCycle < 58 {
            vic.tick()
        }
        vic.spriteY[0] = 8

        XCTAssertEqual(vic.activeSpriteDMASlot, 0)

        vic.tick()

        XCTAssertFalse(vic.spriteDisplay[0])
        XCTAssertEqual(vic.spriteLineData[0], [0xAA, 0xBB, 0xCC])
        XCTAssertEqual(reads, [0x07F8, 0x07F9, 0x07FA, 0x07FB, 0x0080, 0x0081, 0x0082])
    }

    func testSpriteEnableClearAfterDMACheckStillAllowsCycleFiftyEightDisplay() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 55
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7
        vic.spriteColors[0] = 0x02
        vic.spritePointers[0] = 0x02
        vic.readMemory = { address in
            switch address {
            case 0x07F8: return 0x02
            case 0x07F9: return 0x09
            case 0x07FA: return 0x0A
            case 0x07FB: return 0x0B
            case 0x0080: return 0x80
            case 0x0081: return 0x00
            case 0x0082: return 0x00
            default: return 0
            }
        }

        while vic.rasterCycle < 58 {
            vic.tick()
        }
        vic.spriteEnabled = 0x00

        vic.tick()

        XCTAssertTrue(vic.spriteDisplay[0])
        XCTAssertEqual(vic.spriteLineData[0], [0x80, 0x00, 0x00])

        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        vic.renderSprites(&line, fbY: 0)

        XCTAssertEqual(line[0], ColorPalette.rgba[2])
    }

    func testLateSpriteEnableBeforeCycleFiftyEightDoesNotTurnOnDisplayWithoutDMACheck() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 55
        vic.spriteEnabled = 0x00
        vic.spriteY[0] = 7

        while vic.rasterCycle < 58 {
            vic.tick()
            if vic.rasterCycle == 57 {
                vic.spriteEnabled = 0x01
            }
        }

        XCTAssertNil(vic.activeSpriteDMASlot)

        vic.tick()

        XCTAssertFalse(vic.spriteDisplay[0])
        XCTAssertNil(vic.activeSpriteDMASlot)
    }

    func testSpriteDMAFetchesOnlyAtStartOfTwoCycleSlot() {
        let vic = VIC()
        vic.rasterLine = 0
        vic.rasterCycle = 58
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 0
        vic.spritePointers[0] = 0x02
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x07FB: return 0x05
            case 0x0080: return 0xAA
            case 0x0081: return 0xBB
            case 0x0082: return 0xCC
            default: return 0
            }
        }

        vic.tick()
        XCTAssertEqual(vic.rasterCycle, 59)
        XCTAssertEqual(reads, [0x07FB, 0x0080, 0x0081, 0x0082])
        XCTAssertEqual(vic.lastHighPhaseMemoryReads, [0x0080, 0x0081, 0x0082])

        vic.tick()
        XCTAssertEqual(vic.rasterCycle, 60)
        XCTAssertEqual(reads, [0x07FB, 0x0080, 0x0081, 0x0082, 0x07FC])
        XCTAssertEqual(vic.lastHighPhaseMemoryReads, [])
    }

    func testHighPhaseReadTraceClearsOnCPUCycleAfterBadLineFetch() {
        let vic = VIC()
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rasterCycle = 54
        vic.badLine = true
        vic.readMemory = { _ in 0x41 }
        vic.readColorRAM = { _ in 0x07 }

        vic.tick()

        XCTAssertEqual(vic.rasterCycle, 55)
        XCTAssertEqual(vic.lastHighPhaseMemoryReads, [0x0427])
        XCTAssertEqual(vic.lastHighPhaseColorRAMReads, [0x0027])

        vic.tick()

        XCTAssertEqual(vic.rasterCycle, 56)
        XCTAssertEqual(vic.lastHighPhaseMemoryReads, [])
        XCTAssertEqual(vic.lastHighPhaseColorRAMReads, [])
    }

    func testSpriteExpansionStateInitializesUnexpandedRowsEachRasterLine() {
        let vic = VIC()
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7

        vic.rasterLine = 7
        vic.updateSpriteExpansionStateForCurrentLine()
        XCTAssertTrue(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMC[0], 0)
        XCTAssertEqual(vic.spriteLineRow(for: 0), 0)

        vic.rasterLine = 8
        vic.updateSpriteExpansionStateForCurrentLine()
        XCTAssertTrue(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMC[0], 3)
        XCTAssertEqual(vic.spriteLineRow(for: 0), 1)
    }

    func testLowSpriteYCoordinateRepeatsAfterRasterCounterWrap() {
        let vic = VIC()
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7

        vic.rasterLine = 263
        vic.updateSpriteExpansionStateForCurrentLine()

        XCTAssertTrue(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMC[0], 0)
        XCTAssertEqual(vic.spriteLineRow(for: 0), 0)

        vic.rasterLine = 264
        vic.updateSpriteExpansionStateForCurrentLine()

        XCTAssertEqual(vic.spriteMC[0], 3)
        XCTAssertEqual(vic.spriteLineRow(for: 0), 1)
    }

    func testLowSpriteYCoordinateSecondCompareEndsAfterSpriteHeight() {
        let vic = VIC()
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7

        vic.rasterLine = 284
        vic.updateSpriteExpansionStateForCurrentLine()

        XCTAssertFalse(vic.spriteDisplay[0])
        XCTAssertNil(vic.spriteLineRow(for: 0))
        XCTAssertNil(vic.activeSpriteDMASlot)
    }

    func testSpriteDMAFetchesFromRepeatedYCompareAfterRasterCounterWrap() {
        let vic = VIC()
        vic.rasterLine = 263
        vic.rasterCycle = 58
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7
        vic.spritePointers[0] = 0x02
        vic.updateSpriteExpansionStateForCurrentLine()
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x0080: return 0xAA
            case 0x0081: return 0xBB
            case 0x0082: return 0xCC
            default: return 0
            }
        }

        vic.latchSpriteDisplayForCurrentLine()
        vic.fetchSpriteData(sprite: 0)

        XCTAssertTrue(vic.spriteDisplay[0])
        XCTAssertEqual(vic.spriteLineData[0], [0xAA, 0xBB, 0xCC])
        XCTAssertEqual(reads, [0x0080, 0x0081, 0x0082])
    }

    func testExpandedSpriteYCoordinateRepeatsWithDoubledRowsAfterRasterCounterWrap() {
        let vic = VIC()
        vic.spriteEnabled = 0x01
        vic.spriteExpandY = 0x01
        vic.spriteY[0] = 7

        vic.rasterLine = 263
        vic.updateSpriteExpansionStateForCurrentLine()

        XCTAssertFalse(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMC[0], 0)
        XCTAssertEqual(vic.spriteLineRow(for: 0), 0)

        vic.rasterLine = 264
        vic.updateSpriteExpansionStateForCurrentLine()

        XCTAssertTrue(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMC[0], 0)
        XCTAssertEqual(vic.spriteLineRow(for: 0), 0)

        vic.rasterLine = 265
        vic.updateSpriteExpansionStateForCurrentLine()

        XCTAssertFalse(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMC[0], 3)
        XCTAssertEqual(vic.spriteLineRow(for: 0), 1)
    }

    func testNTSCDoesNotRepeatLowSpriteYCoordinatePastFrameEnd() {
        let vic = VIC()
        vic.videoStandard = .ntsc
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7

        vic.rasterLine = 262
        vic.updateSpriteExpansionStateForCurrentLine()

        XCTAssertNil(vic.spriteLineRow(for: 0))
        XCTAssertNil(vic.activeSpriteDMASlot)
    }

    func testLineStartDisabledSpriteClearsStaleDisplayState() {
        let vic = VIC()

        vic.rasterLine = 7
        vic.spriteEnabled = 0x00
        vic.spriteY[0] = 7
        vic.spriteDisplay[0] = true
        vic.spriteLineData[0] = [0xFF, 0xFF, 0xFF]

        vic.updateSpriteExpansionStateForCurrentLine()

        XCTAssertFalse(vic.spriteDisplay[0])

        vic.spriteEnabled = 0x01
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        vic.renderSprites(&line, fbY: 0)

        XCTAssertEqual(line[0], ColorPalette.rgba[0])
    }

    func testSpriteExpansionStateRepeatsRowsForExpandedSprites() {
        let vic = VIC()
        vic.spriteEnabled = 0x01
        vic.spriteExpandY = 0x01
        vic.spriteY[0] = 7

        vic.rasterLine = 7
        vic.updateSpriteExpansionStateForCurrentLine()
        XCTAssertFalse(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMC[0], 0)
        XCTAssertEqual(vic.spriteLineRow(for: 0), 0)

        vic.rasterLine = 8
        vic.updateSpriteExpansionStateForCurrentLine()
        XCTAssertTrue(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMC[0], 0)
        XCTAssertEqual(vic.spriteLineRow(for: 0), 0)

        vic.rasterLine = 9
        vic.updateSpriteExpansionStateForCurrentLine()
        XCTAssertFalse(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMC[0], 3)
        XCTAssertEqual(vic.spriteLineRow(for: 0), 1)
    }

    func testClearingYExpansionDuringActiveRepeatedLineAdvancesSpriteCounter() {
        let vic = VIC()
        vic.spriteEnabled = 0x01
        vic.spriteExpandY = 0x01
        vic.spriteY[0] = 7

        vic.rasterLine = 7
        vic.updateSpriteExpansionStateForCurrentLine()
        XCTAssertFalse(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMC[0], 0)

        vic.writeRegister(0x17, value: 0x00)

        XCTAssertTrue(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMC[0], 3)
        XCTAssertEqual(vic.spriteLineByteOffset(for: 0), 3)
    }

    func testClearingYExpansionAtCycleFifteenAppliesSpriteCrunchCounterFormula() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 15
        vic.spriteEnabled = 0x01
        vic.spriteExpandY = 0x01
        vic.spriteY[0] = 7
        vic.updateSpriteExpansionStateForCurrentLine()
        vic.spriteMCBase[0] = 0
        vic.spriteLastFetchedMC[0] = 3

        vic.writeRegister(0x17, value: 0x00)

        XCTAssertTrue(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMCBase[0], 1)
        XCTAssertEqual(vic.spriteMC[0], 1)
        XCTAssertEqual(vic.spriteLineByteOffset(for: 0), 1)
    }

    func testClearingYExpansionAtCycleFifteenChangesSpriteDMAFetchToCrunchedBytes() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 15
        vic.spriteEnabled = 0x01
        vic.spriteExpandY = 0x01
        vic.spriteY[0] = 7
        vic.spritePointers[0] = 0x02
        vic.updateSpriteExpansionStateForCurrentLine()
        vic.spriteLastFetchedMC[0] = 3
        vic.writeRegister(0x17, value: 0x00)
        vic.rasterCycle = 58

        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x0081: return 0x11
            case 0x0082: return 0x22
            case 0x0083: return 0x33
            default: return 0
            }
        }

        vic.fetchSpriteData(sprite: 0)

        XCTAssertEqual(reads, [0x0081, 0x0082, 0x0083])
        XCTAssertEqual(vic.spriteLineData[0], [0x11, 0x22, 0x33])
        XCTAssertEqual(vic.spriteMC[0], 4)
        XCTAssertEqual(vic.spriteLastFetchedMC[0], 4)
    }

    func testClearingYExpansionWhenExpansionFlipFlopAlreadySetDoesNotDoubleAdvanceCounter() {
        let vic = VIC()
        vic.spriteEnabled = 0x01
        vic.spriteExpandY = 0x01
        vic.spriteY[0] = 7

        vic.rasterLine = 8
        vic.updateSpriteExpansionStateForCurrentLine()
        XCTAssertTrue(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMC[0], 0)

        vic.writeRegister(0x17, value: 0x00)

        XCTAssertTrue(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMC[0], 0)
        XCTAssertEqual(vic.spriteLineByteOffset(for: 0), 0)
    }

    func testLateYExpansionClearAfterCounterWindowDoesNotCrunchActiveSpriteLine() {
        let vic = VIC()
        vic.spriteEnabled = 0x01
        vic.spriteExpandY = 0x01
        vic.spriteY[0] = 7
        vic.rasterLine = 7
        vic.rasterCycle = 17
        vic.updateSpriteExpansionStateForCurrentLine()

        vic.writeRegister(0x17, value: 0x00)

        XCTAssertFalse(vic.spriteYExpFF[0])
        XCTAssertEqual(vic.spriteMC[0], 0)
        XCTAssertEqual(vic.spriteLineByteOffset(for: 0), 0)
    }

    func testExpandedSpriteDMAUsesInitializedSpriteCounter() {
        let vic = VIC()
        vic.rasterLine = 10
        vic.rasterCycle = 58
        vic.spriteEnabled = 0x01
        vic.spriteExpandY = 0x01
        vic.spriteY[0] = 7
        vic.spritePointers[0] = 0x02
        vic.updateSpriteExpansionStateForCurrentLine()
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x0080 + 3: return 0xAA
            case 0x0080 + 4: return 0xBB
            case 0x0080 + 5: return 0xCC
            default: return 0
            }
        }

        vic.fetchSpriteData(sprite: 0)

        XCTAssertEqual(vic.spriteMC[0], 6)
        XCTAssertEqual(vic.spriteLineData[0], [0xAA, 0xBB, 0xCC])
        XCTAssertEqual(reads, [0x0083, 0x0084, 0x0085])
    }

    func testSpriteDMAAdvancesUnexpandedSpriteCounterByThreeBytes() {
        let vic = VIC()
        vic.rasterLine = 9
        vic.rasterCycle = 58
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 7
        vic.spritePointers[0] = 0x02
        vic.updateSpriteExpansionStateForCurrentLine()
        vic.readMemory = { address in
            switch address {
            case 0x0086: return 0xAA
            case 0x0087: return 0xBB
            case 0x0088: return 0xCC
            default: return 0
            }
        }

        XCTAssertEqual(vic.spriteMC[0], 6)
        XCTAssertEqual(vic.spriteLineRow(for: 0), 2)

        vic.fetchSpriteData(sprite: 0)

        XCTAssertEqual(vic.spriteLineData[0], [0xAA, 0xBB, 0xCC])
        XCTAssertEqual(vic.spriteMC[0], 9)
        XCTAssertEqual(vic.spriteLineRow(for: 0), 3)
    }

    func testSpritePointerLatchesDuringLowPhaseBeforeDMASlot() {
        let vic = VIC()
        vic.rasterLine = 0
        vic.rasterCycle = 55
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 0
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x07F8: return 0x02
            case 0x07F9: return 0x09
            case 0x07FA: return 0x0A
            case 0x07FB: return 0x0B
            case 0x0080: return 0xAA
            case 0x0081: return 0xBB
            case 0x0082: return 0xCC
            default: return 0
            }
        }

        while vic.rasterCycle < 58 {
            vic.tick()
        }

        XCTAssertEqual(vic.spritePointers[0], 0x02)
        XCTAssertEqual(vic.spritePointers[1], 0x09)
        XCTAssertEqual(vic.spritePointers[2], 0x0A)
        XCTAssertEqual(reads, [0x07F8, 0x07F9, 0x07FA])

        vic.tick()

        XCTAssertTrue(vic.spriteDisplay[0])
        XCTAssertEqual(vic.spriteLineData[0], [0xAA, 0xBB, 0xCC])
        XCTAssertEqual(reads, [0x07F8, 0x07F9, 0x07FA, 0x07FB, 0x0080, 0x0081, 0x0082])
    }

    func testNTSCSpritePointerSlotsUseLastEightRasterCycles() {
        let vic = VIC()
        vic.videoStandard = .ntsc
        vic.rasterLine = 0

        vic.rasterCycle = 55
        XCTAssertEqual(vic.lowPhaseAccess, .idle)

        vic.rasterCycle = 56
        XCTAssertEqual(vic.lowPhaseAccess, .idle)

        vic.rasterCycle = 57
        XCTAssertEqual(vic.lowPhaseAccess, .spritePointer(sprite: 0))

        vic.rasterCycle = 64
        XCTAssertEqual(vic.lowPhaseAccess, .spritePointer(sprite: 7))
    }

    func testNTSCSpritePointerLatchesAtCycleSixtyFourDuringSpriteThreeDMAStart() {
        let vic = VIC()
        vic.videoStandard = .ntsc
        vic.rasterLine = 7
        vic.rasterCycle = 64
        vic.spriteEnabled = 0x08
        vic.spriteY[3] = 7
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            return address == 0x07FF ? 0x0B : 0
        }

        vic.performLowPhaseAccess()

        XCTAssertEqual(vic.lowPhaseAccess, .spritePointer(sprite: 7))
        XCTAssertEqual(vic.spritePointers[7], 0x0B)
        XCTAssertEqual(reads, [0x07FF])
        XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x07FF])
    }

    func testLowPhaseSpriteMiddleByteFetchesCurrentSpriteRowMiddleByte() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 2
        vic.spriteEnabled = 0x08
        vic.spriteY[3] = 7
        vic.spritePointers[3] = 0x02
        vic.spriteLineData[3] = [0x11, 0x00, 0x33]
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            return address == 0x0081 ? 0x22 : 0x00
        }

        vic.performLowPhaseAccess()

        XCTAssertEqual(reads, [0x0081])
        XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x0081])
        XCTAssertEqual(vic.spriteLineData[3], [0x11, 0x22, 0x33])
    }

    func testLowPhaseMemoryReadTraceRecordsIdleAndRefreshCycles() {
        let vic = VIC()
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rasterCycle = 15
        vic.displayActive = true
        vic.readMemory = { address in
            switch address {
            case 0x0400: return 0x01
            case 0x1008: return 0x80
            default: return 0
            }
        }

        vic.performLowPhaseAccess()

        XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x0400, 0x1008])

        vic.rasterCycle = 10
        vic.performLowPhaseAccess()

        XCTAssertEqual(vic.lowPhaseAccess, .refresh(index: 0))
        XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x3FFF])
        XCTAssertEqual(vic.refreshCounter, 0xFE)

        vic.rasterCycle = 9
        vic.performLowPhaseAccess()

        XCTAssertEqual(vic.lowPhaseAccess, .idle)
        XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x3FFF])
    }

    func testLowPhaseIdleAccessUsesECMIdleAddress() {
        let vic = VIC()
        vic.rasterCycle = 9
        vic.writeRegister(0x11, value: 0x5B)
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            return 0
        }

        vic.performLowPhaseAccess()

        XCTAssertEqual(vic.lowPhaseAccess, .idle)
        XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x39FF])
        XCTAssertEqual(reads, [0x39FF])
    }

    func testLowPhaseAccessReportsRefreshCycles() {
        let vic = VIC()
        vic.rasterLine = 20
        vic.rasterCycle = 10

        for index in 0..<5 {
            XCTAssertEqual(vic.lowPhaseAccess, .refresh(index: index))
            XCTAssertEqual(vic.busPhase, .cpu)
            XCTAssertFalse(vic.baLineLow)
            XCTAssertFalse(vic.aecLineLow)
            vic.tick()
        }

        XCTAssertEqual(vic.refreshCounter, 0xFA)
        XCTAssertEqual(vic.rasterCycle, 15)
        XCTAssertEqual(vic.lowPhaseAccess, .displayData(column: 0))
    }

    func testLowPhaseRefreshCounterWrapsAndResetsAtFrameStart() {
        let vic = VIC()
        vic.rasterLine = 0
        vic.rasterCycle = 10
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            return 0
        }

        for _ in 0..<5 {
            vic.performLowPhaseAccess()
            vic.rasterCycle += 1
        }

        XCTAssertEqual(reads, [0x3FFF, 0x3FFE, 0x3FFD, 0x3FFC, 0x3FFB])
        XCTAssertEqual(vic.refreshCounter, 0xFA)

        vic.refreshCounter = 0x01
        vic.rasterCycle = 10
        vic.performLowPhaseAccess()
        vic.rasterCycle = 11
        vic.performLowPhaseAccess()
        vic.rasterCycle = 12
        vic.performLowPhaseAccess()

        XCTAssertEqual(reads.suffix(3), [0x3F01, 0x3F00, 0x3FFF])
        XCTAssertEqual(vic.refreshCounter, 0xFE)

        vic.rasterLine = UInt16(vic.rasterLinesPerFrame - 1)
        vic.rasterCycle = vic.rasterCyclesPerLine - 1
        vic.endOfLine()

        XCTAssertEqual(vic.rasterLine, 0)
        XCTAssertEqual(vic.refreshCounter, 0xFF)
    }

    func testLowPhaseAccessReportsDisplayColumns() {
        let vic = VIC()
        vic.rasterLine = 20
        vic.rasterCycle = 15

        for column in 0..<40 {
            XCTAssertEqual(vic.lowPhaseAccess, .displayData(column: column))
            vic.tick()
        }

        XCTAssertEqual(vic.rasterCycle, 55)
        XCTAssertEqual(vic.lowPhaseAccess, .spritePointer(sprite: 0))
    }

    func testLowPhaseAccessReportsSpritePointersWithoutStealingCPU() {
        let vic = VIC()
        vic.rasterLine = 20
        vic.rasterCycle = 55

        for sprite in 0..<8 {
            XCTAssertEqual(vic.lowPhaseAccess, .spritePointer(sprite: sprite))
            XCTAssertEqual(vic.busPhase, .cpu)
            XCTAssertFalse(vic.baLineLow)
            XCTAssertFalse(vic.aecLineLow)
            vic.tick()
        }
    }

    func testLowPhaseSpriteMiddleByteRequiresActiveSprite() {
        let vic = VIC()
        vic.rasterLine = 7
        vic.rasterCycle = 2
        vic.spriteEnabled = 0x08
        vic.spriteY[3] = 7

        XCTAssertEqual(vic.lowPhaseAccess, .spriteMiddleByte(sprite: 3))

        vic.spriteY[3] = 42

        XCTAssertEqual(vic.lowPhaseAccess, .idle)
    }

    func testTickReturnsTrueOnlyDuringBadLineBusStealWindow() {
        let vic = VIC()
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rasterCycle = 0
        vic.badLineDENLatched = true

        XCTAssertFalse(vic.tick())
        XCTAssertTrue(vic.badLine)

        while vic.rasterCycle < 15 {
            XCTAssertFalse(vic.tick())
        }

        XCTAssertTrue(vic.tick())
    }

    func testBadLineBALineDropsThreeCyclesBeforeAEC() {
        let vic = VIC()
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rasterCycle = 0
        vic.badLineDENLatched = true
        vic.rowCounter = 5

        vic.tick()
        XCTAssertTrue(vic.badLine)
        XCTAssertEqual(vic.rowCounter, 0)

        while vic.rasterCycle < 12 {
            XCTAssertFalse(vic.baLineLow)
            XCTAssertFalse(vic.aecLineLow)
            XCTAssertEqual(vic.busOwner, .cpu)
            vic.tick()
        }

        XCTAssertTrue(vic.baLineLow)
        XCTAssertFalse(vic.aecLineLow)
        XCTAssertFalse(vic.isStealingCPU)
        XCTAssertEqual(vic.busOwner, .cpu)
        XCTAssertEqual(vic.busPhase, .badLineBAWarning)

        while vic.rasterCycle < 15 {
            vic.tick()
        }

        XCTAssertTrue(vic.baLineLow)
        XCTAssertTrue(vic.aecLineLow)
        XCTAssertTrue(vic.isStealingCPU)
        XCTAssertEqual(vic.busOwner, .vicBadLine)
        XCTAssertEqual(vic.busPhase, .badLineCharacterFetch(column: 0))

        while vic.rasterCycle < 55 {
            vic.tick()
        }

        XCTAssertFalse(vic.baLineLow)
        XCTAssertFalse(vic.aecLineLow)
        XCTAssertFalse(vic.isStealingCPU)
        XCTAssertEqual(vic.busOwner, .cpu)
        XCTAssertEqual(vic.busPhase, .cpu)
    }

    func testBadLineBusPhaseReportsCharacterFetchColumn() {
        let vic = VIC()
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rasterCycle = 0
        vic.badLineDENLatched = true

        while vic.rasterCycle < 15 {
            vic.tick()
        }

        for column in 0..<40 {
            XCTAssertEqual(vic.busPhase, .badLineCharacterFetch(column: column))
            vic.tick()
        }

        XCTAssertEqual(vic.rasterCycle, 55)
        XCTAssertEqual(vic.busPhase, .cpu)
    }

    func testBadLineFetchLatchesCharacterAndColorRAM() {
        let vic = VIC()
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rasterCycle = 15
        vic.badLine = true
        vic.videoCounterBase = 80
        var screenReads: [UInt16] = []
        var colorReads: [UInt16] = []
        vic.readMemory = { address in
            screenReads.append(address)
            switch address {
            case 0x0450: return 0x41
            case 0x0451: return 0x42
            default: return 0
            }
        }
        vic.readColorRAM = { address in
            colorReads.append(address)
            switch address {
            case 0x0050: return 0x2A
            case 0x0051: return 0x37
            default: return 0
            }
        }

        vic.tick()
        vic.tick()

        XCTAssertEqual(vic.lineBuffer[0], 0x41)
        XCTAssertEqual(vic.lineBuffer[1], 0x42)
        XCTAssertEqual(vic.colorBuffer[0], 0x0A)
        XCTAssertEqual(vic.colorBuffer[1], 0x07)
        XCTAssertEqual(vic.displayLineBufferBase, 80)
        XCTAssertEqual(screenReads, [0x0450, 0x0451])
        XCTAssertEqual(colorReads, [0x0050, 0x0051])
        XCTAssertEqual(vic.lastHighPhaseMemoryReads, [0x0451])
        XCTAssertEqual(vic.lastHighPhaseColorRAMReads, [0x0051])
    }

    func testBadLineFetchUsesCurrentScreenBasePerColumn() {
        let vic = VIC()
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rasterCycle = 15
        vic.badLine = true
        vic.memoryPointers = 0x14
        var screenReads: [UInt16] = []
        vic.readMemory = { address in
            screenReads.append(address)
            switch address {
            case 0x0400: return 0x41
            case 0x0801: return 0x42
            default: return 0
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        vic.tick()
        vic.writeRegister(0x18, value: 0x24)
        vic.tick()

        XCTAssertEqual(vic.lineBuffer[0], 0x41)
        XCTAssertEqual(vic.lineBuffer[1], 0x42)
        XCTAssertEqual(screenReads, [0x0400, 0x0801])
    }

    func testLateStartedBadLineFirstFetchesUseUnstableStartupData() {
        let vic = VIC()
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rasterCycle = 20
        vic.badLineDENLatched = true
        vic.writeRegister(0x11, value: 0x10)
        var screenReads: [UInt16] = []
        var colorReads: [UInt16] = []
        vic.readMemory = { address in
            screenReads.append(address)
            return address == 0x0408 ? 0x42 : 0x41
        }
        vic.readColorRAM = { address in
            colorReads.append(address)
            return 0x07
        }

        vic.writeRegister(0x11, value: 0x13)
        for _ in 0..<4 {
            vic.tick()
        }

        XCTAssertEqual(vic.badLineStartCycle, 20)
        XCTAssertEqual(vic.lineBuffer[5], 0xFF)
        XCTAssertEqual(vic.lineBuffer[6], 0xFF)
        XCTAssertEqual(vic.lineBuffer[7], 0xFF)
        XCTAssertEqual(vic.lineBuffer[8], 0x42)
        XCTAssertEqual(vic.colorBuffer[5], 0x0F)
        XCTAssertEqual(vic.colorBuffer[6], 0x0F)
        XCTAssertEqual(vic.colorBuffer[7], 0x0F)
        XCTAssertEqual(screenReads, [0x0408])
        XCTAssertEqual(colorReads, [0x0008])
    }

    func testRenderingUsesCompletedBadLineCharacterAndColorBuffers() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)
        var screenReads: [UInt16] = []
        var colorReads: [UInt16] = []

        vic.lineBuffer[0] = 0x01
        vic.colorBuffer[0] = 0x02
        vic.displayLineBufferValid = true
        vic.readMemory = { address in
            screenReads.append(address)
            switch address {
            case 0x1008: return 0x80
            default: return 0x00
            }
        }
        vic.readColorRAM = { address in
            colorReads.append(address)
            return 0x07
        }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[2])
        XCTAssertFalse(screenReads.contains(0x0400))
        XCTAssertFalse(colorReads.contains(0x0000))
        XCTAssertTrue(screenReads.contains(0x1008))
    }

    func testRenderingUsesPartiallyFetchedBadLineColumns() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)
        var screenReads: [UInt16] = []
        var colorReads: [UInt16] = []

        vic.lineBuffer[0] = 0x01
        vic.colorBuffer[0] = 0x02
        vic.displayLineBufferBase = 0
        vic.badLineFetchMask = 0x01
        vic.readMemory = { address in
            screenReads.append(address)
            switch address {
            case 0x0401: return 0x03
            case 0x1008: return 0x80
            case 0x1018: return 0x80
            default: return 0x00
            }
        }
        vic.readColorRAM = { address in
            colorReads.append(address)
            return address == 0x0001 ? 0x07 : 0x0F
        }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[2])
        XCTAssertEqual(line[VIC.displayLeft + 8], ColorPalette.rgba[7])
        XCTAssertFalse(screenReads.contains(0x0400))
        XCTAssertTrue(screenReads.contains(0x0401))
        XCTAssertFalse(colorReads.contains(0x0000))
        XCTAssertTrue(colorReads.contains(0x0001))
    }

    func testLowPhaseDisplayDataLatchesGlyphByteForCompletedMatrixRow() {
        let vic = VIC()
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rasterCycle = 15
        vic.displayActive = true
        vic.rowCounter = 3
        vic.lineBuffer[0] = 0x01
        vic.displayLineBufferValid = true
        vic.displayLineBufferBase = 0
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x100B: return 0x80
            default: return 0x00
            }
        }

        vic.performLowPhaseAccess()

        XCTAssertEqual(vic.graphicsBuffer[0], 0x80)
        XCTAssertEqual(vic.graphicsBufferBase, 0)
        XCTAssertEqual(vic.graphicsBufferPixelRow, 3)
        XCTAssertFalse(vic.graphicsBufferValid)
        XCTAssertEqual(reads, [0x100B])
        XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x100B])
    }

    func testLowPhaseDisplayDataUsesPartiallyFetchedMatrixColumn() {
        let vic = VIC()
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rasterCycle = 15
        vic.displayActive = true
        vic.rowCounter = 3
        vic.lineBuffer[0] = 0x01
        vic.displayLineBufferBase = 0
        vic.badLineFetchMask = 0x01
        var reads: [UInt16] = []
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x100B: return 0x80
            default: return 0x00
            }
        }

        vic.performLowPhaseAccess()

        XCTAssertEqual(vic.graphicsBuffer[0], 0x80)
        XCTAssertEqual(vic.graphicsBufferBase, 0)
        XCTAssertEqual(vic.graphicsBufferPixelRow, 3)
        XCTAssertEqual(reads, [0x100B])
        XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x100B])
    }

    func testRenderingUsesCompletedLowPhaseGraphicsBuffer() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)
        var reads: [UInt16] = []

        vic.lineBuffer[0] = 0x01
        vic.colorBuffer[0] = 0x02
        vic.displayLineBufferValid = true
        vic.displayLineBufferBase = 0
        vic.graphicsBuffer[0] = 0x80
        vic.graphicsBufferValid = true
        vic.graphicsBufferBase = 0
        vic.graphicsBufferPixelRow = 0
        vic.graphicsBufferScreenBytes[0] = 0x01
        vic.graphicsBufferColorData[0] = 0x02
        vic.readMemory = { address in
            reads.append(address)
            return 0x00
        }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[2])
        XCTAssertFalse(reads.contains(0x1008))
    }

    func testRenderingUsesLowPhaseLatchedBitmapScreenByte() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)
        var screenByte: UInt8 = 0x37
        var bitmapByte: UInt8 = 0x80

        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rasterCycle = 15
        vic.displayActive = true
        vic.controlReg1 = 0x3B
        vic.readMemory = { address in
            switch address {
            case 0x0400: return screenByte
            case 0x0000: return bitmapByte
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x0E }

        vic.performLowPhaseAccess()
        screenByte = 0xF2
        bitmapByte = 0x00

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(vic.graphicsBufferScreenBytes[0], 0x37)
        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[3])
        XCTAssertEqual(line[VIC.displayLeft + 1], ColorPalette.rgba[7])
        XCTAssertTrue(foregroundMask[VIC.displayLeft])
        XCTAssertFalse(foregroundMask[VIC.displayLeft + 1])
    }

    func testRenderingUsesLowPhaseLatchedTextColorData() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)
        var screenByte: UInt8 = 0x01
        var glyphByte: UInt8 = 0x80
        var colorNibble: UInt8 = 0x02

        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rasterCycle = 15
        vic.displayActive = true
        vic.readMemory = { address in
            switch address {
            case 0x0400: return screenByte
            case 0x1008: return glyphByte
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in colorNibble }

        vic.performLowPhaseAccess()
        screenByte = 0x03
        glyphByte = 0x00
        colorNibble = 0x07

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(vic.graphicsBufferScreenBytes[0], 0x01)
        XCTAssertEqual(vic.graphicsBufferColorData[0], 0x02)
        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[2])
        XCTAssertEqual(line[VIC.displayLeft + 1], ColorPalette.rgba[0])
        XCTAssertTrue(foregroundMask[VIC.displayLeft])
        XCTAssertFalse(foregroundMask[VIC.displayLeft + 1])
    }

    func testRenderingUsesPartiallyFetchedLowPhaseGraphicsColumns() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)
        var reads: [UInt16] = []

        vic.lineBuffer[0] = 0x01
        vic.lineBuffer[1] = 0x02
        vic.colorBuffer[0] = 0x02
        vic.colorBuffer[1] = 0x07
        vic.displayLineBufferValid = true
        vic.displayLineBufferBase = 0
        vic.graphicsBuffer[0] = 0x80
        vic.graphicsBufferBase = 0
        vic.graphicsBufferPixelRow = 0
        vic.graphicsFetchMask = 0x01
        vic.graphicsBufferControlReg1[0] = vic.controlReg1
        vic.graphicsBufferControlReg2[0] = vic.controlReg2
        vic.graphicsBufferMemoryPointers[0] = vic.memoryPointers
        vic.graphicsBufferBackgroundColors[0] = vic.backgroundColor
        vic.graphicsBufferScreenBytes[0] = 0x01
        vic.graphicsBufferColorData[0] = 0x02
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x1010: return 0x80
            default: return 0x00
            }
        }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[2])
        XCTAssertEqual(line[VIC.displayLeft + 8], ColorPalette.rgba[7])
        XCTAssertFalse(reads.contains(0x1008))
        XCTAssertTrue(reads.contains(0x1010))
    }

    func testPartiallyFetchedLowPhaseGraphicsColumnLatchesDisplayMode() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)

        vic.controlReg2 = 0xC8
        vic.lineBuffer[0] = 0x01
        vic.lineBuffer[1] = 0x01
        vic.colorBuffer[0] = 0x0F
        vic.colorBuffer[1] = 0x0F
        vic.displayLineBufferValid = true
        vic.displayLineBufferBase = 0
        vic.graphicsBuffer[0] = 0x40
        vic.graphicsBufferBase = 0
        vic.graphicsBufferPixelRow = 0
        vic.graphicsFetchMask = 0x01
        vic.graphicsBufferControlReg1[0] = vic.controlReg1
        vic.graphicsBufferControlReg2[0] = 0xD8
        vic.graphicsBufferMemoryPointers[0] = vic.memoryPointers
        vic.graphicsBufferBackgroundColors[0] = [0x00, 0x02, 0x03, 0x04]
        vic.graphicsBufferScreenBytes[0] = 0x01
        vic.graphicsBufferColorData[0] = 0x0F
        vic.readMemory = { address in
            switch address {
            case 0x1008: return 0x40
            default: return 0x00
            }
        }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[0x02])
        XCTAssertEqual(line[VIC.displayLeft + 1], ColorPalette.rgba[0x02])
        XCTAssertEqual(line[VIC.displayLeft + 8], ColorPalette.rgba[0x00])
        XCTAssertEqual(line[VIC.displayLeft + 9], ColorPalette.rgba[0x0F])
    }

    func testLowPhaseGraphicsBufferOnlyAppliesToMatchingPixelRow() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)

        vic.lineBuffer[0] = 0x01
        vic.colorBuffer[0] = 0x02
        vic.displayLineBufferValid = true
        vic.displayLineBufferBase = 0
        vic.graphicsBuffer[0] = 0x80
        vic.graphicsBufferValid = true
        vic.graphicsBufferBase = 0
        vic.graphicsBufferPixelRow = 1
        vic.readMemory = { address in
            switch address {
            case 0x1008: return 0x00
            default: return 0x00
            }
        }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[0])
    }

    func testCompletedBadLineBufferOnlyAppliesToMatchingMatrixBase() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)

        vic.lineBuffer[0] = 0x01
        vic.colorBuffer[0] = 0x02
        vic.displayLineBufferValid = true
        vic.displayLineBufferBase = 40
        vic.readMemory = { address in
            switch address {
            case 0x0400: return 0x03
            case 0x1018: return 0x80
            case 0x1008: return 0x80
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[7])

        line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 1,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[2])
    }

    func testLatchedMatrixRenderingUsesRowCounterForGlyphRow() {
        let vic = VIC()
        let fbY = VIC.displayTop - VIC.firstVisibleLine
        var reads: [UInt16] = []

        vic.rasterLine = UInt16(VIC.displayTop)
        vic.displayActive = true
        vic.lineBuffer[0] = 0x01
        vic.colorBuffer[0] = 0x02
        vic.displayLineBufferValid = true
        vic.displayLineBufferBase = 0
        vic.rowCounter = 3
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x100B: return 0x80
            default: return 0x00
            }
        }

        vic.renderRasterline()

        XCTAssertEqual(vic.framebuffer[fbY * VIC.screenWidth + VIC.displayLeft], ColorPalette.rgba[2])
        XCTAssertTrue(reads.contains(0x100B))
        XCTAssertFalse(reads.contains(0x1008))
        XCTAssertEqual(vic.rowCounter, 4)
    }

    func testPartiallyFetchedBadLineRowUsesRowCounterForGlyphRow() {
        let vic = VIC()
        let fbY = VIC.displayTop - VIC.firstVisibleLine
        var reads: [UInt16] = []

        vic.rasterLine = UInt16(VIC.displayTop)
        vic.displayActive = true
        vic.lineBuffer[0] = 0x01
        vic.colorBuffer[0] = 0x02
        vic.displayLineBufferBase = 0
        vic.badLineFetchMask = 0x01
        vic.rowCounter = 3
        vic.readMemory = { address in
            reads.append(address)
            switch address {
            case 0x100B: return 0x80
            default: return 0x00
            }
        }

        vic.renderRasterline()

        XCTAssertEqual(vic.framebuffer[fbY * VIC.screenWidth + VIC.displayLeft], ColorPalette.rgba[2])
        XCTAssertTrue(reads.contains(0x100B))
        XCTAssertFalse(reads.contains(0x1008))
        XCTAssertEqual(vic.rowCounter, 4)
    }

    func testRenderedDisplayLinesAdvanceAndWrapRowCounter() {
        let vic = VIC()

        vic.displayActive = true
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rowCounter = 0
        vic.renderRasterline()

        XCTAssertEqual(vic.rowCounter, 1)
        XCTAssertEqual(vic.videoCounterBase, 0)

        vic.rasterLine = UInt16(VIC.displayTop + 7)
        vic.rowCounter = 7
        vic.renderRasterline()

        XCTAssertEqual(vic.rowCounter, 0)
        XCTAssertEqual(vic.videoCounterBase, 40)
    }

    func testCompletedBadLineBufferIgnoresLaterMatrixAndColorChangesButReadsLiveGlyph() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)
        var glyph: UInt8 = 0x80

        vic.lineBuffer[0] = 0x01
        vic.colorBuffer[0] = 0x02
        vic.displayLineBufferValid = true
        vic.readMemory = { address in
            switch address {
            case 0x0400: return 0x03
            case 0x1008: return glyph
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0x07 }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[2])

        glyph = 0x00
        line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[0])
    }

    func testIncompleteBadLineBufferFallsBackToLiveScreenAndColorRAM() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)
        var screenReads: [UInt16] = []
        var colorReads: [UInt16] = []

        vic.lineBuffer[0] = 0x01
        vic.colorBuffer[0] = 0x02
        vic.displayLineBufferValid = false
        vic.readMemory = { address in
            screenReads.append(address)
            switch address {
            case 0x0400: return 0x03
            case 0x1018: return 0x80
            default: return 0x00
            }
        }
        vic.readColorRAM = { address in
            colorReads.append(address)
            return 0x07
        }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[7])
        XCTAssertTrue(screenReads.contains(0x0400))
        XCTAssertTrue(screenReads.contains(0x1018))
        XCTAssertTrue(colorReads.contains(0x0000))
    }

    func testLiveColorRAMFallbackMasksToFourBits() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)

        vic.displayLineBufferValid = false
        vic.readMemory = { address in
            switch address {
            case 0x0400: return 0x01
            case 0x1008: return 0x80
            default: return 0x00
            }
        }
        vic.readColorRAM = { _ in 0xF2 }

        vic.renderGraphicsLine(
            &line,
            foregroundMask: &foregroundMask,
            charRow: 0,
            pixelRow: 0,
            leftBorder: VIC.displayLeft,
            rightBorder: VIC.displayRight
        )

        XCTAssertEqual(line[VIC.displayLeft], ColorPalette.rgba[2])
    }

    func testDisplayDisabledKeepsBadLineBusSignalsHigh() {
        let vic = VIC()
        vic.rasterLine = UInt16(VIC.displayTop)
        vic.rasterCycle = 0
        vic.writeRegister(0x11, value: 0x0B)

        for _ in 0..<56 {
            XCTAssertFalse(vic.badLine)
            XCTAssertFalse(vic.baLineLow)
            XCTAssertFalse(vic.aecLineLow)
            XCTAssertEqual(vic.busOwner, .cpu)
            XCTAssertEqual(vic.busPhase, .cpu)
            vic.tick()
        }
    }

    func testSpriteSpriteCollisionRegisterTracksAndClearsOverlaps() {
        let vic = VIC()
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)

        vic.spriteEnabled = 0x03
        vic.spriteDisplay[0] = true
        vic.spriteDisplay[1] = true
        vic.spriteX[0] = UInt16(VIC.displayLeft)
        vic.spriteX[1] = UInt16(VIC.displayLeft)
        vic.spriteColors[0] = 0x01
        vic.spriteColors[1] = 0x02
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]
        vic.spriteLineData[1] = [0x80, 0x00, 0x00]

        vic.renderSprites(&line, fbY: 0)

        XCTAssertEqual(vic.readRegister(0x1E), 0x03)
        XCTAssertEqual(vic.readRegister(0x1E), 0x00)
    }

    func testSpriteDataCollisionRegisterTracksAndClearsForegroundOverlap() {
        let vic = VIC()
        let background = ColorPalette.rgba[0]
        let foreground = ColorPalette.rgba[7]
        var line = [UInt32](repeating: background, count: VIC.screenWidth)
        line[VIC.displayLeft] = foreground

        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = UInt16(VIC.displayLeft)
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]

        vic.renderSprites(&line, fbY: 0)

        XCTAssertEqual(vic.readRegister(0x1F), 0x01)
        XCTAssertEqual(vic.readRegister(0x1F), 0x00)
    }

    func testSpriteDataCollisionUsesGraphicsMaskWhenForegroundColorMatchesBackground() {
        let vic = VIC()
        let background = ColorPalette.rgba[0]
        var line = [UInt32](repeating: background, count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)

        vic.renderStandardChar(
            line: &line,
            foregroundMask: &foregroundMask,
            xPos: VIC.displayLeft,
            pixelData: 0x80,
            colorByte: 0x00
        )

        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = UInt16(VIC.displayLeft)
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]

        vic.renderSprites(&line, fbY: 0, foregroundMask: foregroundMask)

        XCTAssertEqual(vic.readRegister(0x1F), 0x01)
    }

    func testSpriteBehindBackgroundUsesGraphicsMaskForPriority() {
        let vic = VIC()
        let background = ColorPalette.rgba[0]
        var line = [UInt32](repeating: background, count: VIC.screenWidth)
        var foregroundMask = [Bool](repeating: false, count: VIC.screenWidth)
        foregroundMask[VIC.displayLeft] = true

        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spritePriority = 0x01
        vic.spriteX[0] = UInt16(VIC.displayLeft)
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]

        vic.renderSprites(&line, fbY: 0, foregroundMask: foregroundMask)

        XCTAssertEqual(line[VIC.displayLeft], background)
        XCTAssertEqual(vic.readRegister(0x1F), 0x01)
    }

    func testEnabledSpriteSpriteCollisionRaisesAndAcknowledgesIRQ() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        vic.writeRegister(0x1A, value: 0x04)
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)

        vic.spriteEnabled = 0x03
        vic.spriteDisplay[0] = true
        vic.spriteDisplay[1] = true
        vic.spriteX[0] = UInt16(VIC.displayLeft)
        vic.spriteX[1] = UInt16(VIC.displayLeft)
        vic.spriteColors[0] = 0x01
        vic.spriteColors[1] = 0x02
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]
        vic.spriteLineData[1] = [0x80, 0x00, 0x00]

        vic.renderSprites(&line, fbY: 0)

        XCTAssertEqual(vic.readRegister(0x19), 0xF4)
        XCTAssertEqual(irqStates, [true])

        vic.writeRegister(0x19, value: 0x04)

        XCTAssertEqual(vic.readRegister(0x19), 0x70)
        XCTAssertEqual(irqStates, [true, false])
    }

    func testWideSpriteCollisionRaisesIRQOnceWhilePending() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        vic.writeRegister(0x1A, value: 0x04)
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)

        vic.spriteEnabled = 0x03
        vic.spriteDisplay[0] = true
        vic.spriteDisplay[1] = true
        vic.spriteExpandX = 0x03
        vic.spriteX[0] = UInt16(VIC.displayLeft)
        vic.spriteX[1] = UInt16(VIC.displayLeft)
        vic.spriteColors[0] = 0x01
        vic.spriteColors[1] = 0x02
        vic.spriteLineData[0] = [0xC0, 0x00, 0x00]
        vic.spriteLineData[1] = [0xC0, 0x00, 0x00]

        vic.renderSprites(&line, fbY: 0)

        XCTAssertEqual(vic.readRegister(0x19), 0xF4)
        XCTAssertEqual(irqStates, [true])
    }

    func testEnabledSpriteDataCollisionRaisesAndAcknowledgesIRQ() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        vic.writeRegister(0x1A, value: 0x02)
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        line[VIC.displayLeft] = ColorPalette.rgba[7]

        vic.spriteEnabled = 0x01
        vic.spriteDisplay[0] = true
        vic.spriteX[0] = UInt16(VIC.displayLeft)
        vic.spriteColors[0] = 0x01
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]

        vic.renderSprites(&line, fbY: 0)

        XCTAssertEqual(vic.readRegister(0x19), 0xF2)
        XCTAssertEqual(irqStates, [true])

        vic.writeRegister(0x19, value: 0x02)

        XCTAssertEqual(vic.readRegister(0x19), 0x70)
        XCTAssertEqual(irqStates, [true, false])
    }

    func testEnablingPendingInterruptRaisesIRQOnceAndDisablingDeasserts() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)

        vic.spriteEnabled = 0x03
        vic.spriteDisplay[0] = true
        vic.spriteDisplay[1] = true
        vic.spriteX[0] = UInt16(VIC.displayLeft)
        vic.spriteX[1] = UInt16(VIC.displayLeft)
        vic.spriteColors[0] = 0x01
        vic.spriteColors[1] = 0x02
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]
        vic.spriteLineData[1] = [0x80, 0x00, 0x00]

        vic.renderSprites(&line, fbY: 0)

        XCTAssertEqual(vic.readRegister(0x19), 0x74)
        XCTAssertEqual(irqStates, [])

        vic.writeRegister(0x1A, value: 0x04)
        vic.writeRegister(0x1A, value: 0x04)

        XCTAssertEqual(vic.readRegister(0x19), 0xF4)
        XCTAssertEqual(irqStates, [true])

        vic.writeRegister(0x1A, value: 0x00)

        XCTAssertEqual(vic.readRegister(0x19), 0x74)
        XCTAssertEqual(irqStates, [true, false])
    }

    func testRasterInterruptRaisesAndAcknowledgesIRQ() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        vic.rasterLine = UInt16(vic.rasterLinesPerFrame - 1)

        vic.writeRegister(0x12, value: 0x00)
        vic.writeRegister(0x1A, value: 0x01)
        vic.endOfLine()

        XCTAssertEqual(vic.readRegister(0x19), 0xF1)
        XCTAssertEqual(irqStates, [true])

        vic.writeRegister(0x19, value: 0x01)

        XCTAssertEqual(vic.readRegister(0x19), 0x70)
        XCTAssertEqual(irqStates, [true, false])
    }

    func testAcknowledgingOnePendingInterruptKeepsIRQAssertedForOtherEnabledSource() {
        let vic = VIC()
        var irqStates: [Bool] = []
        vic.onIRQ = { irqStates.append($0) }
        var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
        vic.rasterLine = UInt16(vic.rasterLinesPerFrame - 1)

        vic.writeRegister(0x1A, value: 0x05)
        vic.endOfLine()

        vic.spriteEnabled = 0x03
        vic.spriteDisplay[0] = true
        vic.spriteDisplay[1] = true
        vic.spriteX[0] = UInt16(VIC.displayLeft)
        vic.spriteX[1] = UInt16(VIC.displayLeft)
        vic.spriteColors[0] = 0x01
        vic.spriteColors[1] = 0x02
        vic.spriteLineData[0] = [0x80, 0x00, 0x00]
        vic.spriteLineData[1] = [0x80, 0x00, 0x00]
        vic.renderSprites(&line, fbY: 0)

        XCTAssertEqual(vic.readRegister(0x19), 0xF5)
        XCTAssertEqual(irqStates, [true])

        vic.writeRegister(0x19, value: 0x01)

        XCTAssertEqual(vic.readRegister(0x19), 0xF4)
        XCTAssertEqual(irqStates, [true])

        vic.writeRegister(0x19, value: 0x04)

        XCTAssertEqual(vic.readRegister(0x19), 0x70)
        XCTAssertEqual(irqStates, [true, false])
    }
}
