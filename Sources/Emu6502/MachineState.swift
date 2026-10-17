import Foundation

/// Errors raised while reading a machine snapshot.
public enum MachineStateError: Error, Equatable, LocalizedError {
    case truncated
    case badMagic
    case unsupportedVersion(UInt16)
    case unexpectedChunk(found: String, expected: String)
    case chunkLengthMismatch(String)
    case invalidValue(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .truncated: return "The snapshot ends early."
        case .badMagic: return "This is not a Swift64 snapshot."
        case let .unsupportedVersion(version): return "Snapshot version \(version) is not supported."
        case let .unexpectedChunk(found, expected): return "Expected snapshot section \(expected) but found \(found)."
        case let .chunkLengthMismatch(tag): return "Snapshot section \(tag) has an inconsistent length."
        case let .invalidValue(what): return "Snapshot holds an invalid \(what)."
        case let .decodingFailed(what): return "Could not decode \(what) from the snapshot."
        }
    }
}

/// A value that can be written to and read back from a snapshot stream.
public protocol StateSerializable {
    func writeState(to writer: inout StateWriter)
    static func readState(from reader: inout StateReader) throws -> Self
}

/// Little-endian binary writer with length-prefixed chunks.
public struct StateWriter {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    public mutating func write<T: StateSerializable>(_ value: T) {
        value.writeState(to: &self)
    }

    /// Fast path for byte arrays such as RAM and disk tracks.
    public mutating func write(_ value: [UInt8]) {
        writeInteger(UInt32(value.count))
        bytes.append(contentsOf: value)
    }

    public mutating func writeInteger<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { bytes.append(contentsOf: $0) }
    }

    /// Start a chunk: four-character tag, version, and a length patched by `endChunk`.
    public mutating func beginChunk(_ tag: String, version: UInt16) -> Int {
        let tagBytes = Array(tag.utf8)
        precondition(tagBytes.count == 4, "chunk tags are four ASCII characters")
        bytes.append(contentsOf: tagBytes)
        writeInteger(version)
        let lengthOffset = bytes.count
        writeInteger(UInt32(0))
        return lengthOffset
    }

    public mutating func endChunk(_ lengthOffset: Int) {
        let length = UInt32(bytes.count - lengthOffset - 4)
        var little = length.littleEndian
        withUnsafeBytes(of: &little) { raw in
            for (index, byte) in raw.enumerated() { bytes[lengthOffset + index] = byte }
        }
    }

    /// Embed a Codable value as a binary property list.
    public mutating func writeCodable<T: Encodable>(_ value: T) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        write([UInt8](try encoder.encode(value)))
    }
}

/// Reader matching `StateWriter`. Every read is bounds-checked.
public struct StateReader {
    private let bytes: [UInt8]
    private(set) var offset: Int
    private let end: Int

    public init(bytes: [UInt8]) {
        self.bytes = bytes
        offset = 0
        end = bytes.count
    }

    private init(bytes: [UInt8], offset: Int, end: Int) {
        self.bytes = bytes
        self.offset = offset
        self.end = end
    }

    public var remaining: Int { end - offset }
    public var isAtEnd: Bool { offset >= end }

    public mutating func read<T: StateSerializable>() throws -> T {
        try T.readState(from: &self)
    }

    public mutating func read() throws -> [UInt8] {
        let count = Int(try readInteger() as UInt32)
        return Array(try readBytes(count))
    }

    public mutating func readBytes(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, remaining >= count else { throw MachineStateError.truncated }
        let slice = bytes[offset..<offset + count]
        offset += count
        return slice
    }

    public mutating func readInteger<T: FixedWidthInteger>() throws -> T {
        let size = MemoryLayout<T>.size
        guard remaining >= size else { throw MachineStateError.truncated }
        var value: T = 0
        withUnsafeMutableBytes(of: &value) { raw in
            for index in 0..<size { raw[index] = bytes[offset + index] }
        }
        offset += size
        return T(littleEndian: value)
    }

    /// Read a chunk header and return a reader limited to its body.
    public mutating func readChunk() throws -> (tag: String, version: UInt16, body: StateReader) {
        let tag = String(decoding: try readBytes(4), as: UTF8.self)
        let version: UInt16 = try readInteger()
        let length = Int(try readInteger() as UInt32)
        guard remaining >= length else { throw MachineStateError.truncated }
        let body = StateReader(bytes: bytes, offset: offset, end: offset + length)
        offset += length
        return (tag, version, body)
    }

    public mutating func expectChunk(_ tag: String) throws -> (version: UInt16, body: StateReader) {
        let chunk = try readChunk()
        guard chunk.tag == tag else {
            throw MachineStateError.unexpectedChunk(found: chunk.tag, expected: tag)
        }
        return (chunk.version, chunk.body)
    }

    /// Fail unless a chunk body was consumed exactly.
    public func finishChunk(_ tag: String) throws {
        guard isAtEnd else { throw MachineStateError.chunkLengthMismatch(tag) }
    }

    public mutating func readCodable<T: Decodable>(_ type: T.Type, label: String) throws -> T {
        let blob: [UInt8] = try read()
        do {
            return try PropertyListDecoder().decode(type, from: Data(blob))
        } catch {
            throw MachineStateError.decodingFailed(label)
        }
    }
}

// MARK: - Primitive conformances

extension UInt8: StateSerializable {
    public func writeState(to writer: inout StateWriter) { writer.writeInteger(self) }
    public static func readState(from reader: inout StateReader) throws -> UInt8 { try reader.readInteger() }
}
extension UInt16: StateSerializable {
    public func writeState(to writer: inout StateWriter) { writer.writeInteger(self) }
    public static func readState(from reader: inout StateReader) throws -> UInt16 { try reader.readInteger() }
}
extension UInt32: StateSerializable {
    public func writeState(to writer: inout StateWriter) { writer.writeInteger(self) }
    public static func readState(from reader: inout StateReader) throws -> UInt32 { try reader.readInteger() }
}
extension UInt64: StateSerializable {
    public func writeState(to writer: inout StateWriter) { writer.writeInteger(self) }
    public static func readState(from reader: inout StateReader) throws -> UInt64 { try reader.readInteger() }
}
extension Int8: StateSerializable {
    public func writeState(to writer: inout StateWriter) { writer.writeInteger(self) }
    public static func readState(from reader: inout StateReader) throws -> Int8 { try reader.readInteger() }
}
extension Int16: StateSerializable {
    public func writeState(to writer: inout StateWriter) { writer.writeInteger(self) }
    public static func readState(from reader: inout StateReader) throws -> Int16 { try reader.readInteger() }
}
extension Int32: StateSerializable {
    public func writeState(to writer: inout StateWriter) { writer.writeInteger(self) }
    public static func readState(from reader: inout StateReader) throws -> Int32 { try reader.readInteger() }
}
extension Int64: StateSerializable {
    public func writeState(to writer: inout StateWriter) { writer.writeInteger(self) }
    public static func readState(from reader: inout StateReader) throws -> Int64 { try reader.readInteger() }
}
extension Int: StateSerializable {
    public func writeState(to writer: inout StateWriter) { writer.writeInteger(Int64(self)) }
    public static func readState(from reader: inout StateReader) throws -> Int {
        let value: Int64 = try reader.readInteger()
        guard let result = Int(exactly: value) else { throw MachineStateError.invalidValue("integer") }
        return result
    }
}
extension Bool: StateSerializable {
    public func writeState(to writer: inout StateWriter) { writer.writeInteger(UInt8(self ? 1 : 0)) }
    public static func readState(from reader: inout StateReader) throws -> Bool {
        switch try reader.readInteger() as UInt8 {
        case 0: return false
        case 1: return true
        default: throw MachineStateError.invalidValue("boolean")
        }
    }
}
extension Float: StateSerializable {
    public func writeState(to writer: inout StateWriter) { writer.writeInteger(bitPattern) }
    public static func readState(from reader: inout StateReader) throws -> Float { Float(bitPattern: try reader.readInteger()) }
}
extension Double: StateSerializable {
    public func writeState(to writer: inout StateWriter) { writer.writeInteger(bitPattern) }
    public static func readState(from reader: inout StateReader) throws -> Double { Double(bitPattern: try reader.readInteger()) }
}
extension String: StateSerializable {
    public func writeState(to writer: inout StateWriter) { writer.write(Array(utf8)) }
    public static func readState(from reader: inout StateReader) throws -> String {
        let bytes: [UInt8] = try reader.read()
        guard let string = String(bytes: bytes, encoding: .utf8) else { throw MachineStateError.invalidValue("string") }
        return string
    }
}
extension Array: StateSerializable where Element: StateSerializable {
    public func writeState(to writer: inout StateWriter) {
        writer.writeInteger(UInt32(count))
        for element in self { element.writeState(to: &writer) }
    }
    public static func readState(from reader: inout StateReader) throws -> [Element] {
        let count = Int(try reader.readInteger() as UInt32)
        guard count <= reader.remaining else { throw MachineStateError.truncated }
        var result: [Element] = []
        result.reserveCapacity(count)
        for _ in 0..<count { result.append(try Element.readState(from: &reader)) }
        return result
    }
}
extension Optional: StateSerializable where Wrapped: StateSerializable {
    public func writeState(to writer: inout StateWriter) {
        if let value = self {
            writer.write(true)
            value.writeState(to: &writer)
        } else {
            writer.write(false)
        }
    }
    public static func readState(from reader: inout StateReader) throws -> Wrapped? {
        let present: Bool = try reader.read()
        return present ? try Wrapped.readState(from: &reader) : nil
    }
}
