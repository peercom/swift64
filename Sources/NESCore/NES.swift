import Foundation
import Emu6502

/// Complete NES machine emulation.
public final class NES {

    // MARK: - Components

    public let cpu: CPU6502
    public let memory: NESMemoryMap
    public let ppu: PPU
    public let apu: APU
    public let controller1: Controller
    public let controller2: Controller
    public let cartridge: Cartridge

    var mapper: Mapper?

    // MARK: - State

    public var running: Bool = false

    /// Total master clock cycles
    var masterClock: UInt64 = 0

    // MARK: - Init

    public init() {
        memory = NESMemoryMap()
        cpu = CPU6502(bus: memory)
        ppu = PPU()
        apu = APU()
        controller1 = Controller()
        controller2 = Controller()
        cartridge = Cartridge()

        // Wire up
        memory.ppu = ppu
        memory.apu = apu
        memory.controller1 = controller1
        memory.controller2 = controller2
    }

    // MARK: - Cartridge loading

    @discardableResult
    public func loadCartridge(_ url: URL) -> Bool {
        guard cartridge.loadFromFile(url) else { return false }
        insertCartridge()
        return true
    }

    @discardableResult
    public func loadCartridge(_ data: Data) -> Bool {
        guard cartridge.load(data) else { return false }
        insertCartridge()
        return true
    }

    func insertCartridge() {
        let m = createMapper(for: cartridge)
        self.mapper = m
        memory.mapper = m

        ppu.mirrorMode = cartridge.mirrorMode
        ppu.readCHR = { [weak m] addr in m?.ppuRead(addr) ?? 0 }
        ppu.writeCHR = { [weak m] addr, val in m?.ppuWrite(addr, value: val) }

        reset()
    }

    // MARK: - Power / Reset

    public func reset() {
        cpu.reset()
        // Give CPU time to execute reset sequence
        for _ in 0..<8 { cpu.tick() }
        running = true
    }

    public func powerOn() {
        // Clear RAM
        for i in 0..<memory.ram.count {
            memory.ram[i] = 0
        }
        cpu.powerOn()
        running = true
    }

    // MARK: - Execution

    /// Run one complete frame (~29781 CPU cycles, 89342 PPU dots).
    /// Returns true when a frame is ready.
    public func runFrame() -> Bool {
        ppu.frameReady = false

        while !ppu.frameReady {
            tickOneCPUCycle()
        }

        return true
    }

    /// Run a single CPU cycle (= 3 PPU dots).
    func tickOneCPUCycle() {
        // Handle OAM DMA
        if memory.dmaPending {
            performDMA()
            memory.dmaPending = false
        }

        // CPU tick
        cpu.tick()

        // PPU ticks (3 per CPU cycle)
        ppu.tick()
        ppu.tick()
        ppu.tick()

        // APU tick
        apu.tick()

        // NMI from PPU
        if ppu.nmiOutput {
            ppu.nmiOutput = false
            cpu.triggerNMI()
        }

        // IRQ from APU
        cpu.irqLine = apu.irqPending
    }

    func performDMA() {
        let base = UInt16(memory.dmaPage) << 8
        var data = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 {
            data[i] = memory.read(base + UInt16(i))
        }
        ppu.oamDMA(data)
        // DMA takes ~513 CPU cycles; burn them
        for _ in 0..<513 {
            ppu.tick()
            ppu.tick()
            ppu.tick()
            apu.tick()
        }
    }
}
