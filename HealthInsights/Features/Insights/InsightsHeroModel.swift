import SwiftUI
import InsightKit

/// Builds the Insights hero off the main actor and publishes it when it lands.
///
/// ## What this is actually buying, stated honestly
///
/// The large win on this tab was **not** moving work to a background thread —
/// it was removing the work. The hero used to be `ScoreComparisonChart`, which
/// needs `AppModel.scoreHistory(for:)` per insight: a 90-day replay that walks
/// the sample set once per replayed day. Opening the tab queued one for every
/// scored card, and `AppModel.maxConcurrentReplays` records what that did to
/// scrolling. `BalanceWebSnapshot` reads `InsightResult.score` and the cached
/// `ScoreChange` instead, so **opening this tab now starts no replays at all**.
///
/// What is left is small — a filter, a sort and nine struct copies — and it runs
/// detached anyway, for two reasons that are real rather than ceremonial:
///
/// - The first frame after a cold launch has no `results` yet, so the tab has a
///   genuine empty moment to fill with a skeleton rather than with a collapsed
///   card that shoves the feed upward when it fills.
/// - It is the seam. Anything the hero later wants that *is* expensive — a
///   coherence measure over stored history, say — lands here rather than in a
///   view body, which is where the replays were being triggered from.
///
/// The generation counter is the same guard `AppModel` uses on its own replays:
/// a build that started before the results changed is discarded on arrival
/// rather than publishing a shape built from data that has since been replaced.
@MainActor
@Observable
final class InsightsHeroModel {

    enum Phase: Equatable {
        /// No snapshot yet. The skeleton holds the card's height.
        case building
        /// Built. An empty snapshot is a legitimate outcome — a fresh install
        /// scores nothing — and is why this carries a value rather than being
        /// inferred from `snapshot != nil`.
        case ready(BalanceWebSnapshot)
    }

    private(set) var phase: Phase = .building

    /// What the last build was made of, so a re-render that changed nothing does
    /// not start another. `results` is rebuilt wholesale by `recompute()`, so
    /// identity comparison would rebuild on every refresh regardless of whether
    /// a single number moved.
    @ObservationIgnored private var lastFingerprint: Int?
    @ObservationIgnored private var generation = 0

    var snapshot: BalanceWebSnapshot? {
        if case let .ready(snapshot) = phase { return snapshot }
        return nil
    }

    /// Rebuild if the inputs have actually changed.
    ///
    /// Safe to call from `.task` and from `onChange` — it is idempotent for the
    /// same inputs, which is what lets the view call it without tracking whether
    /// it already has.
    func refresh(results: [InsightResult], changes: [InsightID: ScoreChange]) {
        let fingerprint = Self.fingerprint(results: results, changes: changes)
        guard fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint

        generation += 1
        let generation = self.generation

        // `.userInitiated`: unlike the replays, somebody *is* waiting — this is
        // the thing they opened the tab to see, and it is milliseconds of work.
        Task.detached(priority: .userInitiated) {
            let snapshot = BalanceWebSnapshot.build(results: results, changes: changes)
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.phase = .ready(snapshot)
                }
            }
        }
    }

    /// The scores and the windows they are judged against — the only two things
    /// the shape is made of, so nothing else can force a rebuild.
    private static func fingerprint(results: [InsightResult],
                                    changes: [InsightID: ScoreChange]) -> Int {
        var hasher = Hasher()
        for result in results.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            hasher.combine(result.id)
            hasher.combine(result.score)
            hasher.combine(changes[result.id]?.reference)
            hasher.combine(changes[result.id]?.direction)
        }
        return hasher.finalize()
    }
}
