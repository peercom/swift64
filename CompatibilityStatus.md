# C64 Compatibility Status

This project is targeting preservation-grade Commodore 64 compatibility: stock PAL/NTSC C64 timing, SID model differences, 1541-family true-drive behavior, low-level/protected media, cartridges, and opt-in corpus validation.

## Current Baseline

| Area | Status | Notes |
| --- | --- | --- |
| Machine/chip profiles | Partial | PAL/NTSC C64 profiles select 6581 SID timing, PAL/NTSC C64C profiles select 8580 SID timing, and compatibility manifests can select 1541C or 1541-II drive variants with matching VIC geometry, CIA TOD, SID clock, and drive clock defaults; more board/chip revisions and deeper 1541-family hardware differences remain open. |
| 6510/6502 CPU | Partial-preservation | Cycle-stepped CPU with documented and many undocumented opcodes; remaining work includes conformance-suite closure for decimal flags, RDY/SO/interrupt edges, and unstable opcodes. |
| Memory and I/O banking | Good baseline | BASIC/Kernal/Char ROM banking, I/O dispatch, color RAM nibbles, VIC bank selection, CPU port cassette lines, and open-bus behavior have focused tests. |
| VIC-II | Partial | Rasterline rendering, PAL/NTSC frame timing, bad-line CPU stalls, sprites, collision IRQs, light pen latch, and key readback quirks are covered; full per-cycle BA/AEC, sprite DMA, border tricks, and deeper border timing remain open. |
| SID | Early partial | Three voices, ADSR, waveforms, edge-based oscillator sync, TEST-bit oscillator reset, OSC3/ENV3, paddle reads, model-specific output-stage bias, and a basic filter exist; deeper 6581/8580 analog behavior, ADSR bugs, combined waveforms, and filter curves remain open. |
| CIA 6526 | Partial | Timers, TOD with PAL/NTSC 50/60 Hz selection, keyboard/joystick scanning, RESTORE/NMI input, FLAG/CNT/SP serial paths, PB6/PB7 timer outputs, interrupt masking, and timer read latches are covered; deeper port interactions remain open. |
| 1541 true drive | In progress | 1541 CPU/VIA/GCR/IEC read path exists with D64/G64 smoke coverage, native G64 track streams, and per-byte speed-zone maps; custom loaders, weak bits, alignment-sensitive halftrack behavior, write-back, SAVE, and format support remain open. |
| Tape | Early signal foundation | T64 trap loading, raw TAP v0/v1 pulse parsing/playback, C64 mount-path auto-arming, CPU-port cassette sense/write/motor line surfaces, motor-gated idle FLAG behavior, and TAP-to-CIA1 FLAG edges exist; full datasette/Kernal timing is not complete. |
| Cartridges/expansion | Early partial | Standard CRT parsing, 8K/16K ROM mapping, Ultimax ROM/open-bus memory map behavior, Simon's BASIC upper-ROM control, Magic Desk ROML bank switching, Ocean type 1 ROML/ROMH bank switching, Fun Play/Power Play bank switching, and normal-mapped Westermann/Rex CRT aliases exist; freezer/fastload cartridges, EasyFlash, broader expansion I/O, DMA, and REU remain open. |
| Compatibility harness | Early partial | Local manifests now parse media/profile/drive-mode run settings, mount PRG/D64/G64/T64/TAP/CRT milestones, command sequences, drive status expectations, RAM signatures, and screen RAM hashes; screenshots and resumable result logs remain open. |
| macOS app settings | Partial | Settings expose machine profile, drive mode, and local BASIC/Kernal/Character/1541 ROM paths; more per-subsystem accuracy toggles and validation presets remain open. |

## Validation Policy

- Fast checks stay sequential: build, focused unit test classes, and selected smoke tests.
- Heavy compatibility media runs stay opt-in through environment variables and local untracked manifests under `C64/DISKS`.
- ROMs, commercial media, protected images, screenshots, and generated binary artifacts must remain untracked unless explicitly approved.

## Near-Term Milestones

1. Extend machine/chip profiles with additional board/chip revisions and deeper 1541-family hardware differences.
2. Convert the local compatibility manifest into a reusable corpus runner with deterministic pass/fail reasons.
3. Close VIC-II timing gaps that block raster splits, sprite multiplexing, and protected loaders.
4. Expand 1541 low-level media support for protected G64 behavior before adding write-back.
5. Extend the cartridge framework with common fastload/freezer formats, bank switching, expansion I/O, and REU hooks.
