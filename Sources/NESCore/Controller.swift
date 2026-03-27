import Foundation

/// NES controller (standard joypad).
public final class Controller {

    /// Button bit masks
    public struct Button {
        public static let a:      UInt8 = 1 << 0
        public static let b:      UInt8 = 1 << 1
        public static let select: UInt8 = 1 << 2
        public static let start:  UInt8 = 1 << 3
        public static let up:     UInt8 = 1 << 4
        public static let down:   UInt8 = 1 << 5
        public static let left:   UInt8 = 1 << 6
        public static let right:  UInt8 = 1 << 7
    }

    /// Current button state (bits set = pressed)
    public var buttons: UInt8 = 0

    /// Shift register (latched state being read out)
    var shiftRegister: UInt8 = 0

    /// Strobe mode
    var strobe: Bool = false

    public init() {}

    /// Write to $4016 (controller port)
    public func write(_ value: UInt8) {
        strobe = (value & 1) != 0
        if strobe {
            shiftRegister = buttons
        }
    }

    /// Read from $4016/$4017 — returns one bit at a time
    public func read() -> UInt8 {
        if strobe {
            shiftRegister = buttons
        }
        let bit = shiftRegister & 1
        shiftRegister >>= 1
        return bit | 0x40  // Open bus bits
    }

    // MARK: - Button helpers

    public func press(_ button: UInt8) {
        buttons |= button
    }

    public func release(_ button: UInt8) {
        buttons &= ~button
    }
}
