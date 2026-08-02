import XCTest
@testable import InsightKit

/// Shaped like the morning of 2026-08-02: months of nights on record, wearable
/// not yet synced today. Readiness told that user to "wear your device for a
/// few nights", Energy told them to "record a night", both cards vanished from
/// Today — and the Last-night tile presented the same stale night as fresh.
/// One gap, three contradictory stories. The two models must tell
/// "hasn't synced today" apart from "never recorded", and the waiting state
/// must keep the card listed.
final class StaleSyncDayTests: XCTestCase {

    private func daily(_ type: MetricType, _ value: Double,
                       daysAgo range: ClosedRange<Int>, now: Date) -> [HealthMetricSample] {
        range.map {
            HealthMetricSample(type: type, value: value,
                               start: now.addingTimeInterval(-Double($0) * 86_400),
                               source: .oura)
        }
    }

    // MARK: Readiness

    func testAStaleSyncMorningWaitsRatherThanClaimingNoBaseline() throws {
        let now = Date()
        // A month of history for two components, nothing newer than 2 days.
        let samples = daily(.restingHeartRate, 55, daysAgo: 2...30, now: now)
            + daily(.sleepDurationHours, 7.4, daysAgo: 2...30, now: now)
        let result = ReadinessInsight().evaluate(samples: samples, profile: .init(), now: now)

        XCTAssertNil(result.score)
        XCTAssertEqual(result.headline, "Waiting for today's sync")
        XCTAssertTrue(result.isAwaitingTodaysData)
        XCTAssertTrue(result.isWorthShowing,
                      "a waiting card stays on Today rather than vanishing")
        XCTAssertFalse(result.explanation.contains("Wear your device"),
                       "someone on night 30 must not be told to start wearing one")
        XCTAssertTrue(result.explanation.contains("2 days ago"), result.explanation)
    }

    func testAFreshInstallStillSaysBuildingBaselineAndStaysUnlisted() {
        let result = ReadinessInsight().evaluate(samples: [], profile: .init(), now: Date())
        XCTAssertEqual(result.headline, "Building baseline")
        XCTAssertFalse(result.isAwaitingTodaysData)
        XCTAssertFalse(result.isWorthShowing,
                       "no history and nothing to do — the original listing rule holds")
    }

    // MARK: Energy

    func testEnergyWaitsForLastNightInsteadOfDenyingAllNights() {
        let now = Date()
        let samples = daily(.sleepDurationHours, 7.0, daysAgo: 3...40, now: now)
        let result = EnergyInsight().evaluate(samples: samples, profile: .init(), now: now)

        XCTAssertNil(result.score)
        XCTAssertEqual(result.headline, "Waiting for last night")
        XCTAssertTrue(result.isAwaitingTodaysData)
        XCTAssertTrue(result.isWorthShowing)
        XCTAssertFalse(result.explanation.contains("Record a night"),
                       "243 recorded nights is not zero: \(result.explanation)")
        XCTAssertTrue(result.explanation.contains("hasn't synced"), result.explanation)
    }

    func testEnergyWithNoNightsEverKeepsTheOriginalEmptyState() {
        let now = Date()
        let samples = daily(.heartRate, 70, daysAgo: 0...5, now: now)
        let result = EnergyInsight().evaluate(samples: samples, profile: .init(), now: now)
        XCTAssertEqual(result.headline, "No night yet")
        XCTAssertFalse(result.isAwaitingTodaysData)
        XCTAssertFalse(result.isWorthShowing)
    }
}
