/// Cycle-accurate MOS 6502 CPU emulator.
///
/// Call `tick()` once per system clock cycle. The CPU communicates with the
/// outside world exclusively through the `Bus` protocol.
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

    /// Number of remaining cycles to burn (instruction already executed).
    public var pendingCycles: Int = 0

    /// Bus access counter used during instruction execution to track cycle cost.
    var busAccessCount: Int = 0

    /// Pending NMI (edge-detected).
    var nmiPending: Bool = false
    /// Previous NMI line state for edge detection.
    var nmiLinePrev: Bool = false
    /// NMI line state.
    public var nmiLine: Bool = false

    /// Pending interrupt type to service.
    var interruptPending: InterruptType? = nil

    enum InterruptType {
        case nmi
        case irq
        case reset
    }

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

        // If we have pending cycles from an already-executed instruction, burn one
        if pendingCycles > 0 {
            pendingCycles -= 1
            if pendingCycles == 0 {
                cycle = 0
            }
            return true
        }

        if cycle == 0 {
            // Check for pending interrupts at instruction boundary
            detectNMIEdge()

            if resetPending {
                interruptPending = .reset
                resetPending = false
            } else if nmiPending {
                interruptPending = .nmi
                nmiPending = false
            } else if irqLine && !getFlag(Flags.interrupt) {
                interruptPending = .irq
            }

            if let interrupt = interruptPending {
                interruptPending = nil
                beginInterrupt(interrupt)
                return true
            }

            // Fetch opcode
            opcode = bus.read(pc)
            pc &+= 1
            cycle = 1
        } else {
            executeInstructionCycle()
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

    // MARK: - Counted bus access (for cycle tracking)

    /// Read from bus and count as one cycle.
    func busRead(_ address: UInt16) -> UInt8 {
        busAccessCount += 1
        return bus.read(address)
    }

    /// Write to bus and count as one cycle.
    func busWrite(_ address: UInt16, value: UInt8) {
        busAccessCount += 1
        bus.write(address, value: value)
    }

    // MARK: - Stack helpers

    func push(_ value: UInt8) {
        busWrite(0x0100 | UInt16(sp), value: value)
        sp &-= 1
    }

    func pull() -> UInt8 {
        sp &+= 1
        return busRead(0x0100 | UInt16(sp))
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
    /// and sets up the remaining 6 cycles.
    func beginInterrupt(_ type: InterruptType) {
        // Interrupt sequence is 7 cycles total. We're in cycle 0 (1 cycle consumed).
        // The remaining 6 cycles are set as pendingCycles.
        switch type {
        case .reset:
            _ = bus.read(0x0100 | UInt16(sp))
            sp &-= 1
            _ = bus.read(0x0100 | UInt16(sp))
            sp &-= 1
            _ = bus.read(0x0100 | UInt16(sp))
            sp &-= 1
            setFlag(Flags.interrupt, true)
            let lo = UInt16(bus.read(Vector.reset))
            let hi = UInt16(bus.read(Vector.reset + 1))
            pc = (hi << 8) | lo

        case .nmi:
            _ = bus.read(pc)  // dummy read
            push(UInt8(pc >> 8))
            push(UInt8(pc & 0xFF))
            push(p & ~Flags.brk | Flags.unused)
            setFlag(Flags.interrupt, true)
            let lo = UInt16(bus.read(Vector.nmi))
            let hi = UInt16(bus.read(Vector.nmi + 1))
            pc = (hi << 8) | lo

        case .irq:
            _ = bus.read(pc)  // dummy read
            push(UInt8(pc >> 8))
            push(UInt8(pc & 0xFF))
            push(p & ~Flags.brk | Flags.unused)
            setFlag(Flags.interrupt, true)
            let lo = UInt16(bus.read(Vector.irq))
            let hi = UInt16(bus.read(Vector.irq + 1))
            pc = (hi << 8) | lo
        }
        // 7 cycles total, 1 already consumed by this tick
        pendingCycles = 6
        cycle = 1  // non-zero so we don't re-fetch; pendingCycles will drain to 0 then reset cycle
    }
}
