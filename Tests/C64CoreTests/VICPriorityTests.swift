import XCTest
@testable import C64Core

final class VICPriorityTests: XCTestCase {
    private let standards: [C64VideoStandard] = [.pal, .ntsc]

    private func makeVIC(_ standard: C64VideoStandard = .pal, line: Int = VIC.displayTop) -> VIC {
        let vic = VIC()
        vic.videoStandard = standard
        vic.rasterLine = UInt16(line)
        vic.badLineDENLatched = true
        vic.displayActive = true
        vic.verticalBorderActive = line < VIC.displayTop || line >= VIC.displayBottom
        vic.verticalBorderClosePending = line < VIC.displayTop || line >= VIC.displayBottom
        vic.borderColor = 2
        vic.backgroundColor[0] = 0
        vic.readMemory = { address in
            if (0x0400..<0x07E8).contains(address) { return 1 }
            if (0x1008..<0x1010).contains(address) { return 0xFF }
            return 0
        }
        vic.readColorRAM = { _ in 7 }
        return vic
    }

    private func sprite(_ vic: VIC, _ index: Int, x: Int, color: UInt8 = 1) {
        // These composition fixtures begin with an already loaded display row.
        vic.spriteDisplay[index] = true
        vic.spriteX[index] = UInt16(x)
        vic.spriteColors[index] = color
        vic.seedSpriteRow(index, bytes: [0xFF, 0xFF, 0xFF])
    }

    private func render(_ vic: VIC, traced: Bool) -> [UInt32] {
        let line = vic.rasterLine
        if traced {
            for _ in 0..<vic.rasterCyclesPerLine { vic.tick() }
        } else {
            vic.renderRasterline()
        }
        let start = (Int(line) - VIC.firstVisibleLine) * VIC.screenWidth
        return Array(vic.framebuffer[start..<start + VIC.screenWidth])
    }

    func testClosedBordersHideSpritesInBothCompositionPaths() {
        for standard in standards {
            for traced in [false, true] {
                for line in [VIC.firstVisibleLine, VIC.displayTop, VIC.displayBottom] {
                    let vic = makeVIC(standard, line: line)
                    sprite(vic, 0, x: 10)
                    sprite(vic, 1, x: 340)
                    let pixels = render(vic, traced: traced)
                    XCTAssertEqual(pixels[10], ColorPalette.rgba[2])
                    XCTAssertEqual(pixels[344], ColorPalette.rgba[2])
                    XCTAssertEqual(pixels[24], ColorPalette.rgba[line == VIC.displayTop ? 1 : 2])
                    XCTAssertEqual(pixels[343], ColorPalette.rgba[line == VIC.displayTop ? 1 : 2])
                }
            }
        }
    }

    func testSpriteCollisionsStillLatchInsideClosedTopAndBottomBorders() {
        for standard in standards {
            for traced in [false, true] {
                for line in [VIC.firstVisibleLine, VIC.displayBottom] {
                    let vic = makeVIC(standard, line: line)
                    sprite(vic, 0, x: 100)
                    sprite(vic, 1, x: 100)
                    vic.writeRegister(0x1A, value: 6)
                    let pixels = render(vic, traced: traced)
                    XCTAssertEqual(pixels[100], ColorPalette.rgba[2])
                    XCTAssertEqual(vic.readRegister(0x1E), 3)
                    XCTAssertEqual(vic.readRegister(0x1F), 0)
                    XCTAssertEqual(vic.readRegister(0x19) & 6, 4)
                }
            }
        }
    }

    func testSideBorderMasksPixelsButNotGraphicsCollisions() {
        for standard in standards {
            for traced in [false, true] {
                let vic = makeVIC(standard)
                vic.writeRegister(0x16, value: 0)
                sprite(vic, 0, x: 24)
                sprite(vic, 1, x: 334)
                vic.spritePriority = 3
                let pixels = render(vic, traced: traced)
                XCTAssertEqual(pixels[24], ColorPalette.rgba[2])
                XCTAssertEqual(pixels[31], ColorPalette.rgba[7])
                XCTAssertEqual(pixels[334], ColorPalette.rgba[7])
                XCTAssertEqual(pixels[335], ColorPalette.rgba[2])
                XCTAssertEqual(vic.readRegister(0x1F), 3)
            }
        }
    }

    func testHigherPrioritySpriteBehindForegroundStillOccludesLowerSprites() {
        for standard in standards {
            for traced in [false, true] {
                for high in 0..<7 {
                    let vic = makeVIC(standard)
                    sprite(vic, high, x: 100, color: 1)
                    sprite(vic, high + 1, x: 100, color: 3)
                    vic.spritePriority = UInt8(1 << high)
                    let pixels = render(vic, traced: traced)
                    XCTAssertEqual(pixels[100], ColorPalette.rgba[7])
                    let mask = UInt8(3 << high)
                    XCTAssertEqual(vic.readRegister(0x1E), mask)
                    XCTAssertEqual(vic.readRegister(0x1F), mask)
                }
            }
        }
    }

    func testTransparentHigherPrioritySpriteDoesNotOccludeLowerSprite() {
        for traced in [false, true] {
            let vic = makeVIC()
            sprite(vic, 0, x: 100)
            sprite(vic, 1, x: 100, color: 3)
            vic.spritePriority = 1
            vic.seedSpriteRow(0, bytes: [0x7F, 0xFF, 0xFF])
            let pixels = render(vic, traced: traced)
            XCTAssertEqual(pixels[100], ColorPalette.rgba[3])
            XCTAssertEqual(pixels[101], ColorPalette.rgba[7])
        }
    }

    func testCollisionIRQAcknowledgeDoesNotRearmUnreadCollisionLatch() {
        for flag: UInt8 in [2, 4] {
            let vic = makeVIC()
            sprite(vic, 0, x: 100)
            if flag == 4 { sprite(vic, 1, x: 100) }
            vic.writeRegister(0x1A, value: flag)
            var edges: [Bool] = []
            vic.onIRQ = { edges.append($0) }
            vic.prepareRasterTraceForCurrentLine()
            // Full cycles, stopping in the middle of the overlapping pixels.
            while vic.rasterCycle < 27 { vic.tick() }
            XCTAssertEqual(vic.readRegister(0x19) & flag, flag)
            vic.writeRegister(0x19, value: flag)
            vic.tick()
            XCTAssertEqual(vic.readRegister(0x19) & flag, 0)
            XCTAssertEqual(edges, [true, false])
            let collisionRegister: UInt16 = flag == 4 ? 0x1E : 0x1F
            XCTAssertNotEqual(vic.readRegister(collisionRegister), 0)
            vic.tick()
            XCTAssertEqual(vic.readRegister(0x19) & flag, flag)
            XCTAssertEqual(edges, [true, false, true])
        }
    }

    func testFallbackCollisionIRQAlsoRequiresReadingCollisionRegisterToRearm() {
        for flag: UInt8 in [2, 4] {
            let vic = makeVIC()
            sprite(vic, 0, x: 100)
            if flag == 4 { sprite(vic, 1, x: 100) }
            vic.writeRegister(0x1A, value: flag)
            _ = render(vic, traced: false)
            vic.writeRegister(0x19, value: flag)
            _ = render(vic, traced: false)
            XCTAssertEqual(vic.readRegister(0x19) & flag, 0)
            _ = vic.readRegister(flag == 4 ? 0x1E : 0x1F)
            _ = render(vic, traced: false)
            XCTAssertEqual(vic.readRegister(0x19) & flag, flag)
        }
    }

    func testOpenedBorderCarriesIntoFollowingRasterline() {
        for standard in standards {
            let vic = makeVIC(standard, line: VIC.firstVisibleLine)
            vic.displayActive = false
            vic.verticalBorderActive = false
            vic.verticalBorderClosePending = false
            vic.horizontalBorderActive = false
            sprite(vic, 0, x: 0)
            let pixels = render(vic, traced: true)
            XCTAssertEqual(pixels[0], ColorPalette.rgba[1])
            XCTAssertEqual(pixels[23], ColorPalette.rgba[1])
        }
    }

    func testMissedRightComparisonLeavesLeftBorderOpenOnNextLine() {
        for standard in standards {
            let vic = makeVIC(standard)
            // Change CSEL between the two right-edge comparisons.
            while vic.rasterCycle < 56 { vic.tick() }
            vic.writeRegister(0x16, value: 0)
            let firstLine = vic.rasterLine
            while vic.rasterLine == firstLine { vic.tick() }
            XCTAssertFalse(vic.horizontalBorderActive)
            vic.writeRegister(0x16, value: 8)
            sprite(vic, 0, x: 0)
            let pixels = render(vic, traced: true)
            XCTAssertEqual(pixels[0], ColorPalette.rgba[1])
            XCTAssertEqual(pixels[23], ColorPalette.rgba[1])
            XCTAssertEqual(pixels[344], ColorPalette.rgba[2])
        }
    }

    func testCPUObservesCollisionIRQRearmingBehindClosedBorder() {
        for standard in standards {
            let c64 = C64()
            c64.machineProfile = standard == .pal ? .palC64 : .ntscC64
            c64.trueDriveEmulationMode = .off
            let vic = c64.vic
            vic.recordsBusAccessTraces = false
            vic.writeRegister(0x20, value: 2)
            vic.writeRegister(0x1A, value: 4)
            vic.writeRegister(0x15, value: 3)
            for index in 0..<2 {
                vic.writeRegister(UInt16(index * 2), value: 100)
                vic.writeRegister(UInt16(index * 2 + 1), value: 20)
                vic.writeRegister(UInt16(0x27 + index), value: 1)
                c64.memory.ram[0x07F8 + index] = 0x80
            }
            for address in 0x2000..<0x2040 { c64.memory.ram[address] = 0xFF }
            var program: [UInt8] = [
                0x78, // SEI; observe the pending bits without entering a handler.
                0xAD, 0x12, 0xD0, 0xC9, 22, 0xD0, 0xF9,
                0xAD, 0x19, 0xD0, 0x8D, 0x00, 0x02,
                0xA9, 4, 0x8D, 0x19, 0xD0,
                0xAD, 0x12, 0xD0, 0xC9, 24, 0xD0, 0xF9,
                0xAD, 0x19, 0xD0, 0x8D, 0x01, 0x02,
                0xAD, 0x1E, 0xD0, 0x8D, 0x02, 0x02,
                0xAD, 0x12, 0xD0, 0xC9, 26, 0xD0, 0xF9,
                0xAD, 0x19, 0xD0, 0x8D, 0x03, 0x02
            ]
            let finished = UInt16(0x0600 + program.count)
            program.append(contentsOf: [0x4C, UInt8(truncatingIfNeeded: finished), UInt8(finished >> 8)])
            for (index, byte) in program.enumerated() { c64.memory.ram[0x0600 + index] = byte }
            c64.cpu.pc = 0x0600
            for _ in 0..<(28 * vic.rasterCyclesPerLine) { c64.tickOneCycle() }
            XCTAssertFalse(c64.cpu.jammed)
            XCTAssertTrue((finished...finished + 2).contains(c64.cpu.pc))
            XCTAssertEqual(c64.memory.ram[0x0200] & 4, 4)
            XCTAssertEqual(c64.memory.ram[0x0201] & 4, 0)
            XCTAssertEqual(c64.memory.ram[0x0202], 3)
            XCTAssertEqual(c64.memory.ram[0x0203] & 4, 4)
            for line in 21..<28 {
                let offset = (line - VIC.firstVisibleLine) * VIC.screenWidth
                XCTAssertEqual(vic.framebuffer[offset + 100], ColorPalette.rgba[2])
                XCTAssertEqual(vic.framebuffer[offset + 123], ColorPalette.rgba[2])
            }
        }
    }

    func testClearingDENMidDisplayDoesNotImmediatelyCloseTheBorder() {
        for standard in standards {
            let vic = makeVIC(standard)
            while vic.rasterCycle < 20 { vic.tick() }
            vic.writeRegister(0x11, value: vic.controlReg1 & ~0x10)
            let line = vic.rasterLine
            while vic.rasterLine == line { vic.tick() }
            let start = (Int(line) - VIC.firstVisibleLine) * VIC.screenWidth
            XCTAssertEqual(vic.framebuffer[start + 200], ColorPalette.rgba[7])
            XCTAssertEqual(vic.framebuffer[start + 344], ColorPalette.rgba[2])
        }
    }

    func testDENClearedBeforeTopComparisonKeepsBorderClosed() {
        for standard in standards {
            let vic = makeVIC(standard)
            vic.verticalBorderActive = true
            vic.verticalBorderClosePending = true
            vic.writeRegister(0x11, value: vic.controlReg1 & ~0x10)
            let pixels = render(vic, traced: true)
            XCTAssertTrue(vic.verticalBorderActive)
            XCTAssertEqual(pixels[100], ColorPalette.rgba[2])
        }
    }

    func testBorderComparatorsKeepClockingOutsideFramebufferCrop() {
        for standard in standards {
            for narrow in [false, true] {
                let vic = makeVIC(standard, line: 0)
                vic.horizontalBorderActive = false
                vic.controlReg2 = narrow ? 0 : 8
                for _ in 0..<vic.rasterCyclesPerLine { vic.tick() }
                XCTAssertTrue(vic.horizontalBorderActive)
                XCTAssertTrue(vic.verticalBorderActive)
                XCTAssertFalse(vic.rasterTraceHasSamples)
                XCTAssertFalse(vic.rasterTraceHasGraphicsOutput)
            }
        }
    }

    func testVerticalBorderSuppressesGraphicsWithoutImmediatelyMaskingSprites() {
        for standard in standards {
            let vic = makeVIC(standard, line: VIC.firstVisibleLine)
            vic.horizontalBorderActive = false
            sprite(vic, 0, x: 100)
            let pixels = render(vic, traced: true)
            XCTAssertEqual(pixels[100], ColorPalette.rgba[1])
            XCTAssertEqual(pixels[99], ColorPalette.rgba[0])
            XCTAssertEqual(pixels[344], ColorPalette.rgba[2])
            XCTAssertEqual(vic.readRegister(0x1F), 0)
        }
    }
}
