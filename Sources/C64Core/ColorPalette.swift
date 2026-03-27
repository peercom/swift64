import Foundation

/// C64 16-color palette (RGBA8888). Based on the VICE "pepto" palette.
public struct ColorPalette {
    public static let colors: [(r: UInt8, g: UInt8, b: UInt8)] = [
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

    /// Pre-computed RGBA32 values in little-endian byte order for Metal rgba8Unorm textures.
    /// Memory layout: [R, G, B, A] — on little-endian this is stored as 0xAABBGGRR.
    public static let rgba: [UInt32] = colors.map { c in
        UInt32(c.r) | UInt32(c.g) << 8 | UInt32(c.b) << 16 | 0xFF000000
    }
}
