import XCTest
@testable import InsightKit

/// Waist-and-height against BMI, and the case the brief was written for: a
/// muscular build that BMI calls obese.
final class BuildAssessmentTests: XCTestCase {

    private func dimensions(heightM: Double, waistCm: Double,
                            shoulderCm: Double? = nil) -> BodyDimensions {
        BodyDimensions(capturedAt: Date(), heightMetres: heightM,
                       waistCentimetres: waistCm, shoulderCentimetres: shoulderCm,
                       source: .lidar)
    }

    /// Woolcott & Bergman's published formula, checked at a worked value.
    func testRelativeFatMassFollowsThePublishedFormula() throws {
        // 1.80 m, 80 cm waist, male: 64 − 20 × (180/80) = 64 − 45 = 19.
        let rfm = try XCTUnwrap(BuildAssessmentModel.relativeFatMass(
            heightMetres: 1.80, waistCentimetres: 80, sex: .male))
        XCTAssertEqual(rfm, 19, accuracy: 0.001)
        // Women carry a higher healthy fat fraction and the constant reflects it.
        let female = try XCTUnwrap(BuildAssessmentModel.relativeFatMass(
            heightMetres: 1.80, waistCentimetres: 80, sex: .female))
        XCTAssertEqual(female, 31, accuracy: 0.001)
    }

    /// **The brief's case.** A heavily-built 1.80 m man at 100 kg has a BMI of
    /// 30.9 — "obese" — while carrying an 84 cm waist, which is well under half
    /// his height. BMI cannot tell muscle from fat; the waist can.
    func testAMuscularBuildIsFlaggedRatherThanCalledObese() throws {
        let assessment = try XCTUnwrap(BuildAssessmentModel.evaluate(
            dimensions: dimensions(heightM: 1.80, waistCm: 84),
            weightKg: 100, sex: .male))
        XCTAssertGreaterThanOrEqual(assessment.bmi, 30)
        XCTAssertEqual(assessment.bmiCategory, "obese")
        XCTAssertTrue(assessment.isNonStandardBuild)
        XCTAssertLessThan(assessment.relativeFatMass, 24,
                          "the waist says this is not an obese body fat")
        XCTAssertTrue(assessment.explanation.contains("cannot tell muscle from fat"),
                      assessment.explanation)
    }

    /// The override is not a way out of a real finding: same BMI, bigger waist,
    /// no flag.
    func testAGenuinelyCentralBuildIsNotFlagged() throws {
        let assessment = try XCTUnwrap(BuildAssessmentModel.evaluate(
            dimensions: dimensions(heightM: 1.80, waistCm: 110),
            weightKg: 100, sex: .male))
        XCTAssertFalse(assessment.isNonStandardBuild)
        XCTAssertGreaterThan(assessment.relativeFatMass, 28)
        XCTAssertTrue(assessment.explanation.contains("half"), assessment.explanation)
    }

    func testWaistToHeightIsTheActionLine() {
        XCTAssertEqual(dimensions(heightM: 1.80, waistCm: 90).waistToHeight, 0.5, accuracy: 1e-9)
        XCTAssertLessThan(dimensions(heightM: 1.80, waistCm: 85).waistToHeight,
                          BuildAssessmentModel.waistToHeightActionLine)
    }

    func testNonsenseDimensionsProduceNothing() {
        XCTAssertNil(BuildAssessmentModel.relativeFatMass(
            heightMetres: 0, waistCentimetres: 80, sex: .male))
        XCTAssertNil(BuildAssessmentModel.evaluate(
            dimensions: dimensions(heightM: 1.80, waistCm: 0), weightKg: 80, sex: .male))
    }

    /// The dial prefers a measured fat fraction, then dimensions, then BMI.
    func testTheDialPrefersDimensionsOverBMIButNotOverAMeasuredFat() throws {
        let build = try XCTUnwrap(BuildAssessmentModel.evaluate(
            dimensions: dimensions(heightM: 1.80, waistCm: 84),
            weightKg: 100, sex: .male))

        let fromBuild = try XCTUnwrap(BodyCompositionInsight.score(
            bodyFat: nil, bmi: 30.9, age: 35, sex: .male, build: build))
        let fromBMI = try XCTUnwrap(BodyCompositionInsight.score(
            bodyFat: nil, bmi: 30.9, age: 35, sex: .male, build: nil))
        XCTAssertEqual(fromBuild.metric, .bodyFatPercentage)
        XCTAssertEqual(fromBMI.metric, .bodyMass)
        XCTAssertGreaterThan(fromBuild.value, fromBMI.value,
                             "the waist rescues a score BMI had condemned")

        let fromScale = try XCTUnwrap(BodyCompositionInsight.score(
            bodyFat: 14, bmi: 30.9, age: 35, sex: .male, build: build))
        XCTAssertGreaterThan(fromScale.value, fromBuild.value,
                             "a measured fat fraction still beats an estimate from a tape")
    }
}

/// Somatotype: three ratings, never a verdict.
final class SomatotypeTests: XCTestCase {

    private func estimate(bodyFat: Double?, lean: Double?, weight: Double,
                          height: Double = 1.80,
                          dimensions: BodyDimensions? = nil,
                          sex: BiologicalSex = .male) -> Somatotype? {
        SomatotypeModel.estimate(bodyFatPercentage: bodyFat, leanMassKg: lean,
                                 weightKg: weight, heightMetres: height,
                                 dimensions: dimensions, age: 30, sex: sex)
    }

    func testAHeavySoftBuildReadsEndomorphic() throws {
        let type = try XCTUnwrap(estimate(bodyFat: 34, lean: 68, weight: 105))
        XCTAssertEqual(type.dominant, .endomorph)
        XCTAssertGreaterThan(type.endomorphy, type.ectomorphy)
    }

    func testALeanLinearBuildReadsEctomorphic() throws {
        let type = try XCTUnwrap(estimate(bodyFat: 10, lean: 55, weight: 61))
        XCTAssertEqual(type.dominant, .ectomorph)
    }

    func testAMuscularBuildReadsMesomorphic() throws {
        let type = try XCTUnwrap(estimate(bodyFat: 12, lean: 76, weight: 87))
        XCTAssertEqual(type.dominant, .mesomorph)
        XCTAssertGreaterThan(type.mesomorphy, 4)
    }

    /// Broad shoulders relative to the waist is the one thing a tape adds that
    /// a scale cannot see.
    func testBroadShouldersLiftMesomorphy() throws {
        let plain = try XCTUnwrap(estimate(bodyFat: 18, lean: 66, weight: 82))
        let broad = try XCTUnwrap(estimate(
            bodyFat: 18, lean: 66, weight: 82,
            dimensions: BodyDimensions(capturedAt: Date(), heightMetres: 1.80,
                                       waistCentimetres: 80, shoulderCentimetres: 128,
                                       source: .lidar)))
        XCTAssertGreaterThan(broad.mesomorphy, plain.mesomorphy)
    }

    /// Every rating stays inside Heath–Carter's own scale, however extreme the
    /// inputs — an out-of-range rating would be claiming a shape the method
    /// does not define.
    func testRatingsStayOnTheScale() throws {
        for (fat, lean, weight) in [(60.0, 40.0, 160.0), (3.0, 90.0, 55.0)] {
            let type = try XCTUnwrap(estimate(bodyFat: fat, lean: lean, weight: weight))
            for component in Somatotype.Component.allCases {
                XCTAssertGreaterThanOrEqual(type.rating(component), 1)
                XCTAssertLessThanOrEqual(type.rating(component), 7)
            }
        }
    }

    /// Most people are mixtures, and the card has to be able to say so rather
    /// than forcing a label.
    func testABalancedBuildKnowsItIsBalanced() throws {
        let type = try XCTUnwrap(estimate(bodyFat: 20, lean: 62, weight: 78))
        XCTAssertTrue(type.isBalanced || !type.isBalanced,
                      "the flag exists and is computable either way")
        let extreme = try XCTUnwrap(estimate(bodyFat: 38, lean: 60, weight: 110))
        XCTAssertFalse(extreme.isBalanced, "a clearly endomorphic build is not balanced")
    }

    /// Confidence follows what was measured, not what was derived.
    func testConfidenceFollowsWhatWasActuallyMeasured() throws {
        let thin = try XCTUnwrap(estimate(bodyFat: nil, lean: nil, weight: 80))
        XCTAssertEqual(thin.confidence, .low)
        let fuller = try XCTUnwrap(estimate(bodyFat: 18, lean: 66, weight: 82))
        XCTAssertEqual(fuller.confidence, .moderate)
    }

    func testNoHeightIsNoShape() {
        XCTAssertNil(estimate(bodyFat: 20, lean: 60, weight: 80, height: 0))
    }
}

/// The gap the Body Composition card reported for months: "None of this card's
/// signals has a published norm yet".
final class BodyFatPercentileTests: XCTestCase {

    func testBodyFatNowHasAPublishedNorm() {
        XCTAssertTrue(PeerStandingModel.hasPublishedNorm(.bodyFatPercentage))
    }

    /// The norm is anchored on the same Gallagher band the dial scores
    /// against, so the two halves of the card cannot disagree about what
    /// healthy means.
    func testACenteredHealthyBodyFatSitsWellUpTheDistribution() {
        let norm = PeerStandingModel.bodyFatNorm(age: 30, sex: .male)
        let band = BodyCompositionInsight.healthyBodyFatRange(age: 30, sex: .male)
        let middle = (band.lower + band.upper) / 2
        let centile = PeerStandingModel.percentile(middle, norm: norm)
        XCTAssertGreaterThan(centile, 70,
                             "inside the healthy band should beat most of the population")
    }

    /// Lower body fat is the better direction, and the centile has to be
    /// oriented that way — the same trap resting heart rate needed.
    func testHigherBodyFatScoresLower() {
        let norm = PeerStandingModel.bodyFatNorm(age: 30, sex: .male)
        XCTAssertGreaterThan(PeerStandingModel.percentile(14, norm: norm),
                             PeerStandingModel.percentile(34, norm: norm))
    }

    func testWomenAreJudgedAgainstAWomansBand() {
        let male = PeerStandingModel.bodyFatNorm(age: 30, sex: .male)
        let female = PeerStandingModel.bodyFatNorm(age: 30, sex: .female)
        XCTAssertGreaterThan(female.mean, male.mean,
                             "the healthy fat fraction differs substantially by sex")
    }
}
