import XCTest
@testable import InsightKit

private let heartNow = TestClock.now
private let heartCalendar = TestClock.utc

/// The Heart Health card's own section. What it claims is clinical, so the
/// thresholds and the wording are the part that can be wrong.
final class HeartResponseTests: XCTestCase {

    private func samples(_ metric: MetricType, _ values: [Double],
                         from daysAgo: Int = 0) -> [HealthMetricSample] {
        values.enumerated().map { index, value in
            HealthMetricSample(type: metric, value: value,
                               start: TestClock.day(daysAgo + values.count - 1 - index),
                               source: .appleHealth)
        }
    }

    // MARK: - The published threshold

    /// Cole et al. (NEJM 1999): a fall of 12 bpm **or fewer** is the abnormal
    /// cut-point. At exactly 12 it is abnormal, not borderline-fine — an
    /// off-by-one here would put people on the wrong side of the only published
    /// number this section quotes.
    func testTheCutPointIsInclusive() {
        XCTAssertEqual(HeartResponseModel.RecoveryBand.of(12), .attenuated)
        XCTAssertEqual(HeartResponseModel.RecoveryBand.of(11.9), .attenuated)
        XCTAssertEqual(HeartResponseModel.RecoveryBand.of(12.1), .adequate)
        XCTAssertEqual(HeartResponseModel.RecoveryBand.of(25.9), .adequate)
        XCTAssertEqual(HeartResponseModel.RecoveryBand.of(26), .strong)
    }

    /// The bands describe a reading, never a person. "Poor" and "bad" are
    /// verdicts a single post-workout measurement cannot support.
    func testBandsDescribeTheReadingRatherThanTheReader() {
        for band in HeartResponseModel.RecoveryBand.allCases {
            let phrase = band.phrase.lowercased()
            for verdict in ["poor", "bad", "unhealthy", "abnormal", "at risk"] {
                XCTAssertFalse(phrase.contains(verdict), "\(band): \(phrase)")
            }
        }
    }

    // MARK: - The autonomic pair

    /// Rising resting rate with falling variability is the one combination
    /// worth a sentence: they come off the same signal, so agreement is
    /// evidence in a way either alone is not.
    func testBothDriftingTheWrongWayIsNamed() throws {
        let rising = (0..<30).map { 52 + Double($0) * 0.12 }        // +0.84 bpm/week
        let falling = (0..<30).map { 60 - Double($0) * 0.4 }        // −2.8 ms/week
        let output = HeartResponseModel.evaluate(
            samples: samples(.restingHeartRate, rising)
                + samples(.heartRateVariabilityRMSSD, falling),
            now: heartNow, calendar: heartCalendar)

        XCTAssertEqual(output.autonomic.count, 2)
        let sentence = try XCTUnwrap(output.autonomicSentence)
        XCTAssertTrue(sentence.contains("drifting up"), sentence)
        XCTAssertTrue(sentence.lowercased().contains("worth watching"), sentence)
        // Never an instruction, and never a cause stated as fact.
        XCTAssertFalse(sentence.lowercased().contains("you should"), sentence)
    }

    /// One up and one down is not a story, and a hedged sentence about it would
    /// be worse than none.
    func testDisagreeingSignalsGetNoSentence() {
        let rising = (0..<30).map { 52 + Double($0) * 0.12 }
        let alsoRising = (0..<30).map { 40 + Double($0) * 0.4 }
        let output = HeartResponseModel.evaluate(
            samples: samples(.restingHeartRate, rising)
                + samples(.heartRateVariabilityRMSSD, alsoRising),
            now: heartNow, calendar: heartCalendar)
        XCTAssertNil(output.autonomicSentence)
    }

    /// A tenth of a beat a week is arithmetic, not a trend, and no wrist device
    /// resolves it. Same shape as the 3% floor on substance response.
    func testAMovementTooSmallToResolveIsNotADirection() {
        let flat = (0..<30).map { 55 + Double($0 % 2) * 0.02 }
        let output = HeartResponseModel.evaluate(
            samples: samples(.restingHeartRate, flat),
            now: heartNow, calendar: heartCalendar)
        XCTAssertNil(output.autonomic.first?.isImproving)
    }

    /// Falling resting heart rate is the good direction and rising variability
    /// is the good direction — opposite signs, one verdict each.
    func testEachSignalIsJudgedOnItsOwnGoodDirection() {
        let falling = (0..<30).map { 60 - Double($0) * 0.12 }
        let rising = (0..<30).map { 40 + Double($0) * 0.4 }
        let output = HeartResponseModel.evaluate(
            samples: samples(.restingHeartRate, falling)
                + samples(.heartRateVariabilityRMSSD, rising),
            now: heartNow, calendar: heartCalendar)
        for signal in output.autonomic {
            XCTAssertEqual(signal.isImproving, true, "\(signal.metric)")
        }
    }

    // MARK: - Absence

    func testNothingRecordedIsEmptyRatherThanZero() {
        let output = HeartResponseModel.evaluate(samples: [], now: heartNow,
                                                 calendar: heartCalendar)
        XCTAssertTrue(output.isEmpty)
        XCTAssertNil(output.recovery)
        XCTAssertNil(output.recoveryBand)
    }

    /// A recovery reading only exists on days with a hard effort. Demanding one
    /// from the last week would blank the section for anybody who trains twice
    /// a month, which is most people.
    func testARecoveryFromLastMonthStillCounts() {
        let output = HeartResponseModel.evaluate(
            samples: samples(.heartRateRecovery, [31], from: 30),
            now: heartNow, calendar: heartCalendar)
        XCTAssertEqual(output.recovery, 31)
        XCTAssertEqual(output.recoveryBand, .strong)
        XCTAssertFalse(output.isEmpty)
    }
}
