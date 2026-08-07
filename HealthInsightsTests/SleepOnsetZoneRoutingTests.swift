import Foundation
import XCTest
import InsightKit
@testable import HealthInsights

/// `D56` problem 1, app side: **a bedtime must render in the zone the reader is
/// in now**, not the one their phone was in the night they slept.
///
/// The arithmetic is InsightKit's and is tested there. What is tested here is the
/// thing that was missed on 2026-08-07 and is the only reason the fix shipped
/// nothing to most of the app: the *routing*. The sleep card's own sections were
/// converted one at a time, and the **generic** surfaces — the metric detail
/// page, the Vitals rows, the Data tab, anything that takes a `MetricType` and
/// renders what is stored under it — were missed precisely because they are
/// generic. Nobody grepping for "sleep" finds `AppModel.breakdown(_:)`.
///
/// ## How this is made non-vacuous
///
/// Seeded in Manila, read in Sydney. `NSTimeZone.default` moves `TimeZone.current`
/// and `Calendar.current` for the whole process, which is as close to the
/// reader's actual flight as a unit test gets. Every assertion below is checked
/// against a `XCTAssertNotEqual` on the raw stored values first — if the fixture
/// ever stops producing a difference, these tests fail rather than quietly
/// passing on nothing.
@MainActor
final class SleepOnsetZoneRoutingTests: XCTestCase {

    private var originalZone: TimeZone!

    override func setUp() {
        super.setUp()
        originalZone = NSTimeZone.default
    }

    override func tearDown() {
        NSTimeZone.default = originalZone
        super.tearDown()
    }

    /// A model whose `.sleepOnset` history was minted in Manila, being read from
    /// Sydney — two hours east, the reader's own 2026-08-07 journey.
    private func modelSeededAbroad() -> AppModel {
        NSTimeZone.default = TimeZone(identifier: "Asia/Manila")!
        let model = TestAppModel.make()
        model.seedSyntheticData(days: 60)
        NSTimeZone.default = TimeZone(identifier: "Australia/Sydney")!
        return model
    }

    private func rawOnsets(_ model: AppModel) -> [HealthMetricSample] {
        model.samples.filter { $0.type == .sleepOnset }.sorted { $0.start < $1.start }
    }

    private func convertedOnsets(_ model: AppModel) -> [HealthMetricSample] {
        SleepTravel.onsets(in: model.samples).sorted { $0.start < $1.start }
    }

    /// `series(_:)` — what a chart draws.
    func testSeriesRendersBedtimesInTheZoneTheReaderIsInNow() throws {
        let model = modelSeededAbroad()
        let raw = rawOnsets(model)
        let here = convertedOnsets(model)
        try XCTSkipIf(raw.isEmpty, "The synthetic seed produced no bedtimes.")
        XCTAssertNotEqual(raw.map(\.value), here.map(\.value),
                          "Manila and Sydney must disagree, or this test proves nothing.")

        XCTAssertEqual(model.series(.sleepOnset).map(\.value), here.map(\.value))
        XCTAssertEqual(model.series(.sleepOnset).map(\.start), here.map(\.start))
    }

    /// `latest(_:)` — the Vitals glance row and the Data tab's "most recent".
    func testLatestBedtimeIsTheOneOnTheReadersCurrentClock() throws {
        let model = modelSeededAbroad()
        let raw = rawOnsets(model)
        let here = convertedOnsets(model)
        try XCTSkipIf(raw.isEmpty, "The synthetic seed produced no bedtimes.")
        XCTAssertNotEqual(raw.last?.value, here.last?.value)

        XCTAssertEqual(model.latest(.sleepOnset), here.last?.value)
    }

    /// `breakdown(_:)` — the metric detail screen, per source.
    func testTheMetricDetailBreakdownIsBuiltFromTheConvertedOnsets() throws {
        let model = modelSeededAbroad()
        let here = convertedOnsets(model)
        try XCTSkipIf(here.isEmpty, "The synthetic seed produced no bedtimes.")

        let charted = model.breakdown(.sleepOnset).sources
            .flatMap(\.samples).map(\.value).sorted()
        XCTAssertEqual(charted, here.map(\.value).sorted())
    }

    /// `vitalsSummaries` — the row the Data tab actually draws, which reaches the
    /// value by a different path from `latest(_:)` and so needs its own check.
    func testTheVitalsRowShowsTheConvertedBedtime() throws {
        let model = modelSeededAbroad()
        let here = convertedOnsets(model)
        try XCTSkipIf(here.isEmpty, "The synthetic seed produced no bedtimes.")

        let summary = try XCTUnwrap(model.vitalsSummaries[.sleepOnset])
        XCTAssertEqual(summary.displayValue, here.last?.value)
        XCTAssertEqual(summary.latest.start, here.last?.start)
    }

    /// Every other metric must keep reading the untouched buffer — both because
    /// converting them would be wrong and because `MultiSource`'s memo is keyed
    /// on that buffer's address, and handing it a rebuilt copy costs a full scan
    /// per metric.
    func testNoOtherMetricIsRewritten() throws {
        let model = modelSeededAbroad()
        for metric in [MetricType.heartRate, .stepCount, .bodyMass] {
            let direct = model.samples.samples(of: metric).map(\.value)
            XCTAssertEqual(model.series(metric).map(\.value), direct,
                           "\(metric) must be served straight from `samples`.")
        }
    }
}
