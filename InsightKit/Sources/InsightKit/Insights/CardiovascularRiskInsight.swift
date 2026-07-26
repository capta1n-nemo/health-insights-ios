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

    public var requirements: [GroundingRequirement] {
        var reqs: [GroundingRequirement] = [
            .init(kind: .dateOfBirth, isMandatory: true,
                  rationale: "Age is the strongest driver of 10-year cardiovascular risk."),
            .init(kind: .biologicalSex, isMandatory: true,
                  rationale: "The risk equations are calibrated separately by sex."),
            .init(kind: .totalCholesterol, isMandatory: true,
                  rationale: "From a recent blood test — a core input to the risk model."),
            .init(kind: .hdlCholesterol, isMandatory: true,
                  rationale: "'Good' cholesterol; lowers estimated risk."),
            .init(kind: .currentSmoker, isMandatory: true,
                  rationale: "Smoking roughly doubles cardiovascular risk."),
            .init(kind: .cuffSystolic, isMandatory: true,
                  rationale: "A real cuff systolic reading grounds the estimate.")
        ]
        let needsSCORE2 = preferredEngine != .ascvd
        let needsASCVD = preferredEngine != .score2
        if needsSCORE2 {
            reqs.append(.init(kind: .score2Region, isMandatory: false,
                              rationale: "Calibrates SCORE2 to your region (Australia ≈ low-risk region)."))
        }
        if needsASCVD {
            reqs.append(.init(kind: .hasDiabetes, isMandatory: true,
                              rationale: "Diabetes is an independent risk factor in the ASCVD model."))
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

        // Availability is about presence, not freshness: as long as the core
        // values exist we compute, and let staleness only soften the confidence.
        guard let age = profile.age(asOf: now),
              let sex = profile.sex,
              let totalChol = profile.totalCholesterol,
              let hdl = profile.hdlCholesterol,
              let systolic = sbp else {
            return notYetResult(unmet: unmet)
        }

        // Compute whichever models this engine uses.
        var modelResults: [(name: String, pct: Double)] = []
        if preferredEngine != .ascvd {
            let s2 = CardiovascularRiskModel.score2Risk(.init(
                age: age, sex: sex, isSmoker: profile.isSmoker, systolicBP: systolic,
                totalCholesterol: totalChol, hdlCholesterol: hdl, region: profile.score2Region))
            modelResults.append(("SCORE2", s2 * 100))
        }
        if preferredEngine != .score2 {
            let ascvd = CardiovascularRiskModel.ascvdRisk(.init(
                age: age, sex: sex, race: profile.raceGroup,
                totalCholesterol: CardiovascularRiskModel.mgdL(fromMmolPerL: totalChol),
                hdlCholesterol: CardiovascularRiskModel.mgdL(fromMmolPerL: hdl),
                systolicBP: systolic, treatedForBP: profile.onBPMedication,
                isSmoker: profile.isSmoker, hasDiabetes: profile.hasDiabetes))
            modelResults.append(("ASCVD", ascvd * 100))
        }

        let pcts = modelResults.map(\.pct)
        let consensus = pcts.reduce(0, +) / Double(pcts.count)
        let lo = pcts.min() ?? consensus
        let hi = pcts.max() ?? consensus
        let band = riskBand(pct: consensus)

        // High confidence when every mandatory input is present and fresh; a
        // stale or missing mandatory input softens it. Optional inputs (region,
        // ethnicity, BP-med) never reduce confidence.
        let mandatoryUnsatisfied = statuses.contains { $0.0.isMandatory && $0.1 != .satisfied }
        let confidence: InsightConfidence = mandatoryUnsatisfied ? .moderate : .high

        var drivers: [String] = []
        for m in modelResults { drivers.append(String(format: "%@: %.1f%%", m.name, m.pct)) }
        if modelResults.count > 1 {
            drivers.append(String(format: "Range across models: %.1f–%.1f%%", lo, hi))
        }
        drivers.append("Age \(Int(age.rounded())), \(sex.displayName.lowercased())")
        drivers.append("Systolic BP \(Int(systolic.rounded())) mmHg")
        drivers.append(String(format: "Total/HDL cholesterol %.1f/%.1f mmol/L", totalChol, hdl))
        if profile.isSmoker { drivers.append("Current smoker") }
        if profile.hasDiabetes { drivers.append("Diabetes") }

        let explanation: String
        if modelResults.count > 1 {
            explanation = String(format: "Estimated %.1f%% chance of a heart attack or stroke in the next 10 years (%@). This is the consensus of two validated models — SCORE2 (%.1f%%) and ASCVD (%.1f%%) — shown as a range because they were built on different populations.",
                                 consensus, band.label, modelResults[0].pct, modelResults[1].pct)
        } else {
            explanation = String(format: "Estimated %.1f%% chance of a heart attack or stroke in the next 10 years (%@), computed with the %@ model from your age, sex, blood pressure, cholesterol and smoking status.",
                                 consensus, band.label, modelResults[0].name)
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
