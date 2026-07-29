import XCTest
@testable import InsightKit

final class MultiSourceTests: XCTestCase {
    private func hr(_ v: Double, _ source: MetricSource, minutesAgo: Int) -> HealthMetricSample {
        HealthMetricSample(type: .heartRate, value: v,
                           start: Date().addingTimeInterval(-Double(minutesAgo) * 60),
                           source: source)
    }

    func testDeduplicatesOuraArrivingViaApiAndViaHealth() {
        // Oura via its API and Oura mirrored into Apple Health: same device,
        // same minute, same value → one sample.
        let ouraDirect = hr(60, .oura, minutesAgo: 10)
        let ouraViaHealth = HealthMetricSample(type: .heartRate, value: 60,
            start: ouraDirect.start, source: .appleHealthDevice("Oura"))
        let watch = hr(64, .appleHealthDevice("Apple Watch"), minutesAgo: 10)

        let deduped = MultiSource.deduplicate([ouraDirect, ouraViaHealth, watch])
        XCTAssertEqual(deduped.count, 2) // Oura duplicate collapsed, Watch kept
    }

    func testBreakdownSeparatesDevicesAndComputesConsensus() {
        let samples = [
            hr(62, .appleHealthDevice("Apple Watch"), minutesAgo: 30),
            hr(66, .appleHealthDevice("Apple Watch"), minutesAgo: 5),   // latest Watch = 66
            hr(58, .oura, minutesAgo: 20),
            hr(60, .oura, minutesAgo: 8)                                // latest Oura = 60
        ]
        let b = MultiSource.breakdown(.heartRate, from: samples)
        XCTAssertTrue(b.hasMultipleSources)
        XCTAssertEqual(b.sources.count, 2)
        // Consensus of latest per source = (66 + 60) / 2 = 63
        XCTAssertEqual(b.consensusLatest!, 63, accuracy: 1e-9)
        XCTAssertEqual(b.latestSpread!, 6, accuracy: 1e-9)   // 66 − 60
    }

    func testDeviceFamilyCollapsesOuraLabels() {
        XCTAssertEqual(MetricSource.oura.deviceFamily, "oura")
        XCTAssertEqual(MetricSource.appleHealthDevice("Oura").deviceFamily, "oura")
        XCTAssertEqual(MetricSource.appleHealthDevice("Apple Watch").deviceFamily, "apple_watch")
    }

    func testSingleSourceHasZeroSpread() {
        let b = MultiSource.breakdown(.heartRate, from: [hr(60, .oura, minutesAgo: 5)])
        XCTAssertFalse(b.hasMultipleSources)
        XCTAssertEqual(b.consensusLatest, 60)
        XCTAssertEqual(b.latestSpread, 0)
    }

    /// A glanceable value must be the newest reading, not the mean of each
    /// source's latest — those diverge badly once a source goes quiet, which is
    /// what made the vitals previews read like long-run averages.
    func testMostRecentIsNewestReadingNotCrossSourceMean() {
        let samples = [
            hr(90, .appleHealthDevice("MyFitnessPal"), minutesAgo: 60 * 24 * 300), // stale
            hr(58, .oura, minutesAgo: 10)                                          // current
        ]
        let b = MultiSource.breakdown(.heartRate, from: samples)
        XCTAssertEqual(b.mostRecent?.value, 58)
        XCTAssertEqual(b.mostRecent?.source.deviceFamily, "oura")
        // Averaging the two latest values gives 74 — nowhere near either reading.
        XCTAssertEqual(b.consensusLatest!, 74, accuracy: 1e-9)
    }

    func testMostRecentIsNilWithoutSamples() {
        XCTAssertNil(MultiSource.breakdown(.heartRate, from: []).mostRecent)
    }
}
