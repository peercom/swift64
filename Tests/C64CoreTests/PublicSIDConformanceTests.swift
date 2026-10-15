import XCTest
@testable import C64Core

final class PublicSIDConformanceTests: XCTestCase {
    private struct Fixture {
        let id: String
        let relativePath: String
        let model: SID.Model
        let entryPoint: UInt16
    }

    private let fixtures = [
        Fixture(id: "envrate", relativePath: "SID/resid-test/envrate.prg", model: .mos6581, entryPoint: 0x080D),
        Fixture(id: "envdelay", relativePath: "SID/resid-test/envdelay.prg", model: .mos6581, entryPoint: 0x080D),
        Fixture(id: "envsustain", relativePath: "SID/resid-test/envsustain.prg", model: .mos6581, entryPoint: 0x080D),
        Fixture(id: "envtime", relativePath: "SID/resid-test/envtime.prg", model: .mos6581, entryPoint: 0x080D),
        Fixture(id: "noisetest", relativePath: "SID/resid-test/noisetest.prg", model: .mos6581, entryPoint: 0x080D),
        Fixture(id: "oscsample0-6581", relativePath: "SID/resid-test/oscsample0-6581.prg", model: .mos6581, entryPoint: 0x080D),
        Fixture(id: "oscsample1-6581", relativePath: "SID/resid-test/oscsample1-6581.prg", model: .mos6581, entryPoint: 0x080D),
        Fixture(id: "oscsample0-8580", relativePath: "SID/resid-test/oscsample0-8580.prg", model: .mos8580, entryPoint: 0x080D),
        Fixture(id: "oscsample1-8580", relativePath: "SID/resid-test/oscsample1-8580.prg", model: .mos8580, entryPoint: 0x080D),
        Fixture(id: "osc3-wave0-6581", relativePath: "SID/osc3-wave0/osc3-wave0.prg", model: .mos6581, entryPoint: 0x080D),
        Fixture(id: "osc3-wave0-8580", relativePath: "SID/osc3-wave0/osc3-wave0-new.prg", model: .mos8580, entryPoint: 0x080D),
    ]

    func testOptInVICEPublicSIDPrograms() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rootPath = environment["SWIFT64_PUBLIC_SID_TESTPROGS_DIR"], !rootPath.isEmpty else {
            throw XCTSkip("Set SWIFT64_PUBLIC_SID_TESTPROGS_DIR to a local VICE-testprogs checkout")
        }

        let requestedIDs = Set(
            (environment["SWIFT64_PUBLIC_SID_TEST_IDS"] ?? fixtures.map(\.id).joined(separator: ","))
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let selected = fixtures.filter { requestedIDs.contains($0.id) }
        let knownIDs = Set(fixtures.map(\.id))
        let unknownIDs = requestedIDs.subtracting(knownIDs).sorted()

        XCTAssertTrue(unknownIDs.isEmpty, "Unknown SID fixture IDs: \(unknownIDs.joined(separator: ", "))")
        XCTAssertFalse(selected.isEmpty, "No public SID fixtures selected")
        guard unknownIDs.isEmpty, !selected.isEmpty else { return }

        let maxCycles = max(
            1,
            Int(environment["SWIFT64_PUBLIC_SID_TEST_MAX_CYCLES"] ?? "") ?? 40_000_000
        )
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)

        for fixture in selected {
            let fixtureURL = root.appendingPathComponent(fixture.relativePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL.path), "Missing \(fixtureURL.path)")
            guard FileManager.default.fileExists(atPath: fixtureURL.path) else { continue }

            let c64 = C64(machineProfile: fixture.model == .mos8580 ? .palC64C : .palC64)
            try loadLocalROMs(into: c64)
            c64.trueDriveEmulationMode = .off
            c64.sidModelOverride = fixture.model
            c64.sid.accuracyMode = .fast
            c64.powerOn()

            // Let the Kernal/BASIC cold-start finish before injecting into
            // $0801-$10xx; early injection can be erased by startup RAM init.
            for _ in 0..<100 {
                XCTAssertTrue(c64.runFrame(), fixture.id)
            }

            var result: UInt8?
            c64.onSIDRegisterWriteTrace = { event in
                // VICE test programs signal completion through the SID mirror
                // at $D7FF: zero is pass and $FF is failure.
                if event.register == 0x1F {
                    result = event.value
                }
            }
            let fixtureData = try Data(contentsOf: fixtureURL)
            let completionMarker = try XCTUnwrap(completionMarker(in: fixtureData), "Missing $D7FF completion marker in \(fixture.id)")
            c64.loadPRG(suppressKernalCharacterOutput(in: fixtureData))
            // These VICE fixtures are SYS-style machine-code programs. Reset
            // only the CPU's private execution state so the initialized C64
            // hardware remains intact, then enter at the fixture's SYS target.
            // Clear the KERNAL's periodic CIA IRQ first: direct fixture entry
            // deliberately bypasses the RAM IRQ vectors installed at boot.
            c64.cia1.reset()
            c64.cia2.reset()
            c64.cpu.powerOn()
            c64.cpu.pc = fixture.entryPoint

            var elapsedCycles = 0
            var invalidLowPCInstructions = 0
            var enteredFixture = false
            var recentInstructionPCs: [UInt16] = []
            for cycle in 0..<maxCycles where result == nil {
                c64.tickOneCycle()
                elapsedCycles = cycle + 1
                if c64.cpu.cycle == 0 {
                    if c64.cpu.pc == completionMarker.pc {
                        switch completionMarker.storeOpcode {
                        case 0x8D: result = c64.cpu.a
                        case 0x8E: result = c64.cpu.x
                        case 0x8C: result = c64.cpu.y
                        default: break
                        }
                    }
                    recentInstructionPCs.append(c64.cpu.pc)
                    if recentInstructionPCs.count > 48 {
                        recentInstructionPCs.removeFirst()
                    }
                    if (fixture.entryPoint...0x7FFF).contains(c64.cpu.pc) {
                        enteredFixture = true
                    }
                    if enteredFixture && c64.cpu.pc < 0x0800 {
                        invalidLowPCInstructions += 1
                        if invalidLowPCInstructions >= 32 {
                            break
                        }
                    }
                }
            }
            c64.onSIDRegisterWriteTrace = nil

            print("Public SID fixture \(fixture.id): result=\(result.map(String.init) ?? "timeout") cycles=\(elapsedCycles) pc=$\(String(format: "%04X", c64.cpu.pc))")
            if result == nil {
                print("Recent PCs: \(recentInstructionPCs.map { String(format: "%04X", $0) }.joined(separator: " "))")
                print("CPU: A=$\(String(format: "%02X", c64.cpu.a)) X=$\(String(format: "%02X", c64.cpu.x)) Y=$\(String(format: "%02X", c64.cpu.y)) SP=$\(String(format: "%02X", c64.cpu.sp)) P=$\(String(format: "%02X", c64.cpu.p))")
            }
            XCTAssertNotNil(result, "\(fixture.id) did not report within \(elapsedCycles) cycles at PC $\(String(format: "%04X", c64.cpu.pc))")
            XCTAssertEqual(result, 0, "\(fixture.id) reported SID conformance failure")
        }
    }

    private func loadLocalROMs(into c64: C64) throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/C64App/ROMS", isDirectory: true)
        let basic = try Data(contentsOf: root.appendingPathComponent("C64-901226-01-Commodore-F833D117-Basic.rom"))
        let kernal = try Data(contentsOf: root.appendingPathComponent("C64-901227-03-Commodore-DBE3E7C7-Kernal.rom"))
        let charset = try Data(contentsOf: root.appendingPathComponent("C64-901225-01-Commodore-EC4272EE-Characters.rom"))

        c64.loadROMs(basic: basic, kernal: kernal, charset: charset)
    }

    private func suppressKernalCharacterOutput(in data: Data) -> Data {
        var bytes = [UInt8](data)
        guard bytes.count >= 5 else { return data }

        // Cosmetic output is irrelevant to SID conformance and direct fixture
        // entry does not promise a fully initialized KERNAL editor vector.
        for index in 2..<(bytes.count - 2) where
            bytes[index] == 0x20 && bytes[index + 1] == 0xD2 && bytes[index + 2] == 0xFF
        {
            bytes[index] = 0xEA
            bytes[index + 1] = 0xEA
            bytes[index + 2] = 0xEA
        }
        return Data(bytes)
    }

    private func completionMarker(in data: Data) -> (pc: UInt16, storeOpcode: UInt8)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 6 else { return nil }
        let loadAddress = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)

        for index in 2..<(bytes.count - 2) where
            (bytes[index] == 0x8D || bytes[index] == 0x8E || bytes[index] == 0x8C)
                && bytes[index + 1] == 0xFF
                && bytes[index + 2] == 0xD7
        {
            let instructionAddress = loadAddress &+ UInt16(index - 2)
            return (instructionAddress &+ 3, bytes[index])
        }
        return nil
    }
}
