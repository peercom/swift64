import Foundation

/// MOS 6569 VIC-II (PAL) video chip emulation.
/// Renders one rasterline at a time with PAL or NTSC raster timing.
public final class VIC {

    public var videoStandard: C64VideoStandard = .pal {
        didSet {
            applyVideoStandardTiming()
        }
    }

    // MARK: - Constants (PAL)

    public static let palCyclesPerLine = 63
    public static let palRasterLinesPerFrame = 312
    public static let ntscCyclesPerLine = 65
    public static let ntscRasterLinesPerFrame = 263

    public static let cyclesPerLine = palCyclesPerLine
    public static let totalLines = palRasterLinesPerFrame
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

    /// Raster range where bad lines can occur on PAL VIC-II.
    static let firstBadLine = 0x30
    static let lastBadLine = 0xF7

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
    /// Cycle within current rasterline.
    public var rasterCycle: Int = 0
    /// Active chip-profile cycles per rasterline.
    public private(set) var rasterCyclesPerLine: Int = VIC.palCyclesPerLine
    /// Active chip-profile rasterlines per frame.
    public private(set) var rasterLinesPerFrame: Int = VIC.palRasterLinesPerFrame
    public var activeCyclesPerFrame: Int {
        rasterCyclesPerLine * rasterLinesPerFrame
    }

    /// Records per-cycle VIC bus accesses for diagnostics and unit tests.
    /// Disable this in real-time app playback to avoid hot-path array churn.
    public var recordsBusAccessTraces = true

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
    /// VIC-II invalid ECM combinations render display graphics as black.
    var invalidECMMode: Bool { extendedBGMode && (bitmapMode || multicolorMode) }

    /// Bad line condition
    var badLine: Bool = false
    /// Raster cycle where the current bad-line sequence started.
    var badLineStartCycle: Int?
    /// Whether DEN was observed on raster $30, arming bad lines for this frame.
    var badLineDENLatched: Bool = false
    /// Prevents repeated raster IRQs after multiple compare writes on the same rasterline.
    var rasterIRQTriggeredThisLine: Bool = false
    /// Latched light pen X coordinate ($D013), stored as the upper 8 bits of the 9-bit X counter.
    var lightPenX: UInt8 = 0
    /// Latched light pen Y coordinate ($D014).
    var lightPenY: UInt8 = 0
    /// The VIC-II accepts only one light pen latch event per video frame.
    var lightPenLatchedThisFrame: Bool = false
    /// Vertical border flip-flop. When set, display data is masked by border.
    var verticalBorderActive: Bool = true
    /// Horizontal border flip-flop for the current raster line.
    var horizontalBorderActive: Bool = true

    /// Owner of the VIC-II-visible bus for the current raster cycle.
    public enum BusOwner: Equatable {
        case cpu
        case vicBadLine
        case vicSpriteDMA
    }

    /// VIC-II bus phase for the current raster cycle.
    public enum BusPhase: Equatable {
        case cpu
        case badLineBAWarning
        case badLineCharacterFetch(column: Int)
        case spriteBAWarning(sprite: Int)
        case spriteDMA(sprite: Int)
    }

    /// VIC-II low-phase memory activity. These accesses use the half-cycle
    /// normally available to the VIC and do not by themselves stop the CPU.
    public enum LowPhaseAccess: Equatable {
        case idle
        case refresh(index: Int)
        case displayData(column: Int)
        case spritePointer(sprite: Int)
        case spriteMiddleByte(sprite: Int)
    }

    /// Current cycle's VIC-II bus phase.
    public var busPhase: BusPhase {
        if badLine {
            switch rasterCycle {
            case 12..<15:
                return .badLineBAWarning
            case 15..<55:
                return .badLineCharacterFetch(column: rasterCycle - 15)
            default:
                break
            }
        }

        if let sprite = activeSpriteDMASlot {
            return .spriteDMA(sprite: sprite)
        }
        if let sprite = activeSpriteBAWarningSlot {
            return .spriteBAWarning(sprite: sprite)
        }
        return .cpu
    }

    /// Current cycle's VIC-II low-phase memory access.
    public var lowPhaseAccess: LowPhaseAccess {
        switch rasterCycle {
        case 10..<15:
            return .refresh(index: rasterCycle - 10)
        case 15..<55:
            return .displayData(column: rasterCycle - 15)
        default:
            if let sprite = spritePointerSlotForCurrentCycle() {
                return .spritePointer(sprite: sprite)
            }
            if let sprite = spriteMiddleByteSlotForCurrentCycle(),
               spriteMiddleByteOffset(for: sprite) != nil {
                return .spriteMiddleByte(sprite: sprite)
            }
            return .idle
        }
    }

    /// VIC-II BA line state. A low BA warns the CPU that the VIC will need the bus shortly.
    public var baLineLow: Bool {
        switch busPhase {
        case .badLineBAWarning, .badLineCharacterFetch, .spriteBAWarning, .spriteDMA:
            return true
        case .cpu:
            return false
        }
    }

    /// VIC-II AEC line state. A low AEC means the CPU is no longer allowed to drive the bus.
    public var aecLineLow: Bool {
        switch busPhase {
        case .badLineCharacterFetch, .spriteDMA:
            return true
        case .cpu, .badLineBAWarning, .spriteBAWarning:
            return false
        }
    }

    /// Current cycle's effective bus owner.
    public var busOwner: BusOwner {
        switch busPhase {
        case .badLineCharacterFetch:
            return .vicBadLine
        case .spriteDMA:
            return .vicSpriteDMA
        case .cpu, .badLineBAWarning, .spriteBAWarning:
            return .cpu
        }
    }

    /// True when the VIC is stealing the bus from the CPU for bad-line character fetches.
    var isStealingCPU: Bool {
        aecLineLow
    }

    /// 8-bit DRAM refresh counter used by the VIC low-phase refresh slots.
    var refreshCounter: UInt8 = 0xFF
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
    /// Tracks which bad-line columns have been fetched for the current matrix row.
    var badLineFetchMask: UInt64 = 0
    /// True when lineBuffer/colorBuffer contain a complete fetched matrix row.
    var displayLineBufferValid: Bool = false
    /// VCBASE associated with the completed lineBuffer/colorBuffer row.
    var displayLineBufferBase: Int = 0
    /// Low-phase graphics bytes fetched for the current display line.
    var graphicsBuffer = [UInt8](repeating: 0, count: 40)
    /// Tracks which graphics bytes have been fetched for the current display line.
    var graphicsFetchMask: UInt64 = 0
    /// Matrix base associated with the current graphicsBuffer contents.
    var graphicsBufferBase: Int = 0
    /// Pixel row associated with the current graphicsBuffer contents.
    var graphicsBufferPixelRow: Int = 0
    /// True when graphicsBuffer contains all 40 graphics bytes for its row/pixel row.
    var graphicsBufferValid: Bool = false
    /// Display-mode register state latched alongside each low-phase graphics byte.
    var graphicsBufferControlReg1 = [UInt8](repeating: 0, count: 40)
    var graphicsBufferControlReg2 = [UInt8](repeating: 0, count: 40)
    var graphicsBufferMemoryPointers = [UInt8](repeating: 0, count: 40)
    var graphicsBufferBackgroundColors = [[UInt8]](repeating: [0, 0, 0, 0], count: 40)
    var graphicsBufferScreenBytes = [UInt8](repeating: 0, count: 40)
    var graphicsBufferColorData = [UInt8](repeating: 0, count: 40)

    /// Sprite Y expansion flip-flops
    var spriteYExpFF = [Bool](repeating: false, count: 8)
    /// Sprite data counters (MC, byte offset 0...63 within sprite data)
    var spriteMC = [Int](repeating: 0, count: 8)
    /// Sprite data counter base used by vertical expansion/crunch effects.
    var spriteMCBase = [Int](repeating: 0, count: 8)
    /// MC value after the most recent sprite data fetch.
    var spriteLastFetchedMC = [Int](repeating: 0, count: 8)
    /// Starting MC byte offset used by the most recent sprite data fetch.
    var spriteLastFetchedByteOffset = [Int](repeating: -1, count: 8)
    /// Rasterline for which the sprite expansion state has been initialized.
    var spriteExpansionLine = [Int?](repeating: nil, count: 8)
    /// Sprite display active
    var spriteDisplay = [Bool](repeating: false, count: 8)
    /// Sprite line data (3 bytes × 8 sprites)
    var spriteLineData = [[UInt8]](repeating: [0, 0, 0], count: 8)
    /// Sprite data pointer bytes latched during the low-phase sprite-pointer slots.
    var spritePointers = [UInt8](repeating: 0, count: 8)
    /// Sprite DMA slot that began on the previous line's final cycle and
    /// continues onto cycle 0 of the current line.
    var spriteDMAWrapContinuationSlot: Int?
    /// Rasterline for which sprite DMA enable/Y-match has been sampled.
    var spriteDMACheckLine: Int?
    /// Per-sprite DMA eligibility latched by the cycle 55/56 sprite check.
    var spriteDMACheckMask: UInt8 = 0

    /// Per-visible-pixel raster state captured as the beam advances. This keeps
    /// simple raster color bars and mid-line border mode changes observable even
    /// though the heavier graphics composition still happens at end of line.
    var rasterTraceLine: UInt16?
    var rasterTraceHasSamples: Bool = false
    var rasterTraceHasDisplayOpen: Bool = false
    var rasterTraceValid = [Bool](repeating: false, count: VIC.screenWidth)
    var rasterTraceDisplayOpen = [Bool](repeating: false, count: VIC.screenWidth)
    var rasterTraceBorderColor = [UInt8](repeating: 0, count: VIC.screenWidth)
    var rasterTraceBackgroundColor0 = [UInt8](repeating: 0, count: VIC.screenWidth)
    var rasterTraceBackgroundColor1 = [UInt8](repeating: 0, count: VIC.screenWidth)
    var rasterTraceBackgroundColor2 = [UInt8](repeating: 0, count: VIC.screenWidth)
    var rasterTraceBackgroundColor3 = [UInt8](repeating: 0, count: VIC.screenWidth)
    var spriteTraceLine: UInt16?
    var spriteTraceHasSamples: Bool = false
    var spriteTraceValid = [Bool](repeating: false, count: VIC.screenWidth)
    var spriteTraceColor = [UInt32](repeating: 0, count: VIC.screenWidth)
    var spriteTracePriorityBehindBG = [Bool](repeating: false, count: VIC.screenWidth)
    var spriteTraceDisplayForeground = [Bool](repeating: false, count: VIC.screenWidth)
    var spriteTraceSpriteMask = [UInt8](repeating: 0, count: VIC.screenWidth)

    /// Sprite DMA slots are currently modeled as deterministic two-cycle bursts
    /// per sprite during the VIC-II's sprite-fetch part of the line.
    public var activeSpriteDMASlot: Int? {
        if rasterCycle == 0, let slot = spriteDMAWrapContinuationSlot {
            return slot
        }
        guard let slot = spriteDMASlotForCurrentCycle(),
              spriteDMAEligible(slot, onRasterLine: Int(rasterLine)) else {
            return nil
        }
        return slot
    }

    /// Active sprite whose DMA slot is within the BA warning window.
    public var activeSpriteBAWarningSlot: Int? {
        guard let slot = spriteBAWarningSlotForCurrentCycle(),
              spriteDMAEligible(slot, onRasterLine: spriteBAWarningRasterLine(for: slot)) else {
            return nil
        }
        return slot
    }

    // MARK: - Framebuffer

    /// RGBA framebuffer (width × height × 4 bytes)
    public var framebuffer: [UInt32]
    public var frameReady: Bool = false
    private var graphicsLineScratch = [UInt32](repeating: 0, count: VIC.screenWidth)
    private var foregroundMaskScratch = [Bool](repeating: false, count: VIC.screenWidth)
    private var backgroundColorSourceScratch = [Int8](repeating: -1, count: VIC.screenWidth)
    private var finalLineScratch = [UInt32](repeating: 0, count: VIC.screenWidth)
    private var spriteForegroundMaskScratch = [Bool](repeating: false, count: VIC.screenWidth)

    // MARK: - Memory access callback

    /// Read a byte from the VIC's address space (goes through MemoryMap.vicRead)
    public var readMemory: ((UInt16) -> UInt8)?
    /// VIC memory addresses touched by the most recent high-phase bus access.
    public private(set) var lastHighPhaseMemoryReads: [UInt16] = []
    /// Color RAM addresses touched by the most recent high-phase bus access.
    public private(set) var lastHighPhaseColorRAMReads: [UInt16] = []
    /// VIC memory addresses touched by the most recent low-phase access.
    public private(set) var lastLowPhaseMemoryReads: [UInt16] = []

    /// IRQ callback
    public var onIRQ: ((Bool) -> Void)?

    // MARK: - Init

    public init() {
        framebuffer = [UInt32](repeating: 0, count: VIC.screenWidth * VIC.screenHeight)
    }

    public func reset() {
        spriteX = [UInt16](repeating: 0, count: 8)
        spriteY = [UInt8](repeating: 0, count: 8)
        spriteXMSB = 0
        controlReg1 = 0x1B
        controlReg2 = 0xC8
        rasterCompare = 0
        memoryPointers = 0x14
        let wasIRQActive = interruptRegister & 0x80 != 0
        interruptRegister = 0
        interruptEnable = 0
        spriteEnabled = 0
        spriteMulticolor = 0
        spriteExpandX = 0
        spriteExpandY = 0
        spritePriority = 0
        spriteColors = [UInt8](repeating: 0, count: 8)
        spriteMulticolor0 = 0
        spriteMulticolor1 = 0
        spriteSpriteCollision = 0
        spriteDataCollision = 0
        backgroundColor = [UInt8](repeating: 0, count: 4)
        borderColor = 14

        rasterLine = 0
        rasterCycle = 0
        displayActive = false
        badLine = false
        badLineStartCycle = nil
        badLineDENLatched = false
        rasterIRQTriggeredThisLine = false
        lightPenX = 0
        lightPenY = 0
        lightPenLatchedThisFrame = false
        verticalBorderActive = true
        horizontalBorderActive = true
        refreshCounter = 0xFF
        rowCounter = 0
        videoCounter = 0
        videoCounterBase = 0
        lineBuffer = [UInt8](repeating: 0, count: 40)
        colorBuffer = [UInt8](repeating: 0, count: 40)
        badLineFetchMask = 0
        displayLineBufferValid = false
        displayLineBufferBase = 0
        graphicsBuffer = [UInt8](repeating: 0, count: 40)
        graphicsFetchMask = 0
        graphicsBufferBase = 0
        graphicsBufferPixelRow = 0
        graphicsBufferValid = false
        graphicsBufferControlReg1 = [UInt8](repeating: 0, count: 40)
        graphicsBufferControlReg2 = [UInt8](repeating: 0, count: 40)
        graphicsBufferMemoryPointers = [UInt8](repeating: 0, count: 40)
        graphicsBufferBackgroundColors = [[UInt8]](repeating: [0, 0, 0, 0], count: 40)
        graphicsBufferScreenBytes = [UInt8](repeating: 0, count: 40)
        graphicsBufferColorData = [UInt8](repeating: 0, count: 40)
        spriteYExpFF = [Bool](repeating: false, count: 8)
        spriteMC = [Int](repeating: 0, count: 8)
        spriteMCBase = [Int](repeating: 0, count: 8)
        spriteLastFetchedMC = [Int](repeating: 0, count: 8)
        spriteLastFetchedByteOffset = [Int](repeating: -1, count: 8)
        spriteExpansionLine = [Int?](repeating: nil, count: 8)
        spriteDisplay = [Bool](repeating: false, count: 8)
        spriteLineData = [[UInt8]](repeating: [0, 0, 0], count: 8)
        spritePointers = [UInt8](repeating: 0, count: 8)
        spriteDMAWrapContinuationSlot = nil
        spriteDMACheckLine = nil
        spriteDMACheckMask = 0
        lastHighPhaseMemoryReads = []
        lastHighPhaseColorRAMReads = []
        lastLowPhaseMemoryReads = []
        clearRasterTrace()
        frameReady = false

        if wasIRQActive {
            onIRQ?(false)
        }
    }

    func applyVideoStandardTiming() {
        switch videoStandard {
        case .pal:
            rasterCyclesPerLine = VIC.palCyclesPerLine
            rasterLinesPerFrame = VIC.palRasterLinesPerFrame
        case .ntsc:
            rasterCyclesPerLine = VIC.ntscCyclesPerLine
            rasterLinesPerFrame = VIC.ntscRasterLinesPerFrame
        }
    }

    // MARK: - Tick

    /// Advance one cycle. Returns true if this is a bad line (CPU should be stalled).
    @discardableResult
    public func tick() -> Bool {
        if recordsBusAccessTraces {
            lastHighPhaseMemoryReads.removeAll(keepingCapacity: true)
            lastHighPhaseColorRAMReads.removeAll(keepingCapacity: true)
        }

        // Check for bad line condition
        if rasterCycle == 0 {
            checkBadLine()
            updateVerticalBorderFlipFlop()
            horizontalBorderActive = true
            updateSpriteExpansionStateForCurrentLine()
        }

        let shouldStallCPU = isStealingCPU

        if rasterCycle == 55 || rasterCycle == 56 {
            latchSpriteDMAEligibilityForCurrentLine()
        }
        if rasterCycle == 58 {
            latchSpriteDisplayForCurrentLine()
        }

        captureRasterTraceForCurrentCycle()
        performLowPhaseAccess()

        // Render pixels at specific cycles (raster beam)
        if rasterCycle >= 0 && rasterCycle < rasterCyclesPerLine {
            renderCycle()
        }

        // Sprite data fetch in deterministic per-sprite DMA slots.
        if let sprite = spriteDMAFetchSlotForCurrentCycle() {
            fetchSpriteData(sprite: sprite)
        }

        let wrapContinuation: Int?
        if rasterCycle == rasterCyclesPerLine - 1,
           let slot = spriteDMAFetchSlotForCurrentCycle(),
           activeSpriteDMASlot == slot {
            wrapContinuation = slot
        } else {
            wrapContinuation = nil
        }

        // Advance cycle
        rasterCycle += 1
        if rasterCycle >= rasterCyclesPerLine {
            spriteDMAWrapContinuationSlot = wrapContinuation
            endOfLine()
        } else if rasterCycle != 0 {
            spriteDMAWrapContinuationSlot = nil
        }

        return shouldStallCPU
    }

    func checkBadLine() {
        if rasterLine == UInt16(VIC.firstBadLine) && displayEnabled {
            badLineDENLatched = true
        }

        let wasBadLine = badLine

        // Bad line when rasterline is in the VIC-II bad-line range and lower 3 bits match YSCROLL.
        if rasterLine >= UInt16(VIC.firstBadLine) && rasterLine <= UInt16(VIC.lastBadLine) {
            let yMatch = (rasterLine & 0x07) == UInt16(yScroll)
            let canStartBadLine = wasBadLine || rasterCycle < 55
            if yMatch && badLineDENLatched && canStartBadLine {
                badLine = true
                if !wasBadLine {
                    badLineStartCycle = rasterCycle
                    rowCounter = 0
                }
            } else {
                badLine = false
                badLineStartCycle = nil
            }
        } else {
            badLine = false
            badLineStartCycle = nil
        }

        if badLine && !wasBadLine {
            badLineFetchMask = 0
            displayLineBufferValid = false
            displayLineBufferBase = videoCounterBase
        }
    }

    func endOfLine() {
        // Render this rasterline to framebuffer if visible
        if rasterLine >= UInt16(VIC.firstVisibleLine) && rasterLine <= UInt16(VIC.lastVisibleLine) {
            renderRasterline()
        }

        // Advance rasterline
        rasterCycle = 0
        rasterLine += 1

        if rasterLine >= UInt16(rasterLinesPerFrame) {
            rasterLine = 0
            refreshCounter = 0xFF
            videoCounterBase = 0
            badLineDENLatched = false
            lightPenLatchedThisFrame = false
            verticalBorderActive = true
            frameReady = true
        }
        clearRasterTrace()
        rasterIRQTriggeredThisLine = false
        spriteDMACheckLine = nil
        spriteDMACheckMask = 0
        checkRasterInterrupt()

        // Video counter management
        if rasterLine == UInt16(VIC.displayTop) && displayEnabled {
            displayActive = true
            videoCounterBase = 0
        }
        if rasterLine == UInt16(VIC.displayBottom + 1) && verticalBorderActive {
            displayActive = false
        }
    }

    func updateVerticalBorderFlipFlop() {
        let line = Int(rasterLine)
        let topBorder: Int = rows25 ? VIC.displayTop : VIC.displayTop + 4
        let bottomBorder: Int = rows25 ? VIC.displayBottom : VIC.displayBottom - 4

        if line == topBorder {
            verticalBorderActive = false
        }
        if line == bottomBorder {
            verticalBorderActive = true
        }
    }

    func clearRasterTrace() {
        if !rasterTraceHasSamples && !spriteTraceHasSamples {
            rasterTraceLine = nil
            rasterTraceHasDisplayOpen = false
            spriteTraceLine = nil
            return
        }
        rasterTraceLine = nil
        rasterTraceHasSamples = false
        rasterTraceHasDisplayOpen = false
        spriteTraceLine = nil
        spriteTraceHasSamples = false
        for index in 0..<VIC.screenWidth {
            rasterTraceValid[index] = false
            rasterTraceDisplayOpen[index] = false
            rasterTraceBorderColor[index] = 0
            rasterTraceBackgroundColor0[index] = 0
            rasterTraceBackgroundColor1[index] = 0
            rasterTraceBackgroundColor2[index] = 0
            rasterTraceBackgroundColor3[index] = 0
            spriteTraceValid[index] = false
            spriteTraceColor[index] = 0
            spriteTracePriorityBehindBG[index] = false
            spriteTraceDisplayForeground[index] = false
            spriteTraceSpriteMask[index] = 0
        }
    }

    func prepareRasterTraceForCurrentLine() {
        if rasterTraceLine == rasterLine {
            return
        }

        rasterTraceLine = rasterLine
        rasterTraceHasSamples = false
        rasterTraceHasDisplayOpen = false
        spriteTraceLine = rasterLine
        spriteTraceHasSamples = false
        for index in 0..<VIC.screenWidth {
            rasterTraceValid[index] = false
            rasterTraceDisplayOpen[index] = false
            spriteTraceValid[index] = false
            spriteTraceDisplayForeground[index] = false
            spriteTraceSpriteMask[index] = 0
        }
    }

    func captureRasterTraceForCurrentCycle() {
        guard rasterLine >= UInt16(VIC.firstVisibleLine),
              rasterLine <= UInt16(VIC.lastVisibleLine),
              rasterCycle >= 0,
              rasterCycle < rasterCyclesPerLine else {
            return
        }

        prepareRasterTraceForCurrentLine()

        let startPixel = max(0, min(VIC.screenWidth, rasterCycle * VIC.screenWidth / rasterCyclesPerLine))
        let rawEndPixel = (rasterCycle + 1) * VIC.screenWidth / rasterCyclesPerLine
        let endPixel = max(startPixel + 1, min(VIC.screenWidth, rawEndPixel))
        guard startPixel < endPixel else { return }

        let leftBorder: Int = cols40 ? VIC.displayLeft : VIC.displayLeft + 7
        let rightBorder: Int = cols40 ? VIC.displayRight : VIC.displayRight - 9

        for pixel in startPixel..<endPixel {
            if pixel == leftBorder {
                horizontalBorderActive = false
            }
            if pixel == rightBorder {
                horizontalBorderActive = true
            }

            let displayOpen = displayActive && displayEnabled && !verticalBorderActive && !horizontalBorderActive
            rasterTraceValid[pixel] = true
            rasterTraceDisplayOpen[pixel] = displayOpen
            rasterTraceBorderColor[pixel] = borderColor & 0x0F
            rasterTraceBackgroundColor0[pixel] = backgroundColor[0] & 0x0F
            rasterTraceBackgroundColor1[pixel] = backgroundColor[1] & 0x0F
            rasterTraceBackgroundColor2[pixel] = backgroundColor[2] & 0x0F
            rasterTraceBackgroundColor3[pixel] = backgroundColor[3] & 0x0F
            if displayOpen {
                rasterTraceHasDisplayOpen = true
            }
        }
        rasterTraceHasSamples = true
        captureSpriteTrace(startPixel: startPixel, endPixel: endPixel)
    }

    func captureSpriteTrace(startPixel: Int, endPixel: Int) {
        guard spriteDisplay.contains(true) else { return }
        guard spriteTraceLine == rasterLine else { return }

        for sprite in stride(from: 7, through: 0, by: -1) {
            guard spriteDisplay[sprite] else { continue }

            let spriteMask = UInt8(1 << sprite)
            guard spriteEnabled & spriteMask != 0 else { continue }
            let behindBG = spritePriority & spriteMask != 0
            for x in startPixel..<endPixel {
                guard let color = spritePixelColor(sprite: sprite, x: x) else { continue }
                let hasForeground = displayForegroundAtTracePixel(x)

                if spriteTraceSpriteMask[x] != 0 && spriteTraceSpriteMask[x] & spriteMask == 0 {
                    spriteSpriteCollision |= spriteTraceSpriteMask[x] | spriteMask
                    raiseInterrupt(0x04)
                }
                if hasForeground {
                    spriteDataCollision |= spriteMask
                    raiseInterrupt(0x02)
                }
                spriteTraceSpriteMask[x] |= spriteMask
                if !hasForeground || !behindBG || !spriteTraceValid[x] {
                    spriteTraceValid[x] = true
                    spriteTraceColor[x] = color
                    spriteTracePriorityBehindBG[x] = behindBG
                    spriteTraceDisplayForeground[x] = hasForeground
                }
                spriteTraceHasSamples = true
            }
        }
    }

    func spritePixelColor(sprite: Int, x: Int) -> UInt32? {
        guard let localX = spriteLocalX(sprite: sprite, visibleX: x) else { return nil }

        let expandX = spriteExpandX & (1 << sprite) != 0
        let isMulticolor = spriteMulticolor & (1 << sprite) != 0
        let data = spriteLineData[sprite]
        let fullData = UInt32(data[0]) << 16 | UInt32(data[1]) << 8 | UInt32(data[2])

        if isMulticolor {
            let pixelWidth = expandX ? 4 : 2
            let pair = localX / pixelWidth
            guard pair >= 0 && pair < 12 else { return nil }

            let bits = (fullData >> (22 - pair * 2)) & 0x03
            switch bits {
            case 1: return ColorPalette.rgba[Int(spriteMulticolor0 & 0x0F)]
            case 2: return ColorPalette.rgba[Int(spriteColors[sprite] & 0x0F)]
            case 3: return ColorPalette.rgba[Int(spriteMulticolor1 & 0x0F)]
            default: return nil
            }
        }

        let pixelWidth = expandX ? 2 : 1
        let bit = localX / pixelWidth
        guard bit >= 0 && bit < 24 else { return nil }
        guard fullData & (1 << (23 - bit)) != 0 else { return nil }
        return ColorPalette.rgba[Int(spriteColors[sprite] & 0x0F)]
    }

    func spriteLocalX(sprite: Int, visibleX x: Int) -> Int? {
        let sx = Int(spriteX[sprite] & 0x01FF)
        var localX = x - sx
        if localX < 0 {
            localX += 512
        }
        let width = spriteExpandX & (1 << sprite) != 0 ? 48 : 24
        return localX >= 0 && localX < width ? localX : nil
    }

    func displayForegroundAtTracePixel(_ x: Int) -> Bool {
        guard x >= 0 && x < VIC.screenWidth else { return false }
        guard rasterTraceLine == rasterLine,
              rasterTraceValid[x],
              rasterTraceDisplayOpen[x] else {
            return false
        }
        guard let context = currentDisplayFetchContext() else { return false }

        let rowBase = context.rowBase

        for column in 0..<40 {
            let columnMask = UInt64(1) << UInt64(column)
            let useFetchedGraphics = graphicsBufferBase == rowBase
                && graphicsBufferPixelRow == context.pixelRow
                && (graphicsFetchMask & columnMask) != 0
            let columnControlReg2 = useFetchedGraphics ? graphicsBufferControlReg2[column] : controlReg2
            let columnX = VIC.displayLeft + column * 8 + Int(columnControlReg2 & 0x07)
            guard x >= columnX && x < columnX + 8 else { continue }

            return displayForegroundAtTraceColumn(
                column,
                bitOffset: x - columnX,
                context: context,
                useFetchedGraphics: useFetchedGraphics
            )
        }

        return false
    }

    func displayForegroundAtTraceColumn(_ column: Int,
                                        bitOffset: Int,
                                        context: (charRow: Int, rowBase: Int, pixelRow: Int),
                                        useFetchedGraphics: Bool) -> Bool {
        let rowBase = context.rowBase

        let columnControlReg1 = useFetchedGraphics ? graphicsBufferControlReg1[column] : controlReg1
        let columnControlReg2 = useFetchedGraphics ? graphicsBufferControlReg2[column] : controlReg2
        let columnMemoryPointers = useFetchedGraphics ? graphicsBufferMemoryPointers[column] : memoryPointers
        let columnBitmapMode = columnControlReg1 & 0x20 != 0
        let columnExtendedBGMode = columnControlReg1 & 0x40 != 0
        let columnMulticolorMode = columnControlReg2 & 0x10 != 0

        let readMem = readMemory ?? { _ in return 0 }
        let vc = rowBase + column
        let screenBase = UInt16((columnMemoryPointers >> 4) & 0x0F) * 0x0400
        let charCode: UInt8
        let colorData: UInt8
        if useFetchedGraphics {
            charCode = graphicsBufferScreenBytes[column]
            colorData = graphicsBufferColorData[column]
        } else if hasLatchedMatrixColumn(column, rowBase: rowBase) {
            charCode = lineBuffer[column]
            colorData = colorBuffer[column]
        } else {
            charCode = readMem(screenBase + UInt16(vc))
            colorData = (readColorRAM?(UInt16(vc)) ?? 0x0E) & 0x0F
        }

        let pixelData: UInt8
        if useFetchedGraphics {
            pixelData = graphicsBuffer[column]
        } else {
            let charBase: UInt16
            if columnBitmapMode {
                charBase = UInt16((columnMemoryPointers >> 3) & 0x01) * 0x2000
            } else {
                charBase = UInt16((columnMemoryPointers >> 1) & 0x07) * 0x0800
            }

            if columnBitmapMode {
                let bitmapAddr = charBase + UInt16(vc) * 8 + UInt16(context.pixelRow)
                pixelData = readMem(bitmapAddr)
            } else {
                let glyphCode = columnExtendedBGMode ? (charCode & 0x3F) : charCode
                let charAddr = charBase + UInt16(glyphCode) * 8 + UInt16(context.pixelRow)
                pixelData = readMem(charAddr)
            }
        }

        if columnBitmapMode {
            if columnMulticolorMode {
                let pair = bitOffset / 2
                let bits = (pixelData >> (6 - pair * 2)) & 0x03
                return bits >= 2
            }
            return pixelData & (0x80 >> bitOffset) != 0
        }

        if columnMulticolorMode && (colorData & 0x08) != 0 {
            let pair = bitOffset / 2
            let bits = (pixelData >> (6 - pair * 2)) & 0x03
            return bits >= 2
        }
        return pixelData & (0x80 >> bitOffset) != 0
    }

    func renderCycle() {
        // Fetch char data on bad lines during cycles 15-54.
        if case let .badLineCharacterFetch(column) = busPhase, column < 40 {
            fetchCharData(column: column)
        }
    }

    func performLowPhaseAccess() {
        if recordsBusAccessTraces {
            lastLowPhaseMemoryReads.removeAll(keepingCapacity: true)
        }
        switch lowPhaseAccess {
        case .idle:
            performIdleAccess(recordTrace: recordsBusAccessTraces)
        case .refresh:
            performRefreshAccess(recordTrace: recordsBusAccessTraces)
        case let .displayData(column):
            fetchDisplayData(column: column, recordTrace: recordsBusAccessTraces)
        case let .spritePointer(sprite):
            guard sprite >= 0 && sprite < 8 else { return }

            let readMem = readMemory ?? { _ in return 0 }
            let screenBase = UInt16((memoryPointers >> 4) & 0x0F) * 0x0400
            let address = screenBase + 0x03F8 + UInt16(sprite)
            if recordsBusAccessTraces {
                lastLowPhaseMemoryReads.append(address)
            }
            spritePointers[sprite] = readMem(address)
        case let .spriteMiddleByte(sprite):
            fetchSpriteMiddleByte(sprite: sprite, recordTrace: recordsBusAccessTraces)
        }
    }

    func performRefreshAccess(recordTrace: Bool) {
        let address = UInt16(0x3F00) | UInt16(refreshCounter)
        if recordTrace {
            lastLowPhaseMemoryReads.append(address)
        }
        _ = readMemory?(address)
        refreshCounter &-= 1
    }

    func performIdleAccess(recordTrace: Bool) {
        let address: UInt16 = extendedBGMode ? 0x39FF : 0x3FFF
        if recordTrace {
            lastLowPhaseMemoryReads.append(address)
        }
        _ = readMemory?(address)
    }

    func raiseInterrupt(_ flag: UInt8) {
        interruptRegister |= flag
        updateIRQLine()
    }

    func checkRasterInterrupt() {
        guard rasterLine == rasterCompare && !rasterIRQTriggeredThisLine else { return }
        rasterIRQTriggeredThisLine = true
        raiseInterrupt(0x01)  // IRST
    }

    func updateIRQLine() {
        let wasActive = interruptRegister & 0x80 != 0
        let isActive = interruptRegister & interruptEnable & 0x0F != 0

        if isActive {
            interruptRegister |= 0x80
            if !wasActive {
                onIRQ?(true)
            }
        } else {
            interruptRegister &= 0x7F
            if wasActive {
                onIRQ?(false)
            }
        }
    }

    /// Latch a light pen edge into LPX/LPY. The VIC-II exposes the upper 8 bits
    /// of its 9-bit horizontal counter, so callers provide a 0...511 beam X.
    public func triggerLightPen(x: Int, y: Int) {
        guard !lightPenLatchedThisFrame else { return }

        let clampedX = max(0, min(511, x))
        lightPenX = UInt8((clampedX >> 1) & 0xFF)
        lightPenY = UInt8(y & 0xFF)
        lightPenLatchedThisFrame = true
        raiseInterrupt(0x08)
    }

    /// Latch a light pen edge at the current raster beam position.
    public func triggerLightPenAtCurrentBeam() {
        let beamX = rasterCycle * 512 / rasterCyclesPerLine
        triggerLightPen(x: beamX, y: Int(rasterLine))
    }

    func fetchCharData(column: Int) {
        if recordsBusAccessTraces {
            lastHighPhaseMemoryReads.removeAll(keepingCapacity: true)
            lastHighPhaseColorRAMReads.removeAll(keepingCapacity: true)
        }

        if badLineFetchUsesUnstableStartupData(column: column) {
            lineBuffer[column] = 0xFF
            colorBuffer[column] = 0x0F
            badLineFetchMask |= UInt64(1) << UInt64(column)
            displayLineBufferValid = badLineFetchMask == (UInt64(1) << 40) - 1
            return
        }

        let screenBase = UInt16((memoryPointers >> 4) & 0x0F) * 0x0400
        let vc = UInt16(videoCounterBase + column)
        if column == 0 {
            displayLineBufferBase = videoCounterBase
        }
        let screenAddress = screenBase + vc
        if recordsBusAccessTraces {
            lastHighPhaseMemoryReads.append(screenAddress)
        }
        let charCode = readMemory?(screenAddress) ?? 0
        lineBuffer[column] = charCode
        if recordsBusAccessTraces {
            lastHighPhaseColorRAMReads.append(vc)
        }
        colorBuffer[column] = (readColorRAM?(vc) ?? 0) & 0x0F

        badLineFetchMask |= UInt64(1) << UInt64(column)
        displayLineBufferValid = badLineFetchMask == (UInt64(1) << 40) - 1
    }

    func badLineFetchUsesUnstableStartupData(column: Int) -> Bool {
        guard let startCycle = badLineStartCycle, startCycle >= 12 else { return false }
        let firstFetchColumn = max(0, startCycle - 15)
        return column >= firstFetchColumn && column < min(40, firstFetchColumn + 3)
    }

    func hasLatchedMatrixColumn(_ column: Int, rowBase: Int) -> Bool {
        guard column >= 0 && column < 40 else { return false }
        guard displayLineBufferBase == rowBase else { return false }
        if displayLineBufferValid {
            return true
        }
        let columnMask = UInt64(1) << UInt64(column)
        return badLineFetchMask & columnMask != 0
    }

    func hasAnyLatchedMatrixColumn(rowBase: Int) -> Bool {
        guard displayLineBufferBase == rowBase else { return false }
        return displayLineBufferValid || badLineFetchMask != 0
    }

    func hasLatchedGraphicsColumn(_ column: Int, rowBase: Int, pixelRow: Int) -> Bool {
        guard column >= 0 && column < 40 else { return false }
        guard graphicsBufferBase == rowBase && graphicsBufferPixelRow == pixelRow else { return false }
        if graphicsBufferValid {
            return true
        }
        let columnMask = UInt64(1) << UInt64(column)
        return graphicsFetchMask & columnMask != 0
    }

    func currentDisplayFetchContext() -> (charRow: Int, rowBase: Int, pixelRow: Int)? {
        let topBorder: Int = rows25 ? VIC.displayTop : VIC.displayTop + 4
        let bottomBorder: Int = rows25 ? VIC.displayBottom : VIC.displayBottom - 4
        let line = Int(rasterLine)
        let graphicsY = line - VIC.displayTop

        guard displayActive && displayEnabled && graphicsY >= 0 else { return nil }
        let nominallyVisible = line >= topBorder && line < bottomBorder
        let borderFlipFlopOpen = !verticalBorderActive
        guard nominallyVisible || borderFlipFlopOpen else { return nil }

        let charRow = graphicsY / 8
        let rowBase = charRow * 40
        let pixelRow = hasAnyLatchedMatrixColumn(rowBase: rowBase) ? rowCounter & 0x07 : graphicsY % 8
        return (charRow, rowBase, pixelRow)
    }

    func fetchDisplayData(column: Int, recordTrace: Bool) {
        guard column >= 0 && column < 40 else { return }
        guard let context = currentDisplayFetchContext() else { return }

        if column == 0 || graphicsBufferBase != context.rowBase || graphicsBufferPixelRow != context.pixelRow {
            graphicsFetchMask = 0
            graphicsBufferValid = false
            graphicsBufferBase = context.rowBase
            graphicsBufferPixelRow = context.pixelRow
        }

        let readMem = readMemory ?? { _ in return 0 }
        let screenBase = UInt16((memoryPointers >> 4) & 0x0F) * 0x0400
        let charBase: UInt16
        if bitmapMode {
            charBase = UInt16((memoryPointers >> 3) & 0x01) * 0x2000
        } else {
            charBase = UInt16((memoryPointers >> 1) & 0x07) * 0x0800
        }

        let vc = context.rowBase + column
        let charCode: UInt8
        let colorData: UInt8
        if hasLatchedMatrixColumn(column, rowBase: context.rowBase) {
            charCode = lineBuffer[column]
            colorData = colorBuffer[column]
        } else {
            let screenAddress = screenBase + UInt16(vc)
            if recordTrace {
                lastLowPhaseMemoryReads.append(screenAddress)
            }
            charCode = readMem(screenAddress)
            colorData = (readColorRAM?(UInt16(vc)) ?? 0x0E) & 0x0F
        }

        if bitmapMode {
            let bitmapAddr = charBase + UInt16(vc) * 8 + UInt16(context.pixelRow)
            if recordTrace {
                lastLowPhaseMemoryReads.append(bitmapAddr)
            }
            graphicsBuffer[column] = readMem(bitmapAddr)
        } else {
            let glyphCode = extendedBGMode ? (charCode & 0x3F) : charCode
            let charAddr = charBase + UInt16(glyphCode) * 8 + UInt16(context.pixelRow)
            if recordTrace {
                lastLowPhaseMemoryReads.append(charAddr)
            }
            graphicsBuffer[column] = readMem(charAddr)
        }
        graphicsBufferControlReg1[column] = controlReg1
        graphicsBufferControlReg2[column] = controlReg2
        graphicsBufferMemoryPointers[column] = memoryPointers
        graphicsBufferBackgroundColors[column] = backgroundColor
        graphicsBufferScreenBytes[column] = charCode
        graphicsBufferColorData[column] = colorData

        graphicsFetchMask |= UInt64(1) << UInt64(column)
        graphicsBufferValid = graphicsFetchMask == (UInt64(1) << 40) - 1
    }

    // MARK: - Rasterline rendering

    func renderRasterline() {
        let fbY = Int(rasterLine) - VIC.firstVisibleLine
        guard fbY >= 0 && fbY < VIC.screenHeight else { return }

        let bgCol = ColorPalette.rgba[Int(backgroundColor[0] & 0x0F)]
        let lineOffset = fbY * VIC.screenWidth

        // Determine border limits
        let topBorder: Int = rows25 ? VIC.displayTop : VIC.displayTop + 4
        let bottomBorder: Int = rows25 ? VIC.displayBottom : VIC.displayBottom - 4
        let leftBorder: Int = cols40 ? VIC.displayLeft : VIC.displayLeft + 7
        let rightBorder: Int = cols40 ? VIC.displayRight : VIC.displayRight - 9

        let lineInDisplay = Int(rasterLine) >= topBorder && Int(rasterLine) < bottomBorder
        let graphicsY = Int(rasterLine) - VIC.displayTop

        // Render character/bitmap graphics for this line.
        for px in 0..<VIC.screenWidth {
            graphicsLineScratch[px] = bgCol
            foregroundMaskScratch[px] = false
            backgroundColorSourceScratch[px] = -1
        }

        let useRasterTrace = rasterTraceHasSamples && rasterTraceLine == rasterLine
        if ((lineInDisplay && displayActive && displayEnabled) || (useRasterTrace && rasterTraceHasDisplayOpen)) && graphicsY >= 0 {
            let charRow = graphicsY / 8
            let rowBase = charRow * 40
            let pixelRow = hasAnyLatchedMatrixColumn(rowBase: rowBase) ? rowCounter & 0x07 : graphicsY % 8

            renderGraphicsLine(
                &graphicsLineScratch,
                foregroundMask: &foregroundMaskScratch,
                charRow: charRow,
                pixelRow: pixelRow,
                leftBorder: VIC.displayLeft,
                rightBorder: rightBorder,
                markBackgroundPixel: { pixel, backgroundIndex in
                    guard pixel >= 0 && pixel < VIC.screenWidth else { return }
                    self.backgroundColorSourceScratch[pixel] = Int8(backgroundIndex)
                }
            )
        }

        // Compose final line with borders, then draw sprites over it. C64 sprites
        // can appear in the border while still colliding with display graphics.
        for px in 0..<VIC.screenWidth {
            let traceValid = useRasterTrace && rasterTraceValid[px]
            let fallbackDisplayOpen = lineInDisplay
                && displayActive
                && displayEnabled
                && px >= leftBorder
                && px < rightBorder
            let displayOpen = traceValid
                ? rasterTraceDisplayOpen[px]
                : fallbackDisplayOpen

            if displayOpen {
                let backgroundIndex = Int(backgroundColorSourceScratch[px])
                if traceValid && backgroundIndex >= 0 {
                    finalLineScratch[px] = ColorPalette.rgba[Int(rasterTraceBackgroundColor(backgroundIndex, pixel: px) & 0x0F)]
                } else {
                    finalLineScratch[px] = graphicsLineScratch[px]
                }
            } else {
                let color = traceValid ? rasterTraceBorderColor[px] : borderColor
                finalLineScratch[px] = ColorPalette.rgba[Int(color & 0x0F)]
            }
        }

        for px in 0..<VIC.screenWidth {
            let traceValid = useRasterTrace && rasterTraceValid[px]
            let fallbackDisplayOpen = lineInDisplay
                && displayActive
                && displayEnabled
                && px >= leftBorder
                && px < rightBorder
            let displayOpen = traceValid
                ? rasterTraceDisplayOpen[px]
                : fallbackDisplayOpen
            spriteForegroundMaskScratch[px] = displayOpen ? foregroundMaskScratch[px] : false
        }

        if useRasterTrace && spriteTraceHasSamples && spriteTraceLine == rasterLine {
            applySpriteTrace(&finalLineScratch)
        } else {
            renderSprites(&finalLineScratch, fbY: fbY, foregroundMask: spriteForegroundMaskScratch)
        }

        for px in 0..<VIC.screenWidth {
            framebuffer[lineOffset + px] = finalLineScratch[px]
        }

        // Update video counter at end of display line
        let shouldAdvanceDisplay = (lineInDisplay && displayActive && displayEnabled) || (useRasterTrace && rasterTraceHasDisplayOpen)
        if shouldAdvanceDisplay {
            let charRow = graphicsY / 8
            let rowBase = charRow * 40
            let pixelRow = hasAnyLatchedMatrixColumn(rowBase: rowBase) ? rowCounter & 0x07 : graphicsY % 8
            if pixelRow == 7 {
                videoCounterBase = (charRow + 1) * 40
                rowCounter = 0
            } else {
                rowCounter = (pixelRow + 1) & 0x07
            }
        }
    }

    func applySpriteTrace(_ line: inout [UInt32]) {
        for x in 0..<VIC.screenWidth where spriteTraceValid[x] {
            let hasForeground = spriteTraceDisplayForeground[x]
            if !spriteTracePriorityBehindBG[x] || !hasForeground {
                line[x] = spriteTraceColor[x]
            }
        }
    }

    func rasterTraceBackgroundColor(_ index: Int, pixel: Int) -> UInt8 {
        switch index {
        case 1:
            return rasterTraceBackgroundColor1[pixel]
        case 2:
            return rasterTraceBackgroundColor2[pixel]
        case 3:
            return rasterTraceBackgroundColor3[pixel]
        default:
            return rasterTraceBackgroundColor0[pixel]
        }
    }

    func renderGraphicsLine(_ line: inout [UInt32], foregroundMask: inout [Bool], charRow: Int, pixelRow: Int,
                            leftBorder: Int, rightBorder: Int,
                            markBackgroundPixel: ((Int, Int) -> Void)? = nil) {
        let readMem = readMemory ?? { _ in return 0 }

        for col in 0..<40 {
            let rowBase = charRow * 40
            let useColumnTrace = hasLatchedGraphicsColumn(col, rowBase: rowBase, pixelRow: pixelRow)
            let columnControlReg1 = useColumnTrace ? graphicsBufferControlReg1[col] : controlReg1
            let columnControlReg2 = useColumnTrace ? graphicsBufferControlReg2[col] : controlReg2
            let columnMemoryPointers = useColumnTrace ? graphicsBufferMemoryPointers[col] : memoryPointers
            let columnBackgroundColors = useColumnTrace ? graphicsBufferBackgroundColors[col] : backgroundColor
            let columnBitmapMode = columnControlReg1 & 0x20 != 0
            let columnExtendedBGMode = columnControlReg1 & 0x40 != 0
            let columnMulticolorMode = columnControlReg2 & 0x10 != 0
            let columnInvalidECMMode = columnExtendedBGMode && (columnBitmapMode || columnMulticolorMode)
            let screenBase = UInt16((columnMemoryPointers >> 4) & 0x0F) * 0x0400
            let charBase: UInt16
            if columnBitmapMode {
                charBase = UInt16((columnMemoryPointers >> 3) & 0x01) * 0x2000
            } else {
                charBase = UInt16((columnMemoryPointers >> 1) & 0x07) * 0x0800
            }
            let vc = rowBase + col
            let screenAddr = screenBase + UInt16(vc)
            let charCode: UInt8
            let colorData: UInt8
            if useColumnTrace {
                charCode = graphicsBufferScreenBytes[col]
                colorData = graphicsBufferColorData[col]
            } else if hasLatchedMatrixColumn(col, rowBase: rowBase) {
                charCode = lineBuffer[col]
                colorData = colorBuffer[col]
            } else {
                charCode = readMem(screenAddr)
                colorData = (readColorRAM?(UInt16(vc)) ?? 0x0E) & 0x0F
            }

            let pixelData: UInt8
            if useColumnTrace {
                pixelData = graphicsBuffer[col]
            } else if columnBitmapMode {
                let bitmapAddr = charBase + UInt16(vc) * 8 + UInt16(pixelRow)
                pixelData = readMem(bitmapAddr)
            } else {
                let glyphCode = columnExtendedBGMode ? (charCode & 0x3F) : charCode
                let charAddr = charBase + UInt16(glyphCode) * 8 + UInt16(pixelRow)
                pixelData = readMem(charAddr)
            }

            let columnXScroll = Int(columnControlReg2 & 0x07)
            let xPos = leftBorder + col * 8 + columnXScroll
            let columnBackgroundMarker = columnInvalidECMMode ? nil : markBackgroundPixel

            if columnBitmapMode {
                renderBitmapChar(
                    line: &line,
                    foregroundMask: &foregroundMask,
                    xPos: xPos,
                    pixelData: pixelData,
                    screenByte: charCode,
                    colorByte: colorData,
                    backgroundColors: columnBackgroundColors,
                    isMulticolor: columnMulticolorMode,
                    markBackgroundPixel: columnBackgroundMarker
                )
            } else if columnExtendedBGMode {
                renderExtBGChar(
                    line: &line,
                    foregroundMask: &foregroundMask,
                    xPos: xPos,
                    pixelData: pixelData,
                    charCode: charCode,
                    colorByte: colorData,
                    backgroundColors: columnBackgroundColors,
                    markBackgroundPixel: columnBackgroundMarker
                )
            } else if columnMulticolorMode && (colorData & 0x08) != 0 {
                renderMulticolorChar(
                    line: &line,
                    foregroundMask: &foregroundMask,
                    xPos: xPos,
                    pixelData: pixelData,
                    colorByte: colorData,
                    backgroundColors: columnBackgroundColors,
                    markBackgroundPixel: columnBackgroundMarker
                )
            } else {
                renderStandardChar(
                    line: &line,
                    foregroundMask: &foregroundMask,
                    xPos: xPos,
                    pixelData: pixelData,
                    colorByte: colorData,
                    backgroundColor0: columnBackgroundColors[0],
                    markBackgroundPixel: columnBackgroundMarker
                )
            }

            if columnInvalidECMMode {
                maskInvalidECMOutput(line: &line, xPos: xPos)
            }
        }
    }

    func maskInvalidECMOutput(line: inout [UInt32], xPos: Int) {
        let black = ColorPalette.rgba[0]
        for bit in 0..<8 {
            let px = xPos + bit
            guard px >= 0 && px < VIC.screenWidth else { continue }
            line[px] = black
        }
    }

    /// Standard text mode: 1 bit per pixel
    func renderStandardChar(line: inout [UInt32], foregroundMask: inout [Bool], xPos: Int, pixelData: UInt8, colorByte: UInt8,
                            backgroundColor0: UInt8? = nil,
                            markBackgroundPixel: ((Int, Int) -> Void)? = nil) {
        let fgColor = ColorPalette.rgba[Int(colorByte & 0x0F)]
        let bgColor = ColorPalette.rgba[Int((backgroundColor0 ?? backgroundColor[0]) & 0x0F)]

        for bit in 0..<8 {
            let px = xPos + bit
            guard px >= 0 && px < VIC.screenWidth else { continue }
            if pixelData & (0x80 >> bit) != 0 {
                line[px] = fgColor
                foregroundMask[px] = true
            } else {
                line[px] = bgColor
                markBackgroundPixel?(px, 0)
            }
        }
    }

    /// Multicolor text mode: 2 bits per pixel (double-wide pixels)
    func renderMulticolorChar(line: inout [UInt32], foregroundMask: inout [Bool], xPos: Int, pixelData: UInt8, colorByte: UInt8,
                              backgroundColors: [UInt8]? = nil,
                              markBackgroundPixel: ((Int, Int) -> Void)? = nil) {
        let colorsSource = backgroundColors ?? backgroundColor
        let colors: [UInt32] = [
            ColorPalette.rgba[Int(colorsSource[0] & 0x0F)],
            ColorPalette.rgba[Int(colorsSource[1] & 0x0F)],
            ColorPalette.rgba[Int(colorsSource[2] & 0x0F)],
            ColorPalette.rgba[Int(colorByte & 0x07)],
        ]

        for pair in 0..<4 {
            let bits = (pixelData >> (6 - pair * 2)) & 0x03
            let color = colors[Int(bits)]
            let px0 = xPos + pair * 2
            let px1 = px0 + 1
            if px0 >= 0 && px0 < VIC.screenWidth { line[px0] = color }
            if px1 >= 0 && px1 < VIC.screenWidth { line[px1] = color }
            if bits != 0 {
                if bits >= 2 {
                    if px0 >= 0 && px0 < VIC.screenWidth { foregroundMask[px0] = true }
                    if px1 >= 0 && px1 < VIC.screenWidth { foregroundMask[px1] = true }
                }
            }
            switch bits {
            case 0, 1, 2:
                markBackgroundPixel?(px0, Int(bits))
                markBackgroundPixel?(px1, Int(bits))
            default:
                break
            }
        }
    }

    /// Extended background color mode
    func renderExtBGChar(line: inout [UInt32], foregroundMask: inout [Bool], xPos: Int, pixelData: UInt8,
                         charCode: UInt8, colorByte: UInt8, backgroundColors: [UInt8]? = nil,
                         markBackgroundPixel: ((Int, Int) -> Void)? = nil) {
        let colorsSource = backgroundColors ?? backgroundColor
        let bgIndex = Int(charCode >> 6)
        let fgColor = ColorPalette.rgba[Int(colorByte & 0x0F)]
        let bgColor = ColorPalette.rgba[Int(colorsSource[bgIndex] & 0x0F)]

        for bit in 0..<8 {
            let px = xPos + bit
            guard px >= 0 && px < VIC.screenWidth else { continue }
            if pixelData & (0x80 >> bit) != 0 {
                line[px] = fgColor
                foregroundMask[px] = true
            } else {
                line[px] = bgColor
                markBackgroundPixel?(px, bgIndex)
            }
        }
    }

    /// Bitmap mode rendering
    func renderBitmapChar(line: inout [UInt32], foregroundMask: inout [Bool], xPos: Int, pixelData: UInt8,
                         screenByte: UInt8, colorByte: UInt8, backgroundColors: [UInt8]? = nil,
                         isMulticolor: Bool? = nil,
                         markBackgroundPixel: ((Int, Int) -> Void)? = nil) {
        let fgColor: UInt32
        let bgColor: UInt32

        if isMulticolor ?? multicolorMode {
            let colorsSource = backgroundColors ?? backgroundColor
            let colors: [UInt32] = [
                ColorPalette.rgba[Int(colorsSource[0] & 0x0F)],
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
                if bits != 0 {
                    if bits >= 2 {
                        if px0 >= 0 && px0 < VIC.screenWidth { foregroundMask[px0] = true }
                        if px1 >= 0 && px1 < VIC.screenWidth { foregroundMask[px1] = true }
                    }
                } else {
                    markBackgroundPixel?(px0, 0)
                    markBackgroundPixel?(px1, 0)
                }
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
                foregroundMask[px] = true
            } else {
                line[px] = bgColor
            }
        }
    }

    // MARK: - Sprites

    static let spriteDMAFirstStartCycle = 58

    func spriteDMAStartCycle(for sprite: Int) -> Int? {
        guard sprite >= 0 && sprite < 8 else { return nil }
        let unwrappedCycle = VIC.spriteDMAFirstStartCycle + sprite * 2
        return unwrappedCycle % rasterCyclesPerLine
    }

    func spritePointerSlotForCurrentCycle() -> Int? {
        let firstPointerCycle = rasterCyclesPerLine - 8
        guard rasterCycle >= firstPointerCycle,
              rasterCycle < rasterCyclesPerLine else {
            return nil
        }
        return rasterCycle - firstPointerCycle
    }

    func spriteDMASlotForCurrentCycle() -> Int? {
        for sprite in 0..<8 {
            guard let startCycle = spriteDMAStartCycle(for: sprite) else { continue }
            let secondCycle = (startCycle + 1) % rasterCyclesPerLine
            if rasterCycle == startCycle || rasterCycle == secondCycle {
                return sprite
            }
        }
        return nil
    }

    func spriteMiddleByteSlotForCurrentCycle() -> Int? {
        for sprite in 0..<8 {
            guard let startCycle = spriteDMAStartCycle(for: sprite) else { continue }
            if rasterCycle == (startCycle + 1) % rasterCyclesPerLine {
                return sprite
            }
        }
        return nil
    }

    func spriteBAWarningSlotForCurrentCycle() -> Int? {
        (0..<8)
            .compactMap { sprite -> (sprite: Int, distance: Int)? in
                guard let startCycle = spriteDMAStartCycle(for: sprite) else { return nil }
                let distance = (startCycle - rasterCycle + rasterCyclesPerLine) % rasterCyclesPerLine
                guard distance >= 1 && distance <= 3 else { return nil }
                return (sprite, distance)
            }
            .filter { spriteDMAEligible($0.sprite, onRasterLine: spriteBAWarningRasterLine(for: $0.sprite)) }
            .min { lhs, rhs in
                if lhs.distance == rhs.distance {
                    return lhs.sprite < rhs.sprite
                }
                return lhs.distance < rhs.distance
            }?
            .sprite
    }

    func spriteBAWarningRasterLine(for sprite: Int) -> Int {
        guard let startCycle = spriteDMAStartCycle(for: sprite) else {
            return Int(rasterLine)
        }

        if startCycle <= rasterCycle {
            return (Int(rasterLine) + 1) % rasterLinesPerFrame
        }
        return Int(rasterLine)
    }

    func spriteDMAFetchSlotForCurrentCycle() -> Int? {
        for sprite in 0..<8 {
            guard let startCycle = spriteDMAStartCycle(for: sprite) else { continue }
            if rasterCycle == startCycle {
                return sprite
            }
        }
        return nil
    }

    func spriteLineRow(for sprite: Int) -> Int? {
        spriteLineRow(for: sprite, onRasterLine: Int(rasterLine))
    }

    func spriteLineRow(for sprite: Int, onRasterLine line: Int) -> Int? {
        guard let byteOffset = spriteLineByteOffset(for: sprite, onRasterLine: line) else { return nil }
        return byteOffset / 3
    }

    func spriteLineByteOffset(for sprite: Int) -> Int? {
        spriteLineByteOffset(for: sprite, onRasterLine: Int(rasterLine))
    }

    func spriteLineByteOffset(for sprite: Int, onRasterLine line: Int) -> Int? {
        guard sprite >= 0 && sprite < 8 else { return nil }
        if line == Int(rasterLine),
           spriteExpansionLine[sprite] == line,
           spriteDMAEligibilityKnown(onRasterLine: line),
           spriteDMAEligible(sprite, onRasterLine: line) {
            return spriteMC[sprite]
        }

        return spriteLineByteOffsetFromRegisters(for: sprite, onRasterLine: line)
    }

    func spriteLineByteOffsetFromRegisters(for sprite: Int, onRasterLine line: Int) -> Int? {
        guard spriteEnabled & (1 << sprite) != 0 else { return nil }

        let expandedY = spriteExpandY & (1 << sprite) != 0
        guard let offset = spriteLineOffset(for: sprite, onRasterLine: line, expandedY: expandedY) else {
            return nil
        }

        if line == Int(rasterLine), spriteExpansionLine[sprite] == line {
            return spriteMC[sprite]
        }

        if expandedY {
            return (offset / 2) * 3
        }
        return offset * 3
    }

    func spriteDMAEligibilityKnown(onRasterLine line: Int) -> Bool {
        spriteDMACheckLine == line
    }

    func spriteDMAEligible(_ sprite: Int, onRasterLine line: Int) -> Bool {
        guard sprite >= 0 && sprite < 8 else { return false }
        if spriteDMAEligibilityKnown(onRasterLine: line) {
            return spriteDMACheckMask & (1 << sprite) != 0
        }
        return spriteLineByteOffsetFromRegisters(for: sprite, onRasterLine: line) != nil
    }

    func latchSpriteDMAEligibilityForCurrentLine() {
        let line = Int(rasterLine)
        if spriteDMACheckLine != line {
            spriteDMACheckLine = line
            spriteDMACheckMask = 0
        }

        let lowRaster = UInt8(truncatingIfNeeded: line)
        for sprite in 0..<8 {
            let mask = UInt8(1 << sprite)
            guard spriteDMACheckMask & mask == 0 else { continue }
            guard spriteEnabled & mask != 0 else { continue }

            if spriteY[sprite] == lowRaster {
                initializeSpriteDMAState(sprite: sprite, onRasterLine: line)
                spriteDMACheckMask |= mask
                continue
            }

            guard spriteDisplay[sprite] else { continue }
            guard spriteLineByteOffsetFromRegisters(for: sprite, onRasterLine: line) != nil else { continue }
            spriteDMACheckMask |= mask
        }
    }

    func latchSpriteDisplayForCurrentLine() {
        let line = Int(rasterLine)
        let lowRaster = UInt8(truncatingIfNeeded: line)

        for sprite in 0..<8 where spriteDMAEligible(sprite, onRasterLine: line) {
            spriteMC[sprite] = spriteMCBase[sprite]
            if spriteY[sprite] == lowRaster {
                spriteDisplay[sprite] = true
            }
        }
    }

    func initializeSpriteDMAState(sprite: Int, onRasterLine line: Int) {
        spriteExpansionLine[sprite] = line
        spriteDisplay[sprite] = false
        spriteMCBase[sprite] = 0
        spriteMC[sprite] = 0
        spriteLastFetchedMC[sprite] = 0
        spriteLastFetchedByteOffset[sprite] = -1
        spriteYExpFF[sprite] = spriteExpandY & (1 << sprite) == 0
    }

    func spriteLineOffset(for sprite: Int, onRasterLine line: Int, expandedY: Bool? = nil) -> Int? {
        guard sprite >= 0 && sprite < 8 else { return nil }
        let sy = Int(spriteY[sprite])
        let height = (expandedY ?? (spriteExpandY & (1 << sprite) != 0)) ? 42 : 21
        let primaryOffset = line - sy
        if primaryOffset >= 0 && primaryOffset < height {
            return primaryOffset
        }

        let repeatedStartLine = sy + 256
        guard repeatedStartLine < rasterLinesPerFrame else { return nil }
        let repeatedOffset = line - repeatedStartLine
        if repeatedOffset >= 0 && repeatedOffset < height {
            return repeatedOffset
        }
        return nil
    }

    func updateSpriteExpansionStateForCurrentLine() {
        let line = Int(rasterLine)
        for sprite in 0..<8 {
            guard spriteEnabled & (1 << sprite) != 0 else {
                spriteExpansionLine[sprite] = nil
                spriteYExpFF[sprite] = false
                spriteDisplay[sprite] = false
                spriteMCBase[sprite] = 0
                spriteLastFetchedMC[sprite] = 0
                spriteLastFetchedByteOffset[sprite] = -1
                continue
            }

            let expandedY = spriteExpandY & (1 << sprite) != 0
            guard let offset = spriteLineOffset(for: sprite, onRasterLine: line, expandedY: expandedY) else {
                spriteExpansionLine[sprite] = nil
                spriteYExpFF[sprite] = false
                spriteDisplay[sprite] = false
                spriteMCBase[sprite] = 0
                spriteLastFetchedByteOffset[sprite] = -1
                continue
            }

            spriteExpansionLine[sprite] = line
            if expandedY {
                spriteYExpFF[sprite] = offset % 2 == 1
                spriteMCBase[sprite] = (offset / 2) * 3
            } else {
                spriteYExpFF[sprite] = true
                spriteMCBase[sprite] = offset * 3
            }
            spriteMC[sprite] = spriteMCBase[sprite]
        }
    }

    func applySpriteYExpansionWrite(previous: UInt8, newValue: UInt8) {
        let changedToUnexpanded = previous & ~newValue
        guard changedToUnexpanded != 0 else { return }
        guard rasterCycle <= 16 else { return }

        let line = Int(rasterLine)
        for sprite in 0..<8 where changedToUnexpanded & (1 << sprite) != 0 {
            guard spriteExpansionLine[sprite] == line else { continue }
            guard !spriteYExpFF[sprite] else { continue }

            spriteYExpFF[sprite] = true
            if rasterCycle == 15 {
                let crunchedBase = spriteCrunchMCBase(base: spriteMCBase[sprite], mc: spriteLastFetchedMC[sprite])
                spriteMCBase[sprite] = crunchedBase
                spriteMC[sprite] = crunchedBase
            } else {
                spriteMC[sprite] = min(63, spriteMC[sprite] + 3)
                spriteMCBase[sprite] = spriteMC[sprite]
            }
        }
    }

    func spriteCrunchMCBase(base: Int, mc: Int) -> Int {
        ((0x2A & (base & mc)) | (0x15 & (base | mc))) & 0x3F
    }

    func fetchSpriteData(sprite: Int) {
        if recordsBusAccessTraces {
            lastHighPhaseMemoryReads.removeAll(keepingCapacity: true)
            lastHighPhaseColorRAMReads.removeAll(keepingCapacity: true)
        }

        guard sprite >= 0 && sprite < 8 else { return }
        let readMem = readMemory ?? { _ in return 0 }

        guard let byteOffset = spriteLineByteOffset(for: sprite) else {
            return
        }

        let spritePtr = UInt16(spritePointers[sprite]) * 64
        let dataAddr = spritePtr + UInt16(byteOffset)
        if recordsBusAccessTraces {
            lastHighPhaseMemoryReads.append(contentsOf: [dataAddr, dataAddr + 1, dataAddr + 2])
        }
        spriteLineData[sprite][0] = readMem(dataAddr)
        spriteLineData[sprite][1] = readMem(dataAddr + 1)
        spriteLineData[sprite][2] = readMem(dataAddr + 2)
        spriteLastFetchedByteOffset[sprite] = byteOffset
        if spriteExpansionLine[sprite] == Int(rasterLine) {
            spriteMC[sprite] = min(63, byteOffset + 3)
            spriteLastFetchedMC[sprite] = spriteMC[sprite]
        }
    }

    func spriteMiddleByteOffset(for sprite: Int) -> Int? {
        guard sprite >= 0 && sprite < 8 else { return nil }
        guard spriteMiddleByteSlotForCurrentCycle() == sprite else { return nil }

        if activeSpriteDMASlot == sprite, spriteLastFetchedByteOffset[sprite] >= 0 {
            return spriteLastFetchedByteOffset[sprite]
        }
        return spriteLineByteOffset(for: sprite)
    }

    func fetchSpriteMiddleByte(sprite: Int, recordTrace: Bool) {
        guard sprite >= 0 && sprite < 8 else { return }
        guard let byteOffset = spriteMiddleByteOffset(for: sprite) else { return }

        let readMem = readMemory ?? { _ in return 0 }
        let spritePtr = UInt16(spritePointers[sprite]) * 64
        let address = spritePtr + UInt16(byteOffset + 1)
        if recordTrace {
            lastLowPhaseMemoryReads.append(address)
        }
        spriteLineData[sprite][1] = readMem(address)
    }

    func renderSprites(_ line: inout [UInt32], fbY: Int, foregroundMask: [Bool]? = nil) {
        guard spriteDisplay.contains(true) else { return }

        let graphicsLine = line
        let background = ColorPalette.rgba[Int(backgroundColor[0] & 0x0F)]
        var spriteOccupancy = [UInt8](repeating: 0, count: VIC.screenWidth)

        func plotSpritePixel(sprite: Int, x: Int, color: UInt32, behindBG: Bool) {
            guard x >= 0 && x < VIC.screenWidth else { return }

            let spriteMask = UInt8(1 << sprite)
            if spriteOccupancy[x] != 0 {
                spriteSpriteCollision |= spriteOccupancy[x] | spriteMask
                raiseInterrupt(0x04)  // IMMC
            }
            spriteOccupancy[x] |= spriteMask

            let hasForeground = foregroundMask?[x] ?? (graphicsLine[x] != background)
            if hasForeground {
                spriteDataCollision |= spriteMask
                raiseInterrupt(0x02)  // IMBC
            }

            if !behindBG || !hasForeground {
                line[x] = color
            }
        }

        // Render sprites from back to front (sprite 7 first, 0 last = highest priority)
        for i in stride(from: 7, through: 0, by: -1) {
            guard spriteDisplay[i] else { continue }
            guard spriteEnabled & (1 << i) != 0 else { continue }

            let sx = Int(spriteX[i] & 0x01FF)
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
                        let px = (sx + bit * xWidth + sub) & 0x01FF
                        plotSpritePixel(sprite: i, x: px, color: pixColor, behindBG: behindBG)
                    }
                }
            } else {
                for bit in 0..<24 {
                    guard fullData & (1 << (23 - bit)) != 0 else { continue }
                    let xWidth = expandX ? 2 : 1
                    for sub in 0..<xWidth {
                        let px = (sx + bit * xWidth + sub) & 0x01FF
                        plotSpritePixel(sprite: i, x: px, color: color, behindBG: behindBG)
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
        let register = reg & 0x3F
        switch register {
        case 0x00...0x0F:
            // Sprite X/Y coordinates
            let sprite = Int(register) / 2
            if register & 1 == 0 {
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
        case 0x13: return lightPenX
        case 0x14: return lightPenY
        case 0x15: return spriteEnabled
        case 0x16: return controlReg2 | 0xE0
        case 0x17: return spriteExpandY
        case 0x18: return memoryPointers | 0x01
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
        case 0x27...0x2E: return spriteColors[Int(register) - 0x27] | 0xF0
        default: return 0xFF  // Unused registers read as $FF
        }
    }

    public func debugRegisterValue(_ reg: UInt16) -> UInt8 {
        switch reg & 0x3F {
        case 0x00...0x0F:
            let sprite = Int(reg & 0x0F) / 2
            if reg & 1 == 0 {
                return UInt8(spriteX[sprite] & 0xFF)
            } else {
                return spriteY[sprite]
            }
        case 0x10: return spriteXMSB
        case 0x11:
            var value = controlReg1 & 0x7F
            if rasterLine > 255 { value |= 0x80 }
            return value
        case 0x12: return UInt8(rasterLine & 0xFF)
        case 0x13: return lightPenX
        case 0x14: return lightPenY
        case 0x15: return spriteEnabled
        case 0x16: return controlReg2 | 0xE0
        case 0x17: return spriteExpandY
        case 0x18: return memoryPointers | 0x01
        case 0x19: return interruptRegister | 0x70
        case 0x1A: return interruptEnable | 0xF0
        case 0x1B: return spritePriority
        case 0x1C: return spriteMulticolor
        case 0x1D: return spriteExpandX
        case 0x1E: return spriteSpriteCollision
        case 0x1F: return spriteDataCollision
        case 0x20: return borderColor | 0xF0
        case 0x21: return backgroundColor[0] | 0xF0
        case 0x22: return backgroundColor[1] | 0xF0
        case 0x23: return backgroundColor[2] | 0xF0
        case 0x24: return backgroundColor[3] | 0xF0
        case 0x25: return spriteMulticolor0 | 0xF0
        case 0x26: return spriteMulticolor1 | 0xF0
        case 0x27...0x2E: return spriteColors[Int((reg & 0x3F) - 0x27)] | 0xF0
        default: return 0xFF
        }
    }

    public func writeRegister(_ reg: UInt16, value: UInt8) {
        let register = reg & 0x3F
        switch register {
        case 0x00...0x0F:
            let sprite = Int(register) / 2
            if register & 1 == 0 {
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
            controlReg1 = value & 0x7F
            rasterCompare = (rasterCompare & 0x00FF) | (UInt16(value & 0x80) << 1)
            if rasterLine == UInt16(VIC.firstBadLine) && displayEnabled {
                badLineDENLatched = true
            }
            checkBadLine()
            checkRasterInterrupt()

        case 0x12:
            rasterCompare = (rasterCompare & 0x100) | UInt16(value)
            checkRasterInterrupt()

        case 0x15: spriteEnabled = value
        case 0x16: controlReg2 = value
        case 0x17:
            let previous = spriteExpandY
            spriteExpandY = value
            applySpriteYExpansionWrite(previous: previous, newValue: value)
        case 0x18: memoryPointers = value

        case 0x19:
            // Acknowledge interrupts (write 1 to clear)
            interruptRegister &= ~(value & 0x0F)
            updateIRQLine()

        case 0x1A:
            interruptEnable = value & 0x0F
            if interruptEnable & 0x01 != 0 {
                checkRasterInterrupt()
            }
            updateIRQLine()

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
        case 0x27...0x2E: spriteColors[Int(register) - 0x27] = value & 0x0F
        default: break
        }
    }
}
