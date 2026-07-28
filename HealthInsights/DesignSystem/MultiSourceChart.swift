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
    let breakdown: MultiSourceBreakdown
    /// Only plot samples newer than this many seconds ago.
    var window: TimeInterval = 2 * 24 * 3600

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let source: String
    }

    private var points: [Point] {
        let cutoff = Date().addingTimeInterval(-window)
        return breakdown.sources.flatMap { series in
            series.samples
                .filter { $0.start >= cutoff }
                .map { Point(date: $0.start, value: $0.value, source: series.displayName) }
        }
    }

    private var domain: [String] { breakdown.sources.map(\.displayName) }
    private var range: [Color] { breakdown.sources.indices.map { Theme.sourceColor($0) } }

    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Time", p.date), y: .value(breakdown.type.unit, p.value))
                .foregroundStyle(by: .value("Source", p.source))
                .interpolationMethod(.catmullRom)
        }
        .chartForegroundStyleScale(domain: domain, range: range)
        .chartLegend(.hidden) // we render our own labelled breakdown below
        .frame(height: 170)
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
