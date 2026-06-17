import XCTest
@testable import C64Core

final class VIA6522Tests: XCTestCase {
    func testCA1PositiveEdgeSetsIFRAndIRQWhenEnabled() {
        let via = VIA6522()
        var irqStates: [Bool] = []
        via.onInterrupt = { irqStates.append($0) }

        via.writeRegister(0x0C, value: 0x01) // CA1 positive edge
        via.writeRegister(0x0E, value: 0x82) // enable CA1

        via.ca1 = false
        via.tick()
        via.ca1 = true
        via.tick()

        XCTAssertEqual(via.ifr & VIA6522.IRQ.ca1, VIA6522.IRQ.ca1)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.any, VIA6522.IRQ.any)
        XCTAssertEqual(irqStates.last, true)
    }

    func testPortAReadClearsCA1AndInvokesReadCallback() {
        let via = VIA6522()
        var readCount = 0
        via.onPortARead = { readCount += 1 }
        via.writeRegister(0x0C, value: 0x01)
        via.writeRegister(0x0E, value: 0x82)
        via.ca1 = true
        via.tick()

        _ = via.readRegister(0x01)

        XCTAssertEqual(readCount, 1)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.ca1, 0)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.any, 0)
    }

    func testTimer1UnderflowSetsIFRAndDelayedIRQ() {
        let via = VIA6522()
        var irqStates: [Bool] = []
        via.onInterrupt = { irqStates.append($0) }
        via.writeRegister(0x0E, value: 0xC0) // enable T1
        via.writeRegister(0x04, value: 0x01)
        via.writeRegister(0x05, value: 0x00)

        via.tick()
        XCTAssertEqual(via.ifr & VIA6522.IRQ.timer1, 0)

        via.tick()
        XCTAssertEqual(via.ifr & VIA6522.IRQ.timer1, VIA6522.IRQ.timer1)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.any, VIA6522.IRQ.any)

        via.tick()
        XCTAssertEqual(irqStates.last, true)
    }

    func testCA2HandshakeModeTransitionsOnPortARead() {
        let via = VIA6522()
        var states: [Bool] = []
        via.onCA2Change = { states.append($0) }

        via.writeRegister(0x0C, value: 0x0E) // CA2 manual high
        via.writeRegister(0x0C, value: 0x08) // CA2 handshake mode, initially low
        _ = via.readRegister(0x01)

        XCTAssertTrue(states.contains(false))
        XCTAssertFalse(via.ca2OutputState)
    }
}
