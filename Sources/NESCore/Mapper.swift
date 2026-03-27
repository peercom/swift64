import Foundation

/// Mapper protocol — translates CPU/PPU addresses to cartridge memory.
public protocol Mapper: AnyObject {
    func cpuRead(_ address: UInt16) -> UInt8
    func cpuWrite(_ address: UInt16, value: UInt8)
    func ppuRead(_ address: UInt16) -> UInt8
    func ppuWrite(_ address: UInt16, value: UInt8)
}

// MARK: - Mapper 0 (NROM)

/// NROM: No bank switching. 16KB or 32KB PRG, 8KB CHR.
public final class MapperNROM: Mapper {

    let cart: Cartridge

    public init(_ cart: Cartridge) {
        self.cart = cart
    }

    public func cpuRead(_ address: UInt16) -> UInt8 {
        switch address {
        case 0x6000...0x7FFF:
            return cart.prgRAM[Int(address - 0x6000)]
        case 0x8000...0xFFFF:
            // 32KB: direct map. 16KB: mirror $8000-$BFFF into $C000-$FFFF
            let offset = Int(address - 0x8000) % cart.prgROM.count
            return cart.prgROM[offset]
        default:
            return 0
        }
    }

    public func cpuWrite(_ address: UInt16, value: UInt8) {
        if address >= 0x6000 && address <= 0x7FFF {
            cart.prgRAM[Int(address - 0x6000)] = value
        }
    }

    public func ppuRead(_ address: UInt16) -> UInt8 {
        if address <= 0x1FFF && Int(address) < cart.chrROM.count {
            return cart.chrROM[Int(address)]
        }
        return 0
    }

    public func ppuWrite(_ address: UInt16, value: UInt8) {
        // CHR RAM (if no CHR ROM was provided, chrROM acts as RAM)
        if address <= 0x1FFF && Int(address) < cart.chrROM.count {
            cart.chrROM[Int(address)] = value
        }
    }
}

// MARK: - Mapper 1 (MMC1 / SxROM)

public final class MapperMMC1: Mapper {

    let cart: Cartridge
    var shiftRegister: UInt8 = 0x10
    var control: UInt8 = 0x0C       // power-on: PRG 16KB mode, fix last bank
    var chrBank0: UInt8 = 0
    var chrBank1: UInt8 = 0
    var prgBank: UInt8 = 0

    public init(_ cart: Cartridge) {
        self.cart = cart
    }

    public func cpuRead(_ address: UInt16) -> UInt8 {
        switch address {
        case 0x6000...0x7FFF:
            return cart.prgRAM[Int(address - 0x6000)]
        case 0x8000...0xFFFF:
            let prgMode = (control >> 2) & 3
            let bankCount = cart.prgROM.count / 16384
            switch prgMode {
            case 0, 1: // 32KB mode
                let bank = (Int(prgBank) & 0x0E) % max(bankCount, 1)
                let offset = bank * 16384 + Int(address - 0x8000) % 32768
                return cart.prgROM[offset % cart.prgROM.count]
            case 2: // Fix first, switch second
                if address < 0xC000 {
                    return cart.prgROM[Int(address - 0x8000) % cart.prgROM.count]
                } else {
                    let bank = Int(prgBank) % bankCount
                    return cart.prgROM[bank * 16384 + Int(address - 0xC000)]
                }
            default: // Fix last, switch first (mode 3)
                if address < 0xC000 {
                    let bank = Int(prgBank) % bankCount
                    return cart.prgROM[bank * 16384 + Int(address - 0x8000)]
                } else {
                    let lastBank = bankCount - 1
                    return cart.prgROM[lastBank * 16384 + Int(address - 0xC000)]
                }
            }
        default:
            return 0
        }
    }

    public func cpuWrite(_ address: UInt16, value: UInt8) {
        if address >= 0x6000 && address <= 0x7FFF {
            cart.prgRAM[Int(address - 0x6000)] = value
            return
        }
        guard address >= 0x8000 else { return }

        if value & 0x80 != 0 {
            shiftRegister = 0x10
            control |= 0x0C
            return
        }

        let complete = shiftRegister & 1 != 0
        shiftRegister >>= 1
        shiftRegister |= (value & 1) << 4

        if complete {
            let reg = (address >> 13) & 3
            switch reg {
            case 0: control = shiftRegister
            case 1: chrBank0 = shiftRegister
            case 2: chrBank1 = shiftRegister
            case 3: prgBank = shiftRegister & 0x0F
            default: break
            }
            shiftRegister = 0x10
        }
    }

    public func ppuRead(_ address: UInt16) -> UInt8 {
        guard address <= 0x1FFF else { return 0 }
        let chrMode = (control >> 4) & 1
        let offset: Int
        if chrMode == 0 {
            // 8KB mode
            let bank = Int(chrBank0 & 0x1E)
            offset = bank * 4096 + Int(address)
        } else {
            // 4KB mode
            if address < 0x1000 {
                offset = Int(chrBank0) * 4096 + Int(address)
            } else {
                offset = Int(chrBank1) * 4096 + Int(address - 0x1000)
            }
        }
        if offset < cart.chrROM.count {
            return cart.chrROM[offset]
        }
        return 0
    }

    public func ppuWrite(_ address: UInt16, value: UInt8) {
        guard address <= 0x1FFF, Int(address) < cart.chrROM.count else { return }
        cart.chrROM[Int(address)] = value
    }

    /// MMC1 controls mirroring dynamically
    public var mirrorMode: Cartridge.MirrorMode {
        switch control & 3 {
        case 0: return .horizontal  // one-screen lower
        case 1: return .horizontal  // one-screen upper
        case 2: return .vertical
        case 3: return .horizontal
        default: return .horizontal
        }
    }
}

// MARK: - Mapper 2 (UxROM)

public final class MapperUxROM: Mapper {

    let cart: Cartridge
    var bankSelect: UInt8 = 0

    public init(_ cart: Cartridge) {
        self.cart = cart
    }

    public func cpuRead(_ address: UInt16) -> UInt8 {
        switch address {
        case 0x8000...0xBFFF:
            let bank = Int(bankSelect) % (cart.prgROM.count / 16384)
            return cart.prgROM[bank * 16384 + Int(address - 0x8000)]
        case 0xC000...0xFFFF:
            let lastBank = cart.prgROM.count / 16384 - 1
            return cart.prgROM[lastBank * 16384 + Int(address - 0xC000)]
        default:
            return 0
        }
    }

    public func cpuWrite(_ address: UInt16, value: UInt8) {
        if address >= 0x8000 {
            bankSelect = value
        }
    }

    public func ppuRead(_ address: UInt16) -> UInt8 {
        guard address <= 0x1FFF, Int(address) < cart.chrROM.count else { return 0 }
        return cart.chrROM[Int(address)]
    }

    public func ppuWrite(_ address: UInt16, value: UInt8) {
        guard address <= 0x1FFF, Int(address) < cart.chrROM.count else { return }
        cart.chrROM[Int(address)] = value
    }
}

/// Create the appropriate mapper for a cartridge.
public func createMapper(for cart: Cartridge) -> Mapper {
    switch cart.mapperNumber {
    case 0:  return MapperNROM(cart)
    case 1:  return MapperMMC1(cart)
    case 2:  return MapperUxROM(cart)
    default: return MapperNROM(cart)  // fallback
    }
}
