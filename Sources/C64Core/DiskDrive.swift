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

    /// D64 byte sizes accepted by this emulator.
    ///
    /// The 1541 emulation currently reads standard tracks 1-35, but many real
    /// collections contain extended 40/41/42-track D64 images. Accepting them
    /// lets the standard directory/BAM area mount while later work can preserve
    /// the extra tracks in the low-level media layer.
    static let supportedD64Sizes: Set<Int> = [
        174848, 175531,  // 35 tracks: no error bytes / with error bytes
        196608, 197376,  // 40 tracks
        200704, 201488,  // 41 tracks
        205312, 206114,  // 42 tracks
    ]

    private static let standardBAMTrackLimit = 35

    struct D64Geometry {
        let dataSize: Int
        let errorInfoOffset: Int?
        let trackCount: Int
        let sectorsPerTrack: [Int]
        let trackOffsets: [Int]
    }

    static func d64Geometry(forByteCount byteCount: Int) -> D64Geometry? {
        let trackCount: Int
        let dataSize: Int
        switch byteCount {
        case 174848, 175531:
            trackCount = 35
            dataSize = 174848
        case 196608, 197376:
            trackCount = 40
            dataSize = 196608
        case 200704, 201488:
            trackCount = 41
            dataSize = 200704
        case 205312, 206114:
            trackCount = 42
            dataSize = 205312
        default:
            return nil
        }

        var sectors = sectorsPerTrack
        if trackCount >= 40 {
            sectors.append(contentsOf: [Int](repeating: 17, count: 5))
        }
        if trackCount == 41 {
            sectors.append(16)
        } else if trackCount == 42 {
            sectors.append(contentsOf: [17, 17])
        }

        var offsets = [0]
        var offset = 0
        for track in 1...trackCount {
            offsets.append(offset)
            offset += sectors[track] * 256
        }

        return D64Geometry(
            dataSize: dataSize,
            errorInfoOffset: byteCount > dataSize ? dataSize : nil,
            trackCount: trackCount,
            sectorsPerTrack: sectors,
            trackOffsets: offsets
        )
    }

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
        var writeData: [UInt8] = []
        var position: Int = 0
        var writePosition: Int = 0
        var isOpen: Bool = false
        var clearsCommandStatusOnEOF: Bool = false
        var outputFilename: String?
        var outputFileType: UInt8 = 0x82
        var outputTypeFilter: UInt8?
        var outputReplacesExisting: Bool = false

        var hasData: Bool { position < data.count }

        mutating func readByte() -> UInt8 {
            guard position < data.count else { return 0 }
            let byte = data[position]
            position += 1
            return byte
        }

        mutating func writeByte(_ byte: UInt8) {
            let maximumBufferedBytes = outputFilename == nil ? 256 : 1_048_576
            guard writePosition < maximumBufferedBytes else { return }
            if writeData.count < writePosition {
                writeData.append(contentsOf: [UInt8](repeating: 0, count: writePosition - writeData.count))
            }
            if writePosition < writeData.count {
                writeData[writePosition] = byte
            } else {
                writeData.append(byte)
            }
            writePosition += 1
        }

        mutating func setBufferPointer(_ pointer: Int) {
            position = pointer
            writePosition = pointer
        }
    }

    // MARK: - State

    /// Raw D64 image data
    var imageData: [UInt8]?

    /// 16 channels (logical file numbers)
    var channels = [Channel](repeating: Channel(), count: 16)
    private var commandStatus = "00, OK,00,00\r"
    private var commandResponseData: [UInt8]?
    private var dosMemory = [UInt8](repeating: 0, count: 0x10000)
    public var currentCommandStatus: String { commandStatus }

    /// Parsed directory entries
    public private(set) var directory: [DirectoryEntry] = []

    /// Disk name (from BAM)
    public private(set) var diskName: String = ""

    /// Disk ID
    public private(set) var diskID: String = ""

    var mountedGeometry: D64Geometry?
    public private(set) var mountedFormat: DiskImage.Format?
    public private(set) var hasUnsavedChanges = false
    public private(set) var isWriteProtected = true
    public var onD64ImageChanged: ((Data) -> Void)?

    public var hasSectorErrorInfo: Bool {
        mountedGeometry?.errorInfoOffset != nil
    }

    public var exportedD64Image: Data? {
        guard mountedFormat == .d64, let imageData else { return nil }
        return Data(imageData)
    }

    @discardableResult
    public func replaceMountedD64ImageAfterLowLevelWrite(_ data: Data) -> Bool {
        guard mountedFormat == .d64,
              let geometry = Self.d64Geometry(forByteCount: data.count),
              geometry.dataSize == mountedGeometry?.dataSize else {
            return false
        }

        imageData = [UInt8](data)
        mountedGeometry = geometry
        parseDirectory()
        markD64Modified()
        return true
    }

    public func markChangesSaved() {
        guard mountedFormat == .d64 else { return }
        hasUnsavedChanges = false
    }

    public func setWriteProtected(_ protected: Bool) {
        isWriteProtected = protected
    }

    private func rejectWriteProtected() -> Bool {
        guard isWriteProtected else { return false }
        commandStatus = "26, WRITE PROTECT ON,00,00\r"
        return true
    }

    private func markD64Modified() {
        hasUnsavedChanges = true
        if let exportedD64Image {
            onD64ImageChanged?(exportedD64Image)
        }
    }

    // MARK: - Init

    public init() {}

    // MARK: - Mount / Unmount

    /// Mount a D64 image.
    public func mount(_ data: Data) -> Bool {
        guard let geometry = Self.d64Geometry(forByteCount: data.count) else {
            return false
        }
        imageData = [UInt8](data)
        mountedGeometry = geometry
        mountedFormat = .d64
        hasUnsavedChanges = false
        isWriteProtected = false
        parseDirectory()
        return true
    }

    /// Mount a G64 image by decoding GCR data to D64 sectors.
    public func mountG64(_ data: Data) -> Bool {
        guard let decoded = G64Parser.decode(data) else { return false }
        imageData = decoded
        mountedGeometry = Self.d64Geometry(forByteCount: decoded.count)
        mountedFormat = .g64
        hasUnsavedChanges = false
        isWriteProtected = true
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
        mountedGeometry = nil
        mountedFormat = nil
        hasUnsavedChanges = false
        isWriteProtected = true
        directory = []
        diskName = ""
        diskID = ""
        commandStatus = "00, OK,00,00\r"
        for i in 0..<16 { channels[i] = Channel() }
    }

    public var isMounted: Bool { imageData != nil }

    // MARK: - Sector access

    /// Read a 256-byte sector from the image.
    func readSector(track: Int, sector: Int) -> [UInt8]? {
        guard let image = imageData,
              let geometry = mountedGeometry,
              track >= 1 && track <= geometry.trackCount,
              sector >= 0 && sector < geometry.sectorsPerTrack[track] else { return nil }

        let offset = geometry.trackOffsets[track] + sector * 256
        guard offset + 256 <= geometry.dataSize, offset + 256 <= image.count else { return nil }
        return Array(image[offset..<offset + 256])
    }

    public func readSectorErrorCode(track: Int, sector: Int) -> UInt8? {
        guard let image = imageData,
              let geometry = mountedGeometry,
              let errorInfoOffset = geometry.errorInfoOffset,
              let ordinal = sectorOrdinal(track: track, sector: sector, geometry: geometry) else {
            return nil
        }

        let offset = errorInfoOffset + ordinal
        guard offset < image.count else { return nil }
        return image[offset]
    }

    private func sectorOrdinal(track: Int, sector: Int, geometry: D64Geometry) -> Int? {
        guard track >= 1 && track <= geometry.trackCount,
              sector >= 0 && sector < geometry.sectorsPerTrack[track] else {
            return nil
        }

        var ordinal = sector
        if track > 1 {
            for previousTrack in 1..<track {
                ordinal += geometry.sectorsPerTrack[previousTrack]
            }
        }
        return ordinal
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
        var visitedSectors = Set<Int>()

        while track != 0 {
            let key = sectorChainKey(track: track, sector: sector)
            guard !visitedSectors.contains(key) else { break }
            visitedSectors.insert(key)

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
        findFile(matching: parseDiskFilename(name))
    }

    private func findFile(matching request: DiskFilenameRequest) -> DirectoryEntry? {
        let searchName = request.name

        if searchName == "*" || searchName.isEmpty {
            // First matching typed file. Plain * defaults to PRG.
            let wantedType = request.typeFilter ?? 0x82
            return directory.first { ($0.fileType & 0x07) == (wantedType & 0x07) }
        }

        let uppercasedSearchName = searchName.uppercased()
        return directory.first { entry in
            fileTypeMatches(entry.fileType, filter: request.typeFilter)
                && matchWildcard(uppercasedSearchName, entry.filename.uppercased())
        }
    }

    private func fileTypeMatches(_ fileType: UInt8, filter: UInt8?) -> Bool {
        filter.map { (fileType & 0x07) == ($0 & 0x07) } ?? true
    }

    public func isDirectoryListingRequest(_ name: String) -> Bool {
        parseDiskFilename(name).name.hasPrefix("$")
    }

    public func loadDirectoryListing(matching filename: String = "$") -> [UInt8]? {
        guard validateDirectorySectorsReadable() else { return nil }
        commandStatus = "00, OK,00,00\r"
        return generateDirectoryListing(matching: directoryListingRequest(for: filename))
    }

    /// Read the raw data of a file (following the track/sector chain).
    public func readFileData(_ entry: DirectoryEntry) -> [UInt8] {
        var data: [UInt8] = []
        var track = Int(entry.firstTrack)
        var sector = Int(entry.firstSector)
        var visitedSectors = Set<Int>()

        while track != 0 {
            let key = sectorChainKey(track: track, sector: sector)
            guard !visitedSectors.contains(key) else { break }
            visitedSectors.insert(key)

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

    /// Read file data for LOAD/channel reads, respecting D64 sector error info.
    ///
    /// `readFileData` intentionally remains a raw byte accessor for tools and
    /// tests. This path models 1541 read failures so fast-load compatibility
    /// traps do not silently succeed on damaged D64 sectors.
    public func loadFileData(_ entry: DirectoryEntry) -> [UInt8]? {
        var data: [UInt8] = []
        var track = Int(entry.firstTrack)
        var sector = Int(entry.firstSector)
        var visitedSectors = Set<Int>()

        while track != 0 {
            let key = sectorChainKey(track: track, sector: sector)
            guard !visitedSectors.contains(key) else { break }
            visitedSectors.insert(key)

            if let code = readSectorErrorCode(track: track, sector: sector),
               isReadSideSectorError(code) {
                commandStatus = String(format: "%02d, READ ERROR,%02d,%02d\r", Int(code), track, sector)
                return nil
            }

            guard let sectorData = readSector(track: track, sector: sector) else {
                commandStatus = String(format: "66, ILLEGAL TRACK OR SECTOR,%02d,%02d\r", track, sector)
                return nil
            }

            let nextTrack = Int(sectorData[0])
            let nextSector = Int(sectorData[1])

            if nextTrack == 0 {
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

        commandStatus = "00, OK,00,00\r"
        return data
    }

    public func loadFileData(named filename: String) -> [UInt8]? {
        guard isMounted else {
            commandStatus = "74, DRIVE NOT READY,00,00\r"
            return nil
        }
        guard let entry = findFile(filename) else {
            commandStatus = "62, FILE NOT FOUND,00,00\r"
            return nil
        }
        return loadFileData(entry)
    }

    private func isReadSideSectorError(_ code: UInt8) -> Bool {
        switch code {
        case 20...24, 27...29:
            return true
        default:
            return false
        }
    }

    /// Save a PRG file into the mounted D64 image.
    ///
    /// This is the high-level convenience write path used by Kernal traps. It
    /// updates the D64 image in memory, including BAM free maps, PRG sector
    /// chains, and the first free directory slot. True-drive GCR write-back is
    /// still handled separately by the low-level 1541 roadmap.
    @discardableResult
    public func savePRG(filename: String, data: [UInt8]) -> Bool {
        let request = parseDiskFilename(filename)
        return saveFile(request: request, data: data, fileType: 0x82)
    }

    @discardableResult
    private func saveFile(request: DiskFilenameRequest, data: [UInt8], fileType: UInt8) -> Bool {
        guard isMounted,
              mountedGeometry != nil,
              mountedFormat == .d64,
              !isWriteProtected,
              !request.name.isEmpty,
              request.name != "$" else {
            if isMounted, mountedFormat == .d64, isWriteProtected {
                commandStatus = "26, WRITE PROTECT ON,00,00\r"
            }
            return false
        }
        guard validateDirectorySectorsReadable() else { return false }

        let existing: (slot: DirectorySlot, entry: DirectoryEntry)?
        if request.replaceExisting, request.typeFilter != nil {
            existing = findDirectorySlot(matching: request)
        } else {
            existing = findDirectorySlot(named: request.name)
        }
        guard request.replaceExisting || existing == nil else { return false }

        let releasedSectors: Set<Int>
        if let existing {
            releasedSectors = fileChainKeys(firstTrack: Int(existing.entry.firstTrack), firstSector: Int(existing.entry.firstSector))
        } else {
            releasedSectors = []
        }

        let sectorCount = sectorCountNeeded(forPayloadSize: data.count)
        if sectorCount == 0 {
            let directorySlot: DirectorySlot
            if let existing {
                directorySlot = existing.slot
                clearDirectoryEntry(slot: directorySlot)
                for key in releasedSectors {
                    setBAMSector(track: key >> 8, sector: key & 0xFF, free: true)
                }
            } else {
                guard let freeSlot = findFreeDirectorySlot() else { return false }
                directorySlot = freeSlot
            }
            writeDirectoryEntry(slot: directorySlot, filename: request.name, fileType: fileType, firstSector: (0, 0), sectorCount: 0)
            parseDirectory()
            markD64Modified()
            return true
        }

        guard let allocated = selectFreeSectors(count: sectorCount, releasing: releasedSectors) else { return false }
        let allocatedKeys = Set(allocated.map { sectorChainKey(track: $0.track, sector: $0.sector) })

        let directorySlot: DirectorySlot
        if let existing {
            directorySlot = existing.slot
        } else {
            guard let freeSlot = findFreeDirectorySlot() else { return false }
            directorySlot = freeSlot
        }

        if existing != nil {
            clearDirectoryEntry(slot: directorySlot)
            for key in releasedSectors.subtracting(allocatedKeys) {
                setBAMSector(track: key >> 8, sector: key & 0xFF, free: true)
            }
        }

        for sector in allocated {
            setBAMSector(track: sector.track, sector: sector.sector, free: false)
        }

        writePRGChain(data: data, sectors: allocated)
        writeDirectoryEntry(slot: directorySlot, filename: request.name, fileType: fileType, firstSector: allocated[0], sectorCount: sectorCount)
        parseDirectory()
        markD64Modified()
        return true
    }

    @discardableResult
    public func executeCommand(_ command: String) -> Bool {
        commandResponseData = nil
        let commandBytes = Array(command.utf8)
        if let result = executeMemoryCommand(commandBytes) {
            return result
        }
        if let changedAddress = parseDeviceAddressChangeCommand(command) {
            commandStatus = changedAddress ? "00, OK,00,00\r" : "30, SYNTAX ERROR,00,00\r"
            return changedAddress
        }

        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            commandStatus = "00, OK,00,00\r"
            return true
        }

        let upper = trimmed.uppercased()
        if upper.hasPrefix("S:") || upper.hasPrefix("S0:") || upper.hasPrefix("SCRATCH:") {
            let name: String
            if upper.hasPrefix("SCRATCH:") {
                name = String(trimmed.dropFirst("SCRATCH:".count))
            } else if upper.hasPrefix("S0:") {
                name = String(trimmed.dropFirst(3))
            } else {
                name = String(trimmed.dropFirst(2))
            }

            guard let scratched = scratchFiles(matching: name) else {
                return false
            }

            if scratched > 0 {
                commandStatus = String(format: "%02d, FILES SCRATCHED,00,00\r", min(scratched, 99))
            } else {
                commandStatus = "62, FILE NOT FOUND,00,00\r"
            }
            return true
        }

        if upper.hasPrefix("R:") || upper.hasPrefix("R0:") || upper.hasPrefix("RENAME:") {
            let expression: String
            if upper.hasPrefix("RENAME:") {
                expression = String(trimmed.dropFirst("RENAME:".count))
            } else if upper.hasPrefix("R0:") {
                expression = String(trimmed.dropFirst(3))
            } else {
                expression = String(trimmed.dropFirst(2))
            }

            guard let result = renameFile(expression: expression) else {
                return false
            }

            switch result {
            case .renamed:
                commandStatus = "00, OK,00,00\r"
            case .missingSource:
                commandStatus = "62, FILE NOT FOUND,00,00\r"
            case .destinationExists:
                commandStatus = "63, FILE EXISTS,00,00\r"
            case .writeProtected:
                commandStatus = "26, WRITE PROTECT ON,00,00\r"
            case .readError:
                break
            case .syntaxError:
                commandStatus = "30, SYNTAX ERROR,00,00\r"
            }
            return result == .renamed
        }

        if upper.hasPrefix("C:") || upper.hasPrefix("C0:") || upper.hasPrefix("COPY:") {
            let expression: String
            if upper.hasPrefix("COPY:") {
                expression = String(trimmed.dropFirst("COPY:".count))
            } else if upper.hasPrefix("C0:") {
                expression = String(trimmed.dropFirst(3))
            } else {
                expression = String(trimmed.dropFirst(2))
            }

            guard let result = copyFile(expression: expression) else {
                return false
            }

            switch result {
            case .copied:
                commandStatus = "00, OK,00,00\r"
            case .missingSource:
                commandStatus = "62, FILE NOT FOUND,00,00\r"
            case .destinationExists:
                commandStatus = "63, FILE EXISTS,00,00\r"
            case .writeProtected:
                commandStatus = "26, WRITE PROTECT ON,00,00\r"
            case .readError:
                break
            case .syntaxError:
                commandStatus = "30, SYNTAX ERROR,00,00\r"
            }
            return result == .copied
        }

        if upper.hasPrefix("N:") || upper.hasPrefix("N0:") || upper.hasPrefix("NEW:") {
            let expression: String
            if upper.hasPrefix("NEW:") {
                expression = String(trimmed.dropFirst("NEW:".count))
            } else if upper.hasPrefix("N0:") {
                expression = String(trimmed.dropFirst(3))
            } else {
                expression = String(trimmed.dropFirst(2))
            }

            guard let request = parseNewDiskCommand(expression) else {
                commandStatus = "30, SYNTAX ERROR,00,00\r"
                return false
            }

            guard formatD64(diskName: request.name, diskID: request.id) else { return false }

            commandStatus = "00, OK,00,00\r"
            return true
        }

        if upper.hasPrefix("B-R") || upper.hasPrefix("BLOCK-READ") || upper.hasPrefix("U1") || upper.hasPrefix("UA") {
            guard let result = blockRead(command: trimmed) else {
                commandStatus = "30, SYNTAX ERROR,00,00\r"
                return false
            }

            switch result {
            case .read:
                commandStatus = "00, OK,00,00\r"
            case .invalidBlock(let track, let sector):
                commandStatus = String(format: "66, ILLEGAL TRACK OR SECTOR,%02d,%02d\r", track, sector)
            case .readError:
                break
            case .syntaxError:
                commandStatus = "30, SYNTAX ERROR,00,00\r"
            }
            return result == .read
        }

        if upper.hasPrefix("B-E") || upper.hasPrefix("BLOCK-EXECUTE") {
            guard let result = blockRead(command: trimmed, acceptedPrefixes: ["B-E", "BLOCK-EXECUTE"]) else {
                commandStatus = "30, SYNTAX ERROR,00,00\r"
                return false
            }

            switch result {
            case .read:
                commandStatus = "00, OK,00,00\r"
            case .invalidBlock(let track, let sector):
                commandStatus = String(format: "66, ILLEGAL TRACK OR SECTOR,%02d,%02d\r", track, sector)
            case .readError:
                break
            case .syntaxError:
                commandStatus = "30, SYNTAX ERROR,00,00\r"
            }
            return result == .read
        }

        if upper.hasPrefix("B-W") || upper.hasPrefix("BLOCK-WRITE") || upper.hasPrefix("U2") || upper.hasPrefix("UB") {
            guard let result = blockWrite(command: trimmed) else {
                commandStatus = "30, SYNTAX ERROR,00,00\r"
                return false
            }

            switch result {
            case .written:
                commandStatus = "00, OK,00,00\r"
            case .invalidBlock(let track, let sector):
                commandStatus = String(format: "66, ILLEGAL TRACK OR SECTOR,%02d,%02d\r", track, sector)
            case .driveNotReady:
                commandStatus = "74, DRIVE NOT READY,00,00\r"
            case .writeProtected:
                commandStatus = "26, WRITE PROTECT ON,00,00\r"
            case .syntaxError:
                commandStatus = "30, SYNTAX ERROR,00,00\r"
            }
            return result == .written
        }

        if upper.hasPrefix("B-P") || upper.hasPrefix("BLOCK-POINTER") {
            guard let result = blockPointer(command: trimmed) else {
                commandStatus = "30, SYNTAX ERROR,00,00\r"
                return false
            }

            switch result {
            case .set:
                commandStatus = "00, OK,00,00\r"
            case .syntaxError:
                commandStatus = "30, SYNTAX ERROR,00,00\r"
            }
            return result == .set
        }

        if upper.hasPrefix("B-A") || upper.hasPrefix("BLOCK-ALLOCATE") || upper.hasPrefix("B-F") || upper.hasPrefix("BLOCK-FREE") {
            guard let result = blockAllocation(command: trimmed) else {
                commandStatus = "30, SYNTAX ERROR,00,00\r"
                return false
            }

            switch result {
            case .changed:
                commandStatus = "00, OK,00,00\r"
            case .alreadyAllocated(let track, let sector):
                commandStatus = String(format: "65, NO BLOCK,%02d,%02d\r", track, sector)
            case .invalidBlock(let track, let sector):
                commandStatus = String(format: "66, ILLEGAL TRACK OR SECTOR,%02d,%02d\r", track, sector)
            case .driveNotReady:
                commandStatus = "74, DRIVE NOT READY,00,00\r"
            case .writeProtected:
                commandStatus = "26, WRITE PROTECT ON,00,00\r"
            case .readError:
                break
            case .syntaxError:
                commandStatus = "30, SYNTAX ERROR,00,00\r"
            }
            return result == .changed
        }

        if upper == "I" || upper == "I:" || upper == "I0" || upper == "I0:" || upper == "INITIALIZE" || upper == "INITIALIZE:" {
            guard initializeDisk() else { return false }
            commandStatus = "00, OK,00,00\r"
            return true
        }

        if isDriveResetCommand(upper) {
            guard resetDriveCommand() else { return false }
            commandStatus = "00, OK,00,00\r"
            return true
        }
        if let changedAddress = parseDeviceAddressChangeCommand(trimmed) {
            commandStatus = changedAddress ? "00, OK,00,00\r" : "30, SYNTAX ERROR,00,00\r"
            return changedAddress
        }

        if upper == "V" || upper == "V:" || upper == "V0" || upper == "V0:" || upper == "VALIDATE" || upper == "VALIDATE:" {
            guard validateD64() else {
                return false
            }

            commandStatus = "00, OK,00,00\r"
            return true
        }

        commandStatus = "30, SYNTAX ERROR,00,00\r"
        return false
    }

    private func sectorChainKey(track: Int, sector: Int) -> Int {
        (track << 8) | sector
    }

    private struct DirectorySlot {
        let track: Int
        let sector: Int
        let entryIndex: Int
    }

    private struct DiskFilenameRequest {
        let name: String
        let replaceExisting: Bool
        let fileType: UInt8
        let typeFilter: UInt8?
        let accessMode: DiskFileAccessMode
    }

    private enum DiskFileAccessMode {
        case read
        case write
        case append
    }

    private struct NewDiskCommand {
        let name: String
        let id: String
    }

    private enum RenameResult {
        case renamed
        case missingSource
        case destinationExists
        case writeProtected
        case readError
        case syntaxError
    }

    private enum CopyResult {
        case copied
        case missingSource
        case destinationExists
        case writeProtected
        case readError
        case syntaxError
    }

    private enum BlockReadResult: Equatable {
        case read
        case invalidBlock(track: Int, sector: Int)
        case readError
        case syntaxError
    }

    private enum BlockWriteResult: Equatable {
        case written
        case invalidBlock(track: Int, sector: Int)
        case driveNotReady
        case writeProtected
        case syntaxError
    }

    private enum BlockPointerResult: Equatable {
        case set
        case syntaxError
    }

    private enum BlockAllocationResult: Equatable {
        case changed
        case alreadyAllocated(track: Int, sector: Int)
        case invalidBlock(track: Int, sector: Int)
        case driveNotReady
        case writeProtected
        case readError
        case syntaxError
    }

    private struct BlockCommandRequest {
        let channel: Int
        let driveNumber: Int
        let track: Int
        let sector: Int
    }

    private enum BinaryBlockCommandParseResult {
        case request(BlockCommandRequest)
        case notBinary
        case syntaxError
    }

    private func parseNewDiskCommand(_ expression: String) -> NewDiskCommand? {
        let parts = expression.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(parts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "$" else { return nil }

        let id: String
        if parts.count > 1 {
            id = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            id = diskID.isEmpty ? "00" : diskID
        }
        guard !id.isEmpty else { return nil }

        return NewDiskCommand(name: String(name.prefix(16)), id: String(id.prefix(2)))
    }

    private func blockRead(
        command: String,
        acceptedPrefixes: [String] = ["B-R", "BLOCK-READ", "U1", "UA"]
    ) -> BlockReadResult? {
        guard isMounted else { return .invalidBlock(track: 0, sector: 0) }
        let upper = command.uppercased()
        guard let prefix = acceptedPrefixes.first(where: { upper.hasPrefix($0) }) else {
            return nil
        }

        switch parseBinaryUserBlockCommand(command, userPrefixes: ["U1", "UA"]) {
        case .request(let request):
            return blockRead(request: request)
        case .syntaxError:
            return .syntaxError
        case .notBinary:
            break
        }

        var expression = String(command.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        if expression.hasPrefix(":") || expression.hasPrefix(",") {
            expression.removeFirst()
        }

        guard let request = parseTextBlockCommandRequest(expression) else {
            return .syntaxError
        }
        return blockRead(request: request)
    }

    private func blockRead(request: BlockCommandRequest) -> BlockReadResult {
        guard (0...14).contains(request.channel), request.driveNumber == 0 else {
            return .syntaxError
        }

        if let code = readSectorErrorCode(track: request.track, sector: request.sector),
           isReadSideSectorError(code) {
            commandStatus = String(format: "%02d, READ ERROR,%02d,%02d\r", Int(code), request.track, request.sector)
            return .readError
        }

        guard let sectorData = readSector(track: request.track, sector: request.sector) else {
            return .invalidBlock(track: request.track, sector: request.sector)
        }
        channels[request.channel] = Channel(data: sectorData, position: 0, isOpen: true)
        return .read
    }

    private func blockWrite(command: String) -> BlockWriteResult? {
        guard isMounted, mountedFormat == .d64 else { return .driveNotReady }
        guard !isWriteProtected else { return .writeProtected }
        let upper = command.uppercased()
        let prefix: String
        if upper.hasPrefix("BLOCK-WRITE") {
            prefix = "BLOCK-WRITE"
        } else if upper.hasPrefix("B-W") {
            prefix = "B-W"
        } else if upper.hasPrefix("U2") {
            prefix = "U2"
        } else if upper.hasPrefix("UB") {
            prefix = "UB"
        } else {
            return nil
        }

        switch parseBinaryUserBlockCommand(command, userPrefixes: ["U2", "UB"]) {
        case .request(let request):
            return blockWrite(request: request)
        case .syntaxError:
            return .syntaxError
        case .notBinary:
            break
        }

        var expression = String(command.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        if expression.hasPrefix(":") || expression.hasPrefix(",") {
            expression.removeFirst()
        }

        guard let request = parseTextBlockCommandRequest(expression) else {
            return .syntaxError
        }
        return blockWrite(request: request)
    }

    private func blockWrite(request: BlockCommandRequest) -> BlockWriteResult {
        guard (0...14).contains(request.channel), request.driveNumber == 0 else {
            return .syntaxError
        }

        guard let geometry = mountedGeometry,
              request.track >= 1 && request.track <= geometry.trackCount,
              request.sector >= 0 && request.sector < geometry.sectorsPerTrack[request.track] else {
            return .invalidBlock(track: request.track, sector: request.sector)
        }

        var sectorData = [UInt8](repeating: 0, count: 256)
        let buffered = channels[request.channel].writeData
        if !buffered.isEmpty {
            sectorData.replaceSubrange(0..<min(buffered.count, 256), with: buffered.prefix(256))
        }
        writeSector(track: request.track, sector: request.sector, data: sectorData)
        refreshDirectoryMetadataAfterSectorWrite(track: request.track)
        markD64Modified()
        return .written
    }

    private func refreshDirectoryMetadataAfterSectorWrite(track: Int) {
        guard track == 18 else { return }
        parseDirectory()
    }

    private func parseTextBlockCommandRequest(_ expression: String) -> BlockCommandRequest? {
        let parts = expression
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" })
            .map(String.init)
        guard parts.count == 4,
              let channel = Int(parts[0]),
              let driveNumber = Int(parts[1]),
              let track = Int(parts[2]),
              let sector = Int(parts[3]) else {
            return nil
        }
        return BlockCommandRequest(channel: channel, driveNumber: driveNumber, track: track, sector: sector)
    }

    private func parseBinaryUserBlockCommand(_ command: String, userPrefixes: [String]) -> BinaryBlockCommandParseResult {
        let commandBytes = Array(command.utf8)
        guard let prefix = userPrefixes.first(where: { asciiHasPrefix(commandBytes, $0) }) else {
            return .notBinary
        }

        var payload = Array(commandBytes.dropFirst(prefix.utf8.count))
        while payload.first == UInt8(ascii: ":") ||
              payload.first == UInt8(ascii: ",") ||
              payload.first == UInt8(ascii: " ") ||
              payload.first == 0x09 {
            payload.removeFirst()
        }
        while payload.last == 0x0D || payload.last == 0x0A {
            payload.removeLast()
        }

        guard payload.contains(where: { $0 < 0x20 }) else {
            return .notBinary
        }
        guard payload.count == 4 else {
            return .syntaxError
        }
        return .request(BlockCommandRequest(
            channel: Int(payload[0]),
            driveNumber: Int(payload[1]),
            track: Int(payload[2]),
            sector: Int(payload[3])
        ))
    }

    private func asciiHasPrefix(_ bytes: [UInt8], _ prefix: String) -> Bool {
        let prefixBytes = Array(prefix.utf8)
        guard bytes.count >= prefixBytes.count else { return false }
        for index in 0..<prefixBytes.count {
            let byte = bytes[index]
            let normalized = byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z") ? byte - 0x20 : byte
            guard normalized == prefixBytes[index] else { return false }
        }
        return true
    }

    private func blockPointer(command: String) -> BlockPointerResult? {
        let upper = command.uppercased()
        let prefix: String
        if upper.hasPrefix("BLOCK-POINTER") {
            prefix = "BLOCK-POINTER"
        } else if upper.hasPrefix("B-P") {
            prefix = "B-P"
        } else {
            return nil
        }

        var expression = String(command.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        if expression.hasPrefix(":") || expression.hasPrefix(",") {
            expression.removeFirst()
        }

        let parts = expression
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" })
            .map(String.init)
        guard parts.count == 2,
              let channel = Int(parts[0]),
              let pointer = Int(parts[1]),
              (0...14).contains(channel),
              (0...255).contains(pointer) else {
            return .syntaxError
        }

        channels[channel].setBufferPointer(pointer)
        return .set
    }

    private func blockAllocation(command: String) -> BlockAllocationResult? {
        guard isMounted, mountedFormat == .d64 else { return .driveNotReady }
        guard !isWriteProtected else { return .writeProtected }
        let upper = command.uppercased()
        let allocate: Bool
        let prefix: String
        if upper.hasPrefix("BLOCK-ALLOCATE") {
            allocate = true
            prefix = "BLOCK-ALLOCATE"
        } else if upper.hasPrefix("B-A") {
            allocate = true
            prefix = "B-A"
        } else if upper.hasPrefix("BLOCK-FREE") {
            allocate = false
            prefix = "BLOCK-FREE"
        } else if upper.hasPrefix("B-F") {
            allocate = false
            prefix = "B-F"
        } else {
            return nil
        }

        var expression = String(command.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        if expression.hasPrefix(":") || expression.hasPrefix(",") {
            expression.removeFirst()
        }

        let parts = expression
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" })
            .map(String.init)
        guard parts.count == 3,
              let driveNumber = Int(parts[0]),
              let track = Int(parts[1]),
              let sector = Int(parts[2]),
              driveNumber == 0 else {
            return .syntaxError
        }

        guard let geometry = mountedGeometry,
              track >= 1 && track <= min(geometry.trackCount, Self.standardBAMTrackLimit),
              sector >= 0 && sector < geometry.sectorsPerTrack[track] else {
            return .invalidBlock(track: track, sector: sector)
        }
        guard validateDirectorySectorsReadable() else { return .readError }

        if allocate && !isBAMSectorFree(track: track, sector: sector) {
            let nextFree = nextFreeBlock(afterTrack: track, sector: sector) ?? (track: 0, sector: 0)
            return .alreadyAllocated(track: nextFree.track, sector: nextFree.sector)
        }

        setBAMSector(track: track, sector: sector, free: !allocate)
        markD64Modified()
        return .changed
    }

    private func nextFreeBlock(afterTrack track: Int, sector: Int) -> (track: Int, sector: Int)? {
        guard let geometry = mountedGeometry else { return nil }

        func firstFree(on track: Int, in sectors: Range<Int>) -> (track: Int, sector: Int)? {
            guard track >= 1 && track <= geometry.trackCount else { return nil }
            for candidateSector in sectors where isBAMSectorFree(track: track, sector: candidateSector) {
                return (track, candidateSector)
            }
            return nil
        }

        let sectorsOnRequestedTrack = geometry.sectorsPerTrack[track]
        if sector + 1 < sectorsOnRequestedTrack,
           let next = firstFree(on: track, in: (sector + 1)..<sectorsOnRequestedTrack) {
            return next
        }
        if track < geometry.trackCount {
            for candidateTrack in (track + 1)...geometry.trackCount {
                if let next = firstFree(on: candidateTrack, in: 0..<geometry.sectorsPerTrack[candidateTrack]) {
                    return next
                }
            }
        }
        if track > 1 {
            for candidateTrack in 1..<track {
                if let next = firstFree(on: candidateTrack, in: 0..<geometry.sectorsPerTrack[candidateTrack]) {
                    return next
                }
            }
        }
        if sector > 0 {
            return firstFree(on: track, in: 0..<sector)
        }
        return nil
    }

    @discardableResult
    private func initializeDisk() -> Bool {
        guard isMounted else {
            commandStatus = "74, DRIVE NOT READY,00,00\r"
            return false
        }
        guard validateDirectorySectorsReadable() else { return false }
        parseDirectory()
        return true
    }

    @discardableResult
    private func resetDriveCommand() -> Bool {
        guard isMounted else {
            commandStatus = "74, DRIVE NOT READY,00,00\r"
            return false
        }
        guard validateDirectorySectorsReadable() else { return false }

        for index in 0..<channels.count {
            channels[index] = Channel()
        }
        commandResponseData = nil
        dosMemory = [UInt8](repeating: 0, count: 0x10000)
        parseDirectory()
        return true
    }

    private func isDriveResetCommand(_ uppercasedCommand: String) -> Bool {
        uppercasedCommand == "U0" ||
        uppercasedCommand == "U0:" ||
        uppercasedCommand == "UJ" ||
        uppercasedCommand == "UJ:" ||
        uppercasedCommand == "UI" ||
        uppercasedCommand == "UI:" ||
        uppercasedCommand == "UI+" ||
        uppercasedCommand == "UI-"
    }

    private func parseDeviceAddressChangeCommand(_ command: String) -> Bool? {
        let upper = command.uppercased()
        let prefix: String
        if upper.hasPrefix("U0>") {
            prefix = "U0>"
        } else if upper.hasPrefix("U0:>") {
            prefix = "U0:>"
        } else {
            return nil
        }

        let rawSuffix = String(command.dropFirst(prefix.count))
        if rawSuffix.unicodeScalars.count == 1,
           let scalar = rawSuffix.unicodeScalars.first,
           scalar.value < 0x20 {
            return (8...11).contains(Int(scalar.value))
        }

        let suffix = rawSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suffix.isEmpty else { return false }
        if let number = parseCommandNumber(suffix) {
            return (8...11).contains(number)
        }
        if suffix.unicodeScalars.count == 1,
           let scalar = suffix.unicodeScalars.first {
            return (8...11).contains(Int(scalar.value))
        }
        return false
    }

    private func executeMemoryCommand(_ commandBytes: [UInt8]) -> Bool? {
        guard commandBytes.count >= 3,
              commandBytes[0] == 0x4D || commandBytes[0] == 0x6D,
              commandBytes[1] == 0x2D else {
            return executeLongMemoryCommand(commandBytes)
        }

        var payload = Array(commandBytes.dropFirst(3))
        while payload.last == 0x0D || payload.last == 0x0A {
            payload.removeLast()
        }

        switch commandBytes[2] {
        case 0x52, 0x72: // M-R
            return executeMemoryCommand(kind: .read, payload: payload)
        case 0x57, 0x77: // M-W
            return executeMemoryCommand(kind: .write, payload: payload)
        case 0x45, 0x65: // M-E
            return executeMemoryCommand(kind: .execute, payload: payload)
        default:
            return nil
        }
    }

    private func executeLongMemoryCommand(_ commandBytes: [UInt8]) -> Bool? {
        let command = String(decoding: commandBytes, as: UTF8.self)
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = trimmed.uppercased()

        if upper.hasPrefix("MEMORY-READ") {
            return executeMemoryCommand(kind: .read, payload: Array(trimmed.dropFirst("MEMORY-READ".count).utf8))
        }
        if upper.hasPrefix("MEMORY-WRITE") {
            return executeMemoryCommand(kind: .write, payload: Array(trimmed.dropFirst("MEMORY-WRITE".count).utf8))
        }
        if upper.hasPrefix("MEMORY-EXECUTE") {
            return executeMemoryCommand(kind: .execute, payload: Array(trimmed.dropFirst("MEMORY-EXECUTE".count).utf8))
        }
        return nil
    }

    private enum MemoryCommandKind {
        case read
        case write
        case execute
    }

    private func executeMemoryCommand(kind: MemoryCommandKind, payload: [UInt8]) -> Bool {
        switch kind {
        case .read:
            guard let request = parseMemoryReadPayload(payload) else {
                commandStatus = "30, SYNTAX ERROR,00,00\r"
                return false
            }
            let count = request.count == 0 ? 256 : request.count
            commandResponseData = (0..<count).map { dosMemory[(request.address + $0) & 0xFFFF] }
            commandStatus = "00, OK,00,00\r"
            return true
        case .write:
            guard let request = parseMemoryWritePayload(payload) else {
                commandStatus = "30, SYNTAX ERROR,00,00\r"
                return false
            }
            for (index, byte) in request.bytes.enumerated() {
                dosMemory[(request.address + index) & 0xFFFF] = byte
            }
            commandStatus = "00, OK,00,00\r"
            return true
        case .execute:
            guard parseMemoryExecutePayload(payload) != nil else {
                commandStatus = "30, SYNTAX ERROR,00,00\r"
                return false
            }
            commandStatus = "00, OK,00,00\r"
            return true
        }
    }

    private func parseMemoryReadPayload(_ payload: [UInt8]) -> (address: Int, count: Int)? {
        if payload.first == 0x3A || payload.first == 0x20 || payload.first == 0x09 {
            let text = String(decoding: payload, as: UTF8.self)
            let parts = commandNumberParts(text)
            guard parts.count == 1 || parts.count == 2,
                  let address = parseCommandNumber(parts[0]),
                  (0...0xFFFF).contains(address) else {
                return nil
            }
            let count = parts.count == 2 ? parseCommandNumber(parts[1]) : 1
            guard let count, (0...256).contains(count) else { return nil }
            return (address, count)
        }

        guard payload.count >= 2 else { return nil }
        let address = Int(payload[0]) | (Int(payload[1]) << 8)
        let count = payload.count >= 3 ? Int(payload[2]) : 1
        return (address, count)
    }

    private func parseMemoryWritePayload(_ payload: [UInt8]) -> (address: Int, bytes: [UInt8])? {
        if payload.first == 0x3A || payload.first == 0x20 || payload.first == 0x09 {
            let text = String(decoding: payload, as: UTF8.self)
            let parts = commandNumberParts(text)
            guard parts.count >= 3,
                  let address = parseCommandNumber(parts[0]),
                  let count = parseCommandNumber(parts[1]),
                  (0...0xFFFF).contains(address),
                  (0...256).contains(count),
                  parts.count == (count == 0 ? 256 : count) + 2 else {
                return nil
            }
            var bytes: [UInt8] = []
            for part in parts.dropFirst(2) {
                guard let value = parseCommandNumber(part), (0...0xFF).contains(value) else {
                    return nil
                }
                bytes.append(UInt8(value))
            }
            return (address, bytes)
        }

        guard payload.count >= 3 else { return nil }
        let address = Int(payload[0]) | (Int(payload[1]) << 8)
        let count = Int(payload[2])
        let byteCount = count == 0 ? 256 : count
        guard payload.count >= 3 + byteCount else { return nil }
        return (address, Array(payload[3..<(3 + byteCount)]))
    }

    private func parseMemoryExecutePayload(_ payload: [UInt8]) -> Int? {
        if payload.first == 0x3A || payload.first == 0x20 || payload.first == 0x09 {
            let parts = commandNumberParts(String(decoding: payload, as: UTF8.self))
            guard parts.count == 1,
                  let address = parseCommandNumber(parts[0]),
                  (0...0xFFFF).contains(address) else {
                return nil
            }
            return address
        }

        guard payload.count >= 2 else { return nil }
        return Int(payload[0]) | (Int(payload[1]) << 8)
    }

    private func commandNumberParts(_ text: String) -> [String] {
        var normalized = text
        if normalized.first == ":" {
            normalized.removeFirst()
        }
        return normalized
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" })
            .map(String.init)
    }

    private func parseCommandNumber(_ text: String) -> Int? {
        if text.hasPrefix("$") {
            return Int(text.dropFirst(), radix: 16)
        }
        if text.hasPrefix("0x") || text.hasPrefix("0X") {
            return Int(text.dropFirst(2), radix: 16)
        }
        return Int(text)
    }

    @discardableResult
    private func formatD64(diskName newDiskName: String, diskID newDiskID: String) -> Bool {
        guard var image = imageData,
              let geometry = mountedGeometry,
              mountedFormat == .d64,
              geometry.trackCount >= 35,
              geometry.dataSize <= image.count else {
            commandStatus = "74, DRIVE NOT READY,00,00\r"
            return false
        }
        if rejectWriteProtected() { return false }

        for offset in 0..<geometry.dataSize {
            image[offset] = 0
        }
        if let errorInfoOffset = geometry.errorInfoOffset, errorInfoOffset < image.count {
            for offset in errorInfoOffset..<image.count {
                image[offset] = 0x01
            }
        }

        imageData = image
        initializeBAMAndDirectory(diskName: newDiskName, diskID: newDiskID)
        parseDirectory()
        markD64Modified()
        return true
    }

    private func initializeBAMAndDirectory(diskName newDiskName: String, diskID newDiskID: String) {
        guard var bam = readSector(track: 18, sector: 0),
              var directorySector = readSector(track: 18, sector: 1) else {
            return
        }

        bam = [UInt8](repeating: 0, count: 256)
        bam[0] = 18
        bam[1] = 1
        bam[2] = 0x41

        for track in 1...35 {
            let sectors = Self.sectorsPerTrack[track]
            var bitmap = [UInt8](repeating: 0, count: 3)
            for sector in 0..<sectors {
                bitmap[sector / 8] |= 1 << UInt8(sector % 8)
            }

            if track == 18 {
                bitmap[0] &= ~UInt8(0x03)
                bam[track * 4] = UInt8(sectors - 2)
            } else {
                bam[track * 4] = UInt8(sectors)
            }
            bam[track * 4 + 1] = bitmap[0]
            bam[track * 4 + 2] = bitmap[1]
            bam[track * 4 + 3] = bitmap[2]
        }

        let nameBytes = petsciiFilenameBytes(newDiskName)
        for index in 0..<16 {
            bam[0x90 + index] = nameBytes[index]
        }

        let idBytes = petsciiFilenameBytes(newDiskID)
        bam[0xA0] = 0xA0
        bam[0xA1] = 0xA0
        bam[0xA2] = idBytes[0]
        bam[0xA3] = idBytes[1]
        bam[0xA4] = 0xA0
        bam[0xA5] = 0x32
        bam[0xA6] = 0x41

        directorySector = [UInt8](repeating: 0, count: 256)
        directorySector[0] = 0
        directorySector[1] = 0xFF

        writeSector(track: 18, sector: 0, data: bam)
        writeSector(track: 18, sector: 1, data: directorySector)
    }

    @discardableResult
    private func validateD64() -> Bool {
        guard isMounted,
              let geometry = mountedGeometry,
              mountedFormat == .d64,
              geometry.trackCount >= 35 else {
            commandStatus = "74, DRIVE NOT READY,00,00\r"
            return false
        }
        if rejectWriteProtected() { return false }
        guard validateDirectorySectorsReadable() else { return false }
        guard readSector(track: 18, sector: 0) != nil else {
            commandStatus = "66, ILLEGAL TRACK OR SECTOR,18,00\r"
            return false
        }

        let occupied = occupiedSectors()
        for track in 1...35 {
            let sectors = Self.sectorsPerTrack[track]
            var freeCount = UInt8(0)
            for sector in 0..<sectors {
                let free = !occupied.contains(sectorChainKey(track: track, sector: sector))
                markBAMSector(track: track, sector: sector, free: free)
                if free { freeCount += 1 }
            }

            let countOffset = bamEntryOffset(forTrack: track)
            if countOffset < (imageData?.count ?? 0) {
                imageData?[countOffset] = freeCount
            }
        }

        parseDirectory()
        markD64Modified()
        return true
    }

    private func parseDiskFilename(_ filename: String) -> DiskFilenameRequest {
        var name = filename
        var replaceExisting = false
        var fileType: UInt8 = 0x82
        var typeFilter: UInt8?
        var accessMode: DiskFileAccessMode = .read

        if name.hasPrefix("@") {
            replaceExisting = true
            name.removeFirst()
        }

        if name.hasPrefix(":") {
            name.removeFirst()
        }

        if name.count >= 2 {
            let chars = Array(name)
            if chars[0].isNumber && chars[1] == ":" {
                name.removeFirst(2)
            }
        }

        let parts = name
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        if let first = parts.first {
            name = first
        }

        for option in parts.dropFirst().map({ $0.uppercased() }) {
            switch option {
            case "P", "PRG":
                fileType = 0x82
                typeFilter = 0x82
            case "S", "SEQ":
                fileType = 0x81
                typeFilter = 0x81
            case "U", "USR":
                fileType = 0x83
                typeFilter = 0x83
            case "L", "REL":
                fileType = 0x84
                typeFilter = 0x84
            case "R":
                accessMode = .read
            case "W":
                accessMode = .write
            case "A":
                accessMode = .append
            default:
                break
            }
        }

        return DiskFilenameRequest(
            name: name,
            replaceExisting: replaceExisting,
            fileType: fileType,
            typeFilter: typeFilter,
            accessMode: accessMode
        )
    }

    private func isDiskFilenameOption(_ option: String) -> Bool {
        switch option.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "P", "PRG", "S", "SEQ", "U", "USR", "L", "REL", "R", "W", "A":
            return true
        default:
            return false
        }
    }

    private func findFreeDirectorySlot() -> DirectorySlot? {
        guard let geometry = mountedGeometry, geometry.trackCount >= 18 else { return nil }
        var track = 18
        var sector = 1
        var visitedSectors = Set<Int>()
        var lastDirectorySector: (track: Int, sector: Int)?

        while track != 0 {
            let key = sectorChainKey(track: track, sector: sector)
            guard !visitedSectors.contains(key) else { return nil }
            visitedSectors.insert(key)
            lastDirectorySector = (track, sector)

            guard let data = readSector(track: track, sector: sector) else { return nil }
            for index in 0..<8 where data[index * 32 + 2] == 0 {
                return DirectorySlot(track: track, sector: sector, entryIndex: index)
            }

            track = Int(data[0])
            sector = Int(data[1])
        }

        guard let lastDirectorySector,
              let newSector = allocateDirectoryExtensionSector(occupied: visitedSectors) else {
            return nil
        }

        guard var previousSector = readSector(track: lastDirectorySector.track, sector: lastDirectorySector.sector) else {
            return nil
        }
        previousSector[0] = 18
        previousSector[1] = UInt8(newSector)
        var directorySector = [UInt8](repeating: 0, count: 256)
        directorySector[0] = 0
        directorySector[1] = 0xFF

        setBAMSector(track: 18, sector: newSector, free: false)
        writeSector(track: lastDirectorySector.track, sector: lastDirectorySector.sector, data: previousSector)
        writeSector(track: 18, sector: newSector, data: directorySector)
        return DirectorySlot(track: 18, sector: newSector, entryIndex: 0)
    }

    private func allocateDirectoryExtensionSector(occupied: Set<Int>) -> Int? {
        guard let geometry = mountedGeometry, geometry.trackCount >= 18 else { return nil }
        for sector in 0..<geometry.sectorsPerTrack[18] {
            let key = sectorChainKey(track: 18, sector: sector)
            guard !occupied.contains(key), isBAMSectorFree(track: 18, sector: sector) else { continue }
            return sector
        }
        return nil
    }

    private func findDirectorySlot(named name: String) -> (slot: DirectorySlot, entry: DirectoryEntry)? {
        findDirectorySlot(matching: DiskFilenameRequest(
            name: name,
            replaceExisting: false,
            fileType: 0x82,
            typeFilter: nil,
            accessMode: .read
        ))
    }

    private func findDirectorySlot(matching request: DiskFilenameRequest) -> (slot: DirectorySlot, entry: DirectoryEntry)? {
        let searchName = request.name.uppercased()
        var track = 18
        var sector = 1
        var visitedSectors = Set<Int>()

        while track != 0 {
            let key = sectorChainKey(track: track, sector: sector)
            guard !visitedSectors.contains(key) else { return nil }
            visitedSectors.insert(key)

            guard let data = readSector(track: track, sector: sector) else { return nil }
            for index in 0..<8 {
                let offset = index * 32
                let fileType = data[offset + 2]
                guard fileType != 0 else { continue }

                let filenameRaw = Array(data[offset + 5...offset + 20])
                let filename = petsciiToString(filenameRaw)
                guard filename.uppercased() == searchName,
                      fileTypeMatches(fileType, filter: request.typeFilter) else { continue }

                let entry = DirectoryEntry(
                    filename: filename,
                    filenameRaw: filenameRaw,
                    fileType: fileType,
                    firstTrack: data[offset + 3],
                    firstSector: data[offset + 4],
                    fileSize: UInt16(data[offset + 30]) | (UInt16(data[offset + 31]) << 8)
                )
                return (DirectorySlot(track: track, sector: sector, entryIndex: index), entry)
            }

            track = Int(data[0])
            sector = Int(data[1])
        }

        return nil
    }

    private func scratchFiles(matching filename: String) -> Int? {
        guard isMounted, mountedFormat == .d64 else {
            commandStatus = "74, DRIVE NOT READY,00,00\r"
            return nil
        }
        if rejectWriteProtected() { return nil }
        guard validateDirectorySectorsReadable() else { return nil }
        let request = parseDiskFilename(filename)
        guard !request.name.isEmpty, request.name != "$" else { return 0 }

        let matches = directorySlots(matching: request)
        guard !matches.isEmpty else { return 0 }

        for match in matches {
            let releasedSectors = fileChainKeys(firstTrack: Int(match.entry.firstTrack), firstSector: Int(match.entry.firstSector))
            clearDirectoryEntry(slot: match.slot)
            for key in releasedSectors {
                setBAMSector(track: key >> 8, sector: key & 0xFF, free: true)
            }
        }

        parseDirectory()
        markD64Modified()
        return matches.count
    }

    private func renameFile(expression: String) -> RenameResult? {
        guard isMounted, mountedFormat == .d64 else {
            commandStatus = "74, DRIVE NOT READY,00,00\r"
            return nil
        }
        guard !isWriteProtected else { return .writeProtected }
        guard validateDirectorySectorsReadable() else { return .readError }
        guard let separator = expression.firstIndex(of: "=") else { return .syntaxError }

        let destination = parseDiskFilename(String(expression[..<separator])).name
        let source = parseDiskFilename(String(expression[expression.index(after: separator)...]))
        guard !destination.isEmpty, !source.name.isEmpty, destination != "$", source.name != "$" else {
            return .syntaxError
        }
        guard findDirectorySlot(named: destination) == nil else { return .destinationExists }
        guard let existing = findDirectorySlot(matching: source) else { return .missingSource }

        renameDirectoryEntry(slot: existing.slot, filename: destination)
        parseDirectory()
        markD64Modified()
        return .renamed
    }

    private func copyFile(expression: String) -> CopyResult? {
        guard isMounted, mountedFormat == .d64 else {
            commandStatus = "74, DRIVE NOT READY,00,00\r"
            return nil
        }
        guard !isWriteProtected else { return .writeProtected }
        guard validateDirectorySectorsReadable() else { return .readError }
        guard let separator = expression.firstIndex(of: "=") else { return .syntaxError }

        let destinationRequest = parseDiskFilename(String(expression[..<separator]))
        let sourceSpecs = splitCopySourceExpressions(String(expression[expression.index(after: separator)...]))
        guard !destinationRequest.name.isEmpty, destinationRequest.name != "$", !sourceSpecs.isEmpty else {
            return .syntaxError
        }
        guard findDirectorySlot(named: destinationRequest.name) == nil else { return .destinationExists }

        var copiedData: [UInt8] = []
        var copiedFileType: UInt8?
        for sourceSpec in sourceSpecs {
            let sourceRequest = parseDiskFilename(sourceSpec)
            guard !sourceRequest.name.isEmpty, sourceRequest.name != "$" else { return .syntaxError }
            guard let sourceEntry = findFile(sourceSpec) else { return .missingSource }
            guard let data = loadFileData(sourceEntry) else {
                return .readError
            }
            if copiedFileType == nil {
                copiedFileType = sourceEntry.fileType
            }
            copiedData.append(contentsOf: data)
        }

        let request = DiskFilenameRequest(
            name: destinationRequest.name,
            replaceExisting: false,
            fileType: copiedFileType ?? 0x82,
            typeFilter: nil,
            accessMode: .write
        )
        guard saveFile(request: request, data: copiedData, fileType: request.fileType) else {
            return .syntaxError
        }
        return .copied
    }

    private func splitCopySourceExpressions(_ expression: String) -> [String] {
        let tokens = expression
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        var sources: [String] = []
        for token in tokens where !token.isEmpty {
            if isDiskFilenameOption(token), let last = sources.indices.last {
                sources[last] += ",\(token)"
            } else {
                sources.append(token)
            }
        }
        return sources
    }

    private func directorySlots(matching request: DiskFilenameRequest) -> [(slot: DirectorySlot, entry: DirectoryEntry)] {
        let searchName = request.name.uppercased()
        var matches: [(slot: DirectorySlot, entry: DirectoryEntry)] = []
        var track = 18
        var sector = 1
        var visitedSectors = Set<Int>()

        while track != 0 {
            let key = sectorChainKey(track: track, sector: sector)
            guard !visitedSectors.contains(key) else { return matches }
            visitedSectors.insert(key)

            guard let data = readSector(track: track, sector: sector) else { return matches }
            for index in 0..<8 {
                let offset = index * 32
                let fileType = data[offset + 2]
                guard fileType != 0 else { continue }

                let filenameRaw = Array(data[offset + 5...offset + 20])
                let filename = petsciiToString(filenameRaw)
                guard matchWildcard(searchName, filename.uppercased()),
                      fileTypeMatches(fileType, filter: request.typeFilter) else { continue }

                let entry = DirectoryEntry(
                    filename: filename,
                    filenameRaw: filenameRaw,
                    fileType: fileType,
                    firstTrack: data[offset + 3],
                    firstSector: data[offset + 4],
                    fileSize: UInt16(data[offset + 30]) | (UInt16(data[offset + 31]) << 8)
                )
                matches.append((DirectorySlot(track: track, sector: sector, entryIndex: index), entry))
            }

            track = Int(data[0])
            sector = Int(data[1])
        }

        return matches
    }

    private func sectorCountNeeded(forPayloadSize size: Int) -> Int {
        guard size > 0 else { return 0 }
        if size <= 253 { return 1 }
        return 1 + Int(ceil(Double(size - 253) / 254.0))
    }

    private func writePRGChain(data: [UInt8], sectors: [(track: Int, sector: Int)]) {
        var position = 0

        for index in sectors.indices {
            var sectorData = [UInt8](repeating: 0, count: 256)
            let isLast = index == sectors.indices.last
            let bytesRemaining = data.count - position

            if isLast {
                let byteCount = min(bytesRemaining, 253)
                sectorData[0] = 0
                sectorData[1] = UInt8(byteCount + 2)
                if byteCount > 0 {
                    sectorData.replaceSubrange(2..<(2 + byteCount), with: data[position..<(position + byteCount)])
                    position += byteCount
                }
            } else {
                let next = sectors[index + 1]
                sectorData[0] = UInt8(next.track)
                sectorData[1] = UInt8(next.sector)
                let byteCount = min(bytesRemaining, 254)
                sectorData.replaceSubrange(2..<(2 + byteCount), with: data[position..<(position + byteCount)])
                position += byteCount
            }

            writeSector(track: sectors[index].track, sector: sectors[index].sector, data: sectorData)
        }
    }

    private func writeDirectoryEntry(
        slot: DirectorySlot,
        filename: String,
        fileType: UInt8,
        firstSector: (track: Int, sector: Int),
        sectorCount: Int
    ) {
        guard var sectorData = readSector(track: slot.track, sector: slot.sector) else { return }
        let base = slot.entryIndex * 32
        sectorData[base + 2] = fileType | 0x80
        sectorData[base + 3] = UInt8(firstSector.track)
        sectorData[base + 4] = UInt8(firstSector.sector)

        let name = petsciiFilenameBytes(filename)
        for i in 0..<16 {
            sectorData[base + 5 + i] = name[i]
        }

        sectorData[base + 30] = UInt8(sectorCount & 0xFF)
        sectorData[base + 31] = UInt8((sectorCount >> 8) & 0xFF)
        writeSector(track: slot.track, sector: slot.sector, data: sectorData)
    }

    private func selectFreeSectors(count: Int, releasing released: Set<Int> = []) -> [(track: Int, sector: Int)]? {
        guard let geometry = mountedGeometry else { return nil }
        var occupied = occupiedSectors().subtracting(released)
        var selected: [(track: Int, sector: Int)] = []

        for track in 1...min(geometry.trackCount, Self.standardBAMTrackLimit) where track != 18 {
            ensureUsableBAMBitmap(forTrack: track, occupied: occupied)

            for sector in 0..<geometry.sectorsPerTrack[track] {
                let key = sectorChainKey(track: track, sector: sector)
                guard !occupied.contains(key),
                      released.contains(key) || isBAMSectorFree(track: track, sector: sector) else { continue }
                selected.append((track, sector))
                occupied.insert(key)
                if selected.count == count { return selected }
            }
        }

        return nil
    }

    private func occupiedSectors() -> Set<Int> {
        var occupied = Set<Int>()
        appendDirectoryChain(to: &occupied)
        for entry in directory {
            appendFileChain(entry, to: &occupied)
        }
        return occupied
    }

    private func appendDirectoryChain(to occupied: inout Set<Int>) {
        var track = 18
        var sector = 1

        while track != 0 {
            let key = sectorChainKey(track: track, sector: sector)
            guard !occupied.contains(key) else { return }
            occupied.insert(key)

            guard let data = readSector(track: track, sector: sector) else { return }
            track = Int(data[0])
            sector = Int(data[1])
        }
    }

    private func fileChainKeys(firstTrack: Int, firstSector: Int) -> Set<Int> {
        var keys = Set<Int>()
        var track = firstTrack
        var sector = firstSector

        while track != 0 {
            let key = sectorChainKey(track: track, sector: sector)
            guard !keys.contains(key) else { return keys }
            keys.insert(key)

            guard let data = readSector(track: track, sector: sector) else { return keys }
            track = Int(data[0])
            sector = Int(data[1])
        }

        return keys
    }

    private func appendFileChain(_ entry: DirectoryEntry, to occupied: inout Set<Int>) {
        var track = Int(entry.firstTrack)
        var sector = Int(entry.firstSector)

        while track != 0 {
            let key = sectorChainKey(track: track, sector: sector)
            guard !occupied.contains(key) else { return }
            occupied.insert(key)

            guard let data = readSector(track: track, sector: sector) else { return }
            track = Int(data[0])
            sector = Int(data[1])
        }
    }

    private func ensureUsableBAMBitmap(forTrack track: Int, occupied: Set<Int>) {
        guard let geometry = mountedGeometry,
              let image = imageData,
              track >= 1 && track <= geometry.trackCount else { return }

        let bamOffset = bamEntryOffset(forTrack: track)
        guard bamOffset + 3 < image.count else { return }
        let hasBitmap = image[bamOffset + 1] != 0 || image[bamOffset + 2] != 0 || image[bamOffset + 3] != 0
        guard !hasBitmap, image[bamOffset] > 0 else { return }

        var freeCount = UInt8(0)
        for sector in 0..<geometry.sectorsPerTrack[track] {
            let free = !occupied.contains(sectorChainKey(track: track, sector: sector))
            markBAMSector(track: track, sector: sector, free: free)
            if free { freeCount += 1 }
        }

        if bamOffset < (imageData?.count ?? 0) {
            imageData?[bamOffset] = freeCount
        }
    }

    private func isBAMSectorFree(track: Int, sector: Int) -> Bool {
        guard let image = imageData else { return false }
        let byteOffset = bamEntryOffset(forTrack: track) + 1 + sector / 8
        guard byteOffset < image.count else { return false }
        return image[byteOffset] & (1 << UInt8(sector % 8)) != 0
    }

    private func markBAMSector(track: Int, sector: Int, free: Bool) {
        let byteOffset = bamEntryOffset(forTrack: track) + 1 + sector / 8
        guard imageData != nil, byteOffset < imageData!.count else { return }
        let mask = UInt8(1 << UInt8(sector % 8))
        if free {
            imageData![byteOffset] |= mask
        } else {
            imageData![byteOffset] &= ~mask
        }
        clearSectorErrorCode(track: 18, sector: 0)
    }

    private func setBAMSector(track: Int, sector: Int, free: Bool) {
        let wasFree = isBAMSectorFree(track: track, sector: sector)
        guard wasFree != free else { return }

        markBAMSector(track: track, sector: sector, free: free)
        let countOffset = bamEntryOffset(forTrack: track)
        guard countOffset < (imageData?.count ?? 0) else { return }

        if free {
            let count = imageData?[countOffset] ?? 0
            imageData?[countOffset] = count &+ 1
        } else if let count = imageData?[countOffset], count > 0 {
            imageData?[countOffset] = count - 1
        }
    }

    private func bamEntryOffset(forTrack track: Int) -> Int {
        DiskDrive.trackOffset[18] + track * 4
    }

    private func clearDirectoryEntry(slot: DirectorySlot) {
        guard var sectorData = readSector(track: slot.track, sector: slot.sector) else { return }
        let base = slot.entryIndex * 32
        for offset in 2..<32 {
            sectorData[base + offset] = 0
        }
        writeSector(track: slot.track, sector: slot.sector, data: sectorData)
    }

    private func renameDirectoryEntry(slot: DirectorySlot, filename: String) {
        guard var sectorData = readSector(track: slot.track, sector: slot.sector) else { return }
        let base = slot.entryIndex * 32
        let name = petsciiFilenameBytes(filename)
        for index in 0..<16 {
            sectorData[base + 5 + index] = name[index]
        }
        writeSector(track: slot.track, sector: slot.sector, data: sectorData)
    }

    private func writeSector(track: Int, sector: Int, data: [UInt8]) {
        guard var image = imageData,
              let geometry = mountedGeometry,
              track >= 1 && track <= geometry.trackCount,
              sector >= 0 && sector < geometry.sectorsPerTrack[track],
              data.count == 256 else { return }

        let offset = geometry.trackOffsets[track] + sector * 256
        guard offset + 256 <= image.count else { return }
        image.replaceSubrange(offset..<offset + 256, with: data)
        clearSectorErrorCode(track: track, sector: sector, in: &image, geometry: geometry)
        imageData = image
    }

    private func clearSectorErrorCode(track: Int, sector: Int) {
        guard var image = imageData, let geometry = mountedGeometry else { return }
        clearSectorErrorCode(track: track, sector: sector, in: &image, geometry: geometry)
        imageData = image
    }

    private func clearSectorErrorCode(track: Int, sector: Int, in image: inout [UInt8], geometry: D64Geometry) {
        guard let errorInfoOffset = geometry.errorInfoOffset,
              let ordinal = sectorOrdinal(track: track, sector: sector, geometry: geometry) else {
            return
        }

        let errorOffset = errorInfoOffset + ordinal
        if errorOffset < image.count {
            image[errorOffset] = 0x01
        }
    }

    public func generateDirectoryListing() -> [UInt8] {
        generateDirectoryListing(matching: nil)
    }

    /// Generate a directory listing as a BASIC program (like LOAD"$",8).
    private func generateDirectoryListing(matching request: DiskFilenameRequest?) -> [UInt8] {
        var prg: [UInt8] = []

        // Load address: $0801 (BASIC start — matches where LOAD"$",8 puts it)
        prg.append(0x01)
        prg.append(0x08)

        var lineAddr: UInt16 = 0x0801

        // Header line: 0 "DISK NAME" ID
        lineAddr += addDirectoryLine(&prg, lineNumber: 0, text: headerLine())

        // File entries
        for entry in directory {
            if let request,
               !directoryEntry(entry, matchesListingRequest: request) {
                continue
            }
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

    private func directoryListingRequest(for filename: String) -> DiskFilenameRequest? {
        var listingName = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if listingName.hasPrefix(":") {
            listingName.removeFirst()
        }
        if listingName.count >= 2 {
            let chars = Array(listingName)
            if chars[0].isNumber && chars[1] == ":" {
                listingName.removeFirst(2)
            }
        }
        guard listingName.hasPrefix("$") else { return nil }

        var pattern = String(listingName.dropFirst())
        if pattern == "0" || pattern.isEmpty { return nil }
        if pattern.hasPrefix(":") {
            pattern.removeFirst()
        }
        if pattern.count >= 2 {
            let chars = Array(pattern)
            if chars[0].isNumber && chars[1] == ":" {
                pattern.removeFirst(2)
            }
        }
        guard !pattern.isEmpty else { return nil }
        return parseDiskFilename(pattern)
    }

    private func directoryEntry(_ entry: DirectoryEntry, matchesListingRequest request: DiskFilenameRequest) -> Bool {
        let searchName = request.name.isEmpty ? "*" : request.name.uppercased()
        return fileTypeMatches(entry.fileType, filter: request.typeFilter)
            && (searchName == "*" || matchWildcard(searchName, entry.filename.uppercased()))
    }

    private func validateDirectorySectorsReadable() -> Bool {
        guard isMounted else {
            commandStatus = "74, DRIVE NOT READY,00,00\r"
            return false
        }

        guard validateSectorReadable(track: 18, sector: 0) else { return false }
        guard let bam = readSector(track: 18, sector: 0) else {
            commandStatus = "66, ILLEGAL TRACK OR SECTOR,18,00\r"
            return false
        }

        var track = Int(bam[0])
        var sector = Int(bam[1])
        if track == 0 {
            track = 18
            sector = 1
        }
        var visitedSectors = Set<Int>()

        while track != 0 {
            let key = sectorChainKey(track: track, sector: sector)
            guard !visitedSectors.contains(key) else { break }
            visitedSectors.insert(key)

            guard validateSectorReadable(track: track, sector: sector) else { return false }
            guard let data = readSector(track: track, sector: sector) else {
                commandStatus = String(format: "66, ILLEGAL TRACK OR SECTOR,%02d,%02d\r", track, sector)
                return false
            }

            track = Int(data[0])
            sector = Int(data[1])
        }

        return true
    }

    private func validateSectorReadable(track: Int, sector: Int) -> Bool {
        if let code = readSectorErrorCode(track: track, sector: sector),
           isReadSideSectorError(code) {
            commandStatus = String(format: "%02d, READ ERROR,%02d,%02d\r", Int(code), track, sector)
            return false
        }
        return true
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

    private func commandChannelOutput() -> (data: [UInt8], clearsCommandStatusOnEOF: Bool) {
        if let response = commandResponseData {
            commandResponseData = nil
            return (response, false)
        }
        return (Array(commandStatus.utf8), true)
    }

    private func executeBufferedCommand(channel: Int) {
        let command = String(decoding: channels[channel].writeData, as: UTF8.self)
        channels[channel].writeData.removeAll(keepingCapacity: true)
        channels[channel].writePosition = 0
        _ = executeCommand(command)
        let output = commandChannelOutput()
        channels[channel].data = output.data
        channels[channel].clearsCommandStatusOnEOF = output.clearsCommandStatusOnEOF
        channels[channel].position = 0
        channels[channel].isOpen = true
    }

    /// Open a file on a channel for reading.
    public func openFile(channel: Int, filename: String) -> Bool {
        guard channel >= 0 && channel < 16 else { return false }

        if channel == 15 {
            if !filename.isEmpty {
                _ = executeCommand(filename)
            }
            let output = commandChannelOutput()
            channels[channel] = Channel(
                data: output.data,
                position: 0,
                isOpen: true,
                clearsCommandStatusOnEOF: output.clearsCommandStatusOnEOF
            )
            return true
        }

        let request = parseDiskFilename(filename)
        if request.name.hasPrefix("#") {
            channels[channel] = Channel(data: [], writeData: [], position: 0, isOpen: true)
            return true
        }

        if request.accessMode == .write || request.accessMode == .append {
            return openOutputFile(channel: channel, request: request)
        }

        if isDirectoryListingRequest(filename) {
            // Directory listing
            guard let listing = loadDirectoryListing(matching: filename) else { return false }
            channels[channel] = Channel(data: listing, position: 0, isOpen: true)
            return true
        }

        guard let data = loadFileData(named: filename) else { return false }

        // For PRG files, prepend the load address (first 2 bytes of file data)
        // The file data from the disk already includes the load address
        // Actually, the raw file data on disk IS the PRG data (with load address)
        // So we just use it as-is
        channels[channel] = Channel(data: data, position: 0, isOpen: true)
        return true
    }

    private func openOutputFile(channel: Int, request: DiskFilenameRequest) -> Bool {
        guard isMounted, mountedFormat == .d64 else {
            commandStatus = "74, DRIVE NOT READY,00,00\r"
            return false
        }
        guard !isWriteProtected else {
            commandStatus = "26, WRITE PROTECT ON,00,00\r"
            return false
        }
        guard !request.name.isEmpty,
              request.name != "$",
              !request.name.hasPrefix("#"),
              validateDirectorySectorsReadable() else {
            return false
        }

        let existing = request.accessMode == .append ? findFile(matching: request) : findFile(request.name)
        if request.accessMode == .write && existing != nil && !request.replaceExisting {
            commandStatus = "63, FILE EXISTS,00,00\r"
            return false
        }

        var channelState = Channel(
            data: [],
            writeData: [],
            position: 0,
            writePosition: 0,
            isOpen: true,
            outputFilename: request.name,
            outputFileType: request.fileType,
            outputTypeFilter: request.accessMode == .append ? request.typeFilter : nil,
            outputReplacesExisting: request.replaceExisting || request.accessMode == .append
        )

        if request.accessMode == .append, let existing {
            guard let existingData = loadFileData(existing) else { return false }
            channelState.writeData = existingData
            channelState.writePosition = existingData.count
        }

        channels[channel] = channelState
        commandStatus = "00, OK,00,00\r"
        return true
    }

    /// Read a byte from a channel.
    public func readByte(channel: Int) -> (byte: UInt8, eof: Bool) {
        guard channel >= 0 && channel < 16 && channels[channel].isOpen else {
            return (0, true)
        }
        let byte = channels[channel].readByte()
        let eof = !channels[channel].hasData
        if channel == 15, eof, channels[channel].clearsCommandStatusOnEOF {
            commandStatus = "00, OK,00,00\r"
            channels[channel].clearsCommandStatusOnEOF = false
        }
        return (byte, eof)
    }

    /// Write a byte to an open channel output buffer.
    public func writeByte(channel: Int, byte: UInt8) -> Bool {
        guard channel >= 0 && channel < 16 && channels[channel].isOpen else {
            return false
        }
        if channel == 15, byte == 0x0D {
            executeBufferedCommand(channel: channel)
            return true
        }
        channels[channel].writeByte(byte)
        return true
    }

    /// Close a channel.
    public func closeChannel(_ channel: Int) {
        guard channel >= 0 && channel < 16 else { return }
        if channel == 15, channels[channel].isOpen, !channels[channel].writeData.isEmpty {
            executeBufferedCommand(channel: channel)
        } else if channel != 15,
                  channels[channel].isOpen,
                  let filename = channels[channel].outputFilename {
            var request = parseDiskFilename(filename)
            request = DiskFilenameRequest(
                name: request.name,
                replaceExisting: channels[channel].outputReplacesExisting,
                fileType: channels[channel].outputFileType,
                typeFilter: channels[channel].outputTypeFilter,
                accessMode: .write
            )
            if !saveFile(request: request, data: channels[channel].writeData, fileType: channels[channel].outputFileType) {
                if currentCommandStatus == "00, OK,00,00\r" {
                    commandStatus = "72, DISK FULL,00,00\r"
                }
            }
        }
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

    private func petsciiFilenameBytes(_ filename: String) -> [UInt8] {
        let bytes = filename.prefix(16).map { charToPetscii($0) }
        return bytes + [UInt8](repeating: 0xA0, count: max(0, 16 - bytes.count))
    }
}
