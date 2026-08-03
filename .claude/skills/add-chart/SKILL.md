---
name: add-chart
description: Build or review a Swift Charts view in this app without hitting the SDK hazards and encoding rules it has already been burned by. Use when adding a chart, reviewing one, changing how it encodes colour, dash or series selection, or acting on any "that chart looks wrong" report from the device.
---

# Adding or reviewing a chart

**Every rule here was learnt from a shipped defect. None is style.** Sections 7–9
are the ones a *review* should run through first: they are the failures CI cannot
see, because the app target has no test target and SwiftUI does not exist on
Linux, so the device is the only thing that can falsify them.

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

## 4. Gaps break, unless the bridge earns it

`maxValidInterval` per metric sets the longest gap a line may cross. Joining two
readings across a longer gap asserts a trend nobody measured. Every **measured**
`LineMark` is `.interpolationMethod(.linear)`: a curve between two readings
invents values nobody recorded.

**A short gap may be crossed with an inferred bridge**, and that bridge is the
one curved thing in the app. `SeriesBridging.isBridgeable` decides — bounded by a
multiple of the metric's own join distance *and* by a quarter of the visible
window. `GapBridge.smoothed()` supplies the path: a monotone cubic Hermite, which
provably has no interior extremum and never leaves the interval its two measured
ends define. The marks stay `.linear` **through those points** — an interpolation
method could overshoot, and not overshooting is the entire reason the curve is
built this way. Bridges are dashed (`Theme.projectedStroke`) and dimmed
(`SeriesBridging.bridgeProminence`, which takes the *quieter* end).

⚠️ **Change bridge rendering in one chart and you must change it in the other.**
`MultiSourceChart` and `MetricOverlayChart` both draw them, and shipping one
curved and one straight — the same silence rendered two ways — is a defect this
repo has now caused twice.

⚠️ If you bucket before splitting, **floor the gap rule at the bucket width**.
Comparing bucket starts against a sample-scale interval shatters the line into
single points at zoomed-out ranges. Use `[AggregatedPoint].segments(for:bucket:)`
(`SeriesSegmentation.swift`), never a hand-rolled comparison — the four copies of
that loop under two different rules *were* the defect.

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

## 7. Three things only the device can falsify

CI proves the chart *compiles*. It says nothing about what it draws, the app
target has no test target, and SwiftUI does not exist on Linux — so the phone is
the only gate for all three of these. Each cost a round trip on 2026-08-01.

⚠️ **A gradient in `foregroundStyle` resolves against the mark's own bounding
box, not the plot area.** `Theme.scoreFill(peak:)` takes the peak for exactly
this reason: assuming the plot area drew a full green-amber-red ramp squeezed
into the bottom sixth of a chart whose card scored 15. If a gradient's stops mean
anything (bands, thresholds), compute them against the shape's own extent.

⚠️ **A stacked series that is absent over a stretch still reserves a stacked
offset for it**, interpolated from its first real value, while its polygon starts
only where its data does. The two disagree and the disagreement is drawn as a
wedge of background opening between the bands. **Emit a value at every x for
every series, zero where the band is absent** — a zero-height band draws nothing
and costs one invisible mark.

⚠️ **`AreaMark(x:yStart:yEnd:)` takes no `stacking:` argument.** An absolute band
between two heights is inherently unstacked. It is also the min/max-band shape
this repo carried for months as an unverified hazard; it is now shipping in
`BodyCompositionTrendChart` and does work.

## 8. One quantity drawn over another: hatch it, never blend it

**This is the standing approach. Use `Theme.hatch(light:dark:_:)`.**

Whenever a value has to be shown *inside* or *over* something already coloured —
a share of a band, an estimated stretch of a measured series, two overlapping
spans — the instinct is a translucent fill, and the instinct is wrong.

A wash **mixes**. The reader sees a third colour that means nothing, and worse,
the mix is often nowhere near either parent: blue over red is purple, whatever
the ratio, because that is colour arithmetic and not a tuning problem. Five
attempts at hue and opacity were spent on the water band in
`BodyCompositionTrendChart` before the mechanism changed rather than the value.

A hatch **never** mixes. Every pixel is one colour or the other, so both stay
exactly themselves and the thing underneath is plainly visible between the
stripes. The worked example is water inside the muscle band: the muscle band is
drawn **whole, in muscle red**, and the water is a hatch painted over its lower
portion. Note the second half of that — carving the water out as its own slice
meant the muscle stopped being red across that stretch, so nothing read as being
*underneath*, and no colour choice could put it back. **The problem is usually
geometry before it is hue.**

Three things fall out of the worked example that generalise:

- Draw the host **whole** and paint over it; do not subdivide it.
- The overlaid quantity contributes **no mass to a stack** — give it an
  `AreaMark(x:yStart:yEnd:)` between two cumulative heights instead, and compute
  that span in InsightKit where it can be tested
  (`BodyCompositionSplit.waterSpan`).
- In a **key**, the same quantity is drawn plain and opaque. A key answers "which
  substance is this"; what it sits on top of is a fact about placement.

## 9. When a colour looks wrong, read the pixel before choosing another one

**First move on any "that colour is wrong" report: sample the composited colour
out of the screenshot.** Not pick a new hue — measure the one on screen.

Two sessions have burned multiple rounds tuning a visual by eye — launch-screen
density (three rounds), water-over-muscle (five) — and both collapsed to a single
step the moment something was measured. In the water case the measurement was
rgb(126, 88, 121): red and blue near-equal with green suppressed, which *is* the
definition of plum, and which named the cause instantly after four rounds of
guessing had not.

The general rule: **when a visual fix keeps landing in the same wrong place,
check whether the mechanism can produce the target at all before choosing another
value for it.** Four of those rounds were spent looking for a ratio that does not
exist.

## 9a. Every chart carries the substance shading

**The user's standing rule, 2026-08-03:** *"make sure the stimulant impact
shading is on EVERY chart in the app, and this is a design rule going forward."*

`ScrollableMetricChart` draws it for every chart that wraps it, reading the
windows from the environment — so a new chart that wraps the wrapper gets it and
needs no code. A chart that builds its own `Chart {}` must call
`SubstanceShading.marks(_:in:)` **first**, so it sits behind the data.

`verify.sh` fails on any file with a raw `Chart {` that neither wraps the
wrapper, nor calls `SubstanceShading`, nor carries:

```swift
// substance-shading: exempt — <why>
```

The only honest exemption is an x axis that is not a date —
`FitnessProjectionChart` plots months *ahead*, where a window that happened
yesterday has nowhere to land. "It did not seem relevant" is not an exemption:
the shading claims only that something was logged in that stretch, which is true
on every chart, and the caption (`SubstanceShading.caption`) says exactly that.

What it replaced: the shading was gated on the metrics
`SubstanceResponseAnalyzer` compares, on the reasoning that shading a weight
chart would assert a relationship nothing had looked for. The narrower rule —
*this marks when, not what it did* — is what makes it safe everywhere.

## 10. Review checklist

Run this against any chart being added or reviewed. Each line is a shipped defect.

- [ ] Mark builders have an explicit `-> some ChartContent` (§2).
- [ ] Every dash means "not measured", and nothing else does (§3).
- [ ] Gaps are bridged only where the bridge is earned, and drawn as inferred (§4).
- [ ] Anything deciding whether two series can look alike lives in InsightKit (§5).
- [ ] A gradient's stops are computed against the **mark's** extent, not the plot
      area (§7).
- [ ] Every stacked series has a value at **every** x, zero where absent (§7).
- [ ] Band membership does not change from point to point (§7).
- [ ] Anything drawn over anything else is a hatch, not a wash (§8).
- [ ] Colour complaints were answered by measuring the pixel, not by guessing (§9).
- [ ] The axis fits the data in the **visible window**, not a round number above
      it — and a stacked share chart still starts at zero.
