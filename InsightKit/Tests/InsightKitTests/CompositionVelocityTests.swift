import XCTest
@testable import InsightKit

/// The card scored a level and nothing else: twelve kilograms down over three
/// months scored identically to never having moved. These pin the rate and the
/// quality of the change, and the published bands they are judged against.
final class CompositionVelocityTests: XCTestCase {

    private let calendar = Calendar.current
    private var now: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
        .addingTimeInterval(20 * 3600) }

    private func day(_ back: Int) -> Date {
        calendar.startOfDay(for: now).addingTimeInterval(-Double(back) * 86_400 + 8 * 3600)
    }

    // `falling(from:kgPerWeek:days:)` lived here and was deleted on 2026-08-07:
    // zero callers since the rewrite into `series(_:start:kgPerWeek:days:)`, and
    // its value expression had decayed to
    // `start + kgPerWeek * weeks * -1 * -1 + kgPerWeek * 0` — arithmetic noise
    // that reads as a sign convention and is none. Dead test code is worse than
    // dead production code: nothing compiles against it, so nothing objects.

    /// Explicit: value at `back` days ago is `start - kgPerWeek*(days-back)/7`,
    /// so the newest reading is the lightest when `kgPerWeek` is positive.
    private func series(_ metric: MetricType, start: Double, kgPerWeek: Double,
                        days: Int = 56) -> [HealthMetricSample] {
        (0..<days).map { back in
            let weeksAgo = Double(back) / 7
            return HealthMetricSample(type: metric,
                                      value: start + kgPerWeek * weeksAgo,
                                      start: day(back), source: .withings)
        }
    }

    // MARK: - The fit

    func testASteadyLossIsMeasuredAtItsRealRate() throws {
        // +0.5 kg per week *ago* means −0.5 kg/week going forward.
        let samples = series(.bodyMass, start: 110, kgPerWeek: 0.5)
        let velocity = try XCTUnwrap(CompositionVelocityModel.evaluate(
            samples: samples, now: now, calendar: calendar))
        XCTAssertEqual(velocity.kilogramsPerWeek, -0.5, accuracy: 0.06)
        XCTAssertEqual(velocity.percentPerWeek, -0.5 / 110 * 100, accuracy: 0.06)
        XCTAssertTrue(velocity.isMoving)
        XCTAssertLessThan(velocity.residualSD, 0.5, "a clean line has little scatter")
    }

    func testTooFewWeighInsIsNoVelocity() {
        let samples = series(.bodyMass, start: 110, kgPerWeek: 0.5, days: 3)
        XCTAssertNil(CompositionVelocityModel.evaluate(samples: samples, now: now,
                                                       calendar: calendar))
    }

    /// Daily scale noise is water, not tissue — smoothing is what stops the
    /// slope reporting hydration.
    func testDailyWaterSwingDoesNotBecomeATrend() throws {
        var samples: [HealthMetricSample] = []
        for back in 0..<56 {
            let swing = back % 2 == 0 ? 1.2 : -1.2      // ±1.2 kg day to day
            samples.append(.init(type: .bodyMass, value: 110 + swing,
                                 start: day(back), source: .withings))
        }
        let velocity = try XCTUnwrap(CompositionVelocityModel.evaluate(
            samples: samples, now: now, calendar: calendar))
        XCTAssertEqual(velocity.kilogramsPerWeek, 0, accuracy: 0.15,
                       "a flat but noisy scale is not a trend")
    }

    // MARK: - Quality of the change

    func testLeanShareOfLossIsReported() throws {
        // Losing 1 kg/week of which 0.2 kg is lean — a good ratio.
        let samples = series(.bodyMass, start: 110, kgPerWeek: 1.0)
            + series(.leanBodyMass, start: 77, kgPerWeek: 0.2)
        let velocity = try XCTUnwrap(CompositionVelocityModel.evaluate(
            samples: samples, now: now, calendar: calendar))
        let share = try XCTUnwrap(velocity.leanShareOfChange)
        XCTAssertEqual(share, 0.2, accuracy: 0.05)
        let quality = try XCTUnwrap(CompositionVelocityModel.qualityScore(
            leanShareOfChange: share, isLosing: true))
        XCTAssertGreaterThan(quality, 90, "a fifth of the loss being lean is good")
    }

    func testLosingMostlyMuscleScoresBadly() throws {
        let quality = try XCTUnwrap(CompositionVelocityModel.qualityScore(
            leanShareOfChange: 0.6, isLosing: true))
        XCTAssertLessThan(quality, 40)
        let good = try XCTUnwrap(CompositionVelocityModel.qualityScore(
            leanShareOfChange: 0.25, isLosing: true))
        // This read `XCTAssertGreaterThan(good, good > quality ? quality : 0)`,
        // which asserts `good > 0` in the only case it was meant to catch — it
        // could never fail in the direction it reads as testing.
        XCTAssertGreaterThan(good, quality,
                             "losing a quarter lean must score better than losing "
                             + "three fifths lean")
        XCTAssertGreaterThan(good, 80, "inside the expected 20–30% is fine")
    }

    /// Lean *gained* while the weight falls is the best outcome available.
    func testHoldingLeanWhileLosingIsFullMarks() throws {
        let quality = try XCTUnwrap(CompositionVelocityModel.qualityScore(
            leanShareOfChange: -0.1, isLosing: true))
        XCTAssertEqual(quality, 100)
    }

    /// A stable weight has no ratio: dividing a lean slope by a weight slope
    /// that is noise manufactures a number out of nothing.
    func testAStableWeightHasNoLeanShare() throws {
        let samples = series(.bodyMass, start: 110, kgPerWeek: 0)
            + series(.leanBodyMass, start: 77, kgPerWeek: 0.05)
        let velocity = try XCTUnwrap(CompositionVelocityModel.evaluate(
            samples: samples, now: now, calendar: calendar))
        XCTAssertFalse(velocity.isMoving)
        XCTAssertNil(velocity.leanShareOfChange)
    }

    // MARK: - Rate against the goal

    func testTheIdealLossRateScoresBest() {
        let ideal = CompositionVelocityModel.rateScore(percentPerWeek: -0.75, goal: .lose)
        XCTAssertGreaterThan(ideal, 99)
        let sluggish = CompositionVelocityModel.rateScore(percentPerWeek: -0.1, goal: .lose)
        let tooFast = CompositionVelocityModel.rateScore(percentPerWeek: -2.0, goal: .lose)
        XCTAssertLessThan(sluggish, ideal)
        XCTAssertLessThan(tooFast, sluggish,
                          "overshooting the safe band costs more than standing still")
    }

    /// The whole point of asking for a goal: the same number reads oppositely.
    func testTheSameRateReadsOppositelyUnderOppositeGoals() {
        let losing = -0.75
        XCTAssertGreaterThan(CompositionVelocityModel.rateScore(percentPerWeek: losing, goal: .lose),
                             90)
        XCTAssertLessThan(CompositionVelocityModel.rateScore(percentPerWeek: losing, goal: .gain),
                          25, "losing when you meant to gain is the wrong direction, not slow progress")
        let maintaining = CompositionVelocityModel.rateScore(percentPerWeek: losing, goal: .maintain)
        XCTAssertLessThan(maintaining, 65, "drifting off a maintenance goal costs")
        XCTAssertGreaterThan(maintaining, 30, "…but drifting is not the same as the wrong way")
    }

    /// With no goal stated the card judges safety alone — it must not assume
    /// that a falling weight was wanted.
    func testWithoutAGoalOnlyUnsafeRatesCost() {
        XCTAssertEqual(CompositionVelocityModel.rateScore(percentPerWeek: -0.75, goal: nil), 100)
        XCTAssertEqual(CompositionVelocityModel.rateScore(percentPerWeek: 0.75, goal: nil), 100,
                       "gaining at the same rate is equally unremarkable without a goal")
        XCTAssertLessThan(CompositionVelocityModel.rateScore(percentPerWeek: -2.5, goal: nil), 40,
                          "…but a very fast change is worth flagging either way")
    }

    // MARK: - What the card says

    func testThePhraseNamesTheRateAndTheGuidance() throws {
        let samples = series(.bodyMass, start: 110, kgPerWeek: 0.9)
        let velocity = try XCTUnwrap(CompositionVelocityModel.evaluate(
            samples: samples, now: now, calendar: calendar))
        let phrase = CompositionVelocityModel.phrase(velocity, goal: .lose)
        XCTAssertTrue(phrase.contains("down"), phrase)
        XCTAssertTrue(phrase.contains("0.5–1%"), phrase)
    }

    func testAStableWeightSaysSo() throws {
        let samples = series(.bodyMass, start: 110, kgPerWeek: 0)
        let velocity = try XCTUnwrap(CompositionVelocityModel.evaluate(
            samples: samples, now: now, calendar: calendar))
        XCTAssertTrue(CompositionVelocityModel.phrase(velocity, goal: .maintain)
            .contains("Holding steady"))
    }
}

/// The card as a whole, after velocity joined the pool.
final class BodyCompositionVelocityScoringTests: XCTestCase {

    private let calendar = Calendar.current
    private var now: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
        .addingTimeInterval(20 * 3600) }

    private func profile(goal: WeightGoal?) -> UserHealthProfile {
        var p = UserHealthProfile()
        p.set(.init(kind: .dateOfBirth,
                    value: now.addingTimeInterval(-28 * 365.2425 * 86_400).timeIntervalSince1970,
                    recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: 0, recordedAt: now))
        if let goal { p.set(.init(kind: .weightGoal, value: goal.rawValue, recordedAt: now)) }
        return p
    }

    private func history(weightPerWeekAgo: Double, leanPerWeekAgo: Double,
                         bodyFat: Double) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        for back in 0..<56 {
            let weeksAgo = Double(back) / 7
            let start = calendar.startOfDay(for: now)
                .addingTimeInterval(-Double(back) * 86_400 + 8 * 3600)
            out.append(.init(type: .bodyMass, value: 110 + weightPerWeekAgo * weeksAgo,
                             start: start, source: .withings))
            out.append(.init(type: .leanBodyMass, value: 77 + leanPerWeekAgo * weeksAgo,
                             start: start, source: .withings))
            out.append(.init(type: .bodyFatPercentage, value: bodyFat,
                             start: start, source: .withings))
        }
        out.append(.init(type: .height, value: 1.85,
                         start: calendar.startOfDay(for: now), source: .withings))
        return out
    }

    /// **The requirement, in one test.** Two readers at the same body fat, one
    /// losing well and one static. The card scored them identically before
    /// velocity joined the pool.
    func testLosingWellOutscoresStandingStillAtTheSameBodyFat() throws {
        let insight = BodyCompositionInsight()
        let losing = insight.evaluate(
            samples: history(weightPerWeekAgo: 0.8, leanPerWeekAgo: 0.15, bodyFat: 30.6),
            profile: profile(goal: .lose), now: now)
        let static_ = insight.evaluate(
            samples: history(weightPerWeekAgo: 0, leanPerWeekAgo: 0, bodyFat: 30.6),
            profile: profile(goal: .lose), now: now)

        let losingScore = try XCTUnwrap(losing.score)
        let staticScore = try XCTUnwrap(static_.score)
        XCTAssertGreaterThan(losingScore, staticScore + 8,
                             "the same body fat, and only one of them is going anywhere")
    }

    /// Losing fast and mostly from muscle must score below losing well.
    func testLosingMuscleFastScoresBelowLosingFatSteadily() throws {
        let insight = BodyCompositionInsight()
        let good = insight.evaluate(
            samples: history(weightPerWeekAgo: 0.8, leanPerWeekAgo: 0.15, bodyFat: 30.6),
            profile: profile(goal: .lose), now: now)
        let crash = insight.evaluate(
            samples: history(weightPerWeekAgo: 2.5, leanPerWeekAgo: 1.6, bodyFat: 30.6),
            profile: profile(goal: .lose), now: now)
        XCTAssertGreaterThan(try XCTUnwrap(good.score), try XCTUnwrap(crash.score))
    }

    /// The level is still the largest single term — the user's 0.45.
    func testBodyFatRemainsTheHeaviestSingleInput() throws {
        let result = BodyCompositionInsight().evaluate(
            samples: history(weightPerWeekAgo: 0.8, leanPerWeekAgo: 0.15, bodyFat: 30.6),
            profile: profile(goal: .lose), now: now)
        let heaviest = result.weightedFactors.max { $0.weight < $1.weight }
        XCTAssertEqual(heaviest?.metric, .bodyFatPercentage)
        XCTAssertEqual(BodyCompositionInsight.levelWeight, 0.45, accuracy: 1e-9)
    }

    /// Muscle mass no longer carries a share of its own — it is lean tissue
    /// counted a second time.
    func testMuscleMassIsNotWeightedBesideLeanMass() {
        XCTAssertFalse(BodyCompositionInsight.supportingMetrics.contains { $0.0 == .muscleMass })
        XCTAssertTrue(BodyCompositionInsight.supportingMetrics.contains { $0.0 == .leanBodyMass })
    }

    /// A card with no weight history at all still scores on the level alone.
    func testACardWithNoTrendStillScores() throws {
        let samples: [HealthMetricSample] = [
            .init(type: .bodyMass, value: 110, start: now, source: .withings),
            .init(type: .bodyFatPercentage, value: 30.6, start: now, source: .withings),
            .init(type: .height, value: 1.85, start: now, source: .withings)
        ]
        let result = BodyCompositionInsight().evaluate(
            samples: samples, profile: profile(goal: nil), now: now)
        XCTAssertNotNil(result.score)
    }
}
