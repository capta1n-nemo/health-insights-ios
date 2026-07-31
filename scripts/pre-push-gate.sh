#!/usr/bin/env bash
#
# PreToolUse hook: refuse a `git push` that has not passed the gate.
#
# ## Why this is a hook and not a rule
#
# `CLAUDE.md` has said "run ./scripts/verify.sh --tests before every push" for a
# long time, and it is a good rule that depends entirely on the model choosing to
# follow it. On 2026-07-31 a red CI push happened anyway, and — worse — the whole
# handover protocol failed to fire for an entire session because its trigger was
# three literal phrases the user never happened to say.
#
# The lesson recorded in `docs/efficiency-log.md` is that **a ceremony that
# depends on being invoked will be skipped**. A hook is not invoked by the model;
# the harness runs it. That is the whole difference.
#
# Reads the tool call on stdin, and emits a PreToolUse JSON decision. Exit 0
# always — the decision is carried in the JSON, not in the exit code, so a bug in
# this script cannot silently block every push.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 0

deny() {
    # `permissionDecision: deny` blocks the tool call and shows the reason.
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
        "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
    exit 0
}

allow() {
    printf '{"suppressOutput":true}\n'
    exit 0
}

input=$(cat 2>/dev/null || true)

# Decide from the command itself rather than trusting the hook's `if` filter.
#
# The filter is declared as `if: "Bash(git push*)"` in settings.json and this
# gate was still invoked on an ordinary `cat`, which would have run the full test
# suite on every shell command in the session. Whether that is a version
# difference or a misreading of the syntax does not much matter: a hook that
# fires on everything is a hook that gets deleted, so the script decides for
# itself and the filter is left in place as an optimisation only.
command=$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))
except Exception:
    print("")
' 2>/dev/null || true)

case "$command" in
    # Only a real push. `--dry-run` changes nothing on the remote, and `--help`
    # is not a push at all.
    *--help*|*--dry-run*) allow ;;
    *"git push"*) ;;
    *) allow ;;
esac

if ! output=$(./scripts/verify.sh --tests 2>&1); then
    # The tail is what a reader needs; the full run is long and mostly the test
    # roster scrolling past.
    detail=$(printf '%s' "$output" | grep -E 'error:|does not mention|Rules reference|half-done|stale|✗' | head -20)
    [ -z "$detail" ] && detail=$(printf '%s' "$output" | tail -20)
    deny "The pre-push gate failed — ./scripts/verify.sh --tests did not pass, so this push would put a red commit on main and deploy.yml would install nothing.

$detail

Fix it and push again. If the failure is genuinely unrelated to this change, say so explicitly in your reply rather than working around the gate."
fi

allow
