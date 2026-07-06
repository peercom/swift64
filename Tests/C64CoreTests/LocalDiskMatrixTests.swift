import Foundation
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
    private let milestonePhaseFilterEnv = "SWIFT64_LOCAL_MILESTONE_PHASES"
    private let milestoneIDFilterEnv = "SWIFT64_LOCAL_MILESTONE_IDS"
    private let milestoneMediaLimitEnv = "SWIFT64_LOCAL_MILESTONE_MEDIA_LIMIT"
    private let milestoneShardIndexEnv = "SWIFT64_LOCAL_MILESTONE_SHARD_INDEX"
    private let milestoneShardCountEnv = "SWIFT64_LOCAL_MILESTONE_SHARD_COUNT"
    private let milestoneRequirePhaseFilterMatchesEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_PHASES"
    private let milestoneRequireIDFilterMatchesEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_IDS_MATCH"
    private let milestoneRequireManifestEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_MANIFEST"
    private let milestoneRequireRoadmapPhasesEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_ROADMAP_PHASES"
    private let milestoneRequireIDsEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_IDS"
    private let milestoneRequireExpectedFailureNotesEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_EXPECTED_FAILURE_NOTES"
    private let milestoneRequireExpectedFailureReasonsEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_EXPECTED_FAILURE_REASONS"
    private let milestoneRequireMaxCyclesEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_MAX_CYCLES"
    private let milestoneRequireExplicitActionsEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_ACTIONS"
    private let milestoneRequireObservableExpectationsEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_OBSERVABLES"
    private let milestoneRequirePhase3VICProofsEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_PHASE3_VIC_PROOFS"
    private let milestoneRequireFramebufferScreenshotsEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_FRAMEBUFFER_SCREENSHOTS"
    private let milestoneRejectPlaceholderProofHashesEnv = "SWIFT64_LOCAL_MILESTONE_REJECT_PLACEHOLDER_PROOF_HASHES"
    private let milestoneRequireMediaTypesEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_MEDIA_TYPES"
    private let milestoneRequireMachineProfilesEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_MACHINE_PROFILES"
    private let milestoneRequireDriveModesEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_DRIVE_MODES"
    private let milestoneRequireSIDModelsEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_SID_MODELS"
    private let milestoneRequireSIDAccuracyModesEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_SID_ACCURACY_MODES"
    private let milestoneRequireObservableTypesEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_OBSERVABLE_TYPES"
    private let milestoneRequireVICProofsEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_VIC_PROOFS"
    private let milestoneRequireFailureCategoriesEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_FAILURE_CATEGORIES"
    private let milestoneRequireActionTypesEnv = "SWIFT64_LOCAL_MILESTONE_REQUIRE_ACTION_TYPES"
    private let milestoneUsefulFeatureGateEnv = "SWIFT64_LOCAL_MILESTONE_USEFUL_FEATURE_GATE"
    private let milestoneFailOnUnclassifiedEnv = "SWIFT64_LOCAL_MILESTONE_FAIL_ON_UNCLASSIFIED"
    private let milestoneFailOnUnexpectedEnv = "SWIFT64_LOCAL_MILESTONE_FAIL_ON_UNEXPECTED"
    private let milestoneFailPhasesEnv = "SWIFT64_LOCAL_MILESTONE_FAIL_PHASES"
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
            isNativeLowLevel: true,
            duplicateSectorHeaderCount: 1
        )
        let capabilities = DiskImage(format: .g64, tracks: tracks, maxTrackSize: 2).capabilities

        XCTAssertTrue(mediaStatusMismatches(
            CompatibilityMediaStatus(
                preservesWeakBitRanges: true,
                weakBitRangeCount: 2,
                weakBitTotalBitCount: 12,
                hasDuplicateSectorHeaders: true,
                duplicateSectorHeaderCount: 1,
                variableSpeedZoneByteCount: 2
            ),
            capabilities: capabilities
        ).isEmpty)

        let mismatches = mediaStatusMismatches(
            CompatibilityMediaStatus(
                preservesWeakBitRanges: false,
                weakBitRangeCount: 1,
                weakBitTotalBitCount: 16,
                hasDuplicateSectorHeaders: false,
                duplicateSectorHeaderCount: 2,
                variableSpeedZoneByteCount: 4
            ),
            capabilities: capabilities
        )

        XCTAssertTrue(mismatches.contains("media.weakBitRangeCount 2 != 1"))
        XCTAssertTrue(mismatches.contains("media.weakBitTotalBitCount 12 != 16"))
        XCTAssertTrue(mismatches.contains("media.hasDuplicateSectorHeaders true != false"))
        XCTAssertTrue(mismatches.contains("media.duplicateSectorHeaderCount 1 != 2"))
        XCTAssertTrue(mismatches.contains("media.variableSpeedZoneByteCount 2 != 4"))
        XCTAssertTrue(mismatches.contains("media.preservesWeakBitRanges true != false"))
    }

    func testLowLevelTrackMismatchReportsProtectedTrackProof() {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [0xAA, 0x55, 0x00],
            speedZone: 2,
            speedZoneMap: [0, 1, 2],
            weakBitRanges: [
                DiskImage.Track.WeakBitRange(startBit: 0, endBit: 3),
            ],
            isNativeLowLevel: true
        )
        let drive = Drive1541()
        XCTAssertTrue(drive.insertDiskImage(DiskImage(format: .g64, tracks: tracks, maxTrackSize: 3)))

        XCTAssertTrue(lowLevelTrackMismatches([
            CompatibilityLowLevelTrackExpectation(
                halfTrack: 34,
                byteCount: 3,
                bitLength: 24,
                speedZone: 2,
                bytesHash: CompatibilityHash.fnv1a64([0xAA, 0x55, 0x00]),
                speedZoneMapHash: CompatibilityHash.fnv1a64([0, 1, 2]),
                weakBitRangeCount: 1
            )
        ], disk: drive.disk).isEmpty)

        let mismatches = lowLevelTrackMismatches([
            CompatibilityLowLevelTrackExpectation(
                halfTrack: 34,
                byteCount: 2,
                bitLength: 23,
                speedZone: 3,
                bytesHash: "0000000000000000",
                speedZoneMapHash: "1111111111111111",
                weakBitRangeCount: 2
            ),
            CompatibilityLowLevelTrackExpectation(halfTrack: 35, byteCount: 1)
        ], disk: drive.disk)

        XCTAssertTrue(mismatches.contains("media.lowLevelTrack[34].byteCount 3 != 2"))
        XCTAssertTrue(mismatches.contains("media.lowLevelTrack[34].bitLength 24 != 23"))
        XCTAssertTrue(mismatches.contains("media.lowLevelTrack[34].speedZone 2 != 3"))
        XCTAssertTrue(mismatches.contains { $0.hasPrefix("media.lowLevelTrack[34].bytesHash ") })
        XCTAssertTrue(mismatches.contains { $0.hasPrefix("media.lowLevelTrack[34].speedZoneMapHash ") })
        XCTAssertTrue(mismatches.contains("media.lowLevelTrack[34].weakBitRangeCount 1 != 2"))
        XCTAssertTrue(mismatches.contains("media.lowLevelTrack[35] missing"))
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

    func testMilestoneClassifierUsesPreservationSubsystemCategories() {
        XCTAssertEqual(
            MilestoneResultCategory.classify(passed: false, reason: "SID audio RMS mismatch"),
            .sid
        )
        XCTAssertEqual(
            MilestoneResultCategory.classify(passed: false, reason: "sid.voice[0].frequency $0000 != $1234"),
            .sid
        )
        XCTAssertEqual(
            MilestoneResultCategory.classify(passed: false, reason: "VIC $D011 $00 != $3B"),
            .vic
        )
        XCTAssertEqual(
            MilestoneResultCategory.classify(passed: false, reason: "raster IRQ line drift"),
            .vic
        )
    }

    func testMilestoneRoadmapPhaseRollupMapsCategories() {
        XCTAssertEqual(MilestoneRoadmapPhase.gateablePhases, [
            MilestoneRoadmapPhase.phase2CPUMemoryBus,
            MilestoneRoadmapPhase.phase3VICII,
            MilestoneRoadmapPhase.phase4DriveMedia,
            MilestoneRoadmapPhase.phase5SID,
            MilestoneRoadmapPhase.phase6CIAInputTape,
            MilestoneRoadmapPhase.phase7CartridgeExpansion,
            MilestoneRoadmapPhase.phase8AppDistribution,
        ])
        XCTAssertEqual(
            MilestoneRoadmapPhase.phaseName(forCategory: MilestoneResultCategory.pass.rawValue),
            MilestoneRoadmapPhase.passed
        )
        XCTAssertEqual(
            MilestoneRoadmapPhase.phaseName(forCategory: MilestoneResultCategory.pc.rawValue),
            MilestoneRoadmapPhase.phase2CPUMemoryBus
        )
        XCTAssertEqual(
            MilestoneRoadmapPhase.phaseName(forCategory: MilestoneResultCategory.vic.rawValue),
            MilestoneRoadmapPhase.phase3VICII
        )
        XCTAssertEqual(
            MilestoneRoadmapPhase.phaseName(forCategory: MilestoneResultCategory.video.rawValue),
            MilestoneRoadmapPhase.phase3VICII
        )
        XCTAssertEqual(
            MilestoneRoadmapPhase.phaseName(forCategory: MilestoneResultCategory.protectedMedia.rawValue),
            MilestoneRoadmapPhase.phase4DriveMedia
        )
        XCTAssertEqual(
            MilestoneRoadmapPhase.phaseName(forCategory: MilestoneResultCategory.sid.rawValue),
            MilestoneRoadmapPhase.phase5SID
        )
        XCTAssertEqual(
            MilestoneRoadmapPhase.phaseName(forCategory: MilestoneResultCategory.audio.rawValue),
            MilestoneRoadmapPhase.phase5SID
        )
        XCTAssertEqual(
            MilestoneRoadmapPhase.phaseName(forCategory: MilestoneResultCategory.tape.rawValue),
            MilestoneRoadmapPhase.phase6CIAInputTape
        )
        XCTAssertEqual(
            MilestoneRoadmapPhase.phaseName(forCategory: MilestoneResultCategory.cartridge.rawValue),
            MilestoneRoadmapPhase.phase7CartridgeExpansion
        )
        XCTAssertEqual(
            MilestoneRoadmapPhase.phaseName(forCategory: MilestoneResultCategory.app.rawValue),
            MilestoneRoadmapPhase.phase8AppDistribution
        )
        XCTAssertEqual(
            MilestoneRoadmapPhase.phaseName(forCategory: MilestoneResultCategory.timeout.rawValue),
            MilestoneRoadmapPhase.unclassified
        )
    }

    func testMilestoneFailurePhaseSelectionDeduplicatesAndReportsInvalidNames() {
        let selection = Self.parseMilestonePhaseSelection(
            " phase4DriveMedia, phase5SID, phase4DriveMedia, phase5SIDD, , phase3VICII, phase5SIDD "
        )

        XCTAssertEqual(selection.valid, [
            MilestoneRoadmapPhase.phase4DriveMedia,
            MilestoneRoadmapPhase.phase5SID,
            MilestoneRoadmapPhase.phase3VICII,
        ])
        XCTAssertEqual(selection.invalid, [
            "phase5SIDD",
        ])
    }

    func testMilestoneUsefulFeatureGateDefaultsMergeWithExplicitSelections() {
        let selection = Self.usefulFeatureGateSelection(
            explicitPhases: (valid: [MilestoneRoadmapPhase.phase3VICII], invalid: ["phase9"]),
            explicitMediaTypes: (valid: [CompatibilityMediaType.t64.rawValue], invalid: ["wav"]),
            explicitMachineProfiles: (valid: [CompatibilityMachineProfile.ntscC64.rawValue], invalid: ["c128"]),
            explicitDriveModes: (valid: [CompatibilityDriveMode.fastLoad.rawValue], invalid: ["turbo"]),
            explicitSIDModels: (valid: [SID.Model.mos8580.rawValue], invalid: ["mos6582"]),
            explicitSIDAccuracyModes: (valid: [SID.AccuracyMode.fast.rawValue], invalid: ["resid"]),
            explicitObservableTypes: (valid: [MilestoneObservableType.cia], invalid: ["raster"]),
            explicitFailureCategories: (valid: [CompatibilityFailureCategory.app.rawValue], invalid: ["video"]),
            explicitActionTypes: (valid: [MilestoneActionType.stopTape], invalid: ["mouseDown"]),
            enabled: true
        )

        XCTAssertEqual(selection.phases.valid, [
            MilestoneRoadmapPhase.phase3VICII,
            MilestoneRoadmapPhase.phase4DriveMedia,
            MilestoneRoadmapPhase.phase5SID,
            MilestoneRoadmapPhase.phase6CIAInputTape,
            MilestoneRoadmapPhase.phase7CartridgeExpansion,
        ])
        XCTAssertEqual(selection.phases.invalid, ["phase9"])
        XCTAssertEqual(selection.mediaTypes.valid, [
            CompatibilityMediaType.t64.rawValue,
            CompatibilityMediaType.prg.rawValue,
            CompatibilityMediaType.d64.rawValue,
            CompatibilityMediaType.g64.rawValue,
            CompatibilityMediaType.tap.rawValue,
            CompatibilityMediaType.crt.rawValue,
        ])
        XCTAssertEqual(selection.mediaTypes.invalid, ["wav"])
        XCTAssertEqual(selection.machineProfiles.valid, [
            CompatibilityMachineProfile.ntscC64.rawValue,
            CompatibilityMachineProfile.palC64.rawValue,
            CompatibilityMachineProfile.palC64C.rawValue,
            CompatibilityMachineProfile.ntscC64C.rawValue,
        ])
        XCTAssertEqual(selection.machineProfiles.invalid, ["c128"])
        XCTAssertEqual(selection.driveModes.valid, [
            CompatibilityDriveMode.fastLoad.rawValue,
            CompatibilityDriveMode.compat1541.rawValue,
            CompatibilityDriveMode.standard1541.rawValue,
        ])
        XCTAssertEqual(selection.driveModes.invalid, ["turbo"])
        XCTAssertEqual(selection.sidModels.valid, [
            SID.Model.mos8580.rawValue,
            SID.Model.mos6581.rawValue,
        ])
        XCTAssertEqual(selection.sidModels.invalid, ["mos6582"])
        XCTAssertEqual(selection.sidAccuracyModes.valid, [
            SID.AccuracyMode.fast.rawValue,
            SID.AccuracyMode.compatibility.rawValue,
        ])
        XCTAssertEqual(selection.sidAccuracyModes.invalid, ["resid"])
        XCTAssertEqual(selection.observableTypes.valid, [
            MilestoneObservableType.cia,
            MilestoneObservableType.pc,
            MilestoneObservableType.drive,
            MilestoneObservableType.media,
            MilestoneObservableType.sid,
            MilestoneObservableType.vic,
            MilestoneObservableType.tape,
            MilestoneObservableType.screen,
            MilestoneObservableType.framebuffer,
        ])
        XCTAssertEqual(selection.observableTypes.invalid, ["raster"])
        XCTAssertEqual(selection.failureCategories.valid, [
            CompatibilityFailureCategory.app.rawValue,
            CompatibilityFailureCategory.drive.rawValue,
            CompatibilityFailureCategory.protectedMedia.rawValue,
            CompatibilityFailureCategory.sid.rawValue,
            CompatibilityFailureCategory.vic.rawValue,
            CompatibilityFailureCategory.tape.rawValue,
            CompatibilityFailureCategory.cartridge.rawValue,
        ])
        XCTAssertEqual(selection.failureCategories.invalid, ["video"])
        XCTAssertEqual(selection.actionTypes.valid, [
            MilestoneActionType.stopTape,
            MilestoneActionType.typeText,
            MilestoneActionType.waitCycles,
            MilestoneActionType.joystickDown,
            MilestoneActionType.joystickUp,
            MilestoneActionType.keyDown,
            MilestoneActionType.keyUp,
            MilestoneActionType.startTape,
        ])
        XCTAssertEqual(selection.actionTypes.invalid, ["mouseDown"])

        let disabled = Self.usefulFeatureGateSelection(
            explicitPhases: (valid: [MilestoneRoadmapPhase.phase3VICII], invalid: []),
            explicitMediaTypes: (valid: [], invalid: []),
            explicitMachineProfiles: (valid: [], invalid: []),
            explicitDriveModes: (valid: [], invalid: []),
            explicitSIDModels: (valid: [], invalid: []),
            explicitSIDAccuracyModes: (valid: [], invalid: []),
            explicitObservableTypes: (valid: [], invalid: []),
            explicitFailureCategories: (valid: [], invalid: []),
            explicitActionTypes: (valid: [], invalid: []),
            enabled: false
        )
        XCTAssertEqual(disabled.phases.valid, [MilestoneRoadmapPhase.phase3VICII])
        XCTAssertTrue(disabled.mediaTypes.valid.isEmpty)
    }

    func testMilestoneIDSelectionTrimsAndDeduplicatesNames() {
        let selection = Self.parseMilestoneIDSelection(
            " giana-title, sid-filter, giana-title, , vic-proof, sid-filter "
        )

        XCTAssertEqual(selection, [
            "giana-title",
            "sid-filter",
            "vic-proof",
        ])
    }

    func testMilestoneShardSelectionParsesZeroBasedShard() {
        let selection = Self.parseMilestoneShardSelection(indexValue: " 1 ", countValue: " 3 ")

        XCTAssertEqual(selection.index, 1)
        XCTAssertEqual(selection.count, 3)
        XCTAssertNil(selection.invalidReason)
        XCTAssertTrue(selection.isActive)

        let disabled = Self.parseMilestoneShardSelection(indexValue: nil, countValue: nil)
        XCTAssertNil(disabled.index)
        XCTAssertNil(disabled.count)
        XCTAssertFalse(disabled.isActive)

        let invalid = Self.parseMilestoneShardSelection(indexValue: "3", countValue: "3")
        XCTAssertEqual(invalid.index, 3)
        XCTAssertEqual(invalid.count, 3)
        XCTAssertEqual(invalid.invalidReason, "invalidShard:index=3,count=3")
    }

    func testMilestoneRequiredMediaSelectionDeduplicatesAndReportsInvalidNames() {
        let selection = Self.parseMilestoneMediaTypeSelection(
            " prg, g64, d64, prg, tap, wav, , crt, wav "
        )

        XCTAssertEqual(selection.valid, [
            CompatibilityMediaType.prg.rawValue,
            CompatibilityMediaType.g64.rawValue,
            CompatibilityMediaType.d64.rawValue,
            CompatibilityMediaType.tap.rawValue,
            CompatibilityMediaType.crt.rawValue,
        ])
        XCTAssertEqual(selection.invalid, [
            "wav",
        ])
    }

    func testMilestoneRequiredMachineProfileSelectionDeduplicatesAndReportsInvalidNames() {
        let selection = Self.parseMilestoneMachineProfileSelection(
            " palC64, ntscC64, palC64C, palC64, c128, , ntscC64C, c128 "
        )

        XCTAssertEqual(selection.valid, [
            CompatibilityMachineProfile.palC64.rawValue,
            CompatibilityMachineProfile.ntscC64.rawValue,
            CompatibilityMachineProfile.palC64C.rawValue,
            CompatibilityMachineProfile.ntscC64C.rawValue,
        ])
        XCTAssertEqual(selection.invalid, [
            "c128",
        ])
    }

    func testMilestoneRequiredDriveModeSelectionDeduplicatesAndReportsInvalidNames() {
        let selection = Self.parseMilestoneDriveModeSelection(
            " compat1541, standard1541, fastLoad, compat1541, turbo, , standard1541, turbo "
        )

        XCTAssertEqual(selection.valid, [
            CompatibilityDriveMode.compat1541.rawValue,
            CompatibilityDriveMode.standard1541.rawValue,
            CompatibilityDriveMode.fastLoad.rawValue,
        ])
        XCTAssertEqual(selection.invalid, [
            "turbo",
        ])
    }

    func testMilestoneRequiredSIDModelSelectionDeduplicatesAndReportsInvalidNames() {
        let selection = Self.parseMilestoneSIDModelSelection(
            " mos6581, mos8580, mos6581, mos6582, , mos8580, mos6582 "
        )

        XCTAssertEqual(selection.valid, [
            SID.Model.mos6581.rawValue,
            SID.Model.mos8580.rawValue,
        ])
        XCTAssertEqual(selection.invalid, [
            "mos6582",
        ])
    }

    func testMilestoneRequiredSIDAccuracyModeSelectionDeduplicatesAndReportsInvalidNames() {
        let selection = Self.parseMilestoneSIDAccuracyModeSelection(
            " fast, compatibility, fast, resid, , compatibility, resid "
        )

        XCTAssertEqual(selection.valid, [
            SID.AccuracyMode.fast.rawValue,
            SID.AccuracyMode.compatibility.rawValue,
        ])
        XCTAssertEqual(selection.invalid, [
            "resid",
        ])
    }

    func testMilestoneRequiredObservableTypeSelectionDeduplicatesAndReportsInvalidNames() {
        let selection = Self.parseMilestoneObservableTypeSelection(
            " sid, vic, drive, sid, raster, , framebuffer, raster "
        )

        XCTAssertEqual(selection.valid, [
            MilestoneObservableType.sid,
            MilestoneObservableType.vic,
            MilestoneObservableType.drive,
            MilestoneObservableType.framebuffer,
        ])
        XCTAssertEqual(selection.invalid, [
            "raster",
        ])
    }

    func testMilestoneRequiredVICProofSelectionDeduplicatesAndReportsInvalidNames() {
        let selection = Self.parseMilestoneVICProofSelection(
            " raster, bus, state, raster, spriteCrunch, , framebuffer, spriteCrunch "
        )

        XCTAssertEqual(selection.valid, [
            MilestoneVICProofType.raster,
            MilestoneVICProofType.bus,
            MilestoneVICProofType.state,
            MilestoneVICProofType.framebuffer,
        ])
        XCTAssertEqual(selection.invalid, [
            "spriteCrunch",
        ])
    }

    func testMilestoneRequiredFailureCategorySelectionDeduplicatesAndReportsInvalidNames() {
        let selection = Self.parseMilestoneFailureCategorySelection(
            " sid, vic, protectedMedia, sid, video, , cartridge, video "
        )

        XCTAssertEqual(selection.valid, [
            CompatibilityFailureCategory.sid.rawValue,
            CompatibilityFailureCategory.vic.rawValue,
            CompatibilityFailureCategory.protectedMedia.rawValue,
            CompatibilityFailureCategory.cartridge.rawValue,
        ])
        XCTAssertEqual(selection.invalid, [
            "video",
        ])
    }

    func testMilestoneRequiredActionTypeSelectionDeduplicatesAndReportsInvalidNames() {
        let selection = Self.parseMilestoneActionTypeSelection(
            " typeText, waitCycles, joystickDown, typeText, mouseDown, , startTape, mouseDown "
        )

        XCTAssertEqual(selection.valid, [
            MilestoneActionType.typeText,
            MilestoneActionType.waitCycles,
            MilestoneActionType.joystickDown,
            MilestoneActionType.startTape,
        ])
        XCTAssertEqual(selection.invalid, [
            "mouseDown",
        ])
    }

    func testManifestMilestonePhaseFilterKeepsOnlyExplicitSelectedPhases() throws {
        let manifestJSON = """
        {
          "milestones": [
            {
              "id": "drive",
              "file": "drive.g64",
              "media": "g64",
              "roadmapPhase": "phase4DriveMedia",
              "commands": ["LOAD\\"*\\",8,1"]
            },
            {
              "id": "sid",
              "file": "sid.prg",
              "media": "prg",
              "roadmapPhase": "phase5SID",
              "commands": ["LOAD\\"*\\",8,1"]
            },
            {
              "id": "legacy",
              "file": "legacy.d64",
              "media": "d64",
              "commands": ["LOAD\\"$\\",8"]
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))

        XCTAssertEqual(
            Self.phaseFilteredManifestEntries(
                manifest.milestones,
                selectedPhaseNames: [MilestoneRoadmapPhase.phase5SID]
            ).map(\.id),
            ["sid"]
        )
        XCTAssertEqual(
            Self.phaseFilteredManifestEntries(
                manifest.milestones,
                selectedPhaseNames: []
            ).map(\.id),
            ["drive", "sid", "legacy"]
        )
        let selected = Self.phaseFilteredManifestEntries(
            manifest.milestones,
            selectedPhaseNames: [
                MilestoneRoadmapPhase.phase5SID,
                MilestoneRoadmapPhase.phase6CIAInputTape,
            ]
        )
        let counts = Self.phaseCounts(
            for: selected,
            selectedPhaseNames: [
                MilestoneRoadmapPhase.phase5SID,
                MilestoneRoadmapPhase.phase6CIAInputTape,
            ]
        )
        XCTAssertEqual(counts[MilestoneRoadmapPhase.phase5SID], 1)
        XCTAssertEqual(counts[MilestoneRoadmapPhase.phase6CIAInputTape], 0)
        XCTAssertEqual(Self.phaseCounts(for: manifest.milestones)[MilestoneRoadmapPhase.phase4DriveMedia], 1)
        XCTAssertEqual(Self.phaseCounts(for: manifest.milestones)[MilestoneRoadmapPhase.phase5SID], 1)
        XCTAssertEqual(Self.untaggedPhaseCount(in: manifest.milestones), 1)
        XCTAssertEqual(Self.unnamedMilestoneCount(in: manifest.milestones), 0)
    }

    func testManifestMilestoneIDFilterKeepsOnlyExplicitSelectedIDs() throws {
        let manifestJSON = """
        {
          "milestones": [
            {
              "id": "drive",
              "file": "drive.g64",
              "media": "g64",
              "commands": ["LOAD\\"*\\",8,1"]
            },
            {
              "id": "sid",
              "file": "sid.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"]
            },
            {
              "id": "   ",
              "file": "blank.d64",
              "media": "d64",
              "commands": ["LOAD\\"$\\",8"]
            },
            {
              "file": "missing-id.tap",
              "media": "tap",
              "commands": ["LOAD"]
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))

        XCTAssertEqual(
            Self.idFilteredManifestEntries(
                manifest.milestones,
                selectedIDs: ["sid", "missing", "drive"]
            ).map(\.id),
            ["drive", "sid"]
        )
        XCTAssertEqual(
            Self.idFilteredManifestEntries(
                manifest.milestones,
                selectedIDs: []
            ).map(\.file),
            ["drive.g64", "sid.prg", "blank.d64", "missing-id.tap"]
        )
        XCTAssertEqual(
            Self.shardedManifestEntries(
                manifest.milestones,
                shardSelection: MilestoneShardSelection(index: 1, count: 2)
            ).map(\.file),
            ["sid.prg", "missing-id.tap"]
        )
        XCTAssertEqual(
            Self.shardedManifestEntries(
                manifest.milestones,
                shardSelection: MilestoneShardSelection(index: 0, count: 1)
            ).map(\.file),
            ["drive.g64", "sid.prg", "blank.d64", "missing-id.tap"]
        )
    }

    func testManifestMilestoneIDCoverageCountsMissingAndBlankIDs() throws {
        let manifestJSON = """
        {
          "milestones": [
            {
              "id": "named",
              "file": "named.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"]
            },
            {
              "id": "   ",
              "file": "blank-id.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"]
            },
            {
              "file": "missing-id.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"]
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))

        XCTAssertEqual(Self.unnamedMilestoneCount(in: manifest.milestones), 2)
    }

    func testManifestExpectedFailureCoverageCountsMissingAndBlankNotes() throws {
        let manifestJSON = """
        {
          "milestones": [
            {
              "id": "explained",
              "file": "explained.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "expectedFailure": {
                "category": "sid",
                "note": "Needs measured filter curve"
              }
            },
            {
              "id": "blank",
              "file": "blank.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "expectedFailure": {
                "category": "vic",
                "note": "   "
              }
            },
            {
              "id": "missing",
              "file": "missing.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "expectedFailure": {
                "category": "drive"
              }
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))

        XCTAssertEqual(Self.expectedFailureCount(in: manifest.milestones), 3)
        XCTAssertEqual(Self.expectedFailuresWithoutNotesCount(in: manifest.milestones), 2)
    }

    func testManifestExpectedFailureCoverageCountsMissingAndBlankReasonMarkers() throws {
        let manifestJSON = """
        {
          "milestones": [
            {
              "id": "specific",
              "file": "specific.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "expectedFailure": {
                "category": "drive",
                "reasonContains": ["GCR reads"]
              }
            },
            {
              "id": "blank",
              "file": "blank.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "expectedFailure": {
                "category": "vic",
                "reasonContains": ["   "]
              }
            },
            {
              "id": "missing",
              "file": "missing.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "expectedFailure": {
                "category": "sid"
              }
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))

        XCTAssertEqual(Self.expectedFailureCount(in: manifest.milestones), 3)
        XCTAssertEqual(Self.expectedFailuresWithoutReasonMarkersCount(in: manifest.milestones), 2)
    }

    func testManifestMilestoneMaxCycleCoverageCountsMissingBudgets() throws {
        let manifestJSON = """
        {
          "milestones": [
            {
              "id": "bounded",
              "file": "bounded.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "maxCycles": 1200000
            },
            {
              "id": "implicit",
              "file": "implicit.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"]
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))

        XCTAssertEqual(Self.milestonesWithoutMaxCyclesCount(in: manifest.milestones), 1)
    }

    func testManifestExplicitActionCoverageCountsLegacyCommandMilestones() throws {
        let manifestJSON = """
        {
          "milestones": [
            {
              "id": "scripted",
              "file": "scripted.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "actions": [
                { "type": "text", "text": "LOAD\\"*\\",8,1" },
                { "type": "wait", "cycles": 1200000 }
              ]
            },
            {
              "id": "legacy-command",
              "file": "legacy-command.prg",
              "media": "prg",
              "command": "LOAD\\"*\\",8,1"
            },
            {
              "id": "legacy-commands",
              "file": "legacy-commands.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1", "RUN"]
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))

        XCTAssertEqual(Self.milestonesWithoutExplicitActionsCount(in: manifest.milestones), 2)
    }

    func testManifestObservableExpectationCoverageCountsScriptOnlyMilestones() throws {
        let manifestJSON = """
        {
          "milestones": [
            {
              "id": "pc-proof",
              "file": "pc-proof.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "pcRanges": [
                { "start": 2049, "end": 2303 }
              ]
            },
            {
              "id": "screen-proof",
              "file": "screen-proof.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "screenTextContains": ["READY."]
            },
            {
              "id": "script-only",
              "file": "script-only.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "maxCycles": 1200000,
              "screenshotName": "not-proof"
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))

        XCTAssertEqual(Self.milestonesWithoutObservableExpectationsCount(in: manifest.milestones), 1)
    }

    func testManifestPhase3VICProofCoverageCountsOnlyPhase3MilestonesWithoutVICProof() throws {
        let manifestJSON = """
        {
          "milestones": [
            {
              "id": "phase3-raster-proof",
              "file": "phase3-raster-proof.prg",
              "media": "prg",
              "roadmapPhase": "phase3VICII",
              "commands": ["LOAD\\"*\\",8,1"],
              "vicRasterLine": 64
            },
            {
              "id": "phase3-framebuffer-proof",
              "file": "phase3-framebuffer-proof.prg",
              "media": "prg",
              "roadmapPhase": "phase3VICII",
              "commands": ["LOAD\\"*\\",8,1"],
              "framebufferHash": "0011223344556677"
            },
            {
              "id": "phase3-no-vic-proof",
              "file": "phase3-no-vic-proof.prg",
              "media": "prg",
              "roadmapPhase": "phase3VICII",
              "commands": ["LOAD\\"*\\",8,1"],
              "screenTextContains": ["READY."]
            },
            {
              "id": "phase4-no-vic-proof",
              "file": "phase4-no-vic-proof.g64",
              "media": "g64",
              "roadmapPhase": "phase4DriveMedia",
              "commands": ["LOAD\\"*\\",8,1"],
              "driveStatus": { "minGCRReads": 1 }
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))

        XCTAssertEqual(Self.phase3MilestonesWithoutVICProofCount(in: manifest.milestones), 1)
    }

    func testManifestPhase3VICProofCoverageCountsMissingRequiredProofSet() throws {
        let manifestJSON = """
        {
          "milestones": [
            {
              "id": "phase3-register-only",
              "file": "phase3-register-only.prg",
              "media": "prg",
              "roadmapPhase": "phase3VICII",
              "actions": [{ "type": "waitCycles", "cycles": 1 }],
              "vicRegisters": [
                { "register": 53265, "value": 27 }
              ]
            },
            {
              "id": "phase3-complete-proof",
              "file": "phase3-complete-proof.prg",
              "media": "prg",
              "roadmapPhase": "phase3VICII",
              "actions": [{ "type": "waitCycles", "cycles": 1 }],
              "vicRegisters": [
                { "register": 53265, "value": 27 }
              ],
              "vicState": {
                "displayActive": false
              },
              "vicRasterLine": 64,
              "vicBusOwner": "cpu",
              "vicLowPhaseMemoryReads": [],
              "framebufferHash": "0011223344556677"
            },
            {
              "id": "phase4-register-only",
              "file": "phase4-register-only.g64",
              "media": "g64",
              "roadmapPhase": "phase4DriveMedia",
              "actions": [{ "type": "waitCycles", "cycles": 1 }],
              "vicRegisters": [
                { "register": 53265, "value": 27 }
              ]
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))

        XCTAssertEqual(Self.phase3MilestonesWithoutVICProofCount(in: manifest.milestones), 0)
        XCTAssertEqual(Self.phase3MilestonesMissingRequiredVICProofsCount(in: manifest.milestones), 1)
    }

    func testManifestPhase3VICProofCoverageCanSatisfyAllProofSurfaces() throws {
        let manifestJSON = """
        {
          "milestones": [
            {
              "id": "phase3-complete-proof",
              "file": "phase3-complete-proof.prg",
              "media": "prg",
              "roadmapPhase": "phase3VICII",
              "actions": [{ "type": "waitCycles", "cycles": 1 }],
              "vicRegisters": [
                { "register": 53265, "value": 27 }
              ],
              "vicState": {
                "displayActive": false
              },
              "vicRasterLine": 64,
              "vicBusOwner": "cpu",
              "vicLowPhaseMemoryReads": [],
              "framebufferHash": "0011223344556677"
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))

        XCTAssertEqual(Self.phase3MilestonesWithoutVICProofCount(in: manifest.milestones), 0)
        XCTAssertEqual(Self.phase3MilestonesMissingRequiredVICProofsCount(in: manifest.milestones), 0)
        XCTAssertEqual(Self.vicProofCounts(for: manifest.milestones), [
            MilestoneVICProofType.registers: 1,
            MilestoneVICProofType.state: 1,
            MilestoneVICProofType.raster: 1,
            MilestoneVICProofType.bus: 1,
            MilestoneVICProofType.memoryTrace: 1,
            MilestoneVICProofType.framebuffer: 1,
        ])
    }

    func testPhase3VICExampleManifestSatisfiesStrictProofBundle() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("C64/DISKS/compatibility.phase3-vic.example.json")
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(contentsOf: manifestURL))

        XCTAssertEqual(manifest.milestones.count, 3)
        XCTAssertEqual(Self.phase3MilestonesWithoutVICProofCount(in: manifest.milestones), 0)
        XCTAssertEqual(Self.phase3MilestonesMissingRequiredVICProofsCount(in: manifest.milestones), 0)

        let proofCounts = Self.vicProofCounts(for: manifest.milestones)
        for proofType in MilestoneVICProofType.requiredPhase3Proofs {
            XCTAssertEqual(proofCounts[proofType], 3, "Expected all Phase 3 demo milestones to include \(proofType)")
        }
    }

    func testManifestPlaceholderProofHashCoverageCountsUncalibratedDigests() throws {
        let manifestJSON = """
        {
          "milestones": [
            {
              "id": "template-proof",
              "file": "template-proof.prg",
              "media": "prg",
              "actions": [{ "type": "waitCycles", "cycles": 1 }],
              "vicRegisterSnapshotHash": "0000000000000000",
              "screenRAMHash": "0000000000000000",
              "colorRAMHash": "0000000000000000",
              "framebufferHash": "0000000000000000"
            },
            {
              "id": "calibrated-proof",
              "file": "calibrated-proof.prg",
              "media": "prg",
              "actions": [{ "type": "waitCycles", "cycles": 1 }],
              "vicRegisterSnapshotHash": "0011223344556677",
              "screenRAMHash": "1122334455667788",
              "colorRAMHash": "2233445566778899",
              "framebufferHash": "33445566778899AA"
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))

        XCTAssertEqual(Self.placeholderProofHashCount(in: manifest.milestones), 4)
    }

    func testManifestFramebufferProofCoverageCountsMissingAndBlankScreenshotNames() throws {
        let manifestJSON = """
        {
          "milestones": [
            {
              "id": "named-framebuffer",
              "file": "named-framebuffer.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "framebufferHash": "0011223344556677",
              "screenshotName": "title-proof"
            },
            {
              "id": "missing-screenshot",
              "file": "missing-screenshot.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "framebufferHash": "1122334455667788"
            },
            {
              "id": "blank-screenshot",
              "file": "blank-screenshot.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "framebufferHash": "2233445566778899",
              "screenshotName": "   "
            },
            {
              "id": "screen-ram-only",
              "file": "screen-ram-only.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "screenRAMHash": "33445566778899AA"
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))

        XCTAssertEqual(Self.framebufferHashMilestonesWithoutScreenshotNamesCount(in: manifest.milestones), 2)
    }

    func testManifestFramebufferScreenshotCoverageCountsSanitizedFilenameCollisions() throws {
        let manifestJSON = """
        {
          "milestones": [
            {
              "id": "first-title",
              "file": "first-title.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "framebufferHash": "0011223344556677",
              "screenshotName": "../title screen"
            },
            {
              "id": "second-title",
              "file": "second-title.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "framebufferHash": "1122334455667788",
              "screenshotName": "title/screen"
            },
            {
              "id": "failed-title",
              "file": "failed-title.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "framebufferHash": "2233445566778899",
              "screenshotName": "title screen-failed"
            },
            {
              "id": "unique-title",
              "file": "unique-title.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "framebufferHash": "33445566778899AA",
              "screenshotName": "unique-title"
            },
            {
              "id": "blank-title",
              "file": "blank-title.prg",
              "media": "prg",
              "commands": ["LOAD\\"*\\",8,1"],
              "framebufferHash": "445566778899AABB",
              "screenshotName": " "
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))

        XCTAssertEqual(Self.framebufferScreenshotFilenameCollisions(in: manifest.milestones), ["title_screen.ppm"])
        XCTAssertEqual(Self.framebufferScreenshotFilenameCollisionCount(in: manifest.milestones), 1)
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
            let lowLevelMounted: Bool
            switch ext {
            case "g64":
                lowLevelMounted = gcrDisk.loadG64(data)
            case "nib":
                lowLevelMounted = gcrDisk.loadNIB(data)
            case "nbz":
                lowLevelMounted = gcrDisk.loadNBZ(data)
            case "p64":
                lowLevelMounted = gcrDisk.loadP64(data)
            default:
                lowLevelMounted = gcrDisk.loadD64(data)
            }
            summaries.append("\(url.lastPathComponent): lowLevel=\(lowLevelMounted) native=\(gcrDisk.hasNativeLowLevelImage) halftracks=\(gcrDisk.image?.capabilities.populatedHalfTrackCount ?? 0)")
            XCTAssertTrue(lowLevelMounted, matrixSummary("Low-level media load failed", url: url, gcrDisk: gcrDisk))
            XCTAssertTrue(gcrDisk.hasDisk, matrixSummary("GCR disk should expose at least one track", url: url, gcrDisk: gcrDisk))

            if ext == "g64" || ext == "nib" || ext == "nbz" || ext == "p64" {
                XCTAssertTrue(gcrDisk.hasNativeLowLevelImage, matrixSummary("Native disk images should be preserved as low-level media", url: url, gcrDisk: gcrDisk))
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

        let resultLogURL = milestoneResultLogURL()
        let manifestHash = activeMilestoneManifestHash()
        let screenshotDirectoryURL = milestoneScreenshotDirectoryURL()
        let screenshotFailuresEnabled = shouldWriteFailedMilestoneScreenshots
        let summaryURL = milestoneSummaryURL()
        let runID = milestoneRunID()
        let requiredMediaTypeSelection = milestoneRequiredMediaTypeSelection
        let requiredMachineProfileSelection = milestoneRequiredMachineProfileSelection
        let requiredDriveModeSelection = milestoneRequiredDriveModeSelection
        let requiredSIDModelSelection = milestoneRequiredSIDModelSelection
        let requiredSIDAccuracyModeSelection = milestoneRequiredSIDAccuracyModeSelection
        let requiredObservableTypeSelection = milestoneRequiredObservableTypeSelection
        let requiredVICProofSelection = milestoneRequiredVICProofSelection
        let requiredFailureCategorySelection = milestoneRequiredFailureCategorySelection
        let requiredActionTypeSelection = milestoneRequiredActionTypeSelection

        let milestoneLoad: MilestoneLoadResult
        do {
            milestoneLoad = try localMilestoneLoadResult()
        } catch let error as ManifestValidationError {
            var validationSummary = MilestoneRunSummary()
            validationSummary.configureRun(
                runID: runID,
                manifestURL: activeMilestoneManifestURL(),
                manifestHash: manifestHash,
                resultLogURL: resultLogURL,
                screenshotDirectoryURL: screenshotDirectoryURL,
                resumeEnabled: shouldResumeMilestoneResults,
                strictManifestResumeEnabled: shouldResumeOnlyMatchingManifest,
                screenshotFailuresEnabled: screenshotFailuresEnabled,
                milestoneLimit: localMilestoneLimit,
                manifestValidationErrors: error.errors,
                manifestMilestoneCount: nil,
                selectedMilestoneCount: 0,
                missingMediaFiles: [],
                requireAllManifestMedia: shouldRequireAllMilestoneMedia,
                requiredManifestMediaTypes: requiredMediaTypeSelection.valid,
                invalidRequiredManifestMediaTypes: requiredMediaTypeSelection.invalid,
                requiredManifestMachineProfiles: requiredMachineProfileSelection.valid,
                invalidRequiredManifestMachineProfiles: requiredMachineProfileSelection.invalid,
                requiredManifestDriveModes: requiredDriveModeSelection.valid,
                invalidRequiredManifestDriveModes: requiredDriveModeSelection.invalid,
                requiredManifestSIDModels: requiredSIDModelSelection.valid,
                invalidRequiredManifestSIDModels: requiredSIDModelSelection.invalid,
                requiredManifestSIDAccuracyModes: requiredSIDAccuracyModeSelection.valid,
                invalidRequiredManifestSIDAccuracyModes: requiredSIDAccuracyModeSelection.invalid,
                requiredManifestObservableTypes: requiredObservableTypeSelection.valid,
                invalidRequiredManifestObservableTypes: requiredObservableTypeSelection.invalid,
                requiredManifestVICProofs: requiredVICProofSelection.valid,
                invalidRequiredManifestVICProofs: requiredVICProofSelection.invalid,
                requiredManifestFailureCategories: requiredFailureCategorySelection.valid,
                invalidRequiredManifestFailureCategories: requiredFailureCategorySelection.invalid,
                requiredManifestActionTypes: requiredActionTypeSelection.valid,
                invalidRequiredManifestActionTypes: requiredActionTypeSelection.invalid,
                requireManifest: shouldRequireMilestoneManifest,
                requireTaggedManifestPhases: shouldRequireRoadmapPhasesForManifestMilestones,
                requireManifestMilestoneIDs: shouldRequireIDsForManifestMilestones,
                requireExpectedFailureNotes: shouldRequireExpectedFailureNotesForManifestMilestones,
                requireExpectedFailureReasonMarkers: shouldRequireExpectedFailureReasonsForManifestMilestones,
                requireExplicitMaxCycles: shouldRequireMaxCyclesForManifestMilestones,
                requireExplicitActions: shouldRequireExplicitActionsForManifestMilestones,
                requireObservableExpectations: shouldRequireObservableExpectationsForManifestMilestones,
                requirePhase3VICProofs: shouldRequirePhase3VICProofsForManifestMilestones,
                requireFramebufferScreenshots: shouldRequireFramebufferScreenshotsForManifestMilestones,
                rejectPlaceholderProofHashes: shouldRejectPlaceholderProofHashesForManifestMilestones,
                failOnUnclassified: shouldFailOnUnclassifiedMilestoneFailures,
                failOnUnexpected: shouldFailOnUnexpectedMilestoneFailures,
                failPhaseNames: milestoneFailurePhaseSelection.valid,
                invalidFailPhaseNames: milestoneFailurePhaseSelection.invalid
            )
            validationSummary.refreshDerivedFields()
            try writeMilestoneRunSummary(validationSummary, to: summaryURL)
            throw error
        }
        let milestones = milestoneLoad.milestones
        guard !milestones.isEmpty else {
            throw XCTSkip("No local milestone disks found under C64/DISKS")
        }

        let passedMilestones = shouldResumeMilestoneResults
            ? try passedMilestoneKeys(
                from: resultLogURL,
                matchingManifestHash: shouldResumeOnlyMatchingManifest ? manifestHash : nil
            )
            : []
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
            milestoneShardIndex: milestoneLoad.milestoneShardIndex,
            milestoneShardCount: milestoneLoad.milestoneShardCount,
            preShardMilestoneCount: milestoneLoad.preShardMilestoneCount,
            postShardMilestoneCount: milestoneLoad.postShardMilestoneCount,
            invalidShardConfiguration: milestoneLoad.invalidShardConfiguration,
            manifestMilestoneCount: milestoneLoad.manifestMilestoneCount,
            manifestPhaseCounts: milestoneLoad.manifestPhaseCounts,
            manifestMediaCounts: milestoneLoad.manifestMediaCounts,
            manifestMachineProfileCounts: milestoneLoad.manifestMachineProfileCounts,
            manifestDriveModeCounts: milestoneLoad.manifestDriveModeCounts,
            manifestSIDModelCounts: milestoneLoad.manifestSIDModelCounts,
            manifestSIDAccuracyModeCounts: milestoneLoad.manifestSIDAccuracyModeCounts,
            manifestObservableTypeCounts: milestoneLoad.manifestObservableTypeCounts,
            manifestVICProofCounts: milestoneLoad.manifestVICProofCounts,
            manifestExpectedFailureCategoryCounts: milestoneLoad.manifestExpectedFailureCategoryCounts,
            manifestActionTypeCounts: milestoneLoad.manifestActionTypeCounts,
            manifestUntaggedMilestoneCount: milestoneLoad.manifestUntaggedMilestoneCount,
            manifestUnnamedMilestoneCount: milestoneLoad.manifestUnnamedMilestoneCount,
            manifestExpectedFailureCount: milestoneLoad.manifestExpectedFailureCount,
            manifestExpectedFailuresWithoutNotesCount: milestoneLoad.manifestExpectedFailuresWithoutNotesCount,
            manifestExpectedFailuresWithoutReasonMarkersCount: milestoneLoad.manifestExpectedFailuresWithoutReasonMarkersCount,
            manifestMilestonesWithoutMaxCyclesCount: milestoneLoad.manifestMilestonesWithoutMaxCyclesCount,
            manifestMilestonesWithoutExplicitActionsCount: milestoneLoad.manifestMilestonesWithoutExplicitActionsCount,
            manifestMilestonesWithoutObservableExpectationsCount: milestoneLoad.manifestMilestonesWithoutObservableExpectationsCount,
            manifestPhase3MilestonesWithoutVICProofCount: milestoneLoad.manifestPhase3MilestonesWithoutVICProofCount,
            manifestPhase3MilestonesMissingRequiredVICProofsCount: milestoneLoad.manifestPhase3MilestonesMissingRequiredVICProofsCount,
            manifestFramebufferHashMilestonesWithoutScreenshotNamesCount: milestoneLoad.manifestFramebufferHashMilestonesWithoutScreenshotNamesCount,
            manifestFramebufferScreenshotFilenameCollisionCount: milestoneLoad.manifestFramebufferScreenshotFilenameCollisionCount,
            manifestPlaceholderProofHashCount: milestoneLoad.manifestPlaceholderProofHashCount,
            phaseFilteredMilestoneCount: milestoneLoad.phaseFilteredMilestoneCount,
            selectedMilestoneCount: milestones.count,
            selectedMilestoneKeys: milestones.map(\.resultKey),
            selectedMediaCounts: milestoneLoad.selectedMediaCounts,
            selectedMachineProfileCounts: milestoneLoad.selectedMachineProfileCounts,
            selectedDriveModeCounts: milestoneLoad.selectedDriveModeCounts,
            selectedSIDModelCounts: milestoneLoad.selectedSIDModelCounts,
            selectedSIDAccuracyModeCounts: milestoneLoad.selectedSIDAccuracyModeCounts,
            selectedObservableTypeCounts: milestoneLoad.selectedObservableTypeCounts,
            selectedVICProofCounts: milestoneLoad.selectedVICProofCounts,
            selectedExpectedFailureCategoryCounts: milestoneLoad.selectedExpectedFailureCategoryCounts,
            selectedActionTypeCounts: milestoneLoad.selectedActionTypeCounts,
            missingMediaFiles: milestoneLoad.missingMediaFiles,
            requireAllManifestMedia: shouldRequireAllMilestoneMedia,
            requiredManifestMediaTypes: requiredMediaTypeSelection.valid,
            invalidRequiredManifestMediaTypes: requiredMediaTypeSelection.invalid,
            requiredManifestMachineProfiles: requiredMachineProfileSelection.valid,
            invalidRequiredManifestMachineProfiles: requiredMachineProfileSelection.invalid,
            requiredManifestDriveModes: requiredDriveModeSelection.valid,
            invalidRequiredManifestDriveModes: requiredDriveModeSelection.invalid,
            requiredManifestSIDModels: requiredSIDModelSelection.valid,
            invalidRequiredManifestSIDModels: requiredSIDModelSelection.invalid,
            requiredManifestSIDAccuracyModes: requiredSIDAccuracyModeSelection.valid,
            invalidRequiredManifestSIDAccuracyModes: requiredSIDAccuracyModeSelection.invalid,
            requiredManifestObservableTypes: requiredObservableTypeSelection.valid,
            invalidRequiredManifestObservableTypes: requiredObservableTypeSelection.invalid,
            requiredManifestVICProofs: requiredVICProofSelection.valid,
            invalidRequiredManifestVICProofs: requiredVICProofSelection.invalid,
            requiredManifestFailureCategories: requiredFailureCategorySelection.valid,
            invalidRequiredManifestFailureCategories: requiredFailureCategorySelection.invalid,
            requiredManifestActionTypes: requiredActionTypeSelection.valid,
            invalidRequiredManifestActionTypes: requiredActionTypeSelection.invalid,
            selectedPhaseNames: milestoneLoad.selectedPhaseNames,
            invalidSelectedPhaseNames: milestoneLoad.invalidSelectedPhaseNames,
            selectedPhaseCounts: milestoneLoad.selectedPhaseCounts,
            missingSelectedPhaseNames: milestoneLoad.missingSelectedPhaseNames,
            selectedMilestoneIDs: milestoneLoad.selectedMilestoneIDs,
            missingSelectedMilestoneIDs: milestoneLoad.missingSelectedMilestoneIDs,
            requireSelectedPhases: shouldRequireSelectedMilestonePhases,
            requireSelectedMilestoneIDs: shouldRequireSelectedMilestoneIDs,
            requireManifest: shouldRequireMilestoneManifest,
            requireTaggedManifestPhases: shouldRequireRoadmapPhasesForManifestMilestones,
            requireManifestMilestoneIDs: shouldRequireIDsForManifestMilestones,
            requireExpectedFailureNotes: shouldRequireExpectedFailureNotesForManifestMilestones,
            requireExpectedFailureReasonMarkers: shouldRequireExpectedFailureReasonsForManifestMilestones,
            requireExplicitMaxCycles: shouldRequireMaxCyclesForManifestMilestones,
            requireExplicitActions: shouldRequireExplicitActionsForManifestMilestones,
            requireObservableExpectations: shouldRequireObservableExpectationsForManifestMilestones,
            requirePhase3VICProofs: shouldRequirePhase3VICProofsForManifestMilestones,
            requireFramebufferScreenshots: shouldRequireFramebufferScreenshotsForManifestMilestones,
            rejectPlaceholderProofHashes: shouldRejectPlaceholderProofHashesForManifestMilestones,
            failOnUnclassified: shouldFailOnUnclassifiedMilestoneFailures,
            failOnUnexpected: shouldFailOnUnexpectedMilestoneFailures,
            failPhaseNames: milestoneFailurePhaseSelection.valid,
            invalidFailPhaseNames: milestoneFailurePhaseSelection.invalid
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
            c64.sidModelOverride = milestone.sidModel
            c64.sid.accuracyMode = milestone.sidAccuracyMode ?? .fast
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
        XCTAssertTrue(runSummary.phaseAcceptanceFailures.isEmpty, runSummary.phaseAcceptanceFailureSummary)
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
        applyLocalSIDOverrides(to: c64)
        XCTAssertTrue(c64.mountDisk(giana), "Failed to mount \(giana.path)")
        c64.powerOn()

        for _ in 0..<20 {
            XCTAssertTrue(c64.runFrame())
        }

        let baseline = c64.drive1541.statusSnapshot
        c64.typeText(gianaRunCommand(env: "SWIFT64_LOCAL_GIANA_RUN_COMMAND"))

        let maxCycles = Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_RUN_MAX_CYCLES"] ?? "") ?? 8_000_000
        let stopOnScreenChange = ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_CONTINUE_AFTER_SCREEN_CHANGE"] == nil
        let pressSpaceOnScreenChange = ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_PRESS_SPACE_ON_SCREEN_CHANGE"] == "1"
        let spaceDelayCycles = Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_SPACE_DELAY_CYCLES"] ?? "") ?? 0
        let spaceHoldCycles = Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_SPACE_HOLD_CYCLES"] ?? "") ?? 30_000
        let spaceTargetPC = parseOptionalUInt16Environment("SWIFT64_LOCAL_GIANA_PRESS_SPACE_AT_PC")
        let spaceTargetMinCycle = Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_PRESS_SPACE_AT_PC_MIN_CYCLES"] ?? "") ?? 0
        let wavCaptureURL = optionalFileURLEnvironment("SWIFT64_LOCAL_GIANA_WAV_CAPTURE")
        let wavCaptureSeconds = boundedDoubleEnvironment(
            "SWIFT64_LOCAL_GIANA_WAV_CAPTURE_SECONDS",
            defaultValue: 8,
            range: 0.1...30
        )
        let wavCaptureMaxSamples = max(1, Int((wavCaptureSeconds * SID.sampleRate).rounded()))
        let wavCaptureStartChipWrites = max(
            0,
            Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_WAV_CAPTURE_AFTER_CHIP_WRITES"] ?? "") ?? 3
        )
        let wavCaptureStartMode = ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_WAV_CAPTURE_START"] ?? "voice-output"
        let stopAfterWavCapture = ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_STOP_AFTER_WAV_CAPTURE"] == "1"
        let sidTraceURL = optionalFileURLEnvironment("SWIFT64_LOCAL_GIANA_SID_TRACE_JSONL")
        let sidTraceLimit = max(
            1,
            Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_SID_TRACE_LIMIT"] ?? "") ?? 50_000
        )
        let sidTraceIncludesRAMWindow = ProcessInfo.processInfo.environment["SWIFT64_LOCAL_GIANA_SID_TRACE_INCLUDE_RAM"] == "1"
        var sidTraceEvents: [SIDRegisterWriteTraceEvent] = []
        var sidTraceDroppedEvents = 0
        var wavSamples: [Float] = []
        var wavCaptureStarted = false
        var wavCaptureComplete = false
        if wavCaptureURL != nil {
            wavSamples.reserveCapacity(wavCaptureMaxSamples)
            c64.sid.onSampleGenerated = { sample in
                guard wavCaptureStarted && !wavCaptureComplete else { return }
                if wavSamples.count < wavCaptureMaxSamples {
                    wavSamples.append(sample)
                }
                if wavSamples.count >= wavCaptureMaxSamples {
                    wavCaptureComplete = true
                }
            }
        }
        if sidTraceURL != nil {
            sidTraceEvents.reserveCapacity(min(sidTraceLimit, 50_000))
            c64.onSIDRegisterWriteTrace = { event in
                guard event.reachedChip || sidTraceIncludesRAMWindow else { return }
                guard sidTraceEvents.count < sidTraceLimit else {
                    sidTraceDroppedEvents += 1
                    return
                }
                sidTraceEvents.append(event)
            }
        }
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
        var secondScreenSpacePressed = false
        var spacePressCycle: Int?
        var spaceReleaseCycle: Int?
        var spacePressReason = "none"
        defer {
            c64.sid.onSampleGenerated = nil
            c64.onSIDRegisterWriteTrace = nil
            if secondScreenSpacePressed {
                CompatibilityKey.space.release(on: c64)
            }
        }

        for cycle in 0..<maxCycles {
            if let pressCycle = spacePressCycle, cycle >= pressCycle {
                CompatibilityKey.space.press(on: c64)
                secondScreenSpacePressed = true
                spacePressCycle = nil
                spaceReleaseCycle = cycle + max(1, spaceHoldCycles)
            }
            if let releaseCycle = spaceReleaseCycle, cycle >= releaseCycle {
                CompatibilityKey.space.release(on: c64)
                spaceReleaseCycle = nil
            }
            if wavCaptureURL != nil,
               !wavCaptureStarted,
               shouldStartGianaWAVCapture(
                   c64,
                   minimumChipWrites: wavCaptureStartChipWrites,
                   mode: wavCaptureStartMode
               ) {
                wavCaptureStarted = true
            }
            if wavCaptureComplete && stopAfterWavCapture {
                break
            }

            c64.tickOneCycle()
            if wavCaptureURL != nil,
               !wavCaptureStarted,
               shouldStartGianaWAVCapture(
                   c64,
                   minimumChipWrites: wavCaptureStartChipWrites,
                   mode: wavCaptureStartMode
               ) {
                wavCaptureStarted = true
            }
            if wavCaptureComplete && stopAfterWavCapture {
                break
            }
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
            if let spaceTargetPC,
               !secondScreenSpacePressed,
               spacePressCycle == nil,
               cycle >= spaceTargetMinCycle,
               c64.cpu.pc == spaceTargetPC {
                spacePressReason = "pc=$\(String(format: "%04X", spaceTargetPC))"
                spacePressCycle = cycle
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
                    if pressSpaceOnScreenChange &&
                        spaceTargetPC == nil &&
                        !secondScreenSpacePressed &&
                        spacePressCycle == nil {
                        spacePressReason = "screen-change"
                        spacePressCycle = cycle + max(0, spaceDelayCycles)
                    }
                    if stopOnScreenChange && !pressSpaceOnScreenChange {
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
        let wavCaptureSummary: String
        if let wavCaptureURL {
            if !wavSamples.isEmpty {
                try writeMono16BitWAV(samples: wavSamples, sampleRate: Int(SID.sampleRate), to: wavCaptureURL)
            }
            wavCaptureSummary = "wavCapture=\(wavCaptureURL.path),samples=\(wavSamples.count),started=\(wavCaptureStarted),complete=\(wavCaptureComplete)"
        } else {
            wavCaptureSummary = "wavCapture=disabled"
        }
        let sidTraceSummary: String
        if let sidTraceURL {
            try writeSIDTraceJSONL(sidTraceEvents, to: sidTraceURL)
            sidTraceSummary = "sidTrace=\(sidTraceURL.path),events=\(sidTraceEvents.count),dropped=\(sidTraceDroppedEvents),includeRAM=\(sidTraceIncludesRAMWindow)"
        } else {
            sidTraceSummary = "sidTrace=disabled"
        }
        let summary = "Giana run smoke loaded=\(loaded) enteredProgramCode=\(enteredProgramCode) screenChangedAfterLoad=\(screenChangedAfterLoad) secondScreenSpacePressed=\(secondScreenSpacePressed) spaceReason=\(spacePressReason) cycles=\(c64.cpu.totalCycles) pc=$\(pc) pcBytes=\(pcBytes) vic=\(vicSummary(c64)) sid=\(sidRunSummary(c64)) \(wavCaptureSummary) \(sidTraceSummary) code0A80=\(cpuBytes(c64, at: 0x0A80, count: 72)) kernalHits=\(kernalHitSummary(kernalPCRangeHits)) sameKernalPC=\(sameKernalPCCycles) \(bootFileSummary(c64)) trap=\(loadTrapSummary(c64)) firstLoad=[\(lowLoadSnapshot ?? "none")] fFile=\(diskFileSummary(c64, name: "F")) cc00=\(cpuBytes(c64, at: 0xCC00, count: 16)) nameByte=$\(String(format: "%02X", c64.memory.ram[0x02E2])) drivePC=$\(drivePC) loadEnd=$\(loadEnd) byteReady=\(drive.byteReadyCount - baseline.byteReadyCount) paReads=\(drive.via2PortAReadCount - baseline.via2PortAReadCount) reason=\(failureReason ?? c64.emulationStatus.lastFailureReason ?? "none")"
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
        applyLocalSIDOverrides(to: c64)
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

    private func parseOptionalUInt16Environment(_ name: String) -> UInt16? {
        guard let rawValue = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }
        let parsed: Int?
        if rawValue.lowercased().hasPrefix("0x") {
            parsed = Int(rawValue.dropFirst(2), radix: 16)
        } else if rawValue.hasPrefix("$") {
            parsed = Int(rawValue.dropFirst(), radix: 16)
        } else {
            parsed = Int(rawValue)
        }
        guard let parsed, parsed >= 0 && parsed <= 0xFFFF else { return nil }
        return UInt16(parsed)
    }

    private func applyLocalSIDOverrides(to c64: C64) {
        let environment = ProcessInfo.processInfo.environment
        if let modelValue = environment["SWIFT64_LOCAL_GIANA_SID_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !modelValue.isEmpty,
           let model = SID.Model(rawValue: modelValue) {
            c64.sid.model = model
        }
        if let accuracyValue = environment["SWIFT64_LOCAL_GIANA_SID_ACCURACY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accuracyValue.isEmpty,
           let accuracyMode = SID.AccuracyMode(rawValue: accuracyValue) {
            c64.sid.accuracyMode = accuracyMode
        }
    }

    private func optionalFileURLEnvironment(_ name: String) -> URL? {
        guard let rawValue = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: rawValue)
    }

    private func boundedDoubleEnvironment(
        _ name: String,
        defaultValue: Double,
        range: ClosedRange<Double>
    ) -> Double {
        let value = Double(ProcessInfo.processInfo.environment[name] ?? "") ?? defaultValue
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func writeMono16BitWAV(samples: [Float], sampleRate: Int, to url: URL) throws {
        let outputSamples = acCoupledAudioSamples(samples)
        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36 + outputSamples.count * 2))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * 2))
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(UInt32(outputSamples.count * 2))
        for sample in outputSamples {
            let clamped = min(max(sample, -1), 1)
            data.appendLittleEndian(Int16((clamped * Float(Int16.max)).rounded()))
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func writeSIDTraceJSONL(_ events: [SIDRegisterWriteTraceEvent], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data()
        for event in events {
            data.append(try encoder.encode(event))
            data.append(0x0A)
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func acCoupledAudioSamples(_ samples: [Float]) -> [Float] {
        let pole: Float = 0.995
        var lastInput: Float = 0
        var lastOutput: Float = 0
        return samples.map { sample in
            let output = sample - lastInput + pole * lastOutput
            lastInput = sample
            lastOutput = output
            return min(max(output, -0.95), 0.95)
        }
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

    private func sidRunSummary(_ c64: C64) -> String {
        let state = c64.sid.debugAudioState()
        return "chipWrites=\(c64.sidChipWriteCount),chipRegs=\(sidRegisterHistogram(c64.sidChipRegisterWriteCounts)),ramWindowWrites=\(c64.sidRAMWindowWriteCount),ramRegs=\(sidRegisterHistogram(c64.sidRAMWindowRegisterWriteCounts)),$D418=\(String(format: "%02X", c64.sid.debugRegisterValue(0x18))),mixed=\(state.mixedOutput),direct=\(state.directOutput),filterIn=\(state.filterInput),filterOut=\(state.filterOutput),voices=\(sidVoiceSummary(c64.sid.debugVoiceStates()))"
    }

    private func sidRegisterHistogram(_ counts: [UInt64]) -> String {
        let pairs = counts.enumerated().compactMap { index, count -> String? in
            guard count > 0 else { return nil }
            return "$D4\(String(format: "%02X", index)):\(count)"
        }
        return pairs.isEmpty ? "none" : pairs.joined(separator: "|")
    }

    private func sidVoiceSummary(_ voices: [SID.VoiceDebugState]) -> String {
        voices.enumerated().map { index, voice in
            "v\(index + 1){f=\(String(format: "%04X", voice.frequency)),pw=\(String(format: "%03X", voice.pulseWidth)),ctrl=\(String(format: "%02X", voice.control)),ad=\(String(format: "%02X", voice.attackDecay)),sr=\(String(format: "%02X", voice.sustainRelease)),env=\(String(format: "%02X", voice.envelopeLevel)),gate=\(voice.gate ? 1 : 0),wf=\(voice.hasWaveform ? 1 : 0),out=\(voice.waveformOutput),state=\(voice.envelopeState)}"
        }.joined(separator: "|")
    }

    private func shouldStartGianaWAVCapture(
        _ c64: C64,
        minimumChipWrites: Int,
        mode: String
    ) -> Bool {
        guard c64.sidChipWriteCount >= UInt64(minimumChipWrites) else { return false }
        switch mode {
        case "chip-writes":
            return true
        default:
            let state = c64.sid.debugAudioState()
            return state.directOutput != 0 || state.filterInput != 0 || state.filterOutput != 0
        }
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
        var milestone = LocalMilestone(
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
                minGCRWrites: 1,
                minGCRWriteSplices: 1,
                minGCRWriteEraseBits: 1,
                requiredVariableSpeedZones: [0, 4],
                lastWeakBitHalfTrack: 36,
                lastWeakBitPosition: 12,
                lastWeakBitPositionStart: 10,
                lastWeakBitPositionEnd: 20,
                lastVariableSpeedZoneHalfTrack: 36,
                lastVariableSpeedZoneByteIndex: 4,
                lastVariableSpeedZone: 3,
                track: 17,
                headBitPosition: 123,
                gcrWriteModeActive: true,
                gcrWriteGateActive: true,
                hasDisk: true
            ),
            mediaStatus: CompatibilityMediaStatus(isNativeLowLevel: true),
            ramSignatures: [CompatibilityRAMSignature(address: 0x0801, bytes: [0x01, 0x08])],
            colorRAMSignatures: [CompatibilityRAMSignature(address: 0, bytes: [0x01, 0x02])],
            screenRAMHash: "0000000000000000",
            colorRAMHash: "1111111111111111",
            screenshotName: nil
        )
        milestone.lowLevelTracks = [
            CompatibilityLowLevelTrackExpectation(halfTrack: 34, byteCount: 1)
        ]

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
        XCTAssertTrue(reason.contains("drive.minGCRWrites 0 < 1"))
        XCTAssertTrue(reason.contains("drive.minGCRWriteSplices 0 < 1"))
        XCTAssertTrue(reason.contains("drive.minGCRWriteEraseBits 0 < 1"))
        XCTAssertTrue(reason.contains("drive.requiredVariableSpeedZones missing 0"))
        XCTAssertTrue(reason.contains("drive.requiredVariableSpeedZones invalid 4"))
        XCTAssertTrue(reason.contains("drive.lastWeakBitHalfTrack"))
        XCTAssertTrue(reason.contains("drive.lastWeakBitPosition"))
        XCTAssertTrue(reason.contains("drive.lastWeakBitPosition nil < 10"))
        XCTAssertTrue(reason.contains("drive.lastVariableSpeedZoneHalfTrack"))
        XCTAssertTrue(reason.contains("drive.lastVariableSpeedZoneByteIndex"))
        XCTAssertTrue(reason.contains("drive.lastVariableSpeedZone"))
        XCTAssertTrue(reason.contains("drive.track"))
        XCTAssertTrue(reason.contains("drive.headBitPosition"))
        XCTAssertTrue(reason.contains("drive.gcrWriteModeActive"))
        XCTAssertTrue(reason.contains("drive.gcrWriteGateActive"))
        XCTAssertTrue(reason.contains("drive.hasDisk"))
        XCTAssertTrue(reason.contains("media capabilities unavailable"))
        XCTAssertTrue(reason.contains("media.lowLevelTrack[34] missing"))
        XCTAssertTrue(reason.contains("RAM $0801"))
        XCTAssertTrue(reason.contains("color RAM $0000"))
        XCTAssertTrue(reason.contains("screen hash"))
        XCTAssertTrue(reason.contains("color RAM hash"))
        XCTAssertTrue(reason.contains("timeout state pc=$"))
        XCTAssertTrue(reason.contains("drivePC=$"))
        XCTAssertTrue(reason.contains("track="))
        XCTAssertTrue(reason.contains("headBit="))
        XCTAssertTrue(reason.contains("readHalf="))
        XCTAssertTrue(reason.contains("byteReady="))
        XCTAssertTrue(reason.contains("paReads="))
        XCTAssertTrue(reason.contains("gcrWrites="))
        XCTAssertTrue(reason.contains("gcrWriteMode="))
        XCTAssertTrue(reason.contains("gcrWriteGate="))
        XCTAssertTrue(reason.contains("gcrSplices="))
        XCTAssertTrue(reason.contains("gcrEraseBits="))
        XCTAssertTrue(reason.contains("writeProtected="))
        XCTAssertTrue(reason.contains("mediaChanged="))
        XCTAssertTrue(reason.contains("mediaChangeCount="))
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
        milestone.roadmapPhase = MilestoneRoadmapPhase.phase5SID
        milestone.sidAudioSignature = CompatibilitySIDAudioSignature(sampleCount: 3)
        milestone.lowLevelTracks = [
            CompatibilityLowLevelTrackExpectation(halfTrack: 34)
        ]
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
        tapeC64.sid.accuracyMode = .compatibility
        tapeC64.sid.writeRegister(0x04, value: 0x21)
        tapeC64.sid.writeRegister(0x18, value: 0x8F)
        tapeC64.sid.sampleBuffer[0] = -0.5
        tapeC64.sid.sampleBuffer[1] = 0.25
        tapeC64.sid.sampleBuffer[2] = 0.75
        tapeC64.sid.sampleWritePos = 3
        tapeC64.sid.audioAccumulator = 12.5
        tapeC64.sid.audioAccumulatorCount = 2
        tapeC64.sid.audioOutputState = 34.5
        tapeC64.sid.lastDirectOutput = -1024
        tapeC64.sid.lastFilterInput = 2048
        tapeC64.sid.lastFilterOutput = 512
        tapeC64.sid.lastMixedOutput = 1536
        tapeC64.sid.setExternalAudioInput(12_000)
        tapeC64.sid.writeRegister(0x15, value: 0x07)
        tapeC64.sid.writeRegister(0x16, value: 0xFF)
        tapeC64.sid.writeRegister(0x17, value: 0xF0)
        tapeC64.sid.writeRegister(0x18, value: 0x8F)
        tapeC64.sid.filterLow = 1.25
        tapeC64.sid.filterBand = -2.5
        tapeC64.sid.filterHigh = 3.75
        tapeC64.sid.voices[0].frequency = 0x1234
        tapeC64.sid.voices[0].pulseWidth = 0x0ABC
        tapeC64.sid.voices[0].control = 0x21
        tapeC64.sid.voices[0].attackDecay = 0xAD
        tapeC64.sid.voices[0].sustainRelease = 0xF6
        tapeC64.sid.voices[0].accumulator = 0xABCDEF
        tapeC64.sid.voices[0].shiftRegister = 0x123456
        tapeC64.sid.voices[0].envelopeLevel = 0x7F
        tapeC64.sid.voices[0].envelopeState = .decay
        tapeC64.sid.voices[0].exponentialCounter = 12
        tapeC64.sid.voices[0].exponentialPeriod = 30
        tapeC64.sid.voices[0].holdZero = true
        tapeC64.sid.voices[0].gate = true
        tapeC64.sid.voices[0].rateCounter = 456
        tapeC64.sid.voices[0].waveformDACOutput = 0x0FED
        tapeC64.sid.voices[0].waveformDACHoldCyclesRemaining = 64
        tapeC64.sid.voices[2].control = 0x20
        tapeC64.sid.voices[2].accumulator = 0xAB_CDEF
        tapeC64.sid.voices[2].envelopeLevel = 0x7F
        tapeC64.sid.sampleVoice3Readbacks()
        tapeC64.vic.framebuffer[0] = ColorPalette.rgba[2]
        tapeC64.vic.framebuffer[1] = ColorPalette.rgba[5]
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
        XCTAssertTrue(log.contains(#""roadmapPhase":"#))
        XCTAssertTrue(log.contains(#""finalPC":"#))
        XCTAssertTrue(log.contains(#""finalVICRegisterSnapshotHash":"#))
        XCTAssertTrue(log.contains(#""finalVICRegisterSnapshot":"#))
        XCTAssertTrue(log.contains(#""finalVICState":"#))
        XCTAssertTrue(log.contains(#""finalSIDAccuracyMode":"compatibility""#))
        XCTAssertTrue(log.contains(#""finalSIDModel":"mos6581""#))
        XCTAssertTrue(log.contains(#""finalSIDAudioSignature":"#))
        XCTAssertTrue(log.contains(#""finalSIDAudioState":"#))
        XCTAssertTrue(log.contains(#""finalSIDRegisterSnapshot":"#))
        XCTAssertTrue(log.contains(#""finalSIDReadableRegisterSnapshot":"#))
        XCTAssertTrue(log.contains(#""finalSIDVoiceStates":"#))
        XCTAssertTrue(log.contains(#""finalScreenText":"#))
        XCTAssertTrue(log.contains(#""screenRAMHash":"#))
        XCTAssertTrue(log.contains(#""framebufferHash":"#))
        XCTAssertTrue(log.contains(#""finalTapeDecodeStatus":"rawPulsesOnly""#))
        XCTAssertTrue(log.contains(#""finalMountedTapeName":"loader.tap""#))
        XCTAssertTrue(log.contains(#""finalMediaFormat":"D64""#))
        XCTAssertTrue(log.contains(#""finalLowLevelTracks":"#))
        let records = try log.split(separator: "\n").map {
            try JSONDecoder().decode(MilestoneResultRecord.self, from: Data(String($0).utf8))
        }
        XCTAssertEqual(records.last?.screenshotPath, "/tmp/swift64-screens/demo.ppm")
        XCTAssertEqual(records.last?.formatVersion, MilestoneResultRecord.currentFormatVersion)
        XCTAssertEqual(records.last?.roadmapPhase, MilestoneRoadmapPhase.phase5SID)
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
        XCTAssertEqual(records.last?.finalVICBALineLow, false)
        XCTAssertEqual(records.last?.finalVICAECLineLow, false)
        XCTAssertEqual(records.last?.finalVICBusOwner, "cpu")
        XCTAssertEqual(records.last?.finalVICBusPhase, "cpu")
        XCTAssertEqual(records.last?.finalVICLowPhaseAccess, "idle")
        XCTAssertEqual(records.last?.finalVICHighPhaseMemoryReads, [])
        XCTAssertEqual(records.last?.finalVICHighPhaseColorRAMReads, [])
        XCTAssertEqual(records.last?.finalVICLowPhaseMemoryReads, [])
        XCTAssertEqual(
            records.last?.finalVICRegisterSnapshotHash,
            CompatibilityHash.vicRegisterSnapshot(vicRegisterSnapshot(tapeC64.vic))
        )
        XCTAssertEqual(records.last?.finalVICRegisterSnapshot?.count, 0x2F)
        XCTAssertEqual(records.last?.finalVICRegisterSnapshot?[0x19], "70")
        XCTAssertEqual(records.last?.finalVICState, vicStateSnapshot(tapeC64.vic))
        XCTAssertEqual(records.last?.framebufferHash, CompatibilityHash.framebuffer(
            tapeC64.vic.framebuffer,
            width: VIC.screenWidth,
            height: VIC.screenHeight
        ))
        XCTAssertEqual(records.last?.finalSIDModel, "mos6581")
        XCTAssertEqual(records.last?.finalSIDAccuracyMode, "compatibility")
        XCTAssertEqual(records.last?.finalSIDAudioSignature, SIDAudioSignatureRecord(SID.AudioSignature(
            sampleCount: 3,
            minimum: -0.5,
            maximum: 0.75,
            sum: 0.5,
            absoluteSum: 1.5,
            mean: 0.5 / 3.0,
            rootMeanSquare: 0.540_061_724_867_321_7,
            zeroCrossings: 1
        ), audioSummary: tapeC64.sid.recentAudioSummary(sampleCount: 3)))
        XCTAssertEqual(records.last?.finalSIDAudioState, SIDAudioStateRecord(SID.AudioDebugState(
            accuracyMode: .compatibility,
            sampleCycleCounter: 0,
            cyclesPerSample: tapeC64.sid.cyclesPerSample,
            audioAccumulator: 12.5,
            audioAccumulatorCount: 2,
            audioOutputState: 34.5,
            directOutput: -1024,
            filterInput: 2048,
            filterOutput: 512,
            mixedOutput: 1536,
            externalAudioInput: 12_000,
            externalAudioPathInput: 13_440,
            filterCutoff: 0x07FF,
            filterResonance: 0x0F,
            filterControl: 0,
            volumeFilter: 0x8F,
            volume: 0x0F,
            normalizedFilterCutoffValue: 0x07FF,
            normalizedFilterCutoff: 0.183,
            filterDamping: 0.775,
            voice1FilterEnabled: false,
            voice2FilterEnabled: false,
            voice3FilterEnabled: false,
            externalInputFiltered: false,
            filterLowPassEnabled: false,
            filterBandPassEnabled: false,
            filterHighPassEnabled: false,
            voice3Off: true,
            dataBusLatch: 0x8F,
            dataBusLatchCyclesRemaining: SID.dataBusLatchHoldCycles,
            oscillator3Readback: 0xAB,
            oscillator3ReadbackValid: true,
            envelope3Readback: 0x7F,
            envelope3ReadbackValid: true,
            paddleX: 0xFF,
            paddleY: 0xFF,
            paddleTargetX: 0xFF,
            paddleTargetY: 0xFF,
            paddleScanActive: false,
            paddleScanCounter: nil,
            filterLow: 1.25,
            filterBand: -2.5,
            filterHigh: 3.75,
            sampleWritePosition: 3
        )))
        XCTAssertEqual(records.last?.finalSIDRegisterSnapshot?.count, 0x20)
        XCTAssertEqual(records.last?.finalSIDRegisterSnapshot?[0x04], "21")
        XCTAssertEqual(records.last?.finalSIDRegisterSnapshot?[0x18], "8F")
        XCTAssertEqual(records.last?.finalSIDReadableRegisterSnapshot?.count, 0x20)
        XCTAssertEqual(records.last?.finalSIDReadableRegisterSnapshot?[0x18], "8F")
        XCTAssertEqual(records.last?.finalSIDReadableRegisterSnapshot?[0x1B], "AB")
        XCTAssertEqual(records.last?.finalSIDReadableRegisterSnapshot?[0x1C], "7F")
        XCTAssertEqual(records.last?.finalSIDVoiceStates?.count, 3)
        XCTAssertEqual(records.last?.finalSIDVoiceStates?.first, SIDVoiceStateRecord(SID.VoiceDebugState(
            frequency: 0x1234,
            pulseWidth: 0x0ABC,
            control: 0x21,
            attackDecay: 0xAD,
            sustainRelease: 0xF6,
            accumulator: 0xABCDEF,
            shiftRegister: 0x123456,
            envelopeLevel: 0x7F,
            envelopeOutput: 0x86,
            sustainLevel: 0xFF,
            envelopeState: "decay",
            exponentialCounter: 12,
            exponentialPeriod: 30,
            holdZero: true,
            gate: true,
            controlGate: true,
            sync: false,
            ringMod: false,
            testBit: false,
            waveTriangle: false,
            waveSawtooth: true,
            wavePulse: false,
            waveNoise: false,
            hasWaveform: true,
            oscillatorMSBRose: false,
            noiseClockRose: false,
            rateCounter: 456,
            selectedRatePeriod: SID.decayReleaseRates[0x0D],
            oscillatorOutput: 0x0ABC,
            waveformOutput: 5885,
            waveformDACOutput: 0x0FED,
            waveformDACHoldCyclesRemaining: 64
        )))
        XCTAssertEqual(records.last?.finalHeadBitPosition, 0)
        XCTAssertNil(records.last?.finalReadTrack)
        XCTAssertNil(records.last?.finalReadHalfTrack)
        XCTAssertEqual(records.last?.finalUsingHalfTrackFallback, false)
        XCTAssertEqual(records.last?.finalWeakBitReadCount, 0)
        XCTAssertNil(records.last?.finalLastWeakBitHalfTrack)
        XCTAssertNil(records.last?.finalLastWeakBitPosition)
        XCTAssertEqual(records.last?.finalVariableSpeedZoneSampleCount, 0)
        XCTAssertEqual(records.last?.finalVariableSpeedZoneMask, 0)
        XCTAssertNil(records.last?.finalLastVariableSpeedZoneHalfTrack)
        XCTAssertNil(records.last?.finalLastVariableSpeedZoneByteIndex)
        XCTAssertNil(records.last?.finalLastVariableSpeedZone)
        XCTAssertEqual(records.last?.finalGCRWriteByteCount, 0)
        XCTAssertEqual(records.last?.finalGCRWriteModeActive, false)
        XCTAssertEqual(records.last?.finalGCRWriteGateActive, false)
        XCTAssertEqual(records.last?.finalGCRWriteSpliceCount, 0)
        XCTAssertEqual(records.last?.finalGCRWriteEraseBitCount, 0)
        XCTAssertEqual(records.last?.finalD64ExportBlockedByLowLevelWrites, false)
        XCTAssertEqual(records.last?.finalDriveNoProgressCycleCount, 0)
        XCTAssertNil(records.last?.finalFailureReason)
        XCTAssertEqual(records.last?.finalMediaFormat, "D64")
        XCTAssertEqual(records.last?.finalMediaPopulatedHalfTrackCount, 35)
        XCTAssertEqual(records.last?.finalMediaNativeLowLevelTrackCount, 0)
        XCTAssertEqual(records.last?.finalMediaSyntheticGCRTrackCount, 35)
        XCTAssertEqual(records.last?.finalMediaHasSyntheticGCR, true)
        XCTAssertEqual(records.last?.finalMediaIsNativeLowLevel, false)
        XCTAssertEqual(records.last?.finalMediaPreservesSectorErrorInfo, true)
        XCTAssertEqual(records.last?.finalMediaPreservesWeakBitRanges, false)
        XCTAssertEqual(records.last?.finalMediaSectorErrorCodeCount, 683)
        XCTAssertEqual(records.last?.finalMediaNonDefaultSectorErrorCodeCount, 2)
        XCTAssertEqual(records.last?.finalMediaWeakBitRangeCount, 0)
        XCTAssertEqual(records.last?.finalMediaWeakBitTotalBitCount, 0)
        XCTAssertEqual(records.last?.finalMediaHasDuplicateSectorHeaders, false)
        XCTAssertEqual(records.last?.finalMediaDuplicateSectorHeaderCount, 0)
        XCTAssertEqual(records.last?.finalMediaVariableSpeedZoneByteCount, 0)
        XCTAssertEqual(records.last?.finalMediaSupportsWraparoundReads, true)
        XCTAssertNil(records.last?.finalMediaMaxTrackSize)
        XCTAssertEqual(records.last?.finalMediaUnsupportedFeatures, ["Native copy-protection bitstream"])
        XCTAssertEqual(records.last?.finalLowLevelTracks?.count, 1)
        XCTAssertEqual(records.last?.finalLowLevelTracks?.first?.halfTrack, 34)
        XCTAssertNotNil(records.last?.finalLowLevelTracks?.first?.byteCount)
        XCTAssertNotNil(records.last?.finalLowLevelTracks?.first?.bitLength)
        XCTAssertNotNil(records.last?.finalLowLevelTracks?.first?.speedZone)
        XCTAssertNotNil(records.last?.finalLowLevelTracks?.first?.bytesHash)
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
        XCTAssertNil(legacyRecord.roadmapPhase)
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
        XCTAssertNil(legacyRecord.finalVICBALineLow)
        XCTAssertNil(legacyRecord.finalVICAECLineLow)
        XCTAssertNil(legacyRecord.finalVICBusOwner)
        XCTAssertNil(legacyRecord.finalVICBusPhase)
        XCTAssertNil(legacyRecord.finalVICLowPhaseAccess)
        XCTAssertNil(legacyRecord.finalVICHighPhaseMemoryReads)
        XCTAssertNil(legacyRecord.finalVICHighPhaseColorRAMReads)
        XCTAssertNil(legacyRecord.finalVICLowPhaseMemoryReads)
        XCTAssertNil(legacyRecord.finalVICRegisterSnapshotHash)
        XCTAssertNil(legacyRecord.finalVICRegisterSnapshot)
        XCTAssertNil(legacyRecord.finalVICState)
        XCTAssertNil(legacyRecord.finalSIDAccuracyMode)
        XCTAssertNil(legacyRecord.finalSIDModel)
        XCTAssertNil(legacyRecord.finalSIDAudioSignature)
        XCTAssertNil(legacyRecord.finalSIDAudioState)
        XCTAssertNil(legacyRecord.finalSIDRegisterSnapshot)
        XCTAssertNil(legacyRecord.finalSIDReadableRegisterSnapshot)
        XCTAssertNil(legacyRecord.finalSIDVoiceStates)
        XCTAssertNil(legacyRecord.finalHeadBitPosition)
        XCTAssertNil(legacyRecord.finalWeakBitReadCount)
        XCTAssertNil(legacyRecord.finalLastWeakBitHalfTrack)
        XCTAssertNil(legacyRecord.finalLastWeakBitPosition)
        XCTAssertNil(legacyRecord.finalVariableSpeedZoneSampleCount)
        XCTAssertNil(legacyRecord.finalVariableSpeedZoneMask)
        XCTAssertNil(legacyRecord.finalLastVariableSpeedZoneHalfTrack)
        XCTAssertNil(legacyRecord.finalLastVariableSpeedZoneByteIndex)
        XCTAssertNil(legacyRecord.finalLastVariableSpeedZone)
        XCTAssertNil(legacyRecord.finalGCRWriteByteCount)
        XCTAssertNil(legacyRecord.finalGCRWriteModeActive)
        XCTAssertNil(legacyRecord.finalGCRWriteGateActive)
        XCTAssertNil(legacyRecord.finalGCRWriteSpliceCount)
        XCTAssertNil(legacyRecord.finalGCRWriteEraseBitCount)
        XCTAssertNil(legacyRecord.finalDriveNoProgressCycleCount)
        XCTAssertNil(legacyRecord.finalFailureReason)
        XCTAssertNil(legacyRecord.finalMediaFormat)
        XCTAssertNil(legacyRecord.finalLowLevelTracks)
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
        XCTAssertEqual(skippedRecord.roadmapPhase, MilestoneRoadmapPhase.phase5SID)
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
            milestoneShardIndex: 1,
            milestoneShardCount: 3,
            preShardMilestoneCount: 9,
            postShardMilestoneCount: 4,
            manifestValidationErrors: [],
            manifestMilestoneCount: 7,
            manifestPhaseCounts: [
                MilestoneRoadmapPhase.phase4DriveMedia: 4,
                MilestoneRoadmapPhase.phase5SID: 2,
            ],
            manifestMediaCounts: [
                CompatibilityMediaType.g64.rawValue: 5,
                CompatibilityMediaType.prg.rawValue: 2,
            ],
            manifestMachineProfileCounts: [
                CompatibilityMachineProfile.palC64.rawValue: 5,
                CompatibilityMachineProfile.ntscC64.rawValue: 2,
            ],
            manifestDriveModeCounts: [
                CompatibilityDriveMode.compat1541.rawValue: 5,
                CompatibilityDriveMode.fastLoad.rawValue: 2,
            ],
            manifestSIDModelCounts: [
                SID.Model.mos6581.rawValue: 4,
            ],
            manifestSIDAccuracyModeCounts: [
                SID.AccuracyMode.fast.rawValue: 4,
            ],
            manifestObservableTypeCounts: [
                MilestoneObservableType.drive: 5,
                MilestoneObservableType.sid: 2,
                MilestoneObservableType.vic: 1,
            ],
            manifestVICProofCounts: [
                MilestoneVICProofType.raster: 2,
                MilestoneVICProofType.state: 1,
            ],
            manifestExpectedFailureCategoryCounts: [
                CompatibilityFailureCategory.drive.rawValue: 2,
                CompatibilityFailureCategory.sid.rawValue: 1,
            ],
            manifestActionTypeCounts: [
                MilestoneActionType.typeText: 7,
                MilestoneActionType.waitCycles: 2,
                MilestoneActionType.joystickDown: 1,
            ],
            manifestUntaggedMilestoneCount: 1,
            manifestUnnamedMilestoneCount: 2,
            manifestExpectedFailureCount: 3,
            manifestExpectedFailuresWithoutNotesCount: 2,
            manifestExpectedFailuresWithoutReasonMarkersCount: 1,
            manifestMilestonesWithoutMaxCyclesCount: 2,
            manifestMilestonesWithoutExplicitActionsCount: 3,
            manifestMilestonesWithoutObservableExpectationsCount: 3,
            manifestPhase3MilestonesWithoutVICProofCount: 1,
            manifestPhase3MilestonesMissingRequiredVICProofsCount: 2,
            manifestFramebufferHashMilestonesWithoutScreenshotNamesCount: 2,
            manifestFramebufferScreenshotFilenameCollisionCount: 1,
            manifestFramebufferScreenshotFilenameCollisions: ["title_screen.ppm"],
            manifestPlaceholderProofHashCount: 3,
            phaseFilteredMilestoneCount: 4,
            selectedMilestoneCount: 3,
            selectedMilestoneKeys: [milestone.resultKey],
            selectedMediaCounts: [
                CompatibilityMediaType.g64.rawValue: 3,
            ],
            selectedMachineProfileCounts: [
                CompatibilityMachineProfile.palC64.rawValue: 3,
            ],
            selectedDriveModeCounts: [
                CompatibilityDriveMode.compat1541.rawValue: 3,
            ],
            selectedSIDModelCounts: [
                SID.Model.mos6581.rawValue: 3,
            ],
            selectedSIDAccuracyModeCounts: [
                SID.AccuracyMode.fast.rawValue: 3,
            ],
            selectedObservableTypeCounts: [
                MilestoneObservableType.drive: 3,
                MilestoneObservableType.sid: 1,
            ],
            selectedVICProofCounts: [
                MilestoneVICProofType.raster: 1,
            ],
            selectedExpectedFailureCategoryCounts: [
                CompatibilityFailureCategory.drive.rawValue: 1,
            ],
            selectedActionTypeCounts: [
                MilestoneActionType.typeText: 3,
                MilestoneActionType.waitCycles: 1,
            ],
            missingMediaFiles: ["missing.g64"],
            requireAllManifestMedia: true,
            requiredManifestMediaTypes: [
                CompatibilityMediaType.prg.rawValue,
                CompatibilityMediaType.g64.rawValue,
                CompatibilityMediaType.tap.rawValue,
            ],
            invalidRequiredManifestMediaTypes: ["wav"],
            requiredManifestMachineProfiles: [
                CompatibilityMachineProfile.palC64.rawValue,
                CompatibilityMachineProfile.ntscC64.rawValue,
                CompatibilityMachineProfile.ntscC64C.rawValue,
            ],
            invalidRequiredManifestMachineProfiles: ["c128"],
            requiredManifestDriveModes: [
                CompatibilityDriveMode.compat1541.rawValue,
                CompatibilityDriveMode.fastLoad.rawValue,
                CompatibilityDriveMode.standard1541.rawValue,
            ],
            invalidRequiredManifestDriveModes: ["turbo"],
            requiredManifestSIDModels: [
                SID.Model.mos6581.rawValue,
                SID.Model.mos8580.rawValue,
            ],
            invalidRequiredManifestSIDModels: ["mos6582"],
            requiredManifestSIDAccuracyModes: [
                SID.AccuracyMode.fast.rawValue,
                SID.AccuracyMode.compatibility.rawValue,
            ],
            invalidRequiredManifestSIDAccuracyModes: ["resid"],
            requiredManifestObservableTypes: [
                MilestoneObservableType.drive,
                MilestoneObservableType.sid,
                MilestoneObservableType.framebuffer,
            ],
            invalidRequiredManifestObservableTypes: ["raster"],
            requiredManifestVICProofs: [
                MilestoneVICProofType.raster,
                MilestoneVICProofType.state,
                MilestoneVICProofType.bus,
            ],
            invalidRequiredManifestVICProofs: ["spriteCrunch"],
            requiredManifestFailureCategories: [
                CompatibilityFailureCategory.drive.rawValue,
                CompatibilityFailureCategory.sid.rawValue,
                CompatibilityFailureCategory.vic.rawValue,
            ],
            invalidRequiredManifestFailureCategories: ["video"],
            requiredManifestActionTypes: [
                MilestoneActionType.typeText,
                MilestoneActionType.waitCycles,
                MilestoneActionType.startTape,
            ],
            invalidRequiredManifestActionTypes: ["mouseDown"],
            selectedPhaseNames: [
                MilestoneRoadmapPhase.phase4DriveMedia,
                MilestoneRoadmapPhase.phase5SID,
            ],
            invalidSelectedPhaseNames: ["phase5SIDD"],
            selectedPhaseCounts: [
                MilestoneRoadmapPhase.phase4DriveMedia: 4,
                MilestoneRoadmapPhase.phase5SID: 0,
            ],
            missingSelectedPhaseNames: [
                MilestoneRoadmapPhase.phase5SID,
            ],
            selectedMilestoneIDs: [
                "giana-title",
                "sid-filter",
                "missing-id",
            ],
            missingSelectedMilestoneIDs: [
                "missing-id",
            ],
            requireSelectedPhases: true,
            requireSelectedMilestoneIDs: true,
            requireManifest: true,
            requireTaggedManifestPhases: true,
            requireManifestMilestoneIDs: true,
            requireExpectedFailureNotes: true,
            requireExpectedFailureReasonMarkers: true,
            requireExplicitMaxCycles: true,
            requireExplicitActions: true,
            requireObservableExpectations: true,
            requirePhase3VICProofs: true,
            requireFramebufferScreenshots: true,
            rejectPlaceholderProofHashes: true,
            failOnUnclassified: true,
            failOnUnexpected: true,
            failPhaseNames: [
                MilestoneRoadmapPhase.phase2CPUMemoryBus,
                MilestoneRoadmapPhase.phase4DriveMedia
            ],
            invalidFailPhaseNames: ["phase4DriveMeda"]
        )
        summary.record(MatrixRunResult(passed: true, elapsedCycles: 10, reason: "named milestone reached").record(
            for: milestone,
            c64: C64(),
            screenshotURL: URL(fileURLWithPath: "/tmp/screens/pass.ppm")
        ))
        summary.record(MatrixRunResult(passed: false, elapsedCycles: 20, reason: "PC $0801 not in $C000-$C0FF").record(
            for: milestone,
            c64: C64(),
            expectedFailureMatched: true
        ))
        summary.record(MatrixRunResult(passed: false, elapsedCycles: 25, reason: "GCR reads 0 < 64").record(
            for: milestone,
            c64: C64(),
            expectedFailureMatched: false,
            expectedFailureMismatches: ["category drive != pc"]
        ))
        summary.record(MatrixRunResult(passed: false, elapsedCycles: 30, reason: "unexpected fallback path").record(
            for: milestone,
            c64: C64(),
            screenshotURL: URL(fileURLWithPath: "/tmp/screens/fail.ppm")
        ))
        summary.recordSkipped(milestone)

        try writeMilestoneRunSummary(summary, to: url)

        let decoded = try JSONDecoder().decode(MilestoneRunSummary.self, from: Data(contentsOf: url))
        let expectedVICRegisterSnapshotHash = CompatibilityHash.vicRegisterSnapshot(vicRegisterSnapshot(C64().vic))
        let expectedVICState = vicStateSnapshot(C64().vic)
        func expectedFailureSummary(
            category: String,
            reason: String,
            elapsedCycles: UInt64
        ) -> MilestoneFailureSummary {
            MilestoneFailureSummary(
                key: milestone.resultKey,
                category: category,
                reason: reason,
                elapsedCycles: elapsedCycles,
                finalPC: "0000",
                finalVICRasterLine: 0,
                finalVICRasterCycle: 0,
                finalVICBusOwner: "cpu",
                finalVICBusPhase: "cpu",
                finalVICLowPhaseAccess: "idle",
                finalVICHighPhaseMemoryReads: [],
                finalVICHighPhaseColorRAMReads: [],
                finalVICLowPhaseMemoryReads: [],
                finalVICRegisterSnapshotHash: expectedVICRegisterSnapshotHash,
                finalVICState: expectedVICState
            )
        }
        func expectedDriftSummary(
            category: String,
            reason: String,
            elapsedCycles: UInt64,
            mismatches: [String]
        ) -> MilestoneExpectedFailureDriftSummary {
            MilestoneExpectedFailureDriftSummary(
                key: milestone.resultKey,
                category: category,
                reason: reason,
                elapsedCycles: elapsedCycles,
                mismatches: mismatches,
                finalPC: "0000",
                finalVICRasterLine: 0,
                finalVICRasterCycle: 0,
                finalVICBusOwner: "cpu",
                finalVICBusPhase: "cpu",
                finalVICLowPhaseAccess: "idle",
                finalVICHighPhaseMemoryReads: [],
                finalVICHighPhaseColorRAMReads: [],
                finalVICLowPhaseMemoryReads: [],
                finalVICRegisterSnapshotHash: expectedVICRegisterSnapshotHash,
                finalVICState: expectedVICState
            )
        }
        XCTAssertEqual(decoded.total, 5)
        XCTAssertEqual(decoded.executed, 4)
        XCTAssertEqual(decoded.passed, 1)
        XCTAssertEqual(decoded.failed, 3)
        XCTAssertEqual(decoded.expectedFailures, 1)
        XCTAssertEqual(decoded.unexpectedFailures, 2)
        XCTAssertEqual(decoded.expectedFailureDriftCount, 1)
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
        XCTAssertEqual(decoded.screenshotsWrittenCount, 2)
        XCTAssertEqual(decoded.passedScreenshotCount, 1)
        XCTAssertEqual(decoded.failedScreenshotCount, 1)
        XCTAssertEqual(decoded.milestoneLimit, 5)
        XCTAssertEqual(decoded.milestoneShardIndex, 1)
        XCTAssertEqual(decoded.milestoneShardCount, 3)
        XCTAssertEqual(decoded.preShardMilestoneCount, 9)
        XCTAssertEqual(decoded.postShardMilestoneCount, 4)
        XCTAssertEqual(decoded.manifestValidationErrors, [])
        XCTAssertNil(decoded.invalidShardConfiguration)
        XCTAssertEqual(decoded.manifestMilestoneCount, 7)
        XCTAssertEqual(decoded.manifestPhaseCounts, [
            MilestoneRoadmapPhase.phase4DriveMedia: 4,
            MilestoneRoadmapPhase.phase5SID: 2,
        ])
        XCTAssertEqual(decoded.manifestMediaCounts, [
            CompatibilityMediaType.g64.rawValue: 5,
            CompatibilityMediaType.prg.rawValue: 2,
        ])
        XCTAssertEqual(decoded.manifestMachineProfileCounts, [
            CompatibilityMachineProfile.palC64.rawValue: 5,
            CompatibilityMachineProfile.ntscC64.rawValue: 2,
        ])
        XCTAssertEqual(decoded.manifestDriveModeCounts, [
            CompatibilityDriveMode.compat1541.rawValue: 5,
            CompatibilityDriveMode.fastLoad.rawValue: 2,
        ])
        XCTAssertEqual(decoded.manifestSIDModelCounts, [
            SID.Model.mos6581.rawValue: 4,
        ])
        XCTAssertEqual(decoded.manifestSIDAccuracyModeCounts, [
            SID.AccuracyMode.fast.rawValue: 4,
        ])
        XCTAssertEqual(decoded.manifestObservableTypeCounts, [
            MilestoneObservableType.drive: 5,
            MilestoneObservableType.sid: 2,
            MilestoneObservableType.vic: 1,
        ])
        XCTAssertEqual(decoded.manifestVICProofCounts, [
            MilestoneVICProofType.raster: 2,
            MilestoneVICProofType.state: 1,
        ])
        XCTAssertEqual(decoded.manifestExpectedFailureCategoryCounts, [
            CompatibilityFailureCategory.drive.rawValue: 2,
            CompatibilityFailureCategory.sid.rawValue: 1,
        ])
        XCTAssertEqual(decoded.manifestActionTypeCounts, [
            MilestoneActionType.typeText: 7,
            MilestoneActionType.waitCycles: 2,
            MilestoneActionType.joystickDown: 1,
        ])
        XCTAssertEqual(decoded.manifestUntaggedMilestoneCount, 1)
        XCTAssertEqual(decoded.manifestUnnamedMilestoneCount, 2)
        XCTAssertEqual(decoded.manifestExpectedFailureCount, 3)
        XCTAssertEqual(decoded.manifestExpectedFailuresWithoutNotesCount, 2)
        XCTAssertEqual(decoded.manifestExpectedFailuresWithoutReasonMarkersCount, 1)
        XCTAssertEqual(decoded.manifestMilestonesWithoutMaxCyclesCount, 2)
        XCTAssertEqual(decoded.manifestMilestonesWithoutExplicitActionsCount, 3)
        XCTAssertEqual(decoded.manifestMilestonesWithoutObservableExpectationsCount, 3)
        XCTAssertEqual(decoded.manifestPhase3MilestonesWithoutVICProofCount, 1)
        XCTAssertEqual(decoded.manifestPhase3MilestonesMissingRequiredVICProofsCount, 2)
        XCTAssertEqual(decoded.manifestFramebufferHashMilestonesWithoutScreenshotNamesCount, 2)
        XCTAssertEqual(decoded.manifestFramebufferScreenshotFilenameCollisionCount, 1)
        XCTAssertEqual(decoded.manifestFramebufferScreenshotFilenameCollisions, ["title_screen.ppm"])
        XCTAssertEqual(decoded.manifestPlaceholderProofHashCount, 3)
        XCTAssertEqual(decoded.phaseFilteredMilestoneCount, 4)
        XCTAssertEqual(decoded.selectedMilestoneCount, 3)
        XCTAssertEqual(decoded.selectedMilestoneKeys, [milestone.resultKey])
        XCTAssertEqual(decoded.selectedMediaCounts, [
            CompatibilityMediaType.g64.rawValue: 3,
        ])
        XCTAssertEqual(decoded.selectedMachineProfileCounts, [
            CompatibilityMachineProfile.palC64.rawValue: 3,
        ])
        XCTAssertEqual(decoded.selectedDriveModeCounts, [
            CompatibilityDriveMode.compat1541.rawValue: 3,
        ])
        XCTAssertEqual(decoded.selectedSIDModelCounts, [
            SID.Model.mos6581.rawValue: 3,
        ])
        XCTAssertEqual(decoded.selectedSIDAccuracyModeCounts, [
            SID.AccuracyMode.fast.rawValue: 3,
        ])
        XCTAssertEqual(decoded.selectedObservableTypeCounts, [
            MilestoneObservableType.drive: 3,
            MilestoneObservableType.sid: 1,
        ])
        XCTAssertEqual(decoded.selectedVICProofCounts, [
            MilestoneVICProofType.raster: 1,
        ])
        XCTAssertEqual(decoded.selectedExpectedFailureCategoryCounts, [
            CompatibilityFailureCategory.drive.rawValue: 1,
        ])
        XCTAssertEqual(decoded.selectedActionTypeCounts, [
            MilestoneActionType.typeText: 3,
            MilestoneActionType.waitCycles: 1,
        ])
        XCTAssertEqual(decoded.missingMediaFiles, ["missing.g64"])
        XCTAssertEqual(decoded.requireAllManifestMedia, true)
        XCTAssertEqual(decoded.requiredManifestMediaTypes, [
            CompatibilityMediaType.prg.rawValue,
            CompatibilityMediaType.g64.rawValue,
            CompatibilityMediaType.tap.rawValue,
        ])
        XCTAssertEqual(decoded.invalidRequiredManifestMediaTypes, ["wav"])
        XCTAssertEqual(decoded.missingRequiredManifestMediaTypes, [
            CompatibilityMediaType.tap.rawValue,
        ])
        XCTAssertEqual(decoded.requiredManifestMachineProfiles, [
            CompatibilityMachineProfile.palC64.rawValue,
            CompatibilityMachineProfile.ntscC64.rawValue,
            CompatibilityMachineProfile.ntscC64C.rawValue,
        ])
        XCTAssertEqual(decoded.invalidRequiredManifestMachineProfiles, ["c128"])
        XCTAssertEqual(decoded.missingRequiredManifestMachineProfiles, [
            CompatibilityMachineProfile.ntscC64C.rawValue,
        ])
        XCTAssertEqual(decoded.requiredManifestDriveModes, [
            CompatibilityDriveMode.compat1541.rawValue,
            CompatibilityDriveMode.fastLoad.rawValue,
            CompatibilityDriveMode.standard1541.rawValue,
        ])
        XCTAssertEqual(decoded.invalidRequiredManifestDriveModes, ["turbo"])
        XCTAssertEqual(decoded.missingRequiredManifestDriveModes, [
            CompatibilityDriveMode.standard1541.rawValue,
        ])
        XCTAssertEqual(decoded.requiredManifestSIDModels, [
            SID.Model.mos6581.rawValue,
            SID.Model.mos8580.rawValue,
        ])
        XCTAssertEqual(decoded.invalidRequiredManifestSIDModels, ["mos6582"])
        XCTAssertEqual(decoded.missingRequiredManifestSIDModels, [
            SID.Model.mos8580.rawValue,
        ])
        XCTAssertEqual(decoded.requiredManifestSIDAccuracyModes, [
            SID.AccuracyMode.fast.rawValue,
            SID.AccuracyMode.compatibility.rawValue,
        ])
        XCTAssertEqual(decoded.invalidRequiredManifestSIDAccuracyModes, ["resid"])
        XCTAssertEqual(decoded.missingRequiredManifestSIDAccuracyModes, [
            SID.AccuracyMode.compatibility.rawValue,
        ])
        XCTAssertEqual(decoded.requiredManifestObservableTypes, [
            MilestoneObservableType.drive,
            MilestoneObservableType.sid,
            MilestoneObservableType.framebuffer,
        ])
        XCTAssertEqual(decoded.invalidRequiredManifestObservableTypes, ["raster"])
        XCTAssertEqual(decoded.missingRequiredManifestObservableTypes, [
            MilestoneObservableType.framebuffer,
        ])
        XCTAssertEqual(decoded.requiredManifestVICProofs, [
            MilestoneVICProofType.raster,
            MilestoneVICProofType.state,
            MilestoneVICProofType.bus,
        ])
        XCTAssertEqual(decoded.invalidRequiredManifestVICProofs, ["spriteCrunch"])
        XCTAssertEqual(decoded.missingRequiredManifestVICProofs, [
            MilestoneVICProofType.bus,
        ])
        XCTAssertEqual(decoded.requiredManifestFailureCategories, [
            CompatibilityFailureCategory.drive.rawValue,
            CompatibilityFailureCategory.sid.rawValue,
            CompatibilityFailureCategory.vic.rawValue,
        ])
        XCTAssertEqual(decoded.invalidRequiredManifestFailureCategories, ["video"])
        XCTAssertEqual(decoded.missingRequiredManifestFailureCategories, [
            CompatibilityFailureCategory.vic.rawValue,
        ])
        XCTAssertEqual(decoded.requiredManifestActionTypes, [
            MilestoneActionType.typeText,
            MilestoneActionType.waitCycles,
            MilestoneActionType.startTape,
        ])
        XCTAssertEqual(decoded.invalidRequiredManifestActionTypes, ["mouseDown"])
        XCTAssertEqual(decoded.missingRequiredManifestActionTypes, [
            MilestoneActionType.startTape,
        ])
        XCTAssertEqual(decoded.selectedPhaseNames, [
            MilestoneRoadmapPhase.phase4DriveMedia,
            MilestoneRoadmapPhase.phase5SID,
        ])
        XCTAssertEqual(decoded.invalidSelectedPhaseNames, ["phase5SIDD"])
        XCTAssertEqual(decoded.selectedPhaseCounts, [
            MilestoneRoadmapPhase.phase4DriveMedia: 4,
            MilestoneRoadmapPhase.phase5SID: 0,
        ])
        XCTAssertEqual(decoded.missingSelectedPhaseNames, [
            MilestoneRoadmapPhase.phase5SID,
        ])
        XCTAssertEqual(decoded.selectedMilestoneIDs, [
            "giana-title",
            "sid-filter",
            "missing-id",
        ])
        XCTAssertEqual(decoded.missingSelectedMilestoneIDs, [
            "missing-id",
        ])
        XCTAssertEqual(decoded.requireSelectedPhases, true)
        XCTAssertEqual(decoded.requireSelectedMilestoneIDs, true)
        XCTAssertEqual(decoded.requireManifest, true)
        XCTAssertEqual(decoded.requireTaggedManifestPhases, true)
        XCTAssertEqual(decoded.requireManifestMilestoneIDs, true)
        XCTAssertEqual(decoded.requireExpectedFailureNotes, true)
        XCTAssertEqual(decoded.requireExpectedFailureReasonMarkers, true)
        XCTAssertEqual(decoded.requireExplicitMaxCycles, true)
        XCTAssertEqual(decoded.requireExplicitActions, true)
        XCTAssertEqual(decoded.requireObservableExpectations, true)
        XCTAssertEqual(decoded.requirePhase3VICProofs, true)
        XCTAssertEqual(decoded.requireFramebufferScreenshots, true)
        XCTAssertEqual(decoded.rejectPlaceholderProofHashes, true)
        XCTAssertEqual(decoded.failOnUnclassified, true)
        XCTAssertEqual(decoded.failOnUnexpected, true)
        XCTAssertEqual(decoded.failPhaseNames, [
            MilestoneRoadmapPhase.phase2CPUMemoryBus,
            MilestoneRoadmapPhase.phase4DriveMedia
        ])
        XCTAssertEqual(decoded.invalidFailPhaseNames, ["phase4DriveMeda"])
        XCTAssertEqual(decoded.outcome, "acceptanceFailed")
        XCTAssertEqual(decoded.phaseAcceptanceFailures, [
            "\(MilestoneRoadmapPhase.phase4DriveMedia):\(MilestonePhaseOutcome.expectedFailureDrift)"
        ])
        XCTAssertEqual(decoded.acceptanceFailures, [
            "unclassifiedFailures",
            "unexpectedFailures",
            "phase:\(MilestoneRoadmapPhase.phase4DriveMedia):\(MilestonePhaseOutcome.expectedFailureDrift)",
            "invalidPhase:phase4DriveMeda",
            "invalidSelectedPhase:phase5SIDD",
            "invalidRequiredMediaType:wav",
            "missingRequiredMediaType:tap",
            "invalidRequiredMachineProfile:c128",
            "missingRequiredMachineProfile:ntscC64C",
            "invalidRequiredDriveMode:turbo",
            "missingRequiredDriveMode:standard1541",
            "invalidRequiredSIDModel:mos6582",
            "missingRequiredSIDModel:mos8580",
            "invalidRequiredSIDAccuracyMode:resid",
            "missingRequiredSIDAccuracyMode:compatibility",
            "invalidRequiredObservableType:raster",
            "missingRequiredObservableType:framebuffer",
            "invalidRequiredVICProof:spriteCrunch",
            "missingRequiredVICProof:bus",
            "invalidRequiredFailureCategory:video",
            "missingRequiredFailureCategory:vic",
            "invalidRequiredActionType:mouseDown",
            "missingRequiredActionType:startTape",
            "missingSelectedPhase:\(MilestoneRoadmapPhase.phase5SID)",
            "missingSelectedMilestoneID:missing-id",
            "untaggedManifestMilestones:1",
            "unnamedManifestMilestones:2",
            "expectedFailuresWithoutNotes:2",
            "expectedFailuresWithoutReasonMarkers:1",
            "milestonesWithoutMaxCycles:2",
            "milestonesWithoutExplicitActions:3",
            "milestonesWithoutObservableExpectations:3",
            "phase3MilestonesWithoutVICProof:1",
            "phase3MilestonesMissingRequiredVICProofs:2",
            "framebufferHashMilestonesWithoutScreenshotNames:2",
            "framebufferScreenshotFilenameCollisions:1",
            "placeholderProofHashes:3"
        ])
        XCTAssertEqual(decoded.unclassifiedFailureCount, 1)
        XCTAssertEqual(decoded.formatVersion, 42)
        XCTAssertEqual(decoded.totalElapsedCycles, 85)
        XCTAssertEqual(decoded.maxElapsedCycles, 30)
        XCTAssertEqual(decoded.slowestMilestone, milestone.resultKey)
        XCTAssertEqual(decoded.categories["pass"], 1)
        XCTAssertEqual(decoded.categories["pc"], 1)
        XCTAssertEqual(decoded.categories["drive"], 1)
        XCTAssertEqual(decoded.categories["emulator"], 1)
        XCTAssertEqual(decoded.phaseCounts[MilestoneRoadmapPhase.passed], 1)
        XCTAssertEqual(decoded.phaseCounts[MilestoneRoadmapPhase.phase2CPUMemoryBus], 1)
        XCTAssertEqual(decoded.phaseCounts[MilestoneRoadmapPhase.phase4DriveMedia], 1)
        XCTAssertEqual(decoded.phaseCounts[MilestoneRoadmapPhase.unclassified], 1)
        XCTAssertEqual(decoded.phaseCounts[MilestoneRoadmapPhase.skipped], 1)
        XCTAssertEqual(decoded.phaseBreakdown[MilestoneRoadmapPhase.passed], MilestonePhaseBreakdown(
            total: 1,
            passed: 1
        ))
        XCTAssertEqual(decoded.phaseBreakdown[MilestoneRoadmapPhase.phase2CPUMemoryBus], MilestonePhaseBreakdown(
            total: 1,
            failed: 1,
            expectedFailures: 1
        ))
        XCTAssertEqual(decoded.phaseBreakdown[MilestoneRoadmapPhase.phase4DriveMedia], MilestonePhaseBreakdown(
            total: 1,
            failed: 1,
            unexpectedFailures: 1,
            expectedFailureDrift: 1
        ))
        XCTAssertEqual(decoded.phaseBreakdown[MilestoneRoadmapPhase.unclassified], MilestonePhaseBreakdown(
            total: 1,
            failed: 1,
            unexpectedFailures: 1,
            unclassifiedFailures: 1
        ))
        XCTAssertEqual(decoded.phaseBreakdown[MilestoneRoadmapPhase.skipped], MilestonePhaseBreakdown(
            total: 1,
            skipped: 1
        ))
        XCTAssertEqual(decoded.phaseOutcomes[MilestoneRoadmapPhase.passed], MilestonePhaseOutcome.passed)
        XCTAssertEqual(decoded.phaseOutcomes[MilestoneRoadmapPhase.phase2CPUMemoryBus], MilestonePhaseOutcome.expectedFailures)
        XCTAssertEqual(decoded.phaseOutcomes[MilestoneRoadmapPhase.phase4DriveMedia], MilestonePhaseOutcome.expectedFailureDrift)
        XCTAssertEqual(decoded.phaseOutcomes[MilestoneRoadmapPhase.unclassified], MilestonePhaseOutcome.unclassifiedFailures)
        XCTAssertEqual(decoded.phaseOutcomes[MilestoneRoadmapPhase.skipped], MilestonePhaseOutcome.skipped)
        XCTAssertEqual(decoded.phaseFailureDetails[MilestoneRoadmapPhase.phase2CPUMemoryBus], [
            expectedFailureSummary(
                category: "pc",
                reason: "PC $0801 not in $C000-$C0FF",
                elapsedCycles: 20
            )
        ])
        XCTAssertEqual(decoded.phaseFailureDetails[MilestoneRoadmapPhase.phase4DriveMedia], [
            expectedFailureSummary(
                category: "drive",
                reason: "GCR reads 0 < 64",
                elapsedCycles: 25
            )
        ])
        XCTAssertEqual(decoded.phaseExpectedFailureDriftDetails[MilestoneRoadmapPhase.phase4DriveMedia], [
            expectedDriftSummary(
                category: "drive",
                reason: "GCR reads 0 < 64",
                elapsedCycles: 25,
                mismatches: ["category drive != pc"]
            )
        ])
        XCTAssertEqual(decoded.failedMilestones, [milestone.resultKey, milestone.resultKey, milestone.resultKey])
        XCTAssertEqual(decoded.failedMilestoneDetails, [
            expectedFailureSummary(
                category: "pc",
                reason: "PC $0801 not in $C000-$C0FF",
                elapsedCycles: 20
            ),
            expectedFailureSummary(
                category: "drive",
                reason: "GCR reads 0 < 64",
                elapsedCycles: 25
            ),
            expectedFailureSummary(
                category: "emulator",
                reason: "unexpected fallback path",
                elapsedCycles: 30
            )
        ])
        XCTAssertEqual(decoded.expectedFailureDetails, [
            expectedFailureSummary(
                category: "pc",
                reason: "PC $0801 not in $C000-$C0FF",
                elapsedCycles: 20
            )
        ])
        XCTAssertEqual(decoded.unexpectedFailureDetails, [
            expectedFailureSummary(
                category: "drive",
                reason: "GCR reads 0 < 64",
                elapsedCycles: 25
            ),
            expectedFailureSummary(
                category: "emulator",
                reason: "unexpected fallback path",
                elapsedCycles: 30
            )
        ])
        XCTAssertEqual(decoded.expectedFailureDriftDetails, [
            expectedDriftSummary(
                category: "drive",
                reason: "GCR reads 0 < 64",
                elapsedCycles: 25,
                mismatches: ["category drive != pc"]
            )
        ])
        XCTAssertEqual(decoded.unclassifiedFailureDetails, [
            expectedFailureSummary(
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
        XCTAssertTrue(decoded.unclassifiedFailureSummary.contains("pc=$0000"))
        XCTAssertTrue(decoded.unclassifiedFailureSummary.contains("vicOwner=cpu"))
        XCTAssertTrue(decoded.unclassifiedFailureSummary.contains("vicLow=[]"))
        XCTAssertTrue(decoded.unclassifiedFailureSummary.contains("unexpected fallback path"))
        XCTAssertTrue(decoded.unexpectedFailureSummary.contains("demo.g64"))
        XCTAssertTrue(decoded.unexpectedFailureSummary.contains("vicPhase=cpu"))
        XCTAssertTrue(decoded.unexpectedFailureSummary.contains("vicHigh=[]"))
        XCTAssertTrue(decoded.unexpectedFailureSummary.contains("unexpected fallback path"))
        XCTAssertTrue(decoded.unexpectedFailureSummary.contains("GCR reads 0 < 64"))
        XCTAssertTrue(decoded.expectedFailureDriftSummary.contains("category drive != pc"))
        XCTAssertTrue(decoded.expectedFailureDriftSummary.contains("pc=$0000"))
        XCTAssertTrue(decoded.expectedFailureDriftSummary.contains("vicColor=[]"))
        XCTAssertFalse(decoded.expectedFailureDriftSummary.contains("unexpected fallback path"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains(MilestoneRoadmapPhase.phase4DriveMedia))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains(MilestonePhaseOutcome.expectedFailureDrift))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("invalid:phase4DriveMeda"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("invalidSelected:phase5SIDD"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("missingSelected:phase5SID"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("invalidRequiredMedia:wav"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("missingRequiredMedia:tap"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("invalidRequiredProfile:c128"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("missingRequiredProfile:ntscC64C"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("invalidRequiredDrive:turbo"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("missingRequiredDrive:standard1541"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("invalidRequiredSIDModel:mos6582"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("missingRequiredSIDModel:mos8580"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("invalidRequiredSIDAccuracy:resid"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("missingRequiredSIDAccuracy:compatibility"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("invalidRequiredObservable:raster"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("missingRequiredObservable:framebuffer"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("invalidRequiredFailureCategory:video"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("missingRequiredFailureCategory:vic"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("invalidRequiredAction:mouseDown"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("missingRequiredAction:startTape"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("missingSelectedID:missing-id"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("phase3MilestonesMissingRequiredVICProofs:2"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("framebufferScreenshotFilenameCollisions:1"))
        XCTAssertTrue(decoded.phaseAcceptanceFailureSummary.contains("title_screen.ppm"))
        XCTAssertTrue(decoded.consoleSummary.contains("total=5"))
        XCTAssertTrue(decoded.consoleSummary.contains("executed=4"))
        XCTAssertTrue(decoded.consoleSummary.contains("selected=3"))
        XCTAssertTrue(decoded.consoleSummary.contains("phaseFiltered=4"))
        XCTAssertTrue(decoded.consoleSummary.contains("preShard=9"))
        XCTAssertTrue(decoded.consoleSummary.contains("postShard=4"))
        XCTAssertTrue(decoded.consoleSummary.contains("shardIndex=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("shardCount=3"))
        XCTAssertTrue(decoded.consoleSummary.contains("invalidShard=[none]"))
        XCTAssertTrue(decoded.consoleSummary.contains("manifestPhaseCounts=[phase4DriveMedia=4 phase5SID=2]"))
        XCTAssertTrue(decoded.consoleSummary.contains("manifestMediaCounts=[g64=5 prg=2]"))
        XCTAssertTrue(decoded.consoleSummary.contains("selectedMediaCounts=[g64=3]"))
        XCTAssertTrue(decoded.consoleSummary.contains("manifestMachineProfiles=[ntscC64=2 palC64=5]"))
        XCTAssertTrue(decoded.consoleSummary.contains("selectedMachineProfiles=[palC64=3]"))
        XCTAssertTrue(decoded.consoleSummary.contains("manifestDriveModes=[compat1541=5 fastLoad=2]"))
        XCTAssertTrue(decoded.consoleSummary.contains("selectedDriveModes=[compat1541=3]"))
        XCTAssertTrue(decoded.consoleSummary.contains("manifestSIDModels=[mos6581=4]"))
        XCTAssertTrue(decoded.consoleSummary.contains("selectedSIDModels=[mos6581=3]"))
        XCTAssertTrue(decoded.consoleSummary.contains("manifestSIDAccuracyModes=[fast=4]"))
        XCTAssertTrue(decoded.consoleSummary.contains("selectedSIDAccuracyModes=[fast=3]"))
        XCTAssertTrue(decoded.consoleSummary.contains("manifestObservableTypes=[drive=5 sid=2 vic=1]"))
        XCTAssertTrue(decoded.consoleSummary.contains("selectedObservableTypes=[drive=3 sid=1]"))
        XCTAssertTrue(decoded.consoleSummary.contains("manifestExpectedFailureCategories=[drive=2 sid=1]"))
        XCTAssertTrue(decoded.consoleSummary.contains("selectedExpectedFailureCategories=[drive=1]"))
        XCTAssertTrue(decoded.consoleSummary.contains("manifestActionTypes=[joystickDown=1 typeText=7 waitCycles=2]"))
        XCTAssertTrue(decoded.consoleSummary.contains("selectedActionTypes=[typeText=3 waitCycles=1]"))
        XCTAssertTrue(decoded.consoleSummary.contains("requiredMedia=[prg g64 tap]"))
        XCTAssertTrue(decoded.consoleSummary.contains("invalidRequiredMedia=[wav]"))
        XCTAssertTrue(decoded.consoleSummary.contains("missingRequiredMedia=[tap]"))
        XCTAssertTrue(decoded.consoleSummary.contains("requiredProfiles=[palC64 ntscC64 ntscC64C]"))
        XCTAssertTrue(decoded.consoleSummary.contains("invalidRequiredProfiles=[c128]"))
        XCTAssertTrue(decoded.consoleSummary.contains("missingRequiredProfiles=[ntscC64C]"))
        XCTAssertTrue(decoded.consoleSummary.contains("requiredDriveModes=[compat1541 fastLoad standard1541]"))
        XCTAssertTrue(decoded.consoleSummary.contains("invalidRequiredDriveModes=[turbo]"))
        XCTAssertTrue(decoded.consoleSummary.contains("missingRequiredDriveModes=[standard1541]"))
        XCTAssertTrue(decoded.consoleSummary.contains("requiredSIDModels=[mos6581 mos8580]"))
        XCTAssertTrue(decoded.consoleSummary.contains("invalidRequiredSIDModels=[mos6582]"))
        XCTAssertTrue(decoded.consoleSummary.contains("missingRequiredSIDModels=[mos8580]"))
        XCTAssertTrue(decoded.consoleSummary.contains("requiredSIDAccuracyModes=[fast compatibility]"))
        XCTAssertTrue(decoded.consoleSummary.contains("invalidRequiredSIDAccuracyModes=[resid]"))
        XCTAssertTrue(decoded.consoleSummary.contains("missingRequiredSIDAccuracyModes=[compatibility]"))
        XCTAssertTrue(decoded.consoleSummary.contains("requiredObservableTypes=[drive sid framebuffer]"))
        XCTAssertTrue(decoded.consoleSummary.contains("invalidRequiredObservableTypes=[raster]"))
        XCTAssertTrue(decoded.consoleSummary.contains("missingRequiredObservableTypes=[framebuffer]"))
        XCTAssertTrue(decoded.consoleSummary.contains("requiredFailureCategories=[drive sid vic]"))
        XCTAssertTrue(decoded.consoleSummary.contains("invalidRequiredFailureCategories=[video]"))
        XCTAssertTrue(decoded.consoleSummary.contains("missingRequiredFailureCategories=[vic]"))
        XCTAssertTrue(decoded.consoleSummary.contains("requiredActionTypes=[typeText waitCycles startTape]"))
        XCTAssertTrue(decoded.consoleSummary.contains("invalidRequiredActionTypes=[mouseDown]"))
        XCTAssertTrue(decoded.consoleSummary.contains("missingRequiredActionTypes=[startTape]"))
        XCTAssertTrue(decoded.consoleSummary.contains("manifestUntagged=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("manifestUnnamed=2"))
        XCTAssertTrue(decoded.consoleSummary.contains("manifestExpectedFailures=3"))
        XCTAssertTrue(decoded.consoleSummary.contains("expectedFailuresWithoutNotes=2"))
        XCTAssertTrue(decoded.consoleSummary.contains("expectedFailuresWithoutReasons=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("screenshots=2"))
        XCTAssertTrue(decoded.consoleSummary.contains("passedScreenshots=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("failedScreenshots=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("milestonesWithoutMaxCycles=2"))
        XCTAssertTrue(decoded.consoleSummary.contains("milestonesWithoutExplicitActions=3"))
        XCTAssertTrue(decoded.consoleSummary.contains("milestonesWithoutObservables=3"))
        XCTAssertTrue(decoded.consoleSummary.contains("phase3MilestonesWithoutVICProof=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("phase3MilestonesMissingRequiredVICProofs=2"))
        XCTAssertTrue(decoded.consoleSummary.contains("framebufferProofsWithoutScreenshots=2"))
        XCTAssertTrue(decoded.consoleSummary.contains("framebufferScreenshotCollisions=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("framebufferScreenshotCollisionFiles=[title_screen.ppm]"))
        XCTAssertTrue(decoded.consoleSummary.contains("placeholderProofHashes=3"))
        XCTAssertTrue(decoded.consoleSummary.contains("requireManifest=true"))
        XCTAssertTrue(decoded.consoleSummary.contains("requireTaggedPhases=true"))
        XCTAssertTrue(decoded.consoleSummary.contains("requireIDs=true"))
        XCTAssertTrue(decoded.consoleSummary.contains("requireExpectedFailureNotes=true"))
        XCTAssertTrue(decoded.consoleSummary.contains("requireExpectedFailureReasons=true"))
        XCTAssertTrue(decoded.consoleSummary.contains("requireMaxCycles=true"))
        XCTAssertTrue(decoded.consoleSummary.contains("requireActions=true"))
        XCTAssertTrue(decoded.consoleSummary.contains("requireObservables=true"))
        XCTAssertTrue(decoded.consoleSummary.contains("requirePhase3VICProofs=true"))
        XCTAssertTrue(decoded.consoleSummary.contains("requireFramebufferScreenshots=true"))
        XCTAssertTrue(decoded.consoleSummary.contains("rejectPlaceholderProofHashes=true"))
        XCTAssertTrue(decoded.consoleSummary.contains("selectedPhases=[phase4DriveMedia phase5SID]"))
        XCTAssertTrue(decoded.consoleSummary.contains("selectedPhaseCounts=[phase4DriveMedia=4 phase5SID=0]"))
        XCTAssertTrue(decoded.consoleSummary.contains("invalidSelectedPhases=[phase5SIDD]"))
        XCTAssertTrue(decoded.consoleSummary.contains("missingSelectedPhases=[phase5SID]"))
        XCTAssertTrue(decoded.consoleSummary.contains("selectedIDs=[giana-title sid-filter missing-id]"))
        XCTAssertTrue(decoded.consoleSummary.contains("missingSelectedIDs=[missing-id]"))
        XCTAssertTrue(decoded.consoleSummary.contains("missingMedia=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("expectedFailures=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("unexpectedFailures=2"))
        XCTAssertTrue(decoded.consoleSummary.contains("expectedFailureDrift=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("unclassified=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("outcome=acceptanceFailed"))
        XCTAssertTrue(decoded.consoleSummary.contains("drive=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("pc=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("emulator=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("phases=["))
        XCTAssertTrue(decoded.consoleSummary.contains("phase2CPUMemoryBus=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("phase4DriveMedia=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("unclassified=1"))
        XCTAssertTrue(decoded.consoleSummary.contains("phaseAcceptanceFailures=["))
        XCTAssertTrue(decoded.consoleSummary.contains("phase4DriveMedia:expectedFailureDrift"))
        XCTAssertTrue(decoded.consoleSummary.contains("invalid:phase4DriveMeda"))
        XCTAssertTrue(decoded.consoleSummary.contains("invalidSelected:phase5SIDD"))
        XCTAssertTrue(decoded.consoleSummary.contains("missingSelected:phase5SID"))
        XCTAssertTrue(decoded.consoleSummary.contains("cycles=85"))
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

        var missingManifest = MilestoneRunSummary()
        missingManifest.configureRun(
            runID: nil,
            manifestURL: nil,
            manifestHash: nil,
            resultLogURL: nil,
            screenshotDirectoryURL: nil,
            resumeEnabled: false,
            strictManifestResumeEnabled: false,
            screenshotFailuresEnabled: false,
            milestoneLimit: nil,
            manifestMilestoneCount: nil,
            selectedMilestoneCount: 0,
            missingMediaFiles: [],
            requireAllManifestMedia: false,
            requireManifest: true,
            failOnUnclassified: false,
            failOnUnexpected: false
        )
        missingManifest.refreshDerivedFields()
        XCTAssertEqual(missingManifest.outcome, "acceptanceFailed")
        XCTAssertEqual(missingManifest.acceptanceFailures, ["missingManifest"])
    }

    func testMilestoneRunSummaryCanGatePhase3VICMilestonesWithoutVICProof() {
        var summary = MilestoneRunSummary()
        summary.configureRun(
            runID: nil,
            manifestURL: URL(fileURLWithPath: "/tmp/compatibility.json"),
            manifestHash: nil,
            resultLogURL: nil,
            screenshotDirectoryURL: nil,
            resumeEnabled: false,
            strictManifestResumeEnabled: false,
            screenshotFailuresEnabled: false,
            milestoneLimit: nil,
            manifestMilestoneCount: 3,
            manifestPhaseCounts: [
                MilestoneRoadmapPhase.phase3VICII: 2,
                MilestoneRoadmapPhase.phase4DriveMedia: 1,
            ],
            manifestVICProofCounts: [
                MilestoneVICProofType.raster: 1,
            ],
            manifestPhase3MilestonesWithoutVICProofCount: 1,
            manifestPhase3MilestonesMissingRequiredVICProofsCount: 2,
            selectedMilestoneCount: 0,
            missingMediaFiles: [],
            requireAllManifestMedia: false,
            requirePhase3VICProofs: true,
            failOnUnclassified: false,
            failOnUnexpected: false
        )

        summary.refreshDerivedFields()

        XCTAssertEqual(summary.outcome, "acceptanceFailed")
        XCTAssertEqual(summary.acceptanceFailures, [
            "phase3MilestonesWithoutVICProof:1",
            "phase3MilestonesMissingRequiredVICProofs:2",
        ])
        XCTAssertTrue(summary.consoleSummary.contains("phase3MilestonesWithoutVICProof=1"))
        XCTAssertTrue(summary.consoleSummary.contains("phase3MilestonesMissingRequiredVICProofs=2"))
        XCTAssertTrue(summary.consoleSummary.contains("requirePhase3VICProofs=true"))
    }

    func testMilestoneRunSummaryCanRejectPlaceholderProofHashes() {
        var summary = MilestoneRunSummary()
        summary.configureRun(
            runID: nil,
            manifestURL: URL(fileURLWithPath: "/tmp/compatibility.json"),
            manifestHash: nil,
            resultLogURL: nil,
            screenshotDirectoryURL: nil,
            resumeEnabled: false,
            strictManifestResumeEnabled: false,
            screenshotFailuresEnabled: false,
            milestoneLimit: nil,
            manifestMilestoneCount: 3,
            manifestPlaceholderProofHashCount: 4,
            selectedMilestoneCount: 0,
            missingMediaFiles: [],
            requireAllManifestMedia: false,
            rejectPlaceholderProofHashes: true,
            failOnUnclassified: false,
            failOnUnexpected: false
        )

        summary.refreshDerivedFields()

        XCTAssertEqual(summary.outcome, "acceptanceFailed")
        XCTAssertEqual(summary.acceptanceFailures, [
            "placeholderProofHashes:4",
        ])
        XCTAssertTrue(summary.consoleSummary.contains("placeholderProofHashes=4"))
        XCTAssertTrue(summary.consoleSummary.contains("rejectPlaceholderProofHashes=true"))
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

    func testMilestoneRunSummaryCanGateMissingSelectedMilestoneIDs() {
        var summary = MilestoneRunSummary()
        summary.configureRun(
            runID: nil,
            manifestURL: URL(fileURLWithPath: "/tmp/compatibility.json"),
            manifestHash: nil,
            resultLogURL: nil,
            screenshotDirectoryURL: nil,
            resumeEnabled: false,
            strictManifestResumeEnabled: false,
            screenshotFailuresEnabled: false,
            milestoneLimit: nil,
            manifestMilestoneCount: 2,
            selectedMilestoneCount: 0,
            missingMediaFiles: [],
            requireAllManifestMedia: false,
            selectedMilestoneIDs: ["giana-title", "sid-filter"],
            missingSelectedMilestoneIDs: ["sid-filter"],
            requireSelectedMilestoneIDs: true,
            failOnUnclassified: false,
            failOnUnexpected: false
        )

        summary.refreshDerivedFields()

        XCTAssertEqual(summary.outcome, "acceptanceFailed")
        XCTAssertEqual(summary.acceptanceFailures, ["missingSelectedMilestoneID:sid-filter"])
        XCTAssertTrue(summary.consoleSummary.contains("selectedIDs=[giana-title sid-filter]"))
        XCTAssertTrue(summary.consoleSummary.contains("missingSelectedIDs=[sid-filter]"))
    }

    func testMilestoneRunSummaryGatesInvalidShardConfiguration() {
        var summary = MilestoneRunSummary()
        summary.configureRun(
            runID: nil,
            manifestURL: URL(fileURLWithPath: "/tmp/compatibility.json"),
            manifestHash: nil,
            resultLogURL: nil,
            screenshotDirectoryURL: nil,
            resumeEnabled: false,
            strictManifestResumeEnabled: false,
            screenshotFailuresEnabled: false,
            milestoneLimit: nil,
            milestoneShardIndex: 4,
            milestoneShardCount: 2,
            preShardMilestoneCount: 5,
            postShardMilestoneCount: 5,
            invalidShardConfiguration: "invalidShard:index=4,count=2",
            manifestMilestoneCount: 5,
            selectedMilestoneCount: 5,
            missingMediaFiles: [],
            requireAllManifestMedia: false,
            failOnUnclassified: false,
            failOnUnexpected: false
        )

        summary.refreshDerivedFields()

        XCTAssertEqual(summary.outcome, "acceptanceFailed")
        XCTAssertEqual(summary.acceptanceFailures, ["invalidShard:index=4,count=2"])
        XCTAssertTrue(summary.consoleSummary.contains("invalidShard=[invalidShard:index=4,count=2]"))
    }

    func testMilestoneRunSummaryGatesManifestValidationErrors() {
        var summary = MilestoneRunSummary()
        summary.configureRun(
            runID: nil,
            manifestURL: URL(fileURLWithPath: "/tmp/compatibility.json"),
            manifestHash: nil,
            resultLogURL: nil,
            screenshotDirectoryURL: nil,
            resumeEnabled: false,
            strictManifestResumeEnabled: false,
            screenshotFailuresEnabled: false,
            milestoneLimit: nil,
            manifestValidationErrors: [
                "duplicate milestone id giana-title for a.g64 and b.g64"
            ],
            manifestMilestoneCount: 2,
            selectedMilestoneCount: 0,
            missingMediaFiles: [],
            requireAllManifestMedia: false,
            failOnUnclassified: false,
            failOnUnexpected: false
        )

        summary.refreshDerivedFields()

        XCTAssertEqual(summary.outcome, "acceptanceFailed")
        XCTAssertEqual(summary.acceptanceFailures, [
            "manifestValidation:duplicate milestone id giana-title for a.g64 and b.g64"
        ])
        XCTAssertTrue(summary.consoleSummary.contains("manifestValidation=[duplicate milestone id giana-title for a.g64 and b.g64]"))
    }

    func testManifestMilestoneLimitAppliesAfterShardSelection() throws {
        let manifestJSON = """
        {"milestones":[
          {"id":"a","file":"a.g64","mediaType":"g64","driveMode":"compat1541","roadmapPhase":"phase4DriveMedia","actions":[{"type":"typeText","text":"LOAD\\"*\\",8,1"}]},
          {"id":"b","file":"b.g64","mediaType":"g64","driveMode":"compat1541","roadmapPhase":"phase4DriveMedia","actions":[{"type":"typeText","text":"LOAD\\"*\\",8,1"}]},
          {"id":"c","file":"c.g64","mediaType":"g64","driveMode":"compat1541","roadmapPhase":"phase4DriveMedia","actions":[{"type":"typeText","text":"LOAD\\"*\\",8,1"}]},
          {"id":"d","file":"d.g64","mediaType":"g64","driveMode":"compat1541","roadmapPhase":"phase4DriveMedia","actions":[{"type":"typeText","text":"LOAD\\"*\\",8,1"}]}
        ]}
        """
        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(manifestJSON.utf8))
        let sharded = Self.shardedManifestEntries(
            manifest.milestones,
            shardSelection: MilestoneShardSelection(index: 0, count: 2)
        )
        let limited = Self.limitedManifestEntries(sharded, limit: 1)

        XCTAssertEqual(sharded.map(\.id), ["a", "c"])
        XCTAssertEqual(limited.map(\.id), ["a"])
        XCTAssertTrue(Self.limitedManifestEntries(sharded, limit: nil).map(\.id) == ["a", "c"])
        XCTAssertTrue(Self.limitedManifestEntries(sharded, limit: 0).isEmpty)
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

    func testNamedMilestoneCanMatchFramebufferHash() {
        let c64 = C64()
        c64.vic.framebuffer[0] = ColorPalette.rgba[2]
        c64.vic.framebuffer[1] = ColorPalette.rgba[5]
        let expectedHash = CompatibilityHash.framebuffer(
            c64.vic.framebuffer,
            width: VIC.screenWidth,
            height: VIC.screenHeight
        )
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
            colorRAMHash: nil,
            framebufferHash: expectedHash,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertTrue(result.passed, result.reason)
    }

    func testNamedMilestoneRequiresFramebufferHash() {
        let c64 = C64()
        c64.vic.framebuffer[0] = ColorPalette.rgba[2]
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
            colorRAMHash: nil,
            framebufferHash: "1111111111111111",
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .screen)
        XCTAssertTrue(result.reason.contains("framebuffer hash"))
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
        c64.sid.voices[2].control = 0x20
        c64.sid.voices[2].accumulator = 0xA1_0000
        c64.sid.oscillator3Readback = 0xA0
        c64.sid.oscillator3ReadbackValid = true
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
                CompatibilitySIDRegisterExpectation(register: 0xD418, value: 0x0F, mask: 0x0F),
                CompatibilitySIDRegisterExpectation(register: 0xD41B, value: 0xA1, readMode: .chip),
                CompatibilitySIDRegisterExpectation(register: 0xD41B, value: 0xA1)
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
        c64.sid.oscillator3Readback = 0xA0
        c64.sid.oscillator3ReadbackValid = true
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
                CompatibilitySIDRegisterExpectation(register: 0xD418, value: 0x10, mask: 0x1F),
                CompatibilitySIDRegisterExpectation(register: 0xD41B, value: 0xA1, readMode: .chip)
            ],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .timeout)
        XCTAssertTrue(result.reason.contains("SID debug $D418"))
        XCTAssertTrue(result.reason.contains("SID chip $D41B"))
    }

    func testNamedMilestoneCanMatchSIDAudioSignature() {
        let c64 = C64()
        c64.sid.sampleBuffer[0] = -0.5
        c64.sid.sampleBuffer[1] = 0.25
        c64.sid.sampleBuffer[2] = 0.75
        c64.sid.sampleWritePos = 3
        let audioSummary = c64.sid.recentAudioSummary(sampleCount: 3)
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
            sidAudioSignature: CompatibilitySIDAudioSignature(
                sampleCount: 3,
                minimum: -0.5,
                maximum: 0.75,
                sum: 0.5,
                absoluteSum: 1.5,
                mean: 0.166_666_667,
                rootMeanSquare: 0.540_061_724,
                zeroCrossings: 1,
                zeroCrossingRate: audioSummary.zeroCrossingRate,
                lowBandRootMeanSquare: audioSummary.lowBandRootMeanSquare,
                midBandRootMeanSquare: audioSummary.midBandRootMeanSquare,
                highBandRootMeanSquare: audioSummary.highBandRootMeanSquare,
                crestFactor: audioSummary.crestFactor
            ),
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertTrue(result.passed, result.reason)
    }

    func testNamedMilestoneRequiresSIDAudioSignature() {
        let c64 = C64()
        c64.sid.sampleBuffer[0] = -0.5
        c64.sid.sampleBuffer[1] = 0.25
        c64.sid.sampleBuffer[2] = 0.75
        c64.sid.sampleWritePos = 3
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
            sidAudioSignature: CompatibilitySIDAudioSignature(sampleCount: 3, mean: 1.0),
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .sid)
        XCTAssertTrue(result.reason.contains("SID audio.mean"))
    }

    func testNamedMilestoneRequiresSIDAudioSignatureRMS() {
        let c64 = C64()
        c64.sid.sampleBuffer[0] = -0.5
        c64.sid.sampleBuffer[1] = 0.25
        c64.sid.sampleBuffer[2] = 0.75
        c64.sid.sampleWritePos = 3
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
            sidAudioSignature: CompatibilitySIDAudioSignature(sampleCount: 3, rootMeanSquare: 1.0),
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .sid)
        XCTAssertTrue(result.reason.contains("SID audio.rootMeanSquare"))
    }

    func testNamedMilestoneRequiresSIDAudioTextureSignature() {
        let c64 = C64()
        c64.sid.sampleBuffer[0] = -0.5
        c64.sid.sampleBuffer[1] = 0.25
        c64.sid.sampleBuffer[2] = 0.75
        c64.sid.sampleWritePos = 3
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
            sidAudioSignature: CompatibilitySIDAudioSignature(
                sampleCount: 3,
                highBandRootMeanSquare: 1.0,
                crestFactor: 9.0
            ),
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .sid)
        XCTAssertTrue(result.reason.contains("SID audio.highBandRootMeanSquare"))
        XCTAssertTrue(result.reason.contains("SID audio.crestFactor"))
    }

    func testNamedMilestoneCanMatchSIDAudioState() {
        let c64 = C64()
        c64.sid.accuracyMode = .compatibility
        c64.sid.audioAccumulator = 12.5
        c64.sid.audioAccumulatorCount = 2
        c64.sid.audioOutputState = 34.5
        c64.sid.filterLow = 1.25
        c64.sid.filterBand = -2.5
        c64.sid.filterHigh = 3.75
        c64.sid.sampleWritePos = 4
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
            sidAudioState: CompatibilitySIDAudioState(
                accuracyMode: .compatibility,
                sampleCycleCounter: 1,
                cyclesPerSample: c64.sid.cyclesPerSample,
                audioAccumulator: 12.5,
                audioAccumulatorCount: 3,
                audioOutputState: 34.5,
                directOutput: 0,
                filterInput: 0,
                filterOutput: 0,
                mixedOutput: 0,
                externalAudioInput: 0,
                externalAudioPathInput: 0,
                oscillator3Readback: 0,
                oscillator3ReadbackValid: true,
                envelope3Readback: 0,
                envelope3ReadbackValid: true,
                filterLow: 1.25,
                filterBand: -2.5,
                filterHigh: 3.75,
                sampleWritePosition: 4
            ),
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertTrue(result.passed, result.reason)
    }

    func testNamedMilestoneRequiresSIDAudioState() {
        let c64 = C64()
        c64.sid.accuracyMode = .compatibility
        c64.sid.audioOutputState = 34.5
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
            sidAudioState: CompatibilitySIDAudioState(
                accuracyMode: .fast,
                sampleCycleCounter: 123,
                cyclesPerSample: 1,
                audioOutputState: 35.0,
                directOutput: 1,
                filterInput: 2,
                filterOutput: 3,
                mixedOutput: 4,
                externalAudioInput: 5,
                externalAudioPathInput: 6,
                oscillator3Readback: 7,
                oscillator3ReadbackValid: false,
                envelope3Readback: 8,
                envelope3ReadbackValid: false,
                tolerance: 0.1
            ),
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .sid)
        XCTAssertTrue(result.reason.contains("SID audio.state.accuracyMode"))
        XCTAssertTrue(result.reason.contains("SID audio.state.sampleCycleCounter"))
        XCTAssertTrue(result.reason.contains("SID audio.state.cyclesPerSample"))
        XCTAssertTrue(result.reason.contains("SID audio.state.audioOutputState"))
        XCTAssertTrue(result.reason.contains("SID audio.state.directOutput"))
        XCTAssertTrue(result.reason.contains("SID audio.state.filterInput"))
        XCTAssertTrue(result.reason.contains("SID audio.state.filterOutput"))
        XCTAssertTrue(result.reason.contains("SID audio.state.mixedOutput"))
        XCTAssertTrue(result.reason.contains("SID audio.state.externalAudioInput"))
        XCTAssertTrue(result.reason.contains("SID audio.state.externalAudioPathInput"))
        XCTAssertTrue(result.reason.contains("SID audio.state.oscillator3Readback"))
        XCTAssertTrue(result.reason.contains("SID audio.state.oscillator3ReadbackValid"))
        XCTAssertTrue(result.reason.contains("SID audio.state.envelope3Readback"))
        XCTAssertTrue(result.reason.contains("SID audio.state.envelope3ReadbackValid"))
    }

    func testNamedMilestoneCanMatchSIDVoiceState() {
        let c64 = C64()
        c64.sid.voices[0].frequency = 0x1234
        c64.sid.voices[0].pulseWidth = 0x0ABC
        c64.sid.voices[0].control = 0x21
        c64.sid.voices[0].attackDecay = 0xAD
        c64.sid.voices[0].sustainRelease = 0xF6
        c64.sid.voices[0].accumulator = 0xABCDEF
        c64.sid.voices[0].shiftRegister = 0x123456
        c64.sid.voices[0].envelopeLevel = 0x7F
        c64.sid.voices[0].envelopeState = .decay
        c64.sid.voices[0].exponentialCounter = 12
        c64.sid.voices[0].exponentialPeriod = 30
        c64.sid.voices[0].holdZero = true
        c64.sid.voices[0].gate = true
        c64.sid.voices[0].rateCounter = 456
        c64.sid.voices[0].waveformDACOutput = 0x0FED
        c64.sid.voices[0].waveformDACHoldCyclesRemaining = 64
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
            sidVoiceStates: [
                CompatibilitySIDVoiceState(
                    voice: 0,
                    frequency: 0x1234,
                    pulseWidth: 0x0ABC,
                    control: 0x21,
                    attackDecay: 0xAD,
                    sustainRelease: 0xF6,
                    accumulator: 0xABE023,
                    shiftRegister: 0x123456,
                    envelopeLevel: 0x7F,
                    envelopeOutput: 0x86,
                    sustainLevel: 0xFF,
                    envelopeState: "decay",
                    exponentialCounter: 12,
                    exponentialPeriod: 30,
                    holdZero: true,
                    gate: true,
                    rateCounter: 457,
                    selectedRatePeriod: Int(SID.decayReleaseRates[0x0D]),
                    waveformDACOutput: 0x0ABE,
                    waveformDACHoldCyclesRemaining: 128
                )
            ],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertTrue(result.passed, result.reason)
    }

    func testNamedMilestoneRequiresSIDVoiceState() {
        let c64 = C64()
        c64.sid.voices[1].frequency = 0x1234
        c64.sid.voices[1].envelopeState = .attack
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
            sidVoiceStates: [
                CompatibilitySIDVoiceState(
                    voice: 1,
                    frequency: 0x2345,
                    envelopeOutput: 1,
                    envelopeState: "release",
                    oscillatorOutput: 0x123,
                    waveformOutput: 12
                )
            ],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .sid)
        XCTAssertTrue(result.reason.contains("SID voice1.frequency"))
        XCTAssertTrue(result.reason.contains("SID voice1.envelopeOutput"))
        XCTAssertTrue(result.reason.contains("SID voice1.envelopeState"))
        XCTAssertTrue(result.reason.contains("SID voice1.oscillatorOutput"))
        XCTAssertTrue(result.reason.contains("SID voice1.waveformOutput"))
    }

    func testNamedMilestoneAppliesSIDAccuracyMode() {
        let c64 = C64()
        XCTAssertEqual(c64.sid.accuracyMode, .fast)
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
            sidAccuracyMode: .compatibility,
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertTrue(result.passed, result.reason)
        XCTAssertEqual(c64.sid.accuracyMode, .compatibility)
    }

    func testNamedMilestoneAppliesSIDModelOverride() {
        let c64 = C64(machineProfile: .palC64)
        XCTAssertEqual(c64.sid.model, .mos6581)
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
            sidModel: .mos8580,
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertTrue(result.passed, result.reason)
        XCTAssertEqual(c64.sid.model, .mos8580)
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
        XCTAssertEqual(result.category, .vic)
        XCTAssertTrue(result.reason.contains("VIC $D020"))
    }

    func testNamedMilestoneCanMatchVICRegisterSnapshotHash() {
        let c64 = C64()
        c64.vic.writeRegister(0x11, value: 0x3B)
        c64.vic.writeRegister(0x20, value: 0x06)
        let expectedHash = CompatibilityHash.vicRegisterSnapshot(vicRegisterSnapshot(c64.vic))
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/vic.prg"),
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
            vicRegisterSnapshotHash: expectedHash,
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertTrue(result.passed, result.reason)
    }

    func testNamedMilestoneRequiresVICRegisterSnapshotHash() {
        let c64 = C64()
        c64.vic.writeRegister(0x20, value: 0x06)
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/vic.prg"),
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
            vicRegisterSnapshotHash: "1111111111111111",
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .vic)
        XCTAssertTrue(result.reason.contains("VIC registerSnapshotHash"))
    }

    func testNamedMilestoneCanMatchVICState() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 20
        c64.vic.badLine = true
        c64.vic.badLineStartCycle = 12
        c64.vic.badLineDENLatched = true
        c64.vic.displayActive = true
        c64.vic.verticalBorderActive = false
        c64.vic.horizontalBorderActive = false
        c64.vic.rowCounter = 3
        c64.vic.videoCounterBase = 80
        c64.vic.displayLineBufferBase = 40
        c64.vic.spriteMC = [0, 3, 6, 9, 12, 15, 18, 21]
        c64.vic.spriteMCBase = [0, 3, 6, 9, 12, 15, 18, 21]
        c64.vic.spriteYExpFF = [true, false, true, false, true, false, true, false]
        c64.vic.spriteDisplay = [false, true, false, true, false, true, false, true]
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/vic.prg"),
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
            vicState: CompatibilityVICStateExpectation(
                badLine: true,
                badLineStartCycle: 12,
                badLineDENLatched: true,
                displayActive: true,
                verticalBorderActive: false,
                horizontalBorderActive: false,
                rowCounter: 3,
                videoCounterBase: 80,
                displayLineBufferBase: 40,
                spriteMC: [0, 3, 6, 9, 12, 15, 18, 21],
                spriteMCBase: [0, 3, 6, 9, 12, 15, 18, 21],
                spriteYExpFF: [true, false, true, false, true, false, true, false],
                spriteDisplay: [false, true, false, true, false, true, false, true]
            ),
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertTrue(result.passed, result.reason)
    }

    func testNamedMilestoneRequiresVICState() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 20
        c64.vic.rowCounter = 3
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/vic.prg"),
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
            vicState: CompatibilityVICStateExpectation(rowCounter: 4),
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .vic)
        XCTAssertTrue(result.reason.contains("VIC state rowCounter"))
    }

    func testNamedMilestoneCanMatchVICRasterPosition() {
        let c64 = C64()
        c64.vic.rasterLine = 50
        c64.vic.rasterCycle = 16
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/raster.prg"),
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
            vicRasterLine: 50,
            vicRasterCycle: 17,
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertTrue(result.passed, result.reason)
    }

    func testNamedMilestoneRequiresVICRasterPosition() {
        let c64 = C64()
        c64.vic.rasterLine = 50
        c64.vic.rasterCycle = 16
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/raster.prg"),
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
            vicRasterLine: 51,
            vicRasterCycle: 18,
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .vic)
        XCTAssertTrue(result.reason.contains("VIC rasterLine 50 != 51"))
        XCTAssertTrue(result.reason.contains("VIC rasterCycle 17 != 18"))
    }

    func testNamedMilestoneCanMatchVICBusState() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 14
        c64.vic.badLine = true
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/bus.prg"),
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
            vicRasterLine: VIC.displayTop,
            vicRasterCycle: 15,
            vicBALineLow: true,
            vicAECLineLow: true,
            vicBusOwner: .vicBadLine,
            vicBusPhase: CompatibilityVICBusPhaseExpectation(type: .badLineCharacterFetch, column: 0),
            vicLowPhaseAccess: CompatibilityVICLowPhaseAccessExpectation(type: .displayData, column: 0),
            vicLowPhaseMemoryReads: [0x3FFF],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertTrue(result.passed, result.reason)
    }

    func testNamedMilestoneRequiresVICBusState() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 14
        c64.vic.badLine = true
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/bus.prg"),
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
            vicBALineLow: false,
            vicAECLineLow: false,
            vicBusOwner: .cpu,
            vicBusPhase: CompatibilityVICBusPhaseExpectation(type: .cpu),
            vicLowPhaseAccess: CompatibilityVICLowPhaseAccessExpectation(type: .idle),
            vicHighPhaseMemoryReads: [0x1000],
            vicHighPhaseColorRAMReads: [0x0001],
            vicLowPhaseMemoryReads: [0x0400],
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .vic)
        XCTAssertTrue(result.reason.contains("VIC baLineLow true != false"))
        XCTAssertTrue(result.reason.contains("VIC aecLineLow true != false"))
        XCTAssertTrue(result.reason.contains("VIC busOwner vicBadLine != cpu"))
        XCTAssertTrue(result.reason.contains("VIC busPhase badLineCharacterFetch(column:0) != cpu"))
        XCTAssertTrue(result.reason.contains("VIC lowPhaseAccess displayData(column:0) != idle"))
        XCTAssertTrue(result.reason.contains("VIC highPhaseMemoryReads [] != [$1000]"))
        XCTAssertTrue(result.reason.contains("VIC highPhaseColorRAMReads [] != [$0001]"))
        XCTAssertTrue(result.reason.contains("VIC lowPhaseMemoryReads [$3FFF] != [$0400]"))
    }

    func testNamedMilestoneCanRequireNoVICMemoryTraceReads() {
        let c64 = C64()
        c64.vic.rasterLine = UInt16(VIC.displayTop)
        c64.vic.rasterCycle = 14
        c64.vic.badLine = true
        let milestone = LocalMilestone(
            url: URL(fileURLWithPath: "/tmp/bus.prg"),
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
            vicLowPhaseMemoryReads: [],
            vicLowPhaseMemoryReadsSpecified: true,
            screenRAMHash: nil,
            colorRAMHash: nil,
            screenshotName: nil
        )

        let result = runUntilMilestone(c64, milestone: milestone)

        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.category, .vic)
        XCTAssertTrue(result.reason.contains("VIC lowPhaseMemoryReads [$3FFF] != []"))
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
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "drive.minGCRWrites 0 < 1").category, .protectedMedia)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "drive.minGCRWriteSplices 0 < 1").category, .protectedMedia)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "drive.minGCRWriteEraseBits 0 < 1").category, .protectedMedia)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "write head did not create G64 halftrack").category, .protectedMedia)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "media.variableSpeedZoneByteCount 0 != 256").category, .protectedMedia)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "tape.rawPlaybackActive false != true").category, .tape)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "RAM $0801 00 != 01").category, .ram)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "color RAM $0000 00 != 01").category, .screen)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "screen hash abc != def").category, .screen)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "VIC $D020 06 != 02 mask 0F").category, .vic)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "VIC busOwner vicBadLine != cpu").category, .vic)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "SID $D418 0F != 10 mask FF").category, .sid)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "SID audio.sum 0.000000 != 1.000000").category, .sid)
        XCTAssertEqual(MatrixRunResult(passed: false, elapsedCycles: 1, reason: "SID voice1.frequency $1234 != $2345").category, .sid)
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
        let first = CompatibilityMilestone(
            id: "giana-title",
            file: "first.g64",
            command: #"LOAD"*",8,1"#
        )
        let second = CompatibilityMilestone(
            id: "giana-title",
            file: "second.g64",
            command: #"LOAD"$",8"#
        )

        let errors = manifestMilestoneValidationErrors([first, second])

        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("duplicate milestone id giana-title"), errors[0])
        XCTAssertTrue(errors[0].contains("first.g64"), errors[0])
        XCTAssertTrue(errors[0].contains("second.g64"), errors[0])
    }

    func testManifestMilestoneValidationRejectsDuplicateResultKeys() {
        let first = CompatibilityMilestone(file: "demo.g64", command: #"LOAD"*",8,1"#)
        let second = CompatibilityMilestone(file: "demo.g64", command: #"LOAD"*",8,1"#)

        let errors = manifestMilestoneValidationErrors([first, second])

        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("duplicate milestone key"), errors[0])
        XCTAssertTrue(errors[0].contains("demo.g64"), errors[0])
        XCTAssertTrue(errors[0].contains(#"LOAD"*",8,1"#), errors[0])
    }

    func testManifestMilestoneValidationAllowsDistinctModes() {
        let fastLoad = CompatibilityMilestone(
            file: "demo.g64",
            driveMode: .fastLoad,
            command: #"LOAD"*",8,1"#
        )
        let trueDrive = CompatibilityMilestone(
            file: "demo.g64",
            driveMode: .compat1541,
            command: #"LOAD"*",8,1"#
        )

        XCTAssertTrue(manifestMilestoneValidationErrors([fastLoad, trueDrive]).isEmpty)
    }

    func testManifestMilestoneValidationRunsBeforeMediaResolution() {
        let first = CompatibilityMilestone(
            id: "missing-duplicate",
            file: "missing-a.g64",
            command: #"LOAD"*",8,1"#
        )
        let second = CompatibilityMilestone(
            id: "missing-duplicate",
            file: "missing-b.g64",
            command: #"LOAD"*",8,1"#
        )

        let errors = manifestMilestoneValidationErrors([first, second])

        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("missing-a.g64"), errors[0])
        XCTAssertTrue(errors[0].contains("missing-b.g64"), errors[0])
    }

    func testManifestMilestoneValidationCoversEntriesOutsideCurrentFilter() {
        let selectedPhase = CompatibilityMilestone(
            id: "unique-drive",
            file: "selected.g64",
            command: #"LOAD"*",8,1"#,
            roadmapPhase: .phase4DriveMedia
        )
        let hiddenFirst = CompatibilityMilestone(
            id: "duplicate-hidden-by-phase-filter",
            file: "hidden-a.prg",
            command: "RUN",
            roadmapPhase: .phase5SID
        )
        let hiddenSecond = CompatibilityMilestone(
            id: "duplicate-hidden-by-phase-filter",
            file: "hidden-b.prg",
            command: "RUN",
            roadmapPhase: .phase5SID
        )
        let phaseFiltered = Self.phaseFilteredManifestEntries(
            [selectedPhase, hiddenFirst, hiddenSecond],
            selectedPhaseNames: [MilestoneRoadmapPhase.phase4DriveMedia]
        )

        XCTAssertTrue(manifestMilestoneValidationErrors(phaseFiltered).isEmpty)
        XCTAssertEqual(
            manifestMilestoneValidationErrors([selectedPhase, hiddenFirst, hiddenSecond]).count,
            1
        )
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

    private static let diskImageExtensions: Set<String> = ["d64", "g64", "nib", "nbz", "p64"]
    private static let milestoneMediaExtensions: Set<String> = ["prg", "d64", "g64", "nib", "nbz", "p64", "t64", "tap", "crt"]

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
        shouldUseUsefulFeatureMilestoneGate
            || ProcessInfo.processInfo.environment[milestoneFailOnUnclassifiedEnv] == "1"
    }

    private var shouldFailOnUnexpectedMilestoneFailures: Bool {
        shouldUseUsefulFeatureMilestoneGate
            || ProcessInfo.processInfo.environment[milestoneFailOnUnexpectedEnv] == "1"
    }

    private var milestoneFailurePhaseSelection: (valid: [String], invalid: [String]) {
        Self.parseMilestonePhaseSelection(ProcessInfo.processInfo.environment[milestoneFailPhasesEnv])
    }

    private var milestoneSelectedPhaseSelection: (valid: [String], invalid: [String]) {
        usefulFeatureGateSelection.phases
    }

    private var rawMilestoneSelectedPhaseSelection: (valid: [String], invalid: [String]) {
        Self.parseMilestonePhaseSelection(ProcessInfo.processInfo.environment[milestonePhaseFilterEnv])
    }

    private var milestoneRequiredMediaTypeSelection: (valid: [String], invalid: [String]) {
        usefulFeatureGateSelection.mediaTypes
    }

    private var milestoneRequiredMachineProfileSelection: (valid: [String], invalid: [String]) {
        usefulFeatureGateSelection.machineProfiles
    }

    private var milestoneRequiredDriveModeSelection: (valid: [String], invalid: [String]) {
        usefulFeatureGateSelection.driveModes
    }

    private var milestoneRequiredSIDModelSelection: (valid: [String], invalid: [String]) {
        usefulFeatureGateSelection.sidModels
    }

    private var milestoneRequiredSIDAccuracyModeSelection: (valid: [String], invalid: [String]) {
        usefulFeatureGateSelection.sidAccuracyModes
    }

    private var milestoneRequiredObservableTypeSelection: (valid: [String], invalid: [String]) {
        usefulFeatureGateSelection.observableTypes
    }

    private var milestoneRequiredVICProofSelection: (valid: [String], invalid: [String]) {
        Self.parseMilestoneVICProofSelection(ProcessInfo.processInfo.environment[milestoneRequireVICProofsEnv])
    }

    private var milestoneRequiredFailureCategorySelection: (valid: [String], invalid: [String]) {
        usefulFeatureGateSelection.failureCategories
    }

    private var milestoneRequiredActionTypeSelection: (valid: [String], invalid: [String]) {
        usefulFeatureGateSelection.actionTypes
    }

    private var usefulFeatureGateSelection: UsefulFeatureGateSelection {
        Self.usefulFeatureGateSelection(
            explicitPhases: rawMilestoneSelectedPhaseSelection,
            explicitMediaTypes: Self.parseMilestoneMediaTypeSelection(ProcessInfo.processInfo.environment[milestoneRequireMediaTypesEnv]),
            explicitMachineProfiles: Self.parseMilestoneMachineProfileSelection(ProcessInfo.processInfo.environment[milestoneRequireMachineProfilesEnv]),
            explicitDriveModes: Self.parseMilestoneDriveModeSelection(ProcessInfo.processInfo.environment[milestoneRequireDriveModesEnv]),
            explicitSIDModels: Self.parseMilestoneSIDModelSelection(ProcessInfo.processInfo.environment[milestoneRequireSIDModelsEnv]),
            explicitSIDAccuracyModes: Self.parseMilestoneSIDAccuracyModeSelection(ProcessInfo.processInfo.environment[milestoneRequireSIDAccuracyModesEnv]),
            explicitObservableTypes: Self.parseMilestoneObservableTypeSelection(ProcessInfo.processInfo.environment[milestoneRequireObservableTypesEnv]),
            explicitFailureCategories: Self.parseMilestoneFailureCategorySelection(ProcessInfo.processInfo.environment[milestoneRequireFailureCategoriesEnv]),
            explicitActionTypes: Self.parseMilestoneActionTypeSelection(ProcessInfo.processInfo.environment[milestoneRequireActionTypesEnv]),
            enabled: ProcessInfo.processInfo.environment[milestoneUsefulFeatureGateEnv] == "1"
        )
    }

    private static func usefulFeatureGateSelection(
        explicitPhases: (valid: [String], invalid: [String]),
        explicitMediaTypes: (valid: [String], invalid: [String]),
        explicitMachineProfiles: (valid: [String], invalid: [String]),
        explicitDriveModes: (valid: [String], invalid: [String]),
        explicitSIDModels: (valid: [String], invalid: [String]),
        explicitSIDAccuracyModes: (valid: [String], invalid: [String]),
        explicitObservableTypes: (valid: [String], invalid: [String]),
        explicitFailureCategories: (valid: [String], invalid: [String]),
        explicitActionTypes: (valid: [String], invalid: [String]),
        enabled: Bool
    ) -> UsefulFeatureGateSelection {
        guard enabled else {
            return UsefulFeatureGateSelection(
                phases: explicitPhases,
                mediaTypes: explicitMediaTypes,
                machineProfiles: explicitMachineProfiles,
                driveModes: explicitDriveModes,
                sidModels: explicitSIDModels,
                sidAccuracyModes: explicitSIDAccuracyModes,
                observableTypes: explicitObservableTypes,
                failureCategories: explicitFailureCategories,
                actionTypes: explicitActionTypes
            )
        }
        return UsefulFeatureGateSelection(
            phases: mergeSelection(explicitPhases, defaults: usefulFeaturePhaseDefaults),
            mediaTypes: mergeSelection(explicitMediaTypes, defaults: usefulFeatureMediaTypeDefaults),
            machineProfiles: mergeSelection(explicitMachineProfiles, defaults: usefulFeatureMachineProfileDefaults),
            driveModes: mergeSelection(explicitDriveModes, defaults: usefulFeatureDriveModeDefaults),
            sidModels: mergeSelection(explicitSIDModels, defaults: usefulFeatureSIDModelDefaults),
            sidAccuracyModes: mergeSelection(explicitSIDAccuracyModes, defaults: usefulFeatureSIDAccuracyModeDefaults),
            observableTypes: mergeSelection(explicitObservableTypes, defaults: usefulFeatureObservableTypeDefaults),
            failureCategories: mergeSelection(explicitFailureCategories, defaults: usefulFeatureFailureCategoryDefaults),
            actionTypes: mergeSelection(explicitActionTypes, defaults: usefulFeatureActionTypeDefaults)
        )
    }

    private static func mergeSelection(
        _ explicit: (valid: [String], invalid: [String]),
        defaults: [String]
    ) -> (valid: [String], invalid: [String]) {
        var merged = explicit.valid
        var seen = Set(merged)
        for value in defaults where seen.insert(value).inserted {
            merged.append(value)
        }
        return (merged, explicit.invalid)
    }

    private static func parseMilestonePhaseSelection(_ value: String?) -> (valid: [String], invalid: [String]) {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], [])
        }
        var valid: [String] = []
        var invalid: [String] = []
        var seenValid = Set<String>()
        var seenInvalid = Set<String>()
        let phaseNames = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for phaseName in phaseNames {
            if MilestoneRoadmapPhase.gateablePhases.contains(phaseName) {
                if seenValid.insert(phaseName).inserted {
                    valid.append(phaseName)
                }
            } else if seenInvalid.insert(phaseName).inserted {
                invalid.append(phaseName)
            }
        }
        return (valid, invalid)
    }

    private static func parseMilestoneIDSelection(_ value: String?) -> [String] {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        var selectedIDs: [String] = []
        var seenIDs = Set<String>()
        let ids = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for id in ids where seenIDs.insert(id).inserted {
            selectedIDs.append(id)
        }
        return selectedIDs
    }

    private static func parseMilestoneShardSelection(indexValue: String?, countValue: String?) -> MilestoneShardSelection {
        let trimmedIndex = indexValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedCount = countValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedIndex.isEmpty || !trimmedCount.isEmpty else {
            return MilestoneShardSelection()
        }
        guard let shardIndex = Int(trimmedIndex),
              let shardCount = Int(trimmedCount),
              shardCount > 0,
              shardIndex >= 0,
              shardIndex < shardCount else {
            return MilestoneShardSelection(
                index: Int(trimmedIndex),
                count: Int(trimmedCount),
                invalidReason: "invalidShard:index=\(trimmedIndex.isEmpty ? "missing" : trimmedIndex),count=\(trimmedCount.isEmpty ? "missing" : trimmedCount)"
            )
        }
        return MilestoneShardSelection(index: shardIndex, count: shardCount)
    }

    private static func parseMilestoneMediaTypeSelection(_ value: String?) -> (valid: [String], invalid: [String]) {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], [])
        }
        let acceptedMediaTypes = Set(compatibilityMediaTypeNames)
        var valid: [String] = []
        var invalid: [String] = []
        var seenValid = Set<String>()
        var seenInvalid = Set<String>()
        let mediaTypes = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        for mediaType in mediaTypes {
            if acceptedMediaTypes.contains(mediaType) {
                if seenValid.insert(mediaType).inserted {
                    valid.append(mediaType)
                }
            } else if seenInvalid.insert(mediaType).inserted {
                invalid.append(mediaType)
            }
        }
        return (valid, invalid)
    }

    private static func parseMilestoneMachineProfileSelection(_ value: String?) -> (valid: [String], invalid: [String]) {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], [])
        }
        let acceptedProfiles = Set(compatibilityMachineProfileNames)
        var valid: [String] = []
        var invalid: [String] = []
        var seenValid = Set<String>()
        var seenInvalid = Set<String>()
        let profiles = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for profile in profiles {
            if acceptedProfiles.contains(profile) {
                if seenValid.insert(profile).inserted {
                    valid.append(profile)
                }
            } else if seenInvalid.insert(profile).inserted {
                invalid.append(profile)
            }
        }
        return (valid, invalid)
    }

    private static func parseMilestoneDriveModeSelection(_ value: String?) -> (valid: [String], invalid: [String]) {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], [])
        }
        let acceptedDriveModes = Set(compatibilityDriveModeNames)
        var valid: [String] = []
        var invalid: [String] = []
        var seenValid = Set<String>()
        var seenInvalid = Set<String>()
        let driveModes = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for driveMode in driveModes {
            if acceptedDriveModes.contains(driveMode) {
                if seenValid.insert(driveMode).inserted {
                    valid.append(driveMode)
                }
            } else if seenInvalid.insert(driveMode).inserted {
                invalid.append(driveMode)
            }
        }
        return (valid, invalid)
    }

    private static func parseMilestoneSIDModelSelection(_ value: String?) -> (valid: [String], invalid: [String]) {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], [])
        }
        let acceptedModels = Set(sidModelNames)
        var valid: [String] = []
        var invalid: [String] = []
        var seenValid = Set<String>()
        var seenInvalid = Set<String>()
        let models = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for model in models {
            if acceptedModels.contains(model) {
                if seenValid.insert(model).inserted {
                    valid.append(model)
                }
            } else if seenInvalid.insert(model).inserted {
                invalid.append(model)
            }
        }
        return (valid, invalid)
    }

    private static func parseMilestoneSIDAccuracyModeSelection(_ value: String?) -> (valid: [String], invalid: [String]) {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], [])
        }
        let acceptedModes = Set(sidAccuracyModeNames)
        var valid: [String] = []
        var invalid: [String] = []
        var seenValid = Set<String>()
        var seenInvalid = Set<String>()
        let modes = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for mode in modes {
            if acceptedModes.contains(mode) {
                if seenValid.insert(mode).inserted {
                    valid.append(mode)
                }
            } else if seenInvalid.insert(mode).inserted {
                invalid.append(mode)
            }
        }
        return (valid, invalid)
    }

    private static func parseMilestoneObservableTypeSelection(_ value: String?) -> (valid: [String], invalid: [String]) {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], [])
        }
        let acceptedTypes = Set(milestoneObservableTypeNames)
        var valid: [String] = []
        var invalid: [String] = []
        var seenValid = Set<String>()
        var seenInvalid = Set<String>()
        let observableTypes = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for observableType in observableTypes {
            if acceptedTypes.contains(observableType) {
                if seenValid.insert(observableType).inserted {
                    valid.append(observableType)
                }
            } else if seenInvalid.insert(observableType).inserted {
                invalid.append(observableType)
            }
        }
        return (valid, invalid)
    }

    private static func parseMilestoneVICProofSelection(_ value: String?) -> (valid: [String], invalid: [String]) {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], [])
        }
        let acceptedTypes = Set(milestoneVICProofTypeNames)
        var valid: [String] = []
        var invalid: [String] = []
        var seenValid = Set<String>()
        var seenInvalid = Set<String>()
        let proofTypes = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for proofType in proofTypes {
            if acceptedTypes.contains(proofType) {
                if seenValid.insert(proofType).inserted {
                    valid.append(proofType)
                }
            } else if seenInvalid.insert(proofType).inserted {
                invalid.append(proofType)
            }
        }
        return (valid, invalid)
    }

    private static func parseMilestoneFailureCategorySelection(_ value: String?) -> (valid: [String], invalid: [String]) {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], [])
        }
        let acceptedCategories = Set(milestoneFailureCategoryNames)
        var valid: [String] = []
        var invalid: [String] = []
        var seenValid = Set<String>()
        var seenInvalid = Set<String>()
        let categories = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for category in categories {
            if acceptedCategories.contains(category) {
                if seenValid.insert(category).inserted {
                    valid.append(category)
                }
            } else if seenInvalid.insert(category).inserted {
                invalid.append(category)
            }
        }
        return (valid, invalid)
    }

    private static func parseMilestoneActionTypeSelection(_ value: String?) -> (valid: [String], invalid: [String]) {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], [])
        }
        let acceptedTypes = Set(milestoneActionTypeNames)
        var valid: [String] = []
        var invalid: [String] = []
        var seenValid = Set<String>()
        var seenInvalid = Set<String>()
        let actionTypes = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for actionType in actionTypes {
            if acceptedTypes.contains(actionType) {
                if seenValid.insert(actionType).inserted {
                    valid.append(actionType)
                }
            } else if seenInvalid.insert(actionType).inserted {
                invalid.append(actionType)
            }
        }
        return (valid, invalid)
    }

    private enum MilestoneActionType {
        static let typeText = "typeText"
        static let waitCycles = "waitCycles"
        static let joystickDown = "joystickDown"
        static let joystickUp = "joystickUp"
        static let keyDown = "keyDown"
        static let keyUp = "keyUp"
        static let startTape = "startTape"
        static let stopTape = "stopTape"
    }

    private static let milestoneActionTypeNames = [
        MilestoneActionType.typeText,
        MilestoneActionType.waitCycles,
        MilestoneActionType.joystickDown,
        MilestoneActionType.joystickUp,
        MilestoneActionType.keyDown,
        MilestoneActionType.keyUp,
        MilestoneActionType.startTape,
        MilestoneActionType.stopTape,
    ]

    private enum MilestoneObservableType {
        static let pc = "pc"
        static let drive = "drive"
        static let media = "media"
        static let lowLevelTrack = "lowLevelTrack"
        static let tape = "tape"
        static let ram = "ram"
        static let colorRAM = "colorRAM"
        static let cpu = "cpu"
        static let sid = "sid"
        static let vic = "vic"
        static let cia = "cia"
        static let screen = "screen"
        static let framebuffer = "framebuffer"
    }

    private enum MilestoneVICProofType {
        static let registers = "registers"
        static let state = "state"
        static let raster = "raster"
        static let bus = "bus"
        static let memoryTrace = "memoryTrace"
        static let framebuffer = "framebuffer"
        static let requiredPhase3Proofs = [
            registers,
            state,
            raster,
            bus,
            memoryTrace,
            framebuffer,
        ]
    }

    private static let milestoneVICProofTypeNames = [
        MilestoneVICProofType.registers,
        MilestoneVICProofType.state,
        MilestoneVICProofType.raster,
        MilestoneVICProofType.bus,
        MilestoneVICProofType.memoryTrace,
        MilestoneVICProofType.framebuffer,
    ]

    private static let milestoneObservableTypeNames = [
        MilestoneObservableType.pc,
        MilestoneObservableType.drive,
        MilestoneObservableType.media,
        MilestoneObservableType.lowLevelTrack,
        MilestoneObservableType.tape,
        MilestoneObservableType.ram,
        MilestoneObservableType.colorRAM,
        MilestoneObservableType.cpu,
        MilestoneObservableType.sid,
        MilestoneObservableType.vic,
        MilestoneObservableType.cia,
        MilestoneObservableType.screen,
        MilestoneObservableType.framebuffer,
    ]

    private static let milestoneFailureCategoryNames = [
        CompatibilityFailureCategory.cpu.rawValue,
        CompatibilityFailureCategory.vic.rawValue,
        CompatibilityFailureCategory.sid.rawValue,
        CompatibilityFailureCategory.drive.rawValue,
        CompatibilityFailureCategory.media.rawValue,
        CompatibilityFailureCategory.protectedMedia.rawValue,
        CompatibilityFailureCategory.cartridge.rawValue,
        CompatibilityFailureCategory.app.rawValue,
        CompatibilityFailureCategory.pc.rawValue,
        CompatibilityFailureCategory.ram.rawValue,
        CompatibilityFailureCategory.screen.rawValue,
        CompatibilityFailureCategory.tape.rawValue,
        CompatibilityFailureCategory.cia.rawValue,
        CompatibilityFailureCategory.emulator.rawValue,
        CompatibilityFailureCategory.timeout.rawValue,
    ]

    private static let compatibilityMediaTypeNames = [
        CompatibilityMediaType.prg.rawValue,
        CompatibilityMediaType.d64.rawValue,
        CompatibilityMediaType.g64.rawValue,
        CompatibilityMediaType.nib.rawValue,
        CompatibilityMediaType.nbz.rawValue,
        CompatibilityMediaType.p64.rawValue,
        CompatibilityMediaType.t64.rawValue,
        CompatibilityMediaType.tap.rawValue,
        CompatibilityMediaType.crt.rawValue,
    ]

    private static let compatibilityMachineProfileNames = [
        CompatibilityMachineProfile.palC64.rawValue,
        CompatibilityMachineProfile.palC64C.rawValue,
        CompatibilityMachineProfile.palC64With1541II.rawValue,
        CompatibilityMachineProfile.palC64CWith1541II.rawValue,
        CompatibilityMachineProfile.ntscC64.rawValue,
        CompatibilityMachineProfile.ntscC64C.rawValue,
        CompatibilityMachineProfile.ntscC64With1541II.rawValue,
        CompatibilityMachineProfile.ntscC64CWith1541II.rawValue,
    ]

    private static let compatibilityDriveModeNames = [
        CompatibilityDriveMode.fastLoad.rawValue,
        CompatibilityDriveMode.compat1541.rawValue,
        CompatibilityDriveMode.standard1541.rawValue,
    ]

    private static let sidModelNames = [
        SID.Model.mos6581.rawValue,
        SID.Model.mos8580.rawValue,
    ]

    private static let sidAccuracyModeNames = [
        SID.AccuracyMode.fast.rawValue,
        SID.AccuracyMode.compatibility.rawValue,
    ]

    private struct UsefulFeatureGateSelection {
        var phases: (valid: [String], invalid: [String])
        var mediaTypes: (valid: [String], invalid: [String])
        var machineProfiles: (valid: [String], invalid: [String])
        var driveModes: (valid: [String], invalid: [String])
        var sidModels: (valid: [String], invalid: [String])
        var sidAccuracyModes: (valid: [String], invalid: [String])
        var observableTypes: (valid: [String], invalid: [String])
        var failureCategories: (valid: [String], invalid: [String])
        var actionTypes: (valid: [String], invalid: [String])
    }

    private static let usefulFeaturePhaseDefaults = [
        MilestoneRoadmapPhase.phase4DriveMedia,
        MilestoneRoadmapPhase.phase5SID,
        MilestoneRoadmapPhase.phase6CIAInputTape,
        MilestoneRoadmapPhase.phase7CartridgeExpansion,
    ]

    private static let usefulFeatureMediaTypeDefaults = [
        CompatibilityMediaType.prg.rawValue,
        CompatibilityMediaType.d64.rawValue,
        CompatibilityMediaType.g64.rawValue,
        CompatibilityMediaType.tap.rawValue,
        CompatibilityMediaType.crt.rawValue,
    ]

    private static let usefulFeatureMachineProfileDefaults = [
        CompatibilityMachineProfile.palC64.rawValue,
        CompatibilityMachineProfile.palC64C.rawValue,
        CompatibilityMachineProfile.ntscC64.rawValue,
        CompatibilityMachineProfile.ntscC64C.rawValue,
    ]

    private static let usefulFeatureDriveModeDefaults = [
        CompatibilityDriveMode.compat1541.rawValue,
        CompatibilityDriveMode.standard1541.rawValue,
    ]

    private static let usefulFeatureSIDModelDefaults = [
        SID.Model.mos6581.rawValue,
        SID.Model.mos8580.rawValue,
    ]

    private static let usefulFeatureSIDAccuracyModeDefaults = [
        SID.AccuracyMode.compatibility.rawValue,
    ]

    private static let usefulFeatureObservableTypeDefaults = [
        MilestoneObservableType.pc,
        MilestoneObservableType.drive,
        MilestoneObservableType.media,
        MilestoneObservableType.sid,
        MilestoneObservableType.vic,
        MilestoneObservableType.tape,
        MilestoneObservableType.screen,
        MilestoneObservableType.framebuffer,
    ]

    private static let usefulFeatureFailureCategoryDefaults = [
        CompatibilityFailureCategory.drive.rawValue,
        CompatibilityFailureCategory.protectedMedia.rawValue,
        CompatibilityFailureCategory.sid.rawValue,
        CompatibilityFailureCategory.vic.rawValue,
        CompatibilityFailureCategory.tape.rawValue,
        CompatibilityFailureCategory.cartridge.rawValue,
    ]

    private static let usefulFeatureActionTypeDefaults = [
        MilestoneActionType.typeText,
        MilestoneActionType.waitCycles,
        MilestoneActionType.joystickDown,
        MilestoneActionType.joystickUp,
        MilestoneActionType.keyDown,
        MilestoneActionType.keyUp,
        MilestoneActionType.startTape,
    ]

    private var shouldUseUsefulFeatureMilestoneGate: Bool {
        ProcessInfo.processInfo.environment[milestoneUsefulFeatureGateEnv] == "1"
    }

    private var shouldRequireAllMilestoneMedia: Bool {
        ProcessInfo.processInfo.environment[milestoneRequireAllMediaEnv] == "1"
    }

    private var shouldRequireSelectedMilestonePhases: Bool {
        shouldUseUsefulFeatureMilestoneGate
            || ProcessInfo.processInfo.environment[milestoneRequirePhaseFilterMatchesEnv] == "1"
    }

    private var shouldRequireSelectedMilestoneIDs: Bool {
        ProcessInfo.processInfo.environment[milestoneRequireIDFilterMatchesEnv] == "1"
    }

    private var shouldRequireMilestoneManifest: Bool {
        shouldUseUsefulFeatureMilestoneGate
            || ProcessInfo.processInfo.environment[milestoneRequireManifestEnv] == "1"
    }

    private var shouldRequireRoadmapPhasesForManifestMilestones: Bool {
        shouldUseUsefulFeatureMilestoneGate
            || ProcessInfo.processInfo.environment[milestoneRequireRoadmapPhasesEnv] == "1"
    }

    private var shouldRequireIDsForManifestMilestones: Bool {
        shouldUseUsefulFeatureMilestoneGate
            || ProcessInfo.processInfo.environment[milestoneRequireIDsEnv] == "1"
    }

    private var shouldRequireExpectedFailureNotesForManifestMilestones: Bool {
        shouldUseUsefulFeatureMilestoneGate
            || ProcessInfo.processInfo.environment[milestoneRequireExpectedFailureNotesEnv] == "1"
    }

    private var shouldRequireExpectedFailureReasonsForManifestMilestones: Bool {
        shouldUseUsefulFeatureMilestoneGate
            || ProcessInfo.processInfo.environment[milestoneRequireExpectedFailureReasonsEnv] == "1"
    }

    private var shouldRequireMaxCyclesForManifestMilestones: Bool {
        shouldUseUsefulFeatureMilestoneGate
            || ProcessInfo.processInfo.environment[milestoneRequireMaxCyclesEnv] == "1"
    }

    private var shouldRequireExplicitActionsForManifestMilestones: Bool {
        shouldUseUsefulFeatureMilestoneGate
            || ProcessInfo.processInfo.environment[milestoneRequireExplicitActionsEnv] == "1"
    }

    private var shouldRequireObservableExpectationsForManifestMilestones: Bool {
        shouldUseUsefulFeatureMilestoneGate
            || ProcessInfo.processInfo.environment[milestoneRequireObservableExpectationsEnv] == "1"
    }

    private var shouldRequirePhase3VICProofsForManifestMilestones: Bool {
        ProcessInfo.processInfo.environment[milestoneRequirePhase3VICProofsEnv] == "1"
    }

    private var shouldRequireFramebufferScreenshotsForManifestMilestones: Bool {
        ProcessInfo.processInfo.environment[milestoneRequireFramebufferScreenshotsEnv] == "1"
    }

    private var shouldRejectPlaceholderProofHashesForManifestMilestones: Bool {
        ProcessInfo.processInfo.environment[milestoneRejectPlaceholderProofHashesEnv] == "1"
    }

    private var localMilestoneLimit: Int? {
        Int(ProcessInfo.processInfo.environment["SWIFT64_LOCAL_MILESTONE_LIMIT"] ?? "")
    }

    private var milestoneSelectedIDSelection: [String] {
        Self.parseMilestoneIDSelection(ProcessInfo.processInfo.environment[milestoneIDFilterEnv])
    }

    private var milestoneShardSelection: MilestoneShardSelection {
        Self.parseMilestoneShardSelection(
            indexValue: ProcessInfo.processInfo.environment[milestoneShardIndexEnv],
            countValue: ProcessInfo.processInfo.environment[milestoneShardCountEnv]
        )
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
        c64.sidModelOverride = milestone.sidModel
        if let sidAccuracyMode = milestone.sidAccuracyMode {
            c64.sid.accuracyMode = sidAccuracyMode
        }

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
            let gcrWrites = driveStatus.gcrWriteByteCount - baseline.gcrWriteByteCount
            let gcrWriteSplices = driveStatus.gcrWriteSpliceCount - baseline.gcrWriteSpliceCount
            let gcrWriteEraseBits = driveStatus.gcrWriteEraseBitCount - baseline.gcrWriteEraseBitCount
            let pcReached = milestone.pcRanges.isEmpty || milestone.pcRanges.contains { $0.contains(c64.cpu.pc) }
            let driveProgress = gcrReads >= milestone.minGCRReads && byteReady >= milestone.minByteReady
            let driveExpectationMatches = milestone.driveStatus.map { expectation in
                driveStatusMismatches(
                    expectation,
                    snapshot: driveStatus,
                    status: c64.emulationStatus,
                    gcrReads: gcrReads,
                    byteReady: byteReady,
                    syncDetections: syncDetections,
                    weakBitReads: weakBitReads,
                    variableSpeedZoneSamples: variableSpeedZoneSamples,
                    gcrWrites: gcrWrites,
                    gcrWriteSplices: gcrWriteSplices,
                    gcrWriteEraseBits: gcrWriteEraseBits
                ).isEmpty
            } ?? true
            let mediaExpectationMatches = milestone.mediaStatus.map { expectation in
                mediaStatusMismatches(expectation, capabilities: c64.emulationStatus.mediaCapabilities).isEmpty
            } ?? true
            let lowLevelTrackMatches = lowLevelTrackMismatches(
                milestone.lowLevelTracks,
                disk: c64.drive1541.disk
            ).isEmpty
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
            let sidMatches = sidRegisterMismatches(milestone.sidRegisters, sid: c64.sid).isEmpty
            let sidAudioMatches = milestone.sidAudioSignature.map {
                sidAudioSignatureMismatches($0, sid: c64.sid).isEmpty
            } ?? true
            let sidAudioStateMatches = milestone.sidAudioState.map {
                sidAudioStateMismatches($0, sid: c64.sid).isEmpty
            } ?? true
            let sidVoiceStateMatches = sidVoiceStateMismatches(milestone.sidVoiceStates, sid: c64.sid).isEmpty
            let vicMatches = milestone.vicRegisters.allSatisfy { expectation in
                let actual = c64.vic.debugRegisterValue(UInt16(truncatingIfNeeded: expectation.register))
                return (actual & expectation.mask) == (expectation.value & expectation.mask)
            }
            let vicRegisterSnapshotHashMatches = milestone.vicRegisterSnapshotHash.map {
                CompatibilityHash.vicRegisterSnapshot(vicRegisterSnapshot(c64.vic)).caseInsensitiveCompare($0) == .orderedSame
            } ?? true
            let vicStateMatches = vicStateMismatches(milestone.vicState, vic: c64.vic).isEmpty
            let vicRasterLineMatches = milestone.vicRasterLine.map { Int(c64.vic.rasterLine) == $0 } ?? true
            let vicRasterCycleMatches = milestone.vicRasterCycle.map { c64.vic.rasterCycle == $0 } ?? true
            let vicBusMatches = vicBusMismatches(
                expectedBALineLow: milestone.vicBALineLow,
                expectedAECLineLow: milestone.vicAECLineLow,
                expectedBusOwner: milestone.vicBusOwner,
                expectedBusPhase: milestone.vicBusPhase,
                expectedLowPhaseAccess: milestone.vicLowPhaseAccess,
                vic: c64.vic
            ).isEmpty
            let vicMemoryTraceMatches = vicMemoryTraceMismatches(
                highPhaseMemoryReads: milestone.vicHighPhaseMemoryReads,
                highPhaseMemoryReadsSpecified: milestone.vicHighPhaseMemoryReadsSpecified,
                highPhaseColorRAMReads: milestone.vicHighPhaseColorRAMReads,
                highPhaseColorRAMReadsSpecified: milestone.vicHighPhaseColorRAMReadsSpecified,
                lowPhaseMemoryReads: milestone.vicLowPhaseMemoryReads,
                lowPhaseMemoryReadsSpecified: milestone.vicLowPhaseMemoryReadsSpecified,
                vic: c64.vic
            ).isEmpty
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
            let framebufferHashMatches = milestone.framebufferHash.map {
                CompatibilityHash.framebuffer(
                    c64.vic.framebuffer,
                    width: VIC.screenWidth,
                    height: VIC.screenHeight
                ).caseInsensitiveCompare($0) == .orderedSame
            } ?? true
            let screenTextMatches = milestone.screenTextContains.allSatisfy {
                screenText(c64.memory.ram).localizedCaseInsensitiveContains($0)
            }

            if pcReached
                && driveProgress
                && driveExpectationMatches
                && mediaExpectationMatches
                && lowLevelTrackMatches
                && tapeExpectationMatches
                && ramMatches
                && colorRAMMatches
                && cpuMatches
                && sidMatches
                && sidAudioMatches
                && sidAudioStateMatches
                && sidVoiceStateMatches
                && vicMatches
                && vicRegisterSnapshotHashMatches
                && vicStateMatches
                && vicRasterLineMatches
                && vicRasterCycleMatches
                && vicBusMatches
                && vicMemoryTraceMatches
                && cia1Matches
                && cia2Matches
                && screenTextMatches
                && screenMatches
                && colorRAMHashMatches
                && framebufferHashMatches {
                return MatrixRunResult(passed: true, elapsedCycles: c64.cpu.totalCycles, reason: "named milestone reached")
            }
        }

        return MatrixRunResult(
            passed: false,
            elapsedCycles: c64.cpu.totalCycles,
            reason: namedMilestoneFailureReason(c64, milestone: milestone, baseline: baseline)
        )
    }

    private func localMilestoneLoadResult() throws -> MilestoneLoadResult {
        let urls = try localMediaURLs(limitEnv: milestoneMediaLimitEnv, extensions: Self.milestoneMediaExtensions)
        let manifestLoad = try loadManifestMilestones(urls: urls)
        if !manifestLoad.milestones.isEmpty {
            return manifestLoad
        }
        if !manifestLoad.selectedMilestoneIDs.isEmpty {
            return manifestLoad
        }
        let phaseSelection = milestoneSelectedPhaseSelection
        if !phaseSelection.valid.isEmpty && !phaseSelection.valid.contains(MilestoneRoadmapPhase.phase4DriveMedia) {
            return MilestoneLoadResult(
                selectedPhaseNames: phaseSelection.valid,
                invalidSelectedPhaseNames: phaseSelection.invalid,
                selectedPhaseCounts: Dictionary(uniqueKeysWithValues: phaseSelection.valid.map { ($0, 0) }),
                missingSelectedPhaseNames: phaseSelection.valid
            )
        }

        guard let giana = urls.first(where: {
            $0.lastPathComponent.lowercased().contains("great_giana_sisters")
            && $0.pathExtension.lowercased() == "g64"
        }) else {
            return MilestoneLoadResult(
                phaseFilteredMilestoneCount: phaseSelection.valid.isEmpty ? nil : 0,
                selectedPhaseNames: phaseSelection.valid,
                invalidSelectedPhaseNames: phaseSelection.invalid,
                selectedPhaseCounts: Dictionary(uniqueKeysWithValues: phaseSelection.valid.map { ($0, 0) }),
                missingSelectedPhaseNames: phaseSelection.valid
            )
        }

        let fallbackPhaseCounts = phaseSelection.valid.isEmpty
            ? [:]
            : [MilestoneRoadmapPhase.phase4DriveMedia: 1]
        let fallbackMilestones = Self.limitedMilestones([
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
                sidModel: nil,
                sidRegisters: [],
                sidVoiceStates: [],
                vicRegisters: [],
                cia1Registers: [],
                cia2Registers: [],
                screenTextContains: [],
                screenRAMHash: nil,
                colorRAMHash: nil,
                screenshotName: nil,
                roadmapPhase: MilestoneRoadmapPhase.phase4DriveMedia,
                expectedFailure: nil
            )
        ], limit: localMilestoneLimit)
        return MilestoneLoadResult(
            milestones: fallbackMilestones,
            postShardMilestoneCount: 1,
            manifestPhaseCounts: [MilestoneRoadmapPhase.phase4DriveMedia: 1],
            manifestMediaCounts: [CompatibilityMediaType.g64.rawValue: 1],
            manifestMachineProfileCounts: [CompatibilityMachineProfile.palC64.rawValue: 1],
            manifestDriveModeCounts: [CompatibilityDriveMode.compat1541.rawValue: 1],
            manifestObservableTypeCounts: [MilestoneObservableType.drive: 1],
            manifestVICProofCounts: [:],
            manifestActionTypeCounts: [MilestoneActionType.typeText: 1],
            manifestUntaggedMilestoneCount: 0,
            manifestUnnamedMilestoneCount: 0,
            manifestExpectedFailureCount: 0,
            manifestExpectedFailuresWithoutNotesCount: 0,
            manifestExpectedFailuresWithoutReasonMarkersCount: 0,
            manifestMilestonesWithoutMaxCyclesCount: 0,
            manifestMilestonesWithoutExplicitActionsCount: 0,
            manifestMilestonesWithoutObservableExpectationsCount: 0,
            manifestPhase3MilestonesWithoutVICProofCount: 0,
            manifestPhase3MilestonesMissingRequiredVICProofsCount: 0,
            manifestFramebufferHashMilestonesWithoutScreenshotNamesCount: 0,
            manifestFramebufferScreenshotFilenameCollisionCount: 0,
            manifestFramebufferScreenshotFilenameCollisions: [],
            manifestPlaceholderProofHashCount: 0,
            phaseFilteredMilestoneCount: phaseSelection.valid.isEmpty ? nil : 1,
            selectedMediaCounts: Self.mediaCounts(for: fallbackMilestones),
            selectedMachineProfileCounts: Self.machineProfileCounts(for: fallbackMilestones),
            selectedDriveModeCounts: Self.driveModeCounts(for: fallbackMilestones),
            selectedObservableTypeCounts: Self.observableTypeCounts(for: fallbackMilestones),
            selectedVICProofCounts: Self.vicProofCounts(for: fallbackMilestones),
            selectedActionTypeCounts: Self.actionTypeCounts(for: fallbackMilestones),
            selectedPhaseNames: phaseSelection.valid,
            invalidSelectedPhaseNames: phaseSelection.invalid,
            selectedPhaseCounts: fallbackPhaseCounts,
            missingSelectedPhaseNames: phaseSelection.valid.filter {
                fallbackPhaseCounts[$0, default: 0] == 0
            }
        )
    }

    private func loadManifestMilestones(urls: [URL]) throws -> MilestoneLoadResult {
        let manifestURL = localDiskRoot.appendingPathComponent("compatibility.json")
        let idSelection = milestoneSelectedIDSelection
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return MilestoneLoadResult(
                selectedMilestoneIDs: idSelection,
                missingSelectedMilestoneIDs: idSelection
            )
        }

        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(contentsOf: manifestURL))
        let validationErrors = manifestMilestoneValidationErrors(manifest.milestones)
        guard validationErrors.isEmpty else {
            throw ManifestValidationError(errors: validationErrors)
        }
        let phaseSelection = milestoneSelectedPhaseSelection
        let shardSelection = milestoneShardSelection
        let manifestPhaseCounts = Self.phaseCounts(for: manifest.milestones)
        let manifestMediaCounts = Self.mediaCounts(for: manifest.milestones)
        let manifestMachineProfileCounts = Self.machineProfileCounts(for: manifest.milestones)
        let manifestDriveModeCounts = Self.driveModeCounts(for: manifest.milestones)
        let manifestSIDModelCounts = Self.sidModelCounts(for: manifest.milestones)
        let manifestSIDAccuracyModeCounts = Self.sidAccuracyModeCounts(for: manifest.milestones)
        let manifestObservableTypeCounts = Self.observableTypeCounts(for: manifest.milestones)
        let manifestVICProofCounts = Self.vicProofCounts(for: manifest.milestones)
        let manifestExpectedFailureCategoryCounts = Self.expectedFailureCategoryCounts(for: manifest.milestones)
        let manifestActionTypeCounts = Self.actionTypeCounts(for: manifest.milestones)
        let manifestUntaggedMilestoneCount = Self.untaggedPhaseCount(in: manifest.milestones)
        let manifestUnnamedMilestoneCount = Self.unnamedMilestoneCount(in: manifest.milestones)
        let manifestExpectedFailureCount = Self.expectedFailureCount(in: manifest.milestones)
        let manifestExpectedFailuresWithoutNotesCount = Self.expectedFailuresWithoutNotesCount(in: manifest.milestones)
        let manifestExpectedFailuresWithoutReasonMarkersCount = Self.expectedFailuresWithoutReasonMarkersCount(in: manifest.milestones)
        let manifestMilestonesWithoutMaxCyclesCount = Self.milestonesWithoutMaxCyclesCount(in: manifest.milestones)
        let manifestMilestonesWithoutExplicitActionsCount = Self.milestonesWithoutExplicitActionsCount(in: manifest.milestones)
        let manifestMilestonesWithoutObservableExpectationsCount = Self.milestonesWithoutObservableExpectationsCount(in: manifest.milestones)
        let manifestPhase3MilestonesWithoutVICProofCount = Self.phase3MilestonesWithoutVICProofCount(in: manifest.milestones)
        let manifestPhase3MilestonesMissingRequiredVICProofsCount = Self.phase3MilestonesMissingRequiredVICProofsCount(in: manifest.milestones)
        let manifestFramebufferHashMilestonesWithoutScreenshotNamesCount = Self.framebufferHashMilestonesWithoutScreenshotNamesCount(in: manifest.milestones)
        let manifestFramebufferScreenshotFilenameCollisions = Self.framebufferScreenshotFilenameCollisions(in: manifest.milestones)
        let manifestPlaceholderProofHashCount = Self.placeholderProofHashCount(in: manifest.milestones)
        let phaseFilteredEntries = Self.phaseFilteredManifestEntries(
            manifest.milestones,
            selectedPhaseNames: phaseSelection.valid
        )
        let idFilteredEntries = Self.idFilteredManifestEntries(
            phaseFilteredEntries,
            selectedIDs: idSelection
        )
        let selectedEntries = Self.shardedManifestEntries(
            idFilteredEntries,
            shardSelection: shardSelection
        )
        let limitedSelectedEntries = Self.limitedManifestEntries(
            selectedEntries,
            limit: localMilestoneLimit
        )
        let selectedPhaseCounts = Self.phaseCounts(
            for: phaseFilteredEntries,
            selectedPhaseNames: phaseSelection.valid
        )
        let missingSelectedPhaseNames = phaseSelection.valid.filter {
            selectedPhaseCounts[$0, default: 0] == 0
        }
        let availableSelectedIDs = Set(phaseFilteredEntries.compactMap { entry in
            entry.id?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
        let missingSelectedMilestoneIDs = idSelection.filter {
            !availableSelectedIDs.contains($0)
        }
        let milestones = limitedSelectedEntries.compactMap { entry -> LocalMilestone? in
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
                sidModel: entry.sidModel,
                sidAccuracyMode: entry.sidAccuracyMode,
                sidRegisters: entry.sidRegisters,
                sidAudioSignature: entry.sidAudioSignature,
                sidAudioState: entry.sidAudioState,
                sidVoiceStates: entry.sidVoiceStates,
                vicRegisters: entry.vicRegisters,
                vicRegisterSnapshotHash: entry.vicRegisterSnapshotHash,
                vicState: entry.vicState,
                vicRasterLine: entry.vicRasterLine,
                vicRasterCycle: entry.vicRasterCycle,
                vicBALineLow: entry.vicBALineLow,
                vicAECLineLow: entry.vicAECLineLow,
                vicBusOwner: entry.vicBusOwner,
                vicBusPhase: entry.vicBusPhase,
                vicLowPhaseAccess: entry.vicLowPhaseAccess,
                vicHighPhaseMemoryReads: entry.vicHighPhaseMemoryReads,
                vicHighPhaseMemoryReadsSpecified: entry.vicHighPhaseMemoryReadsSpecified,
                vicHighPhaseColorRAMReads: entry.vicHighPhaseColorRAMReads,
                vicHighPhaseColorRAMReadsSpecified: entry.vicHighPhaseColorRAMReadsSpecified,
                vicLowPhaseMemoryReads: entry.vicLowPhaseMemoryReads,
                vicLowPhaseMemoryReadsSpecified: entry.vicLowPhaseMemoryReadsSpecified,
                cia1Registers: entry.cia1Registers,
                cia2Registers: entry.cia2Registers,
                screenTextContains: entry.screenTextContains,
                screenRAMHash: entry.screenRAMHash,
                colorRAMHash: entry.colorRAMHash,
                framebufferHash: entry.framebufferHash,
                screenshotName: entry.screenshotName,
                roadmapPhase: entry.roadmapPhase?.rawValue,
                expectedFailure: entry.expectedFailure
            )
            milestone.id = entry.id
            milestone.name = entry.name
            milestone.tapeStatus = entry.tapeStatus
            milestone.lowLevelTracks = entry.lowLevelTracks
            milestone.weakBitRanges = entry.weakBitRanges
            milestone.speedZoneRanges = entry.speedZoneRanges
            return milestone
        }
        let missingMediaFiles = missingManifestMediaFiles(limitedSelectedEntries, urls: urls)
        if shouldRequireAllMilestoneMedia && !missingMediaFiles.isEmpty {
            throw ManifestValidationError(errors: [
                "missing manifest media files: \(missingMediaFiles.joined(separator: ", "))"
            ])
        }
        return MilestoneLoadResult(
            milestones: milestones,
            manifestMilestoneCount: manifest.milestones.count,
            milestoneShardIndex: shardSelection.index,
            milestoneShardCount: shardSelection.count,
            preShardMilestoneCount: idFilteredEntries.count,
            postShardMilestoneCount: selectedEntries.count,
            invalidShardConfiguration: shardSelection.invalidReason,
            manifestPhaseCounts: manifestPhaseCounts,
            manifestMediaCounts: manifestMediaCounts,
            manifestMachineProfileCounts: manifestMachineProfileCounts,
            manifestDriveModeCounts: manifestDriveModeCounts,
            manifestSIDModelCounts: manifestSIDModelCounts,
            manifestSIDAccuracyModeCounts: manifestSIDAccuracyModeCounts,
            manifestObservableTypeCounts: manifestObservableTypeCounts,
            manifestVICProofCounts: manifestVICProofCounts,
            manifestExpectedFailureCategoryCounts: manifestExpectedFailureCategoryCounts,
            manifestActionTypeCounts: manifestActionTypeCounts,
            manifestUntaggedMilestoneCount: manifestUntaggedMilestoneCount,
            manifestUnnamedMilestoneCount: manifestUnnamedMilestoneCount,
            manifestExpectedFailureCount: manifestExpectedFailureCount,
            manifestExpectedFailuresWithoutNotesCount: manifestExpectedFailuresWithoutNotesCount,
            manifestExpectedFailuresWithoutReasonMarkersCount: manifestExpectedFailuresWithoutReasonMarkersCount,
            manifestMilestonesWithoutMaxCyclesCount: manifestMilestonesWithoutMaxCyclesCount,
            manifestMilestonesWithoutExplicitActionsCount: manifestMilestonesWithoutExplicitActionsCount,
            manifestMilestonesWithoutObservableExpectationsCount: manifestMilestonesWithoutObservableExpectationsCount,
            manifestPhase3MilestonesWithoutVICProofCount: manifestPhase3MilestonesWithoutVICProofCount,
            manifestPhase3MilestonesMissingRequiredVICProofsCount: manifestPhase3MilestonesMissingRequiredVICProofsCount,
            manifestFramebufferHashMilestonesWithoutScreenshotNamesCount: manifestFramebufferHashMilestonesWithoutScreenshotNamesCount,
            manifestFramebufferScreenshotFilenameCollisionCount: manifestFramebufferScreenshotFilenameCollisions.count,
            manifestFramebufferScreenshotFilenameCollisions: manifestFramebufferScreenshotFilenameCollisions,
            manifestPlaceholderProofHashCount: manifestPlaceholderProofHashCount,
            phaseFilteredMilestoneCount: phaseFilteredEntries.count,
            selectedMediaCounts: Self.mediaCounts(for: milestones),
            selectedMachineProfileCounts: Self.machineProfileCounts(for: milestones),
            selectedDriveModeCounts: Self.driveModeCounts(for: milestones),
            selectedSIDModelCounts: Self.sidModelCounts(for: milestones),
            selectedSIDAccuracyModeCounts: Self.sidAccuracyModeCounts(for: milestones),
            selectedObservableTypeCounts: Self.observableTypeCounts(for: milestones),
            selectedVICProofCounts: Self.vicProofCounts(for: milestones),
            selectedExpectedFailureCategoryCounts: Self.expectedFailureCategoryCounts(for: milestones),
            selectedActionTypeCounts: Self.actionTypeCounts(for: milestones),
            missingMediaFiles: missingMediaFiles,
            selectedPhaseNames: phaseSelection.valid,
            invalidSelectedPhaseNames: phaseSelection.invalid,
            selectedPhaseCounts: selectedPhaseCounts,
            missingSelectedPhaseNames: missingSelectedPhaseNames,
            selectedMilestoneIDs: idSelection,
            missingSelectedMilestoneIDs: missingSelectedMilestoneIDs
        )
    }

    private func manifestMediaURL(for entry: CompatibilityMilestone, urls: [URL]) -> URL? {
        urls.first { $0.lastPathComponent == entry.file || $0.path.contains(entry.file) }
    }

    private static func phaseFilteredManifestEntries(
        _ entries: [CompatibilityMilestone],
        selectedPhaseNames: [String]
    ) -> [CompatibilityMilestone] {
        guard !selectedPhaseNames.isEmpty else {
            return entries
        }
        return entries.filter { entry in
            guard let phase = entry.roadmapPhase?.rawValue else {
                return false
            }
            return selectedPhaseNames.contains(phase)
        }
    }

    private static func idFilteredManifestEntries(
        _ entries: [CompatibilityMilestone],
        selectedIDs: [String]
    ) -> [CompatibilityMilestone] {
        guard !selectedIDs.isEmpty else {
            return entries
        }
        let selectedIDSet = Set(selectedIDs)
        return entries.filter { entry in
            guard let id = entry.id?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty else {
                return false
            }
            return selectedIDSet.contains(id)
        }
    }

    private static func shardedManifestEntries(
        _ entries: [CompatibilityMilestone],
        shardSelection: MilestoneShardSelection
    ) -> [CompatibilityMilestone] {
        guard shardSelection.invalidReason == nil,
              shardSelection.isActive,
              let shardIndex = shardSelection.index,
              let shardCount = shardSelection.count else {
            return entries
        }
        return entries.enumerated().compactMap { offset, entry in
            offset % shardCount == shardIndex ? entry : nil
        }
    }

    private static func limitedManifestEntries(
        _ entries: [CompatibilityMilestone],
        limit: Int?
    ) -> [CompatibilityMilestone] {
        guard let limit else {
            return entries
        }
        return Array(entries.prefix(max(0, limit)))
    }

    private static func limitedMilestones(
        _ milestones: [LocalMilestone],
        limit: Int?
    ) -> [LocalMilestone] {
        guard let limit else {
            return milestones
        }
        return Array(milestones.prefix(max(0, limit)))
    }

    private static func phaseCounts(
        for entries: [CompatibilityMilestone],
        selectedPhaseNames: [String] = []
    ) -> [String: Int] {
        var counts = Dictionary(uniqueKeysWithValues: selectedPhaseNames.map { ($0, 0) })
        for entry in entries {
            guard let phase = entry.roadmapPhase?.rawValue else {
                continue
            }
            counts[phase, default: 0] += 1
        }
        return counts
    }

    private static func mediaCounts(for entries: [CompatibilityMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in entries {
            counts[mediaTypeName(for: entry), default: 0] += 1
        }
        return counts
    }

    private static func mediaCounts(for milestones: [LocalMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for milestone in milestones {
            counts[milestone.mediaType.rawValue, default: 0] += 1
        }
        return counts
    }

    private static func machineProfileCounts(for entries: [CompatibilityMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in entries {
            let profileName = entry.machineProfile?.rawValue ?? CompatibilityMachineProfile.palC64.rawValue
            counts[profileName, default: 0] += 1
        }
        return counts
    }

    private static func machineProfileCounts(for milestones: [LocalMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for milestone in milestones {
            counts[milestone.machineProfile.rawValue, default: 0] += 1
        }
        return counts
    }

    private static func driveModeCounts(for entries: [CompatibilityMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in entries {
            let driveModeName = entry.driveMode?.rawValue ?? CompatibilityDriveMode.compat1541.rawValue
            counts[driveModeName, default: 0] += 1
        }
        return counts
    }

    private static func driveModeCounts(for milestones: [LocalMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for milestone in milestones {
            counts[milestone.driveMode.rawValue, default: 0] += 1
        }
        return counts
    }

    private static func sidModelCounts(for entries: [CompatibilityMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in entries {
            guard let sidModel = entry.sidModel else {
                continue
            }
            counts[sidModel.rawValue, default: 0] += 1
        }
        return counts
    }

    private static func sidModelCounts(for milestones: [LocalMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for milestone in milestones {
            guard let sidModel = milestone.sidModel else {
                continue
            }
            counts[sidModel.rawValue, default: 0] += 1
        }
        return counts
    }

    private static func sidAccuracyModeCounts(for entries: [CompatibilityMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in entries {
            guard let sidAccuracyMode = entry.sidAccuracyMode else {
                continue
            }
            counts[sidAccuracyMode.rawValue, default: 0] += 1
        }
        return counts
    }

    private static func sidAccuracyModeCounts(for milestones: [LocalMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for milestone in milestones {
            guard let sidAccuracyMode = milestone.sidAccuracyMode else {
                continue
            }
            counts[sidAccuracyMode.rawValue, default: 0] += 1
        }
        return counts
    }

    private static func observableTypeCounts(for entries: [CompatibilityMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for observableType in observableTypes(for: entry) {
                counts[observableType, default: 0] += 1
            }
        }
        return counts
    }

    private static func observableTypeCounts(for milestones: [LocalMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for milestone in milestones {
            for observableType in observableTypes(for: milestone) {
                counts[observableType, default: 0] += 1
            }
        }
        return counts
    }

    private static func vicProofCounts(for entries: [CompatibilityMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for proofType in vicProofTypes(for: entry) {
                counts[proofType, default: 0] += 1
            }
        }
        return counts
    }

    private static func vicProofCounts(for milestones: [LocalMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for milestone in milestones {
            for proofType in vicProofTypes(for: milestone) {
                counts[proofType, default: 0] += 1
            }
        }
        return counts
    }

    private static func expectedFailureCategoryCounts(for entries: [CompatibilityMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in entries {
            guard let category = entry.expectedFailure?.category else {
                continue
            }
            counts[category.rawValue, default: 0] += 1
        }
        return counts
    }

    private static func expectedFailureCategoryCounts(for milestones: [LocalMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for milestone in milestones {
            guard let category = milestone.expectedFailure?.category else {
                continue
            }
            counts[category.rawValue, default: 0] += 1
        }
        return counts
    }

    private static func actionTypeCounts(for entries: [CompatibilityMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in entries {
            let actions = entry.actions.isEmpty
                ? entry.commands.map { CompatibilityAction.typeText($0) }
                : entry.actions
            for actionType in Set(actions.map(actionTypeName(for:))) {
                counts[actionType, default: 0] += 1
            }
        }
        return counts
    }

    private static func actionTypeCounts(for milestones: [LocalMilestone]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for milestone in milestones {
            for actionType in Set(milestone.scheduledActions.map(actionTypeName(for:))) {
                counts[actionType, default: 0] += 1
            }
        }
        return counts
    }

    private static func actionTypeName(for action: CompatibilityAction) -> String {
        switch action {
        case .typeText:
            return MilestoneActionType.typeText
        case .waitCycles:
            return MilestoneActionType.waitCycles
        case .joystickDown:
            return MilestoneActionType.joystickDown
        case .joystickUp:
            return MilestoneActionType.joystickUp
        case .keyDown:
            return MilestoneActionType.keyDown
        case .keyUp:
            return MilestoneActionType.keyUp
        case .startTape:
            return MilestoneActionType.startTape
        case .stopTape:
            return MilestoneActionType.stopTape
        }
    }

    private static func observableTypes(for entry: CompatibilityMilestone) -> [String] {
        var types: [String] = []
        if !entry.expectedPCRanges.isEmpty {
            types.append(MilestoneObservableType.pc)
        }
        if entry.minGCRReads != nil || entry.minByteReady != nil || entry.driveStatus != nil {
            types.append(MilestoneObservableType.drive)
        }
        if entry.mediaStatus != nil || !entry.weakBitRanges.isEmpty || !entry.speedZoneRanges.isEmpty {
            types.append(MilestoneObservableType.media)
        }
        if !entry.lowLevelTracks.isEmpty {
            types.append(MilestoneObservableType.lowLevelTrack)
        }
        if entry.tapeStatus != nil {
            types.append(MilestoneObservableType.tape)
        }
        if !entry.ramSignatures.isEmpty {
            types.append(MilestoneObservableType.ram)
        }
        if !entry.colorRAMSignatures.isEmpty || entry.colorRAMHash != nil {
            types.append(MilestoneObservableType.colorRAM)
        }
        if entry.cpuRegisters != nil {
            types.append(MilestoneObservableType.cpu)
        }
        if !entry.sidRegisters.isEmpty
            || entry.sidAudioSignature != nil
            || entry.sidAudioState != nil
            || !entry.sidVoiceStates.isEmpty {
            types.append(MilestoneObservableType.sid)
        }
        if !entry.vicRegisters.isEmpty
            || entry.vicRegisterSnapshotHash != nil
            || entry.vicState != nil
            || entry.vicRasterLine != nil
            || entry.vicRasterCycle != nil
            || entry.vicBALineLow != nil
            || entry.vicAECLineLow != nil
            || entry.vicBusOwner != nil
            || entry.vicBusPhase != nil
            || entry.vicLowPhaseAccess != nil
            || entry.vicHighPhaseMemoryReadsSpecified
            || !entry.vicHighPhaseMemoryReads.isEmpty
            || entry.vicHighPhaseColorRAMReadsSpecified
            || !entry.vicHighPhaseColorRAMReads.isEmpty
            || entry.vicLowPhaseMemoryReadsSpecified
            || !entry.vicLowPhaseMemoryReads.isEmpty {
            types.append(MilestoneObservableType.vic)
        }
        if !entry.cia1Registers.isEmpty || !entry.cia2Registers.isEmpty {
            types.append(MilestoneObservableType.cia)
        }
        if !entry.screenTextContains.isEmpty || entry.screenRAMHash != nil {
            types.append(MilestoneObservableType.screen)
        }
        if entry.framebufferHash != nil {
            types.append(MilestoneObservableType.framebuffer)
        }
        return types
    }

    private static func vicProofTypes(for entry: CompatibilityMilestone) -> [String] {
        var types: [String] = []
        if !entry.vicRegisters.isEmpty || entry.vicRegisterSnapshotHash != nil {
            types.append(MilestoneVICProofType.registers)
        }
        if entry.vicState != nil {
            types.append(MilestoneVICProofType.state)
        }
        if entry.vicRasterLine != nil || entry.vicRasterCycle != nil {
            types.append(MilestoneVICProofType.raster)
        }
        if entry.vicBALineLow != nil
            || entry.vicAECLineLow != nil
            || entry.vicBusOwner != nil
            || entry.vicBusPhase != nil
            || entry.vicLowPhaseAccess != nil {
            types.append(MilestoneVICProofType.bus)
        }
        if entry.vicHighPhaseMemoryReadsSpecified
            || !entry.vicHighPhaseMemoryReads.isEmpty
            || entry.vicHighPhaseColorRAMReadsSpecified
            || !entry.vicHighPhaseColorRAMReads.isEmpty
            || entry.vicLowPhaseMemoryReadsSpecified
            || !entry.vicLowPhaseMemoryReads.isEmpty {
            types.append(MilestoneVICProofType.memoryTrace)
        }
        if entry.framebufferHash != nil {
            types.append(MilestoneVICProofType.framebuffer)
        }
        return types
    }

    private static func observableTypes(for milestone: LocalMilestone) -> [String] {
        var types: [String] = []
        if !milestone.pcRanges.isEmpty {
            types.append(MilestoneObservableType.pc)
        }
        if milestone.minGCRReads > 0 || milestone.minByteReady > 0 || milestone.driveStatus != nil {
            types.append(MilestoneObservableType.drive)
        }
        if milestone.mediaStatus != nil || !milestone.weakBitRanges.isEmpty || !milestone.speedZoneRanges.isEmpty {
            types.append(MilestoneObservableType.media)
        }
        if !milestone.lowLevelTracks.isEmpty {
            types.append(MilestoneObservableType.lowLevelTrack)
        }
        if milestone.tapeStatus != nil {
            types.append(MilestoneObservableType.tape)
        }
        if !milestone.ramSignatures.isEmpty {
            types.append(MilestoneObservableType.ram)
        }
        if !milestone.colorRAMSignatures.isEmpty || milestone.colorRAMHash != nil {
            types.append(MilestoneObservableType.colorRAM)
        }
        if milestone.cpuRegisters != nil {
            types.append(MilestoneObservableType.cpu)
        }
        if !milestone.sidRegisters.isEmpty
            || milestone.sidAudioSignature != nil
            || milestone.sidAudioState != nil
            || !milestone.sidVoiceStates.isEmpty {
            types.append(MilestoneObservableType.sid)
        }
        if !milestone.vicRegisters.isEmpty
            || milestone.vicRegisterSnapshotHash != nil
            || milestone.vicState != nil
            || milestone.vicRasterLine != nil
            || milestone.vicRasterCycle != nil
            || milestone.vicBALineLow != nil
            || milestone.vicAECLineLow != nil
            || milestone.vicBusOwner != nil
            || milestone.vicBusPhase != nil
            || milestone.vicLowPhaseAccess != nil
            || milestone.vicHighPhaseMemoryReadsSpecified
            || !milestone.vicHighPhaseMemoryReads.isEmpty
            || milestone.vicHighPhaseColorRAMReadsSpecified
            || !milestone.vicHighPhaseColorRAMReads.isEmpty
            || milestone.vicLowPhaseMemoryReadsSpecified
            || !milestone.vicLowPhaseMemoryReads.isEmpty {
            types.append(MilestoneObservableType.vic)
        }
        if !milestone.cia1Registers.isEmpty || !milestone.cia2Registers.isEmpty {
            types.append(MilestoneObservableType.cia)
        }
        if !milestone.screenTextContains.isEmpty || milestone.screenRAMHash != nil {
            types.append(MilestoneObservableType.screen)
        }
        if milestone.framebufferHash != nil {
            types.append(MilestoneObservableType.framebuffer)
        }
        return types
    }

    private static func vicProofTypes(for milestone: LocalMilestone) -> [String] {
        var types: [String] = []
        if !milestone.vicRegisters.isEmpty || milestone.vicRegisterSnapshotHash != nil {
            types.append(MilestoneVICProofType.registers)
        }
        if milestone.vicState != nil {
            types.append(MilestoneVICProofType.state)
        }
        if milestone.vicRasterLine != nil || milestone.vicRasterCycle != nil {
            types.append(MilestoneVICProofType.raster)
        }
        if milestone.vicBALineLow != nil
            || milestone.vicAECLineLow != nil
            || milestone.vicBusOwner != nil
            || milestone.vicBusPhase != nil
            || milestone.vicLowPhaseAccess != nil {
            types.append(MilestoneVICProofType.bus)
        }
        if milestone.vicHighPhaseMemoryReadsSpecified
            || !milestone.vicHighPhaseMemoryReads.isEmpty
            || milestone.vicHighPhaseColorRAMReadsSpecified
            || !milestone.vicHighPhaseColorRAMReads.isEmpty
            || milestone.vicLowPhaseMemoryReadsSpecified
            || !milestone.vicLowPhaseMemoryReads.isEmpty {
            types.append(MilestoneVICProofType.memoryTrace)
        }
        if milestone.framebufferHash != nil {
            types.append(MilestoneVICProofType.framebuffer)
        }
        return types
    }

    private static func mediaTypeName(for entry: CompatibilityMilestone) -> String {
        if let mediaType = entry.mediaType {
            return mediaType.rawValue
        }
        switch URL(fileURLWithPath: entry.file).pathExtension.lowercased() {
        case "prg": return CompatibilityMediaType.prg.rawValue
        case "g64": return CompatibilityMediaType.g64.rawValue
        case "nib": return CompatibilityMediaType.nib.rawValue
        case "nbz": return CompatibilityMediaType.nbz.rawValue
        case "p64": return CompatibilityMediaType.p64.rawValue
        case "t64": return CompatibilityMediaType.t64.rawValue
        case "tap": return CompatibilityMediaType.tap.rawValue
        case "crt": return CompatibilityMediaType.crt.rawValue
        default: return CompatibilityMediaType.d64.rawValue
        }
    }

    private static func untaggedPhaseCount(in entries: [CompatibilityMilestone]) -> Int {
        entries.filter { $0.roadmapPhase == nil }.count
    }

    private static func unnamedMilestoneCount(in entries: [CompatibilityMilestone]) -> Int {
        entries.filter { entry in
            entry.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        }.count
    }

    private static func expectedFailureCount(in entries: [CompatibilityMilestone]) -> Int {
        entries.filter { $0.expectedFailure != nil }.count
    }

    private static func expectedFailuresWithoutNotesCount(in entries: [CompatibilityMilestone]) -> Int {
        entries.filter { entry in
            guard let expectedFailure = entry.expectedFailure else {
                return false
            }
            return expectedFailure.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        }.count
    }

    private static func expectedFailuresWithoutReasonMarkersCount(in entries: [CompatibilityMilestone]) -> Int {
        entries.filter { entry in
            guard let expectedFailure = entry.expectedFailure else {
                return false
            }
            return !expectedFailure.reasonContains.contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }.count
    }

    private static func milestonesWithoutMaxCyclesCount(in entries: [CompatibilityMilestone]) -> Int {
        entries.filter { $0.maxCycles == nil }.count
    }

    private static func milestonesWithoutExplicitActionsCount(in entries: [CompatibilityMilestone]) -> Int {
        entries.filter { !$0.hasExplicitActions }.count
    }

    private static func milestonesWithoutObservableExpectationsCount(in entries: [CompatibilityMilestone]) -> Int {
        entries.filter { !hasObservableExpectation($0) }.count
    }

    private static func phase3MilestonesWithoutVICProofCount(in entries: [CompatibilityMilestone]) -> Int {
        entries.filter { entry in
            entry.roadmapPhase?.rawValue == MilestoneRoadmapPhase.phase3VICII
                && vicProofTypes(for: entry).isEmpty
        }.count
    }

    private static func phase3MilestonesMissingRequiredVICProofsCount(in entries: [CompatibilityMilestone]) -> Int {
        entries.filter { entry in
            guard entry.roadmapPhase?.rawValue == MilestoneRoadmapPhase.phase3VICII else {
                return false
            }
            let proofTypes = Set(vicProofTypes(for: entry))
            return !MilestoneVICProofType.requiredPhase3Proofs.allSatisfy { proofTypes.contains($0) }
        }.count
    }

    private static func framebufferHashMilestonesWithoutScreenshotNamesCount(in entries: [CompatibilityMilestone]) -> Int {
        entries.filter { entry in
            guard entry.framebufferHash != nil else { return false }
            return entry.screenshotName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        }.count
    }

    private static func framebufferScreenshotFilenameCollisionCount(in entries: [CompatibilityMilestone]) -> Int {
        framebufferScreenshotFilenameCollisions(in: entries).count
    }

    private static func framebufferScreenshotFilenameCollisions(in entries: [CompatibilityMilestone]) -> [String] {
        var seen: Set<String> = []
        var collisions: Set<String> = []
        for entry in entries where entry.framebufferHash != nil {
            guard let screenshotName = entry.screenshotName,
                  !screenshotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let filename = sanitizedScreenshotName(screenshotName) + ".ppm"
            if !seen.insert(filename).inserted {
                collisions.insert(filename)
            }
        }
        return collisions.sorted()
    }

    private static func placeholderProofHashCount(in entries: [CompatibilityMilestone]) -> Int {
        entries.reduce(0) { count, entry in
            count
                + (isPlaceholderProofHash(entry.vicRegisterSnapshotHash) ? 1 : 0)
                + (isPlaceholderProofHash(entry.screenRAMHash) ? 1 : 0)
                + (isPlaceholderProofHash(entry.colorRAMHash) ? 1 : 0)
                + (isPlaceholderProofHash(entry.framebufferHash) ? 1 : 0)
        }
    }

    private static func isPlaceholderProofHash(_ hash: String?) -> Bool {
        hash?.caseInsensitiveCompare("0000000000000000") == .orderedSame
    }

    private static func hasObservableExpectation(_ entry: CompatibilityMilestone) -> Bool {
        !observableTypes(for: entry).isEmpty
    }

    private func missingManifestMediaFiles(_ entries: [CompatibilityMilestone], urls: [URL]) -> [String] {
        entries.compactMap { entry in
            manifestMediaURL(for: entry, urls: urls) == nil ? entry.file : nil
        }
    }

    private func mountPrePowerOnMedia(for milestone: LocalMilestone, into c64: C64) -> Bool {
        switch milestone.mediaType {
        case .d64, .g64, .nib, .nbz, .p64:
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
        case "nib": return .nib
        case "nbz": return .nbz
        case "p64": return .p64
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
        let gcrWrites = driveStatus.gcrWriteByteCount - baseline.gcrWriteByteCount
        let gcrWriteSplices = driveStatus.gcrWriteSpliceCount - baseline.gcrWriteSpliceCount
        let gcrWriteEraseBits = driveStatus.gcrWriteEraseBitCount - baseline.gcrWriteEraseBitCount
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
                status: c64.emulationStatus,
                gcrReads: gcrReads,
                byteReady: byteReady,
                syncDetections: syncDetections,
                weakBitReads: weakBitReads,
                variableSpeedZoneSamples: variableSpeedZoneSamples,
                gcrWrites: gcrWrites,
                gcrWriteSplices: gcrWriteSplices,
                gcrWriteEraseBits: gcrWriteEraseBits
            ))
        }
        if let mediaStatusExpectation = milestone.mediaStatus {
            unmet.append(contentsOf: mediaStatusMismatches(
                mediaStatusExpectation,
                capabilities: c64.emulationStatus.mediaCapabilities
            ))
        }
        unmet.append(contentsOf: lowLevelTrackMismatches(
            milestone.lowLevelTracks,
            disk: c64.drive1541.disk
        ))
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
        if let sidAudioSignature = milestone.sidAudioSignature {
            unmet.append(contentsOf: sidAudioSignatureMismatches(sidAudioSignature, sid: c64.sid))
        }
        if let sidAudioState = milestone.sidAudioState {
            unmet.append(contentsOf: sidAudioStateMismatches(sidAudioState, sid: c64.sid))
        }
        unmet.append(contentsOf: sidVoiceStateMismatches(milestone.sidVoiceStates, sid: c64.sid))
        unmet.append(contentsOf: vicRegisterMismatches(milestone.vicRegisters, vic: c64.vic))
        if let expectedHash = milestone.vicRegisterSnapshotHash {
            let actualHash = CompatibilityHash.vicRegisterSnapshot(vicRegisterSnapshot(c64.vic))
            if actualHash.caseInsensitiveCompare(expectedHash) != .orderedSame {
                unmet.append("VIC registerSnapshotHash \(actualHash) != \(expectedHash)")
            }
        }
        unmet.append(contentsOf: vicStateMismatches(milestone.vicState, vic: c64.vic))
        unmet.append(contentsOf: vicRasterMismatches(
            expectedLine: milestone.vicRasterLine,
            expectedCycle: milestone.vicRasterCycle,
            vic: c64.vic
        ))
        unmet.append(contentsOf: vicBusMismatches(
            expectedBALineLow: milestone.vicBALineLow,
            expectedAECLineLow: milestone.vicAECLineLow,
            expectedBusOwner: milestone.vicBusOwner,
            expectedBusPhase: milestone.vicBusPhase,
            expectedLowPhaseAccess: milestone.vicLowPhaseAccess,
            vic: c64.vic
        ))
        unmet.append(contentsOf: vicMemoryTraceMismatches(
            highPhaseMemoryReads: milestone.vicHighPhaseMemoryReads,
            highPhaseMemoryReadsSpecified: milestone.vicHighPhaseMemoryReadsSpecified,
            highPhaseColorRAMReads: milestone.vicHighPhaseColorRAMReads,
            highPhaseColorRAMReadsSpecified: milestone.vicHighPhaseColorRAMReadsSpecified,
            lowPhaseMemoryReads: milestone.vicLowPhaseMemoryReads,
            lowPhaseMemoryReadsSpecified: milestone.vicLowPhaseMemoryReadsSpecified,
            vic: c64.vic
        ))
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
        if let expectedFramebufferHash = milestone.framebufferHash {
            let actualFramebufferHash = CompatibilityHash.framebuffer(
                c64.vic.framebuffer,
                width: VIC.screenWidth,
                height: VIC.screenHeight
            )
            if actualFramebufferHash.caseInsensitiveCompare(expectedFramebufferHash) != .orderedSame {
                unmet.append("framebuffer hash \(actualFramebufferHash) != \(expectedFramebufferHash)")
            }
        }

        if unmet.isEmpty {
            return "named milestone timeout after all expectations matched; " + timeoutStateSummary(c64)
        }
        return "named milestone timeout; unmet: " + unmet.joined(separator: "; ") + "; " + timeoutStateSummary(c64)
    }

    private func timeoutStateSummary(_ c64: C64) -> String {
        let driveStatus = c64.drive1541.statusSnapshot
        let readText = driveStatus.readHalfTrack.map {
            "readHalf=\($0)\(driveStatus.usingHalfTrackFallback ? ",fallback" : "")"
        } ?? "readHalf=none"
        return "timeout state pc=$\(hex16(c64.cpu.pc)) drivePC=$\(hex16(driveStatus.cpuPC)) " +
            "track=\(driveStatus.track) half=\(driveStatus.halfTrack) headBit=\(driveStatus.headBitPosition) " +
            "\(readText) motor=\(driveStatus.motorOn) led=\(driveStatus.ledOn) " +
            "byteReady=\(driveStatus.byteReadyCount) paReads=\(driveStatus.via2PortAReadCount) " +
            "sync=\(driveStatus.syncDetectionCount) weakBits=\(driveStatus.weakBitReadCount) " +
            "speedSamples=\(driveStatus.variableSpeedZoneSampleCount) speedZones=$\(hex8(driveStatus.variableSpeedZoneMask)) " +
            "gcrWrites=\(driveStatus.gcrWriteByteCount) gcrWriteMode=\(driveStatus.gcrWriteModeActive) " +
            "gcrWriteGate=\(driveStatus.gcrWriteGateActive) gcrSplices=\(driveStatus.gcrWriteSpliceCount) " +
            "gcrEraseBits=\(driveStatus.gcrWriteEraseBitCount) writeProtected=\(driveStatus.writeProtected) " +
            "hasDisk=\(driveStatus.hasDisk) mediaChanged=\(driveStatus.mediaChanged) " +
            "mediaChangeCount=\(driveStatus.mediaChangeCount) driveNoProgress=\(driveStatus.noProgressCycleCount)"
    }

    private func driveStatusMismatches(
        _ expectation: CompatibilityDriveStatus,
        snapshot: Drive1541.StatusSnapshot,
        status: C64.EmulationStatus,
        gcrReads: UInt64,
        byteReady: UInt64,
        syncDetections: UInt64,
        weakBitReads: UInt64,
        variableSpeedZoneSamples: UInt64,
        gcrWrites: UInt64,
        gcrWriteSplices: UInt64,
        gcrWriteEraseBits: UInt64
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
        if let minGCRWrites = expectation.minGCRWrites, gcrWrites < nonNegativeUInt64(minGCRWrites) {
            mismatches.append("drive.minGCRWrites \(gcrWrites) < \(minGCRWrites)")
        }
        if let minGCRWriteSplices = expectation.minGCRWriteSplices,
           gcrWriteSplices < nonNegativeUInt64(minGCRWriteSplices) {
            mismatches.append("drive.minGCRWriteSplices \(gcrWriteSplices) < \(minGCRWriteSplices)")
        }
        if let minGCRWriteEraseBits = expectation.minGCRWriteEraseBits,
           gcrWriteEraseBits < nonNegativeUInt64(minGCRWriteEraseBits) {
            mismatches.append("drive.minGCRWriteEraseBits \(gcrWriteEraseBits) < \(minGCRWriteEraseBits)")
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
        if let lastWeakBitHalfTrack = expectation.lastWeakBitHalfTrack,
           snapshot.lastWeakBitHalfTrack != lastWeakBitHalfTrack {
            mismatches.append("drive.lastWeakBitHalfTrack \(snapshot.lastWeakBitHalfTrack.map(String.init) ?? "nil") != \(lastWeakBitHalfTrack)")
        }
        if let lastWeakBitPosition = expectation.lastWeakBitPosition,
           snapshot.lastWeakBitPosition != lastWeakBitPosition {
            mismatches.append("drive.lastWeakBitPosition \(snapshot.lastWeakBitPosition.map(String.init) ?? "nil") != \(lastWeakBitPosition)")
        }
        if let lastWeakBitPositionStart = expectation.lastWeakBitPositionStart {
            if let actual = snapshot.lastWeakBitPosition {
                if actual < lastWeakBitPositionStart {
                    mismatches.append("drive.lastWeakBitPosition \(actual) < \(lastWeakBitPositionStart)")
                }
            } else {
                mismatches.append("drive.lastWeakBitPosition nil < \(lastWeakBitPositionStart)")
            }
        }
        if let lastWeakBitPositionEnd = expectation.lastWeakBitPositionEnd {
            if let actual = snapshot.lastWeakBitPosition {
                if actual > lastWeakBitPositionEnd {
                    mismatches.append("drive.lastWeakBitPosition \(actual) > \(lastWeakBitPositionEnd)")
                }
            } else {
                mismatches.append("drive.lastWeakBitPosition nil > \(lastWeakBitPositionEnd)")
            }
        }
        if let lastVariableSpeedZoneHalfTrack = expectation.lastVariableSpeedZoneHalfTrack,
           snapshot.lastVariableSpeedZoneHalfTrack != lastVariableSpeedZoneHalfTrack {
            mismatches.append("drive.lastVariableSpeedZoneHalfTrack \(snapshot.lastVariableSpeedZoneHalfTrack.map(String.init) ?? "nil") != \(lastVariableSpeedZoneHalfTrack)")
        }
        if let lastVariableSpeedZoneByteIndex = expectation.lastVariableSpeedZoneByteIndex,
           snapshot.lastVariableSpeedZoneByteIndex != lastVariableSpeedZoneByteIndex {
            mismatches.append("drive.lastVariableSpeedZoneByteIndex \(snapshot.lastVariableSpeedZoneByteIndex.map(String.init) ?? "nil") != \(lastVariableSpeedZoneByteIndex)")
        }
        if let lastVariableSpeedZone = expectation.lastVariableSpeedZone,
           snapshot.lastVariableSpeedZone != lastVariableSpeedZone {
            mismatches.append("drive.lastVariableSpeedZone \(snapshot.lastVariableSpeedZone.map(String.init) ?? "nil") != \(lastVariableSpeedZone)")
        }
        if let track = expectation.track, snapshot.track != track {
            mismatches.append("drive.track \(snapshot.track) != \(track)")
        }
        if let halfTrack = expectation.halfTrack, snapshot.halfTrack != halfTrack {
            mismatches.append("drive.halfTrack \(snapshot.halfTrack) != \(halfTrack)")
        }
        if let headBitPosition = expectation.headBitPosition,
           snapshot.headBitPosition != headBitPosition {
            mismatches.append("drive.headBitPosition \(snapshot.headBitPosition) != \(headBitPosition)")
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
        if let gcrWriteModeActive = expectation.gcrWriteModeActive,
           snapshot.gcrWriteModeActive != gcrWriteModeActive {
            mismatches.append("drive.gcrWriteModeActive \(snapshot.gcrWriteModeActive) != \(gcrWriteModeActive)")
        }
        if let gcrWriteGateActive = expectation.gcrWriteGateActive,
           snapshot.gcrWriteGateActive != gcrWriteGateActive {
            mismatches.append("drive.gcrWriteGateActive \(snapshot.gcrWriteGateActive) != \(gcrWriteGateActive)")
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
        if let d64ExportBlockedByLowLevelWrites = expectation.d64ExportBlockedByLowLevelWrites,
           status.d64ExportBlockedByLowLevelWrites != d64ExportBlockedByLowLevelWrites {
            mismatches.append("drive.d64ExportBlockedByLowLevelWrites \(status.d64ExportBlockedByLowLevelWrites) != \(d64ExportBlockedByLowLevelWrites)")
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
        if let preservesWeakBitRanges = expectation.preservesWeakBitRanges,
           capabilities.preservesWeakBitRanges != preservesWeakBitRanges {
            mismatches.append("media.preservesWeakBitRanges \(capabilities.preservesWeakBitRanges) != \(preservesWeakBitRanges)")
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
        if let hasDuplicateSectorHeaders = expectation.hasDuplicateSectorHeaders,
           capabilities.hasDuplicateSectorHeaders != hasDuplicateSectorHeaders {
            mismatches.append("media.hasDuplicateSectorHeaders \(capabilities.hasDuplicateSectorHeaders) != \(hasDuplicateSectorHeaders)")
        }
        if let duplicateSectorHeaderCount = expectation.duplicateSectorHeaderCount,
           capabilities.duplicateSectorHeaderCount != duplicateSectorHeaderCount {
            mismatches.append("media.duplicateSectorHeaderCount \(capabilities.duplicateSectorHeaderCount) != \(duplicateSectorHeaderCount)")
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

    private func lowLevelTrackMismatches(
        _ expectations: [CompatibilityLowLevelTrackExpectation],
        disk: GCRDisk
    ) -> [String] {
        var mismatches: [String] = []
        for expectation in expectations {
            let prefix = "media.lowLevelTrack[\(expectation.halfTrack)]"
            guard let track = disk.trackInfo(halfTrack: expectation.halfTrack) else {
                mismatches.append("\(prefix) missing")
                continue
            }
            if let byteCount = expectation.byteCount, track.bytes.count != byteCount {
                mismatches.append("\(prefix).byteCount \(track.bytes.count) != \(byteCount)")
            }
            if let bitLength = expectation.bitLength, track.bitLength != bitLength {
                mismatches.append("\(prefix).bitLength \(track.bitLength) != \(bitLength)")
            }
            if let speedZone = expectation.speedZone, track.speedZone != speedZone {
                mismatches.append("\(prefix).speedZone \(track.speedZone) != \(speedZone)")
            }
            if let bytesHash = expectation.bytesHash {
                let actualHash = CompatibilityHash.fnv1a64(track.bytes)
                if actualHash.caseInsensitiveCompare(bytesHash) != .orderedSame {
                    mismatches.append("\(prefix).bytesHash \(actualHash) != \(bytesHash)")
                }
            }
            if let speedZoneMapHash = expectation.speedZoneMapHash {
                guard let speedZoneMap = track.speedZoneMap else {
                    mismatches.append("\(prefix).speedZoneMapHash nil != \(speedZoneMapHash)")
                    continue
                }
                let actualHash = CompatibilityHash.fnv1a64(speedZoneMap)
                if actualHash.caseInsensitiveCompare(speedZoneMapHash) != .orderedSame {
                    mismatches.append("\(prefix).speedZoneMapHash \(actualHash) != \(speedZoneMapHash)")
                }
            }
            if let weakBitRangeCount = expectation.weakBitRangeCount,
               track.weakBitRanges.count != weakBitRangeCount {
                mismatches.append("\(prefix).weakBitRangeCount \(track.weakBitRanges.count) != \(weakBitRangeCount)")
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
            let actual = sidRegisterValue(expectation, sid: sid)
            let maskedActual = actual & expectation.mask
            let maskedExpected = expectation.value & expectation.mask
            guard maskedActual != maskedExpected else { return nil }
            return "SID \(expectation.readMode.rawValue) $\(hex16(register)) \(hex8(maskedActual)) != \(hex8(maskedExpected)) mask \(hex8(expectation.mask))"
        }
    }

    private func sidRegisterValue(_ expectation: CompatibilitySIDRegisterExpectation, sid: SID) -> UInt8 {
        let register = UInt16(truncatingIfNeeded: expectation.register)
        switch expectation.readMode {
        case .debug:
            return sid.debugRegisterValue(register)
        case .chip:
            return sid.peekReadableRegisterValue(register)
        }
    }

    private func sidAudioSignatureMismatches(
        _ expectation: CompatibilitySIDAudioSignature,
        sid: SID
    ) -> [String] {
        let actual = sid.recentAudioSignature(sampleCount: expectation.sampleCount)
        let actualSummary = sid.recentAudioSummary(sampleCount: expectation.sampleCount)
        var mismatches: [String] = []
        if actual.sampleCount != expectation.sampleCount {
            mismatches.append("SID audio.sampleCount \(actual.sampleCount) != \(expectation.sampleCount)")
        }
        if let minimum = expectation.minimum,
           abs(Double(actual.minimum - minimum)) > expectation.tolerance {
            mismatches.append("SID audio.minimum \(formatFloat(actual.minimum)) != \(formatFloat(minimum)) tolerance \(formatDouble(expectation.tolerance))")
        }
        if let maximum = expectation.maximum,
           abs(Double(actual.maximum - maximum)) > expectation.tolerance {
            mismatches.append("SID audio.maximum \(formatFloat(actual.maximum)) != \(formatFloat(maximum)) tolerance \(formatDouble(expectation.tolerance))")
        }
        if let sum = expectation.sum,
           abs(actual.sum - sum) > expectation.tolerance {
            mismatches.append("SID audio.sum \(formatDouble(actual.sum)) != \(formatDouble(sum)) tolerance \(formatDouble(expectation.tolerance))")
        }
        if let absoluteSum = expectation.absoluteSum,
           abs(actual.absoluteSum - absoluteSum) > expectation.tolerance {
            mismatches.append("SID audio.absoluteSum \(formatDouble(actual.absoluteSum)) != \(formatDouble(absoluteSum)) tolerance \(formatDouble(expectation.tolerance))")
        }
        if let mean = expectation.mean,
           abs(actual.mean - mean) > expectation.tolerance {
            mismatches.append("SID audio.mean \(formatDouble(actual.mean)) != \(formatDouble(mean)) tolerance \(formatDouble(expectation.tolerance))")
        }
        if let rootMeanSquare = expectation.rootMeanSquare,
           abs(actual.rootMeanSquare - rootMeanSquare) > expectation.tolerance {
            mismatches.append("SID audio.rootMeanSquare \(formatDouble(actual.rootMeanSquare)) != \(formatDouble(rootMeanSquare)) tolerance \(formatDouble(expectation.tolerance))")
        }
        if let zeroCrossings = expectation.zeroCrossings,
           actual.zeroCrossings != zeroCrossings {
            mismatches.append("SID audio.zeroCrossings \(actual.zeroCrossings) != \(zeroCrossings)")
        }
        appendSIDAudioDoubleMismatch(&mismatches, field: "zeroCrossingRate", actual: actualSummary.zeroCrossingRate, expected: expectation.zeroCrossingRate, tolerance: expectation.tolerance)
        appendSIDAudioDoubleMismatch(&mismatches, field: "lowBandRootMeanSquare", actual: actualSummary.lowBandRootMeanSquare, expected: expectation.lowBandRootMeanSquare, tolerance: expectation.tolerance)
        appendSIDAudioDoubleMismatch(&mismatches, field: "midBandRootMeanSquare", actual: actualSummary.midBandRootMeanSquare, expected: expectation.midBandRootMeanSquare, tolerance: expectation.tolerance)
        appendSIDAudioDoubleMismatch(&mismatches, field: "highBandRootMeanSquare", actual: actualSummary.highBandRootMeanSquare, expected: expectation.highBandRootMeanSquare, tolerance: expectation.tolerance)
        appendSIDAudioDoubleMismatch(&mismatches, field: "crestFactor", actual: actualSummary.crestFactor, expected: expectation.crestFactor, tolerance: expectation.tolerance)
        return mismatches
    }

    private func appendSIDAudioDoubleMismatch(
        _ mismatches: inout [String],
        field: String,
        actual: Double,
        expected: Double?,
        tolerance: Double
    ) {
        guard let expected,
              abs(actual - expected) > tolerance else {
            return
        }
        mismatches.append("SID audio.\(field) \(formatDouble(actual)) != \(formatDouble(expected)) tolerance \(formatDouble(tolerance))")
    }

    private func sidAudioStateMismatches(
        _ expectation: CompatibilitySIDAudioState,
        sid: SID
    ) -> [String] {
        let actual = sid.debugAudioState()
        var mismatches: [String] = []

        if let accuracyMode = expectation.accuracyMode,
           actual.accuracyMode != accuracyMode {
            mismatches.append("SID audio.state.accuracyMode \(actual.accuracyMode.rawValue) != \(accuracyMode.rawValue)")
        }
        if let sampleCycleCounter = expectation.sampleCycleCounter,
           abs(actual.sampleCycleCounter - sampleCycleCounter) > expectation.tolerance {
            mismatches.append("SID audio.state.sampleCycleCounter \(formatDouble(actual.sampleCycleCounter)) != \(formatDouble(sampleCycleCounter)) tolerance \(formatDouble(expectation.tolerance))")
        }
        if let cyclesPerSample = expectation.cyclesPerSample,
           abs(actual.cyclesPerSample - cyclesPerSample) > expectation.tolerance {
            mismatches.append("SID audio.state.cyclesPerSample \(formatDouble(actual.cyclesPerSample)) != \(formatDouble(cyclesPerSample)) tolerance \(formatDouble(expectation.tolerance))")
        }
        if let audioAccumulator = expectation.audioAccumulator,
           abs(actual.audioAccumulator - audioAccumulator) > expectation.tolerance {
            mismatches.append("SID audio.state.audioAccumulator \(formatDouble(actual.audioAccumulator)) != \(formatDouble(audioAccumulator)) tolerance \(formatDouble(expectation.tolerance))")
        }
        if let audioAccumulatorCount = expectation.audioAccumulatorCount,
           actual.audioAccumulatorCount != audioAccumulatorCount {
            mismatches.append("SID audio.state.audioAccumulatorCount \(actual.audioAccumulatorCount) != \(audioAccumulatorCount)")
        }
        if let audioOutputState = expectation.audioOutputState,
           abs(actual.audioOutputState - audioOutputState) > expectation.tolerance {
            mismatches.append("SID audio.state.audioOutputState \(formatDouble(actual.audioOutputState)) != \(formatDouble(audioOutputState)) tolerance \(formatDouble(expectation.tolerance))")
        }
        if let directOutput = expectation.directOutput,
           actual.directOutput != directOutput {
            mismatches.append("SID audio.state.directOutput \(actual.directOutput) != \(directOutput)")
        }
        if let filterInput = expectation.filterInput,
           actual.filterInput != filterInput {
            mismatches.append("SID audio.state.filterInput \(actual.filterInput) != \(filterInput)")
        }
        if let filterOutput = expectation.filterOutput,
           actual.filterOutput != filterOutput {
            mismatches.append("SID audio.state.filterOutput \(actual.filterOutput) != \(filterOutput)")
        }
        if let mixedOutput = expectation.mixedOutput,
           actual.mixedOutput != mixedOutput {
            mismatches.append("SID audio.state.mixedOutput \(actual.mixedOutput) != \(mixedOutput)")
        }
        if let externalAudioInput = expectation.externalAudioInput,
           actual.externalAudioInput != externalAudioInput {
            mismatches.append("SID audio.state.externalAudioInput \(actual.externalAudioInput) != \(externalAudioInput)")
        }
        if let externalAudioPathInput = expectation.externalAudioPathInput,
           actual.externalAudioPathInput != externalAudioPathInput {
            mismatches.append("SID audio.state.externalAudioPathInput \(actual.externalAudioPathInput) != \(externalAudioPathInput)")
        }
        if let filterCutoff = expectation.filterCutoff,
           Int(actual.filterCutoff) != filterCutoff {
            mismatches.append("SID audio.state.filterCutoff $\(hex(Int(actual.filterCutoff), width: 4)) != $\(hex(filterCutoff, width: 4))")
        }
        if let filterResonance = expectation.filterResonance,
           Int(actual.filterResonance) != filterResonance {
            mismatches.append("SID audio.state.filterResonance $\(hex(Int(actual.filterResonance), width: 1)) != $\(hex(filterResonance, width: 1))")
        }
        if let filterControl = expectation.filterControl,
           Int(actual.filterControl) != filterControl {
            mismatches.append("SID audio.state.filterControl $\(hex(Int(actual.filterControl), width: 1)) != $\(hex(filterControl, width: 1))")
        }
        if let volumeFilter = expectation.volumeFilter,
           Int(actual.volumeFilter) != volumeFilter {
            mismatches.append("SID audio.state.volumeFilter $\(hex(Int(actual.volumeFilter), width: 2)) != $\(hex(volumeFilter, width: 2))")
        }
        if let volume = expectation.volume,
           Int(actual.volume) != volume {
            mismatches.append("SID audio.state.volume $\(hex(Int(actual.volume), width: 1)) != $\(hex(volume, width: 1))")
        }
        if let normalizedFilterCutoffValue = expectation.normalizedFilterCutoffValue,
           Int(actual.normalizedFilterCutoffValue) != normalizedFilterCutoffValue {
            mismatches.append("SID audio.state.normalizedFilterCutoffValue $\(hex(Int(actual.normalizedFilterCutoffValue), width: 3)) != $\(hex(normalizedFilterCutoffValue, width: 3))")
        }
        if let normalizedFilterCutoff = expectation.normalizedFilterCutoff,
           abs(actual.normalizedFilterCutoff - normalizedFilterCutoff) > expectation.tolerance {
            mismatches.append("SID audio.state.normalizedFilterCutoff \(formatDouble(actual.normalizedFilterCutoff)) != \(formatDouble(normalizedFilterCutoff)) tolerance \(formatDouble(expectation.tolerance))")
        }
        if let filterDamping = expectation.filterDamping,
           abs(actual.filterDamping - filterDamping) > expectation.tolerance {
            mismatches.append("SID audio.state.filterDamping \(formatDouble(actual.filterDamping)) != \(formatDouble(filterDamping)) tolerance \(formatDouble(expectation.tolerance))")
        }
        appendSIDAudioBoolMismatch(&mismatches, field: "voice1FilterEnabled", actual: actual.voice1FilterEnabled, expected: expectation.voice1FilterEnabled)
        appendSIDAudioBoolMismatch(&mismatches, field: "voice2FilterEnabled", actual: actual.voice2FilterEnabled, expected: expectation.voice2FilterEnabled)
        appendSIDAudioBoolMismatch(&mismatches, field: "voice3FilterEnabled", actual: actual.voice3FilterEnabled, expected: expectation.voice3FilterEnabled)
        appendSIDAudioBoolMismatch(&mismatches, field: "externalInputFiltered", actual: actual.externalInputFiltered, expected: expectation.externalInputFiltered)
        appendSIDAudioBoolMismatch(&mismatches, field: "filterLowPassEnabled", actual: actual.filterLowPassEnabled, expected: expectation.filterLowPassEnabled)
        appendSIDAudioBoolMismatch(&mismatches, field: "filterBandPassEnabled", actual: actual.filterBandPassEnabled, expected: expectation.filterBandPassEnabled)
        appendSIDAudioBoolMismatch(&mismatches, field: "filterHighPassEnabled", actual: actual.filterHighPassEnabled, expected: expectation.filterHighPassEnabled)
        appendSIDAudioBoolMismatch(&mismatches, field: "voice3Off", actual: actual.voice3Off, expected: expectation.voice3Off)
        if let dataBusLatch = expectation.dataBusLatch,
           Int(actual.dataBusLatch) != dataBusLatch {
            mismatches.append("SID audio.state.dataBusLatch $\(hex(Int(actual.dataBusLatch), width: 2)) != $\(hex(dataBusLatch, width: 2))")
        }
        if let dataBusLatchCyclesRemaining = expectation.dataBusLatchCyclesRemaining,
           actual.dataBusLatchCyclesRemaining != dataBusLatchCyclesRemaining {
            mismatches.append("SID audio.state.dataBusLatchCyclesRemaining \(actual.dataBusLatchCyclesRemaining) != \(dataBusLatchCyclesRemaining)")
        }
        if let oscillator3Readback = expectation.oscillator3Readback,
           Int(actual.oscillator3Readback) != oscillator3Readback {
            mismatches.append("SID audio.state.oscillator3Readback $\(hex(Int(actual.oscillator3Readback), width: 2)) != $\(hex(oscillator3Readback, width: 2))")
        }
        appendSIDAudioBoolMismatch(&mismatches, field: "oscillator3ReadbackValid", actual: actual.oscillator3ReadbackValid, expected: expectation.oscillator3ReadbackValid)
        if let envelope3Readback = expectation.envelope3Readback,
           Int(actual.envelope3Readback) != envelope3Readback {
            mismatches.append("SID audio.state.envelope3Readback $\(hex(Int(actual.envelope3Readback), width: 2)) != $\(hex(envelope3Readback, width: 2))")
        }
        appendSIDAudioBoolMismatch(&mismatches, field: "envelope3ReadbackValid", actual: actual.envelope3ReadbackValid, expected: expectation.envelope3ReadbackValid)
        if let paddleX = expectation.paddleX,
           Int(actual.paddleX) != paddleX {
            mismatches.append("SID audio.state.paddleX $\(hex(Int(actual.paddleX), width: 2)) != $\(hex(paddleX, width: 2))")
        }
        if let paddleY = expectation.paddleY,
           Int(actual.paddleY) != paddleY {
            mismatches.append("SID audio.state.paddleY $\(hex(Int(actual.paddleY), width: 2)) != $\(hex(paddleY, width: 2))")
        }
        if let paddleTargetX = expectation.paddleTargetX,
           Int(actual.paddleTargetX) != paddleTargetX {
            mismatches.append("SID audio.state.paddleTargetX $\(hex(Int(actual.paddleTargetX), width: 2)) != $\(hex(paddleTargetX, width: 2))")
        }
        if let paddleTargetY = expectation.paddleTargetY,
           Int(actual.paddleTargetY) != paddleTargetY {
            mismatches.append("SID audio.state.paddleTargetY $\(hex(Int(actual.paddleTargetY), width: 2)) != $\(hex(paddleTargetY, width: 2))")
        }
        appendSIDAudioBoolMismatch(&mismatches, field: "paddleScanActive", actual: actual.paddleScanActive, expected: expectation.paddleScanActive)
        if let paddleScanCounter = expectation.paddleScanCounter,
           actual.paddleScanCounter != paddleScanCounter {
            let actualCounter = actual.paddleScanCounter.map { "\($0)" } ?? "nil"
            mismatches.append("SID audio.state.paddleScanCounter \(actualCounter) != \(paddleScanCounter)")
        }
        if let filterLow = expectation.filterLow,
           abs(actual.filterLow - filterLow) > expectation.tolerance {
            mismatches.append("SID audio.state.filterLow \(formatDouble(actual.filterLow)) != \(formatDouble(filterLow)) tolerance \(formatDouble(expectation.tolerance))")
        }
        if let filterBand = expectation.filterBand,
           abs(actual.filterBand - filterBand) > expectation.tolerance {
            mismatches.append("SID audio.state.filterBand \(formatDouble(actual.filterBand)) != \(formatDouble(filterBand)) tolerance \(formatDouble(expectation.tolerance))")
        }
        if let filterHigh = expectation.filterHigh,
           abs(actual.filterHigh - filterHigh) > expectation.tolerance {
            mismatches.append("SID audio.state.filterHigh \(formatDouble(actual.filterHigh)) != \(formatDouble(filterHigh)) tolerance \(formatDouble(expectation.tolerance))")
        }
        if let sampleWritePosition = expectation.sampleWritePosition,
           actual.sampleWritePosition != sampleWritePosition {
            mismatches.append("SID audio.state.sampleWritePosition \(actual.sampleWritePosition) != \(sampleWritePosition)")
        }

        return mismatches
    }

    private func appendSIDAudioBoolMismatch(
        _ mismatches: inout [String],
        field: String,
        actual: Bool,
        expected: Bool?
    ) {
        guard let expected, actual != expected else { return }
        mismatches.append("SID audio.state.\(field) \(actual) != \(expected)")
    }

    private func sidVoiceStateMismatches(
        _ expectations: [CompatibilitySIDVoiceState],
        sid: SID
    ) -> [String] {
        let voices = sid.debugVoiceStates()
        return expectations.flatMap { expectation -> [String] in
            guard voices.indices.contains(expectation.voice) else {
                return ["SID voice\(expectation.voice) out of range"]
            }
            let voice = voices[expectation.voice]
            let label = "SID voice\(expectation.voice)"
            var mismatches: [String] = []

            appendSIDVoiceMismatch(&mismatches, label: label, field: "frequency", actual: Int(voice.frequency), expected: expectation.frequency, width: 4)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "pulseWidth", actual: Int(voice.pulseWidth), expected: expectation.pulseWidth, width: 3)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "control", actual: Int(voice.control), expected: expectation.control, width: 2)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "attackDecay", actual: Int(voice.attackDecay), expected: expectation.attackDecay, width: 2)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "sustainRelease", actual: Int(voice.sustainRelease), expected: expectation.sustainRelease, width: 2)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "accumulator", actual: Int(voice.accumulator), expected: expectation.accumulator, width: 6)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "shiftRegister", actual: Int(voice.shiftRegister), expected: expectation.shiftRegister, width: 6)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "envelopeLevel", actual: Int(voice.envelopeLevel), expected: expectation.envelopeLevel, width: 2)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "envelopeOutput", actual: Int(voice.envelopeOutput), expected: expectation.envelopeOutput, width: 2)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "sustainLevel", actual: Int(voice.sustainLevel), expected: expectation.sustainLevel, width: 2)
            appendSIDVoiceStringMismatch(&mismatches, label: label, field: "envelopeState", actual: voice.envelopeState, expected: expectation.envelopeState)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "exponentialCounter", actual: Int(voice.exponentialCounter), expected: expectation.exponentialCounter)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "exponentialPeriod", actual: Int(voice.exponentialPeriod), expected: expectation.exponentialPeriod)
            appendSIDVoiceBoolMismatch(&mismatches, label: label, field: "holdZero", actual: voice.holdZero, expected: expectation.holdZero)
            appendSIDVoiceBoolMismatch(&mismatches, label: label, field: "gate", actual: voice.gate, expected: expectation.gate)
            appendSIDVoiceBoolMismatch(&mismatches, label: label, field: "controlGate", actual: voice.controlGate, expected: expectation.controlGate)
            appendSIDVoiceBoolMismatch(&mismatches, label: label, field: "sync", actual: voice.sync, expected: expectation.sync)
            appendSIDVoiceBoolMismatch(&mismatches, label: label, field: "ringMod", actual: voice.ringMod, expected: expectation.ringMod)
            appendSIDVoiceBoolMismatch(&mismatches, label: label, field: "testBit", actual: voice.testBit, expected: expectation.testBit)
            appendSIDVoiceBoolMismatch(&mismatches, label: label, field: "waveTriangle", actual: voice.waveTriangle, expected: expectation.waveTriangle)
            appendSIDVoiceBoolMismatch(&mismatches, label: label, field: "waveSawtooth", actual: voice.waveSawtooth, expected: expectation.waveSawtooth)
            appendSIDVoiceBoolMismatch(&mismatches, label: label, field: "wavePulse", actual: voice.wavePulse, expected: expectation.wavePulse)
            appendSIDVoiceBoolMismatch(&mismatches, label: label, field: "waveNoise", actual: voice.waveNoise, expected: expectation.waveNoise)
            appendSIDVoiceBoolMismatch(&mismatches, label: label, field: "hasWaveform", actual: voice.hasWaveform, expected: expectation.hasWaveform)
            appendSIDVoiceBoolMismatch(&mismatches, label: label, field: "oscillatorMSBRose", actual: voice.oscillatorMSBRose, expected: expectation.oscillatorMSBRose)
            appendSIDVoiceBoolMismatch(&mismatches, label: label, field: "noiseClockRose", actual: voice.noiseClockRose, expected: expectation.noiseClockRose)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "rateCounter", actual: Int(voice.rateCounter), expected: expectation.rateCounter)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "selectedRatePeriod", actual: Int(voice.selectedRatePeriod), expected: expectation.selectedRatePeriod)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "oscillatorOutput", actual: Int(voice.oscillatorOutput), expected: expectation.oscillatorOutput, width: 3)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "waveformOutput", actual: Int(voice.waveformOutput), expected: expectation.waveformOutput)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "waveformDACOutput", actual: Int(voice.waveformDACOutput), expected: expectation.waveformDACOutput, width: 3)
            appendSIDVoiceMismatch(&mismatches, label: label, field: "waveformDACHoldCyclesRemaining", actual: voice.waveformDACHoldCyclesRemaining, expected: expectation.waveformDACHoldCyclesRemaining)

            return mismatches
        }
    }

    private func appendSIDVoiceMismatch(
        _ mismatches: inout [String],
        label: String,
        field: String,
        actual: Int,
        expected: Int?,
        width: Int? = nil
    ) {
        guard let expected, actual != expected else { return }
        if let width {
            mismatches.append("\(label).\(field) $\(hex(actual, width: width)) != $\(hex(expected, width: width))")
        } else {
            mismatches.append("\(label).\(field) \(actual) != \(expected)")
        }
    }

    private func appendSIDVoiceStringMismatch(
        _ mismatches: inout [String],
        label: String,
        field: String,
        actual: String,
        expected: String?
    ) {
        guard let expected, actual != expected else { return }
        mismatches.append("\(label).\(field) \(actual) != \(expected)")
    }

    private func appendSIDVoiceBoolMismatch(
        _ mismatches: inout [String],
        label: String,
        field: String,
        actual: Bool,
        expected: Bool?
    ) {
        guard let expected, actual != expected else { return }
        mismatches.append("\(label).\(field) \(actual) != \(expected)")
    }

    private func hex(_ value: Int, width: Int) -> String {
        String(format: "%0\(width)X", value)
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

    private func vicRasterMismatches(
        expectedLine: Int?,
        expectedCycle: Int?,
        vic: VIC
    ) -> [String] {
        var mismatches: [String] = []
        if let expectedLine, Int(vic.rasterLine) != expectedLine {
            mismatches.append("VIC rasterLine \(Int(vic.rasterLine)) != \(expectedLine)")
        }
        if let expectedCycle, vic.rasterCycle != expectedCycle {
            mismatches.append("VIC rasterCycle \(vic.rasterCycle) != \(expectedCycle)")
        }
        return mismatches
    }

    private func vicStateMismatches(
        _ expectation: CompatibilityVICStateExpectation?,
        vic: VIC
    ) -> [String] {
        guard let expectation else { return [] }
        var mismatches: [String] = []
        appendVICBoolMismatch(&mismatches, label: "badLine", actual: vic.badLine, expected: expectation.badLine)
        appendVICIntMismatch(&mismatches, label: "badLineStartCycle", actual: vic.badLineStartCycle, expected: expectation.badLineStartCycle)
        appendVICBoolMismatch(&mismatches, label: "badLineDENLatched", actual: vic.badLineDENLatched, expected: expectation.badLineDENLatched)
        appendVICBoolMismatch(&mismatches, label: "displayActive", actual: vic.displayActive, expected: expectation.displayActive)
        appendVICBoolMismatch(&mismatches, label: "verticalBorderActive", actual: vic.verticalBorderActive, expected: expectation.verticalBorderActive)
        appendVICBoolMismatch(&mismatches, label: "horizontalBorderActive", actual: vic.horizontalBorderActive, expected: expectation.horizontalBorderActive)
        appendVICIntMismatch(&mismatches, label: "rowCounter", actual: vic.rowCounter, expected: expectation.rowCounter)
        appendVICIntMismatch(&mismatches, label: "videoCounter", actual: vic.videoCounter, expected: expectation.videoCounter)
        appendVICIntMismatch(&mismatches, label: "videoCounterBase", actual: vic.videoCounterBase, expected: expectation.videoCounterBase)
        appendVICIntMismatch(&mismatches, label: "displayLineBufferBase", actual: vic.displayLineBufferBase, expected: expectation.displayLineBufferBase)
        appendVICUInt64Mismatch(&mismatches, label: "badLineFetchMask", actual: vic.badLineFetchMask, expected: expectation.badLineFetchMask)
        appendVICUInt64Mismatch(&mismatches, label: "graphicsFetchMask", actual: vic.graphicsFetchMask, expected: expectation.graphicsFetchMask)
        appendVICIntArrayMismatch(&mismatches, label: "spriteMC", actual: vic.spriteMC, expected: expectation.spriteMC)
        appendVICIntArrayMismatch(&mismatches, label: "spriteMCBase", actual: vic.spriteMCBase, expected: expectation.spriteMCBase)
        appendVICBoolArrayMismatch(&mismatches, label: "spriteYExpFF", actual: vic.spriteYExpFF, expected: expectation.spriteYExpFF)
        appendVICBoolArrayMismatch(&mismatches, label: "spriteDisplay", actual: vic.spriteDisplay, expected: expectation.spriteDisplay)
        return mismatches.map { "VIC state \($0)" }
    }

    private func appendVICBoolMismatch(
        _ mismatches: inout [String],
        label: String,
        actual: Bool,
        expected: Bool?
    ) {
        guard let expected, actual != expected else { return }
        mismatches.append("\(label) \(actual) != \(expected)")
    }

    private func appendVICIntMismatch(
        _ mismatches: inout [String],
        label: String,
        actual: Int?,
        expected: Int?
    ) {
        guard let expected, actual != expected else { return }
        mismatches.append("\(label) \(actual.map(String.init) ?? "nil") != \(expected)")
    }

    private func appendVICUInt64Mismatch(
        _ mismatches: inout [String],
        label: String,
        actual: UInt64,
        expected: UInt64?
    ) {
        guard let expected, actual != expected else { return }
        mismatches.append("\(label) \(actual) != \(expected)")
    }

    private func appendVICIntArrayMismatch(
        _ mismatches: inout [String],
        label: String,
        actual: [Int],
        expected: [Int]?
    ) {
        guard let expected, actual != expected else { return }
        mismatches.append("\(label) \(actual) != \(expected)")
    }

    private func appendVICBoolArrayMismatch(
        _ mismatches: inout [String],
        label: String,
        actual: [Bool],
        expected: [Bool]?
    ) {
        guard let expected, actual != expected else { return }
        mismatches.append("\(label) \(actual) != \(expected)")
    }

    private func vicBusMismatches(
        expectedBALineLow: Bool?,
        expectedAECLineLow: Bool?,
        expectedBusOwner: CompatibilityVICBusOwner?,
        expectedBusPhase: CompatibilityVICBusPhaseExpectation?,
        expectedLowPhaseAccess: CompatibilityVICLowPhaseAccessExpectation?,
        vic: VIC
    ) -> [String] {
        var mismatches: [String] = []
        if let expectedBALineLow, vic.baLineLow != expectedBALineLow {
            mismatches.append("VIC baLineLow \(vic.baLineLow) != \(expectedBALineLow)")
        }
        if let expectedAECLineLow, vic.aecLineLow != expectedAECLineLow {
            mismatches.append("VIC aecLineLow \(vic.aecLineLow) != \(expectedAECLineLow)")
        }
        if let expectedBusOwner {
            let actual = CompatibilityVICBusOwner(vic.busOwner)
            if actual != expectedBusOwner {
                mismatches.append("VIC busOwner \(actual.rawValue) != \(expectedBusOwner.rawValue)")
            }
        }
        if let expectedBusPhase {
            let actual = CompatibilityVICBusPhaseExpectation(vic.busPhase)
            if actual != expectedBusPhase {
                mismatches.append("VIC busPhase \(actual.summary) != \(expectedBusPhase.summary)")
            }
        }
        if let expectedLowPhaseAccess {
            let actual = CompatibilityVICLowPhaseAccessExpectation(vic.lowPhaseAccess)
            if actual != expectedLowPhaseAccess {
                mismatches.append("VIC lowPhaseAccess \(actual.summary) != \(expectedLowPhaseAccess.summary)")
            }
        }
        return mismatches
    }

    private func vicMemoryTraceMismatches(
        highPhaseMemoryReads: [Int],
        highPhaseMemoryReadsSpecified: Bool,
        highPhaseColorRAMReads: [Int],
        highPhaseColorRAMReadsSpecified: Bool,
        lowPhaseMemoryReads: [Int],
        lowPhaseMemoryReadsSpecified: Bool,
        vic: VIC
    ) -> [String] {
        var mismatches: [String] = []
        appendVICTraceMismatch(
            &mismatches,
            label: "VIC highPhaseMemoryReads",
            actual: vic.lastHighPhaseMemoryReads.map(Int.init),
            expected: highPhaseMemoryReads,
            specified: highPhaseMemoryReadsSpecified
        )
        appendVICTraceMismatch(
            &mismatches,
            label: "VIC highPhaseColorRAMReads",
            actual: vic.lastHighPhaseColorRAMReads.map(Int.init),
            expected: highPhaseColorRAMReads,
            specified: highPhaseColorRAMReadsSpecified
        )
        appendVICTraceMismatch(
            &mismatches,
            label: "VIC lowPhaseMemoryReads",
            actual: vic.lastLowPhaseMemoryReads.map(Int.init),
            expected: lowPhaseMemoryReads,
            specified: lowPhaseMemoryReadsSpecified
        )
        return mismatches
    }

    private func appendVICTraceMismatch(
        _ mismatches: inout [String],
        label: String,
        actual: [Int],
        expected: [Int],
        specified: Bool
    ) {
        guard (specified || !expected.isEmpty), actual != expected else { return }
        mismatches.append("\(label) \(formatAddresses(actual)) != \(formatAddresses(expected))")
    }

    private func formatAddresses(_ addresses: [Int]) -> String {
        "[" + addresses.map { "$\(hex($0, width: 4))" }.joined(separator: ",") + "]"
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

    private func formatFloat(_ value: Float) -> String {
        String(format: "%.6f", Double(value))
    }

    private func formatDouble(_ value: Double) -> String {
        String(format: "%.6f", value)
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
        let baseName = Self.sanitizedScreenshotName(screenshotName)
        let suffixPart = suffix.map { "-" + Self.sanitizedScreenshotName($0) } ?? ""
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

    private static func sanitizedScreenshotName(_ name: String) -> String {
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

private func vicRegisterSnapshot(_ vic: VIC) -> [UInt8] {
    (0..<0x2F).map { vic.debugRegisterValue(UInt16($0)) }
}

private func vicStateSnapshot(_ vic: VIC) -> CompatibilityVICStateExpectation {
    CompatibilityVICStateExpectation(
        badLine: vic.badLine,
        badLineStartCycle: vic.badLineStartCycle,
        badLineDENLatched: vic.badLineDENLatched,
        displayActive: vic.displayActive,
        verticalBorderActive: vic.verticalBorderActive,
        horizontalBorderActive: vic.horizontalBorderActive,
        rowCounter: vic.rowCounter,
        videoCounter: vic.videoCounter,
        videoCounterBase: vic.videoCounterBase,
        displayLineBufferBase: vic.displayLineBufferBase,
        badLineFetchMask: vic.badLineFetchMask,
        graphicsFetchMask: vic.graphicsFetchMask,
        spriteMC: vic.spriteMC,
        spriteMCBase: vic.spriteMCBase,
        spriteYExpFF: vic.spriteYExpFF,
        spriteDisplay: vic.spriteDisplay
    )
}

private struct MatrixRunResult {
    let passed: Bool
    let elapsedCycles: UInt64
    let reason: String

    func summary(name: String, command: String, c64: C64) -> String {
        let drive = c64.drive1541.statusSnapshot
        let media = c64.emulationStatus.mediaCapabilities
        let mediaText = media.map {
            "\($0.format.displayName):tracks=\($0.populatedHalfTrackCount),native=\($0.nativeLowLevelTrackCount),synthetic=\($0.syntheticGCRTrackCount),errors=\($0.nonDefaultSectorErrorCodeCount),weakRanges=\($0.weakBitRangeCount),dupHeaders=\($0.duplicateSectorHeaderCount),speedBytes=\($0.variableSpeedZoneByteCount)"
        } ?? "none"
        let readText = drive.readHalfTrack.map { "readHalf=\($0)\(drive.usingHalfTrackFallback ? ",fallback" : "")" } ?? "readHalf=none"
        let verdict = passed ? "PASS" : "FAIL"
        return "\(verdict) \(name) category=\(category.rawValue) command=\(command) driveMode=\(c64.trueDriveEmulationMode.displayName) cycles=\(elapsedCycles) pc=$\(hex16(c64.cpu.pc)) drivePC=$\(hex16(drive.cpuPC)) track=\(drive.track) half=\(drive.halfTrack) \(readText) media=[\(mediaText)] iec=[\(drive.lastIECCommandSummary)] byteReady=\(drive.byteReadyCount) paReads=\(drive.via2PortAReadCount) gcrWrites=\(drive.gcrWriteByteCount) gcrWriteGate=\(drive.gcrWriteGateActive) gcrSplices=\(drive.gcrWriteSpliceCount) gcrEraseBits=\(drive.gcrWriteEraseBitCount) weakBits=\(drive.weakBitReadCount) speedSamples=\(drive.variableSpeedZoneSampleCount) speedZones=$\(hex8(drive.variableSpeedZoneMask)) reason=\(reason)"
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
        let vicRegisters = vicRegisterSnapshot(c64.vic)
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
            roadmapPhase: milestone.roadmapPhase ?? MilestoneRoadmapPhase.phaseName(forCategory: category.rawValue),
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
            finalVICBALineLow: c64.vic.baLineLow,
            finalVICAECLineLow: c64.vic.aecLineLow,
            finalVICBusOwner: CompatibilityVICBusOwner(c64.vic.busOwner).rawValue,
            finalVICBusPhase: CompatibilityVICBusPhaseExpectation(c64.vic.busPhase).summary,
            finalVICLowPhaseAccess: CompatibilityVICLowPhaseAccessExpectation(c64.vic.lowPhaseAccess).summary,
            finalVICHighPhaseMemoryReads: c64.vic.lastHighPhaseMemoryReads.map(hex16),
            finalVICHighPhaseColorRAMReads: c64.vic.lastHighPhaseColorRAMReads.map(hex16),
            finalVICLowPhaseMemoryReads: c64.vic.lastLowPhaseMemoryReads.map(hex16),
            finalVICRegisterSnapshotHash: CompatibilityHash.vicRegisterSnapshot(vicRegisters),
            finalVICRegisterSnapshot: vicRegisters.map(hex8),
            finalVICState: vicStateSnapshot(c64.vic),
            finalSIDModel: c64.sid.model.rawValue,
            finalSIDAccuracyMode: c64.sid.accuracyMode.rawValue,
            finalSIDAudioSignature: SIDAudioSignatureRecord(
                c64.sid.recentAudioSignature(sampleCount: milestone.sidAudioSignature?.sampleCount ?? 512),
                audioSummary: c64.sid.recentAudioSummary(sampleCount: milestone.sidAudioSignature?.sampleCount ?? 512)
            ),
            finalSIDAudioState: SIDAudioStateRecord(c64.sid.debugAudioState()),
            finalSIDRegisterSnapshot: c64.sid.debugRegisterSnapshot().map(hex8),
            finalSIDReadableRegisterSnapshot: c64.sid.readableRegisterSnapshot().map(hex8),
            finalSIDVoiceStates: c64.sid.debugVoiceStates().map(SIDVoiceStateRecord.init),
            finalDrivePC: hex16(drive.cpuPC),
            finalTrack: drive.track,
            finalHalfTrack: drive.halfTrack,
            finalHeadBitPosition: drive.headBitPosition,
            finalReadTrack: drive.readTrack,
            finalReadHalfTrack: drive.readHalfTrack,
            finalUsingHalfTrackFallback: drive.usingHalfTrackFallback,
            finalByteReadyCount: drive.byteReadyCount,
            finalVia2PortAReadCount: drive.via2PortAReadCount,
            finalWeakBitReadCount: drive.weakBitReadCount,
            finalLastWeakBitHalfTrack: drive.lastWeakBitHalfTrack,
            finalLastWeakBitPosition: drive.lastWeakBitPosition,
            finalVariableSpeedZoneSampleCount: drive.variableSpeedZoneSampleCount,
            finalVariableSpeedZoneMask: drive.variableSpeedZoneMask,
            finalLastVariableSpeedZoneHalfTrack: drive.lastVariableSpeedZoneHalfTrack,
            finalLastVariableSpeedZoneByteIndex: drive.lastVariableSpeedZoneByteIndex,
            finalLastVariableSpeedZone: drive.lastVariableSpeedZone,
            finalGCRWriteByteCount: drive.gcrWriteByteCount,
            finalGCRWriteModeActive: drive.gcrWriteModeActive,
            finalGCRWriteGateActive: drive.gcrWriteGateActive,
            finalGCRWriteSpliceCount: drive.gcrWriteSpliceCount,
            finalGCRWriteEraseBitCount: drive.gcrWriteEraseBitCount,
            finalD64ExportBlockedByLowLevelWrites: c64.emulationStatus.d64ExportBlockedByLowLevelWrites,
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
            finalMediaPreservesWeakBitRanges: media?.preservesWeakBitRanges,
            finalMediaSectorErrorCodeCount: media?.sectorErrorCodeCount,
            finalMediaNonDefaultSectorErrorCodeCount: media?.nonDefaultSectorErrorCodeCount,
            finalMediaWeakBitRangeCount: media?.weakBitRangeCount,
            finalMediaWeakBitTotalBitCount: media?.weakBitTotalBitCount,
            finalMediaHasDuplicateSectorHeaders: media?.hasDuplicateSectorHeaders,
            finalMediaDuplicateSectorHeaderCount: media?.duplicateSectorHeaderCount,
            finalMediaVariableSpeedZoneByteCount: media?.variableSpeedZoneByteCount,
            finalMediaSupportsWraparoundReads: media?.supportsWraparoundReads,
            finalMediaMaxTrackSize: media?.maxTrackSize,
            finalMediaUnsupportedFeatures: media?.unsupportedFeatures,
            finalLowLevelTracks: lowLevelTrackRecords(milestone.lowLevelTracks, disk: c64.drive1541.disk),
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
            framebufferHash: CompatibilityHash.framebuffer(
                c64.vic.framebuffer,
                width: VIC.screenWidth,
                height: VIC.screenHeight
            ),
            screenshotPath: screenshotURL?.path
        )
    }

    private func lowLevelTrackRecords(
        _ expectations: [CompatibilityLowLevelTrackExpectation],
        disk: GCRDisk
    ) -> [LowLevelTrackRecord]? {
        guard !expectations.isEmpty else { return nil }
        return expectations.map { LowLevelTrackRecord(expectation: $0, disk: disk) }
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
    case vic
    case sid
    case drive
    case media
    case protectedMedia
    case cartridge
    case app
    case pc
    case ram
    case screen
    case tape
    // Legacy result names kept for decoding older JSONL/summary files.
    case video
    case audio
    case cia
    case emulator
    case timeout

    static func classify(passed: Bool, reason: String) -> MilestoneResultCategory {
        guard !passed else { return .pass }
        let rawLower = reason.lowercased()
        let lower: String
        if let timeoutStateRange = rawLower.range(of: "; timeout state") {
            lower = String(rawLower[..<timeoutStateRange.lowerBound])
        } else {
            lower = rawLower
        }
        if lower.contains("vic $")
            || lower.contains("vic ")
            || lower.contains("vic.")
            || lower.contains("raster")
            || lower.contains("balinelow")
            || lower.contains("aeclinelow")
            || lower.contains("busowner")
            || lower.contains("badline")
            || lower.contains("bad line")
            || lower.contains("sprite dma")
            || lower.contains("border") {
            return .vic
        }
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
        if lower.contains("drive.minweakbitreads")
            || lower.contains("media.weakbit")
            || lower.contains("weak bit")
            || lower.contains("weak-bit")
            || lower.contains("variable speed")
            || lower.contains("variable-speed")
            || lower.contains("drive.minvariablespeedzonesamples")
            || lower.contains("drive.requiredvariablespeedzones")
            || lower.contains("media.variablespeedzone")
            || lower.contains("speed zone")
            || lower.contains("speed-zone")
            || lower.contains("drive.mingcrwrites")
            || lower.contains("drive.mingcrwritesplices")
            || lower.contains("drive.mingcrwriteerasebits")
            || lower.contains("write head") {
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
            || lower.contains("framebuffer hash")
            || lower.contains("color ram hash")
            || lower.contains("color ram $") {
            return .screen
        }
        if lower.contains("sid $")
            || lower.contains("sid.")
            || lower.contains("sid audio")
            || lower.contains("sid voice")
            || lower.contains("osc3")
            || lower.contains("env3")
            || lower.contains("filter cutoff") {
            return .sid
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

private enum MilestoneRoadmapPhase {
    static let passed = "passed"
    static let skipped = "skipped"
    static let phase2CPUMemoryBus = "phase2CPUMemoryBus"
    static let phase3VICII = "phase3VICII"
    static let phase4DriveMedia = "phase4DriveMedia"
    static let phase5SID = "phase5SID"
    static let phase6CIAInputTape = "phase6CIAInputTape"
    static let phase7CartridgeExpansion = "phase7CartridgeExpansion"
    static let phase8AppDistribution = "phase8AppDistribution"
    static let unclassified = "unclassified"

    static let gateablePhases: Set<String> = [
        phase2CPUMemoryBus,
        phase3VICII,
        phase4DriveMedia,
        phase5SID,
        phase6CIAInputTape,
        phase7CartridgeExpansion,
        phase8AppDistribution,
    ]

    static func phaseName(forCategory category: String) -> String {
        switch category {
        case MilestoneResultCategory.pass.rawValue:
            return passed
        case MilestoneResultCategory.cpu.rawValue,
             MilestoneResultCategory.pc.rawValue,
             MilestoneResultCategory.ram.rawValue:
            return phase2CPUMemoryBus
        case MilestoneResultCategory.vic.rawValue,
             MilestoneResultCategory.video.rawValue,
             MilestoneResultCategory.screen.rawValue:
            return phase3VICII
        case MilestoneResultCategory.drive.rawValue,
             MilestoneResultCategory.media.rawValue,
             MilestoneResultCategory.protectedMedia.rawValue:
            return phase4DriveMedia
        case MilestoneResultCategory.sid.rawValue,
             MilestoneResultCategory.audio.rawValue:
            return phase5SID
        case MilestoneResultCategory.cia.rawValue,
             MilestoneResultCategory.tape.rawValue:
            return phase6CIAInputTape
        case MilestoneResultCategory.cartridge.rawValue:
            return phase7CartridgeExpansion
        case MilestoneResultCategory.app.rawValue:
            return phase8AppDistribution
        default:
            return unclassified
        }
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
    var lowLevelTracks: [CompatibilityLowLevelTrackExpectation] = []
    var weakBitRanges: [CompatibilityWeakBitRange] = []
    var speedZoneRanges: [CompatibilitySpeedZoneRange] = []
    var tapeStatus: CompatibilityTapeStatus? = nil
    let ramSignatures: [CompatibilityRAMSignature]
    let colorRAMSignatures: [CompatibilityRAMSignature]
    var cpuRegisters: CompatibilityCPURegisters? = nil
    var sidModel: SID.Model? = nil
    var sidAccuracyMode: SID.AccuracyMode? = nil
    var sidRegisters: [CompatibilitySIDRegisterExpectation] = []
    var sidAudioSignature: CompatibilitySIDAudioSignature? = nil
    var sidAudioState: CompatibilitySIDAudioState? = nil
    var sidVoiceStates: [CompatibilitySIDVoiceState] = []
    var vicRegisters: [CompatibilityVICRegisterExpectation] = []
    var vicRegisterSnapshotHash: String? = nil
    var vicState: CompatibilityVICStateExpectation? = nil
    var vicRasterLine: Int? = nil
    var vicRasterCycle: Int? = nil
    var vicBALineLow: Bool? = nil
    var vicAECLineLow: Bool? = nil
    var vicBusOwner: CompatibilityVICBusOwner? = nil
    var vicBusPhase: CompatibilityVICBusPhaseExpectation? = nil
    var vicLowPhaseAccess: CompatibilityVICLowPhaseAccessExpectation? = nil
    var vicHighPhaseMemoryReads: [Int] = []
    var vicHighPhaseMemoryReadsSpecified: Bool = false
    var vicHighPhaseColorRAMReads: [Int] = []
    var vicHighPhaseColorRAMReadsSpecified: Bool = false
    var vicLowPhaseMemoryReads: [Int] = []
    var vicLowPhaseMemoryReadsSpecified: Bool = false
    var cia1Registers: [CompatibilityCIARegisterExpectation] = []
    var cia2Registers: [CompatibilityCIARegisterExpectation] = []
    var screenTextContains: [String] = []
    let screenRAMHash: String?
    let colorRAMHash: String?
    var framebufferHash: String? = nil
    let screenshotName: String?
    var roadmapPhase: String? = nil
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
            category: "skipped",
            roadmapPhase: roadmapPhase ?? MilestoneRoadmapPhase.skipped
        )
    }
}

private struct MilestoneLoadResult {
    var milestones: [LocalMilestone] = []
    var manifestMilestoneCount: Int? = nil
    var milestoneShardIndex: Int? = nil
    var milestoneShardCount: Int? = nil
    var preShardMilestoneCount: Int? = nil
    var postShardMilestoneCount: Int? = nil
    var invalidShardConfiguration: String? = nil
    var manifestPhaseCounts: [String: Int] = [:]
    var manifestMediaCounts: [String: Int] = [:]
    var manifestMachineProfileCounts: [String: Int] = [:]
    var manifestDriveModeCounts: [String: Int] = [:]
    var manifestSIDModelCounts: [String: Int] = [:]
    var manifestSIDAccuracyModeCounts: [String: Int] = [:]
    var manifestObservableTypeCounts: [String: Int] = [:]
    var manifestVICProofCounts: [String: Int] = [:]
    var manifestExpectedFailureCategoryCounts: [String: Int] = [:]
    var manifestActionTypeCounts: [String: Int] = [:]
    var manifestUntaggedMilestoneCount: Int = 0
    var manifestUnnamedMilestoneCount: Int = 0
    var manifestExpectedFailureCount: Int = 0
    var manifestExpectedFailuresWithoutNotesCount: Int = 0
    var manifestExpectedFailuresWithoutReasonMarkersCount: Int = 0
    var manifestMilestonesWithoutMaxCyclesCount: Int = 0
    var manifestMilestonesWithoutExplicitActionsCount: Int = 0
    var manifestMilestonesWithoutObservableExpectationsCount: Int = 0
    var manifestPhase3MilestonesWithoutVICProofCount: Int = 0
    var manifestPhase3MilestonesMissingRequiredVICProofsCount: Int = 0
    var manifestFramebufferHashMilestonesWithoutScreenshotNamesCount: Int = 0
    var manifestFramebufferScreenshotFilenameCollisionCount: Int = 0
    var manifestFramebufferScreenshotFilenameCollisions: [String] = []
    var manifestPlaceholderProofHashCount: Int = 0
    var phaseFilteredMilestoneCount: Int? = nil
    var selectedMediaCounts: [String: Int] = [:]
    var selectedMachineProfileCounts: [String: Int] = [:]
    var selectedDriveModeCounts: [String: Int] = [:]
    var selectedSIDModelCounts: [String: Int] = [:]
    var selectedSIDAccuracyModeCounts: [String: Int] = [:]
    var selectedObservableTypeCounts: [String: Int] = [:]
    var selectedVICProofCounts: [String: Int] = [:]
    var selectedExpectedFailureCategoryCounts: [String: Int] = [:]
    var selectedActionTypeCounts: [String: Int] = [:]
    var missingMediaFiles: [String] = []
    var selectedPhaseNames: [String] = []
    var invalidSelectedPhaseNames: [String] = []
    var selectedPhaseCounts: [String: Int] = [:]
    var missingSelectedPhaseNames: [String] = []
    var selectedMilestoneIDs: [String] = []
    var missingSelectedMilestoneIDs: [String] = []
}

private struct MilestoneShardSelection {
    var index: Int?
    var count: Int?
    var invalidReason: String?

    init(index: Int? = nil, count: Int? = nil, invalidReason: String? = nil) {
        self.index = index
        self.count = count
        self.invalidReason = invalidReason
    }

    var isActive: Bool {
        guard let count else { return false }
        return count > 1
    }
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

private func manifestMilestoneValidationErrors(_ milestones: [CompatibilityMilestone]) -> [String] {
    var errors: [String] = []
    var milestonesByID: [String: CompatibilityMilestone] = [:]
    var milestonesByKey: [MilestoneResultKey: CompatibilityMilestone] = [:]

    for milestone in milestones {
        if let id = milestone.id?.trimmingCharacters(in: .whitespacesAndNewlines),
           !id.isEmpty {
            if let previous = milestonesByID[id] {
                errors.append("duplicate milestone id \(id) for \(previous.file) and \(milestone.file)")
            } else {
                milestonesByID[id] = milestone
            }
        }

        let key = milestoneResultKey(for: milestone)
        if let previous = milestonesByKey[key] {
            errors.append("duplicate milestone key \(milestoneResultKeySummary(key)) for \(previous.file) and \(milestone.file)")
        } else {
            milestonesByKey[key] = milestone
        }
    }

    return errors
}

private func milestoneResultKey(for milestone: CompatibilityMilestone) -> MilestoneResultKey {
    MilestoneResultKey(
        id: milestone.id,
        file: URL(fileURLWithPath: milestone.file).lastPathComponent,
        commandSummary: milestoneCommandSummary(milestone),
        machineProfile: (milestone.machineProfile ?? .palC64).rawValue,
        driveMode: (milestone.driveMode ?? .compat1541).rawValue
    )
}

private func milestoneCommandSummary(_ milestone: CompatibilityMilestone) -> String {
    if !milestone.commands.isEmpty {
        return milestone.commands.joined(separator: " | ")
    }
    return milestone.actions.map(\.summary).joined(separator: " | ")
}

private func milestoneResultKeySummary(_ key: MilestoneResultKey) -> String {
    let idText = key.id.map { "id=\($0) " } ?? ""
    return "\(idText)file=\(key.file) profile=\(key.machineProfile) drive=\(key.driveMode) command=\(key.commandSummary)"
}

private struct LowLevelTrackRecord: Codable, Equatable {
    let halfTrack: Int
    let byteCount: Int?
    let bitLength: Int?
    let speedZone: Int?
    let bytesHash: String?
    let speedZoneMapHash: String?
    let weakBitRangeCount: Int?

    init(expectation: CompatibilityLowLevelTrackExpectation, disk: GCRDisk) {
        halfTrack = expectation.halfTrack
        guard let track = disk.trackInfo(halfTrack: expectation.halfTrack) else {
            byteCount = nil
            bitLength = nil
            speedZone = nil
            bytesHash = nil
            speedZoneMapHash = nil
            weakBitRangeCount = nil
            return
        }
        byteCount = track.bytes.count
        bitLength = track.bitLength
        speedZone = track.speedZone
        bytesHash = CompatibilityHash.fnv1a64(track.bytes)
        speedZoneMapHash = track.speedZoneMap.map { CompatibilityHash.fnv1a64($0) }
        weakBitRangeCount = track.weakBitRanges.count
    }
}

private struct MilestoneResultRecord: Codable, Equatable {
    static let currentFormatVersion = 35

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
    let roadmapPhase: String?
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
    let finalVICBALineLow: Bool?
    let finalVICAECLineLow: Bool?
    let finalVICBusOwner: String?
    let finalVICBusPhase: String?
    let finalVICLowPhaseAccess: String?
    let finalVICHighPhaseMemoryReads: [String]?
    let finalVICHighPhaseColorRAMReads: [String]?
    let finalVICLowPhaseMemoryReads: [String]?
    let finalVICRegisterSnapshotHash: String?
    let finalVICRegisterSnapshot: [String]?
    let finalVICState: CompatibilityVICStateExpectation?
    let finalSIDModel: String?
    let finalSIDAccuracyMode: String?
    let finalSIDAudioSignature: SIDAudioSignatureRecord?
    let finalSIDAudioState: SIDAudioStateRecord?
    let finalSIDRegisterSnapshot: [String]?
    let finalSIDReadableRegisterSnapshot: [String]?
    let finalSIDVoiceStates: [SIDVoiceStateRecord]?
    let finalDrivePC: String?
    let finalTrack: Int?
    let finalHalfTrack: Int?
    let finalHeadBitPosition: Int?
    let finalReadTrack: Int?
    let finalReadHalfTrack: Int?
    let finalUsingHalfTrackFallback: Bool?
    let finalByteReadyCount: UInt64?
    let finalVia2PortAReadCount: UInt64?
    let finalWeakBitReadCount: UInt64?
    let finalLastWeakBitHalfTrack: Int?
    let finalLastWeakBitPosition: Int?
    let finalVariableSpeedZoneSampleCount: UInt64?
    let finalVariableSpeedZoneMask: UInt8?
    let finalLastVariableSpeedZoneHalfTrack: Int?
    let finalLastVariableSpeedZoneByteIndex: Int?
    let finalLastVariableSpeedZone: Int?
    let finalGCRWriteByteCount: UInt64?
    let finalGCRWriteModeActive: Bool?
    let finalGCRWriteGateActive: Bool?
    let finalGCRWriteSpliceCount: UInt64?
    let finalGCRWriteEraseBitCount: UInt64?
    let finalD64ExportBlockedByLowLevelWrites: Bool?
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
    let finalMediaPreservesWeakBitRanges: Bool?
    let finalMediaSectorErrorCodeCount: Int?
    let finalMediaNonDefaultSectorErrorCodeCount: Int?
    let finalMediaWeakBitRangeCount: Int?
    let finalMediaWeakBitTotalBitCount: Int?
    let finalMediaHasDuplicateSectorHeaders: Bool?
    let finalMediaDuplicateSectorHeaderCount: Int?
    let finalMediaVariableSpeedZoneByteCount: Int?
    let finalMediaSupportsWraparoundReads: Bool?
    let finalMediaMaxTrackSize: Int?
    let finalMediaUnsupportedFeatures: [String]?
    let finalLowLevelTracks: [LowLevelTrackRecord]?
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
    let framebufferHash: String?
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
        roadmapPhase: String? = nil,
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
        finalVICBALineLow: Bool? = nil,
        finalVICAECLineLow: Bool? = nil,
        finalVICBusOwner: String? = nil,
        finalVICBusPhase: String? = nil,
        finalVICLowPhaseAccess: String? = nil,
        finalVICHighPhaseMemoryReads: [String]? = nil,
        finalVICHighPhaseColorRAMReads: [String]? = nil,
        finalVICLowPhaseMemoryReads: [String]? = nil,
        finalVICRegisterSnapshotHash: String? = nil,
        finalVICRegisterSnapshot: [String]? = nil,
        finalVICState: CompatibilityVICStateExpectation? = nil,
        finalSIDModel: String? = nil,
        finalSIDAccuracyMode: String? = nil,
        finalSIDAudioSignature: SIDAudioSignatureRecord? = nil,
        finalSIDAudioState: SIDAudioStateRecord? = nil,
        finalSIDRegisterSnapshot: [String]? = nil,
        finalSIDReadableRegisterSnapshot: [String]? = nil,
        finalSIDVoiceStates: [SIDVoiceStateRecord]? = nil,
        finalDrivePC: String? = nil,
        finalTrack: Int? = nil,
        finalHalfTrack: Int? = nil,
        finalHeadBitPosition: Int? = nil,
        finalReadTrack: Int? = nil,
        finalReadHalfTrack: Int? = nil,
        finalUsingHalfTrackFallback: Bool? = nil,
        finalByteReadyCount: UInt64? = nil,
        finalVia2PortAReadCount: UInt64? = nil,
        finalWeakBitReadCount: UInt64? = nil,
        finalLastWeakBitHalfTrack: Int? = nil,
        finalLastWeakBitPosition: Int? = nil,
        finalVariableSpeedZoneSampleCount: UInt64? = nil,
        finalVariableSpeedZoneMask: UInt8? = nil,
        finalLastVariableSpeedZoneHalfTrack: Int? = nil,
        finalLastVariableSpeedZoneByteIndex: Int? = nil,
        finalLastVariableSpeedZone: Int? = nil,
        finalGCRWriteByteCount: UInt64? = nil,
        finalGCRWriteModeActive: Bool? = nil,
        finalGCRWriteGateActive: Bool? = nil,
        finalGCRWriteSpliceCount: UInt64? = nil,
        finalGCRWriteEraseBitCount: UInt64? = nil,
        finalD64ExportBlockedByLowLevelWrites: Bool? = nil,
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
        finalMediaPreservesWeakBitRanges: Bool? = nil,
        finalMediaSectorErrorCodeCount: Int? = nil,
        finalMediaNonDefaultSectorErrorCodeCount: Int? = nil,
        finalMediaWeakBitRangeCount: Int? = nil,
        finalMediaWeakBitTotalBitCount: Int? = nil,
        finalMediaHasDuplicateSectorHeaders: Bool? = nil,
        finalMediaDuplicateSectorHeaderCount: Int? = nil,
        finalMediaVariableSpeedZoneByteCount: Int? = nil,
        finalMediaSupportsWraparoundReads: Bool? = nil,
        finalMediaMaxTrackSize: Int? = nil,
        finalMediaUnsupportedFeatures: [String]? = nil,
        finalLowLevelTracks: [LowLevelTrackRecord]? = nil,
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
        framebufferHash: String? = nil,
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
        self.roadmapPhase = roadmapPhase
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
        self.finalVICBALineLow = finalVICBALineLow
        self.finalVICAECLineLow = finalVICAECLineLow
        self.finalVICBusOwner = finalVICBusOwner
        self.finalVICBusPhase = finalVICBusPhase
        self.finalVICLowPhaseAccess = finalVICLowPhaseAccess
        self.finalVICHighPhaseMemoryReads = finalVICHighPhaseMemoryReads
        self.finalVICHighPhaseColorRAMReads = finalVICHighPhaseColorRAMReads
        self.finalVICLowPhaseMemoryReads = finalVICLowPhaseMemoryReads
        self.finalVICRegisterSnapshotHash = finalVICRegisterSnapshotHash
        self.finalVICRegisterSnapshot = finalVICRegisterSnapshot
        self.finalVICState = finalVICState
        self.finalSIDModel = finalSIDModel
        self.finalSIDAccuracyMode = finalSIDAccuracyMode
        self.finalSIDAudioSignature = finalSIDAudioSignature
        self.finalSIDAudioState = finalSIDAudioState
        self.finalSIDRegisterSnapshot = finalSIDRegisterSnapshot
        self.finalSIDReadableRegisterSnapshot = finalSIDReadableRegisterSnapshot
        self.finalSIDVoiceStates = finalSIDVoiceStates
        self.finalDrivePC = finalDrivePC
        self.finalTrack = finalTrack
        self.finalHalfTrack = finalHalfTrack
        self.finalHeadBitPosition = finalHeadBitPosition
        self.finalReadTrack = finalReadTrack
        self.finalReadHalfTrack = finalReadHalfTrack
        self.finalUsingHalfTrackFallback = finalUsingHalfTrackFallback
        self.finalByteReadyCount = finalByteReadyCount
        self.finalVia2PortAReadCount = finalVia2PortAReadCount
        self.finalWeakBitReadCount = finalWeakBitReadCount
        self.finalLastWeakBitHalfTrack = finalLastWeakBitHalfTrack
        self.finalLastWeakBitPosition = finalLastWeakBitPosition
        self.finalVariableSpeedZoneSampleCount = finalVariableSpeedZoneSampleCount
        self.finalVariableSpeedZoneMask = finalVariableSpeedZoneMask
        self.finalLastVariableSpeedZoneHalfTrack = finalLastVariableSpeedZoneHalfTrack
        self.finalLastVariableSpeedZoneByteIndex = finalLastVariableSpeedZoneByteIndex
        self.finalLastVariableSpeedZone = finalLastVariableSpeedZone
        self.finalGCRWriteByteCount = finalGCRWriteByteCount
        self.finalGCRWriteModeActive = finalGCRWriteModeActive
        self.finalGCRWriteGateActive = finalGCRWriteGateActive
        self.finalGCRWriteSpliceCount = finalGCRWriteSpliceCount
        self.finalGCRWriteEraseBitCount = finalGCRWriteEraseBitCount
        self.finalD64ExportBlockedByLowLevelWrites = finalD64ExportBlockedByLowLevelWrites
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
        self.finalMediaPreservesWeakBitRanges = finalMediaPreservesWeakBitRanges
        self.finalMediaSectorErrorCodeCount = finalMediaSectorErrorCodeCount
        self.finalMediaNonDefaultSectorErrorCodeCount = finalMediaNonDefaultSectorErrorCodeCount
        self.finalMediaWeakBitRangeCount = finalMediaWeakBitRangeCount
        self.finalMediaWeakBitTotalBitCount = finalMediaWeakBitTotalBitCount
        self.finalMediaHasDuplicateSectorHeaders = finalMediaHasDuplicateSectorHeaders
        self.finalMediaDuplicateSectorHeaderCount = finalMediaDuplicateSectorHeaderCount
        self.finalMediaVariableSpeedZoneByteCount = finalMediaVariableSpeedZoneByteCount
        self.finalMediaSupportsWraparoundReads = finalMediaSupportsWraparoundReads
        self.finalMediaMaxTrackSize = finalMediaMaxTrackSize
        self.finalMediaUnsupportedFeatures = finalMediaUnsupportedFeatures
        self.finalLowLevelTracks = finalLowLevelTracks
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
        self.framebufferHash = framebufferHash
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
    let finalPC: String?
    let finalVICRasterLine: Int?
    let finalVICRasterCycle: Int?
    let finalVICBusOwner: String?
    let finalVICBusPhase: String?
    let finalVICLowPhaseAccess: String?
    let finalVICHighPhaseMemoryReads: [String]?
    let finalVICHighPhaseColorRAMReads: [String]?
    let finalVICLowPhaseMemoryReads: [String]?
    let finalVICRegisterSnapshotHash: String?
    let finalVICState: CompatibilityVICStateExpectation?

    init(
        key: MilestoneResultKey,
        category: String,
        reason: String,
        elapsedCycles: UInt64,
        finalPC: String? = nil,
        finalVICRasterLine: Int? = nil,
        finalVICRasterCycle: Int? = nil,
        finalVICBusOwner: String? = nil,
        finalVICBusPhase: String? = nil,
        finalVICLowPhaseAccess: String? = nil,
        finalVICHighPhaseMemoryReads: [String]? = nil,
        finalVICHighPhaseColorRAMReads: [String]? = nil,
        finalVICLowPhaseMemoryReads: [String]? = nil,
        finalVICRegisterSnapshotHash: String? = nil,
        finalVICState: CompatibilityVICStateExpectation? = nil
    ) {
        self.key = key
        self.category = category
        self.reason = reason
        self.elapsedCycles = elapsedCycles
        self.finalPC = finalPC
        self.finalVICRasterLine = finalVICRasterLine
        self.finalVICRasterCycle = finalVICRasterCycle
        self.finalVICBusOwner = finalVICBusOwner
        self.finalVICBusPhase = finalVICBusPhase
        self.finalVICLowPhaseAccess = finalVICLowPhaseAccess
        self.finalVICHighPhaseMemoryReads = finalVICHighPhaseMemoryReads
        self.finalVICHighPhaseColorRAMReads = finalVICHighPhaseColorRAMReads
        self.finalVICLowPhaseMemoryReads = finalVICLowPhaseMemoryReads
        self.finalVICRegisterSnapshotHash = finalVICRegisterSnapshotHash
        self.finalVICState = finalVICState
    }

    var finalDiagnostics: String {
        let vicTrace = [
            ("vicHigh", finalVICHighPhaseMemoryReads),
            ("vicColor", finalVICHighPhaseColorRAMReads),
            ("vicLow", finalVICLowPhaseMemoryReads),
        ]
            .compactMap { label, values -> String? in
                guard let values else { return nil }
                return "\(label)=\(values.isEmpty ? "[]" : "[" + values.joined(separator: ",") + "]")"
            }
            .joined(separator: " ")
        let fields: [String?] = [
            finalPC.map { "pc=$\($0)" },
            finalVICRasterLine.map { "vicLine=\($0)" },
            finalVICRasterCycle.map { "vicCycle=\($0)" },
            finalVICBusOwner.map { "vicOwner=\($0)" },
            finalVICBusPhase.map { "vicPhase=\($0)" },
            finalVICLowPhaseAccess.map { "vicLowPhase=\($0)" },
            finalVICRegisterSnapshotHash.map { "vicRegs=\($0)" },
            finalVICState.map { "vicState=\(compactVICStateSummary($0))" },
            vicTrace.isEmpty ? nil : vicTrace,
        ]
        let compact = fields.compactMap(\.self).joined(separator: " ")
        return compact.isEmpty ? "final=unknown" : compact
    }
}

private struct MilestoneExpectedFailureDriftSummary: Codable, Equatable {
    let key: MilestoneResultKey
    let category: String
    let reason: String
    let elapsedCycles: UInt64
    let mismatches: [String]
    let finalPC: String?
    let finalVICRasterLine: Int?
    let finalVICRasterCycle: Int?
    let finalVICBusOwner: String?
    let finalVICBusPhase: String?
    let finalVICLowPhaseAccess: String?
    let finalVICHighPhaseMemoryReads: [String]?
    let finalVICHighPhaseColorRAMReads: [String]?
    let finalVICLowPhaseMemoryReads: [String]?
    let finalVICRegisterSnapshotHash: String?
    let finalVICState: CompatibilityVICStateExpectation?

    init(
        key: MilestoneResultKey,
        category: String,
        reason: String,
        elapsedCycles: UInt64,
        mismatches: [String],
        finalPC: String? = nil,
        finalVICRasterLine: Int? = nil,
        finalVICRasterCycle: Int? = nil,
        finalVICBusOwner: String? = nil,
        finalVICBusPhase: String? = nil,
        finalVICLowPhaseAccess: String? = nil,
        finalVICHighPhaseMemoryReads: [String]? = nil,
        finalVICHighPhaseColorRAMReads: [String]? = nil,
        finalVICLowPhaseMemoryReads: [String]? = nil,
        finalVICRegisterSnapshotHash: String? = nil,
        finalVICState: CompatibilityVICStateExpectation? = nil
    ) {
        self.key = key
        self.category = category
        self.reason = reason
        self.elapsedCycles = elapsedCycles
        self.mismatches = mismatches
        self.finalPC = finalPC
        self.finalVICRasterLine = finalVICRasterLine
        self.finalVICRasterCycle = finalVICRasterCycle
        self.finalVICBusOwner = finalVICBusOwner
        self.finalVICBusPhase = finalVICBusPhase
        self.finalVICLowPhaseAccess = finalVICLowPhaseAccess
        self.finalVICHighPhaseMemoryReads = finalVICHighPhaseMemoryReads
        self.finalVICHighPhaseColorRAMReads = finalVICHighPhaseColorRAMReads
        self.finalVICLowPhaseMemoryReads = finalVICLowPhaseMemoryReads
        self.finalVICRegisterSnapshotHash = finalVICRegisterSnapshotHash
        self.finalVICState = finalVICState
    }

    var finalDiagnostics: String {
        MilestoneFailureSummary(
            key: key,
            category: category,
            reason: reason,
            elapsedCycles: elapsedCycles,
            finalPC: finalPC,
            finalVICRasterLine: finalVICRasterLine,
            finalVICRasterCycle: finalVICRasterCycle,
            finalVICBusOwner: finalVICBusOwner,
            finalVICBusPhase: finalVICBusPhase,
            finalVICLowPhaseAccess: finalVICLowPhaseAccess,
            finalVICHighPhaseMemoryReads: finalVICHighPhaseMemoryReads,
            finalVICHighPhaseColorRAMReads: finalVICHighPhaseColorRAMReads,
            finalVICLowPhaseMemoryReads: finalVICLowPhaseMemoryReads,
            finalVICRegisterSnapshotHash: finalVICRegisterSnapshotHash,
            finalVICState: finalVICState
        ).finalDiagnostics
    }
}

private func compactVICStateSummary(_ state: CompatibilityVICStateExpectation) -> String {
    var parts: [String] = []
    if let badLine = state.badLine { parts.append("badLine=\(badLine)") }
    if let start = state.badLineStartCycle { parts.append("badStart=\(start)") }
    if let den = state.badLineDENLatched { parts.append("den=\(den)") }
    if let display = state.displayActive { parts.append("display=\(display)") }
    if let vertical = state.verticalBorderActive { parts.append("vBorder=\(vertical)") }
    if let horizontal = state.horizontalBorderActive { parts.append("hBorder=\(horizontal)") }
    if let rowCounter = state.rowCounter { parts.append("rc=\(rowCounter)") }
    if let videoCounter = state.videoCounter { parts.append("vc=\(videoCounter)") }
    if let videoCounterBase = state.videoCounterBase { parts.append("vcbase=\(videoCounterBase)") }
    if let displayBase = state.displayLineBufferBase { parts.append("linebase=\(displayBase)") }
    if let mask = state.badLineFetchMask { parts.append(String(format: "badMask=$%010llX", mask)) }
    if let mask = state.graphicsFetchMask { parts.append(String(format: "gfxMask=$%010llX", mask)) }
    if let spriteMC = state.spriteMC { parts.append("mc=[\(spriteMC.map(String.init).joined(separator: ","))]") }
    if let spriteMCBase = state.spriteMCBase { parts.append("mcb=[\(spriteMCBase.map(String.init).joined(separator: ","))]") }
    if let spriteYExpFF = state.spriteYExpFF { parts.append("yexp=[\(spriteYExpFF.map { $0 ? "1" : "0" }.joined())]") }
    if let spriteDisplay = state.spriteDisplay { parts.append("sprdisp=[\(spriteDisplay.map { $0 ? "1" : "0" }.joined())]") }
    return parts.isEmpty ? "empty" : parts.joined(separator: ",")
}

private struct MilestonePhaseBreakdown: Codable, Equatable {
    var total: Int
    var passed: Int
    var failed: Int
    var skipped: Int
    var expectedFailures: Int
    var unexpectedFailures: Int
    var expectedFailureDrift: Int
    var unclassifiedFailures: Int

    init(
        total: Int = 0,
        passed: Int = 0,
        failed: Int = 0,
        skipped: Int = 0,
        expectedFailures: Int = 0,
        unexpectedFailures: Int = 0,
        expectedFailureDrift: Int = 0,
        unclassifiedFailures: Int = 0
    ) {
        self.total = total
        self.passed = passed
        self.failed = failed
        self.skipped = skipped
        self.expectedFailures = expectedFailures
        self.unexpectedFailures = unexpectedFailures
        self.expectedFailureDrift = expectedFailureDrift
        self.unclassifiedFailures = unclassifiedFailures
    }
}

private enum MilestonePhaseOutcome {
    static let passed = "passed"
    static let skipped = "skipped"
    static let expectedFailures = "expectedFailures"
    static let expectedFailureDrift = "expectedFailureDrift"
    static let unexpectedFailures = "unexpectedFailures"
    static let unclassifiedFailures = "unclassifiedFailures"
    static let failures = "failures"

    static func isAcceptanceFailure(_ outcome: String) -> Bool {
        switch outcome {
        case expectedFailureDrift, unexpectedFailures, unclassifiedFailures, failures:
            return true
        default:
            return false
        }
    }
}

private struct MilestoneRunSummary: Codable, Equatable {
    var formatVersion: Int = 42
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
    var screenshotsWrittenCount: Int = 0
    var passedScreenshotCount: Int = 0
    var failedScreenshotCount: Int = 0
    var milestoneLimit: Int?
    var milestoneShardIndex: Int?
    var milestoneShardCount: Int?
    var preShardMilestoneCount: Int?
    var postShardMilestoneCount: Int?
    var manifestValidationErrors: [String] = []
    var invalidShardConfiguration: String?
    var manifestMilestoneCount: Int?
    var manifestPhaseCounts: [String: Int] = [:]
    var manifestMediaCounts: [String: Int] = [:]
    var manifestMachineProfileCounts: [String: Int] = [:]
    var manifestDriveModeCounts: [String: Int] = [:]
    var manifestSIDModelCounts: [String: Int] = [:]
    var manifestSIDAccuracyModeCounts: [String: Int] = [:]
    var manifestObservableTypeCounts: [String: Int] = [:]
    var manifestVICProofCounts: [String: Int] = [:]
    var manifestExpectedFailureCategoryCounts: [String: Int] = [:]
    var manifestActionTypeCounts: [String: Int] = [:]
    var manifestUntaggedMilestoneCount: Int = 0
    var manifestUnnamedMilestoneCount: Int = 0
    var manifestExpectedFailureCount: Int = 0
    var manifestExpectedFailuresWithoutNotesCount: Int = 0
    var manifestExpectedFailuresWithoutReasonMarkersCount: Int = 0
    var manifestMilestonesWithoutMaxCyclesCount: Int = 0
    var manifestMilestonesWithoutExplicitActionsCount: Int = 0
    var manifestMilestonesWithoutObservableExpectationsCount: Int = 0
    var manifestPhase3MilestonesWithoutVICProofCount: Int = 0
    var manifestPhase3MilestonesMissingRequiredVICProofsCount: Int = 0
    var manifestFramebufferHashMilestonesWithoutScreenshotNamesCount: Int = 0
    var manifestFramebufferScreenshotFilenameCollisionCount: Int = 0
    var manifestFramebufferScreenshotFilenameCollisions: [String] = []
    var manifestPlaceholderProofHashCount: Int = 0
    var phaseFilteredMilestoneCount: Int?
    var selectedMilestoneCount: Int?
    var selectedMilestoneKeys: [MilestoneResultKey] = []
    var selectedMediaCounts: [String: Int] = [:]
    var selectedMachineProfileCounts: [String: Int] = [:]
    var selectedDriveModeCounts: [String: Int] = [:]
    var selectedSIDModelCounts: [String: Int] = [:]
    var selectedSIDAccuracyModeCounts: [String: Int] = [:]
    var selectedObservableTypeCounts: [String: Int] = [:]
    var selectedVICProofCounts: [String: Int] = [:]
    var selectedExpectedFailureCategoryCounts: [String: Int] = [:]
    var selectedActionTypeCounts: [String: Int] = [:]
    var missingMediaFiles: [String] = []
    var requireAllManifestMedia: Bool = false
    var requiredManifestMediaTypes: [String] = []
    var invalidRequiredManifestMediaTypes: [String] = []
    var missingRequiredManifestMediaTypes: [String] = []
    var requiredManifestMachineProfiles: [String] = []
    var invalidRequiredManifestMachineProfiles: [String] = []
    var missingRequiredManifestMachineProfiles: [String] = []
    var requiredManifestDriveModes: [String] = []
    var invalidRequiredManifestDriveModes: [String] = []
    var missingRequiredManifestDriveModes: [String] = []
    var requiredManifestSIDModels: [String] = []
    var invalidRequiredManifestSIDModels: [String] = []
    var missingRequiredManifestSIDModels: [String] = []
    var requiredManifestSIDAccuracyModes: [String] = []
    var invalidRequiredManifestSIDAccuracyModes: [String] = []
    var missingRequiredManifestSIDAccuracyModes: [String] = []
    var requiredManifestObservableTypes: [String] = []
    var invalidRequiredManifestObservableTypes: [String] = []
    var missingRequiredManifestObservableTypes: [String] = []
    var requiredManifestVICProofs: [String] = []
    var invalidRequiredManifestVICProofs: [String] = []
    var missingRequiredManifestVICProofs: [String] = []
    var requiredManifestFailureCategories: [String] = []
    var invalidRequiredManifestFailureCategories: [String] = []
    var missingRequiredManifestFailureCategories: [String] = []
    var requiredManifestActionTypes: [String] = []
    var invalidRequiredManifestActionTypes: [String] = []
    var missingRequiredManifestActionTypes: [String] = []
    var selectedPhaseNames: [String] = []
    var invalidSelectedPhaseNames: [String] = []
    var selectedPhaseCounts: [String: Int] = [:]
    var missingSelectedPhaseNames: [String] = []
    var selectedMilestoneIDs: [String] = []
    var missingSelectedMilestoneIDs: [String] = []
    var requireSelectedPhases: Bool = false
    var requireSelectedMilestoneIDs: Bool = false
    var requireManifest: Bool = false
    var requireTaggedManifestPhases: Bool = false
    var requireManifestMilestoneIDs: Bool = false
    var requireExpectedFailureNotes: Bool = false
    var requireExpectedFailureReasonMarkers: Bool = false
    var requireExplicitMaxCycles: Bool = false
    var requireExplicitActions: Bool = false
    var requireObservableExpectations: Bool = false
    var requirePhase3VICProofs: Bool = false
    var requireFramebufferScreenshots: Bool = false
    var rejectPlaceholderProofHashes: Bool = false
    var failOnUnclassified: Bool = false
    var failOnUnexpected: Bool = false
    var failPhaseNames: [String] = []
    var invalidFailPhaseNames: [String] = []
    var outcome: String?
    var acceptanceFailures: [String]?
    var phaseAcceptanceFailures: [String] = []
    var total: Int = 0
    var executed: Int = 0
    var passed: Int = 0
    var failed: Int = 0
    var skipped: Int = 0
    var expectedFailures: Int = 0
    var unexpectedFailures: Int = 0
    var expectedFailureDriftCount: Int = 0
    var unclassifiedFailureCount: Int = 0
    var totalElapsedCycles: UInt64 = 0
    var maxElapsedCycles: UInt64 = 0
    var slowestMilestone: MilestoneResultKey?
    var categories: [String: Int] = [:]
    var phaseCounts: [String: Int] = [:]
    var phaseBreakdown: [String: MilestonePhaseBreakdown] = [:]
    var phaseOutcomes: [String: String] = [:]
    var phaseFailureDetails: [String: [MilestoneFailureSummary]] = [:]
    var phaseExpectedFailureDriftDetails: [String: [MilestoneExpectedFailureDriftSummary]] = [:]
    var failedMilestones: [MilestoneResultKey] = []
    var failedMilestoneDetails: [MilestoneFailureSummary] = []
    var expectedFailureDetails: [MilestoneFailureSummary] = []
    var unexpectedFailureDetails: [MilestoneFailureSummary] = []
    var expectedFailureDriftDetails: [MilestoneExpectedFailureDriftSummary] = []
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
        milestoneShardIndex: Int? = nil,
        milestoneShardCount: Int? = nil,
        preShardMilestoneCount: Int? = nil,
        postShardMilestoneCount: Int? = nil,
        manifestValidationErrors: [String] = [],
        invalidShardConfiguration: String? = nil,
        manifestMilestoneCount: Int?,
        manifestPhaseCounts: [String: Int] = [:],
        manifestMediaCounts: [String: Int] = [:],
        manifestMachineProfileCounts: [String: Int] = [:],
        manifestDriveModeCounts: [String: Int] = [:],
        manifestSIDModelCounts: [String: Int] = [:],
        manifestSIDAccuracyModeCounts: [String: Int] = [:],
        manifestObservableTypeCounts: [String: Int] = [:],
        manifestVICProofCounts: [String: Int] = [:],
        manifestExpectedFailureCategoryCounts: [String: Int] = [:],
        manifestActionTypeCounts: [String: Int] = [:],
        manifestUntaggedMilestoneCount: Int = 0,
        manifestUnnamedMilestoneCount: Int = 0,
        manifestExpectedFailureCount: Int = 0,
        manifestExpectedFailuresWithoutNotesCount: Int = 0,
        manifestExpectedFailuresWithoutReasonMarkersCount: Int = 0,
        manifestMilestonesWithoutMaxCyclesCount: Int = 0,
        manifestMilestonesWithoutExplicitActionsCount: Int = 0,
        manifestMilestonesWithoutObservableExpectationsCount: Int = 0,
        manifestPhase3MilestonesWithoutVICProofCount: Int = 0,
        manifestPhase3MilestonesMissingRequiredVICProofsCount: Int = 0,
        manifestFramebufferHashMilestonesWithoutScreenshotNamesCount: Int = 0,
        manifestFramebufferScreenshotFilenameCollisionCount: Int = 0,
        manifestFramebufferScreenshotFilenameCollisions: [String] = [],
        manifestPlaceholderProofHashCount: Int = 0,
        phaseFilteredMilestoneCount: Int? = nil,
        selectedMilestoneCount: Int?,
        selectedMilestoneKeys: [MilestoneResultKey] = [],
        selectedMediaCounts: [String: Int] = [:],
        selectedMachineProfileCounts: [String: Int] = [:],
        selectedDriveModeCounts: [String: Int] = [:],
        selectedSIDModelCounts: [String: Int] = [:],
        selectedSIDAccuracyModeCounts: [String: Int] = [:],
        selectedObservableTypeCounts: [String: Int] = [:],
        selectedVICProofCounts: [String: Int] = [:],
        selectedExpectedFailureCategoryCounts: [String: Int] = [:],
        selectedActionTypeCounts: [String: Int] = [:],
        missingMediaFiles: [String],
        requireAllManifestMedia: Bool,
        requiredManifestMediaTypes: [String] = [],
        invalidRequiredManifestMediaTypes: [String] = [],
        requiredManifestMachineProfiles: [String] = [],
        invalidRequiredManifestMachineProfiles: [String] = [],
        requiredManifestDriveModes: [String] = [],
        invalidRequiredManifestDriveModes: [String] = [],
        requiredManifestSIDModels: [String] = [],
        invalidRequiredManifestSIDModels: [String] = [],
        requiredManifestSIDAccuracyModes: [String] = [],
        invalidRequiredManifestSIDAccuracyModes: [String] = [],
        requiredManifestObservableTypes: [String] = [],
        invalidRequiredManifestObservableTypes: [String] = [],
        requiredManifestVICProofs: [String] = [],
        invalidRequiredManifestVICProofs: [String] = [],
        requiredManifestFailureCategories: [String] = [],
        invalidRequiredManifestFailureCategories: [String] = [],
        requiredManifestActionTypes: [String] = [],
        invalidRequiredManifestActionTypes: [String] = [],
        selectedPhaseNames: [String] = [],
        invalidSelectedPhaseNames: [String] = [],
        selectedPhaseCounts: [String: Int] = [:],
        missingSelectedPhaseNames: [String] = [],
        selectedMilestoneIDs: [String] = [],
        missingSelectedMilestoneIDs: [String] = [],
        requireSelectedPhases: Bool = false,
        requireSelectedMilestoneIDs: Bool = false,
        requireManifest: Bool = false,
        requireTaggedManifestPhases: Bool = false,
        requireManifestMilestoneIDs: Bool = false,
        requireExpectedFailureNotes: Bool = false,
        requireExpectedFailureReasonMarkers: Bool = false,
        requireExplicitMaxCycles: Bool = false,
        requireExplicitActions: Bool = false,
        requireObservableExpectations: Bool = false,
        requirePhase3VICProofs: Bool = false,
        requireFramebufferScreenshots: Bool = false,
        rejectPlaceholderProofHashes: Bool = false,
        failOnUnclassified: Bool,
        failOnUnexpected: Bool,
        failPhaseNames: [String] = [],
        invalidFailPhaseNames: [String] = []
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
        self.milestoneShardIndex = milestoneShardIndex
        self.milestoneShardCount = milestoneShardCount
        self.preShardMilestoneCount = preShardMilestoneCount
        self.postShardMilestoneCount = postShardMilestoneCount
        self.manifestValidationErrors = manifestValidationErrors
        self.invalidShardConfiguration = invalidShardConfiguration
        self.manifestMilestoneCount = manifestMilestoneCount
        self.manifestPhaseCounts = manifestPhaseCounts
        self.manifestMediaCounts = manifestMediaCounts
        self.manifestMachineProfileCounts = manifestMachineProfileCounts
        self.manifestDriveModeCounts = manifestDriveModeCounts
        self.manifestSIDModelCounts = manifestSIDModelCounts
        self.manifestSIDAccuracyModeCounts = manifestSIDAccuracyModeCounts
        self.manifestObservableTypeCounts = manifestObservableTypeCounts
        self.manifestVICProofCounts = manifestVICProofCounts
        self.manifestExpectedFailureCategoryCounts = manifestExpectedFailureCategoryCounts
        self.manifestActionTypeCounts = manifestActionTypeCounts
        self.manifestUntaggedMilestoneCount = manifestUntaggedMilestoneCount
        self.manifestUnnamedMilestoneCount = manifestUnnamedMilestoneCount
        self.manifestExpectedFailureCount = manifestExpectedFailureCount
        self.manifestExpectedFailuresWithoutNotesCount = manifestExpectedFailuresWithoutNotesCount
        self.manifestExpectedFailuresWithoutReasonMarkersCount = manifestExpectedFailuresWithoutReasonMarkersCount
        self.manifestMilestonesWithoutMaxCyclesCount = manifestMilestonesWithoutMaxCyclesCount
        self.manifestMilestonesWithoutExplicitActionsCount = manifestMilestonesWithoutExplicitActionsCount
        self.manifestMilestonesWithoutObservableExpectationsCount = manifestMilestonesWithoutObservableExpectationsCount
        self.manifestPhase3MilestonesWithoutVICProofCount = manifestPhase3MilestonesWithoutVICProofCount
        self.manifestPhase3MilestonesMissingRequiredVICProofsCount = manifestPhase3MilestonesMissingRequiredVICProofsCount
        self.manifestFramebufferHashMilestonesWithoutScreenshotNamesCount = manifestFramebufferHashMilestonesWithoutScreenshotNamesCount
        self.manifestFramebufferScreenshotFilenameCollisionCount = manifestFramebufferScreenshotFilenameCollisionCount
        self.manifestFramebufferScreenshotFilenameCollisions = manifestFramebufferScreenshotFilenameCollisions
        self.manifestPlaceholderProofHashCount = manifestPlaceholderProofHashCount
        self.phaseFilteredMilestoneCount = phaseFilteredMilestoneCount
        self.selectedMilestoneCount = selectedMilestoneCount
        self.selectedMilestoneKeys = selectedMilestoneKeys
        self.selectedMediaCounts = selectedMediaCounts
        self.selectedMachineProfileCounts = selectedMachineProfileCounts
        self.selectedDriveModeCounts = selectedDriveModeCounts
        self.selectedSIDModelCounts = selectedSIDModelCounts
        self.selectedSIDAccuracyModeCounts = selectedSIDAccuracyModeCounts
        self.selectedObservableTypeCounts = selectedObservableTypeCounts
        self.selectedVICProofCounts = selectedVICProofCounts
        self.selectedExpectedFailureCategoryCounts = selectedExpectedFailureCategoryCounts
        self.selectedActionTypeCounts = selectedActionTypeCounts
        self.missingMediaFiles = missingMediaFiles
        self.requireAllManifestMedia = requireAllManifestMedia
        self.requiredManifestMediaTypes = requiredManifestMediaTypes
        self.invalidRequiredManifestMediaTypes = invalidRequiredManifestMediaTypes
        missingRequiredManifestMediaTypes = requiredManifestMediaTypes.filter {
            manifestMediaCounts[$0, default: 0] == 0
        }
        self.requiredManifestMachineProfiles = requiredManifestMachineProfiles
        self.invalidRequiredManifestMachineProfiles = invalidRequiredManifestMachineProfiles
        missingRequiredManifestMachineProfiles = requiredManifestMachineProfiles.filter {
            manifestMachineProfileCounts[$0, default: 0] == 0
        }
        self.requiredManifestDriveModes = requiredManifestDriveModes
        self.invalidRequiredManifestDriveModes = invalidRequiredManifestDriveModes
        missingRequiredManifestDriveModes = requiredManifestDriveModes.filter {
            manifestDriveModeCounts[$0, default: 0] == 0
        }
        self.requiredManifestSIDModels = requiredManifestSIDModels
        self.invalidRequiredManifestSIDModels = invalidRequiredManifestSIDModels
        missingRequiredManifestSIDModels = requiredManifestSIDModels.filter {
            manifestSIDModelCounts[$0, default: 0] == 0
        }
        self.requiredManifestSIDAccuracyModes = requiredManifestSIDAccuracyModes
        self.invalidRequiredManifestSIDAccuracyModes = invalidRequiredManifestSIDAccuracyModes
        missingRequiredManifestSIDAccuracyModes = requiredManifestSIDAccuracyModes.filter {
            manifestSIDAccuracyModeCounts[$0, default: 0] == 0
        }
        self.requiredManifestObservableTypes = requiredManifestObservableTypes
        self.invalidRequiredManifestObservableTypes = invalidRequiredManifestObservableTypes
        missingRequiredManifestObservableTypes = requiredManifestObservableTypes.filter {
            manifestObservableTypeCounts[$0, default: 0] == 0
        }
        self.requiredManifestVICProofs = requiredManifestVICProofs
        self.invalidRequiredManifestVICProofs = invalidRequiredManifestVICProofs
        missingRequiredManifestVICProofs = requiredManifestVICProofs.filter {
            manifestVICProofCounts[$0, default: 0] == 0
        }
        self.requiredManifestFailureCategories = requiredManifestFailureCategories
        self.invalidRequiredManifestFailureCategories = invalidRequiredManifestFailureCategories
        missingRequiredManifestFailureCategories = requiredManifestFailureCategories.filter {
            manifestExpectedFailureCategoryCounts[$0, default: 0] == 0
        }
        self.requiredManifestActionTypes = requiredManifestActionTypes
        self.invalidRequiredManifestActionTypes = invalidRequiredManifestActionTypes
        missingRequiredManifestActionTypes = requiredManifestActionTypes.filter {
            manifestActionTypeCounts[$0, default: 0] == 0
        }
        self.selectedPhaseNames = selectedPhaseNames
        self.invalidSelectedPhaseNames = invalidSelectedPhaseNames
        self.selectedPhaseCounts = selectedPhaseCounts
        self.missingSelectedPhaseNames = missingSelectedPhaseNames
        self.selectedMilestoneIDs = selectedMilestoneIDs
        self.missingSelectedMilestoneIDs = missingSelectedMilestoneIDs
        self.requireSelectedPhases = requireSelectedPhases
        self.requireSelectedMilestoneIDs = requireSelectedMilestoneIDs
        self.requireManifest = requireManifest
        self.requireTaggedManifestPhases = requireTaggedManifestPhases
        self.requireManifestMilestoneIDs = requireManifestMilestoneIDs
        self.requireExpectedFailureNotes = requireExpectedFailureNotes
        self.requireExpectedFailureReasonMarkers = requireExpectedFailureReasonMarkers
        self.requireExplicitMaxCycles = requireExplicitMaxCycles
        self.requireExplicitActions = requireExplicitActions
        self.requireObservableExpectations = requireObservableExpectations
        self.requirePhase3VICProofs = requirePhase3VICProofs
        self.requireFramebufferScreenshots = requireFramebufferScreenshots
        self.rejectPlaceholderProofHashes = rejectPlaceholderProofHashes
        self.failOnUnclassified = failOnUnclassified
        self.failOnUnexpected = failOnUnexpected
        self.failPhaseNames = failPhaseNames
        self.invalidFailPhaseNames = invalidFailPhaseNames
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
        let roadmapPhase = record.roadmapPhase ?? MilestoneRoadmapPhase.phaseName(forCategory: category)
        if record.screenshotPath != nil {
            screenshotsWrittenCount += 1
            if record.passed {
                passedScreenshotCount += 1
            } else {
                failedScreenshotCount += 1
            }
        }
        if record.passed {
            passed += 1
        } else {
            failed += 1
            let failureSummary = MilestoneFailureSummary(
                key: record.key,
                category: category,
                reason: record.reason,
                elapsedCycles: record.elapsedCycles,
                finalPC: record.finalPC,
                finalVICRasterLine: record.finalVICRasterLine,
                finalVICRasterCycle: record.finalVICRasterCycle,
                finalVICBusOwner: record.finalVICBusOwner,
                finalVICBusPhase: record.finalVICBusPhase,
                finalVICLowPhaseAccess: record.finalVICLowPhaseAccess,
                finalVICHighPhaseMemoryReads: record.finalVICHighPhaseMemoryReads,
                finalVICHighPhaseColorRAMReads: record.finalVICHighPhaseColorRAMReads,
                finalVICLowPhaseMemoryReads: record.finalVICLowPhaseMemoryReads,
                finalVICRegisterSnapshotHash: record.finalVICRegisterSnapshotHash,
                finalVICState: record.finalVICState
            )
            phaseFailureDetails[roadmapPhase, default: []].append(failureSummary)
            if record.expectedFailureMatched == true {
                expectedFailures += 1
                expectedFailureDetails.append(failureSummary)
            } else {
                unexpectedFailures += 1
                unexpectedFailureDetails.append(failureSummary)
            }
            if let mismatches = record.expectedFailureMismatches,
               !mismatches.isEmpty {
                expectedFailureDriftCount += 1
                let driftSummary = MilestoneExpectedFailureDriftSummary(
                    key: record.key,
                    category: category,
                    reason: record.reason,
                    elapsedCycles: record.elapsedCycles,
                    mismatches: mismatches,
                    finalPC: record.finalPC,
                    finalVICRasterLine: record.finalVICRasterLine,
                    finalVICRasterCycle: record.finalVICRasterCycle,
                    finalVICBusOwner: record.finalVICBusOwner,
                    finalVICBusPhase: record.finalVICBusPhase,
                    finalVICLowPhaseAccess: record.finalVICLowPhaseAccess,
                    finalVICHighPhaseMemoryReads: record.finalVICHighPhaseMemoryReads,
                    finalVICHighPhaseColorRAMReads: record.finalVICHighPhaseColorRAMReads,
                    finalVICLowPhaseMemoryReads: record.finalVICLowPhaseMemoryReads,
                    finalVICRegisterSnapshotHash: record.finalVICRegisterSnapshotHash,
                    finalVICState: record.finalVICState
                )
                expectedFailureDriftDetails.append(driftSummary)
                phaseExpectedFailureDriftDetails[roadmapPhase, default: []].append(driftSummary)
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
        phaseCounts[roadmapPhase, default: 0] += 1
        var breakdown = phaseBreakdown[roadmapPhase] ?? MilestonePhaseBreakdown()
        breakdown.total += 1
        if record.passed {
            breakdown.passed += 1
        } else {
            breakdown.failed += 1
            if record.expectedFailureMatched == true {
                breakdown.expectedFailures += 1
            } else {
                breakdown.unexpectedFailures += 1
            }
            if let mismatches = record.expectedFailureMismatches,
               !mismatches.isEmpty {
                breakdown.expectedFailureDrift += 1
            }
            if record.expectedFailureMatched != true
                && (category == "unknown" || category == MilestoneResultCategory.emulator.rawValue) {
                breakdown.unclassifiedFailures += 1
            }
        }
        phaseBreakdown[roadmapPhase] = breakdown
    }

    mutating func recordSkipped(_ milestone: LocalMilestone) {
        total += 1
        skipped += 1
        skippedMilestones.append(milestone.resultKey)
        let roadmapPhase = milestone.roadmapPhase ?? MilestoneRoadmapPhase.skipped
        phaseCounts[roadmapPhase, default: 0] += 1
        var breakdown = phaseBreakdown[roadmapPhase] ?? MilestonePhaseBreakdown()
        breakdown.total += 1
        breakdown.skipped += 1
        phaseBreakdown[roadmapPhase] = breakdown
    }

    mutating func refreshDerivedFields() {
        phaseOutcomes = phaseBreakdown.mapValues(Self.phaseOutcome(for:))
        phaseAcceptanceFailures = failPhaseNames.compactMap { phaseName in
            guard let outcome = phaseOutcomes[phaseName],
                  MilestonePhaseOutcome.isAcceptanceFailure(outcome) else {
                return nil
            }
            return "\(phaseName):\(outcome)"
        }
        var gateFailures: [String] = []
        if failOnUnclassified && hasUnclassifiedFailures {
            gateFailures.append("unclassifiedFailures")
        }
        if failOnUnexpected && hasUnexpectedFailures {
            gateFailures.append("unexpectedFailures")
        }
        if !phaseAcceptanceFailures.isEmpty {
            gateFailures.append(contentsOf: phaseAcceptanceFailures.map { "phase:\($0)" })
        }
        if !invalidFailPhaseNames.isEmpty {
            gateFailures.append(contentsOf: invalidFailPhaseNames.map { "invalidPhase:\($0)" })
        }
        if !invalidSelectedPhaseNames.isEmpty {
            gateFailures.append(contentsOf: invalidSelectedPhaseNames.map { "invalidSelectedPhase:\($0)" })
        }
        if let invalidShardConfiguration {
            gateFailures.append(invalidShardConfiguration)
        }
        if !manifestValidationErrors.isEmpty {
            gateFailures.append(contentsOf: manifestValidationErrors.map { "manifestValidation:\($0)" })
        }
        if !invalidRequiredManifestMediaTypes.isEmpty {
            gateFailures.append(contentsOf: invalidRequiredManifestMediaTypes.map { "invalidRequiredMediaType:\($0)" })
        }
        if !missingRequiredManifestMediaTypes.isEmpty {
            gateFailures.append(contentsOf: missingRequiredManifestMediaTypes.map { "missingRequiredMediaType:\($0)" })
        }
        if !invalidRequiredManifestMachineProfiles.isEmpty {
            gateFailures.append(contentsOf: invalidRequiredManifestMachineProfiles.map { "invalidRequiredMachineProfile:\($0)" })
        }
        if !missingRequiredManifestMachineProfiles.isEmpty {
            gateFailures.append(contentsOf: missingRequiredManifestMachineProfiles.map { "missingRequiredMachineProfile:\($0)" })
        }
        if !invalidRequiredManifestDriveModes.isEmpty {
            gateFailures.append(contentsOf: invalidRequiredManifestDriveModes.map { "invalidRequiredDriveMode:\($0)" })
        }
        if !missingRequiredManifestDriveModes.isEmpty {
            gateFailures.append(contentsOf: missingRequiredManifestDriveModes.map { "missingRequiredDriveMode:\($0)" })
        }
        if !invalidRequiredManifestSIDModels.isEmpty {
            gateFailures.append(contentsOf: invalidRequiredManifestSIDModels.map { "invalidRequiredSIDModel:\($0)" })
        }
        if !missingRequiredManifestSIDModels.isEmpty {
            gateFailures.append(contentsOf: missingRequiredManifestSIDModels.map { "missingRequiredSIDModel:\($0)" })
        }
        if !invalidRequiredManifestSIDAccuracyModes.isEmpty {
            gateFailures.append(contentsOf: invalidRequiredManifestSIDAccuracyModes.map { "invalidRequiredSIDAccuracyMode:\($0)" })
        }
        if !missingRequiredManifestSIDAccuracyModes.isEmpty {
            gateFailures.append(contentsOf: missingRequiredManifestSIDAccuracyModes.map { "missingRequiredSIDAccuracyMode:\($0)" })
        }
        if !invalidRequiredManifestObservableTypes.isEmpty {
            gateFailures.append(contentsOf: invalidRequiredManifestObservableTypes.map { "invalidRequiredObservableType:\($0)" })
        }
        if !missingRequiredManifestObservableTypes.isEmpty {
            gateFailures.append(contentsOf: missingRequiredManifestObservableTypes.map { "missingRequiredObservableType:\($0)" })
        }
        if !invalidRequiredManifestVICProofs.isEmpty {
            gateFailures.append(contentsOf: invalidRequiredManifestVICProofs.map { "invalidRequiredVICProof:\($0)" })
        }
        if !missingRequiredManifestVICProofs.isEmpty {
            gateFailures.append(contentsOf: missingRequiredManifestVICProofs.map { "missingRequiredVICProof:\($0)" })
        }
        if !invalidRequiredManifestFailureCategories.isEmpty {
            gateFailures.append(contentsOf: invalidRequiredManifestFailureCategories.map { "invalidRequiredFailureCategory:\($0)" })
        }
        if !missingRequiredManifestFailureCategories.isEmpty {
            gateFailures.append(contentsOf: missingRequiredManifestFailureCategories.map { "missingRequiredFailureCategory:\($0)" })
        }
        if !invalidRequiredManifestActionTypes.isEmpty {
            gateFailures.append(contentsOf: invalidRequiredManifestActionTypes.map { "invalidRequiredActionType:\($0)" })
        }
        if !missingRequiredManifestActionTypes.isEmpty {
            gateFailures.append(contentsOf: missingRequiredManifestActionTypes.map { "missingRequiredActionType:\($0)" })
        }
        if requireSelectedPhases && !missingSelectedPhaseNames.isEmpty {
            gateFailures.append(contentsOf: missingSelectedPhaseNames.map { "missingSelectedPhase:\($0)" })
        }
        if requireSelectedMilestoneIDs && !missingSelectedMilestoneIDs.isEmpty {
            gateFailures.append(contentsOf: missingSelectedMilestoneIDs.map { "missingSelectedMilestoneID:\($0)" })
        }
        if requireManifest && manifestPath == nil {
            gateFailures.append("missingManifest")
        }
        if requireTaggedManifestPhases && manifestUntaggedMilestoneCount > 0 {
            gateFailures.append("untaggedManifestMilestones:\(manifestUntaggedMilestoneCount)")
        }
        if requireManifestMilestoneIDs && manifestUnnamedMilestoneCount > 0 {
            gateFailures.append("unnamedManifestMilestones:\(manifestUnnamedMilestoneCount)")
        }
        if requireExpectedFailureNotes && manifestExpectedFailuresWithoutNotesCount > 0 {
            gateFailures.append("expectedFailuresWithoutNotes:\(manifestExpectedFailuresWithoutNotesCount)")
        }
        if requireExpectedFailureReasonMarkers && manifestExpectedFailuresWithoutReasonMarkersCount > 0 {
            gateFailures.append("expectedFailuresWithoutReasonMarkers:\(manifestExpectedFailuresWithoutReasonMarkersCount)")
        }
        if requireExplicitMaxCycles && manifestMilestonesWithoutMaxCyclesCount > 0 {
            gateFailures.append("milestonesWithoutMaxCycles:\(manifestMilestonesWithoutMaxCyclesCount)")
        }
        if requireExplicitActions && manifestMilestonesWithoutExplicitActionsCount > 0 {
            gateFailures.append("milestonesWithoutExplicitActions:\(manifestMilestonesWithoutExplicitActionsCount)")
        }
        if requireObservableExpectations && manifestMilestonesWithoutObservableExpectationsCount > 0 {
            gateFailures.append("milestonesWithoutObservableExpectations:\(manifestMilestonesWithoutObservableExpectationsCount)")
        }
        if requirePhase3VICProofs && manifestPhase3MilestonesWithoutVICProofCount > 0 {
            gateFailures.append("phase3MilestonesWithoutVICProof:\(manifestPhase3MilestonesWithoutVICProofCount)")
        }
        if requirePhase3VICProofs && manifestPhase3MilestonesMissingRequiredVICProofsCount > 0 {
            gateFailures.append("phase3MilestonesMissingRequiredVICProofs:\(manifestPhase3MilestonesMissingRequiredVICProofsCount)")
        }
        if requireFramebufferScreenshots && manifestFramebufferHashMilestonesWithoutScreenshotNamesCount > 0 {
            gateFailures.append("framebufferHashMilestonesWithoutScreenshotNames:\(manifestFramebufferHashMilestonesWithoutScreenshotNamesCount)")
        }
        if requireFramebufferScreenshots && manifestFramebufferScreenshotFilenameCollisionCount > 0 {
            gateFailures.append("framebufferScreenshotFilenameCollisions:\(manifestFramebufferScreenshotFilenameCollisionCount)")
        }
        if rejectPlaceholderProofHashes && manifestPlaceholderProofHashCount > 0 {
            gateFailures.append("placeholderProofHashes:\(manifestPlaceholderProofHashCount)")
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

    private static func phaseOutcome(for breakdown: MilestonePhaseBreakdown) -> String {
        if breakdown.total == 0 {
            return MilestonePhaseOutcome.skipped
        }
        if breakdown.unclassifiedFailures > 0 {
            return MilestonePhaseOutcome.unclassifiedFailures
        }
        if breakdown.expectedFailureDrift > 0 {
            return MilestonePhaseOutcome.expectedFailureDrift
        }
        if breakdown.unexpectedFailures > 0 {
            return MilestonePhaseOutcome.unexpectedFailures
        }
        if breakdown.failed > 0 {
            if breakdown.expectedFailures == breakdown.failed {
                return MilestonePhaseOutcome.expectedFailures
            }
            return MilestonePhaseOutcome.failures
        }
        if breakdown.skipped == breakdown.total {
            return MilestonePhaseOutcome.skipped
        }
        return MilestonePhaseOutcome.passed
    }

    var consoleSummary: String {
        let categorySummary = categories
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let categoryText = categorySummary.isEmpty ? "none" : categorySummary
        let phaseSummary = phaseCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let phaseText = phaseSummary.isEmpty ? "none" : phaseSummary
        let phaseAcceptanceSummary = phaseAcceptanceFailures
            .map { "phase:\($0)" }
            + invalidFailPhaseNames.map { "invalid:\($0)" }
            + invalidSelectedPhaseNames.map { "invalidSelected:\($0)" }
            + missingSelectedPhaseNames.map { "missingSelected:\($0)" }
            + missingSelectedMilestoneIDs.map { "missingSelectedID:\($0)" }
            + invalidRequiredManifestMediaTypes.map { "invalidRequiredMedia:\($0)" }
            + missingRequiredManifestMediaTypes.map { "missingRequiredMedia:\($0)" }
            + invalidRequiredManifestMachineProfiles.map { "invalidRequiredProfile:\($0)" }
            + missingRequiredManifestMachineProfiles.map { "missingRequiredProfile:\($0)" }
            + invalidRequiredManifestDriveModes.map { "invalidRequiredDrive:\($0)" }
            + missingRequiredManifestDriveModes.map { "missingRequiredDrive:\($0)" }
            + invalidRequiredManifestSIDModels.map { "invalidRequiredSIDModel:\($0)" }
            + missingRequiredManifestSIDModels.map { "missingRequiredSIDModel:\($0)" }
            + invalidRequiredManifestSIDAccuracyModes.map { "invalidRequiredSIDAccuracy:\($0)" }
            + missingRequiredManifestSIDAccuracyModes.map { "missingRequiredSIDAccuracy:\($0)" }
            + invalidRequiredManifestObservableTypes.map { "invalidRequiredObservable:\($0)" }
            + missingRequiredManifestObservableTypes.map { "missingRequiredObservable:\($0)" }
            + invalidRequiredManifestFailureCategories.map { "invalidRequiredFailureCategory:\($0)" }
            + missingRequiredManifestFailureCategories.map { "missingRequiredFailureCategory:\($0)" }
            + invalidRequiredManifestActionTypes.map { "invalidRequiredAction:\($0)" }
            + missingRequiredManifestActionTypes.map { "missingRequiredAction:\($0)" }
        let phaseAcceptanceText = phaseAcceptanceSummary.isEmpty
            ? "none"
            : phaseAcceptanceSummary.joined(separator: " ")
        let outcomeText = outcome ?? "unresolved"
        let selectedText = selectedMilestoneCount.map(String.init) ?? "unknown"
        let phaseFilteredText = phaseFilteredMilestoneCount.map(String.init) ?? "unknown"
        let shardIndexText = milestoneShardIndex.map(String.init) ?? "none"
        let shardCountText = milestoneShardCount.map(String.init) ?? "none"
        let preShardText = preShardMilestoneCount.map(String.init) ?? "unknown"
        let postShardText = postShardMilestoneCount.map(String.init) ?? "unknown"
        let manifestValidationText = manifestValidationErrors.isEmpty
            ? "none"
            : manifestValidationErrors.joined(separator: " | ")
        let invalidShardText = invalidShardConfiguration ?? "none"
        let manifestPhaseCountText = manifestPhaseCounts.isEmpty
            ? "none"
            : manifestPhaseCounts
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
        let manifestMediaCountText = Self.summaryCountText(manifestMediaCounts)
        let selectedMediaCountText = Self.summaryCountText(selectedMediaCounts)
        let manifestMachineProfileCountText = Self.summaryCountText(manifestMachineProfileCounts)
        let selectedMachineProfileCountText = Self.summaryCountText(selectedMachineProfileCounts)
        let manifestDriveModeCountText = Self.summaryCountText(manifestDriveModeCounts)
        let selectedDriveModeCountText = Self.summaryCountText(selectedDriveModeCounts)
        let manifestSIDModelCountText = Self.summaryCountText(manifestSIDModelCounts)
        let selectedSIDModelCountText = Self.summaryCountText(selectedSIDModelCounts)
        let manifestSIDAccuracyModeCountText = Self.summaryCountText(manifestSIDAccuracyModeCounts)
        let selectedSIDAccuracyModeCountText = Self.summaryCountText(selectedSIDAccuracyModeCounts)
        let manifestObservableTypeCountText = Self.summaryCountText(manifestObservableTypeCounts)
        let selectedObservableTypeCountText = Self.summaryCountText(selectedObservableTypeCounts)
        let manifestVICProofCountText = Self.summaryCountText(manifestVICProofCounts)
        let selectedVICProofCountText = Self.summaryCountText(selectedVICProofCounts)
        let manifestExpectedFailureCategoryCountText = Self.summaryCountText(manifestExpectedFailureCategoryCounts)
        let selectedExpectedFailureCategoryCountText = Self.summaryCountText(selectedExpectedFailureCategoryCounts)
        let manifestActionTypeCountText = Self.summaryCountText(manifestActionTypeCounts)
        let selectedActionTypeCountText = Self.summaryCountText(selectedActionTypeCounts)
        let requiredMediaText = requiredManifestMediaTypes.isEmpty ? "none" : requiredManifestMediaTypes.joined(separator: " ")
        let invalidRequiredMediaText = invalidRequiredManifestMediaTypes.isEmpty ? "none" : invalidRequiredManifestMediaTypes.joined(separator: " ")
        let missingRequiredMediaText = missingRequiredManifestMediaTypes.isEmpty ? "none" : missingRequiredManifestMediaTypes.joined(separator: " ")
        let requiredProfileText = requiredManifestMachineProfiles.isEmpty ? "none" : requiredManifestMachineProfiles.joined(separator: " ")
        let invalidRequiredProfileText = invalidRequiredManifestMachineProfiles.isEmpty ? "none" : invalidRequiredManifestMachineProfiles.joined(separator: " ")
        let missingRequiredProfileText = missingRequiredManifestMachineProfiles.isEmpty ? "none" : missingRequiredManifestMachineProfiles.joined(separator: " ")
        let requiredDriveText = requiredManifestDriveModes.isEmpty ? "none" : requiredManifestDriveModes.joined(separator: " ")
        let invalidRequiredDriveText = invalidRequiredManifestDriveModes.isEmpty ? "none" : invalidRequiredManifestDriveModes.joined(separator: " ")
        let missingRequiredDriveText = missingRequiredManifestDriveModes.isEmpty ? "none" : missingRequiredManifestDriveModes.joined(separator: " ")
        let requiredSIDModelText = requiredManifestSIDModels.isEmpty ? "none" : requiredManifestSIDModels.joined(separator: " ")
        let invalidRequiredSIDModelText = invalidRequiredManifestSIDModels.isEmpty ? "none" : invalidRequiredManifestSIDModels.joined(separator: " ")
        let missingRequiredSIDModelText = missingRequiredManifestSIDModels.isEmpty ? "none" : missingRequiredManifestSIDModels.joined(separator: " ")
        let requiredSIDAccuracyText = requiredManifestSIDAccuracyModes.isEmpty ? "none" : requiredManifestSIDAccuracyModes.joined(separator: " ")
        let invalidRequiredSIDAccuracyText = invalidRequiredManifestSIDAccuracyModes.isEmpty ? "none" : invalidRequiredManifestSIDAccuracyModes.joined(separator: " ")
        let missingRequiredSIDAccuracyText = missingRequiredManifestSIDAccuracyModes.isEmpty ? "none" : missingRequiredManifestSIDAccuracyModes.joined(separator: " ")
        let requiredObservableText = requiredManifestObservableTypes.isEmpty ? "none" : requiredManifestObservableTypes.joined(separator: " ")
        let invalidRequiredObservableText = invalidRequiredManifestObservableTypes.isEmpty ? "none" : invalidRequiredManifestObservableTypes.joined(separator: " ")
        let missingRequiredObservableText = missingRequiredManifestObservableTypes.isEmpty ? "none" : missingRequiredManifestObservableTypes.joined(separator: " ")
        let requiredVICProofText = requiredManifestVICProofs.isEmpty ? "none" : requiredManifestVICProofs.joined(separator: " ")
        let invalidRequiredVICProofText = invalidRequiredManifestVICProofs.isEmpty ? "none" : invalidRequiredManifestVICProofs.joined(separator: " ")
        let missingRequiredVICProofText = missingRequiredManifestVICProofs.isEmpty ? "none" : missingRequiredManifestVICProofs.joined(separator: " ")
        let requiredFailureCategoryText = requiredManifestFailureCategories.isEmpty ? "none" : requiredManifestFailureCategories.joined(separator: " ")
        let invalidRequiredFailureCategoryText = invalidRequiredManifestFailureCategories.isEmpty ? "none" : invalidRequiredManifestFailureCategories.joined(separator: " ")
        let missingRequiredFailureCategoryText = missingRequiredManifestFailureCategories.isEmpty ? "none" : missingRequiredManifestFailureCategories.joined(separator: " ")
        let requiredActionTypeText = requiredManifestActionTypes.isEmpty ? "none" : requiredManifestActionTypes.joined(separator: " ")
        let invalidRequiredActionTypeText = invalidRequiredManifestActionTypes.isEmpty ? "none" : invalidRequiredManifestActionTypes.joined(separator: " ")
        let missingRequiredActionTypeText = missingRequiredManifestActionTypes.isEmpty ? "none" : missingRequiredManifestActionTypes.joined(separator: " ")
        let selectedPhaseText = selectedPhaseNames.isEmpty ? "none" : selectedPhaseNames.joined(separator: " ")
        let invalidSelectedPhaseText = invalidSelectedPhaseNames.isEmpty ? "none" : invalidSelectedPhaseNames.joined(separator: " ")
        let framebufferScreenshotCollisionText = manifestFramebufferScreenshotFilenameCollisions.isEmpty
            ? "none"
            : manifestFramebufferScreenshotFilenameCollisions.joined(separator: " ")
        let selectedPhaseCountText = selectedPhaseCounts.isEmpty
            ? "none"
            : selectedPhaseCounts
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
        let missingSelectedPhaseText = missingSelectedPhaseNames.isEmpty ? "none" : missingSelectedPhaseNames.joined(separator: " ")
        let selectedIDText = selectedMilestoneIDs.isEmpty ? "none" : selectedMilestoneIDs.joined(separator: " ")
        let missingSelectedIDText = missingSelectedMilestoneIDs.isEmpty ? "none" : missingSelectedMilestoneIDs.joined(separator: " ")
        return "Summary total=\(total) selected=\(selectedText) phaseFiltered=\(phaseFilteredText) preShard=\(preShardText) postShard=\(postShardText) shardIndex=\(shardIndexText) shardCount=\(shardCountText) invalidShard=[\(invalidShardText)] manifestValidation=[\(manifestValidationText)] manifestPhaseCounts=[\(manifestPhaseCountText)] manifestMediaCounts=[\(manifestMediaCountText)] selectedMediaCounts=[\(selectedMediaCountText)] manifestMachineProfiles=[\(manifestMachineProfileCountText)] selectedMachineProfiles=[\(selectedMachineProfileCountText)] manifestDriveModes=[\(manifestDriveModeCountText)] selectedDriveModes=[\(selectedDriveModeCountText)] manifestSIDModels=[\(manifestSIDModelCountText)] selectedSIDModels=[\(selectedSIDModelCountText)] manifestSIDAccuracyModes=[\(manifestSIDAccuracyModeCountText)] selectedSIDAccuracyModes=[\(selectedSIDAccuracyModeCountText)] manifestObservableTypes=[\(manifestObservableTypeCountText)] selectedObservableTypes=[\(selectedObservableTypeCountText)] manifestVICProofs=[\(manifestVICProofCountText)] selectedVICProofs=[\(selectedVICProofCountText)] manifestExpectedFailureCategories=[\(manifestExpectedFailureCategoryCountText)] selectedExpectedFailureCategories=[\(selectedExpectedFailureCategoryCountText)] manifestActionTypes=[\(manifestActionTypeCountText)] selectedActionTypes=[\(selectedActionTypeCountText)] requiredMedia=[\(requiredMediaText)] invalidRequiredMedia=[\(invalidRequiredMediaText)] missingRequiredMedia=[\(missingRequiredMediaText)] requiredProfiles=[\(requiredProfileText)] invalidRequiredProfiles=[\(invalidRequiredProfileText)] missingRequiredProfiles=[\(missingRequiredProfileText)] requiredDriveModes=[\(requiredDriveText)] invalidRequiredDriveModes=[\(invalidRequiredDriveText)] missingRequiredDriveModes=[\(missingRequiredDriveText)] requiredSIDModels=[\(requiredSIDModelText)] invalidRequiredSIDModels=[\(invalidRequiredSIDModelText)] missingRequiredSIDModels=[\(missingRequiredSIDModelText)] requiredSIDAccuracyModes=[\(requiredSIDAccuracyText)] invalidRequiredSIDAccuracyModes=[\(invalidRequiredSIDAccuracyText)] missingRequiredSIDAccuracyModes=[\(missingRequiredSIDAccuracyText)] requiredObservableTypes=[\(requiredObservableText)] invalidRequiredObservableTypes=[\(invalidRequiredObservableText)] missingRequiredObservableTypes=[\(missingRequiredObservableText)] requiredVICProofs=[\(requiredVICProofText)] invalidRequiredVICProofs=[\(invalidRequiredVICProofText)] missingRequiredVICProofs=[\(missingRequiredVICProofText)] requiredFailureCategories=[\(requiredFailureCategoryText)] invalidRequiredFailureCategories=[\(invalidRequiredFailureCategoryText)] missingRequiredFailureCategories=[\(missingRequiredFailureCategoryText)] requiredActionTypes=[\(requiredActionTypeText)] invalidRequiredActionTypes=[\(invalidRequiredActionTypeText)] missingRequiredActionTypes=[\(missingRequiredActionTypeText)] manifestUntagged=\(manifestUntaggedMilestoneCount) manifestUnnamed=\(manifestUnnamedMilestoneCount) manifestExpectedFailures=\(manifestExpectedFailureCount) expectedFailuresWithoutNotes=\(manifestExpectedFailuresWithoutNotesCount) expectedFailuresWithoutReasons=\(manifestExpectedFailuresWithoutReasonMarkersCount) screenshots=\(screenshotsWrittenCount) passedScreenshots=\(passedScreenshotCount) failedScreenshots=\(failedScreenshotCount) milestonesWithoutMaxCycles=\(manifestMilestonesWithoutMaxCyclesCount) milestonesWithoutExplicitActions=\(manifestMilestonesWithoutExplicitActionsCount) milestonesWithoutObservables=\(manifestMilestonesWithoutObservableExpectationsCount) phase3MilestonesWithoutVICProof=\(manifestPhase3MilestonesWithoutVICProofCount) phase3MilestonesMissingRequiredVICProofs=\(manifestPhase3MilestonesMissingRequiredVICProofsCount) framebufferProofsWithoutScreenshots=\(manifestFramebufferHashMilestonesWithoutScreenshotNamesCount) framebufferScreenshotCollisions=\(manifestFramebufferScreenshotFilenameCollisionCount) framebufferScreenshotCollisionFiles=[\(framebufferScreenshotCollisionText)] placeholderProofHashes=\(manifestPlaceholderProofHashCount) requireManifest=\(requireManifest) requireTaggedPhases=\(requireTaggedManifestPhases) requireIDs=\(requireManifestMilestoneIDs) requireExpectedFailureNotes=\(requireExpectedFailureNotes) requireExpectedFailureReasons=\(requireExpectedFailureReasonMarkers) requireMaxCycles=\(requireExplicitMaxCycles) requireActions=\(requireExplicitActions) requireObservables=\(requireObservableExpectations) requirePhase3VICProofs=\(requirePhase3VICProofs) requireFramebufferScreenshots=\(requireFramebufferScreenshots) rejectPlaceholderProofHashes=\(rejectPlaceholderProofHashes) selectedPhases=[\(selectedPhaseText)] selectedPhaseCounts=[\(selectedPhaseCountText)] invalidSelectedPhases=[\(invalidSelectedPhaseText)] missingSelectedPhases=[\(missingSelectedPhaseText)] selectedIDs=[\(selectedIDText)] missingSelectedIDs=[\(missingSelectedIDText)] executed=\(executed) passed=\(passed) failed=\(failed) expectedFailures=\(expectedFailures) unexpectedFailures=\(unexpectedFailures) expectedFailureDrift=\(expectedFailureDriftCount) skipped=\(skipped) missingMedia=\(missingMediaFiles.count) unclassified=\(unclassifiedFailureCount) outcome=\(outcomeText) cycles=\(totalElapsedCycles) maxCycles=\(maxElapsedCycles) categories=[\(categoryText)] phases=[\(phaseText)] phaseAcceptanceFailures=[\(phaseAcceptanceText)]"
    }

    private static func summaryCountText(_ counts: [String: Int]) -> String {
        if counts.isEmpty {
            return "none"
        }
        return counts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
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
            Self.failureSummaryLine(detail)
        }
        return "Unclassified milestone failures (\(unclassifiedFailureCount)):\n" + details.joined(separator: "\n")
    }

    var unexpectedFailureSummary: String {
        guard hasUnexpectedFailures else {
            return "No unexpected milestone failures."
        }
        let details = unexpectedFailureDetails.map { detail in
            Self.failureSummaryLine(detail)
        }
        return "Unexpected milestone failures (\(unexpectedFailures)):\n" + details.joined(separator: "\n")
    }

    var expectedFailureDriftSummary: String {
        guard expectedFailureDriftCount > 0 else {
            return "No expected-failure drift."
        }
        let details = expectedFailureDriftDetails.map { detail in
            let idText = detail.key.id.map { "\($0) " } ?? ""
            return "\(idText)\(detail.key.file) \(detail.key.machineProfile)/\(detail.key.driveMode) command=\(detail.key.commandSummary) category=\(detail.category) cycles=\(detail.elapsedCycles) \(detail.finalDiagnostics) reason=\(detail.reason) mismatches=\(detail.mismatches.joined(separator: "; "))"
        }
        return "Expected-failure drift (\(expectedFailureDriftCount)):\n" + details.joined(separator: "\n")
    }

    private static func failureSummaryLine(_ detail: MilestoneFailureSummary) -> String {
        let idText = detail.key.id.map { "\($0) " } ?? ""
        return "\(idText)\(detail.key.file) \(detail.key.machineProfile)/\(detail.key.driveMode) command=\(detail.key.commandSummary) category=\(detail.category) cycles=\(detail.elapsedCycles) \(detail.finalDiagnostics) reason=\(detail.reason)"
    }

    var phaseAcceptanceFailureSummary: String {
        if phaseAcceptanceFailures.isEmpty
            && invalidFailPhaseNames.isEmpty
            && invalidSelectedPhaseNames.isEmpty
            && missingSelectedPhaseNames.isEmpty
            && invalidRequiredManifestMediaTypes.isEmpty
            && missingRequiredManifestMediaTypes.isEmpty
            && invalidRequiredManifestMachineProfiles.isEmpty
            && missingRequiredManifestMachineProfiles.isEmpty
            && invalidRequiredManifestDriveModes.isEmpty
            && missingRequiredManifestDriveModes.isEmpty
            && invalidRequiredManifestSIDModels.isEmpty
            && missingRequiredManifestSIDModels.isEmpty
            && invalidRequiredManifestSIDAccuracyModes.isEmpty
            && missingRequiredManifestSIDAccuracyModes.isEmpty
            && invalidRequiredManifestObservableTypes.isEmpty
            && missingRequiredManifestObservableTypes.isEmpty
            && invalidRequiredManifestVICProofs.isEmpty
            && missingRequiredManifestVICProofs.isEmpty
            && invalidRequiredManifestFailureCategories.isEmpty
            && missingRequiredManifestFailureCategories.isEmpty
            && invalidRequiredManifestActionTypes.isEmpty
            && missingRequiredManifestActionTypes.isEmpty
            && missingSelectedMilestoneIDs.isEmpty
            && manifestPhase3MilestonesWithoutVICProofCount == 0
            && manifestPhase3MilestonesMissingRequiredVICProofsCount == 0
            && manifestFramebufferScreenshotFilenameCollisionCount == 0
            && manifestPlaceholderProofHashCount == 0 {
            return "No phase acceptance failures."
        }
        var parts = phaseAcceptanceFailures
        parts.append(contentsOf: invalidFailPhaseNames.map { "invalid:\($0)" })
        parts.append(contentsOf: invalidSelectedPhaseNames.map { "invalidSelected:\($0)" })
        parts.append(contentsOf: missingSelectedPhaseNames.map { "missingSelected:\($0)" })
        parts.append(contentsOf: invalidRequiredManifestMediaTypes.map { "invalidRequiredMedia:\($0)" })
        parts.append(contentsOf: missingRequiredManifestMediaTypes.map { "missingRequiredMedia:\($0)" })
        parts.append(contentsOf: invalidRequiredManifestMachineProfiles.map { "invalidRequiredProfile:\($0)" })
        parts.append(contentsOf: missingRequiredManifestMachineProfiles.map { "missingRequiredProfile:\($0)" })
        parts.append(contentsOf: invalidRequiredManifestDriveModes.map { "invalidRequiredDrive:\($0)" })
        parts.append(contentsOf: missingRequiredManifestDriveModes.map { "missingRequiredDrive:\($0)" })
        parts.append(contentsOf: invalidRequiredManifestSIDModels.map { "invalidRequiredSIDModel:\($0)" })
        parts.append(contentsOf: missingRequiredManifestSIDModels.map { "missingRequiredSIDModel:\($0)" })
        parts.append(contentsOf: invalidRequiredManifestSIDAccuracyModes.map { "invalidRequiredSIDAccuracy:\($0)" })
        parts.append(contentsOf: missingRequiredManifestSIDAccuracyModes.map { "missingRequiredSIDAccuracy:\($0)" })
        parts.append(contentsOf: invalidRequiredManifestObservableTypes.map { "invalidRequiredObservable:\($0)" })
        parts.append(contentsOf: missingRequiredManifestObservableTypes.map { "missingRequiredObservable:\($0)" })
        parts.append(contentsOf: invalidRequiredManifestVICProofs.map { "invalidRequiredVICProof:\($0)" })
        parts.append(contentsOf: missingRequiredManifestVICProofs.map { "missingRequiredVICProof:\($0)" })
        parts.append(contentsOf: invalidRequiredManifestFailureCategories.map { "invalidRequiredFailureCategory:\($0)" })
        parts.append(contentsOf: missingRequiredManifestFailureCategories.map { "missingRequiredFailureCategory:\($0)" })
        parts.append(contentsOf: invalidRequiredManifestActionTypes.map { "invalidRequiredAction:\($0)" })
        parts.append(contentsOf: missingRequiredManifestActionTypes.map { "missingRequiredAction:\($0)" })
        parts.append(contentsOf: missingSelectedMilestoneIDs.map { "missingSelectedID:\($0)" })
        if manifestPhase3MilestonesWithoutVICProofCount > 0 {
            parts.append("phase3MilestonesWithoutVICProof:\(manifestPhase3MilestonesWithoutVICProofCount)")
        }
        if manifestPhase3MilestonesMissingRequiredVICProofsCount > 0 {
            parts.append("phase3MilestonesMissingRequiredVICProofs:\(manifestPhase3MilestonesMissingRequiredVICProofsCount)")
        }
        if manifestFramebufferScreenshotFilenameCollisionCount > 0 {
            parts.append("framebufferScreenshotFilenameCollisions:\(manifestFramebufferScreenshotFilenameCollisionCount)")
            parts.append("framebufferScreenshotCollisionFiles:\(manifestFramebufferScreenshotFilenameCollisions.joined(separator: " "))")
        }
        if manifestPlaceholderProofHashCount > 0 {
            parts.append("placeholderProofHashes:\(manifestPlaceholderProofHashCount)")
        }
        return "Phase acceptance failures: " + parts.joined(separator: ", ")
    }
}

private struct SIDAudioSignatureRecord: Codable, Equatable {
    let sampleCount: Int
    let minimum: Float
    let maximum: Float
    let sum: Double
    let absoluteSum: Double
    let mean: Double
    let rootMeanSquare: Double
    let zeroCrossings: Int
    let zeroCrossingRate: Double
    let lowBandRootMeanSquare: Double
    let midBandRootMeanSquare: Double
    let highBandRootMeanSquare: Double
    let crestFactor: Double

    private enum CodingKeys: String, CodingKey {
        case sampleCount
        case minimum
        case maximum
        case sum
        case absoluteSum
        case mean
        case rootMeanSquare
        case zeroCrossings
        case zeroCrossingRate
        case lowBandRootMeanSquare
        case midBandRootMeanSquare
        case highBandRootMeanSquare
        case crestFactor
    }

    init(_ signature: SID.AudioSignature, audioSummary: SIDTraceAudioSummary = .empty) {
        sampleCount = signature.sampleCount
        minimum = signature.minimum
        maximum = signature.maximum
        sum = signature.sum
        absoluteSum = signature.absoluteSum
        mean = signature.mean
        rootMeanSquare = signature.rootMeanSquare
        zeroCrossings = signature.zeroCrossings
        zeroCrossingRate = audioSummary.zeroCrossingRate
        lowBandRootMeanSquare = audioSummary.lowBandRootMeanSquare
        midBandRootMeanSquare = audioSummary.midBandRootMeanSquare
        highBandRootMeanSquare = audioSummary.highBandRootMeanSquare
        crestFactor = audioSummary.crestFactor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        minimum = try container.decode(Float.self, forKey: .minimum)
        maximum = try container.decode(Float.self, forKey: .maximum)
        sum = try container.decode(Double.self, forKey: .sum)
        absoluteSum = try container.decode(Double.self, forKey: .absoluteSum)
        mean = try container.decodeIfPresent(Double.self, forKey: .mean) ??
            (sampleCount > 0 ? sum / Double(sampleCount) : 0)
        rootMeanSquare = try container.decodeIfPresent(Double.self, forKey: .rootMeanSquare) ?? 0
        zeroCrossings = try container.decode(Int.self, forKey: .zeroCrossings)
        zeroCrossingRate = try container.decodeIfPresent(Double.self, forKey: .zeroCrossingRate) ?? 0
        lowBandRootMeanSquare = try container.decodeIfPresent(Double.self, forKey: .lowBandRootMeanSquare) ?? 0
        midBandRootMeanSquare = try container.decodeIfPresent(Double.self, forKey: .midBandRootMeanSquare) ?? 0
        highBandRootMeanSquare = try container.decodeIfPresent(Double.self, forKey: .highBandRootMeanSquare) ?? 0
        crestFactor = try container.decodeIfPresent(Double.self, forKey: .crestFactor) ?? 0
    }
}

private struct SIDAudioStateRecord: Codable, Equatable {
    let accuracyMode: String
    let sampleCycleCounter: Double
    let cyclesPerSample: Double
    let audioAccumulator: Double
    let audioAccumulatorCount: Int
    let audioOutputState: Double
    let directOutput: Int32
    let filterInput: Int32
    let filterOutput: Int32
    let mixedOutput: Int32
    let externalAudioInput: Int32
    let externalAudioPathInput: Int32
    let filterCutoff: String
    let filterResonance: String
    let filterControl: String
    let volumeFilter: String
    let volume: String
    let normalizedFilterCutoffValue: String
    let normalizedFilterCutoff: Double
    let filterDamping: Double
    let voice1FilterEnabled: Bool
    let voice2FilterEnabled: Bool
    let voice3FilterEnabled: Bool
    let externalInputFiltered: Bool
    let filterLowPassEnabled: Bool
    let filterBandPassEnabled: Bool
    let filterHighPassEnabled: Bool
    let voice3Off: Bool
    let dataBusLatch: String
    let dataBusLatchCyclesRemaining: Int
    let oscillator3Readback: String
    let oscillator3ReadbackValid: Bool
    let envelope3Readback: String
    let envelope3ReadbackValid: Bool
    let paddleX: String
    let paddleY: String
    let paddleTargetX: String
    let paddleTargetY: String
    let paddleScanActive: Bool
    let paddleScanCounter: Int?
    let filterLow: Double
    let filterBand: Double
    let filterHigh: Double
    let sampleWritePosition: Int

    init(_ state: SID.AudioDebugState) {
        accuracyMode = state.accuracyMode.rawValue
        sampleCycleCounter = state.sampleCycleCounter
        cyclesPerSample = state.cyclesPerSample
        audioAccumulator = state.audioAccumulator
        audioAccumulatorCount = state.audioAccumulatorCount
        audioOutputState = state.audioOutputState
        directOutput = state.directOutput
        filterInput = state.filterInput
        filterOutput = state.filterOutput
        mixedOutput = state.mixedOutput
        externalAudioInput = state.externalAudioInput
        externalAudioPathInput = state.externalAudioPathInput
        filterCutoff = String(format: "%04X", state.filterCutoff)
        filterResonance = String(format: "%01X", state.filterResonance)
        filterControl = String(format: "%01X", state.filterControl)
        volumeFilter = String(format: "%02X", state.volumeFilter)
        volume = String(format: "%01X", state.volume)
        normalizedFilterCutoffValue = String(format: "%03X", state.normalizedFilterCutoffValue)
        normalizedFilterCutoff = state.normalizedFilterCutoff
        filterDamping = state.filterDamping
        voice1FilterEnabled = state.voice1FilterEnabled
        voice2FilterEnabled = state.voice2FilterEnabled
        voice3FilterEnabled = state.voice3FilterEnabled
        externalInputFiltered = state.externalInputFiltered
        filterLowPassEnabled = state.filterLowPassEnabled
        filterBandPassEnabled = state.filterBandPassEnabled
        filterHighPassEnabled = state.filterHighPassEnabled
        voice3Off = state.voice3Off
        dataBusLatch = String(format: "%02X", state.dataBusLatch)
        dataBusLatchCyclesRemaining = state.dataBusLatchCyclesRemaining
        oscillator3Readback = String(format: "%02X", state.oscillator3Readback)
        oscillator3ReadbackValid = state.oscillator3ReadbackValid
        envelope3Readback = String(format: "%02X", state.envelope3Readback)
        envelope3ReadbackValid = state.envelope3ReadbackValid
        paddleX = String(format: "%02X", state.paddleX)
        paddleY = String(format: "%02X", state.paddleY)
        paddleTargetX = String(format: "%02X", state.paddleTargetX)
        paddleTargetY = String(format: "%02X", state.paddleTargetY)
        paddleScanActive = state.paddleScanActive
        paddleScanCounter = state.paddleScanCounter
        filterLow = state.filterLow
        filterBand = state.filterBand
        filterHigh = state.filterHigh
        sampleWritePosition = state.sampleWritePosition
    }
}

private struct SIDVoiceStateRecord: Codable, Equatable {
    let frequency: String
    let pulseWidth: String
    let control: String
    let attackDecay: String
    let sustainRelease: String
    let accumulator: String
    let shiftRegister: String
    let envelopeLevel: String
    let envelopeOutput: String
    let sustainLevel: String
    let envelopeState: String
    let exponentialCounter: UInt16
    let exponentialPeriod: UInt16
    let holdZero: Bool
    let gate: Bool
    let controlGate: Bool
    let sync: Bool
    let ringMod: Bool
    let testBit: Bool
    let waveTriangle: Bool
    let waveSawtooth: Bool
    let wavePulse: Bool
    let waveNoise: Bool
    let hasWaveform: Bool
    let oscillatorMSBRose: Bool
    let noiseClockRose: Bool
    let rateCounter: UInt16
    let selectedRatePeriod: UInt16
    let oscillatorOutput: String
    let waveformOutput: Int16
    let waveformDACOutput: String
    let waveformDACHoldCyclesRemaining: Int

    init(_ state: SID.VoiceDebugState) {
        frequency = String(format: "%04X", state.frequency)
        pulseWidth = String(format: "%03X", state.pulseWidth)
        control = String(format: "%02X", state.control)
        attackDecay = String(format: "%02X", state.attackDecay)
        sustainRelease = String(format: "%02X", state.sustainRelease)
        accumulator = String(format: "%06X", state.accumulator)
        shiftRegister = String(format: "%06X", state.shiftRegister)
        envelopeLevel = String(format: "%02X", state.envelopeLevel)
        envelopeOutput = String(format: "%02X", state.envelopeOutput)
        sustainLevel = String(format: "%02X", state.sustainLevel)
        envelopeState = state.envelopeState
        exponentialCounter = state.exponentialCounter
        exponentialPeriod = state.exponentialPeriod
        holdZero = state.holdZero
        gate = state.gate
        controlGate = state.controlGate
        sync = state.sync
        ringMod = state.ringMod
        testBit = state.testBit
        waveTriangle = state.waveTriangle
        waveSawtooth = state.waveSawtooth
        wavePulse = state.wavePulse
        waveNoise = state.waveNoise
        hasWaveform = state.hasWaveform
        oscillatorMSBRose = state.oscillatorMSBRose
        noiseClockRose = state.noiseClockRose
        rateCounter = state.rateCounter
        selectedRatePeriod = state.selectedRatePeriod
        oscillatorOutput = String(format: "%03X", state.oscillatorOutput)
        waveformOutput = state.waveformOutput
        waveformDACOutput = String(format: "%03X", state.waveformDACOutput)
        waveformDACHoldCyclesRemaining = state.waveformDACHoldCyclesRemaining
    }
}

private extension CompatibilityVICBusOwner {
    init(_ busOwner: VIC.BusOwner) {
        switch busOwner {
        case .cpu:
            self = .cpu
        case .vicBadLine:
            self = .vicBadLine
        case .vicSpriteDMA:
            self = .vicSpriteDMA
        }
    }
}

private extension CompatibilityVICBusPhaseExpectation {
    init(_ busPhase: VIC.BusPhase) {
        switch busPhase {
        case .cpu:
            self.init(type: .cpu)
        case .badLineBAWarning:
            self.init(type: .badLineBAWarning)
        case let .badLineCharacterFetch(column):
            self.init(type: .badLineCharacterFetch, column: column)
        case let .spriteBAWarning(sprite):
            self.init(type: .spriteBAWarning, sprite: sprite)
        case let .spriteDMA(sprite):
            self.init(type: .spriteDMA, sprite: sprite)
        }
    }

    var summary: String {
        switch type {
        case .badLineCharacterFetch:
            return "\(type.rawValue)(column:\(column.map(String.init) ?? "nil"))"
        case .spriteBAWarning, .spriteDMA:
            return "\(type.rawValue)(sprite:\(sprite.map(String.init) ?? "nil"))"
        case .cpu, .badLineBAWarning:
            return type.rawValue
        }
    }
}

private extension CompatibilityVICLowPhaseAccessExpectation {
    init(_ access: VIC.LowPhaseAccess) {
        switch access {
        case .idle:
            self.init(type: .idle)
        case let .refresh(index):
            self.init(type: .refresh, index: index)
        case let .displayData(column):
            self.init(type: .displayData, column: column)
        case let .spritePointer(sprite):
            self.init(type: .spritePointer, sprite: sprite)
        case let .spriteMiddleByte(sprite):
            self.init(type: .spriteMiddleByte, sprite: sprite)
        }
    }

    var summary: String {
        switch type {
        case .refresh:
            return "\(type.rawValue)(index:\(index.map(String.init) ?? "nil"))"
        case .displayData:
            return "\(type.rawValue)(column:\(column.map(String.init) ?? "nil"))"
        case .spritePointer, .spriteMiddleByte:
            return "\(type.rawValue)(sprite:\(sprite.map(String.init) ?? "nil"))"
        case .idle:
            return type.rawValue
        }
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }

    mutating func appendLittleEndian(_ value: Int16) {
        appendLittleEndian(UInt16(bitPattern: value))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }
}

private struct MilestoneResultKey: Codable, Hashable {
    let id: String?
    let file: String
    let commandSummary: String
    let machineProfile: String
    let driveMode: String
}
