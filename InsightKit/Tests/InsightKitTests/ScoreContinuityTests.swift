import XCTest
@testable import InsightKit

/// **A score must not lurch when its input barely moves.**
///
/// This is the general form of a defect this codebase has now shipped twice, so
/// it is enforced here rather than found again by reading the code:
///
/// - Body Composition's score-over-time chart read `49 · 15 · 15 · 55` on four
///   consecutive days because a quality term switched into the blend at full
///   weight as a noisy fitted slope crossed 0.1 %/week;
/// - and `rateScore` had a second step at *exactly zero* — a 25-point jump in
///   the term for a slope of ±0.001 — which the first fix did not cover, because
///   `changeConfidence` is 0 in precisely that band.
///
/// Every function checked here maps a **noisy measurement** to a 0–100 score.
/// The rule is that a small change in the measurement produces a small change in
/// the score. Not that the curve is smooth in the calculus sense — a kink is
/// fine, a **step** is not — because the reader sees the score, not the input,
/// and a step tells them something happened that did not happen.
///
/// ## What belongs here, and what does not
///
/// A step is legitimate where the input genuinely is discrete: a count of days
/// of data, a stated goal, a category somebody chose. Those are not measurements
/// and they do not wander. Everything a sensor or a fit produces does wander,
/// and that is what this sweeps.
final class ScoreContinuityTests: XCTestCase {

    /// The largest score change allowed for a **thousandth** of a unit of input.
    ///
    /// Deliberately not zero: a piecewise-linear curve has kinks, and a kink
    /// crossed in one step of the sweep moves the output by roughly the local
    /// gradient. What this catches is a *step* — an output change with no input
    /// change behind it, which is always at least an order of magnitude larger.
    private let tolerance = 1.0

    /// Sweeps `input` across `range` and fails on the first jump.
    ///
    /// Reports the two inputs either side and both scores, because "some curve
    /// is discontinuous" is not a finding anybody can act on.
    private func assertContinuous(_ name: String,
                                  over range: ClosedRange<Double>,
                                  steps: Int = 4000,
                                  file: StaticString = #filePath,
                                  line: UInt = #line,
                                  _ score: (Double) -> Double?) {
        let width = (range.upperBound - range.lowerBound) / Double(steps)
        var previousInput = range.lowerBound
        var previous = score(previousInput)
        var worst = (jump: 0.0, at: 0.0, from: 0.0, to: 0.0)
        for step in 1...steps {
            let input = range.lowerBound + Double(step) * width
            let value = score(input)
            if let previous, let value {
                let jump = abs(value - previous)
                if jump > worst.jump {
                    worst = (jump, input, previous, value)
                }
            }
            previousInput = input
            previous = value
        }
        _ = previousInput
        XCTAssertLessThanOrEqual(
            worst.jump, tolerance,
            """
            \(name) steps by \(String(format: "%.1f", worst.jump)) points at an input of \
            \(String(format: "%.4f", worst.at)): \(String(format: "%.2f", worst.from)) → \
            \(String(format: "%.2f", worst.to)). A reader's measurement crosses this \
            boundary by noise alone.
            """,
            file: file, line: line)
    }

    // MARK: - Body composition

    /// **The regression.** The rate term, on every goal, across the sign flip
    /// that used to step 25 points at a slope of zero.
    func testRateScoreIsContinuousOnEveryGoal() {
        for goal in WeightGoal.allCases {
            assertContinuous("rateScore(\(goal))", over: -3...3) {
                CompositionVelocityModel.rateScore(percentPerWeek: $0, goal: goal)
            }
        }
    }

    /// And with no goal set, where the curve meets its own flat region.
    func testRateScoreIsContinuousWithNoGoal() {
        assertContinuous("rateScore(no goal)", over: -3...3) {
            CompositionVelocityModel.rateScore(percentPerWeek: $0, goal: nil)
        }
    }

    /// The ramp that started all this. Also covered by
    /// `BodyCompositionStabilityTests`; here so the whole family is in one
    /// sweep and a future edit is caught by either.
    func testChangeConfidenceIsContinuous() {
        assertContinuous("changeConfidence", over: -2...2) { pct in
            CompositionVelocity(windowDays: 56, kilogramsPerWeek: pct, percentPerWeek: pct,
                                leanKilogramsPerWeek: nil, leanShareOfChange: nil,
                                residualSD: 0, weighIns: 56, latestWeight: 100)
                .changeConfidence * 100
        }
    }

    /// The lean-share curve, across the zero crossing where losing flips to
    /// gaining and the same ratio is read in opposite directions.
    func testQualityScoreIsContinuousThroughZero() {
        for losing in [true, false] {
            assertContinuous("qualityScore(isLosing: \(losing))", over: -1...1) {
                CompositionVelocityModel.qualityScore(leanShareOfChange: $0, isLosing: losing)
            }
        }
    }

    // MARK: - Sleep

    /// Hours slept is the noisiest input on the card — a wearable's own
    /// disagreement with itself is ten to fifteen minutes — and it used to be
    /// read through a step table.
    func testSleepDurationScoreIsContinuous() {
        assertContinuous("SleepInsight.durationScore", over: 0...14) {
            SleepInsight.durationScore($0)
        }
    }

    func testSleepLatencyScoreIsContinuous() {
        assertContinuous("SleepInsight.latencyScore", over: 0...120) {
            SleepInsight.latencyScore($0)
        }
    }

    func testSleepEfficiencyScoreIsContinuous() {
        assertContinuous("SleepInsight.efficiencyScore", over: 40...100) {
            SleepInsight.efficiencyScore($0)
        }
    }

    // MARK: - Blood pressure

    /// **Both numbers, independently.** The band is chosen by systolic *and*
    /// diastolic, so a step hides in the diastolic axis even when the systolic
    /// one is smooth — which is exactly where one was found.
    func testBloodPressureScoreIsContinuousInSystolic() {
        for diastolic in [70.0, 82.0, 95.0] {
            assertContinuous("BP score (diastolic \(diastolic))", over: 80...200) {
                BloodPressureEstimator.score(systolic: $0, diastolic: diastolic)
            }
        }
    }

    func testBloodPressureScoreIsContinuousInDiastolic() {
        for systolic in [100.0, 125.0, 150.0] {
            assertContinuous("BP score (systolic \(systolic))", over: 50...130) {
                BloodPressureEstimator.score(systolic: systolic, diastolic: $0)
            }
        }
    }
}
