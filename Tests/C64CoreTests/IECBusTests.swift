import XCTest
@testable import C64Core

final class IECBusTests: XCTestCase {
    func testReleasedBusLinesReadHighOnC64AndLowOnDriveInputs() {
        let bus = IECBus()

        XCTAssertTrue(bus.atnLine)
        XCTAssertTrue(bus.clockLine)
        XCTAssertTrue(bus.dataLine)
        XCTAssertEqual(bus.c64ReadClk, 0x40)
        XCTAssertEqual(bus.c64ReadData, 0x80)
        XCTAssertEqual(bus.drivePortBInput & 0x85, 0x00)
        XCTAssertFalse(bus.ca1State)
    }

    func testDriveAddressInputsDefaultToDevice8Jumpers() {
        let bus = IECBus()

        XCTAssertEqual(bus.drivePortBInput & 0x60, 0x00)
    }

    func testC64OnlyDrivesConfiguredOutputBitsLow() {
        let bus = IECBus()

        bus.updateFromC64(0x38, ddra: 0x38)

        XCTAssertFalse(bus.atnLine)
        XCTAssertFalse(bus.clockLine)
        XCTAssertFalse(bus.dataLine)
        XCTAssertEqual(bus.c64ReadClk, 0x00)
        XCTAssertEqual(bus.c64ReadData, 0x00)
        // The drive samples the C64's write from its next cycle on.
        XCTAssertEqual(bus.drivePortBInput & 0x85, 0x00)
        XCTAssertFalse(bus.ca1State)
        bus.settleC64OutputsAtDrive()
        XCTAssertEqual(bus.drivePortBInput & 0x85, 0x85)
        XCTAssertTrue(bus.ca1State)
    }

    func testC64LineChangesReachTheDriveOneCycleLate() {
        let bus = IECBus()
        bus.updateFromC64(0x08, ddra: 0x38)
        bus.settleC64OutputsAtDrive()
        XCTAssertTrue(bus.ca1State)
        XCTAssertEqual(bus.drivePortBInput & 0x80, 0x80)

        // Releasing ATN: the CIA output changes at the end of the C64 cycle,
        // so the drive still sees ATN asserted during the overlapping cycle.
        bus.updateFromC64(0x00, ddra: 0x38)
        XCTAssertTrue(bus.atnLine)
        XCTAssertTrue(bus.ca1State)
        XCTAssertEqual(bus.drivePortBInput & 0x80, 0x80)
        bus.settleC64OutputsAtDrive()
        XCTAssertFalse(bus.ca1State)
        XCTAssertEqual(bus.drivePortBInput & 0x80, 0x00)

        // The drive's own outputs stay immediate on both sides.
        bus.updateFromDrive(portB: 0x0A, ddrb: 0x0A)
        XCTAssertEqual(bus.drivePortBInput & 0x05, 0x05)
        XCTAssertFalse(bus.clockLine)
        XCTAssertFalse(bus.dataLine)
    }

    func testAtnAcknowledgeGateFollowsTheAtnLevelSeenAtTheDrive() {
        let bus = IECBus()
        bus.updateFromDrive(portB: 0x10, ddrb: 0x10)
        XCTAssertFalse(bus.dataLine, "ATNA set while ATN is released pulls DATA low")

        bus.updateFromC64(0x08, ddra: 0x38)
        XCTAssertFalse(bus.dataLine, "the gate still sees ATN released until the drive side settles")
        bus.settleC64OutputsAtDrive()
        XCTAssertTrue(bus.dataLine, "ATN asserted with ATNA set releases DATA")
        XCTAssertEqual(bus.drivePortBInput & 0x01, 0x00)
    }

    func testInputConfiguredC64PinsDoNotDriveBus() {
        let bus = IECBus()

        bus.updateFromC64(0x38, ddra: 0x00)

        XCTAssertTrue(bus.atnLine)
        XCTAssertTrue(bus.clockLine)
        XCTAssertTrue(bus.dataLine)
    }

    func testDriveOutputsPullClockAndDataLow() {
        let bus = IECBus()

        bus.updateFromDrive(portB: 0x0A, ddrb: 0x0A)

        XCTAssertTrue(bus.atnLine)
        XCTAssertFalse(bus.clockLine)
        XCTAssertFalse(bus.dataLine)
        XCTAssertEqual(bus.drivePortBInput & 0x05, 0x05)
    }

    func testAtnAcknowledgeXorGatePullsDataWhenAtnMatchesDriveAtn() {
        let bus = IECBus()

        bus.updateFromDrive(portB: 0x10, ddrb: 0x10)

        XCTAssertTrue(bus.atnLine)
        XCTAssertFalse(bus.dataLine)
        XCTAssertEqual(bus.c64ReadData, 0x00)
    }
}
