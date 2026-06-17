# C64 Emulator

A Commodore 64 emulator written in Swift, targeting macOS. It boots to BASIC, runs simple programs, supports fast media loading, and now includes an in-progress true-drive 1541 path for compatibility testing with low-level disk images.

There is also an NES emulator sharing the same 6502 CPU core, in even earlier stages.

## Status

- Boots to the C64 BASIC screen
- Keyboard input, joystick (numpad)
- Audio output (SID chip)
- Loads PRG, D64, G64, T64, TAP, and standard CRT cartridge files
- Fast Kernal-trap disk loading plus compatibility true-drive 1541 emulation
- Compact drive status popover for disk, IEC, GCR, and hang diagnostics
- Built-in debugger with CPU trace, breakpoints, and memory inspection
- Focused regression coverage for VIC, CIA, disk, IEC, GCR, SID, and 1541 behavior

### What works

| Component | Status |
|-----------|--------|
| 6502 CPU | Cycle-accurate, 222 opcodes including undocumented |
| VIC-II | Rasterline rendering, sprites, bad-line CPU stalls, raster/collision IRQs |
| SID | 3 voices, ADSR envelopes, waveforms, basic filter |
| CIA 1 & 2 | Timers, keyboard matrix, joystick, edge-sensitive IRQ/NMI |
| Memory | Full ROM banking (BASIC/Kernal/Char ROM, I/O) |
| Disk Drive | D64/G64 via Kernal traps, plus true-drive 1541 read path with IEC/VIA/GCR emulation |
| Tape | T64 and TAP container formats |
| Cartridges | Standard CRT parsing with 8K/16K/Ultimax ROM mapping |

### What needs work

- Many games and demos will not run correctly yet — VIC-II timing, sprite multiplexing, and advanced raster effects need further refinement
- True-drive 1541 compatibility is read-focused and still being validated against protected G64/custom-loader disks
- 1541 SAVE/write/format support is deferred until read compatibility is stable
- Weak/random bits, P64/NIB/flux-level media, and G64 write-back are not implemented
- SID filter is simplified
- Banked/freezer/fastload cartridges, EasyFlash, REU, and expansion-port DMA/I/O are not implemented

See [CompatibilityStatus.md](CompatibilityStatus.md) for the preservation-grade compatibility roadmap and subsystem status.

### Recent emulation work

- Standard CRT cartridge images now mount through the app and map ROML/ROMH for 8K, 16K, and Ultimax cartridges
- SID voice output now centers before envelope application and distinguishes 6581 vs 8580 volume-DAC bias
- VIC-II timing now follows the active PAL/NTSC profile for cycles per rasterline and rasterlines per frame
- CIA TOD timing now exposes PAL/NTSC-derived 50 Hz and 60 Hz rates and switches them through CRA bit 7
- CIA serial input now shifts SP on CNT pulses, serial output shifts on Timer A underflows, and completed transfers raise the serial interrupt source
- CIA timer output now drives PB6/PB7 pulse and toggle modes for software that observes user-port/timer pins
- SID oscillator sync now resets voices on source MSB rising edges instead of source level, improving hard-sync behavior
- The 6510 CPU port now exposes cassette sense, write, and motor-control line levels for later datasette signal-path work
- TAP v0/v1 images now auto-arm raw pulse playback through the C64 tape mount path and can drive CIA1 FLAG edges
- True-drive D64 directory and PRG loads now pass hardware-path smoke tests through IEC, 1541 DOS, GCR byte-ready, and C64 RAM transfer checks
- VIC-II sprite rendering now has corrected X placement, sprite-sprite and sprite-background collision latches, collision IRQs, and foreground-mask based sprite priority/collision behavior
- VIC-II bad-line character fetches now stall the C64 CPU during the fetch window while VIC/CIA/SID/drive timing continues
- CIA interrupt masking/read-clear behavior now deasserts CPU IRQ/NMI lines cleanly and avoids duplicate active callbacks
- C64-level interrupt tests cover combined CIA/VIC IRQ assertion and deassertion

## Building

Requires Swift 5.9+ and macOS 14+.

```sh
swift build -c release
```

### ROMs

You need C64 ROM files and a 1541 drive ROM placed in `Sources/C64App/ROMS/`:

- `basic` — BASIC ROM (8K)
- `kernal` — Kernal ROM (8K)
- `characters` — Character ROM (4K)
- `1541` — 1541/1541C drive ROM (16K)

## Running

```sh
.build/release/C64App
```

### Loading software

- **Drag and drop** D64, G64, PRG, T64, TAP, or CRT files onto the window
- **File menu**: Open Disk Image (Cmd+D), Open Tape (Cmd+T), Load PRG (Cmd+L), Open Cartridge (Cmd+K)
- **Toolbar**: switch between Fast Load and compatibility True Drive 1541 mode
- **Drive Status**: inspect mounted media, LED/motor, track, sync, byte-ready, IEC lines, recent command bytes, and detected hang/JAM reason
- **Reset**: Cmd+Shift+R

### True-drive compatibility testing

Local disk-image matrix tests are opt-in because they depend on files under `C64/DISKS`:

```sh
SWIFT64_LOCAL_DISK_MATRIX=1 swift test --filter LocalDiskMatrixTests/testLocalDiskImagesMountAndEncodeWhenEnabled
SWIFT64_LOCAL_TRUE_DRIVE_MATRIX=1 swift test --filter LocalDiskMatrixTests/testLocalDiskImagesTrueDriveDirectorySmokeWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
```

The named milestone test has a built-in Great Giana Sisters G64 custom-loader progress checkpoint when that local file is present. You can override or add stricter screen/PC milestones with an untracked `C64/DISKS/compatibility.json` file.

Useful fast regression slices:

```sh
swift test --filter VICTests
swift test --filter CIATests
swift test --filter C64InterruptTests
swift test --filter C64TimingTests
swift test --filter Drive1541Tests/testTrueDriveD64DirectoryLoadStartsGCRReadHardware
swift test --filter Drive1541Tests/testTrueDriveD64PrgLoadUsesFileAddress
```

Example milestone manifest:

```json
{
  "milestones": [
    {
      "file": "great_giana_sisters[time_warp_1987](pal)(r1)(!).g64",
      "mediaType": "g64",
      "machineProfile": "palC64",
      "commands": ["LOAD\"*\",8,1", "RUN"],
      "maxCycles": 24000000,
      "pcStart": 49152,
      "pcEnd": 53247,
      "driveStatus": {
        "minGCRReads": 64,
        "minByteReady": 512,
        "minSyncDetections": 1,
        "hasNativeLowLevelImage": true
      },
      "ramSignatures": [
        { "address": 2049, "bytes": "01 08" }
      ],
      "screenRAMHash": "optional-fnv1a64-screen-ram-hash"
    }
  ]
}
```

### Keyboard

The Mac keyboard maps to the C64 keyboard layout. The Escape key acts as the RESTORE key (triggers NMI). Joystick port 2 is mapped to the numpad (8/2/4/6 for directions, 0 or Enter for fire).

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
