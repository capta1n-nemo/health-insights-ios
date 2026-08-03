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

# --- Every chart carries the substance shading -----------------------------
#
# The user's rule, 2026-08-03: *"make sure the stimulant impact shading is on
# EVERY chart in the app, and this is a design rule going forward."*
#
# "Going forward" is the part a lint has to carry: the shading was on one chart
# for months because each new chart's author had no reason to know about it.
# `ScrollableMetricChart` now draws it for every chart that wraps it, so the
# only files this can catch are the ones building a raw `Chart {` of their own
# — which is exactly where the rule gets skipped.
#
# A file passes if it wraps `ScrollableMetricChart`, calls `SubstanceShading`
# itself, or carries the exemption marker with a reason:
#     // substance-shading: exempt — <why>
# An exemption is for a chart whose x axis is not a date (a projection in months
# ahead, a scatter). There is no exemption for "it did not seem relevant".
chartfiles=$(grep -rlE '(^|[^A-Za-z0-9_])Chart[ ]*\{' HealthInsights --include=*.swift 2>/dev/null || true)
unshaded=""
for f in $chartfiles; do
    case "$(basename "$f")" in
        ScrollableMetricChart.swift|SubstanceShading.swift) continue ;;
    esac
    # Comment lines don't build charts. `DomainDataScaffold` documents the rule
    # that a data page never hand-rolls a `Chart {}`, and was flagged for saying
    # so — a lint that fires on prose about itself teaches people to ignore it.
    grep -nE '(^|[^A-Za-z0-9_])Chart[ ]*\{' "$f" \
        | grep -qvE '^[0-9]+:[[:space:]]*(///|//|\*)' || continue
    grep -q 'ScrollableMetricChart\|SubstanceShading\|substance-shading: exempt' "$f" \
        || unshaded="$unshaded $(basename "$f")"
done
if [ -n "$unshaded" ]; then
    note "Charts with no substance shading — wrap ScrollableMetricChart, call SubstanceShading, or mark '// substance-shading: exempt — <why>':$unshaded"
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
pii_hits=$(grep -rInE \
    '\b[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\b|\b[0-9]{8}-[0-9A-F]{16}\b' \
    --include='*.swift' --include='*.yml' --include='*.yaml' --include='*.sh' \
    --include='*.plist' --include='*.pbxproj' --include='*.json' \
    . 2>/dev/null \
    | grep -viE 'UUID\(\)|uuidString|test|mock|fixture|00000000-0000|E621E1F8|deadbeef' \
    | grep -v '^./.github/workflows/deploy.yml:' \
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
fi

if [ "$fail" -eq 0 ]; then
    printf '\n\033[32mClean.\033[0m\n'
else
    printf '\n\033[31mIssues above — read them before pushing.\033[0m\n'
fi
exit "$fail"
