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

`SWIFT64_PUBLIC_VIC_TEST_IDS` selects a comma-separated subset. IDs are `phi1-pal`, `phi1-ntsc`, `sprite-collision-pal`, `graphics-collision-pal`; `fld-20-pal`, `fld-21-pal`, `fld-22-pal`, `fld-29-pal`, `fld-2a-pal`, `fld-2b-pal`; `sprite-dma-54-pal`, `sprite-dma-54-ntsc`, `sprite-dma-57-pal`, `sprite-dma-57-ntsc`; the twelve PAL border IDs; and the seventeen PAL sprite-register split IDs documented below. The default runs all 43. Local ROMs default to `Sources/C64App/ROMS`; `SWIFT64_PUBLIC_VIC_ROM_DIR` can select another directory containing the same named BASIC, Kernal, and character files. Boot is bounded at 300 frames and must display READY; each original BASIC stub is then started with RUN and has a three-million-cycle limit. KERNAL traps are disabled. Completion requires the program's actual CPU write to `$D7FF`, not a normalized SID mirror, patched instruction, direct PC entry, or scan for a result instruction. The four bus/collision programs self-check; the 39 visual programs additionally require exact color-index comparison, since their `$D7FF` write only requests capture. Instances run sequentially and are released between fixtures.

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

The runner selects 50 public programs by default. Seven additional unchanged programs probe PAL/NTSC graphics-fetch timing, Blackmail FLI, and bitmap open borders. The 43-program result above is a historical sprite-split checkpoint. The table below records release 0.4.1; newer results follow in [bitmap output-latch proof](#bitmap-open-border-output-latch).

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

Blackmail has a scoped, strict expected failure for its unresolved FLI row alignment. Its exact mismatch count is asserted outside that waiver, so changed results require investigation; the failure is not counted as a visual pass. The three standard-bitmap border probes retain ordinary zero-difference assertions: they failed in 0.4.1 and now pass without waivers. Multicolor bitmap and standard bitmap are tested separately; a pass for one does not certify the other.

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
