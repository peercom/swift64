import Foundation
import XCTest
@testable import C64Core
@testable import Emu6502

/// Opt-in probe for driving one local disk image through the true drive and
/// recording where it goes: periodic screenshots with decoded screen text and
/// PC hotspots, a scripted key/joystick schedule, every DOS job dispatch with
/// its track/sector and return code, every stepper phase change, and the
/// final drive state. It is the tool used for the protected-loader work in
/// TESTING.md ("Protected loaders on the strict true drive"). Nothing in it
/// changes emulation; it only observes.
///
/// Environment:
/// - `SWIFT64_LOCAL_DRIVE_PROBE=1` enables the test.
/// - `SWIFT64_LOCAL_DRIVE_PROBE_MEDIA` path of the D64/G64/NIB/NBZ/P64 image (required).
/// - `SWIFT64_LOCAL_DRIVE_PROBE_OUTPUT_DIR` directory for the log and PPM screenshots (required).
/// - `SWIFT64_LOCAL_DRIVE_PROBE_COMMAND` text typed after 20 frames (default `LOAD"*",8,1` + `RUN`).
/// - `SWIFT64_LOCAL_DRIVE_PROBE_MODE` `standard1541` (default) or `compat1541`.
/// - `SWIFT64_LOCAL_DRIVE_PROBE_PROFILE` `pal` (default) or `ntsc`.
/// - `SWIFT64_LOCAL_DRIVE_PROBE_MAX_CYCLES` budget (default 60,000,000).
/// - `SWIFT64_LOCAL_DRIVE_PROBE_SHOT_EVERY` screenshot interval in cycles (default 5,000,000).
/// - `SWIFT64_LOCAL_DRIVE_PROBE_INPUT` schedule such as `space@26000000:40000,fire@42000000`
///   (`space`, `return`, `f1`, `fire`, `up`, `down`, `left`, `right`; `@cycle[:holdCycles]`).
/// - `SWIFT64_LOCAL_DRIVE_PROBE_STOP_PC` hex C64 PC that stops the run once reached after
///   `SWIFT64_LOCAL_DRIVE_PROBE_STOP_PC_MIN_CYCLES`.
/// - `SWIFT64_LOCAL_DRIVE_PROBE_COMPARE_FILE` a PRG whose bytes are compared against every
///   RAM write made from C64 PCs in `SWIFT64_LOCAL_DRIVE_PROBE_STORE_PC_RANGE` (hex `lo-hi`,
///   default `0500-0700`); mismatches are logged with the drive bytes sent around them.
/// - `SWIFT64_LOCAL_DRIVE_PROBE_DUMP=1` writes the final C64 and drive RAM images.
final class LocalStrictDriveProbeTests: XCTestCase {
    private struct ScheduledInput {
        let name: String
        let at: Int
        let hold: Int
    }

    func testLocalStrictDriveProbeWhenEnabled() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SWIFT64_LOCAL_DRIVE_PROBE"] == "1" else {
            throw XCTSkip("Set SWIFT64_LOCAL_DRIVE_PROBE=1 with SWIFT64_LOCAL_DRIVE_PROBE_MEDIA and _OUTPUT_DIR")
        }
        let mediaPath = try XCTUnwrap(env["SWIFT64_LOCAL_DRIVE_PROBE_MEDIA"], "SWIFT64_LOCAL_DRIVE_PROBE_MEDIA is required")
        let outputDir = URL(fileURLWithPath: try XCTUnwrap(env["SWIFT64_LOCAL_DRIVE_PROBE_OUTPUT_DIR"], "SWIFT64_LOCAL_DRIVE_PROBE_OUTPUT_DIR is required"))
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let tag = URL(fileURLWithPath: mediaPath).deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)

        let c64 = C64(machineProfile: env["SWIFT64_LOCAL_DRIVE_PROBE_PROFILE"] == "ntsc" ? .ntscC64 : .palC64)
        try loadBundledROMs(into: c64)
        c64.trueDriveEmulationMode = env["SWIFT64_LOCAL_DRIVE_PROBE_MODE"] == "compat1541" ? .compat1541 : .standard1541
        XCTAssertTrue(c64.mountDisk(URL(fileURLWithPath: mediaPath)), "mount failed: \(mediaPath)")
        c64.powerOn()
        for _ in 0..<20 { _ = c64.runFrame() }
        c64.typeText(env["SWIFT64_LOCAL_DRIVE_PROBE_COMMAND"] ?? "LOAD\"*\",8,1\rRUN\r")

        let maxCycles = Int(env["SWIFT64_LOCAL_DRIVE_PROBE_MAX_CYCLES"] ?? "") ?? 60_000_000
        let shotEvery = max(1, Int(env["SWIFT64_LOCAL_DRIVE_PROBE_SHOT_EVERY"] ?? "") ?? 5_000_000)
        let stopPC = UInt16(env["SWIFT64_LOCAL_DRIVE_PROBE_STOP_PC"] ?? "", radix: 16)
        let stopPCMin = Int(env["SWIFT64_LOCAL_DRIVE_PROBE_STOP_PC_MIN_CYCLES"] ?? "") ?? 0
        var inputs: [ScheduledInput] = []
        for item in (env["SWIFT64_LOCAL_DRIVE_PROBE_INPUT"] ?? "").split(separator: ",") {
            let parts = item.split(separator: "@")
            guard parts.count == 2 else { continue }
            let timing = parts[1].split(separator: ":")
            inputs.append(ScheduledInput(
                name: String(parts[0]).trimmingCharacters(in: .whitespaces),
                at: Int(timing[0]) ?? 0,
                hold: timing.count > 1 ? (Int(timing[1]) ?? 30_000) : 30_000
            ))
        }
        var compareFile: [UInt8] = []
        var compareLoad = 0
        if let path = env["SWIFT64_LOCAL_DRIVE_PROBE_COMPARE_FILE"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count > 2 {
            compareFile = [UInt8](data)
            compareLoad = Int(compareFile[0]) | (Int(compareFile[1]) << 8)
        }
        let storeRange = env["SWIFT64_LOCAL_DRIVE_PROBE_STORE_PC_RANGE"] ?? "0500-0700"
        let storeParts = storeRange.split(separator: "-")
        let storePCLow = UInt16(storeParts.first ?? "", radix: 16) ?? 0x0500
        let storePCHigh = UInt16(storeParts.count > 1 ? storeParts[1] : "", radix: 16) ?? 0x0700

        let drive = c64.drive1541
        var log: [String] = []
        var jobLog: [String] = []
        var stepLog: [String] = []
        var pcHist: [UInt16: Int] = [:]
        var active: [(ScheduledInput, Int)] = []
        var lastShot = 0
        var lastDriveCycle = drive.debugCycleCount
        var lastDrivePC: UInt16 = 0xFFFF
        var lastPhase = drive.via2.portB & 0x03
        var lastHalfTrack = drive.halfTrack
        var sentBytes: [(UInt64, UInt8)] = []
        drive.onVIA1PortBWrite = { _, drivePC, portB, _, _ in
            // Custom loaders push data bytes to the bus from RAM code; keep the last few for mismatch context.
            guard (0x0300...0x07FF).contains(drivePC) else { return }
            sentBytes.append((c64.cpu.totalCycles, portB))
            if sentBytes.count > 8 { sentBytes.removeFirst() }
        }
        var compareStores = 0
        var compareMismatches = 0

        c64.memory.onRAMWrite = { address, value in
            guard !compareFile.isEmpty else { return }
            let pc = c64.cpu.pc
            guard pc >= storePCLow && pc < storePCHigh else { return }
            let index = Int(address) - compareLoad + 2
            guard index >= 2 && index < compareFile.count else { return }
            compareStores += 1
            if compareFile[index] != value {
                compareMismatches += 1
                if compareMismatches <= 40 {
                    let sent = sentBytes.suffix(3).map { String(format: "%02X@%llu", $0.1, $0.0) }.joined(separator: ",")
                    log.append(String(format: "MISMATCH c%llu PC=%04X $%04X=%02X expected %02X (store #%d) driveSent=%@", c64.cpu.totalCycles, pc, address, value, compareFile[index], compareStores, sent))
                }
            }
        }
        defer { c64.memory.onRAMWrite = nil; drive.onVIA1PortBWrite = nil }

        func apply(_ name: String, press: Bool) {
            switch name {
            case "space": press ? c64.keyboard.pressKey(row: 7, col: 4) : c64.keyboard.releaseKey(row: 7, col: 4)
            case "return": press ? c64.keyboard.pressKey(row: 0, col: 1) : c64.keyboard.releaseKey(row: 0, col: 1)
            case "f1": press ? c64.keyboard.pressKey(row: 0, col: 4) : c64.keyboard.releaseKey(row: 0, col: 4)
            case "fire": c64.joystick.port2 = press ? 0xEF : 0xFF
            case "up": c64.joystick.port2 = press ? 0xFE : 0xFF
            case "down": c64.joystick.port2 = press ? 0xFD : 0xFF
            case "left": c64.joystick.port2 = press ? 0xFB : 0xFF
            case "right": c64.joystick.port2 = press ? 0xF7 : 0xFF
            default: break
            }
        }

        for cycle in 0..<maxCycles {
            for input in inputs where input.at == cycle {
                apply(input.name, press: true)
                active.append((input, cycle + input.hold))
                log.append("c\(c64.cpu.totalCycles) press \(input.name)")
            }
            active = active.filter { pair in
                if cycle >= pair.1 { apply(pair.0.name, press: false); return false }
                return true
            }
            c64.tickOneCycle()
            if cycle & 0x3FF == 0, let reason = c64.lastFailureReason {
                log.append("FAIL c\(c64.cpu.totalCycles): \(reason) pc=\(hex16(c64.cpu.pc))")
                try writePPM(c64, to: outputDir.appendingPathComponent("\(tag)-fail.ppm"))
                break
            }
            if let stopPC, cycle >= stopPCMin, c64.cpu.cycle == 0, c64.cpu.pc == stopPC {
                log.append("STOP at pc \(hex16(stopPC)) c\(c64.cpu.totalCycles)")
                break
            }
            if cycle & 0x3F == 0 { pcHist[c64.cpu.pc, default: 0] += 1 }

            let driveCycle = drive.debugCycleCount
            if driveCycle != lastDriveCycle {
                lastDriveCycle = driveCycle
                let phase = drive.via2.portB & 0x03
                if phase != lastPhase || drive.halfTrack != lastHalfTrack {
                    if stepLog.count < 4000 {
                        stepLog.append(String(format: "c%llu d%llu phase %d->%d half %d->%d drvtrk=%02X drivePC=%04X", c64.cpu.totalCycles, driveCycle, lastPhase, phase, lastHalfTrack, drive.halfTrack, drive.memory.ram[0x22], drive.cpu.pc))
                    }
                    lastPhase = phase
                    lastHalfTrack = drive.halfTrack
                }
                let drivePC = drive.cpu.pc
                if drive.cpu.cycle == 0 && drivePC != lastDrivePC {
                    lastDrivePC = drivePC
                    switch drivePC {
                    case 0xF379:
                        // DOS job dispatcher about to jump into the buffer code.
                        let buffer = Int(drive.memory.ram[0x31])
                        let slot = max(0, min(4, buffer - 3))
                        if jobLog.count < 4000 {
                            jobLog.append(String(format: "c%llu job buf%02X t%d/s%d@ht%d", c64.cpu.totalCycles, buffer, drive.memory.ram[6 + slot * 2], drive.memory.ram[7 + slot * 2], drive.halfTrack))
                        }
                    case 0xF969:
                        // Job return: $3F holds the job number, its header slot the track/sector.
                        let job = Int(drive.memory.ram[0x3F] & 0x07)
                        let entry = String(format: "ret=%02X job%d t%d/s%d@ht%d", drive.cpu.a, job, drive.memory.ram[6 + job * 2], drive.memory.ram[7 + job * 2], drive.halfTrack)
                        if jobLog.count < 4000 && jobLog.last != entry { jobLog.append(entry) }
                    default:
                        break
                    }
                }
            }
            if cycle - lastShot >= shotEvery {
                lastShot = cycle
                let shot = outputDir.appendingPathComponent(String(format: "%@-%03dM.ppm", tag, cycle / 1_000_000))
                try writePPM(c64, to: shot)
                let top = pcHist.sorted { $0.value > $1.value }.prefix(6).map { "\(hex16($0.key)):\($0.value)" }.joined(separator: " ")
                pcHist.removeAll()
                log.append(String(format: "c%llu shot %@ pc=%@ drivePC=%@ half=%d AE/AF=%02X%02X top=%@ d011=%02X d018=%02X", c64.cpu.totalCycles, shot.lastPathComponent, hex16(c64.cpu.pc), hex16(drive.cpu.pc), drive.halfTrack, c64.memory.ram[0xAF], c64.memory.ram[0xAE], top, c64.vic.readRegister(0x11), c64.vic.readRegister(0x18)))
                log.append(screenText(c64))
            }
        }

        try writePPM(c64, to: outputDir.appendingPathComponent("\(tag)-end.ppm"))
        let status = drive.statusSnapshot
        log.append("END c\(c64.cpu.totalCycles) pc=\(hex16(c64.cpu.pc)) compareStores=\(compareStores) compareMismatches=\(compareMismatches) drivePC=\(hex16(status.cpuPC)) motor=\(status.motorOn) half=\(status.halfTrack) bit=\(status.headBitPosition) sync=\(status.syncDetected) syncs=\(status.syncDetectionCount) byteReady=\(status.byteReadyCount) via2PB=\(String(format: "%02X", drive.via2.portB)) reason=\(c64.lastFailureReason ?? "none")")
        log.append("jobs: " + jobLog.joined(separator: " "))
        log.append("steps: " + stepLog.joined(separator: " | "))
        log.append(screenText(c64))
        if env["SWIFT64_LOCAL_DRIVE_PROBE_DUMP"] == "1" {
            try Data(drive.memory.ram).write(to: outputDir.appendingPathComponent("\(tag)-drive-ram.bin"))
            try Data(c64.memory.ram).write(to: outputDir.appendingPathComponent("\(tag)-c64-ram.bin"))
            log.append("iecCommands=" + drive.decodedIECCommandBytes.map { String(format: "%02X", $0) }.joined(separator: " "))
            log.append("iecData=" + drive.decodedIECDataBytes.map { String(format: "%02X", $0) }.joined(separator: " "))
        }
        try log.joined(separator: "\n").write(to: outputDir.appendingPathComponent("\(tag).log"), atomically: true, encoding: .utf8)
        print("Strict drive probe \(tag): cycles=\(c64.cpu.totalCycles) pc=\(hex16(c64.cpu.pc)) drivePC=\(hex16(status.cpuPC)) half=\(status.halfTrack) jobs=\(jobLog.filter { $0.contains(" job ") }.count) compareMismatches=\(compareMismatches) reason=\(c64.lastFailureReason ?? "none")")
    }

    private func hex16(_ value: UInt16) -> String { String(format: "$%04X", value) }

    private func loadBundledROMs(into c64: C64) throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let roms = root.appendingPathComponent("Sources/C64App/ROMS")
        c64.loadROMs(
            basic: try Data(contentsOf: roms.appendingPathComponent("C64-901226-01-Commodore-F833D117-Basic.rom")),
            kernal: try Data(contentsOf: roms.appendingPathComponent("C64-901227-03-Commodore-DBE3E7C7-Kernal.rom")),
            charset: try Data(contentsOf: roms.appendingPathComponent("C64-901225-01-Commodore-EC4272EE-Characters.rom"))
        )
        c64.loadDriveROM(try Data(contentsOf: roms.appendingPathComponent("1541C.251968-02.bin")))
    }

    private func writePPM(_ c64: C64, to url: URL) throws {
        let width = VIC.screenWidth, height = VIC.screenHeight
        var data = Data("P6\n\(width) \(height)\n255\n".utf8)
        data.reserveCapacity(data.count + width * height * 3)
        for pixel in c64.vic.framebuffer.prefix(width * height) {
            data.append(UInt8(pixel & 0xFF))
            data.append(UInt8((pixel >> 8) & 0xFF))
            data.append(UInt8((pixel >> 16) & 0xFF))
        }
        try data.write(to: url)
    }

    /// Screen RAM decoded as upper-case PETSCII where the code is printable.
    private func screenText(_ c64: C64) -> String {
        let base = Int(c64.vic.readRegister(0x18) >> 4) * 0x400 + Int(~c64.cia2.portA & 0x03) * 0x4000
        var rows: [String] = []
        for row in 0..<25 {
            var line = ""
            for column in 0..<40 {
                let code = c64.memory.ram[(base + row * 40 + column) & 0xFFFF] & 0x7F
                switch code {
                case 0: line.append("@")
                case 1...26: line.append(Character(UnicodeScalar(code + 64)))
                case 32...63: line.append(Character(UnicodeScalar(code)))
                default: line.append(".")
                }
            }
            rows.append(line)
        }
        return rows.joined(separator: "\n")
    }
}
