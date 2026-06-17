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

    @State private var showInspector = true
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        let snap = bridge.snapshot

        NavigationSplitView(columnVisibility: $columnVisibility) {
            CPUStatePanel(snap: snap)
                .navigationTitle("CPU Status")
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            DisassemblyPanel(bridge: bridge, snap: snap)
                .navigationTitle("Disassembly")
                .inspector(isPresented: $showInspector) {
                    VStack(spacing: 0) {
                        MemoryPanel(bridge: bridge, snap: snap)
                        Divider()
                        TracePanel(snap: snap)
                    }
                    .inspectorColumnWidth(min: 300, ideal: 350, max: 400)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if let reason = snap.lastBreak {
                            Text(reason.description)
                                .foregroundColor(.red)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.trailing, 8)
                        }

                        Button(action: {
                            if bridge.isPaused { bridge.resume() } else { bridge.pause() }
                        }) {
                            Label(bridge.isPaused ? "Resume" : "Pause",
                                  systemImage: bridge.isPaused ? "play.fill" : "pause.fill")
                        }

                        Button(action: bridge.step) {
                            Label("Step", systemImage: "arrow.right.to.line")
                        }
                        .disabled(!bridge.isPaused)

                        Toggle(isOn: Binding(
                            get: { bridge.traceEnabled },
                            set: { bridge.setTraceEnabled($0) }
                        )) {
                            Label("Trace", systemImage: "ladybug")
                        }
                        .toggleStyle(.button)
                        .help("Enable CPU Trace")

                        Button(action: bridge.saveTrace) {
                            Label("Save Trace", systemImage: "square.and.arrow.down")
                        }
                        .help("Save trace to file")

                        Button(action: { showInspector.toggle() }) {
                            Label("Inspector", systemImage: "sidebar.right")
                        }
                        .help("Toggle Inspector")
                    }
                }
        }
        .frame(minWidth: 900, minHeight: 600)
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

// MARK: - CPU State

private struct CPUStatePanel: View {
    let snap: Debugger.Snapshot

    var body: some View {
        List {
            Section("Registers") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        regView("PC", String(format: "$%04X", snap.pc))
                        regView("A",  String(format: "$%02X", snap.a))
                    }
                    GridRow {
                        regView("X",  String(format: "$%02X", snap.x))
                        regView("Y",  String(format: "$%02X", snap.y))
                    }
                    GridRow {
                        regView("SP",  String(format: "$%02X", snap.sp))
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Status Flags") {
                FlagsRow(p: snap.p)
                    .padding(.vertical, 4)
            }

            Section("Timing") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow { regView("CYC", "\(snap.totalCycles)") }
                    GridRow { regView("LIN", "\(snap.rasterLine)") }
                    GridRow { regView("COL", "\(snap.rasterCycle)") }
                }
                .padding(.vertical, 4)
            }

            Section("Interrupts") {
                HStack(spacing: 16) {
                    indicator("IRQ", active: snap.irqLine, color: .red)
                    indicator("NMI", active: snap.nmiLine, color: .orange)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
    }

    func regView(_ name: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(name).foregroundColor(.secondary).frame(width: 28, alignment: .trailing)
            Text(value).bold()
        }
    }

    func indicator(_ name: String, active: Bool, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? color : Color.gray.opacity(0.3))
                .frame(width: 10, height: 10)
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
        HStack(spacing: 4) {
            Text("P").foregroundColor(.secondary).frame(width: 16, alignment: .leading)
            Text(String(format: "$%02X", p)).padding(.trailing, 8).bold()

            ForEach(flags, id: \ .0) { name, mask in
                Text(name)
                    .frame(width: 20, height: 20)
                    .background(p & mask != 0 ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(4)
                    .foregroundColor(p & mask != 0 ? .primary : .secondary)
            }
        }
    }
}

// MARK: - Disassembly

private struct DisassemblyPanel: View {
    @ObservedObject var bridge: DebuggerBridge
    let snap: Debugger.Snapshot

    var body: some View {
        ScrollViewReader { proxy in
            List(snap.disassembly) { line in
                DisassemblyRow(line: line, onToggleBreakpoint: {
                    bridge.toggleBreakpoint(line.address)
                })
                .id(line.address)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .listRowBackground(
                    line.isCurrent ? Color.accentColor.opacity(0.2) : Color.clear
                )
            }
            .listStyle(.plain)
            .background(Material.ultraThin)
            .font(.system(size: 13, design: .monospaced))
            .onChange(of: snap.pc) { _, newPC in
                withAnimation {
                    proxy.scrollTo(newPC, anchor: .center)
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
                Image(systemName: line.hasBreakpoint ? "bookmark.fill" : "bookmark")
                    .foregroundColor(line.hasBreakpoint ? .red : .gray.opacity(0.3))
            }
            .buttonStyle(.plain)
            .frame(width: 24)

            Text(line.isCurrent ? ">" : " ")
                .foregroundColor(.accentColor)
                .bold()
                .frame(width: 16)

            Text(String(format: "%04X", line.address))
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)

            Text(line.bytes.padding(toLength: 8, withPad: " ", startingAt: 0))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(line.mnemonic)
                .foregroundColor(mnemonicColor(line.mnemonic))
                .bold()
                .frame(width: 44, alignment: .leading)

            Text(line.operand)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Memory").font(.headline)
                Spacer()
                Picker("", selection: $bridge.memoryPreset) {
                    ForEach(DebuggerBridge.MemoryPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: bridge.memoryPreset) { _, preset in
                    if preset != .custom {
                        bridge.setMemoryPage(preset.address)
                    }
                }
            }
            .padding()
            .background(Material.bar)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(0..<16, id: \ .self) { row in
                        MemoryRow(snap: snap, row: row)
                    }
                }
                .padding()
            }
            .background(Material.ultraThin)
        }
        .frame(maxHeight: 400)
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
                .frame(width: 44, alignment: .leading)
            Text(hex)
                .frame(width: 250, alignment: .leading)
            Text(ascii)
                .foregroundColor(.orange)
                .frame(alignment: .leading)
        }
        .font(.system(size: 13, design: .monospaced))
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
            .padding()
            .background(Material.bar)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(snap.traceLines.enumerated()), id: \ .offset) { idx, line in
                            Text(line)
                                .id(idx)
                                .textSelection(.enabled)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .font(.system(size: 11, design: .monospaced))
                .background(Material.ultraThin)
                .onChange(of: snap.traceLines.count) { _, count in
                    if count > 0 {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }
}
