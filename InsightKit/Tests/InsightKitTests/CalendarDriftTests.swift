import XCTest
@testable import InsightKit

/// **An event that changed after it was judged** — backlog B8 R3 + C4.
///
/// The fourth section is the one that matters: a re-judgement must move the
/// guess and the snapshot and must not be able to reach the reader's answer.
final class CalendarDriftTests: XCTestCase {

    private let judgedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(id: String = "evt-1",
                       title: String = "Weekly planning",
                       location: String? = "Room 2",
                       hours: Double = 1,
                       startOffset: TimeInterval = 0,
                       calendarName: String = "Work",
                       attendees: Int? = 4,
                       allDay: Bool = false) -> CalendarEvent {
        let start = judgedAt.addingTimeInterval(startOffset)
        return CalendarEvent(id: id, start: start,
                             end: start.addingTimeInterval(hours * 3600),
                             isAllDay: allDay, timeZoneIdentifier: nil,
                             calendarName: calendarName, kind: .timed,
                             title: title, location: location,
                             hasVideoLink: false, organizerIsReader: true,
                             attendeeCount: attendees)
    }

    private func judgement(for event: CalendarEvent,
                           correction: CalendarEventClassification? = nil,
                           confirmed: Bool = false,
                           reviewed: Date? = nil,
                           snapshot: Bool = true) -> CalendarEventJudgement {
        CalendarEventJudgement(
            eventID: event.id,
            classification: CalendarEventClassifier.classify(event),
            correction: correction,
            isConfirmed: confirmed,
            reviewedAt: reviewed,
            artifact: snapshot ? CalendarEventArtifact(event: event, capturedAt: judgedAt) : nil)
    }

    // MARK: 1 — a changed event is detected

    func testARenamedEventIsDetected() {
        let original = event()
        let stored = judgement(for: original)
        let renamed = event(title: "Client review")
        XCTAssertTrue(stored.hasDrifted(from: renamed))
        XCTAssertEqual(CalendarEventClassifier.drifted([stored], events: [renamed]).map(\.id),
                       ["evt-1"])
    }

    func testALengthenedEventIsDetected() {
        let stored = judgement(for: event())
        XCTAssertTrue(stored.hasDrifted(from: event(hours: 3)))
    }

    func testAMovedEventIsDetected() {
        // The start is on the snapshot now, so a slot change is drift even when
        // nothing else about the event moved.
        let stored = judgement(for: event())
        XCTAssertTrue(stored.hasDrifted(from: event(startOffset: 3600)))
    }

    func testEveryAxisTheTaskNames() {
        let stored = judgement(for: event())
        XCTAssertTrue(stored.hasDrifted(from: event(title: "Other")))
        XCTAssertTrue(stored.hasDrifted(from: event(location: nil)))
        XCTAssertTrue(stored.hasDrifted(from: event(hours: 2)))
        XCTAssertTrue(stored.hasDrifted(from: event(startOffset: 900)))
        XCTAssertTrue(stored.hasDrifted(from: event(calendarName: "Family")))
        XCTAssertTrue(stored.hasDrifted(from: event(attendees: 9)))
        XCTAssertTrue(stored.hasDrifted(from: event(allDay: true)))
    }

    func testASnapshotWithNoStartCannotSayTheEventMoved() {
        // The one place the optional start earns its optionality: a row written
        // before the field existed decodes with `start == nil`, and "cannot tell"
        // must not read as "changed" — that would re-judge every pre-existing row
        // on the first sync after the upgrade.
        let original = event()
        let old = CalendarEventArtifact(
            title: original.title, location: original.location,
            attendeeCount: original.attendeeCount,
            durationHours: original.durationHours,
            isAllDay: original.isAllDay, calendarName: original.calendarName,
            hasVideoLink: original.hasVideoLink,
            organizerIsReader: original.organizerIsReader, capturedAt: judgedAt)
        XCTAssertNil(old.start)
        XCTAssertFalse(old.differs(from: event(startOffset: 7200)))
        XCTAssertTrue(old.differs(from: event(title: "Renamed")))
    }

    // MARK: 2 — an unchanged event is not re-judged

    func testAnUnchangedEventIsNotDrift() {
        let original = event()
        let stored = judgement(for: original)
        XCTAssertFalse(stored.hasDrifted(from: original))
        XCTAssertTrue(CalendarEventClassifier.drifted([stored], events: [original]).isEmpty)
    }

    func testAnUnjudgedEventIsNotDrift() {
        // Unjudged is not changed. The sync path classifies those separately and
        // counting them here would re-judge the whole calendar on first run.
        XCTAssertTrue(CalendarEventClassifier.drifted([], events: [event()]).isEmpty)
    }

    func testAJudgementWithNoSnapshotIsNeverDrift() {
        let stored = judgement(for: event(), snapshot: false)
        XCTAssertFalse(stored.hasDrifted(from: event(title: "Renamed")))
        XCTAssertTrue(CalendarEventClassifier.drifted([stored],
                                                      events: [event(title: "Renamed")]).isEmpty)
    }

    // MARK: 3 — re-judging moves the guess and the snapshot

    func testRejudgingMovesTheGuessAndTheSnapshot() throws {
        let original = event(title: "Weekly planning", calendarName: "Work")
        let stored = judgement(for: original)
        let changed = event(title: "Dentist", calendarName: "Personal")
        let fresh = CalendarEventClassifier.classify(changed)
        let after = stored.reclassified(
            as: fresh, artifact: CalendarEventArtifact(event: changed))

        XCTAssertEqual(after.classification.context, .personal)
        let snapshot = try XCTUnwrap(after.artifact)
        XCTAssertEqual(snapshot.title, "Dentist")
        XCTAssertEqual(snapshot.calendarName, "Personal")
        // And the drift is now settled — the pair is each other's again.
        XCTAssertFalse(after.hasDrifted(from: changed))
    }

    // MARK: 4 — ⚠️ the invariant: a correction survives a re-judge

    func testAReaderCorrectionSurvivesARejudge() {
        let original = event(title: "Weekly planning", calendarName: "Work")
        let readerSaid = CalendarEventClassification(
            context: .personal, occasion: .blockedTime, presence: .inPerson,
            formality: .casual, hours: 1,
            deciders: [CalendarEventClassification.contextKey: .reader,
                       CalendarEventClassification.occasionKey: .reader,
                       CalendarEventClassification.formalityKey: .reader])
        let stored = judgement(for: original, correction: readerSaid,
                               confirmed: true, reviewed: judgedAt)

        let changed = event(title: "Client review workshop", hours: 5)
        let after = stored
            .markedChangedAfterReview(at: judgedAt.addingTimeInterval(86_400))
            .reclassified(as: CalendarEventClassifier.classify(changed),
                          artifact: CalendarEventArtifact(event: changed))

        // The guess moved.
        XCTAssertEqual(after.classification.formality, .formal)
        XCTAssertNotEqual(after.classification, stored.classification)
        // The reader's answer did not — on any axis.
        XCTAssertEqual(after.correction, readerSaid)
        XCTAssertEqual(after.effective, readerSaid)
        XCTAssertTrue(after.isConfirmed)
        XCTAssertEqual(after.reviewedAt, judgedAt)
        XCTAssertEqual(after.effective.decider(for: CalendarEventClassification.contextKey),
                       .reader)
    }

    func testTheChangedFlagOutlivesTheSnapshotRefresh() {
        // The reason the flag is stored rather than derived: re-judging is what
        // makes `hasDrifted` false again, so a derived flag would vanish exactly
        // when the reader most needs telling.
        let original = event()
        let stored = judgement(for: original,
                               correction: CalendarEventClassifier.classify(original),
                               confirmed: true, reviewed: judgedAt)
        let changed = event(title: "Renamed", hours: 4)
        let flagged = stored.markedChangedAfterReview(at: judgedAt.addingTimeInterval(60))
        XCTAssertTrue(flagged.needsRereview)

        let after = flagged.reclassified(as: CalendarEventClassifier.classify(changed),
                                         artifact: CalendarEventArtifact(event: changed))
        XCTAssertFalse(after.hasDrifted(from: changed))
        XCTAssertTrue(after.needsRereview, "a re-judgement must not silence the flag")
    }

    func testAnUnreviewedJudgementIsNeverFlagged() {
        // Nothing has gone stale — there is no answer. It is simply re-judged.
        let stored = judgement(for: event())
        let flagged = stored.markedChangedAfterReview(at: judgedAt)
        XCTAssertNil(flagged.changedAfterReviewAt)
        XCTAssertFalse(flagged.needsRereview)
    }

    func testTheFlagIsEarliestWins() {
        let stored = judgement(for: event(), confirmed: true, reviewed: judgedAt)
        let first = stored.markedChangedAfterReview(at: judgedAt.addingTimeInterval(60))
        let second = first.markedChangedAfterReview(at: judgedAt.addingTimeInterval(9_000))
        XCTAssertEqual(second.changedAfterReviewAt, judgedAt.addingTimeInterval(60))
    }

    func testReviewingAgainClearsTheFlag() {
        let stored = judgement(for: event(), confirmed: true, reviewed: judgedAt)
            .markedChangedAfterReview(at: judgedAt.addingTimeInterval(60))
        XCTAssertTrue(stored.needsRereview)
        let answered = stored.reviewed(correction: nil, confirmed: true,
                                       at: judgedAt.addingTimeInterval(120))
        XCTAssertNil(answered.changedAfterReviewAt)
        XCTAssertFalse(answered.needsRereview)
    }

    // MARK: 5 — the flag round-trips through JSON

    func testTheFlagSurvivesEncoding() throws {
        let stored = judgement(for: event(), confirmed: true, reviewed: judgedAt)
            .markedChangedAfterReview(at: judgedAt.addingTimeInterval(60))
        let data = try JSONEncoder().encode(stored)
        let back = try JSONDecoder().decode(CalendarEventJudgement.self, from: data)
        XCTAssertEqual(back.changedAfterReviewAt, stored.changedAfterReviewAt)
        XCTAssertEqual(back.artifact?.start, stored.artifact?.start)
    }
}
