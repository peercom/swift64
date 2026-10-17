import XCTest
@testable import C64Core
@testable import Emu6502

final class MachineStateTests: XCTestCase {
    // MARK: - Serialization primitives

    func testWriterAndReaderRoundTripPrimitivesArraysOptionalsAndChunks() throws {
        var w = StateWriter()
        let handle = w.beginChunk("TEST", version: 3)
        w.write(UInt8(0xAB)); w.write(UInt16(0xBEEF)); w.write(UInt32(0xDEADBEEF)); w.write(UInt64.max)
        w.write(Int(-123_456_789)); w.write(Int8(-5)); w.write(true); w.write(false)
        w.write(Double.pi); w.write(Float(1.5)); w.write("héllo"); w.write(["a", "b"])
        w.write([UInt8](repeating: 7, count: 70_000)); w.write([UInt16(1), 2, 3]); w.write([[Bool]]([[true], [false, true]]))
        w.write(Optional<Int>.none); w.write(Optional<Int>.some(42)); w.write([Optional<[UInt8]>]([nil, [1, 2]]))
        w.endChunk(handle)
        let bytesPerChunkHeader = 4 + 2 + 4
        XCTAssertEqual(w.bytes.count - bytesPerChunkHeader, 1 + 2 + 4 + 8 + 8 + 1 + 1 + 1 + 8 + 4 + (4 + 6) + (4 + 5 + 5)
                       + (4 + 70_000) + (4 + 6) + (4 + 4 + 1 + 4 + 2) + 1 + 9 + (4 + 1 + 1 + 4 + 2))

        var r = StateReader(bytes: w.bytes)
        var (version, body) = try r.expectChunk("TEST")
        XCTAssertEqual(version, 3)
        XCTAssertTrue(r.isAtEnd)
        XCTAssertEqual(try body.read() as UInt8, 0xAB); XCTAssertEqual(try body.read() as UInt16, 0xBEEF)
        XCTAssertEqual(try body.read() as UInt32, 0xDEADBEEF); XCTAssertEqual(try body.read() as UInt64, .max)
        XCTAssertEqual(try body.read() as Int, -123_456_789); XCTAssertEqual(try body.read() as Int8, -5)
        XCTAssertTrue(try body.read() as Bool); XCTAssertFalse(try body.read() as Bool)
        XCTAssertEqual(try body.read() as Double, .pi); XCTAssertEqual(try body.read() as Float, 1.5)
        XCTAssertEqual(try body.read() as String, "héllo"); XCTAssertEqual(try body.read() as [String], ["a", "b"])
        XCTAssertEqual((try body.read() as [UInt8]).count, 70_000); XCTAssertEqual(try body.read() as [UInt16], [1, 2, 3])
        XCTAssertEqual(try body.read() as [[Bool]], [[true], [false, true]])
        XCTAssertNil(try body.read() as Int?); XCTAssertEqual(try body.read() as Int?, 42)
        XCTAssertEqual(try body.read() as [[UInt8]?], [nil, [1, 2]])
        XCTAssertNoThrow(try body.finishChunk("TEST"))

        // Truncation, bad booleans, wrong chunk, and unconsumed chunk bodies fail loudly.
        var short = StateReader(bytes: Array(w.bytes.prefix(20)))
        XCTAssertThrowsError(try short.expectChunk("TEST")) { XCTAssertEqual($0 as? MachineStateError, .truncated) }
        var badBool = StateReader(bytes: [2])
        XCTAssertThrowsError(try badBool.read() as Bool)
        var wrongTag = StateReader(bytes: w.bytes)
        XCTAssertThrowsError(try wrongTag.expectChunk("NOPE")) {
            XCTAssertEqual($0 as? MachineStateError, .unexpectedChunk(found: "TEST", expected: "NOPE"))
        }
        var unread = StateReader(bytes: w.bytes)
        let chunk = try unread.expectChunk("TEST").body
        XCTAssertThrowsError(try chunk.finishChunk("TEST")) { XCTAssertEqual($0 as? MachineStateError, .chunkLengthMismatch("TEST")) }
    }

    // MARK: - Completeness guard

    /// Adding a stored property to a chip must be a conscious snapshot decision:
    /// update the save/restore code, then the chip's count.
    func testStoredPropertyCountsMatchSnapshotCode() {
        let c64 = C64()
        func count(_ subject: Any) -> Int { Mirror(reflecting: subject).children.count }
        XCTAssertEqual(count(c64.cpu), CPU6502.snapshotStoredPropertyCount, "CPU6502")
        XCTAssertEqual(count(c64.memory), MemoryMap.snapshotStoredPropertyCount, "MemoryMap")
        XCTAssertEqual(count(c64.vic), VIC.snapshotStoredPropertyCount, "VIC")
        XCTAssertEqual(count(c64.sid), SID.snapshotStoredPropertyCount, "SID")
        XCTAssertEqual(count(c64.cia1), CIA.snapshotStoredPropertyCount, "CIA")
        XCTAssertEqual(count(c64.iecBus), IECBus.snapshotStoredPropertyCount, "IECBus")
        XCTAssertEqual(count(c64.drive1541.via1), VIA6522.snapshotStoredPropertyCount, "VIA6522")
        XCTAssertEqual(count(c64.drive1541), Drive1541.snapshotStoredPropertyCount, "Drive1541")
        XCTAssertEqual(count(c64.drive1541.memory), DriveMemoryMap.snapshotStoredPropertyCount, "DriveMemoryMap")
        XCTAssertEqual(count(c64.drive1541.disk), GCRDisk.snapshotStoredPropertyCount, "GCRDisk")
        XCTAssertEqual(count(c64.tapeUnit), TapeUnit.snapshotStoredPropertyCount, "TapeUnit")
        XCTAssertEqual(count(c64.kernalTraps), KernalTraps.snapshotStoredPropertyCount, "KernalTraps")
        XCTAssertEqual(count(c64.diskDrive), DiskDrive.snapshotStoredPropertyCount, "DiskDrive")
        XCTAssertEqual(count(c64), C64.snapshotStoredPropertyCount, "C64")
    }

    // MARK: - Determinism

    /// A RAM-resident program that drives raster IRQs, sprites, SID, and CIA1
    /// timer IRQs without any ROM.
    private func installProbeProgram(on c64: C64) {
        c64.powerOn()
        let program: [UInt8] = [
            0x78, 0xA9, 0x35, 0x85, 0x01, 0xA9, 0x80, 0x8D, 0xFE, 0xFF, 0xA9, 0x10, 0x8D, 0xFF, 0xFF,
            0xA9, 0x01, 0x8D, 0x1A, 0xD0, 0xA9, 0x80, 0x8D, 0x12, 0xD0, 0xA9, 0x1B, 0x8D, 0x11, 0xD0,
            0x8D, 0x15, 0xD0, 0xA9, 0x81, 0x8D, 0x0D, 0xDC, 0x58,
            0xEE, 0x00, 0x04, 0xAD, 0x12, 0xD0, 0x8D, 0x20, 0xD0, 0x4C, 0x27, 0x10,
        ]
        let handler: [UInt8] = [
            0xAD, 0x0D, 0xDC, 0xEE, 0x19, 0xD0, 0xEE, 0x01, 0x04, 0xAD, 0x01, 0x04, 0x8D, 0x21, 0xD0,
            0x8D, 0x00, 0xD0, 0x8D, 0x00, 0xD4, 0x8D, 0x04, 0xDC, 0xA9, 0x11, 0x8D, 0x0E, 0xDC, 0x40,
        ]
        for (offset, byte) in program.enumerated() { c64.memory.ram[0x1000 + offset] = byte }
        for (offset, byte) in handler.enumerated() { c64.memory.ram[0x1080 + offset] = byte }
        for address in 0x0800..<0x0840 { c64.memory.ram[address] = address & 1 == 0 ? 0xAA : 0x55 }
        for sprite in 0..<8 {
            c64.memory.ram[0x07F8 + sprite] = 0x20
            c64.memory.write(UInt16(0xD001 + sprite * 2), value: UInt8(80 + sprite * 12))
            c64.memory.write(UInt16(0xD000 + sprite * 2), value: UInt8(40 + sprite * 30))
        }
        c64.cpu.pc = 0x1000
    }

    private func signature(of c64: C64) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        func mix(_ byte: UInt8) { hash ^= UInt64(byte); hash = hash &* 0x100000001b3 }
        func mix<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { $0.forEach(mix) } }
        c64.memory.ram.forEach(mix); c64.memory.colorRAM.forEach(mix); c64.vic.framebuffer.forEach { mix($0) }
        mix(c64.cpu.a); mix(c64.cpu.x); mix(c64.cpu.y); mix(c64.cpu.sp); mix(c64.cpu.pc); mix(c64.cpu.p)
        mix(UInt64(c64.cpu.cycle)); mix(c64.cpu.totalCycles)
        mix(c64.vic.rasterLine); mix(UInt64(c64.vic.rasterCycle)); mix(c64.vic.borderColor); mix(c64.vic.readRegister(0x19))
        mix(c64.cia1.timerA); mix(c64.cia1.interruptData); mix(c64.cia2.timerB)
        for voice in c64.sid.voices { mix(voice.accumulator); mix(voice.envelopeLevel) }
        mix(c64.drive1541.cpu.pc); mix(c64.drive1541.cpu.totalCycles); mix(UInt64(c64.drive1541.halfTrack))
        mix(UInt64(c64.drive1541.headBitPosition)); mix(c64.drive1541.via2.timer1Counter)
        mix(c64.iecBus.c64Clk ? 1 : 0); mix(c64.iecBus.driveData ? 1 : 0)
        return hash
    }

    /// Advance until the CPU is inside an instruction and the VIC inside a line.
    private func runToMidInstructionMidLine(_ c64: C64, atLeast cycles: Int) {
        for _ in 0..<cycles { c64.tickOneCycle() }
        var guardCount = 0
        while !(c64.cpu.cycle == 2 && c64.vic.rasterCycle == 30 && c64.vic.rasterLine > 60) && guardCount < 100_000 {
            c64.tickOneCycle()
            guardCount += 1
        }
        XCTAssertNotEqual(c64.cpu.cycle, 0, "snapshot must be taken mid-instruction")
    }

    func testSnapshotMidInstructionContinuesIdenticallyInFreshAndReusedMachines() throws {
        let original = C64()
        installProbeProgram(on: original)
        runToMidInstructionMidLine(original, atLeast: 200_000)
        XCTAssertGreaterThan(original.memory.ram[0x0401], 0, "the raster IRQ handler ran before the snapshot")
        let snapshot = try original.saveState()
        XCTAssertLessThan(snapshot.count, 2_000_000)
        let continuation = 150_000
        for _ in 0..<continuation { original.tickOneCycle() }
        let expected = signature(of: original)

        // Fresh machine: nothing but the snapshot.
        let fresh = C64(machineProfile: .ntscC64)
        try fresh.restoreState(from: snapshot)
        XCTAssertEqual(fresh.machineProfile, .palC64)
        XCTAssertEqual(fresh.vic.rasterCyclesPerLine, VIC.palCyclesPerLine)
        XCTAssertEqual(fresh.cpu.cycle, 2)
        for _ in 0..<continuation { fresh.tickOneCycle() }
        XCTAssertEqual(signature(of: fresh), expected)

        // Same machine, rewound after running on: scratch state must not leak.
        try original.restoreState(from: snapshot)
        for _ in 0..<continuation { original.tickOneCycle() }
        XCTAssertEqual(signature(of: original), expected)

        // Snapshotting the restored machine reproduces the snapshot exactly.
        try fresh.restoreState(from: snapshot)
        XCTAssertEqual(try fresh.saveState(), snapshot)
    }

    func testRestoreRejectsForeignAndTruncatedData() {
        let c64 = C64()
        XCTAssertThrowsError(try c64.restoreState(from: Data("not a snapshot at all".utf8))) {
            XCTAssertEqual($0 as? MachineStateError, .badMagic)
        }
        installProbeProgram(on: c64)
        let snapshot = try! c64.saveState()
        XCTAssertThrowsError(try c64.restoreState(from: snapshot.prefix(snapshot.count / 2))) {
            XCTAssertEqual($0 as? MachineStateError, .truncated)
        }
        var bumped = [UInt8](snapshot)
        bumped[8] = 0xFF
        XCTAssertThrowsError(try c64.restoreState(from: Data(bumped))) {
            XCTAssertEqual($0 as? MachineStateError, .unsupportedVersion(0x00FF))
        }
    }

    // MARK: - Media

    private func makeCRT(name: String, exrom: UInt8, game: UInt8, chips: [(bank: UInt16, address: UInt16, data: [UInt8])]) -> Data {
        var bytes = Array("C64 CARTRIDGE   ".utf8)
        bytes += [0, 0, 0, 0x40, 1, 0, 0, 0, exrom, game, 0, 0, 0, 0, 0, 0]
        var nameBytes = Array(name.utf8.prefix(32)); nameBytes += [UInt8](repeating: 0, count: 32 - nameBytes.count)
        bytes += nameBytes
        for chip in chips {
            bytes += Array("CHIP".utf8)
            let length = UInt32(16 + chip.data.count)
            bytes += [UInt8(length >> 24), UInt8(length >> 16 & 0xFF), UInt8(length >> 8 & 0xFF), UInt8(length & 0xFF)]
            bytes += [0, 0, UInt8(chip.bank >> 8), UInt8(chip.bank & 0xFF), UInt8(chip.address >> 8), UInt8(chip.address & 0xFF)]
            bytes += [UInt8(chip.data.count >> 8), UInt8(chip.data.count & 0xFF)]
            bytes += chip.data
        }
        return Data(bytes)
    }

    func testCartridgeAndHighLevelDiskStateSurviveTheRoundTrip() throws {
        let c64 = C64()
        var rom = [UInt8](repeating: 0xEA, count: 0x2000)
        rom[0x1FFC] = 0x00; rom[0x1FFD] = 0x80
        let crt = makeCRT(name: "SNAP TEST", exrom: 0, game: 1, chips: [(bank: 0, address: 0x8000, data: rom)])
        XCTAssertTrue(c64.mountCartridge(crt))
        var d64 = [UInt8](repeating: 0, count: 174_848)
        d64[0x16500] = 18; d64[0x16501] = 1; d64[0x16502] = 0x41
        for offset in 0x16590..<0x165A0 { d64[offset] = 0x53 }
        XCTAssertTrue(c64.mountDisk(Data(d64), fileName: "blank.d64"))
        installProbeProgram(on: c64)
        for _ in 0..<50_000 { c64.tickOneCycle() }
        XCTAssertNotNil(c64.memory.cartridge)
        let before = c64.memory.cartridge
        let snapshot = try c64.saveState()

        let restored = C64()
        try restored.restoreState(from: snapshot)
        XCTAssertEqual(restored.memory.cartridge, before)
        XCTAssertEqual(restored.mountedCartridgeName, "SNAP TEST")
        XCTAssertEqual(restored.mountedDiskName, "blank.d64")
        XCTAssertTrue(restored.diskDrive.isMounted)
        XCTAssertEqual(restored.diskDrive.mountedFormat, .d64)
        XCTAssertEqual(restored.drive1541.disk.tracks.compactMap { $0 }.count, c64.drive1541.disk.tracks.compactMap { $0 }.count)
        XCTAssertEqual(restored.memory.read(0x8000), 0xEA)

        // Cartridge bank tables are dictionaries, so the embedded property list
        // is not byte-stable; compare behaviour and a second round trip instead.
        let resaved = try restored.saveState()
        let again = C64()
        try again.restoreState(from: resaved)
        XCTAssertEqual(again.memory.cartridge, before)
        for _ in 0..<50_000 { c64.tickOneCycle(); restored.tickOneCycle(); again.tickOneCycle() }
        XCTAssertEqual(signature(of: restored), signature(of: c64))
        XCTAssertEqual(signature(of: again), signature(of: c64))
    }

    // MARK: - ROM-dependent true-drive boot

    private func localROMs() -> (basic: Data, kernal: Data, charset: Data, drive: Data)? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let roms = root.appendingPathComponent("Sources/C64App/ROMS")
        guard let basic = try? Data(contentsOf: roms.appendingPathComponent("C64-901226-01-Commodore-F833D117-Basic.rom")),
              let kernal = try? Data(contentsOf: roms.appendingPathComponent("C64-901227-03-Commodore-DBE3E7C7-Kernal.rom")),
              let charset = try? Data(contentsOf: roms.appendingPathComponent("C64-901225-01-Commodore-EC4272EE-Characters.rom")),
              let drive = try? Data(contentsOf: roms.appendingPathComponent("1541C.251968-02.bin")) else { return nil }
        return (basic, kernal, charset, drive)
    }

    func testBootedTrueDriveMachineSnapshotContinuesIdentically() throws {
        guard let roms = localROMs() else { throw XCTSkip("local ROMs under Sources/C64App/ROMS are required") }
        let c64 = C64()
        c64.loadROMs(basic: roms.basic, kernal: roms.kernal, charset: roms.charset)
        c64.loadDriveROM(roms.drive)
        c64.trueDriveEmulationMode = .compat1541
        var d64 = [UInt8](repeating: 0, count: 174_848)
        d64[0x16500] = 18; d64[0x16501] = 1; d64[0x16502] = 0x41
        XCTAssertTrue(c64.mountDisk(Data(d64), fileName: "blank.d64"))
        c64.powerOn()
        c64.vic.recordsBusAccessTraces = false
        for _ in 0..<60 { XCTAssertTrue(c64.runFrame()) }
        c64.typeText("PRINT 7*6\r")
        for _ in 0..<40 { XCTAssertTrue(c64.runFrame()) }
        XCTAssertGreaterThan(c64.drive1541.cpu.totalCycles, 1_000_000, "the drive CPU ran its ROM")

        runToMidInstructionMidLine(c64, atLeast: 1_000)
        let snapshot = try c64.saveState()
        let continuation = 300_000
        for _ in 0..<continuation { c64.tickOneCycle() }
        let expected = signature(of: c64)

        let restored = C64()
        restored.loadROMs(basic: roms.basic, kernal: roms.kernal, charset: roms.charset)
        restored.loadDriveROM(roms.drive)
        try restored.restoreState(from: snapshot)
        XCTAssertEqual(restored.trueDriveEmulationMode, .compat1541)
        XCTAssertTrue(restored.drive1541.enabled)
        for _ in 0..<continuation { restored.tickOneCycle() }
        XCTAssertEqual(signature(of: restored), expected)
        let screen = restored.memory.ram[0x0400..<0x0400 + 1000]
        XCTAssertTrue(screen.contains(0x34) && screen.contains(0x32), "the typed PRINT result 42 is on screen")
    }
}
