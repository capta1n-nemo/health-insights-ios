import XCTest
@testable import InsightKit

final class MetricSanitizerTests: XCTestCase {
    private func sample(_ type: MetricType, _ value: Double) -> HealthMetricSample {
        HealthMetricSample(type: type, value: value, start: Date(), source: .oura)
    }

    func testDropsZeroRestingHeartRate() {
        let samples = [sample(.restingHeartRate, 0), sample(.restingHeartRate, 58)]
        let clean = samples.sanitizedVitals()
        XCTAssertEqual(clean.count, 1)
        XCTAssertEqual(clean.first?.value, 58)
    }

    func testDropsNonPositiveVitalsAcrossTypes() {
        let samples = [
            sample(.heartRateVariabilityRMSSD, 0),
            sample(.vo2Max, -1),
            sample(.bloodPressureSystolic, 0),
            sample(.bodyMass, 0),
            sample(.oxygenSaturation, 0)
        ]
        XCTAssertTrue(samples.sanitizedVitals().isEmpty)
    }

    func testKeepsLegitimateZeroMetrics() {
        // Steps, active energy, day strain and skin-temp deviation can be zero
        // (or signed) legitimately — they must survive.
        let samples = [
            sample(.stepCount, 0),
            sample(.activeEnergyBurned, 0),
            sample(.dayStrain, 0),
            sample(.skinTemperatureDeviation, -0.3)
        ]
        XCTAssertEqual(samples.sanitizedVitals().count, 4)
    }

    func testKeepsPositiveVitals() {
        let samples = [sample(.restingHeartRate, 55), sample(.bodyMass, 72.4)]
        XCTAssertEqual(samples.sanitizedVitals().count, 2)
    }
}
