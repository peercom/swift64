import XCTest
@testable import C64Core

final class VICGraphicsModeOutputTests: XCTestCase {
    private let standards: [C64VideoStandard] = [.pal, .ntsc]
    // Independent color sequences for the data byte $66, matrix $A2,
    // color RAM $E and backgrounds 6/7/5/1.
    private let colors: [[Int]] = [
        [6, 14, 14, 6, 6, 14, 14, 6],
        [7, 7, 5, 5, 7, 7, 5, 5],
        [2, 10, 10, 2, 2, 10, 10, 2],
        [10, 10, 2, 2, 10, 10, 2, 2],
        [5, 14, 14, 5, 5, 14, 14, 5],
        Array(repeating: 0, count: 8),
        Array(repeating: 0, count: 8),
        Array(repeating: 0, count: 8)
    ]

    private func machine(_ standard: C64VideoStandard, mode: Int, scroll: Int = 0) -> VIC {
        let vic = VIC()
        vic.videoStandard = standard
        vic.rasterLine = 100
        vic.controlReg1 = 0x1B | UInt8((mode & 6) << 4)
        vic.controlReg2 = 8 | UInt8((mode & 1) << 4) | UInt8(scroll)
        vic.memoryPointers = 0x18
        vic.backgroundColor = [6, 7, 5, 1]
        vic.displayActive = true
        vic.verticalBorderActive = false
        vic.verticalBorderClosePending = false
        vic.lineBuffer = Array(repeating: 0xA2, count: 40)
        vic.colorBuffer = Array(repeating: 14, count: 40)
        vic.readMemory = { _ in 0x66 }
        vic.recordsBusAccessTraces = false
        return vic
    }

    private func finishLine(_ vic: VIC, write: (VIC) -> Void = { _ in }) {
        let line = vic.rasterLine
        while vic.rasterLine == line {
            vic.beginCycle()
            if vic.rasterCycle == 25 { write(vic) }
            vic.endCycle()
        }
    }

    private func pixel(_ vic: VIC, line: Int = 100, x: Int) -> UInt32 {
        vic.framebuffer[(line - VIC.firstVisibleLine) * VIC.screenWidth + x]
    }

    func testModeOutputChangesWithoutWaitingForAnotherGraphicsFetch() {
        for standard in standards {
            for initial in 0..<8 {
                for final in 0..<8 where initial != final && (initial & 1 == final & 1 || initial ^ final == 1) {
                    for scroll in 0..<8 {
                        let vic = machine(standard, mode: initial, scroll: scroll)
                        finishLine(vic) {
                            if initial ^ final == 1 {
                                $0.writeRegister(0x16, value: 8 | UInt8((final & 1) << 4) | UInt8(scroll))
                            } else {
                                $0.writeRegister(0x11, value: 0x1B | UInt8((final & 6) << 4))
                            }
                        }
                        // Column 10 was fetched in phi1 before the write. Its
                        // output is later and must use the new mode, not the
                        // mode stored alongside its address. Transition-dot
                        // analog artifacts are checked by the public probes.
                        for bit in 0..<8 {
                            XCTAssertEqual(pixel(vic, x: 104 + scroll + bit), ColorPalette.rgba[colors[final][bit]],
                                           "\(standard) \(initial)->\(final) scroll=\(scroll) bit=\(bit)")
                            XCTAssertEqual(pixel(vic, x: 80 + scroll + bit), ColorPalette.rgba[colors[initial][bit]])
                        }
                    }
                }
            }
        }
    }

    func testBitmapModeChangeRetainsPreviouslyFetchedCharacterData() {
        for standard in standards {
            let vic = machine(standard, mode: 0)
            var fetchAddresses: [UInt16] = []
            vic.readMemory = { address in
                if (25...27).contains(vic.rasterCycle) { fetchAddresses.append(address) }
                return address == 0x2510 ? 0x66 : 0x99
            }
            finishLine(vic) { $0.writeRegister(0x11, value: 0x3B) }
            vic.readMemory = nil
            XCTAssertEqual(fetchAddresses, [0x2510, 0x2010, 0x2060])
            for bit in 0..<8 {
                XCTAssertEqual(pixel(vic, x: 104 + bit), ColorPalette.rgba[colors[2][bit]])
                XCTAssertEqual(pixel(vic, x: 112 + bit), ColorPalette.rgba[colors[2][bit] == 10 ? 2 : 10])
            }
        }
    }

    func testMulticolorEnableRetainsDataLatchUntilReload() {
        // Color-index windows from the hardware-matched modesplit probe,
        // character row $99, matrix $5F, color $E, backgrounds 6/1/2.
        let expected = [
            "2666221122112211", "2266222112211221",
            "6222112211221122", "6622662221122112",
            "2666221122112211", "2266666622211221",
            "6222112211221122", "6622211221122112"
        ]
        for standard in standards {
            for scroll in 0..<8 {
                let vic = machine(standard, mode: 0, scroll: scroll)
                vic.readMemory = { _ in 0x99 }
                vic.lineBuffer = Array(repeating: 0x5F, count: 40)
                vic.backgroundColor = [6, 1, 2, 0]
                finishLine(vic) { $0.writeRegister(0x16, value: 0x18 | UInt8(scroll)) }
                for (offset, color) in expected[scroll].enumerated() {
                    XCTAssertEqual(pixel(vic, x: 100 + offset), ColorPalette.rgba[Int(String(color), radix: 16)!],
                                   "\(standard) scroll=\(scroll) dot=\(offset)")
                }
            }
        }
    }

    func testMulticolorDisableChangesColorBeforeDataWidth() {
        let expected = [
            "ee6ee66ee66ee66e", "6ee6ee66ee66ee66",
            "66e66ee66ee66ee6", "e66e66ee66ee66ee"
        ]
        for standard in standards {
            for scroll in 0..<8 {
                let vic = machine(standard, mode: 1, scroll: scroll)
                vic.readMemory = { _ in 0x99 }
                vic.lineBuffer = Array(repeating: 0x5F, count: 40)
                vic.backgroundColor = [6, 1, 2, 0]
                finishLine(vic) { $0.writeRegister(0x16, value: 8 | UInt8(scroll)) }
                for (offset, color) in expected[scroll % 4].enumerated() {
                    XCTAssertEqual(pixel(vic, x: 100 + offset), ColorPalette.rgba[Int(String(color), radix: 16)!],
                                   "\(standard) scroll=\(scroll) dot=\(offset)")
                }
            }
        }
    }

    func testMulticolorTransitionsKeepLowColorTextHires() {
        for standard in standards {
            for initial in [0, 1] {
                for scroll in 0..<8 {
                    let vic = machine(standard, mode: initial, scroll: scroll)
                    vic.readMemory = { _ in 0x96 }
                    vic.colorBuffer = Array(repeating: 5, count: 40)
                    finishLine(vic) {
                        $0.writeRegister(0x16, value: 8 | UInt8((initial ^ 1) << 4) | UInt8(scroll))
                    }
                    for x in 96..<120 {
                        let bit = (x - VIC.displayLeft - scroll) & 7
                        let color = 0x96 & (0x80 >> bit) == 0 ? 6 : 5
                        XCTAssertEqual(pixel(vic, x: x), ColorPalette.rgba[color],
                                       "\(standard) initial=\(initial) scroll=\(scroll) x=\(x)")
                    }
                }
            }
        }
    }

    func testMulticolorDataLatchDrivesForegroundPriority() {
        let cases: [(mode: Int, scroll: Int, foreground: [Bool])] = [
            (0, 0, [true, false, false, false, true, true, false, false]),
            (1, 1, [false, true, true, false, true, true, false, false])
        ]
        for standard in standards {
            for probe in cases {
                let vic = machine(standard, mode: probe.mode, scroll: probe.scroll)
                vic.readMemory = { _ in 0x99 }
                while vic.rasterCycle < 25 { vic.tick() }
                vic.beginCycle()
                vic.writeRegister(0x16, value: 8 | UInt8((probe.mode ^ 1) << 4) | UInt8(probe.scroll))
                vic.endCycle()
                vic.tick()
                for (dot, foreground) in probe.foreground.enumerated() {
                    XCTAssertEqual(vic.displayForegroundAtTracePixel(100 + dot), foreground,
                                   "\(standard) mode=\(probe.mode) dot=\(dot)")
                }
            }
        }
    }

    func testBitmapClearBackgroundSelectionLagsForeground() {
        for standard in standards {
            for foreground in [false, true] {
                let vic = machine(standard, mode: 2)
                vic.readMemory = { _ in foreground ? 0xFF : 0 }
                finishLine(vic) { $0.writeRegister(0x11, value: 0x1B) }
                for dot in 0..<8 {
                    let color = foreground ? 14 : dot < 2 ? 2 : 6
                    XCTAssertEqual(pixel(vic, x: 100 + dot), ColorPalette.rgba[color],
                                   "\(standard) foreground=\(foreground) dot=\(dot)")
                }
            }
        }
    }

    func testInvalidModeReleaseDoesNotBlankForegroundPriority() {
        for standard in standards {
            for initial in [5, 6] {
                for foreground in [false, true] {
                    let vic = machine(standard, mode: initial)
                    vic.readMemory = { _ in foreground ? 0xFF : 0 }
                    while vic.rasterCycle < 25 { vic.tick() }
                    vic.beginCycle()
                    if initial == 5 { vic.writeRegister(0x16, value: 8) }
                    else { vic.writeRegister(0x11, value: 0x5B) }
                    vic.endCycle()
                    vic.tick()
                    for dot in 0..<8 { XCTAssertEqual(vic.displayForegroundAtTracePixel(100 + dot), foreground) }
                    finishLine(vic)
                    for dot in 0..<8 {
                        let color = dot < (standard == .pal ? 1 : 2) ? 0 : foreground ? 14 : 5
                        XCTAssertEqual(pixel(vic, x: 100 + dot), ColorPalette.rgba[color],
                                       "\(standard) initial=\(initial) foreground=\(foreground) dot=\(dot)")
                    }
                }
            }
        }
    }

    func testBitmapAddressSelectionChangesInTwoStages() {
        for standard in standards {
            for initial in [0, 2, 4, 6] {
                let vic = machine(standard, mode: initial)
                vic.videoCounterBase = 0x148
                vic.rowCounter = 3
                while vic.rasterCycle < 25 { vic.tick() }
                vic.recordsBusAccessTraces = true
                vic.beginCycle()
                let oldAddress: UInt16 = initial & 2 == 0 ? (initial & 4 == 0 ? 0x2513 : 0x2113)
                    : (initial & 4 == 0 ? 0x2A93 : 0x2893)
                XCTAssertEqual(vic.lastLowPhaseMemoryReads, [oldAddress])
                vic.writeRegister(0x11, value: vic.controlReg1 ^ 0x20)
                vic.endCycle()
                vic.tick()
                let mixedAddress: UInt16 = initial & 2 == 0 ? (initial & 4 == 0 ? 0x2A13 : 0x2813)
                    : (initial & 4 == 0 ? 0x259B : 0x219B)
                XCTAssertEqual(vic.lastLowPhaseMemoryReads, [mixedAddress], "\(standard) mode=\(initial)")
                vic.tick()
                let settledAddress: UInt16 = initial & 2 == 0 ? (initial & 4 == 0 ? 0x2AA3 : 0x28A3)
                    : (initial & 4 == 0 ? 0x2513 : 0x2113)
                XCTAssertEqual(vic.lastLowPhaseMemoryReads, [settledAddress])
            }
        }
    }

    func testBitmapAddressDelayExpiresOnIdleCyclesAndReset() {
        for standard in standards {
            for idle in [false, true] {
                let vic = machine(standard, mode: 0)
                // A write before a refresh slot must not affect the first
                // graphics fetch several cycles later.
                while vic.rasterCycle < 10 { vic.tick() }
                vic.beginCycle()
                vic.writeRegister(0x11, value: 0x3B)
                vic.endCycle()
                while vic.rasterCycle < 15 { vic.tick() }
                vic.displayActive = !idle
                vic.recordsBusAccessTraces = true
                vic.tick()
                XCTAssertEqual(vic.lastLowPhaseMemoryReads, [idle ? 0x3FFF : 0x2000])
                vic.beginCycle()
                vic.writeRegister(0x11, value: 0x1B)
                vic.endCycle()
                vic.reset()
                vic.rasterLine = 100
                vic.rasterCycle = 15
                vic.displayActive = true
                vic.lineBuffer[0] = 0xA2
                vic.memoryPointers = 0x18
                vic.tick()
                XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x2510])
            }
        }
    }

    func testModeOutputKeepsForegroundClassificationInInvalidModes() {
        for standard in standards {
            for mode in 0..<8 {
                let vic = machine(standard, mode: mode ^ 1)
                while vic.rasterCycle < 25 { vic.tick() }
                vic.beginCycle()
                vic.writeRegister(0x16, value: 8 | UInt8((mode & 1) << 4))
                vic.endCycle()
                vic.beginCycle()
                vic.endCycle()
                for bit in 0..<8 {
                    let foreground = mode & 1 == 0 ? [false, true, true, false, false, true, true, false]
                        : [false, false, true, true, false, false, true, true]
                    XCTAssertEqual(vic.displayForegroundAtTracePixel(104 + bit), foreground[bit], "mode=\(mode) bit=\(bit)")
                }
            }
        }
    }

    func testECMAddressMaskTransitionsFollowChipProfile() {
        for standard in standards {
            for bitmap in [false, true] {
                for idle in [false, true] {
                    let vic = machine(standard, mode: bitmap ? 6 : 4)
                    vic.videoCounterBase = 0x148
                    vic.rowCounter = 3
                    while vic.rasterCycle < 25 { vic.tick() }
                    vic.displayActive = !idle
                    vic.recordsBusAccessTraces = true
                    vic.beginCycle()
                    vic.writeRegister(0x11, value: bitmap ? 0x3B : 0x1B)
                    vic.endCycle()
                    vic.tick()
                    let nextAddress: UInt16 = idle ? 0x3FFF : bitmap ? 0x2A9B : 0x2513
                    XCTAssertEqual(vic.lastLowPhaseMemoryReads, [standard == .pal ? nextAddress & 0x39FF : nextAddress])
                    vic.tick()
                    XCTAssertEqual(vic.lastLowPhaseMemoryReads, [idle ? 0x3FFF : bitmap ? 0x2AA3 : 0x2513])
                    vic.beginCycle()
                    vic.writeRegister(0x11, value: bitmap ? 0x7B : 0x5B)
                    vic.endCycle()
                    vic.tick()
                    let assertedAddress: UInt16 = idle ? 0x3FFF : bitmap ? 0x2AB3 : 0x2513
                    XCTAssertEqual(vic.lastLowPhaseMemoryReads,
                                   [standard == .pal ? assertedAddress & 0x39FF : assertedAddress])
                    vic.tick()
                    XCTAssertEqual(vic.lastLowPhaseMemoryReads, [idle ? 0x39FF : bitmap ? 0x28BB : 0x2113])
                }
            }
        }
    }

    func testECMClearOutputUsesDelayedBackgroundSelector() {
        for standard in standards {
            let vic = machine(standard, mode: 4)
            vic.readMemory = { _ in 0 }
            finishLine(vic) { $0.writeRegister(0x11, value: 0x1B) }
            // At cycle 25 the beam is at logical X=100. Color selection
            // retains the ECM background through the first two dots.
            for x in 96..<102 { XCTAssertEqual(pixel(vic, x: x), ColorPalette.rgba[5]) }
            for x in 102..<112 { XCTAssertEqual(pixel(vic, x: x), ColorPalette.rgba[6]) }
            vic.writeRegister(0x11, value: 0x5B)
            vic.beginCycle()
            vic.writeRegister(0x11, value: 0x1B)
            vic.reset()
            vic.rasterLine = 100
            vic.rasterCycle = 15
            vic.displayActive = true
            vic.lineBuffer[0] = 0xA2
            vic.memoryPointers = 0x18
            vic.recordsBusAccessTraces = true
            vic.tick()
            XCTAssertEqual(vic.lastLowPhaseMemoryReads, [0x2510])
        }
    }

    func testECMAddressDelayExpiresInNonGraphicsSlots() {
        for standard in standards {
            for initial in [0, 4] {
                for cycle in [10, 54, standard == .pal ? 62 : 64] {
                    let vic = machine(standard, mode: initial)
                    while vic.rasterCycle < cycle { vic.tick() }
                    vic.beginCycle()
                    vic.writeRegister(0x11, value: initial == 0 ? 0x5B : 0x1B)
                    vic.endCycle()
                    vic.tick()
                    // The intervening refresh, idle, or sprite slot consumes
                    // the delayed selection, even without a graphics fetch.
                    vic.rasterLine = 100
                    vic.rasterCycle = 15
                    vic.displayActive = true
                    vic.videoMatrixLineIndex = 0
                    vic.rowCounter = 0
                    vic.recordsBusAccessTraces = true
                    vic.tick()
                    XCTAssertEqual(vic.lastLowPhaseMemoryReads, [initial == 0 ? 0x2110 : 0x2510])
                }
            }
        }
    }

    func testResetDiscardsBothPendingECMAddressSelections() {
        for standard in standards {
            for initial in [0, 4] {
                let vic = machine(standard, mode: initial)
                while vic.rasterCycle < 25 { vic.tick() }
                vic.beginCycle()
                vic.writeRegister(0x11, value: initial == 0 ? 0x5B : 0x1B)
                vic.endCycle()
                vic.reset()
                vic.controlReg1 = initial == 0 ? 0x5B : 0x1B
                vic.rasterLine = 100
                vic.rasterCycle = 15
                vic.displayActive = true
                vic.lineBuffer[0] = 0xA2
                vic.memoryPointers = 0x18
                vic.recordsBusAccessTraces = true
                vic.tick()
                XCTAssertEqual(vic.lastLowPhaseMemoryReads, [initial == 0 ? 0x2110 : 0x2510])
            }
        }
    }

    func testCPUStoresChangeOnlyTheNextGraphicsAddressStage() {
        let changes: [(from: Int, to: Int, pal: UInt16, ntsc: UInt16, settled: UInt16)] = [
            (0, 4, 0x2113, 0x2513, 0x2113),
            (4, 0, 0x2113, 0x2513, 0x2513),
            (4, 2, 0x2813, 0x2813, 0x2AA3),
            (6, 0, 0x219B, 0x219B, 0x2513),
            (0, 6, 0x2813, 0x2A13, 0x28A3),
            (2, 4, 0x219B, 0x259B, 0x2113)
        ]
        for standard in standards {
            for change in changes {
                let c64 = C64(machineProfile: standard == .pal ? .palC64 : .ntscC64)
                c64.trueDriveEmulationMode = .off
                c64.kernalTraps.enabled = false
                let vic = c64.vic
                vic.rasterLine = 100
                vic.controlReg1 = 0x1B | UInt8(change.from << 4)
                vic.memoryPointers = 0x18
                vic.displayActive = true
                vic.videoCounterBase = 0x148
                vic.rowCounter = 3
                vic.lineBuffer = Array(repeating: 0xA2, count: 40)
                vic.readMemory = { UInt8(truncatingIfNeeded: $0 >> 8) }
                while vic.rasterCycle < 22 { vic.tick() }
                c64.cpu.pc = 0x0600
                c64.cpu.a = 0x1B | UInt8(change.to << 4)
                for (offset, byte) in [UInt8(0x8D), 0x11, 0xD0, 0x4C, 0x03, 0x06].enumerated() {
                    c64.memory.ram[0x0600 + offset] = byte
                }
                for _ in 0..<4 { c64.tickOneCycle() }
                XCTAssertEqual(vic.rasterCycle, 26)
                XCTAssertEqual(vic.controlReg1, c64.cpu.a)
                vic.recordsBusAccessTraces = true
                c64.tickOneCycle()
                let first = standard == .pal ? change.pal : change.ntsc
                XCTAssertEqual(vic.lastLowPhaseMemoryReads, [first], "\(standard) \(change.from)->\(change.to)")
                XCTAssertEqual(vic.graphicsBuffer[11], UInt8(first >> 8))
                c64.tickOneCycle()
                XCTAssertEqual(vic.lastLowPhaseMemoryReads, [change.settled])
                XCTAssertEqual(vic.graphicsBuffer[12], UInt8(change.settled >> 8))
                XCTAssertFalse(c64.cpu.jammed)
            }
        }
    }

    func testCompoundBitmapECMWritesKeepAddressStagesIndependent() {
        let changes: [(from: Int, to: Int, pal: UInt16, ntsc: UInt16)] = [
            (4, 2, 0x2813, 0x2813),
            (6, 0, 0x219B, 0x219B),
            (0, 6, 0x2813, 0x2A13),
            (2, 4, 0x219B, 0x259B)
        ]
        for standard in standards {
            for change in changes {
                let vic = machine(standard, mode: change.from)
                vic.videoCounterBase = 0x148
                vic.rowCounter = 3
                while vic.rasterCycle < 25 { vic.tick() }
                vic.beginCycle()
                vic.writeRegister(0x11, value: 0x1B | UInt8(change.to << 4))
                vic.endCycle()
                vic.recordsBusAccessTraces = true
                vic.tick()
                XCTAssertEqual(vic.lastLowPhaseMemoryReads, [standard == .pal ? change.pal : change.ntsc],
                               "\(standard) \(change.from)->\(change.to)")
            }
        }
    }

    func testModeTraceDoesNotLeakAcrossRasterlinesOrReset() {
        for standard in standards {
            let vic = machine(standard, mode: 0)
            finishLine(vic) { $0.writeRegister(0x11, value: 0x3B) }
            vic.controlReg1 = 0x1B
            finishLine(vic)
            for bit in 0..<8 {
                XCTAssertEqual(pixel(vic, line: 101, x: 104 + bit), ColorPalette.rgba[colors[0][bit]])
            }
            vic.reset()
            XCTAssertNil(vic.rasterTraceLine)
            XCTAssertFalse(vic.rasterTraceHasSamples)
        }
    }
}
