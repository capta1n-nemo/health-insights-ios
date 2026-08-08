#!/usr/bin/env bash
#
# The cheap gate. Runs in under a second, needs no toolchain, and checks the
# rules this repo has actually been broken by — each one traceable to a CI
# failure or a shipped bug, not to taste.
#
#   ./scripts/verify.sh                     # lint only (works anywhere)
#   ./scripts/verify.sh --tests             # lint + the full suite. THE GATE.
#   ./scripts/verify.sh --tests Foo         # lint + suites matching Foo, mid-change
#
# Exit 0 = clean. Anything else = read the output before pushing.

set -uo pipefail

# Captured BEFORE the `cd`, because that `cd` destroys the evidence. It is the
# only way `agent-guard.sh` can tell that the scripts you ran and the tree you
# are editing are two different checkouts of this repo — which is a live hazard
# with twelve worktree agents and one repo. See the guard's header.
AGENT_GUARD_CWD="${AGENT_GUARD_CWD:-$PWD}"
export AGENT_GUARD_CWD

cd "$(dirname "$0")/.."

fail=0
note() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# --- Which tree am I about to commit? (D32) --------------------------------
#
# **First, before anything else**, because this is the check that has to be
# tripped over rather than remembered. D32's rule is that every agent verifies
# `git rev-parse --show-toplevel` immediately before staging — and the moment
# immediately before staging is this gate. Writing that rule down more firmly
# had already been tried and had already failed; two agents lost commits.
./scripts/agent-guard.sh || fail=1

# Flag any match of $1 in the given paths. $2 is the explanation.
# A banned pattern, **in code**. Comment lines are skipped.
#
# Not a convenience: this repo's house style is that every fix records the shape
# it replaced, right there in a doc comment — so the ban patterns are quoted, by
# design, in the very files that no longer commit the sin. Before this filter,
# documenting a fix tripped the lint that motivated the fix, twice in one
# session, and the only way out was to describe the mistake less clearly.
#
# A comment cannot be a compile error or a wrong architecture, which is what
# every one of these bans is about. `//` in any leading position, plus ` * ` for
# block-comment continuations.
ban() {
    local pattern=$1 message=$2
    shift 2
    local out
    # grep -rn prints `path:line:content`; strip that prefix before deciding
    # whether the *content* is a comment.
    out=$(grep -rn --include='*.swift' -E "$pattern" "$@" 2>/dev/null \
        | grep -vE '^[^:]*:[0-9]+:[[:space:]]*(//|\*)' || true)
    if [ -n "$out" ]; then
        note "$message"
        printf '%s\n' "$out"
        fail=1
    fi
}

APP=HealthInsights
KIT=InsightKit/Sources
KIT_TESTS=InsightKit/Tests

# Where Xcode build products go. Never inside the working copy — see the
# app-target compile below for why that costs real money on this Mac.
DERIVED_ROOT="${HEALTH_INSIGHTS_DERIVED:-$HOME/Library/Caches/health-insights}"

# **One slot per worktree, because two gates genuinely do run at once.**
#
# Xcode keeps a single `build.db` per derived-data path and holds a lock on it
# for the whole build, so two concurrent `verify.sh --tests` runs sharing a
# path both die with "database is locked". That failure is *not* a compile
# error, but it arrives as two `error:` lines, which is precisely what
# `pre-push-gate.sh` greps for — so it reached the reader dressed as "your
# change broke the build" when nothing was wrong with the diff. Hit twice on
# 2026-08-06, when a worktree-isolated agent and the main checkout ran the
# gate simultaneously. CLAUDE.md actively encourages those agents, so
# concurrent gates are the expected case and not an exotic one.
#
# ⚠️ **The tradeoff is a cold build, and it is paid per worktree, once.** The
# main checkout keeps the unsuffixed path so its incremental build stays at
# ~1.4s; a linked worktree starts from nothing the first time it runs the gate
# — minutes — and is warm thereafter. That is the price of not interleaving
# two builds in one cache, and it is far below the cost of the red push it
# prevents. `HEALTH_INSIGHTS_DERIVED` still overrides the root, and still
# suffixes beneath it; point two worktrees at one root *and* the same slot
# only if you want them to share a cache and are sure they will not race.
#
# `--git-dir` and `--git-common-dir` are the same path in the main working
# tree and differ in every linked worktree. That is the canonical test —
# pattern-matching the path for `/worktrees/` would be fooled by a checkout
# that merely lives in a directory of that name.
DERIVED_SLOT=verify-ios
if [ "$(git rev-parse --git-dir 2>/dev/null)" \
   != "$(git rev-parse --git-common-dir 2>/dev/null)" ]; then
    # Basename so `du -sh` is readable by a human, CRC of the *full* path so
    # two worktrees that happen to share a basename still get separate slots.
    # Outside a git repo both rev-parses fail to the same empty string, so
    # this branch is skipped and the main slot is used — the safe default.
    wt_root=$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")
    DERIVED_SLOT="verify-ios-$(basename "$wt_root")-$(printf '%s' "$wt_root" | cksum | cut -d' ' -f1)"
fi

# --- Architecture rules from CLAUDE.md ------------------------------------

# Scoped to where view models live. The three integration services in
# Core/Integrations are deliberately ObservableObject — they are services with
# a long-lived observer, not view models, and CLAUDE.md's rule is about view
# models. Widen this only if that changes.
ban 'ObservableObject' \
    'CLAUDE.md: view models are @Observable, never ObservableObject.' \
    "$APP/Features" "$APP/Core/State"

ban 'NavigationView' \
    'CLAUDE.md: use NavigationStack, not NavigationView.' "$APP"

# InsightKit must stay platform-free or it stops building on Linux, which is
# what makes local `swift test` possible at all.
ban '^import (HealthKit|UIKit|SwiftUI|Charts)$' \
    'InsightKit must import no platform frameworks — it is the testable core.' "$KIT"

ban '^import Testing$' \
    'Tests use XCTest, not swift-testing.' "$KIT_TESTS"

# --- Swift traps this repo has actually hit --------------------------------

# Key paths do not work on tuple elements: `\.0` and `\.slope` on a tuple are
# compile errors. Cost a CI round trip once.
ban '\\\.[0-9]+\b' \
    'Key paths do not work on tuple elements — use { $0.0 } instead of \.0.' \
    "$KIT" "$KIT_TESTS" "$APP"

# A bare `yyyy-MM-dd` names a calendar day, and a calendar day is local. Two
# ingestion formatters were pinned to UTC while SleepOnset, ShortcutIngest and
# every manual write used calendar.startOfDay — so the reader's 1,720 Oura
# samples sat eight hours off the day boundary their Apple nights sat exactly on,
# and the two only reconciled because their UTC offset is positive. `DayStamp` is
# the rule. The suite is the reason this is a lint: a UTC-pinned test of
# UTC-pinned code agrees with itself.
ban 'TimeZone\(identifier: "UTC"\)' \
    'Parse a date-only field with DayStamp.local — pinning ingestion to UTC puts a day eight hours off the reader'"'"'s own.' \
    "$KIT"

# A default-configured ISO8601DateFormatter rejects fractional seconds, and a
# rejection is nil — indistinguishable from "the connector sent no date". Three
# parsers hand-rolled the fractional-then-plain fallback; the one that got it
# wrong (Oura) lost every bedtime in the reader's two-year history and disabled
# the split-night fix, with every test still green. `PayloadDate.parse` is the
# one door: it tries both forms, plus a bare day string and epoch seconds.
ban 'ISO8601DateFormatter\(\)\.(date|string)' \
    'Parse connector dates with PayloadDate.parse — a bare ISO8601DateFormatter() drops fractional seconds and reports it as nil.' \
    "$KIT"

# A RuleMark/AreaMark/RectangleMark chain without an explicit `-> some
# ChartContent` can resolve to Chart3DContent on this SDK and silently drop
# .lineStyle / .foregroundStyle / .annotation. Broke CI twice.
if out=$(grep -rn --include='*.swift' -B 3 -E '^\s+(RuleMark|AreaMark|RectangleMark|BarMark)\(' "$APP" 2>/dev/null \
         | grep -E 'private (var|func).*: some View|@ViewBuilder' 2>/dev/null); then
    note 'Chart3DContent hazard: a mark builder returning `some View` rather than `some ChartContent`.'
    printf '%s\n' "$out"
    fail=1
fi

# --- Exhaustive switches: adding a case must update every one of these ------
# All have no `default:`, so the compiler catches them — but only on a machine
# with a compiler. This is the sandbox substitute.

# The metric names themselves, so a switch can be checked name-by-name rather
# than by counting — grouped `case .a, .b, .c:` lines make counting useless.
metric_names=$(awk '/^public enum MetricType/,/^}/' \
    InsightKit/Sources/InsightKit/Models/MetricType.swift 2>/dev/null \
    | grep -oE '^\s+case [a-z][A-Za-z0-9]*' | awk '{print $2}' | sort -u)

# Names a switch is allowed not to mention because another arm covers them.
check_switch_covers() {
    local file=$1 symbol=$2
    local body missing=""
    # From the declaration to the closing brace at four-space indent.
    body=$(awk "/(var|func) $symbol/,/^    }\$/" "$file" 2>/dev/null)
    [ -z "$body" ] && return
    # A `default:` arm makes the switch non-exhaustive by design — skip it.
    #
    # ⚠️ Herestrings, NOT `printf | grep -q` — that shape failed on CI and only
    # on CI (red on a3d70d6, green locally, same tree). `grep -q` exits at its
    # first match and closes the pipe; `printf` takes SIGPIPE (exit 141), and
    # under `pipefail` **the pipeline fails even though grep matched** — so a
    # case that IS present got reported missing. macOS delivers the body in one
    # write and never hits it; Linux chunks it. The "printf: write error:
    # Broken pipe" line in the CI log was the tell.
    grep -qE '^\s+default:' <<<"$body" && return
    for name in $metric_names; do
        grep -qE "[.]$name\b" <<<"$body" || missing="$missing $name"
    done
    if [ -n "$missing" ]; then
        note "$symbol ($file) does not mention:$missing"
        fail=1
    fi
}

if [ -n "$metric_names" ]; then
    check_switch_covers InsightKit/Sources/InsightKit/Models/MetricType.swift displayName
    check_switch_covers InsightKit/Sources/InsightKit/Models/MetricType.swift unit
    check_switch_covers InsightKit/Sources/InsightKit/Presentation/MetricPresentation.swift family
    check_switch_covers InsightKit/Sources/InsightKit/Presentation/MetricPresentation.swift chartStyleIndex
    check_switch_covers InsightKit/Sources/InsightKit/Presentation/MetricPresentation.swift presentation
    check_switch_covers InsightKit/Sources/InsightKit/Presentation/MetricPresentation.swift maxValidInterval
    check_switch_covers InsightKit/Sources/InsightKit/Presentation/MetricPresentation.swift referenceRange
    check_switch_covers InsightKit/Sources/InsightKit/Signals/MetricSanitizer.swift requiresPositiveValue
fi

# `InsightID`'s case list, for the generic pass below.
#
# This used to be a bespoke check on `iconName` alone, written when that switch
# carried a `default:` and so failed silently with somebody else's glyph. It no
# longer has one — every InsightID switch except `cadence` is exhaustive now —
# and a hand-picked check on one of them is exactly the shape that let a
# `Suggestion.Basis` switch break CI. The generic pass covers all of them.
insight_names=$(awk '/^public enum InsightID/,/^}/' \
    InsightKit/Sources/InsightKit/Insights/Insight.swift 2>/dev/null \
    | grep -oE '^\s+case [a-z][A-Za-z0-9]*' | awk '{print $2}' | sort -u)

# --- Any exhaustive switch, anywhere, over an InsightKit enum ---------------
#
# The checks above name each switch individually, which only ever catches the
# switches somebody remembered to list. Adding `.convergingSignals` to
# `Suggestion.Basis` broke CI on a switch in `InsightsListView` that no list
# here mentioned — the same shape as the `.vitalSigns` break before it, and the
# reason this generic pass exists.
#
# Swift already requires a switch with no `default:` to name every case, so the
# rule needs no per-switch knowledge: find switch blocks with no default that
# mention this enum's cases, and report any case they leave out. The coverage
# floor is what stops a switch over some *other* type with a coincidentally
# similar case name being flagged.
# Case names of `enum $2` in file $1, at any nesting depth — `Suggestion.Basis`
# is declared inside a struct, so an anchored `^public enum` finds nothing.
enum_cases() {
    awk -v want="$2" '
        !inside && $0 ~ ("enum[[:space:]]+" want "[[:space:]:{]") {
            match($0, /^[[:space:]]*/); indent = RLENGTH; inside = 1; next
        }
        inside {
            match($0, /^[[:space:]]*/)
            if (RLENGTH <= indent && $0 ~ /^[[:space:]]*\}/) { inside = 0; next }
            if ($0 ~ /^[[:space:]]*case [a-z]/) {
                sub(/^[[:space:]]*case /, ""); sub(/[^A-Za-z0-9].*$/, ""); print
            }
        }
    ' "$1" 2>/dev/null | sort -u
}

# $1 = label, rest = case names.
check_every_switch_over() {
    local label=$1
    shift
    local names=("$@")
    [ "${#names[@]}" -lt 2 ] && return
    local floor=$(( (${#names[@]} + 1) / 2 ))
    local report

    report=$(
        for file in $(git ls-files '*.swift' | grep -v '/Tests/'); do
            awk -v names="${names[*]}" -v floor="$floor" -v file="$file" '
                # Open a block at the first `switch`, close it at the `}` that
                # sits at the same indentation. A nested switch is deeper, so it
                # never closes its parent.
                !inside && /^[[:space:]]*(.* = )?switch[[:space:]]/ {
                    match($0, /^[[:space:]]*/)
                    indent = RLENGTH; inside = 1; body = ""; line = NR
                }
                inside {
                    body = body "\n" $0
                    if (NR > line) {
                        match($0, /^[[:space:]]*/)
                        if (RLENGTH <= indent && $0 ~ /^[[:space:]]*\}/) {
                            split(names, want, " ")
                            hit = 0; missing = ""
                            for (i in want) {
                                if (body ~ ("[.]" want[i] "[^A-Za-z0-9]")) hit++
                                else missing = missing " " want[i]
                            }
                            if (hit >= floor && missing != "" && body !~ /\n[[:space:]]*default:/)
                                print file ":" line " does not mention:" missing
                            inside = 0
                        }
                    }
                }
            ' "$file"
        done
    )
    if [ -n "$report" ]; then
        note "Exhaustive switches over $label are missing cases:"
        printf '%s\n' "$report"
        fail=1
    fi
}

# shellcheck disable=SC2046
check_every_switch_over MetricType $metric_names
# shellcheck disable=SC2046
check_every_switch_over InsightID $insight_names
# shellcheck disable=SC2046
check_every_switch_over "Suggestion.Basis" \
    $(enum_cases InsightKit/Sources/InsightKit/Insights/Suggestions.swift Basis)

# chartStyleIndex must stay contiguous from zero, or the metrics most likely to
# share a chart lose first claim on the eight hues.
dupes=$(grep -oE 'return [0-9]+$' InsightKit/Sources/InsightKit/Presentation/MetricPresentation.swift 2>/dev/null \
        | sort | uniq -d | head -3)
if [ -n "$dupes" ]; then
    note 'chartStyleIndex may have duplicate indices (must be contiguous from 0):'
    printf '%s\n' "$dupes"
    fail=1
fi

# --- Rules must not point at scripts that are missing ----------------------
#
# On 2026-07-31 `CLAUDE.md` and the handover command were committed instructing
# the reader to run `./scripts/handover-check.sh`, and the file was not in the
# tree — a canary's `git add -A` had swept the still-untracked script into a
# throwaway commit that `git reset --hard` then discarded. It survived three
# pushes. A rule pointing at a missing script is worse than no rule: it reads as
# a guarantee and silently provides nothing.
#
# This lives here rather than only in `handover-check.sh` because *this* script
# runs before every push, and that one runs only when somebody remembers a
# ceremony.
missing_scripts=""
uncommitted_scripts=""
for f in CLAUDE.md .claude/commands/*.md .claude/skills/*/SKILL.md .claude/settings.json; do
    [ -f "$f" ] || continue
    # Match every spelling, not just `./scripts/x.sh`. An absolute path is what
    # `CLAUDE.md` itself mandates for shell calls, and a bare `scripts/x.sh` is
    # what most prose uses — so the original `[.]/scripts/` pattern was blind to
    # the majority of real references, including every one in the skill that was
    # written to *carry* the absolute-path rule.
    for ref in $(grep -ohE '(/[A-Za-z0-9._/-]*)?scripts/[A-Za-z0-9_-]+[.]sh' "$f" 2>/dev/null \
                 | sed 's#.*/scripts/#scripts/#' | sort -u); do
        if [ ! -x "$ref" ]; then
            missing_scripts="$missing_scripts $ref (in $f)"
        elif ! git ls-files --error-unmatch "$ref" >/dev/null 2>&1; then
            # The exact way `handover-check.sh` was lost: it existed on disk, ran,
            # was canaried, and was never committed — so the rules pointed at a
            # file a fresh clone would not have. Asking the filesystem cannot see
            # that; asking git can.
            uncommitted_scripts="$uncommitted_scripts $ref (in $f)"
        fi
    done
done
if [ -n "$missing_scripts" ]; then
    note "Rules reference scripts that are missing or not executable:$missing_scripts"
    fail=1
fi
if [ -n "$uncommitted_scripts" ]; then
    note "Rules reference scripts that exist here but are NOT COMMITTED — a fresh clone will not have them:$uncommitted_scripts"
    fail=1
fi

# --- Hook commands must be absolute ------------------------------------------
#
# Hook processes inherit the Bash tool's *drifted* working directory, so a
# relative `./scripts/foo.sh` in a hook fails with exit 127 — which is a
# non-blocking hook error, not a denial, so the gate it implements is silently
# skipped. Found 2026-08-02: the pre-push gate had exactly this hole, and the
# workdir hook built to fix cwd drift was itself broken by it. The rule is in
# CLAUDE.md; this is the check that survives a context reset.
if command -v jq >/dev/null 2>&1 && [ -f .claude/settings.json ]; then
    relative_hooks=$(jq -r '[.hooks // {} | .[][] | .hooks[]? | select(.type == "command") | .command | select(startswith("./") or startswith("scripts/"))] | join(", ")' .claude/settings.json 2>/dev/null || true)
    if [ -n "$relative_hooks" ]; then
        note "Hook commands in .claude/settings.json must be \$CLAUDE_PROJECT_DIR-absolute (they inherit the shell's drifted cwd and fail silently): $relative_hooks"
        fail=1
    fi

    # --- The workdir hook's rewrite prefix has a matching allow entry -------
    #
    # `bash-workdir-hook.sh` rewrites every shell call to `cd "<root>" && …`,
    # and Claude Code splits on `&&` and permission-checks each part — so the
    # prefix needs its own allow entry or every shell call prompts.
    #
    # ⚠️ This was wrong for BOTH platforms at once until 2026-08-07, and it
    # went unnoticed for sessions because the failure mode of a missing allow
    # entry is a prompt, not an error. The single entry named the Linux path
    # unquoted; the Mac path had none, and a later fix made the hook emit
    # `cd "…"` with quotes, which silently stopped the Linux entry matching
    # too. Two separate regressions, one invisible symptom.
    #
    # So the check derives the prefix from the hook itself rather than
    # restating it: whatever quoting or path the hook emits, an allow entry
    # has to cover it.
    # ⚠️ Local harness only. The hook is a Claude Code `PreToolUse` hook; it does
    # not exist on a CI runner, in a worktree, or in a fresh clone at some other
    # path — and the allow entries are absolute paths, so on any of those the
    # check would fail for a machine the settings file cannot possibly name.
    # It did exactly that on its first push: red CI on `e689fb9`, with the local
    # gate green, because the runner's root is `/home/runner/work/…`.
    #
    # The rule this encodes is one this repo already learnt from the opposite
    # direction — a guard reporting a failure whose own premise is false. The
    # premise here is "the hook runs on this machine", so the check has to
    # establish that before it can mean anything.
    in_worktree=$([ "$(git rev-parse --git-dir 2>/dev/null)" \
                 != "$(git rev-parse --git-common-dir 2>/dev/null)" ] && echo yes || echo no)
    if [ -z "${CI:-}" ] && [ "$in_worktree" = no ] \
       && [ -f scripts/bash-workdir-hook.sh ] && grep -q 'cd \\"' scripts/bash-workdir-hook.sh; then
        # The hook emits a quoted prefix. Every root it can anchor to needs an
        # entry: this repo, and its worktrees directory.
        root_now=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
        missing=""
        for want in "cd \"$root_now\"" "cd \"$root_now/.claude/worktrees/"; do
            if ! jq -e --arg w "$want" \
                '[.permissions.allow[]? | select(startswith("Bash(" + $w))] | length > 0' \
                .claude/settings.json >/dev/null 2>&1; then
                missing="$missing\n      Bash($want…)"
            fi
        done
        if [ -n "$missing" ]; then
            note "$(printf 'bash-workdir-hook.sh rewrites every shell call to `cd "<root>" && …`, and Claude Code permission-checks that prefix separately — but .claude/settings.json has no allow entry matching it, so every shell call prompts. Add:%b' "$missing")"
            fail=1
        fi
    fi
fi

# --- Every input sheet is reachable from the master input list --------------
#
# The user's rule, 2026-08-02: *"if manual input is allowed on a card, it must
# be in the View and add sub menu of the card, in the + master add button, in
# the add or update section of the settings sub menu"*. The last two are
# generated from `InputKind`, and `InputKindTests` holds the first — but all of
# that only binds inputs that were *declared*. The failure that prompted the
# rule was an input nobody declared at all: a build-override picker inside a
# chart and a dose button inside a section, each opening a sheet that no list
# knew about.
#
# So: any view whose name ends in `Sheet` under Features/ has to be named in
# `AddDataView.swift`, which is where `InputSheet` switches over every
# `InputKind`. Writing an input the master list cannot open is the thing that
# stops building.
if [ -d HealthInsights/Features ] && [ -f HealthInsights/Features/Inputs/AddDataView.swift ]; then
    master=$(cat HealthInsights/Features/Inputs/AddDataView.swift)
    unlisted=""
    while IFS= read -r sheet; do
        [ -z "$sheet" ] && continue
        case "$master" in
            *"$sheet"*) ;;
            *) unlisted="$unlisted $sheet" ;;
        esac
    done <<EOF
$(grep -rhoE 'struct [A-Za-z]+Sheet: View' HealthInsights/Features \
    | sed -E 's/struct ([A-Za-z]+Sheet): View/\1/' | sort -u)
EOF
    if [ -n "$unlisted" ]; then
        note "Input sheets the master list cannot open — add an InputKind case and a branch in AddDataView.swift's InputSheet:$unlisted"
        fail=1
    fi
fi

# --- Data detail pages follow the scaffold convention ----------------------
#
# The user's rule, 2026-08-02: *"not only do we need to have a data menu for
# every data type, but those menus need to follow at least a minimum convention
# of how those subpages are built… so I don't need to keep reprompting."* The
# convention is `DomainDataScaffold` (title, optional shared-component chart,
# entries newest-first, standard empty state), and this is what stops a new
# domain page reinventing its own shape — which is what shipped the substance
# page opening the *add* screen and side effects opening nothing.
#
# Any `<Domain>DataView` under Features/Data must be built with the scaffold.
# `CardDataView` is the one exclusion: it is a card-scoped *browser* over many
# domains, not a single-domain page, so it composes the domain rows itself.
if [ -d HealthInsights/Features/Data ]; then
    nonconforming=""
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$(basename "$f")" in
            CardDataView.swift) continue ;;
        esac
        grep -q 'DomainDataScaffold' "$f" || \
            nonconforming="$nonconforming $(basename "$f")"
    done <<EOF
$(grep -rlE 'struct [A-Za-z]+DataView: View' HealthInsights/Features/Data 2>/dev/null)
EOF
    if [ -n "$nonconforming" ]; then
        note "Data detail pages that skip DomainDataScaffold — every domain data page must use it (see docs/data-conventions.md):$nonconforming"
        fail=1
    fi

    # --- Every DataDomain section actually opens something -----------------
    #
    # Backlog D47. `DomainDataScaffold`'s own doc comment claimed
    # "DataTabView.detailPage(for:) is exhaustive over DataDomain — a new kind
    # of data cannot ship without a detail page". **No such function has ever
    # existed.** The exhaustive switch is `section(for:)` and it renders a
    # *section*; the page is reached by a NavigationLink written by hand in each
    # section body. So a domain could ship with a section that is a dead end and
    # every check passed.
    #
    # That is worse than having no rule: a reader who trusts the comment stops
    # looking. This makes the claim true instead of softening it — each branch
    # of `section(for:)` names a section body, and every one of those bodies has
    # to contain a NavigationLink somewhere.
    if [ -f HealthInsights/Features/Data/DataTabView.swift ] && command -v python3 >/dev/null 2>&1; then
        # Brace-matched, because a line-range heuristic silently reads past the
        # section into its neighbours and then every section looks fine.
        deadends=$(python3 - <<'PYEOF'
import re, pathlib, sys
src = pathlib.Path('HealthInsights/Features/Data/DataTabView.swift').read_text().splitlines()
sw = '\n'.join(src)
m = re.search(r'func section\(for domain: DataDomain\).*?\n    \}', sw, re.S)
names = re.findall(r'case \.\w+: *(\w+)\s*$', m.group(0), re.M) if m else []
bad = []
for n in names:
    start = next((i for i, l in enumerate(src) if re.search(rf'var {n}\s*:', l)), None)
    if start is None:
        continue
    depth = 0
    for i in range(start, len(src)):
        depth += src[i].count('{') - src[i].count('}')
        if depth == 0 and i > start:
            body = '\n'.join(src[start:i + 1])
            # A section may declare itself a dead end on purpose, but it has to
            # say why — same contract as the substance-shading exemption.
            if 'NavigationLink' not in body and 'data-detail: exempt' not in body:
                bad.append(n)
            break
print(' '.join(bad))
PYEOF
)
        if [ -n "$deadends" ]; then
            note "Data-tab sections that open no detail page — every DataDomain section must contain a NavigationLink to its page, or the Data tab shows a row that goes nowhere (backlog D47, docs/data-conventions.md). Add the page, or a '// data-detail: exempt — <why>' comment in the section:$deadends"
            fail=1
        fi
    fi

    # And a data page never hand-rolls a chart. The chart rules live in the
    # shared components (`SubstanceLoadChart`, `MedicationCurveChart`, …) and in
    # the `add-chart` skill; a raw `Chart {` in a domain page is how those rules
    # get skipped. `OtherDataDetailView` is exempt — it is the review surface for
    # *unmodelled* imported data, which has no shared component by definition.
    # `(^|[^A-Za-z0-9_])Chart` so a *component* whose name ends in "Chart"
    # (`SubstanceLoadChart(`) is not mistaken for the raw Swift Charts `Chart`.
    rawcharts=$(grep -rlE 'struct [A-Za-z]+DataView: View' HealthInsights/Features/Data 2>/dev/null \
        | xargs grep -lE '(^|[^A-Za-z0-9_])Chart[ ]*[({]' 2>/dev/null || true)
    if [ -n "$rawcharts" ]; then
        note "Data pages drawing a raw Chart — use a shared chart component so the add-chart rules hold:$(printf ' %s' $(basename $rawcharts))"
        fail=1
    fi
fi

# --- The full export must pass every argument it has -----------------------
#
# Backlog D39: `DataExportView.buildFullExport()` shipped without passing
# `cycles:`, so every logged bleeding day exported as `[]`. The key was present
# and the data was not, which is worse than a missing key — nothing in the file
# says anything was dropped.
#
# **No test in InsightKit can catch this and none ever will.** The gap is in the
# caller: `HealthDataExport.init` defaults the argument, the app target has a
# single native target with no test host, and `HealthDataExportTests` asserts on
# the encoded payload of a bundle it built itself. So the check lives here.
#
# The reader's tenet, 2026-08-06: *"we need to build this into the export
# mechanism, all the data points so when we combine it all at a server-level
# later, we can build these baselines and norms and global trends."* The export
# is the only route from a phone to a pool, so an argument silently defaulted is
# a quantity that can never become a norm. See `docs/norms-and-telemetry.md`.
#
# A defaulted argument the caller genuinely should not pass would need its own
# exemption; there is none today, and adding one should be argued for in the
# initialiser's doc comment first.
exportsrc=InsightKit/Sources/InsightKit/Text/HealthDataExport.swift
exportcaller=HealthInsights/Features/Settings/DataExportView.swift
if [ -f "$exportsrc" ] && [ -f "$exportcaller" ]; then
    initblock=$(awk '/public init\(generatedAt:/,/\) \{/' "$exportsrc")
    missing=""
    for label in $(printf '%s' "$initblock" | grep -oE '[a-zA-Z]+:' | tr -d ':'); do
        grep -q "$label:" "$exportcaller" || missing="$missing $label"
    done
    if [ -n "$missing" ]; then
        note "HealthDataExport arguments the app never passes, so they export empty:$missing"
        fail=1
    fi
fi

# --- ...and every DataDomain must HAVE an argument, or declare why not ------
#
# Backlog D50, found while diagnosing the reader's 2026-08-07 report that new
# data types *"aren't making it into exports by default"*.
#
# The check above closed one half and left the other open: **it only ever
# covered arguments that already existed.** Nothing required a `DataDomain` to
# have one at all. So the three things enforced when a new domain lands were
#
#   1. it must render a Data-tab section  (compiler, exhaustive switch)
#   2. it must NAME an export key         (compiler, exhaustive switch)
#   3. the caller must pass every existing argument   (the check above)
#
# — and a domain could satisfy all three with a section, a key, and **no data in
# the file**. The live instance was `calendarEvents`, which returns the
# "unmodelled" key and emits nothing into it.
#
# So: a domain's key must be an initialiser argument the caller passes, **and
# where two or more domains share a key, each of them must carry a declaration**
#
#     // export-domain: <case> — <why it has no argument of its own>
#
# A shared key is the shape the hole takes. At most one of the domains sharing
# it owns the argument, so for the others nothing in the codebase can tell
# whether their data is really in the file — only a human sentence can, and this
# forces one to exist next to the switch. Sharing a key is legitimate (a cuff
# reading genuinely is a `HealthMetricSample`); sharing one *silently* is not.
#
# The em dash and a non-trivial reason are both required, same contract as the
# substance-shading exemption: "// export-domain: foo —" is not a reason.
domainsrc=InsightKit/Sources/InsightKit/Presentation/DataDomain.swift
if [ -f "$exportsrc" ] && [ -f "$exportcaller" ] && [ -f "$domainsrc" ] \
    && command -v python3 >/dev/null 2>&1; then
    domainissues=$(python3 - "$exportsrc" "$exportcaller" "$domainsrc" <<'PYEOF'
import re, sys, pathlib

exportsrc, exportcaller, domainsrc = (pathlib.Path(p) for p in sys.argv[1:4])
export = exportsrc.read_text()
caller = exportcaller.read_text()
domains_text = domainsrc.read_text()

# Every declared DataDomain case. `case foo` only — `case .foo: return …` in the
# title/summary switches starts with a dot and is not a declaration.
cases = re.findall(r'^\s*case ([a-z]\w*)\s*$', domains_text, re.M)

# The exportKey switch, brace-matched from its own signature. A line-range
# heuristic reads on into the next function and then everything looks fine.
start = export.find('func exportKey(for domain: DataDomain) -> String {')
key_for = {}
if start != -1:
    depth, i = 0, start
    while i < len(export):
        if export[i] == '{':
            depth += 1
        elif export[i] == '}':
            depth -= 1
            if depth == 0:
                break
        i += 1
    body = export[start:i + 1]
    for match in re.finditer(r'^\s*case ((?:\.\w+\s*,?\s*)+):\s*return "([^"]+)"',
                             body, re.M):
        for case in re.findall(r'\.(\w+)', match.group(1)):
            key_for[case] = match.group(2)

# The initialiser's argument labels, and the ones the caller actually passes.
init_match = re.search(r'public init\(generatedAt:.*?\)\s*\{', export, re.S)
labels = set(re.findall(r'(\w+):', init_match.group(0))) if init_match else set()
passed = {label for label in labels if re.search(rf'\b{label}:', caller)}

# Declarations, with a reason that is actually a reason.
declared = {m.group(1) for m in
            re.finditer(r'//\s*export-domain:\s*(\w+)\s*[—-]\s*(\S.{9,})', export)}

shared = {key for key in set(key_for.values())
          if sum(1 for c in cases if key_for.get(c) == key) > 1}

problems = []
for case in cases:
    key = key_for.get(case)
    if key is None:
        problems.append(f'{case} (names no export key at all)')
        continue
    if key not in passed:
        problems.append(f'{case} -> "{key}" (no initialiser argument the app passes)')
        continue
    if key in shared and case not in declared:
        problems.append(f'{case} -> "{key}" (shares the key; needs '
                        f'"// export-domain: {case} — <why>")')
print('; '.join(problems))
PYEOF
)
    if [ -n "$domainissues" ]; then
        note "DataDomains whose data may not be in the export (backlog D50) — give the domain its own HealthDataExport.init argument and pass it, or declare '// export-domain: <case> — <why>' beside its branch of exportKey(for:): $domainissues"
        fail=1
    fi
fi

# --- The sync's completion is never gated on an optional enrichment --------
#
# ⚠️ Found on the reader's phone 2026-08-07: "Data no longer showing in the app",
# with a diagnostics log carrying `Refresh started` and **no `Refresh complete`
# at all** five minutes later, plus a 12.75 s main-thread block.
#
# `performRefresh` awaited `refreshTagApplicability()` before its completion
# marker. That function loops serially over up to twelve tags, building a fresh
# `LanguageModelSession` and awaiting a full on-device model response for each —
# right for the classifier, fatal in front of the marker. The sync never
# finished, so `lastRefreshedAt` never moved and the cards never learnt the data
# had arrived.
#
# **The class this checks: an on-device model call is never awaited on the path
# that tells the app its data is ready.** Enrichment that "can only improve a
# heading" must not be able to stop the heading existing.
if [ -f HealthInsights/Core/State/AppModel.swift ]; then
    gated=$(awk '/private func performRefresh/,/^    \}/' \
        HealthInsights/Core/State/AppModel.swift \
        | grep -nE 'await .*(Applicability|Summarizer|LanguageModel|onDeviceModel)' \
        | grep -vE '^[0-9]+:[[:space:]]*(//|\*)' \
        | grep -vE 'Task[[:space:]]*(\{|\.detached)' || true)
    if [ -n "$gated" ]; then
        note "performRefresh awaits an on-device model call before it reports the sync complete. Detach it — the reader lost every card to exactly this on 2026-08-07:"
        printf '%s\n' "$gated"
        fail=1
    fi
fi

# --- ...and that enrichment pass runs from exactly ONE call site (D66) ------
#
# The check above proves the call is detached; it says nothing about how many
# there are. The 2026-08-08 merge briefly left `refreshTagApplicability()`
# called from two places, and two concurrent detached passes race on
# `tagMappings` — both read the map, both write it back, last writer wins and
# one pass's classifications are silently dropped. Nothing crashes and nothing
# reports it; the reader's tags just quietly lose answers. (Suggested by the
# B12 agent, whose store the race would corrupt.)
#
# Exactly one call site is the invariant, so it is counted rather than
# remembered — and zero is as red as two, because zero means the tag pass
# never runs at all. Parallel agents have collided on this file before: if you
# are adding a feature that needs the pass re-run, route it through the
# existing call site rather than adding a second.
if [ -f HealthInsights/Core/State/AppModel.swift ]; then
    tagcalls=$(grep -nE 'refreshTagApplicability\(\)' \
        HealthInsights/Core/State/AppModel.swift \
        | grep -vE '^[0-9]+:[[:space:]]*(//|\*)' \
        | grep -vE 'func refreshTagApplicability' || true)
    tagcallcount=$(printf '%s\n' "$tagcalls" | grep -c . || true)
    if [ "$tagcallcount" -ne 1 ]; then
        note "refreshTagApplicability() must have exactly ONE call site in AppModel and has $tagcallcount — two concurrent detached passes race on tagMappings and the last writer silently drops the other's classifications (backlog D66):"
        printf '%s\n' "${tagcalls:-(no call site at all — the tag pass never runs)}"
        fail=1
    fi
fi

# --- BSD pgrep has no count flag — a script asking for one reads 0 (D65) ----
#
# `$(pgrep -cf foo)` on macOS prints usage to stderr, exits 2, and expands to
# the empty string — and a `${var:=0}` default then reports a confident **0**.
# It had the D63 load reporter printing "0 xcodebuild" while an xcodebuild was
# holding the build database against it: evidence for the wrong conclusion,
# which is worse than no evidence. Correct form: `pgrep -f foo | wc -l`.
# The 2026-08-08 sweep found no live instance left; this keeps it that way.
pgrepcount=$(grep -rnE 'pgrep +-[A-Za-z]*c' scripts/ 2>/dev/null \
    | grep -vE ':[[:space:]]*#' || true)
if [ -n "$pgrepcount" ]; then
    note "BSD pgrep has no count flag, so this counts as 0 on macOS. Use 'pgrep -f ... | wc -l' instead (backlog D65):"
    printf '%s\n' "$pgrepcount"
    fail=1
fi

# --- The export never reads a lazy view cache ------------------------------
#
# Found 2026-08-07 in the reader's own export: all 18 cards carried
# `history: []` while SwiftData held the rows. `DataExportView.buildFullExport()`
# called `model.scoreHistory(for:)`, which is a **lazy view cache** — it returns
# `[]` and queues a background replay when a card's chart has not been drawn.
# Correct for a view racing to a first frame; wrong for an export that asks
# about every card at once and waits for nothing.
#
# ⚠️ **Why this is a lint and not a test.** It is D39's class exactly — the key
# existed, the data existed, the payload was empty — and `HealthDataExportTests`
# cannot catch it, because it builds its own bundle rather than going through
# this caller. The app target has no test host reaching `DataExportView`.
#
# ⚠️ **And this one mattered beyond the file:** with no exported history there
# are no prediction-versus-actual pairs, so nothing could ever grade a model.
# The app could not learn from itself.
exportcaller=HealthInsights/Features/Settings/DataExportView.swift
if [ -f "$exportcaller" ]; then
    # Skip comment lines — this repo's house style is that a fix records the
    # shape it replaced, right where it was made, so the banned pattern is
    # quoted in the very file that no longer commits it. Same filter `ban` uses.
    lazy=$(grep -nE 'model\.scoreHistory\(for:' "$exportcaller" \
        | grep -vE '^[0-9]+:[[:space:]]*(//|\*|///)' || true)
    if [ -n "$lazy" ]; then
        note "The export reads AppModel's lazy score-history cache, which returns [] until a card's chart has been drawn — use model.storedScoreHistory(for:), which fetches from SwiftData:"
        printf '%s\n' "$lazy"
        fail=1
    fi
fi

# --- Every chart carries the substance shading -----------------------------
#
# The user's rule, 2026-08-03: *"make sure the stimulant impact shading is on
# EVERY chart in the app, and this is a design rule going forward."*
#
# "Going forward" is the part a lint has to carry: the shading was on one chart
# for months because each new chart's author had no reason to know about it.
# `ScrollableMetricChart` now draws it for every chart that wraps it, so the
# only files this can catch are the ones building a raw chart of their own
# — which is exactly where the rule gets skipped.
#
# A file passes if it wraps `ScrollableMetricChart`, calls `SubstanceShading`
# itself, or carries the exemption marker with a reason:
#     // substance-shading: exempt — <why>
# An exemption is for a chart whose x axis is not a date (a projection in months
# ahead, a scatter). There is no exemption for "it did not seem relevant".
#
# ⚠️ **`[({]`, not `\{`** — backlog D11, found on the simulator. This matched
# only `Chart {` and so never saw `Chart(data) { … }`, the data-driven form.
# `OtherDataDetailView`'s chart used it and had gone unshaded since the day it
# shipped, while the *sibling* lint fifty lines above (no raw chart in a data
# page) had matched both forms all along. Widening it caught exactly that one
# file, which is now shaded.
chartfiles=$(grep -rlE '(^|[^A-Za-z0-9_])Chart[ ]*[({]' HealthInsights --include=*.swift 2>/dev/null || true)
unshaded=""
for f in $chartfiles; do
    case "$(basename "$f")" in
        ScrollableMetricChart.swift|SubstanceShading.swift) continue ;;
    esac
    # Comment lines don't build charts. `DomainDataScaffold` documents the rule
    # that a data page never hand-rolls a `Chart {}`, and was flagged for saying
    # so — a lint that fires on prose about itself teaches people to ignore it.
    grep -nE '(^|[^A-Za-z0-9_])Chart[ ]*[({]' "$f" \
        | grep -qvE '^[0-9]+:[[:space:]]*(///|//|\*)' || continue
    grep -q 'ScrollableMetricChart\|SubstanceShading\|substance-shading: exempt' "$f" \
        || unshaded="$unshaded $(basename "$f")"
done
if [ -n "$unshaded" ]; then
    note "Charts with no substance shading — wrap ScrollableMetricChart, call SubstanceShading, or mark '// substance-shading: exempt — <why>':$unshaded"
    fail=1
fi

# --- Rule 5's other half: a bespoke section that is present but empty -------
#
# Backlog G-check-3. The reader's rule 5 is *every card gets a bespoke section*,
# and `InsightDetailView.bespokeSection` is exhaustive over `InsightID`, so a new
# card cannot ship without **a** branch. That is only half the rule: `EmptyView()`
# closes a case, compiles, and renders nothing — so **a section nobody has
# written yet is textually identical to a section deliberately drawn elsewhere.**
#
# That is not hypothetical. An audit on 2026-08-06 read this switch, found a bare
# `EmptyView` on `.readiness`, and listed a card that *does* have a picture among
# the cards with none. The screen and the switch disagreed and the switch won.
#
# So the deliberate absence has to declare itself:
#     case .readiness:
#         noBespokeSection(because: "…")
# and a bare `EmptyView` inside this one property fails. `EmptyView` elsewhere in
# the file is fine and is not touched — `projectionSection` and
# `secondaryBespokeSection` both carry a `default:` arm, which is a switch over
# *some* cards by design rather than a promise about all of them.
bespokefile=HealthInsights/Features/Insights/InsightDetailView.swift
if [ -f "$bespokefile" ]; then
    # From the declaration to the closing brace at four-space indent — the same
    # extraction `check_switch_covers` uses above.
    bespokebody=$(awk '/var bespokeSection/,/^    }$/' "$bespokefile" 2>/dev/null)
    if [ -z "$bespokebody" ]; then
        note "verify.sh cannot find InsightDetailView.bespokeSection — the rule-5 check above is silently checking nothing. Fix the extraction, or move the check to wherever the switch now lives."
        fail=1
    elif printf '%s' "$bespokebody" | grep -nE 'EmptyView' \
            | grep -qvE '^[0-9]+:[[:space:]]*(///|//|\*)'; then
        note "A card's bespoke section is a bare EmptyView, which cannot be told from a section nobody has written (rule 5, backlog G-check-3). Draw something, or declare the absence: noBespokeSection(because: \"<why>\")"
        printf '%s' "$bespokebody" | grep -nE 'EmptyView' \
            | grep -vE '^[0-9]+:[[:space:]]*(///|//|\*)'
        fail=1
    fi
fi

# --- A hard-coded count inside reader-facing copy ---------------------------
#
# Backlog D19 / G-check-2. A section shipped saying *"All four sitting where they
# usually sit"* on a card that was running on **three** signals, and Mental
# Health's empty-state line named all four behaviours it watches including the
# one it had no data for. Fixed once, in `adca807`, and pinned with a test on
# that one card. Nothing stopped the next one.
#
# This is the repo's own ledger row *"a hard-coded count going stale"* — except
# inside a sentence, where it is worse, because the sentence is a claim about
# what the app looked at.
#
# ## What is checked, and why it is this narrow
#
# The obvious lint — any number word in any copy — was measured before it was
# written: **139 hits, nearly all of them legitimate physiology** ("a broken
# seven hours", "your own three-week baseline", "it can swing two kilograms").
# A lint at that signal-to-noise ratio teaches people to ignore lints.
#
# What is actually checkable is narrower and is the real defect: **a spelled-out
# number standing directly in front of one of the app's own collection nouns** —
# four *signals*, seven *behaviours*, three *cards*. That is an assertion about
# the size of something the code owns, and the code can change its size. A
# back-reference ("the two differ", "of the two figures") is not that, so an
# anaphoric determiner in front of a weak noun is skipped. That took 139 to 17.
#
# The two escape hatches, in order of preference:
#   1. Derive it: `\(out.channels.count) signals`. Nothing to go stale.
#   2. `// count-in-copy: exempt — <why>` on the line or the line above, when the
#      count is structural (a two-term equation) or a threshold ("at least two
#      signals") rather than the size of a collection.
# `scripts/count-in-copy-reviewed.txt` is the third: the seventeen strings that
# predate this lint, each reviewed on 2026-08-07 with a reason. It is a ledger of
# what was checked, not a place to add new copy.
if command -v python3 >/dev/null 2>&1; then
    countcopy=$(python3 - <<'PYEOF'
import os, re, sys

WORDS = (r'(?:two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|'
         r'thirteen|fourteen|fifteen|sixteen|seventeen)')
# Nouns naming a collection the code owns. A count in front of one of these is
# an assertion about a size, even with a determiner ("the four cards").
STRONG = (r'(?:signals?|behaviours?|behaviors?|channels?|markers?|cards?|vitals?|'
          r'metrics?|models?|equations?|measures|sections?|inputs?|insights?|domains?)')
# Nouns that are just as often anaphoric ("the two figures the equation
# compares"). Flagged only when nothing points backwards.
WEAK = (r'(?:things?|numbers?|figures?|terms?|factors?|components?|contributors?|'
        r'readings?|scores?|sources?|series|items?|entries)')
ANA = r'(?:the|these|those|other|any|your|its|our)'
# At most two adjectives between the count and the noun, and none of them a
# determiner or preposition — otherwise the gap walks across a clause boundary
# and matches a noun in the *next* phrase.
GAP = (r'(?:\s+(?!the\b|a\b|an\b|this\b|that\b|these\b|those\b|of\b|in\b|on\b|'
       r'and\b|or\b|it\b|its\b|your\b|my\b)[a-z]+){0,2}?')

strong_re = re.compile(r'(?<!\w)' + WORDS + r'\b' + GAP + r'\s+' + STRONG + r'\b', re.I)
weak_re = re.compile(r'(?<!\w)(?:(' + ANA + r')\s+)?' + WORDS + r'\b' + GAP
                     + r'\s+' + WEAK + r'\b', re.I)
literal_re = re.compile(r'"((?:[^"\\]|\\.)*)"')

reviewed = set()
ledger = 'scripts/count-in-copy-reviewed.txt'
if os.path.exists(ledger):
    for raw in open(ledger, encoding='utf-8'):
        raw = raw.strip()
        if not raw or raw.startswith('#'):
            continue
        parts = raw.split('|')
        if len(parts) >= 2:
            reviewed.add((parts[0].strip(), parts[1].strip().lower()))

hits = []
for root in ('InsightKit/Sources', 'HealthInsights'):
    for dirpath, _, files in os.walk(root):
        for name in sorted(files):
            if not name.endswith('.swift'):
                continue
            path = os.path.join(dirpath, name)
            lines = open(path, encoding='utf-8').read().splitlines()
            for i, line in enumerate(lines):
                stripped = line.strip()
                # A comment cannot reach the reader, and this file's own prose
                # about the rule must not trip it.
                if stripped.startswith(('//', '*', '/*')):
                    continue
                nearby = line + (lines[i - 1] if i else '')
                if 'count-in-copy: exempt' in nearby:
                    continue
                for literal in literal_re.finditer(line):
                    text = literal.group(1)
                    # Short literals are identifiers, keys and format fragments.
                    if len(text) < 20:
                        continue
                    found = [m.group(0) for m in strong_re.finditer(text)]
                    found += [m.group(0) for m in weak_re.finditer(text)
                              if not m.group(1)]
                    for fragment in found:
                        if (path, fragment.lower()) in reviewed:
                            continue
                        hits.append('%s:%d  "%s"  in: %s'
                                    % (path, i + 1, fragment, text[:90]))

for hit in hits:
    print(hit)
PYEOF
    ) || countcopy=""
    if [ -n "$countcopy" ]; then
        note "Reader-facing copy states a count in words. Derive it from the collection — \"\\(out.channels.count) signals\" — or, where the count is structural rather than a collection size, mark the line '// count-in-copy: exempt — <why>'. Backlog D19: a section said \"All four\" on a card running on three signals.
$countcopy"
        fail=1
    fi
fi

# --- The fertile window says it is not contraception ------------------------
#
# A fertile window presented as a way to *avoid* pregnancy is a regulated
# medical claim — it is what makes Natural Cycles a cleared device and a period
# tracker not one. This app makes no such claim, and the screen has to say so
# where it cannot be missed.
#
# The rule is mechanical rather than editorial: any view that renders a
# `FertileWindow` must also render `CyclePhaseModel.notContraceptionNotice`,
# which is a constant in InsightKit with a test on its wording. A redesign can
# move the caption; it cannot drop it and still pass.
fertileviews=$(grep -rlE 'fertileWindow|FertileWindow' HealthInsights --include=*.swift 2>/dev/null || true)
missingnotice=""
for f in $fertileviews; do
    grep -q 'notContraceptionNotice' "$f" || missingnotice="$missingnotice $(basename "$f")"
done
if [ -n "$missingnotice" ]; then
    note "A view draws the fertile window without CyclePhaseModel.notContraceptionNotice on screen. The sentence is not optional and not a disclosure:$missingnotice"
    fail=1
fi

# --- Nothing may clear this script's own verdict ---------------------------
#
# On 2026-08-02 `verify.sh --tests` exited 0 on a tree that plain `verify.sh`
# exited 1 on. The runner-artifact recovery in the test block set `fail=0` to
# undo a false failure it had just diagnosed — and `fail` is shared with every
# lint above it, so a lint failure was erased whenever the serial re-run passed.
# The mode CLAUDE.md mandates before every push was the *weaker* of the two, and
# it shipped a tuple key path to `main` that the lint had correctly caught.
#
# The general shape: **a recovery may only undo the thing it diagnosed.** A
# recovery that clears a flag it does not own silently forgives everything else
# that set it. So `fail` is set to 0 exactly once, where it is declared, and any
# recovery gets its own flag — `testfail` is the pattern.
#
# Self-referential on purpose: this file is the gate, so nothing else is in a
# position to check it.
# The needle is assembled from two pieces so that **this check's own source
# never matches it** — otherwise the grep line, and the line excluding the grep
# line, are themselves hits, and the check can only be made to pass by
# weakening it. Excluded beyond that: comment lines and the sole top-level
# declaration in column one.
needle="fail=""0"
stray=$(grep -nE "(^|[^a-zA-Z_])${needle}" "$0" \
    | grep -vE '^[0-9]+:[[:space:]]*#' \
    | grep -vE "^[0-9]+:${needle}$" || true)
if [ -n "$stray" ]; then
    note 'Something clears verify.sh'"'"'s own verdict after a check has set it. A recovery may only undo the thing it diagnosed — give it its own flag, as `testfail` does:'
    printf '%s\n' "$stray"
    fail=1
fi

# --- A band table is a curve, not a staircase ------------------------------
#
# `case 6..<7: return 65` next to `case 7..<7.5: return 85` is twenty points of
# a reader's score for four seconds of sleep. Clinical guidance arrives as
# bands, and scoring a band table with a `switch` over numeric ranges puts a
# step at every edge — on quantities that wander across those edges by
# measurement noise alone.
#
# A sweep on 2026-08-02 found seven of these across the 17 models. The worst was
# 40 points of the blood-pressure card for a tenth of a millimetre of mercury.
# `ScoreCurve.through` is the replacement and `ScoreContinuityTests` is the
# guard; this stops the shape coming back, because the guard only covers curves
# somebody remembered to enrol.
#
# Comment lines are skipped: `ScoreCurve` and `SleepInsight` both quote the old
# shape in their doc comments, which is the point of the doc comments.
bandswitch=$(grep -rnE '^[^/]*case [0-9.]+\.\.[.<][0-9.]+: *return [0-9.]+' \
    InsightKit/Sources/InsightKit 2>/dev/null || true)
if [ -n "$bandswitch" ]; then
    note 'A numeric band table scored with a `switch` — every edge is a step in a card score. Use `ScoreCurve.through` and enrol it in ScoreContinuityTests:'
    printf '%s\n' "$bandswitch"
    fail=1
fi

# --- A test that asserts nothing is worse than no test ---------------------
#
# `ZZProbeTests` sat in the suite for several sessions: a scratch diagnostic
# that printed four numbers, asserted nothing, and passed every run. It cost
# build time on every push and protected nothing, while reading in the test
# count as though it did.
#
# That is the same failure as the two vacuous fixtures caught on 2026-08-02
# (jitter `(day * 3) % 3`, which is identically zero) — a test that cannot
# fail. The general form is uncatchable by grep; a whole *file* with no
# assertion in it is not, and it is the cheap end of the same category.
#
# XCTAssert*, XCTUnwrap, XCTFail and swift-testing's #expect/#require all
# count. A file that has none of them is not testing anything.
if [ -d InsightKit/Tests ]; then
    noassert=""
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        grep -qE 'XCTAssert|XCTUnwrap|XCTFail|#expect|#require' "$f" || \
            noassert="$noassert $(basename "$f")"
    done <<EOF
$(grep -rlE '(final )?class [A-Za-z]+: XCTestCase|@Test' InsightKit/Tests 2>/dev/null)
EOF
    if [ -n "$noassert" ]; then
        note "Test files that assert nothing — a test that cannot fail proves nothing and still costs a build. Give it an assertion or delete it:$noassert"
        fail=1
    fi
fi

# --- No half-done markers in the roadmap -----------------------------------
#
# `- [~]` means "some clauses of this are done and some are not", and it is the
# anti-pattern this repo has already paid for twice: a multi-clause item hides
# its unfinished clauses, and three `[~]` rows survived four pushes describing
# work that had shipped.
#
# There is no legitimate resting state for it. Either the item is done (`[x]`),
# or the unfinished clause is its own `[ ]` item with its own sentence. Being
# made to split it is the point — that is the fix for the failure mode, not a
# formatting preference.
if [ -d docs ]; then
    # Every audited doc, any bullet character, any indentation, and any box that
    # is neither open nor done. The first version matched `^- [~]` in one file,
    # so an indented item, a `*` bullet, a `[-]`, or the same marker in
    # activeContext.md all walked straight past it.
    partial=$(grep -nE '^[[:space:]]*[-*] \[[^ xX]\]' docs/*.md 2>/dev/null || true)
    if [ -n "$partial" ]; then
        note 'Half-done checkbox markers — only `[ ]` and `[x]` are legitimate. Split each into a done `[x]` and an open `[ ]`, because a multi-clause item hides its unfinished clauses:'
        printf '%s\n' "$partial"
        fail=1
    fi
fi

# --- No personal identifiers in a public repository ------------------------
#
# This repo is public and holds one person's health app. Two classes of thing
# must never be committed, and both were found in it on 2026-08-03:
#
#   * a device UDID, hardcoded as a fallback in deploy.yml, and
#   * real health values quoted in the docs as evidence.
#
# The second is the harder one to police and is deliberately NOT linted: the
# docs are an audit and their numbers are what make findings checkable. The rule
# there is judgement — quote a *shape* ("the median rose"), not a reading.
#
# What is linted is the mechanical class: identifiers that are unambiguously
# personal hardware or accounts, which have no business in source at all.
#
# ⚠️ **A lint cannot unpublish anything.** Git history keeps what was committed,
# so this stops the next one rather than removing the last one. See
# docs/privacy-and-ip.md.
#
# `deploy.yml` is exempt by path. Its pinned device UDID was removed on
# 2026-08-03 and requiring a secret instead broke the next deploy; the user
# chose to keep the default. Exempting one known line by path — rather than
# loosening the pattern — keeps every *other* identifier caught.
# **Asks `git ls-files`, not the filesystem**, for the same reason the
# script-exists check does: this lint's own sentence is "looks *committed*", and
# a filesystem walk cannot know whether anything it found is. It walked `.` until
# 2026-08-04, when the app-target compile added `build/verify-ios` and Xcode's
# own build logs — gitignored, never committed, full of activity-log UUIDs —
# failed the gate. `build/simulator` was the same landmine, armed since the
# simulator script landed and waiting for the first person to run both.
#
# Widening the ignore list would have fixed the instance. Reading the index
# fixes the category: a file git does not track cannot leak anything, so the
# question was never about paths.
pii_hits=$(git ls-files -z -- \
    '*.swift' '*.yml' '*.yaml' '*.sh' '*.plist' '*.pbxproj' '*.json' 2>/dev/null \
    | xargs -0 grep -InE \
      '\b[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\b|\b[0-9]{8}-[0-9A-F]{16}\b' \
      2>/dev/null \
    | grep -viE 'UUID\(\)|uuidString|test|mock|fixture|00000000-0000|E621E1F8|deadbeef' \
    | grep -v '^\.github/workflows/deploy\.yml:' \
    | head -5 || true)
if [ -n "$pii_hits" ]; then
    printf '\033[31m✗\033[0m %s\n' 'A hardware or account identifier looks committed:'
    printf '    %s\n' "$pii_hits"
    note 'If it is a device UDID or similar, move it to a repository secret.'
    fail=1
fi

# --- The symbol index must not rot -----------------------------------------
# A stale index is worse than no index, because it gets trusted.

if [ -f docs/symbol-index.md ] && [ -x scripts/gen-symbol-index.sh ]; then
    # Regenerate to a scratch copy and compare — generating over the real file
    # and diffing it against itself always passes, which is the bug this
    # replaces.
    saved=$(mktemp)
    cp docs/symbol-index.md "$saved"
    ./scripts/gen-symbol-index.sh >/dev/null 2>&1 || true
    if ! diff -q "$saved" docs/symbol-index.md >/dev/null 2>&1; then
        note 'docs/symbol-index.md was stale — regenerated. Commit the change.'
        fail=1
    fi
    rm -f "$saved"
fi

# --- The app target must at least parse ------------------------------------
# SwiftUI does not exist on Linux, so nothing here can *type*-check
# `HealthInsights/` and CI has always been the only gate for it. Parsing needs no
# SDK, though, and the brace-balance class is real: one session restructured
# `InsightDetailView` fourteen times, and a push to discover an unbalanced brace
# is a five-minute round trip for something a tenth of a second answers.
#
# `-parse` only. Not `-typecheck`, which would need the iOS SDK and fail on every
# `import SwiftUI` — a check that always fails is a check nobody reads.
if command -v swiftc >/dev/null 2>&1; then
    # Keyed on swiftc's **exit status**, not on grepping its output for
    # "error:". On this toolchain a file with an unterminated declaration exits
    # non-zero while printing only `note:` lines, so the grep version passed a
    # file that does not parse — caught by canarying the check itself.
    parselog=$(mktemp)
    find "$APP" -name '*.swift' -type f 2>/dev/null | while IFS= read -r f; do
        if ! out=$(swiftc -parse "$f" 2>&1); then
            printf '%s\n%s\n' "$f" "$out" >> "$parselog"
        fi
    done
    if [ -s "$parselog" ]; then
        note 'The app target does not parse:'
        head -12 "$parselog"
        fail=1
    fi
    rm -f "$parselog"
fi

# --- Tests, when a toolchain exists ----------------------------------------

if [ "${1:-}" = "--tests" ]; then
    # shellcheck source=/dev/null
    [ -f scripts/swift-env.sh ] && source scripts/swift-env.sh
    # Self-healing: the container is rebuilt every session, so the toolchain is
    # never there the first time. Bootstrapping here rather than telling the
    # caller to means the gate works even when nobody read CLAUDE.md.
    if ! command -v swift >/dev/null 2>&1; then
        note 'No Swift toolchain — installing one (~2 min, once per container).'
        if ./scripts/bootstrap-swift.sh; then
            # shellcheck source=/dev/null
            source scripts/swift-env.sh
        fi
    fi

    if command -v swift >/dev/null 2>&1; then
        # `--tests <pattern>` runs only the matching suites — for the middle of a
        # change, when the full suite is a slower answer to a narrower question.
        # The full run stays the default and stays the gate: pushing on a
        # filtered pass is how a green filter and a red suite reach `main`.
        # Keep the output. A red run whose log has scrolled away is a red run
        # nobody can diagnose. `tee` would mask the exit status, so read it back
        # out of PIPESTATUS.
        testlog="${TMPDIR:-/tmp}/insightkit-tests.log"

        # **The test run gets its own flag, and this is load-bearing.**
        #
        # It used to set the shared `fail`, and the runner-artifact recovery
        # below then cleared `fail` — erasing *every lint failure above it*. So
        # `verify.sh --tests` exited 0 on a tree that plain `verify.sh` exited 1
        # on, and the mode CLAUDE.md mandates before every push was the weaker
        # of the two. It shipped a `\.0` tuple key path to `main` on 2026-08-02;
        # the lint that exists to catch exactly that had fired and been wiped.
        #
        # A recovery may only undo the thing it diagnosed.
        testfail=0
        if [ -n "${2:-}" ]; then
            note "Running InsightKit tests matching '$2' — NOT the gate. Run without a filter before pushing."
            (cd InsightKit && swift test --parallel --filter "$2" 2>&1 | tee "$testlog"; exit "${PIPESTATUS[0]}") || testfail=1
        else
            note "Running InsightKit tests with $(swift --version | head -1)"
            (cd InsightKit && swift test --parallel 2>&1 | tee "$testlog"; exit "${PIPESTATUS[0]}") || testfail=1
        fi

        # `swift test --parallel` on Linux intermittently exits non-zero after a
        # run in which every test passed — no failing test named, nothing in the
        # log but the pass lines. It has happened three times in one session and
        # cost a diagnosis each time.
        #
        # A retry alone would just hide it, so this is a *different* run rather
        # than the same one again: serial, no parallel workers. If the suite
        # passes serially then every test has genuinely passed and the gate has
        # no business staying red — but it says so loudly, because the day this
        # message means something else is the day it matters.
        if [ "$testfail" -ne 0 ] && [ -z "${2:-}" ] \
           && ! grep -qE "error:|XCTAssert.*failed|Fatal error|Test Suite .* failed" "$testlog"; then
            note 'Non-zero exit but no failing test in the log — re-running serially to tell a runner artifact from a real failure.'
            if (cd InsightKit && swift test 2>&1 | tee "$testlog.serial"; exit "${PIPESTATUS[0]}"); then
                printf '\033[33m!\033[0m %s\n' 'Parallel runner exited non-zero; the serial run passed in full. Treating as a runner artifact.'
                testfail=0
            else
                printf '\033[31m✗\033[0m %s\n' "Serial run failed too — this is real. See $testlog.serial"
            fi
        fi
        if [ "$testfail" -ne 0 ]; then
            fail=1
            note "Full test output kept at $testlog"
        fi
    else
        note 'Could not obtain a Swift toolchain (no network?). CI is the gate — say so in the reply.'
    fi

    # --- The app target, actually type-checked (Darwin only) ----------------
    #
    # **This retires the repo's top red-CI category**, and it does so by
    # compiling rather than by approximating. Four red pushes were app-target
    # symbols the local gate could not see: an `internal`
    # `PeerStandingModel.isModelled` read from the app, a missing `.screenTime`
    # arm in `onsetDriverIcon`, and a missing `import InsightKit`. All three are
    # name-resolution failures, and `swiftc -parse` above resolves no names at
    # all — it builds a syntax tree and stops.
    #
    # The efficiency roadmap specified a *textual* cross-target symbol check
    # (collect InsightKit's declarations, grep the app for identifiers, flag any
    # that resolve to an `internal` one) because the hosted Linux container has
    # no iOS SDK and therefore no way to run the real thing. That reasoning was
    # correct for Linux and is simply obsolete on the user's Mac, which has
    # Xcode: the real compiler answers the real question, with no false
    # positives and no list to maintain. The textual check is not worth
    # building — see docs/efficiency-log.md.
    #
    # Cost is why this can sit in the gate at all: an incremental no-change
    # build is ~1.4s. The first run after a clean checkout is minutes, which is
    # the one time it is worth waiting for.
    #
    # `generic/platform=iOS` deliberately — the device SDK, matching what
    # deploy.yml ships, and **it needs no simulator**. The first Mac session
    # (2026-08-04) could not boot one at all, and a gate that depends on the
    # simulator would have been dead that whole session.
    #
    # Its own `iosfail`, for the reason `testfail` has one: a flag shared with
    # the lints above can be cleared by somebody else's recovery.
    if [ "$(uname -s)" = "Darwin" ]; then
        if command -v xcodebuild >/dev/null 2>&1 && [ -d "$APP.xcodeproj" ]; then
            note 'Type-checking the app target against the iOS SDK (Mac only).'
            ioslog="${TMPDIR:-/tmp}/healthinsights-ios-build.log"
            iosfail=0
            # **Derived data lives outside the repo, and on this Mac that is not
            # a tidiness preference.** The working copy is in iCloud Drive, which
            # syncs by folder and knows nothing about `.gitignore` — so a
            # `-derivedDataPath build/…` uploads a few hundred megabytes of
            # object files to the user's iCloud account and keeps
            # `fileproviderd` busy churning them. It was measured at 262 MB
            # after one afternoon. A cache directory is also the right home for
            # something reproducible from source.
            xcodebuild build \
                -project "$APP.xcodeproj" \
                -scheme "$APP" \
                -destination 'generic/platform=iOS' \
                -derivedDataPath "$DERIVED_ROOT/$DERIVED_SLOT" \
                CODE_SIGNING_ALLOWED=NO > "$ioslog" 2>&1 || iosfail=1
            # **Checked before the `error:` grep below, because it would be
            # caught by it.** Xcode reports a locked build database as
            # `error: unable to attach DB: error: accessing build database`
            # — two `error:` lines for something that is not a compile error
            # at all, which is how a concurrent build came to be reported as a
            # broken diff on 2026-08-06. The per-worktree slot above makes the
            # cross-worktree case impossible, but two runs in the *same*
            # checkout can still race: `pre-push-gate.sh` re-runs the whole
            # gate on `git push`, so a manual `verify.sh` still going when the
            # push fires collides with itself. Name it instead of letting the
            # reader debug their own code.
            if [ "$iosfail" -ne 0 ] && grep -q 'database is locked' "$ioslog"; then
                # ⚠️ `Another build holds` is a contract, not just prose:
                # `pre-push-gate.sh` greps for it to tell a collision from a
                # real failure. Reword the rest freely; keep those three words.
                note 'Another build holds this derived-data path — NOT a compile error, and not your diff.'
                printf '%s\n' "Path: $DERIVED_ROOT/$DERIVED_SLOT"
                printf '%s\n' 'Something else is building: another verify.sh, a push whose gate re-runs it, or Xcode itself.'
                printf '%s\n' 'Wait for it to finish and run this again. Nothing here has been checked, so this is not a pass.'
                fail=1
            elif [ "$iosfail" -ne 0 ]; then
                note 'The app target does not compile for iOS:'
                grep -E 'error:' "$ioslog" | head -12
                # A build can fail without printing `error:` (a missing scheme, a
                # broken project file). Say so rather than printing nothing and
                # letting the reader conclude the grep found the whole story —
                # the "guard reporting a failure whose own premise is false"
                # class, which this repo has hit seven times.
                grep -qE 'error:' "$ioslog" \
                    || printf '%s\n' "No 'error:' line — xcodebuild failed for another reason. Full log: $ioslog"
                fail=1
            else
                printf '\033[32m✓\033[0m %s\n' 'App target compiles for iOS.'
            fi
        else
            note 'Darwin but no xcodebuild or no project — skipping the app-target compile. CI is the gate for it.'
        fi
    fi

    # --- The app target's own tests (Darwin + a simulator only) -------------
    #
    # **Backlog D5.** The app target had zero tests until 2026-08-07 — 28,573
    # lines, ~39% of the shipped Swift, and the 39% holding every render site,
    # every card-visibility gate and every `AppModel` transition. InsightKit's
    # suite is large, green, runs on Linux, and cannot see any of it.
    #
    # ⚠️ **This is the only place these tests can ever run.** A unit-test bundle
    # hosted in an iOS app needs the iOS SDK to build and an iOS *simulator* to
    # run — which the hosted Linux sessions do not have, and which `ci.yml`'s
    # runner does not have either. So CI does not gate this target and never
    # will; the Mac gate is the gate. The scheme's BuildAction still lists only
    # the app, so `xcodebuild build` — what CI and `deploy.yml` run — does not
    # compile the test target at all, and a broken test file cannot stop a
    # deploy reaching the phone.
    #
    # Cost, measured on 2026-08-07 (M-series Mac, iPhone 16e simulator):
    #   * **~19 s** on a warm slot — ~11 s of it the tests themselves, the rest
    #     the simulator install/launch round trip. That is what this adds to
    #     `verify.sh --tests` in normal use.
    #   * ~81 s once per cold derived-data slot, i.e. the first gate run in a
    #     fresh worktree. Same shape, and the same tradeoff, as the device-SDK
    #     compile above.
    # That is the price of the class it retires — see `CardRenderSmokeTests`,
    # which found a live process-killing exclusivity trap on its first run.
    #
    # A slot of its own, and not `$DERIVED_SLOT`: this build targets the
    # *simulator* SDK while the compile above targets the device SDK, and
    # sharing one path makes each run invalidate the other's products, turning
    # two ~1.4 s incrementals into two cold builds.
    #
    # Its own `apptestfail`, for the reason `testfail` and `iosfail` have their
    # own: a flag shared with the lints above can be cleared by somebody else's
    # recovery, and that has already shipped a bad commit here once.
    if [ "$(uname -s)" = "Darwin" ] && command -v xcodebuild >/dev/null 2>&1 \
       && [ -d "$APP.xcodeproj" ]; then
        # The same pick as `simulator.sh`: the caller's choice, else the newest
        # available iPhone. Named rather than `booted`, because xcodebuild needs
        # a destination before anything is booted.
        sim="${SIM_DEVICE:-$(xcrun simctl list devices available 2>/dev/null \
            | grep -oE '^ +iPhone [^(]+' | sed 's/^ *//;s/ *$//' | tail -1)}"
        if [ -z "$sim" ]; then
            # **Say it, do not swallow it.** A gate that skips silently reads as
            # a gate that passed, and this repo has paid for that shape more
            # than once. Not a failure either — a Mac with no simulator runtime
            # installed is a real and recoverable state.
            note 'No iOS simulator available — the app-target tests did NOT run.'
            printf '%s\n' 'Nothing has checked HealthInsightsTests. Install a simulator runtime, or say so in the reply.'
        else
            note "Running the app-target tests on $sim (Mac only — CI cannot run these)."
            apptestlog="${TMPDIR:-/tmp}/healthinsights-app-tests.log"
            apptestdd="$DERIVED_ROOT/${DERIVED_SLOT/verify-ios/verify-apptests}"

            # --- D63: make the failure say what it is ----------------------
            #
            # This block used to grep for `error:` and, finding none, tell the
            # reader "the host may have crashed" — a maybe, in the one place a
            # session needs a yes or a no. Under ten-plus concurrent worktree
            # builds on 2026-08-07 it failed repeatedly and differently each
            # time, and its silence produced three wrong diagnoses, the last of
            # which nearly pushed past the gate on a contaminated comparison.
            #
            # ⚠️ **It was right to block every single time.** So nothing here
            # softens the gate: a real assertion still fails, first time, with
            # no retry. What changes is that the output now names which of two
            # different sentences this is —
            #   * *a test ran and disagreed with the code*  → your diff, stop;
            #   * *the host was killed before it ran*       → the machine —
            # and only the second kind is retried, once, out loud, with the
            # machine's load printed beside it as evidence.
            #
            # `app-test-report.sh` owns the classification and canaries itself
            # (`--self-test`). It also closes the inverse hole: a suite that
            # executed **zero tests** used to print a green tick.
            run_app_tests() {
                xcodebuild test \
                    -project "$APP.xcodeproj" \
                    -scheme "$APP" \
                    -destination "platform=iOS Simulator,name=$sim" \
                    -derivedDataPath "$apptestdd" \
                    CODE_SIGNING_ALLOWED=NO > "$apptestlog" 2>&1
            }

            apptestfail=0
            run_app_tests || apptestfail=1
            appreport=$(./scripts/app-test-report.sh verdict "$apptestlog" "$apptestfail")
            apptoken=$(printf '%s\n' "$appreport" | head -1 | awk '{print $1}')
            appretryable=$(printf '%s\n' "$appreport" | head -1 | awk '{print $2}')
            appfirst=$apptoken

            # **One retry, and only for what is not attributable to the diff.**
            # Announced before it happens, because a silent retry is how
            # flakiness stops being visible — and invisible flakiness is what
            # trained the session to argue for pushing through it.
            if [ "$appretryable" = 1 ]; then
                note "App-target tests: $apptoken — not attributable to your diff. Retrying once (D63)."
                printf '%s\n' "$appreport" | tail -n +2
                # Read **now**, not before the run started. An earlier version
                # sampled the load up front and printed a quiet machine beside
                # a host that had just been killed by a loaded one — a wrong
                # number is worse than no number, because it argues.
                ./scripts/app-test-report.sh load
                # Keep the first attempt's log. It is the only record of what
                # the machine did, and the retry would otherwise overwrite the
                # evidence that justified retrying.
                cp "$apptestlog" "${apptestlog%.log}-attempt1.log" 2>/dev/null
                printf '%s\n' "First attempt kept at: ${apptestlog%.log}-attempt1.log"
                sleep 5
                apptestfail=0
                run_app_tests || apptestfail=1
                appreport=$(./scripts/app-test-report.sh verdict "$apptestlog" "$apptestfail")
                apptoken=$(printf '%s\n' "$appreport" | head -1 | awk '{print $1}')
            fi

            if [ "$apptoken" = clean ]; then
                printf '\033[32m✓\033[0m %s\n' \
                    "$(printf '%s\n' "$appreport" | tail -n +2 | head -1)"
                # A pass that only happened on the second attempt is still a
                # pass, and must still be said aloud — the count of these is
                # the only measure of whether D63 is getting better or worse.
                if [ "$appfirst" != "$apptoken" ]; then
                    printf '%s\n' \
                        "  (passed on retry — the first attempt was '$appfirst'. The machine, not your diff.)"
                fi
            else
                note "The app-target tests did not pass — $apptoken:"
                printf '%s\n' "$appreport" | tail -n +2
                if [ "$apptoken" = locked ]; then
                    printf '%s\n' "Path: $apptestdd"
                fi
                ./scripts/app-test-report.sh load
                printf '%s\n' "Full output: $apptestlog"
                # ⚠️ Every token lands here, environmental ones included. An
                # unexplained machine is still an unchecked diff, and "probably
                # the load" is not a check. Say what it was; do not excuse it.
                fail=1
            fi
        fi
    fi
fi

# --- The app-test classifier must still classify (D63) ---------------------
#
# Sub-second, needs no toolchain, and runs on every platform — so it runs in the
# lint pass rather than behind `--tests`, where a Linux session would never see
# it break. What it protects is a set of grep patterns against `xcodebuild`
# output, i.e. exactly the kind of thing that rots quietly and is only noticed
# on the night it matters, which for D63 was a night that cost three wrong
# diagnoses. It also holds the wording contract with `pre-push-gate.sh`.
if [ -x ./scripts/app-test-report.sh ]; then
    if ! selftest=$(./scripts/app-test-report.sh --self-test 2>&1); then
        note 'The app-target failure classifier is broken — it can no longer tell a failed assertion from a killed host:'
        printf '%s\n' "$selftest" | grep -E 'FAIL|fixtures pass'
        fail=1
    fi
fi

# --- FoundationModels must be canImport-guarded ---
#
# CI's runner SDK does not carry FoundationModels, so a bare `import
# FoundationModels` is a red build the local gate cannot see. That is exactly
# what happened on 2026-08-06 and it is a category, not an instance: the whole
# point of that module is that it may be absent.
bare_fm=$(git ls-files '*.swift' | while read -r f; do
  # ⚠️ **The line BEFORE the import, not "does the file mention canImport".**
  # The first version of this check asked whether the file contained the string
  # anywhere — and this very file guards two call sites with it, so a bare
  # import at the top sailed through. A canary caught it; a lint nobody canaries
  # is a lint nobody has tested.
  awk -v file="$f" '
    /^import FoundationModels/ && prev !~ /^#if canImport\(FoundationModels\)/ { print file; exit }
    { prev = $0 }
  ' "$f"
done)
if [ -n "$bare_fm" ]; then
  echo "FoundationModels imported without a canImport guard on the line above — CI has no such module:"
  echo "$bare_fm"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
    printf '\n\033[32mClean.\033[0m\n'
else
    printf '\n\033[31mIssues above — read them before pushing.\033[0m\n'
    # **Say what the machine was doing, on every red (D63).**
    #
    # Not only the app-target block: the first red this fix produced was an
    # *InsightKit* test — `LaunchParticleFieldTests` asserting that cloud
    # generation scales linearly, measured in wall-clock, failing at 2.29x
    # against a 2.0x limit with ten sibling worktrees compiling. It passed in
    # isolation on the same commit two minutes later. So the load belongs on
    # the summary line, where every red sees it, and not only beside the one
    # suite this row started from.
    #
    # ⚠️ **This is context, not an excuse, and the wording has to keep it that
    # way.** "The machine was busy" is precisely the sentence that talked a
    # session into pushing past a real failure on 2026-08-07. The gate has
    # already failed; a loaded machine changes *what to do next* (re-run the
    # named test in isolation) and never *whether this is a pass*.
    if [ -x ./scripts/app-test-report.sh ]; then
        ./scripts/app-test-report.sh load
        printf '%s\n' 'A busy machine is a reason to re-run a timing assertion in isolation before believing it.'
        printf '%s\n' 'It is never a reason to push: this gate has verified nothing either way.'
    fi
fi
exit "$fail"
