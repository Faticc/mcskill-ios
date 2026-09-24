#!/bin/bash
# Builds SDL3 for iOS (device or simulator) with sdl/SDL_uikit_hts.m: UIKit calls on the main thread
# while the game runs on the JVM's thread, and GL through ANGLE's EGL instead of EAGL.
# Output: <out dir>/libSDL3.dylib (install name @rpath/libSDL3.dylib)
# Usage: scripts/build-sdl.sh device|simulator <out dir>
set -euo pipefail

PLATFORM="$1"
OUT="$2"
VERSION=3.4.16
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/build/sdl-src"

if [ ! -d "$SRC" ]; then
    git clone -q --depth 1 --branch "release-$VERSION" https://github.com/libsdl-org/SDL.git "$SRC"
fi
cp "$ROOT/sdl/SDL_uikit_hts.m" "$SRC/src/video/uikit/"
VIDEO="$SRC/src/video/uikit/SDL_uikitvideo.m"
if ! grep -q HTS_UIKit_Install "$VIDEO"; then
    perl -0pi -e 's/(static SDL_VideoDevice \*UIKit_CreateDevice\(void\)\n)/extern void HTS_UIKit_Install(SDL_VideoDevice *device);\n\n$1/' "$VIDEO"
    perl -0pi -e 's/(        device->gl_config\.accelerated = 1;\n\n)(        return device;)/$1        HTS_UIKit_Install(device);\n\n$2/' "$VIDEO"
fi
[ "$(grep -c HTS_UIKit_Install "$VIDEO")" = 2 ] || { echo "SDL_uikitvideo.m hook not applied"; exit 1; }

case "$PLATFORM" in
    device) SYSROOT=iphoneos ;;
    simulator) SYSROOT=iphonesimulator ;;
    *) echo "platform: device|simulator"; exit 1 ;;
esac
BUILD="$ROOT/build/sdl-$PLATFORM"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=$SYSROOT -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 -DCMAKE_BUILD_TYPE=Release \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST_LIBRARY=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
    -DCMAKE_INSTALL_NAME_DIR=@rpath >/dev/null
cmake --build "$BUILD" --target SDL3-shared
mkdir -p "$OUT"
lib=$(find "$BUILD" -maxdepth 1 -name 'libSDL3*.dylib' -type f | head -1)
cp "$lib" "$OUT/libSDL3.dylib"
install_name_tool -id @rpath/libSDL3.dylib "$OUT/libSDL3.dylib"
nm -gU "$OUT/libSDL3.dylib" > "$BUILD/exports.txt"
grep -q ' _SDL_CreateWindow$' "$BUILD/exports.txt"
grep -q ' _HTS_SendKey$' "$BUILD/exports.txt"
echo "SDL3 $VERSION ($PLATFORM): $(stat -f %z "$OUT/libSDL3.dylib") bytes"
