# Card sections — what each screen actually renders

_Audit of record. Re-derived 2026-07-31 after the consolidation from seventeen
insight cards to nine. Every cell was read out of the code._

Written because the app had three families of card-based screen and no record of
which sections each shows. The first pass found eight inconsistencies; five were
closed in Phase 1. Then the count itself turned out to be the real problem —
seventeen cards with three built on VO₂max, three on sleep duration and three
scanning the same baselines — and they were merged to nine.

**Phase 2** (the remaining unique sections) is scoped in `docs/progress.md` and
is now over nine cards rather than seventeen.

---

## 1. Insight detail screens

One file renders all nine: `HealthInsights/Features/Insights/InsightDetailView.swift`.
Its `body` is a fixed sequence. Nothing is per-insight except the gates.

### The sections, in render order

| # | Key | Section | Gate |
|---|---|---|---|
| 1 | `Hdr` | header — dial or headline, confidence badge, explanation | always |
| 2 | `Drv` | "What's driving this" | `!drivers.isEmpty` |
| 3 | `V&A` | "View & add" — what you've given, what's missing, how to add | the model's `contributions` is non-empty |
| 4 | *bespoke* | the card's own picture of its own subject | one `switch`, six cards |
| — | *picker* | the timeframe control — a screen-level control, not a card | any timeframe-driven section renders |
| 5 | `ScrHx` | "Score over time" | history ≥2 |
| 6 | `Goes` | "What goes into this" — overlay, scale picker, legend | series non-empty |
| 7 | `Patt` | "Patterns worth a look" | patterns non-empty |
| 8 | `1st` | "What comes first" — lag | leads non-empty |
| 9 | `Chg` | "What changed" — period contrast | changes non-empty |
| 10 | `Hist` | "Full history" — one link per input | contributors non-empty |
| 11 | `Fbk` | "Was this accurate?" | `primaryValue != nil` |
| 12 | `Disc` | disclaimer | always |

### The matrix

**Key** — `●` always renders · `◐` renders once the data clears a floor ·
`○` cannot ever render.

| Insight | Tab | `Hdr` | `Drv` | `V&A` | bespoke (+ nested) | `ScrHx` | `Goes` | `Patt` | `1st` | `Chg` | `Hist` | `Fbk` | `Disc` |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Readiness | Today | ● | ◐ | ○ | ◐ "How this is weighted" **+ "How far from your normal"** | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Sleep | Today | ● | ◐ | ○ | ◐ "Your fortnight" | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Energy | Today | ● | ◐ | ○ | ◐ "Today" curve | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Substance Impact | Today | ● | ◐ | ● | ◐ "Cardiovascular load" | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Heart Health | Insights | ● | ◐ | ● | ◐ "How this is weighted" **+ "How you compare"** | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Fitness | Insights | ● | ◐ | ● | ◐ "Fitness age over time" **+ "Where this is heading"** | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Heart Attack & Stroke Risk | Insights | ● | ◐ | ● | ◐ "Heart age over time" **+ "If today's numbers hold"** | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Blood Pressure | Insights | ● | ◐ | ● | ◐ "Your readings" | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |
| Body Composition | Insights | ● | ◐ | ● | ◐ "What you're made of" + "How that has changed" | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ | ● |

**The bespoke slot is still one slot.** Five cards now draw two things in it,
separated by a `Divider()` and wrapped in `NestedInsightSection` — the pattern
Body Composition established. A second *top-level* section would have needed a
second placement rule, and the one placement rule is the thing Phase 1 bought.

**Ten of the twelve sections are uniform across all nine cards.** The two that
are not:

- **`V&A` reaches six.** The three without it — Readiness, Sleep, Energy — ask
  the user for nothing and are built entirely from sensed data. That is correct,
  not a gap.
- **The bespoke slot reaches six.** Heart Health, Body Composition and Readiness
  are what Phase 2 is about.

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
| **Today** | summary · suggestion · Last night · Vitals glance · grounding banner · 4 daily tiles | `cadence == .daily && isWorthShowing` |
| **Insights** | "Improve your health" · subtitle · score comparison · 5 trend tiles | `cadence == .trend && isWorthShowing` |
| **Vitals** | 4 metric groups · Blood pressure · Substances · Other data | rows, not cards |
| **Settings ▸ Export my data** | inventory (Markdown) · full export (JSON) · browse the unmodelled | the development feedback loop |

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

---

## How to keep this current

- **Columns** come from `InsightDetailView.body`.
- **Rows** come from `InsightID.allCases` — nine — see the `add-insight` skill.
- **Cell values** come from each model's `InsightResult` plus its `requirements`
  and `contributions`.

`docs/activeContext.md` and `docs/progress.md` remain the authority on *why*.
