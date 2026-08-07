import XCTest
@testable import InsightKit

private let stateNow = TestClock.now
private let stateCalendar = TestClock.utc

/// **The fourth state.** Backlog B15-2.
///
/// `ScoreChangeReader` used to answer `ScoreChange?` and the dashboard rendered
/// the `nil` as an empty space, so three different situations — never scored,
/// scored but not today, scored but not enough — arrived at the reader as the
/// same blank. Only one of them is a reason to keep going, and it was the one
/// the app could not say.
///
/// These tests pin the *distinction*, not the wording: each cause must produce
/// its own case, and the `ScoreChange?` entry points must keep answering exactly
/// what they answered before.
final class ScoreChangeStateTests: XCTestCase {

    private func history(_ scores: [Double], endingDaysAgo: Int = 0) -> [ScorePoint] {
        let today = stateCalendar.startOfDay(for: stateNow)
        return scores.enumerated().map { index, score in
            let back = Double(scores.count - 1 - index + endingDaysAgo)
            return ScorePoint(date: today.addingTimeInterval(-back * 86_400),
                              score: score, confidence: .moderate, contributorCount: 3)
        }
    }

    private func dailyState(_ scores: [Double], endingDaysAgo: Int = 0) -> ScoreChangeState {
        ScoreChangeReader.dailyState(history: history(scores, endingDaysAgo: endingDaysAgo),
                                     now: stateNow, calendar: stateCalendar)
    }

    // MARK: - Daily

    func testNoHistoryAtAllIsLearningRatherThanAnEmptySpace() throws {
        let state = ScoreChangeReader.dailyState(history: [], now: stateNow,
                                                 calendar: stateCalendar)
        let gate = try XCTUnwrap(state.gate, "an empty history is learning, not silence")
        XCTAssertEqual(gate.have, 0)
        XCTAssertEqual(gate.need, ScoreChangeReader.minimumDailyReference)
        XCTAssertEqual(state.pendingLabel, "Learning trends")
        XCTAssertNotNil(state.explanation)
        XCTAssertNil(state.change)
    }

    /// The number that makes someone carry on is *how many more*, and the gate
    /// has to count what is actually there rather than start from zero again.
    func testPartialHistoryCountsWhatItHas() throws {
        let gate = try XCTUnwrap(dailyState([70, 72, 71]).gate)
        XCTAssertEqual(gate.have, 2, "today is the recent side, not the reference")
        XCTAssertEqual(gate.remaining, ScoreChangeReader.minimumDailyReference - 2)
        XCTAssertTrue(try XCTUnwrap(gate.sentence).contains("2 of 4"))
    }

    /// Plenty of history, but the latest score predates today. Nothing is
    /// missing except a sync, so telling the reader to keep wearing something
    /// would be wrong advice — this is its own case for that reason.
    func testAStaleLatestScoreIsNotLearning() {
        let state = dailyState([70, 72, 71, 69, 73, 70, 71, 72], endingDaysAgo: 2)
        XCTAssertEqual(state, .notScoredToday)
        XCTAssertNil(state.gate, "the history is there — nothing is being waited for")
        XCTAssertEqual(state.pendingLabel, "Not scored yet")
    }

    func testAFullHistoryMeasures() throws {
        let state = dailyState([60, 62, 61, 59, 63, 60, 61, 78])
        let change = try XCTUnwrap(state.change)
        XCTAssertEqual(change.direction, .up)
        XCTAssertNil(state.pendingLabel, "a measured card draws an arrow, not a word")
        XCTAssertNil(state.explanation)
    }

    /// A met requirement says nothing — the rule `CoverageGate` was written to
    /// enforce. A card that keeps naming a threshold it has cleared is nagging.
    func testAMeasuredStateCarriesNoGate() {
        XCTAssertNil(dailyState([60, 62, 61, 59, 63, 60, 61, 78]).gate)
    }

    // MARK: - The old API must not have moved

    /// `daily` is now `dailyState().change`, and the reordering of its two
    /// failure tests must not have changed which inputs produce a figure.
    func testTheChangeOnlyAPIAnswersExactlyWhatItUsedTo() {
        XCTAssertNil(ScoreChangeReader.daily(history: history([70, 72]),
                                             now: stateNow, calendar: stateCalendar))
        XCTAssertNil(ScoreChangeReader.daily(
            history: history([70, 72, 71, 69, 73, 70, 71, 72], endingDaysAgo: 2),
            now: stateNow, calendar: stateCalendar))
        XCTAssertNotNil(ScoreChangeReader.daily(
            history: history([60, 62, 61, 59, 63, 60, 61, 78]),
            now: stateNow, calendar: stateCalendar))
    }

    // MARK: - Trend

    /// Two requirements, one sentence. The gate shown is the one that will
    /// still be blocking after the other clears — a gate that promises a figure
    /// which does not arrive is not read a second time.
    func testTheTrendGateNamesWhicheverIsFurthestFromBeingMet() throws {
        // 25 of the last 90 days scored, all inside the last four weeks: the
        // long requirement is met, the recent one is not.
        let dense = history(Array(repeating: 70.0, count: 25))
        let recentShort = ScoreChangeReader.broadState(history: dense, now: stateNow)
        XCTAssertNil(recentShort.gate, "25 recent days meets both requirements")

        // Six days, which meets neither. Recent needs 7 (86% there), the
        // reference needs 21 (29% there) — so the reference is the blocker.
        let thin = history(Array(repeating: 70.0, count: 6))
        let gate = try XCTUnwrap(ScoreChangeReader.broadState(history: thin, now: stateNow).gate)
        XCTAssertEqual(gate.need, ScoreChangeReader.minimumTrendReference)
        XCTAssertEqual(gate.have, 6)
    }

    func testTheTrendChangeOnlyAPIStillMatchesTheState() {
        let thin = history(Array(repeating: 70.0, count: 6))
        XCTAssertNil(ScoreChangeReader.broad(history: thin, now: stateNow))
        XCTAssertEqual(ScoreChangeReader.broadState(history: thin, now: stateNow).change, nil)
    }

    /// Cadence picks the window, and it has to pick the *state* by the same
    /// rule — otherwise a card could show an arrow from one path and a gate
    /// from the other.
    func testCadenceRoutesTheStateTheSameWayItRoutesTheChange() {
        let thin = history([70, 72])
        for id in InsightID.allCases {
            let state = ScoreChangeReader.state(for: id, history: thin, now: stateNow,
                                                calendar: stateCalendar)
            let change = ScoreChangeReader.trend(for: id, history: thin, now: stateNow,
                                                 calendar: stateCalendar)
            XCTAssertEqual(state.change, change, "\(id) disagrees with itself")
        }
    }
}
