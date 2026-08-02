import XCTest
@testable import InsightKit

// The shared backward-looking fixture clock — see `Support/TestClock.swift`.
// Local names kept so no test body changes.
private let vitalsNow = TestClock.now
private let vitalsCalendar = TestClock.utc
private func vitalsDay(_ n: Int) -> Date { TestClock.day(n) }

final class VitalSignsTests: XCTestCase {

    /// One reading per day, newest last, ending today.
    private func series(_ type: MetricType, _ values: [Double],
                        source: MetricSource = .appleHealth) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(type: type, value: value,
                               start: vitalsDay(values.count - 1 - index), source: source)
        }
    }

    /// A settled fortnight, so there is enough history to judge against.
    private func settled(_ type: MetricType, _ level: Double, days: Int = 14,
                         jitter: Double = 1) -> [Double] {
        (0..<days).map { level + Double($0 % 3) * jitter - jitter }
    }

    private func evaluate(_ samples: [HealthMetricSample]) -> VitalSignsCheck.Output {
        VitalSignsCheck.evaluate(samples: samples, now: vitalsNow, calendar: vitalsCalendar)
    }

    private func reading(_ output: VitalSignsCheck.Output,
                         _ metric: MetricType) -> VitalSignsCheck.Reading? {
        output.readings.first { $0.metric == metric }
    }

    // MARK: - Behaviour that must not regress

    func testStableVitalReadsNormal() {
        let output = evaluate(series(.restingHeartRate, settled(.restingHeartRate, 55)))
        XCTAssertEqual(reading(output, .restingHeartRate)?.status, .normal)
    }

    func testSpikeInAConcerningDirectionIsUnusual() {
        let output = evaluate(series(.restingHeartRate, settled(.restingHeartRate, 55) + [78]))
        XCTAssertEqual(reading(output, .restingHeartRate)?.status, .unusual)
        XCTAssertEqual(output.headline, "1 unusual")
    }

    func testDropInAGoodDirectionIsNotAlarming() {
        // The same magnitude of departure, downwards — recovery, not a problem.
        let output = evaluate(series(.restingHeartRate, settled(.restingHeartRate, 60) + [42]))
        let r = reading(output, .restingHeartRate)
        XCTAssertEqual(r?.status, .watch)
        XCTAssertTrue(r?.note.contains("below") ?? false)
    }

    func testAbsoluteFloorOverridesAPermissiveBaseline() {
        // A baseline built from consistently low saturation must not make it
        // read as normal.
        let output = evaluate(series(.oxygenSaturation, settled(.oxygenSaturation, 90, jitter: 0.5)))
        let r = reading(output, .oxygenSaturation)
        XCTAssertEqual(r?.status, .unusual)
        XCTAssertTrue(r?.note.contains("healthy range") ?? false)
    }

    func testPreviouslyOrphanedMetricsAreNowRead() {
        var samples: [HealthMetricSample] = []
        samples += series(.heartRate, settled(.heartRate, 70))
        samples += series(.walkingHeartRateAverage, settled(.walkingHeartRateAverage, 95))
        samples += series(.oxygenSaturation, settled(.oxygenSaturation, 97, jitter: 0.5))
        samples += series(.bodyTemperature, settled(.bodyTemperature, 36.6, jitter: 0.1))
        let covered = Set(evaluate(samples).readings.map(\.metric))
        XCTAssertTrue(covered.isSuperset(of: [.heartRate, .walkingHeartRateAverage,
                                              .oxygenSaturation, .bodyTemperature]))
    }

    func testNoDataProducesAGracefulResult() {
        let result = ReadinessInsight().evaluate(samples: [], profile: UserHealthProfile(), now: vitalsNow)
        XCTAssertNil(result.primaryValue)
        XCTAssertEqual(result.headline, "Building baseline")
    }

    // MARK: - Driver lines

    /// The detail card leads with departures and folds the rest away, so the
    /// classification has to be right — and every line must survive, because
    /// hiding detail is the point but losing it isn't.
    func testDriverLinesSeparateDeparturesFromTheReassuringMajority() {
        var samples = series(.restingHeartRate, settled(.restingHeartRate, 55) + [78])
        samples += series(.heartRate, settled(.heartRate, 70) + [70])
        samples += series(.oxygenSaturation, settled(.oxygenSaturation, 97, jitter: 0.5) + [97])
        let result = ReadinessInsight().evaluate(samples: samples,
                                                  profile: UserHealthProfile(), now: vitalsNow)

        // Counted over the vitals the scan covers rather than over every line:
        // Readiness adds its own component lines, and pinning a total here would
        // make this test fail every time a component is added to the score.
        let scanned: (InsightDriver) -> Bool = { line in
            ["Resting Heart Rate", "Heart Rate", "Blood Oxygen"].contains { line.text.contains($0) }
        }
        let notable = result.driverLines.filter { $0.isNotable == true && scanned($0) }
        let routine = result.driverLines.filter { $0.isNotable == false && scanned($0) }
        XCTAssertEqual(notable.count, 1)
        XCTAssertTrue(notable.first?.text.contains("Resting Heart Rate") ?? false)

        // **One ordinary line, not two, and that is a deliberate change.** Blood
        // oxygen is a readiness *component*, so it already has a line of its own
        // ("Blood oxygen: 97%"); the scan's "in your normal range" line for the
        // same metric was a second row about one signal, and that duplication is
        // why "What's driving this" counted nearly double what every other
        // section on the card did. Heart rate is not a component, so the scan's
        // line is the only thing naming it and it stays.
        XCTAssertEqual(routine.count, 1, "only the unscored vital keeps a scan line")
        XCTAssertTrue(routine.first?.text.contains("Heart Rate") ?? false)

        // Nothing is *lost*, which is the principle this test exists for: the
        // scored vital is still narrated, by its own component line.
        XCTAssertTrue(result.driverLines.contains { $0.text.lowercased().contains("blood oxygen") },
                      "the scored vital must still be named somewhere")
    }

    /// Notable lines come first, because the Today card previews `drivers.first`
    /// and must not show "in your normal range" while the headline says otherwise.
    func testTheFirstDriverIsTheOneWorthSeeing() {
        var samples = series(.heartRate, settled(.heartRate, 70) + [70])
        samples += series(.oxygenSaturation, settled(.oxygenSaturation, 97, jitter: 0.5) + [88])
        let result = ReadinessInsight().evaluate(samples: samples,
                                                  profile: UserHealthProfile(), now: vitalsNow)
        // First among the notable lines, and notable at all — the Today card
        // previews `drivers.first` and must not lead with a reassurance.
        XCTAssertEqual(result.driverLines.first?.isNotable, true)
        XCTAssertTrue(result.driverLines.filter { $0.isNotable == true }
            .contains { $0.text.contains("Blood Oxygen") },
            result.drivers.joined(separator: " | "))
    }

    /// A vital we couldn't judge is something to know, not reassurance.
    func testAVitalWithoutEnoughHistoryIsNotFoldedAway() {
        let result = ReadinessInsight().evaluate(samples: series(.restingHeartRate, [55, 56]),
                                                  profile: UserHealthProfile(), now: vitalsNow)
        XCTAssertTrue(result.driverLines.contains {
            $0.isNotable == true && $0.text.contains("Resting Heart Rate")
        }, "a vital we couldn't judge is something to know, not reassurance")
    }

    /// An insight that doesn't classify must not have its whole list hidden —
    /// absent information is not the same as "all routine".
    func testUnclassifiedDriversStayUnclassified() {
        let result = InsightResult(id: .heartHealth, title: "t", primaryValue: 1, headline: "h",
                                   score: 50, confidence: .high, explanation: "e",
                                   drivers: ["one", "two"], unmetRequirements: [])
        XCTAssertTrue(result.driverLines.allSatisfy { $0.isNotable == nil })
        XCTAssertEqual(result.drivers, ["one", "two"])
    }

    func testVitalSignsIsATodayCard() {
        XCTAssertEqual(InsightID.readiness.cadence, .daily)
        XCTAssertTrue(InsightEngine().models.contains { $0.id == .readiness })
    }

    // MARK: - The defects that made 100 trivial

    /// The old baseline was `suffix(60)` — sixty *readings*. For a vital sampled
    /// hundreds of times a day that is a few hours, so the baseline tracked the
    /// very episode it was supposed to detect and a sustained elevation was
    /// undetectable. Every old fixture was one sample per day, the one shape
    /// where that bug is invisible.
    func testASustainedElevationIsFlaggedEvenWhenDenselySampled() {
        var samples: [HealthMetricSample] = []
        // A fortnight of settled days, 24 readings each. The day-to-day term
        // matters: without it every daily mean is identical, the baseline has
        // no spread, and no z-score can be formed at all.
        for day in 1...14 {
            for hour in 0..<24 {
                samples.append(HealthMetricSample(
                    type: .heartRate,
                    value: 62 + Double(hour % 5) + Double(day % 3),
                    start: vitalsDay(day).addingTimeInterval(Double(hour) * 3600),
                    source: .appleHealth))
            }
        }
        // Today: elevated all day, so the last 60 readings are all high.
        for hour in 0..<24 {
            samples.append(HealthMetricSample(
                type: .heartRate, value: 96 + Double(hour % 5),
                start: vitalsDay(0).addingTimeInterval(Double(hour) * 3600),
                source: .appleHealth))
        }
        let r = reading(evaluate(samples), .heartRate)
        XCTAssertEqual(r?.status, .unusual,
                       "a day-long elevation must not be normalised by its own readings")
        // And the value reported is the day's mean, not one raw sample.
        XCTAssertEqual(r?.value ?? 0, 98, accuracy: 1.0)
    }

    /// `now` used to be accepted and never read, so a months-old reading was
    /// reported as today's vital, counted toward "All normal", and bought high
    /// confidence.
    func testAStaleReadingIsExcludedRatherThanCountedNormal() {
        // Ten days back: past its 3-day freshness window, but still inside the
        // 30-day window that says this is a vital the user does record.
        let old = series(.walkingHeartRateAverage, settled(.walkingHeartRateAverage, 95))
            .map { HealthMetricSample(type: $0.type, value: $0.value,
                                      start: $0.start.addingTimeInterval(-10 * 86_400),
                                      source: $0.source) }
        let fresh = series(.restingHeartRate, settled(.restingHeartRate, 55))
        let output = evaluate(old + fresh)

        XCTAssertNil(reading(output, .walkingHeartRateAverage))
        XCTAssertEqual(output.stale.map(\.metric), [.walkingHeartRateAverage])
        XCTAssertNotEqual(output.headline, "All normal")
    }

    func testStaleReadingsDropCoverageAndTheScoreWithIt() {
        let stale = series(.oxygenSaturation, settled(.oxygenSaturation, 97, jitter: 0.5))
            .map { HealthMetricSample(type: $0.type, value: $0.value,
                                      start: $0.start.addingTimeInterval(-10 * 86_400),
                                      source: $0.source) }
        let fresh = series(.restingHeartRate, settled(.restingHeartRate, 55))

        let full = evaluate(fresh + series(.oxygenSaturation, settled(.oxygenSaturation, 97, jitter: 0.5)))
        let partial = evaluate(fresh + stale)

        XCTAssertEqual(full.coverage, 1, accuracy: 1e-9)
        XCTAssertEqual(partial.coverage, 0.5, accuracy: 1e-9)
        XCTAssertGreaterThan(full.score ?? 0, partial.score ?? 0,
                             "half the vitals missing must not score the same as all of them")
    }

    /// Two paths for the same physical device disagreeing by a few bpm used to
    /// set the standard deviation, swamping the physiological variance the
    /// z-score is supposed to measure — so nothing ever cleared the threshold.
    func testASecondSourceDoesNotInflateVarianceIntoSilence() {
        let watch = series(.restingHeartRate, settled(.restingHeartRate, 55) + [75],
                           source: .appleHealth)
        // A second instrument reading systematically ~7 bpm higher.
        let ring = series(.restingHeartRate, settled(.restingHeartRate, 62) + [82],
                          source: .oura)
        XCTAssertEqual(reading(evaluate(watch + ring), .restingHeartRate)?.status, .unusual)
    }

    /// One reading is not a clean bill of health.
    func testTooLittleHistoryIsNotReportedAsNormal() {
        let output = evaluate(series(.restingHeartRate, [55, 56]))
        let r = reading(output, .restingHeartRate)
        XCTAssertEqual(r?.status, .insufficientHistory)
        XCTAssertNotEqual(output.headline, "All normal")
    }

    /// The score was `100 - (unusual*25 + watch*10)`, so z = 1.2499 cost nothing
    /// and z = 1.2500 cost ten. Normality is now continuous.
    func testNormalityIsContinuousAcrossTheOldThreshold() {
        let spec = VitalSignsCheck.specs.first { $0.metric == .restingHeartRate }!
        let a = VitalSignsCheck.normality(z: 1.24, spec: spec)
        let b = VitalSignsCheck.normality(z: 1.26, spec: spec)
        XCTAssertLessThan(abs(a - b), 1, "no cliff at the old watch threshold")
        // And it is monotonic in |z| rather than flat inside the band.
        XCTAssertGreaterThan(VitalSignsCheck.normality(z: 0, spec: spec),
                             VitalSignsCheck.normality(z: 1, spec: spec))
        XCTAssertGreaterThan(VitalSignsCheck.normality(z: 1, spec: spec),
                             VitalSignsCheck.normality(z: 2, spec: spec))
    }

    /// A card headlined "All normal" used to carry a driver line reading
    /// "a little above your baseline".
    func testStatusAndNoteNeverContradict() {
        // 58.75 lands at z ≈ -1.42 against this baseline: inside the old
        // watch band, but downward on a metric where down is good. That kept
        // `.normal` and still rewrote the note, which is the contradiction.
        let output = evaluate(series(.restingHeartRate, settled(.restingHeartRate, 60) + [58.75]))
        let r = reading(output, .restingHeartRate)
        XCTAssertEqual(r?.status, .normal)
        XCTAssertEqual(r?.note, "in your normal range")
    }

    /// 100 should require everything you normally record to have been measured
    /// today *and* to sit on its baseline.
    func testAPerfectScoreNeedsFullCoverageAndCentredReadings() {
        var samples: [HealthMetricSample] = []
        for (metric, level, jitter) in [(MetricType.restingHeartRate, 55.0, 1.0),
                                        (.heartRate, 70.0, 1.0),
                                        (.oxygenSaturation, 98.0, 0.5),
                                        (.respiratoryRate, 15.0, 0.5)] {
            var values = settled(metric, level, jitter: jitter)
            values.append(level)             // today: exactly on the mean
            samples += series(metric, values)
        }
        let output = evaluate(samples)
        XCTAssertEqual(output.coverage, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(output.score ?? 0, 90)
    }

    func testARelativeCollapseIsCaughtWhereAZScoreCannotSeeIt() {
        // HRV drifting down for weeks: each day is unremarkable against the
        // days before it, but the level has halved.
        let drifting = (0..<20).map { 90 - Double($0) * 3 }
        let output = evaluate(series(.heartRateVariabilityRMSSD, drifting))
        XCTAssertEqual(reading(output, .heartRateVariabilityRMSSD)?.status, .unusual)
    }

    func testWalkingHeartRateBoundCanActuallyFire() {
        // The old hardHigh of 130 sat above any real walking heart rate.
        let output = evaluate(series(.walkingHeartRateAverage,
                                     settled(.walkingHeartRateAverage, 118, jitter: 0.5)))
        XCTAssertEqual(reading(output, .walkingHeartRateAverage)?.status, .unusual)
    }

    func testScoreIsDominatedByTheWorstSignalNotAveragedAway() {
        var healthy: [HealthMetricSample] = []
        for (metric, level, jitter) in [(MetricType.restingHeartRate, 55.0, 1.0),
                                        (.heartRate, 70.0, 1.0),
                                        (.respiratoryRate, 15.0, 0.5)] {
            healthy += series(metric, settled(metric, level, jitter: jitter) + [level])
        }
        // One clearly abnormal vital alongside three clean ones.
        let withOutlier = healthy + series(.oxygenSaturation,
                                           settled(.oxygenSaturation, 98, jitter: 0.5) + [88])
        let score = evaluate(withOutlier).score ?? 100
        XCTAssertLessThan(score, 50, "an abnormal SpO2 must not be averaged away")
    }
}

final class BodyCompositionWiringTests: XCTestCase {
    private func series(_ type: MetricType, _ values: [Double]) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(type: type, value: value,
                               start: Date().addingTimeInterval(Double(index - values.count) * 86_400),
                               source: .withings)
        }
    }

    func testScaleMetricsThatHadNoReaderNowAppear() {
        let samples = series(.bodyMass, [80, 79.6, 79.2])
            + series(.leanBodyMass, [60, 60.1, 60.2])
            + series(.muscleMass, [57, 57.1, 57.2])
            + series(.boneMass, [3.1, 3.1, 3.1])
            + series(.bodyWaterPercentage, [55, 55.2, 55.1])
        let drivers = BodyCompositionInsight()
            .evaluate(samples: samples, profile: UserHealthProfile(), now: Date())
            .drivers
            .joined(separator: "\n")

        XCTAssertTrue(drivers.contains("Lean mass"))
        XCTAssertTrue(drivers.contains("Muscle mass"))
        XCTAssertTrue(drivers.contains("Bone mass"))
        XCTAssertTrue(drivers.contains("Body water"))
    }

    func testWeightFallingWithLeanMassHoldingReadsAsFatLoss() throws {
        let samples = series(.bodyMass, [82, 81, 80, 78.5])
            + series(.leanBodyMass, [60, 60.1, 60, 60.1])
        let narrative = try XCTUnwrap(
            BodyCompositionInsight.compositionNarrative(
                samples: samples, weightSeries: samples.samples(of: .bodyMass)))
        XCTAssertTrue(narrative.contains("from fat"))
    }

    func testWeightAndLeanMassFallingTogetherFlagsMuscleLoss() throws {
        let samples = series(.bodyMass, [82, 81, 80, 78])
            + series(.leanBodyMass, [62, 61.5, 61, 59.5])
        let narrative = try XCTUnwrap(
            BodyCompositionInsight.compositionNarrative(
                samples: samples, weightSeries: samples.samples(of: .bodyMass)))
        XCTAssertTrue(narrative.contains("muscle"))
    }
}

final class VascularAgePromotionTests: XCTestCase {
    func testOuraCardiovascularAgeBecomesAVital() throws {
        let json = #"{"data":[{"day":"2026-01-10","vascular_age":32}]}"#
        var catalogue = FieldCatalogue()
        let result = IngestionPipeline.shipped.ingest(
            [IngestPayload(source: .oura, endpoint: "daily_cardiovascular_age", data: Data(json.utf8))],
            into: &catalogue)
        let promoted = try XCTUnwrap(result.promoted.first)
        XCTAssertEqual(promoted.type, .vascularAge)
        XCTAssertEqual(promoted.value, 32)
    }

    func testHeartAgeReportsTheProviderEstimateAlongsideItsOwn() {
        let now = Date()
        var profile = UserHealthProfile()
        profile.set(.init(kind: .dateOfBirth,
                          value: now.addingTimeInterval(-40 * 365.2425 * 86_400).timeIntervalSince1970,
                          recordedAt: now))
        profile.set(.init(kind: .biologicalSex, value: 0, recordedAt: now))
        // Enough for the insight to produce a headline age, so the driver list
        // is actually built rather than short-circuited by the "add details" path.
        profile.set(.init(kind: .cuffSystolic, value: 120, recordedAt: now))
        let samples = [
            HealthMetricSample(type: .vascularAge, value: 32, start: now, source: .oura),
            HealthMetricSample(type: .vo2Max, value: 44, start: now, source: .appleHealth)
        ]
        // Reported by the risk card now — a provider's own vascular-age
        // estimate sits beside ours rather than being folded into it.
        let drivers = CardiovascularRiskInsight(preferredEngine: .combined)
            .evaluate(samples: samples, profile: profile, now: now)
            .drivers.joined(separator: "\n")
        XCTAssertTrue(drivers.contains("vascular age"), drivers)
    }
}
