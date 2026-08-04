#!/usr/bin/env bash
# PreToolUse hook on Bash: every shell call starts from the repo root.
#
# Why this exists: the Bash tool's working directory persists between calls,
# so one `cd InsightKit && swift test` relocates every later relative path —
# `./scripts/verify.sh`, `sed`, Python heredocs opening relative files. The
# "absolute paths, always" rule in CLAUDE.md failed in six consecutive
# sessions (ledger row in docs/efficiency-log.md); a rule the model can skip
# is tier 1, and this hook is the tier-2 answer the harness runs instead.
#
# Mechanism: rewrite the command to `cd <repo root> && <command>` via
# hookSpecificOutput.updatedInput. Prepending was chosen over denying
# relative-path shapes because the observed failures include heredocs and
# seds that no path lint would catch. A command that already anchors itself
# to the repo root is passed through untouched. Commands the model
# deliberately runs elsewhere still work: their own `cd` follows ours.
#
# Permission note: Claude Code splits compound commands on `&&` and checks
# each part, so the prefix needs its own allow entry —
# "Bash(cd /home/user/health-insights-ios)" in .claude/settings.json —
# and every existing rule keeps matching its original part.
#
# The prefix is *quoted*. On the user's Mac the repo lives in iCloud Drive,
# under a path containing a space ("…/Library/Mobile Documents/…"), so the
# unquoted form this hook shipped with expanded to three words and every
# unanchored shell call in the first Mac session died on
# `cd:1: no such file or directory`. A hook that rewrites commands must
# survive its own repo's path; the Linux container's path had no space in it
# and hid this for five sessions.

set -euo pipefail

root="${CLAUDE_PROJECT_DIR:-/home/user/health-insights-ios}"
input=$(cat)

cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[ -z "$cmd" ] && exit 0

# Already anchored — leave it alone so the rewrite is idempotent.
case "$cmd" in
  "cd $root"* | "cd \"$root\""*) exit 0 ;;
esac

jq -c --arg root "$root" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: (.tool_input | .command = "cd \"\($root)\" && " + .command)
  }
}' <<<"$input"
