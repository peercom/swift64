# Swift64 C64 Emulator

A Commodore 64 emulator written in Swift, targeting macOS. It boots to BASIC, runs common PRG/D64/G64 workflows, includes both fast Kernal-trap loading and a compatibility true-drive 1541 path, and is being developed toward preservation-grade C64 compatibility.

There is also an NES emulator sharing the same 6502 CPU core, in even earlier stages.

Latest packaged macOS release: [Swift64 0.4.3](https://github.com/peercom/swift64/releases/tag/v0.4.3). ROMs and commercial media are not included.

## Status

- Boots to the C64 BASIC screen
- Keyboard input, joystick (numpad or game controllers), warp mode, selectable VIC palettes
- Audio output with selectable SID model and fast/compatibility synthesis modes
- Loads PRG, D64, G64, NIB, NBZ, P64, T64, TAP, standard CRT cartridge files, Action Replay, KCS Power, Atomic Power/Nordic Power, Action Replay 3, Action Replay 4, Final Cartridge I, Final Cartridge Plus, Final Cartridge III, Simon's BASIC, Super Games, C64 Game System/System 3, Warp Speed, Stardos, Game Killer, Prophet64, EXOS, Freeze Frame, Freeze Machine, Snapshot64, Super Explode V5, Super Snapshot V5, MACH 5, Dinamic, Zaxxon/Super Zaxxon, COMAL-80, Structured BASIC, Ross, Dela EP64, Dela EP7x8, Dela EP256, Rex EP256, Mikro Assembler, Magic Formel, Magic Desk, Ocean type 1, Fun Play/Power Play, Epyx FastLoad, Westermann Learning, Rex Utility, and EasyFlash CRTs
- Fast Kernal-trap disk loading plus compatibility true-drive 1541 emulation
- Display-first macOS app with optional right inspector, compact status bar, fullscreen chrome hiding, ROM setup assistant, and CRT shader
- Compact drive status popover for disk, IEC, GCR, protected-media, and hang diagnostics
- Built-in debugger with CPU trace, breakpoints, and memory inspection
- Focused regression coverage for VIC, CIA, disk, IEC, GCR, SID, 1541, cartridge, tape, compatibility-manifest, and performance-benchmark behavior
- Phase 2 CPU, memory, and bus certification is complete for the preservation roadmap gate, with public CPU suites kept opt-in and sequential

### What works

| Component | Status |
|-----------|--------|
| 6502 CPU | Phase 2 complete: cycle-stepped, 222 opcodes including undocumented, RDY/SO/interrupt edge coverage, decimal edge coverage, and opt-in public conformance runners |
| VIC-II | PAL/NTSC beam sampling, clocked graphics counters/color latches, active/inactive sprite fetches and shifters, phased register effects, shared-bus and Ultimax ROMH fetches, bad-line and sprite BA/AEC phases, raster/collision IRQs, and software light-pen/timer synchronization; 144 of 146 public programs pass, including IRQ acknowledgement, sprite-X/reload and cycle-stealing checks, and 135 exact visual fixtures for cartridge mapping, FLD/line-crunch/Blackmail FLI, late display entry and screen/color alignment, text/bitmap open borders, side-border sprites, sprite-register splits, PAL mode splits, sprite crunch and raster IRQ holdoff, and PAL/NTSC display-enable boundaries, DMA-delay scrolling, sprite enable/expansion, and graphics fetches. Two mid-line graphics-mode comparisons still fail; broader game/demo and chip-revision validation remain open |
| SID | 3 voices with 6581/8580 model selection, fast/compatibility modes, ADSR delay/exponential behavior, sync/ring/noise, model-aware combined waveform approximations, OSC3/ENV3/POT readback, data-bus latch behavior, audio signatures, and a bounded routed filter/output-stage foundation |
| CIA 1 & 2 | Pipelined timer start/stop/reload, CNT and cascaded counting, latched interrupts with CPU IRQ/NMI wiring, keyboard matrix, joystick |
| Memory | Full ROM banking (BASIC/Kernal/Char ROM, I/O) |
| Disk Drive | D64/G64 via Kernal traps, read-only raw and compressed NIBTOOLS NIB/NBZ plus first-stage P64 import for the true-drive path, high-level D64 PRG SAVE with exportable modified image bytes, plus true-drive 1541 read path and first-stage low-level GCR write-head/erase plumbing with IEC/VIA/GCR emulation |
| Tape | T64 and TAP container formats, raw TAP pulse playback, stock CBM TAP decode diagnostics, cassette signal/motor/sense plumbing, virtual T64 SAVE output, and TAP/T64 export surfaces |
| Cartridges | Standard CRT parsing with 8K/16K/Ultimax ROM mapping, Action Replay bank/RAM/IO2 mapping, KCS Power ROM/IO/RAM mode control, Atomic Power/Nordic Power ROM/RAM/Ultimax mode control, Action Replay 3 mirrored ROML/ROMH mapping, Action Replay 4 bank/control/IO2 mapping, Final Cartridge I IO-toggle mapping, Final Cartridge Plus segmented ROM/control mapping, Final Cartridge III 16K bank/control/NMI mapping, Simon's BASIC upper-ROM control, Super Games 16K bank/control latch, C64 Game System/System 3 IO1-address bank switching, Warp Speed IO mirroring and ROM-window control, Stardos capacitor-gated ROML/Kernal replacement mapping, Game Killer Kernal-window ROM and IO disable latch, Prophet64 IO2 bank/disable control, EXOS HIRAM-gated Kernal replacement mapping, Freeze Frame reset/IO/freeze ROM-window control, Freeze Machine 16K/32K reset/IO/freeze ROM-window control, Snapshot64 freeze-visible 4K Ultimax ROM mapping, Super Explode V5 bank/IO2/capacitor-gated ROM control, Super Snapshot V5 ROM/RAM/control mapping, MACH 5 ROM/IO mirror enable-disable control, Dinamic IO1-read bank switching, Zaxxon fixed-ROM read-selected upper banks, COMAL-80 black/default 16K bank switching, Structured BASIC IO1 bank/off control, Ross read-triggered bank/off control, Dela EP64/EP7x8/EP256 and Rex EP256 EPROM bank decoding, Mikro Assembler IO mirrors, Magic Formel `$E000` bank switching, Magic Desk ROML bank switching, Ocean type 1 bank switching, Fun Play/Power Play bank switching, Epyx FastLoad ROM/IO2/capacitor-gate behavior, EasyFlash bank/control/RAM mapping, and normal-mapped Westermann/Rex cartridge aliases |
| macOS app | Xcode-based SwiftUI/Metal app with display-first main window, toolbar workflows, optional inspector tabs, ROM setup assistant, Settings tabs, fullscreen display mode, CRT shader, sandbox-safe ROM/media access, and release packaging |

### What needs work

- Release 0.4.3 includes the raster-synchronizer and inactive-sprite fixes, closing Blackmail FLI and both side-border sprite probes without reference tolerances; see [raster synchronizer proof](TESTING.md#raster-synchronizer-timing).
- [Frame-wrap and IRQ acknowledgement fixes](TESTING.md#frame-wrap-and-irq-acknowledgement-timing) place the raster-zero interrupt one clock later and prevent a same-cycle acknowledgement from erasing the CPU's sampled IRQ. The original PAL acknowledgement test now passes; all prior public images and game/multiplexer checkpoint captures remain unchanged.
- [Ultimax cartridge graphics](TESTING.md#ultimax-vic-memory-and-cartridge-graphics) now use the correct VIC ROMH/RAM mapping. The original EasyFlash Ultimax probe improves from 7,819 wrong pixels to an exact match; its 8K/16K counterparts and all previous captures remain unchanged. Custom phase-dependent cartridge hardware is not certified by these checks.
- [Sprite reload timing](TESTING.md#sprite-reload-and-cycle-stealing) now prevents false collisions during ninth-sprite reuse. The original 29-case sprite-X tests and hardware-checked cycle-stealing programs pass under PAL and NTSC.
- The original Hessian-derived 24-sprite example now has [sustained PAL/NTSC display proof](TESTING.md#external-sprite-multiplexer-demo): 240 complete display frames per profile match an independent sprite-list compositor. This is the standalone multiplexer example, not the full Hessian game.
- Martin Piper's original [mixed-mode multiplexer](TESTING.md#patterned-sprite-modes) also matches 240 complete display frames per profile, covering patterned multicolor/hires sprites, transparency, X/Y expansion, and foreground priority without patching the program.
- A [complete-game PAL milestone](TESTING.md#complete-game-milestone) now runs the original Befana vs Balloons 2026 through its title and 1,500 gameplay frames, reaching level 2 with working controls and 1,715,786 exact sprite pixels. The same PRG misses an NTSC raster deadline and is not counted as an NTSC gameplay pass.
- The original [scrolling game framework](TESTING.md#scrolling-game-and-hud-split) now has PAL/NTSC gameplay proof: scrolling graphics/color RAM, moving sprites, a fixed HUD, and a successful area transition. Each profile checks 660 frames with exact source-derived pixels in specified regions; this is not a full-screen or whole-game certification.
- Six [late bad-line and display-entry probes](TESTING.md#late-bad-lines-and-screencolor-alignment) now match their full PAL comparison crops, including a sprite/bitmap reproducer derived from "Shards of Fancy". This verifies the reproducer, not the complete demo.
- [Sprite startup and expansion fixes](TESTING.md#sprite-startup-and-expansion-boundaries) correct disabled sprites starting display, late DMA's first byte, and repeated rows after cycle-sensitive expansion writes. Nineteen distinct public probes now match exactly; the existing 100 reference captures remain unchanged.
- [DMA-delay scrolling](TESTING.md#dma-delay-scrolling-and-graphics-mode-output) adds 42 exact PAL/NTSC reference matches. Separating the [multicolor data latch and color selector](TESTING.md#multicolor-data-and-color-selection) brings PAL `videomode2` and `modesplit` to exact matches. The subsequent [NTSC address-stage fix](TESTING.md#ntsc-graphics-address-transitions) corrects 300 more pixels without changing any previous passing capture. Two strict failures remain: one pixel in PAL `videomode1` and 26 in NTSC `modesplit`. There are no tolerance exceptions; remaining transition timing and alternate chip revisions still need work, and the public suite is not wholly green.
- Broader full-game and multi-part-demo coverage, remaining NTSC raster effects, alternate chip revisions, and extreme-edge physical output mapping still need validation. Passing these bounded milestones is not certification of every game or demo.
- True-drive 1541 compatibility is still being validated against protected G64/custom-loader disks
- Analog magnetic erase strength/decay, complete low-level 1541 format support, and flux-level write semantics are deferred until the low-level read/write path is stable
- P64 import now decodes NRZI flux-pulse chunks into native low-level GCR tracks for true-drive emulation, but exact analog flux timing is still quantized to GCR bit cells; raw and compressed NIBTOOLS NIB/NBZ images mount as read-only native low-level tracks for true-drive emulation, weak/random bit readback and G64 export/write-back are available for native low-level tracks, and Swift64 appends a compatible metadata extension to preserve weak-bit annotations across G64 export/import
- SID analog filter, output-stage distortion, and model-specific 6581/8580 calibration remain approximate and are not yet matched to measured hardware curves
- Freezer button CPU-state capture, Super Snapshot V5 32K RAM-expansion setting, COMAL-80 grey-revision mode selection, deeper fastloader protocol validation, EasyFlash flash writes, REU, and broader expansion-port DMA/I/O are not implemented
- Selectable CRT display shader support is available in the macOS app for scanlines, phosphor mask, and a little composite-style softness

See [CompatibilityStatus.md](CompatibilityStatus.md) for the preservation-grade compatibility roadmap and subsystem status.

## Changelog

Recent emulator and app changes are tracked in [CHANGELOG.md](CHANGELOG.md).

## Building

Requires Swift 5.9+ and macOS 14+.

For the macOS app, use the Xcode project:

```sh
xcodebuild -project Swift64.xcodeproj -scheme Swift64 -configuration Release build
```

For the normal local app loop, the helper below regenerates the Xcode project from `project.yml`, builds Release with a bounded job count, and launches `Swift64.app` from repo-local DerivedData. It requires `xcodegen`; use the direct `xcodebuild` command above if you only want to build the checked-in project:

```sh
script/build_and_run.sh
```

For package-level development and test builds:

```sh
swift build -c release
```

### ROMs

ROM files are copyrighted and are not distributed with this project. On first launch, Swift64 opens the ROM setup assistant when required ROMs are missing. You can also open Settings > ROMs to choose local paths for:

- BASIC ROM (8K)
- Kernal ROM (8K)
- Character ROM (4K)
- 1541/1541C/1541-II drive ROM (16K)

Use Apply to validate and import sandbox-safe private copies into Application Support, or OK to apply and close the settings window. The 1541 drive ROM is optional for fast-load mode but required for true-drive compatibility. For local development and compatibility testing, the app still falls back to untracked ROM files under `C64/ROMS` or `Sources/C64App/ROMS` when explicit Settings paths are not configured.

## Running

```sh
script/build_and_run.sh
```

### Loading software

- **Drag and drop** PRG, D64, G64, NIB, NBZ, P64, T64, TAP, or CRT files onto the window
- **File menu**: Open Disk Image (Cmd+D), Open Tape (Cmd+T), Load PRG (Cmd+L), Open Cartridge (Cmd+K)
- **Toolbar**: open media, apply presets, switch between Fast Load and compatibility True Drive 1541 mode, show Drive Status, toggle Inspector, open Debugger, reset, and open Settings
- **Inspector**: optional Media, Machine, Drive, and Audio tabs for mounted media, profile/mode selection, 1541 diagnostics, and audio/display status
- **Status bar**: optional compact media, drive, ROM, mode, and failure summary at the bottom of the display
- **Drive Status**: inspect mounted media, LED/motor, track, sync, byte-ready, IEC lines, protected-media capabilities, recent command bytes, and detected hang/JAM reason
- **Reset**: Cmd+Shift+R

Fullscreen hides toolbar, inspector, and status chrome so the C64 display fills the stage.

### Testing

Detailed local, opt-in, compatibility, CPU conformance, milestone, and performance test instructions live in [TESTING.md](TESTING.md).

### Keyboard

The Mac keyboard maps to the C64 keyboard layout. Escape maps to RUN/STOP, and Page Up or F12 act as RESTORE keys that trigger NMI. Joystick port 2 is mapped to the numpad (8/2/4/6 for directions, 0 or Enter for fire).

### Game controllers

Any controller recognised by macOS (Xbox, PlayStation, MFi, Switch Pro) works without configuration. The first controller follows the joystick routing in Settings, and a second controller takes the other port. D-pad or left stick moves; A, B, or the shoulder buttons fire.

### Warp mode

Cmd+Shift+W, the toolbar hare button, or Emulation > Warp Mode runs the machine as fast as the Mac allows with audio muted, for skipping long loads and decrunchers. Switch it off to return to real-time, properly paced playback.

## Debugger

Open via **Debug > Show Debugger** (Cmd+Shift+D). The debugger runs in a separate window with four panels:

- **CPU State** — Registers, flags, cycle count, rasterline, IRQ/NMI indicators
- **Disassembly** — Instructions around the current PC, click to set breakpoints
- **Memory Inspector** — Hex dump with presets for Zero Page, Stack, Screen RAM, VIC, SID, CIA registers
- **Trace Log** — Instruction-level execution trace (enable with the Trace toggle)

Controls: Pause/Resume, Step (single instruction), Save Trace to file.

### Programmatic debug API

From code, the `Debugger` class on `C64` provides:

```swift
c64.debugger.addBreakpoint(0xE5CD)
c64.debugger.addWatchpoint(0xD012, type: .read)
c64.debugger.traceEnabled = true
c64.debugger.openTraceFile("/tmp/trace.log")  // VICE-compatible format
```

## Architecture

```
Emu6502          — Reusable 6502 CPU core (Bus protocol, cycle-accurate)
C64Core          — C64 machine: VIC-II, SID, CIA, memory map, disk/tape, debugger
C64App           — macOS GUI: Metal rendering, audio, keyboard, debugger window
NESCore / NESApp — NES emulator (separate, shares CPU core)
```

## License

This is a personal project. ROM files are copyrighted by Commodore and are not included.
