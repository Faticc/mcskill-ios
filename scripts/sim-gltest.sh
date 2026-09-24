#!/bin/bash
# Runs tests/gltest (SDL window, ANGLE, gl4es) in the booted simulator: `--gltest`, a screenshot
# while it draws, then the report and jvm.log.
# Usage: scripts/sim-gltest.sh <HTS.app> <out dir>
set -uo pipefail

APP="$1"
OUT="$2"
BUNDLE=ru.hts.launcher
mkdir -p "$OUT"
UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
xcrun simctl install "$UDID" "$APP" || exit 1
LOGS="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/Documents/logs"
mkdir -p "$LOGS"
rm -f "$LOGS/gltest.json" "$LOGS/jvm.log"

xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" --gltest >/dev/null
status=timeout
shot=0
for _ in $(seq 1 60); do
    sleep 2
    if [ $shot = 0 ] && grep -q '\[gltest\] Drawable' "$LOGS/jvm.log" 2>/dev/null; then
        sleep 2
        xcrun simctl io "$UDID" screenshot "$OUT/gltest.png" >/dev/null && sips -r 270 "$OUT/gltest.png" >/dev/null
        shot=1
    fi
    if [ -f "$LOGS/gltest.json" ]; then status=done; break; fi
    if ! pgrep -f "HTS.app/HTS" >/dev/null; then status="app died"; break; fi
done
[ $shot = 1 ] || { xcrun simctl io "$UDID" screenshot "$OUT/gltest.png" >/dev/null && sips -r 270 "$OUT/gltest.png" >/dev/null; }
echo "===== GL test: $status"
cp "$LOGS/gltest.json" "$OUT/" 2>/dev/null && cat "$OUT/gltest.json"
cp "$LOGS/jvm.log" "$OUT/gltest-jvm.log" 2>/dev/null && tail -60 "$OUT/gltest-jvm.log"
cp "$LOGS/launcher.log" "$OUT/gltest-launcher.log" 2>/dev/null
cp ~/Library/Logs/DiagnosticReports/HTS*.ips "$OUT/" 2>/dev/null
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
grep -q '"ok" : true' "$OUT/gltest.json" 2>/dev/null
