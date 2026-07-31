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
        SleepInsight().evaluate(samples: samples, profile: .init(), now: sqNow)
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

    /// A contributor's `weight` and the coefficient the score actually applies
    /// are two statements of one number — the score uses one, the detail chart
    /// and the "what's driving this" breakdown use the other. They drifted apart
    /// the moment the terms were rebalanced to make room for the stage
    /// breakdown: blood oxygen kept a declared 0.15 while the score had moved to
    /// 0.09, so the chart would have over-credited it by two thirds.
    ///
    /// Summing to one is the cheapest statement of that invariant which does not
    /// require the test to restate the whole weight table — and it is enough,
    /// because a mismatch in any single term breaks the sum.
    func testContributorWeightsMatchTheWeightsTheScoreApplies() throws {
        // Every term reporting, so every weight is in play. A term that is
        // absent simply omits its contributor, which is correct and is why the
        // fixture has to be complete for this assertion to mean anything.
        var full = samples(hours: 8, efficiency: 88, deepMinutes: 96, remMinutes: 96)
        full.append(HealthMetricSample(type: .respiratoryRate, value: 14,
                                       start: TestClock.day(0), source: .oura))
        full.append(HealthMetricSample(type: .oxygenSaturation, value: 97,
                                       start: TestClock.day(0), source: .oura))
        full.append(HealthMetricSample(type: .skinTemperatureDeviation, value: 0.1,
                                       start: TestClock.day(0), source: .oura))
        // Bedtimes, so the regularity term is in play too. It arrived when
        // Sleep Regularity merged into this card, and without it the fixture
        // would be one term short of complete — which is exactly what this
        // assertion is for.
        for night in 0..<8 {
            let bedtime = TestClock.day(night).addingTimeInterval(-12 * 3600)
                .addingTimeInterval(23 * 3600)
            full.append(HealthMetricSample(
                type: .sleepOnset,
                value: SleepOnset.hoursFromMidnight(bedtime, calendar: TestClock.utc) ?? 0,
                start: SleepOnset.night(of: bedtime, calendar: TestClock.utc),
                source: .oura))
        }
        let result = SleepInsight().evaluate(samples: full, profile: .init(),
                                                    now: sqNow)
        XCTAssertEqual(result.contributors.count, 8,
                       "a term stopped contributing — update the expected sum below deliberately")
        let total = result.contributors.map(\.weight).reduce(0, +)
        XCTAssertEqual(total, 1.0, accuracy: 0.001,
                       "declared contributor weights must sum to the score's own coefficients")
    }

    /// The sum test above is a floor, not the invariant.
    ///
    /// Summing the declared weights catches a term whose declaration drifted on
    /// its own — which is the bug that actually happened. It is blind to a
    /// *swap*: move 0.06 from respiratory rate to blood oxygen in both the
    /// declaration and nowhere else, and the sum is still 1.0 while the chart
    /// now over-credits one signal and under-credits the other.
    ///
    /// This measures the real thing without parsing source: hold every input
    /// fixed, move one of them, and check that the score moves by the declared
    /// weight times the sub-score's own change. Δscore ÷ Δsub-score *is* the
    /// applied coefficient, by definition.
    func testBloodOxygenMovesTheScoreByExactlyItsDeclaredWeight() throws {
        func evaluateWith(spo2: Double) -> InsightResult {
            var s = samples(hours: 8, efficiency: 88, deepMinutes: 96, remMinutes: 96)
            s.append(HealthMetricSample(type: .oxygenSaturation, value: spo2,
                                        start: TestClock.day(0), source: .oura))
            return SleepInsight().evaluate(samples: s, profile: .init(), now: sqNow)
        }
        // Two saturations either side of a band edge, so the sub-score moves by
        // a known amount: 97% scores 100, 93% scores 60 (see `oxygenScore`).
        let high = try XCTUnwrap(evaluateWith(spo2: 97).score)
        let low = try XCTUnwrap(evaluateWith(spo2: 93).score)
        let declared = try XCTUnwrap(
            evaluateWith(spo2: 97).contributors.first { $0.metric == .oxygenSaturation }).weight

        let appliedCoefficient = (high - low) / (100.0 - 60.0)
        XCTAssertEqual(appliedCoefficient, declared, accuracy: 0.005,
                       "the score moves by \(appliedCoefficient) per point of blood-oxygen sub-score, but the card declares \(declared) — the chart and the score disagree about how much this signal counts")
    }

    /// Contributors must stay a subset of what the model declares it may read.
    func testContributorsStayWithinCandidateMetrics() {
        let result = evaluate(samples(hours: 8, efficiency: 90, deepMinutes: 90,
                                      remMinutes: 90))
        let candidates = Set(SleepInsight().candidateMetrics)
        for contribution in result.contributors {
            XCTAssertTrue(candidates.contains(contribution.metric), "\(contribution.metric)")
        }
    }
}
