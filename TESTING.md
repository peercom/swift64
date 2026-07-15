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
