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

    func testTheExposureCurveHasNoCliffEither() {
        var previous = WorkImpactModel.exposureScore(level: 0)
        for step in stride(from: 0.0, through: 5.0, by: 0.01) {
            let here = WorkImpactModel.exposureScore(level: step)
            XCTAssertLessThan(abs(here - previous), 1, "the exposure score jumps at \(step)")
            XCTAssertGreaterThanOrEqual(here, 30,
                                        "a diary alone reached the floor: a calendar is "
                                            + "not a health catastrophe on its own")
            previous = here
        }
    }

    // MARK: - D41: the calendar carries a share

    /// **The reader's overrule, as a test.** *"I want all inputs to carry at
    /// least some weight, thats the entire point. If i have had 10 meetings in a
    /// day, how would that not leave me impacted and drained?"*
    ///
    /// The card's number used to be a curve over the body difference alone, so
    /// two readers whose busy days differed from their quiet ones by twenty
    /// minutes and by five hours could score identically. Hold the body
    /// perfectly still and the calendar must now move the number by itself.
    func testExposureMovesTheScoreWithTheBodyHoldingStill() throws {
        let light = WorkLoadFixture(levels: [3, 4, 5], response: 0)
        let heavy = WorkLoadFixture(levels: [1, 3, 6], response: 0)
        let quiet = try XCTUnwrap(light.evaluate())
        let loaded = try XCTUnwrap(heavy.evaluate())

        // The precondition that makes this test about exposure and nothing
        // else: on both calendars the body said nothing.
        XCTAssertLessThan(abs(quiet.pooled), WorkImpactModel.notableResponse,
                          "the light fixture's body responded, so this proves nothing")
        XCTAssertLessThan(abs(loaded.pooled), WorkImpactModel.notableResponse,
                          "the heavy fixture's body responded, so this proves nothing")

        XCTAssertGreaterThan(loaded.exposureLevel, quiet.exposureLevel)
        XCTAssertLessThan(loaded.score, quiet.score - 5,
                          "the calendar still carries none of the number: "
                              + "\(loaded.score) against \(quiet.score)")
    }

    /// ⚠️ **No calendar row is at weight 0 any more.** That state — every load
    /// quantity declared and none of them counting — is exactly what the reader
    /// objected to.
    func testNoCalendarFactorCarriesZero() throws {
        let fixture = WorkLoadFixture(levels: [1, 3, 6], response: 4)
        let result = fixture.card()
        XCTAssertNotNil(result.score, "the fixture never reached a scored state")

        let derivedRows = (result.weightedFactors + result.unweightedFactors)
            .filter { $0.derivedSeries != nil }
        XCTAssertFalse(derivedRows.isEmpty, "the calendar is declared nowhere again")
        for row in derivedRows {
            XCTAssertGreaterThan(row.weight, 0,
                                 "\"\(row.name)\" is back to charted-not-scored")
        }
        // Both halves of the blend are on screen, and together they are the
        // whole number.
        let weighted = result.weightedFactors
        XCTAssertFalse(weighted.filter { $0.metric != nil }.isEmpty, "the body vanished")
        XCTAssertFalse(weighted.filter { $0.derivedSeries != nil }.isEmpty,
                       "the calendar vanished")
        XCTAssertEqual(weighted.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
    }

    /// **The four quadrants, and the trap.** A heavy fortnight the body absorbed
    /// is not a quiet fortnight, and a large body difference across a flat
    /// calendar is not work impact. Each has to read as itself.
    func testTheFourQuadrantsAreDistinguishable() throws {
        let carrying = try XCTUnwrap(WorkLoadFixture(levels: [1, 3, 6], response: 5).evaluate())
        let absorbing = try XCTUnwrap(WorkLoadFixture(levels: [1, 3, 6], response: 0).evaluate())
        let unexplained = try XCTUnwrap(WorkLoadFixture(levels: [8, 9, 10], response: 5).evaluate())
        let quiet = try XCTUnwrap(WorkLoadFixture(levels: [8, 9, 10], response: 0).evaluate())

        XCTAssertEqual(carrying.quadrant, .carrying)
        XCTAssertEqual(absorbing.quadrant, .absorbing)
        XCTAssertEqual(unexplained.quadrant, .unexplained)
        XCTAssertEqual(quiet.quadrant, .quiet)

        let headlines = [carrying, absorbing, unexplained, quiet]
            .map(WorkImpactModel.headline)
        XCTAssertEqual(Set(headlines).count, 4,
                       "two quadrants share a headline, so one of them is lying: \(headlines)")
        let lines = [carrying, absorbing, unexplained, quiet]
            .map(WorkImpactModel.quadrantLine)
        XCTAssertEqual(Set(lines).count, 4, "\(lines)")

        // The ordering the design turns on.
        XCTAssertLessThan(carrying.score, absorbing.score,
                          "a heavy stretch the body showed must score below one it absorbed")
        XCTAssertLessThan(absorbing.score, quiet.score,
                          "carrying a heavy load well must not score identically to an "
                              + "empty diary — the hours were still yours")
        XCTAssertLessThan(carrying.score, unexplained.score,
                          "the same body difference across a flat calendar is not work "
                              + "impact and must not be scored as though it were")
    }

    /// The other half of the same rule, stated on the shares rather than the
    /// number: a body difference measured across two groups of days that barely
    /// differ is discounted, and one measured across a real gap is not.
    func testAThinContrastDiscountsTheBodyAndSaysSo() throws {
        let wide = try XCTUnwrap(WorkLoadFixture(levels: [1, 3, 6], response: 5).evaluate())
        let narrow = try XCTUnwrap(WorkLoadFixture(levels: [8, 9, 10], response: 5).evaluate())

        XCTAssertGreaterThan(wide.responseShare, narrow.responseShare)
        XCTAssertEqual(wide.responseShare, WorkImpactModel.responseShareAtFullContrast,
                       accuracy: 1e-9)
        XCTAssertGreaterThan(narrow.responseShare, 0,
                             "a thin comparison discounts the body, it never silences it")

        // …and the card says which it is rather than leaving it to the dial.
        let text = WorkImpactModel.quadrantLine(narrow).lowercased()
        XCTAssertTrue(text.contains("calendar"), text)
    }

    /// **The version moves whenever the arithmetic does** — the `fitness-v2`
    /// precedent, and the one failure this field exists to prevent.
    ///
    /// `work-impact-v3` and `travel-drain-v2` are B7 H6: both cards now fold in
    /// time since the reader's last recorded leave, so a score from before today
    /// is not comparable with one from after.
    ///
    /// ⚠️ Travel drain moving does **not** reopen its refusal to score its trip
    /// *count* — that stands, for the three reasons at `TravelDrainModel`'s own
    /// note. A date is not a count.
    func testTheWorkImpactModelVersionMoved() {
        XCTAssertEqual(InsightID.workImpact.modelVersion, "work-impact-v3")
        XCTAssertEqual(InsightID.travelDrain.modelVersion, "travel-drain-v2")
        // The other two cards H6 wired, pinned in the same place so a future
        // change to the leave share cannot move one version and forget three.
        XCTAssertEqual(InsightID.sustainedLoad.modelVersion, "sustained-load-v2")
        XCTAssertEqual(InsightID.mentalHealth.modelVersion, "mental-health-v2")
    }

    // MARK: - Fixture

    /// Eight weeks of working days at three levels of load, with a controllable
    /// body response on the nights after the heaviest ones.
    ///
    /// ⚠️ **Three levels, not two, and the reason is the model's own split.**
    /// `WorkImpactModel` divides at the reader's median with `> median` on the
    /// heavy side, so a fixture with exactly two levels puts the median *on* the
    /// high value and leaves the heavy half empty — the card returns nil and
    /// every assertion fails for a reason that has nothing to do with what is
    /// being tested.
    ///
    /// Built on `Calendar.current` deliberately: `WorkImpactInsight.evaluate`
    /// takes the default calendar, so a fixture built in UTC would put events
    /// and readings on different days for any reader east or west of it.
    struct WorkLoadFixture {
        let now = TestClock.now
        let calendar = Calendar.current
        private(set) var events: [CalendarEvent] = []
        private(set) var samples: [HealthMetricSample] = []

        /// - Parameters:
        ///   - levels: meetings per working day, cycled. Each is one standard
        ///     remote hour — the title is deliberately neither a `formalWord`
        ///     nor a `casualWord`, so `loadHours` is the hour count exactly and
        ///     the arithmetic under test is not the classifier's.
        ///   - response: how many raw units worse the body runs on the night
        ///     after a top-level day. **0 is a body that did not notice**, which
        ///     is half the quadrants.
        init(levels: [Int], response: Double) {
            var index = 0
            var busyOffsets: Set<Int> = []
            let heaviest = levels.max() ?? 0
            for offset in 1...WorkImpactModel.windowDays {
                guard let day = calendar.date(byAdding: .day, value: -offset,
                                              to: calendar.startOfDay(for: now))
                else { continue }
                let weekday = calendar.component(.weekday, from: day)
                guard weekday != 1, weekday != 7 else { continue }

                let count = levels[index % levels.count]
                index += 1
                if count == heaviest { busyOffsets.insert(offset) }
                for slot in 0..<count {
                    let start = day.addingTimeInterval(Double(7 + slot) * 3600)
                    events.append(CalendarEvent(
                        id: "w-\(offset)-\(slot)", start: start,
                        end: start.addingTimeInterval(3600),
                        isAllDay: false, timeZoneIdentifier: "Europe/London",
                        calendarName: "Work", kind: .timed,
                        title: "Team planning", location: nil, hasVideoLink: true))
                }
            }

            // Readings on every day of the window, including the mornings after
            // — the model reads the night *after* the day it is judging.
            for offset in 0...(WorkImpactModel.windowDays + 4) {
                guard let day = calendar.date(byAdding: .day, value: -offset,
                                              to: calendar.startOfDay(for: now))
                else { continue }
                // The day this reading is judging is the one before it.
                let busy = busyOffsets.contains(offset + 1)
                // Deterministic spread, so `Baseline.robustScale` has something
                // to divide by. A constant series is refused by the model, and
                // correctly.
                let jitter = Double(offset % 3) * 0.4
                let noon = day.addingTimeInterval(12 * 3600)
                samples.append(.init(type: .restingHeartRate,
                                     value: 56 + (busy ? response : 0) + jitter,
                                     start: noon, end: noon, source: .appleHealth))
                samples.append(.init(type: .heartRateVariabilityRMSSD,
                                     value: 46 - (busy ? response * 1.6 : 0) + jitter,
                                     start: noon, end: noon, source: .appleHealth))
                samples.append(.init(type: .sleepDurationHours,
                                     value: 7.4 - (busy ? response * 0.2 : 0) + jitter * 0.1,
                                     start: noon, end: noon, source: .appleHealth))
            }
        }

        func evaluate() -> WorkImpactModel.Output? {
            WorkImpactModel.evaluate(events: events, judgements: [], samples: samples,
                                     now: now, calendar: calendar)
        }

        func card() -> InsightResult {
            WorkImpactInsight(events: events, judgements: [])
                .evaluate(samples: samples, profile: UserHealthProfile(), now: now)
        }
    }
}
