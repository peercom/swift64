import XCTest
@testable import C64Core

final class CIATests: XCTestCase {
    func testEnablingPendingInterruptAssertsOnceAndMaskClearDeasserts() {
        let cia = CIA(isCIA1: true)
        var irqStates: [Bool] = []
        cia.onInterrupt = { irqStates.append($0) }
        cia.interruptData = 0x01

        cia.writeRegister(0x0D, value: 0x81)
        cia.writeRegister(0x0D, value: 0x81)

        XCTAssertTrue(cia.interruptActive)
        XCTAssertEqual(cia.interruptData, 0x81)
        XCTAssertEqual(irqStates, [true])

        cia.writeRegister(0x0D, value: 0x01)

        XCTAssertFalse(cia.interruptActive)
        XCTAssertEqual(cia.interruptData, 0x01)
        XCTAssertEqual(irqStates, [true, false])
    }

    func testReadingInterruptControlClearsActiveLineOnce() {
        let cia = CIA(isCIA1: true)
        var irqStates: [Bool] = []
        cia.onInterrupt = { irqStates.append($0) }
        cia.interruptData = 0x01
        cia.writeRegister(0x0D, value: 0x81)

        XCTAssertEqual(cia.readRegister(0x0D), 0x81)
        XCTAssertEqual(cia.readRegister(0x0D), 0x00)
        XCTAssertFalse(cia.interruptActive)
        XCTAssertEqual(irqStates, [true, false])
    }
}
