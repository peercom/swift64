import XCTest
@testable import C64Core

final class VICCollisionPipelineTests: XCTestCase {
    private func seed(_ vic: VIC, x: UInt16) {
        vic.rasterLine = 100
        for sprite in 0..<2 {
            vic.spriteDisplay[sprite] = true
            vic.spriteX[sprite] = x
            vic.seedSpriteRow(sprite, bytes: [0x80, 0, 0])
        }
    }

    func testCPUCollisionReadsSeeDelayedPixelsAndDoNotDiscardPendingOnes() {
        for x in 84...104 {
            let c64 = C64(machineProfile: .palC64)
            c64.trueDriveEmulationMode = .off
            c64.kernalTraps.enabled = false
            seed(c64.vic, x: UInt16(x))
            for _ in 0..<21 { c64.vic.tick() }
            c64.cpu.pc = 0x0600
            c64.memory.ram.replaceSubrange(0x0600..<0x0609, with: [
                0xAD, 0x1E, 0xD0, // Read on zero-based cycle 24.
                0x8D, 0x00, 0x02,
                0xAD, 0x1E, 0xD0  // Read-clear must preserve later pipeline input.
            ])
            for _ in 0..<12 { c64.tickOneCycle() }
            XCTAssertEqual(c64.memory.ram[0x0200], x <= 87 ? 3 : 0, "X=\(x)")
            XCTAssertEqual(c64.cpu.a, x <= 87 ? 0 : 3, "X=\(x)")
        }
    }

    func testCollisionIRQWaitsForTheSamePipelineAsTheRegister() {
        let vic = VIC()
        seed(vic, x: 90)
        vic.writeRegister(0x1A, value: 4)
        for _ in 0..<25 { vic.tick() }
        XCTAssertEqual(vic.spriteSpriteCollision, 0)
        XCTAssertEqual(vic.interruptRegister & 0x84, 0)
        vic.tick()
        XCTAssertEqual(vic.readRegister(0x1E), 3)
        XCTAssertEqual(vic.interruptRegister & 0x84, 0x84)
        vic.writeRegister(0x19, value: 4)
        for _ in 0..<3 { vic.tick() }
        XCTAssertEqual(vic.spriteSpriteCollision, 0)
        XCTAssertEqual(vic.interruptRegister & 0x84, 0)
    }

    func testCollisionPipelineSurvivesRasterlineBoundary() {
        let vic = VIC()
        seed(vic, x: 398)
        vic.rasterCycle = 62
        vic.tick()
        XCTAssertEqual(vic.rasterLine, 101)
        XCTAssertEqual(vic.readRegister(0x1E), 0)
        vic.tick()
        XCTAssertEqual(vic.readRegister(0x1E), 3)
    }

    func testResetDiscardsPendingPixelCollisions() {
        let vic = VIC()
        seed(vic, x: 90)
        for _ in 0..<24 { vic.tick() }
        XCTAssertEqual(vic.readRegister(0x1E), 0)
        vic.reset()
        for _ in 0..<4 { vic.tick() }
        XCTAssertEqual(vic.readRegister(0x1E), 0)
        XCTAssertEqual(vic.interruptRegister & 4, 0)
    }
}
