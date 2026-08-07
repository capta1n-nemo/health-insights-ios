import XCTest
@testable import InsightKit

/// **§B11's data spine** — the `.sick` classification (B11-6), the ledger it
/// feeds (B11-4), and the two ends of the reader's brief that are easy to get
/// backwards.
///
/// ⚠️ **Every fixture title here is invented.** This repo is public and an event
/// title is the most identifying string the app holds — none of the reader's own
/// calendar appears in this file, and none ever should.
final class SickDayTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    /// ⚠️ An obviously fake identity, per `docs/privacy-and-ip.md`.
    private let me = ReaderIdentity(name: "Alex Reader",
                                    workEmails: ["a.reader@example.com"])

    private func day(_ n: Int) -> Date {
        utc.startOfDay(for: now.addingTimeInterval(-Double(n) * 86_400))
    }

    private func event(_ title: String, hours: Double = 1,
                       calendarName: String = "Calendar",
                       allDay: Bool = false,
                       kind: CalendarEvent.Kind? = nil) -> CalendarEvent {
        CalendarEvent(id: title, start: now, end: now.addingTimeInterval(hours * 3600),
                      isAllDay: allDay, timeZoneIdentifier: "Europe/London",
                      calendarName: calendarName,
                      kind: kind ?? (allDay ? .allDay : .timed), title: title)
    }

    private func allDayEvent(_ title: String, from: Int, days: Int,
                             kind: CalendarEvent.Kind) -> CalendarEvent {
        CalendarEvent(id: title, start: day(from),
                      end: day(from).addingTimeInterval(Double(days) * 86_400),
                      isAllDay: true, timeZoneIdentifier: nil,
                      calendarName: "Work", kind: kind, title: title)
    }

    // MARK: - B11-6: the classifier learns "sick"

    /// The reader's ask: *"the calendar AI classifier must be able to classify a
    /// day as 'sick', in the same dropdown as meeting, reminder, travel."*
    func testTheReadersOwnSicknessBlocksClassifyAsSick() {
        for title in ["Off sick", "Sick day", "Sick leave", "Unwell", "Flu"] {
            XCTAssertEqual(
                CalendarEventClassifier.classify(event(title, allDay: true),
                                                 identity: me).occasion,
                .sick, "\(title) was not read as a sick day")
        }
    }

    /// Illness outranks leave where a title says both — the same shape of
    /// absence, and only one of the two is what §B11 counts.
    func testAnOOOThatSaysSickIsASickDayNotLeave() {
        XCTAssertEqual(
            CalendarEventClassifier.classify(event("OOO - off sick", allDay: true),
                                             identity: me).occasion,
            .sick)
    }

    /// Somebody else's sick day is somebody else's absence, by exactly the rule
    /// that makes "Sam OOO" one — the ownership ladder is shared, not copied.
    func testSomeoneElsesSickDayIsTheirAbsenceNotTheReadersSickDay() {
        let theirs = CalendarEventClassifier.classify(
            event("Sam off sick", hours: 8, calendarName: "Work"), identity: me)
        XCTAssertEqual(theirs.occasion, .absence)
        XCTAssertNotEqual(CalendarEventBucket(theirs), .work,
                          "a colleague's absence counted as the reader's work day")
    }

    /// A sick day is never meeting load, and never a work day — the same two
    /// guarantees `.leave` carries, for the same reason.
    func testASickDayCostsNoLoadAndIsNeverWork() {
        let sick = CalendarEventClassifier.classify(
            event("Sick day", hours: 8, calendarName: "Work", allDay: true), identity: me)
        XCTAssertEqual(sick.loadHours, 0)
        XCTAssertEqual(CalendarEventBucket(sick), .personal)
    }

    /// **Correctable both ways**, which the reader was explicit about. Nothing
    /// stops a travel guess becoming a sick day or a sick day becoming work —
    /// the occasion picker offers every case in both states.
    func testTheOccasionIsCorrectableInBothDirections() {
        XCTAssertTrue(CalendarEventClassification.Occasion.allCases.contains(.sick),
                      "the sick case has to be in the same dropdown as the others")
        let guess = CalendarEventClassifier.classify(event("Flight to Zurich"),
                                                     identity: me)
        XCTAssertEqual(guess.occasion, .travel)
        let toSick = CalendarEventClassification(
            context: guess.context, occasion: .sick, presence: guess.presence,
            formality: guess.formality, hours: guess.hours, severity: .moderate)
        XCTAssertEqual(toSick.occasion, .sick)
        let backToWork = CalendarEventClassification(
            context: .work, occasion: .meeting, presence: toSick.presence,
            formality: toSick.formality, hours: toSick.hours,
            severity: toSick.severity)
        XCTAssertEqual(backToWork.occasion, .meeting)
        XCTAssertNil(backToWork.severity,
                     "a severity must not survive an occasion that is no longer sick")
    }

    /// The two selectors the reader said are *not relevant* on a sick day, and
    /// the one that is. The predicate lives on the enum so the review row does
    /// not carry two `== .sick` tests of its own.
    func testOnlyASickDayDropsTheWorkAndFormalitySelectors() {
        for occasion in CalendarEventClassification.Occasion.allCases {
            XCTAssertEqual(occasion.asksAboutWorkAndFormality, occasion != .sick,
                           "\(occasion.rawValue)")
        }
        XCTAssertEqual(CalendarEventClassification.SickSeverity.allCases.count, 4)
    }

    /// A grade the reader gave is a correction like any other — `wasCorrected`
    /// has to see it, or the accuracy tally beside it counts the model as having
    /// been right about a field it never guessed.
    func testGradingASickDayCountsAsACorrection() {
        let guess = CalendarEventClassifier.classify(event("Off sick", allDay: true),
                                                     identity: me)
        XCTAssertNil(guess.severity, "the rules never guess how ill somebody was")
        let judgement = CalendarEventJudgement(
            eventID: "e", classification: guess,
            correction: CalendarEventClassification(
                context: guess.context, occasion: .sick, presence: guess.presence,
                formality: guess.formality, hours: guess.hours, severity: .severe))
        XCTAssertTrue(judgement.wasCorrected)
        XCTAssertEqual(judgement.effective.severity, .severe)
    }

    /// A severity survives a re-read of identity and a model refinement, and is
    /// never invented by either.
    func testSeveritySurvivesReoccasioningAndRefinement() {
        let base = CalendarEventClassification(
            context: .personal, occasion: .sick, presence: .unstated,
            formality: .standard, hours: 8, severity: .mild)
        let refined = CalendarEventClassifier.refined(base, modelContext: .work,
                                                      modelFormality: .formal)
        XCTAssertEqual(refined.severity, .mild)
    }

    /// Stored judgements written before §B11-6 have no `severity` key at all.
    /// Decoding must read that back as nil rather than throwing — otherwise the
    /// feature silently empties the reader's whole correction history.
    func testAClassificationStoredBeforeSeverityExistedStillDecodes() throws {
        let json = #"""
        {"context":"work","occasion":"meeting","presence":"remote",
         "formality":"standard","hours":1.5,"deciders":{}}
        """#
        let decoded = try JSONDecoder().decode(
            CalendarEventClassification.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.occasion, .meeting)
        XCTAssertNil(decoded.severity)
    }

    // MARK: - B11-4: the ledger

    /// The pipeline end to end: an all-day sick block becomes a dated period,
    /// **unlabelled**, because an event's words must never travel into a ledger
    /// that exports.
    func testAClassifiedSickBlockBecomesADetectedPeriodWithoutItsTitle() throws {
        let block = allDayEvent("Off sick", from: 10, days: 3, kind: .multiDay)
        let detected = SickDayLedger.detected(
            events: [block],
            judgements: [CalendarEventJudgement(
                eventID: block.id,
                classification: CalendarEventClassifier.classify(block, identity: me))],
            calendar: utc)
        XCTAssertEqual(detected.count, 1)
        let period = try XCTUnwrap(detected.first)
        XCTAssertEqual(period.firstDay, day(10))
        XCTAssertEqual(period.lastDay, day(8),
                       "an all-day end is exclusive; the last day ill is the day before it")
        XCTAssertNil(period.label, "the event's words stay with the event")
        XCTAssertEqual(period.dayCount(calendar: utc), 3)
    }

    /// A timed block is an errand, not a day in bed — counting it would reset
    /// days-since-ill on every appointment.
    func testATimedSickBlockIsNotADetectedPeriod() {
        let slot = CalendarEvent(id: "slot", start: day(3),
                                 end: day(3).addingTimeInterval(3600),
                                 isAllDay: false, timeZoneIdentifier: nil,
                                 calendarName: "Work", kind: .timed,
                                 title: "Sick note - call GP")
        XCTAssertTrue(SickDayLedger.detected(
            events: [slot],
            judgements: [CalendarEventJudgement(
                eventID: slot.id,
                classification: CalendarEventClassifier.classify(slot, identity: me))],
            calendar: utc).isEmpty)
    }

    /// **A week of flu is not leave.** The two ledgers read different occasions,
    /// and the reason this is a test rather than a comment: folding them
    /// together would let illness satisfy `daysSinceLastLeave` and read as
    /// recovery to every card B7 H6 will wire.
    func testASickDayNeverReachesTheHolidayLedger() {
        let block = allDayEvent("Off sick", from: 6, days: 2, kind: .multiDay)
        let judged = [CalendarEventJudgement(
            eventID: block.id,
            classification: CalendarEventClassifier.classify(block, identity: me))]
        XCTAssertEqual(SickDayLedger.detected(events: [block], judgements: judged,
                                              calendar: utc).count, 1)
        XCTAssertTrue(HolidayLedger.detected(events: [block], judgements: judged,
                                             calendar: utc).isEmpty)
    }

    /// Overlapping records of one illness merge, and **the worse grade
    /// survives** — a "mild" written on day one must not overwrite a "severe"
    /// written on day three.
    func testOverlappingPeriodsMergeAndKeepTheWorseGrade() throws {
        let ledger = SickDayLedger(
            detected: [SickDayLedger.Period(firstDay: day(10), lastDay: day(7),
                                            severity: .mild, source: .detected)],
            entered: [SickDayLedger.Period(firstDay: day(8), lastDay: day(5),
                                           label: "Flu", severity: .severe,
                                           source: .entered)],
            calendar: utc)
        XCTAssertEqual(ledger.periods.count, 1)
        let merged = try XCTUnwrap(ledger.periods.first)
        XCTAssertEqual(merged.firstDay, day(10))
        XCTAssertEqual(merged.lastDay, day(5))
        XCTAssertEqual(merged.label, "Flu", "the reader's own words outrank the calendar")
        XCTAssertEqual(merged.severity, .severe)
        XCTAssertEqual(merged.source, .entered)
    }

    /// Three genuinely different answers, and a ledger of only future-dated
    /// records must not read as "recently ill".
    func testDaysSinceLastSickDayDistinguishesNowRecentlyAndNever() {
        let onIt = SickDayLedger(entered: [.init(firstDay: day(1), lastDay: day(0),
                                                 source: .entered)], calendar: utc)
        XCTAssertEqual(onIt.daysSinceLastSickDay(asOf: now, calendar: utc), 0)

        let past = SickDayLedger(entered: [.init(firstDay: day(10), lastDay: day(8),
                                                 source: .entered)], calendar: utc)
        XCTAssertEqual(past.daysSinceLastSickDay(asOf: now, calendar: utc), 8)

        let ahead = SickDayLedger(entered: [.init(firstDay: day(-5), lastDay: day(-3),
                                                  source: .entered)], calendar: utc)
        XCTAssertNil(ahead.daysSinceLastSickDay(asOf: now, calendar: utc),
                     "booked ahead is not the same as recently ill")
    }

    /// The day set is what a count and a join read, and it must not double-count
    /// a merged spell.
    func testTheDaySetCountsEachDayOnce() {
        let ledger = SickDayLedger(
            detected: [.init(firstDay: day(6), lastDay: day(4), source: .detected)],
            entered: [.init(firstDay: day(5), lastDay: day(3), source: .entered)],
            calendar: utc)
        XCTAssertEqual(ledger.sickDays(calendar: utc).count, 4)
        XCTAssertEqual(
            ledger.dayCount(in: DateInterval(start: day(7), end: now), calendar: utc), 4)
    }
}
