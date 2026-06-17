import Foundation

/// MOS 6526 CIA (Complex Interface Adapter) emulation.
/// Two instances: CIA1 ($DC00, IRQ) and CIA2 ($DD00, NMI).
public final class CIA {
    static let palCyclesPerTodTenth = 98_525
    public var cyclesPerTodTenth = CIA.palCyclesPerTodTenth
    public var tod50HzCyclesPerTenth = CIA.palCyclesPerTodTenth
    public var tod60HzCyclesPerTenth = Int((Double(CIA.palCyclesPerTodTenth) * 6.0 / 5.0).rounded())

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
        var value = (portB & ddrb) | (~ddrb & 0xFF)
        if timerAControl & 0x02 != 0 {
            value = setBit(value, bit: 6, high: timerAOutputPBHigh)
        }
        if timerBControl & 0x02 != 0 {
            value = setBit(value, bit: 7, high: timerBOutputPBHigh)
        }
        return value
    }

    // MARK: - Timers

    /// Timer A current value
    public var timerA: UInt16 = 0xFFFF
    /// Timer A latch (reload value)
    public var timerALatch: UInt16 = 0xFFFF
    /// Timer A control register
    public var timerAControl: UInt8 = 0x00
    /// Latched high byte captured by reading Timer A low.
    var timerAHighLatched: UInt8?
    /// Timer A output state used when CRA routes timer output to PB6.
    var timerAOutputHigh: Bool = false
    /// Remaining visible cycles for Timer A pulse output on PB6.
    var timerAPulseCyclesRemaining: Int = 0

    /// Timer B current value
    public var timerB: UInt16 = 0xFFFF
    /// Timer B latch
    public var timerBLatch: UInt16 = 0xFFFF
    /// Timer B control register
    public var timerBControl: UInt8 = 0x00
    /// Latched high byte captured by reading Timer B low.
    var timerBHighLatched: UInt8?
    /// Timer B output state used when CRB routes timer output to PB7.
    var timerBOutputHigh: Bool = false
    /// Remaining visible cycles for Timer B pulse output on PB7.
    var timerBPulseCyclesRemaining: Int = 0

    // MARK: - Interrupt

    /// Interrupt control mask (which sources are enabled)
    public var interruptMask: UInt8 = 0x00
    /// Interrupt control data (which sources have fired)
    public var interruptData: UInt8 = 0x00

    /// Whether this CIA's interrupt line is active
    public var interruptActive: Bool = false

    /// Current external FLAG pin level. The CIA latches interrupt source 4 on a falling edge.
    var flagLineHigh: Bool = true
    /// Current external CNT pin level, used by Timer B's Timer A-underflow + CNT mode.
    var cntLineHigh: Bool = true

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
    var todCycleCount: Int = 0
    var todStoppedForWrite: Bool = false

    // MARK: - Keyboard matrix (CIA1 only)

    /// 8×8 keyboard matrix. Each byte represents a row.
    /// Bit = 0 means key pressed.
    public var keyboardMatrix = [UInt8](repeating: 0xFF, count: 8)

    /// Joystick port 1 (CIA1 port B, $DC01)
    /// Bits: 0=Up, 1=Down, 2=Left, 3=Right, 4=Fire (active low)
    public var joystickPort1: UInt8 = 0xFF

    /// Joystick port 2 (CIA1 port A, $DC00)
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

    // MARK: - Serial port

    /// Serial data register ($DC0C/$DD0C).
    var serialData: UInt8 = 0
    /// Current external/output SP pin level.
    public private(set) var spLineHigh: Bool = true
    var serialInputShift: UInt8 = 0
    var serialInputBitsReceived: Int = 0
    var serialOutputShift: UInt8 = 0
    var serialOutputBitsRemaining: Int = 0

    // MARK: - Init

    public init(isCIA1: Bool) {
        self.isCIA1 = isCIA1
    }

    public func configureTOD(
        fiftyHzCyclesPerTenth: Int,
        sixtyHzCyclesPerTenth: Int,
        selectedCyclesPerTenth: Int
    ) {
        tod50HzCyclesPerTenth = fiftyHzCyclesPerTenth
        tod60HzCyclesPerTenth = sixtyHzCyclesPerTenth
        cyclesPerTodTenth = selectedCyclesPerTenth
        todCycleCount = 0
    }

    // MARK: - Tick

    /// Advance one system clock cycle.
    public func tick() {
        expireTimerOutputPulses()

        // Timer A
        if timerAControl & 0x01 != 0 {
            let countSource = timerAControl & 0x20  // bit 5: 0=system clock, 1=CNT pin
            if countSource == 0 {
                countTimerA()
            }
        }

        // Timer B
        if timerBControl & 0x01 != 0 {
            let countSource = timerBControl & 0x60
            if countSource == 0 {
                // Count system clock
                countTimerB()
            }
            // countSource == 0x40: count timer A underflows (handled in timerAUnderflow)
        }

        tickTOD()
    }

    func timerAUnderflow() {
        updateTimerAOutput()
        shiftSerialOutputBit()

        // Set interrupt flag
        interruptData |= 0x01
        checkInterrupt()

        // Reload or stop
        if timerAControl & 0x08 != 0 {
            // One-shot: stop timer
            timerAControl &= ~0x01
        }
        timerA = timerALatch

        if timerBCountsTimerAUnderflows {
            if timerB == 0 {
                timerBUnderflow()
            } else {
                timerB &-= 1
            }
        }
    }

    func timerBUnderflow() {
        updateTimerBOutput()

        interruptData |= 0x02
        checkInterrupt()

        if timerBControl & 0x08 != 0 {
            timerBControl &= ~0x01
        }
        timerB = timerBLatch
    }

    var timerBCountsTimerAUnderflows: Bool {
        guard timerBControl & 0x01 != 0 else { return false }

        switch timerBControl & 0x60 {
        case 0x40: return true
        case 0x60: return cntLineHigh
        default: return false
        }
    }

    func checkInterrupt() {
        let wasActive = interruptActive
        let isActive = (interruptData & interruptMask & 0x1F) != 0

        if isActive {
            interruptData |= 0x80  // Set IR bit
            interruptActive = true
            if !wasActive {
                onInterrupt?(true)
            }
        } else {
            interruptData &= 0x7F
            interruptActive = false
            if wasActive {
                onInterrupt?(false)
            }
        }
    }

    public func setFlagLine(high: Bool) {
        if flagLineHigh && !high {
            interruptData |= 0x10
            checkInterrupt()
        }
        flagLineHigh = high
    }

    public func setCNTLine(high: Bool) {
        cntLineHigh = high
    }

    public func setSPLine(high: Bool) {
        spLineHigh = high
    }

    public func pulseCNT() {
        if timerAControl & 0x01 != 0 && timerAControl & 0x20 != 0 {
            countTimerA()
        }

        if timerBControl & 0x01 != 0 && timerBControl & 0x60 == 0x20 {
            countTimerB()
        }

        shiftSerialInputBit()
    }

    func countTimerA() {
        if timerA == 0 {
            timerAUnderflow()
        } else {
            timerA &-= 1
        }
    }

    func countTimerB() {
        if timerB == 0 {
            timerBUnderflow()
        } else {
            timerB &-= 1
        }
    }

    var timerAOutputPBHigh: Bool {
        timerAControl & 0x04 != 0 ? timerAOutputHigh : timerAPulseCyclesRemaining > 0
    }

    var timerBOutputPBHigh: Bool {
        timerBControl & 0x04 != 0 ? timerBOutputHigh : timerBPulseCyclesRemaining > 0
    }

    func updateTimerAOutput() {
        if timerAControl & 0x04 != 0 {
            timerAOutputHigh.toggle()
        } else {
            timerAPulseCyclesRemaining = 1
        }
    }

    func updateTimerBOutput() {
        if timerBControl & 0x04 != 0 {
            timerBOutputHigh.toggle()
        } else {
            timerBPulseCyclesRemaining = 1
        }
    }

    func expireTimerOutputPulses() {
        if timerAPulseCyclesRemaining > 0 {
            timerAPulseCyclesRemaining -= 1
        }
        if timerBPulseCyclesRemaining > 0 {
            timerBPulseCyclesRemaining -= 1
        }
    }

    var serialOutputMode: Bool {
        timerAControl & 0x40 != 0
    }

    func shiftSerialInputBit() {
        guard !serialOutputMode else { return }

        serialInputShift = (serialInputShift << 1) | (spLineHigh ? 1 : 0)
        serialInputBitsReceived += 1

        if serialInputBitsReceived == 8 {
            serialData = serialInputShift
            serialInputShift = 0
            serialInputBitsReceived = 0
            interruptData |= 0x08
            checkInterrupt()
        }
    }

    func shiftSerialOutputBit() {
        guard serialOutputMode, serialOutputBitsRemaining > 0 else { return }

        spLineHigh = serialOutputShift & 0x80 != 0
        serialOutputShift <<= 1
        serialOutputBitsRemaining -= 1

        if serialOutputBitsRemaining == 0 {
            interruptData |= 0x08
            checkInterrupt()
        }
    }

    func updateTODFrequencyFromControl() {
        let selectedCycles = timerAControl & 0x80 != 0
            ? tod50HzCyclesPerTenth
            : tod60HzCyclesPerTenth
        if cyclesPerTodTenth != selectedCycles {
            cyclesPerTodTenth = selectedCycles
            todCycleCount = 0
        }
    }

    func setBit(_ value: UInt8, bit: Int, high: Bool) -> UInt8 {
        let mask = UInt8(1 << bit)
        return high ? (value | mask) : (value & ~mask)
    }

    func tickTOD() {
        guard !todStoppedForWrite else { return }

        todCycleCount += 1
        guard todCycleCount >= cyclesPerTodTenth else { return }

        todCycleCount -= cyclesPerTodTenth
        incrementTODTenth()
    }

    func incrementTODTenth() {
        todTenths &+= 1
        if todTenths < 10 {
            checkTODAlarm()
            return
        }

        todTenths = 0
        incrementTODSeconds()
        checkTODAlarm()
    }

    func incrementTODSeconds() {
        todSeconds = incrementBCD(todSeconds, wrappingAt: 0x60)
        if todSeconds == 0 {
            incrementTODMinutes()
        }
    }

    func incrementTODMinutes() {
        todMinutes = incrementBCD(todMinutes, wrappingAt: 0x60)
        if todMinutes == 0 {
            incrementTODHours()
        }
    }

    func incrementTODHours() {
        let pm = todHours & 0x80
        let hour = todHours & 0x1F

        switch hour {
        case 0x00:
            todHours = pm | 0x01
        case 0x11:
            todHours = (pm ^ 0x80) | 0x12
        case 0x12:
            todHours = pm | 0x01
        default:
            todHours = pm | incrementBCD(hour == 0 ? 1 : hour, wrappingAt: 0x13)
        }
    }

    func incrementBCD(_ value: UInt8, wrappingAt limit: UInt8) -> UInt8 {
        var next = value &+ 1
        if next & 0x0F >= 0x0A {
            next = (next & 0xF0) &+ 0x10
        }
        return next >= limit ? 0 : next
    }

    func checkTODAlarm() {
        guard todTenths == todAlarmTenths,
              todSeconds == todAlarmSeconds,
              todMinutes == todAlarmMinutes,
              todHours == todAlarmHours else { return }

        interruptData |= 0x04
        checkInterrupt()
    }

    // MARK: - Register access

    public func readRegister(_ reg: UInt16) -> UInt8 {
        switch reg {
        case 0x00:  // Port A
            if isCIA1 {
                return readKeyboardPortA() & joystickPort2
            }
            // CIA2: output bits from portA, input bits from external (IEC bus)
            let external = readPortAExternal?() ?? 0xFF
            return (portA & ddra) | (external & ~ddra)

        case 0x01:  // Port B
            if isCIA1 {
                return readKeyboardPortB() & joystickPort1
            }
            return portBOut

        case 0x02: return ddra
        case 0x03: return ddrb
        case 0x04:
            timerAHighLatched = UInt8(timerA >> 8)
            return UInt8(timerA & 0xFF)
        case 0x05:
            if let latched = timerAHighLatched {
                timerAHighLatched = nil
                return latched
            }
            return UInt8(timerA >> 8)
        case 0x06:
            timerBHighLatched = UInt8(timerB >> 8)
            return UInt8(timerB & 0xFF)
        case 0x07:
            if let latched = timerBHighLatched {
                timerBHighLatched = nil
                return latched
            }
            return UInt8(timerB >> 8)

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
            if todLatched {
                return todLatchHours
            }
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
            let wasActive = interruptActive
            interruptActive = false
            if wasActive {
                onInterrupt?(false)
            }
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
            onPortAWrite?(portA)
        case 0x01: portB = value
        case 0x02:
            ddra = value
            onPortAWrite?(portA)  // DDR change affects output
        case 0x03: ddrb = value
        case 0x04: timerALatch = (timerALatch & 0xFF00) | UInt16(value)
        case 0x05:
            timerALatch = (timerALatch & 0x00FF) | (UInt16(value) << 8)
            timerAHighLatched = nil
            // If timer stopped, load latch into timer
            if timerAControl & 0x01 == 0 {
                timerA = timerALatch
            }
        case 0x06: timerBLatch = (timerBLatch & 0xFF00) | UInt16(value)
        case 0x07:
            timerBLatch = (timerBLatch & 0x00FF) | (UInt16(value) << 8)
            timerBHighLatched = nil
            if timerBControl & 0x01 == 0 {
                timerB = timerBLatch
            }

        // TOD
        case 0x08:
            if todWriteAlarm { todAlarmTenths = value & 0x0F }
            else {
                todTenths = value & 0x0F
                todCycleCount = 0
                todStoppedForWrite = false
            }
        case 0x09:
            if todWriteAlarm { todAlarmSeconds = value & 0x7F }
            else { todSeconds = value & 0x7F }
        case 0x0A:
            if todWriteAlarm { todAlarmMinutes = value & 0x7F }
            else { todMinutes = value & 0x7F }
        case 0x0B:
            if todWriteAlarm { todAlarmHours = value & 0x9F }
            else {
                todHours = value & 0x9F
                todStoppedForWrite = true
            }

        case 0x0C:
            serialData = value
            serialOutputShift = value
            serialOutputBitsRemaining = serialOutputMode ? 8 : 0

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
            let startRisingEdge = timerAControl & 0x01 == 0 && value & 0x01 != 0
            timerAControl = value & ~0x10  // bit 4 is strobe only
            updateTODFrequencyFromControl()
            if startRisingEdge {
                timerAOutputHigh = true
                timerAPulseCyclesRemaining = 0
            }
            if forceLoad {
                timerA = timerALatch
                timerAHighLatched = nil
            }

        case 0x0F:
            let forceLoad = value & 0x10 != 0
            let startRisingEdge = timerBControl & 0x01 == 0 && value & 0x01 != 0
            todWriteAlarm = (value & 0x80) != 0
            timerBControl = value & ~0x10
            if startRisingEdge {
                timerBOutputHigh = true
                timerBPulseCyclesRemaining = 0
            }
            if forceLoad {
                timerB = timerBLatch
                timerBHighLatched = nil
            }

        default: break
        }
    }

    // MARK: - Keyboard matrix scanning

    /// Read keyboard from Port A. This supports the less common reverse scan:
    /// Port B drives columns, Port A reads rows.
    func readKeyboardPortA() -> UInt8 {
        let columnSelect = portBOut
        var result = portAOut

        for row in 0..<8 {
            for column in 0..<8 where columnSelect & (1 << column) == 0 {
                if keyboardMatrix[row] & (1 << column) == 0 {
                    result &= ~(1 << row)
                }
            }
        }

        return result
    }

    /// Read keyboard from Port B. Port A drives rows, Port B reads columns.
    /// When a row bit in Port A is 0, all pressed keys in that row show as 0 in Port B.
    func readKeyboardPortB() -> UInt8 {
        let rowSelect = portAOut
        var result = portBOut

        // For each row that is selected (driven low), OR in the pressed keys
        for row in 0..<8 {
            if rowSelect & (1 << row) == 0 {
                result &= keyboardMatrix[row]
            }
        }

        return result
    }
}
