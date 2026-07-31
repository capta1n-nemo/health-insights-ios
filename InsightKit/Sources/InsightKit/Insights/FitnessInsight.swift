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
        [.vo2Max, .heartRateRecovery, .restingHeartRate, .walkingHeartRateAverage,
         .dayStrain, .stepCount, .activeEnergyBurned]
    }

    public var requirements: [GroundingRequirement] {
        [
            .init(kind: .dateOfBirth, isMandatory: true,
                  rationale: "Fitness is only meaningful against the norms for your age."),
            .init(kind: .biologicalSex, isMandatory: true,
                  rationale: "The reference tables and the age-related decline both differ by sex.")
        ]
    }

    /// How much of the score each half carries.
    ///
    /// Level leads because "how fit am I" is first a question about where you
    /// are; the trajectory is weighted because holding a flat VO₂max into your
    /// fifties is a real achievement that a level-only score would call
    /// mediocre. Renormalised when only one half is available, the same way
    /// `ReadinessScore` and `HeartHealthScore` handle a missing component.
    static let levelWeight = 0.7
    static let trajectoryWeight = 0.3

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
        let score = (levelScore * Self.levelWeight
                     + (trajectoryScore ?? 0) * (trajectoryScore == nil ? 0 : Self.trajectoryWeight))
            / totalWeight

        // MARK: Drivers

        var drivers: [InsightDriver] = [
            .component(String(format: "VO₂max %.0f mL/kg·min — %@ for your age",
                              vo2, Self.level(levelScore).lowercased()),
                       score: levelScore)
        ]

        drivers.append(InsightDriver(
            text: String(format: "Fitness age %@%@",
                         fitnessAge.isCapped ? "about " : "",
                         Self.agePhrase(fitnessAge, chronologicalAge: age)),
            isNotable: (fitnessAge.yearsYounger ?? 0) < 0))

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
            drivers.append(.notable("Last measured \(days) days ago — an outdoor walk or run will refresh it"))
        }

        // The signals this card newly reads. Reported as lines because they are
        // real and the user should see them; not folded into the score because
        // no validated 0–100 curve exists for them here — see `contributors`.
        drivers.append(contentsOf: Self.contextDrivers(samples: samples, now: now))

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
            contributors: Self.contributors(samples: samples, now: now, vo2: vo2))
    }

    // MARK: - Contributions

    /// VO₂max carries the weight; the rest are reported at weight 0.
    ///
    /// **Deliberate, and the alternative was worse.** Heart-rate recovery, day
    /// strain and walking heart rate are genuinely useful fitness signals, and
    /// this card is the first thing in the app to read them — but there is no
    /// validated 0–100 curve for any of them here. Giving them a made-up weight
    /// would put an invented number inside a score the user is asked to trust.
    /// Weight 0 is the same honesty `VitalSignsCheck` and `HealthWatchModel`
    /// already apply: the signal is on the chart, in the legend, and in
    /// `contributors` for anything later to learn from, without pretending it
    /// was scored.
    static func contributors(samples: [HealthMetricSample], now: Date,
                             vo2: Double) -> [MetricContribution] {
        var out = [MetricContribution(metric: .vo2Max, higherIsBetter: true, weight: 1,
                                      detail: String(format: "%.0f", vo2))]
        for (metric, higherIsBetter) in contextMetrics {
            guard let reading = VitalReader.reading(metric, from: samples, now: now) else { continue }
            out.append(MetricContribution(
                metric: metric, higherIsBetter: higherIsBetter, weight: 0,
                detail: MetricValueFormatter.string(reading.value, metric)))
        }
        return out
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
        (.activeEnergyBurned, true)
    ]

    static func contextDrivers(samples: [HealthMetricSample], now: Date) -> [InsightDriver] {
        contextMetrics.compactMap { metric, _ in
            guard let reading = VitalReader.reading(metric, from: samples, now: now) else { return nil }
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
        let years = output.yearsYounger ?? 0
        let age = String(format: "%.0f", output.fitnessAge)
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
