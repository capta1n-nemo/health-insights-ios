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

    /// **The listing rule changed on 2026-08-05**, at the reader's instruction:
    /// *"every card should show, even if it hasn't got data yet."* This test
    /// used to assert the opposite — that a fresh install leaves Readiness
    /// unlisted — on the reasoning that a card with nothing to do should not
    /// take up space. That conceded the wrong half: the problem with a dead
    /// card is that it is dead, not that it is there.
    ///
    /// It also said "Building baseline" to someone with **no samples at all**,
    /// which describes a process that is not happening. A reader who has
    /// connected nothing is told to connect something.
    func testAFreshInstallAsksForAWearableAndStaysOnTheTab() {
        let result = ReadinessInsight().evaluate(samples: [], profile: .init(), now: Date())
        XCTAssertEqual(result.headline, "Connect a wearable")
        XCTAssertFalse(result.isAwaitingTodaysData,
                       "nothing has ever synced, so there is no sync to wait for")
        XCTAssertTrue(result.isWorthShowing,
                      "a card that cannot appear cannot explain what the app needs")
    }

    /// The distinction the fresh-install case rests on: with *some* nights but
    /// too few to score, "Building baseline" is the true sentence and must
    /// survive. Collapsing the two states is what made the empty copy wrong at
    /// one end or the other.
    func testAThinHistoryStillSaysBuildingBaseline() {
        let now = Date()
        let result = ReadinessInsight().evaluate(
            samples: daily(.sleepDurationHours, 7.2, daysAgo: 20...22, now: now),
            profile: .init(), now: now)
        XCTAssertEqual(result.headline, "Building baseline")
        XCTAssertTrue(result.isWorthShowing)
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

    /// Same rule change as the Readiness case above. "No night yet" named the
    /// gap; "Connect a sleep source" says what to do about it — and the card
    /// now stays on Today to say it.
    func testEnergyWithNoNightsEverAsksForASourceAndStaysOnTheTab() {
        let now = Date()
        let samples = daily(.heartRate, 70, daysAgo: 0...5, now: now)
        let result = EnergyInsight().evaluate(samples: samples, profile: .init(), now: now)
        XCTAssertEqual(result.headline, "Connect a sleep source")
        XCTAssertFalse(result.isAwaitingTodaysData,
                       "no night has ever arrived, so there is no sync to wait for")
        XCTAssertTrue(result.isWorthShowing)
    }
}
