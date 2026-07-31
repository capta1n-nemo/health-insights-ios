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
cd "$(dirname "$0")/.."

fail=0
note() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# Flag any match of $1 in the given paths. $2 is the explanation.
ban() {
    local pattern=$1 message=$2
    shift 2
    local out
    if out=$(grep -rn --include='*.swift' -E "$pattern" "$@" 2>/dev/null); then
        note "$message"
        printf '%s\n' "$out"
        fail=1
    fi
}

APP=HealthInsights
KIT=InsightKit/Sources
KIT_TESTS=InsightKit/Tests

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
    printf '%s' "$body" | grep -qE '^\s+default:' && return
    for name in $metric_names; do
        printf '%s' "$body" | grep -qE "[.]$name\b" || missing="$missing $name"
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
# longer has one — four of the five InsightID switches are exhaustive now — and
# a hand-picked check on one of them is exactly the shape that let a
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
# `.claude/settings.json` is in the list because a hook pointing at a deleted
# script fails *silently* — the harness runs nothing and the push it was meant to
# gate sails through, which is strictly worse than a rule nobody read.
for f in CLAUDE.md .claude/commands/*.md .claude/skills/*/SKILL.md .claude/settings.json; do
    [ -f "$f" ] || continue
    for ref in $(grep -oE '[.]/scripts/[A-Za-z0-9_-]+[.]sh' "$f" 2>/dev/null | sort -u); do
        [ -x "${ref#./}" ] || missing_scripts="$missing_scripts $ref (in $f)"
    done
done
if [ -n "$missing_scripts" ]; then
    note "Rules reference scripts that are missing or not executable:$missing_scripts"
    fail=1
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
if [ -f docs/progress.md ]; then
    partial=$(grep -nE '^- \[~\]' docs/progress.md || true)
    if [ -n "$partial" ]; then
        note 'docs/progress.md has half-done `- [~]` items. Split each into a done `[x]` and an open `[ ]` — a multi-clause item hides its unfinished clauses:'
        printf '%s\n' "$partial"
        fail=1
    fi
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
        if [ -n "${2:-}" ]; then
            note "Running InsightKit tests matching '$2' — NOT the gate. Run without a filter before pushing."
            (cd InsightKit && swift test --parallel --filter "$2") || fail=1
        else
            note "Running InsightKit tests with $(swift --version | head -1)"
            (cd InsightKit && swift test --parallel) || fail=1
        fi
    else
        note 'Could not obtain a Swift toolchain (no network?). CI is the gate — say so in the reply.'
    fi
fi

if [ "$fail" -eq 0 ]; then
    printf '\n\033[32mClean.\033[0m\n'
else
    printf '\n\033[31mIssues above — read them before pushing.\033[0m\n'
fi
exit "$fail"
