import SwiftUI
import InsightKit

/// What a metric-detail section needs to render itself.
struct MetricDetailContext {
    let subject: MetricSubject
    let timeframe: Timeframe
    /// The window on screen, once the chart has reported one.
    let visibleRange: ClosedRange<Date>?
}

/// Picks the layout for a metric.
///
/// A compiler-checked switch over `MetricPresentation` with one concrete `View`
/// per case, rather than a protocol returning `some View`. A protocol would
/// force either `AnyView` — losing SwiftUI's structural identity on a screen
/// that re-renders every pan frame — or a generic parameter propagating out to
/// every call site.
enum MetricViewStrategy {
    @ViewBuilder
    static func summary(for context: MetricDetailContext) -> some View {
        switch context.subject.presentation {
        case .cumulativeTrend:
            CumulativeTrendSummary(context: context)
        case .fluctuatingRange:
            FluctuatingRangeSummary(context: context)
        case .cumulativeTotal:
            CumulativeTotalSummary(context: context)
        case .discreteBivariate, .staticAttribute:
            // These presentations replace the whole screen rather than adding a
            // card to the standard one.
            EmptyView()
        }
    }
}

/// Start, current, change and how fast it's moving — the questions worth asking
/// of a weight, which a min/max range would not answer.
private struct CumulativeTrendSummary: View {
    @Environment(AppModel.self) private var model
    let context: MetricDetailContext

    private var metric: MetricType { context.subject.primaryMetric }

    private var trend: TrendSummary? {
        let breakdown = model.breakdown(metric, in: context.visibleRange ?? allTime)
        // One combined series: a start-to-current change across every device is
        // what the user means, even if they switched scales part-way.
        let samples = breakdown.sources.flatMap(\.samples).sorted { $0.start < $1.start }
        return TrendSummary.make(from: samples)
    }

    private var allTime: ClosedRange<Date> {
        model.breakdown(metric).dateSpan ?? Date()...Date()
    }

    var body: some View {
        if let trend {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Change over this period").font(.headline)
                    HStack(alignment: .top) {
                        stat("Start", trend.start.value)
                        Spacer()
                        stat("Current", trend.current.value)
                        Spacer()
                        deltaStat(trend)
                    }
                    if let velocity = trend.velocityPerWeek, abs(velocity) > 0.001 {
                        Text(velocityText(velocity))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(formatMetric(value, metric)).font(.title3.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func deltaStat(_ trend: TrendSummary) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Change").font(.caption).foregroundStyle(.secondary)
            Text("\(trend.delta > 0 ? "+" : "")\(formatMetric(trend.delta, metric))")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(trend.delta == 0 ? Color.primary : Theme.accent)
        }
    }

    /// Reported per week rather than per day: the figure people actually track,
    /// and steady enough to be meaningful.
    private func velocityText(_ velocity: Double) -> String {
        let direction = velocity > 0 ? "gaining" : "losing"
        let magnitude = formatMetric(abs(velocity), metric)
        return "Currently \(direction) about \(magnitude) \(metric.unit) a week, over the whole window."
    }
}

/// A signal that varies constantly is described by its spread, not a single
/// number — and by where the latest reading sits inside it.
private struct FluctuatingRangeSummary: View {
    @Environment(AppModel.self) private var model
    let context: MetricDetailContext

    private var metric: MetricType { context.subject.primaryMetric }

    private var summary: RangeSummary? {
        let breakdown = context.visibleRange.map { model.breakdown(metric, in: $0) }
            ?? model.breakdown(metric, within: context.timeframe)
        return RangeSummary.make(from: breakdown.sources.flatMap(\.samples))
    }

    var body: some View {
        if let summary {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Range over this period").font(.headline)
                    HStack(alignment: .top) {
                        stat("Low", summary.min)
                        Spacer()
                        stat("Average", summary.mean)
                        Spacer()
                        stat("High", summary.max)
                    }
                    Text("Most readings fall between \(formatMetric(summary.p10, metric)) and \(formatMetric(summary.p90, metric)) \(metric.unit).")
                        .font(.caption).foregroundStyle(.secondary)
                    if let latest = summary.latest, let percentile = summary.latestPercentile {
                        Text(latestText(latest.value, percentile: percentile))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(formatMetric(value, metric)).font(.title3.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func latestText(_ value: Double, percentile: Double) -> String {
        let pct = Int((percentile * 100).rounded())
        return "Your latest reading of \(formatMetric(value, metric)) sits above \(pct)% of this period."
    }
}

/// Steps and active energy only mean anything totalled per day, so this reports
/// days rather than readings.
private struct CumulativeTotalSummary: View {
    @Environment(AppModel.self) private var model
    let context: MetricDetailContext

    private var metric: MetricType { context.subject.primaryMetric }

    /// Totals are computed per source and the busiest one is shown, because
    /// summing a Watch and a pocketed phone together double-counts every step.
    private var totals: [DailyTotal] {
        let breakdown = context.visibleRange.map { model.breakdown(metric, in: $0) }
            ?? model.breakdown(metric, within: context.timeframe)
        guard let richest = breakdown.sources.max(by: { $0.samples.count < $1.samples.count })
        else { return [] }
        return DailyTotals.bucket(richest)
    }

    var body: some View {
        let daily = totals
        if !daily.isEmpty {
            let summary = DailyTotals.summary(daily)
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Daily totals").font(.headline)
                    HStack(alignment: .top) {
                        stat("Today", summary.today)
                        Spacer()
                        stat("Daily average", summary.dailyAverage)
                        Spacer()
                        stat("Best day", summary.best?.total)
                    }
                    Text("Counted from your most complete source, so a phone in your pocket and a watch on your wrist aren't added together.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.map { formatMetric($0, metric) } ?? "—")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
    }
}
