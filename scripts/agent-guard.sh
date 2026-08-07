#!/usr/bin/env bash
#
# Who am I, and where am I allowed to write?
#
# ⚠️ **Twelve agents run in parallel in this repo, in twelve worktrees, sharing
# ONE scratchpad directory.** Two collisions have already cost real work:
#
#   1. A git-helper script written to the shared scratchpad was twice rewritten
#      by other agents to point at *their* worktrees, with the safety check
#      removed. Two agents lost commits; one lost its work entirely and its
#      document had to be rescued by hand. (D32, 2026-08-06.)
#   2. An agent screenshotted another agent's simulator build and believed it.
#      Fixed separately by `simulator.sh`'s per-worktree slot on 2026-08-07 —
#      this script is the other half of the same defect class.
#
# Both had the same shape: **a shared name with no owner in it.** The scratchpad
# for the 2026-08-07 wave held 138 entries and 106 of them were called things
# like `verify.log`, `gate.log`, `oura.json`, `sim.py`, `an.py`, `probe.py` —
# every one of them a name a sibling agent would pick independently, and
# `verify.log` was rewritten at 19:34 and again at 19:46 by different agents.
#
# Writing the rule down more firmly has already failed here repeatedly, so this
# is a command instead:
#
#   ./scripts/agent-guard.sh                  # the pre-staging self-check
#   ./scripts/agent-guard.sh --tag            # this agent's label
#   ./scripts/agent-guard.sh --scratch NAME   # a scratchpad path nobody else can pick
#   ./scripts/agent-guard.sh --scratch-check  # audit the shared scratchpad only
#
# `verify.sh` runs the default mode first, so every agent trips over it
# immediately before staging — which is where D32 says the check belongs.
#
# Exit 0 = safe. Exit 1 = you are about to write into, or from, the wrong tree.

set -uo pipefail

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
dim()  { printf '\033[2m%s\033[0m\n' "$*"; }

fail=0

# Where this script actually lives — resolved, not assumed. The whole point of
# the caller check below is that the copy you ran and the tree you are editing
# can be different copies of the same repo.
self=$(cd -P "$(dirname "$0")" && pwd)
script_root=$(git -C "$self" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${self%/scripts}")

# `--git-dir` and `--git-common-dir` are the same path in a main working tree
# and differ in every linked worktree. That is the canonical test, matching
# `verify.sh` and `simulator.sh`; pattern-matching the path for `/worktrees/`
# would be fooled by a checkout that merely lives in a directory of that name.
tag_for() {
    local r=$1
    if [ "$(git -C "$r" rev-parse --git-dir 2>/dev/null)" \
       != "$(git -C "$r" rev-parse --git-common-dir 2>/dev/null)" ]; then
        basename "$r"
    else
        printf 'main'
    fi
}

TAG=$(tag_for "$script_root")

# Every worktree checked out right now. Used to tell a scratchpad file that
# names an owner from one that names nobody.
#
# ⚠️ `main` is deliberately NOT in this list even though it is a valid tag.
# Ownership here is decided by substring match, and `main` appears inside
# ordinary words — `domain-notes.sh` would be read as another agent's file and
# skipped by the checks below. Worktree names (`wf_…`) are distinctive enough
# for that; `main`'s own files are still recognised by the exact `main--` form.
known_tags() {
    git -C "$script_root" worktree list --porcelain 2>/dev/null \
        | awk '/^worktree /{print $2}' \
        | while read -r w; do basename "$w"; done
}

# The shared scratchpad. The harness hands each session a path and does not
# export it, so this derives it the same way the harness names it: the *main*
# repo path with every non-alphanumeric character replaced by a dash. Sibling
# agents of one wave share the session directory beneath that — which is
# exactly why the collisions happen and exactly why this is findable.
# `AGENT_SCRATCH_DIR` overrides it; a session that was told a different path
# should export that rather than let this guess.
scratch_root() {
    if [ -n "${AGENT_SCRATCH_DIR:-}" ]; then printf '%s\n' "$AGENT_SCRATCH_DIR"; return; fi
    local common main_root slug
    common=$(git -C "$script_root" rev-parse --git-common-dir 2>/dev/null) || return 0
    case "$common" in */.git) main_root=${common%/.git} ;; *) return 0 ;; esac
    [ -d "$main_root" ] || return 0
    main_root=$(cd -P "$main_root" && pwd)
    slug=$(printf '%s' "$main_root" | sed 's/[^A-Za-z0-9]/-/g')
    # Newest session directory wins: collisions only happen within one wave, and
    # an abandoned session's debris is not worth reporting. Both platforms'
    # roots are tried — the Mac resolves /tmp to /private/tmp, a Linux
    # container does not.
    ls -td "/private/tmp/claude-$(id -u)/$slug"/*/scratchpad \
           "/tmp/claude-$(id -u)/$slug"/*/scratchpad 2>/dev/null | head -1
}

# --- --tag ----------------------------------------------------------------
if [ "${1:-}" = "--tag" ]; then
    printf '%s\n' "$TAG"
    exit 0
fi

# --- --scratch NAME -------------------------------------------------------
#
# Collision-proof by construction rather than by remembering. Prints a path;
# it does not create the file, so it composes with anything:
#
#   log=$(./scripts/agent-guard.sh --scratch verify.log)
#   ./scripts/verify.sh --tests > "$log" 2>&1
if [ "${1:-}" = "--scratch" ]; then
    name=${2:-}
    [ -n "$name" ] || { red "usage: $0 --scratch <name>"; exit 1; }
    case "$name" in
        */*) red "No slashes: the label has to be in the FILE name, not a directory above it."
             red "A sibling agent listing the scratchpad sees names, not paths."
             exit 1 ;;
    esac
    root=$(scratch_root)
    [ -n "$root" ] || root="${TMPDIR:-/tmp}/health-insights-scratch"
    mkdir -p "$root" || exit 1
    printf '%s/%s--%s\n' "$root" "$TAG" "$name"
    exit 0
fi

# --- the scratchpad audit -------------------------------------------------
scratch_audit() {
    local root; root=$(scratch_root)
    if [ -z "$root" ] || [ ! -d "$root" ]; then
        dim "Scratchpad: not found — nothing to audit."
        return 0
    fi
    bold "Scratchpad: $root"
    printf '  %s\n' "Yours must be named: ${TAG}--<name>   (./scripts/agent-guard.sh --scratch <name>)"

    local tags; tags=$(known_tags)
    local total=0 attributable=0 mine=0
    local entry base t owned
    for entry in "$root"/*; do
        [ -e "$entry" ] || continue
        base=$(basename "$entry")
        total=$((total + 1))
        case "$base" in "$TAG"--*) mine=$((mine + 1)); attributable=$((attributable + 1)); continue ;; esac
        owned=0
        while IFS= read -r t; do
            [ -n "$t" ] || continue
            case "$base" in *"$t"*) owned=1; break ;; esac
        done <<EOF
$tags
EOF
        [ "$owned" -eq 1 ] && attributable=$((attributable + 1))
    done
    [ "$total" -eq 0 ] && { printf '  %s\n' "empty."; return 0; }

    # **Report what is checkable, not what feels tidy.** An earlier version of
    # this counted every name that did not contain a live worktree tag as
    # "unlabelled" and printed "135 of 136" — true, useless, and instantly
    # ignored, because agents label by hand (`agent10-`, `p5-`, `d25d26-`) with
    # strings no tool can attribute. The number that matters to *you* is how
    # many of these are yours, because everything else is a name a sibling
    # picked and can pick again.
    printf '  %s\n' \
        "$total entries; $mine yours, $attributable attributable to a worktree at all."
    [ "$mine" -eq 0 ] && printf '  %s\n' \
        "Nothing here is yours yet — name your first one ${TAG}--<name> and it stays yours."

    # **The D32 defect itself, not a proxy for it.** A *script* in the shared
    # scratchpad that hardcodes a worktree path is the thing that cost two
    # agents their commits: a helper silently retargeted at someone else's tree.
    #
    # ⚠️ **Scoped to executable kinds on purpose.** The first version scanned
    # every text file and flagged thirteen — all of them captured `verify.sh`
    # output, which of course contains the path of the tree it ran in. A guard
    # whose own premise is false is a category this repo has hit seven times, so:
    # a log records a path, a script *acts* on one, and only the second can be
    # rewritten to point at the wrong tree.
    #
    # Two severities, because only one of them is your problem:
    #   - a script named as YOURS pointing elsewhere -> it was retargeted. Fail.
    #   - an unattributable script pointing elsewhere -> don't run it. Warn.
    # Old debris must never be able to block eleven agents' gates, hence
    # `-mtime -1`; the size bound keeps the multi-MB PDFs and screenshots out.
    local mine_hits="" loose_hits="" f foreign
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in
            *.sh|*.bash|*.zsh|*.py|*.rb|*.pl|*.js|*.mjs) ;;
            *) [ -x "$f" ] || continue ;;
        esac
        base=$(basename "$f")
        owned=0
        while IFS= read -r t; do
            [ -n "$t" ] || continue
            [ "$t" = "$TAG" ] && continue
            case "$base" in *"$t"*) owned=1; break ;; esac
        done <<EOF
$tags
EOF
        [ "$owned" -eq 1 ] && continue          # another agent's, correctly named
        foreign=$(grep -oIE '\.claude/worktrees/[A-Za-z0-9_.-]+' "$f" 2>/dev/null \
                  | sort -u | grep -v "/$TAG\$" | head -3 | tr '\n' ' ')
        [ -n "$foreign" ] || continue
        case "$base" in
            "$TAG"--*) mine_hits="$mine_hits
  $base -> $foreign" ;;
            *)         loose_hits="$loose_hits
  $base -> $foreign" ;;
        esac
    done <<EOF
$(find "$root" -maxdepth 1 -type f -size -256k -mtime -1 2>/dev/null)
EOF

    if [ -n "$loose_hits" ]; then
        bold "Unowned scripts here target another agent's worktree — do NOT run them:"
        printf '%s\n' "$loose_hits"
    fi
    if [ -n "$mine_hits" ]; then
        red "A script carrying YOUR label points at ANOTHER agent's worktree:"
        printf '%s\n' "$mine_hits"
        red "This is D32 exactly — a helper rewritten to target the wrong tree."
        red "Re-derive the path from 'git rev-parse --show-toplevel'; never hardcode a worktree."
        fail=1
    fi
}

if [ "${1:-}" = "--scratch-check" ]; then
    scratch_audit
    exit "$fail"
fi

# --- default: the pre-staging self-check ----------------------------------

root=$(git -C "$script_root" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$root" ]; then
    red "Not a git repository: $script_root"
    exit 1
fi

branch=$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)
siblings=$(git -C "$root" worktree list 2>/dev/null | wc -l | tr -d ' ')
siblings=$((siblings - 1))

bold "Agent: $TAG"
printf '  %s\n' "toplevel: $root"
printf '  %s\n' "branch:   $branch"
[ "$siblings" -gt 0 ] && printf '  %s\n' \
    "sharing this repo with $siblings other worktree(s) right now — stay in your own files."

# **Are you running this copy of the scripts against a different working copy?**
# `verify.sh` exports the caller's directory before its own `cd`, so this sees
# where the command was actually issued from. The failure it catches is an agent
# in worktree W invoking the MAIN checkout's scripts: everything appears to
# work, and the gate then verifies a tree that is not the one being committed.
caller=${AGENT_GUARD_CWD:-$PWD}
caller_root=$(git -C "$caller" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$caller_root" ] && [ "$caller_root" != "$root" ]; then
    red "You ran the scripts in   $root"
    red "but your working copy is $caller_root"
    red "Those are different checkouts. Run \$(git rev-parse --show-toplevel)/scripts/... instead —"
    red "a gate run against the wrong tree passes on code you are not committing."
    fail=1
fi

# Another agent's worktree staged in yours. `.claude/worktrees/` is other
# agents' live working copies; committing one is how a wave loses work.
staged_wt=$(git -C "$root" diff --cached --name-only 2>/dev/null | grep '^\.claude/worktrees/' | head -3)
if [ -n "$staged_wt" ]; then
    red "You have staged files from ANOTHER agent's worktree:"
    printf '%s\n' "$staged_wt"
    red "Unstage them (git restore --staged .claude/worktrees) before committing."
    fail=1
fi

scratch_audit

if [ "$fail" -eq 0 ]; then
    printf '\033[32m✓\033[0m %s\n' "Staging into your own tree."
fi
exit "$fail"
