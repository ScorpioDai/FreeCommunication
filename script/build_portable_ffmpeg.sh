#!/usr/bin/env bash
set -euo pipefail

FFMPEG_VERSION="8.1.2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT_DIR/work/ffmpeg-$FFMPEG_VERSION"
SOURCE_DIR="$BUILD_ROOT/ffmpeg-$FFMPEG_VERSION"
INSTALL_DIR="$BUILD_ROOT/install"
VENDOR_DIR="$ROOT_DIR/Vendor/FFmpeg"

mkdir -p "$BUILD_ROOT"
if [ ! -f "$BUILD_ROOT/ffmpeg.tar.xz" ]; then
  curl -L --fail --retry 3 \
    "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" \
    -o "$BUILD_ROOT/ffmpeg.tar.xz"
fi
if [ ! -d "$SOURCE_DIR" ]; then
  tar -xJf "$BUILD_ROOT/ffmpeg.tar.xz" -C "$BUILD_ROOT"
fi

cd "$SOURCE_DIR"
export MACOSX_DEPLOYMENT_TARGET=15.0
./configure \
  --prefix="$INSTALL_DIR" \
  --cc=clang \
  --arch=arm64 \
  --target-os=darwin \
  --enable-shared \
  --disable-static \
  --disable-doc \
  --disable-debug \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-network \
  --disable-autodetect \
  --disable-avdevice \
  --extra-cflags='-mmacosx-version-min=15.0' \
  --extra-ldflags='-mmacosx-version-min=15.0' \
  --install-name-dir='@rpath'
make -j"$(sysctl -n hw.ncpu)"
make install

mkdir -p "$VENDOR_DIR/lib" "$VENDOR_DIR/Licenses"
cp -p "$INSTALL_DIR/bin/ffmpeg" "$VENDOR_DIR/ffmpeg"
cp -a "$INSTALL_DIR/lib/"*.dylib "$VENDOR_DIR/lib/"
cp -p "$SOURCE_DIR/COPYING.LGPLv2.1" "$VENDOR_DIR/Licenses/FFmpeg-LGPL-2.1.txt"
install_name_tool -add_rpath '@executable_path/lib' "$VENDOR_DIR/ffmpeg" 2>/dev/null || true
chmod +x "$VENDOR_DIR/ffmpeg"

echo "Portable FFmpeg staged at $VENDOR_DIR"
