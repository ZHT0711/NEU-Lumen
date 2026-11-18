#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT/build/ui-preview"
LOG="${RUNNER_TEMP}/system-island-tests.log"

# Verify the actual captures with host Vision, which runs separately from the
# simulator toolchain, before the same files are packaged for distribution.
PROFILE="${UI_PREVIEW_PROFILE:-full}"
case "$PROFILE" in
  nightly)
    HEADERS=(academic-center native-analysis)
    SCREENS=(card services native-map campus-journey)
    ;;
  full)
    HEADERS=(academic-center native-analysis native-downloads)
    SCREENS=(services services-directory services-art grades mooc chaoxing
      native-payment native-electricity native-bills native-analysis native-map
      indoor-navigation indoor-route indoor-points native-library native-telephone
      native-vpn native-affairs native-mail native-news native-agenda native-downloads
      notifications academic-services academic-exams)
    ;;
  *)
    printf 'Unknown UI preview profile: %s\n' "$PROFILE" >&2
    exit 1
    ;;
esac

WORK="$(mktemp -d "${RUNNER_TEMP}/NEU-Lumen-ocr.XXXXXX")"
OCR="$WORK/system-island-check"
cleanup() {
  rm -f "$OCR"
  rmdir "$WORK"
}
trap cleanup EXIT
swiftc -warnings-as-errors "$ROOT/scripts/check_system_island.swift" -o "$OCR" 2>&1 | tee "$LOG"

for SCREEN in "${HEADERS[@]}"; do
  "$OCR" "$OUTPUT/$SCREEN-light.png" "screen:$SCREEN" 2>&1 \
    | tee "$OUTPUT/service-title-$SCREEN.txt" | tee -a "$LOG"
done
for MODE in light dark; do
  cat "$OUTPUT/services-panel-$MODE-state.txt" > "$OUTPUT/services-panel-$MODE-checks.txt"
  "$OCR" "$OUTPUT/services-art-$MODE.png" screen:services-art 2>&1 \
    | tee -a "$OUTPUT/services-panel-$MODE-checks.txt" | tee -a "$LOG"
done

: > "$OUTPUT/screen-content-checks.txt"
for SCREEN in "${SCREENS[@]}"; do
  "$OCR" "$OUTPUT/$SCREEN-light.png" "screen:$SCREEN" 2>&1 \
    | tee -a "$OUTPUT/screen-content-checks.txt" | tee -a "$LOG"
done
if [[ "$PROFILE" == full ]]; then
  : > "$OUTPUT/system-island-checks.txt"
  for KIND in nextCourse custom electricBalance; do
    "$OCR" "$OUTPUT/system-island-$KIND.png" "$KIND" 2>&1 \
      | tee -a "$OUTPUT/system-island-checks.txt" | tee -a "$LOG"
  done
fi

python3 "$ROOT/scripts/package_ui_preview.py" "$OUTPUT"
