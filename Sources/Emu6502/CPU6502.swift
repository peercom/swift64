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

    var resetPending: Bool = false

    // MARK: - Init

    public init(bus: Bus) {
        self.bus = bus
    }

    // MARK: - Public API

    /// Trigger a hardware reset. Takes effect at the next instruction boundary.
    public func reset() {
        resetPending = true
    }

    /// Trigger an NMI. Edge-detected: only triggers on low→high transition.
    public func triggerNMI() {
        nmiLine = true
    }

    /// Execute exactly one clock cycle.
    @discardableResult
    public func tick() -> Bool {
        guard !jammed else { return false }
        totalCycles += 1

        if servicingInterrupt {
            executeInterruptCycle()
            return true
        }

        if cycle == 0 {
            // Check for pending interrupts at instruction boundary
            detectNMIEdge()

            if resetPending {
                resetPending = false
                beginInterrupt(.reset)
                return true
            } else if nmiPending {
                nmiPending = false
                beginInterrupt(.nmi)
                return true
            } else if irqLine && !getFlag(Flags.interrupt) {
                beginInterrupt(.irq)
                return true
            }

            // Fetch opcode
            opcode = bus.read(pc)
            pc &+= 1
            cycle = 1
        } else {
            executeCycle()
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
        nmiLine = false
    }

    /// Begin an interrupt sequence. This consumes the current cycle (cycle 0)
    /// and sets up the per-cycle interrupt state machine.
    func beginInterrupt(_ type: InterruptKind) {
        servicingInterrupt = true
        interruptType = type
        // Cycle 0 of interrupt: dummy read (this tick)
        _ = bus.read(pc)
        cycle = 1
    }

    /// Begin interrupt sequence for cycle 1-6 (called from executeInterruptCycle in Instructions.swift)
    // executeInterruptCycle is in Instructions.swift
}
