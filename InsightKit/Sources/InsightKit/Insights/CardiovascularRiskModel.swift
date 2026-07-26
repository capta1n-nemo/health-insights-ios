import Foundation

/// Ten-year cardiovascular risk from **published, peer-reviewed equations** —
/// not a black box. Two complementary models are implemented:
///
///  • **SCORE2 / SCORE2-OP** — 2021 European Society of Cardiology guidelines.
///    Coefficients & region recalibration scales from Eur Heart J. 2021;42(25).
///  • **ASCVD Pooled Cohort Equations** — 2013 ACC/AHA guideline
///    (Goff et al., Circulation 2013), sex- and race-specific.
///
/// The functions are deterministic and side-effect free so they can be checked
/// directly against the worked examples in those papers (see the unit tests).
///
/// ⚠️ These estimate population risk; they are decision *support*, not a
/// diagnosis. The app surfaces them with that framing.
public enum CardiovascularRiskModel {

    // MARK: - SCORE2 / SCORE2-OP

    /// Inputs for SCORE2. Cholesterol in mmol/L, SBP in mmHg, age in years.
    public struct SCORE2Input: Sendable {
        public var age: Double
        public var sex: BiologicalSex
        public var isSmoker: Bool
        public var systolicBP: Double
        public var totalCholesterol: Double  // mmol/L
        public var hdlCholesterol: Double     // mmol/L
        public var region: SCORE2RiskRegion

        public init(age: Double, sex: BiologicalSex, isSmoker: Bool, systolicBP: Double,
                    totalCholesterol: Double, hdlCholesterol: Double, region: SCORE2RiskRegion) {
            self.age = age
            self.sex = sex
            self.isSmoker = isSmoker
            self.systolicBP = systolicBP
            self.totalCholesterol = totalCholesterol
            self.hdlCholesterol = hdlCholesterol
            self.region = region
        }
    }

    /// 10-year fatal + non-fatal CVD risk as a fraction (0…1).
    public static func score2Risk(_ i: SCORE2Input) -> Double {
        // Centred, scaled transforms per the published algorithm.
        let cage = (i.age - 60) / 5
        let csbp = (i.systolicBP - 120) / 20
        let ctchol = i.totalCholesterol - 6
        let chdl = (i.hdlCholesterol - 1.3) / 0.5
        let smk = i.isSmoker ? 1.0 : 0.0

        // Sex-specific coefficients and baseline survival.
        let c: (cage: Double, smk: Double, csbp: Double, ctchol: Double, chdl: Double,
                smkAge: Double, sbpAge: Double, cholAge: Double, hdlAge: Double, s0: Double)
        switch i.sex {
        case .male:
            c = (0.3742, 0.6012, 0.2777, 0.1458, -0.2698,
                 -0.0755, -0.0255, -0.0281, 0.0426, 0.9605)
        case .female:
            c = (0.4648, 0.7744, 0.3131, 0.1002, -0.2606,
                 -0.1088, -0.0277, -0.0226, 0.0613, 0.9776)
        }

        let lp = c.cage * cage
            + c.smk * smk
            + c.csbp * csbp
            + c.ctchol * ctchol
            + c.chdl * chdl
            + c.smkAge * (smk * cage)
            + c.sbpAge * (csbp * cage)
            + c.cholAge * (ctchol * cage)
            + c.hdlAge * (chdl * cage)

        let uncalibrated = 1 - pow(c.s0, exp(lp))

        // Region + sex recalibration (Eur Heart J 2021;42(25), Supplement).
        let scale = score2Scale(sex: i.sex, region: i.region)
        let calibrated = 1 - exp(-exp(scale.s1 + scale.s2 * log(-log(1 - uncalibrated))))
        return max(0, min(1, calibrated))
    }

    private static func score2Scale(sex: BiologicalSex, region: SCORE2RiskRegion) -> (s1: Double, s2: Double) {
        switch (sex, region) {
        case (.male, .low):        return (-0.5699, 0.7476)
        case (.male, .moderate):   return (-0.1565, 0.8009)
        case (.male, .high):       return (0.3207, 0.9360)
        case (.male, .veryHigh):   return (0.5836, 0.8294)
        case (.female, .low):      return (-0.7380, 0.7019)
        case (.female, .moderate): return (-0.3143, 0.7701)
        case (.female, .high):     return (0.5710, 0.9369)
        case (.female, .veryHigh): return (0.9412, 0.8329)
        }
    }

    // MARK: - ASCVD Pooled Cohort Equations

    public struct ASCVDInput: Sendable {
        public var age: Double
        public var sex: BiologicalSex
        public var race: ASCVDRaceGroup
        public var totalCholesterol: Double  // mg/dL
        public var hdlCholesterol: Double     // mg/dL
        public var systolicBP: Double         // mmHg
        public var treatedForBP: Bool
        public var isSmoker: Bool
        public var hasDiabetes: Bool

        public init(age: Double, sex: BiologicalSex, race: ASCVDRaceGroup,
                    totalCholesterol: Double, hdlCholesterol: Double, systolicBP: Double,
                    treatedForBP: Bool, isSmoker: Bool, hasDiabetes: Bool) {
            self.age = age
            self.sex = sex
            self.race = race
            self.totalCholesterol = totalCholesterol
            self.hdlCholesterol = hdlCholesterol
            self.systolicBP = systolicBP
            self.treatedForBP = treatedForBP
            self.isSmoker = isSmoker
            self.hasDiabetes = hasDiabetes
        }
    }

    /// 10-year hard ASCVD risk as a fraction (0…1). Cholesterol here is mg/dL.
    public static func ascvdRisk(_ i: ASCVDInput) -> Double {
        let lnAge = log(i.age)
        let lnTChol = log(i.totalCholesterol)
        let lnHDL = log(i.hdlCholesterol)
        let lnSBP = log(i.systolicBP)
        let smoker = i.isSmoker ? 1.0 : 0.0
        let diabetes = i.hasDiabetes ? 1.0 : 0.0

        var sum = 0.0
        let s0: Double
        let mean: Double

        switch (i.sex, i.race) {
        case (.female, .whiteOrOther):
            sum += -29.799 * lnAge
            sum += 4.884 * (lnAge * lnAge)
            sum += 13.540 * lnTChol
            sum += -3.114 * (lnAge * lnTChol)
            sum += -13.578 * lnHDL
            sum += 3.149 * (lnAge * lnHDL)
            sum += (i.treatedForBP ? 2.019 : 1.957) * lnSBP
            sum += 7.574 * smoker
            sum += -1.665 * (lnAge * smoker)
            sum += 0.661 * diabetes
            s0 = 0.9665; mean = -29.18
        case (.male, .whiteOrOther):
            sum += 12.344 * lnAge
            sum += 11.853 * lnTChol
            sum += -2.664 * (lnAge * lnTChol)
            sum += -7.990 * lnHDL
            sum += 1.769 * (lnAge * lnHDL)
            sum += (i.treatedForBP ? 1.797 : 1.764) * lnSBP
            sum += 7.837 * smoker
            sum += -1.795 * (lnAge * smoker)
            sum += 0.658 * diabetes
            s0 = 0.9144; mean = 61.18
        case (.female, .africanAmerican):
            sum += 17.114 * lnAge
            sum += 0.940 * lnTChol
            sum += -18.920 * lnHDL
            sum += 4.475 * (lnAge * lnHDL)
            sum += (i.treatedForBP ? 29.291 : 27.820) * lnSBP
            sum += (i.treatedForBP ? -6.432 : -6.087) * (lnAge * lnSBP)
            sum += 0.691 * smoker
            sum += 0.874 * diabetes
            s0 = 0.9533; mean = 86.61
        case (.male, .africanAmerican):
            sum += 2.469 * lnAge
            sum += 0.302 * lnTChol
            sum += -0.307 * lnHDL
            sum += (i.treatedForBP ? 1.916 : 1.809) * lnSBP
            sum += 0.549 * smoker
            sum += 0.645 * diabetes
            s0 = 0.8954; mean = 19.54
        }

        let risk = 1 - pow(s0, exp(sum - mean))
        return max(0, min(1, risk))
    }

    // MARK: - Unit conversion helpers

    /// Convert cholesterol mmol/L → mg/dL (factor 38.67, molar mass of cholesterol).
    public static func mgdL(fromMmolPerL v: Double) -> Double { v * 38.67 }
    /// Convert cholesterol mg/dL → mmol/L.
    public static func mmolPerL(fromMgdL v: Double) -> Double { v / 38.67 }
}
