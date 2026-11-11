#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREVIEW="${RUNNER_TEMP}/NEU-Lumen-ui-validation"
OUTPUT="$ROOT/build/ui-preview"
# Never package stale screenshots from a previous attempt.
rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"
python3 "$ROOT/scripts/prepare_ui_validation.py" "$PREVIEW"
SIM_ID="$(xcrun simctl list devices available -j | python3 -c 'import sys,json; d=json.load(sys.stdin)["devices"]; print(next((v["udid"] for k in sorted(d,reverse=True) for v in d[k] if "iOS" in k and v["name"].startswith("iPhone")), ""))')"
if [[ -z "$SIM_ID" ]]; then
  echo "No available iPhone simulator" >&2
  exit 1
fi
xcrun simctl list devices available -j | python3 -c '
import json, sys
all_devices = json.load(sys.stdin)["devices"]
for runtime, devices in all_devices.items():
    for device in devices:
        if device["udid"] == sys.argv[1]:
            print(json.dumps({"name": device["name"], "runtime": runtime, "udid": device["udid"]}))
            sys.exit(0)
sys.exit("Selected simulator is missing")
' "$SIM_ID" > "$OUTPUT/simulator-device.json"
xcrun simctl boot "$SIM_ID" || true
if ! xcrun simctl bootstatus "$SIM_ID" -b; then
  echo "Simulator failed to become ready" >&2
  exit 1
fi
# Simulator securityd reads the Mach-O simulated-entitlements section. Keep
# the app unsigned and embed that identity at link time, as simulator builds do.
cat > "$PREVIEW/simulator.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>edu.neu.lumen</string>
<key>keychain-access-groups</key><array><string>edu.neu.lumen</string></array>
</dict></plist>
PLIST
xcodebuild build -project "$PREVIEW/NEU-Lumen.xcodeproj" -scheme NEU-Lumen \
  -configuration Debug -sdk iphonesimulator -destination "id=$SIM_ID,arch=$(uname -m)" \
  -derivedDataPath "$PREVIEW/DerivedData" CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO \
  "OTHER_LDFLAGS=\$(inherited) -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker $PREVIEW/simulator.entitlements" \
  > "$OUTPUT/simulator-build.log" 2>&1
APP_PATH="$PREVIEW/DerivedData/Build/Products/Debug-iphonesimulator/NEU-Lumen.app"
python3 "$ROOT/scripts/check_live_activity_bundle.py" "$APP_PATH"
xcrun simctl install "$SIM_ID" "$APP_PATH"
python3 "$ROOT/scripts/ui_fixture_server.py" "$PREVIEW/fixtures" > "$OUTPUT/server.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" || true' EXIT
xcrun simctl status_bar "$SIM_ID" override --time "9:41" --batteryState charged --batteryLevel 100
xcrun simctl ui "$SIM_ID" appearance light
for SCREEN in home home-nanhu schedule services grades mooc chaoxing card profile favorites holidays calendar; do
  xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen "--screen=$SCREEN"
  sleep 3
  xcrun simctl io "$SIM_ID" screenshot "$OUTPUT/$SCREEN-light.png"
done

xcrun simctl ui "$SIM_ID" appearance dark
xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen --screen=home
sleep 3
xcrun simctl io "$SIM_ID" screenshot "$OUTPUT/home-dark.png"
xcrun simctl ui "$SIM_ID" appearance light
xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen --screen=browser --browser-checks
CONTAINER="$(xcrun simctl get_app_container "$SIM_ID" edu.neu.lumen data)"
for _ in $(seq 1 120); do
  if [[ -f "$CONTAINER/Documents/browser-checks.txt" ]]; then break; fi
  sleep 1
done
xcrun simctl io "$SIM_ID" screenshot "$OUTPUT/browser-light.png"
xcrun simctl ui "$SIM_ID" appearance dark
sleep 2
xcrun simctl io "$SIM_ID" screenshot "$OUTPUT/browser-dark.png"
cp "$CONTAINER/Documents/browser-checks.txt" "$OUTPUT/browser-checks.txt"
cat "$OUTPUT/browser-checks.txt"
grep -q "^PASS:" "$OUTPUT/browser-checks.txt"

# 真正终止并重新启动 App，验证 iOS Keychain 跨进程保存与清除会话。
for STAGE in save restore; do
  xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen "--session-${STAGE}-check"
  for _ in $(seq 1 30); do
    if [[ -f "$CONTAINER/Documents/session-${STAGE}.txt" ]]; then break; fi
    sleep 1
  done
  cp "$CONTAINER/Documents/session-${STAGE}.txt" "$OUTPUT/session-${STAGE}.txt"
  cat "$OUTPUT/session-${STAGE}.txt"
  grep -q "^PASS:" "$OUTPUT/session-${STAGE}.txt"
done

xcrun simctl ui "$SIM_ID" appearance light
xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen --live-activity-checks
for _ in $(seq 1 90); do
  if [[ -f "$CONTAINER/Documents/live-activity-checks.txt" ]]; then break; fi
  sleep 1
done
cp "$CONTAINER/Documents/live-activity-checks.txt" "$OUTPUT/live-activity-checks.txt"
cat "$OUTPUT/live-activity-checks.txt"
grep -q "^PASS:" "$OUTPUT/live-activity-checks.txt"
xcrun simctl launch "$SIM_ID" com.apple.Preferences
sleep 3
xcrun simctl io "$SIM_ID" screenshot "$OUTPUT/native-live-activity.png"
python3 "$ROOT/scripts/package_ui_preview.py" "$OUTPUT"
