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

    private func makeC64GameSystemChips() -> [(bank: UInt16, address: UInt16, data: [UInt8])] {
        (0..<64).map { index in
            let bank = UInt16(index)
            return (bank: bank, address: 0x8000, data: Array(repeating: UInt8(0x40 + index), count: 0x2000))
        }
    }

    private func makeWarpSpeedImage() -> [UInt8] {
        var image = [UInt8](repeating: 0x80, count: 0x4000)
        image.replaceSubrange(0x2000..<0x4000, with: [UInt8](repeating: 0xA0, count: 0x2000))
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
