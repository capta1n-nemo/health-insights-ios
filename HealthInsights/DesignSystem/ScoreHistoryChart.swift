import SwiftUI
import Charts
import InsightKit

/// An insight's own score over time — the chart the detail screen should have
/// opened with all along.
///
/// Until now nothing recorded a score, so a card could tell you today's readiness
/// but never whether it was better or worse than last month. The history is part
/// replayed from raw samples and part stored (see `ScoreHistory`), which is why
/// this takes plain `ScorePoint`s and doesn't care where they came from.
struct ScoreHistoryChart: View {
    let points: [ScorePoint]
    /// How much time fills the width — the timeframe picker's zoom level.
    var window: TimeInterval = 30 * 24 * 3600
    var selection: Binding<Date?>?

    @State private var localSelection: Date?

    private var selectionBinding: Binding<Date?> { selection ?? $localSelection }
    private var selected: Date? { selectionBinding.wrappedValue }

    private var span: ClosedRange<Date>? {
        guard let first = points.first?.date, let last = points.last?.date,
              first <= last else { return nil }
        return first...last
    }

    /// The point nearest the scrubbed instant, ignoring anything too far away to
    /// be what the finger is pointing at.
    private func point(at date: Date) -> ScorePoint? {
        guard let nearest = points.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }), abs(nearest.date.timeIntervalSince(date)) <= window / 8 else { return nil }
        return nearest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            chart
        }
    }

    /// Rendered above the chart, not as a mark annotation: on this SDK a
    /// `RuleMark` chain resolves to `Chart3DContent`, which has no `annotation`.
    @ViewBuilder private var readout: some View {
        if let selected, let hit = point(at: selected) {
            HStack(spacing: 8) {
                Circle().fill(Theme.color(forScore: hit.score)).frame(width: 7, height: 7)
                Text("\(Int(hit.score.rounded()))")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                Text(hit.date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.tertiary)
                Text("· \(hit.contributorCount) signal\(hit.contributorCount == 1 ? "" : "s")")
                    .foregroundStyle(.tertiary)
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
            emptyMessage: "No score in this window",
            isEmpty: { range in
                !points.contains { range.contains($0.date) }
            },
            // Fixed 0–100 rather than fitted to the data: a score is a score, and
            // rescaling it per window would make a two-point wobble look dramatic.
            yDomain: { _ in 0...100 }
        ) { range in
            scoreMarks(points.filter { range.contains($0.date) })
        }
    }

    /// Explicit `some ChartContent` return type, as every mark builder in this
    /// app must have: without it the chain can resolve to 3D chart content on
    /// this SDK and silently drop `.lineStyle` and `.foregroundStyle`.
    @ChartContentBuilder
    private func scoreMarks(_ visible: [ScorePoint]) -> some ChartContent {
        bandMarks
        ForEach(visible) { point in
            marks(for: point)
        }
    }

    /// The band lines readiness itself uses, so "80" on the chart means the same
    /// thing as "Primed" on the card.
    @ChartContentBuilder
    private var bandMarks: some ChartContent {
        ForEach([50.0, 70.0], id: \.self) { level in
            RuleMark(y: .value("Band", level))
                .foregroundStyle(Color.secondary.opacity(0.18))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    @ChartContentBuilder
    private func marks(for p: ScorePoint) -> some ChartContent {
        LineMark(x: .value("Day", p.date), y: .value("Score", p.score))
            .foregroundStyle(Theme.accent)
            // Straight segments: a curve would invent scores for days that were
            // never computed.
            .interpolationMethod(.linear)
        PointMark(x: .value("Day", p.date), y: .value("Score", p.score))
            // Coloured by the score's own band, so a bad run reads as a bad run
            // even before the axis is consulted.
            .foregroundStyle(Theme.color(forScore: p.score))
            .symbolSize(26)
    }
}
