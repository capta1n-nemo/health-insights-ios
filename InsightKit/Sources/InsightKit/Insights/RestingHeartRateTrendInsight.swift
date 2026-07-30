import Foundation

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
