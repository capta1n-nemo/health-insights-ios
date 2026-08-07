#!/usr/bin/env bash
# RETIRED 2026-08-07 — use `./scripts/backlog.sh`.
#
# This generated the open-items table at the top of `docs/progress.md` from the
# `- [ ]` boxes below it, and `handover-check.sh --check`ed it. It worked, and
# it is retired for a reason that has nothing to do with it being broken: there
# were **three** open-item lists — this table, `docs/backlog.md`, and two hand
# tables in `docs/activeContext.md` — and a ground-truth pass on 2026-08-07
# found they disagreed in twenty places, with fifteen rows describing work that
# had already shipped.
#
# Three lists is three chances to be wrong and three handovers' worth of effort.
# `docs/backlog.md` is the one list now; `docs/progress.md` keeps the historical
# shipped narrative and no longer records open work.
#
# ⚠️ One thing this script learnt the hard way is carried into the replacement,
# and it must not be lost: it originally matched `- [ ] ` at **column 0**, so a
# single nested item was invisible to the table, to `--check`, and therefore to
# the handover gate meant to stop a session closing on a stale roadmap. A
# counter that cannot see an item cannot notice it going stale. `backlog.sh`
# answers this by refusing to run at all when a row does not parse, rather than
# by matching more patterns.
set -euo pipefail

cat >&2 <<'MSG'
roadmap-table.sh is retired. Use:

    ./scripts/backlog.sh          # regenerate the index
    ./scripts/backlog.sh --check  # what handover-check.sh runs

docs/backlog.md is the single list. docs/progress.md keeps the historical
shipped narrative only — it no longer carries a generated open-items table.
See the header of this file for why, and scripts/backlog.sh for the contract.
MSG
exit 2
