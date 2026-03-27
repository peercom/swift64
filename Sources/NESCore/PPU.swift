import Foundation

/// NES PPU (2C02) — scanline-based rendering.
public final class PPU {

    // MARK: - Constants

    public static let screenWidth = 256
    public static let screenHeight = 240

    static let scanlinesPerFrame = 262
    static let dotsPerScanline = 341

    // MARK: - Framebuffer

    /// RGBA8 framebuffer (256 × 240 × 4 bytes)
    public var framebuffer = [UInt8](repeating: 0, count: screenWidth * screenHeight * 4)
    public var frameReady = false

    // MARK: - VRAM

    /// 2KB nametable RAM (can be mirrored various ways)
    var nametableRAM = [UInt8](repeating: 0, count: 2048)

    /// Palette RAM (32 bytes)
    var paletteRAM = [UInt8](repeating: 0, count: 32)

    /// OAM (256 bytes = 64 sprites × 4 bytes)
    var oam = [UInt8](repeating: 0, count: 256)

    /// Secondary OAM for current scanline evaluation
    var secondaryOAM = [UInt8](repeating: 0xFF, count: 32)

    // MARK: - Registers

    /// $2000 PPUCTRL
    var ctrl: UInt8 = 0
    /// $2001 PPUMASK
    var mask: UInt8 = 0
    /// $2002 PPUSTATUS
    var status: UInt8 = 0
    /// $2003 OAMADDR
    var oamAddr: UInt8 = 0

    // MARK: - Internal PPU registers (loopy)

    /// Current VRAM address (15 bits)
    var v: UInt16 = 0
    /// Temporary VRAM address (15 bits)
    var t: UInt16 = 0
    /// Fine X scroll (3 bits)
    var fineX: UInt8 = 0
    /// Write toggle (for $2005/$2006)
    var w: Bool = false

    /// Data buffer for $2007 reads
    var dataBuffer: UInt8 = 0

    // MARK: - Rendering state

    var scanline: Int = 0
    var dot: Int = 0
    var oddFrame: Bool = false

    /// NMI output line
    public var nmiOutput: Bool = false
    var nmiOccurred: Bool = false
    var nmiPrevious: Bool = false

    // MARK: - Sprite 0 hit

    var sprite0OnLine: Bool = false

    // MARK: - External references

    /// Read CHR data through the mapper
    public var readCHR: ((UInt16) -> UInt8)?
    public var writeCHR: ((UInt16, UInt8) -> Void)?

    /// Mirror mode (set from cartridge)
    public var mirrorMode: Cartridge.MirrorMode = .horizontal

    // MARK: - Init

    public init() {}

    // MARK: - Register access (from CPU side)

    public func readRegister(_ reg: UInt16) -> UInt8 {
        switch reg & 7 {
        case 2: // PPUSTATUS
            var result = status & 0xE0
            result |= dataBuffer & 0x1F  // noise bits from data bus
            if nmiOccurred { result |= 0x80 }
            nmiOccurred = false
            updateNMI()
            w = false
            return result

        case 4: // OAMDATA
            return oam[Int(oamAddr)]

        case 7: // PPUDATA
            var data = dataBuffer
            let addr = v & 0x3FFF
            dataBuffer = ppuRead(addr)
            if addr >= 0x3F00 {
                // Palette reads are not buffered
                data = ppuRead(addr)
                dataBuffer = ppuRead(addr &- 0x1000) // buffer gets nametable "underneath"
            }
            v &+= (ctrl & 0x04) != 0 ? 32 : 1
            return data

        default:
            return 0
        }
    }

    public func writeRegister(_ reg: UInt16, value: UInt8) {
        switch reg & 7 {
        case 0: // PPUCTRL
            ctrl = value
            // t: ...GH.. ........ = d: ......GH
            t = (t & 0xF3FF) | (UInt16(value & 0x03) << 10)
            updateNMI()

        case 1: // PPUMASK
            mask = value

        case 3: // OAMADDR
            oamAddr = value

        case 4: // OAMDATA
            oam[Int(oamAddr)] = value
            oamAddr &+= 1

        case 5: // PPUSCROLL
            if !w {
                // First write: X scroll
                t = (t & 0xFFE0) | (UInt16(value) >> 3)
                fineX = value & 0x07
            } else {
                // Second write: Y scroll
                t = (t & 0x8C1F) | (UInt16(value & 0x07) << 12) |
                    (UInt16(value & 0xF8) << 2)
            }
            w = !w

        case 6: // PPUADDR
            if !w {
                // First write: high byte
                t = (t & 0x00FF) | (UInt16(value & 0x3F) << 8)
            } else {
                // Second write: low byte
                t = (t & 0xFF00) | UInt16(value)
                v = t
            }
            w = !w

        case 7: // PPUDATA
            ppuWrite(v & 0x3FFF, value: value)
            v &+= (ctrl & 0x04) != 0 ? 32 : 1

        default:
            break
        }
    }

    /// OAM DMA: write 256 bytes to OAM
    public func oamDMA(_ data: [UInt8]) {
        for i in 0..<256 {
            oam[Int(oamAddr &+ UInt8(i))] = data[i]
        }
    }

    // MARK: - PPU internal memory access

    func ppuRead(_ address: UInt16) -> UInt8 {
        let addr = address & 0x3FFF
        switch addr {
        case 0x0000...0x1FFF:
            return readCHR?(addr) ?? 0
        case 0x2000...0x3EFF:
            let idx = nametableIndex(addr)
            return nametableRAM[idx]
        case 0x3F00...0x3FFF:
            var palAddr = Int(addr & 0x1F)
            // Mirrors: $3F10/$3F14/$3F18/$3F1C → $3F00/$3F04/$3F08/$3F0C
            if palAddr >= 16 && palAddr & 3 == 0 { palAddr -= 16 }
            return paletteRAM[palAddr]
        default:
            return 0
        }
    }

    func ppuWrite(_ address: UInt16, value: UInt8) {
        let addr = address & 0x3FFF
        switch addr {
        case 0x0000...0x1FFF:
            writeCHR?(addr, value)
        case 0x2000...0x3EFF:
            let idx = nametableIndex(addr)
            nametableRAM[idx] = value
        case 0x3F00...0x3FFF:
            var palAddr = Int(addr & 0x1F)
            if palAddr >= 16 && palAddr & 3 == 0 { palAddr -= 16 }
            paletteRAM[palAddr] = value
        default:
            break
        }
    }

    func nametableIndex(_ address: UInt16) -> Int {
        let addr = Int(address & 0x0FFF)
        switch mirrorMode {
        case .horizontal:
            // A10 from bit 11
            return (addr & 0x03FF) | ((addr & 0x0800) >> 1)
        case .vertical:
            return addr & 0x07FF
        case .fourScreen:
            return addr
        }
    }

    // MARK: - Tick

    /// Advance PPU by one dot (called 3× per CPU cycle).
    public func tick() {
        if scanline < 240 {
            // Visible scanlines
            if dot == 0 {
                // Idle dot
            } else if dot <= 256 {
                // Render pixel
                if dot == 1 { renderScanline() }
            }
        }

        if scanline == 241 && dot == 1 {
            // Enter VBlank
            nmiOccurred = true
            updateNMI()
            frameReady = true
        }

        if scanline == 261 {
            // Pre-render scanline
            if dot == 1 {
                nmiOccurred = false
                status &= ~0x60  // Clear sprite 0 hit and overflow
                updateNMI()
            }
            if dot >= 280 && dot <= 304 && renderingEnabled {
                // Copy vertical bits from t to v
                v = (v & 0x041F) | (t & 0x7BE0)
            }
        }

        // Advance dot/scanline
        dot += 1
        if dot > 340 {
            dot = 0
            scanline += 1
            if scanline > 261 {
                scanline = 0
                oddFrame = !oddFrame
                // Skip dot 0 of scanline 0 on odd frames when rendering
                if oddFrame && renderingEnabled {
                    dot = 1
                }
            }
        }
    }

    var renderingEnabled: Bool {
        mask & 0x18 != 0
    }

    func updateNMI() {
        let nmiActive = nmiOccurred && (ctrl & 0x80 != 0)
        if nmiActive && !nmiPrevious {
            nmiOutput = true
        }
        nmiPrevious = nmiActive
    }

    // MARK: - Scanline renderer

    func renderScanline() {
        let y = scanline
        guard y < PPU.screenHeight else { return }

        var bgPixels = [UInt8](repeating: 0, count: 256)
        var bgOpaque = [Bool](repeating: false, count: 256)

        // Background
        if mask & 0x08 != 0 {
            renderBackground(y: y, pixels: &bgPixels, opaque: &bgOpaque)
        }

        // Sprites
        var spritePixels = [UInt8](repeating: 0, count: 256)
        var spriteOpaque = [Bool](repeating: false, count: 256)
        var spritePriority = [Bool](repeating: false, count: 256) // true = behind BG
        sprite0OnLine = false

        if mask & 0x10 != 0 {
            renderSprites(y: y, pixels: &spritePixels, opaque: &spriteOpaque,
                         priority: &spritePriority)
        }

        // Compose final pixels
        let baseOffset = y * PPU.screenWidth * 4
        for x in 0..<256 {
            // Clipping
            let leftClip = x < 8
            let showBG = (mask & 0x08 != 0) && (!leftClip || mask & 0x02 != 0)
            let showSprite = (mask & 0x10 != 0) && (!leftClip || mask & 0x04 != 0)

            let bg = showBG && bgOpaque[x]
            let spr = showSprite && spriteOpaque[x]

            var colorIndex: UInt8

            if !bg && !spr {
                colorIndex = paletteRAM[0]
            } else if bg && !spr {
                colorIndex = bgPixels[x]
            } else if !bg && spr {
                colorIndex = spritePixels[x]
            } else {
                // Both opaque — sprite 0 hit detection
                if sprite0OnLine && x < 255 {
                    status |= 0x40  // Sprite 0 hit
                }
                colorIndex = spritePriority[x] ? bgPixels[x] : spritePixels[x]
            }

            let rgb = PPU.palette[Int(colorIndex & 0x3F)]
            let offset = baseOffset + x * 4
            framebuffer[offset + 0] = rgb.r
            framebuffer[offset + 1] = rgb.g
            framebuffer[offset + 2] = rgb.b
            framebuffer[offset + 3] = 255
        }
    }

    func renderBackground(y: Int, pixels: inout [UInt8], opaque: inout [Bool]) {
        let patternBase: UInt16 = (ctrl & 0x10) != 0 ? 0x1000 : 0x0000

        // Calculate scroll position
        let scrollY = (Int(v >> 12) & 7) + (Int(v >> 5) & 0x1F) * 8 +
                       (Int(v >> 11) & 1) * 240
        let scrollX = Int(fineX)
        let coarseX = Int(v & 0x1F)
        let nametableX = Int((v >> 10) & 1)

        for tileCol in 0..<33 {
            let col = (coarseX + tileCol) % 64
            let ntX = (nametableX + (coarseX + tileCol) / 32) & 1
            let localCol = col % 32

            let ntBase: UInt16 = 0x2000 + UInt16(ntX) * 0x0400 +
                                 UInt16((v >> 11) & 1) * 0x0800
            let fineY = Int(v >> 12) & 7
            let coarseY = Int((v >> 5) & 0x1F)

            let ntAddr = ntBase + UInt16(coarseY) * 32 + UInt16(localCol)
            let tileIndex = ppuRead(ntAddr)

            // Attribute table
            let attrAddr = ntBase + 0x03C0 + UInt16(coarseY / 4) * 8 + UInt16(localCol / 4)
            let attrByte = ppuRead(attrAddr)
            let attrShift = ((coarseY & 2) << 1) | (localCol & 2)
            let palette = (attrByte >> attrShift) & 0x03

            // Pattern table
            let patAddr = patternBase + UInt16(tileIndex) * 16 + UInt16(fineY)
            let lo = ppuRead(patAddr)
            let hi = ppuRead(patAddr + 8)

            for bit in 0..<8 {
                let px = tileCol * 8 + bit - scrollX
                guard px >= 0 && px < 256 else { continue }

                let shift = 7 - bit
                let colorBit = ((lo >> shift) & 1) | (((hi >> shift) & 1) << 1)
                if colorBit != 0 {
                    let palIndex = UInt16(palette) * 4 + UInt16(colorBit)
                    pixels[px] = paletteRAM[Int(palIndex)]
                    opaque[px] = true
                }
            }
        }
    }

    func renderSprites(y: Int, pixels: inout [UInt8], opaque: inout [Bool],
                       priority: inout [Bool]) {
        let spriteHeight = (ctrl & 0x20) != 0 ? 16 : 8
        let patternBase: UInt16 = (ctrl & 0x08) != 0 ? 0x1000 : 0x0000
        var spriteCount = 0

        // Iterate OAM in reverse so lower-index sprites have priority
        for i in stride(from: 63, through: 0, by: -1) {
            let base = i * 4
            let sprY = Int(oam[base]) + 1
            let tileIndex = oam[base + 1]
            let attr = oam[base + 2]
            let sprX = Int(oam[base + 3])

            guard y >= sprY && y < sprY + spriteHeight else { continue }
            spriteCount += 1
            if spriteCount > 8 { status |= 0x20; break }

            let flipH = (attr & 0x40) != 0
            let flipV = (attr & 0x80) != 0
            let behindBG = (attr & 0x20) != 0
            let palette = attr & 0x03

            var row = y - sprY
            if flipV { row = spriteHeight - 1 - row }

            let patAddr: UInt16
            if spriteHeight == 16 {
                let bank: UInt16 = UInt16(tileIndex & 1) * 0x1000
                let tile = UInt16(tileIndex & 0xFE)
                if row < 8 {
                    patAddr = bank + tile * 16 + UInt16(row)
                } else {
                    patAddr = bank + (tile + 1) * 16 + UInt16(row - 8)
                }
            } else {
                patAddr = patternBase + UInt16(tileIndex) * 16 + UInt16(row)
            }

            let lo = ppuRead(patAddr)
            let hi = ppuRead(patAddr + 8)

            for bit in 0..<8 {
                let px = sprX + bit
                guard px < 256 else { continue }

                let shift = flipH ? bit : (7 - bit)
                let colorBit = ((lo >> shift) & 1) | (((hi >> shift) & 1) << 1)
                guard colorBit != 0 else { continue }

                let palIndex = 0x10 + Int(palette) * 4 + Int(colorBit)
                pixels[px] = paletteRAM[palIndex]
                opaque[px] = true
                priority[px] = behindBG
                if i == 0 { sprite0OnLine = true }
            }
        }
    }

    // MARK: - NES system palette (NTSC)

    struct RGB { let r: UInt8; let g: UInt8; let b: UInt8 }

    static let palette: [RGB] = [
        RGB(r: 84,  g: 84,  b: 84 ), RGB(r: 0,   g: 30,  b: 116), RGB(r: 8,   g: 16,  b: 144), RGB(r: 48,  g: 0,   b: 136),
        RGB(r: 68,  g: 0,   b: 100), RGB(r: 92,  g: 0,   b: 48 ), RGB(r: 84,  g: 4,   b: 0  ), RGB(r: 60,  g: 24,  b: 0  ),
        RGB(r: 32,  g: 42,  b: 0  ), RGB(r: 8,   g: 58,  b: 0  ), RGB(r: 0,   g: 64,  b: 0  ), RGB(r: 0,   g: 60,  b: 0  ),
        RGB(r: 0,   g: 50,  b: 60 ), RGB(r: 0,   g: 0,   b: 0  ), RGB(r: 0,   g: 0,   b: 0  ), RGB(r: 0,   g: 0,   b: 0  ),
        RGB(r: 152, g: 150, b: 152), RGB(r: 8,   g: 76,  b: 196), RGB(r: 48,  g: 50,  b: 236), RGB(r: 92,  g: 30,  b: 228),
        RGB(r: 136, g: 20,  b: 176), RGB(r: 160, g: 20,  b: 100), RGB(r: 152, g: 34,  b: 32 ), RGB(r: 120, g: 60,  b: 0  ),
        RGB(r: 84,  g: 90,  b: 0  ), RGB(r: 40,  g: 114, b: 0  ), RGB(r: 8,   g: 124, b: 0  ), RGB(r: 0,   g: 118, b: 40 ),
        RGB(r: 0,   g: 102, b: 120), RGB(r: 0,   g: 0,   b: 0  ), RGB(r: 0,   g: 0,   b: 0  ), RGB(r: 0,   g: 0,   b: 0  ),
        RGB(r: 236, g: 238, b: 236), RGB(r: 76,  g: 154, b: 236), RGB(r: 120, g: 124, b: 236), RGB(r: 176, g: 98,  b: 236),
        RGB(r: 228, g: 84,  b: 236), RGB(r: 236, g: 88,  b: 180), RGB(r: 236, g: 106, b: 100), RGB(r: 212, g: 136, b: 32 ),
        RGB(r: 160, g: 170, b: 0  ), RGB(r: 116, g: 196, b: 0  ), RGB(r: 76,  g: 208, b: 32 ), RGB(r: 56,  g: 204, b: 108),
        RGB(r: 56,  g: 180, b: 204), RGB(r: 60,  g: 60,  b: 60 ), RGB(r: 0,   g: 0,   b: 0  ), RGB(r: 0,   g: 0,   b: 0  ),
        RGB(r: 236, g: 238, b: 236), RGB(r: 168, g: 204, b: 236), RGB(r: 188, g: 188, b: 236), RGB(r: 212, g: 178, b: 236),
        RGB(r: 236, g: 174, b: 236), RGB(r: 236, g: 174, b: 212), RGB(r: 236, g: 180, b: 176), RGB(r: 228, g: 196, b: 144),
        RGB(r: 204, g: 210, b: 120), RGB(r: 180, g: 222, b: 120), RGB(r: 168, g: 226, b: 144), RGB(r: 152, g: 226, b: 180),
        RGB(r: 160, g: 214, b: 228), RGB(r: 160, g: 162, b: 160), RGB(r: 0,   g: 0,   b: 0  ), RGB(r: 0,   g: 0,   b: 0  ),
    ]
}
