import XCTest
import CryptoKit
@testable import C64Core

final class ExternalVICDemoTests: XCTestCase {
    private struct Sprite {
        let x: Int
        let y: Int
        let color: UInt8
        let slot: Int
        var pattern: [UInt8]? = nil
        var multicolor = false
        var expandedX = false
        var expandedY = false
        var behindBackground = false
    }

    func testSpriteOracleRejectsWrongHeightAndPriority() {
        let c64 = C64()
        c64.vic.framebuffer = [UInt32](repeating: ColorPalette.rgba[6], count: VIC.screenWidth * VIC.screenHeight)
        let sprites = [Sprite(x: 40, y: 60, color: 5, slot: 3), Sprite(x: 52, y: 70, color: 2, slot: 1)]
        for y in 61...81 {
            for x in 40..<64 {
                c64.vic.framebuffer[(y - VIC.firstVisibleLine) * VIC.screenWidth + x] = ColorPalette.rgba[5]
            }
        }
        for y in 71...91 {
            for x in 52..<76 {
                c64.vic.framebuffer[(y - VIC.firstVisibleLine) * VIC.screenWidth + x] = ColorPalette.rgba[2]
            }
        }
        let correct = compareDisplay(c64, sprites: sprites)
        XCTAssertEqual(correct.differences, 0)
        XCTAssertEqual(correct.overlapPixels, 12 * 11)
        c64.vic.framebuffer[(81 - VIC.firstVisibleLine) * VIC.screenWidth + 40] = ColorPalette.rgba[6]
        XCTAssertEqual(compareDisplay(c64, sprites: sprites).differences, 1, "A missing final sprite row must fail")
        c64.vic.framebuffer[(71 - VIC.firstVisibleLine) * VIC.screenWidth + 52] = ColorPalette.rgba[5]
        XCTAssertEqual(compareDisplay(c64, sprites: sprites).differences, 2, "Reversed sprite priority must fail")
    }

    func testOptInHessianSpriteMultiplexerPAL() throws {
        try runHessian(profile: .palC64, name: "pal")
    }

    func testOptInHessianSpriteMultiplexerNTSC() throws {
        try runHessian(profile: .ntscC64, name: "ntsc")
    }

    func testOptInPiperMixedSpriteModesPAL() throws {
        try runPiper(profile: .palC64, name: "pal")
    }

    func testOptInPiperMixedSpriteModesNTSC() throws {
        try runPiper(profile: .ntscC64, name: "ntsc")
    }

    func testOptInBefanaGameplayPAL() throws {
        try runBefana(profile: .palC64, name: "pal")
    }

    func testOptInBefanaNTSCSortDeadline() throws {
        try runBefana(profile: .ntscC64, name: "ntsc", expectSortOverrun: true)
    }

    func testOptInScrollingGameFrameworkPAL() throws {
        try runScrollingGameFramework(profile: .palC64, name: "pal")
    }

    func testOptInScrollingGameFrameworkNTSC() throws {
        try runScrollingGameFramework(profile: .ntscC64, name: "ntsc")
    }

    private struct FrameworkBand {
        let cells: [UInt8]
        let colors: [UInt8]
        let characters: [UInt8]
        let backgrounds: [UInt8]
        let xScroll: Int
        let originY: Int
        let rows: Range<Int>
        var blanked = false
    }

    func testScrollingGameOracleRejectsAlignmentColorAndSpriteErrors() {
        let c64 = C64()
        c64.vic.framebuffer = [UInt32](repeating: ColorPalette.rgba[6], count: VIC.screenWidth * VIC.screenHeight)
        let band = FrameworkBand(cells: [UInt8](repeating: 0, count: 1000),
                                 colors: [UInt8](repeating: 10, count: 1000),
                                 characters: [UInt8](repeating: 0x1B, count: 2048),
                                 backgrounds: [6, 5, 4], xScroll: 7, originY: 55, rows: 55..<56)
        let sprite = Sprite(x: 40, y: 54, color: 3, slot: 0, multicolor: true)
        let colors = [6, 6, 5, 5, 4, 4, 2, 2]
        let row = (55 - VIC.firstVisibleLine) * VIC.screenWidth
        for x in 31..<335 { c64.vic.framebuffer[row + x] = ColorPalette.rgba[colors[(x - 31) & 7]] }
        for x in 40..<64 { c64.vic.framebuffer[row + x] = ColorPalette.rgba[0] }
        let correct = compareFrameworkBands(c64, bands: [band], sprites: [sprite])
        XCTAssertEqual(correct.comparedPixels, 304)
        XCTAssertEqual(correct.differences, 0)
        c64.vic.framebuffer[row + 31] = ColorPalette.rgba[0]
        XCTAssertEqual(compareFrameworkBands(c64, bands: [band], sprites: [sprite]).differences, 1)
        c64.vic.framebuffer[row + 40] = ColorPalette.rgba[6]
        XCTAssertEqual(compareFrameworkBands(c64, bands: [band], sprites: [sprite]).differences, 2)
        let shifted = FrameworkBand(cells: band.cells, colors: band.colors, characters: band.characters,
                                    backgrounds: band.backgrounds, xScroll: 6, originY: 55, rows: 55..<56)
        XCTAssertGreaterThan(compareFrameworkBands(c64, bands: [shifted], sprites: [sprite]).differences, 100)
        let recolored = FrameworkBand(cells: band.cells, colors: [UInt8](repeating: 11, count: 1000),
                                      characters: band.characters, backgrounds: band.backgrounds,
                                      xScroll: 7, originY: 55, rows: 55..<56)
        XCTAssertGreaterThan(compareFrameworkBands(c64, bands: [recolored], sprites: [sprite]).differences, 50)
        var blanked = band
        blanked.blanked = true
        for x in 31..<335 { c64.vic.framebuffer[row + x] = ColorPalette.rgba[0] }
        XCTAssertEqual(compareFrameworkBands(c64, bands: [blanked], sprites: []).differences, 0)
        c64.vic.framebuffer[row + 100] = ColorPalette.rgba[6]
        XCTAssertEqual(compareFrameworkBands(c64, bands: [blanked], sprites: []).differences, 1)
    }

    private func runScrollingGameFramework(profile: MachineProfile, name: String) throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["SWIFT64_EXTERNAL_VIC_DEMOS_DIR"] else {
            throw XCTSkip("Set SWIFT64_EXTERNAL_VIC_DEMOS_DIR after fetching the public demo fixtures")
        }
        let program = try Data(contentsOf: URL(fileURLWithPath: directory)
            .appendingPathComponent("c64gameframework/exampleef.crt"))
        guard SHA256.hash(data: program).map({ String(format: "%02x", $0) }).joined() ==
                "3e1d6e2de8e7773cf6073bdf5c2a72073f1564ed38c73d9844ae57c22e87f239" else {
            return XCTFail("Framework observer requires the pinned original EasyFlash image")
        }
        let c64 = try boot(profile: profile, environment: env)
        guard c64.mountCartridge(program) else { return XCTFail("Could not mount framework cartridge") }
        c64.powerOn()
        c64.vic.recordsBusAccessTraces = false
        var rasterWrites = 0
        var updates = 0
        var sprites: [Sprite] = []
        var registers = [UInt8](repeating: 0, count: 64)
        var top: FrameworkBand?
        var panel: FrameworkBand?
        var listError: String?
        var consumedBuffers: Set<Int> = []
        var scrollPhases: Set<UInt8> = []
        func band(screen: Int, charset: Int, originY: Int, rows: Range<Int>) -> FrameworkBand {
            FrameworkBand(cells: Array(c64.memory.ram[screen..<screen + 1000]),
                          colors: Array(c64.memory.colorRAM.prefix(1000)),
                          characters: Array(c64.memory.ram[charset..<charset + 2048]),
                          backgrounds: Array(registers[0x21...0x23]),
                          xScroll: Int(registers[0x16] & 7), originY: originY, rows: rows)
        }
        for address: UInt16 in [0xD00F, 0xD011, 0xD012, 0xD015, 0xD016, 0xD018, 0xD021, 0xD022, 0xD023] {
            c64.debugger.addWatchpoint(address, type: .write)
        }
        c64.debugger.onBreak = { [weak c64] reason in
            guard let c64, case let .watchpointWrite(address, value) = reason else { return false }
            registers[Int(address & 63)] = value
            if address == 0xD012 { rasterWrites += 1 }
            if address == 0xD011, value == 0x17, c64.vic.rasterLine == 238 {
                panel = band(screen: 0xE000, charset: 0xE000, originY: 55, rows: 239..<247)
            }
            if address == 0xD015, c64.vic.rasterLine < 34, registers[0x18] == 0xEA {
                if value == 0 { sprites = [] }
                if registers[0x11] & 0x70 == 0x10, registers[0x16] & 0x18 == 0x10 {
                    // These rows have already scanned before Irq3 redraws
                    // screen/color RAM at line 145. Later rows are not frozen.
                    top = band(screen: 0xF800, charset: 0xE800,
                               originY: 48 + Int(registers[0x11] & 7), rows: 55..<135)
                    scrollPhases.insert(registers[0x16] & 7)
                } else if value == 0, registers[0x11] == 0x57, registers[0x16] == 0x57 {
                    // BlankScreen deliberately selects invalid ECM+MCM while
                    // loading an area. Check black output, not an omitted frame.
                    top = band(screen: 0xF800, charset: 0xE800, originY: 55, rows: 55..<230)
                    top?.blanked = true
                }
            }
            guard address == 0xD00F, [0, 24].contains(c64.cpu.x), c64.vic.rasterLine < 34 else { return false }
            let pc = Int(c64.cpu.pc)
            // Irq2_Spr0 starts with LDA sortSprY,X / STA $D00F. Derive the
            // original program's table address, never the VIC's sprite state.
            guard pc >= 6, c64.memory.ram[pc - 6] == 0xBD,
                  c64.memory.ram[pc - 3..<pc].elementsEqual([0x8D, 0x0F, 0xD0]) else {
                listError = String(format: "Unexpected framework sprite writer at %04X", pc)
                return false
            }
            let base = Int(c64.memory.ram[pc - 5]) | Int(c64.memory.ram[pc - 4]) << 8
            guard (48..<0xC000 - 288).contains(base) else {
                listError = "Invalid framework sprite table address \(base)"
                return false
            }
            let start = Int(c64.cpu.x)
            guard let end = (start..<start + 24).first(where: {
                c64.memory.ram[base + 96 + $0] & 128 != 0 && c64.memory.ram[base + 240 + $0] == 0
            }) else {
                listError = "Framework sprite table has no final IRQ marker"
                return false
            }
            consumedBuffers.insert(start)
            sprites = (start...end).map { index in
                let slot = 7 - ((index - start) & 7)
                let bit: UInt8 = 1 << slot
                let highIndex = index < start + 8 ? min(start + 7, end) : index
                let pointer = 0xC000 + Int(c64.memory.ram[base + 48 + index]) * 64
                return Sprite(x: Int(c64.memory.ram[base - 48 + index]) +
                                (c64.memory.ram[base + 144 + highIndex] & bit != 0 ? 256 : 0),
                              y: Int(c64.memory.ram[base + index]),
                              color: c64.memory.ram[base + 96 + index] & 15, slot: slot,
                              pattern: Array(c64.memory.ram[pointer..<pointer + 63]), multicolor: true,
                              expandedX: c64.memory.ram[base + 192 + highIndex] & bit != 0)
            }
            updates += 1
            return false
        }
        defer { c64.debugger.onBreak = nil }
        var comparedFrames = 0
        var comparedPixels = 0
        var spritePixels = 0
        var maxSprites = 0
        var mapPositions: Set<UInt8> = []
        var blankFrames: [Int] = []
        var zones: Set<UInt8> = []
        for frame in 0..<900 {
            top = nil
            panel = nil
            let previousUpdates = updates
            c64.joystick.port2 = frame >= 500 ? 0xE7 : 0xFF
            guard c64.runFrame(), !c64.cpu.jammed else {
                return XCTFail("Framework stopped at frame \(frame), PC=\(String(format: "%04X", c64.cpu.pc))")
            }
            guard listError == nil else { return XCTFail(try XCTUnwrap(listError)) }
            if frame >= 240 {
                guard let top, let panel, top.blanked || updates > previousUpdates else {
                    try capture(c64, name: "framework-\(name)-missing-\(frame)", environment: env)
                    return XCTFail("Framework \(name) lost its game/panel raster chain at frame \(frame)")
                }
                if top.blanked {
                    blankFrames.append(frame)
                    guard frame >= 500, c64.memory.ram[0xAA] == 1, blankFrames.count <= 12 else {
                        return XCTFail("Framework \(name) blanked outside its bounded zone transition")
                    }
                }
                let graphics = compareFrameworkBands(c64, bands: [top, panel], sprites: sprites)
                let spriteResult = compareDisplay(c64, sprites: sprites, spriteSharedColors: (1, 0),
                                                  spritesOnly: true, columns: 31..<335, rows: 55..<230)
                guard graphics.differences == 0, spriteResult.differences == 0 else {
                    print("Framework \(name) frame=\(frame) graphics=\(graphics.differences) \(graphics.examples) sprites=\(spriteResult.differences) \(spriteResult.examples)")
                    try capture(c64, name: "framework-\(name)-failure", environment: env)
                    return XCTFail("Framework \(name) source-data display mismatch")
                }
                comparedFrames += 1
                comparedPixels += graphics.comparedPixels
                spritePixels += spriteResult.comparedPixels
                maxSprites = max(maxSprites, sprites.count)
                mapPositions.insert(c64.memory.ram[0xE0]) // mapX in memory.s
                zones.insert(c64.memory.ram[0xAA])
            }
            if [299, 499, 699, 899].contains(frame) {
                try capture(c64, name: "framework-\(name)-\(frame)", environment: env)
            }
        }
        XCTAssertEqual(comparedFrames, 660)
        XCTAssertFalse(blankFrames.isEmpty, "Must cross the doorway and exercise loading blanking")
        XCTAssertEqual(zones, [0, 1])
        XCTAssertEqual(c64.memory.ram[0xAA], 1)
        XCTAssertGreaterThan(c64.memory.ram[0x2A], 2, "Player must move into the new zone after loading")
        XCTAssertFalse(try XCTUnwrap(top).blanked, "Gameplay must resume after the area transition")
        XCTAssertEqual(consumedBuffers, [0, 24])
        XCTAssertEqual(scrollPhases, Set(0...7))
        XCTAssertGreaterThan(mapPositions.count, 3)
        XCTAssertGreaterThan(spritePixels, 100_000)
        XCTAssertGreaterThan(rasterWrites, 500)
        print("Framework \(name): frames=\(comparedFrames), graphicsPixels=\(comparedPixels), spritePixels=\(spritePixels), maxSprites=\(maxSprites), scrollPhases=\(scrollPhases.sorted()), mapPositions=\(mapPositions.sorted()), blankFrames=\(blankFrames)")
    }

    private func compareFrameworkBands(_ c64: C64, bands: [FrameworkBand], sprites: [Sprite])
    -> (differences: Int, comparedPixels: Int, examples: [String]) {
        var differences = 0
        var comparedPixels = 0
        var examples: [String] = []
        for band in bands {
            for y in band.rows {
                let onLine = sprites.filter { y > $0.y && y <= $0.y + 21 && y < 230 }.sorted { $0.slot < $1.slot }
                for x in 31..<335 {
                    let u = x - 24 - band.xScroll
                    let v = y - band.originY
                    let cell = (v / 8) * 40 + u / 8
                    let color = band.colors[cell] & 15
                    let glyph = band.characters[Int(band.cells[cell]) * 8 + (v & 7)]
                    var expected: UInt8
                    if band.blanked {
                        expected = 0
                    } else if color & 8 != 0 {
                        let pair = Int((glyph >> (6 - (u & 6))) & 3)
                        expected = pair == 3 ? color & 7 : band.backgrounds[pair]
                    } else {
                        expected = glyph & (0x80 >> (u & 7)) != 0 ? color : band.backgrounds[0]
                    }
                    for sprite in onLine {
                        if let color = spriteColor(sprite, x: x, y: y, sharedColors: (1, 0)) {
                            expected = color
                            break
                        }
                    }
                    comparedPixels += 1
                    let actual = c64.vic.framebuffer[(y - VIC.firstVisibleLine) * VIC.screenWidth + x]
                    if actual != ColorPalette.rgba[Int(expected)] {
                        differences += 1
                        if examples.count < 12 { examples.append("(\(x),\(y)) expected=\(expected) actual=\(ColorPalette.rgba.firstIndex(of: actual) ?? -1)") }
                    }
                }
            }
        }
        return (differences, comparedPixels, examples)
    }

    private func runBefana(profile: MachineProfile, name: String, expectSortOverrun: Bool = false) throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["SWIFT64_EXTERNAL_VIC_DEMOS_DIR"] else {
            throw XCTSkip("Set SWIFT64_EXTERNAL_VIC_DEMOS_DIR after fetching the public demo fixtures")
        }
        let program = try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("befana2026.prg"))
        guard SHA256.hash(data: program).map({ String(format: "%02x", $0) }).joined() ==
                "07b03ac803f7d731e305215793b67b94f528fc00daf655f0ff395511bf43f7da" else {
            return XCTFail("Befana observer requires the original 2026 release PRG")
        }
        let c64 = try boot(profile: profile, environment: env)
        var sprites: [Sprite] = []
        var updates = 0
        var rasterWrites: [String] = []
        var listError: String?
        var sortStart: UInt64?
        var lateSort: (line: Int, cycle: Int, cycles: UInt64)?
        c64.debugger.addWatchpoint(0xD001, type: .write)
        c64.debugger.addWatchpoint(0xD012, type: .write)
        c64.debugger.onBreak = { [weak c64] reason in
            guard let c64, case let .watchpointWrite(address, value) = reason else { return false }
            if address == 0xD012 {
                rasterWrites.append(String(format: "PC=%04X line=%d:%d next=%d", c64.cpu.pc, c64.vic.rasterLine, c64.vic.rasterCycle, value))
                if rasterWrites.count > 24 { rasterWrites.removeFirst() }
                if c64.cpu.pc == 0x6C0D, value == 0, c64.vic.rasterLine > 0, c64.vic.rasterLine < 252, let sortStart {
                    lateSort = (Int(c64.vic.rasterLine), c64.vic.rasterCycle, c64.cpu.totalCycles - sortStart)
                }
                return false
            }
            if c64.cpu.pc == 0x6BB0 { sortStart = c64.cpu.totalCycles }
            guard c64.cpu.pc == 0x6CC5, c64.cpu.y == 0 else { return false }
            // IRQ3's first sprite setup consumes the completed sorted tables.
            // On NTSC, sorting can cross frame zero; frame-boundary RAM alone
            // would observe a partially sorted list, not the displayed one.
            let count = Int(c64.memory.ram[0xFC])
            guard (1...21).contains(count) else {
                listError = "Invalid source sprite count \(count)"
                return false
            }
            sprites = (0..<count).prefix { c64.memory.ram[0x6DB7 + $0] < 255 }.map { index in
                let pointer = Int(c64.memory.ram[0x6DE2 + index]) * 64
                return Sprite(x: 2 * Int(c64.memory.ram[0x6DA2 + index]),
                              y: Int(c64.memory.ram[0x6DB7 + index]),
                              color: c64.memory.ram[0x6DCD + index] & 15, slot: index & 7,
                              pattern: Array(c64.memory.ram[pointer..<pointer + 63]),
                              multicolor: c64.memory.ram[0x6DF7 + index] != 0)
            }
            updates += 1
            return false
        }
        defer { c64.debugger.onBreak = nil }
        c64.loadPRG(program, autoRun: true)
        var comparedPixels = 0
        var comparedFrames = 0
        var maxVisible = 0
        func checkFrame(_ label: String) throws -> Bool {
            let previousUpdates = updates
            guard c64.runFrame(), !c64.cpu.jammed, updates > previousUpdates, listError == nil else {
                print(rasterWrites.joined(separator: "\n"))
                try capture(c64, name: "befana-\(name)-failure", environment: env)
                XCTFail("Befana \(name) raster chain stopped at \(label)")
                return false
            }
            // The game animates character RAM while the beam is scanning.
            // Check every opaque source-sprite pixel without treating the
            // final character RAM as a reference for earlier rasterlines.
            let result = compareDisplay(c64, sprites: sprites, spriteSharedColors: (10, 15), spritesOnly: true)
            if result.differences > 0 {
                print("Befana \(name) \(label) differences=\(result.differences) \(result.examples)")
                try capture(c64, name: "befana-\(name)-failure", environment: env)
                XCTFail("Befana \(name) sprite mismatch at \(label)")
                return false
            }
            comparedPixels += result.comparedPixels
            comparedFrames += 1
            maxVisible = max(maxVisible, sprites.filter { $0.x < 344 && $0.x + 24 > 24 && $0.y < 250 && $0.y + 21 >= 51 }.count)
            return true
        }

        let authorLabel: [UInt8] = [23, 18, 9, 20, 20, 5, 14, 0, 2, 25] // WRITTEN BY
        var titleReady = false
        for _ in 0..<360 {
            guard c64.runFrame(), !c64.cpu.jammed else { return XCTFail("Befana \(name) stopped during setup") }
            if updates > 0 && c64.memory.ram[0x0400 + 735..<0x0400 + 745].elementsEqual(authorLabel) {
                titleReady = true
                break
            }
        }
        guard titleReady else { return XCTFail("Befana \(name) did not reach its title within 360 frames") }
        if expectSortOverrun {
            // This is a program-timing diagnostic, NOT an NTSC gameplay pass.
            // The original sorter starts on line 252, then schedules the tune
            // IRQ for line zero. Its long title sort outlives the NTSC border.
            lateSort = nil
            for frame in 0..<60 {
                let previousUpdates = updates
                guard c64.runFrame(), !c64.cpu.jammed else { return XCTFail("Befana NTSC CPU stopped") }
                if let lateSort {
                    XCTAssertGreaterThan(lateSort.cycles, UInt64((VIC.ntscRasterLinesPerFrame - 252) * VIC.ntscCyclesPerLine))
                    XCTAssertEqual(updates, previousUpdates, "The missed IRQ cannot produce a sprite list before next raster zero")
                    for _ in 0..<2 { XCTAssertTrue(c64.runFrame()) }
                    XCTAssertGreaterThan(updates, previousUpdates, "The raster chain must resume, not hang the CPU")
                    print("Befana NTSC timing limit: title frame \(frame), line-zero IRQ scheduled at \(lateSort.line):\(lateSort.cycle) after \(lateSort.cycles) sorter clocks; skipped update reproduced, not a gameplay pass")
                    return
                }
            }
            return XCTFail("Befana NTSC deadline diagnostic changed; reassess the original-program timing limit")
        }
        for frame in 0..<240 {
            guard try checkFrame("title frame \(frame)") else { return }
        }
        try capture(c64, name: "befana-\(name)-title", environment: env)

        c64.joystick.port2 = 0xEF
        var gameReady = false
        for _ in 0..<180 {
            let previousUpdates = updates
            guard c64.runFrame(), !c64.cpu.jammed else { return XCTFail("Befana \(name) stopped while starting game") }
            if c64.memory.ram[0xFA] == 0, c64.memory.ram[0xFC] == 16, updates > previousUpdates,
               c64.memory.ram[0x0400..<0x0405].elementsEqual([19, 3, 15, 18, 5]) {
                gameReady = true
                break
            }
        }
        guard gameReady else { return XCTFail("Befana \(name) did not enter gameplay after Fire") }
        var positions: [Int: (x: UInt8, y: UInt8)] = [:]
        for frame in 0..<1500 {
            switch frame {
            case 120..<144: c64.joystick.port2 = 0xE7 // Fire + right
            case 144..<168: c64.joystick.port2 = 0xEB // Fire + left
            case 168..<192: c64.joystick.port2 = 0xED // Fire + down
            case 192..<216: c64.joystick.port2 = 0xEE // Fire + up
            default: c64.joystick.port2 = 0xEF
            }
            guard try checkFrame("game frame \(frame)") else { return }
            if [119, 143, 167, 191, 215].contains(frame) {
                positions[frame] = (c64.memory.ram[0x6D39 + 9], c64.memory.ram[0x6D4E + 9])
            }
        }
        XCTAssertGreaterThan(try XCTUnwrap(positions[143]).x, try XCTUnwrap(positions[119]).x)
        XCTAssertLessThan(try XCTUnwrap(positions[167]).x, try XCTUnwrap(positions[143]).x)
        XCTAssertGreaterThan(try XCTUnwrap(positions[191]).y, try XCTUnwrap(positions[167]).y)
        XCTAssertLessThan(try XCTUnwrap(positions[215]).y, try XCTUnwrap(positions[191]).y)
        XCTAssertEqual(comparedFrames, 1740)
        XCTAssertGreaterThan(comparedPixels, 500_000)
        XCTAssertGreaterThan(maxVisible, 16)
        let score = try XCTUnwrap(Int(String(bytes: c64.memory.ram[0x0405..<0x040A], encoding: .ascii) ?? ""))
        let level = try XCTUnwrap(Int(String(bytes: c64.memory.ram[0x040D..<0x040F], encoding: .ascii) ?? ""))
        let lives = try XCTUnwrap(Int(String(bytes: c64.memory.ram[0x0427...0x0427], encoding: .ascii) ?? ""))
        XCTAssertGreaterThan(score, 0, "Firing must score against targets")
        XCTAssertGreaterThanOrEqual(level, 2, "Gameplay must advance beyond the first level")
        XCTAssertTrue((1...2).contains(lives), "Must resume gameplay after losing a life")
        XCTAssertNil(lateSort, "PAL must meet the sorter deadline throughout the run")
        try capture(c64, name: "befana-\(name)-gameplay", environment: env)
        print("Befana \(name): frames=\(comparedFrames) exactSpritePixels=\(comparedPixels) maxVisible=\(maxVisible) score=\(score) level=\(level) lives=\(lives)")
    }

    func testSpriteOnlyOracleChecksSharedColorsAndOpaqueCoverage() {
        let c64 = C64()
        c64.vic.framebuffer = [UInt32](repeating: ColorPalette.rgba[9], count: VIC.screenWidth * VIC.screenHeight)
        let sprite = Sprite(x: 40, y: 60, color: 7, slot: 0,
                            pattern: [UInt8](repeating: 0x1B, count: 63), multicolor: true)
        let pairs: [UInt8?] = [nil, nil, 10, 10, 7, 7, 15, 15]
        for y in 61...81 {
            for x in 40..<64 {
                if let color = pairs[(x - 40) % 8] {
                    c64.vic.framebuffer[(y - VIC.firstVisibleLine) * VIC.screenWidth + x] = ColorPalette.rgba[Int(color)]
                }
            }
        }
        let correct = compareDisplay(c64, sprites: [sprite], spriteSharedColors: (10, 15), spritesOnly: true)
        XCTAssertEqual(correct.differences, 0)
        XCTAssertEqual(correct.comparedPixels, 18 * 21, "Background/transparent pixels must not inflate sprite proof coverage")
        c64.vic.framebuffer[(61 - VIC.firstVisibleLine) * VIC.screenWidth + 46] = ColorPalette.rgba[13]
        XCTAssertEqual(compareDisplay(c64, sprites: [sprite], spriteSharedColors: (10, 15), spritesOnly: true).differences, 1)
    }

    func testMulticolorOracleDecodesTransparencyAndExpansion() {
        let pattern = [UInt8](repeating: 0x1B, count: 63) // 00, 01, 10, 11
        let normal = Sprite(x: 40, y: 60, color: 7, slot: 0, pattern: pattern, multicolor: true)
        let expected: [UInt8?] = [nil, nil, 10, 10, 7, 7, 13, 13]
        XCTAssertEqual((40..<64).map { spriteColor(normal, x: $0, y: 61) }, expected + expected + expected)
        var expanded = normal
        expanded.expandedX = true
        expanded.expandedY = true
        let doubled = expected.flatMap { [$0, $0] }
        XCTAssertEqual((40..<88).map { spriteColor(expanded, x: $0, y: 102) }, doubled + doubled + doubled)
        XCTAssertNil(spriteColor(expanded, x: 44, y: 60))
        XCTAssertNil(spriteColor(expanded, x: 44, y: 103))
        XCTAssertNil(spriteColor(expanded, x: 88, y: 61))
        XCTAssertNil(spriteColor(normal, x: 42, y: 82))
    }

    func testBackgroundPriorityOracleDoesNotRevealLowerSprite() {
        let c64 = C64()
        c64.memory.charROM = [UInt8](repeating: 255, count: 4096)
        c64.memory.colorRAM = [UInt8](repeating: 9, count: 1024)
        c64.vic.framebuffer = [UInt32](repeating: ColorPalette.rgba[9], count: VIC.screenWidth * VIC.screenHeight)
        let sprites = [Sprite(x: 40, y: 60, color: 5, slot: 0, behindBackground: true),
                       Sprite(x: 52, y: 60, color: 2, slot: 1)]
        for y in 61...81 {
            for x in 64..<76 {
                c64.vic.framebuffer[(y - VIC.firstVisibleLine) * VIC.screenWidth + x] = ColorPalette.rgba[2]
            }
        }
        let correct = compareDisplay(c64, sprites: sprites)
        XCTAssertEqual(correct.differences, 0)
        XCTAssertEqual(correct.backgroundOcclusions, 24 * 21)
        c64.vic.framebuffer[(61 - VIC.firstVisibleLine) * VIC.screenWidth + 52] = ColorPalette.rgba[2]
        XCTAssertEqual(compareDisplay(c64, sprites: sprites).differences, 1)
    }

    private func runPiper(profile: MachineProfile, name: String) throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["SWIFT64_EXTERNAL_VIC_DEMOS_DIR"] else {
            throw XCTSkip("Set SWIFT64_EXTERNAL_VIC_DEMOS_DIR after fetching the public demo fixtures")
        }
        let program = try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("piper/TestMultiplexor9.prg"))
        guard SHA256.hash(data: program).map({ String(format: "%02x", $0) }).joined() ==
                "2c390034bf745230012de9162569cf11bb44e4a728cf34ca180a850348d72f28" else {
            return XCTFail("Piper oracle requires the original TestMultiplexor9.prg")
        }
        let c64 = try boot(profile: profile, environment: env)
        c64.loadPRG(program, autoRun: true)
        for _ in 0..<24 { XCTAssertTrue(c64.runFrame()) }
        var overlapPixels = 0
        var backgroundOcclusions = 0
        for frame in 0..<240 {
            let count = Int(c64.memory.ram[0x4E])
            guard count == 24 else { return XCTFail("Piper sorter has \(count) sprites, expected 24") }
            guard Set(c64.memory.ram[0x55..<0x55 + count]) == Set(UInt8(0)..<24) else {
                return XCTFail("Piper's sorted table lost or duplicated a logical sprite")
            }
            // TestBuildOptions9 + AssemblePost: sorted indices at $55, with
            // source arrays separate from the hardware registers and DMA state.
            let sprites = (0..<count).map { index -> Sprite in
                let item = Int(c64.memory.ram[0x55 + index])
                let pointer = Int(c64.memory.ram[0x1678 + item]) * 64
                return Sprite(x: Int(c64.memory.ram[0x1A + item]) + 256 * Int(c64.memory.ram[0x32 + item]),
                              y: Int(c64.memory.ram[0x02 + item]), color: c64.memory.ram[0x1660 + item] & 15,
                              slot: index & 7, pattern: Array(c64.memory.ram[pointer..<pointer + 63]),
                              multicolor: c64.memory.ram[0x1600 + item] != 0,
                              expandedX: c64.memory.ram[0x1630 + item] != 0,
                              expandedY: c64.memory.ram[0x1648 + item] != 0,
                              behindBackground: c64.memory.ram[0x1618 + item] != 0)
            }
            XCTAssertEqual(sprites.filter(\.multicolor).count, 14)
            XCTAssertEqual(sprites.filter(\.expandedX).count, 14)
            XCTAssertEqual(sprites.filter(\.expandedY).count, 9)
            XCTAssertEqual(sprites.filter(\.behindBackground).count, 14)
            XCTAssertEqual(Set(sprites.compactMap(\.pattern)).count, 4)
            let movingX = c64.memory.ram[0x1E]
            guard c64.runFrame(), !c64.cpu.jammed else { return XCTFail("Piper \(name) stopped at frame \(frame)") }
            XCTAssertEqual(c64.memory.ram[0x1E], movingX &+ 1, "The original bottom IRQ must move sprite 4 every frame")
            XCTAssertEqual(Array(c64.memory.ram[0x0400..<0x0403]), [1, 2, 3], "Original demo's IRQ register-preservation check")
            let result = compareDisplay(c64, sprites: sprites, background: 0)
            overlapPixels += result.overlapPixels
            backgroundOcclusions += result.backgroundOcclusions
            if result.differences > 0 {
                print("Piper \(name) frame=\(frame) differences=\(result.differences) \(result.examples)")
                print(sprites.map { "slot\($0.slot):\($0.x),\($0.y),\($0.color),mc=\($0.multicolor),x2=\($0.expandedX),y2=\($0.expandedY),behind=\($0.behindBackground)" }.joined(separator: " "))
                try capture(c64, name: "piper-\(name)-failure", environment: env)
                return XCTFail("Piper \(name) display mismatch at frame \(frame)")
            }
        }
        XCTAssertGreaterThan(overlapPixels, 1000)
        XCTAssertGreaterThan(backgroundOcclusions, 1000)
        print("Piper \(name): 240 exact mixed-mode display frames, overlapPixels=\(overlapPixels), backgroundOcclusions=\(backgroundOcclusions)")
        try capture(c64, name: "piper-\(name)", environment: env)
    }

    private func runHessian(profile: MachineProfile, name: String) throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["SWIFT64_EXTERNAL_VIC_DEMOS_DIR"] else {
            throw XCTSkip("Set SWIFT64_EXTERNAL_VIC_DEMOS_DIR after fetching the public demo fixtures")
        }
        let root = URL(fileURLWithPath: directory)
        let program = try Data(contentsOf: root.appendingPathComponent("cadaver-multi2/multi2.prg"))
        guard SHA256.hash(data: program).map({ String(format: "%02x", $0) }).joined() ==
                "9db03c429e69fc4a83f70511dfbbadfed68849ef55d028c55f4d82ea6e2fd880" else {
            return XCTFail("The source-based oracle requires the original, unmodified multi2.prg")
        }
        let c64 = try boot(profile: profile, environment: env)
        var sprites: [Sprite] = []
        var updates = 0
        var listError: String?
        var consumedBuffers = Set<Int>()
        c64.debugger.addWatchpoint(0x0005, type: .write)
        c64.debugger.onBreak = { [weak c64] reason in
            guard let c64,
                  case let .watchpointWrite(address, value) = reason,
                  address == 5, value == 0, c64.cpu.pc == 0x1206 else { return false }
            // irq1 consumes the next list here, before releasing the main loop.
            // These addresses are from the bundled source and unpacked PRG,
            // not VIC state or a framebuffer captured from Swift64.
            let start = Int(c64.memory.ram[6])
            let end = Int(c64.memory.ram[7])
            guard [0, 24].contains(start), (start...start + 24).contains(end) else {
                listError = "Invalid doublebuffer range \(start)..<\(end)"
                return false
            }
            consumedBuffers.insert(start)
            sprites = (start..<end).map { index in
                let slot = (index - start) & 7
                let highIndex = index < start + 8 ? min(start + 8, end) - 1 : index
                let high = c64.memory.ram[0x143B + highIndex] & (1 << slot) != 0
                return Sprite(x: Int(c64.memory.ram[0x140B + index]) + (high ? 256 : 0),
                              y: Int(c64.memory.ram[0x146B + index]),
                              color: c64.memory.ram[0x14CB + index] & 15, slot: slot)
            }
            updates += 1
            return false
        }
        defer { c64.debugger.onBreak = nil }
        c64.loadPRG(program, autoRun: true)
        var comparedFrames = 0
        var highXSprites = 0
        var maxSprites = 0
        var maxVisibleSprites = 0
        var overlapPixels = 0
        for frame in 0..<264 {
            guard c64.runFrame(), !c64.cpu.jammed else { return XCTFail("\(name): CPU stopped at frame \(frame)") }
            guard listError == nil else { return XCTFail(try XCTUnwrap(listError)) }
            if frame < 24 { continue }
            guard updates > 0 else { return XCTFail("\(name): demo did not consume its first sprite list") }
            XCTAssertEqual(c64.memory.ram[0x0FC0..<0x1000], [UInt8](repeating: 255, count: 64)[...])
            maxSprites = max(maxSprites, sprites.count)
            maxVisibleSprites = max(maxVisibleSprites, sprites.filter {
                $0.x < 344 && $0.x + 24 > 24 && $0.y < 250 && $0.y + 21 >= 51
            }.count)
            highXSprites += sprites.filter { $0.x >= 256 && $0.x < 344 }.count
            let result = compareDisplay(c64, sprites: sprites)
            overlapPixels += result.overlapPixels
            if result.differences > 0 {
                print("Hessian \(name) frame=\(frame) sprites=\(sprites.count) differences=\(result.differences) \(result.examples)")
                print(sprites.map { "slot\($0.slot):\($0.x),\($0.y),\($0.color)" }.joined(separator: " "))
                try capture(c64, name: "multi2-\(name)-failure", environment: env)
                return XCTFail("\(name): sprite-list display mismatch at frame \(frame)")
            }
            comparedFrames += 1
        }
        XCTAssertEqual(comparedFrames, 240)
        XCTAssertGreaterThan(updates, 230, "A stuck raster IRQ must not pass on one static image")
        XCTAssertEqual(consumedBuffers, [0, 24])
        XCTAssertGreaterThan(maxSprites, 16, "Must exercise at least three uses of hardware sprite slots")
        XCTAssertGreaterThan(maxVisibleSprites, 16, "Reused sprites must appear inside the visible display")
        XCTAssertGreaterThan(highXSprites, 100, "Must exercise 9-bit X coordinates repeatedly")
        XCTAssertGreaterThan(overlapPixels, 1000, "Must exercise overlapping sprite priority repeatedly")
        print("Hessian \(name): \(comparedFrames) exact display frames, updates=\(updates), maxSprites=\(maxSprites), maxVisible=\(maxVisibleSprites), highXSprites=\(highXSprites), overlapPixels=\(overlapPixels)")
        try capture(c64, name: "multi2-\(name)", environment: env)
    }

    private func compareDisplay(_ c64: C64, sprites: [Sprite], background: UInt8 = 6,
                                spriteSharedColors: (UInt8, UInt8) = (10, 13), spritesOnly: Bool = false,
                                columns: Range<Int> = 24..<344, rows: Range<Int> = 51..<251)
    -> (differences: Int, comparedPixels: Int, overlapPixels: Int, backgroundOcclusions: Int, examples: [String]) {
        var differences = 0
        var comparedPixels = 0
        var overlapPixels = 0
        var backgroundOcclusions = 0
        var examples: [String] = []
        for y in rows {
            let onLine = sprites.filter { y > $0.y && y <= $0.y + ($0.expandedY ? 42 : 21) }.sorted { $0.slot < $1.slot }
            for x in columns {
                let cell = ((y - 51) / 8) * 40 + (x - 24) / 8
                let character = Int(c64.memory.ram[0x0400 + cell])
                let glyph = c64.memory.charROM[character * 8 + (y - 51) % 8]
                let ink = !spritesOnly && glyph & (0x80 >> ((x - 24) % 8)) != 0
                var expected = ink ? c64.memory.colorRAM[cell] & 15 : background
                var winner: Int?
                for sprite in onLine {
                    guard let color = spriteColor(sprite, x: x, y: y, sharedColors: spriteSharedColors) else { continue }
                    if winner != nil {
                        overlapPixels += 1
                        break
                    }
                    winner = sprite.slot
                    if ink && sprite.behindBackground {
                        backgroundOcclusions += 1
                    } else {
                        expected = color
                    }
                }
                if spritesOnly && winner == nil { continue }
                comparedPixels += 1
                let actual = c64.vic.framebuffer[(y - VIC.firstVisibleLine) * VIC.screenWidth + x]
                if actual != ColorPalette.rgba[Int(expected)] {
                    differences += 1
                    if examples.count < 12 {
                        examples.append("(\(x),\(y)) expected=\(expected) actual=\(ColorPalette.rgba.firstIndex(of: actual) ?? -1)")
                    }
                }
            }
        }
        return (differences, comparedPixels, overlapPixels, backgroundOcclusions, examples)
    }

    private func spriteColor(_ sprite: Sprite, x: Int, y: Int, sharedColors: (UInt8, UInt8) = (10, 13)) -> UInt8? {
        let column = x - sprite.x
        let row = y - sprite.y - 1
        guard column >= 0, column < (sprite.expandedX ? 48 : 24),
              row >= 0, row < (sprite.expandedY ? 42 : 21) else { return nil }
        let u = column / (sprite.expandedX ? 2 : 1)
        let v = row / (sprite.expandedY ? 2 : 1)
        let byte = sprite.pattern?[v * 3 + u / 8] ?? 255
        if !sprite.multicolor { return byte & (0x80 >> (u & 7)) == 0 ? nil : sprite.color }
        switch (byte >> (6 - (u & 6))) & 3 {
        case 0: return nil
        case 1: return sharedColors.0
        case 2: return sprite.color
        default: return sharedColors.1
        }
    }

    private func boot(profile: MachineProfile, environment: [String: String]) throws -> C64 {
        let romRoot = URL(fileURLWithPath: environment["SWIFT64_PUBLIC_VIC_ROM_DIR"] ?? "Sources/C64App/ROMS")
        let c64 = C64(machineProfile: profile)
        try c64.loadROMsValidated(
            basic: Data(contentsOf: romRoot.appendingPathComponent("C64-901226-01-Commodore-F833D117-Basic.rom")),
            kernal: Data(contentsOf: romRoot.appendingPathComponent("C64-901227-03-Commodore-DBE3E7C7-Kernal.rom")),
            charset: Data(contentsOf: romRoot.appendingPathComponent("C64-901225-01-Commodore-EC4272EE-Characters.rom")))
        c64.trueDriveEmulationMode = .off
        c64.kernalTraps.enabled = false
        c64.powerOn()
        c64.vic.recordsBusAccessTraces = false
        let ready: [UInt8] = [18, 5, 1, 4, 25, 46]
        for _ in 0..<300 {
            XCTAssertTrue(c64.runFrame())
            if (0...994).contains(where: { c64.memory.ram[0x0400 + $0..<0x0400 + $0 + ready.count].elementsEqual(ready) }) {
                return c64
            }
        }
        XCTFail("BASIC boot timed out")
        throw NSError(domain: "ExternalVICDemoTests", code: 1)
    }

    private func capture(_ c64: C64, name: String, environment: [String: String]) throws {
        if let directory = environment["SWIFT64_EXTERNAL_VIC_CAPTURE_DIR"] {
            let output = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            var ppm = Data("P6\n\(VIC.screenWidth) \(VIC.screenHeight)\n255\n".utf8)
            for pixel in c64.vic.framebuffer {
                ppm.append(contentsOf: [UInt8(truncatingIfNeeded: pixel), UInt8(truncatingIfNeeded: pixel >> 8), UInt8(truncatingIfNeeded: pixel >> 16)])
            }
            try ppm.write(to: output.appendingPathComponent(name + ".ppm"))
        }
    }
}
