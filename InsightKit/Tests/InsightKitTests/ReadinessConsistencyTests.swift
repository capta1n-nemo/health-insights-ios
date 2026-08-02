import XCTest
@testable import InsightKit

/// The card's own words must quote the card's own number.
///
/// From the reader's export: the dial read **73.8** above a sentence saying
/// *"Your recovery today is 69/100"*. Readiness scores its components, then
/// blends in the wider vitals scan — and the explanation was written before that
/// second step and carried through unchanged, so one card showed two numbers for
/// one thing.
final class ReadinessConsistencyTests: XCTestCase {

    private func steadySamples(now: Date, calendar: Calendar) -> [HealthMetricSample] {
        var samples: [HealthMetricSample] = []
        let values: [MetricType: Double] = [
            .restingHeartRate: 58, .heartRateVariabilityRMSSD: 48,
            .respiratoryRate: 14, .oxygenSaturation: 97,
            .skinTemperatureDeviation: 0.05, .sleepDurationHours: 7.5,
            .heartRate: 70, .bodyTemperature: 36.7
        ]
        for day in stride(from: 27, through: 0, by: -1) {
            let start = calendar.date(byAdding: .day, value: -day, to: now) ?? now
            for (metric, value) in values {
                let jitter = Double(day % 5 - 2) * 0.02 * value
                samples.append(.init(type: metric, value: value + jitter,
                                     start: start, source: .oura))
            }
        }
        return samples
    }

    /// **The regression.** Whatever number the dial shows, the sentence quotes
    /// it — to the rounding the sentence itself uses.
    func testTheExplanationQuotesTheScoreOnTheDial() throws {
        let now = TestClock.now
        let result = ReadinessInsight().evaluate(
            samples: steadySamples(now: now, calendar: TestClock.utc),
            events: [], profile: UserHealthProfile(), now: now)

        let score = try XCTUnwrap(result.score)
        XCTAssertTrue(result.explanation.contains("\(Int(score.rounded()))/100"),
                      "dial says \(score) but the explanation reads: \(result.explanation)")
    }

    /// And the band word in the sentence is the band of that same number, so
    /// "Ready" on the dial cannot sit above "(Take it easy)" in the words.
    func testTheBandInTheWordsMatchesTheScore() throws {
        let now = TestClock.now
        let result = ReadinessInsight().evaluate(
            samples: steadySamples(now: now, calendar: TestClock.utc),
            events: [], profile: UserHealthProfile(), now: now)

        let score = try XCTUnwrap(result.score)
        let band = ReadinessScore.band(score)
        XCTAssertTrue(result.explanation.contains(band),
                      "expected band \(band) in: \(result.explanation)")
        XCTAssertEqual(result.headline, band, "headline and words must agree too")
    }

    /// The builder itself, across the range — cheap, and it pins the contract
    /// the two call sites rely on.
    func testTheBuilderAlwaysQuotesWhatItWasGiven() {
        for score in stride(from: 0.0, through: 100.0, by: 7.5) {
            let text = ReadinessScore.explanation(score: score, scannedSignals: 3)
            XCTAssertTrue(text.contains("\(Int(score.rounded()))/100"))
            XCTAssertTrue(text.contains(ReadinessScore.band(score)))
        }
    }
}
