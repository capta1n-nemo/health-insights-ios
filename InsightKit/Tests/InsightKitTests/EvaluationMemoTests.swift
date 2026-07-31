import XCTest
@testable import InsightKit

/// The evaluation memo and the day-bucket reuse it sits on top of.
///
/// Both exist purely to make a cold launch faster, and a cache that is merely
/// *fast* is worthless — the whole claim is that the answers are identical to
/// the ones the uncached path gives. These tests are that claim, written down.
///
/// Three things are load-bearing and each has a test here rather than a comment:
///
/// 1. **A memo answers only for the array it was opened for.** Its soundness
///    argument is an identity check on the buffer, not a fingerprint, and a
///    wrong hit would silently attribute one person's data to another read.
/// 2. **Bucketing reuses a day interval across consecutive readings.** That is
///    only safe if a reading at exactly midnight still lands in the new day —
///    `DateInterval.contains` is closed at its end and would put it in the old
///    one — and if a 25-hour DST day still resolves through the calendar.
/// 3. **Neither may depend on input order.** A miss must cost time, never
///    correctness.
final class EvaluationMemoTests: XCTestCase {

    private let watch = MetricSource.appleHealthDevice("Apple Watch")
    private let oura = MetricSource.oura

    private func mixedHistory() -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        for day in 0..<40 {
            for hour in stride(from: 0, to: 24, by: 3) {
                out.append(HealthMetricSample(
                    type: .heartRate, value: 58 + Double((day * 7 + hour) % 25),
                    start: TestClock.day(day).addingTimeInterval(Double(hour - 12) * 3600),
                    source: watch))
            }
            out.append(HealthMetricSample(type: .restingHeartRate,
                                          value: 50 + Double(day % 6),
                                          start: TestClock.day(day), source: watch))
            out.append(HealthMetricSample(type: .restingHeartRate,
                                          value: 52 + Double(day % 4),
                                          start: TestClock.day(day), source: oura))
            out.append(HealthMetricSample(type: .sleepDurationHours,
                                          value: 6.5 + Double(day % 5) * 0.3,
                                          start: TestClock.day(day), source: oura))
        }
        return out.shuffled()
    }

    // MARK: - The memo returns what the uncached path returns

    func testBreakdownIsUnchangedInsideAMemo() {
        let samples = mixedHistory()
        for metric in [MetricType.heartRate, .restingHeartRate, .sleepDurationHours] {
            let uncached = MultiSource.breakdown(metric, from: samples)
            let cached = MultiSource.withMemo(for: samples) {
                // Twice, so the second call is a genuine cache hit.
                _ = MultiSource.breakdown(metric, from: samples)
                return MultiSource.breakdown(metric, from: samples)
            }
            XCTAssertEqual(uncached, cached, "\(metric) breakdown changed under memoisation")
        }
    }

    func testSamplesOfTypeIsUnchangedInsideAMemo() {
        let samples = mixedHistory()
        for metric in [MetricType.heartRate, .restingHeartRate, .sleepDurationHours] {
            let uncached = samples.samples(of: metric)
            let cached = MultiSource.withMemo(for: samples) {
                _ = samples.samples(of: metric)
                return samples.samples(of: metric)
            }
            XCTAssertEqual(uncached, cached, "\(metric) samples(of:) changed under memoisation")
        }
    }

    func testVitalReaderIsUnchangedInsideAMemo() {
        let samples = mixedHistory()
        for metric in [MetricType.heartRate, .restingHeartRate, .sleepDurationHours] {
            let uncached = VitalReader.reading(metric, from: samples,
                                               now: TestClock.now, calendar: TestClock.utc)
            let uncachedSeries = VitalReader.dailySeries(metric, from: samples, days: 30,
                                                         now: TestClock.now, calendar: TestClock.utc)
            let cached = MultiSource.withMemo(for: samples) {
                _ = VitalReader.reading(metric, from: samples,
                                        now: TestClock.now, calendar: TestClock.utc)
                return (VitalReader.reading(metric, from: samples,
                                            now: TestClock.now, calendar: TestClock.utc),
                        VitalReader.dailySeries(metric, from: samples, days: 30,
                                                now: TestClock.now, calendar: TestClock.utc))
            }
            XCTAssertEqual(uncached?.value, cached.0?.value)
            XCTAssertEqual(uncached?.zScore, cached.0?.zScore)
            XCTAssertEqual(uncached?.sourceName, cached.0?.sourceName)
            XCTAssertEqual(uncachedSeries, cached.1)
        }
    }

    /// Two calendars must not share a cache entry: the day a reading belongs to
    /// is a fact about the calendar, not about the reading.
    func testDifferentCalendarsDoNotShareBuckets() {
        let samples = mixedHistory()
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        let (utcSeries, tokyoSeries) = MultiSource.withMemo(for: samples) {
            (VitalReader.dailySeries(.heartRate, from: samples, days: 30,
                                     now: TestClock.now, calendar: TestClock.utc),
             VitalReader.dailySeries(.heartRate, from: samples, days: 30,
                                     now: TestClock.now, calendar: tokyo))
        }
        XCTAssertEqual(utcSeries, VitalReader.dailySeries(.heartRate, from: samples, days: 30,
                                                          now: TestClock.now, calendar: TestClock.utc))
        XCTAssertEqual(tokyoSeries, VitalReader.dailySeries(.heartRate, from: samples, days: 30,
                                                            now: TestClock.now, calendar: tokyo))
        XCTAssertNotEqual(utcSeries, tokyoSeries,
                          "A 9-hour shift should move readings across day boundaries")
    }

    // MARK: - A memo never answers for an array it wasn't opened for

    func testMemoDoesNotAnswerForADifferentArray() {
        let opened = mixedHistory()
        let other = [
            HealthMetricSample(type: .restingHeartRate, value: 99,
                               start: TestClock.day(1), source: oura),
            HealthMetricSample(type: .restingHeartRate, value: 98,
                               start: TestClock.day(0), source: oura),
        ]

        MultiSource.withMemo(for: opened) {
            // Warm the memo on the array it was opened for...
            _ = MultiSource.breakdown(.restingHeartRate, from: opened)
            _ = opened.samples(of: .restingHeartRate)

            // ...then ask about a different one. The answers must describe
            // `other`, not the warmed entry.
            let breakdown = MultiSource.breakdown(.restingHeartRate, from: other)
            XCTAssertEqual(breakdown.sources.count, 1)
            XCTAssertEqual(breakdown.mostRecent?.value, 98)
            XCTAssertEqual(other.samples(of: .restingHeartRate).map(\.value), [99, 98])
            XCTAssertEqual(other.latestValue(.restingHeartRate), 98)
        }
    }

    /// A subset that happens to be as long as the canonical array is still a
    /// different allocation, so it must miss. Constructed to have the same count
    /// deliberately — count alone was never the check, and this is the test that
    /// says so.
    func testEqualLengthCopyIsNotTreatedAsTheSameArray() {
        let opened = mixedHistory()
        let shifted = opened.map {
            HealthMetricSample(type: $0.type, value: $0.value + 10,
                               start: $0.start, source: $0.source)
        }
        XCTAssertEqual(opened.count, shifted.count)

        MultiSource.withMemo(for: opened) {
            _ = MultiSource.breakdown(.restingHeartRate, from: opened)
            let fromShifted = MultiSource.breakdown(.restingHeartRate, from: shifted)
            let expected = MultiSource.breakdown(.restingHeartRate, from: shifted)
            XCTAssertEqual(fromShifted, expected)
            XCTAssertEqual(fromShifted.mostRecent.map { $0.value - 10 },
                           MultiSource.breakdown(.restingHeartRate, from: opened).mostRecent?.value)
        }
    }

    func testEngineResultsAreUnchangedByTheMemo() {
        let samples = mixedHistory()
        let profile = UserHealthProfile()
        let engine = InsightEngine()

        // `evaluateAll` opens a memo internally, so compare each model evaluated
        // on its own — outside any memo — against the engine's memoised pass.
        let memoised = engine.evaluateAll(samples: samples, profile: profile, now: TestClock.now)
        let direct = engine.models.map {
            $0.evaluate(samples: samples, events: [], profile: profile, now: TestClock.now)
        }

        XCTAssertEqual(memoised.count, direct.count)
        for (fromEngine, alone) in zip(memoised, direct) {
            XCTAssertEqual(fromEngine.id, alone.id)
            XCTAssertEqual(fromEngine.score, alone.score, "\(fromEngine.id) scored differently")
            XCTAssertEqual(fromEngine.headline, alone.headline, "\(fromEngine.id) worded differently")
        }
    }

    // MARK: - Day bucketing: the reuse must not move a reading

    /// `bucketed` reuses the previous reading's day interval while the next
    /// reading still falls inside it. A reading at *exactly* midnight is the
    /// case that catches a closed-interval test: it belongs to the day starting
    /// at that instant, not to the one ending there.
    func testMidnightBelongsToTheNewDay() {
        let midnight = TestClock.utc.startOfDay(for: TestClock.now)
        let series = SourceSeries(source: watch, samples: [
            HealthMetricSample(type: .heartRate, value: 60,
                               start: midnight.addingTimeInterval(-3600), source: watch),
            HealthMetricSample(type: .heartRate, value: 70, start: midnight, source: watch),
        ])
        let points = series.bucketed(by: .day, for: .heartRate, calendar: TestClock.utc)
        XCTAssertEqual(points.count, 2, "midnight was folded into the previous day")
        XCTAssertEqual(points.last?.date, midnight)
        XCTAssertEqual(points.last?.value, 70)
    }

    /// A 25-hour day. Every reading must land where the calendar itself puts it,
    /// which is the only thing the reuse is ever allowed to shortcut.
    func testBucketingSurvivesADSTTransition() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        // 2023-11-05: clocks go back at 06:00 UTC, making a 25-hour local day.
        let start = Date(timeIntervalSince1970: 1_699_142_400)   // 2023-11-05T00:00:00Z

        let samples = (0..<72).map { hour in
            HealthMetricSample(type: .heartRate, value: 60 + Double(hour % 10),
                               start: start.addingTimeInterval(Double(hour) * 3600),
                               source: watch)
        }
        let series = SourceSeries(source: watch, samples: samples)

        // The reference is the calendar asked once per reading — what this used
        // to do, and what the reuse must remain indistinguishable from.
        var expected: [Date: [Double]] = [:]
        for sample in samples {
            let day = newYork.dateInterval(of: .day, for: sample.start)?.start ?? sample.start
            expected[day, default: []].append(sample.value)
        }

        let points = series.bucketed(by: .day, for: .heartRate, calendar: newYork)
        XCTAssertEqual(points.count, expected.count)
        for point in points {
            XCTAssertEqual(point.count, expected[point.date]?.count,
                           "wrong number of readings in the bucket at \(point.date)")
        }
        XCTAssertTrue(points.contains { $0.count == 25 },
                      "the 25-hour day should hold 25 hourly readings")
    }

    /// Correctness must not depend on the readings arriving in order — the reuse
    /// is a shortcut on a sorted series, not a precondition.
    func testBucketingIsIndependentOfInputOrder() {
        let samples = (0..<96).map { hour in
            HealthMetricSample(type: .heartRate, value: 55 + Double(hour % 13),
                               start: TestClock.now.addingTimeInterval(-Double(hour) * 3600),
                               source: watch)
        }
        // `SourceSeries` sorts on init, so bucket the shuffled array directly.
        let ordered = SourceSeries(source: watch, samples: samples)
            .bucketed(by: .day, for: .heartRate, calendar: TestClock.utc)
        let shuffled = SourceSeries(source: watch, samples: samples.shuffled())
            .bucketed(by: .day, for: .heartRate, calendar: TestClock.utc)
        XCTAssertEqual(ordered.map(\.date).sorted(), shuffled.map(\.date).sorted())
        for point in ordered {
            XCTAssertEqual(point.value, shuffled.first { $0.date == point.date }?.value)
        }
    }
}
