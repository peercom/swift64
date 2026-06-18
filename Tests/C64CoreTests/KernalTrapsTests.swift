import XCTest
import Emu6502
@testable import C64Core

final class KernalTrapsTests: XCTestCase {
    func testVerifyTrapComparesDiskDataWithoutModifyingRAM() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        c64.memory.ram[0x0801] = 0xA9
        c64.memory.ram[0x0802] = 0x2A
        prepareKernalLoadTrap(c64, filename: "HELLO", verify: true)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.memory.ram[0x0801], 0xA9)
        XCTAssertEqual(c64.memory.ram[0x0802], 0x2A)
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0)
        XCTAssertEqual(c64.cpu.x, 0x03)
        XCTAssertEqual(c64.cpu.y, 0x08)
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
    }

    func testVerifyTrapReportsMismatchWithoutOverwritingRAM() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        c64.memory.ram[0x0801] = 0xEA
        c64.memory.ram[0x0802] = 0x2A
        prepareKernalLoadTrap(c64, filename: "HELLO", verify: true)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.memory.ram[0x0801], 0xEA)
        XCTAssertEqual(c64.memory.ram[0x0802], 0x2A)
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0x10)
        XCTAssertEqual(c64.cpu.a, 0x10)
        XCTAssertTrue(c64.cpu.getFlag(Flags.carry))
    }

    func testUnsupportedSaveTrapReturnsKernalErrorInsteadOfSuccess() {
        let c64 = C64()
        c64.cpu.pc = KernalTraps.saveRoutine
        c64.cpu.sp = 0xFB
        c64.memory.ram[0x01FC] = 0x34
        c64.memory.ram[0x01FD] = 0x12

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.cpu.pc, 0x1235)
        XCTAssertEqual(c64.cpu.sp, 0xFD)
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0x80)
        XCTAssertEqual(c64.cpu.a, 5)
        XCTAssertTrue(c64.cpu.getFlag(Flags.carry))
    }

    private func prepareKernalLoadTrap(
        _ c64: C64,
        filename: String,
        verify: Bool,
        device: UInt8 = 8,
        secondary: UInt8 = 1
    ) {
        let nameAddress = 0x0200
        let bytes = Array(filename.utf8)
        for (index, byte) in bytes.enumerated() {
            c64.memory.ram[nameAddress + index] = byte
        }

        c64.memory.ram[Int(KernalTraps.fnLen)] = UInt8(bytes.count)
        c64.memory.ram[Int(KernalTraps.fnAddr)] = UInt8(nameAddress & 0xFF)
        c64.memory.ram[Int(KernalTraps.fnAddr + 1)] = UInt8(nameAddress >> 8)
        c64.memory.ram[Int(KernalTraps.logicalFile)] = 1
        c64.memory.ram[Int(KernalTraps.device)] = device
        c64.memory.ram[Int(KernalTraps.secondaryAddr)] = secondary
        c64.cpu.a = verify ? 1 : 0
        c64.cpu.pc = KernalTraps.loadRoutine
        c64.cpu.sp = 0xFB
        c64.memory.ram[0x01FC] = 0x34
        c64.memory.ram[0x01FD] = 0x12
    }

    private func makeMinimalD64() -> Data {
        let totalBytes = 174848
        var image = [UInt8](repeating: 0, count: totalBytes)

        let bamOffset = DiskDrive.trackOffset[18]
        image[bamOffset + 0] = 18
        image[bamOffset + 1] = 1
        image[bamOffset + 2] = 0x41

        for track in 1...35 {
            let offset = bamOffset + track * 4
            image[offset] = track == 18 ? 0 : UInt8(DiskDrive.sectorsPerTrack[track])
        }

        let diskName = Array("VERIFY TEST".utf8)
        for i in 0..<16 {
            image[bamOffset + 0x90 + i] = i < diskName.count ? diskName[i] : 0xA0
        }
        image[bamOffset + 0xA2] = 0x41
        image[bamOffset + 0xA3] = 0x42
        image[bamOffset + 0xA5] = 0x32
        image[bamOffset + 0xA6] = 0x41

        let dirOffset = DiskDrive.trackOffset[18] + 256
        image[dirOffset + 0] = 0
        image[dirOffset + 1] = 0xFF
        image[dirOffset + 2] = 0x82
        image[dirOffset + 3] = 1
        image[dirOffset + 4] = 0
        let fileName = Array("HELLO".utf8)
        for i in 0..<16 {
            image[dirOffset + 5 + i] = i < fileName.count ? fileName[i] : 0xA0
        }
        image[dirOffset + 30] = 1
        image[dirOffset + 31] = 0

        let fileOffset = DiskDrive.trackOffset[1]
        image[fileOffset + 0] = 0
        image[fileOffset + 1] = 6
        image[fileOffset + 2] = 0x01
        image[fileOffset + 3] = 0x08
        image[fileOffset + 4] = 0xA9
        image[fileOffset + 5] = 0x2A

        return Data(image)
    }
}
