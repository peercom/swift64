import Foundation

/// Loads PRG files into C64 RAM.
/// PRG format: 2 bytes little-endian load address, followed by data bytes.
public struct PRGLoader {

    /// Parsed PRG file.
    public struct PRGFile {
        public let loadAddress: UInt16
        public let data: [UInt8]

        public var endAddress: UInt16 {
            loadAddress &+ UInt16(data.count)
        }
    }

    /// Parse a PRG file from raw data.
    public static func parse(_ fileData: Data) -> PRGFile? {
        guard fileData.count >= 3 else { return nil }  // Need at least address + 1 byte
        let bytes = [UInt8](fileData)
        let loadAddress = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        let data = Array(bytes[2...])
        return PRGFile(loadAddress: loadAddress, data: data)
    }

    /// Parse a P00 file (PC64 format). Has a 26-byte header before the PRG data.
    public static func parseP00(_ fileData: Data) -> PRGFile? {
        guard fileData.count >= 28 else { return nil }
        let bytes = [UInt8](fileData)

        // Verify P00 header: "C64File\0"
        let sig = bytes[0..<7]
        let expected: [UInt8] = [0x43, 0x36, 0x34, 0x46, 0x69, 0x6C, 0x65]  // "C64File"
        guard Array(sig) == expected else { return nil }

        // PRG data starts at offset 26
        let prgData = Data(bytes[26...])
        return parse(prgData)
    }

    /// Load a PRG file directly into C64 RAM.
    /// If `useFileAddress` is true, loads at the address specified in the file.
    /// Otherwise loads at the BASIC start address ($0801).
    /// Returns the end address.
    public static func load(_ prg: PRGFile, into ram: inout [UInt8], useFileAddress: Bool = true) -> UInt16 {
        let startAddr = useFileAddress ? prg.loadAddress : 0x0801
        for (i, byte) in prg.data.enumerated() {
            let addr = Int(startAddr) + i
            if addr < 0x10000 {
                ram[addr] = byte
            }
        }
        return startAddr &+ UInt16(prg.data.count)
    }

    /// Detect file format from extension and parse accordingly.
    public static func loadFromFile(_ url: URL) -> PRGFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = url.pathExtension.lowercased()
        if ext == "p00" {
            return parseP00(data)
        }
        return parse(data)
    }
}
