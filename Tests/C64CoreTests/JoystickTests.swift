import XCTest
@testable import C64Core

final class JoystickTests: XCTestCase {
    func testNumpadFireMirrorsToPortOneByDefault() {
        let joystick = Joystick()

        XCTAssertTrue(joystick.handleKeyDown(keyCode: 82))
        XCTAssertEqual(joystick.port2 & 0x10, 0)
        XCTAssertEqual(joystick.port1 & 0x10, 0)

        XCTAssertTrue(joystick.handleKeyUp(keyCode: 82))
        XCTAssertEqual(joystick.port2 & 0x10, 0x10)
        XCTAssertEqual(joystick.port1 & 0x10, 0x10)
    }

    func testPortOneMirrorCanBeDisabled() {
        let joystick = Joystick()
        joystick.mirrorPort2ToPort1 = false

        XCTAssertTrue(joystick.handleKeyDown(keyCode: 82))
        XCTAssertEqual(joystick.port2 & 0x10, 0)
        XCTAssertEqual(joystick.port1 & 0x10, 0x10)
    }

    func testExternalControllerStateMergesWithKeyboardPorts() {
        let joystick = Joystick()
        joystick.routing = .port2

        // Controller alone: fire on port 2 only.
        joystick.externalPort2 = 0xFF & ~0x10
        XCTAssertEqual(joystick.effectivePort2, 0xEF)
        XCTAssertEqual(joystick.effectivePort1, 0xFF)
        XCTAssertEqual(joystick.port2, 0xFF, "keyboard state is untouched by controller input")

        // Keyboard adds a direction while the controller still fires.
        XCTAssertTrue(joystick.handleKeyDown(keyCode: 91))
        XCTAssertEqual(joystick.effectivePort2, 0xEE)

        // Releasing the controller leaves only the keyboard direction.
        joystick.externalPort2 = 0xFF
        XCTAssertEqual(joystick.effectivePort2, 0xFE)

        XCTAssertTrue(joystick.handleKeyUp(keyCode: 91))
        XCTAssertEqual(joystick.effectivePort2, 0xFF)
    }

    func testCIA1SeesMergedJoystickPorts() {
        let c64 = C64()
        c64.joystick.externalPort1 = 0xFF & ~0x02
        c64.joystick.externalPort2 = 0xFF & ~0x10
        c64.tickOneCycle()
        XCTAssertEqual(c64.cia1.joystickPort1, 0xFD)
        XCTAssertEqual(c64.cia1.joystickPort2, 0xEF)
    }

    func testNumpadFireCanRouteOnlyToPortOne() {
        let joystick = Joystick()
        joystick.routing = .port1

        XCTAssertTrue(joystick.handleKeyDown(keyCode: 82))
        XCTAssertEqual(joystick.port1 & 0x10, 0)
        XCTAssertEqual(joystick.port2 & 0x10, 0x10)

        XCTAssertTrue(joystick.handleKeyUp(keyCode: 82))
        XCTAssertEqual(joystick.port1 & 0x10, 0x10)
        XCTAssertEqual(joystick.port2 & 0x10, 0x10)
    }
}
