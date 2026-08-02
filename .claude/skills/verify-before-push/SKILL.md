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

The app target still needs CI: `xcodebuild` requires the iOS SDK, so SwiftUI
and HealthKit code is only compiled there. Local green means *InsightKit* is
green.

### The class of error CI catches and `swift test` never will

**An InsightKit type constructed from the app target needs an explicit
`public init`.** A `public struct`'s memberwise initialiser is *internal*, and
the InsightKit tests use `@testable import`, so they can build the type and the
app cannot. Local green, CI red, every time — and the diagnostic
("initializer is inaccessible due to 'internal' protection level") names the
call site in the app, not the declaration that is missing the init.

If you add a public struct to InsightKit and construct it anywhere under
`HealthInsights/`, write the `public init` in the same edit.
