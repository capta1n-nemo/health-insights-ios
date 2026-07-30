import SwiftUI
import InsightKit

/// The universal per-metric screen. For any metric it overlays every source on
/// one chart and shows the honest "Apple Watch: X · Oura: Y · Average: Z"
/// breakdown. Every card links here so multi-source data is treated the same way
/// everywhere.
struct MetricDetailView: View {
    let metric: MetricType
    @Environment(AppModel.self) private var model
    @State private var logScale = false
    @State private var timeframe: Timeframe = .month
    /// The span the chart is currently showing; changes as the user pans.
    @State private var visibleRange: ClosedRange<Date>?
    /// Where the finger is while scrubbing, so the read-outs can follow it.
    @State private var scrubbed: Date?

    /// The whole history, handed to the chart so it has something to scroll
    /// through. The timeframe acts as the zoom level, not as a filter here.
    private var allData: MultiSourceBreakdown { model.breakdown(metric) }

    /// Restricted to what's on screen, so the per-source read-outs and averages
    /// describe the visible window rather than stale latest values.
    private var breakdown: MultiSourceBreakdown {
        if let visibleRange { return model.breakdown(metric, in: visibleRange) }
        return model.breakdown(metric, within: timeframe)
    }
    /// Seconds of history one chart-width shows. `.all` resolves against the
    /// data rather than a fixed constant, which is what stopped a short history
    /// being squashed into a sliver.
    private var window: TimeInterval {
        let span = allData.dateSpan.map { $0.upperBound.timeIntervalSince($0.lowerBound) }
        return timeframe.chartWindow(spanning: span)
    }

    /// Whether the metric has any data at all (across all time) — used so the
    /// timeframe picker stays available even when the chosen window is empty.
    private var hasAnyData: Bool { !allData.sources.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if !hasAnyData {
                    ContentUnavailableView(
                        "No \(metric.displayName.lowercased()) yet",
                        systemImage: "waveform.path.ecg",
                        description: Text("Connect a device or Apple Health, then pull to refresh."))
                        .padding(.top, 40)
                } else {
                    overlayCard
                    if breakdown.sources.isEmpty {
                        Card {
                            Text("No \(metric.displayName.lowercased()) in the window shown. Swipe the chart sideways, or pick a longer timeframe.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        Card {
                            SourceBreakdown(breakdown: breakdown,
                                            timeframe: timeframe,
                                            visibleRange: visibleRange,
                                            scrubbed: scrubbed)
                        }
                        if breakdown.hasMultipleSources { statsCard }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(metric.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Names the span on screen: the timeframe's own label until the user pans
    /// away from the present, then the actual dates being shown.
    private var visibleLabel: String {
        guard let visibleRange, visibleRange.upperBound < Date().addingTimeInterval(-window / 20) else {
            return timeframe.longLabel
        }
        let from = visibleRange.lowerBound.formatted(date: .abbreviated, time: .omitted)
        let to = visibleRange.upperBound.formatted(date: .abbreviated, time: .omitted)
        return "\(from) – \(to)"
    }

    private var overlayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(visibleLabel).font(.headline)
                Picker("Timeframe", selection: $timeframe) {
                    ForEach(Timeframe.allCases) { Text($0.shortLabel).tag($0) }
                }
                .pickerStyle(.segmented)
                if breakdown.hasMultipleSources {
                    Text("Each device is a separate colour, so you can spot where they disagree.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                MultiSourceChart(breakdown: allData,
                                 window: window,
                                 logarithmic: logScale,
                                 onVisibleRangeChange: { visibleRange = $0 },
                                 selection: $scrubbed)
                Text("Drag across the chart to read individual points; swipe it sideways to move back through your history.")
                    .font(.caption2).foregroundStyle(.tertiary)
                HStack {
                    Picker("Scale", selection: $logScale) {
                        Text("Linear").tag(false)
                        Text("Log").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    Spacer()
                }
                if logScale {
                    Text("Logarithmic scale — useful when your sources differ by a wide margin.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var statsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Per-source averages").font(.headline)
                ForEach(Array(breakdown.sources.enumerated()), id: \.element.id) { index, series in
                    HStack(spacing: 9) {
                        Circle().fill(Theme.sourceColor(index)).frame(width: 9, height: 9)
                        Text(series.displayName)
                        Spacer()
                        if let mean = series.mean {
                            Text("\(formatMetric(mean, metric)) \(metric.unit)")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Text("· \(series.samples.count) readings")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}
