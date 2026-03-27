import SwiftUI
import AppKit
import C64Core

@main
struct C64App: App {
    @StateObject private var emulator = EmulatorController()
    @Environment(\.openWindow) private var openWindow

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
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
                        if emulator.c64.mountDisk(url) {
                            print("Disk mounted: \(url.lastPathComponent)")
                        }
                    }
                }
                .keyboardShortcut("d", modifiers: [.command])

                Button("Open Tape Image (T64/TAP)...") {
                    openFile(types: ["t64", "tap"], title: "Open Tape Image") { url in
                        if emulator.c64.mountTape(url) {
                            print("Tape mounted: \(url.lastPathComponent)")
                        }
                    }
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("Load Program (PRG)...") {
                    openFile(types: ["prg", "p00"], title: "Load PRG Program") { url in
                        emulator.c64.loadPRG(url, autoRun: true)
                        print("PRG loaded: \(url.lastPathComponent)")
                    }
                }
                .keyboardShortcut("l", modifiers: [.command])

                Divider()

                Button("Reset C64") {
                    emulator.c64.reset()
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
}
