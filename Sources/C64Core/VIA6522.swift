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
    /// Optional input latches captured by CA1/CB1 active edges when enabled in ACR.
    var portAInputLatch: UInt8?
    var portBInputLatch: UInt8?

    /// Effective output of port A (output bits from register, input bits from external)
    public var portAOut: UInt8 {
        (portA & ddra) | (portAInput & ~ddra)
    }

    /// Effective output of port B
    public var portBOut: UInt8 {
        portBValue(input: portBInput)
    }

    private var portAReadValue: UInt8 {
        (portA & ddra) | ((portAInputLatch ?? portAInput) & ~ddra)
    }

    private var portBReadValue: UInt8 {
        portBValue(input: portBInputLatch ?? portBInput)
    }

    // MARK: - Timers

    /// Timer 1 counter
    public var timer1Counter: UInt16 = 0xFFFF
    /// Timer 1 latch
    public var timer1Latch: UInt16 = 0xFFFF
    /// Timer 1 has fired (one-shot mode: prevents re-interrupt)
    var timer1Fired: Bool = false
    /// Pending Timer 1 IRQ (delayed by 1 cycle to match VICE)
    var pendingT1IRQ: Bool = false
    /// Latched high byte captured by reading Timer 1 low.
    var timer1HighLatched: UInt8?
    /// Timer 1 output state when ACR routes Timer 1 to PB7.
    var timer1PB7OutputHigh: Bool = false

    /// Timer 2 counter
    public var timer2Counter: UInt16 = 0xFFFF
    /// Timer 2 latch low byte (only low byte is latched)
    var timer2LatchLow: UInt8 = 0xFF
    /// Timer 2 has fired
    var timer2Fired: Bool = false
    /// Latched high byte captured by reading Timer 2 low.
    var timer2HighLatched: UInt8?
    /// Current PB6 pulse input level for Timer 2 pulse-count mode.
    var pb6LineHigh: Bool = true

    // MARK: - Shift register

    var shiftRegister: UInt8 = 0x00
    var shiftRegisterBitCount: Int = 0
    var shiftRegisterPhi2Active: Bool = false
    var shiftRegisterTimer2Active: Bool = false
    var shiftRegisterTimer2Counter: UInt8 = 0xFF

    // MARK: - Control registers

    /// Auxiliary Control Register
    /// Bit 7-6: Timer 1 control (00=one-shot, 01=free-run, 10=one-shot+PB7, 11=free-run+PB7)
    /// Bit 5: Timer 2 control (0=timed, 1=count PB6 pulses)
    /// Bit 4-2: Shift register control
    /// Bit 1: Port B latch enable
    /// Bit 0: Port A latch enable
    public var acr: UInt8 = 0x00

    /// Peripheral Control Register
    /// Bit 3-1: CA2 control
    /// Bit 0: CB1 edge (0=negative, 1=positive)
    /// Bit 7-5: CB2 control
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

    /// Callback when effective port A output may have changed.
    public var onPortAWrite: (() -> Void)?

    /// Callback when port B is written (used by Drive1541 to update bus immediately)
    public var onPortBWrite: (() -> Void)?

    /// Callback when CA2 output state changes (used by Drive1541 for byte-ready gating).
    public var onCA2Change: ((Bool) -> Void)?

    /// Callback when CB2 output state changes.
    public var onCB2Change: ((Bool) -> Void)?

    /// Callback when CB1 output clock state changes in shift-register output-clock modes.
    public var onCB1Change: ((Bool) -> Void)?

    /// Callback when port A is read (used by Drive1541 to clear byte-ready)
    public var onPortARead: (() -> Void)?

    /// CA2 output state (for output modes in PCR bits 1-3)
    public var ca2OutputState: Bool = true

    /// CB2 output state (for output modes in PCR bits 5-7)
    public var cb2OutputState: Bool = true

    /// CB1 output clock state for internally clocked shift-register modes.
    public var cb1OutputState: Bool = true

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

    public func reset() {
        portA = 0x00
        portB = 0x00
        ddra = 0x00
        ddrb = 0x00
        portAInputLatch = nil
        portBInputLatch = nil

        timer1Counter = 0xFFFF
        timer1Latch = 0xFFFF
        timer1Fired = false
        pendingT1IRQ = false
        timer1HighLatched = nil
        timer1PB7OutputHigh = false

        timer2Counter = 0xFFFF
        timer2LatchLow = 0xFF
        timer2Fired = false
        timer2HighLatched = nil
        pb6LineHigh = true

        shiftRegister = 0x00
        shiftRegisterBitCount = 0
        shiftRegisterPhi2Active = false
        shiftRegisterTimer2Active = false
        shiftRegisterTimer2Counter = 0xFF
        acr = 0x00
        pcr = 0x00
        ifr = 0x00
        ier = 0x00
        ca2OutputState = true
        cb2OutputState = true
        cb1OutputState = true

        ca1Prev = ca1
        ca2Prev = ca2
        cb1Prev = cb1
        cb2Prev = cb2
        ca1DebugCount = 0

        onInterrupt?(false)
        onPortAWrite?()
        onPortBWrite?()
        onCA2Change?(ca2OutputState)
        onCB2Change?(cb2OutputState)
        onCB1Change?(cb1OutputState)
    }

    // MARK: - Tick

    public func tick() {
        // Resolve pending Timer 1 IRQ from previous cycle (1-cycle delay per VICE)
        if pendingT1IRQ {
            pendingT1IRQ = false
            onInterrupt?(ifr & IRQ.any != 0)
        }

        // Timer 1: always counts down, IRQ on underflow (0 → FFFF)
        // Period = latch + 1 ticks; IRQ line assertion delayed 1 additional cycle.
        timer1Counter &-= 1
        if timer1Counter == 0xFFFF {
            if !timer1Fired {
                updateTimer1PB7Output()
                ifr |= IRQ.timer1
                updateIRQBit7()     // update bit 7 for correct IFR reads
                pendingT1IRQ = true // delay IRQ line assertion by 1 cycle
                if acr & 0x40 == 0 {
                    timer1Fired = true  // one-shot: prevent further interrupts
                }
            }
            // Always reload from latch (both one-shot and free-run per VICE)
            timer1Counter = timer1Latch
        }

        // Timer 2: counts system clocks when ACR bit 5 = 0, IRQ on underflow (no delay)
        if acr & 0x20 == 0 {
            countTimer2()
        }
        clockShiftRegisterTimer2()
        clockShiftRegisterPhi2()

        // Check handshake line edges
        checkCA1Edge()
        checkCA2Edge()
        checkCB1Edge()
        checkCB2Edge()
    }

    public func setPB6Line(high: Bool) {
        if pb6LineHigh && !high && acr & 0x20 != 0 {
            countTimer2()
        }
        pb6LineHigh = high
    }

    func countTimer2() {
        timer2Counter &-= 1
        if timer2Counter == 0xFFFF && !timer2Fired {
            setIFR(IRQ.timer2)  // T2: immediate, no delay
            timer2Fired = true  // one-shot: only one IRQ per T2CH write
        }
    }

    func portBValue(input: UInt8) -> UInt8 {
        var value = (portB & ddrb) | (input & ~ddrb)
        if acr & 0x80 != 0 && ddrb & 0x80 != 0 {
            value = timer1PB7OutputHigh ? (value | 0x80) : (value & 0x7F)
        }
        return value
    }

    func updateTimer1PB7Output() {
        guard acr & 0x80 != 0 else { return }

        let previousPortBOut = portBOut
        if acr & 0x40 != 0 {
            timer1PB7OutputHigh.toggle()
        } else {
            timer1PB7OutputHigh = true
        }
        notifyPortBChanged(from: previousPortBOut)
    }

    func clearTimer1PB7OutputIfActive() {
        guard acr & 0x80 != 0 else { return }

        let previousPortBOut = portBOut
        timer1PB7OutputHigh = false
        notifyPortBChanged(from: previousPortBOut)
    }

    func notifyPortBChanged(from previousValue: UInt8) {
        guard portBOut != previousValue else { return }
        onPortBWrite?()
    }

    func notifyPortAChanged(from previousValue: UInt8) {
        guard portAOut != previousValue else { return }
        onPortAWrite?()
    }

    // MARK: - Handshake edge detection

    /// Debug counter for CA1 edge logging
    var ca1DebugCount = 0

    private func checkCA1Edge() {
        let positiveEdge = pcr & 0x01 != 0
        let triggered = positiveEdge ? (!ca1Prev && ca1) : (ca1Prev && !ca1)
        if ca1 != ca1Prev && ca1DebugCount < 200 {
            ca1DebugCount += 1
            viaLog("[VIA-CA1] edge: \(ca1Prev)→\(ca1) PCR=$\(String(format:"%02X",pcr)) posEdge=\(positiveEdge) triggered=\(triggered) IER=$\(String(format:"%02X",ier)) IFR=$\(String(format:"%02X",ifr)) ca1Enabled=\(ier & IRQ.ca1 != 0)")
        }
        if triggered {
            if acr & 0x01 != 0 {
                portAInputLatch = portAInput
            }
            setIFR(IRQ.ca1)
            if ca1DebugCount < 200 {
                viaLog("[VIA-CA1] IRQ fired! IFR now=$\(String(format:"%02X",ifr)) any=\(ifr & IRQ.any != 0)")
            }
            // CA2 handshake/pulse output: set CA2 high on CA1 active edge
            let ca2Mode = (pcr >> 1) & 0x07
            if (ca2Mode == 4 || ca2Mode == 5) && !ca2OutputState {
                ca2OutputState = true
                onCA2Change?(true)
            }
        }
        ca1Prev = ca1
    }

    private func checkCB1Edge() {
        let positiveEdge = pcr & 0x10 != 0
        let triggered = positiveEdge ? (!cb1Prev && cb1) : (cb1Prev && !cb1)
        if !cb1Prev && cb1 {
            clockShiftRegisterExternalCB1()
        }
        if triggered {
            if acr & 0x02 != 0 {
                portBInputLatch = portBInput
            }
            setIFR(IRQ.cb1)
            let cb2Mode = (pcr >> 5) & 0x07
            if (cb2Mode == 4 || cb2Mode == 5) && !cb2OutputState {
                cb2OutputState = true
                onCB2Change?(true)
            }
        }
        cb1Prev = cb1
    }

    private func checkCA2Edge() {
        let mode = (pcr >> 1) & 0x07
        guard mode <= 3 else {
            ca2Prev = ca2
            return
        }

        let positiveEdge = mode & 0x02 != 0
        let triggered = positiveEdge ? (!ca2Prev && ca2) : (ca2Prev && !ca2)
        if triggered {
            setIFR(IRQ.ca2)
        }
        ca2Prev = ca2
    }

    private func checkCB2Edge() {
        let mode = (pcr >> 5) & 0x07
        guard mode <= 3 else {
            cb2Prev = cb2
            return
        }

        let positiveEdge = mode & 0x02 != 0
        let triggered = positiveEdge ? (!cb2Prev && cb2) : (cb2Prev && !cb2)
        if triggered {
            setIFR(IRQ.cb2)
        }
        cb2Prev = cb2
    }

    func shiftRegisterMode() -> UInt8 {
        (acr >> 2) & 0x07
    }

    func resetShiftRegisterCounter() {
        shiftRegisterBitCount = 0
        shiftRegisterTimer2Counter = timer2LatchLow
    }

    func beginShiftRegisterTransferIfNeeded() {
        switch shiftRegisterMode() {
        case 0x01, 0x05:
            shiftRegisterPhi2Active = false
            shiftRegisterTimer2Active = true
            shiftRegisterTimer2Counter = timer2LatchLow
        case 0x02, 0x06:
            shiftRegisterPhi2Active = true
            shiftRegisterTimer2Active = false
        case 0x04:
            shiftRegisterPhi2Active = false
            shiftRegisterTimer2Active = true
            shiftRegisterTimer2Counter = timer2LatchLow
        default:
            shiftRegisterPhi2Active = false
            shiftRegisterTimer2Active = false
        }
    }

    func clockShiftRegisterTimer2() {
        guard shiftRegisterTimer2Active else { return }

        if shiftRegisterTimer2Counter > 0 {
            shiftRegisterTimer2Counter &-= 1
            return
        }

        shiftRegisterTimer2Counter = timer2LatchLow
        switch shiftRegisterMode() {
        case 0x01:
            pulseShiftRegisterCB1OutputClock()
            shiftRegister = (shiftRegister << 1) | (cb2 ? 1 : 0)
            advanceShiftRegisterCounter(stopAfterByte: true)

        case 0x04:
            pulseShiftRegisterCB1OutputClock()
            shiftOutRegisterBitToCB2(recirculate: true)

        case 0x05:
            pulseShiftRegisterCB1OutputClock()
            shiftOutRegisterBitToCB2()
            advanceShiftRegisterCounter(stopAfterByte: true)

        default:
            shiftRegisterTimer2Active = false
        }
    }

    func clockShiftRegisterPhi2() {
        guard shiftRegisterPhi2Active else { return }

        switch shiftRegisterMode() {
        case 0x02:
            pulseShiftRegisterCB1OutputClock()
            shiftRegister = (shiftRegister << 1) | (cb2 ? 1 : 0)
            advanceShiftRegisterCounter(stopAfterByte: true)

        case 0x06:
            pulseShiftRegisterCB1OutputClock()
            shiftOutRegisterBitToCB2()
            advanceShiftRegisterCounter(stopAfterByte: true)

        default:
            shiftRegisterPhi2Active = false
        }
    }

    func clockShiftRegisterExternalCB1() {
        switch shiftRegisterMode() {
        case 0x03:
            shiftRegister = (shiftRegister << 1) | (cb2 ? 1 : 0)
            advanceShiftRegisterCounter(stopAfterByte: false)

        case 0x07:
            shiftOutRegisterBitToCB2()
            advanceShiftRegisterCounter(stopAfterByte: false)

        default:
            break
        }
    }

    func setCB1OutputState(_ state: Bool) {
        guard cb1OutputState != state else { return }
        cb1OutputState = state
        onCB1Change?(state)
    }

    func pulseShiftRegisterCB1OutputClock() {
        setCB1OutputState(false)
        setCB1OutputState(true)
    }

    func shiftOutRegisterBitToCB2(recirculate: Bool = false) {
        let nextBit = shiftRegister & 0x80 != 0
        if cb2OutputState != nextBit {
            cb2OutputState = nextBit
            onCB2Change?(nextBit)
        }
        shiftRegister = recirculate
            ? ((shiftRegister << 1) | (nextBit ? 1 : 0))
            : (shiftRegister << 1)
    }

    func advanceShiftRegisterCounter(stopAfterByte: Bool) {
        shiftRegisterBitCount += 1
        if shiftRegisterBitCount >= 8 {
            shiftRegisterBitCount = 0
            if stopAfterByte {
                shiftRegisterPhi2Active = false
                shiftRegisterTimer2Active = false
            }
            setIFR(IRQ.sr)
        }
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

    /// Update IFR bit 7 without signaling CPU (for delayed IRQ sources like T1)
    private func updateIRQBit7() {
        if ifr & ier & 0x7F != 0 {
            ifr |= IRQ.any
        } else {
            ifr &= ~IRQ.any
        }
    }

    func updateIRQ() {
        updateIRQBit7()
        onInterrupt?(ifr & IRQ.any != 0)
    }

    // MARK: - Register access

    public func readRegister(_ reg: UInt16) -> UInt8 {
        switch reg & 0x0F {
        case 0x00:  // ORB/IRB - Port B
            clearIFR(IRQ.cb1 | IRQ.cb2)
            let value = portBReadValue
            handleCB2PortBHandshakeAccess()
            portBInputLatch = nil
            return value

        case 0x01:  // ORA/IRA - Port A (with handshake)
            clearIFR(IRQ.ca1 | IRQ.ca2)
            let value = portAReadValue
            handleCA2PortAHandshakeAccess()
            onPortARead?()
            portAInputLatch = nil
            return value

        case 0x02: return ddrb
        case 0x03: return ddra

        case 0x04:  // T1C-L (reading clears T1 interrupt)
            timer1HighLatched = UInt8(timer1Counter >> 8)
            clearIFR(IRQ.timer1)
            return UInt8(timer1Counter & 0xFF)

        case 0x05:
            if let latched = timer1HighLatched {
                timer1HighLatched = nil
                return latched
            }
            return UInt8(timer1Counter >> 8)
        case 0x06: return UInt8(timer1Latch & 0xFF)
        case 0x07: return UInt8(timer1Latch >> 8)

        case 0x08:  // T2C-L (reading clears T2 interrupt)
            timer2HighLatched = UInt8(timer2Counter >> 8)
            clearIFR(IRQ.timer2)
            return UInt8(timer2Counter & 0xFF)

        case 0x09:
            if let latched = timer2HighLatched {
                timer2HighLatched = nil
                return latched
            }
            return UInt8(timer2Counter >> 8)

        case 0x0A:
            clearIFR(IRQ.sr)
            resetShiftRegisterCounter()
            beginShiftRegisterTransferIfNeeded()
            return shiftRegister
        case 0x0B: return acr
        case 0x0C: return pcr
        case 0x0D: return ifr
        case 0x0E: return ier | 0x80  // Bit 7 always reads as 1

        case 0x0F:  // ORA - Port A (no handshake)
            onPortARead?()
            return portAReadValue

        default: return 0
        }
    }

    public func writeRegister(_ reg: UInt16, value: UInt8) {
        switch reg & 0x0F {
        case 0x00:  // ORB - Port B
            portB = value
            clearIFR(IRQ.cb1 | IRQ.cb2)
            handleCB2PortBHandshakeAccess()
            onPortBWrite?()

        case 0x01:  // ORA - Port A (with handshake)
            let previousPortAOut = portAOut
            portA = value
            clearIFR(IRQ.ca1 | IRQ.ca2)
            handleCA2PortAHandshakeAccess()
            notifyPortAChanged(from: previousPortAOut)

        case 0x02:
            ddrb = value
            onPortBWrite?()
        case 0x03:
            let previousPortAOut = portAOut
            ddra = value
            notifyPortAChanged(from: previousPortAOut)

        case 0x04:  // T1L-L (write to latch low)
            timer1Latch = (timer1Latch & 0xFF00) | UInt16(value)

        case 0x05:  // T1C-H (write starts timer)
            timer1Latch = (timer1Latch & 0x00FF) | (UInt16(value) << 8)
            timer1Counter = timer1Latch
            timer1Fired = false
            pendingT1IRQ = false
            timer1HighLatched = nil
            clearTimer1PB7OutputIfActive()
            clearIFR(IRQ.timer1)

        case 0x06:  // T1L-L
            timer1Latch = (timer1Latch & 0xFF00) | UInt16(value)

        case 0x07:  // T1L-H (write to latch high, no timer start)
            timer1Latch = (timer1Latch & 0x00FF) | (UInt16(value) << 8)
            pendingT1IRQ = false
            timer1HighLatched = nil
            clearIFR(IRQ.timer1)

        case 0x08:  // T2L-L (write to latch)
            timer2LatchLow = value

        case 0x09:  // T2C-H (write starts timer)
            timer2Counter = UInt16(timer2LatchLow) | (UInt16(value) << 8)
            timer2Fired = false
            timer2HighLatched = nil
            clearIFR(IRQ.timer2)

        case 0x0A:
            shiftRegister = value
            resetShiftRegisterCounter()
            clearIFR(IRQ.sr)
            beginShiftRegisterTransferIfNeeded()
        case 0x0B:
            let previousShiftMode = shiftRegisterMode()
            let previousPortBOut = portBOut
            acr = value
            if shiftRegisterMode() != previousShiftMode {
                resetShiftRegisterCounter()
                shiftRegisterPhi2Active = false
                shiftRegisterTimer2Active = false
            }
            if shiftRegisterMode() == 0x00 {
                clearIFR(IRQ.sr)
            }
            if value & 0x01 == 0 { portAInputLatch = nil }
            if value & 0x02 == 0 { portBInputLatch = nil }
            notifyPortBChanged(from: previousPortBOut)
        case 0x0C:
            pcr = value
            // Update CA2 output state based on new PCR mode
            let ca2Mode0C = (value >> 1) & 0x07
            switch ca2Mode0C {
            case 6: // manual output low
                if ca2OutputState { ca2OutputState = false; onCA2Change?(false) }
            case 7: // manual output high
                if !ca2OutputState { ca2OutputState = true; onCA2Change?(true) }
            case 4: // handshake output: initially low
                if ca2OutputState { ca2OutputState = false; onCA2Change?(false) }
            case 5: // pulse output: normally high
                if !ca2OutputState { ca2OutputState = true; onCA2Change?(true) }
            default: break // input modes
            }
            let cb2Mode0C = (value >> 5) & 0x07
            switch cb2Mode0C {
            case 6: // manual output low
                if cb2OutputState { cb2OutputState = false; onCB2Change?(false) }
            case 7: // manual output high
                if !cb2OutputState { cb2OutputState = true; onCB2Change?(true) }
            case 4: // handshake output: initially low
                if cb2OutputState { cb2OutputState = false; onCB2Change?(false) }
            case 5: // pulse output: normally high
                if !cb2OutputState { cb2OutputState = true; onCB2Change?(true) }
            default: break // input modes
            }

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
            let previousPortAOut = portAOut
            portA = value
            notifyPortAChanged(from: previousPortAOut)

        default: break
        }
    }

    func handleCA2PortAHandshakeAccess() {
        let mode = (pcr >> 1) & 0x07
        if mode == 4 && ca2OutputState {
            ca2OutputState = false
            onCA2Change?(false)
        } else if mode == 5 {
            if ca2OutputState {
                ca2OutputState = false
                onCA2Change?(false)
            }
            ca2OutputState = true
            onCA2Change?(true)
        }
    }

    func handleCB2PortBHandshakeAccess() {
        let mode = (pcr >> 5) & 0x07
        if mode == 4 && cb2OutputState {
            cb2OutputState = false
            onCB2Change?(false)
        } else if mode == 5 {
            if cb2OutputState {
                cb2OutputState = false
                onCB2Change?(false)
            }
            cb2OutputState = true
            onCB2Change?(true)
        }
    }

    // MARK: - Debug logging

    func viaLog(_ msg: String) {
        C64Trace.log(.via, msg)
    }
}
