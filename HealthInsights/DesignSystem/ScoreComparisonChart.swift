import SwiftUI
import Charts
import InsightKit

/// Several insight scores on one chart.
///
/// Unlike the metric overlay, this needs no normalising and no palette
/// gymnastics: every score is already 0–100, so they are directly comparable,
/// and there are only ever a handful. Plotting them together answers the
/// question the Today tab can't — whether your readiness, sleep and fitness have
/// been moving as one thing or pulling apart.
struct ScoreComparisonChart: View {
    struct Series: Identifiable {
        let id: InsightID
        let title: String
        let points: [ScorePoint]
        let tint: Color
    }

    let series: [Series]
    var window: TimeInterval = 90 * 24 * 3600
    @State private var selection: Date?

    private var span: ClosedRange<Date>? {
        let dates = series.flatMap { $0.points.map(\.date) }
        guard let first = dates.min(), let last = dates.max(), first <= last else { return nil }
        return first...last
    }

    private struct Point: Identifiable {
        var id: String { "\(insight.rawValue)@\(date.timeIntervalSince1970)" }
        let insight: InsightID
        let title: String
        let date: Date
        let score: Double
        let tint: Color
    }

    private func plotted(in range: ClosedRange<Date>) -> [Point] {
        series.flatMap { one in
            one.points.filter { range.contains($0.date) }
                .map { Point(insight: one.id, title: one.title, date: $0.date,
                             score: $0.score, tint: one.tint) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            readout
            ScrollableMetricChart(
                dataSpan: span,
                window: window,
                selection: $selection,
                height: 170,
                emptyMessage: "No scores in this window",
                isEmpty: { range in plotted(in: range).isEmpty },
                yDomain: { _ in 0...100 }
            ) { range in
                marks(plotted(in: range))
            }
            legend
        }
    }

    @ViewBuilder private var readout: some View {
        if let selection, case let rows = nearest(to: selection), !rows.isEmpty {
            HStack(spacing: 10) {
                ForEach(rows) { row in
                    HStack(spacing: 5) {
                        Circle().fill(row.tint).frame(width: 7, height: 7)
                        Text("\(Int(row.score.rounded()))").monospacedDigit()
                    }
                }
                Text(selection.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .font(.caption2)
        } else {
            Text(" ").font(.caption2)
        }
    }

    private func nearest(to date: Date) -> [Point] {
        series.compactMap { one in
            guard let hit = one.points.min(by: {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }), abs(hit.date.timeIntervalSince(date)) <= window / 8 else { return nil }
            return Point(insight: one.id, title: one.title, date: hit.date,
                         score: hit.score, tint: one.tint)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(series) { one in
                HStack(spacing: 5) {
                    Circle().fill(one.tint).frame(width: 8, height: 8)
                    Text(one.title).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    /// Explicit `some ChartContent`, as every mark builder in this app must have.
    @ChartContentBuilder
    private func marks(_ points: [Point]) -> some ChartContent {
        bandMarks
        ForEach(points) { point in
            LineMark(x: .value("Day", point.date), y: .value("Score", point.score),
                     series: .value("Insight", point.title))
                .foregroundStyle(point.tint)
                .interpolationMethod(.linear)
        }
    }

    /// The same band lines `ScoreHistoryChart` draws.
    ///
    /// Without them 65 sat in a shaded context on one screen and on a bare plot
    /// on the other — the same number reading differently depending on which
    /// chart you happened to be looking at.
    @ChartContentBuilder
    private var bandMarks: some ChartContent {
        ForEach([50.0, 70.0], id: \.self) { level in
            RuleMark(y: .value("Band", level))
                .foregroundStyle(Color.secondary.opacity(0.18))
                .lineStyle(Theme.referenceStroke)
        }
    }
}
