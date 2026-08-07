import XCTest
@testable import InsightKit

/// **The leave recommendation and the window it names** — backlog B7 H7.
///
/// ⚠️ Every title here is invented; no real calendar appears in fixtures.
final class LeaveSuggestionTests: XCTestCase {

    private let utc = TestClock.utc
    /// A Tuesday, so the Friday/Monday arithmetic below is not resting on the
    /// anchor happening to fall somewhere convenient.
    private let now = TestClock.now

    private func day(_ n: Int) -> Date {
        utc.startOfDay(for: now.addingTimeInterval(-Double(n) * 86_400))
    }

    private func ledger(lastLeaveDaysAgo: Int?, booked: Int? = nil) -> HolidayLedger {
        var periods: [HolidayLedger.Period] = []
        if let lastLeaveDaysAgo {
            periods.append(HolidayLedger.Period(
                firstDay: day(lastLeaveDaysAgo + 4), lastDay: day(lastLeaveDaysAgo),
                source: .entered))
        }
        if let booked {
            periods.append(HolidayLedger.Period(
                firstDay: day(-booked), lastDay: day(-booked - 3), source: .entered))
        }
        return HolidayLedger(entered: periods, calendar: utc)
    }

    /// A card result with a chosen score, for the health half of the gate.
    private func result(_ id: InsightID, score: Double?) -> InsightResult {
        InsightResult(id: id, title: id == .sustainedLoad ? "Stress load" : "Mental health",
                      primaryValue: score, headline: "", score: score,
                      confidence: .moderate, explanation: "", driverLines: [],
                      unmetRequirements: [])
    }

    private var stressed: [InsightResult] {
        [result(.sustainedLoad, score: 42), result(.mentalHealth, score: 71)]
    }

    private func suggestion(_ input: LeaveSuggestionInput?,
                            results: [InsightResult]) -> Suggestion? {
        SuggestionEngine.leaveWindow(input, results: results, now: now,
                                     calendar: utc).first
    }

    // MARK: - The three conditions, each refused on its own

    func testItFiresWhenABreakIsLongPastAndACardIsBelowItsRange() throws {
        let out = try XCTUnwrap(suggestion(
            LeaveSuggestionInput(ledger: ledger(lastLeaveDaysAgo: 200)),
            results: stressed))
        XCTAssertEqual(out.id, "leave-window")
        XCTAssertEqual(out.basis, .signalOffBaseline,
                       "H7's own rule: below every grounding gap")
        XCTAssertEqual(out.insight, .sustainedLoad, "it points at the lowest card")
        XCTAssertTrue(out.detail.contains("stress load"), out.detail)
    }

    /// ⚠️ **Never on silence.** No recorded leave means the app was not told,
    /// not that none was taken — the guard `LeaveRecency` is built around, and
    /// the one failure that would look entirely reasonable on screen.
    func testItNeverFiresWhenNoLeaveIsRecordedAtAll() {
        XCTAssertNil(suggestion(LeaveSuggestionInput(ledger: HolidayLedger()),
                                results: stressed))
    }

    /// A recent break is not a finding.
    func testItStaysQuietWhenLeaveWasRecent() {
        XCTAssertNil(suggestion(
            LeaveSuggestionInput(ledger: ledger(lastLeaveDaysAgo: 20)),
            results: stressed))
    }

    /// **Never at somebody who has already acted.** Telling a reader with a
    /// holiday booked next month to take one is the nag this app's whole
    /// ranking exists to avoid.
    func testItStaysQuietWhenLeaveIsAlreadyBooked() {
        XCTAssertNil(suggestion(
            LeaveSuggestionInput(ledger: ledger(lastLeaveDaysAgo: 200, booked: 20)),
            results: stressed))
        // …and a booking beyond the horizon does not silence it, or a holiday
        // pencilled in for next year would buy permanent quiet.
        XCTAssertNotNil(suggestion(
            LeaveSuggestionInput(ledger: ledger(lastLeaveDaysAgo: 200, booked: 300)),
            results: stressed))
    }

    /// The health half is required. A long stretch without leave, on somebody
    /// whose cards are fine, is not something this app has standing to raise.
    func testItStaysQuietWhenNothingIsBelowItsRange() {
        XCTAssertNil(suggestion(
            LeaveSuggestionInput(ledger: ledger(lastLeaveDaysAgo: 200)),
            results: [result(.sustainedLoad, score: 88),
                      result(.mentalHealth, score: 79)]))
        // An unscored card is not a low one — `score` of nil must not read as 0.
        XCTAssertNil(suggestion(
            LeaveSuggestionInput(ledger: ledger(lastLeaveDaysAgo: 200)),
            results: [result(.sustainedLoad, score: nil)]))
    }

    // MARK: - It is not medical advice

    /// The line H7 names explicitly. This is a scheduling observation about a
    /// diary and it must read as one — no instruction, and no claim about what
    /// time off does to anybody.
    func testTheCopyMakesNoHealthClaimAndGivesNoInstruction() throws {
        let out = try XCTUnwrap(suggestion(
            LeaveSuggestionInput(ledger: ledger(lastLeaveDaysAgo: 200)),
            results: stressed))
        let text = (out.title + " " + out.detail).lowercased()
        XCTAssertTrue(text.contains("not advice about your health"), text)
        for banned in ["you need", "you should", "will help", "will improve",
                       "rest will", "doctor", "treat"] {
            XCTAssertFalse(text.contains(banned),
                           "\"\(banned)\" turns a scheduling note into advice: \(text)")
        }
    }

    /// It never outranks a real measurement inside its own basis. `departures`
    /// scores |z|/4, so two standard deviations sits at 0.5 — above this by
    /// construction.
    func testItCannotLeadAGroupWhoseSubjectIsMeasurements() throws {
        let out = try XCTUnwrap(suggestion(
            LeaveSuggestionInput(ledger: ledger(lastLeaveDaysAgo: 900)),
            results: stressed))
        XCTAssertLessThan(out.strength, 0.5)
    }

    // MARK: - The window

    /// A day off adjacent to a weekend, chosen from the reader's own diary —
    /// the half of H7 nothing else in this app does.
    func testItNamesTheQuietestWorkingDayNextToAWeekend() throws {
        // Every candidate day in the horizon carries work except one Friday.
        var events: [CalendarEvent] = []
        var quiet: Date?
        for offset in LeaveWindowFinder.leadTimeDays...LeaveWindowFinder.horizonDays {
            let start = day(-offset).addingTimeInterval(9 * 3600)
            let weekday = utc.component(.weekday, from: start)
            guard weekday == 6 || weekday == 2 else { continue }
            if weekday == 6, quiet == nil, offset > 25 {
                quiet = utc.startOfDay(for: start)
                continue
            }
            events.append(CalendarEvent(
                id: "busy-\(offset)", start: start,
                end: start.addingTimeInterval(4 * 3600), isAllDay: false,
                timeZoneIdentifier: "UTC", calendarName: "Work", kind: .timed,
                title: "Project sync", location: nil, hasVideoLink: true))
        }
        let window = try XCTUnwrap(LeaveWindowFinder.best(
            events: events, judgements: [], ledger: ledger(lastLeaveDaysAgo: 200),
            now: now, calendar: utc))
        XCTAssertEqual(utc.component(.weekday, from: window.workingDay), 6,
                       "a long weekend starts on a Friday or ends on a Monday")
        XCTAssertEqual(window.workingDay, quiet,
                       "the one empty day in the horizon was not the one chosen")
        XCTAssertEqual(window.loadHours, 0, accuracy: 1e-9,
                       "the quietest day in the horizon was not chosen")
        XCTAssertFalse(window.hasMarathonDay)
    }

    /// **A marathon day disqualifies a window however light the rest is** —
    /// H7's own wording, and the one filter that is a veto rather than a score.
    func testAMarathonDayIsNeverSuggested() {
        var events: [CalendarEvent] = []
        for offset in LeaveWindowFinder.leadTimeDays...LeaveWindowFinder.horizonDays {
            let start = day(-offset).addingTimeInterval(9 * 3600)
            let weekday = utc.component(.weekday, from: start)
            guard weekday == 6 || weekday == 2 else { continue }
            events.append(CalendarEvent(
                id: "long-\(offset)", start: start,
                end: start.addingTimeInterval(
                    Double(CalendarEventClassifier.marathonHours + 1) * 3600),
                isAllDay: false, timeZoneIdentifier: "UTC",
                calendarName: "Work", kind: .timed,
                title: "Planning workshop", location: "Room 3", hasVideoLink: false))
        }
        XCTAssertNil(LeaveWindowFinder.best(events: events, judgements: [],
                                            ledger: ledger(lastLeaveDaysAgo: 200),
                                            now: now, calendar: utc),
                     "every candidate is a marathon day and none should be offered")
    }

    /// A day already booked as leave is never suggested as leave.
    func testADayAlreadyOffIsNeverOffered() {
        let windows = LeaveWindowFinder.windows(
            events: [], judgements: [],
            ledger: HolidayLedger(entered: [HolidayLedger.Period(
                firstDay: day(-LeaveWindowFinder.leadTimeDays),
                lastDay: day(-LeaveWindowFinder.horizonDays), source: .entered)],
                                  calendar: utc),
            now: now, calendar: utc)
        XCTAssertTrue(windows.isEmpty,
                      "the whole horizon is already booked and nothing should be offered")
    }

    /// **Extending a break already booked beats everything**: one day off joins
    /// two, which is the cheapest suggestion a calendar can make.
    func testAWindowTouchingBookedLeaveWins() throws {
        // Book the Monday after some Friday well inside the horizon, then check
        // the chosen window touches it.
        var booked: [HolidayLedger.Period] = []
        // From day 20 rather than the lead time: the Monday whose window would
        // touch a Tuesday booked on day 7 falls *inside* the lead time and is
        // never offered, which would make this test pass or fail on the anchor.
        for offset in 20...70 {
            let candidate = day(-offset)
            guard utc.component(.weekday, from: candidate) == 3 else { continue }
            booked = [HolidayLedger.Period(firstDay: candidate, lastDay: candidate,
                                           source: .entered)]
            break
        }
        let window = try XCTUnwrap(LeaveWindowFinder.best(
            events: [], judgements: [],
            ledger: HolidayLedger(entered: booked, calendar: utc),
            now: now, calendar: utc))
        XCTAssertTrue(window.extendsBookedLeave,
                      "an empty diary makes every window equally quiet, so the "
                          + "tie-break on touching booked leave is what decides")
    }

    /// Nothing inside the lead time: a quiet Friday the day after tomorrow is
    /// not something anybody can act on.
    func testNothingInsideTheLeadTimeIsOffered() {
        let windows = LeaveWindowFinder.windows(events: [], judgements: [],
                                                ledger: HolidayLedger(),
                                                now: now, calendar: utc)
        for window in windows {
            XCTAssertGreaterThanOrEqual(
                window.workingDay,
                utc.date(byAdding: .day, value: LeaveWindowFinder.leadTimeDays,
                         to: utc.startOfDay(for: now))!)
        }
    }

    // MARK: - Wiring

    /// It reaches the list, and it ranks below every grounding gap there.
    func testItReachesTheSuggestionListBelowTheGroundingGaps() {
        let out = SuggestionEngine.suggestions(
            results: stressed, samples: [], profile: UserHealthProfile(),
            usedInputs: Set(InputKind.allCases),
            leave: LeaveSuggestionInput(ledger: ledger(lastLeaveDaysAgo: 200)),
            now: now, calendar: utc)
        guard let index = out.firstIndex(where: { $0.id == "leave-window" }) else {
            return XCTFail("the leave row never reached the list: \(out.map(\.id))")
        }
        for gap in out.prefix(index) {
            XCTAssertLessThanOrEqual(gap.basis, Suggestion.Basis.signalOffBaseline)
        }
        XCTAssertTrue(out.filter { $0.basis == .unlockAnInsight }
            .allSatisfy { out.firstIndex(of: $0)! < index },
                      "a grounding gap ended up below the leave row")
    }

    /// Nil input emits nothing — every caller with no calendar.
    func testNoInputEmitsNothing() {
        XCTAssertTrue(SuggestionEngine.leaveWindow(nil, results: stressed,
                                                   now: now, calendar: utc).isEmpty)
    }
}
