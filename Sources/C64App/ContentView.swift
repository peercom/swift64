import SwiftUI
import MetalKit
import C64Core
import AVFoundation
import UniformTypeIdentifiers

/// Main content view wrapping the Metal display and handling keyboard/audio.
struct ContentView: View {
    @ObservedObject var emulator: EmulatorController

    @Environment(\.openWindow) private var openWindow
    @State private var showingDriveStatus = false

    private let statusTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var status: C64.EmulationStatus {
        emulator.emulationStatus ?? emulator.c64.emulationStatus
    }

    var body: some View {
        MetalView(emulator: emulator)
            .aspectRatio(CGSize(width: 403, height: 284), contentMode: .fit)
            .frame(minWidth: 806, minHeight: 568)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: { openDisk() }) {
                        Label("Load Disk", systemImage: "opticaldiscdrive")
                    }
                    .help("Mount D64/G64 Disk Image")

                    Button(action: { openTape() }) {
                        Label("Load Tape", systemImage: "cassette")
                    }
                    .help("Mount T64/TAP Tape Image")

                    Button(action: { loadPRG() }) {
                        Label("Load PRG", systemImage: "doc.badge.gearshape")
                    }
                    .help("Load PRG Program")

                    Divider()

                    Toggle(isOn: Binding(
                        get: { emulator.c64.trueDriveEmulation },
                        set: { enabled in
                            emulator.c64.trueDriveEmulationMode = enabled ? .compat1541 : .off
                            if enabled {
                                emulator.c64.iecBus.updateFromC64(emulator.c64.cia2.portA, ddra: emulator.c64.cia2.ddra)
                                emulator.c64.drive1541.powerOn()
                                print("True drive emulation enabled")
                            } else {
                                emulator.c64.drive1541.enabled = false
                                print("True drive emulation disabled (using Kernal traps)")
                            }
                            emulator.refreshStatus()
                        }
                    )) {
                        Label(status.trueDriveMode == .off ? "Fast Load" : "True Drive 1541", systemImage: status.trueDriveMode == .off ? "bolt" : "externaldrive")
                    }
                    .toggleStyle(.button)
                    .help(status.trueDriveMode == .off ? "Fast Kernal-trap loading is active" : "Compatibility true-drive 1541 emulation is active")

                    if emulator.hasMountedDisk {
                        Label(status.mediaCapabilities?.isNativeLowLevel == true ? "Native G64" : "Synthetic GCR", systemImage: status.mediaCapabilities?.isNativeLowLevel == true ? "waveform.path" : "square.stack.3d.down.right")
                            .help(status.mediaCapabilities?.isNativeLowLevel == true ? "Native low-level disk image mounted" : "Synthetic low-level GCR stream mounted")
                    }

                    Button(action: { showingDriveStatus.toggle() }) {
                        Label("Drive Status", systemImage: status.lastFailureReason == nil ? "gauge.with.dots.needle.67percent" : "exclamationmark.triangle")
                    }
                    .help("Show compact drive and media status")
                    .popover(isPresented: $showingDriveStatus, arrowEdge: .bottom) {
                        DriveStatusPopover(status: status)
                            .frame(width: 360)
                    }

                    Divider()

                    Button(action: { openWindow(id: "debugger") }) {
                        Label("Debugger", systemImage: "ladybug")
                    }
                    .help("Show Debugger")

                    Button(action: { emulator.c64.reset() }) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .help("Reset C64")
                }
            }
            .onReceive(statusTimer) { _ in
                emulator.refreshStatus()
            }
    }

    func openDisk() {
        openFile(types: ["d64", "g64"], title: "Open Disk Image") { url in
            emulator.mountDisk(url)
        }
    }

    func openTape() {
        openFile(types: ["t64", "tap"], title: "Open Tape Image") { url in
            if emulator.c64.mountTape(url) {
                print("Tape mounted: \(url.lastPathComponent)")
            }
        }
    }

    func loadPRG() {
        openFile(types: ["prg", "p00"], title: "Load PRG Program") { url in
            emulator.c64.loadPRG(url, autoRun: true)
            print("PRG loaded: \(url.lastPathComponent)")
        }
    }

    func openFile(types: [String], title: String, handler: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = types.compactMap { ext in
            .init(filenameExtension: ext)
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            handler(url)
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                emulator.loadFile(url)
            }
        }
        return true
    }
}

private struct DriveStatusPopover: View {
    let status: C64.EmulationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Drive Status", systemImage: "externaldrive")
                    .font(.headline)
                Spacer()
                Text(status.trueDriveMode.displayName)
                    .foregroundStyle(.secondary)
            }

            if let failure = status.lastFailureReason {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            VStack(alignment: .leading, spacing: 6) {
                StatusRow(label: "Image", value: status.mountedDiskName ?? "none")
                StatusRow(label: "Media", value: mediaDescription)
                StatusRow(label: "Capability", value: capabilityDescription)
                StatusRow(label: "CPU", value: "$\(hex16(status.cpuPC))\(status.cpuJammed ? " JAM" : "")")
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                StatusRow(label: "Drive CPU", value: "$\(hex16(status.drive.cpuPC))\(status.drive.cpuJammed ? " JAM" : "")")
                StatusRow(label: "LED / Motor", value: "\(onOff(status.drive.ledOn)) / \(onOff(status.drive.motorOn))")
                StatusRow(label: "Track", value: "\(status.drive.track)  half \(status.drive.halfTrack)")
                StatusRow(label: "Sync", value: "\(onOff(status.drive.syncDetected))  count \(status.drive.syncDetectionCount)")
                StatusRow(label: "Byte Ready", value: "\(onOff(status.drive.byteReady))  count \(status.drive.byteReadyCount)")
                StatusRow(label: "Port A Reads", value: "\(status.drive.via2PortAReadCount)")
                StatusRow(label: "IEC Bytes", value: status.drive.lastIECCommandSummary)
                StatusRow(label: "No Progress", value: "\(status.drive.noProgressCycleCount) cycles")
            }

            if let iec = status.drive.iec {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    StatusRow(label: "IEC Lines", value: "ATN \(line(iec.atnLine))  CLK \(line(iec.clockLine))  DATA \(line(iec.dataLine))")
                    StatusRow(label: "C64 Pulls", value: "ATN \(onOff(iec.c64Atn))  CLK \(onOff(iec.c64Clock))  DATA \(onOff(iec.c64Data))")
                    StatusRow(label: "Drive Pulls", value: "CLK \(onOff(iec.driveClock))  DATA \(onOff(iec.driveData))  ATNA \(onOff(iec.driveAtn))")
                }
            }

            if let unsupported = status.mediaCapabilities?.unsupportedFeatures, !unsupported.isEmpty {
                Divider()
                Text("Unsupported: \(unsupported.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }

    private var mediaDescription: String {
        guard let format = status.mountedDiskFormat else { return "none" }
        return format.displayName
    }

    private var capabilityDescription: String {
        guard let caps = status.mediaCapabilities else { return "none" }
        if caps.isNativeLowLevel {
            return "Native G64, \(caps.populatedHalfTrackCount) halftracks"
        }
        if caps.hasSyntheticGCR {
            return "Synthetic GCR, \(caps.populatedHalfTrackCount) halftracks"
        }
        return "\(caps.populatedHalfTrackCount) halftracks"
    }

    private func onOff(_ value: Bool) -> String {
        value ? "on" : "off"
    }

    private func line(_ high: Bool) -> String {
        high ? "high" : "low"
    }

    private func hex16(_ value: UInt16) -> String {
        String(format: "%04X", value)
    }
}

private struct StatusRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}

/// Controls the emulator lifecycle: ROM loading, audio, keyboard events.
final class EmulatorController: ObservableObject {
    let c64 = C64()
    var audioEngine: AVAudioEngine?
    var audioSourceNode: AVAudioSourceNode?
    /// Exposed so the debugger bridge can access snapshots.
    weak var renderer: MetalRenderer?

    @Published var hasMountedDisk = false
    @Published var emulationStatus: C64.EmulationStatus?

    init() {
        loadROMs()
        c64.powerOn()
        setupAudio()
        refreshStatus()
    }

    func refreshStatus() {
        emulationStatus = c64.emulationStatus
    }

    /// Load a file by auto-detecting its type from extension.
    func loadFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "d64", "g64":
            mountDisk(url)
        case "t64", "tap":
            if c64.mountTape(url) {
                refreshStatus()
                print("Tape mounted: \(url.lastPathComponent)")
            }
        case "prg", "p00":
            c64.loadPRG(url, autoRun: true)
            refreshStatus()
            print("PRG loaded: \(url.lastPathComponent)")
        default:
            // Try to guess: if < 200K, probably PRG; if ~170K, probably D64
            if let data = try? Data(contentsOf: url) {
                if data.count == 174848 || data.count == 175531 {
                    if c64.mountDisk(data) {
                        hasMountedDisk = true
                        refreshStatus()
                        print("Disk mounted (guessed): \(url.lastPathComponent)")
                    }
                } else if data.count >= 3 {
                    c64.loadPRG(data, autoRun: true)
                    refreshStatus()
                    print("PRG loaded (guessed): \(url.lastPathComponent)")
                }
            }
        }
    }

    func mountDisk(_ url: URL) {
        if c64.mountDisk(url) {
            hasMountedDisk = true
            refreshStatus()
            print("Disk mounted: \(url.lastPathComponent)")
        }
    }

    func loadROMs() {
        // Try Bundle.module first (SPM resource bundle)
        if let romsURL = Bundle.module.url(forResource: "ROMS", withExtension: nil) {
            loadROMsFromDirectory(romsURL)
            return
        }

        // Fallback: look relative to executable and working directory
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let candidates = [
            execDir.appendingPathComponent("C64_C64App.bundle/Contents/Resources/ROMS"),
            execDir.appendingPathComponent("ROMS"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/C64/ROMS"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Sources/C64App/ROMS"),
        ]

        for dir in candidates {
            if FileManager.default.fileExists(atPath: dir.path) {
                loadROMsFromDirectory(dir)
                return
            }
        }

        print("WARNING: Could not find ROM files. The emulator will not boot correctly.")
    }

    func loadROMsFromDirectory(_ dir: URL) {
        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            var basicData: Data?
            var kernalData: Data?
            var charData: Data?

            var driveROMData: Data?

            for file in files {
                let lower = file.lowercased()
                let path = dir.appendingPathComponent(file)
                if lower.contains("basic") {
                    basicData = try Data(contentsOf: path)
                } else if lower.contains("kernal") {
                    kernalData = try Data(contentsOf: path)
                } else if lower.contains("character") || lower.contains("char") {
                    charData = try Data(contentsOf: path)
                } else if lower.contains("1541") {
                    driveROMData = try Data(contentsOf: path)
                }
            }

            if let basic = basicData, let kernal = kernalData, let charset = charData {
                c64.loadROMs(basic: basic, kernal: kernal, charset: charset)
                print("ROMs loaded successfully from \(dir.path)")
            } else {
                print("WARNING: Not all ROM files found in \(dir.path)")
            }

            if let driveROM = driveROMData {
                c64.loadDriveROM(driveROM)
                print("1541 drive ROM loaded (\(driveROM.count) bytes)")
            }
        } catch {
            print("ERROR loading ROMs: \(error)")
        }
    }

    func setupAudio() {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        let sampleRate = SID.sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let sid = c64.sid

        audioSourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in bufferList {
                let frames = Int(frameCount)
                let ptr = buffer.mData!.bindMemory(to: Float.self, capacity: frames)
                for i in 0..<frames {
                    if sid.sampleReadPos != sid.sampleWritePos {
                        ptr[i] = sid.sampleBuffer[sid.sampleReadPos]
                        sid.sampleReadPos = (sid.sampleReadPos + 1) % sid.sampleBuffer.count
                    } else {
                        ptr[i] = 0
                    }
                }
            }
            return noErr
        }

        if let sourceNode = audioSourceNode {
            engine.attach(sourceNode)
            engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
            do {
                try engine.start()
            } catch {
                print("Audio engine failed to start: \(error)")
            }
        }
    }

    deinit {
        audioEngine?.stop()
    }
}

/// NSViewRepresentable wrapper for MTKView.
struct MetalView: NSViewRepresentable {
    let emulator: EmulatorController

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.preferredFramesPerSecond = 50  // PAL
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        // Register for drag & drop
        view.registerForDraggedTypes([.fileURL])

        let renderer = MetalRenderer(mtkView: view, c64: emulator.c64)
        view.delegate = renderer
        context.coordinator.renderer = renderer
        emulator.renderer = renderer

        // Set up keyboard event monitoring
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            return context.coordinator.handleKeyEvent(event)
        }

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(emulator: emulator)
    }

    class Coordinator {
        let emulator: EmulatorController
        var renderer: MetalRenderer?

        init(emulator: EmulatorController) {
            self.emulator = emulator
        }

        func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
            let c64 = emulator.c64

            switch event.type {
            case .keyDown:
                // Let menu shortcuts through (Cmd+key)
                if event.modifierFlags.contains(.command) {
                    return event
                }

                if !event.isARepeat {
                    if c64.keyboard.isRestoreKey(event.keyCode) {
                        c64.cpu.triggerNMI()
                        return nil
                    }
                    if c64.joystick.handleKeyDown(keyCode: event.keyCode) {
                        return nil
                    }
                    _ = c64.keyboard.handleKeyDown(keyCode: event.keyCode, characters: event.characters)
                }
                return nil

            case .keyUp:
                if event.modifierFlags.contains(.command) {
                    return event
                }
                if c64.joystick.handleKeyUp(keyCode: event.keyCode) {
                    return nil
                }
                _ = c64.keyboard.handleKeyUp(keyCode: event.keyCode, characters: event.characters)
                return nil

            case .flagsChanged:
                handleModifier(keyCode: event.keyCode, flags: event.modifierFlags)
                return nil

            default:
                return event
            }
        }

        func handleModifier(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
            let c64 = emulator.c64

            switch keyCode {
            case 56:
                if flags.contains(.shift) { _ = c64.keyboard.handleKeyDown(keyCode: 56) }
                else { _ = c64.keyboard.handleKeyUp(keyCode: 56) }
            case 60:
                if flags.contains(.shift) { _ = c64.keyboard.handleKeyDown(keyCode: 60) }
                else { _ = c64.keyboard.handleKeyUp(keyCode: 60) }
            case 59:
                if flags.contains(.control) { _ = c64.keyboard.handleKeyDown(keyCode: 59) }
                else { _ = c64.keyboard.handleKeyUp(keyCode: 59) }
            case 58:
                if flags.contains(.option) { _ = c64.keyboard.handleKeyDown(keyCode: 58) }
                else { _ = c64.keyboard.handleKeyUp(keyCode: 58) }
            default: break
            }
        }
    }
}
