import Foundation

/// VO₂max as a fitness level for age/sex, plus its trend direction — the single
/// strongest cardiovascular-longevity signal for younger users.
public struct CardioFitnessInsight: InsightModel {
    public let id: InsightID = .cardioFitness
    public let title = "Cardio Fitness"
    public init() {}
    public var candidateMetrics: [MetricType] { [.vo2Max] }
    public var requirements: [GroundingRequirement] {
        [.init(kind: .dateOfBirth, isMandatory: true, rationale: "Fitness levels are age-adjusted."),
         .init(kind: .biologicalSex, isMandatory: true, rationale: "Fitness norms differ by sex.")]
    }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult {
        // VO₂max is estimated, not sampled: Apple publishes one per outdoor walk
        // or run, so 45 days is the honest freshness line and the 36-hour default
        // would call every reading stale. An older reading is still shown — it is
        // the only fitness figure this person has — but it stops buying `.high`,
        // which is what let a 400-day-old number print as current.
        let vo2Reading = VitalReader.reading(.vo2Max, from: samples, now: now,
                                             minimumDays: 2, freshWithin: 45 * 86_400)
        let unmet = unmetRequirements(profile: profile, now: now)
        guard let reading = vo2Reading, let age = profile.age(asOf: now), let sex = profile.sex else {
            return InsightResult(id: id, title: title, primaryValue: nil, headline: "Add details",
                score: nil, confidence: .low,
                explanation: "Add your age and sex, and record cardio fitness (VO₂max) via Apple Watch, to see your fitness level.",
                drivers: [], unmetRequirements: unmet)
        }
        let vo2 = reading.value
        let score = HeartHealthScore.vo2Score(vo2, age: age, sex: sex)
        let level = Self.level(score)
        var drivers = [InsightDriver.component(String(format: "VO₂max: %.0f mL/kg·min", vo2),
                                               score: score)]
        // The baseline is the last 28 days of daily values, not every reading
        // ever taken — and `history` is de-duplicated, so an Oura figure arriving
        // both directly and through Apple Health is one day, not two. That
        // duplication was buying `.high` confidence on its own.
        if reading.history.count >= 2, let base = Baseline.mean(reading.history) {
            let word = trendWord(recent: vo2, baseline: base, higherIsBetter: true)
            // A trend is only worth leading with when it's the wrong way.
            drivers.append(InsightDriver(text: "Trend: \(word)",
                                         isNotable: word.contains("down") && !word.contains("good")))
        }
        if !reading.isFresh {
            let days = Int(now.timeIntervalSince(reading.date) / 86_400)
            drivers.append(.notable("Last measured \(days) days ago — an outdoor walk or run will refresh it"))
        }
        return InsightResult(
            id: id, title: title, primaryValue: vo2, headline: level, score: score,
            confidence: !reading.isFresh ? .low : (reading.history.count >= 2 ? .high : .moderate),
            explanation: "Your cardio fitness (VO₂max \(Int(vo2.rounded()))) is \(level.lowercased()) for your age and sex. Higher VO₂max is one of the strongest predictors of long-term heart health.",
            driverLines: drivers, unmetRequirements: unmet,
            contributors: [.init(metric: .vo2Max, higherIsBetter: true, weight: 1,
                                 detail: String(format: "%.0f", vo2))])
    }
    static func level(_ s: Double) -> String {
        switch s { case 80...: return "Excellent"; case 60..<80: return "Good"
        case 40..<60: return "Average"; default: return "Below average" }
    }
}
