import XCTest
@testable import InsightKit

/// The one thing this type exists for: the same `weight: 0` means "we decided
/// this doesn't count" when a model reports it and "we don't know" when the
/// screen invents it, and only one of those is a finding.
final class ChartedContributionsTests: XCTestCase {

    private let reported = [
        MetricContribution(metric: .restingHeartRate, higherIsBetter: false,
                           weight: 0.6, detail: "58 bpm"),
        // Deliberately unscored, deliberately reported: a real signal with no
        // validated curve behind it. Its zero is a finding.
        MetricContribution(metric: .dayStrain, higherIsBetter: nil,
                           weight: 0, detail: "14.2")
    ]

    func testReportedContributionsPassThroughUntouchedAndAreFlaggedAsReal() {
        let resolved = ChartedContributions.resolve(reported: reported,
                                                    declaredInputs: [.vo2Max])
        XCTAssertTrue(resolved.areReported)
        XCTAssertEqual(resolved.contributions, reported)
        XCTAssertEqual(resolved.metrics, [.restingHeartRate, .dayStrain])
    }

    /// Substance Impact before its first logged event. The card still charts —
    /// an empty box would be worse — but nothing it draws is a claim the model
    /// made about weighting or direction.
    func testAnEmptyReportFallsBackToDeclaredInputsAndSaysSo() {
        let resolved = ChartedContributions.resolve(
            reported: [], declaredInputs: [.restingHeartRate, .sleepDurationHours])
        XCTAssertFalse(resolved.areReported)
        XCTAssertEqual(resolved.metrics, [.restingHeartRate, .sleepDurationHours])
        for contribution in resolved.contributions {
            XCTAssertEqual(contribution.weight, 0)
            XCTAssertNil(contribution.higherIsBetter)
            XCTAssertTrue(contribution.detail.isEmpty)
        }
    }

    /// Finding the declared inputs means searching the engine for the model, and
    /// the common path never needs them.
    func testDeclaredInputsAreNotComputedWhenTheModelReported() {
        var asked = 0
        _ = ChartedContributions.resolve(reported: reported,
                                         declaredInputs: { asked += 1; return [] }())
        XCTAssertEqual(asked, 0)
    }

    /// A model reporting nothing *and* declaring nothing is an empty card, not a
    /// crash and not a phantom row.
    func testNothingReportedAndNothingDeclaredIsSimplyEmpty() {
        let resolved = ChartedContributions.resolve(reported: [], declaredInputs: [])
        XCTAssertTrue(resolved.isEmpty)
        XCTAssertFalse(resolved.areReported)
    }
}
