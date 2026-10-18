# Testing

## True-drive compatibility testing

Local disk-image matrix tests are opt-in because they depend on files under `C64/DISKS`:

```sh
SWIFT64_LOCAL_DISK_MATRIX=1 swift test --filter LocalDiskMatrixTests/testLocalDiskImagesMountAndEncodeWhenEnabled
SWIFT64_LOCAL_TRUE_DRIVE_MATRIX=1 swift test --filter LocalDiskMatrixTests/testLocalDiskImagesTrueDriveDirectorySmokeWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_SLOW_TRUE_DRIVE_TESTS=1 swift test --filter Drive1541Tests/testTrueDriveD64DirectoryLoadStartsGCRReadHardware
SWIFT64_SLOW_TRUE_DRIVE_TESTS=1 swift test --filter Drive1541Tests/testTrueDriveD64PrgLoadUsesFileAddress
```

Performance benchmarks are also opt-in and should usually be run in Release. They measure fast-load, compat true-drive, strict true-drive, raw cycle throughput, SID fast/compatibility throughput, and audio drain paths without starting broad media matrices:

```sh
SWIFT64_PERF_BENCHMARKS=1 swift test -c release --filter PerformanceBenchmarkTests
```

The experimental public SID conformance runner is not yet a certification gate: fixture entry/completion handling still needs independent validation. Programs are opt-in and fetched into `.build`, not committed. The fetch script pins the VICE-testprogs revision. Runs stay sequential and instantiate one C64 at a time; use `SWIFT64_PUBLIC_SID_TEST_IDS` for a focused comma-separated subset:

```sh
script/fetch_sid_testprogs.sh
SWIFT64_PUBLIC_SID_TESTPROGS_DIR=.build/vice-testprogs \
SWIFT64_PUBLIC_SID_TEST_IDS=envrate,envdelay,noisetest \
swift test -c release --filter PublicSIDConformanceTests
```

## VIC sprite sequencer

These subsections record successive checkpoints. Later beam, shifter, and graphics-counter work supersedes the corresponding open items in earlier checkpoints; none substitutes for independently validated external demos.

Run the cycle/fetch/lifecycle regressions sequentially:

```sh
swift test -c release -j 2 --filter 'VICTests|VICSpriteShifterTests|VICBeamTimingTests|VICSlotTimingTests|VICSpriteFetchTests|VICSpriteDMALifecycleTests|VICPriorityTests|C64TimingTests'
```

`VICSpriteDMALifecycleTests` clocks the actual Y comparisons, DMA, byte-counter transfers, and display latches. It checks all eight sprites under PAL and NTSC, normal and expanded heights, early Y/enable changes, repeated Y matches, frame boundaries, late expansion stretching, and CPU writes around the cycle-15/16 crunch boundary. An original ROM-independent 6510 multiplexer program verifies every visible row and intervening gap for two successive sprites with different pointers, colors, and widths. No external ROM, screenshot, or program binary is needed. Tests that begin at an arbitrary fetch slot explicitly seed already-active DMA; they do not infer hardware state from raster-minus-Y arithmetic.

The timing reference is [Christian Bauer's VIC-II article](https://www.cebix.net/VIC-Article.txt), sections 3.6.3 and 3.8.1, supplemented by the hardware-checked public phi1 probes below. Current zero-based pointer-slot tables are PAL `[57,59,61,0,2,4,6,8]` and NTSC 6567R8 `[58,60,62,64,1,3,5,7]`. The original NTSC transcription was one cycle late and is superseded by the public result. Sprite 2's data burst finishes before line end; PAL sprite 3's BA warning crosses the boundary, while NTSC sprite 3's two-cycle DMA burst crosses it. Expansion crunch writes occur in hardware cycle 15 phi2 and affect the following cycle's MCBASE transfer.

2026-10-15: the combined checked Release slice (CPU, memory, SID quality/core, VIC/timing, CIA, drive, KERNAL traps, and manifest tests) passed 835 tests with 12 opt-in skips and zero failures. These results establish synthetic bus and CPU-driven framebuffer coverage, not full demo compatibility. Physical beam-X alignment, horizontal sprite-shifter behavior, advanced raster effects, and independently calibrated external FLI/open-border/multiplexer fixtures remain open. The local authoritative `compatibility.json` and external VIC fixtures were absent in this checkout; tracked example manifests are not passing corpus evidence. The sustained app-audio results below were recorded before these latest sprite changes and are not a new app-playback run.

`VICPriorityTests` adds 14 ROM-independent regressions for the graphics/sprite priority multiplexer and border output. It exercises both PAL/NTSC and traced/fallback composition: closed borders masking all sprites, side-border graphics collisions, top/bottom-border sprite collisions without graphics collisions, transparent sprite pixels, and every adjacent sprite-priority pair. A foreground-hidden higher-priority sprite must still occlude lower-priority sprites. Collision IRQ acknowledgement must not rearm a nonempty `$D01E/$D01F` latch; only reading the corresponding collision register rearms it. An original 6510 program observes that sequence through mapped registers while two overlapping sprites remain hidden behind the top border.

Additional checks distinguish main-border visibility from graphics output, preserve an opened border across a rasterline boundary, clock border comparisons outside the framebuffer crop, and keep DEN writes from acting as an immediate pixel blank. Existing sprite-color/shifter fixtures explicitly open the border where visibility is intended; closed-border tests retain collision assertions. The timing reference above covers priority and collision logic in section 3.8.2 and border/DEN behavior in sections 3.9-3.10. Physical dot-clock alignment and full horizontal-shifter behavior are separate remaining work, not certified by these tests.

Priority/border validation (2026-10-15): `swift build --build-tests -j 2` succeeded; the focused VIC/timing command above passed all 300 tests in Debug. The combined checked Release slice passed 849 tests, with 12 opt-in skips and no failures:

```sh
swift test -c release -j 2 --filter 'CPU6502Tests|MemoryMapTests|SIDAudioQualityTests|SIDTests|C64TimingTests|VICTests|VICSlotTimingTests|VICSpriteFetchTests|VICSpriteDMALifecycleTests|VICPriorityTests|CIATests|Drive1541Tests|KernalTrapsTests|CompatibilityManifestTests'
```

## VIC beam and matrix-fetch timing

`VICBeamTimingTests` adds 12 ROM-independent regressions. Literal chip timing and pixel expectations cover eight-dot color steps, horizontal counter wrap, end-of-cycle light-pen coordinates, BA/AEC boundaries, matrix-before-glyph ordering for every column, late bad-line startup, and collision onset. Original CPU `STA` programs exercise color splits and both successful and missed CSEL border-comparison windows under PAL and NTSC. PAL sprite wrap and unreachable X positions are tested in both traced and fallback rendering; nine-bit wrap fixtures explicitly select NTSC.

The reference is [Christian Bauer's VIC-II article](https://www.cebix.net/VIC-Article.txt), sections 3.6.1-3.6.3, 3.7.2, and 3.11. Zero-based matrix-fetch indices are 14-53, preceded by BA warning indices 11-13; glyph fetches remain at indices 15-54. Capturing pixels after the low-phase fetch prevents collision logic from reading stale graphics data. Existing beam-write tests were retimed without relaxing their pixel/priority/collision assertions.

The framebuffer retains its existing dimensions and logical sprite-X coordinates. Common analog output delay, exact signal crop, and sub-dot NTSC counter-hold behavior are not calibrated here. CPU register writes still take effect on the next whole-cycle sample. Full horizontal sprite-shifter consumption, VC/RC/VMLI sequencing and idle graphics, and independently calibrated FLI/open-border/multiplexer demo captures remain required. In particular, correcting the matrix-fetch window does not certify the entire late-bad-line display-state machine.

Beam validation (2026-10-15): all 312 focused VIC/timing tests passed in Debug, including the original CPU-driven sprite multiplexer and border/priority fixtures. The checked Release integration slice below passed 504 tests with zero skips and zero failures, sequentially:

```sh
swift test -c release -j 2 --filter 'CPU6502Tests|MemoryMapTests|VICTests|VICBeamTimingTests|VICPriorityTests|VICSlotTimingTests|VICSpriteFetchTests|VICSpriteDMALifecycleTests|C64TimingTests|CIATests'
```

## VIC horizontal sprite shifters

Beam output now consumes live 24-bit sprite registers, filled byte by byte by DMA. An X comparison starts shifting without reloading the diagnostic row snapshot. Writes to X or its high bit cannot move an active row or resurrect consumed data; expansion changes the rate of subsequent consumption. Monochrome and multicolor output share the underlying bit stream. Shifter state survives rasterline boundaries, and cropping no longer suppresses horizontal clocks or sprite-sprite collisions.

`VICSpriteShifterTests` adds 11 DMA-backed PAL/NTSC checks: fixed-width monochrome/multicolor rows and next-line reloads, expansion on/off mid-row, expansion after consumption, X changes before/during/after output, moving an unstarted sprite behind the beam, hidden tails across rasterline boundaries, collisions outside both framebuffer axes, and an original CPU store that attempts to replay a consumed row. The existing phased-fetch tests also assert the live shift-register contents after each DMA stage. Older component fixtures that bypass DMA explicitly seed both the diagnostic row and live register. Snapshot composition remains an unclocked helper, not the normal beam path.

Reference: [Christian Bauer's VIC-II article](https://www.cebix.net/VIC-Article.txt), section 3.8.1, describes bytewise loading, pixel shifting, and why a second X comparison cannot replay an emptied row. The two old X-write tests that expected horizontal replay now require the original tail to continue and the second position to remain empty. Whole-cycle register visibility, precise mixed-mode/expansion sub-dot phase changes, and fetch/output overlap still need independent hardware calibration; this does not certify all sprite tricks.

Shifter validation (2026-10-15): `swift build --build-tests -j 2` succeeded, and all 323 focused VIC/timing Debug tests passed, including the existing CPU-driven multiplexer, border, collision, and priority tests. The following sequential Release integration slice passed 533 tests with zero failures; no SID playback or audio test suite was run:

```sh
swift test -c release -j 2 --filter 'CPU6502Tests|MemoryMapTests|VICTests|VICSpriteShifterTests|VICBeamTimingTests|VICPriorityTests|VICSlotTimingTests|VICSpriteFetchTests|VICSpriteDMALifecycleTests|C64TimingTests|C64InterruptTests|CIATests'
```

## Public VIC programs and shared data bus

The opt-in runner uses public test programs from the [VICE test-program collection](https://github.com/libsidplayfp/VICE-testprogs/tree/ef8e8efe52f3d43df7acefad132c6506239bddee/VICII), pinned by `script/fetch_vic_testprogs.sh`. Programs and reference source remain under ignored `.build`; no emulator implementation, ROMs, or fixture binaries are incorporated into the project. The phi1 fixture's README describes its real PAL/NTSC hardware checks.

```sh
sh script/fetch_vic_testprogs.sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
  swift test -c release -j 2 --filter PublicVICConformanceTests
```

`SWIFT64_PUBLIC_VIC_TEST_IDS` selects a comma-separated subset. The original 43-case set includes `phi1-pal`, `phi1-ntsc`, `sprite-collision-pal`, `graphics-collision-pal`; six `fld-<timing>-pal` IDs; four `sprite-dma-<timing>-pal/ntsc` IDs; twelve PAL border IDs; and seventeen PAL sprite-register split IDs. Later sections document subsequent additions. The current default runs all **146 programs**, with **144 passing** and two unresolved strict mode-transition comparisons; see the [latest sprite reload results](#sprite-reload-and-cycle-stealing). Local ROMs default to `Sources/C64App/ROMS`; `SWIFT64_PUBLIC_VIC_ROM_DIR` can select another directory containing the same named BASIC, Kernal, and character files. PRG boot is bounded at 300 frames and must display READY; each original BASIC stub is then started with RUN. CRT fixtures instead boot through their cartridge reset vector. Programs have a three-million-cycle limit, except the two cycle-stealing probes with a 30-million-cycle limit for their frame-by-frame measurements. KERNAL traps are disabled. Completion requires the program's actual mapped CPU write to `$D7FF`, not a normalized SID mirror, patched instruction, direct PC entry, or scan for a result instruction. Nine bus/collision/acknowledgement/sprite-X/cycle-stealing programs self-check; the remaining programs additionally require exact color-index comparison, since their `$D7FF` write only requests capture. Instances run sequentially and are released between fixtures.

Measured Release results (2026-10-15), repeated with identical observables after the IRQ/NTSC/collision fixes:

| Fixture | `$D7FF` | Cycles after RUN injection | Final PC | Raster (zero-based cycle) |
| --- | --- | --- | --- | --- |
| `phi1-pal` | `$00` | 47,288 | `$08E1` | 126:38 |
| `phi1-ntsc` | `$00` | 42,563 | `$08E4` | 128:53 |
| `sprite-collision-pal` | `$00` | 141,065 | `$0928` | 55:8 |
| `graphics-collision-pal` | `$00` | 809,369 | `$0929` | 55:8 |

Before these corrections all four reported `$FF`: PAL bus samples began two cycles early, and the sprite collision test sampled raster 53 alternately at cycles 22/23, producing `03 00 03 00 03 00 00`. Correct CPU IRQ polling makes the read stable at cycle 24. The collision pipeline then yields the fixture's unchanged `03 03 00 00 00 00 00` expectation. Correcting the NTSC pointer slots resolves its remaining bus mismatch. No program instructions, reference data, or completion rules were changed.

`CPUInterruptPollingTests` covers penultimate-cycle IRQ eligibility for read/write/RMW/indexed instructions, late arrivals, retained short pulses, branch polling, and RDY stalls. CLI/SEI/PLP masking follows the sampled I bit; RTI restores it early. Four old tests now assert IRQ before a valid polling point rather than demanding retroactive recognition. Reference: the [Visual6502 interrupt timing observations and simulation links](https://tinymachines.ai/6502/archive/wiki/6502_Timing_of_Interrupt_Handling.html).

`VICCollisionPipelineTests` covers CPU reads around the public fixture's cutoff, preservation of pending coincidences across read-clear and rasterline boundaries, delayed IRQ assertion, and reset. The three four-dot stages model register visibility relative to the logical sprite-X counter; they are not a claim about physical silicon stage topology or analog video delay. PAL timing is externally calibrated here; NTSC collision subphases still need independent fixtures. Snapshot-only composition remains unclocked. Existing clocked collision fixtures now wait for the pipeline without relaxing pixel, priority, latch, or IRQ assertions.

These programs exposed two corrected bus defects: floating `$DE00/$DF00` reads previously returned the CPU's operand byte, and ECM incorrectly redirected i-accesses. VIC reads now drive the shared data bus, while true i-accesses always read `$3FFF`. Idle-state g-accesses retain ECM's `$39FF` behavior. `VICDataBusTests` checks every PAL and NTSC slot through actual 6510 reads, character-ROM/RAM bank selection, color-RAM high bits, and exclusion from CPU read hooks. A running VIC refreshes floating bus data even when the CPU is jammed. Reference: [Bauer's VIC-II article](https://www.cebix.net/VIC-Article.txt), sections 3.6.2, 3.7.1 and 4.

At the bus/collision checkpoint, `swift build --build-tests -j 2` passed, the focused Debug VIC/timing slice passed all 344 tests, and the following Release integration slice executed 725 tests: 714 passed, 11 opt-in slow-drive tests skipped, and no failures. That run's public-runner test included the four programs above. No SID test suite or audio playback was run. The later FLD work below adds visual proof and closes the demonstrated late-BA startup-color defects; broader sub-cycle and demo certification remains open.

```sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
  swift test -c release -j 2 --filter 'CPU6502Tests|CPUInterruptPollingTests|MemoryMapTests|VICTests|VICCollisionPipelineTests|VICDataBusTests|VICGraphicsSequencerTests|VICSpriteShifterTests|VICBeamTimingTests|VICPriorityTests|VICSlotTimingTests|VICSpriteFetchTests|VICSpriteDMALifecycleTests|PublicVICConformanceTests|C64TimingTests|C64InterruptTests|CIATests|Drive1541Tests|VIA6522Tests|IECBusTests'
```

## Public FLD, line-crunch and FLI visual proof

The pinned public `VICII/fldscroll` programs reproduce the scroller used in Cataball+3/Decibel. All six fixed timing variants run unchanged through BASIC. At the program's capture write, the runner compares every color index in the physical 320x200 display area against its upstream `references/*.png`. The source Makefile generates those references with VICE and the `pepto-pal` palette. They are independent emulator reference outputs, not new hardware measurements. The comparison uses fixed PAL crop origins (reference x=32/y=35, Swift64 x=24/y=37), with no image alignment search, tolerances, or locally generated expected hashes. Palette indices avoid conflating different RGB palettes with emulation errors; raw PNG samples avoid host color-management conversion.

Measured Release results (2026-10-15):

| Fixture | Cycles after RUN | Final PC | Raster (zero-based cycle) | Differing pixels |
| --- | --- | --- | --- | --- |
| `fld-20-pal` | 105,868 | `$0C21` | 120:28 | 0 / 64,000 |
| `fld-21-pal` | 105,869 | `$0C21` | 120:29 | 0 / 64,000 |
| `fld-22-pal` | 105,870 | `$0C21` | 120:30 | 0 / 64,000 |
| `fld-29-pal` | 105,877 | `$0C21` | 120:37 | 0 / 64,000 |
| `fld-2a-pal` | 105,923 | `$0C21` | 121:20 | 0 / 64,000 |
| `fld-2b-pal` | 105,923 | `$0C21` | 121:20 | 0 / 64,000 |

Before correction, every variant differed by 20,326-34,813 pixels despite writing `$D7FF=$00`. Connecting CIA1 PB4 to VIC light-pen capture fixed variants 20/22/29. Deferring CPU-phase `$D011` sequencer effects to the next VIC cycle fixed 21's erroneous line crunching and the extra corrupted column in 2A/2B. Sampling the actual RDY-held CPU data bus during the three-cycle AEC startup delay fixed the remaining FLI colors. Source: [Bauer's VIC-II observations](https://www.cebix.net/VIC-Article.txt), sections 3.11 and 3.14.6. Register readback and raster-compare writes remain immediate; only bad-line sequencer effects are deferred.

`VICLightPenWiringTests` covers real CPU stores, DDR-triggered edges, CIA2 isolation, keyboard row selection, joystick fire, and same-frame IRQ acknowledgement. `VICDMABusTests` verifies PAL/NTSC DMA-startup colors from three different following opcodes, AEC bus ownership, and a held operand read rather than a guessed PC peek. `CPUHeldReadTests` checks held versus unstalled bus addresses for all 256 opcodes under both branch-flag/index settings, plus interrupt/reset microcycles, and ensures CPU state is retained while AEC suppresses reads. Existing late-DMA tests now explicitly distinguish the CPU-write cycle from the following VIC fetch cycle; their pixel, address, counter, and clean-fetch assertions remain enabled.

The Release integration slice below executed 747 tests: 736 passed, 11 opt-in slow-drive tests skipped, and no failures. All ten public programs passed; a separate Release repeat produced identical cycle/PC/raster results and zero pixel differences for all six visual fixtures. Final `swift build --build-tests -j 2` and a 583-test checked Debug CPU/memory/VIC/CIA/keyboard/reset/timing slice passed without failures. No SID tests, audio playback, commercial media, or unbounded corpus runs were used. Optional `SWIFT64_PUBLIC_VIC_CAPTURE_DIR=.build/vic-fld-captures` writes local PPM diagnostics; `SWIFT64_PUBLIC_VIC_TRACE_RASTER=1` prints at most 100 `$D011`/`$D016` writes per fixture. Downloads, reference PNGs, and generated captures remain ignored and untracked.

```sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
  swift test -c release -j 2 --filter 'CPU6502Tests|CPUInterruptPollingTests|CPUHeldReadTests|MemoryMapTests|VICTests|VICLightPenWiringTests|VICDMABusTests|VICCollisionPipelineTests|VICDataBusTests|VICGraphicsSequencerTests|VICSpriteShifterTests|VICBeamTimingTests|VICPriorityTests|VICSlotTimingTests|VICSpriteFetchTests|VICSpriteDMALifecycleTests|PublicVICConformanceTests|C64TimingTests|C64InterruptTests|C64ResetTests|CIATests|KeyboardTests|Drive1541Tests|VIA6522Tests|IECBusTests'
```

This proves these six PAL effects within the normal display area, not full open-border or sprite-multiplexer demos, NTSC FLD/FLI, analog output, or arbitrary DMA contention.

## Public sprite expansion and border proof

The same pinned runner now includes `VICII/spritedma/d017-54` and `d017-57` for PAL and NTSC, plus twelve `VICII/border` programs. No test instructions or expected pixels are patched. Sprite references compare the 320x200 picture (PAL reference x=32/y=35, NTSC x=32/y=23). Border references compare 376x272 pixels: reference x=8/y=0 through x=383/y=271, corresponding to Swift64 logical x=0/y=2. This is the shared crop, including side/top/bottom borders; the eight reference pixels left of Swift64's crop are explicitly excluded. No alignment search or mismatch tolerance is used.

Measured Release public-fixture results (2026-10-15):

| Fixture ID | Cycles after RUN | Final PC | Raster (zero-based cycle) | Differing pixels |
| --- | --- | --- | --- | --- |
| `sprite-dma-54-pal` | 103,348 | `$08FB` | 80:28 | 0 / 64,000 |
| `sprite-dma-54-ntsc` | 90,704 | `$08FC` | 80:29 | 0 / 64,000 |
| `sprite-dma-57-pal` | 103,344 | `$08FA` | 80:24 | 0 / 64,000 |
| `sprite-dma-57-ntsc` | 90,700 | `$08FB` | 80:25 | 0 / 64,000 |
| `vborder-32-08-pal` | 74,856 | `$093F` | 252:12 | 0 / 102,272 |
| `vborder-32-09-pal` | 74,857 | `$093F` | 252:13 | 0 / 102,272 |
| `vborder-33-08-pal` | 74,857 | `$093F` | 252:13 | 0 / 102,272 |
| `vborder-33-09-pal` | 74,858 | `$093F` | 252:14 | 0 / 102,272 |
| `vborder2-21-pal` | 74,757 | `$094F` | 250:39 | 0 / 102,272 |
| `vborder2-22-pal` | 74,758 | `$094F` | 250:40 | 0 / 102,272 |
| `vborder2-35-pal` | 74,777 | `$094F` | 250:59 | 0 / 102,272 |
| `vborder2-36-pal` | 74,778 | `$094F` | 250:60 | 0 / 102,272 |
| `vborder2-63-pal` | 74,823 | `$094F` | 251:42 | 0 / 102,272 |
| `vborder2-64-pal` | 74,824 | `$094F` | 251:43 | 0 / 102,272 |
| `hvborder1-pal` | 135,439 | `$094A` | 277:52 | 0 / 102,272 |
| `hvborder2-pal` | 135,118 | `$093C` | 272:46 | 0 / 102,272 |

The initial baseline passed the four expansion fixtures and three vertical-border cases, but failed nine border images with 960-12,800 differing pixels. The fixes are in the emulator, not its reference data:

- Keep a pending vertical-close latch separate from visible graphics gating. Brief RSEL pulses survive until the next line or the left-border sample, rather than disappearing between two sparse comparisons.
- Preserve vertical-border state across frame wrap; only hardware comparisons or reset close it.
- Sample side-border control in hardware cycles 17/18 and 56/57, while retaining logical pixel edges 24/31 and 335/344. Existing CPU-store tests moved their timing windows by one cycle, without changing expected colors, edge pixels, or open/closed outcomes.
- Clearing a sprite's display latch prevents new X matches but does not truncate a row already in the shifter. The combined border tests exposed four missing pixels in the final byte of an expanded sprite's last row.

`VICBorderTimingTests` adds five ROM-independent regressions: six real-6510 four-cycle RSEL pulse boundaries; delayed close without mid-line blanking; PAL/NTSC frame-wrap persistence/reset; DMA-backed expanded final rows with collision tails; and inactive sprites not starting after the display latch closes. Snapshot fixtures that skip earlier scanlines now seed both vertical latches explicitly. All 588 focused checked Debug CPU/memory/VIC/CIA/keyboard/reset/timing tests pass.

The final sequential Release integration slice (the FLD command above with `VICBorderTimingTests` added) executed 752 tests: 741 passed, 11 opt-in slow-drive tests skipped, zero failures. All 26 public fixtures repeated with identical cycle/PC/raster results and zero visual differences. `swift build --build-tests -j 2` also passed. The earlier integration attempt caught a new inactive-sprite fixture positioned before NTSC's display-disable sample; its corrected X=368 position tests the intended after-latch case on both standards without changing emulator behavior or the public reference comparisons.

Behavior references are [Bauer's border/hyperscreen description](https://www.cebix.net/VIC-Article.txt), the [public border fixture observations](https://github.com/libsidplayfp/VICE-testprogs/blob/ef8e8efe52f3d43df7acefad132c6506239bddee/VICII/border/readme.txt), and VICE's cycle-exact border sampling behavior as an implementation reference. Swift64's line-trace/latch implementation is its own; no VICE implementation code is incorporated. Reference screenshots are independent emulator outputs, not new physical-chip measurements.

This expands proof to these PAL open-border effects and PAL/NTSC expansion cases. Full external sprite-multiplexer demos, NTSC open-border/FLI effects, border-edge collision subphases, bitmap idle-color changes, and analog output remain uncertified. The framebuffer uses logical sprite-X coordinates; NTSC's skipped/repeated counter positions outside the normal picture still need physical-output mapping proof. All 26 public programs are bounded and sequential; downloaded PRGs, PNGs, local ROMs and generated PPMs stay ignored/untracked. No SID/audio testing is part of this VIC run.

## Public sprite register split proof

The pinned runner also executes seventeen unmodified [Daniel Kahlin sprite-split programs](https://github.com/libsidplayfp/VICE-testprogs/blob/ef8e8efe52f3d43df7acefad132c6506239bddee/VICII/spritesplit/spritesplit.asm). Each reuses a sprite across eight vertical bands at successive X alignments and performs cycle-timed register writes. These exercise a useful multiplexer primitive, not a complete external demo. The comparison uses the same fixed 376x272 PAL border crop as above, with no alignment search, mismatch tolerance, or locally generated expected pixels.

| Behavior | Fixture IDs |
| --- | --- |
| Hires/multicolor switching | `ss-hires-mc-pal`, `ss-hires-mc-exp-pal`, `ss-mc-hires-pal`, `ss-mc-hires-exp-pal` |
| Individual/shared color writes | `ss-hires-color-pal`, `ss-mc-color0-pal`, `ss-mc-color1-pal`, `ss-mc-color2-pal` |
| X comparator | `ss-xpos-pal` |
| Horizontal expansion switching | `ss-unexp-exp-hires-pal`, `ss-exp-unexp-hires-pal`, `ss-unexp-exp-mc-pal`, `ss-exp-unexp-mc-pal` |
| Foreground priority switching | `ss-pri-pal`, `ss-pri-exp-pal`, `ss-pri-mc-pal`, `ss-pri-mc-exp-pal` |

All seventeen initially failed visual comparison, with 220-2,772 differing pixels each despite successful program completion. All now reach `$D7FF=$00` at 114,166 cycles after RUN, PC `$08B3`, raster 252:10, with **0 / 102,272** differing pixels each. The earlier 26 public programs retain their passing completion and visual results. Combined proof is 43 programs, 39 exact visual fixtures, and 3,605,888 color-index comparisons.

The core changes separate within-cycle sprite output stages. Relative to a CPU store in zero-based cycle 27, priority/expansion changes begin at logical X=118, multicolor changes at X=119, and the new X comparator value at X=120. Color selection changes at X=113 without moving data or collision occupancy. A decoded-pixel latch preserves the current pixel across mode/expansion changes, including the last half-pair. Color output records the selected register source rather than matching old RGB values, preserving hidden-sprite priority. Collision samples retain their original half-cycle maturation windows; the unchanged public collision programs still pass.

`VICSpriteRegisterTimingTests` adds eight ROM-independent tests using real 6510 stores on PAL and NTSC: every sprite's individual/shared color source, hidden equal-colored sprites, all eight X alignments for low-byte and MSB writes, completed-row guards, unchanged-channel isolation, mode-latch tails, and counter-wrap color updates. An older synthetic multicolor assertion now checks the retained hires pixel, odd pair alignment, and final dot instead of expecting immediate pair realignment. The CPU color-split test checks the measured color-output boundary instead of the former whole-cycle approximation.

`swift build --build-tests -j 2` passes. The checked Debug CPU/memory/VIC/CIA/keyboard/reset/timing slice executes 597 tests: 596 passed, one opt-in public-suite skip, zero failures. Run the public proof separately or as part of the bounded Release integration slice:

```sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
  swift test -c release -j 2 --filter 'PublicVICConformanceTests|VIC.*Tests|C64TimingTests|CPU6502Tests|CPUInterruptPollingTests|CPUHeldReadTests|MemoryMapTests|CIATests|KeyboardTests|C64InterruptTests|C64ResetTests|Drive1541Tests|VIA6522Tests|IECBusTests'
```

Final Release results (2026-10-15): 760 tests executed, 749 passed, 11 optional slow-drive skips, zero failures. All 43 public-program completion lines and all 39 visual comparison lines exactly repeat the preceding run. One earlier integration attempt caught the obsolete synthetic multicolor assertion described above; strengthening its retained-pixel/tail checks resolved that failure without changing the already-passing public references. This sprite-split batch follows, and is not included in, the published 0.4.0 archive.

The optional bounded `SWIFT64_PUBLIC_VIC_TRACE_RASTER=1` trace now includes sprite X/mode/priority/expansion/color writes, alongside the display registers. `SWIFT64_PUBLIC_VIC_CAPTURE_DIR` still writes only local PPM diagnostics. All downloads, reference images, ROMs, and generated captures remain ignored/untracked. No SID suite or audio playback is part of this VIC check.

This calibrates the default PAL 6569 reference behavior, not the alternate 8565 captures or independently measured NTSC sub-dot timing. The [upstream 8565 hardware observations](https://github.com/libsidplayfp/VICE-testprogs/blob/ef8e8efe52f3d43df7acefad132c6506239bddee/VICII/spritesplit/8565.txt) document chip-revision differences. Full external sprite-multiplexer demos, NTSC open-border/FLI proof, border-edge collision subphases, and physical-output mapping remain open. Swift64's implementation is its own; no VICE implementation code is incorporated.

## Public graphics-fetch and bitmap-border results

At release 0.4.1, the runner selected 50 public programs by default. Seven additional unchanged programs probe PAL/NTSC graphics-fetch timing, Blackmail FLI, and bitmap open borders. The 43-program result above is a historical sprite-split checkpoint. The table below records release 0.4.1; newer results follow in [bitmap output-latch proof](#bitmap-open-border-output-latch) and [the 52-program side-border expansion](#inactive-sprite-fetches-and-side-border-probes).

Release 0.4.1 validation (2026-10-15): all 50 programs reach their own `$D7FF=$00` completion write, but four fail their visual comparison. There are 46 passing programs: four bus/collision probes and 42 exact visual fixtures, covering 3,836,160 matching color indices. All previously passing sprite-split cases remain exact. The seven additional results are:

| Fixture ID | Cycles after RUN | Final PC | Raster (zero-based cycle) | Differing pixels |
| --- | --- | --- | --- | --- |
| `blackmail-fli-pal` | 369,965 | `$0AA1` | 256:29 | 5,558 / 64,000; expected failure, not a pass |
| `graphics-fetch-pal` | 126,023 | `$0909` | 128:23 | 0 / 64,000 |
| `graphics-fetch-ntsc` | 110,910 | `$090F` | 128:20 | 0 / 64,000 |
| `border-bm-idle-pal` | 292,366 | `$093C` | 272:46 | 7,938 / 102,272; failure |
| `border-bm-ysh-pal` | 291,914 | `$0943` | 265:35 | 5,389 / 102,272; failure |
| `border-bm-ysh2-pal` | 291,788 | `$0945` | 263:35 | 4,718 / 102,272; failure |
| `border-mcbm-pal` | 291,914 | `$0943` | 265:35 | 0 / 102,272 |

`swift build --build-tests -j 2` passes. Without the public-fixture environment variable, the focused Debug slice executes 597 tests (596 passed, one opt-in skip) and Release integration executes 760 (748 passed, 12 opt-in skips), both with zero failures. The separate full public run takes 259.6 seconds and exits 1 with three ordinary assertions and the Blackmail expected failure. The full public suite is deliberately not reported as green.

In releases 0.4.1/0.4.2, Blackmail had a scoped, strict expected failure for its FLI row alignment. Its exact mismatch count was asserted outside that waiver, so changed results required investigation; the failure was not counted as a visual pass. That exception is removed by the later [raster synchronizer fix](#raster-synchronizer-timing). The three standard-bitmap border probes retain ordinary zero-difference assertions: they failed in 0.4.1 and now pass without waivers. Multicolor bitmap and standard bitmap are tested separately; a pass for one does not certify the other.

The pinned [bitmap-border observations](https://github.com/libsidplayfp/VICE-testprogs/blob/ef8e8efe52f3d43df7acefad132c6506239bddee/VICII/border/readme.txt) describe held bitmap background colors outside the graphics window, including an effect used by Krestology/Crest. These failures are useful compatibility targets, not reasons to adjust the upstream reference images. Speculative CIA timer/phase experiments did not resolve Blackmail and were removed; this release changes neither CIA timing nor the machine's CIA/CPU clock order.

To reproduce the seven additional cases with one emulator at a time:

```sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
SWIFT64_PUBLIC_VIC_TEST_IDS=blackmail-fli-pal,graphics-fetch-pal,graphics-fetch-ntsc,border-bm-idle-pal,border-bm-ysh-pal,border-bm-ysh2-pal,border-mcbm-pal \
  swift test -c release -j 2 --filter PublicVICConformanceTests
```

`SWIFT64_PUBLIC_VIC_TRACE_RASTER=1` includes `$D018` writes. Set `SWIFT64_PUBLIC_VIC_TRACE_AFTER_CYCLES` to a nonnegative cycle count after RUN to inspect steady-state behavior instead of setup; the trace remains capped at 100 register writes. Downloads, ROMs, reference PNGs, and optional PPM captures remain local and untracked. No SID test or playback run is part of this release validation.

## Bitmap open-border output latch

Release 0.4.2 (2026-10-15) fixes all three standard-bitmap visual failures above, with unchanged completion cycles, PC, raster positions, and upstream references. Each now has **0 / 102,272** differing pixels. The multicolor bitmap case also stays exact. The public set now has 49 passing programs, 45 exact images, and 4,142,976 matching color indices. Blackmail remains a strict expected failure at 5,558 pixels; an exit-zero runner result does not certify that fixture.

The VIC now keeps the matrix byte used by its output color selector across rows and frame wrap. G-accesses still run under the vertical border, but they cannot replace that output latch while graphics loading is disabled. During idle graphics, zero matrix bits arrive only at the horizontally scrolled cell boundary. Outside graphics cells, standard bitmap therefore uses the retained low nibble instead of `$D021`; other graphics modes use their own background selector. The existing per-pixel trace packs the held matrix and mode alongside its colors, with no new framebuffer or per-line allocations. Constant graphics pixels are distinguished from uncovered output, so foreground and bitmap colors are not accidentally replaced by the idle source.

That change alone removed 7,938 and 5,389 differences from the first two cases and reduced the third from 4,718 to two. The remaining pixels at logical X=328/332, raster 240 exposed a separate fetch/output timing error. The fixture's actual `DEC $D016` writes X-scroll 7 in CPU phase of cycle 53, after column 38's fetch but before its earliest shifter load. Raster capture now straddles the CPU phase, and the current fetched byte takes the new scroll value before loading; it is no longer painted seven dots too soon. Public CPU/bus/collision timing and all seventeen sprite-register split images remain unchanged. Neither CIA timing nor the CPU scheduler was adjusted.

`VICGraphicsColorLatchTests` adds eight ROM-independent PAL/NTSC regressions covering held colors across both side borders, all eight X-scroll values, zero-matrix idle loads, vertical gating with continuing memory access, fetched rather than reread matrix data, all eight mode selectors, CPU-phase color and scroll writes, repeat rendering without state advancement, invisible rasterlines, frame wrap, and reset. Pixel checks use the shared 376-pixel border crop; NTSC's skipped logical X=392...395 positions still require separate physical-output mapping, and are not silently claimed as correct.

Validation is sequential with two build jobs and one emulator. `swift build --build-tests -j 2` passes; the checked Debug slice executes 605 tests (604 passed, one opt-in skip). Full Release integration executes 768 tests (757 passed, 11 slow-drive skips, zero unexpected failures), with Blackmail's existing expected failure reported separately. The full public set retains identical completion observables; the three bitmap comparisons improve to exact without weakening an assertion. No SID suite or audio playback was run. These changes ship in 0.4.2 and do not complete broader game/demo or chip-revision certification.

## Inactive sprite fetches and side-border probes

Development after 0.4.2 models the inactive fetch path described by the pinned [side-border sprite observations](https://github.com/libsidplayfp/VICE-testprogs/blob/ef8e8efe52f3d43df7acefad132c6506239bddee/VICII/sb_sprite_fetch/readme.txt). All sprite slots load their shifters even when DMA is inactive: the two phi2 bytes come from the internal VIC register bus (normally `$FF`), with the phi1 idle byte from `$3FFF` between them. CPU VIC-register reads/writes can change those outer bytes. This does not create extra memory reads, CPU stalls, or sprite-counter advancement. The implementation is original Swift; no VICE implementation code is included.

`VICInactiveSpriteFetchTests` adds five bounded checks: all eight PAL/NTSC slots; current-phase VIC bus values and pull-up reset; non-mutating debugger versus collision-register reads; real indexed 6510 stores including mirrors and RAM isolation; and the extra PAL row at X=`$164` but not `$163`. The CPU test supplies `$AC/$4D/$26` through the actual dummy-read, idle-read, and write phases. Existing synthetic register-output fixtures seed after the early fetch slots; their original exact-pixel checks are retained.

The fetch script and default public set add unmodified `sbsprf24-163.prg` and `sbsprf24-164.prg` from the same pinned revision. At the initial fetch-only checkpoint, both reached `$D7FF=$00` after 134,138 cycles, PC `$0CAA`, raster 257:11, but each differed from its reference by **487 / 102,272 pixels**, unchanged from before the fetch fix. The first differences occurred on raster 118, before the sprite Y-match line 122. The `$D016` write trace showed the border routine missing its intended cycle positions. That led to the shared synchronizer corrections documented below, not a reference tolerance or a VIC offset.

```sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
SWIFT64_PUBLIC_VIC_TEST_IDS=sideborder-sprite-163-pal,sideborder-sprite-164-pal \
  swift test -c release -j 2 --filter PublicVICConformanceTests
```

At that checkpoint this command exited nonzero: **49 / 52 programs** passed, including 45 exact images and 4,142,976 matching color indices. All 97 completion/comparison/known-failure records from the previous 50-program run repeated identically. Blackmail's 5,558-pixel expected failure was distinct from the two ordinary side-border assertions. The command now passes following the synchronizer fixes below. Neither program completion alone nor the synthetic fetch proof counted as a full visual pass.

The checked Debug integration slice executes 610 tests: 609 passed, one opt-in skip, zero failures. Release integration without the opt-in corpus executes 773 tests: 761 passed, 12 skips, zero failures. `swift build --build-tests -j 2` passes. Runs remain sequential with two build jobs and one emulator instance. No SID tests or playback checks are part of this batch. A downloaded SDL VICE reference binary crashed during startup, produced no usable trace, and is not used as validation evidence; no VICE application was installed. ROMs, fixture binaries, reference PNGs, and captures remain local/untracked.

## Raster synchronizer timing

Post-0.4.2 development closes all three remaining public visual failures without changing VIC counter boundaries or expected images. **All 52 programs pass**, including four bus/collision probes and **48 exact visual fixtures covering 4,411,520 color indices**. The expected-failure path is removed: every image comparison requires zero differences.

| Fixture | Earlier differing pixels | Current differing pixels | Cycles after RUN / PC / raster |
| --- | --- | --- | --- |
| `blackmail-fli-pal` | 5,558 / 64,000 | 0 | 369,965 / `$0AA1` / 256:29 |
| `sideborder-sprite-163-pal` | 487 / 102,272 | 0 | 134,138 / `$0CAA` / 257:11 |
| `sideborder-sprite-164-pal` | 487 / 102,272 | 0 | 134,138 / `$0CAA` / 257:11 |

The side-border routine reads a CIA timer to stabilize its IRQ before opening the border and injecting sprite bytes. Swift64 previously applied start/stop/force-load immediately and exposed zero during continuous counting. The new count pipeline follows [Lorenz's hardware cycle tables](https://ist.uwaterloo.ca/~schepers/MJK/cia6526.html), including delayed control/source changes, reload hold, cascaded counting and old-6526 timer IRQ acknowledgement. ICR reads acknowledge the interrupt; clearing its mask does not clear an already latched request. The timer table tests also check PB pins and interrupt data, not just final counter values. Both unchanged side-border images become exact with this correction.

Blackmail then exposed a separate CPU bug: NMI edges bypassed instruction polling. The [documented 6502 detector/polling sequence](https://www.nesdev.org/wiki/Interrupts) requires an edge to reach an instruction's polling point; a late edge waits for the next instruction. NMI polling now follows the same instruction and branch windows as IRQ polling while retaining the edge until serviced. In Blackmail's final frame, the NMI vector read moves from raster 46 cycle 22 to cycle 25, the timer read from cycle 40 (`$B0`) to 43 (`$AD`), and the first `$D011` write from raster 47 cycle 27 to 43. The CIA-only intermediate result had 26,692 wrong pixels; correcting CPU polling reduces it to zero. This failed intermediate run is not counted as validation, and no per-program timing adjustment remains.

Seven new `CIATimerPipelineTests` exercise first-four-cycle control sequences for both timers, continuous and cascaded counts, PB/ICR timing, cancellation of a pending IRQ, CPU-observed reads under PAL/NTSC, CNT/source propagation, and reset. Five `CPUNMIPollingTests` sweep ordinary instruction and branch arrival windows, transient late edges, held data reads, and held opcode fetches. Existing status-stack, BRK/IRQ vector-hijack, simultaneous IRQ/NMI, RESTORE, serial-data, and timer-output checks remain active. Older timer tests now wait for actual underflow output and explicit input-pipeline clocks instead of assuming immediate effects.

```sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
  swift test -c release -j 2 --filter 'PublicVICConformanceTests|VIC.*Tests|C64TimingTests|CPU6502Tests|CPUInterruptPollingTests|CPUNMIPollingTests|CPUHeldReadTests|MemoryMapTests|CIATests|CIATimerPipelineTests|KeyboardTests|C64InterruptTests|C64ResetTests|Drive1541Tests|VIA6522Tests|IECBusTests|CartridgeTests|MachineProfileTests|TapeUnitTests|KernalTrapsTests'
```

The full Release command executes **996 tests: 985 passed, 11 opt-in slow-drive skips, zero failures**, with no expected-failure exceptions. The focused checked Debug slice executes 622 tests: 621 passed and one public-corpus skip. Raster tracing also records up to 32 timer/NMI-vector reads, using the existing trace flag and cycle threshold, to make synchronizer failures diagnosable without unbounded logs. No SID suite or audio playback was run. Builds/tests remain sequential, capped at two build jobs and one emulator. No emulator implementation code was copied from the references; binaries, ROMs, PNGs, and captures remain local/untracked.

This evidence covers the named probes and default chip assumptions, not complete games, full external multiplexer/multi-part demos, other CIA/VIC revisions, or all NTSC raster effects. The broader VIC goal remains active. These changes are not in the published 0.4.2 app.

An additional opt-in drive check is **not passing**:

```sh
SWIFT64_SLOW_TRUE_DRIVE_TESTS=1 swift test -c release -j 2 \
  --filter Drive1541Tests/testTrueDriveD64PrgLoadUsesFileAddress
```

The bounded 10-million-cycle run fails seven assertions: TALK and its secondary address, UNTALK, CLOSE, payload, end pointer, and EOF. Both the new CPU/CIA and a control using their pre-change versions with the same current VIC finish at C64 PC `$EEAD`, drive PC `$F3F2`, serial status `$00`, and IEC commands `28 F0 3F`. The new sources were restored byte-for-byte before the repeat. This isolates the failure from the CPU/CIA timing batch but is not a clean-release comparison and does not close the drive issue. All tests were run sequentially.

Live SDL VICE comparison was abandoned after four identical `x64sc` null-pointer crashes in `strlen` on macOS. No reference result is claimed from those runs. The downloaded app is not running and its disk image was unmounted; the public fixture comparisons above run directly in Swift64 and do not launch VICE.

Final restoration check: `swift build --build-tests -j 2` passes. A Release repeat of Blackmail and both side-border programs also passes with zero differing pixels and the same cycle/PC/raster checkpoints listed above.

## External sprite-multiplexer demo

`ExternalVICDemoTests` runs Lasse Oorni's original [Hessian-derived 24-sprite example](https://cadaver.github.io/rants/sprite.html), not the full Hessian game. The original packed PRG boots via BASIC `RUN`, unpacks itself, installs its own raster IRQs, sorts sprites, and alternates its two display lists. There is no injected IRQ routine, patched PRG, manually set PC, or VICE process.

```sh
sh script/fetch_vic_demos.sh
SWIFT64_EXTERNAL_VIC_DEMOS_DIR=.build/vic-demos \
  swift test -c release -j 2 --filter ExternalVICDemoTests
```

The opt-in tests run one machine at a time, first NTSC then PAL. Each allows 24 frames for startup and checks the following 240 complete 320x200 display areas. At the demo's list-consumption instruction, a read-only observer snapshots the active sorted sprite table. The oracle independently composes the source program's solid 24x21 sprite rectangles using their colors, 9-bit X coordinates, and physical-slot priority over the character-ROM background. It does not derive expectations from VIC sprite state or recorded Swift64 images. SHA-256 checks reject a different PRG because the observer's memory addresses belong to this exact original program. Source and archive remain local/untracked.

Checks also require repeated list consumption, use of both doublebuffers, more than 16 visible logical sprites in a frame, repeated visible high-X sprites, and over 1,000 overlapping pixels to exercise priority. Setting `SWIFT64_EXTERNAL_VIC_CAPTURE_DIR` saves only the final frame of each profile, or the first failing frame, as a local PPM. The 240-frame run is bounded; captures and downloaded archives are never release assets. This does not prove patterned/multicolor sprites, open borders in this demo, other programs, or hardware-specific analog output.

Checked Debug validation (2026-10-15): both demo runs pass, comparing **480 full display frames / 30,720,000 pixels with zero differences**. NTSC consumes 248 sprite lists and PAL 250, with 24 logical sprites reached in each. The visual oracle also has a ROM-free negative-control test: removing a final-row pixel or reversing overlapping-sprite priority must produce an exact mismatch count. Normal test runs skip the two external demos unless explicitly enabled.

The Release repeat passes the same 480 frames with the following coverage. The display oracle checks every pixel, including text and background, with no tolerated mismatch:

| Profile | Lists consumed | Maximum logical / visible sprites | Visible high-X sprite instances | Overlapping pixels |
| --- | --- | --- | --- | --- |
| NTSC | 248 | 24 / 23 | 1,124 | 91,857 |
| PAL | 250 | 24 / 23 | 1,127 | 90,521 |

The sequential Release integration command below passes **47 tests, zero failures or skips** (55.4 seconds excluding the build). Blackmail and both side-border probes retain their exact images and cycle/PC/raster checkpoints. The checked Debug demo run took 634.8 seconds on this host; prefer Release for the opt-in corpus.

```sh
SWIFT64_EXTERNAL_VIC_DEMOS_DIR=.build/vic-demos \
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
SWIFT64_PUBLIC_VIC_TEST_IDS=blackmail-fli-pal,sideborder-sprite-163-pal,sideborder-sprite-164-pal \
  swift test -c release -j 2 --filter 'ExternalVICDemoTests|PublicVICConformanceTests|VICSpriteDMALifecycleTests|C64TimingTests'
```

### Patterned Sprite Modes

The same fetch script also obtains Martin Piper's published [`TestMultiplexor9.prg`](https://github.com/martinpiper/C64Public/blob/d4bad371e98e200bf0f8dbedbc1c1a6df5edb564/SpriteMultiplexor/TestData/TestMultiplexor9.prg) and its corresponding source/options at that pinned revision. Nothing from that program is incorporated into Swift64; the original source, author license, and binary remain local fixtures. Two additional opt-in runs cover PAL and NTSC with the unchanged PRG and the same 24-frame startup / 240-frame measurement bounds.

This fixture mixes 24 logical sprites: 14 multicolor, 14 behind foreground graphics, 14 X-expanded, and 9 Y-expanded, with four different sprite patterns. The oracle reads the program's sorted indices and source arrays before the frame, decodes the original sprite bytes including transparent bit pairs, and composes hardware-slot priority over the character background. It never uses VIC sprite state to decide what should appear. Both the demo's `ABC` CPU-register-preservation check and its bottom-IRQ X-position increment are required every frame. The overlap and background-occlusion coverage counters must be nonzero beyond a minimum threshold.

ROM-free oracle tests cover all four multicolor bit pairs, both expansion dimensions and boundaries, and the priority case where a behind-background winning sprite still masks a lower-priority front sprite. These are checks on the verifier; the original demo is never patched to force a failure or a pass. The exact-image assertion covers the 320x200 display, not analog output or the outer border.

Release validation (2026-10-15) passes **480 mixed-mode frames / 30,720,000 pixels with zero differences**, split equally between PAL and NTSC. Each profile covers 540,304 overlapping pixels and 308,559 pixels where foreground graphics hide the winning sprite. Together with the Hessian-derived example, the run checks 960 complete display frames / 61,440,000 pixels. Original IRQ motion and register preservation continue throughout, so a static captured image cannot satisfy the run.

The expanded sequential Release slice passes **387 tests with zero failures or skips** in 96.1 seconds excluding compilation. It includes all VIC component tests, C64 timing, both external programs, the three verifier checks, and the three public probes below. Blackmail and both side-border probes still have zero pixel differences and unchanged cycle/PC/raster checkpoints. Fresh fixture downloads were checksum-verified before this run; the three verifier tests also pass in checked Debug.

```sh
SWIFT64_EXTERNAL_VIC_DEMOS_DIR=.build/vic-demos \
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
SWIFT64_PUBLIC_VIC_TEST_IDS=blackmail-fli-pal,sideborder-sprite-163-pal,sideborder-sprite-164-pal \
  swift test -c release -j 2 --filter 'ExternalVICDemoTests|PublicVICConformanceTests|VIC.*Tests|C64TimingTests'
```

### Complete Game Milestone

The fetch script also downloads Fabrizio Caruso's original [Befana vs Balloons 2026 release](https://github.com/Fabrizio-Caruso/C64_Multiplexor_C_LIB/releases/tag/befana2026), its matching game/multiplexer source, and the author's non-commercial license notice. The SHA-256-pinned PRG is a local validation fixture only; neither the game, artwork, nor source is included in Swift64 or its release assets.

`testOptInBefanaGameplayPAL` boots through BASIC, waits within fixed bounds for the real title/gameplay states, and supplies ordinary port-2 joystick input. No game variables, IRQ vectors, or PC are patched. It checks 240 title frames and 1,500 gameplay frames, including all four movement directions, shooting/scoring, level advancement, and continued play after a lost life.

At the original IRQ3's first sprite setup, a read-only observer snapshots the completed sorted source table and sprite bitmap bytes. The independent compositor checks every winning opaque sprite pixel in the 320x200 display, including slot priority and the game's shared multicolor values. It does **not** read VIC sprite internals to construct expectations. Character RAM changes while the beam scans, so this game's proof deliberately excludes background/transparent pixels instead of comparing earlier rasterlines against final RAM. The two preceding external demos retain their full-display assertions; this is an additional game-level proof, not a replacement for those stricter images.

PAL Release result (2026-10-15): **1,740 checked frames / 1,715,786 exact sprite pixels**, maximum 19 visible logical sprites, score 225, level 2, two lives remaining. Both title and level-2 captures were visually inspected. A ROM-free verifier control checks opaque-pixel coverage and rejects an incorrect shared multicolor pixel. `SWIFT64_EXTERNAL_VIC_CAPTURE_DIR` saves only the title, final gameplay frame, or first failure as local PPM files.

**NTSC limitation, not a compatibility pass:** the same original PRG misses a title update on the NTSC profile. The bounded trace shows its line-252 sorter taking 2,656 clocks and scheduling the next line-zero IRQ at raster `30:19`, after the target line has passed. `testOptInBefanaNTSCSortDeadline` reproduces that missed deadline and verifies that the IRQ chain resumes, rather than accepting a skipped update as correct gameplay. This diagnostic is counted as a test check, never as an NTSC game milestone. It is source/timing evidence from Swift64, not a hardware capture; no software patch or VIC timing workaround conceals the limitation.

Using fresh checksum-verified downloads, the expanded Release command in the preceding section passes **390 checks, zero failures or skips**, in 221.4 seconds excluding compilation. That total includes the NTSC limitation diagnostic. Both prior multiplexers repeat their exact PAL/NTSC results; Blackmail FLI and the two side-border probes retain zero pixel differences and unchanged completion checkpoints. The game alone can be reproduced with:

```sh
sh script/fetch_vic_demos.sh
SWIFT64_EXTERNAL_VIC_DEMOS_DIR=.build/vic-demos \
  swift test -c release -j 2 --filter ExternalVICDemoTests/testOptInBefanaGameplayPAL
```

`swift build --build-tests -j 2` passes, and all four ROM-free verifier tests pass in checked Debug. Fresh fixture fetching and `sh -n script/fetch_vic_demos.sh` also pass. No VICE process is used.

This proves a bounded PAL play session in the emulation core, not all 30 game levels, NTSC gameplay, analog video, SID sound quality, disk loading, or sustained app playback.

### Scrolling Game and HUD Split

The original [C64gameframework example](https://github.com/cadaver/c64gameframework/tree/c634f6fa7004cc5bfb14df14dee6f9fa3fe20b1b) combines screen/color-RAM scrolling, a sprite multiplexer, a fixed HUD, and CIA/raster IRQs. The fetch script pins both the source revision and published `exampleef.crt` SHA-256 (`3e1d6e2de8e7773cf6073bdf5c2a72073f1564ed38c73d9844ae57c22e87f239`). It fetches original game material only, not emulator code. The cartridge and artwork remain local/untracked and must not be bundled with Swift64. EasyFlash boot deliberately keeps disk-loader behavior out of this VIC test.

`testOptInScrollingGameFrameworkPAL` and `...NTSC` each run 900 frames, allowing 240 for startup. Starting at frame 500, ordinary port-2 right/fire input moves the player through the doorway into zone 1. Assertions require both sorted sprite buffers, all eight horizontal scroll phases, changing map coordinates, the new zone, and resumed movement after loading. No game RAM, PC, IRQ vector, or program byte is patched.

Expected pixels come from source data captured by read-only CPU-write observers, never VIC sprite internals or saved Swift64 screenshots:

- The game's top-of-frame `$D015` write follows its graphics setup. Snapshot screen RAM, color RAM, charset, and the CPU-issued scroll/background values there. Independently decode the complete 304x80 strip at physical coordinates `x=31..<335, y=55..<135`, before the CIA redraw starts at line 145. Later background rows change while scanning and are not falsely treated as frozen.
- The panel's line-238 `$D011` write captures its screen/charset/colors. Decode the complete 304x8 HUD at `y=239..<247`, including transparent/background pixels, with the fixed panel scroll and character row 23.
- At the first sprite setup, snapshot the original sorted tables and sprite-cache bytes. Independently decode every winning opaque sprite pixel within `x=31..<335, y=55..<230`, including multicolor, 9-bit X, expansion and slot priority. The first eight X-MSB/expansion values come from the first group's completed masks, as specified by the original sorter.
- `BlankScreen` explicitly selects invalid ECM+MCM with sprites disabled during zone loading. Require black across the full 304x175 playfield crop plus a correct HUD, and bound this state to at most twelve frames after movement starts, in zone 1. Blanked frames are checked, not silently skipped; the final state must be playable again.

A ROM-free negative control constructs known multicolor pairs and a sprite independently of the decoder. It rejects wrong colors, a missing sprite pixel, a one-pixel scroll offset, and nonblack output during blanking. Expectations use zero pixel tolerance. This validates bounded scrolling/HUD gameplay on the default PAL/NTSC profiles, not the whole game, all lower-screen background redraw pixels, analog output, disk loading, or SID quality.

```sh
sh script/fetch_vic_demos.sh
SWIFT64_EXTERNAL_VIC_DEMOS_DIR=.build/vic-demos \
SWIFT64_EXTERNAL_VIC_CAPTURE_DIR=.build/vic-framework-captures \
  swift test -c release -j 2 --filter ExternalVICDemoTests/testOptInScrollingGameFramework
```

Captures are optional and bounded to four checkpoints per profile plus the first failure. No VICE executable is launched.

Release results (2026-10-16): each profile checks **660 frames: 654 gameplay plus six loading frames (731-736)**. Each matches **17,829,600 graphics/HUD color indices** with zero differences. The separate sprite comparisons match **279,215 PAL / 279,006 NTSC opaque pixels**; some overlap the graphics bands, so these are not additive unique-pixel totals. Both reach zone 1, all eight X-scroll phases, both sprite buffers, and eight simultaneous source sprites. This example run does not claim all 24 framework sprites; Hessian/Piper provide the heavier reuse tests above. Final zone-1 screenshots were inspected separately from the numeric proof.

The sequential Release selection `ExternalVICDemoTests|VIC.*Tests|C64TimingTests` runs **422 cases in 169.6 seconds: 421 pass, the public-runner case skips, and none fail**. All eight external opt-in cases run, including the separately classified Befana NTSC deadline diagnostic. Hessian/Piper retain 960 exact full display frames and their earlier overlap/priority counts; Befana retains PAL level 2, score 225, two lives, and 1,715,786 exact sprite pixels. This run does not rerun or waive the two known public mode-transition failures. Logs are `/tmp/swift64-vic-framework-integration.log`; captures are ignored under `.build/vic-framework-final`. The fetch script passes from fresh local fixtures with every binary checksum verified. No core behavior changes in this batch.

Final checks: `swift build --build-tests -j 2` passes. The checked Debug `VIC.*Tests|C64TimingTests` slice runs 422 cases in 7.7 seconds: **413 pass, nine opt-in skips, zero failures**. A final Release repeat runs five cases in 70.1 seconds with no skips/failures: both scrolling profiles, the oracle negative control, and public completion/image checks with `SWIFT64_PUBLIC_VIC_TEST_IDS=blackmail-fli-pal,sideborder-sprite-163-pal,sideborder-sprite-164-pal,rasterirq-hold-pal`. The game counts/transition frames repeat exactly; the four public images and result/cycle/PC/raster checkpoints retain their previous results. All six Hessian/Piper/Befana checkpoint PPMs also remain byte-identical to `.build/vic-game-final`. Logs are `/tmp/swift64-vic-framework-build.log`, `...-debug.log`, and `...-repeat.log`. Fetch-script syntax, ignored-asset checks, and `git diff --check` pass. Validation is sequential; no SID test, app playback, or VICE launch is part of it.

## DMA-delay scrolling and graphics-mode output

The public runner now includes 42 pinned DMA-delay programs: three ways of delaying the line-48 bad line, seven start-delay values per method, and PAL/NTSC versions of each. They exercise read-modify-write and separate-store Y-scroll changes, plus DEN latching, without injecting CPU state or changing the programs. The initial Release run matches **2,688,000 / 2,688,000 display color indices**, with all 42 original `$D7FF=$00` completions, in 266.5 seconds. No core change was needed for these cases. This proves the selected practical scrolling sequences, not analog VSP memory corruption or the chip-dependent multi-selected buffer behavior in upstream `test4`.

The first output-stage checkpoint used `videomode1` and `videomode2`, each for PAL and NTSC. These exposed a separate graphics-output bug: the renderer used the mode saved at g-access for the entire character, even when a subsequent CPU write changed the output color selector. Lines with actual mode changes now select colors and foreground status from per-pixel mode samples, while retaining the original fetched byte and address. Unchanged-mode lines keep their existing rendering path. That output-stage change did not alter CPU/CIA or graphics-fetch timing; the later address-stage fix is described below.

At that initial checkpoint, PAL comparisons improved from **34 to 3** and **71 to 10** differing pixels out of 64,000, with unchanged completion checkpoints (`videomode1-pal`: 121,513 cycles, PC `$08FC`, raster `56:49`; `videomode2-pal`: 243,858 cycles, PC `$0910`, raster `126:48`). Both failed zero-tolerance assertions at individual mode-transition edges; the latest results are under [multicolor data and color selection](#multicolor-data-and-color-selection). The [upstream mode notes](https://github.com/libsidplayfp/VICE-testprogs/blob/ef8e8efe52f3d43df7acefad132c6506239bddee/VICII/videomode/readme.txt) describe manually constructed, hardware-compared references and chip/temperature-dependent pixels; these improvements do not certify every transition dot or VIC revision.

The original NTSC comparisons failed with 2,976 and 5,854 differing pixels after the output change. Upstream history now establishes a fixture-version mismatch: both PRGs were changed in [3d4cbce (2025-12-20)](https://github.com/libsidplayfp/VICE-testprogs/commit/3d4cbce35c4f8f8ede42d2cb6b60b385ced9da79), adding screen patterns and changing the second program's bitmap bank/data. Their NTSC images were last changed in [bdc9204 (2016-06-02)](https://github.com/libsidplayfp/VICE-testprogs/commit/bdc9204b7ff36fbe6b9538794f16df932ea05df7) and [3666401 (2019-04-29)](https://github.com/libsidplayfp/VICE-testprogs/commit/3666401155a27feb0a9191b8c00477c8cab8a327). Those two comparisons are removed from the runner and fetch list, not marked passed or given relaxed tolerances. Their results remain historical diagnostics, not valid measures of the current PRGs.

The replacements are `modesplit-pal` and `modesplit-ntsc`: the same unchanged, auto-detecting PRG, with references updated together in [6dee9e4 (2025-12-15)](https://github.com/libsidplayfp/VICE-testprogs/commit/6dee9e41cad26e8bb752eab8c3cf7e5f9cb88489). The [upstream README](https://github.com/libsidplayfp/VICE-testprogs/blob/ef8e8efe52f3d43df7acefad132c6506239bddee/VICII/split-tests/modesplit/README.txt) identifies hardware-matched PAL 6569 and NTSC 6567 references, while warning that their manual construction can still contain errors. The runner checks all 320x200 display pixels across eight scroll alignments and repeated text, bitmap, multicolor, ECM, and invalid-mode transitions. Both initially failed strict comparisons; their latest results are recorded below.

The next graphics fetch after a CPU BMM change now retains the old mode's low address byte and uses the new mode for the high address bits. The selection expires after one low phase, including idle/refresh slots, and reset clears it; already-fetched bytes and idle addresses remain unchanged. This fixes the wrong glyph after a bitmap-to-text split. PAL `videomode2` improves from **10 to 6** differences; `videomode1` stays at **3**. `modesplit` improves from **1,088 to 934** on PAL and **1,162 to 1,008** on NTSC. Each still fails zero-tolerance comparison. Mode-selector/color delay, multicolor transition sampling, and remaining ECM address transitions are not certified.

The selected Release run retains exact Blackmail FLI, PAL/NTSC graphics fetches, and both side-border sprite images. All nine programs reach the same completion checkpoints as before; `modesplit-pal` completes at 527,109 cycles / PC `$08C5` / raster `254:51`, and NTSC at 512,310 / `$08C5` / `254:45`. Six ROM-free mode-output tests pass in checked Debug and Release, including both BMM directions, ECM masks, first/second fetch addresses, fetched-byte retention, idle-slot expiry, and reset. No reference pixels or original programs are edited.

`VICGraphicsModeOutputTests` adds four ROM-free PAL/NTSC tests covering all mode selections and scroll offsets, output changes to an already-fetched byte, unchanged memory accesses, foreground classification including invalid modes, and line/reset isolation. Its stable cell checks do not claim the unresolved analog transition dots. The focused checked Debug slice passes 41 tests without failures or skips.

```sh
sh script/fetch_vic_testprogs.sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
SWIFT64_PUBLIC_VIC_TEST_IDS=dma1-03-pal,dma1-03-ntsc,dma1-18-pal,dma1-18-ntsc,dma2-05-pal,dma2-05-ntsc,dma2-18-pal,dma2-18-ntsc,dma3-07-pal,dma3-07-ntsc,dma3-1a-pal,dma3-1a-ntsc \
  swift test -c release -j 2 --filter PublicVICConformanceTests

# Mode-transition diagnostics, including the remaining strict failures:
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
SWIFT64_PUBLIC_VIC_TEST_IDS=videomode1-pal,videomode2-pal,modesplit-pal,modesplit-ntsc \
  swift test -c release -j 2 --filter PublicVICConformanceTests
```

At that checkpoint, the default public selection contained 98 programs: two obsolete NTSC comparisons were replaced with the two version-matched modesplit cases above. All four valid mode-transition comparisons remain asserted. DMA IDs use `dma<method>-<hex-delay>-pal/ntsc`; all selected delays are listed in `dmaDelayFixtures`. Builds and runs remain sequential and bounded. Programs, reference PNGs, ROMs, and captures stay local/untracked. VICE is not launched and no VICE implementation code is used.

Full Release public validation at the earlier output-stage checkpoint completed all 98 then-selected programs in 327.1 seconds: **94 passed, four mode-split comparisons failed**. The passing set comprised four self-checking bus/collision probes and **90 exact images / 7,099,520 matching color indices**. All 90 complete framebuffer captures were byte-for-byte identical to their corresponding earlier baselines, including pixels outside the comparison crops. The combined 81-test invocation had 80 passing component tests and the public-runner test with those four assertions; its exit status was deliberately nonzero. No other assertion failed.

A separate sequential Release regression run of `VIC.*Tests|C64TimingTests`, with `SWIFT64_EXTERNAL_VIC_DEMOS_DIR=.build/vic-game-fixtures-verified`, executes 394 checks: **393 pass, one public-fixture opt-in skip, zero failures**, in 112.4 seconds. The independently run public-suite failures above are not hidden by this skip. Befana repeats its PAL level-2 milestone and identical NTSC deadline diagnostic; Hessian/Piper repeat all 960 exact PAL/NTSC display frames with unchanged overlap/priority counts. `swift build --build-tests -j 2`, `sh -n script/fetch_vic_testprogs.sh`, and `git diff --check` pass. No SID suite, VICE process, or app relaunch is part of these checks.

The subsequent address-stage integration enables both public fixtures and external games for `VIC.*Tests|C64TimingTests`. It executes **396 test cases in 435.9 seconds: 395 pass and one public-runner case fails its four mode-transition assertions, with no skips**. All 98 original programs complete; 94 pass, including the same 90 exact images / 7,099,520 color indices. All 90 complete captures remain byte-identical to the earlier output-stage baseline. Direct before/after comparison of the two modesplit images finds 154 corrected pixels per profile and zero newly incorrect pixels. Their remaining 934/1,008 differences are still failures.

Befana repeats its 1,740-frame PAL run (score 225, level 2, two lives, 1,715,786 exact sprite pixels) and its separately classified NTSC deadline diagnostic. Both external multiplexers repeat 960 exact PAL/NTSC display frames with unchanged overlap/priority counts. The final checked test build passes in 2.56 seconds, and fetch-script syntax / whitespace checks pass. This run does not certify every graphics-mode transition or change SID behavior. Logs remain local at `/tmp/swift64-vic-address-integration.log` and `/tmp/swift64-vic-address-unit.log`; captures remain ignored under `.build/vic-address-final-captures`.

ECM-clear follow-up: the default PAL 6569 path retains the old A9/A10 mask for one more g-access after a CPU clear; the NTSC 6567R8 path releases it immediately. Both keep the old visible ECM background selector for two dots. This distinction is supported by the version-matched modesplit references, not a change to the test program or its timing. Applying the PAL address delay uniformly was rejected because it introduced 192 newly wrong NTSC pixels. With the profile distinction, PAL modesplit improves **934 -> 482** and NTSC **1,008 -> 856**, with **452/152 corrected pixels and zero newly wrong pixels**. PAL videomode2 improves **6 -> 4**; videomode1 remains at **3**. All four remain ordinary zero-tolerance failures with unchanged completion cycles/PC/raster.

Four additional ROM-free checks cover profile-specific first/second addresses in text, bitmap, and idle state; immediate ECM assertion versus delayed release; two-dot output selection; reset while a selection is pending; refresh/idle/sprite-slot expiry; and compound BMM/ECM stores. The complete mode-output class now has ten tests, and the checked Debug mode/color/sequencer slice passes all 35 tests in 2.55 seconds. No graphics data, reference images, or program bytes are patched. C64C/8565/8562 revisions, the multicolor data latch, and remaining output-transition dots still need independent validation.

Final ECM integration uses the same full `VIC.*Tests|C64TimingTests` Release selection with both public and external fixtures enabled. It executes **400 test cases in 434.5 seconds: 399 pass, one public-runner case fails four strict visual assertions, and none skip**. All 98 public programs complete; 94 pass, retaining 90 exact references / 7,099,520 color indices. All 90 complete passing captures are byte-identical to the preceding address-stage baseline. The four failing comparisons remain at 3/4/482/856 pixels with unchanged completion observables. Both multiplexers retain their 960 exact frames, and Befana retains its PAL level-2 result and separate NTSC deadline diagnostic. `swift build --build-tests -j 2`, fetch-script syntax, and whitespace checks pass. The final log is `/tmp/swift64-vic-ecm-integration.log`; local captures are under `.build/vic-ecm-final-captures`. VICE remains stopped, and no SID suite or app relaunch was run.

### Multicolor data and color selection

The follow-up separates the two-bit graphics-data latch from the color selector. MCM changes the selector immediately and reaches the data latch three dots later. Enabling it mid-byte first holds the previous hires sample; subsequent two-bit samples alternate with held dots. A byte reload realigns the pair phase, so odd horizontal scroll positions cannot be modeled by simply pairing adjacent bits in the original byte. This model predicts all 2,112 transition-window pixels in section 3 of the unchanged modesplit reference, including all eight scroll positions and six character rows. The PAL/NTSC references agree over those windows. The model is inferred from these hardware-matched observations and the graphics-shifter description, not from another emulator's implementation or a transistor-level certification.

Bitmap background selection releases two dots after clearing BMM, while foreground color selection changes immediately. ECM background selection takes precedence over the retained bitmap selector. Clearing BMM/MCM with ECM still set retains invalid-mode black output for one dot on PAL 6569 and two on NTSC 6567R8, without erasing the underlying foreground/priority sample. A trial that incorrectly gave the retained bitmap background priority over ECM introduced 24 wrong PAL pixels; that ordering was rejected and covered by a foreground/background regression check.

Six additional ROM-free tests cover the on/off transition windows, low-color text that must remain hires, foreground priority through a delayed data-width change, separate bitmap foreground/background timing, and invalid-mode release with both zero and opaque data. `VICGraphicsModeOutputTests` now has 16 tests. The checked Debug mode/color/sequencer slice passes **41 tests in 2.88 seconds**, with no skips. Normal non-mode-changing lines retain their existing rendering path; the extra per-dot latch replay is limited to mode-changing lines. The trace remains one preallocated scanline, now using 64-bit words to keep data, color, background, and blanking stages distinct. No fetched bytes, bus addresses, CPU timing, program data, or reference images change in this follow-up.

Final sequential Release integration on 2026-10-16 runs `VIC.*Tests|C64TimingTests` with both fixture sets enabled: **406 test cases in 436.1 seconds, 405 passing, one public-runner case failing two strict visual assertions, and no skips**. All 98 public programs complete with their original success code. **96 programs pass: four self-checking bus/collision probes and 92 exact images / 7,227,520 matching color indices**. The remaining differences are:

| Program | Previous ECM checkpoint | Current differences |
|---------|-------------------------|---------------------|
| `videomode1-pal` | 3 | 1: `(63,5)` is color 6, expected 14 |
| `videomode2-pal` | 4 | 0, exact pass |
| `modesplit-pal` | 482 | 0, exact pass |
| `modesplit-ntsc` | 856 | 326, still failing |

Independent before/after comparison finds **1,018 corrected pixels and zero newly wrong pixels** across those four images. Their completion cycles, PC, and raster positions are unchanged. All 90 previously passing complete PPM captures remain byte-identical to the ECM baseline, including pixels outside the reference crops. Both external multiplexers retain all 960 exact PAL/NTSC frames / 61,440,000 pixels. Befana retains its PAL level-2 milestone, 1,715,786 exact sprite pixels, and separately classified NTSC deadline diagnostic. The two remaining visual failures are not exceptions or passes, and alternate VIC/C64C revisions and broader games/demos remain unproved.

`swift build --build-tests -j 2`, `sh -n script/fetch_vic_testprogs.sh`, and `git diff --check` pass. Logs remain local at `/tmp/swift64-vic-mcm-integration.log` and `/tmp/swift64-vic-mcm-checked.log`; captures remain ignored under `.build/vic-mcm-final-captures`. Runs use two build jobs and one emulator instance. VICE remains stopped, and no SID suite or app relaunch is part of this validation.

### NTSC graphics-address transitions

The NTSC 6567R8 address mask now has its own pending selection. ECM assertion retains the unmasked address for one more low phase. An isolated ECM clear still releases immediately, but a write that changes BMM at the same time retains the old ECM selection through the next low phase. PAL keeps its previously verified immediate assertion / delayed release. The BMM low-address stage remains independent, and the ECM mask is applied once to the resulting address rather than separately inside the text, bitmap, and idle branches.

This is an inferred timing model supported by the unchanged, hardware-matched modesplit reference, not a physical address-bus capture. [Bauer's graphics-sequencer description](https://www.cebix.net/VIC-Article.txt) identifies ECM as the A9/A10 gate; the profile-specific transition timing comes from the original probe and reference data. The focused Release comparison corrects **192 pixels in isolated ECM transitions and 108 in compound BMM/ECM transitions**, reducing NTSC differences **326 -> 26**, with zero newly wrong pixels. All three PAL captures remain byte-identical, and all four programs retain their completion cycles/PC/raster.

The remaining NTSC differences comprise 20 reference color-15 dots at `$D021` writes, two pixels at `(128,11)` / `(128,12)`, and four at `(68...71,70)`. The gray dots need independent chip/capture calibration; they are not grounds to insert unconditional gray output into the NMOS model. The other transition-edge pixels also remain unresolved. All 26 retain ordinary zero-tolerance assertions, as does the single remaining PAL `videomode1` pixel. Reference images and PRGs are unchanged.

The mode-output class now has 18 tests. Added real 6510 `STA $D011` cases verify the first and settled addresses and fetched data for six isolated/compound transitions on both profiles. Expanded checks cover assertion as well as release in text, bitmap, and idle state; expiry through refresh/idle/sprite slots; and reset with either pending selection. The checked Debug mode/color/sequencer slice passes **43 tests in 5.05 seconds**, without skips. Logs remain local at `/tmp/swift64-vic-ntsc-mask-checked.log` and `/tmp/swift64-vic-ntsc-mask-trial.log`; trial captures are ignored under `.build/vic-ntsc-mask-captures`.

Full Release integration completes **408 test cases in 437.8 seconds: 407 pass, one public-runner case fails the two remaining visual assertions, and none skip**. All 98 public programs complete; 96 pass, including the same 92 exact images / 7,227,520 color indices. Of the 94 complete captures, only `modesplit-ntsc` changes from the preceding multicolor baseline. All 92 previously passing images and the one-pixel PAL failure remain byte-identical. The NTSC completion checkpoint also remains 512,310 cycles / PC `$08C5` / raster `254:45`.

Hessian and Piper repeat all 960 exact PAL/NTSC display frames with unchanged overlap and priority counts. Befana repeats score 225, level 2, two lives, and 1,715,786 exact PAL sprite pixels; its separate NTSC diagnostic repeats the missed raster-zero deadline at `30:19` after 2,656 sorter clocks. The final checked build, fetch-script syntax, and whitespace checks pass. Final results are in `/tmp/swift64-vic-ntsc-mask-integration.log`, with ignored captures under `.build/vic-ntsc-mask-final-captures`. Validation remains sequential with one emulator; no VICE process, SID suite, app relaunch, or reference-image change is involved.

### Late bad lines and screen/color alignment

Six more unchanged programs from the same pinned public suite now exercise late display entry, line crunching, matrix/color wraparound, and sprite/bitmap interaction. The five `colorfetchbug` variants cover text and bitmap data with deliberately distinct screen/color rows. The [original hardware report](https://sourceforge.net/p/vice-emu/bugs/1627/) describes the text case's first line taking its color from the wrong row in another implementation. These fixtures test Swift64's existing clocked matrix/color pairing; no new timing workaround was needed.

`sequencer-shards-pal` is the author's small reproducer of an idle-to-display problem encountered in Lft's demo "Shards of Fancy". It combines expanded sprite DMA with late `$D011` bitmap writes. Its full PAL reference crop, including the top-right idle area and sprite bars, matches exactly. This is a [demo-derived test program](https://github.com/libsidplayfp/VICE-testprogs/blob/ef8e8efe52f3d43df7acefad132c6506239bddee/VICII/sequencer-bug/readme.txt), not a run of the complete demo or certification of its other parts.

The initial `colorfetch-main-pal` run exposed a runner defect: its RAM initialization wrote `$8A` beneath `$D7FF` with I/O banked out at cycle 855,256 / PC `$081A`. The raw debugger watchpoint incorrectly treated that RAM write as the result. Completion detection now requires the test port to be I/O-mapped using the effective 6510 pins, not just the port output latch. A ROM-free negative control checks all eight banking combinations, success/failure values, an unrelated mirrored address, and DDR input pull-ups. This does not ignore a real failure result: every value written to mapped `$D7FF` still becomes the result and must equal zero.

With that correction, all six programs complete naturally and match **613,632 / 613,632 color indices**. Each compares the existing 376x272 PAL display/border intersection without new masks or tolerances:

| Program | Cycles | PC | Raster |
|---------|--------|----|--------|
| `colorfetch-main-pal` | 1,097,238 | `$0945` | `256:30` |
| `colorfetch-main2-pal` | 94,782 | `$0907` | `256:30` |
| `colorfetch-main3-pal` | 94,783 | `$091F` | `256:31` |
| `colorfetch-main4-pal` | 94,777 | `$091F` | `256:25` |
| `colorfetch-bitmap-pal` | 193,062 | `$0963` | `256:30` |
| `sequencer-shards-pal` | 160,733 | `$0A29` | `55:20` |

The focused Release run passes both test cases in 21.32 seconds. The checked Debug graphics-counter/color-latch/completion slice passes all 26 tests in 2.10 seconds. The programs, source, and PNG references remain local/untracked; `script/fetch_vic_testprogs.sh` fetches them from revision `ef8e8efe52f3d43df7acefad132c6506239bddee`. No emulator implementation code or ROMs are fetched.

```sh
sh script/fetch_vic_testprogs.sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
SWIFT64_PUBLIC_VIC_TEST_IDS=colorfetch-main-pal,colorfetch-main2-pal,colorfetch-main3-pal,colorfetch-main4-pal,colorfetch-bitmap-pal,sequencer-shards-pal \
  swift test -c release -j 2 --filter PublicVICConformanceTests
```

The bounded logs are `/tmp/swift64-vic-colorfetch-baseline.log` (the false RAM-write result), `/tmp/swift64-vic-colorfetch-mapped.log`, `/tmp/swift64-vic-late-display.log`, and `/tmp/swift64-vic-late-display-checked.log`. Captures stay ignored under `.build/vic-late-display-captures`. These six PAL passes do not resolve the existing PAL/NTSC mode-transition differences or certify alternate VIC revisions.

Full sequential Release integration with both public and external fixtures enabled executes **409 test cases in 462.6 seconds: 408 pass, one public-runner case fails the two known mode-transition assertions, and none skip**. All **104 public programs complete; 102 pass**, including **98 exact images / 7,841,152 matching color indices**. Every previous completion cycle/PC/raster checkpoint and all 94 previous complete captures remain identical to the NTSC-mask baseline, including the still-failing one-pixel PAL and 26-pixel NTSC images.

Hessian/Piper retain all 960 exact display frames and overlap/priority counts. Befana repeats PAL score 225 / level 2 / two lives / 1,715,786 exact sprite pixels, plus its separately classified NTSC deadline diagnostic. `swift build --build-tests -j 2`, fetch-script syntax, and whitespace checks pass. The final log is `/tmp/swift64-vic-late-display-integration.log`, with ignored captures under `.build/vic-late-display-final-captures`. No VIC, CPU, CIA, or SID implementation changed in this validation batch, and VICE remains stopped.

### Sprite startup and expansion boundaries

Nineteen additional unmodified public programs cover PAL/NTSC sprite enable/Y changes at DMA/display startup and PAL single/repeated sprite crunch. Ten initially failed despite returning `$D7FF=$00`: enable variants 1/2/4 differed by 378/157/149 pixels on each video standard, and repeated-crunch variants 26/27/28/29 differed by 472/348/286/228 pixels. Three VIC changes make every comparison exact:

- A new sprite display requires `$D015` still enabled at the display comparison. Clearing it after DMA starts does not cancel DMA, and clearing it after display starts does not truncate the active sprite.
- Sprite 0 starting DMA at the second Y comparison has only two BA warning clocks before its first high-phase slot. AEC still leaves the CPU connected for that slot, and the sprite receives `$FF` without a RAM read. MC still advances; the following two bytes and all later sprites/rows read normally.
- The Y-expansion advance decision precedes a CPU `$D017` write in the comparison cycle. Setting expansion in that CPU phase cannot retroactively repeat the row; clearing it still forces advancement. The previously failing repeated-crunch cases had incorrectly repeated the same bytes for eight additional lines.

The [sprite-enable sources and references](https://github.com/libsidplayfp/VICE-testprogs/tree/ef8e8efe52f3d43df7acefad132c6506239bddee/VICII/spriteenable) distinguish 6569/6567R8 from later-chip variants; only the former are used here. Its README records hardware checks for an older test revision, not direct hardware provenance for every current PNG. The [sprite-crunch references](https://github.com/libsidplayfp/VICE-testprogs/tree/ef8e8efe52f3d43df7acefad132c6506239bddee/VICII/spritecrunch) are upstream regression images. The three single-crunch filenames `3b-00`, `3c-00`, and `3d-00` contain identical PRG bytes at this revision (SHA-256 `3108d2b6141fda61fc94a79c176a94e05ec8a0e9d66764fed7f8f4e6ab523432`); only `3c-00` is retained in the runner, so duplicates do not inflate coverage.

All nineteen distinct probes match **1,873,608 color indices** without reference edits or tolerance. PAL uses the existing 376x272 crop. NTSC compares 376x235 pixels spanning raster 28-262, the physical intersection of the 384x247 reference and Swift64's captured frame. It includes the complete display and available borders, but does not certify the reference's extra rows beyond the end of the NTSC frame.

| Program | Cycles | PC | Raster |
|---------|--------|----|--------|
| `sprite-enable-1-pal` / `-ntsc` | 121,313 / 123,148 | `$08F9` / `$08FE` | `53:38` |
| `sprite-enable-2-pal` / `-ntsc` | 121,313 / 123,148 | `$08F8` / `$08FD` | `53:38` |
| `sprite-enable-3-pal` / `-ntsc` | 121,319 / 123,154 | `$08FA` / `$08FE` | `53:44` |
| `sprite-enable-4-pal` / `-ntsc` | 121,313 / 123,148 | `$08F7` / `$08FB` | `53:38` |
| `sprite-enable-5-pal` / `-ntsc` | 121,319 / 123,154 | `$08FA` / `$08FE` | `53:44` |
| `spritecrunch-3c-00-pal` | 143,223 | `$0957` | `89:24` |
| `spritecrunch2-07-pal` | 146,023 | `$0F9E` | `133:52` |
| `spritecrunch2-08-pal` | 146,116 | `$0F9E` | `135:19` |
| `spritecrunch2-09-pal` | 146,117 | `$0F9E` | `135:20` |
| `spritecrunch2-25-pal` | 146,145 | `$0F9E` | `135:48` |
| `spritecrunch2-26-pal` | 146,146 | `$0F9E` | `135:49` |
| `spritecrunch2-27-pal` | 146,147 | `$0F9E` | `135:50` |
| `spritecrunch2-28-pal` | 146,128 | `$0F9E` | `135:31` |
| `spritecrunch2-29-pal` | 146,089 | `$0F9E` | `134:55` |

Only the last two completion times change from the initial run, by 20 and 40 clocks respectively, as corrected sprite rows terminate DMA sooner. Five new ROM-independent regressions cover all eight display latches, real CPU expansion stores around the sampling edge, early/late DMA on both profiles, CPU read-pin visibility while RDY holds the microcycle, next-row recovery, and reset cleanup. Two older C64 timing assertions incorrectly expected immediate AEC takeover for a second-comparison start. They now check CPU ownership and `$FF` in the first slot, then VIC ownership in the next, retaining all their RDY and clock-progress assertions. The checked Debug sprite/C64-timing slice passes all 67 tests in 3.35 seconds. CPU behavior was not changed.

```sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
SWIFT64_PUBLIC_VIC_TEST_IDS=sprite-enable-1-pal,sprite-enable-1-ntsc,sprite-enable-2-pal,sprite-enable-2-ntsc,sprite-enable-3-pal,sprite-enable-3-ntsc,sprite-enable-4-pal,sprite-enable-4-ntsc,sprite-enable-5-pal,sprite-enable-5-ntsc,spritecrunch-3c-00-pal,spritecrunch2-07-pal,spritecrunch2-08-pal,spritecrunch2-09-pal,spritecrunch2-25-pal,spritecrunch2-26-pal,spritecrunch2-27-pal,spritecrunch2-28-pal,spritecrunch2-29-pal \
  swift test -c release -j 2 --filter PublicVICConformanceTests
```

Initial/fixed logs are `/tmp/swift64-vic-sprite-boundaries-baseline.log` and `/tmp/swift64-vic-sprite-boundaries-fixed.log`; they include the two duplicate labels before deduplication. The bounded write trace `/tmp/swift64-vic-crunch-edge.log` exposes the `$D017` sampling boundary. Source programs, PNG references, and generated PPM captures remain local/untracked. No VICE executable is needed or launched.

The complete external/public Release run takes 524.2 seconds. All **123 public programs complete; 121 pass**, with **117 exact images / 9,714,760 matching color indices**. All 100 prior complete captures and 104 prior completion result/cycle/PC checkpoints remain unchanged. Only `videomode1-pal` (one pixel) and `modesplit-ntsc` (26 pixels) fail the public comparisons. Hessian/Piper retain 960 exact PAL/NTSC display frames and unchanged overlap/priority counts. Befana repeats PAL score 225 / level 2 / two lives / 1,715,786 exact sprite pixels, plus its separate NTSC sorter-deadline diagnostic. The log is `/tmp/swift64-vic-sprite-boundaries-integration-final.log`, with ignored captures under `.build/vic-sprite-boundaries-final-captures`.

That integrated run also exposed an old unit test which explicitly expected a disabled sprite to start displaying after its DMA check. Its three assertions conflicted with the now-exact public enable references. `testSpriteEnableClearAfterDMACheckSuppressesDisplayButKeepsDMA` corrects the visibility expectations, verifies that late re-enabling cannot start that row, and still requires all three DMA bytes/counter increments. This subsequent change affects only the test, not the emulator or the external captures above.

After correcting that assertion, the final unit-only `VIC.*Tests|C64TimingTests` slices each execute 414 cases: **407 pass, seven opt-in cases skip, and zero fail**, in 0.54 seconds for Release and 7.38 seconds for checked Debug. Those skips are the six external programs and public-runner case exercised in the separately enabled run above, not seven additional passes. Logs: `/tmp/swift64-vic-sprite-boundaries-unit-final.log` and `/tmp/swift64-vic-sprite-boundaries-debug-final.log`. `swift build --build-tests -j 2` passes in 4.47 seconds; fetch-script syntax and `git diff --check` pass. No core code changes after the full external/public run, and no SID tests or app launches in this batch.

### Raster IRQ holdoff and display-enable boundaries

The unchanged public `rasterirq_hold` program exposed a false raster IRQ: it writes the next raster value to `$D012` in the final clock of each line, keeping the comparator matched. Resetting the IRQ decision at every line produced **11,432 wrong border pixels**. The VIC now retains the comparator match across lines and evaluates a final-phi2 compare write together with the incoming raster value. A continuous match cannot manufacture another rising edge; normal unmatched-to-matched interrupts and the existing same-line suppression remain intact.

This behavior is documented by the original researchers in the [VIC Addendum, Raster IRQ section](https://github.com/martinpiper/C64Docs/blob/b82ab2af6a84396fa20c2a7b5b2f7131fa89ac55/VIC/VIC-Addendum.txt), which points to [the public test program](https://github.com/libsidplayfp/VICE-testprogs/blob/ef8e8efe52f3d43df7acefad132c6506239bddee/VICII/rasterirq/rasterirq_hold.asm). No emulator implementation code is used. The addendum covers PAL; NTSC boundary tests exercise the same modeled mechanism but are not independent NTSC hardware calibration.

Fourteen other new unchanged public programs already pass before this fix: `den01-49-1/2`, `den10-48-1/2`, `denrsel-0/1`, and `disable-bad`, each in PAL and NTSC. They check DEN arming, border opening, and forced/cancelled late bad lines. The last test is a reproducer for an effect in the demo "angle +1", not a full-demo pass. Their references use the existing PAL/NTSC physical-frame intersection crops, with zero tolerance.

Five ROM-independent tests in `VICRasterIRQEdgeTests` cover real 6510 stores one clock before/on/after the boundary, a genuinely new match, rejection of a departing-line match, the ninth raster bit, IRQ-mask changes, comparator rearming, and reset. Two older frame-wrap tests now clock the complete frame rather than manually jumping over the comparator's low interval. The checked Debug VIC/timing slice runs **419 cases: 412 pass, seven opt-in skips, zero failures**. `swift build --build-tests -j 2` also passes.

```sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
SWIFT64_PUBLIC_VIC_TEST_IDS=den01-49-1-pal,den01-49-1-ntsc,den01-49-2-pal,den01-49-2-ntsc,den10-48-1-pal,den10-48-1-ntsc,den10-48-2-pal,den10-48-2-ntsc,denrsel-0-pal,denrsel-0-ntsc,denrsel-1-pal,denrsel-1-ntsc,disable-bad-pal,disable-bad-ntsc,rasterirq-hold-pal \
  swift test -c release -j 2 --filter PublicVICConformanceTests
```

Baseline and bounded IRQ-register trace: `/tmp/swift64-vic-den-baseline.log` and `/tmp/swift64-vic-irqhold-trace.log`. The trace uses `SWIFT64_PUBLIC_VIC_TRACE_RASTER=1` and `SWIFT64_PUBLIC_VIC_TRACE_AFTER_CYCLES=118900`. ROMs, original PRGs, reference PNGs, and generated PPMs remain local/untracked. VICE remains stopped after its unrelated startup crash; no SID tests or app launches are part of this work.

Final sequential Release integration takes **577.9 seconds**, running 419 cases with 418 passing and the public-runner case failing only its two existing visual assertions. All **138 public programs complete; 136 pass**, including **132 exact images / 11,151,456 color indices**. All fifteen additions match **1,436,696 color indices**. Holdoff retains its original completion checkpoint: **121,091 cycles, PC `$08AD`, raster `50:5`**, now with **0/102,272** differences. All 119 prior complete captures and 123 prior result/cycle/PC checkpoints remain identical. The two remaining failures are still `videomode1-pal` (one pixel) and `modesplit-ntsc` (26 pixels), not exceptions or tolerated matches.

Both external multiplexers retain all 960 exact PAL/NTSC display frames and their overlap/priority counts. Befana retains PAL score 225 / level 2 / two lives / 1,715,786 exact sprite pixels, plus the separately classified NTSC sorter-deadline diagnostic. Final integration log: `/tmp/swift64-vic-irq-edge-integration.log`; ignored captures: `.build/vic-irq-edge-final-captures`. A subsequent Release run of `PublicVICConformanceTests|VICRasterIRQEdgeTests|C64InterruptTests`, selecting only `rasterirq-hold-pal` for the public runner, passes **25 cases** in 3.33 seconds with the same result/cycle/PC/raster and exact image. Its log is `/tmp/swift64-vic-irq-edge-repeat.log`. The checked build, script syntax, and whitespace checks pass. No core changes follow the full integration run.

### Frame-wrap and IRQ acknowledgement timing

The raster counter now reaches zero one clock after the physical scanline wraps, placing the line-zero IRQ comparison in hardware cycle 2. Ordinary lines still compare in cycle 1. CPU reads of `$D011/$D012` and their mirrors retain the preceding final-line value during that first clock. Frame-start latches reset with the counter; frame length, sprite DMA slots, framebuffer geometry, and `frameReady` cadence do not gain a clock. This follows [Bauer section 3.12](https://www.cebix.net/VIC-Article.txt) and the [VIC Addendum's start-of-frame observation](https://raw.githubusercontent.com/martinpiper/C64Docs/b82ab2af6a84396fa20c2a7b5b2f7131fa89ac55/VIC/VIC-Addendum.txt). The Addendum specifically documents PAL; the PAL/NTSC unit coverage is not independent chip-revision calibration.

The unchanged public [IRQ acknowledgement program](https://github.com/libsidplayfp/VICE-testprogs/blob/ef8e8efe52f3d43df7acefad132c6506239bddee/interrupts/irq-ackn-bug/irq-ack-vicii.asm), now selected as `irq-ack-pal`, exposed a separate CPU ordering error. The first two timing offsets of both `INC $D019` and `ASL $D019` lost IRQs for raster and sprite-sprite sources; `STA` acknowledgement and register readback were already correct. The failure was identical before and after the frame-wrap fix. CPU pin sampling now precedes same-cycle bus side effects, so an acknowledgement cannot erase the already sampled IRQ. Existing I-flag and NMI polling timing is unchanged.

Before the CPU fix, the original program reported 255 at **990,000 cycles, PC `$0BFB`, raster `114:18`**. After it, the program reports 0 at **990,669 cycles, PC `$0BFB`, raster `124:57`**, with all embedded expected acknowledgement results satisfied. No program bytes or expected results are patched. Its original source is PAL-timed; no NTSC pass is inferred. This is a self-checking fixture, not an additional screenshot comparison.

Six new frame-wrap tests cover real CPU reads/writes around the edge, register mirrors, interrupt masks/acknowledgement, reset cleanup, and three constant-length frames per video standard. Three CPU regressions cover all twelve absolute RMW opcodes, a newly asserted IRQ that must wait for its polling window, and a read-to-clear dummy access. Before the CPU change those three tests produce 15 assertion failures; afterward the checked Debug CPU/VIC/CIA/drive slice runs **826 cases: 803 pass, 23 opt-in cases skip, zero fail**. A focused Release repeat passes 23 cases, including the original acknowledgement/collision programs, Blackmail FLI, and raster holdoff; both visual fixtures retain exact pixels and their prior completion checkpoints.

```sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
SWIFT64_PUBLIC_VIC_TEST_IDS=irq-ack-pal,blackmail-fli-pal,rasterirq-hold-pal,sprite-collision-pal,graphics-collision-pal \
swift test -c release -j 2 --filter 'PublicVICConformanceTests|CPUInterruptPollingTests|VICRasterIRQEdgeTests'
```

Baseline logs: `/tmp/swift64-vic-irq-ack-baseline.log` and `/tmp/swift64-vic-irq-rmw-baseline.log`. Fixed checked/Release logs: `/tmp/swift64-vic-irq-sampling-debug.log` and `/tmp/swift64-vic-irq-sampling-release-focus.log`. All runs are sequential. Original programs and captures remain ignored; no VICE executable, emulator implementation code, SID tests, audio playback, or app launches are used for this follow-up.

Full sequential Release integration runs **826 cases in 1,118.0 seconds: 811 pass, 14 optional CPU/slow-drive cases skip, and one public-runner case fails only its two existing visual assertions**. All **139 public programs complete; 137 pass**, including **132 exact images / 11,151,456 color indices**. All 138 previous result/cycle/PC checkpoints and all 134 previous complete public captures remain identical. `videomode1-pal` still differs at one pixel, and `modesplit-ntsc` at 26; neither is waived or counted as a pass.

Both external multiplexers retain 960 exact full-display frames. Befana repeats PAL level 2 / score 225 / two lives / 1,715,786 exact sprite pixels; the NTSC sorter still schedules its line-zero IRQ at `30:19` after 2,656 clocks, a separately classified deadline diagnostic. The scrolling game retains 660 checked frames and 17,829,600 exact graphics/HUD pixels per profile, plus 279,215 PAL / 279,006 NTSC opaque sprite pixels, with the same six blanking frames and area transition. All 14 prior external checkpoint captures are byte-identical.

```sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
SWIFT64_PUBLIC_VIC_CAPTURE_DIR=.build/vic-irq-sampling-final-public \
SWIFT64_EXTERNAL_VIC_DEMOS_DIR=.build/vic-framework-fresh-fixtures \
SWIFT64_EXTERNAL_VIC_CAPTURE_DIR=.build/vic-irq-sampling-final-external \
swift test -c release -j 2 --filter 'CPU.*Tests|VIC.*Tests|C64TimingTests|C64InterruptTests|CIA.*Tests|VIA6522Tests|IECBusTests|Drive1541Tests'
```

Integration log: `/tmp/swift64-vic-irq-sampling-release-integration.log`. Final `swift build --build-tests -j 2`, fetch-script syntax, and whitespace checks pass; the build log is `/tmp/swift64-vic-irq-sampling-final-build.log`. No core changes follow that full run. These results establish the corrected edge and acknowledgement behavior while retaining existing game/demo proof; they do not certify all raster effects or alternate VIC revisions.

### Ultimax VIC memory and cartridge graphics

The VIC's memory path previously ignored cartridge mapping entirely. In Ultimax mode, local `$3000-$3FFF` now reads the upper 4K of ROMH (CPU `$F000-$FFFF`) independently of the CIA2 RAM bank. The other 12K remains CIA-banked RAM, including the normally character-ROM-mapped addresses. Normal 8K/16K/off modes retain their existing RAM/character-ROM mapping. Missing ROMH uses the shared-bus value rather than exposing hidden RAM, and VIC reads do not invoke CPU read callbacks or cartridge CPU-read side effects.

The mapping follows Thomas Giesel's hardware-derived [PLA tables A.10-A.11 and address-bus pull-ups](https://skoe.de/docs/c64-dissected/pla/c64_pla_dissected_a4ss.pdf#page=64). The pinned [original EasyFlash VIC probes and hardware observations](https://github.com/libsidplayfp/VICE-testprogs/tree/ef8e8efe52f3d43df7acefad132c6506239bddee/C64/carts/ultimax) provide three independent reference comparisons. These are three startup modes of the same test program, not three different games. Each changes CIA2 banks and screen/charset selection, boots through its cartridge reset vector, and writes its original `$D7FF` completion. No program, reference pixels, or ROMs are patched. The runner recognizes mapped Ultimax I/O regardless of `$01`; a negative control checks every CPU-port configuration.

Before the fix, `ultimax-vic-ef-pal` differed at **7,819 / 64,000 pixels**; afterward it is exact. `8k-vic-ef-pal` and `16k-vic-ef-pal` match before and after. All three retain **763,110 cycles / PC `$09D6` / raster `256:54`**, with result zero. Their fixed Release repeat checks **192,000 exact color indices** and passes all seven selected XCTest cases. Four ROM-independent cartridge regressions cover all CIA banks, upper/lower ROMH distinction, EasyFlash bank/mode/reset changes, CPU-port independence, missing ROM, and actual PAL/NTSC sprite DMA with pointers in RAM or ROM. The checked Debug cartridge/memory/sprite/completion slice runs 181 cases: 180 pass, the public-runner case skips, and none fail.

```sh
sh script/fetch_vic_testprogs.sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
SWIFT64_PUBLIC_VIC_TEST_IDS=ultimax-vic-ef-pal,8k-vic-ef-pal,16k-vic-ef-pal \
swift test -c release -j 2 --filter 'PublicVICConformanceTests|CartridgeTests/testUltimaxVIC'
```

Baseline/fixed logs: `/tmp/swift64-vic-ultimax-public-baseline.log` and `/tmp/swift64-vic-ultimax-public-fixed.log`. Captures remain ignored under `.build/vic-ultimax-baseline` and `.build/vic-ultimax-fixed`. The three references are PAL; PAL/NTSC synthetic DMA checks are not independent NTSC hardware measurements. Phase-dependent custom cartridge logic, address-line overrides, and general freezer compatibility are outside this proof. No VICE executable, SID suite, or app launch is used.

Full sequential Release validation runs **991 cases in 1,117.8 seconds: 976 pass, 14 optional CPU/slow-drive cases skip, and one public-runner case fails only the two existing visual assertions**. All **142 public programs complete; 140 pass**, including **135 exact images / 11,343,456 matching color indices**. The one-pixel `videomode1-pal` and 26-pixel `modesplit-ntsc` differences remain ordinary failures, not waived matches. All 139 prior result/cycle/PC/raster checkpoints, all 134 previous public captures, and all 14 previous external captures remain identical. Hessian/Piper retain 960 exact display frames; Befana retains its PAL level-2 milestone and separate NTSC deadline diagnostic; the scrolling game retains both 660-frame profile runs and area transitions.

The same checked Debug selection runs **991 cases: 968 pass, 23 opt-in cases skip, zero fail**, in 43.9 seconds. The complete Release and Debug logs are `/tmp/swift64-vic-ultimax-integration.log` and `/tmp/swift64-vic-ultimax-debug-integration.log`. Final public/external captures are ignored under `.build/vic-ultimax-final-public` and `.build/vic-ultimax-final-external`. `swift build --build-tests -j 2`, fetch-script syntax, and whitespace checks pass; the build log is `/tmp/swift64-vic-ultimax-final-build.log`. No core changes follow these runs.

```sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
SWIFT64_EXTERNAL_VIC_DEMOS_DIR=.build/vic-framework-fresh-fixtures \
swift test -c release -j 2 --filter 'CPU.*Tests|VIC.*Tests|C64TimingTests|C64InterruptTests|CIA.*Tests|VIA6522Tests|IECBusTests|Drive1541Tests|MemoryMapTests|CartridgeTests'
```

### Sprite reload and cycle stealing

The original [sprite-X test programs](https://github.com/libsidplayfp/VICE-testprogs/tree/ef8e8efe52f3d43df7acefad132c6506239bddee/VICII/spritex) expose a reload boundary used by the ninth-sprite trick in Krestage 3. A sprite consumed at X=256 is repositioned into the right border. Before the fix, PAL cases 14/15 and NTSC cases 14/15/16 incorrectly collide. PAL must reject X=365/366 but allow X=367; the corresponding NTSC cases must all remain clear. The pinned source contains **29 cases**, despite the older README's 28-row table.

The sprite shifter now gates output and new X matches through its pointer-fetch cycle and the first three dots of its middle-byte cycle. Reload cancels an already active tail, including expansion/multicolor phase state. This is an empirical sequencer model constrained by the original public results, not a transistor-level derivation. It uses the slot phase rather than hard-coded X coordinates, so wrapped PAL/NTSC slots share the same rule. Memory access phases, MC progression, BA/AEC, inactive-fetch byte contents, and ordinary register-write timing are unchanged.

The original [cycle-stealing programs and hardware measurements](https://github.com/libsidplayfp/VICE-testprogs/tree/ef8e8efe52f3d43df7acefad132c6506239bddee/VICII/spritesteal) additionally check ten enable masks on two sprite-Y/measurement-line combinations. Each combination records 64 separately timed frames and compares 63 measurements with its embedded reference. They run unchanged, with a bounded 30-million-cycle budget per profile rather than the usual three-million-cycle cap. They passed before the reload fix; they are new independent timing coverage, not a claimed timing improvement.

```sh
sh script/fetch_vic_testprogs.sh
SWIFT64_PUBLIC_VIC_TESTPROGS_DIR=.build/vic-testprogs \
SWIFT64_PUBLIC_VIC_TEST_IDS=sprite-x-pal,sprite-x-ntsc,sprite-steal-pal,sprite-steal-ntsc \
swift test -c release -j 2 --filter PublicVICConformanceTests
```

Baseline: `/tmp/swift64-vic-sprite-reuse-baseline.log`. The fixed focused Release run, `/tmp/swift64-vic-reload-public.log`, passes all 12 selected public programs. Both 29-case sprite-X tests report zero: PAL **612,822 cycles / PC `$09D2` / raster `55:21`**, NTSC **533,524 / `$09D3` / `55:4`**. Their one-clock difference from the failing run follows the original success/failure branch. Both side-border sprite references, five sprite-register-split references, and Blackmail FLI still match exactly; sprite-sprite and sprite-graphics collision timing checks also pass.

Three bounded ROM-independent regressions exercise the early-reuse boundary, all eight sprite fetch slots in PAL/NTSC with hires/multicolor/X expansion, and cancellation of an in-flight tail without spontaneous restart. The all-slot checks establish implementation consistency, not additional hardware measurements. The checked Debug VIC/timing run executes **432 cases: 423 pass, nine opt-in skips, zero fail**, in 16.4 seconds (`/tmp/swift64-vic-reload-debug-final.log`). Public fixtures, ROMs, and generated captures remain ignored. No VICE executable or SID suite is used.

Full sequential Release integration executes **994 cases in 1,351.2 seconds: 979 pass, 14 optional cases skip, and one public-runner case fails its two unchanged visual assertions**. All **146 public programs complete; 144 pass**, including **135 exact images / 11,343,456 color indices**. The remaining failures are `videomode1-pal` (one pixel) and `modesplit-ntsc` (26 pixels), with no tolerances or waivers. Both cycle-stealing probes retain their baseline checkpoints: PAL **25,726,795 cycles / PC `$0918` / raster `265:52`**, NTSC **22,428,305 / `$0918` / `257:55`**. All 142 prior completion checkpoints, all 137 public captures (including the two failing comparisons), and all 14 external captures remain identical.

Hessian/Piper retain 960 exact display frames. Befana retains PAL level 2 / score 225 / two lives / 1,715,786 exact sprite pixels, plus its separately classified NTSC deadline diagnostic. Both scrolling-game profiles retain 660 checked frames, their area transition, and the same graphics/sprite counts. The broad checked Debug integration executes **994 cases: 971 pass, 23 opt-in skips, zero failures**, in 43.4 seconds. Logs: `/tmp/swift64-vic-reload-integration.log` and `/tmp/swift64-vic-reload-debug-integration.log`; ignored captures: `.build/vic-reload-final-public` and `.build/vic-reload-final-external`. No core changes follow these runs.

## VIC graphics counters and raster effects

The graphics sequencer now reloads VC/VMLI in hardware cycle 14 phi1 and updates RC/VCBASE in cycle 58 phi1. Bad-line conditions enter display state independently of matrix-DMA scheduling. Matrix and color data are retained in the internal line buffer; g-accesses never obtain missing matrix data through an extra RAM read. Idle g-accesses still read memory and produce graphics with zero matrix/color bits. Framebuffer composition has no counter side effects.

`VICGraphicsSequencerTests` covers PAL and NTSC with 15 bounded, ROM-independent tests. Checks include all 1000 screen/color fetches and 200 pixel rows of a text frame, FLD-delayed rows, 16 FLI rasterlines with changing matrices, late-start DMA with a non-aligned VCBASE, line-crunch wrapping, idle reads/pixels, closed-border counter progress, and original 6510 `STA $D011` instructions before/after the RC-reset comparison. Old beam fixtures now arm actual matrix DMA or explicitly seed the skipped row; their pixel assertions remain intact. Snapshot composition tests no longer expect rendering to advance the machine clock.

Reference: [Christian Bauer's VIC-II article](https://www.cebix.net/VIC-Article.txt), sections 3.7.1-3.7.3 and 3.14.2-3.14.6. VMLI is modeled as a buffer index, not an analog multi-selected-cell network. Precise late-BA/AEC takeover, startup color-bus values, sub-dot register visibility, and external demo captures remain uncalibrated. These synthetic checks establish the implemented counter behavior, not complete FLI/VSP compatibility.

Graphics-sequencer validation (2026-10-15): `swift build --build-tests -j 2` passed; the focused checked Debug VIC/timing slice passed all 338 tests with zero failures. The following sequential Release integration command passed 548 tests with zero failures or skips. No SID suite or audio playback was run:

```sh
swift test -c release -j 2 --filter 'CPU6502Tests|MemoryMapTests|VICTests|VICGraphicsSequencerTests|VICSpriteShifterTests|VICBeamTimingTests|VICPriorityTests|VICSlotTimingTests|VICSpriteFetchTests|VICSpriteDMALifecycleTests|C64TimingTests|C64InterruptTests|CIATests'
```

## Audible SID and Release playback

`SIDAudioQualityTests` covers known pitches (110/440/1760 Hz), triangle/saw/pulse headroom in both models and modes, fast-filter response versus cycle integration, an original three-voice 6510 program, speaker-buffer overrun accounting, and underrun/recovery without a false DC transient. Run sequentially:

```sh
swift test -c release -j 2 --filter 'CPU6502Tests|MemoryMapTests|SIDAudioQualityTests|SIDTests|C64TimingTests|VICTests|VICSlotTimingTests|VICSpriteFetchTests|CIATests|Drive1541Tests|KernalTrapsTests'
```

The Release app has an opt-in ROM-independent sound check. It uses the normal CPU/VIC/SID emulation thread and AVAudioEngine output path, changes no saved preferences, and exits after reporting. The tone is a 440 Hz pulse; music is an original repeating 16-note, three-voice program with a pulse lead, triangle bass, and filtered saw accompaniment. The drive is deliberately disabled, so this is not a true-drive throughput benchmark. Run one instance at a time, without a simultaneous build or test job:

```sh
SWIFT64_AUDIO_CHECK_SECONDS=12 SWIFT64_AUDIO_CHECK_KIND=tone \
SWIFT64_AUDIO_CHECK_MODEL=mos6581 SWIFT64_AUDIO_CHECK_MODE=compatibility \
DerivedData/Swift64/Build/Products/Release/Swift64.app/Contents/MacOS/Swift64

SWIFT64_AUDIO_CHECK_SECONDS=120 SWIFT64_AUDIO_CHECK_KIND=music \
SWIFT64_AUDIO_CHECK_MODEL=mos6581 SWIFT64_AUDIO_CHECK_MODE=compatibility \
DerivedData/Swift64/Build/Products/Release/Swift64.app/Contents/MacOS/Swift64
```

Repeat with `mos8580`, `fast`, and `SWIFT64_AUDIO_CHECK_STANDARD=ntsc`. Set `SWIFT64_AUDIO_CHECK_HZ=110` or `1760` for low/high tone checks (default 440 Hz; bounded to 20-10000 Hz). Duration is bounded to 3-300 seconds. Two fixed buffers retain the first and last 12 seconds, about 4.1 MiB total regardless of run length. The printed `AUDIO_VALIDATION` path points to the opening WAV; a `-tail.wav` and version-2 JSON sit alongside it in the app's sandbox cache (`Swift64/AudioValidation`). Names include video standard, model, mode, and tone frequency, so PAL/NTSC and different tones cannot overwrite one another. Repeating the same configuration replaces its prior capture.

WAVs capture the actual Core Audio source samples after DC removal, clipping protection, and recovery fades, not an unrelated offline synthesizer. Reports include requested/elapsed/audio/captured durations, tail position, sample and frame rates, RMS, peak, first-signal time, longest silence before/after onset, invalid samples, and startup/underrun/overrun/clipping counts. Low Power Mode and thermal state are recorded at the start and end. Overruns count unread samples overwritten by the SID producer since SID reset. This measures the app's source output, not the physical DAC or speakers.

Check the actual PCM with the standard-library-only analyzer, between playback runs:

```sh
python3 script/analyze_sid_capture.py --min-seconds 119 \
  "$HOME/Library/Containers/com.holgervonameln.swift64/Data/Library/Caches/Swift64/AudioValidation/music-pal-mos6581-compatibility.json"
```

The checker exits nonzero for queue loss, clipping, silence, missing/short capture, inconsistent timing/frame accounting, wrong tone pitch, or wrong music. For the original music fixture it identifies all 16 opening lead notes, then independently checks a full 16-note cycle at the expected tempo in the final capture; only the tail's starting phase is fitted. This is a fixture-specific musical regression, not a general music-quality or hardware-fidelity metric. Use `--min-seconds 11` for twelve-second tone captures. Do not include older version-1 reports in a new gate.

Acceptance: low/mid/high tones at the requested pitch after startup; the expected three-voice melody at both the beginning and end; no non-finite samples or clipped frames; and zero post-startup underruns or producer overruns in a sustained run on a machine able to maintain real time. An overloaded host is a performance failure to investigate, not evidence of an oscillator error. Preserve local results for listening comparisons; never commit WAVs or other generated media. These original fixtures establish usable playback, not calibrated analog SID hardware fidelity or general game compatibility.

The shared speaker path buffers 4096 samples (about 93 ms) once at startup, removes DC, and uses short recovery fades instead of holding a stale sample or restarting a long prebuffer after each gap. The DC filter retains its source history across underruns: reseeding at an arbitrary waveform phase produced false DC steps and recovery clipping. A regression compares recovered output to uninterrupted reference samples after the fade.

Frame pacing uses a monotonic deadline and replenishes a depleted queue with normal emulated cycles, never a retuned SID clock. While running, the app holds a [user-initiated activity that allows idle system sleep](https://developer.apple.com/documentation/foundation/processinfo/activityoptions/userinitiatedallowingidlesystemsleep), adding [latency-critical timer/I/O precision](https://developer.apple.com/documentation/foundation/processinfo/activityoptions/latencycritical) when an audio output is attached. It releases the activity on debugger pause or loop exit. The precision request is a power/performance tradeoff confined to active playback, not an exclusive CPU reservation or a guarantee under arbitrary host load. The app does not change the user's power settings.

Xcode Release builds select compile-time exclusivity enforcement for `Emu6502` and `C64Core` only. Debug builds and the Swift Package regression builds retain runtime checks; the app target also retains its default checks. This is a measured playback-performance tradeoff, not permission to introduce overlapping accesses: [Swift's exclusivity guidance](https://www.swift.org/blog/swift-5-exclusivity/) warns that unchecked violations remain undefined behavior. Keep checked SID/VIC/CPU/timing tests as a release gate, particularly when changing core callbacks or `inout` accesses. Bounds checks and normal `-O` optimization remain enabled; do not substitute `-Ounchecked`.

### Recorded playback gate: 2026-10-15

Native ARM64 Xcode Release, drive off, Mac14,2 with 8 GB RAM, AC power, Low Power Mode disabled. Eight sequential 120-second music runs cover PAL/NTSC, 6581/8580, and fast/compatibility. All eight passed the independent PCM checker: zero underrun frames/events, producer overruns, clipped frames, or invalid samples; all 16 expected lead notes matched in both opening and tail captures. Reports recorded nominal thermal state at both endpoints. No simultaneous build/test job or second emulator was running. These results supersede the narrower 2026-10-14 PAL-only check.

| Standard / model / mode | Rendered seconds | Music RMS | Music peak |
| --- | ---: | ---: | ---: |
| PAL / 6581 / fast | 120.021 | 0.23637 | 0.76719 |
| PAL / 6581 / compatibility | 120.597 | 0.29810 | 0.87994 |
| PAL / 8580 / fast | 120.000 | 0.18997 | 0.65771 |
| PAL / 8580 / compatibility | 120.587 | 0.19034 | 0.59582 |
| NTSC / 6581 / fast | 120.075 | 0.23829 | 0.77703 |
| NTSC / 6581 / compatibility | 119.648 | 0.29923 | 0.87866 |
| NTSC / 8580 / fast | 120.683 | 0.19189 | 0.66308 |
| NTSC / 8580 / compatibility | 120.128 | 0.19191 | 0.60590 |

All 24 low/mid/high tone configurations were captured through the same Release speaker path. PAL measured approximately 109.993 / 440.029 / 1759.999 Hz; NTSC approximately 109.971 / 440.004 / 1760.017 Hz. All had zero queue loss, clipping, and invalid samples. Twenty-three twelve-second runs passed directly. The first PAL 6581 fast 110 Hz run had correct pitch but failed the unchanged clock-consistency gate (11.595 rendered seconds versus 12.076 callback-wall seconds). Its report was retained locally; a 30-second repeat passed, including timing and both pitch windows. The short-run timing discrepancy was not isolated to a particular callback and is not proof of an oscillator fault or a physical-output pass.

RMS/peak above are whole-run source-buffer statistics, including startup silence, not hardware-reference measurements. Captures retain the first and last 12 seconds; counters cover all 961.739 seconds of music playback. The focused checked regression command above passed 801 tests, 12 opt-in skips, zero failures. The Release bundle passed `codesign --verify --deep --strict`.

Earlier battery/Low Power Mode stress runs, before the final DC-recovery change and latency-critical activity, failed all eight sustained configurations: 2941-333212 missing samples per run, with recovery clipping in two runs. Their JSON reports remain in `/tmp/swift64-audio-low-power/`. Power state, code, and host load changed between the stress and final runs, so these results do not isolate one cause or certify sustained low-power playback. Timing-preserving optimizations removed idle drive diagnostic hashing, reduced VIC raster-buffer access overhead, and simplified the common single-wave SID path; no emulated cycles were skipped. Re-run the gate after audio, pacing, or hot-path changes.

Captures remain local at `~/Library/Containers/com.holgervonameln.swift64/Data/Library/Caches/Swift64/AudioValidation/`. This closes the bounded PAL/NTSC known-tone/original-music playback gate under the stated conditions. It does not certify long game/true-drive sessions, physical DAC output, low-power operation, or calibrated analog SID accuracy. Public SID conformance fixture handling remains experimental as noted above.

Local public CPU functional-test binaries are also opt-in and run as a single bounded emulator instance. Keep those binaries untracked and provide the success self-loop address for the specific fixture you are running. Set `SWIFT64_CPU_FUNCTIONAL_RESULT_JSON` when you want a machine-readable result artifact with binary metadata, final CPU registers, final PC, cycle counts, and pass/jam/timeout reason:

```sh
SWIFT64_CPU_FUNCTIONAL_TEST_PATH=/path/to/6502_functional_test.bin \
SWIFT64_CPU_FUNCTIONAL_SUCCESS_PC=0x3469 \
SWIFT64_CPU_FUNCTIONAL_START_PC=0x0400 \
SWIFT64_CPU_FUNCTIONAL_INITIAL_A=0x00 \
SWIFT64_CPU_FUNCTIONAL_INITIAL_X=0x00 \
SWIFT64_CPU_FUNCTIONAL_INITIAL_Y=0x00 \
SWIFT64_CPU_FUNCTIONAL_INITIAL_SP=0xfd \
SWIFT64_CPU_FUNCTIONAL_INITIAL_P=0x24 \
SWIFT64_CPU_FUNCTIONAL_MAX_CYCLES=100000000 \
SWIFT64_CPU_FUNCTIONAL_EXPECTED_ELAPSED_CYCLES=1234567 \
SWIFT64_CPU_FUNCTIONAL_ELAPSED_CYCLE_TOLERANCE=0 \
SWIFT64_CPU_FUNCTIONAL_RESULT_JSON=/tmp/swift64-cpu-functional.json \
swift test --filter CPU6502ConformanceTests
```

For multiple public CPU fixtures, use a local untracked manifest and optional aggregate summary. Fixtures run sequentially, with a fresh 64K RAM bus and one CPU instance per fixture:

```json
{
  "fixtures": [
    {
      "id": "6502-functional",
      "name": "6502 functional test",
      "path": "6502_functional_test.bin",
      "loadAddress": "0x0000",
      "startPC": "0x0400",
      "successPC": "0x3469",
      "maxCycles": 100000000,
      "initialRegisters": {
        "a": "$00",
        "x": "$00",
        "y": "$00",
        "sp": "$fd",
        "p": "$24"
      },
      "expectedElapsedCycles": 1234567,
      "elapsedCycleTolerance": 0,
      "initialMemory": [
        { "address": "$fffc", "value": "$00" },
        { "address": "$fffd", "value": "$04" }
      ],
      "finalRegisters": {
        "a": "$00",
        "x": "$00",
        "y": "$00",
        "sp": "$fd",
        "p": { "value": "$24", "mask": "$ef" }
      },
      "finalMemory": [
        { "address": "$0200", "value": "$42" },
        { "address": "$0201", "value": { "value": "$80", "mask": "$f0" } }
      ],
      "finalMemoryRanges": [
        {
          "start": "$0200",
          "length": 16,
          "fnv1a64": "1234567890abcdef"
        }
      ],
      "expectedFailure": {
        "category": "cpu",
        "reasonContains": ["CPU jammed"],
        "note": "Known local waiver until the named opcode/timing issue is fixed"
      }
    }
  ]
}
```

The manifest summary records a stable manifest fingerprint, Phase 2 `category`/`roadmapPhase` labels, expected failures, unexpected failures, expected-failure drift, acceptance-failure counts, and compact failure details alongside full per-fixture records. Fixtures can apply `initialMemory` byte patches after binary load and before CPU execution, set optional `initialRegisters` for A/X/Y/SP/P after reset/start setup, then declare `expectedElapsedCycles` plus an optional `elapsedCycleTolerance`; reaching the success self-loop outside that window is reported as a `timing` failure. Optional `finalRegisters` checks compare A/X/Y/SP/P after the success loop is reached, `finalMemory` checks compare individual RAM bytes by address, and `finalMemoryRanges` checks FNV-1a 64-bit hashes over RAM ranges. Register and memory byte checks can be either a byte value or an object with `value` and `mask` for bit-level assertions. Empty fixture arrays may be omitted from hand-written manifests. The opt-in manifest test fails only when a fixture has an unexpected failure or when a fixture marked as an expected failure starts passing, which keeps CPU-suite waivers explicit and reviewable. Non-empty fixture IDs must be unique, explicit `maxCycles` values must be positive, and timing/register/memory expectation values must be valid so resumable summaries stay deterministic.

```sh
SWIFT64_CPU_FUNCTIONAL_MANIFEST_JSON=/path/to/cpu-functional-manifest.json \
SWIFT64_CPU_FUNCTIONAL_SUMMARY_JSON=/tmp/swift64-cpu-functional-summary.json \
swift test --filter CPU6502ConformanceTests/testOptInFunctionalManifestRunsSequentially
```

Large CPU functional manifests can be filtered by stable fixture ID with `SWIFT64_CPU_FUNCTIONAL_FIXTURE_IDS=id1,id2` before sharding; add `SWIFT64_CPU_FUNCTIONAL_REQUIRE_IDS_MATCH=1` when missing requested IDs should fail fast. They can also be sharded deterministically while still running one `swift test` process at a time. Each shard summary records `SWIFT64_CPU_FUNCTIONAL_SHARD_INDEX`/`SWIFT64_CPU_FUNCTIONAL_SHARD_COUNT`, requested and missing fixture IDs, selected fixture IDs/paths, selected-vs-manifest fixture counts, a derived `outcome` (`notRun`, `passed`, `expectedFailures`, `unexpectedFailures`, or `acceptanceFailed`), failed fixture IDs/paths, acceptance-failure fixture IDs/paths, and compact outcome/failure-category/expectation-status counts; the helper below writes one summary per shard plus a finalized `run-index.json`:

```sh
script/run_cpu_functional_shards.sh /path/to/cpu-functional-manifest.json 4
```

For Tom Harte/SingleStepTests-style JSON CPU vectors, keep the downloaded corpus outside the repository and run bounded slices by file or opcode list. Passing case records are omitted by default so large runs keep only aggregate counts plus failure records; add `SWIFT64_PROCESSOR_JSON_RECORD_PASSING=1` only for small debugging runs. `SWIFT64_PROCESSOR_JSON_STRICT_CYCLES=1` compares the executed cycle count plus each expected bus-cycle address, data value, and read/write operation:

```sh
SWIFT64_PROCESSOR_JSON_TEST_PATH=/path/to/6502/v1/69.json \
SWIFT64_PROCESSOR_JSON_STRICT_CYCLES=1 \
SWIFT64_PROCESSOR_JSON_RESULT_JSON=/tmp/swift64-processor-json-69.json \
swift test -c release --filter CPU6502ProcessorJSONTests/testOptInProcessorJSONSingleStepVectors

SWIFT64_PROCESSOR_JSON_TEST_DIR=/path/to/6502/v1 \
SWIFT64_PROCESSOR_JSON_OPCODES=ea,a9,85,20,60,00,40,6c,f0,d0,69,e9 \
SWIFT64_PROCESSOR_JSON_STRICT_CYCLES=1 \
SWIFT64_PROCESSOR_JSON_RESULT_JSON=/tmp/swift64-processor-json-summary.json \
swift test -c release --filter CPU6502ProcessorJSONTests/testOptInProcessorJSONSingleStepVectors
```

For the full Phase 2 CPU gate, use `SWIFT64_PROCESSOR_JSON_OPCODES=all`. This still runs one JSON file at a time and records only aggregate counts plus failure records by default:

```sh
SWIFT64_PROCESSOR_JSON_TEST_DIR=/path/to/6502/v1 \
SWIFT64_PROCESSOR_JSON_OPCODES=all \
SWIFT64_PROCESSOR_JSON_STRICT_CYCLES=1 \
SWIFT64_PROCESSOR_JSON_FAIL_FAST=1 \
SWIFT64_PROCESSOR_JSON_RESULT_JSON=/tmp/swift64-processor-json-all-opcodes.json \
swift test -c release --filter CPU6502ProcessorJSONTests/testOptInProcessorJSONSingleStepVectors
```

For local machines where a single full sweep is inconvenient, shard the opcode files deterministically. The runner below still executes one `swift test` process at a time, writes one compact JSON summary per shard plus a `run-index.json` listing shard outputs and run settings, finalizes that index even when a shard exits early, records the selected corpus path/opcode set/shard identity plus a stable selected-input FNV-1a fingerprint in each summary, exposes explicit aggregate/per-file `outcome` and `acceptanceFailures` fields plus Phase 2 `category`/`roadmapPhase` labels, structured aggregate `failureDetails`, `failedFiles`, `failedOpcodes`, and per-opcode pass/fail summaries, and defaults to strict cycle checks with fail-fast enabled:

```sh
script/run_cpu_json_shards.sh /path/to/6502/v1 8
```

Processor JSON fixtures are validated before execution, including register widths, RAM entry shapes, address/value ranges, and cycle operation names (`read`/`write`), so malformed local vector files fail with fixture/case/cycle diagnostics instead of looking like CPU regressions.

The Phase 2 CPU certification checkpoint currently passes the Klaus Dormann NMOS 6502 functional binary when loaded as a 64K RAM image with `SWIFT64_CPU_FUNCTIONAL_START_PC=0x0400` and `SWIFT64_CPU_FUNCTIONAL_SUCCESS_PC=0x3469`; do not start that fixture through its reset vector, because Klaus intentionally routes reset/NMI/IRQ vectors to failure traps. The same checkpoint also passes the full local SingleStepTests 6502-v1 strict-cycle sweep: 2,560,000 public vectors across all 256 opcode files. That sweep now covers the fixed KIL/JAM observed dummy-read timing, decimal-mode ARR overflow-safe correction, and AHX/TAS/SHX/SHY page-cross unstable-store masking against public per-cycle vectors. The roadmap Phase 2 gate is complete for CPU, memory, and bus behavior: focused checks cover CPU core behavior, interrupt/RDY/SO timing, C64 reset coupling, 6510 `$0000/$0001` port overlay semantics, VIC-visible RAM underneath the CPU port, ROM/I/O banking, color RAM/open-bus behavior, and VIC-driven CPU stalls. External public fixture sweeps remain local opt-in runs so normal development never starts a huge parallel corpus by accident.

For resumable local milestone runs, add a JSONL result log path. Reuse the same path with `SWIFT64_LOCAL_MILESTONE_RESUME=1` to skip milestones that already recorded a passing result. Add `SWIFT64_LOCAL_MILESTONE_RESUME_STRICT_MANIFEST=1` when you only want to trust previous passes recorded with the current `compatibility.json` content hash. Each run gets a generated ID; set `SWIFT64_LOCAL_MILESTONE_RUN_ID` to supply one explicitly for dashboards or resumable batch scripts:

```sh
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_RESULTS_JSONL=/tmp/swift64-milestones.jsonl swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_RESUME=1 SWIFT64_LOCAL_MILESTONE_RESULTS_JSONL=/tmp/swift64-milestones.jsonl swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_RESUME=1 SWIFT64_LOCAL_MILESTONE_RESUME_STRICT_MANIFEST=1 SWIFT64_LOCAL_MILESTONE_RESULTS_JSONL=/tmp/swift64-milestones.jsonl swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_RUN_ID=giana-compat-001 SWIFT64_LOCAL_MILESTONE_RESULTS_JSONL=/tmp/swift64-milestones.jsonl swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
```

To write a compact aggregate summary for dashboards or manual triage, set `SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON`. The per-milestone JSONL records include a format version, run ID, optional `skipped` marker, manifest hash, optional milestone ID/name, the milestone media type, action summary, max-cycle budget, `expectedFailure` match/mismatch diagnostics, result category plus roadmap phase, final CPU registers/lines, final VIC register snapshot hashes/snapshots, internal VIC state, raster/bus owner/bus phase/low-phase access, and high-/low-phase memory-read traces, 1541 drive state, final failure/no-progress diagnostics, media capability counts and preservation flags including weak-bit and variable-speed-zone counters, per-halftrack low-level track summaries for expected protected-media tracks, SID debug and non-mutating chip-readable register snapshots, tape state, bounded decoded screen text, screen hashes, full-framebuffer hashes for VIC visual proof, and optional screenshot paths. The aggregate summary records runner/result-format metadata, run ID, manifest/result/screenshot paths when configured, the manifest content hash, resume, failed-screenshot, screenshot capture counts split by passing and failed milestones, and limit settings, manifest milestone count, whole-manifest phase, media-type, machine-profile, drive-mode, SID-model, SID-accuracy-mode, observable-type, VIC proof-type, expected-failure-category, and action-type counts, selected media-type, machine-profile, drive-mode, SID-model, SID-accuracy-mode, observable-type, VIC proof-type, expected-failure-category, and action-type counts, required/invalid/missing manifest media-type, machine-profile, drive-mode, SID-model, SID-accuracy-mode, observable-type, VIC proof-type, expected-failure-category, and action-type coverage, untagged manifest milestone count, unnamed manifest milestone count, expected-failure waiver count, expected-failure waivers without notes, expected-failure waivers without reason markers, manifest milestones without explicit `maxCycles`, manifest milestones without explicit `actions`, manifest milestones without observable expectations, framebuffer-hash milestones without screenshot names, sanitized framebuffer screenshot filename collision count and colliding filenames, phase-filtered milestone count, pre-shard and selected milestone counts, selected/invalid phase filters, selected/missing milestone ID filters, shard index/count diagnostics, per-selected-phase milestone counts, selected phase names that matched no milestones, missing media filenames for the selected set, pass/fail/skip counts, expected vs unexpected failure counts/details, expected-failure drift counts/details for known regressions whose category or reason markers changed, derived `outcome` values (`notRun`, `passed`, `expectedFailures`, `unexpectedFailures`, or `acceptanceFailed`), `acceptanceFailures` gate names, category counts including `vic`, `sid`, `protectedMedia`, `cartridge`, and `app`, roadmap `phaseCounts`, per-phase pass/fail/skip `phaseBreakdown`, derived `phaseOutcomes` including `expectedFailureDrift`, per-phase failure and drift detail maps for phase-level progress dashboards, unclassified failure counts/details for unknown or generic emulator failures, tape-specific failures, cycle totals, the slowest milestone, failed milestone details with compact final PC/VIC beam, bus, and memory-trace diagnostics, and failed/skipped milestone keys. Add `SWIFT64_LOCAL_MILESTONE_PHASES` with comma-separated phase names to run only explicitly tagged milestones for those phases; untagged manifest milestones are excluded while a phase filter is active. Add `SWIFT64_LOCAL_MILESTONE_IDS` with comma-separated milestone IDs to run only named manifest milestones after any phase filter, and add `SWIFT64_LOCAL_MILESTONE_REQUIRE_IDS_MATCH=1` when missing requested IDs should fail the aggregate run. Add `SWIFT64_LOCAL_MILESTONE_SHARD_COUNT=N` and zero-based `SWIFT64_LOCAL_MILESTONE_SHARD_INDEX=I` to run a deterministic shard after phase/ID filtering; invalid shard settings become acceptance failures. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_MANIFEST=1` when a strict run must fail unless `C64/DISKS/compatibility.json` is present instead of relying on fallback discovery. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_PHASES=1` when a phase-filtered run should fail if any selected valid phase has no matching milestone. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_ROADMAP_PHASES=1` when a strict corpus run should fail if any manifest milestone lacks an explicit `roadmapPhase`. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_IDS=1` when dashboards/resume history should reject manifest milestones without stable explicit IDs. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_EXPECTED_FAILURE_NOTES=1` when every manifest `expectedFailure` waiver must include a non-empty `note`, and `SWIFT64_LOCAL_MILESTONE_REQUIRE_EXPECTED_FAILURE_REASONS=1` when every waiver must include at least one non-empty `reasonContains` marker. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_MAX_CYCLES=1` when every manifest milestone must declare its own cycle budget. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_ACTIONS=1` when every manifest milestone must use an explicit `actions` script instead of legacy command fallback. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_OBSERVABLES=1` when every manifest milestone must assert at least one observable machine/media state instead of only running actions for a cycle budget. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_FRAMEBUFFER_SCREENSHOTS=1` when every manifest milestone with a `framebufferHash` must also declare a non-empty `screenshotName` and avoid sanitized screenshot filename collisions for opt-in frame capture/debugging. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_MEDIA_TYPES=prg,d64,g64,t64,tap,crt` when a strict corpus contract must cover specific manifest media types; invalid names and missing required media types become acceptance failures. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_MACHINE_PROFILES=palC64,ntscC64,palC64C,ntscC64C` when a strict corpus contract must cover specific machine profiles; invalid names and missing required profiles become acceptance failures. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_DRIVE_MODES=fastLoad,compat1541,standard1541` when a strict corpus contract must cover specific drive modes; invalid names and missing required drive modes become acceptance failures. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_SID_MODELS=mos6581,mos8580` and `SWIFT64_LOCAL_MILESTONE_REQUIRE_SID_ACCURACY_MODES=fast,compatibility` when a strict SID corpus contract must cover specific chip and accuracy-mode settings; invalid names and missing required SID settings become acceptance failures. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_OBSERVABLE_TYPES=drive,sid,vic,framebuffer` when a strict corpus contract must cover specific proof categories; accepted names are `pc`, `drive`, `media`, `lowLevelTrack`, `tape`, `ram`, `colorRAM`, `cpu`, `sid`, `vic`, `cia`, `screen`, and `framebuffer`. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_VIC_PROOFS=registers,state,raster,bus,memoryTrace,framebuffer` when a strict Phase 3 corpus contract must cover specific VIC proof surfaces; invalid names and missing required proof types become acceptance failures. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_FAILURE_CATEGORIES=drive,sid,vic` when a strict corpus contract must cover expected-failure categories for known regressions; accepted names are canonical failure categories such as `cpu`, `vic`, `sid`, `drive`, `media`, `protectedMedia`, `cartridge`, `app`, `pc`, `ram`, `screen`, `tape`, `cia`, `emulator`, and `timeout`. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_ACTION_TYPES=typeText,waitCycles,joystickDown,startTape` when a strict corpus contract must cover specific scripted interaction types; accepted names are `typeText`, `waitCycles`, `joystickDown`, `joystickUp`, `keyDown`, `keyUp`, `startTape`, and `stopTape`. Add `SWIFT64_LOCAL_MILESTONE_REQUIRE_ALL_MEDIA=1` for strict preservation runs that should fail immediately when selected `compatibility.json` entries reference media that is not present in the bounded local selection, add `SWIFT64_LOCAL_MILESTONE_FAIL_ON_UNCLASSIFIED=1` for runs that should fail whenever a milestone lands in the unknown/generic emulator bucket, and add `SWIFT64_LOCAL_MILESTONE_FAIL_ON_UNEXPECTED=1` to fail on any failure that is not matched by manifest `expectedFailure` metadata. Add `SWIFT64_LOCAL_MILESTONE_FAIL_PHASES` with comma-separated phase names to fail selected roadmap phases only when they have unexpected, drifted, unclassified, or generic failure outcomes; accepted names are `phase2CPUMemoryBus`, `phase3VICII`, `phase4DriveMedia`, `phase5SID`, `phase6CIAInputTape`, `phase7CartridgeExpansion`, and `phase8AppDistribution`, and invalid names are reported as acceptance failures:

For strict Phase 3 runs, `SWIFT64_LOCAL_MILESTONE_REQUIRE_PHASE3_VIC_PROOFS=1` requires each `phase3VICII` milestone to include the full VIC proof bundle: `registers`, `state`, `raster`, `bus`, `memoryTrace`, and `framebuffer`. This is stricter than whole-manifest proof coverage and is meant for declaring raster-demo/open-border/sprite-multiplex milestones genuinely proved rather than merely touched.

`C64/DISKS/compatibility.phase3-vic.example.json` is a tracked, media-free starter contract for real Phase 3 demo milestones: representative FLI, open-border, and sprite-multiplex references. Copy those entries into your local untracked `C64/DISKS/compatibility.json`, point `file` at locally owned demo images under `C64/DISKS`, run once with screenshot capture to calibrate `vicRegisterSnapshotHash`/`framebufferHash`, then remove the placeholder expected-failure waivers as each milestone becomes deterministic. `SWIFT64_LOCAL_MILESTONE_REJECT_PLACEHOLDER_PROOF_HASHES=1` fails strict runs when manifest proof hashes still use the all-zero template digest. A strict local Phase 3 pass should include these gates:

```sh
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_PHASES=phase3VICII SWIFT64_LOCAL_MILESTONE_REQUIRE_PHASE3_VIC_PROOFS=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_FRAMEBUFFER_SCREENSHOTS=1 SWIFT64_LOCAL_MILESTONE_REJECT_PLACEHOLDER_PROOF_HASHES=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-phase3-vic-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
```

`SWIFT64_LOCAL_MILESTONE_LIMIT=N` caps the post-shard milestone list before media lookup and execution. Aggregate summaries include `selectedMilestoneKeys` so dashboards can audit exactly which bounded milestones were planned for the run. Use `SWIFT64_LOCAL_MILESTONE_MEDIA_LIMIT=N` only when the media discovery scan itself needs a separate bound.
Duplicate manifest IDs and result keys are rejected before filtering and media lookup, so phase/shard/limit settings or missing local images cannot hide an invalid `compatibility.json` contract. Validation failures are also written to aggregate summaries as `manifestValidationErrors` when `SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON` is configured.
Use `script/run_milestone_shards.sh N` to run the local milestone matrix sequentially across `N` deterministic shards. It writes a shared resumable JSONL result log plus one aggregate summary JSON per shard under `.build/swift64-milestone-shards` by default, and it never starts more than one `swift test` process at a time.

```sh
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_RESULTS_JSONL=/tmp/swift64-milestones.jsonl SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_ALL_MEDIA=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_FAIL_ON_UNCLASSIFIED=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_FAIL_ON_UNEXPECTED=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_MANIFEST=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_PHASES=phase4DriveMedia SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_IDS=great-giana-sisters-title SWIFT64_LOCAL_MILESTONE_REQUIRE_IDS_MATCH=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_SHARD_INDEX=0 SWIFT64_LOCAL_MILESTONE_SHARD_COUNT=4 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_PHASES=phase4DriveMedia,phase5SID SWIFT64_LOCAL_MILESTONE_REQUIRE_PHASES=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_ROADMAP_PHASES=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_IDS=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_EXPECTED_FAILURE_NOTES=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_EXPECTED_FAILURE_REASONS=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_MAX_CYCLES=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_ACTIONS=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_OBSERVABLES=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_PHASE3_VIC_PROOFS=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_FRAMEBUFFER_SCREENSHOTS=1 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_MEDIA_TYPES=prg,d64,g64,t64,tap,crt SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_MACHINE_PROFILES=palC64,ntscC64,palC64C,ntscC64C SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_DRIVE_MODES=fastLoad,compat1541,standard1541 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_SID_MODELS=mos6581,mos8580 SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_SID_ACCURACY_MODES=fast,compatibility SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_OBSERVABLE_TYPES=drive,sid,vic,framebuffer SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_VIC_PROOFS=registers,state,raster,bus,memoryTrace,framebuffer SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_FAILURE_CATEGORIES=drive,sid,vic SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_REQUIRE_ACTION_TYPES=typeText,waitCycles,joystickDown,startTape SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_FAIL_PHASES=phase4DriveMedia,phase5SID SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON=/tmp/swift64-milestone-summary.json swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
```

To capture passing milestone framebuffers, set a screenshot output directory. Files are written as portable PPM images using sanitized `screenshotName` values from the manifest. Add `SWIFT64_LOCAL_MILESTONE_SCREENSHOT_FAILURES=1` to also save `-failed.ppm` captures for failed milestones that declare `screenshotName`:

```sh
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_SCREENSHOT_DIR=/tmp/swift64-screens swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
SWIFT64_LOCAL_MILESTONE_MATRIX=1 SWIFT64_LOCAL_MILESTONE_SCREENSHOT_DIR=/tmp/swift64-screens SWIFT64_LOCAL_MILESTONE_SCREENSHOT_FAILURES=1 swift test --filter LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled
```

The named milestone test has a built-in Great Giana Sisters G64 custom-loader progress checkpoint when that local file is present. You can override or add stricter PRG/D64/G64/NIB/NBZ/P64/T64/TAP/CRT screen, color RAM, RAM, drive, media, and one-or-more-PC-range milestones with an untracked `C64/DISKS/compatibility.json` file. Add `roadmapPhase` when a milestone is meant to prove a specific completion phase, using one of `phase2CPUMemoryBus`, `phase3VICII`, `phase4DriveMedia`, `phase5SID`, `phase6CIAInputTape`, `phase7CartridgeExpansion`, or `phase8AppDistribution`; when omitted, the runner derives a phase from the result category. The runner rejects duplicate non-empty milestone IDs and duplicate result keys (`id`, file, command/action summary, machine profile, drive mode) before executing the local corpus, so resumable logs cannot accidentally treat two milestones as one. Known regressions can be kept in the corpus with an `expectedFailure` object containing a subsystem `category`, optional `reasonContains` string/list, and optional `note`; the runner still records the milestone as failed, but does not fail the XCTest slice unless the actual failure category or reason markers change.

For the Great Giana Sisters G64 sound/reset regression, capture the chip-visible SID write stream after the first start screen by running the focused smoke test with the bounded JSONL SID trace enabled. The smoke test presses Space after the first screen change and continues into the second screen where the music starts; `SWIFT64_LOCAL_GIANA_SID_TRACE_LIMIT` bounds the trace so it stays manageable:

```sh
SWIFT64_LOCAL_GIANA_RUN_SMOKE=1 \
SWIFT64_LOCAL_GIANA_CONTINUE_AFTER_SCREEN_CHANGE=1 \
SWIFT64_LOCAL_GIANA_PRESS_SPACE_AT_PC=0x0AB9 \
SWIFT64_LOCAL_GIANA_PRESS_SPACE_AT_PC_MIN_CYCLES=3000000 \
SWIFT64_LOCAL_GIANA_SID_MODEL=mos6581 \
SWIFT64_LOCAL_GIANA_SID_ACCURACY=compatibility \
SWIFT64_LOCAL_GIANA_SID_TRACE_JSONL=/tmp/swift64-giana-sid.jsonl \
SWIFT64_LOCAL_GIANA_SID_TRACE_LIMIT=50000 \
SWIFT64_LOCAL_GIANA_WAV_CAPTURE=/tmp/swift64-giana.wav \
SWIFT64_LOCAL_GIANA_WAV_CAPTURE_SECONDS=8 \
SWIFT64_LOCAL_GIANA_STOP_AFTER_WAV_CAPTURE=1 \
SWIFT64_LOCAL_GIANA_RUN_MAX_CYCLES=12000000 \
swift test -c release --filter LocalDiskMatrixTests/testLocalGreatGianaSistersRunSmokeWhenEnabled
```

Replay `/tmp/swift64-giana-sid.jsonl` through the clean-room `SIDRegisterTracePlayer` to isolate SID synthesis from CPU/VIC/CIA/1541 timing. If the replayed chip-visible stream still sounds wrong, the remaining work is inside SID waveform/envelope/filter/output behavior; if the trace is sparse, missing writes, or includes unexpected banked-out writes, the problem is upstream in timing, banking, loader state, or drive behavior. Set `SWIFT64_LOCAL_GIANA_SID_TRACE_INCLUDE_RAM=1` only when you need to inspect `$D400-$D7FF` writes that happened while I/O was banked out. The optional WAV capture writes bounded mono 44.1 kHz output from the emulator's SID sample path after real voice/filter output begins; WAV export and app playback are AC-coupled so large SID DC offsets do not swamp or clip the audible signal, while SID debug state still reports raw internal mixer values. Use the WAV for A/B listening against external references without storing reference audio in the repo. `SWIFT64_LOCAL_GIANA_WAV_CAPTURE_AFTER_CHIP_WRITES` defaults to `3`, which skips the two early Kernal `$D418=00` writes. `SWIFT64_LOCAL_GIANA_WAV_CAPTURE_START=chip-writes` can restore the earlier setup-phase capture, but the default `voice-output` mode avoids recording only SID volume/DC output before the tune is active. The optional `SWIFT64_LOCAL_GIANA_PRESS_SPACE_AT_PC` trigger is useful when screen-RAM changes happen before the actual first-start-screen key loop.

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
      "id": "great-giana-sisters-title",
      "name": "Great Giana Sisters title screen",
      "file": "great_giana_sisters[time_warp_1987](pal)(r1)(!).g64",
      "mediaType": "g64",
      "roadmapPhase": "phase4DriveMedia",
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
        "minGCRWrites": 0,
        "minGCRWriteSplices": 0,
        "minGCRWriteEraseBits": 0,
        "requiredVariableSpeedZones": [0, 3],
        "hasNativeLowLevelImage": true,
        "gcrWriteModeActive": false,
        "headBitPosition": 0,
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
        "preservesWeakBitRanges": false,
        "sectorErrorCodeCount": 0,
        "nonDefaultSectorErrorCodeCount": 0,
        "weakBitRangeCount": 0,
        "weakBitTotalBitCount": 0,
        "variableSpeedZoneByteCount": 0,
        "supportsWraparoundReads": true,
        "maxTrackSize": 7928,
        "unsupportedFeaturesContains": ["Weak/random bits"]
      },
      "lowLevelTracks": [
        {
          "halfTrack": 34,
          "byteCount": 7928,
          "bitLength": 63424,
          "speedZone": 3,
          "bytesHash": "optional-fnv1a64-track-byte-hash",
          "speedZoneMapHash": "optional-fnv1a64-speed-map-hash",
          "weakBitRangeCount": 0
        }
      ],
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

When `actions` is omitted, the runner converts `commands` into cycle-0 typed text actions. Explicit actions can type text, wait a fixed number of C64 cycles, press/release joystick controls (`up`, `down`, `left`, `right`, `fire`), press/release named C64 keys such as `space`, `return`, `runStop`, `restore`, cursor keys, and function keys, and control TAP playback with `startTape`/`stopTape`. `screenTextContains` checks decoded screen RAM text without requiring a brittle full-screen hash; `screenRAMHash`, `colorRAMHash`, and `framebufferHash` can pin text RAM, color RAM, or the rendered VIC framebuffer for deterministic raster-demo proof without committing screenshots. Screen, framebuffer, low-level track byte, and speed-map hash expectations must be 16-character FNV-1a hex digests, so typoed proof hashes fail during manifest validation instead of becoming impossible milestones. `cpuRegisters` checks PC/A/X/Y/SP/P state with an optional `pMask`; `sidRegisters`, `sidVoiceStates`, `vicRegisters`, `vicRegisterSnapshotHash`, and `cia1Registers`/`cia2Registers` check effective chip register state with optional masks for audio/video/timer milestones, while `vicRasterLine`, `vicRasterCycle`, `vicBALineLow`, `vicAECLineLow`, `vicBusOwner`, `vicBusPhase`, `vicLowPhaseAccess`, and VIC high-/low-phase memory-read lists, including explicit empty lists when no read is expected, assert exact final beam and bus-stealing state for raster-split and loader-timing proof. SID register milestones default to debugger/effective register state and can opt into `"readMode": "chip"` for non-mutating readable-register comparisons such as sampled OSC3/ENV3. SID voice-state milestones can assert raw oscillator output, signed post-envelope waveform output, raw envelope counter values, sustain threshold, selected ADSR rate period, model-shaped envelope DAC output, waveform DAC latch state, decoded control flags, oscillator/noise edge flags, oscillator counters, and envelope counters without storing audio blobs; SID audio-state milestones can also assert SID sample scheduler position, cycles-per-sample timing, the SID-local bus latch and decay countdown, sampled OSC3/ENV3 latch values and validity flags, POTX/POTY scan state, plus the last direct-output, filter-input, filter-output, mixed-output, raw external-input, and model-shaped external-input integers to separate timing, bus, paddle, routing/filter/input, and output-stage drift. `tapeStatus` checks mounted tape names, TAP decode diagnostics (`none`, `rawPulsesOnly`, `decodedPrograms`, `standardCBMNoPrograms`), raw TAP playback, cassette read/sense/motor lines, and tape export/dirty state. This lets local milestones cover title screens, loader prompts, CPU handoff points, basic SID/VIC/CIA initialization, and datasette signal milestones without custom test code.

## SID filter calibration

`SIDFilterCalibrationTests` (12 ROM-independent cases) pins the measurement-derived filter model in `SID.swift`: the per-model cutoff tables hit their published anchors and stay monotonic; the low-pass, high-pass and band-pass responses are measured cycle by cycle with sine drives at FC 512/1024/1536 (6581) and 256/1024/2047 (8580); band-pass gain at the cutoff equals the model Q for RES 0/8/15 on both chips; FILT1-3/FILTEX route exactly one source each; the 6581 chip-range parameter rescales the curve on its 220 Hz floor and survives reset and snapshots; the 6581 compatibility path raises its cutoff with level and carries routed-voice DC through the low-pass but not the high-pass; the board output network has its 16 kHz / 16 Hz corners; fast mode skips every compatibility-only stage. Run with the SID suites:

```sh
swift test -c release -j 2 --filter 'SIDFilterCalibrationTests|SIDTests|SIDAudioQualityTests|MachineStateTests'
```

### Calibration record: 2026-10-18

What the filter now derives from published data, and from which source:

| Quantity | Model | Source |
| --- | --- | --- |
| 6581 cutoff vs FC | 14 anchors from 220 Hz (FC 0) through 420 Hz (512), 1.6 kHz (768), 5.3 kHz (1024), 9.5 kHz (1280), 14.5 kHz (1536) to 18 kHz (2047), interpolated linearly in log frequency | Dag Lem's documented measurement of a 6581 R4AR with 470 pF capacitors (reSID 0.16 documentation), corroborated by the reSIDfp documentation's measured 220 Hz minimum; the datasheet's "linear" 30 Hz-12 kHz is the design intent, not 6581 behaviour |
| 6581 chip spread | `SID.filterMaximumCutoff6581` (8-20 kHz, default 18 kHz) rescales the log curve while FC 0 stays at 220 Hz | Published 6581 curves top out between about 8.6 kHz and above 20 kHz; the 6581 temperature drift and the measured FC-DAC step at FC 1024 (6.0 to 4.6 kHz on the reference chip) are not modelled |
| 8580 cutoff vs FC | 10 anchors, linear interpolation: 30 Hz floor, 800 Hz (128), 3.3 kHz (512), 6.5 kHz (1024), 9.8 kHz (1536), 12.5 kHz (2047) | Same reSID 0.16 documentation ("closely matches a linear mapping"), datasheet nominal 30 Hz-12 kHz and 11-bit linear control; the measured floor is near 0 Hz, the datasheet floor is used so the integrators never freeze |
| Integrator coefficient | 2 sin(pi f / fclk) per SID clock, so the two-integrator loop resonates at the table frequency on PAL and NTSC clocks | Two-integrator biquad topology confirmed by the chip designer; the coefficient is the exact digital mapping, not a measurement |
| Resonance | 1/Q linear in RES from sqrt 2 (Q 0.707, RES 0) to 1/1.7 (6581) or 1/4 (8580) at RES 15 | 6581: published "approximate range [0.707, 1.7]" and "1/Q controlled linearly by res". 8580: **no published numeric measurement was found**; Q 4 at RES 15 is a model parameter chosen to reproduce the widely reported stronger 8580 peak |
| 6581 level-dependent cutoff | Compatibility mode only: the cutoff rises by up to 60 % with the tracked magnitude of the low-pass integrator (5 ms tracker) | Published descriptions agree the 6581 cutoff drifts upward with signal level (FET voltage-controlled resistors, self-biased NMOS-inverter op-amps); **the gain and time constant are model parameters** |
| 6581 filter-input DC | Compatibility mode only: each voice routed into the filter adds -1/54 of one voice's range | Published mixer measurement: zero-level output 5.50 V at volume 0 versus 5.44 V at volume 15, about -1/18 of one voice's 1.05 V range in total; **splitting it evenly over three voices is this project's assumption**. "No DC offsets in the MOS8580" |
| Output stage | Linear, clamped at the rails, both models | Datasheet: open-source AUDIO OUT buffer into a 1 kOhm load, about 3 V peak-to-peak at 6 V DC. Published analyses place the 6581's audible nonlinearity in the filter and describe the 8580 output as near-ideal, so the previous asymmetric soft-clip (which had no measurement basis) is removed |
| Board output network | Compatibility mode only, both models, per cycle: 10 kOhm / 1000 pF low-pass (15.9 kHz) buffered into 1 kOhm / 10 uF high-pass (15.9 Hz) | C64 board component values as documented with the reSID external-filter description; the unity-gain BJT between the stages is treated as ideal. This replaces the earlier per-sample 0.90 / 0.96 smoothing coefficients |

Still approximate after this change: the 8580 resonance endpoint, the magnitude and dynamics of the 6581 level-dependent cutoff, the per-voice split of the 6581 DC, the EXT IN gains (1.12 / 0.72), the volume-DAC offset tables (their 6581 step is about 5 % of full scale where the published figure is nearer 2 %), temperature drift, and the FC-DAC nonlinearity. No chip was measured for this work and no emulator implementation code was used; the anchors above are the published numbers, the interpolation and scaling are ours. This is a measurement-derived model, not preservation-grade calibration of any particular chip.

Measured checks (Release, fast mode, cycle-driven sines, RMS after settling): at RES 0 both chips give 0.707 +/- 0.04 at the table cutoff, 1/sqrt 17 one octave above it (low-pass) or below it (high-pass), and unity gain two octaves into the passband, at every tested FC value. Band-pass gain at the cutoff is 0.71 / 1.03 / 1.70 (6581) and 0.71 / 1.26 / 4.00 (8580) at RES 0 / 8 / 15, within 6 % of the model Q. With a 24,000-unit drive one octave above the cutoff, the 6581 compatibility path passes more than 10 % more energy than fast mode while the 8580 paths agree within 0.2 %. The board network gives 0.707 at 15.9 kHz and 15.9 Hz, unity at 1 kHz, and below 0.3 at 4 Hz. Save states round-trip the chip-range parameter, the tracker and both network states.

Tests changed because they pinned the replaced approximation: `SIDAudioQualityTests.testFilterAndEnvelopeLookupTablesPreserveTheAnalogApproximation` became `...MatchTheirDocumentedCurves` (envelope table unchanged, cutoff table now checked against the documented interpolation); in `SIDTests` the output-stage, analog-profile, sample-smoothing, filter-input and resonance/cutoff pins now assert the new model, and the compatibility-signature test no longer requires compatibility mode to be louder; two literal cutoff/damping values in `LocalDiskMatrixTests` now read the live SID. The known-tone pitch/headroom, fast-versus-cycle filter response, original three-voice program, and speaker-path tests in `SIDAudioQualityTests` are unchanged. `SID.snapshotStoredPropertyCount` is 46 (board network low/high-pass state, level tracker, chip-range parameter, derived table); the unreleased SID snapshot chunk layout changed accordingly.

Scoreboards. Public SID runner (`PublicSIDConformanceTests`, sequential Release, the 11 pinned programs; none exercises the filter, and `extfilt.prg` is keyboard-driven so it cannot run in the runner): before this change **5 of 11 pass** (envrate, envdelay, envsustain, envtime, noisetest; the four `oscsample` and two `osc3-wave0` programs report `$FF`), in 499.2 seconds. After this change **5 of 11 pass with identical per-program results** (same completion cycles and PCs for all 11 programs), in 508.5 seconds; the oscillator-sample and OSC3 failures predate this work and are not filter-related. `SIDFilterCalibrationTests|SIDTests|SIDAudioQualityTests|MachineStateTests` before the change ran 170 tests with one opt-in skip and no failures (the 12 new cases did not exist yet); after the change **183 tests, one opt-in skip, zero failures** in 27.4 seconds. The broader checked Release slice after the change (`CPU6502Tests|MemoryMapTests|SIDAudioQualityTests|SIDTests|SIDFilterCalibrationTests|MachineStateTests|C64TimingTests|VICTests|VICSlotTimingTests|VICSpriteFetchTests|VICSpriteDMALifecycleTests|VICPriorityTests|CIATests|Drive1541Tests|KernalTrapsTests|CompatibilityManifestTests|LocalDiskMatrixTests|SIDRegisterTraceTests`) executes **993 tests: 978 pass, 18 opt-in skips, 15 failures in six `LocalDiskMatrixTests` cases** (`testMilestoneResultLogRoundTripsPassedEntriesForResume`, `testMilestoneRunSummaryWritesAggregateJSON`, `testNamedMilestoneCanMatchCIARegisters`, `testNamedMilestoneCanMatchVICBusState`, `testNamedMilestoneCanMatchVICState`, `testNamedMilestoneRequiresVICBusState`). Those six cases fail with the same 15 assertions on a clean checkout of the parent commit `9ad3717` (CIA `$DC04` value, VIC bus phase and line-buffer base, milestone summary JSON, sprite-pointer idle state), so they are pre-existing and unrelated to the SID; the SID audio-state milestone cases in the same file pass. No VIC or CIA code is touched; those runners were not rerun.

### Oscillator readback fixes from the public SID programs: 2026-10-18

The six public programs that failed before and after the filter calibration (`oscsample0/1-6581`, `oscsample0/1-8580`, `osc3-wave0-6581/8580`) were traced cycle by cycle against their included hardware dumps. Three defects, all in the oscillator path, none in the filter:

- The pulse comparator special-cased PW 0 as constant low and PW $FFF as constant high. The `osc3-wave0` program, verified on a C64 with a 6581 and a C64C with an 8580, reads OSC3 as $FF for PW 0 and $00 for PW $FFF at phase 0. The comparator now outputs all ones whenever the top 12 accumulator bits are at or above the pulse width, with no special cases.
- The `oscsample1` dumps (FREQ $1000, PW $100) place the 6581's rising pulse edge one cycle after the sawtooth reaches $100, while the 8580's edge is in the same cycle. The 6581 pulse comparator now works from the previous cycle's phase (`Voice.previousPhase`, re-latched by direct accumulator writes, sync and TEST resets, and carried by save states); the 8580 compares the current phase. The behaviour in the cycle of a sync reset is a model choice, not measured.
- A voice with no waveform selected kept its floating DAC value for 128 cycles and then drained it within about 8 ms. `osc3-wave0` requires the value to persist immediately after the waveform is cleared and to decay to zero within 256 PAL frames on the 6581; the `-new` variant allows 1,536 frames on the 8580. The leak step is now 12,000 cycles on the 6581 (full scale drains in about 2.2 s) and 150,000 on the 8580 (about 15 s). The decay curve itself is not measured; the public program only bounds its duration.

Before the fixes, all four `oscsample` programs matched the triangle and sawtooth dumps exactly on both chips and failed only on pulse; after them the pulse dumps match on both chips for PW 0 and PW $100. The combined-waveform dumps (`wf30`-`wf70`) still differ, and the readme states they contain chip-dependent bits and are not part of the pass criterion. The noise dumps (`wf80`) differ from the first sample onward on both chips, which the pass criterion does count; see the scoreboard below. Three ROM-independent regressions cover the pulse levels at phase 0, the 6581/8580 edge timing against the sawtooth, and the complete `osc3-wave0` sequence with its decay windows; the floating-DAC settle test now runs three million cycles.

Public SID runner after these fixes (sequential Release, 555.7 seconds): **7 of 11 pass**. `osc3-wave0-6581` passes after 2,260,486 cycles and `osc3-wave0-8580` after 14,270,303; the five envelope/noise programs are unchanged. The four `oscsample` programs still report `$FF`, now only because of their noise dump. `SIDFilterCalibrationTests|SIDTests|SIDAudioQualityTests|MachineStateTests|CompatibilityManifestTests|SIDRegisterTraceTests`: **224 tests, one opt-in skip, zero failures** in 36.2 seconds.

What the noise dumps show, for the next step: the program samples OSC3 in eight interleaved runs, each starting with TEST held for two frames and then released with the noise waveform at FREQ $1000, so the LFSR shifts every 256 cycles. In the hardware dumps the first run (after the program's 12-million-cycle TEST hold) reads `$FE`, `$FC`, `$F8`, `$F0`, `$E0`, `$C0` at exactly the shift counts where zeros fed into bit 0 reach output taps 0, 2, 5, 9, 11 and 14 of an otherwise all-ones register. Runs two to eight read different pseudo-random sequences from their first sample onward, so a two-frame TEST hold does not return the register to that state; each run continues from where the previous one left it, modified by whatever TEST does in 39,312 cycles. Swift64 resets the register to zero under TEST and produces `$FE` for every run. Reproducing the dumps needs the slow TEST-hold behaviour of the shift register on both chips; that is not attempted here.

### Noise shift register under TEST from the public SID programs: 2026-10-18

Recorded 2026-10-18 (development validation), after the oscillator readback fixes above. The four `oscsample` noise dumps (`oscsample0/1-6581wf80.dat`, `oscsample0/1-8580wf80.dat`) and the `noisetest.a65` source were decoded without consulting any emulator; everything below is derived from them, and the remaining free parameters are named as such.

What the dumps contain. Each file is a 2-byte load address and 4096 bytes; sample index `i` belongs to delay run `r = (i - skip) mod 8`, where `skip` is 4 on the 6581 and 3 on the 8580 (the program's chip probe decides the layout). With that per-chip layout the four files hold the same eight run sequences, so both chips behaved identically on the author's machines. Each run is 512 OSC3 reads 8 cycles apart with FREQ `$1000`, so the register shifts every 256 cycles, first at read 16 (delays 0-5) or read 15 (delays 6-7). Reconstructing each run's 23-bit state from its 16 observed shifts (exhaustive search over 2^23 states, one solution per run) with the output mapping of `noisetest` (register bits 20, 18, 14, 11, 9, 5, 2, 0 drive output bits 11 to 4) gives, after the first accumulator-driven shift, `$7FFFFC` for run 1 and `$1E6F05`, `$10A55A`, `$40EB0E`, `$5DDEDD`, `$2111F3`, `$53F9F7`, `$2991F9` for runs 2-8. Every run-to-run transition is then exactly 247 ordinary shifts (bit 0 = bit 22 XOR bit 17), one shift with bit 0 = NOT bit 17, and one ordinary shift: the 15 remaining shifts of the run, about 232 shifts while the program generates the next run's code, the TEST release, and the next run's first accumulator shift. Run 1 starts from all ones followed by that same release shift (`$7FFFFE` reads `$FE`).

Derived behaviour, now modelled in `SID.swift`:

- A TEST hold freezes the register: the two-frame holds between runs (34,678 to 38,801 cycles in the emulated program) leave all 23 bits intact on both chips. Only a long hold pulls every bit to one; the programs' 23.6-million-cycle initial hold ends at all ones. `noiseShiftRegisterResetCycles` is 0x100000 (6581) and 0x1000000 (8580), inside the window the dumps and the source comment (`on 8580 it takes MUCH longer`) leave open; the exact times, and whether bits drift individually, are not measured, so these are model parameters. The `oscsample` source expects the 6581 to clear within `$2000-$4000` cycles, but its own dump, verified on the 6581 C64, shows the register surviving two frames; Swift64 follows the dump. The register starts at all ones after reset.
- The TEST release clocks the register once with TEST ORed into the bit-22 feedback input, i.e. bit 0 = NOT bit 17. This is the rule `noisetest` itself emulates and verifies against both chips for 256 short pulses; the `oscsample` transitions show the same single shift after a two-frame hold. Setting TEST does not shift (`noisetest` reads OSC3 unchanged right after setting it), so a noise-only voice stays readable under TEST and its frozen value is what OSC3 returns. The old reset-to-`$7FFFF8` model passed `noisetest` only because the old output taps (22, 20, 16, 13, 11, 7, 4, 2) are the `noisetest` taps relabelled by two shifts; against the `oscsample` transitions that labelling needs three shifts per release and then contradicts `noisetest`, so the taps now follow the program.
- The shift lands after a short pipeline: the runs with delays 5 and 6 straddle the first post-release shift on both chips, which puts the OSC3 change in the same cycle on both. Relative to each chip's own readback this is two cycles after the bit-19 edge on the 6581 and one on the 8580 (`noiseShiftPipelineCycles(for:)`); an edge still in the pipeline when TEST is set is dropped (model choice). The 6581 combined-noise ageing now clears the new tap bits (that ageing remains a model).
- The program's chip probe (`sidver`: TEST, FREQ `$4000`, sawtooth, OSC3 read four cycles later) reads `$01` on a 6581 and `$00` on an 8580; the source calls this the 8580 waveform being delayed one cycle. Swift64 read `$00` for both chips, so the 6581 programs had been storing their samples in the 8580 layout, and the noise runs were compared one slot apart. The 6581 OSC3 readback now samples after the cycle's oscillator clock, the 8580 before it (`tick`); the previous session's pulse-edge finding (6581 pulse one cycle after its sawtooth, 8580 same cycle) is unchanged because it compares waveforms within one chip, and the triangle, sawtooth and pulse dumps still match exactly in the corrected layout. ENV3 sampling is unchanged.

Seven ROM-independent regressions in `SIDNoiseTestBitTests` cover the long-hold threshold per model, the two-frame hold with the readable frozen register and the release shift, the `noisetest` short-pulse sequence, the first `oscsample` run (`$FE`, `$FC` from the 2nd shift, `$F8` from the 5th, `$F0` from the 9th, `$E0` from the 11th, `$C0` from the 14th), the second run continuing from the register carried through the hold (`$48`, then `$FB`), the pipeline length per model, and the hold counter in save states; `SIDTests` gains the per-model OSC3 sample point and the chip probe. Save states carry the two new voice fields.

Public SID runner after these changes (sequential Release, 390.8 seconds): **11 of 11 pass**. Before them the same runner recorded 7 of 11 with the four `oscsample` programs failing only on their noise dump; the noise dumps now match on all four programs and `noisetest` still passes. The combined-waveform dumps (`wf30`-`wf70`) still differ, and the program excludes them from its verdict: in the corrected layouts the scratch harness counts 2,810 / 3,552 / 3,644 / 2,292 mismatching samples of 4,096 on the 6581 for `wf30`/`wf50`/`wf60`/`wf70` and 3,645 / 3,945 / 3,892 / 3,654 on the 8580. `SIDTests|SIDAudioQualityTests|SIDFilterCalibrationTests|MachineStateTests|CompatibilityManifestTests|SIDNoiseTestBitTests`: **233 tests, one opt-in skip, zero failures** in 30.0 seconds. The harness that dumped `$C000-$CFFF` per waveform and logged the register around every TEST write is not committed.


## Public CIA conformance runner

Recorded 2026-10-17 (development validation). The opt-in runner `PublicCIAConformanceTests` executes the `exitcode` programs of the CIA section in the pinned [VICE test-program collection](https://github.com/libsidplayfp/VICE-testprogs/tree/ef8e8efe52f3d43df7acefad132c6506239bddee/CIA), the same revision used by the VIC and SID runners. `script/fetch_cia_testprogs.sh` makes a blobless sparse checkout of only the `CIA/` directory under ignored `.build/cia-testprogs`; no programs, hardware dumps, ROMs, or emulator implementation code are committed. Every program boots through BASIC `RUN` on one fresh C64, is never patched, and reports its own verdict by writing `$00` or `$FF` to the testbench port at `$D7FF`; completion is detected exactly like the VIC runner (a write-watchpoint with I/O mapped), never by scanning the PC. The three upstream `interactive` programs (`ciaports`, `ghosting`, `transactor/ciatest64`) need key presses and are excluded. Upstream cycle timeouts are used unchanged.

```sh
sh script/fetch_cia_testprogs.sh
SWIFT64_PUBLIC_CIA_TESTPROGS_DIR=.build/cia-testprogs \
  swift test -c release -j 2 --filter PublicCIAConformanceTests
```

`SWIFT64_PUBLIC_CIA_TEST_IDS` selects a comma-separated subset (IDs are the upstream file stems with a `-pal`/`-ntsc` suffix, e.g. `cia3-pal,cmp-b-counts-a-old-ntsc`). `SWIFT64_PUBLIC_CIA_RESULTS_FILE` writes a tab-separated scoreboard (status, upstream CIA tag, cycles, `$D7FF` value, final PC, border colour). `SWIFT64_PUBLIC_CIA_TEST_MAX_CYCLES` caps every timeout, and `SWIFT64_PUBLIC_CIA_ROM_DIR` overrides the ROM directory. Without the fixtures directory the opt-in case skips; two small always-on cases check the fixture table and the screen decoding. Failing programs print their screen rows and a mask of cells coloured red/light red, which several programs use to mark mismatches.

The upstream `cia-old`/`cia-new` tags are kept as metadata: Swift64 has a single 6526 model, so both variants of each pair run and the scoreboard shows which revision current behaviour matches. The fourteen `*-sdr-icr-4485-*` programs that upstream marks `expect:error` (they only pass on the 6526 batch stamped 4485, twelve of the fourteen) are run and recorded but their `$FF` is not asserted; the two `4485-0` programs upstream does not mark are asserted normally.

Measured sequential Release results (2026-10-17): **143 programs complete, none time out or jam; 53 pass, 78 fail, 12 upstream-expected failures**, in 2,102 seconds for the single opt-in case. The run was repeated once with the final runner (all three cases, 2,051 seconds) with identical per-program status, `$D7FF` value, cycle count, and final PC. Every program completed through its own completion write; this is the baseline before any CIA fix, not a certification. Grouped results:

| Group | Pass | Fail | Notes |
| --- | --- | --- | --- |
| `CIA-AcountsB` (PAL+NTSC) | `cia-b-counts-a`, `cmp-b-counts-a-old` on both profiles | `cmp-b-counts-a-new` on both profiles | Timer B counting Timer A underflows matches the old 6526 dump; the 6526A dump differs at the first compared access. |
| `cia-timer` | none | `cia-timer-oldcias`, `cia-timer-newcias` | Only single boundary cells differ: the red mask marks one or two positions in rows 3, 4, 10 and 14, 15, 21 of the displayed reference, i.e. the ICR flag edge around underrun is one read position off in both the IRQ-disabled and IRQ-enabled blocks. |
| `ciavarious` (19) | `cia1`, `cia2`, `cia5`, `cia6`, `cia7`, `cia9`–`cia14`, `cia3new`, `cia3anew`, `cia4new`, `cia8new` | `cia3`, `cia3a`, `cia4`, `cia8`, `cia15` | The revision-dependent ICR-flag sub-tests (CIA3 K/L, CIA3A D/H, CIA4 X, CIA8 A/C/F/J/L) match the 6526A data, not the 6526 data. `cia15` fails its TOD sub-tests A–C. |
| `dd0drw`, `mirrors`, `pb6pb7` | all three | none | `STA abs,X` dummy-read acknowledge, 16-byte register mirrors, and PB6/PB7 timer-output control pass. |
| `dd0dtest` | – | `dd0dtest` | Tests 07–0B, 0F–11, 14–19 pass on screen; 0C, 0D, 0E, 12 and 13 fail: `INC $DD0D,X` and the related indexed/RMW reads acknowledge the NMI at the wrong cycle, so the expected `FF`/`81` entries read `01`. |
| `irqdelay` (16) | `irqdelay`, `irqdelay-oneshot`, `irqdelay2`, `irqdelay-cia1-4-old`, `irqdelay-cia1-oneshot-4-old`, both plain `cia1`/`cia2` and both `cia2-…-4` variants | all six `*-new` programs | IRQ delay matches the old 6526 (`irqdelay2` shows `0B 0B 0C 0C 0D` = 6526 row); the `-new` variants expect the 6526A row and `irqdelay2-new` writes the first mismatching index (`$0A`) to the port. |
| `reload0` | none | `reload0a`, `reload0b` | Timer low-byte reads after switching mode with the latch written while running differ from the hardware reference; `reload0b` marks nearly every timer-low cell of its top block red across all eight CRA configurations, so the “reload0” discrepancy is broader than the `$00/$11` cases the readme highlights. |
| `shiftregister` top level (13) | `cia-icr-test-continues-old`, `cia-icr-test-oneshot-old`, `cia-sp-test-continues-new`, `cia-sp-test-continues-old` | `cia-icr-test2-continues`, `cia-icr-test2-oneshot`, `cia-icr-test-*-new` (2), `cia-sdr-load`, `cia-sdr-init`, `cia-sdr-delay`, `cia-sp-test-oneshot-new`, `cia-sp-test-oneshot-old` | ICR tests match the old 6526. The SDR-empty flag is raised far too early: `cia-sdr-init` reads `$FE56` where hardware reads `$FCEA` (VICE `$FCF1`), `cia-sdr-load` `$FE57` vs `$FCEB`, and `cia-sdr-delay` shows the same ~364-cycle offset across all 21 delays. One-shot SP tests count 8 interrupts instead of the expected number; continuous mode passes. |
| `shiftregister/cia-sdr-icr` (44) | none | all 32 asserted programs (`cia1`/`cia2`, plain, `generic`, `4485-0`, `test2`) plus 12 upstream-expected failures | Every per-cycle ICR sample reads `$09` (TA and SP flags set) from the first sample, so neither the Timer A nor the SP flag shows the hardware progression. |
| `timerbasics` (6) | `test`, `timer`, `timer_new`, `timer_test1` | `test_new`, `timer_test1_new` | Timer read patterns match the old 6526 dumps; the 6526A dumps differ. |
| `tod` (30) | `alarm`, `alarm-cond`, `alarm-cond2`, `frogger`, `write-stop`, `read-latch`, `stability`, `stability-ntsc`, `hzsync0`, `hzsync2`, `hzsync5`, `hzsync6` | `0alarm`, `1alarm`, `4tod`, `4todcia1`, `5tod`, `6tod`, `fix-hour`, `fix-min`, `fix-sec`, `fix-tsec`, `hour-test`, `ampmtest`, `powerup`, `hammerfist0`, `hammerfist1`, `hzsync1`, `hzsync3`, `hzsync4` | Alarm compare at the current time works, but no alarm interrupt occurs when the clock is restarted at `00:00:00.0` against the default alarm (`0alarm`/`1alarm` count 0 of 40 alarms; `4tod`–`6tod` never see the NMI). Writing `12`/`92` to the hour register does not flip the AM/PM bit (`hour-test`, `ampmtest`). Invalid BCD digits are normalised on carry instead of counting as binary digits (`fix-*`). The clock is running at power-up instead of stopped at `01:00:00.0` (`powerup`), the Hammerfist alarm/reset probe prints `A` instead of `D`, and the 50/60 Hz divider is not reset by TOD writes where hardware resets it (`hzsync1`/`hzsync3` show 6 frames instead of 1–2) and is reset by frequency changes where hardware is not (`hzsync4` shows 7 instead of 3–4). Upstream notes `hzsync3`/`hzsync6` are not fully stable on hardware. |

Net of the revision pairs, 11 failures are `-new` variants whose `-old` twin passes and 4 are `ciavarious` `-old` variants whose `new` twin passes; the remaining 63 failures do not depend on the CIA revision. No CIA behaviour was changed in this session; the list above is the target for follow-up work. `swift build --build-tests -j 2`, `sh -n script/fetch_cia_testprogs.sh`, and `git diff --check` pass. Logs and scoreboards remain local in the session scratch directory.

### CIA defect fixes: 2026-10-17

Recorded 2026-10-17 (development validation), after the baseline above. Five changes, one commit each, all in `Sources/C64Core/CIA.swift` with ROM-independent regressions in `CIATests.swift` and `CIATimerPipelineTests.swift`. No test program or reference was modified. Where the upstream `cia-old`/`cia-new` pairs conflict, Swift64 now models the **old 6526 throughout** (the revision the C64's IRQ-delay and timer dumps already matched); the 6526A twins are expected failures and are listed as such below. Per-cycle diagnostics were taken with a throwaway harness that logged CIA register accesses with cycle stamps and dumped the programs' own result/reference tables; it is not committed.

1. **Serial shift register** (`847efab`). Timer A underflows alternate between output edges (a bit on SP, internal CNT falls) and rising CNT edges; a byte is 15 underflows and the SDR flag is raised four clocks after the eighth output edge (`cia-sdr-init` reads `$FCEA`, `cia-sdr-delay` the full `FCE6…FCE5` pattern). A byte written into an idle shifter reaches it on the next clock, so with latches 1 and 2 the first underflow passes before it; a second write while busy waits and starts on the underflow after the byte completes (`cia-sdr-load`); the shifter only clocks on edges of the underflow signal, so with latch 0 only the first underflow after a load shifts. Clearing CRA bit 6 mid-byte raises the flag once the shifter has run four clocks past its first edge and abandons the byte; setting it raises the flag when the internal CNT level is low (low from one clock after an output edge with a one-clock bounce high on the second, high from four clocks after a rising edge; after the final bit low from the third clock only) and drives CNT high. These rules reproduce both reference screens of every `cia-sdr-icr` program for all 128 latch values.
2. **ICR around underflow, old 6526** (`78cace8`). A timer flag that is enabled when raised arms the interrupt and the line asserts one clock later whatever the mask does in between (`cia-icr-test2` reads `$81` for Timer A = 9 although `$7F` was written in the clock before the assert); an ICR read in that clock cancels it. A Timer B flag raised in the same cycle as an ICR read is lost, although its interrupt still fires (`cia-timer` old dump: the handler reads `$80`; `ciavarious` cia3 K/L, cia3a D/H, cia4 X, cia8 A/C/F/J/L old data); Timer A keeps its flag.
3. **Timer reload from zero** (`d52d0b5`). A count arriving at a counter that is already zero is itself the underflow and does not swallow the following count, and the early reload of a zero counter does not swallow it when the counter was loaded with zero in the previous clock. A timer running with latch 0 therefore counts a newly written latch from the cycle after its reload (`reload0b`: a4 = b4 − 5, with the `$04/$02/$00` tail), while the normal reload-and-hold sequence (`timerbasics` `01 0C 0C 0B`) and the cascade/CNT tables are unchanged.
4. **Interrupt acknowledge for indexed and RMW reads** (`a93b223`). An ICR read clears the flags and drops the line at once but its IR bit is still returned by a read in the very next cycle (the dummy and real read of `INC $DD0D,X`, so the instruction writes `$80`/`$81` back and leaves the mask alone); an interrupt whose assert clock coincides with an ICR read does not assert the line and only leaves that IR bit for such a read; a mask write enabling a flag raised in the previous clock asserts through the one-clock delay; and a clear-mode ICR write in the clock a flag is raised prevents the interrupt (`dd0dtest` 11 and 17–19 versus 10). All 19 `dd0dtest` sub-tests pass.
5. **TOD hour register and digit counting** (`595be78`). Writing hour 12 flips AM/PM (`$12` stores `$92`, `$92` stores `$12`). The digits are binary counters with compare-based carries: ones digits carry at 9, the seconds/minutes tens digit wraps with carry only from 5, hours go 11 → 12 with an AM/PM flip and 12 → 1, and out-of-range digits count on through their width and wrap without carrying (`fix-hour` `$0F → $00`, `$19 → $1A`; `fix-sec` `$69 → $70`, `$79 → $00`).

Measured sequential Release results (2026-10-17, after the five commits): **143 programs complete, none time out or jam; 102 pass, 29 fail, 12 upstream-expected failures**, in 5,662 seconds for the three runner cases (the six auto-baud `cia-sdr-icr` programs now run through all 128 latch values, which is most of the added time). Before the batch the same runner recorded 53 pass / 78 fail / 12 expected. Scoreboard by group:

| Group | Before | After | Remaining failures |
| --- | --- | --- | --- |
| `CIA-AcountsB` (PAL+NTSC) | 4/6 | 4/6 | `cmp-b-counts-a-new` (both profiles): 6526A dump. |
| `cia-timer` | 0/2 | 1/2 | `cia-timer-newcias`: 6526A dump. |
| `ciavarious` (19) | 14/19 | 15/19 | `cia3new`, `cia3anew`, `cia4new`, `cia8new`: 6526A data (their old-data twins and `cia15` now pass). |
| `dd0drw`, `mirrors`, `pb6pb7`, `dd0dtest` | 3/4 | 4/4 | none. |
| `irqdelay` (16) | 10/16 | 10/16 | the six `-new` programs: 6526A IRQ timing. |
| `reload0` | 0/2 | 2/2 | none. |
| `shiftregister` top level (13) | 4/13 | 10/13 | `cia-icr-test-*-new` (2) and `cia-sp-test-oneshot-new`: 6526A. |
| `shiftregister/cia-sdr-icr` (44) | 0/32 | 32/32 | none asserted; the 12 `4485` programs remain upstream-expected failures (they pass only on the 4485 batch). |
| `timerbasics` (6) | 4/6 | 4/6 | `test_new`, `timer_test1_new`: 6526A dumps. |
| `tod` (30) | 12/30 | 18/30 | `0alarm`, `1alarm`, `4tod`, `4todcia1`, `5tod`, `6tod` (alarm on restarting the clock at the alarm time), `powerup` (clock running at power-up), `hammerfist0`/`hammerfist1` (print `A` instead of `D`), `hzsync1`/`hzsync3`/`hzsync4` (50/60 Hz divider reset rules). |

Net: the 17 remaining non-TOD failures are all upstream `cia-new` programs whose 6526 twin passes, i.e. the single-revision decision; the 12 TOD failures concern the alarm trigger on writes, the power-up state and the line-clock divider, none of which this batch touched. The previously passing 53 programs all still pass. `cia-sp-test-oneshot-old` passes and its `-new` twin fails, consistent with the revision model. The 12 `4485` programs are recorded, not asserted, as before.

Unit regressions added: `CIATests` `testSerialOutput*` (timing, small latches, queued byte, latch 0, mode-switch flag), `testTODHourWriteOfTwelveFlipsAMPM`, `testTODDigitsCountAsBinaryWithCompareCarries`; `CIATimerPipelineTests` `testMaskClearedDuringInterruptDelayStillAssertsInterrupt`, `testTimerBFlagRaisedInTheCycleOfAnICRReadIsLostButTimerAFlagSurvives`, `testNewLatchAfterZeroLatchRunCountsFromTheCycleAfterTheReload`, `testICRReadInArmClockBlocksLine`, `testConsecutiveICRReadStillSeesTheIRBit`, `testClearModeMaskWriteInFlagClockPreventsArming`. The checked `CIATests`/`CIATimerPipelineTests` slice runs **64 cases, zero failures** in Release. The public VIC runner, rerun in Release after the batch, is unchanged at **146 programs complete, 144 passing** in 608 seconds: only `videomode1-pal` (one pixel) and `modesplit-ntsc` (26 pixels) differ from their references, as before. `git diff --check` passes. Logs and the scoreboard stay local to the session scratch directory.

### CIA revisions: 6526 and 6526A/8521

Recorded 2026-10-17 (development validation), after the defect batch above. `CIA.Model` selects the chip revision: `.mos6526` (original C64 boards) or `.mos6526A` (the 6526A and the 8521 fitted to the C64C, which the public `cia-new` programs treat alike). `MachineProfile.ciaModel` sets it per board, so the C64C profiles now emulate the 8521 and the C64 profiles the 6526; `C64.ciaModelOverride` forces one revision for both CIAs, like the SID override, and the app exposes it as Settings > General > CIA Chips. The public runner now applies the upstream tag: `cia-old` programs run on the 6526, `cia-new` programs on the 6526A, untagged programs on the profile default.

Two behaviours differ, both taken from the upstream hardware dumps rather than from another emulator:

1. **No interrupt delay.** A timer flag that is enabled when raised asserts the line in the same clock (`irqdelay*-new`, `irqdelay2-new` expects the 6526A row). Enabling the mask for an already raised flag asserts at once instead of one clock later. An ICR read in the flag's clock happened before the flag: it returns the old value and does not acknowledge the new one, so the line still asserts and the next read returns the flag with IR. The `cia-timer` new dump pins this down in the columns where the underflow meets the first or second read: with the acknowledge-cancels-flag reading the handler never ran and the stale flag leaked into the next column's first read.
2. **No lost Timer B flag.** A Timer B flag raised in the clock of an ICR read is kept (`cia-timer-newcias` rows 2/3 show Timer B one column earlier than the old dump; `ciavarious` cia3new/cia3anew/cia4new/cia8new sub-tests).

The 6526 path is unchanged by construction: both branches are selected on `model`, and the old-tagged and untagged programs run on the same code as before.

Measured sequential Release results (2026-10-17): **143 programs complete, none time out or jam; 119 pass, 12 fail, 12 upstream-expected failures**, in 5,430.8 seconds for the single opt-in case. The nineteen `cia-new` programs: all seventeen that failed in the batch above now pass, and the two that already passed still do, so the 19 `cia-new` programs are all green; the 102 programs that passed before are unchanged. The remaining failures are the twelve TOD programs listed in the batch above; none depends on the revision. The public VIC runner was not rerun for this change: no VIC fixture selects a C64C profile, and the 6526 code path is untouched.

Unit regressions added: `CIATimerPipelineTests.test6526AAssertsInTheFlagClockAndKeepsTimerBFlagOnSameClockRead` (same-clock line assertion for both timers, Timer B flag kept under a same-clock read, read-before-flag not acknowledging, immediate assertion on mask enable) and `MachineProfileTests.testC64CProfilesSelect8521CIAAndOverrideWinsForBothCIAs`. The C64/C64C profile split is a hardware default change for the C64C presets: software that detects the CIA revision now sees an 8521 on those profiles.

## Save states

Recorded 2026-10-17 (development validation). `C64.saveState()` serializes the machine into a tagged binary stream (`SW64SNAP`, format version 1) of length-prefixed chunks: `MACH` (profile, overrides, drive scheduling, mounted media names, progress diagnostics), `CPU `, `MEM ` (RAM, color RAM, CPU port, data-bus decay), `VIC ` (registers, counters, line buffers, graphics latches, sprite DMA and shifter state, raster and sprite traces, framebuffer), `SID ` (voices, filter, paddles, read-back latches; the audio queue is flushed rather than saved), `CIA1`/`CIA2` (timer pipelines, interrupt pipeline, serial shifter, TOD), `IEC `, `TRAP` (Kernal trap channels and pending program), `CART` (the whole cartridge including bank, latch and RAM state), `DRV ` (1541 head, GCR pipeline, write gate, CPU, RAM, both VIAs, and the GCR disk with its track info and image), `HDSK` (high-level drive image, channels, DOS RAM, status), and `TAPE` (image, position, write capture). Every chunk body must be consumed exactly on restore, every fixed-size array is length-checked, and enumerations are range-checked, so a corrupt file fails with a `MachineStateError` instead of a partial restore. The 1541 ROM, C64 ROMs, debugger, host key mappings, and audio/trace diagnostics are not part of the state.

`MachineStateTests` provides the proof:

- `testWriterAndReaderRoundTripPrimitivesArraysOptionalsAndChunks` fixes the byte layout of every primitive and checks truncation, bad booleans, wrong chunk tags, and unconsumed chunk bodies all throw.
- `testStoredPropertyCountsMatchSnapshotCode` compares each chip's reflected stored-property count with the number recorded next to its save code, so adding a field without deciding whether it belongs in the snapshot fails the build's tests.
- `testSnapshotMidInstructionContinuesIdenticallyInFreshAndReusedMachines` runs a ROM-free program with raster IRQs, eight sprites, SID writes and CIA timer IRQs, snapshots while the CPU is in cycle 2 of an instruction and the VIC in cycle 30 of a line, and checks that a fresh machine restored from the snapshot, and the original machine rewound to it, reach the same RAM, color RAM, framebuffer, CPU, VIC, CIA, SID and drive signature after 150,000 more cycles as the uninterrupted run. Re-saving the restored machine reproduces the snapshot byte for byte.
- `testCartridgeAndHighLevelDiskStateSurviveTheRoundTrip` embeds an 8K cartridge and a D64 and checks the cartridge compares equal, both drives see the disk, and the re-saved snapshot is identical.
- `testBootedTrueDriveMachineSnapshotContinuesIdentically` (skipped without local ROMs) boots BASIC with the compatibility true drive and a blank D64, types a PRINT, snapshots mid-instruction, and checks 300,000 further cycles match on both the C64 and the drive CPU.

This is a format-level proof of restore fidelity on the covered subsystems, not a compatibility claim: a snapshot taken during a protected loader's custom timing has the same fidelity as the emulation itself. Snapshots are tied to the format version; there is no migration from earlier versions yet.

## Milestone harness unit expectations

### Realignment record: 2026-10-18

Six `LocalDiskMatrixTests` cases (`testMilestoneResultLogRoundTripsPassedEntriesForResume`, `testMilestoneRunSummaryWritesAggregateJSON`, `testNamedMilestoneCanMatchCIARegisters`, `testNamedMilestoneCanMatchVICBusState`, `testNamedMilestoneCanMatchVICState`, `testNamedMilestoneRequiresVICBusState`) had been failing since the 0.4.0 VIC timing work (`9e6d1d2`) and the 0.4.3 CIA timer pipeline (`708eced`); the SID filter calibration found them already failing on its parent commit `9ad3717`. Each was checked against the chip model that the public runners validate, and in every case the core is right and the unit expectation had drifted, so only the expectations changed. No VIC, CIA or SID code was touched.

- **Sprite pointer slot at raster cycle 0.** A fresh machine sits in raster cycle 0, which is hardware cycle 1, the p-access for sprite 3; pointer fetches run on every line whether or not sprite DMA is active (`VICSpriteFetchTests`, public sprite programs). The result-log and run-summary records therefore report `spritePointer(sprite:3)`, not `idle`.
- **Matrix fetch column.** Matrix (c-)accesses occupy hardware cycles 15-54, raster cycles 14-53, with the g-access for the same column one cycle later in phi1 (`VICBeamTimingTests`, the public FLD/FLI images). After one tick from raster cycle 14 the harness reports cycle 15 as `badLineCharacterFetch(column:1)` with `displayData(column:0)`, and the executed cycle's trace holds the column 0 c-access (`$0400`, color RAM `$0000`), which the mismatch strings now spell out.
- **Line-buffer base.** The first c-access of a matrix row latches VCBASE as the line-buffer base, so a bad line entered mid-row reports the current VCBASE (80), not a stale value.
- **CIA timer start.** A 6526 start with force load reads old, latch, latch, latch − 1 over the first four cycles (`CIATimerPipelineTests.testControlWriteReadbackMatchesFirstFourHardwareCycles`, Lorenz's tables, `timerbasics`), so `$DC04` reaches `$33` in the fourth cycle; the milestone allows four cycles instead of one.

Measured sequential Release run (`swift test -c release -j 2 --filter LocalDiskMatrixTests`): **111 tests, 6 opt-in skips (the six `...WhenEnabled` cases), 0 failures**. Before the change the same six cases failed with 15 assertions.
