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
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Scores over time")
        .navigationBarTitleDisplayMode(.inline)
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
