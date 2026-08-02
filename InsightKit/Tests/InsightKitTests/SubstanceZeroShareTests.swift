import XCTest
@testable import InsightKit

/// A signal that took nothing off the substance score has to say **why**, and
/// the three reasons are not interchangeable.
///
/// From the reader's export, under "Charted, not scored": *"Resting Heart Rate:
/// +2 bpm after use — moved the way you'd want it to"*, and the same for HRV
/// down 4% and time-to-fall-asleep up 7 minutes. All three moved the *unwelcome*
/// way, and the same card's driver list flagged all three as notable. One card
/// making two opposite claims about one number.
final class SubstanceZeroShareTests: XCTestCase {

    private func effect(_ metric: MetricType, adverse: Bool,
                        affected: Int, baseline: Int) -> SubstanceResponseAnalyzer.MetricEffect {
        .init(metric: metric, baseline: 60, afterUse: 62,
              deltaAbsolute: 2, deltaPercent: 3.3,
              affectedNights: affected, baselineNights: baseline,
              isAdverse: adverse, baselineSD: 4)
    }

    /// A share it earned needs no excuse.
    func testAScoringSignalGetsNoSuffix() {
        let text = SubstanceResponseAnalyzer.zeroShareReason(
            effect(.restingHeartRate, adverse: true, affected: 20, baseline: 20), share: 0.3)
        XCTAssertEqual(text, "")
    }

    /// The genuinely good case keeps its good-news wording.
    func testAWelcomeMoveStillReadsAsGoodNews() {
        let text = SubstanceResponseAnalyzer.zeroShareReason(
            effect(.restingHeartRate, adverse: false, affected: 20, baseline: 20), share: 0)
        XCTAssertTrue(text.contains("moved the way you'd want it to"))
    }

    /// **The regression.** The reader's own case: adverse, but on three readings.
    /// It must not claim the move was welcome.
    func testAnAdverseMoveOnThinEvidenceIsNotCalledWelcome() {
        let text = SubstanceResponseAnalyzer.zeroShareReason(
            effect(.restingHeartRate, adverse: true, affected: 3, baseline: 65), share: 0)
        XCTAssertFalse(text.contains("moved the way you'd want it to"),
                       "an unwelcome move must never be described as welcome")
        XCTAssertTrue(text.contains("not the direction you'd want"))
        XCTAssertTrue(text.contains("3 readings"), "and it says how thin the evidence is")
    }

    /// Adverse, well-evidenced, but too small to register — a third distinct
    /// answer, and not the same sentence as either of the others.
    func testAnAdverseButTinyMoveSaysSo() {
        let text = SubstanceResponseAnalyzer.zeroShareReason(
            effect(.restingHeartRate, adverse: true,
                   affected: SubstanceResponseAnalyzer.fullEvidencePairs + 5,
                   baseline: 60), share: 0)
        XCTAssertFalse(text.contains("moved the way you'd want it to"))
        XCTAssertTrue(text.contains("too small to move the score"))
    }

    /// The three reasons are genuinely different strings — if two collapsed the
    /// distinction would be lost again without any test failing.
    func testTheThreeReasonsAreDistinct() {
        let welcome = SubstanceResponseAnalyzer.zeroShareReason(
            effect(.restingHeartRate, adverse: false, affected: 20, baseline: 20), share: 0)
        let thin = SubstanceResponseAnalyzer.zeroShareReason(
            effect(.restingHeartRate, adverse: true, affected: 3, baseline: 65), share: 0)
        let tiny = SubstanceResponseAnalyzer.zeroShareReason(
            effect(.restingHeartRate, adverse: true,
                   affected: SubstanceResponseAnalyzer.fullEvidencePairs + 5,
                   baseline: 60), share: 0)
        XCTAssertEqual(Set([welcome, thin, tiny]).count, 3)
    }
}
