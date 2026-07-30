import SwiftUI
import Charts
import InsightKit

extension Theme {
    /// Distinct, colour-blind-friendly line colours assigned per data source.
    static let sourcePalette: [Color] = [
        Color(red: 0.90, green: 0.29, blue: 0.35),   // accent red
        Color(red: 0.20, green: 0.55, blue: 0.92),   // blue
        Color(red: 0.20, green: 0.72, blue: 0.51),   // green
        Color(red: 0.98, green: 0.68, blue: 0.20),   // amber
        Color(red: 0.55, green: 0.35, blue: 0.86)    // purple
    ]
    static func sourceColor(_ index: Int) -> Color {
        sourcePalette[index % sourcePalette.count]
    }
}

/// Formats a metric value for compact display.
///
/// Forwards to `MetricValueFormatter` so every call site picks up the
/// metric-aware precision — notably height, which is stored in metres and used
/// to round to a bare "2".
func formatMetric(_ value: Double, _ type: MetricType) -> String {
    MetricValueFormatter.string(value, type)
}

/// Whether `formatMetric` already rendered the unit, so callers don't append a
/// second one (height comes back as "185 cm", not "185").
func formatMetricIncludesUnit(_ type: MetricType) -> Bool {
    MetricValueFormatter.includesUnit(type)
}

/// Overlays every source of one metric on a single chart — one coloured line
/// per device (Apple Watch, Oura, …) — so differences are visible at a glance.
/// This is the shared component every card uses.
struct MultiSourceChart: View {
    /// Every sample the metric has — the chart scrolls through it rather than
    /// being handed a pre-trimmed slice, which is what makes panning possible.
    let breakdown: MultiSourceBreakdown
    /// How much time fills the chart's width. The timeframe picker sets this, so
    /// it behaves as a zoom level and panning travels through history.
    var window: TimeInterval = 2 * 24 * 3600
    /// Use a logarithmic Y-axis (only honoured when all values are positive) —
    /// helps when sources differ by a wide margin.
    var logarithmic: Bool = false
    /// Reports the window currently on screen, so read-outs beneath the chart can
    /// describe what is actually visible after a pan.
    var onVisibleRangeChange: ((ClosedRange<Date>) -> Void)?
    /// Lets an owner observe the scrub position, so the breakdown beneath can
    /// follow the crosshair. Falls back to private state when not supplied.
    var selection: Binding<Date?>?

    /// The instant being scrubbed over, when no owner supplied a binding.
    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }

    private struct Point: Identifiable {
        /// Derived, not a fresh UUID: a new identity every render made SwiftUI
        /// rebuild every mark on each redraw.
        var id: String { "\(source)@\(date.timeIntervalSince1970)" }
        let date: Date
        let value: Double
        let source: String
    }

    /// The extent of the whole history, which fixes how far the chart can
    /// scroll even though only the visible slice is plotted.
    private var fullDomain: ClosedRange<Date>? { breakdown.dateSpan }

    /// One unbroken run of one source's readings. Flat rather than nested
    /// per-source, because a ForEach over sources containing a ForEach over
    /// segments containing a ForEach over points exceeded what the type checker
    /// would accept inside a chart builder.
    private struct Segment: Identifiable {
        let id: String
        let points: [Point]
    }

    /// Only what's on screen, plus a window either side, bucketed and split on
    /// gaps. Charting a decade of high-frequency readings mark-for-mark is what
    /// made this hang; bucketing also stops long ranges aliasing the way plain
    /// decimation did.
    private func plotted(in range: ClosedRange<Date>) -> [Segment] {
        let bucket = BucketSize.forWindow(window)
        let maxGap = breakdown.type.maxValidInterval
        var out: [Segment] = []
        for series in breakdown.restricted(to: range).sources {
            let name = series.displayName
            let points = series.bucketed(by: bucket, for: breakdown.type)
                .map { Point(date: $0.date, value: $0.value, source: name) }
            for (index, run) in split(points, maxGap: maxGap).enumerated() {
                out.append(Segment(id: "\(name)#\(index)", points: run))
            }
        }
        return out
    }

    /// Breaks a run wherever the gap exceeds `maxGap`, so no line bridges a
    /// period when nothing was measured.
    private func split(_ points: [Point], maxGap: TimeInterval) -> [[Point]] {
        guard !points.isEmpty else { return [] }
        var out: [[Point]] = []
        var current: [Point] = [points[0]]
        for point in points.dropFirst() {
            if let previous = current.last,
               point.date.timeIntervalSince(previous.date) > maxGap {
                out.append(current)
                current = [point]
            } else {
                current.append(point)
            }
        }
        out.append(current)
        return out
    }

    private var domain: [String] { breakdown.sources.map(\.displayName) }
    private var range: [Color] { breakdown.sources.indices.map { Theme.sourceColor($0) } }

    /// One line of the scrub callout. A named type rather than a tuple, because
    /// ForEach needs an id key path and Swift has none into tuple elements.
    private struct Callout: Identifiable {
        let source: String
        let value: Double
        let date: Date
        var id: String { source }
    }

    /// The nearest reading to the scrubbed instant, per source, so the callout
    /// answers "what did each device say around here?".
    private func readings(at date: Date) -> [Callout] {
        breakdown.sources.compactMap { series in
            guard let nearest = series.samples.min(by: {
                abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date))
            }) else { return nil }
            // Ignore a source whose closest reading is far outside the window the
            // user is pointing at — better to omit it than to imply it was there.
            guard abs(nearest.start.timeIntervalSince(date)) <= window / 8 else { return nil }
            return Callout(source: series.displayName, value: nearest.value, date: nearest.start)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
        }
    }

    /// What the finger is currently over. Rendered above the chart rather than as
    /// a mark annotation: on the iOS 26 SDK the RuleMark chain resolves to
    /// Chart3DContent, which has neither `lineStyle` nor `annotation`.
    @ViewBuilder private var readout: some View {
        if let selected, case let rows = readings(at: selected), !rows.isEmpty {
            HStack(spacing: 10) {
                ForEach(rows) { row in
                    HStack(spacing: 5) {
                        if let index = domain.firstIndex(of: row.source) {
                            Circle().fill(Theme.sourceColor(index)).frame(width: 7, height: 7)
                        }
                        Text("\(formatMetric(row.value, breakdown.type))")
                            .monospacedDigit()
                    }
                }
                if let when = rows.map(\.date).max() {
                    Text(when.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .font(.caption2)
        } else {
            // Reserve the row so the chart doesn't jump as scrubbing starts.
            Text(" ").font(.caption2)
        }
    }

    private var chart: some View {
        ScrollableMetricChart(
            dataSpan: fullDomain,
            window: window,
            selection: selectionBinding,
            logarithmic: logarithmic,
            isEmpty: { range in
                plotted(in: range).allSatisfy { $0.points.isEmpty }
            },
            yDomain: { range in
                paddedYDomain(plotted(in: range).flatMap { $0.points.map(\.value) },
                              logarithmic: logarithmic)
            },
            onVisibleRangeChange: onVisibleRangeChange
        ) { range in
            seriesMarks(plotted(in: range))
        }
        .chartForegroundStyleScale(domain: domain, range: self.range)
    }

    /// One line per contiguous run.
    @ChartContentBuilder
    private func seriesMarks(_ segments: [Segment]) -> some ChartContent {
        ForEach(segments) { segment in
            ForEach(segment.points) { point in
                marks(for: point)
            }
        }
    }

    /// Kept in its own function with an explicit return type: it pins the marks
    /// to 2D chart content and keeps each expression small enough to type-check.
    @ChartContentBuilder
    private func marks(for p: Point) -> some ChartContent {
        LineMark(x: .value("Time", p.date), y: .value(breakdown.type.unit, p.value))
            .foregroundStyle(by: .value("Source", p.source))
            // Straight segments between readings: a curve invents values between
            // samples that were never measured.
            .interpolationMethod(.linear)
        // A point per reading so single-reading series still render.
        PointMark(x: .value("Time", p.date), y: .value(breakdown.type.unit, p.value))
            .foregroundStyle(by: .value("Source", p.source))
            .symbolSize(26)
    }
}
