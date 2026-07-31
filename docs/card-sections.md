# Card sections — what each screen actually renders

_Audit of record, written 2026-07-31. Every cell below was read out of the code,
not inferred from another document. Where a claim carries a `file:line`, that
line is the proof._

This exists because the app has three families of card-based screen and no
written record of which sections each one shows. The symptom that prompted it:
some insight detail screens have a chart of their own and most don't, and there
was no way to see how far that went without reading nine files.

**This is a description, not a verdict.** The gaps at the bottom are options,
not a backlog — several of the inconsistencies are deliberate and have their
reasoning in a code comment, which is noted where it applies.

---

## 1. Insight detail screens

One file renders all seventeen: `HealthInsights/Features/Insights/InsightDetailView.swift`.
Its `body` is a fixed sequence of seventeen possible sections. Nothing is
per-insight except the gates.

### The sections, in render order

| # | Key | Section title | Gate | Line |
|---|---|---|---|---|
| 1 | `Hdr` | header — dial or headline, confidence badge, explanation | always | `:31` |
| 2 | `Ages` | "How old are you behaving?" | `id == .heartAge` and an age computed | `:130` |
| 3 | `AgeHx` | "Both ages over time" | `id == .heartAge` and ≥3 points | `:163` |
| 4 | `Req` | "Add these for a better estimate" | `!unmetRequirements.isEmpty` | `:107` |
| 5 | `Drv` | "What's driving this" | `!drivers.isEmpty` | `:225` |
| 6 | `BP→` | "View & add readings" — **a link, not a chart** | `id == .bloodPressure` | `:642` |
| 7 | `Ergy` | "Today" — energy curve | `id == .energy` and curve ≥2 | `:326` |
| 8 | `Frtn` | "Your fortnight" — bedtimes | `id == .circadianConsistency` and ≥`minimumNights` | `:351` |
| 9 | `ScrHx` | "Score over time" — **and the only timeframe picker** | history ≥2 | `:289` |
| 10 | `Load` | "Cardiovascular load" | `id == .substanceImpact` and series ≥7 | `:376` |
| 11 | `Goes` | "What goes into this" — overlay, scale picker, legend | series non-empty | `:419` |
| 12 | `Patt` | "Patterns worth a look" | patterns non-empty | `:489` |
| 13 | `1st` | "What comes first" — lag | `cadence == .trend` **and** leads non-empty | `:536` |
| 14 | `Chg` | "What changed" — period contrast | `cadence == .trend` **and** changes non-empty | `:568` |
| 15 | `Hist` | "Full history" — one link per input | contributors non-empty | `:614` |
| 16 | `Fbk` | "Was this accurate?" | `primaryValue != nil` | `:664` |
| 17 | `Disc` | disclaimer | always | `:705` |

### The matrix

**Key** — `●` always renders · `◐` renders once the data clears a floor
(structurally available to this insight) · `○` **cannot ever render** — the code
names a different `InsightID`, or the cadence gate excludes it · `–` the model
never emits the input, so the section is unreachable.

| Insight | Tab | `Hdr` | `Ages` | `AgeHx` | `Req` | `Drv` | `BP→` | `Ergy` | `Frtn` | `ScrHx` | `Load` | `Goes` | `Patt` | `1st` | `Chg` | `Hist` | `Fbk` | `Disc` |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Readiness | Today | ● | ○ | ○ | – | ◐ | ○ | ○ | ○ | ◐ | ○ | ◐ | ◐ | **○** | **○** | ◐ | ◐ | ● |
| Vitals Check | Today | ● | ○ | ○ | – | ◐ | ○ | ○ | ○ | ◐ | ○ | ◐ | ◐ | **○** | **○** | ◐ | ◐ | ● |
| Sleep Quality | Today | ● | ○ | ○ | – | ◐ | ○ | ○ | ○ | ◐ | ○ | ◐ | ◐ | **○** | **○** | ◐ | ◐ | ● |
| Energy | Today | ● | ○ | ○ | – | ◐ | ○ | **◐** | ○ | ◐ | ○ | ◐ | ◐ | **○** | **○** | ◐ | ◐ | ● |
| Health Watch | Today | ● | ○ | ○ | – | ◐ | ○ | ○ | ○ | ◐ | ○ | ◐ | ◐ | **○** | **○** | ◐ | ◐ | ● |
| Sleep Debt | Today | ● | ○ | ○ | – | ◐ | ○ | ○ | ○ | ◐ | ○ | ◐ | ◐ | **○** | **○** | ◐ | ◐ | ● |
| Substance Impact | Today | ● | ○ | ○ | – | ◐ | ○ | ○ | ○ | ◐ | **◐** | ◐ | ◐ | **○** | **○** | ◐ | ◐ | ● |
| Cardiovascular Risk | Insights | ● | ○ | ○ | ◐ | ◐ | ○ | ○ | ○ | ◐ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Heart Health | Insights | ● | ○ | ○ | ◐ | ◐ | ○ | ○ | ○ | ◐ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Heart & Fitness Age | Insights | ● | **◐** | **◐** | ◐ | ◐ | ○ | ○ | ○ | ◐ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Blood Pressure | Insights | ● | ○ | ○ | ◐ | ◐ | **●** | ○ | ○ | ◐ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Cardio Fitness | Insights | ● | ○ | ○ | ◐ | ◐ | ○ | ○ | ○ | ◐ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Cardio Trajectory | Insights | ● | ○ | ○ | ◐ | ◐ | ○ | ○ | ○ | ◐ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Body Composition | Insights | ● | ○ | ○ | ◐ | ◐ | ○ | ○ | ○ | ◐ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Resting HR Trend | Insights | ● | ○ | ○ | – | ◐ | ○ | ○ | ○ | ◐ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Where You Stand | Insights | ● | ○ | ○ | ◐ | ◐ | ○ | ○ | ○ | ◐ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Sleep Regularity | Insights | ● | ○ | ○ | – | ◐ | ○ | ○ | **◐** | ◐ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |

**Reading the columns down:**

- Six columns (`Ages`, `AgeHx`, `BP→`, `Ergy`, `Frtn`, `Load`) are `id`-gated.
  Between them they touch **5 of 17** insights.
- Two columns (`1st`, `Chg`) are cadence-gated and are off for **7 of 17**.
- One column (`Req`) is off for **9 of 17** — those models declare
  `requirements: []`, which is honest: they read sensed data only.
- The remaining eight columns are uniform across all seventeen. **That half of
  the screen is already consistent**, which is worth saying plainly — the
  contributors overlay, patterns, full-history links, feedback, header and
  disclaimer behave identically everywhere.

### Per-insight facts behind the matrix

| Insight | `cadence` | `requirements` | emits `contributors` | drivers classified | bespoke visual |
|---|---|---|---|---|---|
| Readiness | daily | `[]` | ✅ components | ✅ `.component` | — |
| Vitals Check | daily | `[]` | ✅ readings (weight 0) | ✅ explicit | — |
| Sleep Quality | daily | `[]` | ✅ components | ✅ `.component` | — |
| Energy | daily | `[]` | ✅ | ✅ | `EnergyCurveChart` |
| Health Watch | daily | `[]` | ✅ signals (weight 0) | ✅ explicit | — |
| Sleep Debt | daily | `[]` | ✅ | ✅ | — |
| Substance Impact | daily | `[]` | ✅ | ✅ | `SubstanceLoadChart` |
| Cardiovascular Risk | trend | **10** (6 fixed + 4 for `.combined`) | ✅ systolic only | ✅ `.notable`/`.routine` | — |
| Heart Health | trend | 2 | ✅ components | ✅ `.component` | — |
| Heart & Fitness Age | trend | 6 | ✅ (weight 0) | ✅ mixed | `AgeHistoryChart` + 3-age row |
| Blood Pressure | trend | 2 | ✅ sys/dia | ✅ | link to `MetricDetailView` |
| Cardio Fitness | trend | 2 | ✅ VO₂max | ✅ `.component` | — |
| Cardio Trajectory | trend | 2 | ✅ 4 metrics | ✅ | — |
| Body Composition | trend | 2 | ✅ present metrics | ✅ `.routine` + filter | — |
| Resting HR Trend | trend | `[]` | ✅ resting HR | ✅ | — |
| Where You Stand | trend | 2 | ✅ standings (weight 0) | ✅ `<40th` centile | — |
| Sleep Regularity | trend | `[]` | ✅ | ✅ | `SleepOnsetStripChart` |

Two things this table settles:

- **Every model emits `contributors` on its happy path.** The
  `candidateMetrics` fallback at `InsightDetailView.swift:468` is now only
  reached on a model's "no data yet" branch. It is not dead code, but it is no
  longer papering over an unmigrated model.
- **Every model classifies its drivers** into notable and routine on the happy
  path, so the "Show N more in your normal range" disclosure works everywhere.
  The **early-return branches do not** — they use the string-array
  `InsightResult` initialiser, which leaves `isNotable == nil`, and the screen
  correctly shows those lines in full rather than hiding them
  (`InsightDetailView.swift:225` documents why).

---

## 2. Metric detail screens

`MetricDetailView` switches on `subject.presentation` (`:68`) into three
structurally different screens. This is not one screen with variations — the
blood-pressure and static-attribute branches replace the whole body.

| Section | `cumulativeTrend`<br>weight, body comp | `fluctuatingRange`<br>HR, HRV, sleep, SpO₂ | `cumulativeTotal`<br>steps, active energy | `discreteBivariate`<br>blood pressure | `staticAttribute`<br>height |
|---|---|---|---|---|---|
| summary card | "Change over this period" | "Range over this period" | "Daily totals" | ○ | current value |
| timeframe picker | ✅ in overlay card | ✅ | ✅ | ✅ in chart card | ○ |
| chart | `MultiSourceChart` | ✅ | ✅ | bespoke paired chart | ○ |
| scrub read-out | in-chart | in-chart | in-chart | **above** the chart | ○ |
| per-source breakdown | ✅ | ✅ | ✅ | ○ | ○ |
| per-source averages | multi-source only | multi-source only | multi-source only | ○ | ○ |
| reference range + provenance | ✅ from `referenceRange` | ✅ | ✅ | **restated in the legend** | ○ |
| substance-window shading | ✅ | ✅ | ✅ | ○ | ○ |
| gap/bridge key | ✅ | ✅ | ✅ | ○ | ○ |
| log-scale toggle | ○ by presentation | ✅ | ✅ | ○ | ○ |
| calibration | ○ | ○ | ○ | ✅ | ○ |
| dated history list | ○ | ○ | ○ | ✅ paged | "Earlier entries" |
| add-a-reading | ○ | ○ | ○ | ✅ | ○ |

Blood pressure is the outlier: it is the only metric screen with no source
breakdown, no per-source averages and no substance shading, and it states its
reference bands in its own prose (`BloodPressureSections.swift:196`) rather than
through `MetricType.referenceRange`. Some of that is forced — a paired reading
cannot use the single-series chart — and the `Chart3DContent` hazard is why the
read-out sits above the chart (`:169`). The source breakdown and substance
shading are not forced.

---

## 3. List and tab surfaces

| Surface | Cards, in order | Notes |
|---|---|---|
| **Today** (`DashboardView.swift`) | summary · suggestion (1, dismissible) · Last night · Vitals glance · grounding banner · daily insight tiles | filter: `cadence == .daily` **and `primaryValue != nil`** (`:13`) |
| **Insights** (`InsightsListView.swift`) | "Improve your health" (collapsed) · subtitle · "How your scores compare" · trend insight tiles | filter: `cadence == .trend` **only** (`:15`) |
| **Vitals** (`VitalsView.swift`) | `List` sections: 4 metric groups · Blood pressure · Substances · Other data | rows, not cards |

`InsightCard` (`DashboardView.swift:269`) is shared by both tabs and is
consistent: dial or icon, title, confidence badge, headline, change chip,
first driver line.

---

## 4. The gaps

Ranked by what they cost a reader. Each carries the line that proves it and one
option for what consistency would look like — **stated as an option, not a
decision.**

### 1. The timeframe picker is trapped inside "Score over time"

`InsightDetailView.swift:299` holds the only `Picker("Timeframe"…)` on the
screen. But `timeframe` also drives the contributors overlay (`:421`), the
patterns card (`:492`) and the lag card (`:539`). When an insight has fewer
than two replayable days, section 9 does not render — and the other three are
left **stuck on `.month` with no control anywhere on screen**.

_Consistency would look like:_ hoist the picker to the screen, above the first
data-bearing card, so the window it controls is always adjustable.

### 2. The deep-dive pair is cadence-gated, but the screen is not

`InsightDetailView` is reached from either tab and is byte-identical. Yet the
seven `.daily` insights never show "What comes first" or "What changed"
(`:67`). The comment at `:63` argues from the *tab's* question — "how am I right
now" versus "what has been happening over months" — but the gate sits on the
detail screen, which is the same screen either way. And the daily insights are
exactly the ones with dense daily series, where a lag analysis has the most to
work with.

_Consistency would look like:_ drop the cadence gate and let the existing
sample-count and effect-size floors inside `LagFinder` and `PeriodContrast`
decide, which is how every other section on this screen already works.

### 3. Bespoke charts: 4 of 17, and one of them is a link

Heart Age (two cards), Energy, Sleep Regularity, Substance Impact have one.
Blood Pressure gets a navigation link instead. Twelve have none.

The twelve are not equally deserving, which is the useful part:

- **Readiness and Heart Health** each define their *own* nested `Component`
  type — `name`, `score`, `weight`, `detail`, `metric`, `higherIsBetter`,
  identical field for field (`ReadinessScore.swift:17`,
  `HeartHealthScore.swift:15`). One weighted-contribution card would serve both,
  drawn once, off a shared type that does not exist yet.
  **Sleep Quality** computes the same seven weighted sub-scores but keeps them
  as locals (`SleepQualityInsight.swift:130`), so it would need a `Component`
  extracted before it could use that card.
- **Where You Stand** has percentiles — a standings chart is the obvious shape,
  and the card currently expresses them only as sentences.
- **Sleep Debt, Body Composition, Vitals Check, Health Watch** each have an
  obvious shape (a running debt curve, a composition split, a z-score strip
  shared between the last two).
- **Cardio Fitness** and **Resting HR Trend** are single-metric. The
  contributors overlay already *is* their chart; a bespoke one would duplicate
  it. These two are arguably complete as they stand.
- **Cardiovascular Risk** and **Cardio Trajectory** both compute a projection
  the screen never draws.

_Consistency would look like:_ deciding the rule, not the instances — e.g. "any
insight that computes a shape its overlay can't express gets a card for it",
which would take the count from 4 to about 10 and deliberately leave the
single-metric ones alone.

### 4. Three placements for one class of section

Heart Age's pair sits above requirements and drivers (`:32`); Energy and Sleep
Regularity sit above "Score over time" (`:48`, `:54`, both commented with the
same argument — the thing itself is the finding, the score history is context);
Substance Impact sits *below* it (`:58`). Same class of card, three answers, and
two of the three have written reasoning.

_Consistency would look like:_ applying the Energy/Sleep-Regularity rule to all
of them, which moves Substance Impact up and Heart Age's pair down.

### 5. Caveat footnotes are ad-hoc

Score history, patterns, contributors and age history each close with a
provenance or limitations line. Energy curve, sleep regularity, substance load,
drivers, requirements, period contrast, lag and full-history have none. There is
no rule distinguishing them — the four that have one are the four that were
built with one.

### 6. Header trailing stats are ad-hoc

Score history (trend phrase), Energy ("N spent of M"), Sleep Regularity (social
jetlag), Substance Load (per week) put a figure in the top-right of the card.
Age history and contributors don't. Same absence of a rule.

### 7. Today and Insights disagree about the empty card

`TodayView` filters `cadence == .daily && primaryValue != nil`
(`DashboardView.swift:13`). `InsightsListView` filters on cadence alone
(`InsightsListView.swift:15`). So an ungrounded **trend** insight shows an "Add
your details" placeholder card, and an ungrounded **daily** insight silently
vanishes from the tab.

`InsightCard` already handles the empty case — it falls back to "Tap to add the
details needed" when there are no drivers but there are unmet requirements
(`:302`) — so the placeholder is a designed state that one of the two tabs never
reaches.

### 8. Two presentation flags no view consults

`MetricPresentation.allowsTimeframeSelection` and `.showsChart`
(`MetricPresentation.swift:28–29`) are read **only by
`PresentationTests.swift:58–59`**. `MetricDetailView` hard-codes the equivalent
logic in its `switch` at `:68` and in `standardSections`. They agree today, and
nothing keeps them agreeing — a new `staticAttribute`-like presentation would
set the flags and change no behaviour.

---

## How to keep this current

The matrix is derived from two places, and either one going stale invalidates
part of it:

- **Columns** come from `InsightDetailView.body`. Adding a section adds a
  column; changing a gate changes a column.
- **Rows** come from `InsightID.allCases`. Adding one adds a row — see the
  `add-insight` skill for the five switches it also feeds.
- **Cell values** come from each model's `InsightResult` construction:
  `requirements`, `contributors`, `driverLines`, `score`, `primaryValue`.

`docs/activeContext.md` and `docs/progress.md` remain the authority on *why*
things are the way they are. This file is only the *what*.
