import XCTest
@testable import InsightKit

/// These assertions pin the implementation to the *published* equations. The
/// expected values are derived from the coefficients in the source papers, so a
/// transcription error (wrong sign, swapped unit, misplaced interaction term)
/// breaks the test.
final class CardiovascularRiskTests: XCTestCase {

    // SCORE2 worked profile: 50-year-old female current smoker, SBP 140,
    // total cholesterol 6.3 mmol/L, HDL 1.4 mmol/L, moderate-risk region.
    // Hand-computed from the 2021 ESC coefficients → ≈ 5.2%.
    func testSCORE2FemaleSmokerModerateRegion() {
        let risk = CardiovascularRiskModel.score2Risk(.init(
            age: 50, sex: .female, isSmoker: true, systolicBP: 140,
            totalCholesterol: 6.3, hdlCholesterol: 1.4, region: .moderate))
        XCTAssertEqual(risk, 0.0523, accuracy: 0.0025)
    }

    // Same profile as non-smoker must be lower.
    func testSCORE2SmokingIncreasesRisk() {
        let smoker = CardiovascularRiskModel.score2Risk(.init(
            age: 50, sex: .female, isSmoker: true, systolicBP: 140,
            totalCholesterol: 6.3, hdlCholesterol: 1.4, region: .moderate))
        let nonSmoker = CardiovascularRiskModel.score2Risk(.init(
            age: 50, sex: .female, isSmoker: false, systolicBP: 140,
            totalCholesterol: 6.3, hdlCholesterol: 1.4, region: .moderate))
        XCTAssertGreaterThan(smoker, nonSmoker)
    }

    // High-risk region must exceed low-risk region for identical inputs.
    func testSCORE2RegionMonotonicity() {
        func risk(_ region: SCORE2RiskRegion) -> Double {
            CardiovascularRiskModel.score2Risk(.init(
                age: 60, sex: .male, isSmoker: false, systolicBP: 130,
                totalCholesterol: 5.5, hdlCholesterol: 1.3, region: region))
        }
        XCTAssertLessThan(risk(.low), risk(.moderate))
        XCTAssertLessThan(risk(.moderate), risk(.high))
        XCTAssertLessThan(risk(.high), risk(.veryHigh))
    }

    // ASCVD Pooled Cohort Equations, widely-reproduced reference profile:
    // age 55, TC 213 mg/dL, HDL 50 mg/dL, SBP 120 untreated, non-smoker,
    // non-diabetic → White women ≈ 2.1%, White men ≈ 5.3%.
    func testASCVDWhiteWomanReference() {
        let risk = CardiovascularRiskModel.ascvdRisk(.init(
            age: 55, sex: .female, race: .whiteOrOther,
            totalCholesterol: 213, hdlCholesterol: 50, systolicBP: 120,
            treatedForBP: false, isSmoker: false, hasDiabetes: false))
        XCTAssertEqual(risk, 0.0205, accuracy: 0.003)
    }

    func testASCVDWhiteManReference() {
        let risk = CardiovascularRiskModel.ascvdRisk(.init(
            age: 55, sex: .male, race: .whiteOrOther,
            totalCholesterol: 213, hdlCholesterol: 50, systolicBP: 120,
            treatedForBP: false, isSmoker: false, hasDiabetes: false))
        XCTAssertEqual(risk, 0.0539, accuracy: 0.003)
    }

    func testASCVDDiabetesAndSmokingIncreaseRisk() {
        let base = CardiovascularRiskModel.ascvdRisk(.init(
            age: 55, sex: .male, race: .whiteOrOther,
            totalCholesterol: 213, hdlCholesterol: 50, systolicBP: 120,
            treatedForBP: false, isSmoker: false, hasDiabetes: false))
        let worse = CardiovascularRiskModel.ascvdRisk(.init(
            age: 55, sex: .male, race: .whiteOrOther,
            totalCholesterol: 213, hdlCholesterol: 50, systolicBP: 120,
            treatedForBP: false, isSmoker: true, hasDiabetes: true))
        XCTAssertGreaterThan(worse, base)
    }

    func testCholesterolUnitConversionRoundTrips() {
        let mgdl = CardiovascularRiskModel.mgdL(fromMmolPerL: 6.3)
        XCTAssertEqual(mgdl, 243.6, accuracy: 0.5)
        let back = CardiovascularRiskModel.mmolPerL(fromMgdL: mgdl)
        XCTAssertEqual(back, 6.3, accuracy: 0.001)
    }
}
