# Setup review — 2026-08-06

A full audit of the chat-to-chat machinery: CLAUDE.md, the nine skills,
`.claude/commands/handover.md`, the hooks in `.claude/settings.json`, every
script under `scripts/`, and the docs router. Scope was the five questions that
decide whether a fresh session starts cheap: contradictions between instruction
sources, staleness, missing automation, onboarding cost, and the gap between
what the handover protocol claims and what `handover-check.sh` checks.

Findings marked **applied** were fixed in this review's own commit. Everything
else has a one-sentence fix and is ranked.

---

## Fix these 5 first

1. **The workdir hook broke worktree-isolated agents — applied, but it must
   reach `main` to take effect.** `scripts/bash-workdir-hook.sh` anchored every
   shell call to `$CLAUDE_PROJECT_DIR`, which for an agent under
   `.claude/worktrees/<name>` is the *main* working copy — so a worktree
   agent's relative paths silently read and wrote the main tree (six live
   branches there), and the harness's isolation guard refused **every** `git`
   command the agent issued, because the rewrite reads as git targeting a tree
   outside its worktree. Verified live in this session: plain `git status` was
   refused three different ways. Fix (applied): the hook now reads the payload's
   own `cwd` and anchors to the worktree root when it sits under
   `.claude/worktrees/`; canaried with seven synthetic payloads, all passing.
   Note the live hook is the *main* repo's copy — until this commit lands on
   `main`, every worktree agent stays in that state.

2. **Session-start reading cost is dominated by one file that never sheds
   weight.** `docs/activeContext.md` is 4,135 lines across 28 sessions of
   narrative, and both CLAUDE.md and the `session-start` skill direct every
   session to read it (plus `docs/progress.md` at 2,516 lines, though that one
   opens with the generated table). Superseded narratives — e.g. "### The gate
   lied, Fixed 2026-08-02", long-closed session write-ups — are re-read every
   single session. Fix: at each handover, move superseded sections to
   `docs/archive/activeContext-history.md` (move, never delete); the
   instruction is now step 2 of `.claude/commands/handover.md` (**applied**),
   but the first actual pruning must happen in a main session, since this
   review was barred from touching `activeContext.md`.

3. **Hard counts in always-loaded prose had rotted again, in four places at
   once — applied.** CLAUDE.md said `add-metric-type` covers "eight exhaustive
   switches" while the skill's own table holds nine (`dataCategory` was added
   without the count moving); CLAUDE.md and `add-insight`'s frontmatter said
   "five `InsightID` switches" while the skill's table holds six and its own
   body says "this table said five until 2026-08-03"; `verify-before-push`
   named only seven of the nine metric switches; `bootstrap-swift.sh`'s header
   still claimed "330 tests" (CLAUDE.md itself warns that count moved 330→590);
   `verify.sh`'s comment said "four of the five InsightID switches". This is
   ledger row "a hard-coded count in prose going stale" (5+ sessions). Fix
   (applied): counts removed rather than corrected, per the ledger's own rule,
   with a one-line reason left at each site so the next writer doesn't
   reintroduce one.

4. **`.claude/settings.json:24` allows the hook's `cd` prefix only for the
   Linux container path.** The entry is `"Bash(cd /home/user/health-insights-ios)"`;
   on the user's Mac the hook prepends `cd "/Users/…/HealthAppLocal/health-insights-ios"`,
   and after the worktree fix, `cd "…/.claude/worktrees/<name>"` — neither has
   an allow entry, so compound commands can prompt where the container never
   did. Fix (not applied — settings.json was outside this review's edit
   permit): add the Mac repo path and a worktree-prefix allow entry alongside
   the Linux one.

5. **The top unautomated repeats in the ledger still have no mechanical fix,
   and the top one already has a written spec.** In cost order from
   `docs/efficiency-log.md` (ledger + roadmap): `scripts/card-dump.sh` (two
   sessions spent ~10 build-launch-navigate-screenshot cycles each to read one
   number a model already had — roadmap entry exists with a spec, session 28);
   a stale-count lint for reader-facing copy (ledger says "a lint is possible
   here" — a card's copy must not contain a number word that is also a
   collection count); a second CI run under a non-UTC `TZ` (the timezone
   category is open, three tests were wrong in both directions); and
   `scripts/pixel.sh <png> <x> <y>` (two visual-tuning episodes, eight rounds
   total, both collapsed the moment a pixel was measured). Fix: build
   `card-dump.sh` next per its existing spec; the other three are one small
   script or CI-job each.

---

## Applied in this commit

- `scripts/bash-workdir-hook.sh` — worktree-aware anchoring (finding 1), with
  a seven-case synthetic-payload canary run before committing.
- `.claude/commands/handover.md` — step 2 now instructs pruning
  `activeContext.md` into `docs/archive/activeContext-history.md` (finding 2).
- CLAUDE.md — hook section rewritten to name `$CLAUDE_PROJECT_DIR` instead of
  the hard-coded Linux path and to state the worktree behaviour; both stale
  skill-router counts removed (finding 3); router entries added for
  `docs/data-opportunities.md` and `docs/research-notes.md` (finding 8).
- `.claude/skills/add-metric-type/SKILL.md`, `.claude/skills/add-insight/SKILL.md`,
  `.claude/skills/add-data-or-input/SKILL.md`, `.claude/skills/verify-before-push/SKILL.md`
  — stale counts removed / switch list completed (finding 3); `add-insight`'s
  duplicated "## 6" heading renumbered to 8.
- `.claude/skills/session-start/SKILL.md` — the "working directory does not
  reliably persist" bullet replaced (finding 6).
- `scripts/verify.sh` — stale "four of the five" comment corrected.
- `scripts/handover-check.sh` — check 4's comment no longer claims the test
  suite runs there (finding 9).
- `scripts/bootstrap-swift.sh` — stale "330 tests" count removed.
- `scripts/unbuilt-asks.sh` — now fails loudly if the backlog's `### B2 —` /
  `### B5 —` headings it parses are renamed; before, that printed an empty
  list, i.e. a false "nothing outstanding" — the exact failure the script
  exists to stop (finding 10).

Every edited script was re-run after editing: `verify.sh` (lint mode, Clean),
`handover-check.sh` (runs; correctly red on the uncommitted tree),
`bootstrap-swift.sh` (Darwin early-exit), `unbuilt-asks.sh` (same six rows as
before the edit), and the hook via the canary harness.

---

## The rest of the findings, ranked

6. **Contradiction (fixed): session-start vs CLAUDE.md on the shell working
   directory.** The skill said cwd "does not reliably persist between Bash
   calls" — the truth is the opposite (it persists, including drift) and the
   hook has anchored it since 2026-08-01, which CLAUDE.md states. A session
   obeying the skill wastes care; one reading both loses a cycle to the
   contradiction. **Applied.**

7. **`scripts/ci-errors.sh` is fully duplicated by `ci-status.sh --errors`.**
   Both fetch `refs/ci/errors/<sha>` and show `errors.txt`
   (`ci-status.sh:74–81` vs the whole of `ci-errors.sh`). No rule file
   references `ci-errors.sh`; only the efficiency log's history does. Two
   scripts answering one question is how a future session re-derives which one
   is canonical. Fix: delete `ci-errors.sh` or reduce it to a two-line shim
   that execs `ci-status.sh --errors "$@"` (not applied — removal is a
   judgement call and the ledger cites the file by name).

8. **Router gap (fixed): two real docs were invisible to the router.**
   `docs/data-opportunities.md` (ranked scoring bases for every unmodelled
   signal) and `docs/research-notes.md` (the published-literature half of the
   2026-08-04 research, plus the pointer to the private full reports) appeared
   in no router, so a fresh session could re-research either from scratch —
   the single most expensive class here. **Applied.**

9. **Handover protocol vs gate, audited: one overstatement, two soft spots.**
   The claims in CLAUDE.md ("clean tree, pushed HEAD, green CI on this commit,
   passing lint, all three docs touched, red-CI count matches") all hold in
   `handover-check.sh`. Gaps: check 4's comment claimed "the lint and the
   suite" while running lint only (**fixed**, comment now says what runs);
   nothing checks that the repeat-activity ledger or efficiency roadmap was
   actually touched (handover.md steps 8–9) — only the log-table row's red-CI
   arithmetic is verified; and the docs-touched check only fires when a base
   sha is passed, which the caller can forget with just a warning. Fix for the
   middle one, if wanted: extend check 5's loop to require
   `docs/efficiency-log.md` diffs to include the ledger section when Swift
   changed.

10. **`unbuilt-asks.sh` failed silently on renamed headings (fixed).** See
    "applied" list. Same fragility class to keep in mind for `card-map.sh` and
    `roadmap-table.sh`, though both already fail loudly via `--check` in the
    gate.

11. **Duplication between CLAUDE.md and the skills — the expensive kind, since
    CLAUDE.md loads every session.** The CI-reading rules (never the Actions
    API, use `refs/ci/*`, `--errors`) appear in full three times: CLAUDE.md
    "Primary Verification Commands", `ship-to-main` "Reading CI", and
    `verify-before-push` §4. The deploy-vs-CI distinction appears twice at
    similar length (CLAUDE.md Automation Rules; `ship-to-main`). Fix: keep the
    one-line rule + script name in CLAUDE.md and let the skills carry the
    war stories; saves a few hundred always-loaded tokens per session. Not
    applied — trimming the user's standing prose is their call.

12. **`pre-push-gate.sh` runs `verify.sh --tests` with a 420 s hook timeout;
    a cold-checkout `xcodebuild` is "minutes" by verify.sh's own comment.** A
    first push from a cold Mac checkout could hit the timeout and the gate
    fails open-ish (non-blocking hook error). Fix: raise the timeout in
    `.claude/settings.json` to 900 for that hook, or have the gate skip the
    xcodebuild half when `DERIVED_ROOT` is cold and say so.

13. **`ship-to-main`'s sequence shows `git add -A && git commit` while the
    ledger carries "`git add -A` in a canary, then `git reset --hard`" as an
    open hazard row.** Not a contradiction in context (a commit is not a
    canary), but the one place the pattern is *prescribed* is the one place a
    future session will copy it from. Fix: change the example to `git add -A
    && git commit` only after `git status --short` review, or name the hazard
    beside it.

14. **CLAUDE.md's "First thing, every session" is container-phrased for what
    is now often a Mac session.** "The container is rebuilt for every session,
    so the toolchain never survives" is untrue of the Mac (where the script
    exits immediately and the interesting first action is
    `simulator.sh doctor`, per `session-start`). Harmless but costs a beat of
    reconciliation every Mac session. Fix: one sentence — "on the user's Mac
    this exits instantly; the Mac-specific opening lives in `session-start`."

15. **The handover trigger-phrase block and the protocol summary in CLAUDE.md
    duplicate `.claude/commands/handover.md` at length** — same duplication
    class as finding 11, and `ship-to-main` §Handover already warns that a
    summary of the protocol went stale once. The trigger list must stay in
    CLAUDE.md (it is what fires the command); the three-part summary could be
    one line pointing at the command file.

## What this review deliberately did not do

Per its brief: no edits to `docs/backlog.md`, `docs/activeContext.md`, any
Swift source, `HealthInsights/`, `InsightKit/`, or `.claude/settings.json`
(finding 4 names the settings change for a main session to make). Nothing was
deleted; every fix that removed a count left a reason in its place.
