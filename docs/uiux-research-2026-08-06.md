# UI/UX research — 2026-08-06 (stored for later, and PARTIAL)

**Research, not committed work.** Nothing here has been built, scheduled or
promised. It does not appear in `docs/progress.md` or `docs/backlog.md` as an
open item unless a future session deliberately promotes it.

## ⚠️ Read this first: this file is incomplete, and the rest is recoverable

Nineteen agents ran — one per app surface plus a loading-screen deep dive — and
all nineteen returned without error. **The synthesis step's output was truncated
in transit and only its tail reached this file.** The full per-agent findings
were not lost: they are one `{"type":"result",...}` line per agent in the run's
journal.

```
~/.claude/projects/-Users-jason-salway-Library-Mobile-Documents-com-apple-CloudDocs-HealthAppLocal-health-insights-ios/54307a14-df60-4743-98d6-7fde0e36b6de/subagents/workflows/wf_eaca6903-0ad/journal.jsonl
```

Each line holds a structured `{surface, findings[{title, detail, learnedFrom,
effort}]}`. **A session picking this up should read that journal and finish the
synthesis** rather than re-running the fleet, which cost ~1.16M subagent tokens.
The script is at
`…/workflows/scripts/uiux-research-fleet-wf_eaca6903-0ad.js` and resumes with
`Workflow({scriptPath: …, resumeFromRunId: 'wf_eaca6903-0ad'})` — completed
agents replay from cache, so only an edited synthesis step re-runs.

**The eighteen surfaces covered**: Today tab · Insights list · card detail pages ·
Data tab · charts · onboarding · empty states · input flows · navigation and
information architecture · settings and diagnostics · Cycle tab · score
presentation · typography, colour and iOS 26 glass · motion and haptics ·
accessibility · widgets, Live Activities and watch · notifications · loading
screen.

Each agent was given a named set of reference apps (Oura, Whoop, Apple Health,
Flighty, Linear, Arc, Things 3, Gentler Streak, Flo, Copilot Money and others)
and the repo's own product voice: no gamification, no dark patterns, and
honesty about uncertainty treated as something to design *for* rather than
around.

## The one finding that survived intact — and it is a good one

**Warm launches should skip the animated splash entirely.**

Once streaming hydration makes first content sub-second on a warm launch, invert
`minimumOnScreen` (`LaunchNarration.swift:84`): instead of holding the splash up
0.9 s to avoid a flicker, do not mount the animated `LaunchScreen` at all unless
content is still absent after a ~300 ms grace window. The static
`UILaunchScreen` poster — same cloud, same background (`LaunchScreen.swift:47`)
— covers the gap invisibly, and `isLaunching`'s init-time decision
(`AppModel.swift:1294`) becomes *pending* until either the grace timer or
hydration resolves it. The daily open then goes poster → Today with no branded
motion at all, and the particle heart appears only when there is a real wait to
cover.

**Today every launch, however warm, pays at least 0.9 s of splash.** The flicker
guard solved the right problem in the wrong direction.

*Learned from:* Linear (speed is the feature — the fastest loading screen is
none); Arc (brand motion is spent where it earns attention, never taxed on the
daily open). *Effort: medium.*

## Before acting on anything recovered from the journal

Load the relevant skill first — `add-chart`, `add-data-or-input`, `add-insight`,
`use-the-simulator`. Several findings depend on rules those skills carry. Line
numbers cited were accurate on 2026-08-06 and will drift; conclusions will not.
The top-20 ranking the synthesis produced is a suggestion about one power user's
daily felt value, not a commitment — cross-check the backlog before starting.
