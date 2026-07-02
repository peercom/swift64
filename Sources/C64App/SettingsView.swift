import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var emulator: EmulatorController
    @Environment(\.dismiss) private var dismiss

    @AppStorage(PreferenceKey.machineProfile) private var machineProfile = MachineProfilePreference.palC64.rawValue
    @AppStorage(PreferenceKey.trueDriveMode) private var trueDriveMode = TrueDriveModePreference.off.rawValue
    @AppStorage(PreferenceKey.sidModel) private var sidModel = SIDModelPreference.profileDefault.rawValue
    @AppStorage(PreferenceKey.sidAccuracyMode) private var sidAccuracyMode = SIDAccuracyModePreference.fast.rawValue
    @AppStorage(PreferenceKey.joystickRouting) private var joystickRouting = JoystickRoutingPreference.both.rawValue
    @AppStorage(PreferenceKey.basicROMPath) private var basicROMPath = ""
    @AppStorage(PreferenceKey.kernalROMPath) private var kernalROMPath = ""
    @AppStorage(PreferenceKey.characterROMPath) private var characterROMPath = ""
    @AppStorage(PreferenceKey.driveROMPath) private var driveROMPath = ""
    @AppStorage(PreferenceKey.crtShaderEnabled) private var crtShaderEnabled = false
    @AppStorage(PreferenceKey.crtShaderIntensity) private var crtShaderIntensity = 0.65

    var body: some View {
        TabView {
            Form {
                Section("Presets") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                        ForEach(CompatibilityPresetPreference.allCases) { preset in
                            Button {
                                applyPreset(preset)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: preset.systemImage)
                                        .font(.title3)
                                        .frame(width: 24)
                                        .foregroundStyle(.secondary)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(preset.title)
                                            .font(.callout.weight(.semibold))
                                            .lineLimit(1)
                                        Text(preset.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

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

                    Picker("SID Chip", selection: $sidModel) {
                        ForEach(SIDModelPreference.allCases) { model in
                            Text(model.title).tag(model.rawValue)
                        }
                    }

                    Picker("SID Accuracy", selection: $sidAccuracyMode) {
                        ForEach(SIDAccuracyModePreference.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }

                    Picker("Joystick", selection: $joystickRouting) {
                        ForEach(JoystickRoutingPreference.allCases) { routing in
                            Text(routing.title).tag(routing.rawValue)
                        }
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Button {
                            applyEmulationSettings()
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
                    ROMPathRow(title: "BASIC", path: $basicROMPath, bookmarkKey: PreferenceKey.basicROMBookmark, importedPathKey: PreferenceKey.basicROMImportedPath, storedFileName: "basic.rom") {
                        emulator.romStatusMessage = $0
                    }
                    ROMPathRow(title: "Kernal", path: $kernalROMPath, bookmarkKey: PreferenceKey.kernalROMBookmark, importedPathKey: PreferenceKey.kernalROMImportedPath, storedFileName: "kernal.rom") {
                        emulator.romStatusMessage = $0
                    }
                    ROMPathRow(title: "Characters", path: $characterROMPath, bookmarkKey: PreferenceKey.characterROMBookmark, importedPathKey: PreferenceKey.characterROMImportedPath, storedFileName: "characters.rom") {
                        emulator.romStatusMessage = $0
                    }
                }

                Section("Drive ROM") {
                    ROMPathRow(title: "1541 Drive", path: $driveROMPath, bookmarkKey: PreferenceKey.driveROMBookmark, importedPathKey: PreferenceKey.driveROMImportedPath, storedFileName: "1541.rom") {
                        emulator.romStatusMessage = $0
                    }
                }

                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Label(emulator.romStatusMessage, systemImage: romStatusIcon)
                            .foregroundStyle(romStatusColor)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            _ = applyROMSettings()
                        } label: {
                            Label("Apply", systemImage: "checkmark")
                        }

                        Button {
                            if applyROMSettings() {
                                dismiss()
                            }
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
        .frame(width: 740, height: 520)
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

    private func applyPreset(_ preset: CompatibilityPresetPreference) {
        emulator.applyCompatibilityPreset(preset)
    }

    private func applyEmulationSettings() {
        emulator.applyEmulationPreferences(reset: true)
    }

    @discardableResult
    private func applyROMSettings() -> Bool {
        guard ensureROMBookmarks() else {
            emulator.romStatusMessage = "ROM access was not authorized. Use each folder button once to import sandbox-safe ROM copies."
            return false
        }
        emulator.reloadROMs(reset: true)
        return !emulator.romStatusMessage.lowercased().contains("could not")
    }

    private func ensureROMBookmarks() -> Bool {
        let configuredROMs = [
            ("BASIC", basicROMPath, PreferenceKey.basicROMBookmark, PreferenceKey.basicROMImportedPath, "basic.rom"),
            ("Kernal", kernalROMPath, PreferenceKey.kernalROMBookmark, PreferenceKey.kernalROMImportedPath, "kernal.rom"),
            ("Characters", characterROMPath, PreferenceKey.characterROMBookmark, PreferenceKey.characterROMImportedPath, "characters.rom"),
            ("1541 Drive", driveROMPath, PreferenceKey.driveROMBookmark, PreferenceKey.driveROMImportedPath, "1541.rom"),
        ]

        for (title, path, bookmarkKey, importedPathKey, storedFileName) in configuredROMs where !path.isEmpty {
            guard !hasImportedROM(importedPathKey: importedPathKey) && !hasMatchingBookmark(path: path, bookmarkKey: bookmarkKey) else { continue }
            guard authorizeROM(title: title, path: path, bookmarkKey: bookmarkKey, importedPathKey: importedPathKey, storedFileName: storedFileName) else {
                return false
            }
        }
        return true
    }

    private func hasImportedROM(importedPathKey: String) -> Bool {
        guard let path = UserDefaults.standard.string(forKey: importedPathKey), !path.isEmpty else { return false }
        return FileManager.default.isReadableFile(atPath: path)
    }

    private func hasMatchingBookmark(path: String, bookmarkKey: String) -> Bool {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return false }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return false
        }
        return !isStale && url.path == path
    }

    private func authorizeROM(title: String, path: String, bookmarkKey: String, importedPathKey: String, storedFileName: String) -> Bool {
        let expectedURL = URL(fileURLWithPath: path)
        let panel = NSOpenPanel()
        panel.title = "Authorize \(title) ROM"
        panel.message = "Choose the configured ROM file so Swift64 can import a private copy into its app container."
        panel.prompt = "Authorize"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = expectedURL.deletingLastPathComponent()
        panel.nameFieldStringValue = expectedURL.lastPathComponent

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            _ = try ROMFileStore.importAuthorizedROM(from: url, bookmarkKey: bookmarkKey, importedPathKey: importedPathKey, storedFileName: storedFileName)
            UserDefaults.standard.set(url.path, forKey: pathKey(for: bookmarkKey))
            return true
        } catch {
            print("Could not authorize \(title) ROM: \(error)")
            return false
        }
    }

    private func pathKey(for bookmarkKey: String) -> String {
        switch bookmarkKey {
        case PreferenceKey.basicROMBookmark: return PreferenceKey.basicROMPath
        case PreferenceKey.kernalROMBookmark: return PreferenceKey.kernalROMPath
        case PreferenceKey.characterROMBookmark: return PreferenceKey.characterROMPath
        case PreferenceKey.driveROMBookmark: return PreferenceKey.driveROMPath
        default: return bookmarkKey
        }
    }
}

private struct ROMPathRow: View {
    let title: String
    @Binding var path: String
    let bookmarkKey: String
    let importedPathKey: String
    let storedFileName: String
    let onImport: (String) -> Void

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

            Button {
                clearROM()
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
            .labelStyle(.iconOnly)
            .help("Clear \(title) ROM configuration")
            .disabled(path.isEmpty && !hasImportedROM)
        }
    }

    private var hasImportedROM: Bool {
        guard let importedPath = UserDefaults.standard.string(forKey: importedPathKey), !importedPath.isEmpty else {
            return false
        }
        return FileManager.default.fileExists(atPath: importedPath)
    }

    private func chooseROM() {
        let panel = NSOpenPanel()
        panel.title = "Choose \(title) ROM"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                _ = try ROMFileStore.importAuthorizedROM(from: url, bookmarkKey: bookmarkKey, importedPathKey: importedPathKey, storedFileName: storedFileName)
                path = url.path
                onImport("\(title) ROM authorized and imported.")
            } catch {
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                UserDefaults.standard.removeObject(forKey: importedPathKey)
                onImport("Could not import \(title) ROM: \(error.localizedDescription)")
                print("Could not import \(title) ROM: \(error)")
            }
        }
    }

    private func clearROM() {
        if let importedPath = UserDefaults.standard.string(forKey: importedPathKey), !importedPath.isEmpty {
            try? FileManager.default.removeItem(atPath: importedPath)
        }
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: importedPathKey)
        path = ""
        onImport("\(title) ROM configuration cleared.")
    }
}
