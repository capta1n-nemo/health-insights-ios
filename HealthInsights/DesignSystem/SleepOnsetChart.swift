import SwiftUI
import Charts
import InsightKit

/// How long you took to fall asleep, night by night, against your usual.
///
/// Modelled on `SleepOnsetStripChart` (the "Your fortnight" bedtimes chart) at
/// the reader's request — the same **band and average line**: a dashed line at
/// your typical latency, and a band one standard deviation either side of it, so
/// a tight band reads as "consistent" and a wide one as "all over the place".
/// Both are **re-fitted over whatever window is on screen**, so scrolling to last
/// spring draws last spring's average, never this month's imposed on it.
///
/// The measured nights are solid points; the average and band are fitted
/// quantities, so the line is dashed and the band is a wash behind the points —
/// `add-chart` §3. Wraps `ScrollableMetricChart` for pan/zoom/scrub and takes the
/// card's `window` from the timeframe picker (§1).
struct SleepOnsetChart: View {
    let points: [SleepOnsetModel.Sample]
    let window: TimeInterval
    var selection: Binding<Date?>?

    @State private var localSelection: Date?
    @State private var visibleRange: ClosedRange<Date>?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }
    private var tint: Color { Theme.insightTint(.sleep) }

    private var span: ClosedRange<Date>? {
        guard let first = points.first?.date, let last = points.last?.date,
              first <= last else { return nil }
        return first.addingTimeInterval(-43_200)...last.addingTimeInterval(43_200)
    }

    /// The average and spread over the nights currently on screen — the fallback
    /// is the whole series, used before the chart has reported a range. A mean
    /// and a standard deviation over a few dozen nights, cheap enough for a drag.
    private var fitted: (mean: Double, sd: Double)? {
        let visible = (visibleRange.map { r in points.filter { r.contains($0.date) } } ?? points)
            .map(\.value)
        guard visible.count >= 2, let mean = Baseline.mean(visible),
              let sd = Baseline.standardDeviation(visible) else { return nil }
        return (mean, sd)
    }

    private func point(at date: Date) -> SleepOnsetModel.Sample? {
        guard let nearest = points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }), abs(nearest.date.timeIntervalSince(date)) <= window / 10 else { return nil }
        return nearest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
            caption
        }
    }

    /// Above the chart, never a mark annotation — 3D content has none (§2).
    @ViewBuilder private var readout: some View {
        if let selected, let hit = point(at: selected) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text("\(Int(hit.value.rounded())) min")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                Text(hit.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .foregroundStyle(.secondary)
                if let fitted {
                    let delta = hit.value - fitted.mean
                    if abs(delta) >= 2 {
                        Text(String(format: "· %d min %@ than usual", Int(abs(delta).rounded()),
                                    delta > 0 ? "slower" : "faster"))
                            .foregroundStyle(.tertiary)
                    }
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
            selection: selectionBinding,
            height: 160,
            emptyMessage: "No nights in this window",
            isEmpty: { range in !points.contains { range.contains($0.date) } },
            yDomain: { range in yDomain(range) },
            onVisibleRangeChange: { visibleRange = $0 }
        ) { range in
            onsetMarks(points.filter { range.contains($0.date) }, range: range)
        }
    }

    /// The visible nights and the band, floored at zero with a little headroom,
    /// so a pan rescales to what is on screen (§10).
    private func yDomain(_ range: ClosedRange<Date>) -> ClosedRange<Double>? {
        let visible = points.filter { range.contains($0.date) }.map(\.value)
        guard let hi = visible.max() else { return nil }
        let bandTop = fitted.map { $0.mean + $0.sd } ?? hi
        return 0...(Swift.max(hi, bandTop) * 1.15)
    }

    @ChartContentBuilder
    private func onsetMarks(_ visible: [SleepOnsetModel.Sample],
                           range: ClosedRange<Date>) -> some ChartContent {
        bandMark(range: range)
        averageMark
        ForEach(visible, id: \.date) { night in
            PointMark(x: .value("Night", night.date),
                      y: .value("Minutes", night.value))
                .foregroundStyle(tint.opacity(0.8))
                .symbolSize(30)
        }
    }

    /// One standard deviation either side of your usual latency, across the whole
    /// visible width — the fortnight chart's band, for onset. A `RectangleMark`,
    /// the same safe construction that chart uses (§7: a flat band between two
    /// heights).
    @ChartContentBuilder
    private func bandMark(range: ClosedRange<Date>) -> some ChartContent {
        ForEach(fitted.map { [$0] } ?? [], id: \.mean) { fit in
            RectangleMark(
                xStart: .value("From", range.lowerBound),
                xEnd: .value("To", range.upperBound),
                yStart: .value("Low", Swift.max(0, fit.mean - fit.sd)),
                yEnd: .value("High", fit.mean + fit.sd))
                .foregroundStyle(tint.opacity(0.10))
        }
    }

    /// Your usual time to fall asleep. Dashed because a fitted average is not a
    /// night anybody actually had.
    @ChartContentBuilder
    private var averageMark: some ChartContent {
        ForEach(fitted.map { [$0.mean] } ?? [], id: \.self) { mean in
            RuleMark(y: .value("Usual", mean))
                .foregroundStyle(tint.opacity(0.55))
                .lineStyle(Theme.projectedStroke)
        }
    }

    private var caption: some View {
        Text("Each point is one night. The dashed line is your usual time to fall asleep and the band is how far either side of it you typically land — the narrower the band, the more consistent. Both re-fit to whatever window you scroll to.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
