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
#   ./scripts/deploy-status.sh --errors     # print WHY it failed
#   ./scripts/deploy-status.sh --fresh      # ignore the verdict already there
#
# `--fresh` is for a **re-run of a commit that already has a verdict**, which is
# what happens every time a deploy is retried without a new push. The ref is
# keyed on the sha alone, so `--wait` found the *previous* run's `failed` ref
# and returned instantly — reporting a failure that had not happened yet. It
# baselines whatever is there now and waits for it to change.
#
# `--errors` exists because the verdict was a single bit, so "the phone was
# locked" and "signing rejected a capability" looked identical from here. That
# stopped being tolerable the day a second target with an App Group entitlement
# landed. `deploy.yml` now writes the grepped signing/install lines to
# refs/deploy/errors/<sha>, which is a few hundred bytes.
#
# Exit 0 = installed, 1 = failed, 2 = no verdict yet.
#
# Never reach for the GitHub Actions API instead: its smallest deploy-run
# listing is ~457 KB, which is over 100K tokens for one question.

set -uo pipefail
cd "$(dirname "$0")/.."

wait=0
errors=0
fresh=0
sha=""
for arg in "$@"; do
    case "$arg" in
        --wait) wait=1 ;;
        --errors) errors=1 ;;
        --fresh) fresh=1; wait=1 ;;
        *) sha="$arg" ;;
    esac
done
[ -z "$sha" ] && sha=$(git rev-parse HEAD)

look() {
    git ls-remote origin "refs/deploy/passed/$sha" "refs/deploy/failed/$sha" 2>/dev/null
}

# "No verdict" is three different situations and they need different actions.
#
# Written on 2026-08-01, when a deploy produced no ref and this script said the
# runner was offline. It wasn't: the Mac had picked the job up, got through
# checkout, signing and stamping, and **dropped off ten minutes into the Xcode
# build**. GitHub concluded the job `failure`, and because the runner was gone
# the `if: always()` verdict step never executed — so `always()` does not, in
# fact, always run. A runner that dies mid-step writes neither passed nor
# failed, and this script cannot tell that apart from "still building".
#
# The recipe below is the cheap way to tell them apart. The Actions run listing
# is ~450 KB, which is over 100K tokens read directly — but the MCP tool spills
# it to a file, so `python3` over that file costs a few hundred bytes. Do that
# rather than reading the listing.
no_verdict_help() {
    cat <<'HELP'

"No verdict" means one of three things, and they need different fixes:

  1. still building — a device build plus install can outlast this wait
  2. never started  — no runner claimed the job (the Mac is off or asleep)
  3. died mid-build — a runner picked it up and stopped heartbeating, so the
                      `if: always()` step that writes the verdict never ran

To tell them apart, list the deploy runs and read the job's steps:

  mcp__github__actions_list  method=list_workflow_runs  resource_id=deploy.yml
  mcp__github__actions_list  method=list_workflow_jobs  resource_id=<run id>

That first call spills ~450 KB to a file rather than returning it — parse the
file, never the response:

  python3 -c "
  import json; raw=open(PATH).read(); d=json.loads(raw[raw.find('{'):])
  for r in d['workflow_runs'][:5]:
      print(r['head_sha'][:7], r['status'], r['created_at'], r['id'])"

Read it as:
  · status queued + runner_name "" ....... nobody claimed it → case 2
  · a step stuck in_progress while the job
    concluded failure, later steps pending .. runner died → case 3

Case 2 and case 3 both end the same way: **the queued run deploys as soon as
the Mac comes back**, and it will carry the newest commit, not the one that
failed. Nothing needs re-pushing.
HELP
}

report() {
    case "$1" in
        *"refs/deploy/passed/"*)
            echo "installed  ${sha:0:7}"; return 0 ;;
        *"refs/deploy/failed/"*)
            echo "DEPLOY FAILED  ${sha:0:7}"
            # This used to assert "the build is fine — this is the install
            # step", which was a guess dressed as a finding. A deploy can fail
            # at signing too, and since 2026-08-02 the app has an entitlement
            # that can be refused outright. Ask for the reason instead of
            # naming one.
            echo "Why:  ./scripts/deploy-status.sh --errors"
            echo "Most often the phone: unlocked, same Wi-Fi as the Mac, no VPN,"
            echo "and showing in Xcode ▸ Window ▸ Devices and Simulators."
            echo "Re-run without a new commit: the Actions tab ▸ Deploy ▸ Run workflow"
            return 1 ;;
    esac
    return 2
}

if [ "$wait" -eq 1 ]; then
    # What is already recorded for this sha. Empty unless --fresh, so a normal
    # --wait keeps returning the first verdict it sees.
    baseline=""
    [ "$fresh" -eq 1 ] && baseline=$(look)
    if [ "$fresh" -eq 1 ]; then
        echo "waiting for a new verdict for ${sha:0:7} (ignoring the one already recorded)"
    fi
    # A device build plus install is slower than CI — allow ~15 minutes.
    for _ in $(seq 1 45); do
        out=$(look)
        if [ -n "$out" ] && [ "$out" != "$baseline" ]; then report "$out"; exit $?; fi
        sleep 20
    done
    echo "no deploy verdict for ${sha:0:7} after 15 minutes"
    no_verdict_help
    exit 2
fi

if [ "$errors" -eq 1 ]; then
    if git fetch -q origin "refs/deploy/errors/$sha" 2>/dev/null; then
        git show FETCH_HEAD:errors.txt
        exit 1
    fi
    echo "no deploy error blob for ${sha:0:7} (it installed, is still running, or predates refs/deploy/errors)"
    exit 2
fi

out=$(look)
if [ -z "$out" ]; then
    echo "no deploy verdict yet for ${sha:0:7}"
    no_verdict_help
    exit 2
fi
report "$out"
exit $?
