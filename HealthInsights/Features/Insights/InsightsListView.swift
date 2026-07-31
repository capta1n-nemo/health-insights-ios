import SwiftUI
import InsightKit

/// The Insights tab: analysis-derived, longer-horizon cards (heart-attack risk,
/// heart health, blood pressure, body composition, …) — the things that need
/// trends, not just today's numbers.
struct InsightsListView: View {
    @Environment(AppModel.self) private var model
    /// Collapsed by default. The section is pinned to the top as a persistent
    /// reminder, and a reminder that fills the screen every time you open the
    /// tab stops being one — so it opens as a one-line count and expands on tap.
    @AppStorage("suggestionsExpanded") private var isExpanded = false

    private var trendResults: [InsightResult] {
        model.results.filter { $0.id.cadence == .trend && $0.isWorthShowing }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.spacing) {
                    // Pinned above everything, including the tab's own
                    // subtitle: it is the only thing here that is about what to
                    // *do*, and it is the reason the tab gets opened.
                    suggestionsCard
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
            // A dismissal whose suggestion has stopped being made is dead, and
            // this is where it gets cleared — the one screen guaranteed to have
            // forced the (lazy) suggestion list.
            .task { model.pruneResolvedSuggestions() }
        }
    }

    /// "Improve Your Health" — pinned, collapsed, and keeping what you dismissed.
    ///
    /// It lives here rather than only on Today because this is where the
    /// evidence comes from — the busier-versus-lighter-weeks contrast, the
    /// grounding gaps, the signals off baseline are all derived rather than
    /// sensed. Today shows the single best-founded one and lets you wave it
    /// away; this is the list that keeps it, which is what makes dismissing
    /// something on Today safe rather than destructive.
    ///
    /// Dismissed rows stay, dimmed, with a Restore button. A suggestion the
    /// engine has stopped making is gone from both screens without either of
    /// them deciding anything — see `SuggestionVisibility`.
    ///
    /// Silent when there is nothing to say, which is often and correctly so.
    @ViewBuilder private var suggestionsCard: some View {
        let rows = model.suggestionVisibility.insights
        if !rows.isEmpty {
            let active = rows.filter { !$0.isDismissed }.count
            Card {
                VStack(alignment: .leading, spacing: isExpanded ? 12 : 0) {
                    Button {
                        withAnimation(.snappy) { isExpanded.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.forward.circle")
                            Text("Improve your health").font(.headline)
                            Spacer(minLength: 4)
                            Text(active > 0 ? "\(active)" : "all set")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(active > 0 ? Theme.accent.opacity(0.15)
                                                       : Color.secondary.opacity(0.12),
                                            in: Capsule())
                                .foregroundStyle(active > 0 ? Theme.accent : .secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        Text("What your own data points at, strongest evidence first.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(rows) { row in
                            suggestionRow(row.suggestion, isDismissed: row.isDismissed)
                        }
                        Text("Observations from your own history, not medical advice. Talk to a clinician about anything that concerns you.")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder private func suggestionRow(_ suggestion: Suggestion,
                                            isDismissed: Bool) -> some View {
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
        // Dimmed rather than removed: this list is the reminder, and something
        // you waved away on Today is exactly what it is here to keep hold of.
        .opacity(isDismissed ? 0.45 : 1)

        VStack(alignment: .leading, spacing: 6) {
            if let insight = suggestion.insight {
                NavigationLink { InsightDetailView(insightID: insight) } label: { row }
                    .buttonStyle(.plain)
            } else {
                row
            }
            HStack(spacing: 8) {
                if isDismissed {
                    Button("Show on Today again") {
                        model.restoreSuggestion(id: suggestion.id)
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.mini)
                } else {
                    Button {
                        model.dismissSuggestion(id: suggestion.id)
                    } label: {
                        Label("Dismiss", systemImage: "xmark")
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.mini)
                    .tint(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Green where the evidence is the user's own history, amber where the app is
    /// missing a fact, red where a signal has moved. The dot is a claim about how
    /// well-founded the line is, not about how urgent it is.
    private func colour(for basis: Suggestion.Basis) -> Color {
        switch basis {
        // Several signals agreeing is the best-founded thing this app says, so
        // it takes the same green as an observation from the user's own history
        // rather than a louder hue. The dot ranks evidence; the row's position
        // at the top of the list is what says this one is time-critical.
        case .convergingSignals: return Theme.good
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
