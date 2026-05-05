#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MacBar"
PROJECT_NAME="MacBar.xcodeproj"
SCHEME_NAME="MacBar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DIR="$ROOT_DIR/.derived"
BUILT_APP="$DERIVED_DIR/Build/Products/Debug/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/build"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 0.3

xcodebuild \
  -project "$PROJECT_NAME" \
  -scheme "$SCHEME_NAME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DIR" \
  build

mkdir -p "$DIST_DIR"
TMP_BUNDLE="$DIST_DIR/$APP_NAME.app.tmp.$$"
/usr/bin/ditto "$BUILT_APP" "$TMP_BUNDLE"

if [[ -e "$APP_BUNDLE" ]]; then
  mv "$APP_BUNDLE" "$DIST_DIR/$APP_NAME.app.previous-$(date +%Y%m%d-%H%M%S)-$$"
fi
mv "$TMP_BUNDLE" "$APP_BUNDLE"

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
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
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
