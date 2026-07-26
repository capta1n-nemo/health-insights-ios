import SwiftUI

struct InsightsListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.spacing) {
                    ForEach(model.results, id: \.id) { result in
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
