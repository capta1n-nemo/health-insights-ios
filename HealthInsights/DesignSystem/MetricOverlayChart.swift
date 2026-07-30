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

    /// Exactly which series to draw. Owned by the screen, because the legend is
    /// the picker and the two must agree about what is on the chart.
    var selectedMetrics: Set<MetricType> = []

    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }

    /// The selection rule lives in `OverlaySelection` so it can be tested
    /// without a running view — it decides whether two lines can look alike,
    /// and the first version of it shipped from here and got that wrong.
    private var visibleSeries: [NormalizedSeries] {
        OverlaySelection.visible(series, selected: selectedMetrics)
    }

    private var isFiltering: Bool { visibleSeries.count < series.count }

    /// Hues resolved across the series actually on screen, so no two share one.
    private var slots: [MetricType: Int] {
        MetricPalette.slots(for: visibleSeries.map(\.metric))
    }

    /// A flat point list: nesting a ForEach over series inside a ForEach over
    /// segments inside a ForEach over points exceeds what the chart builder's
    /// type checker will accept — the same shape `MultiSourceChart` settled on.
    private struct Point: Identifiable {
        var id: String { "\(metric.rawValue)@\(date.timeIntervalSince1970)" }
        let date: Date
        let value: Double
        let metric: MetricType
        let label: String
        /// How far from baseline this day was, in SDs, regardless of the scale
        /// being displayed — opacity always tracks the anomaly, not the axis.
        let z: Double
    }

    private struct Segment: Identifiable {
        let id: String
        let points: [Point]
    }

    /// One drawn span between two adjacent readings, carrying the opacity that
    /// span has earned.
    ///
    /// A line is emitted per *pair* rather than per run because opacity has to
    /// vary along it: the flat, ordinary stretches recede almost to nothing and
    /// the peaks and troughs come forward, so seventeen overlaid signals read as
    /// a handful of interesting moments rather than as spaghetti. Swift Charts
    /// applies one style per mark, so varying it means more marks.
    private struct Span: Identifiable {
        let id: String
        let from: Point
        let to: Point
        let opacity: Double
        /// True where nothing was measured between the two ends — drawn dashed,
        /// and never given a dot at either end.
        var isInferred: Bool = false
    }

    /// Baseline is nearly invisible; |z| ≥ 3 is fully opaque.
    static func opacity(forZ z: Double) -> Double {
        let magnitude = Swift.min(abs(z), 3) / 3
        return 0.12 + 0.88 * pow(magnitude, 1.4)
    }

    /// Dots only where something happened, so they mark notable days rather
    /// than decorating every one. Same threshold that decides which series are
    /// drawn at all, so "away from baseline" means one thing on this chart.
    static let pointThreshold = OverlaySelection.notableZ

    /// Most points one series may contribute to one screen.
    ///
    /// Varying opacity costs a mark per span rather than per run, so seventeen
    /// series over two years would be tens of thousands of marks. This is the
    /// ceiling that keeps "All" openable.
    static let maxPointsPerSeries = 110

    /// Thin a run to at most `maxPointsPerSeries`, **keeping the extremes**.
    ///
    /// Not an even stride: a stride drops exactly the days this chart exists to
    /// show. Each bucket contributes its most anomalous reading, so a spike
    /// survives thinning even when a fortnight around it does not.
    static func thinned(_ points: [NormalizedPoint],
                        limit: Int = maxPointsPerSeries) -> [NormalizedPoint] {
        guard points.count > limit, limit > 0 else { return points }
        let bucketSize = Double(points.count) / Double(limit)
        var kept: [NormalizedPoint] = []
        kept.reserveCapacity(limit)
        for bucket in 0..<limit {
            let start = Int(Double(bucket) * bucketSize)
            let end = Swift.min(points.count, Swift.max(start + 1, Int(Double(bucket + 1) * bucketSize)))
            guard start < end,
                  let peak = points[start..<end].max(by: { abs($0.z) < abs($1.z) }) else { continue }
            kept.append(peak)
        }
        return kept
    }

    private var span: ClosedRange<Date>? {
        let dates = series.flatMap { $0.points.map(\.date) }
        guard let first = dates.min(), let last = dates.max(), first <= last else { return nil }
        return first...last
    }

    private func plotted(in range: ClosedRange<Date>) -> [Segment] {
        runs(in: range).flatMap { $0.segments }
    }

    /// The drawn segments of one series, kept grouped so the gaps *between* them
    /// can be considered.
    private struct Run {
        let metric: MetricType
        let segments: [Segment]
    }

    private func runs(in range: ClosedRange<Date>) -> [Run] {
        visibleSeries.map { one in
            let label = one.metric.displayName
            var segments: [Segment] = []
            for (index, run) in one.segments().enumerated() {
                let points = Self.thinned(run.filter { range.contains($0.date) })
                    .map { Point(date: $0.date, value: $0.value(scale),
                                 metric: one.metric, label: label, z: $0.z) }
                guard !points.isEmpty else { continue }
                segments.append(Segment(id: "\(one.metric.rawValue)#\(index)", points: points))
            }
            return Run(metric: one.metric, segments: segments)
        }
    }

    /// Every drawn span, with the opacity each has earned. A span is as
    /// prominent as its more anomalous end.
    private func spans(in range: ClosedRange<Date>) -> [Span] {
        var out: [Span] = []
        for run in runs(in: range) {
            for segment in run.segments {
                for (index, pair) in zip(segment.points, segment.points.dropFirst()).enumerated() {
                    let peak = Swift.max(abs(pair.0.z), abs(pair.1.z))
                    out.append(Span(id: "\(segment.id)|\(index)", from: pair.0, to: pair.1,
                                    opacity: Self.opacity(forZ: peak)))
                }
                // A run of one has no span, so give it a visible dot regardless.
                if segment.points.count == 1, let only = segment.points.first {
                    out.append(Span(id: "\(segment.id)|solo", from: only, to: only,
                                    opacity: Self.opacity(forZ: only.z)))
                }
            }
            out += bridgeSpans(of: run)
        }
        return out
    }

    /// The short gaps in one series, crossed with a dashed connector.
    ///
    /// This chart broke at every gap while the metric-detail chart bridged them,
    /// so the same silence rendered two different ways depending on which screen
    /// you were on. The rule is the shared one in `SeriesBridging` — a gap may
    /// be crossed only when it is within a small multiple of the metric's own
    /// join distance *and* within a quarter of the visible window.
    ///
    /// Paired from the **drawn** endpoints rather than the underlying ones,
    /// because `thinned` can drop a segment's true first or last point at long
    /// zoom. Using the drawn ends guarantees the connector actually touches the
    /// lines it joins, and errs conservative: a thinned-away endpoint makes the
    /// apparent gap wider, so it bridges less often, never more.
    private func bridgeSpans(of run: Run) -> [Span] {
        let pairs = SeriesBridging.bridgePairs(
            across: run.segments.map(\.points), metric: run.metric,
            // A daily grid by construction — the same assumption `segments()`
            // makes.
            bucket: .day, window: window, date: \.date)
        return pairs.enumerated().map { index, pair in
            Span(id: "\(run.metric.rawValue)~bridge\(index)", from: pair.from, to: pair.to,
                 opacity: SeriesBridging.bridgeProminence(
                    from: Self.opacity(forZ: pair.from.z),
                    to: Self.opacity(forZ: pair.to.z)),
                 isInferred: true)
        }
    }


    /// One row of the scrub read-out.
    private struct Callout: Identifiable {
        let metric: MetricType
        let text: String
        var id: MetricType { metric }
    }

    private func readings(at date: Date) -> [Callout] {
        visibleSeries.compactMap { one in
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
                            Circle().fill(Theme.metricColor(row.metric, slots: slots))
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
            emptyMessage: visibleSeries.isEmpty
                ? "Nothing selected — tap a signal below to put it on the chart."
                : isFiltering
                    ? "Nothing selected here is away from your usual pattern in this window."
                    : "No readings in this window",
            isEmpty: { range in plotted(in: range).isEmpty },
            yDomain: { range in
                paddedYDomain(plotted(in: range).flatMap { $0.points.map(\.value) },
                              logarithmic: scale == .raw && logarithmic)
            }
        ) { range in
            overlayMarks(spans(in: range))
        }
    }

    /// No `chartForegroundStyleScale` any more: each span needs its own opacity,
    /// which a domain/range scale keyed on metric name cannot express. Charts'
    /// own legend was already hidden in favour of `MetricOverlayLegend`, so
    /// styling marks directly costs nothing.
    @ChartContentBuilder
    private func overlayMarks(_ spans: [Span]) -> some ChartContent {
        baselineMark
        ForEach(spans) { span in
            marks(for: span)
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
                .lineStyle(Theme.referenceStroke)
        }
    }

    /// One span of one series.
    ///
    /// Explicit return type, as every mark builder here must have — without it
    /// this chain can resolve to 3D chart content and silently drop
    /// `.foregroundStyle`, which is load-bearing here: opacity per span is the
    /// whole encoding.
    @ChartContentBuilder
    private func marks(for span: Span) -> some ChartContent {
        let colour = Theme.metricColor(span.from.metric, slots: slots).opacity(span.opacity)
        // Dash means "not measured" and nothing else in this app, so a bridge
        // takes the reference stroke and a measured span keeps its own.
        let stroke = span.isInferred
            ? Theme.projectedStroke : Theme.metricStroke(span.from.metric)
        LineMark(x: .value("Day", span.from.date), y: .value("Value", span.from.value),
                 series: .value("Span", span.id))
            .foregroundStyle(colour)
            .lineStyle(stroke)
            .interpolationMethod(.linear)
        LineMark(x: .value("Day", span.to.date), y: .value("Value", span.to.value),
                 series: .value("Span", span.id))
            .foregroundStyle(colour)
            .lineStyle(stroke)
            .interpolationMethod(.linear)
        // Dots only on days worth noticing, so the eye lands on the departures.
        ForEach(notableEnds(of: span)) { point in
            PointMark(x: .value("Day", point.date), y: .value("Value", point.value))
                .foregroundStyle(Theme.metricColor(point.metric, slots: slots))
                .symbolSize(24)
        }
    }

    private func notableEnds(of span: Span) -> [Point] {
        var out: [Point] = []
        // A bridge's ends are already dotted by the measured spans either side
        // of it; dotting them again from here would double-draw them and, on a
        // series whose segments are single points, would mark an inferred span
        // as though it were an observation.
        guard !span.isInferred else { return out }
        if abs(span.to.z) >= Self.pointThreshold { out.append(span.to) }
        // The first point of a series has no preceding span to draw it.
        if span.from.id == span.to.id, out.isEmpty { out.append(span.from) }
        return out
    }
}
