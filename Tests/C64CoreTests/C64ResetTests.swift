import XCTest
@testable import C64Core

final class C64ResetTests: XCTestCase {
    func testPowerOnInitializesRAMWithDeterministicColdStartPattern() {
        let c64 = C64()
        var kernal = Data(repeating: 0, count: C64.kernalROMSize)
        kernal[0x1FFC] = 0x00
        kernal[0x1FFD] = 0xE0
        c64.loadROMs(
            basic: Data(repeating: 0, count: C64.basicROMSize),
            kernal: kernal,
            charset: Data(repeating: 0, count: C64.characterROMSize)
        )

        c64.powerOn()

        XCTAssertEqual(c64.memory.ram[0x0000], 0x00)
        XCTAssertEqual(c64.memory.ram[0x003F], 0x00)
        XCTAssertEqual(c64.memory.ram[0x0040], 0xFF)
        XCTAssertEqual(c64.memory.ram[0x007F], 0xFF)
        XCTAssertEqual(c64.memory.ram[0x0080], 0x00)
        XCTAssertEqual(c64.memory.ram[0x00BF], 0x00)
        XCTAssertEqual(c64.memory.ram[0x00C0], 0xFF)
        XCTAssertEqual(c64.memory.ram[0x00FF], 0xFF)
        XCTAssertEqual(c64.memory.ram[0xFF80], 0x00)
        XCTAssertEqual(c64.memory.ram[0xFFBF], 0x00)
        XCTAssertEqual(c64.memory.ram[0xFFC0], 0xFF)
        XCTAssertEqual(c64.memory.ram[0xFFFF], 0xFF)
    }

    func testPowerOnUsesSelectedMachineProfileRAMPattern() {
        var profile = MachineProfile.palC64
        profile = MachineProfile(
            name: profile.name,
            videoStandard: profile.videoStandard,
            cpuClockHz: profile.cpuClockHz,
            ciaTodCyclesPerTenth: profile.ciaTodCyclesPerTenth,
            sidModel: profile.sidModel,
            sidClockHz: profile.sidClockHz,
            driveModel: profile.driveModel,
            driveClockHz: profile.driveClockHz,
            memoryPowerOnPattern: .allOne
        )
        let c64 = C64(machineProfile: profile)
        var kernal = Data(repeating: 0, count: C64.kernalROMSize)
        kernal[0x1FFC] = 0x00
        kernal[0x1FFD] = 0xE0
        c64.loadROMs(
            basic: Data(repeating: 0, count: C64.basicROMSize),
            kernal: kernal,
            charset: Data(repeating: 0, count: C64.characterROMSize)
        )

        c64.powerOn()

        XCTAssertEqual(c64.memory.ram[0x0000], 0xFF)
        XCTAssertEqual(c64.memory.ram[0x003F], 0xFF)
        XCTAssertEqual(c64.memory.ram[0x0040], 0xFF)
        XCTAssertEqual(c64.memory.ram[0x8000], 0xFF)
        XCTAssertEqual(c64.memory.ram[0xFFFF], 0xFF)
    }

    func testPowerOnColdResetsVideoAudioAndCIAState() {
        let c64 = C64()
        var kernal = Data(repeating: 0, count: C64.kernalROMSize)
        kernal[0x1FFC] = 0x00
        kernal[0x1FFD] = 0xE0
        c64.loadROMs(
            basic: Data(repeating: 0, count: C64.basicROMSize),
            kernal: kernal,
            charset: Data(repeating: 0, count: C64.characterROMSize)
        )
        c64.vic.writeRegister(0x20, value: 0x06)
        c64.vic.writeRegister(0x1A, value: 0x01)
        c64.sid.writeRegister(0x18, value: 0x0F)
        c64.cia1.writeRegister(0x0D, value: 0x81)
        c64.cia1.interruptData = 0x01
        c64.cia1.interruptActive = true
        c64.cia2.writeRegister(0x00, value: 0x00)
        c64.cia2.writeRegister(0x02, value: 0x03)

        c64.powerOn()

        XCTAssertEqual(c64.vic.readRegister(0x20), 0xFE)
        XCTAssertEqual(c64.vic.readRegister(0x1A), 0xF0)
        XCTAssertEqual(c64.sid.debugRegisterValue(0x18), 0x00)
        XCTAssertEqual(c64.cia1.interruptData, 0x00)
        XCTAssertFalse(c64.cia1.interruptActive)
        XCTAssertEqual(c64.cia2.readRegister(0x00) & 0x03, 0x03)
    }

    func testPowerOnClearsPendingTypedTextRestoreAndDriveClockResidue() {
        let c64 = C64()
        var kernal = Data(repeating: 0, count: C64.kernalROMSize)
        kernal[0x1FFC] = 0x00
        kernal[0x1FFD] = 0xE0
        c64.loadROMs(
            basic: Data(repeating: 0, count: C64.basicROMSize),
            kernal: kernal,
            charset: Data(repeating: 0, count: C64.characterROMSize)
        )
        c64.typeText("LOAD\"*\",8,1\r")
        XCTAssertEqual(c64.memory.ram[0x00C6], 10)
        XCTAssertTrue(c64.pressRestoreKey())
        c64.driveClockAccumulator = 0.75

        c64.powerOn()
        c64.memory.ram[0x00C6] = 0
        c64.tickOneCycle()

        XCTAssertFalse(c64.restoreKeyDown)
        XCTAssertEqual(c64.driveClockAccumulator, 0)
        XCTAssertEqual(c64.memory.ram[0x00C6], 0)
    }

    func testResetPreservesRAMContentsLikeWarmReset() {
        let c64 = C64()
        var kernal = Data(repeating: 0, count: C64.kernalROMSize)
        kernal[0x1FFC] = 0x00
        kernal[0x1FFD] = 0xE0
        c64.loadROMs(
            basic: Data(repeating: 0, count: C64.basicROMSize),
            kernal: kernal,
            charset: Data(repeating: 0, count: C64.characterROMSize)
        )
        c64.powerOn()
        c64.memory.ram[0x0801] = 0x42
        c64.memory.ram[0xC000] = 0x99

        c64.reset()

        XCTAssertEqual(c64.memory.ram[0x0801], 0x42)
        XCTAssertEqual(c64.memory.ram[0xC000], 0x99)
    }

    func testResetRecoversJammedCPUAndFetchesKernalVector() {
        let c64 = C64()
        var kernal = Data(repeating: 0, count: C64.kernalROMSize)
        kernal[0x1FFC] = 0xCD
        kernal[0x1FFD] = 0xAB
        c64.loadROMs(
            basic: Data(repeating: 0, count: C64.basicROMSize),
            kernal: kernal,
            charset: Data(repeating: 0, count: C64.characterROMSize)
        )

        c64.memory.ram[0x0600] = 0x02
        c64.memory.ram[0xFFFC] = 0x00
        c64.memory.ram[0xFFFD] = 0x06
        c64.memory.write(0x0000, value: 0x2F)
        c64.memory.write(0x0001, value: 0x30)
        c64.cpu.powerOn()
        for _ in 0..<12 where !c64.cpu.jammed {
            c64.tickOneCycle()
        }

        XCTAssertTrue(c64.cpu.jammed)

        c64.reset()
        for _ in 0..<7 {
            c64.tickOneCycle()
        }

        XCTAssertFalse(c64.cpu.jammed)
        XCTAssertEqual(c64.cpu.pc, 0xABCD)
    }

    func testResetRestoresCPUPortBeforeFetchingResetVector() {
        let c64 = C64()
        var basic = Data(repeating: 0, count: C64.basicROMSize)
        var kernal = Data(repeating: 0, count: C64.kernalROMSize)
        var charset = Data(repeating: 0, count: C64.characterROMSize)
        basic[0] = 0xBA
        charset[0] = 0xC4
        kernal[0x1FFC] = 0x34
        kernal[0x1FFD] = 0x12
        c64.loadROMs(basic: basic, kernal: kernal, charset: charset)

        c64.memory.ram[0xFFFC] = 0x78
        c64.memory.ram[0xFFFD] = 0x56
        c64.memory.write(0x0000, value: 0x2F)
        c64.memory.write(0x0001, value: 0x30)

        XCTAssertEqual(c64.memory.read(0xFFFC), 0x78)

        c64.reset()
        for _ in 0..<7 {
            c64.tickOneCycle()
        }

        XCTAssertEqual(c64.memory.portDirection, 0x2F)
        XCTAssertEqual(c64.memory.portData, 0x37)
        XCTAssertEqual(c64.cpu.pc, 0x1234)
    }

    func testWarmResetRestoresCPUPortWithoutOverwritingUnderlyingZeroPageRAM() {
        let c64 = C64()
        var kernal = Data(repeating: 0, count: C64.kernalROMSize)
        kernal[0x1FFC] = 0x00
        kernal[0x1FFD] = 0xE0
        c64.loadROMs(
            basic: Data(repeating: 0, count: C64.basicROMSize),
            kernal: kernal,
            charset: Data(repeating: 0, count: C64.characterROMSize)
        )
        c64.powerOn()
        c64.memory.ram[0x0000] = 0xAA
        c64.memory.ram[0x0001] = 0xBB
        c64.memory.write(0x0000, value: 0x00)
        c64.memory.write(0x0001, value: 0x30)

        c64.reset()

        XCTAssertEqual(c64.memory.portDirection, 0x2F)
        XCTAssertEqual(c64.memory.portData, 0x37)
        XCTAssertEqual(c64.memory.read(0x0000), 0x2F)
        XCTAssertEqual(c64.memory.read(0x0001), 0x37)
        XCTAssertEqual(c64.memory.ram[0x0000], 0xAA)
        XCTAssertEqual(c64.memory.ram[0x0001], 0xBB)
        XCTAssertEqual(c64.memory.vicRead(0x0000), 0xAA)
        XCTAssertEqual(c64.memory.vicRead(0x0001), 0xBB)
    }

    func testResetClearsCapturedCassetteWritePulses() {
        let c64 = C64()

        c64.memory.write(0x0000, value: 0x28)
        c64.memory.write(0x0001, value: 0x00)
        tickCycles(c64, 3)
        c64.memory.write(0x0001, value: 0x08)

        XCTAssertFalse(c64.tapeUnit.writePulses.isEmpty)

        c64.reset()

        XCTAssertTrue(c64.tapeUnit.writePulses.isEmpty)
        XCTAssertFalse(c64.tapeUnit.writeLineHigh)
    }

    private func tickCycles(_ c64: C64, _ count: Int) {
        for _ in 0..<count {
            c64.tickOneCycle()
        }
    }
}
