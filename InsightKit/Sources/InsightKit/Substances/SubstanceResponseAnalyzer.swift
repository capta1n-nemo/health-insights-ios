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
    /// How far back the before/after comparison reaches, for **both** sides.
    ///
    /// It used to reach the whole history, and the user's own card export
    /// showed what that measures: their cuff readings span six years, their
    /// logging spans a fortnight, so "after use" meant *recent* and the clean
    /// baseline meant *years ago* — and a blood pressure that rose over those
    /// years reached the card as "+21 mmHg after use", 87% of the score. A
    /// substance response is an acute claim; both sides of it have to come
    /// from the same stretch of the person's life. Ninety days keeps a
    /// fortnightly cuff-er above the pairing floors while staying inside one
    /// season.
    public static let comparisonWindowDays = 90.0

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
            if let e = effect(for: metric, upIsAdverse: upIsAdverse, events: events,
                              samples: samples, now: now) {
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
                       events: [SubstanceEvent], samples: [HealthMetricSample],
                       now: Date) -> MetricEffect? {
        // Contemporaneous, on both sides — see `comparisonWindowDays`.
        let cutoff = now.addingTimeInterval(-comparisonWindowDays * 86_400)
        let series = samples.samples(of: metric)
            .filter { $0.start >= cutoff && $0.start <= now }
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

    /// The short form of an adverse effect, for the card's headline slot.
    /// Exhaustive over `watched`'s metrics by construction: a metric added
    /// there without a label here falls to the generic form, which is still
    /// true — never silent.
    static func headlineLabel(_ effect: MetricEffect) -> String {
        let arrow = effect.deltaAbsolute >= 0 ? "+" : "−"
        let magnitude = abs(effect.deltaAbsolute)
        switch effect.metric {
        case .restingHeartRate: return String(format: "HR %@%.0f after use", arrow, magnitude)
        case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN:
            return String(format: "HRV %@%.0f%% after use",
                          effect.deltaPercent >= 0 ? "+" : "−", abs(effect.deltaPercent))
        case .bloodPressureSystolic: return String(format: "BP %@%.0f after use", arrow, magnitude)
        case .sleepDurationHours: return String(format: "Sleep %@%.1f h after use", arrow, magnitude)
        case .respiratoryRate: return String(format: "Breathing %@%.1f after use", arrow, magnitude)
        case .oxygenSaturation: return String(format: "SpO₂ %@%.1f%% after use", arrow, magnitude)
        case .heartRateRecovery: return String(format: "Recovery %@%.0f after use", arrow, magnitude)
        case .atrialFibrillationBurden: return String(format: "AFib %@%.1f%% after use", arrow, magnitude)
        case .skinTemperature, .skinTemperatureDeviation:
            return String(format: "Temp %@%.1f °C after use", arrow, magnitude)
        default:
            return String(format: "%@ %@%.1f after use", effect.metric.displayName, arrow, magnitude)
        }
    }

    /// One delta, formatted the way this card talks about that metric — HRV as
    /// a percentage, everything else in its own unit.
    ///
    /// Shared by the driver lines and the weighting rows. As two formatters the
    /// same effect reached the reader as "HRV +5% after use" in one section and
    /// "+3.6 after use" — the raw milliseconds, unlabelled — in the next, two
    /// spellings of one number with nothing saying they were the same fact.
    static func deltaLabel(_ e: MetricEffect) -> String {
        let arrow = e.deltaAbsolute >= 0 ? "+" : "−"
        switch e.metric {
        case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN:
            return String(format: "%@%.0f%%", e.deltaPercent >= 0 ? "+" : "−", abs(e.deltaPercent))
        case .restingHeartRate, .heartRateRecovery:
            return String(format: "%@%.0f bpm", arrow, abs(e.deltaAbsolute))
        case .bloodPressureSystolic:
            return String(format: "%@%.0f mmHg", arrow, abs(e.deltaAbsolute))
        case .sleepDurationHours:
            return String(format: "%@%.1f h", arrow, abs(e.deltaAbsolute))
        case .respiratoryRate:
            return String(format: "%@%.1f br/min", arrow, abs(e.deltaAbsolute))
        case .skinTemperature, .skinTemperatureDeviation:
            return String(format: "%@%.1f °C", arrow, abs(e.deltaAbsolute))
        case .oxygenSaturation, .atrialFibrillationBurden:
            return String(format: "%@%.1f%%", arrow, abs(e.deltaAbsolute))
        default:
            let unit = e.metric.unit
            return String(format: "%@%.1f%@", arrow, abs(e.deltaAbsolute),
                          unit.isEmpty ? "" : " \(unit)")
        }
    }

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

    /// The most that *exposure alone* can take off the score once the body's
    /// actual response is on the card.
    ///
    /// The load used to enter the penalty pool at full strength — up to 100 on
    /// its own — so a regular user's dial read **0 whatever their body did**,
    /// and a measured response that was mild could not be told from one that
    /// was severe. The user's direction, 2026-08-01: *base it off actual
    /// impact, not just outright usage*. So the load is treated as what it
    /// honestly is — evidence of exposure, a prior — and the measurement
    /// supersedes the prior as it arrives: with a well-measured response the
    /// exposure penalty caps at one band's worth, and the measured severities
    /// (which were always effect-size-based) carry the rest of the dial.
    static let exposureCeilingWhenMeasured = 25.0

    /// Measured signals needed before the response counts as well-measured and
    /// the cap above fully applies. Below it the cap phases in linearly — one
    /// weakly-paired metric must not discount a heavy fortnight on its own,
    /// and with nothing measured at all the load still stands alone, because
    /// exposure is then the only evidence there is.
    static let signalsForMeasuredResponse = 3

    /// The pool `score` and `penaltyShares` both draw from — the measured
    /// severities plus the *effective* exposure penalty, always last. One
    /// statement, so the dial and its attribution cannot disagree about how
    /// much the load was allowed to take off.
    static func effectivePenalties(load: Double, effects: [MetricEffect]) -> [Double] {
        let measuredness = Swift.min(1, Double(effects.count) / Double(signalsForMeasuredResponse))
        let capped = Swift.min(load, exposureCeilingWhenMeasured)
        let effectiveLoad = load * (1 - measuredness) + capped * measuredness
        return effects.map(severity) + [effectiveLoad]
    }

    /// 0–100, higher is better — the same direction as every other dial in the
    /// app, including Cardiovascular *Risk*, which maps low risk to a high score.
    /// A raw load passed straight through would paint a heavy fortnight green.
    ///
    /// Worst-offender-dominant, using the identical combiner `VitalSignsCheck`
    /// applies to its penalty pool: one large heart-rate response is the finding
    /// and must not be averaged away by five signals that didn't move, while a
    /// week where everything shifted a little still scores below a clean one.
    /// The fortnight's load enters the same pool as a penalty in its own right
    /// — at full strength only while nothing is measured, capped once the
    /// response is (see `exposureCeilingWhenMeasured`).
    ///
    /// nil for an empty log — no dial, and the card stays hidden.
    static func score(load: Double, effects: [MetricEffect]) -> Double? {
        guard !effects.isEmpty || load > 0 else { return nil }
        var penalties = effectivePenalties(load: load, effects: effects)
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
        let penalties = effectivePenalties(load: load, effects: effects)
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
            // `isAdverse` is already decided when the effect is measured, against
            // the same watched-metric table — recomputing it here would be a
            // second opinion that could drift from the first.
            let name: String?
            switch e.metric {
            case .restingHeartRate: name = "Resting HR"
            case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN: name = "HRV"
            case .skinTemperatureDeviation: name = "Body temp"
            case .sleepDurationHours: name = "Sleep"
            case .respiratoryRate: name = "Respiration"
            case .skinTemperature: name = "Skin temperature"
            case .oxygenSaturation: name = "Blood oxygen"
            case .heartRateRecovery: name = "Heart-rate recovery"
            case .bloodPressureSystolic: name = "Systolic BP"
            case .atrialFibrillationBurden: name = "AFib burden"
            // No `default:` — a metric added to `watched` without a name
            // here would be measured and then silently dropped from the card.
            default: name = nil
            }
            if let name {
                drivers.append(InsightDriver(text: "\(name) \(Self.deltaLabel(e)) after use",
                                             isNotable: e.isAdverse))
            }
        }
        drivers.append(InsightDriver(
            text: "Recent cardiovascular load: \(analysis.loadBand) (\(analysis.eventsInWindow) logs in \(loadWindowDays) days)",
            isNotable: analysis.recentLoad >= 50))

        // Headline: the *strongest* adverse effect, else the load band. It was
        // hardcoded to resting heart rate, so the user's card led with
        // "HR −1 after use" — good news — while a +21 mmHg systolic response
        // carried 87% of the score two lines down. The headline is the one
        // thing the card says on the Today tab; it has to be the finding.
        let headline: String
        if let worst = analysis.effects.filter({ $0.isAdverse })
            .max(by: { severity($0) < severity($1) }), severity(worst) > 0 {
            headline = headlineLabel(worst)
        } else if let rhr = analysis.effects.first(where: { $0.metric == .restingHeartRate }) {
            headline = String(format: "HR %@%.0f after use",
                              rhr.deltaAbsolute >= 0 ? "+" : "−", abs(rhr.deltaAbsolute))
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
        // Safety flag. "Your heart is showing a notable response" is a claim
        // about the *measurements*, so only a measured response may say it —
        // it used to fire on heavy usage alone, which is exactly the
        // usage-versus-impact conflation the score itself was corrected for.
        // A heavy fortnight still gets the care line, honestly attributed to
        // the log rather than to the body.
        let bigHR = analysis.effects.contains { $0.metric == .restingHeartRate && $0.deltaAbsolute >= 12 }
        if bigHR {
            explanation += " Your heart is showing a notable response — if your heart rate stays high, or you feel palpitations, chest pain or breathlessness, please seek medical care."
        } else if analysis.recentLoad >= 80 {
            explanation += " Recent use has been heavy by your own log — if you notice palpitations, chest pain or breathlessness, please seek medical care."
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
            let share = shares.indices.contains(index) ? shares[index] : 0
            return MetricContribution(
                metric: effect.metric,
                higherIsBetter: Self.higherIsBetter(effect.metric),
                weight: share,
                detail: "\(Self.deltaLabel(effect)) after use"
                    // A signal that moved the *welcome* way has a severity of
                    // zero and so takes nothing off. That is good news and has
                    // to read as good news rather than as a bare zero under a
                    // section promising every input carries a share.
                    + (share > 0 ? "" : " — moved the way you'd want it to, so it took nothing off"))
        }
        // The fortnight's load is a penalty in its own right and is not a metric
        // — it is a decaying figure over the log — so it reaches the weighting
        // section as a factor rather than a contribution. Leaving it out would
        // put shares on screen that don't account for the number, and on a heavy
        // fortnight with no measurable biometric response it is the *whole* of it.
        // When the response is well-measured, exposure was capped (see
        // `exposureCeilingWhenMeasured`) and the row says so — a reader whose
        // measured response is mild should see *why* a heavy fortnight no
        // longer zeroes the dial, and a reader with no wearable should see
        // that usage is the only evidence the number rests on.
        let loadWasCapped = analysis.effects.count >= Self.signalsForMeasuredResponse
            && analysis.recentLoad > Self.exposureCeilingWhenMeasured
        let loadFactor = shares.last.map {
            ScoreFactor(source: .derived, name: "Recent substance load",
                        weight: $0,
                        detail: "\(analysis.loadBand) — \(analysis.eventsInWindow) "
                            + "\(analysis.eventsInWindow == 1 ? "log" : "logs") in \(loadWindowDays) days"
                            + (loadWasCapped
                               ? " — capped: your measured response carries the score"
                               : (analysis.effects.isEmpty
                                  ? " — usage is all this number can rest on until there is paired data"
                                  : "")),
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
