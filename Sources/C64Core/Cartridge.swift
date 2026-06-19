import Foundation

/// C64 cartridge image with enough mapping detail for standard CRT ROMs.
public struct Cartridge: Equatable {
    public enum MappingMode: Equatable {
        case normal8K
        case normal16K
        case ultimax
        case actionReplay
        case kcsPower
        case actionReplay3
        case actionReplay4
        case atomicPower
        case finalCartridgeI
        case finalCartridgePlus
        case finalCartridgeIII
        case simonsBasic
        case epyxFastLoad
        case superGames
        case c64GameSystem
        case dinamic
        case zaxxon
        case superSnapshotV5
        case comal80
        case structuredBasic
        case ross
        case warpSpeed
        case stardos
        case gameKiller
        case prophet64
        case exos
        case freezeFrame
        case freezeMachine
        case snapshot64
        case superExplodeV5
        case mach5
        case magicFormel
        case magicDesk
        case ocean
        case funPlay
        case delaEP64
        case delaEP7x8
        case delaEP256
        case rexEP256
        case mikroAssembler
        case easyFlash
    }

    public enum EasyFlashMemoryMode: Equatable {
        case off
        case ultimax
        case eightK
        case sixteenK
    }

    private enum KCSMemoryMode: Equatable {
        case ram
        case eightK
        case sixteenK
        case ultimax
    }

    private enum AtomicPowerMemoryMode: Equatable {
        case off
        case eightK
        case sixteenK
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
    private let finalCartridgePlusKernalROM: [UInt8]?
    private let romlBanks: [UInt16: [UInt8]]
    private let romhBanks: [UInt16: [UInt8]]
    private var activeBank: UInt16
    private var cartridgeDisabled: Bool
    private var kcsMemoryMode: KCSMemoryMode = .sixteenK
    private var kcsRAM: [UInt8] = [UInt8](repeating: 0, count: 0x80)
    private var atomicPowerActive: Bool = true
    private var atomicPowerMemoryMode: AtomicPowerMemoryMode = .eightK
    private var atomicPowerRAMEnabled: Bool = false
    private var atomicPowerRAMAtA000: Bool = false
    private var atomicPowerRAM: [UInt8] = [UInt8](repeating: 0, count: 0x2000)
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
    private var superGamesWriteProtected: Bool
    private var rexEP256SocketSizes: [UInt16: Int]
    private var rexEP256SocketBankOffsets: [UInt16: UInt16]
    private var stardosCapVoltage: Int
    private var stardosROMLVisible: Bool
    private var gameKillerDisableAccessCount: Int
    private var freezeFrameROMLVisible: Bool
    private var freezeFrameROMHVisible: Bool
    private var freezeMachineUpperROMVisible: Bool
    private var freezeMachineKernalROMVisible: Bool
    private var superExplodeV5ROMEnabled: Bool
    private var superExplodeV5CyclesSinceDischarge: Int
    private var superSnapshotV5RAMEnabled: Bool
    private var superSnapshotV5UltimaxMode: Bool
    private var superSnapshotV5RAM: [UInt8]
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
        superGamesWriteProtected: Bool = false,
        rexEP256SocketSizes: [UInt16: Int] = [:],
        rexEP256SocketBankOffsets: [UInt16: UInt16] = [:],
        stardosCapVoltage: Int = 0,
        stardosROMLVisible: Bool = false,
        gameKillerDisableAccessCount: Int = 0,
        freezeFrameROMLVisible: Bool = true,
        freezeFrameROMHVisible: Bool = false,
        freezeMachineUpperROMVisible: Bool = false,
        freezeMachineKernalROMVisible: Bool = false,
        superExplodeV5ROMEnabled: Bool = true,
        superExplodeV5CyclesSinceDischarge: Int = 0,
        superSnapshotV5RAMEnabled: Bool = false,
        superSnapshotV5UltimaxMode: Bool = true,
        superSnapshotV5RAM: [UInt8] = [UInt8](repeating: 0, count: 0x8000),
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
        self.superGamesWriteProtected = superGamesWriteProtected
        self.rexEP256SocketSizes = rexEP256SocketSizes
        self.rexEP256SocketBankOffsets = rexEP256SocketBankOffsets
        self.stardosCapVoltage = stardosCapVoltage
        self.stardosROMLVisible = stardosROMLVisible
        self.gameKillerDisableAccessCount = gameKillerDisableAccessCount
        self.freezeFrameROMLVisible = freezeFrameROMLVisible
        self.freezeFrameROMHVisible = freezeFrameROMHVisible
        self.freezeMachineUpperROMVisible = freezeMachineUpperROMVisible
        self.freezeMachineKernalROMVisible = freezeMachineKernalROMVisible
        self.superExplodeV5ROMEnabled = superExplodeV5ROMEnabled
        self.superExplodeV5CyclesSinceDischarge = superExplodeV5CyclesSinceDischarge
        self.superSnapshotV5RAMEnabled = superSnapshotV5RAMEnabled
        self.superSnapshotV5UltimaxMode = superSnapshotV5UltimaxMode
        self.superSnapshotV5RAM = Array(superSnapshotV5RAM.prefix(0x8000))
        if self.superSnapshotV5RAM.count < 0x8000 {
            self.superSnapshotV5RAM.append(contentsOf: [UInt8](repeating: 0, count: 0x8000 - self.superSnapshotV5RAM.count))
        }
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
        } else if hardwareType == 2 {
            guard !exromLineHigh && !gameLineHigh else { return nil }
            mode = .kcsPower
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
        } else if hardwareType == 8 {
            guard !exromLineHigh && !gameLineHigh else { return nil }
            mode = .superGames
        } else if hardwareType == 9 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .atomicPower
        } else if hardwareType == 10 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .epyxFastLoad
        } else if hardwareType == 15 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .c64GameSystem
        } else if hardwareType == 16 {
            guard !exromLineHigh && !gameLineHigh else { return nil }
            mode = .warpSpeed
        } else if hardwareType == 17 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .dinamic
        } else if hardwareType == 18 {
            guard !exromLineHigh && !gameLineHigh else { return nil }
            mode = .zaxxon
        } else if hardwareType == 20 {
            guard exromLineHigh && !gameLineHigh else { return nil }
            mode = .superSnapshotV5
        } else if hardwareType == 21 {
            guard !exromLineHigh && !gameLineHigh else { return nil }
            mode = .comal80
        } else if hardwareType == 19 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .magicDesk
        } else if hardwareType == 22 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .structuredBasic
        } else if hardwareType == 23 {
            guard !exromLineHigh && !gameLineHigh else { return nil }
            mode = .ross
        } else if hardwareType == 24 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .delaEP64
        } else if hardwareType == 25 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .delaEP7x8
        } else if hardwareType == 26 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .delaEP256
        } else if hardwareType == 27 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .rexEP256
        } else if hardwareType == 28 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .mikroAssembler
        } else if hardwareType == 31 {
            guard exromLineHigh && !gameLineHigh else { return nil }
            mode = .stardos
        } else if hardwareType == 32 {
            mode = .easyFlash
        } else if hardwareType == 42 {
            guard exromLineHigh && !gameLineHigh else { return nil }
            mode = .gameKiller
        } else if hardwareType == 43 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .prophet64
        } else if hardwareType == 44 {
            guard exromLineHigh && !gameLineHigh else { return nil }
            mode = .exos
        } else if hardwareType == 45 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .freezeFrame
        } else if hardwareType == 46 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .freezeMachine
        } else if hardwareType == 47 {
            guard exromLineHigh && !gameLineHigh else { return nil }
            mode = .snapshot64
        } else if hardwareType == 48 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .superExplodeV5
        } else if hardwareType == 51 {
            guard !exromLineHigh && gameLineHigh else { return nil }
            mode = .mach5
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
        var rexEP256SocketSizes: [UInt16: Int] = [:]
        var rexEP256SocketBankOffsets: [UInt16: UInt16] = [:]
        var hasROML = false
        var hasROMH = false

        if mode == .kcsPower {
            guard chips.count == 2,
                  let low = chips.first(where: { $0.bank == 0 && $0.loadAddress == 0x8000 && $0.data.count == 0x2000 }),
                  let high = chips.first(where: { $0.bank == 0 && $0.loadAddress == 0xA000 && $0.data.count == 0x2000 })
            else {
                return nil
            }
            roml = low.data
            romh = high.data
            hasROML = true
            hasROMH = true
        } else if mode == .finalCartridgeI {
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
        } else if mode == .superGames {
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
        } else if mode == .atomicPower {
            for chip in chips {
                guard chip.bank < 4, chip.loadAddress == 0x8000, chip.data.count == 0x2000,
                      Self.insertROMBank(chip.data, bank: chip.bank, into: &romlBanks)
                else {
                    return nil
                }
                romhBanks[chip.bank] = chip.data
            }
            hasROML = !romlBanks.isEmpty
            hasROMH = !romhBanks.isEmpty
            roml = romlBanks[0] ?? roml
            romh = romhBanks[0] ?? romh
        } else if mode == .c64GameSystem {
            for chip in chips {
                guard chip.bank < 64, chip.loadAddress == 0x8000, chip.data.count == 0x2000 else {
                    return nil
                }
                romlBanks[chip.bank] = chip.data
            }
            hasROML = !romlBanks.isEmpty
            roml = romlBanks[0] ?? roml
        } else if mode == .dinamic {
            for chip in chips {
                guard chip.bank < 16, chip.loadAddress == 0x8000, chip.data.count == 0x2000 else {
                    return nil
                }
                romlBanks[chip.bank] = chip.data
            }
            hasROML = !romlBanks.isEmpty
            roml = romlBanks[0] ?? roml
        } else if mode == .zaxxon {
            guard chips.count == 3,
                  let fixed = chips.first(where: { $0.bank == 0 && $0.loadAddress == 0x8000 && $0.data.count == 0x1000 }),
                  let high0 = chips.first(where: { $0.bank == 0 && $0.loadAddress == 0xA000 && $0.data.count == 0x2000 }),
                  let high1 = chips.first(where: { $0.bank == 1 && $0.loadAddress == 0xA000 && $0.data.count == 0x2000 })
            else {
                return nil
            }
            roml = fixed.data + fixed.data
            romhBanks[0] = high0.data
            romhBanks[1] = high1.data
            hasROML = true
            hasROMH = true
        } else if mode == .superSnapshotV5 {
            for chip in chips {
                guard chip.bank < 8, chip.loadAddress == 0x8000, chip.data.count == 0x4000,
                      romlBanks[chip.bank] == nil,
                      romhBanks[chip.bank] == nil
                else {
                    return nil
                }
                romlBanks[chip.bank] = Array(chip.data.prefix(0x2000))
                romhBanks[chip.bank] = Array(chip.data.dropFirst(0x2000).prefix(0x2000))
            }
            hasROML = !romlBanks.isEmpty
            hasROMH = !romhBanks.isEmpty
            roml = romlBanks[0] ?? roml
            romh = romhBanks[0] ?? romh
        } else if mode == .comal80 {
            for chip in chips {
                guard chip.bank < 8, chip.loadAddress == 0x8000, chip.data.count == 0x4000 else {
                    return nil
                }
                guard romlBanks[chip.bank] == nil else { return nil }
                romlBanks[chip.bank] = chip.data
            }
            hasROML = !romlBanks.isEmpty
            hasROMH = !romlBanks.isEmpty
            roml = Array((romlBanks[0] ?? roml).prefix(0x2000))
            romh = Array((romlBanks[0] ?? romh).dropFirst(0x2000).prefix(0x2000))
        } else if mode == .structuredBasic {
            for chip in chips {
                guard chip.bank < 2, chip.loadAddress == 0x8000, chip.data.count == 0x2000 else {
                    return nil
                }
                romlBanks[chip.bank] = chip.data
            }
            hasROML = !romlBanks.isEmpty
            roml = romlBanks[0] ?? roml
        } else if mode == .ross {
            for chip in chips {
                guard chip.bank < 2, chip.loadAddress == 0x8000, chip.data.count == 0x4000 else {
                    return nil
                }
                romlBanks[chip.bank] = chip.data
            }
            hasROML = !romlBanks.isEmpty
            hasROMH = !romlBanks.isEmpty
            roml = Array((romlBanks[0] ?? roml).prefix(0x2000))
            romh = Array((romlBanks[0] ?? romh).dropFirst(0x2000).prefix(0x2000))
        } else if mode == .delaEP64 {
            for chip in chips {
                guard chip.loadAddress == 0x8000 else { return nil }
                if chip.data.count == 0x2000 {
                    guard chip.bank < 9, Self.insertROMBank(chip.data, bank: chip.bank, into: &romlBanks) else {
                        return nil
                    }
                } else if chip.data.count == 0x8000 {
                    guard chip.bank == 1 || chip.bank == 2 else { return nil }
                    let firstBank = (chip.bank - 1) * 4 + 1
                    for index in 0..<4 {
                        let start = index * 0x2000
                        let data = Array(chip.data[start..<(start + 0x2000)])
                        guard Self.insertROMBank(data, bank: firstBank + UInt16(index), into: &romlBanks) else {
                            return nil
                        }
                    }
                } else {
                    return nil
                }
            }
            hasROML = !romlBanks.isEmpty
            roml = romlBanks[0] ?? roml
        } else if mode == .delaEP7x8 {
            for chip in chips {
                guard chip.bank < 8, chip.loadAddress == 0x8000,
                      Self.insertROMBank(chip.data, bank: chip.bank, into: &romlBanks)
                else {
                    return nil
                }
            }
            hasROML = !romlBanks.isEmpty
            roml = romlBanks[0] ?? roml
        } else if mode == .delaEP256 {
            for chip in chips {
                guard chip.bank < 33, chip.loadAddress == 0x8000,
                      Self.insertROMBank(chip.data, bank: chip.bank, into: &romlBanks)
                else {
                    return nil
                }
            }
            hasROML = !romlBanks.isEmpty
            roml = romlBanks[0] ?? roml
        } else if mode == .rexEP256 {
            guard let base = chips.first,
                  base.bank == 0,
                  base.loadAddress == 0x8000,
                  base.data.count == 0x2000,
                  Self.insertROMBank(base.data, bank: 0, into: &romlBanks)
            else {
                return nil
            }

            var nextBank: UInt16 = 1
            for chip in chips.dropFirst() {
                guard (1...8).contains(chip.bank),
                      chip.loadAddress == 0x8000,
                      [0x2000, 0x4000, 0x8000].contains(chip.data.count)
                else {
                    return nil
                }
                let socket = chip.bank - 1
                guard rexEP256SocketSizes[socket] == nil else { return nil }
                rexEP256SocketSizes[socket] = chip.data.count
                rexEP256SocketBankOffsets[socket] = nextBank - 1
                for index in 0..<(chip.data.count / 0x2000) {
                    let start = index * 0x2000
                    let data = Array(chip.data[start..<(start + 0x2000)])
                    guard Self.insertROMBank(data, bank: nextBank, into: &romlBanks) else {
                        return nil
                    }
                    nextBank += 1
                }
            }
            hasROML = true
            roml = base.data
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
        } else if mode == .mikroAssembler {
            guard chips.count == 1, let chip = chips.first,
                  chip.bank == 0, chip.loadAddress == 0x8000, chip.data.count == 0x2000
            else {
                return nil
            }
            roml = chip.data
            hasROML = true
        } else if mode == .stardos {
            guard chips.count == 2,
                  let low = chips.first(where: { $0.bank == 0 && $0.loadAddress == 0x8000 && $0.data.count == 0x2000 }),
                  let high = chips.first(where: { $0.bank == 0 && $0.loadAddress == 0xE000 && $0.data.count == 0x2000 })
            else {
                return nil
            }
            roml = low.data
            romh = high.data
            hasROML = true
            hasROMH = true
        } else if mode == .gameKiller {
            guard chips.count == 1, let chip = chips.first,
                  chip.bank == 0, chip.loadAddress == 0xE000, chip.data.count == 0x2000
            else {
                return nil
            }
            romh = chip.data
            hasROMH = true
        } else if mode == .prophet64 {
            for chip in chips {
                guard chip.bank < 32, chip.loadAddress == 0x8000,
                      Self.insertROMBank(chip.data, bank: chip.bank, into: &romlBanks)
                else {
                    return nil
                }
            }
            hasROML = !romlBanks.isEmpty
            roml = romlBanks[0] ?? romlBanks[romlBanks.keys.min() ?? 0] ?? roml
        } else if mode == .exos {
            guard chips.count == 1, let chip = chips.first,
                  chip.bank == 0, chip.loadAddress == 0xE000, chip.data.count == 0x2000
            else {
                return nil
            }
            romh = chip.data
            hasROMH = true
        } else if mode == .freezeFrame {
            guard chips.count == 1, let chip = chips.first,
                  chip.bank == 0, chip.loadAddress == 0x8000, chip.data.count == 0x2000
            else {
                return nil
            }
            roml = chip.data
            hasROML = true
        } else if mode == .freezeMachine {
            let usesVeryOldSplitFormat = chips.allSatisfy { chip in
                chip.data.count == 0x2000 && chip.loadAddress == 0x8000
            } && (chips.count == 2 || chips.count == 4)
                && chips.map(\.bank).sorted() == Array(UInt16(0)..<UInt16(chips.count))

            for chip in chips {
                if chip.data.count == 0x4000 {
                    guard chip.bank < 2, chip.loadAddress == 0x8000,
                          romlBanks[chip.bank] == nil,
                          romhBanks[chip.bank] == nil
                    else {
                        return nil
                    }
                    romlBanks[chip.bank] = Array(chip.data.prefix(0x2000))
                    romhBanks[chip.bank] = Array(chip.data.dropFirst(0x2000).prefix(0x2000))
                } else if chip.data.count == 0x2000, chip.loadAddress == 0x8000, chip.bank < 4 {
                    let bank = usesVeryOldSplitFormat ? chip.bank / 2 : chip.bank
                    guard bank < 2 else { return nil }
                    if usesVeryOldSplitFormat && chip.bank % 2 == 1 {
                        guard romhBanks[bank] == nil else { return nil }
                        romhBanks[bank] = chip.data
                    } else {
                        guard romlBanks[bank] == nil else { return nil }
                        romlBanks[bank] = chip.data
                    }
                } else if chip.data.count == 0x2000, chip.loadAddress == 0xA000, chip.bank < 2 {
                    guard romhBanks[chip.bank] == nil else { return nil }
                    romhBanks[chip.bank] = chip.data
                } else {
                    return nil
                }
            }
            hasROML = !romlBanks.isEmpty
            hasROMH = !romhBanks.isEmpty
            roml = romlBanks[0] ?? roml
            romh = romhBanks[0] ?? romh
        } else if mode == .snapshot64 {
            guard chips.count == 1, let chip = chips.first,
                  chip.bank == 0, chip.data.count == 0x1000
            else {
                return nil
            }
            roml = chip.data
            hasROML = true
        } else if mode == .superExplodeV5 {
            for chip in chips {
                guard chip.bank < 2, chip.loadAddress == 0x8000,
                      Self.insertROMBank(chip.data, bank: chip.bank, into: &romlBanks)
                else {
                    return nil
                }
            }
            hasROML = !romlBanks.isEmpty
            roml = romlBanks[0] ?? roml
        } else if mode == .mach5 {
            guard chips.count == 1, let chip = chips.first,
                  chip.bank == 0, chip.loadAddress == 0x8000,
                  chip.data.count == 0x1000 || chip.data.count == 0x2000
            else {
                return nil
            }
            if chip.data.count == 0x1000 {
                roml = chip.data + chip.data
            } else {
                roml = chip.data
            }
            hasROML = true
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

        if mode == .kcsPower {
            guard hasROML, hasROMH else { return nil }
        } else if mode == .simonsBasic {
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
        } else if mode == .superGames {
            guard romlBanks.keys.sorted() == [0, 1, 2, 3] else { return nil }
        } else if mode == .atomicPower {
            guard romlBanks.keys.sorted() == [0, 1, 2, 3],
                  romhBanks.keys.sorted() == [0, 1, 2, 3]
            else {
                return nil
            }
        } else if mode == .c64GameSystem {
            guard romlBanks.keys.sorted() == Array(UInt16(0)...UInt16(63)) else { return nil }
        } else if mode == .dinamic {
            guard romlBanks.keys.sorted() == Array(UInt16(0)...UInt16(15)) else { return nil }
        } else if mode == .zaxxon {
            guard hasROML, romhBanks.keys.sorted() == [0, 1] else { return nil }
        } else if mode == .superSnapshotV5 {
            let banks = romlBanks.keys.sorted()
            guard (banks == [0, 1, 2, 3] || banks == Array(UInt16(0)...UInt16(7))),
                  romhBanks.keys.sorted() == banks
            else {
                return nil
            }
        } else if mode == .comal80 {
            let banks = romlBanks.keys.sorted()
            guard banks == [0, 1, 2, 3] || banks == Array(UInt16(0)...UInt16(7)) else { return nil }
        } else if mode == .structuredBasic {
            guard romlBanks.keys.sorted() == [0, 1] else { return nil }
        } else if mode == .ross {
            let banks = romlBanks.keys.sorted()
            guard banks == [0] || banks == [0, 1] else { return nil }
        } else if mode == .delaEP64 {
            guard Self.hasContiguousBanksFromZero(romlBanks), (1...9).contains(romlBanks.count) else { return nil }
        } else if mode == .delaEP7x8 {
            guard Self.hasContiguousBanksFromZero(romlBanks), (1...8).contains(romlBanks.count) else { return nil }
        } else if mode == .delaEP256 {
            guard Self.hasContiguousBanksFromZero(romlBanks), (1...33).contains(romlBanks.count) else { return nil }
        } else if mode == .rexEP256 {
            guard Self.hasContiguousBanksFromZero(romlBanks), (1...33).contains(romlBanks.count) else { return nil }
        } else if mode == .warpSpeed {
            guard hasROML, hasROMH else { return nil }
        } else if mode == .mikroAssembler {
            guard hasROML, !hasROMH else { return nil }
        } else if mode == .stardos {
            guard hasROML, hasROMH else { return nil }
        } else if mode == .gameKiller {
            guard !hasROML, hasROMH else { return nil }
        } else if mode == .prophet64 {
            guard hasROML, !hasROMH else { return nil }
        } else if mode == .exos {
            guard !hasROML, hasROMH else { return nil }
        } else if mode == .freezeFrame {
            guard hasROML, !hasROMH else { return nil }
        } else if mode == .freezeMachine {
            let lowerBanks = romlBanks.keys.sorted()
            guard lowerBanks == [0] || lowerBanks == [0, 1],
                  romhBanks.keys.sorted() == lowerBanks
            else {
                return nil
            }
        } else if mode == .snapshot64 {
            guard hasROML, !hasROMH else { return nil }
        } else if mode == .superExplodeV5 {
            guard romlBanks.keys.sorted() == [0, 1], !hasROMH else { return nil }
        } else if mode == .mach5 {
            guard hasROML, !hasROMH else { return nil }
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
            romhBanks: romhBanks,
            cartridgeDisabled: mode == .snapshot64,
            rexEP256SocketSizes: rexEP256SocketSizes,
            rexEP256SocketBankOffsets: rexEP256SocketBankOffsets
        )
    }

    public var usesUltimaxMemoryMap: Bool {
        mappingMode == .ultimax
            || (mappingMode == .kcsPower && kcsMemoryMode == .ultimax)
            || (mappingMode == .atomicPower && atomicPowerActive && atomicPowerMemoryMode == .ultimax)
            || (mappingMode == .easyFlash && easyFlashMemoryMode == .ultimax)
            || (mappingMode == .snapshot64 && !cartridgeDisabled)
            || (mappingMode == .freezeFrame && freezeFrameROMHVisible)
            || (mappingMode == .freezeMachine && freezeMachineKernalROMVisible)
            || (mappingMode == .superSnapshotV5 && superSnapshotV5UltimaxMode)
    }

    public var nmiLineActive: Bool {
        mappingMode == .finalCartridgeIII && finalCartridgeIIINMILineActive
    }

    public var kernalWindowRequiresHIRAM: Bool {
        mappingMode == .exos || mappingMode == .stardos
    }

    public func read(_ address: UInt16) -> UInt8? {
        let addr = Int(address)
        switch (mappingMode, addr) {
        case (.kcsPower, 0x8000...0x9FFF):
            guard kcsMemoryMode != .ram else { return nil }
            return roml?[addr - 0x8000]
        case (.kcsPower, 0xA000...0xBFFF):
            guard kcsMemoryMode == .sixteenK else { return nil }
            return romh?[addr - 0xA000]
        case (.kcsPower, 0xE000...0xFFFF):
            guard kcsMemoryMode == .ultimax else { return nil }
            return romh?[addr - 0xE000]
        case (.actionReplay, 0x8000...0x9FFF):
            guard !cartridgeDisabled else { return nil }
            if actionReplayRAMEnabled {
                return actionReplayRAM[addr - 0x8000]
            }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.atomicPower, 0x8000...0x9FFF):
            guard atomicPowerActive, atomicPowerMemoryMode != .off else { return nil }
            if atomicPowerRAMEnabled {
                return atomicPowerRAM[addr - 0x8000]
            }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.atomicPower, 0xA000...0xBFFF):
            guard atomicPowerActive else { return nil }
            if atomicPowerRAMAtA000 {
                return atomicPowerRAM[addr - 0xA000]
            }
            guard atomicPowerMemoryMode == .sixteenK else { return nil }
            return romhBanks[activeBank]?[addr - 0xA000]
        case (.atomicPower, 0xE000...0xFFFF):
            guard atomicPowerActive, atomicPowerMemoryMode == .ultimax else { return nil }
            return romhBanks[activeBank]?[addr - 0xE000]
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
        case (.superGames, 0x8000...0x9FFF):
            guard !cartridgeDisabled else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.superGames, 0xA000...0xBFFF):
            guard !cartridgeDisabled else { return nil }
            return romlBanks[activeBank]?[0x2000 + (addr - 0xA000)]
        case (.c64GameSystem, 0x8000...0x9FFF):
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.dinamic, 0x8000...0x9FFF):
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.zaxxon, 0x8000...0x9FFF):
            return roml?[addr - 0x8000]
        case (.zaxxon, 0xA000...0xBFFF):
            return romhBanks[activeBank]?[addr - 0xA000]
        case (.superSnapshotV5, 0x8000...0x9FFF):
            if superSnapshotV5RAMEnabled {
                return superSnapshotV5RAM[superSnapshotV5RAMOffset(addr - 0x8000)]
            }
            guard !cartridgeDisabled else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.superSnapshotV5, 0xA000...0xBFFF):
            guard !superSnapshotV5UltimaxMode, !superSnapshotV5RAMEnabled, !cartridgeDisabled else { return nil }
            return romhBanks[activeBank]?[addr - 0xA000]
        case (.superSnapshotV5, 0xE000...0xFFFF):
            guard superSnapshotV5UltimaxMode, !superSnapshotV5RAMEnabled, !cartridgeDisabled else { return nil }
            return romhBanks[activeBank]?[addr - 0xE000]
        case (.comal80, 0x8000...0x9FFF):
            guard !cartridgeDisabled else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000] ?? 0xFF
        case (.comal80, 0xA000...0xBFFF):
            guard !cartridgeDisabled else { return nil }
            return romlBanks[activeBank]?[0x2000 + (addr - 0xA000)] ?? 0xFF
        case (.structuredBasic, 0x8000...0x9FFF):
            guard !cartridgeDisabled else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.ross, 0x8000...0x9FFF):
            guard !cartridgeDisabled else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.ross, 0xA000...0xBFFF):
            guard !cartridgeDisabled else { return nil }
            return romlBanks[activeBank]?[0x2000 + (addr - 0xA000)]
        case (.delaEP64, 0x8000...0x9FFF),
             (.delaEP7x8, 0x8000...0x9FFF),
             (.delaEP256, 0x8000...0x9FFF):
            guard !cartridgeDisabled else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.rexEP256, 0x8000...0x9FFF):
            guard !cartridgeDisabled else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000] ?? 0xFF
        case (.stardos, 0x8000...0x9FFF):
            guard stardosROMLVisible else { return nil }
            return roml?[addr - 0x8000]
        case (.stardos, 0xE000...0xFFFF):
            return romh?[addr - 0xE000]
        case (.gameKiller, 0xE000...0xFFFF):
            guard !cartridgeDisabled else { return nil }
            return romh?[addr - 0xE000]
        case (.exos, 0xE000...0xFFFF):
            return romh?[addr - 0xE000]
        case (.freezeFrame, 0x8000...0x9FFF):
            guard freezeFrameROMLVisible else { return nil }
            return roml?[addr - 0x8000]
        case (.freezeFrame, 0xE000...0xFFFF):
            guard freezeFrameROMHVisible else { return nil }
            return roml?[addr - 0xE000]
        case (.freezeMachine, 0x8000...0x9FFF):
            guard !cartridgeDisabled else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.freezeMachine, 0xA000...0xBFFF):
            guard !cartridgeDisabled, freezeMachineUpperROMVisible else { return nil }
            return romhBanks[activeBank]?[addr - 0xA000]
        case (.freezeMachine, 0xE000...0xFFFF):
            guard !cartridgeDisabled, freezeMachineKernalROMVisible else { return nil }
            return romhBanks[activeBank]?[addr - 0xE000]
        case (.snapshot64, 0x8000...0x9FFF):
            guard !cartridgeDisabled else { return nil }
            return roml?[(addr - 0x8000) & 0x0FFF]
        case (.snapshot64, 0xE000...0xFFFF):
            guard !cartridgeDisabled else { return nil }
            return roml?[(addr - 0xE000) & 0x0FFF]
        case (.superExplodeV5, 0x8000...0x9FFF):
            guard superExplodeV5ROMEnabled else { return nil }
            return romlBanks[activeBank]?[addr - 0x8000]
        case (.mach5, 0x8000...0x9FFF):
            guard !cartridgeDisabled else { return nil }
            return roml?[addr - 0x8000]
        case (.prophet64, 0x8000...0x9FFF):
            guard !cartridgeDisabled else { return nil }
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
        case (.kcsPower, 0xDE00...0xDEFF):
            if address & 0x0002 != 0 {
                kcsMemoryMode = .ram
            } else {
                kcsMemoryMode = .eightK
            }
            return roml?[0x1E00 + (addr - 0xDE00)]
        case (.kcsPower, 0xDF00...0xDF7F):
            return kcsRAM[addr & 0x7F]
        case (.kcsPower, 0xDF80...0xDFFF):
            return kcsLineStatus()
        case (.atomicPower, 0xDF00...0xDFFF):
            guard atomicPowerActive else { return nil }
            if atomicPowerRAMEnabled || atomicPowerRAMAtA000 {
                return atomicPowerRAM[0x1F00 + (addr - 0xDF00)]
            }
            return romlBanks[activeBank]?[0x1F00 + (addr - 0xDF00)]
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
        case (.dinamic, 0xDE00...0xDE0F):
            activeBank = UInt16(addr - 0xDE00)
            return nil
        case (.structuredBasic, 0xDE00...0xDE03):
            applyStructuredBasicIO(address)
            return nil
        case (.ross, 0xDE00):
            if romlBanks[1] != nil {
                activeBank = 1
            }
            return nil
        case (.ross, 0xDF00):
            cartridgeDisabled = true
            return nil
        case (.warpSpeed, 0xDE00...0xDEFF):
            return roml?[0x1E00 + (addr - 0xDE00)]
        case (.warpSpeed, 0xDF00...0xDFFF):
            return roml?[0x1F00 + (addr - 0xDF00)]
        case (.mikroAssembler, 0xDE00...0xDEFF):
            return roml?[0x1E00 + (addr - 0xDE00)]
        case (.mikroAssembler, 0xDF00...0xDFFF):
            return roml?[0x1F00 + (addr - 0xDF00)]
        case (.rexEP256, 0xDFC0):
            cartridgeDisabled = true
            return nil
        case (.rexEP256, 0xDFE0):
            cartridgeDisabled = false
            return nil
        case (.stardos, 0xDE00...0xDEFF):
            chargeStardosCapacitor()
            return nil
        case (.stardos, 0xDF00...0xDFFF):
            dischargeStardosCapacitor()
            return nil
        case (.freezeFrame, 0xDE00...0xDEFF):
            freezeFrameROMLVisible = true
            freezeFrameROMHVisible = false
            return nil
        case (.freezeFrame, 0xDF00...0xDFFF):
            freezeFrameROMLVisible = false
            freezeFrameROMHVisible = false
            return nil
        case (.freezeMachine, 0xDE00...0xDEFF):
            cartridgeDisabled = false
            freezeMachineUpperROMVisible = true
            freezeMachineKernalROMVisible = false
            return nil
        case (.freezeMachine, 0xDF00...0xDFFF):
            cartridgeDisabled = true
            freezeMachineUpperROMVisible = false
            freezeMachineKernalROMVisible = false
            return nil
        case (.superExplodeV5, 0xDE00...0xDEFF):
            dischargeSuperExplodeV5Capacitor()
            return nil
        case (.superExplodeV5, 0xDF00...0xDFFF):
            return romlBanks[activeBank]?[0x1F00 + (addr - 0xDF00)]
        case (.superSnapshotV5, 0xDE00...0xDEFF):
            guard !cartridgeDisabled else { return nil }
            return romlBanks[activeBank]?[0x1E00 + (addr - 0xDE00)]
        case (.mach5, 0xDE00...0xDEFF):
            return roml?[0x1E00 + (addr - 0xDE00)]
        case (.mach5, 0xDF00...0xDFFF):
            return roml?[0x1F00 + (addr - 0xDF00)]
        case (.easyFlash, 0xDF00...0xDFFF):
            return easyFlashRAM[addr - 0xDF00]
        default:
            return nil
        }
    }

    public mutating func observeRead(_ address: UInt16) {
        if mappingMode == .epyxFastLoad, (0x8000...0x9FFF).contains(address) {
            dischargeEpyxFastLoadCapacitor()
        } else if mappingMode == .superExplodeV5, (0x8000...0x9FFF).contains(address) {
            dischargeSuperExplodeV5Capacitor()
        } else if mappingMode == .zaxxon {
            switch address {
            case 0x8000...0x8FFF:
                activeBank = 0
            case 0x9000...0x9FFF:
                activeBank = 1
            default:
                break
            }
        }
    }

    @discardableResult
    public mutating func write(_ address: UInt16, value: UInt8) -> Bool {
        let addr = Int(address)
        if mappingMode == .atomicPower, atomicPowerActive {
            if atomicPowerRAMEnabled, (0x8000...0x9FFF).contains(addr) {
                atomicPowerRAM[addr - 0x8000] = value
                return true
            }
            if atomicPowerRAMAtA000, (0xA000...0xBFFF).contains(addr) {
                atomicPowerRAM[addr - 0xA000] = value
                return true
            }
        }
        if mappingMode == .superSnapshotV5,
           superSnapshotV5RAMEnabled,
           (0x8000...0x9FFF).contains(addr)
        {
            superSnapshotV5RAM[superSnapshotV5RAMOffset(addr - 0x8000)] = value
            return true
        }
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
        case .kcsPower:
            if address & 0x0002 != 0 {
                kcsMemoryMode = .ultimax
            } else {
                kcsMemoryMode = .sixteenK
            }
        case .atomicPower:
            applyAtomicPowerControl(value)
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
        case .comal80:
            activeBank = UInt16(value & 0x07)
            cartridgeDisabled = value & 0x40 != 0
        case .structuredBasic:
            applyStructuredBasicIO(address)
        case .delaEP64:
            applyDelaEP64Control(value)
        case .delaEP7x8:
            applyDelaEP7x8Control(value)
        case .delaEP256:
            applyDelaEP256Control(value)
        case .stardos:
            chargeStardosCapacitor()
        case .gameKiller:
            disableGameKillerAfterIOAccess()
        case .superExplodeV5:
            dischargeSuperExplodeV5Capacitor()
        case .superSnapshotV5:
            guard !cartridgeDisabled else { break }
            applySuperSnapshotV5Control(value)
        case .mach5:
            cartridgeDisabled = false
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
        if mappingMode == .kcsPower, (0xDF00...0xDF7F).contains(address) {
            kcsRAM[Int(address & 0x007F)] = value
            return
        }
        if mappingMode == .kcsPower, (0xDF80...0xDFFF).contains(address) {
            return
        }
        if mappingMode == .atomicPower, (0xDF00...0xDFFF).contains(address) {
            if atomicPowerActive, atomicPowerRAMEnabled || atomicPowerRAMAtA000 {
                atomicPowerRAM[0x1F00 + Int(address - 0xDF00)] = value
            }
            return
        }
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
        if mappingMode == .superGames, address == 0xDF00, !superGamesWriteProtected {
            activeBank = UInt16(value & 0x03)
            cartridgeDisabled = value & 0x04 != 0
            superGamesWriteProtected = value & 0x08 != 0
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
        if mappingMode == .rexEP256, address == 0xDFA0 {
            applyRexEP256Control(value)
            return
        }
        if mappingMode == .stardos, (0xDF00...0xDFFF).contains(address) {
            dischargeStardosCapacitor()
            return
        }
        if mappingMode == .gameKiller, (0xDF00...0xDFFF).contains(address) {
            disableGameKillerAfterIOAccess()
            return
        }
        if mappingMode == .prophet64, (0xDF00...0xDFFF).contains(address) {
            activeBank = UInt16(value & 0x1F)
            cartridgeDisabled = value & 0x20 != 0
            return
        }
        if mappingMode == .superExplodeV5, (0xDF00...0xDFFF).contains(address) {
            activeBank = value & 0x80 == 0 ? 0 : 1
            return
        }
        if mappingMode == .snapshot64, (0xDF00...0xDFFF).contains(address) {
            cartridgeDisabled = true
            return
        }
        if mappingMode == .mach5, (0xDF00...0xDFFF).contains(address) {
            cartridgeDisabled = true
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

    private mutating func applyStructuredBasicIO(_ address: UInt16) {
        switch address & 0x00FF {
        case 0x00, 0x01:
            activeBank = 0
            cartridgeDisabled = false
        case 0x02:
            activeBank = 1
            cartridgeDisabled = false
        case 0x03:
            cartridgeDisabled = true
        default:
            break
        }
    }

    private mutating func applyDelaEP64Control(_ value: UInt8) {
        if value & 0x80 != 0 {
            cartridgeDisabled = true
            return
        }
        let decodedBank = Int(value & 0x03) << 2 | Int((value >> 4) & 0x03)
        if (4...11).contains(decodedBank) {
            activeBank = UInt16(decodedBank - 3)
        } else {
            activeBank = 0
        }
        cartridgeDisabled = false
    }

    private mutating func applyDelaEP7x8Control(_ value: UInt8) {
        if value == 0xFF {
            cartridgeDisabled = true
            return
        }
        for index in 0..<8 where value & UInt8(1 << index) == 0 {
            activeBank = UInt16(index)
            cartridgeDisabled = false
            return
        }
        activeBank = 0
        cartridgeDisabled = false
    }

    private mutating func applyDelaEP256Control(_ value: UInt8) {
        if value & 0x80 != 0 {
            cartridgeDisabled = true
            return
        }
        let low = Int(value & 0x0F)
        guard low >= 8 else {
            activeBank = 0
            cartridgeDisabled = false
            return
        }
        let groupOffset: Int?
        switch value & 0x70 {
        case 0x30:
            groupOffset = 0
        case 0x20:
            groupOffset = 8
        case 0x10:
            groupOffset = 16
        case 0x00:
            groupOffset = 24
        default:
            groupOffset = nil
        }
        activeBank = groupOffset.map { UInt16($0 + low - 8 + 1) } ?? 0
        cartridgeDisabled = false
    }

    private mutating func applyRexEP256Control(_ value: UInt8) {
        let socket = UInt16(value & 0x0F)
        guard socket < 8 else { return }
        let bankSelect = Int((value & 0xF0) >> 4)
        guard bankSelect <= 3 else { return }

        let socketSize = rexEP256SocketSizes[socket] ?? 0x2000
        let epromPart: Int
        switch socketSize {
        case 0x2000:
            epromPart = 0
        case 0x4000:
            epromPart = bankSelect & 0x01
        case 0x8000:
            epromPart = bankSelect
        default:
            return
        }

        if let offset = rexEP256SocketBankOffsets[socket] {
            activeBank = offset + UInt16(epromPart) + 1
        } else {
            activeBank = UInt16.max
        }
        cartridgeDisabled = false
    }

    private mutating func chargeStardosCapacitor() {
        stardosCapVoltage = min(Self.stardosChargeMax, stardosCapVoltage + Self.stardosChargeStep)
        updateStardosFlipflop()
    }

    private mutating func dischargeStardosCapacitor() {
        stardosCapVoltage = max(0, stardosCapVoltage - Self.stardosDischargeStep)
        updateStardosFlipflop()
    }

    private mutating func updateStardosFlipflop() {
        if stardosCapVoltage < Self.stardosLowThreshold {
            stardosROMLVisible = false
        } else if stardosCapVoltage > Self.stardosHighThreshold {
            stardosROMLVisible = true
        }
    }

    private mutating func disableGameKillerAfterIOAccess() {
        gameKillerDisableAccessCount += 1
        if gameKillerDisableAccessCount > 1 {
            cartridgeDisabled = true
        }
    }

    private func kcsLineStatus() -> UInt8 {
        switch kcsMemoryMode {
        case .eightK:
            return 0x40
        case .sixteenK:
            return 0x00
        case .ultimax:
            return 0x80
        case .ram:
            return 0xC0
        }
    }

    private mutating func applyAtomicPowerControl(_ value: UInt8) {
        guard atomicPowerActive else { return }
        activeBank = UInt16((value >> 3) & 0x03)
        let modeBits = value & 0x03

        if value & 0xE7 == 0x22 {
            atomicPowerMemoryMode = .sixteenK
            atomicPowerRAMEnabled = false
            atomicPowerRAMAtA000 = true
        } else {
            atomicPowerRAMAtA000 = false
            atomicPowerRAMEnabled = value & 0x20 != 0
            switch modeBits {
            case 0:
                atomicPowerMemoryMode = .ultimax
            case 1:
                atomicPowerMemoryMode = .sixteenK
            case 2:
                atomicPowerMemoryMode = .off
            default:
                atomicPowerMemoryMode = .eightK
            }
        }

        if value & 0x04 != 0 {
            atomicPowerActive = false
            atomicPowerRAMEnabled = false
            atomicPowerRAMAtA000 = false
            atomicPowerMemoryMode = .off
        }
    }

    private mutating func applySuperSnapshotV5Control(_ value: UInt8) {
        let bankLow = UInt16((value >> 2) & 0x01)
        let bankMiddle = UInt16((value >> 4) & 0x01) << 1
        let bankHigh = romlBanks[4] == nil ? 0 : UInt16((value >> 5) & 0x01) << 2
        activeBank = bankLow | bankMiddle | bankHigh
        superSnapshotV5RAMEnabled = value & 0x02 == 0
        superSnapshotV5UltimaxMode = value & 0x01 == 0
        cartridgeDisabled = value & 0x08 != 0
    }

    private func superSnapshotV5RAMOffset(_ offset: Int) -> Int {
        offset & 0x1FFF
    }

    public mutating func pressFreezeButton() {
        if mappingMode == .freezeFrame {
            freezeFrameROMLVisible = true
            freezeFrameROMHVisible = true
        } else if mappingMode == .freezeMachine {
            cartridgeDisabled = false
            freezeMachineUpperROMVisible = false
            freezeMachineKernalROMVisible = true
        } else if mappingMode == .snapshot64 {
            cartridgeDisabled = false
        } else if mappingMode == .superSnapshotV5 {
            cartridgeDisabled = false
            superSnapshotV5RAMEnabled = true
            superSnapshotV5UltimaxMode = true
        } else if mappingMode == .kcsPower {
            kcsMemoryMode = .ultimax
        } else if mappingMode == .atomicPower {
            atomicPowerActive = true
            atomicPowerMemoryMode = .ultimax
            atomicPowerRAMEnabled = true
            atomicPowerRAMAtA000 = false
        }
    }

    public mutating func reset() {
        let previousActiveBank = activeBank
        activeBank = 0
        cartridgeDisabled = false
        kcsMemoryMode = .sixteenK
        atomicPowerActive = true
        atomicPowerMemoryMode = .eightK
        atomicPowerRAMEnabled = false
        atomicPowerRAMAtA000 = false
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
        superGamesWriteProtected = false
        stardosCapVoltage = 0
        stardosROMLVisible = false
        gameKillerDisableAccessCount = 0
        freezeFrameROMLVisible = true
        freezeFrameROMHVisible = false
        freezeMachineUpperROMVisible = false
        freezeMachineKernalROMVisible = false
        superExplodeV5ROMEnabled = true
        superExplodeV5CyclesSinceDischarge = 0
        superSnapshotV5RAMEnabled = false
        superSnapshotV5UltimaxMode = true
        warpSpeedROMVisible = true
        if mappingMode == .freezeMachine, romlBanks[1] != nil {
            activeBank = previousActiveBank == 0 ? 1 : 0
        } else if mappingMode == .superExplodeV5 {
            activeBank = previousActiveBank
        }
        if mappingMode == .easyFlash {
            easyFlashMemoryMode = .ultimax
        }
        if mappingMode == .snapshot64 {
            cartridgeDisabled = true
        }
    }

    public mutating func tick(cycles: Int = 1) {
        guard cycles > 0 else { return }
        if mappingMode == .epyxFastLoad, epyxFastLoadROMEnabled {
            epyxFastLoadCyclesSinceDischarge += cycles
            if epyxFastLoadCyclesSinceDischarge >= Self.epyxFastLoadDisableCycles {
                epyxFastLoadROMEnabled = false
            }
        } else if mappingMode == .superExplodeV5, superExplodeV5ROMEnabled {
            superExplodeV5CyclesSinceDischarge += cycles
            if superExplodeV5CyclesSinceDischarge >= Self.superExplodeV5DisableCycles {
                superExplodeV5ROMEnabled = false
            }
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

    private mutating func dischargeSuperExplodeV5Capacitor() {
        superExplodeV5ROMEnabled = true
        superExplodeV5CyclesSinceDischarge = 0
    }

    private static func copy(_ data: [UInt8], into destination: inout [UInt8], at offset: Int) -> Bool {
        guard offset >= 0, offset + data.count <= destination.count else { return false }
        destination.replaceSubrange(offset..<(offset + data.count), with: data)
        return true
    }

    private static func insertROMBank(_ data: [UInt8], bank: UInt16, into banks: inout [UInt16: [UInt8]]) -> Bool {
        guard data.count == 0x2000, banks[bank] == nil else { return false }
        banks[bank] = data
        return true
    }

    private static func hasContiguousBanksFromZero(_ banks: [UInt16: [UInt8]]) -> Bool {
        let keys = banks.keys.sorted()
        guard let maximum = keys.last else { return false }
        return keys == Array(UInt16(0)...maximum)
    }

    private static let supportedHardwareTypes: Set<UInt16> = [
        0,  // Normal cartridge
        1,  // Action Replay
        2,  // KCS Power Cartridge
        3,  // Final Cartridge III
        4,  // Simon's BASIC
        5,  // Ocean type 1
        7,  // Fun Play / Power Play
        8,  // Super Games
        9,  // Atomic Power / Nordic Power
        10, // Epyx FastLoad
        11, // Westermann Learning, normal 16K mapping
        12, // Rex Utility, normal 8K mapping
        13, // Final Cartridge I
        14, // Magic Formel
        15, // C64 Game System / System 3
        16, // Warp Speed
        17, // Dinamic
        18, // Zaxxon / Super Zaxxon
        19, // Magic Desk / Domark / HES Australia
        20, // Super Snapshot V5
        21, // Comal-80
        22, // Structured BASIC
        23, // Ross
        24, // Dela EP64
        25, // Dela EP7x8
        26, // Dela EP256
        27, // Rex EP256
        28, // Mikro Assembler
        31, // Stardos
        42, // Game Killer
        43, // Prophet64
        44, // EXOS
        45, // Freeze Frame
        46, // Freeze Machine
        47, // Snapshot 64
        48, // Super Explode V5.0
        51, // MACH 5
        29, // Final Cartridge Plus
        30, // Action Replay 4
        35, // Action Replay 3
        32  // EasyFlash
    ]

    /// Approximate RC timeout for Epyx FastLoad's capacitor-gated ROM enable.
    /// Reading ROML or IO1 discharges the capacitor and keeps the 8K ROM visible.
    private static let epyxFastLoadDisableCycles = 512

    /// Approximate 300 ms RC timeout for Super Explode V5's EXROM gate.
    private static let superExplodeV5DisableCycles = 300_000

    private static let stardosChargeMax = 5_000_000
    private static let stardosLowThreshold = 1_400_000
    private static let stardosHighThreshold = 2_700_000
    private static let stardosChargeStep = stardosChargeMax / 64
    private static let stardosDischargeStep = stardosChargeMax / 64

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
