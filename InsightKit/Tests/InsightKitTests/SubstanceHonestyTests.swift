import XCTest
@testable import InsightKit

/// **"Honest version, always!"** — the reader's standing rule, 2026-08-05, when
/// told their record supports zero confirmed substance responses.
///
/// Independent statistical review of their own export found that with three
/// exposure episodes and roughly eight effective dimensions among the watched
/// metrics, every candidate effect was removable by same-day movement or by
/// sleep duration. The clearest case — heart rate "responding" to stimulants at
/// 0.91 SD — fell to **0.03** once step count entered the model. It was their
/// own movement.
final class SubstanceHonestyTests: XCTestCase {

    private let utc = TestClock.utc

    private func event(_ substance: SubstanceClass, daysAgo: Double) -> SubstanceEvent {
        SubstanceEvent(substance: substance,
                       timestamp: TestClock.now.addingTimeInterval(-daysAgo * 86_400))
    }

    // MARK: - Episodes are occasions, not events and not days

    func testEventsHoursApartAreOneOccasion() {
        let evening = [event(.alcohol, daysAgo: 5.0), event(.alcohol, daysAgo: 4.9),
                       event(.alcohol, daysAgo: 4.8)]
        XCTAssertEqual(SubstanceEpisodes.episodes(events: evening, calendar: utc).count, 1,
                       "three drinks in one evening were counted as three occasions")
    }

    func testEventsWeeksApartAreSeparateOccasions() {
        let spread = [event(.alcohol, daysAgo: 40), event(.alcohol, daysAgo: 20),
                      event(.alcohol, daysAgo: 3)]
        XCTAssertEqual(SubstanceEpisodes.episodes(events: spread, calendar: utc).count, 3)
    }

    /// **Different substances never merge.** Attributing one substance's
    /// response to another is the single most misleading thing this card could
    /// do, and a time-only rule would do it for anyone who mixes.
    func testTwoSubstancesOnOneNightAreTwoOccasions() {
        let mixed = [event(.alcohol, daysAgo: 5), event(.stimulant, daysAgo: 5)]
        let episodes = SubstanceEpisodes.episodes(events: mixed, calendar: utc)
        XCTAssertEqual(episodes.count, 2)
        XCTAssertEqual(Set(episodes.map(\.substance)), [.alcohol, .stimulant])
    }

    // MARK: - The gate

    /// Below three occasions the card must not call anything a response.
    func testUnderThreeOccasionsNothingIsCalledAResponse() {
        let result = SubstanceImpactInsight(events: [event(.stimulant, daysAgo: 3)])
            .evaluate(samples: [], profile: .init(), now: TestClock.now)
        let text = result.explanation.lowercased()
        XCTAssertTrue(text.contains("not enough yet") || text.contains("one occasion"), text)
        XCTAssertTrue(text.contains("counted rather than estimated"),
                      "the card did not distinguish the counted half from the inferred half: \(text)")
    }

    /// ⚠️ **The daily user must still get a number.** Withholding the score
    /// entirely below three occasions looks principled and breaks the card for
    /// the person it is most for: under any gap rule, using most evenings is one
    /// continuous episode forever. Exposure is counted, not inferred, so it is
    /// honest at any n — it is the *response* that needs replication.
    func testADailyUserStillGetsALoadScore() throws {
        let daily = SubstanceImpactInsight(
            events: (0..<10).map { event(.stimulant, daysAgo: Double($0)) })
        let result = daily.evaluate(samples: [], profile: .init(), now: TestClock.now)
        XCTAssertEqual(SubstanceEpisodes.episodes(events: (0..<10).map { event(.stimulant, daysAgo: Double($0)) },
                                                  calendar: utc).count, 1,
                       "this fixture no longer models a daily user, so it proves nothing")
        XCTAssertNotNil(try? XCTUnwrap(result.score),
                        "a daily user has no score at all, so the card can never tell them they are overdoing it")
    }

    /// Heavier use still scores worse than lighter use — the load half has to
    /// keep working while the response half is withheld.
    func testHeavierUseStillScoresWorseWhileUnderTheGate() throws {
        let heavy = SubstanceImpactInsight(
            events: (0..<10).map { event(.stimulant, daysAgo: Double($0)) })
        let light = SubstanceImpactInsight(events: [event(.caffeine, daysAgo: 6)])
        let heavyScore = try XCTUnwrap(heavy.evaluate(samples: [], profile: .init(), now: TestClock.now).score)
        let lightScore = try XCTUnwrap(light.evaluate(samples: [], profile: .init(), now: TestClock.now).score)
        XCTAssertLessThan(heavyScore, lightScore)
    }

    // MARK: - Every row names what else could explain it

    /// This is the mechanism, not a disclaimer: it is what would have stopped
    /// the card reporting the reader's own step count as a stimulant response.
    func testCardiacAndSleepRowsNameTheirConfounder() {
        XCTAssertEqual(SubstanceEpisodes.alternativeExplanation(for: .restingHeartRate),
                       "how much you moved that day")
        XCTAssertEqual(SubstanceEpisodes.alternativeExplanation(for: .heartRate),
                       "how much you moved that day")
        XCTAssertEqual(SubstanceEpisodes.alternativeExplanation(for: .sleepDeepMinutes),
                       "how long you slept")
    }

    /// A metric with no well-measured alternative gets none rather than a
    /// plausible-sounding guess — inventing a confounder is its own dishonesty.
    func testAMetricWithNoKnownConfounderGetsNoClause() {
        XCTAssertNil(SubstanceEpisodes.alternativeExplanation(for: .bodyMass))
    }
}
