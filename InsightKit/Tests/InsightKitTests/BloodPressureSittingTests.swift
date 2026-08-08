import XCTest
@testable import InsightKit

/// Every test here is named for the defect it pins. The two dedupe cases are
/// both live in the reader's real record as of 2026-08-08, and neither showed up
/// as a wrong-looking number on any screen — which is exactly why they need a
/// test rather than an eye.
final class BloodPressureSittingTests: XCTestCase {

    /// A fixed anchor. Nothing here is relative to "now": clustering is about
    /// gaps between readings, and a test that drifts with the clock is a test
    /// that fails on the wrong day for the wrong reason.
    private let base = Date(timeIntervalSince1970: 1_600_000_000)

    private func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    /// One cuff reading = a systolic + diastolic sample at the same instant,
    /// matching `BloodPressureCalibrationTests.reading`.
    private func samples(_ sys: Double, _ dia: Double, at date: Date,
                         source: MetricSource) -> [HealthMetricSample] {
        [
            HealthMetricSample(type: .bloodPressureSystolic, value: sys, start: date, source: source),
            HealthMetricSample(type: .bloodPressureDiastolic, value: dia, start: date, source: source)
        ]
    }

    private func reading(_ sys: Double, _ dia: Double, at date: Date,
                         source: String = "Withings") -> BloodPressureEstimator.Reading {
        .init(date: date, systolic: sys, diastolic: dia, source: source)
    }

    // MARK: - Defect 1: one reading recorded ten times

    /// **The 2020-10-05 Withings reading that appears ten times at an identical
    /// timestamp.** Ten copies of one moment were counted ten times towards
    /// calibration; `pairedReadings` had no dedup at all.
    func testTenfoldDuplicateAtOneTimestampCollapsesToOneReading() {
        var all: [HealthMetricSample] = []
        for _ in 0..<10 { all += samples(138, 88, at: at(0), source: .withings) }

        let readings = BloodPressureEstimator.pairedReadings(from: all)
        XCTAssertEqual(readings.count, 1, "ten copies of one timestamp are one reading")

        let sittings = BloodPressureSittings.sittings(from: all)
        XCTAssertEqual(sittings.count, 1)
        XCTAssertEqual(sittings.first?.count, 1)
        // Ordinal 1, not nil: the collapse happened before the tie test ran, so
        // this is a lone reading rather than ten readings of unknown order.
        XCTAssertEqual(sittings.first?.entries.first?.ordinal, 1)
        // And a lone reading must not look better-pinned than it is.
        XCTAssertEqual(sittings.first?.systolicSpread, 0)
    }

    // MARK: - Defect 2: one reading arriving down two paths

    /// **The 2026-03-03 reading recorded once as `withings` and once as
    /// `apple_health/withings`.** This recurs for *every* reading whenever the
    /// direct Withings integration and Apple Health sync are both on, silently
    /// doubling the weight of the whole Withings history.
    func testCrossSourceWithingsAndAppleHealthMirrorCollapseToOneReading() {
        var all: [HealthMetricSample] = []
        all += samples(132, 86, at: at(0), source: .withings)
        all += samples(132, 86, at: at(0), source: .appleHealthDevice("Withings"))

        let readings = BloodPressureEstimator.pairedReadings(from: all)
        XCTAssertEqual(readings.count, 1, "one reading, two sync paths")
        // The direct integration survives, not the Apple Health mirror — and it
        // must not depend on which of the two synced first.
        XCTAssertEqual(readings.first?.source, "Withings")

        let sittings = BloodPressureSittings.sittings(from: all)
        XCTAssertEqual(sittings.first?.count, 1)
    }

    /// The same mirror, after a unit round-trip on the way through moved a value
    /// by under a millimetre of mercury — below what any cuff can resolve, so it
    /// is still one reading.
    func testMirroredReadingCollapsesEvenWhenTheSyncPathRoundedIt() {
        let deduped = BloodPressureSittings.deduplicate([
            reading(132, 86, at: at(0), source: "Withings"),
            reading(131, 86, at: at(0), source: "Withings via Apple Health")
        ])
        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.source, "Withings")
    }

    /// ⚠️ The mirror rule must not be greedy. Two different cuffs reaching the
    /// app through Apple Health share a substring and are two readings.
    func testTwoDifferentDevicesAtOneInstantAreNotAMirror() {
        let deduped = BloodPressureSittings.deduplicate([
            reading(132, 86, at: at(0), source: "Withings via Apple Health"),
            reading(121, 79, at: at(0), source: "Omron via Apple Health")
        ])
        XCTAssertEqual(deduped.count, 2)
    }

    // MARK: - Clustering

    /// The threshold is measured, not picked: the reader's inter-reading gaps are
    /// cleanly bimodal — 22 gaps under 4 minutes, then nothing until 68 — so
    /// every window from 5 to 60 minutes produces the identical grouping. This
    /// fixture has the same shape, and this test is what fails if a later change
    /// starts depending on the exact value of `defaultWindow`.
    func testClusteringIsIdenticalAtFiveFifteenAndSixtyMinuteWindows() {
        let readings = [
            // One sitting of three, gaps of 90s and 110s.
            reading(128, 84, at: at(0)),
            reading(124, 82, at: at(90)),
            reading(121, 80, at: at(200)),
            // 75 minutes later — past every window under test.
            reading(133, 88, at: at(75 * 60)),
            reading(129, 85, at: at(75 * 60 + 120)),
            // And a lone reading five hours in.
            reading(118, 78, at: at(300 * 60))
        ]

        // The two edges of the measured plateau, and the default in the middle.
        let windows: [TimeInterval] = [5 * 60, 15 * 60, 60 * 60]
        for window in windows {
            let sittings = BloodPressureSittings.sittings(from: readings, window: window)
            // Newest sitting first, so: the lone one, the pair, then the three.
            XCTAssertEqual(sittings.map(\.count), [1, 2, 3],
                           "grouping moved at a \(Int(window / 60))-minute window")
            XCTAssertEqual(sittings.last?.start, at(0))
        }
    }

    // MARK: - The sitting's own numbers

    /// One bad cuff placement is half a two-reading sitting and a third of a
    /// three-reading one. `Baseline.median` has a 50% breakdown point;
    /// `Baseline.mean` has none.
    func testMedianResistsTheOutlierThatWouldMoveTheMean() {
        let sittings = BloodPressureSittings.sittings(from: [
            reading(120, 80, at: at(0)),
            reading(122, 81, at: at(60)),
            reading(152, 95, at: at(120))
        ])
        guard let sitting = sittings.first else { return XCTFail("no sitting") }
        XCTAssertEqual(sitting.count, 3)
        XCTAssertEqual(sitting.systolic, 122)
        // The mean would have been 131.3 — a number no cuff showed, and a whole
        // ACC/AHA band above the median.
        XCTAssertEqual(Baseline.mean([120, 122, 152]) ?? 0, 131.33, accuracy: 0.01)
        XCTAssertEqual(sitting.diastolic, 81)
    }

    /// The spread is the number the reader sees, and it is never averaged away.
    func testSpreadWiderThanABandMakesTheSittingDisagreeWithItself() {
        let wide = BloodPressureSittings.sittings(from: [
            reading(120, 80, at: at(0)),
            reading(152, 95, at: at(60))
        ]).first
        XCTAssertEqual(wide?.systolicSpread, 32)
        XCTAssertEqual(wide?.disagreesWithItself, true)

        let tight = BloodPressureSittings.sittings(from: [
            reading(120, 80, at: at(0)),
            reading(124, 82, at: at(60))
        ]).first
        XCTAssertEqual(tight?.systolicSpread, 4)
        XCTAssertEqual(tight?.disagreesWithItself, false)
    }

    /// ⚠️ **The √n is the whole point of the type.** A lone reading carries the
    /// entire pooled spread — cuffing once tells the app exactly as much as one
    /// cuff reading is worth, and no rounding of the arithmetic is allowed to
    /// make it look like more.
    func testLoneReadingCarriesTheWholePooledStandardDeviation() {
        guard let lone = BloodPressureSittings
            .sittings(from: [reading(128, 84, at: at(0))]).first else { return XCTFail("no sitting") }
        XCTAssertEqual(lone.count, 1)
        XCTAssertEqual(lone.standardError(pooledWithinSD: 9.6), 9.6, accuracy: 1e-9)

        // Four readings in one morning halve it — they do not abolish it.
        guard let four = BloodPressureSittings.sittings(from: [
            reading(128, 84, at: at(0)), reading(126, 83, at: at(60)),
            reading(124, 82, at: at(120)), reading(122, 81, at: at(180))
        ]).first else { return XCTFail("no sitting") }
        XCTAssertEqual(four.standardError(pooledWithinSD: 9.6), 4.8, accuracy: 1e-9)
    }

    // MARK: - Ordinals

    /// Two readings sharing a timestamp to the second happen once in the reader's
    /// real record. Nothing in the data says which was first, and a cuff drifts
    /// downwards across a sitting — so a guessed order would read as a
    /// physiological direction. Both get `nil`; the unambiguous reading after
    /// them keeps its number.
    func testTiedTimestampsLeaveBothOrdinalsNil() {
        let sittings = BloodPressureSittings.sittings(from: [
            reading(128, 84, at: at(0)),
            reading(118, 76, at: at(0)),
            reading(121, 79, at: at(180))
        ])
        guard let sitting = sittings.first else { return XCTFail("no sitting") }
        // Both survive: 10 mmHg apart is two readings, not one reading rounded.
        XCTAssertEqual(sitting.count, 3)
        XCTAssertEqual(sitting.entries.map(\.ordinal), [nil, nil, 3])
    }

    // MARK: - Pooled within-sitting spread

    func testPooledWithinSDFallsBackBelowThreeMultiReadingSittings() {
        let day: TimeInterval = 24 * 3600
        let sittings = BloodPressureSittings.sittings(from: [
            reading(120, 80, at: at(0)), reading(130, 86, at: at(120)),
            reading(122, 81, at: at(day)), reading(132, 87, at: at(day + 120)),
            reading(124, 82, at: at(2 * day))            // lone — not multi-reading
        ])
        XCTAssertEqual(sittings.count, 3)
        let pooled = BloodPressureSittings.pooledWithinSD(sittings)
        XCTAssertFalse(pooled.learned, "two multi-reading sittings is two mornings")
        XCTAssertEqual(pooled.sd, BloodPressureSittings.fallbackWithinSD)
    }

    func testPooledWithinSDIsLearnedFromThreeMultiReadingSittings() {
        let day: TimeInterval = 24 * 3600
        var readings: [BloodPressureEstimator.Reading] = []
        for index in 0..<3 {
            let start = Double(index) * day
            // Each sitting spreads 10 mmHg, so each contributes a variance of
            // 10²/2 = 50 on one degree of freedom; pooled SD = √50 = 7.071.
            readings.append(reading(120, 80, at: at(start)))
            readings.append(reading(130, 86, at: at(start + 120)))
        }
        let sittings = BloodPressureSittings.sittings(from: readings)
        XCTAssertEqual(sittings.count, 3)
        let pooled = BloodPressureSittings.pooledWithinSD(sittings)
        XCTAssertTrue(pooled.learned)
        XCTAssertEqual(pooled.sd, 50.0.squareRoot(), accuracy: 1e-9)
    }

    /// ⚠️ A cuff replaying its last reading is not evidence of a perfect one, and
    /// a pooled SD of zero would divide `standardError` down to a sitting known
    /// without error.
    func testIdenticalRepeatsDoNotProduceAZeroSpread() {
        let day: TimeInterval = 24 * 3600
        var readings: [BloodPressureEstimator.Reading] = []
        for index in 0..<3 {
            let start = Double(index) * day
            readings.append(reading(126, 83, at: at(start)))
            readings.append(reading(126, 83, at: at(start + 120)))
        }
        let sittings = BloodPressureSittings.sittings(from: readings)
        let pooled = BloodPressureSittings.pooledWithinSD(sittings)
        XCTAssertFalse(pooled.learned)
        XCTAssertEqual(pooled.sd, BloodPressureSittings.fallbackWithinSD)
    }
}
