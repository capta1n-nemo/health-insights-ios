import XCTest
@testable import InsightKit

/// The suite against a realistic history: ~300 heart-rate readings a day, one
/// ring arriving through two delivery paths, a fortnight of silence, and a
/// febrile run at the end.
///
/// Every other fixture in this repo is one sample per day, one source, always
/// fresh — which is exactly the shape in which the *old* Vitals Check behaved.
/// A baseline of `suffix(60)` passed every test it had and printed a baseline
/// heart rate of 100 on the phone. These are the tests that shape can't pass.
final class GoldenDatasetTests: XCTestCase {

    private lazy var samples = GoldenDataset.samples()

    private func check() -> VitalSignsCheck.Output {
        VitalSignsCheck.evaluate(
            samples: TemperatureReconstructor.withReconstructedTemperature(samples),
            now: TestClock.now, calendar: TestClock.utc)
    }

    // MARK: - The shape itself

    func testTheDatasetIsTheShapeItClaimsToBe() {
        XCTAssertGreaterThan(samples.samples(of: .heartRate).count, 10_000,
                             "a real watch publishes hundreds of readings a day")
        // The gap: nothing at all through the silence.
        let gapDay = TestClock.day(GoldenDataset.gapStart - 2)
        let inGap = samples.filter {
            abs($0.start.timeIntervalSince(gapDay)) < 43_200
        }
        XCTAssertTrue(inGap.isEmpty, "the fortnight of silence has data in it")
    }

    func testItIsDeterministic() {
        XCTAssertEqual(GoldenDataset.samples().map(\.value),
                       GoldenDataset.samples().map(\.value))
    }

    // MARK: - What the shape breaks

    /// The defect that started all of this. Sixty *readings* of heart rate is
    /// five hours, so the baseline moves with the very thing it should detect —
    /// and a fever becomes mathematically invisible.
    func testTheHeartRateBaselineIsDaysNotReadings() throws {
        let reading = try XCTUnwrap(VitalReader.reading(
            .heartRate, from: samples, now: TestClock.now, gap: .none,
            calendar: TestClock.utc))
        // 28 days of history, minus the fortnight of silence inside the window.
        XCTAssertGreaterThan(reading.history.count, 8)
        XCTAssertLessThanOrEqual(reading.history.count, VitalReader.defaultWindowDays)
        // And the day's value is the day's *mean*, not one minute of one afternoon.
        XCTAssertEqual(reading.value, 82, accuracy: 6,
                       "the febrile day should read near its own mean")
    }

    /// One ring, two delivery paths. Counting both let inter-path disagreement
    /// set the standard deviation.
    func testADuplicatedRingCountsOnce() throws {
        let daily = VitalReader.dailySeries(.heartRateVariabilityRMSSD, from: samples,
                                            now: TestClock.now, calendar: TestClock.utc)
        let raw = samples.samples(of: .heartRateVariabilityRMSSD).count
        XCTAssertEqual(raw, daily.count * 2, "the fixture should carry two of each night")
        // One value per night after merging, not two.
        XCTAssertEqual(Set(daily.map(\.date)).count, daily.count)
    }

    /// The payoff: on a realistic history, the febrile run is caught.
    func testTheFeverIsFound() {
        let output = check()
        XCTAssertFalse(output.unusual.isEmpty, "a four-day febrile run went unnoticed")
        XCTAssertNotEqual(output.headline, "All normal")
    }

    /// And *which* row catches it is the interesting part.
    ///
    /// A four-day fever is four days long, so by the fourth day three of those
    /// nights are already inside the 28-day baseline the fourth is judged
    /// against. The elevation has become part of its own normal: it lifts the
    /// mean and inflates the spread, and the z-score shrinks toward the
    /// threshold from both directions at once.
    ///
    /// How much that matters depends on how large the departure is against the
    /// signal's *clean* spread. HRV falls 46 → 28 against a settled spread of a
    /// few milliseconds and still clears the bar comfortably. The temperature
    /// deviation moves 0 → 1.1 against a settled spread of about 0.1, which
    /// should be enormous — and by the fourth day the contaminated baseline has
    /// eaten most of it, leaving it hovering at the line.
    ///
    /// That is worth pinning rather than tuning away, because "the fever isn't
    /// in the thermal row" reads as a bug until you know why, and the fix — a
    /// baseline that excludes the run it is judging — is a real change with its
    /// own risks, not a threshold tweak.
    /// ✅ **Fixed 2026-08-05 — and the comment above is kept because it
    /// predicted exactly this.** It said the remedy was "a baseline that
    /// excludes the run it is judging… a real change with its own risks, not a
    /// threshold tweak", and that is what landed: the flagging path measures
    /// its spread with median/MAD, whose 50% breakdown point means three
    /// febrile nights in a four-week window cannot widen it.
    ///
    /// The same fever that used to sit *below* the unusual bar at ~1.9 now
    /// scores **z ≈ 5.0**. Nothing about the data changed; the denominator
    /// stopped absorbing the event it was measuring.
    ///
    /// The reader found the same defect from the other end on the same day:
    /// *"Yesterday my HRV was in danger zone, and today, its still the same
    /// value.. but no longer in danger?"*
    func testASustainedFeverIsCaughtDespiteBeingInsideItsOwnWindow() throws {
        let output = check()
        let hrv = try XCTUnwrap(output.readings.first {
            $0.metric == .heartRateVariabilityRMSSD
        })
        XCTAssertEqual(hrv.status, .unusual, "HRV's departure survives the contamination")

        let thermal = try XCTUnwrap(output.readings.first { $0.metric.family == .thermal })
        let z = try XCTUnwrap(thermal.zScore)
        XCTAssertGreaterThan(z, VitalSignsCheck.unusualZ,
                             "the fever is back under its own baseline — the spread is absorbing it again")
        XCTAssertEqual(thermal.status, .unusual,
                       "the thermal row must say so, not merely score high")
    }

    /// The other half of the same point: when the baseline *is* clean — a fever
    /// that started last night — the thermal row fires on its own.
    func testAFeverStartingTonightIsSeenInTheThermalRow() throws {
        // Two months of settled nights, then one at +1.4 °C.
        var samples: [HealthMetricSample] = []
        var random = GoldenDataset.Seeded(seed: 91)
        for daysAgo in stride(from: 29, through: 1, by: -1) {
            samples.append(HealthMetricSample(
                type: .skinTemperatureDeviation, value: random.jitter(0.15),
                start: TestClock.day(daysAgo), source: .oura))
        }
        samples.append(HealthMetricSample(
            type: .skinTemperatureDeviation, value: 1.4,
            start: TestClock.day(0), source: .oura))

        let output = VitalSignsCheck.evaluate(
            samples: TemperatureReconstructor.withReconstructedTemperature(samples),
            now: TestClock.now, calendar: TestClock.utc)
        XCTAssertTrue(output.unusual.contains { $0.metric.family == .thermal },
                      "found \(output.unusual.map(\.metric))")
    }

    /// One thermal signal, one row — the reconstruction must not double-count it
    /// on real-shaped data any more than on a toy fixture.
    func testOneThermalRowOnARealisticHistory() {
        XCTAssertEqual(check().readings.filter { $0.metric.family == .thermal }.count, 1)
    }

    /// A fortnight of silence is a gap, and a gap breaks the line rather than
    /// being drawn through.
    func testTheSilenceBreaksTheLine() {
        let breakdown = MultiSource.breakdown(.restingHeartRate, from: samples)
        let series = breakdown.sources.first
        let buckets = series?.bucketed(by: .day, for: .restingHeartRate,
                                       calendar: TestClock.utc) ?? []
        XCTAssertEqual(buckets.segments(for: .restingHeartRate, bucket: .day).count, 2,
                       "a fifteen-day silence should split the series in two")
    }

    /// And the same silence must *not* be bridged — it is far past anything an
    /// inferred line could honestly cross.
    func testTheSilenceIsNotBridged() {
        let breakdown = MultiSource.breakdown(.restingHeartRate, from: samples)
        let buckets = breakdown.sources.first?.bucketed(
            by: .day, for: .restingHeartRate, calendar: TestClock.utc) ?? []
        let runs = buckets.segments(for: .restingHeartRate, bucket: .day)
        let bridges = SeriesBridging.bridges(across: runs, metric: .restingHeartRate,
                                             bucket: .day, window: 60 * 86_400)
        XCTAssertTrue(bridges.isEmpty, "a fortnight of nothing was drawn through")
    }

    /// The whole engine runs on it without falling over, and produces scores.
    func testTheEngineProducesResultsOnRealisticData() {
        var profile = UserHealthProfile()
        profile.set(.init(kind: .dateOfBirth,
                          value: TestClock.now.addingTimeInterval(-42 * 365.2425 * 86_400)
                              .timeIntervalSince1970,
                          recordedAt: TestClock.now))
        profile.set(.init(kind: .biologicalSex, value: 0, recordedAt: TestClock.now))
        let results = InsightEngine().evaluateAll(
            samples: TemperatureReconstructor.withReconstructedTemperature(samples),
            profile: profile, now: TestClock.now)
        XCTAssertFalse(results.isEmpty)
        XCTAssertGreaterThanOrEqual(results.filter { $0.score != nil }.count, 3,
                                    "a two-month history should score several cards")
    }
}
