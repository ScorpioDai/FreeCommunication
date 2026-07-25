#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FreeCommunication"
APP_VERSION="1.5.2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
OUTPUT_DMG="$ROOT_DIR/dist/$APP_NAME-$APP_VERSION.dmg"
VOLUME_NAME="$APP_NAME $APP_VERSION"
WORK_DIR="$(mktemp -d /tmp/freecommunication-dmg.XXXXXX)"
STAGING_DIR="$WORK_DIR/staging"
MOUNT_DIR=""
RW_DMG="$WORK_DIR/$APP_NAME-rw.dmg"
MOUNTED=0

cleanup() {
  if [ "$MOUNTED" -eq 1 ]; then
    /usr/bin/hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
  fi
  find "$WORK_DIR" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

if [ ! -d "$APP_BUNDLE" ]; then
  echo "missing app bundle: $APP_BUNDLE" >&2
  echo "run ./script/build_and_run.sh --verify first" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
/bin/mkdir -p "$STAGING_DIR/.background"
/usr/bin/ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/swift "$ROOT_DIR/script/make_dmg_background.swift" \
  "$STAGING_DIR/.background/background.png"

if [ -e "$OUTPUT_DMG" ]; then
  find "$OUTPUT_DMG" -delete
fi

/usr/bin/hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDRW \
  -fs HFS+ \
  "$RW_DMG" >/dev/null

ATTACH_OUTPUT="$(/usr/bin/hdiutil attach \
  "$RW_DMG" \
  -nobrowse \
  -noverify \
  -readwrite)"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUTPUT" | /usr/bin/awk -F '\t' 'END {print $NF}')"
if [ ! -d "$MOUNT_DIR" ]; then
  echo "failed to locate mounted disk image" >&2
  exit 1
fi
MOUNTED=1
/bin/sleep 1

/usr/bin/SetFile -a V "$MOUNT_DIR/.background"

/usr/bin/osascript - "$VOLUME_NAME" "$APP_NAME.app" <<'APPLESCRIPT'
on run arguments
  set volumeName to item 1 of arguments
  set appName to item 2 of arguments

  tell application "Finder"
    tell disk volumeName
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set pathbar visible of container window to false
      set bounds of container window to {160, 160, 880, 636}

      set viewOptions to icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 112
      set text size of viewOptions to 13
      set background picture of viewOptions to file ".background:background.png"

      set position of item appName of container window to {180, 235}
      set position of item "Applications" of container window to {540, 235}

      update without registering applications
      delay 2
      close container window
    end tell
  end tell
end run
APPLESCRIPT

/bin/sync
/usr/bin/hdiutil detach "$MOUNT_DIR" >/dev/null
MOUNTED=0

/usr/bin/hdiutil convert \
  "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$OUTPUT_DMG" >/dev/null

echo "$OUTPUT_DMG"
