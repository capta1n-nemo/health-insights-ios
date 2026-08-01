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
    ///
    /// Each has a documented physiological link to the substances this app lets
    /// people log; nothing is here because it was available. A metric with too
    /// few paired readings simply produces no effect, so adding one costs
    /// nothing but reaches further for anyone who does record it.
    private static let watched: [(MetricType, upIsAdverse: Bool)] = [
        (.restingHeartRate, true),
        (.heartRateVariabilityRMSSD, false),
        (.heartRateVariabilitySDNN, false),
        (.skinTemperatureDeviation, true),
        // Absolute skin temperature, for the wearables that report one instead
        // of a deviation. Same signal, other domain — a Whoop user had no
        // thermal row here at all.
        (.skinTemperature, true),
        (.sleepDurationHours, false),
        (.respiratoryRate, true),
        // Alcohol suppresses respiratory drive in sleep, and overnight
        // desaturation is the clearest non-invasive marker of it.
        (.oxygenSaturation, false),
        // Autonomic recovery after exertion is blunted by stimulants and by
        // alcohol the night before; the watch reports it without being asked.
        (.heartRateRecovery, false),
        // Alcohol and stimulants both raise blood pressure acutely. Cuff
        // readings are sparse, so this usually yields nothing — and correctly
        // says nothing rather than guessing.
        (.bloodPressureSystolic, true),
        // "Holiday heart": alcohol is among the best-documented triggers of an
        // atrial-fibrillation episode, and the watch already measures burden.
        (.atrialFibrillationBurden, true)
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
    /// Derived from `watched`, so the two can never disagree about what this
    /// analyser looks at — the detail screen charts this list.
    public static let comparedMetrics: [MetricType] = watched.map { $0.0 }

    static func higherIsBetter(_ metric: MetricType) -> Bool? {
        switch metric {
        case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN, .sleepDurationHours,
             .oxygenSaturation, .heartRateRecovery:
            return true
        case .restingHeartRate, .respiratoryRate, .bloodPressureSystolic,
             .atrialFibrillationBurden:
            return false
        default:
            return nil   // temperature: nearest the baseline is best
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

    /// Each penalty's share of what came off the score.
    ///
    /// This card said **"Not a weighted average"**, which was true and unhelpful:
    /// it is a worst-offender-dominant pool, and a pool of that shape is exactly
    /// attributable. The combiner is
    ///
    ///     deduction = worst + 0.35 · √(Σ rest²)
    ///
    /// which is homogeneous of degree one in the penalties, so by Euler's
    /// theorem each one's own contribution is `pᵢ · ∂f/∂pᵢ` and the parts sum to
    /// the whole exactly — the worst contributes itself, and every other
    /// penalty contributes `0.35 · pᵢ² / √(Σ rest²)`. No approximation and
    /// nothing chosen: it is the same arithmetic `score` runs, read back.
    ///
    /// Returned in the order given, so a caller can zip it against its own list.
    /// The last element is always the load's share, because `score` appends it
    /// last — the two orderings are stated in one place for that reason.
    static func penaltyShares(load: Double, effects: [MetricEffect]) -> [Double] {
        let penalties = effects.map(severity) + [load]
        guard let worstValue = penalties.max(), worstValue > 0 else {
            return Array(repeating: 0, count: penalties.count)
        }
        // Ties: exactly one penalty plays the "worst" role in `score`, which
        // sorts and takes the first. Picking the first maximum here matches it,
        // and on a tie the choice is arbitrary in both places identically.
        let worstIndex = penalties.firstIndex(of: worstValue) ?? 0
        let restSumSquares = penalties.enumerated()
            .filter { $0.offset != worstIndex }
            .reduce(0.0) { $0 + $1.element * $1.element }
        let restRoot = restSumSquares.squareRoot()
        let total = worstValue + 0.35 * restRoot
        guard total > 0 else { return Array(repeating: 0, count: penalties.count) }
        return penalties.enumerated().map { index, p in
            index == worstIndex
                ? worstValue / total
                : (restRoot > 0 ? 0.35 * p * p / restRoot / total : 0)
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
            case .skinTemperature:
                text = String(format: "Skin temperature %@%.1f °C after use", arrow, abs(e.deltaAbsolute))
            case .oxygenSaturation:
                text = String(format: "Blood oxygen %@%.1f%% after use", arrow, abs(e.deltaAbsolute))
            case .heartRateRecovery:
                text = String(format: "Heart-rate recovery %@%.0f bpm after use", arrow, abs(e.deltaAbsolute))
            case .bloodPressureSystolic:
                text = String(format: "Systolic BP %@%.0f mmHg after use", arrow, abs(e.deltaAbsolute))
            case .atrialFibrillationBurden:
                text = String(format: "AFib burden %@%.1f%% after use", arrow, abs(e.deltaAbsolute))
            // No `default:` — a metric added to `watched` without a sentence
            // here would be measured and then silently dropped from the card.
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

        // Each signal's share of what came off the score.
        //
        // These were weight 0 with the note "the load figure isn't a weighted
        // blend of these" — which is true of a *blend* and was read as "there is
        // no share", so the card said "Not a weighted average". A
        // worst-offender pool divides exactly; `penaltyShares` does it out of
        // the same combiner `score` uses. A signal that moved in the *welcome*
        // direction has a severity of zero and therefore a share of zero, and it
        // stays on the card in the charted-not-scored list — which is the right
        // reading of it: measured, and taking nothing off.
        //
        // `penaltyShares` returns the load's share last, matching the order
        // `score` appends it in.
        let shares = Self.penaltyShares(load: analysis.recentLoad, effects: analysis.effects)
        let contributors = analysis.effects.enumerated().map { index, effect in
            MetricContribution(
                metric: effect.metric,
                higherIsBetter: Self.higherIsBetter(effect.metric),
                weight: shares.indices.contains(index) ? shares[index] : 0,
                detail: String(format: "%@%.1f after use",
                               effect.deltaAbsolute >= 0 ? "+" : "−", abs(effect.deltaAbsolute)))
        }
        // The fortnight's load is a penalty in its own right and is not a metric
        // — it is a decaying figure over the log — so it reaches the weighting
        // section as a factor rather than a contribution. Leaving it out would
        // put shares on screen that don't account for the number, and on a heavy
        // fortnight with no measurable biometric response it is the *whole* of it.
        let loadFactor = shares.last.map {
            ScoreFactor(source: .derived, name: "Recent substance load",
                        weight: $0,
                        detail: "\(analysis.loadBand) — \(analysis.eventsInWindow) "
                            + "\(analysis.eventsInWindow == 1 ? "log" : "logs") in \(loadWindowDays) days",
                        isModifiable: true)
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
            contributors: contributors,
            weighting: .worstOffender,
            otherFactors: loadFactor.map { [$0] } ?? [])
    }
}

/// The stretch after a logged event during which the analyzer treats a reading
/// as affected — as something a chart can draw.
///
/// The card has always *stated* this window ("readings within 18 hours of a log
/// are compared against your clean nights") and never shown it, so the reader
/// had to hold a date arithmetic problem in their head to see which part of a
/// line the sentence was about. This is that sentence, drawn.
public struct SubstanceWindow: Sendable, Equatable, Identifiable {
    public let start: Date
    public let end: Date
    /// Every substance logged inside this span. More than one when overlapping
    /// windows were merged.
    public let substances: [SubstanceClass]

    public init(start: Date, end: Date, substances: [SubstanceClass]) {
        self.start = start
        self.end = end
        self.substances = substances
    }

    public var id: Date { start }
    public func overlaps(_ range: ClosedRange<Date>) -> Bool {
        start <= range.upperBound && end >= range.lowerBound
    }
}

public extension SubstanceResponseAnalyzer {

    /// The after-windows of a log, merged where they overlap.
    ///
    /// Merged, and that is the whole design question. Three coffees across a
    /// morning produce three eighteen-hour windows covering nearly the same
    /// stretch; drawn as three rectangles they stack, and stacked translucent
    /// fills compound into a band darker than a single one — so the chart would
    /// encode *how many logs* in a channel that is supposed to say only
    /// *affected or not*. One merged span at one opacity says the true thing.
    ///
    /// Which substances went into a span is kept rather than collapsed, because
    /// the legend beneath names them and "alcohol and caffeine" is a different
    /// read from "alcohol".
    static func affectedWindows(events: [SubstanceEvent],
                                after: TimeInterval = afterWindow) -> [SubstanceWindow] {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        var out: [SubstanceWindow] = []
        for event in sorted {
            let start = event.timestamp
            let end = start.addingTimeInterval(after)
            if let last = out.last, start <= last.end {
                out[out.count - 1] = SubstanceWindow(
                    start: last.start,
                    // `max` rather than the new end: a later event with a
                    // shorter window must not shorten a span already open.
                    end: Swift.max(last.end, end),
                    substances: last.substances.contains(event.substance)
                        ? last.substances : last.substances + [event.substance])
            } else {
                out.append(SubstanceWindow(start: start, end: end,
                                           substances: [event.substance]))
            }
        }
        return out
    }
}
