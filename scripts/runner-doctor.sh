#!/usr/bin/env bash
# Diagnose why a push to main did not reach the phone.
#
# **Run this ON THE MAC**, not in a Claude sandbox — everything it checks is
# local to the machine hosting the GitHub Actions runner.
#
#     ./scripts/runner-doctor.sh
#
# ## Why this exists
#
# `deploy.yml` is `runs-on: self-hosted`, so a push to `main` only installs if
# the runner on this Mac claims the job. When it doesn't, the symptom is
# indistinguishable from a phone problem: CI is green, `main` has moved, and
# `deploy-status.sh` says "no verdict yet" forever. On 2026-08-03 four commits
# sat unclaimed for hours while the phone was hotspotting the Mac *and* plugged
# in by cable — the network was never the issue.
#
# The tell is in the refs: a deploy that ran and failed writes
# `refs/deploy/failed/<sha>`. **No ref at all means the job never ran.** That
# points at the runner, not at the device — and those need completely different
# fixes, which is the confusion this script exists to end.

set -uo pipefail

pass() { printf '\033[32m  ok\033[0m   %s\n' "$1"; }
fail() { printf '\033[31m FAIL\033[0m  %s\n' "$1"; FAILED=1; }
warn() { printf '\033[33m warn\033[0m  %s\n' "$1"; }
note() { printf '       %s\n' "$1"; }
head() { printf '\n\033[1m%s\033[0m\n' "$1"; }

FAILED=0
PINNED_DEFAULT="26642940-2E82-5266-8527-0A0351F9D4D8"
DEVICE="${IPHONE_DEVICE_ID:-$PINNED_DEFAULT}"

head "1. The runner process"

# The listener is the thing that claims jobs. Everything else can be perfect
# and nothing will deploy without it.
if pgrep -f 'Runner.Listener' >/dev/null 2>&1; then
    pass "Runner.Listener is running (pid $(pgrep -f 'Runner.Listener' | head -1))"
else
    fail "Runner.Listener is NOT running — this alone explains an unclaimed deploy."
    note "Find the runner directory (commonly ~/actions-runner) and either:"
    note "  cd ~/actions-runner && ./run.sh            # foreground, quickest to test"
    note "  cd ~/actions-runner && sudo ./svc.sh start # if installed as a service"
fi

RUNNER_DIR=""
for candidate in "$HOME/actions-runner" "$HOME/Developer/actions-runner" \
                 "/opt/actions-runner" "$HOME/runner"; do
    [ -d "$candidate" ] && RUNNER_DIR="$candidate" && break
done

if [ -n "$RUNNER_DIR" ]; then
    pass "Runner directory: $RUNNER_DIR"
    if [ -x "$RUNNER_DIR/svc.sh" ]; then
        STATUS="$("$RUNNER_DIR/svc.sh" status 2>&1 | head -5)"
        note "svc.sh status:"
        printf '       %s\n' "$STATUS"
    fi
else
    warn "Couldn't find the runner directory in the usual places."
    note "If it lives elsewhere, the checks below still work; only this hint is missing."
fi

head "2. Can the runner reach GitHub?"

# A runner behind a hotspot is usually fine — it makes an *outbound* long poll,
# so no inbound reachability is needed. Captive portals are the exception.
if curl -sS --max-time 10 -o /dev/null -w '%{http_code}' https://api.github.com >/dev/null 2>&1; then
    pass "api.github.com reachable"
else
    fail "Cannot reach api.github.com — the runner cannot claim jobs without it."
    note "On a hotspot, check the phone still has data and no captive portal is in the way."
fi

if [ -n "$RUNNER_DIR" ] && [ -d "$RUNNER_DIR/_diag" ]; then
    LATEST_LOG="$(ls -t "$RUNNER_DIR"/_diag/Runner_*.log 2>/dev/null | head -1)"
    if [ -n "$LATEST_LOG" ]; then
        AGE_MIN=$(( ( $(date +%s) - $(stat -f %m "$LATEST_LOG" 2>/dev/null || echo 0) ) / 60 ))
        if [ "$AGE_MIN" -lt 30 ]; then
            pass "Runner log written ${AGE_MIN}m ago — the listener is alive and polling"
        else
            warn "Newest runner log is ${AGE_MIN}m old — the listener may be wedged"
            note "Restarting it is safe: sudo $RUNNER_DIR/svc.sh stop && sudo $RUNNER_DIR/svc.sh start"
        fi
        note "Last few lines:"
        tail -3 "$LATEST_LOG" | sed 's/^/       /'
    fi
fi

head "3. Xcode and devicectl"

if xcode-select -p >/dev/null 2>&1; then
    pass "Xcode command line tools: $(xcode-select -p)"
else
    fail "xcode-select is not pointed at an Xcode install."
    note "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

if xcrun devicectl --version >/dev/null 2>&1; then
    pass "devicectl available"
else
    fail "devicectl missing — deploy.yml installs the app with it."
fi

head "4. The phone"

TMP_JSON="$(mktemp)"
xcrun devicectl list devices --json-output "$TMP_JSON" >/dev/null 2>&1 || true

if [ -s "$TMP_JSON" ]; then
    python3 - "$TMP_JSON" "$DEVICE" <<'PY'
import json, sys
path, wanted = sys.argv[1], sys.argv[2]
try:
    devices = json.load(open(path)).get("result", {}).get("devices", [])
except Exception as exc:
    print(f"\033[31m FAIL\033[0m  Could not parse the device list: {exc}")
    sys.exit(0)

if not devices:
    print("\033[31m FAIL\033[0m  No devices paired with this Mac at all.")
    print("       Pair in Xcode ▸ Window ▸ Devices and Simulators, and tick")
    print("       \"Connect via network\" so it works without the cable too.")
    sys.exit(0)

found = None
for device in devices:
    props = device.get("hardwareProperties", {})
    ident = device.get("identifier", "")
    name = props.get("marketingName") or device.get("deviceProperties", {}).get("name", "?")
    state = device.get("connectionProperties", {}).get("tunnelState", "?")
    transport = device.get("connectionProperties", {}).get("transportType", "?")
    mark = "→" if ident == wanted else " "
    print(f"       {mark} {name}  [{ident}]  tunnel={state} transport={transport}")
    if ident == wanted:
        found = (state, transport)

print()
if found:
    print(f"\033[32m  ok\033[0m   The pinned device IS paired (transport={found[1]}).")
    print("       A tunnel state of 'unavailable' or 'disconnected' is NOT a problem —")
    print("       devicectl brings it up on demand during install. deploy.yml stopped")
    print("       treating that as fatal on 2026-07-31 for exactly this reason.")
else:
    print("\033[31m FAIL\033[0m  The pinned device is not in the paired list.")
    print(f"       Looking for: {wanted}")
    print("       Either pair it, or set the IPHONE_DEVICE_ID repo secret to one above.")
PY
else
    fail "devicectl returned no device list."
fi
rm -f "$TMP_JSON"

head "Verdict"

if [ "$FAILED" -eq 0 ]; then
    echo "  Nothing here is broken. If a deploy is still unclaimed, look at whether the"
    echo "  runner is *busy* or *offline* in GitHub ▸ Settings ▸ Actions ▸ Runners."
else
    echo "  Fix the FAILs above, then re-run the workflow — no new push is needed."
    echo "  A queued deploy installs the newest commit on main when it is claimed."
fi

echo
echo "  Remember: a push is not an install. Only refs/deploy/passed/<sha> means"
echo "  the app reached the phone — ci-status.sh cannot tell you that."
