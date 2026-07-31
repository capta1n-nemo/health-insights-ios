#!/usr/bin/env bash
#
# "Why did CI fail?" — in a few hundred bytes.
#
# `ci-status.sh` answers *whether* the app target compiled. This answers *what
# broke*, which until now had exactly one source: the GitHub Actions API. Its
# smallest run listing is ~450 KB, and because xcodebuild prints every compile
# step, a tail long enough to reach the error is tens of thousands of tokens of
# noise either way. On 2026-07-31 three fetches totalling ~40 K tokens returned
# the "BUILD FAILED" summary and never the error line, and the bug was found by
# re-reading the diff instead.
#
# `ci.yml`'s app-build job now greps its own log and pushes the result to
# refs/ci/errors/<sha> as a real file. This fetches it.
#
#   ./scripts/ci-errors.sh              # HEAD
#   ./scripts/ci-errors.sh <sha>
#
# Exit 0 = errors printed, 2 = no record (CI passed, still running, or the
# commit predates this mechanism).

set -uo pipefail
cd "$(dirname "$0")/.."

sha="${1:-$(git rev-parse HEAD)}"

if ! git fetch -q --no-tags origin "refs/ci/errors/$sha" 2>/dev/null; then
    echo "no error record for ${sha:0:7} — CI may have passed, or is still running"
    echo "check with: ./scripts/ci-status.sh $sha"
    exit 2
fi

if ! git show FETCH_HEAD:errors.txt 2>/dev/null; then
    echo "ref exists for ${sha:0:7} but carries no errors.txt"
    exit 2
fi
