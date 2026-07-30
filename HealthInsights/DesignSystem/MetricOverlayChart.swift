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

    /// Whether to draw every series or only the ones away from baseline. Owned
    /// by the screen rather than here, because the legend carries the toggle
    /// and the two must agree about what is on the chart.
    var showsAllSeries: Bool = false

    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }

    /// A series counts as away from baseline if any day in it reached the same
    /// departure that earns a point marker — so "anomalous" means one thing on
    /// this chart, not two.
    static func isNotable(_ one: NormalizedSeries) -> Bool {
        one.points.contains { abs($0.z) >= pointThreshold }
    }

    /// What to draw.
    ///
    /// Up to `comfortableSeriesCount` there are enough distinct hues for all of
    /// them, so all of them are drawn. Above that, only the series away from
    /// baseline — the same principle as the drivers card, which leads with what
    /// departed and folds the routine majority away. Nothing is hidden
    /// permanently: the legend's toggle brings the rest back.
    ///
    /// Static so the legend can ask the same question and get the same answer;
    /// a legend keyed to a different set than the chart is worse than none.
    static func visible(_ series: [NormalizedSeries], showingAll: Bool) -> [NormalizedSeries] {
        guard filters(series, showingAll: showingAll) else { return series }
        return series.filter { isNotable($0) }
    }

    static func filters(_ series: [NormalizedSeries], showingAll: Bool) -> Bool {
        !showingAll && series.count > MetricPalette.comfortableSeriesCount
    }

    private var visibleSeries: [NormalizedSeries] {
        Self.visible(series, showingAll: showsAllSeries)
    }

    private var isFiltering: Bool { Self.filters(series, showingAll: showsAllSeries) }

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
    }

    /// Baseline is nearly invisible; |z| ≥ 3 is fully opaque.
    static func opacity(forZ z: Double) -> Double {
        let magnitude = Swift.min(abs(z), 3) / 3
        return 0.12 + 0.88 * pow(magnitude, 1.4)
    }

    /// Dots only where something happened, so they mark notable days rather
    /// than decorating every one.
    static let pointThreshold = 1.5

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
        var out: [Segment] = []
        for one in visibleSeries {
            let label = one.metric.displayName
            for (index, run) in one.segments().enumerated() {
                let points = Self.thinned(run.filter { range.contains($0.date) })
                    .map { Point(date: $0.date, value: $0.value(scale),
                                 metric: one.metric, label: label, z: $0.z) }
                guard !points.isEmpty else { continue }
                out.append(Segment(id: "\(one.metric.rawValue)#\(index)", points: points))
            }
        }
        return out
    }

    /// Every drawn span, with the opacity each has earned. A span is as
    /// prominent as its more anomalous end.
    private func spans(in range: ClosedRange<Date>) -> [Span] {
        var out: [Span] = []
        for segment in plotted(in: range) {
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
        return out
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
            emptyMessage: isFiltering
                ? "Nothing is away from your usual pattern here — turn on \"Show every signal\" to see them all."
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
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
        LineMark(x: .value("Day", span.from.date), y: .value("Value", span.from.value),
                 series: .value("Span", span.id))
            .foregroundStyle(colour)
            .lineStyle(Theme.metricStroke(span.from.metric))
            .interpolationMethod(.linear)
        LineMark(x: .value("Day", span.to.date), y: .value("Value", span.to.value),
                 series: .value("Span", span.id))
            .foregroundStyle(colour)
            .lineStyle(Theme.metricStroke(span.from.metric))
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
        if abs(span.to.z) >= Self.pointThreshold { out.append(span.to) }
        // The first point of a series has no preceding span to draw it.
        if span.from.id == span.to.id, out.isEmpty { out.append(span.from) }
        return out
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
    /// Shared with the chart, so the key and the plot never disagree about
    /// what's on screen.
    var showsAllSeries: Binding<Bool>?
    var onSelect: ((MetricType) -> Void)?

    /// The list expands independently of the chart: you can read about a signal
    /// without adding a line to a crowded plot.
    @State private var showsRoutineRows = false

    private var showingAll: Bool { showsAllSeries?.wrappedValue ?? true }
    private var charted: [NormalizedSeries] {
        MetricOverlayChart.visible(series, showingAll: showingAll)
    }
    /// Rows for series the chart isn't currently drawing.
    private var offChart: [NormalizedSeries] {
        let shown = Set(charted.map(\.metric))
        return series.filter { !shown.contains($0.metric) }
    }
    private var slots: [MetricType: Int] {
        MetricPalette.slots(for: charted.map(\.metric))
    }

    private func contribution(for metric: MetricType) -> MetricContribution? {
        contributions.first { $0.metric == metric }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(charted) { one in
                row(one, slot: slots[one.metric])
            }

            if !offChart.isEmpty {
                Divider()
                Button {
                    withAnimation(.snappy) { showsRoutineRows.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(showsRoutineRows
                             ? "Hide the rest"
                             : "Show \(offChart.count) more in your normal range")
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .rotationEffect(.degrees(showsRoutineRows ? 180 : 0))
                        Spacer()
                    }
                    .foregroundStyle(Theme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showsRoutineRows {
                    // No swatch: these aren't on the chart, so there is no key
                    // for them to be the key to.
                    ForEach(offChart) { one in
                        row(one, slot: nil)
                    }
                }
            }

            // Only offered where it changes something. Below the comfortable
            // count every series is drawn anyway, and a toggle that does
            // nothing is worse than no toggle.
            if let binding = showsAllSeries,
               series.count > MetricPalette.comfortableSeriesCount {
                Toggle(isOn: binding) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Show every signal in the graph").font(.caption)
                        Text("\(series.count) signals is past what \(MetricPalette.hueCount) distinguishable colours can carry, so only the ones away from your baseline are drawn.")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ForEach(missing, id: \.self) { metric in
                missingRow(metric)
            }
        }
    }

    /// `slot` is the hue the chart gave this series, or nil when the chart
    /// isn't drawing it — in which case the row is dimmed and carries no
    /// swatch, because there is no line for it to be the key to.
    private func row(_ one: NormalizedSeries, slot: Int?) -> some View {
        let contribution = contribution(for: one.metric)
        return Button {
            onSelect?(one.metric)
        } label: {
            HStack(spacing: 8) {
                swatch(slot: slot)
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

    /// A short solid stroke in the hue the chart assigned, so the legend and the
    /// chart are unambiguously the same key. Hollow where the series isn't
    /// drawn.
    private func swatch(slot: Int?) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 5))
            path.addLine(to: CGPoint(x: 18, y: 5))
        }
        .stroke(slot.map { Theme.paletteColour(slot: $0) } ?? Color.secondary.opacity(0.25),
                style: StrokeStyle(lineWidth: 2))
        .frame(width: 18, height: 10)
    }

    private func missingRow(_ metric: MetricType) -> some View {
        HStack(spacing: 8) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 5))
                path.addLine(to: CGPoint(x: 18, y: 5))
            }
            // Hollow rather than dashed. Dash now means "inferred, not
            // measured" everywhere in the app, and a metric with no data at all
            // has nothing inferred either.
            .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 2))
            .frame(width: 18, height: 10)
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
