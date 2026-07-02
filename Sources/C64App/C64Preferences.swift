import Foundation
import C64Core

enum PreferenceKey {
    static let machineProfile = "c64.machineProfile"
    static let trueDriveMode = "c64.trueDriveMode"
    static let sidModel = "c64.sid.model"
    static let sidAccuracyMode = "c64.sid.accuracyMode"
    static let joystickRouting = "c64.input.joystickRouting"
    static let basicROMPath = "c64.rom.basicPath"
    static let kernalROMPath = "c64.rom.kernalPath"
    static let characterROMPath = "c64.rom.characterPath"
    static let driveROMPath = "c64.rom.drive1541Path"
    static let basicROMBookmark = "c64.rom.basicBookmark"
    static let kernalROMBookmark = "c64.rom.kernalBookmark"
    static let characterROMBookmark = "c64.rom.characterBookmark"
    static let driveROMBookmark = "c64.rom.drive1541Bookmark"
    static let basicROMImportedPath = "c64.rom.basicImportedPath"
    static let kernalROMImportedPath = "c64.rom.kernalImportedPath"
    static let characterROMImportedPath = "c64.rom.characterImportedPath"
    static let driveROMImportedPath = "c64.rom.drive1541ImportedPath"
    static let crtShaderEnabled = "c64.display.crtShaderEnabled"
    static let crtShaderIntensity = "c64.display.crtShaderIntensity"
}

enum ROMFileStore {
    static func importAuthorizedROM(from url: URL, bookmarkKey: String, importedPathKey: String, storedFileName: String) throws -> URL {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        let data = try Data(contentsOf: url)
        let destination = try importedROMURL(storedFileName: storedFileName)
        try data.write(to: destination, options: .atomic)

        let defaults = UserDefaults.standard
        if let bookmark {
            defaults.set(bookmark, forKey: bookmarkKey)
        }
        defaults.set(destination.path, forKey: importedPathKey)
        return destination
    }

    static func importedROMURL(storedFileName: String) throws -> URL {
        let directory = try importedROMDirectory()
        return directory.appendingPathComponent(storedFileName, isDirectory: false)
    }

    private static func importedROMDirectory() throws -> URL {
        let baseDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseDirectory.appendingPathComponent("Swift64/ROMs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

enum CompatibilityPresetPreference: String, CaseIterable, Identifiable {
    case fastLoad
    case compatTrueDrive
    case strictPAL
    case palC64C
    case ntscC64
    case crtSIDAccurate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fastLoad: return "Fast Load"
        case .compatTrueDrive: return "Compat True Drive"
        case .strictPAL: return "Strict PAL"
        case .palC64C: return "PAL C64C"
        case .ntscC64: return "NTSC C64"
        case .crtSIDAccurate: return "CRT + Accurate SID"
        }
    }

    var subtitle: String {
        switch self {
        case .fastLoad:
            return "PAL C64, Kernal traps, fast SID, CRT off"
        case .compatTrueDrive:
            return "PAL C64, 1541C compat, profile SID, CRT on"
        case .strictPAL:
            return "PAL C64, strict 1541, 6581, accurate SID"
        case .palC64C:
            return "PAL C64C, 1541C compat, 8580, accurate SID"
        case .ntscC64:
            return "NTSC C64, 1541C compat, 6581, accurate SID"
        case .crtSIDAccurate:
            return "Keep machine profile, accurate SID, CRT on"
        }
    }

    var systemImage: String {
        switch self {
        case .fastLoad: return "bolt"
        case .compatTrueDrive: return "externaldrive"
        case .strictPAL: return "checkmark.seal"
        case .palC64C: return "memorychip"
        case .ntscC64: return "globe.americas"
        case .crtSIDAccurate: return "display"
        }
    }

    var machineProfile: MachineProfilePreference? {
        switch self {
        case .fastLoad, .compatTrueDrive, .strictPAL:
            return .palC64
        case .palC64C:
            return .palC64C
        case .ntscC64:
            return .ntscC64
        case .crtSIDAccurate:
            return nil
        }
    }

    var trueDriveMode: TrueDriveModePreference {
        switch self {
        case .fastLoad:
            return .off
        case .strictPAL:
            return .standard1541
        case .compatTrueDrive, .palC64C, .ntscC64, .crtSIDAccurate:
            return .compat1541
        }
    }

    var sidModel: SIDModelPreference {
        switch self {
        case .palC64C:
            return .mos8580
        case .strictPAL, .ntscC64:
            return .mos6581
        case .fastLoad, .compatTrueDrive, .crtSIDAccurate:
            return .profileDefault
        }
    }

    var sidAccuracyMode: SIDAccuracyModePreference {
        switch self {
        case .fastLoad:
            return .fast
        case .compatTrueDrive, .strictPAL, .palC64C, .ntscC64, .crtSIDAccurate:
            return .compatibility
        }
    }

    var crtShaderEnabled: Bool {
        switch self {
        case .fastLoad:
            return false
        case .compatTrueDrive, .strictPAL, .palC64C, .ntscC64, .crtSIDAccurate:
            return true
        }
    }

    var crtShaderIntensity: Double {
        switch self {
        case .fastLoad:
            return 0.0
        case .compatTrueDrive:
            return 0.55
        case .strictPAL, .palC64C, .ntscC64, .crtSIDAccurate:
            return 0.65
        }
    }
}

enum MachineProfilePreference: String, CaseIterable, Identifiable {
    case palC64
    case palC64C
    case palC64With1541II
    case palC64CWith1541II
    case ntscC64
    case ntscC64C
    case ntscC64With1541II
    case ntscC64CWith1541II

    var id: String { rawValue }

    var title: String {
        switch self {
        case .palC64: return "PAL C64 + 1541C"
        case .palC64C: return "PAL C64C + 1541C"
        case .palC64With1541II: return "PAL C64 + 1541-II"
        case .palC64CWith1541II: return "PAL C64C + 1541-II"
        case .ntscC64: return "NTSC C64 + 1541C"
        case .ntscC64C: return "NTSC C64C + 1541C"
        case .ntscC64With1541II: return "NTSC C64 + 1541-II"
        case .ntscC64CWith1541II: return "NTSC C64C + 1541-II"
        }
    }

    var profile: MachineProfile {
        switch self {
        case .palC64: return .palC64
        case .palC64C: return .palC64C
        case .palC64With1541II: return .palC64With1541II
        case .palC64CWith1541II: return .palC64CWith1541II
        case .ntscC64: return .ntscC64
        case .ntscC64C: return .ntscC64C
        case .ntscC64With1541II: return .ntscC64With1541II
        case .ntscC64CWith1541II: return .ntscC64CWith1541II
        }
    }
}

enum TrueDriveModePreference: String, CaseIterable, Identifiable {
    case off
    case standard1541
    case compat1541

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Fast Load"
        case .standard1541: return "True Drive 1541"
        case .compat1541: return "True Drive 1541 Compat"
        }
    }

    var mode: TrueDriveEmulationMode {
        switch self {
        case .off: return .off
        case .standard1541: return .standard1541
        case .compat1541: return .compat1541
        }
    }
}

enum SIDAccuracyModePreference: String, CaseIterable, Identifiable {
    case fast
    case compatibility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "Fast"
        case .compatibility: return "Compatibility"
        }
    }

    var mode: SID.AccuracyMode {
        switch self {
        case .fast: return .fast
        case .compatibility: return .compatibility
        }
    }
}

enum SIDModelPreference: String, CaseIterable, Identifiable {
    case profileDefault
    case mos6581
    case mos8580

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profileDefault: return "Profile Default"
        case .mos6581: return "MOS 6581"
        case .mos8580: return "MOS 8580"
        }
    }

    var model: SID.Model? {
        switch self {
        case .profileDefault: return nil
        case .mos6581: return .mos6581
        case .mos8580: return .mos8580
        }
    }
}

enum JoystickRoutingPreference: String, CaseIterable, Identifiable {
    case both
    case port2
    case port1

    var id: String { rawValue }

    var title: String {
        switch self {
        case .both: return "Both Ports"
        case .port2: return "Port 2"
        case .port1: return "Port 1"
        }
    }

    var routing: JoystickRouting {
        switch self {
        case .both: return .both
        case .port2: return .port2
        case .port1: return .port1
        }
    }
}
