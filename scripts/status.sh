#!/usr/bin/env bash
# Generates `docs/status.md` — "where do we stand", for the reader.
#
# ⚠️ Why this is a script and not a document. The reader asked for a complete
# status breakdown on 2026-08-07 and it was written by hand as
# `docs/status-2026-08-07.md`: 534 lines, correct that morning, stale by the
# evening, and **a fourth list** of exactly the kind `backlog.sh` was built to
# retire. A hand-written status file is a promise to keep two things in step and
# this repo has already proved it cannot keep three.
#
# So the feature half is DERIVED from `docs/backlog.md` (via `backlog.sh --json`,
# so the row contract exists in one place), and the research half is derived from
# the research documents' own status lines. Neither can disagree with its source
# because neither is written down twice.
#
#   ./scripts/status.sh           # rewrite docs/status.md
#   ./scripts/status.sh --check   # exit 1 if it is stale (what handover-check runs)
#
# **A research or design document with no status line is a hard error.** Same
# rule as an unparseable backlog row, for the same reason: 15 of 19 such
# documents had no machine-readable verdict, so "we researched that" and "that
# research reached a conclusion" were indistinguishable — and two of them turned
# out to be refuted designs that a later session could have built from.
set -euo pipefail
cd "$(dirname "$0")/.."

ROWS=$(./scripts/backlog.sh --json)

ROWS="$ROWS" python3 - "$@" <<'PY'
import collections, datetime, json, os, pathlib, re, subprocess, sys

ARGS = sys.argv[1:]
OUT = pathlib.Path("docs/status.md")
rows = json.loads(os.environ["ROWS"])

# --- the research half -----------------------------------------------------
# Every research/design/evidence document declares its own state on one line:
#
#     <!-- status: complete — one clause saying what it concluded -->
#
# States: complete · partial · refuted · superseded · stopped · scoped
RESEARCH_GLOBS = ["docs/*research*.md", "docs/*design*.md", "docs/*evidence*.md",
                  "docs/*audit*.md", "docs/*scope*.md"]
# Not research reports: the standing note file, and the archive.
EXCLUDE = {"docs/research-notes.md"}
STATE_RE = re.compile(r"<!--\s*status:\s*(?P<state>[a-z]+)\s*—\s*(?P<why>.+?)\s*-->")
STATES = ["complete", "partial", "refuted", "superseded", "scoped", "stopped"]

docs, missing = [], []
for g in RESEARCH_GLOBS:
    for p in sorted(pathlib.Path(".").glob(g)):
        s = str(p)
        if s in EXCLUDE or "/archive/" in s or any(d["path"] == s for d in docs):
            continue
        m = STATE_RE.search(p.read_text())
        if not m:
            missing.append(s)
            continue
        st = m.group("state")
        if st not in STATES:
            missing.append(f"{s} (unknown state '{st}')")
            continue
        docs.append({"path": s, "state": st, "why": m.group("why"),
                     "lines": len(p.read_text().splitlines())})

if missing:
    print("status: research documents with no machine-readable status line:\n",
          file=sys.stderr)
    for m in missing:
        print(f"  ✗ {m}", file=sys.stderr)
    print("\n  Add one line to each — anywhere in the file:\n"
          "      <!-- status: complete — what it concluded, in one clause -->\n"
          f"  States: {' · '.join(STATES)}.\n\n"
          "  A research document with no verdict cannot be told apart from one\n"
          "  that was abandoned, and two refuted designs in this repo were very\n"
          "  nearly built from because of exactly that.", file=sys.stderr)
    sys.exit(2)

# --- the feature half ------------------------------------------------------
OPEN = ("open", "part")
by_state = collections.Counter(r["state"] for r in rows)
asks = [r for r in rows if r["ask"]]
GATE_LABEL = {
    "phone": "**Your phone** — only you can close it; a simulator cannot",
    "decision": "**Your call** — a question is waiting on you",
    "needs": "**Another row** — chained behind unfinished work",
    "external": "**Outside the repo** — a provider, an account, a device setting",
    "none": "Nothing — ready to pick up",
}
TIERS = {
    "mech": "Opus 5 · medium", "build": "Opus 5 · high",
    "hard": "Opus 5 · xhigh/max", "ultra": "Opus 5 + ultracode",
    "design": "Fable 5",
}
TIER_ORDER = ["mech", "design", "build", "hard", "ultra"]
WAVES = {"w0": "Blockers", "w1": "Shipped but wrong", "w2": "Quick wins",
         "w3": "Substantial builds", "w4": "Complex, last"}

sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                     capture_output=True, text=True).stdout.strip()
today = datetime.date.today().isoformat()

def title(r):
    return re.sub(r"\*\*", "", r["title"]).replace("|", "\\|").strip()

def table(rs, show_gate=True):
    o = ["| Item | What | Tier | " + ("Waiting on |" if show_gate else "Wave |"),
         "|---|---|---|---|"]
    for r in sorted(rs, key=lambda r: (r["wave"], TIER_ORDER.index(r["tier"])
                                       if r["tier"] in TIER_ORDER else 9, r["id"])):
        last = (r["gate"] if r["gate"] != "none" else "—") if show_gate else r["wave"]
        o.append(f"| `{r['id']}` | {title(r)} | `{r['tier']}` | {last} |")
    return o

L = []
w = L.append
w("# Where we stand")
w("")
w(f"**Generated {today} at `{sha}` by `./scripts/status.sh` — do not edit.**")
w("Every number below is derived: features from `docs/backlog.md` (the one list),")
w("research from each document's own status line. Nothing here is written twice,")
w("so nothing here can disagree with its source.")
w("")
w("## The short answer")
w("")
w(f"- **{by_state['done']} delivered** · **{by_state['part']} partly delivered** · "
  f"**{by_state['open']} not started** · **{by_state['wont']} will not be built** "
  f"(of {len(rows)} tracked items)")
ready = [r for r in rows if r["state"] in OPEN and r["gate"] == "none"]
blocked = [r for r in rows if r["state"] in OPEN and r["gate"] != "none"]
w(f"- Of the {by_state['open'] + by_state['part']} still open: "
  f"**{len(ready)} can be picked up right now**, {len(blocked)} are blocked.")
open_asks = [r for r in asks if r["state"] in OPEN]
w(f"- **You asked for {len(asks)} things in your own words. "
  f"{len(asks) - len(open_asks)} are delivered; {len(open_asks)} are not.**")
rdone = sum(1 for d in docs if d["state"] == "complete")
w(f"- Research: **{len(docs)} documents** — {rdone} complete, "
  + ", ".join(f"{n} {s}" for s, n in
              collections.Counter(d["state"] for d in docs).most_common()
              if s != "complete") + ".")
w("")
w("---")
w("")
w("## 1. What you asked for and have NOT got")
w("")
w("These are the rows carrying an explicit `ask` marker — things you said, in your")
w("own words, that are not finished. This is the list to read first.")
w("")
if open_asks:
    L.extend(table(open_asks))
else:
    w("Nothing. Every ask on the list is delivered.")
w("")
w("## 2. Blocked, and by what")
w("")
w("Nothing here is blocked on effort. Each group needs a different unlock.")
w("")
for g in ["phone", "decision", "external", "needs"]:
    grp = [r for r in blocked if r["gate"].split(":")[0] == g]
    if not grp:
        continue
    w(f"### {GATE_LABEL[g]} — {len(grp)}")
    w("")
    L.extend(table(grp))
    w("")
w("## 3. Ready to pick up, batched by the model it needs")
w("")
w("This is the batching you asked for: a session works one tier, on one model,")
w("without stopping to ask. Waves run in your order — fundamentals, then quick")
w("wins, then the complex work last.")
w("")
for t in TIER_ORDER:
    grp = [r for r in ready if r["tier"] == t]
    if not grp:
        continue
    w(f"### `{t}` — run on **{TIERS[t]}** — {len(grp)} items")
    w("")
    L.extend(table(grp, show_gate=False))
    w("")
w("## 4. Partly delivered — what is missing on each")
w("")
w("A part-done row is the most dangerous kind, because the feature *exists* and")
w("looks finished. The row's prose in `docs/backlog.md` says what is missing.")
w("")
part = [r for r in rows if r["state"] == "part"]
L.extend(table(part))
w("")
w("## 5. Delivered")
w("")
w(f"{by_state['done']} items. Listed by stream so a gap is visible against its")
w("neighbours; the commit for each is in its row in `docs/backlog.md`.")
w("")
done = [r for r in rows if r["state"] == "done"]
for s, n in collections.Counter(r["stream"] for r in done).most_common():
    ids = " ".join(f"`{r['id']}`" for r in sorted(done, key=lambda r: r["id"])
                   if r["stream"] == s)
    w(f"- **{s}** ({n}) — {ids}")
w("")
wont = [r for r in rows if r["state"] == "wont"]
if wont:
    w("## 6. Will not be built")
    w("")
    w("Kept on the list with the reason, so it is never silently re-proposed.")
    w("")
    L.extend(table(wont, show_gate=False))
    w("")
w("## 7. Research")
w("")
w("Each document's state is declared inside it, so this table cannot go stale.")
w("**`refuted` and `superseded` matter most: do not build from those.**")
w("")
w("| Document | State | Lines | What it concluded |")
w("|---|---|---|---|")
for d in sorted(docs, key=lambda d: (STATES.index(d["state"]), d["path"])):
    name = d["path"].removeprefix("docs/")
    w(f"| [`{name}`]({name}) | **{d['state']}** | {d['lines']} | "
      f"{d['why'].replace('|', chr(92) + '|')} |")
w("")
w("---")
w("")
w("*Regenerate with `./scripts/status.sh`. `handover-check.sh` runs `--check` and")
w("a session cannot close while this file disagrees with the backlog.*")

new = "\n".join(L) + "\n"
old = OUT.read_text() if OUT.exists() else ""

# The generated-on line moves every day; comparing it would make --check fail
# for no reason, which is how a gate gets ignored.
def strip_stamp(s):
    return re.sub(r"^\*\*Generated .+$", "", s, flags=re.M)

if strip_stamp(old) == strip_stamp(new):
    print(f"status: docs/status.md up to date ({len(rows)} items, {len(docs)} research docs)")
    sys.exit(0)
if "--check" in ARGS:
    print("status: docs/status.md is stale. Run ./scripts/status.sh.", file=sys.stderr)
    sys.exit(1)
OUT.write_text(new)
print(f"status: wrote docs/status.md — {by_state['done']} delivered, "
      f"{by_state['part']} partial, {by_state['open']} not started, "
      f"{len(open_asks)} open asks, {len(docs)} research docs")
PY
