import SwiftUI
import InsightKit

/// The Insights tab: analysis-derived, longer-horizon cards (heart-attack risk,
/// heart health, blood pressure, body composition, …) — the things that need
/// trends, not just today's numbers.
struct InsightsListView: View {
    @Environment(AppModel.self) private var model

    private var trendResults: [InsightResult] {
        model.results.filter { $0.id.cadence == .trend }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.spacing) {
                    Text("Deeper analysis of your trends over time.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(trendResults, id: \.id) { result in
                        NavigationLink {
                            InsightDetailView(insightID: result.id)
                        } label: {
                            InsightCard(result: result)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insights")
            .refreshable { await model.refresh() }
        }
    }
}
