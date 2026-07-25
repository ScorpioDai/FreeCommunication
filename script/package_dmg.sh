#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FreeCommunication"
APP_VERSION="1.5.1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
OUTPUT_DMG="$ROOT_DIR/dist/$APP_NAME-$APP_VERSION.dmg"
STAGING_DIR="$(mktemp -d /tmp/freecommunication-dmg.XXXXXX)"

cleanup() {
  find "$STAGING_DIR" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

if [ ! -d "$APP_BUNDLE" ]; then
  echo "missing app bundle: $APP_BUNDLE" >&2
  echo "run ./script/build_and_run.sh --verify first" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
/usr/bin/ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"

if [ -e "$OUTPUT_DMG" ]; then
  find "$OUTPUT_DMG" -delete
fi

/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$OUTPUT_DMG"

echo "$OUTPUT_DMG"
