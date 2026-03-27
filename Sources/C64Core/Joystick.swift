import Foundation

/// Joystick port emulation. Maps keyboard keys to joystick directions.
/// Port 2 is the primary gaming port on the C64 (directly read by CIA1 Port A).
public final class Joystick {

    /// Joystick state bits (active low):
    /// Bit 0 = Up, 1 = Down, 2 = Left, 3 = Right, 4 = Fire
    public var port1: UInt8 = 0xFF
    public var port2: UInt8 = 0xFF

    public init() {}

    /// Handle key down for joystick (port 2 by default).
    /// Uses numpad or WASD+Space layout.
    /// Returns true if the key was a joystick key.
    public func handleKeyDown(keyCode: UInt16) -> Bool {
        switch keyCode {
        // Numpad (joystick port 2)
        case 91:  port2 &= ~0x01; return true  // Numpad 8 = Up
        case 84:  port2 &= ~0x02; return true  // Numpad 2 = Down
        case 86:  port2 &= ~0x04; return true  // Numpad 4 = Left
        case 88:  port2 &= ~0x08; return true  // Numpad 6 = Right
        case 82:  port2 &= ~0x10; return true  // Numpad 0 = Fire
        case 83:  port2 &= ~0x10; return true  // Numpad Enter = Fire
        default:  return false
        }
    }

    public func handleKeyUp(keyCode: UInt16) -> Bool {
        switch keyCode {
        case 91:  port2 |= 0x01; return true
        case 84:  port2 |= 0x02; return true
        case 86:  port2 |= 0x04; return true
        case 88:  port2 |= 0x08; return true
        case 82:  port2 |= 0x10; return true
        case 83:  port2 |= 0x10; return true
        default:  return false
        }
    }
}
