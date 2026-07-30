import XCTest
@testable import InsightKit

/// A fixed "now" and a UTC calendar, because the replay walks calendar days and
/// a machine in a different zone would bucket them differently.
private let referenceNow = Date(timeIntervalSince1970: 1_700_000_000)
private var utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// `daysAgo` before the reference, at midday so a day boundary can't straddle it.
private func daysAgo(_ n: Int) -> Date {
    utc.startOfDay(for: referenceNow.addingTimeInterval(-Double(n) * 86_400))
        .addingTimeInterval(12 * 3600)
}

final class ScoreHistoryTests: XCTestCase {

    /// Readiness inputs for `days` consecutive days, HRV climbing over the run.
    private func climbingHistory(days: Int) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        for i in stride(from: days - 1, through: 0, by: -1) {
            let step = Double(days - 1 - i)
            let date = daysAgo(i)
            out.append(.init(type: .heartRateVariabilityRMSSD, value: 40 + step,
                             start: date, source: .oura))
            out.append(.init(type: .restingHeartRate, value: 60 - step * 0.2,
                             start: date, source: .oura))
            out.append(.init(type: .sleepDurationHours, value: 7.5,
                             start: date, source: .oura))
        }
        return out
    }

    func testReplayProducesAPointPerDayOnceThereIsEnoughHistory() {
        let history = climbingHistory(days: 20)
        let points = ScoreHistory.replay(model: ReadinessInsight(), samples: history,
                                         profile: UserHealthProfile(), days: 20,
                                         calendar: utc, now: referenceNow)
        XCTAssertGreaterThan(points.count, 10)
        // Strictly increasing dates, one per calendar day.
        let dates = points.map(\.date)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(Set(dates).count, dates.count)
    }

    func testRisingHRVReadsAsARisingScore() {
        let points = ScoreHistory.replay(model: ReadinessInsight(),
                                         samples: climbingHistory(days: 30),
                                         profile: UserHealthProfile(), days: 30,
                                         calendar: utc, now: referenceNow)
        XCTAssertGreaterThanOrEqual(points.count, 4)
        let slope = points.trendPerWeek
        XCTAssertNotNil(slope)
        XCTAssertGreaterThan(slope!, 0, "HRV climbing every day should lift readiness")
    }

    /// The contract the whole replay rests on: a model is handed only the
    /// samples that existed by the day being replayed. `ReadinessScore` ignores
    /// its `now:` argument and reads `history.last`, so if truncation ever
    /// stopped happening every replayed day would silently show today's score.
    func testAFutureSampleCannotChangeAnEarlierDaysScore() throws {
        let base = climbingHistory(days: 20)
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
                                          samples: climbingHistory(days: 10),
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
