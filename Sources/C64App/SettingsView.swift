import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var emulator: EmulatorController

    @AppStorage(PreferenceKey.machineProfile) private var machineProfile = MachineProfilePreference.palC64.rawValue
    @AppStorage(PreferenceKey.trueDriveMode) private var trueDriveMode = TrueDriveModePreference.off.rawValue
    @AppStorage(PreferenceKey.basicROMPath) private var basicROMPath = ""
    @AppStorage(PreferenceKey.kernalROMPath) private var kernalROMPath = ""
    @AppStorage(PreferenceKey.characterROMPath) private var characterROMPath = ""
    @AppStorage(PreferenceKey.driveROMPath) private var driveROMPath = ""

    var body: some View {
        TabView {
            Form {
                Picker("Machine", selection: $machineProfile) {
                    ForEach(MachineProfilePreference.allCases) { profile in
                        Text(profile.title).tag(profile.rawValue)
                    }
                }

                Picker("Drive Mode", selection: $trueDriveMode) {
                    ForEach(TrueDriveModePreference.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }

                HStack {
                    Spacer()
                    Button("Apply") {
                        emulator.applyEmulationPreferences(reset: true)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Emulation", systemImage: "slider.horizontal.3")
            }

            Form {
                ROMPathRow(title: "BASIC", path: $basicROMPath)
                ROMPathRow(title: "Kernal", path: $kernalROMPath)
                ROMPathRow(title: "Characters", path: $characterROMPath)
                ROMPathRow(title: "1541 Drive", path: $driveROMPath)

                HStack(alignment: .firstTextBaseline) {
                    Text(emulator.romStatusMessage)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button("Reload ROMs") {
                        emulator.reloadROMs(reset: true)
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("ROMs", systemImage: "folder")
            }
        }
        .frame(width: 620, height: 320)
        .scenePadding()
    }
}

private struct ROMPathRow: View {
    let title: String
    @Binding var path: String

    var body: some View {
        HStack {
            TextField(title, text: $path)
                .textFieldStyle(.roundedBorder)
                .fontDesign(.monospaced)
            Button("Choose...") {
                chooseROM()
            }
        }
    }

    private func chooseROM() {
        let panel = NSOpenPanel()
        panel.title = "Choose \(title) ROM"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}

