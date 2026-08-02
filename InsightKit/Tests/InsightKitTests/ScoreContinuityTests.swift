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

    /// Overnight blood oxygen. Added by the handover audit of this session's own
    /// claims: it was **fixed and not swept**, and the roadmap said all seven
    /// were guarded. Fixing without enrolling is how the next edit reintroduces
    /// the step with nothing to catch it.
    func testSleepOxygenScoreIsContinuous() {
        assertContinuous("SleepInsight.oxygenScore", over: 85...100) {
            SleepInsight.oxygenScore($0)
        }
    }

    // MARK: - Readiness

    /// Readiness' own blood-oxygen component: the no-baseline fallback and the
    /// absolute floor below 92, swept together as the card applies them.
    ///
    /// A pulse oximeter's resolution is a percentage point, so both lines were
    /// reachable by rounding — `>= 95 ? 85 : 60` and `min(component, 40)`.
    func testTheReadinessOxygenComponentIsContinuous() {
        // The no-baseline path, where the published fallback lives.
        assertContinuous("ReadinessScore oxygen (no baseline)", over: 85...100) {
            ReadinessScore.oxygenComponent(value: $0, z: nil)
        }
        // And with a baseline, where the absolute floor is the only step left
        // it could take.
        for z in [-2.0, 0.0, 1.5] {
            assertContinuous("ReadinessScore oxygen (z \(z))", over: 85...100) {
                ReadinessScore.oxygenComponent(value: $0, z: z)
            }
        }
    }

    /// And the floor still floors — continuity must not have bought itself by
    /// removing the safety behaviour it was wrapped around.
    func testTheReadinessOxygenFloorStillBites() {
        // A reader whose baseline says 90% is an ordinary night still gets
        // marked down for it, because the floor is absolute.
        let flattering = ReadinessScore.oxygenComponent(value: 90, z: 0)
        XCTAssertLessThanOrEqual(flattering, 40,
                                 "a low absolute saturation was normalised away")
        XCTAssertGreaterThan(ReadinessScore.oxygenComponent(value: 97, z: 0), 60)
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

    // MARK: - Vital signs

    /// The hard-bound override, swept **through** the bound. `boundNormality`
    /// used to cap at 35 regardless of distance, so crossing a clinical bound by
    /// a thousandth of a unit dropped a reading's normality by up to 65 points.
    func testTheHardBoundOverrideIsContinuous() {
        let spec = VitalSignsCheck.specs.first { $0.metric == .oxygenSaturation }
        guard let spec, let hardLow = spec.hardLow else {
            return XCTFail("blood oxygen must have a hard low to sweep")
        }
        // The reading's own curve value, held fixed, so the sweep isolates the
        // override rather than the Gaussian underneath it.
        let fromTheCurve = 82.0
        assertContinuous("boundNormality", over: (hardLow - spec.hardTolerance * 1.5)...(hardLow + 2)) { value in
            value < hardLow
                ? VitalSignsCheck.boundNormality(fromTheCurve,
                                                 distance: hardLow - value, spec: spec)
                : fromTheCurve
        }
    }

    /// And the relative floor, which fires on HRV — the noisiest series here,
    /// and the one whose readers have the widest spreads.
    func testTheRelativeFloorIsContinuous() {
        let floor = 30.0   // an HRV median of 50 against the 0.6 relative floor
        assertContinuous("relativeFloorNormality", over: 10...40) { value in
            value < floor
                ? VitalSignsCheck.relativeFloorNormality(82, value: value, floor: floor)
                : 82
        }
    }

    // MARK: - Energy

    /// One hour's effect on the reservoir. This one **compounds**: `curve` runs
    /// a bucket per hour since midnight, so a three-point step per bucket
    /// reached the card multiplied by a dozen.
    func testTheHourlyEnergyChangeIsContinuous() {
        assertContinuous("EnergyModel.hourlyChange", over: 0...5) {
            // Scaled into score units: the reservoir is 0–100 and this is a
            // change in it, so the same one-point tolerance applies directly.
            EnergyModel.hourlyChange($0)
        }
    }

    /// The ends are unchanged — an idle hour still returns the full trickle, an
    /// active one still costs exactly what it cost.
    func testTheHourlyEnergyChangeKeepsItsEnds() {
        XCTAssertEqual(EnergyModel.hourlyChange(0), EnergyModel.trickleRechargePerHour,
                       accuracy: 1e-9)
        XCTAssertEqual(EnergyModel.hourlyChange(4), -4, accuracy: 1e-9)
        XCTAssertLessThan(EnergyModel.hourlyChange(2), 0, "an active hour must cost")
    }
}
