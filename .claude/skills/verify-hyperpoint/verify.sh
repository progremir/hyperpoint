#!/bin/zsh
# Drives the installed Hyperpoint for verification. Run `verify.sh help` for the commands.
set -euo pipefail

SKILL_DIR=${0:A:h}
REPO=$(git -C "$SKILL_DIR" rev-parse --show-toplevel)
APP="$HOME/Applications/Hyperpoint.app"
PROBE_APP="$HOME/Applications/HyperpointProbe.app"
BIN="$REPO/.verify-bin"
RUN=${HYPERPOINT_VERIFY_RUN:-$(date +%Y%m%d-%H%M%S)}
EVIDENCE="$REPO/.verify-evidence/$RUN"
IDENTITY="Apple Development: Emir Amanbekov (KGBFPV5MVR)"
BUILT_IN='{"Built-In":1,"PrimaryUsagePage":1,"PrimaryUsage":6}'
MAGIC='{"VendorID":0x4C,"ProductID":0x321}'
LOG=/usr/bin/log

mkdir -p "$EVIDENCE" "$BIN"

running_pid() { pgrep -f "$APP/Contents/MacOS/Hyperpoint" | head -1 || true; }

menu_state() {
  "$LOG" show --last "${1:-2m}" --info --style compact \
    --predicate 'subsystem == "dev.emir.hyperpoint" && category == "menu"' 2>/dev/null | grep 'state=' | tail -1
}

wait_ready() {
  local deadline=$((SECONDS + ${1:-30})) line
  while (( SECONDS < deadline )); do
    line=$(menu_state 1m)
    if [[ -n $line && $line == *"Hyperpoint[$(running_pid)"* && $line != *"Applying…"* ]]; then
      echo "$line"; return 0
    fi
    sleep 1
  done
  echo "not ready after ${1:-30}s: $(menu_state 1m)" >&2; return 1
}

quit_app() {
  local pid; pid=$(running_pid)
  [[ -z $pid ]] && { echo "Hyperpoint not running"; return 0; }
  osascript -e 'quit app "Hyperpoint"' >/dev/null
  for _ in {1..20}; do kill -0 "$pid" 2>/dev/null || { echo "quit pid $pid"; return 0; }; sleep 0.5; done
  echo "pid $pid did not exit" >&2; return 1
}

key_maps() {
  for m in "$BUILT_IN" "$MAGIC"; do
    echo "== hidutil --matching $m"
    hidutil property --matching "$m" --get UserKeyMapping
  done
}

build_helpers() {
  [[ "$BIN/hidpp-state" -nt "$SKILL_DIR/helpers/hidpp-state.swift" ]] ||
    swiftc -swift-version 5 -O -o "$BIN/hidpp-state" "$SKILL_DIR/helpers/hidpp-state.swift"
  [[ "$BIN/window-heights" -nt "$SKILL_DIR/helpers/window-heights.swift" ]] ||
    swiftc -swift-version 5 -O -o "$BIN/window-heights" "$SKILL_DIR/helpers/window-heights.swift"
  [[ "$BIN/tab-switches" -nt "$SKILL_DIR/helpers/tab-switches.swift" ]] ||
    swiftc -swift-version 5 -O -o "$BIN/tab-switches" "$SKILL_DIR/helpers/tab-switches.swift"
  [[ "$BIN/set-up" -nt "$SKILL_DIR/helpers/set-up.swift" ]] ||
    swiftc -swift-version 5 -O -o "$BIN/set-up" "$SKILL_DIR/helpers/set-up.swift"
  if [[ ! "$PROBE_APP/Contents/MacOS/HyperpointProbe" -nt "$SKILL_DIR/helpers/probe.swift" ]]; then
    swiftc -swift-version 5 -O -framework IOKit -o "$BIN/HyperpointProbe" "$SKILL_DIR/helpers/probe.swift"
    mkdir -p "$PROBE_APP/Contents/MacOS"
    cp "$BIN/HyperpointProbe" "$PROBE_APP/Contents/MacOS/HyperpointProbe"
    /usr/libexec/PlistBuddy -c 'Clear dict' -c 'Add :CFBundleIdentifier string dev.emir.hyperpoint.probe' \
      -c 'Add :CFBundleName string HyperpointProbe' -c 'Add :CFBundleExecutable string HyperpointProbe' \
      -c 'Add :CFBundlePackageType string APPL' -c 'Add :LSUIElement bool true' "$PROBE_APP/Contents/Info.plist" >/dev/null 2>&1 ||
      /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string dev.emir.hyperpoint.probe' -c 'Add :CFBundleName string HyperpointProbe' \
        -c 'Add :CFBundleExecutable string HyperpointProbe' -c 'Add :CFBundlePackageType string APPL' -c 'Add :LSUIElement bool true' \
        "$PROBE_APP/Contents/Info.plist" >/dev/null
    codesign --force -s "$IDENTITY" --identifier dev.emir.hyperpoint.probe "$PROBE_APP" 2>/dev/null
  fi
}

probe() {
  local mode=$1 out=$2
  : > "$out"
  open -W --stdout "$out" "$PROBE_APP" --args "$mode"
  if grep -q 'accessibilityTrusted=false' "$out"; then
    echo "HyperpointProbe lacks Accessibility. Ask the user to switch it on in System Settings › Privacy & Security › Accessibility." >&2
    return 2
  fi
}

case ${1:-help} in
  build)
    quit_app
    (cd "$REPO" && scripts/bundle.sh) 2>&1 | tee "$EVIDENCE/bundle.log"
    ;;
  launch)
    open "$APP" --args "${@:2}"
    wait_ready "${HYPERPOINT_READY_SECONDS:-30}" | tee "$EVIDENCE/launch.txt"
    ;;
  quit)
    quit_app | tee "$EVIDENCE/quit.txt"
    key_maps > "$EVIDENCE/key-maps-after-quit.txt"
    ;;
  doctor)
    {
      echo "repo HEAD: $(git -C "$REPO" rev-parse --short HEAD) $(git -C "$REPO" branch --show-current)"
      echo "app binary: $(stat -f '%Sm' "$APP/Contents/MacOS/Hyperpoint") (newest commit: $(git -C "$REPO" log -1 --format=%cd))"
      echo "pid: $(running_pid || true)"
      codesign -d -r- "$APP" 2>&1 | grep designated
      codesign -d -r- "$APP" 2>&1 | grep -q cdhash && echo "BAD: designated requirement pins a cdhash; grants reset every build"
      echo "menu: $(menu_state 10m)"
      pgrep -lf 'Karabiner-Core-Service|BetterMouse' | sed 's/^/conflicting: /' || echo "conflicting: none"
    } | tee "$EVIDENCE/doctor.txt"
    ;;
  state)
    build_helpers
    { key_maps; echo "== hidpp"; "$BIN/hidpp-state"; } | tee "$EVIDENCE/state.txt"
    ;;
  log)
    "$LOG" show --last "${2:-10m}" --info --style compact --predicate 'subsystem == "dev.emir.hyperpoint"' \
      > "$EVIDENCE/hyperpoint.log" 2>&1
    tail -20 "$EVIDENCE/hyperpoint.log"
    ;;
  hyper-check)
    build_helpers
    local_runs=${2:-8}; fired=0; stuck=0
    for i in $(seq "$local_runs"); do
      probe none "$EVIDENCE/hyper-run-$i.txt" || exit $?
      grep -q 'carbonHotkeyFired=1' "$EVIDENCE/hyper-run-$i.txt" && fired=$((fired + 1))
      grep -q 'modifiersStuckAfter=true' "$EVIDENCE/hyper-run-$i.txt" && stuck=$((stuck + 1))
    done
    echo "hyper hotkey fired $fired/$local_runs, modifiers stuck after $stuck/$local_runs" | tee "$EVIDENCE/hyper-check.txt"
    ;;
  record)
    build_helpers
    mode=${2:?record posted|wheel|senders|hold}
    echo "recording $mode; ask the user to act now (posted/wheel/hold: 40-45 s, senders: 90 s)"
    probe "$mode" "$EVIDENCE/record-$mode.txt" || exit $?
    python3 "$SKILL_DIR/helpers/analyze.py" "$mode" "$EVIDENCE/record-$mode.txt" | tee "$EVIDENCE/record-$mode-summary.txt"
    ;;
  settings-shots)
    build_helpers
    quit_app
    rm -rf "$EVIDENCE/settings"
    "$BIN/window-heights" 120 > "$EVIDENCE/settings-heights.txt" &
    sampler=$!
    open "$APP" --args -snapshotSettings "$EVIDENCE/settings"
    wait_ready "${HYPERPOINT_READY_SECONDS:-30}" >/dev/null
    # The app writes the dark set last, so the shots are done once a dark PNG exists and nothing new has come for 3 s.
    stable=0; count=-1; deadline=$((SECONDS + 120))
    while (( stable < 3 && SECONDS < deadline )); do
      sleep 1
      shots=("$EVIDENCE"/settings/*.png(N)); dark=("$EVIDENCE"/settings/*-dark.png(N))
      if (( ${#dark} > 0 && ${#shots} == count )); then stable=$((stable + 1)); else stable=0; fi
      count=${#shots}
    done
    kill "$sampler" 2>/dev/null || true
    ls "$EVIDENCE/settings"
    echo "window heights: $(awk '{print $2}' "$EVIDENCE/settings-heights.txt" | paste -sd' ' -)"
    ;;
  settings-switches)
    build_helpers
    switches=0
    "$BIN/tab-switches" > "$EVIDENCE/settings-switches.txt" || switches=$?
    grep -E '^(PASS|FAIL|SKIP)|^window moved| pass' "$EVIDENCE/settings-switches.txt" || tail -3 "$EVIDENCE/settings-switches.txt"
    exit $switches
    ;;
  set-up)
    build_helpers
    "$BIN/set-up" "${@:2}" | tee -a "$EVIDENCE/set-up.txt"
    ;;
  evidence)
    echo "$EVIDENCE"
    ;;
  help|*)
    cat <<EOF
verify.sh <command>   (evidence goes to \$REPO/.verify-evidence/\$HYPERPOINT_VERIFY_RUN)
  doctor             build, signature, pid, last menu state, conflicting apps
  build              quit Hyperpoint, scripts/bundle.sh into ~/Applications/Hyperpoint.app
  launch [args]      open the app and wait for a settled menu state
  quit               quit through the app's own quit path, then record key maps
  state              hidutil key maps and read-only HID++ state of the MX
  log [10m]          Hyperpoint's unified log
  hyper-check [8]    post F18 + F16 N times, count ⌘⌃⌥⇧F16 Carbon hotkey fires
  record <mode>      posted | wheel | senders | hold, needs the user to use the mouse
  settings-shots     relaunch with -snapshotSettings, PNG per tab in light and dark, window heights
  settings-switches  every tab switch, Device change and a page past the screen, sampled at 120 Hz
  set-up "<button>" ["<item>"]  press a new device's Set Up button on Devices, or choose an item from its menu
  evidence           print this run's evidence directory
EOF
    ;;
esac
