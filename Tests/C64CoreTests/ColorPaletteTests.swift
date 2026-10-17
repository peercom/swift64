import XCTest
@testable import C64Core

final class ColorPaletteTests: XCTestCase {
    override func tearDown() {
        ColorPalette.apply(.pepto)
        super.tearDown()
    }

    func testDefaultPresetMatchesLegacyTable() {
        XCTAssertEqual(ColorPalette.activePreset, .pepto)
        XCTAssertEqual(ColorPalette.rgba, ColorPalette.rgbaValues(for: .pepto))
        XCTAssertEqual(ColorPalette.colors.count, 16)
        XCTAssertEqual(ColorPalette.rgba[6], 0xFF8D3140, "blue is stored as little-endian RGBA")
    }

    func testEveryPresetHasSixteenOpaqueColorsWithBlackAndWhite() {
        for preset in ColorPalette.Preset.allCases {
            let rgba = ColorPalette.rgbaValues(for: preset)
            XCTAssertEqual(rgba.count, 16, preset.displayName)
            XCTAssertTrue(rgba.allSatisfy { $0 & 0xFF000000 == 0xFF000000 }, preset.displayName)
            XCTAssertEqual(rgba[0], 0xFF000000, preset.displayName)
            XCTAssertEqual(rgba[1], 0xFFFFFFFF, preset.displayName)
            XCTAssertFalse(preset.displayName.isEmpty)
        }
    }

    func testApplyingPresetChangesVICOutputOnNextRasterline() {
        let vic = VIC()
        vic.reset()
        // Border is light blue (14) after reset; render one visible line.
        ColorPalette.apply(.colodore)
        XCTAssertEqual(ColorPalette.activePreset, .colodore)
        for _ in 0..<(VIC.firstVisibleLine + 1) * VIC.palCyclesPerLine { vic.tick() }
        let border = vic.framebuffer[0]
        XCTAssertEqual(border, ColorPalette.rgbaValues(for: .colodore)[14])
        XCTAssertNotEqual(border, ColorPalette.rgbaValues(for: .pepto)[14])
    }
}
