#!/bin/bash
# Reproducible mGBA build using CMake's built-in Apple platform support.
# Usage: ./build-ios.sh [iphoneos|iphonesimulator|macosx]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM="${1:-${PLATFORM_NAME:-iphoneos}}"
case "$PLATFORM" in
  iphoneos|iphonesimulator) SYSTEM=iOS; DEPLOYMENT=17.0 ;;
  macosx) SYSTEM=Darwin; DEPLOYMENT=14.0 ;;
  *) echo "Unsupported platform: $PLATFORM" >&2; exit 1 ;;
esac
ARCH="${MGBA_ARCH:-arm64}"
BUILD_DIR="$SCRIPT_DIR/build-$PLATFORM-$ARCH"
OUTPUT_DIR="$SCRIPT_DIR/lib/$PLATFORM"
MGBA_SRC="$SCRIPT_DIR/mgba-src"
MGBA_VERSION=0.10.3
if [ ! -d "$MGBA_SRC/.git" ]; then
  git clone --depth 1 --branch "$MGBA_VERSION" https://github.com/mgba-emu/mgba.git "$MGBA_SRC"
fi
if [ "$(git -C "$MGBA_SRC" describe --tags --exact-match HEAD)" != "$MGBA_VERSION" ]; then
  echo "mGBA source must be tagged $MGBA_VERSION" >&2; exit 1
fi
cmake -S "$MGBA_SRC" -B "$BUILD_DIR" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_SYSTEM_NAME="$SYSTEM" \
  -DCMAKE_OSX_SYSROOT="$(xcrun --sdk "$PLATFORM" --show-sdk-path)" \
  -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED=OFF -DBUILD_STATIC=ON \
  -DBUILD_GL=OFF -DBUILD_GLES2=OFF -DBUILD_GLES3=OFF \
  -DBUILD_QT=OFF -DBUILD_SDL=OFF -DBUILD_LIBRETRO=OFF \
  -DBUILD_PERF=OFF -DBUILD_TEST=OFF -DBUILD_SUITE=OFF \
  -DBUILD_EXAMPLE=OFF -DBUILD_ROM_TEST=OFF \
  -DUSE_DISCORD_RPC=OFF -DUSE_SQLITE3=OFF -DUSE_PNG=OFF \
  -DUSE_ZLIB=ON -DUSE_MINIZIP=OFF -DUSE_LZMA=OFF \
  -DUSE_LIBZIP=OFF -DUSE_EPOXY=OFF -DUSE_FFMPEG=OFF \
  -DM_CORE_GBA=ON -DM_CORE_GB=OFF
cmake --build "$BUILD_DIR" --parallel "$(sysctl -n hw.ncpu)"
mkdir -p "$OUTPUT_DIR" "$SCRIPT_DIR/include"
cp "$BUILD_DIR/libmgba.a" "$OUTPUT_DIR/libmgba.a"
cp -R "$MGBA_SRC/include/"* "$SCRIPT_DIR/include/"
if [ -d "$BUILD_DIR/include" ]; then
  cp -R "$BUILD_DIR/include/"* "$SCRIPT_DIR/include/"
fi
printf '%s\n' "mGBA $MGBA_VERSION: $OUTPUT_DIR/libmgba.a ($ARCH)"
