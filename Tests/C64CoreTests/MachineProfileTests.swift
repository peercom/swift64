import XCTest
@testable import C64Core

final class MachineProfileTests: XCTestCase {
    func testDefaultProfileIsPALC64With6581And1541CCompatDrive() {
        let c64 = C64()

        XCTAssertEqual(c64.machineProfile, .palC64)
        XCTAssertEqual(c64.vic.videoStandard, .pal)
        XCTAssertEqual(c64.sid.model, .mos6581)
        XCTAssertEqual(c64.sid.clockRate, 985_248)
        XCTAssertEqual(c64.cia1.cyclesPerTodTenth, 98_525)
        XCTAssertEqual(c64.cia2.cyclesPerTodTenth, 98_525)

        c64.trueDriveEmulationMode = .compat1541

        XCTAssertEqual(c64.drive1541.driveModel, .model1541C)
        XCTAssertEqual(c64.driveClockRatio, 1.0)
    }

    func testNTSCProfileAppliesChipClockAndTODSettings() {
        let c64 = C64(machineProfile: .ntscC64)

        XCTAssertEqual(c64.machineProfile, .ntscC64)
        XCTAssertEqual(c64.vic.videoStandard, .ntsc)
        XCTAssertEqual(c64.sid.clockRate, 1_022_727)
        XCTAssertEqual(c64.cia1.cyclesPerTodTenth, 102_273)
        XCTAssertEqual(c64.cia2.cyclesPerTodTenth, 102_273)
    }

    func testStandardTrueDriveUsesProfileClockRatio() {
        let c64 = C64(machineProfile: .ntscC64)

        c64.trueDriveEmulationMode = .standard1541

        XCTAssertEqual(c64.drive1541.driveModel, .model1541)
        XCTAssertEqual(c64.driveClockRatio, 1_000_000.0 / 1_022_727.0, accuracy: 0.000001)
    }
}
