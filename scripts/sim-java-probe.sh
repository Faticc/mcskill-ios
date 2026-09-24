#!/bin/bash
# Starts each bundled JVM in the booted simulator (`--probe-java N`, one app process per Java: iOS
# allows one JVM per process) and collects jvm.log, the report and crash reports.
# The app must carry JREs packed with `scripts/pack-jre.sh <app> <cache> simulator`.
# Usage: scripts/sim-java-probe.sh <HTS.app> <out dir>
set -uo pipefail

APP="$1"
OUT="$2"
BUNDLE=ru.hts.launcher
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)
echo "Simulator $UDID"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
xcrun simctl install "$UDID" "$APP" || exit 1
LOGS="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/Documents/logs"
mkdir -p "$LOGS"

failed=0
for v in 8 17 25; do
    rm -f "$LOGS/jvm.log" "$LOGS/jvm-probe.json" "$LOGS/jvm-probe.running"
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" --probe-java "$v" >/dev/null
    status="timeout"
    for _ in $(seq 1 90); do
        sleep 2
        if [ -f "$LOGS/jvm-probe.json" ]; then status="done"; break; fi
        if ! pgrep -f "HTS.app/HTS" >/dev/null; then status="app died"; break; fi
    done
    echo "===== Java $v: $status"
    [ -f "$LOGS/jvm-probe.json" ] && cat "$LOGS/jvm-probe.json" && cp "$LOGS/jvm-probe.json" "$OUT/probe-$v.json"
    if [ -f "$LOGS/jvm.log" ]; then
        cp "$LOGS/jvm.log" "$OUT/jvm-$v.log"
        echo "--- jvm.log (tail)"
        tail -40 "$LOGS/jvm.log"
    fi
    grep -q '"ok" : true' "$OUT/probe-$v.json" 2>/dev/null || failed=1
    xcrun simctl io "$UDID" screenshot "$OUT/probe-$v.png" >/dev/null 2>&1 && sips -r 270 "$OUT/probe-$v.png" >/dev/null
done

cp "$LOGS/launcher.log" "$OUT/launcher.log" 2>/dev/null
cp ~/Library/Logs/DiagnosticReports/HTS*.ips "$OUT/" 2>/dev/null
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
exit $failed
