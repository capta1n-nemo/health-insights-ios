import XCTest
@testable import InsightKit

/// The reader, 2026-08-05: *"Provide scoring, based on info from Apple health
/// which should mandate this during setup, but if we don't have it, require them
/// to give it."*
///
/// The eleven micronutrients were promoted the same day with `referenceRange`
/// nil for all of them, because a reference range is a fixed band with no reader
/// in scope and almost every published figure here moves with sex, several with
/// age, and iron by more than twofold. The profile is in scope here, so the band
/// can be right — and the requirement is what makes sure the profile exists.
final class MicronutrientTargetTests: XCTestCase {

    /// **Iron is the case that justifies the whole design.** 18 mg against 8 is
    /// more than twofold, and a single band would tell one of the two that they
    /// are fine when they are deficient.
    func testIronDiffersByMoreThanTwofoldBySex() throws {
        let woman = try XCTUnwrap(MicronutrientTargets.target(for: .dietaryIron, sex: .female, age: 30))
        let man = try XCTUnwrap(MicronutrientTargets.target(for: .dietaryIron, sex: .male, age: 30))
        XCTAssertEqual(woman.recommended, 18)
        XCTAssertEqual(man.recommended, 8)
        XCTAssertGreaterThan(woman.recommended / man.recommended, 2)
    }

    /// And by age within one sex, which is why age is required too.
    func testIronFallsAfterFifty() throws {
        let younger = try XCTUnwrap(MicronutrientTargets.target(for: .dietaryIron, sex: .female, age: 30))
        let older = try XCTUnwrap(MicronutrientTargets.target(for: .dietaryIron, sex: .female, age: 60))
        XCTAssertGreaterThan(younger.recommended, older.recommended)
    }

    /// **Silence rather than the young-adult row.** Quietly defaulting an
    /// unknown age would score a reader of seventy against a figure that is not
    /// theirs, which is the failure this whole mechanism exists to avoid.
    func testAMissingAgeGivesNoTargetWhereAgeMatters() {
        XCTAssertNil(MicronutrientTargets.target(for: .dietaryIron, sex: .female, age: nil))
        XCTAssertNil(MicronutrientTargets.target(for: .dietaryCalcium, sex: .male, age: nil))
        // Vitamin C does not vary with age, so it survives without one.
        XCTAssertNotNil(MicronutrientTargets.target(for: .dietaryVitaminC, sex: .male, age: nil))
    }

    func testAMissingSexGivesNoTargetAtAll() {
        for metric in MicronutrientTargets.targetable {
            XCTAssertNil(MicronutrientTargets.target(for: metric, sex: nil, age: 40),
                         "\(metric) produced a target with no sex to resolve it against")
        }
    }

    /// **A floor and a ceiling are different quantities from different
    /// evidence.** Treating them as the ends of one band is the classic error,
    /// and for several of these the ceiling is the figure that matters.
    func testTheUpperLimitIsAboveTheRecommendedAndSeparateFromIt() throws {
        for metric in MicronutrientTargets.targetable {
            guard let t = MicronutrientTargets.target(for: metric, sex: .female, age: 40),
                  let ceiling = t.upperLimit else { continue }
            XCTAssertGreaterThan(ceiling, t.recommended,
                                 "\(metric)'s upper limit is not above its recommended intake")
        }
    }

    func testStandingReportsBelowMetAndOverTheCeiling() {
        // Vitamin C: 75 mg recommended for a woman, 2,000 mg ceiling.
        XCTAssertEqual(MicronutrientTargets.standing(50, for: .dietaryVitaminC, sex: .female, age: 40), .below)
        XCTAssertEqual(MicronutrientTargets.standing(80, for: .dietaryVitaminC, sex: .female, age: 40), .met)
        XCTAssertEqual(MicronutrientTargets.standing(2_500, for: .dietaryVitaminC, sex: .female, age: 40), .aboveUpperLimit)
    }

    /// A metric with no ceiling can never be reported as over one.
    func testAMetricWithNoCeilingIsNeverOverIt() {
        XCTAssertEqual(MicronutrientTargets.standing(10_000, for: .dietaryVitaminB12, sex: .male, age: 40), .met)
        XCTAssertEqual(MicronutrientTargets.standing(5_000, for: .dietaryMagnesium, sex: .male, age: 40), .met)
    }

    /// **Dietary cholesterol carries no target on purpose.** Its numeric limit
    /// was removed from the US Dietary Guidelines in 2015; drawing the retired
    /// 300 mg line would be quoting a figure its own authors withdrew.
    func testWithdrawnAndAbsentFiguresAreNotInvented() {
        for metric in [MetricType.dietaryCholesterol, .dietaryMonounsaturatedFat,
                       .dietaryPolyunsaturatedFat] {
            XCTAssertNil(MicronutrientTargets.target(for: metric, sex: .male, age: 40),
                         "\(metric) was given a target nobody publishes")
        }
    }

    /// Every figure names where it came from — a number a reader cannot trace is
    /// one they have to take on faith.
    func testEveryTargetNamesItsSource() throws {
        for metric in MicronutrientTargets.targetable {
            let t = try XCTUnwrap(MicronutrientTargets.target(for: metric, sex: .male, age: 40))
            XCTAssertTrue(t.provenance.contains("Institute of Medicine"), "\(metric): \(t.provenance)")
        }
    }

    // MARK: - The requirement that makes the profile exist

    /// Both facts are mandatory now, and each reports itself: the old rule hid
    /// the date-of-birth ask entirely for anyone who had already set a sex.
    func testBothProfileFactsAreRequiredAndReportSeparately() {
        let empty = NutritionInsight().evaluate(samples: [], profile: UserHealthProfile(),
                                                now: TestClock.now)
        let kinds = Set(empty.unmetRequirements.map(\.kind))
        XCTAssertTrue(kinds.contains(.biologicalSex))
        XCTAssertTrue(kinds.contains(.dateOfBirth))
        XCTAssertTrue(NutritionInsight().requirements.allSatisfy(\.isMandatory),
                      "the reader asked for these to be required, not offered")
    }
}
