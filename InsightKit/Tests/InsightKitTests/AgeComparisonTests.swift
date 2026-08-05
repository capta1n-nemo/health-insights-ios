import XCTest
@testable import InsightKit

/// Roadmap #18. Four different answers to "what age does this body look like",
/// each on a different card, with no way to see that they disagree.
///
/// The competitive scan is the reason this is worth building and the reason it
/// is built this way: Whoop sells a "WHOOP Age", Oura prints a cardiovascular
/// age, and **neither publishes what its number is worth**. These pin the two
/// rules that make the difference — relay rather than merge, and print the
/// error or say plainly that there isn't one.
final class AgeComparisonTests: XCTestCase {

    private let now = TestClock.now

    private func vascularSamples(_ value: Double) -> [HealthMetricSample] {
        (0..<20).map { day in
            HealthMetricSample(type: .vascularAge, value: value,
                               start: now.addingTimeInterval(-Double(day) * 86_400),
                               source: .oura)
        }
    }

    // MARK: - Relay, never merge

    /// **The rule the whole section rests on.** Averaging four estimates into
    /// one house number invents a precision none of them has, so every estimate
    /// stays its own row and names whoever computed it.
    func testEveryEstimateNamesWhoComputedIt() {
        let estimates = AgeComparison.estimates(
            chronological: 40,
            fitness: FitnessAgeModel.evaluate(vo2: 46, sex: .male, chronologicalAge: 40),
            heart: nil, sex: .male,
            samples: vascularSamples(32), now: now, calendar: TestClock.utc)

        XCTAssertGreaterThanOrEqual(estimates.count, 3)
        for estimate in estimates {
            XCTAssertFalse(estimate.attribution.isEmpty,
                           "\(estimate.label) was reported with nobody's name on it")
        }
        // The vendor's number carries the vendor's name, not the app's.
        let vascular = estimates.first { $0.label == "Vascular age" }
        XCTAssertEqual(vascular?.attribution, "Oura")
        XCTAssertEqual(vascular?.years, 32)
    }

    /// ⚠️ **A relayed number must not read as the app's own.** Oura publishes a
    /// cardiovascular age with no error at all, and saying that plainly is the
    /// most useful sentence available about it.
    func testAVendorNumberWithNoPublishedErrorSaysSo() throws {
        let estimates = AgeComparison.estimates(
            chronological: 40, fitness: nil, heart: nil, sex: .male,
            samples: vascularSamples(32), now: now, calendar: TestClock.utc)
        let vascular = try XCTUnwrap(estimates.first { $0.label == "Vascular age" })

        XCTAssertNil(vascular.uncertainty.years,
                     "an error was invented for a number the vendor publishes bare")
        XCTAssertTrue(vascular.uncertainty.note.contains("without an error"))
        XCTAssertTrue(vascular.uncertainty.note.contains("Oura"))
    }

    // MARK: - The errors, which are derived rather than cited

    /// The app's own fitness age carries an error it can actually justify: the
    /// norm table it inverts moves a known number of years per mL/kg·min, so a
    /// VO₂max error converts straight into an age error.
    func testTheFitnessAgeErrorIsDerivedFromTheTableItInverts() throws {
        let estimates = AgeComparison.estimates(
            chronological: 40,
            fitness: FitnessAgeModel.evaluate(vo2: 46, sex: .male, chronologicalAge: 40),
            heart: nil, sex: .male, samples: [], now: now, calendar: TestClock.utc)
        let fitness = try XCTUnwrap(estimates.first { $0.label == "Fitness age" })
        let years = try XCTUnwrap(fitness.uncertainty.years)

        // The male table runs 48 → 32 mL/kg·min across 25 → 65 years: 2.5 years
        // per unit, so a ±3.5 VO₂max is roughly ±9 years.
        XCTAssertEqual(AgeComparison.vo2YearsPerUnit(sex: .male), 2.5, accuracy: 0.01)
        XCTAssertEqual(years, 9, accuracy: 0.5)
        XCTAssertTrue(fitness.uncertainty.note.contains("mL/kg·min"),
                      "the error was printed without saying where it came from")
    }

    /// ⚠️ **An honest "we cannot say" beats an invented number.** Where only one
    /// risk equation covers the reader's age there is nothing to measure the
    /// heart age against, and the section says that rather than printing a
    /// figure with no basis.
    func testAnUnmeasurableErrorIsStatedAsUnmeasurableRatherThanGuessed() {
        let single = HeartAgeModel.Output(
            chronologicalAge: 40,
            readings: [.init(engine: .score2, heartAge: 48, excessYears: 8,
                             isCapped: false, riskPercent: 4, optimalRiskPercent: 2)])
        let estimates = AgeComparison.estimates(
            chronological: 40, fitness: nil, heart: single, sex: .male,
            samples: [], now: now, calendar: TestClock.utc)
        let heart = estimates.first { $0.label == "Heart age" }

        XCTAssertNil(heart?.uncertainty.years)
        XCTAssertTrue(heart?.uncertainty.note.contains("nothing to measure") ?? false)
    }

    // MARK: - The finding

    /// **When they disagree by more than their errors allow, that is the
    /// finding** — and it is more useful than any single number here, because it
    /// tells the reader how much to trust the idea of a biological age at all.
    func testAWideDisagreementIsReportedAsTheFinding() throws {
        let estimates = AgeComparison.estimates(
            chronological: 40,
            fitness: FitnessAgeModel.evaluate(vo2: 55, sex: .male, chronologicalAge: 40),
            heart: nil, sex: .male,
            samples: vascularSamples(62), now: now, calendar: TestClock.utc)
        let text = try XCTUnwrap(AgeComparison.disagreement(estimates))

        XCTAssertTrue(text.contains("disagree"))
        XCTAssertTrue(text.lowercased().contains("biological age"),
                      "the finding did not say what the disagreement means")
    }

    /// And two estimates inside their own error bars are **not** disagreeing —
    /// they are the same answer measured twice. Saying otherwise would make the
    /// loudest sentence on the section the one that fires most often.
    func testEstimatesInsideTheirOwnErrorAreNotCalledADisagreement() {
        let estimates = AgeComparison.estimates(
            chronological: 40,
            fitness: FitnessAgeModel.evaluate(vo2: 44, sex: .male, chronologicalAge: 40),
            heart: nil, sex: .male,
            samples: vascularSamples(43), now: now, calendar: TestClock.utc)
        XCTAssertNil(AgeComparison.disagreement(estimates))
    }

    /// Your real age is not an estimate and must never widen the spread.
    func testYourRealAgeIsNotCountedAsAnEstimate() throws {
        let estimates = AgeComparison.estimates(
            chronological: 20,
            fitness: FitnessAgeModel.evaluate(vo2: 40, sex: .male, chronologicalAge: 20),
            heart: nil, sex: .male,
            samples: vascularSamples(45), now: now, calendar: TestClock.utc)
        let spread = try XCTUnwrap(AgeComparison.spread(estimates))
        let guesses = estimates.filter { $0.label != "Your age" }.map(\.years)
        let expected = try XCTUnwrap(guesses.max()) - (try XCTUnwrap(guesses.min()))
        XCTAssertEqual(spread, expected, accuracy: 0.001)
    }
}
