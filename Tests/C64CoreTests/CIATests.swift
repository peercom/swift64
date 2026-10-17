import XCTest
@testable import C64Core

final class CIATests: XCTestCase {
    func testDebugRegisterValueReportsCIAStateWithoutReadSideEffects() {
        let cia = CIA(isCIA1: true)
        cia.writeRegister(0x00, value: 0x12)
        cia.writeRegister(0x01, value: 0x34)
        cia.writeRegister(0x02, value: 0xFF)
        cia.writeRegister(0x03, value: 0x0F)
        cia.timerA = 0x1234
        cia.timerB = 0xABCD
        cia.writeRegister(0x08, value: 0x05)
        cia.writeRegister(0x09, value: 0x42)
        cia.writeRegister(0x0A, value: 0x31)
        cia.writeRegister(0x0B, value: 0x81)
        cia.writeRegister(0x0C, value: 0x5A)
        cia.interruptData = 0x83
        cia.interruptActive = true
        cia.writeRegister(0x0E, value: 0x41)
        cia.writeRegister(0x0F, value: 0x81)

        XCTAssertEqual(cia.debugRegisterValue(0xDC00), 0x12)
        XCTAssertEqual(cia.debugRegisterValue(0xDC01), 0xF4)
        XCTAssertEqual(cia.debugRegisterValue(0xDC02), 0xFF)
        XCTAssertEqual(cia.debugRegisterValue(0xDC03), 0x0F)
        XCTAssertEqual(cia.debugRegisterValue(0xDC04), 0x34)
        XCTAssertEqual(cia.debugRegisterValue(0xDC05), 0x12)
        XCTAssertEqual(cia.debugRegisterValue(0xDC06), 0xCD)
        XCTAssertEqual(cia.debugRegisterValue(0xDC07), 0xAB)
        XCTAssertEqual(cia.debugRegisterValue(0xDC08), 0x05)
        XCTAssertEqual(cia.debugRegisterValue(0xDC09), 0x42)
        XCTAssertEqual(cia.debugRegisterValue(0xDC0A), 0x31)
        XCTAssertEqual(cia.debugRegisterValue(0xDC0B), 0x81)
        XCTAssertEqual(cia.debugRegisterValue(0xDC0C), 0x5A)
        XCTAssertEqual(cia.debugRegisterValue(0xDC0D), 0x83)
        XCTAssertEqual(cia.debugRegisterValue(0xDC0E), 0x41)
        XCTAssertEqual(cia.debugRegisterValue(0xDC0F), 0x81)

        XCTAssertNil(cia.timerAHighLatched)
        XCTAssertEqual(cia.interruptData, 0x83)
        XCTAssertTrue(cia.interruptActive)
    }

    func testTimerBCountsTimerAUnderflows() {
        let cia = CIA(isCIA1: true)
        cia.writeRegister(0x04, value: 0x01)
        cia.writeRegister(0x05, value: 0x00)
        cia.writeRegister(0x06, value: 0x01)
        cia.writeRegister(0x07, value: 0x00)
        cia.writeRegister(0x0D, value: 0x82)
        cia.writeRegister(0x0F, value: 0x41)
        cia.writeRegister(0x0E, value: 0x01)

        tickTimerAUnderflow(cia)
        cia.tick()
        cia.tick() // Cascaded count crosses the Timer B input pipeline.

        XCTAssertFalse(cia.interruptActive)
        XCTAssertEqual(cia.timerB, 0x0000)

        tickTimerAUnderflow(cia)

        XCTAssertTrue(cia.interruptActive)
        XCTAssertEqual(cia.interruptData & 0x02, 0x02)
        XCTAssertEqual(cia.timerB, 0x0001)
    }

    func testTimerBCountsTimerAUnderflowsWhenCNTModeIsSelected() {
        let cia = CIA(isCIA1: true)
        cia.writeRegister(0x04, value: 0x01)
        cia.writeRegister(0x05, value: 0x00)
        cia.writeRegister(0x06, value: 0x01)
        cia.writeRegister(0x07, value: 0x00)
        cia.writeRegister(0x0D, value: 0x82)
        cia.writeRegister(0x0F, value: 0x61)
        cia.writeRegister(0x0E, value: 0x01)

        tickTimerAUnderflow(cia)
        cia.tick()
        cia.tick()

        XCTAssertFalse(cia.interruptActive)
        XCTAssertEqual(cia.timerB, 0x0000)

        tickTimerAUnderflow(cia)

        XCTAssertTrue(cia.interruptActive)
        XCTAssertEqual(cia.interruptData & 0x02, 0x02)
    }

    func testTimerBCountsTimerAUnderflowsOnlyWhileCNTIsHighInGatedMode() {
        let cia = CIA(isCIA1: true)
        cia.writeRegister(0x04, value: 0x01)
        cia.writeRegister(0x05, value: 0x00)
        cia.writeRegister(0x06, value: 0x01)
        cia.writeRegister(0x07, value: 0x00)
        cia.writeRegister(0x0D, value: 0x82)
        cia.writeRegister(0x0F, value: 0x61)
        cia.writeRegister(0x0E, value: 0x01)

        cia.setCNTLine(high: false)
        tickTimerAUnderflow(cia)

        XCTAssertEqual(cia.timerB, 0x0001)
        XCTAssertFalse(cia.interruptActive)

        cia.setCNTLine(high: true)
        tickTimerAUnderflow(cia)
        cia.tick()
        cia.tick()

        XCTAssertEqual(cia.timerB, 0x0000)
        XCTAssertFalse(cia.interruptActive)

        tickTimerAUnderflow(cia)

        XCTAssertEqual(cia.timerB, 0x0001)
        XCTAssertTrue(cia.interruptActive)
        XCTAssertEqual(cia.interruptData & 0x02, 0x02)
    }

    func testTimerACountsCNTPulsesWhenCNTModeIsSelected() {
        let cia = CIA(isCIA1: true)
        cia.writeRegister(0x04, value: 0x01)
        cia.writeRegister(0x05, value: 0x00)
        cia.writeRegister(0x0D, value: 0x81)
        cia.writeRegister(0x0E, value: 0x21)

        cia.tick()
        XCTAssertEqual(cia.timerA, 0x0001)

        cia.pulseCNT()
        tickCNTPropagation(cia)
        XCTAssertEqual(cia.timerA, 0x0000)
        XCTAssertFalse(cia.interruptActive)

        cia.pulseCNT()
        tickCNTPropagation(cia)
        XCTAssertEqual(cia.timerA, 0x0001)
        XCTAssertTrue(cia.interruptActive)
        XCTAssertEqual(cia.interruptData & 0x01, 0x01)
    }

    func testTimerACountsCNTRisingEdgesWhenCNTModeIsSelected() {
        let cia = CIA(isCIA1: true)
        cia.setCNTLine(high: false)
        cia.writeRegister(0x04, value: 0x01)
        cia.writeRegister(0x05, value: 0x00)
        cia.writeRegister(0x0D, value: 0x81)
        cia.writeRegister(0x0E, value: 0x21)

        cia.setCNTLine(high: false)
        XCTAssertEqual(cia.timerA, 0x0001)

        cia.setCNTLine(high: true)
        tickCNTPropagation(cia)
        XCTAssertEqual(cia.timerA, 0x0000)
        XCTAssertFalse(cia.interruptActive)

        cia.setCNTLine(high: true)
        tickCNTPropagation(cia)
        XCTAssertEqual(cia.timerA, 0x0000)

        cia.setCNTLine(high: false)
        XCTAssertEqual(cia.timerA, 0x0000)

        cia.setCNTLine(high: true)
        tickCNTPropagation(cia)
        XCTAssertEqual(cia.timerA, 0x0001)
        XCTAssertTrue(cia.interruptActive)
        XCTAssertEqual(cia.interruptData & 0x01, 0x01)
    }

    func testTimerBCountsCNTPulsesWhenCNTModeIsSelected() {
        let cia = CIA(isCIA1: true)
        cia.writeRegister(0x06, value: 0x01)
        cia.writeRegister(0x07, value: 0x00)
        cia.writeRegister(0x0D, value: 0x82)
        cia.writeRegister(0x0F, value: 0x21)

        cia.tick()
        XCTAssertEqual(cia.timerB, 0x0001)

        cia.pulseCNT()
        tickCNTPropagation(cia)
        XCTAssertEqual(cia.timerB, 0x0000)
        XCTAssertFalse(cia.interruptActive)

        cia.pulseCNT()
        tickCNTPropagation(cia)
        XCTAssertEqual(cia.timerB, 0x0001)
        XCTAssertTrue(cia.interruptActive)
        XCTAssertEqual(cia.interruptData & 0x02, 0x02)
    }

    func testTimerBCountsCNTRisingEdgesWhenCNTModeIsSelected() {
        let cia = CIA(isCIA1: true)
        cia.setCNTLine(high: false)
        cia.writeRegister(0x06, value: 0x01)
        cia.writeRegister(0x07, value: 0x00)
        cia.writeRegister(0x0D, value: 0x82)
        cia.writeRegister(0x0F, value: 0x21)

        cia.setCNTLine(high: true)
        tickCNTPropagation(cia)
        XCTAssertEqual(cia.timerB, 0x0000)
        XCTAssertFalse(cia.interruptActive)

        cia.setCNTLine(high: false)
        cia.setCNTLine(high: true)
        tickCNTPropagation(cia)

        XCTAssertEqual(cia.timerB, 0x0001)
        XCTAssertTrue(cia.interruptActive)
        XCTAssertEqual(cia.interruptData & 0x02, 0x02)
    }

    func testTimerOneShotStopsAfterUnderflow() {
        let cia = CIA(isCIA1: true)
        cia.writeRegister(0x04, value: 0x01)
        cia.writeRegister(0x05, value: 0x00)
        cia.writeRegister(0x0E, value: 0x09)

        tickTimerAUnderflow(cia)

        XCTAssertEqual(cia.timerAControl & 0x01, 0x00)
        XCTAssertEqual(cia.timerA, 0x0001)
        XCTAssertEqual(cia.interruptData & 0x01, 0x01)
    }

    func testTimerBOneShotStopsAfterUnderflow() {
        let cia = CIA(isCIA1: true)
        cia.writeRegister(0x06, value: 0x01)
        cia.writeRegister(0x07, value: 0x00)
        cia.writeRegister(0x0F, value: 0x09)

        tickTimerBUnderflow(cia)

        XCTAssertEqual(cia.timerBControl & 0x01, 0x00)
        XCTAssertEqual(cia.timerB, 0x0001)
        XCTAssertEqual(cia.interruptData & 0x02, 0x02)
    }

    func testTimerAPulseOutputAppearsOnPB6ForOneCycle() {
        let cia = CIA(isCIA1: false)
        cia.writeRegister(0x04, value: 0x01)
        cia.writeRegister(0x05, value: 0x00)
        cia.writeRegister(0x0E, value: 0x03)

        XCTAssertEqual(cia.readRegister(0x01) & 0x40, 0x00)

        tickTimerAUnderflow(cia)

        XCTAssertEqual(cia.readRegister(0x01) & 0x40, 0x40)

        cia.tick()

        XCTAssertEqual(cia.readRegister(0x01) & 0x40, 0x00)
    }

    func testTimerAToggleOutputFlipsPB6OnUnderflow() {
        let cia = CIA(isCIA1: false)
        cia.writeRegister(0x04, value: 0x01)
        cia.writeRegister(0x05, value: 0x00)
        cia.writeRegister(0x0E, value: 0x07)

        XCTAssertEqual(cia.readRegister(0x01) & 0x40, 0x40)

        tickTimerAUnderflow(cia)

        XCTAssertEqual(cia.readRegister(0x01) & 0x40, 0x00)

        tickTimerAUnderflow(cia)

        XCTAssertEqual(cia.readRegister(0x01) & 0x40, 0x40)
    }

    func testTimerBToggleOutputFlipsPB7OnUnderflow() {
        let cia = CIA(isCIA1: false)
        cia.writeRegister(0x06, value: 0x01)
        cia.writeRegister(0x07, value: 0x00)
        cia.writeRegister(0x0F, value: 0x07)

        XCTAssertEqual(cia.readRegister(0x01) & 0x80, 0x80)

        tickTimerBUnderflow(cia)

        XCTAssertEqual(cia.readRegister(0x01) & 0x80, 0x00)

        tickTimerBUnderflow(cia)

        XCTAssertEqual(cia.readRegister(0x01) & 0x80, 0x80)
    }

    func testTimerALowReadLatchesHighByteUntilHighRead() {
        let cia = CIA(isCIA1: true)
        cia.timerA = 0x12FF

        XCTAssertEqual(cia.readRegister(0x04), 0xFF)

        cia.timerA = 0x1100

        XCTAssertEqual(cia.readRegister(0x05), 0x12)
        XCTAssertEqual(cia.readRegister(0x05), 0x11)
    }

    func testTimerAReloadClearsLatchedHighByte() {
        let cia = CIA(isCIA1: true)
        cia.timerA = 0x12FF
        XCTAssertEqual(cia.readRegister(0x04), 0xFF)

        cia.writeRegister(0x04, value: 0x00)
        cia.writeRegister(0x05, value: 0x34)

        XCTAssertEqual(cia.readRegister(0x05), 0x34)
    }

    func testTimerBLowReadLatchesHighByteUntilHighRead() {
        let cia = CIA(isCIA1: true)
        cia.timerB = 0x34FE

        XCTAssertEqual(cia.readRegister(0x06), 0xFE)

        cia.timerB = 0x3301

        XCTAssertEqual(cia.readRegister(0x07), 0x34)
        XCTAssertEqual(cia.readRegister(0x07), 0x33)
    }

    func testTimerBForceLoadClearsLatchedHighByte() {
        let cia = CIA(isCIA1: true)
        cia.timerB = 0x34FE
        cia.timerBLatch = 0x5600
        XCTAssertEqual(cia.readRegister(0x06), 0xFE)

        cia.writeRegister(0x0F, value: 0x10)
        cia.tick()
        cia.tick()

        XCTAssertEqual(cia.readRegister(0x07), 0x56)
    }

    func testTODAdvancesTenthsAndRollsSeconds() {
        let cia = CIA(isCIA1: true)
        cia.writeRegister(0x0B, value: 0x01)
        cia.writeRegister(0x0A, value: 0x00)
        cia.writeRegister(0x09, value: 0x00)
        cia.writeRegister(0x08, value: 0x09)

        tickTODTenth(cia)

        XCTAssertEqual(cia.readRegister(0x0B), 0x01)
        XCTAssertEqual(cia.readRegister(0x0A), 0x00)
        XCTAssertEqual(cia.readRegister(0x09), 0x01)
        XCTAssertEqual(cia.readRegister(0x08), 0x00)
    }

    func testTODRollsFromElevenToTwelveAndTogglesPM() {
        let cia = CIA(isCIA1: true)
        cia.writeRegister(0x0B, value: 0x11)
        cia.writeRegister(0x0A, value: 0x59)
        cia.writeRegister(0x09, value: 0x59)
        cia.writeRegister(0x08, value: 0x09)

        tickTODTenth(cia)

        XCTAssertEqual(cia.readRegister(0x0B), 0x92)
        XCTAssertEqual(cia.readRegister(0x0A), 0x00)
        XCTAssertEqual(cia.readRegister(0x09), 0x00)
        XCTAssertEqual(cia.readRegister(0x08), 0x00)
    }

    func testTODWriteHoursStopsClockUntilTenthsWritten() {
        let cia = CIA(isCIA1: true)
        cia.writeRegister(0x0B, value: 0x01)

        tickTODTenth(cia)

        XCTAssertEqual(cia.readRegister(0x08), 0x00)

        cia.writeRegister(0x08, value: 0x05)
        tickTODTenth(cia)

        XCTAssertEqual(cia.readRegister(0x08), 0x06)
    }

    func testTODHoursReadLatchesUntilTenthsRead() {
        let cia = CIA(isCIA1: true)
        cia.writeRegister(0x0B, value: 0x01)
        cia.writeRegister(0x0A, value: 0x00)
        cia.writeRegister(0x09, value: 0x00)
        cia.writeRegister(0x08, value: 0x08)

        XCTAssertEqual(cia.readRegister(0x0B), 0x01)

        tickTODTenth(cia)
        tickTODTenth(cia)

        XCTAssertEqual(cia.readRegister(0x0B), 0x01)
        XCTAssertEqual(cia.readRegister(0x09), 0x00)
        XCTAssertEqual(cia.readRegister(0x08), 0x08)
        XCTAssertEqual(cia.readRegister(0x09), 0x01)
        XCTAssertEqual(cia.readRegister(0x08), 0x00)
    }

    func testTODAlarmSetsInterruptFlagAndAssertsWhenMasked() {
        let cia = CIA(isCIA1: true)
        var irqStates: [Bool] = []
        cia.onInterrupt = { irqStates.append($0) }

        cia.writeRegister(0x0F, value: 0x80)
        cia.writeRegister(0x0B, value: 0x01)
        cia.writeRegister(0x0A, value: 0x00)
        cia.writeRegister(0x09, value: 0x00)
        cia.writeRegister(0x08, value: 0x01)
        cia.writeRegister(0x0F, value: 0x00)

        cia.writeRegister(0x0B, value: 0x01)
        cia.writeRegister(0x0A, value: 0x00)
        cia.writeRegister(0x09, value: 0x00)
        cia.writeRegister(0x08, value: 0x00)
        cia.writeRegister(0x0D, value: 0x84)

        tickTODTenth(cia)

        XCTAssertTrue(cia.interruptActive)
        XCTAssertEqual(cia.readRegister(0x0D), 0x84)
        XCTAssertEqual(irqStates, [true, false])
    }

    func testTODFrequencySelectionUsesControlRegisterBit7() {
        let cia = CIA(isCIA1: true)
        cia.configureTOD(fiftyHzCyclesPerTenth: 5, sixtyHzCyclesPerTenth: 6, selectedCyclesPerTenth: 5)

        XCTAssertEqual(cia.cyclesPerTodTenth, 5)

        cia.writeRegister(0x08, value: 0x00)
        tickTODCycles(cia, 4)
        XCTAssertEqual(cia.readRegister(0x08), 0x00)
        tickTODCycles(cia, 1)
        XCTAssertEqual(cia.readRegister(0x08), 0x01)

        cia.writeRegister(0x0E, value: 0x00)
        XCTAssertEqual(cia.cyclesPerTodTenth, 6)
        cia.writeRegister(0x08, value: 0x00)
        tickTODCycles(cia, 5)
        XCTAssertEqual(cia.readRegister(0x08), 0x00)
        tickTODCycles(cia, 1)
        XCTAssertEqual(cia.readRegister(0x08), 0x01)

        cia.writeRegister(0x0E, value: 0x80)
        XCTAssertEqual(cia.cyclesPerTodTenth, 5)
        cia.writeRegister(0x08, value: 0x00)
        tickTODCycles(cia, 5)
        XCTAssertEqual(cia.readRegister(0x08), 0x01)
    }

    func testJoystickPort2ReadsFromCIA1PortA() {
        let cia = CIA(isCIA1: true)

        cia.joystickPort2 = 0b1110_1111

        XCTAssertEqual(cia.readRegister(0x00), 0b1110_1111)
        XCTAssertEqual(cia.readRegister(0x01), 0xFF)
    }

    func testJoystickPort1ReadsFromCIA1PortB() {
        let cia = CIA(isCIA1: true)

        cia.joystickPort1 = 0b1111_0111

        XCTAssertEqual(cia.readRegister(0x00), 0xFF)
        XCTAssertEqual(cia.readRegister(0x01), 0b1111_0111)
    }

    func testKeyboardMatrixCanBeScannedFromCIA1PortA() {
        let cia = CIA(isCIA1: true)
        cia.keyboardMatrix[3] = 0b1111_1011
        cia.writeRegister(0x03, value: 0xFF)
        cia.writeRegister(0x01, value: 0b1111_1011)

        XCTAssertEqual(cia.readRegister(0x00), 0b1111_0111)
    }

    func testKeyboardMatrixCanBeScannedFromCIA1PortB() {
        let cia = CIA(isCIA1: true)
        cia.keyboardMatrix[3] = 0b1111_1011
        cia.writeRegister(0x02, value: 0xFF)
        cia.writeRegister(0x00, value: 0b1111_0111)

        XCTAssertEqual(cia.readRegister(0x01), 0b1111_1011)
    }

    func testKeyboardMatrixGhostsColumnsThroughPressedKeyBridge() {
        let cia = CIA(isCIA1: true)
        cia.keyboardMatrix[1] = 0b1111_1011
        cia.keyboardMatrix[3] = 0b1101_1011
        cia.writeRegister(0x02, value: 0xFF)
        cia.writeRegister(0x00, value: 0b1111_1101)

        XCTAssertEqual(cia.readRegister(0x01), 0b1101_1011)
    }

    func testKeyboardMatrixGhostsRowsThroughPressedKeyBridge() {
        let cia = CIA(isCIA1: true)
        cia.keyboardMatrix[1] = 0b1101_1011
        cia.keyboardMatrix[3] = 0b1101_1111
        cia.writeRegister(0x03, value: 0xFF)
        cia.writeRegister(0x01, value: 0b1111_1011)

        XCTAssertEqual(cia.readRegister(0x00), 0b1111_0101)
    }

    func testJoystickPort2LowRowsPropagateThroughKeyboardMatrix() {
        let cia = CIA(isCIA1: true)
        cia.keyboardMatrix[1] = 0b1111_1011
        cia.joystickPort2 = 0b1111_1101

        XCTAssertEqual(cia.readRegister(0x01), 0b1111_1011)
    }

    func testJoystickPort1LowColumnsPropagateThroughKeyboardMatrix() {
        let cia = CIA(isCIA1: true)
        cia.keyboardMatrix[3] = 0b1111_1011
        cia.joystickPort1 = 0b1111_1011

        XCTAssertEqual(cia.readRegister(0x00), 0b1111_0111)
    }

    func testCIA1PortAReadReflectsConfiguredOutputs() {
        let cia = CIA(isCIA1: true)
        cia.writeRegister(0x02, value: 0b0000_1111)
        cia.writeRegister(0x00, value: 0b0000_0101)

        XCTAssertEqual(cia.readRegister(0x00), 0b1111_0101)
    }

    func testCIA1PortBReadReflectsConfiguredOutputs() {
        let cia = CIA(isCIA1: true)
        cia.writeRegister(0x03, value: 0b0000_1111)
        cia.writeRegister(0x01, value: 0b0000_1010)

        XCTAssertEqual(cia.readRegister(0x01), 0b1111_1010)
    }

    func testEnablingPendingInterruptAssertsOnceAndRequiresReadToAcknowledge() {
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

        XCTAssertTrue(cia.interruptActive)
        XCTAssertEqual(cia.interruptData, 0x81)
        XCTAssertEqual(irqStates, [true])
        XCTAssertEqual(cia.readRegister(0x0D), 0x81)
        XCTAssertFalse(cia.interruptActive)
        XCTAssertEqual(cia.interruptData, 0)
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

    func testFlagFallingEdgeSetsInterruptAndAcknowledges() {
        let cia = CIA(isCIA1: true)
        var irqStates: [Bool] = []
        cia.onInterrupt = { irqStates.append($0) }

        cia.writeRegister(0x0D, value: 0x90)
        cia.setFlagLine(high: false)

        XCTAssertTrue(cia.interruptActive)
        XCTAssertEqual(cia.readRegister(0x0D), 0x90)
        XCTAssertEqual(irqStates, [true, false])
    }

    func testFlagInterruptRequiresFallingEdge() {
        let cia = CIA(isCIA1: true)

        cia.setFlagLine(high: false)
        cia.setFlagLine(high: false)

        XCTAssertEqual(cia.interruptData, 0x10)

        cia.writeRegister(0x0D, value: 0x10)
        XCTAssertEqual(cia.interruptData, 0x10)

        _ = cia.readRegister(0x0D)
        cia.setFlagLine(high: false)

        XCTAssertEqual(cia.interruptData, 0x00)

        cia.setFlagLine(high: true)
        cia.setFlagLine(high: false)

        XCTAssertEqual(cia.interruptData, 0x10)
    }

    func testSerialInputShiftsSPOnCNTPulsesAndRaisesInterrupt() {
        let cia = CIA(isCIA1: true)

        cia.writeRegister(0x0D, value: 0x88)

        for bit in [true, false, true, false, false, true, false] {
            cia.setSPLine(high: bit)
            cia.pulseCNT()
            XCTAssertFalse(cia.interruptActive)
        }

        cia.setSPLine(high: true)
        cia.pulseCNT()

        XCTAssertEqual(cia.readRegister(0x0C), 0b1010_0101)
        XCTAssertTrue(cia.interruptActive)
        XCTAssertEqual(cia.readRegister(0x0D), 0x88)
        XCTAssertFalse(cia.interruptActive)
    }

    func testSerialInputShiftsSPOnCNTRisingEdgesAndRaisesInterrupt() {
        let cia = CIA(isCIA1: true)
        cia.setCNTLine(high: false)
        cia.writeRegister(0x0D, value: 0x88)

        for bit in [false, true, true, false, true, false, false, true] {
            cia.setSPLine(high: bit)
            cia.setCNTLine(high: false)
            cia.setCNTLine(high: true)
        }

        XCTAssertEqual(cia.readRegister(0x0C), 0b0110_1001)
        XCTAssertTrue(cia.interruptActive)
        XCTAssertEqual(cia.readRegister(0x0D), 0x88)
        XCTAssertFalse(cia.interruptActive)
    }

    func testSerialInputCallbackReportsCompletedByteAfterEightCNTPulses() {
        let cia = CIA(isCIA1: true)
        var receivedBytes: [UInt8] = []
        cia.onSerialInputByte = { receivedBytes.append($0) }

        for bit in [true, false, true, false, false, true, false] {
            cia.setSPLine(high: bit)
            cia.pulseCNT()
        }

        XCTAssertTrue(receivedBytes.isEmpty)

        cia.setSPLine(high: true)
        cia.pulseCNT()

        XCTAssertEqual(receivedBytes, [0b1010_0101])
        XCTAssertEqual(cia.readRegister(0x0C), 0b1010_0101)
    }

    func testSerialOutputShiftsMSBFirstOnEveryOtherTimerAUnderflow() {
        let cia = CIA(isCIA1: true)

        cia.writeRegister(0x04, value: 0x01)
        cia.writeRegister(0x05, value: 0x00)
        cia.writeRegister(0x0D, value: 0x88)
        cia.writeRegister(0x0E, value: 0x41)
        cia.writeRegister(0x0C, value: 0b1010_0101)

        // A bit is placed on SP on the first underflow and then on every
        // second one; the underflows in between are the rising CNT edges.
        var shiftedBits: [Bool] = []
        for underflow in 0..<16 {
            tickTimerAUnderflow(cia)
            if underflow % 2 == 0 { shiftedBits.append(cia.spLineHigh) }
            XCTAssertFalse(cia.interruptActive, "underflow \(underflow)")
        }
        XCTAssertEqual(shiftedBits, [true, false, true, false, false, true, false, true])
    }

    func testSerialOutputWrittenBeforeOutputModeIsTakenOnFirstUnderflowAfterEnable() {
        let cia = CIA(isCIA1: true)

        cia.writeRegister(0x04, value: 0x01)
        cia.writeRegister(0x05, value: 0x00)
        cia.writeRegister(0x0C, value: 0b1100_0011)
        cia.writeRegister(0x0E, value: 0x01)
        for _ in 0..<10 { cia.tick() }
        XCTAssertEqual(cia.serialOutputBitsRemaining, 0)
        XCTAssertTrue(cia.serialOutputPending)

        cia.writeRegister(0x0E, value: 0x41)
        XCTAssertEqual(cia.serialOutputBitsRemaining, 0, "the shifter loads on the next clock, not on the mode write")

        var shiftedBits: [Bool] = []
        for underflow in 0..<16 {
            tickTimerAUnderflow(cia)
            if underflow % 2 == 0 { shiftedBits.append(cia.spLineHigh) }
        }
        XCTAssertEqual(shiftedBits, [true, true, false, false, false, false, true, true])
        XCTAssertFalse(cia.serialOutputPending)
    }

    func testSerialOutputCallbackReportsEveryShiftedSPBit() {
        let cia = CIA(isCIA1: true)
        var outputBits: [Bool] = []
        var clockPulses = 0
        cia.onSerialOutputBit = { outputBits.append($0) }
        cia.onSerialClockPulse = { clockPulses += 1 }

        cia.writeRegister(0x04, value: 0x01)
        cia.writeRegister(0x05, value: 0x00)
        cia.writeRegister(0x0E, value: 0x41)
        cia.writeRegister(0x0C, value: 0b1100_0011)

        for _ in 0..<16 {
            tickTimerAUnderflow(cia)
        }

        XCTAssertEqual(outputBits, [true, true, false, false, false, false, true, true])
        XCTAssertEqual(clockPulses, 8)
        XCTAssertEqual(cia.spLineHigh, true)
    }

    // Timing measured with the public `cia-sdr-init`/`cia-sdr-delay` programs
    // and the `cia-sdr-icr` per-cycle references: with Timer A latch L the
    // n-th underflow is L + 2 + (n - 1)(L + 1) clocks after the start write,
    // and the SDR flag follows the 15th underflow (the eighth output edge)
    // four clocks later.
    func testSerialOutputFlagFollowsFifteenthUnderflowByFourClocks() {
        let cia = CIA(isCIA1: false)
        cia.writeRegister(0x04, value: 50)
        cia.writeRegister(0x05, value: 0)
        cia.writeRegister(0x0E, value: 0x51)
        cia.writeRegister(0x0C, value: 0x55)

        var timerAFlagClock: Int?
        var serialFlagClock: Int?
        for clock in 1...800 {
            cia.tick()
            if timerAFlagClock == nil && cia.debugRegisterValue(0x0D) & 0x01 != 0 { timerAFlagClock = clock }
            if serialFlagClock == nil && cia.debugRegisterValue(0x0D) & 0x08 != 0 { serialFlagClock = clock }
        }
        // Clock k here is the k-th tick after the start write, so the first
        // underflow (52 clocks after the write) lands on clock 53.
        XCTAssertEqual(timerAFlagClock, 53)
        XCTAssertEqual(serialFlagClock, 53 + 14 * 51 + 4)
    }

    func testSerialOutputFlagForLatchesBelowThreeStartsOnTheSecondUnderflow() {
        // The byte reaches the shifter one clock after the SDR write, so
        // with latches 1 and 2 the first underflow passes before it and the
        // flag lands one period later than the 15-underflow rule suggests.
        // As in the programs, the SDR is written four clocks after CRA.
        for (latch, expected) in [(UInt8(1), 3 + 1 + 15 * 2 + 4), (2, 3 + 2 + 15 * 3 + 4), (3, 3 + 3 + 14 * 4 + 4), (4, 3 + 4 + 14 * 5 + 4)] {
            let cia = CIA(isCIA1: false)
            cia.writeRegister(0x04, value: latch)
            cia.writeRegister(0x05, value: 0)
            cia.writeRegister(0x0E, value: 0x51)
            for _ in 0..<4 { cia.tick() }
            cia.writeRegister(0x0C, value: 0x55)
            var serialFlagClock: Int?
            for clock in 5...200 {
                cia.tick()
                if serialFlagClock == nil && cia.debugRegisterValue(0x0D) & 0x08 != 0 { serialFlagClock = clock }
            }
            XCTAssertEqual(serialFlagClock, expected, "latch \(latch)")
        }
    }

    func testSerialOutputQueuedByteStartsOnTheClosingEdgeOfThePreviousByte() {
        // `cia-sdr-load`: two bytes written back to back are sent without a
        // gap; the second flag is 15 underflows after the first byte's
        // closing edge, plus the same four clocks.
        let cia = CIA(isCIA1: false)
        cia.writeRegister(0x04, value: 50)
        cia.writeRegister(0x05, value: 0)
        cia.writeRegister(0x0E, value: 0x51)
        cia.writeRegister(0x0C, value: 0xAA)
        cia.tick()
        cia.writeRegister(0x0C, value: 0x55)

        var flagClocks: [Int] = []
        for clock in 2...1600 {
            cia.tick()
            if cia.debugRegisterValue(0x0D) & 0x08 != 0 {
                flagClocks.append(clock)
                _ = cia.readRegister(0x0D)
            }
        }
        let firstFlag = 53 + 14 * 51 + 4
        XCTAssertEqual(flagClocks, [firstFlag, 53 + 15 * 51 + 14 * 51 + 4])
    }

    func testSerialOutputZeroLatchShiftsOnlyOnceUntilModeIsSwitched() {
        // Underflows every cycle never drop the underflow signal, so only the
        // first one is a shift edge: no byte completes, but the shifter has
        // started with CNT low, so switching the mode off and on raises the
        // flag each time (`cia-sdr-icr-0` first screen 1, second screen 9).
        let cia = CIA(isCIA1: false)
        cia.writeRegister(0x04, value: 0)
        cia.writeRegister(0x05, value: 0)
        cia.writeRegister(0x0E, value: 0x51)
        cia.writeRegister(0x0C, value: 0x55)
        for _ in 0..<200 {
            cia.tick()
            XCTAssertEqual(cia.debugRegisterValue(0x0D) & 0x08, 0)
        }
        XCTAssertEqual(cia.readRegister(0x0D) & 0x01, 0x01)
        cia.writeRegister(0x0E, value: 0x00)
        XCTAssertEqual(cia.readRegister(0x0D) & 0x08, 0x08)
        cia.writeRegister(0x0E, value: 0x51)
        XCTAssertEqual(cia.readRegister(0x0D) & 0x08, 0x08)
    }

    func testSerialOutputAbortedByModeSwitchRaisesFlagOnceShifterStarted() {
        // `cia-sdr-icr-test2`: clearing CRA bit 6 mid-byte raises the flag,
        // but only from four clocks after the first bit was placed on SP.
        for (clocksAfterFirstEdge, expectFlag) in [(0, false), (3, false), (4, true), (60, true)] {
            let cia = CIA(isCIA1: false)
            cia.writeRegister(0x04, value: 39)
            cia.writeRegister(0x05, value: 0)
            cia.writeRegister(0x0E, value: 0x51)
            cia.writeRegister(0x0C, value: 0x55)
            // The first output edge is the 42nd clock after the start write.
            for _ in 0..<(42 + clocksAfterFirstEdge) { cia.tick() }
            _ = cia.readRegister(0x0D)
            cia.writeRegister(0x0E, value: 0x00)
            XCTAssertEqual(cia.debugRegisterValue(0x0D) & 0x08 != 0, expectFlag, "\(clocksAfterFirstEdge) clocks")
        }

        // An idle shifter is not affected.
        let idle = CIA(isCIA1: false)
        idle.writeRegister(0x04, value: 39)
        idle.writeRegister(0x05, value: 0)
        idle.writeRegister(0x0E, value: 0x51)
        for _ in 0..<100 { idle.tick() }
        idle.writeRegister(0x0E, value: 0x00)
        XCTAssertEqual(idle.debugRegisterValue(0x0D) & 0x08, 0)
    }

    func testSerialOutputReenableRaisesFlagWhenCNTWasFrozenLow() {
        // `cia-sdr-icr` second screen: after an output edge CNT is seen low
        // from the first clock on, with a one-clock bounce high on the
        // second; after a rising edge it stays low for three clocks.
        let outputEdgeCases: [(Int, Bool)] = [(0, false), (1, true), (2, false), (3, true), (10, true), (39, true)]
        let risingEdgeCases: [(Int, Bool)] = [(0, true), (3, true), (4, false), (20, false)]
        for (afterRisingEdge, cases) in [(false, outputEdgeCases), (true, risingEdgeCases)] {
            for (clocks, expectFlag) in cases {
                let cia = CIA(isCIA1: false)
                cia.writeRegister(0x04, value: 39)
                cia.writeRegister(0x05, value: 0)
                cia.writeRegister(0x0E, value: 0x51)
                cia.writeRegister(0x0C, value: 0x55)
                // First output edge is the 42nd clock, the rising edge 40 later.
                for _ in 0..<(42 + (afterRisingEdge ? 40 : 0) + clocks) { cia.tick() }
                cia.writeRegister(0x0E, value: 0x00)
                for _ in 0..<50 { cia.tick() }
                _ = cia.readRegister(0x0D)
                cia.writeRegister(0x0E, value: 0x51)
                XCTAssertEqual(cia.debugRegisterValue(0x0D) & 0x08 != 0, expectFlag,
                               "\(clocks) clocks after \(afterRisingEdge ? "rising" : "output") edge")
                // The restart drives CNT high: a second enable does nothing.
                _ = cia.readRegister(0x0D)
                cia.writeRegister(0x0E, value: 0x00)
                cia.writeRegister(0x0E, value: 0x51)
                XCTAssertEqual(cia.debugRegisterValue(0x0D) & 0x08, 0)
            }
        }
    }

    private func tickTODTenth(_ cia: CIA) {
        for _ in 0..<CIA.palCyclesPerTodTenth {
            cia.tick()
        }
    }

    private func tickTODCycles(_ cia: CIA, _ count: Int) {
        for _ in 0..<count {
            cia.tick()
        }
    }

    private func tickTimerAUnderflow(_ cia: CIA) {
        let toggle = cia.timerAOutputHigh
        for _ in 0..<8 {
            cia.tick()
            if cia.timerAControl & 4 != 0 {
                if cia.timerAOutputHigh != toggle { return }
            } else if cia.timerAPulseCyclesRemaining != 0 { return }
        }
        XCTFail("Timer A did not underflow within eight clocks")
    }

    private func tickTimerBUnderflow(_ cia: CIA) {
        let toggle = cia.timerBOutputHigh
        for _ in 0..<8 {
            cia.tick()
            if cia.timerBControl & 4 != 0 {
                if cia.timerBOutputHigh != toggle { return }
            } else if cia.timerBPulseCyclesRemaining != 0 { return }
        }
        XCTFail("Timer B did not underflow within eight clocks")
    }

    private func tickCNTPropagation(_ cia: CIA) {
        for _ in 0..<4 { cia.tick() }
    }
}
