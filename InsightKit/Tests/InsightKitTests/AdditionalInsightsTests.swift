import XCTest
@testable import InsightKit

final class AdditionalInsightsTests: XCTestCase {
    private func sample(_ type: MetricType, _ value: Double, daysAgo: Int) -> HealthMetricSample {
        HealthMetricSample(type: type, value: value,
                           start: Date().addingTimeInterval(-Double(daysAgo) * 86400),
                           source: .oura)
    }

    private func profile(age: Double, male: Bool) -> UserHealthProfile {
        var p = UserHealthProfile()
        let now = Date()
        p.set(.init(kind: .dateOfBirth, value: now.addingTimeInterval(-age * 365.2425 * 86400).timeIntervalSince1970, recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: male ? 0 : 1, recordedAt: now))
        return p
    }

    func testSleepQualityScoresGoodNight() {
        let samples = [sample(.sleepDurationHours, 7.5, daysAgo: 2),
                       sample(.sleepDurationHours, 8.0, daysAgo: 1),
                       sample(.sleepDurationHours, 7.8, daysAgo: 0)]
        let r = SleepQualityInsight().evaluate(samples: samples, profile: .init(), now: Date())
        XCTAssertNotNil(r.primaryValue)
        XCTAssertGreaterThan(r.score ?? 0, 70)
    }

    func testSleepQualityNoDataIsGraceful() {
        let r = SleepQualityInsight().evaluate(samples: [], profile: .init(), now: Date())
        XCTAssertNil(r.primaryValue)
        XCTAssertEqual(r.headline, "No data yet")
    }

    func testCardioFitnessLevelAndTrend() {
        let samples = [sample(.vo2Max, 46, daysAgo: 20),
                       sample(.vo2Max, 47, daysAgo: 10),
                       sample(.vo2Max, 48, daysAgo: 0)]
        let r = CardioFitnessInsight().evaluate(samples: samples, profile: profile(age: 35, male: true), now: Date())
        XCTAssertEqual(r.primaryValue!, 48, accuracy: 1e-9)
        XCTAssertEqual(r.confidence, .high)
        XCTAssertTrue(r.drivers.contains { $0.contains("Trend") })
    }

    func testBodyCompositionBMI() {
        let samples = [sample(.bodyMass, 80, daysAgo: 0), sample(.height, 1.80, daysAgo: 100)]
        let r = BodyCompositionInsight().evaluate(samples: samples, profile: .init(), now: Date())
        XCTAssertEqual(r.primaryValue!, 24.69, accuracy: 0.05)     // 80 / 1.8²
        XCTAssertTrue(r.drivers.contains { $0.contains("BMI") })
    }

    func testRestingHeartRateTrendFlagsElevation() {
        let samples = [sample(.restingHeartRate, 60, daysAgo: 5),
                       sample(.restingHeartRate, 61, daysAgo: 4),
                       sample(.restingHeartRate, 59, daysAgo: 3),
                       sample(.restingHeartRate, 60, daysAgo: 2),
                       sample(.restingHeartRate, 72, daysAgo: 0)]
        let r = RestingHeartRateTrendInsight().evaluate(samples: samples, profile: .init(), now: Date())
        XCTAssertEqual(r.headline, "72 bpm")
        XCTAssertTrue(r.explanation.contains("elevated"))
    }

    func testEngineRegistersAllInsights() {
        let ids = Set(InsightEngine().models.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: [.sleepQuality, .cardioFitness, .bodyComposition, .restingHeartRateTrend]))
    }
}
