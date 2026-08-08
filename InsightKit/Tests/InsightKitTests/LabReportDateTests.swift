import XCTest
@testable import InsightKit

/// **When was the blood taken?** — the single question a pathology report is
/// worst at answering, and the one this app most needs right.
///
/// A lab result filed under the wrong date is compared against the wrong week of
/// weight, sleep and heart rate, and nothing downstream can tell. Three
/// laboratories in this reader's corpus print between two and five dates on one
/// page, and in two of the three the most prominent one is **wrong**:
///
/// - Sullivan Nicolaides prints five (`Requested`, `Collected`, `Received`,
///   `Reported on`, `Document created`) and only the second is the collection.
/// - My Health Record wraps the report in a page whose own header is the *report*
///   date, days after the draw.
/// - InstantScripts prints a header `Collected:` that contradicts the QML
///   document underneath it — and is even later than that document's own
///   `Completed` line, so it cannot be a collection time at all.
///
/// ⚠️ Every fixture here is structurally faithful to a real report and carries
/// **substituted** dates and values — `docs/privacy-and-ip.md`, "the shape of a
/// finding, never the reading".
final class LabReportDateTests: XCTestCase {

    private func scan(_ text: String) -> LabReportParser.Scan {
        LabReportParser.parseReport(text, source: .pdf,
                                    importedAt: Date(timeIntervalSince1970: 1_780_000_000))
    }

    /// The same UTC construction the parser uses. The report prints no time zone,
    /// so a fixed one is the only answer that does not move with the phone.
    private func utc(_ year: Int, _ month: Int, _ day: Int,
                     _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day,
                                                  hour: hour, minute: minute))!
    }

    // MARK: - Five dates, one of them right

    func testPrefersCollectedOverTheFourOtherDatesSullivanNicolaidesPrints() {
        let text = """
        SULLIVAN NICOLAIDES PATHOLOGY
        Requested: 05/05/2026 09:00
        Collected: 07/05/2026 10:24
        Received:  07/05/2026 15:02
        Reported on: 08/05/2026 08:30
        Document created: 09/05/2026 07:15
        Sodium      139     135 - 145   mmol/L
        """
        let s = scan(text)
        XCTAssertEqual(s.collectedAt, utc(2026, 5, 7, 10, 24))
        XCTAssertTrue(s.results.allSatisfy(\.collectedAtIsExact))
    }

    /// The report date is two days after the draw, and it is the one printed
    /// largest — on the wrapper page, above the document that knows better.
    func testTheMyHealthRecordWrapperDateLosesToTheCollectionDate() {
        let text = """
        Pathology Report / 14-March-2026
        My Health Record
        Collection Date | Observation Date | Test Result Name | Diagnostic Service | Status
        12-Mar-26 | 12-Mar-26 | Full Blood Count | Sullivan Nicolaides | Final

        Date Collected 12-Mar-26
        Haemoglobin   145   130 - 175   g/L
        """
        let s = scan(text)
        XCTAssertEqual(s.collectedAt, utc(2026, 3, 12))
        XCTAssertNotEqual(s.collectedAt, utc(2026, 3, 14))
    }

    /// ⚠️ Both fields say "collected" and both name the same *day*. Only the time
    /// separates them, which is why the parser reads times at all.
    func testTheInstantScriptsHeaderLosesToItsOwnStructuredCollectionTime() {
        let text = """
        InstantScripts Telehealth
        Collected: 2025-06-18 13:15:00
        Completed: 2025-06-18 12:40:00
        204 Collection : 18/06/2025  11:50 am
        Sodium      139     135 - 145   mmol/L
        """
        let s = scan(text)
        XCTAssertEqual(s.collectedAt, utc(2025, 6, 18, 11, 50))
        XCTAssertNotEqual(s.collectedAt, utc(2025, 6, 18, 13, 15))
    }

    /// A report that only says when it was written says nothing about when the
    /// blood was taken, and the parser must not invent the difference.
    func testAReportWithOnlyAReportDateYieldsNoCollectionDate() {
        let text = """
        Reported on: 08/05/2026 08:30
        Document created: 09/05/2026 07:15
        Sodium      139     135 - 145   mmol/L
        """
        let s = scan(text)
        XCTAssertNil(s.collectedAt)
        XCTAssertFalse(s.results.first?.collectedAtIsExact ?? true)
    }

    // MARK: - The shapes a date is printed in

    func testEveryDateShapeTheCorpusPrintsIsRead() {
        let cases: [(String, Date)] = [
            ("Collected: 07/05/2026 10:24", utc(2026, 5, 7, 10, 24)),
            ("Date Collected 12-Mar-26", utc(2026, 3, 12)),
            ("Collected: 2025-06-18 13:15:00", utc(2025, 6, 18, 13, 15)),
            ("Collection Date: 14-March-2026", utc(2026, 3, 14)),
            ("204 Collection : 18/06/2025  11:50 am", utc(2025, 6, 18, 11, 50))
        ]
        for (line, expected) in cases {
            XCTAssertEqual(scan(line).collectedAt, expected, "failed on: \(line)")
        }
    }

    /// Australian reports are day-first. A month-first reading of `07/05/2026`
    /// is a different month, so the parser refuses anything whose month cannot be
    /// a month rather than swapping the two and being quietly wrong.
    func testAMonthFirstDateIsRefusedRatherThanSwapped() {
        let s = scan("Collected: 05/20/2026")
        XCTAssertNil(s.collectedAt)
    }

    /// ⚠️ The heading names the column; the date is on the row underneath, beside
    /// an observation date that is a different day on any report authorised late.
    func testTheDateUnderAColumnHeadingIsTakenFromTheNearestColumn() {
        let text = """
        Test Name | Collection Date | Observation Date
        Full Blood Count | 12-Mar-26 | 14-Mar-26
        """
        let s = scan(text)
        XCTAssertEqual(s.collectedAt, utc(2026, 3, 12))
    }

    // MARK: - A date is not a result

    /// ⚠️ Live until 2026-08-09: `Collected: 07/05/2026 10:24` produced an analyte
    /// called "Collected" with a value of 7, and a My Health Record table row
    /// produced one called "-Dec". A number inside a date is never a result.
    func testADateIsNeverReadAsALabValue() {
        let text = """
        Collected: 07/05/2026 10:24
        12-Mar-26 | 12-Mar-26 | Full Blood Count | Sullivan Nicolaides | Final
        Sodium      139     135 - 145   mmol/L
        """
        let s = scan(text)
        XCTAssertEqual(s.results.count, 1)
        XCTAssertEqual(s.results.first?.analyte.key, "sodium")
    }
}
