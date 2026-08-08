import XCTest
@testable import InsightKit

/// **The test that stands between a refactor and the reader's whole test-result
/// history.**
///
/// Lab results are stored as a JSON payload inside `LabResultRecord`, and
/// `DataStore.labResults()` decodes each row with `try?` inside a `compactMap`.
/// A row that will not decode is therefore **dropped without an error, a log or a
/// warning** — so if `LabValue`'s decoder ever stops reading the shape written
/// before 2026-08-09, every existing result disappears and the Data tab reads
/// "no test results yet".
///
/// The literal strings below are pinned on purpose. Round-tripping the current
/// encoder against the current decoder proves nothing about a payload written by
/// a build that no longer exists, and that is the only payload the reader
/// actually has on disk.
final class LabValueCodecTests: XCTestCase {

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: - The legacy shape

    /// Schema ≤ 7 wrote `LabResult.value` as a bare `Double`.
    func testALegacyBareNumberStillDecodes() throws {
        let legacy = Data(#"5.2"#.utf8)
        let value = try decoder.decode(LabValue.self, from: legacy)
        XCTAssertEqual(value, .quantitative(5.2))
        XCTAssertEqual(value.measuredNumber, 5.2)
    }

    /// A whole legacy `LabResult` payload, exactly as `LabResultRecord` stored it
    /// before `LabValue` existed. If this fails, the reader's history is gone.
    func testALegacyLabResultPayloadStillDecodes() throws {
        let legacy = Data("""
        {
          "id": "1B4E28BA-2FA1-11D2-883F-0016D3CCA427",
          "analyte": {
            "key": "total_cholesterol",
            "displayName": "Total cholesterol",
            "canonicalUnit": "mmol/L",
            "groundingKind": "totalCholesterol",
            "isKnown": true
          },
          "value": 3.6,
          "unit": "mmol/L",
          "collectedAt": 744000000,
          "collectedAtIsExact": true,
          "source": "typed",
          "isConfirmedByReader": true
        }
        """.utf8)

        let result = try decoder.decode(LabResult.self, from: legacy)
        XCTAssertEqual(result.value, .quantitative(3.6))
        XCTAssertEqual(result.value.measuredNumber, 3.6)
        XCTAssertEqual(result.unit, "mmol/L")
        XCTAssertEqual(result.analyte.key, "total_cholesterol")
        XCTAssertTrue(result.collectedAtIsExact)
    }

    /// Integers are a legal JSON number too, and a report that printed `139`
    /// round-trips through `JSONEncoder` without a decimal point.
    func testALegacyIntegerNumberStillDecodes() throws {
        let value = try decoder.decode(LabValue.self, from: Data("139".utf8))
        XCTAssertEqual(value, .quantitative(139))
    }

    // MARK: - The new shapes round-trip

    func testEveryShapeRoundTrips() throws {
        let cases: [LabValue] = [
            .quantitative(3.6),
            .censored(.lessThan, 5),
            .censored(.greaterThan, 90),
            .censored(.greaterOrEqual, 1),
            .qualitative(LabQualitativeResult(printed: "Negative")),
            .qualitative(LabQualitativeResult(printed: "Wibble")),
            .notMeasured(.statedByLaboratory("Specimen unsuitable")),
            .notMeasured(.notStated)
        ]
        for value in cases {
            let data = try encoder.encode(value)
            let back = try decoder.decode(LabValue.self, from: data)
            XCTAssertEqual(back, value, "\(value) did not survive a round trip")
        }
    }

    /// A `LabResult` written today must still decode tomorrow. The bare-number
    /// path must not swallow the keyed one.
    func testANewLabResultRoundTrips() throws {
        let result = LabResult(
            analyte: LabAnalyte.unknown(label: "HIV Ag/Ab", unit: nil),
            value: .qualitative(LabQualitativeResult(printed: "Negative")),
            unit: "",
            collectedAt: Date(timeIntervalSince1970: 1_762_000_000),
            collectedAtIsExact: true,
            source: .pdf)
        let back = try decoder.decode(LabResult.self, from: try encoder.encode(result))
        XCTAssertEqual(back.value, result.value)
        XCTAssertEqual(back.analyte.displayName, "HIV Ag/Ab")
    }

    // MARK: - measuredNumber is the honesty gate

    /// ⚠️ The single most important assertion in this file. Only a measured
    /// number may reach a card, a risk model or a grounding fact.
    func testOnlyAQuantitativeValueYieldsAMeasuredNumber() {
        XCTAssertEqual(LabValue.quantitative(3.6).measuredNumber, 3.6)
        XCTAssertNil(LabValue.censored(.greaterThan, 90).measuredNumber,
                     "a censored bound must never be readable as a measurement")
        XCTAssertNil(LabValue.qualitative(LabQualitativeResult(printed: "Negative")).measuredNumber)
        XCTAssertNil(LabValue.notMeasured(.notStated).measuredNumber)
    }

    /// A censored value still has a position on an axis — it just is not a
    /// measurement. Both halves matter: dropping it loses a real data point,
    /// promoting it invents one.
    func testACensoredValueHasAMagnitudeButNotAMeasurement() {
        let value = LabValue.censored(.lessThan, 5)
        XCTAssertEqual(value.magnitude, 5)
        XCTAssertNil(value.measuredNumber)
        XCTAssertTrue(value.isPlottable)
        XCTAssertEqual(value.formatted, "<5.00")
    }

    func testAWordIsNotPlottable() {
        let value = LabValue.qualitative(LabQualitativeResult(printed: "Not Detected"))
        XCTAssertNil(value.magnitude)
        XCTAssertFalse(value.isPlottable)
        XCTAssertFalse(value.shape.isChartable)
    }

    // MARK: - The word vocabularies

    /// ⚠️ The ordering trap: "Not detected" contains "detected". Matching the
    /// positive vocabulary first would file every negative PCR in this reader's
    /// record as a positive one.
    func testNotDetectedIsNegativeAndNotPositive() {
        XCTAssertEqual(LabQualitativeOrdinal(printed: "Not Detected"), .negative)
        XCTAssertEqual(LabQualitativeOrdinal(printed: "DETECTED"), .positive)
    }

    func testTheThreeVocabulariesCollapseOntoOneScale() {
        for word in ["Negative", "Not Detected", "Non reactive", "Non-reactive", "No growth"] {
            XCTAssertEqual(LabQualitativeOrdinal(printed: word), .negative, word)
        }
        for word in ["Positive", "Detected", "Reactive", "Isolated"] {
            XCTAssertEqual(LabQualitativeOrdinal(printed: word), .positive, word)
        }
        for word in ["Equivocal", "Indeterminate", "Borderline"] {
            XCTAssertEqual(LabQualitativeOrdinal(printed: word), .equivocal, word)
        }
    }

    /// An unrecognised word is stored and shown, never guessed at. The same rule
    /// `LabAnalyte` applies to an uncatalogued analyte.
    func testAnUnrecognisedWordHasNoOrdinalAndIsKeptVerbatim() {
        let result = LabQualitativeResult(printed: "Awaiting culture")
        XCTAssertNil(result.ordinal)
        XCTAssertEqual(result.printed, "Awaiting culture")
        XCTAssertEqual(LabValue.qualitative(result).formatted, "Awaiting culture")
    }

    func testAnEmptyWordHasNoOrdinal() {
        XCTAssertNil(LabQualitativeOrdinal(printed: "   "))
    }

    // MARK: - Presentation

    /// A word has no unit. "Negative mmol/L" reads as a measurement that failed
    /// to print rather than as a word.
    func testAUnitIsNeverAppendedToAWord() {
        let result = LabResult(
            analyte: LabAnalyte.unknown(label: "Syphilis (CMIA) Screen", unit: nil),
            value: .qualitative(LabQualitativeResult(printed: "Negative")),
            unit: "mmol/L",
            collectedAt: Date(), source: .pdf)
        XCTAssertEqual(result.formattedWithUnit, "Negative")
    }

    func testAUnitIsAppendedToACensoredBound() {
        let result = LabResult(
            analyte: LabAnalyte.unknown(label: "HepB surface antibody", unit: "IU/L"),
            value: .censored(.lessThan, 5),
            unit: "IU/L",
            collectedAt: Date(), source: .pdf)
        XCTAssertEqual(result.formattedWithUnit, "<5.00 IU/L")
    }

    /// Precision follows the size of the number, as it always has.
    func testPrecisionFollowsMagnitude() {
        XCTAssertEqual(LabValue.quantitative(146).formatted, "146")
        XCTAssertEqual(LabValue.quantitative(15.3).formatted, "15.3")
        XCTAssertEqual(LabValue.quantitative(3.6).formatted, "3.60")
        XCTAssertEqual(LabValue.quantitative(0.92).formatted, "0.920")
    }

    // MARK: - The checks

    /// A serology result carries no reference interval, so every numeric check
    /// returns its can't-check answer. Recognising the word is what corroborates
    /// it — otherwise a perfectly clear Negative would sit at `.unverified`
    /// forever and be shown to the reader as "read, not cross-checked".
    func testARecognisedWordCorroboratesAReading() {
        let evidence = LabExtractionEvidence(
            rawLabel: "Syphilis (CMIA) Screen", rawValueText: "Negative",
            rawLine: "Syphilis (CMIA) Screen  Negative",
            method: .deterministic,
            checks: [.qualitativeWordRecognised("Negative"), .noPrintedRange, .magnitudeUncheckable])
        XCTAssertEqual(evidence.confidence, .clear)
    }

    func testAnUnrecognisedWordLeavesTheReadingUnverified() {
        let evidence = LabExtractionEvidence(
            rawLabel: "Culture", rawValueText: "Awaiting",
            rawLine: "Culture  Awaiting",
            method: .deterministic,
            checks: [.qualitativeWordUnrecognised("Awaiting"), .noPrintedRange])
        XCTAssertEqual(evidence.confidence, .unverified)
    }

    /// The laboratory's own out-of-range marker says something about the reader's
    /// result, not about how well the app read it. It must never make a reading
    /// doubtful — a genuinely low bicarbonate is flagged `L` and correctly read.
    func testAPrintedAbnormalFlagIsNeitherAFailureNorWeak() {
        XCTAssertFalse(LabValueCheck.printedAbnormalFlag("L").isFailure)
        XCTAssertFalse(LabValueCheck.printedAbnormalFlag("L").isWeak)
    }

    /// Every check must answer both questions. The `default:` this switch used to
    /// carry made a new case silently not-weak, which makes a reading look better
    /// cross-checked than it is.
    func testEveryCheckAnswersIsFailureAndIsWeak() {
        let all: [LabValueCheck] = [
            .insidePrintedRange, .outsidePrintedRange(excursion: 1),
            .grosslyOutsidePrintedRange(excursion: 12), .noPrintedRange,
            .plausibleMagnitude, .implausibleMagnitude, .magnitudeUncheckable,
            .unitRecognised("mmol/L"), .unitUnrecognised("wibbles"),
            .unitInferredFromRange("mmol/L"), .unitMissing,
            .selectedByPrintedRange(chosen: 3.6, rejected: [36]),
            .ocrConfidence(0.9), .ambiguousCharacters("S.2"),
            .corroboratedInSourceText, .notFoundInSourceText,
            .qualitativeWordRecognised("Negative"),
            .qualitativeWordUnrecognised("Awaiting"),
            .censoredBound("<5"), .notMeasuredStated("Specimen unsuitable"),
            .printedAbnormalFlag("H")
        ]
        for check in all {
            XCTAssertFalse(check.explanation.isEmpty, "\(check) has no explanation")
            // Nothing may be both a failure and merely weak.
            XCTAssertFalse(check.isFailure && check.isWeak, "\(check) is both")
        }
    }
}
