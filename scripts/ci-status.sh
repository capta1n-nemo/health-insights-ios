#!/usr/bin/env bash
#
# "Did CI pass for this commit?" — in a few hundred bytes.
#
# The GitHub Actions API is the only other route from an agent sandbox, and its
# smallest run listing is ~450 KB (>100K tokens). Checking CI six times in a
# session cost more than the entire code review it was verifying. `ci.yml`'s
# record-status job pushes the verdict to refs/ci/{passed,failed}/<sha>, and
# `git ls-remote` reads it for almost nothing.
#
#   ./scripts/ci-status.sh              # HEAD
#   ./scripts/ci-status.sh <sha>
#   ./scripts/ci-status.sh --wait       # poll HEAD until a verdict appears
#   ./scripts/ci-status.sh --errors     # print WHY it failed
#
# `--errors` matters as much as the verdict. `ci.yml` already writes the first
# 60 grepped error lines to refs/ci/errors/<sha> — one blob, usually under a
# kilobyte — and on 2026-08-02 a session went to the Actions API to read a
# single compile error instead. That call returned 446 KB and the answer was
# `git fetch` away. **Never open the Actions API for a build error.**
#
# Exit 0 = passed, 1 = failed, 2 = no verdict yet (still running, or the commit
# predates this mechanism).

set -uo pipefail
cd "$(dirname "$0")/.."

wait=0
errors=0
sha=""
for arg in "$@"; do
    case "$arg" in
        --wait) wait=1 ;;
        --errors) errors=1 ;;
        *) sha="$arg" ;;
    esac
done
[ -z "$sha" ] && sha=$(git rev-parse HEAD)

look() {
    # One network round trip, filtered server-side to the two refs that matter.
    git ls-remote origin "refs/ci/passed/$sha" "refs/ci/failed/$sha" 2>/dev/null
}

report() {
    case "$1" in
        *"refs/ci/passed/"*) echo "passed  ${sha:0:7}"; return 0 ;;
        *"refs/ci/failed/"*) echo "FAILED  ${sha:0:7}"; return 1 ;;
    esac
    return 2
}

if [ "$wait" -eq 1 ]; then
    # CI takes ~90 s; poll on that scale rather than hammering.
    for _ in $(seq 1 40); do
        out=$(look)
        if [ -n "$out" ]; then report "$out"; exit $?; fi
        sleep 15
    done
    echo "no verdict for ${sha:0:7} after 10 minutes"
    exit 2
fi

if [ "$errors" -eq 1 ]; then
    if git fetch -q origin "refs/ci/errors/$sha" 2>/dev/null; then
        git show FETCH_HEAD:errors.txt
        exit 1
    fi
    echo "no error blob for ${sha:0:7} (it passed, is still running, or predates refs/ci/errors)"
    exit 2
fi

out=$(look)
if [ -z "$out" ]; then
    echo "no verdict yet for ${sha:0:7} (still running, or pushed before refs/ci existed)"
    exit 2
fi
report "$out"
exit $?
