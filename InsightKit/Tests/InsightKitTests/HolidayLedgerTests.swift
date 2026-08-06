import XCTest
@testable import InsightKit

/// One dated record of leave, two sources — B7 H5, and the detection that
/// feeds it — H3.
///
/// ⚠️ Every title here is invented; no real calendar appears in fixtures.
final class HolidayLedgerTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    /// Midnight `n` days before `now` — the ledger thinks in whole days.
    private func day(_ n: Int) -> Date {
        utc.startOfDay(for: now.addingTimeInterval(-Double(n) * 86_400))
    }

    private func period(from: Int, to: Int, label: String? = nil,
                        source: HolidayLedger.Period.Source) -> HolidayLedger.Period {
        HolidayLedger.Period(firstDay: day(from), lastDay: day(to),
                             label: label, source: source)
    }

    // MARK: - The merge

    /// The same week off usually exists twice — a calendar block and a typed
    /// record — and a card reading both would count one holiday as two.
    func testAnOverlappingDetectedAndEnteredPeriodMergeIntoOne() throws {
        let ledger = HolidayLedger(
            detected: [period(from: 10, to: 6, source: .detected)],
            entered: [period(from: 9, to: 5, label: "Coast trip", source: .entered)],
            calendar: utc)
        XCTAssertEqual(ledger.periods.count, 1)
        let merged = try XCTUnwrap(ledger.periods.first)
        XCTAssertEqual(merged.firstDay, day(10), "the union's start")
        XCTAssertEqual(merged.lastDay, day(5), "the union's end")
        XCTAssertEqual(merged.label, "Coast trip",
                       "the reader's own words outrank the calendar's suggestion")
        XCTAssertEqual(merged.source, .entered)
    }

    /// Adjacent is not overlapping: two holidays back to back are two
    /// holidays, and merging them would erase which was which.
    func testAdjacentPeriodsStaySeparate() {
        let ledger = HolidayLedger(
            entered: [period(from: 10, to: 8, source: .entered),
                      period(from: 7, to: 5, source: .entered)],
            calendar: utc)
        XCTAssertEqual(ledger.periods.count, 2)
    }

    /// Re-entering the same leave twice is one period, not two — the merge is
    /// what makes double entry harmless.
    func testDuplicateEntriesDeduplicate() {
        let ledger = HolidayLedger(
            entered: [period(from: 9, to: 5, source: .entered),
                      period(from: 9, to: 5, source: .entered)],
            calendar: utc)
        XCTAssertEqual(ledger.periods.count, 1)
    }

    /// A reversed interval from a sheet whose pickers crossed is absorbed by
    /// the type, once, rather than corrupting every consumer.
    func testAReversedIntervalIsNormalised() {
        let reversed = HolidayLedger.Period(firstDay: day(3), lastDay: day(8),
                                            label: nil, source: .entered)
        XCTAssertEqual(reversed.firstDay, day(8))
        XCTAssertEqual(reversed.lastDay, day(3))
        XCTAssertEqual(reversed.dayCount(calendar: utc), 6, "both ends inclusive")
    }

    // MARK: - What the cards will read (H6, deliberately not wired yet)

    func testDaysSinceLastLeaveCountsFromTheLastDayOff() {
        let ledger = HolidayLedger(
            entered: [period(from: 30, to: 24, source: .entered)], calendar: utc)
        XCTAssertEqual(ledger.daysSinceLastLeave(asOf: now, calendar: utc), 24)
    }

    func testDaysSinceLastLeaveIsZeroWhileOnLeave() {
        let ledger = HolidayLedger(
            entered: [period(from: 2, to: -2, source: .entered)], calendar: utc)
        XCTAssertEqual(ledger.daysSinceLastLeave(asOf: now, calendar: utc), 0)
    }

    /// "You have a holiday booked" is a different answer from "you had one
    /// recently" — planned future leave must not satisfy a question about
    /// recovery, and no leave at all is nil rather than a large number.
    func testFutureLeaveAloneAnswersNilNotZero() {
        let planned = HolidayLedger(
            entered: [period(from: -10, to: -14, source: .entered)], calendar: utc)
        XCTAssertNil(planned.daysSinceLastLeave(asOf: now, calendar: utc))
        XCTAssertNil(HolidayLedger().daysSinceLastLeave(asOf: now, calendar: utc))
    }

    /// Touching, not contained: a fortnight that ends inside the window was
    /// still leave inside the window.
    func testLeaveInRangeFindsPeriodsTouchingTheRange() {
        let ledger = HolidayLedger(
            entered: [period(from: 40, to: 35, source: .entered),
                      period(from: 20, to: 18, source: .entered),
                      period(from: 4, to: 2, source: .entered)],
            calendar: utc)
        let window = DateInterval(start: day(21), end: day(10))
        let inWindow = ledger.leave(in: window, calendar: utc)
        XCTAssertEqual(inWindow.count, 1)
        XCTAssertEqual(inWindow.first?.firstDay, day(20))

        // A period straddling the window's start still touches it.
        let straddling = DateInterval(start: day(19), end: day(10))
        XCTAssertEqual(ledger.leave(in: straddling, calendar: utc).count, 1)
    }

    // MARK: - Detection (H3)

    private func allDayEvent(_ title: String, from: Int, days: Int,
                             kind: CalendarEvent.Kind) -> CalendarEvent {
        CalendarEvent(id: title, start: day(from),
                      end: day(from).addingTimeInterval(Double(days) * 86_400),
                      isAllDay: true, timeZoneIdentifier: nil,
                      calendarName: "Work", kind: kind, title: title)
    }

    private func judged(_ event: CalendarEvent,
                        identity: ReaderIdentity?) -> CalendarEventJudgement {
        CalendarEventJudgement(
            eventID: event.id,
            classification: CalendarEventClassifier.classify(event, identity: identity))
    }

    /// The pipeline end to end: an all-day "Annual leave" block, classified as
    /// the reader's own, becomes a detected holiday — dated, and **unlabelled**,
    /// because an event title must never travel into a ledger that exports.
    func testAClassifiedLeaveBlockBecomesADetectedHolidayWithoutItsTitle() {
        let identity = ReaderIdentity(name: "Alex Reader",
                                      workEmails: ["a.reader@example.com"])
        let block = allDayEvent("Annual leave", from: 10, days: 5, kind: .multiDay)
        let detected = HolidayLedger.detected(
            events: [block], judgements: [judged(block, identity: identity)],
            calendar: utc)
        XCTAssertEqual(detected.count, 1)
        XCTAssertEqual(detected.first?.firstDay, day(10))
        XCTAssertEqual(detected.first?.lastDay, day(6),
                       "an all-day end is exclusive; the last day off is the day before it")
        XCTAssertNil(detected.first?.label, "the event's words stay with the event")
        XCTAssertEqual(detected.first?.source, .detected)
    }

    /// A colleague's OOO and an unowned marker feed nothing: the ledger holds
    /// the *reader's* leave, and ambiguity was already decided against.
    func testSomeoneElsesAbsenceAndAmbiguousBlocksDetectNothing() {
        let identity = ReaderIdentity(name: "Alex Reader")
        let theirs = allDayEvent("Sam OOO", from: 8, days: 3, kind: .multiDay)
        let unowned = allDayEvent("Out of office", from: 4, days: 2, kind: .multiDay)
        XCTAssertTrue(HolidayLedger.detected(
            events: [theirs], judgements: [judged(theirs, identity: identity)],
            calendar: utc).isEmpty)
        XCTAssertTrue(HolidayLedger.detected(
            events: [unowned], judgements: [judged(unowned, identity: nil)],
            calendar: utc).isEmpty, "no identity: ambiguous, and never leave")
    }

    /// A two-hour timed "OOO" is an absence from meetings, not a holiday —
    /// counting it would reset days-since-leave on every dentist trip.
    func testATimedOOOIsNotADetectedHoliday() {
        let identity = ReaderIdentity(name: "Alex Reader")
        let slot = CalendarEvent(id: "slot", start: day(3),
                                 end: day(3).addingTimeInterval(2 * 3600),
                                 isAllDay: false, timeZoneIdentifier: nil,
                                 calendarName: "Work", kind: .timed, title: "OOO")
        XCTAssertTrue(HolidayLedger.detected(
            events: [slot], judgements: [judged(slot, identity: identity)],
            calendar: utc).isEmpty)
    }

    /// The reader's correction reaches the ledger: confirming "that's actually
    /// my leave" on a block the rules called someone else's is one tap, and
    /// detection reads the *effective* classification.
    func testACorrectionToLeaveReachesTheLedger() {
        let block = allDayEvent("Sam OOO", from: 8, days: 3, kind: .multiDay)
        let identity = ReaderIdentity(name: "Alex Reader")
        let guess = CalendarEventClassifier.classify(block, identity: identity)
        XCTAssertEqual(guess.occasion, .absence)
        let corrected = CalendarEventJudgement(
            eventID: block.id, classification: guess,
            correction: CalendarEventClassification(
                context: guess.context, occasion: .leave, presence: guess.presence,
                formality: guess.formality, hours: guess.hours))
        XCTAssertEqual(HolidayLedger.detected(events: [block],
                                              judgements: [corrected],
                                              calendar: utc).count, 1)
    }
}
