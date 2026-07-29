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
        XCTAssertEqual(groups.first?.latest?.value, 2)
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
