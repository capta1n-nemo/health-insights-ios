#!/usr/bin/env bash
#
# The cheap gate. Runs in under a second, needs no toolchain, and checks the
# rules this repo has actually been broken by — each one traceable to a CI
# failure or a shipped bug, not to taste.
#
#   ./scripts/verify.sh              # lint only (works anywhere)
#   ./scripts/verify.sh --tests      # lint + swift test, if a toolchain exists
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

# An InsightID's icon switch carries a `default:`, so a new card compiles fine
# and silently wears somebody else's glyph. The compiler catches the other four
# switches; this is the one that needs a lint. (`cadence` also defaults, but its
# default *is* the rule — everything not daily is a trend — so it isn't checked.)
insight_names=$(awk '/^public enum InsightID/,/^}/' \
    InsightKit/Sources/InsightKit/Insights/Insight.swift 2>/dev/null \
    | grep -oE '^\s+case [a-z][A-Za-z0-9]*' | awk '{print $2}' | sort -u)

if [ -n "$insight_names" ]; then
    icon_body=$(awk '/(var|func) iconName/,/^    }$/' \
        HealthInsights/Features/Dashboard/DashboardView.swift 2>/dev/null)
    icon_missing=""
    for name in $insight_names; do
        printf '%s' "$icon_body" | grep -qE "[.]$name\b" || icon_missing="$icon_missing $name"
    done
    if [ -n "$icon_missing" ]; then
        note "iconName (DashboardView.swift) does not mention:$icon_missing"
        fail=1
    fi
fi

# chartStyleIndex must stay contiguous from zero, or the metrics most likely to
# share a chart lose first claim on the eight hues.
dupes=$(grep -oE 'return [0-9]+$' InsightKit/Sources/InsightKit/Presentation/MetricPresentation.swift 2>/dev/null \
        | sort | uniq -d | head -3)
if [ -n "$dupes" ]; then
    note 'chartStyleIndex may have duplicate indices (must be contiguous from 0):'
    printf '%s\n' "$dupes"
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
        note "Running InsightKit tests with $(swift --version | head -1)"
        (cd InsightKit && swift test --parallel) || fail=1
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
