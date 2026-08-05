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
}
