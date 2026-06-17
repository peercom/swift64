import Foundation

public enum C64VideoStandard: String, Equatable {
    case pal
    case ntsc
}

public struct MachineProfile: Equatable {
    public let name: String
    public let videoStandard: C64VideoStandard
    public let cpuClockHz: Double
    public let ciaTodCyclesPerTenth: Int
    public let sidModel: SID.Model
    public let sidClockHz: Double
    public let driveModel: Drive1541.DriveModel
    public let driveClockHz: Double

    public init(
        name: String,
        videoStandard: C64VideoStandard,
        cpuClockHz: Double,
        ciaTodCyclesPerTenth: Int,
        sidModel: SID.Model,
        sidClockHz: Double,
        driveModel: Drive1541.DriveModel,
        driveClockHz: Double
    ) {
        self.name = name
        self.videoStandard = videoStandard
        self.cpuClockHz = cpuClockHz
        self.ciaTodCyclesPerTenth = ciaTodCyclesPerTenth
        self.sidModel = sidModel
        self.sidClockHz = sidClockHz
        self.driveModel = driveModel
        self.driveClockHz = driveClockHz
    }

    public var standardDriveClockRatio: Double {
        driveClockHz / cpuClockHz
    }

    public var ciaTod50HzCyclesPerTenth: Int {
        switch videoStandard {
        case .pal:
            return ciaTodCyclesPerTenth
        case .ntsc:
            return Int((Double(ciaTodCyclesPerTenth) * 5.0 / 6.0).rounded())
        }
    }

    public var ciaTod60HzCyclesPerTenth: Int {
        switch videoStandard {
        case .pal:
            return Int((Double(ciaTodCyclesPerTenth) * 6.0 / 5.0).rounded())
        case .ntsc:
            return ciaTodCyclesPerTenth
        }
    }

    public var vicCyclesPerLine: Int {
        switch videoStandard {
        case .pal: return VIC.palCyclesPerLine
        case .ntsc: return VIC.ntscCyclesPerLine
        }
    }

    public var vicRasterLinesPerFrame: Int {
        switch videoStandard {
        case .pal: return VIC.palRasterLinesPerFrame
        case .ntsc: return VIC.ntscRasterLinesPerFrame
        }
    }

    public static let palC64 = MachineProfile(
        name: "PAL C64 + 1541C",
        videoStandard: .pal,
        cpuClockHz: 985_248,
        ciaTodCyclesPerTenth: 98_525,
        sidModel: .mos6581,
        sidClockHz: 985_248,
        driveModel: .model1541C,
        driveClockHz: 1_000_000
    )

    public static let palC64C = MachineProfile(
        name: "PAL C64C + 1541C",
        videoStandard: .pal,
        cpuClockHz: 985_248,
        ciaTodCyclesPerTenth: 98_525,
        sidModel: .mos8580,
        sidClockHz: 985_248,
        driveModel: .model1541C,
        driveClockHz: 1_000_000
    )

    public static let palC64With1541II = MachineProfile(
        name: "PAL C64 + 1541-II",
        videoStandard: .pal,
        cpuClockHz: 985_248,
        ciaTodCyclesPerTenth: 98_525,
        sidModel: .mos6581,
        sidClockHz: 985_248,
        driveModel: .model1541II,
        driveClockHz: 1_000_000
    )

    public static let palC64CWith1541II = MachineProfile(
        name: "PAL C64C + 1541-II",
        videoStandard: .pal,
        cpuClockHz: 985_248,
        ciaTodCyclesPerTenth: 98_525,
        sidModel: .mos8580,
        sidClockHz: 985_248,
        driveModel: .model1541II,
        driveClockHz: 1_000_000
    )

    public static let ntscC64 = MachineProfile(
        name: "NTSC C64 + 1541C",
        videoStandard: .ntsc,
        cpuClockHz: 1_022_727,
        ciaTodCyclesPerTenth: 102_273,
        sidModel: .mos6581,
        sidClockHz: 1_022_727,
        driveModel: .model1541C,
        driveClockHz: 1_000_000
    )

    public static let ntscC64With1541II = MachineProfile(
        name: "NTSC C64 + 1541-II",
        videoStandard: .ntsc,
        cpuClockHz: 1_022_727,
        ciaTodCyclesPerTenth: 102_273,
        sidModel: .mos6581,
        sidClockHz: 1_022_727,
        driveModel: .model1541II,
        driveClockHz: 1_000_000
    )

    public static let ntscC64C = MachineProfile(
        name: "NTSC C64C + 1541C",
        videoStandard: .ntsc,
        cpuClockHz: 1_022_727,
        ciaTodCyclesPerTenth: 102_273,
        sidModel: .mos8580,
        sidClockHz: 1_022_727,
        driveModel: .model1541C,
        driveClockHz: 1_000_000
    )

    public static let ntscC64CWith1541II = MachineProfile(
        name: "NTSC C64C + 1541-II",
        videoStandard: .ntsc,
        cpuClockHz: 1_022_727,
        ciaTodCyclesPerTenth: 102_273,
        sidModel: .mos8580,
        sidClockHz: 1_022_727,
        driveModel: .model1541II,
        driveClockHz: 1_000_000
    )
}
