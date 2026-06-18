#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Swift64"
PROJECT_NAME="Swift64"
SCHEME_NAME="Swift64"
CONFIGURATION="${CONFIGURATION:-Debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/$PROJECT_NAME.xcodeproj"
DERIVED_DATA_DIR="$ROOT_DIR/DerivedData/$PROJECT_NAME"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodegen generate --spec "$ROOT_DIR/project.yml" --project "$ROOT_DIR"
xcodebuild \
  -quiet \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -jobs 2 \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
