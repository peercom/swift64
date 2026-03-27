import Foundation

/// MOS 6526 CIA (Complex Interface Adapter) emulation.
/// Two instances: CIA1 ($DC00, IRQ) and CIA2 ($DD00, NMI).
public final class CIA {

    // MARK: - Ports

    /// Port A data register
    public var portA: UInt8 = 0xFF
    /// Port B data register
    public var portB: UInt8 = 0xFF
    /// Port A data direction (0=input, 1=output)
    public var ddra: UInt8 = 0x00
    /// Port B data direction
    public var ddrb: UInt8 = 0x00

    /// The effective output value of port A (data & direction, inputs pulled high)
    public var portAOut: UInt8 {
        return (portA & ddra) | (~ddra & 0xFF)
    }

    /// The effective output value of port B
    public var portBOut: UInt8 {
        return (portB & ddrb) | (~ddrb & 0xFF)
    }

    // MARK: - Timers

    /// Timer A current value
    public var timerA: UInt16 = 0xFFFF
    /// Timer A latch (reload value)
    public var timerALatch: UInt16 = 0xFFFF
    /// Timer A control register
    public var timerAControl: UInt8 = 0x00

    /// Timer B current value
    public var timerB: UInt16 = 0xFFFF
    /// Timer B latch
    public var timerBLatch: UInt16 = 0xFFFF
    /// Timer B control register
    public var timerBControl: UInt8 = 0x00

    // MARK: - Interrupt

    /// Interrupt control mask (which sources are enabled)
    public var interruptMask: UInt8 = 0x00
    /// Interrupt control data (which sources have fired)
    public var interruptData: UInt8 = 0x00

    /// Whether this CIA's interrupt line is active
    public var interruptActive: Bool = false

    // MARK: - TOD (Time of Day) — simplified

    var todTenths: UInt8 = 0
    var todSeconds: UInt8 = 0
    var todMinutes: UInt8 = 0
    var todHours: UInt8 = 0x01  // BCD, bit 7 = PM
    var todAlarmTenths: UInt8 = 0
    var todAlarmSeconds: UInt8 = 0
    var todAlarmMinutes: UInt8 = 0
    var todAlarmHours: UInt8 = 0
    var todLatched: Bool = false
    var todLatchTenths: UInt8 = 0
    var todLatchSeconds: UInt8 = 0
    var todLatchMinutes: UInt8 = 0
    var todLatchHours: UInt8 = 0
    var todWriteAlarm: Bool = false

    // MARK: - Keyboard matrix (CIA1 only)

    /// 8×8 keyboard matrix. Each byte represents a row.
    /// Bit = 0 means key pressed.
    public var keyboardMatrix = [UInt8](repeating: 0xFF, count: 8)

    /// Joystick port 1 (directly on port A for CIA1)
    /// Bits: 0=Up, 1=Down, 2=Left, 3=Right, 4=Fire (active low)
    public var joystickPort1: UInt8 = 0xFF

    /// Joystick port 2 (on port B for CIA1)
    public var joystickPort2: UInt8 = 0xFF

    /// Is this CIA1 (true) or CIA2 (false)?
    public let isCIA1: Bool

    /// Callback for interrupt state changes
    public var onInterrupt: ((Bool) -> Void)?

    /// Callback to read external input bits for port A (used by CIA2 for IEC bus).
    /// Returns bits to be ORed into port A input (for bits where DDR=0).
    public var readPortAExternal: (() -> UInt8)?

    /// Callback when port A is written (used by CIA2 for IEC bus).
    public var onPortAWrite: ((UInt8) -> Void)?

    // MARK: - Serial port register (stub)
    var serialData: UInt8 = 0

    // MARK: - Init

    public init(isCIA1: Bool) {
        self.isCIA1 = isCIA1
    }

    // MARK: - Tick

    /// Advance one system clock cycle.
    public func tick() {
        // Timer A
        if timerAControl & 0x01 != 0 {
            let countSource = timerAControl & 0x20  // bit 5: 0=system clock, 1=CNT pin
            if countSource == 0 {
                if timerA == 0 {
                    timerAUnderflow()
                } else {
                    timerA &-= 1
                }
            }
        }

        // Timer B
        if timerBControl & 0x01 != 0 {
            let countSource = timerBControl & 0x60
            if countSource == 0 {
                // Count system clock
                if timerB == 0 {
                    timerBUnderflow()
                } else {
                    timerB &-= 1
                }
            }
            // countSource == 0x40: count timer A underflows (handled in timerAUnderflow)
        }
    }

    func timerAUnderflow() {
        // Set interrupt flag
        interruptData |= 0x01
        checkInterrupt()

        // Reload or stop
        if timerAControl & 0x08 != 0 {
            // One-shot: stop timer
            timerAControl &= ~0x01
        }
        timerA = timerALatch

        // If timer B counts timer A underflows
        if timerBControl & 0x61 == 0x41 {
            if timerB == 0 {
                timerBUnderflow()
            } else {
                timerB &-= 1
            }
        }
    }

    func timerBUnderflow() {
        interruptData |= 0x02
        checkInterrupt()

        if timerBControl & 0x08 != 0 {
            timerBControl &= ~0x01
        }
        timerB = timerBLatch
    }

    func checkInterrupt() {
        if (interruptData & interruptMask) != 0 {
            interruptData |= 0x80  // Set IR bit
            interruptActive = true
            onInterrupt?(true)
        }
    }

    // MARK: - Register access

    public func readRegister(_ reg: UInt16) -> UInt8 {
        switch reg {
        case 0x00:  // Port A
            if isCIA1 {
                return readKeyboard() & joystickPort1
            }
            // CIA2: output bits from portA, input bits from external (IEC bus)
            let external = readPortAExternal?() ?? 0xFF
            return (portA & ddra) | (external & ~ddra)

        case 0x01:  // Port B
            if isCIA1 {
                return readKeyboardPortB() & joystickPort2
            }
            return portBOut

        case 0x02: return ddra
        case 0x03: return ddrb
        case 0x04: return UInt8(timerA & 0xFF)
        case 0x05: return UInt8(timerA >> 8)
        case 0x06: return UInt8(timerB & 0xFF)
        case 0x07: return UInt8(timerB >> 8)

        // TOD
        case 0x08:
            if todLatched {
                todLatched = false
                return todLatchTenths
            }
            return todTenths
        case 0x09:
            return todLatched ? todLatchSeconds : todSeconds
        case 0x0A:
            return todLatched ? todLatchMinutes : todMinutes
        case 0x0B:
            // Reading hours latches TOD
            todLatched = true
            todLatchTenths = todTenths
            todLatchSeconds = todSeconds
            todLatchMinutes = todMinutes
            todLatchHours = todHours
            return todHours

        case 0x0C:
            return serialData

        case 0x0D:
            // Interrupt control — reading clears
            let val = interruptData
            interruptData = 0
            interruptActive = false
            onInterrupt?(false)
            return val

        case 0x0E: return timerAControl
        case 0x0F: return timerBControl

        default: return 0
        }
    }

    public func writeRegister(_ reg: UInt16, value: UInt8) {
        switch reg {
        case 0x00:
            portA = value
            onPortAWrite?(portAOut)
        case 0x01: portB = value
        case 0x02:
            ddra = value
            onPortAWrite?(portAOut)  // DDR change affects output
        case 0x03: ddrb = value
        case 0x04: timerALatch = (timerALatch & 0xFF00) | UInt16(value)
        case 0x05:
            timerALatch = (timerALatch & 0x00FF) | (UInt16(value) << 8)
            // If timer stopped, load latch into timer
            if timerAControl & 0x01 == 0 {
                timerA = timerALatch
            }
        case 0x06: timerBLatch = (timerBLatch & 0xFF00) | UInt16(value)
        case 0x07:
            timerBLatch = (timerBLatch & 0x00FF) | (UInt16(value) << 8)
            if timerBControl & 0x01 == 0 {
                timerB = timerBLatch
            }

        // TOD
        case 0x08:
            if todWriteAlarm { todAlarmTenths = value & 0x0F }
            else { todTenths = value & 0x0F }
        case 0x09:
            if todWriteAlarm { todAlarmSeconds = value & 0x7F }
            else { todSeconds = value & 0x7F }
        case 0x0A:
            if todWriteAlarm { todAlarmMinutes = value & 0x7F }
            else { todMinutes = value & 0x7F }
        case 0x0B:
            if todWriteAlarm { todAlarmHours = value & 0x9F }
            else { todHours = value & 0x9F }

        case 0x0C:
            serialData = value

        case 0x0D:
            // Interrupt control
            if value & 0x80 != 0 {
                // Set bits
                interruptMask |= (value & 0x1F)
            } else {
                // Clear bits
                interruptMask &= ~(value & 0x1F)
            }
            checkInterrupt()

        case 0x0E:
            // Timer A control
            let forceLoad = value & 0x10 != 0
            timerAControl = value & ~0x10  // bit 4 is strobe only
            if forceLoad {
                timerA = timerALatch
            }

        case 0x0F:
            let forceLoad = value & 0x10 != 0
            todWriteAlarm = (value & 0x80) != 0
            timerBControl = value & ~0x10
            if forceLoad {
                timerB = timerBLatch
            }

        default: break
        }
    }

    // MARK: - Keyboard matrix scanning

    /// Read keyboard: Port A drives rows, Port B reads columns.
    /// When a row bit in Port A is 0, all pressed keys in that row show as 0 in Port B.
    func readKeyboard() -> UInt8 {
        // Port A is being read, but for keyboard CIA1 reads port B
        // Actually for CIA1, Port A output selects which rows to scan
        return joystickPort1 & 0xFF
    }

    func readKeyboardPortB() -> UInt8 {
        let rowSelect = portAOut
        var result: UInt8 = 0xFF

        // For each row that is selected (driven low), OR in the pressed keys
        for row in 0..<8 {
            if rowSelect & (1 << row) == 0 {
                result &= keyboardMatrix[row]
            }
        }

        return result
    }
}
