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

if [ -n "$matches" ]; then
    echo "$matches"
    exit 0
fi

# Not a top-level type. Fall back to member declarations rather than sending the
# reader away to grep.
#
# This half was added in session 12, which lost a round trip guessing that
# `bucketed` lived in `MultiSource.swift` (it is in `MetricAggregator.swift`).
# The old miss-message said "grep is right for those" — and a reader who falls
# back to grep has to name a file, which is the exact failure the type lookup
# was built to retire, reappearing one level down. One reflex has to answer
# "where does X live" for *any* X, or it is not a reflex.
#
# `git grep` rather than the filesystem: a declaration in an untracked file is
# not yet part of the codebase, and `verify.sh` makes the same choice.
members=$(git grep -nE \
    "(func|var|let|case|init|subscript|typealias|associatedtype)[[:space:]]+\`?$1\`?([^A-Za-z0-9_]|$)" \
    -- '*.swift' 2>/dev/null | head -40)

if [ -n "$members" ]; then
    echo "No top-level type matching '$1' — these are member declarations:" >&2
    echo "$members"
    exit 0
fi

echo "Nothing matching '$1' in $INDEX, and no member declaration either." >&2
echo "If you have just added it, run ./scripts/gen-symbol-index.sh." >&2
echo "If it is only ever a call site, git grep is right: git grep -n '$1' -- '*.swift'" >&2
exit 1
