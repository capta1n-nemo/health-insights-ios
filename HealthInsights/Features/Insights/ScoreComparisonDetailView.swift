import SwiftUI
import InsightKit

/// Every score on one time axis — the old Insights hero, kept whole and moved
/// one tap away.
///
/// ## Why it moved rather than went
///
/// The chart answers something the balance web genuinely cannot: whether your
/// scores have been moving *as one thing or pulling apart* over months. Nothing
/// else in the app asks that, so deleting it would have cost a real question.
///
/// What it could not go on being is the first thing the tab does. Drawing it
/// needs `AppModel.scoreHistory(for:)` for every scored insight, and each of
/// those is a 90-day replay walking the sample set once per replayed day —
/// see `AppModel.maxConcurrentReplays`, whose doc comment records the four-to-six
/// second scroll freezes that came of starting them all on tab open. Behind a
/// tap, the same replays cost only the reader who asked for the answer, and they
/// are the only thing on screen so there is nothing for them to stutter.
struct ScoreComparisonDetailView: View {
    @Environment(AppModel.self) private var model

    /// Which card the decomposition below is explaining. Nil means "the lowest
    /// one", resolved at render — not seeded to a concrete id, because the
    /// lowest score changes under the reader and a seeded default would pin the
    /// section to whichever card was worst the first time they opened it.
    @State private var selectedInsight: InsightID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                let series = comparisonSeries
                Card {
                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        Text("How your scores compare").font(.headline)
                        Text("All of your scores share the same 0–100 scale, so they can be read directly against each other.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if series.count >= 2 {
                            ScoreComparisonChart(series: series)
                        } else {
                            placeholder
                        }
                    }
                }
                Text("The four cards with the most recorded history are drawn, so the chart stays readable. Each card's own screen carries its full score history.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                decompositionSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Scores over time")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Why is my score low

    /// **Backlog #38, placed here by the reader**: *"I don't want this to be a
    /// card, I want this to be part of the deep dive under the insight web."*
    ///
    /// The research called it the highest-value idea in the whole competitive
    /// scan and Oura's number one unfixable complaint. It sits below the
    /// comparison chart on purpose: the chart answers *which* of your scores is
    /// low, and this answers *why that one is* — the natural next question, one
    /// screen down rather than one tap away on a card nobody opens.
    ///
    /// It defaults to the lowest-scoring card, because that is the one the
    /// reader came here about.
    @ViewBuilder private var decompositionSection: some View {
        let scored = model.results.filter { $0.score != nil }
            .sorted { ($0.score ?? 0) < ($1.score ?? 0) }
        if !scored.isEmpty {
            let chosen = scored.first { $0.id == selectedInsight } ?? scored[0]
            Card {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    Text("Why is this score what it is").font(.headline)
                    Picker("Card", selection: Binding(
                        get: { chosen.id },
                        set: { selectedInsight = $0 })
                    ) {
                        ForEach(scored, id: \.id) { result in
                            Text(String(format: "%@ · %.0f", result.title, result.score ?? 0))
                                .tag(result.id)
                        }
                    }
                    .pickerStyle(.menu)

                    if let out = ScoreDecomposition.evaluate(chosen) {
                        Text(out.headline)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        if out.refusal == nil {
                            ForEach(out.rows) { row in
                                decompositionRow(row, worst: out.rows.first?.headroom ?? 1)
                            }
                            if let accounted = out.accountedFor {
                                Text(String(format: "These account for %.0f of the %.0f points between this score and 100. The rest is rounding, and any part of the card whose model does not report its own sub-score.",
                                            accounted, 100 - out.score))
                                    .font(.caption2).foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if !out.unscored.isEmpty {
                            Divider()
                            Text("Charted, and carrying none of the number:")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(out.unscored) { row in
                                Text("\(row.label) — \(row.detail)")
                                    .font(.caption2).foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    /// One component: its own score, its share, and what fixing it would buy.
    ///
    /// The bar is the **headroom**, not the weight. A reader asking why a score
    /// is low is asking what to move, and the heaviest component is very often
    /// already at its ceiling — drawing weight would put the longest bar on the
    /// thing there is least to gain from.
    private func decompositionRow(_ row: ScoreDecomposition.Row,
                                  worst: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(row.label).font(.subheadline)
                Spacer()
                if let component = row.componentScore {
                    Text(String(format: "%.0f/100", component))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                Text(String(format: "%.0f%%", row.weight * 100))
                    .font(.caption).monospacedDigit().foregroundStyle(.tertiary)
                    .frame(width: 38, alignment: .trailing)
            }
            if let headroom = row.headroom, headroom > 0 {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.12)).frame(height: 6)
                        Capsule().fill(Theme.warn.opacity(0.65))
                            .frame(width: max(2, geometry.size.width
                                              * min(headroom / max(worst, 0.001), 1)),
                                   height: 6)
                    }
                    .frame(height: 6)
                }
                .frame(height: 6)
                Text(String(format: "%@ · at its best this would give back %.1f points",
                            row.detail, headroom))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(row.detail)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    /// Working and empty are different states, and the replay takes long enough
    /// that announcing "no scored days yet" would be a false statement that
    /// corrects itself after the reader has read it — the same distinction
    /// `SectionPlaceholder.isLoading` exists for.
    @ViewBuilder private var placeholder: some View {
        let pending = model.results.contains {
            $0.score != nil && model.scoreHistoryIsPending(for: $0.id)
        }
        VStack(alignment: .leading, spacing: 8) {
            if pending {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Replaying your score history…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("Ninety days are being re-scored from your raw samples. This runs once.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Not enough history to compare yet")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Two cards need at least eight scored days each before their lines can be read against one another.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
    }

    /// The scored insights with enough history to plot, most-populated first,
    /// capped so the chart stays readable.
    ///
    /// **This is the one place in the app that still asks for every history at
    /// once**, and it is deliberate here: it is the whole subject of the screen,
    /// and nothing else is competing for the CPU while it runs.
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
