import SwiftUI
import InsightKit

/// The Vitals tab — the "everything" data browser for people who want to dig.
/// Lists every metric that has data, grouped, with its latest value and how many
/// sources report it; tapping opens the multi-source overlay in `MetricDetailView`.
struct VitalsView: View {
    @Environment(AppModel.self) private var model

    private struct MetricGroup: Identifiable {
        let id = UUID()
        let title: String
        let metrics: [MetricType]
    }

    /// Fixed category order; only metrics that actually have samples are shown.
    private static let categories: [(String, [MetricType])] = [
        ("Heart & circulation", [.heartRate, .restingHeartRate, .walkingHeartRateAverage,
                                 .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN,
                                 .vo2Max, .respiratoryRate, .oxygenSaturation,
                                 .bloodPressureSystolic, .bloodPressureDiastolic]),
        ("Body", [.bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass,
                  .boneMass, .bodyWaterPercentage, .height]),
        ("Sleep & recovery", [.sleepDurationHours, .bodyTemperature,
                              .skinTemperatureDeviation, .dayStrain]),
        ("Activity", [.stepCount, .activeEnergyBurned])
    ]

    private var groups: [MetricGroup] {
        let present = Set(model.samples.map(\.type))
        return Self.categories.compactMap { title, metrics in
            let available = metrics.filter { present.contains($0) }
            return available.isEmpty ? nil : MetricGroup(title: title, metrics: available)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView("No data yet", systemImage: "waveform.path.ecg",
                        description: Text("Connect Apple Health or a device in Settings, then pull to refresh."))
                } else {
                    List {
                        ForEach(groups) { group in
                            Section(group.title) {
                                ForEach(group.metrics, id: \.self) { metric in
                                    NavigationLink {
                                        MetricDetailView(metric: metric)
                                    } label: {
                                        row(for: metric)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Vitals")
            .refreshable { await model.refresh() }
        }
    }

    private func row(for metric: MetricType) -> some View {
        let breakdown = model.breakdown(metric)
        let sourceCount = breakdown.sources.count
        return HStack {
            Text(metric.displayName)
            Spacer()
            if let value = breakdown.consensusLatest {
                Text("\(formatMetric(value, metric)) \(metric.unit)")
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            if sourceCount > 1 {
                Text("· \(sourceCount) sources").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
