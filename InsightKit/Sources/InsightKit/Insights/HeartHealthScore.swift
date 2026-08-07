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
        /// The reading `score` came from, in the metric's own unit, plus the
        /// baseline and departure **only where the component judged against the
        /// reader's own history** — which here is respiratory stability alone;
        /// the other three score against published age/sex references, and
        /// quoting a "baseline" for those would misname a norm table.
        public let value: Double?
        public let baseline: Double?
        public let z: Double?
        public init(name: String, score: Double, weight: Double, detail: String,
                    metric: MetricType, higherIsBetter: Bool?,
                    value: Double? = nil, baseline: Double? = nil, z: Double? = nil) {
            self.name = name; self.score = score; self.weight = weight; self.detail = detail
            self.metric = metric; self.higherIsBetter = higherIsBetter
            self.value = value; self.baseline = baseline; self.z = z
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
                                   weight: $0.weight / total, detail: $0.detail,
                                   // The composite is exactly the weighted mean
                                   // of these, so the counterfactual is exact.
                                   componentScore: $0.score, value: $0.value,
                                   baseline: $0.baseline, z: $0.z)
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
                               metric: .vo2Max, higherIsBetter: true,
                               value: vo2))
        }
        if let hr = restingHR {
            comps.append(.init(name: "Resting heart rate",
                               score: restingHRScore(hr), weight: 0.25,
                               detail: String(format: "%.0f bpm", hr),
                               metric: .restingHeartRate, higherIsBetter: false,
                               value: hr))
        }
        if let v = hrv {
            comps.append(.init(name: "Heart-rate variability",
                               score: hrvScore(v, age: age), weight: 0.25,
                               detail: String(format: "%.0f ms", v),
                               metric: hrvMetric, higherIsBetter: true,
                               value: v))
        }
        if let dev = respiratoryRateDeviation {
            // Stable respiratory rate (near baseline) scores high; big deviations lower it.
            let penalty = min(60, abs(dev.zScore ?? 0) * 20)
            comps.append(.init(name: "Respiratory stability",
                               score: clamp(90 - penalty), weight: 0.05,
                               detail: String(format: "%.0f br/min", dev.value),
                               metric: .respiratoryRate, higherIsBetter: nil,
                               // The one component here judged against the
                               // reader's own baseline rather than a norm table.
                               value: dev.value, baseline: dev.baseline, z: dev.zScore))
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
        // **`.none` throughout this block, and for two different reasons.**
        //
        // The resting-HR and HRV lines read `baseline ?? value` as *the level* —
        // "your usual resting heart rate", deliberately, because that is what
        // the paragraph above says a score should rest on. A reference gap is
        // machinery for judging today against the past; used on a level it just
        // makes the level staler, which is the opposite of the fix that comment
        // describes.
        //
        // The respiratory deviation below genuinely is a judgement, and it is
        // still `.none` — because it is a *scored* judgement, and the score
        // bands were calibrated against the ungapped baseline. Held with the
        // rest of the scoring path; see the call-site rule in `VitalReader`.
        let vo2 = VitalReader.reading(.vo2Max, from: samples, now: now, gap: .none)?.value
        let rhrReading = VitalReader.reading(.restingHeartRate, from: samples, now: now,
                                             gap: .none)
        let restHR = rhrReading.map { $0.baseline ?? $0.value }
        // Track which flavour was used, so the chart plots the series the score
        // actually read rather than whichever one it guesses at.
        let hrvMetric: MetricType = VitalReader.reading(.heartRateVariabilityRMSSD,
                                                        from: samples, now: now,
                                                        gap: .none) != nil
            ? .heartRateVariabilityRMSSD : .heartRateVariabilitySDNN
        let hrv = VitalReader.reading(hrvMetric, from: samples, now: now, gap: .none)
            .map { $0.baseline ?? $0.value }

        let respDev: Baseline.Deviation? = VitalReader
            .reading(.respiratoryRate, from: samples, now: now, gap: .none)
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

        // Heart-rate recovery, the measurement this card's own bespoke section
        // draws. Read through `VitalReader` on the same window
        // `HeartResponseModel` uses, so the chart cannot show a reading the
        // section beside it has already discarded as too old.
        //
        // It carries a share now rather than being charted at weight 0. The
        // published 12-beat cut-point stays where it belongs — in the bespoke
        // section, which is about the threshold — and the *weight* here rests on
        // the reader's own baseline, which is what `SupportingSignal` is for. A
        // cut-point says whether a reading is concerning; it is not a 0-100
        // curve, and turning it into one is the invention this app declines.
        // `supportingOrTracked`, not `supporting`: a recovery reading whose
        // baseline is still building used to vanish from the shares *and* from
        // "charted, not scored" — declared, holding data a day old, and visible
        // nowhere. A weight-0 row that says what it is waiting for is the
        // contract every other unweighted signal on this card already honours.
        // `.none`: a supporting score term, held with the rest of the scoring
        // path.
        let supporting = VitalReader.reading(.heartRateRecovery, from: samples, now: now,
                                             freshWithin: HeartResponseModel.recoveryFreshness,
                                             gap: .none)
            .map { ScoreBlend.supportingOrTracked($0, higherIsBetter: true) }
        let blend = ScoreBlend.blend(
            primary: out.components.map {
                ScoreBlend.Term(metric: $0.metric, higherIsBetter: $0.higherIsBetter,
                                score: $0.score, weight: $0.weight, detail: $0.detail,
                                value: $0.value, baseline: $0.baseline, z: $0.z)
            },
            supporting: supporting.map { [$0] } ?? [])
        let score = blend?.score ?? out.score

        let band = HeartHealthInsight.band(score)
        // Confidence scales with how many components were available.
        let confidence: InsightConfidence = out.components.count >= 3 ? .high
            : out.components.count == 2 ? .moderate : .low
        var explanation = "Composite heart-health score of \(Int(score.rounded()))/100 (\(band)), from your cardio fitness, resting heart rate and HRV compared with age-adjusted norms."
        if let supporting, supporting.weight > 0 {
            explanation += " Your heart-rate recovery is read in beside them, against your own normal rather than a published scale, so it carries a smaller share."
        }

        // Where You Stand, absorbed. It was a card of its own reading the same
        // three metrics this one already scores — but the *framing* is not a
        // duplicate: a score says how you are doing, a centile says against
        // whom, and this is the only place in the app that compares the user to
        // published population figures rather than to their own baseline.
        //
        // Folded into the component lines rather than appended after them. As
        // two lists, one metric reached the reader twice with two values and
        // no label for the difference — "Resting heart rate: 58 bpm" four rows
        // above "Resting Heart Rate 60 — top 25%", the component's baseline
        // read against the centile's latest read. One metric, one line: the
        // value the score used, with the centile phrase beside it. A centile
        // band is coarse enough to survive the two reads differing by a couple
        // of beats; two bare numbers are not.
        let standing = PeerStandingModel.evaluate(samples: samples, profile: profile, now: now)
        let standingByMetric = Dictionary(uniqueKeysWithValues:
            (standing?.standings ?? []).map { ($0.metric, $0) })
        var folded: Set<MetricType> = []
        let lines = out.components.map { comp -> InsightDriver in
            let base = InsightDriver.component("\(comp.name): \(comp.detail)", score: comp.score)
            guard let s = standingByMetric[comp.metric] else { return base }
            folded.insert(comp.metric)
            return InsightDriver(text: base.text + " — \(s.phrase) for your age and sex",
                                 isNotable: base.isNotable == true || s.percentile < 40)
        }
        // A standing for a metric the score didn't read still gets its own line.
        let standingLines = (standing?.standings ?? [])
            .filter { !folded.contains($0.metric) }
            .sorted { $0.percentile > $1.percentile }
            .map { s in
                InsightDriver(
                    text: "\(s.metric.displayName) \(MetricValueFormatter.string(s.value, s.metric)) — \(s.phrase) for your age and sex",
                    isNotable: s.percentile < 40)
            }
        if let standing {
            explanation += " Across \(standing.standings.count) measure\(standing.standings.count == 1 ? "" : "s") you sit around the \(Int(standing.overall.rounded()))th centile for people your age and sex — an approximation to published figures, not a lookup into a real distribution — and a centile describes where you sit, not whether anything is wrong."
        }

        let all = lines + standingLines
        // MARK: Derived-series verdict — **nothing to declare, deliberately**
        //
        // Same shape and same answer as Readiness (2026-08-06). This composite
        // is the weighted mean of its components, each of which is one metric
        // scored against a published reference band; the sub-scores and
        // departures are already harvested from `contributions`, and
        // `ScoreHistory` trends the composite.
        //
        // ⚠️ **The one figure that would qualify is not computed here.** Heart
        // rate recovery — the card's own bespoke section — is evaluated by
        // `HeartResponseModel` in the *view*, so it never reaches this result
        // and cannot be declared from it. That is a real gap and it is a
        // rendering-layer one: moving the response model into `evaluate` is the
        // fix, and it changes what the card reports, so it is backlog rather
        // than a side effect of this pass. See COMMIT_MESSAGE / backlog §E.
        return InsightResult(
            id: id, title: title, primaryValue: score,
            headline: band, score: score, confidence: confidence,
            explanation: explanation,
            driverLines: all.filter { $0.isNotable == true } + all.filter { $0.isNotable != true },
            unmetRequirements: unmet,
            contributors: blend?.contributions ?? out.contributions,
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
