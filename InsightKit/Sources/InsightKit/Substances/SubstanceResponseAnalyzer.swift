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

        /// The thinner side of the comparison. Two means are only as trustworthy
        /// as the smaller pool behind them: 3-versus-300 is a 3-reading finding.
        public var evidencePairs: Int { Swift.min(affectedNights, baselineNights) }

        /// Standard error of the difference in means, in baseline SDs —
        /// `√(1/n₁ + 1/n₂)`, the textbook form.
        public var standardErrorInSDs: Double {
            guard affectedNights > 0, baselineNights > 0 else { return .infinity }
            return (1 / Double(affectedNights) + 1 / Double(baselineNights)).squareRoot()
        }

        /// The effect size that survives its own uncertainty: the observed size
        /// less one standard error, floored at zero.
        ///
        /// **This is the difference between a finding and a hint.** The user's
        /// systolic row compared 3 readings after use with 5 clean ones and
        /// reported 2.9 SD — a number whose standard error is 0.73 SD, i.e. a
        /// quarter of itself. Scored at face value it zeroed the dial. Reported
        /// conservatively it is still the largest thing on the card, which is
        /// correct: it is real, it is just not yet certain, and the honest
        /// response to uncertainty is a smaller number rather than a hidden row.
        public var reliableEffectSize: Double {
            guard let size = effectSize else { return 0 }
            return Swift.max(0, size - standardErrorInSDs)
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
        (.atrialFibrillationBurden, true),

        // MARK: Widened 2026-08-02, at the user's direction
        //
        // **"I want almost every vital to go into this, so it can actually see
        // the real impact drugs have to me as an individual."** Eleven signals
        // could only ever describe eleven kinds of response, and the ones left
        // out were not left out for a reason — they were simply never added.
        //
        // Breadth also makes the dial *fairer*, not harsher: the score's
        // `breadthShare` term is a mean over everything measured, so each vital
        // that holds steady is evidence the response is narrow and pulls the
        // deduction down. Adding a signal can only lower the score if the
        // signal actually moved.
        //
        // What is still excluded, and why: body composition, VO₂max, vascular
        // age and height cannot move inside an 18-hour after-use window, so a
        // difference in them across that window measures the passage of time
        // rather than a response. Sleep *onset* is excluded too — it is when
        // you chose to go to bed, which is a decision rather than something
        // the substance did to you.
        (.heartRate, true),
        (.walkingHeartRateAverage, true),
        (.bloodPressureDiastolic, true),
        // Sleep architecture is where alcohol shows up most reliably: it
        // suppresses REM and fragments the second half of the night.
        (.sleepEfficiency, false),
        (.sleepDeepMinutes, false),
        (.sleepRemMinutes, false),
        (.sleepLatencyMinutes, true),
        // Core temperature, for the thermometer users; the two skin channels
        // above cover the wearables.
        (.bodyTemperature, true),
        // Next-day capacity. Not moralising about a quiet day — a substantial,
        // repeatable drop in what you actually did is one of the effects people
        // most want to see measured, and it is invisible in any vital sign.
        (.stepCount, false),
        (.activeEnergyBurned, false),
        (.exerciseMinutes, false),
        (.dayStrain, false),
        // Off the same sensor as SpO₂, and a genuine vasoconstriction signal
        // for stimulants.
        (.peripheralPerfusionIndex, false),
        // Alcohol in particular disturbs glucose regulation for hours.
        (.bloodGlucose, true),
        // Gait: the clearest available proxy for acute motor impairment.
        (.walkingSteadiness, false),
        (.walkingAsymmetry, true)
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

    /// Which direction a chart legend should call "better".
    ///
    /// Deliberately *not* derived from `watched`, though the two overlap: that
    /// table says which direction this analyser treats as adverse **after use**,
    /// which is a narrower question. A temperature is the case that separates
    /// them — a rise after drinking is an adverse response, while neither
    /// direction of a temperature is "better" in general, so the legend must
    /// say `nil` where the pool says `true`.
    ///
    /// The `nil` cases are a **named category rather than a `default:`**, so a
    /// new watched metric cannot fall into "no better end" by forgetting to
    /// mention it — which is how a `default:` behaves and is the shape of every
    /// silent-drop defect this file already carries a test for.
    public static let nearestNormalIsBest: Set<MetricType> = [
        // Neither end of a temperature is an improvement; the reader's own
        // normal is the good place.
        .skinTemperature, .skinTemperatureDeviation, .bodyTemperature,
        // Alcohol drives glucose *down* and stimulants drive it up, and both
        // ends are a problem. The pool scores it one-directionally because that
        // is all the pool can express; the legend must not repeat the
        // simplification as if it were the whole truth.
        .bloodGlucose
    ]

    static func higherIsBetter(_ metric: MetricType) -> Bool? {
        if nearestNormalIsBest.contains(metric) { return nil }
        switch metric {
        case .heartRateVariabilityRMSSD, .heartRateVariabilitySDNN, .sleepDurationHours,
             .oxygenSaturation, .heartRateRecovery, .sleepEfficiency,
             .sleepDeepMinutes, .sleepRemMinutes, .stepCount, .activeEnergyBurned,
             .exerciseMinutes, .peripheralPerfusionIndex, .walkingSteadiness,
             // More strain after use than without it is not the concern here —
             // doing conspicuously *less* is, which is the same reading steps
             // and active energy get.
             .dayStrain:
            return true
        case .restingHeartRate, .respiratoryRate, .bloodPressureSystolic,
             .atrialFibrillationBurden, .heartRate, .walkingHeartRateAverage,
             .bloodPressureDiastolic, .sleepLatencyMinutes, .walkingAsymmetry:
            return false
        default:
            return nil
        }
    }

    // MARK: - The dial

    /// How far an adverse response must move to count as a full-strength
    /// finding — measured in the user's *own* baseline spread rather than in
    /// invented per-metric thresholds. A 4 bpm shift means one thing for someone
    /// whose clean-night resting heart rate varies by 2, and another for someone
    /// it varies by 8; a fixed table cannot tell them apart.
    static let fullStrengthEffectSize = 2.0

    /// Readings on the thinner side of a comparison before an effect carries its
    /// full weight. Below it the effect is still shown, still named in the
    /// drivers, still headlined if it is the largest thing on the card — it
    /// simply cannot take its full toll off the score until the readings back
    /// it. A standard error already discounts statistical noise; this discounts
    /// what a standard error cannot see, which is that a handful of readings
    /// taken close together may share a confound the clean pool doesn't.
    static let fullEvidencePairs = 5

    /// How much of a full-strength finding this effect's evidence supports, 0…1.
    static func evidenceWeight(_ effect: MetricEffect) -> Double {
        Swift.min(1, Double(effect.evidencePairs) / Double(fullEvidencePairs))
    }

    /// One signal's contribution to the pool, 0–100: how far it moved in the
    /// unwelcome direction, judged against the reader's own spread, discounted
    /// for how well that move is evidenced.
    ///
    /// A signal that moved the *welcome* way scores 0 — it took nothing off, and
    /// that is good news rather than a missing row.
    static func severity(_ effect: MetricEffect) -> Double {
        guard effect.isAdverse else { return 0 }
        let strength = Swift.min(100, effect.reliableEffectSize / fullStrengthEffectSize * 100)
        return strength * evidenceWeight(effect)
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

    /// The most exposure can take off when there is **nothing measured at all**.
    ///
    /// It used to be uncapped, so a heavy fortnight with no wearable data read
    /// 0 — the "you had some, you're at 0%" verdict the user rejected outright
    /// on 2026-08-02. A log with no biometrics is evidence of *use* and none of
    /// *harm*, and a dial that treats the two as the same thing is the
    /// draconian reading this card exists to avoid. Just over half is the
    /// honest weight of "you have had a lot lately and nothing here can see
    /// what it did to you".
    static let exposureCeilingUnmeasured = 55.0

    /// How much of the deduction the single worst response may drive.
    ///
    /// **The rest comes from breadth**, and the split is the whole philosophy of
    /// this card: one signal moving a long way is a finding worth a real dent,
    /// but only a body responding *across the board* should approach zero.
    /// Before this, one signal at two standard deviations took 100 points off
    /// on its own — so a single blood-pressure row zeroed a card whose other
    /// seven signals were untouched.
    static let worstResponseShare = 0.45

    /// The remainder, spread over the mean severity of everything measured. A
    /// signal that didn't move pulls this down, which is why watching more
    /// vitals makes the score *fairer* rather than harsher: each new quiet
    /// signal is evidence that the response is narrow.
    static let breadthShare = 0.55

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
    /// What exposure alone may take off, given how much of the body's response
    /// is actually visible. Slides from `exposureCeilingUnmeasured` down to
    /// `exposureCeilingWhenMeasured` as measured signals arrive: the more the
    /// readings can speak, the less the log has to.
    static func effectiveExposure(load: Double, measuredSignals: Int) -> Double {
        let measuredness = Swift.min(1, Double(measuredSignals) / Double(signalsForMeasuredResponse))
        let ceiling = exposureCeilingUnmeasured
            + (exposureCeilingWhenMeasured - exposureCeilingUnmeasured) * measuredness
        return Swift.min(load, ceiling)
    }

    /// What came off the score, itemised — every measured signal's own points,
    /// plus exposure's.
    ///
    /// One statement of the arithmetic, so the dial and its attribution cannot
    /// disagree. The combiner is **linear in the severities**
    ///
    ///     deduction = worstResponseShare · worst
    ///               + breadthShare · mean(severities)
    ///               + exposure
    ///
    /// which makes each signal's own contribution exact by inspection rather
    /// than by Euler's theorem — the previous pool needed the theorem because
    /// its combiner was a root-sum-square. Nothing is approximated in either,
    /// but this one can be read off the page, and a card whose whole job is to
    /// be believed should prefer the arithmetic a sceptical reader can check.
    struct Deduction: Sendable, Equatable {
        /// Points off per effect, in the order the effects were given.
        let perEffect: [Double]
        /// Points off for the fortnight's logged use.
        let exposure: Double

        var raw: Double { perEffect.reduce(0, +) + exposure }
        var total: Double { Swift.max(0, Swift.min(100, raw)) }
    }

    static func deduction(load: Double, effects: [MetricEffect]) -> Deduction {
        let exposure = effectiveExposure(load: load, measuredSignals: effects.count)
        let severities = effects.map(severity)
        guard let worst = severities.max(), !severities.isEmpty else {
            return Deduction(perEffect: [], exposure: exposure)
        }
        // Exactly one severity plays the "worst" role, matching how the score
        // reads it. On a tie the choice is arbitrary and identical in both.
        let worstIndex = severities.firstIndex(of: worst) ?? 0
        let count = Double(severities.count)
        let perEffect = severities.enumerated().map { index, value in
            (index == worstIndex ? worstResponseShare * worst : 0)
                + breadthShare * value / count
        }
        return Deduction(perEffect: perEffect, exposure: exposure)
    }

    /// The pool, kept for callers that zip against it — severities then the
    /// effective exposure, always last.
    static func effectivePenalties(load: Double, effects: [MetricEffect]) -> [Double] {
        effects.map(severity) + [effectiveExposure(load: load, measuredSignals: effects.count)]
    }

    /// 0–100, higher is better — the same direction as every other dial in the
    /// app, including Cardiovascular *Risk*, which maps low risk to a high score.
    ///
    /// ## What this number is for
    ///
    /// _Set by the user, 2026-08-02, after their own card read 0:_ **"just
    /// because I had stimulants doesn't mean it should be 0. This is harm
    /// reduction… measure the impact to me and tell me when I'm overdoing it.
    /// No big impact? Your score will be quite high. If you've had heaps and
    /// there is now a big impact to all your metrics, then yes, lower score."**
    ///
    /// So the dial reads **measured impact**, never disapproval of use:
    ///
    /// - Logged use with no visible response scores **high**. Exposure alone is
    ///   capped, and the cap tightens as measurement improves.
    /// - One signal responding strongly is a real dent, not an annihilation —
    ///   `worstResponseShare` bounds what any single row can do.
    /// - A body responding *broadly* is what takes the number down, because
    ///   that is what a broad response means.
    /// - Thin evidence is discounted rather than hidden: see `severity`.
    ///
    /// nil for an empty log — no dial, and the card stays hidden.
    static func score(load: Double, effects: [MetricEffect]) -> Double? {
        guard !effects.isEmpty || load > 0 else { return nil }
        return Swift.max(0, Swift.min(100, 100 - deduction(load: load, effects: effects).total))
    }

    /// Each input's share of what came off the score, summing to 1.
    ///
    /// This card said **"Not a weighted average"**, which was true and unhelpful:
    /// a pool of this shape is exactly attributable. `deduction` is linear in
    /// the severities, so each share is that input's own points over the total
    /// — no approximation and nothing chosen.
    ///
    /// Returned in the order given, so a caller can zip it against its own list.
    /// The last element is always exposure's share, because `deduction` keeps it
    /// separate — the two orderings are stated in one place for that reason.
    static func penaltyShares(load: Double, effects: [MetricEffect]) -> [Double] {
        let parts = deduction(load: load, effects: effects)
        let all = parts.perEffect + [parts.exposure]
        guard parts.raw > 0 else { return Array(repeating: 0, count: all.count) }
        return all.map { $0 / parts.raw }
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
            // "Body temp" until 2026-08-02, which collided with the real core
            // temperature below the moment that joined the watched list — two
            // rows, one name, different quantities.
            case .skinTemperatureDeviation: name = "Skin temp vs your baseline"
            case .sleepDurationHours: name = "Sleep"
            case .respiratoryRate: name = "Respiration"
            case .skinTemperature: name = "Skin temperature"
            case .oxygenSaturation: name = "Blood oxygen"
            case .heartRateRecovery: name = "Heart-rate recovery"
            case .bloodPressureSystolic: name = "Systolic BP"
            case .atrialFibrillationBurden: name = "AFib burden"
            case .heartRate: name = "Heart rate"
            case .walkingHeartRateAverage: name = "Walking heart rate"
            case .bloodPressureDiastolic: name = "Diastolic BP"
            case .sleepEfficiency: name = "Sleep efficiency"
            case .sleepDeepMinutes: name = "Deep sleep"
            case .sleepRemMinutes: name = "REM sleep"
            case .sleepLatencyMinutes: name = "Time to fall asleep"
            case .bodyTemperature: name = "Body temperature"
            case .stepCount: name = "Steps"
            case .activeEnergyBurned: name = "Active energy"
            case .exerciseMinutes: name = "Exercise minutes"
            case .dayStrain: name = "Day strain"
            case .peripheralPerfusionIndex: name = "Perfusion index"
            case .bloodGlucose: name = "Blood glucose"
            case .walkingSteadiness: name = "Walking steadiness"
            case .walkingAsymmetry: name = "Walking asymmetry"
            // No `default:` — a metric added to `watched` without a name
            // here would be measured and then silently dropped from the card.
            default: name = nil
            }
            if let name {
                // The evidence travels with the finding. A reader shown
                // "+31.5 mmHg after use" has no way to know whether that rests
                // on three readings or three hundred, and the difference is the
                // difference between a hint and a fact — the model-internals
                // export has said so in a footnote since it was written, while
                // the card itself said nothing.
                let evidence = Self.evidenceWeight(e) < 1
                    ? " (on \(e.affectedNights) reading\(e.affectedNights == 1 ? "" : "s") "
                        + "after use vs \(e.baselineNights) clean — counts for less until "
                        + "there are more)"
                    : ""
                drivers.append(InsightDriver(text: "\(name) \(Self.deltaLabel(e)) after use\(evidence)",
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
            let responded = analysis.effects.filter { Self.severity($0) > 0 }.count
            explanation = "This score measures what your own readings show after logged use — not the fact that you used. "
            if responded == 0 {
                explanation += "Across \(analysis.effects.count) signal\(analysis.effects.count == 1 ? "" : "s") measured both with and without use, nothing has moved in a way worth counting, so the score stays high."
            } else {
                explanation += "\(responded) of \(analysis.effects.count) measured signal\(analysis.effects.count == 1 ? "" : "s") "
                    + "\(responded == 1 ? "has" : "have") shifted the unwelcome way; the rest held steady. "
                    + "A single response dents the score, a broad one lowers it a long way, and a change resting on few readings counts for less until more arrive."
            }
            explanation += " This is your own pattern — not medical advice."
        } else {
            explanation = "You've logged use, but nothing here has enough readings both with and without use to compare yet. Until then this number rests on the size of your recent log alone, which can say you've had a lot — never what it did to you. Keep your wearable synced."
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
        let loadWasCapped = analysis.recentLoad
            > Self.effectiveExposure(load: analysis.recentLoad,
                                     measuredSignals: analysis.effects.count)
        let loadFactor = shares.last.map {
            ScoreFactor(source: .derived, name: "Recent substance load",
                        weight: $0,
                        detail: "\(analysis.loadBand) — \(analysis.eventsInWindow) "
                            + "\(analysis.eventsInWindow == 1 ? "log" : "logs") in \(loadWindowDays) days"
                            + (analysis.effects.isEmpty
                               ? " — capped: use alone can never be the whole of this score, "
                                 + "and it is all there is to go on until a signal has readings "
                                 + "both with and without use"
                               : (loadWasCapped
                                  ? " — capped: your measured response carries the score"
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
