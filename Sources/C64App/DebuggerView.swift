import SwiftUI
import AppKit
import C64Core

/// Observable bridge between the emulation thread and the debugger GUI.
final class DebuggerBridge: ObservableObject {
    @Published var snapshot = Debugger.Snapshot()
    @Published var isPaused = false
    @Published var traceEnabled = false
    @Published var memoryPreset: MemoryPreset = .zeroPage

    weak var emulator: EmulatorController?
    private var timer: Timer?

    enum MemoryPreset: String, CaseIterable, Identifiable {
        case zeroPage = "Zero Page ($0000)"
        case stack = "Stack ($0100)"
        case screenRAM = "Screen ($0400)"
        case colorRAM = "Color RAM ($D800)"
        case vic = "VIC-II ($D000)"
        case sid = "SID ($D400)"
        case cia1 = "CIA1 ($DC00)"
        case cia2 = "CIA2 ($DD00)"
        case custom = "Custom..."

        var id: String { rawValue }

        var address: UInt16 {
            switch self {
            case .zeroPage: return 0x0000
            case .stack: return 0x0100
            case .screenRAM: return 0x0400
            case .colorRAM: return 0xD800
            case .vic: return 0xD000
            case .sid: return 0xD400
            case .cia1: return 0xDC00
            case .cia2: return 0xDD00
            case .custom: return 0x0000
            }
        }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard let emu = emulator,
              let renderer = emu.renderer else { return }

        renderer.snapshotLock.lock()
        let snap = renderer.debugSnapshot
        renderer.snapshotLock.unlock()

        if let snap = snap {
            DispatchQueue.main.async { [weak self] in
                self?.snapshot = snap
                self?.isPaused = snap.paused
            }
        }
    }

    func pause() {
        emulator?.c64.debugger.pause()
        isPaused = true
    }

    func resume() {
        emulator?.c64.debugger.resume()
        isPaused = false
    }

    func step() {
        emulator?.c64.debugger.step()
    }

    func setTraceEnabled(_ enabled: Bool) {
        emulator?.c64.debugger.traceEnabled = enabled
        traceEnabled = enabled
    }

    func toggleBreakpoint(_ address: UInt16) {
        guard let dbg = emulator?.c64.debugger else { return }
        if dbg.breakpoints.contains(address) {
            dbg.removeBreakpoint(address)
        } else {
            dbg.addBreakpoint(address)
        }
    }

    func setMemoryPage(_ address: UInt16) {
        emulator?.renderer?.debugMemoryPage = address
    }

    func saveTrace() {
        guard let dbg = emulator?.c64.debugger else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "c64_trace.log"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            let lines = dbg.getTraceLines()
            let text = lines.joined(separator: "\n")
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Main Debugger View

struct DebuggerView: View {
    @StateObject private var bridge = DebuggerBridge()
    let emulator: EmulatorController

    var body: some View {
        let snap = bridge.snapshot
        VStack(spacing: 0) {
            DebugToolbar(bridge: bridge, snap: snap)
            Divider()
            HSplitView {
                VSplitView {
                    CPUStatePanel(snap: snap)
                    MemoryPanel(bridge: bridge, snap: snap)
                }
                .frame(minWidth: 360)
                VSplitView {
                    DisassemblyPanel(bridge: bridge, snap: snap)
                    TracePanel(snap: snap)
                }
                .frame(minWidth: 400)
            }
        }
        .frame(minWidth: 800, minHeight: 520)
        .monospaced()
        .onAppear {
            bridge.emulator = emulator
            bridge.start()
        }
        .onDisappear {
            bridge.stop()
        }
    }
}

// MARK: - Toolbar

private struct DebugToolbar: View {
    @ObservedObject var bridge: DebuggerBridge
    let snap: Debugger.Snapshot

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                if bridge.isPaused { bridge.resume() } else { bridge.pause() }
            }) {
                Label(bridge.isPaused ? "Resume" : "Pause",
                      systemImage: bridge.isPaused ? "play.fill" : "pause.fill")
            }

            Button(action: bridge.step) {
                Label("Step", systemImage: "arrow.right")
            }
            .disabled(!bridge.isPaused)

            Divider().frame(height: 20)

            Toggle("Trace", isOn: Binding(
                get: { bridge.traceEnabled },
                set: { bridge.setTraceEnabled($0) }
            ))
            .toggleStyle(.button)

            Button(action: bridge.saveTrace) {
                Label("Save Trace", systemImage: "square.and.arrow.down")
            }

            Spacer()

            if let reason = snap.lastBreak {
                Text(reason.description)
                    .foregroundColor(.red)
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - CPU State

private struct CPUStatePanel: View {
    let snap: Debugger.Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CPU").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    regView("PC", String(format: "$%04X", snap.pc))
                    regView("A",  String(format: "$%02X", snap.a))
                    regView("X",  String(format: "$%02X", snap.x))
                    regView("Y",  String(format: "$%02X", snap.y))
                }
                GridRow {
                    regView("SP",  String(format: "$%02X", snap.sp))
                    regView("CYC", "\(snap.totalCycles)")
                    regView("LIN", "\(snap.rasterLine)")
                    regView("COL", "\(snap.rasterCycle)")
                }
            }

            FlagsRow(p: snap.p)

            HStack(spacing: 16) {
                indicator("IRQ", active: snap.irqLine, color: .red)
                indicator("NMI", active: snap.nmiLine, color: .orange)
            }
            .font(.system(.caption, design: .monospaced))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func regView(_ name: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(name).foregroundColor(.secondary).frame(width: 24, alignment: .trailing)
            Text(value)
        }
    }

    func indicator(_ name: String, active: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(active ? color : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
            Text(name)
        }
    }
}

private struct FlagsRow: View {
    let p: UInt8

    private let flags: [(String, UInt8)] = [
        ("N", 0x80), ("V", 0x40), ("-", 0x20), ("B", 0x10),
        ("D", 0x08), ("I", 0x04), ("Z", 0x02), ("C", 0x01)
    ]

    var body: some View {
        HStack(spacing: 2) {
            Text("P").foregroundColor(.secondary)
            Text(String(format: "$%02X", p)).padding(.trailing, 4)
            ForEach(flags, id: \.0) { name, mask in
                Text(name)
                    .frame(width: 18, height: 18)
                    .background(p & mask != 0 ? Color.accentColor.opacity(0.3) : Color.clear)
                    .cornerRadius(3)
                    .foregroundColor(p & mask != 0 ? .primary : .secondary)
            }
        }
        .font(.system(.caption, design: .monospaced))
    }
}

// MARK: - Disassembly

private struct DisassemblyPanel: View {
    @ObservedObject var bridge: DebuggerBridge
    let snap: Debugger.Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Disassembly").font(.headline)
                .padding(.horizontal, 10).padding(.top, 6)

            ScrollViewReader { proxy in
                List(snap.disassembly) { line in
                    DisassemblyRow(line: line, onToggleBreakpoint: {
                        bridge.toggleBreakpoint(line.address)
                    })
                    .id(line.address)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                    .listRowBackground(
                        line.isCurrent ? Color.accentColor.opacity(0.2) : Color.clear
                    )
                }
                .listStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .onChange(of: snap.pc) { _, newPC in
                    withAnimation(.none) {
                        proxy.scrollTo(newPC, anchor: .center)
                    }
                }
            }
        }
    }
}

private struct DisassemblyRow: View {
    let line: Debugger.DisassemblyLine
    let onToggleBreakpoint: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggleBreakpoint) {
                Circle()
                    .fill(line.hasBreakpoint ? Color.red : Color.clear)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(width: 18)

            Text(line.isCurrent ? ">" : " ")
                .foregroundColor(.accentColor)
                .frame(width: 12)

            Text(String(format: "%04X", line.address))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)

            Text(line.bytes.padding(toLength: 8, withPad: " ", startingAt: 0))
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(line.mnemonic)
                .foregroundColor(mnemonicColor(line.mnemonic))
                .frame(width: 36, alignment: .leading)

            Text(line.operand)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    func mnemonicColor(_ m: String) -> Color {
        if m.hasPrefix("*") { return .orange }
        switch m {
        case "JMP", "JSR", "RTS", "RTI", "BRK": return .purple
        case "BPL", "BMI", "BVC", "BVS", "BCC", "BCS", "BNE", "BEQ": return .blue
        case "LDA", "LDX", "LDY", "STA", "STX", "STY": return .green
        default: return .primary
        }
    }
}

// MARK: - Memory

private struct MemoryPanel: View {
    @ObservedObject var bridge: DebuggerBridge
    let snap: Debugger.Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Memory").font(.headline)
                Spacer()
                Picker("", selection: $bridge.memoryPreset) {
                    ForEach(DebuggerBridge.MemoryPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .frame(width: 200)
                .onChange(of: bridge.memoryPreset) { _, preset in
                    if preset != .custom {
                        bridge.setMemoryPage(preset.address)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(0..<16, id: \.self) { row in
                        MemoryRow(snap: snap, row: row)
                    }
                }
                .padding(.horizontal, 10)
            }
            .font(.system(size: 11, design: .monospaced))
        }
    }
}

private struct MemoryRow: View {
    let snap: Debugger.Snapshot
    let row: Int

    var body: some View {
        let offset = row * 16
        let addr = UInt16(truncatingIfNeeded: Int(snap.memoryPageStart) + offset)
        let bytes = snap.memoryPage

        var hex = ""
        var ascii = ""
        for i in 0..<16 {
            let idx = offset + i
            if idx < bytes.count {
                let byte = bytes[idx]
                hex += String(format: "%02X ", byte)
                ascii += (byte >= 0x20 && byte < 0x7F) ? String(UnicodeScalar(byte)) : "."
            }
            if i == 7 { hex += " " }
        }

        return HStack(spacing: 0) {
            Text(String(format: "%04X ", addr))
                .foregroundColor(.secondary)
            Text(hex)
            Text(" ")
            Text(ascii)
                .foregroundColor(.orange)
        }
    }
}

// MARK: - Trace

private struct TracePanel: View {
    let snap: Debugger.Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Trace").font(.headline)
                Spacer()
                Text("\(snap.traceLines.count) lines")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(snap.traceLines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .id(idx)
                                .textSelection(.enabled)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 1)
                        }
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .onChange(of: snap.traceLines.count) { _, count in
                    if count > 0 {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }
}
