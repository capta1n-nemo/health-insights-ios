import SwiftUI
import Charts
import InsightKit

/// How long you took to fall asleep, night by night, with the fitted drift laid
/// over it.
///
/// A scatter of nights plus a dashed trend line — deliberately **not** a
/// connected line. Latency is one value per night and nights go missing; joining
/// two of them with a solid segment would draw a "trend" between readings nobody
/// took, the exact thing `add-chart` §4 forbids. The measured points stay points;
/// the only line on the chart is the fit, and a fit is inferred, so it is dashed
/// (`Theme.projectedStroke`) — §3.
///
/// Wraps `ScrollableMetricChart` for pan/zoom/scrub and the y-scale like every
/// other chart in the app (§1), and every mark builder is an explicit
/// `some ChartContent` so the chain cannot resolve to 3D content and drop its
/// modifiers (§2).
struct SleepOnsetChart: View {
    let points: [SleepOnsetModel.Sample]
    let trend: ScoreTrend?
    var window: TimeInterval = 60 * 24 * 3600
    var selection: Binding<Date?>?

    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }
    private var tint: Color { Theme.metricColor(.sleepLatencyMinutes,
                                                slots: MetricPalette.slots(for: [.sleepLatencyMinutes])) }

    private var span: ClosedRange<Date>? {
        guard let first = points.first?.date, let last = points.last?.date,
              first <= last else { return nil }
        return first...last
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
        }
    }

    /// Above the chart, never a mark annotation — 3D content has none (§2).
    @ViewBuilder private var readout: some View {
        if let selected, let hit = point(at: selected) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text("\(Int(hit.value.rounded())) min")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                Text(hit.date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.tertiary)
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
            height: 150,
            emptyMessage: "No nights in this window",
            isEmpty: { range in !points.contains { range.contains($0.date) } },
            yDomain: { range in yDomain(range) }
        ) { range in
            onsetMarks(points.filter { range.contains($0.date) }, range: range)
        }
    }

    /// The visible nights, floored at zero, with a little headroom — so a pan
    /// rescales to what is on screen rather than flattening against an outlier
    /// elsewhere (§10: axis fits the visible window).
    private func yDomain(_ range: ClosedRange<Date>) -> ClosedRange<Double>? {
        let visible = points.filter { range.contains($0.date) }.map(\.value)
        guard let hi = visible.max() else { return nil }
        return 0...(Swift.max(hi * 1.15, 10))
    }

    @ChartContentBuilder
    private func onsetMarks(_ visible: [SleepOnsetModel.Sample],
                           range: ClosedRange<Date>) -> some ChartContent {
        trendMarks(range: range)
        ForEach(visible, id: \.date) { night in
            PointMark(x: .value("Night", night.date),
                      y: .value("Minutes", night.value))
                .foregroundStyle(tint)
                .symbolSize(26)
        }
    }

    private struct TrendPoint: Identifiable {
        let id: String
        let date: Date
        let minutes: Double
    }

    /// The fitted drift, dashed because it is inferred. Two endpoints across the
    /// visible range; the fit is a straight line so two points define it.
    @ChartContentBuilder
    private func trendMarks(range: ClosedRange<Date>) -> some ChartContent {
        ForEach(trendLine(range)) { point in
            LineMark(x: .value("Night", point.date),
                     y: .value("Minutes", point.minutes),
                     series: .value("Series", "fit"))
                .foregroundStyle(tint.opacity(0.6))
                .lineStyle(Theme.projectedStroke)
                .interpolationMethod(.linear)
        }
    }

    private func trendLine(_ range: ClosedRange<Date>) -> [TrendPoint] {
        guard let trend, trend.isMeaningful,
              let first = points.first?.date, let last = points.last?.date,
              first < last else { return [] }
        // Clamp the drawn ends to where data actually is, not the padded range.
        let lo = Swift.max(range.lowerBound, first)
        let hi = Swift.min(range.upperBound, last)
        guard lo < hi else { return [] }
        return [lo, hi].enumerated().map { index, date in
            TrendPoint(id: "fit-\(index)", date: date,
                       minutes: Swift.max(0, trend.value(at: date)))
        }
    }
}
