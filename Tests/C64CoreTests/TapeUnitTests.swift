import XCTest
@testable import C64Core

final class TapeUnitTests: XCTestCase {
    func testMountsTAPVersion0AsRawPulseSignal() {
        let tape = TapeUnit()
        let tap = makeTAP(version: 0, payload: [0x2C, 0x3F, 0x00])

        XCTAssertTrue(tape.mount(tap))
        XCTAssertEqual(tape.format, .tap)
        XCTAssertTrue(tape.entries.isEmpty)
        XCTAssertEqual(tape.tapPulses, [
            .init(cycles: 0x2C * 8, isOverflow: false),
            .init(cycles: 0x3F * 8, isOverflow: false),
            .init(cycles: 256 * 8, isOverflow: true)
        ])
        XCTAssertEqual(tape.tapDecodeStatus, .rawPulsesOnly(pulseCount: 3))
    }

    func testMountsTAPVersion1OverflowPulseWithExactCycleLength() {
        let tape = TapeUnit()
        let tap = makeTAP(version: 1, payload: [0x2C, 0x00, 0x34, 0x12, 0x01])

        XCTAssertTrue(tape.mount(tap))
        XCTAssertEqual(tape.tapPulses, [
            .init(cycles: 0x2C * 8, isOverflow: false),
            .init(cycles: 0x011234, isOverflow: true)
        ])
    }

    func testMountsStandardCBMTAPRawPRGBlockAsLoadableEntry() throws {
        let tape = TapeUnit()
        let tap = makeStandardCBMTAP(blocks: [
            [0x01, 0x08, 0xA9, 0x2A, 0x60]
        ])

        XCTAssertTrue(tape.mount(tap))
        XCTAssertEqual(tape.format, .tap)
        let entry = try XCTUnwrap(tape.entries.first)
        XCTAssertEqual(tape.entries.count, 1)
        XCTAssertEqual(entry.filename, "TAP FILE")
        XCTAssertEqual(entry.startAddress, 0x0801)
        XCTAssertEqual(tape.readEntry(0), [0x01, 0x08, 0xA9, 0x2A, 0x60])
        XCTAssertEqual(tape.tapDecodeStatus, .decodedPrograms(programCount: 1, pulseCount: 102))
    }

    func testMountsStandardCBMTAPHeaderAndDataBlocksAsNamedEntry() throws {
        let tape = TapeUnit()
        var header = [UInt8](repeating: 0, count: 21)
        header[0] = 1
        header[1] = 0x01
        header[2] = 0x08
        header[3] = 0x04
        header[4] = 0x08
        writeASCII("HELLO", into: &header, at: 5, maxLength: 16)
        let tap = makeStandardCBMTAP(blocks: [
            header,
            [0xA9, 0x2A, 0x60]
        ])

        XCTAssertTrue(tape.mount(tap))
        let entry = try XCTUnwrap(tape.entries.first)
        XCTAssertEqual(tape.entries.count, 1)
        XCTAssertEqual(entry.filename, "HELLO")
        XCTAssertEqual(entry.startAddress, 0x0801)
        XCTAssertEqual(entry.endAddress, 0x0804)
        XCTAssertEqual(tape.readEntry(0), [0x01, 0x08, 0xA9, 0x2A, 0x60])
    }

    func testMountsMultipleStandardCBMTAPProgramsAsSeparateEntries() throws {
        let tape = TapeUnit()
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
        let tap = makeStandardCBMTAP(blocks: [
            firstHeader,
            [0xA9, 0x01],
            secondHeader,
            [0xA9, 0x02, 0x60]
        ])

        XCTAssertTrue(tape.mount(tap))
        XCTAssertEqual(tape.entries.map(\.filename), ["FIRST", "SECOND"])
        XCTAssertEqual(tape.findEntry("SECOND"), 1)
        XCTAssertEqual(tape.readEntry(0), [0x01, 0x08, 0xA9, 0x01])
        XCTAssertEqual(tape.readEntry(1), [0x00, 0x20, 0xA9, 0x02, 0x60])
    }

    func testMountsStandardCBMTAPDuplicateHeaderAndDataBlocks() throws {
        let tape = TapeUnit()
        var header = [UInt8](repeating: 0, count: 21)
        header[0] = 1
        header[1] = 0x00
        header[2] = 0x20
        header[3] = 0x03
        header[4] = 0x20
        writeASCII("DUPTAPE", into: &header, at: 5, maxLength: 16)
        let data = [UInt8]([0xA9, 0x7F, 0x60])
        let tap = makeStandardCBMTAP(blocks: [
            header,
            header,
            data,
            data
        ])

        XCTAssertTrue(tape.mount(tap))
        let entry = try XCTUnwrap(tape.entries.first)
        XCTAssertEqual(tape.entries.count, 1)
        XCTAssertEqual(entry.filename, "DUPTAPE")
        XCTAssertEqual(entry.startAddress, 0x2000)
        XCTAssertEqual(entry.endAddress, 0x2003)
        XCTAssertEqual(tape.readEntry(0), [0x00, 0x20, 0xA9, 0x7F, 0x60])
    }

    func testStandardCBMTAPDuplicateDataUsesCleanSecondCopyAfterBadParity() throws {
        let tape = TapeUnit()
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
        let tap = makeTAP(version: 0, payload: payload)

        XCTAssertTrue(tape.mount(tap))
        let entry = try XCTUnwrap(tape.entries.first)
        XCTAssertEqual(entry.filename, "REPAIRED")
        XCTAssertEqual(tape.readEntry(0), [0x00, 0x20, 0xA9, 0x7F, 0x60])
    }

    func testStandardCBMTAPDuplicateDataRepairsOneBadByteFromEachCopy() throws {
        let tape = TapeUnit()
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
        let tap = makeTAP(version: 0, payload: payload)

        XCTAssertTrue(tape.mount(tap))
        let entry = try XCTUnwrap(tape.entries.first)
        XCTAssertEqual(entry.filename, "VOTED")
        XCTAssertEqual(tape.readEntry(0), [0x00, 0x20, 0xA9, 0x7F, 0x60])
    }

    func testStandardCBMTAPConflictingDuplicateDataDoesNotPickArbitraryCopy() {
        let tape = TapeUnit()
        var header = [UInt8](repeating: 0, count: 21)
        header[0] = 1
        header[1] = 0x00
        header[2] = 0x20
        header[3] = 0x03
        header[4] = 0x20
        writeASCII("CONFLICT", into: &header, at: 5, maxLength: 16)
        let tap = makeStandardCBMTAP(blocks: [
            header,
            header,
            [0xA9, 0x01, 0x60],
            [0xA9, 0x02, 0x60]
        ])

        XCTAssertTrue(tape.mount(tap))
        XCTAssertEqual(tape.format, .tap)
        XCTAssertTrue(tape.entries.isEmpty)
        XCTAssertNil(tape.findEntry("CONFLICT"))
        XCTAssertNil(tape.readEntry(0))
        XCTAssertFalse(tape.tapPulses.isEmpty)
        XCTAssertEqual(tape.tapDecodeStatus, .standardCBMNoPrograms(blockCount: 4, reason: .conflictingDuplicateData))
    }

    func testStandardCBMTAPRejectsBadParityButKeepsRawPulseMount() {
        let tape = TapeUnit()
        var payload = encodeStandardCBMTAPBlock([0x01, 0x08, 0x60])
        payload[4] = 0x40
        let tap = makeTAP(version: 0, payload: payload)

        XCTAssertTrue(tape.mount(tap))
        XCTAssertEqual(tape.format, .tap)
        XCTAssertTrue(tape.entries.isEmpty)
        XCTAssertNil(tape.readEntry(0))
        XCTAssertFalse(tape.tapPulses.isEmpty)
        XCTAssertEqual(tape.tapDecodeStatus, .standardCBMNoPrograms(blockCount: 2, reason: .malformedStandardBlocks))
    }

    func testRejectsTAPWithTruncatedPayloadOrOverflowPulse() {
        let tape = TapeUnit()

        XCTAssertFalse(tape.mount(makeTAP(version: 1, declaredSize: 4, payload: [0x2C])))
        XCTAssertFalse(tape.isMounted)
        XCTAssertFalse(tape.mount(makeTAP(version: 1, payload: [0x00, 0x34, 0x12])))
        XCTAssertFalse(tape.isMounted)
        XCTAssertTrue(tape.tapPulses.isEmpty)
    }

    func testUnmountClearsRawTAPPulses() {
        let tape = TapeUnit()

        XCTAssertTrue(tape.mount(makeTAP(version: 0, payload: [0x2C])))
        XCTAssertFalse(tape.tapPulses.isEmpty)
        XCTAssertTrue(tape.startRawPlayback())

        tape.unmount()

        XCTAssertFalse(tape.isMounted)
        XCTAssertTrue(tape.tapPulses.isEmpty)
        XCTAssertNil(tape.format)
        XCTAssertFalse(tape.rawPlaybackActive)
        XCTAssertTrue(tape.readSignalHigh)
    }

    func testRawPlaybackTicksPulseCountdownAndTogglesReadSignal() {
        let tape = TapeUnit()

        XCTAssertTrue(tape.mount(makeTAP(version: 0, payload: [0x02, 0x03])))
        XCTAssertTrue(tape.startRawPlayback())
        XCTAssertTrue(tape.rawPlaybackActive)
        XCTAssertTrue(tape.readSignalHigh)
        XCTAssertEqual(tape.currentPulseIndex, 0)
        XCTAssertEqual(tape.cyclesUntilNextPulse, 16)

        tape.tickRawPlayback(cycles: 15)

        XCTAssertTrue(tape.readSignalHigh)
        XCTAssertEqual(tape.currentPulseIndex, 0)
        XCTAssertEqual(tape.cyclesUntilNextPulse, 1)

        tape.tickRawPlayback()

        XCTAssertFalse(tape.readSignalHigh)
        XCTAssertEqual(tape.currentPulseIndex, 1)
        XCTAssertEqual(tape.cyclesUntilNextPulse, 24)
    }

    func testRawPlaybackCanAdvanceAcrossMultiplePulsesInOneTick() {
        let tape = TapeUnit()

        XCTAssertTrue(tape.mount(makeTAP(version: 0, payload: [0x01, 0x02, 0x01])))
        XCTAssertTrue(tape.startRawPlayback())

        tape.tickRawPlayback(cycles: 8 + 16 + 4)

        XCTAssertTrue(tape.readSignalHigh)
        XCTAssertEqual(tape.currentPulseIndex, 2)
        XCTAssertEqual(tape.cyclesUntilNextPulse, 4)

        tape.tickRawPlayback(cycles: 4)

        XCTAssertFalse(tape.rawPlaybackActive)
        XCTAssertFalse(tape.readSignalHigh)
        XCTAssertEqual(tape.currentPulseIndex, 3)
        XCTAssertEqual(tape.cyclesUntilNextPulse, 0)
    }

    func testRawPlaybackStartFailsWithoutPulseDataAndStopResetsIdleState() {
        let tape = TapeUnit()

        XCTAssertFalse(tape.startRawPlayback())

        XCTAssertTrue(tape.mount(makeTAP(version: 0, payload: [0x01])))
        XCTAssertTrue(tape.startRawPlayback())
        tape.tickRawPlayback(cycles: 8)

        XCTAssertFalse(tape.rawPlaybackActive)
        XCTAssertFalse(tape.readSignalHigh)

        tape.stopRawPlayback()

        XCTAssertFalse(tape.rawPlaybackActive)
        XCTAssertTrue(tape.readSignalHigh)
        XCTAssertEqual(tape.currentPulseIndex, 0)
        XCTAssertEqual(tape.cyclesUntilNextPulse, 0)
    }

    func testCassetteWriteCaptureRecordsMotorGatedLineEdges() {
        let tape = TapeUnit()

        tape.observeCassetteWriteLine(high: true, atCycle: 4, motorEnabled: true)
        tape.observeCassetteWriteLine(high: false, atCycle: 12, motorEnabled: true)
        tape.observeCassetteMotor(enabled: false)
        tape.observeCassetteWriteLine(high: true, atCycle: 20, motorEnabled: false)
        tape.observeCassetteWriteLine(high: false, atCycle: 28, motorEnabled: true)

        XCTAssertEqual(tape.writePulses, [
            .init(cyclesSincePreviousEdge: 0, levelHigh: true),
            .init(cyclesSincePreviousEdge: 8, levelHigh: false),
            .init(cyclesSincePreviousEdge: 0, levelHigh: false)
        ])
        XCTAssertFalse(tape.writeLineHigh)
    }

    func testCapturedWritePulsesExportAsExactTAPVersion1() {
        let tape = TapeUnit()

        tape.observeCassetteWriteLine(high: true, atCycle: 4, motorEnabled: true)
        tape.observeCassetteWriteLine(high: false, atCycle: 12, motorEnabled: true)
        tape.observeCassetteWriteLine(high: true, atCycle: 0x12_350, motorEnabled: true)

        guard let exported = tape.capturedWriteTAP(version: 1) else {
            return XCTFail("Expected captured write pulses to export as TAP")
        }

        let reloaded = TapeUnit()
        XCTAssertTrue(reloaded.mount(exported))
        XCTAssertEqual(reloaded.tapPulses, [
            .init(cycles: 8, isOverflow: false),
            .init(cycles: 0x12_344, isOverflow: true)
        ])
    }

    func testCapturedWritePulsesExportAsTAPVersion0WhenRepresentable() {
        let tape = TapeUnit()

        tape.observeCassetteWriteLine(high: true, atCycle: 0, motorEnabled: true)
        tape.observeCassetteWriteLine(high: false, atCycle: 8, motorEnabled: true)
        tape.observeCassetteWriteLine(high: true, atCycle: 2_056, motorEnabled: true)

        guard let exported = tape.capturedWriteTAP(version: 0) else {
            return XCTFail("Expected 8-cycle write pulses to export as TAP v0")
        }

        XCTAssertEqual(Array(exported.dropFirst(20)), [0x01, 0x00])
        let reloaded = TapeUnit()
        XCTAssertTrue(reloaded.mount(exported))
        XCTAssertEqual(reloaded.tapPulses, [
            .init(cycles: 8, isOverflow: false),
            .init(cycles: 2_048, isOverflow: true)
        ])
    }

    func testCapturedWriteTAPExportRejectsUnrepresentableDurations() {
        let tape = TapeUnit()

        XCTAssertNil(tape.capturedWriteTAP(version: 1))

        tape.observeCassetteWriteLine(high: true, atCycle: 0, motorEnabled: true)
        tape.observeCassetteWriteLine(high: false, atCycle: 9, motorEnabled: true)

        XCTAssertNil(tape.capturedWriteTAP(version: 0))

        tape.observeCassetteWriteLine(high: true, atCycle: 0x1_000_009, motorEnabled: true)

        XCTAssertNil(tape.capturedWriteTAP(version: 1))
        XCTAssertNil(tape.capturedWriteTAP(version: 2))
    }

    func testMountingNewTAPClearsPreviousRawPlaybackState() {
        let tape = TapeUnit()

        XCTAssertTrue(tape.mount(makeTAP(version: 0, payload: [0x01, 0x02])))
        XCTAssertTrue(tape.startRawPlayback())
        tape.tickRawPlayback(cycles: 8)

        XCTAssertFalse(tape.readSignalHigh)
        XCTAssertEqual(tape.currentPulseIndex, 1)

        XCTAssertTrue(tape.mount(makeTAP(version: 0, payload: [0x03])))

        XCTAssertEqual(tape.format, .tap)
        XCTAssertFalse(tape.rawPlaybackActive)
        XCTAssertTrue(tape.readSignalHigh)
        XCTAssertEqual(tape.currentPulseIndex, 0)
        XCTAssertEqual(tape.cyclesUntilNextPulse, 0)
        XCTAssertEqual(tape.tapPulses, [.init(cycles: 24, isOverflow: false)])
    }

    func testMountingT64ClearsPreviousRawTAPPlaybackState() {
        let tape = TapeUnit()

        XCTAssertTrue(tape.mount(makeTAP(version: 0, payload: [0x01, 0x02])))
        XCTAssertTrue(tape.startRawPlayback())
        tape.tickRawPlayback(cycles: 8)

        XCTAssertFalse(tape.readSignalHigh)
        XCTAssertFalse(tape.tapPulses.isEmpty)

        XCTAssertTrue(tape.mount(makeT64(filename: "HELLO", startAddress: 0x0801, payload: [0x42, 0x43])))

        XCTAssertEqual(tape.format, .t64)
        XCTAssertFalse(tape.rawPlaybackActive)
        XCTAssertTrue(tape.readSignalHigh)
        XCTAssertTrue(tape.tapPulses.isEmpty)
        XCTAssertNil(tape.tapPRGData)
        XCTAssertEqual(tape.tapDecodeStatus, .none)
        XCTAssertEqual(tape.entries.first?.filename, "HELLO")
        XCTAssertEqual(tape.readEntry(0), [0x01, 0x08, 0x42, 0x43])
    }

    func testFailedT64MountDoesNotClobberExistingMountedTape() {
        let tape = TapeUnit()

        XCTAssertTrue(tape.mount(makeTAP(version: 0, payload: [0x02])))
        XCTAssertEqual(tape.format, .tap)
        XCTAssertEqual(tape.containerName, "TAP IMAGE")

        var emptyT64 = [UInt8](makeT64(filename: "EMPTY", startAddress: 0x0801, payload: [0x42]))
        writeASCII("BROKEN T64", into: &emptyT64, at: 0x28, maxLength: 24)
        emptyT64[0x24] = 0
        emptyT64[0x25] = 0

        XCTAssertFalse(tape.mount(Data(emptyT64)))
        XCTAssertEqual(tape.format, .tap)
        XCTAssertEqual(tape.containerName, "TAP IMAGE")
        XCTAssertEqual(tape.tapPulses, [.init(cycles: 16, isOverflow: false)])
    }

    func testT64MountRejectsDirectoryEntryWithOutOfRangeData() {
        let tape = TapeUnit()

        XCTAssertTrue(tape.mount(makeTAP(version: 0, payload: [0x02])))

        var corruptT64 = [UInt8](makeT64(filename: "BROKEN", startAddress: 0x0801, payload: [0x42]))
        writeUInt32LE(UInt32(corruptT64.count + 1), into: &corruptT64, at: 0x48)

        XCTAssertFalse(tape.mount(Data(corruptT64)))
        XCTAssertEqual(tape.format, .tap)
        XCTAssertEqual(tape.containerName, "TAP IMAGE")
        XCTAssertEqual(tape.tapPulses, [.init(cycles: 16, isOverflow: false)])
    }

    func testSavePRGCreatesExportableT64Image() throws {
        let tape = TapeUnit()

        XCTAssertTrue(tape.savePRG(filename: "SAVED,P", data: [0x01, 0x08, 0xA9, 0x2A, 0x60]))

        XCTAssertEqual(tape.format, .t64)
        XCTAssertTrue(tape.hasUnsavedChanges)
        XCTAssertEqual(tape.entries.count, 1)
        XCTAssertEqual(tape.entries[0].filename, "SAVED")
        XCTAssertEqual(tape.readEntry(0), [0x01, 0x08, 0xA9, 0x2A, 0x60])

        let exported = try XCTUnwrap(tape.exportedT64Image)
        let remounted = TapeUnit()
        XCTAssertTrue(remounted.mount(exported))
        XCTAssertEqual(remounted.findEntry("SAVED"), 0)
        XCTAssertEqual(remounted.readEntry(0), [0x01, 0x08, 0xA9, 0x2A, 0x60])

        tape.markChangesSaved()
        XCTAssertFalse(tape.hasUnsavedChanges)
    }

    func testSavePRGAppendsToMountedT64AndRejectsMountedTAP() {
        let tape = TapeUnit()

        XCTAssertTrue(tape.mount(makeT64(filename: "OLD", startAddress: 0x0801, payload: [0x42])))
        XCTAssertTrue(tape.savePRG(filename: "NEW", data: [0x00, 0x20, 0xEA]))
        XCTAssertEqual(tape.entries.map(\.filename), ["OLD", "NEW"])
        XCTAssertEqual(tape.readEntry(1), [0x00, 0x20, 0xEA])

        XCTAssertFalse(tape.savePRG(filename: "NEW", data: [0x00, 0x20, 0xEA]))

        let tap = TapeUnit()
        XCTAssertTrue(tap.mount(makeTAP(version: 0, payload: [0x02])))
        XCTAssertFalse(tap.savePRG(filename: "NOPE", data: [0x01, 0x08, 0x60]))
        XCTAssertNil(tap.exportedT64Image)
    }

    private func makeTAP(version: UInt8, declaredSize: Int? = nil, payload: [UInt8]) -> Data {
        var bytes = [UInt8](repeating: 0, count: 20)
        writeASCII("C64-TAPE-RAW", into: &bytes, at: 0)
        bytes[0x0C] = version
        writeUInt32LE(UInt32(declaredSize ?? payload.count), into: &bytes, at: 0x10)
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    private func makeStandardCBMTAP(blocks: [[UInt8]]) -> Data {
        let payload = blocks.flatMap(encodeStandardCBMTAPBlock)
        return makeTAP(version: 0, payload: payload)
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

    private func makeT64(filename: String, startAddress: UInt16, payload: [UInt8]) -> Data {
        let dataOffset = 0x60
        var bytes = [UInt8](repeating: 0, count: dataOffset)
        writeASCII("C64", into: &bytes, at: 0)
        bytes[0x22] = 1
        bytes[0x24] = 1
        bytes[0x40] = 1
        bytes[0x41] = 1
        writeUInt16LE(startAddress, into: &bytes, at: 0x42)
        writeUInt16LE(startAddress + UInt16(payload.count), into: &bytes, at: 0x44)
        writeUInt32LE(UInt32(dataOffset), into: &bytes, at: 0x48)
        writeASCII(filename, into: &bytes, at: 0x50, maxLength: 16)
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    private func writeASCII(_ string: String, into bytes: inout [UInt8], at offset: Int, maxLength: Int? = nil) {
        for (index, byte) in string.utf8.prefix(maxLength ?? string.utf8.count).enumerated() {
            bytes[offset + index] = byte
        }
    }

    private func writeUInt16LE(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8(value >> 8)
    }

    private func writeUInt32LE(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((value >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}
