---
description: Update active context and progress documentation before closing chat session
allowed-tools: Read, Edit, Write, Bash(git *)
---

# End-of-Session Handover Workflow
1. Analyze the code changes and decisions made in this chat session.
2. Update `docs/activeContext.md` with current focus, recent edits, and exact next steps.
3. Update `docs/progress.md` task statuses.
4. Commit changes to git with message `docs: update active context and progress state`.
5. Confirm to the user that memory files are synchronized and a new chat can be started safely.
