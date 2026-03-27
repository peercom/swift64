import Foundation

/// Virtual 1541 disk drive — parses D64 images and serves files via Kernal traps.
public final class DiskDrive {

    // MARK: - D64 format constants

    /// Sectors per track for the 35-track D64 format.
    static let sectorsPerTrack: [Int] = [
        0,  // track 0 doesn't exist
        21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21,  // 1-17
        19, 19, 19, 19, 19, 19, 19,  // 18-24
        18, 18, 18, 18, 18, 18,      // 25-30
        17, 17, 17, 17, 17,          // 31-35
    ]

    /// Byte offset of each track's first sector in the D64 image.
    static let trackOffset: [Int] = {
        var offsets = [0]  // track 0 placeholder
        var offset = 0
        for t in 1...35 {
            offsets.append(offset)
            offset += sectorsPerTrack[t] * 256
        }
        return offsets
    }()

    // MARK: - Directory entry

    public struct DirectoryEntry {
        public let filename: String       // Up to 16 chars, PETSCII
        public let filenameRaw: [UInt8]   // Raw 16 bytes
        public let fileType: UInt8        // $80=DEL, $81=SEQ, $82=PRG, $83=USR, $84=REL
        public let firstTrack: UInt8
        public let firstSector: UInt8
        public let fileSize: UInt16       // In sectors

        public var typeName: String {
            switch fileType & 0x07 {
            case 0: return "DEL"
            case 1: return "SEQ"
            case 2: return "PRG"
            case 3: return "USR"
            case 4: return "REL"
            default: return "???"
            }
        }

        public var isClosed: Bool { fileType & 0x80 != 0 }
    }

    // MARK: - Channel state

    struct Channel {
        var data: [UInt8] = []
        var position: Int = 0
        var isOpen: Bool = false

        var hasData: Bool { position < data.count }

        mutating func readByte() -> UInt8 {
            guard position < data.count else { return 0 }
            let byte = data[position]
            position += 1
            return byte
        }
    }

    // MARK: - State

    /// Raw D64 image data
    var imageData: [UInt8]?

    /// 16 channels (logical file numbers)
    var channels = [Channel](repeating: Channel(), count: 16)

    /// Parsed directory entries
    public private(set) var directory: [DirectoryEntry] = []

    /// Disk name (from BAM)
    public private(set) var diskName: String = ""

    /// Disk ID
    public private(set) var diskID: String = ""

    // MARK: - Init

    public init() {}

    // MARK: - Mount / Unmount

    /// Mount a D64 image.
    public func mount(_ data: Data) -> Bool {
        // Validate size: 174848 (no errors) or 175531 (with errors)
        guard data.count == 174848 || data.count == 175531 || data.count == 196608 else {
            return false
        }
        imageData = [UInt8](data)
        parseDirectory()
        return true
    }

    /// Mount a G64 image by decoding GCR data to D64 sectors.
    public func mountG64(_ data: Data) -> Bool {
        guard let decoded = G64Parser.decode(data) else { return false }
        imageData = decoded
        parseDirectory()
        return true
    }

    /// Mount a disk image from file, auto-detecting D64 or G64 format.
    public func mountFromFile(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        let ext = url.pathExtension.lowercased()
        if ext == "g64" {
            return mountG64(data)
        }
        // Try D64 first, fall back to G64 if D64 size doesn't match
        if mount(data) {
            return true
        }
        return mountG64(data)
    }

    public func unmount() {
        imageData = nil
        directory = []
        diskName = ""
        diskID = ""
        for i in 0..<16 { channels[i] = Channel() }
    }

    public var isMounted: Bool { imageData != nil }

    // MARK: - Sector access

    /// Read a 256-byte sector from the image.
    func readSector(track: Int, sector: Int) -> [UInt8]? {
        guard let image = imageData,
              track >= 1 && track <= 35,
              sector >= 0 && sector < DiskDrive.sectorsPerTrack[track] else { return nil }

        let offset = DiskDrive.trackOffset[track] + sector * 256
        guard offset + 256 <= image.count else { return nil }
        return Array(image[offset..<offset + 256])
    }

    // MARK: - Directory parsing

    func parseDirectory() {
        directory = []

        // Read disk name from BAM (track 18, sector 0)
        guard let bam = readSector(track: 18, sector: 0) else { return }
        diskName = petsciiToString(Array(bam[0x90...0x9F]))
        diskID = petsciiToString(Array(bam[0xA2...0xA3]))

        // Directory starts at track 18, sector 1
        var track = 18
        var sector = 1

        while track != 0 {
            guard let data = readSector(track: track, sector: sector) else { break }

            // 8 directory entries per sector (32 bytes each)
            for i in 0..<8 {
                let offset = i * 32
                let fileType = data[offset + 2]

                // Skip empty entries
                if fileType == 0 { continue }

                let firstTrack = data[offset + 3]
                let firstSector = data[offset + 4]
                let filenameRaw = Array(data[offset + 5...offset + 20])
                let filename = petsciiToString(filenameRaw)
                let fileSize = UInt16(data[offset + 30]) | (UInt16(data[offset + 31]) << 8)

                let entry = DirectoryEntry(
                    filename: filename,
                    filenameRaw: filenameRaw,
                    fileType: fileType,
                    firstTrack: firstTrack,
                    firstSector: firstSector,
                    fileSize: fileSize
                )
                directory.append(entry)
            }

            // Follow chain
            track = Int(data[0])
            sector = Int(data[1])
        }
    }

    // MARK: - File operations

    /// Find a file by name. Supports wildcards (* and ?).
    public func findFile(_ name: String) -> DirectoryEntry? {
        if name == "*" || name.isEmpty {
            // First PRG file
            return directory.first { $0.fileType & 0x07 == 2 }
        }

        let searchName = name.uppercased()
        return directory.first { entry in
            matchWildcard(searchName, entry.filename.uppercased())
        }
    }

    /// Read the raw data of a file (following the track/sector chain).
    public func readFileData(_ entry: DirectoryEntry) -> [UInt8] {
        var data: [UInt8] = []
        var track = Int(entry.firstTrack)
        var sector = Int(entry.firstSector)

        while track != 0 {
            guard let sectorData = readSector(track: track, sector: sector) else { break }

            let nextTrack = Int(sectorData[0])
            let nextSector = Int(sectorData[1])

            if nextTrack == 0 {
                // Last sector: nextSector = number of bytes used + 1
                let bytesUsed = nextSector
                if bytesUsed >= 2 {
                    data.append(contentsOf: sectorData[2..<bytesUsed])
                }
            } else {
                data.append(contentsOf: sectorData[2..<256])
            }

            track = nextTrack
            sector = nextSector
        }

        return data
    }

    /// Generate a directory listing as a BASIC program (like LOAD"$",8).
    public func generateDirectoryListing() -> [UInt8] {
        var prg: [UInt8] = []

        // Load address: $0801 (BASIC start — matches where LOAD"$",8 puts it)
        prg.append(0x01)
        prg.append(0x08)

        var lineAddr: UInt16 = 0x0801

        // Header line: 0 "DISK NAME" ID
        lineAddr += addDirectoryLine(&prg, lineNumber: 0, text: headerLine())

        // File entries
        for entry in directory {
            let typeName = entry.typeName
            let closed = entry.isClosed ? " " : "*"
            let name = "\"\(entry.filename)\""
            let paddedName = name.padding(toLength: 18, withPad: " ", startingAt: 0)
            let line = "\(paddedName) \(closed)\(typeName)"
            lineAddr += addDirectoryLine(&prg, lineNumber: UInt16(entry.fileSize), text: line)
        }

        // Footer: BLOCKS FREE.
        lineAddr += addDirectoryLine(&prg, lineNumber: freeBlocks(), text: "BLOCKS FREE.")

        // End of BASIC program
        prg.append(0x00)
        prg.append(0x00)

        return prg
    }

    func headerLine() -> String {
        let name = "\"" + diskName.padding(toLength: 16, withPad: " ", startingAt: 0) + "\""
        return "\u{12}" + name + " " + diskID  // \u{12} = reverse on
    }

    func addDirectoryLine(_ prg: inout [UInt8], lineNumber: UInt16, text: String) -> UInt16 {
        let startPos = prg.count

        // Placeholder for next line pointer (filled later)
        prg.append(0x00)
        prg.append(0x00)

        // Line number
        prg.append(UInt8(lineNumber & 0xFF))
        prg.append(UInt8(lineNumber >> 8))

        // Spaces for alignment (line numbers < 10 get more padding)
        if lineNumber < 10 { prg.append(0x20); prg.append(0x20); prg.append(0x20) }
        else if lineNumber < 100 { prg.append(0x20); prg.append(0x20) }
        else if lineNumber < 1000 { prg.append(0x20) }

        // Text as PETSCII
        for char in text {
            prg.append(charToPetscii(char))
        }

        // End of line
        prg.append(0x00)

        let lineLen = UInt16(prg.count - startPos)

        // Fill in next line pointer
        let nextAddr = UInt16(0x0801) + UInt16(prg.count - 2)  // -2 for load address
        prg[startPos] = UInt8(nextAddr & 0xFF)
        prg[startPos + 1] = UInt8(nextAddr >> 8)

        return lineLen
    }

    func freeBlocks() -> UInt16 {
        guard let bam = readSector(track: 18, sector: 0) else { return 0 }
        var free: UInt16 = 0
        for track in 1...35 {
            if track == 18 { continue }  // Don't count directory track
            let offset = track * 4
            if offset < bam.count {
                free += UInt16(bam[offset])
            }
        }
        return free
    }

    // MARK: - Channel operations (for Kernal trap LOAD)

    /// Open a file on a channel for reading.
    public func openFile(channel: Int, filename: String) -> Bool {
        guard channel >= 0 && channel < 16 else { return false }

        if filename == "$" {
            // Directory listing
            let listing = generateDirectoryListing()
            channels[channel] = Channel(data: listing, position: 0, isOpen: true)
            return true
        }

        guard let entry = findFile(filename) else { return false }

        let data = readFileData(entry)

        // For PRG files, prepend the load address (first 2 bytes of file data)
        // The file data from the disk already includes the load address
        // Actually, the raw file data on disk IS the PRG data (with load address)
        // So we just use it as-is
        channels[channel] = Channel(data: data, position: 0, isOpen: true)
        return true
    }

    /// Read a byte from a channel.
    public func readByte(channel: Int) -> (byte: UInt8, eof: Bool) {
        guard channel >= 0 && channel < 16 && channels[channel].isOpen else {
            return (0, true)
        }
        let byte = channels[channel].readByte()
        let eof = !channels[channel].hasData
        return (byte, eof)
    }

    /// Close a channel.
    public func closeChannel(_ channel: Int) {
        guard channel >= 0 && channel < 16 else { return }
        channels[channel] = Channel()
    }

    // MARK: - Wildcard matching

    func matchWildcard(_ pattern: String, _ text: String) -> Bool {
        let p = Array(pattern)
        let t = Array(text)
        return matchWildcardHelper(p, 0, t, 0)
    }

    func matchWildcardHelper(_ p: [Character], _ pi: Int, _ t: [Character], _ ti: Int) -> Bool {
        if pi == p.count { return ti == t.count }
        if p[pi] == "*" { return true }  // C64 * matches everything after
        if ti == t.count { return false }
        if p[pi] == "?" || p[pi] == t[ti] {
            return matchWildcardHelper(p, pi + 1, t, ti + 1)
        }
        return false
    }

    // MARK: - PETSCII conversion

    func petsciiToString(_ bytes: [UInt8]) -> String {
        var result = ""
        for byte in bytes {
            if byte == 0xA0 { break }  // Padding
            if byte == 0x00 { break }
            result.append(petsciiToChar(byte))
        }
        return result
    }

    func petsciiToChar(_ byte: UInt8) -> Character {
        switch byte {
        case 0x20...0x40: return Character(UnicodeScalar(byte))       // Space, digits, punctuation
        case 0x41...0x5A: return Character(UnicodeScalar(byte + 32))  // Uppercase → lowercase
        case 0x61...0x7A: return Character(UnicodeScalar(byte - 32))  // Lowercase → uppercase
        case 0xC1...0xDA: return Character(UnicodeScalar(byte - 128)) // Shifted uppercase
        default: return "?"
        }
    }

    func charToPetscii(_ char: Character) -> UInt8 {
        guard let ascii = char.asciiValue else { return 0x3F }
        switch ascii {
        case 0x20...0x40: return ascii
        case 0x41...0x5A: return ascii  // Uppercase stays
        case 0x61...0x7A: return ascii - 32  // lowercase → uppercase PETSCII
        case 0x12: return 0x12  // Reverse on
        case 0x22: return 0x22  // Quote
        default: return 0x3F  // ?
        }
    }
}
