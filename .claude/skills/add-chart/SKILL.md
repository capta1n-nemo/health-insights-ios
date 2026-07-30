---
name: add-chart
description: Build a new Swift Charts view in this app without hitting the SDK hazards and encoding rules it has already been burned by. Use when adding any chart, or changing how an existing one encodes colour, dash or series selection.
---

# Adding a chart

Three rules here were each learnt from a shipped defect. None is style.

## 1. Wrap `ScrollableMetricChart`

It owns pan, zoom, scrub, the scroll domain and the y-scale for every chart in
the app. `MultiSourceChart`, `ScoreHistoryChart`, `MetricOverlayChart`,
`AgeHistoryChart` and the blood-pressure chart all wrap it. Growing a private
copy of that logic is how the "All squashes into a strip" bug happened.

The marks closure is handed the padded date range; slice and thin your own data
inside it.

## 2. Every mark builder gets an explicit `-> some ChartContent`

```swift
@ChartContentBuilder
private func marks(_ visible: [Point]) -> some ChartContent { ... }
```

Without the explicit return type, a `RuleMark` / `AreaMark` / `RectangleMark` /
`BarMark` chain can resolve to **`Chart3DContent`** on this SDK and silently
drop `.lineStyle`, `.foregroundStyle` and `.annotation`. It compiles. It just
renders wrong. This has broken CI twice and shipped once.

Corollaries:
- Prefer `ForEach` over a bare `if` inside a chart builder — a conditional is
  the exact shape that has dropped modifiers here before. `MetricOverlayChart`'s
  `baselineMark` uses `ForEach(scale == .zScore ? [0.0] : [])` for this reason.
- Scrub read-outs go **above** the chart as a normal view, never as a mark
  `.annotation` — 3D content has no `annotation`.

## 3. Dash means "not measured". Nothing else.

Every measured series is a **solid** line. A dashed or dotted stroke means the
value was inferred: a gap, a projection, a reference level
(`Theme.projectedStroke`).

Identity used to be a (hue, dash) pair — collision-free by construction, and
practically wrong, because a dashed line reads as *an estimate* to anyone
looking at it. The user reported the dashes as gap markers, which was the
correct reading.

So identity is **hue alone**, which bounds how many lines a chart may draw:

- Resolve hues with `MetricPalette.slots(for:)` and pass the result to
  `Theme.metricColor(_:slots:)`. Calling it **without** `slots:` falls back to a
  preferred slot that collides — RMSSD/SDNN, systolic/diastolic, heart
  rate/respiratory rate and two more pairs all share a preferred hue.
- Use `OverlaySelection` to decide what's drawn. Eight hues is the ceiling; past
  `comfortableSeriesCount` (6) it draws only the signals away from baseline,
  capped at `hueCount` (8).
- "Away from baseline" is `OverlaySelection.anomaly` — recent **or** sustained,
  never "did any day ever depart". The naive version drew a flat line with one
  three-week-old blip while the legend beside it said "steady".

## 4. Gaps break; they are never bridged silently

`maxValidInterval` per metric sets the longest gap a line may cross. Joining two
readings across a longer gap asserts a trend nobody measured. Every `LineMark`
is `.interpolationMethod(.linear)` — a curve invents values.

⚠️ If you bucket before splitting, **floor the gap rule at the bucket width**.
Comparing bucket starts against a sample-scale interval shatters the line into
single points at zoomed-out ranges. `NormalizedSeries.segments()` guards this
with a two-day floor; `MultiSourceChart` does not, and has the bug.

## 5. Anything that decides whether two lines can look alike goes in InsightKit

Not the view. The app target has no test target, so a rule living there is
verified only by eye — which is exactly how two identical reds shipped.
`OverlaySelection` and `MetricPalette` are in InsightKit for this reason, and
both have tests built from the screenshot that caught the bug.

## 6. Colour bands

`BloodPressureSections` shades the ACC/AHA systolic categories. Note the honest
part: it shades **systolic only** and says so in the caption, because the two
lines share an axis but not thresholds — 85 is stage 1 diastolic and normal
systolic. If your chart's two series don't share thresholds, don't shade one set
and let it read as applying to both.

Clinical bounds for 17 vitals already exist in `VitalSignsInsight.Spec.specs`
(`hardLow`/`hardHigh`), currently `internal`.
