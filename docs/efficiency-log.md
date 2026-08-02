# Efficiency log

One row per chat session, written by `/handover`. The question it exists to
answer: **are we actually getting cheaper per unit of shipped work, or does it
just feel that way?**

## The honest constraint, read this first

**I cannot measure token usage.** There is no API for it from inside a session,
and a number I "estimated" would be invented — which would make this log worse
than not having one, because a fabricated baseline makes every later comparison
meaningless. Anyone tempted to add a `tokens` column: don't, unless it comes from
outside the session.

So every metric below is **auditable from the repository itself**. A future
session can recompute the whole table from `git` and the CI refs without trusting
a word of the prose. That is the property worth protecting.

The one self-reported column is *re-derivations*, and it is kept honest by
requiring each to be **named** — which file, which fact, and where it was already
written down. A count is gameable; "re-read `SeriesBridging` because I looked for
it under its own filename instead of checking `symbol-index.md`" is checkable.

## How each column is computed

| Column | Command | What it means |
| --- | --- | --- |
| Pushes | `git log --oneline <base>..HEAD` plus the push count | Round trips to CI |
| **Red CI** | `git ls-remote origin 'refs/ci/failed/*'` | **The headline waste.** Each is ~5 min of dead time plus a fix commit |
| Rework | Commits that fix something introduced earlier *in the same session* | Work done twice |
| Re-derivations | Self-reported, **each named** | Facts the docs already held |
| Tests | `cd InsightKit && swift test` count, delta from last row | Scope, and the guard on it |
| Compounding | Skills / lint rules / scripts added that stop a repeat | The only column that makes the *next* session cheaper |

**Waste** = red CI + rework + re-derivations. Lower is better, and it is judged
per push rather than absolutely — a long session that ships a lot should be
allowed more of everything.

## The failure mode this log exists to catch, and it is not what it looks like

For three sessions running, **the user had to ask whether the handover had
happened** — and each time, asking found something. The protocol was written, it
was detailed, and it did not fire, because its trigger was three literal phrases
("handover", "wrap up", `/handover`) and the user's actual words were "good to
close this chat?" and "I'm starting a new chat, make sure nothing is missed".

So the lesson is not "write a better protocol". It is:

**A ceremony that depends on being invoked will be skipped.** The checks that
matter belong in something that runs unconditionally, not in an end-of-session
ritual whose trigger is a keyword.

There are two tiers of that, and the second one matters more:

1. **Into `verify.sh`**, which runs before every push — missing script
   references and half-done `[~]` markers moved there on 2026-07-31.
2. **Into a hook**, which the *harness* runs rather than the model.
   `scripts/pre-push-gate.sh` is a `PreToolUse` hook on `Bash(git push*)`: it
   runs the full gate and **denies the push** if it fails. Tier 1 still depends
   on the model choosing to run `verify.sh`. Tier 2 does not depend on the model
   at all, which is the only real answer to "a rule the model can skip".

There is a tier 3, and the red team found it by asking the obvious question:
**what enforces the enforcer?** `verify.sh` was checked by the hook, and the hook
was checked by `verify.sh`. Deleting or `chmod -x`ing either one made the whole
arrangement fail open, silently. So the lint now also runs as a `lint` job in
GitHub Actions, gating the recorded verdict — a tier that exists whether or not
any harness, hook or model is involved.

Anything that can be moved to tier 2 should be — with one caveat learnt
immediately. The hook declares `if: "Bash(git push*)"` and fired anyway on an
ordinary `cat`, which would have run the full test suite on every shell command
in the session. **A hook that fires on everything is a hook that gets deleted**,
so `pre-push-gate.sh` now decides from the command on stdin itself and treats
the declared filter as an optimisation rather than a guarantee. A non-push exits
in 36 ms.

Also worth recording: a red-team subagent left a probe skill behind in
`.claude/skills/`, and the *repo's own new check* caught it — the probe
referenced a non-existent script and the gate refused the push. That is the
mechanism working on its author, which is the only test of it that counts.

Everything left in the ceremony should be there because it *genuinely cannot* be
mechanised — the prose judgement about what a session learnt — and everything
mechanisable should have left.

## Why "compounding" is the column that matters

Waste can be reduced by being careful, which does not survive a context reset.
It is reduced *permanently* only by moving a rule out of somebody's head and into
something that fires on its own — a lint, a skill, a self-healing script.

Session 2026-07-30 is the worked example. CI broke on a `Suggestion.Basis` switch
that `verify.sh`'s hand-maintained list did not mention. The careful fix is to add
that switch to the list. The compounding fix — the one taken — is to check the
*class*: Swift already requires a `default:`-free switch to name every case, so
the lint needs no per-switch knowledge and catches the next one nobody thought of.
One costs a line, the other retires a category.

## The repeat-activity ledger

Activities that recur across sessions, weighted by how often they fire and what
they cost. **This is the input to the efficiency roadmap**: anything at the top
that is not yet automated is the next thing to automate.

| Activity | Sessions seen | Status |
| --- | --- | --- |
| Install a Swift toolchain | every | ✅ automated — `verify.sh --tests` bootstraps itself |
| Regenerate the symbol index | every | ✅ automated — `verify.sh` fails when stale |
| Miss an exhaustive `MetricType` switch | 3+ | ✅ automated — named-switch lint |
| Miss an exhaustive switch over *another* enum | 2 | ✅ automated — generic switch lint (2026-07-30) |
| Read CI status without burning 100K tokens | every | ✅ automated — `ci-status.sh` reads `refs/ci/*` |
| Add a `MetricType` / `InsightID` / chart correctly | 4+ | ✅ skills exist |
| **Lose the working directory in a shell call** | **6** | The rule alone did not hold: ruled in `CLAUDE.md` (2026-07-31) in the plainest wording available — "absolute paths, always", annotated "pure waste" — and it recurred in session 15 twice, session 16 **five times**, session 17
**three times** and session 18 **two-to-three times**. ✅ **automated 2026-08-01 (session 19), with the user's explicit permission** — `scripts/bash-workdir-hook.sh`, a `PreToolUse` hook on `Bash` that rewrites every command to `cd <repo root> && …` via `updatedInput`. Built as session 16 scoped it: prepend, don't reject a path shape, because two of the five instances were heredocs and one a `sed`. See the roadmap entry for the finding that fell out of building it |
| Re-run the full test suite more than needed | 2 | ✅ `verify.sh --tests <pattern>` (2026-07-31) |
| Hunt for a type by guessing its filename | **3** | ✅ automated — `scripts/where.sh <Type>` (2026-07-31). Two rounds of prose failed; the fix is a command shorter than the grep |
| **Hunt for a *method* by guessing its filename** | **1** | ✅ automated — `where.sh` now falls back to member declarations (2026-07-31, session 12). The type-only version told the reader "grep is right for those", and a reader grepping has to name a file — the same failure one level down |
| **A recorded product decision that was really an implementation artefact** | **2** | ⬜ open — "no provider gives us a bedtime" (session 10) and "windowed read or whole history?" (session 12). Both were logged as blocked on something inherent; both dissolved on first inspection. No mechanical check is possible; the rule is *measure before escalating a decision to the user* |
| **A guard reporting a failure whose own premise is false** | **6** | ⚠️ partly — ruled in `CLAUDE.md` and named six times in `activeContext.md`; no mechanical check exists and it is unclear one can. Session 15's instance is the most instructive yet, because the guard was `if: always()` and the false premise was *that it always runs*: a runner that dies mid-step cannot write the verdict, so "no ref" had a third meaning nobody had enumerated. **The partial fix that generalises is to make the guard enumerate its own failure modes** — `deploy-status.sh` now prints all three and the tell for each, rather than asserting the one the author happened to think of |
| **A section shipping without saying what it inferred** | 1 | ✅ automated — `InsightSection`'s `caveat` argument has no default, so omitting it is a compile error and `.none` is a visible choice (2026-08-01, session 15). The convention it replaced was being followed by four sections out of twelve |
| **An oversized MCP result read as unanswerable rather than spilled to a file** | 1 | ✅ ruled — the Actions listing is ~450 KB and the tool writes it to disk; `python3` over that file costs a few hundred bytes. Recorded in `deploy-status.sh` where the question actually gets asked |
| **A container branch that looks right and isn't** (`git checkout main`) | 1 | ✅ `ship-to-main` now ships with `git push origin HEAD:main`, which never reads the local ref |
| A hard-coded count in prose going stale | 3+ | ✅ counts removed from `CLAUDE.md` and the skills rather than updated (2026-07-31) |
| A declared weight drifting from the applied one | 2 | ✅ `testContributorWeightsMatchTheWeightsTheScoreApplies`; Sleep's second instance closed by `SleepInsight.Weight` — one table, so the duplicate is impossible rather than tested (2026-08-01) |
| **A before/after comparison whose two sides come from different eras** | 1 | ✅ for the instance — `comparisonWindowDays` (2026-08-02; six years of BP rise read as "+21 mmHg after use"). ⬜ as a category: no mechanical check exists for the next comparison someone writes; the rule is *both sides of a delta share a window* |
| **A new instrument violating a documented trap of the surface it reads, on first use** | 1 | ⬜ open — the card export shipped "none stored yet" over pending replays while `activeContext.md` carried the trap, mechanism and remedy by name. No mechanical check; the rule is *before shipping a reader of X, grep the docs for X's recorded traps* |
| **A rule pointing at a script that isn't there** | 1 | ✅ `handover-check.sh` check 7 |
| **`git add -A` in a canary, then `git reset --hard`** | 1 | ⬜ **open** — see roadmap |
| **The user having to prompt the handover by hand** | 3+ | ✅ trigger widened to intent; checks moved into `verify.sh` (2026-07-31) |
| **A `[~]` half-done marker surviving a push** | 1 | ✅ `verify.sh` fails on any `- [~]` |
| Not stating the open roadmap until asked | 3+ | ✅ `session-start` skill |
| **Pushing without running the gate** | 1 red CI | ✅ `pre-push-gate.sh` hook + a `lint` job in CI, so it holds without the harness. **Hardened 2026-08-02**: the hook was invoked by a relative path and hook processes inherit the shell's *drifted* cwd, so a push issued after a `cd` skipped the gate silently (exit 127 is a non-blocking hook error). Now `$CLAUDE_PROJECT_DIR`-absolute, and `verify.sh` lints settings.json hook commands for relative paths (canaried) |
| A rule referencing a script that is on disk but uncommitted | 1 | ✅ `verify.sh` asks `git ls-files`, not the filesystem |
| A hard-coded count going stale in a doc nobody re-read | 4+ | ✅ counts deleted rather than updated |
| Assert a close-out state instead of checking it | 3 | ✅ `handover-check.sh` (2026-07-31) |
| **Report "deployed" when nothing was installed** | 1 session, 4 times in it | ✅ automated — `deploy.yml` writes `refs/deploy/*`, `scripts/deploy-status.sh` reads it, `CLAUDE.md` and `ship-to-main` now require it |
| **A build that CI can compile and the user's Mac cannot** | 1 | ⚠️ partly — the `.metal` dependency is gone, but the two environments still differ and nothing compares them. See roadmap |
| **`swift test --parallel` exits non-zero with every test passing** | 3 | ✅ automated — `verify.sh` re-runs serially and only forgives a clean log, loudly |
| **A feature that gates work which already ran in the background** | 1 | ⬜ open — no mechanical check; the rule is in `activeContext.md` |
| **Tune a visual against opinion instead of measurement** | 1 (3 rounds) | ⬜ open — the method (measure the reference, iterate) is recorded but not tooled |
| **Assume what data exists by reading the parsers instead of looking at the data** | **3** | ✅ automated — **Settings ▸ Export my data** (2026-08-01, session 13). Fired three times: *"no provider gives us a bedtime"* (session 10 — the field was in every payload, discarded at ingest), *"`dayStrain` is unread because Whoop isn't connected"* (the parser had been emitting it all along; what was missing was a reader), and Oura naps counted as nights. All three were claims about the **code**, stated as claims about the **data**. The export ends the guessing |
| **A protocol member that should be a requirement but sits only in an extension** | 1 | ✅ `testOverridesSurviveExistentialDispatch`. Callers hold `any InsightModel`; extension-only dispatches statically, so every model silently gets the default and the overrides are dead code **whose own tests still pass**, because those hold the concrete type |
| **Reach for the GitHub Actions API to read a build failure** | **2** | ✅ automated — `refs/ci/errors/<sha>` + `scripts/ci-errors.sh` (2026-08-01, session 14). It fired again first, and cost ~40 K tokens across three calls that never reached the error line; the fix was built in the same session and caught the next three red CIs in one line each |
| **Tune a visual by eye instead of measuring the pixel** | **2** | ⬜ **open** — the launch-screen density (session 11, 3 rounds) and the water colour over muscle (session 14, 5 rounds). Both dissolved the moment something was *measured*: ink coverage there, the composited rgb here. No mechanical check exists, and the rule is one line — **read the pixel out of the screenshot before choosing the next colour** |
| **A Swift Charts encoding that only the device can falsify** | **3** | ⬜ open — the `Chart3DContent` overload, the gradient resolving against the mark's bbox rather than the plot area, and `ImagePaint` tiling inside an `AreaMark`. CI proves it compiles and says nothing about what it draws; the app target has no test target and SwiftUI does not exist on Linux |
| **Fit a bound to the one artefact you happened to observe** | 1 | ⬜ open — no mechanical check. The rule: a bound rejects the *impossible*, never the *alarming*. 119 bpm is a real resting heart rate in AF |
| **Order-dependence inside a parse loop** | 1 | ⬜ open — the nap guard fixed duration and left sleep onset poisoned because it sat below the bedtime collection. A test per *consumer* of the loop is what caught it |
| **A card declaring an input and never reading it** | **1 (4 instances)** | ✅ automated — `testEveryDeclaredInputWithDataIsActuallyRead` (2026-08-01, session 17). Invisible rather than wrong, which is why it survived a session that audited every section: `ChartedContributions.resolve` substitutes the declared list *only* when a card reports nothing, so on a card reporting anything at all the input charts nowhere and links nowhere. The invariant's one allowed exception is genuine alternatives, expressed as `MetricType.interchangeableGroups` — two rows of data rather than a per-model exception list |
| **A principle forbidding X used to justify not-Y** | **2** | ⬜ open — *"an invented weight is worse than none"* argued against **inventing** a weight and was used to justify not **attributing** one (session 17); *"that technique has a fatal flaw"* argued against Catmull-Rom and was read as an argument against curvature (session 9). No mechanical check. The rule: **when a principle is doing load-bearing work, check that the thing it forbids is the thing you are declining to do** |
| **A weight, threshold or share written in the card rather than beside the model** | **2** | ✅ partly — Energy's 0.6/0.25/0.15 appeared nowhere in `EnergyModel` and became `Output.terms` (session 17); Sleep still restates nine coefficients twice in one function and is logged as gap 18. The mechanical half exists — `testContributorWeightsMatchTheWeightsTheScoreApplies` — and does not cover a weight that was never *derived* from anything |
| **A nightly figure wrong because same-day sleep samples combine wrongly** | **3** | ⚠️ the *instances* are each fixed and tested — naps averaged into nights (session 13), midnight-crossing nights split in two (session 14), split-night periods averaged to half (session 19, found by the model-internals export's per-source nights table on its first use) — but the category is `bucketStatistic .mean` over `.sleepDurationHours` being wrong whenever one source emits two same-day samples, and nothing lints a *fourth* producer of that shape. The defence that generalises: any parser emitting nightly figures must emit **one sample per night per metric**, which `SleepNights` does by construction and `parseSleep` now does by grouping |
| **A whole-model run inside a SwiftUI `body`, un-memoised** | 1 (5+ instances) | ⚠️ the instances are fixed — `AppModel.memoized(_:_:)` + `LazyVStack` (2026-08-02, session 19; body re-evaluates per scrub/pan, so each was re-running `VitalSignsCheck` et al. over 231k samples per frame-ish) — but no mechanical check exists: a grep-lint for `samples: model.samples` in view files drowns in legitimate cheap calls. The rule: **a full-sample model call in a view goes through `model.memoized`**, and the next slow-card report is the trigger to re-audit |
| Device verification | every | ❌ not automatable — only the user can do it |

## The efficiency roadmap

### ✅ Parse every changed app-target file before pushing — added session 16

`verify.sh` now runs `swiftc -parse` over the app target. SwiftUI does not exist
on Linux so nothing here can *type*-check `HealthInsights/`, and CI has always
been the only gate for it — but parsing needs no SDK, and the brace-balance class
is a real one: session 16 restructured `InsightDetailView` fourteen times, and a
push to discover an unbalanced brace is a five-minute round trip for something a
tenth of a second answers. Caught nothing this session because it was run by hand
each time; it is here so the next session does not have to remember.

### ✅ A `PreToolUse` hook for the shell's working directory — done (session 19)

Built 2026-08-01 with the user's explicit permission ("I am saying yes, do it"),
after six sessions of evidence. `scripts/bash-workdir-hook.sh` is a `PreToolUse`
hook on `Bash` that rewrites every command to `cd <repo root> && <command>` via
`hookSpecificOutput.updatedInput` — session 16's "prepend, don't reject a path
shape" scope, verbatim. A command already anchored to the root passes through
untouched, and a command that deliberately works elsewhere still does: its own
`cd` runs after ours. Proved live in-session: a bare `pwd` after a stray
`cd InsightKit` came back at the repo root.

**The finding that fell out of building it**: hook processes inherit the Bash
tool's *drifted* working directory — the first version invoked itself as
`./scripts/bash-workdir-hook.sh` and died with exit 127 while the shell sat in
`InsightKit`. The bug this hook exists to fix was breaking the hook. Worse, the
**pre-push gate had the same latent hole**: `./scripts/pre-push-gate.sh` in
`settings.json` would silently fail to run (a non-blocking hook error, not a
denial) on any push issued while the shell had drifted — a gate bypass nobody
would see. Both hook invocations are now `"$CLAUDE_PROJECT_DIR/…"`-absolute.
The rule for the next hook: **a hook command in `settings.json` must use an
absolute path, because it inherits exactly the cwd drift the rest of this
entry is about.**

One permission side-effect, handled: Claude Code splits compound commands on
`&&` and checks each part, so the prefix needs its own allow entry —
`Bash(cd /home/user/health-insights-ios)` — and every existing rule keeps
matching its original part.

### ✅ `verify.sh` lints hook commands for relative paths — session 19

The finding above ("hook processes inherit the drifted cwd") made every
relatively-pathed hook a silent no-op waiting to happen, and the pre-push gate
was one. The rule went into `CLAUDE.md`; this is the tier-2 half: `verify.sh`
fails when any `.claude/settings.json` hook command starts with `./` or
`scripts/`, canaried at build time. The category — "a hook that silently does
not run" — is retired for the path-shaped cause; a hook failing for any other
reason still needs the sentinel-file test in the `update-config` procedure.

### ⬜ The next category without a check: same-day sleep emission

Three sessions, three causes, one arithmetic (`bucketStatistic .mean` over two
same-day samples from one source). The instances are fixed; what does not exist
is a check that a *future* sleep producer emits one sample per night per
metric. A property test over the parsers' outputs — "no two `.sleepDurationHours`
samples share a `(day, source)`" — would close the class for every current and
future parser at once. Scoped, not built: it wants a shared fixture set the
parser tests currently don't have.

### The original scoping, kept for the record

**Why this one.** It is the ledger's highest-count row that has a *mechanical*
answer and does not have it yet: **six** sessions, five instances in session 16,
three in session 17 and two-to-three in session 18, and the rule is already written in `CLAUDE.md` in the
plainest words available. Session 15 broke it twice while having read the file
that forbids it; session 16 broke it five times having read the same file *and*
the ledger row about it; session 17 broke it three times having read both **and
written the ledger row that says tier 1 does not hold for this**.

**That last one is the argument, finished.** There is no version of "state the
rule more clearly" left to try. Six sessions is enough evidence.

**Session 16 narrowed the fix.** The mechanism is that the Bash tool's working
directory persists between calls, so a single `cd InsightKit && swift test`
relocates every later relative path — which means the failure is not confined to
`./scripts/…` invocations at all. Two of session 16's five instances were Python
heredocs and one was a `sed`. So the smaller and more complete fix is **prepend a
`cd` to the repo root on every `Bash` call**, not reject a path shape.

That is the whole argument for tier 2, made concretely. This log's own analysis
says it: *a ceremony that depends on being invoked will be skipped*, and the only
real answer to "a rule the model can skip" is something the **harness** runs. The
precedent exists — `scripts/pre-push-gate.sh` is a `PreToolUse` hook on
`Bash(git push*)` that denies the call outright.

**Scope.** A `PreToolUse` hook on `Bash` that inspects the command and denies it
when it invokes `scripts/…` or `./scripts/…`, or `source scripts/…`, without an
absolute path — with a message naming the absolute form so the fix is a copy
rather than a think. Cheap to write, and unlike the rule it replaces it cannot be
forgotten by a fresh context.

**Not built in session 15 on purpose**: it changes `.claude/settings.json`, which
is the user's harness configuration rather than repo code, and it should be their
call rather than something that appears in a docs commit. A future session should
ask before adding it.

**The weaker second candidate**, recorded so it is not re-derived: a watchdog
reconciling deploy runs that finished with no verdict ref, since `if: always()`
cannot cover a runner that stops heartbeating. The *messaging* half was done in
session 15; a real fix would need a scheduled job on GitHub's own runners
reading the deploy runs and writing the missing verdict. Worth it only if the
Mac dying mid-build stops being a one-off.

### ✅ `scripts/ci-errors.sh <sha>` — done (session 14)

Built exactly as scoped below, under the name `ci-errors.sh` writing to
`refs/ci/errors/<sha>`. `ci.yml`'s `app-build` job greps its own log for
`error:` lines and pushes them as a real file with git plumbing; the script
fetches and prints it.

**It paid for itself inside the same session.** The re-derivation that earned it
cost three Actions API calls and ~40 K tokens and never reached the error line —
the bug was eventually found by re-reading the diff. The next three red CIs were
each diagnosed from one line and a few hundred bytes:

```
SleepOnsetStripChart.swift:51:68: error: 'Night' is not a member type of enum 'CircadianConsistencyModel'
BodyCompositionTrendChart.swift:204:45: error: 'EstimatedSpan' is inaccessible due to 'private' protection level
BodyCompositionTrendChart.swift:336:21: error: incorrect argument labels in call (have 'x:yStart:yEnd:stacking:', ...)
```

The original scoping, kept because the argument is the reusable part:

**The candidate session 13 earned.** Its single re-derivation cost a
453,184-character response to answer "which file failed to compile". The
prohibition in `CLAUDE.md` is about reading *status* cheaply — `ci-status.sh`
solved that — and says nothing about reading a *diagnostic*, so there is no
cheap path and the expensive one gets taken.

`ci-status.sh` already proves the mechanism: `ci.yml`'s record-status job pushes
a verdict to `refs/ci/{passed,failed}/<sha>`, and `git ls-remote` reads it for
almost nothing. The same job can write the failing `error:` lines — a few
hundred bytes — to `refs/ci/diag/<sha>`, and `ci-logs.sh` reads them the same
way.

This retires the *category*: every future red CI, not this one. That is the
column the log says matters, and it is the cheapest remaining item on the
ledger that is still open.

Ordered by (frequency × cost), cheapest fix first.

- [x] **A filtered mode for `verify.sh`.** Done the session it was identified:
      `./scripts/verify.sh --tests <pattern>` runs only the matching suites and
      says in its own output that it is **not** the gate. The full suite ran six
      times in the 2026-07-30 session and only the last was load-bearing.
- [x] **State the absolute-path rule where it will be read.** Done — `CLAUDE.md`
      now opens with it. Several shell calls were lost to a working directory
      that had moved, each costing a full round trip.
- [x] **A close-out gate.** `scripts/handover-check.sh` verifies what the
      protocol used to merely assert. Both canaries fire: a log row whose red-CI
      count disagrees with `refs/ci/failed`, and a session that changed Swift
      without touching the docs.
- [x] **Stop carrying counts in prose.** "330 tests" was stale in six files at
      once, "198 types" in two, "seven switches" in three. Updating a count
      guarantees it rots again; the fix taken was to delete it and point at the
      thing that generates it. Keep counts only where they are recomputed —
      `swift test`, `gen-symbol-index.sh`, this log.
- [ ] **Read the composited pixel before choosing the next colour.** Two sessions
      have now burned multiple rounds tuning a visual by eye — launch-screen
      density (11), water-over-muscle (14) — and both collapsed to one step the
      moment something was measured. Session 14 spent four pushes cycling hues
      that were all on the same axis; sampling the screenshot gave
      rgb(126, 88, 121) and named the cause (a suppressed green channel)
      immediately. Not fully automatable — the screenshot arrives from the user —
      but the *first move* on any "that colour is wrong" report should be to read
      the pixel out of the image, and that belongs in a skill beside the
      `add-chart` rules rather than in a session narrative.
- [ ] **Never `git add -A` inside a canary.** A canary that staged everything
      swept an untracked new script into a throwaway commit, and the
      `git reset --hard` that undid the canary deleted the script with it. The
      rules kept pointing at it for three commits. Use `git stash -u`, or commit
      the real work *before* running any canary that resets.
- [x] **A session-start checklist skill.** `.claude/skills/session-start/` —
      bootstrap in the background, read the two audited docs, state the open
      roadmap *unprompted*. Also carries the absolute-path rule and the
      symbol-index reflex, which is where the two remaining re-derivation
      categories were coming from.
- [x] **Make `symbol-index.md` the reflex, not the fallback.** Done as
      `scripts/where.sh <Type>`, which prints `path:line`. Two rounds of prose had
      already failed — the router said "check here before grepping", the
      `session-start` skill repeated it, and a third session still guessed
      `Ingest/` for `Ingestion/` and grepped a path that did not exist. An
      instruction to consult a file loses to a habit; **a command shorter than
      the grep it replaces does not.** `CLAUDE.md`, the `session-start` skill and
      `.claude/settings.json` all point at it now.
- [ ] **Never `git add -A` inside a canary** — carried forward from session 9,
      still the oldest open item. See above.
- [x] **Make "is it on the phone?" answerable.** Done as `refs/deploy/*` plus
      `scripts/deploy-status.sh`. Until this session nothing recorded whether a
      deploy installed anything, `ci-status.sh` was mistaken for an answer, and
      four consecutive failed deploys were reported to the user as successes
      while he sat looking at an hours-old build. The cheapest possible fix —
      one workflow step and one script — for the single most expensive failure
      recorded in this log.
- [ ] **A build-environment parity check between CI and the user's Mac.** The
      top open item, and the one that cost four deploys. `ci.yml` runs on
      GitHub's `macos-15`; `deploy.yml` runs on a Mac whose Xcode components,
      SDK version and installed toolchains nobody has enumerated. A `.metal`
      file compiled on one and not the other, and CI's green tick actively
      misled. Cheapest useful version: a step in `deploy.yml` that prints
      `xcodebuild -version`, the SDK, and `xcrun metal --version` into a ref or
      an artifact, so the difference is *visible* rather than discovered by a
      build failure. A full parity gate is probably not worth it; knowing what
      the other machine actually has is.
- [x] **Make `where.sh` answer for members, not only types.** Done in session 12,
      which lost a round trip guessing that `bucketed` lived in
      `MultiSource.swift` (`MetricAggregator.swift`). The script's own miss
      message said "grep is right for those" — which sends the reader back to
      naming a file, the exact habit the type lookup exists to retire. A reflex
      that only answers one kind of question is not a reflex; it now falls back
      to `git grep` for declarations and only gives up when there is nothing.
- [ ] **A "blocked on a decision" note needs a measurement before it is
      believed.** Twice now a roadmap item has been recorded as needing the user
      to choose between tradeoffs, and twice the tradeoff was an artefact of the
      implementation rather than a fact about the problem — Sleep Regularity's
      "no provider gives us a bedtime" (session 10) and hydration's "whole
      history or a recent window?" (session 12). Each cost the user nothing
      directly, but each parked real work for several sessions behind a question
      that did not need asking. No lint can catch this. The nearest mechanical
      version: when `activeContext.md` says *ask before building*, require the
      note to carry the measurement that establishes the tradeoff is real — and
      treat a missing one as the first thing to go and get.
- [ ] **A guard whose premise is false has now cost five round trips** and is the
      one recurring category with no mechanical check: the `tunnelState` guard,
      the Oura scope skip, a completeness audit dismissed as stale, and this
      session's commit-signing hook. The shape is always "a check reports an
      environmental failure, and the check is what's wrong". A lint cannot see
      this. The nearest thing to a fix is the rule already in `CLAUDE.md`
      — verify the premise against raw tool output before acting on the remedy —
      so this may be a category that stays human. Recorded rather than solved.

## The log

Efficiency is judged **against the previous row**, not against an absolute. Rows
before the protocol existed are marked *not measured* rather than back-filled
with guesses.

| # | Date | Pushes | Red CI | Rework | Re-derivations | Tests | Compounding | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1–8 | to 2026-07-30 | — | — | — | — | 330 → 520 | 5 skills, symbol index, `ci-status.sh`, named-switch lint | *not measured — protocol did not exist* |
| 9 | 2026-07-30/31 | 9 | **1** | 2 | 2 (named below) | 520 → 590 | Generic exhaustive-switch lint; `verify.sh --tests <pattern>`; absolute-path rule; the efficiency protocol itself | **Baseline.** 0.56 waste/push |
| 10 | 2026-07-31 | 1 | **0** | 0 | 1 (named below) | 590 → 602 | `scripts/where.sh`; `ship-to-main` corrected to `git push origin HEAD:main`; roadmap duplicate deleted | **Better in absolutes, and the ratio is not readable at one push.** 2 waste / 1 push |
| 11 | 2026-07-31 | 12 | **1** | 5 | 1 (named below) | 602 → 634 | `refs/deploy/*` + `deploy-status.sh`; `verify.sh` serial-retry and log retention; "a push is not an install" in `CLAUDE.md` + `ship-to-main`; `LaunchNarration` + `LaunchParticleField` tests (22) | **Worse. The most expensive session recorded** — 6 waste / 12 pushes, plus 4 deploys that installed nothing |
| 12 | 2026-07-31 | 1 | **0** | 0 | 1 (named below) | 634 → 644 | `where.sh` answers for members, not just types; `EvaluationMemoTests` (10) pin a cache against its uncached path | **Better, and on every column.** 1 waste / 1 push; green CI and an installed deploy first time |
| 13 | 2026-07-31/08-01 | 8 | **1** | 1 | 1 (named below) | 644 → 672 | **Settings ▸ Export my data** + `DataInventory`; `ContributionRoute` derived from `requirements` rather than a sixth `InsightID` switch; `MetricType.plausibleRange`; `NapContaminationTests` (12), `ContributionRouteTests` (10), `DataInventoryTests` (10); `add-insight` documents `contributions` | **Better — the best waste ratio recorded.** 3 waste / 8 pushes = 0.375, against a 0.56 baseline. The compounding column is the strongest yet: the export found two real defects in production data the first time it was used |
| 14 | 2026-08-01 | 15 | **4** | 8 | 2 (named below) | 672 → 724 | **`refs/ci/errors/<sha>` + `ci-errors.sh`** — the roadmap's top open item; `SleepNights` (14 tests) moves night-grouping into InsightKit; `BodyCompositionSplit` (+29 tests); `DataInventory.SourceStat` per-source attribution; `ScrubIndicator` shared by every chart; rebuild-from-providers | **Worse, and the worst ratio recorded** — 14 waste / 15 pushes = 0.93 against a 0.56 baseline. Four of the eight rework commits are one visual iterated by eye; see below |

| 15 | 2026-08-01 | 3 | **0** | 0 | 2 (named below) | 724 → 772 | **`SectionCaveat` + `InsightSection` with a *required* `caveat` argument** — a section that infers without saying so is now a compile error; `VitalDeparture` gives the vitals scan's z thresholds one implementation, called by both the score and the strip; `PeerStandingModel.Band`; `PeriodContrast.windowDays`; `deploy-status.sh` names the three "no verdict" cases instead of asserting one; `PeerStandingBandTests`, `VitalDepartureTests`, `SectionCaveatTests`, `ContributionSummaryTests` (+48) | **Better on every absolute column** — red CI 4 → 0, rework 8 → 0, waste 14 → 2 — and the first session since 12 to be green on the first push *and* installed. 2 waste / 3 pushes = 0.67 reads above the 0.56 baseline, but the denominator is three. **The honest sting is in the notes: both remaining items are repeats, one for the sixth time** |

| 16 | 2026-08-01 | 12 | **0** | 0 | 1 (named below) | 772 → 833 | **`scripts/card-map.sh`** — derives the card's section order from `InsightDetailView.body`, `--check` wired into `handover-check.sh`, and handover step 5 spells out what a new card versus a new section changes; `SectionPlaceholder` (+24 tests) gives every section a floor-derived empty state; `ChartedContributions` separates a deliberate zero from an absence; `CircadianConsistencyModel` split so a fit can be recomputed per window; `HeartResponseModel` (+8); `LegendCaption` (+13); `PeriodContrast.comparableCount` shares `dailyMeans` with `changes` | **Better on every measured column, and the cheapest long session recorded.** 1 waste / 12 pushes = 0.08 against a 0.56 baseline; twelve installs, zero red CI, zero rework. **The sting is the unmeasured column** — five dead round trips to the shell's working directory, a tier-1 rule now failing in its fourth consecutive session |

| 17 | 2026-08-01 | 4 | **0** | 1 | 0 | 833 → 868 | **`ScoreWeighting` + `ScoreFactor`** — a card states how its number is formed rather than having it inferred from whether its weights are zero; **`ScoreBlend` + `SupportingSignal`** — one place for the two-step arithmetic every card was doing by hand, one constant for the judgement; **`RiskAttribution`** — attribution by *re-running* the published equation rather than decomposing it, so no coefficient is copied; `MetricType.interchangeableGroups`; `ContributorsFixture` shared by two suites; **three invariants that each found real instances while being written** — `testEveryDeclaredInputWithDataIsActuallyRead`, `testEveryScoringCardStatesHowItsNumberIsFormed`, `testAnUnweightedRowAlwaysSaysWhy`; `add-insight` carries all three | **Level with session 16 on the measured columns, slightly worse on rework.** 1 waste / 4 pushes = 0.25 against session 16's 0.08 and a 0.56 baseline; four pushes, four installs, zero red CI. **The one rework is a user-directed reversal, not a defect** — and the unmeasured column is worse than it looks: three more dead round trips to the shell's working directory, a tier-1 rule now failing for the **fifth** consecutive session |

| 18 | 2026-08-01/02 | 7 (10 commits) | **0** | 1 | 1 (named below) | 868 → 902 | **`SampleCacheCodec`** — the cold-launch decode 965 ms → 4–6 ms, with a free one-way migration (the roadmap's named next item, closed); **`CardStateExport`** — the recalibration instrument, whose *first real use found five live miscalibrations*; `SleepInsight.Weight` one-table coefficients (gap 18); `ActivityDoseModel` + `exerciseMinutes` (data-opportunities #1); `sleepLatencyMinutes` via the nap-aware parser (#4); Withings bookkeeping excluded keyed on the typed parser's own map; `effectivePenalties` one pool for the substance dial and its shares; `comparisonWindowDays`, `minimumTrendSpanDays`, `judgementSamples` — each a category guard with a test shaped like the user's data | **Better than baseline, level with 17, behind 16.** 2 waste / 7 pushes = 0.29 against 0.56 baseline (16: 0.08, 17: 0.25). Zero red CI across seven pushes, seven installs. The rework is the sharpest lesson: the new export violated a *documented* trap on its own first use |

| 19 | 2026-08-02 | 6 | **0** | 1 (named below) | 0 | 902 → 914 | **`scripts/bash-workdir-hook.sh`** — the ledger's six-session row, retired by the harness rather than by care, and its construction closed a silent pre-push-gate bypass (hook cwd inheritance) now also linted by `verify.sh`; **refresh coalescing** — concurrent pipelines join the running one; **`ModelInternalsExport`** — the third instrument, which *found a live parser defect on its first output* (Oura split nights); **`AppModel.memoized` + `LazyVStack` + detached export builds + breakdown prewarm + `SyncActivityPill`** — the performance/visibility pass; `VitalSignsCheck.Reading.historyDays`; `SplitNightTests` | **Better, and the first session with zero working-directory round trips after six sessions of them.** 1 waste / 6 pushes ≈ 0.17 against 18's 0.29 (16: 0.08). Zero red CI across six pushes, six installs, zero re-derivations. The rework is small and instructive: the export misquoted the 1.25 threshold as "1.2" — built and fixed the same day, caught by the user's first real export |

### Session 19 notes

**Red CI (0), six pushes, six installs.** Every push green first time. The
`refs/ci/failed` glob for this session's six SHAs returns zero rows.

**Rework (1), named.** `ModelInternalsExport`'s floors line printed
`watchZ = 1.25` as "1.2" — the shared one-decimal formatter applied to a
threshold, in the instrument that exists to quote thresholds. Introduced in
`809ce84`, fixed in `8155740`, found by reading the user's first real export.

**Re-derivations (0).** The audited docs were opened with work: the hook was
built from the roadmap entry's own scoping (prepend, don't reject a path
shape), and the substance/BP investigations started from what
`activeContext.md` already recorded rather than re-establishing it.

**The unmeasured column, finally at zero.** No dead round trips to the shell's
working directory — the first such session since the row was opened. The hook
did it; care did not.

**What made the session cheap where it was cheap.** The instruments did the
finding: the user's screenshots surfaced five display defects in one pass, the
diagnostics log handed over the double-refresh with timestamps attached, and
the model-internals export — built mid-session — caught the split-night parser
defect *in its own first output*, plus settled the two-session-old "is 119
Oura's?" question via the per-source split. Three of the six pushes were
diagnosed almost entirely from artefacts the user could produce themselves.

### Session 18 notes

**Red CI (0), seven pushes, seven installs.** Every push green first time and
every deploy reported `installed`.

**Rework (1).** `d5016b8` fixed, among five things, the pending-replay
blindness that `84df780` had shipped four hours earlier — the card-outputs
export printed "none stored yet" for eight cards whose replays were still
queued. Four of the five fixes in that commit repaired defects *older* than the
session and are shipped work, not rework; this one clause is the rework, and it
is the instructive kind — see the re-derivation below.

**Re-derivations (1), named.** *"A pending replay is not no-data"* is in
`docs/activeContext.md` under the card-consistency session, with the exact
mechanism (`scoreHistory` returns `[]` on first ask) and the exact remedy
(`scoreHistoryIsPending(for:)`). The export was built without consulting it and
the rule was re-learnt from the user's shared document. **A new instrument
should be checked against the recorded traps of the surfaces it reads** — the
trap list existed; nothing prompted the reading of it.

**The unmeasured column, sixth consecutive session.** Two-to-three dead round
trips to the shell's working directory (`./scripts/where.sh` from the
scratchpad, a relative `sed` from `InsightKit/`, `swift` not on PATH after a
fresh call). The ledger row moves to 6; the `PreToolUse` hook remains the top
roadmap item and still needs the user's permission, now with six sessions of
evidence behind the ask.

**What made the session cheap where it was cheap.** The audited docs were
trusted and opened with work (the decode item and gap 18 were both taken
straight from them); `data-opportunities.md` turned "look for high-value
improvements" into a ranked list with the scoring bases pre-researched, so two
new metrics landed through the skills with zero missed switches; and the
session's own new instrument paid for itself before it was a day old — the
user's first export produced five fixes, four of them for defects that predate
the session and that no test could have found without the shipped numbers.

### Session 17 notes

**Red CI (0), four pushes, four installs.** Every push green first time and
reported `installed`.

**Rework (1), and it is worth being precise about what kind.** `3f74f06`
replaced the weight-0 handling that `bff6390` had shipped four hours earlier —
**a reversal the user directed after reading the result on the phone**, not a
defect fix. It still counts: five cards' contributor logic was built twice.

The interesting question is whether asking first would have avoided it. It was
asked — an `AskUserQuestion` offered exactly this option ("give them scores
too") and it was declined, and then chosen once the shipped version was visible.
**So the question was answered better by the artefact than by the question**,
which is a real finding about this repo's loop rather than an excuse: the user
reviews every build on the phone within minutes, and for a *what should this
section contain* decision that is a cheaper oracle than a multiple-choice
prompt. It is not a general licence — the same reasoning would be wrong for
anything expensive to undo.

**Re-derivations (0).** The audited docs were read once at the start and
trusted; `where.sh` answered eight lookups including two member-level ones
(`resolvedContributions`, `sharesMeasurementBasis`) with no filename guess.

**The honest failure, again: three dead round trips to the working directory.**
`source scripts/swift-env.sh` once, `./scripts/verify.sh` once, and a Python
heredoc opening a relative path once — each after a `cd InsightKit` in an
earlier call. Not a re-derivation and not rework, so it appears in no column.

**This is the fifth consecutive session.** Sessions 14 (1), 15 (2), 16 (5), 17
(3). The rule has been in `CLAUDE.md` in the plainest available wording since
session 9, annotated "pure waste", and the ledger row about it has been read by
every session that then broke it. The log's own thesis is unambiguous — *a
ceremony that depends on being invoked will be skipped*, and *a rule the model
can skip is tier 1, and tier 1 does not hold*. **The mechanical fix has sat in
the roadmap unbuilt for three sessions for one reason: it edits
`.claude/settings.json`, which is the user's harness config.** Asked again at
the end of this session's handover.

**Why the compounding column is the strongest part.** Three of the four new
types are ordinary plumbing; the three new *invariants* are the session's real
output, and each found something while being written rather than after:

1. `testEveryDeclaredInputWithDataIsActuallyRead` caught Energy still not
   charting heart rate after the fix that was supposed to fix it.
2. `testAnUnweightedRowAlwaysSaysWhy` caught three bare zeroes on the risk card
   — a non-smoker, no diabetes, and a systolic already better than optimal, all
   rendering as `0%` with no explanation.
3. `testEveryScoringCardStatesHowItsNumberIsFormed` is what makes
   `ScoreWeighting`'s silent `.unstated` default safe to have.

**`RiskAttribution` is the decision most worth carrying.** Attributing a
published equation's output could have been done by decomposing its linear
predictor — every coefficient is in `CardiovascularRiskModel`, twenty lines
away. That would have been **a second copy of every SCORE2 and ASCVD
coefficient**, which is the `PressureBandTests` defect one level up. Re-running
`HeartAgeModel.riskPercent` with one factor held at optimal gives the same
attribution and knows no coefficient at all. Generalises: **when you need to
attribute a model's output, look for a re-run you can do rather than a
decomposition you have to write.**

**A doc contradicting itself, caught by step 12 rather than by a reader.**
`card-sections.md` and `activeContext.md` both described Fitness and Body
Composition as `ScoreWeighting.singleMeasure` in one paragraph and
`weightedAverage` in a table further down — true for the length of one commit,
stale by the end of the same day. Third time this file has disagreed with itself
inside one session. The polarity that goes stale is always the same one: a claim
about what a card *is*, invalidated by later work in the same session.

### Session 16 notes

**Red CI (0) and rework (0), across twelve pushes.** Every push was green first
time and every one reported `installed`. Three things did that, and none is
carefulness:

1. **`swiftc -parse` on every changed app-target file before pushing.** SwiftUI
   does not exist on Linux so the app target cannot be *type*-checked here, but
   parsing catches the brace-balance class — and this session restructured
   `InsightDetailView` fourteen times. Worth adding to `verify.sh`; see the
   roadmap.
2. **Refusing type-inference gambles in a target only CI compiles.**
   `placeholder.map { .collapsed(…) } ?? .always` leans on leading-dot inference
   flowing back through `map` and `??`; it was replaced with an explicit helper
   at four call sites, and `SectionCaveat.none` was written out longhand in every
   ternary rather than left as `.none`. Each would have cost a push to settle.
3. **Two throwaway probes instead of two arguments.** "Score over time has been
   removed from most cards" was a report about a section this session had not
   touched. A twenty-line test replaying all nine models found the real answer —
   **four cards produce zero score-history points** — in one round trip, and the
   same trick found that only four of nine cards have any weighted contributors
   at all. Both probes were deleted after reading.

**Re-derivation (1), named.** `VitalReader.DailyPoint` — invented a type name,
`where.sh` correctly reported no such thing, and the answer was `DailyValue`.
One round trip. The tool worked; the guess came first, which is the ledger's
"hunt for a type by guessing its name" one level down.

**The honest failure: five dead round trips to the working directory.** Not a
re-derivation and not rework, so it appears in no column above — which is
exactly why it is written here. `cd InsightKit && swift test` leaves the shell
in `InsightKit`, and the Bash tool's cwd **persists between calls**, so the next
`./scripts/verify.sh` resolves to nothing. It happened five times: `verify.sh`
once, `where.sh` once, a `sed` once and two Python heredocs.

The rule is in `CLAUDE.md` in the plainest wording available, annotated "pure
waste", and this is its **fourth consecutive session** of not holding. The log's
own thesis covers this case explicitly — *a rule the model can skip is tier 1,
and tier 1 does not hold* — and the mechanical answer has been sitting in the
roadmap unbuilt for two sessions because it changes `.claude/settings.json`.
**That is the thing to ask the user for.** Session 16 at least narrows it: the
smaller fix is not "reject relative `scripts/…` calls" but "prepend a `cd` to the
repo root on every `Bash` call", which fixes the heredocs and the `sed` too.

**What the compounding column is really worth this time.** `card-map.sh` retires
a category that had recurred twice in three sessions: the session that changes a
card section updates the code and half the record. It is deliberately a *failing*
check rather than a self-healing formatter, because only the ordering can be
generated — the matrix, the gate table and the two feature audits beside it are
hand-written and a moved section changes all four. A formatter would have made
the document quietly wrong instead of loudly stale.

**What made this session cheap.** The user reviewed twelve builds on the phone as
they landed, so eight defects were found by the only gate that can see them
rather than by a later session; the audited docs were read once at the start and
trusted; and `deploy-status.sh` meant "installed" was reported twelve times from
a ref rather than from optimism.

### Session 15 notes

**Red CI (0). Rework (0).** Nothing pushed needed fixing, on a session that
shipped 24 files and five new card sections. What made that possible is worth
naming, because it is the reusable half: the whole InsightKit layer — four new
types and 48 tests — was built and run locally before a line of the app target
was touched, so every logic error was found by `swift test` rather than by CI.
The app target still cannot be compiled here, and the three defects that *would*
have broken it (`ClosedRange<Int>` against a `Double` chart domain, a method
shadowed by a `ForEach` binding, and a trailing label reading "to at 79") were
caught by re-reading the diff against the `add-chart` checklist rather than by a
round trip.

**Re-derivations (2), named. Both are repeats, which is the finding.**

1. **Relative `scripts/swift-env.sh`, twice** — two dead round trips returning
   `No such file or directory`. `CLAUDE.md` ▸ "Shell calls: absolute paths,
   always" says exactly this and already annotates it "pure waste". Third
   session. The rule is tier 1 and tier 1 is not holding — see the roadmap.
2. **The deploy diagnosis was asserted before it was checked.** The user was
   told the missing verdict "looks like the job queueing against an offline Mac
   rather than a build failure". It was not: the Mac had claimed the job and
   died ten minutes into the Xcode build. Sixth instance of the logged
   false-premise category, and the sixth time it arrived wearing a different
   costume.

**`if: always()` does not always run, and that is a real blind spot.**

The reasoning behind the wrong answer above was superficially sound:
`deploy.yml`'s final step writes `refs/deploy/{passed,failed}/<sha>` under
`if: always()`, so "no ref at all" ought to mean "the job never started". What
actually happened is the third case nobody had written down — the runner claimed
the job, cleared checkout, team-ID resolution, keychain unlock and the build
stamp, then stopped heartbeating mid-build. GitHub concluded the job `failure`
with the build step still `in_progress` and the verdict step never reached. **A
runner that dies cannot execute `always()`**, so the verdict-ref mechanism has a
state in which it records nothing at all.

`deploy-status.sh` now prints all three cases and the tell for each —
`runner_name: ""` on a queued job means nobody claimed it; a step stuck
`in_progress` under a `failure` conclusion means the runner died holding it —
plus the cheap way to read them. That last part matters on its own: the MCP
Actions tool **spills an oversized result to a file rather than returning it**,
so `python3` over that file answers the question for a few hundred bytes. The
standing "never use the Actions API" rule is about reading the *response*; it
was being read as "this question cannot be answered cheaply", and it can.

**What made this session cheap.** The two audited docs were trusted rather than
re-established, so it opened by stating the roadmap instead of surveying the
code. `docs/card-sections.md` supplied the section inventory. `where.sh` found
`PeerStandingModel`, `VitalSignsCheck` and `VO2Trajectory` without a filename
guess. And the `add-chart` skill's §7 supplied the `AreaMark(x:yStart:yEnd:)`
"takes no `stacking:`" rule at the moment the projection chart needed it, which
is a compile error that cost session 14 a full CI cycle to discover.

**One thing the audit caught that a handover had already missed.**
`docs/card-sections.md` contradicted itself: line 68 said "the bespoke slot
reaches six" while line 150 in the same file said all nine cards now have one.
Both were written in the same session and only one was updated. Protocol step 11
exists for exactly this and it is the step that keeps getting skipped — the
second polarity, *claims that something is missing*, is the one that goes stale
when work lands.

### Session 14 notes

**Red CI (4), all in the app target, none catchable locally.** `4ba0c91` and
`e9188c2` (the same break: `Night` is nested in `Output`, misdiagnosed once as a
`ChartContent` conformance problem), `ff0a612` (a `private` nested type extended
from file scope), `ac2c62a` (`AreaMark(x:yStart:yEnd:)` takes no `stacking:`).
Every one is a signature-level error in SwiftUI/Charts code that InsightKit's
suite cannot reach, because SwiftUI does not exist on Linux. `verify.sh` was
green before all four.

**Rework (8).** Four are the compile fixes above. **Four are the same visual:**
the water colour over the muscle band, revised at `b902dbe`, `ac2c62a`,
`75e02d1` and `df5140a` after `8b013f9` introduced it. That is the headline
waste of the session and it was self-inflicted — see below.

**Re-derivations (2), named.**
1. **Reached for the GitHub Actions API to read a build failure.**
   `CLAUDE.md` says "Never use the GitHub Actions API for this; its smallest
   response is over 100 K tokens", and this log's own roadmap already carried
   `ci-logs.sh` as the top open item *with the fix specified*. Three calls, one
   453 KB response, ~40 K tokens, and the error line never appeared — the bug was
   found by re-reading the diff instead. The prohibition was read as covering
   *status* only, which is exactly the gap the roadmap item described.
2. **Lost the working directory in a shell call.** `cd InsightKit` persisted into
   a later call and `ls InsightKit/` failed. Ruled in `CLAUDE.md` on 2026-07-31
   ("absolute paths, always") and listed in the ledger as a two-session repeat;
   this is the third.

**Why it got worse, in one sentence.** Five attempts at one colour, because each
one picked a new hue or opacity *by eye* instead of measuring what the composite
actually was — and when it was finally measured, rgb(126, 88, 121) named the
cause (red and blue near-equal, green suppressed) in a single step, after which
the answer was structural rather than chromatic: a hatch never mixes, so it
cannot go purple.

**The generalisable half.** A translucent overlay of blue on red *is* purple —
colour arithmetic, not a tuning problem. Four rounds were spent looking for a
ratio that does not exist. When a visual fix keeps landing in the same wrong
place, check whether the mechanism can produce the target at all before choosing
another value for it.

**What made this session expensive is also what it automated.** The single most
costly item — reading a red CI — is now a git ref and a script, and it was
exercised three times in the same session it was built. Against that: three
Swift Charts behaviours were discovered on the device rather than in a test, and
that category has no mechanical answer while the app target has no test target.
### Session 13 notes

Three asks in one session: audit which sections every card renders, then make
them consistent, then consolidate seventeen cards into nine — plus a data export
that immediately paid for itself.

**The one red CI** (`553e33f`): `isUnmet ? Theme.accent : .tertiary`. `Color`
has static `primary`, `secondary` and `white` — which is why the twelve other
colour ternaries in the app target compile — but **no `tertiary`**, so the two
arms had no common type. Nothing local catches this class: SwiftUI does not
exist on Linux, so CI alone compiles the app target. Fixed by `42efe4c`, which
is also the session's single rework commit.

**The one re-derivation, named**: I called `mcp__github__actions_list` to find
the failed run and got a **453,184-character** response.
`CLAUDE.md` ▸ Primary Verification Commands already says *"Never use the GitHub
Actions API for this; its smallest response is over 100K tokens"*, and
`ci-status.sh` repeats it in its own header. It did not fire because the rule is
about reading *status* and I wanted *logs* — which is precisely the gap, and is
now a roadmap item.

**Near-misses, not counted** (the protocol counts rework *commits*, and all
three were caught before landing) — recorded because each is a category:

- The nap guard was first placed *below* the bedtime collection, so it fixed
  sleep duration and left naps still poisoning sleep onset. **Order inside a
  parse loop is load-bearing.**
- A test asserted the sanitizer rejects 119 bpm. It should not: 119 is a real
  resting heart rate in atrial fibrillation, and the ceiling would have been
  fitted to one user's bad record. **A bound rejects the impossible, never the
  alarming.**
- `VitalReader`'s API shape was guessed (`VitalReader(samples:now:)`) rather than
  read; it is a static enum. `where.sh` answered it in one call afterwards.

**What made this session cheap despite its size.** Eight pushes, one red. The
consolidation touched 55 Swift files and thirteen test files and went green
first time, because the *old tests were repointed rather than deleted* — and
they caught four real regressions the merge would otherwise have shipped
silently: weight-0 contributions counting toward "is this day well-founded" in
`ScoreHistory`, the vitals panel dropping off the overlay chart, an
irregular-rhythm flag no longer outranking an ordinary day, and "we couldn't
judge this vital" being folded in with the normal ones. A fifth — Sleep's
regularity term computing against the real present instead of the `now` it was
handed — was caught by the contributor-weight invariant from session 11.

**The compounding item that matters.** Settings ▸ Export my data was built for
one reason: nobody working on this app can see the user's data, so every "what
signals do we have?" question had been answered by reading the parsers. On first
use it found that Oura naps were being counted as nights — a defect no code
review would have found, because nothing in the parser looks wrong and every
test passed. What gave it away was a median sleep of 5.62 h with a minimum of
0.01 h. That failure has now fired three times (see the ledger); the export
retires the category.

### Session 12 notes

**Red CI (0), rework (0), one push, installed first time.** The gate ran before
the push and CI agreed with it, which is the mechanism working rather than luck.

**The substantive result: a "needs a decision from the user" item did not.**
`activeContext.md` had hydration parked behind a question — read the whole
history on a cold launch, or a recent window with the rest behind Today? — on the
premise that every cheap fix changes what the first frame knows. Benchmarking it
before asking showed the cost was not volume at all but repetition:
`MultiSource.breakdown` and `Array.samples(of:)` each filtered and sorted the
whole ~130k-sample history *per metric per model*, and resting heart rate is read
by seven of the seventeen. `evaluateAll` 1774 → 476 ms, hydration block
2796 → 1564 ms, no change to what any frame knows.

**This is the second time an item was parked behind a tradeoff that wasn't
real** — "no provider gives us a bedtime" was the first. Both are now a ledger
row and a roadmap item: when a note says *ask before building*, the note should
carry the measurement proving the tradeoff exists.

**Re-derivations (1), named.** Guessed that `bucketed` lived in
`MultiSource.swift` and grepped it; it is in `MetricAggregator.swift`. One dead
round trip. `where.sh` could not have answered — it indexed only top-level types
and its miss message explicitly sent the reader to grep. That is the failure the
type lookup was built to retire, one level down, so the fix taken was the
category one: `where.sh` now falls back to member declarations.

**One avoidable full-suite run.** Five full runs (three `verify.sh --tests`, two
bare `swift test` for counts). `--filter` was used correctly for the new test
file; the run straight after it was redundant with the pre-push gate that
followed. Small, but it is the same shape as session 9's six runs and worth not
letting drift back.

**What made it cheap.** The `session-start` skill opened with the roadmap and the
gate rather than a survey; `where.sh` was used for nine lookups and only failed
on the one kind it did not cover; and the two audited docs were trusted, which is
what left budget for a benchmark. The benchmark itself is the transferable part —
the before/after was taken with the *same* harness either side by stashing the
change, rather than comparing two differently-generated runs, which is the only
reason the 3.7× is quotable.

**Not device-verified.** The numbers are an x86 Linux benchmark of the same code
paths, not a measurement on the phone. Ratios travel; absolutes do not.

### Session 11 notes

**The headline is not in the table.** Four deploys in a row installed nothing
and were reported to the user as successes. He spent an hour on an hours-old
build, asked twice where his app was, and was right both times. No column
counted that, because until this session nothing in the repository recorded
whether a deploy reached the phone. That is now `refs/deploy/*` and
`deploy-status.sh`, and it is the single most valuable thing this session
produced.

The mechanism of the error is worth stating precisely, because the pieces all
looked correct: `ci.yml` runs on GitHub's runners and writes `refs/ci/*`;
`ci-status.sh` reads it cheaply; `CLAUDE.md` said, in as many words, to announce
deployment once the push landed. So the instruction, the available signal and
the claim all lined up behind a question none of them was asking. **A green tick
that answers a different question is worse than no tick.**

**Red CI (1).** `047342b` — two `DiagnosticsLog` calls (`@MainActor`) from
MTKView's renderer (not). An error even in Swift 5 mode, so the app target would
not compile. Cost: one CI cycle, one deploy cycle, one fix commit. Entirely
avoidable: **I pushed it without waiting for `ci-status.sh`**, and CI is the only
thing in this sandbox that compiles the app target at all.

**Rework (5) — the worst figure in this log.**
1. `671c752` fixes `7f53f43`: the launch screen gated the whole refresh, turning
   an ~8 s launch into ~32 s. Found by the user, on the phone.
2. `047342b` fixes `ae7c03a`: the `.metal` file broke the user's Mac build.
3. `4084f03` fixes `047342b`: the isolation error above.
4. `9991731` fixes `ae7c03a` and `7f53f43`: density, colour, and the 3× launch
   image flash.
5. `5addcdf` fixes `9991731`: the status line was still unreadable — the first
   attempt corrected its colour but not its position, and it was sitting in 37%
   ink.

Four of the five were found by the user looking at his phone. **CI was green for
every one of them.** That is not a CI failure; it is the shape of this project —
the app target has no test target and the only real gate is a device.

**Re-derivations (1), named.** The commit-signing stop hook. `activeContext.md`
▸ "Two container traps" item 2 already recorded it in full — identity already
correct, key file zero bytes, all of `origin/main` unsigned — and it was
re-verified from raw output anyway at the start of the session. Defensible under
the repo's own "verify the guard's premise" rule, but it is still a fact the
docs held being established a sixth time. The user then asked for the subject to
be dropped entirely; both the skill and the audit are now two lines saying
"closed, do not re-derive".

**Two agent workflows were launched and neither was used.** One ran ~70 minutes.
Both problems they were investigating had already been diagnosed by hand — by
reading the code and frame-differencing the user's screen recording — and fixed
before either finished. The user noticed the spend and was right to. Nothing in
the repo prevents this; the rule is simply *don't start a fan-out for a question
you are already answering*.

**What made the session expensive, in one line:** three of the four rounds were
spent discovering that a thing which passed every check available in the sandbox
did not work on the only machine that matters.

**What made it cheap where it was cheap.** The `session-start` skill opened with
the roadmap instead of a survey. `where.sh` was used instead of guessing a
directory — the three-session repeat did not recur. The
`ScoreHistory.replay` optimisation (O(days×n) → one pass) shipped with an
equivalence test against a naive reference rather than a hope, and the launch
copy, the point cloud and the replay all landed with tests that run on Linux —
32 new tests, which is why none of the five reworks were *logic* errors.

### Session 10 notes

**Red CI (0).** One push, green first time. The pre-push hook ran the full gate
before it left, which is the mechanism working as designed rather than luck.

**Rework (0 commits).** One commit, nothing fixing anything from earlier in the
session.

**Re-derivations (1), named.** Searched for `.sleepOnset`'s promotion rules and
the Sleep Regularity insight by guessing directory names — `Ingest/` for
`Ingestion/` — and grepping paths that do not exist. Two empty greps before
consulting `docs/symbol-index.md`, which the memory router already said to check
first. **This is the third session running with exactly this failure**, and it is
what `scripts/where.sh` exists to retire.

**A misstep that cost a round trip but is not rework.** `git checkout main`
followed by `git merge --ff-only`, which refused with "unrelated histories" and
silently swapped the working tree to a months-old snapshot. The cause was a
container artefact rather than a mistake in reasoning — but the *approach* was
mine, and the correct one (`git push origin HEAD:main`) touches no local branch
at all. Counted in the waste figure above; retired as a category in the
`ship-to-main` skill.

**On the ratio.** 2 waste over 1 push reads as worse than session 9's 0.56, and
that comparison should not be trusted: at one push the denominator is noise, and
the absolute waste fell from 5 to 2 with red CI going 1 → 0. The honest summary
is a cheap session with one repeat of a long-logged failure mode — which is
precisely the thing that got automated rather than noted.

**What made it cheap.** The two audited docs were trusted rather than
re-established, so the session opened by stating the roadmap instead of surveying
the code; the `add-chart` skill supplied the `Chart3DContent`, dash-means-inferred
and `AreaMark`-hazard rules without a re-read of the chart history; and reading
`IngestionPipeline` *before* writing the obvious one-line version of the
promotion item is the only reason that item is not now a silently dead alias row.

### Session 9 notes

**Red CI (1).** `34c03a6` — added a `Suggestion.Basis` case and missed a switch
in `InsightsListView` that no lint mentioned. Cost: one CI cycle plus a fix
commit. *Retired as a category* by the generic switch lint.

**Rework (2).** The CI fix above, and `48ae69c` — curving the metric-detail
chart's gap bridges while leaving the overlay's straight, which recreated in one
commit the exact "same silence, two renderings" defect the file's own history is
about. Cost: one extra commit and CI cycle. Preventable by asking "which *other*
chart draws this?" before committing a rendering change.

**Re-derivations (2), named.**
1. Searched for `SeriesBridging` by filename, found nothing, then grepped —
   `docs/symbol-index.md` had it under `SeriesSegmentation.swift` and the memory
   router already says to check the index first.
2. Ran `./scripts/verify.sh --tests` six times when the InsightKit-only work
   needed `swift test --filter` and one full run before pushing.

**A third rework, and the worst of the session.** `scripts/handover-check.sh`
was written, run, canaried — and then destroyed by a *different* canary, whose
`git add -A` swept the still-untracked file into a throwaway commit that
`git reset --hard` then discarded. `CLAUDE.md` and the handover command were
committed pointing at a file that was no longer in the tree.

The instructive part is not the git accident. A completeness audit **reported
the script missing**, and the report was dismissed as stale on the grounds that
the script had just been written — the same "answer from memory rather than
check" failure as the `tunnelState` guard and the Oura scope guess, now four
instances. Check 7 of the gate closes the mechanical half: any `./scripts/*.sh`
named in `CLAUDE.md`, the handover command or a skill must exist and be
executable.

**What made this session cheap where it was cheap.** The two audited docs were
trusted rather than re-established, which is what let the session open with work
instead of a survey; `ci-status.sh` kept eight CI checks at a few hundred bytes
each instead of ~450 KB per call; and the skills carried the `MetricType` and
`InsightID` checklists so four new metrics and one new insight landed without a
single missed switch — the one break was over an enum no skill covers, which is
precisely the gap now linted.
