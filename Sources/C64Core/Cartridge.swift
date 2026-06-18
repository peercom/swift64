import Foundation

/// C64 cartridge image with enough mapping detail for standard CRT ROMs.
public struct Cartridge: Equatable {
    public enum MappingMode: Equatable {
        case normal8K
        case normal16K
        case ultimax
        case simonsBasic
        case magicDesk
        case ocean
        case funPlay
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

    public var usesUltimaxMemoryMap: Bool {
        mappingMode == .ultimax
    }

    private let roml: [UInt8]?
    private let romh: [UInt8]?
    private let romlBanks: [UInt16: [UInt8]]
    private let romhBanks: [UInt16: [UInt8]]
    private var activeBank: UInt16
    private var cartridgeDisabled: Bool
    private var simonsBasicUpperROMEnabled: Bool

    public init(
        name: String,
        hardwareType: UInt16,
        exromLineHigh: Bool,
        gameLineHigh: Bool,
        mappingMode: MappingMode,
        chips: [Chip],
        roml: [UInt8]?,
        romh: [UInt8]?,
        romlBanks: [UInt16: [UInt8]] = [:],
        romhBanks: [UInt16: [UInt8]] = [:],
        activeBank: UInt16 = 0,
        cartridgeDisabled: Bool = false,
        simonsBasicUpperROMEnabled: Bool = false
    ) {
        self.name = name
        self.hardwareType = hardwareType
        self.exromLineHigh = exromLineHigh
        self.gameLineHigh = gameLineHigh
        self.mappingMode = mappingMode
        self.chips = chips
        self.roml = roml
        self.romh = romh
        self.romlBanks = romlBanks
        self.romhBanks = romhBanks
        self.activeBank = activeBank
        self.cartridgeDisabled = cartridgeDisabled
        self.simonsBasicUpperROMEnabled = simonsBasicUpperROMEnabled
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
        guard Self.supportedHardwareTypes.contains(hardwareType) else { return nil }

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
        if hardwareType == 4 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .simonsBasic
        } else if hardwareType == 5 {
            guard !exromLineHigh && !gameLineHigh else { return nil }
            mode = .ocean
        } else if hardwareType == 7 {
            guard !exromLineHigh && !gameLineHigh else { return nil }
            mode = .funPlay
        } else if hardwareType == 19 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .magicDesk
        } else {
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
        }

        var roml = [UInt8](repeating: 0xFF, count: 0x2000)
        var romh = [UInt8](repeating: 0xFF, count: 0x2000)
        var romlBanks: [UInt16: [UInt8]] = [:]
        var romhBanks: [UInt16: [UInt8]] = [:]
        var hasROML = false
        var hasROMH = false

        if mode == .magicDesk || mode == .ocean || mode == .funPlay {
            for chip in chips {
                guard chip.loadAddress >= 0x8000 && chip.loadAddress <= 0xBFFF else {
                    return nil
                }
                var bank = [UInt8](repeating: 0xFF, count: 0x2000)
                let bankBase: UInt16 = chip.loadAddress < 0xA000 ? 0x8000 : 0xA000
                guard copy(chip.data, into: &bank, at: Int(chip.loadAddress - bankBase)) else {
                    return nil
                }
                if bankBase == 0x8000 {
                    romlBanks[chip.bank] = bank
                } else {
                    guard mode == .ocean else { return nil }
                    romhBanks[chip.bank] = bank
                }
            }
            hasROML = !romlBanks.isEmpty
            hasROMH = !romhBanks.isEmpty
            roml = romlBanks[0] ?? romlBanks[romlBanks.keys.min() ?? 0] ?? roml
            romh = romhBanks[0] ?? romhBanks[romhBanks.keys.min() ?? 0] ?? romh
        } else {
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
        }

        if mode == .simonsBasic {
            guard hasROML, hasROMH else { return nil }
        } else if mode != .magicDesk && mode != .ocean && mode != .funPlay {
            guard hasROML || hasROMH else { return nil }
            if mode == .normal8K {
                guard hasROML else { return nil }
            } else {
                guard hasROML && hasROMH else { return nil }
            }
        } else if mode == .magicDesk {
            guard hasROML, !hasROMH else { return nil }
        } else if mode == .funPlay {
            guard hasROML, !hasROMH else { return nil }
        } else {
            guard hasROML || hasROMH else { return nil }
        }

        return Cartridge(
            name: name.isEmpty ? "CRT Cartridge" : name,
            hardwareType: hardwareType,
            exromLineHigh: exromLineHigh,
            gameLineHigh: gameLineHigh,
            mappingMode: mode,
            chips: chips,
            roml: hasROML ? roml : nil,
            romh: hasROMH ? romh : nil,
            romlBanks: romlBanks,
            romhBanks: romhBanks
        )
    }

    public func read(_ address: UInt16) -> UInt8? {
        let addr = Int(address)
        switch (mappingMode, addr) {
        case (.magicDesk, 0x8000...0x9FFF), (.ocean, 0x8000...0x9FFF), (.funPlay, 0x8000...0x9FFF):
            guard !cartridgeDisabled else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.ocean, 0xA000...0xBFFF):
            return romhBanks[activeBank]?[addr - 0xA000]
        case (.simonsBasic, 0xA000...0xBFFF):
            guard simonsBasicUpperROMEnabled else { return nil }
            return romh?[addr - 0xA000]
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

    public mutating func writeIO1(_ address: UInt16, value: UInt8) {
        guard (0xDE00...0xDEFF).contains(address) else { return }
        switch mappingMode {
        case .simonsBasic:
            simonsBasicUpperROMEnabled = value & 0x01 != 0
        case .magicDesk:
            cartridgeDisabled = value & 0x80 != 0
            activeBank = UInt16(value & 0x7F)
        case .ocean:
            activeBank = UInt16(value & 0x3F)
        case .funPlay:
            activeBank = UInt16(value & 0x39)
            cartridgeDisabled = value == 0x86
        default:
            break
        }
    }

    public mutating func reset() {
        activeBank = 0
        cartridgeDisabled = false
        simonsBasicUpperROMEnabled = false
    }

    private static func copy(_ data: [UInt8], into destination: inout [UInt8], at offset: Int) -> Bool {
        guard offset >= 0, offset + data.count <= destination.count else { return false }
        destination.replaceSubrange(offset..<(offset + data.count), with: data)
        return true
    }

    private static let supportedHardwareTypes: Set<UInt16> = [
        0,  // Normal cartridge
        4,  // Simon's BASIC
        5,  // Ocean type 1
        7,  // Fun Play / Power Play
        11, // Westermann Learning, normal 16K mapping
        12, // Rex Utility, normal 8K mapping
        19  // Magic Desk / Domark / HES Australia
    ]

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
