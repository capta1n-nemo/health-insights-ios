import XCTest
@testable import InsightKit

/// Reading a calendar item on the six axes the reader named.
///
/// ⚠️ **Every fixture title here is invented.** This repo is public and an event
/// title is the most identifying string the app will ever hold — none of the
/// reader's own calendar appears in this file, and none ever should.
final class CalendarClassifierTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    private func event(_ title: String, hours: Double = 1,
                       calendarName: String = "Calendar",
                       location: String? = nil, link: Bool = false,
                       allDay: Bool = false,
                       kind: CalendarEvent.Kind? = nil,
                       organizerIsReader: Bool? = nil) -> CalendarEvent {
        CalendarEvent(id: title, start: now, end: now.addingTimeInterval(hours * 3600),
                      isAllDay: allDay, timeZoneIdentifier: "Europe/London",
                      calendarName: calendarName,
                      kind: kind ?? (allDay ? .allDay : .timed),
                      title: title, location: location, hasVideoLink: link,
                      organizerIsReader: organizerIsReader)
    }

    /// ⚠️ An obviously fake identity, per `docs/privacy-and-ip.md` — no real
    /// name or address ever appears in a fixture.
    private let me = ReaderIdentity(name: "Alex Reader",
                                    workEmails: ["a.reader@example.com"],
                                    personalEmails: ["alex@example.org"])

    // MARK: - The facts, which are not judgement calls

    /// ⚠️ **Half of the six axes are arithmetic or a field being present.**
    /// Asking a language model to decide those would be slower,
    /// non-deterministic and less accurate than reading them — and would put a
    /// hallucination between the reader and a fact their own calendar stated.
    func testPresenceAndDurationAreReadRatherThanInferred() {
        XCTAssertEqual(CalendarEventClassifier.classify(
            event("Project sync", location: "Room 3")).presence, .inPerson)
        XCTAssertEqual(CalendarEventClassifier.classify(
            event("Project sync", link: true)).presence, .remote)
        XCTAssertEqual(CalendarEventClassifier.classify(
            event("Project sync", location: "Room 3", link: true)).presence, .hybrid)
        XCTAssertEqual(CalendarEventClassifier.classify(
            event("Project sync")).presence, .unstated)

        let long = CalendarEventClassifier.classify(event("Planning day", hours: 6))
        XCTAssertEqual(long.hours, 6, accuracy: 0.001)
        XCTAssertTrue(long.isMarathon, "six hours in one stretch is a day, not a slot")
        XCTAssertFalse(CalendarEventClassifier.classify(event("Sync", hours: 1)).isMarathon)
    }

    /// The calendar's own name beats any reading of a title — someone keeping a
    /// "Work" calendar has already done the classification by hand, for years.
    func testTheCalendarNameOutranksTheTitleAndIsRecordedAsAFact() {
        let classified = CalendarEventClassifier.classify(
            event("Dentist", calendarName: "Work"))
        XCTAssertEqual(classified.context, .work)
        XCTAssertEqual(classified.decider(for: CalendarEventClassification.contextKey), .fact,
                       "a calendar the reader themselves named is not a guess")
    }

    // MARK: - The reader's own six

    func testATravelPlaceholderIsRecognisedAsTravel() {
        for title in ["Flight to Singapore", "Domestic flight", "Travel day",
                      "Airport transfer"] {
            XCTAssertEqual(CalendarEventClassifier.classify(event(title)).occasion, .travel,
                           "\(title) was not read as travel")
        }
    }

    /// ⚠️ **One rule catches most of "just something like a reminder" without
    /// reading a word**: an all-day entry with nowhere to be and nobody to dial
    /// is not a meeting.
    func testAnAllDayEntryWithNowhereToBeIsNotAMeeting() {
        let classified = CalendarEventClassifier.classify(event("Renew passport", allDay: true))
        XCTAssertEqual(classified.occasion, .reminder)
        XCTAssertEqual(classified.decider(for: CalendarEventClassification.occasionKey), .fact)
    }

    func testBlockedTimeIsNotCountedAsAMeeting() {
        XCTAssertEqual(CalendarEventClassifier.classify(event("Focus time")).occasion,
                       .blockedTime)
        XCTAssertEqual(CalendarEventClassifier.classify(event("Gym")).occasion, .blockedTime)
    }

    func testSentimentSeparatesACatchUpFromAClientReview() {
        XCTAssertEqual(CalendarEventClassifier.classify(event("Coffee catch up")).formality,
                       .casual)
        XCTAssertEqual(CalendarEventClassifier.classify(event("Client review")).formality,
                       .formal)
        XCTAssertEqual(CalendarEventClassifier.classify(event("Weekly update")).formality,
                       .standard)
    }

    /// An ambiguous title is left **unknown** rather than guessed. That is what
    /// the on-device model is asked about, and a rules-based coin toss wearing a
    /// confident label would be worse than an honest gap.
    func testAnAmbiguousTitleIsLeftForTheModelRatherThanGuessed() {
        XCTAssertEqual(CalendarEventClassifier.classify(event("Thing")).context, .unknown)
    }

    // MARK: - What the model may and may not touch

    /// ⚠️ **A language model overruling a fact is the failure this split exists
    /// to prevent.** It may move the two interpretive axes and nothing else.
    func testTheModelMayNotOverruleAContextTheCalendarNameSettled() {
        let base = CalendarEventClassifier.classify(event("Dentist", calendarName: "Work"))
        let refined = CalendarEventClassifier.refined(base, modelContext: .personal,
                                                      modelFormality: .casual)
        XCTAssertEqual(refined.context, .work, "the model overruled the calendar's own name")
        XCTAssertEqual(refined.formality, .casual, "but it may settle formality")
        XCTAssertEqual(refined.decider(for: CalendarEventClassification.formalityKey), .model)
    }

    func testTheModelSettlesAnAmbiguousContextAndIsRecordedAsHavingDoneSo() {
        let base = CalendarEventClassifier.classify(event("Thing"))
        let refined = CalendarEventClassifier.refined(base, modelContext: .work,
                                                      modelFormality: nil)
        XCTAssertEqual(refined.context, .work)
        XCTAssertEqual(refined.decider(for: CalendarEventClassification.contextKey), .model)
    }

    // MARK: - Load, and the learning loop

    /// Two hours are not two hours. A formal client meeting in a room costs more
    /// than two hours of blocked focus time, and counting them equally is what
    /// makes a "how busy were you" number useless.
    func testLoadIsNotJustHours() {
        let formalInPerson = CalendarEventClassifier.classify(
            event("Client review", hours: 2, location: "Their office"))
        let focus = CalendarEventClassifier.classify(event("Focus time", hours: 2))
        let reminder = CalendarEventClassifier.classify(
            event("Renew passport", allDay: true, kind: .allDay))

        XCTAssertGreaterThan(formalInPerson.loadHours, focus.loadHours)
        XCTAssertEqual(reminder.loadHours, 0, "a marker is not a commitment")
    }

    /// ⚠️ **A correction is stored beside the guess, never merged into it.**
    /// Merged, the app could never tell how often it was right, and re-running
    /// the classifier would silently overwrite the reader.
    func testACorrectionIsKeptApartFromTheGuessSoAccuracyIsMeasurable() {
        let guessed = CalendarEventClassifier.classify(event("Thing"))
        var corrected = CalendarEventJudgement(
            eventID: "1", classification: guessed,
            correction: CalendarEventClassification(
                context: .work, occasion: .meeting, presence: .remote,
                formality: .formal, hours: 1))
        XCTAssertTrue(corrected.wasCorrected)
        XCTAssertEqual(corrected.effective.context, .work, "the reader wins")
        XCTAssertEqual(corrected.classification.context, .unknown,
                       "and the original guess survives, or nothing can be measured")

        corrected = CalendarEventJudgement(eventID: "1", classification: guessed,
                                           isConfirmed: true)
        XCTAssertFalse(corrected.wasCorrected)
    }

    /// "Confirmed correct" and "not looked at yet" are different, and treating
    /// them as one would inflate every accuracy figure the app computes.
    func testAccuracyCountsOnlyWhatTheReaderActuallyReviewed() {
        let guess = CalendarEventClassifier.classify(event("Thing"))
        let judgements = (0..<12).map { index in
            CalendarEventJudgement(eventID: "\(index)", classification: guess,
                                   isConfirmed: index < 9,
                                   reviewedAt: index < 9 ? Date() : nil)
        }
        let accuracy = CalendarClassifierAccuracy.measure(judgements)
        XCTAssertEqual(accuracy.reviewed, 9, "three were never looked at")
        XCTAssertEqual(accuracy.agreed, 9)

        let tooFew = CalendarClassifierAccuracy.measure(Array(judgements.prefix(3)))
        XCTAssertNil(tooFew.rate, "three reviews is not an accuracy figure")
    }

    /// Travel outranks work and personal: a flight booked in a work calendar is
    /// still travel, and travel is what one of the two requested cards is about.
    func testTravelOutranksTheCalendarItWasBookedIn() {
        let flight = CalendarEventClassifier.classify(
            event("Flight to Singapore", calendarName: "Work"))
        XCTAssertEqual(CalendarEventBucket(flight), .travel)
    }

    // MARK: - Whose absence is this (B7 H2)

    /// The reader's brief, verbatim: *"someone just putting an 'OOO' or 'out of
    /// office' block in my calendar, sometimes its mine, sometimes its not"* —
    /// and *"'John smith on holiday - OOO' It can see if that is me, or someone
    /// else."* A name match makes it the reader's leave.
    func testAnOOOBlockNamingTheReaderIsTheirLeave() {
        let mine = CalendarEventClassifier.classify(
            event("Alex Reader on holiday - OOO", allDay: true), identity: me)
        XCTAssertEqual(mine.occasion, .leave)
        XCTAssertEqual(mine.loadHours, 0, "leave is never meeting load")
    }

    /// A name that is not the reader's makes it someone else's absence — never
    /// a meeting, zero load, and out of the work bucket even in a work
    /// calendar.
    func testAnOOOBlockNamingSomeoneElseIsNeverAWorkMeeting() {
        let theirs = CalendarEventClassifier.classify(
            event("Sam OOO", hours: 8, calendarName: "Work"), identity: me)
        XCTAssertEqual(theirs.occasion, .absence)
        XCTAssertEqual(theirs.loadHours, 0)
        XCTAssertNotEqual(CalendarEventBucket(theirs), .work,
                          "a colleague's absence counted as the reader's work day")
    }

    /// ⚠️ **Without identity, ownership cannot be claimed** — an absence marker
    /// classifies as ambiguous absence, and the one hard rule is that it never
    /// classifies as a work meeting.
    func testAnOOOBlockWithNoIdentityIsAmbiguousNeverAMeeting() {
        for title in ["OOO", "Out of office", "Annual leave"] {
            let classified = CalendarEventClassifier.classify(
                event(title, hours: 8, calendarName: "Work"))
            XCTAssertEqual(classified.occasion, .absence, "\(title) without identity")
            XCTAssertEqual(classified.loadHours, 0)
            XCTAssertNotEqual(CalendarEventBucket(classified), .work)
        }
    }

    /// With identity set, an *unnamed* leave marker is the reader's own — other
    /// people's absences arrive named ("Sam OOO") or organised by them, and a
    /// destination is not a person.
    func testAnUnnamedLeaveBlockIsTheReadersOwnOnceIdentityExists() {
        for title in ["OOO", "Annual leave", "Vacation", "PTO",
                      "Holiday to Sydney"] {
            XCTAssertEqual(CalendarEventClassifier.classify(
                event(title, allDay: true), identity: me).occasion, .leave,
                           "\(title) was not read as the reader's leave")
        }
    }

    /// The organiser fact settles ownership when the title says nothing — and
    /// it is recorded as a fact, because it was read off the event rather than
    /// judged.
    func testTheOrganiserFactSettlesAnUnnamedOOO() {
        let mine = CalendarEventClassifier.classify(
            event("OOO", organizerIsReader: true), identity: me)
        XCTAssertEqual(mine.occasion, .leave)
        XCTAssertEqual(mine.decider(for: CalendarEventClassification.occasionKey), .fact)

        let theirs = CalendarEventClassifier.classify(
            event("OOO", organizerIsReader: false), identity: me)
        XCTAssertEqual(theirs.occasion, .absence)
    }

    // MARK: - The vocabulary edges the brief demands judgement on

    /// **"Holiday party" is a party.** A leave word beside a gathering word is
    /// an event the reader attends, not an absence — the edge named in the
    /// brief, tested so the veto cannot quietly regress.
    func testAHolidayPartyIsNotLeave() {
        for title in ["Holiday party", "Holiday drinks", "Leaving party"] {
            let classified = CalendarEventClassifier.classify(event(title), identity: me)
            XCTAssertNotEqual(classified.occasion, .leave, "\(title) filed as leave")
            XCTAssertNotEqual(classified.occasion, .absence, "\(title) filed as absence")
        }
    }

    /// Word boundaries, not substrings: "Ann" must not be found inside
    /// "Annual", and a title merely *containing* leave letters is not leave.
    func testLeaveVocabularyMatchesWholeWordsOnly() {
        // "Bookkeeping review" contains no leave word as a word; "Leavers'
        // drinks" has a leave-ish stem and a gathering word.
        XCTAssertNotEqual(CalendarEventClassifier.classify(
            event("Bookkeeping review"), identity: me).occasion, .leave)
        XCTAssertNotEqual(CalendarEventClassifier.classify(
            event("Leavers drinks"), identity: me).occasion, .leave)
    }

    /// Bare "leave" doubles as a verb, and a departure is travel: "Leave for
    /// airport" belongs to the travel rule, not the holiday ledger.
    func testLeaveForAirportIsTravelNotAHoliday() {
        let departure = CalendarEventClassifier.classify(
            event("Leave for airport"), identity: me)
        XCTAssertEqual(departure.occasion, .travel)
    }

    /// A multi-day "Annual leave" block used to fall to the travel rule, which
    /// claims every multi-day non-reminder. The absence reading now runs first
    /// — this is the H3 shape, the block the ledger detects.
    func testAMultiDayAnnualLeaveBlockIsLeaveNotTravel() {
        let block = CalendarEventClassifier.classify(
            event("Annual leave", allDay: true, kind: .multiDay), identity: me)
        XCTAssertEqual(block.occasion, .leave)
        // And the reader's own leave is their life, not their job — whatever
        // calendar it was booked in.
        XCTAssertEqual(CalendarEventBucket(block), .personal)
    }

    // MARK: - Identity arriving later (H1 unblocks H2 retroactively)

    /// Entering a name re-reads the occasion of stored guesses and touches
    /// nothing else — a model-decided context must survive, or re-classifying
    /// would silently demote the better decision.
    func testReoccasionedMovesOnlyTheOccasionAndPreservesTheModelContext() {
        let stored = CalendarEventClassifier.refined(
            CalendarEventClassifier.classify(event("Annual leave", allDay: true)),
            modelContext: .personal, modelFormality: nil)
        XCTAssertEqual(stored.occasion, .absence, "no identity yet: ambiguous")

        let updated = CalendarEventClassifier.reoccasioned(
            stored, for: event("Annual leave", allDay: true), identity: me)
        XCTAssertEqual(updated?.occasion, .leave)
        XCTAssertEqual(updated?.context, .personal, "the model's context was demoted")
        XCTAssertEqual(updated?.decider(for: CalendarEventClassification.contextKey),
                       .model)

        // No change — no write. The caller skips the store round trip.
        XCTAssertNil(CalendarEventClassifier.reoccasioned(
            updated!, for: event("Annual leave", allDay: true), identity: me))
    }
}
