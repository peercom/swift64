import SwiftUI
import AppKit
import C64Core

@main
struct C64App: App {
    @StateObject private var emulator = EmulatorController()
    @Environment(\.openWindow) private var openWindow

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        #if SWIFT_PACKAGE
        let resourceBundle = Bundle.module
        #else
        let resourceBundle = Bundle.main
        #endif
        if let iconURL = resourceBundle.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("C64") {
            ContentView(emulator: emulator)
        }
        .defaultSize(width: 806, height: 568)
        .commands {
            // File menu commands
            CommandGroup(after: .newItem) {
                Button("Open Disk Image (D64/G64)...") {
                    openFile(types: ["d64", "g64"], title: "Open Disk Image") { url in
                        emulator.mountDisk(url)
                    }
                }
                .keyboardShortcut("d", modifiers: [.command])

                Button("Export Modified D64...") {
                    saveFile(type: "d64", title: "Export Modified D64", defaultName: emulator.suggestedModifiedD64Name) { url in
                        do {
                            try emulator.exportModifiedD64(to: url)
                        } catch {
                            print("Could not export modified D64: \(error.localizedDescription)")
                        }
                    }
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!(emulator.emulationStatus?.canExportModifiedD64 ?? false) || !(emulator.emulationStatus?.diskHasUnsavedChanges ?? false))

                Button("Export Captured TAP...") {
                    saveFile(type: "tap", title: "Export Captured TAP", defaultName: emulator.suggestedCapturedTAPName) { url in
                        do {
                            try emulator.exportCapturedTAP(to: url)
                        } catch {
                            print("Could not export captured TAP: \(error.localizedDescription)")
                        }
                    }
                }
                .disabled(!(emulator.emulationStatus?.canExportCapturedTAP ?? false))

                Button("Export Saved T64...") {
                    saveFile(type: "t64", title: "Export Saved T64", defaultName: emulator.suggestedSavedT64Name) { url in
                        do {
                            try emulator.exportSavedT64(to: url)
                        } catch {
                            print("Could not export saved T64: \(error.localizedDescription)")
                        }
                    }
                }
                .disabled(!(emulator.emulationStatus?.canExportSavedT64 ?? false) || !(emulator.emulationStatus?.tapeHasUnsavedChanges ?? false))

                Button("Open Tape Image (T64/TAP)...") {
                    openFile(types: ["t64", "tap"], title: "Open Tape Image") { url in
                        emulator.mountTape(url)
                    }
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("Load Program (PRG)...") {
                    openFile(types: ["prg", "p00"], title: "Load PRG Program") { url in
                        emulator.c64.loadPRG(url, autoRun: true)
                        emulator.refreshStatus()
                        print("PRG loaded: \(url.lastPathComponent)")
                    }
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button("Open Cartridge Image (CRT)...") {
                    openFile(types: ["crt"], title: "Open Cartridge Image") { url in
                        if emulator.c64.mountCartridge(url) {
                            emulator.c64.reset()
                            emulator.refreshStatus()
                            print("Cartridge mounted: \(url.lastPathComponent)")
                        }
                    }
                }
                .keyboardShortcut("k", modifiers: [.command])

                Divider()

                Button("Reset C64") {
                    emulator.c64.reset()
                    emulator.powerDriveIfNeeded()
                    emulator.refreshStatus()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            // Debug menu
            CommandMenu("Debug") {
                Button("Show Debugger") {
                    openWindow(id: "debugger")
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }

            // Emulation menu
            CommandMenu("Emulation") {
                Toggle("True Drive Emulation (1541)", isOn: Binding(
                    get: { emulator.c64.trueDriveEmulation },
                    set: { enabled in
                        emulator.setTrueDriveMode(enabled ? .compat1541 : .off)
                    }
                ))
            }
        }

        Settings {
            SettingsView(emulator: emulator)
        }

        // Debugger window
        Window("C64 Debugger", id: "debugger") {
            DebuggerView(emulator: emulator)
        }
        .defaultSize(width: 900, height: 600)
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

    func saveFile(type: String, title: String, defaultName: String, handler: @escaping (URL) -> Void) {
        let panel = NSSavePanel()
        panel.title = title
        panel.allowedContentTypes = [.init(filenameExtension: type)].compactMap { $0 }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultName

        if panel.runModal() == .OK, let url = panel.url {
            handler(url)
        }
    }
}
