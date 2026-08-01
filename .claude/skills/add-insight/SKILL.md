---
name: add-insight
description: Add a new InsightModel and its InsightID correctly. Use when creating a new health insight card. An InsightID feeds five switches across two targets, and two registrations that fail silently rather than at compile time.
---

# Adding an insight

Commit `bf68e67` is titled *"Add the missing .vitalSigns cases to exhaustive
InsightID switches"*, body: *"CI caught it… I only updated the engine and
cadence, so the build broke."* This skill is that commit, turned into a list.

`docs/activeContext.md` summarises this; **the table below is the authority.**
Four of the five break the build. Only `cadence` fails silently, by putting the
card on the wrong tab.

## 1. The `InsightID` case

`InsightKit/Sources/InsightKit/Insights/Insight.swift`. The raw value is
persisted (`InsightScoreRecord`, feedback, telemetry), so **renaming an existing
case orphans stored history**. Choose the name once.

## 2. Five switches, two targets

| File | Symbol | Exhaustive? |
| --- | --- | --- |
| `InsightKit/.../Insights/Insight.swift` | `cadence` | has `default:` — check anyway, a wrong cadence puts the card on the wrong tab |
| `InsightKit/.../Feedback/Feedback.swift` | `modelVersion` | **yes — compile error** |
| `HealthInsights/Features/Settings/TelemetryOutboxView.swift` | `prettyInsight` | **yes — compile error** |
| `HealthInsights/Features/Dashboard/DashboardView.swift` | `iconName` | **yes — compile error** |
| `InsightKit/.../Presentation/InsightPalette.swift` | `colourSlot` | **yes — compile error** |

`cadence` decides the tab: `.daily` → Today, `.trend` → Insights. The deep-dive
cards (lagged correlation, period contrast) are gated on `.trend`.

`colourSlot` declares a *preference*, and `InsightPalette.slots(for:)` resolves
collisions per chart — so two cards on one chart can no longer share a hue however
crowded it gets. Give the new insight a slot number nothing else uses:
`testEveryInsightHasADistinctPreference` fails otherwise. There are more insights
than the palette's eight hues by design; the resolver is what makes that safe.

This used to be a fixed table in `Theme.swift` with four colliding pairs and a
comment claiming safety because "never more than four are on screen at once" —
which was untrue, because the user picks which four.

## 3. Two registrations that fail silently

Neither breaks the build. Both make the insight invisible.

- **`InsightEngine`** (`Insights/InsightEngine.swift`) — add the model to the
  registry. Not registered means never evaluated.
- **The view layer** renders `dailyResults` / `trendResults` off the engine, so
  registration is what puts the card on screen.

`SubstanceImpact` was the cautionary case for a long time: it shipped as a card
but was **not** an `InsightModel` and was not in the engine — a free function the
app called directly — so score recording, score replay, the comparison chart and
grounding collection all skipped it silently, for as long as it existed. It is a
registered model now. The lesson stands: registration is not a formality, it is
what makes an insight visible to everything that iterates the registry.

Its input is the user's substance log, which the engine doesn't carry. The fix
was to hold the log as construction state on the model and rebind it with
`InsightEngine.withSubstanceLog(_:)` — worth copying if a new insight ever needs
something `samples` and `profile` can't supply, rather than growing a third
`evaluate` overload.

## 4. The protocol requirements

- **`candidateMetrics`** — no default implementation, so it won't compile
  without one. The declared superset of what the model may read; it drives the
  "no data yet" rows.
- **`evaluate(samples:profile:now:)`** — the `events:` overload has a default
  that forwards here, so only override it if the insight reads Apple's discrete
  event flags.
- **`requirements`** — grounding facts the user must supply. Empty is fine for
  an insight built purely from sensed data. **It now drives two things**: the
  old grounding prompt *and* the card's "View & add" section, via
  `contributions` below.
- **`contributions`** — what the card lets the user view and add
  (`ContributionRoute`). **Has a default**, so a new insight compiles without
  touching it and gets the right answer: the default returns
  `.groundingFacts(requirements.map(\.kind))`, or nothing when `requirements` is
  empty. Deliberately derived rather than switched over `InsightID` — a sixth
  exhaustive switch on that enum is the last thing this repo needs.
  **Override only when the input is a dated log rather than a profile fact.**
  Two models do: `BloodPressureInsight` (`.bloodPressureReadings`) and
  `SubstanceImpactInsight` (`.substanceLog`, despite declaring no requirements
  at all). If you add a third, it needs a matching branch in
  `ViewAndAddSection` — the enum has no `default:`, so that part will not
  compile until you do, which is the intended failure.

## 5. Emit a score and contributors, or say why not

- **`score`** should be non-nil in the normal case, and every shipped card now
  manages it. Three used to fail, and how they were fixed is the useful part:
  Body Composition scored `nil` unconditionally while printing "obese" as a
  driver — the judgement without the calibration; Cardiovascular Risk mapped a
  continuous risk onto four fixed numbers, so 4.9% dialled 90 and 5.1% dialled 72;
  Blood Pressure filled its dial only from a reading under 24 hours old, so a
  weekly cuffer saw a blank six days in seven. If a new insight is tempted toward
  `score: nil`, it is usually one of those three shapes wearing a new hat.
- **`contributors`** — emit a `MetricContribution` as each component is built.
  The detail chart is driven by these, so a component added to the score becomes
  a line with no second edit.
- **`weighting` — a third registration that fails silently.** It defaults to
  `.unstated`, which is deliberate (a new insight should be silent rather than
  claim a basis nobody chose for it) and means a card can ship with a score and
  no account of how its inputs divide it. `ScoreAttributionTests
  .testEveryScoringCardStatesHowItsNumberIsFormed` fails if you forget, which is
  the only reason this is not a fourth silent registration. Pick from
  `ScoreWeighting`: `weightedAverage`, `singleMeasure`, `equation`, `fit`,
  `measurement`, `unstated`.
- **Everything the card charts must carry a weight.** Set by the user on
  2026-08-01, reversing the old "weight 0 is more honest than an invented
  weight" rule — which is still correct about *inventing* one, and was being
  used to justify not *attributing* one. If a signal has no published 0–100
  curve, `ScoreBlend.supporting(_:higherIsBetter:)` judges it against the
  reader's own baseline and `ScoreBlend.blend` gives the supporting group
  `SupportingSignal.collectiveShare` (20%) between them. **If a signal genuinely
  cannot carry a share, say why in its `detail` string** — there are three such
  rows in the whole app and each names its reason;
  `testAnUnweightedRowAlwaysSaysWhy` fails on a bare zero.
- **Declare only what you read.** `candidateMetrics` is not a wish list.
  `testEveryDeclaredInputWithDataIsActuallyRead` fails when a declared metric
  with data never reaches `contributors`, because
  `ChartedContributions.resolve` substitutes the declared list *only* when a
  card reports nothing — so on a card reporting anything at all, a
  declared-but-unread input charts nowhere and links nowhere. Four cards were
  doing this on 2026-08-01. The one allowed exception is genuine alternatives
  (rMSSD or SDNN, a deviation or an absolute), which live in
  `MetricType.interchangeableGroups`.
- **Classify driver lines.** `InsightDriver.component(_:score:)` sets
  `isNotable` from the sub-score, which is what lets the card lead with
  departures and fold the routine ones away. Leaving `isNotable` nil means "this
  insight doesn't draw the distinction" — honest, but the card then shows every
  line.

## 6. Read inputs through `VitalReader`

`Baseline/VitalReader.swift` — the day's de-duplicated value against a windowed
baseline, with freshness. Six insights still hand-roll this and each got it
wrong differently: raw `series.last` is one minute of one afternoon, and
`meanValue` over a 180-day lookback cannot move.

## 7. Verify

```bash
./scripts/verify.sh --tests
```

`ContributorsTests` asserts contributors are a subset of `candidateMetrics`, and
**since 2026-08-01 the converse too** — every declared metric with data must be
read. `ScoreAttributionTests` asserts that a card with a score states its
`weighting`, that its shares sum to 1, and that any row with no share says why.
