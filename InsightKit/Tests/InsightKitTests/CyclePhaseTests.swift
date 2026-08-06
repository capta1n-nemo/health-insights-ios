import XCTest
@testable import InsightKit

/// The phase model and the fertile window — backlog #31 slice 2.
///
/// **Most of these tests are about the uncertainty, not the estimate.** A phase
/// model that prints "day 14" is trivial to write and is what every consumer
/// tracker ships; what makes this one honest is that the ± comes from the
/// reader's own spread, that it refuses below three cycles, and that it says so
/// rather than degrading quietly.
final class CyclePhaseTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    /// Negative offsets are the past — the same convention `CycleLogTests` uses,
    /// so a fixture can be read across both files without re-learning the sign.
    private func day(_ offset: Int) -> Date {
        utc.startOfDay(for: now.addingTimeInterval(Double(offset) * 86_400))
    }

    private func log(starts: [Int], length: Int = 5) -> [CycleDay] {
        starts.flatMap { start in
            (0..<length).map { CycleDay(day: day(start + $0), flow: $0 < 2 ? .medium : .light) }
        }
    }

    private func summary(starts: [Int], length: Int = 5) -> CycleSummary {
        CycleModel.summarise(days: log(starts: starts, length: length), now: now, calendar: utc)
    }

    /// Four completed 28-day cycles, the fifth running and 20 days in — so today
    /// is well past ovulation and solidly luteal.
    private var regularReader: CycleSummary {
        summary(starts: [-132, -104, -76, -48, -20])
    }

    // MARK: - The physiology: the luteal phase is the fixed half

    /// ⚠️ **The single most important assertion in this file.** Ovulation is
    /// counted *backwards from the next period*, so the luteal phase is 14 days
    /// whatever the cycle length, and the follicular phase absorbs the
    /// difference. A forward-counting model — "day 14 of your cycle" — puts
    /// ovulation on day 14 for both readers below, and is wrong for both.
    func testOvulationIsCountedBackFromTheNextPeriodSoTheLutealHalfIsFixed() throws {
        let short = summary(starts: [-100, -76, -52, -28, -4])   // 24-day cycles
        let long = summary(starts: [-145, -110, -75, -40, -5])   // 35-day cycles

        let shortWindow = try XCTUnwrap(CyclePhaseModel.forecast(short, now: now, calendar: utc)
            .prediction)
        let longWindow = try XCTUnwrap(CyclePhaseModel.forecast(long, now: now, calendar: utc)
            .prediction)

        for prediction in [shortWindow, longWindow] {
            let lutealDays = utc.dateComponents([.day], from: prediction.fertileWindow.ovulation,
                                                to: prediction.nextPeriodStart).day
            XCTAssertEqual(lutealDays, CyclePhaseModel.lutealLengthDays,
                           "the luteal phase must be the fixed half, whatever the cycle length")
        }

        // And the follicular half is where the two readers differ — 11 days
        // apart, which is exactly the 35 − 24 the cycle lengths differ by.
        let shortFollicular = utc.dateComponents([.day], from: day(-4),
                                                 to: shortWindow.fertileWindow.ovulation).day
        let longFollicular = utc.dateComponents([.day], from: day(-5),
                                                to: longWindow.fertileWindow.ovulation).day
        XCTAssertEqual((longFollicular ?? 0) - (shortFollicular ?? 0), 11,
                       "the follicular phase must absorb the whole difference in cycle length")
    }

    /// The four phases tile the cycle with no gap and no overlap, and the day
    /// numbering inside each one restarts at 1.
    func testThePhasesTileTheCycleWithoutGapsOrOverlaps() throws {
        let summary = regularReader
        var seen: [CyclePhase] = []
        // Day 1 of the running cycle through the day before the next predicted
        // period. The prediction says 28 days, so 0..<28 covers exactly one.
        for offset in 0..<28 {
            let date = day(-20 + offset)
            let estimate = try XCTUnwrap(
                CyclePhaseModel.phase(on: date, summary: summary, now: now, calendar: utc),
                "day \(offset + 1) of the cycle has no phase")
            XCTAssertEqual(estimate.dayOfCycle, offset + 1)
            XCTAssertTrue(estimate.bounds.contains(date),
                          "\(estimate.phase) does not contain the day it was returned for")
            if seen.last != estimate.phase { seen.append(estimate.phase) }
        }
        XCTAssertEqual(seen, [.menstrual, .follicular, .ovulatory, .luteal],
                       "the phases must run in order and each appear once: \(seen)")
    }

    // MARK: - The fertile window

    /// Ovulation minus five days through ovulation itself — the six-day interval
    /// from Wilcox 1995. Asymmetric because sperm outlive the ovum, and a
    /// symmetric window would be the wrong shape in both directions.
    func testTheFertileWindowIsTheSixDaysEndingOnOvulation() throws {
        let prediction = try XCTUnwrap(
            CyclePhaseModel.forecast(regularReader, now: now, calendar: utc).prediction)
        let window = prediction.fertileWindow

        XCTAssertEqual(window.core.upperBound, window.ovulation,
                       "the window closes on ovulation day, it does not straddle it")
        let span = utc.dateComponents([.day], from: window.core.lowerBound,
                                      to: window.core.upperBound).day
        XCTAssertEqual(span, CyclePhaseModel.fertileDaysBeforeOvulation)
        XCTAssertEqual(span, 5, "six days inclusive — Wilcox 1995")
    }

    /// The soft edge is the ± made visible: `outer` is `core` widened by the
    /// ovulation uncertainty on both sides, which is what the calendar fades.
    func testTheOuterWindowIsTheCoreWidenedByTheUncertaintyOnBothSides() throws {
        let prediction = try XCTUnwrap(
            CyclePhaseModel.forecast(regularReader, now: now, calendar: utc).prediction)
        let window = prediction.fertileWindow
        let pad = window.uncertaintyDays

        XCTAssertEqual(utc.dateComponents([.day], from: window.outer.lowerBound,
                                          to: window.core.lowerBound).day, pad)
        XCTAssertEqual(utc.dateComponents([.day], from: window.core.upperBound,
                                          to: window.outer.upperBound).day, pad)
        XCTAssertTrue(window.outer.contains(window.core.lowerBound))
        XCTAssertTrue(window.outer.contains(window.core.upperBound))
    }

    // MARK: - What it refuses to say

    /// ⚠️ **Two cycles buy nothing.** The ± is derived from the spread, and a
    /// spread needs three observations — so a window drawn from two is an
    /// interval computed correctly over numbers that cannot support one.
    func testItRefusesToPredictBelowThreeCycles() throws {
        let two = summary(starts: [-84, -56, -28])
        XCTAssertEqual(two.lengths.count, 2)

        let refusal = try XCTUnwrap(
            CyclePhaseModel.forecast(two, now: now, calendar: utc).refusal)
        XCTAssertEqual(refusal, .tooFewCycles(have: 2, need: 3))
        XCTAssertTrue(refusal.sentence.contains("1 more"), refusal.sentence)
        XCTAssertTrue(refusal.sentence.contains("guess"), refusal.sentence)

        // And nothing leaks out the side door: no phase for a non-bleeding day.
        XCTAssertNil(CyclePhaseModel.phase(on: day(-10), summary: two, now: now, calendar: utc),
                     "a phase was placed from two cycles")
    }

    func testAnEmptyLogRefusesWithSomethingUsefulRatherThanNothing() throws {
        let empty = CycleModel.summarise(days: [], now: now, calendar: utc)
        let refusal = try XCTUnwrap(
            CyclePhaseModel.forecast(empty, now: now, calendar: utc).refusal)
        XCTAssertEqual(refusal, .nothingLogged)
        XCTAssertFalse(refusal.sentence.isEmpty)
        XCTAssertNil(CyclePhaseModel.phase(on: day(0), summary: empty, now: now, calendar: utc))
    }

    /// A reader whose cycles run 21 to 33 days gets a ±8 on ovulation, which
    /// makes the outer window 22 days wide. That is not a window; it is the
    /// month with an opinion, and the honest output is the refusal.
    func testItRefusesWhenTheReadersOwnSpreadIsWiderThanTheWindow() throws {
        // 21, 33 and 27-day cycles: a spread of 12.
        let variable = summary(starts: [-95, -74, -41, -14])
        XCTAssertEqual(variable.spread, 12)

        let refusal = try XCTUnwrap(
            CyclePhaseModel.forecast(variable, now: now, calendar: utc).refusal)
        guard case let .tooVariable(spread, uncertainty) = refusal else {
            return XCTFail("expected a too-variable refusal, got \(refusal)")
        }
        XCTAssertEqual(spread, 12)
        XCTAssertGreaterThan(uncertainty, CyclePhaseModel.maximumUsefulUncertaintyDays)
        XCTAssertTrue(refusal.sentence.contains("12 days"), refusal.sentence)
    }

    /// A log that stopped a year ago has no cycle in progress to predict from,
    /// and must not predict from the last one it saw.
    func testAnAbandonedLogRefusesRatherThanPredictingFromLastYear() throws {
        let stale = summary(starts: [-500, -472, -444, -416])
        let refusal = try XCTUnwrap(
            CyclePhaseModel.forecast(stale, now: now, calendar: utc).refusal)
        XCTAssertEqual(refusal, .logStale)
        XCTAssertNil(CyclePhaseModel.phase(on: day(0), summary: stale, now: now, calendar: utc))
    }

    // MARK: - The uncertainty is the reader's own

    /// ⚠️ **The ± must move when the reader's cycles do.** A model whose interval
    /// is the same for a metronome and for someone varying by a week has a
    /// textbook constant wearing a personalised label.
    func testTheUncertaintyIsDerivedFromTheReadersOwnSpreadAndNotAConstant() throws {
        let steady = regularReader                                  // spread 0
        let varied = summary(starts: [-116, -88, -56, -28])         // 28, 32, 28: spread 4

        let steadyPrediction = try XCTUnwrap(
            CyclePhaseModel.forecast(steady, now: now, calendar: utc).prediction)
        let variedPrediction = try XCTUnwrap(
            CyclePhaseModel.forecast(varied, now: now, calendar: utc).prediction)

        XCTAssertEqual(varied.spread, 4)
        XCTAssertGreaterThan(variedPrediction.fertileWindow.uncertaintyDays,
                             steadyPrediction.fertileWindow.uncertaintyDays,
                             "a reader who varies more must get a wider window")
        XCTAssertEqual(variedPrediction.nextPeriodUncertaintyDays, 2, "half a spread of 4")
    }

    /// Three identical cycles do not prove zero variability — they prove it is
    /// smaller than three observations can resolve. So the floor is one day, and
    /// a "±0" is never printed.
    func testAPerfectlyRegularReaderStillGetsAFloorOfOneDay() throws {
        let prediction = try XCTUnwrap(
            CyclePhaseModel.forecast(regularReader, now: now, calendar: utc).prediction)
        XCTAssertEqual(regularReader.spread, 0)
        XCTAssertEqual(prediction.nextPeriodUncertaintyDays, 1,
                       "±0 would claim three cycles proved perfect regularity")
        XCTAssertEqual(prediction.fertileWindow.uncertaintyDays,
                       1 + CyclePhaseModel.lutealLengthUncertaintyDays,
                       "the reader's spread plus the luteal constant, added not replaced")
    }

    /// A finished cycle knows when the next period actually began, so only the
    /// luteal constant is uncertain. A retrospective phase is genuinely tighter
    /// than a forward one and flattening the two would throw that away.
    func testAPastCycleIsTighterThanTheRunningOneBecauseItsEndWasObserved() throws {
        let summary = regularReader
        // Mid-luteal in the cycle that ran -48 … -21: ovulation is 14 days back
        // from -20, so -30 is comfortably inside it.
        let past = try XCTUnwrap(
            CyclePhaseModel.phase(on: day(-30), summary: summary, now: now, calendar: utc))
        // Mid-luteal in the running cycle.
        let current = try XCTUnwrap(
            CyclePhaseModel.phase(on: day(0), summary: summary, now: now, calendar: utc))

        XCTAssertEqual(past.phase, .luteal)
        XCTAssertEqual(current.phase, .luteal)
        XCTAssertEqual(past.dayInPhaseUncertaintyDays,
                       CyclePhaseModel.lutealLengthUncertaintyDays,
                       "a completed cycle's next period is a fact, not a prediction")
        XCTAssertGreaterThan(current.dayInPhaseUncertaintyDays,
                             past.dayInPhaseUncertaintyDays)
    }

    // MARK: - Observed beats modelled

    /// **A logged bleeding day needs no model.** It is menstrual from one cycle,
    /// with no ± and no minimum — which is the difference between a record and
    /// a prediction, and the reader sees it as the difference between "day 3"
    /// and "probably day 3".
    func testALoggedBleedingDayIsMenstrualWithNoModelAndNoMinimumCycles() throws {
        let single = summary(starts: [-2])
        XCTAssertNil(CyclePhaseModel.forecast(single, now: now, calendar: utc).prediction,
                     "one cycle cannot support a prediction")

        let estimate = try XCTUnwrap(
            CyclePhaseModel.phase(on: day(-1), summary: single, now: now, calendar: utc))
        XCTAssertEqual(estimate.phase, .menstrual)
        XCTAssertTrue(estimate.isObserved)
        XCTAssertEqual(estimate.dayInPhaseUncertaintyDays, 0)
        XCTAssertFalse(estimate.isBoundaryAmbiguous)
        XCTAssertEqual(estimate.dayInPhase, 2)
    }

    /// The follicular phase *begins* on the day after bleeding stopped, which is
    /// a fact — so its start carries no ±, while its end does. One "phase
    /// uncertainty" for both would invent doubt at the observed edge.
    func testTheFollicularStartIsObservedEvenThoughItsEndIsPredicted() throws {
        let estimate = try XCTUnwrap(
            CyclePhaseModel.phase(on: day(-15), summary: regularReader, now: now, calendar: utc))
        XCTAssertEqual(estimate.phase, .follicular)
        XCTAssertEqual(estimate.dayInPhase, 1, "the day after the last logged bleeding day")
        XCTAssertEqual(estimate.dayInPhaseUncertaintyDays, 0)
        XCTAssertFalse(estimate.isBoundaryAmbiguous,
                       "the day after bleeding stops is definitely follicular")
    }

    /// And a day sitting inside the distance a modelled boundary could move is
    /// flagged, so the sentence can hedge instead of asserting.
    func testADayAgainstAModelledBoundaryIsFlaggedAsAmbiguous() throws {
        // Ovulation is 14 days back from the predicted period at +8, so the
        // ovulatory window is -7 … -5 with a ±3. -8 is one day off it.
        let estimate = try XCTUnwrap(
            CyclePhaseModel.phase(on: day(-8), summary: regularReader, now: now, calendar: utc))
        XCTAssertEqual(estimate.phase, .follicular)
        XCTAssertTrue(estimate.isBoundaryAmbiguous,
                      "a day against the ovulation estimate cannot be asserted")
        XCTAssertTrue(CyclePhaseModel.phaseSentence(estimate).hasPrefix("Probably"),
                      CyclePhaseModel.phaseSentence(estimate))
    }

    // MARK: - What reaches the screen

    /// No branch of the phase sentence asserts a phase flatly. Either it names
    /// an observed fact and says so, or it hedges — and it shows a ± exactly
    /// when the day number itself is uncertain.
    ///
    /// ⚠️ **A modelled phase with no ± is correct, not a gap.** The follicular
    /// day number is counted from the last logged bleeding day, so "day 3" is
    /// exact even though "follicular" is a model's word — the hedge belongs on
    /// the phase name and the ± belongs on the number, and conflating them is
    /// how a screen either over- or under-claims.
    func testNoPhaseSentenceIsABareAssertion() throws {
        let summary = regularReader
        var sawPlusMinus = false
        for offset in 0..<28 {
            let estimate = try XCTUnwrap(
                CyclePhaseModel.phase(on: day(-20 + offset), summary: summary,
                                      now: now, calendar: utc))
            let sentence = CyclePhaseModel.phaseSentence(estimate)
            if estimate.isObserved {
                XCTAssertTrue(sentence.contains("from your log"), sentence)
                XCTAssertFalse(sentence.contains("±"), "a logged day has no ±: \(sentence)")
                continue
            }
            XCTAssertTrue(sentence.hasPrefix("Likely") || sentence.hasPrefix("Probably"),
                          "asserted a modelled phase flatly: \(sentence)")
            XCTAssertEqual(sentence.contains("±"), estimate.dayInPhaseUncertaintyDays > 0,
                           "the ± must appear exactly when the day number is uncertain: \(sentence)")
            if sentence.contains("±") { sawPlusMinus = true }
        }
        XCTAssertTrue(sawPlusMinus,
                      "no day in a whole cycle showed a ± — the uncertainty never reached a sentence")
    }

    /// ⚠️ **The not-contraception sentence exists, says so plainly, and is a
    /// constant the UI reads rather than a string a redesign can drop.**
    func testTheNotContraceptionNoticeSaysSoInPlainWords() {
        let notice = CyclePhaseModel.notContraceptionNotice.lowercased()
        XCTAssertTrue(notice.contains("not contraception"), notice)
        XCTAssertTrue(notice.contains("not fertility advice"), notice)
    }

    /// The window sentence names its basis. A window with no stated basis is
    /// indistinguishable from one copied out of a textbook.
    func testTheFertileWindowSentenceNamesHowManyOfTheReadersOwnCyclesItUsed() throws {
        let prediction = try XCTUnwrap(
            CyclePhaseModel.forecast(regularReader, now: now, calendar: utc).prediction)
        let sentence = CyclePhaseModel.fertileWindowSentence(prediction, calendar: utc)
        XCTAssertTrue(sentence.contains("4 of your own cycles"), sentence)
        XCTAssertTrue(sentence.contains("±\(prediction.fertileWindow.uncertaintyDays) days"),
                      sentence)
        XCTAssertFalse(sentence.lowercased().contains("safe"),
                       "the window must never be worded as a safe day: \(sentence)")
    }

    // MARK: - Degenerate shapes

    /// A 21-day cycle with a 7-day period leaves no room for 14 days of luteal
    /// plus a follicular phase. The boundaries clamp rather than producing a
    /// range that runs backwards, which `ClosedRange` traps on.
    func testAShortCycleWithALongPeriodClampsInsteadOfCrashing() throws {
        let tight = summary(starts: [-84, -63, -42, -21], length: 7)
        for offset in 0..<21 {
            _ = CyclePhaseModel.phase(on: day(-21 + offset), summary: tight,
                                      now: now, calendar: utc)
        }
        // The point is that the loop above did not trap; assert something real
        // as well so the test cannot pass by doing nothing.
        XCTAssertEqual(tight.lengths, [21, 21, 21])
    }

    /// A date before anything was logged belongs to no cycle.
    func testADateBeforeTheLogHasNoPhase() {
        XCTAssertNil(CyclePhaseModel.phase(on: day(-300), summary: regularReader,
                                           now: now, calendar: utc))
    }
}
