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
                    suggestionsCard
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

    /// "Improve Your Health".
    ///
    /// It lives here rather than on Today because this is where the evidence for
    /// it comes from — the busier-versus-lighter-weeks contrast, the grounding
    /// gaps, the signals off baseline are all derived rather than sensed, and a
    /// derived finding belongs next to the analysis it came out of.
    ///
    /// Silent when there is nothing to say, which is often and correctly so.
    @ViewBuilder private var suggestionsCard: some View {
        let suggestions = model.suggestions
        if !suggestions.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Improve your health", systemImage: "arrow.up.forward.circle")
                        .font(.headline)
                    Text("What your own data points at, strongest evidence first.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(suggestions) { suggestion in
                        suggestionRow(suggestion)
                    }
                    Text("Observations from your own history, not medical advice. Talk to a clinician about anything that concerns you.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private func suggestionRow(_ suggestion: Suggestion) -> some View {
        let row = VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(colour(for: suggestion.basis)).frame(width: 7, height: 7)
                Text(suggestion.title).font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Text(suggestion.detail)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let insight = suggestion.insight {
            NavigationLink { InsightDetailView(insightID: insight) } label: { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    /// Green where the evidence is the user's own history, amber where the app is
    /// missing a fact, red where a signal has moved. The dot is a claim about how
    /// well-founded the line is, not about how urgent it is.
    private func colour(for basis: Suggestion.Basis) -> Color {
        switch basis {
        case .yourOwnData: return Theme.good
        case .unlockAnInsight: return Theme.warn
        case .signalOffBaseline: return Theme.accent
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
        let candidates = model.results
            .filter { $0.score != nil }
            .compactMap { result -> (InsightID, String, [ScorePoint])? in
                let points = model.scoreHistory(for: result.id)
                guard points.count >= 8 else { return nil }
                return (result.id, result.title, points)
            }
            .sorted { $0.2.count > $1.2.count }
            .prefix(4)
        // Hues resolved across *this* chart's four, not read off a global table.
        // Twelve insights share eight validated hues, so preferences collide by
        // construction — and since the user chooses which four are drawn, a fixed
        // table could and did put two of a colliding pair on screen together.
        let slots = InsightPalette.slots(for: candidates.map { $0.0 })
        return candidates.map { id, title, points in
            .init(id: id, title: title, points: points,
                  tint: Theme.insightTint(id, slots: slots))
        }
    }
}
