#!/usr/bin/env bash
#
# "Is it actually on the phone?" — the question `ci-status.sh` cannot answer.
#
# The two are easy to confuse and the confusion is expensive. `ci.yml` runs on
# GitHub's own runners and proves the code *compiles*. `deploy.yml` runs on the
# user's self-hosted Mac and is the only thing that puts the app on the iPhone.
# On 2026-07-31 three consecutive deploys failed on an unreachable phone while
# `ci-status.sh` reported green for all three, and each was announced as
# "deployment triggered". A push is not an install.
#
#   ./scripts/deploy-status.sh              # HEAD
#   ./scripts/deploy-status.sh <sha>
#   ./scripts/deploy-status.sh --wait       # poll until a verdict appears
#
# Exit 0 = installed, 1 = failed, 2 = no verdict yet.
#
# Never reach for the GitHub Actions API instead: its smallest deploy-run
# listing is ~457 KB, which is over 100K tokens for one question.

set -uo pipefail
cd "$(dirname "$0")/.."

wait=0
sha=""
for arg in "$@"; do
    case "$arg" in
        --wait) wait=1 ;;
        *) sha="$arg" ;;
    esac
done
[ -z "$sha" ] && sha=$(git rev-parse HEAD)

look() {
    git ls-remote origin "refs/deploy/passed/$sha" "refs/deploy/failed/$sha" 2>/dev/null
}

report() {
    case "$1" in
        *"refs/deploy/passed/"*)
            echo "installed  ${sha:0:7}"; return 0 ;;
        *"refs/deploy/failed/"*)
            echo "DEPLOY FAILED  ${sha:0:7}"
            echo "The build is fine — this is the install step. Usually the phone:"
            echo "  · unlock it, and keep it unlocked for the install"
            echo "  · same Wi-Fi as the Mac, no VPN"
            echo "  · Xcode ▸ Window ▸ Devices and Simulators shows it, 'Connect via network' ticked"
            echo "Re-run without a new commit: gh workflow run deploy.yml  (or the Actions tab)"
            return 1 ;;
    esac
    return 2
}

if [ "$wait" -eq 1 ]; then
    # A device build plus install is slower than CI — allow ~15 minutes.
    for _ in $(seq 1 45); do
        out=$(look)
        if [ -n "$out" ]; then report "$out"; exit $?; fi
        sleep 20
    done
    echo "no deploy verdict for ${sha:0:7} after 15 minutes"
    echo "If the self-hosted Mac runner is offline the job queues and never starts."
    exit 2
fi

out=$(look)
if [ -z "$out" ]; then
    echo "no deploy verdict yet for ${sha:0:7} (still running, or pushed before refs/deploy existed)"
    exit 2
fi
report "$out"
exit $?
