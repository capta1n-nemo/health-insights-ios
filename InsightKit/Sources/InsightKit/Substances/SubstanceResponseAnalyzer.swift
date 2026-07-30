import Foundation

/// Turns a log of substance-use events + the user's biometrics into an honest,
/// personal picture of how their body responds — the thing generic wearables
/// won't tell you. It compares nights that *followed* use against the user's
/// clean-night baseline (resting HR, HRV, temperature, sleep, respiration), and
/// summarises recent cumulative cardiovascular load.
///
/// Framing is deliberate: descriptive, non-judgemental, harm-reduction. It never
/// tells anyone whether or how to use anything; it reflects their own data back
/// and flags when the body's response looks concerning enough to see a clinician.
public enum SubstanceResponseAnalyzer {

    /// How long after an event a night's biometrics are considered "affected".
    public static let afterWindow: TimeInterval = 18 * 3600
    /// Window for the cumulative recent-load indicator.
    public static let loadWindowDays = 14

    public struct MetricEffect: Sendable, Equatable {
        public let metric: MetricType
        public let baseline: Double
        public let afterUse: Double
        public let deltaAbsolute: Double     // afterUse − baseline
        public let deltaPercent: Double      // relative to baseline
        public let affectedNights: Int
        public let baselineNights: Int
        /// True when the change is in the physiologically-worse direction.
        public let isAdverse: Bool
    }

    public struct Analysis: Sendable, Equatable {
        public let effects: [MetricEffect]
        /// 0–100 indicator of recent cumulative cardiovascular load from logged use.
        public let recentLoad: Double
        public let loadBand: String
        public let eventsInWindow: Int
    }

    /// Metrics we look at, with whether "up" is the adverse direction.
    private static let watched: [(MetricType, upIsAdverse: Bool)] = [
        (.restingHeartRate, true),
        (.heartRateVariabilityRMSSD, false),
        (.heartRateVariabilitySDNN, false),
        (.skinTemperatureDeviation, true),
        (.sleepDurationHours, false),
        (.respiratoryRate, true)
    ]

    public static func analyze(events: [SubstanceEvent], samples: [HealthMetricSample], now: Date = Date()) -> Analysis {
        var effects: [MetricEffect] = []
        for (metric, upIsAdverse) in watched {
            if let e = effect(for: metric, upIsAdverse: upIsAdverse, events: events, samples: samples) {
                effects.append(e)
            }
        }
        // Keep at most one HRV effect (whichever source produced one).
        if effects.filter({ $0.metric == .heartRateVariabilityRMSSD || $0.metric == .heartRateVariabilitySDNN }).count > 1 {
            if let first = effects.firstIndex(where: { $0.metric == .heartRateVariabilitySDNN }) {
                effects.remove(at: first)
            }
        }

        let (load, band, count) = recentLoad(events: events, now: now)
        return Analysis(effects: effects, recentLoad: load, loadBand: band, eventsInWindow: count)
    }

    static func effect(for metric: MetricType, upIsAdverse: Bool,
                       events: [SubstanceEvent], samples: [HealthMetricSample]) -> MetricEffect? {
        let series = samples.samples(of: metric)
        guard series.count >= 5 else { return nil }
        let times = events.map(\.timestamp)

        var affected: [Double] = []
        var baseline: [Double] = []
        for sample in series {
            let follows = times.contains { t in
                let dt = sample.start.timeIntervalSince(t)
                return dt >= 0 && dt <= afterWindow
            }
            if follows { affected.append(sample.value) } else { baseline.append(sample.value) }
        }
        guard affected.count >= 2, baseline.count >= 3,
              let a = Baseline.mean(affected), let b = Baseline.mean(baseline), b != 0 else { return nil }

        let deltaAbs = a - b
        let deltaPct = deltaAbs / abs(b) * 100
        let adverse = upIsAdverse ? deltaAbs > 0 : deltaAbs < 0
        return MetricEffect(metric: metric, baseline: b, afterUse: a,
                            deltaAbsolute: deltaAbs, deltaPercent: deltaPct,
                            affectedNights: affected.count, baselineNights: baseline.count,
                            isAdverse: adverse)
    }

    static func recentLoad(events: [SubstanceEvent], now: Date) -> (Double, String, Int) {
        let cutoff = now.addingTimeInterval(-Double(loadWindowDays) * 24 * 3600)
        let recent = events.filter { $0.timestamp >= cutoff }
        // Weighted sum of acute cardiac load, saturating around a "heavy" fortnight.
        let raw = recent.reduce(0.0) { $0 + $1.substance.acuteCardiacLoad }
        let load = min(100, raw / 8.0 * 100)   // ~8 weighted units over 2 weeks → 100
        let band: String
        switch load {
        case ..<20: return (load, "light", recent.count)
        case ..<50: band = "moderate"
        case ..<80: band = "considerable"
        default: band = "high"
        }
        return (load, band, recent.count)
    }

    /// The metrics this analyser compares before and after logged use — the
    /// substance equivalent of an insight's `candidateMetrics`.
    public static let comparedMetrics: [MetricType] = [
        .restingHeartRate, .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN,
        .sleepDurationHours, .skinTemperatureDeviation, .respiratoryRate
    ]

    static func higherIsBetter(_ metric: MetricType) -> Bool? {
        switch metric {
        case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN, .sleepDurationHours:
            return true
        case .restingHeartRate, .respiratoryRate:
            return false
        default:
            return nil   // skin-temp deviation: nearest baseline is best
        }
    }

    // MARK: - Insight surface

    /// Build a dashboard-ready `InsightResult` from an analysis.
    public static func insightResult(events: [SubstanceEvent], samples: [HealthMetricSample], now: Date = Date()) -> InsightResult {
        let id = InsightID.substanceImpact
        let title = "Substance Impact"

        guard !events.isEmpty else {
            return InsightResult(
                id: id, title: title, primaryValue: nil, headline: "Log to see effects",
                score: nil, confidence: .low,
                explanation: "Log alcohol, nicotine, caffeine or other substances and this will show — privately, without judgement — how your own heart rate, HRV, sleep and temperature actually respond.",
                drivers: [], unmetRequirements: [])
        }

        let analysis = analyze(events: events, samples: samples, now: now)

        // A response in the unwanted direction is the finding; one the other way
        // is worth keeping but not worth leading with.
        var drivers: [InsightDriver] = []
        for e in analysis.effects {
            let arrow = e.deltaAbsolute >= 0 ? "+" : "−"
            // `isAdverse` is already decided when the effect is measured, against
            // the same watched-metric table — recomputing it here would be a
            // second opinion that could drift from the first.
            let text: String?
            switch e.metric {
            case .restingHeartRate:
                text = String(format: "Resting HR %@%.0f bpm after use", arrow, abs(e.deltaAbsolute))
            case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN:
                text = String(format: "HRV %@%.0f%% after use", e.deltaPercent >= 0 ? "+" : "−", abs(e.deltaPercent))
            case .skinTemperatureDeviation:
                text = String(format: "Body temp %@%.1f °C after use", arrow, abs(e.deltaAbsolute))
            case .sleepDurationHours:
                text = String(format: "Sleep %@%.1f h after use", arrow, abs(e.deltaAbsolute))
            case .respiratoryRate:
                text = String(format: "Respiration %@%.1f br/min after use", arrow, abs(e.deltaAbsolute))
            default: text = nil
            }
            if let text { drivers.append(InsightDriver(text: text, isNotable: e.isAdverse)) }
        }
        drivers.append(InsightDriver(
            text: "Recent cardiovascular load: \(analysis.loadBand) (\(analysis.eventsInWindow) logs in \(loadWindowDays) days)",
            isNotable: analysis.recentLoad >= 50))

        // Headline: the most salient adverse effect if any, else the load band.
        let headline: String
        if let rhr = analysis.effects.first(where: { $0.metric == .restingHeartRate }) {
            headline = String(format: "HR %@%.0f after use", rhr.deltaAbsolute >= 0 ? "+" : "−", abs(rhr.deltaAbsolute))
        } else {
            headline = "\(analysis.loadBand.capitalized) load"
        }

        // Confidence scales with how much paired data we had.
        let hasEffects = !analysis.effects.isEmpty
        let confidence: InsightConfidence = hasEffects
            ? (analysis.effects.allSatisfy { $0.affectedNights >= 3 } ? .moderate : .low)
            : .low

        var explanation: String
        if hasEffects {
            explanation = "Compared with your substance-free nights, here's how your body has responded after logged use. This is your own pattern — not medical advice."
        } else {
            explanation = "You've logged use, but there isn't enough paired biometric data yet to show reliable before/after differences. Keep your wearable synced."
        }
        // Safety flag for a large stimulant/heart response.
        let bigHR = analysis.effects.contains { $0.metric == .restingHeartRate && $0.deltaAbsolute >= 12 }
        if bigHR || analysis.recentLoad >= 80 {
            explanation += " Your heart is showing a notable response — if your heart rate stays high, or you feel palpitations, chest pain or breathlessness, please seek medical care."
        }

        // Weight 0: the load figure isn't a weighted blend of these, they're the
        // signals the before/after comparison was measured on.
        let contributors = analysis.effects.map { effect in
            MetricContribution(
                metric: effect.metric,
                higherIsBetter: Self.higherIsBetter(effect.metric),
                weight: 0,
                detail: String(format: "%@%.1f after use",
                               effect.deltaAbsolute >= 0 ? "+" : "−", abs(effect.deltaAbsolute)))
        }

        return InsightResult(
            id: id, title: title, primaryValue: analysis.recentLoad,
            headline: headline, score: nil, confidence: confidence,
            explanation: explanation,
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: [],
            contributors: contributors)
    }
}
