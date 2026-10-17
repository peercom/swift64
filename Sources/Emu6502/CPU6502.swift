/// Cycle-accurate MOS 6502 CPU emulator.
///
/// Call `tick()` once per system clock cycle. The CPU communicates with the
/// outside world exclusively through the `Bus` protocol.
///
/// Each tick() performs exactly ONE bus read or write operation.
public final class CPU6502 {

    // MARK: - Registers

    /// Accumulator
    public var a: UInt8 = 0
    /// X index register
    public var x: UInt8 = 0
    /// Y index register
    public var y: UInt8 = 0
    /// Stack pointer (offset from $0100)
    public var sp: UInt8 = 0xFD
    /// Program counter
    public var pc: UInt16 = 0
    /// Processor status register
    public var p: UInt8 = Flags.unused | Flags.interrupt

    // MARK: - Bus

    /// The address/data bus this CPU is connected to.
    public let bus: Bus

    // MARK: - Interrupt lines

    /// IRQ line state (active low / level-sensitive). Set to `true` to assert.
    public var irqLine: Bool = false

    /// RDY input line state. When low, the NMOS 6502 pauses on read cycles
    /// while allowing write cycles already in progress to complete.
    public private(set) var rdyLine: Bool = true

    /// Total number of cycles executed since reset.
    public private(set) var totalCycles: UInt64 = 0

    /// Whether the CPU is jammed (KIL/JAM opcode encountered).
    public internal(set) var jammed: Bool = false

    // MARK: - Internal state

    /// Current opcode being executed.
    var opcode: UInt8 = 0

    /// Cycle within current instruction (0 = fetch).
    public var cycle: Int = 0

    /// Intermediate address register used during addressing mode resolution.
    var addr: UInt16 = 0

    /// Intermediate data value.
    var data: UInt8 = 0

    /// Base address before index addition (for page-crossing detection).
    var baseAddr: UInt16 = 0

    /// Pointer byte for indirect addressing.
    var pointer: UInt8 = 0

    /// Whether the current instruction needs an extra cycle for page crossing.
    var pageCrossed: Bool = false

    /// Compatibility shim for KernalTraps — always 0 in per-cycle mode.
    public var pendingCycles: Int {
        get { return 0 }
        set { /* no-op for compatibility */ }
    }

    /// Pending NMI (edge-detected).
    var nmiPending: Bool = false
    /// Previous NMI line state for edge detection.
    var nmiLinePrev: Bool = false
    /// NMI line state.
    public var nmiLine: Bool = false

    /// Whether we're currently servicing an interrupt sequence.
    public var servicingInterrupt: Bool = false

    /// Type of interrupt currently being serviced.
    enum InterruptKind {
        case none
        case nmi
        case irq
        case reset
    }
    var interruptType: InterruptKind = .none

    /// IRQ eligibility at the preceding clock, and the instruction's committed
    /// poll result. Most instructions poll the pin at their penultimate cycle.
    private var irqSample = false
    private var irqPending = false
    private var nmiSample = false
    private var nmiPolled = false

    /// Vector selected for the current BRK/IRQ/NMI/RESET sequence.
    var interruptVectorAddress: UInt16 = Vector.irq

    /// A late NMI that arrives after the low vector byte was fetched must not
    /// half-hijack the high vector byte; service it after one handler opcode.
    var deferNMIUntilAfterNextInstruction = false

    var resetPending: Bool = false

    // MARK: - Init

    public init(bus: Bus) {
        self.bus = bus
    }

    // MARK: - Public API

    /// Trigger a hardware reset. Takes effect at the next instruction boundary.
    public func reset() {
        jammed = false
        servicingInterrupt = false
        interruptType = .none
        irqSample = false
        irqPending = false
        nmiSample = false
        nmiPolled = false
        interruptVectorAddress = Vector.irq
        deferNMIUntilAfterNextInstruction = false
        cycle = 0
        rdyLine = true
        nmiPending = false
        nmiLinePrev = nmiLine
        resetPending = true
    }

    /// Trigger an NMI. Edge-detected: only triggers on low→high transition.
    public func triggerNMI() {
        setNMILine(high: true)
        setNMILine(high: false)
    }

    /// Set the NMI input line level. A low→high transition is latched and
    /// serviced after an instruction polls the edge detector.
    public func setNMILine(high: Bool) {
        if high && !nmiLine {
            if protectsLateNMIVectorHijack {
                deferNMIUntilAfterNextInstruction = true
                nmiLinePrev = true
            } else {
                nmiPending = true
            }
        }
        nmiLine = high
    }

    /// Pulse the NMOS 6502 SO input.
    ///
    /// The 1541 read hardware uses SO to set the overflow flag when a byte is
    /// ready. Modeling this as a named CPU input keeps drive code from reaching
    /// into status-register internals directly.
    public func pulseSO() {
        setFlag(Flags.overflow, true)
    }

    /// Set the RDY input line level. Low stalls the CPU on the next read cycle.
    public func setRDYLine(high: Bool) {
        rdyLine = high
    }

    /// Execute exactly one clock cycle.
    @discardableResult
    public func tick(busAvailable: Bool = true) -> Bool {
        guard !jammed else { return false }
        totalCycles += 1
        // Bus reads/writes may acknowledge an IRQ after this cycle's pin
        // sample. Preserve that sample without changing I-flag timing.
        let irqAtCycleStart = irqLine
        defer {
            irqSample = irqAtCycleStart && !getFlag(Flags.interrupt)
            nmiSample = nmiPending
        }

        if !rdyLine && currentCycleIsRead() {
            // RDY holds the microcycle, not the memory pins. The C64 may also
            // tri-state those pins with AEC while the VIC owns the shared bus.
            if busAvailable { _ = bus.read(currentReadAddress()) }
            return true
        }

        if servicingInterrupt {
            executeInterruptCycle()
            return true
        }

        if cycle == 0 {
            // Check for pending interrupts at instruction boundary
            detectNMIEdge()
            let takeIRQ = irqPending
            let takeNMI = nmiPolled && nmiPending
            irqPending = false
            nmiPolled = false

            if resetPending {
                resetPending = false
                beginInterrupt(.reset)
                return true
            } else if deferNMIUntilAfterNextInstruction {
                deferNMIUntilAfterNextInstruction = false
                if nmiLine {
                    nmiPending = true
                    nmiLinePrev = true
                }
            } else if takeNMI {
                acknowledgePendingNMI()
                beginInterrupt(.nmi)
                return true
            } else if takeIRQ {
                beginInterrupt(.irq)
                return true
            }

            // Fetch opcode
            opcode = bus.read(pc)
            pc &+= 1
            cycle = 1
        } else {
            let previousCycle = cycle
            executeCycle()
            if CPU6502.templateTable[Int(opcode)] == .branch {
                // Branches poll on their offset cycle, not the final dummy
                // cycle of a same-page taken branch. A page fixup polls again.
                if previousCycle == 1 {
                    irqPending = irqSample
                    nmiPolled = nmiSample
                }
                if previousCycle == 3 {
                    irqPending = irqPending || irqSample
                    nmiPolled = nmiPolled || nmiSample
                }
            } else if cycle == 0 {
                irqPending = irqSample
                nmiPolled = nmiSample
            }
        }

        return true
    }

    /// Run the CPU for a given number of cycles.
    public func run(cycles: Int) {
        for _ in 0..<cycles {
            if !tick() { break }
        }
    }

    /// Perform a full reset sequence (7 cycles) immediately.
    public func powerOn() {
        resetPending = false
        sp = 0xFD
        p = Flags.unused | Flags.interrupt
        let lo = UInt16(bus.read(Vector.reset))
        let hi = UInt16(bus.read(Vector.reset + 1))
        pc = (hi << 8) | lo
        cycle = 0
        totalCycles = 7
        jammed = false
        servicingInterrupt = false
        interruptType = .none
        irqSample = false
        irqPending = false
        nmiSample = false
        nmiPolled = false
        interruptVectorAddress = Vector.irq
        deferNMIUntilAfterNextInstruction = false
        rdyLine = true
        nmiPending = false
        nmiLinePrev = nmiLine
    }

    // MARK: - Flag helpers

    public func getFlag(_ flag: UInt8) -> Bool {
        return (p & flag) != 0
    }

    public func setFlag(_ flag: UInt8, _ value: Bool) {
        if value {
            p |= flag
        } else {
            p &= ~flag
        }
    }

    func setZN(_ value: UInt8) {
        setFlag(Flags.zero, value == 0)
        setFlag(Flags.negative, value & 0x80 != 0)
    }

    // MARK: - Interrupts

    func detectNMIEdge() {
        if nmiLine && !nmiLinePrev {
            nmiPending = true
        }
        nmiLinePrev = nmiLine
    }

    var protectsLateNMIVectorHijack: Bool {
        if servicingInterrupt && interruptType == .irq && cycle == 6 {
            return true
        }
        return !servicingInterrupt && opcode == 0x00 && cycle == 6
    }

    func acknowledgePendingNMI() {
        nmiPending = false
        nmiSample = false
        nmiPolled = false
        nmiLinePrev = nmiLine
    }

    /// Begin an interrupt sequence. This consumes the current cycle (cycle 0)
    /// and sets up the per-cycle interrupt state machine.
    func beginInterrupt(_ type: InterruptKind) {
        servicingInterrupt = true
        interruptType = type
        switch type {
        case .nmi: interruptVectorAddress = Vector.nmi
        case .irq: interruptVectorAddress = Vector.irq
        case .reset: interruptVectorAddress = Vector.reset
        case .none: interruptVectorAddress = Vector.irq
        }
        // Cycle 0 of interrupt: dummy read (this tick)
        _ = bus.read(pc)
        cycle = 1
    }

    /// Begin interrupt sequence for cycle 1-6 (called from executeInterruptCycle in Instructions.swift)
    // executeInterruptCycle is in Instructions.swift
}

// MARK: - CPU state

extension CPU6502 {
    /// Stored properties serialized below; `MachineStateTests` checks the count.
    public static let snapshotStoredPropertyCount = 30

    public func saveState(to w: inout StateWriter) {
        w.write(a); w.write(x); w.write(y); w.write(sp); w.write(pc); w.write(p)
        w.write(irqLine); w.write(rdyLine); w.write(totalCycles); w.write(jammed)
        w.write(opcode); w.write(cycle); w.write(addr); w.write(data); w.write(baseAddr)
        w.write(pointer); w.write(pageCrossed)
        w.write(nmiPending); w.write(nmiLinePrev); w.write(nmiLine); w.write(servicingInterrupt)
        w.write(interruptType.snapshotValue)
        w.write(irqSample); w.write(irqPending); w.write(nmiSample); w.write(nmiPolled)
        w.write(interruptVectorAddress); w.write(deferNMIUntilAfterNextInstruction); w.write(resetPending)
    }

    public func restoreState(from r: inout StateReader) throws {
        a = try r.read(); x = try r.read(); y = try r.read(); sp = try r.read(); pc = try r.read(); p = try r.read()
        irqLine = try r.read(); rdyLine = try r.read(); totalCycles = try r.read(); jammed = try r.read()
        opcode = try r.read(); cycle = try r.read(); addr = try r.read(); data = try r.read(); baseAddr = try r.read()
        pointer = try r.read(); pageCrossed = try r.read()
        nmiPending = try r.read(); nmiLinePrev = try r.read(); nmiLine = try r.read(); servicingInterrupt = try r.read()
        interruptType = try InterruptKind(snapshotValue: try r.read())
        irqSample = try r.read(); irqPending = try r.read(); nmiSample = try r.read(); nmiPolled = try r.read()
        interruptVectorAddress = try r.read(); deferNMIUntilAfterNextInstruction = try r.read(); resetPending = try r.read()
    }
}

extension CPU6502.InterruptKind {
    var snapshotValue: UInt8 {
        switch self {
        case .none: return 0
        case .nmi: return 1
        case .irq: return 2
        case .reset: return 3
        }
    }

    init(snapshotValue: UInt8) throws {
        switch snapshotValue {
        case 0: self = .none
        case 1: self = .nmi
        case 2: self = .irq
        case 3: self = .reset
        default: throw MachineStateError.invalidValue("CPU interrupt kind")
        }
    }
}
