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
        /// The metric this read, so the detail screen charts exactly what the
        /// score used rather than a hand-maintained guess at it.
        public let metric: MetricType
        public let higherIsBetter: Bool?
        public init(name: String, score: Double, weight: Double, detail: String,
                    metric: MetricType, higherIsBetter: Bool?) {
            self.name = name; self.score = score; self.weight = weight; self.detail = detail
            self.metric = metric; self.higherIsBetter = higherIsBetter
        }
    }

    public struct Output: Sendable, Equatable {
        public let score: Double        // 0…100 weighted composite
        public let components: [Component]

        /// Weights renormalised over the components that had data — the same
        /// division the composite itself does.
        public var contributions: [MetricContribution] {
            let total = components.reduce(0) { $0 + $1.weight }
            guard total > 0 else { return [] }
            return components.map {
                MetricContribution(metric: $0.metric, higherIsBetter: $0.higherIsBetter,
                                   weight: $0.weight / total, detail: $0.detail)
            }
        }
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
        /// Which HRV flavour `hrv` came from, so the chart plots that one.
        hrvMetric: MetricType = .heartRateVariabilityRMSSD,
        respiratoryRateDeviation: Baseline.Deviation?,
        age: Double,
        sex: BiologicalSex
    ) -> Output? {
        var comps: [Component] = []

        if let vo2 = vo2Max {
            comps.append(.init(name: "Cardio fitness (VO₂max)",
                               score: vo2Score(vo2, age: age, sex: sex), weight: 0.45,
                               detail: String(format: "%.0f mL/kg·min", vo2),
                               metric: .vo2Max, higherIsBetter: true))
        }
        if let hr = restingHR {
            comps.append(.init(name: "Resting heart rate",
                               score: restingHRScore(hr), weight: 0.25,
                               detail: String(format: "%.0f bpm", hr),
                               metric: .restingHeartRate, higherIsBetter: false))
        }
        if let v = hrv {
            comps.append(.init(name: "Heart-rate variability",
                               score: hrvScore(v, age: age), weight: 0.25,
                               detail: String(format: "%.0f ms", v),
                               metric: hrvMetric, higherIsBetter: true))
        }
        if let dev = respiratoryRateDeviation {
            // Stable respiratory rate (near baseline) scores high; big deviations lower it.
            let penalty = min(60, abs(dev.zScore ?? 0) * 20)
            comps.append(.init(name: "Respiratory stability",
                               score: clamp(90 - penalty), weight: 0.05,
                               detail: String(format: "%.0f br/min", dev.value),
                               metric: .respiratoryRate, higherIsBetter: nil))
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

    /// `heartRateRecovery` is here because this card **draws it**. It is the
    /// only measurement in "How your heart responds", which is this card's own
    /// bespoke section — and it was declared by no card, so it charted nowhere,
    /// linked nowhere under "Full history", and appeared in "What goes into
    /// this" on Fitness only.
    ///
    /// It does not score, and `HeartResponseModel` says at length why: no
    /// validated 0–100 curve exists for it, only a published cut-point. So it
    /// arrives at weight 0 and the weighting section names it as charted rather
    /// than counting it in a footnote.
    public var candidateMetrics: [MetricType] {
        [.vo2Max, .restingHeartRate, .heartRateVariabilityRMSSD,
         .heartRateVariabilitySDNN, .respiratoryRate, .heartRateRecovery]
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

        // Heart health is a *level*, not a moment, so each signal is read as its
        // recent normal rather than its newest sample — one restless night
        // shouldn't move a composite scored against age norms. Freshness isn't
        // gated here (unlike Readiness): VO₂max updates every few weeks by
        // design, and a fortnight-old figure is still the right one.
        //
        // Two bugs this replaces. `latestValue` on HRV returned the newest raw
        // sample, which for a continuously sampled vital is one recent minute.
        // And resting heart rate came from `meanValue` — the mean of every
        // resting-HR sample ever recorded, which over a 180-day lookback is
        // effectively frozen: real improvement moved it by a fraction of a beat,
        // so the score could not reflect one.
        let vo2 = VitalReader.reading(.vo2Max, from: samples, now: now)?.value
        let rhrReading = VitalReader.reading(.restingHeartRate, from: samples, now: now)
        let restHR = rhrReading.map { $0.baseline ?? $0.value }
        // Track which flavour was used, so the chart plots the series the score
        // actually read rather than whichever one it guesses at.
        let hrvMetric: MetricType = VitalReader.reading(.heartRateVariabilityRMSSD,
                                                        from: samples, now: now) != nil
            ? .heartRateVariabilityRMSSD : .heartRateVariabilitySDNN
        let hrv = VitalReader.reading(hrvMetric, from: samples, now: now)
            .map { $0.baseline ?? $0.value }

        let respDev: Baseline.Deviation? = VitalReader
            .reading(.respiratoryRate, from: samples, now: now)
            .flatMap { (reading: VitalReading) -> Baseline.Deviation? in
                guard let z = reading.zScore, let baseline = reading.baseline else { return nil }
                return Baseline.Deviation(value: reading.value, baseline: baseline, zScore: z,
                                          direction: abs(z) >= 1.5 ? (z > 0 ? 1 : -1) : 0)
            }

        guard let out = HeartHealthScore.evaluate(
            vo2Max: vo2, restingHR: restHR, hrv: hrv, hrvMetric: hrvMetric,
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
        let lines = out.components
            .map { InsightDriver.component("\($0.name): \($0.detail)", score: $0.score) }
        var explanation = "Composite heart-health score of \(Int(out.score.rounded()))/100 (\(band)), from your cardio fitness, resting heart rate and HRV compared with age-adjusted norms."

        // Where You Stand, absorbed. It was a card of its own reading the same
        // three metrics this one already scores — but the *framing* is not a
        // duplicate: a score says how you are doing, a centile says against
        // whom, and this is the only place in the app that compares the user to
        // published population figures rather than to their own baseline.
        //
        // Lines, not score terms. `PeerStandingModel` reads exactly the metrics
        // `HeartHealthScore` has already weighted, so scoring them again would
        // count the same measurements twice.
        var standingLines: [InsightDriver] = []
        if let standing = PeerStandingModel.evaluate(samples: samples, profile: profile, now: now) {
            standingLines = standing.standings
                .sorted { $0.percentile > $1.percentile }
                .map { s in
                    InsightDriver(
                        text: "\(s.metric.displayName) \(MetricValueFormatter.string(s.value, s.metric)) — \(s.phrase) for your age and sex",
                        // The weak ones are what a person would want to look at.
                        isNotable: s.percentile < 40)
                }
            explanation += " Across \(standing.standings.count) measure\(standing.standings.count == 1 ? "" : "s") you sit around the \(Int(standing.overall.rounded()))th centile for people your age and sex — an approximation to published figures, not a lookup into a real distribution — and a centile describes where you sit, not whether anything is wrong."
        }

        // The one measurement this card's own section draws, charted at weight 0
        // beside the four it scores. Read through `VitalReader` on the same
        // window `HeartResponseModel` uses, so the chart cannot show a reading
        // the section beside it has already discarded as too old.
        var contributors = out.contributions
        if let recovery = VitalReader.reading(.heartRateRecovery, from: samples, now: now,
                                              freshWithin: HeartResponseModel.recoveryFreshness) {
            contributors.append(.init(
                metric: .heartRateRecovery, higherIsBetter: true, weight: 0,
                detail: String(format: "−%.0f bpm in the first minute", recovery.value)))
        }

        let all = lines + standingLines
        return InsightResult(
            id: id, title: title, primaryValue: out.score,
            headline: band, score: out.score, confidence: confidence,
            explanation: explanation,
            driverLines: all.filter { $0.isNotable == true } + all.filter { $0.isNotable != true },
            unmetRequirements: unmet, contributors: contributors,
            weighting: .weightedAverage)
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
