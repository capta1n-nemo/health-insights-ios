import SwiftUI
import InsightKit

/// The whole screen for a standing fact like height.
///
/// No chart, no timeframe picker, no log/linear toggle: a "past week" view of a
/// number that doesn't move is noise, and the generic screen also rounded the
/// value to a whole metre, turning 1.85 m into "2 m".
struct StaticAttributeCard: View {
    @Environment(AppModel.self) private var model
    let metric: MetricType

    private var breakdown: MultiSourceBreakdown { model.breakdown(metric) }

    /// Newest first — the current value at the top, everything before it as
    /// history.
    private var entries: [HealthMetricSample] {
        breakdown.sources.flatMap(\.samples).sorted { $0.start > $1.start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            if let current = entries.first {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(metric.displayName)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(MetricValueFormatter.detailedString(current.value, metric))
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("Last updated \(current.start.formatted(date: .abbreviated, time: .omitted)) · \(current.source.displayName)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if entries.count > 1 {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Earlier entries").font(.headline)
                            ForEach(entries.dropFirst()) { entry in
                                HStack {
                                    Text(MetricValueFormatter.detailedString(entry.value, metric))
                                        .monospacedDigit()
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(entry.start.formatted(date: .abbreviated, time: .omitted))
                                        Text(entry.source.displayName)
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                    .font(.caption)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No \(metric.displayName.lowercased()) recorded",
                    systemImage: "ruler",
                    description: Text("Add it in Apple Health, or in Settings under your details."))
                    .padding(.top, 40)
            }
        }
    }
}
