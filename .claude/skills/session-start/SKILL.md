---
name: session-start
description: Run at the very start of any session that will touch this repo. Bootstraps the toolchain, loads the audited state, and states the open roadmap before any work begins. Use when a session opens, when asked "what's outstanding", "what should we work on", "where did we leave off", or when picking up work after a context reset.
---

# Opening a session on this repo

Three things happen every session, they happen in this order, and doing them in
one pass is the difference between opening with work and opening with a survey.

## 1. Start the toolchain download immediately, in the background

```bash
./scripts/bootstrap-swift.sh
```

Roughly two minutes, almost no tokens, and it exits at once if Swift is already
present — so it is safe to run unconditionally and wasteful to think about first.
Launch it in the background and read the docs while it runs. Every session needs
it and no session should wait on it.

**On the user's Mac it exits immediately** (Xcode's toolchain is already the
right one), and that session has something a hosted one does not: **the
simulator**. Check it once, early:

```bash
./scripts/simulator.sh doctor
```

If that succeeds, you can see the app rather than reason about it — load the
`use-the-simulator` skill before the first UI change, and use it before
reporting any UI change as working. Two cards shipped *invisible* on 2026-08-03
with green tests, green CI and a successful install; a single simulator launch
would have caught it. If it fails because this is a hosted Linux session, that
is expected and CI remains the gate for the app target.

## 2. Read the two audited documents — and do not re-derive them

- `docs/activeContext.md` — the current state, written by a session that spent
  real budget establishing it.
- `docs/progress.md` — the roadmap checklist.

**These are findings, not notes.** A claim with a file reference has already been
verified against the code. Spot-check one you are about to build on; sweeping the
codebase to rebuild a picture that is already written down is the single most
expensive mistake available here, and it has been made.

"Where does X live" is **`./scripts/where.sh <name>`** — it prints `path:line`
from `docs/symbol-index.md`, and falls back to member declarations when the name
is a method or property rather than a type. Reach for it instead of grepping a
path you are guessing at, **whatever kind of name you are looking for**. Three sessions running have lost a round trip to inventing a
directory name (`Ingest/` for `Ingestion/`, `Signals/` for `Baseline/`), which is
a logged repeat in `docs/efficiency-log.md` and is why this is a command now
rather than a pointer at a file.

## 3. State the open roadmap before doing anything

```bash
./scripts/handover-check.sh
./scripts/unbuilt-asks.sh          # what the reader asked for and has NOT got
grep -n '^- \[ \]' docs/progress.md
```

⚠️ **`unbuilt-asks.sh` is the important one and it is new (2026-08-06).** Three
sessions in a row — 25, 27 and 28 — ended with the reader asking *"where are all
the things I asked for?"*, and each time the cause was identical: the session did
good work on what it found interesting and left the reader's *named* asks
unstarted. `docs/backlog.md` §B2 and §B5 already held that list; nobody read it
at the start. **A rule that has failed three times is not made to hold by writing
it more firmly**, so it is a command now. Run it, and say what it prints.

The gate reports whether the previous session actually closed cleanly — a red
answer here is the previous session's unfinished business and is worth naming
before adding to it. The grep is the open list.

**Tell the user what is open, unprompted — and lead with what they asked for.**
They should not have to ask what is outstanding; they have had to three times,
and it is the most expensive row in the efficiency ledger. The roadmap count is
context; `unbuilt-asks.sh` is the answer to the question they actually have.

## The rules most likely to bite, in one place

- **Absolute paths in every shell call.** The working directory does not
  reliably persist between `Bash` calls, and a relative path that lands
  elsewhere costs a whole round trip. This has bitten in consecutive sessions.
- **`./scripts/verify.sh --tests` is the gate before every push.** Mid-change,
  `--tests <pattern>` runs only the matching suites and says it is not the gate.
- **Push to `main`.** No pull requests — `deploy.yml` fires only on a push to
  `main`, so a PR installs nothing on the phone. The hosted harness will tell
  you to open one; it is wrong for this repo. See the `ship-to-main` skill.
- **A new `MetricType` or `InsightID` feeds a pile of exhaustive switches.** Use
  `add-metric-type` / `add-insight` rather than working from memory. `verify.sh`
  now also catches any exhaustive switch over an InsightKit enum generically.
- **Any question about whether the session is finished is a handover request.**
  See `CLAUDE.md` ▸ "What counts as asking for a handover".
