import Foundation

/// Original, ROM-independent 6510 fixtures for audible end-to-end validation.
/// This deliberately simple tune is a diagnostic, not a hardware reference recording.
public enum SIDSoundCheck {
    public enum Kind: String { case tone, music }
    public static let entryPoint: UInt16 = 0x1000

    public static func program(kind: Kind, clockRate: Double, toneFrequency: Double = 440) -> Data {
        var p = Program()
        p.emit(0x78, 0xD8, 0xA2, 0xFF, 0x9A) // SEI, CLD, LDX #$FF, TXS
        p.store(0x35, at: 0x0001)
        p.store(0x7F, at: 0xDC0D)
        p.store(0x7F, at: 0xDD0D)
        p.emit(0xA9, 0, 0xA2, 24)
        p.label("clearSID")
        p.emit(0x9D, 0, 0xD4, 0xCA)
        p.branch(0x10, "clearSID")
        p.store(0x1B, at: 0xD011)
        p.store(8, at: 0xD016)
        p.store(0x14, at: 0xD018)
        p.store(6, at: 0xD020)
        p.store(0, at: 0xD021)
        p.emit(0xA2, 0)
        p.label("clearScreen")
        p.emit(0xA9, 32)
        for page: UInt8 in [4, 5, 6, 7] { p.emit(0x9D, 0, page) }
        p.emit(0xA9, 14)
        for page: UInt8 in [0xD8, 0xD9, 0xDA, 0xDB] { p.emit(0x9D, 0, page) }
        p.emit(0xE8)
        p.branch(0xD0, "clearScreen")
        for (index, character) in "SWIFT64 AUDIO CHECK".utf8.enumerated() {
            p.store(character >= 65 ? character - 64 : character, at: 0x0400 + UInt16(index))
        }
        let controls: [UInt8] = kind == .tone ? [0x41] : [0x41, 0x11, 0x21]
        for voice in controls.indices {
            let base = UInt16(0xD400 + voice * 7)
            p.store(8, at: base + 3)
            p.store(kind == .tone ? 0 : 0x09, at: base + 5)
            p.store(kind == .tone ? 0xF0 : 0xA8, at: base + 6)
        }
        if kind == .tone {
            let frequency = toneFrequency.isFinite ? min(10_000, max(20, toneFrequency)) : 440
            let word = frequencyWord(frequency, clockRate: clockRate)
            p.store(UInt8(truncatingIfNeeded: word), at: 0xD400)
            p.store(UInt8(word >> 8), at: 0xD401)
            p.store(0x41, at: 0xD404)
            p.store(15, at: 0xD418)
            p.label("tone")
            p.absolute(0x4C, "tone")
        } else {
            p.store(80, at: 0xD416)
            p.store(4, at: 0xD417) // Filter the accompaniment, leave lead/bass direct.
            p.store(0x1F, at: 0xD418)
            p.emit(0xA2, 0)
            p.label("note")
            for voice in controls.indices {
                let base = UInt16(0xD400 + voice * 7)
                p.absolute(0xBD, "lo\(voice)")
                p.emit(0x8D, UInt8(truncatingIfNeeded: base), 0xD4)
                p.absolute(0xBD, "hi\(voice)")
                p.emit(0x8D, UInt8(truncatingIfNeeded: base + 1), 0xD4)
                p.store(controls[voice], at: base + 4)
            }
            p.emit(0x8E, 0x20, 0xD0, 0xA0, 11)
            p.absolute(0x20, "waitFrames")
            for voice in controls.indices { p.store(controls[voice] & 0xFE, at: UInt16(0xD404 + voice * 7)) }
            p.emit(0xA0, 1)
            p.absolute(0x20, "waitFrames")
            p.emit(0xE8, 0x8A, 0x29, 15, 0xAA)
            p.absolute(0x4C, "note")
            p.label("waitFrames")
            p.emit(0xA9, 250)
            p.label("waitStart")
            p.emit(0xCD, 0x12, 0xD0)
            p.branch(0xD0, "waitStart")
            p.label("waitEnd")
            p.emit(0xCD, 0x12, 0xD0)
            p.branch(0xF0, "waitEnd")
            p.emit(0x88)
            p.branch(0xD0, "waitStart")
            p.emit(0x60)
            let notes = [
                [72, 76, 79, 74, 77, 81, 79, 76, 69, 72, 76, 74, 71, 74, 79, 72],
                [48, 48, 48, 48, 53, 53, 53, 53, 45, 45, 45, 45, 43, 43, 43, 43],
                [60, 64, 67, 64, 65, 69, 72, 69, 57, 60, 64, 60, 55, 59, 62, 59]
            ]
            for voice in notes.indices {
                let words = notes[voice].map { frequencyWord(440 * pow(2, Double($0 - 69) / 12), clockRate: clockRate) }
                p.label("lo\(voice)")
                p.bytes.append(contentsOf: words.map { UInt8(truncatingIfNeeded: $0) })
                p.label("hi\(voice)")
                p.bytes.append(contentsOf: words.map { UInt8($0 >> 8) })
            }
        }
        return p.data()
    }

    private static func frequencyWord(_ frequency: Double, clockRate: Double) -> UInt16 {
        UInt16(min(65535, max(0, (frequency * 16_777_216 / clockRate).rounded())))
    }

    private struct Program {
        var bytes: [UInt8] = []
        var labels: [String: Int] = [:]
        var fixups: [(offset: Int, label: String, relative: Bool)] = []
        mutating func emit(_ values: UInt8...) { bytes.append(contentsOf: values) }
        mutating func label(_ name: String) { labels[name] = bytes.count }
        mutating func store(_ value: UInt8, at address: UInt16) {
            emit(0xA9, value, 0x8D, UInt8(truncatingIfNeeded: address), UInt8(address >> 8))
        }
        mutating func branch(_ opcode: UInt8, _ target: String) {
            emit(opcode, 0)
            fixups.append((bytes.count - 1, target, true))
        }
        mutating func absolute(_ opcode: UInt8, _ target: String) {
            emit(opcode, 0, 0)
            fixups.append((bytes.count - 2, target, false))
        }
        mutating func data() -> Data {
            for fixup in fixups {
                let target = labels[fixup.label]!
                if fixup.relative {
                    bytes[fixup.offset] = UInt8(bitPattern: Int8(target - fixup.offset - 1))
                } else {
                    let address = entryPoint + UInt16(target)
                    bytes[fixup.offset] = UInt8(truncatingIfNeeded: address)
                    bytes[fixup.offset + 1] = UInt8(address >> 8)
                }
            }
            return Data([UInt8(truncatingIfNeeded: entryPoint), UInt8(entryPoint >> 8)] + bytes)
        }
    }
}
