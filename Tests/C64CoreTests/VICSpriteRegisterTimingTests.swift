import XCTest
@testable import C64Core

final class VICSpriteRegisterTimingTests: XCTestCase {
    private let standards: [C64VideoStandard] = [.pal, .ntsc]

    private func machine(_ standard: C64VideoStandard, sprite: Int = 0,
                         x: UInt16 = 100, byte: UInt8 = 0xFF, multicolor: Bool = false) -> C64 {
        let c64 = C64(machineProfile: standard == .pal ? .palC64 : .ntscC64)
        c64.trueDriveEmulationMode = .off
        c64.kernalTraps.enabled = false
        let vic = c64.vic
        vic.rasterLine = 100
        vic.verticalBorderActive = false
        vic.verticalBorderClosePending = false
        vic.horizontalBorderActive = false
        vic.recordsBusAccessTraces = false
        vic.readMemory = { _ in 0 }
        vic.spriteDisplay[sprite] = true
        vic.spriteX[sprite] = x
        vic.spriteColors[sprite] = 1
        vic.spriteMulticolor0 = 2
        vic.spriteMulticolor1 = 3
        vic.spriteMulticolor = multicolor ? UInt8(1 << sprite) : 0
        vic.seedSpriteRow(sprite, bytes: [byte, byte, byte])
        return c64
    }

    private func store(_ c64: C64, register: UInt8, value: UInt8, cycle: Int = 27) {
        while c64.vic.rasterCycle < cycle - 3 { c64.vic.tick() }
        c64.cpu.pc = 0x0600
        c64.cpu.a = value
        for (index, byte) in [UInt8(0x8D), register, 0xD0, 0x4C, 0x03, 0x06].enumerated() {
            c64.memory.ram[0x0600 + index] = byte
        }
        for _ in 0..<4 { c64.tickOneCycle() }
        XCTAssertEqual(c64.vic.rasterCycle, cycle + 1)
        let line = c64.vic.rasterLine
        while c64.vic.rasterLine == line { c64.tickOneCycle() }
        XCTAssertFalse(c64.cpu.jammed)
    }

    private func color(_ c64: C64, x: Int) -> UInt32 {
        c64.vic.framebuffer[(100 - VIC.firstVisibleLine) * VIC.screenWidth + x]
    }

    func testCPUColorWritesRecolorOnlyTheSelectedSpriteOutputSource() {
        for standard in standards {
            for sprite in 0..<8 {
                for (byte, register, oldColor) in [(UInt8(0x55), UInt8(0x25), 2),
                                                   (0xAA, UInt8(0x27 + sprite), 1),
                                                   (0xFF, 0x26, 3)] {
                    let c64 = machine(standard, sprite: sprite, byte: byte, multicolor: true)
                    store(c64, register: register, value: 0xF5)
                    for x in 100..<124 {
                        XCTAssertEqual(color(c64, x: x), ColorPalette.rgba[x < 113 ? oldColor : 5],
                                       "\(standard) sprite \(sprite) register \(register) x \(x)")
                    }
                    XCTAssertEqual(color(c64, x: 124), ColorPalette.rgba[0])
                }
            }
        }
    }

    func testHiddenSpriteColorWriteDoesNotRecolorThePriorityWinner() {
        for standard in standards {
            let c64 = machine(standard)
            c64.vic.spriteDisplay[1] = true
            c64.vic.spriteX[1] = 100
            c64.vic.spriteColors[1] = 1 // Same old RGB, different color source.
            c64.vic.seedSpriteRow(1, bytes: [0xFF, 0xFF, 0xFF])
            store(c64, register: 0x28, value: 5)
            for x in 100..<124 { XCTAssertEqual(color(c64, x: x), ColorPalette.rgba[1]) }
            XCTAssertEqual(c64.vic.spriteSpriteCollision, 3)
        }
    }

    func testXComparatorUsesTheNewCPUValueOnlyAfterTheFirstHalfCycle() {
        for standard in standards {
            for sprite in 0..<8 {
                for x: UInt16 in 116...123 {
                    let c64 = machine(standard, sprite: sprite, x: x)
                    store(c64, register: UInt8(sprite * 2), value: 150)
                    let start = x < 120 ? Int(x) : 150
                    for position in 110..<180 {
                        XCTAssertEqual(color(c64, x: position), ColorPalette.rgba[(start..<start + 24).contains(position) ? 1 : 0],
                                       "\(standard) sprite \(sprite) original X \(x) pixel \(position)")
                    }
                }
            }
        }
    }

    func testMulticolorWriteAfterConsumptionCannotRestartTheOutputLatch() {
        for standard in standards {
            let c64 = machine(standard)
            store(c64, register: 0x1C, value: 1, cycle: 32)
            for x in 124..<340 { XCTAssertEqual(color(c64, x: x), ColorPalette.rgba[0]) }
            XCTAssertFalse(c64.vic.spriteShifters[0].active)
        }
    }

    func testXHighBitWriteHasTheSameComparatorBoundaryAsTheLowByte() {
        for standard in standards {
            for sprite in 0..<8 {
                for low: UInt16 in 116...123 {
                    let c64 = machine(standard, sprite: sprite, x: low + 256)
                    c64.vic.spriteXMSB = UInt8(1 << sprite)
                    store(c64, register: 0x10, value: 0)
                    for x in 110..<150 {
                        let visible = low >= 120 && (Int(low)..<Int(low) + 24).contains(x)
                        XCTAssertEqual(color(c64, x: x), ColorPalette.rgba[visible ? 1 : 0])
                    }
                }
            }
        }
    }

    func testMulticolorWritesDoNotResetUnchangedSpritesPairPhase() {
        for standard in standards {
            for value: UInt8 in [1, 3] {
                let c64 = machine(standard, byte: 0x55, multicolor: true)
                c64.vic.spriteMulticolor = 3
                c64.vic.spriteDisplay[1] = true
                c64.vic.spriteX[1] = 100
                c64.vic.seedSpriteRow(1, bytes: [0xFF, 0xFF, 0xFF])
                store(c64, register: 0x1C, value: value)
                for x in 100..<124 { XCTAssertEqual(color(c64, x: x), ColorPalette.rgba[2]) }
                XCTAssertEqual(color(c64, x: 124), ColorPalette.rgba[0])
            }
        }
    }

    func testHiresToMulticolorKeepsDecodedPixelAndCompletesTheLastPair() {
        // Public ss-hires-mc images: a phi2 write on cycle 27 changes
        // the pair latch at X=119, after decoding the hires dot at X=118.
        for standard in standards {
            for expanded in [false, true] {
                let c64 = machine(standard, x: 97, byte: 0x55)
                c64.vic.spriteExpandX = expanded ? 1 : 0
                store(c64, register: 0x1C, value: 1)
                if expanded {
                    for x in 117...120 { XCTAssertEqual(color(c64, x: x), ColorPalette.rgba[0]) }
                    for x in 121...144 { XCTAssertEqual(color(c64, x: x), ColorPalette.rgba[2]) }
                    XCTAssertEqual(color(c64, x: 145), ColorPalette.rgba[0])
                } else {
                    for x in 118...121 { XCTAssertEqual(color(c64, x: x), ColorPalette.rgba[1]) }
                    XCTAssertEqual(color(c64, x: 122), ColorPalette.rgba[0])
                }
            }
        }
    }

    func testColorOutputWriteSpansTheHorizontalCounterWrap() {
        for standard in standards {
            for cycle in [12, 13] {
                let c64 = machine(standard)
                c64.vic.spriteDisplay[0] = false
                c64.vic.verticalBorderActive = true
                c64.vic.verticalBorderClosePending = true
                c64.vic.horizontalBorderActive = true
                c64.vic.borderColor = 2
                store(c64, register: 0x20, value: 5, cycle: cycle)
                for x in 0..<VIC.screenWidth {
                    XCTAssertEqual(color(c64, x: x), ColorPalette.rgba[cycle == 13 && x == 0 ? 2 : 5])
                }
            }
        }
    }
}
