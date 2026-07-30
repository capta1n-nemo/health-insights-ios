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
    /// smoking); blood pressure is the one sensed input.
    public var candidateMetrics: [MetricType] { [.bloodPressureSystolic] }

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

        // Resolve systolic BP: prefer a logged cuff reading, else a measured sample.
        let sbp = profile.cuffSystolic ?? samples.latestValue(.bloodPressureSystolic)

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
            : (assumedCholesterol || mandatoryUnsatisfied ? .moderate : .high)

        var drivers: [String] = []
        for m in usedModels { drivers.append(String(format: "%@: %.1f%%", m.name, m.pct)) }
        if usedModels.count > 1 {
            drivers.append(String(format: "Range across models: %.1f–%.1f%%", lo, hi))
        }
        // Surface any model dropped for being out of its validated age range.
        for m in modelResults where !m.ageValid && anyValid {
            drivers.append("\(m.name) not shown — outside its validated age range")
        }
        drivers.append("Age \(Int(age.rounded())), \(sex.displayName.lowercased())")
        drivers.append("Systolic BP \(Int(systolic.rounded())) mmHg")
        if assumedCholesterol {
            drivers.append("Cholesterol assumed average — add a blood test to improve accuracy")
        } else {
            drivers.append(String(format: "Total/HDL cholesterol %.1f/%.1f mmol/L", totalChol, hdl))
        }
        if profile.isSmoker { drivers.append("Current smoker") }
        if profile.hasDiabetes { drivers.append("Diabetes") }

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

        return InsightResult(
            id: id, title: title, primaryValue: consensus,
            headline: String(format: "%.1f%%", consensus),
            score: band.score, confidence: confidence,
            explanation: explanation, drivers: drivers, unmetRequirements: unmet)
    }

    private func notYetResult(unmet: [GroundingRequirement]) -> InsightResult {
        InsightResult(
            id: id, title: title, primaryValue: nil,
            headline: "Add your details",
            score: nil, confidence: .low,
            explanation: "Provide a few one-off details (blood test, blood pressure, smoking status) and this will estimate your 10-year heart-attack and stroke risk using validated clinical models.",
            drivers: [], unmetRequirements: unmet)
    }

    /// Map risk % to a friendly band + a dial score where lower risk = higher score.
    private func riskBand(pct: Double) -> (label: String, score: Double) {
        switch pct {
        case ..<5:   return ("low", 90)
        case ..<10:  return ("low-to-moderate", 72)
        case ..<20:  return ("moderate-to-high", 45)
        default:     return ("high", 20)
        }
    }
}
