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
    private let milestoneResumeStrictManifestEnv = "SWIFT64_LOCAL_MILESTONE_RESUME_STRICT_MANIFEST"
    private let milestoneScreenshotDirEnv = "SWIFT64_LOCAL_MILESTONE_SCREENSHOT_DIR"
    private let milestoneScreenshotFailuresEnv = "SWIFT64_LOCAL_MILESTONE_SCREENSHOT_FAILURES"
    private let milestoneSummaryEnv = "SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON"
    private let milestoneFailOnUnclassifiedEnv = "SWIFT64_LOCAL_MILESTONE_FAIL_ON_UNCLASSIFIED"
    private let milestoneFailOnUnexpectedEnv = "SWIFT64_LOCAL_MILESTONE_FAIL_ON_UNEXPECTED"
    private let milestoneRequireAllMediaEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_ALL_MEDIA"
    private let milestoneRunIDEnv = "SWIFT64_LOCAL_MILESTONE_RUN_ID"

    func testMediaStatusMismatchReportsProtectedMediaCounters() {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [0xAA, 0x55],
            speedZone: 2,
            speedZoneMap: [0, 1],
            weakBitRanges: [
                DiskImage.Track.WeakBitRange(startBit: 0, endBit: 3),
                DiskImage.Track.WeakBitRange(startBit: 8, endBit: 15),
            ],
            isNativeLowLevel: true
        )
        let capabilities = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 2).capabilities

        XCTAssertTrue(mediaStatusMismatches(
            CompatibilityMediaStatus(
                weakBitRangeCount: 2,
                weakBitTotalBitCount: 12,
                variableSpeedZoneByteCount: 2
            ),
            capabilities: capabilities
        ).isEmpty)

        let mismatches = mediaStatusMismatches(
            CompatibilityMediaStatus(
                weakBitRangeCount: 1,
                weakBitTotalBitCount: 16,
                variableSpeedZoneByteCount: 4
            ),
            capabilities: capabilities
        )

        XCTAssertTrue(mismatches.contains("media.weakBitRangeCount 2 != 1"))
        XCTAssertTrue(mismatches.contains("media.weakBitTotalBitCount 12 != 16"))
        XCTAssertTrue(mismatches.contains("media.variableSpeedZoneByteCount 2 != 4"))
    }

    func testTapeStatusMismatchReportsSignalAndExportFields() {
        let c64 = C64()

        XCTAssertTrue(tapeStatusMismatches(
            CompatibilityTapeStatus(
                decodeStatus: CompatibilityTapeDecodeStatusKind.none,
                rawPlaybackActive: false,
                readSignalHigh: true,
                cassetteSenseLineHigh: true,
                cassetteMotorEnabled: false,
                hasCapturedWritePulses: false,
                canExportCapturedTAP: false,
                hasUnsavedChanges: false,
                canExportSavedT64: false
            ),
            status: c64.emulationStatus
        ).isEmpty)

        let mismatches = tapeStatusMismatches(
            CompatibilityTapeStatus(
                mountedTapeNameContains: "loader.tap",
                decodeStatus: .decodedPrograms,
                pulseCount: 12,
                programCount: 1,
                blockCount: 2,
                decodeFailureReason: .malformedStandardBlocks,
                rawPlaybackActive: true,
                readSignalHigh: false,
                cassetteSenseLineHigh: false,
                cassetteMotorEnabled: true,
                hasCapturedWritePulses: true,
                canExportCapturedTAP: true,
                hasUnsavedChanges: true,
                canExportSavedT64: true
            ),
            status: c64.emulationStatus
        )

        XCTAssertTrue(mismatches.contains("tape.mountedTapeName missing loader.tap"))
        XCTAssertTrue(mismatches.contains("tape.decodeStatus none != decodedPrograms"))
        XCTAssertTrue(mismatches.contains("tape.pulseCount nil != 12"))
        XCTAssertTrue(mismatches.contains("tape.programCount nil != 1"))
        XCTAssertTrue(mismatches.contains("tape.blockCount nil != 2"))
        XCTAssertTrue(mismatches.contains("tape.decodeFailureReason nil != malformedStandardBlocks"))
        XCTAssertTrue(mismatches.contains("tape.rawPlaybackActive false != true"))
        XCTAssertTrue(mismatches.contains("tape.readSignalHigh true != false"))
        XCTAssertTrue(mismatches.contains("tape.cassetteSenseLineHigh true != false"))
        XCTAssertTrue(mismatches.contains("tape.cassetteMotorEnabled false != true"))
        XCTAssertTrue(mismatches.contains("tape.hasCapturedWritePulses false != true"))
        XCTAssertTrue(mismatches.contains("tape.canExportCapturedTAP false != true"))
        XCTAssertTrue(mismatches.contains("tape.hasUnsavedChanges false != true"))
        XCTAssertTrue(mismatches.contains("tape.canExportSavedT64 false != true"))
    }

    func testTapeStatusCanMatchMountedTAPDecodeStatus() {
        let c64 = C64()

        XCTAssertTrue(c64.mountTape(makeTinyTAP(pulses: [0x01, 0x02]), fileName: "loader.tap"))

        XCTAssertTrue(tapeStatusMismatches(
            CompatibilityTapeStatus(
                mountedTapeNameContains: "loader.tap",
                decodeStatus: .rawPulsesOnly,
                pulseCount: 2,
                rawPlaybackActive: true,
                readSignalHigh: true,
                cassetteSenseLineHigh: false,
                cassetteMotorEnabled: false,
                hasCapturedWritePulses: false,
                canExportCapturedTAP: false,
                hasUnsavedChanges: false,
                canExportSavedT64: false
            ),
            status: c64.emulationStatus
        ).isEmpty)
    }

    func testManifestWeakBitRangesApplyAfterDiskMount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let diskURL = directory.appendingPathComponent("weak-annotation.d64")
        try makeResultLogD64WithErrorTable().write(to: diskURL)

        var milestone = LocalMilestone(
            url: diskURL,
            mediaType: .d64,
            machineProfile: .palC64,
            driveMode: .compat1541,
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
            colorRAMHash: nil,
            screenshotName: nil
        )
        milestone.weakBitRanges = [
            CompatibilityWeakBitRange(halfTrack: 34, startBit: 0, endBit: 15)
        ]
        milestone.speedZoneRanges = [
            CompatibilitySpeedZoneRange(halfTrack: 34, startByte: 0, endByte: 3, zone: 3)
        ]

        let c64 = C64()
        XCTAssertTrue(mountPrePowerOnMedia(for: milestone, into: c64))

        let capabilities = try XCTUnwrap(c64.emulationStatus.mediaCapabilities)
        XCTAssertEqual(capabilities.weakBitRangeCount, 1)
        XCTAssertEqual(capabilities.weakBitTotalBitCount, 16)
        let speedMap = try XCTUnwrap(c64.drive1541.disk.trackInfo(halfTrack: 34)?.speedZoneMap)
        XCTAssertEqual(capabilities.variableSpeedZoneByteCount, speedMap.count)
        XCTAssertEqual(c64.drive1541.disk.trackInfo(halfTrack: 34)?.weakBitRanges, [
            DiskImage.Track.WeakBitRange(startBit: 0, endBit: 15)
        ])
        XCTAssertEqual(Array(speedMap.prefix(4)), [3, 3, 3, 3])

        milestone.weakBitRanges = [
            CompatibilityWeakBitRange(halfTrack: 35, startBit: 0, endBit: 15)
        ]
        XCTAssertFalse(mountPrePowerOnMedia(for: milestone, into: C64()))
        milestone.weakBitRanges = []
        milestone.speedZoneRanges = [
            CompatibilitySpeedZoneRange(halfTrack: 35, startByte: 0, endByte: 3, zone: 3)
        ]
        XCTAssertFalse(mountPrePowerOnMedia(for: milestone, into: C64()))
    }

    private func makeTinyTAP(pulses: [UInt8]) -> Data {
        var tap = [UInt8](repeating: 0, count: 20)
        for (offset, byte) in "C64-TAPE-RAW".utf8.enumerated() {
            tap[offset] = byte
        }
        tap[0x0C] = 0
        tap[0x10] = UInt8(pulses.count & 0xFF)
        tap[0x11] = UInt8((pulses.count >> 8) & 0xFF)
        tap[0x12] = UInt8((pulses.count >> 16) & 0xFF)
        tap[0x13] = UInt8((pulses.count >> 24) & 0xFF)
        tap.append(contentsOf: pulses)
        return Data(tap)
    }

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

        let milestoneLoad = try localMilestoneLoadResult()
        let milestones = milestoneLoad.milestones
        guard !milestones.isEmpty else {
            throw XCTSkip("No local milestone disks found under C64/DISKS")
        }

        let resultLogURL = milestoneResultLogURL()
        let manifestHash = activeMilestoneManifestHash()
        let passedMilestones = shouldResumeMilestoneResults
            ? try passedMilestoneKeys(
                from: resultLogURL,
                matchingManifestHash: shouldResumeOnlyMatchingManifest ? manifestHash : nil
            )
            : []
        let screenshotDirectoryURL = milestoneScreenshotDirectoryURL()
        let screenshotFailuresEnabled = shouldWriteFailedMilestoneScreenshots
        let summaryURL = milestoneSummaryURL()
        let runID = milestoneRunID()
        var summaries: [String] = []
        var runSummary = MilestoneRunSummary()
        runSummary.configureRun(
            runID: runID,
            manifestURL: activeMilestoneManifestURL(),
            manifestHash: manifestHash,
            resultLogURL: resultLogURL,
            screenshotDirectoryURL: screenshotDirectoryURL,
            resumeEnabled: shouldResumeMilestoneResults,
            strictManifestResumeEnabled: shouldResumeOnlyMatchingManifest,
            screenshotFailuresEnabled: screenshotFailuresEnabled,
            milestoneLimit: localMilestoneLimit,
            manifestMilestoneCount: milestoneLoad.manifestMilestoneCount,
            selectedMilestoneCount: milestones.count,
            missingMediaFiles: milestoneLoad.missingMediaFiles,
            requireAllManifestMedia: shouldRequireAllMilestoneMedia,
            failOnUnclassified: shouldFailOnUnclassifiedMilestoneFailures,
            failOnUnexpected: shouldFailOnUnexpectedMilestoneFailures
        )
        for milestone in milestones {
            if passedMilestones.contains(milestone.resultKey) {
                summaries.append("SKIP \(milestone.url.lastPathComponent) command=\(milestone.commandSummary) reason=previous pass in result log")
                runSummary.recordSkipped(milestone)
                try appendMilestoneResult(
                    milestone.skippedRecord(
                        runID: runID,
                        manifestHash: manifestHash,
                        reason: "previous pass in result log"
                    ),
                    to: resultLogURL
                )
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
            let expectedFailureMismatches = result.expectedFailureMismatches(for: milestone.expectedFailure)
            var screenshotURL: URL?
            if result.passed {
                screenshotURL = try writeMilestoneScreenshot(for: milestone, c64: c64, to: screenshotDirectoryURL)
            } else if screenshotFailuresEnabled {
                screenshotURL = try writeMilestoneScreenshot(
                    for: milestone,
                    c64: c64,
                    to: screenshotDirectoryURL,
                    suffix: "failed"
                )
            }
            let record = result.record(
                for: milestone,
                c64: c64,
                runID: runID,
                expectedFailureMatched: !result.passed && milestone.expectedFailure != nil && expectedFailureMismatches.isEmpty,
                expectedFailureMismatches: expectedFailureMismatches.isEmpty ? nil : expectedFailureMismatches,
                manifestHash: manifestHash,
                screenshotURL: screenshotURL
            )
            runSummary.record(record)
            try appendMilestoneResult(record, to: resultLogURL)
            XCTAssertTrue(
                result.passed || (milestone.expectedFailure != nil && expectedFailureMismatches.isEmpty),
                expectedFailureMismatches.isEmpty ? summary : summary + " expectedFailureMismatch=\(expectedFailureMismatches.joined(separator: "; "))"
            )
        }
        runSummary.refreshDerivedFields()
        try writeMilestoneRunSummary(runSummary, to: summaryURL)
        if shouldFailOnUnclassifiedMilestoneFailures {
            assertNoUnclassifiedMilestoneFailures(runSummary)
        }
        if shouldFailOnUnexpectedMilestoneFailures {
            assertNoUnexpectedMilestoneFailures(runSummary)
        }
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
            driveStatus: CompatibilityDriveStatus(
                minWeakBitReads: 1,
                minVariableSpeedZoneSamples: 1,
                requiredVariableSpeedZones: [0, 4],
                track: 17,
                hasDisk: true
            ),
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
        XCTAssertTrue(reason.contains("drive.minWeakBitReads 0 < 1"))
        XCTAssertTrue(reason.contains("drive.minVariableSpeedZoneSamples 0 < 1"))
        XCTAssertTrue(reason.contains("drive.requiredVariableSpeedZones missing 0"))
        XCTAssertTrue(reason.contains("drive.requiredVariableSpeedZones invalid 4"))
        XCTAssertTrue(reason.contains("drive.track"))
        XCTAssertTrue(reason.contains("drive.hasDisk"))
        XCTAssertTrue(reason.contains("media capabilities unavailable"))
        XCTAssertTrue(reason.contains("RAM $0801"))
        XCTAssertTrue(reason.contains("color RAM $0000"))
        XCTAssertTrue(reason.contains("screen hash"))
        XCTAssertTrue(reason.contains("color RAM hash"))
        XCTAssertTrue(reason.contains("timeout state pc=$"))
        XCTAssertTrue(reason.contains("drivePC=$"))
        XCTAssertTrue(reason.contains("driveNoProgress="))
    }

    func testMilestoneResultLogRoundTripsPassedEntriesForResume() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("milestones.jsonl")
        var milestone = LocalMilestone(
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
        milestone.id = "demo-loader"
        milestone.name = "Demo Loader"
        let runID = "unit-run"
        let currentManifestHash = "current-manifest"

        try appendMilestoneResult(
            MatrixRunResult(passed: false, elapsedCycles: 10, reason: "first failure").record(
                for: milestone,
                c64: C64(),
                runID: runID,
                manifestHash: currentManifestHash
            ),
            to: logURL
        )
        let tapeC64 = C64()
        XCTAssertTrue(tapeC64.mountTape(makeTinyTAP(pulses: [0x01, 0x02]), fileName: "loader.tap"))
        XCTAssertTrue(tapeC64.mountDisk(makeResultLogD64WithErrorTable(), fileName: "result-log.d64"))
        writeScreenText("READY.", into: tapeC64, row: 4, column: 2)
        try appendMilestoneResult(
            MatrixRunResult(passed: true, elapsedCycles: 20, reason: "named milestone reached").record(
                for: milestone,
                c64: tapeC64,
                runID: runID,
                manifestHash: currentManifestHash,
                screenshotURL: URL(fileURLWithPath: "/tmp/swift64-screens/demo.ppm")
            ),
            to: logURL
        )

        let passed = try passedMilestoneKeys(from: logURL)
        let log = try String(contentsOf: logURL, encoding: .utf8)

        XCTAssertTrue(passed.contains(milestone.resultKey))
        XCTAssertTrue(log.contains("\"passed\":false"))
        XCTAssertTrue(log.contains("\"passed\":true"))
        XCTAssertFalse(log.contains(#""skipped":true"#))
        XCTAssertTrue(log.contains(#""mediaType":"g64""#))
        XCTAssertTrue(log.contains(#""commandSummary":"LOAD\"*\",8,1 | RUN""#))
        XCTAssertTrue(log.contains(#""actionSummary":["LOAD\"*\",8,1","RUN"]"#))
        XCTAssertTrue(log.contains(#""maxCycles":1"#))
        XCTAssertTrue(log.contains(#""category":"#))
        XCTAssertTrue(log.contains(#""finalPC":"#))
        XCTAssertTrue(log.contains(#""finalScreenText":"#))
        XCTAssertTrue(log.contains(#""screenRAMHash":"#))
        XCTAssertTrue(log.contains(#""finalTapeDecodeStatus":"rawPulsesOnly""#))
        XCTAssertTrue(log.contains(#""finalMountedTapeName":"loader.tap""#))
        XCTAssertTrue(log.contains(#""finalMediaFormat":"D64""#))
        let records = try log.split(separator: "\n").map {
            try JSONDecoder().decode(MilestoneResultRecord.self, from: Data(String($0).utf8))
        }
        XCTAssertEqual(records.last?.screenshotPath, "/tmp/swift64-screens/demo.ppm")
        XCTAssertEqual(records.last?.formatVersion, MilestoneResultRecord.currentFormatVersion)
        XCTAssertNil(records.last?.skipped)
        XCTAssertEqual(records.last?.runID, runID)
        XCTAssertEqual(records.last?.manifestHash, currentManifestHash)
        XCTAssertNil(records.last?.expectedFailureCategory)
        XCTAssertNil(records.last?.expectedFailureReasonContains)
        XCTAssertNil(records.last?.expectedFailureMatched)
        XCTAssertNil(records.last?.expectedFailureMismatches)
        XCTAssertEqual(records.last?.milestoneID, "demo-loader")
        XCTAssertEqual(records.last?.milestoneName, "Demo Loader")
        XCTAssertEqual(records.last?.key.id, "demo-loader")
        XCTAssertEqual(records.last?.mediaType, "g64")
        XCTAssertEqual(records.last?.actionSummary, [#"LOAD"*",8,1"#, "RUN"])
        XCTAssertEqual(records.last?.maxCycles, 1)
        XCTAssertEqual(records.last?.finalA, "00")
        XCTAssertEqual(records.last?.finalX, "00")
        XCTAssertEqual(records.last?.finalY, "00")
        XCTAssertEqual(records.last?.finalSP, "FD")
        XCTAssertEqual(records.last?.finalP, "24")
        XCTAssertEqual(records.last?.finalIRQLine, false)
        XCTAssertEqual(records.last?.finalNMILine, false)
        XCTAssertEqual(records.last?.finalRDYLine, true)
        XCTAssertEqual(records.last?.finalCPUInstructionCycle, 0)
        XCTAssertEqual(records.last?.finalVICRasterLine, 0)
        XCTAssertEqual(records.last?.finalVICRasterCycle, 0)
        XCTAssertEqual(records.last?.finalReadTrack, 18)
        XCTAssertEqual(records.last?.finalReadHalfTrack, 34)
        XCTAssertEqual(records.last?.finalUsingHalfTrackFallback, false)
        XCTAssertEqual(records.last?.finalWeakBitReadCount, 0)
        XCTAssertEqual(records.last?.finalVariableSpeedZoneSampleCount, 0)
        XCTAssertEqual(records.last?.finalVariableSpeedZoneMask, 0)
        XCTAssertEqual(records.last?.finalDriveNoProgressCycleCount, 0)
        XCTAssertNil(records.last?.finalFailureReason)
        XCTAssertEqual(records.last?.finalMediaFormat, "D64")
        XCTAssertEqual(records.last?.finalMediaPopulatedHalfTrackCount, 35)
        XCTAssertEqual(records.last?.finalMediaNativeLowLevelTrackCount, 0)
        XCTAssertEqual(records.last?.finalMediaSyntheticGCRTrackCount, 35)
        XCTAssertEqual(records.last?.finalMediaHasSyntheticGCR, true)
        XCTAssertEqual(records.last?.finalMediaIsNativeLowLevel, false)
        XCTAssertEqual(records.last?.finalMediaPreservesSectorErrorInfo, true)
        XCTAssertEqual(records.last?.finalMediaSectorErrorCodeCount, 683)
        XCTAssertEqual(records.last?.finalMediaNonDefaultSectorErrorCodeCount, 2)
        XCTAssertEqual(records.last?.finalMediaWeakBitRangeCount, 0)
        XCTAssertEqual(records.last?.finalMediaWeakBitTotalBitCount, 0)
        XCTAssertEqual(records.last?.finalMediaVariableSpeedZoneByteCount, 0)
        XCTAssertEqual(records.last?.finalMediaSupportsWraparoundReads, true)
        XCTAssertNil(records.last?.finalMediaMaxTrackSize)
        XCTAssertEqual(records.last?.finalMediaUnsupportedFeatures, ["Native copy-protection bitstream"])
        XCTAssertEqual(records.last?.finalMountedTapeName, "loader.tap")
        XCTAssertEqual(records.last?.finalTapeDecodeStatus, "rawPulsesOnly")
        XCTAssertEqual(records.last?.finalTapePulseCount, 2)
        XCTAssertEqual(records.last?.finalTapeRawPlaybackActive, true)
        XCTAssertEqual(records.last?.finalTapeReadSignalHigh, true)
        XCTAssertEqual(records.last?.finalCassetteSenseLineHigh, false)
        XCTAssertEqual(records.last?.finalCassetteMotorEnabled, false)
        XCTAssertEqual(records.last?.finalTapeHasCapturedWritePulses, false)
        XCTAssertEqual(records.last?.finalCanExportCapturedTAP, false)
        XCTAssertEqual(records.last?.finalTapeHasUnsavedChanges, false)
        XCTAssertEqual(records.last?.finalCanExportSavedT64, false)
        XCTAssertTrue(records.last?.finalScreenText?.contains("READY.") == true)
        XCTAssertLessThanOrEqual(records.last?.finalScreenText?.count ?? 0, 1024)

        let legacyURL = directory.appendingPathComponent("legacy.jsonl")
        let legacyLine = #"{"commandSummary":"LOAD\"*\",8,1 | RUN","driveMode":"compat1541","elapsedCycles":5,"file":"demo.g64","machineProfile":"palC64","passed":true,"reason":"old pass"}"#
        try Data((legacyLine + "\n").utf8).write(to: legacyURL)

        let legacyRecord = try JSONDecoder().decode(MilestoneResultRecord.self, from: Data(legacyLine.utf8))
        XCTAssertNil(legacyRecord.formatVersion)
        XCTAssertNil(legacyRecord.skipped)
        XCTAssertNil(legacyRecord.runID)
        XCTAssertNil(legacyRecord.manifestHash)
        XCTAssertNil(legacyRecord.expectedFailureCategory)
        XCTAssertNil(legacyRecord.expectedFailureReasonContains)
        XCTAssertNil(legacyRecord.expectedFailureMatched)
        XCTAssertNil(legacyRecord.expectedFailureMismatches)
        XCTAssertNil(legacyRecord.mediaType)
        XCTAssertNil(legacyRecord.milestoneID)
        XCTAssertNil(legacyRecord.milestoneName)
        XCTAssertNil(legacyRecord.actionSummary)
        XCTAssertNil(legacyRecord.maxCycles)
        XCTAssertNil(legacyRecord.finalReadHalfTrack)
        XCTAssertNil(legacyRecord.finalA)
        XCTAssertNil(legacyRecord.finalX)
        XCTAssertNil(legacyRecord.finalY)
        XCTAssertNil(legacyRecord.finalSP)
        XCTAssertNil(legacyRecord.finalP)
        XCTAssertNil(legacyRecord.finalIRQLine)
        XCTAssertNil(legacyRecord.finalNMILine)
        XCTAssertNil(legacyRecord.finalRDYLine)
        XCTAssertNil(legacyRecord.finalCPUInstructionCycle)
        XCTAssertNil(legacyRecord.finalVICRasterLine)
        XCTAssertNil(legacyRecord.finalVICRasterCycle)
        XCTAssertNil(legacyRecord.finalWeakBitReadCount)
        XCTAssertNil(legacyRecord.finalVariableSpeedZoneSampleCount)
        XCTAssertNil(legacyRecord.finalVariableSpeedZoneMask)
        XCTAssertNil(legacyRecord.finalDriveNoProgressCycleCount)
        XCTAssertNil(legacyRecord.finalFailureReason)
        XCTAssertNil(legacyRecord.finalMediaFormat)
        XCTAssertNil(legacyRecord.finalTapeDecodeStatus)
        XCTAssertNil(legacyRecord.finalScreenText)
        XCTAssertTrue(try passedMilestoneKeys(from: legacyURL).contains(legacyRecord.key))

        let staleLogURL = directory.appendingPathComponent("stale.jsonl")
        try appendMilestoneResult(
            MatrixRunResult(passed: true, elapsedCycles: 30, reason: "named milestone reached").record(
                for: milestone,
                c64: C64(),
                runID: "old-run",
                manifestHash: "old-manifest"
            ),
            to: staleLogURL
        )
        try appendMilestoneResult(
            MatrixRunResult(passed: true, elapsedCycles: 40, reason: "named milestone reached").record(
                for: milestone,
                c64: C64(),
                runID: runID,
                manifestHash: currentManifestHash
            ),
            to: staleLogURL
        )
        XCTAssertTrue(try passedMilestoneKeys(from: staleLogURL).contains(milestone.resultKey))
        XCTAssertTrue(try passedMilestoneKeys(from: staleLogURL, matchingManifestHash: currentManifestHash).contains(milestone.resultKey))
        XCTAssertFalse(try passedMilestoneKeys(from: staleLogURL, matchingManifestHash: "different-manifest").contains(milestone.resultKey))

        let skippedLogURL = directory.appendingPathComponent("skipped.jsonl")
        try appendMilestoneResult(
            milestone.skippedRecord(runID: runID, manifestHash: currentManifestHash, reason: "previous pass in result log"),
            to: skippedLogURL
        )
        let skippedRecord = try XCTUnwrap(
            try String(contentsOf: skippedLogURL, encoding: .utf8)
                .split(separator: "\n")
                .map { try JSONDecoder().decode(MilestoneResultRecord.self, from: Data(String($0).utf8)) }
                .last
        )
        XCTAssertEqual(skippedRecord.formatVersion, MilestoneResultRecord.currentFormatVersion)
        XCTAssertEqual(skippedRecord.skipped, true)
        XCTAssertEqual(skippedRecord.passed, false)
        XCTAssertEqual(skippedRecord.category, "skipped")
        XCTAssertEqual(skippedRecord.runID, runID)
        XCTAssertEqual(skippedRecord.manifestHash, currentManifestHash)
        XCTAssertNil(skippedRecord.expectedFailureMatched)
        XCTAssertEqual(skippedRecord.key, milestone.resultKey)
        XCTAssertFalse(try passedMilestoneKeys(from: skippedLogURL).contains(milestone.resultKey))
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
        summary.configureRun(
            runID: "summary-run",
            manifestURL: URL(fileURLWithPath: "/tmp/compatibility.json"),
            manifestHash: "0123456789abcdef",
            resultLogURL: URL(fileURLWithPath: "/tmp/results.jsonl"),
            screenshotDirectoryURL: URL(fileURLWithPath: "/tmp/screens", isDirectory: true),
            resumeEnabled: true,
            strictManifestResumeEnabled: true,
            screenshotFailuresEnabled: true,
            milestoneLimit: 5,
            manifestMilestoneCount: 7,
            selectedMilestoneCount: 3,
            missingMediaFiles: ["missing.g64"],
            requireAllManifestMedia: true,
            failOnUnclassified: true,
            failOnUnexpected: true
        )
        summary.record(MatrixRunResult(passed: true, elapsedCycles: 10, reason: "named milestone reached").record(for: milestone, c64: C64()))
        summary.record(MatrixRunResult(passed: false, elapsedCycles: 20, reason: "PC $0801 not in $C000-$C0FF").record(
            for: milestone,
            c64: C64(),
            expectedFailureMatched: true
        ))
        summary.record(MatrixRunResult(passed: false, elapsedCycles: 30, reason: "unexpected fallback path").record(for: milestone, c64: C64()))
        summary.recordSkipped(milestone)

        try writeMilestoneRunSummary(summary, to: url)

        let decoded = try JSONDecoder().decode(MilestoneRunSummary.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.total, 4)
        XCTAssertEqual(decoded.executed, 3)
        XCTAssertEqual(decoded.passed, 1)
        XCTAssertEqual(decoded.failed, 2)
        XCTAssertEqual(decoded.expectedFailures, 1)
        XCTAssertEqual(decoded.unexpectedFailures, 1)
        XCTAssertEqual(decoded.skipped, 1)
        XCTAssertEqual(decoded.runnerName, "LocalDiskMatrixTests")
        XCTAssertEqual(decoded.resultRecordFormatVersion, MilestoneResultRecord.currentFormatVersion)
        XCTAssertEqual(decoded.runID, "summary-run")
        XCTAssertEqual(decoded.manifestPath, "/tmp/compatibility.json")
        XCTAssertEqual(decoded.manifestHash, "0123456789abcdef")
        XCTAssertEqual(decoded.resultLogPath, "/tmp/results.jsonl")
        XCTAssertEqual(decoded.screenshotDirectoryPath, "/tmp/screens")
        XCTAssertEqual(decoded.resumeEnabled, true)
        XCTAssertEqual(decoded.strictManifestResumeEnabled, true)
        XCTAssertEqual(decoded.screenshotFailuresEnabled, true)
        XCTAssertEqual(decoded.milestoneLimit, 5)
        XCTAssertEqual(decoded.manifestMilestoneCount, 7)
        XCTAssertEqual(decoded.selectedMilestoneCount, 3)
        XCTAssertEqual(decoded.missingMediaFiles, ["missing.g64"])
        XCTAssertEqual(decoded.requireAllManifestMedia, true)
        XCTAssertEqual(decoded.failOnUnclassified, true)
        XCTAssertEqual(decoded.failOnUnexpected, true)
        XCTAssertEqual(decoded.outcome, "acceptanceFailed")
        XCTAssertEqual(decoded.acceptanceFailures, ["unclassifiedFailures", "unexpectedFailures"])
        XCTAssertEqual(decoded.unclassifiedFailureCount, 1)
        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(decoded.totalElapsedCycles, 60)
        XCTAssertEqual(decoded.maxElapsedCycles, 30)
        XCTAssertEqual(decoded.slowestMilestone, milestone.resultKey)
        XCTAssertEqual(decoded.categories["pass"], 1)
        XCTAssertEqual(decoded.categories["pc"], 1)
        XCTAssertEqual(decoded.categories["emulator"], 1)
        XCTAssertEqual(decoded.failedMilestones, [milestone.resultKey, milestone.resultKey])
        XCTAssertEqual(decoded.failedMilestoneDetails, [
            MilestoneFailureSummary(
                key: milestone.resultKey,
                category: "pc",
                reason: "PC $0801 not in $C000-$C0FF",
                elapsedCycles: 20
            ),
            MilestoneFailureSummary(
                key: milestone.resultKey,
                category: "emulator",
                reason: "unexpected fallback path",
                elapsedCycles: 30
            )
        ])
        XCTAssertEqual(decoded.expectedFailureDetails, [
            MilestoneFailureSummary(
                key: milestone.resultKey,
                category: "pc",
                reason: "PC $0801 not in $C000-$C0FF",
                elapsedCycles: 20
            )
        ])
        XCTAssertEqual(decoded.unexpectedFailureDetails, [
            MilestoneFailureSummary(
                key: milestone.resultKey,
                category: "emulator",
                reason: "unexpected fallback path",
                elapsedCycles: 30
            )
        ])
        XCTAssertEqual(decoded.unclassifiedFailureDetails, [
            MilestoneFailureSummary(
                key: milestone.resultKey,
                category: "emulator",
                reason: "unexpected fallback path",
                elapsedCycles: 30
            )
        ])
        XCTAssertEqual(decoded.skippedMilestones, [milestone.resultKey])
        XCTAssertTrue(decoded.hasUnclassifiedFailures)
        XCTAssertTrue(decoded.hasUnexpectedFailures)
        XCTAssertTrue(decoded.unclassifiedFailureSummary.contains("demo.g64"))
        XCTAssertTrue(decoded.unclassifiedFailureSummary.contains("LOAD\"*\",8,1"))
        XCTAssertTrue(decoded.unclassifiedFailureSummary.contains("unexpected fallback path"))
        XCTAssertTrue(decoded.unexpectedFailureSummary.contains("demo.g64"))
        XCTAssertTrue(decoded.unexpectedFailureSummary.contains("unexpected fallback path"))
        XCTAssertFalse(decoded.unexpectedFailureSummary.contains("PC $0801 not in"))
        XCTAssertTrue(decoded.consoleSummary.contains("total=4"))
        XCTAssertTrue(decoded.consoleSummary.contains("executed=3"))
        XCTAssertTrue(decoded.consoleSummary.contains("selected=3"))
        XCTAssertTrue(decoded.consoleSummary.contains("missingMedia=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("expectedFailures=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("unexpectedFailures=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("unclassified=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("outcome=acceptanceFailed"))
        XCTAssertTrue(decoded.consoleSummary.contains("pc=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("emulator=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("cycles=60"))
    }

    func testMilestoneRunSummaryDerivesOutcomeStates() {
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

        var empty = MilestoneRunSummary()
        empty.refreshDerivedFields()
        XCTAssertEqual(empty.outcome, "notRun")
        XCTAssertEqual(empty.acceptanceFailures, [])

        var passed = MilestoneRunSummary()
        passed.record(MatrixRunResult(passed: true, elapsedCycles: 1, reason: "named milestone reached").record(for: milestone, c64: C64()))
        passed.refreshDerivedFields()
        XCTAssertEqual(passed.outcome, "passed")

        var expected = MilestoneRunSummary()
        expected.record(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "PC $0801 not in $C000-$C0FF").record(
            for: milestone,
            c64: C64(),
            expectedFailureMatched: true
        ))
        expected.refreshDerivedFields()
        XCTAssertEqual(expected.outcome, "expectedFailures")

        var unexpected = MilestoneRunSummary()
        unexpected.record(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "PC $0801 not in $C000-$C0FF").record(for: milestone, c64: C64()))
        unexpected.refreshDerivedFields()
        XCTAssertEqual(unexpected.outcome, "unexpectedFailures")
        XCTAssertEqual(unexpected.acceptanceFailures, [])

        var gated = unexpected
        gated.failOnUnexpected = true
        gated.refreshDerivedFields()
        XCTAssertEqual(gated.outcome, "acceptanceFailed")
        XCTAssertEqual(gated.acceptanceFailures, ["unexpectedFailures"])
    }

    func testMilestoneRunSummaryAcceptanceGateIgnoresCategorizedFailures() {
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/demo.d64"),
            mediaType: .d64,
            machineProfile: .palC64,
            driveMode: .compat1541,
            commands: [#"LOAD"$",8"#],
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
        summary.record(MatrixRunResult(passed: false, elapsedCycles: 20, reason: "PC $0801 not in $C000-$C0FF").record(for: milestone, c64: C64()))

        XCTAssertFalse(summary.hasUnclassifiedFailures)
        XCTAssertEqual(summary.unclassifiedFailureSummary, "No unclassified milestone failures.")
        XCTAssertTrue(summary.hasUnexpectedFailures)
    }

    func testMilestoneManifestHashUsesStableContentFingerprint() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifestURL = directory.appendingPathComponent("compatibility.json")
        let data = Data(#"{"milestones":[]}"#.utf8)
        try data.write(to: manifestURL)

        XCTAssertEqual(milestoneManifestHash(for: manifestURL), CompatibilityHash.fnv1a64(data))
        XCTAssertNil(milestoneManifestHash(for: directory.appendingPathComponent("missing.json")))
        XCTAssertNil(milestoneManifestHash(for: nil))
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

    func testMilestoneActionSchedulerControlsTapePlayback() {
        let c64 = C64()
        XCTAssertTrue(c64.mountTape(makeTinyTAP(pulses: [0x02, 0x03]), fileName: "loader.tap"))
        XCTAssertTrue(c64.tapeUnit.rawPlaybackActive)
        XCTAssertFalse(c64.memory.cassetteSenseLineHigh)

        let scheduler = MilestoneActionScheduler(actions: [
            .stopTape,
            .waitCycles(3),
            .startTape
        ])

        scheduler.applyDueActions(to: c64, elapsedCycles: 0)

        XCTAssertFalse(c64.tapeUnit.rawPlaybackActive)
        XCTAssertTrue(c64.memory.cassetteSenseLineHigh)
        XCTAssertTrue(c64.cia1.flagLineHigh)

        scheduler.applyDueActions(to: c64, elapsedCycles: 2)

        XCTAssertFalse(c64.tapeUnit.rawPlaybackActive)

        scheduler.applyDueActions(to: c64, elapsedCycles: 3)

        XCTAssertTrue(c64.tapeUnit.rawPlaybackActive)
        XCTAssertFalse(c64.memory.cassetteSenseLineHigh)
        XCTAssertTrue(c64.cia1.flagLineHigh)
        XCTAssertEqual(c64.tapeUnit.currentPulseIndex, 0)
        XCTAssertEqual(c64.tapeUnit.cyclesUntilNextPulse, 16)
    }

    func testMilestoneResultCategoriesAreStable() {
        XCTAssertEqual(MatrixRunResult(passed: true, elapsedCycles: 1, reason: "named milestone reached").category, .pass)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "CPU JAM/KIL").category, .cpu)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "C64 PC reached $FFFF").category, .cpu)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "PC $0801 not in $C000-$C0FF").category, .pc)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "cartridge ROML bank mismatch").category, .cartridge)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "app.fullscreen toolbar visible").category, .app)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "GCR reads 0 < 64").category, .drive)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "media capabilities unavailable").category, .media)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "drive.minWeakBitReads 0 < 1").category, .protectedMedia)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "drive.minVariableSpeedZoneSamples 0 < 1").category, .protectedMedia)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "media.variableSpeedZoneByteCount 0 != 256").category, .protectedMedia)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "tape.rawPlaybackActive false != true").category, .tape)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "RAM $0801 00 != 01").category, .ram)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "color RAM $0000 00 != 01").category, .screen)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "screen hash abc != def").category, .screen)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "VIC $D020 06 != 02 mask 0F").category, .video)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "SID $D418 0F != 10 mask FF").category, .audio)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "CIA1 $DC0E 01 != 00 mask 01").category, .cia)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "CPU.A $00 != $01").category, .cpu)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "named milestone timeout").category, .timeout)
    }

    func testExpectedFailureMatchesCategoryAndReason() {
        let c64 = C64()
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/demo.prg"),
            mediaType: .prg,
            machineProfile: .palC64,
            driveMode: .fastLoad,
            commands: [],
            maxCycles: 0,
            pcRanges: [0xC000...0xC0FF],
            minGCRReads: 0,
            minByteReady: 0,
            driveStatus: nil,
            mediaStatus: nil,
            ramSignatures: [],
            colorRAMSignatures: [],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil,
            expectedFailure: CompatibilityExpectedFailure(
                category: .pc,
                reasonContains: ["PC $0000 not in"]
            )
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .pc)
        XCTAssertTrue(result.expectedFailureMismatches(for: milestone.expectedFailure).isEmpty)
        XCTAssertEqual(
            result.expectedFailureMismatches(for: CompatibilityExpectedFailure(category: .drive)),
            ["category pc != drive"]
        )
        XCTAssertEqual(
            result.expectedFailureMismatches(for: CompatibilityExpectedFailure(category: .pc, reasonContains: ["GCR reads"])),
            ["reason missing GCR reads"]
        )

        let mismatchedRecord = result.record(
            for: milestone,
            c64: c64,
            expectedFailureMatched: false,
            expectedFailureMismatches: ["category pc != drive", "reason missing GCR reads"]
        )
        XCTAssertEqual(mismatchedRecord.expectedFailureMatched, false)
        XCTAssertEqual(mismatchedRecord.expectedFailureMismatches, [
            "category pc != drive",
            "reason missing GCR reads",
        ])

        let record = result.record(
            for: milestone,
            c64: c64,
            expectedFailureMatched: true
        )
        XCTAssertEqual(record.expectedFailureCategory, "pc")
        XCTAssertEqual(record.expectedFailureReasonContains, ["PC $0000 not in"])
        XCTAssertEqual(record.expectedFailureMatched, true)
        XCTAssertNil(record.expectedFailureMismatches)

        var summary = MilestoneRunSummary()
        summary.record(record)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.expectedFailures, 1)
        XCTAssertEqual(summary.unexpectedFailures, 0)
        XCTAssertEqual(summary.expectedFailureDetails.map(\.key), [milestone.resultKey])
        XCTAssertTrue(summary.unexpectedFailureDetails.isEmpty)
    }

    func testManifestMilestoneValidationRejectsDuplicateIDs() {
        var first = validationMilestone(file: "first.g64", commands: [#"LOAD"*",8,1"#])
        first.id = "giana-title"
        var second = validationMilestone(file: "second.g64", commands: [#"LOAD"$",8"#])
        second.id = "giana-title"

        let errors = manifestMilestoneValidationErrors([first, second])

        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("duplicate milestone id giana-title"), errors[0])
        XCTAssertTrue(errors[0].contains("first.g64"), errors[0])
        XCTAssertTrue(errors[0].contains("second.g64"), errors[0])
    }

    func testManifestMilestoneValidationRejectsDuplicateResultKeys() {
        let first = validationMilestone(file: "demo.g64", commands: [#"LOAD"*",8,1"#])
        let second = validationMilestone(file: "demo.g64", commands: [#"LOAD"*",8,1"#])

        let errors = manifestMilestoneValidationErrors([first, second])

        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("duplicate milestone key"), errors[0])
        XCTAssertTrue(errors[0].contains("demo.g64"), errors[0])
        XCTAssertTrue(errors[0].contains(#"LOAD"*",8,1"#), errors[0])
    }

    func testManifestMilestoneValidationAllowsDistinctModes() {
        let fastLoad = validationMilestone(file: "demo.g64", driveMode: .fastLoad, commands: [#"LOAD"*",8,1"#])
        let trueDrive = validationMilestone(file: "demo.g64", driveMode: .compat1541, commands: [#"LOAD"*",8,1"#])

        XCTAssertTrue(manifestMilestoneValidationErrors([fastLoad, trueDrive]).isEmpty)
    }

    func testManifestMissingMediaFilesAreReported() {
        let entries = [
            CompatibilityMilestone(file: "present.g64", command: #"LOAD"*",8,1"#),
            CompatibilityMilestone(file: "missing.d64", command: #"LOAD"$",8"#),
            CompatibilityMilestone(file: "nested/also-present.tap", command: "LOAD\r"),
        ]
        let urls = [
            URL(fileURLWithPath: "/tmp/present.g64"),
            URL(fileURLWithPath: "/tmp/corpus/nested/also-present.tap"),
        ]

        XCTAssertEqual(missingManifestMediaFiles(entries, urls: urls), ["missing.d64"])
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

    func testPPMScreenshotWriterAddsFailureSuffix() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

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
            screenshotName: "giana title"
        )

        let screenshotURL = try XCTUnwrap(
            writeMilestoneScreenshot(for: milestone, c64: C64(), to: directory, suffix: "failed")
        )

        XCTAssertEqual(screenshotURL.lastPathComponent, "giana_title-failed.ppm")
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotURL.path))
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

    private var shouldResumeOnlyMatchingManifest: Bool {
        ProcessInfo.processInfo.environment[milestoneResumeStrictManifestEnv] == "1"
    }

    private var shouldWriteFailedMilestoneScreenshots: Bool {
        ProcessInfo.processInfo.environment[milestoneScreenshotFailuresEnv] == "1"
    }

    private var shouldFailOnUnclassifiedMilestoneFailures: Bool {
        ProcessInfo.processInfo.environment[milestoneFailOnUnclassifiedEnv] == "1"
    }

    private var shouldFailOnUnexpectedMilestoneFailures: Bool {
        ProcessInfo.processInfo.environment[milestoneFailOnUnexpectedEnv] == "1"
    }

    private var shouldRequireAllMilestoneMedia: Bool {
        ProcessInfo.processInfo.environment[milestoneRequireAllMediaEnv] == "1"
    }

    private var localMilestoneLimit: Int? {
        Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_MILESTONE_LIMIT"] ?? "")
    }

    private func milestoneRunID() -> String {
        if let configured = ProcessInfo.processInfo.environment[milestoneRunIDEnv],
           !configured.isEmpty {
            return configured
        }
        return UUID().uuidString
    }

    private func activeMilestoneManifestURL() -> URL? {
        let url = localDiskRoot.appendingPathComponent("compatibility.json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func activeMilestoneManifestHash() -> String? {
        milestoneManifestHash(for: activeMilestoneManifestURL())
    }

    private func milestoneManifestHash(for url: URL?) -> String? {
        guard let url,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return CompatibilityHash.fnv1a64(data)
    }

    private func assertNoUnclassifiedMilestoneFailures(
        _ summary: MilestoneRunSummary,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(summary.hasUnclassifiedFailures, summary.unclassifiedFailureSummary, file: file, line: line)
    }

    private func assertNoUnexpectedMilestoneFailures(
        _ summary: MilestoneRunSummary,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(summary.hasUnexpectedFailures, summary.unexpectedFailureSummary, file: file, line: line)
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
            let weakBitReads = driveStatus.weakBitReadCount - baseline.weakBitReadCount
            let variableSpeedZoneSamples = driveStatus.variableSpeedZoneSampleCount - baseline.variableSpeedZoneSampleCount
            let pcReached = milestone.pcRanges.isEmpty || milestone.pcRanges.contains { $0.contains(c64.cpu.pc) }
            let driveProgress = gcrReads >= milestone.minGCRReads && byteReady >= milestone.minByteReady
            let driveExpectationMatches = milestone.driveStatus.map { expectation in
                driveStatusMismatches(
                    expectation,
                    snapshot: driveStatus,
                    gcrReads: gcrReads,
                    byteReady: byteReady,
                    syncDetections: syncDetections,
                    weakBitReads: weakBitReads,
                    variableSpeedZoneSamples: variableSpeedZoneSamples
                ).isEmpty
            } ?? true
            let mediaExpectationMatches = milestone.mediaStatus.map { expectation in
                mediaStatusMismatches(expectation, capabilities: c64.emulationStatus.mediaCapabilities).isEmpty
            } ?? true
            let tapeExpectationMatches = milestone.tapeStatus.map { expectation in
                tapeStatusMismatches(expectation, status: c64.emulationStatus).isEmpty
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
                && tapeExpectationMatches
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

    private func validationMilestone(
        file: String,
        machineProfile: CompatibilityMachineProfile = .palC64,
        driveMode: CompatibilityDriveMode = .compat1541,
        commands: [String]
    ) -> LocalMilestone {
        LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/\(file)"),
            mediaType: .g64,
            machineProfile: machineProfile,
            driveMode: driveMode,
            commands: commands,
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
    }

    private func localMilestoneLoadResult() throws -> MilestoneLoadResult {
        let urls = try localMediaURLs(limitEnv: "SWIFT64_LOCAL_MILESTONE_LIMIT", extensions: Self.milestoneMediaExtensions)
        let manifestLoad = try loadManifestMilestones(urls: urls)
        if !manifestLoad.milestones.isEmpty {
            return manifestLoad
        }

        guard let giana = urls.first(where: {
            $0.lastPathComponent.lowercased().contains("great_giana_sisters")
            && $0.pathExtension.lowercased() == "g64"
        }) else {
            return MilestoneLoadResult()
        }

        return MilestoneLoadResult(
            milestones: [
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
                    screenshotName: nil,
                    expectedFailure: nil
                )
            ]
        )
    }

    private func loadManifestMilestones(urls: [URL]) throws -> MilestoneLoadResult {
        let manifestURL = localDiskRoot.appendingPathComponent("compatibility.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return MilestoneLoadResult()
        }

        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(contentsOf: manifestURL))
        let milestones = manifest.milestones.compactMap { entry -> LocalMilestone? in
            guard let url = manifestMediaURL(for: entry, urls: urls) else {
                return nil
            }
            let driveMode = entry.driveMode ?? .compat1541
            let mediaType = entry.mediaType ?? mediaType(for: url)
            var milestone = LocalMilestone(
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
                screenshotName: entry.screenshotName,
                expectedFailure: entry.expectedFailure
            )
            milestone.id = entry.id
            milestone.name = entry.name
            milestone.tapeStatus = entry.tapeStatus
            milestone.weakBitRanges = entry.weakBitRanges
            milestone.speedZoneRanges = entry.speedZoneRanges
            return milestone
        }
        let validationErrors = manifestMilestoneValidationErrors(milestones)
        guard validationErrors.isEmpty else {
            throw ManifestValidationError(errors: validationErrors)
        }
        let missingMediaFiles = missingManifestMediaFiles(manifest.milestones, urls: urls)
        if shouldRequireAllMilestoneMedia && !missingMediaFiles.isEmpty {
            throw ManifestValidationError(errors: [
                "missing manifest media files: \(missingMediaFiles.joined(separator: ", "))"
            ])
        }
        return MilestoneLoadResult(
            milestones: milestones,
            manifestMilestoneCount: manifest.milestones.count,
            missingMediaFiles: missingMediaFiles
        )
    }

    private func manifestMediaURL(for entry: CompatibilityMilestone, urls: [URL]) -> URL? {
        urls.first { $0.lastPathComponent == entry.file || $0.path.contains(entry.file) }
    }

    private func missingManifestMediaFiles(_ entries: [CompatibilityMilestone], urls: [URL]) -> [String] {
        entries.compactMap { entry in
            manifestMediaURL(for: entry, urls: urls) == nil ? entry.file : nil
        }
    }

    private func mountPrePowerOnMedia(for milestone: LocalMilestone, into c64: C64) -> Bool {
        switch milestone.mediaType {
        case .d64, .g64:
            guard c64.mountDisk(milestone.url) else { return false }
            return applyWeakBitRanges(milestone.weakBitRanges, to: c64)
                && applySpeedZoneRanges(milestone.speedZoneRanges, to: c64)
        case .t64, .tap:
            return c64.mountTape(milestone.url)
        case .crt:
            return c64.mountCartridge(milestone.url)
        case .prg:
            return true
        }
    }

    private func applyWeakBitRanges(_ ranges: [CompatibilityWeakBitRange], to c64: C64) -> Bool {
        let rangesByHalfTrack = Dictionary(grouping: ranges, by: \.halfTrack)
        for (halfTrack, halfTrackRanges) in rangesByHalfTrack {
            guard c64.drive1541.disk.setWeakBitRanges(
                halfTrackRanges.map(\.diskRange),
                forHalfTrack: halfTrack
            ) else {
                return false
            }
        }
        return true
    }

    private func applySpeedZoneRanges(_ ranges: [CompatibilitySpeedZoneRange], to c64: C64) -> Bool {
        let rangesByHalfTrack = Dictionary(grouping: ranges, by: \.halfTrack)
        for (halfTrack, halfTrackRanges) in rangesByHalfTrack {
            guard c64.drive1541.disk.setSpeedZoneRanges(
                halfTrackRanges.map(\.diskRange),
                forHalfTrack: halfTrack
            ) else {
                return false
            }
        }
        return true
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
        let weakBitReads = driveStatus.weakBitReadCount - baseline.weakBitReadCount
        let variableSpeedZoneSamples = driveStatus.variableSpeedZoneSampleCount - baseline.variableSpeedZoneSampleCount
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
                syncDetections: syncDetections,
                weakBitReads: weakBitReads,
                variableSpeedZoneSamples: variableSpeedZoneSamples
            ))
        }
        if let mediaStatusExpectation = milestone.mediaStatus {
            unmet.append(contentsOf: mediaStatusMismatches(
                mediaStatusExpectation,
                capabilities: c64.emulationStatus.mediaCapabilities
            ))
        }
        if let tapeStatusExpectation = milestone.tapeStatus {
            unmet.append(contentsOf: tapeStatusMismatches(
                tapeStatusExpectation,
                status: c64.emulationStatus
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
            return "named milestone timeout after all expectations matched; " + timeoutStateSummary(c64)
        }
        return "named milestone timeout; unmet: " + unmet.joined(separator: "; ") + "; " + timeoutStateSummary(c64)
    }

    private func timeoutStateSummary(_ c64: C64) -> String {
        let driveStatus = c64.drive1541.statusSnapshot
        return "timeout state pc=$\(hex16(c64.cpu.pc)) drivePC=$\(hex16(driveStatus.cpuPC)) driveNoProgress=\(driveStatus.noProgressCycleCount)"
    }

    private func driveStatusMismatches(
        _ expectation: CompatibilityDriveStatus,
        snapshot: Drive1541.StatusSnapshot,
        gcrReads: UInt64,
        byteReady: UInt64,
        syncDetections: UInt64,
        weakBitReads: UInt64,
        variableSpeedZoneSamples: UInt64
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
        if let minWeakBitReads = expectation.minWeakBitReads,
           weakBitReads < nonNegativeUInt64(minWeakBitReads) {
            mismatches.append("drive.minWeakBitReads \(weakBitReads) < \(minWeakBitReads)")
        }
        if let minVariableSpeedZoneSamples = expectation.minVariableSpeedZoneSamples,
           variableSpeedZoneSamples < nonNegativeUInt64(minVariableSpeedZoneSamples) {
            mismatches.append("drive.minVariableSpeedZoneSamples \(variableSpeedZoneSamples) < \(minVariableSpeedZoneSamples)")
        }
        for zone in expectation.requiredVariableSpeedZones {
            guard (0...3).contains(zone) else {
                mismatches.append("drive.requiredVariableSpeedZones invalid \(zone)")
                continue
            }
            if snapshot.variableSpeedZoneMask & UInt8(1 << zone) == 0 {
                mismatches.append("drive.requiredVariableSpeedZones missing \(zone)")
            }
        }
        if let track = expectation.track, snapshot.track != track {
            mismatches.append("drive.track \(snapshot.track) != \(track)")
        }
        if let halfTrack = expectation.halfTrack, snapshot.halfTrack != halfTrack {
            mismatches.append("drive.halfTrack \(snapshot.halfTrack) != \(halfTrack)")
        }
        if let readTrack = expectation.readTrack, snapshot.readTrack != readTrack {
            mismatches.append("drive.readTrack \(snapshot.readTrack.map(String.init) ?? "nil") != \(readTrack)")
        }
        if let readHalfTrack = expectation.readHalfTrack, snapshot.readHalfTrack != readHalfTrack {
            mismatches.append("drive.readHalfTrack \(snapshot.readHalfTrack.map(String.init) ?? "nil") != \(readHalfTrack)")
        }
        if let usingHalfTrackFallback = expectation.usingHalfTrackFallback,
           snapshot.usingHalfTrackFallback != usingHalfTrackFallback {
            mismatches.append("drive.usingHalfTrackFallback \(snapshot.usingHalfTrackFallback) != \(usingHalfTrackFallback)")
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
        if let sectorErrorCodeCount = expectation.sectorErrorCodeCount,
           capabilities.sectorErrorCodeCount != sectorErrorCodeCount {
            mismatches.append("media.sectorErrorCodeCount \(capabilities.sectorErrorCodeCount) != \(sectorErrorCodeCount)")
        }
        if let nonDefaultSectorErrorCodeCount = expectation.nonDefaultSectorErrorCodeCount,
           capabilities.nonDefaultSectorErrorCodeCount != nonDefaultSectorErrorCodeCount {
            mismatches.append("media.nonDefaultSectorErrorCodeCount \(capabilities.nonDefaultSectorErrorCodeCount) != \(nonDefaultSectorErrorCodeCount)")
        }
        if let weakBitRangeCount = expectation.weakBitRangeCount,
           capabilities.weakBitRangeCount != weakBitRangeCount {
            mismatches.append("media.weakBitRangeCount \(capabilities.weakBitRangeCount) != \(weakBitRangeCount)")
        }
        if let weakBitTotalBitCount = expectation.weakBitTotalBitCount,
           capabilities.weakBitTotalBitCount != weakBitTotalBitCount {
            mismatches.append("media.weakBitTotalBitCount \(capabilities.weakBitTotalBitCount) != \(weakBitTotalBitCount)")
        }
        if let variableSpeedZoneByteCount = expectation.variableSpeedZoneByteCount,
           capabilities.variableSpeedZoneByteCount != variableSpeedZoneByteCount {
            mismatches.append("media.variableSpeedZoneByteCount \(capabilities.variableSpeedZoneByteCount) != \(variableSpeedZoneByteCount)")
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

    private func tapeStatusMismatches(
        _ expectation: CompatibilityTapeStatus,
        status: C64.EmulationStatus
    ) -> [String] {
        var mismatches: [String] = []
        if let mountedTapeNameContains = expectation.mountedTapeNameContains {
            if status.mountedTapeName?.localizedCaseInsensitiveContains(mountedTapeNameContains) != true {
                mismatches.append("tape.mountedTapeName missing \(mountedTapeNameContains)")
            }
        }
        let actualDecode = compatibilityTapeDecodeStatus(status.tapeDecodeStatus)
        if let decodeStatus = expectation.decodeStatus,
           actualDecode.status != decodeStatus {
            mismatches.append("tape.decodeStatus \(actualDecode.status.rawValue) != \(decodeStatus.rawValue)")
        }
        if let pulseCount = expectation.pulseCount,
           actualDecode.pulseCount != pulseCount {
            mismatches.append("tape.pulseCount \(actualDecode.pulseCount.map(String.init) ?? "nil") != \(pulseCount)")
        }
        if let programCount = expectation.programCount,
           actualDecode.programCount != programCount {
            mismatches.append("tape.programCount \(actualDecode.programCount.map(String.init) ?? "nil") != \(programCount)")
        }
        if let blockCount = expectation.blockCount,
           actualDecode.blockCount != blockCount {
            mismatches.append("tape.blockCount \(actualDecode.blockCount.map(String.init) ?? "nil") != \(blockCount)")
        }
        if let decodeFailureReason = expectation.decodeFailureReason,
           actualDecode.failureReason != decodeFailureReason {
            mismatches.append("tape.decodeFailureReason \(actualDecode.failureReason?.rawValue ?? "nil") != \(decodeFailureReason.rawValue)")
        }
        if let rawPlaybackActive = expectation.rawPlaybackActive,
           status.tapeRawPlaybackActive != rawPlaybackActive {
            mismatches.append("tape.rawPlaybackActive \(status.tapeRawPlaybackActive) != \(rawPlaybackActive)")
        }
        if let readSignalHigh = expectation.readSignalHigh,
           status.tapeReadSignalHigh != readSignalHigh {
            mismatches.append("tape.readSignalHigh \(status.tapeReadSignalHigh) != \(readSignalHigh)")
        }
        if let cassetteSenseLineHigh = expectation.cassetteSenseLineHigh,
           status.cassetteSenseLineHigh != cassetteSenseLineHigh {
            mismatches.append("tape.cassetteSenseLineHigh \(status.cassetteSenseLineHigh) != \(cassetteSenseLineHigh)")
        }
        if let cassetteMotorEnabled = expectation.cassetteMotorEnabled,
           status.cassetteMotorEnabled != cassetteMotorEnabled {
            mismatches.append("tape.cassetteMotorEnabled \(status.cassetteMotorEnabled) != \(cassetteMotorEnabled)")
        }
        if let hasCapturedWritePulses = expectation.hasCapturedWritePulses,
           status.tapeHasCapturedWritePulses != hasCapturedWritePulses {
            mismatches.append("tape.hasCapturedWritePulses \(status.tapeHasCapturedWritePulses) != \(hasCapturedWritePulses)")
        }
        if let canExportCapturedTAP = expectation.canExportCapturedTAP,
           status.canExportCapturedTAP != canExportCapturedTAP {
            mismatches.append("tape.canExportCapturedTAP \(status.canExportCapturedTAP) != \(canExportCapturedTAP)")
        }
        if let hasUnsavedChanges = expectation.hasUnsavedChanges,
           status.tapeHasUnsavedChanges != hasUnsavedChanges {
            mismatches.append("tape.hasUnsavedChanges \(status.tapeHasUnsavedChanges) != \(hasUnsavedChanges)")
        }
        if let canExportSavedT64 = expectation.canExportSavedT64,
           status.canExportSavedT64 != canExportSavedT64 {
            mismatches.append("tape.canExportSavedT64 \(status.canExportSavedT64) != \(canExportSavedT64)")
        }
        return mismatches
    }

    private func compatibilityTapeDecodeStatus(
        _ status: TapeUnit.TAPDecodeStatus
    ) -> (
        status: CompatibilityTapeDecodeStatusKind,
        pulseCount: Int?,
        programCount: Int?,
        blockCount: Int?,
        failureReason: CompatibilityTapeDecodeFailureReason?
    ) {
        switch status {
        case .none:
            return (.none, nil, nil, nil, nil)
        case let .rawPulsesOnly(pulseCount):
            return (.rawPulsesOnly, pulseCount, nil, nil, nil)
        case let .decodedPrograms(programCount, pulseCount):
            return (.decodedPrograms, pulseCount, programCount, nil, nil)
        case let .standardCBMNoPrograms(blockCount, reason):
            return (.standardCBMNoPrograms, nil, nil, blockCount, compatibilityTapeDecodeFailureReason(reason))
        }
    }

    private func compatibilityTapeDecodeFailureReason(
        _ reason: TapeUnit.TAPDecodeFailureReason
    ) -> CompatibilityTapeDecodeFailureReason {
        switch reason {
        case .noStandardBlocks:
            return .noStandardBlocks
        case .malformedStandardBlocks:
            return .malformedStandardBlocks
        case .incompleteHeaderData:
            return .incompleteHeaderData
        case .conflictingDuplicateData:
            return .conflictingDuplicateData
        }
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
        milestoneScreenText(ram)
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
        var summary = summary
        summary.refreshDerivedFields()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(summary).write(to: url, options: .atomic)
    }

    private func passedMilestoneKeys(
        from url: URL?,
        matchingManifestHash: String? = nil
    ) throws -> Set<MilestoneResultKey> {
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
                  record.passed,
                  record.skipped != true else {
                continue
            }
            if let matchingManifestHash, record.manifestHash != matchingManifestHash {
                continue
            }
            keys.insert(record.key)
        }
        return keys
    }

    private func writeMilestoneScreenshot(
        for milestone: LocalMilestone,
        c64: C64,
        to directory: URL?,
        suffix: String? = nil
    ) throws -> URL? {
        guard let directory,
              let screenshotName = milestone.screenshotName,
              !screenshotName.isEmpty else {
            return nil
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let baseName = sanitizedScreenshotName(screenshotName)
        let suffixPart = suffix.map { "-" + sanitizedScreenshotName($0) } ?? ""
        let filename = baseName + suffixPart + ".ppm"
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

    private func makeResultLogD64WithErrorTable() -> Data {
        var image = [UInt8](repeating: 0, count: 174848)
        let bamOffset = DiskDrive.trackOffset[18]
        image[bamOffset + 0] = 18
        image[bamOffset + 1] = 1
        image[bamOffset + 2] = 0x41
        image[bamOffset + 0xA2] = 0x41
        image[bamOffset + 0xA3] = 0x42

        var errors = [UInt8](repeating: 0x01, count: 683)
        errors[0] = 0x05
        errors[358] = 0x0B
        image.append(contentsOf: errors)
        return Data(image)
    }
}

private func milestoneScreenText(_ ram: [UInt8]) -> String {
    guard ram.count >= 0x0800 else { return "" }
    let text = (0..<25)
        .map { row in
            let start = 0x0400 + row * 40
            let end = start + 40
            return ram[start..<end].map(milestoneScreenCodeCharacter).joined()
        }
        .joined(separator: "\n")
    return String(text.prefix(1024))
}

private func milestoneScreenCodeCharacter(_ byte: UInt8) -> String {
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

private struct MatrixRunResult {
    let passed: Bool
    let elapsedCycles: UInt64
    let reason: String

    func summary(name: String, command: String, c64: C64) -> String {
        let drive = c64.drive1541.statusSnapshot
        let media = c64.emulationStatus.mediaCapabilities
        let mediaText = media.map {
            "\($0.format.displayName):tracks=\($0.populatedHalfTrackCount),native=\($0.nativeLowLevelTrackCount),synthetic=\($0.syntheticGCRTrackCount),errors=\($0.nonDefaultSectorErrorCodeCount),weakRanges=\($0.weakBitRangeCount),speedBytes=\($0.variableSpeedZoneByteCount)"
        } ?? "none"
        let readText = drive.readHalfTrack.map { "readHalf=\($0)\(drive.usingHalfTrackFallback ? ",fallback" : "")" } ?? "readHalf=none"
        let verdict = passed ? "PASS" : "FAIL"
        return "\(verdict) \(name) category=\(category.rawValue) command=\(command) driveMode=\(c64.trueDriveEmulationMode.displayName) cycles=\(elapsedCycles) pc=$\(hex16(c64.cpu.pc)) drivePC=$\(hex16(drive.cpuPC)) track=\(drive.track) half=\(drive.halfTrack) \(readText) media=[\(mediaText)] iec=[\(drive.lastIECCommandSummary)] byteReady=\(drive.byteReadyCount) paReads=\(drive.via2PortAReadCount) weakBits=\(drive.weakBitReadCount) speedSamples=\(drive.variableSpeedZoneSampleCount) speedZones=$\(hex8(drive.variableSpeedZoneMask)) reason=\(reason)"
    }

    var category: MilestoneResultCategory {
        MilestoneResultCategory.classify(passed: passed, reason: reason)
    }

    private func hex16(_ value: UInt16) -> String {
        String(format: "%04X", value)
    }

    private func hex8(_ value: UInt8) -> String {
        String(format: "%02X", value)
    }

    func record(
        for milestone: LocalMilestone,
        c64: C64,
        runID: String? = nil,
        expectedFailureMatched: Bool? = nil,
        expectedFailureMismatches: [String]? = nil,
        manifestHash: String? = nil,
        screenshotURL: URL? = nil
    ) -> MilestoneResultRecord {
        let drive = c64.drive1541.statusSnapshot
        let tapeStatus = c64.emulationStatus
        let tapeDecode = tapeDecodeRecordFields(tapeStatus.tapeDecodeStatus)
        let media = tapeStatus.mediaCapabilities
        return MilestoneResultRecord(
            formatVersion: MilestoneResultRecord.currentFormatVersion,
            runID: runID,
            manifestHash: manifestHash,
            expectedFailureCategory: milestone.expectedFailure?.category.rawValue,
            expectedFailureReasonContains: milestone.expectedFailure?.reasonContains,
            expectedFailureMatched: expectedFailureMatched,
            expectedFailureMismatches: expectedFailureMismatches,
            milestoneID: milestone.id,
            milestoneName: milestone.name,
            file: milestone.url.lastPathComponent,
            mediaType: milestone.mediaType.rawValue,
            commandSummary: milestone.commandSummary,
            actionSummary: milestone.scheduledActions.map(\.summary),
            machineProfile: milestone.machineProfile.rawValue,
            driveMode: milestone.driveMode.rawValue,
            maxCycles: milestone.maxCycles,
            passed: passed,
            elapsedCycles: elapsedCycles,
            reason: reason,
            category: category.rawValue,
            finalPC: hex16(c64.cpu.pc),
            finalA: hex8(c64.cpu.a),
            finalX: hex8(c64.cpu.x),
            finalY: hex8(c64.cpu.y),
            finalSP: hex8(c64.cpu.sp),
            finalP: hex8(c64.cpu.p),
            finalIRQLine: c64.cpu.irqLine,
            finalNMILine: c64.cpu.nmiLine,
            finalRDYLine: c64.cpu.rdyLine,
            finalCPUInstructionCycle: c64.cpu.cycle,
            finalVICRasterLine: Int(c64.vic.rasterLine),
            finalVICRasterCycle: c64.vic.rasterCycle,
            finalDrivePC: hex16(drive.cpuPC),
            finalTrack: drive.track,
            finalHalfTrack: drive.halfTrack,
            finalReadTrack: drive.readTrack,
            finalReadHalfTrack: drive.readHalfTrack,
            finalUsingHalfTrackFallback: drive.usingHalfTrackFallback,
            finalByteReadyCount: drive.byteReadyCount,
            finalVia2PortAReadCount: drive.via2PortAReadCount,
            finalWeakBitReadCount: drive.weakBitReadCount,
            finalVariableSpeedZoneSampleCount: drive.variableSpeedZoneSampleCount,
            finalVariableSpeedZoneMask: drive.variableSpeedZoneMask,
            finalLastIECCommandSummary: drive.lastIECCommandSummary,
            finalDriveNoProgressCycleCount: drive.noProgressCycleCount,
            finalFailureReason: tapeStatus.lastFailureReason,
            finalMediaFormat: media?.format.displayName,
            finalMediaPopulatedHalfTrackCount: media?.populatedHalfTrackCount,
            finalMediaNativeLowLevelTrackCount: media?.nativeLowLevelTrackCount,
            finalMediaSyntheticGCRTrackCount: media?.syntheticGCRTrackCount,
            finalMediaHasSyntheticGCR: media?.hasSyntheticGCR,
            finalMediaIsNativeLowLevel: media?.isNativeLowLevel,
            finalMediaPreservesHalfTracks: media?.preservesHalfTracks,
            finalMediaPreservesRawTrackLengths: media?.preservesRawTrackLengths,
            finalMediaPreservesSpeedZones: media?.preservesSpeedZones,
            finalMediaPreservesVariableSpeedZones: media?.preservesVariableSpeedZones,
            finalMediaPreservesSectorErrorInfo: media?.preservesSectorErrorInfo,
            finalMediaSectorErrorCodeCount: media?.sectorErrorCodeCount,
            finalMediaNonDefaultSectorErrorCodeCount: media?.nonDefaultSectorErrorCodeCount,
            finalMediaWeakBitRangeCount: media?.weakBitRangeCount,
            finalMediaWeakBitTotalBitCount: media?.weakBitTotalBitCount,
            finalMediaVariableSpeedZoneByteCount: media?.variableSpeedZoneByteCount,
            finalMediaSupportsWraparoundReads: media?.supportsWraparoundReads,
            finalMediaMaxTrackSize: media?.maxTrackSize,
            finalMediaUnsupportedFeatures: media?.unsupportedFeatures,
            finalMountedTapeName: tapeStatus.mountedTapeName,
            finalTapeDecodeStatus: tapeDecode.status,
            finalTapePulseCount: tapeDecode.pulseCount,
            finalTapeProgramCount: tapeDecode.programCount,
            finalTapeBlockCount: tapeDecode.blockCount,
            finalTapeDecodeFailureReason: tapeDecode.failureReason,
            finalTapeRawPlaybackActive: tapeStatus.tapeRawPlaybackActive,
            finalTapeReadSignalHigh: tapeStatus.tapeReadSignalHigh,
            finalCassetteSenseLineHigh: tapeStatus.cassetteSenseLineHigh,
            finalCassetteMotorEnabled: tapeStatus.cassetteMotorEnabled,
            finalTapeHasCapturedWritePulses: tapeStatus.tapeHasCapturedWritePulses,
            finalCanExportCapturedTAP: tapeStatus.canExportCapturedTAP,
            finalTapeHasUnsavedChanges: tapeStatus.tapeHasUnsavedChanges,
            finalCanExportSavedT64: tapeStatus.canExportSavedT64,
            finalScreenText: milestoneScreenText(c64.memory.ram),
            screenRAMHash: CompatibilityHash.screenRAM(c64.memory.ram),
            colorRAMHash: CompatibilityHash.colorRAM(c64.memory.colorRAM),
            screenshotPath: screenshotURL?.path
        )
    }

    func expectedFailureMismatches(for expectedFailure: CompatibilityExpectedFailure?) -> [String] {
        guard let expectedFailure else {
            return []
        }
        var mismatches: [String] = []
        if category.rawValue != expectedFailure.category.rawValue {
            mismatches.append("category \(category.rawValue) != \(expectedFailure.category.rawValue)")
        }
        for expectedReason in expectedFailure.reasonContains
            where !reason.localizedCaseInsensitiveContains(expectedReason) {
            mismatches.append("reason missing \(expectedReason)")
        }
        return mismatches
    }

    private func tapeDecodeRecordFields(
        _ status: TapeUnit.TAPDecodeStatus
    ) -> (
        status: String,
        pulseCount: Int?,
        programCount: Int?,
        blockCount: Int?,
        failureReason: String?
    ) {
        switch status {
        case .none:
            return ("none", nil, nil, nil, nil)
        case let .rawPulsesOnly(pulseCount):
            return ("rawPulsesOnly", pulseCount, nil, nil, nil)
        case let .decodedPrograms(programCount, pulseCount):
            return ("decodedPrograms", pulseCount, programCount, nil, nil)
        case let .standardCBMNoPrograms(blockCount, reason):
            return ("standardCBMNoPrograms", nil, nil, blockCount, tapeDecodeFailureReasonName(reason))
        }
    }

    private func tapeDecodeFailureReasonName(_ reason: TapeUnit.TAPDecodeFailureReason) -> String {
        switch reason {
        case .noStandardBlocks:
            return "noStandardBlocks"
        case .malformedStandardBlocks:
            return "malformedStandardBlocks"
        case .incompleteHeaderData:
            return "incompleteHeaderData"
        case .conflictingDuplicateData:
            return "conflictingDuplicateData"
        }
    }
}

private enum MilestoneResultCategory: String {
    case pass
    case cpu
    case drive
    case media
    case protectedMedia
    case cartridge
    case app
    case pc
    case ram
    case screen
    case tape
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
        if lower.contains("cartridge")
            || lower.contains("crt ")
            || lower.contains(".crt")
            || lower.contains("roml")
            || lower.contains("romh")
            || lower.contains("ultimax")
            || lower.contains("exrom")
            || lower.contains("game line") {
            return .cartridge
        }
        if lower.contains("app.")
            || lower.contains("rom setup")
            || lower.contains("roms need setup")
            || lower.contains("fullscreen")
            || lower.contains("full screen")
            || lower.contains("settings")
            || lower.contains("release bundle") {
            return .app
        }
        if lower.contains("weakbit")
            || lower.contains("weak bit")
            || lower.contains("weak-bit")
            || lower.contains("variable speed")
            || lower.contains("variable-speed")
            || lower.contains("variablespeed")
            || lower.contains("speedzone")
            || lower.contains("speed zone")
            || lower.contains("speed-zone")
            || lower.contains("requiredvariablespeedzones") {
            return .protectedMedia
        }
        if lower.contains("media") {
            return .media
        }
        if lower.contains("tape.") || lower.contains("cassette") {
            return .tape
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
        case .startTape:
            _ = c64.startTapePlayback()
        case .stopTape:
            c64.stopTapePlayback()
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
        case .startTape:
            return "tape start"
        case .stopTape:
            return "tape stop"
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
    var id: String?
    var name: String?
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
    var weakBitRanges: [CompatibilityWeakBitRange] = []
    var speedZoneRanges: [CompatibilitySpeedZoneRange] = []
    var tapeStatus: CompatibilityTapeStatus? = nil
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
    var expectedFailure: CompatibilityExpectedFailure? = nil

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
            id: id,
            file: url.lastPathComponent,
            commandSummary: commandSummary,
            machineProfile: machineProfile.rawValue,
            driveMode: driveMode.rawValue
        )
    }

    func skippedRecord(runID: String?, manifestHash: String?, reason: String) -> MilestoneResultRecord {
        MilestoneResultRecord(
            formatVersion: MilestoneResultRecord.currentFormatVersion,
            skipped: true,
            runID: runID,
            manifestHash: manifestHash,
            expectedFailureCategory: expectedFailure?.category.rawValue,
            expectedFailureReasonContains: expectedFailure?.reasonContains,
            expectedFailureMatched: nil,
            milestoneID: id,
            milestoneName: name,
            file: url.lastPathComponent,
            mediaType: mediaType.rawValue,
            commandSummary: commandSummary,
            actionSummary: scheduledActions.map(\.summary),
            machineProfile: machineProfile.rawValue,
            driveMode: driveMode.rawValue,
            maxCycles: maxCycles,
            passed: false,
            elapsedCycles: 0,
            reason: reason,
            category: "skipped"
        )
    }
}

private struct MilestoneLoadResult {
    var milestones: [LocalMilestone] = []
    var manifestMilestoneCount: Int? = nil
    var missingMediaFiles: [String] = []
}

private struct ManifestValidationError: Error, CustomStringConvertible, LocalizedError {
    let errors: [String]

    var description: String {
        "Invalid compatibility manifest: " + errors.joined(separator: "; ")
    }

    var errorDescription: String? {
        description
    }
}

private func manifestMilestoneValidationErrors(_ milestones: [LocalMilestone]) -> [String] {
    var errors: [String] = []
    var milestonesByID: [String: LocalMilestone] = [:]
    var milestonesByKey: [MilestoneResultKey: LocalMilestone] = [:]

    for milestone in milestones {
        if let id = milestone.id?.trimmingCharacters(in: .whitespacesAndNewlines),
           !id.isEmpty {
            if let previous = milestonesByID[id] {
                errors.append("duplicate milestone id \(id) for \(previous.url.lastPathComponent) and \(milestone.url.lastPathComponent)")
            } else {
                milestonesByID[id] = milestone
            }
        }

        let key = milestone.resultKey
        if let previous = milestonesByKey[key] {
            errors.append("duplicate milestone key \(milestoneResultKeySummary(key)) for \(previous.url.lastPathComponent) and \(milestone.url.lastPathComponent)")
        } else {
            milestonesByKey[key] = milestone
        }
    }

    return errors
}

private func milestoneResultKeySummary(_ key: MilestoneResultKey) -> String {
    let idText = key.id.map { "id=\($0) " } ?? ""
    return "\(idText)file=\(key.file) profile=\(key.machineProfile) drive=\(key.driveMode) command=\(key.commandSummary)"
}

private struct MilestoneResultRecord: Codable, Equatable {
    static let currentFormatVersion = 10

    let formatVersion: Int?
    let skipped: Bool?
    let runID: String?
    let manifestHash: String?
    let expectedFailureCategory: String?
    let expectedFailureReasonContains: [String]?
    let expectedFailureMatched: Bool?
    let expectedFailureMismatches: [String]?
    let milestoneID: String?
    let milestoneName: String?
    let file: String
    let mediaType: String?
    let commandSummary: String
    let actionSummary: [String]?
    let machineProfile: String
    let driveMode: String
    let maxCycles: Int?
    let passed: Bool
    let elapsedCycles: UInt64
    let reason: String
    let category: String?
    let finalPC: String?
    let finalA: String?
    let finalX: String?
    let finalY: String?
    let finalSP: String?
    let finalP: String?
    let finalIRQLine: Bool?
    let finalNMILine: Bool?
    let finalRDYLine: Bool?
    let finalCPUInstructionCycle: Int?
    let finalVICRasterLine: Int?
    let finalVICRasterCycle: Int?
    let finalDrivePC: String?
    let finalTrack: Int?
    let finalHalfTrack: Int?
    let finalReadTrack: Int?
    let finalReadHalfTrack: Int?
    let finalUsingHalfTrackFallback: Bool?
    let finalByteReadyCount: UInt64?
    let finalVia2PortAReadCount: UInt64?
    let finalWeakBitReadCount: UInt64?
    let finalVariableSpeedZoneSampleCount: UInt64?
    let finalVariableSpeedZoneMask: UInt8?
    let finalLastIECCommandSummary: String?
    let finalDriveNoProgressCycleCount: UInt64?
    let finalFailureReason: String?
    let finalMediaFormat: String?
    let finalMediaPopulatedHalfTrackCount: Int?
    let finalMediaNativeLowLevelTrackCount: Int?
    let finalMediaSyntheticGCRTrackCount: Int?
    let finalMediaHasSyntheticGCR: Bool?
    let finalMediaIsNativeLowLevel: Bool?
    let finalMediaPreservesHalfTracks: Bool?
    let finalMediaPreservesRawTrackLengths: Bool?
    let finalMediaPreservesSpeedZones: Bool?
    let finalMediaPreservesVariableSpeedZones: Bool?
    let finalMediaPreservesSectorErrorInfo: Bool?
    let finalMediaSectorErrorCodeCount: Int?
    let finalMediaNonDefaultSectorErrorCodeCount: Int?
    let finalMediaWeakBitRangeCount: Int?
    let finalMediaWeakBitTotalBitCount: Int?
    let finalMediaVariableSpeedZoneByteCount: Int?
    let finalMediaSupportsWraparoundReads: Bool?
    let finalMediaMaxTrackSize: Int?
    let finalMediaUnsupportedFeatures: [String]?
    let finalMountedTapeName: String?
    let finalTapeDecodeStatus: String?
    let finalTapePulseCount: Int?
    let finalTapeProgramCount: Int?
    let finalTapeBlockCount: Int?
    let finalTapeDecodeFailureReason: String?
    let finalTapeRawPlaybackActive: Bool?
    let finalTapeReadSignalHigh: Bool?
    let finalCassetteSenseLineHigh: Bool?
    let finalCassetteMotorEnabled: Bool?
    let finalTapeHasCapturedWritePulses: Bool?
    let finalCanExportCapturedTAP: Bool?
    let finalTapeHasUnsavedChanges: Bool?
    let finalCanExportSavedT64: Bool?
    let finalScreenText: String?
    let screenRAMHash: String?
    let colorRAMHash: String?
    let screenshotPath: String?

    init(
        formatVersion: Int? = nil,
        skipped: Bool? = nil,
        runID: String? = nil,
        manifestHash: String? = nil,
        expectedFailureCategory: String? = nil,
        expectedFailureReasonContains: [String]? = nil,
        expectedFailureMatched: Bool? = nil,
        expectedFailureMismatches: [String]? = nil,
        milestoneID: String? = nil,
        milestoneName: String? = nil,
        file: String,
        mediaType: String? = nil,
        commandSummary: String,
        actionSummary: [String]? = nil,
        machineProfile: String,
        driveMode: String,
        maxCycles: Int? = nil,
        passed: Bool,
        elapsedCycles: UInt64,
        reason: String,
        category: String? = nil,
        finalPC: String? = nil,
        finalA: String? = nil,
        finalX: String? = nil,
        finalY: String? = nil,
        finalSP: String? = nil,
        finalP: String? = nil,
        finalIRQLine: Bool? = nil,
        finalNMILine: Bool? = nil,
        finalRDYLine: Bool? = nil,
        finalCPUInstructionCycle: Int? = nil,
        finalVICRasterLine: Int? = nil,
        finalVICRasterCycle: Int? = nil,
        finalDrivePC: String? = nil,
        finalTrack: Int? = nil,
        finalHalfTrack: Int? = nil,
        finalReadTrack: Int? = nil,
        finalReadHalfTrack: Int? = nil,
        finalUsingHalfTrackFallback: Bool? = nil,
        finalByteReadyCount: UInt64? = nil,
        finalVia2PortAReadCount: UInt64? = nil,
        finalWeakBitReadCount: UInt64? = nil,
        finalVariableSpeedZoneSampleCount: UInt64? = nil,
        finalVariableSpeedZoneMask: UInt8? = nil,
        finalLastIECCommandSummary: String? = nil,
        finalDriveNoProgressCycleCount: UInt64? = nil,
        finalFailureReason: String? = nil,
        finalMediaFormat: String? = nil,
        finalMediaPopulatedHalfTrackCount: Int? = nil,
        finalMediaNativeLowLevelTrackCount: Int? = nil,
        finalMediaSyntheticGCRTrackCount: Int? = nil,
        finalMediaHasSyntheticGCR: Bool? = nil,
        finalMediaIsNativeLowLevel: Bool? = nil,
        finalMediaPreservesHalfTracks: Bool? = nil,
        finalMediaPreservesRawTrackLengths: Bool? = nil,
        finalMediaPreservesSpeedZones: Bool? = nil,
        finalMediaPreservesVariableSpeedZones: Bool? = nil,
        finalMediaPreservesSectorErrorInfo: Bool? = nil,
        finalMediaSectorErrorCodeCount: Int? = nil,
        finalMediaNonDefaultSectorErrorCodeCount: Int? = nil,
        finalMediaWeakBitRangeCount: Int? = nil,
        finalMediaWeakBitTotalBitCount: Int? = nil,
        finalMediaVariableSpeedZoneByteCount: Int? = nil,
        finalMediaSupportsWraparoundReads: Bool? = nil,
        finalMediaMaxTrackSize: Int? = nil,
        finalMediaUnsupportedFeatures: [String]? = nil,
        finalMountedTapeName: String? = nil,
        finalTapeDecodeStatus: String? = nil,
        finalTapePulseCount: Int? = nil,
        finalTapeProgramCount: Int? = nil,
        finalTapeBlockCount: Int? = nil,
        finalTapeDecodeFailureReason: String? = nil,
        finalTapeRawPlaybackActive: Bool? = nil,
        finalTapeReadSignalHigh: Bool? = nil,
        finalCassetteSenseLineHigh: Bool? = nil,
        finalCassetteMotorEnabled: Bool? = nil,
        finalTapeHasCapturedWritePulses: Bool? = nil,
        finalCanExportCapturedTAP: Bool? = nil,
        finalTapeHasUnsavedChanges: Bool? = nil,
        finalCanExportSavedT64: Bool? = nil,
        finalScreenText: String? = nil,
        screenRAMHash: String? = nil,
        colorRAMHash: String? = nil,
        screenshotPath: String? = nil
    ) {
        self.formatVersion = formatVersion
        self.skipped = skipped
        self.runID = runID
        self.manifestHash = manifestHash
        self.expectedFailureCategory = expectedFailureCategory
        self.expectedFailureReasonContains = expectedFailureReasonContains
        self.expectedFailureMatched = expectedFailureMatched
        self.expectedFailureMismatches = expectedFailureMismatches
        self.milestoneID = milestoneID
        self.milestoneName = milestoneName
        self.file = file
        self.mediaType = mediaType
        self.commandSummary = commandSummary
        self.actionSummary = actionSummary
        self.machineProfile = machineProfile
        self.driveMode = driveMode
        self.maxCycles = maxCycles
        self.passed = passed
        self.elapsedCycles = elapsedCycles
        self.reason = reason
        self.category = category
        self.finalPC = finalPC
        self.finalA = finalA
        self.finalX = finalX
        self.finalY = finalY
        self.finalSP = finalSP
        self.finalP = finalP
        self.finalIRQLine = finalIRQLine
        self.finalNMILine = finalNMILine
        self.finalRDYLine = finalRDYLine
        self.finalCPUInstructionCycle = finalCPUInstructionCycle
        self.finalVICRasterLine = finalVICRasterLine
        self.finalVICRasterCycle = finalVICRasterCycle
        self.finalDrivePC = finalDrivePC
        self.finalTrack = finalTrack
        self.finalHalfTrack = finalHalfTrack
        self.finalReadTrack = finalReadTrack
        self.finalReadHalfTrack = finalReadHalfTrack
        self.finalUsingHalfTrackFallback = finalUsingHalfTrackFallback
        self.finalByteReadyCount = finalByteReadyCount
        self.finalVia2PortAReadCount = finalVia2PortAReadCount
        self.finalWeakBitReadCount = finalWeakBitReadCount
        self.finalVariableSpeedZoneSampleCount = finalVariableSpeedZoneSampleCount
        self.finalVariableSpeedZoneMask = finalVariableSpeedZoneMask
        self.finalLastIECCommandSummary = finalLastIECCommandSummary
        self.finalDriveNoProgressCycleCount = finalDriveNoProgressCycleCount
        self.finalFailureReason = finalFailureReason
        self.finalMediaFormat = finalMediaFormat
        self.finalMediaPopulatedHalfTrackCount = finalMediaPopulatedHalfTrackCount
        self.finalMediaNativeLowLevelTrackCount = finalMediaNativeLowLevelTrackCount
        self.finalMediaSyntheticGCRTrackCount = finalMediaSyntheticGCRTrackCount
        self.finalMediaHasSyntheticGCR = finalMediaHasSyntheticGCR
        self.finalMediaIsNativeLowLevel = finalMediaIsNativeLowLevel
        self.finalMediaPreservesHalfTracks = finalMediaPreservesHalfTracks
        self.finalMediaPreservesRawTrackLengths = finalMediaPreservesRawTrackLengths
        self.finalMediaPreservesSpeedZones = finalMediaPreservesSpeedZones
        self.finalMediaPreservesVariableSpeedZones = finalMediaPreservesVariableSpeedZones
        self.finalMediaPreservesSectorErrorInfo = finalMediaPreservesSectorErrorInfo
        self.finalMediaSectorErrorCodeCount = finalMediaSectorErrorCodeCount
        self.finalMediaNonDefaultSectorErrorCodeCount = finalMediaNonDefaultSectorErrorCodeCount
        self.finalMediaWeakBitRangeCount = finalMediaWeakBitRangeCount
        self.finalMediaWeakBitTotalBitCount = finalMediaWeakBitTotalBitCount
        self.finalMediaVariableSpeedZoneByteCount = finalMediaVariableSpeedZoneByteCount
        self.finalMediaSupportsWraparoundReads = finalMediaSupportsWraparoundReads
        self.finalMediaMaxTrackSize = finalMediaMaxTrackSize
        self.finalMediaUnsupportedFeatures = finalMediaUnsupportedFeatures
        self.finalMountedTapeName = finalMountedTapeName
        self.finalTapeDecodeStatus = finalTapeDecodeStatus
        self.finalTapePulseCount = finalTapePulseCount
        self.finalTapeProgramCount = finalTapeProgramCount
        self.finalTapeBlockCount = finalTapeBlockCount
        self.finalTapeDecodeFailureReason = finalTapeDecodeFailureReason
        self.finalTapeRawPlaybackActive = finalTapeRawPlaybackActive
        self.finalTapeReadSignalHigh = finalTapeReadSignalHigh
        self.finalCassetteSenseLineHigh = finalCassetteSenseLineHigh
        self.finalCassetteMotorEnabled = finalCassetteMotorEnabled
        self.finalTapeHasCapturedWritePulses = finalTapeHasCapturedWritePulses
        self.finalCanExportCapturedTAP = finalCanExportCapturedTAP
        self.finalTapeHasUnsavedChanges = finalTapeHasUnsavedChanges
        self.finalCanExportSavedT64 = finalCanExportSavedT64
        self.finalScreenText = finalScreenText
        self.screenRAMHash = screenRAMHash
        self.colorRAMHash = colorRAMHash
        self.screenshotPath = screenshotPath
    }

    var key: MilestoneResultKey {
        MilestoneResultKey(
            id: milestoneID,
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
    var runnerName: String = "LocalDiskMatrixTests"
    var resultRecordFormatVersion: Int = MilestoneResultRecord.currentFormatVersion
    var runID: String?
    var manifestPath: String?
    var manifestHash: String?
    var resultLogPath: String?
    var screenshotDirectoryPath: String?
    var resumeEnabled: Bool = false
    var strictManifestResumeEnabled: Bool = false
    var screenshotFailuresEnabled: Bool = false
    var milestoneLimit: Int?
    var manifestMilestoneCount: Int?
    var selectedMilestoneCount: Int?
    var missingMediaFiles: [String] = []
    var requireAllManifestMedia: Bool = false
    var failOnUnclassified: Bool = false
    var failOnUnexpected: Bool = false
    var outcome: String?
    var acceptanceFailures: [String]?
    var total: Int = 0
    var executed: Int = 0
    var passed: Int = 0
    var failed: Int = 0
    var skipped: Int = 0
    var expectedFailures: Int = 0
    var unexpectedFailures: Int = 0
    var unclassifiedFailureCount: Int = 0
    var totalElapsedCycles: UInt64 = 0
    var maxElapsedCycles: UInt64 = 0
    var slowestMilestone: MilestoneResultKey?
    var categories: [String: Int] = [:]
    var failedMilestones: [MilestoneResultKey] = []
    var failedMilestoneDetails: [MilestoneFailureSummary] = []
    var expectedFailureDetails: [MilestoneFailureSummary] = []
    var unexpectedFailureDetails: [MilestoneFailureSummary] = []
    var unclassifiedFailureDetails: [MilestoneFailureSummary] = []
    var skippedMilestones: [MilestoneResultKey] = []

    mutating func configureRun(
        runID: String?,
        manifestURL: URL?,
        manifestHash: String?,
        resultLogURL: URL?,
        screenshotDirectoryURL: URL?,
        resumeEnabled: Bool,
        strictManifestResumeEnabled: Bool,
        screenshotFailuresEnabled: Bool,
        milestoneLimit: Int?,
        manifestMilestoneCount: Int?,
        selectedMilestoneCount: Int?,
        missingMediaFiles: [String],
        requireAllManifestMedia: Bool,
        failOnUnclassified: Bool,
        failOnUnexpected: Bool
    ) {
        resultRecordFormatVersion = MilestoneResultRecord.currentFormatVersion
        self.runID = runID
        manifestPath = manifestURL?.path
        self.manifestHash = manifestHash
        resultLogPath = resultLogURL?.path
        screenshotDirectoryPath = screenshotDirectoryURL?.path
        self.resumeEnabled = resumeEnabled
        self.strictManifestResumeEnabled = strictManifestResumeEnabled
        self.screenshotFailuresEnabled = screenshotFailuresEnabled
        self.milestoneLimit = milestoneLimit
        self.manifestMilestoneCount = manifestMilestoneCount
        self.selectedMilestoneCount = selectedMilestoneCount
        self.missingMediaFiles = missingMediaFiles
        self.requireAllManifestMedia = requireAllManifestMedia
        self.failOnUnclassified = failOnUnclassified
        self.failOnUnexpected = failOnUnexpected
    }

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
            let failureSummary = MilestoneFailureSummary(
                key: record.key,
                category: category,
                reason: record.reason,
                elapsedCycles: record.elapsedCycles
            )
            if record.expectedFailureMatched == true {
                expectedFailures += 1
                expectedFailureDetails.append(failureSummary)
            } else {
                unexpectedFailures += 1
                unexpectedFailureDetails.append(failureSummary)
            }
            failedMilestones.append(record.key)
            failedMilestoneDetails.append(failureSummary)
            if record.expectedFailureMatched != true
                && (category == "unknown" || category == MilestoneResultCategory.emulator.rawValue) {
                unclassifiedFailureCount += 1
                unclassifiedFailureDetails.append(failureSummary)
            }
        }
        categories[category, default: 0] += 1
    }

    mutating func recordSkipped(_ milestone: LocalMilestone) {
        total += 1
        skipped += 1
        skippedMilestones.append(milestone.resultKey)
    }

    mutating func refreshDerivedFields() {
        var gateFailures: [String] = []
        if failOnUnclassified && hasUnclassifiedFailures {
            gateFailures.append("unclassifiedFailures")
        }
        if failOnUnexpected && hasUnexpectedFailures {
            gateFailures.append("unexpectedFailures")
        }
        acceptanceFailures = gateFailures

        if !gateFailures.isEmpty {
            outcome = "acceptanceFailed"
        } else if total == 0 {
            outcome = "notRun"
        } else if failed == 0 {
            outcome = "passed"
        } else if unexpectedFailures == 0 {
            outcome = "expectedFailures"
        } else {
            outcome = "unexpectedFailures"
        }
    }

    var consoleSummary: String {
        let categorySummary = categories
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let categoryText = categorySummary.isEmpty ? "none" : categorySummary
        let outcomeText = outcome ?? "unresolved"
        let selectedText = selectedMilestoneCount.map(String.init) ?? "unknown"
        return "Summary total=\(total) selected=\(selectedText) executed=\(executed) passed=\(passed) failed=\(failed) expectedFailures=\(expectedFailures) unexpectedFailures=\(unexpectedFailures) skipped=\(skipped) missingMedia=\(missingMediaFiles.count) unclassified=\(unclassifiedFailureCount) outcome=\(outcomeText) cycles=\(totalElapsedCycles) maxCycles=\(maxElapsedCycles) categories=[\(categoryText)]"
    }

    var hasUnclassifiedFailures: Bool {
        unclassifiedFailureCount > 0
    }

    var hasUnexpectedFailures: Bool {
        unexpectedFailures > 0
    }

    var unclassifiedFailureSummary: String {
        guard hasUnclassifiedFailures else {
            return "No unclassified milestone failures."
        }
        let details = unclassifiedFailureDetails.map { detail in
            let idText = detail.key.id.map { "\($0) " } ?? ""
            return "\(idText)\(detail.key.file) \(detail.key.machineProfile)/\(detail.key.driveMode) command=\(detail.key.commandSummary) category=\(detail.category) cycles=\(detail.elapsedCycles) reason=\(detail.reason)"
        }
        return "Unclassified milestone failures (\(unclassifiedFailureCount)):\n" + details.joined(separator: "\n")
    }

    var unexpectedFailureSummary: String {
        guard hasUnexpectedFailures else {
            return "No unexpected milestone failures."
        }
        let details = unexpectedFailureDetails.map { detail in
            let idText = detail.key.id.map { "\($0) " } ?? ""
            return "\(idText)\(detail.key.file) \(detail.key.machineProfile)/\(detail.key.driveMode) command=\(detail.key.commandSummary) category=\(detail.category) cycles=\(detail.elapsedCycles) reason=\(detail.reason)"
        }
        return "Unexpected milestone failures (\(unexpectedFailures)):\n" + details.joined(separator: "\n")
    }
}

private struct MilestoneResultKey: Codable, Hashable {
    let id: String?
    let file: String
    let commandSummary: String
    let machineProfile: String
    let driveMode: String
}
