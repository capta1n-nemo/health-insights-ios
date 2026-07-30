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

    /// The window actually on screen, mirrored from the scroll owner so the
    /// reference band clips against the same y-domain the axis is drawn from.
    /// `ScrollableMetricChart` hands `yDomain:` the *visible* range but hands
    /// `marks:` a plot range three windows wide, so the two must be tracked
    /// separately or the band would clip against the wrong one.
    @State private var visibleWindow: ClosedRange<Date>?

    /// The published normal range for this metric, where one exists — which it
    /// does for eight of thirty.
    private var reference: MetricReferenceRange? { breakdown.type.referenceRange }

    private func values(in range: ClosedRange<Date>) -> [Double] {
        plot(in: range).segments.flatMap { $0.points.map(\.value) }
    }

    /// The stripes to shade. Empty until the first `onVisibleRangeChange`, which
    /// `ScrollableMetricChart` fires on appear — so the band arrives the frame
    /// after the data, never before it.
    ///
    /// Nothing is shaded on a log axis. The band's edges are linear values and
    /// the stripe would be drawn at the wrong height — most of these metrics are
    /// `.fluctuatingRange` and so *do* offer the log toggle, which makes this a
    /// live case rather than a theoretical one.
    private var referenceBands: [MetricReferenceBand] {
        guard !logarithmic, let reference, let visibleWindow,
              let domain = MetricReferenceRange.chartDomain(
                  values: values(in: visibleWindow), reference: reference)
        else { return [] }
        return reference.bands(in: domain)
    }

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

    /// What one visible range draws: the measured runs, plus the inferred
    /// connectors between runs close enough to join dashed.
    private struct Plot {
        let segments: [Segment]
        let bridges: [Bridge]
    }

    /// A gap short enough to infer across. Two points and its own series id, so
    /// it draws as one dashed span and never merges with the measured line.
    private struct Bridge: Identifiable {
        let gap: GapBridge
        let source: String
        var id: String { "\(source)~\(gap.id)" }
        var ends: [Point] {
            [Point(date: gap.start, value: gap.startValue, source: source),
             Point(date: gap.end, value: gap.endValue, source: source)]
        }
    }

    /// Only what's on screen, plus a window either side, bucketed and split on
    /// gaps. Charting a decade of high-frequency readings mark-for-mark is what
    /// made this hang; bucketing also stops long ranges aliasing the way plain
    /// decimation did.
    ///
    /// The gap rule is `maxPlottableGap(bucket:)`, never `maxValidInterval`. The
    /// dates being compared here are *bucket starts*, and heart rate's
    /// thirty-minute sample rule against day-wide buckets breaks the line between
    /// every adjacent pair — which is what shattered this chart into loose dots
    /// at every zoom past three days.
    private func plot(in range: ClosedRange<Date>) -> Plot {
        let bucket = BucketSize.forWindow(window)
        var segments: [Segment] = []
        var bridges: [Bridge] = []
        for series in breakdown.restricted(to: range).sources {
            let name = series.displayName
            let runs = series.bucketed(by: bucket, for: breakdown.type)
                .segments(for: breakdown.type, bucket: bucket)
            for (index, run) in runs.enumerated() {
                segments.append(Segment(
                    id: "\(name)#\(index)",
                    points: run.map { Point(date: $0.date, value: $0.value, source: name) }))
            }
            bridges += SeriesBridging.bridges(across: runs, metric: breakdown.type,
                                              bucket: bucket, window: window)
                .map { Bridge(gap: $0, source: name) }
        }
        return Plot(segments: segments, bridges: bridges)
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
                plot(in: range).segments.isEmpty
            },
            yDomain: { range in
                // Bridge endpoints are real bucket values already present in the
                // segments, so bridging never widens the domain. A reference
                // band can, though — an edge you cannot see conveys nothing —
                // and `chartDomain` returns the plain padded domain untouched
                // for the twenty-two metrics that have no band.
                if let reference, !logarithmic {
                    return MetricReferenceRange.chartDomain(values: values(in: range),
                                                            reference: reference)
                }
                return paddedYDomain(values(in: range), logarithmic: logarithmic)
            },
            onVisibleRangeChange: { range in
                visibleWindow = range
                onVisibleRangeChange?(range)
            }
        ) { range in
            allMarks(in: range)
        }
        .chartForegroundStyleScale(domain: domain, range: self.range)
    }

    /// Everything one visible range draws. Inferred content first, so the
    /// measured lines sit on top of it — the order `ScoreHistoryChart` uses too.
    @ChartContentBuilder
    private func allMarks(in range: ClosedRange<Date>) -> some ChartContent {
        let plot = plot(in: range)
        bandMarks(across: range)
        bridgeMarks(plot.bridges)
        seriesMarks(plot.segments)
    }

    /// The published range shaded behind the readings.
    ///
    /// Explicit `-> some ChartContent`, and a `ForEach` rather than an `if`: a
    /// `RectangleMark` behind a conditional is exactly the shape that resolves
    /// to `Chart3DContent` on this SDK and silently drops `.foregroundStyle`. An
    /// empty `referenceBands` draws nothing, which is what a metric with no
    /// published range wants.
    ///
    /// Lighter than the blood-pressure screen's 0.10, because that chart stacks
    /// five thin stripes and this one draws at most three — the middle of which
    /// can fill most of the plot. Both sit under the 0.18 the score rules use, so
    /// a data line is never in doubt against the fill.
    @ChartContentBuilder
    private func bandMarks(across range: ClosedRange<Date>) -> some ChartContent {
        ForEach(referenceBands) { band in
            RectangleMark(xStart: .value("From", range.lowerBound),
                          xEnd: .value("To", range.upperBound),
                          yStart: .value("Low", band.lower),
                          yEnd: .value("High", band.upper))
                .foregroundStyle((band.kind == .normal ? Theme.good : Theme.warn)
                    .opacity(band.kind == .normal ? 0.09 : 0.06))
        }
    }

    /// One line per contiguous run.
    @ChartContentBuilder
    private func seriesMarks(_ segments: [Segment]) -> some ChartContent {
        ForEach(segments) { segment in
            ForEach(segment.points) { point in
                marks(for: point, run: segment.id)
            }
        }
    }

    /// The dashed connectors. Same hue as the line they join — hue is identity —
    /// and dashed because nothing along them was measured.
    @ChartContentBuilder
    private func bridgeMarks(_ bridges: [Bridge]) -> some ChartContent {
        ForEach(bridges) { bridge in
            ForEach(bridge.ends) { end in
                LineMark(x: .value("Time", end.date),
                         y: .value(breakdown.type.unit, end.value),
                         series: .value("Run", bridge.id))
                    .foregroundStyle(by: .value("Source", end.source))
                    .lineStyle(Theme.projectedStroke)
                    .interpolationMethod(.linear)
            }
        }
    }

    /// Kept in its own function with an explicit return type: it pins the marks
    /// to 2D chart content and keeps each expression small enough to type-check.
    ///
    /// `series:` is what makes the gap split visible at all. Without it Swift
    /// Charts groups every `LineMark` sharing a `foregroundStyle(by:)` value into
    /// one line, so each source's runs get joined straight back together and the
    /// split draws nothing.
    @ChartContentBuilder
    private func marks(for p: Point, run: String) -> some ChartContent {
        LineMark(x: .value("Time", p.date), y: .value(breakdown.type.unit, p.value),
                 series: .value("Run", run))
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
