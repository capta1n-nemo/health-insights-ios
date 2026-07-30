import SwiftUI
import Charts
import InsightKit

/// Heart age and fitness age against your real age, over time.
///
/// The card used to show three numbers and a dial — where you are, and nothing
/// about which way it's going. Direction is the actionable part: a heart age of
/// 46 reads one way after a year at 50 and the opposite way after a year at 42.
///
/// Your chronological age is drawn as the reference because it is the only line
/// with a guaranteed slope — one year per year. A heart age climbing more slowly
/// than that is closing the gap even while its own number rises, which no chart
/// of the age alone can show.
struct AgeHistoryChart: View {
    let points: [AgePoint]
    var window: TimeInterval = 365 * 24 * 3600
    var selection: Binding<Date?>?

    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }

    private var span: ClosedRange<Date>? {
        guard let first = points.first?.date, let last = points.last?.date,
              first <= last else { return nil }
        return first...last
    }

    private func point(at date: Date) -> AgePoint? {
        guard let nearest = points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }), abs(nearest.date.timeIntervalSince(date)) <= window / 8 else { return nil }
        return nearest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
            legend
        }
    }

    /// Above the chart rather than as a mark annotation — on this SDK a
    /// `RuleMark` chain resolves to `Chart3DContent`, which has no `annotation`.
    @ViewBuilder private var readout: some View {
        if let selected = selectionBinding.wrappedValue, let hit = point(at: selected) {
            HStack(spacing: 10) {
                Text(hit.date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.tertiary)
                value("You", hit.chronological, Self.chronologicalTint)
                if let heart = hit.heart { value("Heart", heart, Theme.paletteColour(slot: 0)) }
                if let fitness = hit.fitness { value("Fitness", fitness, Theme.paletteColour(slot: 2)) }
                Spacer()
            }
            .font(.caption2)
        } else {
            Text(" ").font(.caption2)
        }
    }

    private func value(_ label: String, _ years: Double, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text("\(label) \(Int(years.rounded()))")
                .monospacedDigit()
        }
    }

    private var chart: some View {
        ScrollableMetricChart(
            dataSpan: span,
            window: window,
            selection: selectionBinding,
            height: 170,
            emptyMessage: "No ages computed in this window",
            isEmpty: { range in !points.contains { range.contains($0.date) } },
            // Padded around the ages actually present: a fixed 0–100 domain
            // would compress a decade of movement into a few pixels.
            yDomain: { range in Self.domain(points.filter { range.contains($0.date) }) }
        ) { range in
            ageMarks(points.filter { range.contains($0.date) })
        }
    }

    /// Every age in view plus three years of headroom, so a line never runs
    /// along the edge of the plot.
    static func domain(_ visible: [AgePoint]) -> ClosedRange<Double>? {
        var values: [Double] = []
        for point in visible {
            values.append(point.chronological)
            if let heart = point.heart { values.append(heart) }
            if let fitness = point.fitness { values.append(fitness) }
        }
        guard let low = values.min(), let high = values.max() else { return nil }
        // A hard floor of one year's width, or a perfectly flat history would
        // produce a degenerate domain.
        let pad = Swift.max(3, (high - low) * 0.15)
        return (low - pad)...(high + pad)
    }

    static let chronologicalTint = Color.secondary

    /// Explicit `some ChartContent`, as every mark builder in this app must
    /// have: without it the chain resolves to 3D chart content on this SDK and
    /// silently drops `.lineStyle` and `.foregroundStyle`.
    @ChartContentBuilder
    private func ageMarks(_ visible: [AgePoint]) -> some ChartContent {
        // Your real age first, underneath, so the two computed ages read
        // against it rather than the other way round.
        ForEach(visible) { point in
            LineMark(x: .value("Day", point.date),
                     y: .value("Age", point.chronological),
                     series: .value("Series", "You"))
                .foregroundStyle(Self.chronologicalTint.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.linear)
        }
        ForEach(visible.filter { $0.heart != nil }) { point in
            LineMark(x: .value("Day", point.date),
                     y: .value("Age", point.heart ?? 0),
                     series: .value("Series", "Heart"))
                .foregroundStyle(Theme.paletteColour(slot: 0))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.linear)
        }
        ForEach(visible.filter { $0.fitness != nil }) { point in
            LineMark(x: .value("Day", point.date),
                     y: .value("Age", point.fitness ?? 0),
                     series: .value("Series", "Fitness"))
                .foregroundStyle(Theme.paletteColour(slot: 2))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.linear)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendKey("Your age", Self.chronologicalTint)
            if points.contains(where: { $0.heart != nil }) {
                legendKey("Heart age", Theme.paletteColour(slot: 0))
            }
            if points.contains(where: { $0.fitness != nil }) {
                legendKey("Fitness age", Theme.paletteColour(slot: 2))
            }
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendKey(_ label: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(tint).frame(width: 12, height: 3)
            Text(label)
        }
    }
}
