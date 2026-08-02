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
        XCTAssertEqual(routes.map(\.inputKind),
                       [.cuffBloodPressure, .substanceEvent, .fileImport, .profileFacts])
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

    /// A dose with no medication has nothing to attach to, and the row says so
    /// rather than disappearing — a missing row and an unbuilt feature look
    /// identical to the reader.
    func testOnlyDosesAreConditional() {
        let conditional = InputKind.allCases.filter { $0.unavailableReason != nil }
        XCTAssertEqual(conditional, [.medicationDose])
    }
}
