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
CONTAINER="$(xcrun simctl get_app_container "$SIM_ID" edu.neu.lumen data)"
# Per-run markers are sourced from the SAME exact packaging allowlist.
while IFS= read -r CHECK; do
  rm -f "$CONTAINER/Documents/$CHECK"
done < <(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from package_ui_preview import CHECKS; print("\n".join(CHECKS))' "$ROOT/scripts")
rm -f "$CONTAINER/Documents/download-save.txt"
wait_ui_marker() {
  local NAME="$1" LIMIT="${2:-120}"
  for _ in $(seq 1 "$LIMIT"); do
    if [[ -f "$CONTAINER/Documents/$NAME" ]]; then break; fi
    sleep 1
  done
  if [[ ! -f "$CONTAINER/Documents/$NAME" ]]; then
    echo "Missing current simulator check: $NAME" >&2
    exit 1
  fi
  cp "$CONTAINER/Documents/$NAME" "$OUTPUT/$NAME"
  cat "$OUTPUT/$NAME"
  python3 -c 'from pathlib import Path; import sys; t=Path(sys.argv[1]).read_text(); assert t.startswith("PASS:") and not any(s.startswith("FAIL:") for s in t.splitlines())' "$OUTPUT/$NAME"
}
python3 "$ROOT/scripts/ui_fixture_server.py" "$PREVIEW/fixtures" > "$OUTPUT/server.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" || true' EXIT
xcrun simctl status_bar "$SIM_ID" override --time "9:41" --batteryState charged --batteryLevel 100
xcrun simctl ui "$SIM_ID" appearance light
for SCREEN in home home-nanhu schedule services grades mooc chaoxing card profile favorites holidays calendar live-activity live-activity-custom native-payment native-vpn native-affairs native-mail; do
  xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen "--screen=$SCREEN"
  sleep 3
  xcrun simctl io "$SIM_ID" screenshot "$OUTPUT/$SCREEN-light.png"
done

# Actual production shared lower-region views, not a drawn Dynamic Island mock.
# All widths are 330/350/370pt with 100pt lower regions; captions explicitly exclude system/device claims.
for KIND in nextCourse cardBalance netBalance electricBalance assignments planner dayOverview academicOverview custom ax-stale; do
  xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen "--screen=live-expanded-$KIND"
  sleep 3
  xcrun simctl io "$SIM_ID" screenshot "$OUTPUT/live-expanded-$KIND-light.png"
done

# Actual native academic pages with explicit DEBUG-only account-scoped synthetic seed.
for SCREEN in academic-center academic-calendar academic-plan; do
  xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen "--screen=$SCREEN"
  wait_ui_marker "$SCREEN-screenshot.txt" 60
  sleep 1
  xcrun simctl io "$SIM_ID" screenshot "$OUTPUT/$SCREEN-light.png"
done

# Use the production reader and content world in REAL WKWebView with synthetic localhost identity.
xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen --academic-web-sync-checks
wait_ui_marker academic-web-sync-checks.txt 120

# Host REAL shared views and REAL metric Layout/Text and assert actual rendered sibling bounds.
xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen --live-activity-layout-checks
wait_ui_marker live-activity-layout-checks.txt 180

# Existing real running download list, not a static mock.
xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen --screen=downloads
for _ in $(seq 1 60); do
  if [[ -f "$CONTAINER/Documents/download-screenshot.txt" ]]; then break; fi
  sleep 0.25
done
cp "$CONTAINER/Documents/download-screenshot.txt" "$OUTPUT/download-screenshot.txt"
python3 -c 'from pathlib import Path; import sys; assert Path(sys.argv[1]).read_text().startswith("PASS:")' "$OUTPUT/download-screenshot.txt"
sleep 1
xcrun simctl io "$SIM_ID" screenshot "$OUTPUT/downloads-light.png"

xcrun simctl ui "$SIM_ID" appearance dark
xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen --screen=home
sleep 3
xcrun simctl io "$SIM_ID" screenshot "$OUTPUT/home-dark.png"
for DARK_SCREEN in profile live-activity; do
  xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen "--screen=$DARK_SCREEN"
  sleep 3
  xcrun simctl io "$SIM_ID" screenshot "$OUTPUT/$DARK_SCREEN-dark.png"
done
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

xcrun simctl ui "$SIM_ID" appearance light
xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen --download-checks
for _ in $(seq 1 120); do
  if [[ -f "$CONTAINER/Documents/download-checks.txt" ]]; then break; fi
  sleep 1
done
cp "$CONTAINER/Documents/download-checks.txt" "$OUTPUT/download-checks.txt"
cat "$OUTPUT/download-checks.txt"
python3 -c 'from pathlib import Path; import sys; assert Path(sys.argv[1]).read_text().startswith("PASS:")' "$OUTPUT/download-checks.txt"

# Real process termination between a completed WKDownload and an unfinished one.
xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen --download-save-check
for _ in $(seq 1 200); do
  if [[ -f "$CONTAINER/Documents/download-save.txt" ]]; then break; fi
  sleep 0.1
done
cp "$CONTAINER/Documents/download-save.txt" "$OUTPUT/download-save.txt"
python3 -c 'from pathlib import Path; import sys; assert Path(sys.argv[1]).read_text().startswith("READY:")' "$OUTPUT/download-save.txt"
xcrun simctl terminate "$SIM_ID" edu.neu.lumen
xcrun simctl launch "$SIM_ID" edu.neu.lumen --download-restore-check
for _ in $(seq 1 60); do
  if [[ -f "$CONTAINER/Documents/download-restore.txt" ]]; then break; fi
  sleep 0.25
done
cp "$CONTAINER/Documents/download-restore.txt" "$OUTPUT/download-restore.txt"
cat "$OUTPUT/download-restore.txt"
python3 -c 'from pathlib import Path; import sys; assert Path(sys.argv[1]).read_text().startswith("PASS:")' "$OUTPUT/download-restore.txt"

xcrun simctl ui "$SIM_ID" appearance light
xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen --live-activity-data-checks
for _ in $(seq 1 30); do
  if [[ -f "$CONTAINER/Documents/live-activity-data-checks.txt" ]]; then break; fi
  sleep 1
done
cp "$CONTAINER/Documents/live-activity-data-checks.txt" "$OUTPUT/live-activity-data-checks.txt"
cat "$OUTPUT/live-activity-data-checks.txt"
python3 -c 'from pathlib import Path; import sys; assert Path(sys.argv[1]).read_text().startswith("PASS:")' "$OUTPUT/live-activity-data-checks.txt"

# 真正终止并重新启动 App，验证 iOS Keychain 跨进程保存与清除会话。
for STAGE in save restore; do
  xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen "--learning-${STAGE}-check"
  for _ in $(seq 1 60); do
    if [[ -f "$CONTAINER/Documents/learning-${STAGE}.txt" ]]; then break; fi
    sleep 1
  done
  cp "$CONTAINER/Documents/learning-${STAGE}.txt" "$OUTPUT/learning-${STAGE}.txt"
  cat "$OUTPUT/learning-${STAGE}.txt"
  grep -q "^PASS:" "$OUTPUT/learning-${STAGE}.txt"
done

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
# Capture the actual SpringBoard-expanded island, not the app-hosted preview.
swiftc -warnings-as-errors "$ROOT/scripts/check_system_island.swift" -o "$PREVIEW/system-island-check" 2>&1 | tee "${RUNNER_TEMP}/system-island-tests.log"
for KIND in nextCourse custom electricBalance; do
  rm -f "$CONTAINER/Documents/system-island-ready.txt" "$CONTAINER/Documents/system-island-sent.txt"
  xcrun simctl launch --terminate-running-process "$SIM_ID" edu.neu.lumen "--system-island=$KIND"
  for _ in $(seq 1 120); do
    if [[ -f "$CONTAINER/Documents/system-island-ready.txt" ]]; then break; fi
    sleep 0.25
  done
  grep -q "^READY:" "$CONTAINER/Documents/system-island-ready.txt"
  xcrun simctl launch "$SIM_ID" com.apple.Preferences
  for _ in $(seq 1 120); do
    if [[ -f "$CONTAINER/Documents/system-island-sent.txt" ]]; then break; fi
    sleep 0.1
  done
  cat "$CONTAINER/Documents/system-island-sent.txt"
  grep -q "^PASS:" "$CONTAINER/Documents/system-island-sent.txt"
  sleep 0.8
  xcrun simctl io "$SIM_ID" screenshot "$OUTPUT/system-island-$KIND.png"
  "$PREVIEW/system-island-check" "$OUTPUT/system-island-$KIND.png" "$KIND" 2>&1 | tee -a "$OUTPUT/system-island-checks.txt" | tee -a "${RUNNER_TEMP}/system-island-tests.log"
  xcrun simctl terminate "$SIM_ID" edu.neu.lumen || true
done

python3 "$ROOT/scripts/package_ui_preview.py" "$OUTPUT"
