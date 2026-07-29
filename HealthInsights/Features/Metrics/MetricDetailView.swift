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

    private var breakdown: MultiSourceBreakdown { model.breakdown(metric) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                if breakdown.sources.isEmpty {
                    ContentUnavailableView(
                        "No \(metric.displayName.lowercased()) yet",
                        systemImage: "waveform.path.ecg",
                        description: Text("Connect a device or Apple Health, then pull to refresh."))
                        .padding(.top, 40)
                } else {
                    overlayCard
                    Card { SourceBreakdown(breakdown: breakdown) }
                    if breakdown.hasMultipleSources { statsCard }
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
                HStack {
                    Text("Last 48 hours").font(.headline)
                    Spacer()
                    Picker("Scale", selection: $logScale) {
                        Text("Linear").tag(false)
                        Text("Log").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                if breakdown.hasMultipleSources {
                    Text("Each device is a separate colour, so you can spot where they disagree.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                MultiSourceChart(breakdown: breakdown, window: 2 * 24 * 3600, logarithmic: logScale)
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
