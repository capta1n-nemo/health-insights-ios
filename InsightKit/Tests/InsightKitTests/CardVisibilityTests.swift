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

    /// The flag is not a way to make every card permanent: a card with nothing
    /// to ask for and nothing to show still stays off the tab.
    ///
    /// ⚠️ **A closed set is the right shape and it is also how this test pinned
    /// a live defect for two days.** Substance Impact was absent from the list
    /// below, so the assertion did not merely fail to catch the card being
    /// invisible — it *required* it. When adding a card here, the question to
    /// answer is "is there something the reader could hand this card right
    /// now", not "does the current build put it in this set".
    func testTheFlagIsNotSetOnCardsWithNothingToAskFor() {
        let noisy = emptyResults().filter { $0.invitesInput }.map(\.id)
        // The radar joined the list on 2026-08-04: with no data at all its ask
        // is real — wear the watch — and a card that cannot ask ships invisible.
        // `.substanceImpact` joined on 2026-08-05; its ask is the log itself.
        XCTAssertEqual(Set(noisy), [.nutrition, .metabolism, .symptomRadar, .substanceImpact],
                       "only the cards waiting on a reader-supplied log should invite input")
    }

    /// Every card that invites input must also offer a **route** to give it,
    /// which is the difference between asking and nagging. Substance Impact
    /// declares `ContributionRoute.substanceLog`; the defect that hid it was
    /// that the reader could never reach the ask in the first place.
    func testAnInvitingCardOffersARouteToActuallyGiveIt() {
        let inviting = Set(emptyResults().filter(\.invitesInput).map(\.id))
        for model in InsightEngine().models where inviting.contains(model.id) {
            XCTAssertFalse(model.contributions.isEmpty && model.requirements.isEmpty,
                           "\(model.id) invites input but declares no contribution route and no requirement, so there is nothing for the card to open")
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
