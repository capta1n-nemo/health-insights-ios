import XCTest
@testable import InsightKit

/// The parser's job is to be right about numbers that end up in a risk model and
/// in an export. Every test here is either a layout a real pathology report uses
/// or a misread that would be invisible without a cross-check.
final class LabReportScanTests: XCTestCase {

    private func scan(_ text: String) -> LabReportParser.Scan {
        LabReportParser.parseReport(text, source: .pdf,
                                    importedAt: Date(timeIntervalSince1970: 1_780_000_000))
    }

    private func result(_ scan: LabReportParser.Scan, _ key: String) -> LabResult? {
        scan.results.first { $0.analyte.key == key }
    }

    // MARK: - The floor the reader named: lipids and HbA1c

    func testReadsAStandardLipidPanel() {
        let text = """
        LIPID PROFILE
        Total Cholesterol      5.2 mmol/L      (0.0 - 5.0)
        HDL Cholesterol        1.4 mmol/L      (1.0 - 2.5)
        LDL Cholesterol        3.1 mmol/L      (0.0 - 3.0)
        Triglycerides          1.6 mmol/L      (0.0 - 1.7)
        """
        let s = scan(text)
        XCTAssertEqual(result(s, "total_cholesterol")?.value, 5.2)
        XCTAssertEqual(result(s, "hdl_cholesterol")?.value, 1.4)
        XCTAssertEqual(result(s, "ldl_cholesterol")?.value, 3.1)
        XCTAssertEqual(result(s, "triglycerides")?.value, 1.6)
    }

    /// The single most damaging failure this parser can have: "HDL cholesterol"
    /// read as total cholesterol feeds the wrong number into SCORE2 and ASCVD.
    func testHDLIsNeverReadAsTotalCholesterol() {
        let s = scan("HDL Cholesterol  1.4 mmol/L  (1.0 - 2.5)")
        XCTAssertEqual(result(s, "hdl_cholesterol")?.value, 1.4)
        XCTAssertNil(result(s, "total_cholesterol"))
    }

    func testReadsHbA1cInMmolPerMol() {
        let s = scan("HbA1c   38 mmol/mol   (20 - 41)")
        XCTAssertEqual(result(s, "hba1c")?.value, 38)
        XCTAssertEqual(result(s, "hba1c")?.unit, "mmol/mol")
    }

    /// HbA1c's two units are affine, not proportional. A multiplier would be
    /// wrong at every value; 5.6% is 38 mmol/mol, not 5.6 x anything.
    func testHbA1cPercentConvertsAffinelyNotProportionally() {
        let s = scan("Haemoglobin A1c   5.6 %   (4.0 - 6.0)")
        let value = try? XCTUnwrap(result(s, "hba1c")?.value)
        XCTAssertNotNil(value)
        XCTAssertEqual(value ?? 0, 37.7, accuracy: 0.2)
    }

    // MARK: - Unit conversion

    func testConvertsCholesterolFromMgPerDl() {
        let s = scan("Total Cholesterol   201 mg/dL   (0 - 200)")
        let value = try? XCTUnwrap(result(s, "total_cholesterol")?.value)
        XCTAssertEqual(value ?? 0, 5.2, accuracy: 0.05)
        XCTAssertEqual(result(s, "total_cholesterol")?.unit, "mmol/L")
    }

    /// Triglycerides use a different molecular weight from cholesterol. Reusing
    /// the cholesterol factor is a silent 2.3x error that looks perfectly
    /// plausible on screen.
    func testTriglyceridesUseTheirOwnConversionFactor() {
        let s = scan("Triglycerides   150 mg/dL   (0 - 150)")
        let value = try? XCTUnwrap(result(s, "triglycerides")?.value)
        XCTAssertEqual(value ?? 0, 1.69, accuracy: 0.02)
    }

    /// A unit the app does not know must never be converted on a guess — the
    /// resulting number looks entirely reasonable and nothing afterwards can
    /// tell it went wrong.
    func testAnUnrecognisedUnitIsStoredVerbatimAndFlagged() {
        let s = scan("Total Cholesterol   5.2 zonks   (0.0 - 5.0)")
        let r = result(s, "total_cholesterol")
        XCTAssertEqual(r?.value, 5.2)
        XCTAssertEqual(r?.unit, "zonks")
        XCTAssertEqual(r?.confidence, .doubtful)
        XCTAssertTrue(r?.evidence?.checks.contains(.unitUnrecognised("zonks")) ?? false)
    }

    // MARK: - The misread guard

    /// The whole point of the printed reference interval: a decimal point in the
    /// wrong place produces a number ten interval-widths out, which is where
    /// physiology does not live.
    func testADecimalPointMisreadIsCaught() {
        let s = scan("Total Cholesterol   52 mmol/L   (0.0 - 5.0)")
        let r = result(s, "total_cholesterol")
        XCTAssertEqual(r?.confidence, .doubtful)
        XCTAssertTrue(r?.evidence?.checks.contains {
            if case .grosslyOutsidePrintedRange = $0 { return true }
            return false
        } ?? false)
    }

    /// ...and the counterpart, which matters just as much: a genuinely raised
    /// value is outside its interval and is NOT a misread. Flagging it would be
    /// the app second-guessing a laboratory, which is the line it does not cross.
    func testAGenuinelyRaisedValueIsNotFlaggedAsAMisread() {
        let s = scan("Total Cholesterol   6.4 mmol/L   (0.0 - 5.0)")
        let r = result(s, "total_cholesterol")
        XCTAssertNotEqual(r?.confidence, .doubtful)
        XCTAssertTrue(r?.evidence?.checks.contains {
            if case .outsidePrintedRange = $0 { return true }
            return false
        } ?? false)
    }

    /// A magnitude no laboratory prints is a misread outright, with or without a
    /// reference interval.
    func testAnImpossibleMagnitudeIsRejectedEvenWithNoPrintedRange() {
        let s = scan("Total Cholesterol   402 mmol/L")
        XCTAssertEqual(result(s, "total_cholesterol")?.confidence, .doubtful)
    }

    /// The screen-time parser's extension, applied here: where a line holds
    /// several numbers, the printed interval **selects** rather than merely
    /// vetoes.
    func testThePrintedRangeSelectsBetweenSeveralNumbersOnALine() {
        // The leading "2" is a specimen/sequence column, which real reports do
        // print. Naively taking the first number gives 2 mmol/L.
        let s = scan("2   Total Cholesterol   5.2 mmol/L   (4.0 - 6.0)")
        let r = result(s, "total_cholesterol")
        XCTAssertEqual(r?.value, 5.2)
        XCTAssertTrue(r?.evidence?.checks.contains {
            if case .selectedByPrintedRange(let chosen, _) = $0 { return chosen == 5.2 }
            return false
        } ?? false)
    }

    /// Select-don't-reject applied to units: an unlabelled 194 beside a 0-200
    /// interval can only be mg/dL, and the inference is recorded as one.
    func testAMissingUnitIsInferredFromThePrintedRange() {
        let s = scan("Total Cholesterol   194   (0 - 200)")
        let r = result(s, "total_cholesterol")
        let value = r?.value ?? 0
        XCTAssertEqual(value, 5.02, accuracy: 0.05)
        XCTAssertTrue(r?.evidence?.checks.contains {
            if case .unitInferredFromRange = $0 { return true }
            return false
        } ?? false)
    }

    /// A comma with three digits after it reads two ways depending on the
    /// country, and a lab value is not the place to silently pick one.
    func testAnAmbiguousThousandsCommaIsFlagged() {
        let s = scan("Ferritin   1,234 ug/L   (30 - 400)")
        let r = s.results.first { $0.analyte.key == "ferritin" }
        XCTAssertEqual(r?.confidence, .doubtful)
        XCTAssertTrue(r?.evidence?.checks.contains {
            if case .ambiguousCharacters = $0 { return true }
            return false
        } ?? false)
    }

    /// An abnormal-flag letter between the value and the unit is common on
    /// printouts, and reading "H" as the unit would fail every conversion.
    func testAnAbnormalFlagBetweenValueAndUnitIsSkipped() {
        let s = scan("Total Cholesterol   6.4 H mmol/L   (0.0 - 5.0)")
        let r = result(s, "total_cholesterol")
        XCTAssertEqual(r?.value, 6.4)
        XCTAssertEqual(r?.unit, "mmol/L")
    }

    // MARK: - Arbitrary analytes (I6's deterministic half)

    /// The change that makes `I6` worth having: a report's other twenty-eight
    /// rows are no longer thrown away.
    func testAnUncataloguedAnalyteIsKeptUnderTheLaboratorysOwnLabel() {
        let s = scan("Anti-Mullerian Hormone   14.2 pmol/L   (10.0 - 30.0)")
        let r = s.results.first { !$0.analyte.isKnown }
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.value, 14.2)
        XCTAssertEqual(r?.unit, "pmol/L")
        XCTAssertEqual(r?.analyte.displayName, "Anti-Mullerian Hormone")
        XCTAssertEqual(r?.analyte.panel, .other)
    }

    /// ...and it says out loud that it could not check the size of it.
    func testAnUncataloguedAnalyteDeclaresItsMagnitudeUncheckable() {
        let s = scan("Anti-Mullerian Hormone   14.2 pmol/L   (10.0 - 30.0)")
        let r = s.results.first { !$0.analyte.isKnown }
        XCTAssertTrue(r?.evidence?.checks.contains(.magnitudeUncheckable) ?? false)
    }

    func testColumnHeadersAreNotReadAsResults() {
        let text = """
        Test                 Result   Units     Reference Range
        Total Cholesterol      5.2    mmol/L    (0.0 - 5.0)
        """
        let s = scan(text)
        XCTAssertEqual(s.results.count, 1)
        XCTAssertEqual(s.results.first?.analyte.key, "total_cholesterol")
    }

    func testLinesWithNoValueAreOfferedToTheModelRatherThanDropped() {
        let text = """
        Total Cholesterol
        HDL Cholesterol
        5.2
        1.4
        """
        let s = scan(text)
        XCTAssertTrue(s.unpairedLines.contains("Total Cholesterol"))
        XCTAssertTrue(s.unpairedLines.contains("HDL Cholesterol"))
    }

    // MARK: - Dates

    /// Collection, not report date: a value filed under the authorisation date
    /// sits in the wrong week against every vital it is compared with.
    func testUsesThePrintedCollectionDate() {
        let text = """
        Collected: 14/03/2026
        Total Cholesterol   5.2 mmol/L   (0.0 - 5.0)
        """
        let s = scan(text)
        XCTAssertNotNil(s.collectedAt)
        XCTAssertTrue(s.results.allSatisfy(\.collectedAtIsExact))
    }

    func testFallsBackToTheImportDateAndSaysSo() {
        let s = scan("Total Cholesterol   5.2 mmol/L   (0.0 - 5.0)")
        XCTAssertNil(s.collectedAt)
        XCTAssertFalse(s.results.first?.collectedAtIsExact ?? true)
    }

    // MARK: - The grounding path

    func testGroundingExtractionStillReturnsLipidsOnly() {
        let text = """
        Total Cholesterol   5.2 mmol/L   (0.0 - 5.0)
        HDL Cholesterol     1.4 mmol/L   (1.0 - 2.5)
        Ferritin            120 ug/L     (30 - 400)
        """
        let extracted = LabReportParser.extract(from: text)
        XCTAssertEqual(Set(extracted.map(\.kind)), [.totalCholesterol, .hdlCholesterol])
    }

    /// A grounding fact is consumed by a risk model that will not ask, so the
    /// bar to become one is higher than the bar to be shown on screen.
    func testADoubtfulReadingNeverBecomesAGroundingFact() {
        let extracted = LabReportParser.extract(from: "Total Cholesterol   52 mmol/L   (0.0 - 5.0)")
        XCTAssertTrue(extracted.isEmpty)
    }
}
