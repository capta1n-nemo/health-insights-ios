import XCTest
@testable import InsightKit

/// **The correction record's three layers** — backlog B8 R3.
///
/// What the model guessed, what the reader said, and *the artifact it judged*.
/// The first two were already kept apart (C4) and tested; this suite covers the
/// third and, more importantly, the two invariants that make the trio worth
/// anything: the snapshot survives storage, and neither layer can overwrite
/// another.
final class CorrectionRecordTests: XCTestCase {

    private func event(title: String = "Quarterly review",
                       location: String? = "Level 3, 200 Example St",
                       attendees: Int? = 6,
                       hours: Double = 1.5,
                       allDay: Bool = false,
                       calendarName: String = "Work",
                       video: Bool = true) -> CalendarEvent {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return CalendarEvent(
            id: "evt-1", start: start, end: start.addingTimeInterval(hours * 3600),
            isAllDay: allDay, timeZoneIdentifier: "Australia/Sydney",
            calendarName: calendarName, kind: allDay ? .allDay : .timed,
            title: title, location: location, hasVideoLink: video,
            organizerIsReader: false, attendeeCount: attendees)
    }

    private func classification(
        context: CalendarEventClassification.Context = .work,
        occasion: CalendarEventClassification.Occasion = .meeting,
        formality: CalendarEventClassification.Formality = .formal
    ) -> CalendarEventClassification {
        CalendarEventClassification(context: context, occasion: occasion,
                                    presence: .inPerson, formality: formality,
                                    hours: 1.5)
    }

    // MARK: - The snapshot itself

    /// Every field the reader's brief named, taken off the event rather than
    /// re-derived: *"the whole email/artifact, so when we feed this back for
    /// improvement, it has all the context."*
    func testTheArtifactCapturesEveryFieldTheBriefNamed() {
        let captured = Date(timeIntervalSince1970: 1_700_000_500)
        let artifact = CalendarEventArtifact(event: event(), capturedAt: captured)

        XCTAssertEqual(artifact.title, "Quarterly review")
        XCTAssertEqual(artifact.location, "Level 3, 200 Example St")
        XCTAssertEqual(artifact.attendeeCount, 6)
        XCTAssertEqual(artifact.durationHours, 1.5, accuracy: 0.001)
        XCTAssertFalse(artifact.isAllDay)
        XCTAssertEqual(artifact.calendarName, "Work")
        XCTAssertTrue(artifact.hasVideoLink)
        XCTAssertEqual(artifact.organizerIsReader, false)
        XCTAssertEqual(artifact.capturedAt, captured)
    }

    /// Unknown is not zero. An event with no attendee records at all is the
    /// ordinary shape of something the reader typed into their own calendar,
    /// and reporting it as a nobody-came meeting would be a made-up figure.
    func testAnEventWithNoAttendeeRecordsSnapshotsAsUnknownRatherThanZero() {
        let artifact = CalendarEventArtifact(event: event(attendees: nil))
        XCTAssertNil(artifact.attendeeCount)
    }

    /// **The round trip**, which is what the whole layer is for: a correction
    /// that cannot be reloaded teaches nothing.
    func testTheSnapshotSurvivesARoundTrip() throws {
        let judgement = CalendarEventJudgement(
            eventID: "evt-1", classification: classification(),
            correction: classification(context: .personal, formality: .casual),
            isConfirmed: true, reviewedAt: Date(timeIntervalSince1970: 1_700_001_000),
            artifact: CalendarEventArtifact(event: event(),
                                            capturedAt: Date(timeIntervalSince1970: 1_700_000_500)))

        let data = try JSONEncoder().encode(judgement)
        let restored = try JSONDecoder().decode(CalendarEventJudgement.self, from: data)

        XCTAssertEqual(restored, judgement)
        XCTAssertEqual(restored.artifact?.title, "Quarterly review")
        XCTAssertEqual(restored.artifact?.attendeeCount, 6)
        XCTAssertEqual(restored.artifact?.capturedAt,
                       Date(timeIntervalSince1970: 1_700_000_500))
    }

    /// Rows written before B8 R3 have no snapshot, and must still decode. The
    /// alternative — inventing one from today's event — is exactly the
    /// history-rewrite the snapshot exists to prevent.
    func testAJudgementWithNoArtifactStillDecodes() throws {
        let judgement = CalendarEventJudgement(eventID: "evt-1",
                                               classification: classification())
        let data = try JSONEncoder().encode(judgement)
        let restored = try JSONDecoder().decode(CalendarEventJudgement.self, from: data)
        XCTAssertNil(restored.artifact)
        XCTAssertEqual(restored.classification, judgement.classification)
    }

    // MARK: - The three layers stay three layers

    /// Guess and correction remain separately readable after a correction —
    /// the C4 discipline, restated now that a third layer sits beside them.
    /// Merged, the app could never say how often it was right.
    func testACorrectionKeepsGuessAndCorrectionDistinguishable() {
        let guess = classification(context: .work, formality: .formal)
        let truth = classification(context: .personal, formality: .casual)
        let judgement = CalendarEventJudgement(
            eventID: "evt-1", classification: guess, correction: truth,
            isConfirmed: true, reviewedAt: Date(),
            artifact: CalendarEventArtifact(event: event()))

        XCTAssertEqual(judgement.classification.context, .work)
        XCTAssertEqual(judgement.correction?.context, .personal)
        XCTAssertEqual(judgement.effective.context, .personal,
                       "the rest of the app reads the correction")
        XCTAssertTrue(judgement.wasCorrected)
        XCTAssertNotNil(judgement.artifact, "and the artifact is a third thing again")
    }

    /// **Re-classifying must not overwrite the reader.** The store guarantees it
    /// by not having the correction in hand; this is the same rule as a value,
    /// which is the form that can actually be tested.
    func testReclassifyingDoesNotOverwriteAReadersCorrection() {
        let reviewedAt = Date(timeIntervalSince1970: 1_700_001_000)
        let original = CalendarEventJudgement(
            eventID: "evt-1",
            classification: classification(context: .work, formality: .formal),
            correction: classification(context: .personal, formality: .casual),
            isConfirmed: true, reviewedAt: reviewedAt,
            artifact: CalendarEventArtifact(event: event()))

        let rerun = original.reclassified(
            as: classification(context: .work, occasion: .blockedTime),
            artifact: CalendarEventArtifact(event: event(title: "Renamed later")))

        XCTAssertEqual(rerun.correction?.context, .personal,
                       "the reader's answer survived a re-run of the classifier")
        XCTAssertEqual(rerun.correction?.formality, .casual)
        XCTAssertTrue(rerun.isConfirmed)
        XCTAssertEqual(rerun.reviewedAt, reviewedAt)
        XCTAssertEqual(rerun.classification.occasion, .blockedTime,
                       "while the guess itself did move")
        XCTAssertEqual(rerun.artifact?.title, "Renamed later",
                       "and the artifact moved with the guess, not with the correction")
    }

    /// A re-classification with no event in hand keeps the snapshot it already
    /// has rather than dropping to two layers.
    func testReclassifyingWithoutAnArtifactKeepsTheStoredOne() {
        let original = CalendarEventJudgement(
            eventID: "evt-1", classification: classification(),
            artifact: CalendarEventArtifact(event: event()))
        let rerun = original.reclassified(as: classification(occasion: .travel))
        XCTAssertEqual(rerun.artifact?.title, "Quarterly review")
    }

    /// **Reviewing must not re-snapshot.** The model judged one version of an
    /// event; an event edited afterwards and re-captured at correction time
    /// would put words in front of the model it never saw.
    func testReviewingLeavesTheSnapshotAndTheGuessAlone() {
        let judged = CalendarEventArtifact(
            event: event(), capturedAt: Date(timeIntervalSince1970: 1_700_000_500))
        let original = CalendarEventJudgement(
            eventID: "evt-1", classification: classification(), artifact: judged)

        let reviewed = original.reviewed(
            correction: classification(context: .personal),
            confirmed: true, at: Date(timeIntervalSince1970: 1_700_090_000))

        XCTAssertEqual(reviewed.artifact, judged)
        XCTAssertEqual(reviewed.classification, original.classification)
        XCTAssertEqual(reviewed.correction?.context, .personal)
    }

    /// The snapshot can say the event has moved on since it was judged — which
    /// is the whole reason to keep a copy rather than a pointer.
    func testTheSnapshotNoticesAnEventEditedAfterwards() {
        let artifact = CalendarEventArtifact(event: event())
        XCTAssertFalse(artifact.differs(from: event()))
        XCTAssertTrue(artifact.differs(from: event(title: "Renamed later")))
        XCTAssertTrue(artifact.differs(from: event(attendees: 9)))
        XCTAssertTrue(artifact.differs(from: event(hours: 3)))
    }
}
