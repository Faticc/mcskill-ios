#!/bin/bash
# Lays out what the game runs on inside <HTS.app> (see App/GameRuntime.swift):
#   Frameworks/ — ANGLE (libEGL/libGLESv2 frameworks), gl4es and OpenAL from Amethyst-iOS at a pinned
#                 commit, LWJGL 3.4.1 natives (release deps-1), our SDL3 (scripts/build-sdl.sh)
#   game/lwjgl-3.4.1/ — the LWJGL jars built with those natives; game/hts-lwjgl-patch.jar (CI build of
#   lwjgl-patch/), MioLibPatcher.jar and the log4j config (game/ of this repo); game/tests/gltest.jar
# With "simulator" the prebuilt Mach-O files are retagged for the simulator and ad-hoc signed.
# Usage: scripts/pack-game-libs.sh <HTS.app> <cache dir> <libSDL3.dylib> <dir with gltest.jar, hts-lwjgl-patch.jar> [simulator]
set -euo pipefail

APP="$1"
CACHE="$2"
SDL="$3"
BUILT="$4"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TARGET="${5:-device}"
AMETHYST=9212a1894865e7ac0466029e25ddb0d895544c76
RAW="https://github.com/AngelAuraMC/Amethyst-iOS/raw/$AMETHYST/Natives/resources/Frameworks"
LWJGL_SHA=0ea4f112bf9e3c3bde9790a00a50988c9662a49f91bfe112675e3fa7e3ec8f0c

AM="$CACHE/amethyst-$AMETHYST"
for f in libEGL.framework/Info.plist libEGL.framework/libEGL libGLESv2.framework/Info.plist \
         libGLESv2.framework/libGLESv2 libgl4es_114.dylib libopenal.dylib; do
    mkdir -p "$(dirname "$AM/$f")"
    [ -s "$AM/$f" ] || curl -fsSL --retry 3 -o "$AM/$f" "$RAW/$f"
done
LW="$CACHE/lwjgl-3.4.1-ios.tar.gz"
[ -s "$LW" ] || gh release download deps-1 -R Faticc/mcskill-ios -p lwjgl-3.4.1-ios.tar.gz -D "$CACHE"
echo "$LWJGL_SHA  $LW" | shasum -a 256 -c - >/dev/null

FW="$APP/Frameworks"
GAME="$APP/game"
mkdir -p "$FW" "$GAME/lwjgl-3.4.1" "$GAME/tests"
cp -R "$AM/." "$FW/"
work=$(mktemp -d)
tar -xzf "$LW" -C "$work"
cp "$work"/natives/*.dylib "$FW/"
cp "$work"/jars/*.jar "$GAME/lwjgl-3.4.1/"
rm -rf "$work"
cp "$SDL" "$FW/libSDL3.dylib"
cp "$(dirname "$SDL")/libhtsgl.dylib" "$FW/"
cp "$BUILT/gltest.jar" "$GAME/tests/gltest.jar"
cp "$BUILT/hts-lwjgl-patch.jar" "$GAME/"
cp "$ROOT"/game/* "$GAME/"

if [ "$TARGET" = simulator ]; then
    while IFS= read -r -d '' f; do
        case "$(basename "$f")" in libSDL3.dylib|libhtsgl.dylib) continue ;; esac
        if file -b "$f" | grep -q '^Mach-O'; then
            xcrun vtool -arch arm64 -set-build-version 7 14.0 16.0 -replace -output "$f" "$f"
            codesign -f -s - "$f" 2>/dev/null
        fi
    done < <(find "$FW" -type f -print0)
fi
echo "game libs ($TARGET): $(ls "$FW" | tr '\n' ' ')"
echo "lwjgl jars: $(ls "$GAME/lwjgl-3.4.1" | wc -l | tr -d ' ')"
