import SwiftUI
import Charts
import InsightKit

/// Cumulative cardiovascular load from the substance log, as a decaying daily
/// series — the "first-class trend" the roadmap asked for.
///
/// The card has always carried a fortnight figure, but that was a box-car: an
/// event counted in full for fourteen days and then vanished overnight. As one
/// number it was serviceable; as a series it would have drawn a staircase of the
/// calendar rather than of the body. `SubstanceLoad` decays it instead, and this
/// draws that.
struct SubstanceLoadChart: View {
    let points: [SubstanceLoadPoint]
    /// How much time fills the width.
    var window: TimeInterval = 90 * 24 * 3600
    /// Draw the fitted line through the load. Dashed, because a fit is inferred
    /// — the one meaning a dash is allowed to carry in this app.
    var showsTrend: Bool = true
    var selection: Binding<Date?>?

    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }
    private var tint: Color { Theme.insightTint(.substanceImpact) }

    private var span: ClosedRange<Date>? {
        guard let first = points.first?.date, let last = points.last?.date,
              first <= last else { return nil }
        return first...last
    }

    private func point(at date: Date) -> SubstanceLoadPoint? {
        guard let nearest = points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }), abs(nearest.date.timeIntervalSince(date)) <= window / 8 else { return nil }
        return nearest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
            caption
        }
    }

    /// Rendered above the chart, not as a mark annotation: on this SDK a
    /// `RuleMark` chain resolves to `Chart3DContent`, which has no `annotation`.
    @ViewBuilder private var readout: some View {
        if let selected, let hit = point(at: selected) {
            HStack(spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text("\(Int(hit.load.rounded()))")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                Text(hit.band).foregroundStyle(.secondary)
                Text(hit.date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.tertiary)
                if hit.eventCount > 0 {
                    Text("· \(hit.eventCount) logged")
                        .foregroundStyle(.tertiary)
                }
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
            emptyMessage: "No logs in this window",
            isEmpty: { range in !points.contains { range.contains($0.date) } },
            // Fixed 0–100. A load scale must not auto-zoom, or a quiet month
            // rescales into looking like a heavy one.
            yDomain: { _ in 0...100 }
        ) { range in
            loadMarks(points.filter { range.contains($0.date) })
        }
    }

    private var caption: some View {
        Text("From your log, not measured — how much cardiovascular load your logged use is still carrying, decaying with a \(Int(SubstanceLoad.halfLifeDays))-day half-life.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    /// Explicit `some ChartContent`, as every mark builder in this app must
    /// have: without it the chain can resolve to 3D chart content on this SDK
    /// and silently drop `.lineStyle` and `.foregroundStyle`.
    @ChartContentBuilder
    private func loadMarks(_ visible: [SubstanceLoadPoint]) -> some ChartContent {
        bandMarks
        trendMarks(visible)
        ForEach(visible) { point in
            marks(for: point)
        }
    }

    @ChartContentBuilder
    private func marks(for p: SubstanceLoadPoint) -> some ChartContent {
        AreaMark(x: .value("Day", p.date), y: .value("Load", p.load))
            .foregroundStyle(tint.opacity(0.15))
            .interpolationMethod(.linear)
        LineMark(x: .value("Day", p.date), y: .value("Load", p.load))
            .foregroundStyle(tint)
            // Straight segments. The series is dense by construction — load is
            // defined on a day with no logs — so there is no gap to bridge and
            // no curve worth inventing.
            .interpolationMethod(.linear)
        // A day the user actually logged something, marked so the peaks are
        // attributable rather than just tall.
        if p.eventCount > 0 {
            PointMark(x: .value("Day", p.date), y: .value("Load", p.load))
                .foregroundStyle(tint)
                .symbolSize(28)
        }
    }

    /// The same band lines the card's words use, so "50" on the chart means the
    /// same thing as "considerable" in the sentence above it.
    @ChartContentBuilder
    private var bandMarks: some ChartContent {
        ForEach([20.0, 50.0, 80.0], id: \.self) { level in
            RuleMark(y: .value("Band", level))
                .foregroundStyle(Color.secondary.opacity(0.18))
                .lineStyle(Theme.referenceStroke)
        }
    }

    private struct TrendPoint: Identifiable {
        let id: String
        let date: Date
        let load: Double
    }

    /// The fitted line, dashed because it is inferred.
    @ChartContentBuilder
    private func trendMarks(_ visible: [SubstanceLoadPoint]) -> some ChartContent {
        ForEach(trendLine(visible)) { point in
            LineMark(x: .value("Day", point.date), y: .value("Load", point.load),
                     series: .value("Band", "fit"))
                .foregroundStyle(tint.opacity(0.6))
                .lineStyle(Theme.projectedStroke)
                .interpolationMethod(.linear)
        }
    }

    private func trendLine(_ visible: [SubstanceLoadPoint]) -> [TrendPoint] {
        guard showsTrend, let trend = points.loadTrend, trend.isMeaningful,
              let first = visible.first?.date, let last = visible.last?.date,
              first < last else { return [] }
        return [first, last].enumerated().map { index, date in
            TrendPoint(id: "fit-\(index)", date: date,
                       load: Swift.max(0, Swift.min(100, trend.value(at: date))))
        }
    }
}
