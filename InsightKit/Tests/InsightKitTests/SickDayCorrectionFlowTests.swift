import XCTest
@testable import InsightKit

/// **What happens when the reader corrects a day to say they were ill** — the
/// whole path, end to end, from the reported defect (2026-08-09, from their own
/// phone):
///
/// > *"bugs like when I correct a day to include illness on the calendar… like I
/// > add severe sickness, the days still shows green on the calendar and the AI
/// > doesn't seem to learn from it"*
///
/// Two failures in one sentence, and they had different causes:
///
/// | | What broke | Where |
/// | --- | --- | --- |
/// | **(a)** the square stayed green | the calendar coloured from `DayHistory.output.status`, whose only input is `samples` | `SickDaysCalendarSection.fill(for:)` |
/// | **(b)** nothing learnt from it | a correction on a *timed* event produced no ledger period at all | `SickDayLedger.detected` |
///
/// Neither is testable where it was found — one is a SwiftUI view and the other
/// needed a shape nobody had written a fixture for — so this file pins the model
/// facts each fix rests on. The view's own arithmetic is the first section: the
/// square must agree with the page one tap behind it, and it must not repaint
/// six months of history on a day nobody said anything about.
///
/// ⚠️ **Every fixture title here is invented.** This repo is public and an event
/// title is the most identifying string the app holds — `docs/privacy-and-ip.md`.
final class SickDayCorrectionFlowTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    /// ⚠️ An obviously fake identity, per `docs/privacy-and-ip.md`.
    private let me = ReaderIdentity(name: "Alex Reader",
                                    workEmails: ["a.reader@example.com"])

    private func day(_ n: Int) -> Date {
        utc.startOfDay(for: now.addingTimeInterval(-Double(n) * 86_400))
    }

    private func signal(_ metric: MetricType, z: Double,
                        concerning: Bool = true) -> HealthWatchModel.Signal {
        HealthWatchModel.Signal(metric: metric, recent: 0, reference: 0, zScore: z,
                                isConcerning: concerning)
    }

    /// A day the watch judged, built the way `timeline` builds one.
    private func output(_ signals: [HealthWatchModel.Signal]) throws
        -> HealthWatchModel.Output {
        try XCTUnwrap(HealthWatchModel.output(fromEvaluated: signals))
    }

    /// An ordinary morning: two channels, neither leaning. The green square.
    private func quietDay() throws -> HealthWatchModel.Output {
        try output([signal(.restingHeartRate, z: 0.1, concerning: false),
                    signal(.respiratoryRate, z: 0.1, concerning: false)])
    }

    private func sickDayPeriod(_ severity: CalendarEventClassification.SickSeverity,
                               on n: Int) -> SickDayLedger {
        SickDayLedger(entered: [.init(firstDay: day(n), lastDay: day(n),
                                      severity: severity, source: .entered)],
                      calendar: utc)
    }

    // MARK: - (a) The square's colour

    /// **The equivalence the fill rests on.**
    ///
    /// `SickDaysCalendarSection.fill(for:said:)` used to read
    /// `Output.status` and now reads
    /// `verdict(today:accumulation: .none, reported:)`. Those are two separate
    /// sets of band gates in two separate places, and if they ever disagree the
    /// change quietly repaints six months of squares for a reason nobody asked
    /// for. On a day nothing was reported they must be the same answer, for
    /// every shape of day the calendar can draw.
    func testAQuietDayIsUnchangedWhenNothingWasSaid() throws {
        let days: [HealthWatchModel.Output] = [
            try quietDay(),
            // One channel leaning — the calendar's fourth colour.
            try output([signal(.restingHeartRate, z: 1.4),
                        signal(.respiratoryRate, z: 0.1, concerning: false)]),
            // Two leaning, which is the agreement gate.
            try output([signal(.restingHeartRate, z: 2.2),
                        signal(.respiratoryRate, z: 2.2)]),
            // One hard lean, which stops an all-clear on its own.
            try output([signal(.restingHeartRate, z: 3.4),
                        signal(.respiratoryRate, z: 0.1, concerning: false)]),
            // Far enough out to reach the strong band.
            try output([signal(.restingHeartRate, z: 4.5),
                        signal(.respiratoryRate, z: 4.5),
                        signal(.oxygenSaturation, z: 4.5)])
        ]
        for today in days {
            let verdict = SymptomRadarModel.verdict(today: today, accumulation: .none,
                                                    reported: .silent)
            XCTAssertEqual(verdict.status, today.status,
                           "the calendar's fill changed a day nobody spoke about")
            XCTAssertEqual(verdict.score, today.score, accuracy: 0.000_1)
        }
    }

    /// **The reported defect, at the level the square reads.** A green morning
    /// the reader has marked as severe illness is not a green morning.
    func testASevereSickDayTakesAQuietMorningOffGreen() throws {
        let today = try quietDay()
        XCTAssertEqual(today.status, .quiet, "fixture is not the green square")

        let said = ReportedIllness.evaluate(day: day(3), symptoms: [],
                                            sickDays: sickDayPeriod(.severe, on: 3),
                                            calendar: utc)
        let verdict = SymptomRadarModel.verdict(today: today, accumulation: .none,
                                                reported: said)
        XCTAssertNotEqual(verdict.status, .quiet,
                          "a day the reader recorded as severe illness still painted quiet")
        XCTAssertTrue(verdict.isReaderReported,
                      "the verdict did not attribute the change to the reader")
        XCTAssertLessThan(verdict.score, today.score)
    }

    /// **Same-day only, on the calendar as everywhere else.** The neighbouring
    /// squares must not move — a statement about Tuesday is about Tuesday, and
    /// the whole reason the fill takes `accumulation: .none` is that memory is
    /// the band and never the colour.
    func testAStatementDoesNotColourTheDaysAroundIt() throws {
        let today = try quietDay()
        let ledger = sickDayPeriod(.severe, on: 3)
        for other in [2, 4] {
            let said = ReportedIllness.evaluate(day: day(other), symptoms: [],
                                                sickDays: ledger, calendar: utc)
            XCTAssertFalse(said.isSpeaking)
            XCTAssertEqual(
                SymptomRadarModel.verdict(today: today, accumulation: .none,
                                          reported: said).status,
                .quiet, "a sick day bled onto the day beside it")
        }
    }

    /// **A grade the reader never gave still speaks**, and this is the case that
    /// found `ReportedIllness.pastTheEdge`.
    ///
    /// `nil` and `.unstated` are both "they said they were ill" — and `.unstated`
    /// is what a calendar-detected sick day carries and what the correction sheet
    /// offers first, so it is the *common* case, not the corner one. It was
    /// anchored exactly on `someSignsExcess`, which scores exactly 85, which the
    /// `score >= 85` gate reads as **quiet**: the day stayed green no matter what
    /// the calendar did with it.
    func testAnUngradedSickDayStillMovesTheSquare() throws {
        let today = try quietDay()
        for severity: CalendarEventClassification.SickSeverity? in [nil, .unstated, .mild] {
            let ledger = SickDayLedger(
                entered: [.init(firstDay: day(5), lastDay: day(5),
                                severity: severity, source: .entered)],
                calendar: utc)
            let said = ReportedIllness.evaluate(day: day(5), symptoms: [],
                                                sickDays: ledger, calendar: utc)
            XCTAssertTrue(said.isSpeaking)
            XCTAssertNotEqual(
                SymptomRadarModel.verdict(today: today, accumulation: .none,
                                          reported: said).status,
                .quiet, "an ungraded sick day left the square green")
        }
    }

    /// The mark on the square, and the sentence beside it, both come from
    /// `components` — so a speaking day always has something to render, and it
    /// says what was recorded rather than what it means.
    func testTheDayCarriesAPhraseTheSquareCanRender() throws {
        let said = ReportedIllness.evaluate(day: day(3), symptoms: [],
                                            sickDays: sickDayPeriod(.severe, on: 3),
                                            calendar: utc)
        let component = try XCTUnwrap(said.component(.recordedSickDay))
        XCTAssertFalse(component.detail.isEmpty,
                       "nothing for the readout to say about a recorded sick day")
        XCTAssertTrue(component.detail.lowercased().contains("severe"))
        // The standing ban, restated where a new surface renders the phrase.
        XCTAssertFalse(component.detail.lowercased().contains("infection"))
    }

    // MARK: - (b) The correction reaching the ledger at all

    /// **The reported defect's other half.** A reader who opens the review row
    /// for an ordinary timed event, sets it to *Sick day* and grades it severe
    /// has said the day was one. Before 2026-08-09 the shape test dropped it
    /// before anything downstream ever saw it: no ledger period, so no Data-tab
    /// row, no radar input, no export line — the app agreeing with itself that
    /// nothing had been said.
    func testAReaderCorrectingATimedEventToSickBecomesAPeriod() throws {
        let slot = CalendarEvent(id: "slot", start: day(4).addingTimeInterval(9 * 3600),
                                 end: day(4).addingTimeInterval(10 * 3600),
                                 isAllDay: false, timeZoneIdentifier: nil,
                                 calendarName: "Work", kind: .timed,
                                 title: "Weekly sync")
        let guess = CalendarEventClassifier.classify(slot, identity: me)
        XCTAssertNotEqual(guess.occasion, .sick, "fixture already reads as illness")

        let correction = CalendarEventClassification(
            context: guess.context, occasion: .sick, presence: guess.presence,
            formality: guess.formality, hours: guess.hours,
            deciders: [CalendarEventClassification.occasionKey: .reader,
                       CalendarEventClassification.severityKey: .reader],
            severity: .severe)
        let periods = SickDayLedger.detected(
            events: [slot],
            judgements: [CalendarEventJudgement(eventID: slot.id, classification: guess,
                                                correction: correction)],
            calendar: utc)

        let period = try XCTUnwrap(periods.first,
                                   "the reader's correction produced no sick-day period")
        XCTAssertEqual(period.firstDay, day(4))
        XCTAssertEqual(period.lastDay, day(4))
        XCTAssertEqual(period.severity, .severe)
        XCTAssertEqual(period.source, .detected)
        XCTAssertNil(period.label, "the event's words stay with the event")
    }

    /// Agreeing it was a sick day and saying **how bad** is the same act, so a
    /// reader-set grade admits a timed block on its own. Nothing but the reader
    /// ever fills `severity` in.
    func testGradingATimedSickBlockIsEnoughOnItsOwn() throws {
        let slot = CalendarEvent(id: "gp", start: day(2).addingTimeInterval(11 * 3600),
                                 end: day(2).addingTimeInterval(12 * 3600),
                                 isAllDay: false, timeZoneIdentifier: nil,
                                 calendarName: "Personal", kind: .timed,
                                 title: "Unwell")
        let guess = CalendarEventClassifier.classify(slot, identity: me)
        XCTAssertEqual(guess.occasion, .sick, "fixture no longer reads as illness")
        XCTAssertTrue(SickDayLedger.detected(
            events: [slot],
            judgements: [CalendarEventJudgement(eventID: slot.id, classification: guess)],
            calendar: utc).isEmpty, "a guess alone should still be dropped")

        let graded = CalendarEventClassification(
            context: guess.context, occasion: .sick, presence: guess.presence,
            formality: guess.formality, hours: guess.hours,
            deciders: [CalendarEventClassification.severityKey: .reader],
            severity: .moderate)
        XCTAssertEqual(
            SickDayLedger.detected(
                events: [slot],
                judgements: [CalendarEventJudgement(eventID: slot.id,
                                                    classification: guess,
                                                    correction: graded)],
                calendar: utc).first?.severity,
            .moderate)
    }

    /// The predicate itself, both ways — the rule is *who decided*, never what
    /// the title said.
    func testOnlyTheReadersOwnDecisionAdmitsATimedBlock() {
        let base = CalendarEventClassification(context: .personal, occasion: .sick,
                                               presence: .unstated, formality: .casual,
                                               hours: 1, severity: .severe)
        XCTAssertFalse(base.sicknessIsTheReaders,
                       "a rules guess claimed to be the reader's own statement")
        XCTAssertTrue(CalendarEventClassification(
            context: .personal, occasion: .sick, presence: .unstated,
            formality: .casual, hours: 1,
            deciders: [CalendarEventClassification.occasionKey: .reader],
            severity: .severe).sicknessIsTheReaders)
        // Not a sick day at all: the reader deciding it was a meeting is not a
        // statement about illness, whatever else they touched.
        XCTAssertFalse(CalendarEventClassification(
            context: .work, occasion: .meeting, presence: .unstated,
            formality: .standard, hours: 1,
            deciders: [CalendarEventClassification.occasionKey: .reader])
            .sicknessIsTheReaders)
        // The on-device model deciding it is still a guess.
        XCTAssertFalse(CalendarEventClassification(
            context: .personal, occasion: .sick, presence: .unstated,
            formality: .casual, hours: 1,
            deciders: [CalendarEventClassification.occasionKey: .model],
            severity: .severe).sicknessIsTheReaders)
    }

    /// **The whole path in one test**: correct an event, and the thing the
    /// symptom radar reads has changed. This is the reader's "the AI doesn't
    /// seem to learn from it", asserted rather than argued about.
    func testACorrectedEventReachesWhatTheRadarReads() throws {
        let slot = CalendarEvent(id: "block", start: day(6).addingTimeInterval(13 * 3600),
                                 end: day(6).addingTimeInterval(14 * 3600),
                                 isAllDay: false, timeZoneIdentifier: nil,
                                 calendarName: "Work", kind: .timed,
                                 title: "Catch-up")
        let guess = CalendarEventClassifier.classify(slot, identity: me)
        let judged = CalendarEventJudgement(
            eventID: slot.id, classification: guess,
            correction: CalendarEventClassification(
                context: guess.context, occasion: .sick, presence: guess.presence,
                formality: guess.formality, hours: guess.hours,
                deciders: [CalendarEventClassification.occasionKey: .reader],
                severity: .severe))

        // Exactly how `AppModel.sickDayLedger` assembles it.
        let ledger = SickDayLedger(
            detected: SickDayLedger.detected(events: [slot], judgements: [judged],
                                             calendar: utc),
            calendar: utc)
        let said = ReportedIllness.evaluate(day: day(6), symptoms: [],
                                            sickDays: ledger, calendar: utc)
        XCTAssertEqual(said.excess, HealthWatchModel.strongSignsExcess,
                       "a corrected severe day did not reach the radar's strong edge")
        XCTAssertNotEqual(
            SymptomRadarModel.verdict(today: try quietDay(), accumulation: .none,
                                      reported: said).status,
            .quiet)
        XCTAssertEqual(ledger.daysSinceLastSickDay(asOf: day(0), calendar: utc), 6)
    }

    /// Two judgement rows for one event id is a storage defect, and the strict
    /// dictionary initialiser used to answer a storage defect by killing the
    /// process on the launch path that builds this ledger.
    func testDuplicateJudgementRowsDoNotBringTheAppDown() {
        let block = CalendarEvent(id: "dupe", start: day(3),
                                  end: day(3).addingTimeInterval(86_400),
                                  isAllDay: true, timeZoneIdentifier: nil,
                                  calendarName: "Personal", kind: .allDay,
                                  title: "Off sick")
        let guess = CalendarEventClassifier.classify(block, identity: me)
        let periods = SickDayLedger.detected(
            events: [block],
            judgements: [CalendarEventJudgement(eventID: block.id, classification: guess),
                         CalendarEventJudgement(eventID: block.id, classification: guess)],
            calendar: utc)
        XCTAssertEqual(periods.count, 1)
    }
}
