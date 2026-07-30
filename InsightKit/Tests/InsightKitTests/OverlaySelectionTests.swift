import XCTest
@testable import InsightKit

/// The bug these exist for: thirteen vitals with nine away from baseline is an
/// ordinary week. "Draw only the anomalous ones" left nine lines against eight
/// hues, so the ninth wrapped and Walking Asymmetry came out the same red as
/// Skin Temperature Deviation. It reached the phone because the rule lived in
/// the view layer where nothing could test it.
final class OverlaySelectionTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A series that sat `level` SDs off baseline every day of the window.
    private func sustained(_ metric: MetricType, level: Double,
                           days: Int = 30) -> NormalizedSeries {
        series(metric, zs: Array(repeating: level, count: days))
    }

    /// A flat series with one spike `daysAgo` — the shape that made body
    /// temperature read as "steady" in the legend and get drawn as notable.
    private func blip(_ metric: MetricType, peak: Double, daysAgo: Int,
                      days: Int = 30) -> NormalizedSeries {
        var zs = Array(repeating: 0.1, count: days)
        zs[days - 1 - daysAgo] = peak
        return series(metric, zs: zs)
    }

    /// `endingDaysAgo` moves the whole series back in time without changing its
    /// shape — the difference between "anchored to the data" and "anchored to
    /// the clock".
    private func series(_ metric: MetricType, zs: [Double],
                        endingDaysAgo: Int = 0) -> NormalizedSeries {
        let end = now.addingTimeInterval(-Double(endingDaysAgo) * 86_400)
        let points = zs.enumerated().map { index, z in
            NormalizedPoint(date: end.addingTimeInterval(-Double(zs.count - 1 - index) * 86_400),
                            z: z, raw: 50 + z)
        }
        return NormalizedSeries(metric: metric, higherIsBetter: true,
                                points: points, baseline: 50)
    }

    // MARK: - Steady signals stay off

    /// The reported bug: a flat signal with one departure three weeks ago was
    /// drawn on a chart whose own legend called it "steady".
    func testAnOldBlipDoesNotMakeASteadySignalNotable() {
        XCTAssertFalse(OverlaySelection.isNotable(blip(.bodyTemperature, peak: 3, daysAgo: 21)))
    }

    /// But a departure that is still current is a finding, even if the rest of
    /// the month was flat. A fever yesterday must not be averaged away.
    func testARecentSpikeIsStillNotable() {
        XCTAssertTrue(OverlaySelection.isNotable(blip(.bodyTemperature, peak: 3, daysAgo: 1)))
    }

    /// A signal that sits off baseline every day is doing something a single
    /// spike is not.
    func testASustainedDepartureIsNotable() {
        XCTAssertTrue(OverlaySelection.isNotable(sustained(.restingHeartRate, level: 1.8)))
        XCTAssertFalse(OverlaySelection.isNotable(sustained(.restingHeartRate, level: 0.4)))
    }

    /// The sustained term earning its place: three weeks well off baseline,
    /// then a quiet week. The recent term sees nothing, and a rule built on it
    /// alone would drop a signal mid-recovery from a month-long excursion.
    func testALongExcursionStaysNotableThroughAQuietWeek() {
        // The quiet tail is one day longer than the recent window, since that
        // window is inclusive at its far edge.
        let quietDays = OverlaySelection.recentDays + 1
        let recovering = series(.restingHeartRate,
                                zs: Array(repeating: 3.0, count: 30 - quietDays)
                                    + Array(repeating: 0.4, count: quietDays))
        XCTAssertLessThan(recovering.points.suffix(quietDays).map { abs($0.z) }.max() ?? 0,
                          OverlaySelection.notableZ,
                          "fixture must be quiet recently, or this proves nothing")
        XCTAssertTrue(OverlaySelection.isNotable(recovering))
    }

    /// Anomaly is measured against the newest reading, not the clock, so a
    /// series that stopped reporting months ago doesn't quietly lose its recent
    /// term and sink down the list as time passes.
    func testAnomalyIsAnchoredToTheDataNotTheClock() {
        let zs = Array(repeating: 0.1, count: 29) + [3.0]
        XCTAssertEqual(OverlaySelection.anomaly(series(.heartRate, zs: zs)),
                       OverlaySelection.anomaly(series(.heartRate, zs: zs, endingDaysAgo: 100)),
                       accuracy: 0.0001)
        XCTAssertTrue(OverlaySelection.isNotable(series(.heartRate, zs: zs, endingDaysAgo: 100)))
    }

    // MARK: - Ranking

    func testTheListIsOrderedMostDepartedFirst() {
        let mixed = [sustained(.heartRate, level: 0.2),
                     sustained(.oxygenSaturation, level: 2.5),
                     sustained(.respiratoryRate, level: 1.0)]
        XCTAssertEqual(OverlaySelection.ranked(mixed).map(\.metric),
                       [.oxygenSaturation, .respiratoryRate, .heartRate])
    }

    func testEqualDeparturesRankDeterministically() {
        let tied = [sustained(.respiratoryRate, level: 2), sustained(.heartRate, level: 2)]
        XCTAssertEqual(OverlaySelection.ranked(tied).map(\.metric),
                       OverlaySelection.ranked(tied).map(\.metric))
        // Lower style index wins, not sort order — Swift's sort isn't stable.
        XCTAssertEqual(OverlaySelection.ranked(tied).first?.metric, .heartRate)
    }

    // MARK: - The default selection

    /// The screenshot's shape: thirteen signals, nine of them departing.
    private func crowdedWeek() -> [NormalizedSeries] {
        let departing: [MetricType] = [
            .oxygenSaturation, .heartRateVariabilitySDNN, .heartRateVariabilityRMSSD,
            .heartRate, .respiratoryRate, .restingHeartRate, .walkingAsymmetry,
            .bloodPressureSystolic, .bloodGlucose
        ]
        let steady: [MetricType] = [.bodyTemperature, .skinTemperatureDeviation,
                                    .walkingSteadiness, .sleepDurationHours]
        return departing.enumerated().map { sustained($0.element, level: 3.0 - Double($0.offset) * 0.1) }
            + steady.map { sustained($0, level: 0.2) }
    }

    func testTheDefaultNeverExceedsThePalette() {
        XCTAssertLessThanOrEqual(OverlaySelection.defaultSelection(crowdedWeek()).count,
                                 MetricPalette.hueCount)
    }

    /// The property that matters: whatever is drawn, no two of them share a hue.
    func testEveryDrawnSeriesGetsItsOwnHue() {
        let week = crowdedWeek()
        let drawn = OverlaySelection.visible(week, selected: OverlaySelection.defaultSelection(week))
        let slots = MetricPalette.slots(for: drawn.map(\.metric))
        XCTAssertEqual(Set(slots.values).count, drawn.count, "two drawn series share a hue")
    }

    func testSteadySignalsAreNotSelectedByDefault() {
        let picked = OverlaySelection.defaultSelection(crowdedWeek())
        XCTAssertFalse(picked.contains(.bodyTemperature))
        XCTAssertFalse(picked.contains(.skinTemperatureDeviation))
    }

    func testTheMostDepartedAreSelectedByDefault() {
        let picked = OverlaySelection.defaultSelection(crowdedWeek())
        XCTAssertTrue(picked.contains(.oxygenSaturation), "the largest departure must be drawn")
        XCTAssertFalse(picked.contains(.bloodGlucose), "the smallest departure is the one to drop")
    }

    func testNothingRoutineIsSelectedOverSomethingDeparting() {
        let week = crowdedWeek()
        let picked = OverlaySelection.defaultSelection(week)
        XCTAssertTrue(week.filter { picked.contains($0.metric) }
            .allSatisfy { OverlaySelection.isNotable($0) })
    }

    /// Six or fewer inputs: there are more hues than series, so everything is
    /// drawn — on a small card "nothing happened here" is worth seeing.
    func testASmallCardDrawsEverythingIncludingTheQuietOnes() {
        let small = [MetricType.heartRate, .sleepDurationHours, .oxygenSaturation,
                     .respiratoryRate, .bodyTemperature, .restingHeartRate]
            .map { sustained($0, level: 0.2) }
        XCTAssertEqual(small.count, MetricPalette.comfortableSeriesCount)
        XCTAssertEqual(OverlaySelection.defaultSelection(small).count, small.count)
    }

    // MARK: - Manual selection

    /// Picking is not restricted by the cap — it's the reader's chart. The
    /// legend warns that colours repeat rather than refusing the request.
    func testAnExplicitSelectionIsHonouredEvenPastThePalette() {
        let week = crowdedWeek()
        let all = Set(week.map(\.metric))
        XCTAssertEqual(OverlaySelection.visible(week, selected: all).count, week.count)
    }

    func testAnEmptySelectionDrawsNothing() {
        XCTAssertTrue(OverlaySelection.visible(crowdedWeek(), selected: []).isEmpty)
    }

    /// Drawing order follows the original list, not the order things were
    /// ticked, so a series keeps its hue when a neighbour is switched off.
    func testDrawingOrderIsIndependentOfSelectionOrder() {
        let week = crowdedWeek()
        let chosen: Set<MetricType> = [.walkingAsymmetry, .oxygenSaturation, .heartRate]
        XCTAssertEqual(OverlaySelection.visible(week, selected: chosen).map(\.metric),
                       week.map(\.metric).filter { chosen.contains($0) })
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
