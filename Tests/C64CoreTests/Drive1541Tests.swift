import XCTest
import Emu6502
@testable import C64Core

final class Drive1541Tests: XCTestCase {
    private static let slowTrueDriveEnv = "SWIFT64_SLOW_TRUE_DRIVE_TESTS"

    func testDriveRAMMirrorsThroughAddressRangeBeforeVIAWindows() {
        let memory = DriveMemoryMap()

        memory.write(0x0012, value: 0xA5)
        XCTAssertEqual(memory.read(0x0812), 0xA5)
        XCTAssertEqual(memory.read(0x1012), 0xA5)

        memory.write(0x17FF, value: 0x5A)

        XCTAssertEqual(memory.read(0x07FF), 0x5A)
        XCTAssertEqual(memory.read(0x0FFF), 0x5A)
    }

    func testDriveRAMMirrorDoesNotCoverVIAWindows() {
        let memory = DriveMemoryMap()
        let via1 = VIA6522()
        let via2 = VIA6522()
        memory.via1 = via1
        memory.via2 = via2

        memory.write(0x1802, value: 0xFF)
        memory.write(0x1800, value: 0x12)
        memory.write(0x1C02, value: 0xFF)
        memory.write(0x1C00, value: 0x34)

        XCTAssertEqual(memory.read(0x1800), 0x12)
        XCTAssertEqual(memory.read(0x1C00), 0x34)
        XCTAssertNotEqual(memory.ram[0x0000], 0x12)
        XCTAssertNotEqual(memory.ram[0x0400], 0x34)
    }

    func testFireByteReadyPulsesSOAndClearsOnPortARead() {
        let drive = Drive1541()

        drive.fireByteReady()

        XCTAssertTrue(drive.cpu.getFlag(Flags.overflow))
        XCTAssertFalse(drive.via2.ca1)
        XCTAssertTrue(drive.statusSnapshot.byteReady)

        _ = drive.via2.readRegister(0x01)

        XCTAssertTrue(drive.via2.ca1)
        XCTAssertFalse(drive.statusSnapshot.byteReady)
    }

    func testGCRHeadDetectsSyncFromInsertedTrack() {
        let drive = Drive1541()
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[36] = DiskImage.Track(
            halfTrack: 36,
            bytes: [0xFF, 0xFF, 0x00, 0x55, 0xAA],
            speedZone: 2,
            isNativeLowLevel: true
        )
        XCTAssertTrue(drive.insertDiskImage(DiskImage(format: .g64, tracks: tracks, maxTrackSize: 5)))
        drive.halfTrack = 36
        drive.motorOn = true

        for _ in 0..<80 {
            drive.tickGCRHead()
            if drive.statusSnapshot.syncDetected { break }
        }

        XCTAssertTrue(drive.statusSnapshot.syncDetected)
        XCTAssertGreaterThan(drive.statusSnapshot.headBitPosition, 0)
        XCTAssertTrue(drive.statusSnapshot.hasNativeLowLevelImage)
    }

    func testGCRHeadUsesPerByteSpeedZoneMap() {
        let fastDrive = makeDriveWithSpeedMappedTrack(zone: 3)
        let slowDrive = makeDriveWithSpeedMappedTrack(zone: 0)
        let fixedDrive = makeDriveWithTrack(bytes: [UInt8](repeating: 0x00, count: 256))

        for _ in 0..<2_000 {
            fastDrive.tickGCRHead()
            slowDrive.tickGCRHead()
            fixedDrive.tickGCRHead()
        }

        XCTAssertGreaterThan(
            fastDrive.headBitPosition,
            slowDrive.headBitPosition,
            "A zone-3 speed map should advance the head farther than zone-0 over the same drive cycles"
        )
        XCTAssertGreaterThan(fastDrive.statusSnapshot.variableSpeedZoneSampleCount, 0)
        XCTAssertGreaterThan(slowDrive.statusSnapshot.variableSpeedZoneSampleCount, 0)
        XCTAssertEqual(fixedDrive.statusSnapshot.variableSpeedZoneSampleCount, 0)
        XCTAssertEqual(fastDrive.statusSnapshot.variableSpeedZoneMask, 1 << 3)
        XCTAssertEqual(slowDrive.statusSnapshot.variableSpeedZoneMask, 1 << 0)
        XCTAssertEqual(fixedDrive.statusSnapshot.variableSpeedZoneMask, 0)
    }

    func testGCRHeadReadsWeakBitRangesAsUnstableBits() {
        let fixedDrive = makeDriveWithTrack(
            bytes: [UInt8](repeating: 0x00, count: 16),
            weakBitRanges: []
        )
        let weakDrive = makeDriveWithTrack(
            bytes: [UInt8](repeating: 0x00, count: 16),
            weakBitRanges: [DiskImage.Track.WeakBitRange(startBit: 0, endBit: 127)]
        )

        let fixedBytes = readPresentedGCRBytes(from: fixedDrive, count: 4)
        let weakBytes = readPresentedGCRBytes(from: weakDrive, count: 4)

        XCTAssertEqual(fixedBytes, [0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(fixedDrive.statusSnapshot.weakBitReadCount, 0)
        XCTAssertTrue(weakBytes.contains { $0 != 0x00 })
        XCTAssertGreaterThan(weakDrive.statusSnapshot.weakBitReadCount, 0)
    }

    func testGCRHeadUsesWeakBitAnnotationsAddedAfterInsert() {
        let drive = makeDriveWithTrack(
            bytes: [UInt8](repeating: 0x00, count: 16),
            weakBitRanges: []
        )

        XCTAssertTrue(drive.disk.setWeakBitRanges(
            [DiskImage.Track.WeakBitRange(startBit: 0, endBit: 127)],
            forHalfTrack: 36
        ))

        let bytes = readPresentedGCRBytes(from: drive, count: 4)
        XCTAssertTrue(bytes.contains { $0 != 0x00 })
        XCTAssertGreaterThan(drive.statusSnapshot.weakBitReadCount, 0)
    }

    func testExportedG64PreservesWeakBitRangesInSwift64Extension() throws {
        let drive = makeDriveWithTrack(
            bytes: [UInt8](repeating: 0x00, count: 16),
            weakBitRanges: [
                DiskImage.Track.WeakBitRange(startBit: 0, endBit: 31),
                DiskImage.Track.WeakBitRange(startBit: 64, endBit: 95),
            ]
        )

        let exported = try XCTUnwrap(drive.disk.exportedG64Image)
        let reloaded = GCRDisk()
        XCTAssertTrue(reloaded.loadG64(exported))

        XCTAssertEqual(reloaded.trackInfo(halfTrack: 36)?.weakBitRanges, [
            DiskImage.Track.WeakBitRange(startBit: 0, endBit: 31),
            DiskImage.Track.WeakBitRange(startBit: 64, endBit: 95),
        ])
        XCTAssertTrue(reloaded.image?.capabilities.preservesWeakBitRanges == true)
        XCTAssertEqual(reloaded.image?.capabilities.weakBitRangeCount, 2)
        XCTAssertEqual(reloaded.image?.capabilities.weakBitTotalBitCount, 64)
    }

    func testEmptyOddHalfTrackReadsAdjacentFullTrackFlux() {
        let drive = makeDriveWithTracks([
            36: [0x00, 0xFF, 0x55, 0xAA, 0x33, 0xCC],
        ])
        drive.halfTrack = 37

        let bytes = readPresentedGCRBytes(from: drive, count: 3)

        XCTAssertFalse(bytes.isEmpty)
        XCTAssertTrue(bytes.contains { $0 != 0x00 })
        XCTAssertEqual(drive.statusSnapshot.halfTrack, 37)
        XCTAssertEqual(drive.statusSnapshot.readHalfTrack, 36)
        XCTAssertEqual(drive.statusSnapshot.readTrack, 19)
        XCTAssertTrue(drive.statusSnapshot.usingHalfTrackFallback)
    }

    func testExplicitHalfTrackDataOverridesAdjacentFallback() {
        let drive = makeDriveWithTracks([
            36: [UInt8](repeating: 0x00, count: 16),
            37: [0xFF, 0xFF, 0x00, 0x55, 0xAA],
        ])
        drive.halfTrack = 37

        for _ in 0..<80 {
            drive.tickGCRHead()
            if drive.statusSnapshot.syncDetected { break }
        }

        XCTAssertTrue(drive.statusSnapshot.syncDetected)
        XCTAssertEqual(drive.statusSnapshot.readHalfTrack, 37)
        XCTAssertEqual(drive.statusSnapshot.readTrack, 19)
        XCTAssertFalse(drive.statusSnapshot.usingHalfTrackFallback)
    }

    func testBlankTrackClearsStaleGCRReadPresentation() {
        let drive = makeDriveWithTracks([
            36: [UInt8](repeating: 0x00, count: 16),
        ])
        drive.halfTrack = 36

        for _ in 0..<1_000 {
            drive.tickGCRHead()
            if drive.statusSnapshot.byteReady { break }
        }

        XCTAssertTrue(drive.statusSnapshot.byteReady)
        XCTAssertFalse(drive.via2.ca1)

        drive.halfTrack = 38
        drive.tickGCRHead()

        XCTAssertFalse(drive.statusSnapshot.byteReady)
        XCTAssertFalse(drive.statusSnapshot.syncDetected)
        XCTAssertEqual(drive.shiftRegister, 0)
        XCTAssertEqual(drive.bitCounter, 0)
        XCTAssertEqual(drive.soDelay, 0)
        XCTAssertEqual(drive.via2.portAInput, 0x00)
        XCTAssertTrue(drive.via2.ca1)
        XCTAssertNil(drive.statusSnapshot.readHalfTrack)
    }

    func testBlankTrackCancelsPendingByteReadyDelay() {
        let drive = makeDriveWithTracks([
            36: [UInt8](repeating: 0x00, count: 16),
        ])
        drive.halfTrack = 38
        drive.soDelay = 5
        drive.via2.ca1 = true
        let baseline = drive.statusSnapshot.byteReadyCount

        drive.tickGCRHead()

        XCTAssertEqual(drive.statusSnapshot.byteReadyCount, baseline)
        XCTAssertFalse(drive.statusSnapshot.byteReady)
        XCTAssertEqual(drive.soDelay, 0)
        XCTAssertTrue(drive.via2.ca1)
    }

    func testInsertDiskRefreshesVIA2WriteProtectAndSyncInputs() {
        let drive = Drive1541()
        drive.via2.portBInput = 0x00

        XCTAssertTrue(drive.insertDiskImage(makeDiskImageWithTrack(bytes: [0x55, 0xAA])))

        let portB = drive.via2.readRegister(0x00)
        XCTAssertEqual(portB & 0x10, 0x00, "Write-protected disks should hold VIA2 PB4 low")
        XCTAssertEqual(portB & 0x80, 0x80, "No active sync should leave VIA2 PB7 high")
        XCTAssertTrue(drive.statusSnapshot.writeProtected)
    }

    func testInsertDiskMarksMediaChangedWithGenerationCounter() {
        let drive = Drive1541()

        XCTAssertFalse(drive.statusSnapshot.mediaChanged)
        XCTAssertEqual(drive.statusSnapshot.mediaChangeCount, 0)

        XCTAssertTrue(drive.insertDiskImage(makeDiskImageWithTrack(bytes: [0x55, 0xAA])))

        XCTAssertTrue(drive.statusSnapshot.mediaChanged)
        XCTAssertEqual(drive.statusSnapshot.mediaChangeCount, 1)
    }

    func testMediaChangeCanBeAcknowledgedAndEjectAdvancesCounter() {
        let drive = Drive1541()
        XCTAssertTrue(drive.insertDiskImage(makeDiskImageWithTrack(bytes: [0x55, 0xAA])))

        drive.acknowledgeMediaChange()
        XCTAssertFalse(drive.statusSnapshot.mediaChanged)
        XCTAssertEqual(drive.statusSnapshot.mediaChangeCount, 1)

        drive.ejectDisk()

        XCTAssertFalse(drive.statusSnapshot.hasDisk)
        XCTAssertTrue(drive.statusSnapshot.mediaChanged)
        XCTAssertEqual(drive.statusSnapshot.mediaChangeCount, 2)
    }

    func testFailedDiskInsertDoesNotChangeMediaGeneration() {
        let drive = Drive1541()

        XCTAssertFalse(drive.insertDisk(Data([0x00, 0x01, 0x02]), isG64: true))

        XCTAssertFalse(drive.statusSnapshot.mediaChanged)
        XCTAssertEqual(drive.statusSnapshot.mediaChangeCount, 0)
    }

    func testInsertDiskClearsStaleGCRReadPipelineState() {
        let drive = Drive1541()
        drive.headBitPosition = 1234
        drive.syncDetected = true
        drive.shiftRegister = 0x03FF
        drive.bitCounter = 7
        drive.byteReadyEdge = true
        drive.byteReadyLevel = true
        drive.soDelay = 9
        drive.via2.ca1 = false

        XCTAssertTrue(drive.insertDiskImage(makeDiskImageWithTrack(bytes: [0x55, 0xAA])))

        XCTAssertEqual(drive.statusSnapshot.headBitPosition, 0)
        XCTAssertFalse(drive.statusSnapshot.syncDetected)
        XCTAssertFalse(drive.statusSnapshot.byteReady)
        XCTAssertEqual(drive.shiftRegister, 0)
        XCTAssertEqual(drive.bitCounter, 0)
        XCTAssertEqual(drive.soDelay, 0)
        XCTAssertTrue(drive.via2.ca1)
        XCTAssertEqual(drive.via2.readRegister(0x00) & 0x80, 0x80)
    }

    func testEjectDiskClearsStaleGCRReadPipelineState() {
        let drive = Drive1541()
        XCTAssertTrue(drive.insertDiskImage(makeDiskImageWithTrack(bytes: [0x55, 0xAA])))
        drive.headBitPosition = 1234
        drive.syncDetected = true
        drive.shiftRegister = 0x03FF
        drive.bitCounter = 7
        drive.byteReadyEdge = true
        drive.byteReadyLevel = true
        drive.soDelay = 9
        drive.via2.ca1 = false

        drive.ejectDisk()

        XCTAssertFalse(drive.statusSnapshot.hasDisk)
        XCTAssertEqual(drive.statusSnapshot.headBitPosition, 0)
        XCTAssertFalse(drive.statusSnapshot.syncDetected)
        XCTAssertFalse(drive.statusSnapshot.byteReady)
        XCTAssertEqual(drive.shiftRegister, 0)
        XCTAssertEqual(drive.bitCounter, 0)
        XCTAssertEqual(drive.soDelay, 0)
        XCTAssertTrue(drive.via2.ca1)
        XCTAssertEqual(drive.via2.readRegister(0x00) & 0x80, 0x80)
    }

    func testWriteProtectChangesAreVisibleThroughVIA2PB4() {
        let drive = Drive1541()
        XCTAssertTrue(drive.insertDiskImage(makeDiskImageWithTrack(bytes: [0x55, 0xAA])))

        drive.setWriteProtected(false)
        XCTAssertEqual(drive.via2.readRegister(0x00) & 0x10, 0x10)
        XCTAssertFalse(drive.statusSnapshot.writeProtected)

        drive.setWriteProtected(true)
        XCTAssertEqual(drive.via2.readRegister(0x00) & 0x10, 0x00)
        XCTAssertTrue(drive.statusSnapshot.writeProtected)
    }

    func testVIA2PortAWriteUpdatesWritableGCRTrackAtHeadPosition() {
        let drive = Drive1541()
        XCTAssertTrue(drive.insertDiskImage(makeDiskImageWithTrack(bytes: [0x00, 0x11, 0x22, 0x33])))
        drive.setWriteProtected(false)
        drive.via2.writeRegister(0x03, value: 0xFF)
        drive.halfTrack = 36
        drive.headBitPosition = 16
        drive.motorOn = true

        drive.via2.writeRegister(0x01, value: 0xA5)
        runWriteHead(drive, completeBytes: 1)

        XCTAssertEqual(drive.disk.trackInfo(halfTrack: 36)?.bytes, [0x00, 0x11, 0xA5, 0x33])
        XCTAssertTrue(drive.disk.hasUnsavedLowLevelWrites)
        XCTAssertEqual(drive.statusSnapshot.gcrWriteByteCount, 1)
        XCTAssertTrue(drive.statusSnapshot.gcrWriteModeActive)
    }

    func testVIA2PortAWriteSplicesUnalignedGCRByteAtHeadPosition() {
        let drive = Drive1541()
        XCTAssertTrue(drive.insertDiskImage(makeDiskImageWithTrack(bytes: [0x00, 0x00, 0x00, 0x00])))
        drive.setWriteProtected(false)
        drive.via2.writeRegister(0x03, value: 0xFF)
        drive.halfTrack = 36
        drive.headBitPosition = 5
        drive.motorOn = true

        drive.via2.writeRegister(0x01, value: 0xA5)
        runWriteHead(drive, completeBytes: 1)

        XCTAssertEqual(drive.disk.trackInfo(halfTrack: 36)?.bytes, [0x05, 0x28, 0x00, 0x00])
        XCTAssertTrue(drive.disk.hasUnsavedLowLevelWrites)
        XCTAssertEqual(drive.statusSnapshot.gcrWriteByteCount, 1)
    }

    func testVIA2PortAWriteCreatesMissingNativeG64HalfTrack() {
        let drive = Drive1541()
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[34] = DiskImage.Track(
            halfTrack: 34,
            bytes: [0xFF, 0xFF],
            speedZone: 2,
            isNativeLowLevel: true
        )
        XCTAssertTrue(drive.insertDiskImage(DiskImage(format: .g64, tracks: tracks, maxTrackSize: 2)))
        drive.setWriteProtected(false)
        drive.via2.writeRegister(0x03, value: 0xFF)
        drive.via2.portB = 0x60
        drive.halfTrack = 35
        drive.headBitPosition = 0
        drive.motorOn = true

        drive.via2.writeRegister(0x01, value: 0xA5)
        runWriteHead(drive, completeBytes: 1)

        let created = drive.disk.trackInfo(halfTrack: 35)
        XCTAssertEqual(created?.bytes.count, GCRDisk.trackLengths[3])
        XCTAssertEqual(created?.bytes.first, 0xA5)
        XCTAssertEqual(created?.speedZone, 3)
        XCTAssertEqual(created?.isNativeLowLevel, true)
        XCTAssertTrue(drive.disk.hasUnsavedLowLevelWrites)
        XCTAssertEqual(drive.statusSnapshot.gcrWriteByteCount, 1)
        XCTAssertEqual(drive.statusSnapshot.readHalfTrack, 35)
        XCTAssertFalse(drive.statusSnapshot.usingHalfTrackFallback)

        let exported = try? XCTUnwrap(drive.disk.exportedG64Image)
        let reloaded = GCRDisk()
        XCTAssertTrue(reloaded.loadG64(exported ?? Data()))
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 35)?.bytes.first, 0xA5)
        XCTAssertEqual(reloaded.trackInfo(halfTrack: 35)?.speedZone, 3)
    }

    func testGCRWriteGateAddsEntryAndExitSpliceWeakRanges() {
        let drive = Drive1541()
        XCTAssertTrue(drive.insertDiskImage(makeDiskImageWithTrack(bytes: [UInt8](repeating: 0x00, count: 8))))
        drive.setWriteProtected(false)
        drive.halfTrack = 36
        drive.headBitPosition = 16
        drive.motorOn = true
        drive.via2.writeRegister(0x03, value: 0xFF)

        drive.via2.writeRegister(0x01, value: 0xA5)
        runWriteHead(drive, completeBytes: 1)

        XCTAssertEqual(drive.statusSnapshot.gcrWriteSpliceCount, 1)
        XCTAssertEqual(drive.disk.trackInfo(halfTrack: 36)?.weakBitRanges, [
            DiskImage.Track.WeakBitRange(startBit: 0, endBit: 15),
        ])

        drive.via2.writeRegister(0x03, value: 0x00)
        drive.tickGCRHead()

        XCTAssertEqual(drive.statusSnapshot.gcrWriteSpliceCount, 2)
        XCTAssertEqual(drive.disk.trackInfo(halfTrack: 36)?.weakBitRanges, [
            DiskImage.Track.WeakBitRange(startBit: 0, endBit: 15),
            DiskImage.Track.WeakBitRange(startBit: 24, endBit: 39),
        ])
    }

    func testGCRWriteGateEntrySpliceWrapsAroundTrackStart() {
        let drive = Drive1541()
        XCTAssertTrue(drive.insertDiskImage(makeDiskImageWithTrack(bytes: [UInt8](repeating: 0x00, count: 4))))
        drive.setWriteProtected(false)
        drive.halfTrack = 36
        drive.headBitPosition = 0
        drive.motorOn = true
        drive.via2.writeRegister(0x03, value: 0xFF)

        drive.tickGCRHead()

        XCTAssertEqual(drive.statusSnapshot.gcrWriteSpliceCount, 1)
        XCTAssertEqual(drive.disk.trackInfo(halfTrack: 36)?.weakBitRanges, [
            DiskImage.Track.WeakBitRange(startBit: 16, endBit: 31),
        ])
    }

    func testGCRWriteGateWithoutFreshPortAByteErasesBits() {
        let drive = Drive1541()
        XCTAssertTrue(drive.insertDiskImage(makeDiskImageWithTrack(bytes: [0xFF, 0xFF, 0xFF, 0xFF])))
        drive.setWriteProtected(false)
        drive.halfTrack = 36
        drive.headBitPosition = 0
        drive.motorOn = true
        drive.via2.writeRegister(0x03, value: 0xFF)

        runWriteHeadErase(drive, erasedBits: 8)

        XCTAssertEqual(drive.disk.trackInfo(halfTrack: 36)?.bytes.first, 0x00)
        XCTAssertEqual(drive.statusSnapshot.gcrWriteEraseBitCount, 8)
        XCTAssertEqual(drive.statusSnapshot.gcrWriteByteCount, 0)
        XCTAssertTrue(drive.disk.hasUnsavedLowLevelWrites)
    }

    func testExportedG64PreservesWriteSpliceWeakRanges() throws {
        let drive = Drive1541()
        XCTAssertTrue(drive.insertDiskImage(makeDiskImageWithTrack(bytes: [UInt8](repeating: 0x00, count: 8))))
        drive.setWriteProtected(false)
        drive.halfTrack = 36
        drive.headBitPosition = 16
        drive.motorOn = true
        drive.via2.writeRegister(0x03, value: 0xFF)

        drive.via2.writeRegister(0x01, value: 0xA5)
        runWriteHead(drive, completeBytes: 1)
        drive.via2.writeRegister(0x03, value: 0x00)
        drive.tickGCRHead()

        let exported = try XCTUnwrap(drive.disk.exportedG64Image)
        let reloaded = GCRDisk()
        XCTAssertTrue(reloaded.loadG64(exported))

        XCTAssertEqual(reloaded.trackInfo(halfTrack: 36)?.weakBitRanges, [
            DiskImage.Track.WeakBitRange(startBit: 0, endBit: 15),
            DiskImage.Track.WeakBitRange(startBit: 24, endBit: 39),
        ])
        XCTAssertTrue(reloaded.image?.capabilities.preservesWeakBitRanges == true)
    }

    func testVIA2PortAWriteHonorsWriteProtectAndMotorGate() {
        let drive = Drive1541()
        XCTAssertTrue(drive.insertDiskImage(makeDiskImageWithTrack(bytes: [0x00, 0x11, 0x22, 0x33])))
        drive.via2.writeRegister(0x03, value: 0xFF)
        drive.halfTrack = 36
        drive.headBitPosition = 8

        drive.via2.writeRegister(0x01, value: 0xA5)
        runWriteHeadCycles(drive)
        XCTAssertEqual(drive.disk.trackInfo(halfTrack: 36)?.bytes, [0x00, 0x11, 0x22, 0x33])

        drive.motorOn = true
        drive.via2.writeRegister(0x01, value: 0x5A)
        runWriteHeadCycles(drive)

        XCTAssertEqual(drive.disk.trackInfo(halfTrack: 36)?.bytes, [0x00, 0x11, 0x22, 0x33])
        XCTAssertFalse(drive.disk.hasUnsavedLowLevelWrites)
        XCTAssertEqual(drive.statusSnapshot.gcrWriteByteCount, 0)
        XCTAssertTrue(drive.statusSnapshot.gcrWriteModeActive)
    }

    func testMotorSpinsDownAfterVIACommandTurnsOff() {
        let drive = Drive1541()

        drive.via2.portB = 0x04
        drive.updateMotorAndStepper()

        XCTAssertTrue(drive.statusSnapshot.motorOn)
        XCTAssertTrue(drive.motorCommandOn)
        XCTAssertEqual(drive.motorSpinDownCyclesRemaining, Drive1541.motorSpinDownCycles)

        drive.via2.portB = 0x00
        drive.updateMotorAndStepper()

        XCTAssertTrue(drive.statusSnapshot.motorOn)
        XCTAssertFalse(drive.motorCommandOn)
        XCTAssertEqual(drive.motorSpinDownCyclesRemaining, Drive1541.motorSpinDownCycles - 1)

        for _ in 0..<(Drive1541.motorSpinDownCycles - 1) {
            drive.updateMotorAndStepper()
        }

        XCTAssertFalse(drive.statusSnapshot.motorOn)
        XCTAssertEqual(drive.motorSpinDownCyclesRemaining, 0)
    }

    func testMotorCommandRefreshesSpinDownWindowWhileHeldOn() {
        let drive = Drive1541()

        drive.via2.portB = 0x04
        drive.updateMotorAndStepper()
        drive.motorSpinDownCyclesRemaining = 3
        drive.updateMotorAndStepper()

        XCTAssertTrue(drive.statusSnapshot.motorOn)
        XCTAssertEqual(drive.motorSpinDownCyclesRemaining, Drive1541.motorSpinDownCycles)
    }

    func testResetClearsVIAAndGCRHardwareStateButKeepsDiskInserted() {
        let drive = makeDriveWithSpeedMappedTrack(zone: 3)
        drive.via1.writeRegister(0x02, value: 0xFF)
        drive.via1.writeRegister(0x00, value: 0x1A)
        drive.via2.writeRegister(0x0E, value: 0xC2)
        drive.fireByteReady()
        _ = drive.via2.readRegister(0x01)
        drive.fireByteReady()
        drive.syncDetected = true
        drive.headBitPosition = 1234
        drive.halfTrack = 10
        drive.motorOn = true
        drive.motorCommandOn = true
        drive.motorSpinDownCyclesRemaining = 123
        drive.ledOn = true

        drive.reset()

        XCTAssertTrue(drive.statusSnapshot.hasDisk)
        XCTAssertEqual(drive.via1.ddrb, 0)
        XCTAssertEqual(drive.via1.portB, 0)
        XCTAssertEqual(drive.via2.ier, 0)
        XCTAssertEqual(drive.via2.ifr, 0)
        XCTAssertFalse(drive.statusSnapshot.byteReady)
        XCTAssertEqual(drive.statusSnapshot.byteReadyCount, 0)
        XCTAssertEqual(drive.statusSnapshot.via2PortAReadCount, 0)
        XCTAssertEqual(drive.statusSnapshot.syncDetectionCount, 0)
        XCTAssertFalse(drive.statusSnapshot.syncDetected)
        XCTAssertEqual(drive.statusSnapshot.headBitPosition, 0)
        XCTAssertEqual(drive.statusSnapshot.halfTrack, 34)
        XCTAssertFalse(drive.statusSnapshot.motorOn)
        XCTAssertFalse(drive.motorCommandOn)
        XCTAssertEqual(drive.motorSpinDownCyclesRemaining, 0)
        XCTAssertFalse(drive.statusSnapshot.ledOn)
    }

    func testTrueDriveBootsBundledDriveROM() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let romURL = root.appendingPathComponent("Sources/C64App/ROMS/1541C.251968-02.bin")
        let rom = try Data(contentsOf: romURL)
        let drive = Drive1541()

        drive.loadROM(rom)
        drive.powerOn()

        XCTAssertEqual(drive.cpu.pc, 0xEAA0)
        XCTAssertTrue(drive.statusSnapshot.enabled)
        XCTAssertEqual(drive.statusSnapshot.model, .model1541C)
    }

    func testDriveROMConfiguresATNInterruptAndSeesBusEdge() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let romURL = root.appendingPathComponent("Sources/C64App/ROMS/1541C.251968-02.bin")
        let bus = IECBus()
        let drive = Drive1541()
        drive.iecBus = bus
        drive.loadROM(try Data(contentsOf: romURL))
        drive.powerOn()

        var configured = false
        for _ in 0..<5_000_000 {
            drive.tick()
            if drive.via1.ier & VIA6522.IRQ.ca1 != 0 {
                configured = true
                break
            }
        }

        XCTAssertTrue(configured, "1541 ROM should enable VIA1 CA1 for ATN handling")

        _ = drive.via1.readRegister(0x01)
        bus.updateFromC64(0x08, ddra: 0x08) // C64 pulls ATN low

        var sawATNInterrupt = false
        for _ in 0..<256 {
            drive.tick()
            if drive.via1.ifr & VIA6522.IRQ.ca1 != 0 {
                sawATNInterrupt = true
                break
            }
        }

        XCTAssertTrue(sawATNInterrupt, "ATN edge should set VIA1 CA1 interrupt flag")
    }

    func testC64TrueDriveBooleanUsesCompatibilityMode() {
        let c64 = C64()

        c64.trueDriveEmulation = true
        XCTAssertEqual(c64.trueDriveEmulationMode, .compat1541)
        XCTAssertEqual(c64.drive1541.driveModel, .model1541C)
        XCTAssertEqual(c64.driveClockRatio, 1.0)

        c64.trueDriveEmulationMode = .standard1541
        XCTAssertTrue(c64.trueDriveEmulation)
        XCTAssertEqual(c64.drive1541.driveModel, .model1541)
        XCTAssertEqual(c64.driveClockRatio, 1_000_000.0 / 985_248.0)

        c64.trueDriveEmulation = false
        XCTAssertEqual(c64.trueDriveEmulationMode, .off)
        XCTAssertFalse(c64.drive1541.enabled)
    }

    func testC64EmulationStatusReportsMountedMediaAndDriveState() throws {
        let c64 = C64()
        try loadBundledROMs(into: c64)
        c64.trueDriveEmulationMode = .compat1541

        let disk = makeMinimalG64()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swift64-status-\(UUID().uuidString).g64")
        try disk.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(c64.mountDisk(url))
        c64.powerOn()

        let status = c64.emulationStatus
        XCTAssertEqual(status.trueDriveMode, .compat1541)
        XCTAssertEqual(status.mountedDiskName, url.lastPathComponent)
        XCTAssertEqual(status.mountedDiskFormat, .g64)
        XCTAssertTrue(status.mediaCapabilities?.isNativeLowLevel == true)
        XCTAssertTrue(status.highLevelDiskWriteProtected)
        XCTAssertTrue(status.drive.writeProtected)
        XCTAssertEqual(status.drive.model, .model1541C)
        XCTAssertEqual(status.drive.lastIECCommandSummary, "none")
        XCTAssertNil(status.lastFailureReason)
    }

    func testC64EmulationStatusReportsD64WriteProtectState() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))

        XCTAssertEqual(c64.emulationStatus.mountedDiskFormat, .d64)
        XCTAssertFalse(c64.emulationStatus.highLevelDiskWriteProtected)
        XCTAssertFalse(c64.emulationStatus.drive.writeProtected)

        c64.setMountedDiskWriteProtected(true)

        XCTAssertTrue(c64.emulationStatus.highLevelDiskWriteProtected)
        XCTAssertTrue(c64.emulationStatus.drive.writeProtected)
    }

    func testC64EmulationStatusReportsFFFFHang() {
        let c64 = C64()
        for _ in 0..<20_050 {
            c64.cpu.pc = 0xFFFF
            c64.tickOneCycle()
        }

        XCTAssertEqual(c64.emulationStatus.lastFailureReason, "C64 PC stuck at $FFFF")
    }

    func testC64FFFFHangCounterRequiresConsecutiveCycles() {
        let c64 = C64()
        for _ in 0..<20_050 {
            c64.cpu.pc = 0xFFFF
            c64.tickOneCycle()
            c64.cpu.pc = 0x0004
            c64.tickOneCycle()
        }

        XCTAssertNil(c64.emulationStatus.lastFailureReason)
    }

    func testC64TypeTextQueuesCommandsLongerThanKeyboardBuffer() {
        let c64 = C64()

        c64.typeText("LOAD\"*\",8,1\r")

        XCTAssertEqual(c64.memory.ram[0x00C6], 10)
        XCTAssertEqual(c64.memory.ram[0x0277], 0x4C)

        c64.memory.ram[0x00C6] = 0
        c64.tickOneCycle()

        XCTAssertEqual(c64.memory.ram[0x00C6], 2)
        XCTAssertEqual(c64.memory.ram[0x0277], 0x31)
        XCTAssertEqual(c64.memory.ram[0x0278], 0x0D)
    }

    func testC64HeadlessTrueDriveBootAndLowLevelMount() throws {
        let c64 = C64()
        try loadBundledROMs(into: c64)
        c64.trueDriveEmulationMode = .compat1541

        let disk = makeMinimalG64()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swift64-headless-\(UUID().uuidString).g64")
        try disk.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(c64.mountDisk(url))
        XCTAssertTrue(c64.mountedDiskIsLowLevelCapable)
        XCTAssertEqual(c64.mountedDiskImage?.format, .g64)

        c64.powerOn()

        XCTAssertTrue(c64.drive1541.statusSnapshot.enabled)
        XCTAssertEqual(c64.trueDriveEmulationMode, .compat1541)
        XCTAssertEqual(c64.drive1541.statusSnapshot.model, .model1541C)

        for _ in 0..<5 {
            XCTAssertTrue(c64.runFrame())
        }

        XCTAssertTrue(c64.drive1541.statusSnapshot.enabled)
        XCTAssertNotEqual(c64.cpu.pc, 0)
    }

    func testC64ResetResetsTrueDriveHardwareAndKeepsMountedDisk() {
        let c64 = C64()
        c64.trueDriveEmulationMode = .compat1541
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        c64.drive1541.fireByteReady()
        c64.drive1541.halfTrack = 10
        c64.drive1541.headBitPosition = 512
        c64.drive1541.motorOn = true
        c64.drive1541.via1.writeRegister(0x02, value: 0xFF)
        c64.drive1541.via1.writeRegister(0x00, value: 0x1A)
        c64.driveClockAccumulator = 0.75

        c64.reset()

        XCTAssertTrue(c64.drive1541.statusSnapshot.hasDisk)
        XCTAssertEqual(c64.drive1541.statusSnapshot.halfTrack, 34)
        XCTAssertEqual(c64.drive1541.statusSnapshot.headBitPosition, 0)
        XCTAssertFalse(c64.drive1541.statusSnapshot.motorOn)
        XCTAssertFalse(c64.drive1541.statusSnapshot.byteReady)
        XCTAssertEqual(c64.drive1541.statusSnapshot.byteReadyCount, 0)
        XCTAssertEqual(c64.drive1541.via1.ddrb, 0)
        XCTAssertEqual(c64.drive1541.via1.portB, 0)
        XCTAssertEqual(c64.driveClockAccumulator, 0)
    }

    func testHighLevelD64MutationRefreshesTrueDriveGCRImage() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        let beforeGeneration = c64.drive1541.statusSnapshot.mediaChangeCount

        XCTAssertTrue(c64.diskDrive.savePRG(filename: "SYNC", data: [0x01, 0x08, 0xA9, 0x42, 0x60]))

        let exported = try XCTUnwrap(c64.exportedD64Image)
        let expected = GCRDisk()
        XCTAssertTrue(expected.loadD64(exported))
        XCTAssertEqual(
            c64.drive1541.disk.trackInfo(halfTrack: 0)?.bytes,
            expected.trackInfo(halfTrack: 0)?.bytes
        )
        XCTAssertEqual(
            c64.drive1541.disk.trackInfo(halfTrack: 34)?.bytes,
            expected.trackInfo(halfTrack: 34)?.bytes
        )
        XCTAssertGreaterThan(c64.drive1541.statusSnapshot.mediaChangeCount, beforeGeneration)
        XCTAssertTrue(c64.drive1541.statusSnapshot.mediaChanged)
    }

    func testLowLevelD64SectorWritesAreReflectedInExportedD64Image() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        let base = try XCTUnwrap(c64.exportedD64Image)
        let geometry = try XCTUnwrap(DiskDrive.d64Geometry(forByteCount: base.count))
        let sectorOffset = geometry.trackOffsets[1]

        var sectors = trackSectors(from: [UInt8](base), track: 1, geometry: geometry)
        sectors[0][5] = 0x7D
        let replacementTrack = c64.drive1541.disk.encodeTrack(
            trackNum: 1,
            sectors: sectors,
            diskID: (0x41, 0x42)
        )
        try applyTrackByteDiffs(to: c64.drive1541.disk, halfTrack: 0, replacement: replacementTrack)

        XCTAssertTrue(c64.drive1541.disk.hasUnsavedLowLevelWrites)
        XCTAssertFalse(c64.diskDrive.hasUnsavedChanges)
        XCTAssertTrue(c64.emulationStatus.diskHasUnsavedChanges)

        let exported = try XCTUnwrap(c64.exportedD64Image)
        XCTAssertEqual([UInt8](exported)[sectorOffset + 5], 0x7D)
        XCTAssertTrue(c64.diskDrive.hasUnsavedChanges)
        XCTAssertFalse(c64.drive1541.disk.hasUnsavedLowLevelWrites)
        XCTAssertTrue(c64.emulationStatus.diskHasUnsavedChanges)
    }

    func testUnrepresentableLowLevelD64WritesDoNotExportStaleD64Image() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        let original = try XCTUnwrap(c64.drive1541.disk.trackInfo(halfTrack: 0)?.bytes)
        let gapOrSyncIndex = try XCTUnwrap(original.firstIndex { $0 != 0x00 })

        c64.drive1541.disk.writeProtected = false
        XCTAssertTrue(c64.drive1541.disk.writeByte(0x00, halfTrack: 0, byteIndex: gapOrSyncIndex))

        XCTAssertTrue(c64.drive1541.disk.hasUnsavedLowLevelWrites)
        XCTAssertFalse(c64.diskDrive.hasUnsavedChanges)
        XCTAssertTrue(c64.emulationStatus.d64ExportBlockedByLowLevelWrites)
        XCTAssertFalse(c64.emulationStatus.canExportModifiedD64)
        XCTAssertNil(c64.exportedD64Image)
        XCTAssertTrue(c64.drive1541.disk.hasUnsavedLowLevelWrites)
        XCTAssertFalse(c64.diskDrive.hasUnsavedChanges)
    }

    func testHighLevelD64CommandMutationsRefreshTrueDriveGCRImage() throws {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        var previousGeneration = c64.drive1541.statusSnapshot.mediaChangeCount

        XCTAssertTrue(c64.diskDrive.openFile(channel: 15, filename: "N:SYNC,ID"))
        try assertTrueDriveMatchesExportedD64(c64, since: &previousGeneration)

        XCTAssertTrue(c64.diskDrive.savePRG(filename: "ONE", data: [0x01, 0x08, 0xA9, 0x99, 0x60]))
        try assertTrueDriveMatchesExportedD64(c64, since: &previousGeneration)

        XCTAssertTrue(c64.diskDrive.openFile(channel: 15, filename: "R:TWO=ONE"))
        try assertTrueDriveMatchesExportedD64(c64, since: &previousGeneration)

        XCTAssertTrue(c64.diskDrive.openFile(channel: 15, filename: "S:TWO"))
        try assertTrueDriveMatchesExportedD64(c64, since: &previousGeneration)

        XCTAssertTrue(c64.diskDrive.openFile(channel: 15, filename: "B-A:0,1,2"))
        try assertTrueDriveMatchesExportedD64(c64, since: &previousGeneration)

        XCTAssertTrue(c64.diskDrive.openFile(channel: 15, filename: "B-F:0,1,2"))
        try assertTrueDriveMatchesExportedD64(c64, since: &previousGeneration)

        XCTAssertTrue(c64.diskDrive.openFile(channel: 2, filename: "#"))
        XCTAssertTrue(c64.diskDrive.writeByte(channel: 2, byte: 0xDE))
        XCTAssertTrue(c64.diskDrive.writeByte(channel: 2, byte: 0xAD))
        XCTAssertTrue(c64.diskDrive.writeByte(channel: 2, byte: 0xBE))
        XCTAssertTrue(c64.diskDrive.openFile(channel: 15, filename: "B-W:2,0,1,3"))
        try assertTrueDriveMatchesExportedD64(c64, since: &previousGeneration)

        XCTAssertTrue(c64.diskDrive.openFile(channel: 3, filename: "CHANNEL,S,W"))
        for byte in Array("SYNCED CHANNEL\r".utf8) {
            XCTAssertTrue(c64.diskDrive.writeByte(channel: 3, byte: byte))
        }
        c64.diskDrive.closeChannel(3)
        try assertTrueDriveMatchesExportedD64(c64, since: &previousGeneration)

        XCTAssertTrue(c64.diskDrive.openFile(channel: 15, filename: "C:COPY=CHANNEL"))
        try assertTrueDriveMatchesExportedD64(c64, since: &previousGeneration)

        XCTAssertTrue(c64.diskDrive.openFile(channel: 3, filename: "EMPTY,S,W"))
        c64.diskDrive.closeChannel(3)
        try assertTrueDriveMatchesExportedD64(c64, since: &previousGeneration)

        XCTAssertTrue(c64.diskDrive.openFile(channel: 15, filename: "V"))
        try assertTrueDriveMatchesExportedD64(c64, since: &previousGeneration)
    }

    func testC64MountAndWriteProtectStateStaySyncedAcrossDrivePaths() {
        let c64 = C64()
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        XCTAssertFalse(c64.diskDrive.isWriteProtected)
        XCTAssertFalse(c64.drive1541.statusSnapshot.writeProtected)

        c64.setMountedDiskWriteProtected(true)
        XCTAssertTrue(c64.diskDrive.isWriteProtected)
        XCTAssertTrue(c64.drive1541.statusSnapshot.writeProtected)
        XCTAssertFalse(c64.diskDrive.savePRG(filename: "LOCKED", data: [0x01, 0x08, 0x60]))
        XCTAssertEqual(c64.diskDrive.currentCommandStatus, "26, WRITE PROTECT ON,00,00\r")

        c64.setMountedDiskWriteProtected(false)
        XCTAssertFalse(c64.diskDrive.isWriteProtected)
        XCTAssertFalse(c64.drive1541.statusSnapshot.writeProtected)
        XCTAssertTrue(c64.diskDrive.savePRG(filename: "OPEN", data: [0x01, 0x08, 0x60]))
        XCTAssertFalse(c64.drive1541.statusSnapshot.writeProtected)

        XCTAssertTrue(c64.mountDisk(makeMinimalG64(), fileName: "decoded.g64"))
        XCTAssertTrue(c64.diskDrive.isWriteProtected)
        XCTAssertTrue(c64.drive1541.statusSnapshot.writeProtected)

        XCTAssertTrue(c64.mountDisk(makeNativeOnlyG64(), fileName: "native-only.g64"))
        XCTAssertFalse(c64.diskDrive.isMounted)
        XCTAssertTrue(c64.diskDrive.isWriteProtected)
        XCTAssertTrue(c64.drive1541.statusSnapshot.writeProtected)
    }

    func testC64ResetClearsPendingTypedTextQueue() {
        let c64 = C64()
        c64.typeText("LOAD\"*\",8,1\r")

        c64.reset()
        c64.memory.ram[0x00C6] = 0
        c64.tickOneCycle()

        XCTAssertEqual(c64.memory.ram[0x00C6], 0)
    }

    func testTrueDriveLoadCommandReachesIECSerialHandshake() throws {
        try requireSlowTrueDriveTests()
        let c64 = try makeBootedTrueDriveC64WithMinimalG64()

        c64.typeText("LOAD\"$\",8\r")

        var sawSerialRoutine = false
        var sawATNAsserted = false
        var sawDriveATN = false

        for _ in 0..<2_000_000 {
            c64.tickOneCycle()
            let pc = c64.cpu.pc
            if pc >= 0xED00 && pc <= 0xEEFF {
                sawSerialRoutine = true
            }
            if c64.iecBus.c64Atn {
                sawATNAsserted = true
            }
            if c64.drive1541.via1.ifr & VIA6522.IRQ.ca1 != 0 {
                sawDriveATN = true
                break
            }
        }

        XCTAssertTrue(sawSerialRoutine, "C64 should enter Kernal IEC serial routines for LOAD in true-drive mode")
        XCTAssertTrue(sawATNAsserted, "C64 should assert ATN on the IEC bus for LOAD")
        XCTAssertTrue(sawDriveATN, "Drive VIA1 should observe the ATN edge")
    }

    func testTrueDriveLoadCommandRunsDriveATNHandler() throws {
        try requireSlowTrueDriveTests()
        let c64 = try makeBootedTrueDriveC64WithMinimalG64()

        c64.typeText("LOAD\"$\",8\r")

        var sawATNInterrupt = false
        var sawATNHandler = false
        var sawReceiveByteRoutine = false

        for _ in 0..<2_500_000 {
            c64.tickOneCycle()

            if c64.drive1541.via1.ifr & VIA6522.IRQ.ca1 != 0 {
                sawATNInterrupt = true
            }

            let pc = c64.drive1541.cpu.pc
            if pc >= 0xE85B && pc <= 0xE8F0 {
                sawATNHandler = true
            }
            if pc >= 0xE9C9 && pc <= 0xE9F0 {
                sawReceiveByteRoutine = true
                break
            }
        }

        XCTAssertTrue(sawATNInterrupt, "Drive VIA1 should raise CA1 for the C64 ATN edge")
        XCTAssertTrue(sawATNHandler, "1541 ROM should vector into the ATN command handler")
        XCTAssertTrue(sawReceiveByteRoutine, "1541 ROM should enter the serial byte receive routine after ATN")
    }

    func testTrueDriveReceivesListenCommandByte() throws {
        try requireSlowTrueDriveTests()
        let c64 = try makeBootedTrueDriveC64WithMinimalG64()

        c64.typeText("LOAD\"$\",8\r")

        var receivedCommand: UInt8?

        for _ in 0..<2_600_000 {
            c64.tickOneCycle()

            if c64.drive1541.cpu.cycle == 0 && c64.drive1541.cpu.pc == 0xE887 {
                receivedCommand = c64.drive1541.cpu.a
                break
            }
        }

        XCTAssertEqual(receivedCommand, 0x28, "1541 should receive IEC LISTEN for device 8 as the first ATN command byte")
    }

    func testTrueDriveListenCommandCompletesATNAcknowledgeCycle() throws {
        try requireSlowTrueDriveTests()
        let c64 = try makeBootedTrueDriveC64WithMinimalG64()

        c64.typeText("LOAD\"$\",8\r")

        var receivedListen = false
        var releasedAfterListen = false

        for _ in 0..<2_800_000 {
            c64.tickOneCycle()

            if c64.drive1541.cpu.cycle == 0,
               c64.drive1541.cpu.pc == 0xE887,
               c64.drive1541.cpu.a == 0x28 {
                receivedListen = true
            }

            let bus = c64.iecBus.snapshot
            if receivedListen,
               bus.atnLine,
               !bus.driveAtn,
               bus.dataLine {
                releasedAfterListen = true
                break
            }
        }

        XCTAssertTrue(receivedListen, "1541 should receive IEC LISTEN for device 8")
        XCTAssertTrue(releasedAfterListen, "1541 should release ATNA/DATA after the C64 releases ATN")
    }

    func testTrueDriveD64DirectoryLoadStartsGCRReadHardware() throws {
        try requireSlowTrueDriveTests()
        let c64 = try makeBootedTrueDriveC64WithMinimalD64()
        let baseline = c64.drive1541.statusSnapshot

        c64.typeText("LOAD\"$\",8\r")

        var sawListen = false
        var sawSecondary = false
        var sawDirectoryName = false
        var sawTalk = false
        var sawTalkSecondary = false
        var sawUntalk = false
        var sawCloseListen = false
        var sawMotor = false
        var sawSync = false
        var sawByteReady = false
        var sawPortARead = false
        var sawDirectoryTitleInRAM = false
        var sawFileEntryInRAM = false
        var sawDirectoryFooterInRAM = false
        var sawLoadEndAddress = false
        var sawEOFStatus = false
        let titleBytes = Array("TRUE DRIVE".utf8)
        let helloBytes = Array("HELLO".utf8)
        let prgBytes = Array("PRG".utf8)
        let footerBytes = Array("BLOCKS FREE.".utf8)

        for _ in 0..<8_000_000 {
            c64.tickOneCycle()

            if c64.drive1541.cpu.cycle == 0,
               c64.drive1541.cpu.pc == 0xE887,
               c64.drive1541.cpu.a == 0x28 {
                sawListen = true
            }
            sawSecondary = sawSecondary || c64.drive1541.decodedIECCommandBytes.contains(0xF0)
            sawDirectoryName = sawDirectoryName || c64.drive1541.decodedIECDataBytes.contains(0x24)
            sawTalk = sawTalk || c64.drive1541.decodedIECCommandBytes.contains(0x48)
            sawTalkSecondary = sawTalkSecondary || c64.drive1541.decodedIECCommandBytes.contains(0x60)
            sawUntalk = sawUntalk || c64.drive1541.decodedIECCommandBytes.contains(0x5F)
            sawCloseListen = sawCloseListen || c64.drive1541.decodedIECCommandBytes.contains(0xE0)

            let status = c64.drive1541.statusSnapshot
            sawMotor = sawMotor || status.motorOn
            sawSync = sawSync || status.syncDetectionCount > baseline.syncDetectionCount
            sawByteReady = sawByteReady || status.byteReadyCount > baseline.byteReadyCount
            sawPortARead = sawPortARead || status.via2PortAReadCount > baseline.via2PortAReadCount
            let loadEndAddress = UInt16(c64.memory.ram[0xAE]) | (UInt16(c64.memory.ram[0xAF]) << 8)
            sawLoadEndAddress = sawLoadEndAddress || loadEndAddress >= 0x085F
            if sawLoadEndAddress {
                sawDirectoryTitleInRAM = sawDirectoryTitleInRAM || containsBytes(in: c64.memory.ram, from: 0x0801, to: 0x0860, titleBytes)
                sawFileEntryInRAM = sawFileEntryInRAM ||
                    containsBytes(in: c64.memory.ram, from: 0x0801, to: 0x0860, helloBytes) &&
                    containsBytes(in: c64.memory.ram, from: 0x0801, to: 0x0860, prgBytes)
                sawDirectoryFooterInRAM = sawDirectoryFooterInRAM || containsBytes(in: c64.memory.ram, from: 0x0801, to: 0x0860, footerBytes)
                sawEOFStatus = sawEOFStatus || c64.memory.ram[0x90] == 0x40
            }

            if sawListen && sawSecondary && sawDirectoryName && sawTalk && sawTalkSecondary && sawUntalk && sawCloseListen &&
                sawMotor && sawSync && sawByteReady && sawPortARead &&
                sawDirectoryTitleInRAM && sawFileEntryInRAM && sawDirectoryFooterInRAM && sawLoadEndAddress && sawEOFStatus {
                break
            }
        }

        print(
            String(
                format: "True-drive directory diagnostic pc=$%04X drivePC=$%04X commands=%@ data=%@ via2: PA=$%02X DDRA=$%02X PB=$%02X DDRB=$%02X IFR=$%02X IER=$%02X PCR=$%02X ACR=$%02X BR=%llu PAReads=%llu sync=%llu readBytes=%@ z00=%@ z6f=%@ buf0200=%@",
                c64.cpu.pc,
                c64.drive1541.cpu.pc,
                c64.drive1541.statusSnapshot.lastIECCommandSummary,
                c64.drive1541.decodedIECDataBytes.map { String(format: "%02X", $0) }.joined(separator: " "),
                c64.drive1541.via2.portAInput,
                c64.drive1541.via2.ddra,
                c64.drive1541.via2.portB,
                c64.drive1541.via2.ddrb,
                c64.drive1541.via2.ifr,
                c64.drive1541.via2.ier,
                c64.drive1541.via2.pcr,
                c64.drive1541.via2.acr,
                c64.drive1541.byteReadyCount - baseline.byteReadyCount,
                c64.drive1541.via2PortAReadCount - baseline.via2PortAReadCount,
                c64.drive1541.syncDetectionCount - baseline.syncDetectionCount,
                hexBytes(c64.drive1541.via2PortAReadBytes.prefix(64)),
                hexBytes(c64.drive1541.memory.ram[0x00..<0x20]),
                hexBytes(c64.drive1541.memory.ram[0x6F..<0x80]),
                hexBytes(c64.drive1541.memory.ram[0x0200..<0x0280])
            )
        )

        XCTAssertTrue(sawListen, "1541 should receive IEC LISTEN for device 8")
        XCTAssertTrue(sawSecondary, "1541 should receive the LOAD secondary address after recognizing device 8")
        XCTAssertTrue(sawDirectoryName, "1541 should receive the directory filename byte over the listener data path")
        XCTAssertTrue(sawTalk, "C64 should enter TALK after the drive prepares the directory channel")
        XCTAssertTrue(sawTalkSecondary, "1541 should receive the TALK secondary address")
        XCTAssertTrue(sawUntalk, "C64 should send UNTALK after reading the directory stream")
        XCTAssertTrue(sawCloseListen, "C64 should send LISTEN secondary close for the directory channel")
        XCTAssertTrue(sawMotor, "1541 DOS should start the spindle motor for directory load")
        XCTAssertTrue(sawSync, "GCR head should detect at least one sync mark on the D64-backed track")
        XCTAssertTrue(sawByteReady, "GCR head should present bytes through VIA2/byte-ready")
        XCTAssertTrue(sawPortARead, "1541 ROM should consume at least one GCR byte through VIA2 Port A")
        XCTAssertTrue(sawDirectoryTitleInRAM, "C64 RAM should contain the directory title loaded over the real serial bus")
        XCTAssertTrue(sawFileEntryInRAM, "C64 RAM should contain a directory file entry loaded over the real serial bus")
        XCTAssertTrue(sawDirectoryFooterInRAM, "C64 RAM should contain the directory footer loaded over the real serial bus")
        XCTAssertTrue(sawLoadEndAddress, "Kernal LOAD end pointer should advance past the complete directory listing")
        XCTAssertTrue(sawEOFStatus, "Kernal serial status should report EOF after the directory stream")
    }

    func testTrueDriveD64PrgLoadUsesFileAddress() throws {
        try requireSlowTrueDriveTests()
        let c64 = try makeBootedTrueDriveC64WithMinimalD64()
        var feeder = KeyboardTextFeeder("LOAD\"*\",8,1\r")
        let baseline = c64.drive1541.statusSnapshot
        let payloadBytes: [UInt8] = [0xA9, 0x2A]

        var sawFilename = false
        var sawTalk = false
        var sawTalkSecondary = false
        var sawUntalk = false
        var sawCloseListen = false
        var sawGCRRead = false
        var sawPayload = false
        var sawLoadEndAddress = false
        var sawEOFStatus = false

        for _ in 0..<10_000_000 {
            feeder.tick(c64)
            c64.tickOneCycle()

            sawFilename = sawFilename || c64.drive1541.decodedIECDataBytes.contains(0x2A)
            sawTalk = sawTalk || c64.drive1541.decodedIECCommandBytes.contains(0x48)
            sawTalkSecondary = sawTalkSecondary || c64.drive1541.decodedIECCommandBytes.contains(0x60)
            sawUntalk = sawUntalk || c64.drive1541.decodedIECCommandBytes.contains(0x5F)
            sawCloseListen = sawCloseListen || c64.drive1541.decodedIECCommandBytes.contains(0xE0)
            sawGCRRead = sawGCRRead || c64.drive1541.statusSnapshot.via2PortAReadCount > baseline.via2PortAReadCount

            let loadEndAddress = UInt16(c64.memory.ram[0xAE]) | (UInt16(c64.memory.ram[0xAF]) << 8)
            sawLoadEndAddress = sawLoadEndAddress || loadEndAddress >= 0x0804
            if sawLoadEndAddress {
                sawPayload = sawPayload || Array(c64.memory.ram[0x0801...0x0802]) == payloadBytes
                sawEOFStatus = sawEOFStatus || c64.memory.ram[0x90] == 0x40
            }

            if sawFilename && sawTalk && sawTalkSecondary && sawUntalk && sawCloseListen &&
                sawGCRRead && sawPayload && sawLoadEndAddress && sawEOFStatus {
                break
            }
        }

        XCTAssertTrue(sawFilename, "1541 should receive wildcard filename byte for LOAD\"*\"")
        XCTAssertTrue(sawTalk, "C64 should enter TALK after the drive opens the first PRG")
        XCTAssertTrue(sawTalkSecondary, "1541 should receive the TALK secondary address for PRG load")
        XCTAssertTrue(sawUntalk, "C64 should send UNTALK after reading the PRG stream")
        XCTAssertTrue(sawCloseListen, "C64 should close the load channel after PRG load")
        XCTAssertTrue(sawGCRRead, "1541 ROM should consume GCR bytes while loading the PRG")
        XCTAssertTrue(sawPayload, "PRG payload should be loaded at its file address $0801")
        XCTAssertTrue(sawLoadEndAddress, "Kernal LOAD end pointer should advance past the PRG payload")
        XCTAssertTrue(sawEOFStatus, "Kernal serial status should report EOF after PRG load")
    }

    func testCompatTrueDriveUsesDirectoryTrapForLoadDollarWithSecondaryOne() {
        let c64 = C64()
        c64.trueDriveEmulationMode = .compat1541
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        prepareKernalLoadTrap(c64, filename: "$", device: 8, secondary: 1)

        XCTAssertTrue(c64.shouldUseKernalTrapAtCurrentInstruction())
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        let endAddress = UInt16(c64.memory.ram[0xAE]) | (UInt16(c64.memory.ram[0xAF]) << 8)
        XCTAssertGreaterThan(endAddress, 0x0801)
        XCTAssertEqual(c64.memory.ram[0x0801], 0x1F)
        XCTAssertEqual(c64.memory.ram[0x0802], 0x08)
        XCTAssertTrue(containsBytes(in: c64.memory.ram, from: 0x0801, to: 0x0900, Array("TRUE DRIVE".utf8)))
        XCTAssertTrue(containsBytes(in: c64.memory.ram, from: 0x0801, to: 0x0900, Array("HELLO".utf8)))
        XCTAssertEqual(c64.memory.ram[0x90], 0)
    }

    func testCompatTrueDriveUsesLoadTrapForWildcardPrgWithSecondaryOne() {
        let c64 = C64()
        c64.trueDriveEmulationMode = .compat1541
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        prepareKernalLoadTrap(c64, filename: "*", device: 8, secondary: 1)

        XCTAssertTrue(c64.shouldUseKernalTrapAtCurrentInstruction())
        XCTAssertTrue(c64.kernalTraps.checkTrap())

        let endAddress = UInt16(c64.memory.ram[0xAE]) | (UInt16(c64.memory.ram[0xAF]) << 8)
        XCTAssertEqual(c64.memory.ram[0x0801], 0xA9)
        XCTAssertEqual(c64.memory.ram[0x0802], 0x2A)
        XCTAssertEqual(endAddress, 0x0803)
        XCTAssertEqual(c64.memory.ram[0x90], 0)
    }

    func testCompatTrueDriveDoesNotTrapNativeOnlyG64Load() {
        let c64 = C64()
        c64.trueDriveEmulationMode = .compat1541
        XCTAssertTrue(c64.mountDisk(makeNativeOnlyG64(), fileName: "native-only.g64"))
        XCTAssertFalse(c64.diskDrive.isMounted)
        XCTAssertTrue(c64.drive1541.statusSnapshot.hasNativeLowLevelImage)

        prepareKernalLoadTrap(c64, filename: "*", device: 8, secondary: 1)

        XCTAssertFalse(c64.shouldUseKernalTrapAtCurrentInstruction())
    }

    func testNativeOnlyG64MountClearsPreviousHighLevelDiskTrapState() {
        let c64 = C64()
        c64.trueDriveEmulationMode = .compat1541
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        XCTAssertTrue(c64.diskDrive.isMounted)

        XCTAssertTrue(c64.mountDisk(makeNativeOnlyG64(), fileName: "native-only.g64"))

        XCTAssertFalse(c64.diskDrive.isMounted)
        XCTAssertTrue(c64.drive1541.statusSnapshot.hasNativeLowLevelImage)

        prepareKernalLoadTrap(c64, filename: "*", device: 8, secondary: 1)

        XCTAssertFalse(c64.shouldUseKernalTrapAtCurrentInstruction())
    }

    func testCompatTrueDriveUsesTrapForDecodedNativeG64Load() {
        let c64 = C64()
        c64.trueDriveEmulationMode = .compat1541
        XCTAssertTrue(c64.mountDisk(makeMinimalG64(), fileName: "decoded-native.g64"))
        XCTAssertTrue(c64.diskDrive.isMounted)
        XCTAssertEqual(c64.diskDrive.mountedFormat, .g64)
        XCTAssertTrue(c64.drive1541.statusSnapshot.hasNativeLowLevelImage)

        prepareKernalLoadTrap(c64, filename: "*", device: 8, secondary: 1)

        XCTAssertTrue(c64.shouldUseKernalTrapAtCurrentInstruction())
    }

    func testStandardTrueDriveDoesNotTrapDecodedNativeG64Load() {
        let c64 = C64()
        c64.trueDriveEmulationMode = .standard1541
        XCTAssertTrue(c64.mountDisk(makeMinimalG64(), fileName: "decoded-native.g64"))
        XCTAssertTrue(c64.diskDrive.isMounted)
        XCTAssertEqual(c64.diskDrive.mountedFormat, .g64)
        XCTAssertTrue(c64.drive1541.statusSnapshot.hasNativeLowLevelImage)

        prepareKernalLoadTrap(c64, filename: "*", device: 8, secondary: 1)

        XCTAssertFalse(c64.shouldUseKernalTrapAtCurrentInstruction())
    }

    func testTypedFastLoadWildcardD64ReachesKernalTrap() throws {
        let c64 = C64()
        try loadBundledROMs(into: c64)
        c64.trueDriveEmulationMode = .off
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        c64.powerOn()

        for _ in 0..<20 {
            XCTAssertTrue(c64.runFrame())
        }

        c64.typeText("LOAD\"*\",8,1\r")

        XCTAssertTrue(runUntilPRGPayloadLoaded(c64), "Typed LOAD should reach the high-level disk trap in fast-load mode")
        XCTAssertEqual(c64.memory.ram[0x0801], 0xA9)
        XCTAssertEqual(c64.memory.ram[0x0802], 0x2A)
        XCTAssertEqual(c64.memory.ram[0x90], 0)
    }

    func testTypedCompatTrueDriveWildcardD64ReachesCompatibilityTrap() throws {
        let c64 = C64()
        try loadBundledROMs(into: c64)
        c64.trueDriveEmulationMode = .compat1541
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        c64.powerOn()

        for _ in 0..<20 {
            XCTAssertTrue(c64.runFrame())
        }

        c64.typeText("LOAD\"*\",8,1\r")

        XCTAssertTrue(runUntilPRGPayloadLoaded(c64), "Typed LOAD should use the compatibility trap in compat true-drive mode")
        XCTAssertEqual(c64.memory.ram[0x0801], 0xA9)
        XCTAssertEqual(c64.memory.ram[0x0802], 0x2A)
        XCTAssertEqual(c64.memory.ram[0x90], 0)
    }

    func testStandardTrueDriveDoesNotUseDirectoryTrap() {
        let c64 = C64()
        c64.trueDriveEmulationMode = .standard1541
        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        prepareKernalLoadTrap(c64, filename: "$", device: 8, secondary: 1)

        XCTAssertFalse(c64.shouldUseKernalTrapAtCurrentInstruction())
    }

    private func runUntilPRGPayloadLoaded(_ c64: C64, maxCycles: Int = 2_000_000) -> Bool {
        for _ in 0..<maxCycles {
            c64.tickOneCycle()
            let endAddress = UInt16(c64.memory.ram[0xAE]) | (UInt16(c64.memory.ram[0xAF]) << 8)
            if c64.memory.ram[0x0801] == 0xA9,
               c64.memory.ram[0x0802] == 0x2A,
               endAddress == 0x0803,
               c64.memory.ram[0x90] == 0 {
                return true
            }
        }
        return false
    }

    private func makeBootedTrueDriveC64WithMinimalG64() throws -> C64 {
        let c64 = C64()
        try loadBundledROMs(into: c64)
        c64.trueDriveEmulationMode = .standard1541

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("swift64-load-\(UUID().uuidString).g64")
        try makeMinimalG64().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(c64.mountDisk(url))
        c64.powerOn()

        for _ in 0..<20 {
            XCTAssertTrue(c64.runFrame())
        }

        return c64
    }

    private func requireSlowTrueDriveTests() throws {
        guard ProcessInfo.processInfo.environment[Self.slowTrueDriveEnv] == "1" else {
            throw XCTSkip("Set \(Self.slowTrueDriveEnv)=1 to run slow true-drive serial load milestones")
        }
    }

    private func makeDriveWithSpeedMappedTrack(zone: UInt8) -> Drive1541 {
        makeDriveWithTrack(
            bytes: [UInt8](repeating: 0x00, count: 256),
            speedZone: Int(zone),
            speedZoneMap: [UInt8](repeating: zone, count: 256)
        )
    }

    private func makeDriveWithTrack(
        bytes: [UInt8],
        speedZone: Int = 2,
        speedZoneMap: [UInt8]? = nil,
        weakBitRanges: [DiskImage.Track.WeakBitRange] = []
    ) -> Drive1541 {
        let drive = Drive1541()
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[36] = DiskImage.Track(
            halfTrack: 36,
            bytes: bytes,
            speedZone: speedZone,
            speedZoneMap: speedZoneMap,
            weakBitRanges: weakBitRanges,
            isNativeLowLevel: true
        )

        XCTAssertTrue(drive.insertDiskImage(DiskImage(format: .g64, tracks: tracks, maxTrackSize: bytes.count)))
        drive.halfTrack = 36
        drive.motorOn = true
        return drive
    }

    private func makeDriveWithTracks(_ trackBytes: [Int: [UInt8]]) -> Drive1541 {
        let drive = Drive1541()
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        for (halfTrack, bytes) in trackBytes {
            tracks[halfTrack] = DiskImage.Track(
                halfTrack: halfTrack,
                bytes: bytes,
                speedZone: 2,
                isNativeLowLevel: true
            )
        }

        XCTAssertTrue(drive.insertDiskImage(DiskImage(format: .g64, tracks: tracks, maxTrackSize: trackBytes.values.map(\.count).max())))
        drive.motorOn = true
        return drive
    }

    private func readPresentedGCRBytes(from drive: Drive1541, count: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        for _ in 0..<12_000 {
            drive.tickGCRHead()
            if drive.statusSnapshot.byteReady {
                bytes.append(drive.via2.readRegister(0x01))
                if bytes.count == count { break }
            }
        }
        return bytes
    }

    private func runWriteHead(_ drive: Drive1541, completeBytes: UInt64) {
        let target = drive.statusSnapshot.gcrWriteByteCount + completeBytes
        for _ in 0..<12_000 {
            drive.tickGCRHead()
            if drive.statusSnapshot.gcrWriteByteCount >= target { return }
        }
        XCTFail("Timed out waiting for \(completeBytes) GCR write byte(s)")
    }

    private func runWriteHeadErase(_ drive: Drive1541, erasedBits: UInt64) {
        let target = drive.statusSnapshot.gcrWriteEraseBitCount + erasedBits
        for _ in 0..<12_000 {
            drive.tickGCRHead()
            if drive.statusSnapshot.gcrWriteEraseBitCount >= target { return }
        }
        XCTFail("Timed out waiting for \(erasedBits) GCR erase bit(s)")
    }

    private func runWriteHeadCycles(_ drive: Drive1541, cycles: Int = 256) {
        for _ in 0..<cycles {
            drive.tickGCRHead()
        }
    }

    private func assertTrueDriveMatchesExportedD64(
        _ c64: C64,
        since previousGeneration: inout UInt64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let exported = try XCTUnwrap(c64.exportedD64Image, file: file, line: line)
        let expected = GCRDisk()
        XCTAssertTrue(expected.loadD64(exported), file: file, line: line)

        for halfTrack in 0..<GCRDisk.maxHalfTracks {
            XCTAssertEqual(
                c64.drive1541.disk.trackInfo(halfTrack: halfTrack)?.bytes,
                expected.trackInfo(halfTrack: halfTrack)?.bytes,
                "half track \(halfTrack)",
                file: file,
                line: line
            )
        }

        let generation = c64.drive1541.statusSnapshot.mediaChangeCount
        XCTAssertGreaterThan(generation, previousGeneration, file: file, line: line)
        previousGeneration = generation
    }

    private func trackSectors(from image: [UInt8], track: Int, geometry: DiskDrive.D64Geometry) -> [[UInt8]] {
        let trackOffset = geometry.trackOffsets[track]
        return (0..<geometry.sectorsPerTrack[track]).map { sector in
            let offset = trackOffset + sector * 256
            return Array(image[offset..<(offset + 256)])
        }
    }

    private func applyTrackByteDiffs(to disk: GCRDisk, halfTrack: Int, replacement: [UInt8]) throws {
        let current = try XCTUnwrap(disk.trackInfo(halfTrack: halfTrack)?.bytes)
        XCTAssertEqual(current.count, replacement.count)
        disk.writeProtected = false

        var changed = 0
        for index in current.indices where current[index] != replacement[index] {
            XCTAssertTrue(disk.writeByte(replacement[index], halfTrack: halfTrack, byteIndex: index))
            changed += 1
        }
        XCTAssertGreaterThan(changed, 0)
    }

    private func makeDiskImageWithTrack(bytes: [UInt8]) -> DiskImage {
        var tracks = [DiskImage.Track?](repeating: nil, count: GCRDisk.maxHalfTracks)
        tracks[36] = DiskImage.Track(
            halfTrack: 36,
            bytes: bytes,
            speedZone: 2,
            isNativeLowLevel: true
        )
        return DiskImage(format: .g64, tracks: tracks, maxTrackSize: bytes.count)
    }

    private func makeBootedTrueDriveC64WithMinimalD64() throws -> C64 {
        let c64 = C64()
        try loadBundledROMs(into: c64)
        c64.trueDriveEmulationMode = .standard1541

        XCTAssertTrue(c64.mountDisk(makeMinimalD64()))
        c64.powerOn()

        for _ in 0..<20 {
            XCTAssertTrue(c64.runFrame())
        }

        return c64
    }

    private func containsBytes(in bytes: [UInt8], from start: Int, to end: Int, _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, end <= bytes.count, start >= 0, end - start >= needle.count else { return false }
        for index in start...(end - needle.count) {
            var matched = true
            for needleIndex in 0..<needle.count where bytes[index + needleIndex] != needle[needleIndex] {
                matched = false
                break
            }
            if matched {
                return true
            }
        }
        return false
    }

    private func hexBytes<C: Collection>(_ bytes: C) -> String where C.Element == UInt8 {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func prepareKernalLoadTrap(_ c64: C64, filename: String, device: UInt8, secondary: UInt8) {
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
        c64.cpu.a = 0
        c64.cpu.pc = KernalTraps.loadRoutine
        c64.cpu.sp = 0xFB
        c64.memory.ram[0x01FC] = 0x34
        c64.memory.ram[0x01FD] = 0x12
    }

    private struct KeyboardTextFeeder {
        private var bytes: [UInt8]
        private var offset: Int = 0

        init(_ text: String) {
            bytes = text.map { char in
                guard let ascii = char.asciiValue else { return 0x20 }
                switch ascii {
                case 0x0D: return 0x0D
                case 0x20...0x40: return ascii
                case 0x41...0x5A: return ascii
                case 0x61...0x7A: return ascii - 32
                default: return 0x20
                }
            }
        }

        mutating func tick(_ c64: C64) {
            guard offset < bytes.count, c64.memory.ram[0x00C6] == 0 else { return }
            let count = min(10, bytes.count - offset)
            for index in 0..<count {
                c64.memory.ram[0x0277 + index] = bytes[offset + index]
            }
            c64.memory.ram[0x00C6] = UInt8(count)
            offset += count
        }
    }

    private func loadBundledROMs(into c64: C64) throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let roms = root.appendingPathComponent("Sources/C64App/ROMS")
        let basic = try Data(contentsOf: roms.appendingPathComponent("C64-901226-01-Commodore-F833D117-Basic.rom"))
        let kernal = try Data(contentsOf: roms.appendingPathComponent("C64-901227-03-Commodore-DBE3E7C7-Kernal.rom"))
        let charset = try Data(contentsOf: roms.appendingPathComponent("C64-901225-01-Commodore-EC4272EE-Characters.rom"))
        let drive = try Data(contentsOf: roms.appendingPathComponent("1541C.251968-02.bin"))

        c64.loadROMs(basic: basic, kernal: kernal, charset: charset)
        c64.loadDriveROM(drive)
    }

    private func makeMinimalG64() -> Data {
        var g64 = [UInt8]()
        g64.append(contentsOf: Array("GCR-1541".utf8))
        g64.append(0x00)
        g64.append(84)
        g64.append(0x00)
        g64.append(0x1E)

        let offsetTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))
        let speedTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))

        let track = GCRDisk()
        let sector = [UInt8](repeating: 0, count: 256)
        let trackBytes = track.encodeTrack(trackNum: 18, sectors: (0..<19).map { _ in sector }, diskID: (0x41, 0x42))
        let trackOffset = g64.count
        g64.append(UInt8(trackBytes.count & 0xFF))
        g64.append(UInt8(trackBytes.count >> 8))
        g64.append(contentsOf: trackBytes)

        let halfTrack = 34
        let offsetPos = offsetTableStart + halfTrack * 4
        g64[offsetPos] = UInt8(trackOffset & 0xFF)
        g64[offsetPos + 1] = UInt8((trackOffset >> 8) & 0xFF)
        g64[offsetPos + 2] = UInt8((trackOffset >> 16) & 0xFF)
        g64[offsetPos + 3] = UInt8((trackOffset >> 24) & 0xFF)

        let speedPos = speedTableStart + halfTrack * 4
        g64[speedPos] = UInt8(GCRDisk.speedZone(for: 18))

        return Data(g64)
    }

    private func makeNativeOnlyG64() -> Data {
        var g64 = [UInt8]()
        g64.append(contentsOf: Array("GCR-1541".utf8))
        g64.append(0x00)
        g64.append(84)
        g64.append(0x00)
        g64.append(0x1E)

        let offsetTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))
        let speedTableStart = g64.count
        g64.append(contentsOf: [UInt8](repeating: 0, count: 84 * 4))

        let trackBytes = [UInt8](repeating: 0x55, count: 512)
        let trackOffset = g64.count
        g64.append(UInt8(trackBytes.count & 0xFF))
        g64.append(UInt8(trackBytes.count >> 8))
        g64.append(contentsOf: trackBytes)

        let halfTrack = 0
        let offsetPos = offsetTableStart + halfTrack * 4
        g64[offsetPos] = UInt8(trackOffset & 0xFF)
        g64[offsetPos + 1] = UInt8((trackOffset >> 8) & 0xFF)
        g64[offsetPos + 2] = UInt8((trackOffset >> 16) & 0xFF)
        g64[offsetPos + 3] = UInt8((trackOffset >> 24) & 0xFF)

        let speedPos = speedTableStart + halfTrack * 4
        g64[speedPos] = 0x02

        return Data(g64)
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

        let diskName = Array("TRUE DRIVE".utf8)
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
