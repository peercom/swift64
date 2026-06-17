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
                Section("Machine") {
                    Picker("Model", selection: $machineProfile) {
                        ForEach(MachineProfilePreference.allCases) { profile in
                            Text(profile.title).tag(profile.rawValue)
                        }
                    }

                    Picker("Drive", selection: $trueDriveMode) {
                        ForEach(TrueDriveModePreference.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Button {
                            emulator.applyEmulationPreferences(reset: true)
                        } label: {
                            Label("Apply", systemImage: "checkmark")
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Emulation", systemImage: "slider.horizontal.3")
            }

            Form {
                Section("C64 ROMs") {
                    ROMPathRow(title: "BASIC", path: $basicROMPath)
                    ROMPathRow(title: "Kernal", path: $kernalROMPath)
                    ROMPathRow(title: "Characters", path: $characterROMPath)
                }

                Section("Drive ROM") {
                    ROMPathRow(title: "1541 Drive", path: $driveROMPath)
                }

                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Label(emulator.romStatusMessage, systemImage: romStatusIcon)
                            .foregroundStyle(romStatusColor)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            emulator.reloadROMs(reset: true)
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        .keyboardShortcut("r", modifiers: [.command])
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("ROMs", systemImage: "folder")
            }
        }
        .frame(width: 700, height: 390)
        .scenePadding()
    }

    private var romStatusIcon: String {
        emulator.romStatusMessage.lowercased().contains("not") || emulator.romStatusMessage.lowercased().contains("could not") ? "exclamationmark.circle" : "checkmark.circle"
    }

    private var romStatusColor: Color {
        romStatusIcon == "checkmark.circle" ? .secondary : .orange
    }
}

private struct ROMPathRow: View {
    let title: String
    @Binding var path: String

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 82, alignment: .trailing)
                .foregroundStyle(.secondary)

            TextField(title, text: $path)
                .textFieldStyle(.roundedBorder)
                .fontDesign(.monospaced)
            Button {
                chooseROM()
            } label: {
                Label("Choose", systemImage: "folder")
            }
            .labelStyle(.iconOnly)
            .help("Choose \(title) ROM")
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
