import XCTest
@testable import InsightKit

/// ⚠️ The most important test in this file is the last one: the parser must be
/// unable to emit a classification the document does not print. Everything else
/// is transcription accuracy.
final class ECGMetadataParserTests: XCTestCase {

    private let applePDF = """
    ECG
    Recorded: 24 July 2026 at 14:05
    Sinus Rhythm
    Average heart rate: 62 BPM
    Duration: 30 seconds
    Apple Watch Series 10
    Lead I
    """

    func testReadsTheRecordedDateAndTime() {
        let result = ECGMetadataParser.parse(applePDF)
        XCTAssertNotNil(result.recordedAt)
    }

    func testReadsThePrintedAverageHeartRate() {
        XCTAssertEqual(ECGMetadataParser.parse(applePDF).averageHeartRate, 62)
    }

    func testReadsTheDuration() {
        XCTAssertEqual(ECGMetadataParser.parse(applePDF).durationSeconds, 30)
    }

    func testReadsTheDevice() {
        XCTAssertEqual(ECGMetadataParser.parse(applePDF).device, "Apple Watch Series 10")
    }

    func testReadsTheLeadConfiguration() {
        XCTAssertEqual(ECGMetadataParser.parse(applePDF).leads, .singleLead)
        XCTAssertEqual(ECGMetadataParser.parse("12-lead ECG\nGE MAC 2000").leads, .twelveLead)
    }

    /// A heart rate that could not have been printed is a misread, not a
    /// tachycardia — the same guard a lab value gets, for the same reason.
    func testAnImpossibleHeartRateIsRejectedRatherThanStored() {
        let result = ECGMetadataParser.parse("Average heart rate: 620 BPM")
        XCTAssertNil(result.averageHeartRate)
        XCTAssertTrue(result.evidence.checks.contains(.implausibleMagnitude))
    }

    /// A field the document did not print is *named* as absent, so a detail page
    /// can say "the document did not state a duration" rather than showing a gap
    /// that reads as a failure.
    func testAbsentFieldsAreNamedRatherThanLeftBlank() {
        let result = ECGMetadataParser.parse("Recorded: 24 July 2026 at 14:05")
        XCTAssertTrue(result.evidence.absentFields.contains(.duration))
        XCTAssertTrue(result.evidence.absentFields.contains(.averageHeartRate))
        XCTAssertFalse(result.evidence.absentFields.contains(.recordedAt))
    }

    // MARK: - The line

    /// The classification is a **quotation**, carried with the attribution that
    /// says whose it is.
    func testThePrintedFindingIsQuotedWithItsProvenance() {
        let result = ECGMetadataParser.parse(applePDF)
        XCTAssertEqual(result.printedFinding, "Sinus Rhythm")
        XCTAssertEqual(result.findingProvenance, .recordingDevice)
    }

    /// ⚠️ **The line, in a test.** A document with a trace and no printed
    /// classification yields no classification. There is no path in this app
    /// from a waveform to a finding, and this is what stops one being added by
    /// accident.
    func testADocumentWithNoPrintedFindingYieldsNoFinding() {
        let clinic = """
        12-lead ECG
        Recorded: 24/07/2026 09:12
        Average heart rate: 71 BPM
        GE MAC 2000
        """
        let result = ECGMetadataParser.parse(clinic)
        XCTAssertNil(result.printedFinding)
        XCTAssertNil(result.findingProvenance)
        XCTAssertTrue(result.evidence.absentFields.contains(.finding))
    }

    /// A legend listing every classification the machine can print is not a
    /// finding about this trace.
    func testALegendListingEveryPossibleResultIsNotReadAsAFinding() {
        let legend = "Key: Sinus Rhythm / Atrial Fibrillation / High Heart Rate / Inconclusive"
        XCTAssertNil(ECGMetadataParser.parse(legend).printedFinding)
    }

    /// The attribution is a property of the record, so a screen that renders the
    /// finding somewhere new cannot drop it.
    func testARecordWithAFindingAlwaysCarriesAnAttribution() {
        let record = ECGRecord(recordedAt: Date(), recordedAtIsExact: true,
                               source: .pdf, leads: .singleLead,
                               printedFinding: "Sinus Rhythm",
                               findingProvenance: .recordingDevice)
        XCTAssertNotNil(record.findingAttribution)
        XCTAssertTrue(record.findingAttribution?.contains("does not interpret") ?? false)
    }

    func testARecordWithNoFindingHasNoAttributionToShow() {
        let record = ECGRecord(recordedAt: Date(), recordedAtIsExact: false,
                               source: .photo, leads: .unstated)
        XCTAssertNil(record.findingAttribution)
    }
}
