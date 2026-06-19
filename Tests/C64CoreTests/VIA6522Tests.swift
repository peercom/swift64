import XCTest
@testable import C64Core

final class VIA6522Tests: XCTestCase {
    func testResetClearsRegistersTimersInterruptsAndLatches() {
        let via = VIA6522()
        var irqStates: [Bool] = []
        var ca2States: [Bool] = []
        var cb2States: [Bool] = []
        var cb1States: [Bool] = []
        via.onInterrupt = { irqStates.append($0) }
        via.onCA2Change = { ca2States.append($0) }
        via.onCB2Change = { cb2States.append($0) }
        via.onCB1Change = { cb1States.append($0) }

        via.portAInput = 0xA5
        via.portBInput = 0x5A
        via.writeRegister(0x00, value: 0x12)
        via.writeRegister(0x01, value: 0x34)
        via.writeRegister(0x02, value: 0xFF)
        via.writeRegister(0x03, value: 0x0F)
        via.writeRegister(0x0B, value: 0x63)
        via.writeRegister(0x0C, value: 0x0E)
        via.writeRegister(0x0E, value: 0xC2)
        via.ca1 = true
        via.tick()

        via.reset()

        XCTAssertEqual(via.portA, 0)
        XCTAssertEqual(via.portB, 0)
        XCTAssertEqual(via.ddra, 0)
        XCTAssertEqual(via.ddrb, 0)
        XCTAssertEqual(via.timer1Counter, 0xFFFF)
        XCTAssertEqual(via.timer1Latch, 0xFFFF)
        XCTAssertEqual(via.timer2Counter, 0xFFFF)
        XCTAssertEqual(via.acr, 0)
        XCTAssertEqual(via.pcr, 0)
        XCTAssertEqual(via.ifr, 0)
        XCTAssertEqual(via.ier, 0)
        XCTAssertTrue(via.ca2OutputState)
        XCTAssertTrue(via.cb2OutputState)
        XCTAssertTrue(via.cb1OutputState)
        XCTAssertEqual(irqStates.last, false)
        XCTAssertEqual(ca2States.last, true)
        XCTAssertEqual(cb2States.last, true)
        XCTAssertEqual(cb1States.last, true)
    }

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

    func testPortALatchCapturesInputOnCA1ActiveEdgeUntilHandshakeRead() {
        let via = VIA6522()
        via.writeRegister(0x0B, value: 0x01) // enable Port A input latch
        via.writeRegister(0x0C, value: 0x01) // CA1 positive edge
        via.portAInput = 0xA5

        via.ca1 = true
        via.tick()

        via.portAInput = 0x5A

        XCTAssertEqual(via.readRegister(0x0F), 0xA5)
        XCTAssertEqual(via.readRegister(0x01), 0xA5)
        XCTAssertEqual(via.readRegister(0x01), 0x5A)
    }

    func testPortALatchDisabledReadsLiveInput() {
        let via = VIA6522()
        via.writeRegister(0x0C, value: 0x01) // CA1 positive edge
        via.portAInput = 0xA5

        via.ca1 = true
        via.tick()

        via.portAInput = 0x5A

        XCTAssertEqual(via.readRegister(0x01), 0x5A)
    }

    func testPortAWriteInvokesOutputCallbackWhenOutputBitsChange() {
        let via = VIA6522()
        var observed: [UInt8] = []
        via.onPortAWrite = { observed.append(via.portAOut) }
        via.writeRegister(0x03, value: 0xFF)
        observed.removeAll()

        via.writeRegister(0x01, value: 0xA5)

        XCTAssertEqual(observed, [0xA5])
    }

    func testPortANoHandshakeWriteInvokesOutputCallbackWhenOutputBitsChange() {
        let via = VIA6522()
        var observed: [UInt8] = []
        via.onPortAWrite = { observed.append(via.portAOut) }
        via.writeRegister(0x03, value: 0xFF)
        observed.removeAll()

        via.writeRegister(0x0F, value: 0x5A)

        XCTAssertEqual(observed, [0x5A])
    }

    func testDDRAWriteInvokesPortAOutputCallbackWhenEffectiveOutputChanges() {
        let via = VIA6522()
        via.portAInput = 0x00
        var observed: [UInt8] = []
        via.onPortAWrite = { observed.append(via.portAOut) }
        via.writeRegister(0x01, value: 0xF0)
        observed.removeAll()

        via.writeRegister(0x03, value: 0xF0)

        XCTAssertEqual(observed, [0xF0])
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

    func testPortBLatchCapturesInputOnCB1ActiveEdgeUntilPortBRead() {
        let via = VIA6522()
        via.writeRegister(0x0B, value: 0x02) // enable Port B input latch
        via.writeRegister(0x0C, value: 0x10) // CB1 positive edge
        via.portBInput = 0x3C

        via.cb1 = true
        via.tick()

        via.portBInput = 0xC3

        XCTAssertEqual(via.readRegister(0x00), 0x3C)
        XCTAssertEqual(via.readRegister(0x00), 0xC3)
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

    func testCB2ManualOutputModesFollowPCR() {
        let via = VIA6522()
        var states: [Bool] = []
        via.onCB2Change = { states.append($0) }

        via.writeRegister(0x0C, value: 0xC0) // CB2 manual low
        via.writeRegister(0x0C, value: 0xE0) // CB2 manual high

        XCTAssertEqual(states, [false, true])
        XCTAssertTrue(via.cb2OutputState)
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

    func testTimer1LowReadLatchesHighByteUntilHighRead() {
        let via = VIA6522()
        via.timer1Counter = 0x12FF

        XCTAssertEqual(via.readRegister(0x04), 0xFF)

        via.timer1Counter = 0x1100

        XCTAssertEqual(via.readRegister(0x05), 0x12)
        XCTAssertEqual(via.readRegister(0x05), 0x11)
    }

    func testTimer1StartClearsLatchedHighByte() {
        let via = VIA6522()
        via.timer1Counter = 0x12FF
        XCTAssertEqual(via.readRegister(0x04), 0xFF)

        via.writeRegister(0x04, value: 0x00)
        via.writeRegister(0x05, value: 0x34)

        XCTAssertEqual(via.readRegister(0x05), 0x34)
    }

    func testTimer1OneShotPB7OutputGoesHighOnUnderflow() {
        let via = VIA6522()
        via.writeRegister(0x02, value: 0x80)
        via.writeRegister(0x0B, value: 0x80)
        via.writeRegister(0x04, value: 0x01)
        via.writeRegister(0x05, value: 0x00)

        XCTAssertEqual(via.readRegister(0x00) & 0x80, 0x00)

        via.tick()
        XCTAssertEqual(via.readRegister(0x00) & 0x80, 0x00)

        via.tick()
        XCTAssertEqual(via.readRegister(0x00) & 0x80, 0x80)
    }

    func testTimer1FreeRunPB7OutputTogglesOnUnderflows() {
        let via = VIA6522()
        via.writeRegister(0x02, value: 0x80)
        via.writeRegister(0x0B, value: 0xC0)
        via.writeRegister(0x04, value: 0x01)
        via.writeRegister(0x05, value: 0x00)

        XCTAssertEqual(via.readRegister(0x00) & 0x80, 0x00)

        via.tick()
        via.tick()
        XCTAssertEqual(via.readRegister(0x00) & 0x80, 0x80)

        via.tick()
        via.tick()
        XCTAssertEqual(via.readRegister(0x00) & 0x80, 0x00)
    }

    func testTimer1PB7OutputDoesNotOverrideInputMode() {
        let via = VIA6522()
        via.portBInput = 0x80
        via.writeRegister(0x02, value: 0x00)
        via.writeRegister(0x0B, value: 0x80)
        via.writeRegister(0x04, value: 0x01)
        via.writeRegister(0x05, value: 0x00)

        XCTAssertEqual(via.readRegister(0x00) & 0x80, 0x80)

        via.portBInput = 0x00
        via.tick()
        via.tick()

        XCTAssertEqual(via.readRegister(0x00) & 0x80, 0x00)
    }

    func testTimer1PB7OutputChangeInvokesPortBCallback() {
        let via = VIA6522()
        var observed: [UInt8] = []
        via.onPortBWrite = { observed.append(via.portBOut & 0x80) }
        via.writeRegister(0x02, value: 0x80)
        via.writeRegister(0x0B, value: 0x80)
        observed.removeAll()

        via.writeRegister(0x04, value: 0x01)
        via.writeRegister(0x05, value: 0x00)
        via.tick()
        via.tick()

        XCTAssertEqual(observed, [0x80])
    }

    func testTimer1PB7InputModeDoesNotInvokePortBCallbackOnUnderflow() {
        let via = VIA6522()
        var callbackCount = 0
        via.onPortBWrite = { callbackCount += 1 }
        via.writeRegister(0x02, value: 0x00)
        via.writeRegister(0x0B, value: 0x80)
        callbackCount = 0

        via.writeRegister(0x04, value: 0x01)
        via.writeRegister(0x05, value: 0x00)
        via.tick()
        via.tick()

        XCTAssertEqual(callbackCount, 0)
    }

    func testACRDisablingTimer1PB7OutputInvokesPortBCallback() {
        let via = VIA6522()
        var observed: [UInt8] = []
        via.onPortBWrite = { observed.append(via.portBOut & 0x80) }
        via.writeRegister(0x02, value: 0x80)
        via.writeRegister(0x0B, value: 0x80)
        via.writeRegister(0x04, value: 0x01)
        via.writeRegister(0x05, value: 0x00)
        via.tick()
        via.tick()
        observed.removeAll()

        via.writeRegister(0x0B, value: 0x00)

        XCTAssertEqual(observed, [0x00])
        XCTAssertEqual(via.readRegister(0x00) & 0x80, 0x00)
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

    func testTimer2LowReadLatchesHighByteUntilHighRead() {
        let via = VIA6522()
        via.timer2Counter = 0x34FE

        XCTAssertEqual(via.readRegister(0x08), 0xFE)

        via.timer2Counter = 0x3301

        XCTAssertEqual(via.readRegister(0x09), 0x34)
        XCTAssertEqual(via.readRegister(0x09), 0x33)
    }

    func testTimer2StartClearsLatchedHighByte() {
        let via = VIA6522()
        via.timer2Counter = 0x34FE
        XCTAssertEqual(via.readRegister(0x08), 0xFE)

        via.writeRegister(0x08, value: 0x00)
        via.writeRegister(0x09, value: 0x56)

        XCTAssertEqual(via.readRegister(0x09), 0x56)
    }

    func testShiftRegisterReadClearsSRInterrupt() {
        let via = VIA6522()
        via.writeRegister(0x0E, value: 0x84)
        via.shiftRegister = 0xA5
        via.setIFR(VIA6522.IRQ.sr)

        XCTAssertEqual(via.readRegister(0x0A), 0xA5)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, 0)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.any, 0)
    }

    func testShiftRegisterWriteClearsSRInterrupt() {
        let via = VIA6522()
        via.writeRegister(0x0E, value: 0x84)
        via.setIFR(VIA6522.IRQ.sr)

        via.writeRegister(0x0A, value: 0x5A)

        XCTAssertEqual(via.shiftRegister, 0x5A)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, 0)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.any, 0)
    }

    func testShiftRegisterExternalCB1InputShiftsCB2BitsAndSetsInterrupt() {
        let via = VIA6522()
        var irqStates: [Bool] = []
        via.onInterrupt = { irqStates.append($0) }
        via.writeRegister(0x0B, value: 0x0C) // SR mode 3: shift in under external CB1 clock
        via.writeRegister(0x0E, value: 0x84) // enable SR interrupt

        pulseExternalShiftInput(via, bits: [true, false, true, false, false, true, false, true])

        XCTAssertEqual(via.shiftRegister, 0xA5)
        XCTAssertEqual(via.shiftRegisterBitCount, 0)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, VIA6522.IRQ.sr)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.any, VIA6522.IRQ.any)
        XCTAssertEqual(irqStates.last, true)
    }

    func testShiftRegisterReadResetsExternalCB1Counter() {
        let via = VIA6522()
        via.writeRegister(0x0B, value: 0x0C)
        via.writeRegister(0x0E, value: 0x84)
        pulseExternalShiftInput(via, bits: [true, false, true, false])

        _ = via.readRegister(0x0A)

        XCTAssertEqual(via.shiftRegisterBitCount, 0)
        pulseExternalShiftInput(via, bits: [true, true, true, true])
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, 0)

        pulseExternalShiftInput(via, bits: [false, false, false, false])
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, VIA6522.IRQ.sr)
    }

    func testShiftRegisterDisabledIgnoresExternalCB1PulsesAndClearsInterrupt() {
        let via = VIA6522()
        via.writeRegister(0x0B, value: 0x0C)
        via.setIFR(VIA6522.IRQ.sr)

        via.writeRegister(0x0B, value: 0x00)
        pulseExternalShiftInput(via, bits: [true, true, true, true, true, true, true, true])

        XCTAssertEqual(via.shiftRegister, 0x00)
        XCTAssertEqual(via.shiftRegisterBitCount, 0)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, 0)
    }

    func testShiftRegisterExternalCB1OutputShiftsMSBFirstAndSetsInterrupt() {
        let via = VIA6522()
        var irqStates: [Bool] = []
        via.onInterrupt = { irqStates.append($0) }
        via.writeRegister(0x0B, value: 0x1C) // SR mode 7: shift out under external CB1 clock
        via.writeRegister(0x0E, value: 0x84)
        via.writeRegister(0x0A, value: 0xA5)

        let states = pulseExternalShiftOutput(via, count: 8)

        XCTAssertEqual(states, [true, false, true, false, false, true, false, true])
        XCTAssertEqual(via.shiftRegister, 0x00)
        XCTAssertEqual(via.shiftRegisterBitCount, 0)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, VIA6522.IRQ.sr)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.any, VIA6522.IRQ.any)
        XCTAssertEqual(irqStates.last, true)
    }

    func testShiftRegisterExternalCB1OutputNotifiesCB2Changes() {
        let via = VIA6522()
        var states: [Bool] = []
        via.onCB2Change = { states.append($0) }
        via.writeRegister(0x0B, value: 0x1C)
        via.writeRegister(0x0A, value: 0x55)

        _ = pulseExternalShiftOutput(via, count: 8)

        XCTAssertEqual(states, [false, true, false, true, false, true, false, true])
    }

    func testShiftRegisterWriteResetsExternalCB1OutputCounter() {
        let via = VIA6522()
        via.writeRegister(0x0B, value: 0x1C)
        via.writeRegister(0x0E, value: 0x84)
        via.writeRegister(0x0A, value: 0xF0)
        _ = pulseExternalShiftOutput(via, count: 4)

        via.writeRegister(0x0A, value: 0x0F)

        XCTAssertEqual(via.shiftRegisterBitCount, 0)
        _ = pulseExternalShiftOutput(via, count: 4)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, 0)

        _ = pulseExternalShiftOutput(via, count: 4)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, VIA6522.IRQ.sr)
    }

    func testShiftRegisterPhi2InputShiftsCB2BitsAndStopsAfterByte() {
        let via = VIA6522()
        var irqStates: [Bool] = []
        via.onInterrupt = { irqStates.append($0) }
        via.writeRegister(0x0B, value: 0x08) // SR mode 2: shift in under PHI2
        via.writeRegister(0x0E, value: 0x84)
        via.writeRegister(0x0A, value: 0x00)

        shiftPhi2Input(via, bits: [true, false, true, false, false, true, false, true])

        XCTAssertEqual(via.shiftRegister, 0xA5)
        XCTAssertEqual(via.shiftRegisterBitCount, 0)
        XCTAssertFalse(via.shiftRegisterPhi2Active)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, VIA6522.IRQ.sr)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.any, VIA6522.IRQ.any)
        XCTAssertEqual(irqStates.last, true)

        via.cb2 = false
        via.tick()
        XCTAssertEqual(via.shiftRegister, 0xA5)
    }

    func testShiftRegisterPhi2OutputShiftsMSBFirstAndStopsAfterByte() {
        let via = VIA6522()
        via.writeRegister(0x0B, value: 0x18) // SR mode 6: shift out under PHI2
        via.writeRegister(0x0E, value: 0x84)
        via.writeRegister(0x0A, value: 0xA5)

        let states = shiftPhi2Output(via, count: 8)

        XCTAssertEqual(states, [true, false, true, false, false, true, false, true])
        XCTAssertEqual(via.shiftRegister, 0x00)
        XCTAssertEqual(via.shiftRegisterBitCount, 0)
        XCTAssertFalse(via.shiftRegisterPhi2Active)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, VIA6522.IRQ.sr)

        via.tick()
        XCTAssertTrue(via.cb2OutputState)
    }

    func testShiftRegisterReadStartsPhi2InputTransferAndClearsInterrupt() {
        let via = VIA6522()
        via.writeRegister(0x0B, value: 0x08)
        via.writeRegister(0x0E, value: 0x84)
        via.setIFR(VIA6522.IRQ.sr)

        _ = via.readRegister(0x0A)

        XCTAssertTrue(via.shiftRegisterPhi2Active)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, 0)
    }

    func testShiftRegisterPhi2ModesEmitCB1OutputClockPulses() {
        let via = VIA6522()
        var states: [Bool] = []
        via.onCB1Change = { states.append($0) }
        via.writeRegister(0x0B, value: 0x08)
        via.writeRegister(0x0A, value: 0x00)

        via.tick()
        via.tick()

        XCTAssertEqual(states, [false, true, false, true])
        XCTAssertTrue(via.cb1OutputState)
    }

    func testShiftRegisterTimer2InputShiftsCB2BitsAndStopsAfterByte() {
        let via = VIA6522()
        via.writeRegister(0x08, value: 0x00)
        via.writeRegister(0x0B, value: 0x04) // SR mode 1: shift in under T2 control
        via.writeRegister(0x0E, value: 0x84)
        via.writeRegister(0x0A, value: 0x00)

        shiftTimer2Input(via, bits: [true, false, true, false, false, true, false, true])

        XCTAssertEqual(via.shiftRegister, 0xA5)
        XCTAssertEqual(via.shiftRegisterBitCount, 0)
        XCTAssertFalse(via.shiftRegisterTimer2Active)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, VIA6522.IRQ.sr)

        via.cb2 = false
        via.tick()
        XCTAssertEqual(via.shiftRegister, 0xA5)
    }

    func testShiftRegisterTimer2OutputShiftsMSBFirstAndStopsAfterByte() {
        let via = VIA6522()
        via.writeRegister(0x08, value: 0x00)
        via.writeRegister(0x0B, value: 0x14) // SR mode 5: shift out under T2 control
        via.writeRegister(0x0E, value: 0x84)
        via.writeRegister(0x0A, value: 0xA5)

        let states = shiftTimer2Output(via, count: 8)

        XCTAssertEqual(states, [true, false, true, false, false, true, false, true])
        XCTAssertEqual(via.shiftRegister, 0x00)
        XCTAssertEqual(via.shiftRegisterBitCount, 0)
        XCTAssertFalse(via.shiftRegisterTimer2Active)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, VIA6522.IRQ.sr)
    }

    func testShiftRegisterTimer2FreeRunOutputRecirculatesWithoutInterrupt() {
        let via = VIA6522()
        via.writeRegister(0x08, value: 0x00)
        via.writeRegister(0x0B, value: 0x10) // SR mode 4: free-running shift out under T2 control
        via.writeRegister(0x0E, value: 0x84)
        via.writeRegister(0x0A, value: 0xA5)

        let firstByte = shiftTimer2Output(via, count: 8)
        let secondByte = shiftTimer2Output(via, count: 8)

        XCTAssertEqual(firstByte, [true, false, true, false, false, true, false, true])
        XCTAssertEqual(secondByte, firstByte)
        XCTAssertEqual(via.shiftRegister, 0xA5)
        XCTAssertEqual(via.ifr & VIA6522.IRQ.sr, 0)
        XCTAssertTrue(via.shiftRegisterTimer2Active)
    }

    func testShiftRegisterTimer2ModesEmitCB1OutputClockPulses() {
        let via = VIA6522()
        var states: [Bool] = []
        via.onCB1Change = { states.append($0) }
        via.writeRegister(0x08, value: 0x00)
        via.writeRegister(0x0B, value: 0x10)
        via.writeRegister(0x0A, value: 0xA5)

        via.tick()
        via.tick()

        XCTAssertEqual(states, [false, true, false, true])
        XCTAssertTrue(via.cb1OutputState)
    }

    func testShiftRegisterExternalCB1ModesDoNotEmitCB1OutputClockPulses() {
        let via = VIA6522()
        var states: [Bool] = []
        via.onCB1Change = { states.append($0) }
        via.writeRegister(0x0B, value: 0x0C)
        via.writeRegister(0x0A, value: 0x00)

        pulseExternalShiftInput(via, bits: [true, false, true, false])

        via.writeRegister(0x0B, value: 0x1C)
        via.writeRegister(0x0A, value: 0xF0)
        _ = pulseExternalShiftOutput(via, count: 4)

        XCTAssertEqual(states, [])
        XCTAssertTrue(via.cb1OutputState)
    }

    func testShiftRegisterTimer2ClockUsesLatchLowDelay() {
        let via = VIA6522()
        via.writeRegister(0x08, value: 0x01)
        via.writeRegister(0x0B, value: 0x04)
        via.writeRegister(0x0A, value: 0x00)

        via.cb2 = true
        via.tick()
        XCTAssertEqual(via.shiftRegister, 0x00)
        XCTAssertEqual(via.shiftRegisterTimer2Counter, 0x00)

        via.tick()
        XCTAssertEqual(via.shiftRegister, 0x01)
        XCTAssertEqual(via.shiftRegisterTimer2Counter, 0x01)
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

    func testCA2HandshakeModeTransitionsOnPortAWrite() {
        let via = VIA6522()
        var states: [Bool] = []
        via.onCA2Change = { states.append($0) }
        via.pcr = 0x08 // CA2 handshake output
        via.ca2OutputState = true

        via.writeRegister(0x01, value: 0xA5)

        XCTAssertEqual(via.portA, 0xA5)
        XCTAssertEqual(states, [false])
        XCTAssertFalse(via.ca2OutputState)
    }

    func testCA2PulseModePulsesOnPortAWrite() {
        let via = VIA6522()
        var states: [Bool] = []
        via.onCA2Change = { states.append($0) }
        via.writeRegister(0x0C, value: 0x0A) // CA2 pulse output, normally high

        via.writeRegister(0x01, value: 0x5A)

        XCTAssertEqual(via.portA, 0x5A)
        XCTAssertEqual(states, [false, true])
        XCTAssertTrue(via.ca2OutputState)
    }

    func testCB2HandshakeModeTransitionsOnPortBRead() {
        let via = VIA6522()
        var states: [Bool] = []
        via.onCB2Change = { states.append($0) }
        via.pcr = 0x80 // CB2 handshake output
        via.cb2OutputState = true

        _ = via.readRegister(0x00)

        XCTAssertEqual(states, [false])
        XCTAssertFalse(via.cb2OutputState)
    }

    func testCB2HandshakeModeTransitionsOnPortBWrite() {
        let via = VIA6522()
        var states: [Bool] = []
        via.onCB2Change = { states.append($0) }
        via.pcr = 0x80 // CB2 handshake output
        via.cb2OutputState = true

        via.writeRegister(0x00, value: 0xA5)

        XCTAssertEqual(via.portB, 0xA5)
        XCTAssertEqual(states, [false])
        XCTAssertFalse(via.cb2OutputState)
    }

    func testCB2HandshakeModeReturnsHighOnCB1ActiveEdge() {
        let via = VIA6522()
        var states: [Bool] = []
        via.onCB2Change = { states.append($0) }
        via.writeRegister(0x0C, value: 0x90) // CB1 positive edge, CB2 handshake output

        via.writeRegister(0x00, value: 0xA5)
        XCTAssertEqual(states, [false])
        XCTAssertFalse(via.cb2OutputState)

        via.cb1 = true
        via.tick()

        XCTAssertEqual(states, [false, true])
        XCTAssertTrue(via.cb2OutputState)
    }

    func testCB2PulseModePulsesOnPortBWrite() {
        let via = VIA6522()
        var states: [Bool] = []
        via.onCB2Change = { states.append($0) }
        via.writeRegister(0x0C, value: 0xA0) // CB2 pulse output, normally high

        via.writeRegister(0x00, value: 0x5A)

        XCTAssertEqual(via.portB, 0x5A)
        XCTAssertEqual(states, [false, true])
        XCTAssertTrue(via.cb2OutputState)
    }

    private func pulseExternalShiftInput(_ via: VIA6522, bits: [Bool]) {
        for bit in bits {
            via.cb2 = bit
            via.cb1 = false
            via.tick()
            via.cb1 = true
            via.tick()
        }
    }

    private func pulseExternalShiftOutput(_ via: VIA6522, count: Int) -> [Bool] {
        var states: [Bool] = []
        for _ in 0..<count {
            via.cb1 = false
            via.tick()
            via.cb1 = true
            via.tick()
            states.append(via.cb2OutputState)
        }
        return states
    }

    private func shiftPhi2Input(_ via: VIA6522, bits: [Bool]) {
        for bit in bits {
            via.cb2 = bit
            via.tick()
        }
    }

    private func shiftPhi2Output(_ via: VIA6522, count: Int) -> [Bool] {
        var states: [Bool] = []
        for _ in 0..<count {
            via.tick()
            states.append(via.cb2OutputState)
        }
        return states
    }

    private func shiftTimer2Input(_ via: VIA6522, bits: [Bool]) {
        for bit in bits {
            via.cb2 = bit
            via.tick()
        }
    }

    private func shiftTimer2Output(_ via: VIA6522, count: Int) -> [Bool] {
        var states: [Bool] = []
        for _ in 0..<count {
            via.tick()
            states.append(via.cb2OutputState)
        }
        return states
    }
}
