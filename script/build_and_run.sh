#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="FreeCommunication"
BUNDLE_ID="com.scorpiodai.FreeCommunication"
APP_VERSION="1.5.0"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
FFMPEG_VENDOR="$ROOT_DIR/Vendor/FFmpeg"

require_file() {
  if [ ! -f "$1" ]; then
    echo "missing required file: $1" >&2
    exit 1
  fi
}

require_file "$ROOT_DIR/Backend/.venv/bin/python"
require_file "$FFMPEG_VENDOR/ffmpeg"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [ -d "$ROOT_DIR/Backend" ]; then
  rsync -a --delete --exclude '__pycache__' "$ROOT_DIR/Backend/" "$APP_RESOURCES/Backend/"
  find "$APP_RESOURCES/Backend" -type d -name '__pycache__' -prune -exec rm -rf {} +
  find "$APP_RESOURCES/Backend" -name '*.pyc' -delete
fi

# A copied venv still points at its creator's base Python. Add that base
# standard library and runtime dylibs so the bundled interpreter can move.
SOURCE_PYTHON="$ROOT_DIR/Backend/.venv/bin/python"
PYTHON_BASE_PREFIX="$("$SOURCE_PYTHON" -c 'import sys; print(sys.base_prefix)')"
PYTHON_VERSION="$("$SOURCE_PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
BUNDLED_RUNTIME="$APP_RESOURCES/Backend/.venv"
BUNDLED_PYTHON_LIB="$BUNDLED_RUNTIME/lib/python$PYTHON_VERSION"
require_file "$PYTHON_BASE_PREFIX/lib/python$PYTHON_VERSION/os.py"
mkdir -p "$BUNDLED_PYTHON_LIB" "$BUNDLED_RUNTIME/lib"
rsync -a --exclude 'site-packages' \
  "$PYTHON_BASE_PREFIX/lib/python$PYTHON_VERSION/" \
  "$BUNDLED_PYTHON_LIB/"
while IFS= read -r -d '' dylib; do
  cp -a "$dylib" "$BUNDLED_RUNTIME/lib/"
done < <(find "$PYTHON_BASE_PREFIX/lib" -maxdepth 1 \( -type f -o -type l \) -name '*.dylib*' -print0)
rm -f "$BUNDLED_RUNTIME/pyvenv.cfg"
find "$APP_RESOURCES/Backend" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "$APP_RESOURCES/Backend" -name '*.pyc' -delete

mkdir -p "$APP_RESOURCES/Tools"
rsync -a --delete "$FFMPEG_VENDOR/" "$APP_RESOURCES/Tools/"
chmod +x "$APP_RESOURCES/Tools/ffmpeg"

if [ -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>FreeCommunication needs microphone access for live field and call transcription.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>FreeCommunication needs screen audio capture for video and call transcription.</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

if ! /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1; then
  echo "warning: ad-hoc codesign failed; the app can still run locally from this build folder." >&2
fi

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
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
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
