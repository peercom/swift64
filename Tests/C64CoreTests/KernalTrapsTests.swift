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

    func testSaveTrapWithoutMountedDiskReturnsKernalErrorInsteadOfSuccess() {
        let c64 = C64()
        c64.cpu.pc = KernalTraps.saveRoutine
        c64.cpu.sp = 0xFB
        c64.memory.ram[0x01FC] = 0x34
        c64.memory.ram[0x01FD] = 0x12
        c64.memory.ram[Int(KernalTraps.device)] = 8

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.cpu.pc, 0x1235)
        XCTAssertEqual(c64.cpu.sp, 0xFD)
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0x80)
        XCTAssertEqual(c64.cpu.a, 5)
        XCTAssertTrue(c64.cpu.getFlag(Flags.carry))
    }

    func testSaveTrapWritesPRGToMountedDisk() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        c64.memory.ram[0x002B] = 0x01
        c64.memory.ram[0x002C] = 0x08
        c64.memory.ram[0x0801] = 0x0B
        c64.memory.ram[0x0802] = 0x08
        c64.memory.ram[0x0803] = 0x0A
        c64.memory.ram[0x0804] = 0x00
        prepareKernalSaveTrap(c64, filename: "SAVED", startPointer: 0x2B, endAddress: 0x0805)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.cpu.pc, 0x1235)
        XCTAssertEqual(c64.cpu.sp, 0xFD)
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0)
        XCTAssertEqual(c64.cpu.a, 0)
        XCTAssertEqual(c64.cpu.x, 0x05)
        XCTAssertEqual(c64.cpu.y, 0x08)
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))

        let entry = try XCTUnwrap(c64.diskDrive.findFile("SAVED"))
        XCTAssertEqual(c64.diskDrive.readFileData(entry), [0x01, 0x08, 0x0B, 0x08, 0x0A, 0x00])

        let status = c64.emulationStatus
        XCTAssertEqual(status.highLevelDiskFormat, .d64)
        XCTAssertTrue(status.diskHasUnsavedChanges)
        XCTAssertTrue(status.canExportModifiedD64)
        XCTAssertNotNil(c64.exportedD64Image)

        c64.markExportedD64ImageSaved()
        let savedStatus = c64.emulationStatus
        XCTAssertFalse(savedStatus.diskHasUnsavedChanges)
        XCTAssertTrue(savedStatus.canExportModifiedD64)
    }

    func testSavedPRGRoundTripsThroughLoadTrapUsingFileAddress() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        c64.memory.ram[0x002B] = 0x00
        c64.memory.ram[0x002C] = 0x20
        c64.memory.ram[0x2000] = 0xA9
        c64.memory.ram[0x2001] = 0x2A
        c64.memory.ram[0x2002] = 0x60
        prepareKernalSaveTrap(c64, filename: "ROUND", startPointer: 0x2B, endAddress: 0x2003)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        c64.memory.ram[0x2000] = 0
        c64.memory.ram[0x2001] = 0
        c64.memory.ram[0x2002] = 0
        prepareKernalLoadTrap(c64, filename: "ROUND", verify: false, secondary: 1)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.memory.ram[0x2000], 0xA9)
        XCTAssertEqual(c64.memory.ram[0x2001], 0x2A)
        XCTAssertEqual(c64.memory.ram[0x2002], 0x60)
        XCTAssertEqual(c64.cpu.x, 0x03)
        XCTAssertEqual(c64.cpu.y, 0x20)
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
    }

    func testSaveTrapReplaceSyntaxOverwritesExistingPRG() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        c64.memory.ram[0x002B] = 0x00
        c64.memory.ram[0x002C] = 0x20
        c64.memory.ram[0x2000] = 0xA9
        c64.memory.ram[0x2001] = 0x01
        prepareKernalSaveTrap(c64, filename: "REPLACE", startPointer: 0x2B, endAddress: 0x2002)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        c64.memory.ram[0x2000] = 0xA9
        c64.memory.ram[0x2001] = 0x02
        c64.memory.ram[0x2002] = 0x60
        prepareKernalSaveTrap(c64, filename: "@0:REPLACE,P", startPointer: 0x2B, endAddress: 0x2003)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        let entry = try XCTUnwrap(c64.diskDrive.findFile("0:REPLACE"))
        XCTAssertEqual(c64.diskDrive.directory.count, 1)
        XCTAssertEqual(c64.diskDrive.readFileData(entry), [0x00, 0x20, 0xA9, 0x02, 0x60])
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
    }

    func testOpenCommandChannelScratchDeletesFileAndStatusCanBeRead() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        c64.memory.ram[0x002B] = 0x00
        c64.memory.ram[0x002C] = 0x20
        c64.memory.ram[0x2000] = 0xA9
        c64.memory.ram[0x2001] = 0x2A
        prepareKernalSaveTrap(c64, filename: "DELETE", startPointer: 0x2B, endAddress: 0x2002)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalOpenTrap(c64, filename: "S:DELETE", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertNil(c64.diskDrive.findFile("DELETE"))
        XCTAssertTrue(c64.emulationStatus.diskHasUnsavedChanges)

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        let status = readKernalChannelLine(c64)

        XCTAssertTrue(status.hasPrefix("01, FILES SCRATCHED"))
        prepareKernalCloseTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
    }

    func testOpenCommandChannelRenameRenamesFileAndStatusCanBeRead() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        c64.memory.ram[0x002B] = 0x00
        c64.memory.ram[0x002C] = 0x20
        c64.memory.ram[0x2000] = 0xA9
        c64.memory.ram[0x2001] = 0x7F
        prepareKernalSaveTrap(c64, filename: "OLD", startPointer: 0x2B, endAddress: 0x2002)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalOpenTrap(c64, filename: "R:NEW=OLD", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertNil(c64.diskDrive.findFile("OLD"))
        let entry = try XCTUnwrap(c64.diskDrive.findFile("NEW"))
        XCTAssertEqual(c64.diskDrive.readFileData(entry), [0x00, 0x20, 0xA9, 0x7F])

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "00, OK,00,00\r")
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

    private func prepareKernalOpenTrap(
        _ c64: C64,
        filename: String,
        logicalFile: UInt8,
        device: UInt8 = 8,
        secondary: UInt8
    ) {
        let nameAddress = 0x0200
        let bytes = Array(filename.utf8)
        for (index, byte) in bytes.enumerated() {
            c64.memory.ram[nameAddress + index] = byte
        }

        c64.memory.ram[Int(KernalTraps.fnLen)] = UInt8(bytes.count)
        c64.memory.ram[Int(KernalTraps.fnAddr)] = UInt8(nameAddress & 0xFF)
        c64.memory.ram[Int(KernalTraps.fnAddr + 1)] = UInt8(nameAddress >> 8)
        c64.memory.ram[Int(KernalTraps.logicalFile)] = logicalFile
        c64.memory.ram[Int(KernalTraps.device)] = device
        c64.memory.ram[Int(KernalTraps.secondaryAddr)] = secondary
        prepareTrapReturn(c64, pc: KernalTraps.openRoutine)
    }

    private func prepareKernalCHKINTrap(_ c64: C64, channel: UInt8) {
        c64.cpu.x = channel
        prepareTrapReturn(c64, pc: KernalTraps.chkinRoutine)
    }

    private func prepareKernalCloseTrap(_ c64: C64, channel: UInt8) {
        c64.cpu.a = channel
        prepareTrapReturn(c64, pc: KernalTraps.closeRoutine)
    }

    private func prepareKernalCHRINTrap(_ c64: C64) {
        prepareTrapReturn(c64, pc: KernalTraps.basinRoutine)
    }

    private func prepareTrapReturn(_ c64: C64, pc: UInt16) {
        c64.cpu.pc = pc
        c64.cpu.sp = 0xFB
        c64.memory.ram[0x01FC] = 0x34
        c64.memory.ram[0x01FD] = 0x12
    }

    private func readKernalChannelLine(_ c64: C64) -> String {
        var bytes: [UInt8] = []
        for _ in 0..<128 {
            prepareKernalCHRINTrap(c64)
            guard c64.kernalTraps.checkTrap() else { break }
            bytes.append(c64.cpu.a)
            if c64.cpu.a == 0x0D { break }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func prepareKernalSaveTrap(
        _ c64: C64,
        filename: String,
        startPointer: UInt8,
        endAddress: UInt16,
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
        c64.cpu.a = startPointer
        c64.cpu.x = UInt8(endAddress & 0xFF)
        c64.cpu.y = UInt8(endAddress >> 8)
        c64.cpu.pc = KernalTraps.saveRoutine
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

    private func makeBlankWritableD64() -> Data {
        let totalBytes = 174848
        var image = [UInt8](repeating: 0, count: totalBytes)
        let bamOffset = DiskDrive.trackOffset[18]

        image[bamOffset + 0] = 18
        image[bamOffset + 1] = 1
        image[bamOffset + 2] = 0x41

        for track in 1...35 {
            let entryOffset = bamOffset + track * 4
            let sectors = DiskDrive.sectorsPerTrack[track]
            var bitmap = [UInt8](repeating: 0, count: 3)
            for sector in 0..<sectors {
                bitmap[sector / 8] |= 1 << UInt8(sector % 8)
            }

            if track == 18 {
                bitmap[0] &= ~UInt8(0x03)
                image[entryOffset] = UInt8(sectors - 2)
            } else {
                image[entryOffset] = UInt8(sectors)
            }

            image[entryOffset + 1] = bitmap[0]
            image[entryOffset + 2] = bitmap[1]
            image[entryOffset + 3] = bitmap[2]
        }

        let diskName = Array("SAVE TEST".utf8)
        for i in 0..<16 {
            image[bamOffset + 0x90 + i] = i < diskName.count ? diskName[i] : 0xA0
        }
        image[bamOffset + 0xA2] = 0x53
        image[bamOffset + 0xA3] = 0x54
        image[bamOffset + 0xA5] = 0x32
        image[bamOffset + 0xA6] = 0x41

        let dirOffset = DiskDrive.trackOffset[18] + 256
        image[dirOffset + 0] = 0
        image[dirOffset + 1] = 0xFF

        return Data(image)
    }
}
