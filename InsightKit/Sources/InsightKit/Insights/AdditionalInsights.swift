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

/// Whether a `trendWord` phrase describes movement in the unwanted direction.
///
/// `trendWord` appends "(good)" when the direction is the favourable one, so
/// anything moving and *not* marked good is what a card should lead with.
private func isAdverseTrend(_ word: String) -> Bool {
    word != "steady" && !word.contains("(good)")
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
        // One value per night, de-duplicated across devices. Previously this read
        // raw samples, so a nap counted as a night and a second source counted
        // the same night twice — which is what drove the consistency score to
        // zero: the spread it measured was fragmentation, not sleep.
        guard let sleepReading = VitalReader.reading(.sleepDurationHours, from: samples,
                                                     now: now, freshWithin: 36 * 3600) else {
            return notReady(id, title, "Connect a sleep source (Oura, Whoop or Apple Health) to see your sleep quality.")
        }
        let lastNight = sleepReading.value
        let durationScore = Self.durationScore(lastNight)
        // A night older than the freshness window is still worth showing, but it
        // is not "last night" and the card shouldn't imply it is.
        let nightsAgo = Swift.max(0, Int((now.timeIntervalSince(sleepReading.date) / 86_400).rounded(.down)))
        let nightLabel = sleepReading.isFresh ? "Last night"
            : "Last recorded night (\(nightsAgo) days ago)"

        let nightly = VitalReader.dailyValues(.sleepDurationHours, from: samples,
                                              days: 14, now: now)
        // Needs a few nights before night-to-night spread means anything; below
        // that it's a neutral figure rather than a damning one.
        let consistencyScore: Double = nightly.count >= 4
            ? (Baseline.standardDeviation(nightly).map { max(0, 100 - $0 * 40) } ?? 60)
            : 60

        // The night's respiratory rate, not the last ten minutes. Wearables
        // report a nightly figure, but daytime readings land in the same series
        // and `last` was picking whichever arrived most recently — often a
        // waking measurement that says nothing about the night.
        let respReading = VitalReader.reading(.respiratoryRate, from: samples, now: now)
        let respScore: Double = {
            guard let dev = respReading?.zScore else { return 75 }
            return max(0, 90 - min(60, abs(dev) * 20))
        }()

        // Overnight blood oxygen. Saturation dipping through the night is the
        // clearest non-invasive marker of disrupted breathing during sleep, and
        // it was being collected and ignored. Neutral 75 when absent, so nights
        // without a reading aren't penalised.
        let spo2Reading = VitalReader.reading(.oxygenSaturation, from: samples, now: now)
        let oxygenScore: Double = {
            guard let latest = spo2Reading?.value else { return 75 }
            switch latest {
            case 96...: return 100
            case 94..<96: return 82
            case 92..<94: return 60
            default: return 35
            }
        }()

        // Skin temperature away from baseline disturbs sleep and marks the
        // night an illness or a heavy drink starts.
        let tempReading = VitalReader.reading(.skinTemperatureDeviation, from: samples, now: now)
        let tempScore: Double = {
            guard let dev = tempReading?.value else { return 75 }
            return max(20, 95 - min(70, abs(dev) * 55))
        }()

        let score = durationScore * 0.45 + consistencyScore * 0.2 + respScore * 0.1
            + oxygenScore * 0.15 + tempScore * 0.1
        let band = Self.band(score)
        // Each line classified by the sub-score behind it, so the detail card
        // leads with whatever cost the night its marks.
        var drivers = [
            InsightDriver.component(nightLabel + String(format: ": %.1f h", lastNight),
                                    score: durationScore),
            InsightDriver.component("Consistency: \(Int(consistencyScore))/100",
                                    score: consistencyScore)
        ]
        if let latest = respReading?.value {
            drivers.append(.component(String(format: "Respiratory rate: %.0f br/min", latest),
                                      score: respScore))
        }
        if let latest = spo2Reading?.value {
            drivers.append(.component(String(format: "Blood oxygen: %.0f%%%@", latest,
                                             latest < 94 ? " — lower than a settled night usually looks" : ""),
                                      score: oxygenScore))
        }
        if let dev = tempReading?.value {
            drivers.append(.component(String(format: "Skin temperature: %+.1f °C vs your baseline", dev),
                                      score: tempScore))
        }

        // Only metrics that actually had a reading become contributions — the
        // neutral 75s above are placeholders for absent data, not measurements,
        // and charting them would draw a line out of nothing.
        //
        // Five components, four metrics: consistency is the night-to-night
        // spread *of the sleep series itself*, not a separate measurement, so it
        // shares sleep's line rather than inventing a fifth. Its weight is folded
        // in and the detail names it, so the 20% isn't unaccounted for.
        var contributors = [MetricContribution(
            metric: .sleepDurationHours, higherIsBetter: true, weight: 0.65,
            detail: String(format: "%.1f h · consistency %d/100",
                           lastNight, Int(consistencyScore)))]
        if let latest = spo2Reading?.value {
            contributors.append(.init(metric: .oxygenSaturation, higherIsBetter: true,
                                      weight: 0.15, detail: String(format: "%.0f%%", latest)))
        }
        if let latest = respReading?.value {
            contributors.append(.init(metric: .respiratoryRate, higherIsBetter: false,
                                      weight: 0.10, detail: String(format: "%.0f br/min", latest)))
        }
        if let dev = tempReading?.value {
            contributors.append(.init(metric: .skinTemperatureDeviation, higherIsBetter: nil,
                                      weight: 0.10, detail: String(format: "%+.1f °C", dev)))
        }

        // A stale night can't buy high confidence however long the history is.
        let confidence: InsightConfidence = (nightly.count >= 5 && sleepReading.isFresh)
            ? .high : .moderate
        return InsightResult(
            id: id, title: title, primaryValue: score, headline: band, score: score,
            confidence: confidence,
            explanation: "Sleep quality \(Int(score.rounded()))/100 (\(band)) — from last night's \(String(format: "%.1f", lastNight)) hours, how consistent your recent nights are, and your breathing, blood oxygen and skin temperature through the night.",
            driverLines: drivers.filter { $0.isNotable == true } + drivers.filter { $0.isNotable != true },
            unmetRequirements: [], contributors: contributors)
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
        var drivers = [InsightDriver.component(String(format: "VO₂max: %.0f mL/kg·min", vo2),
                                               score: score)]
        if vo2Series.count >= 3 {
            let older = Array(vo2Series.dropLast().map(\.value))
            if let base = Baseline.mean(older) {
                let word = trendWord(recent: vo2, baseline: base, higherIsBetter: true)
                // A trend is only worth leading with when it's the wrong way.
                drivers.append(InsightDriver(text: "Trend: \(word)",
                                             isNotable: word.contains("down") && !word.contains("good")))
            }
        }
        return InsightResult(
            id: id, title: title, primaryValue: vo2, headline: level, score: score,
            confidence: vo2Series.count >= 3 ? .high : .moderate,
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
        // Measurements are context; a direction that isn't the good one, and the
        // fat-versus-muscle reading, are the findings.
        var drivers: [InsightDriver] = [.routine(String(format: "Weight: %.1f kg", weight))]
        var headline = String(format: "%.1f kg", weight)
        var primary = weight
        var explanation = "Your latest weight is \(String(format: "%.1f", weight)) kg."

        if let h = height, h > 0.5 {
            let bmi = weight / (h * h)
            let cat = Self.bmiCategory(bmi)
            headline = String(format: "BMI %.1f", bmi)
            primary = bmi
            drivers.insert(InsightDriver(text: String(format: "BMI: %.1f (%@)", bmi, cat),
                                         isNotable: cat != "healthy"), at: 0)
            explanation = "Your BMI is \(String(format: "%.1f", bmi)) (\(cat)), from \(String(format: "%.1f", weight)) kg at \(String(format: "%.2f", h)) m."
        } else {
            // Something the user can act on, so it doesn't get folded away.
            drivers.append(.notable("Add your height to calculate BMI"))
        }
        if let bodyFat = samples.latestValue(.bodyFatPercentage) {
            drivers.append(.routine(String(format: "Body fat: %.1f%%", bodyFat)))
        }
        if weightSeries.count >= 3, let base = Baseline.mean(Array(weightSeries.dropLast().map(\.value))) {
            let word = trendWord(recent: weight, baseline: base, higherIsBetter: false)
            drivers.append(InsightDriver(text: "Weight \(word)", isNotable: isAdverseTrend(word)))
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
            var adverse = false
            if series.count >= 3,
               let base = Baseline.mean(Array(series.dropLast().map(\.value))) {
                let word = trendWord(recent: latest, baseline: base, higherIsBetter: higherIsBetter)
                line += " (\(word))"
                adverse = isAdverseTrend(word)
            }
            drivers.append(InsightDriver(text: line, isNotable: adverse))
        }

        // Weight moving while lean mass holds is fat loss; both falling
        // together is not, and that distinction is worth saying out loud — and
        // is the one line here that is genuinely a finding.
        if let composition = Self.compositionNarrative(samples: samples, weightSeries: weightSeries) {
            drivers.insert(.notable(composition), at: 0)
            explanation += " " + composition
        }

        // Every body measurement that actually reported, evenly weighted: this
        // insight narrates rather than scores, so no share of a score is claimed.
        let present = candidateMetrics.filter { samples.latestValue($0) != nil }
        return InsightResult(
            id: id, title: title, primaryValue: primary, headline: headline, score: nil,
            confidence: height == nil ? .moderate : .high,
            explanation: explanation,
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: [],
            contributors: present.map { metric in
                let unit = metric.unit
                return .init(metric: metric,
                             higherIsBetter: metric == .bodyFatPercentage ? false : nil,
                             weight: 0,
                             detail: String(format: "%.1f%@", samples.latestValue(metric) ?? 0,
                                            unit.isEmpty ? "" : " \(unit)"))
            })
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

    /// Where the card's dial sits, from two things that both matter and can
    /// disagree: today's departure from your own baseline, and which way the
    /// last few weeks are heading. A single high morning after a late night is
    /// not the same finding as a month of steady upward drift, and a card that
    /// only read one of them would call them the same.
    ///
    /// Lower is better throughout, so both terms are negated.
    static func score(z: Double?, weeklyDrift: Double?) -> Double? {
        guard z != nil || weeklyDrift != nil else { return nil }
        // z of 0 → 70 (an ordinary day); a full SD below baseline → 90.
        let level = z.map { max(0, min(100, 70 - $0 * 20)) } ?? 70
        // ±1 bpm/week is a large drift for resting heart rate; ±2 is the cap.
        let drift = weeklyDrift.map { max(0, min(100, 70 - $0 * 15)) } ?? level
        return level * 0.6 + drift * 0.4
    }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult {
        // Daily, de-duplicated, windowed — resting heart rate arrives from more
        // than one device for most users, and the raw series carries several
        // readings a day. See `VitalReader`.
        guard let reading = VitalReader.reading(.restingHeartRate, from: samples, now: now) else {
            return notReady(id, title, "Connect a wearable or Apple Health to track resting heart rate.")
        }
        let latest = reading.value
        guard let z = reading.zScore, let baseline = reading.baseline else {
            return InsightResult(id: id, title: title, primaryValue: latest,
                headline: "\(Int(latest.rounded())) bpm", score: nil, confidence: .low,
                explanation: "Latest resting heart rate is \(Int(latest.rounded())) bpm. A few more days of data will reveal your trend.",
                drivers: ["Latest: \(Int(latest.rounded())) bpm"], unmetRequirements: [])
        }

        // Drift across the baseline window, in bpm per week — the trend the card
        // is named for, which a single day's z-score cannot express.
        let daily = reading.history + [latest]
        let weeklyDrift = Baseline.linearRegression(x: (0..<daily.count).map(Double.init),
                                                    y: daily).map { $0.slope * 7 }

        let direction: String
        switch abs(z) >= 1.5 ? (z > 0 ? 1 : -1) : 0 {
        case 1: direction = "elevated vs your baseline — often strain, poor sleep or illness"
        case -1: direction = "below your baseline — usually a good sign of recovery/fitness"
        default: direction = "in your normal range"
        }

        var lines = [
            InsightDriver(text: String(format: "%.1f SD from baseline", z),
                          isNotable: abs(z) >= 1.5)
        ]
        if let drift = weeklyDrift, abs(drift) >= 0.2 {
            lines.append(InsightDriver(
                text: String(format: "Trending %@ %.1f bpm per week over the last %d days",
                             drift > 0 ? "up" : "down", abs(drift), daily.count),
                // Drifting up is the finding; drifting down is good news and
                // belongs with the routine lines rather than the alarms.
                isNotable: drift > 0))
        }
        // The baseline itself is context you'd look up only if you cared.
        lines.append(.routine(String(format: "Baseline: %.0f bpm", baseline)))
        if !reading.isFresh {
            let daysAgo = max(1, Int(now.timeIntervalSince(reading.date) / 86_400))
            lines.insert(.notable("Last measured \(daysAgo) days ago"), at: 0)
        }

        return InsightResult(
            id: id, title: title, primaryValue: latest, headline: "\(Int(latest.rounded())) bpm",
            score: Self.score(z: z, weeklyDrift: weeklyDrift),
            confidence: reading.isFresh ? .high : .moderate,
            explanation: "Resting heart rate \(Int(latest.rounded())) bpm — \(direction).",
            driverLines: lines.filter { $0.isNotable == true } + lines.filter { $0.isNotable != true },
            unmetRequirements: [],
            contributors: [.init(metric: .restingHeartRate, higherIsBetter: false, weight: 1,
                                 detail: "\(Int(latest.rounded())) bpm")])
    }
}
