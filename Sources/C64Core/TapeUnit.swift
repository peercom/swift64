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

    public struct TapeWritePulse: Equatable {
        public let cyclesSincePreviousEdge: Int
        public let levelHigh: Bool
    }

    public enum TAPDecodeFailureReason: Equatable {
        case noStandardBlocks
        case malformedStandardBlocks
        case incompleteHeaderData
        case conflictingDuplicateData
    }

    public enum TAPDecodeStatus: Equatable {
        case none
        case rawPulsesOnly(pulseCount: Int)
        case decodedPrograms(programCount: Int, pulseCount: Int)
        case standardCBMNoPrograms(blockCount: Int, reason: TAPDecodeFailureReason)
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
    var tapPRGFilename: String?
    var tapPRGEntries: [[UInt8]] = []

    /// TAP: raw pulse durations in C64 CPU cycles.
    public private(set) var tapPulses: [TAPPulse] = []
    public private(set) var tapDecodeStatus: TAPDecodeStatus = .none

    public private(set) var hasUnsavedChanges = false

    /// Current datasette read signal level produced by raw TAP playback.
    public private(set) var readSignalHigh: Bool = true

    /// True while the raw TAP playback cursor is consuming pulse durations.
    public private(set) var rawPlaybackActive: Bool = false

    public private(set) var currentPulseIndex: Int = 0
    public private(set) var cyclesUntilNextPulse: Int = 0

    /// Captured cassette write-line transitions while the motor is running.
    public private(set) var writePulses: [TapeWritePulse] = []

    public private(set) var writeLineHigh: Bool = false
    private var lastWritePulseCycle: UInt64?

    // MARK: - Init

    public init() {}

    // MARK: - Mount / Unmount

    public func mount(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 20 else { return false }

        // Try TAP first: TAP signatures also begin with "C64", so the older
        // loose T64 check would otherwise misclassify larger TAP files.
        if isTAP(bytes) {
            return mountTAP(bytes)
        }

        // Try T64
        if isT64(bytes) {
            return mountT64(bytes)
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
        tapPRGFilename = nil
        tapPRGEntries = []
        tapPulses = []
        tapDecodeStatus = .none
        hasUnsavedChanges = false
        stopRawPlayback()
        clearWriteCapture()
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
        tapDecodeStatus = .none
        tapPRGData = nil
        tapPRGFilename = nil
        tapPRGEntries = []
        entries = parsedEntries
        hasUnsavedChanges = false
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
        tapPRGFilename = nil
        tapPRGEntries = []
        hasUnsavedChanges = false

        let decodeResult = decodeTAPProgramsWithStatus(bytes, headerSize: 20, dataSize: dataSize, version: version)
        let decodedPrograms = decodeResult.programs
        tapPRGEntries = decodedPrograms.map(\.data)
        tapPRGData = tapPRGEntries.first
        tapPRGFilename = decodedPrograms.first?.filename
        tapDecodeStatus = decodeResult.status(pulseCount: pulses.count)

        let decodedEntries: [T64Entry] = decodedPrograms.enumerated().compactMap { index, decoded in
            let prg = decoded.data
            guard prg.count >= 3 else { return nil }
            let addr = UInt16(prg[0]) | (UInt16(prg[1]) << 8)
            return T64Entry(
                entryType: 1,
                fileType: 1,
                startAddress: addr,
                endAddress: addr + UInt16(prg.count - 2),
                filename: decoded.filename ?? (index == 0 ? "TAP FILE" : "TAP FILE \(index + 1)"),
                dataOffset: index,
                dataSize: prg.count - 2
            )
        }
        if !decodedEntries.isEmpty {
            entries = decodedEntries
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

    public func observeCassetteWriteLine(high: Bool, atCycle cycle: UInt64, motorEnabled: Bool) {
        guard writeLineHigh != high else { return }
        writeLineHigh = high

        guard motorEnabled else {
            lastWritePulseCycle = nil
            return
        }

        let delta = lastWritePulseCycle.map { previous in
            cycle >= previous ? Int(cycle - previous) : 0
        } ?? 0
        writePulses.append(TapeWritePulse(cyclesSincePreviousEdge: delta, levelHigh: high))
        lastWritePulseCycle = cycle
    }

    public func observeCassetteMotor(enabled: Bool) {
        if !enabled {
            lastWritePulseCycle = nil
        }
    }

    public func clearWriteCapture() {
        writePulses = []
        writeLineHigh = false
        lastWritePulseCycle = nil
    }

    public func capturedWriteTAP(version: UInt8 = 1) -> Data? {
        guard version == 0 || version == 1 else { return nil }

        var payload: [UInt8] = []
        for pulse in writePulses where pulse.cyclesSincePreviousEdge > 0 {
            guard let encoded = encodeTAPPulseCycles(pulse.cyclesSincePreviousEdge, version: version) else {
                return nil
            }
            payload.append(contentsOf: encoded)
        }
        guard !payload.isEmpty else { return nil }

        var bytes = [UInt8](repeating: 0, count: 20)
        writeASCII("C64-TAPE-RAW", into: &bytes, at: 0)
        bytes[0x0C] = version
        writeUInt32LE(UInt32(payload.count), into: &bytes, at: 0x10)
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    public var exportedT64Image: Data? {
        guard format == .t64, let imageData else { return nil }
        return Data(imageData)
    }

    public func markChangesSaved() {
        hasUnsavedChanges = false
    }

    public func savePRG(filename: String, data: [UInt8]) -> Bool {
        guard data.count >= 2 else { return false }
        guard format == nil || format == .t64 else { return false }

        let normalizedName = normalizedT64Filename(filename)
        guard !normalizedName.isEmpty else { return false }
        guard !entries.contains(where: { $0.filename.uppercased() == normalizedName.uppercased() }) else { return false }

        var savedFiles: [(filename: String, data: [UInt8])] = []
        for index in entries.indices {
            guard let prg = readEntry(index) else { return false }
            savedFiles.append((entries[index].filename, prg))
        }
        savedFiles.append((normalizedName, data))

        guard let t64 = makeT64Image(files: savedFiles, containerName: containerName.isEmpty ? "SWIFT64 TAPE" : containerName) else {
            return false
        }
        guard mountT64([UInt8](t64)) else { return false }
        hasUnsavedChanges = true
        return true
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

    func encodeTAPPulseCycles(_ cycles: Int, version: UInt8) -> [UInt8]? {
        guard cycles > 0 else { return nil }

        if version == 0 {
            guard cycles % 8 == 0 else { return nil }
            let units = cycles / 8
            guard units >= 1 && units <= 256 else { return nil }
            return [UInt8(units == 256 ? 0 : units)]
        }

        guard cycles <= 0xFF_FFFF else { return nil }
        if cycles % 8 == 0 {
            let units = cycles / 8
            if units >= 1 && units <= 255 {
                return [UInt8(units)]
            }
        }

        return [
            0x00,
            UInt8(cycles & 0xFF),
            UInt8((cycles >> 8) & 0xFF),
            UInt8((cycles >> 16) & 0xFF)
        ]
    }

    private enum StandardTAPPulseClass {
        case short
        case medium
        case long
    }

    private struct DecodedTAPProgram {
        let filename: String?
        let data: [UInt8]
    }

    private struct TAPProgramDecodeResult {
        let programs: [DecodedTAPProgram]
        let blockCount: Int
        let failureReason: TAPDecodeFailureReason?

        func status(pulseCount: Int) -> TAPDecodeStatus {
            if !programs.isEmpty {
                return .decodedPrograms(programCount: programs.count, pulseCount: pulseCount)
            }
            guard let failureReason else {
                return .rawPulsesOnly(pulseCount: pulseCount)
            }
            return .standardCBMNoPrograms(blockCount: blockCount, reason: failureReason)
        }
    }

    private struct StandardTAPHeader: Equatable {
        let blockType: UInt8
        let startAddress: UInt16
        let endAddress: UInt16
        let filename: String?
    }

    private struct StandardTAPBlock {
        let bytes: [UInt8?]

        var validBytes: [UInt8]? {
            var decoded: [UInt8] = []
            decoded.reserveCapacity(bytes.count)
            for byte in bytes {
                guard let byte else { return nil }
                decoded.append(byte)
            }
            return decoded
        }
    }

    private enum StandardTAPDataSelection {
        case selected([UInt8])
        case incomplete
        case conflicting
    }

    /// Decode stock CBM ROM-loader TAP streams into the first loadable PRG.
    func decodeTAPData(_ bytes: [UInt8], headerSize: Int, dataSize: Int, version: UInt8) -> [UInt8]? {
        decodeTAPPrograms(bytes, headerSize: headerSize, dataSize: dataSize, version: version).first?.data
    }

    private func decodeTAPPrograms(
        _ bytes: [UInt8],
        headerSize: Int,
        dataSize: Int,
        version: UInt8
    ) -> [DecodedTAPProgram] {
        decodeTAPProgramsWithStatus(bytes, headerSize: headerSize, dataSize: dataSize, version: version).programs
    }

    private func decodeTAPProgramsWithStatus(
        _ bytes: [UInt8],
        headerSize: Int,
        dataSize: Int,
        version: UInt8
    ) -> TAPProgramDecodeResult {
        guard let pulses = decodeTAPPulses(bytes, headerSize: headerSize, dataSize: dataSize, version: version) else {
            return TAPProgramDecodeResult(programs: [], blockCount: 0, failureReason: nil)
        }
        let blocks = decodeStandardCBMTapeBlocks(pulses)
        return extractStandardCBMPrograms(from: blocks)
    }

    private func decodeStandardCBMTapeBlocks(_ pulses: [TAPPulse]) -> [StandardTAPBlock] {
        var blocks: [StandardTAPBlock] = []
        var current: [UInt8?] = []
        var index = 0

        while index + 1 < pulses.count {
            guard let first = classifyStandardTAPPulse(pulses[index].cycles),
                  let second = classifyStandardTAPPulse(pulses[index + 1].cycles) else {
                if !current.isEmpty {
                    blocks.append(StandardTAPBlock(bytes: current))
                    current = []
                }
                index += 1
                continue
            }

            if first == .long && second == .medium {
                index += 2
                current.append(decodeStandardCBMByte(from: pulses, index: &index))
                continue
            }

            if first == .long && second == .short {
                if !current.isEmpty {
                    blocks.append(StandardTAPBlock(bytes: current))
                    current = []
                }
                index += 2
                continue
            }

            if !current.isEmpty {
                blocks.append(StandardTAPBlock(bytes: current))
                current = []
            }
            index += 1
        }

        if !current.isEmpty {
            blocks.append(StandardTAPBlock(bytes: current))
        }
        return blocks
    }

    private func decodeStandardCBMByte(from pulses: [TAPPulse], index: inout Int) -> UInt8? {
        var value: UInt8 = 0
        var oneBits = 0

        for bit in 0..<8 {
            guard let decodedBit = decodeStandardCBMBit(from: pulses, index: &index) else {
                return nil
            }
            if decodedBit {
                value |= UInt8(1 << bit)
                oneBits += 1
            }
        }

        guard let parityBit = decodeStandardCBMBit(from: pulses, index: &index) else {
            return nil
        }
        let totalOneBits = oneBits + (parityBit ? 1 : 0)
        guard totalOneBits % 2 == 1 else { return nil }
        return value
    }

    private func decodeStandardCBMBit(from pulses: [TAPPulse], index: inout Int) -> Bool? {
        guard index + 1 < pulses.count,
              let first = classifyStandardTAPPulse(pulses[index].cycles),
              let second = classifyStandardTAPPulse(pulses[index + 1].cycles) else {
            return nil
        }
        index += 2

        if first == .short && (second == .medium || second == .long) {
            return false
        }
        if (first == .medium || first == .long) && second == .short {
            return true
        }
        return nil
    }

    private func classifyStandardTAPPulse(_ cycles: Int) -> StandardTAPPulseClass? {
        let units = cycles / 8
        switch units {
        case 0x24...0x36:
            return .short
        case 0x37...0x49:
            return .medium
        case 0x4A...0x64:
            return .long
        default:
            return nil
        }
    }

    private func extractStandardCBMPrograms(from blocks: [StandardTAPBlock]) -> TAPProgramDecodeResult {
        var programs: [DecodedTAPProgram] = []
        var headerIndex = 0
        var sawHeader = false
        var sawMalformedBlock = false
        var failureReason: TAPDecodeFailureReason?

        while headerIndex < blocks.count {
            if blocks[headerIndex].validBytes == nil {
                sawMalformedBlock = true
            }

            guard let header = parseStandardTAPHeader(blocks[headerIndex]) else {
                headerIndex += 1
                continue
            }
            sawHeader = true

            var dataIndex = headerIndex + 1
            while dataIndex < blocks.count, parseStandardTAPHeader(blocks[dataIndex]) == header {
                dataIndex += 1
            }

            let payloadSize = Int(header.endAddress - header.startAddress)
            var candidates: [[UInt8?]] = []
            while dataIndex < blocks.count {
                if parseStandardTAPHeader(blocks[dataIndex]) != nil {
                    break
                }

                let dataBlock = blocks[dataIndex]
                if dataBlock.bytes.count >= payloadSize {
                    candidates.append(Array(dataBlock.bytes.prefix(payloadSize)))
                }

                dataIndex += 1
            }

            switch preferredStandardTAPDataCopy(candidates, expectedSize: payloadSize) {
            case let .selected(payload):
                var prg = [UInt8(header.startAddress & 0xFF), UInt8(header.startAddress >> 8)]
                prg.append(contentsOf: payload)
                programs.append(DecodedTAPProgram(filename: header.filename, data: prg))
            case .incomplete:
                if failureReason == nil {
                    failureReason = .incompleteHeaderData
                }
            case .conflicting:
                failureReason = .conflictingDuplicateData
            }

            headerIndex = max(dataIndex, headerIndex + 1)
        }

        if !programs.isEmpty {
            return TAPProgramDecodeResult(programs: programs, blockCount: blocks.count, failureReason: nil)
        }
        if sawHeader {
            return TAPProgramDecodeResult(
                programs: [],
                blockCount: blocks.count,
                failureReason: failureReason ?? .incompleteHeaderData
            )
        }

        var rawPrograms: [DecodedTAPProgram] = []
        for block in blocks {
            if block.validBytes == nil {
                sawMalformedBlock = true
            }
            guard let validBlock = block.validBytes,
                  validBlock.count >= 3 else { continue }
            let startAddress = UInt16(validBlock[0]) | (UInt16(validBlock[1]) << 8)
            let payloadSize = validBlock.count - 2
            guard startAddress >= 0x0200,
                  payloadSize <= Int(UInt16.max - startAddress) + 1 else { continue }
            rawPrograms.append(DecodedTAPProgram(filename: nil, data: validBlock))
        }

        let rawFailure: TAPDecodeFailureReason?
        if !rawPrograms.isEmpty {
            rawFailure = nil
        } else if blocks.isEmpty {
            rawFailure = nil
        } else if sawMalformedBlock {
            rawFailure = .malformedStandardBlocks
        } else {
            rawFailure = nil
        }
        return TAPProgramDecodeResult(programs: rawPrograms, blockCount: blocks.count, failureReason: rawFailure)
    }

    private func preferredStandardTAPDataCopy(_ candidates: [[UInt8?]], expectedSize: Int) -> StandardTAPDataSelection {
        guard !candidates.isEmpty else { return .incomplete }

        for candidate in candidates {
            let matches = candidates.filter { $0 == candidate }.count
            if matches > 1, let valid = fullyDecodedBytes(candidate) {
                return .selected(valid)
            }
        }

        switch repairedStandardTAPDataCopy(candidates, expectedSize: expectedSize) {
        case let .selected(repaired):
            return .selected(repaired)
        case .conflicting:
            return .conflicting
        case .incomplete:
            break
        }

        let exact = candidates.compactMap(fullyDecodedBytes).filter { $0.count == expectedSize }
        if exact.count == 1 {
            return .selected(exact[0])
        }
        if exact.count > 1 {
            return .conflicting
        }

        let decoded = candidates.compactMap(fullyDecodedBytes)
        if decoded.count == 1 {
            return .selected(decoded[0])
        }
        if decoded.count > 1 {
            return .conflicting
        }
        return .incomplete
    }

    private func repairedStandardTAPDataCopy(_ candidates: [[UInt8?]], expectedSize: Int) -> StandardTAPDataSelection {
        guard !candidates.isEmpty else { return .incomplete }
        var repaired: [UInt8] = []
        repaired.reserveCapacity(expectedSize)

        for offset in 0..<expectedSize {
            let values = candidates.compactMap { candidate -> UInt8? in
                guard offset < candidate.count else { return nil }
                return candidate[offset]
            }
            guard !values.isEmpty else { return .incomplete }

            var counts: [UInt8: Int] = [:]
            for value in values {
                counts[value, default: 0] += 1
            }

            let ranked = counts.sorted { lhs, rhs in
                lhs.value > rhs.value
            }
            guard let selected = ranked.first else {
                return .incomplete
            }
            if ranked.count > 1 && ranked[1].value == selected.value {
                return .conflicting
            }
            repaired.append(selected.key)
        }

        return .selected(repaired)
    }

    private func fullyDecodedBytes(_ bytes: [UInt8?]) -> [UInt8]? {
        var decoded: [UInt8] = []
        decoded.reserveCapacity(bytes.count)
        for byte in bytes {
            guard let byte else { return nil }
            decoded.append(byte)
        }
        return decoded
    }

    private func parseStandardTAPHeader(_ block: StandardTAPBlock) -> StandardTAPHeader? {
        guard let bytes = block.validBytes, bytes.count >= 21 else { return nil }
        let blockType = bytes[0]
        guard (1...5).contains(blockType) else { return nil }

        let startAddress = UInt16(bytes[1]) | (UInt16(bytes[2]) << 8)
        let endAddress = UInt16(bytes[3]) | (UInt16(bytes[4]) << 8)
        guard endAddress > startAddress else { return nil }

        let filename = readString(bytes, offset: 5, length: 16)
        return StandardTAPHeader(
            blockType: blockType,
            startAddress: startAddress,
            endAddress: endAddress,
            filename: filename.isEmpty ? nil : filename
        )
    }

    // MARK: - File access

    /// Get the data for an entry (as PRG: load address + data).
    public func readEntry(_ index: Int) -> [UInt8]? {
        guard index >= 0 && index < entries.count else { return nil }
        let entry = entries[index]
        guard let bytes = imageData else { return nil }

        if format == .tap {
            guard entry.dataOffset >= 0, entry.dataOffset < tapPRGEntries.count else { return nil }
            return tapPRGEntries[entry.dataOffset]
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

    private func makeT64Image(files: [(filename: String, data: [UInt8])], containerName: String) -> Data? {
        guard !files.isEmpty, files.count <= Int(UInt16.max) else { return nil }

        let directorySize = 0x40 + files.count * 32
        var bytes = [UInt8](repeating: 0, count: directorySize)
        writeASCII("C64S tape image file", into: &bytes, at: 0)
        bytes[0x20] = 0x01
        bytes[0x21] = 0x01
        writeUInt16LE(UInt16(files.count), into: &bytes, at: 0x22)
        writeUInt16LE(UInt16(files.count), into: &bytes, at: 0x24)
        writeASCII(containerName, into: &bytes, at: 0x28, maxLength: 24)

        var dataOffset = directorySize
        for (index, file) in files.enumerated() {
            guard file.data.count >= 2 else { return nil }
            let payloadSize = file.data.count - 2
            let startAddress = UInt16(file.data[0]) | (UInt16(file.data[1]) << 8)
            guard payloadSize <= Int(UInt16.max) else { return nil }
            let endAddress = startAddress &+ UInt16(payloadSize)
            guard Int(endAddress) >= Int(startAddress) else { return nil }

            let base = 0x40 + index * 32
            bytes[base] = 1
            bytes[base + 1] = 1
            writeUInt16LE(startAddress, into: &bytes, at: base + 2)
            writeUInt16LE(endAddress, into: &bytes, at: base + 4)
            writeUInt32LE(UInt32(dataOffset), into: &bytes, at: base + 8)
            writeASCII(normalizedT64Filename(file.filename), into: &bytes, at: base + 16, maxLength: 16)
            bytes.append(contentsOf: file.data.dropFirst(2))
            dataOffset += payloadSize
        }

        return Data(bytes)
    }

    private func normalizedT64Filename(_ filename: String) -> String {
        let trimmed = filename
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? filename
        return String(trimmed.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
    }

    private func writeASCII(_ string: String, into bytes: inout [UInt8], at offset: Int, maxLength: Int? = nil) {
        for (index, byte) in string.utf8.prefix(maxLength ?? string.utf8.count).enumerated() {
            bytes[offset + index] = byte
        }
    }

    private func writeUInt16LE(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8(value >> 8)
    }

    private func writeUInt32LE(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}
