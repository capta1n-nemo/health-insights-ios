import XCTest
@testable import InsightKit

/// The Data tab's metric list is generated from `MetricType.dataCategory` now,
/// so a new connector's signal appears there automatically. These pin the
/// promise: every metric has a home, and the two that silently went missing from
/// the old hand-written list are back.
final class MetricDataCategoryTests: XCTestCase {

    /// Exhaustiveness is the compiler's job; this asserts the *partition* — every
    /// metric lands in exactly one group, and the listed groups plus ownDomain
    /// cover the whole catalogue with nothing double-counted.
    func testEveryMetricHasExactlyOneCategory() {
        let all = Set(MetricType.allCases)
        let grouped = MetricDataCategory.allCases
            .flatMap { MetricType.metrics(in: $0) }
        XCTAssertEqual(grouped.count, all.count, "a metric is in two groups or none")
        XCTAssertEqual(Set(grouped), all)
    }

    /// The regression: sleep latency and vascular age were metrics with data that
    /// the hand-written Data-tab list dropped. The generated list must carry them.
    func testTheTwoThatWentMissingAreListed() {
        XCTAssertEqual(MetricType.sleepLatencyMinutes.dataCategory, .sleepRecovery)
        XCTAssertEqual(MetricType.vascularAge.dataCategory, .heart)
        XCTAssertTrue(MetricType.metrics(in: .sleepRecovery).contains(.sleepLatencyMinutes))
        XCTAssertTrue(MetricType.metrics(in: .heart).contains(.vascularAge))
    }

    /// Blood pressure and the modelled medication level have their own Data-tab
    /// sections, so they must not also appear in the grouped metric list.
    func testDomainMetricsAreNotInTheGroupedList() {
        for metric in [MetricType.bloodPressureSystolic, .bloodPressureDiastolic,
                       .activeMedicationLevel] {
            XCTAssertEqual(metric.dataCategory, .ownDomain, "\(metric.rawValue)")
        }
        for category in MetricDataCategory.listed {
            XCTAssertFalse(MetricType.metrics(in: category).contains(.activeMedicationLevel))
        }
    }

    /// Every group the tab renders has something in it — an empty heading is a
    /// worse answer than no heading.
    func testEveryListedGroupIsNonEmpty() {
        for category in MetricDataCategory.listed {
            XCTAssertFalse(MetricType.metrics(in: category).isEmpty, category.rawValue)
        }
    }
}
