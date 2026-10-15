import Foundation

/// VIC-II emulation with PAL/NTSC bus and pixel sequencing.
/// Captured graphics/sprite output is composed into the framebuffer per line.
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
    // Three four-dot stages from pixel coincidence to CPU-visible collision
    // latches, calibrated by the public PAL sprite/gfx collision-cycle probes.
    private var collisionPipeline0: UInt16 = 0
    private var collisionPipeline1: UInt16 = 0
    private var collisionPipeline2: UInt16 = 0

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

    /// Graphics sequencer display state, independent of the border flip-flops.
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
    /// Once matrix DMA has begun, the remaining c-accesses finish this line.
    private var matrixDMAActive = false
    private var cpuPhaseActive = false
    private var badLineUpdatePending = false
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
    /// Pending Y comparison, transferred at line start and the left edge.
    var verticalBorderClosePending = true
    /// Main border flip-flop. A missed comparison can keep it open across lines.
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
        if badLine || matrixDMAActive {
            switch rasterCycle {
            case 11..<14:
                return .badLineBAWarning
            case 14..<54:
                return .badLineCharacterFetch(column: rasterCycle - 14)
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
        case let .badLineCharacterFetch(column):
            return !badLineFetchUsesUnstableStartupData(column: column)
        case .spriteDMA:
            return true
        case .cpu, .badLineBAWarning, .spriteBAWarning:
            return false
        }
    }

    /// Current cycle's effective bus owner.
    public var busOwner: BusOwner {
        guard aecLineLow else { return .cpu }
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
    /// Position in the internal 40-entry matrix/color line, advanced by g-accesses.
    var videoMatrixLineIndex: Int = 0

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
    private var graphicsBufferLine: UInt16?
    /// Display-mode register state latched alongside each low-phase graphics byte.
    var graphicsBufferControlReg1 = [UInt8](repeating: 0, count: 40)
    var graphicsBufferControlReg2 = [UInt8](repeating: 0, count: 40)
    var graphicsBufferMemoryPointers = [UInt8](repeating: 0, count: 40)
    var graphicsBufferBackgroundColors = [[UInt8]](repeating: [0, 0, 0, 0], count: 40)
    var graphicsBufferScreenBytes = [UInt8](repeating: 0, count: 40)
    var graphicsBufferColorData = [UInt8](repeating: 0, count: 40)
    /// Matrix bits held by the graphics color selector, including between rows.
    private(set) var graphicsOutputMatrix: UInt8 = 0

    /// Sprite advance-line flip-flops; D017 clear holds these set.
    var spriteYExpFF = [Bool](repeating: true, count: 8)
    private var spriteCrunchPendingMask: UInt8 = 0
    /// Sprite data counters (MC, byte offset 0...63 within sprite data)
    var spriteMC = [Int](repeating: 0, count: 8)
    /// Sprite data counter base used by vertical expansion/crunch effects.
    var spriteMCBase = [Int](repeating: 0, count: 8)
    /// MC value after the most recent sprite data fetch.
    var spriteLastFetchedMC = [Int](repeating: 0, count: 8)
    /// Starting MC byte offset used by the most recent sprite data fetch.
    var spriteLastFetchedByteOffset = [Int](repeating: -1, count: 8)
    /// A two-cycle fetch may cross a rasterline; its address counter must not
    /// be recomputed from the next line's Y coordinate or expansion state.
    private var spriteFetchInFlight: (sprite: Int, pointer: UInt16, offset: Int)?
    /// Sprite display active
    var spriteDisplay = [Bool](repeating: false, count: 8)
    /// Sprite line data (3 bytes × 8 sprites)
    var spriteLineData = [[UInt8]](repeating: [0, 0, 0], count: 8)
    struct SpriteShifter {
        var data: UInt32 = 0
        var remainingBits = 0
        var expansionSecondDot = false
        var multicolorSecondBit = false
        var pixel: UInt8 = 0

        var active: Bool { remainingBits > 0 || multicolorSecondBit || expansionSecondDot }

        mutating func clock(matchesX: Bool, expanded: Bool, multicolor: Bool) -> UInt8 {
            if !active {
                guard matchesX else { return 0 }
                remainingBits = 24
                expansionSecondDot = false
                multicolorSecondBit = false
            }
            if !expansionSecondDot {
                if !multicolor {
                    pixel = data & 0x800000 != 0 ? 2 : 0
                } else {
                    if !multicolorSecondBit { pixel = UInt8((data >> 22) & 3) }
                    multicolorSecondBit.toggle()
                }
            }
            if !expanded || expansionSecondDot {
                data = (data << 1) & 0xFFFFFF
                remainingBits = max(0, remainingBits - 1)
            }
            expansionSecondDot = expanded && !expansionSecondDot
            return pixel
        }
    }
    /// DMA fills the live register byte by byte. X comparison starts shifting;
    /// it must never reload a consumed row from the diagnostic line buffer.
    var spriteShifters = [SpriteShifter](repeating: SpriteShifter(), count: 8)
    private var spriteXWriteThisCycle: (register: UInt8, previous: UInt8)?
    private var spriteMulticolorWriteThisCycle: UInt8?
    /// Sprite data pointer bytes latched during the low-phase sprite-pointer slots.
    var spritePointers = [UInt8](repeating: 0, count: 8)
    /// Rasterline for which sprite DMA enable/Y-match has been sampled.
    var spriteDMACheckLine: Int?
    /// Persistent DMA enable bits. Y/enable writes only start inactive DMA;
    /// an active transfer ends when MCBASE reaches 63, not at a Y-derived height.
    var spriteDMACheckMask: UInt8 = 0

    /// Per-visible-pixel raster state captured as the beam advances. This keeps
    /// simple raster color bars and mid-line border mode changes observable even
    /// though the heavier graphics composition still happens at end of line.
    var rasterTraceLine: UInt16?
    var rasterTraceHasSamples: Bool = false
    var rasterTraceHasDisplayOpen: Bool = false
    var rasterTraceHasGraphicsOutput: Bool = false
    var rasterTraceValid = [Bool](repeating: false, count: VIC.screenWidth)
    var rasterTraceDisplayOpen = [Bool](repeating: false, count: VIC.screenWidth)
    var rasterTraceGraphicsOutput = [Bool](repeating: false, count: VIC.screenWidth)
    // Five colors, held matrix bits, and the idle-output mode share one trace word.
    private var rasterTraceColors = [UInt32](repeating: 0, count: VIC.screenWidth)
    var spriteTraceLine: UInt16?
    var spriteTraceHasSamples: Bool = false
    var spriteTraceValid = [Bool](repeating: false, count: VIC.screenWidth)
    var spriteTraceColor = [UInt32](repeating: 0, count: VIC.screenWidth)
    private var spriteTraceColorRegister = [UInt8](repeating: 0, count: VIC.screenWidth)
    var spriteTracePriorityBehindBG = [Bool](repeating: false, count: VIC.screenWidth)
    var spriteTraceDisplayForeground = [Bool](repeating: false, count: VIC.screenWidth)
    var spriteTraceSpriteMask = [UInt8](repeating: 0, count: VIC.screenWidth)
    private var spriteTraceTouchedPixels: [Int] = []

    /// Sprite DMA slots are currently modeled as deterministic two-cycle bursts
    /// per sprite during the VIC-II's sprite-fetch part of the line.
    public var activeSpriteDMASlot: Int? {
        if let fetch = spriteFetchInFlight,
           spriteMiddleByteSlotForCurrentCycle() == fetch.sprite {
            return fetch.sprite
        }
        guard let slot = spriteDMASlotForCurrentCycle(),
              spriteDMAEligible(slot) else {
            return nil
        }
        return slot
    }

    /// Active sprite whose DMA slot is within the BA warning window.
    public var activeSpriteBAWarningSlot: Int? {
        guard let slot = spriteBAWarningSlotForCurrentCycle(),
              spriteDMAEligible(slot) else {
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
    private var spriteOccupancyScratch = [UInt8](repeating: 0, count: VIC.screenWidth)
    private var spriteOccupancyGenerationScratch = [UInt32](repeating: 0, count: VIC.screenWidth)
    private var spriteOccupancyGeneration: UInt32 = 1
    private var spriteSourceLineScratch = [UInt32](repeating: 0, count: VIC.screenWidth)

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
        collisionPipeline0 = 0
        collisionPipeline1 = 0
        collisionPipeline2 = 0
        backgroundColor = [UInt8](repeating: 0, count: 4)
        borderColor = 14

        rasterLine = 0
        rasterCycle = 0
        displayActive = false
        badLine = false
        badLineStartCycle = nil
        matrixDMAActive = false
        cpuPhaseActive = false
        badLineUpdatePending = false
        badLineDENLatched = false
        rasterIRQTriggeredThisLine = false
        lightPenX = 0
        lightPenY = 0
        lightPenLatchedThisFrame = false
        verticalBorderActive = true
        verticalBorderClosePending = true
        horizontalBorderActive = true
        refreshCounter = 0xFF
        rowCounter = 0
        videoCounter = 0
        videoCounterBase = 0
        videoMatrixLineIndex = 0
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
        graphicsBufferLine = nil
        graphicsBufferControlReg1 = [UInt8](repeating: 0, count: 40)
        graphicsBufferControlReg2 = [UInt8](repeating: 0, count: 40)
        graphicsBufferMemoryPointers = [UInt8](repeating: 0, count: 40)
        graphicsBufferBackgroundColors = [[UInt8]](repeating: [0, 0, 0, 0], count: 40)
        graphicsBufferScreenBytes = [UInt8](repeating: 0, count: 40)
        graphicsBufferColorData = [UInt8](repeating: 0, count: 40)
        graphicsOutputMatrix = 0
        spriteYExpFF = [Bool](repeating: true, count: 8)
        spriteCrunchPendingMask = 0
        spriteMC = [Int](repeating: 0, count: 8)
        spriteMCBase = [Int](repeating: 0, count: 8)
        spriteLastFetchedMC = [Int](repeating: 0, count: 8)
        spriteLastFetchedByteOffset = [Int](repeating: -1, count: 8)
        spriteFetchInFlight = nil
        spriteDisplay = [Bool](repeating: false, count: 8)
        spriteLineData = [[UInt8]](repeating: [0, 0, 0], count: 8)
        spriteShifters = [SpriteShifter](repeating: SpriteShifter(), count: 8)
        spriteXWriteThisCycle = nil
        spriteMulticolorWriteThisCycle = nil
        spritePointers = [UInt8](repeating: 0, count: 8)
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

    /// Advance one cycle without an intervening CPU phase.
    @discardableResult
    public func tick() -> Bool {
        beginCycle()
        let shouldStallCPU = isStealingCPU
        endCycle()
        return shouldStallCPU
    }

    /// Low phase precedes the CPU's bus access. In particular, a CPU write to
    /// D018/DDR/bank pins cannot change a pointer already read in this phase.
    func beginCycle() {
        spriteXWriteThisCycle = nil
        spriteMulticolorWriteThisCycle = nil
        if recordsBusAccessTraces {
            lastHighPhaseMemoryReads.removeAll(keepingCapacity: true)
            lastHighPhaseColorRAMReads.removeAll(keepingCapacity: true)
        }

        // A newly started late DMA fills the first matrix entry in phi2;
        // its preceding phi1 still performs the old idle g-access.
        let wasDisplayActive = displayActive
        let pendingDisplayEntry = badLineUpdatePending && (15..<55).contains(rasterCycle)
        // Check for bad line condition
        if rasterCycle == 0 || badLineUpdatePending {
            badLineUpdatePending = false
            checkBadLine()
        }
        sampleVerticalBorderComparators()
        if rasterCycle == 0 { verticalBorderActive = verticalBorderClosePending }
        clockBorderComparators()

        // Hardware cycles 14 and 58, phi1. These counters run even behind
        // closed borders; framebuffer composition must never advance them.
        if rasterCycle == 13 {
            videoCounter = videoCounterBase
            videoMatrixLineIndex = 0
            if badLine { rowCounter = 0 }
        }
        if rasterCycle == 57 {
            if rowCounter == 7 {
                videoCounterBase = videoCounter
                displayActive = badLine
            }
            if displayActive { rowCounter = (rowCounter + 1) & 7 }
        }

        if rasterCycle == 15 { advanceSpriteCounters() }
        if rasterCycle == spriteDMAFirstStartCycle - 3 || rasterCycle == spriteDMAFirstStartCycle - 2 {
            latchSpriteDMAEligibilityForCurrentLine()
        }
        if rasterCycle == spriteDMAFirstStartCycle {
            latchSpriteDisplayForCurrentLine()
        }

        let delayDisplayEntry = pendingDisplayEntry && !wasDisplayActive && displayActive
        if delayDisplayEntry { displayActive = false }
        performLowPhaseAccess()
        if delayDisplayEntry { displayActive = true }
        captureRasterTraceForCurrentCycle()
        cpuPhaseActive = true
    }

    func endCycle() {
        cpuPhaseActive = false
        captureRasterTrace(startX: beamX(atDot: 4), dotCount: 4)
        // Control/priority changes reach the sequencer before X-position
        // writes reach its comparator. The public spritesplit probes exercise
        // both boundaries at each of the eight sprite-X alignments.
        if let previous = spriteMulticolorWriteThisCycle {
            clockSpritePixels(startX: beamX(atDot: 2), dotCount: 1, collisionStage: 1,
                              oldX: true, multicolorBits: previous)
            applySpriteMulticolorChange(from: previous)
            clockSpritePixels(startX: beamX(atDot: 3), dotCount: 1, collisionStage: 1, oldX: true)
        } else {
            clockSpritePixels(startX: beamX(atDot: 2), dotCount: 2, collisionStage: 1, oldX: true)
        }
        clockSpritePixels(startX: beamX(atDot: 4), dotCount: 4, collisionStage: 2)
        if rasterCycle == spriteDMAFirstStartCycle - 2 {
            for sprite in 0..<8 where spriteDMAEligible(sprite) && spriteExpandY & (1 << sprite) != 0 {
                spriteYExpFF[sprite].toggle()
            }
        }
        // Render pixels at specific cycles (raster beam)
        if rasterCycle >= 0 && rasterCycle < rasterCyclesPerLine {
            renderCycle()
        }

        // Sprite data fetch in deterministic per-sprite DMA slots.
        if let sprite = spriteDMAFetchSlotForCurrentCycle() {
            fetchSpriteData(sprite: sprite)
        } else if let sprite = spriteMiddleByteSlotForCurrentCycle() {
            fetchSpriteLastByte(sprite: sprite)
        }

        // Advance cycle
        rasterCycle += 1
        if rasterCycle >= rasterCyclesPerLine {
            endOfLine()
        }
    }

    func checkBadLine() {
        if rasterLine == UInt16(VIC.firstBadLine) && displayEnabled {
            badLineDENLatched = true
        }

        let wasBadLine = badLine

        // Bad line when rasterline is in the VIC-II bad-line range and lower 3 bits match YSCROLL.
        if rasterLine >= UInt16(VIC.firstBadLine) && rasterLine <= UInt16(VIC.lastBadLine) {
            let yMatch = (rasterLine & 0x07) == UInt16(yScroll)
            if yMatch && badLineDENLatched {
                badLine = true
                displayActive = true
                if !wasBadLine && !matrixDMAActive {
                    badLineStartCycle = rasterCycle
                }
            } else {
                badLine = false
                if !matrixDMAActive { badLineStartCycle = nil }
            }
        } else {
            badLine = false
            badLineStartCycle = nil
        }
    }

    func endOfLine() {
        // Render this rasterline to framebuffer if visible
        if rasterLine >= UInt16(VIC.firstVisibleLine) && rasterLine <= UInt16(VIC.lastVisibleLine) {
            renderRasterline()
        }

        // Advance rasterline
        matrixDMAActive = false
        badLine = false
        badLineStartCycle = nil
        graphicsBufferLine = nil
        graphicsFetchMask = 0
        graphicsBufferValid = false
        rasterCycle = 0
        rasterLine += 1

        if rasterLine >= UInt16(rasterLinesPerFrame) {
            rasterLine = 0
            refreshCounter = 0xFF
            videoCounterBase = 0
            badLineDENLatched = false
            lightPenLatchedThisFrame = false
            frameReady = true
        }
        clearRasterTrace()
        rasterIRQTriggeredThisLine = false
        checkRasterInterrupt()
    }

    private func sampleVerticalBorderComparators() {
        let line = Int(rasterLine)
        let topBorder: Int = rows25 ? VIC.displayTop : VIC.displayTop + 4
        let bottomBorder: Int = rows25 ? VIC.displayBottom : VIC.displayBottom - 4

        if line == topBorder && displayEnabled {
            verticalBorderActive = false
            verticalBorderClosePending = false
        }
        if line == bottomBorder {
            verticalBorderClosePending = true
        }
    }

    private func clockBorderComparators() {
        // Border control is sampled a cycle after the logical sprite-X
        // positions used by the line compositor. Keep the pixel edges fixed.
        let leftCycle = cols40 ? 16 : 17
        let rightCycle = cols40 ? 56 : 55
        if rasterCycle == leftCycle {
            verticalBorderActive = verticalBorderClosePending
            if !verticalBorderActive { horizontalBorderActive = false }
            recordBorderTransition(at: cols40 ? VIC.displayLeft : VIC.displayLeft + 7,
                                   updateGraphics: true)
        }
        if rasterCycle == rightCycle {
            horizontalBorderActive = true
            recordBorderTransition(at: cols40 ? VIC.displayRight : VIC.displayRight - 9,
                                   updateGraphics: false)
        }
    }

    private func recordBorderTransition(at pixel: Int, updateGraphics: Bool) {
        guard rasterLine >= UInt16(VIC.firstVisibleLine),
              rasterLine <= UInt16(VIC.lastVisibleLine) else { return }
        prepareRasterTraceForCurrentLine()
        for x in pixel..<VIC.screenWidth {
            rasterTraceDisplayOpen[x] = !horizontalBorderActive
            if updateGraphics { rasterTraceGraphicsOutput[x] = !verticalBorderActive }
        }
        if !horizontalBorderActive { rasterTraceHasDisplayOpen = true }
        if updateGraphics && !verticalBorderActive { rasterTraceHasGraphicsOutput = true }
    }

    func clearRasterTrace() {
        if !rasterTraceHasSamples && !spriteTraceHasSamples {
            rasterTraceLine = nil
            rasterTraceHasDisplayOpen = false
            rasterTraceHasGraphicsOutput = false
            spriteTraceLine = nil
            return
        }
        rasterTraceLine = nil
        rasterTraceHasSamples = false
        rasterTraceHasDisplayOpen = false
        rasterTraceHasGraphicsOutput = false
        spriteTraceLine = nil
        spriteTraceHasSamples = false
        rasterTraceValid.withUnsafeMutableBufferPointer { $0.update(repeating: false) }
        rasterTraceDisplayOpen.withUnsafeMutableBufferPointer { $0.update(repeating: false) }
        rasterTraceGraphicsOutput.withUnsafeMutableBufferPointer { $0.update(repeating: false) }
        rasterTraceColors.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        for index in spriteTraceTouchedPixels {
            spriteTraceValid[index] = false
            spriteTraceColor[index] = 0
            spriteTracePriorityBehindBG[index] = false
            spriteTraceDisplayForeground[index] = false
            spriteTraceSpriteMask[index] = 0
        }
        spriteTraceTouchedPixels.removeAll(keepingCapacity: true)
    }

    func prepareRasterTraceForCurrentLine() {
        if rasterTraceLine == rasterLine {
            return
        }
        clearRasterTrace()

        rasterTraceLine = rasterLine
        rasterTraceHasSamples = false
        rasterTraceHasDisplayOpen = false
        rasterTraceHasGraphicsOutput = false
        spriteTraceLine = rasterLine
        spriteTraceHasSamples = false
        rasterTraceDisplayOpen.withUnsafeMutableBufferPointer { $0.update(repeating: !horizontalBorderActive) }
    }

    /// Logical sprite-X coordinates, before the common video-output delay.
    /// The 6567R8 tail holds/skips counter values; these are its half-cycle
    /// positions, not a claim of calibrated sub-dot analog output timing.
    func beamX(atDot dot: Int) -> Int {
        let cycle = (rasterCycle + dot / 8) % rasterCyclesPerLine
        let localDot = dot % 8
        if videoStandard == .pal {
            return (404 + cycle * 8 + localDot) % 504
        }
        let halfCycle = cycle * 2 + localDot / 4
        let start: Int
        if halfCycle < 123 {
            start = (412 + halfCycle * 4) % 512
        } else if halfCycle <= 126 {
            start = 396
        } else {
            start = 400 + (halfCycle - 127) * 4
        }
        return start + localDot % 4
    }

    func captureRasterTraceForCurrentCycle() {
        guard rasterCycle >= 0,
              rasterCycle < rasterCyclesPerLine else {
            return
        }

        let first = beamX(atDot: 0)
        captureRasterTrace(startX: first, dotCount: 4)
        // Mature the two half-cycle collision stages before the CPU samples
        // the latches. New pixels are queued by their original half-cycle.
        advanceCollisionPipeline()
        advanceCollisionPipeline()
        clockSpritePixels(startX: first, dotCount: 2, collisionStage: 1)
    }

    private func advanceCollisionPipeline() {
        let matured = collisionPipeline0
        collisionPipeline0 = collisionPipeline1
        collisionPipeline1 = collisionPipeline2
        collisionPipeline2 = 0
        let sprites = UInt8(truncatingIfNeeded: matured)
        let graphics = UInt8(truncatingIfNeeded: matured >> 8)
        if sprites != 0 { latchSpriteCollision(sprites) }
        if graphics != 0 { latchSpriteDataCollision(graphics) }
    }

    private func captureRasterTrace(startX: Int, dotCount: Int) {
        let startPixel = max(0, min(VIC.screenWidth, startX))
        let endPixel = min(VIC.screenWidth, startX + dotCount)
        guard startPixel < endPixel else { return }

        guard rasterLine >= UInt16(VIC.firstVisibleLine),
              rasterLine <= UInt16(VIC.lastVisibleLine) else {
            for pixel in startPixel..<endPixel { clockGraphicsColorLatch(at: pixel) }
            return
        }
        prepareRasterTraceForCurrentLine()

        let colors = UInt32(borderColor & 15) << 16
            | UInt32(backgroundColor[3] & 15) << 12
            | UInt32(backgroundColor[2] & 15) << 8
            | UInt32(backgroundColor[1] & 15) << 4
            | UInt32(backgroundColor[0] & 15)
            | UInt32(controlReg1 & 0x60) << 24
            | UInt32(controlReg2 & 0x10) << 24

        rasterTraceValid.withUnsafeMutableBufferPointer { valid in
            rasterTraceGraphicsOutput.withUnsafeMutableBufferPointer { graphics in
                rasterTraceColors.withUnsafeMutableBufferPointer { color in
                    for pixel in startPixel..<endPixel {
                        // The main border masks final output, not collision detection.
                        // DEN arms the vertical border; it is not a live pixel blank.
                        let graphicsOutput = !verticalBorderActive
                        clockGraphicsColorLatch(at: pixel)
                        valid[pixel] = true
                        graphics[pixel] = graphicsOutput
                        color[pixel] = colors | UInt32(graphicsOutputMatrix) << 20
                        if !horizontalBorderActive { rasterTraceHasDisplayOpen = true }
                        if graphicsOutput { rasterTraceHasGraphicsOutput = true }
                    }
                }
            }
        }
        rasterTraceHasSamples = true
    }

    private func clockGraphicsColorLatch(at pixel: Int) {
        guard !verticalBorderActive, graphicsBufferLine == rasterLine,
              pixel >= VIC.displayLeft, pixel < VIC.displayRight else { return }
        let position = pixel - VIC.displayLeft
        let column = position >> 3
        guard graphicsFetchMask & (UInt64(1) << column) != 0,
              position & 7 == Int(graphicsBufferControlReg2[column] & 7) else { return }
        // A g-access precedes the shifter load. Horizontal scroll delays this
        // color latch too; an idle fetch contributes zero matrix bits only here.
        graphicsOutputMatrix = graphicsBufferScreenBytes[column]
    }

    private func clockSpritePixels(startX: Int, dotCount: Int, collisionStage: Int,
                                   oldX: Bool = false, multicolorBits: UInt8? = nil) {
        let activeMask = activeVisibleSpriteMask()
        guard activeMask != 0 else { return }
        let capturesLine = spriteTraceLine == rasterLine
        if capturesLine && startX < VIC.screenWidth {
            for x in startX..<min(VIC.screenWidth, startX + dotCount) {
                spriteTraceValid[x] = false
                spriteTraceSpriteMask[x] = 0
            }
        }

        // One byte per dot keeps collision occupancy local to this clock span,
        // including blanking and NTSC's repeated counter positions.
        var occupancy: UInt64 = 0
        for sprite in stride(from: 7, through: 0, by: -1) {
            let mask = UInt8(1 << sprite)
            guard activeMask & mask != 0 else { continue }
            var shifter = spriteShifters[sprite]
            var spritePosition = Int(spriteX[sprite])
            if oldX, let write = spriteXWriteThisCycle {
                if write.register == UInt8(sprite * 2) {
                    spritePosition = (spritePosition & 0x100) | Int(write.previous)
                } else if write.register == 0x10 {
                    spritePosition = (spritePosition & 0xFF) | (write.previous & mask != 0 ? 0x100 : 0)
                }
            }
            if !shifter.active && !(startX..<startX + dotCount).contains(spritePosition) {
                continue
            }
            let expanded = spriteExpandX & mask != 0
            let multicolor = (multicolorBits ?? spriteMulticolor) & mask != 0
            for dot in 0..<dotCount {
                let x = startX + dot
                let value = shifter.clock(matchesX: spriteDisplay[sprite] && x == spritePosition,
                                          expanded: expanded, multicolor: multicolor)
                guard value != 0 else { continue }
                let previous = UInt8(truncatingIfNeeded: occupancy >> (dot * 8))
                occupancy |= UInt64(mask) << (dot * 8)
                let capture = capturesLine && x < VIC.screenWidth
                let color = value == 1 ? spriteMulticolor0 : value == 2 ? spriteColors[sprite] : spriteMulticolor1
                let colorRegister = value == 1 ? UInt8(0x25) : value == 2 ? UInt8(0x27 + sprite) : UInt8(0x26)
                recordSpritePixel(sprite: sprite, x: x, color: ColorPalette.rgba[Int(color & 15)],
                                  foreground: capture && displayForegroundAtTracePixel(x),
                                  previousSprites: previous, capture: capture, collisionStage: collisionStage,
                                  colorRegister: colorRegister)
            }
            spriteShifters[sprite] = shifter
        }
    }

    /// Unclocked composition for callers supplying already-positioned fixture
    /// data. Real beam output uses the live shifters, including outside the crop.
    func captureSpriteTrace(startPixel: Int, endPixel: Int) {
        let activeMask = activeVisibleSpriteMask()
        guard activeMask != 0 else { return }
        guard spriteTraceLine == rasterLine else { return }

        for sprite in stride(from: 7, through: 0, by: -1) {
            let spriteMask = UInt8(1 << sprite)
            guard activeMask & spriteMask != 0 else { continue }
            for x in startPixel..<endPixel {
                guard let color = spritePixelColor(sprite: sprite, x: x) else { continue }
                recordSpritePixel(sprite: sprite, x: x, color: color,
                                  foreground: displayForegroundAtTracePixel(x),
                                  previousSprites: spriteTraceSpriteMask[x], capture: true)
            }
        }
    }

    private func recordSpritePixel(sprite: Int, x: Int, color: UInt32, foreground: Bool,
                                   previousSprites: UInt8, capture: Bool, collisionStage: Int? = nil,
                                   colorRegister: UInt8 = 0) {
        let mask = UInt8(1 << sprite)
        var pendingCollisions: UInt16 = 0
        if previousSprites != 0 && previousSprites & mask == 0 {
            if collisionStage != nil { pendingCollisions |= UInt16(previousSprites | mask) }
            else { latchSpriteCollision(previousSprites | mask) }
        }
        if foreground {
            if collisionStage != nil { pendingCollisions |= UInt16(mask) << 8 }
            else { latchSpriteDataCollision(mask) }
        }
        if collisionStage == 1 { collisionPipeline1 |= pendingCollisions }
        else { collisionPipeline2 |= pendingCollisions }
        guard capture else { return }
        if spriteTraceSpriteMask[x] == 0 { spriteTraceTouchedPixels.append(x) }
        spriteTraceSpriteMask[x] |= mask
        // Sprite priority is resolved before foreground priority: a hidden
        // higher-priority sprite still blocks every lower-priority sprite.
        spriteTraceValid[x] = true
        spriteTraceColor[x] = color
        spriteTraceColorRegister[x] = colorRegister
        spriteTracePriorityBehindBG[x] = spritePriority & mask != 0
        spriteTraceDisplayForeground[x] = foreground
        spriteTraceHasSamples = true
    }

    private func updateColorOutput(register: UInt8, value: UInt8) {
        guard cpuPhaseActive, rasterTraceLine == rasterLine else { return }
        // Color selection follows the data/priority pipeline. A phi2 write
        // changes colors eleven dots before the next whole-cycle sample,
        // without moving the sprite data or changing collision occupancy.
        let period = videoStandard == .pal ? 504 : 512
        let first = beamX(atDot: 0) - 3 + period
        if register <= 0x24 {
            let shift = register == 0x20 ? 16 : Int(register - 0x21) * 4
            let mask = UInt32(15) << shift
            for dot in 0..<11 {
                let x = (first + dot) % period
                if x < VIC.screenWidth && rasterTraceValid[x] {
                    rasterTraceColors[x] = (rasterTraceColors[x] & ~mask) | UInt32(value & 15) << shift
                }
            }
        } else {
            for dot in 0..<11 {
                let x = (first + dot) % period
                if x < VIC.screenWidth && spriteTraceValid[x] && spriteTraceColorRegister[x] == register {
                    spriteTraceColor[x] = ColorPalette.rgba[Int(value & 15)]
                }
            }
        }
    }

    private func applySpriteMulticolorChange(from previous: UInt8) {
        let changed = previous ^ spriteMulticolor
        for sprite in 0..<8 where changed & (1 << sprite) != 0 {
            guard spriteShifters[sprite].active else { continue }
            // Enabling multicolor holds the decoded hires pixel for the first
            // half-pair; disabling it releases the latch at the next dot/bit.
            spriteShifters[sprite].multicolorSecondBit = spriteMulticolor & (1 << sprite) != 0
        }
    }

    func activeVisibleSpriteMask() -> UInt8 {
        var mask: UInt8 = 0
        for sprite in 0..<8 where spriteDisplay[sprite] || spriteShifters[sprite].active {
            mask |= UInt8(1 << sprite)
        }
        return mask
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
        let wrap = videoStandard == .pal ? 504 : 512
        guard sx < wrap else { return nil }
        var localX = x - sx
        if localX < 0 {
            localX += wrap
        }
        let width = spriteExpandX & (1 << sprite) != 0 ? 48 : 24
        return localX >= 0 && localX < width ? localX : nil
    }

    func displayForegroundAtTracePixel(_ x: Int) -> Bool {
        guard x >= 0 && x < VIC.screenWidth else { return false }
        guard rasterTraceLine == rasterLine,
              rasterTraceValid[x],
              rasterTraceGraphicsOutput[x] else {
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

        let readMem = readMemory
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
            charCode = readMem?(screenBase + UInt16(vc)) ?? 0
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
                pixelData = readMem?(bitmapAddr) ?? 0
            } else {
                let glyphCode = columnExtendedBGMode ? (charCode & 0x3F) : charCode
                let charAddr = charBase + UInt16(glyphCode) * 8 + UInt16(context.pixelRow)
                pixelData = readMem?(charAddr) ?? 0
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
        // Matrix data arrives in hardware cycles 15-54 phi2, before the
        // corresponding glyph/bitmap fetch in cycles 16-55 phi1.
        if case let .badLineCharacterFetch(column) = busPhase, column < 40 {
            if !matrixDMAActive {
                matrixDMAActive = true
                badLineFetchMask = 0
                displayLineBufferValid = false
                displayLineBufferBase = videoCounterBase
            }
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

            let readMem = readMemory
            let screenBase = UInt16((memoryPointers >> 4) & 0x0F) * 0x0400
            let address = screenBase + 0x03F8 + UInt16(sprite)
            if recordsBusAccessTraces {
                lastLowPhaseMemoryReads.append(address)
            }
            spritePointers[sprite] = readMem?(address) ?? 0
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
        // ECM masks idle-state g-accesses, not the separate i-access slots.
        let address: UInt16 = 0x3FFF
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
        triggerLightPen(x: beamX(atDot: 8), y: Int(rasterLine))
    }

    func fetchCharData(column: Int) {
        if recordsBusAccessTraces {
            lastHighPhaseMemoryReads.removeAll(keepingCapacity: true)
            lastHighPhaseColorRAMReads.removeAll(keepingCapacity: true)
        }

        let index = videoMatrixLineIndex
        guard index < 40 else { return }
        if badLineFetchUsesUnstableStartupData(column: column) {
            lineBuffer[index] = 0xFF
            colorBuffer[index] = (readCPUDataBus?() ?? 0xFF) & 0x0F
            badLineFetchMask |= UInt64(1) << UInt64(index)
            displayLineBufferValid = badLineFetchMask == (UInt64(1) << 40) - 1
            return
        }

        let screenBase = UInt16((memoryPointers >> 4) & 0x0F) * 0x0400
        let vc = UInt16(videoCounter & 0x3FF)
        let screenAddress = screenBase + vc
        if recordsBusAccessTraces {
            lastHighPhaseMemoryReads.append(screenAddress)
        }
        let charCode = readMemory?(screenAddress) ?? 0
        lineBuffer[index] = charCode
        if recordsBusAccessTraces {
            lastHighPhaseColorRAMReads.append(vc)
        }
        colorBuffer[index] = (readColorRAM?(vc) ?? 0) & 0x0F

        badLineFetchMask |= UInt64(1) << UInt64(index)
        displayLineBufferValid = badLineFetchMask == (UInt64(1) << 40) - 1
    }

    func badLineFetchUsesUnstableStartupData(column: Int) -> Bool {
        guard let startCycle = badLineStartCycle, startCycle >= 12 else { return false }
        return column + 14 < startCycle + 3
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
        if graphicsBufferLine == rasterLine {
            return (graphicsBufferBase / 40, graphicsBufferBase, graphicsBufferPixelRow)
        }
        // Unclocked snapshot composition only. Clocked output uses the fetched
        // line above, including its RC before the cycle-58 increment.
        let topBorder: Int = rows25 ? VIC.displayTop : VIC.displayTop + 4
        let bottomBorder: Int = rows25 ? VIC.displayBottom : VIC.displayBottom - 4
        let line = Int(rasterLine)
        let graphicsY = line - VIC.displayTop

        guard displayActive && graphicsY >= 0 else { return nil }
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

        if column == 0 || graphicsBufferLine != rasterLine {
            graphicsFetchMask = 0
            graphicsBufferValid = false
            graphicsBufferLine = rasterLine
            graphicsBufferBase = videoCounterBase
            graphicsBufferPixelRow = rowCounter
        }

        let readMem = readMemory
        let charBase: UInt16
        if bitmapMode {
            charBase = UInt16((memoryPointers >> 3) & 0x01) * 0x2000
        } else {
            charBase = UInt16((memoryPointers >> 1) & 0x07) * 0x0800
        }

        let matrixAvailable = displayActive && videoMatrixLineIndex < 40
        let charCode = matrixAvailable ? lineBuffer[videoMatrixLineIndex] : 0
        let colorData = matrixAvailable ? colorBuffer[videoMatrixLineIndex] : 0
        let address: UInt16
        if !displayActive {
            address = extendedBGMode ? 0x39FF : 0x3FFF
        } else if bitmapMode {
            let bitmapAddress = charBase | UInt16(videoCounter & 0x3FF) << 3 | UInt16(rowCounter)
            address = extendedBGMode ? bitmapAddress & 0x39FF : bitmapAddress
        } else {
            let glyphCode = extendedBGMode ? (charCode & 0x3F) : charCode
            address = charBase | UInt16(glyphCode) << 3 | UInt16(rowCounter)
        }
        if recordTrace { lastLowPhaseMemoryReads.append(address) }
        graphicsBuffer[column] = readMem?(address) ?? 0
        graphicsBufferControlReg1[column] = controlReg1
        graphicsBufferControlReg2[column] = controlReg2
        graphicsBufferMemoryPointers[column] = memoryPointers
        graphicsBufferBackgroundColors[column] = backgroundColor
        graphicsBufferScreenBytes[column] = charCode
        graphicsBufferColorData[column] = colorData

        graphicsFetchMask |= UInt64(1) << UInt64(column)
        graphicsBufferValid = graphicsFetchMask == (UInt64(1) << 40) - 1
        if displayActive {
            videoCounter = (videoCounter + 1) & 0x3FF
            videoMatrixLineIndex += 1
        }
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
        let useRasterTrace = rasterTraceHasSamples && rasterTraceLine == rasterLine

        // Render character/bitmap graphics for this line.
        graphicsLineScratch.withUnsafeMutableBufferPointer { $0.update(repeating: bgCol) }
        foregroundMaskScratch.withUnsafeMutableBufferPointer { $0.update(repeating: false) }
        if useRasterTrace {
            // -2: no graphics byte, -1: constant color, 0...3: D021...D024.
            backgroundColorSourceScratch.withUnsafeMutableBufferPointer { $0.update(repeating: -2) }
        }

        let renderGraphics = useRasterTrace
            ? rasterTraceHasGraphicsOutput
            : lineInDisplay && displayActive && displayEnabled
        if renderGraphics {
            let clocked = graphicsBufferLine == rasterLine
            let charRow = max(0, graphicsY) / 8
            let rowBase = clocked ? graphicsBufferBase : charRow * 40
            let pixelRow = clocked ? graphicsBufferPixelRow
                : (hasAnyLatchedMatrixColumn(rowBase: rowBase) ? rowCounter & 7 : max(0, graphicsY) % 8)

            renderGraphicsLine(
                &graphicsLineScratch,
                foregroundMask: &foregroundMaskScratch,
                charRow: charRow,
                pixelRow: pixelRow,
                leftBorder: VIC.displayLeft,
                rowBase: rowBase,
                markBackgroundPixel: { pixel, backgroundIndex in
                    guard pixel >= 0 && pixel < VIC.screenWidth else { return }
                    self.backgroundColorSourceScratch[pixel] = Int8(backgroundIndex)
                }
            )
        }

        // Compose graphics and sprites before the border. The side borders hide
        // graphics but do not suppress their collision signal.
        finalLineScratch.withUnsafeMutableBufferPointer { line in
            spriteForegroundMaskScratch.withUnsafeMutableBufferPointer { spriteForeground in
                for px in 0..<VIC.screenWidth {
                    let traceValid = useRasterTrace && rasterTraceValid[px]
                    let graphicsOutput = traceValid ? rasterTraceGraphicsOutput[px] : renderGraphics

                    let backgroundIndex = Int(backgroundColorSourceScratch[px])
                    if traceValid && (!graphicsOutput || backgroundIndex == -2) {
                        line[px] = ColorPalette.rgba[Int(rasterTraceIdleColor(pixel: px))]
                    } else if graphicsOutput {
                        if traceValid && backgroundIndex >= 0 {
                            line[px] = ColorPalette.rgba[Int(rasterTraceBackgroundColor(backgroundIndex, pixel: px) & 0x0F)]
                        } else {
                            line[px] = graphicsLineScratch[px]
                        }
                    } else {
                        let color = traceValid ? rasterTraceBackgroundColor(0, pixel: px) : backgroundColor[0]
                        line[px] = ColorPalette.rgba[Int(color & 0x0F)]
                    }
                    spriteForeground[px] = graphicsOutput ? foregroundMaskScratch[px] : false
                }
            }
        }

        // An empty completed beam trace is meaningful: a sprite enabled after
        // its X position must not be painted retroactively at end of line.
        if useRasterTrace && spriteTraceLine == rasterLine {
            applyTouchedSpriteTrace(&finalLineScratch)
        } else {
            renderSprites(&finalLineScratch, fbY: fbY, foregroundMask: spriteForegroundMaskScratch)
        }

        finalLineScratch.withUnsafeMutableBufferPointer { line in
            for px in 0..<VIC.screenWidth {
                let traceValid = useRasterTrace && rasterTraceValid[px]
                let open = traceValid ? rasterTraceDisplayOpen[px]
                    : lineInDisplay && displayActive && displayEnabled && px >= leftBorder && px < rightBorder
                if !open {
                    let color = traceValid ? UInt8((rasterTraceColors[px] >> 16) & 15) : borderColor
                    line[px] = ColorPalette.rgba[Int(color & 0x0F)]
                }
            }
        }

        framebuffer.withUnsafeMutableBufferPointer { destination in
            finalLineScratch.withUnsafeBufferPointer { source in
                precondition(lineOffset + VIC.screenWidth <= destination.count)
                precondition(source.count >= VIC.screenWidth)
                destination.baseAddress!.advanced(by: lineOffset)
                    .update(from: source.baseAddress!, count: VIC.screenWidth)
            }
        }

    }

    func applyTouchedSpriteTrace(_ line: inout [UInt32]) {
        for x in spriteTraceTouchedPixels where spriteTraceValid[x] {
            let hasForeground = spriteTraceDisplayForeground[x]
            if !spriteTracePriorityBehindBG[x] || !hasForeground {
                line[x] = spriteTraceColor[x]
            }
        }
    }

    private func latchSpriteCollision(_ mask: UInt8) {
        let wasClear = spriteSpriteCollision == 0
        spriteSpriteCollision |= mask
        if wasClear { raiseInterrupt(0x04) }
    }

    private func latchSpriteDataCollision(_ mask: UInt8) {
        let wasClear = spriteDataCollision == 0
        spriteDataCollision |= mask
        if wasClear { raiseInterrupt(0x02) }
    }

    func rasterTraceBackgroundColor(_ index: Int, pixel: Int) -> UInt8 {
        let shift = (1...3).contains(index) ? index * 4 : 0
        return UInt8((rasterTraceColors[pixel] >> shift) & 15)
    }

    private func rasterTraceIdleColor(pixel: Int) -> UInt8 {
        let state = rasterTraceColors[pixel]
        let matrix = UInt8(truncatingIfNeeded: state >> 20)
        switch (state >> 28) & 7 {
        case 2: return matrix & 15
        case 4: return rasterTraceBackgroundColor(Int(matrix >> 6), pixel: pixel)
        case 5...7: return 0
        default: return UInt8(state & 15)
        }
    }

    func renderGraphicsLine(_ line: inout [UInt32], foregroundMask: inout [Bool], charRow: Int, pixelRow: Int,
                            leftBorder: Int,
                            rowBase: Int? = nil,
                            markBackgroundPixel: ((Int, Int) -> Void)? = nil) {
        let readMem = readMemory

        for col in 0..<40 {
            let rowBase = rowBase ?? charRow * 40
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
                charCode = readMem?(screenAddr) ?? 0
                colorData = (readColorRAM?(UInt16(vc)) ?? 0x0E) & 0x0F
            }

            let pixelData: UInt8
            if useColumnTrace {
                pixelData = graphicsBuffer[col]
            } else if columnBitmapMode {
                let bitmapAddr = charBase + UInt16(vc) * 8 + UInt16(pixelRow)
                pixelData = readMem?(bitmapAddr) ?? 0
            } else {
                let glyphCode = columnExtendedBGMode ? (charCode & 0x3F) : charCode
                let charAddr = charBase + UInt16(glyphCode) * 8 + UInt16(pixelRow)
                pixelData = readMem?(charAddr) ?? 0
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
                maskInvalidECMOutput(line: &line, xPos: xPos, markBackgroundPixel: markBackgroundPixel)
            }
        }
    }

    func maskInvalidECMOutput(line: inout [UInt32], xPos: Int,
                              markBackgroundPixel: ((Int, Int) -> Void)? = nil) {
        let black = ColorPalette.rgba[0]
        for bit in 0..<8 {
            let px = xPos + bit
            guard px >= 0 && px < VIC.screenWidth else { continue }
            line[px] = black
            markBackgroundPixel?(px, -1)
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
                markBackgroundPixel?(px, -1)
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
                markBackgroundPixel?(px0, -1)
                markBackgroundPixel?(px1, -1)
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
                markBackgroundPixel?(px, -1)
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
                    markBackgroundPixel?(px0, -1)
                    markBackgroundPixel?(px1, -1)
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
            markBackgroundPixel?(px, -1)
            if pixelData & (0x80 >> bit) != 0 {
                line[px] = fgColor
                foregroundMask[px] = true
            } else {
                line[px] = bgColor
            }
        }
    }

    // MARK: - Sprites

    // Zero-based indices: PAL p0 is hardware cycle 58, NTSC R8 p0 is 59.
    // Verified against hardware-checked phi1timing PAL/NTSC programs. Pointer
    // and byte 0 share a cycle; bytes 1 and 2 occupy the next cycle's phases.
    var spriteDMAFirstStartCycle: Int { videoStandard == .pal ? 57 : 58 }

    func spriteDMAStartCycle(for sprite: Int) -> Int? {
        guard sprite >= 0 && sprite < 8 else { return nil }
        let unwrappedCycle = spriteDMAFirstStartCycle + sprite * 2
        return unwrappedCycle % rasterCyclesPerLine
    }

    func spritePointerSlotForCurrentCycle() -> Int? {
        spriteDMAFetchSlotForCurrentCycle()
    }

    func spriteDMASlotForCurrentCycle() -> Int? {
        guard let offset = spriteDMACycleOffset else { return nil }
        return offset / 2
    }

    func spriteMiddleByteSlotForCurrentCycle() -> Int? {
        guard let offset = spriteDMACycleOffset, offset & 1 == 1 else { return nil }
        return offset / 2
    }

    func spriteBAWarningSlotForCurrentCycle() -> Int? {
        let firstStart = spriteDMAFirstStartCycle
        let lastWrappedStart = firstStart + 14 - rasterCyclesPerLine
        if rasterCycle >= lastWrappedStart && rasterCycle < firstStart - 3 { return nil }
        // Check upcoming DMA starts in distance order. Start slots are unique,
        // so this is the same minimum as the former map/filter/sort pipeline.
        for distance in 1...3 {
            let offset = (rasterCycle + distance - firstStart + rasterCyclesPerLine) % rasterCyclesPerLine
            guard offset >= 0, offset < 16, offset & 1 == 0 else { continue }
            let sprite = offset / 2
            if spriteDMAEligible(sprite) {
                return sprite
            }
        }
        return nil
    }

    func spriteDMAFetchSlotForCurrentCycle() -> Int? {
        guard let offset = spriteDMACycleOffset, offset & 1 == 0 else { return nil }
        return offset / 2
    }

    private var spriteDMACycleOffset: Int? {
        guard rasterCycle >= 0, rasterCycle < rasterCyclesPerLine else { return nil }
        let offset = (rasterCycle - spriteDMAFirstStartCycle + rasterCyclesPerLine) % rasterCyclesPerLine
        return offset < 16 ? offset : nil
    }

    func spriteLineRow(for sprite: Int) -> Int? {
        spriteLineByteOffset(for: sprite).map { $0 / 3 }
    }

    func spriteLineByteOffset(for sprite: Int) -> Int? {
        spriteDMAEligible(sprite) ? spriteMC[sprite] : nil
    }

    func spriteDMAEligible(_ sprite: Int) -> Bool {
        guard (0..<8).contains(sprite) else { return false }
        return spriteDMACheckMask & (1 << sprite) != 0
    }

    func latchSpriteDMAEligibilityForCurrentLine() {
        spriteDMACheckLine = Int(rasterLine)
        let lowRaster = UInt8(truncatingIfNeeded: rasterLine)
        for sprite in 0..<8 where !spriteDMAEligible(sprite) {
            let mask = UInt8(1 << sprite)
            if spriteEnabled & mask != 0 && spriteY[sprite] == lowRaster {
                spriteDMACheckMask |= mask
                spriteMCBase[sprite] = 0
                spriteYExpFF[sprite] = true
            }
        }
    }

    func latchSpriteDisplayForCurrentLine() {
        let lowRaster = UInt8(truncatingIfNeeded: rasterLine)
        for sprite in 0..<8 {
            spriteMC[sprite] = spriteMCBase[sprite]
            if !spriteDMAEligible(sprite) {
                spriteDisplay[sprite] = false
                // Disable new X matches, but let an already shifting final
                // row finish, including expanded sprites in the right border.
            } else if spriteY[sprite] == lowRaster {
                spriteDisplay[sprite] = true
            }
        }
    }

    // PAL cycle 16 phi1: all eight fetch bursts are complete. MCBASE and DMA
    // survive scanline/frame boundaries and changes to the programmed Y.
    func advanceSpriteCounters() {
        for sprite in 0..<8 {
            let mask = UInt8(1 << sprite)
            if spriteYExpFF[sprite] {
                spriteMCBase[sprite] = spriteCrunchPendingMask & mask != 0
                    ? spriteCrunchMCBase(base: spriteMCBase[sprite], mc: spriteMC[sprite])
                    : spriteMC[sprite]
            }
            if spriteMCBase[sprite] == 63 { spriteDMACheckMask &= ~mask }
        }
        spriteCrunchPendingMask = 0
    }

    func applySpriteYExpansionWrite(newValue: UInt8) {
        for sprite in 0..<8 where newValue & (1 << sprite) == 0 {
            // A write in cycle 15 phi2 affects the following cycle's base
            // transfer, not MC immediately. Later writes can stretch rows.
            if !spriteYExpFF[sprite] && rasterCycle == 14 {
                spriteCrunchPendingMask |= UInt8(1 << sprite)
            }
            spriteYExpFF[sprite] = true
        }
    }

    func spriteCrunchMCBase(base: Int, mc: Int) -> Int {
        ((0x2A & (base & mc)) | (0x15 & (base | mc))) & 0x3F
    }

    func fetchSpriteData(sprite: Int) {
        spriteFetchInFlight = nil
        guard sprite >= 0 && sprite < 8 else { return }
        guard activeSpriteDMASlot == sprite,
              let byteOffset = spriteLineByteOffset(for: sprite) else {
            return
        }
        spriteFetchInFlight = (sprite, UInt16(spritePointers[sprite]) * 64, byteOffset)
        spriteLastFetchedByteOffset[sprite] = byteOffset
        fetchSpriteByte(sprite: sprite, index: 0, lowPhase: false, recordTrace: recordsBusAccessTraces)
    }

    func spriteMiddleByteOffset(for sprite: Int) -> Int? {
        guard sprite >= 0 && sprite < 8 else { return nil }
        guard spriteMiddleByteSlotForCurrentCycle() == sprite else { return nil }

        if let fetch = spriteFetchInFlight, fetch.sprite == sprite {
            return fetch.offset
        }
        return nil
    }

    func fetchSpriteMiddleByte(sprite: Int, recordTrace: Bool) {
        guard sprite >= 0 && sprite < 8 else { return }
        guard spriteMiddleByteOffset(for: sprite) != nil else { return }
        fetchSpriteByte(sprite: sprite, index: 1, lowPhase: true, recordTrace: recordTrace)
    }

    func fetchSpriteLastByte(sprite: Int) {
        fetchSpriteByte(sprite: sprite, index: 2, lowPhase: false, recordTrace: recordsBusAccessTraces)
        spriteFetchInFlight = nil
    }

    private func fetchSpriteByte(sprite: Int, index: Int, lowPhase: Bool, recordTrace: Bool) {
        guard let fetch = spriteFetchInFlight, fetch.sprite == sprite else { return }
        let offset = (fetch.offset + index) & 0x3F
        let address = fetch.pointer | UInt16(offset)
        if recordTrace {
            if lowPhase { lastLowPhaseMemoryReads.append(address) }
            else { lastHighPhaseMemoryReads.append(address) }
        }
        let value = readMemory?(address) ?? 0
        spriteLineData[sprite][index] = value
        let shift = (2 - index) * 8
        spriteShifters[sprite].data = (spriteShifters[sprite].data & ~(0xFF << shift)) | UInt32(value) << shift
        spriteMC[sprite] = (offset + 1) & 0x3F
        spriteLastFetchedMC[sprite] = spriteMC[sprite]
    }

    func renderSprites(_ line: inout [UInt32], fbY: Int, foregroundMask: [Bool]? = nil) {
        let activeMask = activeVisibleSpriteMask()
        guard activeMask != 0 else { return }

        let background = ColorPalette.rgba[Int(backgroundColor[0] & 0x0F)]
        spriteOccupancyGeneration &+= 1
        if spriteOccupancyGeneration == 0 {
            spriteOccupancyGeneration = 1
            for x in 0..<VIC.screenWidth {
                spriteOccupancyGenerationScratch[x] = 0
            }
        }
        spriteSourceLineScratch.withUnsafeMutableBufferPointer { destination in
            line.withUnsafeBufferPointer { source in
                destination.baseAddress!.update(from: source.baseAddress!, count: VIC.screenWidth)
            }
        }

        func plotSpritePixel(sprite: Int, x: Int, color: UInt32, behindBG: Bool) {
            guard x >= 0 && x < VIC.screenWidth else { return }

            let spriteMask = UInt8(1 << sprite)
            if spriteOccupancyGenerationScratch[x] != spriteOccupancyGeneration {
                spriteOccupancyGenerationScratch[x] = spriteOccupancyGeneration
                spriteOccupancyScratch[x] = 0
            }
            if spriteOccupancyScratch[x] != 0 {
                latchSpriteCollision(spriteOccupancyScratch[x] | spriteMask)
            }
            spriteOccupancyScratch[x] |= spriteMask

            let hasForeground = foregroundMask?[x] ?? (spriteSourceLineScratch[x] != background)
            if hasForeground {
                latchSpriteDataCollision(spriteMask)
            }

            if !behindBG || !hasForeground {
                line[x] = color
            } else {
                line[x] = spriteSourceLineScratch[x]
            }
        }

        // Render sprites from back to front (sprite 7 first, 0 last = highest priority)
        for i in stride(from: 7, through: 0, by: -1) {
            guard activeMask & UInt8(1 << i) != 0 else { continue }

            let sx = Int(spriteX[i] & 0x01FF)
            let wrap = videoStandard == .pal ? 504 : 512
            guard sx < wrap else { continue }
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
                        let px = (sx + bit * xWidth + sub) % wrap
                        plotSpritePixel(sprite: i, x: px, color: pixColor, behindBG: behindBG)
                    }
                }
            } else {
                for bit in 0..<24 {
                    guard fullData & (1 << (23 - bit)) != 0 else { continue }
                    let xWidth = expandX ? 2 : 1
                    for sub in 0..<xWidth {
                        let px = (sx + bit * xWidth + sub) % wrap
                        plotSpritePixel(sprite: i, x: px, color: color, behindBG: behindBG)
                    }
                }
            }
        }
    }

    // MARK: - Color RAM callback

    /// Callback to read color RAM (from MemoryMap)
    public var readColorRAM: ((UInt16) -> UInt8)?
    /// CPU D0-D3 feed VIC color inputs while AEC leaves the CPU on the bus.
    var readCPUDataBus: (() -> UInt8)?

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
        if cpuPhaseActive {
            if register < 0x10 && register & 1 == 0 {
                spriteXWriteThisCycle = (UInt8(register), UInt8(truncatingIfNeeded: spriteX[Int(register) / 2]))
            } else if register == 0x10 {
                spriteXWriteThisCycle = (0x10, spriteXMSB)
            }
            if (0x20...0x2E).contains(register) { updateColorOutput(register: UInt8(register), value: value) }
        }
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
            // A phi2 CPU store cannot retroactively start this cycle's
            // c-access. Evaluate at the next phi1, using its raster Y.
            if cpuPhaseActive {
                badLineUpdatePending = true
            } else {
                checkBadLine()
            }
            checkRasterInterrupt()

        case 0x12:
            rasterCompare = (rasterCompare & 0x100) | UInt16(value)
            checkRasterInterrupt()

        case 0x15: spriteEnabled = value
        case 0x16:
            controlReg2 = value
            if cpuPhaseActive, (15..<55).contains(rasterCycle), graphicsBufferLine == rasterLine {
                // Phi1 fetched this byte, but its first possible output dot is
                // in phi2. XSCROLL selects that load point after the CPU write.
                let column = rasterCycle - 15
                graphicsBufferControlReg2[column] = (graphicsBufferControlReg2[column] & ~7) | (value & 7)
            }
        case 0x17:
            spriteExpandY = value
            applySpriteYExpansionWrite(newValue: value)
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
        case 0x1C:
            let previous = spriteMulticolor
            spriteMulticolor = value
            if cpuPhaseActive { spriteMulticolorWriteThisCycle = previous }
            else { applySpriteMulticolorChange(from: previous) }
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
