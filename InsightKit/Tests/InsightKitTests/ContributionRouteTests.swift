import XCTest
@testable import InsightKit

/// What each card lets the user view and add.
///
/// These live here rather than being checked by eye because the app target has
/// no test target, and because the failure mode is silent: a model whose route
/// is wrong renders a "View & add" section offering the wrong thing, or an empty
/// one, and nothing complains.
final class ContributionRouteTests: XCTestCase {

    private let engine = InsightEngine()

    private func model(_ id: InsightID) -> any InsightModel {
        guard let found = engine.models.first(where: { $0.id == id }) else {
            fatalError("\(id) is not registered in InsightEngine")
        }
        return found
    }

    // MARK: - The derived default

    /// Every model that asks for grounding facts offers exactly those facts, in
    /// the order it declared them. This is the whole point of deriving the route
    /// rather than switching on `InsightID`: the two lists cannot drift.
    ///
    /// **The invariant is the *contents* of the grounding route, not the number
    /// of routes.** It asserted "exactly one" until 2026-08-02, which was an
    /// incidental truth rather than the rule — Body Composition now also offers
    /// a file import, because the user's rule is that every input type appears
    /// in "View & add", and a card can want more than one kind of thing from
    /// you. What must never drift is a grounding route that names facts the
    /// model does not actually require.
    func testGroundingFactsAreDerivedFromTheModelsOwnRequirements() {
        for model in engine.models where !model.requirements.isEmpty {
            // The log-backed model deliberately doesn't follow the default.
            if model.id == .bloodPressure { continue }

            let grounding = model.contributions.compactMap { route -> [GroundingKind]? in
                guard case .groundingFacts(let kinds) = route else { return nil }
                return kinds
            }
            XCTAssertEqual(grounding.count, 1,
                           "\(model.id) should offer exactly one grounding route")
            XCTAssertEqual(grounding.first, model.requirements.map(\.kind),
                           "\(model.id)'s route must name its own requirements")
        }
    }

    /// A route the reader can reach must be one the section knows how to draw.
    /// `ViewAndAddSection` switches exhaustively over these, so a new case is a
    /// compile error there — this pins the other half, that every case a model
    /// actually offers is one somebody chose to offer.
    func testEveryOfferedRouteIsDeliberate() {
        for model in engine.models {
            for route in model.contributions {
                switch route {
                case .groundingFacts(let kinds):
                    XCTAssertFalse(kinds.isEmpty,
                                   "\(model.id) offers an empty grounding route")
                case .bloodPressureReadings, .substanceLog, .fileImport,
                     .medication, .bodyType, .bodyMeasurements, .screenTime,
                     .symptomLog, .readerIdentity:
                    continue
                }
            }
        }
    }

    /// A model with nothing to ask for offers nothing — no empty section.
    ///
    /// `.sleep` joined the overriders on 2026-08-02: it declares no standing
    /// facts but does take **screen time**, which Apple's sandbox means no app
    /// can read for itself, and which is the only way the onset deep-dive can
    /// answer "is it tech time?".
    func testModelsWithoutRequirementsOfferNothingUnlessTheyOverride() {
        // `.symptomRadar` joined 2026-08-04: no grounding facts, but it offers
        // the symptom-tag route it grades itself against. `.workImpact` joined
        // with B7 H1: no grounding facts, but it offers the identity route that
        // decides whose OOO block a working day contains.
        let overriders: Set<InsightID> = [.substanceImpact, .sleep, .symptomRadar,
                                          .workImpact]
        for model in engine.models
        where model.requirements.isEmpty && !overriders.contains(model.id) {
            XCTAssertTrue(model.contributions.isEmpty,
                          "\(model.id) has no requirements and no log, so it should offer no route")
        }
    }

    // MARK: - The two overrides

    /// Blood pressure takes a dated series, not two profile facts. Without the
    /// override the default would read its `requirements` and offer
    /// `.cuffSystolic` / `.cuffDiastolic` as standing facts — one latest number
    /// where the model wants a log, and no calibration progress.
    func testBloodPressureOffersItsLogRatherThanTwoStandingFacts() {
        XCTAssertEqual(model(.bloodPressure).contributions, [.bloodPressureReadings])
    }

    /// Substance Impact's only input is the log, and it declares no
    /// requirements — so the derived default would leave the one card that is
    /// entirely user-entered with no way to enter anything.
    func testSubstanceImpactOffersItsLogDespiteHavingNoRequirements() {
        let substance = model(.substanceImpact)
        XCTAssertTrue(substance.requirements.isEmpty)
        XCTAssertEqual(substance.contributions, [.substanceLog])
    }

    /// The radar's route is deliberate too — and deliberately the first with
    /// no `InputKind` behind it: the tags are made in Apple Health, so the
    /// section views and guides rather than opening a sheet. Do not "fix" the
    /// empty mapping by inventing an in-app symptom sheet.
    func testTheSymptomRadarOffersTheTagRouteItGradesItselfAgainst() {
        let radarModel = model(.symptomRadar)
        XCTAssertTrue(radarModel.requirements.isEmpty)
        XCTAssertEqual(radarModel.contributions, [.symptomLog])
        XCTAssertEqual(ContributionRoute.symptomLog.inputKinds, [])
    }

    /// Work impact offers identity (B7 H1) — the input that decides whose OOO
    /// block a working day contains. Travel drain deliberately does not: its
    /// model reads time-zone changes and no classifications, and a card
    /// offering an input its model ignores would be claiming a sensitivity it
    /// does not have.
    func testWorkImpactOffersIdentityAndTravelDrainDoesNot() {
        XCTAssertEqual(model(.workImpact).contributions, [.readerIdentity])
        XCTAssertTrue(model(.travelDrain).contributions.isEmpty)
        XCTAssertEqual(ContributionRoute.readerIdentity.inputKinds, [.readerIdentity])
    }

    // MARK: - Dispatch

    /// The overrides must actually run through `any InsightModel`.
    ///
    /// `contributions` is a protocol *requirement* with a default in an
    /// extension. Had it been declared only in the extension, this call would
    /// dispatch statically to the default and both overrides above would be
    /// dead code that still passed their own tests, because those hold the
    /// concrete type.
    func testOverridesSurviveExistentialDispatch() {
        let erased: [any InsightModel] = engine.models
        let bp = erased.first { $0.id == .bloodPressure }
        let substance = erased.first { $0.id == .substanceImpact }
        XCTAssertEqual(bp?.contributions, [.bloodPressureReadings])
        XCTAssertEqual(substance?.contributions, [.substanceLog])
    }

    // MARK: - Canary

    /// A new insight picks the default up with no edit — which is the reason
    /// this is derived rather than switched. If someone converts
    /// `contributions` into an exhaustive switch over `InsightID` later, this
    /// fails and says why.
    func testANewModelGetsTheDefaultWithoutBeingRegisteredAnywhere() {
        struct Newcomer: InsightModel {
            let id: InsightID = .readiness      // any id; unused here
            let title = "Newcomer"
            var candidateMetrics: [MetricType] { [.restingHeartRate] }
            var requirements: [GroundingRequirement] {
                [.init(kind: .dateOfBirth, isMandatory: true, rationale: "because")]
            }
            func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                          now: Date) -> InsightResult {
                InsightResult(id: id, title: title, primaryValue: nil, headline: "",
                              score: nil, confidence: .low, explanation: "",
                              drivers: [], unmetRequirements: [])
            }
        }
        XCTAssertEqual(Newcomer().contributions, [.groundingFacts([.dateOfBirth])])
    }

    // MARK: - What a tab lists

    private func result(primaryValue: Double?,
                        unmet: [GroundingKind]) -> InsightResult {
        InsightResult(
            id: .readiness, title: "t", primaryValue: primaryValue, headline: "",
            score: nil, confidence: .low, explanation: "", drivers: [],
            unmetRequirements: unmet.map {
                GroundingRequirement(kind: $0, isMandatory: true, rationale: "r")
            })
    }

    /// A card with a number is always worth listing.
    func testACardWithANumberIsShown() {
        XCTAssertTrue(result(primaryValue: 42, unmet: []).isWorthShowing)
    }

    /// A card with no number but something to add is shown, so the placeholder
    /// is reachable from both tabs rather than only from Insights.
    func testACardWithNothingButSomethingToAddIsShown() {
        XCTAssertTrue(result(primaryValue: nil, unmet: [.dateOfBirth]).isWorthShowing)
    }

    /// A card with no number and nothing to add is not — this is what stops a
    /// fresh install filling Today with dead "no data yet" cards, since the
    /// daily insights declare no requirements at all.
    func testACardWithNothingToShowAndNothingToAddIsHidden() {
        XCTAssertFalse(result(primaryValue: nil, unmet: []).isWorthShowing)
    }

    /// Every card that asks the user for something has a way to be asked.
    ///
    /// The gap this closes: Substance Impact's log was reachable only from a
    /// toolbar button on Today, and Body Composition has no entry route at all
    /// (deliberately deferred). This pins the invariant for the models that are
    /// meant to have one.
    func testEveryModelWithRequirementsOffersARoute() {
        for model in engine.models where !model.requirements.isEmpty {
            XCTAssertFalse(model.contributions.isEmpty,
                           "\(model.id) asks for grounding but offers no way to give it")
        }
    }
}
