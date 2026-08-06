#!/usr/bin/env bash
# What the reader has asked for and has NOT got.
#
# ⚠️ **This exists because of a three-session repeat.** Sessions 25, 27 and 28
# each ended with the reader asking where their requested work was, and each time
# the cause was the same: the session did good work on what it found interesting
# and left the named asks unstarted. `docs/backlog.md` §B2/§B5 already held the
# list; nobody read it at the start.
#
# So it is a command now, and `session-start` runs it. A rule that has failed
# three times is not made to hold by writing it more firmly.
set -euo pipefail
cd "$(dirname "$0")/.."

# Fail LOUDLY if the backlog headings this parses ever move. Without this, a
# renamed "### B2 —" makes the script print an empty list — a false "nothing
# outstanding", which is the exact three-session failure it exists to stop.
if ! grep -q '^### B2 —' docs/backlog.md || ! grep -q '^### B5 —' docs/backlog.md; then
    echo "ERROR: docs/backlog.md no longer has '### B2 —' / '### B5 —' headings." >&2
    echo "This script parses them; fix the headings or this script before trusting its output." >&2
    exit 1
fi

echo "Things the reader asked for that are NOT built:"
echo
# §B5 rows without a ✅, and §B2 rows without one. The marker convention is the
# backlog's own: ✅ shipped, ◐ partly, bare number open.
awk '
  # ⚠️ Any ### heading closes the previous section. The first version only reset
  # on "## C." and silently swallowed §B3 and §B4 — research proposals and
  # already-shipped sections — reporting them as things the reader was still
  # waiting for. A canary of one run caught it.
  /^### / { section = "" }
  /^### B2 —/ { section = "asked for" }
  /^### B5 —/ { section = "you reversed a refusal" }
  section != "" && /^\| *[0-9]+ *\|/ {
    if ($0 ~ /✅/) next            # shipped
    if ($0 ~ /UPHELD/) next        # the reader agreed not to build it
    print "  [" section "] " $0
  }
' docs/backlog.md | cut -c1-160

echo
echo "Full detail: docs/backlog.md §B2 (asked for) and §B5 (refusals you reversed)."
