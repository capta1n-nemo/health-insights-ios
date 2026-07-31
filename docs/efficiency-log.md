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
| Lose the working directory in a shell call | 2 | ✅ ruled in `CLAUDE.md` (2026-07-31) |
| Re-run the full test suite more than needed | 2 | ✅ `verify.sh --tests <pattern>` (2026-07-31) |
| Hunt for a type by guessing its filename | **3** | ✅ automated — `scripts/where.sh <Type>` (2026-07-31). Two rounds of prose failed; the fix is a command shorter than the grep |
| **A guard reporting a failure whose own premise is false** | **5** | ⚠️ partly — ruled in `CLAUDE.md` and named five times in `activeContext.md`; no mechanical check exists and it is unclear one can |
| **A container branch that looks right and isn't** (`git checkout main`) | 1 | ✅ `ship-to-main` now ships with `git push origin HEAD:main`, which never reads the local ref |
| A hard-coded count in prose going stale | 3+ | ✅ counts removed from `CLAUDE.md` and the skills rather than updated (2026-07-31) |
| A declared weight drifting from the applied one | 1 | ✅ `testContributorWeightsMatchTheWeightsTheScoreApplies` |
| **A rule pointing at a script that isn't there** | 1 | ✅ `handover-check.sh` check 7 |
| **`git add -A` in a canary, then `git reset --hard`** | 1 | ⬜ **open** — see roadmap |
| **The user having to prompt the handover by hand** | 3+ | ✅ trigger widened to intent; checks moved into `verify.sh` (2026-07-31) |
| **A `[~]` half-done marker surviving a push** | 1 | ✅ `verify.sh` fails on any `- [~]` |
| Not stating the open roadmap until asked | 3+ | ✅ `session-start` skill |
| **Pushing without running the gate** | 1 red CI | ✅ `pre-push-gate.sh` hook + a `lint` job in CI, so it holds without the harness |
| A rule referencing a script that is on disk but uncommitted | 1 | ✅ `verify.sh` asks `git ls-files`, not the filesystem |
| A hard-coded count going stale in a doc nobody re-read | 4+ | ✅ counts deleted rather than updated |
| Assert a close-out state instead of checking it | 3 | ✅ `handover-check.sh` (2026-07-31) |
| Device verification | every | ❌ not automatable — only the user can do it |

## The efficiency roadmap

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
