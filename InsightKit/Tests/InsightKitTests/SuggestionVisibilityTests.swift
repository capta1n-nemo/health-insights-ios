import XCTest
@testable import InsightKit

private let visNow = TestClock.now

/// Suggestions were generated, ranked, and then shown unconditionally forever.
/// This is the half that was missing: what is worth saying *again*.
final class SuggestionVisibilityTests: XCTestCase {

    private func suggestion(_ id: String, basis: Suggestion.Basis = .signalOffBaseline,
                            strength: Double = 0.5) -> Suggestion {
        Suggestion(id: id, title: id, detail: "", basis: basis, strength: strength)
    }

    private func dismissal(_ id: String, daysAgo: Double) -> SuggestionDismissal {
        SuggestionDismissal(suggestionID: id,
                            dismissedAt: visNow.addingTimeInterval(-daysAgo * 86_400))
    }

    private func resolve(_ suggestions: [Suggestion],
                         _ dismissals: [SuggestionDismissal]) -> SuggestionVisibility.Resolved {
        SuggestionVisibility.resolve(suggestions: suggestions, dismissals: dismissals,
                                     now: visNow)
    }

    func testNothingDismissedMeansTodayShowsTheBestFoundedOne() {
        let out = resolve([suggestion("a"), suggestion("b")], [])
        XCTAssertEqual(out.today.map(\.id), ["a"])
        XCTAssertEqual(out.insights.map(\.id), ["a", "b"])
        XCTAssertFalse(out.insights.contains { $0.isDismissed })
    }

    func testADismissedSuggestionLeavesToday() {
        let out = resolve([suggestion("a"), suggestion("b")], [dismissal("a", daysAgo: 1)])
        XCTAssertEqual(out.today.map(\.id), ["b"], "the next one should take its place")
    }

    /// Insights is the persistent reminder, so a dismissal removes it from Today
    /// and marks it here — it does not delete it.
    func testInsightsKeepsDismissedSuggestions() throws {
        let out = resolve([suggestion("a")], [dismissal("a", daysAgo: 1)])
        XCTAssertTrue(out.today.isEmpty)
        let row = try XCTUnwrap(out.insights.first)
        XCTAssertTrue(row.isDismissed)
    }

    /// A suggestion silenced forever is indistinguishable from one that was
    /// never generated, so a fact still missing after a month is raised again.
    func testADismissalExpiresAfterThirtyDays() {
        XCTAssertTrue(resolve([suggestion("a")], [dismissal("a", daysAgo: 29)]).today.isEmpty)
        XCTAssertEqual(resolve([suggestion("a")], [dismissal("a", daysAgo: 31)]).today.map(\.id),
                       ["a"])
    }

    /// "It should only come back when something *new* appears." A new finding
    /// has a new id, so it is simply not dismissed — no extra machinery.
    func testSomethingNewComesBackImmediately() {
        let out = resolve([suggestion("a"), suggestion("b")], [dismissal("a", daysAgo: 1)])
        XCTAssertEqual(out.today.map(\.id), ["b"])
    }

    /// The rule that makes "hide it once the associated tasks are completed"
    /// need no per-suggestion definition of completion.
    ///
    /// The engine only emits a suggestion while its condition holds — so a
    /// grounding gap being filled, a signal returning to baseline and an
    /// observation ceasing to be true all look identical from here: the id stops
    /// being emitted. The dead dismissal is reported for pruning.
    func testASuggestionThatStoppedBeingTrueDisappearsFromBoth() {
        let out = resolve([suggestion("b")], [dismissal("a", daysAgo: 1)])
        XCTAssertFalse(out.today.contains { $0.id == "a" })
        XCTAssertFalse(out.insights.contains { $0.id == "a" })
        XCTAssertEqual(out.resolvedDismissals, ["a"], "the dead dismissal should be pruned")
    }

    /// And a live dismissal must never be pruned — pruning it would put the
    /// suggestion straight back on Today, which is the bug this test exists to
    /// stop somebody introducing while tidying.
    func testALiveDismissalIsNeverPruned() {
        XCTAssertTrue(resolve([suggestion("a")], [dismissal("a", daysAgo: 1)])
            .resolvedDismissals.isEmpty)
    }

    /// Dismissing something twice extends the silence rather than resetting it
    /// to whichever record happened to be read last.
    func testTheLatestDismissalWins() {
        let out = resolve([suggestion("a")],
                          [dismissal("a", daysAgo: 40), dismissal("a", daysAgo: 2)])
        XCTAssertTrue(out.today.isEmpty, "the recent dismissal should still be silencing it")

        let reversed = resolve([suggestion("a")],
                               [dismissal("a", daysAgo: 2), dismissal("a", daysAgo: 40)])
        XCTAssertEqual(out.today.count, reversed.today.count, "order must not matter")
    }

    func testEverythingDismissedMeansTodayShowsNothing() {
        let out = resolve([suggestion("a"), suggestion("b")],
                          [dismissal("a", daysAgo: 1), dismissal("b", daysAgo: 1)])
        XCTAssertTrue(out.today.isEmpty)
        XCTAssertEqual(out.insights.count, 2, "both stay on Insights as reminders")
    }

    func testNoSuggestionsMeansNoRows() {
        let out = resolve([], [dismissal("a", daysAgo: 1)])
        XCTAssertTrue(out.today.isEmpty)
        XCTAssertTrue(out.insights.isEmpty)
        XCTAssertEqual(out.resolvedDismissals, ["a"])
    }
}
