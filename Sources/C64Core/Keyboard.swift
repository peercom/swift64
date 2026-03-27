import Foundation

/// Maps macOS key codes to the C64 8×8 keyboard matrix.
/// The C64 keyboard is scanned by setting Port A (rows) and reading Port B (columns).
///
/// Matrix layout (row, column):
///   Col:    0      1      2      3      4      5      6      7
/// Row 0: DEL    RET    CRS→   F7     F1     F3     F5     CRS↓
/// Row 1: 3      W      A      4      Z      S      E      LSHIFT
/// Row 2: 5      R      D      6      C      F      T      X
/// Row 3: 7      Y      G      8      B      H      U      V
/// Row 4: 9      I      J      0      M      K      O      N
/// Row 5: +      P      L      -      .      :      @      ,
/// Row 6: £      *      ;      HOME   RSHIFT =      ↑      /
/// Row 7: 1      ←      CTRL   2      SPACE  C=     Q      STOP
public final class Keyboard {

    /// Reference to CIA1's keyboard matrix
    public weak var cia: CIA?

    /// Current key state: maps (row, col) to pressed state
    var keyState = [[Bool]](repeating: [Bool](repeating: false, count: 8), count: 8)

    public init() {}

    /// Press a key by its matrix position
    public func pressKey(row: Int, col: Int) {
        guard row >= 0 && row < 8 && col >= 0 && col < 8 else { return }
        keyState[row][col] = true
        updateMatrix()
    }

    /// Release a key by its matrix position
    public func releaseKey(row: Int, col: Int) {
        guard row >= 0 && row < 8 && col >= 0 && col < 8 else { return }
        keyState[row][col] = false
        updateMatrix()
    }

    /// Update the CIA1 keyboard matrix from our state
    func updateMatrix() {
        guard let cia = cia else { return }
        for row in 0..<8 {
            var rowBits: UInt8 = 0xFF
            for col in 0..<8 {
                if keyState[row][col] {
                    rowBits &= ~(1 << col)
                }
            }
            cia.keyboardMatrix[row] = rowBits
        }
    }

    /// Handle a macOS key event. Returns true if the key was handled.
    /// `characters` is the typed character string (from NSEvent.characters),
    /// used for symbolic mapping of shifted punctuation.
    public func handleKeyDown(keyCode: UInt16, characters: String? = nil) -> Bool {
        // Symbolic mapping: Mac shifted symbols → C64 keys
        if let mapping = symbolMapping(characters) {
            // Release Mac shift — C64 may or may not need shift for this symbol
            releaseKey(row: 1, col: 7)
            releaseKey(row: 6, col: 4)
            if mapping.shift {
                pressKey(row: 1, col: 7)
            }
            pressKey(row: mapping.row, col: mapping.col)
            return true
        }

        // Cursor left/up need shift held on C64
        if keyCode == 123 || keyCode == 126 {
            pressKey(row: 1, col: 7)  // Left Shift
        }
        if let (row, col) = macKeyToC64(keyCode) {
            pressKey(row: row, col: col)
            return true
        }
        return false
    }

    public func handleKeyUp(keyCode: UInt16, characters: String? = nil) -> Bool {
        if let mapping = symbolMapping(characters) {
            releaseKey(row: mapping.row, col: mapping.col)
            if mapping.shift {
                releaseKey(row: 1, col: 7)
            }
            return true
        }

        if keyCode == 123 || keyCode == 126 {
            releaseKey(row: 1, col: 7)  // Left Shift
        }
        if let (row, col) = macKeyToC64(keyCode) {
            releaseKey(row: row, col: col)
            return true
        }
        return false
    }

    /// Map Mac typed characters to C64 matrix positions for symbols that
    /// differ between Mac and C64 keyboard layouts.
    /// Returns (row, col, needsShift) or nil if no special mapping needed.
    func symbolMapping(_ characters: String?) -> (row: Int, col: Int, shift: Bool)? {
        guard let ch = characters?.first else { return nil }
        switch ch {
        case "*": return (6, 1, false)   // C64 * is its own key
        case "(": return (3, 3, true)    // C64 ( is Shift+8
        case ")": return (4, 0, true)    // C64 ) is Shift+9
        case "&": return (2, 3, true)    // C64 & is Shift+6
        default: return nil
        }
    }

    /// Map macOS virtual key codes to C64 matrix positions (row, col).
    func macKeyToC64(_ keyCode: UInt16) -> (Int, Int)? {
        switch keyCode {
        // Number row
        case 18:  return (7, 0)  // 1
        case 19:  return (7, 3)  // 2
        case 20:  return (1, 0)  // 3
        case 21:  return (1, 3)  // 4
        case 23:  return (2, 0)  // 5
        case 22:  return (2, 3)  // 6
        case 26:  return (3, 0)  // 7
        case 28:  return (3, 3)  // 8
        case 25:  return (4, 0)  // 9
        case 29:  return (4, 3)  // 0

        // Letters
        case 0:   return (1, 2)  // A
        case 11:  return (3, 4)  // B
        case 8:   return (2, 4)  // C
        case 2:   return (2, 2)  // D
        case 14:  return (1, 6)  // E
        case 3:   return (2, 5)  // F
        case 5:   return (3, 2)  // G
        case 4:   return (3, 5)  // H
        case 34:  return (4, 1)  // I
        case 38:  return (4, 2)  // J
        case 40:  return (4, 5)  // K
        case 37:  return (5, 2)  // L
        case 46:  return (4, 4)  // M
        case 45:  return (4, 7)  // N
        case 31:  return (4, 6)  // O
        case 35:  return (5, 1)  // P
        case 12:  return (7, 6)  // Q
        case 15:  return (2, 1)  // R
        case 1:   return (1, 5)  // S
        case 17:  return (2, 6)  // T
        case 32:  return (3, 6)  // U
        case 9:   return (3, 7)  // V
        case 13:  return (1, 1)  // W
        case 7:   return (2, 7)  // X
        case 16:  return (3, 1)  // Y
        case 6:   return (1, 4)  // Z

        // Special keys
        case 36:  return (0, 1)  // Return
        case 49:  return (7, 4)  // Space
        case 51:  return (0, 0)  // Delete (Backspace → INST/DEL)
        case 53:  return (7, 7)  // Escape → RUN/STOP
        case 48:  return nil     // Tab (not used, or could map to Ctrl)

        // Shift keys
        case 56:  return (1, 7)  // Left Shift
        case 60:  return (6, 4)  // Right Shift

        // Arrow keys
        case 123: return (0, 2)  // Left → CRSR← (shift + CRSR→)
        case 124: return (0, 2)  // Right → CRSR→
        case 125: return (0, 7)  // Down → CRSR↓
        case 126: return (0, 7)  // Up → CRSR↑ (shift + CRSR↓)

        // Function keys
        case 122: return (0, 4)  // F1
        case 120: return (0, 5)  // F3
        case 99:  return (0, 6)  // F5
        case 118: return (0, 3)  // F7

        // Punctuation
        case 27:  return (5, 3)  // -  (minus)
        case 24:  return (5, 0)  // =  (plus on C64) → +
        case 33:  return (5, 5)  // [  → :
        case 30:  return (5, 6)  // ]  → @
        case 41:  return (5, 7)  // ;  → ,
        case 39:  return (6, 2)  // '  → ;
        case 43:  return (5, 4)  // ,  → .
        case 47:  return (6, 7)  // .  → /
        case 44:  return (6, 7)  // /  → /
        case 50:  return (7, 1)  // `  → ←

        // Modifier keys
        case 59:  return (7, 2)  // Control
        case 58:  return (7, 5)  // Option → C= key

        // Home
        case 115: return (6, 3)  // Home → CLR/HOME

        default:  return nil
        }
    }

    /// Check if RESTORE key is pressed (triggers NMI).
    /// We map Page Up or F12 to RESTORE.
    public func isRestoreKey(_ keyCode: UInt16) -> Bool {
        return keyCode == 116 || keyCode == 111  // Page Up or F12
    }
}
