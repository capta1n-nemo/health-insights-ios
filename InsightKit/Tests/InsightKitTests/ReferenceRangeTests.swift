import XCTest
@testable import InsightKit

/// Reference bands existed on the blood-pressure chart alone, while the
/// thresholds for the other vitals sat in the Vitals Check alarm table where the
/// app target couldn't see them.
///
/// The tempting fix — publish `VitalSignsCheck.Spec` — is the wrong one. Those
/// are *alarm* bounds, not normal ranges: blood oxygen's floor is 94% with no
/// ceiling, so a band drawn between them would cover every point ever plotted.
/// The two tables stay independent and are bound together by
/// `testANormalBandIsNeverWiderThanItsAlarmBounds` rather than by derivation.
final class ReferenceRangeTests: XCTestCase {

    private func range(_ metric: MetricType) throws -> MetricReferenceRange {
        try XCTUnwrap(metric.referenceRange, "\(metric) has no reference range")
    }

    /// A band that disagreed with the alarm table would say one thing on the
    /// chart and another on the card.
    func testANormalBandIsNeverWiderThanItsAlarmBounds() throws {
        for metric in MetricType.allCases {
            guard let range = metric.referenceRange,
                  let spec = VitalSignsCheck.specs.first(where: { $0.metric == metric })
            else { continue }
            if let alarmLow = spec.hardLow, let normalLow = range.normal.low {
                XCTAssertGreaterThanOrEqual(
                    normalLow, alarmLow,
                    "\(metric)'s normal floor sits below its own alarm floor")
            }
            if let alarmHigh = spec.hardHigh, let normalHigh = range.normal.high {
                XCTAssertLessThanOrEqual(
                    normalHigh, alarmHigh,
                    "\(metric)'s normal ceiling sits above its own alarm ceiling")
            }
        }
    }

    /// Every range that exists must be orderable, and must carry the words that
    /// make it mean something. A shaded rectangle with no caption is decoration.
    func testEveryRangeIsWellFormedAndAttributed() {
        for metric in MetricType.allCases {
            guard let range = metric.referenceRange else { continue }
            if let low = range.normal.low, let high = range.normal.high {
                XCTAssertLessThan(low, high, "\(metric)'s normal band is inverted")
            }
            XCTAssertFalse(range.caption.isEmpty, "\(metric) has a band and no caption")
            XCTAssertFalse(range.provenance.isEmpty, "\(metric) has a band and no source")
            XCTAssertEqual(range.edges, range.edges.sorted())
        }
    }

    /// The shoulders have to sit either side of the normal band, or the chart
    /// draws caution *inside* normal.
    func testCautionShouldersSitOutsideTheNormalBand() throws {
        for metric in MetricType.allCases {
            guard let range = metric.referenceRange else { continue }
            if let below = range.cautionBelow?.high, let normalLow = range.normal.low {
                XCTAssertLessThanOrEqual(below, normalLow, "\(metric)'s low shoulder overlaps normal")
            }
            if let above = range.cautionAbove?.low, let normalHigh = range.normal.high {
                XCTAssertGreaterThanOrEqual(above, normalHigh, "\(metric)'s high shoulder overlaps normal")
            }
        }
    }

    /// Every banded metric also offers a log axis, so "they can't overlap" is not
    /// available as an argument — the chart has to decline to shade explicitly,
    /// and this is the note that says why that check is load-bearing rather than
    /// defensive.
    func testBandedMetricsDoOfferALogAxisSoTheChartMustDeclineToShade() {
        let banded = MetricType.allCases.filter { $0.referenceRange != nil }
        XCTAssertFalse(banded.isEmpty)
        XCTAssertTrue(banded.allSatisfy { $0.presentation.allowsLogScale },
                      "if this ever stops holding, MultiSourceChart's log guard can relax")
    }

    /// Heart rate is the one the roadmap asked for and the one that must not
    /// have a band: its 40–100 bounds are for the *day's* representative value,
    /// and this chart plots raw samples, workouts included.
    func testHeartRateHasNoBandBecauseItPlotsRawSamples() {
        XCTAssertNil(MetricType.heartRate.referenceRange)
        XCTAssertNotNil(MetricType.restingHeartRate.referenceRange)
    }

    /// The ACC/AHA bands live in `BloodPressureEstimator.Category` and are drawn
    /// from there. A second copy is one copy too many.
    func testBloodPressureKeepsItsBandsInOnePlace() {
        XCTAssertNil(MetricType.bloodPressureSystolic.referenceRange)
        XCTAssertNil(MetricType.bloodPressureDiastolic.referenceRange)
    }

    // MARK: - Clipping and the decision not to shade

    func testAnOpenEndedBandIsClippedToTheDomain() throws {
        let range = try range(.heartRateRecovery)   // normal is 12 and up
        let bands = range.bands(in: 0...40)
        let normal = try XCTUnwrap(bands.first { $0.kind == .normal })
        XCTAssertEqual(normal.lower, 12)
        XCTAssertEqual(normal.upper, 40, "an open top must clip to the domain, not run off it")
    }

    /// A wholly green plot is not reassurance, it is ink. The caption already
    /// states the range in words.
    func testABandCoveringTheWholePlotIsNotDrawn() throws {
        let range = try range(.oxygenSaturation)    // normal 95–100
        XCTAssertTrue(range.bands(in: 95...100).isEmpty)
        XCTAssertFalse(range.bands(in: 88...100).isEmpty)
    }

    /// Normal draws last so it sits over the shoulders.
    func testTheNormalBandIsDrawnOverItsShoulders() throws {
        let bands = try range(.respiratoryRate).bands(in: 5...30)
        XCTAssertEqual(bands.last?.kind, .normal)
    }

    // MARK: - The axis

    /// An edge you cannot see conveys nothing, so the axis stretches to reach it.
    func testTheDomainWidensToBringABandEdgeOnScreen() throws {
        let range = try range(.oxygenSaturation)
        let domain = try XCTUnwrap(MetricReferenceRange.chartDomain(
            values: [96, 97, 98], reference: range))
        XCTAssertLessThanOrEqual(domain.lowerBound, 95, "the normal floor stayed off screen")
    }

    /// But not at any price: a tight CGM morning must not be flattened into a
    /// line so a 3.9–10.0 band can be drawn around it.
    func testTheDomainWillNotFlattenTheDataToReachAFarEdge() throws {
        let range = try range(.bloodGlucose)
        let values = [5.2, 5.4, 5.5, 5.3]
        let plain = try XCTUnwrap(paddedYDomain(values))
        let widened = try XCTUnwrap(MetricReferenceRange.chartDomain(
            values: values, reference: range))
        let plainSpan = plain.upperBound - plain.lowerBound
        let widenedSpan = widened.upperBound - widened.lowerBound
        XCTAssertLessThanOrEqual(widenedSpan, plainSpan * 4.01,
                                 "the expansion budget was ignored")
    }

    /// A metric with no range must get exactly the domain it got before.
    func testAMetricWithNoRangeKeepsItsPlainDomain() throws {
        let values = [60.0, 72, 85]
        XCTAssertEqual(MetricReferenceRange.chartDomain(values: values, reference: nil),
                       paddedYDomain(values))
    }
}

/// Twelve insights, eight validated hues. `Theme.insightTint` answered that with
/// a fixed table and a comment claiming safety because "never more than four are
/// on screen at once" — but the user picks which four, and four pairs shared a
/// hue. It stopped being hypothetical when Substance Impact got a score and could
/// reach the comparison chart at all.
final class InsightPaletteTests: XCTestCase {

    func testAnyChartfulOfInsightsResolvesToDistinctHues() {
        let all = InsightID.allCases
        for size in 1...InsightPalette.hueCount {
            for start in all.indices {
                let chosen = (0..<size).map { all[(start + $0) % all.count] }
                let slots = InsightPalette.slots(for: chosen)
                XCTAssertEqual(Set(slots.values).count, Set(chosen).count,
                               "two of \(chosen.map(\.rawValue)) share a hue")
            }
        }
    }

    /// The four pairs that used to collide, named so a future reshuffle can't
    /// quietly recreate them.
    func testThePreviouslyCollidingPairsAreSeparable() {
        let pairs: [(InsightID, InsightID)] = [
            (.heartAge, .bloodPressure),
            (.cardioFitness, .bodyComposition),
            (.heartHealth, .restingHeartRateTrend),
            (.cardioTrajectory, .substanceImpact)
        ]
        for (a, b) in pairs {
            let slots = InsightPalette.slots(for: [a, b])
            XCTAssertNotEqual(slots[a], slots[b], "\(a.rawValue) and \(b.rawValue) still collide")
        }
    }

    /// An insight keeps its own preferred hue wherever that hue is free, so the
    /// same card usually looks the same from one screen to the next.
    func testAnInsightKeepsItsPreferredHueWhenItIsFree() {
        let slots = InsightPalette.slots(for: [.readiness])
        XCTAssertEqual(slots[.readiness], InsightID.readiness.colourSlot)
    }

    func testEveryInsightHasADistinctPreference() {
        let preferences = InsightID.allCases.map(\.colourSlot)
        XCTAssertEqual(Set(preferences).count, preferences.count,
                       "two insights declare the same preferred slot")
    }
}
