import XCTest
@testable import C64Core

final class MemoryMapTests: XCTestCase {
    func testResetCPUPortRestoresDefaultROMBankingAndCassetteOutputs() {
        let memory = MemoryMap()
        memory.write(0x0000, value: 0x00)
        memory.write(0x0001, value: 0x00)

        memory.resetCPUPort()

        XCTAssertEqual(memory.portDirection, 0x2F)
        XCTAssertEqual(memory.portData, 0x37)
        XCTAssertEqual(memory.read(0x0001), 0x37)
        XCTAssertFalse(memory.cassetteWriteLineHigh)
        XCTAssertTrue(memory.cassetteMotorLineHigh)
        XCTAssertFalse(memory.cassetteMotorEnabled)
    }

    func testCPUDataPortInputBitsReadAsEffectivePulledUpPortLines() {
        let memory = MemoryMap()

        memory.write(0x0000, value: 0x00)
        memory.write(0x0001, value: 0x00)

        XCTAssertEqual(memory.read(0x0001), 0x37)
    }

    func testCPUInternalPortRegistersOverlayRAMAtZeroAndOne() {
        let memory = MemoryMap()
        memory.ram[0x0000] = 0xAA
        memory.ram[0x0001] = 0xBB

        memory.write(0x0000, value: 0x12)
        memory.write(0x0001, value: 0x23)

        XCTAssertEqual(memory.portDirection, 0x12)
        XCTAssertEqual(memory.portData, 0x23)
        XCTAssertEqual(memory.read(0x0000), 0x12)
        XCTAssertEqual(memory.read(0x0001), 0x27)
        XCTAssertEqual(memory.ram[0x0000], 0xAA)
        XCTAssertEqual(memory.ram[0x0001], 0xBB)
    }

    func testCPUInternalPortReadsIgnoreUnderlyingRAMAfterDirectRAMMutation() {
        let memory = MemoryMap()

        memory.write(0x0000, value: 0x2F)
        memory.write(0x0001, value: 0x37)
        memory.ram[0x0000] = 0x00
        memory.ram[0x0001] = 0x00

        XCTAssertEqual(memory.read(0x0000), 0x2F)
        XCTAssertEqual(memory.read(0x0001), 0x37)
        XCTAssertEqual(memory.ram[0x0000], 0x00)
        XCTAssertEqual(memory.ram[0x0001], 0x00)
    }

    func testVICSeesUnderlyingRAMAtCPUInternalPortAddresses() {
        let memory = MemoryMap()
        memory.ram[0x0000] = 0xAA
        memory.ram[0x0001] = 0xBB

        memory.write(0x0000, value: 0x12)
        memory.write(0x0001, value: 0x23)

        XCTAssertEqual(memory.read(0x0000), 0x12)
        XCTAssertEqual(memory.read(0x0001), 0x27)
        XCTAssertEqual(memory.vicRead(0x0000), 0xAA)
        XCTAssertEqual(memory.vicRead(0x0001), 0xBB)
    }

    func testCPUDataPortReflectsCassetteSenseInputLine() {
        let memory = MemoryMap()
        memory.write(0x0000, value: 0x00)
        memory.write(0x0001, value: 0x00)

        memory.cassetteSenseLineHigh = false

        XCTAssertEqual(memory.read(0x0001), 0x27)

        memory.cassetteSenseLineHigh = true

        XCTAssertEqual(memory.read(0x0001), 0x37)
    }

    func testCPUDataPortOutputDirectionOverridesCassetteSenseInput() {
        let memory = MemoryMap()
        memory.cassetteSenseLineHigh = false

        memory.write(0x0000, value: 0x10)
        memory.write(0x0001, value: 0x10)

        XCTAssertEqual(memory.read(0x0001) & 0x10, 0x10)

        memory.write(0x0001, value: 0x00)

        XCTAssertEqual(memory.read(0x0001) & 0x10, 0x00)
    }

    func testCPUPortSnapshotReportsEffectiveBankingLines() {
        let memory = MemoryMap()

        var snapshot = memory.cpuPortSnapshot
        XCTAssertEqual(snapshot.direction, 0x2F)
        XCTAssertEqual(snapshot.data, 0x37)
        XCTAssertEqual(snapshot.effective, 0x37)
        XCTAssertTrue(snapshot.loram)
        XCTAssertTrue(snapshot.hiram)
        XCTAssertTrue(snapshot.charen)

        memory.write(0x0001, value: 0x30)

        snapshot = memory.cpuPortSnapshot
        XCTAssertEqual(snapshot.data, 0x30)
        XCTAssertEqual(snapshot.effective, 0x30)
        XCTAssertFalse(snapshot.loram)
        XCTAssertFalse(snapshot.hiram)
        XCTAssertFalse(snapshot.charen)
    }

    func testCPUPortWriteObserverReportsAddressValueAndEffectiveSnapshot() {
        let memory = MemoryMap()
        var writes: [(UInt16, UInt8, MemoryMap.CPUPortSnapshot)] = []
        memory.onCPUPortWrite = { address, value, snapshot in
            writes.append((address, value, snapshot))
        }

        memory.write(0x0000, value: 0x2F)
        memory.write(0x0001, value: 0x34)

        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(writes[0].0, 0x0000)
        XCTAssertEqual(writes[0].1, 0x2F)
        XCTAssertEqual(writes[0].2.direction, 0x2F)
        XCTAssertEqual(writes[0].2.data, 0x37)
        XCTAssertEqual(writes[0].2.effective, 0x37)
        XCTAssertEqual(writes[1].0, 0x0001)
        XCTAssertEqual(writes[1].1, 0x34)
        XCTAssertEqual(writes[1].2.direction, 0x2F)
        XCTAssertEqual(writes[1].2.data, 0x34)
        XCTAssertEqual(writes[1].2.effective, 0x34)
        XCTAssertFalse(writes[1].2.loram)
        XCTAssertFalse(writes[1].2.hiram)
        XCTAssertTrue(writes[1].2.charen)
    }

    func testRAMWriteObserverReportsCommittedNormalRAMWritesOnly() {
        let memory = MemoryMap()
        var writes: [(UInt16, UInt8)] = []
        memory.onRAMWrite = { address, value in
            writes.append((address, value))
        }

        memory.write(0x0801, value: 0xAB)
        memory.write(0xD020, value: 0x05)
        memory.write(0xD400, value: 0x11)
        memory.write(0x0001, value: 0x34)
        memory.write(0xD400, value: 0x22)
        memory.write(0xA000, value: 0xCD)

        XCTAssertEqual(writes.map(\.0), [0x0801, 0xD400, 0xA000])
        XCTAssertEqual(writes.map(\.1), [0xAB, 0x22, 0xCD])
        XCTAssertEqual(memory.ram[0x0801], 0xAB)
        XCTAssertEqual(memory.ram[0xD400], 0x22)
        XCTAssertEqual(memory.ram[0xA000], 0xCD)
    }

    func testCPUDataPortExposesCassetteOutputLineLevels() {
        let memory = MemoryMap()
        memory.write(0x0000, value: 0x28)
        memory.write(0x0001, value: 0x28)

        XCTAssertTrue(memory.cassetteWriteLineHigh)
        XCTAssertTrue(memory.cassetteMotorLineHigh)
        XCTAssertFalse(memory.cassetteMotorEnabled)

        memory.write(0x0001, value: 0x00)

        XCTAssertFalse(memory.cassetteWriteLineHigh)
        XCTAssertFalse(memory.cassetteMotorLineHigh)
        XCTAssertTrue(memory.cassetteMotorEnabled)
    }

    func testCPUDataPortNotifiesCassetteOutputLineChanges() {
        let memory = MemoryMap()
        var writeLevels: [Bool] = []
        var motorLevels: [Bool] = []
        memory.onCassetteWriteLineChange = { writeLevels.append($0) }
        memory.onCassetteMotorLineChange = { motorLevels.append($0) }

        memory.write(0x0000, value: 0x28)
        memory.write(0x0001, value: 0x08)
        memory.write(0x0001, value: 0x28)
        memory.write(0x0001, value: 0x28)
        memory.write(0x0001, value: 0x00)

        XCTAssertEqual(writeLevels, [true, false])
        XCTAssertEqual(motorLevels, [false, true, false])
    }

    func testCPUDataDirectionChangesNotifyEffectiveCassetteOutputLevels() {
        let memory = MemoryMap()
        var writeLevels: [Bool] = []
        var motorLevels: [Bool] = []
        memory.onCassetteWriteLineChange = { writeLevels.append($0) }
        memory.onCassetteMotorLineChange = { motorLevels.append($0) }

        memory.write(0x0001, value: 0x08)
        writeLevels.removeAll()
        motorLevels.removeAll()

        memory.write(0x0000, value: 0x00)
        memory.write(0x0000, value: 0x28)

        XCTAssertEqual(writeLevels, [false, true])
        XCTAssertEqual(motorLevels, [true, false])
    }

    func testROMBankingReadsROMsAndWritesRAMUnderneath() {
        let memory = MemoryMap()
        memory.basicROM[0] = 0xBA
        memory.kernalROM[0] = 0xE0
        memory.charROM[0] = 0xC4
        memory.ram[0xA000] = 0x11
        memory.ram[0xD000] = 0x22
        memory.ram[0xE000] = 0x33

        XCTAssertEqual(memory.read(0xA000), 0xBA)
        XCTAssertEqual(memory.read(0xE000), 0xE0)

        memory.write(0xA000, value: 0x44)
        memory.write(0xE000, value: 0x55)

        XCTAssertEqual(memory.ram[0xA000], 0x44)
        XCTAssertEqual(memory.ram[0xE000], 0x55)
        XCTAssertEqual(memory.read(0xA000), 0xBA)
        XCTAssertEqual(memory.read(0xE000), 0xE0)

        memory.write(0x0001, value: 0x33)
        XCTAssertEqual(memory.read(0xD000), 0xC4)

        memory.write(0x0001, value: 0x30)
        XCTAssertEqual(memory.read(0xA000), 0x44)
        XCTAssertEqual(memory.read(0xD000), 0x22)
        XCTAssertEqual(memory.read(0xE000), 0x55)
    }

    func testVICBankSelectionUsesCIA2PortADirectionAndInvertedLowBits() {
        let memory = MemoryMap()
        let cia2 = CIA(isCIA1: false)
        memory.cia2 = cia2

        memory.ram[0x0000] = 0x10
        memory.ram[0x4000] = 0x40
        memory.ram[0x8000] = 0x80
        memory.ram[0xC000] = 0xC0

        XCTAssertEqual(memory.vicRead(0x0000), 0x10)

        cia2.writeRegister(0x00, value: 0x00)
        XCTAssertEqual(memory.vicRead(0x0000), 0x10)

        cia2.writeRegister(0x02, value: 0x03)
        XCTAssertEqual(memory.vicRead(0x0000), 0xC0)

        cia2.writeRegister(0x00, value: 0x02)
        XCTAssertEqual(memory.vicRead(0x0000), 0x40)

        cia2.writeRegister(0x00, value: 0x01)
        XCTAssertEqual(memory.vicRead(0x0000), 0x80)
    }

    func testVICSeesCharacterROMOnlyInCharacterROMWindows() {
        let memory = MemoryMap()
        let cia2 = CIA(isCIA1: false)
        memory.cia2 = cia2
        memory.charROM[0] = 0xC1
        memory.ram[0x1000] = 0x10
        memory.ram[0x2000] = 0x20
        memory.ram[0x8000] = 0x80
        memory.ram[0x9000] = 0x90

        XCTAssertEqual(memory.vicRead(0x1000), 0xC1)
        XCTAssertEqual(memory.vicRead(0x2000), 0x20)

        cia2.writeRegister(0x02, value: 0x03)
        cia2.writeRegister(0x00, value: 0x01)

        XCTAssertEqual(memory.vicRead(0x1000), 0xC1)
        XCTAssertEqual(memory.vicRead(0x0000), 0x80)
    }

    func testUnmappedExpansionAreaReturnsLastCPUReadValue() {
        let memory = MemoryMap()
        memory.ram[0xC000] = 0xA7

        XCTAssertEqual(memory.read(0xC000), 0xA7)
        XCTAssertEqual(memory.read(0xDE00), 0xA7)
        XCTAssertEqual(memory.read(0xDFFF), 0xA7)
    }

    func testUnmappedExpansionAreaReturnsLastCPUWriteValue() {
        let memory = MemoryMap()

        memory.write(0x2000, value: 0x5C)

        XCTAssertEqual(memory.read(0xDF00), 0x5C)
    }

    func testSIDWriteOnlyRegistersReturnOpenBus() {
        let memory = MemoryMap()
        let sid = SID()
        memory.sid = sid
        sid.setPaddle(x: 0x44, y: 0x55)

        memory.ram[0xC000] = 0xA9
        XCTAssertEqual(memory.read(0xC000), 0xA9)

        sid.writeRegister(0x00, value: 0x34)
        XCTAssertEqual(memory.read(0xD400), 0xA9)
        XCTAssertEqual(memory.read(0xD418), 0xA9)
        XCTAssertEqual(memory.read(0xD419), 0x44)
        XCTAssertEqual(memory.read(0xD41A), 0x55)
    }

    func testSIDRegisterWriteObserverReceivesMirroredRegisterAndValue() {
        let memory = MemoryMap()
        let sid = SID()
        memory.sid = sid
        var writes: [(UInt16, UInt8)] = []
        memory.onSIDRegisterWrite = { register, value in
            writes.append((register, value))
        }

        memory.write(0xD420, value: 0x34)
        memory.write(0xD7FF, value: 0x9A)

        XCTAssertEqual(writes.map(\.0), [0x00, 0x1F])
        XCTAssertEqual(writes.map(\.1), [0x34, 0x9A])
        XCTAssertEqual(sid.debugRegisterValue(0x00), 0x34)
    }

    func testBankedOutSIDAddressWriteObserverReceivesMirroredRegisterAndValue() {
        let memory = MemoryMap()
        let sid = SID()
        memory.sid = sid
        var sidWrites: [(UInt16, UInt8)] = []
        var ramWindowWrites: [(UInt16, UInt8)] = []
        memory.onSIDRegisterWrite = { register, value in
            sidWrites.append((register, value))
        }
        memory.onBankedOutSIDAddressWrite = { register, value in
            ramWindowWrites.append((register, value))
        }

        memory.write(0x0001, value: 0x30)
        memory.write(0xD420, value: 0x34)

        XCTAssertTrue(sidWrites.isEmpty)
        XCTAssertEqual(ramWindowWrites.map(\.0), [0x00])
        XCTAssertEqual(ramWindowWrites.map(\.1), [0x34])
        XCTAssertEqual(memory.ram[0xD420], 0x34)
        XCTAssertNotEqual(sid.debugRegisterValue(0x00), 0x34)
    }

    func testC64SIDWriteCountersDistinguishChipAndRAMWindowWrites() {
        let c64 = C64()

        c64.memory.write(0xD418, value: 0x0F)
        c64.memory.write(0x0001, value: 0x30)
        c64.memory.write(0xD418, value: 0x07)

        XCTAssertEqual(c64.sidChipWriteCount, 1)
        XCTAssertEqual(c64.sidRAMWindowWriteCount, 1)
        XCTAssertEqual(c64.sidChipRegisterWriteCounts[0x18], 1)
        XCTAssertEqual(c64.sidRAMWindowRegisterWriteCounts[0x18], 1)
        XCTAssertEqual(c64.sid.debugRegisterValue(0x18), 0x0F)
        XCTAssertEqual(c64.memory.ram[0xD418], 0x07)

        c64.reset()

        XCTAssertEqual(c64.sidChipRegisterWriteCounts.reduce(0, +), 0)
        XCTAssertEqual(c64.sidRAMWindowRegisterWriteCounts.reduce(0, +), 0)
    }

    func testColorRAMReadsLowNibbleWithOpenBusHighNibble() {
        let memory = MemoryMap()
        memory.ram[0xC000] = 0xA3
        memory.write(0xD800, value: 0x5E)

        XCTAssertEqual(memory.colorRAM[0], 0x0E)

        XCTAssertEqual(memory.read(0xC000), 0xA3)
        XCTAssertEqual(memory.read(0xD800), 0xAE)
    }

    func testAbsentVICAndCIAReadsReturnOpenBus() {
        let memory = MemoryMap()
        memory.ram[0xC000] = 0x72

        XCTAssertEqual(memory.read(0xC000), 0x72)

        XCTAssertEqual(memory.read(0xD000), 0x72)
        XCTAssertEqual(memory.read(0xDC00), 0x72)
        XCTAssertEqual(memory.read(0xDD00), 0x72)
    }

    func testIOMirrorsDispatchToUnderlyingChips() {
        let memory = MemoryMap()
        let vic = VIC()
        let sid = SID()
        let cia1 = CIA(isCIA1: true)
        let cia2 = CIA(isCIA1: false)
        memory.vic = vic
        memory.sid = sid
        memory.cia1 = cia1
        memory.cia2 = cia2

        memory.write(0xD040, value: 0x34)
        XCTAssertEqual(vic.debugRegisterValue(0x00), 0x34)
        XCTAssertEqual(memory.read(0xD040), 0x34)

        memory.write(0xD420, value: 0x78)
        XCTAssertEqual(sid.debugRegisterValue(0x00), 0x78)
        XCTAssertEqual(memory.read(0xD420), 0x78)

        sid.setPaddle(x: 0x12, y: 0x34)
        sid.voices[2].control = 0x20
        sid.voices[2].accumulator = 0xAB0000
        sid.voices[2].envelopeLevel = 0x56
        XCTAssertEqual(memory.read(0xD439), 0x12)
        XCTAssertEqual(memory.read(0xD43A), 0x34)
        XCTAssertEqual(memory.read(0xD43B), 0xAB)
        XCTAssertEqual(memory.read(0xD43C), 0x56)

        memory.write(0xDC12, value: 0xFF)
        memory.write(0xDC10, value: 0x56)
        XCTAssertEqual(cia1.debugRegisterValue(0x02), 0xFF)
        XCTAssertEqual(cia1.debugRegisterValue(0x00), 0x56)
        XCTAssertEqual(memory.read(0xDC10), 0x56)

        memory.write(0xDD10, value: 0x9A)
        memory.write(0xDD12, value: 0xFF)
        XCTAssertEqual(cia2.debugRegisterValue(0x00), 0x9A)
        XCTAssertEqual(memory.read(0xDD10), 0x9A)
    }

    func testOpenBusDecaysToHighAfterIdleCycles() {
        let memory = MemoryMap()
        memory.cpuDataBusDecayDelay = 3
        memory.ram[0xC000] = 0x42

        XCTAssertEqual(memory.read(0xC000), 0x42)
        XCTAssertEqual(memory.read(0xDE00), 0x42)

        memory.tickBus(cycles: 2)
        XCTAssertEqual(memory.read(0xDE00), 0x42)

        memory.tickBus(cycles: 3)
        XCTAssertEqual(memory.read(0xDE00), 0xFF)
    }

    func testWritesRefreshDecayingOpenBus() {
        let memory = MemoryMap()
        memory.cpuDataBusDecayDelay = 2

        memory.write(0x2000, value: 0x5C)
        memory.tickBus(cycles: 1)
        memory.write(0x2001, value: 0xA6)
        memory.tickBus(cycles: 1)

        XCTAssertEqual(memory.read(0xDF00), 0xA6)
    }

    func testColorRAMOpenHighNibbleUsesDecayedCPUDataBus() {
        let memory = MemoryMap()
        memory.cpuDataBusDecayDelay = 1
        memory.write(0xD800, value: 0x0E)
        memory.ram[0xC000] = 0xA3

        XCTAssertEqual(memory.read(0xC000), 0xA3)
        XCTAssertEqual(memory.read(0xD800), 0xAE)

        memory.tickBus(cycles: 1)

        XCTAssertEqual(memory.read(0xD800), 0xFE)
    }
}
