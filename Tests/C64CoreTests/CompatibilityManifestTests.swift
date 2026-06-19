import XCTest
@testable import C64Core

final class CompatibilityManifestTests: XCTestCase {
    func testManifestDecodesPreservationMilestoneFields() throws {
        let json = """
        {
          "milestones": [
            {
              "file": "demo.g64",
              "mediaType": "g64",
              "machineProfile": "ntscC64",
              "driveMode": "standard1541",
              "commands": ["LOAD\\"*\\",8,1", "RUN"],
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
                "track": 18,
                "halfTrack": 36,
                "motorOn": true,
                "ledOn": true,
                "writeProtected": false,
                "hasDisk": true,
                "hasNativeLowLevelImage": true,
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
                "supportsWraparoundReads": true,
                "maxTrackSize": 7928,
                "unsupportedFeaturesContains": ["Weak/random bits", "Write-back"]
              },
              "ramSignatures": [
                { "address": 2049, "bytes": "01 08 a9 00" },
                { "address": 49152, "bytes": [169, 66, 96] }
              ],
              "colorRAMSignatures": [
                { "address": 0, "bytes": "01 02 03" },
                { "address": 999, "bytes": [14, 15] }
              ],
              "screenRAMHash": "0123456789abcdef",
              "colorRAMHash": "fedcba9876543210",
              "screenshotName": "demo-title"
            }
          ]
        }
        """

        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8))
        let milestone = try XCTUnwrap(manifest.milestones.first)

        XCTAssertEqual(milestone.file, "demo.g64")
        XCTAssertEqual(milestone.mediaType, .g64)
        XCTAssertEqual(milestone.machineProfile, .ntscC64)
        XCTAssertEqual(milestone.machineProfile?.profile, .ntscC64)
        XCTAssertEqual(milestone.driveMode, .standard1541)
        XCTAssertEqual(milestone.driveMode?.trueDriveMode, .standard1541)
        XCTAssertEqual(milestone.commands, ["LOAD\"*\",8,1", "RUN"])
        XCTAssertEqual(milestone.command, "LOAD\"*\",8,1")
        XCTAssertEqual(milestone.pcRange, 0xC000...0xCFFF)
        XCTAssertEqual(milestone.pcRanges.map(\.range), [0x0800...0x0FFF, 0xD000...0xDFFF])
        XCTAssertEqual(milestone.expectedPCRanges, [0x0800...0x0FFF, 0xD000...0xDFFF, 0xC000...0xCFFF])
        XCTAssertEqual(milestone.driveStatus?.minGCRReads, 128)
        XCTAssertEqual(milestone.driveStatus?.minByteReady, 1024)
        XCTAssertEqual(milestone.driveStatus?.minSyncDetections, 4)
        XCTAssertEqual(milestone.driveStatus?.track, 18)
        XCTAssertEqual(milestone.driveStatus?.halfTrack, 36)
        XCTAssertEqual(milestone.driveStatus?.motorOn, true)
        XCTAssertEqual(milestone.driveStatus?.ledOn, true)
        XCTAssertEqual(milestone.driveStatus?.writeProtected, false)
        XCTAssertEqual(milestone.driveStatus?.hasDisk, true)
        XCTAssertEqual(milestone.driveStatus?.hasNativeLowLevelImage, true)
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
        XCTAssertEqual(milestone.mediaStatus?.supportsWraparoundReads, true)
        XCTAssertEqual(milestone.mediaStatus?.maxTrackSize, 7928)
        XCTAssertEqual(milestone.mediaStatus?.unsupportedFeaturesContains, ["Weak/random bits", "Write-back"])
        XCTAssertEqual(milestone.ramSignatures[0].bytes, [0x01, 0x08, 0xA9, 0x00])
        XCTAssertEqual(milestone.ramSignatures[1].bytes, [0xA9, 0x42, 0x60])
        XCTAssertEqual(milestone.colorRAMSignatures[0].address, 0)
        XCTAssertEqual(milestone.colorRAMSignatures[0].bytes, [0x01, 0x02, 0x03])
        XCTAssertEqual(milestone.colorRAMSignatures[1].address, 999)
        XCTAssertEqual(milestone.colorRAMSignatures[1].bytes, [0x0E, 0x0F])
        XCTAssertEqual(milestone.screenRAMHash, "0123456789abcdef")
        XCTAssertEqual(milestone.colorRAMHash, "fedcba9876543210")
        XCTAssertEqual(milestone.screenshotName, "demo-title")
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
        XCTAssertNil(milestone.mediaType)
        XCTAssertNil(milestone.machineProfile)
        XCTAssertNil(milestone.driveMode)
        XCTAssertEqual(milestone.commands, ["LOAD\"$\",8"])
        XCTAssertEqual(milestone.command, "LOAD\"$\",8")
        XCTAssertNil(milestone.pcRange)
        XCTAssertNil(milestone.driveStatus)
        XCTAssertNil(milestone.mediaStatus)
        XCTAssertEqual(milestone.ramSignatures, [])
        XCTAssertEqual(milestone.colorRAMSignatures, [])
        XCTAssertNil(milestone.screenRAMHash)
        XCTAssertNil(milestone.colorRAMHash)
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
            { "file": "tape.t64", "mediaType": "t64", "command": "LOAD" },
            { "file": "signal.tap", "mediaType": "tap", "command": "LOAD" },
            { "file": "cart.crt", "mediaType": "crt", "command": "SYS 32768" }
          ]
        }
        """

        let manifest = try JSONDecoder().decode(CompatibilityManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.milestones.compactMap(\.mediaType), [.prg, .d64, .g64, .t64, .tap, .crt])
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
