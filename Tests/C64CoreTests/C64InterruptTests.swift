import XCTest
@testable import C64Core

final class C64InterruptTests: XCTestCase {
    func testCIA1InterruptMaskClearDeassertsCPUIRQLine() {
        let c64 = C64()

        c64.cia1.interruptData = 0x01
        c64.cia1.writeRegister(0x0D, value: 0x81)

        XCTAssertTrue(c64.cpu.irqLine)

        c64.cia1.writeRegister(0x0D, value: 0x01)

        XCTAssertFalse(c64.cpu.irqLine)
    }

    func testVICInterruptAcknowledgeDeassertsCPUIRQLine() {
        let c64 = C64()

        c64.vic.writeRegister(0x12, value: 0x00)
        c64.vic.writeRegister(0x1A, value: 0x01)
        c64.vic.endOfLine()

        XCTAssertTrue(c64.cpu.irqLine)

        c64.vic.writeRegister(0x19, value: 0x01)

        XCTAssertFalse(c64.cpu.irqLine)
    }

    func testCPUIRQLineStaysAssertedUntilAllSourcesClear() {
        let c64 = C64()

        c64.cia1.interruptData = 0x01
        c64.cia1.writeRegister(0x0D, value: 0x81)
        c64.vic.writeRegister(0x12, value: 0x00)
        c64.vic.writeRegister(0x1A, value: 0x01)
        c64.vic.endOfLine()

        XCTAssertTrue(c64.cpu.irqLine)

        c64.cia1.writeRegister(0x0D, value: 0x01)

        XCTAssertTrue(c64.cpu.irqLine)

        c64.vic.writeRegister(0x19, value: 0x01)

        XCTAssertFalse(c64.cpu.irqLine)
    }
}
