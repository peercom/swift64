import XCTest
@testable import C64Core

/// Opt-in runner for the REU section of the pinned VICE test-program
/// collection (fetched by `script/fetch_reu_testprogs.sh`, never committed).
/// Every program boots unmodified through BASIC `RUN` on a PAL C64 with the
/// unit size its readme expects, and reports through the `$D7FF` test port.
/// Visual timing programs are included for their completion value only; their
/// reference images are not compared here.
final class PublicREUConformanceTests: XCTestCase {
    struct Fixture {
        let id: String
        let path: String
        let model: REU.Model
        var maxCycles: Int
    }

    static let fixtures: [Fixture] = {
        var list: [Fixture] = []
        func add(_ id: String, _ path: String, _ model: REU.Model = .reu1750, cycles: Int = 100_000_000) {
            list.append(Fixture(id: id, path: path, model: model, maxCycles: cycles))
        }
        add("toc64", "64ktransfer/toc64.prg")
        add("toreu", "64ktransfer/toreu.prg")
        add("badoublewrite", "badoublewrite/badoublewrite.prg")
        add("colorram", "colorram/colorram.prg")
        add("cpuport", "cpuport/cpuport.prg")
        add("detectreu", "detectsize/detectreu.prg")
        // The floating-bus probes expect a 256K unit with unpopulated banks.
        for name in ["floating", "floating-a", "floating-b", "floating3a", "floating3b",
                     "floating4a", "floating4b", "floating4c", "floating4d"] {
            add(name, "floatingbus/\(name).prg", .reu1764, cycles: 300_000_000)
        }
        add("ioglitch", "ioglitch/ioglitch.prg")
        add("mirrors", "mirrors/mirrors.prg")
        add("mirrors128k", "mirrors/mirrors128k.prg", .reu1700)
        add("mirrors256k", "mirrors/mirrors256k.prg", .reu1764)
        add("mirrors512k", "mirrors/mirrors512k.prg", .reu1750)
        add("mirrors1m", "mirrors/mirrors1m.prg", .reu1MB)
        add("mirrors2m", "mirrors/mirrors2m.prg", .reu2MB)
        add("mirrors4m", "mirrors/mirrors4m.prg", .reu4MB)
        add("mirrors8m", "mirrors/mirrors8m.prg", .reu8MB)
        add("mirrors16m", "mirrors/mirrors16m.prg", .reu16MB)
        add("bitfill-auto", "misc/bitfill-auto.prg")
        add("twoblocks-auto", "misc/twoblocks-auto.prg")
        add("twoblocks-ff00-auto", "misc/twoblocks-ff00-auto.prg")
        add("wheels", "misc/wheels.prg")
        add("reutiming", "reutiming/reutiming.prg")
        for name in ["a", "a2", "a3", "a4", "b", "b2", "b3", "b4", "b5", "b6", "c", "c2", "c3", "c4",
                     "d", "d2", "d3", "d4", "e", "e2", "e3", "e4", "e5", "e6", "f", "f2", "f3", "f4",
                     "g", "g2", "g3", "g4"] {
            add("reutiming2-\(name)", "reutiming2/\(name).prg")
        }
        add("rmwtrigger-ram", "rmw-trigger/rmwtrigger-ram.prg")
        add("rmwtrigger-rom", "rmw-trigger/rmwtrigger-rom.prg")
        for name in ["cmp", "swap", "swap2", "toc64", "toreu"] {
            add("xfertiming-\(name)", "xfertiming/xfertiming-\(name).prg")
        }
        return list
    }()

    func testOptInPublicREUPrograms() throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["SWIFT64_PUBLIC_REU_TESTPROGS_DIR"], !directory.isEmpty else {
            throw XCTSkip("Set SWIFT64_PUBLIC_REU_TESTPROGS_DIR after running script/fetch_reu_testprogs.sh")
        }
        let fixtures = Self.fixtures
        let requested = Set((env["SWIFT64_PUBLIC_REU_TEST_IDS"] ?? fixtures.map(\.id).joined(separator: ","))
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let unknown = requested.subtracting(fixtures.map(\.id))
        guard !requested.isEmpty, unknown.isEmpty else {
            XCTFail("Invalid REU fixture selection: \(unknown.sorted())")
            return
        }
        let cycleCap = Int(env["SWIFT64_PUBLIC_REU_TEST_MAX_CYCLES"] ?? "")
        let root = URL(fileURLWithPath: directory)
        let romRoot = URL(fileURLWithPath: env["SWIFT64_PUBLIC_REU_ROM_DIR"] ?? "Sources/C64App/ROMS")
        let basic = try Data(contentsOf: romRoot.appendingPathComponent("C64-901226-01-Commodore-F833D117-Basic.rom"))
        let kernal = try Data(contentsOf: romRoot.appendingPathComponent("C64-901227-03-Commodore-DBE3E7C7-Kernal.rom"))
        let charset = try Data(contentsOf: romRoot.appendingPathComponent("C64-901225-01-Commodore-EC4272EE-Characters.rom"))

        var scoreboard: [String] = []
        var counts: [String: Int] = [:]
        for fixture in fixtures where requested.contains(fixture.id) {
            try autoreleasepool {
                let programURL = root.appendingPathComponent("REU/" + fixture.path)
                guard FileManager.default.fileExists(atPath: programURL.path) else {
                    XCTFail("\(fixture.id): missing \(programURL.path)")
                    scoreboard.append("\(fixture.id)\tmissing\t\(fixture.model.rawValue)\t0\t-\t-\t-")
                    counts["missing", default: 0] += 1
                    return
                }
                let program = try Data(contentsOf: programURL)
                let c64 = C64(machineProfile: .palC64)
                try c64.loadROMsValidated(basic: basic, kernal: kernal, charset: charset)
                c64.attachREU(fixture.model)
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
                    XCTFail("\(fixture.id): BASIC did not reach READY")
                    scoreboard.append("\(fixture.id)\tno-ready\t\(fixture.model.rawValue)\t0\t-\t-\t-")
                    counts["no-ready", default: 0] += 1
                    return
                }

                var result: UInt8?
                c64.debugger.addWatchpoint(0xD7FF, type: .write)
                c64.debugger.onBreak = { reason in
                    if case let .watchpointWrite(address, value) = reason,
                       let completion = PublicCIAConformanceTests.completionValue(address: address, value: value, memory: c64.memory) {
                        result = completion
                    }
                    return false
                }
                defer { c64.debugger.onBreak = nil }

                c64.loadPRG(program, autoRun: true)
                let limit = min(fixture.maxCycles, cycleCap ?? Int.max)
                var cycles = 0
                while result == nil && !c64.cpu.jammed && cycles < limit {
                    c64.tickOneCycle()
                    cycles += 1
                }

                let status: String
                switch result {
                case 0: status = "pass"
                case nil: status = c64.cpu.jammed ? "jam" : "timeout"
                default: status = "fail"
                }
                counts[status, default: 0] += 1
                let pc = String(format: "%04X", c64.cpu.pc)
                let resultText = result.map { String(format: "$%02X", $0) } ?? "none"
                let line = "\(fixture.id)\t\(status)\t\(fixture.model.rawValue)\t\(cycles)\t\(resultText)\t$\(pc)\tborder=\(c64.vic.borderColor & 15)"
                scoreboard.append(line)
                print("Public REU " + line.replacingOccurrences(of: "\t", with: " "))
                if status != "pass" {
                    let masks = PublicCIAConformanceTests.redCellMask(c64.memory.colorRAM)
                    for (row, text) in PublicCIAConformanceTests.screenRows(c64.memory.ram).enumerated()
                    where !text.allSatisfy({ $0 == " " }) || masks[row] != nil {
                        print(String(format: "Public REU %@ screen %02d: %@", fixture.id, row, text))
                        if let mask = masks[row] {
                            print(String(format: "Public REU %@ red    %02d: %@", fixture.id, row, mask))
                        }
                    }
                }
                XCTAssertFalse(c64.cpu.jammed, "\(fixture.id): CPU jam at $\(pc)")
                XCTAssertNotNil(result, "\(fixture.id): no $D7FF completion within \(cycles) cycles at $\(pc)")
                XCTAssertEqual(result, 0, "\(fixture.id): public fixture reported failure")
            }
        }

        let summary = counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("Public REU scoreboard: \(scoreboard.count) programs; \(summary)")
        if let path = env["SWIFT64_PUBLIC_REU_RESULTS_FILE"], !path.isEmpty {
            let header = "id\tstatus\tunit\tcycles\td7ff\tpc\tborder"
            try (([header] + scoreboard).joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
