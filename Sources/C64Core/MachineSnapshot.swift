import Foundation
import Emu6502

/// Wraps a Codable value so property-list encoding always has a container.
struct SnapshotBox<Value: Codable>: Codable {
    let value: Value
}

extension StateWriter {
    mutating func writeBoxed<T: Codable>(_ value: T) throws {
        try writeCodable(SnapshotBox(value: value))
    }
}

extension StateReader {
    mutating func readBoxed<T: Codable>(_ type: T.Type, label: String) throws -> T {
        try readCodable(SnapshotBox<T>.self, label: label).value
    }
}

/// Validates a fixed-length array read from a snapshot.
func snapshotFixed<T>(_ values: [T], count: Int, _ what: String) throws -> [T] {
    guard values.count == count else { throw MachineStateError.invalidValue(what) }
    return values
}

extension MachineProfile {
    /// Every built-in profile, used to resolve a snapshot's profile by name.
    public static let allPresets: [MachineProfile] = [
        .palC64, .palC64C, .palC64With1541II, .palC64CWith1541II,
        .ntscC64, .ntscC64C, .ntscC64With1541II, .ntscC64CWith1541II,
    ]
}
