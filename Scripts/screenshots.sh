#!/bin/bash
#
# Captures the App Store screenshots, for every platform and every locale we
# ship them in, straight into fastlane/screenshots/ where `deliver` picks them
# up.
#
#   Scripts/screenshots.sh                        # everything, every locale
#   Scripts/screenshots.sh --platform ios         # one platform
#   Scripts/screenshots.sh --locales en-US,ja     # a couple of locales
#
# How it works: the app is launched with an in-memory store seeded from
# Tests/Screenshots/Fixtures and with its clock pinned (see ScreenshotSeed and
# TideClock), so the same tide curve comes out of every run; a UI test walks it
# through the screens and saves a PNG of each. Simulator screenshots already
# come out at exactly the pixel sizes App Store Connect demands — 1320x2868 for
# the 6.9" iPhone, 2064x2752 for the 13" iPad, 3840x2160 for Vision Pro,
# 416x496 for the watch — so nothing is resized. Only the Mac, which has no
# simulator and is photographed window-and-all, is fitted to 2880x1800.
#
# Anything the run cannot do it says out loud rather than quietly shipping a
# gap: see the summary it prints at the end.
set -euo pipefail

cd "$(dirname "$0")/.."
readonly ROOT="$PWD"
readonly WORK_DIR_NAME="io.ngs.Tides.screenshots"
# The macOS UI test runner is sandboxed: its home is this container, and that is
# the one directory both it and this script can write to. Derived from the
# TidesScreenshots bundle id in Project.swift — Xcode appends `.xctrunner`.
readonly MAC_RUNNER_BUNDLE_ID="io.ngs.TidesScreenshots.xctrunner"
readonly APP_BUNDLE_ID="io.ngs.Tides"
# Simulators the run creates for itself, so it never shoots on a device you are
# signed into iCloud on.
readonly DEVICE_PREFIX="Shiomi Shot"
# Path to the compiled Mac compositor, set once the run needs it.
compositor=""
readonly DERIVED_DATA="$ROOT/.build/screenshots"
readonly FIXTURES="$ROOT/Tests/Screenshots/Fixtures"
readonly OUTPUT_ROOT="$ROOT/fastlane/screenshots"

# The instant every shot is taken at. A spring morning, with the tide mid-fall
# at Tokyo Bay and the moon a young crescent — and 9:41, the time Apple puts on
# its own devices. Bump it when the screenshots should look newer; nothing else
# depends on it.
readonly FIXED_DATE="${TIDES_FIXED_DATE:-2026-03-21T00:41:00Z}"

# The locales the screenshots are shot in. The app ships in 36, but App Store
# Connect falls back to the primary language wherever a localization has no
# screenshots of its own, so these are the ones worth the wall-clock time.
# Each entry is <App Store locale>:<language>:<region>: the language picks the
# app's strings, the region its date and number formats.
readonly DEFAULT_LOCALES=(
  "en-US:en:US"
  "ja:ja:JP"
  "zh-Hans:zh-Hans:CN"
  "ko:ko:KR"
  "de-DE:de:DE"
  "fr-FR:fr:FR"
  "es-ES:es:ES"
)

# Which simulator stands in for each platform, and which App Store size that
# produces. iPhone 6.9" and iPad 13" are the only iOS sizes Apple still asks
# for; the smaller classes are scaled from them automatically.
readonly IPHONE_DEVICE="iPhone 17 Pro Max"
readonly IPAD_DEVICE="iPad Pro 13-inch (M5)"
readonly VISION_DEVICE="Apple Vision Pro"
readonly WATCH_DEVICE="Apple Watch Series 11 (46mm)"

# macOS screenshots are of the app's window, composed onto a backdrop at the
# App Store's largest accepted Mac size. Drop an image at MAC_BACKDROP to use
# your own wallpaper; without one the compositor paints its sea gradient.
readonly MAC_WIDTH=2880
readonly MAC_HEIGHT=1800
readonly MAC_BACKDROP="$ROOT/fastlane/screenshots/mac/backdrop.png"

platforms=(ios mac visionos watchos)
locales=("${DEFAULT_LOCALES[@]}")
failures=()

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

# --- arguments ---------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform | --platforms)
      IFS=',' read -r -a platforms <<<"$2"
      shift 2
      ;;
    --locales)
      requested=()
      IFS=',' read -r -a wanted <<<"$2"
      for want in "${wanted[@]}"; do
        if [[ "$want" == "all" ]]; then
          requested=("${DEFAULT_LOCALES[@]}")
          break
        fi
        match=""
        for known in "${DEFAULT_LOCALES[@]}"; do
          [[ "${known%%:*}" == "$want" ]] && match="$known"
        done
        if [[ -z "$match" ]]; then
          echo "error: unknown locale '$want'. Known: ${DEFAULT_LOCALES[*]%%:*}" >&2
          exit 2
        fi
        requested+=("$match")
      done
      locales=("${requested[@]}")
      shift 2
      ;;
    -h | --help) usage 0 ;;
    *)
      echo "error: unknown option '$1'" >&2
      usage 2
      ;;
  esac
done

# --- helpers -----------------------------------------------------------------

# Everything below writes into the derived-data directory — logs, the scratch
# files `device_udid` reads its answer back from, the compiled compositor. Make
# it once, here, before any of them runs: on a clean checkout it does not exist
# yet, and a redirection into a missing directory fails before the command it
# was meant to capture ever starts.
mkdir -p "$DERIVED_DATA"

# Prints the udid of the simulator to shoot on, creating it if this is the
# first run.
#
# The run gets its own devices — named "<prefix> <model>" — rather than the ones
# you develop on. A simulator you have used is signed into iCloud and will
# interrupt the shoot with an Apple Account prompt (which also puts your email
# address in the screenshot); a freshly created one never is. They are kept
# between runs, so only the first run pays for the creation. Delete them from
# Xcode whenever you like: the next run makes them again.
device_udid() {
  local model="$1"
  xcrun simctl list --json |
    MODEL="$model" PREFIX="$DEVICE_PREFIX" python3 -c '
import json, os, sys
model, prefix = os.environ["MODEL"], os.environ["PREFIX"]
catalogue = json.load(sys.stdin)
name = f"{prefix} {model}"

for entries in catalogue["devices"].values():
    for device in entries:
        if device["name"] == name and device.get("isAvailable", True):
            print(device["udid"])
            sys.exit(0)

kinds = [k for k in catalogue["devicetypes"] if k["name"] == model]
if not kinds:
    sys.exit(f"no simulator model named {model!r} is installed")
kind = kinds[0]["identifier"]

# The newest runtime this model can actually run.
runtimes = [
    r for r in catalogue["runtimes"]
    if r["isAvailable"] and kind in r.get("supportedDeviceTypes", []) or
    r["isAvailable"] and any(d["identifier"] == kind for d in r.get("supportedDeviceTypes", []))
]
if not runtimes:
    sys.exit(f"no installed runtime supports {model!r}")
runtimes.sort(key=lambda r: [int(p) for p in r["version"].split(".")])
print("create", kind, runtimes[-1]["identifier"], sep="\t")
' >"$DERIVED_DATA/device.txt" 2>"$DERIVED_DATA/device.err" || {
    cat "$DERIVED_DATA/device.err" >&2
    return 1
  }

  local answer
  answer="$(cat "$DERIVED_DATA/device.txt")"
  if [[ "$answer" == create* ]]; then
    local kind runtime
    kind="$(echo "$answer" | cut -f2)"
    runtime="$(echo "$answer" | cut -f3)"
    log "creating a clean simulator: $DEVICE_PREFIX $model" >&2
    xcrun simctl create "$DEVICE_PREFIX $model" "$kind" "$runtime"
  else
    echo "$answer"
  fi
}

# The directory the test and this script meet in: config in, PNGs out.
#
# On a simulator that is the device's own data container — a plain directory on
# this Mac, which is what makes the handover possible at all. The macOS test
# runner is sandboxed, so there the meeting point is its container, which is
# where its `NSHomeDirectory()` points.
work_dir() {
  local udid="${1:-}"
  if [[ -n "$udid" ]]; then
    echo "$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Caches/$WORK_DIR_NAME"
  else
    echo "$HOME/Library/Containers/$MAC_RUNNER_BUNDLE_ID/Data/Library/Caches/$WORK_DIR_NAME"
  fi
}

# Writes the config the test reads: which language, which instant, which
# locations, and whether the host takes the picture.
write_config() {
  local dir="$1" language="$2" region="$3" external="$4"
  mkdir -p "$dir"
  rm -f "$dir"/*.png "$dir"/capture-request-* "$dir"/capture-done-*
  env LOCALE_KEY="$5" LANGUAGE="$language" REGION="$region" \
    EXTERNAL="$external" FIXTURES="$FIXTURES" FIXED_DATE="$FIXED_DATE" \
    python3 "$ROOT/Scripts/screenshot_config.py" >"$dir/config.json"
}

# Collects what the test produced into the tree `deliver` uploads from.
#
# Files are named <order>_<screen>_<device>.png: deliver decides *which* store
# size a file belongs to by its pixel dimensions, and only uses the name to
# order the shots within that size — so the iPhone and iPad files can share a
# directory, as they always have here.
collect() {
  local dir="$1" platform="$2" locale="$3" suffix="$4"
  local destination="$OUTPUT_ROOT/$platform/$locale"
  mkdir -p "$destination"
  local collected=0
  for file in "$dir"/*.png; do
    [[ -e "$file" ]] || continue
    local base
    base="$(basename "$file" .png)"
    cp "$file" "$destination/${base}_${suffix}.png"
    collected=$((collected + 1))
  done
  if [[ $collected -eq 0 ]]; then
    failures+=("$platform/$locale/$suffix: the run produced no screenshots")
    return 1
  fi
  log "$platform/$locale: $collected shots ($suffix)"
}

# Compiles the Mac compositor once per run and prints the binary's path.
build_compositor() {
  local source="$ROOT/Scripts/compose_mac_screenshot.swift"
  local binary="$DERIVED_DATA/compose_mac_screenshot"
  if [[ ! -x "$binary" || "$source" -nt "$binary" ]]; then
    swiftc -O -o "$binary" "$source" >/dev/null
  fi
  echo "$binary"
}

# Boots a simulator and freezes its status bar at the time Apple's own
# marketing shots use. Not supported on the watch, which keeps the real clock.
prepare_simulator() {
  local udid="$1" status_bar="$2"
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  if [[ "$status_bar" == "yes" ]]; then
    xcrun simctl status_bar "$udid" override \
      --time "9:41" \
      --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --cellularMode active --cellularBars 4 \
      --batteryState charged --batteryLevel 100 >/dev/null 2>&1 ||
      warn "could not override the status bar on $udid"
  fi
}

# Runs one capture pass: one scheme, one device, one locale.
#
# Simulators run unsigned builds happily, which keeps the run independent of
# whatever certificates this machine has. macOS does not: an unsigned test
# runner is killed on launch, so there the build signs itself as usual.
run_test() {
  local scheme="$1" destination="$2" log_file="$3"
  local signing=(CODE_SIGNING_ALLOWED=NO)
  if [[ "$destination" == "platform=macOS" ]]; then
    signing=()
  fi
  xcodebuild test \
    -workspace "$ROOT/Tides.xcworkspace" \
    -scheme "$scheme" \
    -destination "$destination" \
    -derivedDataPath "$DERIVED_DATA" \
    ${signing[@]+"${signing[@]}"} \
    >"$log_file" 2>&1
}

# Some screens the test cannot photograph itself, so it asks us to: it drops a
# `capture-request-<name>` file, holds the app still, and waits for
# `capture-done-<name>`. This watches for those requests until the test exits.
#
# Two platforms need it, for different reasons. visionOS simply refuses to
# screenshot from a UI test ("Manual screenshots are not supported"), and only
# `simctl` can. On macOS a UI test *can* screenshot the window, but it flattens
# it: the rounded corners come back filled with black and the system's drop
# shadow is gone. `screencapture` hands back what macOS actually draws — corners
# cut out of the alpha, the real translucent shadow around it — which is what
# gets composed onto the backdrop.
watch_for_captures() {
  local dir="$1" udid="$2" test_pid="$3"
  while kill -0 "$test_pid" 2>/dev/null; do
    for request in "$dir"/capture-request-*; do
      [[ -e "$request" ]] || continue
      local name="${request##*capture-request-}"
      if [[ -n "$udid" ]]; then
        xcrun simctl io "$udid" screenshot --type=png "$dir/$name.png" >/dev/null 2>&1 ||
          warn "simctl could not screenshot $name"
      else
        capture_mac_window "$dir/$name.png" || warn "screencapture could not photograph $name"
      fi
      rm -f "$request"
      touch "$dir/capture-done-$name"
    done
    sleep 0.2
  done
}

# Photographs the app's window, shadow and all, straight off the desktop.
capture_mac_window() {
  local output="$1" window
  window="$("$compositor" --window-id "$APP_BUNDLE_ID")" || return 1
  # -l: that window alone. No -o: keep the drop shadow. -x: no shutter sound.
  screencapture -x -l "$window" "$output"
}

# --- platforms ---------------------------------------------------------------

shoot_simulator() {
  local platform="$1" scheme="$2" device="$3" suffix="$4" status_bar="$5" external="$6"
  # The watch app is part of the iOS app on the store, and `deliver` sorts the
  # files by pixel size, so its shots belong in the iOS directory.
  local destination_platform="$platform"
  [[ "$platform" == "watchos" ]] && destination_platform="ios"
  local udid
  if ! udid="$(device_udid "$device")"; then
    failures+=("$platform: no simulator named '$device' is installed")
    warn "skipping $platform: no simulator named '$device'"
    return
  fi
  prepare_simulator "$udid" "$status_bar"
  local dir
  dir="$(work_dir "$udid")"

  for entry in "${locales[@]}"; do
    IFS=':' read -r locale language region <<<"$entry"
    log "$platform · $device · $locale"
    write_config "$dir" "$language" "$region" "$external" "$locale"

    local log_file="$DERIVED_DATA/$platform-$locale.log"
    if [[ "$external" == "true" ]]; then
      run_test "$scheme" "id=$udid" "$log_file" &
      local test_pid=$!
      watch_for_captures "$dir" "$udid" "$test_pid"
      wait "$test_pid" || {
        failures+=("$platform/$locale: the capture run failed — see $log_file")
        warn "$platform/$locale failed; see $log_file"
        continue
      }
    else
      if ! run_test "$scheme" "id=$udid" "$log_file"; then
        failures+=("$platform/$locale: the capture run failed — see $log_file")
        warn "$platform/$locale failed; see $log_file"
        continue
      fi
    fi
    collect "$dir" "$destination_platform" "$locale" "$suffix" || true
  done
}

shoot_mac() {
  local dir
  dir="$(work_dir)"
  compositor="$(build_compositor)"
  for entry in "${locales[@]}"; do
    IFS=':' read -r locale language region <<<"$entry"
    log "mac · $locale"
    write_config "$dir" "$language" "$region" "true" "$locale"

    local log_file="$DERIVED_DATA/mac-$locale.log"
    run_test "TidesScreenshots" "platform=macOS" "$log_file" &
    local test_pid=$!
    watch_for_captures "$dir" "" "$test_pid"
    if ! wait "$test_pid"; then
      failures+=("mac/$locale: the capture run failed — see $log_file")
      warn "mac/$locale failed; see $log_file"
      continue
    fi
    # A UI test can only photograph the window's own rectangle, so the shots
    # arrive as bare windows: square-cornered, shadowless, at whatever size the
    # window was. Each is composed onto the backdrop at the store's size.
    for file in "$dir"/*.png; do
      [[ -e "$file" ]] || continue
      "$compositor" "$file" "$file" "$MAC_WIDTH" "$MAC_HEIGHT" "$MAC_BACKDROP"
    done
    collect "$dir" "mac" "$locale" "desktop" || true
  done
}

# --- run ---------------------------------------------------------------------

for platform in "${platforms[@]}"; do
  case "$platform" in
    ios)
      shoot_simulator ios TidesScreenshots "$IPHONE_DEVICE" iphone yes false
      shoot_simulator ios TidesScreenshots "$IPAD_DEVICE" ipad yes false
      ;;
    mac) shoot_mac ;;
    visionos)
      # The status bar cannot be overridden on visionOS, and the shot has no
      # room for one anyway.
      shoot_simulator visionos TidesScreenshotsVision "$VISION_DEVICE" vision no true
      ;;
    watchos)
      # `simctl status_bar override` is rejected on watchOS, so the watch shots
      # carry the simulator's real clock. Nothing else can be done about it.
      shoot_simulator watchos TidesWatchScreenshots "$WATCH_DEVICE" watch no false
      ;;
    *)
      echo "error: unknown platform '$platform'" >&2
      exit 2
      ;;
  esac
done

echo
if [[ ${#failures[@]} -gt 0 ]]; then
  warn "${#failures[@]} part(s) of the run did not produce screenshots:"
  for failure in "${failures[@]}"; do
    printf '  - %s\n' "$failure" >&2
  done
  exit 1
fi

log "Done. Review $OUTPUT_ROOT, then upload with:"
echo "      bundle exec fastlane ios deliver_screenshots"
echo "      bundle exec fastlane mac deliver_screenshots"
echo "      bundle exec fastlane visionos deliver_screenshots"
