import Foundation

/// C64 cartridge image with enough mapping detail for standard CRT ROMs.
public struct Cartridge: Equatable {
    public enum MappingMode: Equatable {
        case normal8K
        case normal16K
        case ultimax
        case actionReplay
        case actionReplay3
        case actionReplay4
        case finalCartridgeI
        case finalCartridgePlus
        case finalCartridgeIII
        case simonsBasic
        case epyxFastLoad
        case c64GameSystem
        case warpSpeed
        case magicFormel
        case magicDesk
        case ocean
        case funPlay
        case easyFlash
    }

    public enum EasyFlashMemoryMode: Equatable {
        case off
        case ultimax
        case eightK
        case sixteenK
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
    private let finalCartridgePlusKernalROM: [UInt8]?
    private let romlBanks: [UInt16: [UInt8]]
    private let romhBanks: [UInt16: [UInt8]]
    private var activeBank: UInt16
    private var cartridgeDisabled: Bool
    private var actionReplayRAMEnabled: Bool
    private var actionReplayRAM: [UInt8]
    private var actionReplay3ROMVisible: Bool
    private var actionReplay4ROMVisible: Bool
    private var finalCartridgeIROMVisible: Bool
    private var finalCartridgePlusEnabled: Bool
    private var finalCartridgePlusLowROMVisible: Bool
    private var finalCartridgePlusKernalROMVisible: Bool
    private var finalCartridgePlusControlBit7: Bool
    private var finalCartridgeIIIRegisterHidden: Bool
    private var finalCartridgeIIIROMLVisible: Bool
    private var finalCartridgeIIIROMHVisible: Bool
    private var finalCartridgeIIINMILineActive: Bool
    private var simonsBasicUpperROMEnabled: Bool
    private var epyxFastLoadROMEnabled: Bool
    private var epyxFastLoadCyclesSinceDischarge: Int
    private var warpSpeedROMVisible: Bool
    /// This model assumes the physical EasyFlash boot jumper is in "Boot".
    /// In that position, $DE02 modes 000 and 010 derive GAME from the jumper.
    private var easyFlashBootJumperEnabled: Bool
    private var easyFlashMemoryMode: EasyFlashMemoryMode
    private var easyFlashRAM: [UInt8]

    public init(
        name: String,
        hardwareType: UInt16,
        exromLineHigh: Bool,
        gameLineHigh: Bool,
        mappingMode: MappingMode,
        chips: [Chip],
        roml: [UInt8]?,
        romh: [UInt8]?,
        finalCartridgePlusKernalROM: [UInt8]? = nil,
        romlBanks: [UInt16: [UInt8]] = [:],
        romhBanks: [UInt16: [UInt8]] = [:],
        activeBank: UInt16 = 0,
        cartridgeDisabled: Bool = false,
        actionReplayRAMEnabled: Bool = false,
        actionReplayRAM: [UInt8] = [UInt8](repeating: 0, count: 0x2000),
        actionReplay3ROMVisible: Bool = true,
        actionReplay4ROMVisible: Bool = true,
        finalCartridgeIROMVisible: Bool = true,
        finalCartridgePlusEnabled: Bool = true,
        finalCartridgePlusLowROMVisible: Bool = true,
        finalCartridgePlusKernalROMVisible: Bool = true,
        finalCartridgePlusControlBit7: Bool = false,
        finalCartridgeIIIRegisterHidden: Bool = false,
        finalCartridgeIIIROMLVisible: Bool = true,
        finalCartridgeIIIROMHVisible: Bool = true,
        finalCartridgeIIINMILineActive: Bool = false,
        simonsBasicUpperROMEnabled: Bool = false,
        epyxFastLoadROMEnabled: Bool = true,
        epyxFastLoadCyclesSinceDischarge: Int = 0,
        warpSpeedROMVisible: Bool = true,
        easyFlashBootJumperEnabled: Bool = true,
        easyFlashMemoryMode: EasyFlashMemoryMode = .ultimax,
        easyFlashRAM: [UInt8] = [UInt8](repeating: 0, count: 0x100)
    ) {
        self.name = name
        self.hardwareType = hardwareType
        self.exromLineHigh = exromLineHigh
        self.gameLineHigh = gameLineHigh
        self.mappingMode = mappingMode
        self.chips = chips
        self.roml = roml
        self.romh = romh
        self.finalCartridgePlusKernalROM = finalCartridgePlusKernalROM
        self.romlBanks = romlBanks
        self.romhBanks = romhBanks
        self.activeBank = activeBank
        self.cartridgeDisabled = cartridgeDisabled
        self.actionReplayRAMEnabled = actionReplayRAMEnabled
        self.actionReplayRAM = Array(actionReplayRAM.prefix(0x2000))
        if self.actionReplayRAM.count < 0x2000 {
            self.actionReplayRAM.append(contentsOf: [UInt8](repeating: 0, count: 0x2000 - self.actionReplayRAM.count))
        }
        self.actionReplay3ROMVisible = actionReplay3ROMVisible
        self.actionReplay4ROMVisible = actionReplay4ROMVisible
        self.finalCartridgeIROMVisible = finalCartridgeIROMVisible
        self.finalCartridgePlusEnabled = finalCartridgePlusEnabled
        self.finalCartridgePlusLowROMVisible = finalCartridgePlusLowROMVisible
        self.finalCartridgePlusKernalROMVisible = finalCartridgePlusKernalROMVisible
        self.finalCartridgePlusControlBit7 = finalCartridgePlusControlBit7
        self.finalCartridgeIIIRegisterHidden = finalCartridgeIIIRegisterHidden
        self.finalCartridgeIIIROMLVisible = finalCartridgeIIIROMLVisible
        self.finalCartridgeIIIROMHVisible = finalCartridgeIIIROMHVisible
        self.finalCartridgeIIINMILineActive = finalCartridgeIIINMILineActive
        self.simonsBasicUpperROMEnabled = simonsBasicUpperROMEnabled
        self.epyxFastLoadROMEnabled = epyxFastLoadROMEnabled
        self.epyxFastLoadCyclesSinceDischarge = epyxFastLoadCyclesSinceDischarge
        self.warpSpeedROMVisible = warpSpeedROMVisible
        self.easyFlashBootJumperEnabled = easyFlashBootJumperEnabled
        self.easyFlashMemoryMode = easyFlashMemoryMode
        self.easyFlashRAM = Array(easyFlashRAM.prefix(0x100))
        if self.easyFlashRAM.count < 0x100 {
            self.easyFlashRAM.append(contentsOf: [UInt8](repeating: 0, count: 0x100 - self.easyFlashRAM.count))
        }
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
        if hardwareType == 1 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .actionReplay
        } else if hardwareType == 35 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .actionReplay3
        } else if hardwareType == 30 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .actionReplay4
        } else if hardwareType == 13 {
            guard !exromLineHigh && !gameLineHigh else { return nil }
            mode = .finalCartridgeI
        } else if hardwareType == 29 {
            guard exromLineHigh && !gameLineHigh else { return nil }
            mode = .finalCartridgePlus
        } else if hardwareType == 14 {
            guard exromLineHigh && !gameLineHigh else { return nil }
            mode = .magicFormel
        } else if hardwareType == 3 {
            guard exromLineHigh && gameLineHigh else { return nil }
            mode = .finalCartridgeIII
        } else if hardwareType == 4 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .simonsBasic
        } else if hardwareType == 5 {
            guard !exromLineHigh && !gameLineHigh else { return nil }
            mode = .ocean
        } else if hardwareType == 7 {
            guard !exromLineHigh && !gameLineHigh else { return nil }
            mode = .funPlay
        } else if hardwareType == 10 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .epyxFastLoad
        } else if hardwareType == 15 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .c64GameSystem
        } else if hardwareType == 16 {
            guard !exromLineHigh && !gameLineHigh else { return nil }
            mode = .warpSpeed
        } else if hardwareType == 19 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .magicDesk
        } else if hardwareType == 32 {
            mode = .easyFlash
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
        var finalCartridgePlusKernalROM: [UInt8]?
        var romlBanks: [UInt16: [UInt8]] = [:]
        var romhBanks: [UInt16: [UInt8]] = [:]
        var hasROML = false
        var hasROMH = false

        if mode == .finalCartridgeI {
            guard chips.count == 1, let chip = chips.first,
                  chip.bank == 0, chip.loadAddress == 0x8000, chip.data.count == 0x4000
            else {
                return nil
            }
            roml = Array(chip.data.prefix(0x2000))
            romh = Array(chip.data.dropFirst(0x2000).prefix(0x2000))
            hasROML = true
            hasROMH = true
        } else if mode == .finalCartridgePlus {
            guard chips.count == 1, let chip = chips.first,
                  chip.bank == 0, chip.loadAddress == 0x0000, chip.data.count == 0x8000
            else {
                return nil
            }
            finalCartridgePlusKernalROM = Array(chip.data[0x2000..<0x4000])
            roml = Array(chip.data[0x4000..<0x6000])
            romh = Array(chip.data[0x6000..<0x8000])
            hasROML = true
            hasROMH = true
        } else if mode == .magicFormel {
            for chip in chips {
                guard chip.bank < 8, chip.loadAddress == 0xE000, chip.data.count == 0x2000 else {
                    return nil
                }
                romhBanks[chip.bank] = chip.data
            }
            hasROMH = !romhBanks.isEmpty
            romh = romhBanks[0] ?? romh
        } else if mode == .actionReplay || mode == .actionReplay3 || mode == .actionReplay4 {
            for chip in chips {
                let maximumBanks: UInt16 = mode == .actionReplay3 ? 2 : 4
                guard chip.bank < maximumBanks, chip.loadAddress == 0x8000, chip.data.count == 0x2000 else {
                    return nil
                }
                romlBanks[chip.bank] = chip.data
            }
            hasROML = !romlBanks.isEmpty
            roml = romlBanks[0] ?? roml
        } else if mode == .finalCartridgeIII {
            for chip in chips {
                guard chip.bank < 4, chip.loadAddress == 0x8000, chip.data.count == 0x4000 else {
                    return nil
                }
                romlBanks[chip.bank] = chip.data
            }
            hasROML = !romlBanks.isEmpty
            hasROMH = !romlBanks.isEmpty
            roml = Array((romlBanks[0] ?? roml).prefix(0x2000))
            romh = Array((romlBanks[0] ?? romh).dropFirst(0x2000).prefix(0x2000))
        } else if mode == .c64GameSystem {
            for chip in chips {
                guard chip.bank < 64, chip.loadAddress == 0x8000, chip.data.count == 0x2000 else {
                    return nil
                }
                romlBanks[chip.bank] = chip.data
            }
            hasROML = !romlBanks.isEmpty
            roml = romlBanks[0] ?? roml
        } else if mode == .warpSpeed {
            guard chips.count == 1, let chip = chips.first,
                  chip.bank == 0, chip.loadAddress == 0x8000, chip.data.count == 0x4000
            else {
                return nil
            }
            roml = Array(chip.data.prefix(0x2000))
            romh = Array(chip.data.dropFirst(0x2000).prefix(0x2000))
            hasROML = true
            hasROMH = true
        } else if mode == .magicDesk || mode == .ocean || mode == .funPlay || mode == .easyFlash {
            for chip in chips {
                if mode == .easyFlash {
                    guard chip.bank < 64 else { return nil }
                }
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
                    guard mode == .ocean || mode == .easyFlash else { return nil }
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
        } else if mode == .finalCartridgeI {
            guard hasROML, hasROMH else { return nil }
        } else if mode == .finalCartridgePlus {
            guard hasROML, hasROMH, finalCartridgePlusKernalROM != nil else { return nil }
        } else if mode == .magicFormel {
            guard romhBanks.keys.sorted() == Array(UInt16(0)...UInt16(7)) else { return nil }
        } else if mode == .actionReplay3 {
            guard romlBanks.keys.sorted() == [0, 1] else { return nil }
        } else if mode == .actionReplay || mode == .actionReplay4 {
            guard romlBanks.keys.sorted() == [0, 1, 2, 3] else { return nil }
        } else if mode == .finalCartridgeIII {
            guard romlBanks.keys.sorted() == [0, 1, 2, 3] else { return nil }
        } else if mode == .c64GameSystem {
            guard romlBanks.keys.sorted() == Array(UInt16(0)...UInt16(63)) else { return nil }
        } else if mode == .warpSpeed {
            guard hasROML, hasROMH else { return nil }
        } else if mode != .magicDesk && mode != .ocean && mode != .funPlay && mode != .easyFlash {
            guard hasROML || hasROMH else { return nil }
            if mode == .normal8K {
                guard hasROML else { return nil }
            } else if mode == .epyxFastLoad {
                guard hasROML, !hasROMH else { return nil }
            } else {
                guard hasROML && hasROMH else { return nil }
            }
        } else if mode == .magicDesk {
            guard hasROML, !hasROMH else { return nil }
        } else if mode == .funPlay {
            guard hasROML, !hasROMH else { return nil }
        } else if mode == .easyFlash {
            guard hasROML || hasROMH else { return nil }
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
            finalCartridgePlusKernalROM: finalCartridgePlusKernalROM,
            romlBanks: romlBanks,
            romhBanks: romhBanks
        )
    }

    public var usesUltimaxMemoryMap: Bool {
        mappingMode == .ultimax || (mappingMode == .easyFlash && easyFlashMemoryMode == .ultimax)
    }

    public var nmiLineActive: Bool {
        mappingMode == .finalCartridgeIII && finalCartridgeIIINMILineActive
    }

    public func read(_ address: UInt16) -> UInt8? {
        let addr = Int(address)
        switch (mappingMode, addr) {
        case (.actionReplay, 0x8000...0x9FFF):
            guard !cartridgeDisabled else { return nil }
            if actionReplayRAMEnabled {
                return actionReplayRAM[addr - 0x8000]
            }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.actionReplay3, 0x8000...0x9FFF):
            guard !cartridgeDisabled, actionReplay3ROMVisible else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.actionReplay3, 0xA000...0xBFFF):
            guard !cartridgeDisabled, actionReplay3ROMVisible else { return nil }
            return romlBanks[activeBank]?[addr - 0xA000]
        case (.actionReplay4, 0x8000...0x9FFF):
            guard !cartridgeDisabled, actionReplay4ROMVisible else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.finalCartridgeI, 0x8000...0x9FFF):
            guard finalCartridgeIROMVisible else { return nil }
            return roml?[addr - 0x8000]
        case (.finalCartridgeI, 0xA000...0xBFFF):
            guard finalCartridgeIROMVisible else { return nil }
            return romh?[addr - 0xA000]
        case (.finalCartridgePlus, 0x8000...0x9FFF):
            guard finalCartridgePlusEnabled, finalCartridgePlusLowROMVisible else { return nil }
            return roml?[addr - 0x8000]
        case (.finalCartridgePlus, 0xA000...0xBFFF):
            guard finalCartridgePlusEnabled, finalCartridgePlusLowROMVisible else { return nil }
            return romh?[addr - 0xA000]
        case (.finalCartridgePlus, 0xE000...0xFFFF):
            guard finalCartridgePlusEnabled, finalCartridgePlusKernalROMVisible else { return nil }
            return finalCartridgePlusKernalROM?[addr - 0xE000]
        case (.magicFormel, 0xE000...0xFFFF):
            guard !cartridgeDisabled else { return nil }
            return romhBanks[activeBank]?[addr - 0xE000]
        case (.finalCartridgeIII, 0x8000...0x9FFF):
            guard finalCartridgeIIIROMLVisible else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.finalCartridgeIII, 0xA000...0xBFFF):
            guard finalCartridgeIIIROMHVisible else { return nil }
            return romlBanks[activeBank]?[0x2000 + (addr - 0xA000)]
        case (.magicDesk, 0x8000...0x9FFF), (.ocean, 0x8000...0x9FFF), (.funPlay, 0x8000...0x9FFF):
            guard !cartridgeDisabled else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.epyxFastLoad, 0x8000...0x9FFF):
            guard epyxFastLoadROMEnabled else { return nil }
            return roml?[addr - 0x8000]
        case (.c64GameSystem, 0x8000...0x9FFF):
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.warpSpeed, 0x8000...0x9FFF):
            guard warpSpeedROMVisible else { return nil }
            return roml?[addr - 0x8000]
        case (.warpSpeed, 0xA000...0xBFFF):
            guard warpSpeedROMVisible else { return nil }
            return romh?[addr - 0xA000]
        case (.ocean, 0xA000...0xBFFF):
            return romhBanks[activeBank]?[addr - 0xA000]
        case (.easyFlash, 0x8000...0x9FFF):
            guard easyFlashMemoryMode != .off else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.easyFlash, 0xA000...0xBFFF):
            guard easyFlashMemoryMode == .sixteenK else { return nil }
            return romhBanks[activeBank]?[addr - 0xA000]
        case (.easyFlash, 0xE000...0xFFFF):
            guard easyFlashMemoryMode == .ultimax else { return nil }
            return romhBanks[activeBank]?[addr - 0xE000]
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

    public mutating func readIO(_ address: UInt16) -> UInt8? {
        let addr = Int(address)
        switch (mappingMode, addr) {
        case (.actionReplay, 0xDF00...0xDFFF):
            guard !cartridgeDisabled else { return nil }
            if actionReplayRAMEnabled {
                return actionReplayRAM[0x1F00 + (addr - 0xDF00)]
            }
            return romlBanks[activeBank]?[0x1F00 + (addr - 0xDF00)]
        case (.actionReplay4, 0xDF00...0xDFFF):
            guard !cartridgeDisabled, actionReplay4ROMVisible else { return nil }
            return romlBanks[activeBank]?[addr - 0xDF00]
        case (.finalCartridgeI, 0xDE00...0xDEFF):
            let value = finalCartridgeIROMVisible ? romh?[0x1E00 + (addr - 0xDE00)] : nil
            finalCartridgeIROMVisible = false
            return value
        case (.finalCartridgeI, 0xDF00...0xDFFF):
            finalCartridgeIROMVisible = true
            return romh?[0x1F00 + (addr - 0xDF00)]
        case (.finalCartridgePlus, 0xDF00...0xDFFF):
            guard finalCartridgePlusEnabled else { return nil }
            return finalCartridgePlusControlBit7 ? 0x80 : 0x00
        case (.finalCartridgeIII, 0xDE00...0xDFFF):
            return romlBanks[activeBank]?[0x3E00 + (addr - 0xDE00)]
        case (.epyxFastLoad, 0xDE00...0xDEFF):
            dischargeEpyxFastLoadCapacitor()
            return nil
        case (.epyxFastLoad, 0xDF00...0xDFFF):
            return roml?[0x1F00 + ((addr - 0xDF00) & 0xFF)]
        case (.c64GameSystem, 0xDE00...0xDE3F):
            activeBank = UInt16(addr - 0xDE00)
            return nil
        case (.warpSpeed, 0xDE00...0xDEFF):
            return roml?[0x1E00 + (addr - 0xDE00)]
        case (.warpSpeed, 0xDF00...0xDFFF):
            return roml?[0x1F00 + (addr - 0xDF00)]
        case (.easyFlash, 0xDF00...0xDFFF):
            return easyFlashRAM[addr - 0xDF00]
        default:
            return nil
        }
    }

    public mutating func observeRead(_ address: UInt16) {
        guard mappingMode == .epyxFastLoad, (0x8000...0x9FFF).contains(address) else { return }
        dischargeEpyxFastLoadCapacitor()
    }

    @discardableResult
    public mutating func write(_ address: UInt16, value: UInt8) -> Bool {
        let addr = Int(address)
        guard mappingMode == .actionReplay,
              actionReplayRAMEnabled,
              !cartridgeDisabled,
              (0x8000...0x9FFF).contains(addr)
        else {
            return false
        }
        actionReplayRAM[addr - 0x8000] = value
        return true
    }

    public mutating func writeIO1(_ address: UInt16, value: UInt8) {
        guard (0xDE00...0xDEFF).contains(address) else { return }
        switch mappingMode {
        case .actionReplay:
            activeBank = UInt16((value >> 3) & 0x03)
            cartridgeDisabled = value & 0x04 != 0
            actionReplayRAMEnabled = value & 0x20 != 0
        case .actionReplay3:
            activeBank = UInt16(value & 0x01)
            cartridgeDisabled = value & 0x04 != 0
            actionReplay3ROMVisible = value & 0x08 != 0
        case .actionReplay4:
            guard !cartridgeDisabled else { return }
            activeBank = UInt16((value & 0x01) | ((value & 0x10) >> 3))
            actionReplay4ROMVisible = value & 0x08 != 0
            if value & 0x04 != 0 {
                cartridgeDisabled = true
                actionReplay4ROMVisible = false
            }
        case .finalCartridgeI:
            finalCartridgeIROMVisible = false
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
        case .c64GameSystem:
            guard address <= 0xDE3F else { break }
            activeBank = UInt16(address - 0xDE00)
        case .warpSpeed:
            warpSpeedROMVisible = true
        case .easyFlash:
            switch address & 0x00FF {
            case 0x00:
                activeBank = UInt16(value & 0x3F)
            case 0x02:
                applyEasyFlashControl(value)
            default:
                break
            }
        default:
            break
        }
    }

    public mutating func writeIO2(_ address: UInt16, value: UInt8) {
        if mappingMode == .actionReplay, (0xDF00...0xDFFF).contains(address), actionReplayRAMEnabled {
            actionReplayRAM[0x1F00 + Int(address - 0xDF00)] = value
            return
        }
        if mappingMode == .finalCartridgeI, (0xDF00...0xDFFF).contains(address) {
            finalCartridgeIROMVisible = true
            return
        }
        if mappingMode == .finalCartridgePlus, (0xDF00...0xDFFF).contains(address) {
            finalCartridgePlusControlBit7 = value & 0x80 != 0
            finalCartridgePlusEnabled = value & 0x10 != 0
            finalCartridgePlusKernalROMVisible = value & 0x20 != 0
            finalCartridgePlusLowROMVisible = value & 0x40 == 0
            return
        }
        if mappingMode == .warpSpeed, (0xDF00...0xDFFF).contains(address) {
            warpSpeedROMVisible = false
            return
        }
        if mappingMode == .magicFormel, (0xDF00...0xDFFF).contains(address) {
            if address == 0xDF00, value == 0xFF {
                cartridgeDisabled = true
            } else if (0xDF00...0xDF07).contains(address) {
                activeBank = UInt16(address - 0xDF00)
                cartridgeDisabled = false
            }
            return
        }
        if mappingMode == .finalCartridgeIII, address == 0xDFFF, !finalCartridgeIIIRegisterHidden {
            activeBank = UInt16(value & 0x03)
            finalCartridgeIIIRegisterHidden = value & 0x80 != 0
            finalCartridgeIIINMILineActive = value & 0x40 == 0
            finalCartridgeIIIROMLVisible = value & 0x10 == 0
            finalCartridgeIIIROMHVisible = finalCartridgeIIIROMLVisible && value & 0x20 == 0
            return
        }
        guard mappingMode == .easyFlash, (0xDF00...0xDFFF).contains(address) else { return }
        easyFlashRAM[Int(address - 0xDF00)] = value
    }

    public mutating func reset() {
        activeBank = 0
        cartridgeDisabled = false
        actionReplayRAMEnabled = false
        actionReplay3ROMVisible = true
        actionReplay4ROMVisible = true
        finalCartridgeIROMVisible = true
        finalCartridgePlusEnabled = true
        finalCartridgePlusLowROMVisible = true
        finalCartridgePlusKernalROMVisible = true
        finalCartridgePlusControlBit7 = false
        finalCartridgeIIIRegisterHidden = false
        finalCartridgeIIIROMLVisible = true
        finalCartridgeIIIROMHVisible = true
        finalCartridgeIIINMILineActive = false
        simonsBasicUpperROMEnabled = false
        epyxFastLoadROMEnabled = true
        epyxFastLoadCyclesSinceDischarge = 0
        warpSpeedROMVisible = true
        if mappingMode == .easyFlash {
            easyFlashMemoryMode = .ultimax
        }
    }

    public mutating func tick(cycles: Int = 1) {
        guard mappingMode == .epyxFastLoad, epyxFastLoadROMEnabled, cycles > 0 else { return }
        epyxFastLoadCyclesSinceDischarge += cycles
        if epyxFastLoadCyclesSinceDischarge >= Self.epyxFastLoadDisableCycles {
            epyxFastLoadROMEnabled = false
        }
    }

    private mutating func applyEasyFlashControl(_ value: UInt8) {
        switch value & 0x07 {
        case 0b000:
            easyFlashMemoryMode = easyFlashBootJumperEnabled ? .ultimax : .off
        case 0b010:
            easyFlashMemoryMode = easyFlashBootJumperEnabled ? .sixteenK : .eightK
        case 0b100:
            easyFlashMemoryMode = .off
        case 0b101:
            easyFlashMemoryMode = .ultimax
        case 0b110:
            easyFlashMemoryMode = .eightK
        case 0b111:
            easyFlashMemoryMode = .sixteenK
        default:
            break
        }
    }

    private mutating func dischargeEpyxFastLoadCapacitor() {
        epyxFastLoadROMEnabled = true
        epyxFastLoadCyclesSinceDischarge = 0
    }

    private static func copy(_ data: [UInt8], into destination: inout [UInt8], at offset: Int) -> Bool {
        guard offset >= 0, offset + data.count <= destination.count else { return false }
        destination.replaceSubrange(offset..<(offset + data.count), with: data)
        return true
    }

    private static let supportedHardwareTypes: Set<UInt16> = [
        0,  // Normal cartridge
        1,  // Action Replay
        3,  // Final Cartridge III
        4,  // Simon's BASIC
        5,  // Ocean type 1
        7,  // Fun Play / Power Play
        10, // Epyx FastLoad
        11, // Westermann Learning, normal 16K mapping
        12, // Rex Utility, normal 8K mapping
        13, // Final Cartridge I
        14, // Magic Formel
        15, // C64 Game System / System 3
        16, // Warp Speed
        19, // Magic Desk / Domark / HES Australia
        29, // Final Cartridge Plus
        30, // Action Replay 4
        35, // Action Replay 3
        32  // EasyFlash
    ]

    /// Approximate RC timeout for Epyx FastLoad's capacitor-gated ROM enable.
    /// Reading ROML or IO1 discharges the capacitor and keeps the 8K ROM visible.
    private static let epyxFastLoadDisableCycles = 512

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
