import SwiftUI
import Charts
import InsightKit

/// **"The trend across your nights"** — backlog S13, the trend *surface* for the
/// breathing-disturbance index.
///
/// `BreathingDisturbanceTrend` has existed since B18-1 and already produced the
/// two honest statements available: where the latest night sits among the
/// reader's own, and whether the series is drifting by more than it scatters.
/// What it had nowhere to be *drawn* was the line itself. The section it lived
/// in charted the index with `MultiSourceChart`, which answers a different
/// question — *do my two devices agree* — and has no fitted line on it at all,
/// so the drift sentence sat under a picture that could neither confirm nor
/// contradict it.
///
/// ## ⚠️ What this may never become
///
/// **Nothing here scores the index and nothing here screens for apnoea.** Oura's
/// breathing-disturbance index is a proprietary composite of overnight
/// blood-oxygen dips and the movement that goes with interrupted breaths; the
/// AHI thresholds that exist (5, 15, 30 events an hour) grade a polysomnogram,
/// and no published work maps a ring's index onto them. So this chart carries
/// **no reference band, no colour ramp and no threshold rule** — every one of
/// which would be a scale nobody published, drawn. It has the reader's own
/// middle half of nights and their own fitted line, and that is the whole
/// vocabulary. `BreathingDisturbanceTrend.notAnApnoeaTest` and
/// `.whatWouldAnswerIt` say so in words on the section that contains this one.
///
/// ## ⚠️ The line is the whole-history fit, deliberately not re-fitted per window
///
/// `OvernightNightlyChart` re-fits its mean and band to whatever window is
/// scrolled to, which is right there: nothing in that section quotes a specific
/// line. Here the drift sentence beside the chart names a slope and a scatter
/// from `BreathingDisturbanceTrend.trend`, which is fitted over every night —
/// so a chart drawing a *different* line would put a picture and a sentence on
/// one screen disagreeing about the same quantity. The caption says which it is.
struct BreathingTrendSection: View {
    let trend: BreathingDisturbanceTrend
    let timeframe: Timeframe

    /// Whether the chart draws a fitted line at all. The same flag
    /// `BreathingTrendChart` gates the line on and `driftSentence` gates its
    /// wording on, read once here so the heading, the caveat, the line and the
    /// sentence cannot disagree.
    private var hasLine: Bool { trend.trend?.isMeaningful == true }

    var body: some View {
        NestedInsightSection(
            title: "The trend across your nights",
            trailing: trend.nights.isEmpty ? nil
                : "\(trend.nights.count) \(trend.nights.count == 1 ? "night" : "nights")",
            // ⚠️ **The caveat has to match the picture.** The first version said
            // "the line is a least-squares fit" unconditionally, and on the
            // simulator it sat under a chart with no line on it — a footnote
            // describing something that was not drawn. `.fitted` when a line is
            // there, `.none` when the section is reporting measurements and a
            // band of them and nothing else.
            caveat: hasLine
                ? .computed(.fitted,
                            "The line is a least-squares fit through your own nights "
                            + "and the band is the middle half of them. Both describe "
                            + "your record and neither is a scale: no published work "
                            + "says what a level of this index means, so nothing here "
                            + "scores it or bands it as good or bad.")
                : .computed(.none,
                            "Your own nights and the middle half of them, as recorded. "
                            + "No line and no band of \"normal\": no published work says "
                            + "what a level of this index means, so nothing here scores "
                            + "it or bands it as good or bad.")
        ) {
            // ⚠️ Unconditional heading and caption; only the figures are
            // optional (`add-chart` §9b). A section that vanishes while it is
            // counting cannot say what it is counting to.
            if let drift = trend.driftSentence {
                caption(drift)
            } else if let waiting = trend.coverage?.sentence {
                caption(waiting)
            } else {
                caption("No nights with a breathing-disturbance reading yet. This "
                        + "comes from a wearable that reports one — Oura's ring does — "
                        + "and it appears here as soon as one syncs.")
            }
            if trend.nights.count >= 2 {
                BreathingTrendChart(trend: trend,
                                    window: timeframe.chartWindow(
                                        spanning: trend.span.map {
                                            $0.upperBound.timeIntervalSince($0.lowerBound)
                                        }))
                if let percentile = trend.latestPercentile {
                    footnote(String(format: "Your most recent night sits above %.0f%% of "
                                    + "the %d nights recorded — a position among your own "
                                    + "nights, and nothing more than that.",
                                    percentile * 100, trend.nights.count))
                }
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The nights, the reader's own middle half, and the fitted line.
///
/// Wraps `ScrollableMetricChart`, so panning, the substance shading
/// (`add-chart` §9a), the empty-window message and the `‹` `›` jump-to-nearest
/// affordances (§9b) all arrive without a line of code here.
struct BreathingTrendChart: View {
    let trend: BreathingDisturbanceTrend
    let window: TimeInterval

    @State private var selection: Date?

    private var tint: Color { Theme.insightTint(.sleep) }

    private var nights: [BreathingDisturbanceTrend.Night] { trend.nights }

    /// Half a day either side, so the first and last points are not drawn on
    /// the plot's own edge.
    private var span: ClosedRange<Date>? {
        trend.span.map {
            $0.lowerBound.addingTimeInterval(-43_200)...$0.upperBound.addingTimeInterval(43_200)
        }
    }

    /// The reader's own middle half — the 25th and 75th centiles of every night
    /// they have, **not** of the visible window, so it agrees with the
    /// percentile sentence under the chart.
    private var middleHalf: (low: Double, high: Double)? {
        let values = nights.map(\.value)
        guard values.count >= 4,
              let low = Baseline.quantile(0.25, of: values),
              let high = Baseline.quantile(0.75, of: values),
              low < high else { return nil }
        return (low, high)
    }

    private func night(at date: Date) -> BreathingDisturbanceTrend.Night? {
        guard let nearest = nights.min(by: {
            abs($0.night.timeIntervalSince(date)) < abs($1.night.timeIntervalSince(date))
        }), abs(nearest.night.timeIntervalSince(date)) <= window / 10 else { return nil }
        return nearest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
            caption
        }
    }

    /// Above the chart as an ordinary view, never a mark `.annotation` — on this
    /// SDK a `RuleMark` chain can resolve to `Chart3DContent`, which has none
    /// (`add-chart` §2). The blank line keeps the height constant so a scrub
    /// cannot move the page.
    @ViewBuilder private var readout: some View {
        if let selection, let hit = night(at: selection) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(MetricValueFormatter.string(hit.value, .breathingDisturbanceIndex))
                    .font(.caption.weight(.semibold)).monospacedDigit()
                Text(hit.night.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .foregroundStyle(.secondary)
                if let median = trend.median, abs(hit.value - median) >= 0.1 {
                    Text(String(format: "· %.1f %@ than your middle night",
                                abs(hit.value - median),
                                hit.value > median ? "higher" : "lower"))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .font(.caption2)
        } else {
            Text(" ").font(.caption2)
        }
    }

    private var chart: some View {
        ScrollableMetricChart(
            dataSpan: span,
            window: window,
            selection: $selection,
            height: 165,
            emptyMessage: "Nothing was recorded in the period on screen. Swipe the chart sideways, tap the arrows on its edges to jump to your nearest nights, or pick a longer timeframe.",
            isEmpty: { range in !nights.contains { range.contains($0.night) } },
            yDomain: { range in yDomain(range) }
        ) { range in
            marks(nights.filter { range.contains($0.night) }, range: range)
        }
    }

    /// Scaled to the visible nights and the band, so panning rescales rather
    /// than flattening a quiet fortnight against an outlier elsewhere.
    private func yDomain(_ range: ClosedRange<Date>) -> ClosedRange<Double>? {
        let visible = nights.filter { range.contains($0.night) }.map(\.value)
        guard let low = visible.min(), let high = visible.max() else { return nil }
        let bandLow = middleHalf.map { $0.low } ?? low
        let bandHigh = middleHalf.map { $0.high } ?? high
        let lower = Swift.max(0, Swift.min(low, bandLow) - 0.5)
        let upper = Swift.max(high, bandHigh) + 0.5
        return lower < upper ? lower...upper : nil
    }

    /// ⚠️ Explicit `-> some ChartContent` on every builder, and `ForEach` rather
    /// than a bare `if` — without both, a `RuleMark`/`RectangleMark` chain can
    /// resolve to `Chart3DContent` on this SDK and silently drop its modifiers
    /// (`add-chart` §2).
    @ChartContentBuilder
    private func marks(_ visible: [BreathingDisturbanceTrend.Night],
                       range: ClosedRange<Date>) -> some ChartContent {
        bandMark(range: range)
        fittedLine(range: range)
        ForEach(visible) { night in
            PointMark(x: .value("Night", night.night),
                      y: .value("Index", night.value))
                .foregroundStyle(tint.opacity(0.8))
                .symbolSize(30)
        }
    }

    /// The middle half of the reader's nights. A plain low-opacity fill and
    /// **not** `Theme.scoreFill` — the height here encodes an index nobody
    /// scores, so a band ramp would encode a judgement that does not exist
    /// (`add-chart` §7a: ramp only where moving along the gradient means moving
    /// along a scored quantity).
    @ChartContentBuilder
    private func bandMark(range: ClosedRange<Date>) -> some ChartContent {
        ForEach(middleHalf.map { [$0] } ?? [], id: \.low) { band in
            RectangleMark(xStart: .value("From", range.lowerBound),
                          xEnd: .value("To", range.upperBound),
                          yStart: .value("Low", band.low),
                          yEnd: .value("High", band.high))
                .foregroundStyle(tint.opacity(0.10))
        }
    }

    /// The fit, drawn only where the model says there is a direction worth
    /// naming — `isMeaningful` is the same gate `driftSentence` uses, so the
    /// line and the sentence appear and disappear together.
    ///
    /// Dashed, because a fitted value is not a night anybody had
    /// (`add-chart` §3).
    @ChartContentBuilder
    private func fittedLine(range: ClosedRange<Date>) -> some ChartContent {
        ForEach(fittedPoints(range: range), id: \.date) { point in
            LineMark(x: .value("Night", point.date),
                     y: .value("Fitted", point.value),
                     series: .value("Series", "fit"))
                .foregroundStyle(tint.opacity(0.6))
                .lineStyle(Theme.projectedStroke)
                .interpolationMethod(.linear)
        }
    }

    /// Two points are enough for a straight line, and clipping them to the
    /// nights actually recorded stops the fit being extrapolated across a
    /// stretch with no data in it.
    private func fittedPoints(range: ClosedRange<Date>) -> [(date: Date, value: Double)] {
        guard let fit = trend.trend, fit.isMeaningful, let span = trend.span else { return [] }
        let from = Swift.max(range.lowerBound, span.lowerBound)
        let to = Swift.min(range.upperBound, span.upperBound)
        guard from < to else { return [] }
        return [(from, fit.value(at: from)), (to, fit.value(at: to))]
    }

    private var caption: some View {
        Text(trend.trend?.isMeaningful == true
             ? "Each point is one night. The band is the middle half of every night you have recorded, and the dashed line is the fit through all of them — the same line the sentence above quotes, so it does not change as you scroll. It is dashed because a fitted value is not a night you had."
             : "Each point is one night. The band is the middle half of every night you have recorded. No line is drawn: the slope through these nights is smaller than how much they differ from each other, so there is no direction here worth naming.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
