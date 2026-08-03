#!/usr/bin/env bash
#
# Recover the self-hosted Actions runner on the deploy Mac.
#
# Run this **on the Mac**, not in a sandbox. The repo is checked out at
#   ~/actions-runner/health-app-ios/health-insights-ios/health-insights-ios
# and that path is stable between runs, so:
#
#   cd ~/actions-runner/health-app-ios/health-insights-ios/health-insights-ios
#   ./scripts/fix-runner.sh
#
# **`./scripts/runner-doctor.sh` is the diagnosis; this is the repair.** Doctor
# tells an unclaimed job from an unreachable phone by reading the deploy refs.
# This one fixes the specific fault below and asserts the fix took.
#
# ⚠️ Written on 2026-08-03 **without checking that runner-doctor.sh already
# existed**, which is precisely the class CLAUDE.md ▸ "Check before you Write"
# is about. One `ls scripts/ | grep runner` would have cost nothing. The two do
# genuinely different jobs and both are kept — but the division is written here
# because nobody derived it, it was rationalised afterwards.
#
# ── Why this exists ───────────────────────────────────────────────────────────
#
# On 2026-08-03 four deploys in a row (dabfd3a, 4a5137b, 18969e4, 4d095b4) died
# in the *Checkout* step with:
#
#   ##[error]Missing file at path: <runner>/_temp/_runner_file_commands/set_output_<uuid>
#   The file '<runner>/_diag/pages/<id>_<id>_1.log' already exists.
#
# Two `Runner.Listener` processes were alive in one installation directory,
# each clearing `_temp` and `_diag` under the other. xcodebuild never ran, so
# none of it was the code, the signing or the phone — but "deploy failed" reads
# as all three, and a whole session went into establishing that it was none.
#
# ⚠️ **This runner is a LaunchAgent, so `svc.sh` must NOT be run with sudo.**
# `deploy.yml`'s setup note used to say `sudo ./svc.sh stop`; on this Mac that
# answers "Must not run with sudo", the stop silently does not happen, and the
# duplicate listener you were trying to clear is still there afterwards. Three
# password prompts were spent on that.
#
# Two smaller things worth not rediscovering:
#   • `Load failed: 5: Input/output error` from `./svc.sh start` means the
#     service is *already loaded*, not that starting failed. Stop first.
#   • Do not paste command lists with trailing `#` comments into this Mac's
#     shell — zsh here does not have INTERACTIVE_COMMENTS set, so the comment
#     becomes arguments (`grep: expect: No such file or directory`).

set -uo pipefail

RUNNER_DIR="${RUNNER_DIR:-$HOME/actions-runner}"

listeners() { pgrep -fl 'Runner.Listener' 2>/dev/null; }
count() { pgrep -f 'Runner.Listener' 2>/dev/null | wc -l | tr -d ' '; }

if [ ! -d "$RUNNER_DIR" ]; then
    echo "No runner installation at $RUNNER_DIR"
    echo "Set RUNNER_DIR=/path/to/actions-runner and re-run."
    exit 1
fi

echo "Runner directory: $RUNNER_DIR"
echo "Listeners before: $(count)"
listeners

cd "$RUNNER_DIR" || exit 1

# No sudo. See the note above — with sudo this is a no-op that looks like a fix.
echo
echo "Stopping the service..."
./svc.sh stop || echo "  (svc.sh stop returned non-zero; continuing to the kill)"

# The service stop only ends the listener it owns. A second one started by hand
# with ./run.sh is exactly what this script exists to clear, and svc.sh does not
# know about it.
echo "Killing any remaining listener..."
pkill -f 'Runner.Listener' 2>/dev/null || true
sleep 2

remaining=$(count)
if [ "$remaining" != "0" ]; then
    echo
    echo "⚠️  $remaining listener(s) still alive after the kill:"
    listeners
    echo "Something is restarting them. Check for a second runner installation"
    echo "and for extra plists:  ls ~/Library/LaunchAgents/actions.runner.*"
    exit 1
fi

# Stale page logs are what produce "already exists" on the next job. Safe to
# delete: _diag is diagnostics only, and the runner recreates the directory.
echo "Clearing stale diagnostics..."
rm -rf "$RUNNER_DIR/_diag/pages"

echo "Starting the service..."
./svc.sh start || true
sleep 3

final=$(count)
echo
echo "Listeners after: $final"
listeners
echo

if [ "$final" = "1" ]; then
    echo "✅ Exactly one listener. Re-run the deploy:"
    echo "   Actions ▸ Deploy to iPhone over Wi-Fi ▸ Run workflow"
    exit 0
fi

echo "❌ Expected exactly one listener, found $final."
if [ "$final" = "0" ]; then
    echo "The service did not come up. Try:  cd $RUNNER_DIR && ./run.sh"
    echo "and leave that Terminal window open."
else
    echo "More than one listener means a second installation or a stray ./run.sh."
    echo "Check:  ls ~/Library/LaunchAgents/actions.runner.*"
fi
exit 1
