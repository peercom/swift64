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
    @State private var isDropTargeted = false
    @State private var isFullScreen = false
    @State private var showingROMAssistant = false
    @AppStorage(PreferenceKey.showInspector) private var showInspector = false
    @AppStorage(PreferenceKey.showStatusBar) private var showStatusBar = true
    @AppStorage(PreferenceKey.romAssistantDismissed) private var romAssistantDismissed = false

    private let statusTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var status: C64.EmulationStatus {
        emulator.emulationStatus ?? emulator.c64.emulationStatus
    }

    var body: some View {
        NavigationStack {
            C64DisplayWorkspace(
                emulator: emulator,
                status: status,
                isDropTargeted: isDropTargeted,
                showsStatusBar: showStatusBar && !isFullScreen,
                romSetupState: emulator.romSetupState,
                showROMAssistant: showROMAssistantBadge,
                openDisk: openDisk,
                loadPRG: loadPRG,
                openROMAssistant: {
                    romAssistantDismissed = false
                    showingROMAssistant = true
                }
            )
            .ignoresSafeArea(isFullScreen ? .all : [], edges: .all)
            .navigationTitle(status.mountedDiskName ?? "Commodore 64")
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button("Open Disk Image...") { openDisk() }
                        Toggle("Write Protect D64", isOn: Binding(
                            get: { status.highLevelDiskWriteProtected },
                            set: { emulator.setMountedDiskWriteProtected($0) }
                        ))
                        .disabled(status.highLevelDiskFormat != .d64)
                        Button("Export Modified D64...") { exportModifiedD64() }
                            .disabled(!status.canExportModifiedD64 || !status.diskHasUnsavedChanges)
                        Button("Export Modified G64...") { exportModifiedG64() }
                            .disabled(!status.canExportModifiedG64 || !status.diskHasUnsavedChanges)
                        Button("Export Captured TAP...") { exportCapturedTAP() }
                            .disabled(!status.canExportCapturedTAP)
                        Button("Export Saved T64...") { exportSavedT64() }
                            .disabled(!status.canExportSavedT64 || !status.tapeHasUnsavedChanges)
                        Button("Open Tape Image...") { openTape() }
                        Button("Load Program...") { loadPRG() }
                        Button("Open Cartridge Image...") { openCartridge() }
                    } label: {
                        Label("Open", systemImage: "folder.badge.plus")
                    }
                    .help("Open C64 software or media")

                    Divider()

                    Menu {
                        ForEach(CompatibilityPresetPreference.allCases) { preset in
                            Button {
                                emulator.applyCompatibilityPreset(preset)
                            } label: {
                                Label(preset.title, systemImage: preset.systemImage)
                            }
                            .help(preset.subtitle)
                        }
                    } label: {
                        Label("Preset", systemImage: "slider.horizontal.3")
                    }
                    .help("Apply an emulation compatibility preset")

                    Toggle(isOn: Binding(
                        get: { emulator.c64.trueDriveEmulation },
                        set: { enabled in
                            emulator.setTrueDriveMode(enabled ? .compat1541 : .off)
                        }
                    )) {
                        Label(status.trueDriveMode == .off ? "Fast Load" : "True Drive 1541", systemImage: status.trueDriveMode == .off ? "bolt" : "externaldrive")
                    }
                    .toggleStyle(.button)
                    .help(status.trueDriveMode == .off ? "Fast Kernal-trap loading is active" : "Compatibility true-drive 1541 emulation is active")

                    Button(action: { showingDriveStatus.toggle() }) {
                        Label("Drive Status", systemImage: status.lastFailureReason == nil ? "gauge.with.dots.needle.67percent" : "exclamationmark.triangle")
                    }
                    .help("Show compact drive and media status")
                    .popover(isPresented: $showingDriveStatus, arrowEdge: .bottom) {
                        DriveStatusPopover(status: status)
                            .frame(width: 360)
                    }

                    Divider()

                    Button(action: { showInspector.toggle() }) {
                        Label("Inspector", systemImage: "sidebar.right")
                    }
                    .help(showInspector ? "Hide Inspector" : "Show Inspector")

                    Button(action: { openWindow(id: "debugger") }) {
                        Label("Debugger", systemImage: "ladybug")
                    }
                    .help("Show Debugger")

                    Button(action: reset) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .help("Reset C64")

                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Open emulator settings")
                }
            }
        }
        .frame(minWidth: 1040, minHeight: 680)
        .inspector(isPresented: inspectorBinding) {
            C64InspectorView(
                emulator: emulator,
                status: status,
                openDisk: openDisk,
                openTape: openTape,
                loadPRG: loadPRG,
                openCartridge: openCartridge,
                exportModifiedD64: exportModifiedD64,
                exportModifiedG64: exportModifiedG64,
                exportCapturedTAP: exportCapturedTAP,
                exportSavedT64: exportSavedT64,
                openDebugger: { openWindow(id: "debugger") },
                reset: reset,
                openROMAssistant: {
                    romAssistantDismissed = false
                    showingROMAssistant = true
                }
            )
            .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
        }
        .toolbar(isFullScreen ? .hidden : .visible, for: .windowToolbar)
        .background(WindowFullScreenObserver(isFullScreen: $isFullScreen).frame(width: 0, height: 0))
        .onChange(of: isFullScreen) { _, fullScreen in
            if fullScreen {
                showInspector = false
            }
        }
        .onReceive(statusTimer) { _ in
            emulator.refreshStatus()
            presentROMAssistantIfNeeded()
        }
        .sheet(isPresented: $showingROMAssistant) {
            ROMSetupAssistantView(emulator: emulator) {
                romAssistantDismissed = true
                showingROMAssistant = false
            }
        }
        .onAppear {
            presentROMAssistantIfNeeded()
        }
        .onChange(of: romAssistantDismissed) { _, dismissed in
            if !dismissed {
                presentROMAssistantIfNeeded(force: true)
            }
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { showInspector && !isFullScreen },
            set: { showInspector = $0 }
        )
    }

    private var showROMAssistantBadge: Bool {
        !emulator.romSetupState.isComplete
    }

    private func presentROMAssistantIfNeeded(force: Bool = false) {
        guard !emulator.romSetupState.isComplete else {
            showingROMAssistant = false
            return
        }
        if force || !romAssistantDismissed {
            showingROMAssistant = true
        }
    }

    func openDisk() {
        openFile(types: ["d64", "g64", "nib", "nbz", "p64"], title: "Open Disk Image") { url in
            emulator.mountDisk(url)
        }
    }

    func exportModifiedD64() {
        let panel = NSSavePanel()
        panel.title = "Export Modified D64"
        panel.allowedContentTypes = [.init(filenameExtension: "d64")].compactMap { $0 }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = emulator.suggestedModifiedD64Name

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try emulator.exportModifiedD64(to: url)
            } catch {
                print("Could not export modified D64: \(error.localizedDescription)")
            }
        }
    }

    func exportModifiedG64() {
        let panel = NSSavePanel()
        panel.title = "Export Modified G64"
        panel.allowedContentTypes = [.init(filenameExtension: "g64")].compactMap { $0 }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = emulator.suggestedModifiedG64Name

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try emulator.exportModifiedG64(to: url)
            } catch {
                print("Could not export modified G64: \(error.localizedDescription)")
            }
        }
    }

    func exportCapturedTAP() {
        let panel = NSSavePanel()
        panel.title = "Export Captured TAP"
        panel.allowedContentTypes = [.init(filenameExtension: "tap")].compactMap { $0 }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = emulator.suggestedCapturedTAPName

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try emulator.exportCapturedTAP(to: url)
            } catch {
                print("Could not export captured TAP: \(error.localizedDescription)")
            }
        }
    }

    func exportSavedT64() {
        let panel = NSSavePanel()
        panel.title = "Export Saved T64"
        panel.allowedContentTypes = [.init(filenameExtension: "t64")].compactMap { $0 }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = emulator.suggestedSavedT64Name

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try emulator.exportSavedT64(to: url)
            } catch {
                print("Could not export saved T64: \(error.localizedDescription)")
            }
        }
    }

    func openTape() {
        openFile(types: ["t64", "tap"], title: "Open Tape Image") { url in
            emulator.mountTape(url)
        }
    }

    func loadPRG() {
        openFile(types: ["prg", "p00"], title: "Load PRG Program") { url in
            emulator.c64.loadPRG(url, autoRun: true)
            emulator.refreshStatus()
            print("PRG loaded: \(url.lastPathComponent)")
        }
    }

    func openCartridge() {
        openFile(types: ["crt"], title: "Open Cartridge Image") { url in
            if emulator.c64.mountCartridge(url) {
                emulator.c64.reset()
                emulator.refreshStatus()
                print("Cartridge mounted: \(url.lastPathComponent)")
            }
        }
    }

    func reset() {
        emulator.c64.reset()
        emulator.powerDriveIfNeeded()
        emulator.refreshStatus()
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

private struct C64SidebarView: View {
    let status: C64.EmulationStatus
    let romStatusMessage: String
    let openDisk: () -> Void
    let openTape: () -> Void
    let loadPRG: () -> Void
    let openCartridge: () -> Void
    let openDebugger: () -> Void
    let reset: () -> Void

    var body: some View {
        List {
            Section("Media") {
                SidebarActionRow(
                    title: "Disk Image",
                    detail: status.mountedDiskName ?? "D64 or G64",
                    systemImage: "opticaldiscdrive",
                    action: openDisk
                )
                SidebarActionRow(
                    title: "Program",
                    detail: "PRG or P00",
                    systemImage: "doc.badge.gearshape",
                    action: loadPRG
                )
                SidebarActionRow(
                    title: "Tape",
                    detail: status.mountedTapeName ?? "T64 or TAP",
                    systemImage: "cassette",
                    action: openTape
                )
                SidebarActionRow(
                    title: "Cartridge",
                    detail: status.mountedCartridgeName ?? "CRT",
                    systemImage: "memorychip",
                    action: openCartridge
                )
            }

            Section("Machine") {
                SidebarValueRow(title: "CPU", value: "$\(hex16(status.cpuPC))\(status.cpuJammed ? " JAM" : "")", systemImage: status.cpuJammed ? "exclamationmark.triangle" : "cpu")
                SidebarValueRow(title: "ROMs", value: romStatusMessage, systemImage: romStatusMessage.lowercased().contains("not") || romStatusMessage.lowercased().contains("could not") ? "exclamationmark.circle" : "checkmark.circle")
                SidebarActionRow(
                    title: "Debugger",
                    detail: "CPU, memory, trace",
                    systemImage: "ladybug",
                    action: openDebugger
                )
                SidebarActionRow(
                    title: "Reset",
                    detail: "Restart the C64",
                    systemImage: "arrow.counterclockwise",
                    action: reset
                )
            }

            Section("Drive") {
                SidebarValueRow(title: "Mode", value: status.trueDriveMode.displayName, systemImage: status.trueDriveMode == .off ? "bolt" : "externaldrive")
                SidebarValueRow(title: "Media", value: mediaDescription, systemImage: status.mediaCapabilities?.isNativeLowLevel == true ? "waveform.path" : "square.stack.3d.down.right")
                SidebarValueRow(title: "LED / Motor", value: "\(onOff(status.drive.ledOn)) / \(onOff(status.drive.motorOn))", systemImage: status.drive.ledOn ? "record.circle" : "circle")
                SidebarValueRow(title: "Track", value: "\(status.drive.track)  half \(status.drive.halfTrack)", systemImage: "point.topleft.down.curvedto.point.bottomright.up")

                if let failure = status.lastFailureReason {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var mediaDescription: String {
        guard let format = status.mountedDiskFormat else { return "none" }
        if status.mediaCapabilities?.isNativeLowLevel == true {
            return "\(format.displayName), native"
        }
        if status.mediaCapabilities?.hasSyntheticGCR == true {
            return "\(format.displayName), synthetic GCR"
        }
        return format.displayName
    }

    private func onOff(_ value: Bool) -> String {
        value ? "on" : "off"
    }

    private func hex16(_ value: UInt16) -> String {
        String(format: "%04X", value)
    }

}

private struct SidebarActionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SidebarRowContent(title: title, detail: detail, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarValueRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        SidebarRowContent(title: title, detail: value, systemImage: systemImage)
    }
}

private struct SidebarRowContent: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct C64DisplayWorkspace: View {
    @ObservedObject var emulator: EmulatorController
    let status: C64.EmulationStatus
    let isDropTargeted: Bool
    let showsStatusBar: Bool
    let romSetupState: ROMSetupState
    let showROMAssistant: Bool
    let openDisk: () -> Void
    let loadPRG: () -> Void
    let openROMAssistant: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let displaySize = displaySize(for: proxy.size)

                ZStack {
                    Color.black

                    MetalView(emulator: emulator)
                        .frame(width: displaySize.width, height: displaySize.height)

                    if showROMAssistant {
                        VStack {
                            HStack {
                                ROMWarningBadge(state: romSetupState, action: openROMAssistant)
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(18)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay {
                if isDropTargeted {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 34, weight: .semibold))
                        Text("Drop C64 media")
                            .font(.headline)
                        Text("D64, G64, NIB, NBZ, P64, T64, TAP, PRG, P00, CRT")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsStatusBar {
                    C64StatusBar(status: status, romStatusMessage: emulator.romStatusMessage)
                }
            }
        }
        .background(.black)
        .contextMenu {
            Button("Open Disk Image...") { openDisk() }
            Button("Load Program...") { loadPRG() }
            Divider()
            Button("ROM Setup...") { openROMAssistant() }
        }
    }

    private func displaySize(for container: CGSize) -> CGSize {
        let ratio = CGFloat(403.0 / 284.0)
        let availableWidth = max(container.width - 36, 1)
        let availableHeight = max(container.height - 36, 1)
        let widthFromHeight = availableHeight * ratio

        if widthFromHeight <= availableWidth {
            return CGSize(width: widthFromHeight, height: availableHeight)
        }

        return CGSize(width: availableWidth, height: availableWidth / ratio)
    }
}

private struct WindowFullScreenObserver: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window, isFullScreen: $isFullScreen)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window, isFullScreen: $isFullScreen)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var observedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []

        func attach(to window: NSWindow?, isFullScreen: Binding<Bool>) {
            guard let window, observedWindow !== window else {
                if let window {
                    isFullScreen.wrappedValue = window.styleMask.contains(.fullScreen)
                }
                return
            }

            removeObservers()
            observedWindow = window
            isFullScreen.wrappedValue = window.styleMask.contains(.fullScreen)

            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { _ in
                isFullScreen.wrappedValue = true
            })
            observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { _ in
                isFullScreen.wrappedValue = false
            })
        }

        deinit {
            removeObservers()
        }

        private func removeObservers() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
        }
    }
}

private struct C64StatusBar: View {
    let status: C64.EmulationStatus
    let romStatusMessage: String

    var body: some View {
        HStack(spacing: 14) {
            StatusPill(title: "Mode", value: status.trueDriveMode == .off ? "Fast Load" : status.trueDriveMode.displayName, systemImage: status.trueDriveMode == .off ? "bolt" : "externaldrive")
            StatusPill(title: "Disk", value: status.mountedDiskName ?? "none", systemImage: "opticaldiscdrive")
            StatusPill(title: "Drive", value: "LED \(onOff(status.drive.ledOn))  Motor \(onOff(status.drive.motorOn))", systemImage: status.drive.ledOn ? "record.circle.fill" : "circle")

            Spacer(minLength: 8)

            if let failure = status.lastFailureReason {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                Label(romStatusSummary, systemImage: romStatusIcon)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var romStatusSummary: String {
        romStatusMessage
            .replacingOccurrences(of: "ROM files are not configured. ", with: "")
            .replacingOccurrences(of: "Set BASIC, Kernal, Characters, and 1541 paths in Settings.", with: "ROMs need setup")
    }

    private var romStatusIcon: String {
        romStatusMessage.lowercased().contains("not") || romStatusMessage.lowercased().contains("could not") ? "exclamationmark.circle" : "checkmark.circle"
    }

    private func onOff(_ value: Bool) -> String {
        value ? "on" : "off"
    }
}

private struct StatusPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text(title)
                    .foregroundStyle(.secondary)
                Text(value)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: systemImage)
        }
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
                StatusRow(label: "Tape", value: status.mountedTapeName ?? "none")
                StatusRow(label: "Cartridge", value: status.mountedCartridgeName ?? "none")
                StatusRow(label: "Media", value: mediaDescription)
                StatusRow(label: "Fast Media", value: highLevelMediaDescription)
                StatusRow(label: "Modified", value: modifiedDescription)
                StatusRow(label: "Write Protect", value: status.highLevelDiskWriteProtected ? "on" : "off")
                StatusRow(label: "DOS Exec", value: highLevelDriveExecuteDescription)
                StatusRow(label: "Tape Capture", value: tapeCaptureDescription)
                StatusRow(label: "Tape Save", value: tapeSaveDescription)
                StatusRow(label: "Tape Decode", value: tapeDecodeDescription)
                StatusRow(label: "Tape Signal", value: tapeSignalDescription)
                StatusRow(label: "Capability", value: capabilityDescription)
                StatusRow(label: "CPU", value: "$\(hex16(status.cpuPC))\(status.cpuJammed ? " JAM" : "")")
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                StatusRow(label: "Drive CPU", value: "$\(hex16(status.drive.cpuPC))\(status.drive.cpuJammed ? " JAM" : "")")
                StatusRow(label: "LED / Motor", value: "\(onOff(status.drive.ledOn)) / \(onOff(status.drive.motorOn))")
                StatusRow(label: "Track", value: "\(status.drive.track)  half \(status.drive.halfTrack)")
                StatusRow(label: "Head Bit", value: "\(status.drive.headBitPosition)")
                StatusRow(label: "Read Track", value: readTrackDescription)
                StatusRow(label: "Sync", value: "\(onOff(status.drive.syncDetected))  count \(status.drive.syncDetectionCount)")
                StatusRow(label: "Byte Ready", value: "\(onOff(status.drive.byteReady))  count \(status.drive.byteReadyCount)")
                StatusRow(label: "Weak Bits", value: "\(status.drive.weakBitReadCount)")
                StatusRow(label: "Speed Zones", value: "\(status.drive.variableSpeedZoneSampleCount)  mask $\(hex8(status.drive.variableSpeedZoneMask))")
                StatusRow(label: "Write Head", value: "\(onOff(status.drive.gcrWriteModeActive))  count \(status.drive.gcrWriteByteCount)  splices \(status.drive.gcrWriteSpliceCount)  erase \(status.drive.gcrWriteEraseBitCount)")
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

    private var highLevelMediaDescription: String {
        status.highLevelDiskFormat?.displayName ?? "none"
    }

    private var readTrackDescription: String {
        guard let readTrack = status.drive.readTrack,
              let readHalfTrack = status.drive.readHalfTrack else {
            return "none"
        }
        let fallback = status.drive.usingHalfTrackFallback ? " fallback" : ""
        return "\(readTrack)  half \(readHalfTrack)\(fallback)"
    }

    private var modifiedDescription: String {
        if status.diskHasUnsavedChanges {
            if status.d64ExportBlockedByLowLevelWrites {
                return "yes, raw D64 changes"
            }
            if status.canExportModifiedD64 {
                return "yes, exportable D64"
            }
            if status.canExportModifiedG64 {
                return "yes, exportable G64"
            }
            return "yes"
        }
        return "no"
    }

    private var highLevelDriveExecuteDescription: String {
        guard let address = status.highLevelDriveExecuteAddress else { return "none" }
        return "$\(hex16(address))"
    }

    private var tapeCaptureDescription: String {
        if status.tapeHasCapturedWritePulses {
            return status.canExportCapturedTAP ? "yes, exportable TAP" : "yes"
        }
        return "no"
    }

    private var tapeSaveDescription: String {
        if status.tapeHasUnsavedChanges {
            return status.canExportSavedT64 ? "yes, exportable T64" : "yes"
        }
        return "no"
    }

    private var tapeDecodeDescription: String {
        switch status.tapeDecodeStatus {
        case .none:
            return "none"
        case let .rawPulsesOnly(pulseCount):
            return "raw pulses, \(pulseCount)"
        case let .decodedPrograms(programCount, pulseCount):
            return "\(programCount) program\(programCount == 1 ? "" : "s"), \(pulseCount) pulses"
        case let .standardCBMNoPrograms(blockCount, reason):
            return "\(blockCount) block\(blockCount == 1 ? "" : "s"), \(tapeFailureDescription(reason))"
        }
    }

    private var tapeSignalDescription: String {
        "\(status.tapeRawPlaybackActive ? "play" : "stop")  read \(line(status.tapeReadSignalHigh))  sense \(line(status.cassetteSenseLineHigh))  motor \(onOff(status.cassetteMotorEnabled))"
    }

    private func tapeFailureDescription(_ reason: TapeUnit.TAPDecodeFailureReason) -> String {
        switch reason {
        case .noStandardBlocks:
            return "no CBM blocks"
        case .malformedStandardBlocks:
            return "malformed blocks"
        case .incompleteHeaderData:
            return "incomplete data"
        case .conflictingDuplicateData:
            return "conflicting copies"
        }
    }

    private var capabilityDescription: String {
        guard let caps = status.mediaCapabilities else { return "none" }
        var suffixes: [String] = []
        if caps.preservesVariableSpeedZones {
            suffixes.append("variable speed")
        }
        if caps.preservesSectorErrorInfo {
            let nonDefault = caps.nonDefaultSectorErrorCodeCount
            suffixes.append(nonDefault > 0 ? "error table \(nonDefault)" : "error table")
        }
        if caps.hasDuplicateSectorHeaders {
            suffixes.append("duplicate headers \(caps.duplicateSectorHeaderCount)")
        }
        if caps.weakBitRangeCount > 0 {
            let label = caps.preservesWeakBitRanges ? "weak ranges" : "volatile weak ranges"
            suffixes.append("\(label) \(caps.weakBitRangeCount)")
        }
        let suffix = suffixes.isEmpty ? "" : ", \(suffixes.joined(separator: ", "))"
        if caps.isNativeLowLevel {
            return "Native G64, \(caps.populatedHalfTrackCount) halftracks\(suffix)"
        }
        if caps.hasSyntheticGCR {
            return "Synthetic GCR, \(caps.populatedHalfTrackCount) halftracks\(suffix)"
        }
        return "\(caps.populatedHalfTrackCount) halftracks\(suffix)"
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

    private func hex8(_ value: UInt8) -> String {
        String(format: "%02X", value)
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

struct ROMSetupState {
    struct Item: Identifiable {
        let id: String
        let title: String
        let path: String
        let bookmarkKey: String
        let importedPathKey: String
        let storedFileName: String
        let required: Bool
        let expectedSize: Int

        var isConfigured: Bool {
            let defaults = UserDefaults.standard
            if let importedPath = defaults.string(forKey: importedPathKey),
               !importedPath.isEmpty,
               FileManager.default.isReadableFile(atPath: importedPath) {
                return true
            }
            if !path.isEmpty, FileManager.default.isReadableFile(atPath: path) {
                return true
            }
            return defaults.data(forKey: bookmarkKey) != nil
        }

        var statusText: String {
            if let importedPath = UserDefaults.standard.string(forKey: importedPathKey),
               !importedPath.isEmpty,
               FileManager.default.isReadableFile(atPath: importedPath) {
                return "Imported"
            }
            if isConfigured {
                return "Configured"
            }
            return required ? "Required" : "Optional"
        }
    }

    let items: [Item]

    var requiredItems: [Item] {
        items.filter(\.required)
    }

    var missingRequiredCount: Int {
        requiredItems.filter { !$0.isConfigured }.count
    }

    var isComplete: Bool {
        missingRequiredCount == 0
    }

    var driveROMConfigured: Bool {
        items.first { $0.id == "drive1541" }?.isConfigured == true
    }

    var summary: String {
        if isComplete && driveROMConfigured {
            return "C64 and 1541 ROMs are ready."
        }
        if isComplete {
            return "C64 ROMs are ready. 1541 ROM is optional until true-drive mode is used."
        }
        return "\(missingRequiredCount) required ROM\(missingRequiredCount == 1 ? "" : "s") missing."
    }
}

private struct ROMWarningBadge: View {
    let state: ROMSetupState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(state.summary, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.yellow)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Open ROM setup")
    }
}

private struct C64InspectorView: View {
    @ObservedObject var emulator: EmulatorController
    let status: C64.EmulationStatus
    let openDisk: () -> Void
    let openTape: () -> Void
    let loadPRG: () -> Void
    let openCartridge: () -> Void
    let exportModifiedD64: () -> Void
    let exportModifiedG64: () -> Void
    let exportCapturedTAP: () -> Void
    let exportSavedT64: () -> Void
    let openDebugger: () -> Void
    let reset: () -> Void
    let openROMAssistant: () -> Void

    @State private var tab: InspectorTab = .media
    @State private var showsAdvancedDrive = false

    enum InspectorTab: String, CaseIterable, Identifiable {
        case media = "Media"
        case machine = "Machine"
        case drive = "Drive"
        case audio = "Audio"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .media: return "externaldrive"
            case .machine: return "memorychip"
            case .drive: return "opticaldiscdrive"
            case .audio: return "speaker.wave.2"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $tab) {
                ForEach(InspectorTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .media:
                        mediaPanel
                    case .machine:
                        machinePanel
                    case .drive:
                        drivePanel
                    case .audio:
                        audioPanel
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.bar)
    }

    private var mediaPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection("Mounted Media") {
                InspectorRow("Disk", status.mountedDiskName ?? "none", systemImage: "opticaldiscdrive")
                InspectorRow("Tape", status.mountedTapeName ?? "none", systemImage: "cassette")
                InspectorRow("Cartridge", status.mountedCartridgeName ?? "none", systemImage: "memorychip")
                InspectorRow("Format", status.mountedDiskFormat?.displayName ?? "none", systemImage: "square.stack.3d.down.right")
            }

            InspectorSection("Open") {
                InspectorButtonGrid {
                    Button("Disk", systemImage: "opticaldiscdrive", action: openDisk)
                    Button("PRG", systemImage: "doc.badge.gearshape", action: loadPRG)
                    Button("Tape", systemImage: "cassette", action: openTape)
                    Button("CRT", systemImage: "memorychip", action: openCartridge)
                }
            }

            InspectorSection("Write / Export") {
                Toggle("Write Protect D64", isOn: Binding(
                    get: { status.highLevelDiskWriteProtected },
                    set: { emulator.setMountedDiskWriteProtected($0) }
                ))
                .disabled(status.highLevelDiskFormat != .d64)

                InspectorButtonGrid {
                    Button("Export D64", action: exportModifiedD64)
                        .disabled(!status.canExportModifiedD64 || !status.diskHasUnsavedChanges)
                    Button("Export G64", action: exportModifiedG64)
                        .disabled(!status.canExportModifiedG64 || !status.diskHasUnsavedChanges)
                    Button("Export TAP", action: exportCapturedTAP)
                        .disabled(!status.canExportCapturedTAP)
                    Button("Export T64", action: exportSavedT64)
                        .disabled(!status.canExportSavedT64 || !status.tapeHasUnsavedChanges)
                }
            }

            if !emulator.romSetupState.isComplete {
                InspectorSection("ROMs") {
                    Label(emulator.romSetupState.summary, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Open ROM Setup", systemImage: "folder.badge.gearshape", action: openROMAssistant)
                }
            }
        }
    }

    private var machinePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection("Preset") {
                ForEach(CompatibilityPresetPreference.allCases) { preset in
                    Button {
                        emulator.applyCompatibilityPreset(preset)
                    } label: {
                        Label(preset.title, systemImage: preset.systemImage)
                    }
                    .help(preset.subtitle)
                }
            }

            InspectorSection("Current") {
                InspectorRow("Profile", emulator.machineSummary.profile, systemImage: "desktopcomputer")
                InspectorRow("Drive", status.trueDriveMode.displayName, systemImage: status.trueDriveMode == .off ? "bolt" : "externaldrive")
                InspectorRow("SID", emulator.machineSummary.sid, systemImage: "waveform")
                InspectorRow("Joystick", emulator.machineSummary.joystick, systemImage: "gamecontroller")
            }

            InspectorSection("Actions") {
                Toggle("True Drive 1541 Compat", isOn: Binding(
                    get: { emulator.c64.trueDriveEmulation },
                    set: { emulator.setTrueDriveMode($0 ? .compat1541 : .off) }
                ))
                Button("Reset C64", systemImage: "arrow.counterclockwise", action: reset)
                Button("Open Debugger", systemImage: "ladybug", action: openDebugger)
            }
        }
    }

    private var drivePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let failure = status.lastFailureReason {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            InspectorSection("1541") {
                InspectorRow("CPU", "$\(hex16(status.drive.cpuPC))\(status.drive.cpuJammed ? " JAM" : "")", systemImage: status.drive.cpuJammed ? "exclamationmark.triangle" : "cpu")
                InspectorRow("LED / Motor", "\(onOff(status.drive.ledOn)) / \(onOff(status.drive.motorOn))", systemImage: status.drive.ledOn ? "record.circle.fill" : "circle")
                InspectorRow("Track", "\(status.drive.track) half \(status.drive.halfTrack)", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                InspectorRow("Sync", "\(onOff(status.drive.syncDetected)) count \(status.drive.syncDetectionCount)", systemImage: "waveform.path")
                InspectorRow("Byte Ready", "\(onOff(status.drive.byteReady)) count \(status.drive.byteReadyCount)", systemImage: "arrow.left.arrow.right")
            }

            DisclosureGroup("Advanced", isExpanded: $showsAdvancedDrive) {
                VStack(alignment: .leading, spacing: 8) {
                    InspectorRow("Head Bit", "\(status.drive.headBitPosition)", systemImage: "smallcircle.filled.circle")
                    InspectorRow("Port A Reads", "\(status.drive.via2PortAReadCount)", systemImage: "number")
                    InspectorRow("Weak Bits", "\(status.drive.weakBitReadCount)", systemImage: "sparkles")
                    InspectorRow("Speed Zones", "\(status.drive.variableSpeedZoneSampleCount) mask $\(hex8(status.drive.variableSpeedZoneMask))", systemImage: "speedometer")
                    InspectorRow("IEC Bytes", status.drive.lastIECCommandSummary, systemImage: "cable.connector")
                    InspectorRow("No Progress", "\(status.drive.noProgressCycleCount) cycles", systemImage: "clock")
                }
                .padding(.top, 8)
            }
        }
    }

    private var audioPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorSection("SID") {
                InspectorRow("Model", emulator.machineSummary.sid, systemImage: "waveform")
                InspectorRow("Accuracy", emulator.c64.sid.accuracyMode.rawValue, systemImage: "slider.horizontal.3")
                InspectorRow("Underruns", "\(emulator.audioUnderrunFrames)", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            }

            InspectorSection("Display") {
                Toggle("CRT Shader", isOn: Binding(
                    get: { emulator.crtShaderEnabled },
                    set: { enabled in
                        UserDefaults.standard.set(enabled, forKey: PreferenceKey.crtShaderEnabled)
                        emulator.applyDisplayPreferences()
                    }
                ))
                HStack {
                    Text("Intensity")
                    Slider(value: Binding(
                        get: { Double(emulator.crtShaderIntensity) },
                        set: { value in
                            UserDefaults.standard.set(value, forKey: PreferenceKey.crtShaderIntensity)
                            emulator.applyDisplayPreferences()
                        }
                    ), in: 0...1)
                }
                .disabled(!emulator.crtShaderEnabled)
            }
        }
    }

    private func onOff(_ value: Bool) -> String {
        value ? "on" : "off"
    }

    private func hex16(_ value: UInt16) -> String {
        String(format: "%04X", value)
    }

    private func hex8(_ value: UInt8) -> String {
        String(format: "%02X", value)
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

private struct InspectorRow: View {
    let title: String
    let value: String
    let systemImage: String

    init(_ title: String, _ value: String, systemImage: String) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .font(.caption)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }
}

private struct InspectorButtonGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
            content
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private struct ROMSetupAssistantView: View {
    @ObservedObject var emulator: EmulatorController
    let dismiss: () -> Void

    @AppStorage(PreferenceKey.basicROMPath) private var basicROMPath = ""
    @AppStorage(PreferenceKey.kernalROMPath) private var kernalROMPath = ""
    @AppStorage(PreferenceKey.characterROMPath) private var characterROMPath = ""
    @AppStorage(PreferenceKey.driveROMPath) private var driveROMPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: emulator.romSetupState.isComplete ? "checkmark.seal.fill" : "folder.badge.gearshape")
                    .font(.largeTitle)
                    .foregroundStyle(emulator.romSetupState.isComplete ? .green : .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("ROM Setup")
                        .font(.title2.weight(.semibold))
                    Text(emulator.romSetupState.summary)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 10) {
                ForEach(emulator.romSetupState.items) { item in
                    ROMSetupRow(item: item) {
                        chooseROM(item)
                    } clear: {
                        clearROM(item)
                    }
                }
            }

            Text("Swift64 cannot distribute Commodore ROMs. Choose your own ROM files once; Swift64 imports private sandbox-safe copies for future launches.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Later") {
                    dismiss()
                }
                Button {
                    applyROMs()
                } label: {
                    Label("Apply", systemImage: "checkmark")
                }
                Button("OK") {
                    applyROMs()
                    if emulator.romSetupState.isComplete {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
    }

    private func chooseROM(_ item: ROMSetupState.Item) {
        let panel = NSOpenPanel()
        panel.title = "Choose \(item.title) ROM"
        panel.message = "Choose the \(item.title) ROM so Swift64 can import a private copy."
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try ROMFileStore.importAuthorizedROM(
                from: url,
                bookmarkKey: item.bookmarkKey,
                importedPathKey: item.importedPathKey,
                storedFileName: item.storedFileName
            )
            setPath(url.path, for: item)
            emulator.romStatusMessage = "\(item.title) ROM imported."
        } catch {
            emulator.romStatusMessage = "Could not import \(item.title) ROM: \(error.localizedDescription)"
        }
    }

    private func clearROM(_ item: ROMSetupState.Item) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: item.bookmarkKey)
        defaults.removeObject(forKey: item.importedPathKey)
        setPath("", for: item)
        emulator.romStatusMessage = "\(item.title) ROM configuration cleared."
    }

    private func applyROMs() {
        emulator.reloadROMs(reset: true)
    }

    private func setPath(_ path: String, for item: ROMSetupState.Item) {
        switch item.id {
        case "basic": basicROMPath = path
        case "kernal": kernalROMPath = path
        case "characters": characterROMPath = path
        case "drive1541": driveROMPath = path
        default: break
        }
    }
}

private struct ROMSetupRow: View {
    let item: ROMSetupState.Item
    let choose: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isConfigured ? "checkmark.circle.fill" : (item.required ? "exclamationmark.circle.fill" : "circle"))
                .foregroundStyle(item.isConfigured ? .green : (item.required ? .orange : .secondary))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                Text(item.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose", action: choose)
            Button("Clear", action: clear)
                .disabled(!item.isConfigured)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MediaSummary {
    let disk: String
    let tape: String
    let cartridge: String
    let diskFormat: String
    let hasUnsavedChanges: Bool
}

struct MachineSummary {
    let profile: String
    let drive: String
    let sid: String
    let joystick: String
}

/// Controls the emulator lifecycle: ROM loading, audio, keyboard events.
final class EmulatorController: ObservableObject {
    let c64 = C64()
    var audioEngine: AVAudioEngine?
    var audioSourceNode: AVAudioSourceNode?
    var audioUnderrunFrames: UInt64 = 0
    /// Exposed so the debugger bridge can access snapshots.
    var renderer: MetalRenderer?

    @Published var hasMountedDisk = false
    @Published var emulationStatus: C64.EmulationStatus?
    @Published var romStatusMessage = "ROM paths are not configured."
    @Published var displayFramesPerSecond = MachineProfile.palC64.displayFramesPerSecond
    @Published var crtShaderEnabled = false
    @Published var crtShaderIntensity: Float = 0.65

    var suggestedModifiedD64Name: String {
        guard let name = c64.emulationStatus.mountedDiskName else {
            return "modified.d64"
        }

        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        return "\(base)-modified.d64"
    }

    var suggestedModifiedG64Name: String {
        guard let name = c64.emulationStatus.mountedDiskName else {
            return "modified.g64"
        }

        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        return "\(base)-modified.g64"
    }

    var suggestedCapturedTAPName: String {
        "captured-tape.tap"
    }

    var suggestedSavedT64Name: String {
        guard let name = c64.emulationStatus.mountedTapeName else {
            return "saved-tape.t64"
        }

        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        return "\(base)-saved.t64"
    }

    var romSetupState: ROMSetupState {
        let defaults = UserDefaults.standard
        return ROMSetupState(items: [
            ROMSetupState.Item(
                id: "basic",
                title: "BASIC",
                path: defaults.string(forKey: PreferenceKey.basicROMPath) ?? "",
                bookmarkKey: PreferenceKey.basicROMBookmark,
                importedPathKey: PreferenceKey.basicROMImportedPath,
                storedFileName: "basic.rom",
                required: true,
                expectedSize: 8192
            ),
            ROMSetupState.Item(
                id: "kernal",
                title: "Kernal",
                path: defaults.string(forKey: PreferenceKey.kernalROMPath) ?? "",
                bookmarkKey: PreferenceKey.kernalROMBookmark,
                importedPathKey: PreferenceKey.kernalROMImportedPath,
                storedFileName: "kernal.rom",
                required: true,
                expectedSize: 8192
            ),
            ROMSetupState.Item(
                id: "characters",
                title: "Characters",
                path: defaults.string(forKey: PreferenceKey.characterROMPath) ?? "",
                bookmarkKey: PreferenceKey.characterROMBookmark,
                importedPathKey: PreferenceKey.characterROMImportedPath,
                storedFileName: "characters.rom",
                required: true,
                expectedSize: 4096
            ),
            ROMSetupState.Item(
                id: "drive1541",
                title: "1541 Drive",
                path: defaults.string(forKey: PreferenceKey.driveROMPath) ?? "",
                bookmarkKey: PreferenceKey.driveROMBookmark,
                importedPathKey: PreferenceKey.driveROMImportedPath,
                storedFileName: "1541.rom",
                required: false,
                expectedSize: 16384
            ),
        ])
    }

    var mediaSummary: MediaSummary {
        let status = c64.emulationStatus
        return MediaSummary(
            disk: status.mountedDiskName ?? "none",
            tape: status.mountedTapeName ?? "none",
            cartridge: status.mountedCartridgeName ?? "none",
            diskFormat: status.mountedDiskFormat?.displayName ?? "none",
            hasUnsavedChanges: status.diskHasUnsavedChanges || status.tapeHasUnsavedChanges
        )
    }

    var machineSummary: MachineSummary {
        let defaults = UserDefaults.standard
        let profileID = defaults.string(forKey: PreferenceKey.machineProfile) ?? MachineProfilePreference.palC64.rawValue
        let modeID = defaults.string(forKey: PreferenceKey.trueDriveMode) ?? TrueDriveModePreference.off.rawValue
        let sidModelID = defaults.string(forKey: PreferenceKey.sidModel) ?? SIDModelPreference.profileDefault.rawValue
        let sidAccuracyID = defaults.string(forKey: PreferenceKey.sidAccuracyMode) ?? SIDAccuracyModePreference.fast.rawValue
        let joystickID = defaults.string(forKey: PreferenceKey.joystickRouting) ?? JoystickRoutingPreference.both.rawValue
        let profile = MachineProfilePreference(rawValue: profileID) ?? .palC64
        let drive = TrueDriveModePreference(rawValue: modeID) ?? .off
        let sidModel = SIDModelPreference(rawValue: sidModelID) ?? .profileDefault
        let sidAccuracy = SIDAccuracyModePreference(rawValue: sidAccuracyID) ?? .fast
        let joystick = JoystickRoutingPreference(rawValue: joystickID) ?? .both

        return MachineSummary(
            profile: profile.title,
            drive: drive.title,
            sid: "\(sidModel.title), \(sidAccuracy.title)",
            joystick: joystick.title
        )
    }

    init() {
        c64.vic.recordsBusAccessTraces = false
        migrateLegacyPreferencesIfNeeded()
        applyEmulationPreferences(reset: false, powerDrive: false)
        applyDisplayPreferences()
        reloadROMs(reset: false)
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
        case "d64", "g64", "nib", "nbz", "p64":
            mountDisk(url)
        case "t64", "tap":
            mountTape(url)
        case "prg", "p00":
            c64.loadPRG(url, autoRun: true)
            refreshStatus()
            print("PRG loaded: \(url.lastPathComponent)")
        case "crt":
            if c64.mountCartridge(url) {
                c64.reset()
                refreshStatus()
                print("Cartridge mounted: \(url.lastPathComponent)")
            }
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
        do {
            let data = try readUserSelectedFile(url)
            guard c64.mountDisk(data, fileName: url.lastPathComponent) else {
                print("Could not mount disk image: \(url.lastPathComponent)")
                return
            }
            hasMountedDisk = true
            refreshStatus()
            print("Disk mounted: \(url.lastPathComponent)")
        } catch {
            print("Could not read disk image \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func setMountedDiskWriteProtected(_ protected: Bool) {
        c64.setMountedDiskWriteProtected(protected)
        refreshStatus()
    }

    func mountTape(_ url: URL) {
        do {
            let data = try readUserSelectedFile(url)
            guard c64.mountTape(data, fileName: url.lastPathComponent) else {
                print("Could not mount tape image: \(url.lastPathComponent)")
                return
            }
            refreshStatus()
            print("Tape mounted: \(url.lastPathComponent)")
        } catch {
            print("Could not read tape image \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func exportModifiedD64(to url: URL) throws {
        guard let data = c64.exportedD64Image else {
            throw CocoaError(.fileNoSuchFile)
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        try data.write(to: url, options: .atomic)
        c64.markExportedD64ImageSaved()
        refreshStatus()
        print("Modified D64 exported: \(url.lastPathComponent)")
    }

    func exportModifiedG64(to url: URL) throws {
        guard let data = c64.exportedG64Image else {
            throw CocoaError(.fileNoSuchFile)
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        try data.write(to: url, options: .atomic)
        let markedSaved = c64.markExportedG64ImageSaved()
        refreshStatus()
        if markedSaved {
            print("Modified G64 exported: \(url.lastPathComponent)")
        } else {
            print("Modified G64 snapshot exported: \(url.lastPathComponent)")
        }
    }

    func exportCapturedTAP(to url: URL) throws {
        guard let data = c64.exportedCapturedTAPImage() else {
            throw CocoaError(.fileNoSuchFile)
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        try data.write(to: url, options: .atomic)
        c64.clearCapturedTapeWritePulses()
        refreshStatus()
        print("Captured TAP exported: \(url.lastPathComponent)")
    }

    func exportSavedT64(to url: URL) throws {
        guard let data = c64.exportedT64Image else {
            throw CocoaError(.fileNoSuchFile)
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        try data.write(to: url, options: .atomic)
        c64.markExportedT64ImageSaved()
        refreshStatus()
        print("Saved T64 exported: \(url.lastPathComponent)")
    }

    private func readUserSelectedFile(_ url: URL) throws -> Data {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
    }

    func setTrueDriveMode(_ mode: TrueDriveEmulationMode) {
        let preference: TrueDriveModePreference
        switch mode {
        case .off: preference = .off
        case .standard1541: preference = .standard1541
        case .compat1541: preference = .compat1541
        }
        UserDefaults.standard.set(preference.rawValue, forKey: PreferenceKey.trueDriveMode)
        c64.trueDriveEmulationMode = mode
        powerDriveIfNeeded()
        print(mode == .off ? "True drive emulation disabled (using Kernal traps)" : "\(mode.displayName) enabled")
        refreshStatus()
    }

    func applyCompatibilityPreset(_ preset: CompatibilityPresetPreference, reset: Bool = true) {
        let defaults = UserDefaults.standard
        if let machineProfile = preset.machineProfile {
            defaults.set(machineProfile.rawValue, forKey: PreferenceKey.machineProfile)
        }
        defaults.set(preset.trueDriveMode.rawValue, forKey: PreferenceKey.trueDriveMode)
        defaults.set(preset.sidModel.rawValue, forKey: PreferenceKey.sidModel)
        defaults.set(preset.sidAccuracyMode.rawValue, forKey: PreferenceKey.sidAccuracyMode)
        defaults.set(preset.crtShaderEnabled, forKey: PreferenceKey.crtShaderEnabled)
        defaults.set(preset.crtShaderIntensity, forKey: PreferenceKey.crtShaderIntensity)

        applyEmulationPreferences(reset: reset)
        applyDisplayPreferences()
        print("Applied compatibility preset: \(preset.title)")
    }

    func applyEmulationPreferences(reset: Bool, powerDrive: Bool = true) {
        let defaults = UserDefaults.standard
        let profileID = defaults.string(forKey: PreferenceKey.machineProfile) ?? MachineProfilePreference.palC64.rawValue
        let modeID = defaults.string(forKey: PreferenceKey.trueDriveMode) ?? TrueDriveModePreference.off.rawValue
        let sidModelID = defaults.string(forKey: PreferenceKey.sidModel) ?? SIDModelPreference.profileDefault.rawValue
        let sidAccuracyModeID = defaults.string(forKey: PreferenceKey.sidAccuracyMode) ?? SIDAccuracyModePreference.fast.rawValue
        let joystickID = defaults.string(forKey: PreferenceKey.joystickRouting) ?? JoystickRoutingPreference.both.rawValue
        let profile = MachineProfilePreference(rawValue: profileID) ?? .palC64
        let mode = TrueDriveModePreference(rawValue: modeID) ?? .off
        let sidModel = SIDModelPreference(rawValue: sidModelID) ?? .profileDefault
        let sidAccuracyMode = SIDAccuracyModePreference(rawValue: sidAccuracyModeID) ?? .fast
        let joystickRouting = JoystickRoutingPreference(rawValue: joystickID) ?? .both

        c64.machineProfile = profile.profile
        c64.sidModelOverride = sidModel.model
        c64.sid.accuracyMode = sidAccuracyMode.mode
        displayFramesPerSecond = profile.profile.displayFramesPerSecond
        c64.trueDriveEmulationMode = mode.mode
        c64.joystick.routing = joystickRouting.routing
        if reset {
            c64.reset()
        }
        if powerDrive {
            powerDriveIfNeeded()
        }
        refreshStatus()
        print("Applied emulation settings: \(profile.title), \(mode.title), SID \(sidModel.title)/\(sidAccuracyMode.title), joystick \(joystickRouting.title)")
    }

    func applyDisplayPreferences() {
        let defaults = UserDefaults.standard
        crtShaderEnabled = defaults.bool(forKey: PreferenceKey.crtShaderEnabled)
        let storedIntensity = defaults.object(forKey: PreferenceKey.crtShaderIntensity) as? Double ?? 0.65
        crtShaderIntensity = Float(min(max(storedIntensity, 0.0), 1.0))
        renderer?.crtShaderEnabled = crtShaderEnabled
        renderer?.crtShaderIntensity = crtShaderIntensity
    }

    func powerDriveIfNeeded() {
        if c64.trueDriveEmulationMode == .off {
            c64.drive1541.enabled = false
            return
        }

        c64.iecBus.updateFromC64(c64.cia2.portA, ddra: c64.cia2.ddra)
        c64.drive1541.powerOn()
    }

    func reloadROMs(reset: Bool) {
        if hasConfiguredROMPaths() {
            guard loadROMsFromConfiguredPaths() else { return }
            if reset {
                c64.reset()
                powerDriveIfNeeded()
                refreshStatus()
            }
            return
        }

        // Fallback: look relative to executable and working directory
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let candidates = [
            execDir.appendingPathComponent("ROMS"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/C64/ROMS"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Sources/C64App/ROMS"),
        ]

        for dir in candidates {
            if FileManager.default.fileExists(atPath: dir.path) {
                if loadROMsFromDirectory(dir) {
                    if reset {
                        c64.reset()
                        powerDriveIfNeeded()
                        refreshStatus()
                    }
                    return
                }
            }
        }

        romStatusMessage = "ROM files are not configured. Set BASIC, Kernal, Characters, and 1541 paths in Settings."
        print("WARNING: \(romStatusMessage)")
    }

    func hasConfiguredROMPaths() -> Bool {
        let defaults = UserDefaults.standard
        let sources = [
            (defaults.string(forKey: PreferenceKey.basicROMPath) ?? "", PreferenceKey.basicROMBookmark, PreferenceKey.basicROMImportedPath),
            (defaults.string(forKey: PreferenceKey.kernalROMPath) ?? "", PreferenceKey.kernalROMBookmark, PreferenceKey.kernalROMImportedPath),
            (defaults.string(forKey: PreferenceKey.characterROMPath) ?? "", PreferenceKey.characterROMBookmark, PreferenceKey.characterROMImportedPath),
            (defaults.string(forKey: PreferenceKey.driveROMPath) ?? "", PreferenceKey.driveROMBookmark, PreferenceKey.driveROMImportedPath),
        ]
        return sources.contains { path, bookmarkKey, importedPathKey in
            hasROMSource(path: path, bookmarkKey: bookmarkKey, importedPathKey: importedPathKey)
        }
    }

    func loadROMsFromConfiguredPaths() -> Bool {
        let defaults = UserDefaults.standard
        let basicPath = defaults.string(forKey: PreferenceKey.basicROMPath) ?? ""
        let kernalPath = defaults.string(forKey: PreferenceKey.kernalROMPath) ?? ""
        let characterPath = defaults.string(forKey: PreferenceKey.characterROMPath) ?? ""
        let drivePath = defaults.string(forKey: PreferenceKey.driveROMPath) ?? ""

        do {
            guard hasROMSource(path: basicPath, bookmarkKey: PreferenceKey.basicROMBookmark, importedPathKey: PreferenceKey.basicROMImportedPath),
                  hasROMSource(path: kernalPath, bookmarkKey: PreferenceKey.kernalROMBookmark, importedPathKey: PreferenceKey.kernalROMImportedPath),
                  hasROMSource(path: characterPath, bookmarkKey: PreferenceKey.characterROMBookmark, importedPathKey: PreferenceKey.characterROMImportedPath) else {
                romStatusMessage = "BASIC, Kernal, and Characters ROM paths are required."
                print("WARNING: \(romStatusMessage)")
                return false
            }

            let basic = try loadConfiguredROM(path: basicPath, bookmarkKey: PreferenceKey.basicROMBookmark, importedPathKey: PreferenceKey.basicROMImportedPath)
            let kernal = try loadConfiguredROM(path: kernalPath, bookmarkKey: PreferenceKey.kernalROMBookmark, importedPathKey: PreferenceKey.kernalROMImportedPath)
            let characters = try loadConfiguredROM(path: characterPath, bookmarkKey: PreferenceKey.characterROMBookmark, importedPathKey: PreferenceKey.characterROMImportedPath)
            try c64.loadROMsValidated(basic: basic, kernal: kernal, charset: characters)

            if hasROMSource(path: drivePath, bookmarkKey: PreferenceKey.driveROMBookmark, importedPathKey: PreferenceKey.driveROMImportedPath) {
                let drive = try loadConfiguredROM(path: drivePath, bookmarkKey: PreferenceKey.driveROMBookmark, importedPathKey: PreferenceKey.driveROMImportedPath)
                try c64.loadDriveROMValidated(drive)
                romStatusMessage = "ROMs loaded from configured paths, including 1541 drive ROM."
            } else {
                romStatusMessage = "C64 ROMs loaded from configured paths. 1541 drive ROM is not configured."
            }
            print(romStatusMessage)
            return true
        } catch {
            romStatusMessage = "Could not load configured ROM paths: \(error.localizedDescription)"
            print("ERROR: \(romStatusMessage)")
            return false
        }
    }

    func hasROMSource(path: String, bookmarkKey: String, importedPathKey: String) -> Bool {
        if let importedPath = UserDefaults.standard.string(forKey: importedPathKey),
           !importedPath.isEmpty,
           FileManager.default.isReadableFile(atPath: importedPath) {
            return true
        }

        guard !path.isEmpty else { return false }
        if FileManager.default.isReadableFile(atPath: path) {
            return true
        }
        return UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    func loadConfiguredROM(path: String, bookmarkKey: String, importedPathKey: String) throws -> Data {
        if let importedPath = UserDefaults.standard.string(forKey: importedPathKey), !importedPath.isEmpty {
            let importedURL = URL(fileURLWithPath: importedPath)
            if FileManager.default.isReadableFile(atPath: importedURL.path) {
                return try Data(contentsOf: importedURL)
            }
        }

        if let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if path.isEmpty || url.path == path {
                if isStale {
                    try saveSecurityBookmark(for: url, key: bookmarkKey)
                }
                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                return try Data(contentsOf: url)
            }
        }

        guard !path.isEmpty else {
            throw ROMAccessError.missingSandboxSource
        }

        let url = URL(fileURLWithPath: path)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ROMAccessError.missingSecurityBookmark(path: path, underlying: error)
        }
    }

    func saveSecurityBookmark(for url: URL, key: String) throws {
        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: key)
    }

    func migrateLegacyPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        let legacyDomainName = "local.swift64.C64App"
        guard let legacyDomain = defaults.persistentDomain(forName: legacyDomainName) else { return }

        for key in [
            PreferenceKey.machineProfile,
            PreferenceKey.trueDriveMode,
            PreferenceKey.joystickRouting,
            PreferenceKey.basicROMPath,
            PreferenceKey.kernalROMPath,
            PreferenceKey.characterROMPath,
            PreferenceKey.driveROMPath,
            PreferenceKey.crtShaderEnabled,
            PreferenceKey.crtShaderIntensity,
        ] where defaults.object(forKey: key) == nil {
            if let value = legacyDomain[key] {
                defaults.set(value, forKey: key)
            }
        }
    }

    enum ROMAccessError: LocalizedError {
        case missingSecurityBookmark(path: String, underlying: Error)
        case missingSandboxSource

        var errorDescription: String? {
            switch self {
            case .missingSecurityBookmark(let path, let underlying):
                return "Cannot access \(path). Re-select the ROM in Settings so Swift64 can import a sandbox-safe copy. \(underlying.localizedDescription)"
            case .missingSandboxSource:
                return "No sandbox-safe ROM copy is available. Re-select the ROM in Settings."
            }
        }
    }

    func loadROMsFromDirectory(_ dir: URL) -> Bool {
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
                try c64.loadROMsValidated(basic: basic, kernal: kernal, charset: charset)
                romStatusMessage = "C64 ROMs loaded from \(dir.path)"
                print(romStatusMessage)
            } else {
                romStatusMessage = "Not all C64 ROM files found in \(dir.path)"
                print("WARNING: \(romStatusMessage)")
                return false
            }

            if let driveROM = driveROMData {
                try c64.loadDriveROMValidated(driveROM)
                romStatusMessage = "C64 and 1541 ROMs loaded from \(dir.path)"
                print("1541 drive ROM loaded (\(driveROM.count) bytes)")
            }
            return true
        } catch {
            romStatusMessage = "Error loading ROMs: \(error.localizedDescription)"
            print("ERROR loading ROMs: \(error)")
            return false
        }
    }

    func setupAudio() {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        let sampleRate = SID.sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let sid = c64.sid
        let dcBlockerPole: Float = 0.995
        let prebufferTarget = min(4096, sid.sampleBuffer.count / 2)
        let underrunLowWatermark = min(512, prebufferTarget / 4)
        var dcBlockerLastInput: Float = 0
        var dcBlockerLastOutput: Float = 0
        var lastOutput: Float = 0
        var prebuffering = true
        var underrunFrames: UInt64 = 0

        audioSourceNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in bufferList {
                let frames = Int(frameCount)
                let ptr = buffer.mData!.bindMemory(to: Float.self, capacity: frames)
                let availableSamples = sid.availableAudioSamplesForPlayback()
                if prebuffering && availableSamples < prebufferTarget {
                    for i in 0..<frames {
                        ptr[i] = lastOutput
                    }
                    underrunFrames += UInt64(frames)
                    continue
                }
                prebuffering = false

                let output = UnsafeMutableBufferPointer(start: ptr, count: frames)
                let samplesRead = sid.readAudioSamplesForPlayback(into: output)

                if samplesRead == 0 {
                    prebuffering = true
                    for i in 0..<frames {
                        ptr[i] = lastOutput
                    }
                    underrunFrames += UInt64(frames)
                    continue
                }

                for i in 0..<samplesRead {
                    let rawSample = ptr[i]
                    let coupledSample = rawSample - dcBlockerLastInput + dcBlockerPole * dcBlockerLastOutput
                    dcBlockerLastInput = rawSample
                    dcBlockerLastOutput = coupledSample
                    lastOutput = min(max(coupledSample, -0.95), 0.95)
                    ptr[i] = lastOutput
                }

                if samplesRead < frames {
                    prebuffering = true
                    for i in samplesRead..<frames {
                        ptr[i] = lastOutput
                    }
                    underrunFrames += UInt64(frames - samplesRead)
                } else if sid.availableAudioSamplesForPlayback() <= underrunLowWatermark {
                    prebuffering = true
                }
            }
            self?.audioUnderrunFrames = underrunFrames
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
        renderer?.stop()
        audioEngine?.stop()
    }
}

/// NSViewRepresentable wrapper for MTKView.
struct MetalView: NSViewRepresentable {
    let emulator: EmulatorController

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.preferredFramesPerSecond = emulator.displayFramesPerSecond
        view.colorPixelFormat = .bgra8Unorm
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        // Register for drag & drop
        view.registerForDraggedTypes([.fileURL])

        let renderer: MetalRenderer?
        if let existingRenderer = emulator.renderer {
            existingRenderer.configure(for: view)
            renderer = existingRenderer
        } else {
            renderer = MetalRenderer(mtkView: view, c64: emulator.c64)
            emulator.renderer = renderer
        }
        view.delegate = renderer
        context.coordinator.renderer = renderer
        renderer?.crtShaderEnabled = emulator.crtShaderEnabled
        renderer?.crtShaderIntensity = emulator.crtShaderIntensity

        // Set up keyboard event monitoring
        context.coordinator.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            return context.coordinator.handleKeyEvent(event)
        }

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        if nsView.preferredFramesPerSecond != emulator.displayFramesPerSecond {
            nsView.preferredFramesPerSecond = emulator.displayFramesPerSecond
        }
        context.coordinator.renderer?.crtShaderEnabled = emulator.crtShaderEnabled
        context.coordinator.renderer?.crtShaderIntensity = emulator.crtShaderIntensity
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(emulator: emulator)
    }

    class Coordinator {
        let emulator: EmulatorController
        var renderer: MetalRenderer?
        var eventMonitor: Any?

        init(emulator: EmulatorController) {
            self.emulator = emulator
        }

        deinit {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
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
                        c64.pressRestoreKey()
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
                if c64.keyboard.isRestoreKey(event.keyCode) {
                    c64.releaseRestoreKey()
                    return nil
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
