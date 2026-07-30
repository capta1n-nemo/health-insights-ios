import XCTest
@testable import InsightKit

final class RawMetricAndTimeframeTests: XCTestCase {
    private func raw(_ id: String, _ name: String, _ value: Double, daysAgo: Double,
                     source: MetricSource = .appleHealth) -> RawMetricSample {
        RawMetricSample(identifier: id, displayName: name, value: value, unit: "u",
                        start: Date().addingTimeInterval(-daysAgo * 24 * 3600), source: source)
    }

    func testGroupsByIdentifierNewestFirst() {
        let samples = [
            raw("a", "Alpha", 1, daysAgo: 3),
            raw("a", "Alpha", 2, daysAgo: 1),
            raw("b", "Bravo", 9, daysAgo: 2)
        ]
        let groups = samples.groupedByIdentifier()
        XCTAssertEqual(groups.count, 2)
        // Sorted by display name: Alpha, Bravo.
        XCTAssertEqual(groups.first?.displayName, "Alpha")
        // Newest sample first within a group.
        XCTAssertEqual(groups.first?.latest?.numericValue, 2)
    }

    func testTextGroupIsNotPlottableButKeepsItsStates() {
        let now = Date()
        let samples = [
            RawMetricSample(identifier: "oura.daily_resilience.level", displayName: "Level",
                            value: .text("solid"), unit: "", start: now, source: .oura),
            RawMetricSample(identifier: "oura.daily_resilience.level", displayName: "Level",
                            value: .text("strong"), unit: "",
                            start: now.addingTimeInterval(-86_400), source: .oura)
        ]
        let group = try? XCTUnwrap(samples.groupedByIdentifier().first)
        XCTAssertEqual(group?.isPlottable, false)
        XCTAssertEqual(group?.distinctTextValues, ["solid", "strong"])
        XCTAssertEqual(group?.latest?.formattedValue, "solid")
    }

    func testLegacyNumericCacheStillDecodes() throws {
        // Caches written before `value` became a typed RawValue stored a bare
        // JSON number. They must keep loading, or a user's history vanishes.
        let legacy = """
        [{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","identifier":"a","displayName":"A",
          "value":42.5,"unit":"kg","start":760000000,"end":760000000,
          "source":{"id":"oura","displayName":"Oura"}}]
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([RawMetricSample].self, from: legacy)
        XCTAssertEqual(decoded.first?.value, .number(42.5))
        XCTAssertEqual(decoded.first?.numericValue, 42.5)
    }

    func testTimeframeFilter() {
        let samples = [raw("a", "A", 1, daysAgo: 2), raw("a", "A", 2, daysAgo: 40)]
        XCTAssertEqual(samples.within(.week).count, 1)
        XCTAssertEqual(samples.within(.all).count, 2)
    }

    func testTimeframeWindows() {
        XCTAssertNil(Timeframe.all.window)
        XCTAssertEqual(Timeframe.week.window, 7 * 24 * 3600)
        XCTAssertNil(Timeframe.all.startDate())
        XCTAssertNotNil(Timeframe.month.startDate())
        XCTAssertEqual(Timeframe.allCases.count, 6)
    }
}
