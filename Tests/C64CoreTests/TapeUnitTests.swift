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

    private func makeTAP(version: UInt8, declaredSize: Int? = nil, payload: [UInt8]) -> Data {
        var bytes = [UInt8](repeating: 0, count: 20)
        writeASCII("C64-TAPE-RAW", into: &bytes, at: 0)
        bytes[0x0C] = version
        writeUInt32LE(UInt32(declaredSize ?? payload.count), into: &bytes, at: 0x10)
        bytes.append(contentsOf: payload)
        return Data(bytes)
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
