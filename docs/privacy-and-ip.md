# Privacy and IP on a public repository

Written 2026-08-03, after the user asked how to protect the project and whether
any personal information had reached the public repo. Some of it had.

## The bad news first: history is not redactable in place

**A public repository publishes its history, not just its current state.**
Deleting a value in a new commit leaves it in every earlier one, reachable by
anyone with the URL, and GitHub keeps unreferenced objects visible through the
API for a long time after. Forks and clones keep it regardless.

So there are exactly two honest options for anything already committed:

1. **Rewrite history** (`git filter-repo`), force-push, and delete every fork.
   Effective for the repo itself; cannot recall a clone anyone already took.
2. **Make the repository private**, which removes public access to the whole
   history at once.

Everything below assumes that. Redacting going forward is worth doing — it stops
the *next* leak — but it is not a fix for the last one.

## What was found, 2026-08-03

| What | Where | Status |
| --- | --- | --- |
| **iPhone UDID**, hardcoded as a fallback | `deploy.yml`, and briefly `runner-doctor.sh` | Removed; now secret-only. **Still in history.** |
| **Real health values** — sleep medians, resting-HR min/median/max, weekly screen-time totals | `docs/progress.md`, `docs/activeContext.md` | Present by design. See below. |
| **Full name in the bundle identifier** — `com.jasonsalway.healthinsights` | `project.yml`, `project.pbxproj`, `docs/deployment.md` | Present. Changing it re-provisions the app. |
| Credentials, tokens, provisioning profiles | — | **None committed.** `.gitignore` covers `.build`; no `.p12`, `.mobileprovision` or `.env` is tracked. |

The combination is what matters. Health values alone would be anonymous; a name
alone would be harmless. **Together, in one public repo, they are a named
person's sleep, heart-rate and screen-time data.**

### Why the health values are in the docs at all

They are evidence. `progress.md` records *"Oura's own median (4.94 vs Apple's
6.86)"* because that number is what proved the split-night defect, and a session
that reads "the medians disagreed" cannot check the claim or notice when it stops
being true. The audit is the most valuable artefact in this repo and vague
findings would gut it.

**The rule going forward, applied by judgement rather than by lint:** quote the
*shape* of a finding, not the reading. "The median rose once split nights were
summed" carries the finding; "4.94 → 5.85" carries the reader's sleep. Where a
number genuinely is the evidence, it belongs in a commit message on a private
repo, or behind the private/public split below.

Deliberately not linted: a regex that catches "5.85" catches every version
number and threshold in the codebase, and a lint that cries wolf gets disabled.

## What *is* linted

`verify.sh` fails on a committed hardware or account identifier — UUIDs and
UDID-shaped strings outside tests and fixtures. Proved with a canary. It is a
mechanical class with no legitimate reason to be in source; the judgement class
above stays a judgement.

## Going private: the cost, honestly

The blocker was a belief that private repos make Actions expensive. Half true,
and the expensive half is fixable.

| Runner | Public repo | Private repo |
| --- | --- | --- |
| GitHub-hosted **Linux** | free | 1× included minutes |
| GitHub-hosted **macOS** | free | **10× included minutes** |
| **Self-hosted** (this Mac) | free | **free — no minutes at all** |

Free plan includes 2,000 minutes/month; Pro (~$4/mo) includes 3,000. At the 10×
macOS multiplier that is **200 macOS minutes a month on Free**, and this repo's
`ci.yml` runs *two* `macos-15` jobs on every push. At roughly five minutes each
that is ~100 billed minutes per push — **about twenty pushes a month before
overage**, and this project does that in a day. Overage runs ~$0.08 per macOS
minute, so a busy month would be tens of dollars.

`deploy.yml` already runs `self-hosted`, so it is free either way.

### The fix, and its one real cost

**Move `ci.yml`'s two `macos-15` jobs to the self-hosted Mac; leave the
`ubuntu-latest` jobs on GitHub.** Then a private repo costs approximately
nothing: the Linux jobs run the full InsightKit suite at 1×, and 2,000 free
minutes is far more than this project uses.

The cost is real and worth stating: **macOS CI would then only run when the Mac
is on.** On 2026-08-03 the runner was down for most of a day; under this
arrangement the app-compile check would have been unavailable for all of it,
while the Linux job — which runs the actual test gate — would have carried on
unaffected. That is the right side of the trade to be on, but it is a trade.

## Recommendation

1. **Go private.** It is the only thing that addresses both the IP question and
   the already-published history in one move, and it is the reason to solve the
   cost question rather than live with it.
2. **Move the macOS CI jobs to self-hosted first**, so the switch costs nothing.
3. **If the repo must stay public**, then at minimum: rewrite history to drop
   the UDID, move the health values out of the docs into a private notes file,
   and accept that the bundle identifier still names the author.
4. **A licence does not protect much either way.** With no `LICENSE` file the
   default is already "all rights reserved" — nobody may legally reuse it. That
   stops honest reuse and does nothing about the dishonest kind. Private is
   protection; a licence is paperwork.
