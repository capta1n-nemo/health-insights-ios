import XCTest
@testable import InsightKit

/// Backlog B18-1 / S9. The assertions that matter are the ones about what this
/// type will **not** say: no score, no band, no direction it has not earned, and
/// a refusal that names a sleep study rather than trailing off.
final class BreathingDisturbanceTrendTests: XCTestCase {

    private let calendar = Calendar.current

    private var day0: Date {
        calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: day0) ?? day0
    }

    private func nights(_ values: [Double]) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(type: .breathingDisturbanceIndex, value: value,
                               start: day(index), end: day(index), source: .oura)
        }
    }

    // MARK: - The floor

    func testBelowTheFloorThereIsNoPlacementAndNoLine() throws {
        let trend = BreathingDisturbanceTrend.build(samples: nights([3, 4, 5, 6]),
                                                    calendar: calendar)
        XCTAssertNil(trend.trend)
        XCTAssertNil(trend.latestPercentile)
        XCTAssertNil(trend.driftSentence)
        let gate = try XCTUnwrap(trend.coverage)
        XCTAssertEqual(gate.remaining, BreathingDisturbanceTrend.minimumNights - 4)
        XCTAssertNotNil(gate.sentence)
    }

    func testTwoReadingsForOneNightDoNotBothEnterTheFit() {
        var samples = nights(Array(repeating: 5, count: 20))
        samples.append(HealthMetricSample(type: .breathingDisturbanceIndex, value: 40,
                                          start: day(0).addingTimeInterval(3600),
                                          end: day(0).addingTimeInterval(3600), source: .oura))
        let trend = BreathingDisturbanceTrend.build(samples: samples, calendar: calendar)
        XCTAssertEqual(trend.nights.count, 20, "a re-synced night is one night")
    }

    // MARK: - What it is allowed to say

    func testAFlatSeriesIsCalledSteadyRatherThanGivenADirection() throws {
        let values = (0..<30).map { Double(5 + $0 % 3) }
        let trend = BreathingDisturbanceTrend.build(samples: nights(values), calendar: calendar)
        let sentence = try XCTUnwrap(trend.driftSentence)
        XCTAssertTrue(sentence.contains("Steady"))
        XCTAssertFalse(trend.trend?.isMeaningful ?? true)
    }

    /// ⚠️ **The ramp carries noise on purpose.** `ScoreTrend.isMeaningful` opens
    /// `residualSD > 0`, so a mathematically perfect line reports as *not*
    /// meaningful — which is the right guard for a real series and a trap for a
    /// synthetic one. Real nights scatter; this fixture does too.
    func testARealDriftIsNamedAndSaysItIsNotAVerdict() throws {
        let values = (0..<30).map { Double($0) * 0.5 + Double($0 % 3) * 0.2 }
        let trend = BreathingDisturbanceTrend.build(samples: nights(values), calendar: calendar)
        let sentence = try XCTUnwrap(trend.driftSentence)
        XCTAssertTrue(sentence.contains("Drifting up"), sentence)
        XCTAssertTrue(sentence.contains("not a verdict"), sentence)
    }

    func testTheLatestNightIsPlacedAmongTheReadersOwn() throws {
        var values = Array(repeating: 4.0, count: 29)
        values.append(30)
        let trend = BreathingDisturbanceTrend.build(samples: nights(values), calendar: calendar)
        XCTAssertEqual(try XCTUnwrap(trend.latestPercentile), 1, accuracy: 0.01,
                       "Baseline's own 0–1 scale, not a percentage")
    }

    // MARK: - The refusal

    func testTheRefusalNamesTheOnlyThingThatActuallyAnswersIt() {
        XCTAssertTrue(BreathingDisturbanceTrend.whatWouldAnswerIt.contains("sleep study"))
        XCTAssertTrue(BreathingDisturbanceTrend.notAnApnoeaTest.contains("not an apnoea test"))
        XCTAssertTrue(BreathingDisturbanceTrend.notAnApnoeaTest
            .contains("does not screen for apnoea"))
    }

    /// The metric itself must stay unscoreable. A reference range appearing on it
    /// would put a band on every chart in the app that draws it, which is the
    /// apnoea claim arriving through the back door.
    func testTheIndexStillCarriesNoPublishedRange() {
        XCTAssertNil(MetricType.breathingDisturbanceIndex.referenceRange)
    }
}
