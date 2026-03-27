import Foundation

/// Parses iNES ROM files and provides cartridge data.
public final class Cartridge {

    public enum MirrorMode: UInt8 {
        case horizontal = 0
        case vertical   = 1
        case fourScreen = 2
    }

    public var prgROM: [UInt8] = []
    public var chrROM: [UInt8] = []
    public private(set) var mapperNumber: UInt8 = 0
    public private(set) var mirrorMode: MirrorMode = .horizontal
    public private(set) var hasBatteryRAM: Bool = false
    public var prgRAM = [UInt8](repeating: 0, count: 8192)

    public init() {}

    /// Load an iNES (.nes) file.
    @discardableResult
    public func load(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 16 else { return false }

        // Check "NES\x1A" magic
        guard bytes[0] == 0x4E, bytes[1] == 0x45, bytes[2] == 0x53, bytes[3] == 0x1A else {
            return false
        }

        let prgBanks = Int(bytes[4])  // 16KB units
        let chrBanks = Int(bytes[5])  // 8KB units
        let flags6 = bytes[6]
        let flags7 = bytes[7]

        mirrorMode = (flags6 & 0x08) != 0 ? .fourScreen :
                     (flags6 & 0x01) != 0 ? .vertical : .horizontal
        hasBatteryRAM = (flags6 & 0x02) != 0
        mapperNumber = (flags6 >> 4) | (flags7 & 0xF0)

        let hasTrainer = (flags6 & 0x04) != 0
        var offset = 16 + (hasTrainer ? 512 : 0)

        let prgSize = prgBanks * 16384
        guard bytes.count >= offset + prgSize else { return false }
        prgROM = Array(bytes[offset..<offset + prgSize])
        offset += prgSize

        let chrSize = chrBanks * 8192
        if chrSize > 0 && bytes.count >= offset + chrSize {
            chrROM = Array(bytes[offset..<offset + chrSize])
        } else if chrBanks == 0 {
            // CHR RAM (8KB)
            chrROM = [UInt8](repeating: 0, count: 8192)
        }

        return true
    }

    @discardableResult
    public func loadFromFile(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return load(data)
    }
}
