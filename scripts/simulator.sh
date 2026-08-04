#!/usr/bin/env bash
#
# Drive the iOS Simulator: build, install, launch, screenshot, read the log.
#
# WHY THIS EXISTS
#
# Until 2026-08-03 nothing in this project could see what the app *looked like*.
# The hosted sessions run on Linux with no Xcode, so the app target was compiled
# only by CI and every visual question — does this card appear, is that button
# in the right place, does the empty state say anything — could only be answered
# by deploying to the user's phone and asking them.
#
# That cost a real defect: the Nutrition and Metabolism cards shipped
# **invisible** on 2026-08-03, filtered off the tab by `isWorthShowing` because
# they had no data and declared no unmet requirement. A single simulator launch
# would have caught it in seconds. The user found it instead.
#
# So: a session running in the Claude Code app on the user's Mac can and should
# use this before saying a UI change works.
#
# USAGE
#
#   ./scripts/simulator.sh doctor          # what's installed, what's missing
#   ./scripts/simulator.sh build           # build for the simulator
#   ./scripts/simulator.sh run             # build + boot + install + launch
#   ./scripts/simulator.sh shot [file]     # screenshot the booted simulator
#   ./scripts/simulator.sh logs [minutes]  # the app's own log lines
#   ./scripts/simulator.sh reset --yes     # erase the simulator's data
#
# WHAT IT CANNOT TELL YOU
#
# The Health app does not ship on the simulator, so HealthKit returns nothing
# and every card renders its **empty** state. That is worth checking — it is
# the state a new reader sees, and it is where the invisible-card defect lived —
# but a simulator screenshot says nothing about a chart with data in it, a
# reference band, a scrub read-out or the substance shading. Those still need
# the phone. See `docs/deployment.md` ▸ "The simulator".
#
# THIS DOES NOT REPLACE THE GATE. `./scripts/verify.sh --tests` still runs
# before every push, and CI still compiles the app target. The simulator answers
# a *different* question: what the reader sees.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="HealthInsights.xcodeproj"
SCHEME="HealthInsights"
BUNDLE_ID="com.jasonsalway.healthinsights"
DERIVED="${SIM_DERIVED_DATA:-build/simulator}"
SHOTS="${SIM_SHOT_DIR:-build/simulator-shots}"
# Overridable: `SIM_DEVICE="iPhone 16 Pro" ./scripts/simulator.sh run`
DEVICE="${SIM_DEVICE:-}"

die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
note() { printf '\033[1m%s\033[0m\n' "$*"; }

require_darwin() {
    [ "$(uname -s)" = "Darwin" ] || die \
"This needs macOS with Xcode, and this session is $(uname -s).

A hosted session (Claude Code on the web) runs in a Linux container: no Xcode,
no simctl, no iOS SDK — which is why CI is the only thing that compiles the app
target there. Open this repo in the Claude Code app on the Mac to use the
simulator, and let CI keep gating the hosted sessions."
    command -v xcrun >/dev/null 2>&1 || die "xcrun not found — install Xcode and its command line tools."
}

# The simulator to drive: the caller's choice, else the first available iPhone
# on the newest runtime. Named rather than 'booted' at build time because
# xcodebuild needs a destination before anything is booted.
pick_device() {
    if [ -n "$DEVICE" ]; then echo "$DEVICE"; return; fi
    xcrun simctl list devices available \
        | grep -oE '^ +iPhone [^(]+' \
        | sed 's/^ *//;s/ *$//' \
        | tail -1
}

udid_for() {
    xcrun simctl list devices available \
        | grep -F "$1 (" | head -1 \
        | grep -oE '\([0-9A-F-]{36}\)' | tr -d '()'
}

app_path() {
    echo "$DERIVED/Build/Products/Debug-iphonesimulator/$SCHEME.app"
}

cmd_doctor() {
    require_darwin
    note "Xcode"
    xcodebuild -version 2>/dev/null || die "xcodebuild not usable — check 'xcode-select -p'."
    printf '  developer dir: %s\n' "$(xcode-select -p 2>/dev/null || echo '?')"
    note "iOS runtimes"
    xcrun simctl list runtimes available | grep -i ios || \
        die "No iOS runtime installed. Xcode ▸ Settings ▸ Components ▸ install an iOS 18 runtime (the app's deployment target is iOS 18.0)."
    note "Simulators"
    local device; device="$(pick_device)"
    [ -n "$device" ] || die "No available iPhone simulator. Create one in Xcode ▸ Settings ▸ Components."
    printf '  will use: %s\n' "$device"
    note "Swift"
    swift --version 2>/dev/null | head -1 || printf '  (none on PATH — source scripts/swift-env.sh)\n'
    printf '\n\033[32mReady.\033[0m Next: ./scripts/simulator.sh run\n'
}

cmd_build() {
    require_darwin
    local device; device="$(pick_device)"
    [ -n "$device" ] || die "No available iPhone simulator — run ./scripts/simulator.sh doctor"
    note "Building $SCHEME for $device…"
    # `CODE_SIGNING_ALLOWED=NO` because a simulator build needs no signature —
    # the same flag the CI build uses, and the reason this works without the
    # Developer Program membership the device build needs.
    xcodebuild build \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -destination "platform=iOS Simulator,name=$device" \
        -derivedDataPath "$DERIVED" \
        CODE_SIGNING_ALLOWED=NO \
        | grep -E "error:|warning: (unused|deprecated)|BUILD (SUCCEEDED|FAILED)" || true
    [ -d "$(app_path)" ] || die "No app bundle at $(app_path) — the build failed. Re-run without the grep filter to see why."
    printf '\033[32mBuilt:\033[0m %s\n' "$(app_path)"
}

cmd_run() {
    require_darwin
    cmd_build
    local device udid; device="$(pick_device)"; udid="$(udid_for "$device")"
    [ -n "$udid" ] || die "Could not resolve a UDID for '$device'."
    # `boot` fails when already booted, which is not an error here.
    xcrun simctl boot "$udid" 2>/dev/null || true
    open -a Simulator 2>/dev/null || true
    xcrun simctl install "$udid" "$(app_path)"
    xcrun simctl launch "$udid" "$BUNDLE_ID" >/dev/null
    printf '\033[32mLaunched\033[0m %s on %s\n' "$BUNDLE_ID" "$device"
    printf 'Screenshot it with: ./scripts/simulator.sh shot\n'
}

cmd_shot() {
    require_darwin
    mkdir -p "$SHOTS"
    # Named by the caller, or by the commit being looked at — a screenshot with
    # no provenance is the same trap as a chart with no caption.
    local out="${1:-$SHOTS/$(git rev-parse --short HEAD)-$(date +%H%M%S).png}"
    xcrun simctl io booted screenshot "$out"
    printf '\033[32mSaved:\033[0m %s\n' "$out"
    printf 'Read it with the Read tool — it renders images.\n'
}

cmd_logs() {
    require_darwin
    local minutes="${1:-2}"
    xcrun simctl spawn booted log show \
        --last "${minutes}m" \
        --style compact \
        --predicate "process == \"$SCHEME\"" 2>/dev/null | tail -80
}

cmd_reset() {
    require_darwin
    [ "${1:-}" = "--yes" ] || die "This erases the simulator's data — every logged reading, every setting. Re-run with --yes if that is what you want."
    local udid; udid="$(udid_for "$(pick_device)")"
    xcrun simctl shutdown "$udid" 2>/dev/null || true
    xcrun simctl erase "$udid"
    printf '\033[32mErased.\033[0m The next run starts at onboarding.\n'
}

case "${1:-doctor}" in
    doctor) cmd_doctor ;;
    build)  cmd_build ;;
    run)    cmd_run ;;
    shot)   shift; cmd_shot "${1:-}" ;;
    logs)   shift; cmd_logs "${1:-2}" ;;
    reset)  shift; cmd_reset "${1:-}" ;;
    *)      die "Unknown command '$1'. One of: doctor build run shot logs reset" ;;
esac
