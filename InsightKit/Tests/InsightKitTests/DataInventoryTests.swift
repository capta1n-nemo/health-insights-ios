import XCTest
@testable import InsightKit

/// The data-inventory export.
///
/// Tested here rather than looked at on a phone because the report's whole
/// purpose is to be *trusted* — it is the evidence a future session will decide
/// what to build from, and a report that quietly omits a signal is worse than no
/// report at all.
final class DataInventoryTests: XCTestCase {

    private func sample(_ type: MetricType, _ value: Double, daysAgo: Double,
                        source: MetricSource = .oura) -> HealthMetricSample {
        HealthMetricSample(type: type, value: value,
                           start: Date().addingTimeInterval(-daysAgo * 86_400),
                           source: source)
    }

    private func raw(_ id: String, _ value: RawValue, daysAgo: Double,
                     unit: String = "", source: MetricSource = .oura) -> RawMetricSample {
        RawMetricSample(identifier: id, displayName: id, value: value, unit: unit,
                        start: Date().addingTimeInterval(-daysAgo * 86_400),
                        source: source)
    }

    // MARK: - Coverage

    /// Every signal present reaches the report. The failure this guards is the
    /// one that makes the whole export pointless: a field silently dropped, so a
    /// reader concludes the data isn't there when it is.
    func testEverySignalPresentAppearsInTheReport() {
        let samples = [sample(.restingHeartRate, 52, daysAgo: 2),
                       sample(.vo2Max, 44, daysAgo: 3),
                       sample(.dayStrain, 12.4, daysAgo: 1)]
        let groups = [RawMetricGroup(id: "oura.daily.spo2_pct", displayName: "SpO2 pct",
                                     unit: "%", samples: [raw("oura.daily.spo2_pct", .number(97), daysAgo: 1)])]
        let report = DataInventory.markdown(samples: samples, rawGroups: groups)

        for needle in ["Resting Heart Rate", "VO₂max", "oura.daily.spo2_pct"] {
            XCTAssertTrue(report.contains(needle), "report is missing \(needle)")
        }
        XCTAssertEqual(DataInventory.rows(samples: samples, rawGroups: groups).count, 4)
    }

    /// The unmodelled half is the reason the report exists, so it must be
    /// distinguishable from the modelled half rather than merged into one list.
    func testUnmodelledSignalsAreReportedSeparately() {
        let groups = [RawMetricGroup(id: "whoop.cycle.strain", displayName: "Strain",
                                     unit: "", samples: [raw("whoop.cycle.strain", .number(14), daysAgo: 1)])]
        let report = DataInventory.markdown(samples: [sample(.restingHeartRate, 50, daysAgo: 1)],
                                            rawGroups: groups)
        let modelledHeader = report.range(of: "## Signals an insight can already read")!
        let rawHeader = report.range(of: "## Imported, not yet modelled")!
        let modelledSection = report[modelledHeader.upperBound..<rawHeader.lowerBound]

        XCTAssertTrue(modelledSection.contains("Resting Heart Rate"))
        XCTAssertFalse(modelledSection.contains("whoop.cycle.strain"),
                       "an unmodelled field must not be listed as one an insight reads")
        XCTAssertTrue(report[rawHeader.upperBound...].contains("whoop.cycle.strain"))
    }

    /// A categorical field has no distribution but does have a state list —
    /// Oura's resilience level is the worked example, and it renders as an empty
    /// chart everywhere else in the app.
    func testCategoricalFieldsReportTheirStatesRatherThanAnAverage() {
        let samples = [raw("oura.resilience.level", .text("strong"), daysAgo: 1),
                       raw("oura.resilience.level", .text("adequate"), daysAgo: 2),
                       raw("oura.resilience.level", .text("strong"), daysAgo: 3)]
        let group = RawMetricGroup(id: "oura.resilience.level", displayName: "Level",
                                   unit: "", samples: samples)
        let rows = DataInventory.rawRows([group])

        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].median, "a text field has no median")
        XCTAssertEqual(Set(rows[0].states), ["strong", "adequate"])
        XCTAssertTrue(DataInventory.markdown(samples: [], rawGroups: [group])
            .contains("Categorical fields"))
    }

    // MARK: - The numbers

    func testDistributionIsReportedOverTheWholeSeries() {
        let samples = (1...5).map { sample(.restingHeartRate, Double(50 + $0), daysAgo: Double($0)) }
        let row = DataInventory.modelledRows(samples)[0]
        XCTAssertEqual(row.count, 5)
        XCTAssertEqual(row.min, 51)
        XCTAssertEqual(row.median, 53)
        XCTAssertEqual(row.max, 55)
    }

    func testMedianOfAnEvenCountAveragesTheMiddlePair() {
        XCTAssertEqual(DataInventory.median([1, 2, 3, 4]), 2.5)
        XCTAssertEqual(DataInventory.median([7]), 7)
        XCTAssertNil(DataInventory.median([]))
    }

    /// Every source that contributed is named. Which device said what is half of
    /// what makes the report actionable — two sources disagreeing is a finding.
    func testEveryContributingSourceIsNamed() {
        let samples = [sample(.restingHeartRate, 52, daysAgo: 1, source: .oura),
                       sample(.restingHeartRate, 55, daysAgo: 2, source: .appleHealth)]
        let row = DataInventory.modelledRows(samples)[0]
        XCTAssertEqual(row.sources, ["Apple Health", "Oura"])
    }

    /// Dates are built from calendar components, not a `DateFormatter` — several
    /// of those are Darwin-only and this package's suite runs on Linux.
    func testDatesRenderAsPlainISODays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14 UTC
        XCTAssertEqual(DataInventory.day(date, calendar), "2023-11-14")
    }

    // MARK: - What must never be in it

    /// The report is built to be handed to someone else, so the thing it must
    /// never carry is anything that would let them act as the user.
    func testTheReportCarriesNothingCredentialShaped() {
        let report = DataInventory.markdown(
            samples: [sample(.restingHeartRate, 52, daysAgo: 1)],
            rawGroups: [RawMetricGroup(id: "oura.daily.x", displayName: "X", unit: "",
                                       samples: [raw("oura.daily.x", .number(1), daysAgo: 1)])])
        for forbidden in ["access_token", "refresh_token", "client_secret",
                          "Bearer", "apiKey", "password"] {
            XCTAssertFalse(report.lowercased().contains(forbidden.lowercased()),
                           "the export must never contain \(forbidden)")
        }
    }

    /// An empty install produces a report that says so rather than an empty
    /// string — the user needs to be able to tell "nothing synced" from "the
    /// export is broken".
    func testAnEmptyInstallStillProducesAReadableReport() {
        let report = DataInventory.markdown(samples: [], rawGroups: [])
        XCTAssertTrue(report.contains("0 modelled signals"))
        XCTAssertTrue(report.contains("_None._"))
    }

    // MARK: - Full export

    func testFullExportRoundTripsEveryReading() throws {
        let samples = [sample(.restingHeartRate, 52, daysAgo: 1),
                       sample(.vo2Max, 44, daysAgo: 2)]
        let group = RawMetricGroup(id: "oura.daily.x", displayName: "X", unit: "u",
                                   samples: [raw("oura.daily.x", .number(3), daysAgo: 1, unit: "u")])
        let data = try DataInventory.fullExportJSON(samples: samples, rawGroups: [group])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual((json["samples"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual((json["unmodelled"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
    }
}
