import XCTest
@testable import InsightKit

/// The master input list's guarantees.
///
/// `InputKind` exists so the app's four input surfaces cannot drift apart
/// again. The switches hold that in the app target; these hold the parts a
/// switch cannot — that every case says something useful, that the groups
/// partition the list rather than losing a case, and that no model can ask for
/// a fact the reader has no way to enter.
final class InputKindTests: XCTestCase {

    func testEveryInputSaysWhatItIsAndWhatItIsFor() {
        for kind in InputKind.allCases {
            XCTAssertFalse(kind.title.isEmpty, "\(kind) has no title")
            XCTAssertFalse(kind.symbolName.isEmpty, "\(kind) has no symbol")
            // Twenty is arbitrary but a placeholder never clears it, and a row
            // whose explanation is "Add" tells the reader nothing.
            XCTAssertGreaterThan(kind.detail.count, 20,
                                 "\(kind) needs a real explanation, not a label")
        }
    }

    /// The groups must *partition* the list. A case belonging to no group is
    /// one the master screen silently drops, which is the failure this whole
    /// type exists to prevent — and it would look exactly like the input never
    /// having been built.
    func testGroupsCoverEveryInputExactlyOnce() {
        let grouped = InputGroup.allCases.flatMap(\.kinds)
        XCTAssertEqual(Set(grouped), Set(InputKind.allCases))
        XCTAssertEqual(grouped.count, InputKind.allCases.count,
                       "a kind appears under more than one heading")
    }

    func testEveryGroupIsUsed() {
        for group in InputGroup.allCases {
            XCTAssertFalse(group.kinds.isEmpty,
                           "\(group) is a heading with nothing under it")
            XCTAssertFalse(group.title.isEmpty)
        }
    }

    /// Every card route lands somewhere in the master list. The mapping is an
    /// exhaustive switch, so this cannot fail by omission — what it pins is
    /// that the two lists mean the same things by the same names.
    func testCardRoutesMapToTheMasterList() {
        let routes: [ContributionRoute] = [
            .bloodPressureReadings, .substanceLog, .fileImport,
            .groundingFacts([.dateOfBirth])
        ]
        XCTAssertEqual(routes.map(\.inputKinds),
                       [[.cuffBloodPressure], [.substanceEvent],
                        [.fileImport], [.profileFacts]])
    }

    /// **The one that would have caught the reported bug.** `weightGoal`
    /// shipped, Body Composition required it, and Settings' hand-written array
    /// of nine kinds did not include it — so the app asked for a fact it gave
    /// no way to set. Any grounding kind must be reachable: either it has its
    /// own row, or it arrives as part of another input.
    func testEveryGroundingFactIsReachableFromSomeInput() {
        // The only fact entered as part of another: diastolic arrives with
        // systolic, because a cuff reading is one event with two numbers.
        let arrivesWithAnother: Set<GroundingKind> = [.cuffDiastolic]
        let reachable = Set(GroundingKind.directlyEntered).union(arrivesWithAnother)
        XCTAssertEqual(reachable, Set(GroundingKind.allCases),
                       "no way to enter: \(Set(GroundingKind.allCases).subtracting(reachable))")
    }

    /// And the same claim from the models' side: nothing an insight requires
    /// may be un-enterable.
    func testNoShippedModelRequiresAnUnreachableFact() {
        let required = Set(InsightEngine().models.flatMap { $0.requirements.map(\.kind) })
        let reachable = Set(GroundingKind.directlyEntered).union([.cuffDiastolic])
        XCTAssertTrue(required.isSubset(of: reachable),
                      "required but not enterable: \(required.subtracting(reachable))")
    }

    func testWeightGoalIsEnterable() {
        XCTAssertTrue(GroundingKind.weightGoal.isEnteredDirectly)
        XCTAssertTrue(GroundingKind.directlyEntered.contains(.weightGoal))
    }

    // MARK: - The rule: if a card takes it, the card must say so

    /// **The check the user asked for.**
    ///
    /// *"Make a check to ensure that if manual input is allowed on a card, it
    /// must be in the View and add sub menu of the card."* Every input that
    /// declares `mustBeOfferedOnACard` has to be reachable from some shipped
    /// model's `contributions` — which is what fills "View & add".
    ///
    /// It exists because the rule was broken silently: Body Composition offered
    /// a body-type override inside a chart and a dose button inside the
    /// medication section, and its "View & add" mentioned neither. Nothing
    /// failed; the card just quietly stopped being the one place that says what
    /// it wants from you.
    func testEveryInputACardTakesIsOfferedByThatCardsViewAndAdd() {
        let offered = Set(InsightEngine().models
            .flatMap(\.contributions)
            .flatMap(\.inputKinds))
        let required = Set(InputKind.allCases.filter(\.mustBeOfferedOnACard))
        XCTAssertTrue(required.isSubset(of: offered),
                      "offered nowhere on a card: \(required.subtracting(offered))")
    }

    /// The other direction: a route may not offer an input that has declared
    /// itself Settings-only. Two places claiming the same input is how one of
    /// them gets forgotten.
    func testSettingsOnlyInputsAreNotAlsoOnACard() {
        let offered = Set(InsightEngine().models
            .flatMap(\.contributions).flatMap(\.inputKinds))
        for kind in InputKind.allCases where !kind.mustBeOfferedOnACard {
            XCTAssertFalse(offered.contains(kind),
                           "\(kind) says Settings-only but a card offers it")
        }
    }

    /// Every route earns its place: no route may map to nothing.
    func testEveryRouteOffersAtLeastOneInput() {
        let routes: [ContributionRoute] = [
            .bloodPressureReadings, .substanceLog, .fileImport,
            .medication, .bodyType, .groundingFacts([.dateOfBirth])
        ]
        for route in routes {
            XCTAssertFalse(route.inputKinds.isEmpty, "\(route) offers nothing")
        }
        // Medication is the one route that stands for more than one input —
        // regimen, doses and side effects are one conversation, and three
        // near-identical buttons on one card would be worse than one.
        XCTAssertEqual(Set(ContributionRoute.medication.inputKinds),
                       [.medicationRegimen, .medicationDose, .sideEffect])
    }

    /// Body Composition is the card that was wrong, so it gets named.
    func testBodyCompositionOffersEverythingItTakes() {
        let kinds = Set(BodyCompositionInsight().contributions.flatMap(\.inputKinds))
        XCTAssertTrue(kinds.contains(.bodyType), "the build override")
        XCTAssertTrue(kinds.contains(.medicationRegimen), "the regimen")
        XCTAssertTrue(kinds.contains(.medicationDose), "logging a dose")
        XCTAssertTrue(kinds.contains(.fileImport), "the Shotsy file")
        XCTAssertTrue(kinds.contains(.profileFacts), "the grounding facts")
    }

    /// A dose with no medication has nothing to attach to, and the row says so
    /// rather than disappearing — a missing row and an unbuilt feature look
    /// identical to the reader.
    func testOnlyDosesAreConditional() {
        let conditional = InputKind.allCases.filter { $0.unavailableReason != nil }
        XCTAssertEqual(conditional, [.medicationDose])
    }
}

/// The fourth and fifth clauses of the rule: a never-used input becomes a
/// dismissible row in "Improve your health", which is what puts it on Today.
final class UnusedInputSuggestionTests: XCTestCase {

    func testAnInputNeverUsedIsSuggested() {
        let suggestions = SuggestionEngine.unusedInputs(used: [])
        let prompted = Set(suggestions.map(\.id))
        for kind in InputKind.allCases where kind.promptsWhenNeverUsed {
            XCTAssertTrue(prompted.contains("input-\(kind.rawValue)"),
                          "\(kind) prompts when never used, but produced no row")
        }
    }

    func testUsingItStopsTheSuggestion() {
        let all = Set(InputKind.allCases)
        XCTAssertTrue(SuggestionEngine.unusedInputs(used: all).isEmpty)
    }

    /// The id has to be stable per input, because dismissal is keyed on it —
    /// and it has to *stop being emitted* once used, because that is what
    /// clears the dismissal rather than leaving it to shadow a future prompt.
    func testTheIdIsStablePerInput() {
        let first = SuggestionEngine.unusedInputs(used: [])
        let second = SuggestionEngine.unusedInputs(used: [])
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(Set(first.map(\.id)).count, first.count, "ids collide")
    }

    /// Weaker than a grounding fact that is costing a card its score. "Here is
    /// a feature you have not tried" must never outrank "this card cannot
    /// produce a number without it".
    func testItRanksBelowARealGroundingGap() {
        let feature = SuggestionEngine.unusedInputs(used: []).first
        XCTAssertNotNil(feature)
        XCTAssertEqual(feature?.basis, .unlockAnInsight)
        XCTAssertLessThan(feature?.strength ?? 1, 0.2)
    }

    /// Nobody is asked to have a side effect, and nobody is asked twice for the
    /// facts `unlocks` already prompts for by name.
    func testTheQuietInputsStayQuiet() {
        let prompted = Set(SuggestionEngine.unusedInputs(used: []).map(\.id))
        for kind in [InputKind.sideEffect, .profileFacts, .cuffBloodPressure,
                     .medicationDose, .bodyType, .bloodTestPhoto] {
            XCTAssertFalse(prompted.contains("input-\(kind.rawValue)"),
                           "\(kind) should not nag")
        }
    }
}
