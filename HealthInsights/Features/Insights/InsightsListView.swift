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
                    scoreComparisonCard
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

    /// Every scored insight on one axis.
    ///
    /// Scores need no normalising — they are all 0–100 already — so this is the
    /// one overlay in the app that is directly comparable without a transform.
    /// It answers a question no single card can: whether your scores have been
    /// moving as one thing or pulling apart.
    @ViewBuilder private var scoreComparisonCard: some View {
        let series = comparisonSeries
        if series.count >= 2 {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How your scores compare").font(.headline)
                    Text("All of your scores share the same 0–100 scale, so they can be read directly against each other.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ScoreComparisonChart(series: series)
                }
            }
        }
    }

    /// The scored insights that have enough history to plot, most-populated
    /// first, capped so the chart stays readable.
    private var comparisonSeries: [ScoreComparisonChart.Series] {
        model.results
            .filter { $0.score != nil }
            .compactMap { result -> ScoreComparisonChart.Series? in
                let points = model.scoreHistory(for: result.id)
                guard points.count >= 8 else { return nil }
                return .init(id: result.id, title: result.title, points: points,
                             tint: Theme.insightTint(result.id))
            }
            .sorted { $0.points.count > $1.points.count }
            .prefix(4)
            .map { $0 }
    }
}
