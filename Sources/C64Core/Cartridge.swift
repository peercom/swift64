import Foundation

/// C64 cartridge image with enough mapping detail for standard CRT ROMs.
public struct Cartridge: Equatable {
    public enum MappingMode: Equatable {
        case normal8K
        case normal16K
        case ultimax
    }

    public struct Chip: Equatable {
        public let type: UInt16
        public let bank: UInt16
        public let loadAddress: UInt16
        public let data: [UInt8]
    }

    public let name: String
    public let hardwareType: UInt16
    public let exromLineHigh: Bool
    public let gameLineHigh: Bool
    public let mappingMode: MappingMode
    public let chips: [Chip]

    private let roml: [UInt8]?
    private let romh: [UInt8]?

    public init(
        name: String,
        hardwareType: UInt16,
        exromLineHigh: Bool,
        gameLineHigh: Bool,
        mappingMode: MappingMode,
        chips: [Chip],
        roml: [UInt8]?,
        romh: [UInt8]?
    ) {
        self.name = name
        self.hardwareType = hardwareType
        self.exromLineHigh = exromLineHigh
        self.gameLineHigh = gameLineHigh
        self.mappingMode = mappingMode
        self.chips = chips
        self.roml = roml
        self.romh = romh
    }

    public static func parseCRT(_ data: Data) -> Cartridge? {
        let bytes = [UInt8](data)
        guard bytes.count >= 0x40 else { return nil }
        guard String(bytes: bytes[0..<16], encoding: .ascii) == "C64 CARTRIDGE   " else {
            return nil
        }

        let headerLength = Int(readUInt32BE(bytes, at: 0x10))
        guard headerLength >= 0x40, headerLength <= bytes.count else { return nil }

        let hardwareType = readUInt16BE(bytes, at: 0x16)
        guard hardwareType == 0 else { return nil }

        let exromLineHigh = bytes[0x18] != 0
        let gameLineHigh = bytes[0x19] != 0
        let rawName = bytes[0x20..<0x40]
        let name = String(bytes: rawName.prefix { $0 != 0 }, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "CRT Cartridge"

        var chips: [Chip] = []
        var offset = headerLength
        while offset < bytes.count {
            guard offset + 16 <= bytes.count else { return nil }
            guard String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii) == "CHIP" else {
                return nil
            }

            let packetLength = Int(readUInt32BE(bytes, at: offset + 4))
            guard packetLength >= 16, offset + packetLength <= bytes.count else { return nil }

            let chipType = readUInt16BE(bytes, at: offset + 8)
            let bank = readUInt16BE(bytes, at: offset + 10)
            let loadAddress = readUInt16BE(bytes, at: offset + 12)
            let size = Int(readUInt16BE(bytes, at: offset + 14))
            guard size <= packetLength - 16 else { return nil }

            let payloadStart = offset + 16
            let payloadEnd = payloadStart + size
            chips.append(Chip(
                type: chipType,
                bank: bank,
                loadAddress: loadAddress,
                data: Array(bytes[payloadStart..<payloadEnd])
            ))

            offset += packetLength
        }

        guard !chips.isEmpty else { return nil }

        let mode: MappingMode
        switch (exromLineHigh, gameLineHigh) {
        case (false, true):
            mode = .normal8K
        case (false, false):
            mode = .normal16K
        case (true, false):
            mode = .ultimax
        default:
            return nil
        }

        var roml = [UInt8](repeating: 0xFF, count: 0x2000)
        var romh = [UInt8](repeating: 0xFF, count: 0x2000)
        var hasROML = false
        var hasROMH = false

        for chip in chips where chip.bank == 0 {
            switch chip.loadAddress {
            case 0x8000...0x9FFF:
                guard copy(chip.data, into: &roml, at: Int(chip.loadAddress - 0x8000)) else {
                    return nil
                }
                hasROML = true
            case 0xA000...0xBFFF:
                guard copy(chip.data, into: &romh, at: Int(chip.loadAddress - 0xA000)) else {
                    return nil
                }
                hasROMH = true
            case 0xE000...0xFFFF:
                guard mode == .ultimax, copy(chip.data, into: &romh, at: Int(chip.loadAddress - 0xE000)) else {
                    return nil
                }
                hasROMH = true
            default:
                return nil
            }
        }

        guard hasROML || hasROMH else { return nil }
        if mode == .normal8K {
            guard hasROML else { return nil }
        } else {
            guard hasROML && hasROMH else { return nil }
        }

        return Cartridge(
            name: name.isEmpty ? "CRT Cartridge" : name,
            hardwareType: hardwareType,
            exromLineHigh: exromLineHigh,
            gameLineHigh: gameLineHigh,
            mappingMode: mode,
            chips: chips,
            roml: hasROML ? roml : nil,
            romh: hasROMH ? romh : nil
        )
    }

    public func read(_ address: UInt16) -> UInt8? {
        let addr = Int(address)
        switch (mappingMode, addr) {
        case (_, 0x8000...0x9FFF):
            return roml?[addr - 0x8000]
        case (.normal16K, 0xA000...0xBFFF):
            return romh?[addr - 0xA000]
        case (.ultimax, 0xE000...0xFFFF):
            return romh?[addr - 0xE000]
        default:
            return nil
        }
    }

    private static func copy(_ data: [UInt8], into destination: inout [UInt8], at offset: Int) -> Bool {
        guard offset >= 0, offset + data.count <= destination.count else { return false }
        destination.replaceSubrange(offset..<(offset + data.count), with: data)
        return true
    }

    private static func readUInt16BE(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    private static func readUInt32BE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }
}
