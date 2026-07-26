import XCTest
@testable import InsightKit

final class BaselineTests: XCTestCase {
    func testMeanAndStandardDeviation() {
        let xs = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
        XCTAssertEqual(Baseline.mean(xs)!, 5.0, accuracy: 1e-9)
        // Sample SD (n-1) of this classic set is ~2.138.
        XCTAssertEqual(Baseline.standardDeviation(xs)!, 2.138, accuracy: 0.01)
    }

    func testStandardDeviationNeedsTwoPoints() {
        XCTAssertNil(Baseline.standardDeviation([3.0]))
        XCTAssertNil(Baseline.mean([]))
    }

    func testEWMAWeightsRecentMore() {
        let flat = Baseline.ewma([10, 10, 10, 10])!
        XCTAssertEqual(flat, 10, accuracy: 1e-9)
        let rising = Baseline.ewma([10, 10, 10, 20], alpha: 0.5)!
        XCTAssertGreaterThan(rising, 12) // pulled toward the recent 20
    }

    func testZScore() {
        let history = [60.0, 62, 58, 61, 59]
        let z = Baseline.zScore(70, history: history)!
        XCTAssertGreaterThan(z, 3) // 70 is well above a ~60 baseline
        XCTAssertNil(Baseline.zScore(70, history: [60, 60, 60])) // no spread
    }

    func testDeviationDirection() {
        let history = Array(repeating: 60.0, count: 3) + [61, 59, 60, 61, 59]
        let dev = Baseline.deviation(latest: 85, history: history)!
        XCTAssertEqual(dev.direction, 1)
    }
}

final class HeartHealthTests: XCTestCase {
    func testFitProfileScoresHigherThanUnfit() {
        let fit = HeartHealthScore.evaluate(
            vo2Max: 50, restingHR: 52, hrv: 70, respiratoryRateDeviation: nil,
            age: 35, sex: .male)!
        let unfit = HeartHealthScore.evaluate(
            vo2Max: 28, restingHR: 82, hrv: 25, respiratoryRateDeviation: nil,
            age: 35, sex: .male)!
        XCTAssertGreaterThan(fit.score, unfit.score)
        XCTAssertGreaterThan(fit.score, 70)
        XCTAssertLessThan(unfit.score, 55)
    }

    func testWeightsReNormalizeWhenComponentsMissing() {
        // Only VO2max present → composite equals its sub-score.
        let out = HeartHealthScore.evaluate(
            vo2Max: 40, restingHR: nil, hrv: nil, respiratoryRateDeviation: nil,
            age: 40, sex: .male)!
        XCTAssertEqual(out.components.count, 1)
        XCTAssertEqual(out.score, out.components[0].score, accuracy: 1e-9)
    }

    func testRestingHRScoreMonotonic() {
        XCTAssertGreaterThan(HeartHealthScore.restingHRScore(50), HeartHealthScore.restingHRScore(80))
    }
}

final class BloodPressureTests: XCTestCase {
    func testCategoryBoundaries() {
        XCTAssertEqual(BloodPressureEstimator.category(systolic: 118, diastolic: 76), "Normal")
        XCTAssertEqual(BloodPressureEstimator.category(systolic: 124, diastolic: 78), "Elevated")
        XCTAssertEqual(BloodPressureEstimator.category(systolic: 134, diastolic: 82), "Stage 1 hypertension")
        XCTAssertEqual(BloodPressureEstimator.category(systolic: 150, diastolic: 95), "Stage 2 hypertension")
        XCTAssertEqual(BloodPressureEstimator.category(systolic: 185, diastolic: 100), "Hypertensive crisis")
    }

    func testEstimatorRequiresMinimumCalibration() {
        let few = (0..<3).map { i in
            BloodPressureEstimator.CalibrationPoint(
                restingHR: 60 + Double(i), systolic: 120, diastolic: 80,
                date: Date(timeIntervalSince1970: Double(i)))
        }
        XCTAssertNil(BloodPressureEstimator.estimate(currentRestingHR: 62, calibration: few))
    }

    func testEstimatorLearnsPositiveHRTrend() {
        // Construct a clean relationship: systolic = 80 + HR.
        let points = (0..<8).map { i -> BloodPressureEstimator.CalibrationPoint in
            let hr = 55.0 + Double(i) * 3
            return .init(restingHR: hr, systolic: 80 + hr, diastolic: 50 + hr * 0.5,
                         date: Date(timeIntervalSince1970: Double(i)))
        }
        let est = BloodPressureEstimator.estimate(currentRestingHR: 70, calibration: points)!
        XCTAssertEqual(est.systolic, 150, accuracy: 1.0)      // 80 + 70
        XCTAssertLessThan(est.systolicUncertainty, 2.0)       // near-perfect fit
        XCTAssertEqual(est.calibrationCount, 8)
    }

    func testLinearFitRecoversKnownLine() {
        let x = [1.0, 2, 3, 4, 5]
        let y = x.map { 3 * $0 + 7 }
        let fit = BloodPressureEstimator.linearFit(x: x, y: y)!
        XCTAssertEqual(fit.slope, 3, accuracy: 1e-6)
        XCTAssertEqual(fit.intercept, 7, accuracy: 1e-6)
        XCTAssertEqual(fit.residualSD, 0, accuracy: 1e-6)
    }
}

final class InsightEngineTests: XCTestCase {
    private func fullProfile() -> UserHealthProfile {
        var p = UserHealthProfile()
        let now = Date()
        // 50 years old.
        let dob = now.addingTimeInterval(-50 * 365.2425 * 24 * 3600)
        p.set(.init(kind: .dateOfBirth, value: dob.timeIntervalSince1970, recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: 0, recordedAt: now)) // male
        p.set(.init(kind: .totalCholesterol, value: 5.5, recordedAt: now))
        p.set(.init(kind: .hdlCholesterol, value: 1.3, recordedAt: now))
        p.set(.init(kind: .currentSmoker, value: 0, recordedAt: now))
        p.set(.init(kind: .hasDiabetes, value: 0, recordedAt: now))
        p.set(.init(kind: .cuffSystolic, value: 130, recordedAt: now))
        p.set(.init(kind: .cuffDiastolic, value: 82, recordedAt: now))
        return p
    }

    func testEngineProducesConfidentCVRiskWhenGrounded() {
        let engine = InsightEngine()
        let result = engine.result(for: .cardiovascularRisk, samples: [], profile: fullProfile())!
        XCTAssertNotNil(result.primaryValue)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertFalse(result.drivers.isEmpty)
    }

    func testCombinedRiskIsMeanOfBothModels() {
        // Same inputs, computed directly, must average to the insight's consensus.
        let profile = fullProfile()
        let now = Date()
        let age = profile.age(asOf: now)!
        let s2 = CardiovascularRiskModel.score2Risk(.init(
            age: age, sex: .male, isSmoker: false, systolicBP: 130,
            totalCholesterol: 5.5, hdlCholesterol: 1.3, region: profile.score2Region)) * 100
        let ascvd = CardiovascularRiskModel.ascvdRisk(.init(
            age: age, sex: .male, race: .whiteOrOther,
            totalCholesterol: CardiovascularRiskModel.mgdL(fromMmolPerL: 5.5),
            hdlCholesterol: CardiovascularRiskModel.mgdL(fromMmolPerL: 1.3),
            systolicBP: 130, treatedForBP: false, isSmoker: false, hasDiabetes: false)) * 100

        let insight = CardiovascularRiskInsight(preferredEngine: .combined)
        let result = insight.evaluate(samples: [], profile: profile, now: now)
        XCTAssertEqual(result.primaryValue!, (s2 + ascvd) / 2, accuracy: 0.01)
        // Both model figures and a range are surfaced to the user.
        XCTAssertTrue(result.drivers.contains { $0.hasPrefix("SCORE2:") })
        XCTAssertTrue(result.drivers.contains { $0.hasPrefix("ASCVD:") })
        XCTAssertTrue(result.drivers.contains { $0.contains("Range across models") })
    }

    func testCombinedRiskAsksForDiabetes() {
        // Diabetes is mandatory for the ASCVD half; a profile without it should
        // still compute but flag diabetes as an unmet requirement.
        var p = fullProfile()
        p.inputs[.hasDiabetes] = nil
        let insight = CardiovascularRiskInsight(preferredEngine: .combined)
        let result = insight.evaluate(samples: [], profile: p, now: Date())
        XCTAssertNotNil(result.primaryValue)
        XCTAssertEqual(result.confidence, .moderate)
        XCTAssertTrue(result.unmetRequirements.contains { $0.kind == .hasDiabetes })
    }

    func testEngineReportsMissingGroundingWhenEmpty() {
        let engine = InsightEngine()
        let outstanding = engine.outstandingGrounding(profile: UserHealthProfile())
        // With an empty profile, mandatory items like DOB must be surfaced.
        XCTAssertTrue(outstanding.contains { $0.requirement.kind == .dateOfBirth })
        XCTAssertTrue(outstanding.first!.requirement.isMandatory)
    }

    func testBloodPressureInsightShowsLoggedReading() {
        let engine = InsightEngine()
        let result = engine.result(for: .bloodPressure, samples: [], profile: fullProfile())!
        XCTAssertEqual(result.headline, "130/82")
    }
}
