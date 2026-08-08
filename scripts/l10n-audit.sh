#!/usr/bin/env bash
#
# How far off is this app from speaking anything but English?
#
# Written 2026-08-07 for backlog D7, and the reason it is a script rather than a
# paragraph is that the paragraph would go stale in one session. "About 500
# strings" is the kind of figure that gets copied forward for months after it
# stopped being true; a number you can re-derive in two seconds does not.
#
# It counts three populations, because they need three different kinds of work
# and lumping them together is what makes the job look impossible:
#
#   1. App-target SwiftUI literals — `Text("…")`, `Button("…")`, and friends.
#      These are the cheap ones. SwiftUI's `Text(_: LocalizedStringKey)` already
#      goes through the main bundle, `SWIFT_EMIT_LOC_STRINGS` is already YES in
#      project.yml, and `HealthInsights/Resources/Localizable.xcstrings` now
#      exists to receive them — so Xcode extracts this whole population on the
#      next build with **no source change at all**. What remains for them is a
#      translator, not an engineer.
#
#   2. App-target string interpolation inside those literals. Extraction still
#      works, but the placeholder order is frozen by the interpolation, so a
#      language that wants a different word order cannot have one. These need
#      rewriting as format strings with positional arguments before they are
#      genuinely translatable.
#
#   3. InsightKit prose. The hard population, and the one that makes a "just
#      localise it" estimate wrong by an order of magnitude. The package has no
#      `defaultLocalization`, so nothing in it can resolve a localised string at
#      all; the sentences are *assembled* from clauses at runtime rather than
#      written whole; and many carry a metric unit inside the sentence, which
#      ties this job to the units one. See MeasurementSystem.swift.
#
# Usage:  ./scripts/l10n-audit.sh          — the counts
#         ./scripts/l10n-audit.sh --files  — the counts, plus the worst files

set -euo pipefail
root=$(git rev-parse --show-toplevel)
cd "$root"

app=HealthInsights
kit=InsightKit/Sources

# SwiftUI initialisers whose first argument is a LocalizedStringKey. Anything on
# this list is extracted automatically once a String Catalog is present.
localisable='(Text|Button|Label|Toggle|Picker|Stepper|Section|TextField|SecureField|Link|NavigationLink|navigationTitle|confirmationDialog|alert|help|accessibilityLabel|accessibilityHint)'

count() { grep -rhoE "$1" --include='*.swift' "$2" 2>/dev/null | wc -l | tr -d ' '; }

auto=$(count "$localisable\\(\"[^\"]+\"" "$app")
interpolated=$(count "$localisable\\(\"[^\"]*\\\\\\(" "$app")
# Prose in InsightKit: a quoted run of 20+ characters containing a space. Short
# literals are overwhelmingly dictionary keys, identifiers and unit labels, and
# counting those would inflate the figure into meaninglessness.
kit_prose=$(grep -rhoE '"[^"]{20,}"' --include='*.swift' "$kit" 2>/dev/null | grep -c ' ' || true)

# Population 4 (added 2026-08-08, with the catalog): app-target prose the
# catalog CANNOT see. A literal reaches the catalog only through a
# `LocalizedStringKey`/`LocalizedStringResource` position or `String(localized:)`;
# a ternary inside `Text(...)`, a `switch` that returns copy, or a plain-String
# parameter renders verbatim forever. Same 20-chars-with-a-space methodology as
# the InsightKit count, minus lines the extractor or `String(localized:)`
# already covers — an estimate for sizing the sweep, not a lint.
# Comment lines are dropped first: this repo's house style quotes prose in
# doc comments constantly, and counting those as UI copy would roughly double
# the figure. (The InsightKit count above keeps its original methodology so
# its history stays comparable.)
app_dark=$(grep -rhE '"[^"]{20,}"' --include='*.swift' "$app" 2>/dev/null \
    | grep -vE '^[[:space:]]*//' \
    | grep -vE "$localisable\\(\"" \
    | grep -vE 'String\(localized:' \
    | grep -oE '"[^"]{20,}"' | grep -c ' ' || true)

printf '%s\n' "Localisation audit — $(date +%Y-%m-%d)"
printf '%s\n' "------------------------------------------------------------"
printf '  %-52s %6s\n' "App-target literals Xcode can extract for free" "$auto"
printf '  %-52s %6s\n' "  …of which interpolate, so freeze word order" "$interpolated"
printf '  %-52s %6s\n' "App-target prose the catalog can't see (plain String)" "$app_dark"
printf '  %-52s %6s\n' "InsightKit prose strings (no bundle, no catalog)" "$kit_prose"
printf '  %-52s %6s\n' "TOTAL" "$((auto + app_dark + kit_prose))"
printf '%s\n' "------------------------------------------------------------"

if [ -f "$app/Resources/Localizable.xcstrings" ]; then
    # Read as JSON, not grepped: a grep for language codes counted the *source*
    # language's own entries as "languages beyond source" the first time the
    # catalog was populated (2026-08-08), and an earlier grep exited 1 on the
    # empty catalog and killed the whole report under `set -o pipefail`. An
    # audit that lies about — or dies on — the state it exists to report is the
    # worst kind of gate.
    python3 - "$app/Resources/Localizable.xcstrings" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
src = c.get('sourceLanguage')
strings = c.get('strings', {})
langs = {l for e in strings.values() for l in e.get('localizations', {}) if l != src}
print(f"String Catalog: present, holding {len(strings)} keys "
      f"(./scripts/l10n-extract.sh refreshes it). "
      f"Languages beyond source: {len(langs)}")
PY
else
    printf '%s\n' "String Catalog: ABSENT — population 1 is not being extracted."
fi

if grep -q 'defaultLocalization' InsightKit/Package.swift; then
    printf '%s\n' "InsightKit: declares a defaultLocalization."
else
    printf '%s\n' "InsightKit: no defaultLocalization — its prose cannot be localised at all yet."
fi

if [ "${1:-}" = "--files" ]; then
    printf '\n%s\n' "Heaviest app-target files:"
    grep -rcE "$localisable\\(\"[^\"]+\"" --include='*.swift' "$app" 2>/dev/null \
        | awk -F: '$2 > 0' | sort -t: -k2 -rn | head -12 | sed 's/^/  /'
    printf '\n%s\n' "Heaviest InsightKit files:"
    grep -rcE '"[^"]{20,}"' --include='*.swift' "$kit" 2>/dev/null \
        | awk -F: '$2 > 0' | sort -t: -k2 -rn | head -12 | sed 's/^/  /'
fi
