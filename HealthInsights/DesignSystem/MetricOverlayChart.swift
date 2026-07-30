import SwiftUI
import Charts
import InsightKit

/// Every metric behind one insight, drawn on a single axis so they can be
/// compared with each other.
///
/// `MultiSourceChart` overlays one *metric* split by *device*; this overlays
/// several *metrics* against each other. That's only possible because the series
/// arrive standardised — see `SeriesNormalizer`. A log axis was the obvious first
/// idea and doesn't work: the log of blood oxygen (95–99%) is a flat line while
/// the log of sleep (5–9 h) still swings, so the shapes stay incomparable. Raw
/// mode is still offered, because sometimes you want the actual numbers, and it
/// carries a health warning in the caption rather than pretending otherwise.
///
/// Note there is exactly one Y scale here. Two scales for two units is the
/// classic way to make any two lines appear to agree, and it is never done.
struct MetricOverlayChart: View {
    let series: [NormalizedSeries]
    var scale: SeriesScale = .zScore
    var logarithmic: Bool = false
    var window: TimeInterval = 30 * 24 * 3600
    var selection: Binding<Date?>?

    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }

    /// A flat point list: nesting a ForEach over series inside a ForEach over
    /// segments inside a ForEach over points exceeds what the chart builder's
    /// type checker will accept — the same shape `MultiSourceChart` settled on.
    private struct Point: Identifiable {
        var id: String { "\(metric.rawValue)@\(date.timeIntervalSince1970)" }
        let date: Date
        let value: Double
        let metric: MetricType
        let label: String
    }

    private struct Segment: Identifiable {
        let id: String
        let points: [Point]
    }

    private var span: ClosedRange<Date>? {
        let dates = series.flatMap { $0.points.map(\.date) }
        guard let first = dates.min(), let last = dates.max(), first <= last else { return nil }
        return first...last
    }

    private func plotted(in range: ClosedRange<Date>) -> [Segment] {
        var out: [Segment] = []
        for one in series {
            let label = one.metric.displayName
            for (index, run) in one.segments().enumerated() {
                let points = run.filter { range.contains($0.date) }
                    .map { Point(date: $0.date, value: $0.value(scale),
                                 metric: one.metric, label: label) }
                guard !points.isEmpty else { continue }
                out.append(Segment(id: "\(one.metric.rawValue)#\(index)", points: points))
            }
        }
        return out
    }

    private var domain: [String] { series.map(\.metric.displayName) }
    private var colours: [Color] { series.map { Theme.metricColor($0.metric) } }

    /// One row of the scrub read-out.
    private struct Callout: Identifiable {
        let metric: MetricType
        let text: String
        var id: MetricType { metric }
    }

    private func readings(at date: Date) -> [Callout] {
        series.compactMap { one in
            guard let nearest = one.points.min(by: {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }), abs(nearest.date.timeIntervalSince(date)) <= window / 8 else { return nil }
            let text = scale == .raw
                ? formatMetric(nearest.raw, one.metric)
                : String(format: "%+.1f", nearest.z)
            return Callout(metric: one.metric, text: text)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
        }
    }

    @ViewBuilder private var readout: some View {
        if let selected, case let rows = readings(at: selected), !rows.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(rows) { row in
                        HStack(spacing: 5) {
                            Circle().fill(Theme.metricColor(row.metric))
                                .frame(width: 7, height: 7)
                            Text(row.text).monospacedDigit()
                        }
                    }
                    Text(selected.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption2)
            }
        } else {
            Text(" ").font(.caption2)
        }
    }

    private var chart: some View {
        ScrollableMetricChart(
            dataSpan: span,
            window: window,
            selection: selectionBinding,
            logarithmic: scale == .raw && logarithmic,
            height: 190,
            emptyMessage: "No readings in this window",
            isEmpty: { range in plotted(in: range).isEmpty },
            yDomain: { range in
                paddedYDomain(plotted(in: range).flatMap { $0.points.map(\.value) },
                              logarithmic: scale == .raw && logarithmic)
            }
        ) { range in
            overlayMarks(plotted(in: range))
        }
        .chartForegroundStyleScale(domain: domain, range: colours)
    }

    @ChartContentBuilder
    private func overlayMarks(_ segments: [Segment]) -> some ChartContent {
        baselineMark
        ForEach(segments) { segment in
            ForEach(segment.points) { point in
                marks(for: point)
            }
        }
    }

    /// "Your normal" — the line every standardised series is measured against.
    /// Only meaningful in compare mode; in raw mode zero is just zero.
    /// A `ForEach` over an empty array rather than an `if`, to keep the builder
    /// on the one construction this app has verified against the 3D-content
    /// overload hazard — a bare conditional in a chart builder is exactly the
    /// shape that has silently dropped `.lineStyle` here before.
    @ChartContentBuilder
    private var baselineMark: some ChartContent {
        ForEach(scale == .zScore ? [0.0] : [], id: \.self) { level in
            RuleMark(y: .value("Your normal", level))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }

    /// Explicit return type, as every mark builder here must have — without it
    /// this chain can resolve to 3D chart content and drop its modifiers.
    @ChartContentBuilder
    private func marks(for p: Point) -> some ChartContent {
        LineMark(x: .value("Day", p.date), y: .value("Value", p.value))
            .foregroundStyle(by: .value("Metric", p.label))
            .interpolationMethod(.linear)
        PointMark(x: .value("Day", p.date), y: .value("Value", p.value))
            .foregroundStyle(by: .value("Metric", p.label))
            .symbolSize(20)
    }
}

/// The legend under the overlay.
///
/// Not optional decoration: four of the eight light-mode hues sit below 3:1
/// against the grouped background, so the palette is only accessible with the
/// names and values written out beside the swatches. It also carries the metrics
/// that have *no* data, which is the difference between "this doesn't affect your
/// score" and "we couldn't measure it".
struct MetricOverlayLegend: View {
    let series: [NormalizedSeries]
    let contributions: [MetricContribution]
    /// Declared inputs with nothing to plot — shown dimmed rather than omitted.
    let missing: [MetricType]
    var onSelect: ((MetricType) -> Void)?

    private func contribution(for metric: MetricType) -> MetricContribution? {
        contributions.first { $0.metric == metric }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(series) { one in
                row(one)
            }
            ForEach(missing, id: \.self) { metric in
                missingRow(metric)
            }
        }
    }

    private func row(_ one: NormalizedSeries) -> some View {
        let contribution = contribution(for: one.metric)
        return Button {
            onSelect?(one.metric)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Theme.metricColor(one.metric)).frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(one.metric.displayName)
                        .font(.subheadline)
                    if let weight = contribution?.weight, weight > 0 {
                        Text("\(Int((weight * 100).rounded()))% of this score")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if let trend = trendPhrase(one) {
                        Text(trend).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // The model's own formatting when it reported one, otherwise the
                // latest plotted value. Checked for emptiness, not just for nil:
                // a stand-in contribution carries a blank detail, and printing
                // that would leave the row with no number at all.
                if let detail = contribution?.detail, !detail.isEmpty {
                    Text(detail).font(.subheadline.weight(.medium))
                        .monospacedDigit()
                } else if let raw = one.latest?.raw {
                    Text(formatMetric(raw, one.metric))
                        .font(.subheadline.weight(.medium)).monospacedDigit()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func missingRow(_ metric: MetricType) -> some View {
        HStack(spacing: 8) {
            Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                .frame(width: 9, height: 9)
            Text(metric.displayName).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text("No data").font(.caption).foregroundStyle(.tertiary)
        }
    }

    /// Direction over the window, in plain words, and whether that direction is
    /// the good one for this particular signal — rising HRV and rising resting
    /// heart rate mean opposite things, and a bare arrow would imply otherwise.
    /// Silent about good-or-bad where neither direction is (temperature
    /// deviation is best near zero).
    private func trendPhrase(_ one: NormalizedSeries) -> String? {
        guard let slope = one.trendPerWeek, abs(slope) >= PatternFinder.minimumSlope else {
            return "steady"
        }
        let rising = slope > 0
        let direction = rising ? "trending up" : "trending down"
        guard let higherIsBetter = one.higherIsBetter else { return direction }
        return direction + (rising == higherIsBetter ? " (good)" : " (worth watching)")
    }
}
