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
    /// claiming something no amount of fitting can support.
    func testAnImpossiblyConfidentFitIsNotBelieved() {
        let overconfident = BloodPressureEstimator.Drift(
            latestSystolicError: 3, latestDiastolicError: 1,
            meanAbsoluteSystolicError: 3, checkedReadings: 4,
            daysSinceLastReading: 1, systolicUncertainty: 0)
        XCTAssertEqual(overconfident.effectiveUncertainty,
                       BloodPressureEstimator.Drift.uncertaintyFloor)
        XCTAssertEqual(overconfident.band, "Tracking",
                       "3 mmHg out is not drift, however tight the fit claims to be")
    }

    func testTheSummaryNamesTheDayAndTheDirection() {
        let drift = BloodPressureEstimator.Drift(
            latestSystolicError: 9, latestDiastolicError: 4,
            meanAbsoluteSystolicError: 7, checkedReadings: 4,
            daysSinceLastReading: 1, systolicUncertainty: 5)
        XCTAssertTrue(drift.summary.contains("yesterday"), drift.summary)
        XCTAssertTrue(drift.summary.contains("high"), drift.summary)
    }

    func testDaysSinceLastReadingCountsFromTheNewestPoint() throws {
        let drift = try XCTUnwrap(
            BloodPressureEstimator.drift(calibration: calibration(9),
                                         now: base.addingTimeInterval(5 * 86_400)))
        // The newest fixture point sits three days before `base`.
        XCTAssertEqual(drift.daysSinceLastReading, 8)
    }
}
