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
    /// Weighted units over `loadWindowDays` that saturate the load indicator.
    public static let loadSaturationUnits = 8.0

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
        /// Spread of the clean-night baseline this delta is judged against.
        public let baselineSD: Double

        /// The delta in baseline standard deviations.
        ///
        /// nil when the baseline had no spread to divide by — a delta against a
        /// flat baseline is unjudgeable, not infinitely severe.
        public var effectSize: Double? {
            baselineSD > 0 ? abs(deltaAbsolute) / baselineSD : nil
        }
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
                            isAdverse: adverse,
                            baselineSD: Baseline.standardDeviation(baseline) ?? 0)
    }

    /// The word for a load figure.
    ///
    /// Shared, so the fortnight count and the daily series can never band the
    /// same number differently.
    public static func band(for load: Double) -> String {
        switch load {
        case ..<20: return "light"
        case ..<50: return "moderate"
        case ..<80: return "considerable"
        default: return "high"
        }
    }

    /// Today's load, the count behind it, and the word for it.
    ///
    /// The count still says "N logs in `loadWindowDays` days" — a plain fact
    /// about the log, unchanged. The *load* is now the decaying figure from
    /// `SubstanceLoad`, so the number on the card and the line on its chart are
    /// one quantity rather than two takes on it. This does move the number on
    /// real data: a heavy weekend peaks higher and then tails off, where before
    /// it held flat for a fortnight and vanished overnight.
    static func recentLoad(events: [SubstanceEvent], now: Date) -> (Double, String, Int) {
        let cutoff = now.addingTimeInterval(-Double(loadWindowDays) * 24 * 3600)
        let visible = events.filter { $0.timestamp <= now }
        let count = visible.filter { $0.timestamp >= cutoff }.count
        let load = SubstanceLoad.load(events: visible, at: now)
        return (load, band(for: load), count)
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

    // MARK: - The dial

    /// How far an adverse response must move to count as a full-strength
    /// finding — measured in the user's *own* baseline spread rather than in
    /// invented per-metric thresholds. A 4 bpm shift means one thing for someone
    /// whose clean-night resting heart rate varies by 2, and another for someone
    /// it varies by 8; a fixed table cannot tell them apart.
    static let fullStrengthEffectSize = 2.0

    static func severity(_ effect: MetricEffect) -> Double {
        guard effect.isAdverse, let size = effect.effectSize else { return 0 }
        return Swift.min(100, size / fullStrengthEffectSize * 100)
    }

    /// 0–100, higher is better — the same direction as every other dial in the
    /// app, including Cardiovascular *Risk*, which maps low risk to a high score.
    /// A raw load passed straight through would paint a heavy fortnight green.
    ///
    /// Worst-offender-dominant, using the identical combiner `VitalSignsCheck`
    /// applies to its penalty pool: one large heart-rate response is the finding
    /// and must not be averaged away by five signals that didn't move, while a
    /// week where everything shifted a little still scores below a clean one. The
    /// fortnight's load enters the same pool as a penalty in its own right, so
    /// heavy use scores low before any biometric response is even measurable.
    ///
    /// nil for an empty log — no dial, and the card stays hidden.
    static func score(load: Double, effects: [MetricEffect]) -> Double? {
        guard !effects.isEmpty || load > 0 else { return nil }
        var penalties = effects.map(severity)
        penalties.append(load)
        penalties.sort(by: >)
        guard let worst = penalties.first else { return nil }
        let rest = penalties.dropFirst().reduce(0) { $0 + $1 * $1 }
        return Swift.max(0, Swift.min(100, 100 - (worst + 0.35 * rest.squareRoot())))
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
            headline: headline,
            score: Self.score(load: analysis.recentLoad, effects: analysis.effects),
            confidence: confidence,
            explanation: explanation,
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: [],
            contributors: contributors)
    }
}
