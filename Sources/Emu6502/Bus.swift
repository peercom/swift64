/// Protocol for the CPU's address/data bus.
/// Host emulators implement this to wire up RAM, ROM, and I/O chips.
public protocol Bus: AnyObject {
    /// Read a byte from the given 16-bit address.
    func read(_ address: UInt16) -> UInt8

    /// Write a byte to the given 16-bit address.
    func write(_ address: UInt16, value: UInt8)
}
