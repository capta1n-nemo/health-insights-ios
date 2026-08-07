import XCTest
@testable import InsightKit

/// **How long you take to come back** — backlog §C S6.
///
/// The interesting half of this model is not the arithmetic, it is what it
/// refuses to count, so most of what is pinned here is the gap rule and the
/// definition of "recovered".
final class RecoveryTrackerTests: XCTestCase {

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private let day0 = Date(timeIntervalSince1970: 19_900 * 86_400)

    private func point(_ dayOffset: Int, _ score: Double) -> ScorePoint {
        ScorePoint(date: day0.addingTimeInterval(Double(dayOffset) * 86_400),
                   score: score, confidence: .moderate, contributorCount: 4)
    }

    /// A steady baseline with a little jitter, so the robust spread is non-zero
    /// without any day counting as a dip.
    private func steady(_ days: Range<Int>, around: Double = 70) -> [ScorePoint] {
        days.map { point($0, around + Double($0 % 3) - 1) }
    }

    // MARK: - What counts as recovered

    /// ⚠️ **The definition that matters.** A dip is over on the first day back
    /// at *typical*, not the first day back above the dip line — measuring to
    /// the edge of the hole reports roughly half the real recovery.
    func testRecoveryIsMeasuredBackToTypicalNotBackToTheDipLine() throws {
        // Twenty steady days, then a crash and a three-day climb that passes
        // through the dip line on the way up.
        var points = steady(0..<20)
        points += [point(20, 40), point(21, 55), point(22, 64), point(23, 71)]
        points += steady(24..<30)

        let out = try XCTUnwrap(RecoveryTracker.evaluate(points, calendar: utc))
        let episode = try XCTUnwrap(out.episodes.first { $0.recovered != nil })
        // Day 20 → day 23. Stopping at day 22 (back above the dip floor, still
        // under typical) would have said two.
        XCTAssertEqual(episode.days, 3)
        XCTAssertEqual(episode.troughScore, 40, accuracy: 1e-9)
    }

    /// A dip that ends the next day says so, and the phrase reads as English
    /// rather than as "1 days".
    func testAOneDayDipReadsAsBackTheNextDay() throws {
        var points = steady(0..<20)
        points += [point(20, 45), point(21, 72)]
        points += steady(22..<33)

        let out = try XCTUnwrap(RecoveryTracker.evaluate(points, calendar: utc))
        let episode = try XCTUnwrap(out.episodes.first)
        XCTAssertEqual(episode.days, 1)
        XCTAssertTrue(episode.isObserved)
    }

    // MARK: - ⚠️ The gap rule

    /// **The fabrication this model exists to refuse.** A dip on one day
    /// followed by nothing for a week and then a good day is not a seven-day
    /// recovery — nobody watched six of those days.
    func testAnEpisodeSpanningAGapIsKeptAndExcludedFromTheFigure() throws {
        var points = steady(0..<20)
        points += [point(20, 40)]
        // Nothing between day 21 and day 28 — a week off the wearable.
        points += steady(28..<40)

        let out = try XCTUnwrap(RecoveryTracker.evaluate(points, calendar: utc))
        let episode = try XCTUnwrap(out.episodes.first { $0.start == self.point(20, 0).date })
        XCTAssertFalse(episode.isObserved, "an eight-day step is not an observed recovery")
        XCTAssertFalse(episode.countsTowardTypical)
        XCTAssertEqual(out.unobservedEpisodes, 1)
        // …and it is still *shown*, because hiding half the evidence is how a
        // tracker starts looking tidier than the data.
        XCTAssertTrue(out.episodes.contains { !$0.isObserved })
    }

    /// A gap inside the allowance is stepped over without complaint — a long
    /// weekend off the ring is the common case, not an anomaly.
    func testAShortGapInsideAnEpisodeIsStillObserved() throws {
        var points = steady(0..<20)
        points += [point(20, 42), point(23, 72)]
        points += steady(24..<34)

        let out = try XCTUnwrap(RecoveryTracker.evaluate(points, calendar: utc))
        let episode = try XCTUnwrap(out.episodes.first { $0.days != nil })
        XCTAssertTrue(episode.isObserved)
        XCTAssertEqual(episode.days, 3)
    }

    // MARK: - The figure, and when it is withheld

    /// One recovered dip is an anecdote. The gate says what is missing rather
    /// than the figure silently not appearing.
    func testOneEpisodeIsNotEnoughForATypicalAndTheGateSaysSo() throws {
        var points = steady(0..<20)
        points += [point(20, 45), point(21, 72)]
        points += steady(22..<34)

        let out = try XCTUnwrap(RecoveryTracker.evaluate(points, calendar: utc))
        XCTAssertNil(out.typicalDays)
        let sentence = try XCTUnwrap(out.gate?.sentence)
        XCTAssertTrue(sentence.contains("1 of 2"), sentence)
        XCTAssertTrue(RecoveryTracker.phrase(out).contains("1 of 2"))
    }

    func testTwoRecoveredDipsProduceAMedian() throws {
        var points = steady(0..<20)
        points += [point(20, 44), point(21, 60), point(22, 72)]   // 2 days
        points += steady(23..<30)
        points += [point(30, 42), point(31, 58), point(32, 71)]   // 2 days
        points += steady(33..<44)

        let out = try XCTUnwrap(RecoveryTracker.evaluate(points, calendar: utc))
        XCTAssertEqual(try XCTUnwrap(out.typicalDays), 2, accuracy: 1e-9)
        XCTAssertTrue(RecoveryTracker.phrase(out).contains("2 days"),
                      RecoveryTracker.phrase(out))
    }

    /// Two dips a single good day apart stay two dips. Merging them would
    /// report one long "recovery" spanning a week of normal days.
    func testTwoDipsSeparatedByOneGoodDayStayTwoDips() throws {
        var points = steady(0..<20)
        points += [point(20, 44), point(21, 72), point(22, 43), point(23, 71)]
        points += steady(24..<36)

        let out = try XCTUnwrap(RecoveryTracker.evaluate(points, calendar: utc))
        XCTAssertEqual(out.episodes.filter { $0.days != nil }.count, 2)
        XCTAssertEqual(try XCTUnwrap(out.typicalDays), 1, accuracy: 1e-9)
    }

    /// A dip still running has no length and is reported as open rather than
    /// being given one.
    func testAnOpenDipHasNoLengthAndIsReportedAsOpen() throws {
        var points = steady(0..<20)
        points += [point(20, 41), point(21, 44)]

        let out = try XCTUnwrap(RecoveryTracker.evaluate(points, calendar: utc))
        let open = try XCTUnwrap(out.openEpisode)
        XCTAssertNil(open.days)
        XCTAssertFalse(open.countsTowardTypical)
    }

    // MARK: - The thresholds are the reader's own

    /// **The same trace, shifted, gives the same answer.** A recovery tracker
    /// built on a fixed threshold would tell one reader they never dip and
    /// another that they never recover.
    func testTheDipLineFollowsTheReadersOwnDistribution() throws {
        var low = steady(0..<20, around: 40)
        low += [point(20, 10), point(21, 25), point(22, 41)]
        low += steady(23..<34, around: 40)

        let out = try XCTUnwrap(RecoveryTracker.evaluate(low, calendar: utc))
        XCTAssertEqual(try XCTUnwrap(out.episodes.first).days, 2)
        XCTAssertLessThan(out.dipFloor, out.typical)
    }

    /// No dip at all is a finding, not an empty section.
    func testASteadyRecordReportsNoDipsRatherThanNothing() throws {
        let out = try XCTUnwrap(RecoveryTracker.evaluate(steady(0..<40), calendar: utc))
        XCTAssertTrue(out.episodes.isEmpty)
        XCTAssertTrue(RecoveryTracker.phrase(out).contains("No day"),
                      RecoveryTracker.phrase(out))
    }

    /// Below the floor there is no distribution to speak of, and the model
    /// says nothing rather than describing one from a handful of days.
    func testTooLittleHistoryProducesNothing() {
        XCTAssertNil(RecoveryTracker.evaluate(steady(0..<10), calendar: utc))
        XCTAssertNil(RecoveryTracker.evaluate([], calendar: utc))
    }

    /// A record with no spread has no scale to measure a dip against, and
    /// inventing one would make every reading a dip or none of them.
    func testAFlatRecordProducesNothing() {
        let flat = (0..<40).map { point($0, 70) }
        XCTAssertNil(RecoveryTracker.evaluate(flat, calendar: utc))
    }
}
