import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var emulator: EmulatorController
    @Environment(\.dismiss) private var dismiss

    @AppStorage(PreferenceKey.machineProfile) private var machineProfile = MachineProfilePreference.palC64.rawValue
    @AppStorage(PreferenceKey.trueDriveMode) private var trueDriveMode = TrueDriveModePreference.off.rawValue
    @AppStorage(PreferenceKey.basicROMPath) private var basicROMPath = ""
    @AppStorage(PreferenceKey.kernalROMPath) private var kernalROMPath = ""
    @AppStorage(PreferenceKey.characterROMPath) private var characterROMPath = ""
    @AppStorage(PreferenceKey.driveROMPath) private var driveROMPath = ""
    @AppStorage(PreferenceKey.crtShaderEnabled) private var crtShaderEnabled = false
    @AppStorage(PreferenceKey.crtShaderIntensity) private var crtShaderIntensity = 0.65

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
                            applyROMSettings()
                        } label: {
                            Label("Apply", systemImage: "checkmark")
                        }

                        Button {
                            applyROMSettings()
                            dismiss()
                        } label: {
                            Text("OK")
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("ROMs", systemImage: "folder")
            }

            Form {
                Section("CRT") {
                    Toggle("CRT Shader", isOn: $crtShaderEnabled)

                    HStack {
                        Text("Intensity")
                        Slider(value: $crtShaderIntensity, in: 0.0...1.0)
                        Text(crtIntensityLabel)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .disabled(!crtShaderEnabled)
                }

                Section {
                    HStack {
                        Spacer()
                        Button {
                            emulator.applyDisplayPreferences()
                        } label: {
                            Label("Apply", systemImage: "checkmark")
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Display", systemImage: "display")
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

    private var crtIntensityLabel: String {
        "\(Int((crtShaderIntensity * 100).rounded()))%"
    }

    private func applyROMSettings() {
        emulator.reloadROMs(reset: true)
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
