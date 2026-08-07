#!/usr/bin/env bash
#
# **What did the app-target test run actually fail at?** (backlog D63)
#
# `verify.sh --tests` runs `xcodebuild test` for `HealthInsightsTests`, and the
# Mac gate is the only place those tests can ever run. On a quiet machine they
# are green. On the evening of 2026-08-07, with ten-plus worktree agents
# building at once, the run failed **repeatedly and differently each time** —
# `CardRoutingTests` reporting *zero tests executed* with the host killed,
# `CardRenderSmokeTests` failing, `AppModelStateTests` green throughout.
#
# The damage was not the flakiness. The damage was that the gate's failure
# **named no cause**, so the session had to guess, and guessed wrong three
# times — the third guess being "it is pre-existing, push past the gate",
# argued from a `git stash` comparison that was contaminated by container
# state. Both commits were green when re-run afterwards.
#
# ⚠️ **So the fix is emphatically not a quieter gate.** A red that is usually
# environmental trains a session to push through a real one; that is the
# defect, and suppressing failures would deepen it. The fix is a gate that
# **tells the truth faster**:
#
#   * *"a test asserted and failed"* and *"the test host was killed before it
#     ran anything"* are different sentences, and only the first one is about
#     the diff. This script decides which, from the log, and says so.
#   * Everything it cannot attribute to the diff is **retried once** by
#     `verify.sh` before it is called a failure — and the retry is announced,
#     never silent, because an unannounced retry is how flakiness stops being
#     visible.
#   * A failure prints the **machine load at the time**, so "twelve agents were
#     compiling" is evidence in the transcript rather than a hunch a later
#     session has to re-form.
#
# It also closes the inverse hole, which is worse and was never noticed:
# **a suite that executes zero tests currently reports as a pass.** `xcodebuild`
# exits 0, `Executed 0 tests, with 0 failures` scrolls past, and the gate prints
# a green tick for a class that never ran. See the `empty` verdict.
#
# Usage:
#   app-test-report.sh verdict <log> <xcodebuild-exit-status>
#       Line 1: `<token> <retryable 0|1>`. Remaining lines: what to tell the
#       reader, already worded. Always exits 0 — the caller owns the exit code.
#   app-test-report.sh load
#       One-line snapshot of what else is running on this Mac.
#   app-test-report.sh --self-test
#       Canary the classifier against recorded log shapes. A lint nobody
#       canaries is a lint nobody has tested — this repo has learnt that twice.
#
# Tokens, and what each one means for the reader:
#   assertion  a test ran and disagreed with the code            → YOUR DIFF
#   compile    the test target did not build                     → YOUR DIFF
#   empty      zero tests executed although nothing errored      → NOT A PASS
#   host       the test host crashed, hung or was killed         → the machine
#   infra      simulator/toolchain could not get as far as tests → the machine
#   locked     another build holds the derived-data path         → concurrency
#   unknown    it failed and left no attributable evidence       → unattributed
#   clean      the log holds no failure evidence at all

set -uo pipefail

# --- What else is this Mac doing? ------------------------------------------
#
# Printed beside a failure, not instead of it. The point is that a later
# session reading the transcript can see the concurrency without having to
# re-derive it — the 2026-08-07 session had to reason its way to "ten to twelve
# worktree agents" from memory, and that number is the whole diagnosis.
load_snapshot() {
    local avg cpus builds sims frontends hosts gates per
    avg=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}')
    cpus=$(sysctl -n hw.ncpu 2>/dev/null || echo 0)
    # ⚠️ **`pgrep -f … | wc -l`, never `pgrep -cf`.** BSD `pgrep` has no `-c`:
    # it prints a usage message to stderr and exits 2, so the first version of
    # this line reported "0 xcodebuild" *while an xcodebuild was holding the
    # build database against it*. A load report that under-counts is worse than
    # none — it is evidence for the wrong conclusion, which is the exact defect
    # D63 is about. Caught by running it, not by reading it.
    builds=$(pgrep -f 'xcodebuild' 2>/dev/null | wc -l | tr -d ' ')
    frontends=$(pgrep -f 'swift-frontend' 2>/dev/null | wc -l | tr -d ' ')
    sims=$(xcrun simctl list devices booted 2>/dev/null | grep -c 'Booted' || true)
    # **Test hosts and sibling gates, not just compiles.** Without these the
    # line can read "load 20.4 … 0 xcodebuild, 0 swift-frontend", which looks
    # like the counters are broken again and invites the reader to discard the
    # whole report. They were not broken — the other eleven worktrees were
    # *running tests*, not compiling, and that is exactly the load that kills a
    # test host. Observed on the run that reproduced D63, 2026-08-08.
    hosts=$(pgrep -f 'xctest' 2>/dev/null | wc -l | tr -d ' ')
    gates=$(pgrep -f 'verify.sh' 2>/dev/null | wc -l | tr -d ' ')
    : "${avg:=?}" "${builds:=0}" "${frontends:=0}" "${sims:=0}" "${hosts:=0}" "${gates:=0}"

    printf 'Machine at this moment: load %s across %s cores' "$avg" "$cpus"
    printf ', %s xcodebuild, %s swift-frontend, %s xctest host(s), %s other verify.sh, %s booted simulator(s).\n' \
        "$builds" "$frontends" "$hosts" "$gates" "$sims"

    # A judgement, not just numbers, because "load 24.1" means nothing without
    # the core count and the reader should not have to do the division. One
    # runnable process per core is saturated; twice that is the state D63 was
    # observed in.
    if [ "$cpus" -gt 0 ] && [ "$avg" != '?' ]; then
        per=$(awk -v a="$avg" -v c="$cpus" 'BEGIN { printf "%.1f", a / c }')
        if awk -v p="$per" 'BEGIN { exit !(p >= 2.0) }'; then
            printf 'That is %sx saturation — the conditions D63 was recorded under.\n' "$per"
        elif awk -v p="$per" 'BEGIN { exit !(p >= 1.0) }'; then
            printf 'That is %sx saturation — busy, but not the D63 conditions.\n' "$per"
        else
            printf 'That is %sx saturation — the machine is quiet.\n' "$per"
        fi
    fi
}

# --- Which suites executed nothing? ----------------------------------------
#
# `Test Suite 'X' passed ... Executed 0 tests` is the shape that made a killed
# host look like a green class. Reported by name, because "some suite ran
# nothing" is not actionable and "CardRoutingTests ran nothing" is.
#
# Container suites (`All tests`, `*.xctest`) are only interesting when the whole
# run executed nothing — otherwise they are noise around a real inner suite.
empty_suites() {
    awk '
        match($0, /Test Suite .[^'\''"]+/) {
            s = substr($0, RSTART, RLENGTH)
            sub(/Test Suite ./, "", s)
            suite = s
        }
        /Executed 0 tests/ && suite != "" { print suite; suite = "" }
        # swift-testing says it differently, and says it once for the whole run.
        /Test run with 0 tests/ { print "the swift-testing run" }
    ' "$1" | sort -u
}

total_executed() {
    # The last total wins: after a crash-restart xcodebuild prints running
    # totals, and only the final one covers the whole run.
    grep -oE 'Executed [0-9]+ tests?' "$1" 2>/dev/null | tail -1 \
        | grep -oE '[0-9]+' || printf '0'
}

verdict() {
    local log=$1 status=${2:-0}
    [ -f "$log" ] || { printf 'unknown 1\nNo log at %s — nothing can be attributed.\n' "$log"; return 0; }

    # ⚠️ **Order is the whole design here, and it runs diff-first.**
    #
    # A run can hold both an assertion and a crash — one class disagreed with
    # the code while another was killed. Retrying that would be wrong twice
    # over: it costs a second full run and it invites "it passed the second
    # time" over a genuine failure. So any evidence that a test *ran and
    # disagreed* wins over every environmental marker, and is never retried.

    # A crashed test case also prints `Test Case '...' failed`, so that line is
    # deliberately NOT an assertion marker on its own. These three are: XCTest's
    # file:line diagnostic, swift-testing's recorded issue, and a bare
    # XCTAssert/XCTFail report.
    if grep -qE ': error: -\[|recorded an issue|XCTAssert[A-Za-z]* failed|XCTFail' "$log"; then
        printf 'assertion 0\n'
        printf 'A test ran and disagreed with the code. This IS about your diff.\n'
        grep -E ': error: -\[|recorded an issue|XCTAssert[A-Za-z]* failed|XCTFail' "$log" | head -12
        return 0
    fi

    # Compile errors in the test target: `file.swift:12:5: error: …` with no
    # `-[` (which would make it a test diagnostic, handled above).
    if grep -qE '\.swift:[0-9]+:[0-9]+: error: ' "$log"; then
        printf 'compile 0\n'
        printf 'The test target did not build. This IS about your diff.\n'
        grep -E '\.swift:[0-9]+:[0-9]+: error: ' "$log" | head -12
        return 0
    fi

    # Concurrency, and already survivable: kept as its own token because the
    # remedy (wait, re-run) differs from the rest and the path is worth printing.
    if grep -q 'database is locked' "$log"; then
        printf 'locked 1\n'
        printf 'Another build holds this derived-data path. Not a test failure, and not your diff.\n'
        return 0
    fi

    # The host died. Every one of these means the tests did not get to speak,
    # which is why none of them is a statement about the diff.
    if grep -qE 'Restarting after unexpected exit|Lost connection to the test|test runner exited|never began executing tests|Early unexpected exit|crashed with signal|Test crashed|Failed to background test runner|terminated due to signal|Message from debugger' "$log"; then
        printf 'host 1\n'
        printf 'The test host died before the tests could report. This is the MACHINE, not your diff.\n'
        grep -E 'Restarting after unexpected exit|Lost connection to the test|test runner exited|never began executing tests|Early unexpected exit|crashed with signal|Test crashed|Failed to background test runner|terminated due to signal' "$log" | head -6
        return 0
    fi

    # Never reached the tests at all. `launchd_sim … could not bind to session`
    # is here by name: it is what the 2026-08-07 session's second wrong turn —
    # "give the app tests their own simulator" — actually produced.
    if grep -qE 'Unable to boot|Failed to boot|launchd_sim|could not bind to session|Timed out waiting for|Simulator device failed|Unable to find a destination|failed to install|Application .* is not installed|Domain = IXErrorDomain|Domain = FBSOpenApplicationServiceErrorDomain' "$log"; then
        printf 'infra 1\n'
        printf 'The simulator never got as far as running tests. This is the MACHINE, not your diff.\n'
        grep -E 'Unable to boot|Failed to boot|launchd_sim|could not bind to session|Timed out waiting for|Simulator device failed|Unable to find a destination|failed to install|Domain = IXErrorDomain|Domain = FBSOpenApplicationServiceErrorDomain' "$log" | head -6
        return 0
    fi

    # --- Zero tests executed --------------------------------------------------
    #
    # Reached whether or not xcodebuild failed, and that is the point. `Executed
    # 0 tests` beside exit status 0 is the false green this repo had no check
    # for: a class that never ran cannot have passed, and the gate said it did.
    local empties total
    empties=$(empty_suites "$log")
    total=$(total_executed "$log")
    if [ -n "$empties" ] || [ "$total" = '0' ]; then
        printf 'empty 1\n'
        printf 'Zero tests executed. This is NOT a pass — nothing has been checked.\n'
        if [ -n "$empties" ]; then
            printf 'Executed nothing: %s\n' "$(printf '%s' "$empties" | tr '\n' ' ')"
        fi
        printf 'A suite that runs no tests is a host problem, not a green suite.\n'
        return 0
    fi

    if [ "$status" -eq 0 ]; then
        printf 'clean 0\n'
        printf 'Executed %s tests, no failure evidence in the log.\n' "$total"
        return 0
    fi

    # It failed and said nothing attributable. Retryable — but the wording has
    # to stay honest: unattributed is not the same as environmental, and the
    # caller must not report it as one.
    printf 'unknown 1\n'
    printf 'The run failed and left no evidence naming a cause.\n'
    printf 'It is NOT known to be environmental — it is unattributed. Read the full log.\n'
    return 0
}

# --- Canary ----------------------------------------------------------------
#
# Every fixture below is a shape that has actually been seen in this repo's
# logs, not an invented one. Run after touching any pattern above:
#     ./scripts/app-test-report.sh --self-test
self_test() {
    # Deliberately NOT `local`: the EXIT trap runs after this function has
    # returned, and a local would be unbound by then — which under `set -u` is
    # an error printed *after* the results, i.e. a passing canary that looks
    # like it broke.
    pass=0; count=0
    st_tmp=$(mktemp -d)
    trap 'rm -rf "$st_tmp"' EXIT

    check() { # name, expected-token, exit-status, log-body
        local name=$1 want=$2 status=$3 body=$4 got out
        count=$((count + 1))
        printf '%s\n' "$body" > "$st_tmp/log"
        # Captured whole, then trimmed. Piping `verdict` straight into `head -1`
        # closes the pipe under it and it dies of EPIPE mid-report.
        out=$(verdict "$st_tmp/log" "$status")
        got=$(printf '%s\n' "$out" | head -1 | awk '{print $1}')
        if [ "$got" = "$want" ]; then
            printf '  ok    %-34s -> %s\n' "$name" "$got"
            pass=$((pass + 1))
        else
            printf '  FAIL  %-34s -> %s (wanted %s)\n' "$name" "$got" "$want"
        fi
    }

    check 'XCTest assertion' assertion 1 \
'Test Suite '"'"'CardRoutingTests'"'"' started at 2026-08-07 21:03:11.001.
/Users/j/HealthInsightsTests/CardRoutingTests.swift:42: error: -[HealthInsightsTests.CardRoutingTests testEveryCardRoutes] : XCTAssertEqual failed: ("9") is not equal to ("14")
Test Case '"'"'-[HealthInsightsTests.CardRoutingTests testEveryCardRoutes]'"'"' failed (0.004 seconds).
Executed 40 tests, with 1 failure (0 unexpected) in 11.2 seconds'

    check 'swift-testing issue' assertion 1 \
'✘ Test cardsAreNeverHidden() recorded an issue at CardRoutingTests.swift:88:5: Expectation failed
✘ Test run with 40 tests failed after 11.4 seconds with 1 issue.'

    check 'compile error in test target' compile 1 \
'/Users/j/HealthInsightsTests/CardRenderSmokeTests.swift:19:24: error: cannot find '"'"'AppModel'"'"' in scope
** TEST BUILD FAILED **'

    # ⚠️ The one that matters most: a killed host, which must never read as a
    # diff failure however loudly `TEST FAILED` is printed underneath it.
    check 'host killed mid-run' host 1 \
'Test Suite '"'"'CardRoutingTests'"'"' started at 2026-08-07 21:41:02.113.
Restarting after unexpected exit, crash, or test timeout in HealthInsightsTests.CardRoutingTests/testEveryCardRoutes(); summary will include totals from previous launches.
Test Case '"'"'-[HealthInsightsTests.CardRoutingTests testEveryCardRoutes]'"'"' failed (0.000 seconds).
** TEST FAILED **'

    check 'lost connection to test manager' host 1 \
'Testing failed:
	Lost connection to the test manager service.
** TEST FAILED **'

    check 'simulator would not boot' infra 1 \
'Unable to boot device because we cannot determine the runtime bundle.
launchd_sim failed to start: could not bind to session
** TEST FAILED **'

    check 'derived-data lock' locked 1 \
'error: accessing build database "/Users/j/Library/Caches/.../build.db": database is locked
error: Build service could not start'

    # The false green. Exit status 0 and a "passed" line, and it is still not a
    # pass — this is the hole the D63 fix exists to close.
    check 'zero tests but exit 0' empty 0 \
'Test Suite '"'"'CardRoutingTests'"'"' passed at 2026-08-07 21:03:11.123.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
** TEST SUCCEEDED **'

    check 'genuinely green' clean 0 \
'Test Suite '"'"'CardRoutingTests'"'"' passed at 2026-08-07 21:03:11.123.
	 Executed 14 tests, with 0 failures (0 unexpected) in 3.100 (3.104) seconds
Test Suite '"'"'All tests'"'"' passed at 2026-08-07 21:03:14.000.
	 Executed 40 tests, with 0 failures (0 unexpected) in 11.200 (11.210) seconds
** TEST SUCCEEDED **'

    check 'failed with no evidence' unknown 1 \
'Executed 40 tests, with 0 failures (0 unexpected) in 11.200 seconds
xcodebuild exited nonzero for a reason it did not print'

    # An assertion beside a crash: diff-first, and NOT retryable. Retrying a run
    # that contains a real failure is how "it passed the second time" gets said
    # about a genuine break.
    check 'assertion beside a crash' assertion 1 \
'Restarting after unexpected exit, crash, or test timeout in HealthInsightsTests.CardRenderSmokeTests/testX().
/Users/j/HealthInsightsTests/AppModelStateTests.swift:12: error: -[HealthInsightsTests.AppModelStateTests testY] : XCTAssertTrue failed'

    # --- The two-script contract -------------------------------------------
    #
    # `pre-push-gate.sh` decides whether a denial reads "fix your diff" or
    # "wait for the machine" by grepping for the sentences printed *here*. That
    # coupling has already broken once — on 2026-08-06 the gate grepped for
    # xcodebuild's wording when verify.sh had replaced it, so the branch matched
    # nothing and a build collision was presented as a broken diff.
    #
    # Rewording a sentence above is therefore a silent behaviour change one
    # script away. This canaries it: the phrase must exist on both sides.
    local here gate
    here=$(cd "$(dirname "$0")" && pwd)
    gate="$here/pre-push-gate.sh"
    if [ -f "$gate" ]; then
        local phrase
        for phrase in 'This is the MACHINE, not your diff' \
                      'Another build holds' \
                      'Zero tests executed'; do
            count=$((count + 1))
            if grep -qF "$phrase" "$here/app-test-report.sh" && grep -qF "$phrase" "$gate"; then
                printf '  ok    %-34s -> both scripts\n' "contract: ${phrase:0:22}…"
                pass=$((pass + 1))
            else
                printf '  FAIL  %-34s -> pre-push-gate.sh cannot match it\n' "contract: ${phrase:0:22}…"
            fi
        done
    fi

    printf '\n%s of %s classifier fixtures pass.\n' "$pass" "$count"
    [ "$pass" -eq "$count" ]
}

case "${1:---self-test}" in
    verdict)    verdict "${2:?log path}" "${3:-0}" ;;
    load)       load_snapshot ;;
    --self-test|self-test) self_test ;;
    *) printf 'usage: %s verdict <log> <exit> | load | --self-test\n' "$0" >&2; exit 2 ;;
esac
