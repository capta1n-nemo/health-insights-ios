---
description: Update active context and progress documentation before closing chat session
allowed-tools: Read, Edit, Write, Bash(git *)
---

# End-of-Session Handover Workflow
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
6. Commit changes to git with message `docs: update active context and progress state`.
7. Confirm to the user that memory files are synchronized and a new chat can be started safely.
