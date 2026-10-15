import XCTest
@testable import C64Core

final class VICSpriteFetchTests: XCTestCase {
    // Zero-based cycles from the hardware-checked phi1timing PAL/NTSC probes,
    // independent of VIC's slot helpers.
    private let schedules: [(C64VideoStandard, [Int])] = [
        (.pal, [57, 59, 61, 0, 2, 4, 6, 8]),
        (.ntsc, [58, 60, 62, 64, 1, 3, 5, 7])
    ]

    func testEverySpriteFetchesPointerThenThreeBytesAcrossTwoCycles() {
        for (standard, starts) in schedules {
            for sprite in 0..<8 {
                let vic = VIC()
                vic.videoStandard = standard
                vic.rasterLine = 100
                vic.rasterCycle = starts[sprite]
                vic.spriteEnabled = UInt8(1 << sprite)
                vic.spriteDMACheckMask = UInt8(1 << sprite)
                vic.spriteY[sprite] = 100
                vic.seedSpriteRow(sprite, bytes: [0xEE, 0xEE, 0xEE])
                var reads: [UInt16] = []
                var tail: UInt8 = 0x22
                vic.readMemory = { address in
                    reads.append(address)
                    if address == 0x07F8 + UInt16(sprite) { return 0x20 }
                    if address == 0x0800 { return 0x11 }
                    return tail
                }

                XCTAssertEqual(vic.lowPhaseAccess, .spritePointer(sprite: sprite))
                vic.tick()
                XCTAssertEqual(reads, [0x07F8 + UInt16(sprite), 0x0800])
                XCTAssertEqual(vic.lastHighPhaseMemoryReads, [0x0800])
                XCTAssertEqual(vic.spriteLineData[sprite], [0x11, 0xEE, 0xEE])
                XCTAssertEqual(vic.spriteShifters[sprite].data, 0x11EEEE)
                XCTAssertEqual(vic.spriteMC[sprite], 1)

                tail = 0x33
                reads.removeAll()
                XCTAssertEqual(vic.lowPhaseAccess, .spriteMiddleByte(sprite: sprite))
                vic.tick()
                XCTAssertEqual(reads, [0x0801, 0x0802])
                XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x0801])
                XCTAssertEqual(vic.lastHighPhaseMemoryReads, [0x0802])
                XCTAssertEqual(vic.spriteLineData[sprite], [0x11, 0x33, 0x33])
                XCTAssertEqual(vic.spriteShifters[sprite].data, 0x113333)
                XCTAssertEqual(vic.spriteMC[sprite], 3)
            }
        }
    }

    func testDisabledSpritesStillReadPointersButNeverFetchData() {
        for (standard, starts) in schedules {
            for sprite in 0..<8 {
                let vic = VIC()
                vic.videoStandard = standard
                vic.rasterCycle = starts[sprite]
                var reads: [UInt16] = []
                vic.readMemory = { reads.append($0); return 0x20 }
                XCTAssertFalse(vic.baLineLow)
                XCTAssertFalse(vic.aecLineLow)
                vic.tick()
                XCTAssertEqual(reads, [0x07F8 + UInt16(sprite)])
                XCTAssertTrue(vic.lastHighPhaseMemoryReads.isEmpty)
                XCTAssertFalse(vic.aecLineLow)
                reads.removeAll()
                vic.tick()
                XCTAssertEqual(reads, [0x3FFF])
                XCTAssertTrue(vic.lastHighPhaseMemoryReads.isEmpty)
            }
        }
    }

    func testD018ChangeJustBeforePointerReadSelectsNewSpriteImage() {
        for (standard, starts) in schedules {
            let vic = VIC()
            vic.videoStandard = standard
            vic.rasterLine = 100
            vic.rasterCycle = starts[0] - 3
            vic.spriteEnabled = 1
            vic.spriteY[0] = 100
            vic.readMemory = { address in
                switch address {
                case 0x07F8: return 0x20
                case 0x0BF8: return 0x30
                case 0x0C00: return 0xA5
                default: return 0
                }
            }
            for _ in 0..<3 { vic.tick() }
            vic.writeRegister(0x18, value: 0x24)
            vic.tick()
            XCTAssertEqual(vic.spritePointers[0], 0x30)
            XCTAssertEqual(vic.spriteLineData[0][0], 0xA5)
            XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x0BF8])
            XCTAssertEqual(vic.lastHighPhaseMemoryReads, [0x0C00])
        }
    }

    func testPointerStaysLatchedButBankPinsRemainLiveDuringBurst() {
        let c64 = C64()
        let vic = c64.vic
        vic.rasterLine = 100
        vic.rasterCycle = 57
        vic.spriteEnabled = 1
        vic.spriteY[0] = 100
        vic.spriteDMACheckMask = 1
        vic.spriteMC[0] = 0
        vic.spriteMCBase[0] = 0
        c64.cia2.writeRegister(2, value: 3)
        c64.cia2.writeRegister(0, value: 3)
        c64.memory.ram[0x07F8] = 0x20
        c64.memory.ram[0x0800] = 0x11
        c64.memory.ram[0x4801] = 0x22
        c64.memory.ram[0x4802] = 0x33
        c64.memory.ram[0x4BF8] = 0x30
        vic.tick()
        vic.writeRegister(0x18, value: 0x24)
        c64.cia2.writeRegister(0, value: 2)
        vic.tick()
        XCTAssertEqual(vic.spritePointers[0], 0x20)
        XCTAssertEqual(vic.spriteLineData[0], [0x11, 0x22, 0x33])
    }

    func testStartedBurstCompletesAfterEnableClears() {
        let vic = VIC()
        vic.rasterLine = 100
        vic.rasterCycle = 57
        vic.spriteY[0] = 100
        vic.spriteDMACheckMask = 1
        vic.spriteMC[0] = 0
        vic.spriteMCBase[0] = 0
        vic.spriteEnabled = 1
        vic.readMemory = { $0 == 0x07F8 ? 0x20 : UInt8(truncatingIfNeeded: $0) }
        vic.tick()
        vic.writeRegister(0x15, value: 0)
        XCTAssertEqual(vic.activeSpriteDMASlot, 0)
        XCTAssertTrue(vic.aecLineLow)
        vic.tick()
        XCTAssertEqual(vic.spriteLineData[0], [0, 1, 2])
    }

    func testSixBitCounterWrapDoesNotReadTheNextSpriteBlock() {
        let vic = VIC()
        vic.rasterLine = 100
        vic.rasterCycle = 57
        vic.spriteEnabled = 1
        vic.spriteDMACheckLine = 100
        vic.spriteDMACheckMask = 1
        vic.spriteMCBase[0] = 62
        vic.readMemory = { $0 == 0x07F8 ? 0x20 : UInt8(truncatingIfNeeded: $0) }
        vic.tick()
        XCTAssertEqual(vic.spriteMC[0], 63)
        XCTAssertEqual(vic.lastHighPhaseMemoryReads, [0x083E])
        vic.tick()
        XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x083F])
        XCTAssertEqual(vic.lastHighPhaseMemoryReads, [0x0800])
        XCTAssertEqual(vic.spriteLineData[0], [0x3E, 0x3F, 0])
        XCTAssertEqual(vic.spriteMC[0], 1)
    }

    func testCPUWriteToD018DoesNotRetroactivelyChangeSameCyclePointerRead() {
        for (standard, starts) in schedules {
            let c64 = C64()
            c64.vic.videoStandard = standard
            c64.vic.rasterCycle = starts[0] - 3
            c64.vic.rasterLine = 100
            c64.cpu.pc = 0x0600
            c64.cpu.a = 0x24
            c64.memory.ram[0x0600] = 0x8D // STA $D018, write on fourth cycle
            c64.memory.ram[0x0601] = 0x18
            c64.memory.ram[0x0602] = 0xD0
            c64.memory.ram[0x07F8] = 0x20
            c64.memory.ram[0x0BF8] = 0x30
            for _ in 0..<4 { c64.tickOneCycle() }
            XCTAssertEqual(c64.vic.memoryPointers, 0x24)
            XCTAssertEqual(c64.vic.spritePointers[0], 0x20)
            XCTAssertEqual(c64.vic.lastLowPhaseMemoryReads, [0x07F8])
        }
    }

    func testCPUWriteAfterSecondYCompareDoesNotStartDMAOnThatLine() {
        let c64 = C64()
        c64.vic.rasterLine = 100
        c64.vic.rasterCycle = 52
        c64.vic.spriteEnabled = 1
        c64.vic.spriteY[0] = 10
        c64.cpu.pc = 0x0600
        c64.cpu.a = 100
        c64.memory.ram[0x0600] = 0x8D // STA $D001, write in cycle index 55
        c64.memory.ram[0x0601] = 0x01
        c64.memory.ram[0x0602] = 0xD0
        for _ in 0..<4 { c64.tickOneCycle() }
        XCTAssertEqual(c64.vic.spriteY[0], 100)
        XCTAssertEqual(c64.vic.spriteDMACheckMask, 0)
        c64.vic.tick()
        c64.vic.tick()
        XCTAssertFalse(c64.vic.spriteDisplay[0])
        XCTAssertNil(c64.vic.activeSpriteDMASlot)
    }

    func testBAStopsOpcodeReadsForWarningAndSpriteDMAThenResumes() {
        let c64 = C64()
        c64.vic.rasterLine = 100
        c64.vic.rasterCycle = 54
        c64.vic.spriteEnabled = 1
        c64.vic.spriteY[0] = 100
        c64.cpu.pc = 0x0600
        c64.memory.ram[0x0600] = 0xEA
        for _ in 0..<5 {
            c64.tickOneCycle()
            XCTAssertFalse(c64.cpu.rdyLine)
            XCTAssertEqual(c64.cpu.pc, 0x0600)
            XCTAssertEqual(c64.cpu.cycle, 0)
        }
        XCTAssertEqual(c64.vic.rasterCycle, 59)
        c64.tickOneCycle()
        XCTAssertTrue(c64.cpu.rdyLine)
        XCTAssertEqual(c64.cpu.pc, 0x0601)
    }

    func testBAAllowsPendingStoreButStopsTheFollowingOpcodeRead() {
        let c64 = C64()
        c64.vic.rasterLine = 100
        c64.vic.rasterCycle = 52
        c64.vic.spriteEnabled = 1
        c64.vic.spriteY[0] = 100
        c64.cpu.pc = 0x0600
        c64.cpu.a = 0x42
        c64.memory.ram[0x0600] = 0x85 // STA $10
        c64.memory.ram[0x0601] = 0x10
        c64.memory.ram[0x0602] = 0xEA
        c64.tickOneCycle()
        c64.tickOneCycle()
        XCTAssertFalse(c64.vic.baLineLow) // compare occurs in the next low phase
        XCTAssertFalse(c64.vic.aecLineLow)
        c64.tickOneCycle()
        XCTAssertFalse(c64.cpu.rdyLine)
        XCTAssertEqual(c64.memory.ram[0x0010], 0x42)
        XCTAssertEqual(c64.cpu.pc, 0x0602)
        c64.tickOneCycle()
        XCTAssertEqual(c64.cpu.pc, 0x0602)
        XCTAssertEqual(c64.cpu.cycle, 0)
    }

    func testBadLineBAStopsReadsBeforeAECWithoutStoppingTheClock() {
        let c64 = C64()
        c64.vic.rasterLine = 51
        c64.vic.rasterCycle = 11
        c64.vic.badLine = true
        c64.cpu.pc = 0x0600
        c64.memory.ram[0x0600] = 0xEA
        let before = c64.cpu.totalCycles
        for _ in 0..<43 { c64.tickOneCycle() }
        XCTAssertEqual(c64.cpu.totalCycles, before + 43)
        XCTAssertEqual(c64.cpu.pc, 0x0600)
        XCTAssertEqual(c64.cpu.cycle, 0)
        XCTAssertEqual(c64.vic.rasterCycle, 54)
        c64.tickOneCycle()
        XCTAssertEqual(c64.cpu.pc, 0x0601)
    }
}
