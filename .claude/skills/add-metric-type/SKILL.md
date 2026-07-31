---
name: add-metric-type
description: Add a new MetricType to InsightKit correctly. Use whenever a new vital, measurement or body metric needs to become a first-class canonical metric — it feeds eight exhaustive switches and several tests, and missing one is this repo's most frequent CI break.
---

# Adding a `MetricType`

Deliberately load-bearing: the compiler will refuse to build until every
exhaustive switch handles the new case. That is the design, not an obstacle —
it forces a decision about how the metric is named, shown, charted and
validated. The cost is only a problem when you discover it from CI two minutes
later instead of locally.

**Run `./scripts/verify.sh` after step 2.** It lists exactly which switches
still don't mention your new case, without needing a compiler.

## 1. The case itself

`InsightKit/Sources/InsightKit/Models/MetricType.swift` — add to the enum.
Canonical units are the app's vocabulary: metres, kilograms, °C, mmHg, hours.
Convert at the provider boundary, never here.

## 2. The eight exhaustive switches

None has a `default:`, so all eight must be updated:

| Where | What it decides |
| --- | --- |
| `MetricType.swift` ▸ `displayName` | The name a human reads |
| `MetricType.swift` ▸ `unit` | Suffix. Empty where the value carries its own |
| `MetricPresentation.swift` ▸ `family` | Which system it measures. Drives pattern-tautology suppression |
| `MetricPresentation.swift` ▸ `chartStyleIndex` | Hue order. **Must stay contiguous from zero** |
| `MetricPresentation.swift` ▸ `presentation` | trend / range / total / bivariate / static layout |
| `MetricPresentation.swift` ▸ `maxValidInterval` | Longest gap a chart line may bridge |
| `MetricPresentation.swift` ▸ `referenceRange` | The published normal band, or `nil` — see below |
| `Signals/MetricSanitizer.swift` ▸ `requiresPositiveValue` | Whether zero is a real reading |

Safe (they have `default:` or are derived): `bucketStatistic`, `inSentence`,
`colourSlot`, `sharesMeasurementBasis`, `maxPlottableGap`.

⚠️ `MetricValueFormatter` has a `default:` that renders `Int(value.rounded())`,
so omitting a new metric compiles cleanly and silently prints 33.6 °C as "34".
Not compiler-enforced; do it anyway.

### `referenceRange` is usually `nil`, and that is the honest answer

Most metrics have no published normal range, and `nil` is the honest answer for them. Write
`case .newThing: return nil  // because …` with the reason — a silent `nil` is
the failure mode this repo keeps paying for. And do not reach for
`VitalSignsCheck.Spec`'s `hardLow`/`hardHigh`: those are *alarm* bounds, not
normal ranges, and a band drawn between them shades almost the whole plot.

### `chartStyleIndex` deserves thought

It is the order hues are claimed in, and the table front-loads the vitals most
likely to share one chart. If the new metric will appear on a crowded overlay,
put it early; if it's niche, append. `testStyleIndicesAreContiguousFromZero`
enforces contiguity, so inserting means renumbering everything after it.

### `family` is not cosmetic

It suppresses tautological patterns ("on days when heart rate changes, resting
heart rate does too"). If the new metric is derived from the same measurement
as an existing one, check `sharesMeasurementBasis(with:)` covers the pair —
heart rate and HRV are in *different* families but share a basis, and that
needed an explicit exception.

## 3. Get data into it

- **Apple Health**: add to `readMap` in `HealthKitService.swift`. Anything not
  in `readMap` lands in the raw "Other data" bucket instead.
- **A provider**: prefer a `PromotionRuleSet` entry (path/leaf/suffix →
  `MetricType` + unit conversion) over a parser change. Promotion is data, never
  inference — a field that merely *looks* like a known vital is catalogued as a
  proposal, not silently wired in.

## 4. Make something read it

A metric with no reader is invisible. Either add it to an insight's
`candidateMetrics` **and** emit a `MetricContribution` for it from the scoring
code, or accept that it is Vitals-tab-only and say so. `docs/architecture.md`
carries the metric → insight table; keep it current.

Read it through `VitalReader` (`Baseline/VitalReader.swift`) — the day's
de-duplicated value against a windowed baseline, with freshness. Every insight
does now; six used to hand-roll it and each got it wrong differently, which is
what the type exists to stop happening again.

## 5. Tests that will move

- `MetricColourSlotTests` — contiguity and per-chart hue distinctness
- Any coverage fixture in `VitalSignsTests` that enumerates metrics
- `ContributorsTests` if you touched an insight's candidates

## 6. Verify

```bash
./scripts/verify.sh --tests
```
