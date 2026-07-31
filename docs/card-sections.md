# Card sections — what each screen actually renders

_Audit of record. First written 2026-07-31 from a read of the code; re-derived
the same day after Phase 1 of the consistency work landed. Every cell below was
read out of the code, not carried over from the previous version._

This exists because the app has three families of card-based screen and no
written record of which sections each one shows. The symptom that prompted it:
some insight detail screens have a chart of their own and most don't.

**Phase 1 of the consistency work is done.** Five of the eight gaps the first
audit found are closed; three remain and are listed with the reason. Phase 2 —
the remaining unique sections — is scoped in `docs/progress.md`.

---

## 1. Insight detail screens

One file renders all seventeen: `HealthInsights/Features/Insights/InsightDetailView.swift`.
Its `body` is a fixed sequence. Nothing is per-insight except the gates.

### The sections, in render order

| # | Key | Section | Gate |
|---|---|---|---|
| 1 | `Hdr` | header — dial or headline, confidence badge, explanation | always |
| 2 | `Drv` | "What's driving this" | `!drivers.isEmpty` |
| 3 | `V&A` | **"View & add"** — what you've given, what's missing, how to add | the model's `contributions` is non-empty |
| 4 | `Ages` | "How old are you behaving?" | `id == .heartAge` |
| 5 | `AgeHx` | "Both ages over time" | `id == .heartAge`, ≥3 points |
| 6 | `BPCh` | "Your readings" — the paired chart | `id == .bloodPressure`, any readings |
| 7 | `Ergy` | "Today" — energy curve | `id == .energy`, curve ≥2 |
| 8 | `Frtn` | "Your fortnight" — bedtimes | `id == .circadianConsistency` |
| — | *picker* | **the timeframe control** — a screen-level control, not a card | any timeframe-driven section renders |
| 9 | `Load` | "Cardiovascular load" | `id == .substanceImpact`, series ≥7 |
| 10 | `ScrHx` | "Score over time" | history ≥2 |
| 11 | `Goes` | "What goes into this" — overlay, scale picker, legend | series non-empty |
| 12 | `Patt` | "Patterns worth a look" | patterns non-empty |
| 13 | `1st` | "What comes first" — lag | leads non-empty |
| 14 | `Chg` | "What changed" — period contrast | changes non-empty |
| 15 | `Hist` | "Full history" — one link per input | contributors non-empty |
| 16 | `Fbk` | "Was this accurate?" | `primaryValue != nil` |
| 17 | `Disc` | disclaimer | always |

Sections 4–9 are the **bespoke slot** — one placement rule, above "Score over
time", because the card's own subject is the finding and the months of scores
derived from it are the supporting context.

### The matrix

**Key** — `●` always renders · `◐` renders once the data clears a floor ·
`○` **cannot ever render** — the code names a different `InsightID`.

| Insight | Tab | `Hdr` | `Drv` | `V&A` | `Ages` | `AgeHx` | `BPCh` | `Ergy` | `Frtn` | `Load` | `ScrHx` | `Goes` | `Patt` | `1st` | `Chg` | `Hist` | `Fbk` | `Disc` |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Readiness | Today | ● | ◐ | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Vitals Check | Today | ● | ◐ | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Sleep Quality | Today | ● | ◐ | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Energy | Today | ● | ◐ | ○ | ○ | ○ | ○ | **◐** | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Health Watch | Today | ● | ◐ | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Sleep Debt | Today | ● | ◐ | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Substance Impact | Today | ● | ◐ | **●** | ○ | ○ | ○ | ○ | ○ | **◐** | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Cardiovascular Risk | Insights | ● | ◐ | **●** | ○ | ○ | ○ | ○ | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Heart Health | Insights | ● | ◐ | **●** | ○ | ○ | ○ | ○ | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Heart & Fitness Age | Insights | ● | ◐ | **●** | **◐** | **◐** | ○ | ○ | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Blood Pressure | Insights | ● | ◐ | **●** | ○ | ○ | **◐** | ○ | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Cardio Fitness | Insights | ● | ◐ | **●** | ○ | ○ | ○ | ○ | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Cardio Trajectory | Insights | ● | ◐ | **●** | ○ | ○ | ○ | ○ | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Body Composition | Insights | ● | ◐ | **●** | ○ | ○ | ○ | ○ | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Resting HR Trend | Insights | ● | ◐ | ○ | ○ | ○ | ○ | ○ | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Where You Stand | Insights | ● | ◐ | **●** | ○ | ○ | ○ | ○ | ○ | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Sleep Regularity | Insights | ● | ◐ | ○ | ○ | ○ | ○ | ○ | **◐** | ○ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |

**Reading the columns down:**

- **Ten of the seventeen sections are uniform across all seventeen insights** —
  up from eight before Phase 1. The two that changed are `1st` and `Chg`, which
  used to be off for the seven daily insights.
- **`V&A` reaches nine**: the eight models that declare grounding requirements,
  plus Substance Impact, which declares none and overrides because its whole
  input is the log.
- **Six columns are the bespoke slot**, touching five insights. That is the one
  substantial gap left, and Phase 2 is about it.

### Per-insight facts behind the matrix

| Insight | `cadence` | `requirements` | `contributions` | emits `contributors` | bespoke visual |
|---|---|---|---|---|---|
| Readiness | daily | 0 | — | ✅ components | — |
| Vitals Check | daily | 0 | — | ✅ readings (weight 0) | — |
| Sleep Quality | daily | 0 | — | ✅ components | — |
| Energy | daily | 0 | — | ✅ | `EnergyCurveChart` |
| Health Watch | daily | 0 | — | ✅ signals (weight 0) | — |
| Sleep Debt | daily | 0 | — | ✅ | — |
| Substance Impact | daily | 0 | **`.substanceLog`** (override) | ✅ | `SubstanceLoadChart` |
| Cardiovascular Risk | trend | 10 (6 fixed + 4 for `.combined`) | `.groundingFacts` | ✅ systolic only | — |
| Heart Health | trend | 2 | `.groundingFacts` | ✅ components | — |
| Heart & Fitness Age | trend | 6 | `.groundingFacts` | ✅ (weight 0) | `AgeHistoryChart` + 3-age row |
| Blood Pressure | trend | 2 | **`.bloodPressureReadings`** (override) | ✅ sys/dia | `BloodPressureChart` |
| Cardio Fitness | trend | 2 | `.groundingFacts` | ✅ VO₂max | — |
| Cardio Trajectory | trend | 2 | `.groundingFacts` | ✅ 4 metrics | — |
| Body Composition | trend | 2 | `.groundingFacts` | ✅ present metrics | — |
| Resting HR Trend | trend | 0 | — | ✅ resting HR | — |
| Where You Stand | trend | 2 | `.groundingFacts` | ✅ standings (weight 0) | — |
| Sleep Regularity | trend | 0 | — | ✅ | `SleepOnsetStripChart` |

Three things this settles:

- **`contributions` is derived, not switched.** The default reads the
  `requirements` the model already declares, so the two lists cannot drift and a
  new insight cannot forget to opt in. Only the two log-backed models override.
  It is a **protocol requirement** with a default in an extension — an
  extension-only member would dispatch statically through `any InsightModel` and
  both overrides would be dead code.
- **Every model emits `contributors` on its happy path**, so the
  `candidateMetrics` fallback is reached only on a "no data yet" branch.
- **Every model classifies its drivers** into notable and routine, so the
  "Show N more in your normal range" disclosure works everywhere. The
  early-return branches deliberately don't, and the screen shows those lines in
  full rather than hiding them.

---

## 2. Metric detail screens

`MetricDetailView` switches on `subject.presentation` (`:68`) into three
structurally different bodies.

| Section | `cumulativeTrend`<br>weight, body comp | `fluctuatingRange`<br>HR, HRV, sleep | `cumulativeTotal`<br>steps, energy | `discreteBivariate`<br>blood pressure | `staticAttribute`<br>height |
|---|---|---|---|---|---|
| summary card | Change over this period | Range over this period | Daily totals | ○ | current value |
| timeframe picker | ✅ | ✅ | ✅ | ✅ | ○ |
| chart | `MultiSourceChart` | ✅ | ✅ | `BloodPressureChart` (shared) | ○ |
| scrub read-out | in-chart | in-chart | in-chart | above the chart | ○ |
| per-source breakdown | ✅ | ✅ | ✅ | ○ | ○ |
| per-source averages | multi-source only | multi-source only | multi-source only | ○ | ○ |
| reference range + provenance | from `referenceRange` | ✅ | ✅ | restated in the chart's legend | ○ |
| substance-window shading | ✅ | ✅ | ✅ | ○ | ○ |
| gap / bridge key | ✅ | ✅ | ✅ | ○ | ○ |
| log-scale toggle | ○ by presentation | ✅ | ✅ | ○ | ○ |
| calibration | ○ | ○ | ○ | ✅ | ○ |
| dated history list | ○ | ○ | ○ | ✅ paged | Earlier entries |
| add a reading | ○ | ○ | ○ | ✅ | ○ |

Blood pressure is still the outlier, but less of one: its chart is now
`BloodPressureChart`, the same component the insight card draws, rather than a
private copy. Some of the rest is forced — a paired reading cannot use the
single-series chart, and the `Chart3DContent` hazard is why the read-out sits
above the plot. The missing source breakdown and substance shading are not.

---

## 3. List and tab surfaces

| Surface | Cards, in order | Which insights it lists |
|---|---|---|
| **Today** (`DashboardView.swift`) | summary · suggestion (one, dismissible) · Last night · Vitals glance · grounding banner · daily insight tiles | `cadence == .daily && isWorthShowing` |
| **Insights** (`InsightsListView.swift`) | "Improve your health" (collapsed) · subtitle · "How your scores compare" · trend insight tiles | `cadence == .trend && isWorthShowing` |
| **Vitals** (`VitalsView.swift`) | `List` sections: 4 metric groups · Blood pressure · Substances · Other data | rows, not cards |

`InsightResult.isWorthShowing` lives in InsightKit and is one rule for both
tabs: a card with no number earns its place when there is something the user can
do about it.

---

## 4. The gaps

### Closed in Phase 1

1. **The timeframe picker is no longer trapped inside "Score over time."** It is
   a screen-level control above the sections that read it. It used to drive the
   overlay, patterns and lag cards from inside a section that disappears under
   two replayable days.
2. **The deep-dive pair lost its cadence gate.** `LagFinder` and
   `PeriodContrast`'s own floors decide, which is how every other section works.
3. **One placement rule for the bespoke slot** — above "Score over time".
   Substance Impact moved up, Heart Age's pair moved down.
4. **The two tabs agree**, on a rule rather than on one tab's behaviour.
5. **Blood pressure's chart is on the card that talks about it**, and every
   card that takes user input has the same "View & add" section. This one was
   not in the original audit — it came from the user.

### Still open

6. **Bespoke charts: five of seventeen.** The twelve without are not equally
   deserving:
   - **Readiness and Heart Health** each define their own nested `Component`
     type — `name`, `score`, `weight`, `detail`, `metric`, `higherIsBetter` —
     identical field for field (`ReadinessScore.swift:17`,
     `HeartHealthScore.swift:15`). One weighted-contribution card would serve
     both. **Sleep Quality** computes the same seven weighted sub-scores as
     locals (`SleepQualityInsight.swift:130`) and would need them lifted first.
   - **Where You Stand** has percentiles it states only as sentences.
     **Sleep Debt, Body Composition, Vitals Check, Health Watch** each have an
     obvious shape. **Cardiovascular Risk** and **Cardio Trajectory** both
     compute a projection nothing draws.
   - **Cardio Fitness and Resting HR Trend get nothing, deliberately.** They are
     single-metric; the contributors overlay already *is* their chart.
7. **Caveat footnotes and header trailing stats are ad-hoc.** Four sections have
   a provenance line and a top-right figure; the rest don't, and there is no
   rule distinguishing them. Deferred to Phase 2 so the rule is applied once,
   across the new sections and the old ones together.
8. **Two presentation flags no view consults.**
   `MetricPresentation.allowsTimeframeSelection` and `.showsChart`
   (`MetricPresentation.swift:28–29`) are read only by
   `PresentationTests.swift:58–59`; `MetricDetailView` hard-codes the equivalent
   logic. They agree today and nothing keeps them agreeing.

---

## How to keep this current

The matrix is derived from two places, and either going stale invalidates part
of it:

- **Columns** come from `InsightDetailView.body`.
- **Rows** come from `InsightID.allCases` — see the `add-insight` skill.
- **Cell values** come from each model's `InsightResult` construction plus its
  `requirements` / `contributions`.

`docs/activeContext.md` and `docs/progress.md` remain the authority on *why*
things are the way they are. This file is only the *what*.
