---
name: add-insight
description: Add a new InsightModel and its InsightID correctly. Use when creating a new health insight card. An InsightID feeds five switches across two targets, and two registrations that fail silently rather than at compile time.
---

# Adding an insight

Commit `bf68e67` is titled *"Add the missing .vitalSigns cases to exhaustive
InsightID switches"*, body: *"CI caught it… I only updated the engine and
cadence, so the build broke."* This skill is that commit, turned into a list.

**The list in `docs/activeContext.md` is incomplete** — it names three switches;
there are five. Trust this file.

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
| `HealthInsights/Features/Dashboard/DashboardView.swift` | `iconName` | has `default:` — silently gives the wrong icon |
| `HealthInsights/DesignSystem/Theme.swift` | `insightTint` | has `default:` — silently shares a hue |

`cadence` decides the tab: `.daily` → Today, `.trend` → Insights. The deep-dive
cards (lagged correlation, period contrast) are gated on `.trend`.

⚠️ `insightTint` already has **four colliding pairs** (heartAge/bloodPressure,
cardioFitness/bodyComposition, heartHealth/restingHeartRateTrend,
cardioTrajectory/substanceImpact). Its comment claims safety because "never more
than four are on screen at once" — but the *user* picks which four on the score
comparison chart. Don't add a fifth collision; pick a free slot.

## 3. Two registrations that fail silently

Neither breaks the build. Both make the insight invisible.

- **`InsightEngine`** (`Insights/InsightEngine.swift`) — add the model to the
  registry. Not registered means never evaluated.
- **The view layer** renders `dailyResults` / `trendResults` off the engine, so
  registration is what puts the card on screen.

`SubstanceImpact` is the cautionary case: it ships as a card but is **not** an
`InsightModel` and is not in the engine — it is built by a free function the app
calls directly. Anything applied "to every insight" silently skips it.

## 4. The protocol requirements

- **`candidateMetrics`** — no default implementation, so it won't compile
  without one. The declared superset of what the model may read; it drives the
  "no data yet" rows.
- **`evaluate(samples:profile:now:)`** — the `events:` overload has a default
  that forwards here, so only override it if the insight reads Apple's discrete
  event flags.
- **`requirements`** — grounding facts the user must supply. Empty is fine for
  an insight built purely from sensed data.

## 5. Emit a score and contributors, or say why not

- **`score`** should be non-nil in the normal case. Three cards currently fail
  this and it is logged as a defect, not a pattern to copy: Body Composition
  hard-codes `score: nil`, Cardiovascular Risk uses a four-step function
  (4.9% dials 90, 5.1% dials 72), and Blood Pressure is nil on most days.
- **`contributors`** — emit a `MetricContribution` as each component is built.
  The detail chart is driven by these, so a component added to the score becomes
  a line with no second edit.
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

`ContributorsTests` asserts contributors are a subset of `candidateMetrics`.
