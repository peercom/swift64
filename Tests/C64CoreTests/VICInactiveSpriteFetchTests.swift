import XCTest
@testable import C64Core

final class VICInactiveSpriteFetchTests: XCTestCase {
    private let schedules: [(C64VideoStandard, [Int])] = [
        (.pal, [57, 59, 61, 0, 2, 4, 6, 8]),
        (.ntsc, [58, 60, 62, 64, 1, 3, 5, 7])
    ]

    func testEveryInactiveSlotLoadsPulledUpAndIdleBytesWithoutDMAOrCounterAdvance() {
        for (standard, starts) in schedules {
            for sprite in 0..<8 {
                let vic = VIC()
                vic.videoStandard = standard
                vic.rasterLine = 100
                vic.rasterCycle = starts[sprite]
                vic.spriteMCBase[sprite] = 12
                vic.spriteMC[sprite] = 12
                vic.seedSpriteRow(sprite, bytes: [0, 0, 0])
                var reads: [UInt16] = []
                vic.readMemory = { address in
                    reads.append(address)
                    return address == 0x3FFF ? 0x4D : 0x20
                }
                for _ in 0..<2 {
                    vic.beginCycle()
                    XCTAssertFalse(vic.aecLineLow)
                    XCTAssertFalse(vic.baLineLow)
                    vic.endCycle()
                    XCTAssertTrue(vic.lastHighPhaseMemoryReads.isEmpty)
                }
                XCTAssertEqual(reads, [UInt16(0x07F8 + sprite), 0x3FFF])
                XCTAssertEqual(vic.spriteLineData[sprite], [0xFF, 0x4D, 0xFF])
                XCTAssertEqual(vic.spriteShifters[sprite].data, 0xFF4DFF)
                XCTAssertEqual(vic.spriteMC[sprite], 12)
                XCTAssertEqual(vic.spriteMCBase[sprite], 12)
                XCTAssertEqual(vic.spriteDMACheckMask, 0)
                XCTAssertFalse(vic.spriteDisplay[sprite])
            }
        }
    }

    func testInactiveSlotsSampleOnlyCurrentCPUPhaseVICRegisterAccesses() {
        let vic = VIC()
        vic.rasterLine = 100
        vic.rasterCycle = 6
        vic.spriteX[0] = 0xAC
        vic.readMemory = { $0 == 0x3FFF ? 0x4D : 0x20 }
        vic.beginCycle()
        XCTAssertEqual(vic.readRegister(0x40), 0xAC)
        vic.endCycle()
        vic.beginCycle()
        vic.writeRegister(0x7F, value: 0x26)
        vic.endCycle()
        XCTAssertEqual(vic.spriteLineData[6], [0xAC, 0x4D, 0x26])
        // A CPU access in the previous cycle must not leak into sprite 7.
        vic.tick()
        XCTAssertEqual(vic.spriteLineData[7][0], 0xFF)
    }

    func testDebuggerReadsDoNotDriveTheInternalBusOrClearCollisions() {
        let vic = VIC()
        vic.rasterCycle = 6
        vic.spriteSpriteCollision = 0x36
        vic.beginCycle()
        XCTAssertEqual(vic.debugRegisterValue(0x1E), 0x36)
        vic.endCycle()
        XCTAssertEqual(vic.spriteSpriteCollision, 0x36)
        XCTAssertEqual(vic.spriteLineData[6][0], 0xFF)
        vic.beginCycle()
        XCTAssertEqual(vic.readRegister(0x1E), 0x36)
        vic.endCycle()
        XCTAssertEqual(vic.spriteSpriteCollision, 0)
        XCTAssertEqual(vic.spriteLineData[6][2], 0x36)
    }

    func testCPUIndexedStoreSuppliesDummyReadAndWriteToInactiveSprite() {
        for (standard, starts) in schedules {
            for address: UInt16 in [0xD000, 0xD040, 0x4000] {
                let c64 = C64(machineProfile: standard == .pal ? .palC64 : .ntscC64)
                c64.trueDriveEmulationMode = .off
                c64.kernalTraps.enabled = false
                c64.vic.rasterLine = 100
                c64.vic.rasterCycle = starts[6] - 3
                c64.vic.spriteX[0] = 0xAC
                c64.vic.recordsBusAccessTraces = false
                c64.memory.ram[0x3FFF] = 0x4D
                c64.memory.ram[0x4000] = 0xAC
                c64.memory.ram[0x0600] = 0x99 // STA abs,Y: dummy read then write
                c64.memory.ram[0x0601] = UInt8(truncatingIfNeeded: address)
                c64.memory.ram[0x0602] = UInt8(address >> 8)
                c64.cpu.pc = 0x0600
                c64.cpu.a = 0x26
                c64.cpu.y = 0
                for _ in 0..<5 {
                    c64.tickOneCycle()
                    XCTAssertTrue(c64.cpu.rdyLine)
                }
                XCTAssertEqual(c64.cpu.pc, 0x0603)
                XCTAssertEqual(c64.vic.spriteLineData[6], address == 0x4000
                               ? [0xFF, 0x4D, 0xFF] : [0xAC, 0x4D, 0x26])
                XCTAssertEqual(c64.vic.spriteMC[6], 0)
            }
        }
    }

    func testInactiveSpriteCanDisplayPrefetchedBytesOnItsYMatchLineInSideBorder() {
        for x in [355, 356] {
            let vic = VIC()
            vic.rasterLine = 100
            vic.spriteEnabled = 0x40
            vic.spriteY[6] = 100
            vic.spriteX[6] = UInt16(x)
            vic.spriteColors[6] = 2
            vic.verticalBorderActive = false
            vic.verticalBorderClosePending = false
            vic.horizontalBorderActive = false
            vic.backgroundColor[0] = 7
            vic.readMemory = { $0 == 0x3FFF ? 0x4D : 0x20 }
            while vic.rasterLine == 100 {
                if vic.rasterCycle == 55 { vic.controlReg2 = 8 }
                if vic.rasterCycle == 56 { vic.controlReg2 = 0 }
                vic.beginCycle()
                if vic.rasterCycle == 6 { vic.writeRegister(0x2F, value: 0xAC) }
                if vic.rasterCycle == 7 { vic.writeRegister(0x2F, value: 0x26) }
                vic.endCycle()
            }
            let row = (100 - VIC.firstVisibleLine) * VIC.screenWidth
            for bit in 0..<24 {
                let visible = x == 356 && (0xAC4D26 & (1 << (23 - bit))) != 0
                XCTAssertEqual(vic.framebuffer[row + x + bit], ColorPalette.rgba[visible ? 2 : 7], "x=\(x) bit=\(bit)")
            }
        }
    }
}
