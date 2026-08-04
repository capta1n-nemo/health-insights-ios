import XCTest
@testable import InsightKit

/// The third cause of the "7.5 h night reported as 4 h" symptom, found in the
/// user's first model-internals export: Oura splits a broken night into
/// several records (`period` 0, 1, 2…) stamped with the same `day`, and
/// `bucketStatistic` *averages* same-day sleep — so a night slept in two
/// 4.3 h halves read as 4.3 h while Apple Health's summed path said 8.7 h.
/// Four nights in one month showed Oura at almost exactly half of Apple.
final class SplitNightTests: XCTestCase {

    private func payload(_ records: String) -> Data {
        Data(#"{"data":[\#(records)],"next_token":null}"#.utf8)
    }

    /// The user's 2026-07-31 shape: a long sleep, a wake, a continuation —
    /// two records, one night.
    private let firstHalf = """
    {"day":"2026-07-31","type":"long_sleep","period":0,
     "bedtime_start":"2026-07-31T01:40:00+01:00",
     "lowest_heart_rate":48,"average_hrv":70,"average_breath":14.0,
     "total_sleep_duration":15480,"deep_sleep_duration":3600,
     "rem_sleep_duration":3000,"time_in_bed":17000,"efficiency":91,
     "latency":660}
    """
    private let secondHalf = """
    {"day":"2026-07-31","type":"sleep","period":1,
     "bedtime_start":"2026-07-31T06:30:00+01:00",
     "lowest_heart_rate":55,"average_hrv":60,"average_breath":16.0,
     "total_sleep_duration":15840,"deep_sleep_duration":1800,
     "rem_sleep_duration":4200,"time_in_bed":18000,"efficiency":88,
     "latency":60}
    """

    private func samples(of type: MetricType,
                         in all: [HealthMetricSample]) -> [HealthMetricSample] {
        all.filter { $0.type == type }
    }

    func testANightInTwoPeriodsIsOneSummedNight() throws {
        let all = try OuraResponseParser.parseSleepUTC(payload("\(firstHalf),\(secondHalf)"))
        let durations = samples(of: .sleepDurationHours, in: all)
        XCTAssertEqual(durations.count, 1,
                       "two periods of one night must be one sample, or the day bucket averages them")
        XCTAssertEqual(durations[0].value, (15480 + 15840) / 3600.0, accuracy: 0.01)
        XCTAssertEqual(samples(of: .sleepDeepMinutes, in: all).first?.value ?? 0,
                       (3600 + 1800) / 60.0, accuracy: 0.01)
        XCTAssertEqual(samples(of: .sleepRemMinutes, in: all).first?.value ?? 0,
                       (3000 + 4200) / 60.0, accuracy: 0.01)
    }

    /// The night's sleeping low is the lowest of any period's low.
    func testTheNightsRestingHeartRateIsTheLowestPeriodsLow() throws {
        let all = try OuraResponseParser.parseSleepUTC(payload("\(firstHalf),\(secondHalf)"))
        let rhr = samples(of: .restingHeartRate, in: all)
        XCTAssertEqual(rhr.count, 1)
        XCTAssertEqual(rhr[0].value, 48)
    }

    /// "Fell asleep in about N min" is a claim about going to bed — the
    /// continuation's near-instant re-onset must not become the night's figure
    /// (the same hazard the nap filter closes, one record type over).
    func testLatencyIsTheFirstPeriodsNotTheContinuations() throws {
        let all = try OuraResponseParser.parseSleepUTC(payload("\(secondHalf),\(firstHalf)"))
        let latency = samples(of: .sleepLatencyMinutes, in: all)
        XCTAssertEqual(latency.count, 1)
        XCTAssertEqual(latency[0].value, 660 / 60.0, accuracy: 0.01,
                       "order in the payload must not decide which period's latency wins")
    }

    /// Rates combine weighted by sleep time; efficiency by time in bed. With
    /// near-equal halves the combined figures sit between the halves'.
    func testRatesCombineWeightedRatherThanSummed() throws {
        let all = try OuraResponseParser.parseSleepUTC(payload("\(firstHalf),\(secondHalf)"))
        let hrv = try XCTUnwrap(samples(of: .heartRateVariabilityRMSSD, in: all).first)
        let sleepWeights: (Double, Double) = (15480, 15840)
        let expectedHRV: Double = (70.0 * sleepWeights.0 + 60.0 * sleepWeights.1)
            / (sleepWeights.0 + sleepWeights.1)
        XCTAssertEqual(hrv.value, expectedHRV, accuracy: 0.01)
        let efficiency = try XCTUnwrap(samples(of: .sleepEfficiency, in: all).first)
        let bedWeights: (Double, Double) = (17000, 18000)
        let expectedEfficiency: Double = (91.0 * bedWeights.0 + 88.0 * bedWeights.1)
            / (bedWeights.0 + bedWeights.1)
        XCTAssertEqual(efficiency.value, expectedEfficiency, accuracy: 0.01)
    }

    /// A single-period night is exactly what it was before this fix — Oura's
    /// own published figures, untouched.
    func testASinglePeriodNightIsUnchanged() throws {
        let all = try OuraResponseParser.parseSleepUTC(payload(firstHalf))
        XCTAssertEqual(samples(of: .sleepDurationHours, in: all).first?.value ?? 0,
                       15480 / 3600.0, accuracy: 0.001)
        XCTAssertEqual(samples(of: .sleepEfficiency, in: all).first?.value ?? 0, 91,
                       accuracy: 0.001)
        XCTAssertEqual(samples(of: .sleepLatencyMinutes, in: all).first?.value ?? 0, 11,
                       accuracy: 0.001)
    }
}
