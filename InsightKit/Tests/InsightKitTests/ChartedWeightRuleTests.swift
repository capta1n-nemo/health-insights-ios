import XCTest
@testable import InsightKit

/// **Standing rule 4, enforced: everything a card charts carries a weight, or
/// says why it cannot.**
///
/// Backlog `G-check-1`. Of the reader's rules that have an enforceable shape,
/// rule 4 was the last one held by memory alone. Rule 3 has a `verify.sh` lint,
/// rule 9 has a non-optional exhaustive switch, rule 10 has
/// `DerivedFactorIdentityTests`, rule 11 has two checks. Rule 4 — everything a
/// card *charts* — had nothing, even though the convention it enforces is
/// already written out at the contribution sites (`HeartAgeAnalyser
/// .contributors`, `MetabolismInsight`'s logged-intake row).
///
/// ## What a "weight" is, and why zero is allowed
///
/// A `MetricContribution` is emitted by the scoring code at the point the
/// component is built, and it is what the detail screen charts. A weight above
/// zero is the rule satisfied outright. A weight of **zero is legitimate** —
/// Fitness charts five signals it does not score, Readiness eleven — but it is
/// only legitimate as a *stated decision*. The convention the whole app already
/// uses for that is an em-dash clause on the row:
///
///     "2,100 kcal a day logged — one of the two terms this card solves; it has
///      no share of the answer because it is not averaged into it"
///
/// A bare `"2,100 kcal"` at weight 0 is the failure this file exists for: on
/// screen it is indistinguishable from a signal the app forgot to weight, and
/// "we looked at this and decided it counts for nothing" is a completely
/// different statement from "we don't know what this counts for".
///
/// ## Why this is not `ScoreAttributionTests.testAnUnweightedRowAlwaysSaysWhy`
///
/// That test is the closest existing thing and it leaves three real gaps, each
/// of which is a way a rule-4 violation reaches the phone green:
///
/// 1. **It opens `guard result.score != nil else { continue }`.** A card with no
///    number still charts — that is rule 2 — and every one of its contributions
///    is therefore at weight 0 and completely unchecked. `ContributorsFixture`'s
///    own doc comment records the last time a `guard … else { continue }` in
///    that file silently skipped two whole cards.
/// 2. **It runs on one fixture.** A contribution that only appears when a signal
///    is *missing* — which is exactly when a model starts charting things it
///    cannot score — is never evaluated.
/// 3. **It reads `unweightedFactors`, not `contributors`.** That is the derived
///    view: it merges in `otherFactors` and sorts. The rule is about what is
///    charted, and what is charted is `contributors`.
///
/// ## The limit, stated rather than implied
///
/// This holds the rule for every signal a *model reports*. It cannot hold it for
/// a bespoke section in the app target that draws something the model never
/// emitted — the app target has no test target, and a hand-drawn `Chart {}` is
/// reachable only from `verify.sh`. Where a card charts a series it does not
/// report as a contribution, this file is silent and the reviewer is not.
final class ChartedWeightRuleTests: XCTestCase {

    private let now = TestClock.now

    /// The reason clause has to be a reason. The shortest one shipping today is
    /// `"not counted."` at twelve characters; a floor of eight with a space in
    /// it fails an empty tail or a single word without touching real copy.
    private let shortestUsefulReason = 8

    // MARK: - The scenarios
    //
    // **Degraded coverage is not a nice-to-have here, it is the point.** A model
    // charting a signal it cannot score is overwhelmingly a *thin data* branch:
    // the component had too few days, or the profile fact it needed is missing,
    // so it drops to weight 0 and the row has to explain itself. Running only
    // the full fixture tests the branch least likely to be wrong.

    private struct Scenario {
        let name: String
        let samples: [HealthMetricSample]
        let profile: UserHealthProfile
    }

    private func scenarios() -> [Scenario] {
        let full = ContributorsFixture.fullCoverage(now: now)
        let profile = ContributorsFixture.profile(now: now)
        var out = [
            Scenario(name: "full coverage", samples: full, profile: profile),
            // No date of birth and no sex. Every age-norm card falls back here.
            Scenario(name: "no grounding facts", samples: full,
                     profile: UserHealthProfile()),
            // Enough history for the daily cards, not enough for the seasonal
            // ones — Sustained Load and Gait change shape across this line.
            Scenario(name: "30 days only",
                     samples: ContributorsFixture.fullCoverage(days: 30, now: now),
                     profile: profile),
        ]
        // One signal at a time, chosen because each is read by several cards as
        // a *component* rather than as the subject — dropping it is what makes a
        // model renormalise over what is left and chart the rest unscored.
        for dropped: MetricType in [.heartRateVariabilityRMSSD, .restingHeartRate,
                                    .sleepDurationHours, .respiratoryRate,
                                    .vo2Max, .bodyFatPercentage] {
            out.append(Scenario(name: "without \(dropped.rawValue)",
                                samples: full.filter { $0.type != dropped },
                                profile: profile))
        }
        return out
    }

    // MARK: - The rule

    func testEveryChartedSignalCarriesAShareOrSaysWhyItCannot() {
        for scenario in scenarios() {
            for model in InsightEngine().models {
                let result = model.evaluate(samples: scenario.samples,
                                            profile: scenario.profile, now: now)
                for contribution in result.contributors where contribution.weight == 0 {
                    let detail = contribution.detail
                    let where_ = "\(result.id.rawValue) charts "
                        + "\(contribution.metric.rawValue) at weight 0 "
                        + "(\(scenario.name))"

                    guard let reason = detail.components(separatedBy: " — ").last,
                          detail.contains(" — ") else {
                        XCTFail("\(where_) with no stated reason — \"\(detail)\". "
                                    + "Rule 4: a charted signal carries a share or its "
                                    + "own row says why it cannot. Append an em-dash "
                                    + "clause, as HeartAgeAnalyser.contributors and "
                                    + "MetabolismInsight already do.")
                        continue
                    }
                    XCTAssertTrue(reason.count >= shortestUsefulReason
                                      && reason.contains(" "),
                                  "\(where_) and its reason is \"\(reason)\", which is "
                                      + "not one. The clause after the em dash has to "
                                      + "say why the zero is a decision.")
                }
            }
        }
    }

    /// The other half of "carries a weight": the number has to be a share.
    ///
    /// A negative or non-finite weight would draw a bar of nonsense length and
    /// would poison `normalised`, which divides by the total. Nothing produces
    /// one today; this is the cheap guard that keeps a `NaN` out of a chart the
    /// day a division goes wrong.
    func testAChartedShareIsAlwaysAFiniteNonNegativeFraction() {
        for scenario in scenarios() {
            for model in InsightEngine().models {
                let result = model.evaluate(samples: scenario.samples,
                                            profile: scenario.profile, now: now)
                for contribution in result.contributors {
                    XCTAssertTrue(contribution.weight.isFinite
                                      && contribution.weight >= 0
                                      && contribution.weight <= 1,
                                  "\(result.id.rawValue): \(contribution.metric.rawValue) "
                                      + "charts a share of \(contribution.weight) "
                                      + "(\(scenario.name)) — a share is a finite "
                                      + "fraction of one")
                }
            }
        }
    }

    // MARK: - The check itself is checked
    //
    // A lint nobody proved fires is a lint that does not. These two run the
    // same predicate the sweep above runs, over contributions written here to
    // be wrong, so a refactor that guts the assertion is caught by the file
    // that contains it.

    func testTheRuleRejectsABareZeroAndAcceptsAStatedOne() {
        XCTAssertFalse(statesItsReason(
            MetricContribution(metric: .dietaryEnergy, higherIsBetter: nil,
                               weight: 0, detail: "2,100 kcal")),
                       "a bare figure at weight 0 must fail the rule")
        XCTAssertFalse(statesItsReason(
            MetricContribution(metric: .dietaryEnergy, higherIsBetter: nil,
                               weight: 0, detail: "2,100 kcal — no")),
                       "a two-character clause is not a reason")
        XCTAssertTrue(statesItsReason(
            MetricContribution(metric: .dietaryEnergy, higherIsBetter: nil,
                               weight: 0, detail:
                                "2,100 kcal a day logged — one of the two terms this "
                                + "card solves, so it has no share of the answer")))
        // A weighted row needs no clause at all: the share is the answer.
        XCTAssertTrue(statesItsReason(
            MetricContribution(metric: .restingHeartRate, higherIsBetter: false,
                               weight: 0.4, detail: "58 bpm")))
    }

    private func statesItsReason(_ contribution: MetricContribution) -> Bool {
        guard contribution.weight == 0 else { return true }
        guard contribution.detail.contains(" — "),
              let reason = contribution.detail.components(separatedBy: " — ").last
        else { return false }
        return reason.count >= shortestUsefulReason && reason.contains(" ")
    }
}
