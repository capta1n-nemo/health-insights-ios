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

    // MARK: - Withings measure numbers (reader: "make sense of those obscure ones")

    /// ⚠️ **Each name was checked against the reader's own values before being
    /// written**, because a mapping copied out of documentation is a guess until
    /// something confirms it. 226 reads 2318–2583, which is a basal metabolic
    /// rate in kcal and nothing else; 227 reads 28–31, which is an age; 170
    /// reads 4.5–5.5 unitless, which is a visceral-fat index.
    func testWithingsMeasureNumbersBecomeNames() {
        XCTAssertEqual(RawFieldPresentation.title(forPath: "withings.measure.226"),
                       "Basal metabolic rate")
        XCTAssertEqual(RawFieldPresentation.title(forPath: "withings.measure.170"),
                       "Visceral fat index")
        XCTAssertEqual(RawFieldPresentation.title(forPath: "withings.measure.227"),
                       "Metabolic age")
        XCTAssertEqual(RawFieldPresentation.title(forPath: "withings.measure.8"),
                       "Fat mass")
        // And a named measure survives collision widening intact — "Measure
        // visceral fat index" would be worse than the number.
        let titles = RawFieldPresentation.titles(for: ["withings.measure.170",
                                                       "withings.measure.226"])
        XCTAssertEqual(titles["withings.measure.170"], "Visceral fat index")
    }

    /// ⚠️ **Four Withings fields are not measurements at all** — how the reading
    /// was taken rather than what it says, and two of them are constant across
    /// every row the reader has. Listing a constant 1 as a data point is noise.
    func testRecordingDetailsAreNotMistakenForMeasurements() {
        // And each carries a NAME, not its wire key — seen on screen, the row
        // read "Attrib — how it was recorded — 0", which explains nothing.
        XCTAssertEqual(RawFieldPresentation.title(forPath: "withings.measure.attrib"),
                       "How it was measured")
        XCTAssertEqual(RawFieldPresentation.title(forPath: "oura.sleep.sleep_algorithm_version"),
                       "Sleep algorithm version")
        for identifier in ["withings.measure.attrib", "withings.measure.category",
                           "withings.measure.model", "withings.measure.modelid",
                           "oura.sleep.sleep_algorithm_version"] {
            XCTAssertTrue(RawFieldPresentation.isRecordingDetail(identifier), identifier)
        }
        for identifier in ["withings.measure.226", "oura.sleep.average_hrv",
                           "HKQuantityTypeIdentifierStepCount"] {
            XCTAssertFalse(RawFieldPresentation.isRecordingDetail(identifier), identifier)
        }
    }

    // MARK: - Metadata never renders as a reading (D27)

    /// ⚠️ **Naming a recording detail was only half the fix.** On screen the
    /// rows still read "How it was measured — 0", "Device model ID — 16",
    /// "Measurement categ… — 1" — each a code dressed as a measurement, with a
    /// trend chevron. A code either decodes to words or the row prints nothing.
    func testARecordingDetailCodeDecodesToWordsOrStaysSilent() {
        XCTAssertEqual(
            RawFieldPresentation.rowValue(0, unit: "", identifier: "withings.measure.attrib"),
            "Measured by the device")
        XCTAssertEqual(
            RawFieldPresentation.rowValue(2, unit: "", identifier: "withings.measure.attrib"),
            "Entered by hand")
        XCTAssertEqual(
            RawFieldPresentation.rowValue(1, unit: "", identifier: "withings.measure.category"),
            "A measurement")
        // An opaque identifier has no words, so it prints nothing at all —
        // "Device model ID — 16" is noise shaped like a reading.
        XCTAssertNil(RawFieldPresentation.rowValue(16, unit: "", identifier: "withings.measure.modelid"))
        XCTAssertNil(RawFieldPresentation.rowValue(3, unit: "", identifier: "oura.sleep.type"))
        // And an unobserved code is not guessed at — same rule as `unit(_:)`.
        XCTAssertNil(RawFieldPresentation.rowValue(7, unit: "", identifier: "withings.measure.attrib"))
    }

    /// An actual measurement keeps the unit-and-precision path — the new door
    /// must not change what walks through the old one.
    func testAnOrdinaryMeasurementStillRendersThroughRowValue() {
        XCTAssertEqual(
            RawFieldPresentation.rowValue(35.89, unit: "degC",
                                          identifier: "HKQuantityTypeIdentifierBasalBodyTemperature"),
            "35.9 °C")
        XCTAssertEqual(
            RawFieldPresentation.rowValue(70, unit: "count",
                                          identifier: "oura.daily_readiness.score"),
            "70")
    }

    // MARK: - Oura stress & resilience (D28)

    /// ⚠️ **`stress_high` is SECONDS of the day in that state.** The row
    /// printed the raw four-digit figure — hours of the day dressed as a
    /// count, beside neighbours whose numbers are readings.
    func testStressDurationsRenderAsTimeNotSeconds() {
        XCTAssertEqual(
            RawFieldPresentation.rowValue(9900, unit: "", identifier: "oura.daily_stress.stress_high"),
            "2h 45m")
        XCTAssertEqual(
            RawFieldPresentation.rowValue(1800, unit: "", identifier: "oura.daily_stress.recovery_high"),
            "30m")
    }

    /// A state word reads as a word; the hypnogram summary still works through
    /// the same door; an unfamiliar string passes through verbatim.
    func testStateWordsReadAsWordsAndEverythingElseIsUntouched() {
        XCTAssertEqual(
            RawFieldPresentation.rowText("normal", identifier: "oura.daily_stress.day_summary"),
            "Normal")
        XCTAssertEqual(
            RawFieldPresentation.rowText("solid", identifier: "oura.daily_resilience.level"),
            "Solid")
        XCTAssertEqual(
            RawFieldPresentation.rowText("3311111111111", identifier: "oura.sleep.hypnogram"),
            "13 values")
        XCTAssertEqual(
            RawFieldPresentation.rowText("Body Smart", identifier: "withings.measure.model"),
            "Body Smart")
    }

    /// The stress fields carry names, not leaf fragments — "Stress high" names
    /// nothing — and like the named Withings measures they survive list-wide
    /// collision resolution intact.
    func testStressFieldsCarryNames() {
        XCTAssertEqual(RawFieldPresentation.title(forPath: "oura.daily_stress.stress_high"),
                       "Time stressed")
        XCTAssertEqual(RawFieldPresentation.title(forPath: "oura.daily_stress.recovery_high"),
                       "Time restored")
        XCTAssertEqual(RawFieldPresentation.title(forPath: "oura.daily_resilience.level"),
                       "Resilience level")
        let titles = RawFieldPresentation.titles(for: ["oura.daily_stress.stress_high",
                                                       "oura.daily_stress.day_summary"])
        XCTAssertEqual(titles["oura.daily_stress.stress_high"], "Time stressed")
        XCTAssertEqual(titles["oura.daily_stress.day_summary"], "Day summary")
    }
}
