import Foundation

/// MOS 6522 VIA (Versatile Interface Adapter) used in the 1541 disk drive.
/// Two instances: VIA1 (serial bus interface at $1800) and VIA2 (disk controller at $1C00).
public final class VIA6522 {

    // MARK: - Ports

    /// Port A output register
    public var portA: UInt8 = 0x00
    /// Port B output register
    public var portB: UInt8 = 0x00
    /// Port A data direction (1=output, 0=input)
    public var ddra: UInt8 = 0x00
    /// Port B data direction
    public var ddrb: UInt8 = 0x00

    /// External input lines for ports (bits where DDR=0 read from here)
    public var portAInput: UInt8 = 0xFF
    public var portBInput: UInt8 = 0xFF

    /// Effective output of port A (output bits from register, input bits from external)
    public var portAOut: UInt8 {
        (portA & ddra) | (portAInput & ~ddra)
    }

    /// Effective output of port B
    public var portBOut: UInt8 {
        (portB & ddrb) | (portBInput & ~ddrb)
    }

    // MARK: - Timers

    /// Timer 1 counter
    public var timer1Counter: UInt16 = 0xFFFF
    /// Timer 1 latch
    public var timer1Latch: UInt16 = 0xFFFF
    /// Timer 1 has fired (one-shot mode: prevents re-interrupt)
    var timer1Fired: Bool = false

    /// Timer 2 counter
    public var timer2Counter: UInt16 = 0xFFFF
    /// Timer 2 latch low byte (only low byte is latched)
    var timer2LatchLow: UInt8 = 0xFF
    /// Timer 2 has fired
    var timer2Fired: Bool = false

    // MARK: - Shift register

    var shiftRegister: UInt8 = 0x00

    // MARK: - Control registers

    /// Auxiliary Control Register
    /// Bit 7-6: Timer 1 control (00=one-shot, 01=free-run, 10=one-shot+PB7, 11=free-run+PB7)
    /// Bit 5: Timer 2 control (0=timed, 1=count PB6 pulses)
    /// Bit 4-2: Shift register control
    /// Bit 1: Port B latch enable
    /// Bit 0: Port A latch enable
    public var acr: UInt8 = 0x00

    /// Peripheral Control Register
    /// Bit 3-1: CB2 control
    /// Bit 0: CB1 edge (0=negative, 1=positive)
    /// Bit 7-5: CA2 control
    /// Bit 4: CA1 edge (0=negative, 1=positive)
    public var pcr: UInt8 = 0x00

    // MARK: - Interrupts

    /// Interrupt Flag Register (bit 7 = IRQ status)
    public var ifr: UInt8 = 0x00
    /// Interrupt Enable Register
    public var ier: UInt8 = 0x00

    /// IFR bit positions
    public struct IRQ {
        public static let ca2:    UInt8 = 0x01
        public static let ca1:    UInt8 = 0x02
        public static let sr:     UInt8 = 0x04
        public static let cb2:    UInt8 = 0x08
        public static let cb1:    UInt8 = 0x10
        public static let timer2: UInt8 = 0x20
        public static let timer1: UInt8 = 0x40
        public static let any:    UInt8 = 0x80
    }

    /// Callback when interrupt state changes
    public var onInterrupt: ((Bool) -> Void)?

    /// Callback when port B is written (used by Drive1541 to update bus immediately)
    public var onPortBWrite: (() -> Void)?

    // MARK: - Handshake lines

    /// CA1 input line state (directly sampled)
    public var ca1: Bool = false
    private var ca1Prev: Bool = false

    /// CA2 input line state
    public var ca2: Bool = false
    private var ca2Prev: Bool = false

    /// CB1 input line state
    public var cb1: Bool = false
    private var cb1Prev: Bool = false

    /// CB2 input line state
    public var cb2: Bool = false
    private var cb2Prev: Bool = false

    // MARK: - Init

    public init() {}

    // MARK: - Tick

    public func tick() {
        // Timer 1
        if timer1Counter == 0 {
            if !timer1Fired {
                setIFR(IRQ.timer1)
                timer1Fired = true
            }
            let t1FreeRun = acr & 0x40 != 0
            if t1FreeRun {
                timer1Counter = timer1Latch
                timer1Fired = false  // Allow re-interrupt in free-run mode
            }
        } else {
            timer1Counter &-= 1
        }

        // Timer 2 (only counts system clocks when ACR bit 5 = 0)
        if acr & 0x20 == 0 {
            if timer2Counter == 0 {
                if !timer2Fired {
                    setIFR(IRQ.timer2)
                    timer2Fired = true
                }
            } else {
                timer2Counter &-= 1
            }
        }

        // Check handshake line edges
        checkCA1Edge()
        checkCB1Edge()
    }

    // MARK: - Handshake edge detection

    /// Debug counter for CA1 edge logging
    var ca1DebugCount = 0

    private func checkCA1Edge() {
        let positiveEdge = pcr & 0x01 != 0
        let triggered = positiveEdge ? (!ca1Prev && ca1) : (ca1Prev && !ca1)
        if ca1 != ca1Prev && ca1DebugCount < 10 {
            ca1DebugCount += 1
            let msg = "[VIA] CA1 edge: prev=\(ca1Prev) cur=\(ca1) posEdge=\(positiveEdge) triggered=\(triggered) IFR=$\(String(format:"%02X",ifr)) IER=$\(String(format:"%02X",ier))\n"
            if let data = msg.data(using: .utf8),
               let fh = FileHandle(forWritingAtPath: "/tmp/c64_debug.log") {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        }
        if triggered {
            setIFR(IRQ.ca1)
        }
        ca1Prev = ca1
    }

    private func checkCB1Edge() {
        let positiveEdge = pcr & 0x10 != 0
        let triggered = positiveEdge ? (!cb1Prev && cb1) : (cb1Prev && !cb1)
        if triggered {
            setIFR(IRQ.cb1)
        }
        cb1Prev = cb1
    }

    // MARK: - Interrupt management

    func setIFR(_ flag: UInt8) {
        ifr |= flag
        updateIRQ()
    }

    func clearIFR(_ flag: UInt8) {
        ifr &= ~flag
        updateIRQ()
    }

    func updateIRQ() {
        if ifr & ier & 0x7F != 0 {
            ifr |= IRQ.any
        } else {
            ifr &= ~IRQ.any
        }
        onInterrupt?(ifr & IRQ.any != 0)
    }

    // MARK: - Register access

    public func readRegister(_ reg: UInt16) -> UInt8 {
        switch reg & 0x0F {
        case 0x00:  // ORB/IRB - Port B
            clearIFR(IRQ.cb1 | IRQ.cb2)
            return (portB & ddrb) | (portBInput & ~ddrb)

        case 0x01:  // ORA/IRA - Port A (with handshake)
            clearIFR(IRQ.ca1 | IRQ.ca2)
            return (portA & ddra) | (portAInput & ~ddra)

        case 0x02: return ddrb
        case 0x03: return ddra

        case 0x04:  // T1C-L (reading clears T1 interrupt)
            clearIFR(IRQ.timer1)
            return UInt8(timer1Counter & 0xFF)

        case 0x05: return UInt8(timer1Counter >> 8)
        case 0x06: return UInt8(timer1Latch & 0xFF)
        case 0x07: return UInt8(timer1Latch >> 8)

        case 0x08:  // T2C-L (reading clears T2 interrupt)
            clearIFR(IRQ.timer2)
            return UInt8(timer2Counter & 0xFF)

        case 0x09: return UInt8(timer2Counter >> 8)

        case 0x0A: return shiftRegister
        case 0x0B: return acr
        case 0x0C: return pcr
        case 0x0D: return ifr
        case 0x0E: return ier | 0x80  // Bit 7 always reads as 1

        case 0x0F:  // ORA - Port A (no handshake)
            return (portA & ddra) | (portAInput & ~ddra)

        default: return 0
        }
    }

    public func writeRegister(_ reg: UInt16, value: UInt8) {
        switch reg & 0x0F {
        case 0x00:  // ORB - Port B
            portB = value
            clearIFR(IRQ.cb1 | IRQ.cb2)
            onPortBWrite?()

        case 0x01:  // ORA - Port A (with handshake)
            portA = value
            clearIFR(IRQ.ca1 | IRQ.ca2)

        case 0x02:
            ddrb = value
            onPortBWrite?()
        case 0x03: ddra = value

        case 0x04:  // T1L-L (write to latch low)
            timer1Latch = (timer1Latch & 0xFF00) | UInt16(value)

        case 0x05:  // T1C-H (write starts timer)
            timer1Latch = (timer1Latch & 0x00FF) | (UInt16(value) << 8)
            timer1Counter = timer1Latch
            timer1Fired = false
            clearIFR(IRQ.timer1)

        case 0x06:  // T1L-L
            timer1Latch = (timer1Latch & 0xFF00) | UInt16(value)

        case 0x07:  // T1L-H (write to latch high, no timer start)
            timer1Latch = (timer1Latch & 0x00FF) | (UInt16(value) << 8)
            clearIFR(IRQ.timer1)

        case 0x08:  // T2L-L (write to latch)
            timer2LatchLow = value

        case 0x09:  // T2C-H (write starts timer)
            timer2Counter = UInt16(timer2LatchLow) | (UInt16(value) << 8)
            timer2Fired = false
            clearIFR(IRQ.timer2)

        case 0x0A: shiftRegister = value
        case 0x0B: acr = value
        case 0x0C: pcr = value

        case 0x0D:  // IFR - write 1 to clear flags
            ifr &= ~(value & 0x7F)
            updateIRQ()

        case 0x0E:  // IER - bit 7: 1=set, 0=clear the bits specified
            if value & 0x80 != 0 {
                ier |= (value & 0x7F)
            } else {
                ier &= ~(value & 0x7F)
            }
            updateIRQ()

        case 0x0F:  // ORA (no handshake)
            portA = value

        default: break
        }
    }
}
