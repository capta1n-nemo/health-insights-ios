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
| Hunt for a type by guessing its filename | 2 | ⚠️ partly — `symbol-index.md` exists and was not consulted first |
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
- [ ] **Make `symbol-index.md` the reflex, not the fallback.** The router already
      says "check here before grepping". It was still skipped. Consider having
      `verify.sh` print a one-line reminder, or fold the index into the skills
      that most often precede a hunt.
- [ ] **A session-start checklist skill** that front-loads the three things every
      session does (bootstrap, read the two docs, check the roadmap) so they
      happen in one pass rather than being rediscovered.

## The log

Efficiency is judged **against the previous row**, not against an absolute. Rows
before the protocol existed are marked *not measured* rather than back-filled
with guesses.

| # | Date | Pushes | Red CI | Rework | Re-derivations | Tests | Compounding | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1–8 | to 2026-07-30 | — | — | — | — | 330 → 520 | 5 skills, symbol index, `ci-status.sh`, named-switch lint | *not measured — protocol did not exist* |
| 9 | 2026-07-30/31 | 8 | **1** | 2 | 2 (named below) | 520 → 590 | Generic exhaustive-switch lint; `verify.sh --tests <pattern>`; absolute-path rule; the efficiency protocol itself | **Baseline.** 0.63 waste/push |

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

**What made this session cheap where it was cheap.** The two audited docs were
trusted rather than re-established, which is what let the session open with work
instead of a survey; `ci-status.sh` kept eight CI checks at a few hundred bytes
each instead of ~450 KB per call; and the skills carried the `MetricType` and
`InsightID` checklists so four new metrics and one new insight landed without a
single missed switch — the one break was over an enum no skill covers, which is
precisely the gap now linted.
