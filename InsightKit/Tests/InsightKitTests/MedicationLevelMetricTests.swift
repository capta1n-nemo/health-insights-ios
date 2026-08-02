import XCTest
@testable import InsightKit

/// `activeMedicationLevel` is the only **modelled** metric in the app, and the
/// things that keep it from being mistaken for a measurement are the things
/// worth pinning.
final class MedicationLevelMetricTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    private func doses(_ count: Int, mg: Double = 5) -> [AdministeredDose] {
        (0..<count).map {
            AdministeredDose(takenAt: start.addingTimeInterval(Double($0) * 7 * 86_400),
                             milligrams: mg)
        }
    }

    func testDailySamplesAreOnePerDayAndCarryTheCalculatedSource() {
        let samples = PharmacokineticsModel.dailySamples(
            doses: doses(4), compound: .tirzepatide,
            from: start, to: start.addingTimeInterval(27 * 86_400))

        XCTAssertEqual(samples.count, 28)
        XCTAssertTrue(samples.allSatisfy { $0.type == .activeMedicationLevel })
        // **The honesty invariant.** Every screen that names a source reads
        // this; a device name here would present a model as a reading.
        XCTAssertTrue(samples.allSatisfy { $0.source == .calculated })
        XCTAssertEqual(MetricSource.calculated.displayName, "Worked out by this app")
    }

    func testTheLevelAccumulatesAcrossWeeklyDoses() {
        let samples = PharmacokineticsModel.dailySamples(
            doses: doses(6), compound: .tirzepatide,
            from: start, to: start.addingTimeInterval(41 * 86_400))
        // A weekly injectable with a five-day half-life is still climbing at
        // six weeks — the whole reason the curve is worth drawing.
        let firstWeek = samples.prefix(7).map(\.value).max() ?? 0
        let lastWeek = samples.suffix(7).map(\.value).max() ?? 0
        XCTAssertGreaterThan(lastWeek, firstWeek * 1.5)
    }

    func testNoDosesProducesNoSamples() {
        XCTAssertTrue(PharmacokineticsModel.dailySamples(
            doses: [], compound: .tirzepatide,
            from: start, to: start.addingTimeInterval(30 * 86_400)).isEmpty)
    }

    // MARK: - How the card treats it

    /// **The decision the user asked about.** They offered it a 2% weight so it
    /// would appear on the contributors chart. It appears there at weight 0
    /// instead: `MetricOverlayChart` draws contributors, not weights, so the
    /// chart was the real ask — and a weight would mean "more of this is
    /// better" or "less of this is better", neither of which is true of how
    /// much of a prescribed drug is in somebody.
    func testTheMedicationIsAContributorButIsNeverScored() {
        let samples = PharmacokineticsModel.dailySamples(
            doses: doses(4), compound: .tirzepatide,
            from: start, to: start.addingTimeInterval(27 * 86_400))
        let tracked = BodyCompositionInsight.trackedNotScored(samples: samples)

        let row = tracked.first { $0.metric == .activeMedicationLevel }
        XCTAssertNotNil(row, "it has to reach the contributors list to be drawn")
        XCTAssertEqual(row?.weight, 0)
        XCTAssertNil(row?.higherIsBetter, "neither direction is the good one")
        XCTAssertTrue(row?.detail.contains("not measured") == true,
                      "the row has to say it was worked out, not measured")
    }

    func testNoMedicationMeansNoRow() {
        let tracked = BodyCompositionInsight.trackedNotScored(samples: [])
        XCTAssertFalse(tracked.contains { $0.metric == .activeMedicationLevel })
    }

    /// Muscle mass was the only tracked-not-scored row before this one; adding
    /// a second must not have displaced it.
    func testMuscleMassSurvivesTheSecondTrackedRow() {
        let samples = [
            HealthMetricSample(type: .muscleMass, value: 40, start: start, source: .withings)
        ] + PharmacokineticsModel.dailySamples(
            doses: doses(2), compound: .tirzepatide,
            from: start, to: start.addingTimeInterval(13 * 86_400))
        let tracked = BodyCompositionInsight.trackedNotScored(samples: samples)
        XCTAssertEqual(Set(tracked.map(\.metric)), [.muscleMass, .activeMedicationLevel])
        XCTAssertTrue(tracked.allSatisfy { $0.weight == 0 })
    }

    // MARK: - Presentation

    func testItIsItsOwnFamilySoTheWeightPatternIsNotSuppressed() {
        XCTAssertEqual(MetricType.activeMedicationLevel.family, .pharmacology)
        // Same family reads as a tautology and is suppressed. Weight against
        // drug level is the one relationship this metric exists to show, so the
        // two must not share a family.
        XCTAssertFalse(MetricType.activeMedicationLevel
            .sharesMeasurementBasis(with: .bodyMass))
    }

    func testZeroIsARealReading() {
        // Before the first dose and long after the last. Sanitising it away
        // would make the curve start mid-air.
        XCTAssertFalse(MetricType.activeMedicationLevel.requiresPositiveValue)
    }

    func testThereIsNoNormalBandForADrugLevel() {
        // A band would read as a target dose, and this app never suggests one.
        XCTAssertNil(MetricType.activeMedicationLevel.referenceRange)
    }

    func testItFormatsToTwoDecimalsRatherThanWholeMilligrams() {
        // The default formatter rounds to whole numbers, which would render the
        // entire decay curve between two doses as a flat staircase.
        XCTAssertEqual(MetricValueFormatter.string(7.418, .activeMedicationLevel), "7.42")
    }

    func testItsNameSaysWhereItIsWithoutClaimingAMeasurement() {
        XCTAssertEqual(MetricType.activeMedicationLevel.displayName,
                       "Medication In Your System")
        XCTAssertEqual(MetricType.activeMedicationLevel.unit, "mg")
    }
}
