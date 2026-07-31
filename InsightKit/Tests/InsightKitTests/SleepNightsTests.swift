import XCTest
@testable import InsightKit

private let nightsCalendar = TestClock.utc

/// The second half of the nap defect, found the same way as the first — from
/// the distribution rather than from the code.
///
/// The Oura fix landed, deployed and installed, and the export still showed a
/// sleep-duration **minimum of 0.01 h** and a sleep-efficiency **minimum of 2%**.
/// Those did not come from Oura. They came from `HealthKitService.fetchSleep`
/// keying every nightly figure on the calendar day each *segment* started, so a
/// night that crossed midnight was filed as two — one of them a sliver.
///
/// `SleepOnset.night(of:)` sat in the same function, over the same segments,
/// with a doc comment naming the duration series as doing exactly this wrong.
final class SleepNightsTests: XCTestCase {

    private let source = MetricSource(id: "apple_health", displayName: "Apple Health")

    /// An instant at `hour:minute` UTC, `daysAgo` before the anchor.
    ///
    /// `TestClock.day` is midday, so a fixture can never straddle midnight by
    /// accident; this takes that back off to reach the day's true start.
    private func at(_ hour: Int, _ minute: Int = 0, daysAgo: Int) -> Date {
        TestClock.day(daysAgo).addingTimeInterval(-12 * 3600)
            .addingTimeInterval(Double(hour) * 3600 + Double(minute) * 60)
    }

    private func segment(_ kind: SleepSegment.Kind,
                         from: (Int, Int), fromDaysAgo: Int,
                         to: (Int, Int), toDaysAgo: Int) -> SleepSegment {
        SleepSegment(kind: kind,
                     start: at(from.0, from.1, daysAgo: fromDaysAgo),
                     end: at(to.0, to.1, daysAgo: toDaysAgo))
    }

    private func durations(_ segments: [SleepSegment]) -> [HealthMetricSample] {
        SleepNights.samples(from: segments, source: source, calendar: nightsCalendar)
            .samples(of: .sleepDurationHours)
    }

    // MARK: - One night is one night

    /// The headline defect. Apple Health writes a night as a run of stage
    /// segments; the ones before midnight were filed under one day and the ones
    /// after under the next, so a single 8 h night became a 1 h "night" and a
    /// 7 h one.
    func testANightCrossingMidnightIsOneNightNotTwo() throws {
        let night = [
            segment(.core, from: (23, 0), fromDaysAgo: 6, to: (24, 0), toDaysAgo: 6),
            segment(.deep, from: (0, 0), fromDaysAgo: 5, to: (2, 30), toDaysAgo: 5),
            segment(.rem, from: (2, 30), fromDaysAgo: 5, to: (4, 0), toDaysAgo: 5),
            segment(.core, from: (4, 0), fromDaysAgo: 5, to: (7, 0), toDaysAgo: 5),
        ]
        let result = durations(night)
        XCTAssertEqual(result.count, 1, "one night must produce one duration")
        XCTAssertEqual(try XCTUnwrap(result.first).value, 8, accuracy: 0.001)
    }

    /// The exact number the export showed. A night beginning at 23:59 put one
    /// minute on the earlier day, and one minute is 0.017 h — which is what a
    /// `sleepDurationHours` minimum of 0.01 was.
    func testAMinuteBeforeMidnightDoesNotBecomeItsOwnNight() throws {
        let result = durations([
            segment(.core, from: (23, 59), fromDaysAgo: 4, to: (24, 0), toDaysAgo: 4),
            segment(.core, from: (0, 0), fromDaysAgo: 3, to: (6, 30), toDaysAgo: 3),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(try XCTUnwrap(result.first).value, 6.5167, accuracy: 0.001)
    }

    /// A night is stamped at the morning it ends on, which is also how Oura
    /// dates one. `bucketStatistic` averages same-day samples, so if the two
    /// sources disagreed by a day, a real night from one would be averaged with
    /// a different night from the other — and that is the "7.5 h night reported
    /// as 4 h" symptom all over again.
    func testANightIsStampedAtTheMorningItEndsOn() throws {
        let result = durations([
            segment(.core, from: (23, 0), fromDaysAgo: 6, to: (24, 0), toDaysAgo: 6),
            segment(.core, from: (0, 0), fromDaysAgo: 5, to: (7, 0), toDaysAgo: 5),
        ])
        let expected = nightsCalendar.startOfDay(for: at(7, 0, daysAgo: 5))
        XCTAssertEqual(try XCTUnwrap(result.first).start, expected)
    }

    /// Two genuinely separate nights must stay separate — the fix must not
    /// collapse everything into one bucket.
    func testTwoNightsStayTwoNights() {
        let result = durations([
            segment(.core, from: (23, 0), fromDaysAgo: 6, to: (24, 0), toDaysAgo: 6),
            segment(.core, from: (0, 0), fromDaysAgo: 5, to: (6, 0), toDaysAgo: 5),
            segment(.core, from: (23, 30), fromDaysAgo: 5, to: (24, 0), toDaysAgo: 5),
            segment(.core, from: (0, 0), fromDaysAgo: 4, to: (7, 0), toDaysAgo: 4),
        ])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map { ($0.value * 100).rounded() / 100 }, [7, 7.5])
    }

    // MARK: - Efficiency

    /// The other export number. Efficiency split its numerator and denominator
    /// at midnight *independently*, so a sliver of asleep over a whole night in
    /// bed read as 2% — and the reverse overflowed, which is the only reason the
    /// old code needed to clamp at 100.
    func testEfficiencyTakesItsNumeratorAndDenominatorFromTheSameNight() throws {
        let samples = SleepNights.samples(from: [
            SleepSegment(kind: .inBed, start: at(22, 30, daysAgo: 6), end: at(7, 0, daysAgo: 5)),
            segment(.core, from: (23, 0), fromDaysAgo: 6, to: (24, 0), toDaysAgo: 6),
            segment(.core, from: (0, 0), fromDaysAgo: 5, to: (6, 30), toDaysAgo: 5),
        ], source: source, calendar: nightsCalendar)
        let efficiency = samples.samples(of: .sleepEfficiency)
        XCTAssertEqual(efficiency.count, 1)
        // 7.5 h asleep of 8.5 h in bed.
        XCTAssertEqual(try XCTUnwrap(efficiency.first).value, 88.235, accuracy: 0.01)
    }

    /// Rings infer sleep and never write an in-bed segment. No denominator must
    /// mean no reading, not a fabricated 100%.
    func testNoInBedSegmentMeansNoEfficiency() {
        let samples = SleepNights.samples(from: [
            segment(.core, from: (23, 0), fromDaysAgo: 6, to: (24, 0), toDaysAgo: 6),
            segment(.core, from: (0, 0), fromDaysAgo: 5, to: (6, 0), toDaysAgo: 5),
        ], source: source, calendar: nightsCalendar)
        XCTAssertTrue(samples.samples(of: .sleepEfficiency).isEmpty)
    }

    // MARK: - Stages

    func testStagesAreSummedPerNightAndReportedInMinutes() throws {
        let samples = SleepNights.samples(from: [
            segment(.deep, from: (23, 30), fromDaysAgo: 6, to: (24, 0), toDaysAgo: 6),
            segment(.deep, from: (0, 0), fromDaysAgo: 5, to: (0, 45), toDaysAgo: 5),
            segment(.rem, from: (3, 0), fromDaysAgo: 5, to: (4, 0), toDaysAgo: 5),
        ], source: source, calendar: nightsCalendar)
        let deep = samples.samples(of: .sleepDeepMinutes)
        XCTAssertEqual(deep.count, 1)
        XCTAssertEqual(try XCTUnwrap(deep.first).value, 75, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(samples.samples(of: .sleepRemMinutes).first).value,
                       60, accuracy: 0.001)
    }

    // MARK: - Naps

    /// An afternoon nap falls inside the 18:00→18:00 window that keys the
    /// *previous* night, so before this rule it added its minutes to last
    /// night's total. It is not part of any night.
    func testAnAfternoonNapAddsNothingToLastNight() throws {
        let withoutNap = durations([
            segment(.core, from: (23, 0), fromDaysAgo: 6, to: (24, 0), toDaysAgo: 6),
            segment(.core, from: (0, 0), fromDaysAgo: 5, to: (7, 0), toDaysAgo: 5),
        ])
        let withNap = durations([
            segment(.core, from: (23, 0), fromDaysAgo: 6, to: (24, 0), toDaysAgo: 6),
            segment(.core, from: (0, 0), fromDaysAgo: 5, to: (7, 0), toDaysAgo: 5),
            segment(.core, from: (15, 0), fromDaysAgo: 5, to: (15, 40), toDaysAgo: 5),
        ])
        XCTAssertEqual(withNap.count, 1, "the nap must not become a night of its own")
        XCTAssertEqual(try XCTUnwrap(withNap.first).value,
                       try XCTUnwrap(withoutNap.first).value, accuracy: 0.001,
                       "nor add its minutes to the night")
    }

    /// A cluster whose earliest sleep is not a plausible onset is a nap, whatever
    /// window it landed in. Same admission test the onset series uses, so the two
    /// cannot disagree about what a night is.
    func testALoneMiddayNapIsNotANight() {
        XCTAssertTrue(durations([
            segment(.core, from: (13, 0), fromDaysAgo: 5, to: (14, 30), toDaysAgo: 5),
        ]).isEmpty)
    }

    /// A late lie-in is a night, not a nap. The admission test looks at the
    /// night's *onset*; segments that continue past it are still that night, or
    /// every long sleep would be truncated at 06:00.
    func testALieInIsStillOneNight() throws {
        let result = durations([
            segment(.core, from: (23, 0), fromDaysAgo: 6, to: (24, 0), toDaysAgo: 6),
            segment(.core, from: (0, 0), fromDaysAgo: 5, to: (7, 0), toDaysAgo: 5),
            segment(.core, from: (7, 0), fromDaysAgo: 5, to: (10, 30), toDaysAgo: 5),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(try XCTUnwrap(result.first).value, 11.5, accuracy: 0.001)
    }

    /// Pinned as *intended*, not as an oversight, so nobody "fixes" it in
    /// isolation. Sleep starting outside ±6 h of midnight yields no night —
    /// `SleepOnset.plausibleHours`, the same trade the bedtime series already
    /// made and recorded. Changing it here without changing it there would put
    /// the two series back into disagreement about how many nights there were.
    func testDayShiftSleepIsDroppedRatherThanReportedWrong() {
        XCTAssertTrue(durations([
            segment(.core, from: (9, 0), fromDaysAgo: 5, to: (11, 0), toDaysAgo: 5),
        ]).isEmpty)
    }

    // MARK: - Consistency with the onset series

    /// The whole point of routing both through `SleepOnset.night(of:)`: the
    /// duration and the bedtime for one night must land on the same date. They
    /// did not before, which is how the two series could disagree about how many
    /// nights there had been.
    func testDurationAndOnsetForOneNightShareADate() throws {
        let samples = SleepNights.samples(from: [
            segment(.core, from: (23, 15), fromDaysAgo: 6, to: (24, 0), toDaysAgo: 6),
            segment(.core, from: (0, 0), fromDaysAgo: 5, to: (6, 45), toDaysAgo: 5),
        ], source: source, calendar: nightsCalendar)
        let duration = try XCTUnwrap(samples.samples(of: .sleepDurationHours).first)
        let onset = try XCTUnwrap(samples.samples(of: .sleepOnset).first)
        XCTAssertEqual(duration.start, onset.start)
        XCTAssertEqual(onset.value, -0.75, accuracy: 0.001, "23:15 is −0.75 h from midnight")
    }

    // MARK: - Degenerate input

    /// A provider writing `end` before `start` should contribute nothing rather
    /// than subtract from the night.
    func testAnInvertedSegmentContributesNothing() throws {
        let result = durations([
            segment(.core, from: (23, 0), fromDaysAgo: 6, to: (24, 0), toDaysAgo: 6),
            segment(.core, from: (0, 0), fromDaysAgo: 5, to: (6, 0), toDaysAgo: 5),
            SleepSegment(kind: .core, start: at(3, 0, daysAgo: 5), end: at(1, 0, daysAgo: 5)),
        ])
        XCTAssertEqual(try XCTUnwrap(result.first).value, 7, accuracy: 0.001)
    }

    func testNoSegmentsProducesNoSamples() {
        XCTAssertTrue(SleepNights.samples(from: [], source: source,
                                          calendar: nightsCalendar).isEmpty)
    }

    /// In-bed time with nothing asleep is not a zero-hour night — it is a night
    /// we have no sleep reading for, and a 0 would be charted as one.
    func testInBedAloneProducesNothing() {
        XCTAssertTrue(SleepNights.samples(from: [
            SleepSegment(kind: .inBed, start: at(23, 0, daysAgo: 6), end: at(7, 0, daysAgo: 5)),
        ], source: source, calendar: nightsCalendar).isEmpty)
    }
}
