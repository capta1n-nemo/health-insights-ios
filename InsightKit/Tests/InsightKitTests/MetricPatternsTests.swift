import XCTest
@testable import InsightKit

private let patternNow = Date(timeIntervalSince1970: 1_700_000_000)
private var patternCalendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func patternDay(_ i: Int) -> Date {
    patternCalendar.startOfDay(for: patternNow.addingTimeInterval(-Double(i) * 86_400))
        .addingTimeInterval(12 * 3600)
}

final class CorrelationTests: XCTestCase {
    func testPerfectPositiveAndNegativeRelations() {
        let x = [1.0, 2, 3, 4, 5]
        XCTAssertEqual(Baseline.correlation(x: x, y: [2.0, 4, 6, 8, 10])!, 1, accuracy: 1e-9)
        XCTAssertEqual(Baseline.correlation(x: x, y: [10.0, 8, 6, 4, 2])!, -1, accuracy: 1e-9)
    }

    func testKnownIntermediateValue() {
        // Hand-computed: dx = [-2,-1,0,1,2], dy = [-1,-2,1,0,2]
        // sxy = 8, sxx = 10, syy = 10 → r = 8/√100 = 0.8
        let r = Baseline.correlation(x: [1, 2, 3, 4, 5], y: [2, 1, 4, 3, 5])
        XCTAssertEqual(r!, 0.8, accuracy: 1e-9)
    }

    func testNoSpreadOrTooFewPointsGivesNil() {
        XCTAssertNil(Baseline.correlation(x: [1, 1, 1, 1], y: [1, 2, 3, 4]))
        XCTAssertNil(Baseline.correlation(x: [1, 2], y: [1, 2]))
        XCTAssertNil(Baseline.correlation(x: [1, 2, 3], y: [1, 2]))
    }

    func testResultNeverEscapesTheValidRange() {
        let big = (0..<50).map { Double($0) * 1_000_000 }
        let r = Baseline.correlation(x: big, y: big)
        XCTAssertLessThanOrEqual(r!, 1)
        XCTAssertGreaterThanOrEqual(r!, -1)
    }
}

final class NormalizedSeriesTests: XCTestCase {

    private func daily(_ metric: MetricType, _ values: [Double]) -> [HealthMetricSample] {
        values.enumerated().map { offset, value in
            HealthMetricSample(type: metric, value: value,
                               start: patternDay(values.count - 1 - offset), source: .oura)
        }
    }

    private var window: ClosedRange<Date> {
        patternDay(60)...patternNow.addingTimeInterval(3600)
    }

    /// The point of the whole exercise: hours and percent land on one axis.
    func testUnlikeUnitsBecomeComparable() {
        let samples = daily(.sleepDurationHours, [6, 6.5, 7, 7.5, 8, 8.5, 9])
            + daily(.oxygenSaturation, [99, 98, 97, 96, 95, 94, 93])
        let series = SeriesNormalizer.series(
            for: [.init(metric: .sleepDurationHours, higherIsBetter: true, weight: 0.5, detail: ""),
                  .init(metric: .oxygenSaturation, higherIsBetter: true, weight: 0.5, detail: "")],
            samples: samples, range: window, calendar: patternCalendar)

        XCTAssertEqual(series.count, 2)
        // Both series span a similar number of standard deviations despite one
        // being measured in hours and the other in percent.
        for one in series {
            let zs = one.points.map(\.z)
            XCTAssertEqual(zs.min()!, -1.5, accuracy: 0.2)
            XCTAssertEqual(zs.max()!, 1.5, accuracy: 0.2)
        }
        // And the raw values survive for the "Raw" toggle.
        XCTAssertEqual(series.first { $0.metric == .sleepDurationHours }?.points.last?.raw, 9)
    }

    func testAFlatSeriesIsDroppedRatherThanDividedByZero() {
        let samples = daily(.respiratoryRate, [14, 14, 14, 14, 14])
        let series = SeriesNormalizer.series(
            for: [.init(metric: .respiratoryRate, higherIsBetter: false, weight: 1, detail: "")],
            samples: samples, range: window, calendar: patternCalendar)
        XCTAssertTrue(series.isEmpty)
    }

    func testBaselineIsTheWindowMeanSoZeroMeansTypical() {
        let samples = daily(.restingHeartRate, [50, 55, 60, 65, 70])
        let series = SeriesNormalizer.series(
            for: [.init(metric: .restingHeartRate, higherIsBetter: false, weight: 1, detail: "")],
            samples: samples, range: window, calendar: patternCalendar)
        XCTAssertEqual(series.first?.baseline ?? 0, 60, accuracy: 1e-9)
        // The middle reading sits exactly on the baseline.
        XCTAssertEqual(series.first?.points[2].z ?? 1, 0, accuracy: 1e-9)
    }

    /// A daily-bucketed series must not be shattered by `maxValidInterval`,
    /// which is 30 minutes for heart rate — shorter than a bucket.
    func testDailyBucketsAreNotBrokenByAHighFrequencyMetricsGapRule() {
        let samples = daily(.heartRate, [60, 62, 64, 66, 68, 70])
        let series = SeriesNormalizer.series(
            for: [.init(metric: .heartRate, higherIsBetter: false, weight: 0, detail: "")],
            samples: samples, range: window, calendar: patternCalendar)
        XCTAssertEqual(series.first?.segments().count, 1)
    }

    func testLogScaleIsRefusedWhenASeriesCanBeNegative() {
        let samples = daily(.skinTemperatureDeviation, [-0.3, 0.1, 0.4, -0.2, 0.6])
        let series = SeriesNormalizer.series(
            for: [.init(metric: .skinTemperatureDeviation, higherIsBetter: nil, weight: 0, detail: "")],
            samples: samples, range: window, calendar: patternCalendar)
        XCTAssertFalse(series.supportsLogScale)
    }
}

final class PatternFinderTests: XCTestCase {

    private func series(_ metric: MetricType, _ values: [Double],
                        higherIsBetter: Bool? = nil) -> NormalizedSeries {
        let mean = Baseline.mean(values)!
        let sd = Baseline.standardDeviation(values)!
        let points = values.enumerated().map { offset, value in
            NormalizedPoint(date: patternDay(values.count - 1 - offset),
                            z: (value - mean) / sd, raw: value)
        }
        return NormalizedSeries(metric: metric, higherIsBetter: higherIsBetter,
                                points: points, baseline: mean)
    }

    /// The user's own example: sleep going up while blood oxygen goes down.
    func testOppositeTrendsAreReportedAsADivergence() {
        let rising = Array(stride(from: 6.0, through: 9.0, by: 0.1))       // 31 days
        let falling = Array(stride(from: 99.0, through: 96.0, by: -0.1))
        let found = PatternFinder.patterns(
            in: [series(.sleepDurationHours, rising, higherIsBetter: true),
                 series(.oxygenSaturation, falling, higherIsBetter: true)],
            calendar: patternCalendar)

        let divergence = found.first { $0.kind == .divergence }
        XCTAssertNotNil(divergence)
        XCTAssertEqual(divergence?.a, .sleepDurationHours, "the rising metric is named first")
        XCTAssertEqual(divergence?.b, .oxygenSaturation)
        XCTAssertTrue(divergence!.sentence.contains("Sleep Duration"))
        XCTAssertTrue(divergence!.sentence.contains("blood oxygen"))
    }

    func testTooFewDaysReportsNothing() {
        let short = [1.0, 2, 3, 4, 5, 6]
        let found = PatternFinder.patterns(
            in: [series(.sleepDurationHours, short),
                 series(.oxygenSaturation, Array(short.reversed()))],
            calendar: patternCalendar)
        XCTAssertTrue(found.isEmpty)
    }

    func testWeakCorrelationsAreSuppressed() {
        // Same direction (so no divergence) but unrelated day to day. Two
        // different families, so the suppression under test is the r floor and
        // not the family rule.
        let a = (0..<30).map { Double($0 % 7) + Double($0) * 0.01 }
        let b = (0..<30).map { Double(($0 * 3) % 5) + Double($0) * 0.01 }
        let found = PatternFinder.patterns(
            in: [series(.respiratoryRate, a), series(.restingHeartRate, b)],
            minimumMagnitude: 0.95, calendar: patternCalendar)
        XCTAssertTrue(found.filter { $0.kind == .coMovement }.isEmpty)
    }

    /// "On days when heart rate changes, resting heart rate tends to as well
    /// (r = 0.75)" reached the screen. It is a fact about how resting heart rate
    /// is derived, not an observation about the person, and it displaced real
    /// cross-system findings.
    func testTautologicalSameFamilyPairsAreNotReported() {
        let base = (0..<30).map { Double(($0 * 7) % 11) }
        let found = PatternFinder.patterns(
            in: [series(.heartRate, base),
                 series(.restingHeartRate, base.map { $0 * 0.8 + 40 })],
            calendar: patternCalendar)
        XCTAssertTrue(found.filter { $0.kind == .coMovement }.isEmpty,
                      "heart rate and resting heart rate are one family")
    }

    /// The sentence claims a superlative, so only one metric may carry it.
    /// Two were being emitted, both saying "more closely than the others".
    func testOnlyTheStrongestDriverIsReported() {
        let a = (0..<30).map { Double(($0 * 5) % 13) }
        let b = (0..<30).map { Double(($0 * 5) % 13) * 0.9 + 1 }
        let scores = a.enumerated().map { offset, value in
            ScorePoint(date: patternDay(a.count - 1 - offset), score: 40 + value * 3,
                       confidence: .high, contributorCount: 4)
        }
        let found = PatternFinder.patterns(
            in: [series(.sleepDurationHours, a), series(.oxygenSaturation, b)],
            against: scores, calendar: patternCalendar)
        XCTAssertEqual(found.filter { $0.kind == .driver }.count, 1)
    }

    func testAcronymsSurviveMidSentence() {
        XCTAssertEqual(MetricType.heartRateVariabilityRMSSD.inSentence, "HRV (rMSSD)")
        XCTAssertEqual(MetricType.heartRateVariabilitySDNN.inSentence, "HRV (SDNN)")
        XCTAssertEqual(MetricType.oxygenSaturation.inSentence, "blood oxygen")
        XCTAssertEqual(MetricType.restingHeartRate.inSentence, "resting heart rate")
        // Ordinary words fall to lower case; the bracketed acronym does not.
        XCTAssertEqual(MetricType.vo2Max.inSentence, "cardio fitness (VO₂max)")
    }

    func testCoMovementIsFoundBetweenTwoSignalsThatTrackEachOther() {
        let base = (0..<30).map { Double(($0 * 7) % 11) }
        let found = PatternFinder.patterns(
            in: [series(.restingHeartRate, base),
                 series(.respiratoryRate, base.map { $0 * 2 + 1 })],
            calendar: patternCalendar)
        let co = found.first { $0.kind == .coMovement }
        XCTAssertNotNil(co)
        XCTAssertEqual(co!.statistic, 1, accuracy: 1e-6)
        XCTAssertTrue(co!.sentence.contains("association, not a cause"),
                      "every correlation must carry its caveat")
    }

    func testAMetricTrackingTheScoreIsReportedAsADriver() {
        let values = (0..<30).map { Double(($0 * 5) % 13) }
        let scores = values.enumerated().map { offset, value in
            ScorePoint(date: patternDay(values.count - 1 - offset),
                       score: 40 + value * 3, confidence: .high, contributorCount: 4)
        }
        let found = PatternFinder.patterns(
            in: [series(.sleepDurationHours, values, higherIsBetter: true)],
            against: scores, calendar: patternCalendar)
        let driver = found.first { $0.kind == .driver }
        XCTAssertNotNil(driver)
        XCTAssertEqual(driver?.a, .sleepDurationHours)
        XCTAssertNil(driver?.b)
        XCTAssertGreaterThan(driver!.statistic, 0.9)
    }

    func testOnlyAHandfulOfPatternsAreReturned() {
        let many = (0..<6).map { i in
            series(MetricType.allCases[i], (0..<30).map { Double($0) * (i.isMultiple(of: 2) ? 1 : -1) })
        }
        let found = PatternFinder.patterns(in: many, limit: 3, calendar: patternCalendar)
        XCTAssertLessThanOrEqual(found.count, 3)
    }
}
