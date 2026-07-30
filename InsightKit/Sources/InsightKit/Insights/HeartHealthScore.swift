import Foundation

/// A transparent, composite "heart health" score (0–100) built from *measured*
/// cardiovascular-fitness signals, each compared to age/sex reference ranges and
/// (where history exists) the user's own baseline. No training data or opaque
/// model — every component and weight is inspectable.
///
/// Components (present ones are re-weighted to sum to 1):
///  • VO₂max (cardiorespiratory fitness) — strongest predictor of outcomes.
///  • Resting heart rate — lower is generally better.
///  • HRV — higher generally reflects better autonomic balance.
///  • Respiratory rate — scored for stability against baseline.
public enum HeartHealthScore {

    public struct Component: Sendable, Equatable {
        public let name: String
        public let score: Double       // 0…100
        public let weight: Double
        public let detail: String
        public init(name: String, score: Double, weight: Double, detail: String) {
            self.name = name; self.score = score; self.weight = weight; self.detail = detail
        }
    }

    public struct Output: Sendable, Equatable {
        public let score: Double        // 0…100 weighted composite
        public let components: [Component]
    }

    // MARK: - Reference-range sub-scores (clamped 0…100)

    /// VO₂max reference midpoints (mL/kg/min) by sex and age band, from standard
    /// cardiorespiratory-fitness norms. We score relative to a "good" band.
    static func vo2Score(_ vo2: Double, age: Double, sex: BiologicalSex) -> Double {
        let good: Double
        switch sex {
        case .male:
            good = age < 30 ? 48 : age < 40 ? 44 : age < 50 ? 40 : age < 60 ? 36 : 32
        case .female:
            good = age < 30 ? 41 : age < 40 ? 38 : age < 50 ? 34 : age < 60 ? 31 : 28
        }
        // 60% of the "good" value scores ~50; the good value scores ~85.
        let ratio = vo2 / good
        return clamp((ratio - 0.5) / (1.1 - 0.5) * 100)
    }

    /// Resting HR sub-score. ~50 bpm → excellent, ~85 → poor.
    static func restingHRScore(_ hr: Double) -> Double {
        clamp((85 - hr) / (85 - 50) * 100)
    }

    /// HRV sub-score with an age-declining reference. Uses whichever of SDNN /
    /// rMSSD is provided; both are treated on the same rough ms scale here.
    static func hrvScore(_ hrv: Double, age: Double) -> Double {
        // Rough "healthy" reference that declines with age.
        let ref = max(20, 70 - (age - 20) * 0.6)
        return clamp(hrv / ref * 75)   // at the reference you score ~75
    }

    // MARK: - Composite

    public static func evaluate(
        vo2Max: Double?,
        restingHR: Double?,
        hrv: Double?,
        respiratoryRateDeviation: Baseline.Deviation?,
        age: Double,
        sex: BiologicalSex
    ) -> Output? {
        var comps: [Component] = []

        if let vo2 = vo2Max {
            comps.append(.init(name: "Cardio fitness (VO₂max)",
                               score: vo2Score(vo2, age: age, sex: sex), weight: 0.45,
                               detail: String(format: "%.0f mL/kg·min", vo2)))
        }
        if let hr = restingHR {
            comps.append(.init(name: "Resting heart rate",
                               score: restingHRScore(hr), weight: 0.25,
                               detail: String(format: "%.0f bpm", hr)))
        }
        if let v = hrv {
            comps.append(.init(name: "Heart-rate variability",
                               score: hrvScore(v, age: age), weight: 0.25,
                               detail: String(format: "%.0f ms", v)))
        }
        if let dev = respiratoryRateDeviation {
            // Stable respiratory rate (near baseline) scores high; big deviations lower it.
            let penalty = min(60, abs(dev.zScore ?? 0) * 20)
            comps.append(.init(name: "Respiratory stability",
                               score: clamp(90 - penalty), weight: 0.05,
                               detail: String(format: "%.0f br/min", dev.value)))
        }

        guard !comps.isEmpty else { return nil }
        let totalWeight = comps.reduce(0) { $0 + $1.weight }
        let composite = comps.reduce(0) { $0 + $1.score * $1.weight } / totalWeight
        return Output(score: composite, components: comps)
    }

    static func clamp(_ x: Double) -> Double { max(0, min(100, x)) }
}

/// `InsightModel` adapter for the heart-health composite. All its inputs come
/// from sensed data, so it needs only age & sex as grounding.
public struct HeartHealthInsight: InsightModel {
    public let id: InsightID = .heartHealth
    public let title = "Heart Health"

    public init() {}

    public var candidateMetrics: [MetricType] {
        [.vo2Max, .restingHeartRate, .heartRateVariabilityRMSSD,
         .heartRateVariabilitySDNN, .respiratoryRate]
    }

    public var requirements: [GroundingRequirement] {
        [
            .init(kind: .dateOfBirth, isMandatory: true,
                  rationale: "Fitness norms are age-adjusted."),
            .init(kind: .biologicalSex, isMandatory: true,
                  rationale: "Fitness norms differ by sex.")
        ]
    }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult {
        let unmet = unmetRequirements(profile: profile, now: now)
        guard let age = profile.age(asOf: now), let sex = profile.sex else {
            return InsightResult(
                id: id, title: title, primaryValue: nil, headline: "Add your details",
                score: nil, confidence: .low,
                explanation: "Add your date of birth and sex so fitness signals can be scored against age-adjusted norms.",
                drivers: [], unmetRequirements: unmet)
        }

        let vo2 = samples.latestValue(.vo2Max)
        let restHR = samples.meanValue(.restingHeartRate)
        let hrv = samples.latestValue(.heartRateVariabilityRMSSD)
            ?? samples.latestValue(.heartRateVariabilitySDNN)

        let respSamples = samples.samples(of: .respiratoryRate).map(\.value)
        let respDev: Baseline.Deviation? = respSamples.count >= 4
            ? Baseline.deviation(latest: respSamples.last!, history: Array(respSamples.dropLast()))
            : nil

        guard let out = HeartHealthScore.evaluate(
            vo2Max: vo2, restingHR: restHR, hrv: hrv,
            respiratoryRateDeviation: respDev, age: age, sex: sex) else {
            return InsightResult(
                id: id, title: title, primaryValue: nil, headline: "No data yet",
                score: nil, confidence: .low,
                explanation: "Connect Apple Health or a wearable so we can read your cardio fitness, resting heart rate and HRV.",
                drivers: [], unmetRequirements: unmet)
        }

        let band = HeartHealthInsight.band(out.score)
        // Confidence scales with how many components were available.
        let confidence: InsightConfidence = out.components.count >= 3 ? .high
            : out.components.count == 2 ? .moderate : .low
        let drivers = out.components.map { "\($0.name): \($0.detail)" }
        let explanation = "Composite heart-health score of \(Int(out.score.rounded()))/100 (\(band)), from your cardio fitness, resting heart rate and HRV compared with age-adjusted norms."

        return InsightResult(
            id: id, title: title, primaryValue: out.score,
            headline: band, score: out.score, confidence: confidence,
            explanation: explanation, drivers: drivers, unmetRequirements: unmet)
    }

    static func band(_ score: Double) -> String {
        switch score {
        case 80...: return "Excellent"
        case 65..<80: return "Good"
        case 50..<65: return "Fair"
        default: return "Needs attention"
        }
    }
}
