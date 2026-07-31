import XCTest
@testable import InsightKit

private let circNow = TestClock.now
private let circCalendar = TestClock.utc

/// Sleep onset, and the card built on it. The roadmap carried circadian
/// consistency as blocked on a missing signal; the signal was in the payloads
/// the whole time and was being discarded at ingest.
final class SleepOnsetEncodingTests: XCTestCase {

    /// An instant at `hour:minute` UTC on the day `daysAgo` before the anchor.
    ///
    /// `TestClock.day` is **midday** — deliberately, so that a reading can never
    /// straddle midnight. This fixture is about bedtimes, which do nothing else,
    /// so it takes that back off to get to the day's true start.
    private func at(_ hour: Int, _ minute: Int = 0, daysAgo: Int = 0) -> Date {
        TestClock.day(daysAgo).addingTimeInterval(-12 * 3600)
            .addingTimeInterval(Double(hour) * 3600 + Double(minute) * 60)
    }

    private func hours(_ hour: Int, _ minute: Int = 0) -> Double? {
        SleepOnset.hoursFromMidnight(at(hour, minute), calendar: circCalendar)
    }

    // MARK: - The encoding

    func testEveningFoldsNegativeAndMorningStaysPositive() throws {
        XCTAssertEqual(try XCTUnwrap(hours(22, 30)), -1.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(hours(0, 30)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(hours(0, 0)), 0, accuracy: 0.0001)
    }

    /// The whole reason for the encoding. On a clock hour in [0, 24) the mean of
    /// 23:30 and 00:30 is noon, and every consumer would need circular
    /// statistics to avoid saying so. Here the arithmetic mean is the right
    /// answer, which is what lets `Baseline`, the regressions and the charts
    /// treat this metric like any other.
    func testTheArithmeticMeanOfTwoNightsEitherSideOfMidnightIsMidnight() throws {
        let mean = try XCTUnwrap(Baseline.mean([XCTUnwrap(hours(23, 30)),
                                                XCTUnwrap(hours(0, 30))]))
        XCTAssertEqual(mean, 0, accuracy: 0.0001)
    }

    /// A nap is not a bedtime. Returning nil rather than clamping is the point:
    /// squeezing 15:00 into the band would manufacture a bedtime out of an
    /// afternoon, and the consistency figure is a spread — one invented value
    /// moves it more than a missing night does.
    func testAnAfternoonIsNotASleepOnset() {
        XCTAssertNil(hours(15, 0))
        XCTAssertNil(hours(11, 30))
        XCTAssertNil(hours(12, 0))
    }

    func testTheBandEdgesAreInclusive() {
        XCTAssertNotNil(hours(18, 0))
        XCTAssertNotNil(hours(6, 0))
        XCTAssertNil(hours(17, 59))
        XCTAssertNil(hours(6, 1))
    }

    // MARK: - Night grouping

    /// 23:30 Monday and 01:00 Tuesday are one night and two calendar days. The
    /// duration series groups by calendar day and gets away with it; a timestamp
    /// cannot.
    func testSegmentsEitherSideOfMidnightAreOneNight() {
        let before = at(23, 30, daysAgo: 3)
        let after = at(1, 0, daysAgo: 2)
        XCTAssertEqual(SleepOnset.night(of: before, calendar: circCalendar),
                       SleepOnset.night(of: after, calendar: circCalendar))
    }

    func testTheEarliestSegmentOfANightWins() throws {
        let samples = SleepOnset.samples(
            fromSegmentStarts: [at(1, 0, daysAgo: 2), at(23, 30, daysAgo: 3),
                                at(3, 15, daysAgo: 2)],
            source: .appleHealth, calendar: circCalendar)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(try XCTUnwrap(samples.first).value, -0.5, accuracy: 0.0001)
    }

    /// An afternoon nap keys to the same night as the sleep that preceded it and
    /// must not become that night's onset — it is later, so "earliest wins"
    /// already handles it, and this pins that it does.
    func testANapDoesNotBecomeTheNightsOnset() throws {
        let samples = SleepOnset.samples(
            fromSegmentStarts: [at(23, 0, daysAgo: 3), at(15, 0, daysAgo: 2)],
            source: .oura, calendar: circCalendar)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(try XCTUnwrap(samples.first).value, -1, accuracy: 0.0001)
    }

    func testEachNightProducesOneSample() {
        let starts = (1...5).map { at(23, 0, daysAgo: $0) }
        XCTAssertEqual(SleepOnset.samples(fromSegmentStarts: starts, source: .oura,
                                          calendar: circCalendar).count, 5)
    }

    // MARK: - Rendering

    func testAnOnsetRendersAsAClockTime() {
        XCTAssertEqual(MetricValueFormatter.string(-1.5, .sleepOnset), "22:30")
        XCTAssertEqual(MetricValueFormatter.string(0.5, .sleepOnset), "00:30")
        XCTAssertEqual(MetricValueFormatter.string(0, .sleepOnset), "00:00")
    }

    /// The default branch renders `Int(value.rounded())`, which would print
    /// −1.5 as "-2". Compiles cleanly either way, which is why this is here.
    func testAnOnsetNeverRendersAsABareNumber() {
        XCTAssertFalse(MetricValueFormatter.string(-1.5, .sleepOnset).contains("-"))
    }

    /// Zero is midnight and negative is any evening bedtime, so a positivity
    /// rule would throw away most of the series.
    func testTheSanitizerKeepsNegativeOnsets() {
        let samples = [HealthMetricSample(type: .sleepOnset, value: -1.5,
                                          start: circNow, source: .oura)]
        XCTAssertEqual(samples.sanitizedVitals().count, 1)
    }
}

final class CircadianConsistencyTests: XCTestCase {

    /// `nights` bedtimes, `daysAgo` counting back, each offset from 23:00 by the
    /// matching entry in `offsets` (in hours).
    private func samples(_ offsets: [Double]) -> [HealthMetricSample] {
        offsets.enumerated().map { index, offset in
            // Midnight of that day (see `at` above), plus the bedtime.
            let start = TestClock.day(offsets.count - index)
                .addingTimeInterval(-12 * 3600)
                .addingTimeInterval((23 + offset) * 3600)
            let value = SleepOnset.hoursFromMidnight(start, calendar: circCalendar) ?? 0
            return HealthMetricSample(type: .sleepOnset, value: value,
                                      start: SleepOnset.night(of: start, calendar: circCalendar),
                                      source: .oura)
        }
    }

    private func evaluate(_ offsets: [Double]) -> CircadianConsistencyModel.Output? {
        CircadianConsistencyModel.evaluate(samples: samples(offsets), now: circNow,
                                           calendar: circCalendar)
    }

    func testTooFewNightsSaysNothing() {
        XCTAssertNil(evaluate([0, 0, 0]))
    }

    func testAnIdenticalBedtimeEveryNightScoresFull() throws {
        let output = try XCTUnwrap(evaluate(Array(repeating: 0, count: 12)))
        XCTAssertEqual(output.spreadHours, 0, accuracy: 0.0001)
        XCTAssertEqual(CircadianConsistencyModel.score(spreadHours: output.spreadHours), 100,
                       accuracy: 0.0001)
        XCTAssertEqual(output.band, "Very regular")
    }

    func testAWanderingBedtimeScoresLower() throws {
        let steady = try XCTUnwrap(evaluate([0, 0.1, -0.1, 0, 0.1, -0.1, 0, 0.1,
                                             -0.1, 0, 0.1, -0.1]))
        let wandering = try XCTUnwrap(evaluate([0, 1.5, -1.5, 0.8, -1.2, 1.4, -0.9,
                                                1.1, -1.4, 0.6, -1.1, 1.3]))
        XCTAssertLessThan(wandering.spreadHours, 2.6)
        XCTAssertGreaterThan(wandering.spreadHours, steady.spreadHours)
        XCTAssertLessThan(CircadianConsistencyModel.score(spreadHours: wandering.spreadHours),
                          CircadianConsistencyModel.score(spreadHours: steady.spreadHours))
    }

    /// The distinction the card exists to draw, and the reason social jetlag is
    /// folded out rather than averaged in.
    ///
    /// A perfectly consistent weekend lie-in is *regular* — two blocks, each
    /// tight — and a bedtime that wanders randomly by the same amount is not.
    /// One number cannot say both, so the shift is reported on its own line and
    /// removed from the spread.
    func testARecurringWeekendShiftIsNotRandomness() throws {
        // Fourteen nights: the weekend ones run three hours later. Which
        // calendar days are weekends is decided by the fixture's own clock, so
        // this is built by asking rather than assuming.
        var offsets: [Double] = []
        for index in 0..<14 {
            let start = TestClock.day(14 - index)
                .addingTimeInterval(-12 * 3600).addingTimeInterval(23 * 3600)
            let night = SleepOnset.night(of: start, calendar: circCalendar)
            offsets.append(circCalendar.isDateInWeekend(night) ? 3 : 0)
        }
        let shifted = try XCTUnwrap(evaluate(offsets))
        // Same values, scrambled so the shift no longer lines up with weekends.
        let scrambled = try XCTUnwrap(evaluate(offsets.shuffled(using: &fixedRNG)))

        XCTAssertLessThan(shifted.spreadHours, scrambled.spreadHours,
                          "a consistent lie-in should read as more regular than the same hours at random")
        let jetlag = try XCTUnwrap(shifted.socialJetlagHours)
        XCTAssertEqual(jetlag, 3, accuracy: 0.35)
    }

    func testTheCardScoresAndNamesTheHour() throws {
        let result = CircadianConsistencyInsight().evaluate(
            samples: samples(Array(repeating: 0, count: 12)), profile: .init(), now: circNow)
        XCTAssertNotNil(result.score)
        XCTAssertTrue(result.headline.contains("23:00"), result.headline)
        XCTAssertEqual(result.id, .circadianConsistency)
    }

    /// It is a fortnight's shape, not a claim about today, so it belongs on the
    /// Insights tab.
    func testItIsATrendCard() {
        XCTAssertEqual(InsightID.circadianConsistency.cadence, .trend)
    }

    /// The one thing this card must never say. Chronotype is constitutional and
    /// shift work is a job; the score is the spread and never the hour.
    func testTheCardNeverJudgesTheHour() {
        for offsets in [Array(repeating: 0.0, count: 12),      // 23:00
                        Array(repeating: 2.5, count: 12),      // 01:30
                        Array(repeating: -4.0, count: 12)] {   // 19:00
            let result = CircadianConsistencyInsight().evaluate(
                samples: samples(offsets), profile: .init(), now: circNow)
            XCTAssertEqual(result.score ?? -1, 100, accuracy: 0.0001,
                           "a perfectly regular sleeper was marked down for the hour they keep")
            let text = (result.explanation + " " + result.drivers.joined(separator: " "))
                .lowercased()
            for phrase in ["too late", "too early", "should be", "later than you should"] {
                XCTAssertFalse(text.contains(phrase), text)
            }
        }
    }
}

/// A seeded generator, because `Date.now`-free determinism is a rule here and a
/// shuffled fixture must produce the same order on every run.
private var fixedRNG = SeededGenerator(seed: 20_260_730)

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
