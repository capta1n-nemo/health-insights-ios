#!/usr/bin/env bash
# Where does a type live? Answers from docs/symbol-index.md.
#
# This exists because "check the index before grepping" has been written in the
# memory router, in CLAUDE.md and in the session-start skill, and has now been
# skipped in three consecutive sessions — each time by guessing a directory name
# and grepping a path that does not exist. Prose telling the reader to consult a
# file loses to a habit; a command that is shorter than the grep does not.
#
#   ./scripts/where.sh PromotionRule
#   ./scripts/where.sh sleeponset          # case-insensitive, substring
#
# Prints `path:line  Type` for every match, resolved to a real path from the
# repository root so the result can be opened directly.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 2
INDEX="docs/symbol-index.md"

if [ $# -eq 0 ]; then
    echo "usage: ./scripts/where.sh <type-name-or-fragment>" >&2
    exit 2
fi

if [ ! -f "$INDEX" ]; then
    echo "$INDEX is missing — run ./scripts/gen-symbol-index.sh" >&2
    exit 2
fi

# The index is a nested list: `## <root>`, then `- \`<file>\``, then
# `  - \`<Type>\` :<line>`. A match has to carry its two enclosing headings
# down with it, which is what the two state variables are for.
matches=$(awk -v needle="$1" '
    BEGIN { IGNORECASE = 1; lc_needle = tolower(needle) }
    /^## / { root = substr($0, 4); next }
    /^- `/ { file = $0; gsub(/^- `|`$/, "", file); next }
    /^  - `/ {
        line = $0
        sub(/^  - `/, "", line)
        type = line; sub(/`.*$/, "", type)
        lineno = line; sub(/^[^:]*:/, "", lineno)
        if (index(tolower(type), lc_needle) > 0)
            printf "%s/%s:%s  %s\n", root, file, lineno, type
    }
' "$INDEX")

if [ -z "$matches" ]; then
    echo "No type matching '$1' in $INDEX." >&2
    echo "If you have just added it, run ./scripts/gen-symbol-index.sh." >&2
    echo "If it is not a top-level type (a method, a case, a property), the" >&2
    echo "index does not carry it — grep is right for those." >&2
    exit 1
fi

echo "$matches"
