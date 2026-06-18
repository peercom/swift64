import XCTest
@testable import C64Core

final class CartridgeTests: XCTestCase {
    func testParsesStandard8KCRTAndMapsROML() {
        let roml = Array(repeating: UInt8(0x42), count: 0x2000)
        let crt = makeCRT(exrom: 0, game: 1, chips: [
            (address: 0x8000, data: roml)
        ])

        let cartridge = Cartridge.parseCRT(crt)

        XCTAssertEqual(cartridge?.name, "TEST CART")
        XCTAssertEqual(cartridge?.mappingMode, .normal8K)
        XCTAssertEqual(cartridge?.read(0x8000), 0x42)
        XCTAssertEqual(cartridge?.read(0x9FFF), 0x42)
        XCTAssertNil(cartridge?.read(0xA000))
    }

    func testParsesStandard16KCRTAndMemoryMapOverridesBasicROM() throws {
        let roml = Array(repeating: UInt8(0x80), count: 0x2000)
        let romh = Array(repeating: UInt8(0xA0), count: 0x2000)
        let crt = makeCRT(exrom: 0, game: 0, chips: [
            (address: 0x8000, data: roml),
            (address: 0xA000, data: romh)
        ])
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.basicROM[0] = 0xBA
        memory.ram[0x8000] = 0x11
        memory.ram[0xA000] = 0x22

        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xA000), 0xA0)

        memory.write(0x8000, value: 0x33)
        memory.write(0xA000, value: 0x44)

        XCTAssertEqual(memory.ram[0x8000], 0x33)
        XCTAssertEqual(memory.ram[0xA000], 0x44)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xA000), 0xA0)
    }

    func testParsesWestermannLearningCRTAsNormal16KMapping() throws {
        let crt = makeCRT(
            hardwareType: 11,
            exrom: 0,
            game: 0,
            chips: [
                (address: 0x8000, data: Array(repeating: 0x81, count: 0x2000)),
                (address: 0xA000, data: Array(repeating: 0xA1, count: 0x2000))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.basicROM[0] = 0xBA

        XCTAssertEqual(cartridge.hardwareType, 11)
        XCTAssertEqual(cartridge.mappingMode, .normal16K)
        XCTAssertEqual(memory.read(0x8000), 0x81)
        XCTAssertEqual(memory.read(0xA000), 0xA1)
    }

    func testParsesRexUtilityCRTAsNormal8KMapping() throws {
        let crt = makeCRT(
            hardwareType: 12,
            exrom: 0,
            game: 1,
            chips: [
                (address: 0x8000, data: Array(repeating: 0x52, count: 0x2000))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.basicROM[0] = 0xBA

        XCTAssertEqual(cartridge.hardwareType, 12)
        XCTAssertEqual(cartridge.mappingMode, .normal8K)
        XCTAssertEqual(memory.read(0x8000), 0x52)
        XCTAssertEqual(memory.read(0xA000), 0xBA)
        XCTAssertNil(cartridge.read(0xA000))
    }

    func testParsesUltimaxCRTAndMapsROMHAtKernalWindow() throws {
        let roml = Array(repeating: UInt8(0x80), count: 0x2000)
        let romh = Array(repeating: UInt8(0xE0), count: 0x2000)
        let crt = makeCRT(exrom: 1, game: 0, chips: [
            (address: 0x8000, data: roml),
            (address: 0xE000, data: romh)
        ])
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.kernalROM[0] = 0xFE

        XCTAssertEqual(cartridge.mappingMode, .ultimax)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xE000), 0xE0)
    }

    func testUltimaxMemoryMapLeavesMiddleRangesOpenAndKeepsC000RAM() throws {
        let roml = Array(repeating: UInt8(0x80), count: 0x2000)
        let romh = Array(repeating: UInt8(0xE0), count: 0x2000)
        let crt = makeCRT(exrom: 1, game: 0, chips: [
            (address: 0x8000, data: roml),
            (address: 0xE000, data: romh)
        ])
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.ram[0x0FFF] = 0x0F
        memory.ram[0x1000] = 0x11
        memory.ram[0xA000] = 0xAA
        memory.ram[0xC000] = 0xC0
        memory.basicROM[0] = 0xBA
        memory.kernalROM[0] = 0xFE

        XCTAssertEqual(memory.read(0x0FFF), 0x0F)
        XCTAssertEqual(memory.read(0xC000), 0xC0)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xE000), 0xE0)

        XCTAssertEqual(memory.read(0x1000), 0xE0)
        XCTAssertEqual(memory.read(0xA000), 0xE0)

        memory.write(0x1000, value: 0x22)
        memory.write(0xA000, value: 0x33)
        memory.write(0xC000, value: 0x44)
        memory.write(0xE000, value: 0x55)

        XCTAssertEqual(memory.ram[0x1000], 0x11)
        XCTAssertEqual(memory.ram[0xA000], 0xAA)
        XCTAssertEqual(memory.ram[0xC000], 0x44)
        XCTAssertEqual(memory.read(0xE000), 0xE0)
    }

    func testUltimaxMemoryMapKeepsIOVisibleRegardlessOfCPUROMPortBits() throws {
        let crt = makeCRT(exrom: 1, game: 0, chips: [
            (address: 0x8000, data: Array(repeating: 0x80, count: 0x2000)),
            (address: 0xE000, data: Array(repeating: 0xE0, count: 0x2000))
        ])
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.write(0x0001, value: 0x30)

        memory.write(0xD800, value: 0x0B)
        memory.ram[0xC000] = 0xA3

        XCTAssertEqual(memory.read(0xC000), 0xA3)
        XCTAssertEqual(memory.read(0xD800), 0xAB)
    }

    func testParsesSimonsBasicCRTAndControlsUpperROMThroughIO1() throws {
        let crt = makeCRT(
            hardwareType: 4,
            exrom: 0,
            game: 1,
            chips: [
                (address: 0x8000, data: Array(repeating: 0x80, count: 0x2000)),
                (address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.basicROM[0] = 0xBA

        XCTAssertEqual(cartridge.hardwareType, 4)
        XCTAssertEqual(cartridge.mappingMode, .simonsBasic)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xA000), 0xBA)

        memory.write(0xDE00, value: 0x01)
        XCTAssertEqual(memory.read(0xA000), 0xA0)

        memory.write(0xDE00, value: 0x00)
        XCTAssertEqual(memory.read(0xA000), 0xBA)
    }

    func testC64ResetRestoresSimonsBasicUpperROMDisabledState() throws {
        let crt = makeCRT(
            hardwareType: 4,
            exrom: 0,
            game: 1,
            chips: [
                (address: 0x8000, data: Array(repeating: 0x80, count: 0x2000)),
                (address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.basicROM[0] = 0xBA

        c64.memory.write(0xDE00, value: 0x01)
        XCTAssertEqual(c64.memory.read(0xA000), 0xA0)

        c64.reset()

        XCTAssertEqual(c64.memory.read(0x8000), 0x80)
        XCTAssertEqual(c64.memory.read(0xA000), 0xBA)
    }

    func testParsesMagicDeskCRTAndBanksROMLThroughIO1() throws {
        let crt = makeCRT(
            hardwareType: 19,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x10, count: 0x2000)),
                (bank: 1, address: 0x8000, data: Array(repeating: 0x21, count: 0x2000)),
                (bank: 2, address: 0x8000, data: Array(repeating: 0x32, count: 0x2000))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge

        XCTAssertEqual(cartridge.hardwareType, 19)
        XCTAssertEqual(cartridge.mappingMode, .magicDesk)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertNil(cartridge.read(0xA000))

        memory.write(0xDE00, value: 0x01)
        XCTAssertEqual(memory.read(0x8000), 0x21)

        memory.write(0xDE00, value: 0x02)
        XCTAssertEqual(memory.read(0x8000), 0x32)
    }

    func testMagicDeskIO1DisableFallsBackToUnderlyingRAMAndCanReenable() throws {
        let crt = makeCRT(
            hardwareType: 19,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x10, count: 0x2000)),
                (bank: 1, address: 0x8000, data: Array(repeating: 0x21, count: 0x2000))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.ram[0x8000] = 0x44

        XCTAssertEqual(memory.read(0x8000), 0x10)

        memory.write(0xDE00, value: 0x81)
        XCTAssertEqual(memory.read(0x8000), 0x44)

        memory.write(0xDE00, value: 0x01)
        XCTAssertEqual(memory.read(0x8000), 0x21)
    }

    func testC64ResetRestoresMagicDeskStartupBankAndEnableState() throws {
        let crt = makeCRT(
            hardwareType: 19,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x10, count: 0x2000)),
                (bank: 1, address: 0x8000, data: Array(repeating: 0x21, count: 0x2000))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.ram[0x8000] = 0x44

        c64.memory.write(0xDE00, value: 0x81)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        c64.reset()

        XCTAssertEqual(c64.memory.read(0x8000), 0x10)
        XCTAssertEqual(c64.mountedCartridgeName, "TEST CART")
    }

    func testParsesOceanCRTAndBanksROMLThroughIO1() throws {
        let crt = makeCRT(
            hardwareType: 5,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x10, count: 0x2000)),
                (bank: 1, address: 0x8000, data: Array(repeating: 0x21, count: 0x2000)),
                (bank: 2, address: 0x8000, data: Array(repeating: 0x32, count: 0x2000))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge

        XCTAssertEqual(cartridge.hardwareType, 5)
        XCTAssertEqual(cartridge.mappingMode, .ocean)
        XCTAssertEqual(memory.read(0x8000), 0x10)

        memory.write(0xDE00, value: 0x01)
        XCTAssertEqual(memory.read(0x8000), 0x21)

        memory.write(0xDE00, value: 0x42)
        XCTAssertEqual(memory.read(0x8000), 0x32)
    }

    func testOceanCRTCanBankUpperROMHBlocks() throws {
        let crt = makeCRT(
            hardwareType: 5,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x10, count: 0x2000)),
                (bank: 16, address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.ram[0x8000] = 0x44
        memory.basicROM[0] = 0xBA

        XCTAssertEqual(memory.read(0x8000), 0x10)

        memory.write(0xDE00, value: 0x10)

        XCTAssertEqual(memory.read(0x8000), 0x44)
        XCTAssertEqual(memory.read(0xA000), 0xA0)
    }

    func testParsesFunPlayCRTAndBanksROMLThroughDecodedIO1Values() throws {
        let crt = makeCRT(
            hardwareType: 7,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0x00, address: 0x8000, data: Array(repeating: 0x10, count: 0x2000)),
                (bank: 0x08, address: 0x8000, data: Array(repeating: 0x21, count: 0x2000)),
                (bank: 0x39, address: 0x8000, data: Array(repeating: 0xFF, count: 0x2000))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge

        XCTAssertEqual(cartridge.hardwareType, 7)
        XCTAssertEqual(cartridge.mappingMode, .funPlay)
        XCTAssertEqual(memory.read(0x8000), 0x10)

        memory.write(0xDE00, value: 0x08)
        XCTAssertEqual(memory.read(0x8000), 0x21)

        memory.write(0xDE00, value: 0x39)
        XCTAssertEqual(memory.read(0x8000), 0xFF)
    }

    func testFunPlayDisableWriteFallsBackToUnderlyingRAMUntilReset() throws {
        let crt = makeCRT(
            hardwareType: 7,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0x00, address: 0x8000, data: Array(repeating: 0x10, count: 0x2000)),
                (bank: 0x08, address: 0x8000, data: Array(repeating: 0x21, count: 0x2000))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.ram[0x8000] = 0x44

        c64.memory.write(0xDE00, value: 0x08)
        XCTAssertEqual(c64.memory.read(0x8000), 0x21)

        c64.memory.write(0xDE00, value: 0x86)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x10)
    }

    func testRejectsUnsupportedCartridgeHardwareType() {
        var crt = makeCRT(exrom: 0, game: 1, chips: [
            (address: 0x8000, data: Array(repeating: 0x42, count: 0x2000))
        ])
        crt[0x17] = 1

        XCTAssertNil(Cartridge.parseCRT(crt))
    }

    func testC64MountCartridgeInstallsParsedCRT() {
        let crt = makeCRT(exrom: 0, game: 1, chips: [
            (address: 0x8000, data: Array(repeating: 0x5A, count: 0x2000))
        ])
        let c64 = C64()

        XCTAssertTrue(c64.mountCartridge(crt))
        XCTAssertEqual(c64.mountedCartridgeName, "TEST CART")
        XCTAssertEqual(c64.emulationStatus.mountedCartridgeName, "TEST CART")
        XCTAssertEqual(c64.memory.read(0x8000), 0x5A)

        c64.unmountCartridge()
        XCTAssertNil(c64.mountedCartridgeName)
        XCTAssertNil(c64.memory.cartridge)
    }

    private func makeCRT(
        hardwareType: UInt16 = 0,
        exrom: UInt8,
        game: UInt8,
        chips: [(address: UInt16, data: [UInt8])]
    ) -> Data {
        makeCRT(
            hardwareType: hardwareType,
            exrom: exrom,
            game: game,
            chips: chips.map { (bank: UInt16(0), address: $0.address, data: $0.data) }
        )
    }

    private func makeCRT(
        hardwareType: UInt16 = 0,
        exrom: UInt8,
        game: UInt8,
        chips: [(bank: UInt16, address: UInt16, data: [UInt8])]
    ) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x40)
        writeASCII("C64 CARTRIDGE   ", into: &bytes, at: 0)
        writeUInt32BE(0x40, into: &bytes, at: 0x10)
        writeUInt16BE(0x0100, into: &bytes, at: 0x14)
        writeUInt16BE(hardwareType, into: &bytes, at: 0x16)
        bytes[0x18] = exrom
        bytes[0x19] = game
        writeASCII("TEST CART", into: &bytes, at: 0x20)

        for chip in chips {
            bytes.append(contentsOf: makeCHIP(bank: chip.bank, address: chip.address, data: chip.data))
        }

        return Data(bytes)
    }

    private func makeCHIP(bank: UInt16 = 0, address: UInt16, data: [UInt8]) -> [UInt8] {
        var chip = [UInt8](repeating: 0, count: 16)
        writeASCII("CHIP", into: &chip, at: 0)
        writeUInt32BE(UInt32(16 + data.count), into: &chip, at: 4)
        writeUInt16BE(0, into: &chip, at: 8)
        writeUInt16BE(bank, into: &chip, at: 10)
        writeUInt16BE(address, into: &chip, at: 12)
        writeUInt16BE(UInt16(data.count), into: &chip, at: 14)
        chip.append(contentsOf: data)
        return chip
    }

    private func writeASCII(_ string: String, into bytes: inout [UInt8], at offset: Int) {
        for (index, byte) in string.utf8.enumerated() {
            bytes[offset + index] = byte
        }
    }

    private func writeUInt16BE(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 1] = UInt8(value & 0xFF)
    }

    private func writeUInt32BE(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8((value >> 24) & 0xFF)
        bytes[offset + 1] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 3] = UInt8(value & 0xFF)
    }
}
