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

## Handover now measures itself — read this before the next one

`/handover` has three parts and the third is **non-negotiable**: end the session
by telling the user whether it was cheaper than the last one, with the table.
See `.claude/commands/handover.md` and `docs/efficiency-log.md`.

The constraint that shaped it: **token usage cannot be observed from inside a
session**, so any figure would be invented and would poison every later
comparison. Every column is recomputable from `git` and `refs/ci/*` by a session
that trusts none of the prose. The one self-reported column — re-derivations —
requires each to be *named*, with the place the fact was already written down.

The column that matters is **compounding**: being careful does not survive a
context reset, but a lint, a skill or a self-healing script does. When a problem
appears, ask whether the fix retires the *instance* or the *category*.

## Current focus

**The Phase-2 session (latest).** One push, `dc5fae6`, CI green. "Continue with
roadmap" — the open list was read back and the four buildable Phase 2 items were
taken, plus a fifth the user added on reading the plan. Body Composition's scan
entry was **deferred by the user** to its own session.

### One defect, three times: a number that dies at a string boundary

This is the finding worth carrying, because it is a *class* and the codebase
almost certainly has more of it.

- `PeerStandingModel` computes a centile. `HeartHealthScore.swift:219-226` turns
  each one into `"HRV 48 ms — top 25% for your age and sex"` and the number is
  never seen again.
- `HeartAgeAnalyser` fills `Analysis.projections` (`:146`).
  `CardiovascularRiskInsight.swift:186` reads four *other* fields off that local
  and lets it fall out of scope. Worse: the analyser's own `explanation()`
  (`:273`) writes *"The projections below run the same validated equations at
  future ages"* — and that function has **no production caller at all**, only
  `DeepDiveTests` and `HeartAgeTests`. A promise nobody could see being broken.
- `VO2Trajectory.projectedIn12Months` and `.residualSD` — the latter described in
  its own doc comment as "the honest ± on the forecast" — were read nowhere
  outside `CardioTrajectory.swift`.

**How to find the next one**: grep a model's `Output` for a public field, then
grep the app target for its name. `InsightResult` has no typed side-channel, so
anything not in `contributors`, `driverLines`, `score` or `headline` reaches the
screen only if some view calls the model directly — and mostly nothing does.

### Two threshold tables that could have drifted, and now cannot

Both are the `PressureBandTests` situation, and both were fixed by making the
duplicate impossible rather than by testing that two copies agree.

- `PeerStandingModel.Standing.phrase` held the edges 90 / 75 / 60 / 40 / 25
  inline. A strip that *shades* those bands has to read the same numbers.
  `PeerStandingModel.Band` owns them now; `phrase` reads it.
- The vitals scan's `watchZ` / `unusualZ` moved into `VitalDeparture`, and
  **`VitalSignsCheck.reading` now calls `VitalDeparture.band(z:concerning:)`**.
  One implementation, not two that agree today.

**And the strip's band is `Reading.status`, not a re-derivation from z.** Two
reasons, both real:
- **Direction matters.** `Spec.concernWhenHigh`/`concernWhenLow` mark the
  clinically meaningful way round. Colouring by `abs(z)` would paint a resting
  heart rate two SD *below* baseline — the best morning of the month — in the
  same red as the worst.
- **An absolute bound overrides a personal one.** A reading can be `.unusual` at
  a small z. `VitalDeparture.isBeyondClinicalBound` is derived by asking whether
  the z alone would have produced that band, and it exists because a red dot
  near the middle of the axis with no explanation reads as a rendering fault.

### The chrome rule is a compile error now, not a convention

`InsightSection` (over `Card`) and `NestedInsightSection` carry title, at most
one figure, content, caveat. **`caveat` has no default**, so a section cannot be
written without stating one and `.none` is a visible choice.

That is the compounding shape the efficiency log keeps asking for: it retires the
*category* — "a section can ship without saying it inferred" — rather than the
eight instances, and it needs no lint because the compiler is the gate. The old
convention was followed by four sections out of twelve.

What it replaced, measured by reading every section: footnote colour split three
ways for one job (`.tertiary`, `.secondary`, `Theme.warn`), four header fonts,
inner spacings of 8 / 10 / 12 with no rule, and **one trailing slot that changed
quantity under a fallback** — a kilogram delta, or a count of weigh-ins, same
position, nothing to tell them apart.

Moving the wording into `SectionCaveat` (InsightKit, tested) immediately caught
two shipped defects: the body-composition caption opened *"Height is your
weight"*, and pluralised *"across 1 weigh-ins"*.

### "View & add" claimed an anatomy it did not have

Its own doc comment said "the anatomy is fixed whatever the route". Read against
the code: blood pressure had a grounded summary and the other two did not; the
grounding-facts route had **no add button at all**, so its rows were the only way
in; the "all readings" link appeared only past three readings, so the screen was
unreachable exactly while a user was learning the feature; and all three routes
previewed their own contents on the card.

Now everywhere: header and figure, green grounded summary, one prominent button
into the sub-menu holding adding *and* what was added, and a link to the fuller
screen **where one exists past it**. No previews — readings, events and fact
values all moved behind the button (`GroundingDetailView` is new for the facts).

Two decisions to keep: the link is blood-pressure-only, because
`SubstanceLogView` and the grounding list already *are* the full view and two
controls pointing at one destination is what this section exists to remove; and
`ContributionSummary.bloodPressure` **defers to `CalibrationStatus`** rather than
forming a second opinion on whether it is calibrated.

### The gate that did not need to fire

`progress.md` had carried "**Do this first**: ask the user for the data
inventory" on Phase 2 for several sessions. It gated nothing, and the reason
generalises: **every remaining item drew output a model was already computing**,
so "does the data exist" was answered by the model producing a value at all.
Each section self-gates on its own floor, which is what every existing section
does — so a card with nothing to show doesn't draw it, and nothing had to be
decided in advance. Same shape as *"this needs a product decision" is a claim
about the implementation*.

**The charts-on-the-phone session (previous).** Fifteen pushes, all installed. It
began as "here is a fresh inventory" and became a long iterate-on-the-phone loop
over the Body Composition card. What it produced, and what it cost, are both
worth reading before touching a chart here.

### The two data defects, and how they were found

- **A night crossing midnight was counted as two.**
  `HealthKitService.fetchSleep` keyed every nightly figure on
  `Calendar.startOfDay(for: segment.startDate)`. Apple Health writes a night as a
  run of stage segments, so the pre-midnight ones were filed under one day and
  the rest under the next: one night became two, the smaller a sliver. That is
  the export's `sleepDurationHours` **min of 0.01 h**, and — efficiency having
  split its numerator and denominator independently — its **2% minimum** too. It
  also dated Apple Health a day out from Oura, which stamps a night at the day it
  *ends*, and `bucketStatistic` averages same-day samples. Same "7.5 h reported
  as 4 h" shape as the nap bug, from a second cause that outlived it.
  Now `SleepNights` in InsightKit, 14 tests, keyed on `SleepOnset.night(of:)`.
  **The fix was one scroll from the bug, in a comment that named it** —
  `SleepOnset.night(of:)` said "grouping by calendar day is what the duration
  series already does and it is wrong", written by the session that fixed the
  timestamp path and left the duration path alone.
- **The export could not settle the question it was built for.** The nap fix was
  to be proved by `restingHeartRate`'s max falling from 119, but three sources
  feed that metric and the report gave one merged distribution, so 119 named
  nobody. `DataInventory` now emits per-source N/first/last/min/median/max for
  every multi-source signal. **Still unproven — ask for a fresh export.**

### What the phone now has that it did not

- **Settings ▸ Troubleshooting ▸ Rebuild data from providers.** Pull-to-refresh
  *merges*; the cache-merge keeps the samples of any source that returned nothing,
  so a provider that quietly fails to sync serves stale values forever and no
  amount of pulling dislodges them. "Refresh" and "replace" were different
  requests and only the first had a gesture. Manual entries, grounding, substance
  logs and feedback are SwiftData and untouched.
- **Phase 2 is done**: all nine cards have a bespoke section. Heart Health and
  Readiness share "How this is weighted" (drawn from `contributors`' renormalised
  weight — no new type, no model change, exactly as the roadmap predicted); Body
  Composition got "What you're made of" plus a stacked-area history.
- **A scrub line on every chart.** Seven charts wrap `ScrollableMetricChart`, so
  drawing it there covered all seven at once; only the two standalone charts
  needed their own.
- **Score history is filled and graded by band.**

### Five chart lessons, in cost order — read these before touching a chart

1. **A Swift Charts gradient resolves against the mark's own bounding box, not
   the plot area.** A card scoring 15 drew the full green-amber-red ramp squeezed
   into the bottom sixth of the chart. `Theme.scoreFill(peak:)` takes the peak for
   this reason.
2. **A stacked area whose series is absent over a stretch still reserves a
   stacked offset for it**, interpolated from its first real value, while its
   polygon starts only where its data does. The two disagree and the disagreement
   is drawn — a white wedge widening to exactly the size of the first reading.
   **Give every series a value at every x, zero where the band is absent.**
3. **Band membership must not vary point to point.** Giving each day the finest
   split its own readings supported was honest and drew a row of notches. A day
   missing the muscle/bone division now borrows the ratio from the nearest day
   that measured one and is flagged `isEstimated`.
4. **A translucent overlay cannot make blue over red look blue.** Five attempts
   at hue and opacity all landed on plum, because red mixed with blue *is* purple
   — colour arithmetic, not a tuning problem. The measured composite was
   rgb(126, 88, 121): red and blue near-equal, green suppressed. **A hatch never
   mixes**: every pixel is one colour or the other. `Theme.waterHatch`.
5. **Measure the pixel, don't pick the hue.** Four of this session's eight rework
   commits are one visual iterated by eye. One measurement found the cause in a
   single step. Same shape as the launch-screen tuning in session 11, which is
   already in the ledger as *tune a visual against opinion instead of
   measurement*.

### Three things to carry from the first half of the same session

- **A measurement artefact can survive the fix aimed at it, because two causes
  produce one symptom.** The Oura nap fix was correct, deployed and installed;
  the number it was meant to move did not move, and the tempting reading was that
  the fix had failed. It hadn't — a second cause was still live.
- **An instrument that cannot attribute cannot settle anything.** The export was
  built to end "we don't have X" arguments and then merged away the one
  distinction the argument needed.
- **"Refresh" and "replace" are different requests.** Only the first had a
  gesture, and the cache-merge means a silently-failing provider serves stale
  values forever. Now Settings ▸ Troubleshooting ▸ Rebuild data from providers.

**The data-export session (previous).** The export built last session was used for
the first time, and it immediately found **two defects in signals the app
already models** — not the missing signals everyone expected.

- **Oura naps were being counted as nights.** `OuraResponseParser.SleepRecord`
  never decoded `type`, so `late_nap` and `rest` segments became
  `.sleepDurationHours` — and because `bucketStatistic` *averages* same-day
  sleep, a 7.5 h night plus a 20-minute nap reached the user as a 4 h night.
  The same records also lent their **awake** heart rate to `.restingHeartRate`,
  which seven models read, and an evening nap could become the night's
  *bedtime*, because `SleepOnset` keeps the earliest segment and −4.0 h is
  inside its plausible band. Sleep, Readiness, Energy, Heart Health, Fitness and
  Blood Pressure were all downstream of it.
- **`MetricSanitizer` had no upper bound**, only `value > 0`. Now every metric
  declares a `plausibleRange`.

**The rule this establishes**: *"we don't have X" and "X looks fine" are both
claims about the code until somebody has looked at the distribution.* Nothing in
the parser looked wrong; every test passed. What gave it away was a median sleep
of 5.62 h with a minimum of 0.01 h.

Three things worth carrying:

- **A bound must reject the impossible, never the alarming.** The artefact that
  started this was a resting heart rate of 119. It was tempting to set the
  ceiling just under it — that would have been fitting the bound to one user's
  bad record, and 119 bpm is a real resting heart rate in atrial fibrillation.
  It is an artefact because of *where it came from*, not its value. The nap
  filter removes it; the bound is for values no living person produces.
- **Order matters inside a parse loop.** The nap guard was first placed after the
  bedtime was collected, so naps still poisoned sleep onset. The fix only works
  at the top of the loop.
- **Check whether a migration is needed before building one.** The plan assumed
  the corrupted history needed a wipe-and-re-sync. It does not: `sync()` always
  pulls a 730-day window, and the cache merge already replaces *all* of a
  source's samples when it returns data. The next ordinary refresh rebuilds
  Oura's history through the corrected parser on its own.

`docs/data-opportunities.md` is new: the ranked list of signals nothing reads
yet, each with the published basis for whether it can be scored honestly, plus
how Oura's own scores should be handled. **Ask for a fresh export before
building from it** — the numbers that prove the fix are the sleep-duration
median and the resting-HR maximum.

**The card-consolidation session (previous).** Three pushes, all installed:
Phase 1 of the consistency work (`42efe4c`), the data export (`0d8bc48`), and
**seventeen insight cards merged into nine** (`367e0ab`).

`docs/card-sections.md` is the audit of record and was re-derived after each.
**Phase 2 — the three cards still without a bespoke section — is scoped in
`docs/progress.md` and not started.**

### What to know before touching the insight layer

- **Nine cards.** Fitness ← Cardio Fitness + Fitness Trajectory + fitness age.
  Sleep ← Sleep Quality + Sleep Debt + Sleep Regularity. Readiness ← Readiness +
  Vitals Check + Health Watch. Heart age went to the risk card (which runs those
  equations); centiles went to Heart Health (which reads those metrics);
  Resting Heart Rate and Where You Stand were deleted as cards.
- **The maths was kept.** `VO2Trajectory`, `FitnessAgeModel`, `HeartAgeAnalyser`,
  `SleepDebtModel`, `CircadianConsistencyModel`, `VitalSignsCheck`,
  `HealthWatchModel`, `PeerStandingModel` all still exist with their tests, as
  *components*. Only the wrappers and their ids went. **Do not rebuild any of
  them** — check for the model before writing one.
- **`contributions` is derived from `requirements`, not switched over
  `InsightID`.** A sixth exhaustive switch on that enum would be the most
  expensive possible way to add a feature — it is already the most frequent CI
  break here.

### Five lessons this session, in cost order

- **A protocol member with a default must still be a protocol *requirement*.**
  Callers hold `any InsightModel`; declared only in an extension, it dispatches
  statically, every model silently gets the default, and the overrides are dead
  code **that still pass their own tests** because those hold the concrete type.
  `testOverridesSurviveExistentialDispatch` is the shape of test that catches it.
- **A merge drops behaviour silently, and only the old tests know what.** Four
  real regressions were caught by tests written for the deleted cards: weight-0
  contributions counting toward "is this day well-founded" in `ScoreHistory`, the
  vitals panel leaving the overlay chart, an irregular-rhythm flag no longer
  outranking an ordinary day, and "we couldn't judge this vital" being folded in
  with the normal ones. **When merging cards, repoint the tests rather than
  deleting them** — each one is a behaviour somebody decided on.
- **Pass `now` to every component, always.** Sleep's regularity term defaulted to
  the real present, which would have flattened every replayed day of score
  history without ever erroring. `ScoreHistory.replay` hands a model a past day
  as `now`; a component that ignores it reads a window the samples don't reach.
- **`Color` has `primary`, `secondary` and `white` — but no `tertiary`.** One red
  CI. Twelve existing `x ? Theme.foo : .secondary` ternaries compile because the
  shorthand resolves to a `Color` static. **Nothing local catches this class** —
  SwiftUI does not exist on Linux, so CI alone compiles the app target.
- **Generate a wide table rather than hand-writing it.** The 17×17 matrix was
  hand-written and its column tally was wrong by one; the generated version
  caught it. A grid that big has no reviewable failure mode by eye.

### The claim that was wrong, and the rule it restates

The plan said `dayStrain` never arrived because it had an alias but no promotion
rule. **Whoop's typed parser has been emitting it as a first-class sample all
along** (`WhoopResponseParser.swift:69`) — the gap was at the *consumption* end:
no insight read it. Same shape as the bedtime that sat "blocked on a missing
signal" for several sessions while being discarded at ingest. **"We don't have
X" is a claim about the code until somebody has looked at the data** — which is
now possible, see below.

### The feedback loop that closes this class of error

**Settings ▸ Export my data.** An inventory of every signal — modelled *and* the
imported-but-unmodelled fields behind Vitals ▸ Other data — with counts, date
ranges, sources and distributions, small enough to paste into a chat. Plus a
full JSON export. `DataInventory` in InsightKit builds it and is tested there.

**Ask the user for the inventory before deciding what to build next.** Nobody
working on this app has ever seen what is actually in their Vitals tab.

**The roadmap-continuation session (previous).** "Continue with roadmap" — the
open list was read back, and the only substantial item buildable from a sandbox
was the hydration cost left over from session 11. It was recorded as needing a
product decision first; measuring it showed it did not, and the insight pass is
now 3.7× faster with no change to what the first frame knows. See "Immediate
next steps" below for the numbers and for the one part that *does* still need
the user (the cache format). Nothing in this session has been seen on the phone.

**The loading-screen session, in four rounds of user feedback.** Built the
splash, shipped a 32-second launch with it, fixed that, replaced the animation
with a live Metal particle heart, broke the user's build for four deploys, and
tuned the result against measurements of their own reference. Every single
defect was found by the user on the phone, not by CI. Read the efficiency log's
session-11 notes before the next one — this was the most expensive session
recorded.

**The one structural thing to know before touching anything:**
`ci-status.sh` proves the code *compiles on GitHub's runners*.
`deploy-status.sh` proves it *reached the phone*, and `deploy.yml` runs on the
user's own Mac. They are different questions, the second is the one that
matters, and for most of this session only the first was being asked — which is
how "deployment triggered" got said four times over failed deploys. **A push is
not an install. Run both.**

`docs/progress.md` ▸ "App-launch loading screen" has the full account; the
things worth carrying:

- **A screen that covers a wait can become a screen that causes one.** The
  splash waited for the whole of `refresh()` before revealing Today — but that
  work had *always* run behind an already-visible app, with a spinner on the
  Today card. The feature took correctly-backgrounded work and put it in front
  of the user. **When adding a gate, check what the user could already see
  without it.** It now waits on `isHydrated` — enough data to draw Today — and
  nothing else.
- **A SwiftUI launch screen cannot cover the pre-first-frame gap.** 7–8 s of the
  report was `AppModel.init` — a `@State` default, so it runs before SwiftUI
  draws anything — doing a JSON decode of ~128k samples plus all seventeen
  insights. The app was not white by choice; it had not reached its first frame.
  Only `UILaunchScreen` in `Support/Info.plist` covers that, and it was an empty
  dict, which renders plain white. **If you are asked to fix a blank screen at
  launch, find out whether the app has drawn its first frame yet.**
- **`Sendable` for testability is `Sendable` for concurrency.** Moving hydration
  off the main actor was nearly free because `HealthMetricSample`, `InsightEngine`,
  `InsightResult` and `UserHealthProfile` were already `Sendable` — built
  platform-free so InsightKit could be tested on Linux. The same property let
  them leave the main thread. `DataStore`'s four *file*-backed cache accessors
  are now `nonisolated`; the SwiftData ones cannot follow, because `mainContext`
  is main-actor by construction.
- **A timeout must not live on the thread it is timing out.** The 20 s hard
  ceiling was polled from the `@MainActor` narration loop, so it was starved by
  exactly the main-thread work it existed to protect against. The one launch
  that needed it was the one launch that could not fire it. Now it sleeps off
  the main actor and hops back only to act.

- **CI green does not mean the user's Mac can build it.** `ci.yml` runs on
  GitHub's `macos-15`; `deploy.yml` runs on the user's own Mac, and that is the
  only machine that installs anything. Adding a `.metal` file broke *their*
  build for four consecutive deploys — Xcode 26 ships the Metal compiler as a
  separately downloadable component and their Mac does not have it — while CI
  passed every time, because GitHub's image does. **Any build input that is not
  plain Swift is a place the two environments can differ.** The shader is now
  compiled at runtime with `makeLibrary(source:)`, which needs no toolchain on
  either machine.
- **The launch heart is drawn live by Metal, not played from a file.** The video
  it replaced was 608×1078 on a screen that upscales ~2.4×, with its density and
  speed baked in — and those were exactly the complaints. `LaunchParticleField`
  (InsightKit, tested) builds the cloud; `LaunchParticleView` draws it. Density,
  colour and speed are now constants, which matters because they were tuned
  three times.
- **Tune against a measurement, not against an opinion.** "Too light, not dense
  enough" was answered by measuring the user's own reference frame — ink
  coverage 30.6%, mean saturation 53.2, mean luminance 168, darkest 5% at 125 —
  and iterating the renderer until it matched (33.4 / 53.6 / 171 / 137). The
  first attempt had been washing 82% of the way to white. Same method placed the
  caption: sweeping ink coverage in horizontal bands found 1.6% at 0.58–0.63
  against 37% where the text had been sitting.
- **A semantic colour is only semantic if the surface under it is too.** The
  status line used `.secondary` on a screen that deliberately commits to a light
  background whatever the system appearance is. On a phone in dark mode that
  resolves to a *light* grey, and the copy vanished.

**Earlier in the same session**, before the regression was reported:

- **A brief's own constraint can be half of a pair, with the other half unstated.**
  The scope said the copy "must be driven by a timer rather than by real phase
  transitions, or a fast launch will flash three messages in half a second" —
  correct, and the failure it names is real. Followed literally it produces the
  opposite lie: a status line announcing "Generating insights" while the network
  request it depends on is still out. The resolution is that neither drives it —
  **the timer paces, the phase clamps** — and the invariant underneath both is
  simpler than either: nothing replaces a line before it has been on screen long
  enough to read. When a brief explains *why* a constraint exists, check whether
  the reason has a mirror image.
- **The new state is `AppModel.launchPhase`, not `isSyncing`.** The scope had
  already identified this: one flag covered the provider round-trip and the
  FoundationModels pass, and those are exactly the two waits the copy exists to
  tell apart. `refresh()` sets `.ready` in a `defer` declared *above* the
  too-soon refresh gate, so a skipped refresh still releases the screen.
- **Every floor on this screen is one that gets dropped in a refactor**, which is
  why they are all constants in InsightKit with tests rather than magic numbers
  in the view: a minimum on-screen time so a cached launch doesn't flicker, a
  hard ceiling so a stalled refresh can't trap the user, and a minimum dwell per
  line. A launch screen that never leaves is the worst outcome available here.

**The roadmap-review session** (previous). "Let's go through roadmap" — the open
list was read back, and the two items that were both open *and* buildable from a
sandbox were taken: Sleep Regularity's own chart, and sleep onset through the
promotion rules. Both shipped in `ada3b1d`. `docs/progress.md` ▸ "The
roadmap-review session" has the detail. Three things are worth carrying:

- **A guard whose comment states a premise is a place the premise can be wrong.**
  `IngestionPipeline` promoted on `field.value.doubleValue`, commented "promotion
  is numeric by definition" — true of every metric until `.sleepOnset`, which
  derives from a timestamp. The failure mode was not an error: a rule pointed at
  a text field *matched* and promoted nothing. The one-line version of that
  roadmap item (add `bedtime_start` to the alias table) would have shipped
  looking correct and done nothing. **Before adding a row to a data table, check
  that the machinery reading it can represent the new row's type.**
- **Check the field survives ingest before writing a rule for it.**
  `GenericJSONIngestor` excludes `startDateKeys` from the field sweep, and
  `bedtime_start` is one of Oura's (`start` is Whoop's). A promotion rule aimed
  at either would match nothing, forever, silently. Written down beside the
  aliases in `PromotionRules.swift`.
- **The container's local `main` is a stale, unrelated history** — see the
  section below. This cost a round trip and is now fixed in the `ship-to-main`
  skill rather than only recorded here.

### Two container traps, both of which look like success

Neither is about this codebase; both are about the environment, and both were hit
in one session.

1. **`git checkout main` silently gives you a months-old tree.** Local `main` sat
   at `87cd998` with **no merge base at all** against `origin/main` (`9f5db1d`).
   The checkout succeeds, and `docs/progress.md` comes back as a version from
   many sessions ago. `git push -u origin main` from a `claude/*` branch has the
   same root cause — it pushes that local ref rather than your work.
   **Ship with `git push origin HEAD:main`**, which never consults the local
   branch. Corrected in the `ship-to-main` skill, with the check that proves the
   push is a fast-forward.
2. **A stop hook asks you to amend every commit. It is a closed matter.**
   Settled on 2026-07-31 and **the user has asked that it not be discussed
   again** — the remedy is a no-op and acting on it would force-push `main`. The
   `ship-to-main` skill says so at the point it fires. Don't re-derive it, don't
   explain it back, don't act on it.

   The generalisable half is worth keeping, because it has now cost six round
   trips in different disguises: **verify a guard's premise against raw tool
   output before acting on its remedy.** Same shape as the `tunnelState` deploy
   guard, the Oura scope guess, and the "script is missing" report dismissed as
   stale.

### The previous session's findings, still current

- **The one blocked roadmap item was never actually blocked.** Circadian
  consistency had been logged for several sessions as needing a signal no
  provider gives us. HealthKit's sleep segments carry a real `startDate`, Oura's
  `bedtime_start` was *already being decoded* (and used only as a fallback for
  the record's date), and Whoop's records carry `start`. All three were collapsed
  to hours-per-calendar-day at ingest and the timestamp thrown away. **Rule worth
  keeping: "no provider gives us X" is a claim about the parsers, not about the
  APIs, until somebody has opened the payload.**
- **`.sleepOnset` is signed hours from midnight with the branch cut at midday**,
  not a clock hour. This is the load-bearing decision. A clock hour in [0, 24)
  needs circular statistics — the mean of 23:30 and 00:30 is midnight, not noon —
  and `Baseline`, the regressions and every chart here are linear. Moving the
  wrap to a time nobody sleeps makes the arithmetic mean the circular mean, so
  *no consumer has to know*. Choosing a representation beats propagating a
  special case.
- **Sleep Regularity scores the spread and never the hour**, and there is a test
  sweeping three very different bedtimes to keep it that way. Chronotype is
  largely constitutional and shift work is a job. `referenceRange` is `nil` for
  the same reason, with the reason written down.
- **Social jetlag is subtracted from the spread rather than averaged into it.** A
  consistent weekend lie-in is two tight blocks plus a recurring shift; a bedtime
  wandering by the same amount at random is neither. One number cannot say both.
- **The overlay chart's dash-versus-opacity question resolved to "the quieter end
  wins".** Everywhere else a span is as prominent as its more anomalous end,
  because both ends were measured. A bridge was measured nowhere, so a maximum
  would let one spike pull a week of silence forward as though something had been
  observed in it. `SeriesBridging.bridgeProminence`.
- **`verify.sh` now lints *any* exhaustive switch over an InsightKit enum**, not
  a hand-maintained list of them. CI broke this session on a `Suggestion.Basis`
  switch in `InsightsListView` that no list mentioned — the same shape as the
  `.vitalSigns` break before it. Swift already requires a `default:`-free switch
  to name every case, so the check needs no per-switch knowledge. Two canaries
  prove it fires.

Then a second half, driven by the user's re-read of their own feedback list and
three fresh complaints. The findings from that half:

- **The trend chip is not "vs yesterday", and that was researched rather than
  assumed.** None of Oura, Whoop, Garmin, Apple Health, Fitbit or Withings ships
  a day-over-day delta on a daily score: day-to-day HRV variability is 3–13% and
  a genuinely hard day moves it 10–20%, so the arrow would report noise most
  days and get ignored. `ScoreChange` keeps the direction and moves the
  comparison — today against the trailing week, four weeks against the quarter.
  Full reasoning and sources in `docs/progress.md` ▸ "How trend indicators are
  rendered". **If a future session is asked to "just make it vs yesterday",
  that is a one-line change and the argument above is what to put beside it.**
- **A relative threshold needs an absolute companion.** Three instances in one
  session, all the same shape — a small denominator makes anything significant.
  Blood-pressure drift is floored at ±5 mmHg (a fit through few points claimed
  *zero* uncertainty and divided by it), the substance suggestion at 3%, and
  `ScoreChange` at two points.
- **"Completed" needed no per-suggestion definition.** The engine only emits a
  suggestion while its condition holds, so vanishing from its output *is*
  resolution by whichever of the three routes. When a feature seems to need
  per-case rules, check whether the generator already encodes them.
- **A slow tap was one call doing far too much.** Logging a substance ran the
  whole engine over the whole sample set and dropped every cache. When a
  cheap-looking interaction is slow, look for the shared recompute it reuses
  rather than the work it obviously does.
- **"That technique has a fatal flaw" is not "this is impossible".** Gap bridging
  shipped straight with an argument that a curve invents an extremum. True of
  Catmull-Rom and natural cubics; mistaken for an argument against curvature. A
  monotone cubic Hermite cannot have an interior extremum at all. The gap between
  those two claims was a shipped deviation from an explicit instruction.

### What is still not done, and why

- **On-device verification of everything since the last device-verified build.**
  Nothing in this session or the previous two has been seen on the phone. CI
  proves it compiles; both regressions two sessions ago were caught by the user's
  screenshots, not by CI.
- **`EnergyModel.exertionHours` still weights every heart-rate sample equally.**
  Deliberate and commented — a watch's own sampling gaps are not idle time, and
  using real inter-sample intervals needs a decision about what a gap means.
- **`AppModel.swift` and `InsightDetailView.swift` are the two largest app-target
  files and are deliberately unsplit.** Swift's `private` is file-scoped, so an
  extension-based split widens every member the moved code touches, and both are
  dense with private state. Three files *were* split (`OAuthIntegration`,
  `AdditionalInsights`, `HeartAge`); `BloodPressureEstimator.swift` and
  `VitalSignsInsight.swift` still hold model and insight together and are the
  remaining candidates — and being InsightKit, they carry no file-private
  coupling to the view layer, so the objection above does not apply to them.
- **New provider integrations** (Hume direct, Ultrahuman, Garmin, Fitbit) need
  the user's own developer credentials per provider and cannot be tested from
  here at all. Same for the VisionKit scanner and ECG import — device-only
  surfaces with no test path.
- ~~**Filled `AreaMark` min/max bands** want a compile spike.~~ **Resolved
  2026-08-01**: `BodyCompositionTrendChart` ships `AreaMark(x:yStart:yEnd:)` for
  the water film and it draws correctly. The one real catch is that the overload
  takes **no `stacking:` argument** — an absolute band between two heights is
  inherently unstacked — which is a compile error, not a silent one. Recorded in
  the `add-chart` skill.
- **Oura's ~4–6 months of history** is still unexplained. Offered, not taken up.
- **The LiDAR body scan** is still open by request — explicitly a roadmap note
  rather than a build, and scoped in `docs/progress.md`. The app-launch loading
  screen that sat beside it is **done**; see "Current focus".
- **The open efficiency-roadmap items are now these** — the two this line used to
  name (`symbol-index.md` as a reflex, a session-start checklist skill) were both
  built sessions ago as `scripts/where.sh` and `.claude/skills/session-start/`,
  and this bullet had gone stale claiming otherwise. **Also now closed:** reading
  a red CI cheaply, built 2026-08-01 as `refs/ci/errors/<sha>` +
  `scripts/ci-errors.sh`. Currently open: a build-environment parity check
  between CI and the user's Mac (the top item, and the one that cost four
  deploys); *read the composited pixel before choosing another colour* (new, and
  the most expensive item of session 14); never `git add -A` inside a canary; the
  false-premise guard category, which may stay human; and a *"blocked on a
  decision" note should carry the measurement that proves the tradeoff is real*.
  See `docs/efficiency-log.md`, which is the authority.

## Two regressions I shipped, and what they cost

Both were caught by the user's screenshots, not by CI, and both have the same
root cause: **the rule lived in the view layer where no test could reach it.**

1. **Two identical reds.** "Draw only the anomalous ones" is not by itself a
   small number — thirteen vitals with nine departing is an ordinary week, so the
   ninth line wrapped onto a hue already in use.
2. **Steady signals drawn as notable**, contradicting the legend one line below.

Fixed by moving the rule into `InsightKit/Sources/InsightKit/Presentation/OverlaySelection.swift`
and testing it against the screenshot's own shape. **Rule worth keeping: if a
piece of logic decides whether two things can look alike, or whether a number is
right, it belongs in InsightKit.** The app target has no test target — anything
that lives there is verified only by eye.

## The Oura scope answer (don't re-derive this)

Oura returns **401, not 403, for a missing scope** — it reserves 403 for a
lapsed subscription — and names the scope in the RFC7807 `detail` of the body.
Neither its published scope table nor its OpenAPI spec (v1.37, eight scopes)
documents which endpoint needs which. Learned from its own error text:

| Collection | Scope |
| --- | --- |
| `daily_resilience` | `stress` |
| `daily_cardiovascular_age` | `heart_health` |
| `vO2_max` | `heart_health` |

Also: Oura's developer console moved to `developer.ouraring.com/applications`
(the OAuth authorize/token endpoints did **not** move). And Oura does **not**
reliably return `scope` on the OAuth callback, despite documenting that it does.

## Recent architectural choices worth knowing

- **One quantity drawn over another is a hatch, never a blend.** This is the
  standing approach — `Theme.hatch(light:dark:_:)`, worked example in
  `BodyCompositionTrendChart`. A translucent fill *mixes*, and the mix is a third
  colour that means nothing and is frequently nowhere near either parent: blue
  over red is purple at every ratio, because it is colour arithmetic rather than
  a tuning problem. A hatch keeps both colours because every pixel is one of
  them. Two corollaries earned the hard way: **draw the host band whole and paint
  over it** — carving the overlaid share out as its own slice removes the host's
  colour from that stretch, so nothing reads as underneath and no hue can fix it —
  and **the overlaid quantity contributes no mass to the stack**, so it wants an
  `AreaMark(x:yStart:yEnd:)` between two cumulative heights, with the span
  computed in InsightKit where it is testable.
- **When a colour looks wrong, measure the composited pixel before choosing
  another one.** Five rounds went into the water colour by eye; the measurement
  (rgb 126, 88, 121 — red and blue near-equal, green suppressed) named the cause
  in one step. Generalised: when a visual fix keeps landing in the same wrong
  place, check whether the mechanism can produce the target at all before picking
  another value for it.

- **Choose a representation instead of propagating a special case.** `.sleepOnset`
  could have been a clock hour with circular statistics, and then `Baseline`,
  every regression and every chart would have had to know which metric they were
  holding. Moving the branch cut to midday made the linear machinery correct by
  construction. When one value type would make everything downstream an
  exception, look for the encoding that makes it not one.
- **"No provider gives us X" is a claim about the parsers.** Circadian consistency
  sat blocked for sessions on a signal that was in every payload and was being
  discarded at ingest. Before recording something as blocked on a missing signal,
  open the payload.
- **Merge overlapping spans before shading them.** Three logs in a morning drawn
  as three translucent rectangles compound into a darker band, which encodes *how
  many* in a channel meant to say only *whether*. Same class of error as two
  identical reds: an encoding that carries information nobody intended.
- **A generic lint beats a maintained list of lints.** The exhaustive-switch check
  named each switch individually and therefore only caught the ones somebody had
  remembered. Swift's own rule — a `default:`-free switch names every case — is
  enough to check the class rather than the instances.
- **Don't ask for a permission you don't use.** Oura's `heartrate` scope was
  requested for months and never called. Removing it costs a comment naming the
  three steps to reinstate.

- **A shared reader beats a shared convention.** Every insight "knew" it should
  read a daily, de-duplicated, windowed value; every insight wrote its own and
  got it wrong differently. `VitalReader` is the convention made a type. When you
  find the same four-line pattern in five files with five bugs, extract it —
  don't document it.
- **Freshness is reported, not enforced.** `VitalReading.isFresh` is a fact; what
  it *means* is the insight's call. Readiness drops a stale component (it's a
  claim about today); Heart Health keeps one (VO₂max updates every few weeks by
  design). A single global staleness rule would have been wrong for one of them.
- **Presentation logic that can be wrong belongs in InsightKit.** The app target
  has no test target. `OverlaySelection` and `MetricPalette` decide whether two
  lines can look alike — that is a correctness question, not a styling one, and
  both regressions this session came from having it in the view.
- **A tri-state flag beats a Bool when "we didn't check" is a real state.**
  `InsightDriver.isNotable: Bool?` — `nil` means the insight doesn't draw the
  distinction, which must not render as "everything is fine".
- **Two copies of a clinical threshold need a test binding them.** The
  blood-pressure bands exist in `Category.of` (classify) and `systolicRange`
  (shade). `PressureBandTests` sweeps every value from 80 to 210 and asserts each
  lands inside the band its own classifier assigned it.
- **Encoding that is technically safe can still be practically wrong.** The
  (hue, dash) pair was collision-free by construction and validated with a
  colour-blindness tool. It still failed, because dash carries a *meaning* to
  readers — "estimated / missing" — that no separation metric measures. Check
  what an encoding says, not just whether it's distinguishable.
- **Providers fetch bytes; the pipeline decides what they mean.** `SyncedData`
  now carries `payloads: [IngestPayload]` alongside samples. A provider's typed
  parser contributes only the handful of fields it has *unit and semantic*
  knowledge about; everything else in the document is the pipeline's job. That
  inversion is why a field Oura added this morning reaches the vitals layer with
  no code change.
- **`RawValue` is `number | text | flag`,** encoded as a bare JSON scalar. The
  bare-scalar choice is load-bearing: caches written when `RawMetricSample.value`
  was a `Double` decode straight into `.number(...)`, so the migration is free.
  There is a test pinning this — don't "tidy" it into a tagged object.
- **Numeric arrays summarise, they don't explode.** Oura's 5-minute night series
  (`heart_rate.items`, ~200/night) becomes count/min/max/mean/first/last.
  Expanding literally would add ~40k samples per sync for data Apple Health
  already mirrors. `FlattenPolicy.arrayStrategy = .expand` is the per-field
  switch if a series ever earns it. Chosen deliberately with the user.
- **Promotion is data, never inference.** `PromotionRuleSet` maps
  path/leaf/suffix → `MetricType` with unit conversion. A field that merely
  *looks* like a known vital (alias match, no rule) is catalogued and logged as
  a **proposal**. This is what stops a provider renaming a field from silently
  rewiring an insight. Also chosen deliberately with the user.
- **Empty ≠ unknown.** `OAuthTokens.grantedScopes` stores `nil`, never `[]`, and
  **nothing may withhold a request on the strength of it.** A build that skipped
  collections whose scope looked absent read "provider didn't say" as "granted
  nothing" and suppressed the very sync that would have proven the fix worked.
  The provider's own 401 is the only authority.
- **A scope 401 is never retried.** `ProviderAPIError.missingScope` recognises
  Oura's phrasing; a fresh token carries the same grant, so retrying only spends
  a single-use refresh token and logs each failure twice. Refreshes are coalesced
  through one in-flight `Task` and disabled for the rest of a sync after a
  failure, because Oura's refresh tokens are single-use — nine endpoints each
  refreshing on their own 401 would revoke the grant outright.
- **Vascular age is a second opinion, not an input.** Oura's estimate became its
  own `MetricType.vascularAge` rather than being merged into `HeartAgeInsight`'s
  own calculation. Two models built on different inputs disagreeing is
  information; averaging them away is not. VO₂max went the *other* way — Oura's
  joins the existing `.vo2Max` metric as another source, matching how heart rate
  and weight already work.
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

## The sandbox has a Swift toolchain now — use it

This section used to say the opposite, and that was the single most expensive
false belief in the repo: it meant every logic error was found by pushing and
waiting ~90 s for CI.

`InsightKit` was always meant to be platform-free, but two Darwin-only
Foundation APIs had crept in (`Measurement.formatted` and `CFBooleanGetTypeID`)
and CI runs on macOS, so nothing caught them. Both are behind
`#if canImport(Darwin)`. **The full suite passes on Swift 6.0.3 / Ubuntu 24.04** — `swift test` prints the count, so it is not repeated here to rot.

```bash
./scripts/verify.sh --tests     # installs the toolchain if absent, then runs
```

The container is rebuilt per session so the toolchain never survives, but the
gate **self-heals**: `verify.sh --tests` bootstraps Swift itself rather than
telling you to. Nothing depends on this document being read. Better still, put
`./scripts/bootstrap-swift.sh || true` in the environment's setup script and it
costs no session time at all — see `docs/deployment.md`.

`xcodebuild` is still macOS-only, so the **app target** is compiled only by CI.
Local green means InsightKit is green: the clinical maths, scoring, baselines
and parsers — which is where the bugs have actually been.

Still worth care, because nothing local checks them: key paths don't work on
tuple elements (`\.volume` on a tuple is a compile error — use `{ $0.volume }`),
and don't shadow a function with a local of the same name. `scripts/verify.sh`
checks the first of those.

Adding a `MetricType` or an `InsightID` case is deliberately load-bearing: both
feed exhaustive switches. **This bit CI again this session** — `.vitalSigns` was
added to the engine and cadence but not to the four switches, so the build broke.
The complete list, verified by grepping for the enum's last case:

- `MetricType` — **eight** switches: `displayName`, `unit` (both in
  `MetricType.swift`),
  **`family`**, **`chartStyleIndex`**, `presentation`, `maxValidInterval` (all
  four in `MetricPresentation.swift`), **`referenceRange`** (also
  `MetricPresentation.swift` — usually `nil`, and the case must say *why*;
  `.sleepOnset` is the worked example), `requiresPositiveValue`
  (`Signals/MetricSanitizer.swift`). `bucketStatistic`, `inSentence` and
  `MetricValueFormatter` are safe — the first has a `default:`, the second is
  derived from `displayName`.
  `colourSlot` and `sharesMeasurementBasis` are **derived**, not switches, so
  they no longer need touching. `chartStyleIndex` must stay contiguous from zero
  (`testStyleIndicesAreContiguousFromZero` pins it) so the metrics most likely to
  share a chart keep first claim on the eight hues.
- `InsightID`: **five switches, not three** — this list was itself stale and is
  now verified. `cadence` (`Insight.swift`), `modelVersion` (`Feedback.swift`),
  `prettyInsight` (`TelemetryOutboxView`), `iconName` (`DashboardView`),
  `colourSlot` (`Presentation/InsightPalette.swift` — *not* `insightTint` in
  `Theme.swift`, which now resolves through it). **Four of the five are
  exhaustive and break the build**: `modelVersion`, `prettyInsight`, `iconName`,
  `colourSlot`. Only `cadence` carries a `default:`, and it fails *silently* by
  putting the card on the wrong tab. Plus registration in `InsightEngine`, which
  breaks nothing and simply makes the card never appear.
  **Use the `add-insight` skill rather than this summary.**
  **`primaryMetric` in `InsightDetailView` is gone** — the detail screen now
  charts `InsightResult.contributors`, which the scoring code emits itself, so
  that switch no longer exists to fall out of date.

Adding an `InsightModel` also requires `candidateMetrics` (no default
implementation, so it won't compile without one). `MetricColourSlotTests` no
longer depends on what co-occurs — it asserts that *any* set up to the palette
size resolves to distinct hues, so adding a metric to an insight can't break it
from a file that never mentions colour. That was deliberate: the previous version
encoded a belief about co-occurrence, and the belief shipped wrong.

Do this grep *before* pushing, because CI is the only thing that will tell you.

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

## Lesson worth keeping: don't let a guess pre-empt the authority

The scope skip described above cost the user a deploy cycle and a round of
pointless account-fiddling (revoking an Oura authorisation that was already
correct). The app *inferred* that a permission was missing and acted on the
inference by not making the call — which destroyed the evidence that would have
shown the inference was wrong.

Rule: when a remote system is the authority on whether something is permitted,
ask it. A local prediction may inform a warning; it must never replace the
request. This is the same failure shape as the `tunnelState` guard below.

## Immediate next steps

**Hydration was ~12 s on the user's data. The insight half of it is now 3.7×
faster, and the question this section used to ask does not need asking.**

It said a decision was needed first — whole history, or a recent window with the
rest loaded behind Today? — because every cheap fix was assumed to change what
the first frame knows. **That premise was wrong, and measuring it is what showed
so.** The cost was never the *volume* of data. It was the same work done over
and over: `MultiSource.breakdown` filtered all ~130k samples and sorted the
result on every call, `Array.samples(of:)` did the same, and both were called
once per metric *per insight model* — resting heart rate is read by seven of the
seventeen. Nothing about that work varies between the models.

So there was no tradeoff to put to the user. Fixed with three semantics-
preserving changes, all in InsightKit, all covered by `EvaluationMemoTests`:

- **`EvaluationMemo`, scoped to one evaluation pass** (`MultiSource.withMemo`,
  opened by `InsightEngine.evaluateAll` and `result(for:)`). Memoises
  `breakdown`, `Array.samples(of:)` and the per-source daily buckets. It is a
  `@TaskLocal`, so it lives exactly as long as the evaluation and can never go
  stale against changed data.
- **The day-bucket reuse in `SourceSeries.bucketed`.** It asked
  `Calendar.dateInterval(of:for:)` once per sample — ~400 ms of a ~470 ms
  heart-rate read. Series arrive sorted, so it now holds the previous reading's
  interval and reuses it while the next reading still falls inside.
- **The redundant re-sort in `breakdown`** — `deduplicate` already returns
  oldest → newest and `Dictionary(grouping:)` preserves that order, so each
  group was being re-sorted for nothing (78k elements, for heart rate).

Measured on a synthetic 131,400-sample / 24.7 MB set, the same benchmark either
side of the change (x86 Linux, so read the *ratios*, not the absolutes):

| stage | before | after |
| --- | --- | --- |
| `loadCachedSamples` (JSON decode) | 1002 ms | 1002 ms |
| `sanitizedVitals` + temperature | 21 ms | 19 ms |
| `evaluateAll` (17 models) | 1774 ms | **476 ms** |
| total | 2796 ms | **1564 ms** |

**Two things to carry, and one thing left.**

- **"This needs a product decision" is a claim about the implementation, and it
  can be wrong.** Exactly the shape of "no provider gives us a bedtime": a
  tradeoff recorded as inherent turned out to be an artefact of how the code was
  written. Measure before escalating a decision to the user.
- **The memo's identity check is sound, not a fingerprint.** It holds a strong
  reference to the array it was opened for, so that buffer cannot be freed while
  the memo lives, so no *other* live array can be handed its base address. Equal
  base address and equal count therefore means the same buffer, and by
  copy-on-write the same contents. Anything else misses and is computed the long
  way. `testMemoDoesNotAnswerForADifferentArray` and
  `testEqualLengthCopyIsNotTreatedAsTheSameArray` pin it.

**What is left is the decode, and it is now 68% of the remaining time.** The
JSON is ~190 bytes per sample, and most of that is repetition: a full `UUID`
string and a `{id, displayName}` source object written out for every single
reading, when there are only a handful of distinct sources. Interning the source
table would cut both the file and the decode substantially. That one *does* need
the user, because it changes the on-disk cache format and so needs a migration
path — the existing format has a test pinning it (`RawValue` as a bare JSON
scalar) for exactly this reason. **Ask before building that one.** Note the
measured dead end: `PropertyListEncoder(.binary)` is *slower* than JSON here
(2190 ms vs 1026 ms), so "just use a binary cache" is not the answer.

The ten-item feedback list is closed and so is every roadmap item that could be
closed from a sandbox. What remains falls into three groups.

### 1. Only the user can do these

- **The on-device walkthrough.** The launch screen and Insights *have* now been
  seen and reported on — that is how every defect in session 11 was found. The
  older items below still have not. Newest first:
  - **Cold launch — time it, and this is the one still genuinely unknown.**
    Confirmed already, from the user's own screenshots: no white screen, the
    heart draws, the animation is smooth, Insights no longer freezes. What has
    *not* been confirmed since the last three changes is the timing.
    From tapping the icon: flat `#D9D9D9` (that is `UILaunchScreen`, before any
    code), then the heart — dense rose mist, drifting slowly, ring framing the
    screen — then Today, populated, with the sync spinner still turning.
    **A sync finishing after Today appears is correct now, not a bug.**
    The negatives are the ones worth the trouble: **background the app and
    return — the splash must not come back**; a first-run install must go
    straight to onboarding with no splash; the status line must not strobe; and
    the heart must not flash at the wrong size on the handover from the static
    launch screen (it did, at 3×, when the poster was in the asset catalog's 1x
    slot — hence colour-only now).
    Past ~4 s the copy should change register entirely ("Still going — that's a
    lot of history to read"), and nothing should hold the screen past 8 s.
  - **If the launch screen is a plain grey rectangle with text and no heart**,
    the Metal shader compiled on CI but failed at runtime on the device. It
    logs to Settings ▸ Troubleshooting rather than failing silently — that is
    the first place to look, and it is the one part of the renderer no test
    here can reach.
  - **Insights ▸ Sleep Regularity ▸ "Your fortnight"** — a new chart above the
    score history. Points are the nights, the dashed line is the usual bedtime,
    the shaded band is the spread. Check the y axis reads **clock times** and not
    bare numbers (a "−1.5" there is the signed-hours encoding leaking); that
    weekend nights are squares and weekdays circles; that the night the card
    names as "furthest out" is the enlarged point; and that a second dashed line
    appears only when there is a real weekend shift.
  - **Energy ▸ Today** — an area chart of the day's curve with a dashed line at
    the morning charge, and "N spent of M" in the header. Check it renders before
    the score history, and that scrubbing reads the hour.
  - **Insights ▸ Sleep Regularity** — a new card. Check it appears at all (it
    needs five nights with a recorded sleep time), that the headline reads like
    "Regular · 23:10", and that the weekend line only shows when there is a real
    shift.
  - **Any vital chart with substance logs behind it** — faint grey vertical
    columns for the 18 hours after each log, merged where they overlap, with the
    caption underneath. Confirm they do *not* look like the horizontal reference
    bands on the same chart.
  - **An insight detail overlay with a gap in one series** — the gap should now
    cross with a dashed connector, visibly dimmer than the measured line either
    side of it.
  - **Vitals ▸ Sleep & recovery** — a "Sleep Onset" row, rendering as a clock
    time rather than a number.
  - **The overlay chart** — no two drawn lines share a colour; steady signals
    are off the chart by default and in the list below it, ordered most-departed
    first and each row tappable; more than eight selected shows the "colours
    repeat" warning rather than repeating them silently.
  - **Heart & Fitness Age** opens with both ages plotted against the
    chronological line, and the pace sentence reads as "gaining on it" / "running
    ahead" rather than a bare slope.
  - **Blood pressure** shows shaded systolic bands with the diastolic limits as
    thin rules, and the caption explaining which is which.
  - **"What's driving this"** leads with departures and folds the routine lines
    behind the disclosure.
  - **Vitals Check** on Today reads "All normal" on a quiet day and names the
    outlier when there is one; **Other data** renders Oura's resilience `level`
    as text with a States tally rather than an empty chart; Cardio Fitness shows
    two sources (Apple Watch + Oura); Heart Age prints Oura's vascular age line;
    Body Composition shows lean/muscle/bone/water with the fat-vs-muscle
    narrative.
  - **The paste prompt is gone** from Settings ▸ Data sources ▸ Oura. Clipboard
    autofill was removed because reading `UIPasteboard` raised iOS's "Paste from
    your Mac?" prompt on every appearance. Do not reintroduce clipboard *reads*
    there; writes (Copy buttons) are fine.
  - Oldest: the three-age row on Heart & Fitness Age (narrowest device); a
    profile with no blood pressure showing the fitness half alone; Heart Rate at
    `All` *and* `Y`; Weight's gap-broken line and weekly velocity; provenance
    badges and the Inactive section; drag-to-scrub; Height as a plain card; blood
    pressure from all three entry points.
- **Whether Oura's ~4–6 months of history is an account boundary or a re-pair.**
  A 730-day window returns 171 sleep records, 128 daily_activity, 107
  daily_readiness, with **no `next_token`** — so that is genuinely all Oura will
  serve, and pagination (now implemented) will not change it. Apple Health holds
  128,302 Oura-mirrored samples. Byte counts match record counts, so nothing is
  truncated client-side. Offered several sessions ago, not taken up.
- **New provider integrations** (Hume direct, Ultrahuman, Garmin, Fitbit). Each
  needs the user's own developer credentials, and nothing about them can be
  exercised from a sandbox.

### 2. Deliberate non-decisions, with the reasoning recorded

- `EnergyModel.exertionHours` weights every heart-rate sample equally. Crude, and
  says so; real inter-sample intervals need a decision about what a gap means.
- `AppModel.swift` and `InsightDetailView.swift` stay unsplit — see above.
- ~~Filled `AreaMark` min/max bands still want a compile spike.~~ Done — see
  above; `AreaMark(x:yStart:yEnd:)` ships in `BodyCompositionTrendChart`.
- `.sleepOnset` resolves against `Calendar.current`, not the offset the provider
  stamped. Right at home, wrong on the second night of a trip. Both HealthKit and
  Oura behave the same way, so the sources at least agree with each other.

### 3. The ten-item feedback list — five of the six deltas are closed

The six open clauses found by re-reading the list are now closed, bar the LiDAR
body scan, which is a roadmap note by request rather than a build. What is worth
carrying forward:

- **"That technique has a fatal flaw" is not "this is impossible".** Gap
  bridging shipped straight rather than smoothed, with a written argument that a
  curve invents a local extremum where nothing was measured. The argument is
  correct about Catmull-Rom and natural cubics and was mistaken for an argument
  against curvature. A monotone cubic Hermite (Fritsch–Carlson / PCHIP) cannot
  have an interior extremum at all, which is exactly the missing guarantee. The
  gap between those two claims was a shipped deviation from an explicit
  instruction.
- **A relative threshold needs an absolute companion.** This bit three times in
  one session, each time the same shape: a small denominator makes anything
  significant. Blood-pressure drift floored at ±5 mmHg because a fit through a
  handful of points claimed zero uncertainty; the substance suggestion floored
  at 3% because a tight set of clean nights makes a fifth of a bpm clear half a
  standard deviation; `ScoreChange` floored at two points for the same reason.
- **"Completed" did not need defining per suggestion.** Three bases would have
  needed three different answers. None was necessary — the engine only emits a
  suggestion while its condition holds, so disappearing from its output *is*
  resolution, by whichever route. When a feature seems to need per-case rules,
  check whether the generator already encodes them.
- **The trend indicator is not "vs yesterday", and that was researched.** Nobody
  ships it: day-to-day HRV noise (3–13%) swamps what one night changes. See
  `docs/progress.md` ▸ "How trend indicators are rendered".
- **A slow tap was one call doing far too much.** Logging a substance ran the
  whole insight engine over the whole sample set and dropped every cache. When a
  cheap-looking interaction is slow, look for the shared recompute it is reusing
  rather than for the work it obviously does.

### 4. What the six deltas turned into

Re-reading the ten-item feedback list against the code found six clauses still
open, each sitting *inside* an item whose headline was true — which is why none
was visible from the record. **Five are now closed; one is parked deliberately,
and a seventh was added by the user.**

| # | Clause | State |
| --- | --- | --- |
| 1 | Suggestion lifecycle — dismissible, on Today, pinned/collapsible on Insights, hidden once resolved | ✅ |
| 2 | Smoothed predicted values across gaps | ✅ monotone cubic, both charts |
| 3 | Blood-pressure drift counter | ✅ held-out, floored at ±5 mmHg |
| 4 | Sleep Quality's remaining Oura/Whoop/Apple inputs | ✅ efficiency, deep, REM |
| 5 | Substance log as a general data source | ✅ feeds the suggestion engine |
| 6 | Camera + LiDAR guided body scan | ⬜ roadmap note by request, scoped in `progress.md` |
| 7 | App-launch loading screen | ✅ `LaunchScreen` + tested `LaunchNarration` |

Plus three direct complaints, all fixed: the substance log page's lag (one call
running the whole engine over the whole sample set), the date picker hidden
behind a long-press, and an edit button under the minimum tap target.

**Lesson worth keeping: a multi-clause item marked `[x]` hides its unfinished
clauses.** Every one of the six sat inside an item whose headline was true. When
a feedback line has an "and also" in it, record the clauses separately.

### 5. Genuinely open work, cheapest first

The two cheapest items here — Sleep Regularity's own chart, and sleep onset
through the promotion rules — **are done**; see `docs/progress.md` ▸ "The
roadmap-review session". Two findings from them are worth carrying:

- **A guard whose comment states a premise is a place the premise can be wrong.**
  `IngestionPipeline` promoted on `field.value.doubleValue`, commented "promotion
  is numeric by definition". That was true of every metric until `.sleepOnset`,
  which derives from a timestamp — and the failure mode was not an error but a
  rule that matched and promoted nothing. The one-line version of the roadmap
  item (add `bedtime_start` to the alias table) would have shipped looking
  correct. **When adding a row to a data table, check that the machinery reading
  it can represent the new row's type.**
- **Check whether the field survives ingest before writing a rule for it.**
  `GenericJSONIngestor` excludes `startDateKeys` from the field sweep, and
  `bedtime_start` is one of Oura's. A promotion rule aimed at it would match
  nothing forever, silently. Recorded in `PromotionRules.swift` beside the
  aliases.

Still open:

- **Foundation Models structured extraction for arbitrary lab analytes**, and the
  VisionKit live scanner. Both are on the roadmap and both are device surfaces
  with no test path from here.
- **Core ML personal anomaly detection**, once there is enough history.


