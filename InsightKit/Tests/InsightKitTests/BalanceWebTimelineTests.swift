import XCTest
@testable import InsightKit

/// The morph slider's frames — backlog P20.
///
/// In InsightKit because the app target has no test target and SwiftUI does not
/// exist on Linux, so this is the only place the rules the slider rests on can
/// be falsified at all. See `add-chart` §5.
///
/// The rules under test are the honesty ones, not the arithmetic: **the axes do
/// not move between frames**, **a card missing a step is dropped and named**,
/// and **the grey underlay is today rather than another past**.
final class BalanceWebTimelineTests: XCTestCase {

    /// A UTC calendar with Monday weeks, so a bucket boundary is the same fact
    /// on every machine that runs this.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func point(_ date: Date, _ score: Double) -> ScorePoint {
        ScorePoint(date: date, score: score, confidence: .moderate, contributorCount: 4)
    }

    /// A score on every day from `from` to `to` inclusive.
    private func daily(from: Date, to: Date, score: (Int) -> Double) -> [ScorePoint] {
        var out: [ScorePoint] = []
        var cursor = from
        var index = 0
        while cursor <= to {
            out.append(point(cursor, score(index)))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
            index += 1
        }
        return out
    }

    // MARK: - Bucketing

    /// A month bucket starts on the first and ends on the first of the next —
    /// half open, so a reading at midnight on the 1st belongs to exactly one
    /// frame rather than two or none.
    func testMonthBucketIsHalfOpen() {
        let bucket = WebTimeGranularity.month.bucket(containing: day(2026, 3, 17),
                                                     calendar: calendar)
        XCTAssertEqual(bucket?.start, day(2026, 3, 1))
        XCTAssertEqual(bucket?.end, day(2026, 4, 1))
    }

    /// Quarters are computed rather than asked of `Calendar`, so the arithmetic
    /// is worth pinning at both ends of one.
    func testQuartersRunJanuaryAprilJulyOctober() {
        for (month, start) in [(1, 1), (2, 1), (3, 1), (4, 4), (6, 4),
                               (7, 7), (9, 7), (10, 10), (12, 10)] {
            let bucket = WebTimeGranularity.quarter.bucket(containing: day(2026, month, 15),
                                                           calendar: calendar)
            XCTAssertEqual(bucket?.start, day(2026, start, 1),
                           "month \(month) should sit in the quarter starting \(start)")
        }
    }

    /// A December quarter has to roll the year, which is where a naive
    /// `month + 3` puts the end in month 15.
    func testQuarterRollsTheYear() {
        let bucket = WebTimeGranularity.quarter.bucket(containing: day(2026, 11, 3),
                                                       calendar: calendar)
        XCTAssertEqual(bucket?.start, day(2026, 10, 1))
        XCTAssertEqual(bucket?.end, day(2027, 1, 1))
    }

    // MARK: - The coverage rule

    /// **The rule the whole section rests on.** A card missing a score in any
    /// one step is not drawn — carrying its last value forward would invent a
    /// reading, and dropping its vertex to the centre would draw "no data" at
    /// the same radius as "scored zero".
    func testACardMissingOneStepIsDroppedAndNamed() {
        let start = day(2026, 1, 1)
        let end = day(2026, 3, 31)
        let complete = daily(from: start, to: end) { _ in 60 }
        // Nothing in February at all.
        let gappy = daily(from: start, to: day(2026, 1, 31)) { _ in 50 }
            + daily(from: day(2026, 3, 1), to: end) { _ in 55 }

        let timeline = BalanceWebTimeline.build(
            histories: [.readiness: complete, .sleep: complete,
                        .fitness: complete, .bloodPressure: gappy],
            granularity: .month, calendar: calendar)

        XCTAssertEqual(timeline.frames.count, 3)
        for frame in timeline.frames {
            XCTAssertEqual(frame.snapshot.spokes.map(\.id), [.readiness, .sleep, .fitness],
                           "the axes must not change between frames")
        }
        XCTAssertEqual(timeline.excluded, [InsightID.bloodPressure.shortTitle])
    }

    /// The step width is the reader's lever over that rule, which is the whole
    /// reason the picker exists: the same gap that costs a card its place at one
    /// width can be invisible at another.
    func testACoarserStepCanBringAnExcludedCardBack() {
        let start = day(2026, 1, 5)      // a Monday
        let end = day(2026, 3, 29)
        let complete = daily(from: start, to: end) { _ in 60 }
        // Present every month, but only in the first fortnight of each — so it
        // misses whole weeks and no months.
        var patchy: [ScorePoint] = []
        for month in 1...3 {
            let from = max(day(2026, month, 5), start)
            patchy += daily(from: from, to: day(2026, month, 14)) { _ in 45 }
        }

        let weekly = BalanceWebTimeline.build(
            histories: [.readiness: complete, .sleep: complete,
                        .fitness: complete, .bloodPressure: patchy],
            granularity: .week, calendar: calendar)
        XCTAssertEqual(weekly.excluded, [InsightID.bloodPressure.shortTitle])

        let monthly = BalanceWebTimeline.build(
            histories: [.readiness: complete, .sleep: complete,
                        .fitness: complete, .bloodPressure: patchy],
            granularity: .month, calendar: calendar)
        XCTAssertTrue(monthly.excluded.isEmpty)
        XCTAssertEqual(monthly.frames.first?.snapshot.spokes.count, 4)
    }

    /// A detector kept off the hero must not arrive here by the back door: the
    /// symptom radar reports 100 when it has found nothing, and this chart reads
    /// radius as *how well it is going*.
    func testCardsOffTheBalanceWebNeverGetASpoke() {
        let points = daily(from: day(2026, 1, 1), to: day(2026, 2, 28)) { _ in 70 }
        let timeline = BalanceWebTimeline.build(
            histories: [.readiness: points, .sleep: points, .fitness: points,
                        .symptomRadar: points, .mentalHealth: points],
            granularity: .month, calendar: calendar)
        for frame in timeline.frames {
            XCTAssertFalse(frame.snapshot.spokes.contains { $0.id == .symptomRadar })
            XCTAssertFalse(frame.snapshot.spokes.contains { $0.id == .mentalHealth })
        }
        // And they are not named as "excluded" either — they were never
        // candidates, and blaming coverage for a rule about detectors would send
        // the reader to change a step width that cannot help.
        XCTAssertTrue(timeline.excluded.isEmpty)
    }

    // MARK: - What the frames say

    /// Each frame's score is the mean of its own days, and only its own days.
    func testAFrameAveragesItsOwnBucket() {
        let january = daily(from: day(2026, 1, 1), to: day(2026, 1, 31)) { _ in 40 }
        let february = daily(from: day(2026, 2, 1), to: day(2026, 2, 28)) { _ in 80 }
        let points = january + february
        let timeline = BalanceWebTimeline.build(
            histories: [.readiness: points, .sleep: points, .fitness: points],
            granularity: .month, calendar: calendar)

        XCTAssertEqual(timeline.frames.count, 2)
        XCTAssertEqual(timeline.frames[0].snapshot.spokes.first?.score ?? 0, 40, accuracy: 1e-9)
        XCTAssertEqual(timeline.frames[1].snapshot.spokes.first?.score ?? 0, 80, accuracy: 1e-9)
        XCTAssertEqual(timeline.frames[0].scoredDayCount, 31 * 3)
    }

    /// **The grey underlay is today, on every frame** — not each frame's own
    /// trailing average, which would be a second past and would answer nothing.
    func testEveryFrameIsReferencedAgainstTheNewestStep() {
        let january = daily(from: day(2026, 1, 1), to: day(2026, 1, 31)) { _ in 40 }
        let february = daily(from: day(2026, 2, 1), to: day(2026, 2, 28)) { _ in 80 }
        let points = january + february
        let timeline = BalanceWebTimeline.build(
            histories: [.readiness: points, .sleep: points, .fitness: points],
            granularity: .month, calendar: calendar)

        for frame in timeline.frames {
            for spoke in frame.snapshot.spokes {
                XCTAssertEqual(spoke.reference ?? 0, 80, accuracy: 1e-9)
            }
        }
    }

    /// `referenceDays` stays nil so `referenceDescription` — which describes a
    /// *trailing window* — cannot volunteer a sentence that is wrong here.
    func testNoTrailingWindowIsClaimed() {
        let points = daily(from: day(2026, 1, 1), to: day(2026, 3, 1)) { index in
            Double(50 + index % 10)
        }
        let timeline = BalanceWebTimeline.build(
            histories: [.readiness: points, .sleep: points, .fitness: points],
            granularity: .month, calendar: calendar)
        for frame in timeline.frames {
            XCTAssertNil(frame.snapshot.referenceDescription)
        }
    }

    /// The oldest frame has nothing behind it, so it gets no arrow — a different
    /// silence from "steady", which is a measured answer.
    func testTheOldestFrameHasNoDirection() {
        let points = daily(from: day(2026, 1, 1), to: day(2026, 3, 1)) { index in
            index < 31 ? 40 : 80
        }
        let timeline = BalanceWebTimeline.build(
            histories: [.readiness: points, .sleep: points, .fitness: points],
            granularity: .month, calendar: calendar)
        XCTAssertNil(timeline.frames.first?.snapshot.spokes.first?.direction)
        XCTAssertEqual(timeline.frames[1].snapshot.spokes.first?.direction, .up)
    }

    /// Movement under the app's own two-point deadband is "stable", not a
    /// direction — the same floor `ScoreChange` applies everywhere else.
    func testSmallMovementReadsAsSteady() {
        XCTAssertEqual(BalanceWebTimeline.direction(from: 60, to: 61.4), .steady)
        XCTAssertEqual(BalanceWebTimeline.direction(from: 60, to: 62.5), .up)
        XCTAssertEqual(BalanceWebTimeline.direction(from: 60, to: 57), .down)
        XCTAssertNil(BalanceWebTimeline.direction(from: nil, to: 57))
    }

    // MARK: - What the screen has to print

    /// The span is the first and last scored day, and it is what the section
    /// prints. A chart that silently changes the stretch of life it covers is
    /// the ambiguity this app exists to avoid.
    func testSpanIsTheFirstAndLastScoredDay() {
        let points = daily(from: day(2026, 1, 9), to: day(2026, 4, 2)) { _ in 60 }
        let timeline = BalanceWebTimeline.build(
            histories: [.readiness: points, .sleep: points, .fitness: points],
            granularity: .month, calendar: calendar)
        XCTAssertEqual(timeline.span?.lowerBound, day(2026, 1, 9))
        XCTAssertEqual(timeline.span?.upperBound, day(2026, 4, 2))
        XCTAssertEqual(timeline.dayCount, 84)
        XCTAssertEqual(timeline.frames.count, 4)
    }

    /// Two frames is the floor for a *morph*: a slider with one position is a
    /// control that does nothing, and a single frame is the hero web with extra
    /// chrome around it.
    func testOneStepIsNotMorphable() {
        let points = daily(from: day(2026, 1, 3), to: day(2026, 1, 20)) { _ in 60 }
        let timeline = BalanceWebTimeline.build(
            histories: [.readiness: points, .sleep: points, .fitness: points],
            granularity: .month, calendar: calendar)
        XCTAssertEqual(timeline.frames.count, 1)
        XCTAssertFalse(timeline.isMorphable)
    }

    /// Two spokes draw a line segment, which reads as a chart with a bug in it.
    func testTwoCardsIsNotDrawable() {
        let points = daily(from: day(2026, 1, 1), to: day(2026, 3, 1)) { _ in 60 }
        let timeline = BalanceWebTimeline.build(
            histories: [.readiness: points, .sleep: points],
            granularity: .month, calendar: calendar)
        XCTAssertEqual(timeline.frames.count, 3)
        XCTAssertFalse(timeline.isMorphable)
    }

    /// Nothing in, nothing claimed — and no crash on the empty case, which is
    /// what a fresh install hands this.
    func testEmptyHistoriesProduceAnEmptyTimeline() {
        let timeline = BalanceWebTimeline.build(histories: [:], granularity: .week,
                                                calendar: calendar)
        XCTAssertTrue(timeline.frames.isEmpty)
        XCTAssertTrue(timeline.excluded.isEmpty)
        XCTAssertNil(timeline.span)
        XCTAssertNil(timeline.dayCount)
        XCTAssertFalse(timeline.isMorphable)
    }

    /// The order is `colourSlot`, the same as the hero's — the shape a reader
    /// learns in one place is the shape they meet in the other.
    func testSpokeOrderMatchesTheHero() {
        let points = daily(from: day(2026, 1, 1), to: day(2026, 3, 1)) { _ in 60 }
        let timeline = BalanceWebTimeline.build(
            histories: [.bodyComposition: points, .readiness: points, .fitness: points],
            granularity: .month, calendar: calendar)
        XCTAssertEqual(timeline.frames.first?.snapshot.spokes.map(\.id),
                       [.readiness, .fitness, .bodyComposition])
    }
}
