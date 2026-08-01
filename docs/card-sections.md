# Card sections — what each screen actually renders

_Audit of record. Re-derived 2026-07-31 after the consolidation from seventeen
insight cards to nine, and again 2026-08-01 after the section order changed.
Every cell was read out of the code._

Written because the app had three families of card-based screen and no record of
which sections each shows. The first pass found eight inconsistencies; five were
closed in Phase 1. Then the count itself turned out to be the real problem —
seventeen cards with three built on VO₂max, three on sleep duration and three
scanning the same baselines — and they were merged to nine.

**Phase 2 is done** as of 2026-08-01 (`dc5fae6`), bar Body Composition's
"view & add" scan entry, which the user deferred to its own session — see
"Still open" ▸ 10.

---

## 1. Insight detail screens

One file renders all nine: `HealthInsights/Features/Insights/InsightDetailView.swift`.
Its `body` is a fixed sequence. Nothing is per-insight except the gates.

### The sections, in render order

| # | Key | Section | Gate |
|---|---|---|---|
| 1 | `Hdr` | header — dial or headline, confidence badge, explanation | always |
| — | *picker* | the timeframe control — a screen-level control, not a card | **always** |
| 2 | `ScrHx` | **"Score over time"** — the first section on every card | **always** |
| 3 | `Drv` | "What's driving this" | **always** |
| 4 | `Wgt` | "How this is weighted" — arrives **closed** | **always** |
| 5 | *bespoke* | the card's own picture of its own subject | one `switch`, all nine cards |
| 6 | `Patt` | "Patterns worth a look" — arrives **closed** | **always** |
| 7 | `1st` | "What comes first" — lag, arrives **closed** | **always** |
| 8 | `Goes` | "What goes into this" — overlay, scale picker, legend | **always** |
| 9 | `Chg` | "What changed" — period contrast | **always** |
| 10 | `Hist` | "Full history" — one link per input | contributors non-empty — but `candidateMetrics` is never empty (`ContributorsTests`), so in practice always |
| 11 | `V&A` | "View & add" — what you've given, what's missing, how to add | the model's `contributions` is non-empty |
| 12 | `Fbk` | "Was this accurate?" | `primaryValue != nil` |
| 13 | `Disc` | disclaimer | always |

**Reordered 2026-08-01, on the user's reading of the shipped screens.** Three
moves, each with its own reason:

- **The two findings sections came up**, from below "What goes into this" to
  directly under the score they are findings about. They used to sit behind a
  chart, a scale picker and a thirteen-row legend — so the one part of the
  screen that had already read the data *for* the reader was the part hardest to
  reach.
- **"View & add" went down**, from third to second-from-last, beside "Was this
  accurate?" — the other thing the screen asks *of* the reader rather than tells
  them. It is not a daily concern, and it was sitting ahead of every finding on
  a screen nobody opens in order to type.
- **The timeframe picker lost its gate.** `usesTimeframe` hid it where nothing
  read the window; both findings sections now always render and both read it. It
  also hid it in the one case where widening the window is the *remedy* — a card
  with no series — which left `SectionPlaceholder` pointing at a control that
  wasn't on screen.

Two more moves later the same day, again on the user's reading of the screens:

- **"Score over time" is now the first section on every card**, above "What's
  driving this" and above the bespoke slot. The rule it replaces — bespoke
  first, because the card's own subject is the finding and the months of scores
  derived from it are supporting context — was a reasonable call and is simply
  not the one the user wants. The timeframe picker moved up with it, because it
  has to sit above every section that reads the window.
- **"How this is weighted" left the bespoke slot and became universal**, closed
  by default like the two findings sections. See below for why an empty one is
  worth drawing.

### Every section closes; only some arrive closed

Sections 2–10 are all `InsightSection`, and **every `InsightSection` has a
chevron**. The two that do not — `V&A` and `Fbk` — are plain `Card`s and were
excluded by the user by name, which is also why nothing had to be opted out: the
capability comes from the container, and those two were never in it.

*Collapsed* and *collapsible* were the same thing until 2026-08-01, and the bug
that exposed the difference is worth keeping. "Score over time" was collapsible
only while it was **empty**, because the view passed `.collapsed` for the
placeholder and `.always` for the chart — so the reader could close the section
that had nothing in it, and then lost the chevron the moment the replay landed
and it had something. `SectionExpansion` is now a struct whose `startsExpanded`
says only what the section does before anyone touches it.

Which arrive closed: `Wgt`, `Patt`, `1st` always, plus **any section with
nothing to show**, which shows its `SectionPlaceholder` headline as the preview
line. Everything else arrives open. A section that arrives open has no preview:
`trailing` is already the one number worth opening it for, and somebody who
closed a section themselves does not need telling what they closed.

**The reader's choice is a `Bool?`, not a `Bool`.** `startsExpanded` is derived
from data that lands *after* the first render, so a plain flag would either
freeze a section at whichever state it was born in, or reopen one the reader had
deliberately closed each time new data arrived. Three states, because there are
three: closed by the reader, opened by the reader, and not yet asked.

### The matrix

**Key** — `●` always renders · `◐` renders once the data clears a floor ·
`○` cannot ever render.

| Insight | Tab | `Hdr` | `ScrHx` | `Drv` | `Wgt` | bespoke | `Patt` | `1st` | `Goes` | `Chg` | `Hist` | `V&A` | `Fbk` | `Disc` |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Readiness | Today | ● | ● | ● | ● | ◐ "How far from your normal" | ● | ● | ● | ● | ● | ○ | ◐ | ● |
| Sleep | Today | ● | ● | ● | ● | ◐ "Your fortnight" | ● | ● | ● | ● | ● | ○ | ◐ | ● |
| Energy | Today | ● | ● | ● | ● | ◐ "Today" curve | ● | ● | ● | ● | ● | ○ | ◐ | ● |
| Substance Impact | Today | ● | ● | ● | ● | ◐ "Cardiovascular load" | ● | ● | ● | ● | ● | ● | ◐ | ● |
| Heart Health | Insights | ● | ● | ● | ● | ◐ "How you compare" | ● | ● | ● | ● | ● | ● | ◐ | ● |
| Fitness | Insights | ● | ● | ● | ● | ◐ "Fitness age over time" **+ "Where this is heading"** | ● | ● | ● | ● | ● | ● | ◐ | ● |
| Heart Attack & Stroke Risk | Insights | ● | ● | ● | ● | ◐ "Heart age over time" **+ "If today's numbers hold"** | ● | ● | ● | ● | ● | ● | ◐ | ● |
| Blood Pressure | Insights | ● | ● | ● | ● | ◐ "Your readings" | ● | ● | ● | ● | ● | ● | ◐ | ● |
| Body Composition | Insights | ● | ● | ● | ● | ◐ "What you're made of" + "How that has changed" | ● | ● | ● | ● | ● | ● | ◐ | ● |

**The bespoke slot is still one slot.** Three cards draw two things in it,
separated by a `Divider()` and wrapped in `NestedInsightSection` — the pattern
Body Composition established. A second *top-level* section would have needed a
second placement rule, and the one placement rule is the thing Phase 1 bought.

It was five until 2026-08-01. Heart Health and Readiness had their centile strip
and their departure panel nested under "How this is weighted", which was their
bespoke section — and when that section went universal *and closed by default*,
those two strips would have arrived hidden inside a collapsed generic section.
**A card's own picture of its own subject must not be something you have to open
a shared section to find**, so both were promoted into the bespoke slot itself.

**Every card renders the same sections, in the same order, always.** Three
deliberate exceptions remain, each about the *card* rather than about the data:

- **`V&A` reaches six.** The three without it — Readiness, Sleep, Energy — ask
  the user for nothing and are built entirely from sensed data. "Add a reading"
  on a card that takes none is a control that can never do anything.
- **The bespoke slot is per-card by construction** — it is the card's own
  picture of its own subject, so there is nothing generic to draw in its place.
  It reaches all nine, and five cards draw *two* things in it, nested under one
  `Divider()`.
- **`Fbk` needs a number to rate.** "Was this accurate?" on a card showing no
  value is a control with no subject, and feedback recorded against nothing
  pollutes the telemetry the models are tuned on.

### Why the rest are `●` with nothing to show

They were all `◐` until 2026-08-01, and the floors are high: two scored days for
`ScrHx`, fourteen paired days for `Patt` and `1st`, seven days in each of two
windows for `Chg`. Measured rather than assumed — a replay over a realistic
five-signal dataset gives **four of the nine cards zero score-history points** —
so "Score over time" was absent more often than present, and its absence read as
the chart having been taken away.

**A section that vanishes is an absence the reader cannot read.** "Score over
time" missing means the 90-day replay hasn't finished, *or* no day has had two
of this card's signals recording at once, *or* exactly one has. Only somebody
holding the source could tell those apart — and the first fixes itself in a
second while the third is one day away.

`SectionPlaceholder` (InsightKit, tested) works out which applies, from the same
floors the section's own producer gates on — `ScoreHistory.minimumContributors`,
`PatternFinder.defaultMinimumPairs`, `PeriodContrast.minimumDaysPerPeriod` — and
quotes the actual shortfall, so "not enough data yet" can never appear under a
card holding two years of it. An empty section arrives **collapsed** with the
reason as its preview; `Patt` and `1st` arrive collapsed either way, previewing
their strongest finding. See `SectionExpansion`.

**"How this is weighted" is the one where empty is a fact about the card, not
about the data.** Only Heart Health, Readiness, Sleep and Energy blend their
components in fixed proportions. Cardiovascular Risk runs published equations,
Blood Pressure runs an estimator, Substance Impact reports what each signal did
after a logged event — all three report contributors at **weight 0 on purpose**,
and that deliberate zero was previously invisible because the section simply
wasn't drawn. It now says "Not a weighted average" and points at the two
sections that do carry the per-signal detail. `SectionPlaceholder.weighting`
distinguishes that from a model reporting no contributors at all, which is a
different statement again — see `ChartedContributions`.

The collapsed preview for a card that *does* weight names the heaviest signal,
and `[MetricContribution].weightingPreview` refuses the superlative on a tie:
`byInfluence` breaks ties by name, so on six equal Readiness components the
first is not "the most", and saying so would be false.

**The `isComputing` arm is the one that earns its keep.** `AppModel.scoreHistory`
returns `[]` on first ask and replays off the main actor, so a card opened cold
is genuinely empty for a second or two. "No scored days yet" there would be a
false statement that corrects itself only after the reader has read it;
`AppModel.scoreHistoryIsPending(for:)` is what stops it being said.

That the bespoke line above once said "reaches six" while item 7 under "Still
open" in this same file said all nine had one is worth keeping in view: **a file
disagreeing with itself, written in one session and half-updated in it** — the
polarity handover step 11 exists to catch, and the one that keeps getting
skipped, because a claim that something is *missing* is exactly what the work
invalidates.

### Per-insight facts behind the matrix

| Insight | `cadence` | Grounding | `contributions` | Absorbed |
|---|---|---|---|---|
| Readiness | daily | 0 | — | Vitals Check, Health Watch |
| Sleep | daily | 0 | — | Sleep Quality, Sleep Debt, Sleep Regularity |
| Energy | daily | 0 | — | — |
| Substance Impact | daily | 0 | `.substanceLog` (override) | — |
| Heart Health | trend | 2 | `.groundingFacts` | Where You Stand (centiles), Resting HR |
| Fitness | trend | 2 | `.groundingFacts` | Cardio Fitness, Fitness Trajectory, fitness age |
| Heart Attack & Stroke Risk | trend | 10 | `.groundingFacts` | heart age |
| Blood Pressure | trend | 2 | `.bloodPressureReadings` (override) | — |
| Body Composition | trend | 2 | `.groundingFacts` | — |

**The maths of every merged card was kept**, as components with their own tests:
`VO2Trajectory`, `FitnessAgeModel`, `HeartAgeAnalyser`, `SleepDebtModel`,
`CircadianConsistencyModel`, `VitalSignsCheck`, `HealthWatchModel`,
`PeerStandingModel`. Only the wrappers and their `InsightID`s went.

### Signals the merge newly wired in

`dayStrain` reached **no insight at all**; `heartRateRecovery` and
`walkingHeartRateAverage` reached only the vitals scanner, never a score. All
three are now on Fitness. They contribute at **weight 0** — real signals worth
charting, but no validated 0–100 curve exists for them here, and an invented
weight inside a score the user is asked to trust is worse than none.

The absolute temperatures (`skinTemperature`, `bodyTemperature`) joined Sleep
for the same reason: the card read the *deviation* and nothing read the absolute,
which on a device reporting only the absolute was the whole signal.

---

## 2. Metric detail screens

`MetricDetailView` switches on `subject.presentation` into three structurally
different bodies. Unchanged by the consolidation.

| Section | `cumulativeTrend` | `fluctuatingRange` | `cumulativeTotal` | `discreteBivariate` | `staticAttribute` |
|---|---|---|---|---|---|
| summary card | Change over this period | Range over this period | Daily totals | ○ | current value |
| timeframe picker | ✅ | ✅ | ✅ | ✅ | ○ |
| chart | `MultiSourceChart` | ✅ | ✅ | `BloodPressureChart` (shared) | ○ |
| per-source breakdown / averages | ✅ | ✅ | ✅ | ○ | ○ |
| reference range + provenance | ✅ | ✅ | ✅ | in the chart's legend | ○ |
| substance-window shading | ✅ | ✅ | ✅ | ○ | ○ |
| log-scale toggle | ○ by presentation | ✅ | ✅ | ○ | ○ |
| calibration · history · add | ○ | ○ | ○ | ✅ | Earlier entries |

---

## 3. List, tab and settings surfaces

| Surface | Cards, in order | Which insights it lists |
|---|---|---|
| **Today** | summary · suggestion · Last night · Vitals glance · 4 daily tiles | `cadence == .daily && isWorthShowing` |
| **Insights** | "Improve your health" · subtitle · score comparison · 5 trend tiles | `cadence == .trend && isWorthShowing` |
| **Vitals** | 4 metric groups · Blood pressure · Substances · Other data | rows, not cards |
| **Settings ▸ Export my data** | inventory (Markdown) · full export (JSON) · browse the unmodelled | the development feedback loop |

**Today lost "Improve your insights" on 2026-08-01.** `GroundingPromptBanner`
listed the same grounding gaps that `SuggestionEngine.unlocks` already emits as
`.unlockAnInsight` — reaching the reader twice, through the dismissible
`suggestionCard` on Today and the full "Improve your health" list on Insights.
Two surfaces for one set of facts, and only the suggestion could be dismissed,
so waving a prompt away on Today left the same prompt on Today.

The one thing the banner said that the suggestions did not — that a fact was
**stale** rather than absent — moved into `unlocks` rather than going with it.
`unmetRequirements` is "not satisfied", which covers both, and "add your
cholesterol" to someone who added it last year reads as the app having lost it.
`AppModel.outstandingGrounding` went too; the engine's own remains.

---

## 4. The gaps

### Closed

1. The timeframe picker is a screen-level control, not trapped inside "Score
   over time" — which it outlived by three sections.
2. "What comes first" / "What changed" lost their cadence gate.
3. One placement rule for the bespoke slot, above "Score over time".
4. Both tabs share one listing rule, `InsightResult.isWorthShowing`.
5. One "View & add" section on every card that takes input, and blood pressure's
   chart on the card that talks about it.
6. **Seventeen cards became nine.** The overlap *was* the inconsistency.

### Still open

7. ~~**Three cards have no bespoke section**~~ — **closed.** All nine now have
   one. Heart Health and Readiness share `weightedContributionCard` ("How this
   is weighted"), drawn from `InsightResult.contributors`' renormalised weight —
   no new type and no model change, exactly as Phase 2 predicted. Body
   Composition got "What you're made of", backed by `BodyCompositionSplit` in
   InsightKit (12 tests). **The bespoke switch keeps its `default:`** even though
   all nine cases are now named: making it exhaustive would add a sixth
   build-breaking switch over `InsightID`, which `activeContext.md` singles out
   as the most expensive way to add a feature here.
8. ~~**Caveat footnotes and header trailing stats are ad-hoc.**~~ **Closed
   2026-08-01** (`dc5fae6`). Every section now goes through `InsightSection`
   (or `NestedInsightSection`), which carries the title, at most one figure and
   the caveat, at one spacing and one footnote colour.

   **The rule is enforced by the compiler, not by a convention.** `caveat` has
   no default value, so a section cannot be written without stating one and
   `.none` is a visible choice. The previous convention was followed by four
   sections out of twelve, and the one it was skipped on — "What comes first",
   a correlation at a lag fitted through however many days two series overlap
   on — was the most inferential claim on the screen.

   The words are `SectionCaveat`, in InsightKit, with tests. Two defects fell
   out of moving them there: the body-composition caption opened *"Height is
   your weight"*, and it pluralised "across 1 weigh-ins".

   The trailing slot now carries **one quantity**. It used to show a kilogram
   delta *or* a count of weigh-ins in the same position on the same card.
9. **Two presentation flags no view consults** —
   `MetricPresentation.allowsTimeframeSelection` and `.showsChart` are read only
   by `PresentationTests`.
10. **Body Composition's "view & add" scan entry** — a fourth
   `ContributionRoute`. Deferred by the user on 2026-08-01 to its own session.
   The capture it points at is the camera + LiDAR body scan, which is
   deliberately a roadmap note and is ARKit, so it cannot be exercised from a
   sandbox at all. Adding the case touches `ContributionRoute`, the exhaustive
   switch in `ViewAndAddSection.section(for:)`, an override on
   `BodyCompositionInsight` returning *two* routes, and the skip list in
   `ContributionRouteTests.testGroundingFactsAreDerivedFromTheModelsOwnRequirements`.

11. ~~**The legend under "What goes into this" stated one fact out of three.**~~
   **Closed 2026-08-01.** Each row printed whichever of *direction*, *is that
   direction good* and *weighting* an `if` reached first: the weight where there
   was one, the trend otherwise, and the good-or-bad verdict only where the
   model had declared a direction. So which of the three was missing varied row
   to row, with nothing on screen to say which. All three now render on every
   row, of every legend, on every card — `LegendCaption`, in InsightKit.

   The interesting part is what fell out of it. `weight: 0` and
   `higherIsBetter: nil` are real *findings* in some rows — `dayStrain` is
   deliberately unscored, a temperature deviation deliberately has no good
   direction — and pure *absences* in others, because
   `InsightDetailView.resolvedContributions` substitutes an insight's declared
   inputs when it reports none, and the stand-ins carry exactly those values.
   Rendered naively, every row of such a card announces itself as "tracked, not
   scored · neither direction is better", two claims no model made. **Substance
   Impact before its first logged event is the live case**, found by a test
   written for something else. `ChartedContributions` carries the distinction
   now; `ContributorsTests` pins that Substance Impact is the only insight that
   reaches it.

---

## How to keep this current

- **Columns** come from `InsightDetailView.body`.
- **Rows** come from `InsightID.allCases` — nine — see the `add-insight` skill.
- **Cell values** come from each model's `InsightResult` plus its `requirements`
  and `contributions`.

`docs/activeContext.md` and `docs/progress.md` remain the authority on *why*.
