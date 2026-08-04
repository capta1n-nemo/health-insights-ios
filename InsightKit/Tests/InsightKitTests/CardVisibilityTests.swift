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
        for id in [InsightID.nutrition, .metabolism] {
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
    func testTheFlagIsNotSetOnCardsWithNothingToAskFor() {
        let noisy = emptyResults().filter { $0.invitesInput }.map(\.id)
        XCTAssertEqual(Set(noisy), [.nutrition, .metabolism],
                       "only the cards waiting on a reader-supplied log should invite input")
    }
}
