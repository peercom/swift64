import XCTest
@testable import C64Core

final class VICSpriteDMALifecycleTests: XCTestCase {
    private let standards: [C64VideoStandard] = [.pal, .ntsc]

    private func expectedOffsets(expanded: Bool) -> [UInt16] {
        var result: [UInt16] = []
        for row in 0..<21 {
            for _ in 0..<(expanded ? 2 : 1) {
                for byte in 0..<3 { result.append(UInt16(row * 3 + byte)) }
            }
        }
        return result
    }

    private func advance(_ vic: VIC, toLine line: Int, cycle: Int) {
        for _ in 0..<(vic.rasterLinesPerFrame * vic.rasterCyclesPerLine) {
            if vic.rasterLine == UInt16(line) && vic.rasterCycle == cycle { return }
            vic.tick()
        }
        XCTFail("VIC did not reach line \(line), cycle \(cycle)")
    }

    func testAllEightSpritesFetchExactly21RowsOr42ExpandedRows() {
        for standard in standards {
            for expanded in [false, true] {
                let vic = VIC()
                vic.videoStandard = standard
                vic.writeRegister(0x11, value: 0)
                vic.writeRegister(0x15, value: 0xFF)
                vic.writeRegister(0x17, value: expanded ? 0xFF : 0)
                vic.spriteY = [UInt8](repeating: 50, count: 8)
                var fetched = [[UInt16]](repeating: [], count: 8)
                vic.readMemory = { address in
                    if (0x07F8...0x07FF).contains(address) {
                        return UInt8(0x20 + address - 0x07F8)
                    }
                    if (0x0800..<0x0A00).contains(address) {
                        fetched[Int(address - 0x0800) / 64].append(address & 63)
                    }
                    return 0xFF
                }
                advance(vic, toLine: 94, cycle: 0)
                let expected = expectedOffsets(expanded: expanded)
                for sprite in 0..<8 {
                    XCTAssertEqual(fetched[sprite], expected, "\(standard) expanded=\(expanded) sprite=\(sprite)")
                    XCTAssertFalse(vic.spriteDisplay[sprite])
                }
            }
        }
    }

    func testPreparingNextYAndClearingEnableDoesNotTruncateActiveDMA() {
        for standard in standards {
            let vic = VIC()
            vic.videoStandard = standard
            vic.writeRegister(0x11, value: 0)
            vic.writeRegister(0x15, value: 1)
            vic.spriteY[0] = 50
            var fetched: [UInt16] = []
            vic.readMemory = { address in
                if address == 0x07F8 { return 0x20 }
                if (0x0800..<0x0840).contains(address) { fetched.append(address & 63) }
                return 0xFF
            }
            advance(vic, toLine: 51, cycle: 20)
            vic.writeRegister(1, value: 180)
            vic.writeRegister(0x15, value: 0)
            advance(vic, toLine: 72, cycle: 0)
            XCTAssertEqual(fetched, Array(UInt16(0)...62), "\(standard)")
            XCTAssertFalse(vic.spriteDisplay[0])
        }
    }

    func testMatchingYAgainDuringDMADoesNotRestartTheCounter() {
        let vic = VIC()
        vic.writeRegister(0x15, value: 1)
        vic.spriteY[0] = 50
        vic.readMemory = { $0 == 0x07F8 ? 0x20 : 0xFF }
        for row in 0..<5 {
            advance(vic, toLine: 50 + row, cycle: 54)
            vic.writeRegister(1, value: UInt8(50 + row))
            advance(vic, toLine: 50 + row, cycle: 59)
            XCTAssertEqual(vic.spriteLastFetchedByteOffset[0], row * 3)
        }
    }

    func testEnableMustStillBeSetAtDisplayStartWithoutCancellingDMA() {
        for standard in standards {
            for sprite in 0..<8 {
                let vic = VIC()
                vic.videoStandard = standard
                let mask = UInt8(1 << sprite)
                vic.spriteY[sprite] = 50
                vic.writeRegister(0x15, value: mask)
                advance(vic, toLine: 50, cycle: vic.spriteDMAFirstStartCycle - 1)
                XCTAssertTrue(vic.spriteDMAEligible(sprite))
                vic.beginCycle()
                vic.writeRegister(0x15, value: 0)
                vic.endCycle()
                vic.tick()
                XCTAssertFalse(vic.spriteDisplay[sprite], "\(standard) sprite=\(sprite)")
                XCTAssertTrue(vic.spriteDMAEligible(sprite))
                // Re-enabling after the display comparison cannot start this row.
                vic.writeRegister(0x15, value: mask)
                vic.tick()
                XCTAssertFalse(vic.spriteDisplay[sprite])
            }
        }
    }

    func testExpandedSpriteCanStretchPastItsNominalHeight() {
        let vic = VIC()
        vic.writeRegister(0x15, value: 1)
        vic.writeRegister(0x17, value: 1)
        vic.spriteY[0] = 50
        vic.readMemory = { $0 == 0x07F8 ? 0x20 : 0xFF }
        for line in 51...105 {
            advance(vic, toLine: line, cycle: 16)
            vic.writeRegister(0x17, value: 0)
            vic.writeRegister(0x17, value: 1)
            advance(vic, toLine: line, cycle: 59)
            XCTAssertEqual(vic.spriteMCBase[0], 0)
            XCTAssertEqual(vic.spriteLastFetchedByteOffset[0], 0)
            XCTAssertTrue(vic.spriteDisplay[0])
        }
        advance(vic, toLine: 149, cycle: 0)
        XCTAssertFalse(vic.spriteDisplay[0])
    }

    func testActiveDMAContinuesAcrossTheVideoFrameBoundary() {
        for standard in standards {
            let vic = VIC()
            vic.videoStandard = standard
            vic.writeRegister(0x11, value: 0)
            vic.writeRegister(0x15, value: 0xFF)
            vic.writeRegister(0x17, value: 0xFF)
            // PAL's second low-eight-bit Y match is near the frame end.
            let start = standard == .pal ? 300 : 250
            vic.spriteY = [UInt8](repeating: UInt8(truncatingIfNeeded: start), count: 8)
            vic.rasterLine = UInt16(start)
            var fetched = [[UInt16]](repeating: [], count: 8)
            vic.readMemory = { address in
                if (0x07F8...0x07FF).contains(address) { return UInt8(0x20 + address - 0x07F8) }
                if (0x0800..<0x0A00).contains(address) {
                    fetched[Int(address - 0x0800) / 64].append(address & 63)
                }
                return 0xFF
            }
            for _ in 0..<(44 * vic.rasterCyclesPerLine) { vic.tick() }
            let expected = expectedOffsets(expanded: true)
            for sprite in 0..<8 {
                XCTAssertEqual(fetched[sprite], expected, "\(standard) sprite=\(sprite)")
            }
        }
    }

    func testLowEightBitYCompareRepeatsOnlyWhereTheVideoFrameReachesIt() {
        for standard in standards {
            let vic = VIC()
            vic.videoStandard = standard
            vic.writeRegister(0x11, value: 0)
            vic.writeRegister(0x15, value: 1)
            vic.spriteY[0] = 7
            var fetched: [UInt16] = []
            vic.readMemory = { address in
                if address == 0x07F8 { return 0x20 }
                if (0x0800..<0x0840).contains(address) { fetched.append(address & 63) }
                return 0xFF
            }
            for _ in 0..<(vic.rasterLinesPerFrame * vic.rasterCyclesPerLine) { vic.tick() }
            var expected = expectedOffsets(expanded: false)
            if standard == .pal { expected += expectedOffsets(expanded: false) }
            XCTAssertEqual(fetched, expected, "\(standard)")
        }
    }

    func testEnabledSpritesDoNotFetchDataBeforeTheYCompare() {
        let vic = VIC()
        vic.writeRegister(0x15, value: 0xFF)
        vic.spriteY = [UInt8](repeating: 100, count: 8)
        advance(vic, toLine: 100, cycle: 54)
        XCTAssertEqual(vic.spriteDMACheckMask, 0)
        XCTAssertEqual(vic.spriteLastFetchedByteOffset, [Int](repeating: -1, count: 8))
        vic.tick()
        XCTAssertEqual(vic.spriteDMACheckMask, 0xFF)
    }

    func testCPUExpansionWritesRespectBothSidesOfTheCounterTransfer() {
        // CPU writes are phi2; only cycle 15 (index 14) crunches the base
        // transfer in cycle 16 phi1. A later clear must still set the FF.
        for (writeCycle, expectedBase) in [(13, 9), (14, 5), (15, 6), (16, 6)] {
            let c64 = C64()
            let vic = c64.vic
            vic.rasterLine = 100
            vic.rasterCycle = writeCycle - 3
            vic.spriteDMACheckMask = 3
            vic.spriteExpandY = 3
            for sprite in 0..<2 {
                vic.spriteYExpFF[sprite] = false
                vic.spriteMCBase[sprite] = 6
                vic.spriteMC[sprite] = 9
            }
            c64.cpu.pc = 0x0600
            c64.cpu.a = 2
            c64.memory.ram[0x0600] = 0x8D // STA $D017
            c64.memory.ram[0x0601] = 0x17
            c64.memory.ram[0x0602] = 0xD0
            for _ in 0..<4 { c64.tickOneCycle() }
            while vic.rasterCycle <= 15 { vic.tick() }
            XCTAssertTrue(vic.spriteYExpFF[0], "writeCycle=\(writeCycle)")
            XCTAssertFalse(vic.spriteYExpFF[1])
            XCTAssertEqual(vic.spriteMCBase[0], expectedBase, "writeCycle=\(writeCycle)")
            XCTAssertEqual(vic.spriteMCBase[1], 6)
            XCTAssertEqual(vic.spriteMC[0], 9, "MC is reloaded only at cycle 58")
        }
    }

    func testCrunchedBaseSelectsTheNextFetchedBytes() {
        let vic = VIC()
        vic.rasterLine = 100
        vic.rasterCycle = 14
        vic.spriteDMACheckMask = 1
        vic.spriteExpandY = 1
        vic.spriteYExpFF[0] = false
        vic.spriteMCBase[0] = 6
        vic.spriteMC[0] = 9
        vic.readMemory = { $0 == 0x07F8 ? 0x20 : UInt8(truncatingIfNeeded: $0) }
        vic.beginCycle()
        vic.writeRegister(0x17, value: 0)
        vic.endCycle()
        XCTAssertEqual(vic.spriteMCBase[0], 6)
        advance(vic, toLine: 100, cycle: 59)
        XCTAssertEqual(vic.spriteLastFetchedByteOffset[0], 5)
        XCTAssertEqual(vic.spriteLineData[0], [5, 6, 7])
    }

    func testCPUExpansionSetAtToggleCycleCannotRetroactivelyRepeatTheRow() {
        for standard in standards {
            let toggleCycle = standard == .pal ? 55 : 56
            for writeCycle in (toggleCycle - 1)...(toggleCycle + 1) {
                let c64 = C64(machineProfile: standard == .pal ? .palC64 : .ntscC64)
                let vic = c64.vic
                vic.rasterLine = 100
                vic.rasterCycle = writeCycle - 3
                vic.spriteDMACheckMask = 8
                vic.spriteMC[3] = 3
                vic.spriteMCBase[3] = 0
                c64.memory.ram[0x07FB] = 0x20
                c64.cpu.pc = 0x0600
                c64.cpu.a = 8
                c64.memory.ram[0x0600] = 0x8D // STA $D017
                c64.memory.ram[0x0601] = 0x17
                c64.memory.ram[0x0602] = 0xD0
                for _ in 0..<4 { c64.tickOneCycle() }
                advance(vic, toLine: 101, cycle: 16)
                XCTAssertEqual(vic.spriteMCBase[3], writeCycle < toggleCycle ? 0 : 3,
                               "\(standard) writeCycle=\(writeCycle)")
            }
        }
    }

    func testFinalRowDisplayEndsAtDisplayLatchNotAtDMAStop() {
        let vic = VIC()
        vic.writeRegister(0x15, value: 1)
        vic.spriteY[0] = 50
        vic.readMemory = { $0 == 0x07F8 ? 0x20 : 0xFF }
        advance(vic, toLine: 71, cycle: 15)
        XCTAssertTrue(vic.spriteDMAEligible(0))
        XCTAssertTrue(vic.spriteDisplay[0])
        vic.tick()
        XCTAssertFalse(vic.spriteDMAEligible(0))
        XCTAssertTrue(vic.spriteDisplay[0])
        advance(vic, toLine: 71, cycle: 57)
        vic.tick()
        XCTAssertFalse(vic.spriteDisplay[0])
    }

    func testMultiplexerRestartsCompletedSpriteWithNewYAndPointer() {
        let vic = VIC()
        vic.writeRegister(0x15, value: 1)
        vic.spriteY[0] = 50
        var pointer: UInt8 = 0x20
        vic.readMemory = { $0 == 0x07F8 ? pointer : UInt8(truncatingIfNeeded: $0) }
        advance(vic, toLine: 72, cycle: 0)
        XCTAssertFalse(vic.spriteDMAEligible(0))
        vic.writeRegister(1, value: 80)
        pointer = 0x30
        advance(vic, toLine: 80, cycle: 54)
        XCTAssertFalse(vic.spriteDMAEligible(0))
        advance(vic, toLine: 80, cycle: 59)
        XCTAssertTrue(vic.spriteDMAEligible(0))
        XCTAssertTrue(vic.spriteDisplay[0])
        XCTAssertEqual(vic.spriteLastFetchedByteOffset[0], 0)
        XCTAssertEqual(vic.spritePointers[0], 0x30)
        XCTAssertEqual(vic.lastHighPhaseMemoryReads, [0x0C02])
    }

    func testCPUDrivenMultiplexerPreservesBothVisibleSprites() {
        for standard in standards {
            for expanded in [false, true] {
                let c64 = C64()
                c64.machineProfile = standard == .pal ? .palC64 : .ntscC64
                c64.trueDriveEmulationMode = .off
                let vic = c64.vic
                vic.recordsBusAccessTraces = false
                vic.writeRegister(0, value: 100)
                vic.writeRegister(1, value: 60)
                vic.writeRegister(0x15, value: 1)
                vic.writeRegister(0x17, value: expanded ? 1 : 0)
                vic.writeRegister(0x27, value: 2)
                c64.memory.ram[0x07F8] = 0x80
                for address in 0x2000..<0x2040 { c64.memory.ram[address] = 0xFF }
                // Second image has a distinct 8-pixel-wide shape.
                for byte in 0..<63 { c64.memory.ram[0x2040 + byte] = byte % 3 == 0 ? 0xFF : 0 }
                let nextY = expanded ? 140 : 100
                let changePointerY = expanded ? 105 : 85
                let program: [UInt8] = [
                    0xAD, 0x12, 0xD0, 0xC9, 61, 0xD0, 0xF9, // wait for first visible row
                    0xA9, UInt8(nextY), 0x8D, 0x01, 0xD0,   // prepare next Y early
                    0xA9, 0, 0x8D, 0x15, 0xD0,             // clear enable during active DMA
                    0xAD, 0x12, 0xD0, 0xC9, UInt8(changePointerY), 0xD0, 0xF9,
                    0xA9, 0x81, 0x8D, 0xF8, 0x07,          // next image
                    0xA9, 5, 0x8D, 0x27, 0xD0,             // next color
                    0xA9, 1, 0x8D, 0x15, 0xD0,             // arm the next Y comparison
                    0x4C, 0x27, 0x06
                ]
                for (index, byte) in program.enumerated() { c64.memory.ram[0x0600 + index] = byte }
                c64.cpu.pc = 0x0600
                let height = expanded ? 42 : 21
                for _ in 0..<((nextY + height + 3) * vic.rasterCyclesPerLine) { c64.tickOneCycle() }
                XCTAssertFalse(c64.cpu.jammed)
                XCTAssertEqual(vic.spriteY[0], UInt8(nextY))
                XCTAssertEqual(vic.spritePointers[0], 0x81)
                for row in 0..<height {
                    let first = (61 + row - VIC.firstVisibleLine) * VIC.screenWidth
                    let second = (nextY + 1 + row - VIC.firstVisibleLine) * VIC.screenWidth
                    XCTAssertEqual(vic.framebuffer[first + 100], ColorPalette.rgba[2], "\(standard) expanded=\(expanded) row=\(row)")
                    XCTAssertEqual(vic.framebuffer[first + 123], ColorPalette.rgba[2])
                    XCTAssertEqual(vic.framebuffer[second + 100], ColorPalette.rgba[5])
                    XCTAssertEqual(vic.framebuffer[second + 107], ColorPalette.rgba[5])
                    XCTAssertNotEqual(vic.framebuffer[second + 108], ColorPalette.rgba[5])
                }
                for line in [60, 61 + height, nextY, nextY + height + 1] {
                    let pixel = vic.framebuffer[(line - VIC.firstVisibleLine) * VIC.screenWidth + 100]
                    XCTAssertNotEqual(pixel, ColorPalette.rgba[2])
                    XCTAssertNotEqual(pixel, ColorPalette.rgba[5])
                }
            }
        }
    }
}
