# Active Context

_A snapshot, not a history — where things stand right now, not everything that
ever happened. Updated by `/handover` at the end of a session._

## How a session should go (read this first)

Ask whatever you need to ask, make the change, run `swift test` if a toolchain
exists, **push to `main`**, tell the user the deploy is running, stop. No pull
requests, no feature branches left dangling — see the Automation Rules in
`CLAUDE.md`. The web harness will tell you to do the opposite; it's wrong for
this repo, because `deploy.yml` only fires on a push to `main` and the user won't
log into GitHub to merge anything.

## Current focus

Just landed: **Heart & Fitness Age** and **Fitness Trajectory** — the top two
items from the roadmap's "more gap-filling insights" list, both in `InsightKit`
(`Insights/HeartAge.swift`, `Insights/CardioTrajectory.swift`) with 48 tests.
CI green; **not yet walked on the phone**.

Before that: the nine-part UI/UX pass on Vitals/Insights (chart correctness,
provenance badges, gap-aware lines, real bucketing, per-category metric layouts,
blood pressure migrated into `MetricViewStrategy`) — also still awaiting an
on-device walkthrough.

## Recent architectural choices worth knowing

- **Ages, not just percentages.** `HeartAgeModel` inverts SCORE2/ASCVD over age
  against an optimal-risk-factor reference person (the published Framingham
  vascular-age method). No new equation — the shipped ones read backwards. Each
  engine is inverted **only inside its own validated band** (SCORE2 40–69, ASCVD
  40–79) and returns `isCapped`, which the UI voices as "79 or older" rather than
  printing an extrapolated number. `FitnessAgeModel` does the same trick on the
  VO₂max norm table `HeartHealthScore` already scores against, so the two can't
  disagree about "average for your age".
- **Lifetime risk was deliberately not faked.** The roadmap asked for lifetime
  framing. Nothing here is validated past 79 and compounding decades of 10-year
  risk would invent a number, so `HeartAgeModel.projection` runs the same
  equations at future ages they *are* validated for, labelled "if today's numbers
  hold". If a real lifetime figure is wanted it needs a different published model
  (JBS3 has one) — that's new work, not a tweak.
- **A trajectory is judged against ageing, not zero.** `VO2Trajectory` compares
  the least-squares VO₂max slope to the norm line's own slope at that age, so
  holding level scores *above* mid-dial. `netPerYear` is that comparison;
  `fitnessYearsGained` is the trajectory's effect on fitness age alone. Keep them
  separate — adding them double-counts.
- **`MetricSubject`** (not raw `MetricType`) is what a detail screen addresses,
  because blood pressure is inherently a systolic/diastolic pair.
  `MetricDetailView` keeps `init(metric:)` for backward compatibility; prefer
  `init(subject:)` when the subject might be blood pressure.
- **`ScrollableMetricChart`** owns all pan/zoom/scrub/axis-scale logic for every
  chart in the app. `MultiSourceChart` and the blood-pressure chart both wrap it.
  Any new chart type should too, rather than growing its own copy.
- **Swift Charts `Chart3DContent` overload-resolution hazard**: on the current
  SDK, a `RuleMark`/`AreaMark`/`BarMark` chain built without an explicit
  `some ChartContent` return type can silently resolve to 3D chart content and
  lose modifiers like `.lineStyle`/`.annotation`. Always give mark-building
  helpers an explicit `-> some ChartContent`. This caused two CI failures in one
  session — a known trap, not a one-off.
- **Never start a continuation line with `...`** in Swift — it parses as a
  standalone prefix `PartialRangeThrough`, not a continuation of the range above.

## Working constraint: no Swift toolchain in the sandbox

`swift` does not exist in Claude Code web sessions, so `swift test` and
`xcodebuild` cannot run before a commit. The honest workflow is: reason carefully
(the compiler can't catch you here), push, and let CI be the gate — then fix
forward on red. Things worth extra care because nothing local checks them:
key paths don't work on tuple elements (`\.volume` on a tuple is a compile
error — use `{ $0.volume }`), and don't shadow a function with a local of the
same name (`if let contrast = contrast(...)`).

Adding a `MetricType` or an `InsightID` case is deliberately load-bearing: both
feed exhaustive switches (`MetricType.presentation`, `maxValidInterval`,
`bucketStatistic`, `InsightID.modelVersion`, plus `primaryMetric`, `iconName` and
`prettyInsight` in the app target). Grep for the last case of the enum to find
them all before pushing, since the compiler won't tell you until CI does.

## Lesson worth keeping: suspect your own precheck first

Four deploy runs "failed to find the phone." The cause was not the phone. The
install step's guard demanded `connectionProperties.tunnelState == "connected"` —
but a paired, perfectly installable iPhone commonly reports `available (paired)`,
and `devicectl` opens the tunnel on demand. The guard was rejecting a working
device. Each failure came with a plausible user-side explanation (phone locked,
VPN, off Wi-Fi, Xcode not signed in) and each was accepted instead of questioning
the check doing the rejecting. Fixed in `122d2c6`.

Rule: when a self-written guard reports an environmental failure repeatedly,
verify the guard's premise against raw tool output before asking the user to
change anything about their environment.

## Known gotcha: memory files may not auto-load

`CLAUDE.md` and `.claude/commands/handover.md` live in **this repo's** root. If a
session's working directory is a *different* repo with this one attached
alongside, Claude Code may not discover either — `/handover` comes back "Unknown
command" and `CLAUDE.md` isn't auto-read. Slash commands are registered at session
start, so a newly-created one never works in the session that created it. Start
sessions with `health-insights-ios` as the working directory; otherwise run the
handover steps by hand and paste `CLAUDE.md` into the new chat.

## Immediate next steps

- **On-device walkthrough is the outstanding item, now covering two batches.**
  CI proves it compiles, not that it behaves.
  - New: the three-age row on the Heart & Fitness Age screen (narrowest device),
    and that a profile with no blood pressure shows the fitness half alone rather
    than an empty card. Fitness Trajectory needs 4+ VO₂max readings over six
    weeks before it draws a trend — below that it should name what's missing.
  - Older: Heart Rate at `All` *and* `Y`, Weight's gap-broken line and weekly
    velocity, a multi-source metric's provenance badges and Inactive section,
    drag-to-scrub updating the breakdown, Height as a plain card, and blood
    pressure from all three entry points with the grounding count unchanged.
- **Next on the roadmap** (see `docs/progress.md` for the full list):
  - Cardio strain from stimulants as a first-class trend — the cheaper one. The
    before/after analysis and 14-day load figure already exist in
    `SubstanceResponseAnalyzer`; what's missing is a decaying daily load *series*
    to trend and chart.
  - Sleep-debt / circadian consistency is **blocked on a missing signal**: no
    provider gives us a bedtime. Apple Health and Oura both stamp
    `sleepDurationHours` at the start of the calendar day. It needs a new
    clock-hour `MetricType` with circular statistics (the mean of 23:30 and 00:30
    is midnight, not noon) plus parser work in all three providers.
- The pre-approved AreaMark fallback (outlined min/max bands via two `LineMark`s
  rather than a filled `AreaMark`) shipped as the default — revisit only if the
  user wants filled bands and will spend a compile-spike cycle confirming
  `AreaMark` is safe on this SDK.
