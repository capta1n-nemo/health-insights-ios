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

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let source: String
    }

    private var allPoints: [Point] {
        breakdown.sources.flatMap { series in
            series.samples.map {
                Point(date: $0.start, value: $0.value, source: series.displayName)
            }
        }
    }

    /// Anchor the initial view on the newest reading rather than on "now", so a
    /// metric that last reported a while ago still opens showing its data.
    private var defaultStart: Date {
        let end = allPoints.map(\.date).max() ?? Date()
        return end.addingTimeInterval(-window)
    }

    private var visibleStart: Date { scrollX ?? defaultStart }
    private var visibleRange: ClosedRange<Date> {
        visibleStart...visibleStart.addingTimeInterval(window)
    }

    private var scrollBinding: Binding<Date> {
        Binding(get: { visibleStart }, set: { scrollX = $0 })
    }

    /// Points on screen right now — the Y-scale follows the pan so a zoomed-in
    /// window isn't flattened by outliers elsewhere in the history.
    private var points: [Point] {
        allPoints.filter { visibleRange.contains($0.date) }
    }

    private var domain: [String] { breakdown.sources.map(\.displayName) }
    private var range: [Color] { breakdown.sources.indices.map { Theme.sourceColor($0) } }

    private var values: [Double] { points.map(\.value) }
    /// Log axis is only meaningful (and mathematically valid) for positive data.
    private var useLog: Bool { logarithmic && !values.isEmpty && values.allSatisfy { $0 > 0 } }

    /// A padded Y-range so a single point or a flat line isn't glued to an edge
    /// and stays visible.
    private var yDomain: ClosedRange<Double>? {
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

    /// The nearest reading to the scrubbed instant, per source, so the callout
    /// answers "what did each device say around here?".
    private func readings(at date: Date) -> [(source: String, sample: HealthMetricSample)] {
        breakdown.sources.compactMap { series in
            guard let nearest = series.samples.min(by: {
                abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date))
            }) else { return nil }
            // Ignore a source whose closest reading is far outside the window the
            // user is pointing at — better to omit it than to imply it was there.
            guard abs(nearest.start.timeIntervalSince(date)) <= window / 8 else { return nil }
            return (series.displayName, nearest)
        }
    }

    var body: some View {
        Chart {
            ForEach(allPoints) { p in
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
            if let selected {
                RuleMark(x: .value("Selected", selected))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fitToChart, y: .disabled)) {
                        callout(at: selected)
                    }
            }
        }
        .chartForegroundStyleScale(domain: domain, range: range)
        .modifier(YScaleModifier(domain: yDomain, log: useLog))
        .chartLegend(.hidden) // we render our own labelled breakdown below
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: window)
        .chartScrollPosition(x: scrollBinding)
        .chartXSelection(value: $selected)
        .frame(height: 170)
        .overlay {
            if points.isEmpty {
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

    @ViewBuilder private func callout(at date: Date) -> some View {
        let rows = readings(at: date)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(rows, id: \.source) { row in
                    HStack(spacing: 6) {
                        if let index = domain.firstIndex(of: row.source) {
                            Circle().fill(Theme.sourceColor(index)).frame(width: 7, height: 7)
                        }
                        Text("\(formatMetric(row.sample.value, breakdown.type)) \(breakdown.type.unit)")
                            .monospacedDigit()
                        Text(row.source).foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                }
                if let when = rows.map(\.sample.start).max() {
                    Text(when.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
            .shadow(radius: 2, y: 1)
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
