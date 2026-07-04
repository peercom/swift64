#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${1:-${SWIFT64_PROCESSOR_JSON_TEST_DIR:-}}"
SHARD_COUNT="${2:-${SWIFT64_PROCESSOR_JSON_SHARD_COUNT:-4}}"
OPCODES="${SWIFT64_PROCESSOR_JSON_OPCODES:-all}"
OUT_DIR="${SWIFT64_PROCESSOR_JSON_OUT_DIR:-$ROOT_DIR/.build/swift64-cpu-json-shards/$(date +%Y%m%d-%H%M%S)}"
SUMMARY_LIST="$OUT_DIR/summaries.list"
RUN_INDEX_JSON="$OUT_DIR/run-index.json"
TEST_FILTER="CPU6502ProcessorJSONTests/testOptInProcessorJSONSingleStepVectors"
RUN_INDEX_CLOSED=0

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

close_run_index() {
  if [[ "$RUN_INDEX_CLOSED" -eq 0 && -f "$RUN_INDEX_JSON" ]]; then
    printf '\n  ]\n}\n' >> "$RUN_INDEX_JSON"
    RUN_INDEX_CLOSED=1
  fi
}

if [[ -z "$TEST_DIR" ]]; then
  echo "usage: $0 /path/to/TomHarte/ProcessorTests/6502/v1 [positive-shard-count]" >&2
  exit 2
fi

if ! [[ "$SHARD_COUNT" =~ ^[0-9]+$ ]] || [[ "$SHARD_COUNT" -lt 1 ]]; then
  echo "shard count must be a positive integer" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
: > "$SUMMARY_LIST"
{
  printf '{\n'
  printf '  "formatVersion": 1,\n'
  printf '  "runnerName": "script/run_cpu_json_shards.sh",\n'
  printf '  "category": "cpu",\n'
  printf '  "roadmapPhase": "phase2CPUMemoryBus",\n'
  printf '  "testDirectory": "%s",\n' "$(json_escape "$TEST_DIR")"
  printf '  "opcodeSelection": "%s",\n' "$(json_escape "$OPCODES")"
  printf '  "shardCount": %s,\n' "$SHARD_COUNT"
  printf '  "strictCycles": "%s",\n' "${SWIFT64_PROCESSOR_JSON_STRICT_CYCLES:-1}"
  printf '  "failFast": "%s",\n' "${SWIFT64_PROCESSOR_JSON_FAIL_FAST:-1}"
  printf '  "summaries": [\n'
} > "$RUN_INDEX_JSON"
trap close_run_index EXIT

cd "$ROOT_DIR"

for ((shard_index = 0; shard_index < SHARD_COUNT; shard_index++)); do
  summary_json="$OUT_DIR/processor-json-shard-$shard_index-of-$SHARD_COUNT.json"
  echo "$summary_json" >> "$SUMMARY_LIST"
  if [[ "$shard_index" -gt 0 ]]; then
    printf ',\n' >> "$RUN_INDEX_JSON"
  fi
  printf '    {"shardIndex": %s, "summary": "%s"}' "$shard_index" "$(json_escape "$summary_json")" >> "$RUN_INDEX_JSON"
  echo "Running Swift64 CPU JSON shard $((shard_index + 1))/$SHARD_COUNT"

  env \
    SWIFT64_PROCESSOR_JSON_TEST_DIR="$TEST_DIR" \
    SWIFT64_PROCESSOR_JSON_OPCODES="$OPCODES" \
    SWIFT64_PROCESSOR_JSON_SHARD_INDEX="$shard_index" \
    SWIFT64_PROCESSOR_JSON_SHARD_COUNT="$SHARD_COUNT" \
    SWIFT64_PROCESSOR_JSON_STRICT_CYCLES="${SWIFT64_PROCESSOR_JSON_STRICT_CYCLES:-1}" \
    SWIFT64_PROCESSOR_JSON_FAIL_FAST="${SWIFT64_PROCESSOR_JSON_FAIL_FAST:-1}" \
    SWIFT64_PROCESSOR_JSON_RESULT_JSON="$summary_json" \
    swift test -c release --filter "$TEST_FILTER"
done

close_run_index

cat <<EOF
Swift64 CPU JSON shard run complete.
Output directory: $OUT_DIR
Summary list:     $SUMMARY_LIST
Run index:        $RUN_INDEX_JSON
EOF
