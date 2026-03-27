/// Status register flag bit positions.
public struct Flags {
    public static let carry: UInt8     = 1 << 0  // C
    public static let zero: UInt8      = 1 << 1  // Z
    public static let interrupt: UInt8 = 1 << 2  // I
    public static let decimal: UInt8   = 1 << 3  // D
    public static let brk: UInt8       = 1 << 4  // B
    public static let unused: UInt8    = 1 << 5  // Always 1
    public static let overflow: UInt8  = 1 << 6  // V
    public static let negative: UInt8  = 1 << 7  // N
}

/// Interrupt vectors.
public enum Vector {
    public static let nmi: UInt16   = 0xFFFA
    public static let reset: UInt16 = 0xFFFC
    public static let irq: UInt16   = 0xFFFE
}

/// Addressing mode identifiers used by the instruction decoder.
public enum AddressingMode {
    case implied
    case accumulator
    case immediate
    case zeroPage
    case zeroPageX
    case zeroPageY
    case absolute
    case absoluteX
    case absoluteY
    case indirectX    // (Indirect,X)
    case indirectY    // (Indirect),Y
    case relative
    case indirect     // JMP only
}
