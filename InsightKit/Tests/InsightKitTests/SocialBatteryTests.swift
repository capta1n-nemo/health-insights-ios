import XCTest
@testable import InsightKit

/// **Social battery** — backlog B9-1.
///
/// ⚠️ **The first three tests are the ones that matter**, because they are the
/// three ways this card could have shipped as Work impact with the word
/// "people" substituted:
///
/// 1. personal contact and weekends stay *in* the data;
/// 2. the weekend confound is handled by splitting inside each block rather than
///    by throwing the weekend away;
/// 3. whether more company counts for or against the reader is **read off their
///    own nights**, not assumed.
///
/// The fourth thing this file holds is the refusals: a verdict whose interval
/// spans zero says *"we cannot tell yet"*, and the card prints no battery
/// percentage at all.
final class SocialBatteryTests: XCTestCase {

    private let now = TestClock.now

    // MARK: - Fixture

    /// A calendar of the shape this card is built for: work meetings on
    /// weekdays, personal contact at weekends, and a body that responds — or
    /// doesn't — on the nights after the busier days.
    ///
    /// `Calendar.current` rather than UTC, deliberately and for
    /// `WorkLoadFixture`'s reason: the model buckets with the calendar it is
    /// handed and `VitalReader` is handed the same one, so fixture and bucketing
    /// stay coupled by construction.
    struct SocialFixture {
        let now = TestClock.now
        let calendar = Calendar.current
        private(set) var events: [CalendarEvent] = []
        private(set) var samples: [HealthMetricSample] = []
        /// Day offsets that carry the heavier half of their own stratum.
        private(set) var heavyOffsets: Set<Int> = []

        /// - Parameters:
        ///   - response: raw units the body runs **worse** on the night after a
        ///     heavier day. Negative means the body reads *better* — a reader
        ///     company restores. Zero is a body that did not notice.
        ///   - attendees: how many people the calendar states per meeting. `nil`
        ///     is the ordinary shape of an event somebody put in their own
        ///     calendar, and it must not be read as zero.
        ///   - weekendContact: whether the weekends carry personal contact at
        ///     all. Off, the weekend stratum has no contrast and is dropped.
        init(response: Double, attendees: Int? = 6, weekendContact: Bool = true) {
            var weekdayIndex = 0
            var weekendIndex = 0
            for offset in 1...SocialBatteryModel.windowDays {
                guard let day = calendar.date(byAdding: .day, value: -offset,
                                              to: calendar.startOfDay(for: now))
                else { continue }
                let weekday = calendar.component(.weekday, from: day)
                let isWeekend = weekday == 1 || weekday == 7

                if isWeekend {
                    defer { weekendIndex += 1 }
                    guard weekendContact, weekendIndex.isMultiple(of: 2) else { continue }
                    heavyOffsets.insert(offset)
                    // Personal contact: a long lunch with friends.
                    add(day: day, offset: offset, hours: 3, calendarName: "Family",
                        title: "Lunch with friends", attendees: attendees.map { $0 / 2 })
                } else {
                    defer { weekdayIndex += 1 }
                    let heavy = weekdayIndex.isMultiple(of: 2)
                    if heavy { heavyOffsets.insert(offset) }
                    add(day: day, offset: offset, hours: heavy ? 4 : 1,
                        calendarName: "Work", title: "Team planning",
                        attendees: attendees)
                }
            }

            // Readings on every day of the window, **including the mornings
            // after** — the model reads the night after the day it is judging.
            for offset in 0...(SocialBatteryModel.windowDays + 4) {
                guard let day = calendar.date(byAdding: .day, value: -offset,
                                              to: calendar.startOfDay(for: now))
                else { continue }
                // The day this reading judges is the one before it.
                let busy = heavyOffsets.contains(offset + 1)
                // Deterministic spread uncorrelated with the split, so
                // `Baseline.robustScale` has something to divide by. A constant
                // series is refused by the model, and correctly.
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

        private mutating func add(day: Date, offset: Int, hours: Double,
                                  calendarName: String, title: String,
                                  attendees: Int?) {
            let start = day.addingTimeInterval(12 * 3600)
            events.append(CalendarEvent(
                id: "s-\(offset)", start: start,
                end: start.addingTimeInterval(hours * 3600),
                isAllDay: false, timeZoneIdentifier: "Europe/London",
                calendarName: calendarName, kind: .timed, title: title,
                location: nil, hasVideoLink: true, organizerIsReader: nil,
                attendeeCount: attendees))
        }

        func analyse() -> SocialBatteryModel.Readiness {
            SocialBatteryModel.analyse(events: events, judgements: [], samples: samples,
                                       now: now, calendar: calendar)
        }

        func output() -> SocialBatteryModel.Output? {
            SocialBatteryModel.evaluate(events: events, judgements: [], samples: samples,
                                        now: now, calendar: calendar)
        }

        func card() -> InsightResult {
            SocialBatteryInsight(events: events, judgements: [])
                .evaluate(samples: samples, profile: UserHealthProfile(), now: now)
        }
    }

    private func readyOutput(response: Double = 4, attendees: Int? = 6,
                             weekendContact: Bool = true,
                             file: StaticString = #filePath,
                             line: UInt = #line) throws -> SocialBatteryModel.Output {
        let fixture = SocialFixture(response: response, attendees: attendees,
                                    weekendContact: weekendContact)
        switch fixture.analyse() {
        case .ready(let out):
            return out
        case .waiting(let gate):
            XCTFail("the fixture never reached a scored state: \(gate.sentence ?? "met")",
                    file: file, line: line)
            throw XCTSkip("not ready")
        case .noCalendar:
            XCTFail("the fixture handed over no calendar", file: file, line: line)
            throw XCTSkip("no calendar")
        }
    }

    // MARK: - 1. Personal contact and weekends are IN

    /// ⚠️ **The difference from Work impact, as a test.** That card drops every
    /// personal event and every weekend on purpose. Dinner with friends is the
    /// exact contact this card exists to measure, and a Saturday is where most
    /// of it lives — so both must survive.
    func testPersonalContactAndWeekendsReachTheComparison() {
        let fixture = SocialFixture(response: 4)
        let days = SocialBatteryModel.contactDays(events: fixture.events, judgements: [],
                                                  now: now, calendar: fixture.calendar)
        let weekends = days.filter { $0.stratum == .weekend }
        XCTAssertFalse(weekends.isEmpty, "the weekend was excluded, as the work card does")
        XCTAssertTrue(weekends.contains { $0.hours > 0 },
                      "weekend days reached the comparison but carried no contact")
        XCTAssertTrue(days.contains { $0.chosenHours > 0 },
                      "personal contact was dropped, so this is the work card again")

        // And the same calendar read by the work card sees none of it.
        let work = WorkImpactModel.workingDayLoad(events: fixture.events, judgements: [],
                                                  now: now, calendar: fixture.calendar)
        for logged in work.keys {
            let weekday = fixture.calendar.component(.weekday, from: logged)
            XCTAssertFalse(weekday == 1 || weekday == 7)
        }
    }

    /// A day the reader saw nobody is a **zero**, not a gap. It is the quiet
    /// side of the whole comparison, and building days only where events exist —
    /// which is what `workingDayProfile` does — would throw the most restful
    /// days away.
    func testADayWithNoContactIsAZeroRatherThanAbsent() {
        let fixture = SocialFixture(response: 4)
        let days = SocialBatteryModel.contactDays(events: fixture.events, judgements: [],
                                                  now: now, calendar: fixture.calendar)
        XCTAssertTrue(days.contains { $0.hours == 0 },
                      "no zero-contact day survived, so nothing quiet is being compared")
        // Consecutive, with no holes: a gap in this list is a day the model
        // cannot see.
        let sorted = days.map(\.day).sorted()
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            XCTAssertEqual(fixture.calendar.dateComponents([.day], from: earlier, to: later).day,
                           1, "the day list has a hole in it")
        }
    }

    /// The window never starts before the calendar does. Counting an unsynced
    /// day as solitude is a confident wrong answer.
    func testTheWindowStartsAtTheFirstEventRatherThanAtTheCutoff() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now).addingTimeInterval(-10 * 86_400 + 12 * 3600)
        let events = [CalendarEvent(id: "only", start: start,
                                    end: start.addingTimeInterval(3600),
                                    isAllDay: false, timeZoneIdentifier: nil,
                                    calendarName: "Work", kind: .timed,
                                    title: "Catch-up", location: nil, hasVideoLink: true)]
        let days = SocialBatteryModel.contactDays(events: events, judgements: [],
                                                  now: now, calendar: calendar)
        XCTAssertEqual(days.count, 10,
                       "the model invented days the calendar has never covered")
    }

    // MARK: - 2. The confound is handled by blocking, not exclusion

    /// **The split is made inside each stratum.** A pooled split would put every
    /// weekend on the quiet side and the card would be measuring Saturday.
    func testTheSplitIsMadeInsideEachStratumSoNeitherHalfIsAllWeekend() throws {
        let out = try readyOutput()
        XCTAssertEqual(Set(out.strata), Set(SocialBatteryModel.Stratum.allCases),
                       "a stratum was dropped on a fixture built to give both contrast")
        XCTAssertTrue(out.droppedStrata.isEmpty)

        let fixture = SocialFixture(response: 4)
        let days = SocialBatteryModel.contactDays(events: fixture.events, judgements: [],
                                                  now: now, calendar: fixture.calendar)
        let split = SocialBatteryModel.stratifiedSplit(
            days, by: { $0.hours },
            minimumPerStratum: SocialBatteryModel.minimumDaysPerStratum)
        for half in [split.high, split.low] {
            XCTAssertTrue(half.contains { $0.stratum == .weekday })
            XCTAssertTrue(half.contains { $0.stratum == .weekend },
                          "one half of the split holds no weekend, so the comparison "
                              + "is weekday-versus-weekend after all")
        }
    }

    /// A stratum with no contrast is **dropped whole and named**, never folded
    /// into the other — folding is precisely the confound.
    func testAStratumWithNoContrastIsDroppedRatherThanFoldedIn() throws {
        let out = try readyOutput(weekendContact: false)
        XCTAssertEqual(out.strata, [.weekday])
        XCTAssertEqual(out.droppedStrata, [.weekend])
        // Nothing from the dropped block reached either half.
        XCTAssertGreaterThanOrEqual(out.heavyDays, SocialBatteryModel.minimumDaysPerHalf)
    }

    // MARK: - 3. The direction is learnt, never assumed

    /// **The novel part of this card.** For a reader whose body reads *better*
    /// after busy days, a full diary must not be scored as their worst
    /// fortnight — that would be the app asserting a personality it never
    /// measured.
    func testAFullDiaryScoresBetterForAReaderCompanyRestores() throws {
        let drained = try readyOutput(response: 4)
        let restored = try readyOutput(response: -4)

        XCTAssertLessThan(drained.restorationIndex, 0)
        XCTAssertGreaterThan(restored.restorationIndex, 0)
        XCTAssertGreaterThan(restored.score, drained.score + 10,
                             "the same calendar scored the same for two opposite bodies")

        // And the exposure rows themselves flipped, not just the body rows.
        func exposure(_ out: SocialBatteryModel.Output) -> Double {
            SocialBatteryModel.exposureScore(level: out.exposureLevel,
                                             restorationIndex: out.restorationIndex)
        }
        XCTAssertGreaterThan(exposure(restored), exposure(drained))
    }

    /// With the body saying nothing either way, the index sits near the middle
    /// and the exposure curve sits between its two ends — a demand nobody has
    /// graded is still a demand, and it is not weightless.
    func testAnUngradedDemandStillCountsMildlyAgainst() throws {
        let out = try readyOutput(response: 0)
        XCTAssertLessThan(abs(out.restorationIndex), 0.5,
                          "the model called a direction on a body that said nothing")
        let neutral = SocialBatteryModel.exposureScore(level: 1.5, restorationIndex: 0)
        XCTAssertLessThan(neutral, SocialBatteryModel.restoringExposureScore(level: 1.5))
        XCTAssertGreaterThan(neutral, SocialBatteryModel.costlyExposureScore(level: 1.5))
    }

    // MARK: - The refusals

    /// **"We cannot tell yet" is a real answer**, and it is the honest one at
    /// low n. A body that did not respond must not produce a verdict.
    func testAResponseWhoseIntervalSpansZeroRefusesToNameADirection() throws {
        let out = try readyOutput(response: 0)
        XCTAssertFalse(out.overall.isDistinguishableFromZero,
                       "a body that did nothing was called")
        XCTAssertTrue(SocialBatteryModel.restorationPhrase(out)
                        .localizedCaseInsensitiveContains("too close to call"),
                      SocialBatteryModel.restorationPhrase(out))
        for finding in out.findings where finding.response != nil {
            XCTAssertEqual(finding.verdict, .tooCloseToTell,
                           "\(finding.kind) was called on a body that said nothing")
            XCTAssertTrue(SocialBatteryModel.kindSentence(finding)
                            .localizedCaseInsensitiveContains("cannot tell yet"))
        }
    }

    /// And with a real response it does name one, in both directions.
    func testAResponseClearOfZeroIsNamedInBothDirections() throws {
        let drained = try readyOutput(response: 4)
        let restored = try readyOutput(response: -4)
        XCTAssertTrue(drained.overall.isDistinguishableFromZero)
        XCTAssertTrue(restored.overall.isDistinguishableFromZero)
        XCTAssertEqual(drained.finding(.obligated)?.verdict, .drains)
        XCTAssertEqual(restored.finding(.obligated)?.verdict, .restores)
    }

    /// ⚠️ **No battery percentage, ever.** The reader asked for capacity
    /// remaining today; Energy's reservoir constants were chosen in this repo
    /// rather than measured (the open B19 problem), and borrowing them would
    /// have produced the most reassuring figure on the card and the least true.
    func testTheCardPrintsNoBatteryPercentageAndSaysWhy() throws {
        let card = SocialFixture(response: 4).card()
        XCTAssertNotNil(card.score)
        XCTAssertTrue(card.drivers.contains(SocialBatteryModel.capacityRefusal),
                      "the refusal is not on the card, so the absence reads as an omission")
        XCTAssertTrue(SocialBatteryModel.capacityRefusal
                        .localizedCaseInsensitiveContains("no percentage here"))
        for driver in card.drivers {
            XCTAssertFalse(driver.localizedCaseInsensitiveContains("battery level"), driver)
            XCTAssertFalse(driver.localizedCaseInsensitiveContains("% charged"), driver)
        }
    }

    /// The waiting branch never tells a reader to connect a calendar they have
    /// already connected — the defect found on the travel card, 2026-08-07.
    func testWaitingNeverAsksForACalendarThatIsAlreadyConnected() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now).addingTimeInterval(-3 * 86_400 + 12 * 3600)
        let events = [CalendarEvent(id: "a", start: start,
                                    end: start.addingTimeInterval(3600),
                                    isAllDay: false, timeZoneIdentifier: nil,
                                    calendarName: "Work", kind: .timed,
                                    title: "Catch-up", location: nil, hasVideoLink: true)]
        let card = SocialBatteryInsight(events: events, judgements: [])
            .evaluate(samples: [], profile: UserHealthProfile(), now: now)
        XCTAssertNil(card.score)
        XCTAssertFalse(card.headline.localizedCaseInsensitiveContains("connect"),
                       card.headline)
        XCTAssertFalse(card.explanation.localizedCaseInsensitiveContains("connect your calendar"),
                       card.explanation)
        XCTAssertFalse(card.invitesInput)
        // ⚠️ Deliberately **not** asserting `isWorthShowing` here. `waitingOn`
        // produces a result with no number, no unmet requirement and
        // `invitesInput: false`, which `InsightResult.isWorthShowing` filters
        // off the tab — so all three calendar cards vanish while they are
        // counting rather than saying what they are counting. That is a
        // pre-existing defect in shared code (`InsightPhrasing.waitingOn`),
        // reported rather than patched here because three cards and
        // `CardVisibilityTests` move together and eleven agents are in this tree.
    }

    /// With no calendar at all it *does* invite, and stays on the tab to do it —
    /// the rule that cost two invisible cards on 2026-08-03.
    func testWithNoCalendarTheCardInvitesRatherThanVanishing() {
        let card = SocialBatteryInsight().evaluate(samples: [], profile: UserHealthProfile(),
                                                   now: now)
        XCTAssertTrue(card.invitesInput)
        XCTAssertTrue(card.isWorthShowing)
        XCTAssertFalse(card.explanation.isEmpty)
    }

    // MARK: - What counts as contact

    /// An all-day banner is not twenty-four hours of company, a reminder is not
    /// company at all, and neither is a sick day or somebody's leave.
    func testOnlyRealMeetingsCountAsContact() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now).addingTimeInterval(-2 * 86_400)
        let banner = CalendarEvent(id: "all", start: day, end: day.addingTimeInterval(86_400),
                                   isAllDay: true, timeZoneIdentifier: nil,
                                   calendarName: "Work", kind: .allDay,
                                   title: "Conference", location: nil)
        let reminder = CalendarEvent(id: "rem", start: day.addingTimeInterval(9 * 3600),
                                     end: day.addingTimeInterval(9 * 3600),
                                     isAllDay: false, timeZoneIdentifier: nil,
                                     calendarName: "Personal", kind: .timed,
                                     title: "Bin day", location: nil)
        let days = SocialBatteryModel.contactDays(events: [banner, reminder], judgements: [],
                                                  now: now, calendar: calendar)
        XCTAssertTrue(days.allSatisfy { $0.hours == 0 && $0.meetings == 0 },
                      "an all-day banner or a reminder was counted as company")
    }

    /// A meeting with no stated guest list is **unknown**, never zero people.
    func testAnUnstatedGuestListIsNotZeroPeople() throws {
        let known = try readyOutput(attendees: 6)
        let unknown = try readyOutput(attendees: nil)
        XCTAssertEqual(known.peopleCoverage, 1, accuracy: 1e-9)
        XCTAssertEqual(unknown.peopleCoverage, 0, accuracy: 1e-9)
        XCTAssertEqual(unknown.typicalDayPeople, 0, accuracy: 1e-9)
        // …and the row that cannot be filled in says so rather than scoring a 0.
        let row = try XCTUnwrap(unknown.factors.first {
            $0.derivedSeries == DerivedSeriesID(.socialBattery, SocialBatteryModel.peopleGapKey)
        })
        XCTAssertEqual(row.weight, 0, accuracy: 1e-9)
        XCTAssertTrue(row.detail.contains(" — "),
                      "an unweighted row with no reason: \"\(row.detail)\"")
    }

    /// A reader's correction changes which kind of contact an event is, and
    /// therefore what the card finds — which is the point of storing corrections.
    func testAReaderCorrectionMovesContactBetweenChosenAndOwed() {
        let fixture = SocialFixture(response: 4)
        let plain = SocialBatteryModel.contactDays(events: fixture.events, judgements: [],
                                                   now: now, calendar: fixture.calendar)
        let corrections = fixture.events.map { event in
            CalendarEventJudgement(
                eventID: event.id,
                classification: CalendarEventClassifier.classify(event),
                correction: CalendarEventClassification(
                    context: .personal, occasion: .meeting, presence: .remote,
                    formality: .casual, hours: 2))
        }
        let corrected = SocialBatteryModel.contactDays(events: fixture.events,
                                                       judgements: corrections,
                                                       now: now, calendar: fixture.calendar)
        XCTAssertGreaterThan(plain.reduce(0) { $0 + $1.obligatedHours }, 0)
        XCTAssertEqual(corrected.reduce(0) { $0 + $1.obligatedHours }, 0, accuracy: 1e-9,
                       "the reader said all of this was personal and it was ignored")
        XCTAssertGreaterThan(corrected.reduce(0) { $0 + $1.chosenHours }, 0)
    }

    // MARK: - Today, without a percentage

    /// The forward-looking half is a **fact off the calendar**: what is still in
    /// the diary, split at now.
    func testTodaySplitsWhatHasHappenedFromWhatIsStillAhead() throws {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        // `TestClock.now` is 22:13:20Z, so an 09:00 event is behind and a 23:30
        // one is ahead — in UTC. Anchor both relative to `now` instead, so the
        // test says the same thing on a machine in any zone.
        let past = CalendarEvent(id: "past", start: now.addingTimeInterval(-3 * 3600),
                                 end: now.addingTimeInterval(-2 * 3600),
                                 isAllDay: false, timeZoneIdentifier: nil,
                                 calendarName: "Work", kind: .timed,
                                 title: "Team planning", location: nil, hasVideoLink: true)
        let ahead = CalendarEvent(id: "ahead", start: now.addingTimeInterval(600),
                                  end: now.addingTimeInterval(3600),
                                  isAllDay: false, timeZoneIdentifier: nil,
                                  calendarName: "Work", kind: .timed,
                                  title: "Team planning", location: nil, hasVideoLink: true)
        // Both must fall inside today for the test to be about the split.
        try XCTSkipUnless(calendar.isDate(past.start, inSameDayAs: start)
                            && calendar.isDate(ahead.start, inSameDayAs: start),
                          "the anchor straddles midnight in this zone")
        let today = try XCTUnwrap(SocialBatteryModel.todayLoad(
            events: [past, ahead], judgements: [], typicalDayHours: 2, medianHours: 2,
            now: now, calendar: calendar))
        XCTAssertGreaterThan(today.elapsedHours, 0)
        XCTAssertGreaterThan(today.aheadHours, 0)
        XCTAssertEqual(today.meetings, 2)
    }

    /// Today is never in the comparison — its night has not happened.
    func testTodayIsNotOneOfTheDaysCompared() {
        let fixture = SocialFixture(response: 4)
        let days = SocialBatteryModel.contactDays(events: fixture.events, judgements: [],
                                                  now: now, calendar: fixture.calendar)
        let today = fixture.calendar.startOfDay(for: now)
        XCTAssertFalse(days.contains { $0.day >= today })
    }

    // MARK: - Curves

    /// Sweeps `input` and fails on a step. Local rather than in
    /// `ScoreContinuityTests` so that eleven agents working in parallel are not
    /// all editing one file; the rule and the tolerance are that file's.
    private func assertContinuous(_ name: String, over range: ClosedRange<Double>,
                                  steps: Int = 4000,
                                  file: StaticString = #filePath, line: UInt = #line,
                                  _ score: (Double) -> Double) {
        let width = (range.upperBound - range.lowerBound) / Double(steps)
        var previous = score(range.lowerBound)
        var worst = (jump: 0.0, at: 0.0)
        for step in 1...steps {
            let input = range.lowerBound + Double(step) * width
            let value = score(input)
            if abs(value - previous) > worst.jump { worst = (abs(value - previous), input) }
            previous = value
        }
        XCTAssertLessThanOrEqual(
            worst.jump, 1.0,
            "\(name) steps by \(worst.jump) at an input of \(worst.at)",
            file: file, line: line)
    }

    /// Both exposure curves, and every interpolation between them.
    ///
    /// ⚠️ **Sweeping both axes separately is the part that matters** — a step
    /// hides in one axis while the other is smooth, which is exactly where the
    /// blood-pressure discontinuity was.
    func testTheExposureCurveHasNoCliffOnEitherAxis() {
        for index in stride(from: -1.0, through: 1.0, by: 0.25) {
            assertContinuous("exposureScore(level, index: \(index))", over: 0...5) {
                SocialBatteryModel.exposureScore(level: $0, restorationIndex: index)
            }
        }
        for level in stride(from: 0.0, through: 4.0, by: 0.5) {
            assertContinuous("exposureScore(index, level: \(level))", over: -2...2) {
                SocialBatteryModel.exposureScore(level: level, restorationIndex: $0)
            }
        }
    }

    /// The headcount row's weight is a **ramp**, not a threshold — gating its
    /// presence on a coverage figure that moves as events sync would make a
    /// share appear and disappear with nothing behind it.
    func testThePeopleRowsWeightRampsRatherThanSwitchingOn() {
        assertContinuous("peopleConfidence", over: -0.5...1.5) {
            SocialBatteryModel.peopleConfidence(coverage: $0) * 100
        }
        XCTAssertEqual(SocialBatteryModel.peopleConfidence(coverage: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(SocialBatteryModel.peopleConfidence(coverage: 1), 1, accuracy: 1e-9)
    }

    /// The restoration index is continuous in the body's own answer, and
    /// saturates exactly where the interval clears zero.
    func testTheRestorationIndexIsContinuousAndBounded() {
        func index(_ pooled: Double) -> Double {
            SocialBatteryModel.restorationIndex(
                .init(channels: [], pooled: pooled, standardError: 0.25,
                      highDays: 20, lowDays: 20))
        }
        assertContinuous("restorationIndex", over: -3...3) { index($0) * 100 }
        XCTAssertEqual(index(0), 0, accuracy: 1e-9)
        XCTAssertEqual(index(-0.5), 1, accuracy: 1e-9, "it saturates at the interval's edge")
        XCTAssertEqual(index(-5), 1, accuracy: 1e-9)
        XCTAssertEqual(index(5), -1, accuracy: 1e-9)
    }

    // MARK: - Attribution (add-insight §5, §5a)

    /// Every derived weight names a series this card actually produces.
    ///
    /// `DerivedFactorIdentityTests` runs the same rule over the whole engine —
    /// but on a **samples-only** fixture, where this card is holding no calendar
    /// and produces nothing at all. This is the version with a calendar in it,
    /// which is the only one that can see these rows.
    func testEveryDerivedWeightNamesASeriesThisCardProduces() throws {
        let result = SocialFixture(response: 4).card()
        XCTAssertNotNil(result.score, "the fixture never reached a scored state")
        let produced = Set(DerivedHarvest.series(from: result).map { $0.0.id })
        let rows = result.weightedFactors + result.unweightedFactors
        let derived = rows.compactMap(\.derivedSeries)
        XCTAssertFalse(derived.isEmpty, "the calendar is declared nowhere")
        for id in derived {
            XCTAssertTrue(produced.contains(id),
                          "\(id.rawValue) is weighted and never produced — an empty page")
            XCTAssertEqual(id.producedBy, .socialBattery)
        }
    }

    /// Shares sum to one across both halves, and both halves are on screen.
    func testTheCalendarAndTheBodyAreShareOfOneNumber() throws {
        let result = SocialFixture(response: 4).card()
        let weighted = result.weightedFactors
        XCTAssertFalse(weighted.filter { $0.metric != nil }.isEmpty, "the body vanished")
        XCTAssertFalse(weighted.filter { $0.derivedSeries != nil }.isEmpty,
                       "the calendar vanished")
        XCTAssertEqual(weighted.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
    }

    /// Every row carrying no share says why, on its own row.
    func testEveryUnweightedRowSaysWhy() {
        let result = SocialFixture(response: 4).card()
        for row in result.unweightedFactors {
            XCTAssertTrue(row.detail.contains(" — "),
                          "\(row.name) carries no share and gives no reason: \"\(row.detail)\"")
        }
    }

    /// Contributors are a subset of what the card declares it may read, and
    /// every declared metric with data is actually read.
    func testDeclaredInputsAndReadInputsAgree() {
        let model = SocialBatteryInsight()
        let result = SocialFixture(response: 4).card()
        let declared = Set(model.candidateMetrics)
        let read = Set(result.contributors.map(\.metric))
        XCTAssertTrue(read.isSubset(of: declared), "\(read.subtracting(declared))")
        XCTAssertTrue(declared.isSubset(of: read),
                      "declared but never read: \(declared.subtracting(read))")
    }

    /// The figures the reader asked to see in the Data tab are all there, and
    /// each carries a distinct key.
    func testEveryFigureTheCardWorksOutBecomesASeries() throws {
        let out = try readyOutput()
        let outputs = SocialBatteryModel.derivedOutputs(out)
        let keys = outputs.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "two series share a key: \(keys)")
        for expected in [SocialBatteryModel.contactGapKey, SocialBatteryModel.peopleGapKey,
                         SocialBatteryModel.exposureKey, SocialBatteryModel.pooledKey,
                         SocialBatteryModel.restorationKey,
                         SocialBatteryModel.chosenResponseKey,
                         SocialBatteryModel.obligatedResponseKey] {
            XCTAssertTrue(keys.contains(expected), "\(expected) is not kept as a series")
        }
        XCTAssertTrue(outputs.allSatisfy { !$0.displayName.isEmpty })
    }

    /// The card states how its number is formed, and its confidence never reads
    /// higher than its own interval allows.
    func testConfidenceIsCappedByTheIntervalAroundTheFinding() throws {
        let called = SocialFixture(response: 4).card()
        let uncalled = SocialFixture(response: 0).card()
        XCTAssertEqual(called.weighting, .weightedAverage)
        XCTAssertEqual(uncalled.confidence, .low,
                       "a card whose central finding spans zero read as moderate")
        XCTAssertNotEqual(called.confidence, .low)
    }

    // MARK: - Registration (add-insight §3 — the two that fail silently)

    /// Registered in the engine, and rebound by `withCalendar`. Neither failure
    /// breaks the build; both make the card invisible to score recording,
    /// replay, the balance web and the comparison chart.
    func testTheCardIsRegisteredAndBoundToTheCalendar() throws {
        XCTAssertTrue(InsightEngine().models.contains { $0.id == .socialBattery },
                      "not registered, so nothing that iterates the registry can see it")
        let fixture = SocialFixture(response: 4)
        let bound = InsightEngine().withCalendar(events: fixture.events, judgements: [])
        let model = try XCTUnwrap(bound.models.first { $0.id == .socialBattery }
                                    as? SocialBatteryInsight)
        XCTAssertEqual(model.events.count, fixture.events.count,
                       "withCalendar left this card holding an empty calendar")
        XCTAssertEqual(bound.models.count, InsightEngine().models.count)
    }

    func testTheModelVersionIsPinned() {
        XCTAssertEqual(InsightID.socialBattery.modelVersion, "social-battery-v1")
    }
}
