import Foundation

/// Virtual datasette — parses T64 and TAP files for Kernal trap loading.
public final class TapeUnit {

    // MARK: - T64 directory entry

    public struct T64Entry {
        public let entryType: UInt8    // 0=free, 1=normal tape file, 3=memory snapshot
        public let fileType: UInt8     // C64 file type (PRG=1, SEQ=2, etc.)
        public let startAddress: UInt16
        public let endAddress: UInt16
        public let filename: String
        public let dataOffset: Int
        public let dataSize: Int
    }

    public struct TAPPulse: Equatable {
        public let cycles: Int
        public let isOverflow: Bool
    }

    // MARK: - State

    /// Raw image data
    var imageData: [UInt8]?

    /// T64 entries
    public private(set) var entries: [T64Entry] = []

    /// Container name
    public private(set) var containerName: String = ""

    /// Format type
    public enum Format: Equatable {
        case t64
        case tap
    }
    public private(set) var format: Format?

    /// TAP: decoded PRG data (header + payload)
    var tapPRGData: [UInt8]?

    /// TAP: raw pulse durations in C64 CPU cycles.
    public private(set) var tapPulses: [TAPPulse] = []

    /// Current datasette read signal level produced by raw TAP playback.
    public private(set) var readSignalHigh: Bool = true

    /// True while the raw TAP playback cursor is consuming pulse durations.
    public private(set) var rawPlaybackActive: Bool = false

    public private(set) var currentPulseIndex: Int = 0
    public private(set) var cyclesUntilNextPulse: Int = 0

    // MARK: - Init

    public init() {}

    // MARK: - Mount / Unmount

    public func mount(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 20 else { return false }

        // Try T64 first
        if isT64(bytes) {
            return mountT64(bytes)
        }

        // Try TAP
        if isTAP(bytes) {
            return mountTAP(bytes)
        }

        return false
    }

    public func mountFromFile(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return mount(data)
    }

    public func unmount() {
        imageData = nil
        entries = []
        containerName = ""
        format = nil
        tapPRGData = nil
        tapPulses = []
        stopRawPlayback()
    }

    public var isMounted: Bool { imageData != nil }

    // MARK: - T64 format

    func isT64(_ bytes: [UInt8]) -> Bool {
        // Check for "C64" signature at start
        guard bytes.count >= 64 else { return false }
        let sig = String(bytes: Array(bytes[0..<3]), encoding: .ascii) ?? ""
        return sig == "C64"
    }

    func mountT64(_ bytes: [UInt8]) -> Bool {
        var parsedEntries: [T64Entry] = []

        // Header: 64 bytes
        // $20-$21: version
        // $22-$23: max directory entries
        // $24-$25: used entries
        guard bytes.count >= 64 else { return false }

        let maxEntries = Int(bytes[0x22]) | (Int(bytes[0x23]) << 8)
        let usedEntries = Int(bytes[0x24]) | (Int(bytes[0x25]) << 8)

        // Container name at offset $28, 24 bytes
        let parsedContainerName = readString(bytes, offset: 0x28, length: 24)

        // Entries start at offset $40, 32 bytes each
        let entryCount = min(usedEntries, maxEntries)
        for i in 0..<entryCount {
            let base = 0x40 + i * 32
            guard base + 32 <= bytes.count else { break }

            let entryType = bytes[base]
            if entryType == 0 { continue }  // Free entry

            let fileType = bytes[base + 1]
            let startAddr = UInt16(bytes[base + 2]) | (UInt16(bytes[base + 3]) << 8)
            let endAddr = UInt16(bytes[base + 4]) | (UInt16(bytes[base + 5]) << 8)
            let dataOffset = Int(bytes[base + 8]) | (Int(bytes[base + 9]) << 8) |
                             (Int(bytes[base + 10]) << 16) | (Int(bytes[base + 11]) << 24)
            let filename = readString(bytes, offset: base + 16, length: 16)
            let dataSize = Int(endAddr) - Int(startAddr)
            guard dataSize >= 0,
                  dataOffset >= 0,
                  dataOffset <= bytes.count,
                  dataSize <= bytes.count - dataOffset else { continue }

            parsedEntries.append(T64Entry(
                entryType: entryType,
                fileType: fileType,
                startAddress: startAddr,
                endAddress: endAddr,
                filename: filename,
                dataOffset: dataOffset,
                dataSize: dataSize
            ))
        }

        guard !parsedEntries.isEmpty else { return false }

        stopRawPlayback()
        imageData = bytes
        format = .t64
        containerName = parsedContainerName
        tapPulses = []
        tapPRGData = nil
        entries = parsedEntries
        return true
    }

    // MARK: - TAP format

    func isTAP(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 20 else { return false }
        let sig = String(bytes: Array(bytes[0..<12]), encoding: .ascii) ?? ""
        return sig.hasPrefix("C64-TAPE-RAW")
    }

    func mountTAP(_ bytes: [UInt8]) -> Bool {
        // TAP files contain raw pulse data. For Kernal trap loading,
        // we decode the tape data to extract the PRG payload.
        // TAP header: 20 bytes
        // $00-$0B: signature "C64-TAPE-RAW"
        // $0C: TAP version (0 or 1)
        // $10-$13: data size (LE 32-bit)

        guard bytes.count >= 20 else { return false }
        let version = bytes[0x0C]
        let dataSize = Int(bytes[0x10]) | (Int(bytes[0x11]) << 8) |
                        (Int(bytes[0x12]) << 16) | (Int(bytes[0x13]) << 24)
        guard dataSize >= 0, 20 + dataSize <= bytes.count else { return false }
        guard let pulses = decodeTAPPulses(bytes, headerSize: 20, dataSize: dataSize, version: version),
              !pulses.isEmpty else { return false }

        stopRawPlayback()
        imageData = bytes
        format = .tap
        entries = []
        containerName = "TAP IMAGE"
        tapPulses = pulses

        // For TAP files, we attempt to decode the CBM tape encoding.
        // This is complex (pilot tones, sync, data blocks) — for now we
        // just store the raw data. The Kernal trap will use a simplified approach.
        tapPRGData = decodeTAPData(bytes, headerSize: 20, dataSize: dataSize, version: version)

        if let prg = tapPRGData, prg.count >= 3 {
            let addr = UInt16(prg[0]) | (UInt16(prg[1]) << 8)
            entries = [T64Entry(
                entryType: 1,
                fileType: 1,
                startAddress: addr,
                endAddress: addr + UInt16(prg.count - 2),
                filename: "TAP FILE",
                dataOffset: 0,
                dataSize: prg.count - 2
            )]
            return true
        }

        return true
    }

    @discardableResult
    public func startRawPlayback() -> Bool {
        guard !tapPulses.isEmpty else { return false }
        readSignalHigh = true
        rawPlaybackActive = true
        currentPulseIndex = 0
        cyclesUntilNextPulse = tapPulses[0].cycles
        return true
    }

    public func stopRawPlayback() {
        rawPlaybackActive = false
        readSignalHigh = true
        currentPulseIndex = 0
        cyclesUntilNextPulse = 0
    }

    public func tickRawPlayback(cycles: Int = 1) {
        guard rawPlaybackActive, cycles > 0 else { return }

        var remaining = cycles
        while rawPlaybackActive && remaining > 0 {
            if cyclesUntilNextPulse > remaining {
                cyclesUntilNextPulse -= remaining
                remaining = 0
            } else {
                remaining -= cyclesUntilNextPulse
                advanceRawPulse()
            }
        }
    }

    func advanceRawPulse() {
        readSignalHigh.toggle()
        currentPulseIndex += 1

        if currentPulseIndex >= tapPulses.count {
            rawPlaybackActive = false
            cyclesUntilNextPulse = 0
            return
        }

        cyclesUntilNextPulse = tapPulses[currentPulseIndex].cycles
    }

    func decodeTAPPulses(_ bytes: [UInt8], headerSize: Int, dataSize: Int, version: UInt8) -> [TAPPulse]? {
        guard version == 0 || version == 1 else { return nil }
        guard headerSize >= 0, dataSize >= 0, headerSize + dataSize <= bytes.count else { return nil }

        var pulses: [TAPPulse] = []
        var offset = headerSize
        let end = headerSize + dataSize

        while offset < end {
            let value = bytes[offset]
            offset += 1

            if value == 0 {
                if version == 0 {
                    pulses.append(TAPPulse(cycles: 256 * 8, isOverflow: true))
                } else {
                    guard offset + 3 <= end else { return nil }
                    let cycles = Int(bytes[offset])
                        | (Int(bytes[offset + 1]) << 8)
                        | (Int(bytes[offset + 2]) << 16)
                    offset += 3
                    pulses.append(TAPPulse(cycles: cycles, isOverflow: true))
                }
            } else {
                pulses.append(TAPPulse(cycles: Int(value) * 8, isOverflow: false))
            }
        }

        return pulses
    }

    /// Simplified TAP decoder: extract first PRG block from CBM tape encoding.
    func decodeTAPData(_ bytes: [UInt8], headerSize: Int, dataSize: Int, version: UInt8) -> [UInt8]? {
        // CBM tape format uses pulse lengths to encode bits.
        // A short pulse (~352 cycles) = 0, long pulse (~512 cycles) = 1
        // Each byte: 8 data bits + 1 parity bit + 2 marker bits
        // This is extremely complex to decode properly.
        //
        // For practical purposes, many TAP files also have the program data
        // at known offsets. We'll use a heuristic: scan for the data header
        // sequence and extract the following payload.
        //
        // If this fails, the user should convert TAP to T64 or PRG externally.
        return nil
    }

    // MARK: - File access

    /// Get the data for an entry (as PRG: load address + data).
    public func readEntry(_ index: Int) -> [UInt8]? {
        guard index >= 0 && index < entries.count else { return nil }
        let entry = entries[index]
        guard let bytes = imageData else { return nil }

        if format == .tap {
            return tapPRGData
        }

        // T64: extract data from offset
        let offset = entry.dataOffset
        let size = entry.dataSize
        guard offset >= 0 && offset + size <= bytes.count else { return nil }

        // Build PRG: start address + data
        var prg: [UInt8] = []
        prg.append(UInt8(entry.startAddress & 0xFF))
        prg.append(UInt8(entry.startAddress >> 8))
        prg.append(contentsOf: bytes[offset..<offset + size])
        return prg
    }

    /// Find an entry by name. Empty name or "*" returns first entry.
    public func findEntry(_ name: String) -> Int? {
        if name.isEmpty || name == "*" {
            return entries.isEmpty ? nil : 0
        }
        let search = name.uppercased()
        return entries.firstIndex { $0.filename.uppercased().hasPrefix(search) }
    }

    // MARK: - Helpers

    func readString(_ bytes: [UInt8], offset: Int, length: Int) -> String {
        var result = ""
        for i in 0..<length {
            let idx = offset + i
            guard idx < bytes.count else { break }
            let byte = bytes[idx]
            if byte == 0x00 || byte == 0xA0 { break }
            if byte >= 0x20 && byte < 0x7F {
                result.append(Character(UnicodeScalar(byte)))
            } else if byte >= 0xC1 && byte <= 0xDA {
                result.append(Character(UnicodeScalar(byte - 0x80)))
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
