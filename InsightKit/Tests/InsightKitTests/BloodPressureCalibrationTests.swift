import XCTest
@testable import InsightKit

final class BloodPressureCalibrationTests: XCTestCase {
    /// One cuff reading = a systolic + diastolic sample at the same instant.
    private func reading(_ sys: Double, _ dia: Double, daysAgo: Double,
                         source: MetricSource = .appleHealthDevice("Cuff")) -> [HealthMetricSample] {
        let date = Date().addingTimeInterval(-daysAgo * 24 * 3600)
        return [
            HealthMetricSample(type: .bloodPressureSystolic, value: sys, start: date, source: source),
            HealthMetricSample(type: .bloodPressureDiastolic, value: dia, start: date, source: source)
        ]
    }

    func testPairsSystolicAndDiastolicAcrossSources() {
        var samples: [HealthMetricSample] = []
        samples += reading(120, 80, daysAgo: 1, source: .appleHealthDevice("Apple Watch"))
        samples += reading(118, 78, daysAgo: 2, source: .withings)
        let readings = BloodPressureEstimator.pairedReadings(from: samples)
        XCTAssertEqual(readings.count, 2)
        // Newest first.
        XCTAssertEqual(readings.first?.systolic, 120)
        XCTAssertEqual(readings.first?.source, "Apple Watch")
    }

    func testThreeRecentReadingsNeedTwoMoreForInitial() {
        // The user's example: 3 readings in the last 30 days → ask for 2 more.
        var samples: [HealthMetricSample] = []
        samples += reading(122, 80, daysAgo: 2)
        samples += reading(119, 79, daysAgo: 10)
        samples += reading(121, 81, daysAgo: 20)
        let status = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertEqual(status.totalReadings, 3)
        XCTAssertEqual(status.recentReadings, 3)
        XCTAssertFalse(status.initialComplete)
        XCTAssertEqual(status.neededForInitial, 2)
    }

    func testFiveReadingsCompleteInitialCalibration() {
        var samples: [HealthMetricSample] = []
        for d in [1.0, 5, 12, 18, 27] { samples += reading(120, 80, daysAgo: d) }
        let status = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertEqual(status.totalReadings, 5)
        XCTAssertTrue(status.initialComplete)
        XCTAssertEqual(status.neededForInitial, 0)
    }

    func testMaintenanceFreshnessUsesLast30Days() {
        // Initial done long ago, but nothing recent → needs maintenance readings.
        var samples: [HealthMetricSample] = []
        for d in [200.0, 210, 220, 230, 240] { samples += reading(120, 80, daysAgo: d) }
        let status = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertTrue(status.initialComplete)
        XCTAssertEqual(status.recentReadings, 0)
        XCTAssertFalse(status.isFresh)
        XCTAssertEqual(status.neededThisMonth, BloodPressureEstimator.maintenanceReadingsPerMonth)

        // Add two recent → fresh/grounded.
        samples += reading(118, 78, daysAgo: 3)
        samples += reading(122, 82, daysAgo: 10)
        let fresh = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertEqual(fresh.recentReadings, 2)
        XCTAssertTrue(fresh.isFresh)
        XCTAssertEqual(fresh.neededThisMonth, 0)
    }

    func testAppleHealthReadingsSatisfyCuffRequirement() {
        // Only Apple Health BP present, no in-app grounding → the insight should
        // not still be asking the user to log a cuff reading.
        var samples: [HealthMetricSample] = []
        samples += reading(124, 82, daysAgo: 1)
        let result = BloodPressureInsight().evaluate(
            samples: samples, profile: UserHealthProfile(), now: Date())
        XCTAssertFalse(result.unmetRequirements.contains { $0.kind == .cuffSystolic })
        XCTAssertFalse(result.unmetRequirements.contains { $0.kind == .cuffDiastolic })
        XCTAssertEqual(result.headline, "124/82")
    }
}
