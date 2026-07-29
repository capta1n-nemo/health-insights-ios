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
func formatMetric(_ value: Double, _ type: MetricType) -> String {
    switch type {
    case .bodyMass, .leanBodyMass, .sleepDurationHours, .bodyTemperature,
         .skinTemperatureDeviation, .dayStrain:
        return String(format: "%.1f", value)
    case .bodyFatPercentage, .oxygenSaturation:
        return String(format: "%.0f%%", value)
    default:
        return "\(Int(value.rounded()))"
    }
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

    /// Leading edge of the visible window; nil until the user pans.
    @State private var scrollX: Date?
    /// The instant the user is scrubbing over, nil when not touching the chart.
    @State private var selected: Date?

    /// Most readings a single source contributes to one screen. Beyond this the
    /// extra marks are invisible at chart resolution but still cost layout time.
    private static let maxPointsPerSource = 300

    private struct Point: Identifiable {
        /// Derived, not a fresh UUID: a new identity every render made SwiftUI
        /// rebuild every mark on each redraw.
        var id: String { "\(source)@\(date.timeIntervalSince1970)" }
        let date: Date
        let value: Double
        let source: String
    }

    /// The extent of the whole history, which fixes how far the chart can scroll
    /// even though only the visible slice is plotted.
    private var fullDomain: ClosedRange<Date> {
        let starts = breakdown.sources.compactMap(\.samples.first?.start)
        let ends = breakdown.sources.compactMap(\.samples.last?.start)
        guard let first = starts.min(), let last = ends.max(), first < last else {
            let now = Date()
            return now.addingTimeInterval(-window)...now
        }
        return first...last
    }

    /// Anchor the initial view on the newest reading rather than on "now", so a
    /// metric that last reported a while ago still opens showing its data.
    private var defaultStart: Date {
        fullDomain.upperBound.addingTimeInterval(-window)
    }

    private var visibleStart: Date { scrollX ?? defaultStart }
    private var visibleRange: ClosedRange<Date> {
        visibleStart...visibleStart.addingTimeInterval(window)
    }

    private var scrollBinding: Binding<Date> {
        Binding(get: { visibleStart }, set: { scrollX = $0 })
    }

    /// Only what's on screen, plus a window either side so a pan doesn't reveal
    /// an empty chart before the next redraw, thinned for plotting. Charting a
    /// decade of high-frequency readings mark-for-mark is what made this hang.
    private var visibleBreakdown: MultiSourceBreakdown {
        // `...` must not start the continuation line: Swift then parses it as a
        // standalone prefix PartialRangeThrough, leaving `padded` typed as a
        // bare Date and failing to match restricted(to: ClosedRange<Date>).
        let lower = visibleStart.addingTimeInterval(-window)
        let upper = visibleStart.addingTimeInterval(window * 2)
        return breakdown.restricted(to: lower...upper)
            .downsampled(to: Self.maxPointsPerSource * 3)
    }

    /// Points on screen right now — the Y-scale follows the pan so a zoomed-in
    /// window isn't flattened by outliers elsewhere in the history.
    private var points: [Point] {
        visibleBreakdown.restricted(to: visibleRange)
            .downsampled(to: Self.maxPointsPerSource)
            .sources
            .flatMap { series in
                series.samples.map {
                    Point(date: $0.start, value: $0.value, source: series.displayName)
                }
            }
    }

    private var domain: [String] { breakdown.sources.map(\.displayName) }
    private var range: [Color] { breakdown.sources.indices.map { Theme.sourceColor($0) } }

    /// Log axis is only meaningful (and mathematically valid) for positive data.
    private func useLog(for plotted: [Point]) -> Bool {
        logarithmic && !plotted.isEmpty && plotted.allSatisfy { $0.value > 0 }
    }

    /// A padded Y-range so a single point or a flat line isn't glued to an edge
    /// and stays visible.
    private func yDomain(for plotted: [Point]) -> ClosedRange<Double>? {
        let values = plotted.map(\.value)
        let useLog = useLog(for: plotted)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        if lo == hi {
            let pad = Swift.max(abs(lo) * 0.05, 1)
            let lower = useLog ? Swift.max(lo * 0.9, 0.0001) : lo - pad
            return lower...(hi + pad)
        }
        let span = hi - lo
        let lower = useLog ? Swift.max(lo * 0.7, 0.0001) : lo - span * 0.1
        return lower...(hi + span * 0.1)
    }

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
        // Computed once here rather than per access: each of the marks, the
        // Y-scale and the empty check would otherwise re-slice the history.
        let plotted = points
        return Chart {
            ForEach(plotted) { p in
                LineMark(x: .value("Time", p.date), y: .value(breakdown.type.unit, p.value))
                    .foregroundStyle(by: .value("Source", p.source))
                    // Straight segments between readings: a curve invents values
                    // between samples that were never measured.
                    .interpolationMethod(.linear)
                // A point per sample so single-reading series still render visibly.
                PointMark(x: .value("Time", p.date), y: .value(breakdown.type.unit, p.value))
                    .foregroundStyle(by: .value("Source", p.source))
                    .symbolSize(26)
            }
        }
        .chartForegroundStyleScale(domain: domain, range: range)
        .modifier(YScaleModifier(domain: yDomain(for: plotted), log: useLog(for: plotted)))
        .chartLegend(.hidden) // we render our own labelled breakdown below
        .chartScrollableAxes(.horizontal)
        // The full extent stays scrollable even though only the visible slice
        // is plotted.
        .chartXScale(domain: fullDomain)
        .chartXVisibleDomain(length: window)
        .chartScrollPosition(x: scrollBinding)
        .chartXSelection(value: $selected)
        .frame(height: 170)
        .overlay {
            if plotted.isEmpty {
                Text("No readings in this window")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear { onVisibleRangeChange?(visibleRange) }
        .onChange(of: scrollX) { onVisibleRangeChange?(visibleRange) }
        .onChange(of: window) {
            // A new zoom level re-anchors on the newest reading.
            scrollX = nil
            onVisibleRangeChange?(visibleRange)
        }
    }
}

/// Applies the (optional) padded Y domain, in linear or logarithmic mode.
private struct YScaleModifier: ViewModifier {
    let domain: ClosedRange<Double>?
    let log: Bool

    func body(content: Content) -> some View {
        if let domain {
            if log {
                content.chartYScale(domain: domain, type: .log)
            } else {
                content.chartYScale(domain: domain)
            }
        } else {
            content
        }
    }
}

/// "Apple Watch: 66 · Oura: 60 · Average: 63" — the honest per-source read-out
/// that sits under the chart on every card.
struct SourceBreakdown: View {
    let breakdown: MultiSourceBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(breakdown.hasMultipleSources ? "What each source says" : "Latest reading")
                .font(.headline)

            ForEach(Array(breakdown.sources.enumerated()), id: \.element.id) { index, series in
                HStack(spacing: 9) {
                    Circle().fill(Theme.sourceColor(index)).frame(width: 9, height: 9)
                    Text(series.displayName)
                    Spacer()
                    if let latest = series.latest {
                        Text("\(formatMetric(latest, breakdown.type)) \(breakdown.type.unit)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .font(.subheadline)
            }

            if breakdown.hasMultipleSources, let avg = breakdown.consensusLatest {
                Divider()
                HStack {
                    Text("Average").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(formatMetric(avg, breakdown.type)) \(breakdown.type.unit)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                if let spread = breakdown.latestSpread, spread > 0 {
                    Text("Your sources differ by \(formatMetric(spread, breakdown.type)) \(breakdown.type.unit) right now.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
