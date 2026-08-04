---
name: verify-before-push
description: Run before every push. Installs a Swift toolchain if the sandbox has none, runs the full InsightKit suite locally, and lints the traps that have actually broken this repo's CI. Use whenever Swift files have changed and you are about to commit.
---

# Verify before pushing

CI is a ~90-second round trip on a self-hosted Mac, and reading its result used
to cost a 450 KB API response. Almost everything CI catches can be caught here
first, for nothing.

## 1. Get a toolchain (once per sandbox)

```bash
./scripts/bootstrap-swift.sh && source scripts/swift-env.sh
```

~2 minutes, ~780 MB, then `swift` is on PATH. Skips instantly if already
present. **InsightKit builds and its full suite passes on Linux** — that was
made true deliberately; see `docs/architecture.md` ▸ "Running the tests
anywhere". If the download fails (no network), say so plainly and fall back to
CI as the gate. Don't pretend a check ran.

## 2. Run the gate

```bash
./scripts/verify.sh --tests
```

Without `--tests` it is lint-only and takes under a second, so it is worth
running even with no toolchain. It checks:

- `@Observable` not `ObservableObject`, `NavigationStack` not `NavigationView`
- InsightKit imports no platform framework — the property that makes local
  testing possible at all
- XCTest, not swift-testing
- **Key paths on tuple elements** (`\.0`) — a compile error that cost a CI cycle
- **The `Chart3DContent` overload hazard** — a mark builder returning
  `some View` instead of `some ChartContent` silently drops `.lineStyle` and
  `.foregroundStyle`. Broke CI twice.
- **Every exhaustive `MetricType` switch mentions every metric.** Adding a case
  and missing one of `displayName`, `unit`, `family`, `chartStyleIndex`,
  `presentation`, `maxValidInterval`, `requiresPositiveValue` is the single most
  common way this repo breaks its own build.

## 3. Interpreting a failure

A lint hit is a fact, not an opinion — go and look. If you conclude a rule is
wrong for a case, **change the rule in `scripts/verify.sh` with a comment
saying why**, rather than working around it silently. The `ObservableObject`
check is already scoped this way: the three integration services in
`Core/Integrations` are deliberately exempt.

## 4. After pushing

```bash
./scripts/ci-status.sh --wait      # 0 passed / 1 failed / 2 no verdict yet
./scripts/ci-status.sh --errors    # on a red: the compile errors themselves
```

**Never** reach for the GitHub Actions API for either — its smallest response
is over 100K tokens. `ci.yml` already writes the grepped errors to
`refs/ci/errors/<sha>`, and `--errors` fetches that blob; on 2026-08-02 an
Actions API call returned 446 KB to deliver one line of compile error that was
sitting in a git ref the whole time.

### Whether the app target needs CI depends on where you are running

**On the user's Mac it does not, since 2026-08-04.** `verify.sh --tests` runs
the real `xcodebuild` against the iOS SDK, so the gate compiles SwiftUI and
HealthKit exactly as CI does. ~1.4s incremental; minutes on a cold checkout,
which is the one time it is worth waiting for. It targets
`generic/platform=iOS` and so **needs no simulator** — the first Mac session
could not boot one, and a gate that needed one would have been dead all day.

**In a hosted Linux session it still does.** There is no iOS SDK, so `verify.sh`
falls back to `swiftc -parse` per app file — which catches an unbalanced brace
and **nothing else**, because parsing resolves no names. Local green there means
*InsightKit* is green and says nothing about the app target.

The section below is therefore about a Linux session, and about what CI is for.

### The class of error CI catches and `swift test` never will

**An InsightKit type constructed from the app target needs an explicit
`public init`.** A `public struct`'s memberwise initialiser is *internal*, and
the InsightKit tests use `@testable import`, so they can build the type and the
app cannot. Local green, CI red, every time — and the diagnostic
("initializer is inaccessible due to 'internal' protection level") names the
call site in the app, not the declaration that is missing the init.

If you add a public struct to InsightKit and construct it anywhere under
`HealthInsights/`, write the `public init` in the same edit.

## The gate checks itself now, because it lied once

On 2026-08-02 `./scripts/verify.sh --tests` exited **0** on a tree that plain
`./scripts/verify.sh` exited **1** on. The mode this skill tells you to run was
the weaker of the two, and it shipped a compile error to `main` on a commit
whose gate had printed `Clean.`

The test block's runner-artifact recovery set `fail=0` to undo a false failure
it had just diagnosed — and `fail` is the flag every lint above it also sets, so
a real lint failure was erased whenever the serial re-run passed.

**A recovery may only undo the thing it diagnosed.** A recovery that clears a
flag it does not own silently forgives everything else that set it. The test run
owns `testfail`; `fail` is assigned zero exactly once, at its declaration; and
`verify.sh` greps itself for a stray assignment, with the needle assembled from
two string pieces so the check's own source cannot match it.

Two consequences for anyone editing the script:

- **Give a new recovery its own flag.** The self-check fails the build if you
  reach for `fail=0`.
- **`ban` skips comment lines.** Quoting a banned pattern while documenting the
  fix for it is the house style here, not a violation — and before this,
  documenting a fix tripped the lint that motivated it.

And a standing one for anyone reading a green gate: **CI's `lint` job runs plain
`verify.sh` on Ubuntu with no toolchain.** That independence is what caught this,
so if local and CI ever disagree again, trust CI and go looking for the reason
rather than re-running.
