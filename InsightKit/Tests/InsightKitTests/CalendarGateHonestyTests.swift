import XCTest
@testable import InsightKit

/// **A card must never tell the reader to do something they have already done.**
///
/// Found on the reader's own phone, 2026-08-07: Travel drain said *"Connect your
/// calendar"* while their calendar was connected. `TravelDrainModel.evaluate`
/// returned `nil` down three separate paths — too few trips, too few days either
/// side of them, too few responding signals — and `WorkImpactModel` down five.
/// Every one of them rendered the same invitation.
///
/// That is backlog D46 (*"every 'not enough yet' gate is invisible"*) in its
/// worst form. A silent gate leaves the reader guessing; a gate that names the
/// **wrong cause** makes them act, and nothing changes. Worse, it is unfalsifiable
/// from the outside — the card looks like it is working.
///
/// So these tests assert the one thing that matters and would have caught it:
/// **if the app is holding calendar events, no card may ask for a calendar.**
final class CalendarGateHonestyTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)
    private lazy var now = TestClock.now

    /// One ordinary event, so the calendar is unambiguously connected — and far
    /// too little of anything else for either card to score.
    private func oneEvent() -> [CalendarEvent] {
        let start = now.addingTimeInterval(-3 * 86_400)
        return [CalendarEvent(id: "e1",
                              start: start, end: start.addingTimeInterval(1800),
                              isAllDay: false,
                              timeZoneIdentifier: "Australia/Sydney",
                              calendarName: "Work", kind: .timed,
                              title: "Standup", location: nil,
                              hasVideoLink: true, organizerIsReader: false,
                              attendeeCount: 3)]
    }

    func testTravelDrainNeverAsksForACalendarItAlreadyHas() {
        let card = TravelDrainInsight(events: oneEvent())
            .evaluate(samples: [], profile: UserHealthProfile(), now: now)

        XCTAssertFalse(card.headline.localizedCaseInsensitiveContains("connect"),
                       "Travel drain asked for a calendar while holding events — the reader's 2026-08-07 defect: \(card.headline)")
        XCTAssertFalse((card.explanation ?? "").localizedCaseInsensitiveContains("connect your calendar"),
                       "the explanation still tells the reader to connect a connected calendar")
        XCTAssertFalse(card.invitesInput,
                       "a coverage gate is not an invitation — there is nothing the reader can give")
        XCTAssertTrue((card.explanation ?? "").localizedCaseInsensitiveContains("trip"),
                      "the card must name what it is actually waiting for: \(card.explanation ?? "nil")")
    }

    func testWorkImpactNeverAsksForACalendarItAlreadyHas() {
        let card = WorkImpactInsight(events: oneEvent(), judgements: [])
            .evaluate(samples: [], profile: UserHealthProfile(), now: now)

        XCTAssertFalse(card.headline.localizedCaseInsensitiveContains("connect"),
                       "Work impact asked for a calendar while holding events: \(card.headline)")
        XCTAssertFalse(card.invitesInput,
                       "a coverage gate is not an invitation")
    }

    /// The other half, and it must keep working: with **no** events, "connect it"
    /// is the true and useful thing to say. A fix that made both cards silent
    /// would trade one wrong message for a worse one.
    func testWithNoCalendarAtAllTheInvitationIsStillOffered() {
        let travel = TravelDrainInsight(events: [])
            .evaluate(samples: [], profile: UserHealthProfile(), now: now)
        let work = WorkImpactInsight(events: [], judgements: [])
            .evaluate(samples: [], profile: UserHealthProfile(), now: now)

        XCTAssertTrue(travel.headline.localizedCaseInsensitiveContains("connect"),
                      "with no events at all, asking for the calendar is correct")
        XCTAssertTrue(travel.invitesInput, "and that one IS an invitation")
        XCTAssertTrue(work.headline.localizedCaseInsensitiveContains("connect"))
        XCTAssertTrue(work.invitesInput)
    }

    /// The gate has to be *readable*, not merely present. A `CoverageGate` whose
    /// requirement is already met returns a nil sentence, and a card rendering
    /// that would print the context and then stop mid-thought.
    func testTheWaitingSentenceSaysBothHowManyAndWhatFor() {
        let card = TravelDrainInsight(events: oneEvent())
            .evaluate(samples: [], profile: UserHealthProfile(), now: now)
        let text = card.explanation ?? ""

        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("\(TravelDrainModel.minimumTrips)"),
                      "the reader should see the number it is counting to: \(text)")
        XCTAssertGreaterThan(text.count, 80,
                             "a bare fragment is not an explanation: \(text)")
    }

    // MARK: - The card must still be ON SCREEN while it waits

    /// ⚠️ **The defect the first fix caused, found by the reader within the hour:
    /// *"Where is the travel card gone"*.**
    ///
    /// `waitingOn` correctly sets `invitesInput: false` — a coverage gate is not
    /// an invitation, because there is nothing the reader can give. But
    /// `isWorthShowing` was `primaryValue != nil || !unmetRequirements.isEmpty
    /// || isAwaitingTodaysData || invitesInput`, so all four went false and the
    /// card **vanished from the list**.
    ///
    /// `CardVisibilityTests.testEveryCardStaysOnScreenEvenWithNothingAtAll` did
    /// not catch it, and the reason is worth keeping: with *nothing at all* the
    /// model returns `.noCalendar`, which still invites input and is still
    /// visible. **The invisible state needed a card that is connected and still
    /// counting** — a fixture nobody had, because it is the state between the
    /// two everybody tests.
    func testACardWaitingOnCoverageIsStillOnScreen() {
        let travel = TravelDrainInsight(events: oneEvent())
            .evaluate(samples: [], profile: UserHealthProfile(), now: now)
        let work = WorkImpactInsight(events: oneEvent(), judgements: [])
            .evaluate(samples: [], profile: UserHealthProfile(), now: now)

        XCTAssertTrue(travel.isWorthShowing,
                      "Travel drain vanished while waiting — standing rule 2: every card shows, even with no data")
        XCTAssertTrue(work.isWorthShowing, "Work impact vanished while waiting")
        XCTAssertTrue(travel.isLearning, "the card should say it is still counting")
        XCTAssertFalse(travel.invitesInput,
                       "and it must NOT claim there is something to give — that was the original defect")
    }

    /// The flag has to survive the rebuild, because a field-by-field rebuild
    /// silently dropping one is a defect this repo has shipped twice
    /// (`invitesInput` in 2026-08-05, `subheadline` in D24).
    func testTheLearningFlagSurvivesAppendingDriverLines() {
        let card = TravelDrainInsight(events: oneEvent())
            .evaluate(samples: [], profile: UserHealthProfile(), now: now)
            .appending(driverLines: [InsightDriver(text: "extra", isNotable: false)])
        XCTAssertTrue(card.isLearning, "appending(driverLines:) dropped isLearning")
        XCTAssertTrue(card.isWorthShowing)
    }
}
