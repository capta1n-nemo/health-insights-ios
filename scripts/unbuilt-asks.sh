#!/usr/bin/env bash
# RETIRED 2026-08-07 — use `./scripts/backlog.sh --asks`.
#
# ⚠️ This script was written to stop a three-session repeat: sessions 25, 27 and
# 28 each ended with the reader asking where their requested work was. It failed
# the same way, a fourth time, and the failure is worth keeping written down.
#
# It matched `^### B2 —` and `^### B5 —`, and rows shaped `^| <digits> |`. The
# reader's 2026-08-07 brief (§B9–§B19, 22 rows) and their holidays brief (§B7,
# H1–H7) are `##`-level headings with `H1`/`C1`/`S1` row ids. They were
# **structurally invisible to it**. On the morning of 2026-08-07 it printed two
# items while roughly thirty of the reader's own asks sat open.
#
# The lesson is not "parse harder". It is that **a parser which silently returns
# nothing reads as "nothing outstanding"** — so the replacement treats an
# unreadable row as a hard error, and treats a section carrying table rows but no
# backlog rows as a hard error too, which is precisely how those briefs hid.
#
# It also had the right instinct in one place, kept in the replacement: it failed
# loudly if the headings it parsed ever moved. That guarded the headings it knew
# about and could not guard the ones it did not.
set -euo pipefail

cat >&2 <<'MSG'
unbuilt-asks.sh is retired. Use:

    ./scripts/backlog.sh --asks

There is one list now — docs/backlog.md — and one script that reads it. This
script parsed two hard-coded headings and could not see §B7 or §B9–§B19, so it
under-reported the reader's own asks by about thirty. See the header of this
file for the whole story, and scripts/backlog.sh for the contract.
MSG
exit 2
