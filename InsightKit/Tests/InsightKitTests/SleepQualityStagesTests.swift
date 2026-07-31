import XCTest
@testable import InsightKit

private let sqNow = TestClock.now

/// The stage breakdown Oura, Whoop and Apple have all been sending and the
/// parsers were discarding. Sleep Quality scored a night by its length and its
/// breathing while the composition of that night sat unread in the same payload.
final class SleepQualityStagesTests: XCTestCase {

    /// `nights` of `hours` sleep, with an optional stage breakdown on the most
    /// recent one.
    private func samples(hours: Double, nights: Int = 8,
                         efficiency: Double? = nil,
                         deepMinutes: Double? = nil,
                         remMinutes: Double? = nil) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        for night in 0..<nights {
            out.append(HealthMetricSample(type: .sleepDurationHours, value: hours,
                                          start: TestClock.day(night), source: .oura))
        }
        if let efficiency {
            out.append(HealthMetricSample(type: .sleepEfficiency, value: efficiency,
                                          start: TestClock.day(0), source: .oura))
        }
        if let deepMinutes {
            out.append(HealthMetricSample(type: .sleepDeepMinutes, value: deepMinutes,
                                          start: TestClock.day(0), source: .oura))
        }
        if let remMinutes {
            out.append(HealthMetricSample(type: .sleepRemMinutes, value: remMinutes,
                                          start: TestClock.day(0), source: .oura))
        }
        return out
    }

    private func evaluate(_ samples: [HealthMetricSample]) -> InsightResult {
        SleepQualityInsight().evaluate(samples: samples, profile: .init(), now: sqNow)
    }

    /// The design decision worth pinning. A six-hour sleeper with textbook
    /// proportions has a *duration* problem, which the duration term is already
    /// scoring — charging them again on composition would be double-counting
    /// one short night, which is exactly the class of bug this app has had to
    /// unpick before.
    func testCompositionIsScoredAsAShareNotAsMinutes() throws {
        // Both nights have identical proportions: 40% of the night deep + REM.
        let long = evaluate(samples(hours: 8, deepMinutes: 96, remMinutes: 96))
        let short = evaluate(samples(hours: 5, deepMinutes: 60, remMinutes: 60))

        let longRestorative = try XCTUnwrap(
            long.drivers.first { $0.contains("Deep and REM") })
        let shortRestorative = try XCTUnwrap(
            short.drivers.first { $0.contains("Deep and REM") })
        // Same share, so the same sentence about the share.
        XCTAssertTrue(longRestorative.contains("40%"), longRestorative)
        XCTAssertTrue(shortRestorative.contains("40%"), shortRestorative)
        // And the short night still scores worse — on duration, where it should.
        XCTAssertLessThan(try XCTUnwrap(short.score), try XCTUnwrap(long.score))
    }

    func testAPoorlyProportionedNightScoresBelowAWellProportionedOne() throws {
        let typical = evaluate(samples(hours: 8, deepMinutes: 96, remMinutes: 96))
        let thin = evaluate(samples(hours: 8, deepMinutes: 20, remMinutes: 25))
        XCTAssertLessThan(try XCTUnwrap(thin.score), try XCTUnwrap(typical.score))
    }

    func testEfficiencyMovesTheScoreAndIsNamed() throws {
        let good = evaluate(samples(hours: 8, efficiency: 93))
        let poor = evaluate(samples(hours: 8, efficiency: 68))
        XCTAssertLessThan(try XCTUnwrap(poor.score), try XCTUnwrap(good.score))
        XCTAssertTrue(good.drivers.contains { $0.contains("Efficiency") },
                      "the user has to be able to see what moved it")
    }

    /// Absent stage data must not be penalised — most of the world has a phone
    /// and no ring, and a night with no breakdown is not a bad night.
    func testANightWithNoBreakdownIsNotPunished() throws {
        let bare = try XCTUnwrap(evaluate(samples(hours: 8)).score)
        let full = try XCTUnwrap(
            evaluate(samples(hours: 8, efficiency: 88, deepMinutes: 96, remMinutes: 96)).score)
        XCTAssertEqual(bare, full, accuracy: 12,
                       "a missing breakdown should be neutral, not a penalty")
    }

    /// Contributors drive the detail chart, so a term that moved the score has
    /// to appear as a line — and one that had no reading must not.
    func testOnlyMeasuredStagesBecomeContributors() {
        let withStages = evaluate(samples(hours: 8, efficiency: 90, deepMinutes: 90,
                                          remMinutes: 90))
        let metrics = Set(withStages.contributors.map(\.metric))
        XCTAssertTrue(metrics.isSuperset(of: [.sleepEfficiency, .sleepDeepMinutes,
                                              .sleepRemMinutes]))

        let without = evaluate(samples(hours: 8))
        XCTAssertFalse(Set(without.contributors.map(\.metric)).contains(.sleepEfficiency))
    }

    /// Contributors must stay a subset of what the model declares it may read.
    func testContributorsStayWithinCandidateMetrics() {
        let result = evaluate(samples(hours: 8, efficiency: 90, deepMinutes: 90,
                                      remMinutes: 90))
        let candidates = Set(SleepQualityInsight().candidateMetrics)
        for contribution in result.contributors {
            XCTAssertTrue(candidates.contains(contribution.metric), "\(contribution.metric)")
        }
    }
}
