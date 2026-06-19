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

    func testParsesKCSPowerCRTAndSwitchesModesThroughIO1Accesses() throws {
        let crt = makeCRT(
            hardwareType: 2,
            exrom: 0,
            game: 0,
            chips: makeKCSPowerChips()
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.basicROM[0] = 0xBA
        memory.ram[0x8000] = 0x44
        memory.ram[0xA000] = 0x55

        XCTAssertEqual(cartridge.hardwareType, 2)
        XCTAssertEqual(cartridge.mappingMode, .kcsPower)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xA000), 0xA0)

        XCTAssertEqual(memory.read(0xDE00), 0xDE)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xA000), 0xBA)

        XCTAssertEqual(memory.read(0xDE02), 0xDE)
        XCTAssertEqual(memory.read(0x8000), 0x44)
        XCTAssertEqual(memory.read(0xA000), 0xBA)

        memory.write(0xDE00, value: 0x00)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xA000), 0xA0)

        memory.write(0xDE02, value: 0x00)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xE000), 0xA0)
        XCTAssertEqual(memory.read(0xA000), 0xA0)
    }

    func testKCSPowerIO2RAMAndLineStatus() throws {
        let crt = makeCRT(
            hardwareType: 2,
            exrom: 0,
            game: 0,
            chips: makeKCSPowerChips()
        )
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))

        memory.write(0xDF00, value: 0x12)
        memory.write(0xDF7F, value: 0x34)
        memory.write(0xDF80, value: 0x56)
        XCTAssertEqual(memory.read(0xDF00), 0x12)
        XCTAssertEqual(memory.read(0xDF7F), 0x34)

        XCTAssertEqual(memory.read(0xDF80) & 0xC0, 0x00)
        _ = memory.read(0xDE00)
        XCTAssertEqual(memory.read(0xDF80) & 0xC0, 0x40)
        _ = memory.read(0xDE02)
        XCTAssertEqual(memory.read(0xDF80) & 0xC0, 0xC0)
        memory.write(0xDE02, value: 0x00)
        XCTAssertEqual(memory.read(0xDF80) & 0xC0, 0x80)
    }

    func testKCSPowerResetAndFreezeRestoreExpectedModes() throws {
        let crt = makeCRT(
            hardwareType: 2,
            exrom: 0,
            game: 0,
            chips: makeKCSPowerChips()
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))

        _ = c64.memory.read(0xDE02)
        XCTAssertNotEqual(c64.memory.read(0x8000), 0x80)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x80)
        XCTAssertEqual(c64.memory.read(0xA000), 0xA0)

        c64.pressCartridgeFreezeButton()
        XCTAssertEqual(c64.memory.read(0x8000), 0x80)
        XCTAssertEqual(c64.memory.read(0xE000), 0xA0)
    }

    func testKCSPowerRejectsMissingMisplacedOrWrongSizeImages() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 2,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 2,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x2000)),
                (bank: 0, address: 0xE000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 2,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x1000)),
                (bank: 0, address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )))
    }

    func testParsesActionReplayCRTAndBanksROMLThroughIO1() throws {
        let crt = makeCRT(
            hardwareType: 1,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make8KBank(first: 0x10, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make8KBank(first: 0x21, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make8KBank(first: 0x32, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make8KBank(first: 0x43, io: 0xD3))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge

        XCTAssertEqual(cartridge.hardwareType, 1)
        XCTAssertEqual(cartridge.mappingMode, .actionReplay)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertEqual(memory.read(0xDF10), 0xD0)

        memory.write(0xDE00, value: 0x18)

        XCTAssertEqual(memory.read(0x8000), 0x43)
        XCTAssertEqual(memory.read(0xDF10), 0xD3)
    }

    func testActionReplayRAMOverlayAndIO2WindowAreWritable() throws {
        let crt = makeCRT(
            hardwareType: 1,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make8KBank(first: 0x10, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make8KBank(first: 0x21, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make8KBank(first: 0x32, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make8KBank(first: 0x43, io: 0xD3))
            ]
        )
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        memory.ram[0x8000] = 0x44

        memory.write(0xDE00, value: 0x20)
        memory.write(0x8000, value: 0x5A)
        memory.write(0xDF10, value: 0x6B)

        XCTAssertEqual(memory.read(0x8000), 0x5A)
        XCTAssertEqual(memory.ram[0x8000], 0x44)
        XCTAssertEqual(memory.read(0xDF10), 0x6B)
        XCTAssertEqual(memory.read(0x9F10), 0x6B)
    }

    func testActionReplayDisableFallsBackToUnderlyingRAMUntilReset() throws {
        let crt = makeCRT(
            hardwareType: 1,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make8KBank(first: 0x10, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make8KBank(first: 0x21, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make8KBank(first: 0x32, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make8KBank(first: 0x43, io: 0xD3))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.ram[0x8000] = 0x44

        c64.memory.write(0xDE00, value: 0x04)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)
        XCTAssertEqual(c64.memory.read(0xDF10), 0x44)

        c64.reset()

        XCTAssertEqual(c64.memory.read(0x8000), 0x10)
    }

    func testActionReplayRejectsIncompleteBankSet() {
        let crt = makeCRT(
            hardwareType: 1,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make8KBank(first: 0x10, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make8KBank(first: 0x21, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make8KBank(first: 0x32, io: 0xD2))
            ]
        )

        XCTAssertNil(Cartridge.parseCRT(crt))
    }

    func testParsesActionReplay3CRTAndMirrorsSelectedBankIntoROMLAndROMH() throws {
        let crt = makeCRT(
            hardwareType: 35,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make8KBank(first: 0x10, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make8KBank(first: 0x21, io: 0xD1))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.basicROM[0] = 0xBA

        XCTAssertEqual(cartridge.hardwareType, 35)
        XCTAssertEqual(cartridge.mappingMode, .actionReplay3)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertEqual(memory.read(0xA000), 0x10)

        memory.write(0xDE00, value: 0x09)

        XCTAssertEqual(memory.read(0x8000), 0x21)
        XCTAssertEqual(memory.read(0xA000), 0x21)
    }

    func testActionReplay3CanHideReenableAndDisableROMThroughIO1() throws {
        let crt = makeCRT(
            hardwareType: 35,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make8KBank(first: 0x10, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make8KBank(first: 0x21, io: 0xD1))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.ram[0x8000] = 0x44
        c64.memory.basicROM[0] = 0xBA

        c64.memory.write(0xDE00, value: 0x00)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)
        XCTAssertEqual(c64.memory.read(0xA000), 0xBA)

        c64.memory.write(0xDE00, value: 0x08)
        XCTAssertEqual(c64.memory.read(0x8000), 0x10)
        XCTAssertEqual(c64.memory.read(0xA000), 0x10)

        c64.memory.write(0xDE00, value: 0x0C)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)
        XCTAssertEqual(c64.memory.read(0xA000), 0xBA)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x10)
        XCTAssertEqual(c64.memory.read(0xA000), 0x10)
    }

    func testActionReplay3RejectsIncompleteBankSet() {
        let crt = makeCRT(
            hardwareType: 35,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make8KBank(first: 0x10, io: 0xD0))
            ]
        )

        XCTAssertNil(Cartridge.parseCRT(crt))
    }

    func testParsesActionReplay4CRTAndBanksROMLThroughIO1() throws {
        let crt = makeCRT(
            hardwareType: 30,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make8KBank(first: 0x10, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make8KBank(first: 0x21, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make8KBank(first: 0x32, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make8KBank(first: 0x43, io: 0xD3))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge

        XCTAssertEqual(cartridge.hardwareType, 30)
        XCTAssertEqual(cartridge.mappingMode, .actionReplay4)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertEqual(memory.read(0xDF10), 0x10)

        memory.write(0xDE00, value: 0x19)

        XCTAssertEqual(memory.read(0x8000), 0x43)
        XCTAssertEqual(memory.read(0xDF10), 0x43)
    }

    func testActionReplay4CanHideROMAndReenableThroughIO1() throws {
        let crt = makeCRT(
            hardwareType: 30,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make8KBank(first: 0x10, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make8KBank(first: 0x21, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make8KBank(first: 0x32, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make8KBank(first: 0x43, io: 0xD3))
            ]
        )
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        memory.ram[0x8000] = 0x44

        memory.write(0xDE00, value: 0x00)
        XCTAssertEqual(memory.read(0x8000), 0x44)
        XCTAssertEqual(memory.read(0xDF10), 0x44)

        memory.write(0xDE00, value: 0x08)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertEqual(memory.read(0xDF10), 0x10)
    }

    func testActionReplay4FreezeEndDisableIgnoresLaterIO1UntilReset() throws {
        let crt = makeCRT(
            hardwareType: 30,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make8KBank(first: 0x10, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make8KBank(first: 0x21, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make8KBank(first: 0x32, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make8KBank(first: 0x43, io: 0xD3))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.ram[0x8000] = 0x44

        c64.memory.write(0xDE00, value: 0x0C)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        c64.memory.write(0xDE00, value: 0x19)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x10)
    }

    func testActionReplay4RejectsIncompleteBankSet() {
        let crt = makeCRT(
            hardwareType: 30,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make8KBank(first: 0x10, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make8KBank(first: 0x21, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make8KBank(first: 0x32, io: 0xD2))
            ]
        )

        XCTAssertNil(Cartridge.parseCRT(crt))
    }

    func testParsesFinalCartridgeIAndMaps16KROM() throws {
        let crt = makeCRT(
            hardwareType: 13,
            exrom: 0,
            game: 0,
            chips: [
                (address: 0x8000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.basicROM[0] = 0xBA

        XCTAssertEqual(cartridge.hardwareType, 13)
        XCTAssertEqual(cartridge.mappingMode, .finalCartridgeI)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertEqual(memory.read(0xA000), 0xA0)
    }

    func testFinalCartridgeIIO1DisablesAndIO2EnablesROM() throws {
        let crt = makeCRT(
            hardwareType: 13,
            exrom: 0,
            game: 0,
            chips: [
                (address: 0x8000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.ram[0x8000] = 0x44
        c64.memory.basicROM[0] = 0xBA

        XCTAssertEqual(c64.memory.read(0xDE10), 0xD0)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)
        XCTAssertEqual(c64.memory.read(0xA000), 0xBA)

        XCTAssertEqual(c64.memory.read(0xDF10), 0xD0)
        XCTAssertEqual(c64.memory.read(0x8000), 0x10)
        XCTAssertEqual(c64.memory.read(0xA000), 0xA0)

        c64.memory.write(0xDE00, value: 0x00)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        c64.memory.write(0xDF00, value: 0x00)
        XCTAssertEqual(c64.memory.read(0x8000), 0x10)
    }

    func testC64ResetRestoresFinalCartridgeIROMVisible() throws {
        let crt = makeCRT(
            hardwareType: 13,
            exrom: 0,
            game: 0,
            chips: [
                (address: 0x8000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.ram[0x8000] = 0x44

        c64.memory.write(0xDE00, value: 0x00)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        c64.reset()

        XCTAssertEqual(c64.memory.read(0x8000), 0x10)
    }

    func testFinalCartridgeIRejectsSplitOrShortImages() {
        let splitCRT = makeCRT(
            hardwareType: 13,
            exrom: 0,
            game: 0,
            chips: [
                (address: 0x8000, data: Array(repeating: 0x10, count: 0x2000)),
                (address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )
        let shortCRT = makeCRT(
            hardwareType: 13,
            exrom: 0,
            game: 0,
            chips: [
                (address: 0x8000, data: Array(repeating: 0x10, count: 0x2000))
            ]
        )

        XCTAssertNil(Cartridge.parseCRT(splitCRT))
        XCTAssertNil(Cartridge.parseCRT(shortCRT))
    }

    func testParsesFinalCartridgePlusAndMapsDocumentedSegments() throws {
        let crt = makeCRT(
            hardwareType: 29,
            exrom: 1,
            game: 0,
            chips: [
                (address: 0x0000, data: makeFinalCartridgePlusImage(unused: 0xFF, kernal: 0xE0, low: 0x80, high: 0xA0))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.basicROM[0] = 0xBA
        memory.kernalROM[0] = 0xFE

        XCTAssertEqual(cartridge.hardwareType, 29)
        XCTAssertEqual(cartridge.mappingMode, .finalCartridgePlus)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xA000), 0xA0)
        XCTAssertEqual(memory.read(0xE000), 0xE0)
    }

    func testFinalCartridgePlusIO2ControlBitsToggleROMWindowsAndReadback() throws {
        let crt = makeCRT(
            hardwareType: 29,
            exrom: 1,
            game: 0,
            chips: [
                (address: 0x0000, data: makeFinalCartridgePlusImage(unused: 0xFF, kernal: 0xE0, low: 0x80, high: 0xA0))
            ]
        )
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        memory.ram[0x8000] = 0x44
        memory.basicROM[0] = 0xBA
        memory.kernalROM[0] = 0xFE

        memory.write(0xDF00, value: 0x10)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xA000), 0xA0)
        XCTAssertEqual(memory.read(0xE000), 0xFE)
        XCTAssertEqual(memory.read(0xDF10), 0x00)

        memory.write(0xDF00, value: 0xF0)
        XCTAssertEqual(memory.read(0x8000), 0x44)
        XCTAssertEqual(memory.read(0xA000), 0xBA)
        XCTAssertEqual(memory.read(0xE000), 0xE0)
        XCTAssertEqual(memory.read(0xDF10), 0x80)

        memory.write(0xDF00, value: 0x00)
        XCTAssertEqual(memory.read(0x8000), 0x44)
        XCTAssertEqual(memory.read(0xA000), 0xBA)
        XCTAssertEqual(memory.read(0xE000), 0xFE)
        XCTAssertEqual(memory.read(0xDF10), 0xFE)
    }

    func testC64ResetRestoresFinalCartridgePlusControlState() throws {
        let crt = makeCRT(
            hardwareType: 29,
            exrom: 1,
            game: 0,
            chips: [
                (address: 0x0000, data: makeFinalCartridgePlusImage(unused: 0xFF, kernal: 0xE0, low: 0x80, high: 0xA0))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.ram[0x8000] = 0x44

        c64.memory.write(0xDF00, value: 0x00)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        c64.reset()

        XCTAssertEqual(c64.memory.read(0x8000), 0x80)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE0)
    }

    func testFinalCartridgePlusRejectsSplitOrShortImages() {
        let splitCRT = makeCRT(
            hardwareType: 29,
            exrom: 1,
            game: 0,
            chips: [
                (address: 0x0000, data: Array(repeating: 0xFF, count: 0x4000)),
                (address: 0x4000, data: Array(repeating: 0x80, count: 0x4000))
            ]
        )
        let shortCRT = makeCRT(
            hardwareType: 29,
            exrom: 1,
            game: 0,
            chips: [
                (address: 0x0000, data: Array(repeating: 0xFF, count: 0x4000))
            ]
        )

        XCTAssertNil(Cartridge.parseCRT(splitCRT))
        XCTAssertNil(Cartridge.parseCRT(shortCRT))
    }

    func testParsesFinalCartridgeIIIAndBanks16KThroughDFFF() throws {
        let crt = makeCRT(
            hardwareType: 3,
            exrom: 1,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x21, high: 0xB1, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make16KBank(low: 0x32, high: 0xC2, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make16KBank(low: 0x43, high: 0xD3, io: 0xD3))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.basicROM[0] = 0xBA

        XCTAssertEqual(cartridge.hardwareType, 3)
        XCTAssertEqual(cartridge.mappingMode, .finalCartridgeIII)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertEqual(memory.read(0xA000), 0xA0)
        XCTAssertEqual(memory.read(0xDE00), 0xD0)
        XCTAssertEqual(memory.read(0xDFFF), 0xD0)

        memory.write(0xDFFF, value: 0x42)

        XCTAssertEqual(memory.read(0x8000), 0x32)
        XCTAssertEqual(memory.read(0xA000), 0xC2)
        XCTAssertEqual(memory.read(0xDE00), 0xD2)
        XCTAssertEqual(memory.read(0xDFFF), 0xD2)
    }

    func testFinalCartridgeIIILineControlCanExposeLowerROMOnlyOrDisableROM() throws {
        let crt = makeCRT(
            hardwareType: 3,
            exrom: 1,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x21, high: 0xB1, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make16KBank(low: 0x32, high: 0xC2, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make16KBank(low: 0x43, high: 0xD3, io: 0xD3))
            ]
        )
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        memory.ram[0x8000] = 0x44
        memory.basicROM[0] = 0xBA

        memory.write(0xDFFF, value: 0x60)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertEqual(memory.read(0xA000), 0xBA)

        memory.write(0xDFFF, value: 0x70)
        XCTAssertEqual(memory.read(0x8000), 0x44)
        XCTAssertEqual(memory.read(0xA000), 0xBA)
    }

    func testFinalCartridgeIIIRegisterHideIgnoresLaterBankWritesUntilReset() throws {
        let crt = makeCRT(
            hardwareType: 3,
            exrom: 1,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x21, high: 0xB1, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make16KBank(low: 0x32, high: 0xC2, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make16KBank(low: 0x43, high: 0xD3, io: 0xD3))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))

        c64.memory.write(0xDFFF, value: 0xC2)
        XCTAssertEqual(c64.memory.read(0x8000), 0x32)

        c64.memory.write(0xDFFF, value: 0x40)
        XCTAssertEqual(c64.memory.read(0x8000), 0x32)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x10)
    }

    func testFinalCartridgeIIIDFFFBit6DrivesCPUNMILine() throws {
        let crt = makeCRT(
            hardwareType: 3,
            exrom: 1,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x21, high: 0xB1, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make16KBank(low: 0x32, high: 0xC2, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make16KBank(low: 0x43, high: 0xD3, io: 0xD3))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        XCTAssertFalse(c64.cpu.nmiLine)

        c64.memory.write(0xDFFF, value: 0x00)
        XCTAssertTrue(c64.cpu.nmiLine)

        c64.memory.write(0xDFFF, value: 0x40)
        XCTAssertFalse(c64.cpu.nmiLine)
    }

    func testFinalCartridgeIIIHiddenRegisterKeepsNMILineUntilReset() throws {
        let crt = makeCRT(
            hardwareType: 3,
            exrom: 1,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x21, high: 0xB1, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make16KBank(low: 0x32, high: 0xC2, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make16KBank(low: 0x43, high: 0xD3, io: 0xD3))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))

        c64.memory.write(0xDFFF, value: 0x82)
        XCTAssertTrue(c64.cpu.nmiLine)

        c64.memory.write(0xDFFF, value: 0x40)
        XCTAssertTrue(c64.cpu.nmiLine)

        c64.reset()
        XCTAssertFalse(c64.cpu.nmiLine)
    }

    func testFinalCartridgeIIIRejectsIncompleteBankSet() {
        let crt = makeCRT(
            hardwareType: 3,
            exrom: 1,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x21, high: 0xB1, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make16KBank(low: 0x32, high: 0xC2, io: 0xD2))
            ]
        )

        XCTAssertNil(Cartridge.parseCRT(crt))
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

    func testParsesMagicFormelCRTAndBanksKernalWindowThroughIO2() throws {
        let crt = makeCRT(
            hardwareType: 14,
            exrom: 1,
            game: 0,
            chips: (0..<8).map { bank in
                (bank: UInt16(bank), address: UInt16(0xE000), data: Array(repeating: UInt8(0xE0 + bank), count: 0x2000))
            }
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.kernalROM[0] = 0xFE

        XCTAssertEqual(cartridge.hardwareType, 14)
        XCTAssertEqual(cartridge.mappingMode, .magicFormel)
        XCTAssertEqual(memory.read(0xE000), 0xE0)

        memory.write(0xDF03, value: 0x00)
        XCTAssertEqual(memory.read(0xE000), 0xE3)

        memory.write(0xDF07, value: 0x00)
        XCTAssertEqual(memory.read(0xE000), 0xE7)
    }

    func testMagicFormelFFToDF00DisablesUntilBankWriteOrReset() throws {
        let crt = makeCRT(
            hardwareType: 14,
            exrom: 1,
            game: 0,
            chips: (0..<8).map { bank in
                (bank: UInt16(bank), address: UInt16(0xE000), data: Array(repeating: UInt8(0xE0 + bank), count: 0x2000))
            }
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.kernalROM[0] = 0xFE

        c64.memory.write(0xDF04, value: 0x00)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE4)

        c64.memory.write(0xDF00, value: 0xFF)
        XCTAssertEqual(c64.memory.read(0xE000), 0xFE)

        c64.memory.write(0xDF02, value: 0x00)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE2)

        c64.memory.write(0xDF00, value: 0xFF)
        c64.reset()
        XCTAssertEqual(c64.memory.read(0xE000), 0xE0)
    }

    func testMagicFormelRejectsIncompleteOrMisplacedBanks() {
        let incompleteCRT = makeCRT(
            hardwareType: 14,
            exrom: 1,
            game: 0,
            chips: (0..<7).map { bank in
                (bank: UInt16(bank), address: UInt16(0xE000), data: Array(repeating: UInt8(0xE0 + bank), count: 0x2000))
            }
        )
        let misplacedCRT = makeCRT(
            hardwareType: 14,
            exrom: 1,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0xE0, count: 0x2000))
            ]
        )

        XCTAssertNil(Cartridge.parseCRT(incompleteCRT))
        XCTAssertNil(Cartridge.parseCRT(misplacedCRT))
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

    func testParsesSuperGamesCRTAndBanks16KThroughDF00() throws {
        let crt = makeCRT(
            hardwareType: 8,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x21, high: 0xB1, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make16KBank(low: 0x32, high: 0xC2, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make16KBank(low: 0x43, high: 0xD3, io: 0xD3))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge

        XCTAssertEqual(cartridge.hardwareType, 8)
        XCTAssertEqual(cartridge.mappingMode, .superGames)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertEqual(memory.read(0xA000), 0xA0)

        memory.write(0xDF00, value: 0x02)
        XCTAssertEqual(memory.read(0x8000), 0x32)
        XCTAssertEqual(memory.read(0xA000), 0xC2)

        memory.write(0xDF00, value: 0x03)
        XCTAssertEqual(memory.read(0x8000), 0x43)
        XCTAssertEqual(memory.read(0xA000), 0xD3)
    }

    func testSuperGamesCanDisableAndWriteProtectUntilReset() throws {
        let crt = makeCRT(
            hardwareType: 8,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x21, high: 0xB1, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make16KBank(low: 0x32, high: 0xC2, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make16KBank(low: 0x43, high: 0xD3, io: 0xD3))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.ram[0x8000] = 0x44
        c64.memory.basicROM[0] = 0xBA

        c64.memory.write(0xDF00, value: 0x0E)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)
        XCTAssertEqual(c64.memory.read(0xA000), 0xBA)

        c64.memory.write(0xDF00, value: 0x01)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)
        XCTAssertEqual(c64.memory.read(0xA000), 0xBA)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x10)
        XCTAssertEqual(c64.memory.read(0xA000), 0xA0)
    }

    func testSuperGamesRejectsIncompleteOrMisplacedBanks() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 8,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x21, high: 0xB1, io: 0xD1))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 8,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0xA000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0))
            ]
        )))
    }

    func testParsesAtomicPowerCRTAndBanksROMThroughIO1() throws {
        let crt = makeCRT(
            hardwareType: 9,
            exrom: 0,
            game: 1,
            chips: makeAtomicPowerChips()
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.basicROM[0] = 0xBA

        XCTAssertEqual(cartridge.hardwareType, 9)
        XCTAssertEqual(cartridge.mappingMode, .atomicPower)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xA000), 0xBA)
        XCTAssertEqual(memory.read(0xDF00), 0xD0)

        memory.write(0xDE00, value: 0x18)
        XCTAssertEqual(memory.read(0x8000), 0x83)
        XCTAssertEqual(memory.read(0xE000), 0x83)
        XCTAssertEqual(memory.read(0xDF00), 0xD3)

        memory.write(0xDE00, value: 0x11)
        XCTAssertEqual(memory.read(0x8000), 0x82)
        XCTAssertEqual(memory.read(0xA000), 0x82)
    }

    func testAtomicPowerRAMOverlayAndIO2Window() throws {
        let crt = makeCRT(
            hardwareType: 9,
            exrom: 0,
            game: 1,
            chips: makeAtomicPowerChips()
        )
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))

        memory.write(0xDE00, value: 0x20)
        memory.write(0x8000, value: 0x5A)
        memory.write(0xDFFF, value: 0x6B)
        XCTAssertEqual(memory.read(0x8000), 0x5A)
        XCTAssertEqual(memory.read(0xDFFF), 0x6B)

        memory.write(0xDE00, value: 0x22)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        memory.write(0xA000, value: 0x7C)
        memory.write(0xDF00, value: 0x8D)
        XCTAssertEqual(memory.read(0xA000), 0x7C)
        XCTAssertEqual(memory.read(0xDF00), 0x8D)
    }

    func testAtomicPowerDisableResetAndFreezeState() throws {
        let crt = makeCRT(
            hardwareType: 9,
            exrom: 0,
            game: 1,
            chips: makeAtomicPowerChips()
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.ram[0x8000] = 0x44

        c64.memory.write(0xDE00, value: 0x04)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)
        XCTAssertNotEqual(c64.memory.read(0xDF00), 0xD0)

        c64.memory.write(0xDE00, value: 0x18)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x80)

        c64.memory.write(0xDE00, value: 0x04)
        c64.pressCartridgeFreezeButton()
        c64.memory.write(0x8000, value: 0x66)
        XCTAssertEqual(c64.memory.read(0x8000), 0x66)
        XCTAssertEqual(c64.memory.read(0xE000), 0x80)
    }

    func testAtomicPowerRejectsIncompleteMisplacedOrWrongSizeImages() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 9,
            exrom: 0,
            game: 1,
            chips: Array(makeAtomicPowerChips().dropLast())
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 9,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make8KBank(first: 0x80, io: 0xD0)),
                (bank: 1, address: 0xA000, data: make8KBank(first: 0x81, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make8KBank(first: 0x82, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make8KBank(first: 0x83, io: 0xD3))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 9,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x1000)),
                (bank: 1, address: 0x8000, data: make8KBank(first: 0x81, io: 0xD1)),
                (bank: 2, address: 0x8000, data: make8KBank(first: 0x82, io: 0xD2)),
                (bank: 3, address: 0x8000, data: make8KBank(first: 0x83, io: 0xD3))
            ]
        )))
    }

    func testParsesDinamicCRTAndBanksROMLThroughIO1Reads() throws {
        let crt = makeCRT(
            hardwareType: 17,
            exrom: 0,
            game: 1,
            chips: makeDinamicChips()
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.basicROM[0] = 0xBA

        XCTAssertEqual(cartridge.hardwareType, 17)
        XCTAssertEqual(cartridge.mappingMode, .dinamic)
        XCTAssertEqual(memory.read(0x8000), 0x50)
        XCTAssertEqual(memory.read(0xA000), 0xBA)

        memory.write(0xD020, value: 0x5A)
        XCTAssertEqual(memory.read(0xDE0F), 0x5A)
        XCTAssertEqual(memory.read(0x8000), 0x5F)

        XCTAssertEqual(memory.read(0xDE03), 0x5F)
        XCTAssertEqual(memory.read(0x8000), 0x53)
    }

    func testDinamicRejectsIncompleteMisplacedOrOutOfRangeImages() {
        var incomplete = makeDinamicChips()
        incomplete.removeLast()
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 17,
            exrom: 0,
            game: 1,
            chips: incomplete
        )))

        var misplaced = makeDinamicChips()
        misplaced[0] = (bank: 0, address: 0xA000, data: Array(repeating: 0x50, count: 0x2000))
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 17,
            exrom: 0,
            game: 1,
            chips: misplaced
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 17,
            exrom: 0,
            game: 1,
            chips: [(bank: 16, address: 0x8000, data: Array(repeating: 0x50, count: 0x2000))]
        )))
    }

    func testParsesZaxxonCRTAndSelectsUpperBanksThroughFixedROMReads() throws {
        let crt = makeCRT(
            hardwareType: 18,
            exrom: 0,
            game: 0,
            chips: makeZaxxonChips()
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge

        XCTAssertEqual(cartridge.hardwareType, 18)
        XCTAssertEqual(cartridge.mappingMode, .zaxxon)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0x9000), 0x80)
        XCTAssertEqual(memory.read(0xA000), 0xB1)

        _ = memory.read(0x8001)
        XCTAssertEqual(memory.read(0xA000), 0xA0)

        _ = memory.read(0x9001)
        XCTAssertEqual(memory.read(0xA000), 0xB1)
    }

    func testZaxxonRejectsIncompleteMisplacedOrDuplicateImages() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 18,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x1000)),
                (bank: 0, address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 18,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x2000)),
                (bank: 0, address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000)),
                (bank: 1, address: 0xA000, data: Array(repeating: 0xB1, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 18,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x1000)),
                (bank: 0, address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000)),
                (bank: 0, address: 0xA000, data: Array(repeating: 0xB1, count: 0x2000))
            ]
        )))
    }

    func testParsesSuperSnapshotV5CRTAndBanksROMThroughIO1Writes() throws {
        let crt = makeCRT(
            hardwareType: 20,
            exrom: 1,
            game: 0,
            chips: makeSuperSnapshotV5Chips(count: 4)
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge

        XCTAssertEqual(cartridge.hardwareType, 20)
        XCTAssertEqual(cartridge.mappingMode, .superSnapshotV5)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xE000), 0x90)
        XCTAssertEqual(memory.read(0xDE00), 0xA0)

        memory.write(0xDE00, value: 0x06)
        XCTAssertEqual(memory.read(0x8000), 0x81)
        XCTAssertEqual(memory.read(0xE000), 0x91)
        XCTAssertEqual(memory.read(0xDE00), 0xA1)

        memory.write(0xDE00, value: 0x12)
        XCTAssertEqual(memory.read(0x8000), 0x82)
        XCTAssertEqual(memory.read(0xE000), 0x92)
    }

    func testSuperSnapshotV5RAMOverlayAndReleaseMode() throws {
        let crt = makeCRT(
            hardwareType: 20,
            exrom: 1,
            game: 0,
            chips: makeSuperSnapshotV5Chips(count: 4)
        )
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        memory.kernalROM[0] = 0xFE

        memory.write(0xDE00, value: 0x00)
        memory.write(0x8000, value: 0x5A)
        XCTAssertEqual(memory.read(0x8000), 0x5A)
        XCTAssertEqual(memory.read(0xDE00), 0xA0)

        memory.write(0xDE00, value: 0x03)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xA000), 0x90)
        XCTAssertEqual(memory.read(0xE000), 0xFE)
    }

    func testSuperSnapshotV5Accepts128KROMAndUsesHighBankBit() throws {
        let fourBankCRT = makeCRT(
            hardwareType: 20,
            exrom: 1,
            game: 0,
            chips: makeSuperSnapshotV5Chips(count: 4)
        )
        var fourBankCartridge = try XCTUnwrap(Cartridge.parseCRT(fourBankCRT))
        fourBankCartridge.writeIO1(0xDE00, value: 0x32)
        XCTAssertEqual(fourBankCartridge.read(0x8000), 0x82)

        let eightBankCRT = makeCRT(
            hardwareType: 20,
            exrom: 1,
            game: 0,
            chips: makeSuperSnapshotV5Chips(count: 8)
        )
        var eightBankCartridge = try XCTUnwrap(Cartridge.parseCRT(eightBankCRT))
        eightBankCartridge.writeIO1(0xDE00, value: 0x32)
        XCTAssertEqual(eightBankCartridge.read(0x8000), 0x86)
    }

    func testSuperSnapshotV5DisableIgnoresIO1UntilResetOrFreeze() throws {
        let crt = makeCRT(
            hardwareType: 20,
            exrom: 1,
            game: 0,
            chips: makeSuperSnapshotV5Chips(count: 4)
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))

        c64.memory.write(0xDE00, value: 0x0A)
        XCTAssertNotEqual(c64.memory.read(0x8000), 0x80)
        XCTAssertNotEqual(c64.memory.read(0xDE00), 0xA0)

        c64.memory.write(0xDE00, value: 0x06)
        XCTAssertNotEqual(c64.memory.read(0x8000), 0x81)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x80)

        c64.memory.write(0xDE00, value: 0x0A)
        c64.pressCartridgeFreezeButton()
        c64.memory.write(0x8000, value: 0x66)
        XCTAssertEqual(c64.memory.read(0x8000), 0x66)
    }

    func testSuperSnapshotV5RejectsMissingMisplacedDuplicateOrWrongSizeBanks() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 20,
            exrom: 1,
            game: 0,
            chips: Array(makeSuperSnapshotV5Chips(count: 4).dropLast())
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 20,
            exrom: 1,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x80, high: 0x90, io: 0xA0)),
                (bank: 1, address: 0xA000, data: make16KBank(low: 0x81, high: 0x91, io: 0xA1)),
                (bank: 2, address: 0x8000, data: make16KBank(low: 0x82, high: 0x92, io: 0xA2)),
                (bank: 3, address: 0x8000, data: make16KBank(low: 0x83, high: 0x93, io: 0xA3))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 20,
            exrom: 1,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x80, high: 0x90, io: 0xA0)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x81, high: 0x91, io: 0xA1)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x82, high: 0x92, io: 0xA2)),
                (bank: 3, address: 0x8000, data: make16KBank(low: 0x83, high: 0x93, io: 0xA3))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 20,
            exrom: 1,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x2000)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x81, high: 0x91, io: 0xA1)),
                (bank: 2, address: 0x8000, data: make16KBank(low: 0x82, high: 0x92, io: 0xA2)),
                (bank: 3, address: 0x8000, data: make16KBank(low: 0x83, high: 0x93, io: 0xA3))
            ]
        )))
    }

    func testParsesComal80CRTAndBanks16KThroughIO1Writes() throws {
        let crt = makeCRT(
            hardwareType: 21,
            exrom: 0,
            game: 0,
            chips: makeComal80Chips(count: 4)
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge

        XCTAssertEqual(cartridge.hardwareType, 21)
        XCTAssertEqual(cartridge.mappingMode, .comal80)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xA000), 0x90)

        memory.write(0xDEFE, value: 0x02)
        XCTAssertEqual(memory.read(0x8000), 0x82)
        XCTAssertEqual(memory.read(0xA000), 0x92)

        memory.write(0xDE00, value: 0x40)
        memory.ram[0x8000] = 0x44
        XCTAssertEqual(memory.read(0x8000), 0x44)
        XCTAssertNotEqual(memory.read(0xA000), 0x92)

        memory.write(0xDE00, value: 0x01)
        XCTAssertEqual(memory.read(0x8000), 0x81)
        XCTAssertEqual(memory.read(0xA000), 0x91)
    }

    func testComal80AcceptsOptionalExtraROMBanksAndResetRestoresBankZero() throws {
        let crt = makeCRT(
            hardwareType: 21,
            exrom: 0,
            game: 0,
            chips: makeComal80Chips(count: 8)
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))

        c64.memory.write(0xDE00, value: 0x06)
        XCTAssertEqual(c64.memory.read(0x8000), 0x86)
        XCTAssertEqual(c64.memory.read(0xA000), 0x96)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x80)
        XCTAssertEqual(c64.memory.read(0xA000), 0x90)
    }

    func testComal80RejectsMissingMisplacedDuplicateOrWrongSizeBanks() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 21,
            exrom: 0,
            game: 0,
            chips: Array(makeComal80Chips(count: 4).dropLast())
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 21,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x80, high: 0x90, io: 0xA0)),
                (bank: 1, address: 0xA000, data: make16KBank(low: 0x81, high: 0x91, io: 0xA1)),
                (bank: 2, address: 0x8000, data: make16KBank(low: 0x82, high: 0x92, io: 0xA2)),
                (bank: 3, address: 0x8000, data: make16KBank(low: 0x83, high: 0x93, io: 0xA3))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 21,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x80, high: 0x90, io: 0xA0)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x81, high: 0x91, io: 0xA1)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x82, high: 0x92, io: 0xA2)),
                (bank: 3, address: 0x8000, data: make16KBank(low: 0x83, high: 0x93, io: 0xA3))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 21,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x2000)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x81, high: 0x91, io: 0xA1)),
                (bank: 2, address: 0x8000, data: make16KBank(low: 0x82, high: 0x92, io: 0xA2)),
                (bank: 3, address: 0x8000, data: make16KBank(low: 0x83, high: 0x93, io: 0xA3))
            ]
        )))
    }

    func testParsesStructuredBasicCRTAndSwitchesThroughIO1Accesses() throws {
        let crt = makeCRT(
            hardwareType: 22,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x2000)),
                (bank: 1, address: 0x8000, data: Array(repeating: 0x91, count: 0x2000))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.ram[0x8000] = 0x44

        XCTAssertEqual(cartridge.hardwareType, 22)
        XCTAssertEqual(cartridge.mappingMode, .structuredBasic)
        XCTAssertEqual(memory.read(0x8000), 0x80)

        memory.write(0xDE02, value: 0x00)
        XCTAssertEqual(memory.read(0x8000), 0x91)

        memory.write(0xD020, value: 0x5A)
        XCTAssertEqual(memory.read(0xDE00), 0x5A)
        XCTAssertEqual(memory.read(0x8000), 0x80)

        XCTAssertEqual(memory.read(0xDE03), 0x80)
        XCTAssertEqual(memory.read(0x8000), 0x44)

        memory.write(0xDE01, value: 0x00)
        XCTAssertEqual(memory.read(0x8000), 0x80)
    }

    func testStructuredBasicRejectsIncompleteOrMisplacedBanks() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 22,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 22,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0xA000, data: Array(repeating: 0x80, count: 0x2000)),
                (bank: 1, address: 0x8000, data: Array(repeating: 0x91, count: 0x2000))
            ]
        )))
    }

    func testParsesRossCRTAndReadSelectsBankOrDisablesUntilReset() throws {
        let crt = makeCRT(
            hardwareType: 23,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make16KBank(low: 0x21, high: 0xB1, io: 0xD1))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.ram[0x8000] = 0x44
        c64.memory.basicROM[0] = 0xBA
        let cartridge = try XCTUnwrap(c64.memory.cartridge)

        XCTAssertEqual(cartridge.hardwareType, 23)
        XCTAssertEqual(cartridge.mappingMode, .ross)
        XCTAssertEqual(c64.memory.read(0x8000), 0x10)
        XCTAssertEqual(c64.memory.read(0xA000), 0xA0)

        _ = c64.memory.read(0xDE00)
        XCTAssertEqual(c64.memory.read(0x8000), 0x21)
        XCTAssertEqual(c64.memory.read(0xA000), 0xB1)

        _ = c64.memory.read(0xDF00)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)
        XCTAssertEqual(c64.memory.read(0xA000), 0xBA)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x10)
        XCTAssertEqual(c64.memory.read(0xA000), 0xA0)
    }

    func testRossAcceptsSingle16KBankAndRejectsMisplacedImages() throws {
        let crt = makeCRT(
            hardwareType: 23,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))

        XCTAssertEqual(cartridge.mappingMode, .ross)
        XCTAssertEqual(cartridge.read(0x8000), 0x10)
        XCTAssertEqual(cartridge.read(0xA000), 0xA0)

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 23,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0xA000, data: make16KBank(low: 0x10, high: 0xA0, io: 0xD0))
            ]
        )))
    }

    func testParsesDelaEP64CRTAndDecodesDocumentedBankBits() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 24,
            exrom: 0,
            game: 1,
            chips: makeDelaEP64Chips()
        )))
        c64.memory.ram[0x8000] = 0x44

        let cartridge = try XCTUnwrap(c64.memory.cartridge)
        XCTAssertEqual(cartridge.hardwareType, 24)
        XCTAssertEqual(cartridge.mappingMode, .delaEP64)
        XCTAssertEqual(c64.memory.read(0x8000), 0x60)

        c64.memory.write(0xDE00, value: 0x01)
        XCTAssertEqual(c64.memory.read(0x8000), 0x61)

        c64.memory.write(0xDE00, value: 0x31)
        XCTAssertEqual(c64.memory.read(0x8000), 0x64)

        c64.memory.write(0xDE00, value: 0x02)
        XCTAssertEqual(c64.memory.read(0x8000), 0x65)

        c64.memory.write(0xDE00, value: 0x32)
        XCTAssertEqual(c64.memory.read(0x8000), 0x68)

        c64.memory.write(0xDE00, value: 0x00)
        XCTAssertEqual(c64.memory.read(0x8000), 0x60)

        c64.memory.write(0xDE00, value: 0x80)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x60)
    }

    func testDelaEP64RejectsMissingBaseDuplicateOrMisplacedImages() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 24,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 1, address: 0x8000, data: Array(repeating: 0x61, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 24,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x60, count: 0x2000)),
                (bank: 0, address: 0x8000, data: Array(repeating: 0x61, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 24,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0xA000, data: Array(repeating: 0x60, count: 0x2000))
            ]
        )))
    }

    func testParsesDelaEP7x8CRTAndSelectsOneHotLowBanks() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 25,
            exrom: 0,
            game: 1,
            chips: makeDela8KChips(count: 8, base: 0x70)
        )))
        c64.memory.ram[0x8000] = 0x44

        let cartridge = try XCTUnwrap(c64.memory.cartridge)
        XCTAssertEqual(cartridge.hardwareType, 25)
        XCTAssertEqual(cartridge.mappingMode, .delaEP7x8)
        XCTAssertEqual(c64.memory.read(0x8000), 0x70)

        c64.memory.write(0xDE00, value: 0xFE)
        XCTAssertEqual(c64.memory.read(0x8000), 0x70)

        c64.memory.write(0xDE00, value: 0xFD)
        XCTAssertEqual(c64.memory.read(0x8000), 0x71)

        c64.memory.write(0xDE00, value: 0x7F)
        XCTAssertEqual(c64.memory.read(0x8000), 0x77)

        c64.memory.write(0xDE00, value: 0xFF)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x70)
    }

    func testDelaEP7x8RejectsMissingMisplacedOrOutOfRangeImages() {
        var missing = makeDela8KChips(count: 4, base: 0x70)
        missing.remove(at: 1)
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 25,
            exrom: 0,
            game: 1,
            chips: missing
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 25,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0xA000, data: Array(repeating: 0x70, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 25,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 8, address: 0x8000, data: Array(repeating: 0x78, count: 0x2000))
            ]
        )))
    }

    func testParsesDelaEP256CRTAndDecodesBankWindows() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 26,
            exrom: 0,
            game: 1,
            chips: makeDela8KChips(count: 33, base: 0x30)
        )))
        c64.memory.ram[0x8000] = 0x44

        let cartridge = try XCTUnwrap(c64.memory.cartridge)
        XCTAssertEqual(cartridge.hardwareType, 26)
        XCTAssertEqual(cartridge.mappingMode, .delaEP256)
        XCTAssertEqual(c64.memory.read(0x8000), 0x30)

        c64.memory.write(0xDE00, value: 0x38)
        XCTAssertEqual(c64.memory.read(0x8000), 0x31)

        c64.memory.write(0xDE00, value: 0x3F)
        XCTAssertEqual(c64.memory.read(0x8000), 0x38)

        c64.memory.write(0xDE00, value: 0x28)
        XCTAssertEqual(c64.memory.read(0x8000), 0x39)

        c64.memory.write(0xDE00, value: 0x1F)
        XCTAssertEqual(c64.memory.read(0x8000), 0x48)

        c64.memory.write(0xDE00, value: 0x08)
        XCTAssertEqual(c64.memory.read(0x8000), 0x49)

        c64.memory.write(0xDE00, value: 0x0F)
        XCTAssertEqual(c64.memory.read(0x8000), 0x50)

        c64.memory.write(0xDE00, value: 0x20)
        XCTAssertEqual(c64.memory.read(0x8000), 0x30)

        c64.memory.write(0xDE00, value: 0x80)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)
    }

    func testDelaEP256RejectsMissingMisplacedOrOutOfRangeImages() {
        var missing = makeDela8KChips(count: 5, base: 0x30)
        missing.remove(at: 2)
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 26,
            exrom: 0,
            game: 1,
            chips: missing
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 26,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0xA000, data: Array(repeating: 0x30, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 26,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 33, address: 0x8000, data: Array(repeating: 0x51, count: 0x2000))
            ]
        )))
    }

    func testParsesRexEP256CRTAndBanksVariableEPROMsThroughIO2() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 27,
            exrom: 0,
            game: 1,
            chips: makeRexEP256Chips()
        )))
        c64.memory.ram[0x8000] = 0x44

        let cartridge = try XCTUnwrap(c64.memory.cartridge)
        XCTAssertEqual(cartridge.hardwareType, 27)
        XCTAssertEqual(cartridge.mappingMode, .rexEP256)
        XCTAssertEqual(c64.memory.read(0x8000), 0x90)

        c64.memory.write(0xDFA0, value: 0x00)
        XCTAssertEqual(c64.memory.read(0x8000), 0xA0)

        c64.memory.write(0xDFA0, value: 0x01)
        XCTAssertEqual(c64.memory.read(0x8000), 0xB0)

        c64.memory.write(0xDFA0, value: 0x11)
        XCTAssertEqual(c64.memory.read(0x8000), 0xB1)

        c64.memory.write(0xDFA0, value: 0x02)
        XCTAssertEqual(c64.memory.read(0x8000), 0xC0)

        c64.memory.write(0xDFA0, value: 0x12)
        XCTAssertEqual(c64.memory.read(0x8000), 0xC1)

        c64.memory.write(0xDFA0, value: 0x22)
        XCTAssertEqual(c64.memory.read(0x8000), 0xC2)

        c64.memory.write(0xDFA0, value: 0x32)
        XCTAssertEqual(c64.memory.read(0x8000), 0xC3)

        XCTAssertEqual(c64.memory.read(0xDFC0), 0xC3)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        _ = c64.memory.read(0xDFE0)
        XCTAssertEqual(c64.memory.read(0x8000), 0xC3)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x90)
    }

    func testRexEP256MissingSocketReadsAsEmptyEPROMAndInvalidWritesPreserveBank() throws {
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(makeCRT(
            hardwareType: 27,
            exrom: 0,
            game: 1,
            chips: makeRexEP256Chips()
        )))

        memory.write(0xDFA0, value: 0x00)
        XCTAssertEqual(memory.read(0x8000), 0xA0)

        memory.write(0xDFA0, value: 0x07)
        XCTAssertEqual(memory.read(0x8000), 0xFF)

        memory.write(0xDFA0, value: 0x08)
        XCTAssertEqual(memory.read(0x8000), 0xFF)

        memory.write(0xDFA0, value: 0x42)
        XCTAssertEqual(memory.read(0x8000), 0xFF)
    }

    func testRexEP256RejectsMissingBaseDuplicateOrMisplacedImages() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 27,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 1, address: 0x8000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 27,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x90, count: 0x2000)),
                (bank: 1, address: 0x8000, data: Array(repeating: 0xA0, count: 0x2000)),
                (bank: 1, address: 0x8000, data: Array(repeating: 0xA1, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 27,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x90, count: 0x2000)),
                (bank: 1, address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 27,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x90, count: 0x2000)),
                (bank: 9, address: 0x8000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )))
    }

    func testParsesMikroAssemblerCRTAndMirrorsROMIntoIO() throws {
        let crt = makeCRT(
            hardwareType: 28,
            exrom: 0,
            game: 1,
            chips: [
                (address: 0x8000, data: makeMikroAssemblerImage())
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge

        XCTAssertEqual(cartridge.hardwareType, 28)
        XCTAssertEqual(cartridge.mappingMode, .mikroAssembler)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xDE00), 0xDE)
        XCTAssertEqual(memory.read(0xDFFF), 0xDF)
    }

    func testMikroAssemblerRejectsSplitOrShortImages() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 28,
            exrom: 0,
            game: 1,
            chips: [
                (address: 0x8000, data: Array(repeating: 0x80, count: 0x1000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 28,
            exrom: 0,
            game: 1,
            chips: [
                (address: 0x8000, data: Array(repeating: 0x80, count: 0x2000)),
                (address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )))
    }

    func testParsesEpyxFastLoadCRTAndMapsROMLAndIO2LastPage() throws {
        var rom = [UInt8](repeating: 0xFF, count: 0x2000)
        rom[0x0000] = 0x42
        rom[0x1F7A] = 0x7A
        let crt = makeCRT(
            hardwareType: 10,
            exrom: 0,
            game: 1,
            chips: [
                (address: 0x8000, data: rom)
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.basicROM[0] = 0xBA

        XCTAssertEqual(cartridge.hardwareType, 10)
        XCTAssertEqual(cartridge.mappingMode, .epyxFastLoad)
        XCTAssertEqual(memory.read(0x8000), 0x42)
        XCTAssertEqual(memory.read(0xDF7A), 0x7A)
        XCTAssertEqual(memory.read(0xA000), 0xBA)
    }

    func testEpyxFastLoadROMTimesOutAndIO1ReadReenablesIt() throws {
        var rom = [UInt8](repeating: 0xFF, count: 0x2000)
        rom[0x0000] = 0x42
        let crt = makeCRT(
            hardwareType: 10,
            exrom: 0,
            game: 1,
            chips: [
                (address: 0x8000, data: rom)
            ]
        )
        var cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))

        XCTAssertEqual(cartridge.read(0x8000), 0x42)

        cartridge.tick(cycles: 512)
        XCTAssertNil(cartridge.read(0x8000))

        XCTAssertNil(cartridge.readIO(0xDE00))
        XCTAssertEqual(cartridge.read(0x8000), 0x42)
    }

    func testC64CycleTickAdvancesEpyxFastLoadTimeout() throws {
        var rom = [UInt8](repeating: 0xFF, count: 0x2000)
        rom[0x0000] = 0x42
        let crt = makeCRT(
            hardwareType: 10,
            exrom: 0,
            game: 1,
            chips: [
                (address: 0x8000, data: rom)
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))

        XCTAssertEqual(c64.memory.read(0x8000), 0x42)

        for _ in 0..<512 {
            c64.tickOneCycle()
        }

        XCTAssertNil(c64.memory.cartridge?.read(0x8000))
    }

    func testEpyxFastLoadRejectsUpperROMHImages() {
        let crt = makeCRT(
            hardwareType: 10,
            exrom: 0,
            game: 1,
            chips: [
                (address: 0x8000, data: Array(repeating: 0x80, count: 0x2000)),
                (address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )

        XCTAssertNil(Cartridge.parseCRT(crt))
    }

    func testParsesC64GameSystemCRTAndBanksThroughIO1AddressWrites() throws {
        let crt = makeCRT(
            hardwareType: 15,
            exrom: 0,
            game: 1,
            chips: makeC64GameSystemChips()
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.basicROM[0] = 0xBA

        XCTAssertEqual(cartridge.hardwareType, 15)
        XCTAssertEqual(cartridge.mappingMode, .c64GameSystem)
        XCTAssertEqual(memory.read(0x8000), 0x40)
        XCTAssertEqual(memory.read(0x9FFF), 0x40)
        XCTAssertEqual(memory.read(0xA000), 0xBA)

        memory.write(0xDE03, value: 0x00)
        XCTAssertEqual(memory.read(0x8000), 0x43)

        memory.write(0xDE3F, value: 0x00)
        XCTAssertEqual(memory.read(0x8000), 0x7F)
    }

    func testC64GameSystemIO1AddressReadsAlsoSelectBanksAndReturnOpenBus() throws {
        let crt = makeCRT(
            hardwareType: 15,
            exrom: 0,
            game: 1,
            chips: makeC64GameSystemChips()
        )
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))

        memory.write(0xD020, value: 0x5A)

        XCTAssertEqual(memory.read(0xDE21), 0x5A)
        XCTAssertEqual(memory.read(0x8000), 0x61)
    }

    func testC64GameSystemRejectsIncompleteMisplacedOrOutOfRangeImages() {
        var incomplete = makeC64GameSystemChips()
        incomplete.removeLast()
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 15,
            exrom: 0,
            game: 1,
            chips: incomplete
        )))

        var misplaced = makeC64GameSystemChips()
        misplaced[0] = (bank: 0, address: 0xA000, data: Array(repeating: 0x40, count: 0x2000))
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 15,
            exrom: 0,
            game: 1,
            chips: misplaced
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 15,
            exrom: 0,
            game: 1,
            chips: [(bank: 64, address: 0x8000, data: Array(repeating: 0x40, count: 0x2000))]
        )))
    }

    func testParsesWarpSpeedCRTAndMirrorsROMLLast512BytesIntoIO() throws {
        let crt = makeCRT(
            hardwareType: 16,
            exrom: 0,
            game: 0,
            chips: [
                (address: 0x8000, data: makeWarpSpeedImage())
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge

        XCTAssertEqual(cartridge.hardwareType, 16)
        XCTAssertEqual(cartridge.mappingMode, .warpSpeed)
        XCTAssertEqual(memory.read(0x8000), 0x80)
        XCTAssertEqual(memory.read(0xA000), 0xA0)
        XCTAssertEqual(memory.read(0xDE00), 0xDE)
        XCTAssertEqual(memory.read(0xDFFF), 0xDF)
    }

    func testWarpSpeedIO2DisablesROMWindowButKeepsIOMappedUntilIO1ReenableOrReset() throws {
        let crt = makeCRT(
            hardwareType: 16,
            exrom: 0,
            game: 0,
            chips: [
                (address: 0x8000, data: makeWarpSpeedImage())
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.ram[0x8000] = 0x44
        c64.memory.basicROM[0] = 0xBA

        c64.memory.write(0xDF00, value: 0x00)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)
        XCTAssertEqual(c64.memory.read(0xA000), 0xBA)
        XCTAssertEqual(c64.memory.read(0xDE00), 0xDE)
        XCTAssertEqual(c64.memory.read(0xDFFF), 0xDF)

        c64.memory.write(0xDE00, value: 0x00)
        XCTAssertEqual(c64.memory.read(0x8000), 0x80)
        XCTAssertEqual(c64.memory.read(0xA000), 0xA0)

        c64.memory.write(0xDF00, value: 0x00)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x80)
        XCTAssertEqual(c64.memory.read(0xA000), 0xA0)
    }

    func testWarpSpeedRejectsSplitOrShortImages() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 16,
            exrom: 0,
            game: 0,
            chips: [
                (address: 0x8000, data: Array(repeating: 0x80, count: 0x2000)),
                (address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 16,
            exrom: 0,
            game: 0,
            chips: [
                (address: 0x8000, data: Array(repeating: 0x80, count: 0x2000))
            ]
        )))
    }

    func testParsesStardosCRTAndChargesROMLWindowThroughIO1Reads() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 31,
            exrom: 1,
            game: 0,
            chips: makeStardosChips()
        )))
        c64.memory.ram[0x8000] = 0x44
        c64.memory.kernalROM[0] = 0xFE

        let cartridge = try XCTUnwrap(c64.memory.cartridge)
        XCTAssertEqual(cartridge.hardwareType, 31)
        XCTAssertEqual(cartridge.mappingMode, .stardos)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE0)

        for _ in 0..<35 {
            _ = c64.memory.read(0xDE61)
        }
        XCTAssertEqual(c64.memory.read(0x8000), 0x80)

        for _ in 0..<18 {
            _ = c64.memory.read(0xDFA1)
        }
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE0)

        c64.memory.ram[0xE000] = 0xEE
        c64.memory.write(0x0001, value: 0x35)
        XCTAssertEqual(c64.memory.read(0xE000), 0xEE)
        c64.memory.write(0x0001, value: 0x37)
    }

    func testStardosWritesAlsoChargeAndDischargeControlCapacitor() throws {
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(makeCRT(
            hardwareType: 31,
            exrom: 1,
            game: 0,
            chips: makeStardosChips()
        )))
        memory.ram[0x8000] = 0x44

        for _ in 0..<35 {
            memory.write(0xDE00, value: 0x00)
        }
        XCTAssertEqual(memory.read(0x8000), 0x80)

        for _ in 0..<18 {
            memory.write(0xDF00, value: 0x00)
        }
        XCTAssertEqual(memory.read(0x8000), 0x44)
    }

    func testStardosRejectsMissingMisplacedOrExtraImages() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 31,
            exrom: 1,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 31,
            exrom: 1,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x2000)),
                (bank: 0, address: 0xA000, data: Array(repeating: 0xE0, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 31,
            exrom: 1,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x2000)),
                (bank: 0, address: 0xE000, data: Array(repeating: 0xE0, count: 0x2000)),
                (bank: 1, address: 0xE000, data: Array(repeating: 0xE1, count: 0x2000))
            ]
        )))
    }

    func testParsesGameKillerCRTAndMapsOnlyKernalWindow() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 42,
            exrom: 1,
            game: 0,
            chips: makeGameKillerChips()
        )))
        c64.memory.ram[0x8000] = 0x44
        c64.memory.kernalROM[0] = 0xFE

        let cartridge = try XCTUnwrap(c64.memory.cartridge)
        XCTAssertEqual(cartridge.hardwareType, 42)
        XCTAssertEqual(cartridge.mappingMode, .gameKiller)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE2)
    }

    func testGameKillerDisablesAfterTwoIOWritesAndResetReenables() {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 42,
            exrom: 1,
            game: 0,
            chips: makeGameKillerChips()
        )))
        c64.memory.kernalROM[0] = 0xFE

        c64.memory.write(0xDE00, value: 0x00)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE2)

        c64.memory.write(0xDF00, value: 0x00)
        XCTAssertEqual(c64.memory.read(0xE000), 0xFE)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0xE000), 0xE2)
    }

    func testGameKillerRejectsMissingMisplacedOrExtraImages() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 42,
            exrom: 1,
            game: 0,
            chips: [(bank: UInt16, address: UInt16, data: [UInt8])]()
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 42,
            exrom: 1,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0xE2, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 42,
            exrom: 1,
            game: 0,
            chips: [
                (bank: 0, address: 0xE000, data: Array(repeating: 0xE2, count: 0x2000)),
                (bank: 1, address: 0xE000, data: Array(repeating: 0xE3, count: 0x2000))
            ]
        )))
    }

    func testParsesProphet64CRTAndBanksROMLThroughIO2() throws {
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(makeCRT(
            hardwareType: 43,
            exrom: 0,
            game: 1,
            chips: makeProphet64Chips()
        )))
        memory.basicROM[0] = 0xBA

        XCTAssertEqual(memory.cartridge?.hardwareType, 43)
        XCTAssertEqual(memory.cartridge?.mappingMode, .prophet64)
        XCTAssertEqual(memory.read(0x8000), 0x40)
        XCTAssertEqual(memory.read(0xA000), 0xBA)

        memory.write(0xDF00, value: 0x03)
        XCTAssertEqual(memory.read(0x8000), 0x43)

        memory.write(0xDFFF, value: 0x1F)
        XCTAssertEqual(memory.read(0x8000), 0x5F)
    }

    func testProphet64DisableBitFallsBackToRAMAndCanReenable() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 43,
            exrom: 0,
            game: 1,
            chips: makeProphet64Chips()
        )))
        c64.memory.ram[0x8000] = 0x44

        c64.memory.write(0xDF00, value: 0x23)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        c64.memory.write(0xDF00, value: 0x04)
        XCTAssertEqual(c64.memory.read(0x8000), 0x44)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x40)
    }

    func testProphet64AcceptsSparseBanksAndRejectsBadImages() throws {
        let sparse = try XCTUnwrap(Cartridge.parseCRT(makeCRT(
            hardwareType: 43,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x40, count: 0x2000)),
                (bank: 31, address: 0x8000, data: Array(repeating: 0x5F, count: 0x2000))
            ]
        )))
        var mutable = sparse
        XCTAssertEqual(mutable.read(0x8000), 0x40)
        mutable.writeIO2(0xDF00, value: 0x1F)
        XCTAssertEqual(mutable.read(0x8000), 0x5F)

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 43,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 32, address: 0x8000, data: Array(repeating: 0x60, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 43,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0xA000, data: Array(repeating: 0x40, count: 0x2000))
            ]
        )))
    }

    func testParsesEXOSCRTAndMapsKernalWindowOnlyWhenHIRAMSelected() throws {
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(makeCRT(
            hardwareType: 44,
            exrom: 1,
            game: 0,
            chips: makeEXOSChips()
        )))
        memory.kernalROM[0] = 0xFE
        memory.ram[0xE000] = 0x44

        XCTAssertEqual(memory.cartridge?.hardwareType, 44)
        XCTAssertEqual(memory.cartridge?.mappingMode, .exos)
        XCTAssertEqual(memory.read(0xE000), 0xE4)

        memory.write(0x0001, value: 0x35)
        XCTAssertEqual(memory.read(0xE000), 0x44)

        memory.write(0x0001, value: 0x37)
        XCTAssertEqual(memory.read(0xE000), 0xE4)
    }

    func testEXOSRejectsMissingMisplacedOrExtraImages() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 44,
            exrom: 1,
            game: 0,
            chips: [(bank: UInt16, address: UInt16, data: [UInt8])]()
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 44,
            exrom: 1,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0xE4, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 44,
            exrom: 1,
            game: 0,
            chips: [
                (bank: 0, address: 0xE000, data: Array(repeating: 0xE4, count: 0x2000)),
                (bank: 1, address: 0xE000, data: Array(repeating: 0xE5, count: 0x2000))
            ]
        )))
    }

    func testParsesFreezeFrameCRTAndTogglesROMThroughIOReadsAndFreeze() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 45,
            exrom: 0,
            game: 1,
            chips: makeFreezeFrameChips()
        )))
        c64.memory.ram[0x8000] = 0x80
        c64.memory.kernalROM[0] = 0xE0

        XCTAssertEqual(c64.memory.cartridge?.hardwareType, 45)
        XCTAssertEqual(c64.memory.cartridge?.mappingMode, .freezeFrame)
        XCTAssertEqual(c64.memory.read(0x8000), 0x45)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE0)

        XCTAssertEqual(c64.memory.read(0xDF00), 0xE0)
        XCTAssertEqual(c64.memory.read(0x8000), 0x80)

        XCTAssertEqual(c64.memory.read(0xDE00), 0x80)
        XCTAssertEqual(c64.memory.read(0x8000), 0x45)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE0)

        c64.pressCartridgeFreezeButton()

        XCTAssertEqual(c64.memory.read(0x8000), 0x45)
        XCTAssertEqual(c64.memory.read(0xE000), 0x45)

        XCTAssertEqual(c64.memory.read(0xDF00), 0x45)
        XCTAssertEqual(c64.memory.read(0x8000), 0x80)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE0)

        c64.pressCartridgeFreezeButton()
        XCTAssertEqual(c64.memory.read(0xE000), 0x45)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x45)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE0)
    }

    func testFreezeFrameRejectsMissingMisplacedOrExtraImages() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 45,
            exrom: 0,
            game: 1,
            chips: [(bank: UInt16, address: UInt16, data: [UInt8])]()
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 45,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 1, address: 0x8000, data: Array(repeating: 0x45, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 45,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0xA000, data: Array(repeating: 0x45, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 45,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x45, count: 0x1000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 45,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x45, count: 0x2000)),
                (bank: 0, address: 0xE000, data: Array(repeating: 0x46, count: 0x2000))
            ]
        )))
    }

    func testParsesFreezeMachineCRTAndTogglesROMThroughIOReadsAndFreeze() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 46,
            exrom: 0,
            game: 1,
            chips: makeFreezeMachineChips()
        )))
        c64.memory.ram[0x8000] = 0x80
        c64.memory.basicROM[0] = 0xBA
        c64.memory.kernalROM[0] = 0xE0

        XCTAssertEqual(c64.memory.cartridge?.hardwareType, 46)
        XCTAssertEqual(c64.memory.cartridge?.mappingMode, .freezeMachine)
        XCTAssertEqual(c64.memory.read(0x8000), 0x20)
        XCTAssertEqual(c64.memory.read(0xA000), 0xBA)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE0)

        XCTAssertEqual(c64.memory.read(0xDF00), 0xE0)
        XCTAssertEqual(c64.memory.read(0x8000), 0x80)

        XCTAssertEqual(c64.memory.read(0xDE00), 0x80)
        XCTAssertEqual(c64.memory.read(0x8000), 0x20)
        XCTAssertEqual(c64.memory.read(0xA000), 0x21)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE0)

        c64.pressCartridgeFreezeButton()

        XCTAssertEqual(c64.memory.read(0x8000), 0x20)
        XCTAssertEqual(c64.memory.read(0xE000), 0x21)

        XCTAssertEqual(c64.memory.read(0xDF00), 0x21)
        XCTAssertEqual(c64.memory.read(0x8000), 0x80)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE0)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x20)
        XCTAssertEqual(c64.memory.read(0xA000), 0xBA)
    }

    func testFreezeMachine32KResetTogglesActive16KBank() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 46,
            exrom: 0,
            game: 1,
            chips: makeFreezeMachineChips(includeSecondBank: true)
        )))

        XCTAssertEqual(c64.memory.read(0x8000), 0x20)

        c64.reset()

        XCTAssertEqual(c64.memory.read(0x8000), 0x30)
        _ = c64.memory.read(0xDE00)
        XCTAssertEqual(c64.memory.read(0xA000), 0x31)

        c64.reset()

        XCTAssertEqual(c64.memory.read(0x8000), 0x20)
    }

    func testFreezeMachineAcceptsSplit8KCRTLayouts() throws {
        let oldSplit = Cartridge.parseCRT(makeCRT(
            hardwareType: 46,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x40, count: 0x2000)),
                (bank: 0, address: 0xA000, data: Array(repeating: 0x41, count: 0x2000)),
                (bank: 1, address: 0x8000, data: Array(repeating: 0x50, count: 0x2000)),
                (bank: 1, address: 0xA000, data: Array(repeating: 0x51, count: 0x2000))
            ]
        ))
        var oldSplitCart = try XCTUnwrap(oldSplit)
        XCTAssertEqual(oldSplitCart.read(0x8000), 0x40)
        _ = oldSplitCart.readIO(0xDE00)
        XCTAssertEqual(oldSplitCart.read(0xA000), 0x41)
        oldSplitCart.reset()
        XCTAssertEqual(oldSplitCart.read(0x8000), 0x50)

        let veryOldSplit = Cartridge.parseCRT(makeCRT(
            hardwareType: 46,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x60, count: 0x2000)),
                (bank: 1, address: 0x8000, data: Array(repeating: 0x61, count: 0x2000)),
                (bank: 2, address: 0x8000, data: Array(repeating: 0x70, count: 0x2000)),
                (bank: 3, address: 0x8000, data: Array(repeating: 0x71, count: 0x2000))
            ]
        ))
        var veryOldSplitCart = try XCTUnwrap(veryOldSplit)
        XCTAssertEqual(veryOldSplitCart.read(0x8000), 0x60)
        _ = veryOldSplitCart.readIO(0xDE00)
        XCTAssertEqual(veryOldSplitCart.read(0xA000), 0x61)
        veryOldSplitCart.reset()
        XCTAssertEqual(veryOldSplitCart.read(0x8000), 0x70)
    }

    func testFreezeMachineRejectsMissingMisplacedOrIncompleteImages() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 46,
            exrom: 0,
            game: 1,
            chips: [(bank: UInt16, address: UInt16, data: [UInt8])]()
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 46,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0xA000, data: Array(repeating: 0x20, count: 0x4000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 46,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x20, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 46,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 2, address: 0x8000, data: Array(repeating: 0x20, count: 0x4000))
            ]
        )))
    }

    func testParsesSnapshot64CRTAndShowsROMOnlyAfterFreezeUntilIO2Write() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 47,
            exrom: 1,
            game: 0,
            chips: makeSnapshot64Chips()
        )))
        c64.memory.ram[0x8000] = 0x80
        c64.memory.kernalROM[0] = 0xE0

        XCTAssertEqual(c64.memory.cartridge?.hardwareType, 47)
        XCTAssertEqual(c64.memory.cartridge?.mappingMode, .snapshot64)
        XCTAssertEqual(c64.memory.read(0x8000), 0x80)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE0)

        c64.pressCartridgeFreezeButton()

        XCTAssertEqual(c64.memory.read(0x8000), 0x64)
        XCTAssertEqual(c64.memory.read(0x9000), 0x64)
        XCTAssertEqual(c64.memory.read(0xE000), 0x64)
        XCTAssertEqual(c64.memory.read(0xF000), 0x64)

        c64.memory.write(0xDF00, value: 0x00)

        XCTAssertEqual(c64.memory.read(0x8000), 0x80)
        XCTAssertEqual(c64.memory.read(0xE000), 0xE0)

        c64.pressCartridgeFreezeButton()
        XCTAssertEqual(c64.memory.read(0x8000), 0x64)

        c64.reset()
        XCTAssertEqual(c64.memory.read(0x8000), 0x80)
    }

    func testSnapshot64RejectsMissingMisplacedOrExtraImages() {
        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 47,
            exrom: 1,
            game: 0,
            chips: [(bank: UInt16, address: UInt16, data: [UInt8])]()
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 47,
            exrom: 1,
            game: 0,
            chips: [
                (bank: 1, address: 0x8000, data: Array(repeating: 0x64, count: 0x1000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 47,
            exrom: 1,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x64, count: 0x2000))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 47,
            exrom: 1,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x64, count: 0x1000)),
                (bank: 0, address: 0xE000, data: Array(repeating: 0x65, count: 0x1000))
            ]
        )))
    }

    func testParsesSuperExplodeV5CRTAndBanksROMLThroughIO2Bit7() throws {
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(makeCRT(
            hardwareType: 48,
            exrom: 0,
            game: 1,
            chips: makeSuperExplodeV5Chips()
        )))
        memory.basicROM[0] = 0xBA

        XCTAssertEqual(memory.cartridge?.hardwareType, 48)
        XCTAssertEqual(memory.cartridge?.mappingMode, .superExplodeV5)
        XCTAssertEqual(memory.read(0x8000), 0x48)
        XCTAssertEqual(memory.read(0x9FFF), 0xD0)
        XCTAssertEqual(memory.read(0xA000), 0xBA)
        XCTAssertEqual(memory.read(0xDF00), 0xD0)
        XCTAssertEqual(memory.read(0xDFFF), 0xD0)

        memory.write(0xDF00, value: 0x80)

        XCTAssertEqual(memory.read(0x8000), 0x58)
        XCTAssertEqual(memory.read(0xDF00), 0xD1)

        memory.write(0xDF00, value: 0x00)
        XCTAssertEqual(memory.read(0x8000), 0x48)
    }

    func testSuperExplodeV5ROMTimesOutAndROMLOrIO1ReenablesIt() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 48,
            exrom: 0,
            game: 1,
            chips: makeSuperExplodeV5Chips()
        )))
        c64.memory.ram[0x8000] = 0x80

        XCTAssertEqual(c64.memory.read(0x8000), 0x48)

        c64.memory.tickCartridge(cycles: 300_000)

        XCTAssertNil(c64.memory.cartridge?.read(0x8000))
        XCTAssertEqual(c64.memory.read(0x8000), 0x48)
        c64.memory.tickCartridge(cycles: 300_000)
        XCTAssertEqual(c64.memory.ram[0x8000], 0x80)

        _ = c64.memory.read(0xDE00)
        XCTAssertEqual(c64.memory.read(0x8000), 0x48)

        c64.memory.tickCartridge(cycles: 300_000)
        XCTAssertNil(c64.memory.cartridge?.read(0x8000))
        c64.memory.write(0xDE00, value: 0x00)
        XCTAssertEqual(c64.memory.read(0x8000), 0x48)
    }

    func testSuperExplodeV5PreservesBankAcrossResetAndRejectsBadImages() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 48,
            exrom: 0,
            game: 1,
            chips: makeSuperExplodeV5Chips()
        )))

        c64.memory.write(0xDF00, value: 0x80)
        XCTAssertEqual(c64.memory.read(0x8000), 0x58)

        c64.reset()

        XCTAssertEqual(c64.memory.read(0x8000), 0x58)

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 48,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: make8KBank(first: 0x48, io: 0xD0))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 48,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0xA000, data: make8KBank(first: 0x48, io: 0xD0)),
                (bank: 1, address: 0x8000, data: make8KBank(first: 0x58, io: 0xD1))
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 48,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 2, address: 0x8000, data: make8KBank(first: 0x68, io: 0xD2)),
                (bank: 1, address: 0x8000, data: make8KBank(first: 0x58, io: 0xD1))
            ]
        )))
    }

    func testParsesMach5CRTAndMirrorsROMIntoIO() throws {
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(makeCRT(
            hardwareType: 51,
            exrom: 0,
            game: 1,
            chips: makeMach5Chips()
        )))

        XCTAssertEqual(memory.cartridge?.hardwareType, 51)
        XCTAssertEqual(memory.cartridge?.mappingMode, .mach5)
        XCTAssertEqual(memory.read(0x8000), 0x51)
        XCTAssertEqual(memory.read(0x9E00), 0xDE)
        XCTAssertEqual(memory.read(0x9FFF), 0xDF)
        XCTAssertEqual(memory.read(0xDE00), 0xDE)
        XCTAssertEqual(memory.read(0xDFFF), 0xDF)
    }

    func testMach5IOWritesDisableAndReenableROMWindow() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(makeCRT(
            hardwareType: 51,
            exrom: 0,
            game: 1,
            chips: makeMach5Chips()
        )))
        c64.memory.ram[0x8000] = 0x80

        XCTAssertEqual(c64.memory.read(0x8000), 0x51)

        c64.memory.write(0xDF00, value: 0x00)

        XCTAssertEqual(c64.memory.read(0x8000), 0x80)
        XCTAssertEqual(c64.memory.read(0xDE00), 0xDE)
        XCTAssertEqual(c64.memory.read(0xDFFF), 0xDF)

        c64.memory.write(0xDE00, value: 0x00)

        XCTAssertEqual(c64.memory.read(0x8000), 0x51)

        c64.memory.write(0xDF00, value: 0x00)
        c64.reset()

        XCTAssertEqual(c64.memory.read(0x8000), 0x51)
    }

    func testMach5Accepts4KImagesMirroredTo8KAndRejectsBadImages() throws {
        var cartridge = try XCTUnwrap(Cartridge.parseCRT(makeCRT(
            hardwareType: 51,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x45, count: 0x1000))
            ]
        )))

        XCTAssertEqual(cartridge.read(0x8000), 0x45)
        XCTAssertEqual(cartridge.read(0x9000), 0x45)
        XCTAssertEqual(cartridge.readIO(0xDE00), 0x45)
        XCTAssertEqual(cartridge.readIO(0xDF00), 0x45)

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 51,
            exrom: 0,
            game: 1,
            chips: [(bank: UInt16, address: UInt16, data: [UInt8])]()
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 51,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 1, address: 0x8000, data: makeMach5Image())
            ]
        )))

        XCTAssertNil(Cartridge.parseCRT(makeCRT(
            hardwareType: 51,
            exrom: 0,
            game: 1,
            chips: [
                (bank: 0, address: 0xA000, data: makeMach5Image())
            ]
        )))
    }

    func testParsesEasyFlashCRTAndBanksROMLAndROMHThroughIO1() throws {
        let crt = makeCRT(
            hardwareType: 32,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x10, count: 0x2000)),
                (bank: 0, address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000)),
                (bank: 1, address: 0x8000, data: Array(repeating: 0x21, count: 0x2000)),
                (bank: 1, address: 0xA000, data: Array(repeating: 0xB1, count: 0x2000))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.kernalROM[0] = 0xFE
        memory.basicROM[0] = 0xBA

        XCTAssertEqual(cartridge.hardwareType, 32)
        XCTAssertEqual(cartridge.mappingMode, .easyFlash)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertEqual(memory.read(0xE000), 0xA0)

        memory.write(0xDE02, value: 0b111)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertEqual(memory.read(0xA000), 0xA0)
        XCTAssertEqual(memory.read(0xE000), 0xFE)

        memory.write(0xDE00, value: 0x01)
        XCTAssertEqual(memory.read(0x8000), 0x21)
        XCTAssertEqual(memory.read(0xA000), 0xB1)

        memory.write(0xDE02, value: 0b110)
        XCTAssertEqual(memory.read(0x8000), 0x21)
        XCTAssertEqual(memory.read(0xA000), 0xBA)

        memory.write(0xDE02, value: 0b000)
        XCTAssertEqual(memory.read(0x8000), 0x21)
        XCTAssertEqual(memory.read(0xE000), 0xB1)

        memory.write(0xDE02, value: 0b010)
        XCTAssertEqual(memory.read(0x8000), 0x21)
        XCTAssertEqual(memory.read(0xA000), 0xB1)
        XCTAssertEqual(memory.read(0xE000), 0xFE)
    }

    func testEasyFlashCanDisableROMAndKeepsIO2RAMVisible() throws {
        let crt = makeCRT(
            hardwareType: 32,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x10, count: 0x2000)),
                (bank: 0, address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        memory.ram[0x8000] = 0x44

        memory.write(0xDF10, value: 0x5A)
        XCTAssertEqual(memory.read(0xDF10), 0x5A)

        memory.write(0xDE02, value: 0b100)
        XCTAssertEqual(memory.read(0x8000), 0x44)
        XCTAssertEqual(memory.read(0xDF10), 0x5A)

        memory.write(0xDE02, value: 0b101)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertEqual(memory.read(0xE000), 0xA0)
    }

    func testEasyFlashControlRegistersAreWriteOnlyOpenBusReads() throws {
        let crt = makeCRT(
            hardwareType: 32,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x10, count: 0x2000)),
                (bank: 1, address: 0x8000, data: Array(repeating: 0x21, count: 0x2000))
            ]
        )
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))

        memory.write(0xDE00, value: 0x01)
        XCTAssertEqual(memory.read(0x8000), 0x21)

        memory.write(0xD020, value: 0x5A)
        XCTAssertEqual(memory.read(0xDE00), 0x5A)
        XCTAssertEqual(memory.read(0xDE02), 0x5A)
    }

    func testEasyFlashReservedControlModesPreserveCurrentMapping() throws {
        let crt = makeCRT(
            hardwareType: 32,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x10, count: 0x2000)),
                (bank: 0, address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )
        let memory = MemoryMap()
        memory.cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        memory.basicROM[0] = 0xBA
        memory.kernalROM[0] = 0xFE

        memory.write(0xDE02, value: 0b111)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertEqual(memory.read(0xA000), 0xA0)
        XCTAssertEqual(memory.read(0xE000), 0xFE)

        memory.write(0xDE02, value: 0b001)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertEqual(memory.read(0xA000), 0xA0)
        XCTAssertEqual(memory.read(0xE000), 0xFE)

        memory.write(0xDE02, value: 0b011)
        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertEqual(memory.read(0xA000), 0xA0)
        XCTAssertEqual(memory.read(0xE000), 0xFE)
    }

    func testEasyFlashAcceptsSparseROMLOnlyCRT() throws {
        let crt = makeCRT(
            hardwareType: 32,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x10, count: 0x2000))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge
        memory.write(0xDE02, value: 0b110)

        XCTAssertEqual(memory.read(0x8000), 0x10)
        XCTAssertNil(cartridge.read(0xA000))
    }

    func testEasyFlashAcceptsSparseROMHOnlyCRT() throws {
        let crt = makeCRT(
            hardwareType: 32,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000))
            ]
        )
        let cartridge = try XCTUnwrap(Cartridge.parseCRT(crt))
        let memory = MemoryMap()
        memory.cartridge = cartridge

        XCTAssertNil(cartridge.read(0x8000))
        XCTAssertEqual(memory.read(0xE000), 0xA0)
    }

    func testEasyFlashRejectsOutOfRangeBankNumber() {
        let crt = makeCRT(
            hardwareType: 32,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 64, address: 0x8000, data: Array(repeating: 0x10, count: 0x2000))
            ]
        )

        XCTAssertNil(Cartridge.parseCRT(crt))
    }

    func testC64ResetRestoresEasyFlashStartupBankAndMode() throws {
        let crt = makeCRT(
            hardwareType: 32,
            exrom: 0,
            game: 0,
            chips: [
                (bank: 0, address: 0x8000, data: Array(repeating: 0x10, count: 0x2000)),
                (bank: 0, address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000)),
                (bank: 1, address: 0x8000, data: Array(repeating: 0x21, count: 0x2000)),
                (bank: 1, address: 0xA000, data: Array(repeating: 0xB1, count: 0x2000))
            ]
        )
        let c64 = C64()
        XCTAssertTrue(c64.mountCartridge(crt))
        c64.memory.basicROM[0] = 0xBA

        c64.memory.write(0xDE02, value: 0b111)
        c64.memory.write(0xDE00, value: 0x01)
        XCTAssertEqual(c64.memory.read(0xA000), 0xB1)

        c64.reset()

        XCTAssertEqual(c64.mountedCartridgeName, "TEST CART")
        XCTAssertEqual(c64.memory.read(0x8000), 0x10)
        XCTAssertEqual(c64.memory.read(0xE000), 0xA0)
        XCTAssertEqual(c64.memory.read(0xA000), 0xA0)
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

    private func make16KBank(low: UInt8, high: UInt8, io: UInt8) -> [UInt8] {
        var bank = [UInt8](repeating: low, count: 0x4000)
        bank.replaceSubrange(0x2000..<0x3E00, with: [UInt8](repeating: high, count: 0x1E00))
        bank.replaceSubrange(0x3E00..<0x4000, with: [UInt8](repeating: io, count: 0x200))
        return bank
    }

    private func make8KBank(first: UInt8, io: UInt8) -> [UInt8] {
        var bank = [UInt8](repeating: first, count: 0x2000)
        bank.replaceSubrange(0x1F00..<0x2000, with: [UInt8](repeating: io, count: 0x100))
        return bank
    }

    private func makeKCSPowerChips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        var low = [UInt8](repeating: 0x80, count: 0x2000)
        low.replaceSubrange(0x1E00..<0x1F00, with: [UInt8](repeating: 0xDE, count: 0x100))
        return [
            (bank: 0, address: 0x8000, data: low),
            (bank: 0, address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000))
        ]
    }

    private func makeAtomicPowerChips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        (0..<4).map { index in
            let bank = UInt16(index)
            let first = UInt8(0x80 + index)
            let io = UInt8(0xD0 + index)
            let data = make8KBank(first: first, io: io)
            return (
                bank: bank,
                address: 0x8000,
                data: data
            )
        }
    }

    private func makeC64GameSystemChips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        (0..<64).map { index in
            let bank = UInt16(index)
            return (bank: bank, address: 0x8000, data: Array(repeating: UInt8(0x40 + index), count: 0x2000))
        }
    }

    private func makeDinamicChips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        (0..<16).map { index in
            let bank = UInt16(index)
            return (bank: bank, address: 0x8000, data: Array(repeating: UInt8(0x50 + index), count: 0x2000))
        }
    }

    private func makeZaxxonChips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        [
            (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x1000)),
            (bank: 0, address: 0xA000, data: Array(repeating: 0xA0, count: 0x2000)),
            (bank: 1, address: 0xA000, data: Array(repeating: 0xB1, count: 0x2000))
        ]
    }

    private func makeSuperSnapshotV5Chips(count: Int) -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        (0..<count).map { index in
            let bank = UInt16(index)
            let low = UInt8(0x80 + index)
            let high = UInt8(0x90 + index)
            let io = UInt8(0xA0 + index)
            var data = make16KBank(low: low, high: high, io: io)
            data.replaceSubrange(0x1E00..<0x1F00, with: [UInt8](repeating: io, count: 0x100))
            return (
                bank: bank,
                address: 0x8000,
                data: data
            )
        }
    }

    private func makeComal80Chips(count: Int) -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        (0..<count).map { index in
            let bank = UInt16(index)
            let low = UInt8(0x80 + index)
            let high = UInt8(0x90 + index)
            let io = UInt8(0xA0 + index)
            let data = make16KBank(low: low, high: high, io: io)
            return (
                bank: bank,
                address: 0x8000,
                data: data
            )
        }
    }

    private func makeDelaEP64Chips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        var firstEPROM: [UInt8] = []
        var secondEPROM: [UInt8] = []
        for index in 1...4 {
            firstEPROM.append(contentsOf: [UInt8](repeating: UInt8(0x60 + index), count: 0x2000))
        }
        for index in 5...8 {
            secondEPROM.append(contentsOf: [UInt8](repeating: UInt8(0x60 + index), count: 0x2000))
        }
        return [
            (bank: 0, address: 0x8000, data: Array(repeating: 0x60, count: 0x2000)),
            (bank: 1, address: 0x8000, data: firstEPROM),
            (bank: 2, address: 0x8000, data: secondEPROM)
        ]
    }

    private func makeDela8KChips(count: Int, base: UInt8) -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        (0..<count).map { index in
            (
                bank: UInt16(index),
                address: 0x8000,
                data: Array(repeating: UInt8(Int(base) + index), count: 0x2000)
            )
        }
    }

    private func makeRexEP256Chips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        var socket2: [UInt8] = []
        var socket3: [UInt8] = []
        for index in 0..<2 {
            socket2.append(contentsOf: [UInt8](repeating: UInt8(0xB0 + index), count: 0x2000))
        }
        for index in 0..<4 {
            socket3.append(contentsOf: [UInt8](repeating: UInt8(0xC0 + index), count: 0x2000))
        }
        return [
            (bank: 0, address: 0x8000, data: Array(repeating: 0x90, count: 0x2000)),
            (bank: 1, address: 0x8000, data: Array(repeating: 0xA0, count: 0x2000)),
            (bank: 2, address: 0x8000, data: socket2),
            (bank: 3, address: 0x8000, data: socket3)
        ]
    }

    private func makeMikroAssemblerImage() -> [UInt8] {
        var image = [UInt8](repeating: 0x80, count: 0x2000)
        image[0x1E00] = 0xDE
        image[0x1FFF] = 0xDF
        return image
    }

    private func makeWarpSpeedImage() -> [UInt8] {
        var image = [UInt8](repeating: 0x80, count: 0x4000)
        image.replaceSubrange(0x2000..<0x4000, with: [UInt8](repeating: 0xA0, count: 0x2000))
        image[0x1E00] = 0xDE
        image[0x1FFF] = 0xDF
        return image
    }

    private func makeStardosChips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        [
            (bank: 0, address: 0x8000, data: Array(repeating: 0x80, count: 0x2000)),
            (bank: 0, address: 0xE000, data: Array(repeating: 0xE0, count: 0x2000))
        ]
    }

    private func makeGameKillerChips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        [
            (bank: 0, address: 0xE000, data: Array(repeating: 0xE2, count: 0x2000))
        ]
    }

    private func makeProphet64Chips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        (0..<32).map { index in
            (
                bank: UInt16(index),
                address: 0x8000,
                data: Array(repeating: UInt8(0x40 + index), count: 0x2000)
            )
        }
    }

    private func makeEXOSChips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        [
            (bank: 0, address: 0xE000, data: Array(repeating: 0xE4, count: 0x2000))
        ]
    }

    private func makeFreezeFrameChips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        [
            (bank: 0, address: 0x8000, data: Array(repeating: 0x45, count: 0x2000))
        ]
    }

    private func makeFreezeMachineChips(includeSecondBank: Bool = false) -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        var chips = [
            (bank: UInt16(0), address: UInt16(0x8000), data: make16KBank(low: 0x20, high: 0x21, io: 0x21))
        ]
        if includeSecondBank {
            chips.append((bank: 1, address: 0x8000, data: make16KBank(low: 0x30, high: 0x31, io: 0x31)))
        }
        return chips
    }

    private func makeSnapshot64Chips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        [
            (bank: 0, address: 0x8000, data: Array(repeating: 0x64, count: 0x1000))
        ]
    }

    private func makeSuperExplodeV5Chips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        [
            (bank: 0, address: 0x8000, data: make8KBank(first: 0x48, io: 0xD0)),
            (bank: 1, address: 0x8000, data: make8KBank(first: 0x58, io: 0xD1))
        ]
    }

    private func makeMach5Chips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        [
            (bank: 0, address: 0x8000, data: makeMach5Image())
        ]
    }

    private func makeMach5Image() -> [UInt8] {
        var image = [UInt8](repeating: 0x51, count: 0x2000)
        image[0x1E00] = 0xDE
        image[0x1FFF] = 0xDF
        return image
    }

    private func makeFinalCartridgePlusImage(unused: UInt8, kernal: UInt8, low: UInt8, high: UInt8) -> [UInt8] {
        var image: [UInt8] = []
        image.append(contentsOf: [UInt8](repeating: unused, count: 0x2000))
        image.append(contentsOf: [UInt8](repeating: kernal, count: 0x2000))
        image.append(contentsOf: [UInt8](repeating: low, count: 0x2000))
        image.append(contentsOf: [UInt8](repeating: high, count: 0x2000))
        return image
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
