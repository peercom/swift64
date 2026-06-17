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

    func testCA2InputPositiveEdgeSetsIFRAndIRQWhenEnabled() {
        let via = VIA6522()
        var irqStates: [Bool] = []
        via.onInterrupt = { irqStates.append($0) }

        via.writeRegister(0x0C, value: 0x04) // CA2 positive-edge input
        via.writeRegister(0x0E, value: 0x81) // enable CA2

        via.ca2 = false
        via.tick()
        via.ca2 = true
        via.tick()

        XCTAssertEqual(via.ifr & VIA6522.IRQ.ca2, VIA6522.IRQ.ca2)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.any, VIA6522.IRQ.any)
        XCTAssertEqual(irqStates.last, true)
    }

    func testCB2InputNegativeEdgeSetsIFRAndClearsOnPortBRead() {
        let via = VIA6522()
        via.writeRegister(0x0C, value: 0x00) // CB2 negative-edge input
        via.writeRegister(0x0E, value: 0x88) // enable CB2

        via.cb2 = true
        via.tick()
        via.cb2 = false
        via.tick()

        XCTAssertEqual(via.ifr & VIA6522.IRQ.cb2, VIA6522.IRQ.cb2)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.any, VIA6522.IRQ.any)

        _ = via.readRegister(0x00)

        XCTAssertEqual(via.ifr & VIA6522.IRQ.cb2, 0)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.any, 0)
    }

    func testCA2AndCB2OutputModesDoNotLatchInputEdges() {
        let via = VIA6522()
        via.writeRegister(0x0C, value: 0xCE) // CA2 manual high, CB2 manual low
        via.writeRegister(0x0E, value: 0x89) // enable CA2 and CB2

        via.ca2 = false
        via.cb2 = true
        via.tick()
        via.ca2 = true
        via.cb2 = false
        via.tick()

        XCTAssertEqual(via.ifr & (VIA6522.IRQ.ca2 | VIA6522.IRQ.cb2), 0)
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

    func testTimer2CountsPB6FallingEdgesWhenPulseModeIsSelected() {
        let via = VIA6522()
        var irqStates: [Bool] = []
        via.onInterrupt = { irqStates.append($0) }
        via.writeRegister(0x0E, value: 0xA0) // enable T2
        via.writeRegister(0x0B, value: 0x20) // T2 counts PB6 pulses
        via.writeRegister(0x08, value: 0x01)
        via.writeRegister(0x09, value: 0x00)

        via.tick()
        XCTAssertEqual(via.timer2Counter, 0x0001)

        via.setPB6Line(high: false)
        XCTAssertEqual(via.timer2Counter, 0x0000)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.timer2, 0)

        via.setPB6Line(high: true)
        via.setPB6Line(high: false)

        XCTAssertEqual(via.timer2Counter, 0xFFFF)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.timer2, VIA6522.IRQ.timer2)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.any, VIA6522.IRQ.any)
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
