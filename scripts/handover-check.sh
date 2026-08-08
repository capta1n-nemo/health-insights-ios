#!/usr/bin/env bash
#
# The close-out gate. Run it as the LAST step of `/handover`, before telling the
# user the session is safe to close.
#
#   ./scripts/handover-check.sh                  # checks that need no baseline
#   ./scripts/handover-check.sh <base-ref>       # + everything scoped to a session
#
# ## Why this exists
#
# The handover protocol used to end with "confirm to the user that memory files
# are synchronized". That is an *assertion the model makes*, and on 2026-07-31 it
# was made and was wrong: `docs/activeContext.md` still described five completed
# things as open, and the efficiency log's own numbers disagreed with what had
# just been reported out loud. The user caught it by asking.
#
# An assertion cannot catch that. A check can. Everything below is a fact about
# the repository, so it holds however little context is left at the end of a long
# session — which is exactly when handover happens and exactly when a model is
# least able to audit itself.
#
# Exit 0 = safe to close. Anything else = do not tell the user it is done.

set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
bad()  { printf '\n\033[31m✗ %s\033[0m\n' "$1"; fail=1; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[33m!\033[0m %s\n' "$1"; }

BASE="${1:-}"

# --- 1. Nothing uncommitted ------------------------------------------------
if [ -n "$(git status --porcelain)" ]; then
    bad 'Uncommitted changes. The next session clones fresh and will never see them:'
    git status --short | sed 's/^/    /'
else
    ok 'Working tree clean'
fi

# --- 2. Pushed --------------------------------------------------------------
# The container is reclaimed after the session. A commit that only exists here
# is a commit that does not exist.
git fetch origin main --quiet 2>/dev/null || warn 'Could not fetch origin (offline?)'
local_head=$(git rev-parse HEAD 2>/dev/null)
remote_head=$(git rev-parse origin/main 2>/dev/null || echo 'unknown')
if [ "$local_head" != "$remote_head" ]; then
    bad "HEAD ($(git rev-parse --short HEAD)) is not origin/main (${remote_head:0:7}). Unpushed work is lost work."
    git log --oneline origin/main..HEAD 2>/dev/null | sed 's/^/    /'
else
    ok 'HEAD matches origin/main'
fi

# --- 3. CI green on exactly this commit ------------------------------------
# `deploy.yml` only fires on a green push to main, so a red HEAD means nothing
# reached the phone however many commits landed.
if [ -x scripts/ci-status.sh ]; then
    verdict=$(./scripts/ci-status.sh 2>/dev/null | tail -1)
    case "$verdict" in
        passed*) ok "CI passed on $(git rev-parse --short HEAD)" ;;
        failed*) bad "CI FAILED on HEAD — nothing has deployed. $verdict" ;;
        *)       warn "CI verdict not recorded yet for HEAD ($verdict). Wait for it before closing." ;;
    esac
fi

# --- 4. The lint still passes ----------------------------------------------
# Plain verify.sh: the lints and (on Darwin) the app-target parse, NOT the test
# suite — the suite belongs to the pre-push gate, which ran before HEAD reached
# origin. A handover that leaves the lint red hands the next session a broken
# baseline and no way to tell which change broke it.
if ./scripts/verify.sh >/dev/null 2>&1; then
    ok 'verify.sh lint clean'
else
    bad 'verify.sh lint is NOT clean — run ./scripts/verify.sh and read it'
fi

# --- 5. The docs were actually updated -------------------------------------
# The check that would have caught 2026-07-31. Updating the docs is step 2 of the
# protocol and is the step most likely to be skipped when context is short,
# because it is the one with no compiler behind it.
if [ -n "$BASE" ]; then
    changed=$(git diff --name-only "$BASE"..HEAD 2>/dev/null)
    if [ -z "$changed" ]; then
        warn "No changes between $BASE and HEAD — is the base right?"
    else
        code_changed=$(printf '%s\n' "$changed" | grep -cE '\.swift$' || true)
        # ⚠️ `docs/backlog.md`, not `docs/progress.md`, since 2026-08-07. There is
        # ONE list now. progress.md keeps the historical shipped narrative and is
        # no longer where open work is recorded, so requiring a session to touch
        # it would be asking for a ritual edit to a file it had no reason to
        # change — and a ritual edit is how a doc starts lying.
        for doc in docs/activeContext.md docs/backlog.md docs/efficiency-log.md; do
            if printf '%s\n' "$changed" | grep -qx "$doc"; then
                ok "$doc updated this session"
            elif [ "$code_changed" -gt 0 ]; then
                bad "$doc was NOT updated, but $code_changed Swift files changed. The docs are the audit of record — a stale one is worse than none."
            else
                warn "$doc not updated (no Swift changed either, so this may be fine)"
            fi
        done
    fi
else
    warn 'No base ref given — skipping the docs-updated and red-CI-count checks.'
    warn 'Pass the previous handover commit, e.g. ./scripts/handover-check.sh <sha>'
fi

# --- 6. The efficiency log's red-CI count matches reality ------------------
# The log's whole value is that a future session can recompute it and find the
# same numbers. Red CI is the one column derivable from the repo alone, so it is
# the one that can be *proved* rather than trusted — and it is the headline
# figure reported to the user.
if [ -n "$BASE" ] && [ -f docs/efficiency-log.md ]; then
    session_shas=$(git rev-list "$BASE"..HEAD 2>/dev/null)
    actual_red=0
    if [ -n "$session_shas" ]; then
        failed_refs=$(git ls-remote origin 'refs/ci/failed/*' 2>/dev/null | awk '{print $1}')
        for sha in $session_shas; do
            printf '%s\n' "$failed_refs" | grep -q "^$sha$" && actual_red=$((actual_red + 1))
        done
    fi
    # The newest table row is the last line starting with `| ` that has a digit
    # in its first cell — i.e. skipping the header and the separator.
    row=$(grep -E '^\| *[0-9]' docs/efficiency-log.md | tail -1)
    if [ -z "$row" ]; then
        bad 'docs/efficiency-log.md has no session row. The protocol requires one per session.'
    else
        logged_red=$(printf '%s' "$row" | awk -F'|' '{gsub(/[^0-9]/, "", $5); print $5}')
        if [ "${logged_red:-x}" = "$actual_red" ]; then
            ok "Efficiency log's red-CI count ($actual_red) matches refs/ci/failed"
        else
            bad "Efficiency log says $logged_red red CI, the repo says $actual_red. Fix the row — a log whose arithmetic does not match the repo is worse than no log."
        fi
    fi
fi

# --- 7. Every script the rules tell you to run actually exists -------------
#
# The check that would have caught 2026-07-31's second failure, which was worse
# than the first. `CLAUDE.md` and the handover command were both updated to say
# "run ./scripts/handover-check.sh", the commit message described what it did in
# detail, and the file was not in the tree — a canary's `git add -A` had swept
# the then-untracked script into a throwaway commit and `git reset --hard` had
# deleted it. An audit reported the script missing and the report was dismissed
# as stale, because it contradicted a memory of having written it.
#
# A rule pointing at a script that does not exist is worse than no rule: it reads
# as a guarantee and silently provides nothing.
missing_scripts=""
for f in CLAUDE.md .claude/commands/handover.md .claude/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    for ref in $(grep -oE '\./scripts/[A-Za-z0-9_-]+\.sh' "$f" 2>/dev/null | sort -u); do
        if [ ! -x "${ref#./}" ]; then
            missing_scripts="$missing_scripts\n    $ref (referenced by $f)"
        fi
    done
done
if [ -n "$missing_scripts" ]; then
    bad 'Rules point at scripts that are missing or not executable:'
    printf "$missing_scripts\n"
else
    ok 'Every script the rules reference exists and is executable'
fi

# --- 7b. The card map still matches the code -------------------------------
# The insight detail screen is the app's most-edited surface and
# `docs/card-sections.md` is the only record of what each card renders. A
# session that moved a section and updated the code but not the document has
# happened, twice; the ordering half is now generated, so it can be checked
# rather than remembered.
#
# The check fails on a *stale ordering*, and that is deliberately a prompt to
# re-read the rest of the file. A new or moved section also changes the matrix,
# the gate table and the feature audit, and all three are written by hand.
if [ -x scripts/card-map.sh ]; then
    if scripts/card-map.sh --check >/dev/null 2>&1; then
        ok 'docs/card-sections.md matches InsightDetailView.body'
    else
        bad 'docs/card-sections.md is out of date with the card sections.'
        printf '    Run ./scripts/card-map.sh, then re-read the matrix, the gate\n'
        printf '    table and the feature audit — those are hand-written and a\n'
        printf '    moved section changes all three.\n'
    fi
fi

# --- 7c. The backlog parses, and its index matches its rows ----------------
# ⚠️ This replaced the `roadmap-table.sh --check` on 2026-08-07, when three
# open-item lists became one. It does strictly more than the old check: as well
# as catching a stale index, `backlog.sh` hard-errors on any row whose shape it
# cannot read, and on any section carrying table rows but no backlog rows.
#
# That second rule is the one worth keeping. `unbuilt-asks.sh` matched two
# hard-coded headings, so §B7 and §B9–§B19 — about thirty of the reader's own
# asks — were invisible to it, and it reported two. A parser that silently
# returns nothing reads as "nothing outstanding".
if [ -x scripts/backlog.sh ]; then
    if backlog_out=$(scripts/backlog.sh --check 2>&1); then
        ok "docs/backlog.md parses and its index is current"
    else
        bad "docs/backlog.md does not parse, or its index is stale."
        printf '%s\n' "$backlog_out" | sed 's/^/    /'
    fi
fi

# `docs/status.md` is generated from the same rows plus each research document's
# own status line. It is checked here because the reader reads THAT file, and a
# hand-maintained status document is how this repo grew a fourth list once
# already (`docs/status-2026-08-07.md`, correct for one morning).
if [ -x scripts/status.sh ]; then
    if status_out=$(scripts/status.sh --check 2>&1); then
        ok "docs/status.md is current"
    else
        bad "docs/status.md is stale, or a research doc has no status line."
        printf '%s\n' "$status_out" | sed 's/^/    /'
    fi
fi

# --- 8. Open items are still countable, per tier ---------------------------
# Not a pass/fail — numbers to read back to the user, so "nothing is missed" is
# a count they can check rather than a claim they have to take on trust. Broken
# out by tier because that is how work is now batched: a session picks a tier,
# states the model it needs, and grinds.
if [ -x scripts/backlog.sh ]; then
    printf '\n'
    scripts/backlog.sh 2>/dev/null | tail -1
    for tier in mech design build hard ultra; do
        n=$(scripts/backlog.sh --tier "$tier" 2>/dev/null | grep -c '^  w[0-4]' || true)
        [ "$n" -gt 0 ] && printf '  %-7s %s open\n' "$tier" "$n"
    done
    asked=$(scripts/backlog.sh --asks 2>/dev/null | grep -c '^  w[0-4]' || true)
    printf '\n\033[1m%s of those are things the reader asked for in their own words\033[0m — lead with these.\n' "$asked"
fi

if [ "$fail" -eq 0 ]; then
    printf '\n\033[32mSafe to close.\033[0m\n'
else
    printf '\n\033[31mNOT safe to close — fix the above before saying the session is done.\033[0m\n'
fi
exit "$fail"
