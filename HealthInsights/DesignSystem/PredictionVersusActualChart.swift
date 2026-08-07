import SwiftUI
import Charts
import InsightKit

/// **What the app said, against what turned out to be true.**
///
/// Backlog P24. One chart, two series over the same dates, and a vertical rule
/// joining each pair so the miss itself is the thing you see rather than
/// something you have to measure off the axis.
///
/// ## The encoding, and why it is the only honest one available
///
/// - **The truth is solid.** A cuff reading is a measurement.
/// - **The prediction is dashed** (`Theme.projectedStroke`). Dash means "not
///   measured" everywhere in this app and means nothing else — see the
///   `add-chart` skill §3 — and a modelled value drawn solid beside a measured
///   one is precisely the confusion the rule exists to stop.
/// - **Both share the metric's own hue.** Hue is identity, and these two series
///   are the *same quantity*: this reader's systolic pressure, once guessed and
///   once measured. Giving them different hues would say they were different
///   things; the dash already carries the only difference there is.
/// - **The miss is a rule between them**, in neutral grey. It is neither series
///   and asserts nothing about direction beyond what the geometry shows.
///
/// It wraps `ScrollableMetricChart`, so panning, scrubbing, the `‹` `›`
/// jump-to-nearest affordances and the substance shading all arrive without a
/// line here — and `verify.sh`'s shading rule is satisfied by the wrapper rather
/// than by an exemption.
///
/// ⚠️ **No trend line, deliberately.** "Is it getting better?" is the obvious
/// next question and it is unanswerable at the counts a real person accumulates:
/// a slope through eight residuals is noise with a direction. `CalibrationReport`
/// withholds the figures that need more, and this chart withholds the picture
/// that would imply them.
struct PredictionVersusActualChart: View {
    let report: CalibrationReport
    var height: CGFloat = 170

    @State private var selection: Date?

    private var pairs: [GradedPrediction] { report.pairs }

    private var span: ClosedRange<Date>? {
        guard let first = pairs.first?.date, let last = pairs.last?.date,
              first <= last else { return nil }
        return first...last
    }

    /// The whole record fits on screen at rest, with room either side, and pans
    /// from there. A fixed 30-day window would open on an empty chart for a
    /// reader whose five readings are spread over a year — the exact "panned off
    /// the data" state the chevrons exist to rescue people from, presented as
    /// the *default*.
    private var window: TimeInterval {
        guard let span else { return 30 * 24 * 3600 }
        let extent = span.upperBound.timeIntervalSince(span.lowerBound)
        return max(14 * 24 * 3600, extent * 1.2)
    }

    /// Nearest pair to the scrubbed instant, ignoring anything too far away to
    /// be what the finger is pointing at.
    private func pair(at date: Date) -> GradedPrediction? {
        guard let nearest = pairs.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }), abs(nearest.date.timeIntervalSince(date)) <= window / 8 else { return nil }
        return nearest
    }

    /// **No `slots:` here, and that is safe rather than an omission.** The
    /// slot-aware call exists because `Theme.metricColor`'s preferred hues
    /// collide in pairs — systolic with diastolic, RMSSD with SDNN — and a
    /// chart drawing two of them needs the collision resolved. This chart draws
    /// **one** metric, twice; there is no second metric here to collide with.
    private var hue: Color { Theme.metricColor(report.metric) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
            key
        }
    }

    /// Above the chart as a normal view, never as a mark `.annotation`: on this
    /// SDK a `RuleMark` chain can resolve to `Chart3DContent`, which has no
    /// annotation at all.
    ///
    /// The blank line in the `else` branch is load-bearing — it holds the height
    /// so that scrubbing does not change the page's content height under the
    /// finger.
    @ViewBuilder private var readout: some View {
        if let selection, let hit = pair(at: selection) {
            HStack(spacing: 8) {
                Text(hit.date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
                Text(String(format: "said %.0f", hit.predicted))
                    .foregroundStyle(hue.opacity(0.75))
                Text(String(format: "was %.0f", hit.actual)).foregroundStyle(hue)
                Text(String(format: "· out by %.0f %@", hit.absoluteError, report.unit))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .font(.caption2.monospacedDigit())
        } else {
            Text(" ").font(.caption2)
        }
    }

    private var chart: some View {
        ScrollableMetricChart(
            dataSpan: span,
            window: window,
            selection: $selection,
            height: height,
            emptyMessage: "No graded predictions in the period on screen",
            isEmpty: { range in !pairs.contains { range.contains($0.date) } },
            yDomain: { range in domain(in: range) }
        ) { range in
            marks(pairs.filter { range.contains($0.date) })
        }
    }

    /// Fitted to what is on screen, over **both** series — scaling to the
    /// measured one alone would push a bad prediction off the top of the chart,
    /// which is the one reading this whole screen exists to show.
    private func domain(in range: ClosedRange<Date>) -> ClosedRange<Double>? {
        let visible = pairs.filter { range.contains($0.date) }
        let values = visible.flatMap { [$0.predicted, $0.actual] }
        guard let low = values.min(), let high = values.max() else { return nil }
        let pad = max(2, (high - low) * 0.2)
        return (low - pad)...(high + pad)
    }

    /// Explicit `some ChartContent`, as every mark builder in this app must
    /// have: without it the chain can resolve to 3D chart content on this SDK
    /// and silently drop `.lineStyle` and `.foregroundStyle`.
    @ChartContentBuilder
    private func marks(_ visible: [GradedPrediction]) -> some ChartContent {
        missMarks(visible)
        predictedMarks(visible)
        actualMarks(visible)
    }

    /// The gap between guess and truth, drawn as the thing it is.
    @ChartContentBuilder
    private func missMarks(_ visible: [GradedPrediction]) -> some ChartContent {
        ForEach(visible) { pair in
            RuleMark(x: .value("When", pair.date),
                     yStart: .value("Measured", pair.actual),
                     yEnd: .value("Predicted", pair.predicted))
                .foregroundStyle(Color.secondary.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
    }

    /// ⚠️ **Dashed and dimmed, because nobody measured it.**
    @ChartContentBuilder
    private func predictedMarks(_ visible: [GradedPrediction]) -> some ChartContent {
        ForEach(visible) { pair in
            LineMark(x: .value("When", pair.date),
                     y: .value(report.metric.displayName, pair.predicted),
                     series: .value("Series", "predicted"))
                .foregroundStyle(hue.opacity(0.55))
                .lineStyle(Theme.projectedStroke)
                // Straight, never curved: a curve would invent predictions for
                // days the model was never asked about.
                .interpolationMethod(.linear)
            PointMark(x: .value("When", pair.date),
                      y: .value(report.metric.displayName, pair.predicted))
                .foregroundStyle(hue.opacity(0.55))
                .symbol(.circle)
                .symbolSize(18)
        }
    }

    @ChartContentBuilder
    private func actualMarks(_ visible: [GradedPrediction]) -> some ChartContent {
        ForEach(visible) { pair in
            LineMark(x: .value("When", pair.date),
                     y: .value(report.metric.displayName, pair.actual),
                     series: .value("Series", "measured"))
                .foregroundStyle(hue)
                .interpolationMethod(.linear)
            PointMark(x: .value("When", pair.date),
                      y: .value(report.metric.displayName, pair.actual))
                .foregroundStyle(hue)
                .symbolSize(30)
        }
    }

    /// A key that names which line is a measurement, in words. The dash carries
    /// the meaning, and a reader who has not learnt the convention should not
    /// have to.
    private var key: some View {
        HStack(spacing: 14) {
            Label {
                Text("Measured (\(report.metric.displayName))").font(.caption2)
            } icon: {
                Rectangle().fill(hue).frame(width: 14, height: 2)
            }
            Label {
                Text("What the app predicted").font(.caption2)
            } icon: {
                Rectangle().fill(hue.opacity(0.55)).frame(width: 14, height: 2)
                    .mask(HStack(spacing: 2) {
                        Rectangle().frame(width: 4)
                        Rectangle().frame(width: 4)
                        Rectangle()
                    })
            }
            Spacer()
        }
        .foregroundStyle(.secondary)
    }
}
