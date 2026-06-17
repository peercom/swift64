import XCTest
@testable import C64Core

final class C64ROMValidationTests: XCTestCase {
    func testValidatedC64ROMLoadingAcceptsExpectedSizes() throws {
        let c64 = C64()
        let basic = Data(repeating: 0xBA, count: C64.basicROMSize)
        let kernal = Data(repeating: 0xE0, count: C64.kernalROMSize)
        let charset = Data(repeating: 0xC4, count: C64.characterROMSize)

        try c64.loadROMsValidated(basic: basic, kernal: kernal, charset: charset)

        XCTAssertEqual(c64.memory.basicROM.count, C64.basicROMSize)
        XCTAssertEqual(c64.memory.kernalROM.count, C64.kernalROMSize)
        XCTAssertEqual(c64.memory.charROM.count, C64.characterROMSize)
        XCTAssertEqual(c64.memory.basicROM[0], 0xBA)
        XCTAssertEqual(c64.memory.kernalROM[0], 0xE0)
        XCTAssertEqual(c64.memory.charROM[0], 0xC4)
    }

    func testValidatedC64ROMLoadingRejectsWrongSize() {
        let c64 = C64()
        let basic = Data(repeating: 0xBA, count: C64.basicROMSize - 1)
        let kernal = Data(repeating: 0xE0, count: C64.kernalROMSize)
        let charset = Data(repeating: 0xC4, count: C64.characterROMSize)

        XCTAssertThrowsError(try c64.loadROMsValidated(basic: basic, kernal: kernal, charset: charset)) { error in
            XCTAssertEqual(
                error as? C64ROMValidationError,
                .invalidSize(name: "BASIC", expected: C64.basicROMSize, actual: C64.basicROMSize - 1)
            )
        }
    }

    func testValidatedDriveROMLoadingRejectsWrongSize() {
        let c64 = C64()
        let driveROM = Data(repeating: 0xFF, count: C64.drive1541ROMSize + 1)

        XCTAssertThrowsError(try c64.loadDriveROMValidated(driveROM)) { error in
            XCTAssertEqual(
                error as? C64ROMValidationError,
                .invalidSize(name: "1541 drive", expected: C64.drive1541ROMSize, actual: C64.drive1541ROMSize + 1)
            )
        }
    }
}

