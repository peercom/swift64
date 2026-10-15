import XCTest
@testable import C64Core

final class VICGraphicsSequencerTests: XCTestCase {
    private let standards: [C64VideoStandard] = [.pal, .ntsc]

    private func machine(_ standard: C64VideoStandard) -> VIC {
        let vic = VIC()
        vic.videoStandard = standard
        vic.memoryPointers = 0x18
        vic.readMemory = { address in
            if (0x0400..<0x0800).contains(address) { return UInt8(truncatingIfNeeded: address) }
            return 0x80
        }
        vic.readColorRAM = { _ in 7 }
        return vic
    }

    private func advance(_ vic: VIC, line: Int, cycle: Int = 0) {
        let target = line * vic.rasterCyclesPerLine + cycle
        let current = Int(vic.rasterLine) * vic.rasterCyclesPerLine + vic.rasterCycle
        precondition(target >= current)
        for _ in current..<target { vic.tick() }
    }

    func testCPUPhaseBadLineWriteStartsMatrixDMAOnFollowingCycle() {
        for standard in standards {
            let vic = machine(standard)
            advance(vic, line: 52, cycle: 51)
            let original = vic.lineBuffer
            vic.beginCycle()
            vic.writeRegister(0x11, value: 0x1C)
            vic.endCycle()
            XCTAssertFalse(vic.badLine)
            XCTAssertEqual(vic.lineBuffer, original)
            XCTAssertTrue(vic.lastHighPhaseMemoryReads.isEmpty)
            vic.beginCycle()
            XCTAssertTrue(vic.badLine)
            XCTAssertEqual(vic.badLineStartCycle, 52)
            vic.endCycle()
            XCTAssertEqual(vic.lineBuffer[38], 0xFF)
            XCTAssertEqual(vic.lineBuffer[37], original[37])
        }
    }

    func testLastCycleYScrollWriteUsesNextRasterLineForBadLineCondition() {
        for standard in standards {
            for lastCycle in [false, true] {
                let vic = machine(standard)
                advance(vic, line: 48, cycle: vic.rasterCyclesPerLine - (lastCycle ? 1 : 2))
                XCTAssertFalse(vic.displayActive)
                vic.beginCycle()
                vic.writeRegister(0x11, value: 0x10)
                vic.endCycle()
                vic.beginCycle()
                XCTAssertEqual(vic.displayActive, !lastCycle)
                XCTAssertEqual(vic.badLine, !lastCycle)
                vic.endCycle()
            }
        }
    }

    func testRowResetAndVideoCounterReloadOccurInCycleFourteen() {
        for standard in standards {
            let vic = machine(standard)
            advance(vic, line: 51)
            vic.rowCounter = 5
            vic.videoCounter = 123
            advance(vic, line: 51, cycle: 13)
            XCTAssertTrue(vic.displayActive)
            XCTAssertEqual(vic.rowCounter, 5)
            XCTAssertEqual(vic.videoCounter, 123)
            vic.beginCycle()
            XCTAssertEqual(vic.rowCounter, 0)
            XCTAssertEqual(vic.videoCounter, 0)
            vic.endCycle()
        }
    }

    func testNormalRowsAdvanceAtCycleFiftyEightNotDuringRendering() {
        for standard in standards {
            let vic = machine(standard)
            for line in 51...66 {
                advance(vic, line: line, cycle: 55)
                let row = (line - 51) & 7
                let base = ((line - 51) / 8) * 40
                XCTAssertEqual(vic.rowCounter, row)
                XCTAssertEqual(vic.videoCounter, base + 40)
                XCTAssertEqual(vic.videoCounterBase, base)
                vic.renderRasterline()
                XCTAssertEqual(vic.rowCounter, row)
                XCTAssertEqual(vic.videoCounterBase, base)
                advance(vic, line: line, cycle: 57)
                vic.beginCycle()
                XCTAssertEqual(vic.rowCounter, row == 7 ? 7 : row + 1)
                XCTAssertEqual(vic.displayActive, row != 7)
                XCTAssertEqual(vic.videoCounterBase, base + (row == 7 ? 40 : 0))
                vic.endCycle()
            }
        }
    }

    func testFLDDelaysFirstMatrixRowWithoutSkippingScreenMemory() {
        for standard in standards {
            let vic = machine(standard)
            for line in 0..<80 {
                vic.writeRegister(0x11, value: 0x18 | UInt8((line + 1) & 7))
                advance(vic, line: line + 1)
            }
            XCTAssertEqual(vic.videoCounterBase, 0)
            XCTAssertFalse(vic.displayActive)
            vic.writeRegister(0x11, value: 0x18)
            for row in 0..<8 {
                advance(vic, line: 80 + row, cycle: 15)
                vic.beginCycle()
                XCTAssertEqual(vic.lastLowPhaseMemoryReads, [UInt16(0x2000 + row)])
                XCTAssertEqual(vic.graphicsBufferScreenBytes[0], 0)
                XCTAssertEqual(vic.videoCounter, 1)
                vic.endCycle()
                let base = (80 + row - VIC.firstVisibleLine) * VIC.screenWidth
                advance(vic, line: 81 + row)
                XCTAssertEqual(vic.framebuffer[base + 24], ColorPalette.rgba[7])
                XCTAssertEqual(vic.framebuffer[base + 25], ColorPalette.rgba[0])
            }
            XCTAssertEqual(vic.videoCounterBase, 40)
        }
    }

    func testFLIChangesMatrixEveryLineButKeepsBitmapRowProgression() {
        for standard in standards {
            let vic = machine(standard)
            vic.readMemory = { address in
                if address < 0x0400 { return 0x80 }
                return UInt8(((Int(address) / 0x400) & 7) << 4) | 2
            }
            advance(vic, line: 51)
            vic.writeRegister(0x11, value: 0x3B)
            for line in 51...66 {
                let matrix = ((line - 51) & 7) + 1
                vic.writeRegister(0x18, value: UInt8(matrix << 4))
                if line > 51 {
                    vic.writeRegister(0x11, value: 0x38 | UInt8((line + 1) & 7))
                    advance(vic, line: line, cycle: 13)
                    vic.beginCycle()
                    // CPU phi2 write after the RC-reset comparison: the usual FLI sequence.
                    vic.writeRegister(0x11, value: 0x38 | UInt8(line & 7))
                    vic.endCycle()
                }
                advance(vic, line: line, cycle: 23)
                let row = (line - 51) & 7
                let base = ((line - 51) / 8) * 40
                vic.beginCycle()
                XCTAssertEqual(vic.rowCounter, row)
                XCTAssertEqual(vic.lastLowPhaseMemoryReads, [UInt16((base + 8) * 8 + row)])
                XCTAssertEqual(vic.graphicsBufferScreenBytes[8], UInt8((matrix & 7) << 4) | 2)
                vic.endCycle()
                XCTAssertEqual(vic.lastHighPhaseMemoryReads, [UInt16(matrix * 0x400 + base + 9)])
                advance(vic, line: line + 1)
                let offset = (line - VIC.firstVisibleLine) * VIC.screenWidth + 24 + 8 * 8
                XCTAssertEqual(vic.framebuffer[offset], ColorPalette.rgba[matrix & 7])
                XCTAssertEqual(vic.framebuffer[offset + 1], ColorPalette.rgba[2])
            }
            XCTAssertEqual(vic.videoCounterBase, 80)
        }
    }

    func testLinecrunchUsesTenBitCountersAndDoesNotReadNewMatrixData() {
        for standard in standards {
            let vic = machine(standard)
            advance(vic, line: 59)
            XCTAssertEqual(vic.rowCounter, 7)
            XCTAssertEqual(vic.videoCounterBase, 40)
            for line in 59..<85 {
                vic.writeRegister(0x11, value: 0x18 | UInt8(line & 7))
                XCTAssertTrue(vic.displayActive)
                vic.writeRegister(0x11, value: 0x18 | UInt8((line + 1) & 7))
                advance(vic, line: line, cycle: 14)
                for _ in 14..<55 {
                    vic.tick()
                    XCTAssertTrue(vic.lastHighPhaseMemoryReads.isEmpty)
                }
                advance(vic, line: line + 1)
                XCTAssertEqual(vic.rowCounter, 7)
                XCTAssertFalse(vic.displayActive)
                XCTAssertEqual(vic.videoCounterBase, ((line - 57) * 40) & 0x3FF)
            }
        }
    }

    func testLateBadLineConditionKeepsDisplayActiveWithoutMatrixDMA() {
        for standard in standards {
            let vic = machine(standard)
            advance(vic, line: 58, cycle: 54)
            XCTAssertEqual(vic.rowCounter, 7)
            vic.beginCycle()
            vic.writeRegister(0x11, value: 0x1A)
            vic.endCycle()
            XCTAssertFalse(vic.badLine)
            vic.tick()
            XCTAssertTrue(vic.badLine)
            XCTAssertFalse(vic.baLineLow)
            advance(vic, line: 59, cycle: 15)
            XCTAssertTrue(vic.displayActive)
            XCTAssertEqual(vic.rowCounter, 0)
            XCTAssertEqual(vic.videoCounterBase, 40)
            vic.beginCycle()
            XCTAssertEqual(vic.graphicsBufferScreenBytes[0], 0)
            XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x2000])
            vic.endCycle()
        }
    }

    func testClosedBorderAndDENClearDoNotStopGraphicsCounters() {
        for standard in standards {
            let vic = machine(standard)
            vic.writeRegister(0x11, value: 0x19)
            advance(vic, line: 49, cycle: 15)
            XCTAssertTrue(vic.verticalBorderActive)
            vic.writeRegister(0x11, value: 0x09)
            advance(vic, line: 50)
            XCTAssertEqual(vic.rowCounter, 1)
            XCTAssertEqual(vic.videoCounter, 40)
            XCTAssertTrue(vic.displayActive)
        }
    }

    func testIdleGraphicsFetchesDoNotReadMatrixOrAdvanceVideoCounter() {
        for standard in standards {
            for ecm in [false, true] {
                let vic = machine(standard)
                vic.writeRegister(0x11, value: ecm ? 0x40 : 0)
                advance(vic, line: 20, cycle: 15)
                for column in 0..<40 {
                    vic.beginCycle()
                    XCTAssertEqual(vic.lastLowPhaseMemoryReads, [ecm ? 0x39FF : 0x3FFF])
                    XCTAssertEqual(vic.graphicsBufferScreenBytes[column], 0)
                    XCTAssertEqual(vic.graphicsBufferColorData[column], 0)
                    XCTAssertEqual(vic.videoCounter, 0)
                    vic.endCycle()
                }
            }
        }
    }

    func testIdleTextPixelsAppearWhenTheVerticalBorderIsOpen() {
        for standard in standards {
            let vic = machine(standard)
            vic.backgroundColor[0] = 5
            for line in 0...60 {
                vic.writeRegister(0x11, value: 0x18 | UInt8((line + 1) & 7))
                advance(vic, line: line + 1)
            }
            let offset = (60 - VIC.firstVisibleLine) * VIC.screenWidth + 24
            XCTAssertFalse(vic.displayActive)
            XCTAssertEqual(vic.framebuffer[offset], ColorPalette.rgba[0])
            XCTAssertEqual(vic.framebuffer[offset + 1], ColorPalette.rgba[5])
        }
    }

    func testScreenBaseWriteOnNonBadLineDoesNotRereadTheMatrix() {
        for standard in standards {
            let vic = machine(standard)
            advance(vic, line: 52, cycle: 15)
            vic.writeRegister(0x18, value: 0x28)
            for column in 0..<40 {
                vic.beginCycle()
                XCTAssertEqual(vic.lastLowPhaseMemoryReads, [UInt16(0x2001 + column * 8)])
                XCTAssertEqual(vic.graphicsBufferScreenBytes[column], UInt8(column))
                vic.endCycle()
                XCTAssertTrue(vic.lastHighPhaseMemoryReads.isEmpty)
            }
        }
    }

    func testCompleteTextFrameFetchesOneThousandCellsAndAllEightGlyphRows() {
        for standard in standards {
            let vic = machine(standard)
            var matrixAddresses: [UInt16] = []
            var colorAddresses: [UInt16] = []
            vic.readMemory = { address in
                if (0x0400..<0x07E8).contains(address) {
                    matrixAddresses.append(address)
                    return UInt8(address & 1)
                }
                if (0x2000..<0x2010).contains(address) {
                    let row = Int(address & 7)
                    return address & 8 == 0 ? 0x80 >> row : 1 << row
                }
                return 0
            }
            vic.readColorRAM = { address in
                colorAddresses.append(address)
                return UInt8((Int(address) / 40) % 15 + 1)
            }
            for _ in 0..<vic.activeCyclesPerFrame { vic.tick() }
            XCTAssertEqual(matrixAddresses, (0..<1000).map { UInt16(0x0400 + $0) })
            XCTAssertEqual(colorAddresses, (0..<1000).map { UInt16($0) })
            for y in 0..<200 {
                let color = ColorPalette.rgba[(y / 8) % 15 + 1]
                let expected = (0..<320).map { x in
                    let lit = (x / 8) & 1 == 0 ? (x & 7) == (y & 7) : (x & 7) == 7 - (y & 7)
                    return lit ? color : ColorPalette.rgba[0]
                }
                let offset = (51 + y - VIC.firstVisibleLine) * VIC.screenWidth + 24
                XCTAssertEqual(Array(vic.framebuffer[offset..<offset + 320]), expected, "\(standard) row=\(y)")
            }
            XCTAssertEqual(vic.videoCounterBase, 0)
            XCTAssertEqual(vic.rowCounter, 7)
            XCTAssertFalse(vic.displayActive)
        }
    }

    func testDelayedDMAStartsAtBufferZeroAndLeavesANonAlignedVideoBase() {
        for standard in standards {
            let vic = machine(standard)
            advance(vic, line: 59)
            vic.writeRegister(0x11, value: 0x18)
            advance(vic, line: 60, cycle: 20)
            XCTAssertFalse(vic.displayActive)
            XCTAssertEqual(vic.videoCounter, 40)
            vic.beginCycle()
            vic.writeRegister(0x11, value: 0x1C)
            vic.endCycle()
            vic.tick()
            XCTAssertEqual(vic.badLineFetchMask, 1)
            XCTAssertEqual(vic.lineBuffer[0], 0xFF)
            XCTAssertEqual(vic.videoMatrixLineIndex, 0)
            for cycle in 22..<55 {
                vic.beginCycle()
                XCTAssertEqual(vic.videoMatrixLineIndex, cycle - 21)
                XCTAssertEqual(vic.videoCounter, 40 + cycle - 21)
                vic.endCycle()
                if (24..<54).contains(cycle) {
                    XCTAssertEqual(vic.lastHighPhaseMemoryReads, [UInt16(0x0428 + cycle - 21)])
                }
            }
            advance(vic, line: 61)
            XCTAssertEqual(vic.videoCounterBase, 73)
            vic.writeRegister(0x11, value: 0x1D)
            advance(vic, line: 61, cycle: 14)
            vic.tick()
            XCTAssertEqual(vic.lastHighPhaseMemoryReads, [0x0449])
            XCTAssertEqual(vic.lastHighPhaseColorRAMReads, [73])
        }
    }

    func testStartedMatrixDMAFinishesAfterBadLineConditionIsRemoved() {
        for standard in standards {
            let vic = machine(standard)
            advance(vic, line: 51, cycle: 16)
            vic.writeRegister(0x11, value: 0x1C)
            XCTAssertFalse(vic.badLine)
            for column in 2..<40 {
                vic.beginCycle()
                XCTAssertTrue(vic.baLineLow)
                XCTAssertTrue(vic.aecLineLow)
                vic.endCycle()
                XCTAssertEqual(vic.lastHighPhaseMemoryReads, [UInt16(0x0400 + column)])
            }
            XCTAssertFalse(vic.baLineLow)
            XCTAssertTrue(vic.displayLineBufferValid)
            XCTAssertEqual(vic.lineBuffer, (0..<40).map { UInt8($0) })
        }
    }

    func testCPUFLIStoresBeforeAndAfterTheRowResetComparison() {
        for standard in standards {
            for writeCycle in [12, 13, 14] {
                let c64 = C64()
                c64.machineProfile = standard == .pal ? .palC64 : .ntscC64
                c64.trueDriveEmulationMode = .off
                let vic = c64.vic
                vic.writeRegister(0x11, value: 0x3B)
                vic.writeRegister(0x18, value: 0x10)
                for address in 0x20..<0x0400 { c64.memory.ram[address] = 0x80 }
                for address in 0x0400..<0x0800 { c64.memory.ram[address] = 0x72 }
                c64.memory.ram[0x0200] = 0
                let program: [UInt8] = [
                    0xA9, 0x3C,       // LDA #$3C
                    0x8D, 0x11, 0xD0, // STA $D011: start a bad line on raster 52.
                    0xEE, 0x00, 0x02, // INC $0200 after the CPU regains the bus.
                    0x4C, 0x08, 0xC0
                ]
                for (index, byte) in program.enumerated() { c64.memory.ram[0xC000 + index] = byte }
                advance(vic, line: 52, cycle: writeCycle - 5)
                c64.cpu.pc = 0xC000
                while vic.rasterCycle <= writeCycle { c64.tickOneCycle() }
                XCTAssertEqual(vic.controlReg1, 0x3C)
                while vic.rasterCycle < 55 { c64.tickOneCycle() }
                XCTAssertEqual(vic.graphicsBufferPixelRow, writeCycle < 13 ? 0 : 1)
                XCTAssertEqual(vic.videoCounter, 40)
                XCTAssertEqual(vic.videoCounterBase, 0)
                while vic.rasterLine == 52 { c64.tickOneCycle() }
                XCTAssertEqual(c64.memory.ram[0x0200], 1)
                XCTAssertFalse(c64.cpu.jammed)
            }
        }
    }

    func testBitmapAddressesUseAllTenCounterBitsAndECMAddressMask() {
        for standard in standards {
            for ecm in [false, true] {
                for vc in [0, 63, 64, 127, 128, 255, 512, 1023] {
                    let vic = machine(standard)
                    vic.rasterLine = 100
                    vic.rasterCycle = 15
                    vic.displayActive = true
                    vic.controlReg1 = ecm ? 0x7B : 0x3B
                    vic.memoryPointers = 0x18
                    vic.videoCounter = vc
                    vic.videoCounterBase = vc
                    vic.rowCounter = 6
                    vic.performLowPhaseAccess()
                    let raw = 0x2000 | vc << 3 | 6
                    XCTAssertEqual(vic.lastLowPhaseMemoryReads, [UInt16(ecm ? raw & 0x39FF : raw)])
                    XCTAssertEqual(vic.videoCounter, (vc + 1) & 0x3FF)
                }
            }
        }
    }
}
