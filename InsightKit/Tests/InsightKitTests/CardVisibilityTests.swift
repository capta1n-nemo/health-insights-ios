import XCTest
@testable import InsightKit

/// **Two cards shipped invisible on 2026-08-03**, and the user found them
/// missing from a build that contained them. Nutrition and Metabolism both need
/// a food log; with none they returned `notReady`, which sets no
/// `primaryValue` and no unmet requirement — so `isWorthShowing` filtered them
/// off the Insights tab, where they would have explained what they needed.
///
/// The app target has no test target, so this is the only place the rule can be
/// held: **a card that is waiting for something the reader can hand it must
/// stay on screen to ask.**
final class CardVisibilityTests: XCTestCase {

    /// Every registered model, evaluated against nothing at all — the state of a
    /// fresh install, and the state this defect lived in.
    private func emptyResults() -> [InsightResult] {
        InsightEngine().models.map {
            $0.evaluate(samples: [], profile: UserHealthProfile(), now: TestClock.now)
        }
    }

    /// **Every card, always — the reader's rule, 2026-08-05:** *"every card
    /// should show, even if it hasn't got data yet."*
    ///
    /// The old rule kept a numberless card off the tab unless it had something
    /// to ask for, on the reasoning that a fresh install would otherwise carry
    /// up to seven dead cards. That reasoning conceded the wrong half: the
    /// problem with a dead card is that it is *dead*, not that it is *there*. A
    /// card that says "connect a wearable and this will score your readiness"
    /// is the app explaining itself to someone who has just installed it.
    ///
    /// So visibility is now unconditional, and the burden moves to the empty
    /// state — which is what the paired test below holds.
    func testEveryCardStaysOnScreenEvenWithNothingAtAll() {
        let hidden = emptyResults().filter { !$0.isWorthShowing }.map(\.id)
        XCTAssertEqual(hidden, [],
                       "these cards vanish on a fresh install, so they can never explain themselves")
    }

    /// The other half, and the one that does the work: a card visible with no
    /// data must lead with something the reader can act on. Found on 2026-08-04
    /// — Nutrition and Metabolism were put back on the tab and both then read
    /// "No data yet", which is visible and still a dead end.
    func testNoCardLeadsWithADeadEnd() {
        let deadEnds = ["No data yet", "Not enough data", "No data", ""]
        for result in emptyResults() {
            XCTAssertFalse(deadEnds.contains(result.headline),
                           "\(result.id) is on the tab with headline \"\(result.headline)\" — the row shows the headline, so this reader has been told nothing they can act on")
        }
    }

    func testCardsWaitingForAnInputStayOnScreenToAskForIt() throws {
        let results = emptyResults()
        // `.substanceImpact` joined on 2026-08-05, found by the reader on the
        // Insights tab: "why is the substance card not showing… every card
        // should show, even if it hasn't got data yet." Its whole input is the
        // reader's own log, so an empty log is exactly when it must be able to
        // ask — and it was the one state in which it could not.
        for id in [InsightID.nutrition, .metabolism, .substanceImpact] {
            let result = try XCTUnwrap(results.first { $0.id == id })
            XCTAssertNil(result.score, "\(id) should have no number with no data")
            XCTAssertTrue(result.isWorthShowing,
                          "\(id) is filtered off the tab on an empty profile, so it can never ask for what it needs")
            XCTAssertFalse(result.explanation.isEmpty,
                           "\(id) is visible but says nothing about what it wants")
        }
    }

    /// **This test used to assert a closed set, and that is how it pinned a live
    /// defect for two days.** It read
    /// `XCTAssertEqual(Set(noisy), [.nutrition, .metabolism, .symptomRadar])` —
    /// so the guard written to stop cards shipping invisible *required*
    /// Substance Impact to be one of them. The list had been populated from what
    /// the build happened to do rather than from the rule it exists to enforce.
    ///
    /// The replacement asserts the rule directly and in the direction that can
    /// still fail usefully: a card that **has** a number is not asking for
    /// anything, so it must not claim to be. Under the reader's 2026-08-05 rule
    /// the other direction — which empty cards invite input — is now "all of
    /// them", and `testEveryCardStaysOnScreenEvenWithNothingAtAll` holds it.
    func testACardWithANumberIsNotAskingForAnything() {
        let scored = InsightEngine().models.map {
            $0.evaluate(samples: SyntheticSeed.samples(days: 120, endingOn: TestClock.now),
                        profile: UserHealthProfile(), now: TestClock.now)
        }
        for result in scored where result.primaryValue != nil {
            XCTAssertFalse(result.invitesInput,
                           "\(result.id) has a value and still invites input, so it will nag a reader who has already given it what it needs")
        }
    }

    /// **Being on the tab is half the job; the other half is asking.**
    ///
    /// The 2026-08-03 fix put Nutrition and Metabolism back on the Insights tab
    /// and the test above proved it. Running the app on 2026-08-04 showed both
    /// of them sitting there reading **"No data yet"** — visible, and still a
    /// dead end, because `notReady` hard-coded that headline for every card and
    /// the row renders the headline rather than the explanation.
    ///
    /// The row is the only text most readers see. A card that invites input and
    /// leads with "No data yet" has told them nothing they could act on, which
    /// is the same defect the visibility fix was for, one layer in.
    func testAnInvitingCardLeadsWithTheAskNotWithNoDataYet() {
        for result in emptyResults() where result.invitesInput {
            XCTAssertNotEqual(result.headline, "No data yet",
                              "\(result.id) invites input but its headline asks for nothing — the row shows the headline, not the explanation")
            XCTAssertFalse(result.headline.isEmpty, "\(result.id) has no headline at all")
        }
    }
}
