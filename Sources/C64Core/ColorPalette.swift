import Foundation

/// C64 16-color palette (RGBA8888) with selectable presets.
///
/// The active table is swapped as a whole between emulated frames; VIC
/// rendering indexes `rgba` directly, so a change takes effect on the next
/// rasterline that is composed.
public struct ColorPalette {
    public typealias RGB = (r: UInt8, g: UInt8, b: UInt8)

    public enum Preset: String, CaseIterable, Sendable {
        /// Pepto's 2001 PAL measurement as tabulated on the C64 Wiki.
        case pepto
        /// Pepto's PAL palette as shipped with VICE (`pepto-pal.vpl`).
        case peptoPAL
        /// Pepto's later Colodore palette, calibrated against a PAL CRT.
        case colodore

        public var displayName: String {
            switch self {
            case .pepto: return "Pepto (C64 Wiki)"
            case .peptoPAL: return "Pepto PAL (VICE)"
            case .colodore: return "Colodore"
            }
        }

        public var colors: [RGB] {
            switch self {
            case .pepto: return ColorPalette.peptoColors
            case .peptoPAL: return ColorPalette.peptoPALColors
            case .colodore: return ColorPalette.colodoreColors
            }
        }
    }

    static let peptoColors: [RGB] = [
        (0x00, 0x00, 0x00),  //  0 Black
        (0xFF, 0xFF, 0xFF),  //  1 White
        (0x88, 0x39, 0x32),  //  2 Red
        (0x67, 0xB6, 0xBD),  //  3 Cyan
        (0x8B, 0x3F, 0x96),  //  4 Purple
        (0x55, 0xA0, 0x49),  //  5 Green
        (0x40, 0x31, 0x8D),  //  6 Blue
        (0xBF, 0xCE, 0x72),  //  7 Yellow
        (0x8B, 0x54, 0x29),  //  8 Orange
        (0x57, 0x42, 0x00),  //  9 Brown
        (0xB8, 0x69, 0x62),  // 10 Light red
        (0x50, 0x50, 0x50),  // 11 Dark grey
        (0x78, 0x78, 0x78),  // 12 Grey
        (0x94, 0xE0, 0x89),  // 13 Light green
        (0x78, 0x69, 0xC4),  // 14 Light blue
        (0x9F, 0x9F, 0x9F),  // 15 Light grey
    ]

    static let peptoPALColors: [RGB] = [
        (0x00, 0x00, 0x00),  //  0 Black
        (0xFF, 0xFF, 0xFF),  //  1 White
        (0x68, 0x37, 0x2B),  //  2 Red
        (0x70, 0xA4, 0xB2),  //  3 Cyan
        (0x6F, 0x3D, 0x86),  //  4 Purple
        (0x58, 0x8D, 0x43),  //  5 Green
        (0x35, 0x28, 0x79),  //  6 Blue
        (0xB8, 0xC7, 0x6F),  //  7 Yellow
        (0x6F, 0x4F, 0x25),  //  8 Orange
        (0x43, 0x39, 0x00),  //  9 Brown
        (0x9A, 0x67, 0x59),  // 10 Light red
        (0x44, 0x44, 0x44),  // 11 Dark grey
        (0x6C, 0x6C, 0x6C),  // 12 Grey
        (0x9A, 0xD2, 0x84),  // 13 Light green
        (0x6C, 0x5E, 0xB5),  // 14 Light blue
        (0x95, 0x95, 0x95),  // 15 Light grey
    ]

    static let colodoreColors: [RGB] = [
        (0x00, 0x00, 0x00),  //  0 Black
        (0xFF, 0xFF, 0xFF),  //  1 White
        (0x81, 0x33, 0x38),  //  2 Red
        (0x75, 0xCE, 0xC8),  //  3 Cyan
        (0x8E, 0x3C, 0x97),  //  4 Purple
        (0x56, 0xAC, 0x4D),  //  5 Green
        (0x2E, 0x2C, 0x9B),  //  6 Blue
        (0xED, 0xF1, 0x71),  //  7 Yellow
        (0x8E, 0x50, 0x29),  //  8 Orange
        (0x55, 0x38, 0x00),  //  9 Brown
        (0xC4, 0x6C, 0x71),  // 10 Light red
        (0x4A, 0x4A, 0x4A),  // 11 Dark grey
        (0x7B, 0x7B, 0x7B),  // 12 Grey
        (0xA9, 0xFF, 0x9F),  // 13 Light green
        (0x70, 0x6D, 0xEB),  // 14 Light blue
        (0xB2, 0xB2, 0xB2),  // 15 Light grey
    ]

    /// The default preset's colors, kept for callers that only need a table.
    public static let colors: [RGB] = Preset.pepto.colors

    /// Currently selected preset.
    public private(set) static var activePreset: Preset = .pepto

    /// Pre-computed RGBA32 values in little-endian byte order for Metal rgba8Unorm textures.
    /// Memory layout: [R, G, B, A] — on little-endian this is stored as 0xAABBGGRR.
    public private(set) static var rgba: [UInt32] = rgbaValues(for: .pepto)

    /// Select a preset. Call between frames on the thread that drives
    /// emulation, since VIC rendering reads `rgba` without locking.
    public static func apply(_ preset: Preset) {
        activePreset = preset
        rgba = rgbaValues(for: preset)
    }

    public static func rgbaValues(for preset: Preset) -> [UInt32] {
        preset.colors.map { c in
            UInt32(c.r) | UInt32(c.g) << 8 | UInt32(c.b) << 16 | 0xFF000000
        }
    }
}
