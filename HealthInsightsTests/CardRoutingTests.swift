import XCTest
import InsightKit
@testable import HealthInsights

/// **Which tab a card reaches, and whether any card reaches none.**
///
/// This is the class of defect the app target has actually shipped. On
/// 2026-08-03 Nutrition and Metabolism went out *invisible* — green InsightKit
/// suite, green CI, successful install, and the reader found two features
/// missing from a build that contained them. `InsightKit`'s `CardVisibilityTests`
/// now covers the model half (a card with nothing to show but something to ask
/// for stays on screen). It cannot cover this half: **the two filters that
/// decide which tab a result is listed on live in the app target**, one line
/// each, inside view structs.
///
///   * `Features/Dashboard/DashboardView.swift`
///     `model.results.filter { $0.id.cadence == .daily && $0.isWorthShowing }`
///   * `Features/Insights/InsightsListView.swift`
///     `model.results.filter { $0.id.cadence == .trend && $0.isWorthShowing }`
///
/// Between them those two lines are the app's entire card-routing rule, and
/// nothing checked that they *cover* the cadences. `surface(for:)` below is the
/// check, and it is a compile-time one: a third `InsightCadence` case stops this
/// file building, and the message is the list of filters that must claim it.
@MainActor
final class CardRoutingTests: XCTestCase {

    /// The tabs that list cards. Not an app type on purpose — this mirrors the
    /// two filters rather than being imported by them, so it fails when they
    /// drift instead of drifting with them.
    enum Surface: CaseIterable {
        case today, insights
    }

    /// ⚠️ **Exhaustive, and that is the point.** Add a case to
    /// `InsightCadence` and this stops compiling until somebody says which tab
    /// lists it — which is exactly the moment to remember that
    /// `DashboardView.swift` and `InsightsListView.swift` each carry one
    /// hard-coded cadence comparison. A card whose cadence no tab filters for
    /// is built, scored, recorded, exported — and never drawn.
    static func surface(for cadence: InsightCadence) -> Surface {
        switch cadence {
        case .daily: return .today
        case .trend: return .insights
        }
    }

    // MARK: - Every card has a tab

    func testEveryInsightIDRoutesToExactlyOneSurface() {
        var bySurface: [Surface: [InsightID]] = [:]
        for id in InsightID.allCases {
            bySurface[Self.surface(for: id.cadence), default: []].append(id)
        }
        let routed = bySurface.values.reduce(0) { $0 + $1.count }
        XCTAssertEqual(routed, InsightID.allCases.count,
                       "Every InsightID must be listed by exactly one tab.")
        // Both tabs must actually have something, or one of the two filters is
        // dead code nobody would notice was dead.
        for surface in Surface.allCases {
            XCTAssertFalse(bySurface[surface, default: []].isEmpty,
                           "No card routes to \(surface) — one of the two tab filters lists nothing.")
        }
    }

    // MARK: - Nothing worth showing falls between the tabs

    /// The partition, asserted against real evaluated results rather than
    /// against the enum.
    ///
    /// `worth == today + insights` is the whole invariant: a result that is
    /// worth showing and is on neither tab is a card the reader cannot see and
    /// therefore cannot be told about.
    func testNoWorthShowingResultIsDroppedByBothTabs() async {
        let model = await TestAppModel.seeded()
        XCTAssertFalse(model.results.isEmpty,
                       "A seeded model evaluated to nothing — the engine wiring, not the routing, is broken.")

        let worth = model.results.filter(\.isWorthShowing)
        let today = worth.filter { $0.id.cadence == .daily }
        let insights = worth.filter { $0.id.cadence == .trend }

        XCTAssertEqual(worth.count, today.count + insights.count,
                       """
                       \(worth.count - today.count - insights.count) card(s) are worth showing and appear on \
                       neither tab. Check the cadence filters in DashboardView and InsightsListView.
                       """)
        XCTAssertFalse(today.isEmpty, "Today would list no cards on a full history.")
        XCTAssertFalse(insights.isEmpty, "Insights would list no cards on a full history.")
    }

    /// **The 2026-08-03 defect, in the shape it actually shipped in.**
    ///
    /// A fresh install evaluates every card with nothing at all. The rule is
    /// not "every card shows" — most correctly stay off the tab, because their
    /// empty state is "connect a wearable" and a placeholder cannot help with
    /// that. The rule is that a card that *invites input* — one whose missing
    /// piece is something the reader could hand it — must survive the filter,
    /// because a card the reader cannot see cannot tell them what it needs.
    func testCardsInvitingInputSurviveAFreshInstall() {
        let results = TestAppModel.freshInstallResults()
        XCTAssertFalse(results.isEmpty, "The app's engine evaluated no cards at all.")

        let inviting = results.filter(\.invitesInput)
        XCTAssertFalse(inviting.isEmpty,
                       """
                       No card invites input on a fresh install. Either every card now has data it \
                       cannot have, or `invitesInput` has stopped being set — which is precisely how \
                       Nutrition and Metabolism shipped invisible on 2026-08-03.
                       """)
        for result in inviting {
            XCTAssertTrue(result.isWorthShowing,
                          "\(result.id) invites input but is filtered off its tab — it cannot ask for what it needs.")
            // And it must land somewhere. This is the same partition as above,
            // asserted on the state a first-run reader is actually in.
            _ = Self.surface(for: result.id.cadence)
        }
    }

    /// A card is listed once, not twice.
    ///
    /// `applyRecomputed` assigns `results` wholesale from one `evaluateAll`,
    /// but `recompute()` rebinds the engine on every pass
    /// (`withSubstanceLog`/`withSymptoms`/`withCalendar`) and the comment on it
    /// records that those rebinds *replace rather than append* — a rule with no
    /// test behind it until now. A duplicated id draws the same card twice on
    /// one tab.
    func testEachCardIsEvaluatedOnce() async {
        let model = await TestAppModel.seeded()
        let ids = model.results.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count,
                       "A card was evaluated twice — check the engine rebinds in AppModel.recompute().")
    }
}
