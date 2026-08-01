import XCTest
@testable import InsightKit

private let attributionNow = Date(timeIntervalSince1970: 1_700_000_000)
private func attributionDay(_ i: Int) -> Date {
    attributionNow.addingTimeInterval(-Double(i) * 86_400)
}

/// How each card divides its number between its inputs.
///
/// Four cards said **"Not a weighted average"** until 2026-08-01, and on three
/// of them it was false rather than merely unhelpful — the shares existed and
/// nobody had computed them. These tests pin the arithmetic that replaced it,
/// and, more importantly, the two claims the copy makes about it: that the
/// shares account for the whole number, and that a factor nobody can change is
/// marked as one.
final class ScoreAttributionTests: XCTestCase {

    // MARK: - The shared shape

    func testFactorsNormaliseToOne() {
        let factors: [ScoreFactor] = [
            .init(source: .derived, name: "A", weight: 2, detail: "", isModifiable: true),
            .init(source: .derived, name: "B", weight: 1, detail: "", isModifiable: true),
            .init(source: .derived, name: "C", weight: 0, detail: "", isModifiable: true)
        ]
        let out = factors.normalised
        XCTAssertEqual(out.count, 2, "a zero share is not a bar")
        XCTAssertEqual(out.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
        XCTAssertEqual(out.first?.name, "A", "heaviest first")
    }

    func testNormalisingNothingIsEmptyRatherThanADivisionByZero() {
        let allZero: [ScoreFactor] = [
            .init(source: .derived, name: "A", weight: 0, detail: "", isModifiable: true)
        ]
        XCTAssertTrue(allZero.normalised.isEmpty)
    }

    /// The same refusal `[MetricContribution].weightingPreview` makes: ties are
    /// broken by name, so on a tie the first is not the largest.
    func testThePreviewRefusesASuperlativeOnATie() {
        let tied: [ScoreFactor] = [
            .init(source: .derived, name: "A", weight: 0.4, detail: "", isModifiable: true),
            .init(source: .derived, name: "B", weight: 0.4, detail: "", isModifiable: true),
            .init(source: .derived, name: "C", weight: 0.2, detail: "", isModifiable: true)
        ]
        let preview = tied.weightingPreview ?? ""
        XCTAssertFalse(preview.contains("carries the most"), preview)
        XCTAssertTrue(preview.contains("2 inputs lead jointly"), preview)
    }

    /// Metric shares and non-metric shares are shares of **one** number. Merged
    /// without a shared renormalisation they would each sum to 1 and the card
    /// would draw two 100%s.
    func testMetricAndNonMetricSharesAreRenormalisedTogether() {
        let result = InsightResult(
            id: .cardiovascularRisk, title: "", primaryValue: 5, headline: "",
            score: 50, confidence: .moderate, explanation: "", drivers: [],
            unmetRequirements: [],
            contributors: [.init(metric: .bloodPressureSystolic, higherIsBetter: false,
                                 weight: 0.25, detail: "")],
            weighting: .equation("SCORE2"),
            otherFactors: [.init(source: .grounding(.dateOfBirth), name: "Age and sex",
                                 weight: 0.75, detail: "", isModifiable: false)])
        XCTAssertEqual(result.weightedFactors.count, 2)
        XCTAssertEqual(result.weightedFactors.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
        XCTAssertEqual(result.weightedFactors.first?.name, "Age and sex")
    }

    /// "Charted, not scored" and "carries none of the number" are both here, and
    /// a row missing from either would say the app never looked.
    func testUnweightedFactorsCarryBothKinds() {
        let result = InsightResult(
            id: .cardiovascularRisk, title: "", primaryValue: 5, headline: "",
            score: 50, confidence: .moderate, explanation: "", drivers: [],
            unmetRequirements: [],
            contributors: [
                .init(metric: .bloodPressureSystolic, higherIsBetter: false,
                      weight: 1, detail: ""),
                .init(metric: .vo2Max, higherIsBetter: true, weight: 0, detail: "")
            ],
            weighting: .equation("SCORE2"),
            otherFactors: [.init(source: .grounding(.currentSmoker), name: "Smoking",
                                 weight: 0, detail: "non-smoker", isModifiable: true)])
        let names = result.unweightedFactors.map(\.name)
        XCTAssertTrue(names.contains("Smoking"), "\(names)")
        XCTAssertTrue(names.contains(MetricType.vo2Max.displayName), "\(names)")
        XCTAssertFalse(names.contains(MetricType.bloodPressureSystolic.displayName))
    }

    /// A card that hasn't stated a basis must not have one inferred for it. The
    /// default is silence, so a new insight is honest before anyone touches it.
    func testTheDefaultBasisIsSilence() {
        let result = InsightResult(
            id: .energy, title: "", primaryValue: nil, headline: "", score: nil,
            confidence: .low, explanation: "", drivers: [], unmetRequirements: [])
        XCTAssertEqual(result.weighting, .unstated)
        XCTAssertFalse(result.weighting.carriesShares)
    }

    /// Every basis has to say something specific. The generic sentence is what
    /// this whole change replaced, so none of them may fall back to it.
    func testEveryBasisExplainsItselfDistinctly() {
        let bases: [ScoreWeighting] = [
            .weightedAverage, .singleMeasure("a published range"),
            .equation("SCORE2"), .fit("your own readings"),
            .measurement("A cuff reading."), .worstOffender, .unstated
        ]
        let explanations = bases.map(\.explanation)
        XCTAssertEqual(Set(explanations).count, bases.count,
                       "two bases share a sentence, so one of them is wrong")
        for text in explanations {
            XCTAssertGreaterThan(text.count, 60, text)
            XCTAssertFalse(text.contains("*"),
                           "this reaches SwiftUI as a String variable, so an "
                               + "asterisk renders as an asterisk: \(text)")
        }
    }

    // MARK: - Heart Attack & Stroke Risk

    private func riskSubject(systolic: Double = 145, smoker: Bool = true,
                             diabetes: Bool = false,
                             totalChol: Double = 6.2,
                             hdl: Double = 1.0) -> HeartAgeModel.Subject {
        .init(sex: .male, race: .whiteOrOther, region: .low, systolicBP: systolic,
              totalCholesterolMmol: totalChol, hdlCholesterolMmol: hdl,
              isSmoker: smoker, hasDiabetes: diabetes, treatedForBP: false)
    }

    func testRiskSharesAccountForTheWholeNumber() {
        let factors = RiskAttribution.factors(
            engines: [.score2, .ascvd], subject: riskSubject(), age: 55,
            cholesterolAssumed: false)
        XCTAssertEqual(factors.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
        XCTAssertTrue(factors.allSatisfy { $0.weight >= 0 },
                      "a negative share would have to draw a bar pointing backwards")
    }

    /// Age and sex are the one row a reader cannot act on, and they are usually
    /// the largest. Marking them is what stops the section reading as a list of
    /// things to work on with the biggest bar on the one nobody can move.
    func testAgeAndSexAreOneRowAndNotModifiable() {
        let factors = RiskAttribution.factors(
            engines: [.score2], subject: riskSubject(), age: 55,
            cholesterolAssumed: false)
        let fixed = factors.filter { !$0.isModifiable }
        XCTAssertEqual(fixed.count, 1, "exactly one non-modifiable row")
        XCTAssertEqual(fixed.first?.name, "Age and sex")
        XCTAssertGreaterThan(fixed.first?.weight ?? 0, 0)
    }

    /// The attribution has to move with the factor. A smoker's smoking carries
    /// a share; a non-smoker's carries none, and the row stays so "none" is
    /// distinguishable from "not looked at".
    func testSmokingCarriesAShareOnlyForASmoker() {
        let smoker = RiskAttribution.factors(
            engines: [.score2, .ascvd], subject: riskSubject(smoker: true), age: 55,
            cholesterolAssumed: false)
        let neither = RiskAttribution.factors(
            engines: [.score2, .ascvd], subject: riskSubject(smoker: false), age: 55,
            cholesterolAssumed: false)
        XCTAssertGreaterThan(smoker.first { $0.name == "Smoking" }?.weight ?? 0, 0.05)
        XCTAssertEqual(neither.first { $0.name == "Smoking" }?.weight, 0)
        let neitherRow = neither.first { $0.name == "Smoking" }?.detail ?? ""
        XCTAssertTrue(neitherRow.hasPrefix("non-smoker"), neitherRow)
        // "Carrying none" and "not looked at" are opposite statements, and a
        // bare zero says the second.
        XCTAssertTrue(neitherRow.contains("carrying none of your risk"), neitherRow)
    }

    /// A factor already at the optimal value is carrying none of the risk, and
    /// that is a finding rather than an absence.
    func testAFactorAtOptimalCarriesNothing() {
        let factors = RiskAttribution.factors(
            engines: [.score2],
            subject: riskSubject(systolic: HeartAgeModel.OptimalReference.systolicBP),
            age: 55, cholesterolAssumed: false)
        let bp = factors.first { $0.metric == .bloodPressureSystolic }
        XCTAssertEqual(bp?.weight ?? -1, 0, accuracy: 1e-9)
        XCTAssertNotNil(bp, "the row stays: 'carrying none' is not 'not looked at'")
    }

    /// Raising one factor and nothing else must raise that factor's share. This
    /// is the check that the attribution is of the equation rather than of a
    /// table somebody typed.
    func testAWorseFactorTakesALargerShare() {
        let mild = RiskAttribution.factors(
            engines: [.score2, .ascvd], subject: riskSubject(systolic: 130), age: 55,
            cholesterolAssumed: false)
        let severe = RiskAttribution.factors(
            engines: [.score2, .ascvd], subject: riskSubject(systolic: 175), age: 55,
            cholesterolAssumed: false)
        XCTAssertGreaterThan(severe.first { $0.metric == .bloodPressureSystolic }?.weight ?? 0,
                             mild.first { $0.metric == .bloodPressureSystolic }?.weight ?? 0)
    }

    func testNoEnginesMeansNoAttributionRatherThanAnInventedOne() {
        XCTAssertTrue(RiskAttribution.factors(engines: [], subject: riskSubject(),
                                              age: 55, cholesterolAssumed: false).isEmpty)
    }

    /// An assumed cholesterol still drives the equation, so it still carries a
    /// share — and the row has to say it was assumed, because that share is the
    /// strongest argument for a blood test the card can make.
    func testAnAssumedCholesterolSaysSoOnItsOwnRow() {
        let factors = RiskAttribution.factors(
            engines: [.score2], subject: riskSubject(), age: 55,
            cholesterolAssumed: true)
        let chol = factors.first { $0.name == "Total cholesterol" }
        XCTAssertTrue(chol?.detail.contains("assumed average") ?? false, chol?.detail ?? "")
    }

    // MARK: - Substance Impact

    /// `effectSize` is `|delta| / baselineSD`, so the spread is what sets it.
    private func effect(_ metric: MetricType, effectSize: Double) -> SubstanceResponseAnalyzer.MetricEffect {
        .init(metric: metric, baseline: 60, afterUse: 66, deltaAbsolute: 6,
              deltaPercent: 10, affectedNights: 5, baselineNights: 20,
              isAdverse: true, baselineSD: 6 / effectSize)
    }

    /// The combiner is homogeneous of degree one in the penalties, so the parts
    /// sum to the whole exactly — no normalisation, no approximation.
    func testPenaltySharesAccountForTheDeductionExactly() {
        let effects = [effect(.restingHeartRate, effectSize: 1.6),
                       effect(.heartRateVariabilityRMSSD, effectSize: 0.8),
                       effect(.sleepDurationHours, effectSize: 0.4)]
        let load = 30.0
        let shares = SubstanceResponseAnalyzer.penaltyShares(load: load, effects: effects)
        XCTAssertEqual(shares.count, effects.count + 1, "the load is a penalty of its own")
        XCTAssertEqual(shares.reduce(0, +), 1, accuracy: 1e-9)

        // And the shares really are shares of what came off the score.
        let score = SubstanceResponseAnalyzer.score(load: load, effects: effects) ?? 0
        let deduction = 100 - score
        XCTAssertGreaterThan(deduction, 0)
        let worst = shares.max() ?? 0
        XCTAssertEqual(worst * deduction,
                       SubstanceResponseAnalyzer.severity(effects[0]), accuracy: 1e-6,
                       "the largest response contributes itself, whole")
    }

    func testTheWorstResponseTakesTheLargestShare() {
        let effects = [effect(.heartRateVariabilityRMSSD, effectSize: 0.5),
                       effect(.restingHeartRate, effectSize: 2.0)]
        let shares = SubstanceResponseAnalyzer.penaltyShares(load: 5, effects: effects)
        XCTAssertGreaterThan(shares[1], shares[0])
    }

    /// A fortnight of heavy use with nothing measurable yet is the load's number
    /// outright, and the card has to be able to say so.
    func testTheLoadCanBeTheWholeOfIt() {
        let shares = SubstanceResponseAnalyzer.penaltyShares(load: 60, effects: [])
        XCTAssertEqual(shares, [1])
    }

    func testNothingAdverseDividesNothing() {
        XCTAssertEqual(SubstanceResponseAnalyzer.penaltyShares(load: 0, effects: []), [0])
    }

    // MARK: The dial is measured impact, not usage (user direction, 2026-08-01)

    /// A benign response: measured properly, and it barely moved.
    private func benign(_ metric: MetricType) -> SubstanceResponseAnalyzer.MetricEffect {
        .init(metric: metric, baseline: 60, afterUse: 60.6, deltaAbsolute: 0.6,
              deltaPercent: 1, affectedNights: 5, baselineNights: 20,
              isAdverse: true, baselineSD: 6)   // effect size 0.1 — noise
    }

    /// The complaint this closes: daily use saturated the load, the load
    /// entered the pool at full strength, and the dial read 0 whatever the
    /// body did. With the response well-measured and mild, exposure alone is
    /// capped at one band's worth and the dial has to say "mild", not "worst
    /// possible".
    func testAMeasuredMildResponseIsNotScoredZeroByUsageAlone() throws {
        let effects = [benign(.restingHeartRate), benign(.heartRateVariabilityRMSSD),
                       benign(.sleepDurationHours)]
        let heavy = try XCTUnwrap(SubstanceResponseAnalyzer.score(load: 100, effects: effects))
        XCTAssertGreaterThan(heavy, 60,
                             "a well-measured mild response must dominate a saturated load")
        // And the same usage with a genuinely large measured response still
        // scores hard — the cap frees the measurement, it does not soften it.
        let severe = [effect(.restingHeartRate, effectSize: 2.0),
                      benign(.heartRateVariabilityRMSSD), benign(.sleepDurationHours)]
        let bad = try XCTUnwrap(SubstanceResponseAnalyzer.score(load: 100, effects: severe))
        XCTAssertLessThan(bad, 25, "a full-strength measured response is still the finding")
        XCTAssertLessThan(bad, heavy)
    }

    /// With nothing measured, exposure is the only evidence there is, and a
    /// heavy fortnight must still read as one — the cap needs measurement to
    /// earn it.
    func testAnUnmeasuredHeavyFortnightStillScoresLow() throws {
        let score = try XCTUnwrap(SubstanceResponseAnalyzer.score(load: 100, effects: []))
        XCTAssertEqual(score, 0)
        // One weakly-paired signal discounts only a third of the way.
        let one = try XCTUnwrap(SubstanceResponseAnalyzer.score(
            load: 100, effects: [benign(.restingHeartRate)]))
        XCTAssertLessThan(one, 40, "one measured signal must not fully discount exposure")
    }

    /// The shares and the score keep drawing from one pool after the cap, so
    /// the Euler property survives it.
    func testSharesStillAccountForTheDeductionWithTheCapApplied() throws {
        let effects = [benign(.restingHeartRate), benign(.heartRateVariabilityRMSSD),
                       benign(.sleepDurationHours)]
        let shares = SubstanceResponseAnalyzer.penaltyShares(load: 100, effects: effects)
        XCTAssertEqual(shares.reduce(0, +), 1, accuracy: 1e-9)
        let score = try XCTUnwrap(SubstanceResponseAnalyzer.score(load: 100, effects: effects))
        let deduction = 100 - score
        // The capped load is the worst penalty here and contributes itself.
        let worstShare = try XCTUnwrap(shares.max())
        XCTAssertEqual(worstShare * deduction,
                       SubstanceResponseAnalyzer.exposureCeilingWhenMeasured,
                       accuracy: 1e-6)
    }

    // MARK: - Body Composition

    /// Body fat is the whole number where a scale reports it — which is what
    /// "Not a weighted average" was denying.
    func testBodyFatCarriesTheWholeDialWhenAScaleReportsIt() {
        let dial = BodyCompositionInsight.score(bodyFat: 18, bmi: 23, age: 35, sex: .male)
        XCTAssertEqual(dial?.metric, .bodyFatPercentage)
    }

    /// BMI is the fallback, and it attributes to body mass: height is the only
    /// thing on this card that cannot change between two readings, so it is what
    /// the score is measured against rather than something moving it.
    func testTheBMIFallbackAttributesToBodyMassRatherThanHeight() {
        let dial = BodyCompositionInsight.score(bodyFat: nil, bmi: 23, age: 35, sex: .male)
        XCTAssertEqual(dial?.metric, .bodyMass)
        XCTAssertNil(BodyCompositionInsight.score(bodyFat: nil, bmi: nil, age: 35, sex: .male))
    }

    // MARK: - Blood pressure's three routes

    private func bpSamples(lastReadingDaysAgo: Double, readings: Int = 6,
                           systolic: Double = 128, diastolic: Double = 82)
        -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        for i in 0..<readings {
            let date = attributionNow.addingTimeInterval(
                -(lastReadingDaysAgo + Double(i) * 2) * 86_400)
            out.append(.init(type: .bloodPressureSystolic, value: systolic + Double(i),
                             start: date, source: .manual))
            out.append(.init(type: .bloodPressureDiastolic, value: diastolic + Double(i),
                             start: date, source: .manual))
            out.append(.init(type: .restingHeartRate, value: 56 + Double(i) * 1.5,
                             start: date, source: .appleHealth))
            // Deliberately not collinear with resting heart rate: two predictors
            // on a line make `bivariateFit`'s normal equations degenerate, it
            // returns nil, and the estimate silently drops to the
            // resting-HR-only fallback — which is a real behaviour with its own
            // row note, and not the two-predictor path this exercises.
            out.append(.init(type: .heartRateVariabilityRMSSD,
                             value: 52 - Double(i) + Double((i * 7) % 5) * 2.5,
                             start: date, source: .appleHealth))
        }
        // Today's autonomic readings, which are what the estimate is *of*.
        for i in 0..<3 {
            out.append(.init(type: .restingHeartRate, value: 61,
                             start: attributionDay(i), source: .appleHealth))
            out.append(.init(type: .heartRateVariabilityRMSSD, value: 44,
                             start: attributionDay(i), source: .appleHealth))
        }
        return out
    }

    /// A reading from the last day is the answer, and nothing modelled beats it.
    func testAFreshCuffReadingIsTheDialAndIsNotWeighted() throws {
        let result = BloodPressureInsight().evaluate(
            samples: bpSamples(lastReadingDaysAgo: 0.2), profile: UserHealthProfile(),
            now: attributionNow)
        guard case .singleMeasure(let against) = result.weighting else {
            return XCTFail("expected a published-range measure, got \(result.weighting)")
        }
        XCTAssertTrue(against.contains("ACC/AHA"), against)
        XCTAssertTrue(against.contains("last 24 hours"), against)
        XCTAssertEqual(try XCTUnwrap(result.score),
                       BloodPressureEstimator.score(systolic: 128, diastolic: 82),
                       accuracy: 1e-9)

        // Both numbers set the category, so both carry a share of it, and the
        // higher one along its own axis carries more.
        let weighted = result.weightedFactors
        XCTAssertEqual(weighted.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
        XCTAssertEqual(Set(weighted.compactMap(\.metric)),
                       [.bloodPressureSystolic, .bloodPressureDiastolic])
    }

    /// Both numbers always carry a share, including on the best reading someone
    /// has ever taken. A leave-one-out against 120/80 was the obvious
    /// alternative and measures the *deficit*, so a reader at 112/72 would see
    /// two empty rows.
    func testAPerfectReadingStillDividesBetweenItsTwoNumbers() {
        let shares = BloodPressureEstimator.readingShares(systolic: 112, diastolic: 72)
        XCTAssertGreaterThan(shares.systolic, 0)
        XCTAssertGreaterThan(shares.diastolic, 0)
        XCTAssertEqual(shares.systolic + shares.diastolic, 1, accuracy: 1e-9)

        // And a systolic far along its own axis beside an ordinary diastolic
        // carries the larger share.
        let lopsided = BloodPressureEstimator.readingShares(systolic: 175, diastolic: 78)
        XCTAssertGreaterThan(lopsided.systolic, lopsided.diastolic)
    }

    /// Past a day the estimate takes over — it is the only one of the three
    /// routes that is a statement about *now*. It used to rank below the recent
    /// average, which answers a different question and cannot move when the
    /// person does.
    func testPastADayTheDialShiftsToTheExperimentalEstimate() {
        let result = BloodPressureInsight().evaluate(
            samples: bpSamples(lastReadingDaysAgo: 3), profile: UserHealthProfile(),
            now: attributionNow)
        guard case .fit = result.weighting else {
            return XCTFail("expected a fit, got \(result.weighting)")
        }
        XCTAssertEqual(result.confidence, .experimental)
        XCTAssertTrue(result.explanation.contains("over a day old"), result.explanation)

        // The dial is the estimate, not the average of the readings behind it.
        let trend = BloodPressureEstimator.recentTrend(from: bpSamples(lastReadingDaysAgo: 3),
                                                       now: attributionNow)
        let trendScore = trend.map {
            BloodPressureEstimator.score(systolic: $0.systolic, diastolic: $0.diastolic)
        }
        XCTAssertNotNil(trendScore)
        XCTAssertNotEqual(result.score ?? 0, trendScore ?? 0, accuracy: 1e-9)
    }

    /// On that route the two autonomic signals are what the number is made of,
    /// and their shares come from the fit rather than from a constant.
    func testTheEstimateRouteWeightsThePredictorsItActuallyUsed() {
        let result = BloodPressureInsight().evaluate(
            samples: bpSamples(lastReadingDaysAgo: 3), profile: UserHealthProfile(),
            now: attributionNow)
        let weighted = result.weightedFactors
        XCTAssertFalse(weighted.isEmpty)
        XCTAssertEqual(weighted.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
        let metrics = Set(weighted.compactMap(\.metric))
        XCTAssertTrue(metrics.contains(.restingHeartRate), "\(metrics)")
        // The cuff readings carry the level and today's autonomic readings carry
        // the nudge: the estimate is the person's own average plus a departure.
        // Both are in the number, which is why the estimate moves so little day
        // to day and why the cadence rule exists at all.
        XCTAssertTrue(metrics.contains(.bloodPressureSystolic), "\(metrics)")
        let cuffShare = weighted
            .filter { $0.metric == .bloodPressureSystolic || $0.metric == .bloodPressureDiastolic }
            .reduce(0) { $0 + $1.weight }
        XCTAssertEqual(cuffShare, 1 - SupportingSignal.collectiveShare, accuracy: 1e-9)
        // The rule the user set, in the form that survives every route: an input
        // either carries a share or says on its own row why it doesn't. A bare
        // zero under a section promising "everything carries a share, however
        // small" is the failure mode this replaces.
        for row in result.unweightedFactors {
            XCTAssertTrue(row.detail.contains(" — "),
                          "\(row.name) has no share and no reason: \(row.detail)")
        }
    }

    /// Every card, every unweighted row: a share or a stated reason.
    func testAnUnweightedRowAlwaysSaysWhy() {
        let samples = ContributorsFixture.fullCoverage(now: attributionNow)
        for model in InsightEngine().models {
            let result = model.evaluate(samples: samples,
                                        profile: ContributorsFixture.profile(now: attributionNow),
                                        now: attributionNow)
            guard result.score != nil else { continue }
            for row in result.unweightedFactors {
                XCTAssertTrue(row.detail.contains(" — "),
                              "\(model.id): \(row.name) carries no share and gives no "
                                  + "reason — \"\(row.detail)\"")
            }
        }
    }

    /// The floor: cuff readings and nothing to estimate from. Reached only when
    /// the estimate cannot be produced, which is the honest ordering.
    func testWithoutAnythingToEstimateFromTheRecentAverageStillHoldsTheDial() {
        let readingsOnly = bpSamples(lastReadingDaysAgo: 3).filter {
            $0.type == .bloodPressureSystolic || $0.type == .bloodPressureDiastolic
        }
        let result = BloodPressureInsight().evaluate(
            samples: readingsOnly, profile: UserHealthProfile(), now: attributionNow)
        XCTAssertNotNil(result.score)
        XCTAssertEqual(result.confidence, .moderate)
        guard case .singleMeasure(let against) = result.weighting else {
            return XCTFail("expected a published-range measure, got \(result.weighting)")
        }
        XCTAssertTrue(against.contains("average of"), against)
        XCTAssertEqual(result.weightedFactors.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
    }

    /// The predictor split is of the *departure* from the person's own mean, so
    /// a predictor sitting exactly on its mean is doing nothing to the estimate.
    func testAPredictorAtItsOwnMeanCarriesNothing() {
        let shares = BloodPressureEstimator.predictorShares(
            b1: 0.8, x1: 60, mean1: 60, b2: -0.3, x2: 40, mean2: 50)
        XCTAssertEqual(shares.restingHR, 0, accuracy: 1e-9)
        XCTAssertEqual(shares.hrv, 1, accuracy: 1e-9)
    }

    /// Both on their means: the estimate is exactly the mean and neither
    /// predictor moved it. Handing one the whole of nothing would draw a full
    /// bar under a signal doing nothing.
    func testTwoIdlePredictorsSplitEvenlyRatherThanOneTakingItAll() {
        let shares = BloodPressureEstimator.predictorShares(
            b1: 0.8, x1: 60, mean1: 60, b2: -0.3, x2: 50, mean2: 50)
        XCTAssertEqual(shares.restingHR, 0.5, accuracy: 1e-9)
        XCTAssertEqual(shares.hrv, 0.5, accuracy: 1e-9)
    }

    // MARK: - Energy

    /// The weights here were 0.6 / 0.25 / 0.15 — three constants written in the
    /// card that appear nowhere in the model, under a heading promising "the
    /// share each signal has of the score".
    func testEnergyWeightsComeFromTheModelsOwnTerms() {
        var samples: [HealthMetricSample] = []
        for i in 0..<14 {
            samples.append(.init(type: .sleepDurationHours, value: 7.5,
                                 start: attributionDay(i), source: .oura))
            samples.append(.init(type: .heartRateVariabilityRMSSD, value: 50,
                                 start: attributionDay(i), source: .oura))
            samples.append(.init(type: .restingHeartRate, value: 55,
                                 start: attributionDay(i), source: .oura))
        }
        // Today's work, and enough heart rate for the exertion term to exist.
        for hour in 0..<8 {
            samples.append(.init(type: .heartRate, value: hour < 4 ? 95 : 62,
                                 start: attributionNow.addingTimeInterval(-Double(hour) * 3600),
                                 source: .appleHealth))
        }
        samples.append(.init(type: .activeEnergyBurned, value: 400,
                             start: attributionNow.addingTimeInterval(-3600),
                             source: .appleHealth))

        let result = EnergyInsight().evaluate(samples: samples,
                                              profile: UserHealthProfile(),
                                              now: attributionNow)
        let weighted = result.contributors.weighted
        XCTAssertEqual(weighted.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
        XCTAssertTrue(weighted.contains { $0.metric == .heartRate },
                      "time above resting is a term of the model and reaches the "
                          + "reader as a driver line; it must carry its share too")
        // Not the three constants it used to report.
        XCTAssertFalse(weighted.contains { abs($0.weight - 0.6) < 1e-9 && $0.metric == .sleepDurationHours }
                        && weighted.count == 3,
                       "these look like the hand-written 0.6 / 0.25 / 0.15")
    }

    // MARK: - Sleep

    /// The card declared both absolute temperatures since the merge and read
    /// neither, so on a device reporting only an absolute the temperature term
    /// silently took its neutral 75 and the metric charted nowhere.
    func testSleepReadsAnAbsoluteTemperatureWhenNoDeviationIsReported() {
        var samples: [HealthMetricSample] = []
        for i in 0..<14 {
            samples.append(.init(type: .sleepDurationHours, value: 7.4,
                                 start: attributionDay(i), source: .whoop))
            // A run of ordinary nights, then a hot one.
            samples.append(.init(type: .skinTemperature, value: i == 0 ? 35.4 : 33.8,
                                 start: attributionDay(i), source: .whoop))
        }
        let result = SleepInsight().evaluate(samples: samples,
                                             profile: UserHealthProfile(),
                                             now: attributionNow)
        let charted = result.contributors.first { $0.metric == .skinTemperature }
        XCTAssertNotNil(charted, "the absolute temperature reached no section")
        XCTAssertEqual(charted?.weight ?? 0, 0.03, accuracy: 1e-9,
                       "it takes the temperature term's own weight")
        XCTAssertTrue(result.drivers.contains { $0.contains("from your normal") },
                      "\(result.drivers)")
    }

    /// And the deviation still wins where a device reports one, so the two are
    /// never both read — which would count one thermometer twice.
    func testADeviationIsPreferredAndTheAbsoluteDoesNotDoubleCount() {
        var samples: [HealthMetricSample] = []
        for i in 0..<14 {
            samples.append(.init(type: .sleepDurationHours, value: 7.4,
                                 start: attributionDay(i), source: .oura))
            samples.append(.init(type: .skinTemperature, value: 33.8,
                                 start: attributionDay(i), source: .oura))
            samples.append(.init(type: .skinTemperatureDeviation, value: 0.2,
                                 start: attributionDay(i), source: .oura))
        }
        let result = SleepInsight().evaluate(samples: samples,
                                             profile: UserHealthProfile(),
                                             now: attributionNow)
        let temperatures = result.contributors.filter {
            [.skinTemperature, .skinTemperatureDeviation, .bodyTemperature].contains($0.metric)
        }
        XCTAssertEqual(temperatures.count, 1, "one thermometer, one row")
        XCTAssertEqual(temperatures.first?.metric, .skinTemperatureDeviation)
    }

    // MARK: - Every card, on the same dataset

    /// The claim the section makes on every card at once: the shares it draws
    /// account for the whole of the number above them.
    func testEveryCardsSharesAccountForItsWholeNumber() {
        let samples = ContributorsFixture.fullCoverage(now: attributionNow)
        for model in InsightEngine().models {
            let result = model.evaluate(samples: samples,
                                        profile: ContributorsFixture.profile(now: attributionNow),
                                        now: attributionNow)
            let weighted = result.weightedFactors
            guard !weighted.isEmpty else { continue }
            XCTAssertEqual(weighted.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-6,
                           "\(model.id) draws shares that don't add up to its number")
            XCTAssertTrue(result.weighting.carriesShares,
                          "\(model.id) draws shares under a basis that says it has none")
        }
    }

    /// Nothing may go back to the state this session started in: a card with a
    /// number, contributors, and no statement of how the two relate.
    func testEveryScoringCardStatesHowItsNumberIsFormed() {
        let samples = ContributorsFixture.fullCoverage(now: attributionNow)
        for model in InsightEngine().models {
            let result = model.evaluate(samples: samples,
                                        profile: ContributorsFixture.profile(now: attributionNow),
                                        now: attributionNow)
            guard result.score != nil else { continue }
            XCTAssertNotEqual(result.weighting, .unstated,
                              "\(model.id) has a score and hasn't said how it is formed")
        }
    }
}
