# C64 Emulator

A Commodore 64 emulator written in Swift, targeting macOS. It boots to BASIC, runs simple programs, supports fast media loading, and now includes an in-progress true-drive 1541 path for compatibility testing with low-level disk images.

There is also an NES emulator sharing the same 6502 CPU core, in even earlier stages.

## Status

- Boots to the C64 BASIC screen
- Keyboard input, joystick (numpad)
- Audio output (SID chip)
- Loads PRG, D64, G64, T64, TAP, standard CRT cartridge files, Action Replay, KCS Power, Atomic Power/Nordic Power, Action Replay 3, Action Replay 4, Final Cartridge I, Final Cartridge Plus, Final Cartridge III, Simon's BASIC, Super Games, C64 Game System/System 3, Warp Speed, Stardos, Game Killer, Prophet64, EXOS, Freeze Frame, Freeze Machine, Snapshot64, Super Explode V5, Super Snapshot V5, MACH 5, Dinamic, Zaxxon/Super Zaxxon, COMAL-80, Structured BASIC, Ross, Dela EP64, Dela EP7x8, Dela EP256, Rex EP256, Mikro Assembler, Magic Formel, Magic Desk, Ocean type 1, Fun Play/Power Play, Epyx FastLoad, Westermann Learning, Rex Utility, and EasyFlash CRTs
- Fast Kernal-trap disk loading plus compatibility true-drive 1541 emulation
- Compact drive status popover for disk, IEC, GCR, and hang diagnostics
- Built-in debugger with CPU trace, breakpoints, and memory inspection
- Focused regression coverage for VIC, CIA, disk, IEC, GCR, SID, and 1541 behavior

### What works

| Component | Status |
|-----------|--------|
| 6502 CPU | Cycle-accurate, 222 opcodes including undocumented |
| VIC-II | Rasterline rendering, sprites, bad-line and sprite BA/AEC phases, low-phase VIC access decoding, two-cycle sprite DMA slots, CPU stalls, raster/collision IRQs |
| SID | 3 voices, ADSR envelopes with exponential decay/release, waveforms/noise LFSR, model-aware routed filter foundation |
| CIA 1 & 2 | Timers, keyboard matrix, joystick, edge-sensitive IRQ/NMI |
| Memory | Full ROM banking (BASIC/Kernal/Char ROM, I/O) |
| Disk Drive | D64/G64 via Kernal traps, high-level D64 PRG SAVE with exportable modified image bytes, plus true-drive 1541 read path with IEC/VIA/GCR emulation |
| Tape | T64 and TAP container formats |
| Cartridges | Standard CRT parsing with 8K/16K/Ultimax ROM mapping, Action Replay bank/RAM/IO2 mapping, KCS Power ROM/IO/RAM mode control, Atomic Power/Nordic Power ROM/RAM/Ultimax mode control, Action Replay 3 mirrored ROML/ROMH mapping, Action Replay 4 bank/control/IO2 mapping, Final Cartridge I IO-toggle mapping, Final Cartridge Plus segmented ROM/control mapping, Final Cartridge III 16K bank/control/NMI mapping, Simon's BASIC upper-ROM control, Super Games 16K bank/control latch, C64 Game System/System 3 IO1-address bank switching, Warp Speed IO mirroring and ROM-window control, Stardos capacitor-gated ROML/Kernal replacement mapping, Game Killer Kernal-window ROM and IO disable latch, Prophet64 IO2 bank/disable control, EXOS HIRAM-gated Kernal replacement mapping, Freeze Frame reset/IO/freeze ROM-window control, Freeze Machine 16K/32K reset/IO/freeze ROM-window control, Snapshot64 freeze-visible 4K Ultimax ROM mapping, Super Explode V5 bank/IO2/capacitor-gated ROM control, Super Snapshot V5 ROM/RAM/control mapping, MACH 5 ROM/IO mirror enable-disable control, Dinamic IO1-read bank switching, Zaxxon fixed-ROM read-selected upper banks, COMAL-80 black/default 16K bank switching, Structured BASIC IO1 bank/off control, Ross read-triggered bank/off control, Dela EP64/EP7x8/EP256 and Rex EP256 EPROM bank decoding, Mikro Assembler IO mirrors, Magic Formel `$E000` bank switching, Magic Desk ROML bank switching, Ocean type 1 bank switching, Fun Play/Power Play bank switching, Epyx FastLoad ROM/IO2/capacitor-gate behavior, EasyFlash bank/control/RAM mapping, and normal-mapped Westermann/Rex cartridge aliases |

### What needs work

- Many games and demos will not run correctly yet — VIC-II timing, sprite multiplexing, and advanced raster effects need further refinement
- True-drive 1541 compatibility is read-focused and still being validated against protected G64/custom-loader disks
- True-drive GCR writes, native G64 write-back, and low-level 1541 format support are deferred until read compatibility is stable
- NIB/P64/flux-level media import and G64 write-back are not implemented; weak/random bit readback is available for low-level tracks that provide weak-bit ranges
- SID filter is simplified and not yet calibrated to measured 6581/8580 curves
- Freezer button CPU-state capture, Super Snapshot V5 32K RAM-expansion setting, COMAL-80 grey-revision mode selection, deeper fastloader protocol validation, EasyFlash flash writes, REU, and broader expansion-port DMA/I/O are not implemented
- Selectable CRT display shader support is available in the macOS app for scanlines, phosphor mask, and a little composite-style softness

See [CompatibilityStatus.md](CompatibilityStatus.md) for the preservation-grade compatibility roadmap and subsystem status.

### Recent emulation work

- The macOS app now has Settings for machine/drive profile selection and local ROM file paths instead of relying on distributable bundled ROMs
- The macOS app now includes an opt-in CRT display shader with adjustable intensity
- ROM loading now validates expected stock ROM sizes before applying Settings-selected files
- PAL/NTSC machine profiles now drive exact emulation frame cadence and macOS display refresh hints as well as VIC/CIA/SID timing
- Machine profiles can now target 1541-II drive variants for PAL/NTSC C64 and C64C compatibility manifests
- CIA CNT line rising edges now drive Timer A/Timer B CNT counting and SP serial input shifts, improving pin-level serial/timer compatibility for loaders and peripherals
- CIA serial output now preserves SDR writes made before output mode is enabled and starts shifting the pending byte when CRA serial-output mode is selected
- NMOS 6502 decimal ADC/SBC now have exhaustive operand/carry coverage for hardware-style accumulator and flag behavior, including invalid BCD inputs and cases where the final BCD result differs from the flags' source values
- NMOS 6502 RDY input is now modeled as a line-level CPU pin that stalls opcode/data reads while allowing in-progress write cycles to complete
- VIC-II AEC-low bus stealing now drives the CPU RDY line instead of skipping CPU ticks, so halted reads freeze while pending writes can still drain
- NMOS 6502 IRQ masking now honors the one-boundary delay after late `I` flag changes from `CLI`, `SEI`, and `PLP`
- Simultaneous NMI/IRQ arbitration now has focused coverage: NMI vectors first, then a still-asserted IRQ is serviced after RTI restores `I` clear
- BRK/IRQ/NMI stack status bytes now have focused coverage: BRK pushes the break flag set while hardware IRQ/NMI pushes it clear
- NMI can now hijack BRK/IRQ vector fetches before the low vector byte is read, while late NMIs are prevented from half-hijacking only the high byte; held late NMIs are deferred until after the first handler opcode, and released transients are missed
- CIA keyboard scanning now propagates pressed-key bridges through the 8x8 matrix, including phantom-key behavior in both row-driven and column-driven scan directions
- CIA joystick-port lows now participate in keyboard matrix propagation, matching the shared CIA1 row/column wiring used by real joystick and keyboard interactions
- SID 6581 combined noise waveforms now approximate DAC-bit drain toward noise LFSR lockup while 8580 preserves the cleaner digital combined-noise path; TEST-bit reseeding covers recovery from the locked state
- SID waveform DAC output now floats briefly after all waveforms are disabled, preserving short sample-trick output windows before the latch decays to silence
- SID 6581 saw+pulse combined waveform output now uses the saw/triangle DAC-mix approximation, while 8580 keeps pulse-gated digital saw masking
- SID ADSR attack now switches to decay on the same envelope step that reaches maximum level instead of waiting for an extra attack period
- SID ADSR decay now enters sustain on the same envelope decrement that reaches the current sustain level
- SID output-stage volume DAC now uses model-specific curves: a stronger non-linear 6581 DC offset path and a smaller near-linear 8580 path
- SID filter resonance damping is now model-specific, with routed voices remaining inaudible when no low/band/high-pass output mode is selected
- VIA 6522 shift-register reads and writes now acknowledge the SR interrupt flag, matching register-side behavior needed before deeper serial shift timing work
- VIA 6522 shift-register modes 1-7 now shift CB2 data in/out under Timer 2, PHI2, or external CB1 clock control, including free-running T2 output recirculation and eight-pulse SR interrupts
- VIA 6522 internally clocked shift-register modes now expose CB1 output-clock pulses for peripherals that observe the generated serial clock
- VIA 6522 Timer 1 now drives and notifies PB7 output changes from underflows and ACR mode changes when PB7 is configured as an output, while preserving external PB7 input reads for SYNC/write-protect style wiring
- VIA 6522 Port A output changes now have observable callbacks on ORA/DDRA writes, giving disk/peripheral integrations the same kind of immediate pin-update hook already used on Port B
- VIA 6522 CA2 handshake and pulse output modes now respond to ORA writes as well as ORA reads
- VIA 6522 CB2 manual, handshake, and pulse output modes now track PCR and Port B access with observable output-state callbacks, including CB1-edge handshake release
- 1541 motor control now models a bounded spindle spin-down window after the VIA motor command turns off, instead of stopping the GCR head instantly
- 1541 media insert/eject now clears stale GCR head sync, byte-ready, shift-register, and delayed-SO state so a new disk cannot inherit read-pipeline state from the previous image
- High-level KERNAL SAVE to mounted D64 images now writes proper PRG load-address headers, accepts `0:`/`,P` style disk filename syntax, supports `@0:` replace saves, updates PRG sector chains, directory entries, and BAM free maps, and provides app-visible dirty tracking with an explicit Export Modified D64 command
- High-level 1541 command-channel `N:`/`NEW:` formatting now clears writable D64 images, rebuilds the BAM and empty directory, preserves D64 geometry/error-table shape, and reports status-channel results
- High-level disk command-channel support now handles `OPEN15,8,15,"S:FILE"` style SCRATCH/delete commands, wildcard deletes, `R:NEW=OLD` renames, `C:NEW=OLD` PRG copies, `V:`/`VALIDATE` BAM rebuilds, `B-R`/`U1` block reads into data channels, and status-channel readback
- The 1541 GCR head now supports weak/random bit ranges on low-level tracks, producing unstable readback for protected-media regions that importers can annotate
- Empty odd halftracks now fall back to adjacent full-track flux, while explicit native G64 halftrack data still overrides the fallback
- Drive status, local milestone expectations, and JSONL results now distinguish requested head halftrack from the effective low-level halftrack being read
- Compatibility manifests can now select PRG/D64/G64/T64/TAP/CRT media and `fastLoad`, `compat1541`, or `standard1541` drive modes per milestone
- Compatibility milestone timeouts now report deterministic unmet expectations for PC ranges, GCR/byte-ready progress, drive status, media capabilities, RAM/color-RAM signatures, screen hashes, and color RAM hashes
- Media capability checks now include weak/random-bit range counts, total weak-bit coverage, and per-byte variable-speed-zone coverage for protected G64 validation
- Compatibility milestone runs can now append categorized JSONL result logs with final PC/drive/media/tape/screen state, write compact aggregate JSON summaries, and resume by skipping milestones that already passed in a previous log
- Compatibility milestones with `screenshotName` can now write opt-in PPM framebuffer snapshots through `SWIFT64_LOCAL_MILESTONE_SCREENSHOT_DIR`
- Machine profiles now include PAL/NTSC C64C variants that select the 8580 SID while preserving matching video, CIA TOD, and 1541C timing
- Standard CRT cartridge images now mount through the app and map ROML/ROMH for 8K, 16K, and Ultimax cartridges
- Action Replay CRT cartridges now parse type 1 images, switch 8K ROM banks through IO1, expose the current ROM or cartridge RAM through IO2, support the RAM overlay at `$8000-$9FFF`, and honor the disable bit
- KCS Power CRT cartridges now parse type 2 images, expose 16K/8K/Ultimax/RAM-off modes through IO1 access, mirror the second-last ROML page in IO1, and provide the 128-byte IO2 RAM/status behavior
- Atomic Power/Nordic Power CRT cartridges now parse type 9 images, switch four 8K ROM banks, expose ROM/RAM/off/Ultimax modes through IO1, support the special `$A000` RAM window, and mirror the active ROM/RAM page through IO2
- Action Replay 3 CRT cartridges now parse type 35 images, switch two 8K ROM banks through IO1, mirror the active bank into ROML/ROMH, and honor EXROM-hide and disable control
- Action Replay 4 CRT cartridges now parse type 30 images, switch 8K ROM banks through IO1, mirror the selected ROM's first page through IO2, and honor ROM-hide/freeze-end disable control
- Final Cartridge I CRT cartridges now parse type 13 images, map the 16K ROM at `$8000-$BFFF`, expose cartridge ROM through IO1/IO2, and toggle ROM visibility off/on through IO1/IO2 access
- Final Cartridge Plus CRT cartridges now parse type 29 images, map the 32K image segments into `$8000`, `$A000`, and `$E000`, and honor IO2 enable/visibility/readback control bits
- Final Cartridge III CRT cartridges now parse type 3 images, select 16K banks through `$DFFF`, mirror selected bank bytes through IO1/IO2, honor the register-hide bit, and drive the CPU NMI line through the cartridge control register
- Simon's BASIC CRT cartridges now parse type 4 images and control the upper ROM through IO1 writes
- Super Games CRT cartridges now parse type 8 images, switch four 16K banks through `$DF00`, and honor the disable/write-protect latch until reset
- C64 Game System/System 3 CRT cartridges now parse type 15 images and select 64 ROML banks through `$DE00-$DE3F` IO1 address accesses
- Warp Speed CRT cartridges now parse type 16 images, mirror `$9E00-$9FFF` into IO1/IO2, and toggle the `$8000-$BFFF` ROM window through IO2/IO1 writes
- Stardos CRT cartridges now parse type 31 images, expose the `$E000-$FFFF` Kernal replacement, and model IO1/IO2 capacitor-gated ROML enable/disable behavior
- Game Killer CRT cartridges now parse type 42 images, expose the `$E000-$FFFF` ROM while leaving lower memory as normal RAM, and disable after two IO1/IO2 writes
- Prophet64 CRT cartridges now parse type 43 banked ROML images and use IO2 writes for 32-bank selection and cartridge disable control
- EXOS CRT cartridges now parse type 44 images and expose the `$E000-$FFFF` Kernal replacement only while HIRAM is selected
- Freeze Frame CRT cartridges now parse type 45 images, map their 8K ROM at `$8000` after reset, toggle visibility through IO1/IO2 reads, and mirror the ROM into `$E000` through the cartridge freeze hook
- Freeze Machine CRT cartridges now parse type 46 16K/32K images plus VICE-compatible split 8K layouts, map lower/upper ROM halves through reset, IO1, IO2, and freeze-window behavior, and toggle the active 16K bank on reset for 32K images
- Snapshot64 CRT cartridges now parse type 47 images, keep their 4K ROM hidden after reset, expose it in Ultimax-style `$8000/$9000/$E000/$F000` mirrors through the cartridge freeze hook, and hide it again on IO2 writes
- Super Explode V5 CRT cartridges now parse type 48 images, switch two 8K ROML banks through `$DF00` bit 7, mirror the active bank's last page in IO2, and approximate its capacitor-gated ROM visibility timeout
- Super Snapshot V5 CRT cartridges now parse type 20 64K/128K images, mirror the selected `$9E00` ROM page through IO1, switch ROM banks and ROM/RAM visibility through IO1 writes, and expose the stock 8K RAM overlay path
- MACH 5 CRT cartridges now parse type 51 4K/8K images, mirror `$9E00-$9FFF` into IO1/IO2, and use IO1/IO2 writes for ROM enable/disable control
- Dinamic CRT cartridges now parse type 17 images and select 16 ROML banks through `$DE00-$DE0F` IO1 read accesses
- Zaxxon/Super Zaxxon CRT cartridges now parse type 18 images, mirror the fixed `$8000-$8FFF` ROM at `$9000`, and select upper ROMH banks through fixed-ROM reads
- COMAL-80 CRT cartridges now parse type 21 4-bank and optional 8-bank black/default images, map 16K banks at `$8000-$BFFF`, and use mirrored IO1 writes for bank/off control
- Structured BASIC CRT cartridges now parse type 22 images and use `$DE00-$DE03` read/write accesses for bank selection and cartridge-off control
- Ross CRT cartridges now parse type 23 16K/32K images and use `$DE00/$DF00` reads for bank selection and cartridge-off control
- Dela EP64 CRT cartridges now parse type 24 images, accept 8K banks or 32K EPROM blocks, decode `$DE00` bank bits, and honor bit 7 cartridge-off control
- Dela EP7x8 CRT cartridges now parse type 25 images and select one of eight 8K banks through one-hot-low `$DE00` values
- Dela EP256 CRT cartridges now parse type 26 images and decode the documented `$38-$3F`, `$28-$2F`, `$18-$1F`, and `$08-$0F` bank windows
- Rex EP256 CRT cartridges now parse type 27 images, bank 8K/16K/32K EPROM sockets through `$DFA0`, and honor `$DFC0/$DFE0` EXROM off/on reads
- Mikro Assembler CRT cartridges now parse type 28 images and mirror `$9E00-$9FFF` into IO1/IO2
- Magic Formel CRT cartridges now parse type 14 images, switch eight `$E000-$FFFF` ROM banks through `$DF00-$DF07`, and support the `$FF` to `$DF00` normal-Kernal fallback
- Magic Desk CRT cartridges now parse type 19 banked ROML images and switch banks through IO1 writes
- C64 reset/power-on now restores cartridge latch state so banked cartridges return to their startup bank
- Ocean type 1 CRT cartridges now parse type 5 banked ROML/ROMH images and switch banks through IO1 writes
- Fun Play/Power Play CRT cartridges now parse type 7 banked ROML images and switch banks through their decoded IO1 values
- Westermann Learning and Rex Utility CRT cartridge types now mount through the existing normal 16K/8K mapping path
- Epyx FastLoad CRT cartridges now parse type 10 images, expose the 8K ROM at `$8000`, mirror the last ROM page through IO2, and model the documented 512-cycle IO1/ROML capacitor-gated ROM enable timeout
- EasyFlash CRT cartridges now parse type 32 images, switch banks through `$DE00`, control 8K/16K/Ultimax/off modes through `$DE02`, and expose the `$DF00` RAM page
- RESTORE is now modeled as a C64 machine input that triggers an edge-sensitive CPU NMI
- SID voice output now centers before envelope application and distinguishes 6581 vs 8580 volume-DAC bias
- SID voice routing now feeds a bounded state-variable filter with model-specific cutoff scaling and correct voice-3-off direct-output behavior
- SID external audio input is clamped to audio range and can now be mixed directly or routed through the filter through `$D417` bit 3
- SID ADSR decay/release now use the exponential counter thresholds instead of decrementing linearly at every rate tick
- SID sustain state now responds to lowered sustain levels by resuming decay instead of freezing at the old level
- SID noise generation now clocks the LFSR on accumulator bit 19 and maps the documented shift-register taps into OSC/noise output bits
- SID combined noise waveforms now mask noise output with selected triangle/saw/pulse output instead of ignoring the other waveform bits
- SID triangle ring modulation now follows the sync-source oscillator MSB and leaves non-triangle waveforms unaffected
- SID pulse waveforms now handle zero/max pulse-width edge cases and compare against the top 12 accumulator bits
- SID voices with no waveform selected now contribute silence instead of a spurious centered negative signal
- SID TEST-bit handling now keeps noise cleared while held and reseeds the noise shift register when released
- SID direct chip reads now model a decaying local data-bus latch while memory-mapped write-only SID reads still preserve C64 CPU open-bus behavior
- SID ADSR timing now uses a 15-bit equality-based rate counter, exposing the classic delay-bug behavior when switching to faster envelope rates after the counter has already passed the new period
- VIC-II timing now follows the active PAL/NTSC profile for cycles per rasterline and rasterlines per frame
- CIA TOD timing now exposes PAL/NTSC-derived 50 Hz and 60 Hz rates and switches them through CRA bit 7
- CIA serial input now shifts SP on CNT pulses, serial output shifts on Timer A underflows, and completed transfers raise the serial interrupt source
- CIA serial output now keeps SDR bytes pending across output-mode changes so software can prime the serial register before enabling CRA bit 6
- CIA keyboard matrix reads now include multi-key bridge/phantom behavior instead of only direct key intersections
- CIA joystick port 1/2 switch lows now feed the same keyboard matrix bridge model instead of only affecting final port bits
- CIA timer output now drives PB6/PB7 pulse and toggle modes for software that observes user-port/timer pins
- SID oscillator sync now resets voices on source MSB rising edges instead of source level, improving hard-sync behavior
- The 6510 CPU port now exposes cassette sense, write, and motor-control line levels for later datasette signal-path work
- TAP v0/v1 images now auto-arm raw pulse playback through the C64 tape mount path and can drive CIA1 FLAG edges
- TAP raw playback now idles CIA1 FLAG high whenever the cassette motor is off, avoiding stale tape pulses after motor stops or reset
- Raw TAP playback now has machine-level play/stop control, app-visible tape signal status, and end-of-tape cassette sense release so TAP playback no longer leaves the machine thinking PLAY is held after the pulse stream ends
- Stock CBM TAP files now decode short/medium/long pulse pairs into parity-checked bytes for raw PRG-like blocks, header+data block pairs, multiple named programs per TAP, duplicate header/data layouts, clean duplicate data fallback after a parity-damaged first copy, cross-copy byte voting when duplicate data copies have different parity-damaged bytes, and conservative rejection of conflicting duplicate data copies
- TAP mounts now expose decode diagnostics through emulator status, distinguishing raw pulse-only playback, decoded standard CBM programs, malformed/parity-damaged blocks, incomplete header/data pairs, and conflicting duplicate data copies
- The 6510 cassette write and motor-control outputs now emit effective line-change callbacks, and the datasette captures motor-gated write pulse timing with C64 status/API visibility, TAP v0/v1 export, and macOS File/toolbar export actions for future SAVE/write support
- Kernal-trap SAVE to tape device 1 now creates or appends to a virtual T64 image with C64 status/API visibility and macOS export actions, while mounted TAP images are left untouched
- Mounted tape names now surface through C64 status and the macOS sidebar/popover, and virtual T64 SAVE output round-trips through the tape LOAD trap
- macOS tape opens now use the same sandbox-safe user-selected file path as disk images, covering menu opens, toolbar opens, and drag/drop
- Tape image replacement now clears stale raw TAP playback cursors, signal level, and pulse data so T64/TAP swaps cannot inherit the previous tape's signal path
- T64 mounting now rejects directory entries whose payload ranges fall outside the image, preventing mounted-but-unreadable tape state after corrupt media swaps
- True-drive D64 directory and PRG loads now pass hardware-path smoke tests through IEC, 1541 DOS, GCR byte-ready, and C64 RAM transfer checks
- Extended 40/41/42-track D64 images now keep their extra-track geometry for fast sector reads and synthetic true-drive GCR tracks
- D64 images with appended sector-error tables now preserve per-sector error metadata for future bad-sector/GCR error simulation
- D64 sector-error tables now corrupt synthetic GCR sync/header/data/checksum/disk-ID fields for common read-error codes
- Media capabilities and compatibility manifests now expose total and non-default D64 sector-error code counts so bad-sector fixtures can be validated without opening binary snapshots
- D64 directory and PRG sector-chain walkers now stop on cyclic chains instead of hanging on malformed media
- KERNAL VERIFY traps now compare disk data against RAM and report verify mismatches without modifying memory
- KERNAL SAVE traps now write PRG files with proper load-address headers to mounted D64 images in fast/convenience mode and still report an error when no writable disk path is available
- G64 fast-path sector decoding now keeps whole-track data beyond track 35 by producing extended D64 geometry when present
- G64 fast-path sector decoding now validates GCR symbols plus header/data checksums instead of accepting corrupted sectors as good data
- G64 fast-path sector decoding now fails when no sectors decode, while native true-drive G64 streams still mount as low-level media
- G64 low-level loading now rejects unsupported G64 versions instead of accepting unknown layouts as native tracks
- G64 low-level loading now rejects images without track data and keeps the previous disk mounted after failed loads
- G64 native tracks now preserve per-byte speed-zone blocks and the 1541 GCR head uses those maps for variable-speed read timing
- G64 media capabilities now report raw track length, constant speed-zone, and halftrack preservation accurately for native tracks
- 1541 media insert and write-protect changes now refresh the VIA2 disk-controller input lines that drive ROM code observes
- 1541 reset/power-on now clears VIA timers, interrupts, port state, byte-ready, and GCR head state while keeping mounted media inserted
- C64 reset now also resets true-drive 1541 hardware state and clears host-queued typed commands without ejecting mounted media
- C64 reset now clears CIA timer, interrupt, serial, TOD, and CIA2 IEC output state so reset releases serial lines and deasserts IRQ/NMI
- C64 reset now clears VIC-II register/raster/IRQ state and SID voice/filter/audio state while preserving selected video and SID models
- C64 reset now restores the 6510 CPU port before reset-vector fetches, so Kernal ROM is visible even after software banks ROM out
- 6502/6510 reset now recovers from JAM/KIL opcodes and resumes through the reset vector instead of staying halted
- 6502/6510 reset now discards stale pending NMI edges and does not immediately retrigger a held NMI line after reset
- VIC-II sprite rendering now has corrected X placement, sprite-sprite and sprite-background collision latches, collision IRQs, and foreground-mask based sprite priority/collision behavior
- VIC-II bad-line timing now exposes separate BA warning and AEC halt phases, reports per-cycle bad-line character-fetch bus ownership, and stalls the C64 CPU only during the AEC-low fetch window while VIC/CIA/SID/drive timing continues
- VIC-II sprite fetching now uses deterministic two-cycle per-sprite DMA slots with observable bus ownership and CPU stalls instead of repeatedly fetching every sprite during the loose sprite window
- VIC-II sprite DMA now drops BA during the pre-DMA warning window, including slots that begin just after the rasterline wraps, while keeping the CPU running until AEC goes low
- VIC-II timing now exposes low-phase refresh, display-data, sprite-pointer, and active-sprite middle-byte access phases separately from CPU-stealing high-phase bus ownership
- VIC-II sprite pointer bytes are now latched during their low-phase pointer slots and later consumed by the sprite DMA fetch path
- VIC-II bad-line fetches now latch both character codes and color RAM nibbles into the line buffers during the character-fetch window
- VIC-II text/bitmap rendering now uses completed bad-line matrix/color buffers instead of rereading live screen/color RAM for the already-latched character row
- VIC-II latched matrix buffers are now tied to their fetched VCBASE, preventing a completed row buffer from being reused for the wrong character row
- VIC-II row-counter state now resets on bad lines, advances through rendered display lines, and selects glyph rows for completed latched matrix rows
- VIC-II low-phase display-data cycles now latch glyph/bitmap bytes into a graphics buffer that rendering can consume when the row and pixel row match
- VIC-II live color RAM fallback reads now mask to the same four-bit color RAM values used by bad-line latches
- VIC-II sprite vertical-expansion state now initializes per rasterline, keeps unexpanded sprites advancing every line, and repeats expanded sprite rows through the sprite data counter path
- VIC-II sprite MC now tracks byte offsets through sprite data and advances by three bytes after each sprite DMA row fetch
- CIA interrupt masking/read-clear behavior now deasserts CPU IRQ/NMI lines cleanly and avoids duplicate active callbacks
- C64-level interrupt tests cover combined CIA/VIC IRQ assertion and deassertion

## Building

Requires Swift 5.9+ and macOS 14+.

```sh
swift build -c release
```

### ROMs

ROM files are copyrighted and are not distributed with this project. Open the app's Settings window and choose local paths for:

- BASIC ROM (8K)
- Kernal ROM (8K)
- Character ROM (4K)
- 1541/1541C/1541-II drive ROM (16K)

For local development and compatibility testing, the app still falls back to untracked ROM files under `C64/ROMS` or `Sources/C64App/ROMS` when explicit Settings paths are not configured.

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
SWIFT64_SLOW_TRUE_DRIVE_TESTS=1 swift test --filter Drive1541Tests/testTrueDriveD64DirectoryLoadStartsGCRReadHardware
SWIFT64_SLOW_TRUE_DRIVE_TESTS=1 swift test --filter Drive1541Tests/testTrueDriveD64PrgLoadUsesFileAddress
```

Local public CPU functional-test binaries are also opt-in and run as a single bounded emulator instance. Keep those binaries untracked and provide the success self-loop address for the specific fixture you are running:

```sh
SWIFT64_CPU_FUNCTIONAL_TEST_PATH=/path/to/6502_functional_test.bin \
SWIFT64_CPU_FUNCTIONAL_SUCCESS_PC=0x3469 \
SWIFT64_CPU_FUNCTIONAL_START_PC=0x0400 \
SWIFT64_CPU_FUNCTIONAL_MAX_CYCLES=100000000 \
swift test --filter CPU6502ConformanceTests
```

For resumable local milestone runs, add a JSONL result log path. Reuse the same path with `SWIFT64_LOCAL_MILESTONE_RESUME=1` to skip milestones that already recorded a passing result:

```sh
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_RESULTS_JSONL=/tmp/swift64-milestones.jsonl swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_RESUME=1 SWIFT64_LOCAL_MILESTONE_RESULTS_JSONL=/tmp/swift64-milestones.jsonl swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
```

To write a compact aggregate summary for dashboards or manual triage, set `SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON`. The per-milestone JSONL records include a format version, the milestone media type, action summary, max-cycle budget, final PC, 1541 drive state, media capability counts including weak-bit and variable-speed-zone counters, tape state, screen hashes, and optional screenshot paths. The aggregate summary records pass/fail/skip counts, category counts including `protectedMedia`, `cartridge`, and `app`, tape-specific failures, cycle totals, the slowest milestone, failed milestone details, and failed/skipped milestone keys:

```sh
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_RESULTS_JSONL=/tmp/swift64-milestones.jsonl SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
```

To capture passing milestone framebuffers, set a screenshot output directory. Files are written as portable PPM images using sanitized `screenshotName` values from the manifest:

```sh
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_SCREENSHOT_DIR=/tmp/swift64-screens swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
```

The named milestone test has a built-in Great Giana Sisters G64 custom-loader progress checkpoint when that local file is present. You can override or add stricter PRG/D64/G64/T64/TAP/CRT screen, color RAM, RAM, drive, media, and one-or-more-PC-range milestones with an untracked `C64/DISKS/compatibility.json` file.

Useful fast regression slices:

```sh
swift test --filter VICTests
swift test --filter CIATests
swift test --filter C64InterruptTests
swift test --filter C64TimingTests
swift test --filter Drive1541Tests
```

The slow true-drive serial-load milestones inside `Drive1541Tests` are skipped by default unless `SWIFT64_SLOW_TRUE_DRIVE_TESTS=1` is set, because they run multi-million-cycle 1541 ROM paths.

Example milestone manifest:

```json
{
  "milestones": [
    {
      "file": "great_giana_sisters[time_warp_1987](pal)(r1)(!).g64",
      "mediaType": "g64",
      "machineProfile": "palC64",
      "driveMode": "compat1541",
      "commands": ["LOAD\"*\",8,1", "RUN"],
      "actions": [
        { "type": "text", "text": "LOAD\"*\",8,1" },
        { "type": "wait", "cycles": 1200000 },
        { "type": "joystickDown", "control": "fire" },
        { "type": "wait", "cycles": 100000 },
        { "type": "joystickUp", "control": "fire" },
        { "type": "keyDown", "key": "space" },
        { "type": "keyUp", "key": "space" },
        { "type": "stopTape" },
        { "type": "wait", "cycles": 120000 },
        { "type": "startTape" }
      ],
      "maxCycles": 24000000,
      "pcStart": 49152,
      "pcEnd": 53247,
      "pcRanges": [
        { "start": 2048, "end": 4095 },
        { "start": 49152, "end": 53247 }
      ],
      "driveStatus": {
        "minGCRReads": 64,
        "minByteReady": 512,
        "minSyncDetections": 1,
        "minWeakBitReads": 1,
        "minVariableSpeedZoneSamples": 1,
        "requiredVariableSpeedZones": [0, 3],
        "hasNativeLowLevelImage": true,
        "readTrack": 18,
        "readHalfTrack": 34,
        "usingHalfTrackFallback": false
      },
      "mediaStatus": {
        "populatedHalfTrackCount": 84,
        "nativeLowLevelTrackCount": 84,
        "syntheticGCRTrackCount": 0,
        "hasSyntheticGCR": false,
        "isNativeLowLevel": true,
        "preservesHalfTracks": true,
        "preservesRawTrackLengths": true,
        "preservesSpeedZones": true,
        "preservesVariableSpeedZones": true,
        "preservesSectorErrorInfo": false,
        "sectorErrorCodeCount": 0,
        "nonDefaultSectorErrorCodeCount": 0,
        "weakBitRangeCount": 0,
        "weakBitTotalBitCount": 0,
        "variableSpeedZoneByteCount": 0,
        "supportsWraparoundReads": true,
        "maxTrackSize": 7928,
        "unsupportedFeaturesContains": ["Weak/random bits", "Write-back"]
      },
      "weakBitRanges": [
        { "halfTrack": 34, "startBit": 128, "endBit": 255 }
      ],
      "speedZoneRanges": [
        { "halfTrack": 34, "startByte": 0, "endByte": 127, "zone": 0 },
        { "halfTrack": 34, "startByte": 128, "endByte": 255, "zone": 3 }
      ],
      "tapeStatus": {
        "mountedTapeNameContains": "loader.tap",
        "decodeStatus": "rawPulsesOnly",
        "pulseCount": 1024,
        "programCount": null,
        "blockCount": null,
        "decodeFailureReason": null,
        "rawPlaybackActive": true,
        "readSignalHigh": false,
        "cassetteSenseLineHigh": false,
        "cassetteMotorEnabled": true,
        "hasCapturedWritePulses": false,
        "canExportCapturedTAP": false,
        "hasUnsavedChanges": false,
        "canExportSavedT64": false
      },
      "ramSignatures": [
        { "address": 2049, "bytes": "01 08" }
      ],
      "colorRAMSignatures": [
        { "address": 0, "bytes": "06 0e 01" }
      ],
      "cpuRegisters": {
        "pc": "$c000",
        "a": "$01",
        "x": "$02",
        "y": "$03",
        "sp": "$fa",
        "p": "$24",
        "pMask": "$ef"
      },
      "sidRegisters": [
        { "register": "$D418", "value": "$0f" },
        { "register": "$D404", "value": "$21", "mask": "$f1" }
      ],
      "vicRegisters": [
        { "register": "$D020", "value": "$06", "mask": "$0f" },
        { "register": "$D011", "value": "$3b" }
      ],
      "cia1Registers": [
        { "register": "$DC0E", "value": "$41", "mask": "$41" }
      ],
      "cia2Registers": [
        { "register": "$DD02", "value": "$3f" }
      ],
      "screenTextContains": ["READY.", "PRESS FIRE"],
      "screenRAMHash": "optional-fnv1a64-screen-ram-hash",
      "colorRAMHash": "optional-fnv1a64-color-ram-hash"
    }
  ]
}
```

When `actions` is omitted, the runner converts `commands` into cycle-0 typed text actions. Explicit actions can type text, wait a fixed number of C64 cycles, press/release joystick controls (`up`, `down`, `left`, `right`, `fire`), press/release named C64 keys such as `space`, `return`, `runStop`, `restore`, cursor keys, and function keys, and control TAP playback with `startTape`/`stopTape`. `screenTextContains` checks decoded screen RAM text without requiring a brittle full-screen hash. `cpuRegisters` checks PC/A/X/Y/SP/P state with an optional `pMask`; `sidRegisters`, `vicRegisters`, `cia1Registers`, and `cia2Registers` check effective chip register state with optional masks for audio/video/timer milestones. `tapeStatus` checks mounted tape names, TAP decode diagnostics (`none`, `rawPulsesOnly`, `decodedPrograms`, `standardCBMNoPrograms`), raw TAP playback, cassette read/sense/motor lines, and tape export/dirty state. This lets local milestones cover title screens, loader prompts, CPU handoff points, basic SID/VIC/CIA initialization, and datasette signal milestones without custom test code.

### Keyboard

The Mac keyboard maps to the C64 keyboard layout. Escape maps to RUN/STOP, and Page Up or F12 act as RESTORE keys that trigger NMI. Joystick port 2 is mapped to the numpad (8/2/4/6 for directions, 0 or Enter for fire).

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
