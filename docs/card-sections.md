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
| 2 | `Drv` | "What's driving this" | **always** |
| 3 | *bespoke* | the card's own picture of its own subject | one `switch`, all nine cards |
| — | *picker* | the timeframe control — a screen-level control, not a card | **always** |
| 4 | `ScrHx` | "Score over time" | **always** |
| 5 | `Patt` | "Patterns worth a look" — **collapsed by default** | **always** |
| 6 | `1st` | "What comes first" — lag, **collapsed by default** | **always** |
| 7 | `Goes` | "What goes into this" — overlay, scale picker, legend | **always** |
| 8 | `Chg` | "What changed" — period contrast | **always** |
| 9 | `Hist` | "Full history" — one link per input | contributors non-empty — but `candidateMetrics` is never empty (`ContributorsTests`), so in practice always |
| 10 | `V&A` | "View & add" — what you've given, what's missing, how to add | the model's `contributions` is non-empty |
| 11 | `Fbk` | "Was this accurate?" | `primaryValue != nil` |
| 12 | `Disc` | disclaimer | always |

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
  with no series — which left `FindingsPlaceholder` pointing at a control that
  wasn't on screen.

### The matrix

**Key** — `●` always renders · `◐` renders once the data clears a floor ·
`○` cannot ever render.

| Insight | Tab | `Hdr` | `Drv` | bespoke (+ nested) | `ScrHx` | `Patt` | `1st` | `Goes` | `Chg` | `Hist` | `V&A` | `Fbk` | `Disc` |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Readiness | Today | ● | ● | ◐ "How this is weighted" **+ "How far from your normal"** | ● | ● | ● | ● | ● | ● | ○ | ◐ | ● |
| Sleep | Today | ● | ● | ◐ "Your fortnight" | ● | ● | ● | ● | ● | ● | ○ | ◐ | ● |
| Energy | Today | ● | ● | ◐ "Today" curve | ● | ● | ● | ● | ● | ● | ○ | ◐ | ● |
| Substance Impact | Today | ● | ● | ◐ "Cardiovascular load" | ● | ● | ● | ● | ● | ● | ● | ◐ | ● |
| Heart Health | Insights | ● | ● | ◐ "How this is weighted" **+ "How you compare"** | ● | ● | ● | ● | ● | ● | ● | ◐ | ● |
| Fitness | Insights | ● | ● | ◐ "Fitness age over time" **+ "Where this is heading"** | ● | ● | ● | ● | ● | ● | ● | ◐ | ● |
| Heart Attack & Stroke Risk | Insights | ● | ● | ◐ "Heart age over time" **+ "If today's numbers hold"** | ● | ● | ● | ● | ● | ● | ● | ◐ | ● |
| Blood Pressure | Insights | ● | ● | ◐ "Your readings" | ● | ● | ● | ● | ● | ● | ● | ◐ | ● |
| Body Composition | Insights | ● | ● | ◐ "What you're made of" + "How that has changed" | ● | ● | ● | ● | ● | ● | ● | ◐ | ● |

**The bespoke slot is still one slot.** Five cards now draw two things in it,
separated by a `Divider()` and wrapped in `NestedInsightSection` — the pattern
Body Composition established. A second *top-level* section would have needed a
second placement rule, and the one placement rule is the thing Phase 1 bought.

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
