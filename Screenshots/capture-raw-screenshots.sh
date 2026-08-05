#!/bin/bash
#
# Captures the raw App Store screenshots from the Simulator.
#
#   ./capture-raw-screenshots.sh            # all five tools
#   ./capture-raw-screenshots.sh 03 05      # only these
#
# Then run ./make-store-screenshots.sh to add captions and framing.
#
# Each tool is opened directly via the DIY_START_TAB environment variable
# (honoured only in Simulator builds), so no UI automation is needed. The tools
# without hardware in the Simulator — level, scanner, torch, ruler — publish a
# representative state under `#if targetEnvironment(simulator)`, so what lands
# here is the real UI rather than an empty or "hardware required" screen.

set -euo pipefail
cd "$(dirname "$0")"

DEVICE="${DEVICE:-iPhone 17 Pro Max}"   # 6.9" — 1320x2868, the size App Store Connect wants
BUNDLE_ID="io.cttech.diycompanion"
DERIVED="${DERIVED:-$(mktemp -d)/dd}"
EXPECTED="1320x2868"

# tab index : output filename
shot_for() {
  case "$1" in
    01) echo "0:01-spirit-level.png" ;;
    02) echo "1:02-wall-scanner.png" ;;
    03) echo "2:03-torch.png" ;;
    04) echo "3:04-noise-meter.png" ;;
    05) echo "4:05-ruler.png" ;;
    *)  echo "" ;;
  esac
}

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then targets=(01 02 03 04 05); fi

echo "Booting ${DEVICE}..."
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true

# A fixed status bar keeps the set consistent: 09:41, full bars, full battery.
xcrun simctl status_bar "$DEVICE" override \
  --time "09:41" --cellularBars 4 --wifiBars 3 --batteryState charged --batteryLevel 100

echo "Building..."
xcodebuild build \
  -project ../DIYCompanion.xcodeproj \
  -scheme DIYCompanion \
  -destination "platform=iOS Simulator,name=${DEVICE}" \
  -derivedDataPath "$DERIVED" >/dev/null

APP="$(find "$DERIVED/Build/Products" -name "DIYCompanion.app" -maxdepth 3 | head -1)"
[ -n "$APP" ] || { echo "Could not find built .app under $DERIVED"; exit 1; }
xcrun simctl install "$DEVICE" "$APP"

for id in "${targets[@]}"; do
  spec="$(shot_for "$id")"
  [ -n "$spec" ] || { echo "  skipping unknown target '$id'"; continue; }
  tab="${spec%%:*}"
  out="${spec##*:}"

  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
  # SIMCTL_CHILD_ prefix is required: simctl does not pass the shell environment
  # to the launched app, it forwards only variables named this way.
  # The tools animate into their representative state, so let them settle.
  SIMCTL_CHILD_DIY_START_TAB="$tab" xcrun simctl launch "$DEVICE" "$BUNDLE_ID" >/dev/null
  sleep 4
  xcrun simctl io "$DEVICE" screenshot --type=png "$out" >/dev/null 2>&1

  size="$(magick identify -format "%wx%h" "$out")"
  if [ "$size" != "$EXPECTED" ]; then
    echo "  ✗ ${out} is ${size}, expected ${EXPECTED} — wrong simulator?"
    exit 1
  fi
  echo "  ✓ ${out}  ${size}"
done

xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
echo
echo "Done. Now run ./make-store-screenshots.sh to caption and frame them."
