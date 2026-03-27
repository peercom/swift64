import SwiftUI
import AppKit
import NESCore

@main
struct NESApp: App {
    @StateObject private var emulator = NESEmulatorController()

    var body: some Scene {
        WindowGroup {
            NESContentView(emulator: emulator)
        }
        .defaultSize(width: 768, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open ROM...") {
                    openFile(types: ["nes"], title: "Open NES ROM") { url in
                        if emulator.nes.loadCartridge(url) {
                            print("ROM loaded: \(url.lastPathComponent)")
                        }
                    }
                }
                .keyboardShortcut("o")

                Divider()

                Button("Reset") {
                    emulator.nes.reset()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }

    func openFile(types: [String], title: String, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = types.compactMap {
            .init(filenameExtension: $0)
        }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
}
