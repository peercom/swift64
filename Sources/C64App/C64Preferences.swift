import Foundation
import C64Core

enum PreferenceKey {
    static let machineProfile = "c64.machineProfile"
    static let trueDriveMode = "c64.trueDriveMode"
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
        let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

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
