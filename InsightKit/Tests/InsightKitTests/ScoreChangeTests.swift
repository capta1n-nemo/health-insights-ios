import XCTest
@testable import InsightKit

private let trendNow = TestClock.now
private let trendCalendar = TestClock.utc

/// Direction next to a score, and the restraint that makes it worth reading.
///
/// The survey behind the design: no major health app renders a day-over-day
/// delta on a daily score, because day-to-day HRV variability (3–13% depending
/// on method) swamps what a single night actually changes.
final class ScoreChangeTests: XCTestCase {

    /// Scores counting back from today, oldest first. Index 0 is `daysBack`
    /// days ago; the last entry is today.
    private func history(_ scores: [Double]) -> [ScorePoint] {
        let today = trendCalendar.startOfDay(for: trendNow)
        return scores.enumerated().map { index, score in
            ScorePoint(date: today.addingTimeInterval(-Double(scores.count - 1 - index) * 86_400),
                       score: score, confidence: .moderate, contributorCount: 3)
        }
    }

    private func daily(_ scores: [Double]) -> ScoreChange? {
        ScoreChangeReader.daily(history: history(scores), now: trendNow,
                               calendar: trendCalendar)
    }

    // MARK: - Daily

    func testTooLittleHistorySaysNothing() {
        XCTAssertNil(daily([70, 72]))
    }

    /// A score with no score for today is not a score for today.
    func testAStaleLatestScoreIsNotReportedAsToday() {
        let today = trendCalendar.startOfDay(for: trendNow)
        let stale = (0..<8).map { index in
            ScorePoint(date: today.addingTimeInterval(-Double(index + 3) * 86_400),
                       score: 70, confidence: .moderate, contributorCount: 3)
        }
        XCTAssertNil(ScoreChangeReader.daily(history: stale, now: trendNow,
                                            calendar: trendCalendar))
    }

    func testARealRiseReadsAsUp() throws {
        let trend = try XCTUnwrap(daily([60, 62, 61, 59, 63, 60, 61, 78]))
        XCTAssertEqual(trend.direction, .up)
        XCTAssertEqual(trend.label, "+17")
        XCTAssertTrue(trend.isMeaningful)
    }

    func testARealFallReadsAsDown() throws {
        let trend = try XCTUnwrap(daily([80, 82, 81, 79, 83, 80, 81, 62]))
        XCTAssertEqual(trend.direction, .down)
        XCTAssertEqual(trend.label, "−19")
    }

    /// The whole point. An ordinary wobble inside a person's usual spread is
    /// not a finding, and pointing an arrow at it every day teaches the user to
    /// stop reading the arrow.
    func testAnOrdinaryWobbleIsSteady() throws {
        let trend = try XCTUnwrap(daily([60, 68, 55, 71, 58, 66, 62, 64]))
        XCTAssertEqual(trend.direction, .steady)
        XCTAssertNil(trend.label)
        XCTAssertFalse(trend.isMeaningful)
    }

    /// The chip renders in every direction — steady included — so the reader can
    /// tell "no change" from "not measured". The signed label is still absent
    /// when steady (nothing to point at); `chipLabel` is what the chip draws and
    /// is never empty.
    func testTheChipHasWordsInEveryDirection() throws {
        let up = try XCTUnwrap(daily([60, 62, 61, 59, 63, 60, 61, 78]))
        let down = try XCTUnwrap(daily([80, 82, 81, 79, 83, 80, 81, 62]))
        let steady = try XCTUnwrap(daily([60, 68, 55, 71, 58, 66, 62, 64]))
        XCTAssertEqual(up.chipLabel, "+17")
        XCTAssertEqual(down.chipLabel, "−19")
        XCTAssertEqual(steady.chipLabel, "Stable")
        XCTAssertFalse(steady.chipLabel.isEmpty)
    }

    /// The same absolute move is a finding in a steady score and noise in a
    /// jumpy one — which is why this standardises rather than thresholding on
    /// points alone.
    func testTheSameMoveMeansMoreInASteadyScore() throws {
        let steady = try XCTUnwrap(daily([70, 70, 70, 70, 70, 70, 70, 78]))
        let jumpy = try XCTUnwrap(daily([50, 90, 55, 88, 52, 91, 60, 78]))
        XCTAssertEqual(steady.direction, .up)
        XCTAssertEqual(jumpy.direction, .steady,
                       "8 points inside a 40-point swing is not a rise")
    }

    /// A flat reference has no spread to divide by. A real move against one is
    /// a real move, not an undefined ratio — but one point still isn't.
    func testAFlatReferenceStillNeedsAFewPoints() throws {
        XCTAssertEqual(try XCTUnwrap(daily([70, 70, 70, 70, 70, 70, 70, 71])).direction,
                       .steady)
        XCTAssertEqual(try XCTUnwrap(daily([70, 70, 70, 70, 70, 70, 70, 74])).direction,
                       .up)
    }

    // MARK: - Broad

    /// Short-against-long, not this-month-against-last-month: every app that
    /// ships this uses a long reference, because a long one is stable and does
    /// not drift along with the change being measured.
    func testTheBroadComparisonIsShortAgainstLong() throws {
        // Ninety days at 50, then the last twenty-eight at 65.
        var scores = Array(repeating: 50.0, count: 62)
        scores += Array(repeating: 65.0, count: 28)
        let trend = try XCTUnwrap(ScoreChangeReader.broad(history: history(scores),
                                                         now: trendNow))
        XCTAssertEqual(trend.direction, .up)
        XCTAssertEqual(trend.recentDays, ScoreChangeReader.trendRecentDays)
        XCTAssertEqual(trend.referenceDays, ScoreChangeReader.trendReferenceDays)
    }

    func testASteadyQuarterIsSteady() throws {
        let scores = (0..<90).map { 70 + Double($0 % 3) }
        let trend = try XCTUnwrap(ScoreChangeReader.broad(history: history(scores),
                                                         now: trendNow))
        XCTAssertEqual(trend.direction, .steady)
    }

    func testABroadTrendNeedsAQuartersWorthOfHistory() {
        XCTAssertNil(ScoreChangeReader.broad(history: history(Array(repeating: 70.0, count: 10)),
                                            now: trendNow))
    }

    // MARK: - Routing

    /// Cadence already encodes the difference, so a call site never picks a
    /// window and the two cannot drift apart.
    func testCadenceChoosesTheComparison() throws {
        var scores = Array(repeating: 50.0, count: 62)
        scores += Array(repeating: 65.0, count: 28)
        let full = history(scores)

        let broad = try XCTUnwrap(ScoreChangeReader.trend(for: .heartHealth, history: full,
                                                         now: trendNow, calendar: trendCalendar))
        XCTAssertEqual(broad.referenceDays, ScoreChangeReader.trendReferenceDays)

        // `calendar:` is passed for the same reason every other call here pins
        // UTC: the fixture's days are UTC days. Without it this test read
        // `Calendar.current` and passed only on a machine in UTC — which every
        // CI run is, and the user's Mac is not.
        let day = try XCTUnwrap(ScoreChangeReader.trend(for: .readiness, history: full,
                                                       now: trendNow, calendar: trendCalendar))
        XCTAssertEqual(day.referenceDays, ScoreChangeReader.dailyReferenceDays)
    }

    /// The daily threshold is stricter than the trend one, because Today is
    /// seen many times a week and a trend card a few times a month — the cost
    /// of a false "it's up!" is an order of magnitude higher there.
    func testTodayIsHeldToAStricterBarThanInsights() {
        XCTAssertGreaterThan(ScoreChange.dailyThreshold, ScoreChange.trendThreshold)
    }
}
