import XCTest
@testable import C64Core

extension VIC {
    /// Seed a fetched row for component fixtures that bypass the DMA slots.
    func seedSpriteRow(_ sprite: Int, bytes: [UInt8]) {
        precondition(bytes.count == 3)
        spriteLineData[sprite] = bytes
        spriteShifters[sprite] = SpriteShifter(data: UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[2]))
    }
}

final class VICSpriteShifterTests: XCTestCase {
    private let standards: [C64VideoStandard] = [.pal, .ntsc]
    private let pattern: [UInt8] = [0xF0, 0xCC, 0xAA]

    private func machine(_ standard: C64VideoStandard, x: UInt16 = 100,
                         expanded: Bool = false, multicolor: Bool = false,
                         vic: VIC = VIC(), firstLine: UInt16 = 100, sprites: Int = 1) -> VIC {
        vic.videoStandard = standard
        vic.rasterLine = firstLine
        vic.verticalBorderActive = false
        vic.verticalBorderClosePending = false
        vic.horizontalBorderActive = false
        vic.spriteEnabled = UInt8((1 << sprites) - 1)
        for sprite in 0..<sprites {
            vic.spriteX[sprite] = x
            vic.spriteY[sprite] = UInt8(truncatingIfNeeded: firstLine)
            vic.spriteColors[sprite] = 1
        }
        vic.spriteMulticolor0 = 2
        vic.spriteMulticolor1 = 3
        vic.spriteExpandX = expanded ? 1 : 0
        vic.spriteMulticolor = multicolor ? 1 : 0
        let bytes = pattern
        vic.readMemory = { address in
            if (0x07F8...0x07FF).contains(address) { return 0x20 }
            if (0x0800..<0x083F).contains(address) { return bytes[Int(address - 0x0800) % 3] }
            return 0
        }
        while vic.rasterLine == firstLine { vic.tick() }
        XCTAssertEqual(vic.spriteLineData[0], bytes)
        XCTAssertTrue(vic.spriteDisplay[0])
        return vic
    }

    private func finishLine(_ vic: VIC) {
        let line = vic.rasterLine
        while vic.rasterLine == line { vic.tick() }
    }

    private func pixel(_ vic: VIC, _ x: Int, line: Int = 101) -> UInt32 {
        vic.framebuffer[(line - VIC.firstVisibleLine) * VIC.screenWidth + x]
    }

    private func expectedBit(_ offset: Int) -> UInt32 {
        let set = pattern[offset / 8] & (0x80 >> (offset % 8)) != 0
        return ColorPalette.rgba[set ? 1 : 0]
    }

    func testXWriteDuringOutputDoesNotMoveTheRemainingBitsOrReplayTheRow() {
        for standard in standards {
            let vic = machine(standard)
            while vic.rasterCycle < 26 { vic.tick() } // X=100...107 already emitted.
            vic.writeRegister(0, value: 200)
            finishLine(vic)
            for bit in 0..<24 { XCTAssertEqual(pixel(vic, 100 + bit), expectedBit(bit)) }
            for x in 200..<224 { XCTAssertEqual(pixel(vic, x), ColorPalette.rgba[0]) }
        }
    }

    func testXWriteAfterConsumptionDoesNotProduceASecondSprite() {
        for standard in standards {
            for expanded in [false, true] {
                for multicolor in [false, true] {
                    let vic = machine(standard, expanded: expanded, multicolor: multicolor)
                    while vic.rasterCycle < 32 { vic.tick() }
                    vic.writeRegister(0, value: 200)
                    finishLine(vic)
                    for x in 200..<248 { XCTAssertEqual(pixel(vic, x), ColorPalette.rgba[0]) }
                }
            }
        }
    }

    func testXWriteBeforeComparisonSelectsTheNewPosition() {
        for standard in standards {
            let vic = machine(standard)
            while vic.rasterCycle < 25 { vic.tick() }
            vic.writeRegister(0, value: 200)
            finishLine(vic)
            for x in 100..<124 { XCTAssertEqual(pixel(vic, x), ColorPalette.rgba[0]) }
            for bit in 0..<24 { XCTAssertEqual(pixel(vic, 200 + bit), expectedBit(bit)) }
        }
    }

    func testExpansionWriteSlowsOnlyBitsNotAlreadyConsumed() {
        for standard in standards {
            let vic = machine(standard)
            while vic.rasterCycle < 26 { vic.tick() }
            vic.writeRegister(0x1D, value: 1)
            finishLine(vic)
            for bit in 0..<8 { XCTAssertEqual(pixel(vic, 100 + bit), expectedBit(bit)) }
            for bit in 8..<24 {
                XCTAssertEqual(pixel(vic, 108 + (bit - 8) * 2), expectedBit(bit))
                XCTAssertEqual(pixel(vic, 109 + (bit - 8) * 2), expectedBit(bit))
            }
            XCTAssertEqual(pixel(vic, 140), ColorPalette.rgba[0])
        }
    }

    func testClearingExpansionSpeedsOnlyTheRemainingBits() {
        for standard in standards {
            let vic = machine(standard, expanded: true)
            while vic.rasterCycle < 27 { vic.tick() } // 16 dots consume eight bits.
            vic.writeRegister(0x1D, value: 0)
            finishLine(vic)
            for bit in 0..<8 {
                XCTAssertEqual(pixel(vic, 100 + bit * 2), expectedBit(bit))
                XCTAssertEqual(pixel(vic, 101 + bit * 2), expectedBit(bit))
            }
            for bit in 8..<24 { XCTAssertEqual(pixel(vic, 108 + bit), expectedBit(bit)) }
            XCTAssertEqual(pixel(vic, 132), ColorPalette.rgba[0])
        }
    }

    func testNormalAndMulticolorRowsReloadOnTheNextRasterline() {
        let monochrome = [1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0]
        let pairs = [3, 3, 0, 0, 3, 0, 3, 0, 1, 1, 1, 1]
        for standard in standards {
            for expanded in [false, true] {
                for multicolor in [false, true] {
                    let vic = machine(standard, expanded: expanded, multicolor: multicolor)
                    let colors = multicolor ? pairs : monochrome
                    let width = (multicolor ? 2 : 1) * (expanded ? 2 : 1)
                    for row in 101...102 {
                        finishLine(vic)
                        for (index, color) in colors.enumerated() {
                            for dot in 0..<width {
                                XCTAssertEqual(pixel(vic, 100 + index * width + dot, line: row), ColorPalette.rgba[color])
                            }
                        }
                        XCTAssertEqual(pixel(vic, 100 + colors.count * width, line: row), ColorPalette.rgba[0])
                    }
                }
            }
        }
    }

    func testMovingUnstartedExpandedSpriteBehindBeamDoesNotStartOutput() {
        for standard in standards {
            let vic = machine(standard, x: 200, expanded: true)
            while vic.rasterCycle < 26 { vic.tick() }
            vic.writeRegister(0, value: 80)
            finishLine(vic)
            for x in 80..<248 { XCTAssertEqual(pixel(vic, x), ColorPalette.rgba[0]) }
        }
    }

    func testEnablingExpansionAfterConsumptionDoesNotResurrectPixels() {
        for standard in standards {
            let vic = machine(standard)
            while vic.rasterCycle < 29 { vic.tick() }
            vic.writeRegister(0x1D, value: 1)
            finishLine(vic)
            for x in 124..<148 { XCTAssertEqual(pixel(vic, x), ColorPalette.rgba[0]) }
        }
    }

    func testShifterConsumesHiddenTailAcrossRasterlineBoundary() {
        for standard in standards {
            let vic = machine(standard, x: 400)
            while vic.rasterCycle < 13 { vic.tick() }
            XCTAssertEqual(vic.spriteShifters[0].data, 0)
            XCTAssertEqual(vic.spriteShifters[0].remainingBits, 0)
            vic.writeRegister(0x10, value: 0)
            vic.writeRegister(0, value: 100)
            finishLine(vic)
            for x in 100..<124 { XCTAssertEqual(pixel(vic, x), ColorPalette.rgba[0]) }
        }
    }

    func testSpriteCollisionsRunOutsideHorizontalAndVerticalFramebufferCrop() {
        for standard in standards {
            for line: UInt16 in [5, 100] {
                let vic = machine(standard, x: 450, firstLine: line, sprites: 2)
                vic.writeRegister(0x1A, value: 4)
                let firstCycle = standard == .pal ? 5 : 4
                while vic.rasterCycle < firstCycle { vic.tick() }
                XCTAssertEqual(vic.readRegister(0x1E), 0)
                vic.tick()
                XCTAssertEqual(vic.readRegister(0x1E), 0)
                vic.tick()
                XCTAssertEqual(vic.readRegister(0x1E), 0)
                vic.tick()
                XCTAssertEqual(vic.readRegister(0x1E), 3)
                XCTAssertEqual(vic.readRegister(0x19) & 0x84, 0x84)
                XCTAssertFalse(vic.spriteTraceHasSamples)
            }
        }
    }

    func testCPUStoreCannotReplayConsumedSpriteAtSecondXPosition() {
        for standard in standards {
            let c64 = C64()
            c64.machineProfile = standard == .pal ? .palC64 : .ntscC64
            c64.trueDriveEmulationMode = .off
            let vic = machine(standard, vic: c64.vic)
            while vic.rasterCycle < 28 { vic.tick() }
            c64.cpu.pc = 0x0600
            c64.cpu.a = 200
            for (offset, byte) in [UInt8(0x8D), 0x00, 0xD0, 0x4C, 0x03, 0x06].enumerated() {
                c64.memory.ram[0x0600 + offset] = byte
            }
            while vic.rasterLine == 101 { c64.tickOneCycle() }
            XCTAssertFalse(c64.cpu.jammed)
            XCTAssertEqual(vic.readRegister(0), 200)
            for bit in 0..<24 { XCTAssertEqual(pixel(vic, 100 + bit), expectedBit(bit)) }
            for x in 200..<224 { XCTAssertEqual(pixel(vic, x), ColorPalette.rgba[0]) }
        }
    }
}
