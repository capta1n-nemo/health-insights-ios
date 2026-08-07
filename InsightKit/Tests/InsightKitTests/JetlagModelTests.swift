import XCTest
@testable import InsightKit

/// Backlog `B21`. The reader's own journey — Manila (UTC+8) → Sydney (UTC+10),
/// eastward, two zones — is the worked example throughout.
///
/// **Nothing here is pinned to UTC.** Every fixture names a real zone, because
/// a UTC-pinned test of zone arithmetic agrees with itself and proves nothing;
/// `verify.sh` bans the shape for exactly that reason.
final class JetlagModelTests: XCTestCase {

    private let manila = TimeZone(identifier: "Asia/Manila")!       // +8, no DST
    private let sydney = TimeZone(identifier: "Australia/Sydney")!  // +10 in August
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    private func calendar(_ zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    private func instant(_ zone: TimeZone, _ y: Int, _ mo: Int, _ d: Int,
                         _ h: Int, _ mi: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c.date(from: DateComponents(year: y, month: mo, day: d,
                                           hour: h, minute: mi))!
    }

    private func event(_ zone: TimeZone, _ start: Date, id: String) -> CalendarEvent {
        CalendarEvent(id: id, start: start, end: start.addingTimeInterval(3600),
                      isAllDay: false, timeZoneIdentifier: zone.identifier,
                      calendarName: "Work", kind: .timed)
    }

    // MARK: - The asymmetry, which is the whole claim

    /// The one property that must never be lost: **east costs more than west
    /// for the same number of zones.** If a refactor makes this pass by making
    /// both rates equal, the citation in `JetlagModel` has become decoration.
    func testEastwardCostsMoreThanWestwardForTheSameDose() {
        let east = JetlagModel.adjustmentDays(shiftHours: 2)
        let west = JetlagModel.adjustmentDays(shiftHours: -2)
        XCTAssertGreaterThan(east, west)
        XCTAssertEqual(east / west, JetlagModel.daysPerZoneEastward
                       / JetlagModel.daysPerZoneWestward, accuracy: 0.0001)
    }

    /// The published rates, at the reader's own dose.
    func testManilaToSydneyIsThreeDaysEastward() {
        XCTAssertEqual(JetlagModel.adjustmentDays(shiftHours: 2), 3, accuracy: 0.0001)
    }

    func testSydneyToManilaIsTwoDaysWestward() {
        XCTAssertEqual(JetlagModel.adjustmentDays(shiftHours: -2), 2, accuracy: 0.0001)
    }

    /// The derivation's premise. A τ that had drifted below 24 h would invert
    /// the argument in the doc comment without changing a line of arithmetic.
    func testIntrinsicPeriodIsLongerThanADay() {
        XCTAssertGreaterThan(JetlagModel.intrinsicPeriodHours, 24)
    }

    // MARK: - Folding

    func testFoldTakesTheShortWayRound() {
        // Sydney → Los Angeles is −19 h written out; the clock advances 5.
        XCTAssertEqual(JetlagModel.fold(-19), 5, accuracy: 0.0001)
        XCTAssertEqual(JetlagModel.fold(19), -5, accuracy: 0.0001)
    }

    func testFoldLeavesOrdinaryShiftsAlone() {
        XCTAssertEqual(JetlagModel.fold(2), 2, accuracy: 0.0001)
        XCTAssertEqual(JetlagModel.fold(-8), -8, accuracy: 0.0001)
    }

    /// Exactly twelve is a genuine tie and is read as the harder direction.
    func testTwelveStaysEastward() {
        XCTAssertEqual(JetlagModel.fold(12), 12, accuracy: 0.0001)
        XCTAssertEqual(JetlagModel.fold(-12), 12, accuracy: 0.0001)
    }

    /// A nineteen-hour arithmetic difference must not cost nineteen zones of
    /// adjustment — that is the whole point of folding, and getting it wrong
    /// would print a four-week recovery for a real journey.
    func testAdjustmentUsesTheFoldedDose() {
        XCTAssertEqual(JetlagModel.adjustmentDays(shiftHours: -19),
                       5 * JetlagModel.daysPerZoneEastward, accuracy: 0.0001)
    }

    // MARK: - The comparison window

    func testWindowGrowsWithTheDose() {
        XCTAssertLessThan(JetlagModel.windowDays(shiftHours: 1),
                          JetlagModel.windowDays(shiftHours: 8))
    }

    /// The defect this replaces: a flat four days for every journey.
    func testWindowIsAtLeastOneDayAndIsCapped() {
        XCTAssertEqual(JetlagModel.windowDays(shiftHours: 0.5), 1)
        XCTAssertEqual(JetlagModel.windowDays(shiftHours: 12),
                       JetlagModel.maximumWindowDays)
    }

    // MARK: - Crossings from the calendar

    func testCalendarCrossingIsSignedEastwardForManilaToSydney() {
        let cal = calendar(sydney)
        let events = [
            event(manila, instant(manila, 2026, 8, 4, 10), id: "a"),
            event(manila, instant(manila, 2026, 8, 5, 10), id: "b"),
            event(sydney, instant(sydney, 2026, 8, 7, 10), id: "c"),
        ]
        let found = JetlagModel.crossings(events: events, calendar: cal)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].shiftHours, 2, accuracy: 0.0001)
        XCTAssertTrue(found[0].isEastward)
        XCTAssertEqual(found[0].from, manila.identifier)
        XCTAssertEqual(found[0].to, sydney.identifier)
        XCTAssertEqual(found[0].evidence, .calendar)
    }

    /// ⚠️ **The reason this walks the events itself.** `timeZoneChanges` drops
    /// the zone moved *from*, so a signed dose reconstructed from its output
    /// alone loses the very first change — half the evidence on a two-trip
    /// record. Both must still find the same *number* of changes.
    func testFindsTheSameChangesAsCalendarModel() {
        let cal = calendar(sydney)
        let events = [
            event(manila, instant(manila, 2026, 8, 1, 9), id: "a"),
            event(sydney, instant(sydney, 2026, 8, 7, 9), id: "b"),
            event(manila, instant(manila, 2026, 8, 20, 9), id: "c"),
        ]
        XCTAssertEqual(JetlagModel.crossings(events: events, calendar: cal).count,
                       CalendarModel.timeZoneChanges(events, calendar: cal).count)
    }

    /// A homeward leg is the mirror of the outbound one, and must be negative.
    func testReturnLegIsWestward() {
        let cal = calendar(sydney)
        let events = [
            event(sydney, instant(sydney, 2026, 8, 1, 9), id: "a"),
            event(manila, instant(manila, 2026, 8, 3, 9), id: "b"),
        ]
        let found = JetlagModel.crossings(events: events, calendar: cal)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].shiftHours, -2, accuracy: 0.0001)
        XCTAssertFalse(found[0].isEastward)
    }

    /// A change of zone *name* with no change of offset is not a journey the
    /// body notices. Sydney and Melbourne are one zone in two names.
    func testSameOffsetUnderADifferentNameIsNotACrossing() {
        let melbourne = TimeZone(identifier: "Australia/Melbourne")!
        let cal = calendar(sydney)
        let events = [
            event(sydney, instant(sydney, 2026, 8, 1, 9), id: "a"),
            event(melbourne, instant(melbourne, 2026, 8, 3, 9), id: "b"),
        ]
        XCTAssertTrue(JetlagModel.crossings(events: events, calendar: cal).isEmpty)
    }

    // MARK: - Crossings measured off the reading

    func testMeasuredCrossingComesFromTheNightsZoneSpan() {
        let day = instant(sydney, 2026, 8, 7, 12)
        let spans = [day: SleepTravel.ZoneSpan(atSleep: 8 * 3600, atWake: 10 * 3600)]
        let found = JetlagModel.crossings(spans: spans)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].shiftHours, 2, accuracy: 0.0001)
        XCTAssertEqual(found[0].evidence, .measured)
    }

    func testANightThatDidNotMoveIsNotACrossing() {
        let day = instant(sydney, 2026, 8, 7, 12)
        let spans = [day: SleepTravel.ZoneSpan(atSleep: 10 * 3600, atWake: 10 * 3600)]
        XCTAssertTrue(JetlagModel.crossings(spans: spans).isEmpty)
    }

    /// A measured one-hour shift may be a clock change rather than a flight, and
    /// the card is required to say so rather than announce a journey.
    func testAnHourMeasuredIsFlaggedAsPossiblyDaylightSaving() {
        let day = instant(sydney, 2026, 4, 5, 12)
        let spans = [day: SleepTravel.ZoneSpan(atSleep: 11 * 3600, atWake: 10 * 3600)]
        XCTAssertTrue(JetlagModel.crossings(spans: spans)[0].possiblyDaylightSaving)
    }

    /// The calendar path keys on the zone *identifier*, which daylight saving
    /// does not change — so it can never raise the flag.
    func testCalendarCrossingIsNeverFlaggedAsDaylightSaving() {
        let cal = calendar(sydney)
        let events = [
            event(manila, instant(manila, 2026, 8, 1, 9), id: "a"),
            event(sydney, instant(sydney, 2026, 8, 7, 9), id: "b"),
        ]
        XCTAssertFalse(JetlagModel.crossings(events: events, calendar: cal)[0]
            .possiblyDaylightSaving)
    }

    // MARK: - Merging, so one journey is not counted twice

    func testOneJourneySeenBothWaysIsCountedOnceAndKeepsTheMeasurement() {
        let cal = calendar(sydney)
        let arrival = instant(sydney, 2026, 8, 7, 9)
        let measured = [cal.startOfDay(for: arrival):
                            SleepTravel.ZoneSpan(atSleep: 8 * 3600, atWake: 10 * 3600)]
        let events = [
            event(manila, instant(manila, 2026, 8, 1, 9), id: "a"),
            event(sydney, arrival, id: "b"),
        ]
        let merged = JetlagModel.merged(JetlagModel.crossings(spans: measured),
                                        JetlagModel.crossings(events: events, calendar: cal),
                                        calendar: cal)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].evidence, .measured)
    }

    func testTwoJourneysAFortnightApartStayTwo() {
        let cal = calendar(sydney)
        let events = [
            event(sydney, instant(sydney, 2026, 7, 1, 9), id: "a"),
            event(manila, instant(manila, 2026, 7, 10, 9), id: "b"),
            event(sydney, instant(sydney, 2026, 7, 25, 9), id: "c"),
        ]
        XCTAssertEqual(JetlagModel.merged(JetlagModel.crossings(events: events,
                                                                calendar: cal),
                                          calendar: cal).count, 2)
    }

    // MARK: - How many trips a measured recovery would need

    /// The row's actual ask: **say how many trips it would take** rather than
    /// fitting a curve to two. These are the numbers the card prints, and they
    /// come out of a power calculation with its effect size named.
    func testTripsNeededIsEightForALargeEffectAndThirtyTwoForHalfOfOne() {
        XCTAssertEqual(JetlagModel.tripsNeeded(effectSD: 1.0), 8)
        XCTAssertEqual(JetlagModel.tripsNeeded(effectSD: 0.5), 32)
    }

    func testSmallerEffectsNeedMoreTrips() {
        XCTAssertGreaterThan(JetlagModel.tripsNeeded(effectSD: 0.25),
                             JetlagModel.tripsNeeded(effectSD: 0.5))
    }

    // MARK: - Readiness, so no gate ever names the wrong cause

    func testNoEvidenceWhenNothingKnowsTheReaderMoved() {
        guard case .noEvidence = JetlagModel.analyse(events: [], samples: [],
                                                     calendar: calendar(sydney))
        else { return XCTFail("expected .noEvidence") }
    }

    /// One flight states its dose and refuses everything else. The dose is
    /// arithmetic on an offset and is true of one trip; a contrast is not.
    func testOneCrossingIsDoseOnly() {
        let cal = calendar(sydney)
        let events = [
            event(manila, instant(manila, 2026, 8, 1, 9), id: "a"),
            event(sydney, instant(sydney, 2026, 8, 7, 9), id: "b"),
        ]
        guard case .doseOnly(let out) = JetlagModel.analyse(events: events, samples: [],
                                                            calendar: cal)
        else { return XCTFail("expected .doseOnly") }
        XCTAssertEqual(out.crossings.count, 1)
        XCTAssertEqual(out.latest?.shiftHours, 2)
    }

    /// Trips exist, so the calendar is plainly connected. What is thin is the
    /// body data — and the gate has to say *that*, not "connect your calendar".
    /// A card naming the wrong cause is the defect the reader found on their own
    /// phone on 2026-08-07.
    func testTwoCrossingsWithNoBodyDataWaitOnSignalsRatherThanTheCalendar() {
        let cal = calendar(sydney)
        let events = [
            event(sydney, instant(sydney, 2026, 7, 1, 9), id: "a"),
            event(manila, instant(manila, 2026, 7, 10, 9), id: "b"),
            event(sydney, instant(sydney, 2026, 7, 25, 9), id: "c"),
        ]
        guard case .waiting(let gate) = JetlagModel.analyse(events: events, samples: [],
                                                            calendar: cal)
        else { return XCTFail("expected .waiting") }
        XCTAssertEqual(gate.unit, "responding signal")
        XCTAssertNotNil(gate.sentence)
    }

    /// End to end, with a body that responds: two crossings, a resting heart
    /// rate that runs higher in the days after each and a sleep duration that
    /// runs shorter. The section can then say what happened without pooling two
    /// trips into a curve.
    func testReadyReportsSignedChannelsAgainstOrdinaryDays() {
        let cal = calendar(sydney)
        let now = instant(sydney, 2026, 8, 10, 12)
        let events = [
            event(sydney, instant(sydney, 2026, 7, 1, 9), id: "a"),
            event(manila, instant(manila, 2026, 7, 10, 9), id: "b"),
            event(sydney, instant(sydney, 2026, 7, 25, 9), id: "c"),
        ]
        let disrupted = Set([10, 11, 25, 26, 27])   // west 2 days, east 3
        var samples: [HealthMetricSample] = []
        for day in 1...40 {
            guard let date = cal.date(byAdding: .day, value: -day,
                                      to: cal.startOfDay(for: now)) else { continue }
            let month = cal.component(.month, from: date)
            let dom = cal.component(.day, from: date)
            let hit = month == 7 && disrupted.contains(dom)
            // Ordinary days have to *vary*: `Baseline.robustScale` of a constant
            // is zero, the channel is refused for want of a denominator, and the
            // readiness falls through to `.waiting` — which is correct behaviour
            // and would make a flat fixture test nothing at all.
            let wobble = Double((day % 5) - 2)
            samples.append(HealthMetricSample(type: .restingHeartRate,
                                              value: (hit ? 62 : 54) + wobble,
                                              start: date, end: date, source: .appleHealth))
            samples.append(HealthMetricSample(type: .sleepDurationHours,
                                              value: (hit ? 5.5 : 7.5) + wobble * 0.2,
                                              start: date, end: date, source: .appleHealth))
        }
        guard case .ready(let out) = JetlagModel.analyse(events: events, samples: samples,
                                                         now: now, calendar: cal)
        else { return XCTFail("expected .ready") }
        XCTAssertEqual(out.crossings.count, 2)
        XCTAssertEqual(out.responses.count, 2)
        // Both channels moved the unwelcome way, and both say so with a positive
        // `towardWorse` despite pointing in opposite raw directions.
        for response in out.responses {
            XCTAssertGreaterThan(response.towardWorse, 0, "\(response.metric)")
            XCTAssertGreaterThan(response.daysCounted, 0)
        }
        XCTAssertEqual(out.tripsForLargeEffect, 8)
        XCTAssertFalse(out.hasMeasuredCrossing)
    }
}
