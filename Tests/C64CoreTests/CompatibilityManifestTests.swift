import XCTest
@testable import C64Core

final class CompatibilityManifestTests: XCTestCase {
    func testManifestDecodesPreservationMilestoneFields() throws {
        let json = """
        {
          "milestones": [
            {
              "id": "giana-title-compat1541",
              "name": "Great Giana Sisters title screen",
              "file": "demo.g64",
              "mediaType": "g64",
              "machineProfile": "ntscC64",
              "driveMode": "standard1541",
              "commands": ["LOAD\\"*\\",8,1", "RUN"],
              "actions": [
                { "type": "text", "text": "LOAD\\"*\\",8,1" },
                { "type": "wait", "cycles": 1200000 },
                { "type": "joystickDown", "control": "fire" },
                { "type": "waitCycles", "cycles": 100000 },
                { "type": "joystickUp", "button": "fire" },
                { "type": "keyDown", "key": "RUN/STOP" },
                { "type": "keyUp", "key": "RUN/STOP" },
                { "type": "stopTape" },
                { "type": "wait", "cycles": 64 },
                { "type": "startTape" }
              ],
              "maxCycles": 24000000,
              "pcStart": 49152,
              "pcEnd": 53247,
              "pcRanges": [
                { "start": 2048, "end": 4095 },
                { "start": 53248, "end": 57343 }
              ],
              "minGCRReads": 64,
              "minByteReady": 512,
              "driveStatus": {
                "minGCRReads": 128,
                "minByteReady": 1024,
                "minSyncDetections": 4,
                "minWeakBitReads": 16,
                "minVariableSpeedZoneSamples": 32,
                "minGCRWrites": 7,
                "minGCRWriteSplices": 2,
                "minGCRWriteEraseBits": 9,
                "requiredVariableSpeedZones": [0, 3],
                "track": 18,
                "halfTrack": 34,
                "headBitPosition": 12345,
                "readTrack": 18,
                "readHalfTrack": 34,
                "usingHalfTrackFallback": false,
                "motorOn": true,
                "ledOn": true,
                "gcrWriteModeActive": true,
                "writeProtected": false,
                "hasDisk": true,
                "mediaChanged": true,
                "minMediaChangeCount": 1,
                "hasNativeLowLevelImage": true,
                "d64ExportBlockedByLowLevelWrites": true,
                "lastIECCommandContains": "28"
              },
              "mediaStatus": {
                "populatedHalfTrackCount": 84,
                "nativeLowLevelTrackCount": 84,
                "syntheticGCRTrackCount": 0,
                "hasSyntheticGCR": false,
                "isNativeLowLevel": true,
                "preservesHalfTracks": true,
                "preservesRawTrackLengths": true,
                "preservesSpeedZones": true,
                "preservesVariableSpeedZones": true,
                "preservesSectorErrorInfo": true,
                "preservesWeakBitRanges": false,
                "sectorErrorCodeCount": 683,
                "nonDefaultSectorErrorCodeCount": 2,
                "weakBitRangeCount": 3,
                "weakBitTotalBitCount": 512,
                "hasDuplicateSectorHeaders": true,
                "duplicateSectorHeaderCount": 4,
                "variableSpeedZoneByteCount": 7928,
                "supportsWraparoundReads": true,
                "maxTrackSize": 7928,
                "unsupportedFeaturesContains": ["Weak/random bits", "Flux-level timing"]
              },
              "weakBitRanges": [
                { "halfTrack": 34, "startBit": 128, "endBit": 255 },
                { "halfTrack": 35, "startBit": 64, "endBit": 95 }
              ],
              "speedZoneRanges": [
                { "halfTrack": 34, "startByte": 0, "endByte": 127, "zone": 0 },
                { "halfTrack": 34, "startByte": 128, "endByte": 255, "zone": 3 }
              ],
              "tapeStatus": {
                "mountedTapeNameContains": "demo.tap",
                "decodeStatus": "decodedPrograms",
                "pulseCount": 512,
                "programCount": 2,
                "blockCount": 4,
                "decodeFailureReason": "incompleteHeaderData",
                "rawPlaybackActive": true,
                "readSignalHigh": false,
                "cassetteSenseLineHigh": false,
                "cassetteMotorEnabled": true,
                "hasCapturedWritePulses": false,
                "canExportCapturedTAP": false,
                "hasUnsavedChanges": true,
                "canExportSavedT64": true
              },
              "ramSignatures": [
                { "address": 2049, "bytes": "01 08 a9 00" },
                { "address": 49152, "bytes": [169, 66, 96] }
              ],
              "colorRAMSignatures": [
                { "address": 0, "bytes": "01 02 03" },
                { "address": 999, "bytes": [14, 15] }
              ],
              "cpuRegisters": {
                "pc": "$c000",
                "a": "$01",
                "x": 2,
                "y": "$03",
                "sp": "$fa",
                "status": "$24",
                "statusMask": "$ef"
              },
              "sidModel": "mos8580",
              "sidAccuracyMode": "compatibility",
              "sidRegisters": [
                { "register": "$D418", "value": "$0f" },
                { "register": 54276, "value": 33, "mask": "$f1" }
              ],
              "sidAudioSignature": {
                "sampleCount": 128,
                "minimum": -0.125,
                "maximum": 0.5,
                "sum": 1.25,
                "absoluteSum": 3.5,
                "mean": 0.009765625,
                "rootMeanSquare": 0.25,
                "zeroCrossings": 4,
                "tolerance": 0.0001
              },
              "sidAudioState": {
                "accuracyMode": "compatibility",
                "audioAccumulator": 12.5,
                "audioAccumulatorCount": 2,
                "audioOutputState": 34.5,
                "filterLow": 1.25,
                "filterBand": -2.5,
                "filterHigh": 3.75,
                "sampleWritePosition": 4,
                "tolerance": 0.001
              },
              "sidVoiceStates": [
                {
                  "voice": 0,
                  "frequency": "$1234",
                  "pulseWidth": "$0abc",
                  "control": "$21",
                  "attackDecay": "$ad",
                  "sustainRelease": "$f6",
                  "accumulator": "$abcdef",
                  "shiftRegister": "$123456",
                  "envelopeLevel": "$7f",
                  "envelopeState": "decay",
                  "exponentialCounter": 12,
                  "exponentialPeriod": 30,
                  "holdZero": true,
                  "gate": true,
                  "rateCounter": 456,
                  "waveformDACOutput": "$0fed",
                  "waveformDACHoldCyclesRemaining": 64
                }
              ],
              "vicRegisters": [
                { "register": "$D020", "value": "$06", "mask": "$0f" },
                { "register": "$D011", "value": "$3b" }
              ],
              "cia1Registers": [
                { "register": "$DC0E", "value": "$41", "mask": "$41" }
              ],
              "cia2Registers": [
                { "register": "$DD02", "value": "$3f" }
              ],
              "screenTextContains": ["READY.", "PRESS FIRE"],
              "screenRAMHash": "0123456789abcdef",
              "colorRAMHash": "fedcba9876543210",
              "screenshotName": "demo-title",
              "expectedFailure": {
                "category": "drive",
                "reasonContains": ["GCR reads", "byte-ready"],
                "note": "Known protected-loader regression"
              }
            }
          ]
        }
        """

        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8))
        let milestone = try XCTUnwrap(manifest.milestones.first)

        XCTAssertEqual(milestone.id, "giana-title-compat1541")
        XCTAssertEqual(milestone.name, "Great Giana Sisters title screen")
        XCTAssertEqual(milestone.file, "demo.g64")
        XCTAssertEqual(milestone.mediaType, .g64)
        XCTAssertEqual(milestone.machineProfile, .ntscC64)
        XCTAssertEqual(milestone.machineProfile?.profile, .ntscC64)
        XCTAssertEqual(milestone.driveMode, .standard1541)
        XCTAssertEqual(milestone.driveMode?.trueDriveMode, .standard1541)
        XCTAssertEqual(milestone.commands, ["LOAD\"*\",8,1", "RUN"])
        XCTAssertEqual(milestone.actions, [
            .typeText("LOAD\"*\",8,1"),
            .waitCycles(1_200_000),
            .joystickDown(.fire),
            .waitCycles(100_000),
            .joystickUp(.fire),
            .keyDown(.runStop),
            .keyUp(.runStop),
            .stopTape,
            .waitCycles(64),
            .startTape
        ])
        XCTAssertEqual(milestone.command, "LOAD\"*\",8,1")
        XCTAssertEqual(milestone.pcRange, 0xC000...0xCFFF)
        XCTAssertEqual(milestone.pcRanges.map(\.range), [0x0800...0x0FFF, 0xD000...0xDFFF])
        XCTAssertEqual(milestone.expectedPCRanges, [0x0800...0x0FFF, 0xD000...0xDFFF, 0xC000...0xCFFF])
        XCTAssertEqual(milestone.driveStatus?.minGCRReads, 128)
        XCTAssertEqual(milestone.driveStatus?.minByteReady, 1024)
        XCTAssertEqual(milestone.driveStatus?.minSyncDetections, 4)
        XCTAssertEqual(milestone.driveStatus?.minWeakBitReads, 16)
        XCTAssertEqual(milestone.driveStatus?.minVariableSpeedZoneSamples, 32)
        XCTAssertEqual(milestone.driveStatus?.minGCRWrites, 7)
        XCTAssertEqual(milestone.driveStatus?.minGCRWriteSplices, 2)
        XCTAssertEqual(milestone.driveStatus?.minGCRWriteEraseBits, 9)
        XCTAssertEqual(milestone.driveStatus?.requiredVariableSpeedZones, [0, 3])
        XCTAssertEqual(milestone.driveStatus?.track, 18)
        XCTAssertEqual(milestone.driveStatus?.halfTrack, 34)
        XCTAssertEqual(milestone.driveStatus?.headBitPosition, 12345)
        XCTAssertEqual(milestone.driveStatus?.readTrack, 18)
        XCTAssertEqual(milestone.driveStatus?.readHalfTrack, 34)
        XCTAssertEqual(milestone.driveStatus?.usingHalfTrackFallback, false)
        XCTAssertEqual(milestone.driveStatus?.motorOn, true)
        XCTAssertEqual(milestone.driveStatus?.ledOn, true)
        XCTAssertEqual(milestone.driveStatus?.gcrWriteModeActive, true)
        XCTAssertEqual(milestone.driveStatus?.writeProtected, false)
        XCTAssertEqual(milestone.driveStatus?.hasDisk, true)
        XCTAssertEqual(milestone.driveStatus?.mediaChanged, true)
        XCTAssertEqual(milestone.driveStatus?.minMediaChangeCount, 1)
        XCTAssertEqual(milestone.driveStatus?.hasNativeLowLevelImage, true)
        XCTAssertEqual(milestone.driveStatus?.d64ExportBlockedByLowLevelWrites, true)
        XCTAssertEqual(milestone.driveStatus?.lastIECCommandContains, "28")
        XCTAssertEqual(milestone.mediaStatus?.populatedHalfTrackCount, 84)
        XCTAssertEqual(milestone.mediaStatus?.nativeLowLevelTrackCount, 84)
        XCTAssertEqual(milestone.mediaStatus?.syntheticGCRTrackCount, 0)
        XCTAssertEqual(milestone.mediaStatus?.hasSyntheticGCR, false)
        XCTAssertEqual(milestone.mediaStatus?.isNativeLowLevel, true)
        XCTAssertEqual(milestone.mediaStatus?.preservesHalfTracks, true)
        XCTAssertEqual(milestone.mediaStatus?.preservesRawTrackLengths, true)
        XCTAssertEqual(milestone.mediaStatus?.preservesSpeedZones, true)
        XCTAssertEqual(milestone.mediaStatus?.preservesVariableSpeedZones, true)
        XCTAssertEqual(milestone.mediaStatus?.preservesSectorErrorInfo, true)
        XCTAssertEqual(milestone.mediaStatus?.preservesWeakBitRanges, false)
        XCTAssertEqual(milestone.mediaStatus?.sectorErrorCodeCount, 683)
        XCTAssertEqual(milestone.mediaStatus?.nonDefaultSectorErrorCodeCount, 2)
        XCTAssertEqual(milestone.mediaStatus?.weakBitRangeCount, 3)
        XCTAssertEqual(milestone.mediaStatus?.weakBitTotalBitCount, 512)
        XCTAssertEqual(milestone.mediaStatus?.hasDuplicateSectorHeaders, true)
        XCTAssertEqual(milestone.mediaStatus?.duplicateSectorHeaderCount, 4)
        XCTAssertEqual(milestone.mediaStatus?.variableSpeedZoneByteCount, 7928)
        XCTAssertEqual(milestone.mediaStatus?.supportsWraparoundReads, true)
        XCTAssertEqual(milestone.mediaStatus?.maxTrackSize, 7928)
        XCTAssertEqual(milestone.mediaStatus?.unsupportedFeaturesContains, ["Weak/random bits", "Flux-level timing"])
        XCTAssertEqual(milestone.weakBitRanges, [
            CompatibilityWeakBitRange(halfTrack: 34, startBit: 128, endBit: 255),
            CompatibilityWeakBitRange(halfTrack: 35, startBit: 64, endBit: 95)
        ])
        XCTAssertEqual(milestone.speedZoneRanges, [
            CompatibilitySpeedZoneRange(halfTrack: 34, startByte: 0, endByte: 127, zone: 0),
            CompatibilitySpeedZoneRange(halfTrack: 34, startByte: 128, endByte: 255, zone: 3)
        ])
        XCTAssertEqual(milestone.tapeStatus, CompatibilityTapeStatus(
            mountedTapeNameContains: "demo.tap",
            decodeStatus: .decodedPrograms,
            pulseCount: 512,
            programCount: 2,
            blockCount: 4,
            decodeFailureReason: .incompleteHeaderData,
            rawPlaybackActive: true,
            readSignalHigh: false,
            cassetteSenseLineHigh: false,
            cassetteMotorEnabled: true,
            hasCapturedWritePulses: false,
            canExportCapturedTAP: false,
            hasUnsavedChanges: true,
            canExportSavedT64: true
        ))
        XCTAssertEqual(milestone.ramSignatures[0].bytes, [0x01, 0x08, 0xA9, 0x00])
        XCTAssertEqual(milestone.ramSignatures[1].bytes, [0xA9, 0x42, 0x60])
        XCTAssertEqual(milestone.colorRAMSignatures[0].address, 0)
        XCTAssertEqual(milestone.colorRAMSignatures[0].bytes, [0x01, 0x02, 0x03])
        XCTAssertEqual(milestone.colorRAMSignatures[1].address, 999)
        XCTAssertEqual(milestone.colorRAMSignatures[1].bytes, [0x0E, 0x0F])
        XCTAssertEqual(milestone.cpuRegisters, CompatibilityCPURegisters(
            pc: 0xC000,
            a: 0x01,
            x: 0x02,
            y: 0x03,
            sp: 0xFA,
            p: 0x24,
            pMask: 0xEF
        ))
        XCTAssertEqual(milestone.sidModel, .mos8580)
        XCTAssertEqual(milestone.sidAccuracyMode, .compatibility)
        XCTAssertEqual(milestone.sidRegisters, [
            CompatibilitySIDRegisterExpectation(register: 0xD418, value: 0x0F),
            CompatibilitySIDRegisterExpectation(register: 0xD404, value: 0x21, mask: 0xF1)
        ])
        XCTAssertEqual(milestone.sidAudioSignature, CompatibilitySIDAudioSignature(
            sampleCount: 128,
            minimum: -0.125,
            maximum: 0.5,
            sum: 1.25,
            absoluteSum: 3.5,
            mean: 0.009765625,
            rootMeanSquare: 0.25,
            zeroCrossings: 4,
            tolerance: 0.0001
        ))
        XCTAssertEqual(milestone.sidAudioState, CompatibilitySIDAudioState(
            accuracyMode: .compatibility,
            audioAccumulator: 12.5,
            audioAccumulatorCount: 2,
            audioOutputState: 34.5,
            filterLow: 1.25,
            filterBand: -2.5,
            filterHigh: 3.75,
            sampleWritePosition: 4,
            tolerance: 0.001
        ))
        XCTAssertEqual(milestone.sidVoiceStates, [
            CompatibilitySIDVoiceState(
                voice: 0,
                frequency: 0x1234,
                pulseWidth: 0x0ABC,
                control: 0x21,
                attackDecay: 0xAD,
                sustainRelease: 0xF6,
                accumulator: 0xABCDEF,
                shiftRegister: 0x123456,
                envelopeLevel: 0x7F,
                envelopeState: "decay",
                exponentialCounter: 12,
                exponentialPeriod: 30,
                holdZero: true,
                gate: true,
                rateCounter: 456,
                waveformDACOutput: 0x0FED,
                waveformDACHoldCyclesRemaining: 64
            )
        ])
        XCTAssertEqual(milestone.vicRegisters, [
            CompatibilityVICRegisterExpectation(register: 0xD020, value: 0x06, mask: 0x0F),
            CompatibilityVICRegisterExpectation(register: 0xD011, value: 0x3B)
        ])
        XCTAssertEqual(milestone.cia1Registers, [
            CompatibilityCIARegisterExpectation(register: 0xDC0E, value: 0x41, mask: 0x41)
        ])
        XCTAssertEqual(milestone.cia2Registers, [
            CompatibilityCIARegisterExpectation(register: 0xDD02, value: 0x3F)
        ])
        XCTAssertEqual(milestone.screenTextContains, ["READY.", "PRESS FIRE"])
        XCTAssertEqual(milestone.screenRAMHash, "0123456789abcdef")
        XCTAssertEqual(milestone.colorRAMHash, "fedcba9876543210")
        XCTAssertEqual(milestone.screenshotName, "demo-title")
        XCTAssertEqual(milestone.expectedFailure, CompatibilityExpectedFailure(
            category: .drive,
            reasonContains: ["GCR reads", "byte-ready"],
            note: "Known protected-loader regression"
        ))
    }

    func testManifestKeepsLegacyMilestoneFieldsOptional() throws {
        let json = """
        {
          "milestones": [
            {
              "file": "legacy.d64",
              "command": "LOAD\\"$\\",8"
            }
          ]
        }
        """

        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8))
        let milestone = try XCTUnwrap(manifest.milestones.first)

        XCTAssertEqual(milestone.file, "legacy.d64")
        XCTAssertNil(milestone.id)
        XCTAssertNil(milestone.name)
        XCTAssertNil(milestone.mediaType)
        XCTAssertNil(milestone.machineProfile)
        XCTAssertNil(milestone.driveMode)
        XCTAssertEqual(milestone.commands, ["LOAD\"$\",8"])
        XCTAssertEqual(milestone.weakBitRanges, [])
        XCTAssertEqual(milestone.speedZoneRanges, [])
        XCTAssertEqual(milestone.actions, [.typeText("LOAD\"$\",8")])
        XCTAssertEqual(milestone.command, "LOAD\"$\",8")
        XCTAssertNil(milestone.pcRange)
        XCTAssertNil(milestone.driveStatus)
        XCTAssertNil(milestone.mediaStatus)
        XCTAssertEqual(milestone.ramSignatures, [])
        XCTAssertEqual(milestone.colorRAMSignatures, [])
        XCTAssertNil(milestone.cpuRegisters)
        XCTAssertNil(milestone.sidModel)
        XCTAssertEqual(milestone.sidRegisters, [])
        XCTAssertEqual(milestone.sidVoiceStates, [])
        XCTAssertEqual(milestone.vicRegisters, [])
        XCTAssertEqual(milestone.cia1Registers, [])
        XCTAssertEqual(milestone.cia2Registers, [])
        XCTAssertEqual(milestone.screenTextContains, [])
        XCTAssertNil(milestone.screenRAMHash)
        XCTAssertNil(milestone.colorRAMHash)
        XCTAssertNil(milestone.expectedFailure)
        XCTAssertEqual(milestone.pcRanges, [])
        XCTAssertEqual(milestone.expectedPCRanges, [])
    }

    func testManifestDecodesDriveModes() throws {
        let json = """
        {
          "milestones": [
            {
              "file": "fast.d64",
              "mediaType": "d64",
              "driveMode": "fastLoad",
              "command": "LOAD\\"*\\",8,1"
            },
            {
              "file": "hybrid.g64",
              "mediaType": "g64",
              "driveMode": "compat1541",
              "command": "LOAD\\"*\\",8,1"
            },
            {
              "file": "strict.g64",
              "mediaType": "g64",
              "driveMode": "standard1541",
              "command": "LOAD\\"*\\",8,1"
            }
          ]
        }
        """

        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.milestones[0].driveMode?.trueDriveMode, .off)
        XCTAssertEqual(manifest.milestones[1].driveMode?.trueDriveMode, .compat1541)
        XCTAssertEqual(manifest.milestones[2].driveMode?.trueDriveMode, .standard1541)
    }

    func testManifestDecodesAllMilestoneMediaTypes() throws {
        let json = """
        {
          "milestones": [
            { "file": "program.prg", "mediaType": "prg", "command": "RUN" },
            { "file": "disk.d64", "mediaType": "d64", "command": "LOAD\\"*\\",8,1" },
            { "file": "raw.g64", "mediaType": "g64", "command": "LOAD\\"*\\",8,1" },
            { "file": "raw.nib", "mediaType": "nib", "command": "LOAD\\"*\\",8,1" },
            { "file": "packed.nbz", "mediaType": "nbz", "command": "LOAD\\"*\\",8,1" },
            { "file": "flux.p64", "mediaType": "p64", "command": "LOAD\\"*\\",8,1" },
            { "file": "tape.t64", "mediaType": "t64", "command": "LOAD" },
            { "file": "signal.tap", "mediaType": "tap", "command": "LOAD" },
            { "file": "cart.crt", "mediaType": "crt", "command": "SYS 32768" }
          ]
        }
        """

        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.milestones.compactMap(\.mediaType), [.prg, .d64, .g64, .nib, .nbz, .p64, .t64, .tap, .crt])
    }

    func testManifestDecodesC64CProfiles() throws {
        let json = """
        {
          "milestones": [
            {
              "file": "pal-c64c.prg",
              "mediaType": "prg",
              "machineProfile": "palC64C",
              "command": "RUN"
            },
            {
              "file": "ntsc-c64c.prg",
              "mediaType": "prg",
              "machineProfile": "ntscC64C",
              "command": "RUN"
            }
          ]
        }
        """

        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.milestones[0].machineProfile, .palC64C)
        XCTAssertEqual(manifest.milestones[0].machineProfile?.profile.sidModel, .mos8580)
        XCTAssertEqual(manifest.milestones[0].machineProfile?.profile.videoStandard, .pal)
        XCTAssertEqual(manifest.milestones[1].machineProfile, .ntscC64C)
        XCTAssertEqual(manifest.milestones[1].machineProfile?.profile.sidModel, .mos8580)
        XCTAssertEqual(manifest.milestones[1].machineProfile?.profile.videoStandard, .ntsc)
    }

    func testManifestDecodes1541IIProfiles() throws {
        let json = """
        {
          "milestones": [
            {
              "file": "pal-1541ii.d64",
              "mediaType": "d64",
              "machineProfile": "palC64With1541II",
              "command": "LOAD\\"*\\",8,1"
            },
            {
              "file": "ntsc-c64c-1541ii.d64",
              "mediaType": "d64",
              "machineProfile": "ntscC64CWith1541II",
              "command": "LOAD\\"*\\",8,1"
            }
          ]
        }
        """

        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.milestones[0].machineProfile, .palC64With1541II)
        XCTAssertEqual(manifest.milestones[0].machineProfile?.profile.sidModel, .mos6581)
        XCTAssertEqual(manifest.milestones[0].machineProfile?.profile.driveModel, .model1541II)
        XCTAssertEqual(manifest.milestones[1].machineProfile, .ntscC64CWith1541II)
        XCTAssertEqual(manifest.milestones[1].machineProfile?.profile.sidModel, .mos8580)
        XCTAssertEqual(manifest.milestones[1].machineProfile?.profile.driveModel, .model1541II)
    }

    func testManifestRejectsEmptyCommandSequence() {
        let json = """
        {
          "milestones": [
            {
              "file": "empty.d64",
              "commands": []
            }
          ]
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8)))
    }

    func testManifestDecodesActionsOnlyMilestone() throws {
        let json = """
        {
          "milestones": [
            {
              "file": "title.prg",
              "actions": [
                { "action": "typeText", "command": "RUN" },
                { "action": "waitCycles", "cycles": 10 },
                { "action": "pressJoystick", "button": "fire" },
                { "action": "releaseJoystick", "control": "fire" },
                { "action": "pressKey", "key": "space" },
                { "action": "releaseKey", "key": "restore" }
              ]
            }
          ]
        }
        """

        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8))
        let milestone = try XCTUnwrap(manifest.milestones.first)

        XCTAssertEqual(milestone.commands, ["RUN"])
        XCTAssertEqual(milestone.actions, [
            .typeText("RUN"),
            .waitCycles(10),
            .joystickDown(.fire),
            .joystickUp(.fire),
            .keyDown(.space),
            .keyUp(.restore)
        ])
    }

    func testManifestDecodesSingleScreenTextExpectation() throws {
        let json = """
        {
          "milestones": [
            {
              "file": "title.prg",
              "command": "RUN",
              "screenTextContains": "READY."
            }
          ]
        }
        """

        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.milestones.first?.screenTextContains, ["READY."])
    }

    func testManifestRejectsInvalidPCRanges() {
        let json = """
        {
          "milestones": [
            {
              "file": "bad-range.d64",
              "command": "LOAD\\"*\\",8,1",
              "pcRanges": [
                { "start": 65536, "end": 65537 }
              ]
            }
          ]
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8)))
    }

    func testManifestRejectsInvalidDriveSpeedZoneExpectations() {
        let json = """
        {
          "milestones": [
            {
              "file": "bad-drive-zone.g64",
              "command": "LOAD\\"*\\",8,1",
              "driveStatus": {
                "requiredVariableSpeedZones": [0, 4]
              }
            }
          ]
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8)))
    }

    func testManifestRejectsNegativeDriveCounters() {
        let json = """
        {
          "milestones": [
            {
              "file": "bad-drive-counter.g64",
              "command": "LOAD\\"*\\",8,1",
              "driveStatus": {
                "minVariableSpeedZoneSamples": -1
              }
            }
          ]
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8)))
    }

    func testManifestRejectsNegativeMediaCounters() {
        let json = """
        {
          "milestones": [
            {
              "file": "bad-media-counter.g64",
              "command": "LOAD\\"*\\",8,1",
              "mediaStatus": {
                "weakBitTotalBitCount": -1
              }
            }
          ]
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8)))
    }

    func testManifestRejectsInvalidSIDAudioSignature() {
        let invalidSignatures = [
            #""sampleCount": -1"#,
            #""sampleCount": 1, "absoluteSum": -0.1"#,
            #""sampleCount": 1, "rootMeanSquare": -0.1"#,
            #""sampleCount": 1, "zeroCrossings": -1"#,
            #""sampleCount": 1, "minimum": 0.5, "maximum": -0.5"#,
            #""sampleCount": 1, "tolerance": -0.1"#
        ]

        for signature in invalidSignatures {
            let json = """
            {
              "milestones": [
                {
                  "file": "demo.prg",
                  "sidAudioSignature": { \(signature) }
                }
              ]
            }
            """

            XCTAssertThrowsError(
                try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8)),
                "Expected invalid SID audio signature to be rejected: \(signature)"
            )
        }
    }

    func testManifestRejectsInvalidSIDVoiceState() {
        let invalidVoiceStates = [
            #""voice": -1"#,
            #""voice": 3"#,
            #""voice": 0, "frequency": "$10000""#,
            #""voice": 0, "pulseWidth": "$1000""#,
            #""voice": 0, "control": "$100""#,
            #""voice": 0, "accumulator": "$1000000""#,
            #""voice": 0, "shiftRegister": "$800000""#,
            #""voice": 0, "waveformDACHoldCyclesRemaining": -1"#
        ]

        for voiceState in invalidVoiceStates {
            let json = """
            {
              "milestones": [
                {
                  "file": "demo.prg",
                  "sidVoiceStates": [{ \(voiceState) }]
                }
              ]
            }
            """

            XCTAssertThrowsError(
                try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8)),
                "Expected invalid SID voice state to be rejected: \(voiceState)"
            )
        }
    }

    func testManifestRejectsInvalidSpeedZoneRanges() {
        let invalidZoneJSON = """
        {
          "milestones": [
            {
              "file": "bad-speed-zone.g64",
              "command": "LOAD\\"*\\",8,1",
              "speedZoneRanges": [
                { "halfTrack": 34, "startByte": 0, "endByte": 127, "zone": 4 }
              ]
            }
          ]
        }
        """
        let reversedRangeJSON = """
        {
          "milestones": [
            {
              "file": "bad-speed-zone-range.g64",
              "command": "LOAD\\"*\\",8,1",
              "speedZoneRanges": [
                { "halfTrack": 34, "startByte": 128, "endByte": 127, "zone": 3 }
              ]
            }
          ]
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(CompatibilityManifest.self, from: Data(invalidZoneJSON.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(CompatibilityManifest.self, from: Data(reversedRangeJSON.utf8)))
    }

    func testInvalidLegacyPCRangeDoesNotProduceRange() throws {
        let json = """
        {
          "milestones": [
            {
              "file": "bad-legacy-range.d64",
              "command": "LOAD\\"*\\",8,1",
              "pcStart": 53248,
              "pcEnd": 49152
            }
          ]
        }
        """

        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8))
        let milestone = try XCTUnwrap(manifest.milestones.first)

        XCTAssertNil(milestone.pcRange)
        XCTAssertEqual(milestone.expectedPCRanges, [])
    }

    func testScreenRAMHashUsesStableFNV1A64OverTextScreenBytes() {
        var ram = [UInt8](repeating: 0, count: 0x10000)
        ram[0x0400] = 0x01
        ram[0x0401] = 0x02

        let first = CompatibilityHash.screenRAM(ram)
        ram[0x0800] = 0xFF
        let unchanged = CompatibilityHash.screenRAM(ram)
        ram[0x0401] = 0x03
        let changed = CompatibilityHash.screenRAM(ram)

        XCTAssertEqual(first, unchanged)
        XCTAssertNotEqual(first, changed)
    }

    func testColorRAMHashUsesStableFNV1A64OverColorNibbles() {
        var colorRAM = [UInt8](repeating: 0, count: 1024)
        colorRAM[0] = 0x81
        colorRAM[1] = 0x02

        let first = CompatibilityHash.colorRAM(colorRAM)
        colorRAM[1000] = 0x0F
        let unchanged = CompatibilityHash.colorRAM(colorRAM)
        colorRAM[0] = 0x03
        let changed = CompatibilityHash.colorRAM(colorRAM)

        XCTAssertEqual(first, unchanged)
        XCTAssertNotEqual(first, changed)
    }
}
