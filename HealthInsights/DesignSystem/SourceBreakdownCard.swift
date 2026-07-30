import SwiftUI
import InsightKit

/// "What each source says" — the honest per-source read-out under every chart.
///
/// Three things it is careful about:
///  * it describes the window on screen, not all of history, so switching
///    timeframe or panning changes the numbers;
///  * a source that has gone quiet is shown as history rather than being allowed
///    into the current average, where it would invent a disagreement;
///  * it says which path each reading arrived by, since the same ring can report
///    both directly and through Apple Health.
struct SourceBreakdown: View {
    /// Already restricted to the window being described.
    let breakdown: MultiSourceBreakdown
    var timeframe: Timeframe = .month
    /// The window on screen, when the chart has reported one.
    var visibleRange: ClosedRange<Date>?
    /// Where the finger is, while scrubbing.
    var scrubbed: Date?

    private var range: ClosedRange<Date> {
        if let visibleRange { return visibleRange }
        if let span = breakdown.dateSpan { return span }
        let now = Date()
        return now.addingTimeInterval(-86_400)...now
    }

    /// How recently a source must have reported to count as describing "now".
    ///
    /// Over a day, week or month the window itself is the test. Over six months
    /// or more that would let a source that stopped reporting last spring look
    /// current, so those fall back to the last 30 days.
    private var recencyWindow: TimeInterval {
        switch timeframe {
        case .day, .week, .month:
            return timeframe.window ?? 30 * 24 * 3600
        case .sixMonths, .year, .all:
            return 30 * 24 * 3600
        }
    }

    private var activity: SourceActivity {
        breakdown.activity(in: range, recencyWindow: recencyWindow)
    }

    private var isScrubbing: Bool { scrubbed != nil }

    /// A period average is the honest figure over anything longer than a day;
    /// "right now" only means something at day resolution.
    private var showsPeriodAverage: Bool { !isScrubbing && timeframe != .day }

    private var title: String {
        if let scrubbed {
            return scrubbed.formatted(date: .abbreviated, time: .shortened)
        }
        if !breakdown.hasMultipleSources {
            return showsPeriodAverage ? "Average for selected period" : "Latest reading"
        }
        return showsPeriodAverage
            ? "What each source says — average for selected period"
            : "What each source says right now"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)

            ForEach(Array(activity.active.enumerated()), id: \.element.id) { index, series in
                row(series, colorIndex: colorIndex(of: series, fallback: index))
            }

            if activity.active.isEmpty {
                Text("No source reported in this window.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            consensusRows
            inactiveSection
        }
    }

    /// Colour follows the source's position in the full breakdown, so a line
    /// doesn't change colour just because another source dropped out of view.
    private func colorIndex(of series: SourceSeries, fallback: Int) -> Int {
        breakdown.sources.firstIndex { $0.id == series.id } ?? fallback
    }

    private func row(_ series: SourceSeries, colorIndex: Int) -> some View {
        HStack(spacing: 9) {
            Circle().fill(Theme.sourceColor(colorIndex)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(series.displayName)
                originLabel(for: series)
            }
            Spacer()
            if let value = value(for: series) {
                Text(formatted(value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder private func originLabel(for series: SourceSeries) -> some View {
        let origins = series.origins
        if !origins.isEmpty {
            HStack(spacing: 3) {
                ForEach(SourceOrigin.allCases.filter { origins.contains($0) }, id: \.self) {
                    Image(systemName: $0.badgeSymbol)
                }
                Text(origins.combinedLabel)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    /// What this source says for the window being described.
    private func value(for series: SourceSeries) -> Double? {
        if let scrubbed { return nearest(in: series, to: scrubbed) }
        if showsPeriodAverage {
            // Median for the metrics whose bucket rule is a median, so one
            // outlier reading can't move the reported figure.
            let values = series.samples.map(\.value)
            return breakdown.type.bucketStatistic == .median
                ? Baseline.quantile(0.5, of: values)
                : Baseline.mean(values)
        }
        return series.latest
    }

    /// The reading nearest the crosshair, ignoring any too far away to be what
    /// the user is pointing at.
    private func nearest(in series: SourceSeries, to date: Date) -> Double? {
        guard let nearest = series.samples.min(by: {
            abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date))
        }) else { return nil }
        let tolerance = range.upperBound.timeIntervalSince(range.lowerBound) / 8
        guard abs(nearest.start.timeIntervalSince(date)) <= tolerance else { return nil }
        return nearest.value
    }

    private func formatted(_ value: Double) -> String {
        let text = formatMetric(value, breakdown.type)
        guard !formatMetricIncludesUnit(breakdown.type), !breakdown.type.unit.isEmpty else {
            return text
        }
        return "\(text) \(breakdown.type.unit)"
    }

    /// Average and disagreement, over the live sources only.
    @ViewBuilder private var consensusRows: some View {
        if activity.canCompare, let average = breakdown.consensus(over: activity.active) {
            Divider()
            HStack {
                Text("Average").font(.subheadline.weight(.semibold))
                Spacer()
                Text(formatted(average))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            if let spread = breakdown.spread(over: activity.active), spread > 0 {
                Text("Your sources differ by \(formatted(spread)).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Sources with history here but nothing recent. Listed so the data isn't
    /// hidden, tagged so it can't be mistaken for current.
    @ViewBuilder private var inactiveSection: some View {
        if !activity.inactive.isEmpty {
            Divider()
            Text("Inactive · historical")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(activity.inactive, id: \.series.id) { stale in
                HStack(spacing: 9) {
                    Circle().fill(.tertiary).frame(width: 9, height: 9)
                    Text(stale.series.displayName)
                    Spacer()
                    if let last = stale.series.latest {
                        Text(formatted(last)).monospacedDigit()
                    }
                    Text("· last seen \(stale.lastActive.formatted(.dateTime.month(.abbreviated).year()))")
                        .font(.caption2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text("Excluded from the average — these haven't reported recently.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
