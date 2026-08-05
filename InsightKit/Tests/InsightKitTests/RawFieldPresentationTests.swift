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
        XCTAssertEqual(RawFieldPresentation.codedSeriesSummary(hypnogram), "25 values")
    }

    /// A real number, however long, is not a coded series — and a short digit
    /// string is a value, not a hypnogram.
    func testOrdinaryValuesAreNotMistakenForSeries() {
        XCTAssertFalse(RawFieldPresentation.isCodedSeries("12197"))
        XCTAssertFalse(RawFieldPresentation.isCodedSeries("35.89"),
                       "a decimal point means it is a number, not a stage code")
        XCTAssertFalse(RawFieldPresentation.isCodedSeries(""))
    }

    // MARK: - Names that are actually names
    //
    // All three of these were on screen the first time the grouped catalogue
    // rendered, in the simulator against the reader's own export. Leading with
    // the leaf is right, and is not enough on its own.

    /// **"Average" names nothing.** A leaf that describes how a number was
    /// reduced borrows its parent.
    func testAGenericLeafBorrowsItsParent() {
        XCTAssertEqual(
            RawFieldPresentation.title(forPath: "oura.daily_spo2.spo2_percentage.average"),
            "SpO₂ percentage average")
        // And a distinctive one does not — the eleven Oura contributors keep the
        // short names that made this readable in the first place.
        XCTAssertEqual(
            RawFieldPresentation.title(forPath: "oura.daily_activity.contributors.meeting_daily_targets"),
            "Meeting daily targets")
    }

    /// ⚠️ **"Contributors efficiency" and "Contributors latency"** — two rows
    /// that widened to a container name. `contributors` describes the shape of
    /// Oura's payload, not the subject of the field, so widening reaches past it
    /// to the thing a reader was trying to tell apart.
    func testWideningSkipsContainerNamesAndReachesSomethingThatNames() {
        let paths = ["oura.daily_sleep.contributors.efficiency",
                     "oura.daily_activity.contributors.efficiency"]
        let titles = RawFieldPresentation.titles(for: paths)
        for path in paths {
            let title = try? XCTUnwrap(titles[path])
            XCTAssertFalse(title?.lowercased().contains("contributors") ?? true,
                           "widened into a container name: \(title ?? "")")
        }
        XCTAssertEqual(titles[paths[0]], "Daily sleep efficiency")
        XCTAssertEqual(titles[paths[1]], "Daily activity efficiency")
    }

    /// **"Daily readiness hrv balance"** — a borrowed token moving mid-name gets
    /// its capital dropped, and an acronym must not. Seen on screen.
    func testAnAcronymKeepsItsCapitalsWhenBorrowedIntoTheMiddleOfAName() {
        let paths = ["oura.daily_readiness.contributors.hrv_balance",
                     "oura.daily_sleep.contributors.hrv_balance"]
        let titles = RawFieldPresentation.titles(for: paths)
        XCTAssertEqual(titles[paths[0]], "Daily readiness HRV balance")
        // And an ordinary word still loses it, or every name reads as a menu.
        XCTAssertEqual(RawFieldPresentation.decapitalised("Body temperature"),
                       "body temperature")
        XCTAssertEqual(RawFieldPresentation.decapitalised("SpO₂ percentage"),
                       "SpO₂ percentage")
    }

    /// **Two rows read "Activity balance", with different values.** A name only
    /// has to be unique among the names beside it, which is why the whole list
    /// resolves together.
    func testCollidingNamesEachGrowAParent() {
        let paths = ["oura.daily_readiness.contributors.activity_balance",
                     "oura.daily_sleep.contributors.activity_balance",
                     "oura.daily_activity.contributors.meeting_daily_targets"]
        let titles = RawFieldPresentation.titles(for: paths)

        XCTAssertNotEqual(titles[paths[0]], titles[paths[1]],
                          "two different fields still render as the same row")
        // Only the pair that clashed grows. The one that did not is untouched.
        XCTAssertEqual(titles[paths[2]], "Meeting daily targets")
        for path in paths.prefix(2) {
            XCTAssertTrue(titles[path]?.lowercased().contains("activity balance") == true,
                          "the disambiguated name lost the thing it names: \(titles[path] ?? "")")
        }
    }

    /// Three-way collisions resolve too, rather than being half-fixed by one
    /// pass and left ambiguous.
    func testAThreeWayCollisionFullyResolves() {
        let paths = ["a.one.deep.body_temperature",
                     "b.two.deep.body_temperature",
                     "c.three.deep.body_temperature"]
        let titles = RawFieldPresentation.titles(for: paths)
        XCTAssertEqual(Set(paths.compactMap { titles[$0] }).count, 3)
    }

    /// **"32.00 years" claims precision a vascular age does not have**, and a
    /// score out of 100 printed "70.00" on every row at once.
    func testNumbersAreShownInTheDigitsTheyHave() {
        XCTAssertEqual(RawFieldPresentation.formatted(32, unit: "years"), "32 years")
        XCTAssertEqual(RawFieldPresentation.formatted(70, unit: "count"), "70")
        XCTAssertEqual(RawFieldPresentation.formatted(6.5712, unit: ""), "6.57")
        XCTAssertEqual(RawFieldPresentation.formatted(757.4, unit: "kcal"), "757 kcal")
        // The conversion still happens on the way through.
        XCTAssertEqual(RawFieldPresentation.formatted(4184, unit: "kJ"), "1000 kcal")
    }
}
