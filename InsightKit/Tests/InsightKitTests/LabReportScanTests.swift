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
        XCTAssertEqual(result(s, "total_cholesterol")?.value.measuredNumber, 5.2)
        XCTAssertEqual(result(s, "hdl_cholesterol")?.value.measuredNumber, 1.4)
        XCTAssertEqual(result(s, "ldl_cholesterol")?.value.measuredNumber, 3.1)
        XCTAssertEqual(result(s, "triglycerides")?.value.measuredNumber, 1.6)
    }

    /// The single most damaging failure this parser can have: "HDL cholesterol"
    /// read as total cholesterol feeds the wrong number into SCORE2 and ASCVD.
    func testHDLIsNeverReadAsTotalCholesterol() {
        let s = scan("HDL Cholesterol  1.4 mmol/L  (1.0 - 2.5)")
        XCTAssertEqual(result(s, "hdl_cholesterol")?.value.measuredNumber, 1.4)
        XCTAssertNil(result(s, "total_cholesterol"))
    }

    func testReadsHbA1cInMmolPerMol() {
        let s = scan("HbA1c   38 mmol/mol   (20 - 41)")
        XCTAssertEqual(result(s, "hba1c")?.value.measuredNumber, 38)
        XCTAssertEqual(result(s, "hba1c")?.unit, "mmol/mol")
    }

    /// HbA1c's two units are affine, not proportional. A multiplier would be
    /// wrong at every value; 5.6% is 38 mmol/mol, not 5.6 x anything.
    func testHbA1cPercentConvertsAffinelyNotProportionally() {
        let s = scan("Haemoglobin A1c   5.6 %   (4.0 - 6.0)")
        let value = try? XCTUnwrap(result(s, "hba1c")?.value.measuredNumber)
        XCTAssertNotNil(value)
        XCTAssertEqual(value ?? 0, 37.7, accuracy: 0.2)
    }

    // MARK: - Unit conversion

    func testConvertsCholesterolFromMgPerDl() {
        let s = scan("Total Cholesterol   201 mg/dL   (0 - 200)")
        let value = try? XCTUnwrap(result(s, "total_cholesterol")?.value.measuredNumber)
        XCTAssertEqual(value ?? 0, 5.2, accuracy: 0.05)
        XCTAssertEqual(result(s, "total_cholesterol")?.unit, "mmol/L")
    }

    /// Triglycerides use a different molecular weight from cholesterol. Reusing
    /// the cholesterol factor is a silent 2.3x error that looks perfectly
    /// plausible on screen.
    func testTriglyceridesUseTheirOwnConversionFactor() {
        let s = scan("Triglycerides   150 mg/dL   (0 - 150)")
        let value = try? XCTUnwrap(result(s, "triglycerides")?.value.measuredNumber)
        XCTAssertEqual(value ?? 0, 1.69, accuracy: 0.02)
    }

    /// A unit the app does not know must never be converted on a guess — the
    /// resulting number looks entirely reasonable and nothing afterwards can
    /// tell it went wrong.
    func testAnUnrecognisedUnitIsStoredVerbatimAndFlagged() {
        let s = scan("Total Cholesterol   5.2 zonks   (0.0 - 5.0)")
        let r = result(s, "total_cholesterol")
        XCTAssertEqual(r?.value.measuredNumber, 5.2)
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
        XCTAssertEqual(r?.value.measuredNumber, 5.2)
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
        let value = r?.value.measuredNumber ?? 0
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
        XCTAssertEqual(r?.value.measuredNumber, 6.4)
        XCTAssertEqual(r?.unit, "mmol/L")
    }

    // MARK: - Arbitrary analytes (I6's deterministic half)

    /// The change that makes `I6` worth having: a report's other twenty-eight
    /// rows are no longer thrown away.
    func testAnUncataloguedAnalyteIsKeptUnderTheLaboratorysOwnLabel() {
        let s = scan("Anti-Mullerian Hormone   14.2 pmol/L   (10.0 - 30.0)")
        let r = s.results.first { !$0.analyte.isKnown }
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.value.measuredNumber, 14.2)
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

    // MARK: - Words, not numbers (the Australian serology corpus)
    //
    // ⚠️ Every fixture below is structurally faithful to a real report and
    // carries **substituted** values — `docs/privacy-and-ip.md`, "the shape of a
    // finding, never the reading".

    func testASerologyWordIsKeptExactlyAsTheLaboratoryPrintedIt() {
        let text = """
        HIV Ag/Ab  Negative
        Syphilis (CMIA) Screen  Negative
        Chlamydia trachomatis NAT  Negative
        """
        let s = scan(text)
        XCTAssertEqual(result(s, "hiv_ag_ab")?.value,
                       .qualitative(LabQualitativeResult(printed: "Negative")))
        XCTAssertEqual(result(s, "syphilis_treponemal")?.value.formatted, "Negative")
        XCTAssertEqual(result(s, "chlamydia_trachomatis_nat")?.analyte.panel, .infection)
        // A word is corroborated by being recognised, not by falling in an
        // interval — a report prints no reference range beside "Negative".
        XCTAssertEqual(result(s, "hiv_ag_ab")?.confidence, .clear)
    }

    /// ⚠️ **The misread this ordering exists to stop.** `HSV 1 DNA (NAA)` carries
    /// a `1` that is not inside a word, so the numeric path scored it as the
    /// result and filed a herpes PCR as *HSV 1 = 1*.
    func testANucleicAcidTestReadsNotDetectedRatherThanAResultOfOne() {
        let s = scan("HSV 1 DNA (NAA)  Not Detected")
        XCTAssertEqual(result(s, "hsv1_dna")?.value,
                       .qualitative(LabQualitativeResult(printed: "Not Detected")))
        XCTAssertNil(result(s, "hsv1_dna")?.value.measuredNumber)
        XCTAssertTrue(s.results.allSatisfy { $0.value.measuredNumber == nil })
    }

    /// "Not detected" contains "detected". Taking the shorter match would file
    /// every negative PCR in this reader's record as a positive one.
    func testTheLongerNegativePhraseWinsOverTheShorterPositiveOneInsideIt() {
        let s = scan("HSV 1 DNA (NAA)  Not Detected")
        let printed = result(s, "hsv1_dna")?.evidence?.rawValueText
        XCTAssertEqual(printed, "Not Detected")
        XCTAssertTrue(result(s, "hsv1_dna")?.evidence?.checks
            .contains(.qualitativeWordRecognised("Not Detected")) ?? false)
    }

    /// Shouted, and with no space before the method. Both are how this
    /// laboratory prints a positive.
    func testAShoutedDetectedIsKeptVerbatimAndPlacedAsPositive() {
        let s = scan("Adenovirus DNA(NAA) DETECTED")
        XCTAssertEqual(result(s, "adenovirus_dna")?.value.formatted, "DETECTED")
        XCTAssertEqual(LabQualitativeResult(printed: "DETECTED").ordinal, .positive)
    }

    /// An analyte the catalogue has never met still gets its word read, under the
    /// laboratory's own label — the qualitative half of `I6`.
    func testAnUncataloguedSerologyLabelStillYieldsItsWord() {
        let text = """
        HIV 1 / 2 total antibody  Non reactive
        Faecal H. pylori Ag (ChLIA)  Negative
        """
        let s = scan(text)
        let antibody = s.results.first { $0.analyte.displayName.contains("total antibody") }
        XCTAssertEqual(antibody?.value,
                       .qualitative(LabQualitativeResult(printed: "Non reactive")))
        XCTAssertEqual(antibody?.analyte.isKnown, false)
        let pylori = s.results.first { $0.analyte.displayName.contains("pylori") }
        XCTAssertEqual(pylori?.value.formatted, "Negative")
    }

    /// A word the app cannot place is stored and shown, never guessed at — the
    /// qualitative twin of `unitUnrecognised`.
    func testAWordTheOrdinalScaleCannotPlaceIsStoredAndFlagged() {
        let s = scan("Urine microscopy   Trace")
        let r = s.results.first
        XCTAssertEqual(r?.value.formatted, "Trace")
        XCTAssertTrue(r?.evidence?.checks
            .contains(.qualitativeWordUnrecognised("Trace")) ?? false)
        XCTAssertEqual(r?.confidence, .unverified)
    }

    /// ⚠️ A report's interpretive comments end in the same vocabulary its results
    /// do. Without the last-thing-on-the-line rule and the prose-word guard, this
    /// sentence becomes an analyte.
    func testAnInterpretiveCommentEndingInAResultWordIsNotAnAnalyte() {
        let line = "Note: A negative result does not exclude recent infection."
        let s = scan(line)
        XCTAssertTrue(s.results.isEmpty)
        XCTAssertTrue(s.unpairedLines.contains(line))
    }

    /// ...and the counterpart: a measurement is not thrown away because a word
    /// followed it. Reading this as "Normal" loses the glucose entirely.
    func testAMeasurementIsNotOverriddenByATrailingWord() {
        let s = scan("Glucose   5.4 mmol/L   3.0 - 5.5   Normal")
        XCTAssertEqual(result(s, "glucose")?.value.measuredNumber, 5.4)
        XCTAssertEqual(result(s, "glucose")?.unit, "mmol/L")
    }

    // MARK: - Bounds, not measurements

    /// ⚠️ The failure `LabValue` exists to make unrepresentable. `<5` stored as 5
    /// turns the assay's floor into a reading and nothing afterwards can tell.
    func testACensoredBoundNeverBecomesAMeasurement() {
        let s = scan("HepB surface antibody  <5  IU/L")
        let r = s.results.first
        XCTAssertEqual(r?.value, .censored(.lessThan, 5))
        XCTAssertNil(r?.value.measuredNumber)
        XCTAssertEqual(r?.value.magnitude, 5)
        XCTAssertTrue(r?.evidence?.checks.contains(.censoredBound("<5")) ?? false)
    }

    /// Two bounds on one line: the last is the interval, the first is the result.
    /// Getting this backwards stores an assay ceiling as a measured 90 and walks
    /// it into a renal trend.
    func testAnEgfrCeilingIsAnUpperBoundAndNotAMeasuredNinety() {
        let s = scan("eGFR  >90  >59")
        let r = result(s, "egfr")
        XCTAssertEqual(r?.value, .censored(.greaterThan, 90))
        XCTAssertNil(r?.value.measuredNumber)
        XCTAssertEqual(r?.referenceRange?.printed, ">59")
        XCTAssertNotEqual(r?.confidence, .doubtful)
    }

    /// ⚠️ A bound on an analyte the catalogue expects as a *word* is exempt from
    /// the magnitude guard, because `measuredNumber` is already nil for it and
    /// there is nothing left for the guard to protect. Without the exemption a
    /// cleanly-read line comes back "check this one".
    func testABoundOnAWordAnalyteIsNotFlaggedAsAnImpossibleMagnitude() {
        let s = scan("Hepatitis B surface antibody  <5  IU/L")
        let r = result(s, "hep_b_surface_antibody")
        XCTAssertEqual(r?.value, .censored(.lessThan, 5))
        XCTAssertNotEqual(r?.confidence, .doubtful)
        XCTAssertTrue(r?.evidence?.checks.contains(.magnitudeUncheckable) ?? false)
    }

    /// A censored bound must never reach a risk model, whatever else is right
    /// about the reading.
    func testACensoredGroundingValueIsNeverExtracted() {
        let extracted = LabReportParser.extract(from: "Total Cholesterol  <2.0 mmol/L  (0.0 - 5.0)")
        XCTAssertTrue(extracted.isEmpty)
    }

    // MARK: - The laboratory produced no value

    /// **Not the same as absent.** The reader was told a test failed, and that is
    /// a fact about their record worth keeping — in the laboratory's own words.
    func testAnUnsuitableSpecimenIsStoredAsNotMeasuredWithTheStatedReason() {
        let text = """
        Iron  N/A  SpecimenUnsuitable
        Saturation  N/A  SpecimenUnsuitable
        """
        let s = scan(text)
        XCTAssertEqual(s.results.count, 2)
        XCTAssertEqual(s.results.first?.value,
                       .notMeasured(.statedByLaboratory("SpecimenUnsuitable")))
        XCTAssertNil(s.results.first?.value.measuredNumber)
        XCTAssertEqual(s.results.first?.unit, "")
        XCTAssertTrue(s.results.first?.evidence?.checks
            .contains(.notMeasuredStated("SpecimenUnsuitable")) ?? false)
    }

    /// The platelet row is simply absent from the count and the reason is printed
    /// underneath it as a sentence. Dropping the sentence loses the only thing
    /// the reader needs to know about their platelets that day.
    func testACommentThatACountCouldNotBeProvidedBecomesANotMeasuredResult() {
        let comment = "An accurate platelet count could not be provided due to platelet clumping"
        let text = """
        Haemoglobin   145   130 - 175   g/L
        \(comment)
        """
        let s = scan(text)
        XCTAssertEqual(result(s, "platelets")?.value,
                       .notMeasured(.statedByLaboratory(comment)))
        XCTAssertEqual(result(s, "haemoglobin")?.value.measuredNumber, 145)
    }

    // MARK: - The laboratory's own abnormal flag

    /// ⚠️ `L` between the value and the interval is the laboratory saying "low",
    /// not litres. Reading it as a unit stamps the bicarbonate `unitUnrecognised`
    /// and loses the mmol/L printed on the far side of its own interval.
    func testAPrintedLowFlagIsRecordedAndIsNotReadAsLitres() {
        let s = scan("Bicarbonate 19 L 20 - 32 mmol/L")
        let r = result(s, "bicarbonate")
        XCTAssertEqual(r?.value.measuredNumber, 19)
        XCTAssertEqual(r?.unit, "mmol/L")
        XCTAssertTrue(r?.evidence?.checks.contains(.printedAbnormalFlag("L")) ?? false)
        // Recorded, never interpreted: the flag says nothing about the reading.
        XCTAssertNotEqual(r?.confidence, .doubtful)
    }

    func testAPrintedHighFlagBeforeAOneSidedIntervalIsRecorded() {
        let s = scan("Haemolysis Index 146 H <40")
        let r = result(s, "haemolysis_index")
        XCTAssertEqual(r?.value.measuredNumber, 146)
        XCTAssertTrue(r?.evidence?.checks.contains(.printedAbnormalFlag("H")) ?? false)
        XCTAssertEqual(r?.referenceRange?.printed, "<40")
    }

    /// ...and the other direction of the same ambiguity: a lone `L` with nothing
    /// after it is the unit litres, because a flag never ends the line.
    func testATrailingLitresIsAUnitAndNotAFlag() {
        let s = scan("Urine volume  1.2 L")
        let r = s.results.first
        XCTAssertEqual(r?.unit, "L")
        XCTAssertFalse(r?.evidence?.checks.contains(.printedAbnormalFlag("L")) ?? true)
    }

    // MARK: - The specimen

    /// ⚠️ `isNoiseLine` throws this row away, rightly — but until it was read
    /// first, that also threw away the only statement on the page of *what was
    /// tested*. A potassium from serum and one from plasma are different numbers.
    func testTheSpecimenTypeIsReadBeforeItsLineIsDiscarded() {
        let text = """
        Specimen Type: Serum
        Sodium   139   135 - 145 mmol/L
        """
        let s = scan(text)
        XCTAssertEqual(s.specimen, "Serum")
        XCTAssertEqual(s.results.count, 1)
        XCTAssertFalse(s.unpairedLines.contains { $0.lowercased().contains("specimen") })
    }

    func testNoSpecimenIsNeverGuessedAtAsBlood() {
        XCTAssertNil(scan("Sodium   139   135 - 145 mmol/L").specimen)
    }

    // MARK: - Reference intervals, all four printed shapes

    func testTheFourReferenceIntervalShapesAreAllRead() {
        let text = """
        Triglycerides   1.2 mmol/L   <5.6
        TSH             2.4 mIU/L    >0.89
        Calcium         2.35 mmol/L  2.10 - 2.60
        Vitamin D       92 nmol/L    <64
        Ferritin        120 ug/L     0 - 80
        """
        let s = scan(text)
        XCTAssertEqual(result(s, "triglycerides")?.referenceRange?.printed, "<5.6")
        XCTAssertEqual(result(s, "triglycerides")?.referenceRange?.low, nil)
        XCTAssertEqual(result(s, "triglycerides")?.referenceRange?.high, 5.6)
        XCTAssertEqual(result(s, "tsh")?.referenceRange?.printed, ">0.89")
        XCTAssertEqual(result(s, "tsh")?.referenceRange?.low, 0.89)
        XCTAssertEqual(result(s, "tsh")?.referenceRange?.high, nil)
        // Calcium is not in the catalogue, so it arrives under the laboratory's
        // own label — which is exactly where a two-sided interval most needs to
        // survive: nothing else on an uncatalogued row can size the number.
        let calcium = s.results.first { $0.analyte.displayName == "Calcium" }
        XCTAssertEqual(calcium?.referenceRange?.printed, "2.10 - 2.60")
        XCTAssertEqual(calcium?.referenceRange?.low, 2.10)
        XCTAssertEqual(calcium?.referenceRange?.high, 2.60)
        XCTAssertEqual(calcium?.value.measuredNumber, 2.35)
        XCTAssertEqual(result(s, "vitamin_d")?.referenceRange?.printed, "<64")
        XCTAssertEqual(result(s, "ferritin")?.referenceRange?.printed, "0 - 80")
        XCTAssertEqual(result(s, "ferritin")?.referenceRange?.low, 0)
        XCTAssertEqual(result(s, "ferritin")?.referenceRange?.high, 80)
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
