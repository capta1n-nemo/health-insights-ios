import XCTest
@testable import InsightKit

/// Every case here is a row the reader can see in their own Data tab today.
final class RawFieldPresentationTests: XCTestCase {

    /// **"count" is not a unit**, and it was the clearest nonsense on the
    /// screen: `Body Mass Index  32.26 count`.
    func testCountIsNotAUnit() {
        XCTAssertEqual(RawFieldPresentation.unit("count"), "")
        XCTAssertEqual(RawFieldPresentation.unit("count/min"), "/min")
    }

    func testMachineUnitsBecomeReadableOnes() {
        XCTAssertEqual(RawFieldPresentation.unit("degC"), "°C")
        XCTAssertEqual(RawFieldPresentation.unit("dBASPL"), "dB")
        XCTAssertEqual(RawFieldPresentation.unit("km/hr"), "km/h")
    }

    /// **An unfamiliar unit passes through unchanged.** Showing it verbatim is
    /// honest; guessing at it is not, and a mapping that invents an answer for
    /// anything it has not seen would be wrong silently.
    func testAnUnknownUnitIsNotGuessedAt() {
        XCTAssertEqual(RawFieldPresentation.unit("furlongs/fortnight"), "furlongs/fortnight")
        XCTAssertEqual(RawFieldPresentation.unit(""), "")
    }

    /// Two energy units on one tab makes the reader do arithmetic to compare
    /// their own data. Apple reports basal energy in kJ; everything else here
    /// is kcal.
    func testKilojoulesBecomeKilocalories() {
        let (value, unit) = RawFieldPresentation.converted(418.4, unit: "kJ")
        XCTAssertEqual(value, 100, accuracy: 0.01)
        XCTAssertEqual(unit, "kcal")
    }

    func testConversionLeavesEverythingElseAlone() {
        let (value, unit) = RawFieldPresentation.converted(35.89, unit: "degC")
        XCTAssertEqual(value, 35.89, accuracy: 0.001)
        XCTAssertEqual(unit, "°C")
    }

    // MARK: - Titles

    /// **The leaf carries the meaning and it was the part being truncated.**
    /// `oura.daily_activity.contributors.meeting_daily_targets` rendered as
    /// "Daily activity · Contributors: Mee…" — every visible character shared
    /// with its siblings, and the distinguishing word cut off.
    func testTheDistinguishingWordSurvives() {
        XCTAssertEqual(
            RawFieldPresentation.title(forPath: "oura.daily_activity.contributors.meeting_daily_targets"),
            "Meeting daily targets")
        XCTAssertEqual(
            RawFieldPresentation.title(forPath: "oura.daily_activity.contributors.stay_active"),
            "Stay active")
    }

    /// Two sibling contributors must not render identically — the whole point.
    func testSiblingsAreDistinguishable() {
        let a = RawFieldPresentation.title(forPath: "oura.daily_activity.contributors.training_frequency")
        let b = RawFieldPresentation.title(forPath: "oura.daily_activity.contributors.training_volume")
        XCTAssertNotEqual(a, b)
    }

    func testAcronymsSurviveLowerCasing() {
        XCTAssertEqual(RawFieldPresentation.humanised("vo2_max"), "VO₂ max")
        XCTAssertEqual(RawFieldPresentation.humanised("average_hrv"), "Average HRV")
        XCTAssertEqual(RawFieldPresentation.humanised("spo2_percentage"), "SpO₂ percentage")
    }

    func testCamelCaseSplitsWithoutBreakingAcronymRuns() {
        XCTAssertEqual(RawFieldPresentation.humanised("equivalentWalkingDistance"),
                       "Equivalent walking distance")
    }

    /// Sentence case, not Title Case: a column of Capitalised Words reads as a
    /// menu rather than as a list of names.
    func testSentenceCaseNotTitleCase() {
        XCTAssertEqual(RawFieldPresentation.humanised("high_activity_time"), "High activity time")
    }

    // MARK: - Values that are not scalars

    /// Oura's hypnogram is a per-five-minute stage code. Printed as a value it
    /// says nothing and shoves every other column off the row.
    func testACodedSeriesIsRecognisedAndSummarised() {
        let hypnogram = "3311111111111222211114444"
        XCTAssertTrue(RawFieldPresentation.isCodedSeries(hypnogram))
        XCTAssertEqual(RawFieldPresentation.codedSeriesSummary(hypnogram), "25 steps")
    }

    /// A real number, however long, is not a coded series — and a short digit
    /// string is a value, not a hypnogram.
    func testOrdinaryValuesAreNotMistakenForSeries() {
        XCTAssertFalse(RawFieldPresentation.isCodedSeries("12197"))
        XCTAssertFalse(RawFieldPresentation.isCodedSeries("35.89"),
                       "a decimal point means it is a number, not a stage code")
        XCTAssertFalse(RawFieldPresentation.isCodedSeries(""))
    }
}
