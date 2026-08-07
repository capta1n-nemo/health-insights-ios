# Accessibility for charts, custom visualisations and dense cards (D6)

**Status:** research only — no code written, no shared file edited. Every measurement below was taken from this working copy on 2026-08-07 or derived by running code against the installed iOS SDK; every citation carries author, venue, n and effect size, and the places where no evidence exists are marked as such.

---

## Summary

The app has **52 live `.accessibility*` call sites in 22 of 288 source files** — more than the brief's "23", but concentrated in the wrong places. The brief's claim that "charts, the radar web and the body mesh carry no VoiceOver description at all" is **two-thirds wrong and one-third worse than stated**: `SymptomRadarWebCard` and `ScoreBalanceWeb` already speak a per-vertex sentence each, and they are the two best-described views in the app; meanwhile **17 of the 18 `*Chart.swift` files contain zero accessibility code**, and `BodyMeshView` — an `SCNView` behind `UIViewRepresentable` — is a genuine hard null that VoiceOver cannot enter at all. The single highest-leverage fact I found is that **`accessibilityChartDescriptor(_:)` is an extension on `View`, not on `Chart`** (iOS 15+, confirmed in the installed SDK's `SwiftUI.swiftinterface` line 19968), and `AXChartDescriptor.ContentDirection` ships `.radialClockwise` — so the hand-drawn radar web can be given the *real* VoiceOver chart rotor, Describe Chart and Audio Graph, without becoming a Swift Chart. The second is that Swift Charts' free accessibility tree is actively harmful here rather than merely absent: `SubstanceShading.marks` puts unlabelled `RectangleMark`s on *every* chart in the app by design, and those become unlabelled elements a VoiceOver user must swipe through between data points. On Dynamic Type the app is unarmoured — **zero `@ScaledMetric`, zero `dynamicTypeSize`, zero `ViewThatFits`, 144 `fixedSize()` and 42 literal `frame(height:)`** — and I derived, rather than guessed, what that costs: at AX5 the radar's widest axis label is **213.1 pt wide against a plotted web only 150 pt across**, so the label crosses the centre of its own chart and runs off the screen edge.

---

## 1. What is actually there — measured, 2026-08-07

Counted from `/Users/jason.salway/health-insights-ios` at `a6c1d37`.

| Measure | Value |
|---|---|
| Swift files (`HealthInsights/` + `InsightKit/Sources/`) | 288 |
| Files containing any `.accessibility*` modifier | 22 (7.6%) |
| `.accessibility*` call sites (2 more in comments, excluded) | 52 |
| — `.accessibilityLabel(` | 27 |
| — `.accessibilityElement(` | 15 |
| — `.accessibilityHidden(` | 7 |
| — `.accessibilityHint(` | 2 |
| — `.accessibilityAddTraits(` | 2 |
| — `.accessibilityValue(` | **1** |
| `AXChartDescriptor` / `accessibilityChartDescriptor` / audio-graph code | **0** |
| `@ScaledMetric` | **0** |
| `.dynamicTypeSize(...)` | **0** |
| `ViewThatFits` | **0** |
| `@Environment(\.accessibilityReduceMotion)` | 2 (`LaunchScreen`, `DataTabView`) |
| `accessibilityReduceTransparency` / `DifferentiateWithoutColor` / `legibilityWeight` | **0** |
| `.fixedSize(` | 144 |
| `frame(height: <literal>)` | 42 |
| `minimumScaleFactor` | 2 |
| `.symbol(` on chart marks (shape as well as hue) | 1 |
| UI-test target / `XCUIApplication` | **none** |

### The chart files, individually

Every file in `HealthInsights/DesignSystem/*Chart*.swift`:

```
0  AgeHistoryChart          0  MedicationResponseChart   0  ScoreHistoryChart
0  BloodPressureChart       0  MetricOverlayChart        1  ScrollableMetricChart *
0  BodyCompositionTrendChart 0 MultiSourceChart          0  SleepOnsetChart
0  DerivedSeriesChart       0  NightSleepChart           0  SleepOnsetStripChart
0  EnergyCurveChart         0  ScoreComparisonChart      0  SleepStageAverageChart
0  FitnessProjectionChart   0  MedicationCurveChart      0  SubstanceLoadChart
0  BodyMeshView             2  ScoreDial
```

\* `ScrollableMetricChart`'s single modifier is on the *empty-state jump button* (line 222, "Jump to the nearest earlier readings"). **The `Chart { }` itself carries nothing.**

### The good news, and why it matters for scope

**20 of the app's chart-bearing views wrap `ScrollableMetricChart`.** That is one file. `SubstanceShading.marks` and `ScrubIndicator.at` are already drawn *inside* the wrapper rather than by callers — the file's own doc comment says this is "what makes 'on every chart' a property of the code instead of a thing each author has to remember". The same argument applies exactly to accessibility: **a descriptor plumbed into `ScrollableMetricChart` reaches twenty charts in one edit.** Only five raw `Chart {` bodies exist outside it (`FitnessProjectionChart`, `EnergyCurveChart`, `SleepStageAverageChart`, `NightSleepChart`, plus the wrapper's own).

### Correcting the brief

The radar and balance web are **not** silent. `SymptomRadarWebCard.speech(for:)` (line ~221) already produces, e.g.:

> "Heart rate variability rMSSD: leaning hard, 38 ms against 52 ms usual"

and `ScoreBalanceWeb` labels each vertex and gives it `.isButton` plus a real 44×44 hit target ("A 9pt dot is not a tap target; 44 is." — `ScoreBalanceWeb.swift:335`). By the Lundgard/Satyanarayan model below these are **Level 2** descriptions, which is exactly the level blind readers rate more useful than sighted ones. This work should be treated as the template, not as a gap.

The real gaps are: **the charts**, **the mesh**, **the chart-level summary sentence**, and **Dynamic Type everywhere**.

---

## 2. Swift Charts: what is free, what is not, and what is actively wrong

All availability below read from the installed SDK (`iPhoneOS26.2.sdk`), not from memory. Deployment target is **iOS 18.0** (`project.pbxproj:162`), so everything here is available unconditionally.

### 2.1 What Swift Charts gives you for nothing

Swift Charts builds an accessibility element per data mark and wires up the three VoiceOver chart affordances — **Describe Chart**, **Audio Graph**, and **Chart Details** — from the plottable values themselves ([Apple, WWDC21 session 10122, "Bring accessibility to charts in your app"](https://developer.apple.com/videos/play/wwdc2021/10122/); [Majid Jabrayilov, "Mastering charts in SwiftUI: Accessibility", 2023](https://swiftwithmajid.com/2023/02/28/mastering-charts-in-swiftui-accessibility/)). The label strings come from the `PlottableValue` keys — i.e. from `.value("From", …)`, `.value("Selected", …)` and so on, which in this repo were written as *code documentation*, never as speech.

**This is the trap.** The free tree is generated from strings nobody chose for a listener.

### 2.2 The per-mark API (confirmed signatures)

On `ChartContent`, `@available(iOS 16.0+)`:

```swift
func accessibilityLabel(_ label: Text)          -> some ChartContent
func accessibilityValue(_ valueDescription: Text) -> some ChartContent
func accessibilityHidden(_ hidden: Bool)        -> some ChartContent
func accessibilityIdentifier(_ identifier: String) -> some ChartContent
```

On `VectorizedChartContent` (i.e. `ForEach`-backed marks), `@available(iOS 18.0+)` — **key-path overloads, which is what this app should use**, since every series here is a `ForEach` over a model type:

```swift
func accessibilityLabel(_ label: KeyPath<Self.DataElement, Text>) -> some VectorizedChartContent<Self.DataElement>
func accessibilityValue(_ value: KeyPath<Self.DataElement, some StringProtocol>) -> some VectorizedChartContent<Self.DataElement>
func accessibilityHidden(_ hidden: KeyPath<Self.DataElement, Bool>) -> some VectorizedChartContent<Self.DataElement>
```

The `accessibilityHidden(KeyPath<…, Bool>)` overload is precisely the tool for **dash-means-inferred**: a projected or interpolated point can be hidden from the swipe tree, or better, labelled differently, from the same key path the dash pattern already reads.

### 2.3 The chart-level descriptor (confirmed signatures)

`SwiftUI.swiftinterface:19968`, `@available(iOS 15.0+)`, **on `View`**:

```swift
extension View {
  func accessibilityChartDescriptor<R>(_ representable: R) -> some View
    where R: AXChartDescriptorRepresentable
}

public protocol AXChartDescriptorRepresentable {
  func makeChartDescriptor() -> AXChartDescriptor
  func updateChartDescriptor(_ descriptor: AXChartDescriptor)
}
```

From `Accessibility.framework/Headers/AXAudiograph.h` (all `iOS 15.0+`):

```objc
AXChartDescriptor(title:summary:xAxis:yAxis:additionalAxes:series:)
  .contentDirection : AXChartDescriptorContentDirection
  .contentFrame     : CGRect

AXNumericDataAxisDescriptor(title:lowerBound:upperBound:gridlinePositions:valueDescriptionProvider:)
  .scaleType : .linear | .log10 | .ln
  .valueDescriptionProvider : (Double) -> String

AXCategoricalDataAxisDescriptor(title:categoryOrder:)
AXDataSeriesDescriptor(name:isContinuous:dataPoints:)
AXDataPoint(x:y:additionalValues:label:)

AXChartDescriptorContentDirection:
  .leftToRight .rightToLeft .topToBottom .bottomToTop
  .radialClockwise .radialCounterClockwise      // ← see §5
```

**Three things this app needs from that surface and does not have:**

1. **`valueDescriptionProvider`** is the only place the audio graph and the axis read-out learn units. Without it VoiceOver reads bare doubles: `"52.0"`, not `"52 milliseconds"`. The app already owns `MetricValueFormatter.string(_:_:)` — the provider is a one-line adapter.
2. **`scaleType`.** `ScrollableMetricChart` has a `logarithmic: Bool` (line 27) and applies it via `MetricYScale`. Nothing tells the accessibility layer. **An audio graph over a log-scaled series with `scaleType == .linear` sonifies a curve that is not on screen** — pitch would track the raw value while the visible line tracks its logarithm. That is "modelled dressed as measured" in the audio channel, and it is a silent defect: the chart looks right, the sound is wrong. Wire `scaleType = logarithmic ? .log10 : .linear`.
3. **`summary`.** This is where the honest-uncertainty sentence belongs (§3).

### 2.4 The defect the free tree creates in *this* app

`SubstanceShading.marks(_:in:)` emits, on **every chart in the app**, a `ForEach` of:

```swift
RectangleMark(xStart: .value("From", …), xEnd: .value("To", …))
```

Those are chart content. Swift Charts will generate accessibility elements for them, labelled from the keys `"From"` and `"To"`. A VoiceOver user swiping a heart-rate chart therefore hits an unlabelled grey rectangle announced as a `From`/`To` pair between the readings they were trying to read — and there is no way to tell from speech that it is the substance shading, whose whole documented purpose is that it "marks when, not what it did".

`ScrubIndicator.at(_:)` has the same problem with its `RuleMark(x: .value("Selected", instant))`.

**Prescription:** both must carry `.accessibilityHidden(true)` (iOS 16 `ChartContent` overload), and their content must be re-stated *once* — the shading in the chart `summary` ("three logged-substance windows in view"), the scrub position as the chart's `.accessibilityValue`. This is a two-line change in two files that fixes twenty-plus charts, and it is the single change with the best ratio in this whole document.

### 2.5 Scrolling and selection — unverified, and only the device can answer

`ScrollableMetricChart` uses `.chartScrollableAxes(.horizontal)`, `.chartXVisibleDomain(length:)`, `.chartScrollPosition(x:)` and `.chartXSelection(value:)`. **I could not establish from documentation whether Swift Charts' generated accessibility tree covers the whole scroll domain or only the visible window, nor whether `chartXSelection` is reachable without sighted dragging.** No published answer exists that I could find, and this session's web-search budget is exhausted. This is a `use-the-phone` question, and the app's own culture already says so (`add-chart`: "the three behaviours only the device can falsify").

What is certain from the SDK is the tool for the operable half:

```swift
@available(iOS 14.0+)
func accessibilityScrollAction(_ handler: @escaping (Edge) -> Void) -> …
```

A three-finger swipe on a VoiceOver-focused element fires this. `ScrollableMetricChart` already owns `scrollX`, `window`, `nearestPopulatedStart(before:)` and `visibleRange` — panning by one window on `.leading`/`.trailing` and announcing the new range is a ten-line addition and makes the pan gesture, which is currently sighted-only, reachable.

---

## 3. What a good spoken description of a trend chart contains

### 3.1 The evidence

**Lundgard, A. & Satyanarayan, A. (2022). "Accessible Visualization via Natural Language Descriptions: A Four-Level Model of Semantic Content." *IEEE TVCG* 28(1) (Proc. InfoVis 2021).** Grounded-theory analysis of **2,147 sentences**; mixed-methods evaluation with **30 blind and 90 sighted readers**. Four levels:

| Level | Content | Example for this app |
|---|---|---|
| **L1** | Construction properties — marks, encodings, axes | "Line chart. Resting heart rate in beats per minute, over 90 days." |
| **L2** | Statistics and relations — extrema, means, correlations | "Range 48 to 71. Currently 54, down 4 from the 90-day average." |
| **L3** | Perceptual/cognitive — trends, patterns, clusters | "Falling steadily since mid-June, with one three-day spike in July." |
| **L4** | Domain insight — external context, explanation | "That spike overlaps the illness window." |

**The finding that should drive this app's design:** both groups rated **L3 most useful**; **blind readers rated L2 significantly more useful than sighted readers did, and L4 much less useful.** In other words the L4 sentence — the interpretive one this app is full of — is the one blind readers want *least*, and L2, the numbers, is the one they want more of than sighted readers do. This app's chart captions today are almost entirely L4.

**Sharif, A., Chintalapati, S. S., Wobbrock, J. O. & Reinecke, K. (2021). "Understanding Screen-Reader Users' Experiences with Online Data Visualizations." *ASSETS '21*.** Qualitative study with 9 screen-reader users; quantitative study with **36 screen-reader and 36 non-screen-reader users**. Screen-reader users extracted information **61.48% less accurately** and spent **210.96% more time** on the same charts.

**Sharif, A., Wang, O. H., Muongchan, A. T., Reinecke, K. & Wobbrock, J. O. (2022). "VoxLens: Making Online Data Visualizations Accessible with an Interactive JavaScript Plug-In." *CHI '22*.** Adding summary + sonification + query interaction produced **+122% accuracy and −36% interaction time** versus the no-tool baseline from the 2021 study. **This is the effect size that justifies the work**: it is not a courtesy, it roughly doubles the information a screen-reader user extracts.

**Zong, J., Lee, C., Lundgard, A., Jang, J., Hajas, D. & Satyanarayan, A. (2022). "Rich Screen Reader Experiences for Accessible Data Visualization." *Computer Graphics Forum* (Proc. EuroVis 2022).** Mixed-methods study with **13 blind and low-vision readers**. Names three design dimensions — **structure** (how entities are organised for traversal), **navigation** (structural, spatial and targeted stepping), **description** (semantic content, composition, verbosity). The paper reports qualitative findings; **no effect size is reported and I will not invent one.**

The three dimensions map cleanly onto Apple's stack, which is why they are worth adopting as this repo's vocabulary: *structure* = the `AXChartDescriptor` series/axes, *navigation* = `accessibilityScrollAction` + the chart rotor + per-mark elements, *description* = `summary` + per-mark `accessibilityLabel`/`accessibilityValue`.

### 3.2 The prescribed sentence template for this app

Ordered by the evidence above (L1 minimal, L2 and L3 full, L4 last and separable), and constrained by this repo's rules:

```
<what it is, once>. <units>.                                   ← L1, ~8 words
<n> readings from <first date> to <last date>.                 ← L1/L2, the count is the honesty
Range <min> to <max>. Latest <value> on <date>.                ← L2
<trend clause>.                                                ← L3
<uncertainty clause — MANDATORY when anything is modelled>.    ← the app's own rule
<caveat clause — gaps, inference, vendor relay>.               ← the app's own rule
```

Worked example, `ScoreHistoryChart`:

> "Sleep score over time, 0 to 100. 249 nights from 7 November 2025 to 6 August 2026. Range 41 to 92. Latest 78, on 6 August. Rising over the last three weeks; before that flat since April. 31 of these nights are modelled from partial data and are drawn dashed. Shaded periods mark hours after something you logged — when, not what it did."

Rules that fall out of the app's existing standards:

- **Never speak a trend the chart does not draw.** The L3 clause must be computed from the same series the marks read, not re-derived — otherwise the spoken chart and the drawn chart can disagree, and only one user will ever notice.
- **The count is not optional.** "249 nights" is what turns "thin data is a reason to print the error bar" into speech. A chart of four points must say *four*.
- **Dash-means-inferred must survive into speech.** A dashed segment is invisible to VoiceOver unless the value string says so. Prescription: modelled points get `.accessibilityValue("<value>, modelled")`; measured points get the bare value. Same key path that drives the dash.
- **A vendor composite is relayed, never blended — in speech too.** Oura's stress field, present on 90 of the last 90 days, must be spoken as *"Oura's stress reading, their formula, shown alongside"* and must never appear inside a sentence describing our own score.
- **`SubstanceShading.caption` already exists as a string constant.** Reuse it verbatim in the `summary`; do not write a second wording that can drift from the printed one.

### 3.3 Verbosity — where to put the long half

`AXCustomContent` (`Accessibility.framework`, iOS 14+) exists exactly for this and the app uses it zero times:

```swift
func accessibilityCustomContent(_ label: Text, _ value: Text,
                                importance: AXCustomContent.Importance = .default) -> …
```

`.default` content is spoken **on demand** via the More Content rotor; `.high` is spoken immediately. This is the mechanism that lets a card be terse by default and complete on request — the alternative is a 40-word `accessibilityLabel` the user must sit through on every swipe. Prescription: the L1/L2 core goes in the label, the caveat/provenance/uncertainty clauses go in `.default` custom content. That is a better fit for this app than for most, because this app's caveats are long by policy.

---

## 4. Dynamic Type — measured, not cited

### 4.1 The table

Derived by compiling against `iPhoneSimulator SDK` and running under `simctl spawn` on a booted iPhone 16e / iOS 26.3, calling `UIFont.preferredFont(forTextStyle:compatibleWith:)` across all twelve `UIContentSizeCategory` values. Point sizes, rounded:

| Style | XS | S | M | **L (default)** | XL | XXL | XXXL | AX1 | AX2 | AX3 | AX4 | **AX5** | **AX5 ÷ L** |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| largeTitle | 31 | 32 | 33 | **34** | 36 | 38 | 40 | 44 | 48 | 52 | 56 | **60** | 1.76× |
| title1 | 25 | 26 | 27 | **28** | 30 | 32 | 34 | 38 | 43 | 48 | 53 | **58** | 2.07× |
| title2 | 19 | 20 | 21 | **22** | 24 | 26 | 28 | 34 | 39 | 44 | 50 | **56** | 2.55× |
| title3 | 17 | 18 | 19 | **20** | 22 | 24 | 26 | 31 | 37 | 43 | 49 | **55** | 2.75× |
| headline | 14 | 15 | 16 | **17** | 19 | 21 | 23 | 28 | 33 | 40 | 47 | **53** | 3.12× |
| body | 14 | 15 | 16 | **17** | 19 | 21 | 23 | 28 | 33 | 40 | 47 | **53** | 3.12× |
| callout | 13 | 14 | 15 | **16** | 18 | 20 | 22 | 26 | 32 | 38 | 44 | **51** | 3.19× |
| subheadline | 12 | 13 | 14 | **15** | 17 | 19 | 21 | 25 | 30 | 36 | 42 | **49** | 3.27× |
| footnote | 12 | 12 | 12 | **13** | 15 | 17 | 19 | 23 | 27 | 33 | 38 | **44** | 3.38× |
| caption1 | 11 | 11 | 11 | **12** | 14 | 16 | 18 | 22 | 26 | 32 | 37 | **43** | 3.58× |
| caption2 | 11 | 11 | 11 | **11** | 13 | 15 | 17 | 20 | 24 | 29 | 34 | **40** | **3.64×** |

### 4.2 Two derived consequences, both bad for this app specifically

**(a) The smallest text grows the most.** `caption2` scales **3.64×**; `largeTitle` scales **1.76×**. The app's dense material — `InsightDetailView` alone uses `.caption`/`.caption2` **114 times**, `SubstanceEpisodesSection` 25, `DataTabView` 24, `MedicationSection` 23 — is precisely the material that more than triples. A card whose title grows 1.76× while its legend, caveat and axis labels grow 3.64× does not scale; it inverts.

**(b) Visual hierarchy halves.** At default the largeTitle:caption2 ratio is 34/11 = **3.09×**. At AX5 it is 60/40 = **1.50×**. Everything converges toward the same apparent size, so any layout that relies on size alone to say "this is the headline and that is the caveat" stops saying it at exactly the setting where the user most needs the structure. That is an argument for `.accessibilityAddTraits(.isHeader)` and real semantic grouping, not for capping the type size.

### 4.3 What the code does about it

Nothing. **`@ScaledMetric`: 0. `.dynamicTypeSize(...)`: 0. `ViewThatFits`: 0.** Against **144 `.fixedSize()`**, **42 literal `frame(height:)`**, and only **2 `minimumScaleFactor`** in the whole app.

`.fixedSize()` is the dangerous one and its use here is deliberate and wrong for this purpose: it tells SwiftUI *"give this text its ideal size and never compress it"*. At AX5 the text does not wrap, does not truncate and does not shrink — **it draws outside its parent**, silently, with no clipping warning and no test failure. Every one of the 144 sites is a candidate overflow. (The `.fixedSize(horizontal: false, vertical: true)` variant — which *only* allows vertical growth — is correct and should be left alone; the bare `.fixedSize()` calls are the ones to audit. `SymptomRadarWebCard` line 189 uses bare `.fixedSize()` on its axis labels; line 88 uses the safe two-argument form on its caption.)

**A note on how to justify this work honestly.** Published prevalence figures for large-text use are about populations. This app has one known reader. Inflating a population statistic into a reason would be exactly the move this repo forbids. The honest reasons are: (i) Dynamic Type is *situational* — sunlight, post-exercise, in bed, without glasses — and a health app is used in all four; (ii) the failure mode is silent and permanent, so it costs nothing now and cannot be discovered later without looking; (iii) if the app is ever shown to a clinician or a family member, the setting is theirs, not the reader's.

---

## 5. ⚠️ The custom-drawn radar web

### 5.1 The derived arithmetic, and why it is decisive

From `SymptomRadarWebCard.swift`:

- `web.frame(height: 250).frame(maxWidth: .infinity)` (line 84–85)
- `let side = min(geo.size.width, geo.size.height)` (line 97) → on any iPhone in portrait, **`side = 250`**
- `plotRadiusRatio = 0.30` (line 42) → `radius = 75 pt`, **plotted web diameter = 150 pt**
- `labelRadiusRatio = 1.32` (line 44) → label centres sit **99 pt** from the middle
- labels are `.font(.caption2.weight(.medium))` and `.fixedSize()` (lines 188–189)
- 7 axes → 51.4° apart; adjacent label centres are `2 × 99 × sin(25.7°)` = **85.9 pt** apart

Measured string widths for the file's own `shortName` outputs, rendered in `.systemFont(ofSize:weight:.medium)` under `simctl spawn`:

| Label | at default (11 pt) | at AX5 (40 pt) |
|---|--:|--:|
| RHR | 23.2 | 78.7 |
| SpO₂ | 26.6 | 89.5 |
| Resp rate | 51.1 | 165.9 |
| Temp dev | 51.9 | 169.4 |
| Skin temp | 53.6 | 175.6 |
| HRV SDNN | 58.4 | 198.0 |
| **HRV rMSSD** | **63.2** | **213.1** |

Three failures follow, none of which require a device to establish:

1. **The label is wider than the chart.** 213.1 pt against a 150 pt web. The widest axis label is **1.42× the diameter of the entire plotted figure.**
2. **The label crosses its own centre.** Half-width 106.6 pt, centre at 99 pt from the middle → its inner edge lands at 99 − 106.6 = **−7.6 pt**, i.e. past the centre of the web, over the opposite half of the chart.
3. **It leaves the screen.** Outer edge at 99 + 106.6 = **205.6 pt** from centre. Half of a 390 pt iPhone screen is 195 pt — so it overflows the *screen* by ~11 pt **before counting any card or section padding**, and `.fixedSize()` guarantees it will not wrap or truncate to avoid it. Adjacent labels, whose centres are 85.9 pt apart, overlap each other by ~100 pt.

The `250` and the `0.30` are literals that do not scale with Dynamic Type. The labels do. That is the whole mechanism, and it applies identically to `ScoreBalanceWeb` (same `plotRadiusRatio`/`labelRadiusRatio` pattern, same `.caption2` + `.fixedSize()` labels, plus a value and an arrow glyph in the same `HStack`, so its labels are *wider* still).

### 5.2 The finding that changes the approach

**There is no published guidance specific to making radar/spider charts non-visually accessible.** I looked; the accessibility-visualisation literature (Zong 2022, Lundgard 2022, Sharif 2021/2022) is about Cartesian charts, and the radar-chart literature is about whether radar charts are a good idea at all, not about screen readers. *No published curve or convention exists for this.* Saying so is the honest answer, and it means the design decision has to be argued from the platform rather than borrowed.

The platform has the answer, and it is better than expected:

- **`accessibilityChartDescriptor(_:)` is on `View`.** It does not require a `Chart`. It can be attached to the `GeometryReader` that draws the web.
- **`AXChartDescriptorContentDirection` includes `.radialClockwise` and `.radialCounterClockwise`.** Apple built polar content direction into the descriptor. This is the intended mechanism.

So the radar web can be given a *real* chart descriptor — Describe Chart, Chart Details and an Audio Graph that sweeps the axes clockwise — while remaining hand-drawn `Path`s. Shape:

```
xAxis  : AXCategoricalDataAxisDescriptor(
           title: "Signal",
           categoryOrder: <the 7 metric displayNames, in draw order>)
yAxis  : AXNumericDataAxisDescriptor(
           title: "Departure from your usual",
           lowerBound: 0, upperBound: 1,           // the ring fractions
           gridlinePositions: [0.5, 1.0],          // = Self.ringFractions
           valueDescriptionProvider: { … "half a ring out" / "on the outer ring" … })
series : one AXDataSeriesDescriptor(isContinuous: false),
         one AXDataPoint per axis, .label carrying the existing speech(for:) string
contentDirection = .radialClockwise
summary = "<n> of 7 signals leaning. <m> without enough data to judge."
```

Two honesty constraints that are not optional here:

- **An axis with `signal == nil` must not be given a `y` value of 0.** `AXDataPoint(x:y:)` takes an optional `y` — pass `nil`, keep the category, and let the label say "not enough data". A zero would be sonified as a low pitch and read as a *measurement of nothing wrong*, which is the exact inversion the greyed spoke exists to prevent.
- **The discounted twin must stay discounted in the audio graph.** The two HRV measures and the two temperatures "each count once" (the card's own caption). An audio graph over seven equally-weighted points sonifies four votes where the model counts two. Either mark the discounted points `.accessibilityHidden` in the series and state the pairing in the `summary`, or keep them and have the `summary` say plainly that two pairs are each one vote. Do not let the sound imply a weighting the model does not use.

### 5.3 The other radar defect: 6-pt accessibility elements

`SymptomRadarWebCard.dot(for:signal:)` draws `Circle().frame(width: 6…9, height: 6…9)` and the *dot itself* carries `.accessibilityLabel(speech(for: axis))` (line 144). The accessibility frame follows the view frame, so VoiceOver's element for a non-leaning signal is **6×6 pt**. That is below Apple's HIG 44×44 pt minimum and below WCAG 2.2 SC 2.5.8 Target Size (Minimum, AA) at 24×24 CSS px. Direct-touch exploration will skip it; Voice Control's "tap …" will struggle to hit it. `ScoreBalanceWeb` already solved this on line 335 with an inner `.frame(width: 44, height: 44).contentShape(Circle())` — **copy that, verbatim, into the radar.** The radar's dots also lack `.accessibilityAddTraits(.isButton)`, correctly, since they are not tappable; but they should carry `.isStaticText`-equivalent semantics via being real elements rather than decoration.

---

## 6. ⚠️ The 3D body mesh — the real null

`BodyMeshView` is `struct BodyMeshView: UIViewRepresentable` wrapping an `SCNView`. It contains **zero accessibility code**. An `SCNView` publishes no accessibility elements of its own, so VoiceOver sees an empty region. `allowsCameraControl = true` with `.orbitTurntable` means the entire interaction — the spin that the file's own doc comment argues is *load-bearing*, because "a girth is a ring around the body, and a front-on projection shows one diameter of it" — is available only to a sighted user with a working pan gesture.

This is worse than the radar: the radar is a described chart with a layout bug; the mesh is genuinely nothing.

**The good news is the data is already there and already tested on Linux.** `InsightKit/Sources/InsightKit/Body/BodyMesh.swift` publishes exactly what a spoken description needs:

```swift
public struct BodyMesh {
  public let rings: [Ring]                  // .provenance: RingProvenance, .circumferenceMetres, .station
  public let labelAnchors: [LabelAnchor]    // .station, .valueCentimetres, .isMeasured
  public let measuredTriangles:  [UInt32]   // disjoint from…
  public let estimatedTriangles: [UInt32]
  public let isWhollyEstimated: Bool
}
```

Prescription, in order:

1. **`.accessibilityElement(children: .ignore)`** on the `BodyMeshView` — an `SCNView` has no children worth traversing, and `.contain` would produce an empty container.
2. **`.accessibilityLabel`** built from `isWhollyEstimated` and the measured/estimated split. `isWhollyEstimated == true` **must** be spoken — this is the "modelled is never dressed as measured" rule, and the mesh is the one view in the app where an entirely estimated figure is visually indistinguishable at a glance from a measured one except by hue. The legend says it visually (`BodyMeshLegend`); nothing says it aloud.
3. **One `.accessibilityCustomContent` per `LabelAnchor`**, `importance: .default`, so the reader can rotor through stations on demand:
   `accessibilityCustomContent(Text(anchor.station.displayName), Text("\(anchor.valueCentimetres, .0f) centimetres\(anchor.isMeasured ? "" : ", estimated")"))`
   With ~6–8 anchors this is the right verbosity: nothing in the default utterance, everything on request.
4. **`.accessibilityAdjustableAction { direction in … }`** to rotate the turntable in fixed steps — 45° per swipe-up/down, announcing the new facing ("facing left side"). This makes the *argument for 3D over the outline* — that a girth is a circumference, not a width — actually available non-visually. It is the only way to do so, since `SCNView`'s camera controller cannot be driven by VoiceOver gestures.
5. **`.accessibilityChartDescriptor`** with the stations as an `AXCategoricalDataAxisDescriptor` and circumference in cm as the numeric axis. This gives the mesh an Audio Graph — a pitch sweep head-to-foot over the girth profile — which is a genuinely good non-visual rendering of a body shape and costs one struct.
6. **`BodyMeshLegend`** must be `.accessibilityElement(children: .combine)` with a single label; as written its swatches are two unlabelled `Circle()`s and two `Text`s.
7. **`BodySilhouetteView.speech(_:isProjected:)` is the pattern to extend** — it is already correct in kind ("Projected body shape. Waist 92 cm.") and merely thin. It speaks one station out of the ~8 the model holds, and it does not say what "projected" is projected *from*.

---

## 7. The checklist

Ordered by (charts covered) ÷ (files touched). Items 1–4 cover twenty-plus charts in four files.

### Tier 1 — one file each, whole-app effect

- [ ] **`SubstanceShading.marks`** — add `.accessibilityHidden(true)` to the `RectangleMark`. Removes an unlabelled element from *every* chart in the app.
- [ ] **`ScrubIndicator.at`** — add `.accessibilityHidden(true)` to both `RuleMark` overloads.
- [ ] **`ScrollableMetricChart`** — accept an `AXChartDescriptorRepresentable` (or a small `ChartSpeech` value type) from callers, apply `.accessibilityChartDescriptor(…)` on the `Chart`. Set `scaleType = logarithmic ? .log10 : .linear`. **This is the item that matters most.**
- [ ] **`ScrollableMetricChart`** — add `.accessibilityScrollAction { edge in … }` that pans by one `window` using the existing `nearestPopulatedStart(before:)`, and announces the new visible range.
- [ ] **`ScrollableMetricChart`** — `.accessibilityValue` reflecting `selection` when scrubbing, so the scrub read-out is spoken.

### Tier 2 — per chart, 18 + 5 sites

- [ ] Each chart supplies a `summary` following the §3.2 template: kind, units, **count**, span, range, latest, trend, uncertainty, caveat.
- [ ] Each series supplies `valueDescriptionProvider` wired to `MetricValueFormatter.string(_:_:)`. No bare doubles.
- [ ] Every mark drawn from a `ForEach` gets `.accessibilityLabel(\.…)` and `.accessibilityValue(\.…)` via the iOS 18 key-path overloads.
- [ ] **Dashed/inferred points say so in their value string.** Same key path that selects the dash.
- [ ] Multi-series charts (`MultiSourceChart`, `MetricOverlayChart`, `BloodPressureChart`) supply one `AXDataSeriesDescriptor` per series with a real `name` — the audio graph plays series in turn and unnamed series are indistinguishable.
- [ ] Relayed vendor composites are named as such in the series name, never merged into ours.
- [ ] The 5 raw `Chart {` bodies outside the wrapper (`FitnessProjectionChart`, `EnergyCurveChart`, `SleepStageAverageChart`, `NightSleepChart`) get the same treatment individually.

### Tier 3 — the custom visualisations

- [ ] **Radar dots** get the 44×44 `contentShape` treatment copied from `ScoreBalanceWeb.swift:335`.
- [ ] **Radar** gets `.accessibilityChartDescriptor` with `contentDirection = .radialClockwise`, categorical x, numeric y bounded 0…1, gridlines at `ringFractions`. `signal == nil` → `AXDataPoint(x:y: nil)`.
- [ ] **`ScoreBalanceWeb`** gets the same descriptor.
- [ ] **Both webs**: `.accessibilityLabel` on the container is a title, not a description — add a `summary` in the descriptor carrying the counts ("3 of 7 leaning, 1 without enough data").
- [ ] **`BodyMeshView`**: items 1–7 of §6.
- [ ] **`BodySilhouetteView.speech`**: extend to all available stations via `accessibilityCustomContent`, and say what a projection is projected from.

### Tier 4 — Dynamic Type

- [ ] **Audit the 144 bare `.fixedSize()`** — the two-argument `(horizontal: false, vertical: true)` form is fine and should be left; bare `.fixedSize()` on any text inside a fixed-width or fixed-height container is a defect.
- [ ] **Radar + balance web**: replace `.frame(height: 250)` with `@ScaledMetric(relativeTo: .caption2) private var webSide: CGFloat = 250`, so the figure grows with the labels rather than being overrun by them. Alternatively, and more cheaply, switch to a **vertical list layout above AX1** via `@Environment(\.dynamicTypeSize) … if size.isAccessibilitySize` — a radar with 213 pt labels is not a radar, and a labelled list of the same seven readings is the honest fallback. **Do not** cap with `.dynamicTypeSize(...DynamicTypeSize.accessibility1)`; capping is refusing the user's setting.
- [ ] **Every `frame(height: <literal>)` that contains text** (42 sites) → `@ScaledMetric`.
- [ ] Add `.accessibilityAddTraits(.isHeader)` to card and section titles — at AX5 the size hierarchy compresses from 3.09× to 1.50× and stops carrying structure on its own.
- [ ] `.symbol(…)` is used **once** in the whole app. Any chart distinguishing series by hue alone fails for colour vision deficiency and for `accessibilityDifferentiateWithoutColor` (currently read nowhere). Pair every hue with a symbol or a dash pattern — which `add-chart`'s hatch-never-blend rule already argues for on different grounds.

### Tier 5 — make it enforceable, not remembered

This repo's stated preference is "the fix that retires a *category* over the one that retires an instance", and its mechanism for that is `verify.sh` plus an exhaustive switch. Three candidates:

- [ ] **`verify.sh`: no `Chart {` without a descriptor.** Mirror the existing substance-shading lint exactly: a raw `Chart {` must either be inside `ScrollableMetricChart`, carry `.accessibilityChartDescriptor`, or carry `// a11y: exempt — <why>`. This is the same shape as the rule that already works, so it is cheap to add and cheap to read.
- [ ] **`verify.sh`: no bare `.fixedSize()` inside a file that also contains a literal `frame(width:` or `frame(height:`.** Noisier; run it as a warning first and count the hits before making it fatal.
- [ ] **A UI test target — the app has none.** An `XCUITest` that walks the tab bar and asserts every `.otherElement` matching the chart identifiers has a non-empty `label` would catch regressions that neither `swift test` nor CI can see, and `XCUIElement.debugDescription` dumps the whole accessibility tree for inspection. This is the only mechanised check that can falsify §2.5 (whether the scrollable chart's tree covers the full domain), and it would run on the Mac gate alongside the existing `xcodebuild`.

---

## 8. What I could not establish

Stated plainly, per the brief:

1. **Whether Swift Charts' generated accessibility tree covers the whole `chartXScale` domain or only `chartXVisibleDomain`.** No documentation found. Device-verifiable via VoiceOver + an accessibility-tree dump; belongs in `use-the-phone`.
2. **Whether `chartXSelection` is operable without a sighted drag.** Same status.
3. **How Swift Charts' automatic Audio Graph maps pitch to value, and whether it honours `chartYScale`.** Undocumented. Consequence: I cannot verify from documentation that setting `scaleType = .log10` on the descriptor actually fixes the log-scale sonification, only that it is the field designed for it. Verify by listening on the device to a chart with `logarithmic: true`.
4. **Published guidance for non-visual radar/spider charts.** *None exists that I could find.* The `.radialClockwise` descriptor is a platform affordance, not a validated design; if it is adopted, it is on Apple's authority and this repo's reasoning, and the doc should say so rather than imply an evidence base.
5. **Any effect size for Zong et al. 2022.** The paper reports qualitative findings from 13 BLV readers; I did not find a quantitative result and did not invent one.
6. **Any prevalence figure for Dynamic Type usage.** Not sought, because a population statistic would not honestly justify work on a single-reader app (see §4.3).

---

## Sources

- Lundgard, A. & Satyanarayan, A. (2022). *Accessible Visualization via Natural Language Descriptions: A Four-Level Model of Semantic Content.* IEEE TVCG 28(1), Proc. InfoVis. 2,147 sentences; 30 blind + 90 sighted readers. — [arxiv.org/abs/2110.04406](https://arxiv.org/abs/2110.04406) · [vis.csail.mit.edu/pubs/vis-text-model/](https://vis.csail.mit.edu/pubs/vis-text-model/)
- Sharif, A., Chintalapati, S. S., Wobbrock, J. O. & Reinecke, K. (2021). *Understanding Screen-Reader Users' Experiences with Online Data Visualizations.* ASSETS '21. 9 qualitative; 36 + 36 quantitative. −61.48% accuracy, +210.96% time. — [dl.acm.org/doi/10.1145/3441852.3471202](https://dl.acm.org/doi/fullHtml/10.1145/3441852.3471202) · [PDF](https://athersharif.me/documents/assets-2021-understanding-sru-experiences-online-data-viz.pdf)
- Sharif, A., Wang, O. H., Muongchan, A. T., Reinecke, K. & Wobbrock, J. O. (2022). *VoxLens: Making Online Data Visualizations Accessible with an Interactive JavaScript Plug-In.* CHI '22. +122% accuracy, −36% interaction time vs. the 2021 baseline. — [dl.acm.org/doi/10.1145/3491102.3517431](https://dl.acm.org/doi/fullHtml/10.1145/3491102.3517431) · [PDF](https://faculty.washington.edu/wobbrock/pubs/chi-22.04.pdf)
- Zong, J., Lee, C., Lundgard, A., Jang, J., Hajas, D. & Satyanarayan, A. (2022). *Rich Screen Reader Experiences for Accessible Data Visualization.* Computer Graphics Forum (Proc. EuroVis). 13 BLV readers; structure / navigation / description. No effect size reported. — [arxiv.org/abs/2205.04917](https://arxiv.org/abs/2205.04917)
- Apple (2021). *Bring accessibility to charts in your app.* WWDC21 session 10122. — [developer.apple.com/videos/play/wwdc2021/10122/](https://developer.apple.com/videos/play/wwdc2021/10122/)
- Apple. `AXChartDescriptorRepresentable`. — [developer.apple.com/documentation/swiftui/axchartdescriptorrepresentable](https://developer.apple.com/documentation/swiftui/axchartdescriptorrepresentable)
- Create with Swift. *Making charts accessible with Swift Charts.* — [createwithswift.com/making-charts-accessible-with-swift-charts/](https://www.createwithswift.com/making-charts-accessible-with-swift-charts/)
- Jabrayilov, M. (2023). *Mastering charts in SwiftUI: Accessibility.* — [swiftwithmajid.com/2023/02/28/mastering-charts-in-swiftui-accessibility/](https://swiftwithmajid.com/2023/02/28/mastering-charts-in-swiftui-accessibility/)

**Primary sources read directly, not cited from the web** (authoritative, and the reason the API signatures above can be trusted): `iPhoneOS26.2.sdk/System/Library/Frameworks/Accessibility.framework/Headers/AXAudiograph.h` and `AXCustomContent.h`; `Charts.framework/Modules/Charts.swiftmodule/arm64e-apple-ios.swiftinterface`; `SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface` and `SwiftUICore.swiftinterface`.

**Derived, not cited**: the Dynamic Type table (§4.1) and the label-width measurements (§5.1) were produced by compiling a short program against the iOS Simulator SDK and running it under `xcrun simctl spawn booted` on iPhone 16e / iOS 26.3. Both are reproducible; the sources are in `/private/tmp/claude-502/-Users-jason-salway-health-insights-ios/7f9c6881-3877-4d55-80a2-79bcf81103b5/scratchpad/dt.swift` and `w.swift`.