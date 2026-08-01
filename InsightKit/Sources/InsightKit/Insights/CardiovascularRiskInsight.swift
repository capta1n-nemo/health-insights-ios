import Foundation

/// Wraps `CardiovascularRiskModel` as a first-class `InsightModel`, wiring the
/// canonical samples + user profile into the equation inputs and declaring the
/// grounding facts it needs.
///
/// Default is `.combined`: it computes **both** SCORE2 and ASCVD and reports a
/// consensus (their mean) plus the individual results and the min–max range as
/// an honest uncertainty band. The two equations target slightly different
/// endpoints and populations, so the ensemble is presented as a range, never as
/// false precision. This is the recommended mode for Australia, which isn't the
/// native population of either single model.
public struct CardiovascularRiskInsight: InsightModel {
    public enum Engine: Sendable { case score2, ascvd, combined }

    public let id: InsightID = .cardiovascularRisk
    public let title = "Heart Attack & Stroke Risk"
    public let preferredEngine: Engine

    public init(preferredEngine: Engine = .combined) {
        self.preferredEngine = preferredEngine
    }

    // Population-average fallbacks so the estimate still works before a blood
    // test is entered. Roughly the adult mean (mmol/L); replaced the moment the
    // user adds their own numbers, which upgrades the confidence.
    private static let defaultTotalCholesterol = 5.2
    private static let defaultHDLCholesterol = 1.3

    /// Risk is overwhelmingly driven by grounding facts (age, sex, cholesterol,
    /// smoking); blood pressure is the one sensed input to the *equations*.
    ///
    /// VO₂max and vascular age are here because this card **draws them**. It
    /// absorbed heart age, so `HeartAgeAnalyser` runs behind it and reads both —
    /// vascular age reaches the card as a driver line, and "Heart age over time"
    /// replays over exactly this list. Declaring only systolic left two signals
    /// charted in the bespoke section, named in "What's driving this", and
    /// absent from "What goes into this" and "Full history" — which is the
    /// specific inconsistency this list exists to prevent.
    ///
    /// Neither feeds the risk figure, so both arrive at weight 0 and the
    /// weighting section names them as charted-not-scored.
    public var candidateMetrics: [MetricType] {
        [.bloodPressureSystolic, .vo2Max, .vascularAge]
    }

    public var requirements: [GroundingRequirement] {
        var reqs: [GroundingRequirement] = [
            .init(kind: .dateOfBirth, isMandatory: true,
                  rationale: "Age is the strongest driver of 10-year cardiovascular risk."),
            .init(kind: .biologicalSex, isMandatory: true,
                  rationale: "The risk equations are calibrated separately by sex."),
            .init(kind: .cuffSystolic, isMandatory: true,
                  rationale: "A real cuff (or Apple Health) blood-pressure reading grounds the estimate."),
            // Cholesterol is optional — we assume an average until you add a blood
            // test, then the estimate becomes more accurate.
            .init(kind: .totalCholesterol, isMandatory: false,
                  rationale: "From a blood test — improves accuracy (an average is assumed until then)."),
            .init(kind: .hdlCholesterol, isMandatory: false,
                  rationale: "'Good' cholesterol; improves accuracy (an average is assumed until then)."),
            .init(kind: .currentSmoker, isMandatory: false,
                  rationale: "Smoking roughly doubles cardiovascular risk (assumed non-smoker until set).")
        ]
        let needsSCORE2 = preferredEngine != .ascvd
        let needsASCVD = preferredEngine != .score2
        if needsSCORE2 {
            reqs.append(.init(kind: .score2Region, isMandatory: false,
                              rationale: "Calibrates SCORE2 to your region (Australia ≈ low-risk region)."))
        }
        if needsASCVD {
            reqs.append(.init(kind: .hasDiabetes, isMandatory: false,
                              rationale: "Diabetes is an independent risk factor (assumed none until set)."))
            reqs.append(.init(kind: .ascvdRaceGroup, isMandatory: false,
                              rationale: "ASCVD publishes separate coefficients by ethnicity."))
            reqs.append(.init(kind: .onBPMedication, isMandatory: false,
                              rationale: "Blood-pressure treatment status adjusts the ASCVD estimate."))
        }
        return reqs
    }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult {
        let statuses = requirementStatuses(profile: profile, now: now)
        let unmet = statuses.compactMap { $0.1 == .satisfied ? nil : $0.0 }

        // Resolve systolic BP: prefer a logged cuff reading, else a measured
        // sample read through `VitalReader` — the day's de-duplicated value,
        // against a 14-day window matching `GroundingKind.cuffSystolic.freshness`.
        //
        // Two things were wrong with `latestValue`. A cuff reading arriving as a
        // *sample* bypassed the staleness rule the same reading typed into the
        // profile has to obey; and "latest" meant whichever of the day's cuffings
        // happened to be last, where a morning 118 and an evening 146 are one
        // day's blood pressure and a clinician averages them. SCORE2 and ASCVD
        // are exponential in systolic, so that is the largest single number this
        // migration moves.
        let bpReading = VitalReader.reading(.bloodPressureSystolic, from: samples,
                                            now: now, freshWithin: 14 * 86_400)
        let sbp = profile.cuffSystolic ?? bpReading?.value
        let staleSystolic = profile.cuffSystolic == nil && (bpReading.map { !$0.isFresh } ?? false)

        // Only age, sex and a blood-pressure value are truly required. Everything
        // else falls back to a sensible average so people without a blood test
        // still get an estimate — flagged as less certain until they add it.
        guard let age = profile.age(asOf: now),
              let sex = profile.sex,
              let systolic = sbp else {
            return notYetResult(unmet: unmet)
        }
        let totalChol = profile.totalCholesterol ?? Self.defaultTotalCholesterol
        let hdl = profile.hdlCholesterol ?? Self.defaultHDLCholesterol
        let assumedCholesterol = profile.totalCholesterol == nil || profile.hdlCholesterol == nil
        // Presence and freshness are different questions, and only presence was
        // being asked. A seven-month-old lab is still the best number we have —
        // better than a population average — so it keeps being used; what it
        // stops buying is `.high` confidence and a silent pass.
        let staleCholesterol = !assumedCholesterol
            && !((profile.input(.totalCholesterol)?.isFresh(asOf: now) ?? false)
                 && (profile.input(.hdlCholesterol)?.isFresh(asOf: now) ?? false))

        // Compute whichever models this engine uses, tagging each with whether
        // the person's age is inside that model's *validated* range. Applying an
        // equation outside its derivation age band is extrapolation, so we track
        // it and prefer the in-range models for the headline number.
        //   SCORE2: validated 40–69 · ASCVD Pooled Cohort Equations: 40–79.
        var modelResults: [(name: String, pct: Double, ageValid: Bool)] = []
        if preferredEngine != .ascvd {
            let s2 = CardiovascularRiskModel.score2Risk(.init(
                age: age, sex: sex, isSmoker: profile.isSmoker, systolicBP: systolic,
                totalCholesterol: totalChol, hdlCholesterol: hdl, region: profile.score2Region))
            modelResults.append(("SCORE2", s2 * 100, (40...69).contains(age)))
        }
        if preferredEngine != .score2 {
            let ascvd = CardiovascularRiskModel.ascvdRisk(.init(
                age: age, sex: sex, race: profile.raceGroup,
                totalCholesterol: CardiovascularRiskModel.mgdL(fromMmolPerL: totalChol),
                hdlCholesterol: CardiovascularRiskModel.mgdL(fromMmolPerL: hdl),
                systolicBP: systolic, treatedForBP: profile.onBPMedication,
                isSmoker: profile.isSmoker, hasDiabetes: profile.hasDiabetes))
            modelResults.append(("ASCVD", ascvd * 100, (40...79).contains(age)))
        }

        // Headline consensus uses only age-valid models; if none are valid (age
        // outside 40–79) we fall back to all of them but drop confidence to low.
        let validModels = modelResults.filter(\.ageValid)
        let anyValid = !validModels.isEmpty
        let usedModels = anyValid ? validModels : modelResults
        let pcts = usedModels.map(\.pct)
        let consensus = pcts.reduce(0, +) / Double(pcts.count)
        let lo = pcts.min() ?? consensus
        let hi = pcts.max() ?? consensus
        let band = riskBand(pct: consensus)

        // Confidence: outside the validated age range → low. Otherwise high when
        // we have real cholesterol and no stale mandatory input; assuming an
        // average cholesterol (or a stale mandatory input) softens it to moderate.
        let mandatoryUnsatisfied = statuses.contains { $0.0.isMandatory && $0.1 != .satisfied }
        let confidence: InsightConfidence = !anyValid ? .low
            : (assumedCholesterol || staleCholesterol || staleSystolic || mandatoryUnsatisfied
               ? .moderate : .high)

        // The risk figures themselves, the modifiable factors carrying that risk,
        // and anything the user could act on lead; the demographic inputs and a
        // cholesterol already on file are context.
        var drivers: [InsightDriver] = []
        for m in usedModels { drivers.append(.notable(String(format: "%@: %.1f%%", m.name, m.pct))) }
        if usedModels.count > 1 {
            drivers.append(.notable(String(format: "Range across models: %.1f–%.1f%%", lo, hi)))
        }
        // Surface any model dropped for being out of its validated age range.
        for m in modelResults where !m.ageValid && anyValid {
            drivers.append(.notable("\(m.name) not shown — outside its validated age range"))
        }
        drivers.append(.routine("Age \(Int(age.rounded())), \(sex.displayName.lowercased())"))
        // 140 is the hypertension line; below it, blood pressure is context.
        drivers.append(InsightDriver(
            text: staleSystolic
                ? "Systolic BP \(Int(systolic.rounded())) mmHg — over two weeks old"
                : "Systolic BP \(Int(systolic.rounded())) mmHg",
            isNotable: systolic >= 140 || staleSystolic))
        if assumedCholesterol {
            drivers.append(.notable("Cholesterol assumed average — add a blood test to improve accuracy"))
        } else if staleCholesterol {
            drivers.append(.notable(String(format: "Total/HDL cholesterol %.1f/%.1f mmol/L — over six months old, worth repeating", totalChol, hdl)))
        } else {
            drivers.append(.routine(String(format: "Total/HDL cholesterol %.1f/%.1f mmol/L", totalChol, hdl)))
        }
        if profile.isSmoker { drivers.append(.notable("Current smoker")) }
        if profile.hasDiabetes { drivers.append(.notable("Diabetes")) }

        // Heart age, absorbed from the card that used to carry it alongside
        // fitness age. It belongs here rather than anywhere else because
        // `HeartAgeAnalyser` inverts *these* equations — the same SCORE2/ASCVD
        // run above, read backwards against an optimal-risk reference person. A
        // percentage and an age are the same finding in two units, and they were
        // on two different screens.
        //
        // Fitness age went to `FitnessInsight`. The one thing the split loses is
        // the side-by-side row, so the sentence it carried is said here instead.
        let ageAnalysis = HeartAgeAnalyser().analyse(samples: samples, profile: profile, now: now)
        if let heart = ageAnalysis.heart, let heartAge = heart.heartAge {
            drivers.append(InsightDriver(
                text: String(format: "Heart age %@%.0f%@", heart.isCapped ? "about " : "",
                             heartAge,
                             (heart.excessYears).map {
                                 abs($0) < 1 ? " — level with your actual age"
                                     : String(format: " — %.0f years %@ your actual age",
                                              abs($0), $0 > 0 ? "above" : "below")
                             } ?? ""),
                isNotable: (heart.excessYears ?? 0) >= 1))
            if let mine = heart.riskPercent, let optimal = heart.optimalRiskPercent {
                drivers.append(.notable(String(format: "10-year risk %.1f%% against %.1f%% at optimal levels — that gap is the modifiable part",
                                               mine, optimal)))
            }
            drivers.append(.routine("Heart age and fitness age can disagree — a fit heart can still carry high blood pressure. Fitness age is on the Fitness card."))
        }
        if let vascular = ageAnalysis.vascularAgeUsed {
            // A provider's own estimate, reported beside ours rather than folded
            // into it. Two models built on different inputs disagreeing is
            // information; averaging them away is not.
            drivers.append(.routine(String(format: "%@ estimates your vascular age at %.0f",
                                           ageAnalysis.vascularAgeSource ?? "Your wearable",
                                           vascular)))
        }

        var explanation: String
        if usedModels.count > 1 {
            explanation = String(format: "Estimated %.1f%% chance of a heart attack or stroke in the next 10 years (%@). This is the consensus of two validated models — %@ (%.1f%%) and %@ (%.1f%%) — shown as a range because they were built on different populations.",
                                 consensus, band.label,
                                 usedModels[0].name, usedModels[0].pct,
                                 usedModels[1].name, usedModels[1].pct)
        } else {
            explanation = String(format: "Estimated %.1f%% chance of a heart attack or stroke in the next 10 years (%@), computed with the %@ model from your age, sex, blood pressure, cholesterol and smoking status.",
                                 consensus, band.label, usedModels[0].name)
        }
        if assumedCholesterol {
            explanation += " An average cholesterol is assumed — add a recent blood test for a more accurate figure."
        }
        if !anyValid {
            explanation += " Note: these equations are validated for ages 40–79, so at your age this is indicative only — please discuss with a clinician."
        }

        // What each input is doing to the number.
        //
        // This card used to report blood pressure at weight 0 and nothing else,
        // so "How this is weighted" said *"Not a weighted average"* — which
        // conflated "nobody chose these proportions" (true) with "there are no
        // proportions" (false). `RiskAttribution` holds one factor at a time at
        // its optimal value and re-runs the same equations, which is the method
        // the card's own "that gap is the modifiable part" line already
        // describes. It reuses `HeartAgeModel.riskPercent`, so no coefficient is
        // written down twice.
        let subject = HeartAgeModel.Subject(
            sex: sex, race: profile.raceGroup, region: profile.score2Region,
            systolicBP: systolic, totalCholesterolMmol: totalChol,
            hdlCholesterolMmol: hdl, isSmoker: profile.isSmoker,
            hasDiabetes: profile.hasDiabetes, treatedForBP: profile.onBPMedication)
        let factors = RiskAttribution.factors(
            engines: usedModels.compactMap { HeartAgeModel.Engine(rawValue: $0.name) },
            subject: subject, age: age,
            cholesterolAssumed: assumedCholesterol)
        let systolicShare = factors.first { $0.metric == .bloodPressureSystolic }?.weight ?? 0

        // Blood pressure carries its share on the contribution itself rather
        // than as a second factor, so the overlay legend under "What goes into
        // this" reads the same number this section draws.
        var contributors = [MetricContribution(
            metric: .bloodPressureSystolic, higherIsBetter: false,
            weight: systolicShare, detail: "\(Int(systolic.rounded())) mmHg")]
        // VO₂max and vascular age, charted by this card's own section and named
        // in its drivers. `HeartAgeAnalyser` already reports them at weight 0
        // and reads them off the analysis rather than the samples, so the chart
        // cannot plot a different number than the driver line quotes.
        contributors += HeartAgeAnalyser.contributors(ageAnalysis)
            .filter { $0.metric != .bloodPressureSystolic }

        return InsightResult(
            id: id, title: title, primaryValue: consensus,
            headline: String(format: "%.1f%%", consensus),
            score: band.score, confidence: confidence,
            explanation: explanation, driverLines: drivers, unmetRequirements: unmet,
            contributors: contributors,
            weighting: .equation(usedModels.map(\.name).joined(separator: " and ")),
            otherFactors: factors.filter { $0.metric != .bloodPressureSystolic })
    }

    private func notYetResult(unmet: [GroundingRequirement]) -> InsightResult {
        InsightResult(
            id: id, title: title, primaryValue: nil,
            headline: "Add your details",
            score: nil, confidence: .low,
            explanation: "Provide a few one-off details (blood test, blood pressure, smoking status) and this will estimate your 10-year heart-attack and stroke risk using validated clinical models.",
            drivers: [], unmetRequirements: unmet)
    }

    /// The friendly band label. 5 / 10 / 20 % are the clinical thresholds and
    /// are what the copy says; the *dial* deliberately no longer shares them.
    func riskBand(pct: Double) -> (label: String, score: Double) {
        let label: String
        switch pct {
        case ..<5:   label = "low"
        case ..<10:  label = "low-to-moderate"
        case ..<20:  label = "moderate-to-high"
        default:     label = "high"
        }
        return (label, Self.score(pct: pct))
    }

    /// 10-year risk % → a 0–100 dial, continuous and strictly decreasing.
    ///
    /// This used to be the same four-step function as the label — {90, 72, 45,
    /// 20} — so 4.9 % dialled 90 and 5.1 % dialled 72: an 18-point drop across
    /// two tenths of a percentage point, and nothing at all moving between 10 %
    /// and 19.9 %. That is the defect already fixed in Vitals Check and Heart
    /// Age, and this card was missed.
    ///
    /// Risk is multiplicative — every SCORE2 and ASCVD coefficient is a
    /// log-hazard — so the continuous analogue of a risk band is a logistic in
    /// *log* risk. That is the same family as `HeartAgeAnalyser.score`, written
    /// here as a power because it reads better than an exp-of-log:
    ///
    ///     100 / (1 + (pct / centre)^exponent)
    ///
    /// `centre` and `exponent` are a least-squares fit to the four old anchors
    /// evaluated at their band midpoints (2.5 / 7.5 / 15 / 30 %), so no card's
    /// number jumps: 93.1 / 70.4 / 44.4 / 21.1 against the old 90 / 72 / 45 /
    /// 20. Clamped 1…99 for the reason Heart Age is — a perfect score and a
    /// hopeless one should both have to be earned.
    static func score(pct: Double) -> Double {
        let centre = 13.0        // % 10-year risk that dials 50
        let exponent = 1.575
        let p = Swift.max(0.01, pct)
        return Swift.max(1, Swift.min(99, 100 / (1 + pow(p / centre, exponent))))
    }
}
