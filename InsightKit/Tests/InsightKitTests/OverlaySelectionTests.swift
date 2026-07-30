import XCTest
@testable import InsightKit

/// The bug these exist for: thirteen vitals with nine away from baseline is an
/// ordinary week. "Draw only the anomalous ones" left nine lines against eight
/// hues, so the ninth wrapped and Walking Asymmetry came out the same red as
/// Skin Temperature Deviation. It reached the phone because the rule lived in
/// the view layer where nothing could test it.
final class OverlaySelectionTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A series whose furthest departure from baseline is `peak`.
    private func series(_ metric: MetricType, peak: Double) -> NormalizedSeries {
        let points = (0..<20).map { day in
            NormalizedPoint(date: now.addingTimeInterval(-Double(19 - day) * 86_400),
                            z: day == 19 ? peak : 0.1,
                            raw: 50 + peak)
        }
        return NormalizedSeries(metric: metric, higherIsBetter: true,
                                points: points, baseline: 50)
    }

    /// Thirteen signals, nine of them away from baseline — the exact shape from
    /// the screenshot.
    private func crowdedWeek() -> [NormalizedSeries] {
        let departing: [MetricType] = [
            .oxygenSaturation, .bodyTemperature, .heartRateVariabilitySDNN,
            .heartRateVariabilityRMSSD, .heartRate, .respiratoryRate,
            .restingHeartRate, .skinTemperatureDeviation, .walkingAsymmetry
        ]
        let routine: [MetricType] = [
            .bloodPressureSystolic, .bloodPressureDiastolic,
            .walkingSteadiness, .sleepDurationHours
        ]
        return departing.enumerated().map { series($0.element, peak: 3.0 - Double($0.offset) * 0.1) }
            + routine.map { series($0, peak: 0.4) }
    }

    func testNeverDrawsMoreSeriesThanThereAreHues() {
        let drawn = OverlaySelection.visible(crowdedWeek(), showingAll: false)
        XCTAssertLessThanOrEqual(drawn.count, MetricPalette.hueCount)
    }

    /// The property that actually matters, stated directly: whatever is drawn,
    /// no two of them may share a colour.
    func testEveryDrawnSeriesGetsItsOwnHue() {
        let drawn = OverlaySelection.visible(crowdedWeek(), showingAll: false)
        let slots = MetricPalette.slots(for: drawn.map(\.metric))
        XCTAssertEqual(Set(slots.values).count, drawn.count,
                       "two drawn series share a hue")
    }

    /// Which eight survive is not arbitrary — the furthest from baseline do.
    func testTheMostDepartedSurviveTheCap() {
        let drawn = OverlaySelection.visible(crowdedWeek(), showingAll: false)
        XCTAssertTrue(drawn.contains { $0.metric == .oxygenSaturation },
                      "the largest departure must be drawn")
        XCTAssertFalse(drawn.contains { $0.metric == .walkingAsymmetry },
                       "the smallest departure is the one to drop")
    }

    /// Nothing routine gets in ahead of something that departed.
    func testRoutineSeriesAreNeverDrawnOverDepartingOnes() {
        let drawn = OverlaySelection.visible(crowdedWeek(), showingAll: false)
        XCTAssertTrue(drawn.allSatisfy { OverlaySelection.isNotable($0) })
    }

    /// Six or fewer inputs: there are enough colours, so nothing is hidden even
    /// when every one of them is sitting on baseline.
    func testASmallCardDrawsEverything() {
        let small = [MetricType.heartRate, .sleepDurationHours, .oxygenSaturation,
                     .respiratoryRate, .bodyTemperature, .restingHeartRate]
            .map { series($0, peak: 0.2) }
        XCTAssertEqual(small.count, MetricPalette.comfortableSeriesCount)
        XCTAssertEqual(OverlaySelection.visible(small, showingAll: false).count, small.count)
        XCTAssertFalse(OverlaySelection.filters(small, showingAll: false))
    }

    /// Asking for every signal overrides the cap: past the palette a repeat is
    /// unavoidable, and the user asked for it explicitly.
    func testShowingAllOverridesBothTheFilterAndTheCap() {
        let all = crowdedWeek()
        XCTAssertEqual(OverlaySelection.visible(all, showingAll: true).count, all.count)
    }

    /// Order is preserved, so a series keeps its hue when a neighbour drops out
    /// rather than the whole chart repainting.
    func testDrawnSeriesKeepTheirOriginalOrder() {
        let week = crowdedWeek()
        let drawn = OverlaySelection.visible(week, showingAll: false).map(\.metric)
        let expected = week.map(\.metric).filter { drawn.contains($0) }
        XCTAssertEqual(drawn, expected)
    }

    /// Same input, same eight — no shuffling between renders.
    func testSelectionIsStableAcrossCalls() {
        let week = crowdedWeek()
        XCTAssertEqual(OverlaySelection.visible(week, showingAll: false).map(\.metric),
                       OverlaySelection.visible(week, showingAll: false).map(\.metric))
    }

    /// Ties are broken deterministically rather than by sort order, which Swift
    /// does not guarantee to be stable.
    func testTiedDeparturesResolveDeterministically() {
        let tied = [MetricType.heartRate, .heartRateVariabilityRMSSD, .oxygenSaturation,
                    .bodyTemperature, .bloodPressureSystolic, .bloodGlucose,
                    .restingHeartRate, .walkingSteadiness, .respiratoryRate]
            .map { series($0, peak: 2.0) }
        let first = OverlaySelection.visible(tied, showingAll: false).map(\.metric)
        XCTAssertEqual(first.count, MetricPalette.hueCount)
        XCTAssertEqual(first, OverlaySelection.visible(tied, showingAll: false).map(\.metric))
    }
}

/// "HRV and resting heart rate move in opposite directions (r = −0.71)" reached
/// the patterns card. Both are computed from the same beat-to-beat intervals, so
/// that is arithmetic wearing the clothes of a finding — and it crowds out the
/// cross-system observations the card exists for.
final class MeasurementBasisTests: XCTestCase {

    func testHeartRateAndVariabilityShareABasisDespiteDifferentFamilies() {
        XCTAssertNotEqual(MetricType.restingHeartRate.family,
                          MetricType.heartRateVariabilityRMSSD.family)
        XCTAssertTrue(MetricType.restingHeartRate
            .sharesMeasurementBasis(with: .heartRateVariabilityRMSSD))
    }

    func testTwoReadingsOfOneMeasurementShareABasis() {
        XCTAssertTrue(MetricType.bodyTemperature
            .sharesMeasurementBasis(with: .skinTemperatureDeviation))
        XCTAssertTrue(MetricType.bloodPressureSystolic
            .sharesMeasurementBasis(with: .bloodPressureDiastolic))
    }

    /// The relation must not swallow genuine cross-system pairs, which are the
    /// whole point of the card.
    func testUnrelatedSystemsDoNotShareABasis() {
        XCTAssertFalse(MetricType.sleepDurationHours.sharesMeasurementBasis(with: .oxygenSaturation))
        XCTAssertFalse(MetricType.restingHeartRate.sharesMeasurementBasis(with: .sleepDurationHours))
        XCTAssertFalse(MetricType.bodyMass.sharesMeasurementBasis(with: .stepCount))
    }

    func testTheRelationIsSymmetricAndReflexive() {
        for a in MetricType.allCases {
            XCTAssertTrue(a.sharesMeasurementBasis(with: a))
            for b in MetricType.allCases {
                XCTAssertEqual(a.sharesMeasurementBasis(with: b),
                               b.sharesMeasurementBasis(with: a))
            }
        }
    }
}
