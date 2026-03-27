import Foundation
import Emu6502

/// NES CPU memory map implementing the Bus protocol.
public final class NESMemoryMap: Bus {

    /// 2KB internal RAM
    public var ram = [UInt8](repeating: 0, count: 2048)

    /// Component references
    public weak var ppu: PPU?
    public weak var apu: APU?
    public var mapper: Mapper?
    public weak var controller1: Controller?
    public weak var controller2: Controller?

    /// OAM DMA state
    public var dmaPending: Bool = false
    public var dmaPage: UInt8 = 0

    public init() {}

    public func read(_ address: UInt16) -> UInt8 {
        switch address {
        case 0x0000...0x1FFF:
            return ram[Int(address & 0x07FF)]

        case 0x2000...0x3FFF:
            return ppu?.readRegister(address) ?? 0

        case 0x4016:
            return controller1?.read() ?? 0

        case 0x4017:
            return controller2?.read() ?? 0

        case 0x4000...0x4015:
            return apu?.readRegister(address) ?? 0

        case 0x4018...0x401F:
            return 0  // Test mode

        case 0x4020...0xFFFF:
            return mapper?.cpuRead(address) ?? 0

        default:
            return 0
        }
    }

    public func write(_ address: UInt16, value: UInt8) {
        switch address {
        case 0x0000...0x1FFF:
            ram[Int(address & 0x07FF)] = value

        case 0x2000...0x3FFF:
            ppu?.writeRegister(address, value: value)

        case 0x4014:
            // OAM DMA
            dmaPage = value
            dmaPending = true

        case 0x4016:
            controller1?.write(value)
            controller2?.write(value)

        case 0x4000...0x4013, 0x4015, 0x4017:
            apu?.writeRegister(address, value: value)

        case 0x4020...0xFFFF:
            mapper?.cpuWrite(address, value: value)

        default:
            break
        }
    }
}
