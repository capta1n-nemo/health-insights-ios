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
#   ./scripts/simulator.sh logs [minutes] [--all]
#                                          # the app's own diagnostic lines;
#                                          # --all for the framework chatter too
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
# Outside the working copy on purpose. This repo lives in the user's iCloud
# Drive, which syncs by folder and ignores `.gitignore` entirely — so build
# products written under `build/` are uploaded to their iCloud account and
# churned by `fileproviderd`. Measured at 766 MB across `build/` on 2026-08-04,
# during a session that also watched `fileproviderd` sit at 150% CPU.
DERIVED="${SIM_DERIVED_DATA:-$HOME/Library/Caches/health-insights/simulator}"
SHOTS="${SIM_SHOT_DIR:-build/simulator-shots}"

# --- One slot per worktree, because agents genuinely do run in parallel -------
#
# ⚠️ **Found the hard way on 2026-08-07, and it fails SILENTLY.** Every worktree
# shared one derived-data path, installed the same bundle id onto the same
# simulator UDID, and named shots `<short-sha>-<time>.png` — and the sha is
# identical across worktrees built from the same base commit. So agent A could
# screenshot agent B's build with nothing in the output saying so.
#
# It cost a worktree agent several rounds: it verified its chevrons, then two
# later screenshots showed them gone. The giveaway was a Blood Pressure card
# still rendering `= No change`, a string that agent's own commit had already
# replaced. **A screenshot that is confidently of the wrong build is worse than
# no screenshot** — it is evidence pointing the wrong way, and this repo uses
# screenshots precisely for the claims tests cannot make.
#
# `--git-dir` vs `--git-common-dir` is the canonical worktree test (matching
# `verify.sh`): the same path in a main working tree, different in every linked
# one. Pattern-matching for `/worktrees/` would be fooled by a checkout that
# merely lives in a directory of that name.
WORKTREE_TAG=""
if [ "$(git rev-parse --git-dir 2>/dev/null)" \
   != "$(git rev-parse --git-common-dir 2>/dev/null)" ]; then
    wt_root=$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")
    WORKTREE_TAG="$(basename "$wt_root")"
    DERIVED="${SIM_DERIVED_DATA:-$HOME/Library/Caches/health-insights/simulator-$WORKTREE_TAG}"
fi
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

    # **Wait for the boot, and check it happened.**
    #
    # `simctl boot` returns as soon as the request is accepted, so the `install`
    # below used to run against a device still shutting down — and reported
    # "Unable to lookup in current state: Shutdown", which names the *install*
    # and says nothing about the boot that never happened. On 2026-08-04 that
    # cost the first Mac session ten minutes chasing an install problem that did
    # not exist. A step must fail with its own diagnosis, not leave the next one
    # to report a symptom.
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
    if [ "$(xcrun simctl list devices | grep "$udid" | grep -c Booted)" -eq 0 ]; then
        printf '\033[31m✗\033[0m %s\n' "'$device' did not boot." >&2
        printf '%s\n' "The exact reason, from simctl:" >&2
        xcrun simctl boot "$udid" 2>&1 | sed 's/^/    /' >&2
        printf '\n%s\n' "If it says 'launchd_sim ... could not bind to session', the simulator subsystem is wedged. In order of cost:" >&2
        printf '%s\n' "  1. Check the load average — a boot can time out under a post-restart iCloud/Spotlight storm. \`uptime\`" >&2
        printf '%s\n' "  2. Quit Simulator.app, then: killall -9 com.apple.CoreSimulator.CoreSimulatorService" >&2
        printf '%s\n' "  3. Log out and back in, or restart the Mac." >&2
        printf '\n%s\n' "None of this is the app's fault — the build above succeeded. Say so plainly and fall back to CI." >&2
        exit 1
    fi

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
    local tag="${WORKTREE_TAG:+$WORKTREE_TAG-}"
    local out="${1:-$SHOTS/$tag$(git rev-parse --short HEAD)-$(date +%H%M%S).png}"
    xcrun simctl io booted screenshot "$out"
    printf '\033[32mSaved:\033[0m %s\n' "$out"

    # ⚠️ Say WHICH BUILD was on screen, rather than letting the reader infer it.
    # The screenshot cannot show you that it is of somebody else's install; the
    # binary's mtime can. A shot taken before your own build finished, or of a
    # build another worktree installed, is now visible rather than deduced from
    # noticing a string you thought you had changed.
    local udid installed
    udid=$(xcrun simctl list devices booted -j 2>/dev/null \
        | python3 -c 'import json,sys;d=json.load(sys.stdin)["devices"];print(next((x["udid"] for v in d.values() for x in v if x.get("state")=="Booted"),""))' 2>/dev/null || true)
    if [ -n "$udid" ]; then
        installed=$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" app 2>/dev/null || true)
        if [ -n "$installed" ] && [ -e "$installed" ]; then
            printf 'Installed build: %s\n' \
                "$(date -r "$installed" '+%Y-%m-%d %H:%M:%S')"
            printf '  ⚠️ If that is older than your last build, you are looking at a\n'
            printf '     different install — run `simulator.sh run` before believing it.\n'
        fi
    fi
    printf 'Read it with the Read tool — it renders images.\n'
}

# The app's own diagnostic lines — not everything its process emits.
#
# ⚠️ **`process == "HealthInsights"` was the wrong predicate and it hid the
# thing this command exists to show.** `DiagnosticsLog` has mirrored every entry
# to the unified log since 2026-08-06 under the app's own subsystem, and this
# command still could not find one: UIKit, CoreAnimation, RemoteTextInput and
# the keyboard arbiter all log *inside the app's process*, at hundreds of lines
# a second. A measured `logs 10` on a freshly launched app returned eighty lines
# of keyboard geometry and zero from the app. The mirror was working; the filter
# was not (backlog D26).
#
# So the default is the subsystem — which is exactly the set of lines
# `DiagnosticsLog` writes, and nothing else. `--all` restores the old
# process-wide firehose for the rarer case where the framework chatter is the
# thing being read.
cmd_logs() {
    require_darwin
    local minutes=2 predicate="subsystem == \"$BUNDLE_ID\"" what="the app's own diagnostics"
    for arg in "$@"; do
        case "$arg" in
            --all) predicate="process == \"$SCHEME\""; what="everything in the app's process" ;;
            *[!0-9]*) die "Unknown argument '$arg'. Usage: logs [minutes] [--all]" ;;
            *) minutes="$arg" ;;
        esac
    done
    note "Last ${minutes}m — $what"
    local out
    # ⚠️ **`--info` is not optional here, and leaving it off is the other half of
    # why this command looked broken.** `DiagnosticsLog.mirrorToUnifiedLog` maps
    # ok / null / info to `Logger.info` and only `fail` to `Logger.error`, and
    # `log show` omits INFO-level messages unless asked. So the one command a
    # session runs to read the app's diagnostics was, by construction, showing
    # only the failures — and on a run where nothing failed, nothing at all.
    out="$(xcrun simctl spawn booted log show \
        --last "${minutes}m" \
        --info \
        --style compact \
        --predicate "$predicate" 2>/dev/null | tail -80)"
    # `log show` prints its header whatever happens, so "no output" looks the
    # same as "one blank result" unless it is said out loud. A silent empty
    # answer here is what makes a session start clicking through Settings.
    if [ "$(printf '%s\n' "$out" | grep -cv '^Timestamp\|^$')" -eq 0 ]; then
        printf '%s\n' "$out"
        printf '\n\033[33mNo app diagnostic lines in the last %sm.\033[0m\n' "$minutes"
        printf '%s\n' "Every launch writes one ('App: Launched — …'), so an empty answer here means"
        printf '%s\n' "the app has not launched in that window. Widen it (./scripts/simulator.sh logs 30),"
        printf '%s\n' "or relaunch with ./scripts/simulator.sh run. Add --all for framework chatter too."
        return 0
    fi
    printf '%s\n' "$out"
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
    logs)   shift; cmd_logs "$@" ;;
    reset)  shift; cmd_reset "${1:-}" ;;
    *)      die "Unknown command '$1'. One of: doctor build run shot logs reset" ;;
esac
