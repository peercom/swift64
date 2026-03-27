import Foundation

/// MOS 6569 VIC-II (PAL) video chip emulation.
/// Renders one rasterline at a time. The host calls `tick()` 63 times per rasterline.
public final class VIC {

    // MARK: - Constants (PAL)

    public static let cyclesPerLine = 63
    public static let totalLines = 312
    public static let cyclesPerFrame = cyclesPerLine * totalLines  // 19656

    /// Visible screen area
    public static let screenWidth = 403
    public static let screenHeight = 284

    /// First/last visible rasterline
    public static let firstVisibleLine = 14
    public static let lastVisibleLine = 297

    /// Display window (where text/bitmap appears, relative to rasterline)
    public static let displayTop = 51
    public static let displayBottom = 251
    public static let displayLeft = 24     // in pixels from left edge of visible area
    public static let displayRight = 344

    // MARK: - Registers

    /// Sprite X coordinates (lower 8 bits)
    var spriteX = [UInt16](repeating: 0, count: 8)
    /// Sprite Y coordinates
    var spriteY = [UInt8](repeating: 0, count: 8)
    /// Sprite X MSBs (combined in register $D010)
    var spriteXMSB: UInt8 = 0

    /// Control register 1 ($D011)
    var controlReg1: UInt8 = 0x1B
    /// Control register 2 ($D016)
    var controlReg2: UInt8 = 0xC8

    /// Raster compare value
    var rasterCompare: UInt16 = 0

    /// Memory pointers ($D018)
    var memoryPointers: UInt8 = 0x14

    /// Interrupt register ($D019)
    var interruptRegister: UInt8 = 0
    /// Interrupt enable ($D01A)
    var interruptEnable: UInt8 = 0

    /// Sprite registers
    var spriteEnabled: UInt8 = 0       // $D015
    var spriteMulticolor: UInt8 = 0    // $D01C
    var spriteExpandX: UInt8 = 0       // $D01D
    var spriteExpandY: UInt8 = 0       // $D017
    var spritePriority: UInt8 = 0      // $D01B (0=sprite in front)
    var spriteColors = [UInt8](repeating: 0, count: 8)  // $D027-$D02E
    var spriteMulticolor0: UInt8 = 0   // $D025
    var spriteMulticolor1: UInt8 = 0   // $D026

    /// Sprite-sprite collision ($D01E)
    var spriteSpriteCollision: UInt8 = 0
    /// Sprite-background collision ($D01F)
    var spriteDataCollision: UInt8 = 0

    /// Background colors
    var backgroundColor = [UInt8](repeating: 0, count: 4)  // $D021-$D024
    /// Border color
    var borderColor: UInt8 = 14  // light blue

    // MARK: - Internal state

    /// Current rasterline
    public var rasterLine: UInt16 = 0
    /// Cycle within current rasterline (0-62)
    public var rasterCycle: Int = 0

    /// Whether the VIC is in the display area vertically
    var displayActive: Bool = false
    /// Vertical scroll
    var yScroll: UInt8 { controlReg1 & 0x07 }
    /// Horizontal scroll
    var xScroll: UInt8 { controlReg2 & 0x07 }
    /// 25/24 row mode
    var rows25: Bool { controlReg1 & 0x08 != 0 }
    /// 40/38 column mode
    var cols40: Bool { controlReg2 & 0x08 != 0 }
    /// Display enabled (DEN)
    var displayEnabled: Bool { controlReg1 & 0x10 != 0 }
    /// Bitmap mode
    var bitmapMode: Bool { controlReg1 & 0x20 != 0 }
    /// Extended background mode
    var extendedBGMode: Bool { controlReg1 & 0x40 != 0 }
    /// Multicolor text mode
    var multicolorMode: Bool { controlReg2 & 0x10 != 0 }

    /// Bad line condition
    var badLine: Bool = false

    /// Row counter (RC) — 0 to 7, tracks which line within a char row
    var rowCounter: Int = 0
    /// Video counter (VC) — pointer into screen memory
    var videoCounter: Int = 0
    /// Video counter base (VCBASE)
    var videoCounterBase: Int = 0

    /// Line buffer for character codes (40 chars)
    var lineBuffer = [UInt8](repeating: 0, count: 40)
    /// Line buffer for color data (40 chars)
    var colorBuffer = [UInt8](repeating: 0, count: 40)

    /// Sprite Y expansion flip-flops
    var spriteYExpFF = [Bool](repeating: false, count: 8)
    /// Sprite data counters (MC, 0-63 × 3)
    var spriteMC = [Int](repeating: 0, count: 8)
    /// Sprite display active
    var spriteDisplay = [Bool](repeating: false, count: 8)
    /// Sprite line data (3 bytes × 8 sprites)
    var spriteLineData = [[UInt8]](repeating: [0, 0, 0], count: 8)

    // MARK: - Framebuffer

    /// RGBA framebuffer (width × height × 4 bytes)
    public var framebuffer: [UInt32]
    public var frameReady: Bool = false

    // MARK: - Memory access callback

    /// Read a byte from the VIC's address space (goes through MemoryMap.vicRead)
    public var readMemory: ((UInt16) -> UInt8)?

    /// IRQ callback
    public var onIRQ: ((Bool) -> Void)?

    // MARK: - Init

    public init() {
        framebuffer = [UInt32](repeating: 0, count: VIC.screenWidth * VIC.screenHeight)
    }

    // MARK: - Tick

    /// Advance one cycle. Returns true if this is a bad line (CPU should be stalled).
    @discardableResult
    public func tick() -> Bool {
        var isBadLine = false

        // Check for bad line condition
        if rasterCycle == 0 {
            checkBadLine()
            isBadLine = badLine
        }

        // Render pixels at specific cycles (raster beam)
        if rasterCycle >= 0 && rasterCycle < VIC.cyclesPerLine {
            renderCycle()
        }

        // Sprite data fetch at cycles 58-62 and 0-2
        if rasterCycle >= 55 {
            fetchSpriteData()
        }

        // Advance cycle
        rasterCycle += 1
        if rasterCycle >= VIC.cyclesPerLine {
            endOfLine()
        }

        return isBadLine
    }

    func checkBadLine() {
        // Bad line when rasterline is in display area and lower 3 bits match YSCROLL
        if rasterLine >= UInt16(VIC.displayTop) && rasterLine <= UInt16(VIC.displayBottom) {
            let yMatch = (rasterLine & 0x07) == UInt16(yScroll)
            if yMatch && displayEnabled {
                badLine = true
                rowCounter = 0
            } else {
                badLine = false
            }
        } else {
            badLine = false
        }
    }

    func endOfLine() {
        // Render this rasterline to framebuffer if visible
        if rasterLine >= UInt16(VIC.firstVisibleLine) && rasterLine < UInt16(VIC.lastVisibleLine) {
            renderRasterline()
        }

        // Raster IRQ check
        if rasterLine == rasterCompare {
            interruptRegister |= 0x01  // IRST
            if interruptEnable & 0x01 != 0 {
                interruptRegister |= 0x80
                onIRQ?(true)
            }
        }

        // Advance rasterline
        rasterCycle = 0
        rasterLine += 1

        if rasterLine >= UInt16(VIC.totalLines) {
            rasterLine = 0
            videoCounterBase = 0
            frameReady = true
        }

        // Video counter management
        if rasterLine == UInt16(VIC.displayTop) && displayEnabled {
            displayActive = true
            videoCounterBase = 0
        }
        if rasterLine == UInt16(VIC.displayBottom + 1) {
            displayActive = false
        }
    }

    func renderCycle() {
        // Fetch char data on bad lines during cycles 15-54
        if badLine && rasterCycle >= 15 && rasterCycle < 55 {
            let col = rasterCycle - 15
            if col < 40 {
                fetchCharData(column: col)
            }
        }
    }

    func fetchCharData(column: Int) {
        let screenBase = UInt16((memoryPointers >> 4) & 0x0F) * 0x0400
        let vc = UInt16(videoCounterBase + column)
        let charCode = readMemory?(screenBase + vc) ?? 0
        lineBuffer[column] = charCode

        // Color RAM read (this comes directly from memory map)
        // We'll store it during the fetch
        colorBuffer[column] = 0  // Will be filled by external color read
    }

    // MARK: - Rasterline rendering

    func renderRasterline() {
        let fbY = Int(rasterLine) - VIC.firstVisibleLine
        guard fbY >= 0 && fbY < VIC.screenHeight else { return }

        let borderCol = ColorPalette.rgba[Int(borderColor & 0x0F)]
        let bgCol = ColorPalette.rgba[Int(backgroundColor[0] & 0x0F)]
        let lineOffset = fbY * VIC.screenWidth

        // Determine border limits
        let topBorder: Int = rows25 ? VIC.displayTop : VIC.displayTop + 4
        let bottomBorder: Int = rows25 ? VIC.displayBottom : VIC.displayBottom - 4
        let leftBorder: Int = cols40 ? VIC.displayLeft : VIC.displayLeft + 7
        let rightBorder: Int = cols40 ? VIC.displayRight : VIC.displayRight - 9

        let lineInDisplay = Int(rasterLine) >= topBorder && Int(rasterLine) < bottomBorder
        let displayY = Int(rasterLine) - topBorder

        // Render character/bitmap graphics for this line
        var graphicsLine = [UInt32](repeating: bgCol, count: VIC.screenWidth)

        if lineInDisplay && displayActive && displayEnabled {
            let charRow = displayY / 8
            let pixelRow = displayY % 8

            renderGraphicsLine(&graphicsLine, charRow: charRow, pixelRow: pixelRow,
                              leftBorder: leftBorder, rightBorder: rightBorder)

            // Render sprites
            renderSprites(&graphicsLine, fbY: fbY)
        }

        // Compose final line with borders
        for px in 0..<VIC.screenWidth {
            if !lineInDisplay || px < leftBorder || px >= rightBorder {
                framebuffer[lineOffset + px] = borderCol
            } else {
                framebuffer[lineOffset + px] = graphicsLine[px]
            }
        }

        // Update video counter at end of display line
        if lineInDisplay && displayActive {
            let charRow = displayY / 8
            let pixelRow = displayY % 8
            if pixelRow == 7 {
                videoCounterBase = (charRow + 1) * 40
            }
        }
    }

    func renderGraphicsLine(_ line: inout [UInt32], charRow: Int, pixelRow: Int,
                            leftBorder: Int, rightBorder: Int) {
        let readMem = readMemory ?? { _ in return 0 }

        let screenBase = UInt16((memoryPointers >> 4) & 0x0F) * 0x0400
        let charBase: UInt16
        if bitmapMode {
            charBase = UInt16((memoryPointers >> 3) & 0x01) * 0x2000
        } else {
            charBase = UInt16((memoryPointers >> 1) & 0x07) * 0x0800
        }

        for col in 0..<40 {
            let vc = charRow * 40 + col
            let screenAddr = screenBase + UInt16(vc)
            let charCode = readMem(screenAddr)
            let colorData = readColorRAM?(UInt16(vc)) ?? 0x0E

            let pixelData: UInt8
            if bitmapMode {
                let bitmapAddr = charBase + UInt16(vc) * 8 + UInt16(pixelRow)
                pixelData = readMem(bitmapAddr)
            } else {
                let charAddr = charBase + UInt16(charCode) * 8 + UInt16(pixelRow)
                pixelData = readMem(charAddr)
            }

            let xPos = leftBorder + col * 8 + Int(xScroll)

            if bitmapMode {
                renderBitmapChar(line: &line, xPos: xPos, pixelData: pixelData,
                                screenByte: charCode, colorByte: colorData)
            } else if extendedBGMode {
                renderExtBGChar(line: &line, xPos: xPos, pixelData: pixelData,
                               charCode: charCode, colorByte: colorData)
            } else if multicolorMode && (colorData & 0x08) != 0 {
                renderMulticolorChar(line: &line, xPos: xPos, pixelData: pixelData,
                                    colorByte: colorData)
            } else {
                renderStandardChar(line: &line, xPos: xPos, pixelData: pixelData,
                                  colorByte: colorData)
            }
        }
    }

    /// Standard text mode: 1 bit per pixel
    func renderStandardChar(line: inout [UInt32], xPos: Int, pixelData: UInt8, colorByte: UInt8) {
        let fgColor = ColorPalette.rgba[Int(colorByte & 0x0F)]
        let bgColor = ColorPalette.rgba[Int(backgroundColor[0] & 0x0F)]

        for bit in 0..<8 {
            let px = xPos + bit
            guard px >= 0 && px < VIC.screenWidth else { continue }
            if pixelData & (0x80 >> bit) != 0 {
                line[px] = fgColor
            } else {
                line[px] = bgColor
            }
        }
    }

    /// Multicolor text mode: 2 bits per pixel (double-wide pixels)
    func renderMulticolorChar(line: inout [UInt32], xPos: Int, pixelData: UInt8, colorByte: UInt8) {
        let colors: [UInt32] = [
            ColorPalette.rgba[Int(backgroundColor[0] & 0x0F)],
            ColorPalette.rgba[Int(backgroundColor[1] & 0x0F)],
            ColorPalette.rgba[Int(backgroundColor[2] & 0x0F)],
            ColorPalette.rgba[Int(colorByte & 0x07)],
        ]

        for pair in 0..<4 {
            let bits = (pixelData >> (6 - pair * 2)) & 0x03
            let color = colors[Int(bits)]
            let px0 = xPos + pair * 2
            let px1 = px0 + 1
            if px0 >= 0 && px0 < VIC.screenWidth { line[px0] = color }
            if px1 >= 0 && px1 < VIC.screenWidth { line[px1] = color }
        }
    }

    /// Extended background color mode
    func renderExtBGChar(line: inout [UInt32], xPos: Int, pixelData: UInt8,
                         charCode: UInt8, colorByte: UInt8) {
        let bgIndex = Int(charCode >> 6)
        let fgColor = ColorPalette.rgba[Int(colorByte & 0x0F)]
        let bgColor = ColorPalette.rgba[Int(backgroundColor[bgIndex] & 0x0F)]

        for bit in 0..<8 {
            let px = xPos + bit
            guard px >= 0 && px < VIC.screenWidth else { continue }
            if pixelData & (0x80 >> bit) != 0 {
                line[px] = fgColor
            } else {
                line[px] = bgColor
            }
        }
    }

    /// Bitmap mode rendering
    func renderBitmapChar(line: inout [UInt32], xPos: Int, pixelData: UInt8,
                         screenByte: UInt8, colorByte: UInt8) {
        let fgColor: UInt32
        let bgColor: UInt32

        if multicolorMode {
            let colors: [UInt32] = [
                ColorPalette.rgba[Int(backgroundColor[0] & 0x0F)],
                ColorPalette.rgba[Int(screenByte >> 4)],
                ColorPalette.rgba[Int(screenByte & 0x0F)],
                ColorPalette.rgba[Int(colorByte & 0x0F)],
            ]
            for pair in 0..<4 {
                let bits = (pixelData >> (6 - pair * 2)) & 0x03
                let color = colors[Int(bits)]
                let px0 = xPos + pair * 2
                let px1 = px0 + 1
                if px0 >= 0 && px0 < VIC.screenWidth { line[px0] = color }
                if px1 >= 0 && px1 < VIC.screenWidth { line[px1] = color }
            }
            return
        }

        fgColor = ColorPalette.rgba[Int(screenByte >> 4)]
        bgColor = ColorPalette.rgba[Int(screenByte & 0x0F)]

        for bit in 0..<8 {
            let px = xPos + bit
            guard px >= 0 && px < VIC.screenWidth else { continue }
            if pixelData & (0x80 >> bit) != 0 {
                line[px] = fgColor
            } else {
                line[px] = bgColor
            }
        }
    }

    // MARK: - Sprites

    func fetchSpriteData() {
        guard spriteEnabled != 0 else { return }
        let readMem = readMemory ?? { _ in return 0 }
        let screenBase = UInt16((memoryPointers >> 4) & 0x0F) * 0x0400

        for i in 0..<8 {
            guard spriteEnabled & (1 << i) != 0 else { continue }

            let sy = spriteY[i]
            let height: Int = (spriteExpandY & (1 << i) != 0) ? 42 : 21
            let line = Int(rasterLine)

            if line >= Int(sy) && line < Int(sy) + height {
                let row: Int
                if spriteExpandY & (1 << i) != 0 {
                    row = (line - Int(sy)) / 2
                } else {
                    row = line - Int(sy)
                }

                // Read sprite pointer from screen memory + $03F8
                let ptrAddr = screenBase + 0x03F8 + UInt16(i)
                let spritePtr = UInt16(readMem(ptrAddr)) * 64

                let dataAddr = spritePtr + UInt16(row * 3)
                spriteLineData[i][0] = readMem(dataAddr)
                spriteLineData[i][1] = readMem(dataAddr + 1)
                spriteLineData[i][2] = readMem(dataAddr + 2)
                spriteDisplay[i] = true
            } else {
                spriteDisplay[i] = false
            }
        }
    }

    func renderSprites(_ line: inout [UInt32], fbY: Int) {
        guard spriteEnabled != 0 else { return }

        // Render sprites from back to front (sprite 7 first, 0 last = highest priority)
        for i in stride(from: 7, through: 0, by: -1) {
            guard spriteEnabled & (1 << i) != 0 && spriteDisplay[i] else { continue }

            let sx = Int(spriteX[i])
            let expandX = spriteExpandX & (1 << i) != 0
            let isMulticolor = spriteMulticolor & (1 << i) != 0
            let behindBG = spritePriority & (1 << i) != 0
            let color = ColorPalette.rgba[Int(spriteColors[i] & 0x0F)]

            let data = spriteLineData[i]
            let fullData = UInt32(data[0]) << 16 | UInt32(data[1]) << 8 | UInt32(data[2])

            if isMulticolor {
                let mc0 = ColorPalette.rgba[Int(spriteMulticolor0 & 0x0F)]
                let mc1 = ColorPalette.rgba[Int(spriteMulticolor1 & 0x0F)]

                for bit in 0..<12 {
                    let bits = (fullData >> (22 - bit * 2)) & 0x03
                    guard bits != 0 else { continue }

                    let pixColor: UInt32
                    switch bits {
                    case 1: pixColor = mc0
                    case 2: pixColor = color
                    case 3: pixColor = mc1
                    default: continue
                    }

                    let xWidth = expandX ? 4 : 2
                    for sub in 0..<xWidth {
                        let px = sx + bit * xWidth + sub - VIC.firstVisibleLine + VIC.displayLeft
                        guard px >= 0 && px < VIC.screenWidth else { continue }
                        if !behindBG || line[px] == ColorPalette.rgba[Int(backgroundColor[0] & 0x0F)] {
                            line[px] = pixColor
                        }
                    }
                }
            } else {
                for bit in 0..<24 {
                    guard fullData & (1 << (23 - bit)) != 0 else { continue }
                    let xWidth = expandX ? 2 : 1
                    for sub in 0..<xWidth {
                        let px = sx + bit * xWidth + sub - VIC.firstVisibleLine + VIC.displayLeft
                        guard px >= 0 && px < VIC.screenWidth else { continue }
                        if !behindBG || line[px] == ColorPalette.rgba[Int(backgroundColor[0] & 0x0F)] {
                            line[px] = color
                        }
                    }
                }
            }
        }
    }

    // MARK: - Color RAM callback

    /// Callback to read color RAM (from MemoryMap)
    public var readColorRAM: ((UInt16) -> UInt8)?

    // MARK: - Register access

    public func readRegister(_ reg: UInt16) -> UInt8 {
        switch reg {
        case 0x00...0x0F:
            // Sprite X/Y coordinates
            let sprite = Int(reg) / 2
            if reg & 1 == 0 {
                return UInt8(spriteX[sprite] & 0xFF)
            } else {
                return spriteY[sprite]
            }

        case 0x10: return spriteXMSB
        case 0x11:
            var val = controlReg1 & 0x7F
            if rasterLine > 255 { val |= 0x80 }
            return val
        case 0x12: return UInt8(rasterLine & 0xFF)
        case 0x13...0x14: return 0  // Light pen (not implemented)
        case 0x15: return spriteEnabled
        case 0x16: return controlReg2 | 0xC0
        case 0x17: return spriteExpandY
        case 0x18: return memoryPointers
        case 0x19: return interruptRegister | 0x70
        case 0x1A: return interruptEnable | 0xF0
        case 0x1B: return spritePriority
        case 0x1C: return spriteMulticolor
        case 0x1D: return spriteExpandX
        case 0x1E:
            let val = spriteSpriteCollision
            spriteSpriteCollision = 0
            return val
        case 0x1F:
            let val = spriteDataCollision
            spriteDataCollision = 0
            return val
        case 0x20: return borderColor | 0xF0
        case 0x21: return backgroundColor[0] | 0xF0
        case 0x22: return backgroundColor[1] | 0xF0
        case 0x23: return backgroundColor[2] | 0xF0
        case 0x24: return backgroundColor[3] | 0xF0
        case 0x25: return spriteMulticolor0 | 0xF0
        case 0x26: return spriteMulticolor1 | 0xF0
        case 0x27...0x2E: return spriteColors[Int(reg) - 0x27] | 0xF0
        default: return 0xFF  // Unused registers read as $FF
        }
    }

    public func writeRegister(_ reg: UInt16, value: UInt8) {
        switch reg {
        case 0x00...0x0F:
            let sprite = Int(reg) / 2
            if reg & 1 == 0 {
                spriteX[sprite] = (spriteX[sprite] & 0x100) | UInt16(value)
            } else {
                spriteY[sprite] = value
            }

        case 0x10:
            spriteXMSB = value
            for i in 0..<8 {
                if value & (1 << i) != 0 {
                    spriteX[i] |= 0x100
                } else {
                    spriteX[i] &= 0xFF
                }
            }

        case 0x11:
            controlReg1 = value
            rasterCompare = (rasterCompare & 0x00FF) | (UInt16(value & 0x80) << 1)

        case 0x12:
            rasterCompare = (rasterCompare & 0x100) | UInt16(value)

        case 0x15: spriteEnabled = value
        case 0x16: controlReg2 = value
        case 0x17: spriteExpandY = value
        case 0x18: memoryPointers = value

        case 0x19:
            // Acknowledge interrupts (write 1 to clear)
            interruptRegister &= ~(value & 0x0F)
            if interruptRegister & interruptEnable & 0x0F == 0 {
                interruptRegister &= 0x7F
                onIRQ?(false)
            }

        case 0x1A:
            interruptEnable = value & 0x0F
            // Check if any pending interrupt should now fire
            if interruptRegister & interruptEnable & 0x0F != 0 {
                interruptRegister |= 0x80
                onIRQ?(true)
            }

        case 0x1B: spritePriority = value
        case 0x1C: spriteMulticolor = value
        case 0x1D: spriteExpandX = value
        case 0x20: borderColor = value & 0x0F
        case 0x21: backgroundColor[0] = value & 0x0F
        case 0x22: backgroundColor[1] = value & 0x0F
        case 0x23: backgroundColor[2] = value & 0x0F
        case 0x24: backgroundColor[3] = value & 0x0F
        case 0x25: spriteMulticolor0 = value & 0x0F
        case 0x26: spriteMulticolor1 = value & 0x0F
        case 0x27...0x2E: spriteColors[Int(reg) - 0x27] = value & 0x0F
        default: break
        }
    }
}
