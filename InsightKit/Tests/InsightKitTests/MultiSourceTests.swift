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

    /// The binary-searched range restriction must agree with a plain filter,
    /// including at the boundaries.
    func testRestrictedMatchesFilteringAndKeepsBoundaries() {
        let samples = (0..<200).map { hr(60 + Double($0 % 10), .oura, minutesAgo: $0) }
        let series = SourceSeries(source: .oura, samples: samples)
        let now = Date()
        let range = now.addingTimeInterval(-100 * 60)...now.addingTimeInterval(-50 * 60)

        let restricted = series.restricted(to: range).samples
        let filtered = series.samples.filter { range.contains($0.start) }
        XCTAssertEqual(restricted.map(\.id), filtered.map(\.id))
        XCTAssertFalse(restricted.isEmpty)
    }

    func testRestrictedIsEmptyOutsideTheData() {
        let series = SourceSeries(source: .oura, samples: [hr(60, .oura, minutesAgo: 5)])
        let long = Date().addingTimeInterval(-3600)
        XCTAssertTrue(series.restricted(to: long...long.addingTimeInterval(60)).samples.isEmpty)
    }

    /// Thinning keeps the shape's endpoints, which is what stops a chart losing
    /// its most recent reading.
    func testDownsamplingCapsCountAndKeepsEnds() {
        let samples = (0..<5_000).map { hr(Double(50 + $0 % 40), .oura, minutesAgo: 5_000 - $0) }
        let series = SourceSeries(source: .oura, samples: samples)
        let thinned = series.downsampled(to: 300)
        XCTAssertEqual(thinned.samples.count, 300)
        XCTAssertEqual(thinned.samples.first?.id, series.samples.first?.id)
        XCTAssertEqual(thinned.samples.last?.id, series.samples.last?.id)
    }

    func testDownsamplingLeavesShortSeriesAlone() {
        let series = SourceSeries(source: .oura, samples: (0..<10).map { hr(60, .oura, minutesAgo: $0) })
        XCTAssertEqual(series.downsampled(to: 300).samples.count, 10)
    }

    /// Restricting a breakdown drops sources with nothing in the window, so a
    /// read-out can't show a value from outside it.
    func testRestrictedBreakdownDropsSourcesOutsideTheWindow() {
        let b = MultiSource.breakdown(.heartRate, from: [
            hr(90, .appleHealthDevice("MyFitnessPal"), minutesAgo: 60 * 24 * 300),
            hr(58, .oura, minutesAgo: 10)
        ])
        let recent = b.restricted(to: Date().addingTimeInterval(-3600)...Date())
        XCTAssertEqual(recent.sources.count, 1)
        XCTAssertEqual(recent.mostRecent?.value, 58)
    }
}

/// The double-count an outside analysis of the user's export found on
/// 2026-08-02: one metric arriving as a daily *total* down one path and as the
/// same day's *intervals* down another, both from the same device.
///
/// `deviceFamily` deliberately collapses those paths into one series — which is
/// right for a mean or a median and catastrophic for a sum, because the two
/// paths are a total and its own parts. The export made it visible as one
/// path's median of 7 steps beside another's median of 4,435.
final class CumulativeDoubleCountTests: XCTestCase {

    private let day = Calendar.current.startOfDay(
        for: Date(timeIntervalSince1970: 1_780_000_000))

    private func steps(_ value: Double, _ source: MetricSource,
                       hour: Double) -> HealthMetricSample {
        HealthMetricSample(type: .stepCount, value: value,
                           start: day.addingTimeInterval(hour * 3600), source: source)
    }

    /// Oura's own daily total, plus the same day mirrored into Apple Health as
    /// intervals adding to the same figure. One walk, not two.
    private var oneDayTwoWays: [HealthMetricSample] {
        let direct = MetricSource.oura
        let mirrored = MetricSource(id: "apple_health/oura", displayName: "Oura via Apple Health")
        var out = [steps(4_400, direct, hour: 23.5)]
        for hour in 0..<22 {
            out.append(steps(200, mirrored, hour: Double(hour)))
        }
        return out
    }

    func testADailyTotalIsNotAddedToItsOwnMirroredIntervals() throws {
        let breakdown = MultiSource.breakdown(.stepCount, from: oneDayTwoWays)
        // Both paths are one device, so this is deliberately a single series.
        XCTAssertEqual(breakdown.sources.count, 1, "the same ring is one instrument")

        let buckets = try XCTUnwrap(breakdown.sources.first)
            .bucketed(by: .day, statistic: .sum)
        let total = try XCTUnwrap(buckets.first).value
        XCTAssertEqual(total, 4_400, accuracy: 1,
                       "4,400 steps reported twice is still 4,400 steps — was 8,800")
    }

    /// A single path is untouched: the sum of a day's intervals is that day.
    func testASinglePathStillSumsItsIntervals() throws {
        let mirrored = MetricSource(id: "apple_health/oura", displayName: "Oura via Apple Health")
        let samples = (0..<10).map { steps(100, mirrored, hour: Double($0)) }
        let buckets = try XCTUnwrap(MultiSource.breakdown(.stepCount, from: samples)
            .sources.first).bucketed(by: .day, statistic: .sum)
        XCTAssertEqual(try XCTUnwrap(buckets.first).value, 1_000, accuracy: 1)
    }

    /// The partially-synced case: the fuller path is the day's account, so a
    /// mid-sync mirror must not shrink a complete direct total.
    func testTheMoreCompletePathWins() throws {
        let direct = MetricSource.oura
        let mirrored = MetricSource(id: "apple_health/oura", displayName: "Oura via Apple Health")
        let samples = [steps(4_400, direct, hour: 23.5),
                       steps(150, mirrored, hour: 1)]   // only one interval synced so far
        let buckets = try XCTUnwrap(MultiSource.breakdown(.stepCount, from: samples)
            .sources.first).bucketed(by: .day, statistic: .sum)
        XCTAssertEqual(try XCTUnwrap(buckets.first).value, 4_400, accuracy: 1)
    }

    /// Averaged metrics are unaffected — the fix is scoped to sums, where a
    /// total and its parts are the only readings that can be added twice.
    func testMeanMetricsAreUnaffected() throws {
        let direct = MetricSource.oura
        let samples = [HealthMetricSample(type: .restingHeartRate, value: 50,
                                          start: day, source: direct),
                       HealthMetricSample(type: .restingHeartRate, value: 60,
                                          start: day.addingTimeInterval(3600), source: direct)]
        let buckets = try XCTUnwrap(MultiSource.breakdown(.restingHeartRate, from: samples)
            .sources.first).bucketed(by: .day, statistic: .mean)
        XCTAssertEqual(try XCTUnwrap(buckets.first).value, 55, accuracy: 0.001)
    }
}
