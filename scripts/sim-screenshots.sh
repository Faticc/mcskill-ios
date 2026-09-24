#!/bin/bash
# Installs the simulator build and takes screenshots of every screen and window: the login, then
# the demo account (--demo) with each window opened by --screen. Copies the app's own log.
# Usage: scripts/sim-screenshots.sh <HTS.app> <out dir>
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

# simctl saves the portrait framebuffer; the app is landscape, turn it upright
upright() {
    sips -r 270 "$1" >/dev/null
}

shot() {
    local name="$1"
    shift
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
    sleep 5
    xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
    upright "$OUT/$name.png"
    echo "shot $name"
}

# The first start also has to register the app and fonts; give it longer
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
sleep 8
xcrun simctl io "$UDID" screenshot "$OUT/01-login.png" >/dev/null
upright "$OUT/01-login.png"
echo "shot 01-login"

shot 02-home --demo
shot 03-menu --demo --screen menu
shot 04-settings --demo --screen settings
shot 05-help --demo --screen help
shot 06-mods --demo --screen mods
shot 07-progress --demo --screen progress
shot 08-unavailable --demo --screen unavailable
shot 09-mfa --demo --screen mfa
shot 10-totp --demo --screen totp
shot 11-java --demo --screen java
shot 12-probe --demo --screen probe
shot 13-sync --demo --screen sync

DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
cp "$DATA/Documents/logs/launcher.log" "$OUT/launcher.log" || echo "no app log"
xcrun simctl terminate "$UDID" "$BUNDLE" || true
