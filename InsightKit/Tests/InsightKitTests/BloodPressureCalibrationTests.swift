import XCTest
@testable import InsightKit

final class BloodPressureCalibrationTests: XCTestCase {
    /// One cuff reading = a systolic + diastolic sample at the same instant.
    private func reading(_ sys: Double, _ dia: Double, daysAgo: Double,
                         source: MetricSource = .appleHealthDevice("Cuff")) -> [HealthMetricSample] {
        let date = Date().addingTimeInterval(-daysAgo * 24 * 3600)
        return [
            HealthMetricSample(type: .bloodPressureSystolic, value: sys, start: date, source: source),
            HealthMetricSample(type: .bloodPressureDiastolic, value: dia, start: date, source: source)
        ]
    }

    func testPairsSystolicAndDiastolicAcrossSources() {
        var samples: [HealthMetricSample] = []
        samples += reading(120, 80, daysAgo: 1, source: .appleHealthDevice("Apple Watch"))
        samples += reading(118, 78, daysAgo: 2, source: .withings)
        let readings = BloodPressureEstimator.pairedReadings(from: samples)
        XCTAssertEqual(readings.count, 2)
        // Newest first.
        XCTAssertEqual(readings.first?.systolic, 120)
        XCTAssertEqual(readings.first?.source, "Apple Watch via Apple Health")
    }

    func testThreeRecentReadingsNeedTwoMoreForInitial() {
        // The user's example: 3 readings in the last 30 days → ask for 2 more.
        var samples: [HealthMetricSample] = []
        samples += reading(122, 80, daysAgo: 2)
        samples += reading(119, 79, daysAgo: 10)
        samples += reading(121, 81, daysAgo: 20)
        let status = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertEqual(status.totalReadings, 3)
        XCTAssertEqual(status.recentReadings, 3)
        XCTAssertFalse(status.isGrounded)
        XCTAssertEqual(status.neededForGrounding, 2)
    }

    func testFiveRecentReadingsGround() {
        var samples: [HealthMetricSample] = []
        for d in [1.0, 5, 12, 18, 27] { samples += reading(120, 80, daysAgo: d) }
        let status = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertEqual(status.recentReadings, 5)
        XCTAssertTrue(status.isGrounded)
        XCTAssertEqual(status.neededForGrounding, 0)
    }

    func testOnlyLast30DaysCountTowardGrounding() {
        // Five readings, but all older than 30 days → NOT grounded; they show in
        // history (totalReadings) but don't count toward the 5.
        var samples: [HealthMetricSample] = []
        for d in [40.0, 60, 90, 120, 150] { samples += reading(120, 80, daysAgo: d) }
        let status = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertEqual(status.totalReadings, 5)
        XCTAssertEqual(status.recentReadings, 0)
        XCTAssertFalse(status.isGrounded)
        XCTAssertEqual(status.neededForGrounding, 5)

        // Add five within 30 days → grounded.
        for d in [2.0, 6, 11, 20, 28] { samples += reading(118, 78, daysAgo: d) }
        let grounded = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertEqual(grounded.recentReadings, 5)
        XCTAssertTrue(grounded.isGrounded)
    }

    func testAppleHealthReadingsSatisfyCuffRequirement() {
        // Only Apple Health BP present, no in-app grounding → the insight should
        // not still be asking the user to log a cuff reading.
        var samples: [HealthMetricSample] = []
        samples += reading(124, 82, daysAgo: 1)
        let result = BloodPressureInsight().evaluate(
            samples: samples, profile: UserHealthProfile(), now: Date())
        XCTAssertFalse(result.unmetRequirements.contains { $0.kind == .cuffSystolic })
        XCTAssertFalse(result.unmetRequirements.contains { $0.kind == .cuffDiastolic })
        XCTAssertEqual(result.headline, "124/82")
    }
}

/// The chart shades the AHA bands, which means the thresholds now exist in two
/// places: `Category.of` decides a reading's category, and `systolicRange` /
/// `diastolicRange` decide where the shading sits. Two copies of a clinical
/// threshold is one copy too many unless something holds them to each other.
final class PressureBandTests: XCTestCase {

    /// Every systolic value must land in the band whose range contains it —
    /// with the diastolic held at a value that can't promote the category.
    func testSystolicRangesAgreeWithTheClassifier() {
        for systolic in stride(from: 80.0, through: 210.0, by: 1.0) {
            let category = BloodPressureEstimator.Category.of(systolic: systolic, diastolic: 70)
            let range = category.systolicRange
            XCTAssertGreaterThanOrEqual(systolic, range.lower,
                                        "\(systolic) classified \(category) but sits below its band")
            if let upper = range.upper {
                XCTAssertLessThan(systolic, upper,
                                  "\(systolic) classified \(category) but sits above its band")
            }
        }
    }

    /// The same for diastolic, systolic held low. Elevated is defined by
    /// systolic alone, so it never appears on this axis.
    func testDiastolicRangesAgreeWithTheClassifier() {
        for diastolic in stride(from: 50.0, through: 130.0, by: 1.0) {
            let category = BloodPressureEstimator.Category.of(systolic: 110, diastolic: diastolic)
            let range = category.diastolicRange
            XCTAssertGreaterThanOrEqual(diastolic, range.lower,
                                        "\(diastolic) classified \(category) but sits below its band")
            if let upper = range.upper {
                XCTAssertLessThan(diastolic, upper,
                                  "\(diastolic) classified \(category) but sits above its band")
            }
        }
    }

    /// The bands must tile the axis with no gap and no overlap, or the shading
    /// will show seams the classifier doesn't have.
    func testSystolicBandsTileWithoutGaps() {
        let ordered = BloodPressureEstimator.Category.allCases
        for (lower, higher) in zip(ordered, ordered.dropFirst()) {
            XCTAssertEqual(lower.systolicRange.upper ?? -1, higher.systolicRange.lower,
                           "\(lower) and \(higher) don't meet")
        }
        XCTAssertNil(ordered.last?.systolicRange.upper, "the top band must be open-ended")
    }

    /// The reason the chart shades systolic only: the two axes disagree, and a
    /// single shaded set would mislabel one of the two lines.
    func testTheTwoAxesGenuinelyDisagree() {
        XCTAssertEqual(BloodPressureEstimator.Category.of(systolic: 110, diastolic: 85), .stage1)
        XCTAssertEqual(BloodPressureEstimator.Category.of(systolic: 110, diastolic: 70), .normal)
    }
}

/// The drift counter — the half of feedback item 8 that never got built. The
/// cadence rule ("five to ground, two a month to maintain") shipped without the
/// number it exists to protect, so being told to cuff again read identically
/// whether the model was still tracking the person or had wandered off them.
final class BloodPressureDriftTests: XCTestCase {

    private let base = TestClock.now

    /// `n` calibration points where systolic is a clean linear function of
    /// resting heart rate, plus an optional error injected into the last one.
    private func calibration(_ n: Int, lastSystolicOffset: Double = 0)
        -> [BloodPressureEstimator.CalibrationPoint] {
        (0..<n).map { index in
            let hr = 55 + Double(index)
            let isLast = index == n - 1
            return .init(restingHR: hr,
                         systolic: 100 + hr * 0.5 + (isLast ? lastSystolicOffset : 0),
                         diastolic: 65 + hr * 0.3 + (isLast ? lastSystolicOffset / 2 : 0),
                         date: base.addingTimeInterval(-Double(n - index) * 3 * 86_400))
        }
    }

    /// Held out, not fitted through. Scoring a fit against the readings it was
    /// built from reports how well least squares interpolates, which always
    /// flatters and answers nobody's question.
    func testDriftNeedsMoreReadingsThanTheFitItself() {
        let minimum = BloodPressureEstimator.minimumCalibrationPoints
        XCTAssertNil(BloodPressureEstimator.drift(calibration: calibration(minimum), now: base),
                     "with exactly a fit's worth there is nothing left to hold out")
        XCTAssertNotNil(BloodPressureEstimator.drift(calibration: calibration(minimum + 1),
                                                     now: base))
    }

    /// A person whose blood pressure really does track their resting heart rate
    /// should read as tracking — the counter must not manufacture drift out of
    /// the model's own arithmetic.
    func testAPerfectlyPredictableUserShowsNoDrift() throws {
        let drift = try XCTUnwrap(
            BloodPressureEstimator.drift(calibration: calibration(9), now: base))
        XCTAssertEqual(drift.latestSystolicError, 0, accuracy: 1.5)
        XCTAssertEqual(drift.band, "Tracking")
        XCTAssertTrue(drift.isWithinStatedUncertainty)
    }

    /// And a reading the model did not see coming should register as one.
    func testAnUnpredictedReadingShowsAsDrift() throws {
        let drift = try XCTUnwrap(
            BloodPressureEstimator.drift(calibration: calibration(9, lastSystolicOffset: 30),
                                         now: base))
        // The estimate predicted the old relationship, so it reads low against a
        // cuff that came in 30 mmHg higher.
        XCTAssertLessThan(drift.latestSystolicError, -10)
        XCTAssertNotEqual(drift.band, "Tracking")
        XCTAssertFalse(drift.isWithinStatedUncertainty)
    }

    /// Drift is expressed against the fit's *own* claimed spread, because "out
    /// by 6" means opposite things for a model claiming ±8 and one claiming ±2.
    func testTheBandIsRelativeToTheFitsOwnUncertainty() {
        let tight = BloodPressureEstimator.Drift(
            latestSystolicError: 6, latestDiastolicError: 3,
            meanAbsoluteSystolicError: 6, checkedReadings: 3,
            daysSinceLastReading: 2, systolicUncertainty: 12)
        let loose = BloodPressureEstimator.Drift(
            latestSystolicError: 14, latestDiastolicError: 6,
            meanAbsoluteSystolicError: 12, checkedReadings: 3,
            daysSinceLastReading: 2, systolicUncertainty: 5)
        XCTAssertEqual(tight.band, "Tracking")
        XCTAssertEqual(loose.band, "Off")
    }

    /// A fit through a handful of points can claim a residual spread of nearly
    /// zero — and exactly zero when the readings sit on a line. Left alone,
    /// every millimetre after that reads as catastrophic drift.
    ///
    /// The floor is the accuracy the cuff itself is held to (ISO 81060-2,
    /// ±5 mmHg): a model claiming to beat the instrument that measured it is
    /// claiming something no amount of fitting can support. A `Drift` built
    /// without a learned floor still gets that one.
    func testAnImpossiblyConfidentFitIsNotBelieved() {
        let overconfident = BloodPressureEstimator.Drift(
            latestSystolicError: 3, latestDiastolicError: 1,
            meanAbsoluteSystolicError: 3, checkedReadings: 4,
            daysSinceLastReading: 1, systolicUncertainty: 0)
        XCTAssertEqual(overconfident.effectiveUncertainty,
                       BloodPressureEstimator.Drift.isoMeanErrorLimit)
        XCTAssertEqual(overconfident.band, "Tracking",
                       "3 mmHg out is not drift, however tight the fit claims to be")
    }

    func testTheSummaryNamesTheDayAndTheDirection() {
        let drift = BloodPressureEstimator.Drift(
            latestSystolicError: 9, latestDiastolicError: 4,
            meanAbsoluteSystolicError: 7, checkedReadings: 4,
            daysSinceLastReading: 1, systolicUncertainty: 5)
        let summary = drift.summary(statedUncertainty: 7)
        XCTAssertTrue(summary.contains("yesterday"), summary)
        XCTAssertTrue(summary.contains("high"), summary)
    }

    /// ⚠️ **Backlog Q2: the card printed two ± and two cuff ages on one screen.**
    /// "±14, fitted to 23 readings" sat a few inches from "the ±13 it is judged
    /// on", and "over a day old" beside "2 days ago" — each defensible alone,
    /// together a card contradicting itself with no way for the reader to know
    /// which to believe.
    ///
    /// The drift sentence no longer chooses an uncertainty; it is given the one
    /// the card is showing, so the two cannot diverge.
    func testTheDriftSentenceQuotesTheUncertaintyItIsGivenAndNoOther() {
        let drift = BloodPressureEstimator.Drift(
            latestSystolicError: 9, latestDiastolicError: 4,
            meanAbsoluteSystolicError: 7, checkedReadings: 4,
            daysSinceLastReading: 2, systolicUncertainty: 13)
        let summary = drift.summary(statedUncertainty: 16)
        XCTAssertTrue(summary.contains("±16"), summary)
        XCTAssertFalse(summary.contains("±13"),
                       "the fit's own spread must not appear beside the one the card states")
        XCTAssertTrue(summary.contains("2 days ago"), summary)
    }

    /// And the stated ± is the widest of the three, because an error bar is a
    /// promise: a fit claiming ±5 while missing by 9 on this reader's own
    /// held-out readings is not an error bar, it is a wish.
    func testTheStatedUncertaintyIsWidenedByWhatTheModelHasActuallyMissedBy() {
        let confidentFit = BloodPressureEstimator.Estimate(
            systolic: 124, diastolic: 80, systolicUncertainty: 4,
            diastolicUncertainty: 3, calibrationCount: 12)
        let missesBy9 = BloodPressureEstimator.Drift(
            latestSystolicError: 9, latestDiastolicError: 4,
            meanAbsoluteSystolicError: 9, checkedReadings: 6,
            daysSinceLastReading: 2, systolicUncertainty: 4)

        XCTAssertEqual(BloodPressureEstimator.statedUncertainty(fit: confidentFit, drift: nil),
                       BloodPressureEstimator.Drift.isoMeanErrorLimit,
                       "nothing here can beat the cuff that produced the training data")
        XCTAssertEqual(BloodPressureEstimator.statedUncertainty(fit: confidentFit,
                                                               drift: missesBy9), 9,
                       "measured misses outrank a confident fit")
    }

    func testDaysSinceLastReadingCountsFromTheNewestPoint() throws {
        let drift = try XCTUnwrap(
            BloodPressureEstimator.drift(calibration: calibration(9),
                                         now: base.addingTimeInterval(5 * 86_400)))
        // The newest fixture point sits three days before `base`.
        XCTAssertEqual(drift.daysSinceLastReading, 8)
    }
}

/// **The sitting is the unit, so the counts count sittings** (2026-08-09).
///
/// `BloodPressureSitting` argued the case and nothing consumed it: the card, the
/// ± and every calibration figure still counted readings, so each of them was
/// too confident by roughly √n and the grounding rule could be satisfied by one
/// busy morning. These pin the wiring.
///
/// The figures on the reader's screen went *down* when this landed — 20 sittings
/// where 42 readings used to be counted — and that drop is the correction.
final class BloodPressureSittingCountTests: XCTestCase {

    /// Minutes-apart readings, so one call builds one sitting.
    private func sitting(_ pairs: [(Double, Double)], daysAgo: Double) -> [HealthMetricSample] {
        let start = Date().addingTimeInterval(-daysAgo * 86_400)
        return pairs.enumerated().flatMap { index, pair -> [HealthMetricSample] in
            let date = start.addingTimeInterval(Double(index) * 120)
            return [
                HealthMetricSample(type: .bloodPressureSystolic, value: pair.0,
                                   start: date, source: .appleHealthDevice("Cuff")),
                HealthMetricSample(type: .bloodPressureDiastolic, value: pair.1,
                                   start: date, source: .appleHealthDevice("Cuff"))
            ]
        }
    }

    // MARK: - Counting

    /// Four cuffs one after another on a Sunday morning are **one** observation
    /// of one person. They make that morning better known by a factor of two;
    /// they say nothing at all about next Tuesday.
    func testAMorningOfFourCuffsCountsOnceTowardsGrounding() {
        let samples = sitting([(128, 84), (124, 82), (121, 80), (119, 78)], daysAgo: 1)
        let status = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertEqual(status.totalReadings, 1, "four readings, one sitting")
        XCTAssertEqual(status.recentReadings, 1)
        XCTAssertFalse(status.isGrounded)
        XCTAssertEqual(status.neededForGrounding, 4,
                       "four more occasions, not four more readings")
    }

    /// ⚠️ And they cannot complete the one-off calibration between them. A
    /// regression fitted through a single morning has no spread in the thing it
    /// is regressing against; the estimate it produces is a statement about that
    /// morning wearing the label of a person.
    func testFiveCuffsInOneMorningDoNotCompleteTheInitialCalibration() {
        let samples = sitting([(128, 84), (126, 83), (124, 82), (122, 81), (120, 80)],
                              daysAgo: 2)
        let status = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertFalse(status.hasCompletedInitial)
        XCTAssertEqual(status.phase, .initial)
        XCTAssertEqual(status.required, 5)
    }

    /// Five separate occasions still do, which is the rule the reader was
    /// promised — only now it means what it says.
    func testFiveSeparateSittingsStillGround() {
        var samples: [HealthMetricSample] = []
        for day in [1.0, 6, 12, 19, 26] { samples += sitting([(120, 80)], daysAgo: day) }
        let status = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertEqual(status.recentReadings, 5)
        XCTAssertTrue(status.hasCompletedInitial)
        XCTAssertTrue(status.isGrounded)
    }

    /// The copy has to say so, or a count that halved overnight reads as lost
    /// data rather than as a correction.
    func testTheGuidanceSaysSittingsAndSaysWhy() {
        let samples = sitting([(128, 84), (124, 82)], daysAgo: 1)
        let guidance = BloodPressureEstimator.calibrationStatus(from: samples).guidance
        XCTAssertTrue(guidance.contains("sitting"), guidance)
        XCTAssertTrue(guidance.contains("count once"), guidance)
        XCTAssertFalse(guidance.contains("cuff readings"), guidance)
    }

    // MARK: - The trend

    /// **The recent pattern averages sitting medians, not readings.** Cuffing
    /// three times on one morning used to give that morning three times the
    /// weight of a day it disagreed with — so the "recent average" was partly an
    /// average of the reader's cuffing habit. And the median inside the sitting
    /// keeps one bad placement out of the morning's own answer.
    func testTheTrendAveragesSittingMediansNotReadings() throws {
        var samples = sitting([(148, 90), (150, 92), (190, 110)], daysAgo: 1)
        for day in [5.0, 10, 15] { samples += sitting([(120, 80)], daysAgo: day) }

        let trend = try XCTUnwrap(BloodPressureEstimator.recentTrend(from: samples))
        XCTAssertEqual(trend.readingCount, 4, "three days and one three-cuff morning")
        // The morning's median is 150 (its mean would be 162.7), and it counts
        // once: (150 + 120 + 120 + 120) / 4.
        XCTAssertEqual(trend.systolic, 127.5, accuracy: 1e-9)
        // Reading-weighted it was 141.3 — 14 mmHg and a whole ACC/AHA band out,
        // bought entirely with one morning's repeat cuffs.
        XCTAssertNotEqual(trend.systolic, 848.0 / 6, accuracy: 1)
    }

    /// End to end: the card's own words count sittings too. The driver line is
    /// the one the reader actually reads.
    func testTheCardSaysSittingsInTheRecentAverageLine() {
        var samples = sitting([(132, 86), (128, 84), (126, 83)], daysAgo: 3)
        for day in [11.0, 21] { samples += sitting([(124, 82)], daysAgo: day) }

        let result = BloodPressureInsight().evaluate(
            samples: samples, profile: UserHealthProfile(), now: Date())
        let lines = result.driverLines.map(\.text)
        XCTAssertTrue(lines.contains { $0.contains("across 3 sittings") },
                      lines.joined(separator: " | "))
        XCTAssertFalse(lines.contains { $0.contains("across 5 readings") },
                       lines.joined(separator: " | "))
    }

    // MARK: - The floor under the ±

    /// ⚠️ **ISO 81060-2 bounds the *cuff's mean error against a clinical
    /// reference*.** It says nothing about the same person cuffing themselves
    /// twice on a sofa, and this reader's pooled within-sitting SD is 9.6 mmHg —
    /// so for a one-reading sitting the old ±5 floor was optimistic by very
    /// nearly 2x, and the card was promising a precision their cuff has never
    /// once delivered.
    func testTheFloorIsTheWiderOfIsoAndThisReadersOwnCuff() {
        let lone = BloodPressureEstimator.Drift.uncertaintyFloor(pooledWithinSD: 9.6, readings: 1)
        XCTAssertEqual(lone, 9.6, accuracy: 1e-9)
        XCTAssertGreaterThan(lone, BloodPressureEstimator.Drift.isoMeanErrorLimit * 1.9)
    }

    /// Repeat readings really do narrow the answer — just never below the
    /// instrument that produced them.
    func testRepeatCuffsNarrowTheFloorBackToTheInstrumentAndNoFurther() {
        let two = BloodPressureEstimator.Drift.uncertaintyFloor(pooledWithinSD: 9.6, readings: 2)
        XCTAssertEqual(two, 9.6 / 2.0.squareRoot(), accuracy: 1e-9)
        // 9.6/√4 = 4.8, under ISO — so ISO binds again.
        XCTAssertEqual(BloodPressureEstimator.Drift.uncertaintyFloor(pooledWithinSD: 9.6, readings: 4),
                       BloodPressureEstimator.Drift.isoMeanErrorLimit)
    }

    /// ⚠️ A sitting cannot have zero readings (`BloodPressureSitting.init?`
    /// refuses one), but a caller doing the arithmetic can still hand this a
    /// zero, and dividing by √0 would return a floor of infinity.
    func testAnEmptySittingCannotDivideTheFloorAway() {
        XCTAssertEqual(BloodPressureEstimator.Drift.uncertaintyFloor(pooledWithinSD: 9.6, readings: 0),
                       9.6, accuracy: 1e-9)
    }

    /// The stated ± is still the widest of three; only the floor term moved.
    func testTheStatedUncertaintyWidensToTheLearnedFloor() {
        let confidentFit = BloodPressureEstimator.Estimate(
            systolic: 124, diastolic: 80, systolicUncertainty: 4,
            diastolicUncertainty: 3, calibrationCount: 12)
        let floor = BloodPressureEstimator.Drift.uncertaintyFloor(pooledWithinSD: 9.6, readings: 1)
        XCTAssertEqual(
            BloodPressureEstimator.statedUncertainty(fit: confidentFit, drift: nil,
                                                     uncertaintyFloor: floor),
            9.6, accuracy: 1e-9)
        // A measured miss still outranks it, and the ISO-only default is what an
        // un-updated caller keeps.
        let missesBy12 = BloodPressureEstimator.Drift(
            latestSystolicError: 12, latestDiastolicError: 5,
            meanAbsoluteSystolicError: 12, checkedReadings: 6,
            daysSinceLastReading: 2, systolicUncertainty: 4, uncertaintyFloor: floor)
        XCTAssertEqual(
            BloodPressureEstimator.statedUncertainty(fit: confidentFit, drift: missesBy12,
                                                     uncertaintyFloor: floor), 12)
        XCTAssertEqual(BloodPressureEstimator.statedUncertainty(fit: confidentFit, drift: nil),
                       BloodPressureEstimator.Drift.isoMeanErrorLimit)
    }

    /// And the drift verdict is judged against the same floor the card prints —
    /// 8 mmHg out is "Drifting" against ISO's 5 and "Tracking" against this
    /// reader's own 9.6. One error, two verdicts, and the honest one is the
    /// wider: a miss inside what this cuff does to itself is not evidence the
    /// model has wandered.
    func testTheDriftBandIsJudgedAgainstTheSameFloor() {
        func drift(floor: Double?) -> BloodPressureEstimator.Drift {
            floor.map {
                .init(latestSystolicError: 8, latestDiastolicError: 4,
                      meanAbsoluteSystolicError: 8, checkedReadings: 4,
                      daysSinceLastReading: 1, systolicUncertainty: 0, uncertaintyFloor: $0)
            } ?? .init(latestSystolicError: 8, latestDiastolicError: 4,
                       meanAbsoluteSystolicError: 8, checkedReadings: 4,
                       daysSinceLastReading: 1, systolicUncertainty: 0)
        }
        XCTAssertEqual(drift(floor: nil).band, "Drifting")
        XCTAssertEqual(
            drift(floor: BloodPressureEstimator.Drift.uncertaintyFloor(pooledWithinSD: 9.6,
                                                                       readings: 1)).band,
            "Tracking")
    }
}
