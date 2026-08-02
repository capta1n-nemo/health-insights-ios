import Foundation

/// BMI from weight + height, plus weight and body-fat trends.
public struct BodyCompositionInsight: InsightModel {
    public let id: InsightID = .bodyComposition
    public let title = "Body Composition"
    public init() {}
    /// `.height` is deliberately absent — see `supportingMetrics`. It is a
    /// static attribute with no series to chart and nothing that can change
    /// between two readings; it enters through BMI and is named in the drivers.
    public var candidateMetrics: [MetricType] {
        [.bodyMass, .bodyFatPercentage, .leanBodyMass, .muscleMass, .boneMass,
         .bodyWaterPercentage]
    }
    /// Non-mandatory: without them the dial falls back to BMI rather than
    /// disappearing, and the card still narrates.
    public var requirements: [GroundingRequirement] {
        [.init(kind: .dateOfBirth, isMandatory: false,
               rationale: "Healthy body-fat ranges are age-banded."),
         .init(kind: .biologicalSex, isMandatory: false,
               rationale: "Healthy body-fat ranges differ substantially by sex."),
         .init(kind: .weightGoal, isMandatory: false,
               rationale: "The rate your weight is moving at is scored against "
                   + "what you're aiming for — without it, only unsafe speeds count.")]
    }

    /// Grounding facts **and** a file import: a Shotsy backup carries weight,
    /// body fat and lean mass, which is most of what this card reads. See
    /// `ContributionRoute.fileImport` for why an input has to be offered on the
    /// card rather than only in Settings.
    public var contributions: [ContributionRoute] {
        [.groundingFacts(requirements.map(\.kind)), .fileImport]
    }

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

        var bmi: Double?
        if let h = height, h > 0.5 {
            let value = weight / (h * h)
            bmi = value
            let cat = Self.bmiCategory(value)
            headline = String(format: "BMI %.1f", value)
            primary = value
            drivers.insert(InsightDriver(text: String(format: "BMI: %.1f (%@)", value, cat),
                                         isNotable: cat != "healthy"), at: 0)
            explanation = "Your BMI is \(String(format: "%.1f", value)) (\(cat)), from \(String(format: "%.1f", weight)) kg at \(String(format: "%.2f", h)) m."
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
        let composition = Self.compositionNarrative(samples: samples, weightSeries: weightSeries)
        if let composition {
            drivers.insert(.notable(composition), at: 0)
            explanation += " " + composition
        }

        // **One measurement carries the dial** — body fat where a scale reports
        // it, body mass through BMI otherwise — and which one is the model's own
        // answer rather than a guess made here.
        //
        // The rest of what a body-composition scale measures now carries a share
        // rather than being charted at weight 0. There is no published 0–100
        // curve for lean, muscle or bone mass, and there is a defensible reading
        // of each against this person's own normal: lean and muscle mass falling
        // away from your baseline is the thing this card's whole narrative is
        // about, and it was contributing nothing to the number that narrative
        // sits under. See `SupportingSignal`.
        let bodyFat = samples.latestValue(.bodyFatPercentage)
        let dial = Self.score(bodyFat: bodyFat, bmi: bmi,
                              age: profile.age(asOf: now), sex: profile.sex)
        let velocity = CompositionVelocityModel.evaluate(samples: samples, now: now)
        let goal = profile.weightGoal

        // The header must lead with whatever the dial actually rests on. It was
        // built from BMI unconditionally, *before* the route above was chosen,
        // so a card whose score was 80% body fat opened "Your BMI is 32.2
        // (obese)" and put "BMI 32.2" under the number — a basis the weighting
        // section two screens down contradicted. BMI stays in the sentence and
        // in the drivers; it just no longer poses as the score.
        if let dial, dial.metric == .bodyFatPercentage, let bodyFat,
           let age = profile.age(asOf: now), let sex = profile.sex {
            let range = Self.healthyBodyFatRange(age: age, sex: sex)
            let position = bodyFat > range.upper ? "above"
                : bodyFat < range.lower ? "below" : "inside"
            headline = String(format: "Body fat %.1f%%", bodyFat)
            primary = bodyFat
            var lead = String(format: "Your body fat is %.1f%% — %@ the %.0f–%.0f%% healthy range for your age and sex, and it carries most of this score.",
                              bodyFat, position, range.lower, range.upper)
            if let bmi, let h = height {
                lead += String(format: " BMI %.1f (%@), from %.1f kg at %.2f m.",
                               bmi, Self.bmiCategory(bmi), weight, h)
            }
            if let composition {
                lead += " " + composition
            }
            explanation = lead
        }
        // **The primary pool is a level, a rate and a quality** — not a level
        // alone. See `CompositionVelocity` for why: a reader twelve kilograms
        // down scored identically to one who had never moved, because body fat
        // on the day was the whole number.
        //
        // 0.45 to the level is the user's own figure (2026-08-02), and it sits
        // where the published scoring systems sit: InBody's score moves on
        // lean mass and fat mass roughly symmetrically against height-and-sex
        // norms rather than treating fat as dominant. Here the other 0.55 is
        // split between how fast the mass is moving and how much of what moves
        // is lean tissue — which is the same "lean matters as much as fat"
        // judgement, expressed as change rather than as level.
        var terms: [ScoreBlend.Term] = []
        if let dial {
            terms.append(.init(metric: dial.metric,
                                 higherIsBetter: dial.metric == .bodyFatPercentage ? false : nil,
                                 score: dial.value, weight: Self.levelWeight,
                                 detail: Self.formatted(dial.metric, samples: samples)))
        }
        if let velocity {
            terms.append(.init(
                metric: .bodyMass, higherIsBetter: nil,
                score: CompositionVelocityModel.rateScore(
                    percentPerWeek: velocity.percentPerWeek, goal: goal),
                weight: Self.rateWeight,
                detail: CompositionVelocityModel.phrase(velocity, goal: goal),
                isPublishedScale: goal != nil))
            if let quality = CompositionVelocityModel.qualityScore(
                leanShareOfChange: velocity.leanShareOfChange,
                isLosing: velocity.kilogramsPerWeek < 0) {
                terms.append(.init(
                    metric: .leanBodyMass, higherIsBetter: true,
                    score: quality, weight: Self.qualityWeight,
                    detail: Self.qualityDetail(velocity)))
            }
        }
        let blend = terms.isEmpty ? nil : ScoreBlend.blend(
            primary: terms,
            supporting: Self.supportingTerms(samples: samples, now: now,
                                             excluding: Set(terms.map(\.metric))))
        return InsightResult(
            id: id, title: title, primaryValue: primary, headline: headline,
            score: blend?.score ?? dial?.value,
            confidence: Self.scoreConfidence(bodyFat: bodyFat, height: height,
                                             profile: profile, now: now),
            explanation: explanation,
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: unmetRequirements(profile: profile, now: now),
            contributors: (blend?.contributions ?? []) + Self.trackedNotScored(samples: samples),
            weighting: dial == nil ? .unstated : .weightedAverage)
    }

    /// Signals this card draws but deliberately does not score.
    ///
    /// **Muscle mass, and it is charted rather than dropped.** It left the
    /// weighted pool because a BIA scale derives it from lean mass, so scoring
    /// both counted one tissue twice — but the reader still wants to see it,
    /// and a metric that is declared and reported nowhere charts on no section
    /// of its own card (`ContributorsTests`, which caught exactly this the
    /// moment the weight was removed). A weight-0 row with its reason on it is
    /// the shape this repo already uses for every other unscored signal.
    static func trackedNotScored(samples: [HealthMetricSample]) -> [MetricContribution] {
        var out: [MetricContribution] = []
        if let muscle = samples.latestValue(.muscleMass) {
            out.append(MetricContribution(
                metric: .muscleMass, higherIsBetter: true, weight: 0,
                detail: String(format: "%.1f kg — tracked, not scored: your scale works it "
                               + "out from lean mass, which already carries a share, and "
                               + "counting both would count one tissue twice", muscle)))
        }
        // **The medication, and why its weight is zero rather than small.**
        //
        // The user asked for this on the chart: *"I also want that data point to
        // go into the 'what goes into this' chart, even if it has like a 2%
        // weighting for the overall score, so I can see this one go up.. and
        // everything else go down probably."* The chart is what they were
        // after, and a weight-0 contributor is drawn there exactly like a
        // scored one — `MetricOverlayChart` reads `contributors`, not weights.
        //
        // The 2% is the part that is declined, and deliberately. A weight says
        // "more of this is better" or "less of this is better", and neither is
        // true of a drug level: the right amount is whatever somebody was
        // prescribed. Scoring it would make the card reward a higher dose,
        // which is both meaningless and the opposite of what this app says
        // anywhere else about medication. What the drug is *doing* is already
        // scored — that is `rateWeight`, the speed the weight is moving at.
        //
        // `higherIsBetter: nil` for the same reason: neither direction is good.
        if let level = samples.latestValue(.activeMedicationLevel) {
            out.append(MetricContribution(
                metric: .activeMedicationLevel, higherIsBetter: nil, weight: 0,
                detail: String(format: "%.2f mg — tracked, not scored: worked out from "
                               + "your logged doses, not measured. There is no better or "
                               + "worse level to be at; what it's doing to your weight is "
                               + "what this card scores", level)))
        }
        return out
    }

    /// Everything a scale reports beyond the one measurement carrying the dial.
    ///
    /// `.height` is deliberately not here and is no longer a declared input.
    /// It is a **static attribute** — the app already gives it a plain value
    /// card with no chart — so it is neither a series to draw under "What goes
    /// into this" nor a thing that can move between two readings. It enters the
    /// number through BMI and is named in the drivers, which is where a constant
    /// belongs. This is the one signal that left the card rather than earning a
    /// weight, and the alternative was a bar whose only honest label would be
    /// "this cannot change".
    /// The level — body fat against its published range, or BMI in fallback.
    /// The user's figure, 2026-08-02: *"I think it should be 45%, maybe 50%
    /// max"*, and it matches where the established scoring systems sit.
    static let levelWeight = 0.45
    /// How fast the mass is moving, against the goal and the published bands.
    static let rateWeight = 0.30
    /// How much of what moved was lean tissue.
    static let qualityWeight = 0.25

    /// The row's own sentence about loss quality, in the reader's terms.
    static func qualityDetail(_ velocity: CompositionVelocity) -> String {
        guard let share = velocity.leanShareOfChange else { return "—" }
        let losing = velocity.kilogramsPerWeek < 0
        if losing && share <= 0 {
            return "lean mass is holding while the weight comes off — the loss is fat"
        }
        let percent = Int((abs(share) * 100).rounded())
        if losing {
            return percent > Int(CompositionVelocityModel.leanShareConcern * 100)
                ? "\(percent)% of what you're losing is lean tissue — above the 20–30% expected, so some of the loss is muscle"
                : "\(percent)% of what you're losing is lean tissue, inside the expected 20–30%"
        }
        return "\(percent)% of what you're gaining is lean tissue"
    }

    static let supportingMetrics: [(MetricType, Bool?)] = [
        (.bodyFatPercentage, false),
        // `false`, matching the judgement the drivers on this same card
        // already make (`trendWord(..., higherIsBetter: false)` prints
        // "Weight trending down (good)"). It was `nil` — departure in either
        // direction penalised — so the user's export showed the card calling
        // their loss good in one line and docking them "2.1 SD below your
        // normal" for it in the share table. One card, one opinion. The
        // muscle-loss half of a falling weight is not lost by this: lean and
        // muscle mass below carry `true`, so loss that takes muscle with it
        // still costs, which is exactly the narrative's own warning.
        (.bodyMass, false),
        // **Muscle mass is deliberately absent, and this is the co-linearity
        // fix.** A BIA scale measures weight and impedance and *derives* the
        // rest: lean = weight × (1 − fat%), and muscle is a fixed fraction of
        // lean. Weighting lean mass, muscle mass and weight as three signals
        // counted two measurements three times and called it breadth — an
        // outside analysis of the user's export named it on 2026-08-02 and it
        // was right. One lean-tissue term stands for the tissue; the level
        // term and the velocity terms carry the rest.
        (.leanBodyMass, true),
        (.boneMass, true),
        (.bodyWaterPercentage, nil)
    ]

    static func supportingTerms(samples: [HealthMetricSample], now: Date,
                                excluding primary: Set<MetricType>) -> [ScoreBlend.Term] {
        supportingMetrics.compactMap { metric, higherIsBetter in
            guard !primary.contains(metric),
                  let reading = VitalReader.reading(metric, from: samples, now: now)
            else { return nil }
            return ScoreBlend.supporting(reading, higherIsBetter: higherIsBetter)
        }
    }

    static func formatted(_ metric: MetricType, samples: [HealthMetricSample]) -> String {
        let unit = metric.unit
        return String(format: "%.1f%@", samples.latestValue(metric) ?? 0,
                      unit.isEmpty ? "" : " \(unit)")
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

    // MARK: - The dial
    //
    // This card carried `score: nil` unconditionally, which meant it could never
    // show a dial even with a complete smart-scale dataset — while at the same
    // time printing "BMI: 30.4 (obese)" as a notable driver. That is the
    // judgement without the calibration, not restraint about making one.

    /// Healthy body-fat % for age and sex — the Gallagher et al. (2000) bands
    /// behind the NIH / ACE "healthy range" tables. Published thresholds, not a
    /// weighting this app invented, which is the same justification the repo
    /// already accepted for scoring blood pressure.
    static func healthyBodyFatRange(age: Double, sex: BiologicalSex) -> (lower: Double, upper: Double) {
        switch sex {
        case .male:   return age < 40 ? (8, 19)  : age < 60 ? (11, 21) : (13, 24)
        case .female: return age < 40 ? (21, 32) : age < 60 ? (23, 33) : (24, 35)
        }
    }

    /// How close a value sits to the middle of a published healthy range.
    ///
    /// The same Gaussian falloff `VitalSignsCheck.normality` uses, with the
    /// range's own half-width standing in for a standard deviation: dead centre
    /// scores 100, either edge about 82. Below the range costs half as much —
    /// lean is not the failure mode this measures, and it is the same asymmetry
    /// Vitals Check applies to a departure in the harmless direction.
    static func rangeScore(_ value: Double, lower: Double, upper: Double) -> Double {
        let centre = (lower + upper) / 2
        let halfWidth = Swift.max(0.5, (upper - lower) / 2)
        let d = (value - centre) / halfWidth
        let base = 100 * exp(-0.5 * pow(d / 1.6, 2))
        return d < 0 ? 100 - (100 - base) * 0.5 : base
    }

    /// Body fat against the age/sex healthy range when a scale reports it; BMI
    /// against 18.5–24.9 otherwise.
    ///
    /// BMI is the *fallback* rather than the basis because it cannot tell muscle
    /// from fat — which is the whole distinction this card exists to draw, and
    /// the reason it carried no score for so long. Scoring BMI when a measured
    /// fat fraction is on hand would be choosing the worse instrument.
    ///
    /// **Returns the measurement it rested on, not only the number.** The card
    /// has to say which of its inputs carries the dial, and deriving that from a
    /// second copy of this branch is how the picture and the number drift apart.
    /// One measurement is the whole score on either branch: this card is not a
    /// blend, and it used to say "not a weighted average" for that reason —
    /// which describes a card with no attributable share rather than one where a
    /// single input has all of it.
    ///
    /// The BMI branch attributes to **body mass** rather than splitting with
    /// height. Both are needed to compute it, but height is a constant here: it
    /// is the only thing on this card that cannot change between two readings,
    /// so it is what the score is measured *against* rather than something
    /// moving it. It stays a charted input at weight 0.
    /// **Three routes now, and the middle one is new** (2026-08-02): a measured
    /// fat fraction, then an estimate from the reader's own *dimensions*, then
    /// BMI. `build` is the waist-and-height estimate — see `BuildAssessment`.
    ///
    /// The ordering is the same "prefer the better instrument" argument that
    /// put fat ahead of BMI in the first place. Relative Fat Mass is validated
    /// against DXA and BMI is not validated against anything except itself, so
    /// where a waist measurement exists it displaces BMI — and where a scale
    /// reports fat directly, that still wins over both.
    static func score(bodyFat: Double?, bmi: Double?, age: Double?, sex: BiologicalSex?,
                      build: BuildAssessment? = nil)
        -> (value: Double, metric: MetricType)? {
        if let bodyFat, let age, let sex {
            let range = healthyBodyFatRange(age: age, sex: sex)
            return (rangeScore(bodyFat, lower: range.lower, upper: range.upper),
                    .bodyFatPercentage)
        }
        if let build, let age, let sex {
            let range = healthyBodyFatRange(age: age, sex: sex)
            return (rangeScore(build.relativeFatMass, lower: range.lower, upper: range.upper),
                    .bodyFatPercentage)
        }
        if let bmi { return (rangeScore(bmi, lower: 18.5, upper: 24.9), .bodyMass) }
        return nil
    }

    /// `.high` only when the dial rests on a measured fat fraction against a
    /// real age and sex. BMI alone is a weaker instrument and should say so.
    static func scoreConfidence(bodyFat: Double?, height: Double?,
                                profile: UserHealthProfile, now: Date) -> InsightConfidence {
        if bodyFat != nil, profile.age(asOf: now) != nil, profile.sex != nil { return .high }
        return height == nil ? .low : .moderate
    }
}
