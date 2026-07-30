import XCTest
@testable import InsightKit

final class VitalSignsTests: XCTestCase {
    private func series(_ type: MetricType, _ values: [Double],
                        source: MetricSource = .appleHealth) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(type: type, value: value,
                               start: Date().addingTimeInterval(Double(index - values.count) * 86_400),
                               source: source)
        }
    }

    func testStableVitalReadsNormal() {
        let samples = series(.restingHeartRate, [55, 56, 54, 55, 56, 55])
        let reading = VitalSignsCheck.evaluate(samples: samples).readings.first
        XCTAssertEqual(reading?.metric, .restingHeartRate)
        XCTAssertEqual(reading?.status, .normal)
    }

    func testSpikeInAConcerningDirectionIsUnusual() {
        // Resting HR jumping well above a tight baseline.
        let samples = series(.restingHeartRate, [55, 56, 54, 55, 56, 78])
        let output = VitalSignsCheck.evaluate(samples: samples)
        XCTAssertEqual(output.readings.first?.status, .unusual)
        XCTAssertEqual(output.headline, "1 unusual")
    }

    func testDropInAGoodDirectionIsNotAlarming() {
        // The same magnitude of departure, downwards — recovery, not a problem.
        let samples = series(.restingHeartRate, [60, 61, 59, 60, 61, 45])
        let reading = VitalSignsCheck.evaluate(samples: samples).readings.first
        XCTAssertEqual(reading?.status, .watch)
        XCTAssertTrue(reading?.note.contains("below") ?? false)
    }

    func testAbsoluteFloorOverridesAPermissiveBaseline() {
        // A baseline built from consistently low saturation must not make 89%
        // read as normal.
        let samples = series(.oxygenSaturation, [89, 89, 90, 89, 89, 89])
        let reading = VitalSignsCheck.evaluate(samples: samples).readings.first
        XCTAssertEqual(reading?.status, .unusual)
        XCTAssertTrue(reading?.note.contains("healthy range") ?? false)
    }

    func testPreviouslyOrphanedMetricsAreNowRead() {
        // Heart rate, walking heart rate, blood oxygen and body temperature had
        // no reader at all before this insight existed.
        var samples: [HealthMetricSample] = []
        samples += series(.heartRate, [70, 72, 71, 69, 70, 71])
        samples += series(.walkingHeartRateAverage, [95, 96, 94, 95, 96, 95])
        samples += series(.oxygenSaturation, [97, 98, 97, 97, 98, 97])
        samples += series(.bodyTemperature, [36.6, 36.7, 36.6, 36.5, 36.6, 36.6])
        let covered = Set(VitalSignsCheck.evaluate(samples: samples).readings.map(\.metric))
        XCTAssertTrue(covered.isSuperset(of: [.heartRate, .walkingHeartRateAverage,
                                              .oxygenSaturation, .bodyTemperature]))
    }

    func testNoDataProducesAGracefulResult() {
        let result = VitalSignsInsight().evaluate(samples: [], profile: UserHealthProfile(), now: Date())
        XCTAssertNil(result.primaryValue)
        XCTAssertEqual(result.headline, "No data yet")
    }

    func testAllNormalScoresFull() {
        let samples = series(.restingHeartRate, [55, 56, 54, 55, 56, 55])
            + series(.oxygenSaturation, [97, 98, 97, 97, 98, 97])
        let result = VitalSignsInsight().evaluate(samples: samples, profile: UserHealthProfile(), now: Date())
        XCTAssertEqual(result.score, 100)
        XCTAssertEqual(result.headline, "All normal")
    }

    func testVitalSignsIsATodayCard() {
        XCTAssertEqual(InsightID.vitalSigns.cadence, .daily)
        XCTAssertTrue(InsightEngine().models.contains { $0.id == .vitalSigns })
    }
}

final class BodyCompositionWiringTests: XCTestCase {
    private func series(_ type: MetricType, _ values: [Double]) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(type: type, value: value,
                               start: Date().addingTimeInterval(Double(index - values.count) * 86_400),
                               source: .withings)
        }
    }

    func testScaleMetricsThatHadNoReaderNowAppear() {
        let samples = series(.bodyMass, [80, 79.6, 79.2])
            + series(.leanBodyMass, [60, 60.1, 60.2])
            + series(.muscleMass, [57, 57.1, 57.2])
            + series(.boneMass, [3.1, 3.1, 3.1])
            + series(.bodyWaterPercentage, [55, 55.2, 55.1])
        let drivers = BodyCompositionInsight()
            .evaluate(samples: samples, profile: UserHealthProfile(), now: Date())
            .drivers
            .joined(separator: "\n")

        XCTAssertTrue(drivers.contains("Lean mass"))
        XCTAssertTrue(drivers.contains("Muscle mass"))
        XCTAssertTrue(drivers.contains("Bone mass"))
        XCTAssertTrue(drivers.contains("Body water"))
    }

    func testWeightFallingWithLeanMassHoldingReadsAsFatLoss() throws {
        let samples = series(.bodyMass, [82, 81, 80, 78.5])
            + series(.leanBodyMass, [60, 60.1, 60, 60.1])
        let narrative = try XCTUnwrap(
            BodyCompositionInsight.compositionNarrative(
                samples: samples, weightSeries: samples.samples(of: .bodyMass)))
        XCTAssertTrue(narrative.contains("from fat"))
    }

    func testWeightAndLeanMassFallingTogetherFlagsMuscleLoss() throws {
        let samples = series(.bodyMass, [82, 81, 80, 78])
            + series(.leanBodyMass, [62, 61.5, 61, 59.5])
        let narrative = try XCTUnwrap(
            BodyCompositionInsight.compositionNarrative(
                samples: samples, weightSeries: samples.samples(of: .bodyMass)))
        XCTAssertTrue(narrative.contains("muscle"))
    }
}

final class VascularAgePromotionTests: XCTestCase {
    func testOuraCardiovascularAgeBecomesAVital() throws {
        let json = #"{"data":[{"day":"2026-01-10","vascular_age":32}]}"#
        var catalogue = FieldCatalogue()
        let result = IngestionPipeline.shipped.ingest(
            [IngestPayload(source: .oura, endpoint: "daily_cardiovascular_age", data: Data(json.utf8))],
            into: &catalogue)
        let promoted = try XCTUnwrap(result.promoted.first)
        XCTAssertEqual(promoted.type, .vascularAge)
        XCTAssertEqual(promoted.value, 32)
    }

    func testHeartAgeReportsTheProviderEstimateAlongsideItsOwn() {
        let now = Date()
        var profile = UserHealthProfile()
        profile.set(.init(kind: .dateOfBirth,
                          value: now.addingTimeInterval(-40 * 365.2425 * 86_400).timeIntervalSince1970,
                          recordedAt: now))
        profile.set(.init(kind: .biologicalSex, value: 0, recordedAt: now))
        // Enough for the insight to produce a headline age, so the driver list
        // is actually built rather than short-circuited by the "add details" path.
        profile.set(.init(kind: .cuffSystolic, value: 120, recordedAt: now))
        let samples = [
            HealthMetricSample(type: .vascularAge, value: 32, start: now, source: .oura),
            HealthMetricSample(type: .vo2Max, value: 44, start: now, source: .appleHealth)
        ]
        let drivers = HeartAgeInsight()
            .evaluate(samples: samples, profile: profile, now: now)
            .drivers.joined(separator: "\n")
        XCTAssertTrue(drivers.contains("vascular age"), drivers)
    }
}
