import Foundation

/// A transparent daily "readiness / recovery" score (0–100) in the spirit of
/// Oura Readiness and Whoop Recovery — the single number under-30 wearable users
/// check every morning. Unlike those closed scores, every component and weight
/// here is inspectable, and each signal is judged against the user's OWN recent
/// baseline (not a population model), which is what makes it personal.
///
/// Components (present ones are re-weighted to sum to 1):
///  • HRV vs baseline        — higher than your normal = better recovered
///  • Resting HR vs baseline — lower than your normal = better recovered
///  • Sleep duration         — vs a 7.5 h target
///  • Skin-temp deviation    — near your baseline is good; a spike costs points
///  • Respiratory stability  — a jump above baseline costs points
public enum ReadinessScore {

    public struct Component: Sendable, Equatable {
        public let name: String
        public let score: Double      // 0…100
        public let weight: Double
        public let detail: String
        /// The metric this component read. Carried so the detail screen can
        /// chart exactly what the score used — add a component here and it
        /// appears on the chart with no other edit.
        public let metric: MetricType
        /// nil where neither direction is "better" (temperature deviation).
        public let higherIsBetter: Bool?
    }

    public struct Output: Sendable, Equatable {
        public let score: Double
        public let components: [Component]
        public let band: String

        /// Components as chart contributions, with weights renormalised over the
        /// ones that actually had data — the same division the score itself does.
        public var contributions: [MetricContribution] {
            let total = components.reduce(0) { $0 + $1.weight }
            guard total > 0 else { return [] }
            return components.map {
                MetricContribution(metric: $0.metric, higherIsBetter: $0.higherIsBetter,
                                   weight: $0.weight / total, detail: $0.detail)
            }
        }
    }

    static func clamp(_ x: Double) -> Double { max(0, min(100, x)) }

    /// Map a z-score (value vs baseline history) to 0…100 where higher-is-better
    /// signals score up when above baseline. `polarity` flips it for lower-is-better.
    static func zScoreToScore(_ z: Double, polarity: Double) -> Double {
        // z of 0 → 65 (a typical day); +1.5 SD in the good direction → ~95.
        clamp(65 + polarity * z * 20)
    }

    public static func evaluate(samples: [HealthMetricSample]) -> Output? {
        var comps: [Component] = []

        func history(_ type: MetricType) -> [Double] { samples.samples(of: type).map(\.value) }

        // HRV — prefer rMSSD, fall back to SDNN. Higher than baseline is better.
        let hrvMetric: MetricType = history(.heartRateVariabilityRMSSD).isEmpty
            ? .heartRateVariabilitySDNN : .heartRateVariabilityRMSSD
        let hrv = history(hrvMetric)
        if hrv.count >= 4, let latest = hrv.last,
           let z = Baseline.zScore(latest, history: Array(hrv.dropLast())) {
            comps.append(.init(name: "HRV vs your baseline",
                               score: zScoreToScore(z, polarity: 1),
                               weight: 0.40, detail: String(format: "%.0f ms", latest),
                               metric: hrvMetric, higherIsBetter: true))
        }

        // Resting HR — lower than baseline is better.
        let rhr = history(.restingHeartRate)
        if rhr.count >= 4, let latest = rhr.last,
           let z = Baseline.zScore(latest, history: Array(rhr.dropLast())) {
            comps.append(.init(name: "Resting HR vs your baseline",
                               score: zScoreToScore(z, polarity: -1),
                               weight: 0.25, detail: String(format: "%.0f bpm", latest),
                               metric: .restingHeartRate, higherIsBetter: false))
        }

        // Sleep — vs a 7.5 h target (6 h ≈ 55, 8 h ≈ 90).
        if let sleep = samples.latestValue(.sleepDurationHours) {
            let s = clamp((sleep - 4) / (8.0 - 4) * 100)
            comps.append(.init(name: "Sleep", score: s, weight: 0.20,
                               detail: String(format: "%.1f h", sleep),
                               metric: .sleepDurationHours, higherIsBetter: true))
        }

        // Skin-temp deviation — being near baseline is good; a spike (fever /
        // strain / alcohol) pulls it down. Uses the deviation directly.
        if let dev = samples.latestValue(.skinTemperatureDeviation) {
            let penalty = min(70, abs(dev) * 60)
            comps.append(.init(name: "Body temperature", score: clamp(92 - penalty),
                               weight: 0.10, detail: String(format: "%+.1f °C", dev),
                               metric: .skinTemperatureDeviation, higherIsBetter: nil))
        }

        // Respiratory rate — a rise above baseline is an early strain/illness sign.
        let resp = history(.respiratoryRate)
        if resp.count >= 4, let latest = resp.last,
           let z = Baseline.zScore(latest, history: Array(resp.dropLast())) {
            comps.append(.init(name: "Respiratory rate", score: zScoreToScore(z, polarity: -1),
                               weight: 0.05, detail: String(format: "%.0f br/min", latest),
                               metric: .respiratoryRate, higherIsBetter: false))
        }

        // Overnight blood oxygen — a drop below your own normal accompanies
        // disrupted breathing, altitude and illness, and it moves before you
        // feel it. Small weight: it's a narrow signal, and most nights it says
        // nothing. Absolute floor as well as a personal one, because a baseline
        // built from consistently low saturation would normalise the problem.
        let spo2 = history(.oxygenSaturation)
        if let latest = spo2.last {
            let component: Double
            if spo2.count >= 4, let z = Baseline.zScore(latest, history: Array(spo2.dropLast())) {
                component = zScoreToScore(z, polarity: 1)
            } else {
                component = latest >= 95 ? 85 : 60
            }
            let floored = latest < 92 ? min(component, 40) : component
            comps.append(.init(name: "Blood oxygen", score: floored, weight: 0.05,
                               detail: String(format: "%.0f%%", latest),
                               metric: .oxygenSaturation, higherIsBetter: true))
        }

        guard !comps.isEmpty else { return nil }
        let total = comps.reduce(0) { $0 + $1.weight }
        let score = comps.reduce(0) { $0 + $1.score * $1.weight } / total
        return Output(score: score, components: comps, band: band(score))
    }

    static func band(_ score: Double) -> String {
        switch score {
        case 80...: return "Primed"
        case 66..<80: return "Ready"
        case 50..<66: return "Take it easy"
        default: return "Recover"
        }
    }
}

/// `InsightModel` adapter. Readiness needs no grounding — it's built entirely
/// from sensed signals compared to the user's own history.
public struct ReadinessInsight: InsightModel {
    public let id: InsightID = .readiness
    public let title = "Readiness"
    public init() {}

    public var requirements: [GroundingRequirement] { [] }

    /// Everything `ReadinessScore.evaluate` can read. Both HRV flavours appear
    /// because it prefers rMSSD and falls back to SDNN.
    public var candidateMetrics: [MetricType] {
        [.heartRateVariabilityRMSSD, .heartRateVariabilitySDNN, .restingHeartRate,
         .sleepDurationHours, .skinTemperatureDeviation, .respiratoryRate,
         .oxygenSaturation]
    }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult {
        guard let out = ReadinessScore.evaluate(samples: samples) else {
            return InsightResult(
                id: id, title: title, primaryValue: nil, headline: "Building baseline",
                score: nil, confidence: .low,
                explanation: "Wear your device for a few nights so we can learn your normal HRV, resting heart rate and sleep — then you'll get a daily readiness score.",
                drivers: [], unmetRequirements: [])
        }
        let confidence: InsightConfidence = out.components.count >= 3 ? .high
            : out.components.count == 2 ? .moderate : .low
        // Components that are holding the score down come first and stay
        // visible; the ones behaving normally fold away on the detail screen.
        // Partitioned rather than sorted: Swift's sort isn't stable, and the
        // weight order components arrive in is meaningful.
        let lines = out.components
            .map { InsightDriver.component("\($0.name): \($0.detail)", score: $0.score) }
        return InsightResult(
            id: id, title: title, primaryValue: out.score,
            headline: out.band, score: out.score, confidence: confidence,
            explanation: "Your recovery today is \(Int(out.score.rounded()))/100 (\(out.band)), from how your HRV, resting heart rate, sleep and temperature compare with your own recent baseline.",
            driverLines: lines.filter { $0.isNotable == true } + lines.filter { $0.isNotable != true },
            unmetRequirements: [], contributors: out.contributions)
    }
}
