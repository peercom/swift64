import Foundation
import C64Core

enum PreferenceKey {
    static let machineProfile = "c64.machineProfile"
    static let trueDriveMode = "c64.trueDriveMode"
    static let basicROMPath = "c64.rom.basicPath"
    static let kernalROMPath = "c64.rom.kernalPath"
    static let characterROMPath = "c64.rom.characterPath"
    static let driveROMPath = "c64.rom.drive1541Path"
    static let crtShaderEnabled = "c64.display.crtShaderEnabled"
    static let crtShaderIntensity = "c64.display.crtShaderIntensity"
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
