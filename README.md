# C64 Emulator

A Commodore 64 emulator written in Swift, targeting macOS. This project is in **early stages** — it boots to BASIC and runs simple programs, but broader compatibility with real-world software and games is still being developed and tested.

There is also an NES emulator sharing the same 6502 CPU core, in even earlier stages.

## Status

- Boots to the C64 BASIC screen
- Keyboard input, joystick (numpad)
- Audio output (SID chip)
- Loads PRG, D64, G64, T64, and TAP files
- Built-in debugger with CPU trace, breakpoints, and memory inspection

### What works

| Component | Status |
|-----------|--------|
| 6502 CPU | Cycle-accurate, 222 opcodes including undocumented |
| VIC-II | Rasterline rendering, sprites, bad lines, raster IRQ |
| SID | 3 voices, ADSR envelopes, waveforms, basic filter |
| CIA 1 & 2 | Timers, keyboard matrix, joystick, IRQ/NMI |
| Memory | Full ROM banking (BASIC/Kernal/Char ROM, I/O) |
| Disk Drive | D64 and G64 image support via Kernal traps |
| Tape | T64 and TAP container formats |

### What needs work

- Many games and demos will not run correctly yet — VIC-II timing, sprite multiplexing, and advanced raster effects need further refinement
- No serial bus emulation (disk access is handled via Kernal traps, not cycle-accurate 1541 emulation)
- Copy-protected software that relies on drive timing will not work
- SID filter is simplified
- No REU, cartridge, or expansion port support

## Building

Requires Swift 5.9+ and macOS 14+.

```sh
swift build -c release
```

### ROMs

You need C64 ROM files (not included) placed in `Sources/C64App/ROMS/`:

- `basic` — BASIC ROM (8K)
- `kernal` — Kernal ROM (8K)
- `characters` — Character ROM (4K)

## Running

```sh
.build/release/C64App
```

### Loading software

- **Drag and drop** D64, G64, PRG, T64, or TAP files onto the window
- **File menu**: Open Disk Image (Cmd+D), Open Tape (Cmd+T), Load PRG (Cmd+L)
- **Reset**: Cmd+Shift+R

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
