#!/bin/bash
#
# build-ios.sh - Compile mGBA as a static library for iOS (arm64)
#
# Prerequisites:
#   - CMake 3.20+
#   - Xcode command line tools
#   - ios-cmake toolchain (auto-downloaded)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build-ios"
OUTPUT_DIR="${SCRIPT_DIR}/lib"
INCLUDE_DIR="${SCRIPT_DIR}/include"
MGBA_VERSION="0.10.3"
MGBA_SRC="${SCRIPT_DIR}/mgba-src"

echo "=== Building mGBA ${MGBA_VERSION} for iOS ==="

# Step 1: Clone mGBA source if not exists
if [ ! -d "${MGBA_SRC}" ]; then
    echo ">>> Cloning mGBA source..."
    git clone --depth 1 --branch "${MGBA_VERSION}" \
        https://github.com/mgba-emu/mgba.git "${MGBA_SRC}"
fi

# Step 2: Download ios-cmake toolchain if not exists
TOOLCHAIN_FILE="${SCRIPT_DIR}/ios.toolchain.cmake"
if [ ! -f "${TOOLCHAIN_FILE}" ]; then
    echo ">>> Downloading ios-cmake toolchain..."
    curl -sL https://raw.githubusercontent.com/nickhutchinson/ios-cmake/master/toolchain/iOS.cmake \
        -o "${TOOLCHAIN_FILE}" || {
        # Fallback: create minimal toolchain
        cat > "${TOOLCHAIN_FILE}" << 'TOOLCHAIN_EOF'
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_ARCHITECTURES arm64)
set(CMAKE_OSX_DEPLOYMENT_TARGET "16.0")
set(CMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH NO)
set(CMAKE_IOS_INSTALL_COMBINED YES)
TOOLCHAIN_EOF
    }
fi

# Step 3: Create build directory
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Step 4: Configure with CMake
echo ">>> Configuring mGBA with CMake..."
cmake -B "${BUILD_DIR}" -S "${MGBA_SRC}" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN_FILE}" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED=OFF \
    -DBUILD_STATIC=ON \
    -DBUILD_GL=OFF \
    -DBUILD_GLES2=OFF \
    -DBUILD_GLES3=OFF \
    -DBUILD_QT=OFF \
    -DBUILD_SDL=OFF \
    -DBUILD_LIBRETRO=OFF \
    -DBUILD_PERF=OFF \
    -DBUILD_TEST=OFF \
    -DBUILD_SUITE=OFF \
    -DBUILD_EXAMPLE=OFF \
    -DBUILD_ROM_TEST=OFF \
    -DUSE_DISCORD_RPC=OFF \
    -DUSE_SQLITE3=OFF \
    -DUSE_PNG=OFF \
    -DUSE_ZLIB=ON \
    -DUSE_MINIZIP=ON \
    -DUSE_LZMA=OFF \
    -DUSE_LIBZIP=OFF \
    -DUSE_EPOXY=OFF \
    -DUSE_FFMPEG=OFF \
    -DM_CORE_GBA=ON \
    -DM_CORE_GB=ON

# Step 5: Build
echo ">>> Building mGBA..."
cmake --build "${BUILD_DIR}" --config Release -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Step 6: Copy outputs
echo ">>> Installing outputs..."
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${INCLUDE_DIR}"

# Copy static library
find "${BUILD_DIR}" -name "libmgba.a" -exec cp {} "${OUTPUT_DIR}/" \;

# Copy headers
if [ -d "${MGBA_SRC}/include" ]; then
    cp -R "${MGBA_SRC}/include/"* "${INCLUDE_DIR}/"
fi
# Also copy generated headers
if [ -d "${BUILD_DIR}/include" ]; then
    cp -R "${BUILD_DIR}/include/"* "${INCLUDE_DIR}/"
fi

echo "=== mGBA build complete ==="
echo "  Library: ${OUTPUT_DIR}/libmgba.a"
echo "  Headers: ${INCLUDE_DIR}/"
echo ""
echo "Add to Xcode:"
echo "  - Header Search Paths: \$(PROJECT_DIR)/GBAEmulator/mGBA/include"
echo "  - Library Search Paths: \$(PROJECT_DIR)/GBAEmulator/mGBA/lib"
echo "  - Other Linker Flags: -lmgba"
