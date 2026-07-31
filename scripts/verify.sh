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
        # Keep the output. A red run whose log has scrolled away is a red run
        # nobody can diagnose. `tee` would mask the exit status, so read it back
        # out of PIPESTATUS.
        testlog="${TMPDIR:-/tmp}/insightkit-tests.log"
        if [ -n "${2:-}" ]; then
            note "Running InsightKit tests matching '$2' — NOT the gate. Run without a filter before pushing."
            (cd InsightKit && swift test --parallel --filter "$2" 2>&1 | tee "$testlog"; exit "${PIPESTATUS[0]}") || fail=1
        else
            note "Running InsightKit tests with $(swift --version | head -1)"
            (cd InsightKit && swift test --parallel 2>&1 | tee "$testlog"; exit "${PIPESTATUS[0]}") || fail=1
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
        if [ "$fail" -ne 0 ] && [ -z "${2:-}" ] \
           && ! grep -qE "error:|XCTAssert.*failed|Fatal error|Test Suite .* failed" "$testlog"; then
            note 'Non-zero exit but no failing test in the log — re-running serially to tell a runner artifact from a real failure.'
            if (cd InsightKit && swift test 2>&1 | tee "$testlog.serial"; exit "${PIPESTATUS[0]}"); then
                printf '\033[33m!\033[0m %s\n' 'Parallel runner exited non-zero; the serial run passed in full. Treating as a runner artifact.'
                fail=0
            else
                printf '\033[31m✗\033[0m %s\n' "Serial run failed too — this is real. See $testlog.serial"
            fi
        fi
        [ "$fail" -eq 0 ] || note "Full test output kept at $testlog"
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
