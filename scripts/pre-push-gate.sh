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
    # **A build-database collision is not a failed gate, and must not be
    # worded like one.** The wording below tells the reader to fix their diff
    # and, failing that, to justify pushing anyway — both wrong when the cause
    # is a concurrent build, and on 2026-08-06 that is exactly what happened:
    # the collision's own message is two `error:` lines, so the grep below
    # picked it up and presented it as a broken diff. Checked first, and the
    # whole block is kept rather than grepped, because the actionable part is
    # the instruction to wait rather than the line naming the fault.
    #
    # ⚠️ **Matches verify.sh's own words, not xcodebuild's.** The obvious
    # pattern here is `database is locked`, and it is wrong: verify.sh
    # *replaces* that line with its own message rather than printing it, so
    # grepping for xcodebuild's wording matches nothing and the collision
    # falls through to the "your diff is broken" branch below — the very bug
    # this is here to fix. Caught by canary, 2026-08-06. `Another build
    # holds` is a contract between the two scripts; the raw phrase is kept as
    # a second alternative in case a future verify.sh passes the log through.
    # Herestring, not printf|grep -q — under pipefail that pipeline fails on an
    # EARLY match (grep exits, printf takes SIGPIPE). Cost a red CI on a3d70d6.
    if grep -qE 'Another build holds|database is locked' <<<"$output"; then
        deny "$(printf '%s' "$output" | grep -A3 -E 'Another build holds|database is locked' | head -8)

The gate did not fail — it could not run. Another build holds the same
derived-data path, so nothing about this change has been checked either way.

Wait for the other build to finish and push again. Do not work around this by
skipping the gate: it has verified nothing, so a push now is unverified."
    fi
    # **The same shape, one level down: the app-target tests (D63).**
    #
    # Below, the denial ends "Fix it and push again… if the failure is genuinely
    # unrelated to this change, say so explicitly" — which is the right sentence
    # for a broken diff and the wrong one for a test host that was killed under
    # ten concurrent worktree builds. On 2026-08-07 that wording is what a
    # session had to argue against, and it argued badly: three wrong diagnoses,
    # the last of them "it is pre-existing, push past the gate".
    #
    # ⚠️ **Still a denial.** Nothing here lets an unverified push through — the
    # tests did not run, so the diff is unchecked and the answer is still no.
    # What changes is that the reader is told what to do about it (wait, re-run)
    # rather than sent looking for a defect that is not in their code.
    #
    # Matches `verify.sh`/`app-test-report.sh`'s own words, for the reason the
    # branch above records: the raw xcodebuild phrasing never reaches here.
    # `verify.sh` has already retried once before printing either of these.
    if grep -qE 'This is the MACHINE, not your diff|Zero tests executed' <<<"$output"; then
        deny "$(printf '%s' "$output" | grep -B2 -A6 -E 'This is the MACHINE, not your diff|Zero tests executed' | head -24)

The app-target tests did not report on your diff — and verify.sh already
retried once. This is the machine (backlog D63), not your change.

Nothing about this push has been checked, so it is still a no. Wait for the
other agents' builds to finish and run ./scripts/verify.sh --tests again. Do
not push past this: the gate being usually-environmental is exactly how a real
failure gets pushed through."
    fi
    # The tail is what a reader needs; the full run is long and mostly the test
    # roster scrolling past.
    detail=$(printf '%s' "$output" | grep -E 'error:|does not mention|Rules reference|half-done|stale|✗' | head -20)
    [ -z "$detail" ] && detail=$(printf '%s' "$output" | tail -20)
    deny "The pre-push gate failed — ./scripts/verify.sh --tests did not pass, so this push would put a red commit on main and deploy.yml would install nothing.

$detail

Fix it and push again. If the failure is genuinely unrelated to this change, say so explicitly in your reply rather than working around the gate."
fi

allow
