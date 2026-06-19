import XCTest
@testable import C64Core

final class LocalDiskMatrixTests: XCTestCase {
    private let matrixEnv = "SWIFT64_LOCAL_DISK_MATRIX"
    private let trueDriveEnv = "SWIFT64_LOCAL_TRUE_DRIVE_MATRIX"
    private let milestoneEnv = "SWIFT64_LOCAL_MILESTONE_MATRIX"
    private let gianaRunEnv = "SWIFT64_LOCAL_GIANA_RUN_SMOKE"
    private let gianaFastRunEnv = "SWIFT64_LOCAL_GIANA_FAST_RUN_SMOKE"
    private let milestoneResultLogEnv = "SWIFT64_LOCAL_MILESTONE_RESULTS_JSONL"
    private let milestoneResumeEnv = "SWIFT64_LOCAL_MILESTONE_RESUME"
    private let milestoneScreenshotDirEnv = "SWIFT64_LOCAL_MILESTONE_SCREENSHOT_DIR"
    private let milestoneSummaryEnv = "SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON"

    func testLocalDiskImagesMountAndEncodeWhenEnabled() throws {
        try requireEnvironment(matrixEnv)

        let urls = try localMediaURLs(limitEnv: "SWIFT64_LOCAL_DISK_LIMIT", extensions: Self.diskImageExtensions)
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

        let urls = try localMediaURLs(limitEnv: "SWIFT64_LOCAL_TRUE_DRIVE_LIMIT", defaultLimit: 1, extensions: Self.diskImageExtensions)
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

        let resultLogURL = milestoneResultLogURL()
        let passedMilestones = shouldResumeMilestoneResults
            ? try passedMilestoneKeys(from: resultLogURL)
            : []
        let screenshotDirectoryURL = milestoneScreenshotDirectoryURL()
        let summaryURL = milestoneSummaryURL()
        var summaries: [String] = []
        var runSummary = MilestoneRunSummary()
        for milestone in milestones {
            if passedMilestones.contains(milestone.resultKey) {
                summaries.append("SKIP \(milestone.url.lastPathComponent) command=\(milestone.commandSummary) reason=previous pass in result log")
                runSummary.recordSkipped(milestone)
                continue
            }

            let c64 = C64(machineProfile: milestone.machineProfile.profile)
            try loadBundledROMs(into: c64)
            c64.trueDriveEmulationMode = milestone.driveMode.trueDriveMode
            XCTAssertTrue(mountPrePowerOnMedia(for: milestone, into: c64), "Failed to mount \(milestone.url.path)")
            c64.powerOn()
            XCTAssertTrue(mountPostPowerOnMedia(for: milestone, into: c64), "Failed to load \(milestone.url.path)")

            for _ in 0..<20 {
                XCTAssertTrue(c64.runFrame())
            }

            for command in milestone.commands {
                c64.typeText(command + "\r")
            }
            let result = runUntilMilestone(c64, milestone: milestone)
            let summary = result.summary(name: milestone.url.lastPathComponent, command: milestone.commandSummary, c64: c64)
            summaries.append(summary)
            var screenshotURL: URL?
            if result.passed {
                screenshotURL = try writeMilestoneScreenshot(for: milestone, c64: c64, to: screenshotDirectoryURL)
            }
            let record = result.record(for: milestone, c64: c64, screenshotURL: screenshotURL)
            runSummary.record(record)
            try appendMilestoneResult(record, to: resultLogURL)
            XCTAssertTrue(result.passed, summary)
        }
        try writeMilestoneRunSummary(runSummary, to: summaryURL)
        print("Local named milestone matrix:\n" + summaries.joined(separator: "\n") + "\n" + runSummary.consoleSummary)
    }

    func testLocalGreatGianaSistersRunSmokeWhenEnabled() throws {
        try requireEnvironment(gianaRunEnv)

        let urls = try localMediaURLs(limitEnv: "SWIFT64_LOCAL_GIANA_RUN_LIMIT", extensions: Self.diskImageExtensions)
        let giana = try XCTUnwrap(urls.first {
            $0.lastPathComponent.lowercased().contains("great_giana_sisters")
            && $0.pathExtension.lowercased() == "g64"
        })

        let c64 = C64(machineProfile: .palC64)
        try loadBundledROMs(into: c64)
        c64.trueDriveEmulationMode = .compat1541
        XCTAssertTrue(c64.mountDisk(giana), "Failed to mount \(giana.path)")
        c64.powerOn()

        for _ in 0..<20 {
            XCTAssertTrue(c64.runFrame())
        }

        let baseline = c64.drive1541.statusSnapshot
        c64.typeText("LOAD\"*\",8,1\rRUN\r")

        let maxCycles = Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_RUN_MAX_CYCLES"] ?? "") ?? 8_000_000
        var loaded = false
        var loadScreenHash: String?
        var screenChangedAfterLoad = false
        var ranPostLoadCycles = 0
        var enteredProgramCode = false

        for _ in 0..<maxCycles {
            c64.tickOneCycle()
            enteredProgramCode = enteredProgramCode || (0x0801...0xBFFF).contains(c64.cpu.pc)

            let loadEndAddress = UInt16(c64.memory.ram[0xAE]) | (UInt16(c64.memory.ram[0xAF]) << 8)
            if !loaded && loadEndAddress > 0x0900 {
                loaded = true
                loadScreenHash = CompatibilityHash.screenRAM(c64.memory.ram)
            }

            if loaded {
                ranPostLoadCycles += 1
                if ranPostLoadCycles > 200_000,
                   let loadScreenHash,
                   CompatibilityHash.screenRAM(c64.memory.ram) != loadScreenHash {
                    screenChangedAfterLoad = true
                    break
                }
            }
        }

        let drive = c64.drive1541.statusSnapshot
        let pc = String(format: "%04X", c64.cpu.pc)
        let drivePC = String(format: "%04X", drive.cpuPC)
        let loadEndAddress = UInt16(c64.memory.ram[0xAE]) | (UInt16(c64.memory.ram[0xAF]) << 8)
        let loadEnd = String(format: "%04X", loadEndAddress)
        let summary = "Giana run smoke loaded=\(loaded) enteredProgramCode=\(enteredProgramCode) screenChangedAfterLoad=\(screenChangedAfterLoad) cycles=\(c64.cpu.totalCycles) pc=$\(pc) drivePC=$\(drivePC) loadEnd=$\(loadEnd) byteReady=\(drive.byteReadyCount - baseline.byteReadyCount) paReads=\(drive.via2PortAReadCount - baseline.via2PortAReadCount) reason=\(c64.emulationStatus.lastFailureReason ?? "none")"
        print(summary)

        XCTAssertTrue(loaded || enteredProgramCode, summary)
    }

    func testLocalGreatGianaSistersFastRunSmokeWhenEnabled() throws {
        try requireEnvironment(gianaFastRunEnv)

        let urls = try localMediaURLs(limitEnv: "SWIFT64_LOCAL_GIANA_RUN_LIMIT", extensions: Self.diskImageExtensions)
        let giana = try XCTUnwrap(urls.first {
            $0.lastPathComponent.lowercased().contains("great_giana_sisters")
            && $0.pathExtension.lowercased() == "g64"
        })

        let c64 = C64(machineProfile: .palC64)
        try loadBundledROMs(into: c64)
        c64.trueDriveEmulationMode = .off
        XCTAssertTrue(c64.mountDisk(giana), "Failed to mount \(giana.path)")
        c64.powerOn()

        for _ in 0..<20 {
            XCTAssertTrue(c64.runFrame())
        }

        c64.typeText("LOAD\"*\",8,1\rRUN\r")
        let maxCycles = Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_FAST_RUN_MAX_CYCLES"] ?? "") ?? 4_000_000
        var loaded = false
        var loadScreenHash: String?
        var screenChangedAfterLoad = false
        var ranPostLoadCycles = 0
        var enteredProgramCode = false

        for _ in 0..<maxCycles {
            c64.tickOneCycle()
            enteredProgramCode = enteredProgramCode || (0x0801...0xBFFF).contains(c64.cpu.pc)

            let loadEndAddress = UInt16(c64.memory.ram[0xAE]) | (UInt16(c64.memory.ram[0xAF]) << 8)
            if !loaded && loadEndAddress > 0x0900 {
                loaded = true
                loadScreenHash = CompatibilityHash.screenRAM(c64.memory.ram)
            }

            if loaded {
                ranPostLoadCycles += 1
                if ranPostLoadCycles > 200_000,
                   let loadScreenHash,
                   CompatibilityHash.screenRAM(c64.memory.ram) != loadScreenHash {
                    screenChangedAfterLoad = true
                    break
                }
            }
        }

        let pc = String(format: "%04X", c64.cpu.pc)
        let loadEndAddress = UInt16(c64.memory.ram[0xAE]) | (UInt16(c64.memory.ram[0xAF]) << 8)
        let loadEnd = String(format: "%04X", loadEndAddress)
        let summary = "Giana fast run smoke loaded=\(loaded) enteredProgramCode=\(enteredProgramCode) screenChangedAfterLoad=\(screenChangedAfterLoad) cycles=\(c64.cpu.totalCycles) pc=$\(pc) loadEnd=$\(loadEnd) reason=\(c64.emulationStatus.lastFailureReason ?? "none")"
        print(summary)

        XCTAssertTrue(loaded || enteredProgramCode, summary)
    }

    func testNamedMilestoneFailureReasonReportsUnmetExpectations() {
        let c64 = C64()
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/missing.d64"),
            mediaType: .d64,
            machineProfile: .palC64,
            driveMode: .compat1541,
            commands: [#"LOAD"*",8,1"#],
            maxCycles: 1,
            pcRanges: [0xC000...0xC0FF],
            minGCRReads: 1,
            minByteReady: 1,
            driveStatus: CompatibilityDriveStatus(track: 18, hasDisk: true),
            mediaStatus: CompatibilityMediaStatus(isNativeLowLevel: true),
            ramSignatures: [CompatibilityRAMSignature(address: 0x0801, bytes: [0x01, 0x08])],
            colorRAMSignatures: [CompatibilityRAMSignature(address: 0, bytes: [0x01, 0x02])],
            screenRAMHash: "0000000000000000",
            colorRAMHash: "1111111111111111",
            screenshotName: nil
        )

        let reason = namedMilestoneFailureReason(
            c64,
            milestone: milestone,
            baseline: c64.drive1541.statusSnapshot
        )

        XCTAssertTrue(reason.contains("PC $"))
        XCTAssertTrue(reason.contains("GCR reads 0 < 1"))
        XCTAssertTrue(reason.contains("byte-ready 0 < 1"))
        XCTAssertTrue(reason.contains("drive.track"))
        XCTAssertTrue(reason.contains("drive.hasDisk"))
        XCTAssertTrue(reason.contains("media capabilities unavailable"))
        XCTAssertTrue(reason.contains("RAM $0801"))
        XCTAssertTrue(reason.contains("color RAM $0000"))
        XCTAssertTrue(reason.contains("screen hash"))
        XCTAssertTrue(reason.contains("color RAM hash"))
    }

    func testMilestoneResultLogRoundTripsPassedEntriesForResume() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("milestones.jsonl")
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/demo.g64"),
            mediaType: .g64,
            machineProfile: .palC64,
            driveMode: .compat1541,
            commands: [#"LOAD"*",8,1"#, "RUN"],
            maxCycles: 1,
            pcRanges: [],
            minGCRReads: 0,
            minByteReady: 0,
            driveStatus: nil,
            mediaStatus: nil,
            ramSignatures: [],
            colorRAMSignatures: [],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        try appendMilestoneResult(
            MatrixRunResult(passed: false, elapsedCycles: 10, reason: "first failure").record(for: milestone, c64: C64()),
            to: logURL
        )
        try appendMilestoneResult(
            MatrixRunResult(passed: true, elapsedCycles: 20, reason: "named milestone reached").record(
                for: milestone,
                c64: C64(),
                screenshotURL: URL(fileURLWithPath: "/tmp/swift64-screens/demo.ppm")
            ),
            to: logURL
        )

        let passed = try passedMilestoneKeys(from: logURL)
        let log = try String(contentsOf: logURL, encoding: .utf8)

        XCTAssertTrue(passed.contains(milestone.resultKey))
        XCTAssertTrue(log.contains("\"passed\":false"))
        XCTAssertTrue(log.contains("\"passed\":true"))
        XCTAssertTrue(log.contains(#""commandSummary":"LOAD\"*\",8,1 | RUN""#))
        XCTAssertTrue(log.contains(#""category":"#))
        XCTAssertTrue(log.contains(#""finalPC":"#))
        XCTAssertTrue(log.contains(#""screenRAMHash":"#))
        let records = try log.split(separator: "\n").map {
            try JSONDecoder().decode(MilestoneResultRecord.self, from: Data(String($0).utf8))
        }
        XCTAssertEqual(records.last?.screenshotPath, "/tmp/swift64-screens/demo.ppm")

        let legacyURL = directory.appendingPathComponent("legacy.jsonl")
        let legacyLine = #"{"commandSummary":"LOAD\"*\",8,1 | RUN","driveMode":"compat1541","elapsedCycles":5,"file":"demo.g64","machineProfile":"palC64","passed":true,"reason":"old pass"}"#
        try Data((legacyLine + "\n").utf8).write(to: legacyURL)

        XCTAssertTrue(try passedMilestoneKeys(from: legacyURL).contains(milestone.resultKey))
    }

    func testMilestoneRunSummaryWritesAggregateJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("summary.json")
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/demo.g64"),
            mediaType: .g64,
            machineProfile: .palC64,
            driveMode: .compat1541,
            commands: [#"LOAD"*",8,1"#],
            maxCycles: 1,
            pcRanges: [],
            minGCRReads: 0,
            minByteReady: 0,
            driveStatus: nil,
            mediaStatus: nil,
            ramSignatures: [],
            colorRAMSignatures: [],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )
        var summary = MilestoneRunSummary()
        summary.record(MatrixRunResult(passed: true, elapsedCycles: 10, reason: "named milestone reached").record(for: milestone, c64: C64()))
        summary.record(MatrixRunResult(passed: false, elapsedCycles: 20, reason: "PC $0801 not in $C000-$C0FF").record(for: milestone, c64: C64()))
        summary.recordSkipped(milestone)

        try writeMilestoneRunSummary(summary, to: url)

        let decoded = try JSONDecoder().decode(MilestoneRunSummary.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.total, 3)
        XCTAssertEqual(decoded.executed, 2)
        XCTAssertEqual(decoded.passed, 1)
        XCTAssertEqual(decoded.failed, 1)
        XCTAssertEqual(decoded.skipped, 1)
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.totalElapsedCycles, 30)
        XCTAssertEqual(decoded.maxElapsedCycles, 20)
        XCTAssertEqual(decoded.slowestMilestone, milestone.resultKey)
        XCTAssertEqual(decoded.categories["pass"], 1)
        XCTAssertEqual(decoded.categories["pc"], 1)
        XCTAssertEqual(decoded.failedMilestones, [milestone.resultKey])
        XCTAssertEqual(decoded.failedMilestoneDetails, [
            MilestoneFailureSummary(
                key: milestone.resultKey,
                category: "pc",
                reason: "PC $0801 not in $C000-$C0FF",
                elapsedCycles: 20
            )
        ])
        XCTAssertEqual(decoded.skippedMilestones, [milestone.resultKey])
        XCTAssertTrue(decoded.consoleSummary.contains("total=3"))
        XCTAssertTrue(decoded.consoleSummary.contains("executed=2"))
        XCTAssertTrue(decoded.consoleSummary.contains("pc=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("cycles=30"))
    }

    func testNamedMilestoneRequiresColorRAMHash() {
        let c64 = C64()
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/demo.prg"),
            mediaType: .prg,
            machineProfile: .palC64,
            driveMode: .fastLoad,
            commands: [],
            maxCycles: 1,
            pcRanges: [],
            minGCRReads: 0,
            minByteReady: 0,
            driveStatus: nil,
            mediaStatus: nil,
            ramSignatures: [],
            colorRAMSignatures: [],
            screenRAMHash: nil,
            colorRAMHash: "1111111111111111",
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .screen)
        XCTAssertTrue(result.reason.contains("color RAM hash"))
    }

    func testNamedMilestoneRequiresColorRAMSignature() {
        let c64 = C64()
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/demo.prg"),
            mediaType: .prg,
            machineProfile: .palC64,
            driveMode: .fastLoad,
            commands: [],
            maxCycles: 1,
            pcRanges: [],
            minGCRReads: 0,
            minByteReady: 0,
            driveStatus: nil,
            mediaStatus: nil,
            ramSignatures: [],
            colorRAMSignatures: [CompatibilityRAMSignature(address: 0, bytes: [0x01])],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .screen)
        XCTAssertTrue(result.reason.contains("color RAM $0000"))
    }

    func testMilestoneResultCategoriesAreStable() {
        XCTAssertEqual(MatrixRunResult(passed: true, elapsedCycles: 1, reason: "named milestone reached").category, .pass)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "CPU JAM/KIL").category, .cpu)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "C64 PC reached $FFFF").category, .cpu)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "PC $0801 not in $C000-$C0FF").category, .pc)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "GCR reads 0 < 64").category, .drive)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "media capabilities unavailable").category, .media)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "RAM $0801 00 != 01").category, .ram)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "color RAM $0000 00 != 01").category, .screen)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "screen hash abc != def").category, .screen)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "named milestone timeout").category, .timeout)
    }

    func testLegacyMilestoneResultRecordsDecodeWithoutCategory() throws {
        let legacyLine = #"{"commandSummary":"RUN","driveMode":"fastLoad","elapsedCycles":5,"file":"demo.prg","machineProfile":"palC64","passed":false,"reason":"named milestone timeout"}"#
        let record = try JSONDecoder().decode(MilestoneResultRecord.self, from: Data(legacyLine.utf8))

        XCTAssertNil(record.category)
        XCTAssertEqual(record.key.file, "demo.prg")
    }

    func testPPMScreenshotWriterSanitizesNameAndWritesFramebuffer() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let c64 = C64()
        c64.vic.framebuffer[0] = ColorPalette.rgba[2]
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/demo.g64"),
            mediaType: .g64,
            machineProfile: .palC64,
            driveMode: .compat1541,
            commands: [#"LOAD"*",8,1"#],
            maxCycles: 1,
            pcRanges: [],
            minGCRReads: 0,
            minByteReady: 0,
            driveStatus: nil,
            mediaStatus: nil,
            ramSignatures: [],
            colorRAMSignatures: [],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: "../title screen"
        )

        let screenshotURL = try XCTUnwrap(writeMilestoneScreenshot(for: milestone, c64: c64, to: directory))
        XCTAssertEqual(screenshotURL.lastPathComponent, "title_screen.ppm")
        let data = try Data(contentsOf: screenshotURL)
        let header = "P6\n\(VIC.screenWidth) \(VIC.screenHeight)\n255\n"
        let headerData = Data(header.utf8)

        XCTAssertTrue(data.starts(with: headerData))
        XCTAssertEqual(data[headerData.count], 0x88)
        XCTAssertEqual(data[headerData.count + 1], 0x39)
        XCTAssertEqual(data[headerData.count + 2], 0x32)
    }

    private func requireEnvironment(_ name: String) throws {
        guard ProcessInfo.processInfo.environment[name] == "1" else {
            throw XCTSkip("Set \(name)=1 to run local disk image matrix tests")
        }
    }

    private static let diskImageExtensions: Set<String> = ["d64", "g64"]
    private static let milestoneMediaExtensions: Set<String> = ["prg", "d64", "g64", "t64", "tap", "crt"]

    private func localMediaURLs(
        limitEnv: String,
        defaultLimit: Int? = nil,
        extensions allowedExtensions: Set<String>
    ) throws -> [URL] {
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
            return allowedExtensions.contains(url.pathExtension.lowercased()) ? url : nil
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

    private var shouldResumeMilestoneResults: Bool {
        ProcessInfo.processInfo.environment[milestoneResumeEnv] == "1"
    }

    private func milestoneResultLogURL() -> URL? {
        guard let path = ProcessInfo.processInfo.environment[milestoneResultLogEnv],
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func milestoneScreenshotDirectoryURL() -> URL? {
        guard let path = ProcessInfo.processInfo.environment[milestoneScreenshotDirEnv],
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func milestoneSummaryURL() -> URL? {
        guard let path = ProcessInfo.processInfo.environment[milestoneSummaryEnv],
              !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
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
            let syncDetections = driveStatus.syncDetectionCount - baseline.syncDetectionCount
            let pcReached = milestone.pcRanges.isEmpty || milestone.pcRanges.contains { $0.contains(c64.cpu.pc) }
            let driveProgress = gcrReads >= milestone.minGCRReads && byteReady >= milestone.minByteReady
            let driveExpectationMatches = milestone.driveStatus.map { expectation in
                driveStatusMismatches(
                    expectation,
                    snapshot: driveStatus,
                    gcrReads: gcrReads,
                    byteReady: byteReady,
                    syncDetections: syncDetections
                ).isEmpty
            } ?? true
            let mediaExpectationMatches = milestone.mediaStatus.map { expectation in
                mediaStatusMismatches(expectation, capabilities: c64.emulationStatus.mediaCapabilities).isEmpty
            } ?? true
            let ramMatches = milestone.ramSignatures.allSatisfy { signature in
                let start = signature.address
                let end = start + signature.bytes.count
                guard start >= 0 && end <= c64.memory.ram.count else { return false }
                return Array(c64.memory.ram[start..<end]) == signature.bytes
            }
            let colorRAMMatches = milestone.colorRAMSignatures.allSatisfy { signature in
                let start = signature.address
                let end = start + signature.bytes.count
                guard start >= 0 && end <= c64.memory.colorRAM.count else { return false }
                let actual = c64.memory.colorRAM[start..<end].map { $0 & 0x0F }
                let expected = signature.bytes.map { $0 & 0x0F }
                return actual == expected
            }
            let screenMatches = milestone.screenRAMHash.map {
                CompatibilityHash.screenRAM(c64.memory.ram).caseInsensitiveCompare($0) == .orderedSame
            } ?? true
            let colorRAMHashMatches = milestone.colorRAMHash.map {
                CompatibilityHash.colorRAM(c64.memory.colorRAM).caseInsensitiveCompare($0) == .orderedSame
            } ?? true

            if pcReached
                && driveProgress
                && driveExpectationMatches
                && mediaExpectationMatches
                && ramMatches
                && colorRAMMatches
                && screenMatches
                && colorRAMHashMatches {
                return MatrixRunResult(passed: true, elapsedCycles: c64.cpu.totalCycles, reason: "named milestone reached")
            }
        }

        return MatrixRunResult(
            passed: false,
            elapsedCycles: c64.cpu.totalCycles,
            reason: namedMilestoneFailureReason(c64, milestone: milestone, baseline: baseline)
        )
    }

    private func localMilestones() throws -> [LocalMilestone] {
        let urls = try localMediaURLs(limitEnv: "SWIFT64_LOCAL_MILESTONE_LIMIT", extensions: Self.milestoneMediaExtensions)
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
                mediaType: .g64,
                machineProfile: .palC64,
                driveMode: .compat1541,
                commands: [#"LOAD"*",8,1"#],
                maxCycles: Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_MILESTONE_MAX_CYCLES"] ?? "") ?? 1_500_000,
                pcRanges: [],
                minGCRReads: UInt64(Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_MILESTONE_MIN_GCR_READS"] ?? "") ?? 0),
                minByteReady: UInt64(Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_MILESTONE_MIN_BYTE_READY"] ?? "") ?? 256),
                driveStatus: nil,
                mediaStatus: nil,
                ramSignatures: [],
                colorRAMSignatures: [],
                screenRAMHash: nil,
                colorRAMHash: nil,
                screenshotName: nil
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
            let driveMode = entry.driveMode ?? .compat1541
            let mediaType = entry.mediaType ?? mediaType(for: url)
            return LocalMilestone(
                url: url,
                mediaType: mediaType,
                machineProfile: entry.machineProfile ?? .palC64,
                driveMode: driveMode,
                commands: entry.commands,
                maxCycles: entry.maxCycles ?? 24_000_000,
                pcRanges: entry.expectedPCRanges,
                minGCRReads: nonNegativeUInt64(entry.driveStatus?.minGCRReads ?? entry.minGCRReads ?? defaultMinGCRReads(for: driveMode)),
                minByteReady: nonNegativeUInt64(entry.driveStatus?.minByteReady ?? entry.minByteReady ?? defaultMinByteReady(for: driveMode)),
                driveStatus: entry.driveStatus,
                mediaStatus: entry.mediaStatus,
                ramSignatures: entry.ramSignatures,
                colorRAMSignatures: entry.colorRAMSignatures,
                screenRAMHash: entry.screenRAMHash,
                colorRAMHash: entry.colorRAMHash,
                screenshotName: entry.screenshotName
            )
        }
    }

    private func mountPrePowerOnMedia(for milestone: LocalMilestone, into c64: C64) -> Bool {
        switch milestone.mediaType {
        case .d64, .g64:
            return c64.mountDisk(milestone.url)
        case .t64, .tap:
            return c64.mountTape(milestone.url)
        case .crt:
            return c64.mountCartridge(milestone.url)
        case .prg:
            return true
        }
    }

    private func mountPostPowerOnMedia(for milestone: LocalMilestone, into c64: C64) -> Bool {
        guard milestone.mediaType == .prg else { return true }
        guard PRGLoader.loadFromFile(milestone.url) != nil else { return false }
        c64.loadPRG(milestone.url)
        return true
    }

    private func mediaType(for url: URL) -> CompatibilityMediaType {
        switch url.pathExtension.lowercased() {
        case "prg": return .prg
        case "g64": return .g64
        case "t64": return .t64
        case "tap": return .tap
        case "crt": return .crt
        default: return .d64
        }
    }

    private func namedMilestoneFailureReason(
        _ c64: C64,
        milestone: LocalMilestone,
        baseline: Drive1541.StatusSnapshot
    ) -> String {
        let driveStatus = c64.drive1541.statusSnapshot
        let gcrReads = driveStatus.via2PortAReadCount - baseline.via2PortAReadCount
        let byteReady = driveStatus.byteReadyCount - baseline.byteReadyCount
        let syncDetections = driveStatus.syncDetectionCount - baseline.syncDetectionCount
        var unmet: [String] = []

        if !milestone.pcRanges.isEmpty && !milestone.pcRanges.contains(where: { $0.contains(c64.cpu.pc) }) {
            unmet.append("PC $\(hex16(c64.cpu.pc)) not in \(formatRanges(milestone.pcRanges))")
        }
        if gcrReads < milestone.minGCRReads {
            unmet.append("GCR reads \(gcrReads) < \(milestone.minGCRReads)")
        }
        if byteReady < milestone.minByteReady {
            unmet.append("byte-ready \(byteReady) < \(milestone.minByteReady)")
        }
        if let driveStatusExpectation = milestone.driveStatus {
            unmet.append(contentsOf: driveStatusMismatches(
                driveStatusExpectation,
                snapshot: driveStatus,
                gcrReads: gcrReads,
                byteReady: byteReady,
                syncDetections: syncDetections
            ))
        }
        if let mediaStatusExpectation = milestone.mediaStatus {
            unmet.append(contentsOf: mediaStatusMismatches(
                mediaStatusExpectation,
                capabilities: c64.emulationStatus.mediaCapabilities
            ))
        }
        unmet.append(contentsOf: ramSignatureMismatches(
            milestone.ramSignatures,
            ram: c64.memory.ram,
            label: "RAM",
            valueMask: nil
        ))
        unmet.append(contentsOf: ramSignatureMismatches(
            milestone.colorRAMSignatures,
            ram: c64.memory.colorRAM,
            label: "color RAM",
            valueMask: 0x0F
        ))
        if let expectedScreenHash = milestone.screenRAMHash {
            let actualScreenHash = CompatibilityHash.screenRAM(c64.memory.ram)
            if actualScreenHash.caseInsensitiveCompare(expectedScreenHash) != .orderedSame {
                unmet.append("screen hash \(actualScreenHash) != \(expectedScreenHash)")
            }
        }
        if let expectedColorRAMHash = milestone.colorRAMHash {
            let actualColorRAMHash = CompatibilityHash.colorRAM(c64.memory.colorRAM)
            if actualColorRAMHash.caseInsensitiveCompare(expectedColorRAMHash) != .orderedSame {
                unmet.append("color RAM hash \(actualColorRAMHash) != \(expectedColorRAMHash)")
            }
        }

        if unmet.isEmpty {
            return "named milestone timeout after all expectations matched"
        }
        return "named milestone timeout; unmet: " + unmet.joined(separator: "; ")
    }

    private func driveStatusMismatches(
        _ expectation: CompatibilityDriveStatus,
        snapshot: Drive1541.StatusSnapshot,
        gcrReads: UInt64,
        byteReady: UInt64,
        syncDetections: UInt64
    ) -> [String] {
        var mismatches: [String] = []
        if let minGCRReads = expectation.minGCRReads, gcrReads < nonNegativeUInt64(minGCRReads) {
            mismatches.append("drive.minGCRReads \(gcrReads) < \(minGCRReads)")
        }
        if let minByteReady = expectation.minByteReady, byteReady < nonNegativeUInt64(minByteReady) {
            mismatches.append("drive.minByteReady \(byteReady) < \(minByteReady)")
        }
        if let minSyncDetections = expectation.minSyncDetections,
           syncDetections < nonNegativeUInt64(minSyncDetections) {
            mismatches.append("drive.minSyncDetections \(syncDetections) < \(minSyncDetections)")
        }
        if let track = expectation.track, snapshot.track != track {
            mismatches.append("drive.track \(snapshot.track) != \(track)")
        }
        if let halfTrack = expectation.halfTrack, snapshot.halfTrack != halfTrack {
            mismatches.append("drive.halfTrack \(snapshot.halfTrack) != \(halfTrack)")
        }
        if let motorOn = expectation.motorOn, snapshot.motorOn != motorOn {
            mismatches.append("drive.motorOn \(snapshot.motorOn) != \(motorOn)")
        }
        if let ledOn = expectation.ledOn, snapshot.ledOn != ledOn {
            mismatches.append("drive.ledOn \(snapshot.ledOn) != \(ledOn)")
        }
        if let writeProtected = expectation.writeProtected, snapshot.writeProtected != writeProtected {
            mismatches.append("drive.writeProtected \(snapshot.writeProtected) != \(writeProtected)")
        }
        if let hasDisk = expectation.hasDisk, snapshot.hasDisk != hasDisk {
            mismatches.append("drive.hasDisk \(snapshot.hasDisk) != \(hasDisk)")
        }
        if let hasNativeLowLevelImage = expectation.hasNativeLowLevelImage,
           snapshot.hasNativeLowLevelImage != hasNativeLowLevelImage {
            mismatches.append("drive.hasNativeLowLevelImage \(snapshot.hasNativeLowLevelImage) != \(hasNativeLowLevelImage)")
        }
        if let lastIECCommandContains = expectation.lastIECCommandContains,
           !snapshot.lastIECCommandSummary.localizedCaseInsensitiveContains(lastIECCommandContains) {
            mismatches.append("drive.lastIECCommandSummary missing \(lastIECCommandContains)")
        }
        return mismatches
    }

    private func mediaStatusMismatches(
        _ expectation: CompatibilityMediaStatus,
        capabilities: DiskImage.Capabilities?
    ) -> [String] {
        guard let capabilities else { return ["media capabilities unavailable"] }
        var mismatches: [String] = []
        if let populatedHalfTrackCount = expectation.populatedHalfTrackCount,
           capabilities.populatedHalfTrackCount != populatedHalfTrackCount {
            mismatches.append("media.populatedHalfTrackCount \(capabilities.populatedHalfTrackCount) != \(populatedHalfTrackCount)")
        }
        if let nativeLowLevelTrackCount = expectation.nativeLowLevelTrackCount,
           capabilities.nativeLowLevelTrackCount != nativeLowLevelTrackCount {
            mismatches.append("media.nativeLowLevelTrackCount \(capabilities.nativeLowLevelTrackCount) != \(nativeLowLevelTrackCount)")
        }
        if let syntheticGCRTrackCount = expectation.syntheticGCRTrackCount,
           capabilities.syntheticGCRTrackCount != syntheticGCRTrackCount {
            mismatches.append("media.syntheticGCRTrackCount \(capabilities.syntheticGCRTrackCount) != \(syntheticGCRTrackCount)")
        }
        if let hasSyntheticGCR = expectation.hasSyntheticGCR,
           capabilities.hasSyntheticGCR != hasSyntheticGCR {
            mismatches.append("media.hasSyntheticGCR \(capabilities.hasSyntheticGCR) != \(hasSyntheticGCR)")
        }
        if let isNativeLowLevel = expectation.isNativeLowLevel,
           capabilities.isNativeLowLevel != isNativeLowLevel {
            mismatches.append("media.isNativeLowLevel \(capabilities.isNativeLowLevel) != \(isNativeLowLevel)")
        }
        if let preservesHalfTracks = expectation.preservesHalfTracks,
           capabilities.preservesHalfTracks != preservesHalfTracks {
            mismatches.append("media.preservesHalfTracks \(capabilities.preservesHalfTracks) != \(preservesHalfTracks)")
        }
        if let preservesRawTrackLengths = expectation.preservesRawTrackLengths,
           capabilities.preservesRawTrackLengths != preservesRawTrackLengths {
            mismatches.append("media.preservesRawTrackLengths \(capabilities.preservesRawTrackLengths) != \(preservesRawTrackLengths)")
        }
        if let preservesSpeedZones = expectation.preservesSpeedZones,
           capabilities.preservesSpeedZones != preservesSpeedZones {
            mismatches.append("media.preservesSpeedZones \(capabilities.preservesSpeedZones) != \(preservesSpeedZones)")
        }
        if let preservesVariableSpeedZones = expectation.preservesVariableSpeedZones,
           capabilities.preservesVariableSpeedZones != preservesVariableSpeedZones {
            mismatches.append("media.preservesVariableSpeedZones \(capabilities.preservesVariableSpeedZones) != \(preservesVariableSpeedZones)")
        }
        if let preservesSectorErrorInfo = expectation.preservesSectorErrorInfo,
           capabilities.preservesSectorErrorInfo != preservesSectorErrorInfo {
            mismatches.append("media.preservesSectorErrorInfo \(capabilities.preservesSectorErrorInfo) != \(preservesSectorErrorInfo)")
        }
        if let supportsWraparoundReads = expectation.supportsWraparoundReads,
           capabilities.supportsWraparoundReads != supportsWraparoundReads {
            mismatches.append("media.supportsWraparoundReads \(capabilities.supportsWraparoundReads) != \(supportsWraparoundReads)")
        }
        if let maxTrackSize = expectation.maxTrackSize,
           capabilities.maxTrackSize != maxTrackSize {
            mismatches.append("media.maxTrackSize \(capabilities.maxTrackSize.map(String.init) ?? "nil") != \(maxTrackSize)")
        }
        for expectedFeature in expectation.unsupportedFeaturesContains {
            guard capabilities.unsupportedFeatures.contains(where: {
                $0.localizedCaseInsensitiveContains(expectedFeature)
            }) else {
                mismatches.append("media.unsupportedFeatures missing \(expectedFeature)")
                continue
            }
        }
        return mismatches
    }

    private func ramSignatureMismatches(
        _ signatures: [CompatibilityRAMSignature],
        ram: [UInt8],
        label: String,
        valueMask: UInt8?
    ) -> [String] {
        func normalized(_ byte: UInt8) -> UInt8 {
            valueMask.map { byte & $0 } ?? byte
        }

        return signatures.compactMap { signature in
            let start = signature.address
            let end = start + signature.bytes.count
            guard start >= 0 && end <= ram.count else {
                return "\(label) $\(hex16(UInt16(truncatingIfNeeded: start))) out of range"
            }
            let actual = Array(ram[start..<end]).map(normalized)
            let expected = signature.bytes.map(normalized)
            guard actual != expected else { return nil }
            return "\(label) $\(hex16(UInt16(start))) \(formatBytes(actual)) != \(formatBytes(expected))"
        }
    }

    private func formatRanges(_ ranges: [ClosedRange<UInt16>]) -> String {
        ranges.map { "$\(hex16($0.lowerBound))-$\(hex16($0.upperBound))" }
            .joined(separator: ",")
    }

    private func formatBytes(_ bytes: [UInt8]) -> String {
        bytes.prefix(8)
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")
    }

    private func hex16(_ value: UInt16) -> String {
        String(format: "%04X", value)
    }

    private func nonNegativeUInt64(_ value: Int) -> UInt64 {
        UInt64(max(0, value))
    }

    private func defaultMinGCRReads(for driveMode: CompatibilityDriveMode) -> Int {
        driveMode == .fastLoad ? 0 : 64
    }

    private func defaultMinByteReady(for driveMode: CompatibilityDriveMode) -> Int {
        driveMode == .fastLoad ? 0 : 512
    }

    private func matrixSummary(_ message: String, url: URL, gcrDisk: GCRDisk) -> String {
        let caps = gcrDisk.image?.capabilities
        return "\(message) for \(url.path) format=\(caps?.format.displayName ?? "unknown") halftracks=\(caps?.populatedHalfTrackCount ?? 0) native=\(caps?.nativeLowLevelTrackCount ?? 0) synthetic=\(caps?.syntheticGCRTrackCount ?? 0)"
    }

    private func appendMilestoneResult(_ record: MilestoneResultRecord, to url: URL?) throws {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(record)
        data.append(0x0A)

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    private func writeMilestoneRunSummary(_ summary: MilestoneRunSummary, to url: URL?) throws {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(summary).write(to: url, options: .atomic)
    }

    private func passedMilestoneKeys(from url: URL?) throws -> Set<MilestoneResultKey> {
        guard let url,
              FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let decoder = JSONDecoder()
        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
        var keys = Set<MilestoneResultKey>()
        for line in lines {
            guard let data = String(line).data(using: .utf8),
                  let record = try? decoder.decode(MilestoneResultRecord.self, from: data),
                  record.passed else {
                continue
            }
            keys.insert(record.key)
        }
        return keys
    }

    private func writeMilestoneScreenshot(for milestone: LocalMilestone, c64: C64, to directory: URL?) throws -> URL? {
        guard let directory,
              let screenshotName = milestone.screenshotName,
              !screenshotName.isEmpty else {
            return nil
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = sanitizedScreenshotName(screenshotName) + ".ppm"
        let url = directory.appendingPathComponent(filename)
        try ppmData(
            framebuffer: c64.vic.framebuffer,
            width: VIC.screenWidth,
            height: VIC.screenHeight
        ).write(to: url, options: .atomic)
        return url
    }

    private func ppmData(framebuffer: [UInt32], width: Int, height: Int) -> Data {
        var data = Data("P6\n\(width) \(height)\n255\n".utf8)
        data.reserveCapacity(data.count + width * height * 3)
        for pixel in framebuffer.prefix(width * height) {
            data.append(UInt8(pixel & 0x000000FF))
            data.append(UInt8((pixel & 0x0000FF00) >> 8))
            data.append(UInt8((pixel & 0x00FF0000) >> 16))
        }
        return data
    }

    private func sanitizedScreenshotName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitizedScalars = name.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let sanitized = String(sanitizedScalars)
            .split(separator: "_")
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return sanitized.isEmpty ? "milestone" : sanitized
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
        return "\(verdict) \(name) category=\(category.rawValue) command=\(command) driveMode=\(c64.trueDriveEmulationMode.displayName) cycles=\(elapsedCycles) pc=$\(hex16(c64.cpu.pc)) drivePC=$\(hex16(drive.cpuPC)) track=\(drive.track) half=\(drive.halfTrack) iec=[\(drive.lastIECCommandSummary)] byteReady=\(drive.byteReadyCount) paReads=\(drive.via2PortAReadCount) reason=\(reason)"
    }

    var category: MilestoneResultCategory {
        MilestoneResultCategory.classify(passed: passed, reason: reason)
    }

    private func hex16(_ value: UInt16) -> String {
        String(format: "%04X", value)
    }

    func record(for milestone: LocalMilestone, c64: C64, screenshotURL: URL? = nil) -> MilestoneResultRecord {
        let drive = c64.drive1541.statusSnapshot
        return MilestoneResultRecord(
            file: milestone.url.lastPathComponent,
            commandSummary: milestone.commandSummary,
            machineProfile: milestone.machineProfile.rawValue,
            driveMode: milestone.driveMode.rawValue,
            passed: passed,
            elapsedCycles: elapsedCycles,
            reason: reason,
            category: category.rawValue,
            finalPC: hex16(c64.cpu.pc),
            finalDrivePC: hex16(drive.cpuPC),
            finalTrack: drive.track,
            finalHalfTrack: drive.halfTrack,
            finalByteReadyCount: drive.byteReadyCount,
            finalVia2PortAReadCount: drive.via2PortAReadCount,
            finalLastIECCommandSummary: drive.lastIECCommandSummary,
            screenRAMHash: CompatibilityHash.screenRAM(c64.memory.ram),
            colorRAMHash: CompatibilityHash.colorRAM(c64.memory.colorRAM),
            screenshotPath: screenshotURL?.path
        )
    }
}

private enum MilestoneResultCategory: String {
    case pass
    case cpu
    case drive
    case media
    case pc
    case ram
    case screen
    case emulator
    case timeout

    static func classify(passed: Bool, reason: String) -> MilestoneResultCategory {
        guard !passed else { return .pass }
        let lower = reason.lowercased()
        if lower.contains("cpu") || lower.contains("jam") || lower.contains("$ffff") {
            return .cpu
        }
        if lower.contains("pc $") {
            return .pc
        }
        if lower.contains("media") {
            return .media
        }
        if lower.contains("gcr")
            || lower.contains("byte-ready")
            || lower.contains("drive.")
            || lower.contains("iec") {
            return .drive
        }
        if lower.contains("screen hash")
            || lower.contains("color ram hash")
            || lower.contains("color ram $") {
            return .screen
        }
        if lower.contains("ram $") {
            return .ram
        }
        if lower.contains("timeout") {
            return .timeout
        }
        return .emulator
    }
}

private struct LocalMilestone {
    let url: URL
    let mediaType: CompatibilityMediaType
    let machineProfile: CompatibilityMachineProfile
    let driveMode: CompatibilityDriveMode
    let commands: [String]
    let maxCycles: Int
    let pcRanges: [ClosedRange<UInt16>]
    let minGCRReads: UInt64
    let minByteReady: UInt64
    let driveStatus: CompatibilityDriveStatus?
    let mediaStatus: CompatibilityMediaStatus?
    let ramSignatures: [CompatibilityRAMSignature]
    let colorRAMSignatures: [CompatibilityRAMSignature]
    let screenRAMHash: String?
    let colorRAMHash: String?
    let screenshotName: String?

    var commandSummary: String {
        commands.joined(separator: " | ")
    }

    var resultKey: MilestoneResultKey {
        MilestoneResultKey(
            file: url.lastPathComponent,
            commandSummary: commandSummary,
            machineProfile: machineProfile.rawValue,
            driveMode: driveMode.rawValue
        )
    }
}

private struct MilestoneResultRecord: Codable, Equatable {
    let file: String
    let commandSummary: String
    let machineProfile: String
    let driveMode: String
    let passed: Bool
    let elapsedCycles: UInt64
    let reason: String
    let category: String?
    let finalPC: String?
    let finalDrivePC: String?
    let finalTrack: Int?
    let finalHalfTrack: Int?
    let finalByteReadyCount: UInt64?
    let finalVia2PortAReadCount: UInt64?
    let finalLastIECCommandSummary: String?
    let screenRAMHash: String?
    let colorRAMHash: String?
    let screenshotPath: String?

    init(
        file: String,
        commandSummary: String,
        machineProfile: String,
        driveMode: String,
        passed: Bool,
        elapsedCycles: UInt64,
        reason: String,
        category: String? = nil,
        finalPC: String? = nil,
        finalDrivePC: String? = nil,
        finalTrack: Int? = nil,
        finalHalfTrack: Int? = nil,
        finalByteReadyCount: UInt64? = nil,
        finalVia2PortAReadCount: UInt64? = nil,
        finalLastIECCommandSummary: String? = nil,
        screenRAMHash: String? = nil,
        colorRAMHash: String? = nil,
        screenshotPath: String? = nil
    ) {
        self.file = file
        self.commandSummary = commandSummary
        self.machineProfile = machineProfile
        self.driveMode = driveMode
        self.passed = passed
        self.elapsedCycles = elapsedCycles
        self.reason = reason
        self.category = category
        self.finalPC = finalPC
        self.finalDrivePC = finalDrivePC
        self.finalTrack = finalTrack
        self.finalHalfTrack = finalHalfTrack
        self.finalByteReadyCount = finalByteReadyCount
        self.finalVia2PortAReadCount = finalVia2PortAReadCount
        self.finalLastIECCommandSummary = finalLastIECCommandSummary
        self.screenRAMHash = screenRAMHash
        self.colorRAMHash = colorRAMHash
        self.screenshotPath = screenshotPath
    }

    var key: MilestoneResultKey {
        MilestoneResultKey(
            file: file,
            commandSummary: commandSummary,
            machineProfile: machineProfile,
            driveMode: driveMode
        )
    }
}

private struct MilestoneFailureSummary: Codable, Equatable {
    let key: MilestoneResultKey
    let category: String
    let reason: String
    let elapsedCycles: UInt64
}

private struct MilestoneRunSummary: Codable, Equatable {
    var formatVersion: Int = 1
    var total: Int = 0
    var executed: Int = 0
    var passed: Int = 0
    var failed: Int = 0
    var skipped: Int = 0
    var totalElapsedCycles: UInt64 = 0
    var maxElapsedCycles: UInt64 = 0
    var slowestMilestone: MilestoneResultKey?
    var categories: [String: Int] = [:]
    var failedMilestones: [MilestoneResultKey] = []
    var failedMilestoneDetails: [MilestoneFailureSummary] = []
    var skippedMilestones: [MilestoneResultKey] = []

    mutating func record(_ record: MilestoneResultRecord) {
        total += 1
        executed += 1
        totalElapsedCycles += record.elapsedCycles
        if record.elapsedCycles >= maxElapsedCycles {
            maxElapsedCycles = record.elapsedCycles
            slowestMilestone = record.key
        }
        let category = record.category ?? "unknown"
        if record.passed {
            passed += 1
        } else {
            failed += 1
            failedMilestones.append(record.key)
            failedMilestoneDetails.append(MilestoneFailureSummary(
                key: record.key,
                category: category,
                reason: record.reason,
                elapsedCycles: record.elapsedCycles
            ))
        }
        categories[category, default: 0] += 1
    }

    mutating func recordSkipped(_ milestone: LocalMilestone) {
        total += 1
        skipped += 1
        skippedMilestones.append(milestone.resultKey)
    }

    var consoleSummary: String {
        let categorySummary = categories
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let categoryText = categorySummary.isEmpty ? "none" : categorySummary
        return "Summary total=\(total) executed=\(executed) passed=\(passed) failed=\(failed) skipped=\(skipped) cycles=\(totalElapsedCycles) maxCycles=\(maxElapsedCycles) categories=[\(categoryText)]"
    }
}

private struct MilestoneResultKey: Codable, Hashable {
    let file: String
    let commandSummary: String
    let machineProfile: String
    let driveMode: String
}
