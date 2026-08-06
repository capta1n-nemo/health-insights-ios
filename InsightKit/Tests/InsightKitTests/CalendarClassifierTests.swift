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
                       kind: CalendarEvent.Kind? = nil) -> CalendarEvent {
        CalendarEvent(id: title, start: now, end: now.addingTimeInterval(hours * 3600),
                      isAllDay: allDay, timeZoneIdentifier: "Europe/London",
                      calendarName: calendarName,
                      kind: kind ?? (allDay ? .allDay : .timed),
                      title: title, location: location, hasVideoLink: link)
    }

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
}
