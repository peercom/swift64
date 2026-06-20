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
}
