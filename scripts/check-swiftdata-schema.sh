#!/usr/bin/env bash
#
# **A new mandatory column on a shipped @Model kills the app on launch.**
#
# This repo has no `SchemaMigrationPlan`. It relies entirely on SwiftData's
# implicit lightweight migration, which cannot invent a value for a new
# non-optional, non-defaulted property — so the store fails to migrate,
# `DataStore.init` turns that into a `fatalError`, and every existing install
# dies at launch. That shipped on 2026-08-09 (`189a5e1`,
# `LabResultRecord.shapeRaw`) and the reader hit it within minutes.
#
# ⚠️ **No test and no simulator run can catch this.** A fresh install has no
# store to migrate, so the broken build and the fixed build both launch happily —
# which is exactly what happened while diagnosing it. Only a device with history
# fails. So the guard has to be a lint, and this is it.
#
# The rule: a stored property on a `@Model` is optional, or it has a default.
# The snapshot beside this script lists the ones that shipped together and are
# therefore already in every store.

set -euo pipefail
cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"

snapshot="scripts/swiftdata-mandatory-attributes.txt"
[ -f "$snapshot" ] || { printf '\033[31m✗\033[0m %s is missing\n' "$snapshot"; exit 1; }

current=$(python3 - <<'PY'
import re, glob
out = []
for path in sorted(glob.glob("HealthInsights/Core/Persistence/*.swift")):
    src = open(path).read()
    for m in re.finditer(r'@Model\s*\n\s*final class (\w+)', src):
        name = m.group(1)
        i = src.index("{", m.end()); depth = 0; j = i
        while j < len(src):
            if src[j] == "{": depth += 1
            elif src[j] == "}":
                depth -= 1
                if depth == 0: break
            j += 1
        for v in re.finditer(
                r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*var\s+(\w+)\s*:\s*([^\n=]+?)(\s*=\s*.+)?$',
                src[i:j], re.M):
            prop, typ, default = v.group(1), v.group(2).strip(), v.group(3)
            if "{" in typ:            # computed, not stored
                continue
            if typ.endswith("?"):     # optional — migration fills it with nil
                continue
            if default is not None:   # defaulted — migration fills it with that
                continue
            out.append(f"{name}.{prop}")
print("\n".join(sorted(out)))
PY
)

expected=$(grep -v '^#' "$snapshot" | grep -v '^[[:space:]]*$' | sort)
added=$(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$current" | sort) || true)

if [ -n "$added" ]; then
    printf '\033[31m✗\033[0m New mandatory attribute(s) on a shipped @Model:\n'
    printf '    %s\n' $added
    cat <<'EOF'

    SwiftData cannot fill these for stores that already exist, so the app will
    fatalError on launch for every current install — and neither the test suite
    nor a fresh simulator install can see it.

    Make the property optional, or give it a default:

        var shapeRaw: String = LabValueShape.quantitative.rawValue

    If the property genuinely shipped in the same release as its model, add it
    to scripts/swiftdata-mandatory-attributes.txt with a line saying why.
EOF
    exit 1
fi

removed=$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$current" | sort) || true)
if [ -n "$removed" ]; then
    printf '\033[33m!\033[0m Mandatory attribute(s) removed or made optional — update the snapshot:\n'
    printf '    %s\n' $removed
    exit 1
fi

printf '\033[32m✓\033[0m No new mandatory @Model attributes (%s tracked)\n' "$(printf '%s\n' "$expected" | wc -l | tr -d ' ')"
