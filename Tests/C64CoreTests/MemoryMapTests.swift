import XCTest
@testable import C64Core

final class MemoryMapTests: XCTestCase {
    func testResetCPUPortRestoresDefaultROMBankingAndCassetteOutputs() {
        let memory = MemoryMap()
        memory.write(0x0000, value: 0x00)
        memory.write(0x0001, value: 0x00)

        memory.resetCPUPort()

        XCTAssertEqual(memory.portDirection, 0x2F)
        XCTAssertEqual(memory.portData, 0x37)
        XCTAssertEqual(memory.read(0x0001), 0x37)
        XCTAssertFalse(memory.cassetteWriteLineHigh)
        XCTAssertTrue(memory.cassetteMotorLineHigh)
        XCTAssertFalse(memory.cassetteMotorEnabled)
    }

    func testCPUDataPortInputBitsReadAsEffectivePulledUpPortLines() {
        let memory = MemoryMap()

        memory.write(0x0000, value: 0x00)
        memory.write(0x0001, value: 0x00)

        XCTAssertEqual(memory.read(0x0001), 0x37)
    }

    func testCPUDataPortReflectsCassetteSenseInputLine() {
        let memory = MemoryMap()
        memory.write(0x0000, value: 0x00)
        memory.write(0x0001, value: 0x00)

        memory.cassetteSenseLineHigh = false

        XCTAssertEqual(memory.read(0x0001), 0x27)

        memory.cassetteSenseLineHigh = true

        XCTAssertEqual(memory.read(0x0001), 0x37)
    }

    func testCPUDataPortOutputDirectionOverridesCassetteSenseInput() {
        let memory = MemoryMap()
        memory.cassetteSenseLineHigh = false

        memory.write(0x0000, value: 0x10)
        memory.write(0x0001, value: 0x10)

        XCTAssertEqual(memory.read(0x0001) & 0x10, 0x10)

        memory.write(0x0001, value: 0x00)

        XCTAssertEqual(memory.read(0x0001) & 0x10, 0x00)
    }

    func testCPUDataPortExposesCassetteOutputLineLevels() {
        let memory = MemoryMap()
        memory.write(0x0000, value: 0x28)
        memory.write(0x0001, value: 0x28)

        XCTAssertTrue(memory.cassetteWriteLineHigh)
        XCTAssertTrue(memory.cassetteMotorLineHigh)
        XCTAssertFalse(memory.cassetteMotorEnabled)

        memory.write(0x0001, value: 0x00)

        XCTAssertFalse(memory.cassetteWriteLineHigh)
        XCTAssertFalse(memory.cassetteMotorLineHigh)
        XCTAssertTrue(memory.cassetteMotorEnabled)
    }

    func testROMBankingReadsROMsAndWritesRAMUnderneath() {
        let memory = MemoryMap()
        memory.basicROM[0] = 0xBA
        memory.kernalROM[0] = 0xE0
        memory.charROM[0] = 0xC4
        memory.ram[0xA000] = 0x11
        memory.ram[0xD000] = 0x22
        memory.ram[0xE000] = 0x33

        XCTAssertEqual(memory.read(0xA000), 0xBA)
        XCTAssertEqual(memory.read(0xE000), 0xE0)

        memory.write(0xA000, value: 0x44)
        memory.write(0xE000, value: 0x55)

        XCTAssertEqual(memory.ram[0xA000], 0x44)
        XCTAssertEqual(memory.ram[0xE000], 0x55)
        XCTAssertEqual(memory.read(0xA000), 0xBA)
        XCTAssertEqual(memory.read(0xE000), 0xE0)

        memory.write(0x0001, value: 0x33)
        XCTAssertEqual(memory.read(0xD000), 0xC4)

        memory.write(0x0001, value: 0x30)
        XCTAssertEqual(memory.read(0xA000), 0x44)
        XCTAssertEqual(memory.read(0xD000), 0x22)
        XCTAssertEqual(memory.read(0xE000), 0x55)
    }

    func testVICBankSelectionUsesCIA2PortADirectionAndInvertedLowBits() {
        let memory = MemoryMap()
        let cia2 = CIA(isCIA1: false)
        memory.cia2 = cia2

        memory.ram[0x0000] = 0x10
        memory.ram[0x4000] = 0x40
        memory.ram[0x8000] = 0x80
        memory.ram[0xC000] = 0xC0

        XCTAssertEqual(memory.vicRead(0x0000), 0x10)

        cia2.writeRegister(0x00, value: 0x00)
        XCTAssertEqual(memory.vicRead(0x0000), 0x10)

        cia2.writeRegister(0x02, value: 0x03)
        XCTAssertEqual(memory.vicRead(0x0000), 0xC0)

        cia2.writeRegister(0x00, value: 0x02)
        XCTAssertEqual(memory.vicRead(0x0000), 0x40)

        cia2.writeRegister(0x00, value: 0x01)
        XCTAssertEqual(memory.vicRead(0x0000), 0x80)
    }

    func testVICSeesCharacterROMOnlyInCharacterROMWindows() {
        let memory = MemoryMap()
        let cia2 = CIA(isCIA1: false)
        memory.cia2 = cia2
        memory.charROM[0] = 0xC1
        memory.ram[0x1000] = 0x10
        memory.ram[0x2000] = 0x20
        memory.ram[0x8000] = 0x80
        memory.ram[0x9000] = 0x90

        XCTAssertEqual(memory.vicRead(0x1000), 0xC1)
        XCTAssertEqual(memory.vicRead(0x2000), 0x20)

        cia2.writeRegister(0x02, value: 0x03)
        cia2.writeRegister(0x00, value: 0x01)

        XCTAssertEqual(memory.vicRead(0x1000), 0xC1)
        XCTAssertEqual(memory.vicRead(0x0000), 0x80)
    }

    func testUnmappedExpansionAreaReturnsLastCPUReadValue() {
        let memory = MemoryMap()
        memory.ram[0xC000] = 0xA7

        XCTAssertEqual(memory.read(0xC000), 0xA7)
        XCTAssertEqual(memory.read(0xDE00), 0xA7)
        XCTAssertEqual(memory.read(0xDFFF), 0xA7)
    }

    func testUnmappedExpansionAreaReturnsLastCPUWriteValue() {
        let memory = MemoryMap()

        memory.write(0x2000, value: 0x5C)

        XCTAssertEqual(memory.read(0xDF00), 0x5C)
    }

    func testSIDWriteOnlyRegistersReturnOpenBus() {
        let memory = MemoryMap()
        let sid = SID()
        memory.sid = sid
        sid.setPaddle(x: 0x44, y: 0x55)

        memory.ram[0xC000] = 0xA9
        XCTAssertEqual(memory.read(0xC000), 0xA9)

        sid.writeRegister(0x00, value: 0x34)
        XCTAssertEqual(memory.read(0xD400), 0xA9)
        XCTAssertEqual(memory.read(0xD418), 0xA9)
        XCTAssertEqual(memory.read(0xD419), 0x44)
        XCTAssertEqual(memory.read(0xD41A), 0x55)
    }

    func testColorRAMReadsLowNibbleWithOpenBusHighNibble() {
        let memory = MemoryMap()
        memory.ram[0xC000] = 0xA3
        memory.write(0xD800, value: 0x5E)

        XCTAssertEqual(memory.colorRAM[0], 0x0E)

        XCTAssertEqual(memory.read(0xC000), 0xA3)
        XCTAssertEqual(memory.read(0xD800), 0xAE)
    }

    func testAbsentVICAndCIAReadsReturnOpenBus() {
        let memory = MemoryMap()
        memory.ram[0xC000] = 0x72

        XCTAssertEqual(memory.read(0xC000), 0x72)

        XCTAssertEqual(memory.read(0xD000), 0x72)
        XCTAssertEqual(memory.read(0xDC00), 0x72)
        XCTAssertEqual(memory.read(0xDD00), 0x72)
    }
}
