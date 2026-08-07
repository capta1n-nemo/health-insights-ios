import Foundation

/// Fitness: where you are, where you're heading, and how old that makes you.
///
/// One card from three. Cardio Fitness scored the VO₂max *level*, Fitness
/// Trajectory scored the *direction*, and Heart & Fitness Age reported the same
/// VO₂max as an *age* — three cards reading one metric and answering three
/// halves of one question.
///
/// **None of the maths is new.** The level comes from `HeartHealthScore.vo2Score`
/// (the same norm table Heart Health scores against, so the two cards cannot
/// disagree about "average for your age"), the direction from `VO2Trajectory`,
/// and the age from `FitnessAgeModel`. All three keep their own tests.
public struct FitnessInsight: InsightModel {
    public let id: InsightID = .fitness
    public let title = "Fitness"

    public init() {}

    /// VO₂max carries the score; everything after it is reported, not scored —
    /// see `contributors` below for why that distinction is deliberate.
    ///
    /// `heartRateRecovery`, `dayStrain` and `walkingHeartRateAverage` are new
    /// here. All three were already being imported and none reached any score:
    /// strain was not read by a single insight, and the other two only by the
    /// vitals scanner. They are among the most useful fitness signals the app
    /// holds, so they belong on this card's chart even before anything scores
    /// them.
    /// `.distanceWalkingRunning`, `.flightsClimbed` and `.physicalEffort` join
    /// on 2026-08-06 — backlog §B5 #34–35, both the reader's own reversals, and
    /// both explicitly *as Fitness sections rather than cards*. All three were
    /// being scraped into the raw pile and read by nothing.
    public var candidateMetrics: [MetricType] {
        [.vo2Max, .exerciseMinutes, .heartRateRecovery, .restingHeartRate,
         .walkingHeartRateAverage, .dayStrain, .stepCount, .activeEnergyBurned,
         .distanceWalkingRunning, .flightsClimbed, .physicalEffort]
    }

    public var requirements: [GroundingRequirement] {
        [
            .init(kind: .dateOfBirth, isMandatory: true,
                  rationale: "Fitness is only meaningful against the norms for your age."),
            .init(kind: .biologicalSex, isMandatory: true,
                  rationale: "The reference tables and the age-related decline both differ by sex.")
        ]
    }

    /// How much of the primary pool each term carries.
    ///
    /// Level leads because "how fit am I" is first a question about where you
    /// are; the trajectory is weighted because holding a flat VO₂max into your
    /// fifties is a real achievement that a level-only score would call
    /// mediocre. Renormalised when a term is missing, the same way
    /// `ReadinessScore` and `HeartHealthScore` handle a missing component.
    ///
    /// The dose term is the rebalance `docs/data-opportunities.md` item #1
    /// proposed, for the reason it states: this card scored nothing the reader
    /// actually *does* — VO₂max level and trajectory both move over months,
    /// exercise minutes move this week. It joins the primary pool rather than
    /// the supporting signals because, alone among the activity metrics, it
    /// has a published scale (`ActivityDoseModel`, WHO 2020). With no dose
    /// data the other two renormalise to 0.6875 / 0.3125 — within a point or
    /// two of the old 0.7 / 0.3, deliberately, so a reader without a watch
    /// sees the number they saw yesterday.
    static let levelWeight = 0.55
    static let trajectoryWeight = 0.25
    static let doseWeight = 0.20

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                         now: Date) -> InsightResult {
        let unmet = unmetRequirements(profile: profile, now: now)
        guard let age = profile.age(asOf: now), let sex = profile.sex else {
            return InsightResult(
                id: id, title: title, primaryValue: nil, headline: "Add your details",
                score: nil, confidence: .low,
                explanation: "Add your date of birth and sex, and this turns your cardio-fitness readings into a level for your age, a direction, and a fitness age.",
                drivers: [], unmetRequirements: unmet)
        }

        // `VitalReader`'s 36-hour default freshness is wrong for this metric.
        // An Apple Watch estimates VO₂max on outdoor walks and runs, so a weekly
        // cadence is normal and a fortnight-old figure is still the right one —
        // Heart Health makes the same call for the same reason. `staleAfter` is
        // the trajectory model's own documented threshold rather than a number
        // invented here.
        // `.none`: `.value` only, scored against age/sex norms — the comment on
        // the `.vo2Max` term below says so in as many words.
        guard let vo2Reading = VitalReader.reading(.vo2Max, from: samples, now: now,
                                                   freshWithin: VO2Trajectory.staleAfter,
                                                   gap: .none) else {
            return InsightResult(
                id: id, title: title, primaryValue: nil, headline: "No readings yet",
                score: nil, confidence: .low,
                explanation: "No cardio-fitness readings yet. An Apple Watch estimates VO₂max during outdoor walks and runs, and Oura reports one too — a few of either is enough to start.",
                drivers: [], unmetRequirements: unmet)
        }
        let vo2 = vo2Reading.value

        // MARK: The two scored halves

        let levelScore = HeartHealthScore.vo2Score(vo2, age: age, sex: sex)
        let trajectory = VO2Trajectory.evaluate(samples: samples, age: age, sex: sex, now: now)
        // Same mapping the trajectory card used: matching the age-typical
        // decline sits mid-dial, beating it climbs.
        let trajectoryScore = trajectory.map {
            Swift.max(0, Swift.min(100, 60 + $0.netPerYear * 20))
        }
        let fitnessAge = FitnessAgeModel.evaluate(vo2: vo2, sex: sex, chronologicalAge: age)

        let totalWeight = Self.levelWeight + (trajectoryScore == nil ? 0 : Self.trajectoryWeight)
        let vo2Score = (levelScore * Self.levelWeight
                        + (trajectoryScore ?? 0) * (trajectoryScore == nil ? 0 : Self.trajectoryWeight))
            / totalWeight

        // The week's activity dose, against the WHO band. One combined VO₂max
        // term rather than level and trajectory separately, because
        // `MetricContribution` is the single statement of a metric's share and
        // two `.vo2Max` rows would break that.
        //
        // ⚠️ **Two inputs, one term** (2026-08-06, backlog §B5 #34). Effort
        // intensity answers the same question as the exercise minute and
        // answers it better — it carries the intensity, so WHO's own
        // one-vigorous-for-two-moderate substitution can be applied — so it
        // *supersedes* the dose rather than sitting beside it. A second WHO
        // term would count one afternoon's walking twice. When the week has too
        // little effort data (`EffortIntensityModel` gates on worn days), the
        // exercise minute is still there and nothing about the card changes.
        let effort = EffortIntensityModel.evaluate(samples: samples, now: now)
        let dose = ActivityDoseModel.evaluate(samples: samples, now: now)
        var primary: [ScoreBlend.Term] = [
            // Judged against age/sex norms, so no baseline/z — those fields are
            // for the reader's own history, and a norm table is not that.
            .init(metric: .vo2Max, higherIsBetter: true, score: vo2Score,
                  weight: totalWeight, detail: String(format: "%.0f", vo2),
                  value: vo2)
        ]
        if let effort {
            // No `value`: the score judges moderate-equivalent minutes, which
            // is a derived weekly figure and not a reading in physicalEffort's
            // own unit — the detail says the number in words instead.
            primary.append(.init(
                metric: .physicalEffort, higherIsBetter: true, score: effort.score,
                weight: Self.doseWeight,
                detail: String(format: "%.0f moderate-equivalent min this week",
                               effort.moderateEquivalentMinutes)))
        } else if let dose {
            primary.append(.init(
                metric: .exerciseMinutes, higherIsBetter: true, score: dose.score,
                weight: Self.doseWeight,
                detail: String(format: "%.0f min this week", dose.weeklyMinutes),
                // The week's total, in the metric's own minutes — exactly what
                // the WHO band scored.
                value: dose.weeklyMinutes))
        }

        // The supporting signals carry a share of the number rather than being
        // charted beside it at weight 0. See `SupportingSignal` for the
        // argument that reversed: none of these has a published 0–100 curve,
        // and the answer to weaker evidence is a smaller weight, not a zero
        // one. Exercise minutes appears in both lists on purpose — when the
        // dose can be judged, `ScoreBlend` keeps the published-scale primary
        // term and drops the supporting duplicate; when it cannot (too few
        // recorded days), the signal still reaches the chart as a supporting
        // one rather than vanishing.
        let blend = ScoreBlend.blend(
            primary: primary,
            supporting: Self.supportingTerms(samples: samples, now: now))
        let score = blend?.score ?? vo2Score

        // MARK: Drivers

        var drivers: [InsightDriver] = [
            .component(String(format: "VO₂max %.0f mL/kg·min — %@ for your age",
                              vo2, Self.level(levelScore).lowercased()),
                       score: levelScore)
        ]

        // The one line on this card about what the reader did *this week*, from
        // whichever of the two inputs is scoring it. The coverage line follows
        // the effort figure rather than being folded into it: "392 min moderate"
        // and "from 4 of the last 7 days" are two different claims and the
        // second one is the caveat.
        if let effort {
            drivers.append(.component(EffortIntensityModel.phrase(effort),
                                      score: effort.score))
            drivers.append(.routine(EffortIntensityModel.coveragePhrase(effort)))
        } else if let dose {
            drivers.append(.component(ActivityDoseModel.phrase(dose), score: dose.score))
        }

        drivers.append(InsightDriver(
            text: String(format: "Fitness age %@%@",
                         fitnessAge.isCapped ? "about " : "",
                         Self.agePhrase(fitnessAge, chronologicalAge: age)),
            isNotable: (fitnessAge.yearsYounger ?? 0) < 0))

        // The width of that answer, on its own line, immediately after it
        // (backlog Q3). The reader said the point figure "doesn't seem right",
        // and it is not wrong so much as far narrower than the evidence
        // supports: the norm line falls ~0.4 mL/kg·min a year, so the wrist
        // estimate's own ±3.5 is roughly ±9 years before anything else.
        // Printing 68 alone claims a precision this input does not have.
        if let range = fitnessAge.ageRange, (fitnessAge.rangeWidth ?? 0) >= 2 {
            drivers.append(.routine(String(
                format: "That figure is worth %.0f–%.0f — a wrist VO₂max carries about ±%.1f, and this norm line only falls %.1f a year, so a small error in the reading is a big one in the age",
                range.lowerBound.rounded(), range.upperBound.rounded(),
                AgeComparison.vo2EstimateError,
                abs(FitnessAgeModel.referenceVO2(age: age + 0.5, sex: sex)
                    - FitnessAgeModel.referenceVO2(age: age - 0.5, sex: sex)))))
        }
        if fitnessAge.isExtrapolated {
            drivers.append(.routine(String(
                format: "⚠️ Below VO₂max %.0f the reference line is the table's last slope carried onward, not a measured norm — the age is an extrapolation",
                FitnessAgeModel.anchors(for: sex).last?.vo2 ?? 0)))
        }

        if let trajectory {
            drivers.append(InsightDriver(
                text: String(format: "%@ — net of ageing, %@%.1f a year",
                             trajectory.direction.label, trajectory.netPerYear >= 0 ? "+" : "−",
                             abs(trajectory.netPerYear)),
                isNotable: trajectory.netPerYear < 0))
            drivers.append(.routine(String(format: "Raw trend %@%.1f a year against an age-typical %.1f",
                                           trajectory.perYear >= 0 ? "+" : "−",
                                           abs(trajectory.perYear), trajectory.ageTypicalPerYear)))
            drivers.append(.routine(String(format: "From %d readings over %.0f days",
                                           trajectory.readings, trajectory.spanDays)))
            // A lever is only worth leading with when there is ground to make up.
            drivers.append(contentsOf: trajectory.levers.map {
                InsightDriver(text: "\($0.title): \($0.detail)",
                              isNotable: trajectory.netPerYear < 0)
            })
        } else {
            drivers.append(.routine("Not enough readings yet for a trajectory — that needs \(VO2Trajectory.minimumReadings) spread over six weeks."))
        }

        if !vo2Reading.isFresh {
            let days = Int(now.timeIntervalSince(vo2Reading.date) / 86_400)
            drivers.append(.notable("Last measured \(days) \(SectionCaveat.plural(days, "day")) ago — an outdoor walk or run will refresh it"))
        }

        // The signals this card newly reads. Reported as lines because they are
        // real and the user should see them; not folded into the score because
        // no validated 0–100 curve exists for them here — see `contributors`.
        // Exercise minutes already has its weekly line above whenever the dose
        // was judged, and a second daily figure under it would read as a
        // different quantity in the same words.
        var alreadySaidWeekly: Set<MetricType> = []
        if effort != nil { alreadySaidWeekly.insert(.physicalEffort) }
        if dose != nil { alreadySaidWeekly.insert(.exerciseMinutes) }
        drivers.append(contentsOf: Self.contextDrivers(
            samples: samples, now: now, excluding: alreadySaidWeekly))

        return InsightResult(
            id: id, title: title,
            primaryValue: vo2,
            headline: Self.level(levelScore),
            score: score,
            confidence: Self.confidence(vo2Reading, trajectory: trajectory),
            explanation: Self.explanation(vo2: vo2, levelScore: levelScore,
                                          fitnessAge: fitnessAge, trajectory: trajectory,
                                          age: age),
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: unmet,
            contributors: blend?.contributions
                ?? [.init(metric: .vo2Max, higherIsBetter: true, weight: 1,
                          detail: String(format: "%.0f", vo2),
                          componentScore: vo2Score, value: vo2)],
            weighting: .weightedAverage,
            // ⚠️ **The series existed and the rows did not (2026-08-06).** These
            // four figures have been `derivedOutputs` since the derived-series
            // substrate shipped, so the Data tab could chart them — and they
            // still appeared nowhere on the card itself, because only a factor
            // reaches "What goes into this" and "How this is weighted". That is
            // the reader's complaint in its purest form: a figure the app
            // derives, kept, and then not used anywhere they look.
            otherFactors: Self.producedFigures(fitnessAge: fitnessAge,
                                               trajectory: trajectory, effort: effort),
            derivedOutputs: Self.derivedOutputs(fitnessAge: fitnessAge,
                                                trajectory: trajectory, effort: effort))
    }

    /// The three headline figures as rows.
    ///
    /// ⚠️ Weight 0 — see `ScoreFactor.producedFigure`. This card's number is
    /// VO₂max scored against a published band, blended with supporting signals;
    /// the fitness age is that same VO₂max read off an age axis, so weighting it
    /// would be scoring one measurement twice. The moderate-equivalent minutes
    /// genuinely feed nothing — `ActivityDoseModel` reports them and the score
    /// does not read them — and the row says so rather than implying otherwise
    /// by absence.
    static func producedFigures(fitnessAge: FitnessAgeModel.Output,
                                trajectory: VO2Trajectory.Output?,
                                effort: EffortIntensityModel.Output?) -> [ScoreFactor] {
        var rows: [ScoreFactor] = [
            .producedFigure(
                DerivedSeriesID(.fitness, "fitnessAge"), name: "Fitness age",
                detail: String(format: "%.0f — your VO₂max read off the age axis instead of the fitness one. Tracked, not scored: it is the same measurement as the row above, in years.",
                               fitnessAge.fitnessAge))
        ]
        if let trajectory {
            rows.append(.producedFigure(
                DerivedSeriesID(.fitness, "vo2NetPerYear"),
                name: "VO₂max trend, net of ageing",
                detail: String(format: "%+.2f mL/kg·min a year after the expected age-related decline is taken out. A slope through your readings — it says where you are heading, and the number above says where you are.",
                               trajectory.netPerYear)))
        }
        if let effort {
            rows.append(.producedFigure(
                DerivedSeriesID(.fitness, "moderateEquivalentMinutes"),
                name: "Moderate-equivalent minutes this week",
                detail: String(format: "%.0f min, with vigorous time counted double as the guidance does — charted and never scored, because the guideline threshold is about long-run health outcomes rather than about this week's VO₂max.",
                               effort.moderateEquivalentMinutes)))
        }
        return rows
    }

    /// **What this card works out that nothing else holds.**
    ///
    /// Three figures that existed only as sentences until 2026-08-06: the
    /// fitness age (recomputed every launch and remembered nowhere, so "is my
    /// fitness age improving" could only be answered by re-deriving it), the
    /// ageing-adjusted trajectory, and the week's moderate-equivalent minutes.
    ///
    /// The keys are stable identifiers baked into stored history — renaming one
    /// orphans its series, so they are treated like `modelVersion` and not
    /// edited for tidiness.
    static func derivedOutputs(fitnessAge: FitnessAgeModel.Output,
                               trajectory: VO2Trajectory.Output?,
                               effort: EffortIntensityModel.Output?) -> [DerivedOutput] {
        var out: [DerivedOutput] = [
            .init(key: "fitnessAge", displayName: "Fitness age", unit: "years",
                  value: fitnessAge.fitnessAge, higherIsBetter: false, precision: 0)
        ]
        if let trajectory {
            out.append(.init(key: "vo2NetPerYear",
                             displayName: "VO₂max trend, net of ageing",
                             unit: "mL/kg·min a year", value: trajectory.netPerYear,
                             higherIsBetter: true, precision: 2))
        }
        if let effort {
            out.append(.init(key: "moderateEquivalentMinutes",
                             displayName: "Moderate-equivalent minutes this week",
                             unit: "min", value: effort.moderateEquivalentMinutes,
                             higherIsBetter: true, precision: 0))
            // A share, not a dose — and the one figure on this card that says
            // anything about *how hard* rather than *how much*. `nil` where
            // there was no active time to take a share of, which is why this is
            // conditional rather than defaulted to zero.
            if let share = effort.vigorousShare {
                out.append(.init(key: "vigorousShare",
                                 displayName: "Share of active time at vigorous effort",
                                 unit: "%", value: share * 100,
                                 higherIsBetter: true, precision: 0))
            }
        }
        return out
    }

    // MARK: - Contributions

    /// The supporting signals, judged against the reader's own baseline.
    ///
    /// **This reverses a decision recorded at length, and the reversal is the
    /// user's.** These were reported at weight 0 on the argument that no
    /// validated 0–100 curve exists for any of them and an invented weight
    /// inside a trusted score is worse than none. That argument is against
    /// *inventing* one; it did not justify a section headed "What goes into
    /// this" listing seven signals of which one went into anything.
    ///
    /// Nothing is invented here. `SupportingSignal.score` is the mapping
    /// `ReadinessScore` already weights every one of its components with —
    /// direction-aware departure from this person's own normal — and it earns
    /// the smaller weight that weaker evidence deserves rather than none at all.
    static func supportingTerms(samples: [HealthMetricSample], now: Date,
                                calendar: Calendar = .current) -> [ScoreBlend.Term] {
        contextMetrics.compactMap { metric, higherIsBetter in
            // `.none`: supporting score terms, held with the rest of the
            // scoring path. See the call-site rule in `VitalReader`.
            VitalReader.reading(metric, from: samples, now: now, gap: .none,
                                excludingPartialDay: excludesPartialDay(metric),
                                calendar: calendar)
                .flatMap { ScoreBlend.supporting($0, higherIsBetter: higherIsBetter) }
        }
    }

    /// A cumulative metric read mid-day is not a low day.
    ///
    /// The user's own card export is the evidence: "Steps: 224 · 1.5 SD below
    /// your normal", exported in the morning — today's partial total judged
    /// against a baseline of complete days, a comparison that reads
    /// catastrophic every day before dinner. Cumulative metrics are judged on
    /// the last *complete* day instead; yesterday is still inside the
    /// freshness window, so nothing goes stale by waiting for midnight.
    /// Point-in-time vitals keep today — a heart rate at 9 am is a whole
    /// measurement, not a fraction of one.
    ///
    /// ⚠️ **This used to return a filtered copy of the sample set, and that was
    /// four fifths of the whole insight pass** (backlog `D57`). Handing
    /// `VitalReader` a new array defeats the evaluation memo, which keys on the
    /// canonical array's identity — so each of the five cumulative metrics
    /// here, on each of two call sites, paid a full scan, a full deduplicate
    /// and a full re-bucketing of the reader's 381,701 readings. The rule is
    /// unchanged; only where it is applied moved, from the samples to the
    /// buckets. See `VitalReader.reading(excludingPartialDay:)`.
    static func excludesPartialDay(_ metric: MetricType) -> Bool {
        metric.presentation == .cumulativeTotal
    }

    /// The supporting signals, and which direction is the good one.
    ///
    /// Day strain has no good direction — a high training load is neither good
    /// nor bad without knowing what it was for — so it reports `nil` rather than
    /// implying a verdict, the same way skin-temperature deviation does.
    static let contextMetrics: [(MetricType, Bool?)] = [
        (.heartRateRecovery, true),
        (.restingHeartRate, false),
        (.walkingHeartRateAverage, false),
        (.dayStrain, nil),
        (.stepCount, true),
        (.activeEnergyBurned, true),
        // Backlog §B5 #35. Both are near-restatements of steps — which is why
        // they are supporting signals on an existing card and not a card of
        // their own — but flights is the one activity figure that reads effort
        // against gravity, and it moves independently of the other two on a
        // day with a hill in it.
        (.distanceWalkingRunning, true),
        (.flightsClimbed, true),
        // Usually promoted to the primary pool by `ActivityDoseModel`;
        // this row is the fallback for a week with too few recorded days.
        (.exerciseMinutes, true),
        // Same relationship, one level up: promoted to the primary pool by
        // `EffortIntensityModel` when the week has enough worn days, and here
        // as a day-against-your-own-normal signal when it does not.
        (.physicalEffort, true)
    ]

    static func contextDrivers(samples: [HealthMetricSample], now: Date,
                               excluding: Set<MetricType> = [],
                               calendar: Calendar = .current) -> [InsightDriver] {
        contextMetrics.compactMap { metric, _ in
            guard !excluding.contains(metric),
                  let reading = VitalReader.reading(
                    metric, from: samples, now: now, gap: .none,
                    excludingPartialDay: excludesPartialDay(metric),
                    calendar: calendar) else { return nil }
            return .routine("\(metric.displayName): \(MetricValueFormatter.string(reading.value, metric)) \(metric.unit)")
        }
    }

    // MARK: - Phrasing

    /// The same bands Cardio Fitness used, so the word on the card didn't change
    /// when the cards merged.
    static func level(_ score: Double) -> String {
        switch score {
        case 85...: return "Excellent"
        case 70..<85: return "Good"
        case 50..<70: return "Fair"
        default: return "Needs work"
        }
    }

    static func agePhrase(_ output: FitnessAgeModel.Output,
                          chronologicalAge: Double) -> String {
        // The difference is taken between the two *displayed* (rounded)
        // figures, not the unrounded ones, so the sentence survives the
        // reader's own arithmetic: a 28-year-old shown "fitness age 68" must
        // read "40 years older", not the "39" that 67.5 − 28.4 rounds to.
        guard output.yearsYounger != nil else {
            return "\(String(format: "%.0f", output.fitnessAge)) — level with your actual age"
        }
        let displayedAge = output.fitnessAge.rounded()
        let years = chronologicalAge.rounded() - displayedAge
        let age = String(format: "%.0f", displayedAge)
        if abs(years) < 1 { return "\(age) — level with your actual age" }
        return years > 0
            ? String(format: "%@ — %.0f years younger than you are", age, years)
            : String(format: "%@ — %.0f years older than you are", age, -years)
    }

    static func confidence(_ reading: VitalReading,
                           trajectory: VO2Trajectory.Output?) -> InsightConfidence {
        if !reading.isFresh { return .low }
        guard let trajectory else { return .moderate }
        return trajectory.readings >= 8 && trajectory.spanDays >= 120 ? .high : .moderate
    }

    static func explanation(vo2: Double, levelScore: Double,
                            fitnessAge: FitnessAgeModel.Output,
                            trajectory: VO2Trajectory.Output?,
                            age: Double) -> String {
        var text = String(format: "Your VO₂max of %.0f is %@ for your age and sex, which puts your fitness age at about %.0f. Cardio fitness is one of the strongest single predictors of long-term health.",
                          vo2, level(levelScore).lowercased(), fitnessAge.fitnessAge)
        if let trajectory {
            text += String(format: " Over the last %.0f days it has moved %@%.1f a year, against an age-typical %.1f — so net of ageing you are %@.",
                           trajectory.spanDays,
                           trajectory.perYear >= 0 ? "+" : "−", abs(trajectory.perYear),
                           trajectory.ageTypicalPerYear,
                           trajectory.direction == .improving ? "gaining"
                               : (trajectory.direction == .holding ? "holding station" : "losing ground"))
        }
        return text
    }
}
