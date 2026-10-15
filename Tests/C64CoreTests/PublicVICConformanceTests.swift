import XCTest
import AppKit
@testable import C64Core

final class PublicVICConformanceTests: XCTestCase {
    private enum ReferenceArea {
        case palDisplay, ntscDisplay, palBorder

        var crop: (x: Int, y: Int, width: Int, height: Int, imageHeight: Int, rasterTop: Int) {
            switch self {
            case .palDisplay: return (32, 35, 320, 200, 272, 16)
            case .ntscDisplay: return (32, 23, 320, 200, 247, 28)
            // Intersection of VICE's PAL crop with Swift64's physical X>=0 crop.
            case .palBorder: return (8, 0, 376, 272, 272, 16)
            }
        }
    }

    private struct Fixture {
        let id: String
        let path: String
        let profile: MachineProfile
        var referenceArea: ReferenceArea? = nil
        var knownPixelMismatches: Int? = nil
    }

    private let fixtures = [
        Fixture(id: "phi1-pal", path: "phi1timing/phi1timing.prg", profile: .palC64),
        Fixture(id: "phi1-ntsc", path: "phi1timing/phi1timing_ntsc.prg", profile: .ntscC64),
        Fixture(id: "sprite-collision-pal", path: "spritecollisions/sprite-sprite-collision-cycle.prg", profile: .palC64),
        Fixture(id: "graphics-collision-pal", path: "spritecollisions/sprite-gfx-collision-cycle.prg", profile: .palC64),
        Fixture(id: "blackmail-fli-pal", path: "flibug/blackmail-fixed.prg", profile: .palC64, referenceArea: .palDisplay, knownPixelMismatches: 5_558),
        Fixture(id: "graphics-fetch-pal", path: "gfxfetch/gfxfetch.prg", profile: .palC64, referenceArea: .palDisplay),
        Fixture(id: "graphics-fetch-ntsc", path: "gfxfetch/gfxfetch_ntsc.prg", profile: .ntscC64, referenceArea: .ntscDisplay)
    ] + ["20", "21", "22", "29", "2A", "2B"].map {
        Fixture(id: "fld-\($0.lowercased())-pal", path: "fldscroll/fldscroll-\($0)-60.prg", profile: .palC64, referenceArea: .palDisplay)
    } + ["54", "57"].flatMap { timing in
        [Fixture(id: "sprite-dma-\(timing)-pal", path: "spritedma/d017-\(timing).prg", profile: .palC64, referenceArea: .palDisplay),
         Fixture(id: "sprite-dma-\(timing)-ntsc", path: "spritedma/d017-\(timing)_ntsc.prg", profile: .ntscC64, referenceArea: .ntscDisplay)]
    } + ["vborder-32-08", "vborder-32-09", "vborder-33-08", "vborder-33-09",
         "vborder2-21", "vborder2-22", "vborder2-35", "vborder2-36", "vborder2-63", "vborder2-64",
         "hvborder1", "hvborder2", "border-bm-idle", "border-bm-ysh", "border-bm-ysh2", "border-mcbm"].map {
        Fixture(id: "\($0)-pal", path: "border/\($0).prg", profile: .palC64, referenceArea: .palBorder)
    } + ["ss-hires-mc", "ss-hires-mc-exp", "ss-mc-hires", "ss-mc-hires-exp",
         "ss-hires-color", "ss-mc-color0", "ss-mc-color1", "ss-mc-color2", "ss-xpos",
         "ss-unexp-exp-hires", "ss-exp-unexp-hires", "ss-unexp-exp-mc", "ss-exp-unexp-mc",
         "ss-pri", "ss-pri-exp", "ss-pri-mc", "ss-pri-mc-exp"].map {
        Fixture(id: "\($0)-pal", path: "spritesplit/\($0).prg", profile: .palC64, referenceArea: .palBorder)
    }

    func testOptInPublicVICPrograms() throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["SWIFT64_PUBLIC_VIC_TESTPROGS_DIR"], !directory.isEmpty else {
            throw XCTSkip("Set SWIFT64_PUBLIC_VIC_TESTPROGS_DIR after running script/fetch_vic_testprogs.sh")
        }
        let requested = Set((env["SWIFT64_PUBLIC_VIC_TEST_IDS"] ?? fixtures.map(\.id).joined(separator: ","))
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let unknown = requested.subtracting(fixtures.map(\.id))
        guard !requested.isEmpty, unknown.isEmpty else {
            XCTFail("Invalid VIC fixture selection: \(requested.sorted())")
            return
        }
        let root = URL(fileURLWithPath: directory)
        let romRoot = URL(fileURLWithPath: env["SWIFT64_PUBLIC_VIC_ROM_DIR"] ?? "Sources/C64App/ROMS")
        let basic = try Data(contentsOf: romRoot.appendingPathComponent("C64-901226-01-Commodore-F833D117-Basic.rom"))
        let kernal = try Data(contentsOf: romRoot.appendingPathComponent("C64-901227-03-Commodore-DBE3E7C7-Kernal.rom"))
        let charset = try Data(contentsOf: romRoot.appendingPathComponent("C64-901225-01-Commodore-EC4272EE-Characters.rom"))

        for fixture in fixtures where requested.contains(fixture.id) {
            try autoreleasepool {
                let program = try Data(contentsOf: root.appendingPathComponent("VICII/" + fixture.path))
                let c64 = C64(machineProfile: fixture.profile)
                try c64.loadROMsValidated(basic: basic, kernal: kernal, charset: charset)
                c64.trueDriveEmulationMode = .off
                c64.kernalTraps.enabled = false
                c64.powerOn()
                c64.vic.recordsBusAccessTraces = false
                let ready: [UInt8] = [18, 5, 1, 4, 25, 46]
                var reachedReady = false
                for _ in 0..<300 {
                    XCTAssertTrue(c64.runFrame())
                    reachedReady = (0...994).contains { offset in
                        c64.memory.ram[0x0400 + offset..<0x0400 + offset + ready.count].elementsEqual(ready)
                    }
                    if reachedReady { break }
                }
                guard reachedReady else {
                    for row in 0..<8 {
                        print("boot row \(row): " + c64.memory.ram[0x0400 + row * 40..<0x0400 + (row + 1) * 40].map { String(format: "%02X", $0) }.joined(separator: " "))
                    }
                    XCTFail("\(fixture.id): BASIC did not reach READY before loading at $\(String(format: "%04X", c64.cpu.pc))")
                    return
                }

                var result: UInt8?
                var collisionReads: [String] = []
                c64.memory.onCPURead = { [weak c64] address, value in
                    guard let c64, address == 0xD01E || address == 0xD01F,
                          collisionReads.count < 90 else { return }
                    collisionReads.append(String(format: "$%04X=%02X line=%d cycle=%d X=%d", address, value, c64.vic.rasterLine, c64.vic.rasterCycle, c64.vic.spriteX[0]))
                }
                c64.debugger.addWatchpoint(0xD7FF, type: .write)
                let traceRaster = env["SWIFT64_PUBLIC_VIC_TRACE_RASTER"] == "1"
                let traceAfterCycles = max(0, Int(env["SWIFT64_PUBLIC_VIC_TRACE_AFTER_CYCLES"] ?? "0") ?? 0)
                let tracedRegisters: Set<UInt16> = [0xD000, 0xD011, 0xD016, 0xD018, 0xD01B, 0xD01C, 0xD01D,
                                                    0xD020, 0xD021, 0xD025, 0xD026, 0xD027]
                if traceRaster {
                    for address in tracedRegisters { c64.debugger.addWatchpoint(address, type: .write) }
                }
                var rasterWrites = 0
                var cycles = 0
                c64.debugger.onBreak = { reason in
                    if case let .watchpointWrite(address, value) = reason {
                        if address == 0xD7FF { result = value }
                        if traceRaster, cycles >= traceAfterCycles, tracedRegisters.contains(address), rasterWrites < 100 {
                            rasterWrites += 1
                            print("VIC write \(fixture.id) line=\(c64.vic.rasterLine) cycle=\(c64.vic.rasterCycle) register=\(String(format: "%04X", address)) value=\(value) RC=\(c64.vic.rowCounter) VC=\(c64.vic.videoCounter) BASE=\(c64.vic.videoCounterBase) active=\(c64.vic.displayActive) vertical=\(c64.vic.verticalBorderActive) main=\(c64.vic.horizontalBorderActive)")
                        }
                    }
                    return false
                }
                defer {
                    c64.debugger.onBreak = nil
                    c64.memory.onCPURead = nil
                }
                // Use BASIC RUN and the fixture's own SYS stub, setup, and IRQ
                // vectors. Never patch code or infer completion from a PC scan.
                c64.loadPRG(program, autoRun: true)
                while result == nil && !c64.cpu.jammed && cycles < 3_000_000 {
                    c64.tickOneCycle()
                    cycles += 1
                }
                let pc = String(format: "%04X", c64.cpu.pc)
                print("Public VIC \(fixture.id): result=\(result.map(String.init) ?? "timeout") cycles=\(cycles) PC=$\(pc) raster=\(c64.vic.rasterLine):\(c64.vic.rasterCycle)")
                if result != 0 {
                    if fixture.id.hasPrefix("phi1-") {
                        print("phi1 bytes: " + c64.memory.ram[0x0D00..<0x0D42].map { String(format: "%02X", $0) }.joined(separator: " "))
                    } else {
                        let graphics = fixture.id == "graphics-collision-pal"
                        let measuredBase = graphics ? 0x0450 : 0x0428
                        let referenceBase = graphics ? 0x0428 : 0x0450
                        let count = graphics ? 40 : 7
                        let measured = c64.memory.ram[measuredBase..<measuredBase + count].map { String(format: "%02X", $0) }.joined(separator: " ")
                        let reference = c64.memory.ram[referenceBase..<referenceBase + count].map { String(format: "%02X", $0) }.joined(separator: " ")
                        print("screen result=\(measured) reference=\(reference)")
                    }
                    if !collisionReads.isEmpty { print(collisionReads.joined(separator: "\n")) }
                }
                XCTAssertFalse(c64.cpu.jammed, "\(fixture.id): CPU jam at $\(pc)")
                XCTAssertNotNil(result, "\(fixture.id): no $D7FF completion within \(cycles) cycles at $\(pc)")
                XCTAssertEqual(result, 0, "\(fixture.id): public fixture reported failure")
                if let area = fixture.referenceArea, result == 0 {
                    let programURL = root.appendingPathComponent("VICII/" + fixture.path)
                    let reference = programURL.deletingLastPathComponent().appendingPathComponent("references/" + programURL.lastPathComponent + ".png")
                    try compareFrame(c64.vic.framebuffer, reference: reference, area: area,
                                     id: fixture.id, knownPixelMismatches: fixture.knownPixelMismatches)
                }
            }
        }
    }

    private func compareFrame(_ pixels: [UInt32], reference: URL, area: ReferenceArea, id: String,
                              knownPixelMismatches: Int?) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: reference)))
        let crop = area.crop
        XCTAssertEqual(bitmap.pixelsWide, 384)
        XCTAssertEqual(bitmap.pixelsHigh, crop.imageHeight)
        guard bitmap.pixelsWide == 384, bitmap.pixelsHigh == crop.imageHeight else { return }
        // The upstream Makefile explicitly selects the pepto-pal palette.
        // Compare color indices, not this emulator's different RGB palette.
        let referencePalette: [UInt32] = [
            0x000000, 0xFFFFFF, 0x68372B, 0x70A4B2, 0x6F3D86, 0x588D43, 0x352879, 0xB8C76F,
            0x6F4F25, 0x433900, 0x9A6759, 0x444444, 0x6C6C6C, 0x9AD284, 0x6C5EB5, 0x959595
        ]
        let actualPalette = Dictionary(uniqueKeysWithValues: ColorPalette.rgba.enumerated().map { ($0.element, $0.offset) })
        var mismatches = 0
        var examples: [String] = []
        var components = [Int](repeating: 0, count: 4)
        for y in 0..<crop.height {
            for x in 0..<crop.width {
                bitmap.getPixel(&components, atX: crop.x + x, y: crop.y + y)
                let rgb = UInt32(components[0]) << 16 | UInt32(components[1]) << 8 | UInt32(components[2])
                let expected = try XCTUnwrap(referencePalette.firstIndex(of: rgb), String(format: "Unknown reference color %06X", rgb))
                let actualY = crop.rasterTop + crop.y + y - VIC.firstVisibleLine
                let actualX = crop.x + x - 8
                let actual = actualPalette[pixels[actualY * VIC.screenWidth + actualX]]
                if actual != expected {
                    mismatches += 1
                    if examples.count < 16 { examples.append("(\(x),\(y))=\(actual ?? -1), expected \(expected)") }
                }
            }
        }
        print("Public VIC \(id): \(mismatches)/\(crop.width * crop.height) pixel differences; \(examples.joined(separator: "; "))")
        if let knownPixelMismatches {
            print("Public VIC \(id): knownFailure=vic expectedPixelMismatches=\(knownPixelMismatches)")
            XCTAssertEqual(mismatches, knownPixelMismatches, "\(id): known failure changed; re-evaluate its classification")
            XCTExpectFailure("\(id): unresolved FLI row alignment; not a compatibility pass") {
                XCTAssertEqual(mismatches, 0, "\(id): display differs from upstream reference")
            }
        } else {
            XCTAssertEqual(mismatches, 0, "\(id): display differs from upstream reference")
        }
        if let directory = ProcessInfo.processInfo.environment["SWIFT64_PUBLIC_VIC_CAPTURE_DIR"] {
            let url = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var ppm = Data("P6\n\(VIC.screenWidth) \(VIC.screenHeight)\n255\n".utf8)
            for pixel in pixels { ppm.append(contentsOf: [UInt8(truncatingIfNeeded: pixel), UInt8(truncatingIfNeeded: pixel >> 8), UInt8(truncatingIfNeeded: pixel >> 16)]) }
            try ppm.write(to: url.appendingPathComponent(id + ".ppm"))
        }
    }
}
