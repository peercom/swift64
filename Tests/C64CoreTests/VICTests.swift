import XCTest
@testable import C64Core

final class VICTests: XCTestCase {
    func testEndOfLineRendersLastVisibleRasterline() {
        let vic = VIC()
        let borderColor = ColorPalette.rgba[2]
        let fbY = VIC.lastVisibleLine - VIC.firstVisibleLine

        vic.rasterLine = UInt16(VIC.lastVisibleLine)
        vic.borderColor = 0x02

        vic.endOfLine()

        XCTAssertEqual(vic.framebuffer[fbY * VIC.screenWidth], borderColor)
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
        vic.rasterCycle = 0
        vic.spriteEnabled = 0x01
        vic.spriteY[0] = 0
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

        XCTAssertTrue(vic.spriteDisplay[0])
        XCTAssertEqual(vic.spriteLineData[0], [0xAA, 0xBB, 0xCC])
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
