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
        XCTAssertEqual(bus.drivePortBInput & 0x85, 0x85)
        XCTAssertTrue(bus.ca1State)
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
