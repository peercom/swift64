import XCTest
@testable import C64Core

final class VICSlotTimingTests: XCTestCase {
    func testDirectMemoryCallbacksDoNotRetainTheMachineOrItsChips() {
        weak var machine: C64?
        weak var memory: MemoryMap?
        weak var vic: VIC?
        weak var cia: CIA?
        autoreleasepool {
            let c64 = C64()
            machine = c64
            memory = c64.memory
            vic = c64.vic
            cia = c64.cia2
            c64.memory.ram[0x0234] = 0x42
            c64.cia2.writeRegister(0, value: 3)
            c64.cia2.writeRegister(2, value: 3)
            XCTAssertEqual(c64.vic.readMemory?(0x0234), 0x42)
            c64.memory.colorRAM[0] = 7
            XCTAssertEqual(c64.vic.readColorRAM?(0), 7)
            for bank in 0..<4 {
                c64.memory.ram[bank * 0x4000 + 0x0234] = UInt8(bank + 10)
                c64.cia2.writeRegister(0, value: UInt8(3 - bank))
                XCTAssertEqual(c64.vic.readMemory?(0x0234), UInt8(bank + 10))
                XCTAssertEqual(c64.vic.readMemory?(0x1234), c64.memory.vicRead(0x1234))
            }
        }
        XCTAssertNil(machine)
        XCTAssertNil(memory)
        XCTAssertNil(vic)
        XCTAssertNil(cia)
    }

    func testArithmeticSlotsMatchReferenceAcrossPALAndNTSC() {
        let schedules: [(C64VideoStandard, [Int])] = [
            (.pal, [57, 59, 61, 0, 2, 4, 6, 8]),
            (.ntsc, [58, 60, 62, 64, 1, 3, 5, 7])
        ]
        for (standard, starts) in schedules {
            let vic = VIC()
            vic.videoStandard = standard
            vic.rasterLine = 100
            // DMA, not the now-cleared enable register or current Y, owns BA.
            vic.spriteEnabled = 0
            for cycle in 0..<vic.rasterCyclesPerLine {
                vic.rasterCycle = cycle
                XCTAssertEqual(vic.spriteDMAFetchSlotForCurrentCycle(), starts.firstIndex(of: cycle))
                XCTAssertEqual(vic.spriteMiddleByteSlotForCurrentCycle(), starts.firstIndex { ($0 + 1) % vic.rasterCyclesPerLine == cycle })
                XCTAssertEqual(vic.spriteDMASlotForCurrentCycle(), starts.firstIndex { $0 == cycle || ($0 + 1) % vic.rasterCyclesPerLine == cycle })
                for mask in 0...255 {
                    vic.spriteDMACheckMask = UInt8(mask)
                    let expected = (0..<8).compactMap { sprite -> (Int, Int)? in
                        let distance = (starts[sprite] - cycle + vic.rasterCyclesPerLine) % vic.rasterCyclesPerLine
                        guard distance >= 1, distance <= 3, mask & (1 << sprite) != 0 else { return nil }
                        return (sprite, distance)
                    }.min { $0.1 < $1.1 }?.0
                    XCTAssertEqual(vic.spriteBAWarningSlotForCurrentCycle(), expected, "\(standard) cycle=\(cycle) mask=\(mask)")
                }
            }
        }
    }
}
