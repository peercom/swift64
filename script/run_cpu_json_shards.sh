#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="${1:-${SWIFT64_PROCESSOR_JSON_TEST_DIR:-}}"
SHARD_COUNT="${2:-${SWIFT64_PROCESSOR_JSON_SHARD_COUNT:-4}}"
OPCODES="${SWIFT64_PROCESSOR_JSON_OPCODES:-all}"
OUT_DIR="${SWIFT64_PROCESSOR_JSON_OUT_DIR:-$ROOT_DIR/.build/swift64-cpu-json-shards/$(date +%Y%m%d-%H%M%S)}"
SUMMARY_LIST="$OUT_DIR/summaries.list"
TEST_FILTER="CPU6502ProcessorJSONTests/testOptInProcessorJSONSingleStepVectors"

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

cd "$ROOT_DIR"

for ((shard_index = 0; shard_index < SHARD_COUNT; shard_index++)); do
  summary_json="$OUT_DIR/processor-json-shard-$shard_index-of-$SHARD_COUNT.json"
  echo "$summary_json" >> "$SUMMARY_LIST"
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

cat <<EOF
Swift64 CPU JSON shard run complete.
Output directory: $OUT_DIR
Summary list:     $SUMMARY_LIST
EOF
