import XCTest
@testable import C64Core

final class VICDataBusTests: XCTestCase {
    func testVICRAMAndCharacterROMDriveFloatingCPUReadsWithoutCPUReadHooks() {
        let memory = MemoryMap()
        var cpuReads = 0
        memory.onCPURead = { _, _ in cpuReads += 1 }
        memory.ram[0x8234] = 0xAB
        memory.colorRAM[0] = 7
        XCTAssertEqual(memory.vicRead(0x0234, portA: 1), 0xAB)
        XCTAssertEqual(cpuReads, 0)
        XCTAssertEqual(memory.read(0xDEAD), 0xAB)
        XCTAssertEqual(memory.read(0xD800), 0xA7)

        memory.charROM[0x234] = 0xC5
        XCTAssertEqual(memory.vicRead(0x1234, portA: 1), 0xC5)
        XCTAssertEqual(cpuReads, 2)
        XCTAssertEqual(memory.read(0xDF00), 0xC5)
    }

    func testCPUReadsCurrentPhi1FetchAcrossEveryPALAndNTSCSlot() {
        // Hardware-checked phi1timing sequences distinguish ECM idle graphics
        // from i-accesses and include the NTSC sprite-3 burst across line end.
        let schedules: [(MachineProfile, String)] = [
            (.palC64, "3i4i5i6i7irrrrr" + String(repeating: "g", count: 40) + "ii0i1i2i"),
            (.ntscC64, "i4i5i6i7iirrrrr" + String(repeating: "g", count: 40) + "iii0i1i2i3")
        ]
        for (profile, sequence) in schedules {
            for (targetCycle, slot) in sequence.enumerated() {
                let c64 = C64(machineProfile: profile)
                c64.trueDriveEmulationMode = .off
                c64.kernalTraps.enabled = false
                c64.vic.recordsBusAccessTraces = false
                c64.vic.controlReg1 = 0x4B
                c64.vic.memoryPointers = 0x14
                c64.vic.rasterLine = 20
                c64.vic.rasterCycle = (targetCycle + sequence.count - 3) % sequence.count
                c64.vic.refreshCounter = 0x80
                for i in 0..<256 { c64.memory.ram[0x3F00 + i] = 0x55 }
                c64.memory.ram[0x3FFF] = 0xFF
                c64.memory.ram[0x39FF] = 0xAA
                for i in 0..<8 { c64.memory.ram[0x07F8 + i] = UInt8(i) }
                c64.cpu.pc = 0x0600
                c64.memory.ram.replaceSubrange(0x0600..<0x0603, with: [0xAD, 0xAD, 0xDE])

                for _ in 0..<4 { c64.tickOneCycle() }

                let expected: UInt8
                switch slot {
                case "i": expected = 0xFF
                case "r": expected = 0x55
                case "g": expected = 0xAA
                default: expected = UInt8(String(slot))!
                }
                XCTAssertEqual(c64.cpu.a, expected, "cycle \(targetCycle), slot \(slot)")
            }
        }
    }
}
