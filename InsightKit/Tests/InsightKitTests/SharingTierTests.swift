import XCTest
@testable import InsightKit

/// **Two-tier sharing** — backlog B8 R5.
///
/// The point of the design is that the tier is a *function*, not a boolean
/// somebody has to remember to consult, so the guarantee is testable rather than
/// promised. The load-bearing assertion in this file is
/// `testMetadataOnlyCarriesNoFreeTextAtAll`: if it ever fails, a privacy claim
/// on the Settings screen has become false.
final class SharingTierTests: XCTestCase {

    private let title = "Quarterly review with Northwind"
    private let place = "Level 3, 200 Example St"

    private func judgement(corrected: Bool = true,
                           confirmed: Bool = true) -> CalendarEventJudgement {
        let guess = CalendarEventClassification(context: .work, occasion: .meeting,
                                                presence: .inPerson, formality: .formal,
                                                hours: 1.5)
        let truth = CalendarEventClassification(context: .personal, occasion: .meeting,
                                                presence: .inPerson, formality: .casual,
                                                hours: 1.5)
        return CalendarEventJudgement(
            eventID: "evt-1", classification: guess,
            correction: corrected ? truth : nil,
            isConfirmed: confirmed, reviewedAt: Date(timeIntervalSince1970: 0),
            artifact: CalendarEventArtifact(
                title: title, location: place, attendeeCount: 6,
                durationHours: 1.5, isAllDay: false, calendarName: "Work",
                hasVideoLink: true, organizerIsReader: false,
                capturedAt: Date(timeIntervalSince1970: 0)))
    }

    // MARK: - The defaults the reader asked for

    /// *"both opted in by default"* — the reader's own words, and the one
    /// setting in this app whose default was dictated rather than reasoned.
    func testBothTiersAreOnByDefault() {
        let preferences = SharingPreferences()
        XCTAssertTrue(preferences.isEnabled(.full))
        XCTAssertTrue(preferences.isEnabled(.metadataOnly))
        XCTAssertEqual(preferences, SharingPreferences.standard)
        XCTAssertFalse(preferences.sharesNothing)
    }

    /// Two switches, not one three-position control: turning `full` off must
    /// leave `metadataOnly` exactly where it was.
    func testEachTierSwitchesOffIndependently() {
        var preferences = SharingPreferences()
        preferences.setEnabled(false, for: .full)
        XCTAssertFalse(preferences.isEnabled(.full))
        XCTAssertTrue(preferences.isEnabled(.metadataOnly))
        XCTAssertEqual(preferences.enabledTiers, [.metadataOnly])
        XCTAssertEqual(preferences.effectiveTier, .metadataOnly)

        preferences.setEnabled(false, for: .metadataOnly)
        XCTAssertTrue(preferences.sharesNothing)
        XCTAssertNil(preferences.effectiveTier,
                     "both off means nothing goes — and the nil is the refusal")
    }

    /// `.full` is a superset, so where both are on it is the one that applies.
    func testFullWinsWhereBothAreOn() {
        XCTAssertEqual(SharingPreferences.standard.effectiveTier, .full)
    }

    // MARK: - The guarantee

    /// **The assertion the whole design exists to make available.**
    ///
    /// The fixture's title and location are the most identifying strings this
    /// app holds. Under `.metadataOnly` they must be absent from the record's
    /// fields, from its `freeText`, from its one-line summary, and from its
    /// encoded bytes — the last because a payload is what would actually leave,
    /// not a convenient accessor over it.
    func testMetadataOnlyCarriesNoFreeTextAtAll() throws {
        let record = try XCTUnwrap(judgement().sharedRecord(under: .metadataOnly))

        XCTAssertTrue(record.freeText.isEmpty,
                      "metadata-only leaked: \(record.freeText)")
        XCTAssertFalse(record.fields.contains { $0.value.isFreeText })
        XCTAssertNil(record.field("title"))
        XCTAssertNil(record.field("location"))
        XCTAssertNil(record.field("calendarName"))

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(record), encoding: .utf8))
        XCTAssertFalse(json.contains(title))
        XCTAssertFalse(json.contains(place))
        XCTAssertFalse(json.contains("Northwind"))
        XCTAssertFalse(record.summary.contains(title))
        XCTAssertFalse(record.summary.contains(place))
    }

    /// **The other half of the content boundary: a residual is shape, a reading
    /// is not.**
    ///
    /// The reader's own sentence for this tier is *"Blood pressure estimate is
    /// 13 BP above actual cuff"* — the 13 and not the 118. The test of the
    /// boundary is whether a recipient could reconstruct a reading about this
    /// person; with only the gap, they cannot.
    func testMetadataOnlyCarriesResidualsButNeverReadings() throws {
        let outcome = PredictionOutcome(
            insightID: .bloodPressure, metric: .bloodPressureSystolic,
            predicted: 131, actual: 118, modelVersion: "test",
            cohort: Cohort(sex: "male", ageBand: "30-39",
                           ethnicity: "unspecified", region: "unspecified"))
        let record = try XCTUnwrap(outcome.sharedRecord(under: .metadataOnly))

        XCTAssertTrue(record.readings.isEmpty, "a raw reading escaped: \(record.readings)")
        XCTAssertTrue(record.content.isEmpty)
        XCTAssertNil(record.field("estimated"))
        XCTAssertNil(record.field("measured"))
        XCTAssertEqual(record.field("difference"), .residual(13))

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(record), encoding: .utf8))
        XCTAssertFalse(json.contains("118"), "the cuff reading is reconstructible from the payload")
        XCTAssertFalse(json.contains("131"))
        XCTAssertTrue(json.contains("13"))
        // Coarse cohort survives: a norm needs strata, and a band names nobody.
        XCTAssertEqual(record.field("cohortAgeBand"), .category("30-39"))
    }

    /// `.full` is where the readings live, so the filter above is a filter and
    /// not an amputation.
    func testFullCarriesTheReadingsBehindTheResidual() throws {
        let outcome = PredictionOutcome(
            insightID: .bloodPressure, metric: .bloodPressureSystolic,
            predicted: 131, actual: 118, modelVersion: "test",
            cohort: Cohort(sex: "male", ageBand: "30-39",
                           ethnicity: "unspecified", region: "unspecified"))
        let record = try XCTUnwrap(outcome.sharedRecord(under: .full))
        XCTAssertEqual(record.readings.sorted(), [118, 131])
        XCTAssertEqual(record.field("measured"), .reading(118))
    }

    /// Every case of `SharedValue` has to have answered "is this about the
    /// person or about the model?", and adding one without answering it is the
    /// only way this design fails quietly.
    func testEveryValueKindHasDeclaredWhichSideOfTheBoundaryItIsOn() {
        XCTAssertTrue(SharedValue.freeText("x").isContent)
        XCTAssertTrue(SharedValue.reading(118).isContent)
        XCTAssertFalse(SharedValue.residual(13).isContent)
        XCTAssertFalse(SharedValue.category("work").isContent)
        XCTAssertFalse(SharedValue.number(6).isContent)
        XCTAssertFalse(SharedValue.flag(true).isContent)
    }

    /// The other half of the same guarantee: `.metadataOnly` is empty of words
    /// because words were *filtered*, not because the shaper produces nothing.
    /// A filter that empties everything passes the test above and is useless.
    func testFullCarriesTheArtifactsOwnWords() throws {
        let record = try XCTUnwrap(judgement().sharedRecord(under: .full))
        XCTAssertEqual(record.freeText.sorted(), [place, title, "Work"].sorted())
        XCTAssertTrue(record.summary.contains(title))
    }

    /// Both tiers keep the correction itself, because a move between cases of a
    /// closed enum the app defined names nobody. This is what `.metadataOnly` is
    /// *for* — the reader's *"a work guess was corrected to personal"*.
    func testBothTiersKeepTheBeforeAndAfterCategories() throws {
        for tier in SharingTier.allCases {
            let record = try XCTUnwrap(judgement().sharedRecord(under: tier))
            let context = try XCTUnwrap(record.changes.first { $0.axis == "context" })
            XCTAssertEqual(context.from, "work")
            XCTAssertEqual(context.to, "personal")
            XCTAssertTrue(record.changes.contains { $0.axis == "formality" })
            XCTAssertTrue(record.summary.contains("work"))
            XCTAssertTrue(record.summary.contains("personal"))
        }
    }

    /// The counts and durations are not free text and are exactly the
    /// quantities `docs/norms-and-telemetry.md` says a pooled norm needs, so
    /// `.metadataOnly` keeps them.
    func testMetadataOnlyKeepsTheShapeOfTheEvent() throws {
        let record = try XCTUnwrap(judgement().sharedRecord(under: .metadataOnly))
        XCTAssertEqual(record.field("attendeeCount"), .number(6))
        XCTAssertEqual(record.field("durationHours"), .number(1.5))
        XCTAssertEqual(record.field("hasVideoLink"), .flag(true))
    }

    /// An item nobody has looked at is not a correction. Sharing it as one
    /// would inflate any accuracy figure computed from the pool — the same
    /// refusal `CalendarClassifierAccuracy` already makes on device.
    func testAnUnreviewedJudgementSharesNothing() {
        let untouched = judgement(corrected: false, confirmed: false)
        for tier in SharingTier.allCases {
            XCTAssertNil(untouched.sharedRecord(under: tier))
        }
    }

    /// "You got it right" is a label in its own right and goes out with no
    /// changes attached.
    func testAConfirmationSharesWithNoChanges() throws {
        let record = try XCTUnwrap(
            judgement(corrected: false, confirmed: true).sharedRecord(under: .full))
        XCTAssertTrue(record.changes.isEmpty)
        XCTAssertTrue(record.summary.lowercased().contains("confirmed"))
    }

    // MARK: - The reader's own example

    /// *"Blood pressure esitmate is 13 BP above actual cuff"* — the reader's
    /// worked example, and the sentence the Settings screen shows.
    func testTheBloodPressureExampleReadsAsTheReaderDescribedIt() throws {
        let outcome = PredictionOutcome(
            insightID: .bloodPressure, metric: .bloodPressureSystolic,
            predicted: 131, actual: 118, modelVersion: "test",
            cohort: Cohort(sex: "unspecified", ageBand: "unspecified",
                           ethnicity: "unspecified", region: "unspecified"))
        let record = try XCTUnwrap(outcome.sharedRecord(under: .metadataOnly))

        XCTAssertEqual(record.field("difference"), .residual(13))
        XCTAssertTrue(record.summary.contains("13"))
        XCTAssertTrue(record.summary.contains("mmHg"), record.summary)
        XCTAssertTrue(record.summary.contains("above"), record.summary)
        XCTAssertTrue(record.freeText.isEmpty)
    }

    /// **The sentence survives the stripping.** The reader's example is what
    /// `.metadataOnly` produces, not a description of it — including the
    /// direction, which is a property of the residual's sign and needs neither
    /// reading to state.
    func testTheDirectionOfTheErrorSurvivesWithoutEitherReading() throws {
        let outcome = PredictionOutcome(
            insightID: .bloodPressure, metric: .bloodPressureSystolic,
            predicted: 110, actual: 118, modelVersion: "test",
            cohort: Cohort(sex: "unspecified", ageBand: "unspecified",
                           ethnicity: "unspecified", region: "unspecified"))
        let meta = try XCTUnwrap(outcome.sharedRecord(under: .metadataOnly))
        XCTAssertTrue(meta.summary.contains("below"), meta.summary)
        XCTAssertTrue(meta.summary.contains("8"), meta.summary)
        XCTAssertTrue(meta.readings.isEmpty)
    }

    // MARK: - The worked examples on the Settings screen

    /// The screen shows records built by the real shaper, so the promise it
    /// makes cannot drift from what the code does. These assertions are what
    /// stop somebody replacing them with hand-written strings later.
    func testTheWorkedExamplesGoThroughTheRealShaper() {
        let full = SharingExample.calendarCorrection(under: .full)
        let meta = SharingExample.calendarCorrection(under: .metadataOnly)

        XCTAssertEqual(full.tier, .full)
        XCTAssertEqual(meta.tier, .metadataOnly)
        XCTAssertTrue(full.summary.contains(SharingExample.eventTitle))
        XCTAssertFalse(meta.summary.contains(SharingExample.eventTitle))
        XCTAssertTrue(meta.freeText.isEmpty)
        XCTAssertFalse(full.freeText.isEmpty)

        for tier in SharingTier.allCases {
            XCTAssertTrue(SharingExample.estimateCorrection(under: tier)
                .summary.contains("13"))
        }
    }

    /// The tier's own description of itself has to agree with what it does, or
    /// the Settings copy is a stale privacy promise — the exact failure B8 R6
    /// exists to close.
    func testATiersStatedShapeMatchesWhatItProduces() throws {
        for tier in SharingTier.allCases {
            let record = try XCTUnwrap(judgement().sharedRecord(under: tier))
            XCTAssertEqual(tier.carriesContent, !record.content.isEmpty,
                           "\(tier.rawValue) says carriesContent == \(tier.carriesContent) and does the opposite")
            XCTAssertFalse(tier.title.isEmpty)
            XCTAssertFalse(tier.summary.isEmpty)
        }
    }
}
