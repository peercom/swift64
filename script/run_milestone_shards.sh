#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARD_COUNT="${1:-${SWIFT64_LOCAL_MILESTONE_SHARD_COUNT:-4}}"
RUN_ID_PREFIX="${SWIFT64_LOCAL_MILESTONE_RUN_ID_PREFIX:-milestone-shard}"
OUT_DIR="${SWIFT64_LOCAL_MILESTONE_OUT_DIR:-$ROOT_DIR/.build/swift64-milestone-shards/$(date +%Y%m%d-%H%M%S)}"
RESULTS_JSONL="${SWIFT64_LOCAL_MILESTONE_RESULTS_JSONL:-$OUT_DIR/results.jsonl}"
SUMMARY_LIST="$OUT_DIR/summaries.list"
TEST_FILTER="LocalDiskMatrixTests/testLocalDiskImagesNamedMilestonesWhenEnabled"

if ! [[ "$SHARD_COUNT" =~ ^[0-9]+$ ]] || [[ "$SHARD_COUNT" -lt 1 ]]; then
  echo "usage: $0 [positive-shard-count]" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
: > "$SUMMARY_LIST"

cd "$ROOT_DIR"

for ((shard_index = 0; shard_index < SHARD_COUNT; shard_index++)); do
  summary_json="$OUT_DIR/summary-shard-$shard_index-of-$SHARD_COUNT.json"
  echo "$summary_json" >> "$SUMMARY_LIST"
  echo "Running Swift64 milestone shard $((shard_index + 1))/$SHARD_COUNT"

  env \
    SWIFT64_LOCAL_MILESTONE_MATRIX=1 \
    SWIFT64_LOCAL_MILESTONE_RESUME=1 \
    SWIFT64_LOCAL_MILESTONE_RESUME_STRICT_MANIFEST=1 \
    SWIFT64_LOCAL_MILESTONE_SHARD_INDEX="$shard_index" \
    SWIFT64_LOCAL_MILESTONE_SHARD_COUNT="$SHARD_COUNT" \
    SWIFT64_LOCAL_MILESTONE_RESULTS_JSONL="$RESULTS_JSONL" \
    SWIFT64_LOCAL_MILESTONE_SUMMARY_JSON="$summary_json" \
    SWIFT64_LOCAL_MILESTONE_RUN_ID="$RUN_ID_PREFIX-$shard_index-of-$SHARD_COUNT" \
    swift test --filter "$TEST_FILTER"
done

cat <<EOF
Swift64 milestone shard run complete.
Output directory: $OUT_DIR
Result log:       $RESULTS_JSONL
Summary list:     $SUMMARY_LIST
EOF
