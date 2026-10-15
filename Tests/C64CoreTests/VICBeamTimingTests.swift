import XCTest
@testable import C64Core

final class VICBeamTimingTests: XCTestCase {
    private let standards: [C64VideoStandard] = [.pal, .ntsc]

    func testRasterColorStepsFollowEightDotsPerCycle() {
        for standard in standards {
            let vic = VIC()
            vic.videoStandard = standard
            vic.rasterLine = UInt16(VIC.firstVisibleLine)
            for cycle in 0..<vic.rasterCyclesPerLine {
                vic.writeRegister(0x20, value: UInt8(cycle % 15 + 1))
                vic.tick()
            }
            // Both chips wrap to X=0 in the second half of hardware cycle 13.
            for x in 0..<380 {
                let expectedCycle = (x + 100) / 8
                XCTAssertEqual(vic.framebuffer[x], ColorPalette.rgba[expectedCycle % 15 + 1], "\(standard) x=\(x)")
            }
        }
    }

    func testBeginningOfRasterlineDoesNotPaintTheLeftEdge() {
        for standard in standards {
            let vic = VIC()
            vic.videoStandard = standard
            vic.rasterLine = UInt16(VIC.firstVisibleLine)
            for _ in 0..<12 { vic.tick() }
            XCTAssertFalse(vic.rasterTraceValid[0])
            vic.tick()
            XCTAssertTrue(vic.rasterTraceValid[0])
            XCTAssertTrue(vic.rasterTraceValid[3])
            XCTAssertFalse(vic.rasterTraceValid[4])
        }
    }

    func testLightPenUsesDocumentedEndOfCycleCoordinates() {
        for standard in standards {
            // Hardware cycles, not zero-based indices. Bauer's cycle-20 example is $3c.
            var samples = [(1, standard == .pal ? 412 : 420), (13, 4), (16, 28), (20, 60), (55, 340), (56, 348)]
            samples += standard == .pal ? [(63, 404)] : [(61, 388), (62, 396), (63, 396), (64, 404), (65, 412)]
            for (cycle, x) in samples {
                let vic = VIC()
                vic.videoStandard = standard
                vic.rasterLine = 100
                vic.rasterCycle = cycle - 1
                vic.triggerLightPenAtCurrentBeam()
                XCTAssertEqual(vic.readRegister(0x13), UInt8(x >> 1), "\(standard) cycle=\(cycle)")
                XCTAssertEqual(vic.readRegister(0x14), 100)
            }
        }
    }

    func testBadLineBusPhasesMatchHardwareCyclesTwelveThroughFiftyFour() {
        for standard in standards {
            let vic = VIC()
            vic.videoStandard = standard
            vic.rasterLine = 51
            vic.badLineDENLatched = true
            for cycle in 0..<vic.rasterCyclesPerLine {
                vic.beginCycle()
                XCTAssertEqual(vic.baLineLow, (11..<54).contains(cycle), "\(standard) cycle=\(cycle + 1)")
                XCTAssertEqual(vic.aecLineLow, (14..<54).contains(cycle))
                if (14..<54).contains(cycle) {
                    XCTAssertEqual(vic.busPhase, .badLineCharacterFetch(column: cycle - 14))
                }
                vic.endCycle()
            }
        }
    }

    func testMatrixByteIsLatchedBeforeCorrespondingGlyphFetch() {
        for standard in standards {
            let vic = VIC()
            vic.videoStandard = standard
            vic.rasterLine = 51
            vic.badLineDENLatched = true
            vic.displayActive = true
            vic.memoryPointers = 0x18
            vic.readMemory = { address in
                if (0x0400..<0x0428).contains(address) { return UInt8(address - 0x0400 + 1) }
                return 0x80
            }
            vic.readColorRAM = { _ in 7 }
            for cycle in 0..<vic.rasterCyclesPerLine {
                vic.beginCycle()
                if (15..<55).contains(cycle) {
                    let column = cycle - 15
                    XCTAssertEqual(vic.graphicsBufferScreenBytes[column], UInt8(column + 1))
                    XCTAssertEqual(vic.lastLowPhaseMemoryReads, [UInt16(0x2000 + (column + 1) * 8)])
                }
                vic.endCycle()
                if (14..<54).contains(cycle) {
                    XCTAssertEqual(vic.lastHighPhaseMemoryReads, [UInt16(0x0400 + cycle - 14)])
                }
            }
            let base = (51 - VIC.firstVisibleLine) * VIC.screenWidth
            for column in 0..<40 {
                XCTAssertEqual(vic.framebuffer[base + 24 + column * 8], ColorPalette.rgba[7])
                XCTAssertEqual(vic.framebuffer[base + 25 + column * 8], ColorPalette.rgba[0])
            }
        }
    }

    private func machine(_ standard: C64VideoStandard, line: Int) -> C64 {
        let c64 = C64()
        c64.machineProfile = standard == .pal ? .palC64 : .ntscC64
        c64.trueDriveEmulationMode = .off
        c64.vic.rasterLine = UInt16(line)
        c64.vic.recordsBusAccessTraces = false
        c64.vic.borderColor = 2
        c64.vic.backgroundColor[0] = 1
        return c64
    }

    private func store(_ c64: C64, register: UInt8, value: UInt8, atCycle cycle: Int) {
        while c64.vic.rasterCycle < cycle - 3 { c64.vic.tick() }
        c64.cpu.pc = 0x0600
        c64.cpu.a = value
        for (index, byte) in [UInt8(0x8D), register, 0xD0, 0x4C, 0x03, 0x06].enumerated() {
            c64.memory.ram[0x0600 + index] = byte
        }
        for _ in 0..<4 { c64.tickOneCycle() }
        let line = c64.vic.rasterLine
        while c64.vic.rasterLine == line { c64.tickOneCycle() }
        XCTAssertFalse(c64.cpu.jammed)
    }

    func testCPUColorStoreReachesTheColorOutputStageWithinTheCycle() {
        for standard in standards {
            for cycle in [19, 30, 44] {
                let c64 = machine(standard, line: VIC.firstVisibleLine)
                store(c64, register: 0x20, value: 5, atCycle: cycle)
                // The color mux is eleven dots later than the old whole-cycle
                // data sample. Public sprite/color splits independently verify it.
                let split = cycle * 8 - 103
                XCTAssertEqual(c64.vic.framebuffer[split - 1], ColorPalette.rgba[2])
                XCTAssertEqual(c64.vic.framebuffer[split], ColorPalette.rgba[5])
                XCTAssertEqual(c64.vic.framebuffer[split + 7], ColorPalette.rgba[5])
            }
        }
    }

    func testCPUColumnSelectWriteOnlyOpensRightBorderInsideComparisonWindow() {
        for standard in standards {
            for cycle in [54, 55, 56] {
                let c64 = machine(standard, line: 100)
                c64.vic.displayActive = true
                c64.vic.verticalBorderActive = false
                c64.vic.verticalBorderClosePending = false
                store(c64, register: 0x16, value: 0, atCycle: cycle)
                let base = (100 - VIC.firstVisibleLine) * VIC.screenWidth
                XCTAssertEqual(c64.vic.framebuffer[base + 360], ColorPalette.rgba[cycle == 55 ? 1 : 2], "\(standard) write=\(cycle)")
            }
        }
    }

    func testCPUColumnSelectWriteOnlyMissesLeftBorderInsideComparisonWindow() {
        for standard in standards {
            for cycle in [15, 16, 17] {
                let c64 = machine(standard, line: 100)
                c64.vic.displayActive = true
                c64.vic.verticalBorderActive = false
                c64.vic.verticalBorderClosePending = false
                c64.vic.controlReg2 = 0
                store(c64, register: 0x16, value: 8, atCycle: cycle)
                let base = (100 - VIC.firstVisibleLine) * VIC.screenWidth
                XCTAssertEqual(c64.vic.framebuffer[base + 100], ColorPalette.rgba[cycle == 16 ? 2 : 1], "\(standard) write=\(cycle)")
            }
        }
    }

    func testSpriteCollisionDoesNotPrecedeItsPhysicalXPosition() {
        for standard in standards {
            let vic = VIC()
            vic.videoStandard = standard
            vic.rasterLine = 100
            for sprite in 0..<2 {
                vic.spriteDisplay[sprite] = true
                vic.spriteX[sprite] = 100
                vic.seedSpriteRow(sprite, bytes: [0xFF, 0xFF, 0xFF])
            }
            for _ in 0..<25 { vic.tick() }
            XCTAssertEqual(vic.readRegister(0x1E), 0)
            vic.tick()
            XCTAssertEqual(vic.readRegister(0x1E), 0)
            vic.tick()
            XCTAssertEqual(vic.readRegister(0x1E), 3)
        }
    }

    func testLateBadLineUsesOnlyTheRemainingThreeCycleBAWarning() {
        for standard in standards {
            for start in 11...21 {
                let vic = VIC()
                vic.videoStandard = standard
                vic.rasterLine = 51
                vic.badLineDENLatched = true
                vic.controlReg1 = 0x18
                vic.readMemory = { _ in 0x42 }
                vic.readColorRAM = { _ in 7 }
                while vic.rasterCycle < start { vic.tick() }
                while vic.rasterCycle < 54 {
                    let cycle = vic.rasterCycle
                    vic.beginCycle()
                    if cycle == start { vic.writeRegister(0x11, value: 0x1B) }
                    vic.endCycle()
                    guard cycle >= max(14, start + 1) else {
                        XCTAssertTrue(vic.lastHighPhaseMemoryReads.isEmpty)
                        continue
                    }
                    let column = cycle - max(14, start + 1)
                    let unstable = cycle < start + 4
                    let context = "\(standard) start=\(start) cycle=\(cycle)"
                    XCTAssertEqual(vic.lineBuffer[column], unstable ? 0xFF : 0x42, context)
                    XCTAssertEqual(vic.colorBuffer[column], unstable ? 15 : 7, context)
                    XCTAssertEqual(vic.lastHighPhaseMemoryReads,
                                   unstable ? [] : [UInt16(0x0400 + column)], context)
                }
            }
        }
    }

    func testPALSpriteCounterWrapsAt504InBothRenderingPaths() {
        for expanded in [false, true] {
            for multicolor in [false, true] {
                let vic = VIC()
                vic.rasterLine = 100
                vic.verticalBorderActive = false
                vic.verticalBorderClosePending = false
                vic.horizontalBorderActive = false
                vic.spriteDisplay[0] = true
                vic.spriteX[0] = 500
                vic.spriteColors[0] = 1
                vic.spriteMulticolor1 = 1
                vic.spriteMulticolor = multicolor ? 1 : 0
                vic.spriteExpandX = expanded ? 1 : 0
                vic.seedSpriteRow(0, bytes: [0xFF, 0xFF, 0xFF])
                let end = (expanded ? 48 : 24) - 4
                XCTAssertEqual(vic.spriteLocalX(sprite: 0, visibleX: 0), 4)
                XCTAssertNil(vic.spriteLocalX(sprite: 0, visibleX: end))
                var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
                vic.renderSprites(&line, fbY: 0)
                XCTAssertEqual(line[0], ColorPalette.rgba[1])
                XCTAssertEqual(line[end - 1], ColorPalette.rgba[1])
                XCTAssertEqual(line[end], ColorPalette.rgba[0])
                while vic.rasterLine == 100 { vic.tick() }
                let base = (100 - VIC.firstVisibleLine) * VIC.screenWidth
                XCTAssertEqual(vic.framebuffer[base], ColorPalette.rgba[1])
                XCTAssertEqual(vic.framebuffer[base + end - 1], ColorPalette.rgba[1])
                XCTAssertNotEqual(vic.framebuffer[base + end], ColorPalette.rgba[1])
            }
        }
    }

    func testPALDoesNotMatchSpritePositionsBeyondCounterMaximum() {
        for x in 504...511 {
            let vic = VIC()
            vic.rasterLine = 100
            vic.spriteDisplay[0] = true
            vic.spriteX[0] = UInt16(x)
            vic.spriteColors[0] = 1
            vic.spriteExpandX = 1
            vic.seedSpriteRow(0, bytes: [0xFF, 0xFF, 0xFF])
            var line = [UInt32](repeating: ColorPalette.rgba[0], count: VIC.screenWidth)
            vic.renderSprites(&line, fbY: 0)
            XCTAssertTrue(line.allSatisfy { $0 == ColorPalette.rgba[0] })
            XCTAssertNil(vic.spriteLocalX(sprite: 0, visibleX: 0))
            while vic.rasterCycle < 54 { vic.tick() }
            XCTAssertFalse(vic.spriteTraceHasSamples)
        }
    }
}
