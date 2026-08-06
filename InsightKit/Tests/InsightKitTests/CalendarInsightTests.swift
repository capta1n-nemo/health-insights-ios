import XCTest
@testable import InsightKit

/// Work impact and travel drain — the two cards the reader asked for by name.
///
/// ⚠️ **The first two tests are the ones that matter.** Both cards compare the
/// reader's body on one kind of day against another, and both are exposed to the
/// same confound: a naive busy-versus-quiet split is mostly weekdays versus
/// weekends. A card built that way reports that meetings wreck your recovery
/// when what it found is that Saturday exists.
final class CalendarInsightTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    private func day(_ offset: Int) -> Date {
        utc.startOfDay(for: now.addingTimeInterval(Double(offset) * 86_400))
    }

    private func meeting(_ dayOffset: Int, hours: Double,
                         calendarName: String = "Work") -> CalendarEvent {
        let start = day(dayOffset).addingTimeInterval(9 * 3600)
        return CalendarEvent(id: "\(dayOffset)-\(hours)", start: start,
                             end: start.addingTimeInterval(hours * 3600),
                             isAllDay: false, timeZoneIdentifier: "Europe/London",
                             calendarName: calendarName, kind: .timed,
                             title: "Project sync", location: nil, hasVideoLink: true)
    }

    private func vitals(_ metric: MetricType, base: Double,
                        on days: [Int], value: Double) -> [HealthMetricSample] {
        (1...70).map { offset in
            let date = day(-offset)
            let v = days.contains(-offset) ? value : base
            return HealthMetricSample(type: metric, value: v, start: date, end: date,
                                      source: .appleHealth)
        }
    }

    // MARK: - The confound

    /// ⚠️ **Weekends are excluded from both sides.** Without this, the "quiet"
    /// half is Saturday and Sunday and the card measures the weekend.
    func testWeekendsAreExcludedFromTheComparisonEntirely() {
        // Two months of events on every single day, weekends included.
        let events = (1...56).map { meeting(-$0, hours: 3) }
        let load = WorkImpactModel.workingDayLoad(events: events, judgements: [],
                                                  now: now, calendar: utc)
        for logged in load.keys {
            let weekday = utc.component(.weekday, from: logged)
            XCTAssertFalse(weekday == 1 || weekday == 7,
                           "a weekend day reached the comparison")
        }
        XCTAssertFalse(load.isEmpty)
    }

    /// Only work counts. A dentist appointment is a commitment and it is not
    /// what this card is about.
    func testPersonalEventsDoNotCountTowardWorkLoad() {
        let events = (1...40).map { meeting(-$0, hours: 3, calendarName: "Family") }
        let load = WorkImpactModel.workingDayLoad(events: events, judgements: [],
                                                  now: now, calendar: utc)
        XCTAssertTrue(load.isEmpty, "personal events were counted as work")
    }

    /// A reader's correction changes which bucket an event is in, and therefore
    /// the load — which is the point of storing corrections at all.
    func testAReaderCorrectionChangesTheLoad() {
        let events = (1...40).map { meeting(-$0, hours: 3, calendarName: "Family") }
        let corrected = events.map { event in
            CalendarEventJudgement(
                eventID: event.id,
                classification: CalendarEventClassifier.classify(event),
                correction: CalendarEventClassification(
                    context: .work, occasion: .meeting, presence: .remote,
                    formality: .standard, hours: 3))
        }
        let load = WorkImpactModel.workingDayLoad(events: events, judgements: corrected,
                                                  now: now, calendar: utc)
        XCTAssertFalse(load.isEmpty, "the reader said these were work and it was ignored")
    }

    // MARK: - Travel

    /// **One flight is an anecdote.** A card that turns a single trip into a
    /// finding is what the substance card was refused for.
    func testTravelSaysNothingFromASingleTrip() {
        let single = [CalendarEvent(id: "a", start: day(-30), end: day(-30),
                                    isAllDay: true, timeZoneIdentifier: "Europe/London",
                                    calendarName: "Work", kind: .allDay, title: "Home"),
                      CalendarEvent(id: "b", start: day(-20), end: day(-20),
                                    isAllDay: true, timeZoneIdentifier: "Asia/Singapore",
                                    calendarName: "Work", kind: .allDay, title: "Away")]
        XCTAssertNil(TravelDrainModel.evaluate(
            events: single,
            samples: vitals(.restingHeartRate, base: 58, on: [], value: 58),
            now: now, calendar: utc),
            "one zone change is not evidence")
    }

    // MARK: - The cards themselves

    /// With no calendar at all, both cards must invite the reader rather than
    /// vanishing — the rule that cost two invisible cards on 2026-08-03.
    func testBothCardsInviteInputWhenThereIsNoCalendar() {
        let profile = UserHealthProfile()
        let work = WorkImpactInsight().evaluate(samples: [], profile: profile, now: now)
        let travel = TravelDrainInsight().evaluate(samples: [], profile: profile, now: now)
        for result in [work, travel] {
            XCTAssertTrue(result.invitesInput, "\(result.id) would be filtered off the tab")
            XCTAssertTrue(result.isWorthShowing)
            XCTAssertFalse(result.explanation.isEmpty)
        }
    }

    /// Travel drain's empty state has to explain *why* it needs the calendar,
    /// because "connect your calendar" on a health app is otherwise a non-sequitur.
    func testTravelDrainExplainsWhyItNeedsACalendarAtAll() {
        let result = TravelDrainInsight().evaluate(
            samples: [], profile: UserHealthProfile(), now: now)
        XCTAssertTrue(result.explanation.lowercased().contains("no location"),
                      result.explanation)
    }

    func testTheScoreCurveHasNoCliff() {
        var previous = WorkImpactModel.score(pooled: -2)
        for step in stride(from: -2.0, through: 3.0, by: 0.01) {
            let here = WorkImpactModel.score(pooled: step)
            XCTAssertLessThan(abs(here - previous), 1, "the score jumps at \(step)")
            previous = here
        }
    }
}
