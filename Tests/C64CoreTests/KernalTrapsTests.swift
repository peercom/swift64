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

    func testLoadTrapRespectsD64SectorReadErrorsAndCommandStatus() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64(firstFileSectorError: 23)))
        prepareKernalLoadTrap(c64, filename: "HELLO", verify: false)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertTrue(c64.cpu.getFlag(Flags.carry))
        XCTAssertEqual(c64.cpu.a, 23)
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0x80)
        XCTAssertNotEqual(c64.memory.ram[0x0801], 0xA9)
        XCTAssertEqual(c64.diskDrive.currentCommandStatus, "23, READ ERROR,01,00\r")

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "23, READ ERROR,01,00\r")
    }

    func testDirectoryLoadTrapRespectsD64DirectorySectorReadErrorsAndCommandStatus() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64(directorySectorError: 23)))
        prepareKernalLoadTrap(c64, filename: "$", verify: false)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertTrue(c64.cpu.getFlag(Flags.carry))
        XCTAssertEqual(c64.cpu.a, 23)
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0x80)
        XCTAssertEqual(c64.diskDrive.currentCommandStatus, "23, READ ERROR,18,01\r")

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "23, READ ERROR,18,01\r")
    }

    func testOpenTrapReportsD64SectorReadErrorsAsDosErrorCode() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64(firstFileSectorError: 23)))
        prepareKernalOpenTrap(c64, filename: "HELLO", logicalFile: 2, secondary: 2)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertTrue(c64.cpu.getFlag(Flags.carry))
        XCTAssertEqual(c64.cpu.a, 23)
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0x80)
        XCTAssertEqual(c64.diskDrive.currentCommandStatus, "23, READ ERROR,01,00\r")
    }

    func testOpenAppendTrapReportsD64SectorReadErrorsAsDosErrorCode() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64(firstFileSectorError: 23)))
        prepareKernalOpenTrap(c64, filename: "HELLO,P,A", logicalFile: 2, secondary: 2)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertTrue(c64.cpu.getFlag(Flags.carry))
        XCTAssertEqual(c64.cpu.a, 23)
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0x80)
        XCTAssertEqual(c64.diskDrive.currentCommandStatus, "23, READ ERROR,01,00\r")
    }

    func testOpenCommandChannelCopyReportsSourceD64ReadError() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64(firstFileSectorError: 23)))
        prepareKernalOpenTrap(c64, filename: "C:COPY=HELLO", logicalFile: 15, secondary: 15)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0)
        XCTAssertNil(c64.diskDrive.findFile("COPY"))

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "23, READ ERROR,01,00\r")
    }

    func testOpenCommandChannelScratchDoesNotDeleteFileWithD64ReadError() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64(firstFileSectorError: 23)))
        XCTAssertNotNil(c64.diskDrive.findFile("HELLO"))

        prepareKernalOpenTrap(c64, filename: "S:HELLO", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertNotNil(c64.diskDrive.findFile("HELLO"))
        XCTAssertFalse(c64.emulationStatus.diskHasUnsavedChanges)

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "23, READ ERROR,01,00\r")
    }

    func testDirectoryLoadTrapHonorsNameAndTypeFilters() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeSameNamePRGAndSEQD64()))
        prepareKernalLoadTrap(c64, filename: "$:HELLO,S", verify: false)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0)

        let endAddress = Int(c64.memory.ram[0x2D]) | (Int(c64.memory.ram[0x2E]) << 8)
        let loadedListing = String(decoding: c64.memory.ram[0x0801..<endAddress], as: UTF8.self)
        XCTAssertTrue(loadedListing.contains("HELLO"))
        XCTAssertTrue(loadedListing.contains("SEQ"))
        XCTAssertFalse(loadedListing.contains("PRG"))
    }

    func testLoadTrapMissingDiskFileReportsFileNotFoundCommandStatus() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        prepareKernalLoadTrap(c64, filename: "MISSING", verify: false)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertTrue(c64.cpu.getFlag(Flags.carry))
        XCTAssertEqual(c64.cpu.a, 4)
        XCTAssertEqual(c64.diskDrive.currentCommandStatus, "62, FILE NOT FOUND,00,00\r")

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "62, FILE NOT FOUND,00,00\r")
    }

    func testLoadTrapWithoutMountedDiskReportsDriveNotReadyCommandStatus() {
        let c64 = C64()
        prepareKernalLoadTrap(c64, filename: "HELLO", verify: false)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertTrue(c64.cpu.getFlag(Flags.carry))
        XCTAssertEqual(c64.cpu.a, 4)
        XCTAssertEqual(c64.diskDrive.currentCommandStatus, "74, DRIVE NOT READY,00,00\r")

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "74, DRIVE NOT READY,00,00\r")
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

    func testCommandChannelOpenWithoutMountedDiskReportsDriveNotReady() {
        let c64 = C64()

        prepareKernalOpenTrap(c64, filename: "I", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0)

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "74, DRIVE NOT READY,00,00\r")
    }

    func testBufferChannelOpenWithoutMountedDiskCanBeWrittenAndReportsDriveNotReadyOnDiskWrite() {
        let c64 = C64()

        prepareKernalOpenTrap(c64, filename: "#", logicalFile: 2, secondary: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0)

        prepareKernalCHKOUTTrap(c64, channel: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHROUTTrap(c64, byte: 0xDE)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalOpenTrap(c64, filename: "B-W:2,0,1,0", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "74, DRIVE NOT READY,00,00\r")
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

    func testSaveTrapRespectsD64DirectorySectorReadErrors() {
        let c64 = C64()
        var image = [UInt8](makeBlankWritableD64())
        image.append(contentsOf: d64ErrorTable(firstFileSectorError: nil, directorySectorError: 23))
        XCTAssertTrue(c64.mountDisk(Data(image), fileName: "bad-dir.d64"))
        c64.memory.ram[0x002B] = 0x01
        c64.memory.ram[0x002C] = 0x08
        c64.memory.ram[0x0801] = 0x60
        prepareKernalSaveTrap(c64, filename: "BLOCKED", startPointer: 0x2B, endAddress: 0x0802)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.diskDrive.currentCommandStatus, "23, READ ERROR,18,01\r")
        XCTAssertNil(c64.diskDrive.findFile("BLOCKED"))
        XCTAssertFalse(c64.emulationStatus.diskHasUnsavedChanges)
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0x80)
        XCTAssertTrue(c64.cpu.getFlag(Flags.carry))
    }

    func testSaveTrapWritesPRGToVirtualTape() throws {
        let c64 = C64()
        c64.memory.ram[0x002B] = 0x01
        c64.memory.ram[0x002C] = 0x08
        c64.memory.ram[0x0801] = 0x0B
        c64.memory.ram[0x0802] = 0x08
        c64.memory.ram[0x0803] = 0x0A
        c64.memory.ram[0x0804] = 0x00
        prepareKernalSaveTrap(c64, filename: "TAPESAVE", startPointer: 0x2B, endAddress: 0x0805, device: 1)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.cpu.pc, 0x1235)
        XCTAssertEqual(c64.cpu.sp, 0xFD)
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0)
        XCTAssertEqual(c64.cpu.a, 0)
        XCTAssertEqual(c64.cpu.x, 0x05)
        XCTAssertEqual(c64.cpu.y, 0x08)
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
        XCTAssertTrue(c64.tapeUnit.hasUnsavedChanges)
        XCTAssertEqual(c64.tapeUnit.findEntry("TAPESAVE"), 0)
        XCTAssertEqual(c64.tapeUnit.readEntry(0), [0x01, 0x08, 0x0B, 0x08, 0x0A, 0x00])
        XCTAssertTrue(c64.emulationStatus.tapeHasUnsavedChanges)
        XCTAssertTrue(c64.emulationStatus.canExportSavedT64)

        let exported = try XCTUnwrap(c64.tapeUnit.exportedT64Image)
        let remounted = TapeUnit()
        XCTAssertTrue(remounted.mount(exported))
        XCTAssertEqual(remounted.readEntry(0), [0x01, 0x08, 0x0B, 0x08, 0x0A, 0x00])

        c64.markExportedT64ImageSaved()
        XCTAssertFalse(c64.emulationStatus.tapeHasUnsavedChanges)
        XCTAssertTrue(c64.emulationStatus.canExportSavedT64)
    }

    func testSavedTapePRGRoundTripsThroughLoadTrapUsingFileAddress() {
        let c64 = C64()
        c64.memory.ram[0x002B] = 0x00
        c64.memory.ram[0x002C] = 0x20
        c64.memory.ram[0x2000] = 0xA9
        c64.memory.ram[0x2001] = 0x2A
        c64.memory.ram[0x2002] = 0x60
        prepareKernalSaveTrap(c64, filename: "TROUND", startPointer: 0x2B, endAddress: 0x2003, device: 1)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.emulationStatus.mountedTapeName, "saved-tape.t64")

        c64.memory.ram[0x2000] = 0
        c64.memory.ram[0x2001] = 0
        c64.memory.ram[0x2002] = 0
        prepareKernalLoadTrap(c64, filename: "TROUND", verify: false, device: 1, secondary: 1)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.memory.ram[0x2000], 0xA9)
        XCTAssertEqual(c64.memory.ram[0x2001], 0x2A)
        XCTAssertEqual(c64.memory.ram[0x2002], 0x60)
        XCTAssertEqual(c64.cpu.x, 0x03)
        XCTAssertEqual(c64.cpu.y, 0x20)
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
    }

    func testLoadTrapReadsStandardCBMTAPDuplicateBlocks() {
        let c64 = C64()
        var header = [UInt8](repeating: 0, count: 21)
        header[0] = 1
        header[1] = 0x00
        header[2] = 0x20
        header[3] = 0x03
        header[4] = 0x20
        writeASCII("DUPTAPE", into: &header, at: 5, maxLength: 16)
        let data = [UInt8]([0xA9, 0x7F, 0x60])
        XCTAssertTrue(c64.mountTape(makeStandardCBMTAP(blocks: [header, header, data, data]), fileName: "duptape.tap"))

        prepareKernalLoadTrap(c64, filename: "DUPTAPE", verify: false, device: 1, secondary: 1)

        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.memory.ram[0x2000], 0xA9)
        XCTAssertEqual(c64.memory.ram[0x2001], 0x7F)
        XCTAssertEqual(c64.memory.ram[0x2002], 0x60)
        XCTAssertEqual(c64.cpu.x, 0x03)
        XCTAssertEqual(c64.cpu.y, 0x20)
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
    }

    func testLoadTrapReadsNamedSecondProgramFromStandardCBMTAP() {
        let c64 = C64()
        var firstHeader = [UInt8](repeating: 0, count: 21)
        firstHeader[0] = 1
        firstHeader[1] = 0x01
        firstHeader[2] = 0x08
        firstHeader[3] = 0x03
        firstHeader[4] = 0x08
        writeASCII("FIRST", into: &firstHeader, at: 5, maxLength: 16)
        var secondHeader = [UInt8](repeating: 0, count: 21)
        secondHeader[0] = 1
        secondHeader[1] = 0x00
        secondHeader[2] = 0x20
        secondHeader[3] = 0x03
        secondHeader[4] = 0x20
        writeASCII("SECOND", into: &secondHeader, at: 5, maxLength: 16)
        XCTAssertTrue(c64.mountTape(makeStandardCBMTAP(blocks: [
            firstHeader,
            [0xA9, 0x01],
            secondHeader,
            [0xA9, 0x02, 0x60]
        ]), fileName: "two-programs.tap"))

        prepareKernalLoadTrap(c64, filename: "SECOND", verify: false, device: 1, secondary: 1)

        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.memory.ram[0x2000], 0xA9)
        XCTAssertEqual(c64.memory.ram[0x2001], 0x02)
        XCTAssertEqual(c64.memory.ram[0x2002], 0x60)
        XCTAssertEqual(c64.cpu.x, 0x03)
        XCTAssertEqual(c64.cpu.y, 0x20)
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
    }

    func testLoadTrapReadsCleanSecondStandardCBMTAPDataCopy() {
        let c64 = C64()
        var header = [UInt8](repeating: 0, count: 21)
        header[0] = 1
        header[1] = 0x00
        header[2] = 0x20
        header[3] = 0x03
        header[4] = 0x20
        writeASCII("REPAIRED", into: &header, at: 5, maxLength: 16)
        let data = [UInt8]([0xA9, 0x7F, 0x60])
        var payload: [UInt8] = []
        payload.append(contentsOf: encodeStandardCBMTAPBlock(header))
        payload.append(contentsOf: encodeStandardCBMTAPBlock(header))
        var damagedData = encodeStandardCBMTAPBlock(data)
        damageStandardCBMParity(byteIndex: 0, in: &damagedData)
        payload.append(contentsOf: damagedData)
        payload.append(contentsOf: encodeStandardCBMTAPBlock(data))
        let tap = makeTAP(payload: payload)
        XCTAssertTrue(c64.mountTape(tap, fileName: "repaired.tap"))

        prepareKernalLoadTrap(c64, filename: "REPAIRED", verify: false, device: 1, secondary: 1)

        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.memory.ram[0x2000], 0xA9)
        XCTAssertEqual(c64.memory.ram[0x2001], 0x7F)
        XCTAssertEqual(c64.memory.ram[0x2002], 0x60)
        XCTAssertEqual(c64.cpu.x, 0x03)
        XCTAssertEqual(c64.cpu.y, 0x20)
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
    }

    func testLoadTrapRepairsStandardCBMTAPDataBytesAcrossDuplicateCopies() {
        let c64 = C64()
        var header = [UInt8](repeating: 0, count: 21)
        header[0] = 1
        header[1] = 0x00
        header[2] = 0x20
        header[3] = 0x03
        header[4] = 0x20
        writeASCII("VOTED", into: &header, at: 5, maxLength: 16)
        let data = [UInt8]([0xA9, 0x7F, 0x60])
        var firstCopy = encodeStandardCBMTAPBlock(data)
        var secondCopy = encodeStandardCBMTAPBlock(data)
        damageStandardCBMParity(byteIndex: 0, in: &firstCopy)
        damageStandardCBMParity(byteIndex: 1, in: &secondCopy)
        var payload: [UInt8] = []
        payload.append(contentsOf: encodeStandardCBMTAPBlock(header))
        payload.append(contentsOf: encodeStandardCBMTAPBlock(header))
        payload.append(contentsOf: firstCopy)
        payload.append(contentsOf: secondCopy)
        XCTAssertTrue(c64.mountTape(makeTAP(payload: payload), fileName: "voted.tap"))

        prepareKernalLoadTrap(c64, filename: "VOTED", verify: false, device: 1, secondary: 1)

        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.memory.ram[0x2000], 0xA9)
        XCTAssertEqual(c64.memory.ram[0x2001], 0x7F)
        XCTAssertEqual(c64.memory.ram[0x2002], 0x60)
        XCTAssertEqual(c64.cpu.x, 0x03)
        XCTAssertEqual(c64.cpu.y, 0x20)
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
    }

    func testLoadTrapRejectsConflictingStandardCBMTAPDuplicateData() {
        let c64 = C64()
        var header = [UInt8](repeating: 0, count: 21)
        header[0] = 1
        header[1] = 0x00
        header[2] = 0x20
        header[3] = 0x03
        header[4] = 0x20
        writeASCII("CONFLICT", into: &header, at: 5, maxLength: 16)
        XCTAssertTrue(c64.mountTape(makeStandardCBMTAP(blocks: [
            header,
            header,
            [0xA9, 0x01, 0x60],
            [0xA9, 0x02, 0x60]
        ]), fileName: "conflict.tap"))

        prepareKernalLoadTrap(c64, filename: "CONFLICT", verify: false, device: 1, secondary: 1)

        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.memory.ram[0x2000], 0)
        XCTAssertEqual(c64.memory.ram[0x2001], 0)
        XCTAssertEqual(c64.memory.ram[0x2002], 0)
        XCTAssertEqual(c64.memory.ram[Int(KernalTraps.status)], 0x42)
        XCTAssertEqual(c64.cpu.a, 4)
        XCTAssertTrue(c64.cpu.getFlag(Flags.carry))
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

    func testDiskLoadTrapReturnsThroughBASICVectorsForSystemAreaLoader() {
        // A boot file that loads over $0300-$0303 autostarts on hardware when BASIC jumps
        // through its warm-start vector after the LOAD returns; the trap must return
        // normally and leave the loaded vector in place instead of jumping into the file.
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        var payload = [UInt8](repeating: 0xEA, count: 0x0304 - 0x02A7)
        payload[0] = 0xA2  // LDX #$02 at $02A7
        payload[1] = 0x02
        payload[0x0300 - 0x02A7] = 0x8B  // error vector $E38B
        payload[0x0301 - 0x02A7] = 0xE3
        payload[0x0302 - 0x02A7] = 0xA7  // main-loop vector -> $02A7
        payload[0x0303 - 0x02A7] = 0x02
        XCTAssertTrue(c64.diskDrive.savePRG(filename: "BOOT", data: [0xA7, 0x02] + payload))
        prepareKernalLoadTrap(c64, filename: "BOOT", verify: false, secondary: 1)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.memory.ram[0x02A7], 0xA2)
        XCTAssertEqual(c64.memory.ram[0x0302], 0xA7)
        XCTAssertEqual(c64.memory.ram[0x0303], 0x02)
        XCTAssertEqual(c64.cpu.pc, 0x1235, "trap returns to the caller, BASIC then jumps through $0302")
        XCTAssertEqual(c64.cpu.x, 0x04)
        XCTAssertEqual(c64.cpu.y, 0x03)
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
    }

    func testDiskLoadTrapReturnsThroughStackOverwrittenByBootFile() {
        // Boot files that load over the stack page replace the LOAD caller's return address,
        // so the Kernal's RTS lands in the file. The trap must pop the overwritten slot.
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        // Loads $01F8-$0207: fill the stack slots with $0202 so any popped return lands at $0203.
        var payload = [UInt8](repeating: 0x02, count: 8)
        payload += [0xEA, 0xEA, 0xEA, 0xA9, 0x01, 0x4C, 0x03, 0x02]  // $0200..$0207
        XCTAssertTrue(c64.diskDrive.savePRG(filename: "MENU", data: [0xF8, 0x01] + payload))
        prepareKernalLoadTrap(c64, filename: "MENU", verify: false, secondary: 1)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.memory.ram[0x01FC], 0x02)
        XCTAssertEqual(c64.memory.ram[0x01FD], 0x02)
        XCTAssertEqual(c64.cpu.pc, 0x0203)
        XCTAssertEqual(c64.cpu.sp, 0xFD)
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
    }

    func testDiskLoadTrapKeepsKernalVectorTableLoadedByBootFile() {
        // Ocean-style boot files load a replacement vector table at $0316 whose CHROUT entry
        // points into the file; the next Kernal print then starts the loader. The trap must
        // not execute the table as code.
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        var payload = [UInt8](repeating: 0x00, count: 0x0340 - 0x0316)
        payload[0x0326 - 0x0316] = 0x3C  // CHROUT -> $033C
        payload[0x0327 - 0x0316] = 0x03
        payload[0x033C - 0x0316] = 0x78  // SEI
        payload[0x033D - 0x0316] = 0x4C  // JMP $4000
        payload[0x033E - 0x0316] = 0x00
        payload[0x033F - 0x0316] = 0x40
        XCTAssertTrue(c64.diskDrive.savePRG(filename: "HUDSON", data: [0x16, 0x03] + payload))
        prepareKernalLoadTrap(c64, filename: "HUDSON", verify: false, secondary: 1)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.cpu.pc, 0x1235)
        XCTAssertEqual(c64.memory.ram[0x0326], 0x3C)
        XCTAssertEqual(c64.memory.ram[0x0327], 0x03)
        XCTAssertEqual(c64.memory.ram[0x033C], 0x78)
    }

    func testLoadTrapHandlesFileEndingAtTopOfMemory() {
        // A full 8K file at $E000 ends exactly at $FFFF; the Kernal reports the wrapped end
        // address $0000 in X/Y and the trap must not trap on the wrap.
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        let payload = [UInt8](repeating: 0xEA, count: 0x2000)
        XCTAssertTrue(c64.diskDrive.savePRG(filename: "TOP", data: [0x00, 0xE0] + payload))
        prepareKernalLoadTrap(c64, filename: "TOP", verify: false, secondary: 1)

        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.memory.ram[0xE000], 0xEA)
        XCTAssertEqual(c64.memory.ram[0xFFFF], 0xEA)
        XCTAssertEqual(c64.cpu.x, 0x00)
        XCTAssertEqual(c64.cpu.y, 0x00)
        XCTAssertEqual(c64.memory.ram[0xAE], 0x00)
        XCTAssertEqual(c64.memory.ram[0xAF], 0x00)
        XCTAssertFalse(c64.cpu.getFlag(Flags.carry))
    }

    func testLoadTrapPrintsKernalMessagesOnlyInDirectModeBeforeTheTransfer() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        // 1,000 bytes of $55 loading at $0400 cover the whole default screen.
        let payload = [UInt8](repeating: 0x55, count: 1000)
        XCTAssertTrue(c64.diskDrive.savePRG(filename: "SCREEN", data: [0x00, 0x04] + payload))

        // Program mode (MSGFLG bit 7 clear): nothing is printed, the file data is intact.
        c64.memory.ram[0x9D] = 0x00
        c64.memory.ram[0x0288] = 0x04
        c64.memory.ram[0xD6] = 5
        c64.memory.ram[0xD3] = 0
        prepareKernalLoadTrap(c64, filename: "SCREEN", verify: false, secondary: 1)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertTrue(c64.memory.ram[0x0400..<0x07E8].allSatisfy { $0 == 0x55 })
        XCTAssertEqual(c64.memory.ram[0xD6], 5)
        XCTAssertEqual(c64.memory.ram[0xD3], 0)

        // Direct mode: "\rSEARCHING FOR name" and "\rLOADING" are printed with the Kernal's
        // line discipline (cursor left on the LOADING line, no trailing CR) and before the
        // transfer, so the loaded data wins on the rows the messages used.
        for address in 0x0400..<0x07E8 { c64.memory.ram[address] = 0x20 }
        c64.memory.ram[0x9D] = 0x80
        c64.memory.ram[0xD6] = 5
        c64.memory.ram[0xD3] = 0
        prepareKernalLoadTrap(c64, filename: "SCREEN", verify: false, secondary: 1)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertTrue(c64.memory.ram[0x0400..<0x07E8].allSatisfy { $0 == 0x55 })
        XCTAssertEqual(c64.memory.ram[0xD6], 7, "SEARCHING on row 6, LOADING on row 7")
        XCTAssertEqual(c64.memory.ram[0xD3], 7, "cursor stays after LOADING")

        // A file that does not touch the screen leaves both messages visible.
        XCTAssertTrue(c64.diskDrive.savePRG(filename: "HIGH", data: [0x00, 0xC0, 0xEA, 0x60]))
        for address in 0x0400..<0x07E8 { c64.memory.ram[address] = 0x20 }
        c64.memory.ram[0xD6] = 5
        c64.memory.ram[0xD3] = 0
        prepareKernalLoadTrap(c64, filename: "HIGH", verify: false, secondary: 1)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        let row6 = c64.memory.ram[(0x0400 + 6 * 40)..<(0x0400 + 6 * 40 + 18)].map { UInt8($0) }
        let row7 = c64.memory.ram[(0x0400 + 7 * 40)..<(0x0400 + 7 * 40 + 7)].map { UInt8($0) }
        XCTAssertEqual(row6, Array("SEARCHING FOR HIGH".utf8).map { $0 >= 0x41 ? $0 - 0x40 : $0 })
        XCTAssertEqual(row7, Array("LOADING".utf8).map { $0 - 0x40 })
        XCTAssertEqual(c64.memory.ram[0xD6], 7)
        XCTAssertEqual(c64.memory.ram[0xD3], 7)
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

    func testCommandChannelOutputExecutesOnCloseAndStatusCanBeRead() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        c64.memory.ram[0x002B] = 0x00
        c64.memory.ram[0x002C] = 0x20
        c64.memory.ram[0x2000] = 0xA9
        c64.memory.ram[0x2001] = 0x2A
        prepareKernalSaveTrap(c64, filename: "DELETE", startPointer: 0x2B, endAddress: 0x2002)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKOUTTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        for byte in Array("S:DELETE\r".utf8) {
            prepareKernalCHROUTTrap(c64, byte: byte)
            XCTAssertTrue(c64.kernalTraps.checkTrap())
        }
        prepareKernalCloseTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertNil(c64.diskDrive.findFile("DELETE"))
        XCTAssertTrue(c64.emulationStatus.diskHasUnsavedChanges)

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertTrue(readKernalChannelLine(c64).hasPrefix("01, FILES SCRATCHED"))

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "00, OK,00,00\r")
    }

    func testCommandChannelMemoryReadViaKernalOutputAndInput() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKOUTTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        for byte in Array("M-W:$0600,2,$BA,$5E\r".utf8) {
            prepareKernalCHROUTTrap(c64, byte: byte)
            XCTAssertTrue(c64.kernalTraps.checkTrap())
        }

        for byte in Array("M-R:$0600,2\r".utf8) {
            prepareKernalCHROUTTrap(c64, byte: byte)
            XCTAssertTrue(c64.kernalTraps.checkTrap())
        }

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0xBA)
        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0x5E)
    }

    func testCommandChannelLongMemoryAliasesViaKernalOutputAndInput() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKOUTTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        for byte in Array("MEMORY-WRITE:$0610,2,$C0,$DE\r".utf8) {
            prepareKernalCHROUTTrap(c64, byte: byte)
            XCTAssertTrue(c64.kernalTraps.checkTrap())
        }

        for byte in Array("MEMORY-READ:$0610,2\r".utf8) {
            prepareKernalCHROUTTrap(c64, byte: byte)
            XCTAssertTrue(c64.kernalTraps.checkTrap())
        }

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0xC0)
        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0xDE)
    }

    func testCommandChannelResetViaKernalOutputClearsDriveMemory() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKOUTTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        for byte in Array("M-W:$0400,1,$7F\r".utf8) {
            prepareKernalCHROUTTrap(c64, byte: byte)
            XCTAssertTrue(c64.kernalTraps.checkTrap())
        }
        for byte in Array("UJ\r".utf8) {
            prepareKernalCHROUTTrap(c64, byte: byte)
            XCTAssertTrue(c64.kernalTraps.checkTrap())
        }
        for byte in Array("M-R:$0400,1\r".utf8) {
            prepareKernalCHROUTTrap(c64, byte: byte)
            XCTAssertTrue(c64.kernalTraps.checkTrap())
        }

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0x00)
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

    func testOpenCommandChannelCopyDuplicatesFileAndStatusCanBeRead() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        c64.memory.ram[0x002B] = 0x00
        c64.memory.ram[0x002C] = 0x20
        c64.memory.ram[0x2000] = 0xA9
        c64.memory.ram[0x2001] = 0x7F
        prepareKernalSaveTrap(c64, filename: "SOURCE", startPointer: 0x2B, endAddress: 0x2002)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalOpenTrap(c64, filename: "C:COPY=SOURCE", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertNotNil(c64.diskDrive.findFile("SOURCE"))
        let copied = try XCTUnwrap(c64.diskDrive.findFile("COPY"))
        XCTAssertEqual(c64.diskDrive.readFileData(copied), [0x00, 0x20, 0xA9, 0x7F])
        XCTAssertTrue(c64.emulationStatus.diskHasUnsavedChanges)

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "00, OK,00,00\r")
    }

    func testOpenCommandChannelNewFormatsDiskAndStatusCanBeRead() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        let blankFreeBlocks = c64.diskDrive.freeBlocks()
        c64.memory.ram[0x002B] = 0x00
        c64.memory.ram[0x002C] = 0x20
        c64.memory.ram[0x2000] = 0xA9
        c64.memory.ram[0x2001] = 0x7F
        prepareKernalSaveTrap(c64, filename: "OLD", startPointer: 0x2B, endAddress: 0x2002)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertNotNil(c64.diskDrive.findFile("OLD"))

        prepareKernalOpenTrap(c64, filename: "N:FORMATTED,FT", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.diskDrive.diskName, "formatted")
        XCTAssertEqual(c64.diskDrive.diskID, "ft")
        XCTAssertEqual(c64.diskDrive.directory.count, 0)
        XCTAssertNil(c64.diskDrive.findFile("OLD"))
        XCTAssertEqual(c64.diskDrive.freeBlocks(), blankFreeBlocks)
        XCTAssertTrue(c64.emulationStatus.diskHasUnsavedChanges)

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "00, OK,00,00\r")
    }

    func testOpenCommandChannelValidateRebuildsBAMAndStatusCanBeRead() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        let blankFreeBlocks = c64.diskDrive.freeBlocks()
        c64.memory.ram[0x002B] = 0x00
        c64.memory.ram[0x002C] = 0x20
        c64.memory.ram[0x2000] = 0xA9
        c64.memory.ram[0x2001] = 0x7F
        prepareKernalSaveTrap(c64, filename: "KEEP", startPointer: 0x2B, endAddress: 0x2002)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.diskDrive.freeBlocks(), blankFreeBlocks - 1)

        var corrupted = try XCTUnwrap(c64.exportedD64Image).map { $0 }
        let trackOneBAM = DiskDrive.trackOffset[18] + 1 * 4
        corrupted[trackOneBAM] = 0
        corrupted[trackOneBAM + 1] = 0
        corrupted[trackOneBAM + 2] = 0
        corrupted[trackOneBAM + 3] = 0
        XCTAssertTrue(c64.mountDisk(Data(corrupted), fileName: "corrupt.d64"))
        XCTAssertLessThan(c64.diskDrive.freeBlocks(), blankFreeBlocks - 1)

        prepareKernalOpenTrap(c64, filename: "V:", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        XCTAssertEqual(c64.diskDrive.freeBlocks(), blankFreeBlocks - 1)
        XCTAssertTrue(c64.emulationStatus.diskHasUnsavedChanges)
        let entry = try XCTUnwrap(c64.diskDrive.findFile("KEEP"))
        XCTAssertEqual(c64.diskDrive.readFileData(entry), [0x00, 0x20, 0xA9, 0x7F])

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "00, OK,00,00\r")
    }

    func testOpenCommandChannelBlockReadFeedsTargetChannel() {
        let c64 = C64()
        var image = [UInt8](makeBlankWritableD64())
        let sectorOffset = DiskDrive.trackOffset[1] + 2 * 256
        image[sectorOffset] = 0x03
        image[sectorOffset + 1] = 0xDE
        image[sectorOffset + 2] = 0xAD
        image[sectorOffset + 3] = 0xBE
        XCTAssertTrue(c64.mountDisk(Data(image), fileName: "block.d64"))

        prepareKernalOpenTrap(c64, filename: "B-R:2,0,1,2", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "00, OK,00,00\r")

        prepareKernalCHKINTrap(c64, channel: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0xDE)
        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0xAD)
        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0xBE)
    }

    func testOpenCommandChannelBlockReadReportsInvalidTrackSector() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))

        prepareKernalOpenTrap(c64, filename: "B-R:2,0,99,0", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "66, ILLEGAL TRACK OR SECTOR,99,00\r")
    }

    func testOpenCommandChannelBlockReadReportsExtendedD64SectorError() throws {
        let c64 = C64()
        var image = [UInt8](makeMinimalD64())
        image.append(contentsOf: [UInt8](repeating: 0, count: 200_704 - image.count))
        image.append(contentsOf: [UInt8](repeating: 0x01, count: 784))
        let geometry = try XCTUnwrap(DiskDrive.d64Geometry(forByteCount: image.count))
        let errorOffset = try XCTUnwrap(geometry.errorInfoOffset)
        image[errorOffset + 783] = 23
        XCTAssertTrue(c64.mountDisk(Data(image), fileName: "extended-errors.d64"))

        prepareKernalOpenTrap(c64, filename: "B-R:2,0,41,15", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "23, READ ERROR,41,15\r")
    }

    func testBufferedCommandChannelBinaryU1FeedsTargetChannel() {
        let c64 = C64()
        var image = [UInt8](makeBlankWritableD64())
        let sectorOffset = DiskDrive.trackOffset[1] + 3 * 256
        image[sectorOffset] = 0x12
        image[sectorOffset + 1] = 0x34
        XCTAssertTrue(c64.mountDisk(Data(image), fileName: "binaryu1.d64"))

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKOUTTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        for byte in [UInt8(ascii: "U"), UInt8(ascii: "1"), UInt8(ascii: ":"), 2, 0, 1, 3] {
            prepareKernalCHROUTTrap(c64, byte: byte)
            XCTAssertTrue(c64.kernalTraps.checkTrap())
        }
        prepareKernalCloseTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalCHKINTrap(c64, channel: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0x12)
        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0x34)
    }

    func testBufferedCommandChannelBinaryBlockReadUsesBufferPointerLength() {
        let c64 = C64()
        var image = [UInt8](makeBlankWritableD64())
        let sectorOffset = DiskDrive.trackOffset[1] + 3 * 256
        image[sectorOffset] = 0x02
        image[sectorOffset + 1] = 0x12
        image[sectorOffset + 2] = 0x34
        XCTAssertTrue(c64.mountDisk(Data(image), fileName: "binarybr.d64"))

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKOUTTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        writeKernalBytes(c64, [UInt8(ascii: "B"), UInt8(ascii: "-"), UInt8(ascii: "R"), UInt8(ascii: ":"), 2, 0, 1, 3])
        prepareKernalCloseTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalCHKINTrap(c64, channel: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0x12)
        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0x34)
    }

    func testOpenCommandChannelAcceptsLongBlockReadAlias() {
        let c64 = C64()
        var image = [UInt8](makeBlankWritableD64())
        let sectorOffset = DiskDrive.trackOffset[1] + 2 * 256
        image[sectorOffset] = 0x02
        image[sectorOffset + 1] = 0xCA
        image[sectorOffset + 2] = 0xFE
        XCTAssertTrue(c64.mountDisk(Data(image), fileName: "longblock.d64"))

        prepareKernalOpenTrap(c64, filename: "BLOCK-READ:2,0,1,2", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "00, OK,00,00\r")

        prepareKernalCHKINTrap(c64, channel: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0xCA)
        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0xFE)
    }

    func testOpenCommandChannelBlockExecuteFeedsTargetChannel() {
        let c64 = C64()
        var image = [UInt8](makeBlankWritableD64())
        let sectorOffset = DiskDrive.trackOffset[1] + 2 * 256
        image[sectorOffset] = 0xA9
        image[sectorOffset + 1] = 0x42
        image[sectorOffset + 2] = 0x60
        XCTAssertTrue(c64.mountDisk(Data(image), fileName: "blockexec.d64"))

        prepareKernalOpenTrap(c64, filename: "B-E:2,0,1,2", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "00, OK,00,00\r")

        prepareKernalCHKINTrap(c64, channel: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0xA9)
        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0x42)
        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, 0x60)
    }

    func testOpenCommandChannelBlockWriteUsesKernalOutputBuffer() throws {
        let c64 = C64()
        var image = [UInt8](makeBlankWritableD64())
        image.append(contentsOf: [UInt8](repeating: 0x01, count: 683))
        image[174848 + 2] = 23
        XCTAssertTrue(c64.mountDisk(Data(image), fileName: "blockwrite.d64"))

        prepareKernalOpenTrap(c64, filename: "#", logicalFile: 2, secondary: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalOpenTrap(c64, filename: "B-P:2,4", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKOUTTrap(c64, channel: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHROUTTrap(c64, byte: 0xDE)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHROUTTrap(c64, byte: 0xAD)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHROUTTrap(c64, byte: 0xBE)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalOpenTrap(c64, filename: "B-W:2,0,1,2", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        let sector = try XCTUnwrap(c64.diskDrive.readSector(track: 1, sector: 2))
        XCTAssertEqual(Array(sector.prefix(8)), [7, 0, 0, 0, 0xDE, 0xAD, 0xBE, 0])
        XCTAssertEqual(c64.diskDrive.readSectorErrorCode(track: 1, sector: 2), 0x01)
        XCTAssertTrue(c64.emulationStatus.diskHasUnsavedChanges)

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "00, OK,00,00\r")
    }

    func testBufferedCommandChannelBinaryBlockWriteUsesBufferPointerSemantics() throws {
        let c64 = C64()
        var image = [UInt8](makeBlankWritableD64())
        image.append(contentsOf: [UInt8](repeating: 0x01, count: 683))
        image[174848 + 2] = 23
        XCTAssertTrue(c64.mountDisk(Data(image), fileName: "binarybw.d64"))

        prepareKernalOpenTrap(c64, filename: "#", logicalFile: 2, secondary: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKOUTTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        writeKernalBytes(c64, [UInt8(ascii: "B"), UInt8(ascii: "-"), UInt8(ascii: "P"), UInt8(ascii: ":"), 2, 4])
        prepareKernalCloseTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalCHKOUTTrap(c64, channel: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        writeKernalBytes(c64, [0xDE, 0xAD, 0xBE])

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKOUTTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        writeKernalBytes(c64, [UInt8(ascii: "B"), UInt8(ascii: "-"), UInt8(ascii: "W"), UInt8(ascii: ":"), 2, 0, 1, 2])
        prepareKernalCloseTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        let sector = try XCTUnwrap(c64.diskDrive.readSector(track: 1, sector: 2))
        XCTAssertEqual(Array(sector.prefix(8)), [7, 0, 0, 0, 0xDE, 0xAD, 0xBE, 0])
        XCTAssertEqual(c64.diskDrive.readSectorErrorCode(track: 1, sector: 2), 0x01)
        XCTAssertTrue(c64.emulationStatus.diskHasUnsavedChanges)
    }

    func testOpenCommandChannelBlockWriteClearsExtendedD64SectorError() throws {
        let c64 = C64()
        var image = [UInt8](makeMinimalD64())
        image.append(contentsOf: [UInt8](repeating: 0, count: 200_704 - image.count))
        image.append(contentsOf: [UInt8](repeating: 0x01, count: 784))
        let geometry = try XCTUnwrap(DiskDrive.d64Geometry(forByteCount: image.count))
        let errorOffset = try XCTUnwrap(geometry.errorInfoOffset)
        image[errorOffset + 783] = 23
        XCTAssertTrue(c64.mountDisk(Data(image), fileName: "extended-write.d64"))

        prepareKernalOpenTrap(c64, filename: "#", logicalFile: 2, secondary: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKOUTTrap(c64, channel: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        for byte in [UInt8(0x4C), 0x00, 0xC0] {
            prepareKernalCHROUTTrap(c64, byte: byte)
            XCTAssertTrue(c64.kernalTraps.checkTrap())
        }

        prepareKernalOpenTrap(c64, filename: "U2:2,0,41,15", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        let sector = try XCTUnwrap(c64.diskDrive.readSector(track: 41, sector: 15))
        XCTAssertEqual(Array(sector.prefix(3)), [0x4C, 0x00, 0xC0])
        XCTAssertEqual(c64.diskDrive.readSectorErrorCode(track: 41, sector: 15), 0x01)
        XCTAssertTrue(c64.emulationStatus.diskHasUnsavedChanges)

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "00, OK,00,00\r")
    }

    func testBufferedCommandChannelBinaryBlockAllocateAndFreeUpdateBAM() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))
        let initialFreeBlocks = c64.diskDrive.freeBlocks()

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKOUTTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        writeKernalBytes(c64, [UInt8(ascii: "B"), UInt8(ascii: "-"), UInt8(ascii: "A"), UInt8(ascii: ":"), 0, 1, 2])
        prepareKernalCloseTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.diskDrive.freeBlocks(), initialFreeBlocks - 1)

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKOUTTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        writeKernalBytes(c64, [UInt8(ascii: "B"), UInt8(ascii: "-"), UInt8(ascii: "F"), UInt8(ascii: ":"), 0, 1, 2])
        prepareKernalCloseTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.diskDrive.freeBlocks(), initialFreeBlocks)
    }

    func testBufferedCommandChannelAcceptsRawU0DeviceAddressChange() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKOUTTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        for byte in [UInt8(ascii: "U"), UInt8(ascii: "0"), UInt8(ascii: ">"), 10] {
            prepareKernalCHROUTTrap(c64, byte: byte)
            XCTAssertTrue(c64.kernalTraps.checkTrap())
        }

        prepareKernalCloseTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(readKernalChannelLine(c64), "00, OK,00,00\r")
    }

    func testKernalOpenWriteChannelCreatesSEQFileOnClose() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))

        prepareKernalOpenTrap(c64, filename: "TEXT,S,W", logicalFile: 2, secondary: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCHKOUTTrap(c64, channel: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        for byte in Array("HELLO CHANNEL\r".utf8) {
            prepareKernalCHROUTTrap(c64, byte: byte)
            XCTAssertTrue(c64.kernalTraps.checkTrap())
        }
        prepareKernalCloseTrap(c64, channel: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        let entry = try XCTUnwrap(c64.diskDrive.findFile("TEXT"))
        XCTAssertEqual(entry.typeName, "SEQ")
        XCTAssertEqual(c64.diskDrive.readFileData(entry), Array("HELLO CHANNEL\r".utf8))
        XCTAssertTrue(c64.emulationStatus.diskHasUnsavedChanges)
    }

    func testKernalOpenCloseWriteChannelCreatesEmptySEQFile() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))

        prepareKernalOpenTrap(c64, filename: "EMPTY,S,W", logicalFile: 2, secondary: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        prepareKernalCloseTrap(c64, channel: 2)
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        let entry = try XCTUnwrap(c64.diskDrive.findFile("EMPTY"))
        XCTAssertEqual(entry.typeName, "SEQ")
        XCTAssertEqual(entry.fileSize, 0)
        XCTAssertEqual(entry.firstTrack, 0)
        XCTAssertEqual(entry.firstSector, 0)
        XCTAssertEqual(c64.diskDrive.readFileData(entry), [])
    }

    func testCompatTrueDriveAllowsKernalChannelTrapsThroughC64Gate() {
        let c64 = C64()
        c64.trueDriveEmulationMode = .compat1541
        XCTAssertTrue(c64.mountDisk(makeBlankWritableD64()))

        prepareKernalOpenTrap(c64, filename: "", logicalFile: 15, secondary: 15)
        XCTAssertTrue(c64.shouldUseKernalTrapAtCurrentInstruction())
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalCHKINTrap(c64, channel: 15)
        XCTAssertTrue(c64.shouldUseKernalTrapAtCurrentInstruction())
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        prepareKernalCHRINTrap(c64)
        XCTAssertTrue(c64.shouldUseKernalTrapAtCurrentInstruction())
        XCTAssertTrue(c64.kernalTraps.checkTrap())
        XCTAssertEqual(c64.cpu.a, UInt8(ascii: "0"))

        prepareKernalCloseTrap(c64, channel: 15)
        XCTAssertTrue(c64.shouldUseKernalTrapAtCurrentInstruction())
        XCTAssertTrue(c64.kernalTraps.checkTrap())
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

    private func prepareKernalCHKOUTTrap(_ c64: C64, channel: UInt8) {
        c64.cpu.x = channel
        prepareTrapReturn(c64, pc: KernalTraps.chkoutRoutine)
    }

    private func prepareKernalCloseTrap(_ c64: C64, channel: UInt8) {
        c64.cpu.a = channel
        prepareTrapReturn(c64, pc: KernalTraps.closeRoutine)
    }

    private func prepareKernalCHRINTrap(_ c64: C64) {
        prepareTrapReturn(c64, pc: KernalTraps.basinRoutine)
    }

    private func prepareKernalCHROUTTrap(_ c64: C64, byte: UInt8) {
        c64.cpu.a = byte
        prepareTrapReturn(c64, pc: KernalTraps.bsoutRoutine)
    }

    private func writeKernalBytes(_ c64: C64, _ bytes: [UInt8]) {
        for byte in bytes {
            prepareKernalCHROUTTrap(c64, byte: byte)
            XCTAssertTrue(c64.kernalTraps.checkTrap())
        }
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

    private func makeStandardCBMTAP(blocks: [[UInt8]]) -> Data {
        let payload = blocks.flatMap(encodeStandardCBMTAPBlock)
        return makeTAP(payload: payload)
    }

    private func makeTAP(payload: [UInt8]) -> Data {
        var bytes = [UInt8](repeating: 0, count: 20)
        writeASCII("C64-TAPE-RAW", into: &bytes, at: 0)
        bytes[0x0C] = 0
        writeUInt32LE(UInt32(payload.count), into: &bytes, at: 0x10)
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    private func encodeStandardCBMTAPBlock(_ bytes: [UInt8]) -> [UInt8] {
        var payload: [UInt8] = []
        for byte in bytes {
            appendStandardPulse(.long, to: &payload)
            appendStandardPulse(.medium, to: &payload)

            var oneBits = 0
            for bit in 0..<8 {
                let isOne = byte & UInt8(1 << bit) != 0
                if isOne { oneBits += 1 }
                appendStandardBit(isOne, to: &payload)
            }
            appendStandardBit(oneBits % 2 == 0, to: &payload)
        }

        appendStandardPulse(.long, to: &payload)
        appendStandardPulse(.short, to: &payload)
        return payload
    }

    private enum StandardPulse {
        case short
        case medium
        case long
    }

    private func appendStandardBit(_ bit: Bool, to payload: inout [UInt8]) {
        if bit {
            appendStandardPulse(.medium, to: &payload)
            appendStandardPulse(.short, to: &payload)
        } else {
            appendStandardPulse(.short, to: &payload)
            appendStandardPulse(.medium, to: &payload)
        }
    }

    private func appendStandardPulse(_ pulse: StandardPulse, to payload: inout [UInt8]) {
        switch pulse {
        case .short:
            payload.append(0x2C)
        case .medium:
            payload.append(0x40)
        case .long:
            payload.append(0x54)
        }
    }

    private func damageStandardCBMParity(byteIndex: Int, in payload: inout [UInt8]) {
        let parityOffset = byteIndex * 20 + 18
        guard parityOffset + 1 < payload.count else { return }
        payload[parityOffset] = 0x2C
        payload[parityOffset + 1] = 0x40
    }

    private func writeASCII(_ string: String, into bytes: inout [UInt8], at offset: Int, maxLength: Int? = nil) {
        for (index, byte) in string.utf8.prefix(maxLength ?? string.utf8.count).enumerated() {
            bytes[offset + index] = byte
        }
    }

    private func writeUInt32LE(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private func makeMinimalD64(
        firstFileSectorError: UInt8? = nil,
        directorySectorError: UInt8? = nil
    ) -> Data {
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
        image[fileOffset + 1] = 5
        image[fileOffset + 2] = 0x01
        image[fileOffset + 3] = 0x08
        image[fileOffset + 4] = 0xA9
        image[fileOffset + 5] = 0x2A

        if firstFileSectorError != nil || directorySectorError != nil {
            var imageWithErrors = image
            let errorTable = d64ErrorTable(
                firstFileSectorError: firstFileSectorError,
                directorySectorError: directorySectorError
            )
            imageWithErrors.append(contentsOf: errorTable)
            return Data(imageWithErrors)
        }

        return Data(image)
    }

    private func makeSameNamePRGAndSEQD64() -> Data {
        var image = [UInt8](makeBlankWritableD64())
        let dirOffset = DiskDrive.trackOffset[18] + 256

        image[dirOffset + 2] = 0x82
        image[dirOffset + 3] = 1
        image[dirOffset + 4] = 0
        let name = Array("HELLO".utf8)
        for index in 0..<16 {
            image[dirOffset + 5 + index] = index < name.count ? name[index] : 0xA0
        }
        image[dirOffset + 30] = 1

        image[dirOffset + 32 + 2] = 0x81
        image[dirOffset + 32 + 3] = 1
        image[dirOffset + 32 + 4] = 1
        for index in 0..<16 {
            image[dirOffset + 32 + 5 + index] = index < name.count ? name[index] : 0xA0
        }
        image[dirOffset + 32 + 30] = 1

        return Data(image)
    }

    private func d64ErrorTable(
        firstFileSectorError: UInt8?,
        directorySectorError: UInt8?
    ) -> [UInt8] {
        var table = [UInt8](repeating: 0x01, count: 683)
        if let firstFileSectorError {
            table[0] = firstFileSectorError
        }
        if let directorySectorError {
            table[358] = directorySectorError
        }
        return table
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
