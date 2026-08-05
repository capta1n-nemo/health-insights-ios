import XCTest
@testable import InsightKit

/// **The graceful-population invariant.** A metric a card reports as a
/// contributor drives the sections keyed on `contributors` — "What goes into
/// this", "How this is weighted", "Full history". A metric a card declares in
/// `candidateMetrics` drives the sections keyed on that — "How you compare",
/// "How far from your normal", the overlay's declared fallback. The cross-card
/// audit found these two lists disagreeing: Body Composition charted the
/// modelled medication level as a contributor while omitting it from
/// `candidateMetrics`, so the same signal showed in three sections and vanished
/// from two.
///
/// The rule that stops it recurring: **every metric a model reports as a
/// contributor must also be a candidate.** Then a scored signal reaches every
/// section that signal belongs in, whichever way a section is keyed — which is
/// the "gracefully populates across the cards" the user asked for.
final class ContributorCandidateTests: XCTestCase {

    func testEveryReportedContributorMetricIsACandidate() {
        let now = TestClock.now
        // **A season, not a fortnight.** "Full coverage" has to mean enough
        // *history* for every registered card, not just enough metrics: a card
        // whose whole point is a month against the months before it cannot
        // contribute to a 20-day fixture, and shortening its window to suit a
        // test would be the test dictating the model.
        var samples = ContributorsFixture.fullCoverage(days: 130, now: now)

        // Metrics the shared fixture omits, added so each model emits its full
        // contributor set — including the modelled medication level, which is
        // the one that broke the invariant and which only appears when its
        // (calculated) samples are present.
        let extra: [MetricType: Double] = [
            .exerciseMinutes: 30, .sleepOnset: -1.0, .sleepEfficiency: 90,
            .sleepDeepMinutes: 80, .sleepRemMinutes: 95, .sleepLatencyMinutes: 12
        ]
        for i in stride(from: 19, through: 0, by: -1) {
            let start = now.addingTimeInterval(-Double(i) * 86_400)
            for (metric, value) in extra {
                samples.append(.init(type: metric, value: value, start: start, source: .oura))
            }
            samples.append(.init(type: .activeMedicationLevel, value: 8,
                                 start: start, source: .calculated))
        }

        let profile = ContributorsFixture.profile(now: now)
        for model in InsightEngine().models {
            let candidates = Set(model.candidateMetrics)
            let result = model.evaluate(samples: samples, profile: profile, now: now)
            for contribution in result.contributors {
                XCTAssertTrue(
                    candidates.contains(contribution.metric),
                    "\(model.id.rawValue) reports \(contribution.metric.rawValue) as a "
                        + "contributor but it is not in candidateMetrics — it will show in "
                        + "the contributor sections and vanish from How-you-compare / "
                        + "How-far-from-normal.")
            }
        }
    }
}
