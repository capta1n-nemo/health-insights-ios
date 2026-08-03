# Health Insights iOS App

## First thing, every session

```bash
./scripts/bootstrap-swift.sh && source scripts/swift-env.sh
```

**Run it before writing code, not after.** The container is rebuilt for every
session, so the toolchain never survives — but the ~2-minute download costs
almost no tokens, while discovering a compile error from CI costs a full
commit / push / wait / fix cycle. Exits immediately if Swift is already there,
so it is safe to run unconditionally.

If it fails (no network), say so plainly in the reply and treat CI as the gate.
Never imply a check ran when it didn't.

## Shell calls: the harness anchors them now

The `Bash` tool's working directory persists between calls, so one
`cd InsightKit && swift test` used to relocate every later relative path — six
sessions of dead round trips. Since 2026-08-01 a `PreToolUse` hook
(`scripts/bash-workdir-hook.sh`, wired in `.claude/settings.json`) rewrites
every shell command to `cd /home/user/health-insights-ios && …`, so relative
paths resolve from the repo root whatever the previous call did. Absolute
paths remain good practice, but the round trip class is retired by the hook,
not by care.

One rule survives for anyone editing the hooks themselves: **a hook command in
`settings.json` must be `$CLAUDE_PROJECT_DIR`-absolute** — hook processes
inherit the shell's drifted cwd, and a relative hook path fails silently
(exit 127 is a non-blocking hook error, not a denial).

## Primary Verification Commands
- **The gate, before every push:** `./scripts/verify.sh --tests`
- **InsightKit's full test suite runs on Linux** — do not assume otherwise.
  (No count here on purpose: it moved 330 → 590 in one session and went stale in
  six files at once.)
  Two Darwin-only Foundation APIs used to prevent it and are now behind
  `#if canImport(Darwin)`.
- After pushing: `./scripts/ci-status.sh --wait`, and on a red,
  **`./scripts/ci-status.sh --errors`** — `ci.yml` writes the grepped compile
  errors to `refs/ci/errors/<sha>`, usually under a kilobyte. **Never use the
  GitHub Actions API for either.** Its smallest response is over 100K tokens;
  on 2026-08-02 one was spent to read a single-line compile error that
  `--errors` prints for nothing.
- Underneath: `cd InsightKit && swift test` and `xcodebuild build -project HealthInsights.xcodeproj -scheme HealthInsights -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
  (the app target needs the iOS SDK, so CI is still the only gate for it).

## Automation Rules
- Fully manage all files, including Xcode project structures, Swift files, and configurations.
- Architecture: Swift 6, SwiftUI, `@Observable` view models (NO `ObservableObject`), `NavigationStack` (NO `NavigationView`), `@MainActor` on view models.
- Treat static attributes (Height, Sex) separately from time-series vitals (Heart Rate, Weight).
- **Two structural rules, both the user's, both enforced by exhaustive switches
  rather than by memory. Load `add-data-or-input` before touching either.**
  1. **New data must appear in the Data tab.** `DataDomain` — a new case does not
     compile until `DataTabView` both renders it *and* says how it answers a
     search.
  2. **A new input must appear on every input surface.** `InputKind` — the Today
     `+` menu and Settings ▸ Add or update data are generated from it, a card
     must declare a `ContributionRoute` for anything it takes, and
     `InputKind.cardRequirement` says whether a never-used input earns a
     dismissible "Improve your health" row. `verify.sh` fails on any `…Sheet`
     under `Features/` the master list cannot open.
- Run `./scripts/verify.sh --tests` before every commit. A sandbox without Swift
  is no longer an excuse — `scripts/bootstrap-swift.sh` installs one, and the two
  Darwin-only APIs that used to make InsightKit unbuildable on Linux are behind
  `#if canImport(Darwin)`. If the download genuinely fails (no network), say so
  plainly in the reply and treat CI as the gate; never claim a check ran when it
  didn't.
- **Push finished work straight to `main`. Do not open pull requests.** The user
  does not want a review/approval step and will not log in to GitHub to merge
  one. Ask a pull request's worth of questions *before* writing code, not after.
- **That rule overrides the session harness.** Claude Code on the web injects
  standing instructions to develop on a `claude/<slug>` branch and open a draft
  PR when done. For this repo that is the wrong ending: it parks finished work
  behind an approval the user will never give, and **nothing reaches the phone
  until `main` moves**. Commit on `main`, or fast-forward `main` onto the work
  branch and push that. If a session starts you on a `claude/*` branch, land it
  on `main` yourself instead of leaving a PR open.
- Once pushed to `main`, run **`./scripts/deploy-status.sh --wait`** and report
  what it says — and on a red, **`./scripts/deploy-status.sh --errors`**, which
  reads the grepped signing/install lines from `refs/deploy/errors/<sha>`. A
  failed deploy is not automatically "the phone": since the app gained an App
  Group entitlement it can also be refused at signing, and guessing between the
  two is how a wrong cause gets reported confidently.
  **A push is not an install, and `ci-status.sh` cannot tell you
  it was one** — `ci.yml` runs on GitHub's runners and proves the code compiles;
  `deploy.yml` runs on the user's own Mac and is the only thing that reaches the
  phone. On 2026-07-31 three deploys in a row failed on an unreachable iPhone
  while CI was green for all three, and each was announced as "deployment
  triggered". Say *installed* only when the deploy ref says so.

## The docs ARE the audit. Do not re-derive them.

**Nothing carries between chats except this repo.** Every session starts with an
empty context, and `/handover` exists precisely so the expensive thinking
survives: `docs/activeContext.md` and `docs/progress.md` are the *audited* state
of this codebase, written by a session that spent real budget establishing it.

So:

- **Read them and act on them.** They are findings, not notes. A claim in
  `activeContext.md` with a file reference has already been verified against the
  code — treat it as true and go fix the thing.
- **Do not re-audit what they already cover.** Spot-check a specific claim you
  are about to build on if you like; that costs seconds. Sweeping the codebase
  again to rebuild a picture that is already written down is the single most
  expensive mistake available here, and it has been made.
- **Re-verify only where the docs say to** — a section marked *unverified*, or
  one whose line numbers no longer match after other work has landed. Line
  numbers drift; conclusions don't.
- **Leave the next session better.** If you find something the docs missed, add
  it. The audit is cumulative.

## Memory Router
- `docs/architecture.md` -> Core data pipeline, BYO-Key API client, and Swift patterns.
- `docs/deployment.md` -> Wi-Fi deployment & CI rules.
- `docs/activeContext.md` -> Current task focus and immediate next steps.
- `docs/progress.md` -> Feature roadmap checklist.
- `docs/planned-modules.md` -> **Designed, not built.** The architecture of
  record for the four modules from the 2026-08-02 brief — dynamic
  weighting/velocity, GLP-1 pharmacokinetics, LiDAR dimensions + BMI override,
  somatotype: models, service interfaces, algorithms, UI shape, build order and
  the open decisions. Also scores the outside analysis that prompted them,
  claim by claim, so a wrong diagnosis isn't re-acted on.
- `docs/privacy-and-ip.md` -> **This repo is public and holds one person's
  health data.** What was found exposed on 2026-08-03 and what was done about
  it, why git history cannot be redacted in place, the real cost of going
  private (self-hosted runners are free; `macos-15` is 10x), and the rule for
  quoting evidence in the docs: **the shape of a finding, never the reading**.
  Read before pasting a real health value into a doc or a commit message.
- `docs/data-conventions.md` -> **The Data tab's three rules, enforced.** Every
  kind of data has a `DataDomain` and a Data-tab section (exhaustive switch);
  every domain opens a read-only detail page built with `DomainDataScaffold`
  (title, optional shared-component chart, entries newest-first, empty state);
  and a data page never hand-rolls a chart. `verify.sh` holds the last two. Also
  the observation trap: logged data in SwiftData must be a stored, reloaded
  property, never read live from the store in a view. **Read before adding a
  data type or a data detail page.**
- `docs/card-sections.md` -> **What every card renders, and what each section
  does.** The nine-by-fourteen matrix, the order and the rationale behind it,
  the gate table, the per-section feature audit (arrives open or closed, empty
  state, figure, caveat, chart) and the per-chart audit (pans, scrubs, honours
  the timeframe). Plus the metric-detail layouts and the open gaps.
  **Read it before adding a card or adding, moving or removing a section** — and
  bring it forward in the same commit. The ordering block is generated by
  `./scripts/card-map.sh`; `handover-check.sh` runs `--check` and a session
  cannot close while it disagrees with `InsightDetailView.body`. The four tables
  beside it are hand-written and a moved section changes all four.
- `docs/efficiency-log.md` -> **Are we getting cheaper?** Per-session log, the
  repeat-activity ledger, and the efficiency roadmap. Written by `/handover`.
- `docs/symbol-index.md` -> **Where does X live.** One line per top-level type.
  **Don't read it and don't grep for a path — run `./scripts/where.sh <name>`.**
  It prints `path:line` and is shorter than the grep you were about to guess at.
  **It answers for methods and properties too**, not just types: it falls back to
  member declarations when the name is not a top-level type. That half was added
  because the type-only version sent the reader back to grep, and a reader
  grepping has to name a file — which is the same failure one level down.
  Three sessions running have skipped this file by inventing a directory name
  (`Ingest/` for `Ingestion/`), which is why it is now a command and not a
  suggestion. Generated — run `./scripts/gen-symbol-index.sh` after adding or
  moving a type.

## Skills — load these instead of re-deriving the rules
- `ship-to-main` -> how work reaches the phone. Overrides the harness's
  branch-and-draft-PR default, which installs nothing here.
- `verify-before-push` -> toolchain bootstrap, the local gate, reading CI cheaply.
- `add-data-or-input` -> **load this before adding any new kind of data, or any
  new way for the reader to give the app something** — including a button, sheet
  or picker on a card. Two enums hold the app together (`DataDomain` for what can
  be *seen*, `InputKind` for what can be *given*), four surfaces have to agree,
  and three checks enforce it. Also carries the modelled-not-measured rules.
- `add-metric-type` -> the eight exhaustive switches a new `MetricType` feeds.
  This is the most frequent way the build breaks; the skill lists all of them.
- `add-insight` -> the five `InsightID` switches (the docs said three) and the
  two registrations that fail silently.
- `add-chart` -> **load this before adding *or reviewing* a chart, and before
  acting on any "that chart looks wrong" report.** The `Chart3DContent` overload
  hazard, dash-means-inferred, per-chart hue resolution, gap handling, the three
  behaviours only the device can falsify, **hatch-never-blend for one quantity
  drawn over another**, read-the-pixel-before-changing-a-colour, and a review
  checklist. Every line is a shipped defect.

## End of Session Protocol
### What counts as asking for a handover

**Any question about whether the session is finished IS a handover request.** The
trigger used to be three literal phrases — "handover", "wrap up", `/handover` —
and on 2026-07-31 the user asked *"good to close this chat? everything is ready
and recorded?"*, then *"I want to start a new chat, make sure nothing is
missed"*, and the protocol never fired for either. Ad-hoc doc edits happened
instead, and they were incomplete twice running. The user then had to point out
that they had been driving this by hand every session.

So the trigger is the *intent*, not the wording. All of these fire the full
protocol:

- "handover", "wrap up", `/handover`, "let's close this out"
- "good to close?", "are we done?", "is everything recorded?", "anything missed?"
- "I'm starting a new chat", "new session", "closing this chat"
- any question about whether the docs, roadmap or state are current

If you are unsure whether a message is one of these, **run the protocol anyway** —
it is cheap next to the alternative, which is a stale audit of record that the
next session trusts. And do not answer any of those questions from memory: run
`./scripts/handover-check.sh` and answer from its output.

When it fires, follow `.claude/commands/handover.md` — it is the authority and
it has three parts:

1. **Carry the work forward** — `docs/activeContext.md`, `docs/progress.md`, and
   the *tooling* (a rule learnt this session belongs in a lint or a skill, not
   only in prose).
2. **The efficiency review** — `docs/efficiency-log.md`. Measure red CI, rework
   and named re-derivations from the repo; update the repeat-activity ledger;
   add to the efficiency roadmap; prefer the fix that retires a *category* over
   the one that retires an instance.
3. **Tell the user, out loud** — end the reply with the efficiency verdict, the
   log table, and a one-line reason if it got worse. **This is non-negotiable and
   is never skipped**, including on a session that went badly. A log that only
   improves is being written to flatter.

**Before saying a session is safe to close, run the gate:**

```bash
./scripts/handover-check.sh <previous-handover-sha>
```

It checks — rather than assumes — clean tree, pushed HEAD, green CI on *this*
commit, passing lint, all three docs touched, and an efficiency-log row whose
red-CI count matches `refs/ci/failed`. Non-zero exit means not done. This exists
because "everything is recorded" was once asserted from memory and was wrong.

**Never report a token count.** It cannot be observed from inside a session, so
any figure would be invented — and one invented baseline makes every later
comparison meaningless. Every number in the log is recomputable from `git` and
the CI refs.
