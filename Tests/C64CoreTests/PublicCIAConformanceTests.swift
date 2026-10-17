import XCTest
@testable import C64Core

/// Opt-in runner for the public CIA programs of the VICE test-program
/// collection, modelled on `PublicVICConformanceTests`.
///
/// Every program listed here is an `exitcode` entry of the upstream
/// `testbench/c64-testlist.in` CIA section at the pinned revision fetched by
/// `script/fetch_cia_testprogs.sh`. Each boots through BASIC `RUN` and reports
/// its own verdict by writing `$00` (pass) or `$FF` (fail) to the testbench
/// port at `$D7FF`. The three upstream `interactive` programs (`ciaports`,
/// `ghosting`, `transactor/ciatest64`) need key presses and are not run.
///
/// Programs are never patched and completion is never inferred from a PC scan.
/// The upstream old/new CIA tagging is carried as metadata only: Swift64 has a
/// single 6526 model, so both variants run and the scoreboard records which
/// revision the current behaviour matches.
final class PublicCIAConformanceTests: XCTestCase {
    /// Upstream `cia-old` / `cia-new` tag of a program (6526 vs 6526A/8521).
    enum CIARevision: String {
        case any, old, new
    }

    struct Fixture {
        let id: String
        /// Relative to the fetched `CIA/` directory.
        let path: String
        let profile: MachineProfile
        var revision: CIARevision = .any
        /// Upstream testbench timeout in CPU cycles.
        var maxCycles: Int
        /// Upstream marks the program `expect:error`: it only passes on the
        /// 6526 batch stamped 4485. A `$FF` result is recorded, not asserted.
        var upstreamExpectsFailure = false
    }

    static let fixtures: [Fixture] = {
        var list: [Fixture] = []
        func pal(_ id: String, _ path: String, _ revision: CIARevision = .any, cycles: Int, expectsFailure: Bool = false) {
            list.append(Fixture(id: id + "-pal", path: path, profile: .palC64, revision: revision,
                                maxCycles: cycles, upstreamExpectsFailure: expectsFailure))
        }
        func ntsc(_ id: String, _ path: String, _ revision: CIARevision = .any, cycles: Int) {
            list.append(Fixture(id: id + "-ntsc", path: path, profile: .ntscC64, revision: revision, maxCycles: cycles))
        }

        // Timer B counting Timer A underflows, with hardware dumps embedded.
        pal("cia-b-counts-a", "CIA-AcountsB/cia-b-counts-a.prg", cycles: 100_000_000)
        pal("cmp-b-counts-a-old", "CIA-AcountsB/cmp-b-counts-a-old.prg", .old, cycles: 100_000_000)
        pal("cmp-b-counts-a-new", "CIA-AcountsB/cmp-b-counts-a-new.prg", .new, cycles: 100_000_000)
        ntsc("cia-b-counts-a", "CIA-AcountsB/cia-b-counts-a_ntsc.prg", cycles: 100_000_000)
        ntsc("cmp-b-counts-a-old", "CIA-AcountsB/cmp-b-counts-a-old_ntsc.prg", .old, cycles: 100_000_000)
        ntsc("cmp-b-counts-a-new", "CIA-AcountsB/cmp-b-counts-a-new_ntsc.prg", .new, cycles: 100_000_000)

        // ICR near timer underrun, with and without interrupts enabled.
        pal("cia-timer-oldcias", "cia-timer/cia-timer-oldcias.prg", .old, cycles: 200_000_000)
        pal("cia-timer-newcias", "cia-timer/cia-timer-newcias.prg", .new, cycles: 200_000_000)

        // André Fachat's timer/port/TOD set, repacked to run every case at startup.
        pal("cia1", "ciavarious/cia1.prg", cycles: 10_000_000)
        pal("cia2", "ciavarious/cia2.prg", cycles: 20_000_000)
        pal("cia3", "ciavarious/cia3.prg", .old, cycles: 10_000_000)
        pal("cia3a", "ciavarious/cia3a.prg", .old, cycles: 10_000_000)
        pal("cia4", "ciavarious/cia4.prg", .old, cycles: 20_000_000)
        pal("cia5", "ciavarious/cia5.prg", cycles: 20_000_000)
        pal("cia6", "ciavarious/cia6.prg", cycles: 20_000_000)
        pal("cia7", "ciavarious/cia7.prg", cycles: 10_000_000)
        pal("cia8", "ciavarious/cia8.prg", .old, cycles: 10_000_000)
        pal("cia9", "ciavarious/cia9.prg", cycles: 10_000_000)
        for number in 10...14 {
            pal("cia\(number)", "ciavarious/cia\(number).prg", cycles: 10_000_000)
        }
        pal("cia15", "ciavarious/cia15.prg", cycles: 160_000_000)
        pal("cia3new", "ciavarious/cia3new.prg", .new, cycles: 10_000_000)
        pal("cia3anew", "ciavarious/cia3anew.prg", .new, cycles: 10_000_000)
        pal("cia4new", "ciavarious/cia4new.prg", .new, cycles: 20_000_000)
        pal("cia8new", "ciavarious/cia8new.prg", .new, cycles: 10_000_000)

        // Interrupt acknowledge timing through read-modify-write and indexed reads.
        pal("dd0drw", "dd0drw/dd0drw.prg", cycles: 6_000_000)
        // Upstream runs dd0dtest under both CIA models; it detects the model itself.
        pal("dd0dtest", "dd0dtest/dd0dtest.prg", cycles: 100_000_000)
        pal("ciamirrors", "mirrors/ciamirrors.prg", cycles: 9_000_000)

        // One-cycle IRQ delay differences between CIA revisions.
        pal("irqdelay", "irqdelay/irqdelay.prg", .old, cycles: 7_000_000)
        pal("irqdelay-new", "irqdelay/irqdelay-new.prg", .new, cycles: 7_000_000)
        pal("irqdelay-oneshot", "irqdelay/irqdelay-oneshot.prg", .old, cycles: 7_000_000)
        pal("irqdelay-oneshot-new", "irqdelay/irqdelay-oneshot-new.prg", .new, cycles: 7_000_000)
        pal("irqdelay2", "irqdelay/irqdelay2.prg", .old, cycles: 9_000_000)
        pal("irqdelay2-new", "irqdelay/irqdelay2-new.prg", .new, cycles: 9_000_000)
        pal("irqdelay-cia1-4-new", "irqdelay/irqdelay-cia1-4-new.prg", .new, cycles: 10_000_000)
        pal("irqdelay-cia1-4-old", "irqdelay/irqdelay-cia1-4-old.prg", .old, cycles: 10_000_000)
        pal("irqdelay-cia1-oneshot-4-new", "irqdelay/irqdelay-cia1-oneshot-4-new.prg", .new, cycles: 10_000_000)
        pal("irqdelay-cia1-oneshot-4-old", "irqdelay/irqdelay-cia1-oneshot-4-old.prg", .old, cycles: 10_000_000)
        for name in ["irqdelay-cia1-oneshot", "irqdelay-cia1", "irqdelay-cia2-4",
                     "irqdelay-cia2-oneshot-4", "irqdelay-cia2-oneshot", "irqdelay-cia2"] {
            pal(name, "irqdelay/\(name).prg", cycles: 10_000_000)
        }

        pal("pb6pb7", "pb6pb7/main.prg", cycles: 7_000_000)
        pal("reload0a", "reload0/reload0a.prg", cycles: 20_000_000)
        pal("reload0b", "reload0/reload0b.prg", cycles: 20_000_000)

        // Serial shift register and ICR behaviour.
        pal("cia-icr-test2-continues", "shiftregister/cia-icr-test2-continues.prg", cycles: 10_000_000)
        pal("cia-icr-test2-oneshot", "shiftregister/cia-icr-test2-oneshot.prg", cycles: 10_000_000)
        pal("cia-icr-test-continues-new", "shiftregister/cia-icr-test-continues-new.prg", .new, cycles: 10_000_000)
        pal("cia-icr-test-continues-old", "shiftregister/cia-icr-test-continues-old.prg", .old, cycles: 10_000_000)
        pal("cia-icr-test-oneshot-new", "shiftregister/cia-icr-test-oneshot-new.prg", .new, cycles: 10_000_000)
        pal("cia-icr-test-oneshot-old", "shiftregister/cia-icr-test-oneshot-old.prg", .old, cycles: 10_000_000)
        pal("cia-sdr-load", "shiftregister/cia-sdr-load.prg", cycles: 7_000_000)
        pal("cia-sdr-init", "shiftregister/cia-sdr-init.prg", cycles: 7_000_000)
        pal("cia-sdr-delay", "shiftregister/cia-sdr-delay.prg", cycles: 7_000_000)
        // Upstream lists the SDR/ICR set under both CIA models with identical expectations.
        for cia in ["cia1", "cia2"] {
            for rate in ["0", "3", "19", "39"] {
                pal("\(cia)-sdr-icr-\(rate)", "shiftregister/cia-sdr-icr/\(cia)-sdr-icr-\(rate).prg", cycles: 16_000_000)
                pal("\(cia)-sdr-icr-generic-\(rate)", "shiftregister/cia-sdr-icr/\(cia)-sdr-icr-generic-\(rate).prg", cycles: 16_000_000)
                pal("\(cia)-sdr-icr-4485-\(rate)", "shiftregister/cia-sdr-icr/\(cia)-sdr-icr-4485-\(rate).prg",
                    cycles: 16_000_000, expectsFailure: rate != "0")
            }
            for range in ["0_7f", "1_7f", "4_7f"] {
                pal("\(cia)-sdr-icr-\(range)", "shiftregister/cia-sdr-icr/\(cia)-sdr-icr-\(range).prg", cycles: 121_000_000)
                pal("\(cia)-sdr-icr-generic-\(range)", "shiftregister/cia-sdr-icr/\(cia)-sdr-icr-generic-\(range).prg", cycles: 121_000_000)
                pal("\(cia)-sdr-icr-4485-\(range)", "shiftregister/cia-sdr-icr/\(cia)-sdr-icr-4485-\(range).prg",
                    cycles: 121_000_000, expectsFailure: true)
            }
            pal("\(cia)-sdr-icr-test2-0_7f", "shiftregister/cia-sdr-icr/\(cia)-sdr-icr-test2-0_7f.prg", cycles: 130_000_000)
        }
        pal("cia-sp-test-continues-new", "shiftregister/cia-sp-test-continues-new.prg", .new, cycles: 50_000_000)
        pal("cia-sp-test-continues-old", "shiftregister/cia-sp-test-continues-old.prg", .old, cycles: 50_000_000)
        pal("cia-sp-test-oneshot-new", "shiftregister/cia-sp-test-oneshot-new.prg", .new, cycles: 50_000_000)
        pal("cia-sp-test-oneshot-old", "shiftregister/cia-sp-test-oneshot-old.prg", .old, cycles: 50_000_000)

        // Timer read patterns against hardware dumps.
        pal("timerbasics-test-new", "timerbasics/test_new.prg", .new, cycles: 100_000_000)
        pal("timerbasics-test", "timerbasics/test.prg", .old, cycles: 100_000_000)
        pal("timerbasics-timer-new", "timerbasics/timer_new.prg", .new, cycles: 100_000_000)
        pal("timerbasics-timer", "timerbasics/timer.prg", .old, cycles: 100_000_000)
        pal("timerbasics-timer-test1-new", "timerbasics/timer_test1_new.prg", .new, cycles: 100_000_000)
        pal("timerbasics-timer-test1", "timerbasics/timer_test1.prg", .old, cycles: 100_000_000)

        // Time-of-day clock and alarm.
        for name in ["0alarm", "1alarm", "4todcia1", "4tod", "5tod", "6tod",
                     "fix-hour", "fix-min", "fix-sec", "fix-tsec", "frogger", "hour-test",
                     "powerup", "write-stop"] {
            pal(name, "tod/\(name).prg", cycles: 100_000_000)
        }
        for name in ["alarm-cond2", "alarm-cond", "alarm", "hammerfist0", "hammerfist1", "ampmtest"] {
            pal(name, "tod/\(name).prg", cycles: 10_000_000)
        }
        // Upstream notes hzsync3 and hzsync6 are not 100% stable on hardware.
        for number in 0...6 {
            pal("hzsync\(number)", "tod/hzsync\(number).prg", cycles: 100_000_000)
        }
        pal("read-latch", "tod/read-latch.prg", cycles: 100_000_000)
        pal("stability", "tod/stability.prg", cycles: 40_000_000)
        ntsc("stability", "tod/stability-ntsc.prg", cycles: 41_000_000)
        return list
    }()

    /// Same testbench-port rule as `PublicVICConformanceTests`: a RAM clear
    /// beneath banked-out I/O is not a test-port write.
    static func completionValue(address: UInt16, value: UInt8, memory: MemoryMap) -> UInt8? {
        guard address == 0xD7FF else { return nil }
        guard memory.cartridge?.usesUltimaxMemoryMap == true || (memory.charen && (memory.loram || memory.hiram)) else { return nil }
        return value
    }

    /// Screen RAM rows decoded as plain text for failure diagnostics.
    static func screenRows(_ ram: [UInt8]) -> [String] {
        (0..<25).map { row in
            let start = 0x0400 + row * 40
            return String(ram[start..<start + 40].map { code -> Character in
                let plain = code & 0x7F
                let ascii: UInt8 = plain < 32 ? plain + 64 : (plain < 96 ? plain : 0x2E)
                return Character(UnicodeScalar(ascii))
            })
        }
    }

    /// Several programs mark mismatching cells red (2) or light red (10)
    /// instead of printing them; this masks those cells per row.
    static func redCellMask(_ colorRAM: [UInt8]) -> [String?] {
        (0..<25).map { row in
            let cells = colorRAM[row * 40..<row * 40 + 40].map { $0 & 0x0F }
            guard cells.contains(where: { $0 == 2 || $0 == 10 }) else { return nil }
            return String(cells.map { $0 == 2 || $0 == 10 ? "R" : "." })
        }
    }

    func testFixtureTableIsConsistent() {
        let ids = Self.fixtures.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate CIA fixture IDs")
        for fixture in Self.fixtures {
            XCTAssertTrue(fixture.id.hasSuffix("-pal") || fixture.id.hasSuffix("-ntsc"), fixture.id)
            XCTAssertTrue(fixture.path.hasSuffix(".prg"), fixture.path)
            XCTAssertGreaterThan(fixture.maxCycles, 0, fixture.id)
            if fixture.upstreamExpectsFailure {
                XCTAssertTrue(fixture.id.contains("-4485-"), "\(fixture.id): only the 4485 batch is upstream expect:error")
            }
        }
        XCTAssertEqual(Self.fixtures.filter { $0.id.hasSuffix("-ntsc") }.count, 4)
    }

    func testScreenRowDecodingUsesUppercaseGraphicsSet() {
        var ram = [UInt8](repeating: 0x20, count: 0x10000)
        ram[0x0400] = 0x08 // H
        ram[0x0401] = 0x09 // I
        ram[0x0402] = 0x31 // 1
        ram[0x0403] = 0x80 | 0x01 // reverse A
        ram[0x0404] = 0x60 // graphics block
        XCTAssertEqual(Self.screenRows(ram)[0].prefix(5), "HI1A.")
        XCTAssertEqual(Self.screenRows(ram).count, 25)

        var colorRAM = [UInt8](repeating: 1, count: 1024)
        colorRAM[41] = 2
        colorRAM[42] = 0xFA // upper nibble is floating bus, low nibble light red
        let masks = Self.redCellMask(colorRAM)
        XCTAssertNil(masks[0])
        XCTAssertEqual(masks[1], ".RR" + String(repeating: ".", count: 37))
    }

    func testOptInPublicCIAPrograms() throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["SWIFT64_PUBLIC_CIA_TESTPROGS_DIR"], !directory.isEmpty else {
            throw XCTSkip("Set SWIFT64_PUBLIC_CIA_TESTPROGS_DIR after running script/fetch_cia_testprogs.sh")
        }
        let fixtures = Self.fixtures
        let requested = Set((env["SWIFT64_PUBLIC_CIA_TEST_IDS"] ?? fixtures.map(\.id).joined(separator: ","))
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let unknown = requested.subtracting(fixtures.map(\.id))
        guard !requested.isEmpty, unknown.isEmpty else {
            XCTFail("Invalid CIA fixture selection: \(unknown.sorted())")
            return
        }
        let cycleCap = Int(env["SWIFT64_PUBLIC_CIA_TEST_MAX_CYCLES"] ?? "")
        let root = URL(fileURLWithPath: directory)
        let romRoot = URL(fileURLWithPath: env["SWIFT64_PUBLIC_CIA_ROM_DIR"] ?? "Sources/C64App/ROMS")
        let basic = try Data(contentsOf: romRoot.appendingPathComponent("C64-901226-01-Commodore-F833D117-Basic.rom"))
        let kernal = try Data(contentsOf: romRoot.appendingPathComponent("C64-901227-03-Commodore-DBE3E7C7-Kernal.rom"))
        let charset = try Data(contentsOf: romRoot.appendingPathComponent("C64-901225-01-Commodore-EC4272EE-Characters.rom"))

        var scoreboard: [String] = []
        var counts: [String: Int] = [:]
        for fixture in fixtures where requested.contains(fixture.id) {
            try autoreleasepool {
                let programURL = root.appendingPathComponent("CIA/" + fixture.path)
                guard FileManager.default.fileExists(atPath: programURL.path) else {
                    XCTFail("\(fixture.id): missing \(programURL.path)")
                    scoreboard.append("\(fixture.id)\tmissing\t\(fixture.revision.rawValue)\t0\t-\t-")
                    counts["missing", default: 0] += 1
                    return
                }
                let program = try Data(contentsOf: programURL)
                let c64 = C64(machineProfile: fixture.profile)
                try c64.loadROMsValidated(basic: basic, kernal: kernal, charset: charset)
                c64.trueDriveEmulationMode = .off
                c64.kernalTraps.enabled = false
                c64.powerOn()
                c64.vic.recordsBusAccessTraces = false

                // Boot through BASIC until READY. is on screen, as the VIC runner does.
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
                    XCTFail("\(fixture.id): BASIC did not reach READY before loading at $\(String(format: "%04X", c64.cpu.pc))")
                    scoreboard.append("\(fixture.id)\tno-ready\t\(fixture.revision.rawValue)\t0\t-\t-")
                    counts["no-ready", default: 0] += 1
                    return
                }

                var result: UInt8?
                c64.debugger.addWatchpoint(0xD7FF, type: .write)
                c64.debugger.onBreak = { reason in
                    if case let .watchpointWrite(address, value) = reason,
                       let completion = Self.completionValue(address: address, value: value, memory: c64.memory) {
                        result = completion
                    }
                    return false
                }
                defer { c64.debugger.onBreak = nil }

                // PRGs use BASIC RUN; nothing is patched and no PC scan infers completion.
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
                default: status = fixture.upstreamExpectsFailure ? "expected-fail" : "fail"
                }
                counts[status, default: 0] += 1
                let pc = String(format: "%04X", c64.cpu.pc)
                let resultText = result.map { String(format: "$%02X", $0) } ?? "none"
                let line = "\(fixture.id)\t\(status)\t\(fixture.revision.rawValue)\t\(cycles)\t\(resultText)\t$\(pc)\tborder=\(c64.vic.borderColor & 15)"
                scoreboard.append(line)
                print("Public CIA " + line.replacingOccurrences(of: "\t", with: " "))
                if status != "pass" {
                    let masks = Self.redCellMask(c64.memory.colorRAM)
                    for (row, text) in Self.screenRows(c64.memory.ram).enumerated()
                    where !text.allSatisfy({ $0 == " " }) || masks[row] != nil {
                        print(String(format: "Public CIA %@ screen %02d: %@", fixture.id, row, text))
                        if let mask = masks[row] {
                            print(String(format: "Public CIA %@ red    %02d: %@", fixture.id, row, mask))
                        }
                    }
                }
                XCTAssertFalse(c64.cpu.jammed, "\(fixture.id): CPU jam at $\(pc)")
                XCTAssertNotNil(result, "\(fixture.id): no $D7FF completion within \(cycles) cycles at $\(pc)")
                if !fixture.upstreamExpectsFailure {
                    XCTAssertEqual(result, 0, "\(fixture.id): public fixture reported failure")
                }
            }
        }

        let total = scoreboard.count
        let summary = counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("Public CIA scoreboard: \(total) programs; \(summary)")
        if let path = env["SWIFT64_PUBLIC_CIA_RESULTS_FILE"], !path.isEmpty {
            let header = "id\tstatus\tupstream-cia\tcycles\td7ff\tpc\tborder"
            try (([header] + scoreboard).joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
