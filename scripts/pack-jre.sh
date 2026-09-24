#!/bin/bash
# Puts Amethyst's iOS builds of Java 8, 17 and 25 into <HTS.app>/java_runtimes/java-N-openjdk,
# trimmed as Amethyst's Makefile does. The zips are kept in <cache dir> between CI runs.
# Usage: scripts/pack-jre.sh <HTS.app> <cache dir>
set -euo pipefail

APP="$1"
CACHE="$2"
BASE=https://assets.angelauramc.dev/openjdk/ios-arm64
mkdir -p "$CACHE" "$APP/java_runtimes"

for v in 8 17 25; do
    zip="$CACHE/jre$v-ios-aarch64.zip"
    [ -s "$zip" ] || curl -fsSL --retry 3 -o "$zip" "$BASE/jre$v-ios-aarch64.zip"
    work=$(mktemp -d)
    unzip -q "$zip" -d "$work"
    dest="$APP/java_runtimes/java-$v-openjdk"
    rm -rf "$dest"
    mkdir -p "$dest"
    tar -xJf "$work"/jre$v-*.tar.xz -C "$dest"
    rm -rf "$work"
    (cd "$dest" && rm -rf ASSEMBLY_EXCEPTION bin include jre legal LICENSE man THIRD_PARTY_README \
        lib/ct.sym lib/jspawnhelper lib/libjsig.dylib lib/src.zip lib/tools.jar)
    echo "java-$v-openjdk: $(grep '^JAVA_VERSION=' "$dest/release"), $(du -sh "$dest" | cut -f1)"
done

# Nothing may point outside the bundle
if find "$APP/java_runtimes" -type l | grep -q .; then
    echo "symlinks left in java_runtimes:"
    find "$APP/java_runtimes" -type l
    exit 1
fi
