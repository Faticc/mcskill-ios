#!/bin/bash
# Installs the simulator build, takes screenshots of the login screen and of the demo server list,
# and copies the app's own log. Usage: scripts/sim-screenshots.sh <HTS.app> <out dir>
set -euo pipefail

APP="$1"
OUT="$2"
BUNDLE=ru.hts.launcher
mkdir -p "$OUT"

# Newest iOS runtime, first iPhone in it
UDID=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
best = None
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if ".iOS-" not in runtime:
        continue
    for d in devices:
        if d.get("isAvailable") and d["name"].startswith("iPhone"):
            if best is None or runtime > best[0]:
                best = (runtime, d["udid"], d["name"])
            break
print(best[1])
print(best[2] + " / " + best[0], file=sys.stderr)
')
echo "Simulator $UDID"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"

xcrun simctl launch "$UDID" "$BUNDLE"
sleep 8
xcrun simctl io "$UDID" screenshot "$OUT/1-login.png"
xcrun simctl terminate "$UDID" "$BUNDLE" || true

xcrun simctl launch "$UDID" "$BUNDLE" --demo
sleep 6
xcrun simctl io "$UDID" screenshot "$OUT/2-servers-demo.png"

DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
cp "$DATA/Documents/logs/launcher.log" "$OUT/launcher.log" || echo "no app log"
xcrun simctl terminate "$UDID" "$BUNDLE" || true
