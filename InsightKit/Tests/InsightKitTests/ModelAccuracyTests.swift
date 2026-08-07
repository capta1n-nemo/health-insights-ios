import XCTest
@testable import InsightKit

/// Backlog P24. Every test here pins a decision that, got wrong, would print a
/// confident number nobody could falsify.
final class ModelAccuracyTests: XCTestCase {

    private let cohort = Cohort(sex: "male", ageBand: "30-39",
                                ethnicity: "white_or_other", region: "low")

    private func outcome(_ predicted: Double, _ actual: Double, day: Int,
                         metric: MetricType = .bloodPressureSystolic,
                         insight: InsightID = .bloodPressure,
                         version: String = "bp-estimator-v2") -> PredictionOutcome {
        PredictionOutcome(insightID: insight, metric: metric, predicted: predicted,
                          actual: actual, modelVersion: version, cohort: cohort,
                          recordedAt: Date(timeIntervalSince1970: 1_767_225_600 + Double(day) * 86_400))
    }

    private func report(errors: [Double], actuals: [Double]) -> CalibrationReport {
        precondition(errors.count == actuals.count)
        let outcomes = zip(actuals, errors).enumerated().map { index, pair in
            outcome(pair.0 + pair.1, pair.0, day: index)
        }
        return ModelAccuracy.reports(from: outcomes)[0]
    }

    // MARK: - ⚠️ Marking its own homework

    /// The single most important test in this file. A card's own score is not
    /// ground truth for that card, and grading against it would produce a
    /// plausible number that means nothing.
    func testAPredictionGradedAgainstTheModelsOwnOutputIsRefused() {
        // A hypothetical "readiness predicted 70, readiness turned out 66" pair.
        // `dayStrain` stands in for any quantity this app computes itself.
        let selfGraded = outcome(70, 66, day: 0, metric: .dayStrain, insight: .readiness,
                                 version: "readiness-v2")
        XCTAssertFalse(ModelAccuracy.admits(selfGraded))
        XCTAssertTrue(ModelAccuracy.reports(from: [selfGraded]).isEmpty)
    }

    /// A vendor's estimate is a model too — comparing against it is a
    /// comparison, not a measurement.
    func testAnotherVendorsEstimateIsNotGroundTruth() {
        XCTAssertFalse(ModelAccuracy.admits(outcome(45, 42, day: 0, metric: .vo2Max,
                                                    insight: .fitness, version: "fitness-v2")))
        XCTAssertFalse(ModelAccuracy.admits(outcome(7, 6.2, day: 0, metric: .sleepDurationHours,
                                                    insight: .sleep, version: "sleep-v1")))
    }

    /// Deny-by-default: the admitted set is an allowlist, so a metric added to
    /// the app later is refused until somebody decides it qualifies.
    func testAdmittedTruthsAreAnAllowlistNotAnExclusionList() {
        let admitted = MetricType.allCases.filter { ModelAccuracy.externallyMeasuredTruths.contains($0) }
        XCTAssertEqual(Set(admitted), ModelAccuracy.externallyMeasuredTruths)
        XCTAssertLessThan(admitted.count, MetricType.allCases.count / 2,
                          "The allowlist has grown into an exclusion list — re-read the circularity note.")
        XCTAssertTrue(ModelAccuracy.admits(outcome(128, 121, day: 0)))
    }

    /// Refused pairs are counted, not silently dropped. A silent filter is how
    /// this hazard comes back.
    func testRefusedPairsAreReportedRatherThanVanishing() {
        let entries = ModelAccuracy.ledger(
            outcomes: [outcome(70, 66, day: 0, metric: .dayStrain, insight: .readiness,
                               version: "readiness-v2")],
            verdicts: [])
        let readiness = entries.first { $0.insightID == .readiness }
        XCTAssertEqual(readiness?.withheldPairs, 1)
        XCTAssertEqual(readiness?.gradedPairs, 0)
        XCTAssertEqual(readiness?.evidence, .selfDefined)
    }

    // MARK: - Nothing is claimed at n = 3

    func testFiguresAreWithheldBelowTheirThresholds() {
        let thin = report(errors: [2, -3, 1], actuals: [120, 124, 118])
        XCTAssertEqual(thin.n, 3)
        XCTAssertNil(thin.typicalError)
        XCTAssertNil(thin.bias)
        XCTAssertNil(thin.persistenceSkill)
        guard case .tooFew(let gate) = thin.reading else { return XCTFail("expected .tooFew") }
        XCTAssertEqual(gate.have, 3)
        XCTAssertEqual(gate.need, CalibrationReport.minimumForTypicalError)
        // ⚠️ Never a blank: the withheld figure is replaced by what it is waiting for.
        XCTAssertNotNil(gate.sentence)
        XCTAssertTrue(thin.sentence.contains("2 more"))
    }

    /// The `n` is never dropped from the sentence — it is the difference
    /// between a measurement and an anecdote.
    func testEverySentenceCarriesItsN() {
        let five = report(errors: [4, -3, 5, -2, 4], actuals: [120, 124, 118, 126, 121])
        XCTAssertTrue(five.sentence.contains("5 graded predictions"), five.sentence)
        let twelve = ModelAccuracy.workedExample()
        XCTAssertTrue(twelve.sentence.contains("12 graded predictions"), twelve.sentence)
    }

    /// A two-sided sign test cannot reach p < 0.05 until n = 6, so the bias
    /// threshold must sit above the point where five same-direction misses
    /// could be five coin flips.
    func testDirectionIsNotClaimedFromFiveCoinFlips() {
        let allHigh = report(errors: [3, 4, 2, 5, 3], actuals: [120, 124, 118, 126, 121])
        XCTAssertEqual(allHigh.overPredictions, 5)
        XCTAssertFalse(allHigh.biasIsBeyondChance)
        XCTAssertNil(allHigh.bias)
    }

    func testExactTwoSidedSignTest() {
        // 8 of 8 one way: 2 * (1/256).
        let allHigh = report(errors: Array(repeating: 3.0, count: 8),
                             actuals: [120, 124, 118, 126, 121, 125, 119, 123])
        XCTAssertEqual(allHigh.directionP ?? 1, 2.0 / 256.0, accuracy: 1e-9)
        XCTAssertTrue(allHigh.biasIsBeyondChance)
        // 4 of 8 each way: the whole distribution, so p = 1.
        let even = report(errors: [3, -3, 2, -2, 4, -4, 1, -1],
                          actuals: [120, 124, 118, 126, 121, 125, 119, 123])
        XCTAssertEqual(even.directionP ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertFalse(even.biasIsBeyondChance)
    }

    // MARK: - Calibrated and useless

    /// The case the whole screen exists for: tiny errors on a quantity that
    /// barely moves. An accuracy percentage would have called this excellent.
    func testAPreciseModelWithNoSkillIsNotCalledAccurate() {
        // Truth wanders by ~1; the model is out by ~1 too. Alternating sign, so
        // there is no lean to report and only skill can catch it.
        let actuals: [Double] = [120, 121, 120, 121, 120, 121, 120, 121, 120, 121, 120, 121]
        let errors: [Double] = [1, -1, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1]
        let flat = report(errors: errors, actuals: actuals)
        XCTAssertEqual(flat.typicalError ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(flat.persistenceBaselineError ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(flat.persistenceSkill ?? 1, 0, accuracy: 1e-9)
        guard case .noSkill = flat.reading else {
            return XCTFail("A model no better than 'same as last time' must not read as tracking: \(flat.reading)")
        }
        XCTAssertTrue(flat.sentence.contains("not yet useful"), flat.sentence)
    }

    /// The baseline and the model are scored on the same pairs — the first has
    /// nothing before it and is dropped from both sides, not one.
    func testSkillComparesLikeWithLike() {
        let r = ModelAccuracy.workedExample()
        XCTAssertEqual(r.comparableError ?? 0, 43.0 / 11.0, accuracy: 1e-9)
        XCTAssertEqual(r.persistenceBaselineError ?? 0, 53.0 / 11.0, accuracy: 1e-9)
        XCTAssertEqual(r.persistenceSkill ?? 0, 1 - 43.0 / 53.0, accuracy: 1e-9)
    }

    /// Ordering is load-bearing: the baseline compares each truth with the one
    /// before it, so unsorted input would measure how jumbled the array is.
    func testPairsAreSortedOldestFirstWhateverTheStoreReturns() {
        let shuffled = [outcome(125, 120, day: 5), outcome(122, 118, day: 1),
                        outcome(130, 126, day: 9), outcome(121, 119, day: 3)]
        let r = ModelAccuracy.reports(from: shuffled)[0]
        XCTAssertEqual(r.pairs.map(\.actual), [118, 119, 120, 126])
    }

    // MARK: - Bias versus scatter

    func testAConsistentLeanIsNamedAsFixableAndSeparatedFromScatter() {
        let r = ModelAccuracy.workedExample()
        XCTAssertEqual(r.n, 12)
        XCTAssertEqual(r.overPredictions, 12)
        XCTAssertEqual(r.typicalError ?? 0, 4, accuracy: 1e-9)
        XCTAssertEqual(r.bias ?? 0, 4, accuracy: 1e-9)
        XCTAssertTrue(r.biasIsBeyondChance)
        // Scatter is what would remain after correcting the offset — a
        // different, smaller quantity than the error itself.
        XCTAssertNotNil(r.scatterAroundBias)
        XCTAssertLessThan(r.scatterAroundBias ?? 99, r.typicalError ?? 0)
        guard case .leans(_, let high, _) = r.reading else {
            return XCTFail("expected .leans, got \(r.reading)")
        }
        XCTAssertTrue(high)
        XCTAssertTrue(r.sentence.contains("too high"), r.sentence)
    }

    /// The worked example is what a reader with nothing yet is shown, so it has
    /// to survive every gate it teaches — and it must not be mistaken for data.
    func testTheWorkedExampleClearsEveryThresholdItDemonstrates() {
        let r = ModelAccuracy.workedExample()
        XCTAssertGreaterThanOrEqual(r.n, CalibrationReport.minimumForSkill)
        XCTAssertNotNil(r.typicalError)
        XCTAssertNotNil(r.bias)
        XCTAssertNotNil(r.persistenceSkill)
        // Invented, so it is deterministic and never varies between launches.
        XCTAssertEqual(ModelAccuracy.workedExample(), ModelAccuracy.workedExample())
    }

    // MARK: - Pooling across model versions

    func testPairsFromTwoModelVersionsAreFlaggedRatherThanQuietlyPooled() {
        let mixed = [outcome(128, 121, day: 0, version: "bp-estimator-v1"),
                     outcome(126, 122, day: 1, version: "bp-estimator-v2")]
        let r = ModelAccuracy.reports(from: mixed)[0]
        XCTAssertEqual(r.modelVersions.count, 2)
        XCTAssertNotNil(r.comparabilityWarning)
        let single = report(errors: [2, 1], actuals: [120, 121])
        XCTAssertNil(single.comparabilityWarning)
    }

    // MARK: - The ledger

    /// Rule 7's spirit: every card appears, whatever it has. A card missing
    /// from this screen is indistinguishable from a card that never existed.
    func testEveryCardGetsARowEvenWithNothingToGrade() {
        let entries = ModelAccuracy.ledger(outcomes: [], verdicts: [])
        XCTAssertEqual(entries.count, InsightID.allCases.count)
        XCTAssertEqual(Set(entries.map(\.insightID)), Set(InsightID.allCases))
        XCTAssertTrue(entries.allSatisfy { $0.evidence == .selfDefined })
        XCTAssertTrue(entries.allSatisfy { !$0.whatWouldMakeItGradable.isEmpty })
    }

    func testMeasuredCardsSortAheadOfRatedOnesAheadOfUngradableOnes() {
        let entries = ModelAccuracy.ledger(
            outcomes: (0..<6).map { outcome(125, 120, day: $0) },
            verdicts: [(.sleep, .accurate), (.sleep, .inaccurate)],
            titles: [.bloodPressure: "Blood pressure", .sleep: "Sleep"])
        XCTAssertEqual(entries.first?.insightID, .bloodPressure)
        XCTAssertEqual(entries.first?.evidence, .externalTruth)
        XCTAssertEqual(entries.first?.title, "Blood pressure")
        XCTAssertEqual(entries[1].insightID, .sleep)
        XCTAssertEqual(entries[1].evidence, .readerVerdict)
        XCTAssertTrue(entries.dropFirst(2).allSatisfy { $0.evidence == .selfDefined })
    }

    /// Systolic and diastolic are two predictions, not one — pooling their
    /// errors would average two different quantities.
    func testEachMetricGetsItsOwnReport() {
        let outcomes = (0..<6).flatMap { day in
            [outcome(125, 120, day: day),
             outcome(82, 78, day: day, metric: .bloodPressureDiastolic)]
        }
        let entry = ModelAccuracy.ledger(outcomes: outcomes, verdicts: [])
            .first { $0.insightID == .bloodPressure }
        XCTAssertEqual(entry?.reports.count, 2)
        XCTAssertEqual(entry?.gradedPairs, 12)
        XCTAssertEqual(Set(entry?.reports.map(\.metric) ?? []),
                       [.bloodPressureSystolic, .bloodPressureDiastolic])
    }

    /// Thumbs are agreement, not accuracy, and a rate out of three is a rate
    /// out of nothing.
    func testAgreementRateIsWithheldUntilThereAreEnoughRatings() {
        XCTAssertNil(VerdictTally(accurate: 2, inaccurate: 1).agreement)
        XCTAssertNotNil(VerdictTally(accurate: 2, inaccurate: 1).gate.sentence)
        XCTAssertEqual(VerdictTally(accurate: 8, inaccurate: 2).agreement ?? 0, 0.8, accuracy: 1e-9)
        XCTAssertNil(VerdictTally(accurate: 8, inaccurate: 2).gate.sentence)   // met gates say nothing
    }

    /// Stored score days are context and must never become an accuracy figure:
    /// a card can be scored every day for a year and still have nothing
    /// checking it.
    func testScoredDaysNeverBecomeEvidence() {
        let entries = ModelAccuracy.ledger(outcomes: [], verdicts: [],
                                           scoredDays: [.readiness: 365])
        let readiness = entries.first { $0.insightID == .readiness }
        XCTAssertEqual(readiness?.scoredDays, 365)
        XCTAssertEqual(readiness?.evidence, .selfDefined)
        XCTAssertEqual(readiness?.gradedPairs, 0)
    }

    // MARK: - Arithmetic

    func testMedianHandlesBothParities() {
        XCTAssertEqual(CalibrationReport.median([3, 1, 2]), 2)
        XCTAssertEqual(CalibrationReport.median([4, 1, 3, 2]), 2.5)
        XCTAssertEqual(CalibrationReport.median([]), 0)
    }

    func testBinomialCoefficients() {
        XCTAssertEqual(CalibrationReport.binomial(8, 0), 1, accuracy: 1e-9)
        XCTAssertEqual(CalibrationReport.binomial(8, 4), 70, accuracy: 1e-9)
        XCTAssertEqual(CalibrationReport.binomial(12, 5), 792, accuracy: 1e-9)
        XCTAssertEqual(CalibrationReport.binomial(5, 9), 0, accuracy: 1e-9)
    }
}
