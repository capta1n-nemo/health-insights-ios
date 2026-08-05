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
    public var candidateMetrics: [MetricType] {
        [.vo2Max, .exerciseMinutes, .heartRateRecovery, .restingHeartRate,
         .walkingHeartRateAverage, .dayStrain, .stepCount, .activeEnergyBurned]
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
        guard let vo2Reading = VitalReader.reading(.vo2Max, from: samples, now: now,
                                                   freshWithin: VO2Trajectory.staleAfter) else {
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
        let dose = ActivityDoseModel.evaluate(samples: samples, now: now)
        var primary: [ScoreBlend.Term] = [
            .init(metric: .vo2Max, higherIsBetter: true, score: vo2Score,
                  weight: totalWeight, detail: String(format: "%.0f", vo2))
        ]
        if let dose {
            primary.append(.init(
                metric: .exerciseMinutes, higherIsBetter: true, score: dose.score,
                weight: Self.doseWeight,
                detail: String(format: "%.0f min this week", dose.weeklyMinutes)))
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

        // The one line on this card about what the reader did *this week*.
        if let dose {
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
        drivers.append(contentsOf: Self.contextDrivers(
            samples: samples, now: now,
            excluding: dose == nil ? [] : [.exerciseMinutes]))

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
                          detail: String(format: "%.0f", vo2))],
            weighting: .weightedAverage)
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
            VitalReader.reading(metric,
                                from: judgementSamples(for: metric, samples: samples,
                                                       now: now, calendar: calendar),
                                now: now)
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
    static func judgementSamples(for metric: MetricType,
                                 samples: [HealthMetricSample],
                                 now: Date, calendar: Calendar) -> [HealthMetricSample] {
        guard metric.presentation == .cumulativeTotal else { return samples }
        let startOfToday = calendar.startOfDay(for: now)
        return samples.filter { $0.start < startOfToday }
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
        // Usually promoted to the primary pool by `ActivityDoseModel`;
        // this row is the fallback for a week with too few recorded days.
        (.exerciseMinutes, true)
    ]

    static func contextDrivers(samples: [HealthMetricSample], now: Date,
                               excluding: Set<MetricType> = [],
                               calendar: Calendar = .current) -> [InsightDriver] {
        contextMetrics.compactMap { metric, _ in
            guard !excluding.contains(metric),
                  let reading = VitalReader.reading(
                    metric,
                    from: judgementSamples(for: metric, samples: samples,
                                           now: now, calendar: calendar),
                    now: now) else { return nil }
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
