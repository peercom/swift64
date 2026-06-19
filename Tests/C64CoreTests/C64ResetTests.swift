import XCTest
@testable import C64Core

final class C64ResetTests: XCTestCase {
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
        for _ in 0..<4 where !c64.cpu.jammed {
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
