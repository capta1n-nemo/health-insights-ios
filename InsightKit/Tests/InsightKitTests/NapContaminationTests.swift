import XCTest
@testable import InsightKit

/// The two defects the user's own data export surfaced.
///
/// Both were invisible from the code: the parser looked correct, the sanitizer
/// looked correct, and every existing test passed. What gave them away was the
/// *distribution* — a median sleep of 5.6 h with a minimum of 0.01 h, and a
/// resting heart rate reaching 119 against a median of 56. That is the argument
/// for the export existing, and these tests are what stops both coming back.
final class NapContaminationTests: XCTestCase {

    // MARK: - Naps are not nights

    private func payload(_ records: String) -> Data {
        Data(#"{"data":[\#(records)],"next_token":null}"#.utf8)
    }

    private let night = """
    {"day":"2026-07-20","type":"long_sleep","lowest_heart_rate":48,
     "average_hrv":62,"average_breath":14.2,"total_sleep_duration":27000}
    """
    private let nap = """
    {"day":"2026-07-20","type":"late_nap","lowest_heart_rate":94,
     "average_hrv":31,"average_breath":17.5,"total_sleep_duration":1200}
    """
    private let rest = """
    {"day":"2026-07-20","type":"rest","lowest_heart_rate":119,
     "total_sleep_duration":36}
    """

    /// The headline defect. Oura's `sleep` endpoint returns *segments*, and
    /// `bucketStatistic` averages same-day samples — so a 7.5 h night beside a
    /// 20-minute nap was reported to the user as a 4 h night.
    func testANapOnTheSameDayDoesNotHalveTheNight() throws {
        let samples = try OuraResponseParser.parseSleepUTC(payload("\(night),\(nap)"))
        let durations = samples.samples(of: .sleepDurationHours)
        XCTAssertEqual(durations.count, 1, "the nap must not become a second night")
        XCTAssertEqual(try XCTUnwrap(durations.first).value, 7.5, accuracy: 0.001)
    }

    /// A 36-second "rest" period was reaching the user as 0.01 hours of sleep.
    func testAThirtySixSecondRestPeriodIsNotANightsSleep() throws {
        let samples = try OuraResponseParser.parseSleepUTC(payload(rest))
        XCTAssertTrue(samples.samples(of: .sleepDurationHours).isEmpty)
    }

    /// The quieter half of the same bug, and the more damaging one: a nap's
    /// "lowest heart rate" is an *awake* heart rate, and it was being fed
    /// straight into the resting-HR series that five cards read.
    func testANapsHeartRateNeverBecomesARestingHeartRate() throws {
        let samples = try OuraResponseParser.parseSleepUTC(payload("\(night),\(nap),\(rest)"))
        let resting = samples.samples(of: .restingHeartRate).map(\.value)
        XCTAssertEqual(resting, [48], "only the night's sleeping low is a resting heart rate")
    }

    /// HRV and respiratory rate ride the same records and were equally polluted.
    func testTheOtherNightlySignalsAreFilteredToo() throws {
        let samples = try OuraResponseParser.parseSleepUTC(payload("\(night),\(nap)"))
        XCTAssertEqual(samples.samples(of: .heartRateVariabilityRMSSD).map(\.value), [62])
        XCTAssertEqual(samples.samples(of: .respiratoryRate).map(\.value), [14.2])
    }

    /// **The failure direction that matters.** An unrecognised or absent `type`
    /// is counted as a night. An allow-list would empty the sleep card the day
    /// Oura adds a value, and would do it silently — the same shape as the two
    /// guards this repo has already shipped with a wrong premise.
    func testAnUnknownOrAbsentTypeIsStillCountedAsANight() throws {
        for type in [#""type":"long_sleep","#, #""type":"sleep","#,
                     #""type":"some_future_value","#, ""] {
            let record = """
            {"day":"2026-07-20",\(type)"lowest_heart_rate":48,"total_sleep_duration":27000}
            """
            let samples = try OuraResponseParser.parseSleepUTC(payload(record))
            XCTAssertEqual(samples.samples(of: .sleepDurationHours).count, 1,
                           "type \(type.isEmpty ? "(absent)" : type) should count as a night")
        }
        XCTAssertTrue(OuraResponseParser.isNight(nil))
        XCTAssertTrue(OuraResponseParser.isNight("LONG_SLEEP"), "case-insensitive")
        XCTAssertFalse(OuraResponseParser.isNight("late_nap"))
    }

    /// Latency rides the same defence: a doze's near-instant onset must not
    /// become the night's figure. This is why the metric is emitted by the
    /// typed parser and not promoted from the generic pipeline, which cannot
    /// tell a nap segment from a night.
    func testANapsLatencyDoesNotBecomeTheNights() throws {
        let night = """
        {"day":"2026-07-20","type":"long_sleep","total_sleep_duration":27000,
         "latency":900}
        """
        let nap = """
        {"day":"2026-07-20","type":"late_nap","total_sleep_duration":1200,
         "latency":30}
        """
        let samples = try OuraResponseParser.parseSleepUTC(payload("\(night),\(nap)"))
        let latencies = samples.samples(of: .sleepLatencyMinutes)
        XCTAssertEqual(latencies.map(\.value), [15],
                       "one night, one latency, in minutes — the nap's 30 s is gone")
    }

    // MARK: - A morning re-sleep is part of the night (user ruling, 2026-08-02)

    /// The 07-29 shape from the user's own export: Oura closed the night at the
    /// first wake (4.3 h) and typed the 8:20 am return to bed `late_nap`, while
    /// Apple Health summed the same morning into 8.5 h. One night's sleep, per
    /// the user — so a nap-typed record that *begins before noon* joins the
    /// night's totals.
    func testAMorningReSleepJoinsTheNight() throws {
        let night = """
        {"day":"2026-07-29","type":"long_sleep","bedtime_start":"2026-07-29T02:53:00+00:00",
         "total_sleep_duration":15480}
        """
        let reSleep = """
        {"day":"2026-07-29","type":"late_nap","bedtime_start":"2026-07-29T08:20:00+00:00",
         "total_sleep_duration":15120}
        """
        let samples = try OuraResponseParser.parseSleepUTC(payload("\(night),\(reSleep)"))
        let durations = samples.samples(of: .sleepDurationHours)
        XCTAssertEqual(durations.count, 1)
        XCTAssertEqual(try XCTUnwrap(durations.first).value, 8.5, accuracy: 0.01,
                       "both blocks are one night's sleep")

        // The re-sleep still never provides the night's bedtime.
        let onsets = samples.samples(of: .sleepOnset)
        XCTAssertEqual(onsets.count, 1)
        XCTAssertEqual(try XCTUnwrap(onsets.first).value, 2.883, accuracy: 0.01,
                       "the onset is 02:53, not 08:20")
    }

    /// The narrowness that keeps the nap filter's original cases safe: an
    /// afternoon start is not a re-sleep, and a record with no start time
    /// cannot prove it was a morning.
    func testAnAfternoonNapStillDoesNotJoinTheNight() throws {
        let night = """
        {"day":"2026-07-20","type":"long_sleep","total_sleep_duration":27000}
        """
        let siesta = """
        {"day":"2026-07-20","type":"late_nap","bedtime_start":"2026-07-20T15:00:00+00:00",
         "total_sleep_duration":3600}
        """
        let samples = try OuraResponseParser.parseSleepUTC(payload("\(night),\(siesta)"))
        XCTAssertEqual(try XCTUnwrap(samples.samples(of: .sleepDurationHours).first).value,
                       7.5, accuracy: 0.001, "a siesta is still a nap")
    }

    /// An 8 pm nap encodes as −4.0 h, which is inside `SleepOnset.plausibleHours`,
    /// and `SleepOnset.samples` keeps the *earliest* segment of each night — so
    /// before the filter moved to the top of the loop, a nap outranked the real
    /// bedtime and silently became it. Sleep's regularity term scores the spread
    /// of exactly these values.
    func testAnEveningNapDoesNotBecomeTheBedtime() throws {
        let eveningNap = """
        {"day":"2026-07-20","type":"late_nap","bedtime_start":"2026-07-19T20:00:00+00:00",
         "total_sleep_duration":1800}
        """
        let realNight = """
        {"day":"2026-07-20","type":"long_sleep","bedtime_start":"2026-07-19T23:00:00+00:00",
         "total_sleep_duration":27000}
        """
        let onsets = try OuraResponseParser
            .parseSleepUTC(payload("\(eveningNap),\(realNight)"))
            .samples(of: .sleepOnset)
        XCTAssertEqual(onsets.count, 1)
        // −1.0 is 23:00. −4.0 would be the nap.
        XCTAssertEqual(try XCTUnwrap(onsets.first).value, -1, accuracy: 0.001,
                       "the nap must not outrank the real bedtime")
    }

    // MARK: - One artefact must not set the baseline

    private func sample(_ type: MetricType, _ value: Double) -> HealthMetricSample {
        HealthMetricSample(type: type, value: value, start: Date(), source: .oura)
    }

    /// **The 119 bpm the export exposed is not caught here, and that is correct.**
    ///
    /// It was tempting to set the resting-heart-rate ceiling just under it. That
    /// would have been fitting the bound to one user's artefact: 119 bpm is a
    /// perfectly possible resting heart rate for someone in atrial fibrillation
    /// or acutely unwell, and rejecting it would delete the single most important
    /// reading the app could ever receive.
    ///
    /// The 119 is an artefact because of *where it came from* — a `rest` record —
    /// not because of its value, and `testANapsHeartRateNeverBecomesARestingHeartRate`
    /// above is what removes it. This bound exists for the values no living
    /// person produces at all.
    func testTheRestingHeartRateBoundRejectsTheImpossibleNotTheAlarming() {
        XCTAssertEqual([sample(.restingHeartRate, 119)].sanitizedVitals().count, 1,
                       "119 bpm is possible in AF — the nap filter removes this one, not the bound")
        XCTAssertEqual([sample(.restingHeartRate, 200)].sanitizedVitals().count, 0,
                       "200 bpm is not a resting heart rate under any circumstances")
        XCTAssertEqual([sample(.restingHeartRate, 0)].sanitizedVitals().count, 0)
    }

    /// **The bound must never reject bad news.** A resting heart rate of 95 is a
    /// finding the user needs, not an artefact — the whole point of the range is
    /// that it is a survival limit, not a clinical one.
    func testAHighButRealRestingHeartRateSurvives() {
        for value in [45.0, 55, 75, 95, 100] {
            XCTAssertEqual([sample(.restingHeartRate, value)].sanitizedVitals().count, 1,
                           "\(value) bpm is a real resting heart rate and must be kept")
        }
    }

    /// Same rule across the metrics where an artefact would do the most damage:
    /// reject the impossible, keep the alarming.
    func testEachBoundRejectsTheImpossibleAndKeepsTheAlarming() {
        let cases: [(MetricType, keep: Double, drop: Double)] = [
            (.oxygenSaturation, keep: 88, drop: 140),        // 88% is hypoxia, 140% is not a number
            (.respiratoryRate, keep: 28, drop: 300),
            (.bloodPressureSystolic, keep: 195, drop: 900),  // 195 is a crisis and must be shown
            (.bodyTemperature, keep: 39.5, drop: 200),       // 39.5 °C is a fever
            (.heartRateVariabilityRMSSD, keep: 12, drop: 5000),
            (.bodyMass, keep: 205, drop: 4000)
        ]
        for (metric, keep, drop) in cases {
            XCTAssertEqual([sample(metric, keep)].sanitizedVitals().count, 1,
                           "\(metric) should keep \(keep)")
            XCTAssertEqual([sample(metric, drop)].sanitizedVitals().count, 0,
                           "\(metric) should drop \(drop)")
        }
    }

    /// Metrics with no honest ceiling keep having none. A big step day is a big
    /// step day.
    func testUnboundedMetricsStayUnbounded() {
        XCTAssertNil(MetricType.stepCount.plausibleRange)
        XCTAssertNil(MetricType.activeEnergyBurned.plausibleRange)
        XCTAssertEqual([sample(.stepCount, 90_000)].sanitizedVitals().count, 1)
    }

    /// Signed and zero-valued metrics must not be caught by a range that assumed
    /// positivity — the trap `requiresPositiveValue` already documents.
    func testSignedAndZeroValuedMetricsAreNotCaughtByTheRange() {
        XCTAssertEqual([sample(.sleepOnset, -1.5)].sanitizedVitals().count, 1)
        XCTAssertEqual([sample(.skinTemperatureDeviation, -0.8)].sanitizedVitals().count, 1)
        XCTAssertEqual([sample(.atrialFibrillationBurden, 0)].sanitizedVitals().count, 1)
        XCTAssertEqual([sample(.sleepRemMinutes, 0)].sanitizedVitals().count, 1)
    }

    /// Every metric either declares a range or declares that it has none, so a
    /// new `MetricType` cannot slip through unbounded by accident.
    func testEveryMetricHasBeenConsidered() {
        for metric in MetricType.allCases {
            guard let range = metric.plausibleRange else { continue }
            XCTAssertLessThan(range.lowerBound, range.upperBound,
                              "\(metric) has an inverted range")
        }
    }
}
