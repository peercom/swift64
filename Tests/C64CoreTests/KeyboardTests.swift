import XCTest
@testable import C64Core

final class KeyboardTests: XCTestCase {
    func testDiskLoadPunctuationMapsByTypedCharacter() {
        let (keyboard, cia) = makeKeyboard()

        XCTAssertTrue(keyboard.handleKeyDown(keyCode: 39, characters: "\""))
        assertPressed(row: 7, col: 3, in: cia)
        assertPressed(row: 1, col: 7, in: cia)
        XCTAssertTrue(keyboard.handleKeyUp(keyCode: 39, characters: nil))
        assertReleased(row: 7, col: 3, in: cia)
        assertReleased(row: 1, col: 7, in: cia)

        XCTAssertTrue(keyboard.handleKeyDown(keyCode: 43, characters: ","))
        assertPressed(row: 5, col: 7, in: cia)
        assertReleased(row: 1, col: 7, in: cia)
        XCTAssertTrue(keyboard.handleKeyUp(keyCode: 43, characters: nil))
        assertReleased(row: 5, col: 7, in: cia)

        XCTAssertTrue(keyboard.handleKeyDown(keyCode: 21, characters: "$"))
        assertPressed(row: 1, col: 3, in: cia)
        assertPressed(row: 1, col: 7, in: cia)
        XCTAssertTrue(keyboard.handleKeyUp(keyCode: 21, characters: nil))
        assertReleased(row: 1, col: 3, in: cia)
        assertReleased(row: 1, col: 7, in: cia)
    }

    func testBasicCommandSymbolsMapToC64Keys() {
        let (keyboard, cia) = makeKeyboard()

        let symbols: [(String, UInt16, Int, Int, Bool)] = [
            ("*", 28, 6, 1, false),
            (",", 43, 5, 7, false),
            ("+", 24, 5, 0, false),
            ("-", 27, 5, 3, false),
            (".", 47, 5, 4, false),
            (":", 41, 5, 5, false),
            ("=", 24, 6, 5, false),
            ("@", 30, 5, 6, false)
        ]

        for (character, keyCode, row, col, shifted) in symbols {
            XCTAssertTrue(keyboard.handleKeyDown(keyCode: keyCode, characters: character), character)
            assertPressed(row: row, col: col, in: cia, character)
            if shifted {
                assertPressed(row: 1, col: 7, in: cia, character)
            } else {
                assertReleased(row: 1, col: 7, in: cia, character)
            }
            XCTAssertTrue(keyboard.handleKeyUp(keyCode: keyCode, characters: nil), character)
            assertReleased(row: row, col: col, in: cia, character)
            assertReleased(row: 1, col: 7, in: cia, character)
        }
    }

    private func makeKeyboard() -> (Keyboard, CIA) {
        let keyboard = Keyboard()
        let cia = CIA(isCIA1: true)
        keyboard.cia = cia
        return (keyboard, cia)
    }

    private func assertPressed(row: Int, col: Int, in cia: CIA, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(cia.keyboardMatrix[row] & UInt8(1 << col), 0, message, file: file, line: line)
    }

    private func assertReleased(row: Int, col: Int, in cia: CIA, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(cia.keyboardMatrix[row] & UInt8(1 << col), 0, message, file: file, line: line)
    }
}
