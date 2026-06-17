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

    func testCIA2InterruptAssertAndClearDrivesCPUNMILine() {
        let c64 = C64()

        c64.cia2.interruptData = 0x01
        c64.cia2.writeRegister(0x0D, value: 0x81)

        XCTAssertTrue(c64.cpu.nmiLine)

        XCTAssertEqual(c64.cia2.readRegister(0x0D), 0x81)
        XCTAssertFalse(c64.cpu.nmiLine)
    }

    func testRestoreKeyPressTriggersMachineLevelNMI() {
        let c64 = C64()

        XCTAssertFalse(c64.restoreKeyDown)

        XCTAssertTrue(c64.pressRestoreKey())

        XCTAssertTrue(c64.restoreKeyDown)
        XCTAssertFalse(c64.cpu.nmiLine)

        c64.tickOneCycle()

        XCTAssertTrue(c64.cpu.servicingInterrupt)

        c64.releaseRestoreKey()

        XCTAssertFalse(c64.restoreKeyDown)
    }

    func testHoldingRestoreKeyDoesNotRetriggerUntilReleased() {
        let c64 = C64()

        XCTAssertTrue(c64.pressRestoreKey())
        XCTAssertFalse(c64.pressRestoreKey())

        c64.releaseRestoreKey()

        XCTAssertTrue(c64.pressRestoreKey())
    }

    func testRawTAPFallingEdgeDrivesCIA1FlagOnlyWhenCassetteMotorRuns() {
        let c64 = C64()

        XCTAssertTrue(c64.mountTape(makeTAP(payload: [0x01])))
        XCTAssertTrue(c64.tapeUnit.rawPlaybackActive)
        XCTAssertFalse(c64.memory.cassetteSenseLineHigh)
        c64.cia1.writeRegister(0x0D, value: 0x90)

        for _ in 0..<8 {
            c64.tickOneCycle()
        }

        XCTAssertFalse(c64.cia1.interruptActive)
        XCTAssertEqual(c64.tapeUnit.currentPulseIndex, 0)

        c64.memory.write(0x0000, value: 0x20)
        c64.memory.write(0x0001, value: 0x00)

        for _ in 0..<8 {
            c64.tickOneCycle()
        }

        XCTAssertFalse(c64.tapeUnit.readSignalHigh)
        XCTAssertEqual(c64.tapeUnit.currentPulseIndex, 1)
        XCTAssertTrue(c64.cia1.interruptActive)
        XCTAssertTrue(c64.cpu.irqLine)
        XCTAssertEqual(c64.cia1.readRegister(0x0D), 0x90)
        XCTAssertFalse(c64.cpu.irqLine)
    }

    func testUnmountTapeClearsRawPlaybackAndRestoresSenseAndFlagLines() {
        let c64 = C64()

        XCTAssertTrue(c64.mountTape(makeTAP(payload: [0x01])))
        XCTAssertTrue(c64.tapeUnit.rawPlaybackActive)
        XCTAssertFalse(c64.memory.cassetteSenseLineHigh)

        c64.unmountTape()

        XCTAssertFalse(c64.tapeUnit.isMounted)
        XCTAssertFalse(c64.tapeUnit.rawPlaybackActive)
        XCTAssertTrue(c64.memory.cassetteSenseLineHigh)
        XCTAssertTrue(c64.cia1.flagLineHigh)
    }

    private func makeTAP(payload: [UInt8]) -> Data {
        var bytes = [UInt8](repeating: 0, count: 20)
        writeASCII("C64-TAPE-RAW", into: &bytes, at: 0)
        bytes[0x0C] = 0
        writeUInt32LE(UInt32(payload.count), into: &bytes, at: 0x10)
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    private func writeASCII(_ string: String, into bytes: inout [UInt8], at offset: Int) {
        for (index, byte) in string.utf8.enumerated() {
            bytes[offset + index] = byte
        }
    }

    private func writeUInt32LE(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}
