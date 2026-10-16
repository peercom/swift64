import XCTest
@testable import C64Core

final class VICRasterIRQEdgeTests: XCTestCase {
    private func machine(_ profile: MachineProfile, line: UInt16, compare: UInt16) -> C64 {
        let c64 = C64(machineProfile: profile)
        c64.trueDriveEmulationMode = .off
        c64.kernalTraps.enabled = false
        c64.vic.rasterLine = line
        c64.vic.writeRegister(0x11, value: UInt8((compare >> 1) & 0x80))
        c64.vic.writeRegister(0x12, value: UInt8(truncatingIfNeeded: compare))
        c64.vic.writeRegister(0x1A, value: 1)
        c64.vic.writeRegister(0x19, value: 1)
        return c64
    }

    private func store(_ c64: C64, register: UInt8, value: UInt8, atCycle cycle: Int) {
        let vic = c64.vic
        while vic.rasterCycle < cycle - 3 { vic.tick() }
        c64.cpu.pc = 0x0600
        c64.cpu.a = value
        c64.memory.ram[0x0600] = 0x8D // STA absolute; fourth clock writes.
        c64.memory.ram[0x0601] = register
        c64.memory.ram[0x0602] = 0xD0
        for _ in 0..<4 { c64.tickOneCycle() }
        XCTAssertEqual(c64.cpu.pc, 0x0603)
    }

    private func read(_ c64: C64, address: UInt16, atCycle cycle: Int) -> UInt8 {
        while c64.vic.rasterCycle < cycle - 3 { c64.vic.tick() }
        c64.cpu.pc = 0x0600
        c64.memory.ram[0x0600] = 0xAD // LDA absolute; fourth clock reads.
        c64.memory.ram[0x0601] = UInt8(truncatingIfNeeded: address)
        c64.memory.ram[0x0602] = UInt8(address >> 8)
        for _ in 0..<4 { c64.tickOneCycle() }
        XCTAssertEqual(c64.cpu.pc, 0x0603)
        return c64.cpu.a
    }

    func testFrameWrapCounterAndIRQAreOneClockLaterThanOrdinaryLines() {
        // Bauer 3.12: raster zero compares in hardware cycle 2, not 1.
        // VIC-Addendum: X wraps normally; the frame starts one clock later.
        for profile in [MachineProfile.palC64, .ntscC64] {
            let c64 = machine(profile, line: UInt16(profile.vicRasterLinesPerFrame - 1), compare: 0)
            let vic = c64.vic
            for _ in 0..<vic.rasterCyclesPerLine { vic.tick() }
            XCTAssertEqual(vic.rasterLine, 0, "Physical frame geometry must not gain a clock")
            XCTAssertEqual(vic.rasterCycle, 0)
            XCTAssertTrue(vic.frameReady)
            XCTAssertEqual(vic.readRegister(0x12), UInt8(truncatingIfNeeded: vic.rasterLinesPerFrame - 1))
            XCTAssertEqual(vic.readRegister(0x11) & 0x80, 0x80)
            XCTAssertEqual(vic.readRegister(0x19), 0x70)
            vic.tick()
            XCTAssertEqual(vic.rasterCycle, 1)
            XCTAssertEqual(vic.readRegister(0x12), 0)
            XCTAssertEqual(vic.readRegister(0x11) & 0x80, 0)
            XCTAssertEqual(vic.readRegister(0x19), 0xF1)
            vic.writeRegister(0x19, value: 1)
            vic.tick()
            XCTAssertEqual(vic.readRegister(0x19), 0x70, "Acknowledgement must not retrigger a held match")
        }
    }

    func testCPUReadsCounterHighBitAndIRQAcrossFrameWrapIncludingMirrors() {
        for profile in [MachineProfile.palC64, .ntscC64] {
            for offset in [0, 1, 2] {
                for address: UInt16 in [0xD011, 0xD051, 0xD012, 0xD3D2, 0xD019, 0xD059] {
                    let c64 = machine(profile, line: UInt16(profile.vicRasterLinesPerFrame - 1), compare: 0)
                    let lastLine = c64.vic.rasterLinesPerFrame - 1
                    let beforeReset = offset == 0
                    let expected: UInt8
                    switch address & 63 {
                    case 0x11: expected = beforeReset ? 0x80 : 0
                    case 0x12: expected = beforeReset ? UInt8(truncatingIfNeeded: lastLine) : 0
                    default: expected = beforeReset ? 0x70 : 0xF1
                    }
                    XCTAssertEqual(read(c64, address: address, atCycle: c64.vic.rasterCyclesPerLine + offset),
                                   expected, "\(profile.name) \(String(format: "%04X", address)) offset=\(offset)")
                }
            }
        }
    }

    func testAcknowledgingBeforeAndAfterLineZeroEdgeDoesNotLoseOrRepeatIRQ() {
        for profile in [MachineProfile.palC64, .ntscC64] {
            for offset in [0, 1] {
                let c64 = machine(profile, line: UInt16(profile.vicRasterLinesPerFrame - 1), compare: 0)
                store(c64, register: 0x19, value: 1, atCycle: c64.vic.rasterCyclesPerLine + offset)
                XCTAssertEqual(c64.vic.readRegister(0x19), offset == 0 ? 0xF1 : 0x70)
            }
        }
    }

    func testFirstClockCompareWritesMeetIncomingZeroRatherThanOldLastLine() {
        for profile in [MachineProfile.palC64, .ntscC64] {
            let lastLine = UInt16(profile.vicRasterLinesPerFrame - 1)
            let c64 = machine(profile, line: lastLine, compare: 0x100)
            store(c64, register: 0x11, value: 0, atCycle: c64.vic.rasterCyclesPerLine)
            XCTAssertEqual(c64.vic.readRegister(0x19), 0xF1)

            let departing = machine(profile, line: lastLine, compare: 0x100)
            store(departing, register: 0x12, value: UInt8(truncatingIfNeeded: lastLine),
                  atCycle: departing.vic.rasterCyclesPerLine)
            XCTAssertEqual(departing.vic.readRegister(0x19), 0x70)
        }
    }

    func testDelayedFrameStateResetsTogetherAndCannotSurviveChipReset() {
        for profile in [MachineProfile.palC64, .ntscC64] {
            let c64 = machine(profile, line: UInt16(profile.vicRasterLinesPerFrame - 1), compare: 1)
            let vic = c64.vic
            vic.rasterCycle = vic.rasterCyclesPerLine - 1
            vic.refreshCounter = 17
            vic.videoCounterBase = 120
            vic.badLineDENLatched = true
            vic.triggerLightPen(x: 100, y: 40)
            vic.tick()
            XCTAssertEqual(vic.refreshCounter, 17)
            XCTAssertEqual(vic.videoCounterBase, 120)
            XCTAssertTrue(vic.badLineDENLatched)
            XCTAssertTrue(vic.lightPenLatchedThisFrame)
            vic.tick()
            XCTAssertEqual(vic.refreshCounter, 0xFF)
            XCTAssertEqual(vic.videoCounterBase, 0)
            XCTAssertFalse(vic.badLineDENLatched)
            XCTAssertFalse(vic.lightPenLatchedThisFrame)

            vic.rasterLine = UInt16(vic.rasterLinesPerFrame - 1)
            vic.rasterCycle = vic.rasterCyclesPerLine - 1
            vic.tick()
            vic.reset()
            XCTAssertEqual(vic.readRegister(0x12), 0)
            vic.tick()
            XCTAssertEqual(vic.readRegister(0x19), 0x70, "Reset must discard the pending frame edge")
        }
    }

    func testMaskedLineZeroIRQStillLatchesAndPhysicalFrameDurationStaysConstant() {
        for profile in [MachineProfile.palC64, .ntscC64] {
            let c64 = machine(profile, line: UInt16(profile.vicRasterLinesPerFrame - 1), compare: 0)
            let vic = c64.vic
            vic.recordsBusAccessTraces = false
            vic.writeRegister(0x1A, value: 0)
            for _ in 0..<vic.rasterCyclesPerLine { vic.tick() }
            XCTAssertEqual(vic.readRegister(0x19), 0x70)
            XCTAssertFalse(c64.cpu.irqLine)
            vic.tick()
            XCTAssertEqual(vic.readRegister(0x19), 0x71)
            XCTAssertFalse(c64.cpu.irqLine)
            vic.writeRegister(0x1A, value: 1)
            XCTAssertTrue(c64.cpu.irqLine)
            vic.writeRegister(0x19, value: 1)
            XCTAssertFalse(c64.cpu.irqLine)

            vic.reset()
            for _ in 0..<3 {
                vic.frameReady = false
                for _ in 0..<vic.activeCyclesPerFrame - 1 { vic.tick() }
                XCTAssertFalse(vic.frameReady)
                vic.tick()
                XCTAssertTrue(vic.frameReady)
                XCTAssertEqual(vic.rasterCycle, 0)
                XCTAssertEqual(vic.rasterLine, 0)
            }
        }
    }

    func testFollowingRasterAtBoundaryHoldsIRQButAdjacentWritesDoNot() {
        for profile in [MachineProfile.palC64, .ntscC64] {
            for offset in [-1, 0, 1] {
                let c64 = machine(profile, line: 100, compare: 100)
                let vic = c64.vic
                var irqStates: [Bool] = []
                vic.onIRQ = { irqStates.append($0) }
                store(c64, register: 0x12, value: 101, atCycle: vic.rasterCyclesPerLine - 1 + offset)
                while vic.rasterLine == 100 { vic.tick() }
                XCTAssertEqual(vic.rasterLine, 101)
                XCTAssertEqual(vic.readRegister(0x19), offset == 0 ? 0x70 : 0xF1,
                               "\(profile.name) offset=\(offset)")
                XCTAssertEqual(irqStates, offset == 0 ? [] : [true])
            }
        }
    }

    func testBoundaryWriteStillRaisesIRQWhenComparatorWasNotMatched() {
        for profile in [MachineProfile.palC64, .ntscC64] {
            let c64 = machine(profile, line: 100, compare: 99)
            store(c64, register: 0x12, value: 101, atCycle: c64.vic.rasterCyclesPerLine - 1)
            XCTAssertEqual(c64.vic.rasterLine, 101)
            XCTAssertEqual(c64.vic.readRegister(0x19), 0xF1)
        }
    }

    func testBoundaryWriteDoesNotMatchTheDepartingRaster() {
        for profile in [MachineProfile.palC64, .ntscC64] {
            let c64 = machine(profile, line: 100, compare: 99)
            store(c64, register: 0x12, value: 100, atCycle: c64.vic.rasterCyclesPerLine - 1)
            XCTAssertEqual(c64.vic.rasterLine, 101)
            XCTAssertEqual(c64.vic.readRegister(0x19), 0x70)
        }
    }

    func testHighBitBoundaryWriteUsesTheIncomingRaster() {
        for profile in [MachineProfile.palC64, .ntscC64] {
            let c64 = machine(profile, line: 255, compare: 0)
            store(c64, register: 0x11, value: 0x80, atCycle: c64.vic.rasterCyclesPerLine - 1)
            XCTAssertEqual(c64.vic.rasterLine, 256)
            XCTAssertEqual(c64.vic.readRegister(0x19), 0xF1)
        }
    }

    func testHeldComparatorRearmsAfterLeavingTheMatchAndAfterReset() {
        for profile in [MachineProfile.palC64, .ntscC64] {
            let c64 = machine(profile, line: 100, compare: 100)
            let vic = c64.vic
            store(c64, register: 0x12, value: 101, atCycle: vic.rasterCyclesPerLine - 1)
            vic.writeRegister(0x1A, value: 0)
            vic.writeRegister(0x1A, value: 1)
            XCTAssertEqual(vic.readRegister(0x19), 0x70, "IRQ mask changes are not comparator edges")
            while vic.rasterLine == 101 { vic.tick() }
            vic.writeRegister(0x12, value: 102)
            XCTAssertEqual(vic.readRegister(0x19), 0xF1)
            vic.reset()
            vic.writeRegister(0x12, value: 0)
            XCTAssertEqual(vic.readRegister(0x19), 0x71)
        }
    }
}
