import XCTest
@testable import InsightKit

/// Roadmap #27's last open half. `VitalReader.reading` has said for months that
/// *"the winner is always one series, never a blend"*; `dailySeries` meant the
/// per-source day buckets together, and eighteen callers read it.
///
/// **Measured on the reader's own export before any of this was written**:
/// 36.5% of 211 resting-heart-rate days carry more than one source; the pooled
/// respiratory-rate reference SD — the denominator of every radar z — is 1.77×
/// the single-series one; and replaying `HealthWatchModel` day by day,
/// `isLeaning` disagreed on 50 of 687 (day, metric) pairs.
///
/// ⚠️ **Three of the first-drafted tests here were refuted by a verifier before
/// they ran**, and each refutation is preserved as a comment where it applies —
/// a test that passes whether or not the fix landed is worse than no test.
final class CrossDeviceSeriesTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    private func nights(_ source: MetricSource, _ metric: MetricType,
                        days: Range<Int>, value: (Int) -> Double) -> [HealthMetricSample] {
        days.map { day in
            HealthMetricSample(type: metric, value: value(day),
                               start: now.addingTimeInterval(-Double(day) * 86_400 - 3_600),
                               source: source)
        }
    }

    // MARK: - Never a blend

    /// ⚠️ **The fixture has both devices reporting INSIDE the window**, which is
    /// the correction that makes this test mean anything. A first draft put one
    /// device's days entirely outside the range and would have passed on the old
    /// code too, because `dailySeries` has always filtered by the cutoff *before*
    /// pooling — the pooling is what changed, not the windowing.
    func testTheBetterCoveredInstrumentWinsOutrightRatherThanBeingAveragedIn() throws {
        // Ring: every night at 55. Watch: a third of nights at 69.
        var samples = nights(.oura, .restingHeartRate, days: 0..<30) { _ in 55 }
        samples += nights(.appleHealth, .restingHeartRate,
                          days: 0..<30) { $0 % 3 == 0 ? 69 : .nan }
            .filter { !$0.value.isNaN }

        let series = VitalReader.dailySeries(.restingHeartRate, from: samples,
                                             days: 30, now: now, calendar: utc)

        XCTAssertFalse(series.isEmpty)
        for point in series {
            XCTAssertEqual(point.value, 55, accuracy: 0.001,
                           "a co-reported day was averaged: \(point.value)")
        }
        // And specifically not 62, which is the mean of 55 and 69 — the exact
        // value the old code returned on a third of these days.
        XCTAssertFalse(series.contains { abs($0.value - 62) < 0.001 })
    }

    /// The inter-device gap was becoming the variance, and the variance is the
    /// denominator of every z-score in the app.
    ///
    /// ⚠️ Asserted as a *comparison against a single-instrument fixture*, not
    /// against a magic threshold — a first draft asserted "> 4 bpm" and the real
    /// pooled figure for this fixture is ≈3.4, so it would have failed for the
    /// right reason and been "fixed" by loosening the number.
    func testTheGapBetweenTwoInstrumentsIsNoLongerReadAsVariability() throws {
        var mixed = nights(.oura, .restingHeartRate, days: 0..<28) { _ in 55 }
        mixed += nights(.appleHealth, .restingHeartRate, days: 0..<28) { _ in 69 }
            .filter { Int($0.start.timeIntervalSince1970) % 3 == 0 }

        let alone = nights(.oura, .restingHeartRate, days: 0..<28) { _ in 55 }

        let mixedSD = Baseline.standardDeviation(
            VitalReader.dailySeries(.restingHeartRate, from: mixed, days: 28,
                                    now: now, calendar: utc).map(\.value)) ?? 0
        let aloneSD = Baseline.standardDeviation(
            VitalReader.dailySeries(.restingHeartRate, from: alone, days: 28,
                                    now: now, calendar: utc).map(\.value)) ?? 0

        XCTAssertEqual(mixedSD, aloneSD, accuracy: 0.001,
                       "adding a second instrument changed the spread of the series")
    }

    // MARK: - Which instrument wins

    /// ⚠️ **Coverage of the window being read, not of the archive** — and this is
    /// the correction that stopped the obvious fix being adopted. `reading()`
    /// ranks fresh sources by *total* history, and this reader's Apple Watch
    /// holds the most resting-heart-rate days overall while having almost none
    /// recently. Reusing that ranking cut the radar's usable signal-days from
    /// 138 to 30 on the channel that flips most.
    func testTheWinnerIsWhicheverCoversTheWindowBeingRead() throws {
        // A dead device with a long memory: 120 days, all of them old.
        var samples = nights(.appleHealth, .restingHeartRate, days: 40..<160) { _ in 70 }
        // A live one with less history but the window covered.
        samples += nights(.oura, .restingHeartRate, days: 0..<25) { _ in 55 }

        let recent = VitalReader.dailySeries(.restingHeartRate, from: samples,
                                             days: 30, now: now, calendar: utc)
        XCTAssertEqual(recent.count, 25)
        XCTAssertTrue(recent.allSatisfy { abs($0.value - 55) < 0.001 },
                      "the dead device with the longer archive took the window")

        // Over the whole record the archive genuinely does cover more, and the
        // answer flips — which is the point: the question is per window.
        let all = VitalReader.dailySeries(.restingHeartRate, from: samples,
                                          now: now, calendar: utc)
        XCTAssertEqual(all.count, 120)
        XCTAssertTrue(all.allSatisfy { abs($0.value - 70) < 0.001 })
    }

    /// A tie on coverage breaks on recency, so a stalled device cannot hold the
    /// series by having happened to report the same number of days.
    func testATieBreaksOnTheMoreRecentInstrument() throws {
        var samples = nights(.appleHealth, .restingHeartRate, days: 10..<20) { _ in 70 }
        samples += nights(.oura, .restingHeartRate, days: 0..<10) { _ in 55 }

        let series = VitalReader.dailySeries(.restingHeartRate, from: samples,
                                             days: 30, now: now, calendar: utc)
        XCTAssertEqual(series.count, 10)
        XCTAssertTrue(series.allSatisfy { abs($0.value - 55) < 0.001 },
                      "the stalled device held the series on a tie")
    }

    /// One instrument is unaffected — the change must be invisible to the
    /// overwhelming majority of readers, who have exactly one.
    func testASingleInstrumentIsUntouched() throws {
        let samples = nights(.oura, .heartRateVariabilityRMSSD,
                             days: 0..<40) { 45 + Double($0 % 5) }
        let series = VitalReader.dailySeries(.heartRateVariabilityRMSSD, from: samples,
                                             days: 40, now: now, calendar: utc)
        XCTAssertEqual(series.count, 40)
        XCTAssertEqual(series.map(\.value).max(), 49)
        XCTAssertEqual(series.map(\.value).min(), 45)
    }

    // MARK: - What it was breaking

    /// ⚠️ **The radar fixture carries three metrics, not one.** A first draft
    /// used resting heart rate alone — and `HealthWatchModel.output(fromEvaluated:)`
    /// returns nil below two collapsed channels, so `XCTAssertNil(…leaning…)`
    /// would have passed whether or not the fix landed. Vacuous.
    ///
    /// A device arriving partway through a settled fortnight must not read as a
    /// body that changed.
    func testTheRadarDoesNotFlagAnInstrumentArriving() throws {
        // ⚠️ Jittered, and that is not decoration: a perfectly flat series has a
        // standard deviation of zero, `signal(for:daily:now:)` guards on
        // `spread > 0`, and every channel drops — which is how the first version
        // of this test failed with a nil output rather than a wrong one.
        let jitter: [Double] = [0, 0.8, -0.5, 1.1, -0.9, 0.4, -1.2, 0.7, -0.3, 0.2]
        var samples: [HealthMetricSample] = []
        // Three independent channels, all settled, all from the ring.
        samples += nights(.oura, .restingHeartRate, days: 0..<40) {
            55 + jitter[$0 % jitter.count]
        }
        samples += nights(.oura, .respiratoryRate, days: 0..<40) {
            14 + jitter[$0 % jitter.count] * 0.2
        }
        samples += nights(.oura, .skinTemperatureDeviation, days: 0..<40) {
            jitter[$0 % jitter.count] * 0.08
        }
        // A watch appears five days ago, reading consistently higher on the two
        // channels it measures. Nothing about the body changed.
        samples += nights(.appleHealth, .restingHeartRate, days: 0..<5) { _ in 68 }
        samples += nights(.appleHealth, .respiratoryRate, days: 0..<5) { _ in 16.5 }

        let output = try XCTUnwrap(HealthWatchModel.evaluate(samples: samples, now: now,
                                                             calendar: utc))
        XCTAssertGreaterThanOrEqual(output.signals.count, 2,
                                    "fixture too thin to be a real test")
        XCTAssertTrue(output.leaning.isEmpty,
                      "a second device arriving read as illness: \(output.leaning.map(\.metric))")
        XCTAssertEqual(output.status, .quiet)
    }
}
