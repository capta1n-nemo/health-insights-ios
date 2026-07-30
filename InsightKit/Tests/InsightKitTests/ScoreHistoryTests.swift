import XCTest
@testable import InsightKit

private let referenceNow = TestClock.now
private let utc = TestClock.utc
private func daysAgo(_ n: Int) -> Date { TestClock.day(n) }

final class ScoreHistoryTests: XCTestCase {

    /// Readiness inputs for `days` consecutive days.
    ///
    /// The first half sits on a settled baseline; the second half departs from
    /// it, further each day. That shape is deliberate — see
    /// `testRisingHRVReadsAsARisingScore`, where a *linear* ramp would prove
    /// nothing.
    private func improvingHistory(days: Int) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        let settled = days / 2
        for i in stride(from: days - 1, through: 0, by: -1) {
            let elapsed = days - 1 - i                     // 0 = oldest
            let departure = Double(max(0, elapsed - settled))
            // A little jitter so the settled stretch has a real spread to
            // measure a z-score against.
            let jitter = Double(elapsed % 3) - 1
            let date = daysAgo(i)
            out.append(.init(type: .heartRateVariabilityRMSSD,
                             value: 45 + jitter + departure * 2,
                             start: date, source: .oura))
            out.append(.init(type: .restingHeartRate,
                             value: 60 + jitter * 0.5 - departure * 0.4,
                             start: date, source: .oura))
            out.append(.init(type: .sleepDurationHours, value: 7.5,
                             start: date, source: .oura))
        }
        return out
    }

    func testReplayProducesAPointPerDayOnceThereIsEnoughHistory() {
        let history = improvingHistory(days: 20)
        let points = ScoreHistory.replay(model: ReadinessInsight(), samples: history,
                                         profile: UserHealthProfile(), days: 20,
                                         calendar: utc, now: referenceNow)
        XCTAssertGreaterThan(points.count, 10)
        // Strictly increasing dates, one per calendar day.
        let dates = points.map(\.date)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(Set(dates).count, dates.count)
    }

    /// Readiness is measured against your own recent normal, so what lifts it is
    /// *departing* from baseline — not improving at a steady rate.
    ///
    /// Worth stating because it is unintuitive: a perfectly linear ramp produces
    /// a **constant** z-score. Over a ramp of length n the history's mean is n/2
    /// while its SD grows in proportion to n, so z settles near √12/2 ≈ 1.73
    /// whatever n is, and the replayed score comes out flat. An earlier version
    /// of this test ramped linearly and asserted a rising slope; it measured
    /// nothing and CI caught it. Hence `improvingHistory`, which holds a
    /// baseline first and then widens away from it.
    func testRisingHRVReadsAsARisingScore() {
        let points = ScoreHistory.replay(model: ReadinessInsight(),
                                         samples: improvingHistory(days: 30),
                                         profile: UserHealthProfile(), days: 30,
                                         calendar: utc, now: referenceNow)
        XCTAssertGreaterThanOrEqual(points.count, 4)
        let slope = points.trendPerWeek
        XCTAssertNotNil(slope)
        XCTAssertGreaterThan(slope!, 0, "HRV pulling away from baseline should lift readiness")
    }

    /// The companion property, pinned so nobody "fixes" the fixture back.
    func testASteadyLinearRampIsAConstantDepartureNotARisingOne() {
        var linear: [HealthMetricSample] = []
        for i in stride(from: 29, through: 0, by: -1) {
            let step = Double(29 - i)
            linear.append(.init(type: .heartRateVariabilityRMSSD, value: 40 + step,
                                start: daysAgo(i), source: .oura))
            linear.append(.init(type: .restingHeartRate, value: 60 - step * 0.2,
                                start: daysAgo(i), source: .oura))
            linear.append(.init(type: .sleepDurationHours, value: 7.5,
                                start: daysAgo(i), source: .oura))
        }
        let points = ScoreHistory.replay(model: ReadinessInsight(), samples: linear,
                                         profile: UserHealthProfile(), days: 30,
                                         calendar: utc, now: referenceNow)
        XCTAssertGreaterThanOrEqual(points.count, 4)
        XCTAssertEqual(points.trendPerWeek ?? 1, 0, accuracy: 0.05,
                       "a linear ramp holds a constant z, so the score should be flat")
    }

    /// The contract the whole replay rests on: a model is handed only the
    /// samples that existed by the day being replayed. `ReadinessScore` ignores
    /// its `now:` argument and reads `history.last`, so if truncation ever
    /// stopped happening every replayed day would silently show today's score.
    func testAFutureSampleCannotChangeAnEarlierDaysScore() throws {
        let base = improvingHistory(days: 20)
        let withSpike = base + [
            HealthMetricSample(type: .heartRateVariabilityRMSSD, value: 400,
                               start: daysAgo(0), source: .oura)
        ]
        let a = ScoreHistory.replay(model: ReadinessInsight(), samples: base,
                                    profile: UserHealthProfile(), days: 20,
                                    calendar: utc, now: referenceNow)
        let b = ScoreHistory.replay(model: ReadinessInsight(), samples: withSpike,
                                    profile: UserHealthProfile(), days: 20,
                                    calendar: utc, now: referenceNow)
        // Every day but the last must be untouched by a sample dated later.
        let sharedDays = Set(a.dropLast().map(\.date))
        XCTAssertFalse(sharedDays.isEmpty, "fixture produced nothing to compare")
        for day in sharedDays {
            let before = try XCTUnwrap(a.first { $0.date == day }?.score)
            let after = try XCTUnwrap(b.first { $0.date == day }?.score)
            XCTAssertEqual(before, after, accuracy: 1e-9,
                           "a later sample rewrote \(day)")
        }
    }

    func testDaysRestingOnASingleSignalAreSkippedNotScoredAsZero() {
        // Sleep alone: one metric, so never enough to plot.
        let sleepOnly = (0..<20).map { i in
            HealthMetricSample(type: .sleepDurationHours, value: 7.5,
                               start: daysAgo(i), source: .oura)
        }
        let points = ScoreHistory.replay(model: ReadinessInsight(), samples: sleepOnly,
                                         profile: UserHealthProfile(), days: 20,
                                         calendar: utc, now: referenceNow)
        XCTAssertTrue(points.isEmpty)
        XCTAssertFalse(points.contains { $0.score == 0 })
    }

    func testEmptyInputsProduceNoPoints() {
        XCTAssertTrue(ScoreHistory.replay(model: ReadinessInsight(), samples: [],
                                          profile: UserHealthProfile(), days: 30,
                                          calendar: utc, now: referenceNow).isEmpty)
        XCTAssertTrue(ScoreHistory.replay(model: ReadinessInsight(),
                                          samples: improvingHistory(days: 10),
                                          profile: UserHealthProfile(), days: 0,
                                          calendar: utc, now: referenceNow).isEmpty)
    }

    /// A stored point is what the user was actually shown that day, so it must
    /// survive a recomputation that would otherwise rewrite it.
    func testStoredPointsWinOverReplayedOnesForTheSameDay() {
        let day = utc.startOfDay(for: daysAgo(3))
        let replayed = [ScorePoint(date: day, score: 50, confidence: .moderate,
                                   contributorCount: 3)]
        let stored = [ScorePoint(date: day, score: 88, confidence: .high,
                                 contributorCount: 5)]
        let merged = ScoreHistory.merging(replayed: replayed, stored: stored, calendar: utc)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].score, 88, accuracy: 1e-9)
        XCTAssertEqual(merged[0].confidence, .high)
    }

    func testMergingKeepsNonOverlappingDaysFromBothSidesInOrder() {
        let older = ScorePoint(date: utc.startOfDay(for: daysAgo(5)), score: 60,
                               confidence: .high, contributorCount: 4)
        let newer = ScorePoint(date: utc.startOfDay(for: daysAgo(1)), score: 70,
                               confidence: .high, contributorCount: 4)
        let merged = ScoreHistory.merging(replayed: [older], stored: [newer], calendar: utc)
        XCTAssertEqual(merged.map(\.score), [60, 70])
    }

    func testTrendPerWeekRecoversAKnownSlope() {
        // Two points a day apart for two weeks, rising exactly 1/day = 7/week.
        let points = (0..<14).map { i in
            ScorePoint(date: daysAgo(13 - i), score: 50 + Double(i),
                       confidence: .high, contributorCount: 4)
        }
        XCTAssertEqual(points.trendPerWeek!, 7, accuracy: 1e-6)
    }
}
