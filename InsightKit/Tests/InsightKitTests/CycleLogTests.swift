import XCTest
@testable import InsightKit

/// The cycle log — backlog #31, refused three times and reversed by the reader.
///
/// **The tests that matter here are the ones about what it refuses to say.** A
/// period tracker's characteristic failure is asserting a precision it cannot
/// have: "your cycle is 28 days" from three observations. There is no property
/// on `CycleSummary` that returns a single length, and these pin that.
final class CycleLogTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    private func day(_ offset: Int) -> Date {
        utc.startOfDay(for: now.addingTimeInterval(Double(offset) * 86_400))
    }

    /// Periods starting on the given day-offsets, each `length` days long.
    private func log(starts: [Int], length: Int = 5) -> [CycleDay] {
        starts.flatMap { start in
            (0..<length).map { CycleDay(day: day(start + $0), flow: $0 < 2 ? .medium : .light) }
        }
    }

    // MARK: - The arithmetic

    func testDayOneIsTheFirstBleedingDayAndACycleRunsToTheDayBeforeTheNext() throws {
        let summary = CycleModel.summarise(days: log(starts: [-84, -56, -28]),
                                           now: now, calendar: utc)
        XCTAssertEqual(summary.cycles.count, 3)
        XCTAssertEqual(summary.lengths, [28, 28],
                       "two completed cycles of 28 days, and the third is still running")
        XCTAssertEqual(summary.periodLengths, [5, 5])
    }

    /// ⚠️ **The cycle in progress has no length**, and giving it one is the most
    /// common way a tracker misleads: a running cycle counted as a short one
    /// drags every average down.
    func testTheRunningCycleIsNotGivenALength() throws {
        let summary = CycleModel.summarise(days: log(starts: [-56, -28]),
                                           now: now, calendar: utc)
        let current = try XCTUnwrap(summary.current)
        XCTAssertTrue(current.isInProgress)
        XCTAssertNil(current.length(calendar: utc))
        XCTAssertEqual(summary.lengths.count, 1, "only the closed cycle has a length")
        XCTAssertEqual(summary.currentDay, 29)
    }

    /// A single unlogged day mid-period must not split one period into two
    /// cycles and halve every length. That failure is worse than its opposite:
    /// missing a day is common, a genuine two-day gap between periods is not.
    func testAMissedDayInsideAPeriodDoesNotSplitIt() {
        var days = log(starts: [-28], length: 5)
        days.removeAll { $0.day == day(-26) }
        let summary = CycleModel.summarise(days: days, now: now, calendar: utc)
        XCTAssertEqual(summary.cycles.count, 1,
                       "one missed day became a second cycle, which halves every length")
    }

    /// A log that stopped a year ago is not a cycle in progress.
    func testAnAbandonedLogDoesNotReportADayNumberForever() {
        let summary = CycleModel.summarise(days: log(starts: [-400]),
                                           now: now, calendar: utc)
        XCTAssertNil(summary.currentDay,
                     "day 400 is a stale log, not a cycle")
    }

    // MARK: - What it refuses to say

    /// **There is no single-number cycle length anywhere on the summary.** Two
    /// observations are a pair, not a range, and this is the app's whole claim
    /// against every consumer tracker.
    func testItWillNotOfferARangeFromTooFewCycles() {
        let two = CycleModel.summarise(days: log(starts: [-84, -56, -28]),
                                       now: now, calendar: utc)
        XCTAssertEqual(two.lengths.count, 2)
        XCTAssertNil(two.lengthRange, "two lengths are not a range")
        XCTAssertNil(two.spread)

        let sentence = CycleModel.lengthSentence(two)
        XCTAssertTrue(sentence.contains("2 complete cycles"), sentence)
        XCTAssertFalse(sentence.contains("28 days"),
                       "it stated a length from two observations: \(sentence)")
    }

    /// And once it can speak, it leads with the range and names the spread —
    /// the number a single average would hide.
    func testTheLengthSentenceReportsARangeAndItsSpreadRatherThanAnAverage() {
        var days = log(starts: [-112, -84, -55, -26])
        days += log(starts: [0])
        let summary = CycleModel.summarise(days: days, now: now, calendar: utc)
        let sentence = CycleModel.lengthSentence(summary)

        XCTAssertNotNil(summary.lengthRange)
        XCTAssertTrue(sentence.contains(" to "), sentence)
        XCTAssertTrue(sentence.lowercased().contains("spread"), sentence)
    }

    /// Every branch of the headline and the sentence has to be reachable and
    /// non-empty — an empty log is the state every reader starts in.
    func testTheEmptyLogSaysSomethingUsefulRatherThanNothing() {
        let empty = CycleModel.summarise(days: [], now: now, calendar: utc)
        XCTAssertEqual(CycleModel.headline(empty), "Nothing logged yet")
        XCTAssertFalse(CycleModel.lengthSentence(empty).isEmpty)
        XCTAssertNil(empty.lengthRange)
        XCTAssertNil(empty.currentDay)
    }

    /// HealthKit's flow ordinal is a number, not a name. A silent off-by-one
    /// would turn a light day into a heavy one everywhere downstream.
    func testTheHealthKitFlowMappingRejectsTheNonFlowValues() {
        XCTAssertEqual(MenstrualFlowLevel.fromHealthKitValue(2), .light)
        XCTAssertEqual(MenstrualFlowLevel.fromHealthKitValue(4), .heavy)
        XCTAssertNil(MenstrualFlowLevel.fromHealthKitValue(0), "unspecified is not a flow")
        XCTAssertNil(MenstrualFlowLevel.fromHealthKitValue(5), "none is not a flow")
    }
}
