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

    /// Restricted to the selected timeframe, so the per-source read-outs and
    /// averages reflect only that window (not stale latest values).
    private var breakdown: MultiSourceBreakdown { model.breakdown(metric, within: timeframe) }
    /// Seconds of history to show; `.all` maps to a very large window.
    private var window: TimeInterval { timeframe.window ?? 60 * 60 * 24 * 366 * 12 }

    /// Whether the metric has any data at all (across all time) — used so the
    /// timeframe picker stays available even when the chosen window is empty.
    private var hasAnyData: Bool { !model.breakdown(metric).sources.isEmpty }

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
                            Text("No \(metric.displayName.lowercased()) in \(timeframe.longLabel.lowercased()). Try a longer timeframe.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        Card { SourceBreakdown(breakdown: breakdown) }
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

    private var overlayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(timeframe.longLabel).font(.headline)
                Picker("Timeframe", selection: $timeframe) {
                    ForEach(Timeframe.allCases) { Text($0.shortLabel).tag($0) }
                }
                .pickerStyle(.segmented)
                if breakdown.hasMultipleSources {
                    Text("Each device is a separate colour, so you can spot where they disagree.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                MultiSourceChart(breakdown: breakdown, window: window, logarithmic: logScale)
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
