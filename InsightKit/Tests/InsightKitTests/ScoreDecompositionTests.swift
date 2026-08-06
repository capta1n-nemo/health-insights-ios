import XCTest
@testable import InsightKit

/// "Why is my score low" — backlog #38, the competitive scan's highest-value
/// idea and Oura's number one unfixable complaint.
///
/// **Half of these pin refusals rather than answers**, which is the design: only
/// a weighted average is linear in its parts, and the value of the section is
/// as much in declining to decompose a risk equation as in decomposing a blend.
final class ScoreDecompositionTests: XCTestCase {

    private func result(score: Double, weighting: ScoreWeighting,
                        contributors: [MetricContribution]) -> InsightResult {
        InsightResult(id: .readiness, title: "Readiness", primaryValue: score,
                      headline: "", score: score, confidence: .moderate,
                      explanation: "", drivers: [], unmetRequirements: [],
                      contributors: contributors, weighting: weighting)
    }

    private func contribution(_ metric: MetricType, weight: Double,
                              componentScore: Double?) -> MetricContribution {
        MetricContribution(metric: metric, higherIsBetter: true, weight: weight,
                           detail: "detail", componentScore: componentScore)
    }

    // MARK: - The arithmetic

    /// The counterfactual is exact for a weighted mean, because a weighted mean
    /// is linear in each term. Nothing is simulated and nothing re-run.
    func testTheCounterfactualIsExactForAWeightedAverage() throws {
        let out = try XCTUnwrap(ScoreDecomposition.evaluate(result(
            score: 62, weighting: .weightedAverage,
            contributors: [contribution(.restingHeartRate, weight: 0.5, componentScore: 40),
                           contribution(.sleepDurationHours, weight: 0.5, componentScore: 84)])))

        let worst = try XCTUnwrap(out.rows.first)
        XCTAssertEqual(worst.metric, .restingHeartRate)
        // (100 − 40) × 0.5 = 30 points available from the worst component.
        XCTAssertEqual(try XCTUnwrap(worst.headroom), 30, accuracy: 0.001)
        // And the two together account for the whole gap to 100.
        XCTAssertEqual(try XCTUnwrap(out.accountedFor), 38, accuracy: 0.001)
    }

    /// ⚠️ **Ordered by headroom, not by weight**, and this is the whole
    /// usefulness of the section. A reader asking why a score is low is asking
    /// what to move — and the heaviest component is very often already at its
    /// ceiling, so ordering by weight would put the longest bar on the thing
    /// there is least to gain from.
    func testItLeadsWithTheBiggestLeverRatherThanTheBiggestShare() throws {
        let out = try XCTUnwrap(ScoreDecomposition.evaluate(result(
            score: 88, weighting: .weightedAverage,
            contributors: [
                // Three quarters of the score, and perfect: nothing to gain.
                contribution(.restingHeartRate, weight: 0.75, componentScore: 100),
                // A quarter of the score, and poor: 12 points sitting there.
                contribution(.sleepDurationHours, weight: 0.25, componentScore: 52),
            ])))

        XCTAssertEqual(out.rows.first?.metric, .sleepDurationHours,
                       "the lever is the small share with room, not the big share at its ceiling")
        XCTAssertTrue(out.headline.contains("Sleep"), out.headline)
        XCTAssertTrue(try XCTUnwrap(out.rows.first).isLever)
        XCTAssertFalse(try XCTUnwrap(out.rows.last).isLever)
    }

    /// Everything at its ceiling is a real answer and must not read as an error.
    func testEverythingAtItsCeilingSaysSoRatherThanNamingAWorstComponent() throws {
        let out = try XCTUnwrap(ScoreDecomposition.evaluate(result(
            score: 100, weighting: .weightedAverage,
            contributors: [contribution(.restingHeartRate, weight: 0.5, componentScore: 100),
                           contribution(.sleepDurationHours, weight: 0.5, componentScore: 100)])))
        XCTAssertTrue(out.headline.contains("no single thing"), out.headline)
    }

    /// A weight-0 row is charted and carries none of the number. It must appear,
    /// separately, rather than being dropped or drawn as a lever with zero
    /// headroom.
    func testChartedButUnscoredRowsAreKeptApartFromTheLevers() throws {
        let out = try XCTUnwrap(ScoreDecomposition.evaluate(result(
            score: 70, weighting: .weightedAverage,
            contributors: [contribution(.restingHeartRate, weight: 1.0, componentScore: 70),
                           MetricContribution(metric: .dietaryEnergy, higherIsBetter: nil,
                                              weight: 0, detail: "tracked, not scored — no published figure")])))
        XCTAssertEqual(out.rows.count, 1)
        XCTAssertEqual(out.unscored.map(\.metric), [.dietaryEnergy])
    }

    // MARK: - The refusals

    /// ⚠️ **Only a weighted average is linear in its parts.** Every other
    /// weighting must decline, by name, rather than print a plausible number —
    /// and the refusal has to say *why*, because "we can't tell you" without a
    /// reason is indistinguishable from a bug.
    func testEveryNonLinearWeightingRefusesAndSaysWhy() throws {
        let nonLinear: [ScoreWeighting] = [
            .equation("SCORE2"), .fit("a regression through your own readings"),
            .singleMeasure("the ACC/AHA bands"), .measurement("your latest reading"),
            .worstOffender, .accumulative, .unstated,
        ]
        for weighting in nonLinear {
            let reason = try XCTUnwrap(ScoreDecomposition.refusalReason(for: weighting),
                                       "\(weighting) silently produced a counterfactual")
            XCTAssertGreaterThan(reason.count, 40,
                                 "\(weighting) refuses without explaining itself")

            let out = try XCTUnwrap(ScoreDecomposition.evaluate(result(
                score: 50, weighting: weighting,
                contributors: [contribution(.restingHeartRate, weight: 1, componentScore: 50)])))
            XCTAssertEqual(out.refusal, reason)
            XCTAssertNil(out.rows.first?.headroom,
                         "\(weighting) attached a headroom figure to a model that cannot support one")
            XCTAssertEqual(out.headline, reason,
                           "the refusal is what the section leads with")
        }
        XCTAssertNil(ScoreDecomposition.refusalReason(for: .weightedAverage))
    }

    /// The equation refusal points at the thing that *does* answer it properly,
    /// rather than leaving the reader at a dead end.
    func testTheEquationRefusalPointsAtTheAttributionThatDoesAnswerIt() throws {
        let reason = try XCTUnwrap(ScoreDecomposition.refusalReason(for: .equation("SCORE2")))
        XCTAssertTrue(reason.contains("SCORE2"), reason)
        XCTAssertTrue(reason.lowercased().contains("again")
                        || reason.lowercased().contains("attribution"),
                      "a refusal that does not name the alternative is a dead end: \(reason)")
    }

    /// A card with no score has nothing to explain, and asking is not an error.
    func testACardWithNoScoreDecomposesToNothing() {
        let unscored = InsightResult(
            id: .nutrition, title: "Nutrition", primaryValue: nil, headline: "",
            score: nil, confidence: .low, explanation: "", drivers: [],
            unmetRequirements: [])
        XCTAssertNil(ScoreDecomposition.evaluate(unscored))
    }

    // MARK: - The plumbing that made this possible

    /// ⚠️ `ScoreBlend.blend` used to compute every component's own 0–100 and
    /// drop all of them. That single discarded field is why no card could answer
    /// this question for the life of the app.
    func testTheBlendCarriesEachTermsOwnScoreThrough() throws {
        let blended = try XCTUnwrap(ScoreBlend.blend(
            primary: [.init(metric: .vo2Max, higherIsBetter: true, score: 41,
                            weight: 1, detail: "41")],
            supporting: []))
        let row = try XCTUnwrap(blended.contributions.first)
        XCTAssertEqual(row.componentScore, 41,
                       "the sub-score must survive the blend, or the decomposition has nothing to read")
        XCTAssertEqual(try XCTUnwrap(row.counterfactual()), 59, accuracy: 0.001)
    }

    /// And a supporting term fills in the value and baseline it was judged
    /// against, because that is exactly what defines it.
    func testASupportingTermCarriesItsBaselineAndDeparture() throws {
        let reading = VitalReading(metric: .restingHeartRate, value: 62, date: Date(),
                                   baseline: 55, zScore: 1.4, history: [54, 55, 56],
                                   sourceName: "Ring", isFresh: true)
        let term = try XCTUnwrap(ScoreBlend.supporting(reading, higherIsBetter: false))
        XCTAssertEqual(term.value, 62)
        XCTAssertEqual(term.baseline, 55)
        XCTAssertEqual(term.z, 1.4)
    }

    // MARK: - The models, on the full-coverage fixture (2026-08-06 sweep)

    /// ⚠️ **Every weighted row of every weighted-average card reports its own
    /// 0–100.** These six declare `.weightedAverage`, so their counterfactual
    /// is exact — and a weighted row without a sub-score on one of them is a
    /// model that computed the number and threw it away, which is precisely the
    /// defect the decomposition fields were added to end. The fixture default
    /// is the full 130 days on purpose: the guard on `score` *fails* rather
    /// than skips, because a skipped card is how Sustained Load and Gait once
    /// sat unchecked under the very sweep meant to prove them.
    func testEveryWeightedAverageCardReportsASubScoreOnEveryWeightedRow() {
        let now = Date()
        let samples = ContributorsFixture.fullCoverage(now: now)
        let profile = ContributorsFixture.profile(now: now)
        let models: [any InsightModel] = [
            ReadinessInsight(), SleepInsight(), HeartHealthInsight(),
            FitnessInsight(), BodyCompositionInsight(), NutritionInsight(),
        ]
        for model in models {
            let result = model.evaluate(samples: samples, profile: profile, now: now)
            XCTAssertNotNil(result.score,
                            "\(result.title) did not score on the full fixture — the assertions below never ran")
            let weighted = result.contributors.weighted
            XCTAssertFalse(weighted.isEmpty,
                           "\(result.title) scored with no weighted contributors to decompose")
            for row in weighted {
                XCTAssertNotNil(row.componentScore,
                                "\(result.title)'s \(row.metric.displayName) carries "
                                    + "\(Int((row.weight * 100).rounded()))% and reports no sub-score")
            }
        }
    }

    /// The three window-against-your-own-season models score through a curve
    /// over a *pooled* departure, so no channel owns a 0–100 and a
    /// componentScore there would license counterfactual arithmetic the curve
    /// cannot honour. What each channel genuinely holds — the recent window,
    /// the reference it was judged against, and the departure between them —
    /// must all be present instead.
    func testTheBaselineWindowModelsShowTheirWorkingAndDeclineASubScore() {
        let now = Date()
        let samples = ContributorsFixture.fullCoverage(now: now)
        let profile = ContributorsFixture.profile(now: now)
        let models: [any InsightModel] = [
            SustainedLoadInsight(), GaitInsight(), MentalHealthInsight(),
        ]
        for model in models {
            let result = model.evaluate(samples: samples, profile: profile, now: now)
            XCTAssertNotNil(result.score,
                            "\(result.title) did not score on the full fixture")
            let weighted = result.contributors.weighted
            XCTAssertFalse(weighted.isEmpty,
                           "\(result.title) scored with no weighted contributors")
            for row in weighted {
                XCTAssertNil(row.componentScore,
                             "\(result.title)'s \(row.metric.displayName) claims a per-channel 0–100 its pooled curve cannot support")
                XCTAssertNotNil(row.value,
                                "\(result.title)'s \(row.metric.displayName) hides its recent window")
                XCTAssertNotNil(row.baseline,
                                "\(result.title)'s \(row.metric.displayName) hides what it was judged against")
                XCTAssertNotNil(row.z,
                                "\(result.title)'s \(row.metric.displayName) hides its departure")
            }
        }
    }

    /// ⚠️ Energy feeds its reservoir level into every blend term because the
    /// blend's score is discarded there — and before `scoreIsOwn` that level
    /// came out of the blend as every term's `componentScore`, telling the
    /// reader each input had scored exactly what the card did. The reservoir
    /// terms must report **nil**, the honest "this model has not been taught
    /// to say".
    func testEnergysReservoirLevelNeverPosesAsATermsOwnScore() {
        let now = Date()
        let result = EnergyInsight().evaluate(
            samples: ContributorsFixture.fullCoverage(now: now),
            profile: ContributorsFixture.profile(now: now), now: now)
        // The two terms the fixture is guaranteed to charge and drain through.
        for metric in [MetricType.sleepDurationHours, .activeEnergyBurned] {
            let row = result.contributors.first { $0.metric == metric }
            XCTAssertNotNil(row, "Energy lost its \(metric.displayName) term on the full fixture")
            XCTAssertNil(row?.componentScore,
                         "Energy's \(metric.displayName) reports the whole reservoir level as its own sub-score")
        }
    }

    /// A biological-age marker's own answer is an *age equivalent*, not a
    /// 0–100 — squeezing one into `componentScore` would invent the very
    /// calibration the card refuses. The observed reading, though, is the one
    /// number every marker genuinely holds, and each weighted row must show it.
    func testBiologicalAgeMarkersCarryTheirReadingAndNoInventedSubScore() {
        let now = Date()
        let result = BiologicalAgeInsight().evaluate(
            samples: ContributorsFixture.fullCoverage(now: now),
            profile: ContributorsFixture.profile(now: now), now: now)
        let weighted = result.contributors.weighted
        XCTAssertFalse(weighted.isEmpty,
                       "Biological age found no markers on the full fixture")
        for row in weighted {
            XCTAssertNil(row.componentScore,
                         "\(row.metric.displayName) claims a 0–100 where the marker's own answer is an age")
            XCTAssertNotNil(row.value,
                            "\(row.metric.displayName) hides the reading its age equivalent came from")
        }
    }
}
