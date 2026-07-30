import Foundation

// Shared helpers for the extra insights.
private func notReady(_ id: InsightID, _ title: String, _ message: String) -> InsightResult {
    InsightResult(id: id, title: title, primaryValue: nil, headline: "No data yet",
                  score: nil, confidence: .low, explanation: message,
                  drivers: [], unmetRequirements: [])
}

private func trendWord(recent: Double, baseline: Double, higherIsBetter: Bool) -> String {
    let delta = recent - baseline
    if abs(delta) < 0.5 { return "steady" }
    let rising = delta > 0
    let good = rising == higherIsBetter
    return (rising ? "trending up" : "trending down") + (good ? " (good)" : "")
}

// MARK: - Sleep Quality (daily)

/// Transparent sleep-quality score: duration vs need, night-to-night
/// consistency, and respiratory stability against the personal baseline.
public struct SleepQualityInsight: InsightModel {
    public let id: InsightID = .sleepQuality
    public let title = "Sleep Quality"
    public init() {}
    public var requirements: [GroundingRequirement] { [] }
    public var candidateMetrics: [MetricType] {
        [.sleepDurationHours, .oxygenSaturation, .respiratoryRate, .skinTemperatureDeviation]
    }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult {
        let sleep = samples.samples(of: .sleepDurationHours)
        guard let lastNight = sleep.last?.value else {
            return notReady(id, title, "Connect a sleep source (Oura, Whoop or Apple Health) to see your sleep quality.")
        }
        let durationScore = Self.durationScore(lastNight)

        let recent = Array(sleep.suffix(14).map(\.value))
        let consistencyScore: Double = Baseline.standardDeviation(recent).map { max(0, 100 - $0 * 40) } ?? 60

        let resp = samples.samples(of: .respiratoryRate).map(\.value)
        let respScore: Double = {
            guard resp.count >= 4, let dev = Baseline.deviation(latest: resp.last!, history: Array(resp.dropLast())) else { return 75 }
            return max(0, 90 - min(60, abs(dev.zScore ?? 0) * 20))
        }()

        // Overnight blood oxygen. Saturation dipping through the night is the
        // clearest non-invasive marker of disrupted breathing during sleep, and
        // it was being collected and ignored. Neutral 75 when absent, so nights
        // without a reading aren't penalised.
        let spo2 = samples.samples(of: .oxygenSaturation).map(\.value)
        let oxygenScore: Double = {
            guard let latest = spo2.last else { return 75 }
            switch latest {
            case 96...: return 100
            case 94..<96: return 82
            case 92..<94: return 60
            default: return 35
            }
        }()

        // Skin temperature away from baseline disturbs sleep and marks the
        // night an illness or a heavy drink starts.
        let tempScore: Double = {
            guard let dev = samples.latestValue(.skinTemperatureDeviation) else { return 75 }
            return max(20, 95 - min(70, abs(dev) * 55))
        }()

        let score = durationScore * 0.45 + consistencyScore * 0.2 + respScore * 0.1
            + oxygenScore * 0.15 + tempScore * 0.1
        let band = Self.band(score)
        var drivers = [String(format: "Last night: %.1f h", lastNight),
                       "Consistency: \(Int(consistencyScore))/100"]
        if !resp.isEmpty { drivers.append(String(format: "Respiratory rate: %.0f br/min", resp.last!)) }
        if let latest = spo2.last {
            drivers.append(String(format: "Blood oxygen: %.0f%%%@", latest,
                                  latest < 94 ? " — lower than a settled night usually looks" : ""))
        }
        if let dev = samples.latestValue(.skinTemperatureDeviation) {
            drivers.append(String(format: "Skin temperature: %+.1f °C vs your baseline", dev))
        }

        // Only metrics that actually had a reading become contributions — the
        // neutral 75s above are placeholders for absent data, not measurements,
        // and charting them would draw a line out of nothing. Duration and
        // consistency are one line: they read the same metric, so their weights
        // merge rather than plotting sleep twice.
        var contributors = [MetricContribution(
            metric: .sleepDurationHours, higherIsBetter: true, weight: 0.65,
            detail: String(format: "%.1f h", lastNight))]
        if let latest = spo2.last {
            contributors.append(.init(metric: .oxygenSaturation, higherIsBetter: true,
                                      weight: 0.15, detail: String(format: "%.0f%%", latest)))
        }
        if let latest = resp.last {
            contributors.append(.init(metric: .respiratoryRate, higherIsBetter: false,
                                      weight: 0.10, detail: String(format: "%.0f br/min", latest)))
        }
        if let dev = samples.latestValue(.skinTemperatureDeviation) {
            contributors.append(.init(metric: .skinTemperatureDeviation, higherIsBetter: nil,
                                      weight: 0.10, detail: String(format: "%+.1f °C", dev)))
        }

        let confidence: InsightConfidence = sleep.count >= 5 ? .high : .moderate
        return InsightResult(
            id: id, title: title, primaryValue: score, headline: band, score: score,
            confidence: confidence,
            explanation: "Sleep quality \(Int(score.rounded()))/100 (\(band)) — from last night's \(String(format: "%.1f", lastNight)) hours, how consistent your recent nights are, and your breathing, blood oxygen and skin temperature through the night.",
            drivers: drivers, unmetRequirements: [], contributors: contributors)
    }

    static func durationScore(_ h: Double) -> Double {
        switch h {
        case 7.5...9: return 100
        case 7..<7.5, 9..<9.5: return 85
        case 6..<7, 9.5..<10: return 65
        case 5..<6: return 45
        default: return 30
        }
    }
    static func band(_ s: Double) -> String {
        switch s { case 80...: return "Excellent"; case 65..<80: return "Good"
        case 50..<65: return "Fair"; default: return "Poor" }
    }
}

// MARK: - Cardio Fitness (trend)

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
        let vo2Series = samples.samples(of: .vo2Max)
        let unmet = unmetRequirements(profile: profile, now: now)
        guard let vo2 = vo2Series.last?.value, let age = profile.age(asOf: now), let sex = profile.sex else {
            return InsightResult(id: id, title: title, primaryValue: nil, headline: "Add details",
                score: nil, confidence: .low,
                explanation: "Add your age and sex, and record cardio fitness (VO₂max) via Apple Watch, to see your fitness level.",
                drivers: [], unmetRequirements: unmet)
        }
        let score = HeartHealthScore.vo2Score(vo2, age: age, sex: sex)
        let level = Self.level(score)
        var drivers = [String(format: "VO₂max: %.0f mL/kg·min", vo2)]
        if vo2Series.count >= 3 {
            let older = Array(vo2Series.dropLast().map(\.value))
            if let base = Baseline.mean(older) {
                drivers.append("Trend: \(trendWord(recent: vo2, baseline: base, higherIsBetter: true))")
            }
        }
        return InsightResult(
            id: id, title: title, primaryValue: vo2, headline: level, score: score,
            confidence: vo2Series.count >= 3 ? .high : .moderate,
            explanation: "Your cardio fitness (VO₂max \(Int(vo2.rounded()))) is \(level.lowercased()) for your age and sex. Higher VO₂max is one of the strongest predictors of long-term heart health.",
            drivers: drivers, unmetRequirements: unmet)
    }
    static func level(_ s: Double) -> String {
        switch s { case 80...: return "Excellent"; case 60..<80: return "Good"
        case 40..<60: return "Average"; default: return "Below average" }
    }
}

// MARK: - Body Composition (trend)

/// BMI from weight + height, plus weight and body-fat trends.
public struct BodyCompositionInsight: InsightModel {
    public let id: InsightID = .bodyComposition
    public let title = "Body Composition"
    public init() {}
    public var candidateMetrics: [MetricType] {
        [.bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass, .boneMass,
         .bodyWaterPercentage, .height]
    }
    public var requirements: [GroundingRequirement] { [] }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult {
        let weightSeries = samples.samples(of: .bodyMass)
        guard let weight = weightSeries.last?.value else {
            return notReady(id, title, "Connect a scale (Withings) or Apple Health to track weight, BMI and body fat.")
        }
        let height = samples.latestValue(.height)
        var drivers: [String] = [String(format: "Weight: %.1f kg", weight)]
        var headline = String(format: "%.1f kg", weight)
        var primary = weight
        var explanation = "Your latest weight is \(String(format: "%.1f", weight)) kg."

        if let h = height, h > 0.5 {
            let bmi = weight / (h * h)
            let cat = Self.bmiCategory(bmi)
            headline = String(format: "BMI %.1f", bmi)
            primary = bmi
            drivers.insert(String(format: "BMI: %.1f (%@)", bmi, cat), at: 0)
            explanation = "Your BMI is \(String(format: "%.1f", bmi)) (\(cat)), from \(String(format: "%.1f", weight)) kg at \(String(format: "%.2f", h)) m."
        } else {
            drivers.append("Add your height to calculate BMI")
        }
        if let bodyFat = samples.latestValue(.bodyFatPercentage) {
            drivers.append(String(format: "Body fat: %.1f%%", bodyFat))
        }
        if weightSeries.count >= 3, let base = Baseline.mean(Array(weightSeries.dropLast().map(\.value))) {
            drivers.append("Weight \(trendWord(recent: weight, baseline: base, higherIsBetter: false))")
        }

        // The rest of what a body-composition scale actually measures. These
        // were being imported and charted but read by nothing — and they are
        // the part that distinguishes losing fat from losing muscle, which is
        // the only interesting question behind a change in weight.
        for (metric, label, higherIsBetter) in [
            (MetricType.leanBodyMass, "Lean mass", true),
            (MetricType.muscleMass, "Muscle mass", true),
            (MetricType.boneMass, "Bone mass", true),
            (MetricType.bodyWaterPercentage, "Body water", true)
        ] {
            let series = samples.samples(of: metric)
            guard let latest = series.last?.value else { continue }
            let unit = metric.unit
            var line = String(format: "%@: %.1f%@", label, latest, unit.isEmpty ? "" : " \(unit)")
            if series.count >= 3,
               let base = Baseline.mean(Array(series.dropLast().map(\.value))) {
                line += " (\(trendWord(recent: latest, baseline: base, higherIsBetter: higherIsBetter)))"
            }
            drivers.append(line)
        }

        // Weight moving while lean mass holds is fat loss; both falling
        // together is not, and that distinction is worth saying out loud.
        if let composition = Self.compositionNarrative(samples: samples, weightSeries: weightSeries) {
            drivers.append(composition)
            explanation += " " + composition
        }

        return InsightResult(
            id: id, title: title, primaryValue: primary, headline: headline, score: nil,
            confidence: height == nil ? .moderate : .high,
            explanation: explanation, drivers: drivers, unmetRequirements: [])
    }

    /// Reads the direction of weight change against lean mass.
    static func compositionNarrative(samples: [HealthMetricSample],
                                     weightSeries: [HealthMetricSample]) -> String? {
        let lean = samples.samples(of: .leanBodyMass)
        guard weightSeries.count >= 3, lean.count >= 3,
              let weightNow = weightSeries.last?.value,
              let leanNow = lean.last?.value,
              let weightBase = Baseline.mean(Array(weightSeries.dropLast().map(\.value))),
              let leanBase = Baseline.mean(Array(lean.dropLast().map(\.value))) else { return nil }
        let weightDelta = weightNow - weightBase
        let leanDelta = leanNow - leanBase
        guard abs(weightDelta) >= 0.5 else {
            return abs(leanDelta) >= 0.4
                ? "Weight is steady while lean mass is \(leanDelta > 0 ? "rising" : "falling") — a recomposition, not a gain or loss."
                : nil
        }
        if weightDelta < 0 {
            return leanDelta >= -0.2
                ? "Weight is down and lean mass is holding — the loss is coming from fat."
                : "Weight and lean mass are falling together — some of the loss is muscle."
        }
        return leanDelta > 0.2
            ? "Weight is up and so is lean mass — the gain isn't only fat."
            : "Weight is up with lean mass flat — the gain is mostly fat."
    }
    static func bmiCategory(_ bmi: Double) -> String {
        switch bmi { case ..<18.5: return "underweight"; case 18.5..<25: return "healthy"
        case 25..<30: return "overweight"; default: return "obese" }
    }
}

// MARK: - Resting Heart Rate Trend (trend)

/// Where resting heart rate is heading vs the personal baseline — a sensitive
/// early signal of fitness gains, or of strain/illness when it rises.
public struct RestingHeartRateTrendInsight: InsightModel {
    public let id: InsightID = .restingHeartRateTrend
    public let title = "Resting Heart Rate"
    public init() {}
    public var candidateMetrics: [MetricType] { [.restingHeartRate] }
    public var requirements: [GroundingRequirement] { [] }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult {
        let series = samples.samples(of: .restingHeartRate).map(\.value)
        guard let latest = series.last else {
            return notReady(id, title, "Connect a wearable or Apple Health to track resting heart rate.")
        }
        guard series.count >= 4, let dev = Baseline.deviation(latest: latest, history: Array(series.dropLast())) else {
            return InsightResult(id: id, title: title, primaryValue: latest,
                headline: "\(Int(latest.rounded())) bpm", score: nil, confidence: .low,
                explanation: "Latest resting heart rate is \(Int(latest.rounded())) bpm. A few more days of data will reveal your trend.",
                drivers: ["Latest: \(Int(latest.rounded())) bpm"], unmetRequirements: [])
        }
        let direction: String
        switch dev.direction {
        case 1: direction = "elevated vs your baseline — often strain, poor sleep or illness"
        case -1: direction = "below your baseline — usually a good sign of recovery/fitness"
        default: direction = "in your normal range"
        }
        return InsightResult(
            id: id, title: title, primaryValue: latest, headline: "\(Int(latest.rounded())) bpm",
            score: nil, confidence: .high,
            explanation: "Resting heart rate \(Int(latest.rounded())) bpm — \(direction).",
            drivers: [String(format: "Baseline: %.0f bpm", dev.baseline),
                      dev.zScore.map { String(format: "%.1f SD from baseline", $0) } ?? "Within range"],
            unmetRequirements: [])
    }
}
