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

        vic.tick()
        XCTAssertEqual(vic.rasterCycle, 60)
        XCTAssertEqual(reads, [0x07FB, 0x0080, 0x0081, 0x0082, 0x07FC])
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

        XCTAssertEqual(vic.rasterCycle, 15)
        XCTAssertEqual(vic.lowPhaseAccess, .displayData(column: 0))
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
