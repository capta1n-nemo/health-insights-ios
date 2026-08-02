import XCTest
@testable import InsightKit

/// Body Composition's dial has three routes and the middle one has no input yet.
///
/// The cross-card audit reported the waist-derived Relative Fat Mass route as
/// "dead in this card's scoring path", which read as a wiring bug. It is not:
/// `BodyDimensions` has no input, no storage and no source anywhere in the app,
/// because the LiDAR capture it was designed around is still a roadmap note. So
/// `build` is legitimately nil at the only call site.
///
/// These tests keep the route **working** while it waits, so it is not
/// rediscovered as rotten the day a waist measurement arrives, and pin the
/// preference order the card's own copy promises.
final class BodyCompositionRouteTests: XCTestCase {

    private let age = 40.0
    private let sex = BiologicalSex.male

    private func build(rfm: Double) -> BuildAssessment {
        BuildAssessment(bmi: 30, bmiCategory: "obese", relativeFatMass: rfm,
                        waistToHeight: 0.6, isNonStandardBuild: false,
                        explanation: "test build")
    }

    /// A measured fat fraction beats everything — the whole reason BMI is the
    /// fallback and not the basis.
    func testAMeasuredFatFractionWins() throws {
        let result = try XCTUnwrap(BodyCompositionInsight.score(
            bodyFat: 18, bmi: 30, age: age, sex: sex, build: build(rfm: 40)))
        XCTAssertEqual(result.metric, .bodyFatPercentage)
        let fatOnly = try XCTUnwrap(BodyCompositionInsight.score(
            bodyFat: 18, bmi: nil, age: age, sex: sex))
        XCTAssertEqual(result.value, fatOnly.value, accuracy: 1e-9,
                       "the build must not perturb a measured reading")
    }

    /// **The route that is waiting for an input.** Given a build and no measured
    /// fat, it scores from Relative Fat Mass and reports it as a fat fraction —
    /// not as body mass, because that is the quantity it estimated.
    func testTheBuildRouteWorksWhenItHasAnInput() throws {
        let result = try XCTUnwrap(BodyCompositionInsight.score(
            bodyFat: nil, bmi: 30, age: age, sex: sex, build: build(rfm: 18)))
        XCTAssertEqual(result.metric, .bodyFatPercentage)

        // And it displaces BMI: the same subject scored without the build lands
        // on body mass and a different number.
        let bmiOnly = try XCTUnwrap(BodyCompositionInsight.score(
            bodyFat: nil, bmi: 30, age: age, sex: sex))
        XCTAssertEqual(bmiOnly.metric, .bodyMass)
        XCTAssertNotEqual(result.value, bmiOnly.value, accuracy: 0.5)
    }

    /// A healthy RFM must score better than an unhealthy one, or the route is
    /// wired backwards and nobody would notice until it went live.
    func testTheBuildRouteIsOrientedCorrectly() throws {
        let lean = try XCTUnwrap(BodyCompositionInsight.score(
            bodyFat: nil, bmi: 30, age: age, sex: sex, build: build(rfm: 15)))
        let heavy = try XCTUnwrap(BodyCompositionInsight.score(
            bodyFat: nil, bmi: 30, age: age, sex: sex, build: build(rfm: 38)))
        XCTAssertGreaterThan(lean.value, heavy.value)
    }

    /// Without age and sex there is no healthy band to score against, so the
    /// build route stands down to BMI rather than inventing one.
    func testTheBuildRouteNeedsAgeAndSex() throws {
        let result = try XCTUnwrap(BodyCompositionInsight.score(
            bodyFat: nil, bmi: 30, age: nil, sex: nil, build: build(rfm: 18)))
        XCTAssertEqual(result.metric, .bodyMass, "falls through to BMI")
    }

    /// The documented truth, pinned: with no measured fat and no build, the dial
    /// rests on BMI — which is what the reader's own card does today, and which
    /// is why the confidence drops.
    func testTodaysRealPathIsBMIWhenFatIsMissing() throws {
        let result = try XCTUnwrap(BodyCompositionInsight.score(
            bodyFat: nil, bmi: 32.3, age: age, sex: sex))
        XCTAssertEqual(result.metric, .bodyMass)
        XCTAssertEqual(BodyCompositionInsight.scoreConfidence(
            bodyFat: nil, height: 1.85, profile: UserHealthProfile(), now: TestClock.now),
                       .moderate, "a BMI-only dial must not claim high confidence")
    }
}
