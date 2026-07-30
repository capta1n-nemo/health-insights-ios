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

    func testPartitionReportsWhatWasDropped() {
        let samples = [
            sample(.restingHeartRate, 0),
            sample(.restingHeartRate, 58),
            sample(.stepCount, 0),
            sample(.bodyMass, -2)
        ]
        let (kept, dropped) = samples.partitionedVitals()
        XCTAssertEqual(kept.count, 2)
        XCTAssertEqual(dropped.count, 2)
        XCTAssertEqual(Set(dropped.map(\.type)), [.restingHeartRate, .bodyMass])
        // The diagnostics log needs the source of a dropped sample to name the
        // provider that sent the placeholder.
        XCTAssertEqual(Set(dropped.map { $0.source.id }), ["oura"])
    }

    func testPartitionAgreesWithSanitizedVitals() {
        let samples = [
            sample(.heartRate, 0), sample(.heartRate, 61),
            sample(.skinTemperatureDeviation, -0.4), sample(.oxygenSaturation, 0)
        ]
        XCTAssertEqual(samples.partitionedVitals().kept.map(\.id),
                       samples.sanitizedVitals().map(\.id))
    }
}
