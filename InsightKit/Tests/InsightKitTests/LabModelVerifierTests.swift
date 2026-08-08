import XCTest
@testable import InsightKit

/// The on-device model is allowed to *name* and to *pair*. It is never allowed
/// to produce a number. These tests are the enforcement of that sentence — every
/// one of them is a way a language model can be confidently wrong.
final class LabModelVerifierTests: XCTestCase {

    private let page = """
    BIOCHEMISTRY
    Alk. Phos.
    Serum TSH level (XaELV)
    88
    2.4
    """

    private func scan(_ text: String) -> LabReportParser.Scan {
        LabReportParser.parseReport(text, source: .pdf,
                                    importedAt: Date(timeIntervalSince1970: 1_780_000_000))
    }

    // MARK: - The guard

    /// The failure that makes a model dangerous here: a number that is not on
    /// the page. It carries no OCR artefact, looks entirely reasonable, and
    /// would flow into the export as a measurement.
    func testAValueNotInTheSourceTextIsRefused() {
        let proposal = LabModelVerifier.Proposal(
            label: "Alk. Phos.", analyteKey: "alp", valueText: "104",
            unitText: "U/L", sourceLine: nil)
        let verdicts = LabModelVerifier.verify([proposal], against: scan(page), source: .pdf)
        XCTAssertNil(verdicts.first?.accepted)
        XCTAssertTrue(verdicts.first?.checks.contains(.notFoundInSourceText) ?? false)
    }

    /// The same failure wearing the other hat — a real number under a label the
    /// model invented.
    func testALabelNotInTheSourceTextIsRefused() {
        let proposal = LabModelVerifier.Proposal(
            label: "Magnesium", analyteKey: nil, valueText: "88",
            unitText: "U/L", sourceLine: nil)
        let verdicts = LabModelVerifier.verify([proposal], against: scan(page), source: .pdf)
        XCTAssertNil(verdicts.first?.accepted)
    }

    /// Both present somewhere on a page of thirty analytes proves nothing about
    /// their belonging together — which is the pairing job the model was given,
    /// so it is exactly where it can be wrong.
    func testALabelAndValueTooFarApartAreRefused() {
        let sparse = """
        Alk. Phos.
        \(String(repeating: "filler text on this report ", count: 6))
        88 U/L
        """
        let proposal = LabModelVerifier.Proposal(
            label: "Alk. Phos.", analyteKey: "alp", valueText: "88",
            unitText: "U/L", sourceLine: nil)
        let verdicts = LabModelVerifier.verify([proposal], against: scan(sparse), source: .pdf)
        XCTAssertNil(verdicts.first?.accepted)
    }

    func testAQuotedLineThatIsNotOnThePageIsRefused() {
        let proposal = LabModelVerifier.Proposal(
            label: "Alk. Phos.", analyteKey: "alp", valueText: "88",
            unitText: "U/L", sourceLine: "Alk. Phos. 88 U/L (30 - 130)")
        let verdicts = LabModelVerifier.verify([proposal], against: scan(page), source: .pdf)
        XCTAssertNil(verdicts.first?.accepted)
    }

    /// A model that answers in words rather than digits gets nothing: the
    /// arithmetic is this app's, always.
    func testAValueThatIsNotABareNumberIsRefused() {
        let text = "Alk. Phos. eighty-eight U/L"
        let proposal = LabModelVerifier.Proposal(
            label: "Alk. Phos.", analyteKey: "alp", valueText: "eighty-eight",
            unitText: "U/L", sourceLine: nil)
        let verdicts = LabModelVerifier.verify([proposal], against: scan(text), source: .pdf)
        XCTAssertNil(verdicts.first?.accepted)
    }

    /// A catalogue key that does not exist is a sign the whole response is
    /// confabulated, so it is refused rather than downgraded to "unknown".
    func testAnInventedAnalyteKeyIsRefused() {
        let proposal = LabModelVerifier.Proposal(
            label: "Alk. Phos.", analyteKey: "alkaline_phosphatase_serum",
            valueText: "88", unitText: "U/L", sourceLine: nil)
        let verdicts = LabModelVerifier.verify([proposal], against: scan(page), source: .pdf)
        XCTAssertNil(verdicts.first?.accepted)
        XCTAssertNotNil(verdicts.first?.refusal)
    }

    /// The rule-based path is the one under test; the model supplements it and
    /// must never overrule it.
    func testTheModelCannotOverwriteWhatTheParserAlreadyRead() {
        let parsed = scan("Total Cholesterol 5.2 mmol/L (0.0 - 5.0)")
        let proposal = LabModelVerifier.Proposal(
            label: "Total Cholesterol", analyteKey: "total_cholesterol",
            valueText: "5.2", unitText: "mmol/L", sourceLine: nil)
        let verdicts = LabModelVerifier.verify([proposal], against: parsed, source: .pdf)
        XCTAssertNil(verdicts.first?.accepted)
    }

    // MARK: - What it is for

    /// Job one: mapping a label the catalogue's synonyms do not carry onto a
    /// known analyte, so the value joins the reader's existing trend instead of
    /// starting a second one under a name they will never search for.
    ///
    /// The deterministic parser reads this line perfectly well — it just cannot
    /// *name* it, so it files it under the laboratory's own words. That is the
    /// gap the model closes.
    private let oddLabel = "Phosphatase, alkaline (bone isoform)  88 U/L"

    func testTheParserAloneCannotNameAnOddlyLabelledAnalyte() {
        let parsed = scan(oddLabel)
        XCTAssertEqual(parsed.results.count, 1)
        XCTAssertFalse(parsed.results[0].analyte.isKnown)
    }

    func testAMappedLabelJoinsTheKnownAnalyte() {
        let proposal = LabModelVerifier.Proposal(
            label: "Phosphatase, alkaline (bone isoform)", analyteKey: "alp",
            valueText: "88", unitText: "U/L", sourceLine: oddLabel)
        let verdicts = LabModelVerifier.verify([proposal], against: scan(oddLabel), source: .pdf)
        let accepted = verdicts.first?.accepted
        XCTAssertEqual(accepted?.analyte.key, "alp")
        XCTAssertEqual(accepted?.value.measuredNumber, 88)
        XCTAssertEqual(accepted?.unit, "U/L")
        XCTAssertEqual(accepted?.evidence?.method, .onDeviceModel)
    }

    /// ...and the renamed value **replaces** the unnamed one rather than sitting
    /// beside it. Two rows for one measurement is how a trend gets to disagree
    /// with itself.
    func testAReconciledRenameReplacesTheUnnamedResult() {
        let proposal = LabModelVerifier.Proposal(
            label: "Phosphatase, alkaline (bone isoform)", analyteKey: "alp",
            valueText: "88", unitText: "U/L", sourceLine: oddLabel)
        let reconciled = LabModelVerifier.reconcile([proposal], with: scan(oddLabel),
                                                    source: .pdf)
        XCTAssertEqual(reconciled.results.count, 1)
        XCTAssertEqual(reconciled.results.first?.analyte.key, "alp")
        XCTAssertNotNil(reconciled.verdicts.first?.supersedes)
    }

    /// A recognised analyte is never replaced by a model, under any
    /// circumstance: the rule-based path is the one under test.
    func testAKnownResultIsNeverSupersededByAModel() {
        let parsed = scan("Total Cholesterol 5.2 mmol/L (0.0 - 5.0)")
        let proposal = LabModelVerifier.Proposal(
            label: "Total Cholesterol", analyteKey: "hdl_cholesterol",
            valueText: "5.2", unitText: "mmol/L",
            sourceLine: "Total Cholesterol 5.2 mmol/L (0.0 - 5.0)")
        let reconciled = LabModelVerifier.reconcile([proposal], with: parsed, source: .pdf)
        XCTAssertEqual(reconciled.results.filter { $0.analyte.key == "total_cholesterol" }.count, 1)
        XCTAssertNil(reconciled.verdicts.first?.supersedes)
    }

    /// Job two: pairing across a column-major OCR, where the parser sees words
    /// with no numbers and numbers with no words.
    func testPairingAcrossAColumnMajorLayout() {
        let proposal = LabModelVerifier.Proposal(
            label: "Serum TSH level (XaELV)", analyteKey: "tsh",
            valueText: "2.4", unitText: "mIU/L", sourceLine: nil)
        let verdicts = LabModelVerifier.verify([proposal], against: scan(page), source: .pdf)
        XCTAssertEqual(verdicts.first?.accepted?.analyte.key, "tsh")
        XCTAssertEqual(verdicts.first?.accepted?.value.measuredNumber, 2.4)
    }

    /// A model-named value is never marked as clearly read: the report printed
    /// no interval next to it, which is why the parser could not pair it.
    func testAModelNamedValueIsNeverPresentedAsTyped() {
        let proposal = LabModelVerifier.Proposal(
            label: "Phosphatase, alkaline (bone isoform)", analyteKey: "alp",
            valueText: "88", unitText: "U/L", sourceLine: oddLabel)
        let verdicts = LabModelVerifier.verify([proposal], against: scan(oddLabel), source: .pdf)
        XCTAssertNotEqual(verdicts.first?.accepted?.confidence, .typed)
        XCTAssertNotNil(verdicts.first?.accepted?.evidence)
        XCTAssertEqual(verdicts.first?.accepted?.evidence?.method, .onDeviceModel)
    }

    /// An implausible magnitude is caught on the model path exactly as it is on
    /// the deterministic one — the check does not care who proposed the number.
    func testAnImplausibleModelValueIsMarkedDoubtful() {
        let text = "Phosphatase, alkaline (bone isoform)  88000 U/L"
        let proposal = LabModelVerifier.Proposal(
            label: "Phosphatase, alkaline (bone isoform)", analyteKey: "alp",
            valueText: "88000", unitText: "U/L", sourceLine: text)
        let verdicts = LabModelVerifier.verify([proposal], against: scan(text), source: .pdf)
        XCTAssertEqual(verdicts.first?.accepted?.confidence, .doubtful)
    }

    // MARK: - Reading the model's answer

    func testParsesTheLineFormat() {
        let response = """
        Alk. Phos. | alp | 88 | U/L | Alk. Phos. 88 U/L
        Odd Assay |  | 1.2 | ratio | Odd Assay 1.2 ratio
        """
        let proposals = LabModelVerifier.proposals(fromModelResponse: response)
        XCTAssertEqual(proposals.count, 2)
        XCTAssertEqual(proposals[0].analyteKey, "alp")
        XCTAssertNil(proposals[1].analyteKey)
        XCTAssertEqual(proposals[1].valueText, "1.2")
    }

    /// A model that answers in prose produces lines with no pipes. They are
    /// dropped rather than half-parsed — a partial row is a wrong row.
    func testProseAroundTheAnswerIsDropped() {
        let response = """
        Here are the values I found in the report:
        Alk. Phos. | alp | 88 | U/L | Alk. Phos. 88 U/L
        I hope this helps.
        """
        XCTAssertEqual(LabModelVerifier.proposals(fromModelResponse: response).count, 1)
    }

    func testARowWithNoValueIsDropped() {
        XCTAssertTrue(LabModelVerifier.proposals(fromModelResponse: "Alk. Phos. | alp | ").isEmpty)
    }

    /// The prompt's list of mappable keys is generated from the catalogue, so a
    /// new analyte becomes mappable the moment it is added — one list, not two.
    func testMappableKeysComeFromTheCatalogue() {
        XCTAssertTrue(LabModelVerifier.mappableKeys.contains("hba1c"))
        XCTAssertTrue(LabModelVerifier.mappableKeys.contains("total_cholesterol"))
        XCTAssertEqual(LabModelVerifier.mappableKeys.split(separator: "\n").count,
                       LabAnalyteCatalog.entries.count)
    }
}
