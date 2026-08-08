#!/usr/bin/env bash
#
# **Did the build we just installed actually survive launch on the phone?**
#
# `deploy-status.sh` says *installed*, which is a statement about signing and
# copying, not about running. On 2026-08-09 a build reported `installed` and
# then died on every launch — a new mandatory `@Model` column the store could
# not migrate — and nothing in the pipeline noticed, because:
#
#   - the test suite cannot reach CoreData's migration validation;
#   - CI builds and never runs the app;
#   - a fresh simulator install has no store to migrate, so the broken build
#     launches happily there. It did. That is how the wrong conclusion got
#     reached before the device was asked.
#
# So this asks the device. It launches the installed app with the console
# attached, watches for a fixed window, and fails on a fatal error, a CoreData
# store failure, or a crash signal.
#
# Signal 15 is expected and is *not* a failure: it is this script terminating
# the console session at the end of the window.
#
#   ./scripts/device-smoke.sh              # default 25s watch
#   ./scripts/device-smoke.sh 40           # longer watch
#
set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"

watch_seconds="${1:-25}"
bundle="com.jasonsalway.healthinsights"

# Match the UUID by shape, not by column: both the Name and the Model columns
# contain spaces ("iPhone (not a rogue access point)", "iPhone 16 Pro"), so any
# positional field is wrong for some devices — it picked an ECID the first time.
device=$(xcrun devicectl list devices 2>/dev/null \
    | grep 'available (paired)' \
    | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
    | head -1)
if [ -z "$device" ]; then
    printf '\033[33m!\033[0m No paired, available device — cannot smoke-test the phone.\n'
    printf '  This is the only check that can see a launch-time store failure.\n'
    exit 2
fi

log=$(mktemp -t device-smoke)
xcrun devicectl device process launch \
    --device "$device" --console --terminate-existing "$bundle" > "$log" 2>&1 &
pid=$!
for _ in $(seq 1 "$watch_seconds"); do
    kill -0 $pid 2>/dev/null || break
    perl -e 'select(undef,undef,undef,1)'
done
kill $pid 2>/dev/null
wait $pid 2>/dev/null

if ! grep -q "Launched application" "$log"; then
    printf '\033[31m✗\033[0m The app never launched.\n'
    sed -n '1,20p' "$log"
    exit 1
fi

# `signal 15` is our own kill at the end of the window. Anything else is a crash.
if grep -qiE "Fatal error|CoreData: error|Store failed to load" "$log" \
   || grep -qE "terminated due to signal (4|5|6|9|10|11)\b" "$log"; then
    printf '\033[31m✗\033[0m The app died on the phone after launching.\n\n'
    grep -iE "Fatal error|CoreData: error|reason|attribute|terminated due to signal" "$log" \
        | head -12 | sed 's/^/    /'
    printf '\n    Full log: %s\n' "$log"
    exit 1
fi

printf '\033[32m✓\033[0m Ran on the phone for %ss with no fatal error.\n' "$watch_seconds"
rm -f "$log"
