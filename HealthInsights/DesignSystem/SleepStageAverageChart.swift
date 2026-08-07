import SwiftUI
import Charts
import InsightKit

/// **A typical night over the chosen timeframe, one bar per source.**
///
/// `NightSleepChart` draws *one* night. This draws the average of however many
/// the page's timeframe control has selected, in the same four stage colours and
/// the same lane order, so the two charts on the sleep card read as the same
/// picture at two zoom levels rather than as two unrelated diagrams.
///
/// ## Why the bars are per source and never pooled
///
/// The whole reason the night chart exists is that Oura and Apple Health
/// disagreed about a night by four hours and both were right about what they
/// saw. An average across sources would resolve that disagreement by fiat, and
/// resolving it is exactly what the card refuses to do. Each source gets a bar
/// and its own night count.
///
/// ## What the bar's length is, and is not
///
/// It is the mean over the nights **that source recorded**, not over the nights
/// in the window. A ring worn nine nights in thirty is not somebody sleeping two
/// hours a night, which is what the other denominator would draw. The count
/// beside each bar is what makes that readable rather than a footnote — a
/// three-night mean is drawn, and labelled as three nights.
///
/// A plain `Chart`, like `NightSleepChart`: the x axis is hours, not time, so
/// there is nothing to pan through and no date for a substance window to land
/// on.
struct SleepStageAverageChart: View {
    let averages: SleepStageAverages

    /// One drawn segment. Absent stages are emitted at zero rather than
    /// skipped — the stacked-offset rule from the chart skill — which costs an
    /// invisible mark and keeps every bar's segment order identical.
    private struct Segment: Identifiable {
        let source: String
        let stage: NightSleepDetail.Stage?
        let hours: Double
        var id: String { "\(source)-\(stage?.label ?? "window")" }
    }

    private var segments: [Segment] {
        averages.rows.flatMap { row -> [Segment] in
            guard row.hasStageDetail else {
                // Honestly stageless: one undivided grey bar. Filing this
                // source's whole night under "light" would invent stage detail
                // that was never measured.
                return [Segment(source: row.source, stage: nil, hours: row.asleepHours)]
            }
            return NightSleepDetail.Stage.allCases.map { stage in
                Segment(source: row.source, stage: stage,
                        hours: row.hoursByStage[stage] ?? 0)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            chart
            counts
            key
            caption
        }
    }

    private var chart: some View {
        // substance-shading: exempt — the x axis is hours per night, not a date.
        // A logged drink happened at an instant, and this chart has no instant
        // anywhere on it for that window to land on. `NightSleepChart`, which
        // does have a time axis, draws the shading.
        Chart {
            marks
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel().font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.caption2)
            }
        }
        .chartXAxisLabel("hours per night", alignment: .trailing)
        .frame(height: CGFloat(averages.rows.count) * 44 + 28)
    }

    /// Explicit `some ChartContent`: without it a `BarMark` chain can resolve to
    /// `Chart3DContent` on this SDK and silently drop `.foregroundStyle`.
    @ChartContentBuilder
    private var marks: some ChartContent {
        ForEach(segments) { segment in
            BarMark(
                x: .value("Hours", segment.hours),
                y: .value("Source", segment.source),
                height: .ratio(0.58)
            )
            .foregroundStyle(NightSleepChart.color(for: segment.stage))
        }
    }

    /// How much each bar is based on, beside the bar rather than in a caption.
    /// A mean of three nights and a mean of thirty look identical on the axis,
    /// and the difference is the whole question of whether to believe it.
    private var counts: some View {
        HStack(spacing: 10) {
            ForEach(averages.rows) { row in
                Text("\(row.source): \(row.nights) \(row.nights == 1 ? "night" : "nights")")
            }
            Spacer()
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    /// Plain, opaque swatches — a key answers "which stage is this".
    private var key: some View {
        HStack(spacing: 10) {
            ForEach(NightSleepDetail.Stage.allCases, id: \.self) { stage in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(NightSleepChart.color(for: stage))
                        .frame(width: 8, height: 8)
                    Text(stage.label)
                }
            }
            if averages.rows.contains(where: { !$0.hasStageDetail }) {
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(NightSleepChart.color(for: nil))
                        .frame(width: 8, height: 8)
                    Text("No stage detail")
                }
            }
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var caption: some View {
        Text("Each bar is one source's typical night over the timeframe below — the mean of the nights that source actually recorded, not of every night in the window, so a wearable you wore nine nights isn't drawn as nine thin ones. Sources are never averaged together: where two disagree, both bars are drawn and the difference is the finding.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
