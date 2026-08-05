import XCTest
@testable import InsightKit

private let readerNow = TestClock.now
private let readerCalendar = TestClock.utc
private func readerDay(_ daysAgo: Int) -> Date { TestClock.day(daysAgo) }

/// Which device's reading `VitalReader` speaks for, when several measured the
/// same vital.
///
/// The rule used to be "most history wins", full stop — which has it backwards
/// at the top: a device that stopped reporting last week has the *most*
/// established baseline and the *weakest* claim on describing today. `VitalReader`
/// would return that stale reading, correctly labelled `isFresh: false`, while a
/// fresh reading sat unreachable in the same sample set. Callers that drop a
/// stale component — Readiness does — lost the signal entirely.
///
/// Every fixture in the existing suite is single-source or all-fresh, which is
/// exactly why none of them caught it.
final class VitalReaderSelectionTests: XCTestCase {

    private func series(_ metric: MetricType, _ values: [Double],
                        source: MetricSource, endingDaysAgo: Int = 0) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(
                type: metric, value: value,
                start: readerDay(endingDaysAgo + values.count - 1 - index),
                source: source)
        }
    }

    private func read(_ samples: [HealthMetricSample],
                      _ metric: MetricType = .heartRateVariabilityRMSSD) -> VitalReading? {
        VitalReader.reading(metric, from: samples, now: readerNow, calendar: readerCalendar)
    }

    /// The bug, exactly: a long-quiet ring against a short-but-current watch.
    func testAFreshSourceBeatsAStaleOneWithMoreHistory() {
        var samples = series(.heartRateVariabilityRMSSD, Array(repeating: 62, count: 20),
                             source: .oura, endingDaysAgo: 5)
        samples += series(.heartRateVariabilityRMSSD, Array(repeating: 50, count: 6),
                          source: .appleHealthDevice("Apple Watch"))
        let reading = read(samples)
        XCTAssertEqual(reading?.value, 50, "the quiet ring outvoted the watch reporting today")
        XCTAssertTrue(try XCTUnwrap(reading?.isFresh))
    }

    /// Among sources that are equally fresh, the best-established spread still
    /// wins — that half of the old rule was right and must survive.
    func testAmongFreshSourcesTheMostHistoryStillWins() {
        var samples = series(.heartRateVariabilityRMSSD, Array(repeating: 62, count: 20),
                             source: .oura)
        samples += series(.heartRateVariabilityRMSSD, Array(repeating: 50, count: 6),
                          source: .appleHealthDevice("Apple Watch"))
        XCTAssertEqual(read(samples)?.value, 62)
    }

    /// When everything is stale, the reader still answers — "we have a number we
    /// can't vouch for" and "we have nothing" are different, and the caller
    /// decides. It picks the most recent of them.
    func testWhenEverySourceIsStaleTheNewestWins() {
        var samples = series(.heartRateVariabilityRMSSD, Array(repeating: 62, count: 20),
                             source: .oura, endingDaysAgo: 30)
        samples += series(.heartRateVariabilityRMSSD, Array(repeating: 50, count: 6),
                          source: .appleHealthDevice("Apple Watch"), endingDaysAgo: 10)
        let reading = read(samples)
        XCTAssertEqual(reading?.value, 50)
        XCTAssertFalse(try XCTUnwrap(reading?.isFresh))
    }

    /// `VitalReader` and `VitalSignsCheck` must agree about which device speaks.
    /// They are one rule, and `VitalSignsCheck` was the one that had it right.
    func testTheReaderAgreesWithVitalsCheckOnSourceSelection() {
        var samples = series(.restingHeartRate, Array(repeating: 62, count: 20),
                             source: .oura, endingDaysAgo: 5)
        samples += series(.restingHeartRate, Array(repeating: 50, count: 8),
                          source: .appleHealthDevice("Apple Watch"))
        let reader = VitalReader.reading(.restingHeartRate, from: samples,
                                         now: readerNow, calendar: readerCalendar)
        let check = VitalSignsCheck.evaluate(samples: samples, now: readerNow,
                                             calendar: readerCalendar)
            .readings.first { $0.metric == .restingHeartRate }
        XCTAssertEqual(reader?.sourceName, check?.sourceName)
        XCTAssertEqual(reader?.value, check?.value)
    }
}

/// A regression needs x. `dailyValues` throws the dates away, and fitting its
/// output against `0, 1, 2, …` compiles, runs, and silently answers a different
/// question — one measured VO₂max series with a gap in it gave 160 mL/kg·min per
/// year where the truth was 10.
final class VitalReaderDailySeriesTests: XCTestCase {

    private func sample(_ value: Double, daysAgo: Int,
                        source: MetricSource = .appleHealth) -> HealthMetricSample {
        HealthMetricSample(type: .vo2Max, value: value, start: readerDay(daysAgo), source: source)
    }

    func testDatesSurviveAndAreOldestFirst() {
        let samples = [sample(44, daysAgo: 0), sample(42, daysAgo: 140), sample(43, daysAgo: 7)]
        let series = VitalReader.dailySeries(.vo2Max, from: samples,
                                             now: readerNow, calendar: readerCalendar)
        XCTAssertEqual(series.map(\.value), [42, 43, 44])
        XCTAssertEqual(series.map(\.date), series.map(\.date).sorted())
    }

    /// The whole reason the dated variant exists: index spacing and date spacing
    /// disagree wildly across a gap.
    func testASeriesWithAGapIsNotEvenlySpaced() throws {
        let samples = [sample(40, daysAgo: 200), sample(41, daysAgo: 193),
                       sample(44, daysAgo: 7), sample(45, daysAgo: 0)]
        let series = VitalReader.dailySeries(.vo2Max, from: samples,
                                             now: readerNow, calendar: readerCalendar)
        let first = try? XCTUnwrap(series.first?.date)
        let byDate = Baseline.linearRegression(
            x: series.map { $0.date.timeIntervalSince(first ?? readerNow) / 86_400 },
            y: series.map(\.value))
        let byIndex = Baseline.linearRegression(
            x: (0..<series.count).map(Double.init), y: series.map(\.value))
        let perYearByDate = try XCTUnwrap(byDate?.slope) * 365.25
        let perYearByIndex = try XCTUnwrap(byIndex?.slope) * 365.25
        XCTAssertLessThan(abs(perYearByDate), 15, "a real VO₂max slope is single digits")
        XCTAssertGreaterThan(abs(perYearByIndex), 100,
                             "index spacing is meant to be badly wrong here")
    }

    /// The undated variant is now defined in terms of the dated one, so they can
    /// never disagree about what a day's value is.
    func testTheUndatedVariantIsTheSameValues() {
        let samples = [sample(44, daysAgo: 0), sample(42, daysAgo: 20), sample(43, daysAgo: 7)]
        XCTAssertEqual(
            VitalReader.dailyValues(.vo2Max, from: samples, days: 60,
                                    now: readerNow, calendar: readerCalendar),
            VitalReader.dailySeries(.vo2Max, from: samples, days: 60,
                                    now: readerNow, calendar: readerCalendar).map(\.value))
    }

    /// ⚠️ **This used to assert the mean of two instruments, and that was the
    /// defect** — roadmap #27's last open half. It was written under the name
    /// "devices are merged by day", which conflated two different questions:
    ///
    /// - *Two delivery paths for one device is one reading, not two.* True, and
    ///   `MultiSource.collapseMirrors` owns it — before this function ever runs.
    /// - *Two different instruments on one day.* Not a merge. They are two
    ///   measurements of one quantity by devices that disagree, and averaging
    ///   them makes the series' level track which devices happened to report.
    ///
    /// Measured on the reader's export: 36.5% of 211 resting-heart-rate days
    /// carry more than one source, and the radar's `isLeaning` flipped on 7.3%
    /// of (day, metric) pairs because of it.
    func testTwoInstrumentsOnOneDayAreNotAveraged() {
        let samples = [sample(44, daysAgo: 0, source: .oura),
                       sample(46, daysAgo: 0, source: .appleHealth)]
        let series = VitalReader.dailySeries(.vo2Max, from: samples,
                                             now: readerNow, calendar: readerCalendar)
        XCTAssertEqual(series.count, 1)
        let value = try? XCTUnwrap(series.first?.value)
        XCTAssertNotEqual(value, 45, "the two instruments were averaged")
        XCTAssertTrue(value == 44 || value == 46, "the value came from neither instrument")
    }

    /// And a tie is resolved the same way every time. Two instruments with one
    /// day each, the same day: whichever wins, it must keep winning, or the
    /// chart changes between launches on identical data.
    func testATotalTieIsStillDeterministic() {
        let samples = [sample(44, daysAgo: 0, source: .oura),
                       sample(46, daysAgo: 0, source: .appleHealth)]
        let first = VitalReader.dailySeries(.vo2Max, from: samples,
                                            now: readerNow, calendar: readerCalendar)
        for _ in 0..<20 {
            XCTAssertEqual(VitalReader.dailySeries(.vo2Max, from: samples.shuffled(),
                                                   now: readerNow, calendar: readerCalendar)
                            .map(\.value),
                           first.map(\.value),
                           "the winner changed when the input order did")
        }
    }
}
