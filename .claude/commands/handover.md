---
description: Update active context and progress documentation before closing chat session
allowed-tools: Read, Edit, Write, Bash(git *), Bash(./scripts/*)
---

# End-of-Session Handover Workflow

## Part 1 — carry the work forward

1. Analyze the code changes and decisions made in this chat session.
2. Update `docs/activeContext.md` with current focus, recent edits, and exact next steps.
3. Update `docs/progress.md` task statuses.
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
5. Run `./scripts/verify.sh` and `./scripts/gen-symbol-index.sh` so the index and
   lint are current before the docs commit.

## Part 2 — the efficiency review (mandatory, never skipped)

A feedback loop, not a report. The point is that each session makes the next one
cheaper, and that we can *tell* whether it did rather than assuming.

6. **Measure from the repository — never from memory, and never from a token
   count.** Token usage cannot be observed from inside a session, so any figure
   would be invented, and one invented baseline poisons every later comparison.
   Everything below is recomputable by the next session:

   ```bash
   git log --oneline <session-base>..HEAD          # commits
   git ls-remote origin 'refs/ci/failed/*'         # red CI — the headline waste
   cd InsightKit && swift test 2>&1 | tail -3      # test count
   ```

   Then count, honestly:
   - **Red CI pushes** — each is a dead round trip plus a fix commit.
   - **Rework commits** — anything fixing something introduced earlier in the
     same session.
   - **Re-derivations** — facts the docs already held that got re-established
     anyway. **Name each one**: which fact, and where it was already written
     down. An unnamed count is gameable and worthless; a named one is checkable.

7. **Update the repeat-activity ledger** in `docs/efficiency-log.md`. Anything
   done in this session that has now happened in two or more sessions goes in, or
   has its count raised. Recurring-and-unautomated is what feeds the roadmap.

8. **Add at least one item to the efficiency roadmap, or say why not.** The
   ledger's top unautomated row is the default candidate.

9. **Prefer the compounding fix to the careful one.** Being more careful does not
   survive a context reset; a lint, a skill or a self-healing script does. When
   this session hit a problem, ask whether the fix retires the *instance* or the
   *category*, and reach for the category.

10. **Append a row to the log table** in `docs/efficiency-log.md`, with a short
    notes block underneath naming the red CI, the rework and the re-derivations.
    Mark unmeasurable history as *not measured* — never back-fill a guess.

11. **Re-read what you just wrote, against the code.** Not "update the docs" —
    *check* them. Open `docs/activeContext.md` and verify every claim that
    something is unbuilt, missing or not-yet-wired is still true after this
    session's work. This is the step that failed on 2026-07-31: five completed
    things were still described as open, because updating a file and auditing a
    file are different acts and only the first was done.

12. Commit with `docs: update active context, progress and efficiency log`.

13. **Run the close-out gate and paste its output.**

    ```bash
    ./scripts/handover-check.sh <previous-handover-sha>
    ```

    It verifies — rather than asserts — that the tree is clean, HEAD is pushed,
    CI is green on *this* commit, the lint passes, all three docs were actually
    touched this session, and the efficiency log's red-CI count matches
    `refs/ci/failed`. **If it exits non-zero, the session is not done. Do not
    tell the user otherwise.** It also prints the open-roadmap count, which is
    the number to read back to them.

## Part 3 — tell the user, out loud

14. **End the reply with the efficiency verdict.** This is the non-negotiable
    part. It must contain:
    - **More or less efficient than the last session**, stated plainly.
    - **The log table**, so the trend is visible rather than asserted.
    - **A short reason if it got worse** — a sentence or two, not an essay.
    - **What was automated this session** so it cannot recur.

    Be willing to report a regression. A log that only ever improves is one being
    written to flatter, and it stops being worth keeping the moment that happens.

15. Confirm a new chat can be started safely — **on the strength of the gate's
    output, never on your own recollection.** "Everything is recorded" was said
    once from memory and was wrong; the check exists so that sentence has
    something behind it.
