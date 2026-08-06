import Foundation

/// A signal a card charts that no published 0–100 curve exists for.
///
/// ## The rule this reverses, and why
///
/// Until 2026-08-01 these arrived at **weight 0**, on a standing argument that
/// an invented weight inside a number the user is asked to trust is worse than
/// none. That argument stands against *inventing* one. It does not justify what
/// it was actually producing, which was a section titled "What goes into this"
/// listing six signals of which one went into anything.
///
/// The resolution is that a weight does not have to be invented, because the
/// app already knows how to judge a signal it has no published scale for: **how
/// far it sits from the reader's own normal, in the direction that matters.**
/// That is what `VitalSignsCheck` has done for seventeen vitals since it was
/// written, and what `ReadinessScore` does for every component it weights. It is
/// weaker evidence than a published curve — a departure from your own baseline
/// is real information but is not calibrated against an outcome — and the answer
/// to weaker evidence is a **smaller weight**, not a zero one.
///
/// So a supporting signal is scored the way everything else here is scored, and
/// the row says which basis it rests on.
public enum SupportingSignal {

    /// The share of a card's number that its supporting signals carry between
    /// them, divided among however many there are.
    ///
    /// **One constant, deliberately.** It is the whole of the judgement in this
    /// change and it is retuned in one place. 20% is enough that a signal
    /// visibly moves the number — the point of listing it — and small enough
    /// that a card's primary measurement still decides what the card says: on
    /// Fitness, VO₂max keeps 80% against six supporting signals at about 3%
    /// each, and no combination of them can turn "Excellent" into "Needs work".
    public static let collectiveShare = 0.20

    /// 0–100 for a signal judged against the reader's own baseline.
    ///
    /// The identical mapping `ReadinessScore` weights its components with — z of
    /// 0 is an ordinary day at 65, and 1.5 SD in the good direction is about 95
    /// — extended with the case Readiness has no need for. `higherIsBetter` of
    /// `nil` means neither direction is the good one (day strain, a temperature
    /// deviation), so the score falls away from the baseline in **both**
    /// directions rather than rewarding one of them.
    ///
    /// `nil` z is not a zero score: it means the signal has no baseline to be
    /// judged against yet, so it earns no weight rather than a bad one.
    public static func score(z: Double?, higherIsBetter: Bool?) -> Double? {
        guard let z else { return nil }
        guard let higherIsBetter else {
            // Nearest the baseline is best. Starts above the directional cases'
            // ordinary day, because sitting *on* your normal is the whole of
            // what this asks for.
            return clamp(85 - abs(z) * 20)
        }
        return clamp(65 + (higherIsBetter ? 1 : -1) * z * 20)
    }

    static func clamp(_ x: Double) -> Double { Swift.max(0, Swift.min(100, x)) }
}

/// Folding a card's supporting signals into the number its primary measurement
/// carries.
///
/// Every card that scores does the same two-step arithmetic and each was doing
/// it by hand: renormalise the components that had data, then multiply and sum.
/// Adding a second group of terms to five cards separately is five places for
/// the weights to stop summing to one, which is the claim the section makes on
/// screen.
public enum ScoreBlend {

    /// One input, its 0–100, and its weight *within its own group*. Weights are
    /// relative — `blend` renormalises each group — so a caller states the
    /// proportions it means and never the totals.
    public struct Term: Sendable, Equatable {
        public let metric: MetricType
        public let higherIsBetter: Bool?
        public let score: Double
        public let weight: Double
        public let detail: String
        /// False where the score rests on the reader's own baseline rather than
        /// a published scale, so the row can say so. The distinction is the
        /// honesty claim this change turns on and it is not visible from a
        /// weight.
        public let isPublishedScale: Bool
        /// The raw value this term was scored from, and what it was judged
        /// against. Carried through to `MetricContribution` so the decomposition
        /// can show the arithmetic rather than only its result — see backlog #38.
        public let value: Double?
        public let baseline: Double?
        public let z: Double?
        /// False where `score` is a **placeholder the caller fed in so the
        /// blend could still weight**, not this component's own 0–100 — Energy
        /// passes its reservoir level into every term because the blend's score
        /// is discarded there, and emitting that as a `componentScore` told the
        /// reader every input had scored identically. When false the blend
        /// emits nil instead, which is `MetricContribution`'s word for "this
        /// model has not been taught to say".
        public let scoreIsOwn: Bool

        public init(metric: MetricType, higherIsBetter: Bool?, score: Double,
                    weight: Double, detail: String, isPublishedScale: Bool = true,
                    value: Double? = nil, baseline: Double? = nil, z: Double? = nil,
                    scoreIsOwn: Bool = true) {
            self.metric = metric
            self.higherIsBetter = higherIsBetter
            self.score = score
            self.weight = weight
            self.detail = detail
            self.isPublishedScale = isPublishedScale
            self.value = value
            self.baseline = baseline
            self.z = z
            self.scoreIsOwn = scoreIsOwn
        }
    }

    /// The blended number and the contributions that account for it.
    ///
    /// `nil` when there is nothing to score at all. A card with primary terms
    /// and no supporting ones is unchanged from what it produced before this
    /// existed — the supporting share is only carved out of the primary group
    /// when there is something to put in it, so a reader with no wearable sees
    /// exactly the number they saw yesterday.
    ///
    /// A metric appearing in both groups keeps its **primary** term and is
    /// dropped from the supporting one: a signal already weighed on a published
    /// scale must not be weighed a second time against its own baseline, which
    /// is the double-counting this codebase has had to unpick before.
    public static func blend(primary: [Term], supporting: [Term],
                             supportingShare: Double = SupportingSignal.collectiveShare)
        -> (score: Double, contributions: [MetricContribution])? {
        let primaryMetrics = Set(primary.map(\.metric))
        var seen = primaryMetrics
        let extra = supporting.filter { term in
            guard !primaryMetrics.contains(term.metric), !seen.contains(term.metric)
            else { return false }
            seen.insert(term.metric)
            return true
        }

        let primaryTotal = primary.reduce(0) { $0 + $1.weight }
        let extraTotal = extra.reduce(0) { $0 + $1.weight }
        guard primaryTotal > 0 || extraTotal > 0 else { return nil }

        // Whichever group is empty hands its share to the other, so a card with
        // only supporting signals still scores rather than dividing by zero.
        let share = primaryTotal > 0 ? (extraTotal > 0 ? supportingShare : 0) : 1
        let weighted: [(Term, Double)] =
            primary.map { ($0, primaryTotal > 0 ? $0.weight / primaryTotal * (1 - share) : 0) }
            + extra.map { ($0, extraTotal > 0 ? $0.weight / extraTotal * share : 0) }

        let score = weighted.reduce(0) { $0 + $1.0.score * $1.1 }
        // ⚠️ **`term.score` used to be dropped here**, which is why no card
        // could answer "why is my score low". The blend knew every component's
        // own 0–100 and threw all of them away the instant it had the weighted
        // mean — so the detail screen could show a share and never the number
        // the share was applied to. Backlog #38 / S2.
        let contributions = weighted.map { term, weight in
            MetricContribution(metric: term.metric, higherIsBetter: term.higherIsBetter,
                               weight: weight, detail: term.detail,
                               // Only a score the term genuinely owns survives —
                               // a placeholder presented as a sub-score would be
                               // worse than the nil that says "not taught to say".
                               componentScore: term.scoreIsOwn ? term.score : nil,
                               value: term.value,
                               baseline: term.baseline, z: term.z)
        }
        return (score, contributions)
    }

    /// A supporting term from a reading, or `nil` when there is no baseline to
    /// judge it against yet.
    ///
    /// The `detail` carries the value **and** the departure, because a share of
    /// 3% under a bare number gives the reader no way to see why it is 3% and
    /// not 30%.
    public static func supporting(_ reading: VitalReading, higherIsBetter: Bool?,
                                  weight: Double = 1) -> Term? {
        guard let score = SupportingSignal.score(z: reading.zScore,
                                                 higherIsBetter: higherIsBetter)
        else { return nil }
        let departure = reading.zScore.map {
            abs($0) < 0.5 ? " · about your normal"
                : String(format: " · %.1f SD %@ your normal", abs($0), $0 > 0 ? "above" : "below")
        } ?? ""
        return Term(metric: reading.metric, higherIsBetter: higherIsBetter, score: score,
                    weight: weight,
                    detail: MetricValueFormatter.string(reading.value, reading.metric) + departure,
                    isPublishedScale: false,
                    // A supporting term is *defined* by its departure from the
                    // reader's own baseline, so it is the one kind of term that
                    // can always fill these in.
                    value: reading.value, baseline: reading.baseline, z: reading.zScore)
    }

    // MARK: - Blending a measured signal with a figure the card worked out
    //
    // ⚠️ **`Term` is keyed by `MetricType`, and that is a real design choice
    // rather than an oversight**: it is what lets one contribution feed the
    // overlay chart, its legend and the weighting section without any of them
    // re-deriving it. The cost is that a card whose number genuinely divides
    // between a *measured* signal and a *computed* one had nowhere to say so,
    // and did the two-step arithmetic by hand instead — which is two more
    // places for the shares to stop summing to one, the exact claim
    // "How this is weighted" makes on screen.
    //
    // Work impact is the case that forced it (backlog D41, 2026-08-06). Its
    // number now divides between how much work there was — a figure read off
    // the calendar, not a metric — and how much the body differed, which is
    // three metrics. Both halves are shares of one number.

    /// One weighted input that is **not** a metric: a figure the card worked
    /// out, named by the series it keeps.
    ///
    /// The `id` is mandatory for the reason `ScoreFactor.Source.derived`'s is —
    /// a row saying "the gap between your busy and quiet days — 21%" that
    /// nothing can trend is a link to an empty page, and
    /// `DerivedFactorIdentityTests` fails the build on one.
    public struct FactorTerm: Sendable, Equatable {
        public let id: DerivedSeriesID
        public let name: String
        /// This input's own 0–100, before its weight is applied.
        public let score: Double
        /// Its weight **within the factor group**; `blend` renormalises.
        public let weight: Double
        public let detail: String
        public let isModifiable: Bool

        public init(id: DerivedSeriesID, name: String, score: Double,
                    weight: Double, detail: String, isModifiable: Bool = true) {
            self.id = id
            self.name = name
            self.score = score
            self.weight = weight
            self.detail = detail
            self.isModifiable = isModifiable
        }
    }

    /// Metric terms and non-metric factors blended as shares of **one** number.
    ///
    /// `metricShare` is what the metric group carries between them; the factors
    /// carry the rest. Weights inside each group are relative and renormalised,
    /// so a caller states proportions and never totals — and the two lists that
    /// come back carry *absolute* shares that sum to 1 across both, which is
    /// what `InsightResult.weightedFactors` needs so a card does not draw two
    /// 100%s.
    ///
    /// Whichever group is empty hands its share to the other, so this can never
    /// silently score a card on nothing. `nil` when both are empty.
    public static func blend(metrics: [Term], factors: [FactorTerm],
                             metricShare: Double)
        -> (score: Double, contributions: [MetricContribution], factors: [ScoreFactor])? {
        let metricTotal = metrics.reduce(0) { $0 + $1.weight }
        let factorTotal = factors.reduce(0) { $0 + $1.weight }
        guard metricTotal > 0 || factorTotal > 0 else { return nil }
        let share = metricTotal > 0
            ? (factorTotal > 0 ? Swift.max(0, Swift.min(1, metricShare)) : 1)
            : 0

        let contributions = metrics.map { term in
            MetricContribution(
                metric: term.metric, higherIsBetter: term.higherIsBetter,
                weight: metricTotal > 0 ? term.weight / metricTotal * share : 0,
                detail: term.detail,
                // Same rule as the two-group blend: a placeholder presented as
                // a sub-score is worse than the nil that says "not taught to
                // say".
                componentScore: term.scoreIsOwn ? term.score : nil,
                value: term.value, baseline: term.baseline, z: term.z)
        }
        let emitted = factors.map { factor in
            ScoreFactor.derived(factor.id, name: factor.name,
                                weight: factorTotal > 0
                                    ? factor.weight / factorTotal * (1 - share) : 0,
                                detail: factor.detail,
                                isModifiable: factor.isModifiable)
        }

        let score = zip(metrics, contributions).reduce(0) { $0 + $1.0.score * $1.1.weight }
            + zip(factors, emitted).reduce(0) { $0 + $1.0.score * $1.1.weight }
        return (score, contributions, emitted)
    }

    /// A supporting term with a share, or a weight-0 row that says why not —
    /// never a silent drop.
    ///
    /// `supporting` alone returns `nil` for a reading with no baseline, and a
    /// caller that `compactMap`s it makes the signal disappear from every list
    /// on the card: heart-rate recovery had data a day old and appeared in
    /// neither the weighted shares nor "charted, not scored", which is the
    /// invisible middle state the why-rows exist to forbid. A weight of 0
    /// contributes nothing to the number; the detail says what would change it.
    public static func supportingOrTracked(_ reading: VitalReading,
                                           higherIsBetter: Bool?,
                                           weight: Double = 1) -> Term {
        supporting(reading, higherIsBetter: higherIsBetter, weight: weight)
            ?? Term(metric: reading.metric, higherIsBetter: higherIsBetter,
                    score: 0, weight: 0,
                    detail: MetricValueFormatter.string(reading.value, reading.metric)
                        + " — tracked, not scored: needs \(VitalSignsCheck.minimumBaselineDays) "
                        + "recent days of history before it can be judged against your normal",
                    isPublishedScale: false,
                    // The reading is real even while it cannot be judged, so
                    // the decomposition can still print it beside the why-row.
                    value: reading.value,
                    // `scoreIsOwn: false`: the 0 above is the weight-0 row's
                    // placeholder, not a verdict — this signal was *not* scored,
                    // and a componentScore of 0 would say it scored terribly.
                    scoreIsOwn: false)
    }
}
