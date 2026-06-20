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
        c64.typeText(gianaRunCommand(env: "SWIFT64_LOCAL_GIANA_RUN_COMMAND"))

        let maxCycles = Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_RUN_MAX_CYCLES"] ?? "") ?? 8_000_000
        let stopOnScreenChange = ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_CONTINUE_AFTER_SCREEN_CHANGE"] == nil
        var loaded = false
        var loadScreenHash: String?
        var screenChangedAfterLoad = false
        var ranPostLoadCycles = 0
        var enteredProgramCode = false
        var failureReason: String?
        var lowLoadSnapshot: String?
        var kernalPCRangeHits: [UInt16: Int] = [:]
        var lastKernalPC: UInt16?
        var sameKernalPCCycles = 0

        for cycle in 0..<maxCycles {
            c64.tickOneCycle()
            enteredProgramCode = enteredProgramCode || (0x0801...0xBFFF).contains(c64.cpu.pc)
            if (0xFFB0...0xFFE4).contains(c64.cpu.pc) {
                kernalPCRangeHits[c64.cpu.pc, default: 0] += 1
                if lastKernalPC == c64.cpu.pc {
                    sameKernalPCCycles += 1
                } else {
                    lastKernalPC = c64.cpu.pc
                    sameKernalPCCycles = 1
                }
            } else {
                lastKernalPC = nil
                sameKernalPCCycles = 0
            }
            if cycle & 0x03FF == 0, let reason = c64.emulationStatus.lastFailureReason {
                failureReason = reason
                break
            }

            let loadEndAddress = UInt16(c64.memory.ram[0xAE]) | (UInt16(c64.memory.ram[0xAF]) << 8)
            if lowLoadSnapshot == nil && hasGianaFirstStageLoaded(c64, loadEndAddress: loadEndAddress) {
                lowLoadSnapshot = firstStageLoadSnapshot(c64)
            }
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
                    if stopOnScreenChange {
                        break
                    }
                }
            }
        }

        let drive = c64.drive1541.statusSnapshot
        let pc = String(format: "%04X", c64.cpu.pc)
        let drivePC = String(format: "%04X", drive.cpuPC)
        let loadEndAddress = UInt16(c64.memory.ram[0xAE]) | (UInt16(c64.memory.ram[0xAF]) << 8)
        let loadEnd = String(format: "%04X", loadEndAddress)
        let pcBytes = cpuBytes(c64, at: c64.cpu.pc, count: 12)
        let summary = "Giana run smoke loaded=\(loaded) enteredProgramCode=\(enteredProgramCode) screenChangedAfterLoad=\(screenChangedAfterLoad) cycles=\(c64.cpu.totalCycles) pc=$\(pc) pcBytes=\(pcBytes) vic=\(vicSummary(c64)) code0A80=\(cpuBytes(c64, at: 0x0A80, count: 72)) kernalHits=\(kernalHitSummary(kernalPCRangeHits)) sameKernalPC=\(sameKernalPCCycles) \(bootFileSummary(c64)) trap=\(loadTrapSummary(c64)) firstLoad=[\(lowLoadSnapshot ?? "none")] fFile=\(diskFileSummary(c64, name: "F")) cc00=\(cpuBytes(c64, at: 0xCC00, count: 16)) nameByte=$\(String(format: "%02X", c64.memory.ram[0x02E2])) drivePC=$\(drivePC) loadEnd=$\(loadEnd) byteReady=\(drive.byteReadyCount - baseline.byteReadyCount) paReads=\(drive.via2PortAReadCount - baseline.via2PortAReadCount) reason=\(failureReason ?? c64.emulationStatus.lastFailureReason ?? "none")"
        print(summary)

        XCTAssertNil(failureReason, summary)
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

        c64.typeText(gianaRunCommand(env: "SWIFT64_LOCAL_GIANA_FAST_RUN_COMMAND"))
        let maxCycles = Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_FAST_RUN_MAX_CYCLES"] ?? "") ?? 4_000_000
        let stopOnScreenChange = ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_CONTINUE_AFTER_SCREEN_CHANGE"] == nil
        var loaded = false
        var loadScreenHash: String?
        var screenChangedAfterLoad = false
        var ranPostLoadCycles = 0
        var enteredProgramCode = false
        var lowLoadSnapshot: String?
        var kernalPCRangeHits: [UInt16: Int] = [:]
        var lastKernalPC: UInt16?
        var sameKernalPCCycles = 0

        for _ in 0..<maxCycles {
            c64.tickOneCycle()
            enteredProgramCode = enteredProgramCode || (0x0801...0xBFFF).contains(c64.cpu.pc)
            if (0xFFB0...0xFFE4).contains(c64.cpu.pc) {
                kernalPCRangeHits[c64.cpu.pc, default: 0] += 1
                if lastKernalPC == c64.cpu.pc {
                    sameKernalPCCycles += 1
                } else {
                    lastKernalPC = c64.cpu.pc
                    sameKernalPCCycles = 1
                }
            } else {
                lastKernalPC = nil
                sameKernalPCCycles = 0
            }

            let loadEndAddress = UInt16(c64.memory.ram[0xAE]) | (UInt16(c64.memory.ram[0xAF]) << 8)
            if lowLoadSnapshot == nil && hasGianaFirstStageLoaded(c64, loadEndAddress: loadEndAddress) {
                lowLoadSnapshot = firstStageLoadSnapshot(c64)
            }
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
                    if stopOnScreenChange {
                        break
                    }
                }
            }
        }

        let pc = String(format: "%04X", c64.cpu.pc)
        let loadEndAddress = UInt16(c64.memory.ram[0xAE]) | (UInt16(c64.memory.ram[0xAF]) << 8)
        let loadEnd = String(format: "%04X", loadEndAddress)
        let pcBytes = cpuBytes(c64, at: c64.cpu.pc, count: 12)
        let summary = "Giana fast run smoke loaded=\(loaded) enteredProgramCode=\(enteredProgramCode) screenChangedAfterLoad=\(screenChangedAfterLoad) cycles=\(c64.cpu.totalCycles) pc=$\(pc) pcBytes=\(pcBytes) vic=\(vicSummary(c64)) code0A80=\(cpuBytes(c64, at: 0x0A80, count: 72)) kernalHits=\(kernalHitSummary(kernalPCRangeHits)) sameKernalPC=\(sameKernalPCCycles) \(bootFileSummary(c64)) trap=\(loadTrapSummary(c64)) firstLoad=[\(lowLoadSnapshot ?? "none")] fFile=\(diskFileSummary(c64, name: "F")) cc00=\(cpuBytes(c64, at: 0xCC00, count: 16)) nameByte=$\(String(format: "%02X", c64.memory.ram[0x02E2])) loadEnd=$\(loadEnd) reason=\(c64.emulationStatus.lastFailureReason ?? "none")"
        print(summary)

        XCTAssertTrue(loaded || enteredProgramCode, summary)
    }

    private func cpuBytes(_ c64: C64, at address: UInt16, count: Int) -> String {
        (0..<count).map {
            String(format: "%02X", c64.memory.read(address &+ UInt16($0)))
        }.joined(separator: " ")
    }

    private func gianaRunCommand(env: String) -> String {
        ProcessInfo.processInfo.environment[env] ?? "LOAD\"*\",8,1\rRUN\r"
    }

    private func loadTrapSummary(_ c64: C64) -> String {
        let start = c64.kernalTraps.lastLoadTrapAddress.map { String(format: "%04X", $0) } ?? "none"
        let end = c64.kernalTraps.lastLoadTrapEndAddress.map { String(format: "%04X", $0) } ?? "none"
        return "count=\(c64.kernalTraps.handledLoadTrapCount),last=\(c64.kernalTraps.lastLoadTrapFilename ?? "none"),addr=$\(start)-$\(end)"
    }

    private func kernalHitSummary(_ hits: [UInt16: Int]) -> String {
        hits.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }
        .prefix(8)
        .map { "$\(String(format: "%04X", $0.key)):\($0.value)" }
        .joined(separator: ",")
    }

    private func vicSummary(_ c64: C64) -> String {
        "$D011=\(String(format: "%02X", c64.memory.read(0xD011))) $D012=\(String(format: "%02X", c64.memory.read(0xD012))) raster=\(c64.vic.rasterLine) cycle=\(c64.vic.rasterCycle)"
    }

    private func hasGianaFirstStageLoaded(_ c64: C64, loadEndAddress: UInt16) -> Bool {
        loadEndAddress == 0x0300
            && c64.memory.ram[0x02A2] == 0xA2
            && c64.memory.ram[0x02A4] == 0x8E
    }

    private func firstStageLoadSnapshot(_ c64: C64) -> String {
        let pc = String(format: "%04X", c64.cpu.pc)
        let stackReturn = UInt16(c64.memory.ram[0x0100 + Int(c64.cpu.sp &+ 1)])
            | (UInt16(c64.memory.ram[0x0100 + Int(c64.cpu.sp &+ 2)]) << 8)
        return "cycle=\(c64.cpu.totalCycles) pc=$\(pc) sp=$\(String(format: "%02X", c64.cpu.sp)) ret=$\(String(format: "%04X", stackReturn)) bytes02A2=\(cpuBytes(c64, at: 0x02A2, count: 8)) nameByte=$\(String(format: "%02X", c64.memory.ram[0x02E2]))"
    }

    private func bootFileSummary(_ c64: C64) -> String {
        guard let entry = c64.diskDrive.findFile("*") else { return "bootFile=missing" }
        let data = c64.diskDrive.readFileData(entry)
        let loadAddress = data.count >= 2
            ? UInt16(data[0]) | (UInt16(data[1]) << 8)
            : 0
        let preview = data.prefix(128).map { String(format: "%02X", $0) }.joined(separator: " ")
        return "bootFile=\"\(entry.filename)\" bootLoad=$\(String(format: "%04X", loadAddress)) bootBytes=\(preview)"
    }

    private func diskFileSummary(_ c64: C64, name: String) -> String {
        guard let entry = c64.diskDrive.findFile(name) else { return "missing" }
        let data = c64.diskDrive.readFileData(entry)
        let loadAddress = data.count >= 2
            ? UInt16(data[0]) | (UInt16(data[1]) << 8)
            : 0
        let preview = data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
        return "\"\(entry.filename)\"@$\(String(format: "%04X", loadAddress)):\(preview)"
    }

    private func prepareKernalLoadTrap(_ c64: C64, filename: String, device: UInt8, secondary: UInt8) {
        let nameAddress = 0x0200
        let bytes = Array(filename.utf8)
        for (index, byte) in bytes.enumerated() {
            c64.memory.ram[nameAddress + index] = byte
        }

        c64.memory.ram[Int(KernalTraps.fnLen)] = UInt8(bytes.count)
        c64.memory.ram[Int(KernalTraps.fnAddr)] = UInt8(nameAddress & 0xFF)
        c64.memory.ram[Int(KernalTraps.fnAddr + 1)] = UInt8(nameAddress >> 8)
        c64.memory.ram[Int(KernalTraps.logicalFile)] = 1
        c64.memory.ram[Int(KernalTraps.device)] = device
        c64.memory.ram[Int(KernalTraps.secondaryAddr)] = secondary
        c64.cpu.a = 0
        c64.cpu.pc = KernalTraps.loadRoutine
        c64.cpu.sp = 0xFB
        c64.memory.ram[0x01FC] = 0x34
        c64.memory.ram[0x01FD] = 0x12
    }

    func testLocalGreatGianaSistersDirectoryDecodeWhenEnabled() throws {
        try requireEnvironment(gianaFastRunEnv)

        let urls = try localMediaURLs(limitEnv: "SWIFT64_LOCAL_GIANA_RUN_LIMIT", extensions: Self.diskImageExtensions)
        let giana = try XCTUnwrap(urls.first {
            $0.lastPathComponent.lowercased().contains("great_giana_sisters")
            && $0.pathExtension.lowercased() == "g64"
        })

        let data = try Data(contentsOf: giana)
        let drive = DiskDrive()
        XCTAssertTrue(drive.mountG64(data), "Failed to decode G64 into fast media: \(giana.path)")

        let entries = drive.directory.map {
            "\($0.filename) type=\($0.typeName) first=\($0.firstTrack)/\($0.firstSector) blocks=\($0.fileSize)"
        }
        print("Giana decoded directory count=\(drive.directory.count) diskName=\"\(drive.diskName)\" diskID=\"\(drive.diskID)\" entries=\(entries)")
        print("Giana lookup star=\(String(describing: drive.findFile("*")?.filename)) dollar=\(drive.isDirectoryListingRequest("$"))")

        XCTAssertNotNil(drive.findFile("*"), "Decoded G64 should expose a wildcard-loadable first PRG")

        let c64 = C64(machineProfile: .palC64)
        XCTAssertTrue(c64.mountDisk(giana), "Failed to mount \(giana.path)")
        prepareKernalLoadTrap(c64, filename: "*", device: 8, secondary: 1)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.memory.ram[0x02A2], 0xA2)
        XCTAssertEqual(c64.memory.ram[0x02A3], 0x00)
        XCTAssertEqual(c64.memory.ram[0x02A4], 0x8E)
        XCTAssertEqual(c64.memory.ram[0x02E2], 0x46)
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
            driveStatus: CompatibilityDriveStatus(track: 17, hasDisk: true),
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

    func testNamedMilestoneCanMatchScreenText() {
        let c64 = C64()
        writeScreenText("READY.", into: c64, row: 4, column: 2)
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
            screenTextContains: ["ready."],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertTrue(result.passed, result.reason)
    }

    func testNamedMilestoneRequiresScreenText() {
        let c64 = C64()
        writeScreenText("READY.", into: c64, row: 4, column: 2)
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
            screenTextContains: ["press fire"],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .screen)
        XCTAssertTrue(result.reason.contains("screen text missing press fire"))
    }

    func testNamedMilestoneCanMatchSIDRegisters() {
        let c64 = C64()
        c64.sid.writeRegister(0x04, value: 0x21)
        c64.sid.writeRegister(0x18, value: 0x8F)
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
            sidRegisters: [
                CompatibilitySIDRegisterExpectation(register: 0x04, value: 0x21),
                CompatibilitySIDRegisterExpectation(register: 0xD418, value: 0x0F, mask: 0x0F)
            ],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertTrue(result.passed, result.reason)
    }

    func testNamedMilestoneRequiresSIDRegisters() {
        let c64 = C64()
        c64.sid.writeRegister(0x18, value: 0x0F)
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
            sidRegisters: [CompatibilitySIDRegisterExpectation(register: 0xD418, value: 0x10, mask: 0x1F)],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .audio)
        XCTAssertTrue(result.reason.contains("SID $D418"))
    }

    func testNamedMilestoneCanMatchVICRegisters() {
        let c64 = C64()
        c64.vic.writeRegister(0x11, value: 0x3B)
        c64.vic.writeRegister(0x16, value: 0x18)
        c64.vic.writeRegister(0x20, value: 0x06)
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
            vicRegisters: [
                CompatibilityVICRegisterExpectation(register: 0xD011, value: 0x3B),
                CompatibilityVICRegisterExpectation(register: 0xD016, value: 0x18, mask: 0x1F),
                CompatibilityVICRegisterExpectation(register: 0xD020, value: 0x06, mask: 0x0F)
            ],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertTrue(result.passed, result.reason)
    }

    func testNamedMilestoneRequiresVICRegisters() {
        let c64 = C64()
        c64.vic.writeRegister(0x20, value: 0x06)
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
            vicRegisters: [CompatibilityVICRegisterExpectation(register: 0xD020, value: 0x02, mask: 0x0F)],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .video)
        XCTAssertTrue(result.reason.contains("VIC $D020"))
    }

    func testNamedMilestoneCanMatchCIARegisters() {
        let c64 = C64()
        c64.cia1.writeRegister(0x04, value: 0x34)
        c64.cia1.writeRegister(0x05, value: 0x12)
        c64.cia1.writeRegister(0x0E, value: 0x41)
        c64.cia2.writeRegister(0x02, value: 0x3F)
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
            cia1Registers: [
                CompatibilityCIARegisterExpectation(register: 0xDC04, value: 0x33),
                CompatibilityCIARegisterExpectation(register: 0xDC05, value: 0x12),
                CompatibilityCIARegisterExpectation(register: 0xDC0E, value: 0x01, mask: 0x01)
            ],
            cia2Registers: [CompatibilityCIARegisterExpectation(register: 0xDD02, value: 0x3F)],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertTrue(result.passed, result.reason)
    }

    func testNamedMilestoneRequiresCIARegisters() {
        let c64 = C64()
        c64.cia1.writeRegister(0x0E, value: 0x41)
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
            cia1Registers: [CompatibilityCIARegisterExpectation(register: 0xDC0E, value: 0x00, mask: 0x01)],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .cia)
        XCTAssertTrue(result.reason.contains("CIA1 $DC0E"))
    }

    func testNamedMilestoneCanMatchCPURegisters() {
        let c64 = C64()
        c64.cpu.pc = 0xC000
        c64.cpu.a = 0x01
        c64.cpu.x = 0x02
        c64.cpu.y = 0x03
        c64.cpu.sp = 0xFA
        c64.cpu.p = 0xB4

        let mismatches = cpuRegisterMismatches(
            CompatibilityCPURegisters(
                pc: 0xC000,
                a: 0x01,
                x: 0x02,
                y: 0x03,
                sp: 0xFA,
                p: 0x24,
                pMask: 0x6F
            ),
            c64: c64
        )

        XCTAssertEqual(mismatches, [])
    }

    func testNamedMilestoneRequiresCPURegisters() {
        let c64 = C64()
        c64.cpu.pc = 0x0801
        c64.cpu.a = 0x00
        c64.cpu.x = 0x02
        c64.cpu.y = 0x03
        c64.cpu.sp = 0xFA
        c64.cpu.p = 0x24
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/demo.prg"),
            mediaType: .prg,
            machineProfile: .palC64,
            driveMode: .fastLoad,
            commands: [],
            maxCycles: 0,
            pcRanges: [],
            minGCRReads: 0,
            minByteReady: 0,
            driveStatus: nil,
            mediaStatus: nil,
            ramSignatures: [],
            colorRAMSignatures: [],
            cpuRegisters: CompatibilityCPURegisters(pc: 0xC000, a: 0x01, x: 0x02, y: 0x03, sp: 0xFA, p: 0x24),
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .cpu)
        XCTAssertTrue(result.reason.contains("CPU.PC $0801 != $C000"))
        XCTAssertTrue(result.reason.contains("CPU.A $00 != $01"))
    }

    func testMilestoneActionSchedulerAppliesJoystickEventsAtWaitedCycles() {
        let c64 = C64()
        let scheduler = MilestoneActionScheduler(actions: [
            .waitCycles(3),
            .joystickDown(.fire),
            .waitCycles(2),
            .joystickUp(.fire)
        ])

        scheduler.applyDueActions(to: c64, elapsedCycles: 0)
        XCTAssertEqual(c64.joystick.port1 & 0x10, 0x10)
        XCTAssertEqual(c64.joystick.port2 & 0x10, 0x10)

        scheduler.applyDueActions(to: c64, elapsedCycles: 3)
        XCTAssertEqual(c64.joystick.port1 & 0x10, 0)
        XCTAssertEqual(c64.joystick.port2 & 0x10, 0)

        scheduler.applyDueActions(to: c64, elapsedCycles: 4)
        XCTAssertEqual(c64.joystick.port1 & 0x10, 0)
        XCTAssertEqual(c64.joystick.port2 & 0x10, 0)

        scheduler.applyDueActions(to: c64, elapsedCycles: 5)
        XCTAssertEqual(c64.joystick.port1 & 0x10, 0x10)
        XCTAssertEqual(c64.joystick.port2 & 0x10, 0x10)
    }

    func testMilestoneActionSchedulerAppliesKeyboardEventsAtWaitedCycles() {
        let c64 = C64()
        let scheduler = MilestoneActionScheduler(actions: [
            .waitCycles(2),
            .keyDown(.space),
            .waitCycles(2),
            .keyUp(.space),
            .keyDown(.cursorLeft),
            .keyUp(.cursorLeft)
        ])

        scheduler.applyDueActions(to: c64, elapsedCycles: 0)
        XCTAssertEqual(c64.cia1.keyboardMatrix[7] & 0x10, 0x10)

        scheduler.applyDueActions(to: c64, elapsedCycles: 2)
        XCTAssertEqual(c64.cia1.keyboardMatrix[7] & 0x10, 0)

        scheduler.applyDueActions(to: c64, elapsedCycles: 4)
        XCTAssertEqual(c64.cia1.keyboardMatrix[7] & 0x10, 0x10)

        scheduler.applyDueActions(to: c64, elapsedCycles: 5)
        XCTAssertEqual(c64.cia1.keyboardMatrix[0] & 0x04, 0x04)
        XCTAssertEqual(c64.cia1.keyboardMatrix[1] & 0x80, 0x80)
    }

    func testMilestoneActionSchedulerAppliesRestoreKeyEvents() {
        let c64 = C64()
        let scheduler = MilestoneActionScheduler(actions: [
            .keyDown(.restore),
            .waitCycles(1),
            .keyUp(.restore)
        ])

        scheduler.applyDueActions(to: c64, elapsedCycles: 0)
        XCTAssertTrue(c64.restoreKeyDown)

        scheduler.applyDueActions(to: c64, elapsedCycles: 1)
        XCTAssertFalse(c64.restoreKeyDown)
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
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "VIC $D020 06 != 02 mask 0F").category, .video)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "SID $D418 0F != 10 mask FF").category, .audio)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "CIA1 $DC0E 01 != 00 mask 01").category, .cia)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "CPU.A $00 != $01").category, .cpu)
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
        let actionScheduler = MilestoneActionScheduler(actions: milestone.scheduledActions)

        for elapsedCycles in 0..<milestone.maxCycles {
            actionScheduler.applyDueActions(to: c64, elapsedCycles: elapsedCycles)
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
            let cpuMatches = cpuRegisterMismatches(milestone.cpuRegisters, c64: c64).isEmpty
            let sidMatches = milestone.sidRegisters.allSatisfy { expectation in
                let actual = c64.sid.debugRegisterValue(UInt16(truncatingIfNeeded: expectation.register))
                return (actual & expectation.mask) == (expectation.value & expectation.mask)
            }
            let vicMatches = milestone.vicRegisters.allSatisfy { expectation in
                let actual = c64.vic.debugRegisterValue(UInt16(truncatingIfNeeded: expectation.register))
                return (actual & expectation.mask) == (expectation.value & expectation.mask)
            }
            let cia1Matches = milestone.cia1Registers.allSatisfy { expectation in
                let actual = c64.cia1.debugRegisterValue(UInt16(truncatingIfNeeded: expectation.register))
                return (actual & expectation.mask) == (expectation.value & expectation.mask)
            }
            let cia2Matches = milestone.cia2Registers.allSatisfy { expectation in
                let actual = c64.cia2.debugRegisterValue(UInt16(truncatingIfNeeded: expectation.register))
                return (actual & expectation.mask) == (expectation.value & expectation.mask)
            }
            let screenMatches = milestone.screenRAMHash.map {
                CompatibilityHash.screenRAM(c64.memory.ram).caseInsensitiveCompare($0) == .orderedSame
            } ?? true
            let colorRAMHashMatches = milestone.colorRAMHash.map {
                CompatibilityHash.colorRAM(c64.memory.colorRAM).caseInsensitiveCompare($0) == .orderedSame
            } ?? true
            let screenTextMatches = milestone.screenTextContains.allSatisfy {
                screenText(c64.memory.ram).localizedCaseInsensitiveContains($0)
            }

            if pcReached
                && driveProgress
                && driveExpectationMatches
                && mediaExpectationMatches
                && ramMatches
                && colorRAMMatches
                && cpuMatches
                && sidMatches
                && vicMatches
                && cia1Matches
                && cia2Matches
                && screenTextMatches
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
                cpuRegisters: nil,
                sidRegisters: [],
                vicRegisters: [],
                cia1Registers: [],
                cia2Registers: [],
                screenTextContains: [],
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
                actions: entry.actions,
                maxCycles: entry.maxCycles ?? 24_000_000,
                pcRanges: entry.expectedPCRanges,
                minGCRReads: nonNegativeUInt64(entry.driveStatus?.minGCRReads ?? entry.minGCRReads ?? defaultMinGCRReads(for: driveMode)),
                minByteReady: nonNegativeUInt64(entry.driveStatus?.minByteReady ?? entry.minByteReady ?? defaultMinByteReady(for: driveMode)),
                driveStatus: entry.driveStatus,
                mediaStatus: entry.mediaStatus,
                ramSignatures: entry.ramSignatures,
                colorRAMSignatures: entry.colorRAMSignatures,
                cpuRegisters: entry.cpuRegisters,
                sidRegisters: entry.sidRegisters,
                vicRegisters: entry.vicRegisters,
                cia1Registers: entry.cia1Registers,
                cia2Registers: entry.cia2Registers,
                screenTextContains: entry.screenTextContains,
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
        unmet.append(contentsOf: cpuRegisterMismatches(milestone.cpuRegisters, c64: c64))
        unmet.append(contentsOf: sidRegisterMismatches(milestone.sidRegisters, sid: c64.sid))
        unmet.append(contentsOf: vicRegisterMismatches(milestone.vicRegisters, vic: c64.vic))
        unmet.append(contentsOf: ciaRegisterMismatches(milestone.cia1Registers, cia: c64.cia1, label: "CIA1"))
        unmet.append(contentsOf: ciaRegisterMismatches(milestone.cia2Registers, cia: c64.cia2, label: "CIA2"))
        if let expectedScreenHash = milestone.screenRAMHash {
            let actualScreenHash = CompatibilityHash.screenRAM(c64.memory.ram)
            if actualScreenHash.caseInsensitiveCompare(expectedScreenHash) != .orderedSame {
                unmet.append("screen hash \(actualScreenHash) != \(expectedScreenHash)")
            }
        }
        let actualScreenText = screenText(c64.memory.ram)
        for expectedText in milestone.screenTextContains where !actualScreenText.localizedCaseInsensitiveContains(expectedText) {
            unmet.append("screen text missing \(expectedText)")
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
        if let mediaChanged = expectation.mediaChanged, snapshot.mediaChanged != mediaChanged {
            mismatches.append("drive.mediaChanged \(snapshot.mediaChanged) != \(mediaChanged)")
        }
        if let minMediaChangeCount = expectation.minMediaChangeCount,
           snapshot.mediaChangeCount < nonNegativeUInt64(minMediaChangeCount) {
            mismatches.append("drive.mediaChangeCount \(snapshot.mediaChangeCount) < \(minMediaChangeCount)")
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

    private func sidRegisterMismatches(
        _ expectations: [CompatibilitySIDRegisterExpectation],
        sid: SID
    ) -> [String] {
        expectations.compactMap { expectation in
            let register = UInt16(truncatingIfNeeded: expectation.register)
            let actual = sid.debugRegisterValue(register)
            let maskedActual = actual & expectation.mask
            let maskedExpected = expectation.value & expectation.mask
            guard maskedActual != maskedExpected else { return nil }
            return "SID $\(hex16(register)) \(hex8(maskedActual)) != \(hex8(maskedExpected)) mask \(hex8(expectation.mask))"
        }
    }

    private func vicRegisterMismatches(
        _ expectations: [CompatibilityVICRegisterExpectation],
        vic: VIC
    ) -> [String] {
        expectations.compactMap { expectation in
            let register = UInt16(truncatingIfNeeded: expectation.register)
            let actual = vic.debugRegisterValue(register)
            let maskedActual = actual & expectation.mask
            let maskedExpected = expectation.value & expectation.mask
            guard maskedActual != maskedExpected else { return nil }
            return "VIC $\(hex16(register)) \(hex8(maskedActual)) != \(hex8(maskedExpected)) mask \(hex8(expectation.mask))"
        }
    }

    private func ciaRegisterMismatches(
        _ expectations: [CompatibilityCIARegisterExpectation],
        cia: CIA,
        label: String
    ) -> [String] {
        expectations.compactMap { expectation in
            let register = UInt16(truncatingIfNeeded: expectation.register)
            let actual = cia.debugRegisterValue(register)
            let maskedActual = actual & expectation.mask
            let maskedExpected = expectation.value & expectation.mask
            guard maskedActual != maskedExpected else { return nil }
            return "\(label) $\(hex16(register)) \(hex8(maskedActual)) != \(hex8(maskedExpected)) mask \(hex8(expectation.mask))"
        }
    }

    private func cpuRegisterMismatches(
        _ expectation: CompatibilityCPURegisters?,
        c64: C64
    ) -> [String] {
        guard let expectation else { return [] }
        var mismatches: [String] = []

        if let expectedPC = expectation.pc, c64.cpu.pc != UInt16(expectedPC) {
            mismatches.append("CPU.PC $\(hex16(c64.cpu.pc)) != $\(hex16(UInt16(expectedPC)))")
        }
        if let expectedA = expectation.a, c64.cpu.a != expectedA {
            mismatches.append("CPU.A $\(hex8(c64.cpu.a)) != $\(hex8(expectedA))")
        }
        if let expectedX = expectation.x, c64.cpu.x != expectedX {
            mismatches.append("CPU.X $\(hex8(c64.cpu.x)) != $\(hex8(expectedX))")
        }
        if let expectedY = expectation.y, c64.cpu.y != expectedY {
            mismatches.append("CPU.Y $\(hex8(c64.cpu.y)) != $\(hex8(expectedY))")
        }
        if let expectedSP = expectation.sp, c64.cpu.sp != expectedSP {
            mismatches.append("CPU.SP $\(hex8(c64.cpu.sp)) != $\(hex8(expectedSP))")
        }
        if let expectedP = expectation.p {
            let maskedActual = c64.cpu.p & expectation.pMask
            let maskedExpected = expectedP & expectation.pMask
            if maskedActual != maskedExpected {
                mismatches.append("CPU.P $\(hex8(maskedActual)) != $\(hex8(maskedExpected)) mask \(hex8(expectation.pMask))")
            }
        }

        return mismatches
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

    private func writeScreenText(_ text: String, into c64: C64, row: Int, column: Int) {
        let start = 0x0400 + row * 40 + column
        for (offset, byte) in text.utf8.enumerated() where start + offset < 0x0800 {
            c64.memory.ram[start + offset] = asciiToScreenCode(byte)
        }
    }

    private func screenText(_ ram: [UInt8]) -> String {
        guard ram.count >= 0x0800 else { return "" }
        return (0..<25)
            .map { row in
                let start = 0x0400 + row * 40
                let end = start + 40
                return ram[start..<end].map(screenCodeCharacter).joined()
            }
            .joined(separator: "\n")
    }

    private func screenCodeCharacter(_ byte: UInt8) -> String {
        switch byte {
        case 0x00: return "@"
        case 0x01...0x1A:
            return String(UnicodeScalar(UInt8(ascii: "A") + byte - 1))
        case 0x1B: return "["
        case 0x1C: return "\\"
        case 0x1D: return "]"
        case 0x1E: return "^"
        case 0x20: return " "
        case 0x21...0x3F:
            return String(UnicodeScalar(byte))
        case 0x40: return "-"
        default:
            return " "
        }
    }

    private func asciiToScreenCode(_ byte: UInt8) -> UInt8 {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"):
            return byte - UInt8(ascii: "A") + 1
        case UInt8(ascii: "a")...UInt8(ascii: "z"):
            return byte - UInt8(ascii: "a") + 1
        default:
            return byte
        }
    }

    private func hex16(_ value: UInt16) -> String {
        String(format: "%04X", value)
    }

    private func hex8(_ value: UInt8) -> String {
        String(format: "%02X", value)
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
    case video
    case audio
    case cia
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
            || lower.contains("screen text")
            || lower.contains("color ram hash")
            || lower.contains("color ram $") {
            return .screen
        }
        if lower.contains("vic $") {
            return .video
        }
        if lower.contains("sid $") {
            return .audio
        }
        if lower.contains("cia1 $") || lower.contains("cia2 $") {
            return .cia
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

private final class MilestoneActionScheduler {
    private let events: [(cycle: Int, action: CompatibilityAction)]
    private var nextEventIndex = 0

    init(actions: [CompatibilityAction]) {
        var scheduledEvents: [(cycle: Int, action: CompatibilityAction)] = []
        var cycle = 0
        for action in actions {
            switch action {
            case let .waitCycles(waitCycles):
                cycle += max(0, waitCycles)
            default:
                scheduledEvents.append((cycle, action))
            }
        }
        self.events = scheduledEvents
    }

    func applyDueActions(to c64: C64, elapsedCycles: Int) {
        while nextEventIndex < events.count && events[nextEventIndex].cycle <= elapsedCycles {
            apply(events[nextEventIndex].action, to: c64)
            nextEventIndex += 1
        }
    }

    private func apply(_ action: CompatibilityAction, to c64: C64) {
        switch action {
        case let .typeText(text):
            c64.typeText(text.hasSuffix("\r") ? text : text + "\r")
        case let .joystickDown(control):
            _ = c64.joystick.handleKeyDown(keyCode: control.keyCode)
        case let .joystickUp(control):
            _ = c64.joystick.handleKeyUp(keyCode: control.keyCode)
        case let .keyDown(key):
            key.press(on: c64)
        case let .keyUp(key):
            key.release(on: c64)
        case .waitCycles:
            break
        }
    }
}

private extension CompatibilityJoystickControl {
    var keyCode: UInt16 {
        switch self {
        case .up: return 91
        case .down: return 84
        case .left: return 86
        case .right: return 88
        case .fire: return 82
        }
    }
}

private extension CompatibilityAction {
    var summary: String {
        switch self {
        case let .typeText(text):
            return text
        case let .waitCycles(cycles):
            return "wait \(cycles) cycles"
        case let .joystickDown(control):
            return "joystick \(control.rawValue) down"
        case let .joystickUp(control):
            return "joystick \(control.rawValue) up"
        case let .keyDown(key):
            return "key \(key.summaryName) down"
        case let .keyUp(key):
            return "key \(key.summaryName) up"
        }
    }
}

private extension CompatibilityKey {
    var summaryName: String {
        switch self {
        case .space: return "space"
        case .returnKey: return "return"
        case .runStop: return "runStop"
        case .restore: return "restore"
        case .home: return "home"
        case .delete: return "delete"
        case .cursorUp: return "cursorUp"
        case .cursorDown: return "cursorDown"
        case .cursorLeft: return "cursorLeft"
        case .cursorRight: return "cursorRight"
        case .f1: return "f1"
        case .f3: return "f3"
        case .f5: return "f5"
        case .f7: return "f7"
        case .leftShift: return "leftShift"
        case .rightShift: return "rightShift"
        case .control: return "control"
        case .commodore: return "commodore"
        }
    }

    var matrixMapping: (row: Int, col: Int, shifted: Bool)? {
        switch self {
        case .space: return (7, 4, false)
        case .returnKey: return (0, 1, false)
        case .runStop: return (7, 7, false)
        case .home: return (6, 3, false)
        case .delete: return (0, 0, false)
        case .cursorUp: return (0, 7, true)
        case .cursorDown: return (0, 7, false)
        case .cursorLeft: return (0, 2, true)
        case .cursorRight: return (0, 2, false)
        case .f1: return (0, 4, false)
        case .f3: return (0, 5, false)
        case .f5: return (0, 6, false)
        case .f7: return (0, 3, false)
        case .leftShift: return (1, 7, false)
        case .rightShift: return (6, 4, false)
        case .control: return (7, 2, false)
        case .commodore: return (7, 5, false)
        case .restore: return nil
        }
    }

    func press(on c64: C64) {
        if self == .restore {
            _ = c64.pressRestoreKey()
            return
        }
        guard let mapping = matrixMapping else { return }
        if mapping.shifted {
            c64.keyboard.pressKey(row: 1, col: 7)
        }
        c64.keyboard.pressKey(row: mapping.row, col: mapping.col)
    }

    func release(on c64: C64) {
        if self == .restore {
            c64.releaseRestoreKey()
            return
        }
        guard let mapping = matrixMapping else { return }
        c64.keyboard.releaseKey(row: mapping.row, col: mapping.col)
        if mapping.shifted {
            c64.keyboard.releaseKey(row: 1, col: 7)
        }
    }
}

private struct LocalMilestone {
    let url: URL
    let mediaType: CompatibilityMediaType
    let machineProfile: CompatibilityMachineProfile
    let driveMode: CompatibilityDriveMode
    let commands: [String]
    var actions: [CompatibilityAction] = []
    let maxCycles: Int
    let pcRanges: [ClosedRange<UInt16>]
    let minGCRReads: UInt64
    let minByteReady: UInt64
    let driveStatus: CompatibilityDriveStatus?
    let mediaStatus: CompatibilityMediaStatus?
    let ramSignatures: [CompatibilityRAMSignature]
    let colorRAMSignatures: [CompatibilityRAMSignature]
    var cpuRegisters: CompatibilityCPURegisters? = nil
    var sidRegisters: [CompatibilitySIDRegisterExpectation] = []
    var vicRegisters: [CompatibilityVICRegisterExpectation] = []
    var cia1Registers: [CompatibilityCIARegisterExpectation] = []
    var cia2Registers: [CompatibilityCIARegisterExpectation] = []
    var screenTextContains: [String] = []
    let screenRAMHash: String?
    let colorRAMHash: String?
    let screenshotName: String?

    var commandSummary: String {
        if !commands.isEmpty {
            return commands.joined(separator: " | ")
        }
        return actions.map(\.summary).joined(separator: " | ")
    }

    var scheduledActions: [CompatibilityAction] {
        actions.isEmpty ? commands.map { .typeText($0) } : actions
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
