# C64 Compatibility Status

This project is targeting preservation-grade Commodore 64 compatibility: stock PAL/NTSC C64 timing, SID model differences, 1541-family true-drive behavior, low-level/protected media, cartridges, and opt-in corpus validation.

## Current Baseline

| Area | Status | Notes |
| --- | --- | --- |
| 6510/6502 CPU | Partial-preservation | Cycle-stepped CPU with documented and many undocumented opcodes; remaining work includes conformance-suite closure for decimal flags, RDY/SO/interrupt edges, and unstable opcodes. |
| Memory and I/O banking | Good baseline | BASIC/Kernal/Char ROM banking, I/O dispatch, color RAM nibbles, VIC bank selection, and open-bus behavior have focused tests. |
| VIC-II | Partial | Rasterline rendering, bad-line CPU stalls, sprites, collision IRQs, light pen latch, and key readback quirks are covered; full per-cycle BA/AEC, sprite DMA, border tricks, and PAL/NTSC geometry remain open. |
| SID | Early partial | Three voices, ADSR, waveforms, edge-based oscillator sync, TEST-bit oscillator reset, OSC3/ENV3, paddle reads, and a basic filter exist; 6581/8580 model differences, ADSR bugs, combined waveforms, and filter curves remain open. |
| CIA 6526 | Partial | Timers, TOD, keyboard/joystick scanning, FLAG/CNT paths, PB6/PB7 timer outputs, interrupt masking, and timer read latches are covered; serial port, TOD 50/60 Hz profile closure, and deeper port interactions remain open. |
| 1541 true drive | In progress | 1541 CPU/VIA/GCR/IEC read path exists with D64/G64 smoke coverage; custom loaders, weak bits, halftracks, variable track length, write-back, SAVE, and format support remain open. |
| Tape | Container-level | T64/TAP mounting and trap loading exist; real datasette signal timing is not complete. |
| Cartridges/expansion | Early partial | Standard CRT parsing and basic 8K/16K/Ultimax ROM mapping exist; banked/freezer/fastload cartridges, EasyFlash, expansion I/O, DMA, and REU remain open. |
| Compatibility harness | Early partial | Local manifests now parse media/profile/run settings plus RAM signatures and screen RAM hashes; full PRG/D64/G64/T64/TAP/CRT execution, screenshots, and resumable result logs remain open. |

## Validation Policy

- Fast checks stay sequential: build, focused unit test classes, and selected smoke tests.
- Heavy compatibility media runs stay opt-in through environment variables and local untracked manifests under `C64/DISKS`.
- ROMs, commercial media, protected images, screenshots, and generated binary artifacts must remain untracked unless explicitly approved.

## Near-Term Milestones

1. Complete machine/chip profiles for PAL/NTSC, SID 6581/8580, and 1541-family timing.
2. Convert the local compatibility manifest into a reusable corpus runner with deterministic pass/fail reasons.
3. Close VIC-II timing gaps that block raster splits, sprite multiplexing, and protected loaders.
4. Expand 1541 low-level media support for protected G64 behavior before adding write-back.
5. Extend the cartridge framework with common fastload/freezer formats, bank switching, expansion I/O, and REU hooks.
