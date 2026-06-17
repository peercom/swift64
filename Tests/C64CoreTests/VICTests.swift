import XCTest
@testable import C64Core

final class VICTests: XCTestCase {
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
