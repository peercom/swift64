import Foundation
import Emu6502

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
    private var pendingGraphicsAddressBitmapMode: Bool?
    private var pendingGraphicsAddressECM: Bool?
    /// Whether DEN was observed on raster $30, arming bad lines for this frame.
    var badLineDENLatched: Bool = false
    /// Prevents repeated raster IRQs after multiple compare writes on the same rasterline.
    var rasterIRQTriggeredThisLine: Bool = false
    private var rasterCompareMatched = false
    private var frameStartPending = false
    /// Y resets one clock after X wraps at frame end. Physical scanline
    /// coordinates still wrap normally for DMA slots and framebuffer geometry.
    private var rasterCounter: UInt16 {
        frameStartPending ? UInt16(rasterLinesPerFrame - 1) : rasterLine
    }
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

    /// BA as an expansion-port bus master samples it at the start of the
    /// cycle. When a sprite's DMA is switched on in the same phi1 as its BA
    /// warning begins (sprite 0 in cycle 55), BA falls too late in that cycle
    /// for the REC, which still performs its access; the 6510 and the PLA
    /// see it low (`reutiming2` e/e3 hardware references).
    public var baLineLowAtCycleStart: Bool {
        guard baLineLow else { return false }
        if case let .spriteBAWarning(sprite) = busPhase, spriteDMASwitchedOnMask & (1 << sprite) != 0 {
            return false
        }
        return true
    }

    /// VIC-II AEC line state. A low AEC means the CPU is no longer allowed to drive the bus.
    public var aecLineLow: Bool {
        switch busPhase {
        case let .badLineCharacterFetch(column):
            return !badLineFetchUsesUnstableStartupData(column: column)
        case .spriteDMA(let sprite):
            return !(sprite == 0 && spriteZeroDMAStartedLate && rasterCycle == spriteDMAFirstStartCycle)
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
    private var cpuPhaseInternalDataBus: UInt8 = 0xFF
    private var spriteXWriteThisCycle: (register: UInt8, previous: UInt8)?
    private var spriteMulticolorWriteThisCycle: UInt8?
    /// Sprite data pointer bytes latched during the low-phase sprite-pointer slots.
    var spritePointers = [UInt8](repeating: 0, count: 8)
    /// Rasterline for which sprite DMA enable/Y-match has been sampled.
    var spriteDMACheckLine: Int?
    /// Persistent DMA enable bits. Y/enable writes only start inactive DMA;
    /// an active transfer ends when MCBASE reaches 63, not at a Y-derived height.
    var spriteDMACheckMask: UInt8 = 0
    /// Starting sprite 0 at the second Y comparison leaves only two BA
    /// warning clocks before its first high-phase read, rather than three.
    private var spriteZeroDMAStartedLate = false
    /// Sprites whose DMA was switched on in the current cycle's phi1 check
    /// (cleared at the start of every cycle).
    private var spriteDMASwitchedOnMask: UInt8 = 0

    /// Per-visible-pixel raster state captured as the beam advances. This keeps
    /// simple raster color bars and mid-line border mode changes observable even
    /// though the heavier graphics composition still happens at end of line.
    var rasterTraceLine: UInt16?
    var rasterTraceHasSamples: Bool = false
    var rasterTraceHasDisplayOpen: Bool = false
    var rasterTraceHasGraphicsOutput: Bool = false
    private var rasterTraceHasGraphicsModeChanges = false
    var rasterTraceValid = [Bool](repeating: false, count: VIC.screenWidth)
    var rasterTraceDisplayOpen = [Bool](repeating: false, count: VIC.screenWidth)
    var rasterTraceGraphicsOutput = [Bool](repeating: false, count: VIC.screenWidth)
    // Colors/matrix occupy bits 0-27; color mode 28-30, data MCM 31,
    // background BMM 32, and invalid-mode release hold 33.
    private var rasterTraceColors = [UInt64](repeating: 0, count: VIC.screenWidth)
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
        pendingGraphicsAddressBitmapMode = nil
        pendingGraphicsAddressECM = nil
        badLineDENLatched = false
        rasterIRQTriggeredThisLine = false
        rasterCompareMatched = false
        frameStartPending = false
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
        cpuPhaseInternalDataBus = 0xFF
        spriteXWriteThisCycle = nil
        spriteMulticolorWriteThisCycle = nil
        spritePointers = [UInt8](repeating: 0, count: 8)
        spriteDMACheckLine = nil
        spriteDMACheckMask = 0
        spriteZeroDMAStartedLate = false
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
        cpuPhaseInternalDataBus = 0xFF
        spriteDMASwitchedOnMask = 0
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
        // The expansion decision precedes this cycle's CPU register write.
        // A later clear still forces the FF high; a set cannot toggle it back.
        if rasterCycle == spriteDMAFirstStartCycle - 2 {
            for sprite in 0..<8 where spriteDMAEligible(sprite) && spriteExpandY & (1 << sprite) != 0 {
                spriteYExpFF[sprite].toggle()
            }
        }
        if rasterCycle == spriteDMAFirstStartCycle {
            latchSpriteDisplayForCurrentLine()
        }

        let delayDisplayEntry = pendingDisplayEntry && !wasDisplayActive && displayActive
        if delayDisplayEntry { displayActive = false }
        performLowPhaseAccess()
        pendingGraphicsAddressBitmapMode = nil
        pendingGraphicsAddressECM = nil
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
            clockSpritePixels(startDot: 2, dotCount: 1, collisionStage: 1,
                              oldX: true, multicolorBits: previous)
            applySpriteMulticolorChange(from: previous)
            clockSpritePixels(startDot: 3, dotCount: 1, collisionStage: 1, oldX: true)
        } else {
            clockSpritePixels(startDot: 2, dotCount: 2, collisionStage: 1, oldX: true)
        }
        clockSpritePixels(startDot: 4, dotCount: 4, collisionStage: 2)
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
        } else if frameStartPending && rasterCycle == 1 {
            frameStartPending = false
            refreshCounter = 0xFF
            videoCounterBase = 0
            badLineDENLatched = false
            lightPenLatchedThisFrame = false
            rasterIRQTriggeredThisLine = false
            checkRasterInterrupt()
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
            frameStartPending = true
            frameReady = true
        } else {
            rasterIRQTriggeredThisLine = false
        }
        clearRasterTrace()
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
        rasterTraceHasGraphicsModeChanges = false
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
        clockSpritePixels(startDot: 0, dotCount: 2, collisionStage: 1)
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

        let colors = UInt64(borderColor & 15) << 16
            | UInt64(backgroundColor[3] & 15) << 12
            | UInt64(backgroundColor[2] & 15) << 8
            | UInt64(backgroundColor[1] & 15) << 4
            | UInt64(backgroundColor[0] & 15)
            | UInt64(controlReg1 & 0x60) << 24
            | UInt64(controlReg2 & 0x10) << 24
            | UInt64(controlReg2 & 0x10) << 27
            | UInt64(controlReg1 & 0x20) << 27

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
                        color[pixel] = colors | UInt64(graphicsOutputMatrix) << 20
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

    private func clockSpritePixels(startDot: Int, dotCount: Int, collisionStage: Int,
                                   oldX: Bool = false, multicolorBits: UInt8? = nil) {
        let startX = beamX(atDot: startDot)
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
            // The reload gate suppresses X matches through the pointer cycle
            // and the first three dots of the middle-byte cycle. Original
            // spritex hardware results put PAL sprite 0's first reuse at X=367.
            let reloadDots: Int
            if let offset = spriteDMACycleOffset, offset / 2 == sprite {
                reloadDots = offset & 1 == 0 ? 8 : 3
            } else {
                reloadDots = 0
            }
            for dot in 0..<dotCount {
                if startDot + dot < reloadDots {
                    shifter.remainingBits = 0
                    shifter.expansionSecondDot = false
                    shifter.multicolorSecondBit = false
                    shifter.pixel = 0
                    continue
                }
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
            let mask = UInt64(15) << shift
            for dot in 0..<11 {
                let x = (first + dot) % period
                if x < VIC.screenWidth && rasterTraceValid[x] {
                    rasterTraceColors[x] = (rasterTraceColors[x] & ~mask) | UInt64(value & 15) << shift
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

    private func updateGraphicsModeOutput(mask: UInt8, value: UInt8, firstDot: Int, shift: Int = 24) {
        guard cpuPhaseActive, rasterTraceLine == rasterLine else { return }
        rasterTraceHasGraphicsModeChanges = true
        // Mode selection follows the fetched data through a separate output
        // path. Do not change the address or contents of an earlier g-access.
        let packedMask = UInt64(mask) << shift
        for dot in firstDot..<4 {
            let x = beamX(atDot: dot)
            if x < VIC.screenWidth && rasterTraceValid[x] {
                rasterTraceColors[x] = (rasterTraceColors[x] & ~packedMask) | UInt64(value & mask) << shift
            }
        }
    }

    private func holdInvalidGraphicsOutput() {
        guard cpuPhaseActive, rasterTraceLine == rasterLine else { return }
        // Clearing BMM/MCM while ECM remains set releases black output
        // after the color selector: one dot on 6569, two on 6567R8.
        for dot in 0..<(videoStandard == .pal ? 1 : 2) {
            let x = beamX(atDot: dot)
            if x < VIC.screenWidth && rasterTraceValid[x] { rasterTraceColors[x] |= 1 << 33 }
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

        let x = VIC.displayLeft + column * 8 + Int(columnControlReg2 & 7) + bitOffset
        if rasterTraceHasGraphicsModeChanges, rasterTraceValid[x] {
            return graphicsOutputPixel(pixelData: pixelData, screenByte: charCode, colorByte: colorData,
                                       bit: bitOffset, pixel: x).foreground
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
        let value = readMemory?(address) ?? 0
        if let sprite = spriteMiddleByteSlotForCurrentCycle() {
            // Inactive sprite slots still load the shifter: phi1 supplies
            // the idle byte, while phi2 samples the internal register bus.
            latchSpriteDataByte(sprite: sprite, index: 1, value: value)
        }
    }

    func raiseInterrupt(_ flag: UInt8) {
        interruptRegister |= flag
        updateIRQLine()
    }

    func checkRasterInterrupt() {
        // The last phi2 write and the raster increment reach the comparator
        // together. Following the counter across that edge must not retrigger.
        if cpuPhaseActive && (rasterCycle == rasterCyclesPerLine - 1 || frameStartPending) { return }
        let matched = rasterCounter == rasterCompare
        let risingEdge = matched && !rasterCompareMatched
        rasterCompareMatched = matched
        guard risingEdge && !rasterIRQTriggeredThisLine else { return }
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
        triggerLightPen(x: beamX(atDot: 8), y: Int(rasterCounter))
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
        var address: UInt16
        if !displayActive {
            address = 0x3FFF
        } else if bitmapMode {
            address = charBase | UInt16(videoCounter & 0x3FF) << 3 | UInt16(rowCounter)
        } else {
            address = charBase | UInt16(charCode) << 3 | UInt16(rowCounter)
        }
        // BMM reaches the high-address selection before the low-address
        // selection. The first g-access after a CPU write uses the old
        // selection for A0-A7, with the new mode supplying A8-A13.
        if displayActive, let oldBitmapMode = pendingGraphicsAddressBitmapMode {
            let lowAddress = UInt16(oldBitmapMode ? videoCounter : Int(charCode)) << 3 | UInt16(rowCounter)
            address = (address & 0x3F00) | (lowAddress & 0xFF)
        }
        // ECM gates A9/A10 independently of the bitmap address selector.
        // A pending selection lasts only through the next low phase.
        if pendingGraphicsAddressECM ?? extendedBGMode { address &= 0x39FF }
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
        let mode = (state >> 28) & 7
        if mode >= 5 || state & (1 << 33) != 0 { return 0 }
        if mode & 5 == 0 && state & (1 << 32) != 0 { return matrix & 15 }
        switch mode {
        case 4: return rasterTraceBackgroundColor(Int(matrix >> 6), pixel: pixel)
        default: return UInt8(state & 15)
        }
    }

    private func graphicsOutputPixel(pixelData: UInt8, screenByte: UInt8, colorByte: UInt8,
                                     bit: Int, pixel: Int) -> (color: UInt8, foreground: Bool) {
        let mode = (rasterTraceColors[pixel] >> 28) & 7
        let bitmap = mode & 2 != 0
        let multicolor = mode & 1 != 0 && (bitmap || colorByte & 8 != 0)
        // The data latch and color selector see MCM at different times.
        // Replay from this byte's reload so a mode change can retain the
        // previous hires pixel for the second dot of a multicolor pair.
        var bits: UInt8 = 0
        var secondDot = false
        var previousMulticolor = false
        for dot in 0...bit {
            let sample = rasterTraceColors[pixel - bit + dot]
            let dataMulticolor = sample & 0x80000000 != 0 && (sample & 0x20000000 != 0 || colorByte & 8 != 0)
            if dot > 0 && dataMulticolor && !previousMulticolor { secondDot = true }
            let shifted = UInt16(pixelData) << dot
            if dataMulticolor {
                if !secondDot { bits = UInt8((shifted >> 6) & 3) }
                secondDot.toggle()
            } else {
                bits = UInt8((shifted >> 7) & 1) << 1
            }
            previousMulticolor = dataMulticolor
        }
        let foreground = bits & 2 != 0
        if mode >= 5 || rasterTraceColors[pixel] & (1 << 33) != 0 { return (0, foreground) }
        if multicolor {
            switch bits {
            case 0: return (rasterTraceBackgroundColor(0, pixel: pixel), false)
            case 1: return (bitmap ? screenByte >> 4 : rasterTraceBackgroundColor(1, pixel: pixel), false)
            case 2: return (bitmap ? screenByte & 15 : rasterTraceBackgroundColor(2, pixel: pixel), true)
            default: return (colorByte & (bitmap ? 15 : 7), true)
            }
        }
        if !foreground && mode & 4 == 0 && rasterTraceColors[pixel] & (1 << 32) != 0 {
            return (screenByte & 15, false)
        }
        if bitmap && foreground { return (screenByte >> 4, true) }
        if foreground { return (colorByte & 15, true) }
        return (rasterTraceBackgroundColor(mode == 4 ? Int(screenByte >> 6) : 0, pixel: pixel), false)
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

            if useColumnTrace, rasterTraceHasGraphicsModeChanges, rasterTraceLine == rasterLine {
                for bit in 0..<8 {
                    let pixel = xPos + bit
                    guard pixel >= 0, pixel < VIC.screenWidth, rasterTraceValid[pixel] else { continue }
                    let output = graphicsOutputPixel(pixelData: pixelData, screenByte: charCode,
                                                     colorByte: colorData, bit: bit, pixel: pixel)
                    line[pixel] = ColorPalette.rgba[Int(output.color)]
                    foregroundMask[pixel] = output.foreground
                    markBackgroundPixel?(pixel, -1)
                }
                continue
            }

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
                spriteDMASwitchedOnMask |= mask
                if sprite == 0 { spriteZeroDMAStartedLate = rasterCycle == spriteDMAFirstStartCycle - 2 }
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
            } else if spriteY[sprite] == lowRaster && spriteEnabled & (1 << sprite) != 0 {
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
            latchSpriteDataByte(sprite: sprite, index: 0, value: cpuPhaseInternalDataBus)
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
        if spriteFetchInFlight?.sprite == sprite {
            fetchSpriteByte(sprite: sprite, index: 2, lowPhase: false, recordTrace: recordsBusAccessTraces)
        } else {
            latchSpriteDataByte(sprite: sprite, index: 2, value: cpuPhaseInternalDataBus)
        }
        spriteFetchInFlight = nil
    }

    private func fetchSpriteByte(sprite: Int, index: Int, lowPhase: Bool, recordTrace: Bool) {
        guard let fetch = spriteFetchInFlight, fetch.sprite == sprite else { return }
        let offset = (fetch.offset + index) & 0x3F
        let address = fetch.pointer | UInt16(offset)
        let value: UInt8
        if sprite == 0 && index == 0 && spriteZeroDMAStartedLate {
            // AEC has not released the CPU yet; no RAM read takes place.
            value = 0xFF
            spriteZeroDMAStartedLate = false
        } else {
            if recordTrace {
                if lowPhase { lastLowPhaseMemoryReads.append(address) }
                else { lastHighPhaseMemoryReads.append(address) }
            }
            value = readMemory?(address) ?? 0
        }
        latchSpriteDataByte(sprite: sprite, index: index, value: value)
        spriteMC[sprite] = (offset + 1) & 0x3F
        spriteLastFetchedMC[sprite] = spriteMC[sprite]
    }

    private func latchSpriteDataByte(sprite: Int, index: Int, value: UInt8) {
        spriteLineData[sprite][index] = value
        let shift = (2 - index) * 8
        spriteShifters[sprite].data = (spriteShifters[sprite].data & ~(0xFF << shift)) | UInt32(value) << shift
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
        let value = debugRegisterValue(reg)
        if cpuPhaseActive { cpuPhaseInternalDataBus = value }
        let register = reg & 0x3F
        switch register {
        case 0x1E:
            spriteSpriteCollision = 0
        case 0x1F:
            spriteDataCollision = 0
        default: break
        }
        return value
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
            if rasterCounter > 255 { value |= 0x80 }
            return value
        case 0x12: return UInt8(rasterCounter & 0xFF)
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
            cpuPhaseInternalDataBus = value
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
            if cpuPhaseActive && (controlReg1 ^ value) & 0x20 != 0 {
                pendingGraphicsAddressBitmapMode = bitmapMode
            }
            if (controlReg1 ^ value) & 0x20 != 0 {
                updateGraphicsModeOutput(mask: 0x20, value: value, firstDot: 0)
                updateGraphicsModeOutput(mask: 0x20, value: value, firstDot: value & 0x20 == 0 ? 2 : 0, shift: 27)
                if invalidECMMode && value & 0x60 == 0x40 && !multicolorMode { holdInvalidGraphicsOutput() }
            }
            if (controlReg1 ^ value) & 0x40 != 0 {
                if cpuPhaseActive {
                    // PAL delays release; NTSC delays assertion and preserves
                    // the old mask when BMM changes in the same CPU write.
                    let delay = videoStandard == .pal ? value & 0x40 == 0
                        : value & 0x40 != 0 || (controlReg1 ^ value) & 0x20 != 0
                    pendingGraphicsAddressECM = delay ? extendedBGMode : nil
                }
                updateGraphicsModeOutput(mask: 0x40, value: value, firstDot: value & 0x40 == 0 ? 2 : 0)
            }
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
            if (controlReg2 ^ value) & 0x10 != 0 {
                updateGraphicsModeOutput(mask: 0x10, value: value, firstDot: 0)
                updateGraphicsModeOutput(mask: 0x10, value: value, firstDot: 3, shift: 27)
                if invalidECMMode && extendedBGMode && !bitmapMode && value & 0x10 == 0 { holdInvalidGraphicsOutput() }
            }
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

// MARK: - Snapshot state

extension VIC {
    public static let snapshotStoredPropertyCount = 125

    /// Scratch line buffers, bus-access diagnostics, and callbacks are not state.
    func saveState(to w: inout StateWriter) {
        w.write(UInt8(videoStandard == .pal ? 0 : 1))
        w.write(spriteX); w.write(spriteY); w.write(spriteXMSB)
        w.write(controlReg1); w.write(controlReg2); w.write(rasterCompare); w.write(memoryPointers)
        w.write(interruptRegister); w.write(interruptEnable)
        w.write(spriteEnabled); w.write(spriteMulticolor); w.write(spriteExpandX); w.write(spriteExpandY); w.write(spritePriority)
        w.write(spriteColors); w.write(spriteMulticolor0); w.write(spriteMulticolor1)
        w.write(spriteSpriteCollision); w.write(spriteDataCollision)
        w.write(collisionPipeline0); w.write(collisionPipeline1); w.write(collisionPipeline2)
        w.write(backgroundColor); w.write(borderColor)
        w.write(rasterLine); w.write(rasterCycle); w.write(displayActive)
        w.write(badLine); w.write(badLineStartCycle); w.write(matrixDMAActive); w.write(cpuPhaseActive); w.write(badLineUpdatePending)
        w.write(pendingGraphicsAddressBitmapMode); w.write(pendingGraphicsAddressECM)
        w.write(badLineDENLatched); w.write(rasterIRQTriggeredThisLine); w.write(rasterCompareMatched); w.write(frameStartPending)
        w.write(lightPenX); w.write(lightPenY); w.write(lightPenLatchedThisFrame)
        w.write(verticalBorderActive); w.write(verticalBorderClosePending); w.write(horizontalBorderActive)
        w.write(refreshCounter); w.write(rowCounter); w.write(videoCounter); w.write(videoCounterBase); w.write(videoMatrixLineIndex)
        w.write(lineBuffer); w.write(colorBuffer); w.write(badLineFetchMask); w.write(displayLineBufferValid); w.write(displayLineBufferBase)
        w.write(graphicsBuffer); w.write(graphicsFetchMask); w.write(graphicsBufferBase); w.write(graphicsBufferPixelRow)
        w.write(graphicsBufferValid); w.write(graphicsBufferLine)
        w.write(graphicsBufferControlReg1); w.write(graphicsBufferControlReg2); w.write(graphicsBufferMemoryPointers)
        w.write(graphicsBufferBackgroundColors); w.write(graphicsBufferScreenBytes); w.write(graphicsBufferColorData)
        w.write(graphicsOutputMatrix)
        w.write(spriteYExpFF); w.write(spriteCrunchPendingMask); w.write(spriteMC); w.write(spriteMCBase)
        w.write(spriteLastFetchedMC); w.write(spriteLastFetchedByteOffset)
        if let fetch = spriteFetchInFlight {
            w.write(true); w.write(fetch.sprite); w.write(fetch.pointer); w.write(fetch.offset)
        } else {
            w.write(false)
        }
        w.write(spriteDisplay); w.write(spriteLineData)
        for shifter in spriteShifters {
            w.write(shifter.data); w.write(shifter.remainingBits); w.write(shifter.expansionSecondDot)
            w.write(shifter.multicolorSecondBit); w.write(shifter.pixel)
        }
        w.write(cpuPhaseInternalDataBus)
        if let write = spriteXWriteThisCycle {
            w.write(true); w.write(write.register); w.write(write.previous)
        } else {
            w.write(false)
        }
        w.write(spriteMulticolorWriteThisCycle)
        w.write(spritePointers); w.write(spriteDMACheckLine); w.write(spriteDMACheckMask); w.write(spriteZeroDMAStartedLate)
        w.write(rasterTraceLine); w.write(rasterTraceHasSamples); w.write(rasterTraceHasDisplayOpen)
        w.write(rasterTraceHasGraphicsOutput); w.write(rasterTraceHasGraphicsModeChanges)
        w.write(rasterTraceValid); w.write(rasterTraceDisplayOpen); w.write(rasterTraceGraphicsOutput); w.write(rasterTraceColors)
        w.write(spriteTraceLine); w.write(spriteTraceHasSamples); w.write(spriteTraceValid); w.write(spriteTraceColor)
        w.write(spriteTraceColorRegister); w.write(spriteTracePriorityBehindBG); w.write(spriteTraceDisplayForeground)
        w.write(spriteTraceSpriteMask); w.write(spriteTraceTouchedPixels)
        w.write(framebuffer); w.write(frameReady); w.write(spriteOccupancyGeneration)
        w.write(spriteDMASwitchedOnMask)
    }

    func restoreState(from r: inout StateReader) throws {
        let width = VIC.screenWidth
        videoStandard = (try r.read() as UInt8) == 0 ? .pal : .ntsc
        spriteX = try snapshotFixed(try r.read(), count: 8, "sprite X"); spriteY = try snapshotFixed(try r.read(), count: 8, "sprite Y"); spriteXMSB = try r.read()
        controlReg1 = try r.read(); controlReg2 = try r.read(); rasterCompare = try r.read(); memoryPointers = try r.read()
        interruptRegister = try r.read(); interruptEnable = try r.read()
        spriteEnabled = try r.read(); spriteMulticolor = try r.read(); spriteExpandX = try r.read(); spriteExpandY = try r.read(); spritePriority = try r.read()
        spriteColors = try snapshotFixed(try r.read(), count: 8, "sprite colors"); spriteMulticolor0 = try r.read(); spriteMulticolor1 = try r.read()
        spriteSpriteCollision = try r.read(); spriteDataCollision = try r.read()
        collisionPipeline0 = try r.read(); collisionPipeline1 = try r.read(); collisionPipeline2 = try r.read()
        backgroundColor = try snapshotFixed(try r.read(), count: 4, "background colors"); borderColor = try r.read()
        rasterLine = try r.read(); rasterCycle = try r.read(); displayActive = try r.read()
        badLine = try r.read(); badLineStartCycle = try r.read(); matrixDMAActive = try r.read(); cpuPhaseActive = try r.read(); badLineUpdatePending = try r.read()
        pendingGraphicsAddressBitmapMode = try r.read(); pendingGraphicsAddressECM = try r.read()
        badLineDENLatched = try r.read(); rasterIRQTriggeredThisLine = try r.read(); rasterCompareMatched = try r.read(); frameStartPending = try r.read()
        lightPenX = try r.read(); lightPenY = try r.read(); lightPenLatchedThisFrame = try r.read()
        verticalBorderActive = try r.read(); verticalBorderClosePending = try r.read(); horizontalBorderActive = try r.read()
        refreshCounter = try r.read(); rowCounter = try r.read(); videoCounter = try r.read(); videoCounterBase = try r.read(); videoMatrixLineIndex = try r.read()
        lineBuffer = try snapshotFixed(try r.read(), count: 40, "line buffer"); colorBuffer = try snapshotFixed(try r.read(), count: 40, "color buffer")
        badLineFetchMask = try r.read(); displayLineBufferValid = try r.read(); displayLineBufferBase = try r.read()
        graphicsBuffer = try snapshotFixed(try r.read(), count: 40, "graphics buffer"); graphicsFetchMask = try r.read(); graphicsBufferBase = try r.read(); graphicsBufferPixelRow = try r.read()
        graphicsBufferValid = try r.read(); graphicsBufferLine = try r.read()
        graphicsBufferControlReg1 = try snapshotFixed(try r.read(), count: 40, "graphics control 1")
        graphicsBufferControlReg2 = try snapshotFixed(try r.read(), count: 40, "graphics control 2")
        graphicsBufferMemoryPointers = try snapshotFixed(try r.read(), count: 40, "graphics pointers")
        graphicsBufferBackgroundColors = try snapshotFixed(try r.read(), count: 40, "graphics background colors")
        guard graphicsBufferBackgroundColors.allSatisfy({ $0.count == 4 }) else { throw MachineStateError.invalidValue("graphics background colors") }
        graphicsBufferScreenBytes = try snapshotFixed(try r.read(), count: 40, "graphics screen bytes")
        graphicsBufferColorData = try snapshotFixed(try r.read(), count: 40, "graphics color data")
        graphicsOutputMatrix = try r.read()
        spriteYExpFF = try snapshotFixed(try r.read(), count: 8, "sprite expansion flip-flops"); spriteCrunchPendingMask = try r.read()
        spriteMC = try snapshotFixed(try r.read(), count: 8, "sprite MC"); spriteMCBase = try snapshotFixed(try r.read(), count: 8, "sprite MCBASE")
        spriteLastFetchedMC = try snapshotFixed(try r.read(), count: 8, "sprite fetched MC"); spriteLastFetchedByteOffset = try snapshotFixed(try r.read(), count: 8, "sprite fetched offset")
        if try r.read() as Bool {
            spriteFetchInFlight = (sprite: try r.read(), pointer: try r.read(), offset: try r.read())
        } else {
            spriteFetchInFlight = nil
        }
        spriteDisplay = try snapshotFixed(try r.read(), count: 8, "sprite display")
        spriteLineData = try snapshotFixed(try r.read(), count: 8, "sprite line data")
        guard spriteLineData.allSatisfy({ $0.count == 3 }) else { throw MachineStateError.invalidValue("sprite line data") }
        for index in 0..<8 {
            spriteShifters[index].data = try r.read(); spriteShifters[index].remainingBits = try r.read()
            spriteShifters[index].expansionSecondDot = try r.read(); spriteShifters[index].multicolorSecondBit = try r.read()
            spriteShifters[index].pixel = try r.read()
        }
        cpuPhaseInternalDataBus = try r.read()
        if try r.read() as Bool {
            spriteXWriteThisCycle = (register: try r.read(), previous: try r.read())
        } else {
            spriteXWriteThisCycle = nil
        }
        spriteMulticolorWriteThisCycle = try r.read()
        spritePointers = try snapshotFixed(try r.read(), count: 8, "sprite pointers"); spriteDMACheckLine = try r.read(); spriteDMACheckMask = try r.read(); spriteZeroDMAStartedLate = try r.read()
        rasterTraceLine = try r.read(); rasterTraceHasSamples = try r.read(); rasterTraceHasDisplayOpen = try r.read()
        rasterTraceHasGraphicsOutput = try r.read(); rasterTraceHasGraphicsModeChanges = try r.read()
        rasterTraceValid = try snapshotFixed(try r.read(), count: width, "raster trace valid")
        rasterTraceDisplayOpen = try snapshotFixed(try r.read(), count: width, "raster trace display")
        rasterTraceGraphicsOutput = try snapshotFixed(try r.read(), count: width, "raster trace graphics")
        rasterTraceColors = try snapshotFixed(try r.read(), count: width, "raster trace colors")
        spriteTraceLine = try r.read(); spriteTraceHasSamples = try r.read()
        spriteTraceValid = try snapshotFixed(try r.read(), count: width, "sprite trace valid")
        spriteTraceColor = try snapshotFixed(try r.read(), count: width, "sprite trace color")
        spriteTraceColorRegister = try snapshotFixed(try r.read(), count: width, "sprite trace register")
        spriteTracePriorityBehindBG = try snapshotFixed(try r.read(), count: width, "sprite trace priority")
        spriteTraceDisplayForeground = try snapshotFixed(try r.read(), count: width, "sprite trace foreground")
        spriteTraceSpriteMask = try snapshotFixed(try r.read(), count: width, "sprite trace mask")
        spriteTraceTouchedPixels = try r.read()
        guard spriteTraceTouchedPixels.allSatisfy({ (0..<width).contains($0) }) else { throw MachineStateError.invalidValue("sprite trace pixels") }
        framebuffer = try snapshotFixed(try r.read(), count: width * VIC.screenHeight, "framebuffer")
        frameReady = try r.read(); spriteOccupancyGeneration = try r.read()
        // Generation stamps left by earlier lines must not match restored ones.
        for index in spriteOccupancyGenerationScratch.indices { spriteOccupancyGenerationScratch[index] = 0 }
        lastHighPhaseMemoryReads = []; lastHighPhaseColorRAMReads = []; lastLowPhaseMemoryReads = []
        // Appended after 0.6.0; snapshots written before it end here.
        spriteDMASwitchedOnMask = r.isAtEnd ? 0 : try r.read()
    }
}
