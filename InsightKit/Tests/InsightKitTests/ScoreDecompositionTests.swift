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

    // MARK: - The floor, swept over the registry (backlog D25, 2026-08-07)

    /// ⚠️ **No weighted row anywhere reports a share and nothing else.**
    ///
    /// Every test above pins one model's answer or one model's refusal, which is
    /// exactly how four weighted sites sat for a month carrying a percentage and
    /// four nils: no test asked the question of the **registry**. This one does.
    ///
    /// It is deliberately the weakest claim that still catches the defect — a
    /// weighted row must carry either its own 0–100 or the reading it was built
    /// from. *Which* of those is right is the model's business, and the tests
    /// above decide it card by card; having neither is a card that cannot show
    /// its working at all, and that is what this refuses to let back in.
    ///
    /// ⚠️ **Written as an equality against a named exemption list, not as a
    /// blanket pass.** The first run of this sweep found a card the D25 audit
    /// had missed entirely — Energy, three weighted rows at 43%, 30% and 7%,
    /// each carrying a share and four nils. It is out of that session's scope
    /// and is a backlog row of its own. An `XCTSkip` or a quiet `continue` would
    /// hide it again; an equality means **fixing Energy fails this test**, which
    /// is the reminder to delete the exemption and close the row.
    func testNoWeightedRowReportsAShareAndNothingElse() {
        // Energy's terms are deliberately without a `componentScore` — the blend
        // discards its own score there and `scoreIsOwn` is false, pinned by
        // `testEnergysReservoirLevelNeverPosesAsATermsOwnScore`. That is correct
        // and is *not* what this records: the gap is `value`, the reading each
        // term was built from, which nothing has ever explained leaving out.
        let knownBare: Set<String> = ["Energy"]
        let now = Date()
        let samples = ContributorsFixture.fullCoverage(now: now)
        let profile = ContributorsFixture.profile(now: now)
        var scored = 0
        var bare: Set<String> = []
        for model in InsightEngine().models {
            let result = model.evaluate(samples: samples, profile: profile, now: now)
            guard result.score != nil else { continue }
            scored += 1
            for row in result.contributors.weighted
            where row.componentScore == nil && row.value == nil {
                bare.insert(result.title)
            }
        }
        XCTAssertEqual(bare, knownBare,
                       "cards whose weighted rows report a share and nothing else changed. "
                           + "Newly listed: \(bare.subtracting(knownBare).sorted()) — give each "
                           + "weighted row its own 0–100 or the reading it was built from. "
                           + "No longer listed: \(knownBare.subtracting(bare).sorted()) — fixed, "
                           + "so delete it from `knownBare` and close its backlog row.")
        // A sweep that silently stops sweeping reads as a pass. Same guard as
        // the fixture assertions above, for the same reason.
        XCTAssertGreaterThanOrEqual(scored, 10,
                                    "only \(scored) registered cards scored on the full "
                                        + "fixture, so this swept almost nothing")
    }

    /// The illness radar scores a **pooled** excess through one curve
    /// (`HealthWatchModel.score(excess:)`) and declares `.accumulative`, so it
    /// makes the same refusal as Sustained Load, Gait and Mental Health — and
    /// until D25 it made that refusal by carrying nothing at all, on seven
    /// weighted signals, while `Signal` held all three numbers the whole time.
    func testTheIllnessRadarShowsEachSignalsWindowBaselineAndDeparture() {
        let now = Date()
        let result = SymptomRadarInsight().evaluate(
            samples: ContributorsFixture.fullCoverage(now: now),
            profile: ContributorsFixture.profile(now: now), now: now)
        let weighted = result.contributors.weighted
        XCTAssertFalse(weighted.isEmpty, "the radar found no signals on the full fixture")
        for row in weighted {
            XCTAssertNil(row.componentScore,
                         "\(row.metric.displayName) claims a per-signal 0–100 the pooled curve cannot support")
            XCTAssertNotNil(row.value, "\(row.metric.displayName) hides its recent window")
            XCTAssertNotNil(row.baseline, "\(row.metric.displayName) hides what it was judged against")
            XCTAssertNotNil(row.z, "\(row.metric.displayName) hides its departure")
        }
    }

    /// Substance Impact's severity **is** each signal's own 0–100 on the card's
    /// own scale — the dial is `100 − deduction` and severity is what each
    /// signal put into that pool. It was computed and dropped.
    ///
    /// The counterfactual stays refused regardless: the card declares
    /// `.worstOffender`, and a pool set by its worst member is not linear in its
    /// parts even when every part has a number. That separation — a sub-score
    /// without a headroom — is the point of the test.
    func testSubstanceImpactReportsEachSignalsOwnScoreButStillRefusesACounterfactual() throws {
        // ⚠️ **The full-coverage fixture measures nothing here**, and a test
        // written against it passes vacuously — its series carry no response
        // tied to a logged night, so every severity is 0 and `weighted` is
        // empty. So this builds the response instead: ten logged nights at 58
        // against twenty clean ones averaging 54, which is deliberately a
        // *partial* response (about 1.4 SD). A saturating one would score the
        // row at exactly 0 and prove nothing about the field being real.
        let now = TestClock.now
        let useDays: Set<Int> = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]
        let events = useDays.map {
            SubstanceEvent(substance: .alcohol, timestamp: TestClock.hours(Double($0) * 24 + 6))
        }
        let samples = (0..<30).map { day in
            HealthMetricSample(type: .restingHeartRate,
                               value: useDays.contains(day) ? 58 : 50 + Double(day % 5) * 2,
                               start: TestClock.hours(Double(day) * 24), source: .oura)
        }
        let result = SubstanceResponseAnalyzer.insightResult(
            events: events, samples: samples, now: now)
        let weighted = result.contributors.weighted
        XCTAssertFalse(weighted.isEmpty, "the fixture measured no weighted response")
        for row in weighted {
            let score = try XCTUnwrap(row.componentScore,
                                      "\(row.metric.displayName) carries a share of the deduction and no sub-score")
            XCTAssertGreaterThan(score, 0, "\(row.metric.displayName) saturated — the fixture stopped being partial")
            XCTAssertLessThan(score, 100, "\(row.metric.displayName) took nothing off yet carries a share")
            // The after-use mean, the clean-night baseline, and the departure
            // between them — signed as measured, so a rise in resting heart
            // rate is positive whether or not a rise is welcome.
            XCTAssertEqual(try XCTUnwrap(row.value), 58, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(row.baseline), 54, accuracy: 0.001)
            XCTAssertGreaterThan(try XCTUnwrap(row.z), 0,
                                 "\(row.metric.displayName) rose after use and reports a negative departure")
        }
        let out = try XCTUnwrap(ScoreDecomposition.evaluate(result))
        XCTAssertNotNil(out.refusal, "a worst-offender pool must still decline the counterfactual")
        XCTAssertTrue(out.rows.allSatisfy { $0.headroom == nil },
                      "a sub-score licensed headroom arithmetic on a model that cannot support it")
    }

    /// Blood pressure's two axes each own a published ladder, and
    /// `score(systolic:diastolic:)` takes the **minimum** of the two — so each
    /// axis has a genuine 0–100 that the min discards.
    ///
    /// The row must also quote the number the *dial* scored rather than the
    /// newest sample: the card has three routes and only one of them reads
    /// today's cuff.
    func testBloodPressureAxesReportTheirOwnLadderScoreForTheNumberTheDialUsed() throws {
        let now = Date()
        let result = BloodPressureInsight().evaluate(
            samples: ContributorsFixture.fullCoverage(now: now),
            profile: ContributorsFixture.profile(now: now), now: now)
        XCTAssertNotNil(result.score, "blood pressure did not score on the full fixture")
        for metric in [MetricType.bloodPressureSystolic, .bloodPressureDiastolic] {
            let row = try XCTUnwrap(result.contributors.first { $0.metric == metric },
                                    "\(metric.displayName) lost its row")
            let score = try XCTUnwrap(row.componentScore,
                                      "\(metric.displayName) reports no ladder score")
            let value = try XCTUnwrap(row.value, "\(metric.displayName) reports no reading")
            let ladder = metric == .bloodPressureSystolic
                ? BloodPressureEstimator.systolicLadder : BloodPressureEstimator.diastolicLadder
            XCTAssertEqual(score, ScoreCurve.through(ladder, at: value), accuracy: 0.001,
                           "\(metric.displayName)'s sub-score is not its own ladder read at its own value")
            // The card's number is the lower of the two axes, so neither axis
            // may score below it — that is what "minimum" means, and it is the
            // cheapest check that the pair came from one route rather than two.
            XCTAssertGreaterThanOrEqual(score, try XCTUnwrap(result.score) - 0.001,
                                        "\(metric.displayName) scored under the dial it is a minimum of")
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
