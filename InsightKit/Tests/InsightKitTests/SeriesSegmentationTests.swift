import XCTest
@testable import InsightKit

private let segCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
/// 2026-01-01T00:00Z, matching the pinned-UTC convention in `PresentationTests`.
private let segBase = Date(timeIntervalSince1970: 1_767_225_600)
private let segDay: TimeInterval = 86_400

/// When a chart line may be drawn as continuous.
///
/// `MetricType.maxValidInterval` is a *sample*-scale rule — thirty minutes for
/// heart rate. `MultiSourceChart` compared it against *bucket starts*, so at any
/// zoom past three days it broke the line between every adjacent pair and drew
/// the whole series as loose dots. `NormalizedSeries` had guarded against exactly
/// this with its own two-day floor; the metric-detail chart had no floor at all.
///
/// The rule now lives in InsightKit, where it can be tested — the app target has
/// no test target, which is why this was only ever checked by eye.
final class SeriesSegmentationTests: XCTestCase {

    private func series(_ metric: MetricType, offsets: [TimeInterval]) -> SourceSeries {
        SourceSeries(source: .appleHealth,
                     samples: offsets.map {
                         HealthMetricSample(type: metric, value: 60,
                                            start: segBase.addingTimeInterval($0),
                                            source: .appleHealth)
                     })
    }

    private func run(_ dayOffsets: [Double]) -> [AggregatedPoint] {
        dayOffsets.map {
            AggregatedPoint(date: segBase.addingTimeInterval($0 * segDay),
                            value: 60, mean: 60, median: 60, min: 60, max: 60, count: 1)
        }
    }

    // MARK: - The bug

    func testDailyBucketsOfHeartRateAreOneSegment() {
        // A month of hourly heart-rate readings, bucketed to days.
        let offsets = (0..<(30 * 24)).map { Double($0) * 3600 }
        let buckets = series(.heartRate, offsets: offsets)
            .bucketed(by: .day, for: .heartRate, calendar: segCalendar)
        XCTAssertEqual(buckets.count, 30)
        XCTAssertEqual(buckets.segments(maxGap: MetricType.heartRate.maxValidInterval).count, 30,
                       "the sample-scale rule is meant to shatter a daily grid — that was the bug")
        XCTAssertEqual(buckets.segments(for: .heartRate, bucket: .day).count, 1)
    }

    /// The floor must not loosen the one zoom where the sample rule is correct.
    func testRawWidthKeepsTheSampleScaleRule() {
        let buckets = run([0, 600 / segDay, 1200 / segDay, 1800 / segDay,
                           5400 / segDay, 6000 / segDay])
        XCTAssertEqual(buckets.segments(for: .heartRate, bucket: .raw).count, 2)
    }

    /// Two bucket widths exactly: one missing bucket joins, two do not.
    func testOneMissingDayJoinsAndTwoDoNot() {
        XCTAssertEqual(run([0, 1, 3]).segments(for: .heartRate, bucket: .day).count, 1)
        XCTAssertEqual(run([0, 1, 4]).segments(for: .heartRate, bucket: .day).count, 2)
    }

    /// The longest month is the nominal width, so a monthly grid can't split
    /// itself across February.
    func testMonthlyGridDoesNotSelfShatter() {
        let offsets = (0..<400).map { Double($0) * segDay }
        let buckets = series(.heartRate, offsets: offsets)
            .bucketed(by: .month, for: .heartRate, calendar: segCalendar)
        XCTAssertGreaterThan(buckets.count, 12)
        XCTAssertEqual(buckets.segments(for: .heartRate, bucket: .month).count, 1)
    }

    func testWeeklyGridDoesNotSelfShatter() {
        let offsets = (0..<200).map { Double($0) * segDay }
        let buckets = series(.heartRate, offsets: offsets)
            .bucketed(by: .week, for: .heartRate, calendar: segCalendar)
        XCTAssertEqual(buckets.segments(for: .heartRate, bucket: .week).count, 1)
    }

    /// A metric whose own interval is wider than the floor keeps its own rule.
    func testBodyMassKeepsItsFortnightRuleAtDayWidth() {
        XCTAssertEqual(run([0, 1, 11]).segments(for: .bodyMass, bucket: .day).count, 1)
        XCTAssertEqual(run([0, 1, 21]).segments(for: .bodyMass, bucket: .day).count, 2)
    }

    /// The proof that moving `NormalizedSeries` onto the shared rule changed
    /// nothing: at day width it *is* that file's old two-day floor.
    func testTheSharedRuleMatchesTheNormalizedSeriesFloor() {
        for metric in MetricType.allCases {
            XCTAssertEqual(metric.maxPlottableGap(bucket: .day),
                           Swift.max(metric.maxValidInterval, 2 * segDay),
                           "\(metric) diverges from the floor NormalizedSeries carried")
        }
    }

    func testTheGapRuleNeverShrinksAsBucketsWiden() {
        for metric in MetricType.allCases {
            var previous: TimeInterval = 0
            for bucket in [BucketSize.raw, .hour, .day, .week, .month] {
                let gap = metric.maxPlottableGap(bucket: bucket)
                XCTAssertGreaterThan(gap, 0, "\(metric) at \(bucket)")
                XCTAssertGreaterThanOrEqual(gap, previous, "\(metric) shrank at \(bucket)")
                previous = gap
            }
        }
    }
}

/// Which gaps may be crossed with an inferred, dashed connector — roadmap item
/// 4b. Bounded twice: by a multiple of the metric's own honest join distance, and
/// by a fraction of the visible window, so a zoomed-out chart can never be mostly
/// inference.
final class SeriesBridgingTests: XCTestCase {

    private func run(_ dayOffsets: [Double]) -> [AggregatedPoint] {
        dayOffsets.map {
            AggregatedPoint(date: segBase.addingTimeInterval($0 * segDay),
                            value: 60 + $0, mean: 60 + $0, median: 60 + $0,
                            min: 60, max: 61, count: 1)
        }
    }

    private func bridges(_ dayOffsets: [Double], metric: MetricType = .restingHeartRate,
                         windowDays: Double = 30) -> [GapBridge] {
        let runs = run(dayOffsets).segments(for: metric, bucket: .day)
        return SeriesBridging.bridges(across: runs, metric: metric, bucket: .day,
                                      window: windowDays * segDay)
    }

    func testAModestGapIsBridgedAndALongOneIsNot() {
        XCTAssertEqual(bridges([0, 1, 2, 6, 7]).count, 1, "a four-day hole should bridge")
        XCTAssertEqual(bridges([0, 1, 2, 10, 11]).count, 0, "an eight-day hole should not")
    }

    /// The geometry clause: the same gap bridges on a month view and not on a
    /// week view, because a dashed stretch filling a third of the chart asserts
    /// more than it should.
    func testABridgeNeverSpansAQuarterOfTheWindow() {
        XCTAssertEqual(bridges([0, 1, 6, 7], windowDays: 7).count, 0)
        XCTAssertEqual(bridges([0, 1, 6, 7], windowDays: 30).count, 1)
    }

    func testABridgeCarriesTheRealEndpoints() throws {
        let bridge = try XCTUnwrap(bridges([0, 1, 2, 6, 7]).first)
        XCTAssertEqual(bridge.start, segBase.addingTimeInterval(2 * segDay))
        XCTAssertEqual(bridge.end, segBase.addingTimeInterval(6 * segDay))
        XCTAssertEqual(bridge.startValue, 62)
        XCTAssertEqual(bridge.endValue, 66)
        XCTAssertEqual(bridge.duration, 4 * segDay)
    }

    func testAContinuousRunHasNoBridges() {
        XCTAssertTrue(bridges([0, 1, 2, 3, 4]).isEmpty)
    }

    /// The invariant a future tweak to the constants must not break: nothing that
    /// was measured may sit inside an inferred span.
    func testBridgesNeverOverlapADrawnSegment() {
        let offsets: [Double] = [0, 1, 2, 7, 8, 40]
        let runs = run(offsets).segments(for: .restingHeartRate, bucket: .day)
        XCTAssertEqual(runs.count, 3)
        let spans = SeriesBridging.bridges(across: runs, metric: .restingHeartRate,
                                           bucket: .day, window: 30 * segDay)
        XCTAssertEqual(spans.count, 1, "the five-day hole bridges, the 32-day one does not")
        for span in spans {
            for point in runs.flatMap({ $0 }) {
                XCTAssertFalse(point.date > span.start && point.date < span.end,
                               "a measured point sits inside an inferred span")
            }
        }
    }

    /// When the window clause falls below the join rule, nothing bridges. Self
    /// consistent, and it needs no special case.
    func testATinyWindowBridgesNothing() {
        XCTAssertTrue(bridges([0, 1, 2, 6, 7], windowDays: 2).isEmpty)
    }
}

/// The overlay chart's half of roadmap 4b. It broke at every gap while the
/// metric-detail chart bridged them, so the same silence rendered two different
/// ways depending on which screen you were on.
final class OverlayBridgingTests: XCTestCase {

    private func points(_ dayOffsets: [Double]) -> [NormalizedPoint] {
        dayOffsets.map {
            NormalizedPoint(date: segBase.addingTimeInterval($0 * segDay),
                            z: $0 < 3 ? 0.2 : 2.6, raw: 60 + $0)
        }
    }

    private func pairs(_ dayOffsets: [Double], windowDays: Double = 30)
        -> [(from: NormalizedPoint, to: NormalizedPoint)] {
        let series = NormalizedSeries(metric: .restingHeartRate, higherIsBetter: false,
                                      points: points(dayOffsets), baseline: 60)
        return SeriesBridging.bridgePairs(across: series.segments(),
                                          metric: .restingHeartRate, bucket: .day,
                                          window: windowDays * segDay, date: \.date)
    }

    /// The same two bounds the `AggregatedPoint` version obeys — the point of
    /// making the pairing generic was that there is one rule, not two.
    func testTheOverlayObeysTheSameBoundsAsTheDetailChart() {
        XCTAssertEqual(pairs([0, 1, 2, 6, 7]).count, 1, "a four-day hole should bridge")
        XCTAssertEqual(pairs([0, 1, 2, 10, 11]).count, 0, "an eight-day hole should not")
        XCTAssertEqual(pairs([0, 1, 6, 7], windowDays: 7).count, 0, "a quarter of a week")
    }

    func testABridgeCarriesTheRealEndpointsWithTheirZScores() throws {
        let bridge = try XCTUnwrap(pairs([0, 1, 2, 6, 7]).first)
        XCTAssertEqual(bridge.from.date, segBase.addingTimeInterval(2 * segDay))
        XCTAssertEqual(bridge.to.date, segBase.addingTimeInterval(6 * segDay))
        // The z-scores are the reason this returns the points rather than a
        // `GapBridge`: the overlay encodes anomaly as opacity, and a flattened
        // two-dates-two-values struct cannot carry that.
        XCTAssertEqual(bridge.from.z, 0.2, accuracy: 0.0001)
        XCTAssertEqual(bridge.to.z, 2.6, accuracy: 0.0001)
    }

    func testAContinuousRunIsNeverBridged() {
        XCTAssertTrue(pairs([0, 1, 2, 3, 4]).isEmpty)
    }

    /// The decision the audit left open: how a dashed span interacts with the
    /// overlay's per-span opacity encoding.
    ///
    /// The quieter end wins. Everywhere else a span is as prominent as its more
    /// anomalous end, because both ends were measured. A bridge was measured
    /// nowhere, so taking the maximum would let one spike pull a week of silence
    /// forward as though something had been observed in it.
    func testAnInferredSpanIsNeverLouderThanItsQuieterEnd() {
        let loud = 0.9, quiet = 0.2
        let prominence = SeriesBridging.bridgeProminence(from: quiet, to: loud)
        XCTAssertLessThanOrEqual(prominence, quiet)
        XCTAssertEqual(prominence,
                       SeriesBridging.bridgeProminence(from: loud, to: quiet),
                       "which end is which must not matter")
    }

    /// And it is always dimmer than the measured span it continues, so dash is
    /// not the only thing separating inference from measurement.
    func testAnInferredSpanIsDimmerThanEitherMeasuredEnd() {
        for (a, b) in [(0.2, 0.9), (0.5, 0.5), (1.0, 0.12)] {
            XCTAssertLessThan(SeriesBridging.bridgeProminence(from: a, to: b),
                              Swift.min(a, b))
        }
    }
}
