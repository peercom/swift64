import XCTest
@testable import C64Core

final class LocalDiskMatrixTests: XCTestCase {
    private let matrixEnv = "SWIFT64_LOCAL_DISK_MATRIX"
    private let trueDriveEnv = "SWIFT64_LOCAL_TRUE_DRIVE_MATRIX"
    private let milestoneEnv = "SWIFT64_LOCAL_MILESTONE_MATRIX"

    func testLocalDiskImagesMountAndEncodeWhenEnabled() throws {
        try requireEnvironment(matrixEnv)

        let urls = try localDiskURLs(limitEnv: "SWIFT64_LOCAL_DISK_LIMIT")
        XCTAssertFalse(urls.isEmpty, "Expected local disk images under C64/DISKS")

        var summaries: [String] = []
        for url in urls {
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.lowercased()

            let gcrDisk = GCRDisk()
            let lowLevelMounted = ext == "g64" ? gcrDisk.loadG64(data) : gcrDisk.loadD64(data)
            summaries.append("\(url.lastPathComponent): lowLevel=\(lowLevelMounted) native=\(gcrDisk.hasNativeLowLevelImage) halftracks=\(gcrDisk.image?.capabilities.populatedHalfTrackCount ?? 0)")
            XCTAssertTrue(lowLevelMounted, matrixSummary("Low-level media load failed", url: url, gcrDisk: gcrDisk))
            XCTAssertTrue(gcrDisk.hasDisk, matrixSummary("GCR disk should expose at least one track", url: url, gcrDisk: gcrDisk))

            if ext == "g64" {
                XCTAssertTrue(gcrDisk.hasNativeLowLevelImage, matrixSummary("G64 should be preserved as native low-level media", url: url, gcrDisk: gcrDisk))
            } else {
                let highLevelDrive = DiskDrive()
                let highLevelMounted = highLevelDrive.mountFromFile(url)
                XCTAssertTrue(highLevelMounted, "High-level mount failed for \(url.path)")
                XCTAssertTrue(highLevelDrive.isMounted, "DiskDrive should report mounted for \(url.path)")
            }
        }
        print("Local media matrix:\n" + summaries.joined(separator: "\n"))
    }

    func testLocalDiskImagesTrueDriveDirectorySmokeWhenEnabled() throws {
        try requireEnvironment(trueDriveEnv)

        let urls = try localDiskURLs(limitEnv: "SWIFT64_LOCAL_TRUE_DRIVE_LIMIT", defaultLimit: 1)
        XCTAssertFalse(urls.isEmpty, "Expected local disk images under C64/DISKS")

        var summaries: [String] = []
        for url in urls {
            let c64 = C64()
            try loadBundledROMs(into: c64)
            c64.trueDriveEmulationMode = .compat1541
            XCTAssertTrue(c64.mountDisk(url), "Failed to mount \(url.path)")
            c64.powerOn()

            for _ in 0..<20 {
                XCTAssertTrue(c64.runFrame())
            }

            c64.typeText("LOAD\"$\",8\r")
            let result = runUntilDirectoryLoadMilestone(c64)
            summaries.append(result.summary(name: url.lastPathComponent, command: #"LOAD"$",8"#, c64: c64))
            XCTAssertTrue(result.passed, result.summary(name: url.lastPathComponent, command: #"LOAD"$",8"#, c64: c64))
        }
        print("Local true-drive directory matrix:\n" + summaries.joined(separator: "\n"))
    }

    func testLocalDiskImagesNamedMilestonesWhenEnabled() throws {
        try requireEnvironment(milestoneEnv)

        let milestones = try localMilestones()
        guard !milestones.isEmpty else {
            throw XCTSkip("No local milestone disks found under C64/DISKS")
        }

        var summaries: [String] = []
        for milestone in milestones {
            let c64 = C64(machineProfile: milestone.machineProfile.profile)
            try loadBundledROMs(into: c64)
            c64.trueDriveEmulationMode = .compat1541
            XCTAssertTrue(c64.mountDisk(milestone.url), "Failed to mount \(milestone.url.path)")
            c64.powerOn()

            for _ in 0..<20 {
                XCTAssertTrue(c64.runFrame())
            }

            c64.typeText(milestone.command + "\r")
            let result = runUntilMilestone(c64, milestone: milestone)
            let summary = result.summary(name: milestone.url.lastPathComponent, command: milestone.command, c64: c64)
            summaries.append(summary)
            XCTAssertTrue(result.passed, summary)
        }
        print("Local named milestone matrix:\n" + summaries.joined(separator: "\n"))
    }

    private func requireEnvironment(_ name: String) throws {
        guard ProcessInfo.processInfo.environment[name] == "1" else {
            throw XCTSkip("Set \(name)=1 to run local disk image matrix tests")
        }
    }

    private func localDiskURLs(limitEnv: String, defaultLimit: Int? = nil) throws -> [URL] {
        let root = localDiskRoot
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let filter = ProcessInfo.processInfo.environment["SWIFT64_LOCAL_DISK_FILTER"]?.lowercased()
        let urls = try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { return nil }
            if let filter, !url.path.lowercased().contains(filter) {
                return nil
            }
            switch url.pathExtension.lowercased() {
            case "d64", "g64":
                return url
            default:
                return nil
            }
        }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        let limit = Int(ProcessInfo.processInfo.environment[limitEnv] ?? "")
            ?? defaultLimit
            ?? urls.count
        return Array(urls.prefix(max(0, limit)))
    }

    private var localDiskRoot: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("C64/DISKS")
    }

    private func runUntilDirectoryLoadMilestone(_ c64: C64) -> MatrixRunResult {
        let baseline = c64.drive1541.statusSnapshot
        var sawTalkSecondary = false
        var sawUntalk = false
        var sawCloseListen = false
        var sawGCRRead = false
        var sawLoadEndAddress = false
        var sawEOFStatus = false

        for _ in 0..<8_000_000 {
            c64.tickOneCycle()
            if let reason = c64.emulationStatus.lastFailureReason {
                return MatrixRunResult(passed: false, elapsedCycles: c64.cpu.totalCycles, reason: reason)
            }

            sawTalkSecondary = sawTalkSecondary || c64.drive1541.decodedIECCommandBytes.contains(0x60)
            sawUntalk = sawUntalk || c64.drive1541.decodedIECCommandBytes.contains(0x5F)
            sawCloseListen = sawCloseListen || c64.drive1541.decodedIECCommandBytes.contains(0xE0)
            sawGCRRead = sawGCRRead || c64.drive1541.statusSnapshot.via2PortAReadCount > baseline.via2PortAReadCount

            let loadEndAddress = UInt16(c64.memory.ram[0xAE]) | (UInt16(c64.memory.ram[0xAF]) << 8)
            sawLoadEndAddress = sawLoadEndAddress || loadEndAddress > 0x0801
            if sawLoadEndAddress {
                sawEOFStatus = sawEOFStatus || c64.memory.ram[0x90] == 0x40
            }

            if sawTalkSecondary && sawUntalk && sawCloseListen && sawGCRRead && sawLoadEndAddress && sawEOFStatus {
                return MatrixRunResult(passed: true, elapsedCycles: c64.cpu.totalCycles, reason: "directory milestone reached")
            }
        }

        return MatrixRunResult(passed: false, elapsedCycles: c64.cpu.totalCycles, reason: "directory milestone timeout")
    }

    private func runUntilMilestone(_ c64: C64, milestone: LocalMilestone) -> MatrixRunResult {
        let baseline = c64.drive1541.statusSnapshot

        for _ in 0..<milestone.maxCycles {
            c64.tickOneCycle()

            if let reason = c64.emulationStatus.lastFailureReason {
                return MatrixRunResult(passed: false, elapsedCycles: c64.cpu.totalCycles, reason: reason)
            }
            if c64.cpu.jammed || c64.drive1541.cpu.jammed {
                return MatrixRunResult(passed: false, elapsedCycles: c64.cpu.totalCycles, reason: "CPU JAM/KIL")
            }
            if c64.cpu.pc == 0xFFFF {
                return MatrixRunResult(passed: false, elapsedCycles: c64.cpu.totalCycles, reason: "C64 PC reached $FFFF")
            }

            let driveStatus = c64.drive1541.statusSnapshot
            let gcrReads = driveStatus.via2PortAReadCount - baseline.via2PortAReadCount
            let byteReady = driveStatus.byteReadyCount - baseline.byteReadyCount
            let pcReached = milestone.pcRange?.contains(c64.cpu.pc) ?? true
            let driveProgress = gcrReads >= milestone.minGCRReads && byteReady >= milestone.minByteReady
            let ramMatches = milestone.ramSignatures.allSatisfy { signature in
                let start = signature.address
                let end = start + signature.bytes.count
                guard start >= 0 && end <= c64.memory.ram.count else { return false }
                return Array(c64.memory.ram[start..<end]) == signature.bytes
            }
            let screenMatches = milestone.screenRAMHash.map {
                CompatibilityHash.screenRAM(c64.memory.ram).caseInsensitiveCompare($0) == .orderedSame
            } ?? true

            if pcReached && driveProgress && ramMatches && screenMatches {
                return MatrixRunResult(passed: true, elapsedCycles: c64.cpu.totalCycles, reason: "named milestone reached")
            }
        }

        return MatrixRunResult(passed: false, elapsedCycles: c64.cpu.totalCycles, reason: "named milestone timeout")
    }

    private func localMilestones() throws -> [LocalMilestone] {
        let urls = try localDiskURLs(limitEnv: "SWIFT64_LOCAL_MILESTONE_LIMIT")
        let manifestMilestones = try loadManifestMilestones(urls: urls)
        if !manifestMilestones.isEmpty {
            return manifestMilestones
        }

        guard let giana = urls.first(where: {
            $0.lastPathComponent.lowercased().contains("great_giana_sisters")
            && $0.pathExtension.lowercased() == "g64"
        }) else {
            return []
        }

        return [
            LocalMilestone(
                url: giana,
                machineProfile: .palC64,
                command: #"LOAD"*",8,1"#,
                maxCycles: Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_MILESTONE_MAX_CYCLES"] ?? "") ?? 1_500_000,
                pcRange: nil,
                minGCRReads: UInt64(Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_MILESTONE_MIN_GCR_READS"] ?? "") ?? 0),
                minByteReady: UInt64(Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_MILESTONE_MIN_BYTE_READY"] ?? "") ?? 256),
                ramSignatures: [],
                screenRAMHash: nil
            )
        ]
    }

    private func loadManifestMilestones(urls: [URL]) throws -> [LocalMilestone] {
        let manifestURL = localDiskRoot.appendingPathComponent("compatibility.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return []
        }

        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(contentsOf: manifestURL))
        return manifest.milestones.compactMap { entry in
            guard let url = urls.first(where: { $0.lastPathComponent == entry.file || $0.path.contains(entry.file) }) else {
                return nil
            }
            return LocalMilestone(
                url: url,
                machineProfile: entry.machineProfile ?? .palC64,
                command: entry.command,
                maxCycles: entry.maxCycles ?? 24_000_000,
                pcRange: entry.pcRange,
                minGCRReads: UInt64(entry.minGCRReads ?? 64),
                minByteReady: UInt64(entry.minByteReady ?? 512),
                ramSignatures: entry.ramSignatures,
                screenRAMHash: entry.screenRAMHash
            )
        }
    }

    private func matrixSummary(_ message: String, url: URL, gcrDisk: GCRDisk) -> String {
        let caps = gcrDisk.image?.capabilities
        return "\(message) for \(url.path) format=\(caps?.format.displayName ?? "unknown") halftracks=\(caps?.populatedHalfTrackCount ?? 0) native=\(caps?.nativeLowLevelTrackCount ?? 0) synthetic=\(caps?.syntheticGCRTrackCount ?? 0)"
    }

    private func loadBundledROMs(into c64: C64) throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let roms = root.appendingPathComponent("Sources/C64App/ROMS")
        let basic = try Data(contentsOf: roms.appendingPathComponent("C64-901226-01-Commodore-F833D117-Basic.rom"))
        let kernal = try Data(contentsOf: roms.appendingPathComponent("C64-901227-03-Commodore-DBE3E7C7-Kernal.rom"))
        let charset = try Data(contentsOf: roms.appendingPathComponent("C64-901225-01-Commodore-EC4272EE-Characters.rom"))
        let drive = try Data(contentsOf: roms.appendingPathComponent("1541C.251968-02.bin"))

        c64.loadROMs(basic: basic, kernal: kernal, charset: charset)
        c64.loadDriveROM(drive)
    }
}

private struct MatrixRunResult {
    let passed: Bool
    let elapsedCycles: UInt64
    let reason: String

    func summary(name: String, command: String, c64: C64) -> String {
        let drive = c64.drive1541.statusSnapshot
        let verdict = passed ? "PASS" : "FAIL"
        return "\(verdict) \(name) command=\(command) cycles=\(elapsedCycles) pc=$\(hex16(c64.cpu.pc)) drivePC=$\(hex16(drive.cpuPC)) track=\(drive.track) half=\(drive.halfTrack) iec=[\(drive.lastIECCommandSummary)] byteReady=\(drive.byteReadyCount) paReads=\(drive.via2PortAReadCount) reason=\(reason)"
    }

    private func hex16(_ value: UInt16) -> String {
        String(format: "%04X", value)
    }
}

private struct LocalMilestone {
    let url: URL
    let machineProfile: CompatibilityMachineProfile
    let command: String
    let maxCycles: Int
    let pcRange: ClosedRange<UInt16>?
    let minGCRReads: UInt64
    let minByteReady: UInt64
    let ramSignatures: [CompatibilityRAMSignature]
    let screenRAMHash: String?
}
