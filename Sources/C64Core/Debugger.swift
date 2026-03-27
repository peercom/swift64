import Foundation
import Emu6502

/// Debug infrastructure for the C64 emulator.
/// Provides CPU trace logging, execution breakpoints, and memory watchpoints.
public final class Debugger {

    // MARK: - Types

    public enum WatchType {
        case read
        case write
        case readWrite
    }

    public struct Watchpoint {
        public let address: UInt16
        public let type: WatchType
        public let label: String?

        public init(address: UInt16, type: WatchType, label: String? = nil) {
            self.address = address
            self.type = type
            self.label = label
        }
    }

    public enum BreakReason: CustomStringConvertible {
        case breakpoint(UInt16)
        case watchpointRead(UInt16, UInt8)
        case watchpointWrite(UInt16, UInt8)

        public var description: String {
            switch self {
            case .breakpoint(let addr):
                return String(format: "Breakpoint at $%04X", addr)
            case .watchpointRead(let addr, let val):
                return String(format: "Watch read $%04X = $%02X", addr, val)
            case .watchpointWrite(let addr, let val):
                return String(format: "Watch write $%04X <- $%02X", addr, val)
            }
        }
    }

    // MARK: - State

    /// Execution breakpoints (PC addresses).
    public var breakpoints: Set<UInt16> = []

    /// Memory watchpoints keyed by address.
    public var watchpoints: [UInt16: Watchpoint] = [:]

    /// Whether CPU tracing is enabled.
    public var traceEnabled: Bool = false

    /// Maximum number of trace lines to keep in the ring buffer (0 = file only).
    public var traceBufferSize: Int = 10_000

    /// Ring buffer of recent trace lines.
    public private(set) var traceBuffer: [String] = []
    private var traceIndex: Int = 0
    private var traceBufferFull: Bool = false

    /// File handle for trace output (nil = buffer only).
    private var traceFile: FileHandle?
    private var traceFilePath: String?

    /// Called when a breakpoint or watchpoint fires. Return true to pause.
    public var onBreak: ((BreakReason) -> Bool)?

    /// Whether the debugger is paused.
    public private(set) var paused: Bool = false

    /// Last break reason.
    public private(set) var lastBreak: BreakReason?

    /// Weak references set by C64 init.
    weak var cpu: CPU6502?
    weak var memory: MemoryMap?

    // MARK: - Init

    public init() {}

    deinit {
        closeTraceFile()
    }

    // MARK: - Breakpoints

    public func addBreakpoint(_ address: UInt16) {
        breakpoints.insert(address)
    }

    public func removeBreakpoint(_ address: UInt16) {
        breakpoints.remove(address)
    }

    public func clearBreakpoints() {
        breakpoints.removeAll()
    }

    // MARK: - Watchpoints

    public func addWatchpoint(_ address: UInt16, type: WatchType, label: String? = nil) {
        watchpoints[address] = Watchpoint(address: address, type: type, label: label)
    }

    public func removeWatchpoint(_ address: UInt16) {
        watchpoints.removeValue(forKey: address)
    }

    public func clearWatchpoints() {
        watchpoints.removeAll()
    }

    // MARK: - Pause / Resume

    public func pause() {
        paused = true
    }

    public func resume() {
        paused = false
        lastBreak = nil
    }

    /// Execute a single instruction then pause again.
    public func step() {
        paused = false
        // Will be set back to paused after one instruction in checkBreakpoint
        singleStepping = true
    }

    var singleStepping: Bool = false

    // MARK: - Trace file

    /// Start writing trace output to a file.
    public func openTraceFile(_ path: String) {
        closeTraceFile()
        FileManager.default.createFile(atPath: path, contents: nil)
        traceFile = FileHandle(forWritingAtPath: path)
        traceFilePath = path
    }

    /// Stop writing trace output to file.
    public func closeTraceFile() {
        traceFile?.closeFile()
        traceFile = nil
        traceFilePath = nil
    }

    // MARK: - Check at instruction boundary (called from C64.tickOneCycle)

    /// Called at cycle 0 (instruction boundary). Returns true if execution should continue.
    func checkBreakpoint() -> Bool {
        guard let cpu = cpu else { return true }

        if singleStepping {
            singleStepping = false
            paused = true
            return false
        }

        if breakpoints.contains(cpu.pc) {
            let reason = BreakReason.breakpoint(cpu.pc)
            lastBreak = reason
            if let handler = onBreak {
                paused = handler(reason)
            } else {
                paused = true
            }
            if paused { return false }
        }

        return true
    }

    // MARK: - Watchpoint checks (called from MemoryMap)

    func notifyRead(_ address: UInt16, value: UInt8) {
        guard let wp = watchpoints[address] else { return }
        guard wp.type == .read || wp.type == .readWrite else { return }

        let reason = BreakReason.watchpointRead(address, value)
        lastBreak = reason
        if let handler = onBreak {
            paused = handler(reason)
        } else {
            paused = true
        }
    }

    func notifyWrite(_ address: UInt16, value: UInt8) {
        guard let wp = watchpoints[address] else { return }
        guard wp.type == .write || wp.type == .readWrite else { return }

        let reason = BreakReason.watchpointWrite(address, value)
        lastBreak = reason
        if let handler = onBreak {
            paused = handler(reason)
        } else {
            paused = true
        }
    }

    // MARK: - CPU Trace

    /// Log the current instruction. Called at cycle 0 before execution.
    func traceInstruction() {
        guard traceEnabled, let cpu = cpu, let mem = memory else { return }

        let pc = cpu.pc
        let opcode = mem.ram[Int(pc)]  // Read from RAM directly to avoid side effects
        let info = Disassembler.opcodeInfo[Int(opcode)]
        let bytes = Disassembler.operandSize(info.mode)

        // Read operand bytes directly from underlying memory
        let b1: UInt8 = bytes >= 2 ? readUnderlying(pc &+ 1, mem: mem) : 0
        let b2: UInt8 = bytes >= 3 ? readUnderlying(pc &+ 2, mem: mem) : 0

        // Format: PC  BYTES  MNEMONIC OPERAND  A=XX X=XX Y=XX SP=XX P=XX  cyc=N
        let hexBytes: String
        switch bytes {
        case 1: hexBytes = String(format: "%02X      ", opcode)
        case 2: hexBytes = String(format: "%02X %02X   ", opcode, b1)
        case 3: hexBytes = String(format: "%02X %02X %02X", opcode, b1, b2)
        default: hexBytes = String(format: "%02X      ", opcode)
        }

        let operand = Disassembler.formatOperand(info.mode, b1: b1, b2: b2)
        let mnemonic = info.mnemonic.padding(toLength: 4, withPad: " ", startingAt: 0)

        let line = String(format: "%04X  %@  %@%@  A=%02X X=%02X Y=%02X SP=%02X P=%02X  cyc=%llu",
                          pc, hexBytes, mnemonic, operand,
                          cpu.a, cpu.x, cpu.y, cpu.sp, cpu.p,
                          cpu.totalCycles)

        appendTrace(line)
    }

    /// Read a byte without triggering watchpoints or I/O side effects.
    func readUnderlying(_ address: UInt16, mem: MemoryMap) -> UInt8 {
        let addr = Int(address)
        // For ROM areas, read through the normal banking logic but avoid I/O
        switch addr {
        case 0xA000...0xBFFF:
            if mem.loram && mem.hiram { return mem.basicROM[addr - 0xA000] }
            return mem.ram[addr]
        case 0xD000...0xDFFF:
            // Always read RAM here to avoid I/O side effects
            if (mem.hiram || mem.loram) && !mem.charen {
                return mem.charROM[addr - 0xD000]
            }
            return mem.ram[addr]
        case 0xE000...0xFFFF:
            if mem.hiram { return mem.kernalROM[addr - 0xE000] }
            return mem.ram[addr]
        default:
            return mem.ram[addr]
        }
    }

    private func appendTrace(_ line: String) {
        // Write to file if open
        if let file = traceFile {
            file.write(Data((line + "\n").utf8))
        }

        // Write to ring buffer
        guard traceBufferSize > 0 else { return }

        if traceBuffer.count < traceBufferSize {
            traceBuffer.append(line)
        } else {
            traceBuffer[traceIndex] = line
            traceBufferFull = true
        }
        traceIndex = (traceIndex + 1) % traceBufferSize
    }

    /// Return trace lines in chronological order.
    public func getTraceLines() -> [String] {
        if traceBufferFull {
            return Array(traceBuffer[traceIndex...]) + Array(traceBuffer[..<traceIndex])
        }
        return traceBuffer
    }

    /// Clear the trace buffer.
    public func clearTrace() {
        traceBuffer.removeAll()
        traceIndex = 0
        traceBufferFull = false
    }

    // MARK: - Snapshot (for GUI, thread-safe)

    /// A frozen snapshot of emulator state for the debugger GUI to display.
    public struct Snapshot {
        public var pc: UInt16 = 0
        public var a: UInt8 = 0
        public var x: UInt8 = 0
        public var y: UInt8 = 0
        public var sp: UInt8 = 0
        public var p: UInt8 = 0
        public var totalCycles: UInt64 = 0
        public var rasterLine: UInt16 = 0
        public var rasterCycle: Int = 0
        public var irqLine: Bool = false
        public var nmiLine: Bool = false
        public var paused: Bool = false
        public var lastBreak: BreakReason?
        public var disassembly: [DisassemblyLine] = []
        public var traceLines: [String] = []
        public var memoryPage: [UInt8] = []
        public var memoryPageStart: UInt16 = 0
        public var breakpoints: Set<UInt16> = []

        public init() {}
    }

    public struct DisassemblyLine: Identifiable {
        public var id: UInt16 { address }
        public let address: UInt16
        public let bytes: String
        public let mnemonic: String
        public let operand: String
        public let size: Int
        public let isCurrent: Bool
        public let hasBreakpoint: Bool
    }

    /// Take a snapshot of current emulator state. Call from the emulation thread.
    public func takeSnapshot(memoryStart: UInt16 = 0x0000) -> Snapshot {
        guard let cpu = cpu, let mem = memory else { return Snapshot() }

        var snap = Snapshot()
        snap.pc = cpu.pc
        snap.a = cpu.a
        snap.x = cpu.x
        snap.y = cpu.y
        snap.sp = cpu.sp
        snap.p = cpu.p
        snap.totalCycles = cpu.totalCycles
        snap.irqLine = cpu.irqLine
        snap.nmiLine = cpu.nmiLine
        snap.paused = paused
        snap.lastBreak = lastBreak
        snap.breakpoints = breakpoints

        // Rasterline info - read from VIC via the C64 reference
        // (VIC is not directly wired to the debugger, so we access via memory's weak ref)
        if let vic = mem.vic {
            snap.rasterLine = vic.rasterLine
            snap.rasterCycle = vic.rasterCycle
        }

        // Disassembly: 32 lines starting a bit before PC
        snap.disassembly = disassembleLines(around: cpu.pc, count: 32, mem: mem)

        // Trace: last 200 lines
        let allTrace = getTraceLines()
        snap.traceLines = Array(allTrace.suffix(200))

        // Memory page: 256 bytes from requested start
        snap.memoryPageStart = memoryStart
        snap.memoryPage = (0..<256).map { i in
            mem.ram[Int((UInt32(memoryStart) + UInt32(i)) & 0xFFFF)]
        }

        return snap
    }

    private func disassembleLines(around pc: UInt16, count: Int, mem: MemoryMap) -> [DisassemblyLine] {
        // Start a few instructions before PC for context
        // We'll scan back by guessing, then forward
        var lines: [DisassemblyLine] = []

        // Try to start ~10 instructions before PC by scanning back ~30 bytes
        let startAddr = pc &- 30
        var addr = startAddr
        var foundPc = false

        // Forward pass: disassemble up to count instructions
        for _ in 0..<(count + 20) {
            let opcode = readUnderlying(addr, mem: mem)
            let info = Disassembler.opcodeInfo[Int(opcode)]
            let size = Disassembler.operandSize(info.mode)

            let b1: UInt8 = size >= 2 ? readUnderlying(addr &+ 1, mem: mem) : 0
            let b2: UInt8 = size >= 3 ? readUnderlying(addr &+ 2, mem: mem) : 0

            let hexBytes: String
            switch size {
            case 1: hexBytes = String(format: "%02X", opcode)
            case 2: hexBytes = String(format: "%02X %02X", opcode, b1)
            case 3: hexBytes = String(format: "%02X %02X %02X", opcode, b1, b2)
            default: hexBytes = String(format: "%02X", opcode)
            }

            var operand = Disassembler.formatOperand(info.mode, b1: b1, b2: b2)
            if info.mode == .relative {
                let offset = Int8(bitPattern: b1)
                let target = addr &+ UInt16(bitPattern: Int16(size) + Int16(offset))
                operand = String(format: "$%04X", target)
            }

            if addr == pc { foundPc = true }

            lines.append(DisassemblyLine(
                address: addr,
                bytes: hexBytes,
                mnemonic: info.mnemonic,
                operand: operand,
                size: size,
                isCurrent: addr == pc,
                hasBreakpoint: breakpoints.contains(addr)
            ))

            addr &+= UInt16(size)

            // Once we've found PC and have enough lines after it, stop
            if foundPc && lines.count > count { break }
        }

        // Trim to show context around PC
        if let pcIndex = lines.firstIndex(where: { $0.isCurrent }) {
            let start = max(0, pcIndex - 8)
            let end = min(lines.count, start + count)
            return Array(lines[start..<end])
        }

        return Array(lines.prefix(count))
    }

    // MARK: - Memory dump

    /// Hex dump a range of memory.
    public func hexDump(from start: UInt16, count: Int) -> String {
        guard let mem = memory else { return "" }
        var lines: [String] = []
        var addr = Int(start)
        var remaining = count

        while remaining > 0 {
            let lineBytes = min(remaining, 16)
            var hex = ""
            var ascii = ""
            for i in 0..<16 {
                if i < lineBytes {
                    let byte = mem.ram[(addr + i) & 0xFFFF]
                    hex += String(format: "%02X ", byte)
                    ascii += (byte >= 0x20 && byte < 0x7F) ? String(UnicodeScalar(byte)) : "."
                } else {
                    hex += "   "
                }
                if i == 7 { hex += " " }
            }
            lines.append(String(format: "%04X  %@ %@", addr & 0xFFFF, hex, ascii))
            addr += lineBytes
            remaining -= lineBytes
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Disassembler

public enum Disassembler {

    public struct OpcodeInfo {
        public let mnemonic: String
        public let mode: AddressingMode
    }

    /// Format an operand for display.
    public static func operandSize(_ mode: AddressingMode) -> Int {
        switch mode {
        case .implied, .accumulator:   return 1
        case .immediate, .zeroPage, .zeroPageX, .zeroPageY,
             .indirectX, .indirectY, .relative:
                                       return 2
        case .absolute, .absoluteX, .absoluteY, .indirect:
                                       return 3
        }
    }

    public static func formatOperand(_ mode: AddressingMode, b1: UInt8, b2: UInt8) -> String {
        let addr16 = UInt16(b2) << 8 | UInt16(b1)
        switch mode {
        case .implied:       return ""
        case .accumulator:   return "A"
        case .immediate:     return String(format: "#$%02X", b1)
        case .zeroPage:      return String(format: "$%02X", b1)
        case .zeroPageX:     return String(format: "$%02X,X", b1)
        case .zeroPageY:     return String(format: "$%02X,Y", b1)
        case .absolute:      return String(format: "$%04X", addr16)
        case .absoluteX:     return String(format: "$%04X,X", addr16)
        case .absoluteY:     return String(format: "$%04X,Y", addr16)
        case .indirectX:     return String(format: "($%02X,X)", b1)
        case .indirectY:     return String(format: "($%02X),Y", b1)
        case .relative:
            // Show target address (PC + 2 + signed offset) — but we don't know PC here,
            // so just show the offset. Caller can resolve if needed.
            return String(format: "$%02X", b1)
        case .indirect:      return String(format: "($%04X)", addr16)
        }
    }

    /// Disassemble a range of memory.
    public static func disassemble(memory: MemoryMap, from start: UInt16, count: Int) -> String {
        var lines: [String] = []
        var pc = start
        var remaining = count

        while remaining > 0 {
            let opcode = memory.ram[Int(pc)]
            let info = opcodeInfo[Int(opcode)]
            let size = operandSize(info.mode)

            let b1: UInt8 = size >= 2 ? memory.ram[Int((pc &+ 1) & 0xFFFF)] : 0
            let b2: UInt8 = size >= 3 ? memory.ram[Int((pc &+ 2) & 0xFFFF)] : 0

            let hexBytes: String
            switch size {
            case 1: hexBytes = String(format: "%02X      ", opcode)
            case 2: hexBytes = String(format: "%02X %02X   ", opcode, b1)
            case 3: hexBytes = String(format: "%02X %02X %02X", opcode, b1, b2)
            default: hexBytes = String(format: "%02X      ", opcode)
            }

            var operand = formatOperand(info.mode, b1: b1, b2: b2)

            // For relative branches, resolve the target address
            if info.mode == .relative {
                let offset = Int8(bitPattern: b1)
                let target = pc &+ UInt16(bitPattern: Int16(size) + Int16(offset))
                operand = String(format: "$%04X", target)
            }

            let mnemonic = info.mnemonic.padding(toLength: 4, withPad: " ", startingAt: 0)
            lines.append(String(format: "%04X  %@  %@%@", pc, hexBytes, mnemonic, operand))

            pc &+= UInt16(size)
            remaining -= 1
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Opcode table

    /// Full 6502 opcode table (256 entries). Undocumented opcodes shown as *NOP, *LAX, etc.
    public static let opcodeInfo: [OpcodeInfo] = {
        var table = [OpcodeInfo](repeating: OpcodeInfo(mnemonic: "???", mode: .implied), count: 256)

        // Helper
        func set(_ op: Int, _ mn: String, _ m: AddressingMode) {
            table[op] = OpcodeInfo(mnemonic: mn, mode: m)
        }

        // LDA
        set(0xA9, "LDA", .immediate);  set(0xA5, "LDA", .zeroPage)
        set(0xB5, "LDA", .zeroPageX);  set(0xAD, "LDA", .absolute)
        set(0xBD, "LDA", .absoluteX);  set(0xB9, "LDA", .absoluteY)
        set(0xA1, "LDA", .indirectX);  set(0xB1, "LDA", .indirectY)

        // LDX
        set(0xA2, "LDX", .immediate);  set(0xA6, "LDX", .zeroPage)
        set(0xB6, "LDX", .zeroPageY);  set(0xAE, "LDX", .absolute)
        set(0xBE, "LDX", .absoluteY)

        // LDY
        set(0xA0, "LDY", .immediate);  set(0xA4, "LDY", .zeroPage)
        set(0xB4, "LDY", .zeroPageX);  set(0xAC, "LDY", .absolute)
        set(0xBC, "LDY", .absoluteX)

        // STA
        set(0x85, "STA", .zeroPage);   set(0x95, "STA", .zeroPageX)
        set(0x8D, "STA", .absolute);   set(0x9D, "STA", .absoluteX)
        set(0x99, "STA", .absoluteY);  set(0x81, "STA", .indirectX)
        set(0x91, "STA", .indirectY)

        // STX
        set(0x86, "STX", .zeroPage);   set(0x96, "STX", .zeroPageY)
        set(0x8E, "STX", .absolute)

        // STY
        set(0x84, "STY", .zeroPage);   set(0x94, "STY", .zeroPageX)
        set(0x8C, "STY", .absolute)

        // ADC
        set(0x69, "ADC", .immediate);  set(0x65, "ADC", .zeroPage)
        set(0x75, "ADC", .zeroPageX);  set(0x6D, "ADC", .absolute)
        set(0x7D, "ADC", .absoluteX);  set(0x79, "ADC", .absoluteY)
        set(0x61, "ADC", .indirectX);  set(0x71, "ADC", .indirectY)

        // SBC
        set(0xE9, "SBC", .immediate);  set(0xE5, "SBC", .zeroPage)
        set(0xF5, "SBC", .zeroPageX);  set(0xED, "SBC", .absolute)
        set(0xFD, "SBC", .absoluteX);  set(0xF9, "SBC", .absoluteY)
        set(0xE1, "SBC", .indirectX);  set(0xF1, "SBC", .indirectY)

        // AND
        set(0x29, "AND", .immediate);  set(0x25, "AND", .zeroPage)
        set(0x35, "AND", .zeroPageX);  set(0x2D, "AND", .absolute)
        set(0x3D, "AND", .absoluteX);  set(0x39, "AND", .absoluteY)
        set(0x21, "AND", .indirectX);  set(0x31, "AND", .indirectY)

        // ORA
        set(0x09, "ORA", .immediate);  set(0x05, "ORA", .zeroPage)
        set(0x15, "ORA", .zeroPageX);  set(0x0D, "ORA", .absolute)
        set(0x1D, "ORA", .absoluteX);  set(0x19, "ORA", .absoluteY)
        set(0x01, "ORA", .indirectX);  set(0x11, "ORA", .indirectY)

        // EOR
        set(0x49, "EOR", .immediate);  set(0x45, "EOR", .zeroPage)
        set(0x55, "EOR", .zeroPageX);  set(0x4D, "EOR", .absolute)
        set(0x5D, "EOR", .absoluteX);  set(0x59, "EOR", .absoluteY)
        set(0x41, "EOR", .indirectX);  set(0x51, "EOR", .indirectY)

        // CMP
        set(0xC9, "CMP", .immediate);  set(0xC5, "CMP", .zeroPage)
        set(0xD5, "CMP", .zeroPageX);  set(0xCD, "CMP", .absolute)
        set(0xDD, "CMP", .absoluteX);  set(0xD9, "CMP", .absoluteY)
        set(0xC1, "CMP", .indirectX);  set(0xD1, "CMP", .indirectY)

        // CPX
        set(0xE0, "CPX", .immediate);  set(0xE4, "CPX", .zeroPage)
        set(0xEC, "CPX", .absolute)

        // CPY
        set(0xC0, "CPY", .immediate);  set(0xC4, "CPY", .zeroPage)
        set(0xCC, "CPY", .absolute)

        // INC
        set(0xE6, "INC", .zeroPage);   set(0xF6, "INC", .zeroPageX)
        set(0xEE, "INC", .absolute);   set(0xFE, "INC", .absoluteX)

        // DEC
        set(0xC6, "DEC", .zeroPage);   set(0xD6, "DEC", .zeroPageX)
        set(0xCE, "DEC", .absolute);   set(0xDE, "DEC", .absoluteX)

        // INX, INY, DEX, DEY
        set(0xE8, "INX", .implied);    set(0xC8, "INY", .implied)
        set(0xCA, "DEX", .implied);    set(0x88, "DEY", .implied)

        // ASL
        set(0x0A, "ASL", .accumulator); set(0x06, "ASL", .zeroPage)
        set(0x16, "ASL", .zeroPageX);   set(0x0E, "ASL", .absolute)
        set(0x1E, "ASL", .absoluteX)

        // LSR
        set(0x4A, "LSR", .accumulator); set(0x46, "LSR", .zeroPage)
        set(0x56, "LSR", .zeroPageX);   set(0x4E, "LSR", .absolute)
        set(0x5E, "LSR", .absoluteX)

        // ROL
        set(0x2A, "ROL", .accumulator); set(0x26, "ROL", .zeroPage)
        set(0x36, "ROL", .zeroPageX);   set(0x2E, "ROL", .absolute)
        set(0x3E, "ROL", .absoluteX)

        // ROR
        set(0x6A, "ROR", .accumulator); set(0x66, "ROR", .zeroPage)
        set(0x76, "ROR", .zeroPageX);   set(0x6E, "ROR", .absolute)
        set(0x7E, "ROR", .absoluteX)

        // BIT
        set(0x24, "BIT", .zeroPage);   set(0x2C, "BIT", .absolute)

        // Branches
        set(0x10, "BPL", .relative);   set(0x30, "BMI", .relative)
        set(0x50, "BVC", .relative);   set(0x70, "BVS", .relative)
        set(0x90, "BCC", .relative);   set(0xB0, "BCS", .relative)
        set(0xD0, "BNE", .relative);   set(0xF0, "BEQ", .relative)

        // Jumps and calls
        set(0x4C, "JMP", .absolute);   set(0x6C, "JMP", .indirect)
        set(0x20, "JSR", .absolute);   set(0x60, "RTS", .implied)

        // Interrupts
        set(0x00, "BRK", .implied);    set(0x40, "RTI", .implied)

        // Stack
        set(0x48, "PHA", .implied);    set(0x68, "PLA", .implied)
        set(0x08, "PHP", .implied);    set(0x28, "PLP", .implied)

        // Flags
        set(0x18, "CLC", .implied);    set(0x38, "SEC", .implied)
        set(0xD8, "CLD", .implied);    set(0xF8, "SED", .implied)
        set(0x58, "CLI", .implied);    set(0x78, "SEI", .implied)
        set(0xB8, "CLV", .implied)

        // Transfers
        set(0xAA, "TAX", .implied);    set(0x8A, "TXA", .implied)
        set(0xA8, "TAY", .implied);    set(0x98, "TYA", .implied)
        set(0xBA, "TSX", .implied);    set(0x9A, "TXS", .implied)

        // NOP
        set(0xEA, "NOP", .implied)

        // --- Undocumented opcodes (commonly used ones) ---

        // *NOP (various addressing modes)
        for op in [0x1A, 0x3A, 0x5A, 0x7A, 0xDA, 0xFA] as [Int] {
            set(op, "*NOP", .implied)
        }
        for op in [0x04, 0x44, 0x64] as [Int] {
            set(op, "*NOP", .zeroPage)
        }
        for op in [0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4] as [Int] {
            set(op, "*NOP", .zeroPageX)
        }
        set(0x80, "*NOP", .immediate)
        for op in [0x0C] as [Int] {
            set(op, "*NOP", .absolute)
        }
        for op in [0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC] as [Int] {
            set(op, "*NOP", .absoluteX)
        }

        // *LAX
        set(0xA7, "*LAX", .zeroPage);  set(0xB7, "*LAX", .zeroPageY)
        set(0xAF, "*LAX", .absolute);  set(0xBF, "*LAX", .absoluteY)
        set(0xA3, "*LAX", .indirectX); set(0xB3, "*LAX", .indirectY)

        // *SAX
        set(0x87, "*SAX", .zeroPage);  set(0x97, "*SAX", .zeroPageY)
        set(0x8F, "*SAX", .absolute);  set(0x83, "*SAX", .indirectX)

        // *SBC
        set(0xEB, "*SBC", .immediate)

        // *DCP
        set(0xC7, "*DCP", .zeroPage);  set(0xD7, "*DCP", .zeroPageX)
        set(0xCF, "*DCP", .absolute);  set(0xDF, "*DCP", .absoluteX)
        set(0xDB, "*DCP", .absoluteY); set(0xC3, "*DCP", .indirectX)
        set(0xD3, "*DCP", .indirectY)

        // *ISC (ISB)
        set(0xE7, "*ISC", .zeroPage);  set(0xF7, "*ISC", .zeroPageX)
        set(0xEF, "*ISC", .absolute);  set(0xFF, "*ISC", .absoluteX)
        set(0xFB, "*ISC", .absoluteY); set(0xE3, "*ISC", .indirectX)
        set(0xF3, "*ISC", .indirectY)

        // *SLO
        set(0x07, "*SLO", .zeroPage);  set(0x17, "*SLO", .zeroPageX)
        set(0x0F, "*SLO", .absolute);  set(0x1F, "*SLO", .absoluteX)
        set(0x1B, "*SLO", .absoluteY); set(0x03, "*SLO", .indirectX)
        set(0x13, "*SLO", .indirectY)

        // *RLA
        set(0x27, "*RLA", .zeroPage);  set(0x37, "*RLA", .zeroPageX)
        set(0x2F, "*RLA", .absolute);  set(0x3F, "*RLA", .absoluteX)
        set(0x3B, "*RLA", .absoluteY); set(0x23, "*RLA", .indirectX)
        set(0x33, "*RLA", .indirectY)

        // *SRE
        set(0x47, "*SRE", .zeroPage);  set(0x57, "*SRE", .zeroPageX)
        set(0x4F, "*SRE", .absolute);  set(0x5F, "*SRE", .absoluteX)
        set(0x5B, "*SRE", .absoluteY); set(0x43, "*SRE", .indirectX)
        set(0x53, "*SRE", .indirectY)

        // *RRA
        set(0x67, "*RRA", .zeroPage);  set(0x77, "*RRA", .zeroPageX)
        set(0x6F, "*RRA", .absolute);  set(0x7F, "*RRA", .absoluteX)
        set(0x7B, "*RRA", .absoluteY); set(0x63, "*RRA", .indirectX)
        set(0x73, "*RRA", .indirectY)

        // *ANC
        set(0x0B, "*ANC", .immediate); set(0x2B, "*ANC", .immediate)

        // *ALR
        set(0x4B, "*ALR", .immediate)

        // *ARR
        set(0x6B, "*ARR", .immediate)

        // *AXS (SBX)
        set(0xCB, "*AXS", .immediate)

        // KIL/JAM opcodes
        for op in [0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72,
                   0x92, 0xB2, 0xD2, 0xF2] as [Int] {
            set(op, "*KIL", .implied)
        }

        return table
    }()
}
