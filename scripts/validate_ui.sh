#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREVIEW="${RUNNER_TEMP}/NEU-Lumen-ui-validation"
OUTPUT="$ROOT/build/ui-preview"
mkdir -p "$OUTPUT"
python3 "$ROOT/scripts/prepare_ui_validation.py" "$PREVIEW"
SIM_ID="$(xcrun simctl list devices available -j | python3 -c 'import sys,json; d=json.load(sys.stdin)["devices"]; print(next(v["udid"] for k in sorted(d,reverse=True) for v in d[k] if "iOS" in k and v["name"].startswith("iPhone")))')"
xcrun simctl boot "$SIM_ID" || true
xcrun simctl bootstatus "$SIM_ID" -b
xcodebuild build -project "$PREVIEW/NEU-Lumen.xcodeproj" -scheme NEU-Lumen \
  -configuration Debug -sdk iphonesimulator -destination "id=$SIM_ID" \
  -derivedDataPath "$PREVIEW/DerivedData" CODE_SIGNING_ALLOWED=NO > "$OUTPUT/simulator-build.log" 2>&1
# Keychain requires an application identity even in the simulator. The release
# IPA is signed by the installer; give this disposable simulator build its own.
cat > "$PREVIEW/simulator.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>edu.neu.lumen</string>
<key>keychain-access-groups</key><array><string>edu.neu.lumen</string></array>
</dict></plist>
PLIST
codesign --force --sign - --entitlements "$PREVIEW/simulator.entitlements" \
  "$PREVIEW/DerivedData/Build/Products/Debug-iphonesimulator/NEU-Lumen.app"
xcrun simctl install "$SIM_ID" "$PREVIEW/DerivedData/Build/Products/Debug-iphonesimulator/NEU-Lumen.app"
python3 -m http.server 8787 --bind 127.0.0.1 --directory "$PREVIEW/fixtures" > "$OUTPUT/server.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" || true' EXIT
xcrun simctl status_bar "$SIM_ID" override --time "9:41" --batteryState charged --batteryLevel 100
xcrun simctl ui "$SIM_ID" appearance light
for SCREEN in home schedule services grades; do
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
for _ in $(seq 1 60); do
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
