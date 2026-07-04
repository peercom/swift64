import XCTest
@testable import C64Core

final class MachineProfileTests: XCTestCase {
    func testDefaultProfileIsPALC64With6581And1541CCompatDrive() {
        let c64 = C64()

        XCTAssertEqual(c64.machineProfile, .palC64)
        XCTAssertEqual(c64.vic.videoStandard, .pal)
        XCTAssertEqual(c64.vic.rasterCyclesPerLine, 63)
        XCTAssertEqual(c64.vic.rasterLinesPerFrame, 312)
        XCTAssertEqual(c64.vic.activeCyclesPerFrame, 19_656)
        XCTAssertEqual(c64.machineProfile.displayFrameRateHz, 985_248.0 / 19_656.0, accuracy: 0.000001)
        XCTAssertEqual(c64.machineProfile.displayFramesPerSecond, 50)
        XCTAssertEqual(c64.sid.model, .mos6581)
        XCTAssertEqual(c64.sid.clockRate, 985_248)
        XCTAssertEqual(c64.cia1.cyclesPerTodTenth, 98_525)
        XCTAssertEqual(c64.cia2.cyclesPerTodTenth, 98_525)
        XCTAssertEqual(c64.cia1.tod50HzCyclesPerTenth, 98_525)
        XCTAssertEqual(c64.cia1.tod60HzCyclesPerTenth, 118_230)

        c64.trueDriveEmulationMode = .compat1541

        XCTAssertEqual(c64.drive1541.driveModel, .model1541C)
        XCTAssertEqual(c64.driveClockRatio, 1.0)
    }

    func testNTSCProfileAppliesChipClockAndTODSettings() {
        let c64 = C64(machineProfile: .ntscC64)

        XCTAssertEqual(c64.machineProfile, .ntscC64)
        XCTAssertEqual(c64.vic.videoStandard, .ntsc)
        XCTAssertEqual(c64.vic.rasterCyclesPerLine, 65)
        XCTAssertEqual(c64.vic.rasterLinesPerFrame, 263)
        XCTAssertEqual(c64.vic.activeCyclesPerFrame, 17_095)
        XCTAssertEqual(c64.machineProfile.displayFrameRateHz, 1_022_727.0 / 17_095.0, accuracy: 0.000001)
        XCTAssertEqual(c64.machineProfile.displayFramesPerSecond, 60)
        XCTAssertEqual(c64.sid.clockRate, 1_022_727)
        XCTAssertEqual(c64.cia1.cyclesPerTodTenth, 102_273)
        XCTAssertEqual(c64.cia2.cyclesPerTodTenth, 102_273)
        XCTAssertEqual(c64.cia1.tod50HzCyclesPerTenth, 85_228)
        XCTAssertEqual(c64.cia1.tod60HzCyclesPerTenth, 102_273)
    }

    func testC64CProfilesSelect8580SIDWithMatchingVideoTiming() {
        let palC64C = C64(machineProfile: .palC64C)
        let ntscC64C = C64(machineProfile: .ntscC64C)

        XCTAssertEqual(palC64C.machineProfile.name, "PAL C64C + 1541C")
        XCTAssertEqual(palC64C.vic.videoStandard, .pal)
        XCTAssertEqual(palC64C.sid.model, .mos8580)
        XCTAssertEqual(palC64C.sid.clockRate, 985_248)
        XCTAssertEqual(palC64C.cia1.cyclesPerTodTenth, 98_525)
        XCTAssertEqual(palC64C.machineProfile.driveModel, .model1541C)
        palC64C.trueDriveEmulationMode = .compat1541
        XCTAssertEqual(palC64C.drive1541.driveModel, .model1541C)

        XCTAssertEqual(ntscC64C.machineProfile.name, "NTSC C64C + 1541C")
        XCTAssertEqual(ntscC64C.vic.videoStandard, .ntsc)
        XCTAssertEqual(ntscC64C.sid.model, .mos8580)
        XCTAssertEqual(ntscC64C.sid.clockRate, 1_022_727)
        XCTAssertEqual(ntscC64C.cia1.cyclesPerTodTenth, 102_273)
        XCTAssertEqual(ntscC64C.machineProfile.driveModel, .model1541C)
        ntscC64C.trueDriveEmulationMode = .compat1541
        XCTAssertEqual(ntscC64C.drive1541.driveModel, .model1541C)
    }

    func test1541IIProfilesSelectAlternateDriveModel() {
        let palC64With1541II = C64(machineProfile: .palC64With1541II)
        let ntscC64CWith1541II = C64(machineProfile: .ntscC64CWith1541II)

        XCTAssertEqual(palC64With1541II.machineProfile.name, "PAL C64 + 1541-II")
        XCTAssertEqual(palC64With1541II.sid.model, .mos6581)
        XCTAssertEqual(palC64With1541II.machineProfile.driveModel, .model1541II)
        palC64With1541II.trueDriveEmulationMode = .compat1541
        XCTAssertEqual(palC64With1541II.drive1541.driveModel, .model1541II)
        XCTAssertFalse(palC64With1541II.drive1541.is1541C)
        XCTAssertEqual(palC64With1541II.driveClockRatio, 1.0)

        XCTAssertEqual(ntscC64CWith1541II.machineProfile.name, "NTSC C64C + 1541-II")
        XCTAssertEqual(ntscC64CWith1541II.sid.model, .mos8580)
        XCTAssertEqual(ntscC64CWith1541II.machineProfile.driveModel, .model1541II)
        ntscC64CWith1541II.trueDriveEmulationMode = .compat1541
        XCTAssertEqual(ntscC64CWith1541II.drive1541.driveModel, .model1541II)
        XCTAssertFalse(ntscC64CWith1541II.drive1541.is1541C)
        XCTAssertEqual(ntscC64CWith1541II.driveClockRatio, 1.0)
    }

    func testSIDModelOverrideSurvivesProfileApplicationPowerOnAndReset() {
        let c64 = C64(machineProfile: .palC64)
        XCTAssertEqual(c64.sid.model, .mos6581)

        c64.sidModelOverride = .mos8580
        XCTAssertEqual(c64.sid.model, .mos8580)

        c64.machineProfile = .ntscC64
        XCTAssertEqual(c64.sid.model, .mos8580)
        XCTAssertEqual(c64.sid.clockRate, 1_022_727)

        c64.powerOn()
        XCTAssertEqual(c64.sid.model, .mos8580)

        c64.reset()
        XCTAssertEqual(c64.sid.model, .mos8580)

        c64.sidModelOverride = nil
        XCTAssertEqual(c64.sid.model, .mos6581)

        c64.machineProfile = .palC64C
        XCTAssertEqual(c64.sid.model, .mos8580)
    }

    func testStandardTrueDriveUsesProfileClockRatio() {
        let c64 = C64(machineProfile: .ntscC64)

        c64.trueDriveEmulationMode = .standard1541

        XCTAssertEqual(c64.drive1541.driveModel, .model1541)
        XCTAssertEqual(c64.driveClockRatio, 1_000_000.0 / 1_022_727.0, accuracy: 0.000001)
    }

    func testMachineProfileCarriesRAMPowerOnPattern() {
        XCTAssertEqual(MachineProfile.palC64.memoryPowerOnPattern, .alternating64ByteBlocks)
        XCTAssertEqual(MemoryPowerOnPattern.alternating64ByteBlocks.byte(at: 0x003F), 0x00)
        XCTAssertEqual(MemoryPowerOnPattern.alternating64ByteBlocks.byte(at: 0x0040), 0xFF)
        XCTAssertEqual(MemoryPowerOnPattern.allZero.byte(at: 0x0040), 0x00)
        XCTAssertEqual(MemoryPowerOnPattern.allOne.byte(at: 0x0040), 0xFF)
    }

    func testDriveROMLoadPreservesSelectedCompatDriveProfile() {
        let c64 = C64(machineProfile: .palC64With1541II)
        c64.trueDriveEmulationMode = .compat1541

        c64.loadDriveROM(makeDetectable1541CROM())

        XCTAssertEqual(c64.drive1541.driveModel, .model1541II)
        XCTAssertFalse(c64.drive1541.is1541C)
        XCTAssertEqual(c64.driveClockRatio, 1.0)
    }

    func testDriveROMLoadPreservesStandardTrueDriveModelAndClockRatio() {
        let c64 = C64(machineProfile: .ntscC64CWith1541II)
        c64.trueDriveEmulationMode = .standard1541

        c64.loadDriveROM(makeDetectable1541CROM())

        XCTAssertEqual(c64.drive1541.driveModel, .model1541)
        XCTAssertFalse(c64.drive1541.is1541C)
        XCTAssertEqual(c64.driveClockRatio, 1_000_000.0 / 1_022_727.0, accuracy: 0.000001)
    }

    private func makeDetectable1541CROM() -> Data {
        var rom = [UInt8](repeating: 0xEA, count: C64.drive1541ROMSize)
        rom[0] = 0xAD
        rom[1] = 0x00
        rom[2] = 0x18
        rom[3] = 0x29
        rom[4] = 0x01
        rom[0x3FFC] = 0x00
        rom[0x3FFD] = 0xC0
        return Data(rom)
    }
}
