#!/usr/bin/env python3
"""Fail when a ✅ row in docs/backlog.md still describes its work as unbuilt.

The consolidation's own failure mode, surviving inside the consolidated list.

`I9` read "Mesh renders; **no capture exists**" for a week after the guided
body-scan capture shipped in `1dc9789`; a session planning from that row would
have rebuilt a shipped feature. Earlier the same day `P22` and `R24` were marked
✅ with bodies still ending *"is not started"*. Three instances, all found by the
handover's both-polarities sweep and never by any check — and the efficiency log
said "no mechanical check exists" until this was written. The status glyph and
the prose are both free text and nothing related them. This does.

⚠️ **This is a separate file rather than a heredoc inside `verify.sh` for a
reason worth keeping.** It started as `stale=$(python3 - <<'X' … X)` and broke
`verify.sh` with "syntax error: unexpected end of file" — the regex below
contains backticks, and bash parses the *inside* of `$( )` looking for its
matching paren, so a backtick in a heredoc nested there opens a command
substitution that never closes. Any lint whose pattern must match this repo's
`` `ID` `` row syntax has to live outside command substitution.

Scoped narrowly on purpose:
  - the row TITLE is exempt — a defect's own name is often "X does not exist";
  - quoted spans are exempt — this repo quotes superseded claims deliberately;
  - the body stops at the next heading, so a section title cannot trip it;
  - a row that genuinely needs the phrase declares `<!-- stale-ok: why -->`.
"""
import pathlib
import re
import sys

DOC = pathlib.Path("docs/backlog.md")
ROW = re.compile(r"^- `(?P<id>[^`]+)` (?P<st>[⬜◐✅❌]) ")
STALE = re.compile(
    r"\b(is not started|not yet started|no capture exists|is unbuilt"
    r"|not built yet|nothing is built|never been built"
    r"|no such (?:view|screen|section|card) exists)\b", re.I)
QUOTE = re.compile(r'\*"[^"]*"\*|"[^"\n]{0,400}"', re.S)

if not DOC.exists():
    sys.exit(0)

lines = DOC.read_text().splitlines()
idx = [(n, m.group("id"), m.group("st"))
       for n, line in enumerate(lines) if (m := ROW.match(line))]

hits = []
for k, (n, rid, st) in enumerate(idx):
    if st != "✅":
        continue
    end = idx[k + 1][0] if k + 1 < len(idx) else len(lines)
    body = []
    for line in lines[n + 1:end]:          # n+1 — the title line is exempt
        if line.startswith("#"):
            break
        if line.lstrip().startswith(">"):  # blockquotes are quotations too
            continue
        body.append(line)
    text = "\n".join(body)
    if "stale-ok:" in text:
        continue
    m = STALE.search(QUOTE.sub("", text))
    if m:
        hits.append(f'{rid} ({DOC}:{n + 1}) still says "{m.group(0)}"')

if hits:
    print("\033[31m✗\033[0m A ✅ row still describes its work as unbuilt:")
    for h in hits:
        print(f"    {h}")
    print("\n\033[1mEither the mark is wrong or the prose is stale — and a session "
          "planning\n  from the prose will rebuild shipped work. Fix it, or mark "
          "the row\n  <!-- stale-ok: why --> if the phrase is deliberate.\033[0m")
    sys.exit(1)
