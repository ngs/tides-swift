#!/bin/bash
# Launches the watch app in a simulator with saved locations seeded from the
# screenshot fixtures — no paired iPhone, no iCloud account, no network.
#
# The watch normally receives its locations through CloudKit, which a
# simulator does not have; this reuses the screenshot run's seeding path
# (`TIDES_SCREENSHOT_SEED`, see ScreenshotSeed) to hand the app an in-memory
# store at launch. `simctl launch` forwards environment variables that carry
# the `SIMCTL_CHILD_` prefix.
#
# Usage: Scripts/watch-preview.sh ["Apple Watch Series 11 (46mm)"]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:-Apple Watch Series 11 (46mm)}"
BUNDLE_ID="io.ngs.Tides.watchkitapp"
DERIVED="$ROOT/.build/watch-preview"

# The same simulator name exists once per installed runtime, which xcodebuild
# refuses as ambiguous — resolve one UDID: a booted match first, else the
# newest runtime's.
UDID="$(DEVICE_NAME="$DEVICE" python3 - <<'EOF'
import json
import os
import subprocess

name = os.environ["DEVICE_NAME"]
listing = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "-j"]))
matches = []
for runtime, devices in listing["devices"].items():
    if "watchOS" not in runtime:
        continue
    for device in devices:
        if device["name"] == name:
            matches.append((device["state"] == "Booted", runtime, device["udid"]))
if not matches:
    raise SystemExit(f"no available watch simulator named {name!r}")
matches.sort(reverse=True)
print(matches[0][2])
EOF
)"

SEED="$(FIXTURES="$ROOT/Tests/Screenshots/Fixtures" python3 - <<'EOF'
import base64
import json
import os
import pathlib

fixtures = pathlib.Path(os.environ["FIXTURES"])
spec = json.loads((fixtures / "locations.json").read_text())
locations = [
    {
        "name": entry["names"].get("en-US") or next(iter(entry["names"].values())),
        "latitude": entry["latitude"],
        "longitude": entry["longitude"],
        "parameters": json.loads((fixtures / entry["parameters"]).read_text()),
    }
    for entry in spec["locations"]
]
print(base64.b64encode(json.dumps({"locations": locations}).encode()).decode())
EOF
)"

echo "Building TidesWatch for '$DEVICE' ($UDID)…"
xcodebuild build \
  -workspace "$ROOT/Tides.xcworkspace" \
  -scheme TidesWatch \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  -quiet

APP="$DERIVED/Build/Products/Debug-watchsimulator/TidesWatch.app"
[[ -d "$APP" ]] || { echo "error: $APP not found" >&2; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
SIMCTL_CHILD_TIDES_SCREENSHOT_SEED="$SEED" \
  xcrun simctl launch "$UDID" "$BUNDLE_ID"
echo "Launched with the locations seeded from Tests/Screenshots/Fixtures."
