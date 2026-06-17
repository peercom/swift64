import XCTest
@testable import C64Core

final class CIATests: XCTestCase {
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
        XCTAssertEqual(cia.timerA, 0x0000)
        XCTAssertFalse(cia.interruptActive)

        cia.pulseCNT()
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
        XCTAssertEqual(cia.timerB, 0x0000)
        XCTAssertFalse(cia.interruptActive)

        cia.pulseCNT()
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

    private func tickTODTenth(_ cia: CIA) {
        for _ in 0..<CIA.palCyclesPerTodTenth {
            cia.tick()
        }
    }

    private func tickTimerAUnderflow(_ cia: CIA) {
        cia.tick()
        cia.tick()
    }

    private func tickTimerBUnderflow(_ cia: CIA) {
        cia.tick()
        cia.tick()
    }
}
