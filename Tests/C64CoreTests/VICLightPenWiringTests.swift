import XCTest
@testable import C64Core

final class VICLightPenWiringTests: XCTestCase {
    private func machine() -> C64 {
        let c64 = C64()
        c64.trueDriveEmulationMode = .off
        c64.kernalTraps.enabled = false
        c64.vic.recordsBusAccessTraces = false
        c64.vic.rasterLine = 80
        return c64
    }

    func testCPUWriteCapturesBeamAndRaisesVICInterruptOnSameCycle() {
        let c64 = machine()
        c64.cia1.writeRegister(3, value: 0x10)
        c64.vic.writeRegister(0x1A, value: 0x08)
        c64.cpu.pc = 0x0600
        c64.cpu.a = 0xEF
        c64.memory.ram.replaceSubrange(0x0600..<0x0603, with: [0x8D, 0x01, 0xDC])
        c64.vic.rasterCycle = 16
        for _ in 0..<3 { c64.tickOneCycle() }
        XCTAssertFalse(c64.vic.lightPenLatchedThisFrame)
        c64.tickOneCycle() // STA at hardware cycle 20: end-of-cycle X=$03C.
        XCTAssertEqual(c64.vic.readRegister(0x13), 0x1E)
        XCTAssertEqual(c64.vic.readRegister(0x14), 80)
        XCTAssertEqual(c64.vic.readRegister(0x19) & 0x88, 0x88)
        XCTAssertTrue(c64.cpu.irqLine)
    }

    func testInputLatchDoesNotDriveLPButChangingDDRDoes() {
        let c64 = machine()
        c64.cia1.writeRegister(1, value: 0xEF)
        XCTAssertFalse(c64.vic.lightPenLatchedThisFrame)
        c64.vic.rasterCycle = 19
        c64.cia1.writeRegister(3, value: 0x10)
        XCTAssertTrue(c64.vic.lightPenLatchedThisFrame)
        XCTAssertEqual(c64.vic.lightPenX, 0x1E)
    }

    func testCIA2DoesNotDriveLightPen() {
        let c64 = machine()
        c64.cia2.writeRegister(3, value: 0xFF)
        c64.cia2.writeRegister(1, value: 0)
        XCTAssertFalse(c64.vic.lightPenLatchedThisFrame)
    }

    func testSpaceKeyTriggersOnlyWhenItsRowIsSelected() {
        let c64 = machine()
        c64.cia1.writeRegister(2, value: 0xFF)
        c64.keyboard.pressKey(row: 7, col: 4)
        XCTAssertFalse(c64.vic.lightPenLatchedThisFrame)
        c64.vic.rasterCycle = 19
        c64.cia1.writeRegister(0, value: 0x7F)
        XCTAssertTrue(c64.vic.lightPenLatchedThisFrame)
        XCTAssertEqual(c64.vic.lightPenX, 0x1E)
    }

    func testJoystickFireTriggersPB4AndAcknowledgementDoesNotRearmSameFrame() {
        let c64 = machine()
        c64.vic.rasterCycle = 19
        c64.cia1.joystickPort1 = 0xEF
        XCTAssertEqual(c64.vic.lightPenX, 0x1E)
        c64.vic.writeRegister(0x19, value: 0x08)
        c64.cia1.joystickPort1 = 0xFF
        c64.vic.rasterCycle = 25
        c64.cia1.joystickPort1 = 0xEF
        XCTAssertEqual(c64.vic.lightPenX, 0x1E)
        XCTAssertEqual(c64.vic.readRegister(0x19) & 0x08, 0)
    }
}
