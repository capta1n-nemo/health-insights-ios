import XCTest
@testable import InsightKit

/// Covers the pure model layer added for the metric-detail restructure:
/// chart windows, presentation categories, aggregation, activity and formatting.
final class PresentationTests: XCTestCase {

    private func sample(_ v: Double, _ type: MetricType = .bodyMass,
                        daysAgo: Double, source: MetricSource = .withings) -> HealthMetricSample {
        HealthMetricSample(type: type, value: v,
                           start: Date().addingTimeInterval(-daysAgo * 24 * 3600),
                           source: source)
    }

    // MARK: - Chart window (the All/Y squish)

    /// The bug: `.all` used a fixed ~12-year constant, so 90 days of data was
    /// drawn into a decade-wide viewport and squashed against the left edge.
    func testAllTimeWindowFollowsTheDataRatherThanAFixedConstant() {
        let ninetyDays: TimeInterval = 90 * 24 * 3600
        let window = Timeframe.all.chartWindow(spanning: ninetyDays)
        XCTAssertEqual(window, ninetyDays * 1.02, accuracy: 1)
        XCTAssertLessThan(window, 365 * 24 * 3600)   // nowhere near 12 years
    }

    func testAllTimeWindowClampsWhenThereIsNoData() {
        XCTAssertEqual(Timeframe.all.chartWindow(spanning: nil),
                       Timeframe.minimumChartWindow)
        XCTAssertEqual(Timeframe.all.chartWindow(spanning: 0),
                       Timeframe.minimumChartWindow)
    }

    func testFixedTimeframesIgnoreTheDataSpan() {
        let tiny: TimeInterval = 60
        XCTAssertEqual(Timeframe.month.chartWindow(spanning: tiny), Timeframe.month.window)
        XCTAssertEqual(Timeframe.year.chartWindow(spanning: nil), Timeframe.year.window)
    }

    func testTickGranularityWidensWithSpan() {
        let day: TimeInterval = 24 * 3600
        XCTAssertEqual(Timeframe.tickGranularity(forSpan: 6 * 3600), .hour)
        XCTAssertEqual(Timeframe.tickGranularity(forSpan: 10 * day), .day)
        XCTAssertEqual(Timeframe.tickGranularity(forSpan: 200 * day), .month)
        XCTAssertEqual(Timeframe.tickGranularity(forSpan: 1000 * day), .year)
    }

    // MARK: - Presentation categories

    func testEveryMetricHasAPresentation() {
        for metric in MetricType.allCases {
            _ = metric.presentation      // exhaustive switch; would trap if not
            XCTAssertGreaterThan(metric.maxValidInterval, 0, "\(metric)")
        }
    }

    func testHeightIsAStaticAttributeAndDrawsNoChart() {
        XCTAssertTrue(MetricType.height.isStaticAttribute)
        XCTAssertFalse(MetricType.height.presentation.showsChart)
        XCTAssertFalse(MetricType.height.presentation.allowsTimeframeSelection)
    }

    func testWeightUsesMedianAndStepsUseSum() {
        XCTAssertEqual(MetricType.bodyMass.bucketStatistic, .median)
        XCTAssertEqual(MetricType.stepCount.bucketStatistic, .sum)
        XCTAssertEqual(MetricType.heartRate.bucketStatistic, .mean)
    }

    /// Sleep arrives as one value a night, so totalling it is meaningless.
    func testSleepIsARangeNotADailyTotal() {
        XCTAssertEqual(MetricType.sleepDurationHours.presentation, .fluctuatingRange)
        XCTAssertEqual(MetricType.activeEnergyBurned.presentation, .cumulativeTotal)
    }

    // MARK: - Subject

    func testEitherHalfOfACuffReadingResolvesToThePairedSubject() {
        XCTAssertEqual(MetricSubject(metric: .bloodPressureSystolic), .bloodPressure)
        XCTAssertEqual(MetricSubject(metric: .bloodPressureDiastolic), .bloodPressure)
        XCTAssertEqual(MetricSubject.bloodPressure.metrics,
                       [.bloodPressureSystolic, .bloodPressureDiastolic])
        XCTAssertEqual(MetricSubject.bloodPressure.displayName, "Blood Pressure")
    }

    func testOrdinaryMetricsPassThrough() {
        XCTAssertEqual(MetricSubject(metric: .bodyMass), .single(.bodyMass))
        XCTAssertEqual(MetricSubject(metric: .bodyMass).presentation, .cumulativeTrend)
    }

    // MARK: - Provenance

    func testOriginDistinguishesDirectApiFromTheAppleHealthBridge() {
        XCTAssertEqual(MetricSource.oura.origin, .directAPI)
        XCTAssertEqual(MetricSource.withings.origin, .directAPI)
        XCTAssertEqual(MetricSource.appleHealthDevice("Oura").origin, .appleHealth)
        XCTAssertEqual(MetricSource.appleHealthDevice("Apple Watch").origin, .appleWatch)
        XCTAssertEqual(MetricSource.manual.origin, .manual)
        XCTAssertEqual(MetricSource.document.origin, .document)
    }

    /// Persistence rebuilds a source from its id alone, so origin must survive
    /// losing the friendly display name.
    func testOriginSurvivesAPersistenceRoundTrip() {
        let restored = MetricSource(id: "apple_health/apple_watch",
                                    displayName: "apple_health/apple_watch")
        XCTAssertEqual(restored.origin, .appleWatch)
    }

    func testMergedSeriesReportsEveryPathItWasFedBy() {
        let series = SourceSeries(source: .oura, samples: [
            sample(60, .heartRate, daysAgo: 2, source: .oura),
            sample(61, .heartRate, daysAgo: 1, source: .appleHealthDevice("Oura"))
        ])
        XCTAssertEqual(series.origins, [.directAPI, .appleHealth])
        XCTAssertEqual(series.latestOrigin, .appleHealth)
    }

    // MARK: - Gap segmentation

    func testSeriesSplitsWhereReadingsAreTooFarApart() {
        let series = SourceSeries(source: .withings, samples: [
            sample(80, daysAgo: 40), sample(81, daysAgo: 39),
            sample(78, daysAgo: 2),  sample(77, daysAgo: 1)      // 37-day gap
        ])
        let segments = series.segments(maxGap: MetricType.bodyMass.maxValidInterval)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].count, 2)
        XCTAssertEqual(segments[1].count, 2)
    }

    func testContinuousSeriesIsOneSegment() {
        let series = SourceSeries(source: .withings, samples: [
            sample(80, daysAgo: 3), sample(81, daysAgo: 2), sample(80, daysAgo: 1)
        ])
        XCTAssertEqual(series.segments(maxGap: MetricType.bodyMass.maxValidInterval).count, 1)
    }

    // MARK: - Bucketing

    func testDailyBucketsUseTheMetricStatistic() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar(identifier: .gregorian)
        func at(_ hour: Double, _ v: Double) -> HealthMetricSample {
            HealthMetricSample(type: .bodyMass, value: v,
                               start: day.addingTimeInterval(hour * 3600),
                               source: .withings)
        }
        // 80, 90, 100 in one day: mean 90, median 90; an outlier day would
        // separate them, which is the point of the median rule for weight.
        let series = SourceSeries(source: .withings, samples: [at(1, 80), at(2, 90), at(3, 100)])
        let buckets = series.bucketed(by: .day, for: .bodyMass, calendar: cal)
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].median, 90, accuracy: 1e-9)
        XCTAssertEqual(buckets[0].mean, 90, accuracy: 1e-9)
        XCTAssertEqual(buckets[0].min, 80)
        XCTAssertEqual(buckets[0].max, 100)
        XCTAssertEqual(buckets[0].count, 3)
        XCTAssertEqual(buckets[0].value, buckets[0].median, accuracy: 1e-9)
    }

    func testStepsSumWithinADayRatherThanAveraging() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar(identifier: .gregorian)
        let series = SourceSeries(source: .appleHealthDevice("iPhone"), samples: (1...4).map {
            HealthMetricSample(type: .stepCount, value: 1000,
                               start: day.addingTimeInterval(Double($0) * 3600),
                               source: .appleHealthDevice("iPhone"))
        })
        let buckets = series.bucketed(by: .day, for: .stepCount, calendar: cal)
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets[0].value, 4000, accuracy: 1e-9)
        XCTAssertEqual(buckets[0].mean, 1000, accuracy: 1e-9)
    }

    func testRawBucketingReturnsEveryReading() {
        let series = SourceSeries(source: .withings, samples: [
            sample(80, daysAgo: 2), sample(81, daysAgo: 1)
        ])
        XCTAssertEqual(series.bucketed(by: .raw, for: .bodyMass).count, 2)
    }

    // MARK: - Active vs inactive sources

    /// The complaint that drove this: an old phone entry from years ago was
    /// still dragging the current average.
    func testASourceThatWentQuietIsExcludedFromTheCurrentAverage() {
        let breakdown = MultiSource.breakdown(.bodyMass, from: [
            sample(95, daysAgo: 900, source: .appleHealthDevice("MyFitnessPal")),
            sample(82, daysAgo: 1, source: .withings)
        ])
        let range = Date().addingTimeInterval(-1000 * 24 * 3600)...Date()
        let activity = breakdown.activity(in: range, recencyWindow: 30 * 24 * 3600)

        XCTAssertEqual(activity.active.count, 1)
        XCTAssertEqual(activity.inactive.count, 1)
        XCTAssertFalse(activity.canCompare)          // no honest discrepancy
        XCTAssertEqual(breakdown.consensus(over: activity.active)!, 82, accuracy: 1e-9)
        // Whereas the all-sources consensus is the misleading number.
        XCTAssertEqual(breakdown.consensusLatest!, 88.5, accuracy: 1e-9)
    }

    func testTwoLiveSourcesCanBeCompared() {
        let breakdown = MultiSource.breakdown(.bodyMass, from: [
            sample(84, daysAgo: 2, source: .appleHealthDevice("Apple Watch")),
            sample(82, daysAgo: 1, source: .withings)
        ])
        let range = Date().addingTimeInterval(-60 * 24 * 3600)...Date()
        let activity = breakdown.activity(in: range, recencyWindow: 30 * 24 * 3600)
        XCTAssertTrue(activity.canCompare)
        XCTAssertEqual(breakdown.spread(over: activity.active)!, 2, accuracy: 1e-9)
    }

    func testDateSpanCoversEverySource() {
        let breakdown = MultiSource.breakdown(.bodyMass, from: [
            sample(95, daysAgo: 100), sample(82, daysAgo: 1)
        ])
        let span = breakdown.dateSpan
        XCTAssertNotNil(span)
        XCTAssertEqual(span!.upperBound.timeIntervalSince(span!.lowerBound),
                       99 * 24 * 3600, accuracy: 60)
        XCTAssertNil(MultiSource.breakdown(.bodyMass, from: []).dateSpan)
    }

    // MARK: - Trend summary

    func testVelocityRecoversAKnownWeeklySlope() {
        // Losing exactly 0.5 kg a week for 8 weeks.
        let samples = (0..<8).map { week in
            sample(90 - 0.5 * Double(week), daysAgo: Double(56 - week * 7))
        }
        let trend = TrendSummary.make(from: samples)
        XCTAssertNotNil(trend)
        XCTAssertEqual(trend!.velocityPerWeek!, -0.5, accuracy: 0.02)
        XCTAssertEqual(trend!.delta, -3.5, accuracy: 1e-9)
        XCTAssertEqual(trend!.smoothed.count, samples.count)
    }

    func testFlatSeriesHasNoVelocity() {
        let samples = (0..<5).map { sample(80, daysAgo: Double(5 - $0)) }
        XCTAssertEqual(TrendSummary.make(from: samples)!.velocityPerWeek!, 0, accuracy: 1e-9)
    }

    func testSingleReadingSummarisesButCannotHaveAVelocity() {
        let trend = TrendSummary.make(from: [sample(80, daysAgo: 1)])
        XCTAssertNotNil(trend)
        XCTAssertNil(trend!.velocityPerWeek)
        XCTAssertEqual(trend!.delta, 0)
    }

    func testEmptySeriesHasNoTrend() {
        XCTAssertNil(TrendSummary.make(from: []))
    }

    // MARK: - Range summary

    func testRangeSummaryQuantiles() {
        let samples = (1...100).map { sample(Double($0), .heartRate, daysAgo: Double(101 - $0)) }
        let range = RangeSummary.make(from: samples)!
        XCTAssertEqual(range.min, 1)
        XCTAssertEqual(range.max, 100)
        XCTAssertEqual(range.median, 50.5, accuracy: 0.01)
        XCTAssertEqual(range.p10, 10.9, accuracy: 0.2)
        XCTAssertEqual(range.p90, 90.1, accuracy: 0.2)
        XCTAssertEqual(range.latest?.value, 100)
        XCTAssertEqual(range.latestPercentile!, 1.0, accuracy: 1e-9)
    }

    // MARK: - Daily totals

    func testDailyTotalsSumPerDayAndReportTheBestDay() {
        let cal = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        func step(_ v: Double, dayOffset: Double, hour: Double) -> HealthMetricSample {
            HealthMetricSample(type: .stepCount, value: v,
                               start: day.addingTimeInterval(dayOffset * 86_400 + hour * 3600),
                               source: .appleHealthDevice("iPhone"))
        }
        let series = SourceSeries(source: .appleHealthDevice("iPhone"), samples: [
            step(3000, dayOffset: 0, hour: 1), step(2000, dayOffset: 0, hour: 5),
            step(9000, dayOffset: 1, hour: 2)
        ])
        let totals = DailyTotals.bucket(series, calendar: cal)
        XCTAssertEqual(totals.count, 2)
        XCTAssertEqual(totals[0].total, 5000, accuracy: 1e-9)
        let summary = DailyTotals.summary(totals, now: day, calendar: cal)
        XCTAssertEqual(summary.windowTotal, 14_000, accuracy: 1e-9)
        XCTAssertEqual(summary.best?.total, 9000)
        XCTAssertEqual(summary.dailyAverage!, 7000, accuracy: 1e-9)
    }

    // MARK: - Formatting

    /// Height is stored in metres, and rounding it to an Int rendered 1.85 m
    /// as "2".
    func testHeightKeepsItsPrecisionInMetricLocales() {
        let text = MetricValueFormatter.string(1.85, .height, locale: Locale(identifier: "en_AU"))
        XCTAssertTrue(text.contains("185"), "expected centimetres, got \(text)")
        XCTAssertFalse(text.hasPrefix("2"), "height was rounded to a whole metre: \(text)")
    }

    func testHeightUsesFeetAndInchesInImperialLocales() {
        let text = MetricValueFormatter.string(1.85, .height, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(text.contains("ft") || text.contains("′") || text.contains("foot"),
                      "expected an imperial height, got \(text)")
    }

    func testOtherMetricsKeepTheirExistingFormatting() {
        XCTAssertEqual(MetricValueFormatter.string(62.4, .heartRate), "62")
        XCTAssertEqual(MetricValueFormatter.string(82.35, .bodyMass), "82.3")
        XCTAssertEqual(MetricValueFormatter.string(97, .oxygenSaturation), "97%")
    }

    // MARK: - Blood pressure additions

    func testMeanArterialPressure() {
        XCTAssertEqual(BloodPressureEstimator.meanArterialPressure(systolic: 120, diastolic: 80),
                       93.33, accuracy: 0.01)
    }

    func testCategoryBoundaries() {
        typealias C = BloodPressureEstimator.Category
        XCTAssertEqual(C.of(systolic: 118, diastolic: 76), .normal)
        XCTAssertEqual(C.of(systolic: 120, diastolic: 76), .elevated)
        XCTAssertEqual(C.of(systolic: 130, diastolic: 76), .stage1)
        XCTAssertEqual(C.of(systolic: 118, diastolic: 80), .stage1)   // higher of the two wins
        XCTAssertEqual(C.of(systolic: 140, diastolic: 76), .stage2)
        XCTAssertEqual(C.of(systolic: 180, diastolic: 76), .crisis)
        XCTAssertLessThan(C.normal, C.crisis)
    }

    /// The existing string API is used by the insight copy and must not drift.
    func testCategoryStringApiIsUnchanged() {
        XCTAssertEqual(BloodPressureEstimator.category(systolic: 135, diastolic: 85),
                       "Stage 1 hypertension")
        XCTAssertEqual(BloodPressureEstimator.category(systolic: 110, diastolic: 70), "Normal")
    }

    func testGroundingSplitAtThirtyDays() {
        let now = Date()
        func reading(daysAgo: Double) -> BloodPressureEstimator.Reading {
            .init(date: now.addingTimeInterval(-daysAgo * 24 * 3600),
                  systolic: 120, diastolic: 80, source: "Manual entry")
        }
        let (recent, earlier) = BloodPressureEstimator.split(
            [reading(daysAgo: 1), reading(daysAgo: 29.9), reading(daysAgo: 31)], now: now)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(earlier.count, 1)
    }
}
