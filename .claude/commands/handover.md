---
description: Update active context and progress documentation before closing chat session
allowed-tools: Read, Edit, Write, Bash(git *), Bash(./scripts/*)
---

# End-of-Session Handover Workflow

**This fires on intent, not on a keyword.** "Good to close?", "anything missed?",
"I'm starting a new chat" and "is everything recorded?" are all handover
requests. The three-literal-phrase trigger let two of those pass unhandled in one
session — see `CLAUDE.md` ▸ "What counts as asking for a handover". When unsure,
run it.

**Do not answer a "are we done?" question from memory.** Run
`./scripts/handover-check.sh` and answer from its output. That specific mistake
has now happened four times in this repo's history.

## Part 1 — carry the work forward

1. Analyze the code changes and decisions made in this chat session.
2. Update `docs/activeContext.md` with current focus, recent edits, and exact
   next steps. **And keep it a *current* state, not a stack**: the file is read
   at every session start, so every superseded narrative left in it is a tax on
   every future session (by 2026-08-06 it had accreted to 4,100+ lines across
   28 sessions). When a section describes work that later sessions closed or
   re-decided, **move it to `docs/archive/activeContext-history.md`** — move,
   never delete, so the audit survives — and leave one line behind only if a
   conclusion is still load-bearing.
3. **Update `docs/backlog.md` — it is the ONE list — then run
   `./scripts/backlog.sh`.**

   ⚠️ **There is one list. Do not start a second one.** Until 2026-08-07 there
   were three — the roadmap table in `progress.md`, the backlog, and two hand
   tables in `activeContext.md` — and a ground-truth pass found they disagreed
   in twenty places, with fifteen rows describing work that had already
   shipped. Maintaining them cost a session's budget every handover and still
   lost things. `docs/progress.md` now keeps only the historical shipped
   narrative; `docs/activeContext.md` keeps the current state and next steps in
   prose. **Neither records open work.**

   Three things, every handover:

   - **Every item this session closed gets its row marked `✅` with the
     commit.** Not deleted — nothing is ever deleted from the backlog, only
     marked. A removed row is how a backlog starts lying.
   - **Every finding gets a NEW row**, with an id, a wave, a stream, a tier and
     a gate. *A finding without a row is a finding lost* — that is what the
     three-list era did to six symptom-radar rows and to thirty of the reader's
     own asks.
   - **Run `./scripts/backlog.sh`, then `./scripts/status.sh`** — the second
     regenerates `docs/status.md`, the file the reader actually reads. It is
     derived from the backlog and from each research document's own
     `<!-- status: … -->` line, and it **hard-errors on a research or design doc
     that has no such line**. Add the line when you write the doc; a research
     report with no verdict cannot be told apart from an abandoned one.
   - **Run `./scripts/backlog.sh`** to regenerate the index. `handover-check.sh`
     runs `--check` and a session cannot close while the index and the rows
     disagree — and `backlog.sh` **hard-errors** on a row it cannot parse, or on
     a section carrying table rows but no backlog rows. That second rule exists
     because `unbuilt-asks.sh` parsed two hard-coded headings, could not see
     §B7 or §B9–§B19, and reported two open asks when about thirty were open.

   **Every row carries a `tier`** saying what model and effort it needs —
   `mech` (Opus 5 · medium), `build` (Opus 5 · high), `hard` (Opus 5 ·
   xhigh/max), `ultra` (Opus 5 + ultracode workflow), `design` (Fable 5). Set it
   honestly when you add a row: it is what lets a later session batch a tier and
   grind without stopping to ask, and it is the reader's own request. Say the
   model out loud when starting a batch whose tier differs from the one running.
4. **Carry the tooling forward, not just the prose.** If this session learnt a
   rule, hit a trap, or built a shortcut, put it where the *next* session will
   trip over it rather than only in the narrative:
   - a repeatable check -> `scripts/verify.sh`
   - a procedure with a checklist -> a skill in `.claude/skills/`
   - a command worth not re-deriving -> `scripts/`, and permit it in
     `.claude/settings.json` so it doesn't prompt
   - a rule that changed -> `CLAUDE.md`, and **correct the old wording** rather
     than appending. A stale rule that is still read is worse than no rule.
   Prefer self-healing over instructions: `verify.sh --tests` installs a Swift
   toolchain itself rather than telling the reader to.
5. **Bring `docs/card-sections.md` forward if any card section changed.** This
   is a numbered step of its own because the insight detail screen is the most
   edited surface in the app and that file is the only record of what each card
   shows. Many more cards are coming; the value of the record is that a gap in a
   *new* card is visible against the others, and that only works if it is true.

   ```bash
   ./scripts/card-map.sh          # regenerates the ordering block
   ./scripts/card-map.sh --check  # what handover-check.sh runs
   ```

   The generated block is **the section order only**. Four things beside it are
   hand-written, and a new or moved section changes all of them:

   - **the matrix** — one row per insight, one column per section, `●`/`◐`/`○`;
   - **the gate table** — what each section needs before it draws content rather
     than a `SectionPlaceholder`;
   - **the feature audit** — per section: arrives open or closed, has an empty
     state, its figure, its caveat, its chart;
   - **the chart audit** — per chart: pans, scrubs, honours the card's timeframe.

   A new card means a new matrix row and a bespoke-slot entry. A new *section*
   means a column in the matrix and a row in three tables. If the answer for a
   new card is `○` in any column, say why in the file — "correct, not a gap" is
   a finding and needs its reason beside it, exactly as `V&A` and `Fbk` do.

   The order itself has a rationale, written down under "The order, and why".
   Read it before moving anything.

6. Run `./scripts/verify.sh` and `./scripts/gen-symbol-index.sh` so the index and
   lint are current before the docs commit.

## Part 2 — the efficiency review (mandatory, never skipped)

A feedback loop, not a report. The point is that each session makes the next one
cheaper, and that we can *tell* whether it did rather than assuming.

7. **Measure from the repository — never from memory, and never from a token
   count.** Token usage cannot be observed from inside a session, so any figure
   would be invented, and one invented baseline poisons every later comparison.
   Everything below is recomputable by the next session:

   ```bash
   git log --oneline <session-base>..HEAD          # commits
   # Red CI, scoped to THIS session — the bare glob returns every failure the
   # repo has ever recorded, which is not what the row means.
   git log --format=%H <session-base>..HEAD | while read s; do \
       git ls-remote origin "refs/ci/failed/$s"; done | wc -l
   cd InsightKit && swift test 2>&1 | tail -3      # test count
   ```

   Then count, honestly:
   - **Red CI pushes** — each is a dead round trip plus a fix commit.
   - **Rework commits** — anything fixing something introduced earlier in the
     same session.
   - **Re-derivations** — facts the docs already held that got re-established
     anyway. **Name each one**: which fact, and where it was already written
     down. An unnamed count is gameable and worthless; a named one is checkable.

8. **Update the repeat-activity ledger** in `docs/efficiency-log.md`. Anything
   done in this session that has now happened in two or more sessions goes in, or
   has its count raised. Recurring-and-unautomated is what feeds the roadmap.

9. **Add at least one item to the efficiency roadmap, or say why not.** The
   ledger's top unautomated row is the default candidate.

10. **Prefer the compounding fix to the careful one.** Being more careful does not
   survive a context reset; a lint, a skill or a self-healing script does. When
   this session hit a problem, ask whether the fix retires the *instance* or the
   *category*, and reach for the category.

11. **Append a row to the log table** in `docs/efficiency-log.md`, with a short
    notes block underneath naming the red CI, the rework and the re-derivations.
    Mark unmeasurable history as *not measured* — never back-fill a guess.

12. **Re-read what you just wrote, against the code — both polarities.** Not
    "update the docs", *check* them. Two passes, and the second is the one that
    gets skipped:
    - every claim that something is **unbuilt, missing or not-yet-wired** — this
      session's own work is what invalidates those;
    - every checklist item this session marked **`[x]` or `[~]`, clause by
      clause**. A multi-clause item marked done hides its unfinished clauses:
      that is how six of them survived a "closed" list once already.

    This is the step that failed on 2026-07-31 — five completed things were
    still described as open, because updating a file and auditing a file are
    different acts and only the first was done.

13. Commit with `docs: update active context, progress and efficiency log`.

14. **Run the close-out gate and paste its output.**

    ```bash
    ./scripts/handover-check.sh <previous-handover-sha>
    ```

    It verifies — rather than asserts — that the tree is clean, HEAD is pushed,
    CI is green on *this* commit, the lint passes, `docs/backlog.md` parses and
    its index is current, all three docs were actually touched this session
    (`activeContext.md`, **`backlog.md`**, `efficiency-log.md`), and the
    efficiency log's red-CI count matches `refs/ci/failed`. **If it exits
    non-zero, the session is not done. Do not tell the user otherwise.** It also
    prints the open count **broken out by tier**, and how many of those are
    things the reader asked for in their own words — those are the numbers to
    read back to them, and the asked-for one goes first.

## Part 3 — tell the user, out loud

15. **End the reply with the efficiency verdict.** This is the non-negotiable
    part. It must contain:
    - **More or less efficient than the last session**, stated plainly.
    - **The log table**, so the trend is visible rather than asserted.
    - **A short reason if it got worse** — a sentence or two, not an essay.
    - **What was automated this session** so it cannot recur.

    Be willing to report a regression. A log that only ever improves is one being
    written to flatter, and it stops being worth keeping the moment that happens.

16. Confirm a new chat can be started safely — **on the strength of the gate's
    output, never on your own recollection.** "Everything is recorded" was said
    once from memory and was wrong; the check exists so that sentence has
    something behind it.
