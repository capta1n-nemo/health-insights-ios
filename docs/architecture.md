# Health Insights — Architecture

## Goal

Turn data from Apple Health, Oura and Withings (extensible to more sources) into
insights that aren't directly measured — starting with **heart health**,
**cardiovascular risk**, and **blood pressure** — with the heavy lifting done
**on-device** and near-zero backend.

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│  SwiftUI app (HealthInsights)                            │
│  Onboarding · Dashboard · Insights · Grounding · Settings    │
├──────────────────────────────────────────────────────────────┤
│  AppModel (@Observable)  — orchestrates sync + evaluation     │
├───────────────┬───────────────┬──────────────┬───────────────┤
│ Integrations  │ HealthKit     │ Intelligence │ Persistence    │
│ protocol +    │ Service       │ Foundation   │ SwiftData      │
│ registry      │ (Apple Health)│ Models (LLM) │ (grounding,    │
│ Apple/Oura/   │               │ + fallback   │  logs, state)  │
│ Withings      │               │              │                │
├──────────────────────────────────────────────────────────────┤
│  InsightKit (pure Swift package — NO HealthKit/UIKit)         │
│  Canonical models · Baseline stats · Insight models · Engine  │
└──────────────────────────────────────────────────────────────┘
        (Oura/Withings OAuth runs on-device; credentials in Keychain — no backend)
```

### InsightKit (the testable core)

`InsightKit` is a standalone Swift package with **no platform imports**, so
every clinical/statistical function is verifiable with `swift test` — no Xcode,
simulator or device. It contains:

- **Canonical models** (`MetricType`, `HealthMetricSample`, `UserHealthProfile`,
  `GroundingInput`) — the vendor-neutral vocabulary everything else speaks.
- **Baseline** — EWMA, z-score, percentile: transparent personalisation.
- **Insight models** implementing `InsightModel`, each declaring its own
  `GroundingRequirement`s and computing purely from samples + profile.
- **InsightEngine** — registry + evaluator; also unions the outstanding
  grounding prompts across insights.

The app adapts platform data into these types and renders the results.

## Data flow

1. `AppModel.refresh()` pulls samples from every **connected** integration
   (`IntegrationRegistry.syncAllConnected`) plus locally-logged manual samples.
2. Samples are normalised to `HealthMetricSample` (canonical units).
3. The user's grounding facts are loaded into a `UserHealthProfile`.
4. `InsightEngine.evaluateAll` runs each insight → `[InsightResult]`.
5. `FoundationModelSummarizer` turns the results into a plain-language summary
   (on-device LLM when available, deterministic template otherwise).
6. SwiftUI renders cards, dials, trends, and grounding prompts.

## The science (why it's honest)

| Insight | Method | Source |
|---------|--------|--------|
| Cardiovascular risk | **Combined SCORE2/SCORE2-OP + ASCVD Pooled Cohort Equations** — both computed, reported as a consensus (mean) with the min–max range as an uncertainty band; deterministic, sex-specific | SCORE2 Working Group, *Eur Heart J* 2021;42(25):2439–2454 · Goff et al., *Circulation* 2013;129(25 S2) |
| Heart health | Composite of VO₂max, resting HR, HRV vs. age/sex norms + personal baseline | Established cardiorespiratory-fitness norms |
| Blood pressure | Grounding-first (logged cuff readings + trend); **experimental** personalised estimator gated behind calibration, always with uncertainty | — |
| Heart age (vascular age) | The person's own 10-year risk **inverted over age** against an optimal-risk-factor reference person of the same sex. No new equation — the shipped ones, read backwards | D'Agostino et al., *Circulation* 2008;117(6):743–753 (Framingham vascular age); same framing as JBS3 / NHS heart age |
| Fitness age | The same age/sex VO₂max norms the heart-health score marks against, interpolated into a continuous line and inverted | Cardiorespiratory-fitness norms (as above) |

Design principles that keep this trustworthy:

- **No invented numbers.** Risk % comes from published equations; the LLM only
  phrases results, it never produces values.
- **Confidence is always shown** (`Validated` / `Estimate` / `Needs data` /
  `Experimental`).
- **Cuffless BP is explicitly experimental** — wearable-only BP is unreliable
  without per-person calibration; the app frames it that way and leans on real
  cuff readings.

## Ages instead of percentages (`HeartAge.swift`, `CardioTrajectory.swift`)

A percentage is easy to shrug off; "your heart is running eight years ahead of
you" is not. Both age insights re-express models the app already has on the axis
people feel, and both are careful about the same three things:

- **Never solved outside a validated band.** `HeartAgeModel.solveAge` inverts
  each engine only inside `Engine.validatedAgeRange` (SCORE2 40–69, ASCVD 40–79)
  and returns an `isCapped` flag, which the UI says out loud ("79 or older")
  rather than printing a number produced by extrapolation. `FitnessAgeModel`
  does the same at 20–75, the extent of the norm table.
- **No fabricated lifetime risk.** The roadmap asked for lifetime framing. Nothing
  here is validated past 79, and compounding decades of 10-year risk would be
  inventing a figure, so `HeartAgeModel.projection` instead runs the *same*
  published equations at future ages they are validated for, labelled "if today's
  numbers hold". It answers "where is this heading?" without making anything up.
- **A trajectory is judged against ageing, not zero.** VO₂max falls with age
  regardless, so `VO2Trajectory` compares the least-squares slope to the norm
  line's own slope at that age (`ageTypicalChangePerYear`). Holding level scores
  *above* mid-dial, because it is genuinely a gain. `netPerYear` is that
  comparison; `fitnessYearsGained` is the trajectory's effect on fitness age
  alone. They are deliberately separate — adding them would count it twice.

"What would move it" prefers the user's own history (their busier weeks versus
their lighter ones, from a single source so a walk isn't counted twice) and falls
back to general training evidence, with `Lever.isPersonal` marking which is which.

## The structural invariants — the enums that hold the app together

_Added 2026-08-02, after two consecutive sessions where a shipped feature
reached one screen and was invisible on every other. Both failures had the same
shape: **a rule that depended on somebody remembering.** The app target has no
test target, so the compiler is the only thing that can hold a rule there — and
that is why each of these is an enum with exhaustive switches at its surfaces
rather than a convention, a comment or a checklist._

**Load the `add-data-or-input` skill before touching any of them.**

| Invariant | Type | Guarantees | Surfaces that switch on it |
| --- | --- | --- | --- |
| Every kind of data can be **seen** | `DataDomain` | the Data tab is complete | `DataTabView.section(for:)`, `DataTabView.isVisible(_:)` |
| Every kind of data can be **given** | `InputKind` | all four input surfaces agree | `AddDataView`, `AddInputMenu`, `InputSheet`, `AddDataView.standing(_:)`, `AppModel.usedInputs` |
| A card says what it takes | `ContributionRoute` | "View & add" is the card's whole answer | `ViewAndAddSection.section(for:)`, `ContributionRoute.inputKinds` |
| A metric is fully described | `MetricType` | eight decisions per metric | see the `add-metric-type` skill |
| A section says what it inferred | `SectionCaveat` | `caveat:` has no default value | every `InsightSection` call site |
| A card's sections have one order | — | `card-map.sh --check` | `InsightDetailView.body` |

### Rule 1 — new data appears in the Data tab

> *"whenever we add new data, it must have an entry in that tab.. eg substances
> should have a section, medications, later when we do composition scans"*
> — the user, 2026-08-02

The Data tab (called Vitals until that day) is the app's answer to *"what do you
actually know about me"*, and that claim only holds if it is complete. It kept
not being: the substance log was reachable only from a toolbar button for weeks,
and medication doses and imported side effects were written to the store and
listed nowhere.

`DataTabView.body` is `ForEach(DataDomain.allCases)` into an exhaustive switch,
and `isVisible(_:)` is a **second** exhaustive switch saying how each domain
answers a search. A new kind of data does not build until it has answered both.

**A domain is not a `MetricType`.** A metric is one measured series; a domain is
a *shape* — a dated log, paired readings, a regimen with a decay curve. Most are
not series at all, which is precisely why they kept falling out of a screen
built around series.

### Rule 2 — a new input appears on every input surface

> *"if manual input is allowed on a card, it must be in the View and add sub
> menu of the card, in the + master add button, in the add or update section of
> the settings sub menu; if it's missing, or hasn't been added for the first
> time, it goes into the improve your health recommendation that can be
> dismissed"* — the user, 2026-08-02

Four surfaces, two of them free:

| Surface | How it stays current |
| --- | --- |
| Today's `+` menu (`AddInputMenu`) | generated from `InputKind.allCases` |
| Settings ▸ Add or update data (`AddDataView`) | generated from `InputKind.allCases` |
| A card's "View & add" (`ViewAndAddSection`) | the model must declare a `ContributionRoute` |
| "Improve your health" | `SuggestionEngine.unusedInputs`, from `InputKind.cardRequirement` |

`InputKind.cardRequirement` is the rule made checkable — `.offeredAndPrompted`,
`.offeredOnly`, or `.settingsOnly(reason)` — and **three** checks hold it, each
catching a different half:

1. `InputKindTests` — every kind that must be on a card is in some shipped
   model's `contributions`, and no Settings-only kind is.
2. `verify.sh` — any `…Sheet` under `Features/` must be named in
   `AddDataView.swift`. *The test binds inputs somebody declared; this binds the
   ones nobody did*, which is the failure that actually happened: a
   build-override picker inside a chart and a dose button inside a section.
3. `SuggestionEngine.unusedInputs` — the dismissible prompt, at strength 0.15,
   deliberately below every grounding gap.

`ContributionRoute.inputKinds` is **plural**: `.medication` stands for the
regimen, the doses *and* the side effects, and a one-to-one mapping would have
left two of the three undeclared while looking correct.

### Rule 3 — modelled is never dressed as measured

One metric is computed rather than sensed (`activeMedicationLevel`, from logged
doses and a published half-life). Three guards keep it honest, and a second
modelled metric must copy all three:

- **`MetricSource.calculated`** on every sample — the overlay legend, the
  per-source breakdown and the export all say *"Worked out by this app"*.
- **Its own `MetricFamily`.** Sharing a family with what it is drawn against
  would suppress the pair as a tautology, hiding the one relationship it exists
  to show.
- **Weight 0 with the reason on the row, and no `referenceRange`.** A weight
  asserts that more or less of the thing is better; a reference band on a
  prescribed drug level reads as a target dose.

### Rule 4 — one axis, standardised, never two

`MetricOverlayChart` and `MedicationResponseChart` both put unlike units on a
single axis as z-scores against each series' own window mean, and print the real
values in the scrub read-out. **Two y-axes is how any two lines can be slid
until they appear to agree**, and no chart in this app does it. See the
`add-chart` skill for the rest of the charting rules — every line of it is a
shipped defect.

## Extensibility

- **New data source**: implement `HealthIntegration` and register it. Insights
  never change — they only see canonical samples.
- **New insight**: implement `InsightModel` (declare its grounding needs) and add
  it to `InsightEngine`. The grounding UI and dashboard pick it up automatically.
- **New metric**: add a `MetricType` case and map it in the relevant provider.
- **Future ML**: `Baseline` can be swapped/augmented with a Core ML model for
  personalised anomaly detection without touching the insight contracts.

## On-device intelligence

- **Apple Foundation Models** (`FoundationModels`, iOS 26+): the daily summary is
  generated on-device via `LanguageModelSession`, gated by availability with a
  template fallback. No health data leaves the phone.
- **Core ML** is the planned home for personalised predictive models; the MVP
  deliberately uses transparent classical statistics first.

## Privacy

- Health data is processed and stored **on the device** (SwiftData + HealthKit).
- Oura/Withings OAuth runs entirely on-device; the user's own developer
  credentials and tokens live in the iOS Keychain. No backend is required (an
  optional HTTPS-redirect helper exists only for Withings' redirect quirk).

## Not a medical device

These insights are for information and self-tracking only. They do not diagnose,
treat, or prevent disease and are not a substitute for professional medical
advice. Users should consult a clinician for health decisions and seek emergency
care for acute symptoms.

## Swift patterns (going forward)

New code should follow: Swift 6, SwiftUI, `@Observable` for view-model-shaped
state (not `ObservableObject`), `NavigationStack` (not `NavigationView`),
`@MainActor` on anything that touches UI state. `AppModel`
(`HealthInsights/Core/State/AppModel.swift`) is the reference — `@Observable`,
`@MainActor`, with `@ObservationIgnored` caches for derived data that must not
retrigger a view update when filled mid-render.

One existing exception, not yet migrated: `OAuthIntegration`
(`HealthInsights/Core/Integrations/OAuthIntegration.swift`) is
`ObservableObject`/`@Published`, predating this convention. Left as-is rather
than refactored opportunistically — touch it only as part of a task that
already needs to change that file.

## Provenance and source merging

`MetricSource.deviceFamily` (`InsightKit/.../HealthMetricSample.swift`)
deliberately collapses the same physical device arriving via two paths — e.g.
Oura synced directly via its API *and* mirrored into Apple Health — into one
series, so a reading is never double-counted. `MetricSource.origin` /
`SourceOrigin` records *which* path each reading actually took (direct API vs.
Apple Health bridge vs. Apple Watch vs. manual/document), derived from the
source `id` so it survives losing the friendly display name on a persistence
round-trip. Use `origin` for labelling ("Oura via Apple Health"); use
`deviceFamily` for grouping/deduplication. Don't conflate the two.

## Static attributes vs. time-series vitals

Not every `MetricType` is a trend. `MetricType.presentation`
(`InsightKit/.../Presentation/MetricPresentation.swift`) is an **exhaustive**
switch (no `default:`) classifying each metric — adding a case fails to compile
until it's categorised:

- `.staticAttribute` — a standing fact (height). No chart, no timeframe picker,
  no log/linear toggle; rendered by `StaticAttributeCard`, formatted via
  `MetricValueFormatter` (locale-aware — `185 cm` / `6 ft 1 in`, never a bare
  metre count rounded to an integer).
- `.cumulativeTrend` — weight, body composition. Start/current/delta + a
  least-squares weekly velocity (`TrendSummary`), never first-minus-last.
- `.fluctuatingRange` — heart rate, HRV, SpO₂, sleep, etc. Min/max/mean/percentile
  (`RangeSummary`).
- `.cumulativeTotal` — steps, active energy. Bucketed **per source** and
  summed per day (`DailyTotals`) — never summed *across* sources, which would
  double-count a step taken with a phone in your pocket and a watch on your wrist.
- `.discreteBivariate` — blood pressure. The only metric addressed as a pair
  (`MetricSubject.bloodPressure`) rather than a single `MetricType`; carries its
  own AHA category bands, mean arterial pressure, and 30-day grounding split
  (`BloodPressureEstimator`).

`MetricDetailView` routes on `MetricSubject.presentation` via
`MetricViewStrategy` — a compiler-checked switch with one concrete `View` per
case, not a protocol returning `some View` (that would force `AnyView` and lose
SwiftUI's structural identity on a screen that re-renders every pan frame).

## What an insight detail screen shows

Tapping a card opens `InsightDetailView`, which used to end in a chart of **one**
metric picked by a hand-written `InsightID → MetricType` switch in the app
target. Readiness weights six signals and the switch named HRV, so the screen
showed 40% of the story and drifted every time a score gained an input. That
switch is gone. The screen is now built from three things:

1. **Score over time** (`ScoreHistoryChart`). Nothing ever persisted a score, so
   this is part **replayed** and part **stored**:
   - `ScoreHistory.replay` re-runs the model against samples **truncated** to
     each past day. The truncation is the mechanism, not the `now:` argument —
     `ReadinessScore` ignores `now` and reads `history.last`, so handing it a
     past date without trimming the samples would return today's score for every
     day. `ScoreHistoryTests` pins that contract.
   - `InsightScoreRecord` stores each day's score as it's computed.
     `ScoreHistory.merging` lays stored days over replayed ones, because a
     stored row is what the user was actually told — a recomputation would
     otherwise rewrite the past whenever a weight changed.
   - Days where fewer than two signals *fired* are skipped. Having the data
     isn't using it: readiness needs four nights before its HRV component
     exists, so an early day can hold three metrics and still be scored off
     sleep alone.
2. **An overlay of every input** (`MetricOverlayChart` + `NormalizedSeries`),
   standardised so unlike units share one axis.
3. **Patterns** (`PatternFinder`) read off those series — see below.

Plus, where the insight has one: **what's driving this**, and for Heart &
Fitness Age, **both ages over time**.

### "What's driving this": departures first, the routine folded away

`InsightDriver` carries `isNotable: Bool?`, and the card leads with the lines
that departed while the rest sit behind "Show N more in your normal range".
Vitals Check scans seventeen signals; on an ordinary day sixteen say "in your
normal range", which buries the one that doesn't and makes the card a wall.
Hiding the detail entirely would make it a black box, so it is one tap away
rather than gone.

`isNotable` is **tri-state on purpose**. `nil` means *this insight doesn't draw
the distinction*, which is not the same as "everything is routine" — an
unclassified insight still shows all its lines rather than claiming a clean bill
of health it never checked.

### Both ages over time (`HeartAgeHistory`)

The Heart & Fitness Age card was three numbers and a dial: where you are, and
nothing about which way it's going — and the direction is the part you can act
on. `HeartAgeHistory.replay` rebuilds both ages weekly on the same **truncation**
contract `ScoreHistory` uses (`analyse` reads `latestValue`, so the only honest
way to reconstruct a past day is to hand it the samples that existed by then).
Weekly, not daily, because both ages move in steps as slow inputs land and a
daily replay draws a staircase of duplicates.

Your chronological age is drawn alongside as the reference, because it is the
only line with a guaranteed slope. That is also how the pace is reported —
`yearsPerYear` against the 1.0 everyone gets, so 0.9 reads as "gaining on it"
rather than as a bare slope that looks like good news. Grounding facts
(cholesterol, smoking) are applied as they stand today; the profile has no
history to replay, and the card says so rather than implying the reconstruction
is exact.

### Contributions: why the chart can't drift from the maths

`InsightResult.contributors: [MetricContribution]` is emitted **by the scoring
code as it builds each component**, carrying the metric, its renormalised weight
and the model's own formatting. Adding a component to `ReadinessScore` therefore
adds a line to the chart with no second edit anywhere.

`InsightModel.candidateMetrics` is the declared superset and has **no default
implementation**, so a new insight fails to compile until it says what it reads.
It exists to render "no data yet" rows — the difference between "this doesn't
affect your score" and "we couldn't measure it". `ContributorsTests` asserts
contributors are always a subset of candidates.

### Standardising, and why not a log axis

Log was the obvious first idea and does not work: `log(SpO₂ 95–99%)` is a flat
line while `log(sleep 5–9 h)` still swings, so the shapes stay incomparable and
the comparison is exactly the point. `SeriesNormalizer` buckets each metric to a
daily grid (via `SourceSeries.bucketed(by:for:)`, so weight still uses its median
and steps their sum) and z-scores it against **the whole visible window** — a
trailing baseline would give each series a drifting zero. Raw mode is still
offered, with log available only when every series is strictly positive and
`presentation.allowsLogScale`.

There is exactly **one Y scale**. Two scales for two units is the standard way to
make any two lines appear to agree.

### Patterns, and the floors they must clear

`PatternFinder` reports three things, all as associations and never as causes:

- **Divergence** — two signals whose least-squares slopes point opposite ways.
  This is the observation no single-metric chart can show ("more sleep, but your
  blood oxygen is drifting down").
- **Co-movement** — Pearson r (`Baseline.correlation`) over day-aligned z-values.
- **Driver** — which input tracks the score itself most closely.

Floors: ≥ 14 paired days, |r| ≥ 0.3, |slope| ≥ 0.05 SD/week, at most four
reported. Below those the card is absent rather than speculative.

### Metric colours

`MetricType.colourSlot` (`MetricPresentation.swift`) assigns one of **eight**
validated categorical hues; `Theme.metricColor` maps a slot to its light/dark
step. Fixed per metric, never by position in the on-screen list — a chart that
repaints its surviving series when one drops out can't be read across two
glances. Twenty-four metrics share eight hues, which is safe only because a slot
is reused **solely between metrics that never appear on the same chart**; what
co-occurs is decided by each insight's `candidateMetrics`, so
`MetricColourSlotTests` checks every insight for a collision. Adding a metric to
an insight can break that test from a file that never mentions colour — that is
the point.

Four of the eight light-mode steps sit below 3:1 against the grouped background,
so the legend under every overlay (name + value per series) is **required**, not
decoration: identity is never carried by colour alone.

Note this is a *second* colour scale. `Theme.sourcePalette` keys on **source**
("which device said this"); this one keys on **metric** ("which signal is this").
They answer different questions and both are needed.

## `VitalReader`: one way to read a vital

Every insight used to build its own baseline by hand — `series.last` for "today"
and `Array(series.dropLast())` for "normal". That has four defects and had them
everywhere:

1. **The newest raw sample isn't the day's value.** For a continuously sampled
   vital that is one minute of one afternoon — a heart rate taken mid-run
   reported as the day's. HRV arrives sixty-odd times a night, so a single
   artefact reading at the end of the series *was* the whole night's HRV.
2. **The baseline was every reading ever taken**, so it adapted to a real change
   far too slowly — and for high-frequency metrics it was actually the last few
   *hours*, a baseline that moves with the thing it should be detecting.
3. **Duplicates counted twice.** The same ring arriving directly and through
   Apple Health both survived, so inter-device disagreement rather than
   physiology set the standard deviation, and departures never cleared it.
4. **No reading was ever too old to use.** A months-old value was reported as
   today's, and bought the card its high confidence.

Heart Health had a fifth, worse one: resting heart rate came from `meanValue` —
the mean of *every* resting-HR sample ever recorded. Over a 180-day lookback that
number is effectively frozen; a genuine improvement moved it by a fraction of a
beat, so the score could not reflect one.

`Baseline/VitalReader.swift` is the fix made shared. `VitalReader.reading(_:from:)`
returns a `VitalReading`: the day's representative value (via the metric's own
`bucketStatistic`), the windowed baseline behind it, a z-score, the source it
came from, and `isFresh`. Per source, de-duplicated, 28-day window, minimum
history before any z is offered — because a single reading is not a clean bill of
health and shouldn't read as one. `dailyValues(_:from:days:)` returns the series
for the things that need it (sleep consistency is the night-to-night spread, not
a single day).

**Freshness is a per-insight decision, not a global one.** Readiness *drops* a
component whose reading is stale — it is a claim about today, and a week-old HRV
says nothing about this morning. Heart Health deliberately does not gate on it:
VO₂max updates every few weeks by design, and a fortnight-old figure is still the
right one. The reader reports staleness; the insight decides what it means.

## Vitals Check: why a perfect score is hard

The card once read 100 / "All normal" on essentially every day. That was the
model, not the user's health, and every cause pushed the same way:

- **The baseline was the anomaly.** History was `suffix(60)` — sixty *readings*.
  Heart rate arrives raw at ~300 samples a day, so the "personal baseline" was
  the last five hours and moved with whatever it was meant to detect. It printed
  a baseline heart rate of 100 bpm. It is now the day's representative value
  **per source**, bucketed by the metric's own `bucketStatistic`, against a
  28-day window needing ≥ 7 days present.
- **Nothing checked the date.** `now` was accepted and never read, so a reading
  of any age was current, normal by construction, and bought high confidence
  while the copy said "measured today". Each `Spec` now carries `freshWithin`;
  anything older moves to a stale list that is named and counted against
  coverage.
- **Two paths for one device set the variance.** `MultiSource.deduplicate` was
  never called on the insight path, so inter-device disagreement — not
  physiology — sized the SD. Sources are de-duplicated and scored separately.
- **The score was a step function.** `100 - (unusual*25 + watch*10)` ignored the
  z-scores it carried. `normality` is now continuous (Gaussian in z),
  direction-aware, aggregated worst-first — this insight reports outliers, it
  does not average an abnormal SpO₂ against a normal heart rate — then **capped
  by coverage** measured against what this person's devices normally provide.
  So 100 needs everything you usually record measured today *and* on baseline,
  while a one-wearable user isn't punished for lacking a second.
- **Bounds were wrong.** Walking heart rate's 130 could never fire; blood oxygen
  flagged only at 92 when 94 is the attention line; body temperature applied
  core bounds to a *reconstructed skin* series, so a fever needed +2.3 °C.
  Apple's real thermometer readings are now in `readMap`.

HRV also gains a **relative floor** (60% of the long-run median), because a slow
collapse walks its own baseline down and no rolling z-score can see it.

## Events are not metrics

Apple's discrete flags — irregular rhythm, high/low heart rate, low cardio
fitness, unsteady walking — have no unit, no baseline, no bucketing rule and no
gap interval. Modelling them as a `MetricType` would mean inventing all four, so
`VitalEvent` is a separate input. `InsightModel` has an `evaluate(samples:events:
profile:now:)` overload **with a default implementation** that ignores them, so
only Vitals Check overrides and the other ten models were untouched. Events
outrank z-scores, are de-duplicated by kind, and are priced by severity.
`ScoreHistory.replay` truncates them on the same contract as samples.

Watch the encoding quirk: a HealthKit category sample with value `notApplicable`
(0) *and* a duration is stored as **minutes**, not the enum. So the sample's
existence is the signal, not its value.

## Chart identity: hue alone, and a bounded number of lines

Identity used to be a **(hue, dash) pair**. Eight validated hues is the ceiling
for a categorical palette, Vitals Check charts seventeen signals, and no
seven-hue subset clears the colour-blind all-pairs floor — measured with the
validator, not assumed, after the first version shipped two indistinguishable
greens. A globally-unique (hue, dash) pair per metric made any subset
collision-free by construction.

**It was measurably safe and practically wrong.** A dashed line reads as *an
estimate, or a gap in the data* — not as a different signal. The user reported
the dashes as gap markers, which is the correct reading of that ink.

So the encoding inverted. **Dash now means exactly one thing anywhere in the
app: this value was not measured** — a gap, a projection, a reference level
(`Theme.projectedStroke`). Every measured series is solid, and identity is hue
alone. Which means the *number of lines* has to stay inside what hue can carry:

- **`MetricPalette.slots(for:)`** (`Presentation/MetricPresentation.swift`)
  assigns hues **per chart**, not globally. A metric keeps its own preferred slot
  (`colourSlot`) wherever that slot is free, so the same signal usually looks the
  same from card to card; where two would collide, the later one steps to the
  next free hue. Global assignment could not promise distinctness once dash was
  gone — `colourSlot` is `chartStyleIndex % 8`, so two metrics eight apart in the
  table collided silently.
- **`OverlaySelection`** (`Presentation/OverlaySelection.swift`) decides which
  series are drawn. It lives in InsightKit, not the view, for the same reason
  `colourSlot` does: it is the rule that determines whether two lines can look
  alike, and the first version shipped from the view layer where no test could
  reach it — and put two identical reds on one chart.

### What counts as "away from baseline"

`OverlaySelection.anomaly` is deliberately **not** "did any day in the window
depart". That question let a flat line with one blip three weeks ago rank
alongside a signal elevated all fortnight, so body temperature was drawn on a
chart whose own legend called it "steady" — a card contradicting itself in two
places at once.

Two terms, larger wins:

- **Recent** — the furthest it got in the last seven days, so yesterday's fever
  is a finding even if the rest of the month was flat.
- **Sustained** — the RMS departure across the window, so a signal sitting a full
  SD off baseline every day counts, while one |z| = 4 day among thirty flat ones
  comes to ≈0.8 and doesn't.

Anchored to the **newest reading**, not the clock, so a series that stopped
reporting doesn't lose its recent term and sink down the list as time passes.

### Selection is the reader's

The legend is a picker: every signal is individually tappable, and the list is
ordered most-departed first so choosing among thirteen is reading from the top
rather than hunting. `defaultSelection` is a *starting point* — everything when
there are ≤ `comfortableSeriesCount` (6) series, otherwise the notable ones
capped at `hueCount` (8). Going past eight by hand is allowed rather than
refused; the legend says plainly that the colours will repeat.

**Opacity carries the anomaly.** Each span between adjacent readings is drawn at
an opacity set by how far from baseline it is (≈0.12 at baseline, opaque by
|z| ≥ 3), so flat ordinary stretches recede and departures come forward. Dots
appear only past 1.5 SD — the same threshold that decides which series are drawn
at all, so "away from baseline" means one thing on the chart. Thinning for long
windows keeps the **extremes** rather than striding, because a stride drops
exactly the days the chart exists to show.

### Reference bands

The blood-pressure chart shades the ACC/AHA categories behind the readings
(`Category.systolicRange`). **Systolic only, and the chart says so**: the two
lines share one mmHg axis but not one set of thresholds — 85 is stage 1
diastolic and entirely normal systolic — so a single shaded set would mislabel
one of them. Diastolic limits are thin rules in the diastolic line's own colour.

The thresholds therefore exist in two places (`Category.of` classifies,
`systolicRange`/`diastolicRange` place the shading), so `PressureBandTests` holds
them to each other: every value from 80 to 210 must land inside the band its own
classifier assigned it, and the bands must tile the axis with no seam.

⚠️ Horizontal band marks are the API family most prone to the `Chart3DContent`
overload hazard. Every mark builder keeps its explicit `-> some ChartContent`.

## Insights tab: the deep dive

Today asks "how am I right now"; the Insights tab asks "what has been happening
over months". Gated on `InsightID.cadence == .trend` so the split stays clean.

- **`LagFinder`** — the one question Today structurally cannot ask. Today
  compares today with yesterday, so every relationship it sees is same-day.
  Correlating a metric at day *d* against the score at *d+1…d+3* asks whether
  last night's sleep predicts tomorrow. A lag is reported only when it beats
  same-day by a real margin, or it is the same finding blurred.
- **`PeriodContrast`** — last 28 days against the prior 28, standardised by the
  prior period's own spread. A z-score cannot answer "has my normal moved?",
  because its baseline drifts along with the change.
- **`ScoreTrend`** — the fitted line *with its residual spread*, never a bare
  slope, matching the standard `VO2Trajectory` already holds itself to.
- **`ScoreComparisonChart`** — scores are all 0–100, so they are the one overlay
  in the app that needs no transform at all.

**Patterns must not report their own arithmetic.** `PatternFinder` suppresses
any pair where `MetricType.sharesMeasurementBasis(with:)` holds. Same family is
the obvious case — body temperature and skin-temperature deviation are one
measurement reported twice. The non-obvious one is **heart rate against
heart-rate variability**: both are computed from the same beat-to-beat interval
stream, so a shorter interval is simultaneously a higher rate and less room to
vary. "HRV and resting heart rate move in opposite directions (r = −0.71)"
reached the card as the *top* pattern, and it is arithmetic wearing the clothes
of a finding.

They stay in separate `MetricFamily` values because family also drives colour
grouping and how the app talks about systems, where the distinction is real —
so shared *basis* is its own, narrower question. Both the co-movement and the
divergence branches consult it; divergence previously had no guard at all, and
two readings of one measurement always diverge when one is the inverse of the
other.

## Chart gap interpolation

`MetricType.maxValidInterval` (same file) sets the longest gap a chart line may
bridge before it breaks into a separate segment: 30 min for high-frequency
signals (heart rate, SpO₂), 24 h for daily-cadence ones (resting HR, HRV,
sleep), 14 days for infrequent ones (weight, VO₂max, blood pressure). Joining
two readings across a longer gap with a straight line asserts a trend that was
never measured, so `ScrollableMetricChart` draws one `LineMark` run per segment
from `SourceSeries.segments(maxGap:)` rather than one continuous line per
source.

Long ranges are **bucketed**, not decimated: `SourceSeries.bucketed(by:for:)`
(`InsightKit/.../Models/MetricAggregator.swift`) reduces a window to
mean/median/min/max per bucket using each metric's own rule (`bucketStatistic`
— median for weight so one water-weight day can't move the line, sum for
step-like totals, mean otherwise), which is what feeds the chart at `6M`/`Y`/`All`
zoom levels.

## BYO-Key direct API integrations (Oura / Withings / Whoop)

No backend: OAuth runs entirely on-device via `ASWebAuthenticationSession`
(`OAuthWebFlow`), and the user supplies their own developer Client ID (+ secret
where required) pasted into `ProviderSetupView`. Only the client ID is
required — `ProviderCredentialStore.credentials(for:)` treats an absent secret
as `""` rather than requiring both, because Oura's flow is PKCE and has no
secret; requiring one made that provider permanently unable to report having
credentials. Pasted values are sanitised with `.whitespacesAndNewlines` (not
just `.whitespaces` — a console copy usually carries a trailing newline) both
in the view and again in the store, so a stray character can't reach the
Keychain by either path. `CredentialValidator` gives inline feedback before the
network round-trip (catches pasting the redirect URI or console URL by
mistake) without being strict about actual key shape, since providers issue
UUIDs, hex strings and opaque tokens interchangeably.

### Scopes, 401s, and why the log must carry the response body

Oura returns **401, not 403, when a token is missing a scope** — it reserves 403
for a lapsed subscription — and names the scopes it wanted in the RFC7807
`detail` field of the body. So a token that fetches `daily_sleep` happily can
401 on `daily_resilience` in the same sync, and a log line that reads only
`HTTP 401` is undiagnosable. `ProviderAPIError` therefore unpacks every ≥400
body (`title` / `detail` / `error_description`, plus Oura's `x-trace-id`
header) into the diagnostics detail, along with a plain-English remedy per
status code.

Two more things make a partial grant visible rather than mysterious:

- The OAuth **callback** carries the scopes actually granted (`?code=…&scope=…`),
  which Oura warns "may be different than the scopes that were requested" —
  its consent screen lets the user switch scopes off individually. `connect()`
  captures that list into `OAuthTokens.grantedScopes`, logs anything withheld,
  and every sync re-states it. The token *response* has no scope field, so a
  refresh carries the stored list forward rather than losing it.
- `getJSON` refreshes the access token **once** on a 401 and retries. Without
  it, `validAccessToken()` only ever refreshed against the locally-stored
  expiry — and `isExpired` is `false` whenever the provider omitted
  `expires_in`, so a server-side revocation was unrecoverable. Refreshes are
  coalesced through a single in-flight `Task` and disabled for the rest of a
  sync once one fails, because Oura's refresh tokens are single-use: nine
  endpoints each refreshing on their own 401 would revoke the grant instead of
  repairing it.

**The scopes Oura doesn't document.** Its published scope table and OpenAPI
spec both list eight scopes (`email`, `personal`, `daily`, `heartrate`,
`workout`, `tag`, `session`, `spo2`/`spo2Daily`) and say nothing about which
endpoint needs which. Three collections need scopes that appear on neither
list, discovered only from the text of Oura's own 401 bodies:

| Collection | Scope |
| --- | --- |
| `daily_resilience` | `stress` |
| `daily_cardiovascular_age` | `heart_health` |
| `vO2_max` | `heart_health` |

`OuraProvider.requiredScope` holds that mapping, but **only to name the scope
in the summary when a rejection didn't spell it out — never to pre-empt a
call.** An earlier build skipped collections whose scope looked absent from
`grantedScopes` and got it badly wrong: Oura doesn't reliably return `scope` on
the callback, so "didn't say" was read as "granted nothing" and three
collections were withheld without ever being tried. Hence `grantedScopes` stores
`nil`, never `[]`, for an unreported grant, and nothing may withhold a request
on the strength of it. Oura's own 401 is the only authority.

A scope 401 is never retried — `ProviderAPIError.missingScope` recognises
Oura's "Token is not authorized access <scope> scope" phrasing, and a fresh
token carries the same grant, so retrying only spends a single-use refresh
token and logs the failure twice.

Enabling a scope on the Oura application does nothing by itself: the grant is
baked into the token. Nor is reconnecting always enough — with an authorization
already on file, Oura can reissue against the old grant without showing a
consent screen, so the user must revoke the app in their Oura account first.

Oura's developer console has moved to `developer.ouraring.com/applications`;
the OAuth authorize/token endpoints did not move with it.

Pagination is followed. `OuraProvider.fetchPages` walks `next_token` to a ceiling
of `maxPages` (20), stops if a cursor repeats — a server handing back the same
page would otherwise loop until the ceiling — and **fails the whole collection if
any page fails** rather than returning a truncated series, because half a history
is indistinguishable downstream from a genuinely short one and the app would draw
a gap it invented. The log says how many pages a collection took whenever it took
more than one.

This was a logged warning for a long time on the reasoning that it had never
fired. A warning that has not fired is not evidence that it cannot, and the
failure mode is silent history loss on exactly the long back-fill a first sync
performs.

The `heartrate` scope is deliberately **not** requested — see `OuraProvider` for
the three steps to reinstate it, and why ~50k five-minute samples Apple Health
already mirrors is not worth an unused permission.

## Ingestion pipeline (provider payload → vitals)

`InsightKit/Sources/InsightKit/Ingestion/`. Providers fetch bytes; the pipeline
decides what they mean. Nothing in it knows a provider by name.

```
IngestPayload (raw bytes + source + endpoint)
   → PayloadIngestor        — EnvelopeSpec says where records live and how they're dated
   → JSONFlattener          — recursive walk to typed leaves on dotted paths
   → FieldCatalogue         — persisted registry; first sighting of a path is an event
   → PromotionRuleSet       — path/leaf/suffix → MetricType (+ unit conversion), as data
   → IngestionResult        — raw samples, promoted vitals, new fields, proposals, skips
```

Four rules this design exists to enforce:

1. **Everything is captured, and the exceptions are counted.** `RawValue` is
   `number | text | flag`, so strings and booleans survive — Oura's resilience
   `level`, its sleep hypnogram, Withings' `comment`. Anything not stored
   becomes a `SkippedField` with a reason, reported in Troubleshooting, so
   "100% ingested" is auditable rather than aspirational.
2. **Numeric arrays are summarised, not exploded.** Oura's 5-minute night
   series would add ~40k samples per sync for data Apple Health already
   mirrors, so `heart_rate.items` becomes count/min/max/mean/first/last.
   `FlattenPolicy.arrayStrategy = .expand` switches a field to literal
   point-by-point capture when it earns it.
3. **A new connector is a declaration.** `GenericJSONIngestor` covers Oura and
   Whoop from an `EnvelopeSpec` alone. `WithingsMeasureIngestor` exists only
   because Withings sends `(type, value, unit)` triples instead of named
   fields — the escape hatch, not the pattern.
4. **Promotion is data, never inference.** A rule promotes; a field that merely
   *looks* like a known vital is catalogued and logged as a proposal. A
   provider renaming a field can therefore never silently rewire an insight.

`AppModel.refresh()` runs the pipeline before the cache merge and before
`recompute()`, so a field discovered this sync reaches insights in the same
sync.

## Which vitals feed which insight

Kept current deliberately — a metric with no reader is imported, charted and
then ignored, which is how `heartRate`, `walkingHeartRateAverage`,
`oxygenSaturation`, `bodyTemperature` and the whole body-composition tail sat
unused despite tens of thousands of samples.

| Metric | Read by |
| --- | --- |
| heartRate, walkingHeartRateAverage | Vitals Check |
| bodyTemperature | Vitals Check — **core only**: a thermometer, Withings 71/12 |
| skinTemperature | Vitals Check, when no deviation spoke — Whoop, Withings 73, Apple wrist, and reconstruction |
| restingHeartRate | Readiness, RHR Trend, Heart Health, Heart Age, Vitals Check |
| HRV (SDNN / rMSSD) | Readiness, Heart Health, Vitals Check |
| oxygenSaturation | Readiness, Sleep Quality, Vitals Check |
| respiratoryRate | Readiness, Sleep Quality, Vitals Check |
| skinTemperatureDeviation | Readiness, Sleep Quality, Vitals Check |
| sleepDurationHours | Readiness, Sleep Quality, Sleep Debt, Energy |
| sleepOnset | Sleep Regularity — signed hours from midnight, branch cut at midday |
| sleepEfficiency, sleepDeepMinutes, sleepRemMinutes | Sleep Quality — deep and REM scored as a *share of the night*, never a minute target |
| vo2Max | Cardio Fitness, Cardio Trajectory, Heart Age |
| vascularAge | Heart Age (as a second opinion, never merged into ours) |
| bodyMass, bodyFatPercentage, height | Body Composition |
| leanBodyMass, muscleMass, boneMass, bodyWaterPercentage | Body Composition |
| bloodPressureSystolic/Diastolic | Blood Pressure, Heart Age, Cardiovascular Risk |
| stepCount, activeEnergyBurned | Cardio Trajectory, Energy |
| exerciseMinutes | Fitness (weekly WHO dose via `ActivityDoseModel`) |
| sleepLatencyMinutes | Sleep (Ohayon 2017 term; typed Oura parser only, nap-aware) |
| dayStrain | *(no reader — Whoop not connected)* |

## Keychain storage

Two layers: `KeychainStore` (`HealthInsights/Core/Persistence/KeychainStore.swift`)
is a generic get/set/delete wrapper over a `kSecClassGenericPassword` item,
`kSecAttrAccessibleAfterFirstUnlock`. `ProviderCredentialStore` is the typed
layer on top, namespacing keys by provider id (`"\(providerID).clientID"`,
`.clientSecret`, `.tokens`). Nothing health-related is stored here — only OAuth
client credentials and tokens.

## Running the tests anywhere

`InsightKit` is a platform-free package, which was always the intent — but two
Darwin-only Foundation APIs quietly broke it on Linux, and nobody noticed because
CI runs on macOS. The consequence was expensive: agent sandboxes ship no Swift,
so **every logic error had to be found by pushing and waiting ~90 s for CI**, and
each status check cost a ~450 KB API response.

Both are now behind `#if canImport(Darwin)`:

- **`Measurement.formatted(_:)`** (`MetricValueFormatter.lengthString`) — there
  is no `FormatStyle` for `Measurement` in swift-corelibs-foundation, and
  `MeasurementFormatter` is explicitly unavailable there too. The Linux fallback
  reports centimetres rather than guessing at Apple's `.personHeight` splitting;
  the one test asserting imperial output is `#if canImport(Darwin)`.
- **`CFBooleanGetTypeID`** (`Ingestion/JSONBoolean.swift`) — corelibs has no
  `CFBoolean`. The Linux branch keys on the encoded `objCType`, verified
  empirically rather than assumed: a JSON `true` is `c`, an integer is `i`, a
  double is `d`. `boolValue` is no help — it is true for any non-zero number.

Result: **the full suite passes on Swift 6.0.3 / Ubuntu 24.04** — `swift test` prints
the count, which is why one is not repeated here. The tooling is:

| Script | What it does |
| --- | --- |
| `scripts/bootstrap-swift.sh` | Installs a Linux toolchain (~2 min, once per sandbox) |
| `scripts/swift-env.sh` | `source` it to put `swift` on `PATH` |
| `scripts/verify.sh` | Sub-second lint of the traps this repo has been broken by; `--tests` also runs the suite |
| `scripts/ci-status.sh` | "Did CI pass for this SHA?" via `git ls-remote` |

`verify.sh` exists because the compiler is the only thing that catches an
unhandled `MetricType` case, and the compiler is what a sandbox lacks. It checks
each exhaustive switch **by name** — grouped `case .a, .b:` arms make counting
useless — and reports exactly which metric each one is missing.

`ci-status.sh` reads a git ref rather than the Actions API. `ci.yml`'s
`record-status` job pushes the verdict to `refs/ci/passed/<sha>` or
`refs/ci/failed/<sha>`; refs under `refs/ci/` cannot trigger a workflow, so it
cannot loop. A `git ls-remote` filtered to those two refs is a few hundred bytes
against the API's ~450 KB.

The **app target still needs CI**: `xcodebuild` requires the iOS SDK, so all the
SwiftUI, HealthKit and SwiftData code is compiled only there. Local green means
InsightKit is green — the clinical maths, the scoring, the baselines and the
parsers, which is where the bugs have actually been.

## Verification

- **`./scripts/verify.sh --tests`** — the gate. Lints the traps this repo has
  been broken by, then runs the InsightKit suite: the risk equations
  against published worked examples, the statistics against hand-computed
  fixtures. It **installs a Swift toolchain itself** if the sandbox has none,
  so it works anywhere — see "Running the tests anywhere" above.
- **`./scripts/ci-status.sh --wait`** after pushing. Never the GitHub Actions
  API; its smallest response is over 100K tokens.
- The **app target** is still CI-only: `xcodebuild` needs the iOS SDK, so the
  SwiftUI, HealthKit and SwiftData code is compiled on push and nowhere else.
- Open `HealthInsights.xcodeproj` in Xcode 16+ and run on a device/simulator
  with Health data. (If the project won't open, regenerate it with
  `xcodegen generate`.)
