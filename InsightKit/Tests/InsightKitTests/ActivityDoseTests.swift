import XCTest
@testable import InsightKit

final class ActivityDoseTests: XCTestCase {

    private let now = TestClock.day(0)

    /// Exercise-time samples as HealthKit writes them: several accrual
    /// intervals per active day, none on rest days.
    private func week(minutesByDayAgo: [Int: [Double]]) -> [HealthMetricSample] {
        minutesByDayAgo.flatMap { daysAgo, chunks in
            chunks.enumerated().map { index, minutes in
                HealthMetricSample(
                    type: .exerciseMinutes, value: minutes,
                    start: TestClock.day(daysAgo).addingTimeInterval(Double(8 + index) * 3600),
                    source: .appleHealthDevice("Apple Watch"))
            }
        }
    }

    // MARK: - The curve, at the guideline's own anchors

    func testTheCurveHitsTheGuidelineAnchors() {
        XCTAssertEqual(ActivityDoseModel.score(weeklyMinutes: 0), 20)
        XCTAssertEqual(ActivityDoseModel.score(weeklyMinutes: 150), 75)
        XCTAssertEqual(ActivityDoseModel.score(weeklyMinutes: 300), 100)
        XCTAssertEqual(ActivityDoseModel.score(weeklyMinutes: 600), 100,
                       "WHO states extra benefit past 300 but no longer quantifies it — the curve holds rather than climbs")
    }

    func testTheCurveIsMonotone() {
        let scores = stride(from: 0.0, through: 500, by: 5)
            .map { ActivityDoseModel.score(weeklyMinutes: $0) }
        for (a, b) in zip(scores, scores.dropFirst()) {
            XCTAssertLessThanOrEqual(a, b)
        }
    }

    // MARK: - The weekly read

    func testAWeekSumsAcrossItsDaysWithMissingDaysAsZero() throws {
        // Three active days totalling 150 — rest days count as zero, so this
        // is exactly the guideline floor, not 150 scaled up.
        let samples = week(minutesByDayAgo: [1: [30, 20], 3: [60], 5: [40]])
        let output = try XCTUnwrap(ActivityDoseModel.evaluate(samples: samples, now: now))
        XCTAssertEqual(output.weeklyMinutes, 150, accuracy: 0.001)
        XCTAssertEqual(output.recordedDays, 3)
        XCTAssertEqual(output.score, 75, accuracy: 0.001)
    }

    func testTooFewRecordedDaysCannotBeJudged() {
        // A watch worn twice in a week: missing-as-zero would be a damning
        // number built on absence, so the answer is no number at all.
        let samples = week(minutesByDayAgo: [1: [45], 4: [30]])
        XCTAssertNil(ActivityDoseModel.evaluate(samples: samples, now: now))
    }

    func testOldActivityIsOutsideTheWeek() throws {
        var samples = week(minutesByDayAgo: [1: [30], 2: [30], 3: [30]])
        samples += week(minutesByDayAgo: [20: [300]])
        let output = try XCTUnwrap(ActivityDoseModel.evaluate(samples: samples, now: now))
        XCTAssertEqual(output.weeklyMinutes, 90, accuracy: 0.001,
                       "a fortnight-old workout must not count toward this week's dose")
    }

    func testTwoDevicesDoNotDoubleCountTheSameWorkout() throws {
        // Watch and phone both record the morning — `dailySeries` means across
        // sources, so the day reads once, not twice.
        var samples = week(minutesByDayAgo: [1: [40], 2: [40], 3: [40]])
        samples += samples.map {
            HealthMetricSample(type: .exerciseMinutes, value: $0.value,
                               start: $0.start, source: .appleHealthDevice("iPhone"))
        }
        let output = try XCTUnwrap(ActivityDoseModel.evaluate(samples: samples, now: now))
        XCTAssertEqual(output.weeklyMinutes, 120, accuracy: 0.001)
    }

    // MARK: - On the card

    private func profile(age: Double = 40, male: Bool = true) -> UserHealthProfile {
        var p = UserHealthProfile()
        p.set(.init(kind: .dateOfBirth,
                    value: now.addingTimeInterval(-age * 365.2425 * 86_400).timeIntervalSince1970,
                    recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: male ? 0 : 1, recordedAt: now))
        return p
    }

    func testFitnessContributorsCarryTheDoseAtItsWeight() throws {
        var samples = week(minutesByDayAgo: [1: [60, 40], 2: [60], 3: [60], 5: [80]])
        // Enough VO₂max history for the card to score at all.
        for week in 0..<8 {
            samples.append(HealthMetricSample(
                type: .vo2Max, value: 40,
                start: TestClock.day(week * 7), source: .appleHealthDevice("Apple Watch")))
        }
        let result = FitnessInsight().evaluate(samples: samples, profile: profile(),
                                               now: now)
        let dose = try XCTUnwrap(result.contributors.first { $0.metric == .exerciseMinutes },
                                 "a judged week must reach 'What goes into this'")
        XCTAssertGreaterThan(dose.weight, 0)
        XCTAssertEqual(result.contributors.filter { $0.metric == .exerciseMinutes }.count, 1,
                       "the primary term wins; the supporting duplicate must be dropped")
        XCTAssertTrue(result.driverLines.contains { $0.text.contains("this week") },
                      "the weekly line is the card's one sentence about this week")
    }

    /// "Steps: 224 · 1.5 SD below your normal", exported at breakfast — a
    /// partial day judged against complete ones reads catastrophic every
    /// morning. Cumulative metrics are judged on the last complete day.
    func testAPartialDayOfStepsIsNotJudgedAsALowDay() throws {
        var samples: [HealthMetricSample] = []
        for day in 1...14 {
            // Some spread, or the baseline has no SD and nothing can be judged.
            samples.append(HealthMetricSample(
                type: .stepCount, value: 8000 + Double(day % 5) * 400,
                start: TestClock.day(day), source: .appleHealthDevice("iPhone")))
        }
        // This morning: 224 steps so far. TestClock.now is mid-day, so the
        // day-0 bucket is genuinely partial.
        samples.append(HealthMetricSample(
            type: .stepCount, value: 224,
            start: TestClock.utc.startOfDay(for: TestClock.now).addingTimeInterval(8 * 3600),
            source: .appleHealthDevice("iPhone")))

        let terms = FitnessInsight.supportingTerms(samples: samples, now: TestClock.now,
                                                   calendar: TestClock.utc)
        let steps = try XCTUnwrap(terms.first { $0.metric == .stepCount })
        XCTAssertFalse(steps.detail.contains("224"),
                       "this morning's partial total must not be the judged value: \(steps.detail)")
        XCTAssertGreaterThan(steps.score, 30,
                             "yesterday's complete day is ordinary; 224 against an 8k baseline would score ~0")
    }

    func testAWatchlessProfileScoresExactlyAsBefore() {
        // No exercise data at all: the dose term must renormalise away, not
        // drag the score with a phantom zero.
        var samples: [HealthMetricSample] = []
        for week in 0..<8 {
            samples.append(HealthMetricSample(
                type: .vo2Max, value: 40,
                start: TestClock.day(week * 7), source: .appleHealthDevice("Apple Watch")))
        }
        let result = FitnessInsight().evaluate(samples: samples, profile: profile(),
                                               now: now)
        XCTAssertNotNil(result.score)
        XCTAssertFalse(result.contributors.contains { $0.metric == .exerciseMinutes })
    }
}
