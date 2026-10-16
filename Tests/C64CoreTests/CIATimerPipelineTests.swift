import XCTest
@testable import C64Core

final class CIATimerPipelineTests: XCTestCase {
    // Hardware sequences documented by Wolfgang Lorenz, CIA6526 v2.15:
    // https://ist.uwaterloo.ca/~schepers/MJK/cia6526.html
    func testControlWriteReadbackMatchesFirstFourHardwareCycles() {
        let cases: [(UInt8, UInt8, [UInt16])] = [
            (0x00, 0x01, [8, 8, 7, 6]),
            (0x00, 0x10, [8, 5, 5, 5]),
            (0x00, 0x11, [8, 5, 5, 4]),
            (0x01, 0x11, [7, 5, 5, 4]),
            (0x01, 0x10, [7, 5, 5, 5]),
            (0x01, 0x00, [7, 6, 6, 6])
        ]
        for timer in 0..<2 {
            for (old, new, expected) in cases {
                let cia = CIA(isCIA1: timer == 0)
                let control = UInt16(0x0E + timer)
                cia.writeRegister(control, value: old)
                for _ in 0..<4 { cia.tick() }
                if timer == 0 { cia.timerA = 8; cia.timerALatch = 5 }
                else { cia.timerB = 8; cia.timerBLatch = 5 }
                cia.writeRegister(control, value: new)
                for value in expected {
                    cia.tick()
                    XCTAssertEqual(timer == 0 ? cia.timerA : cia.timerB, value,
                                   "timer \(timer), control \(old)->\(new)")
                }
            }
        }
    }

    func testContinuousCounterReloadsWithoutReadingZeroAndHoldsNextCycle() {
        for timer in 0..<2 {
            let cia = CIA(isCIA1: true)
            cia.writeRegister(UInt16(4 + 2 * timer), value: 2)
            cia.writeRegister(UInt16(5 + 2 * timer), value: 0)
            cia.writeRegister(UInt16(0x0E + timer), value: 1)
            var values: [UInt16] = []
            for _ in 0..<10 {
                cia.tick()
                values.append(timer == 0 ? cia.timerA : cia.timerB)
            }
            XCTAssertEqual(values, [2, 2, 1, 2, 2, 1, 2, 2, 1, 2])
        }
    }

    func testCascadedCountersPinsAndInterruptMatchHardwareTable() {
        let cia = CIA(isCIA1: false)
        for low: UInt16 in [4, 6] {
            cia.writeRegister(low, value: 2)
            cia.writeRegister(low + 1, value: 0)
        }
        cia.writeRegister(0x0D, value: 0x82)
        cia.writeRegister(0x0F, value: 0x47)
        cia.writeRegister(0x0E, value: 0x03)
        cia.tick()
        cia.tick()
        let a: [UInt16] = [1, 2, 2, 1, 2, 2, 1, 2, 2, 1, 2, 2]
        let b: [UInt16] = [2, 2, 2, 1, 1, 1, 0, 0, 2, 2, 2, 2]
        let pins: [UInt8] = [0x80, 0xC0, 0x80, 0x80, 0xC0, 0x80, 0x80, 0xC0, 0, 0, 0x40, 0]
        let icr: [UInt8] = [0, 1, 1, 1, 1, 1, 1, 1, 3, 0x83, 0x83, 0x83]
        for cycle in a.indices {
            cia.tick()
            XCTAssertEqual(cia.timerA, a[cycle], "cycle \(cycle)")
            XCTAssertEqual(cia.timerB, b[cycle], "cycle \(cycle)")
            XCTAssertEqual(cia.portBOut & 0xC0, pins[cycle], "cycle \(cycle)")
            XCTAssertEqual(cia.debugRegisterValue(0x0D), icr[cycle], "cycle \(cycle)")
        }
    }

    func testUnderflowReadCancelsPendingIRQButMaskClearCannotClearAssertedIRQ() {
        for cancel in [false, true] {
            let cia = CIA(isCIA1: true)
            cia.writeRegister(4, value: 2)
            cia.writeRegister(5, value: 0)
            cia.writeRegister(0x0D, value: 0x81)
            cia.writeRegister(0x0E, value: 9)
            for _ in 0..<4 { cia.tick() }
            XCTAssertEqual(cia.timerAControl & 1, 0)
            XCTAssertEqual(cia.debugRegisterValue(0x0D), 1)
            XCTAssertFalse(cia.interruptActive)
            if cancel { XCTAssertEqual(cia.readRegister(0x0D), 1) }
            cia.tick()
            XCTAssertEqual(cia.interruptActive, !cancel)
            if !cancel {
                cia.writeRegister(0x0D, value: 1)
                XCTAssertTrue(cia.interruptActive)
                XCTAssertEqual(cia.readRegister(0x0D), 0x81)
                XCTAssertFalse(cia.interruptActive)
            }
        }
    }

    func testCPUStoreThenCounterReadObservesDelayedStartAndForceLoad() {
        for profile: MachineProfile in [.palC64, .ntscC64] {
            for control: UInt8 in [1, 0x11] {
                let c64 = C64(machineProfile: profile)
                c64.trueDriveEmulationMode = .off
                c64.kernalTraps.enabled = false
                c64.cia1.writeRegister(4, value: 0x40)
                c64.cia1.writeRegister(5, value: 0)
                c64.cpu.pc = 0x0600
                c64.cpu.a = control
                for (offset, byte) in [UInt8(0x8D), 0x0E, 0xDC, 0xAD, 0x04, 0xDC].enumerated() {
                    c64.memory.ram[0x0600 + offset] = byte
                }
                for _ in 0..<8 { c64.tickOneCycle() }
                XCTAssertEqual(c64.cpu.pc, 0x0606)
                XCTAssertEqual(c64.cpu.a, control == 1 ? 0x3E : 0x3F)
                XCTAssertFalse(c64.cpu.jammed)
            }
        }
    }

    func testCNTEdgesAndSourceSwitchesCrossTheInputPipeline() {
        for timer in 0..<2 {
            let cia = CIA(isCIA1: true)
            let control = UInt16(0x0E + timer)
            cia.writeRegister(UInt16(4 + 2 * timer), value: 10)
            cia.writeRegister(UInt16(5 + 2 * timer), value: 0)
            cia.writeRegister(control, value: 0x21)
            cia.pulseCNT()
            var values: [UInt16] = []
            for _ in 0..<5 {
                cia.tick()
                values.append(timer == 0 ? cia.timerA : cia.timerB)
            }
            XCTAssertEqual(values, [10, 10, 10, 9, 9])
            cia.writeRegister(control, value: 1)
            values = []
            for _ in 0..<4 {
                cia.tick()
                values.append(timer == 0 ? cia.timerA : cia.timerB)
            }
            XCTAssertEqual(values, [9, 9, 8, 7])
            cia.writeRegister(control, value: 0x21)
            values = []
            for _ in 0..<4 {
                cia.tick()
                values.append(timer == 0 ? cia.timerA : cia.timerB)
            }
            XCTAssertEqual(values, [6, 5, 5, 5])
        }
    }

    func testResetDiscardsPendingTimerClocksLoadsAndInterrupts() {
        for clocksBeforeReset in 0..<6 {
            let cia = CIA(isCIA1: false)
            for low: UInt16 in [4, 6] {
                cia.writeRegister(low, value: 1)
                cia.writeRegister(low + 1, value: 0)
            }
            cia.writeRegister(0x0D, value: 0x83)
            cia.writeRegister(0x0E, value: 0x11)
            cia.writeRegister(0x0F, value: 0x11)
            cia.pulseCNT()
            for _ in 0..<clocksBeforeReset { cia.tick() }
            cia.reset()
            for _ in 0..<8 { cia.tick() }
            XCTAssertEqual(cia.timerA, 0xFFFF)
            XCTAssertEqual(cia.timerB, 0xFFFF)
            XCTAssertEqual(cia.interruptData, 0)
            XCTAssertFalse(cia.interruptActive)
        }
    }
}
