import Foundation

/// "Heart age" (vascular age): the age at which someone with *optimal* risk
/// factors would carry the same 10-year cardiovascular risk as you carry now.
///
/// This is the published vascular-age method — the risk equation is not modified,
/// it is inverted over age against an optimal-factor reference person
/// (D'Agostino et al., *Circulation* 2008;117(6):743–753, the Framingham
/// vascular-age formulation; the same framing used by the JBS3 and NHS
/// heart-age calculators). Here it is applied to the two equations the app
/// already ships, and reported as a consensus with its range, exactly as the
/// underlying risk figure is.
public enum HeartAgeModel {

    /// Which published equation a heart age came from.
    public enum Engine: String, Sendable, Equatable, CaseIterable {
        case score2 = "SCORE2"
        case ascvd = "ASCVD"

        /// The age band the equation was derived and validated in. Inverting
        /// outside it would be extrapolation, so the search is bounded by it.
        public var validatedAgeRange: ClosedRange<Double> {
            switch self {
            case .score2: return 40...69
            case .ascvd: return 40...79
            }
        }
    }

    /// The optimal-risk-factor reference person: never-smoker, no diabetes,
    /// untreated systolic 120 mmHg, total cholesterol 4.65 mmol/L (180 mg/dL),
    /// HDL 1.55 mmol/L (60 mg/dL) — the "optimal" factor set used by the
    /// vascular-age literature.
    public enum OptimalReference {
        public static let systolicBP: Double = 120
        public static let totalCholesterolMmol: Double = 4.65
        public static let hdlCholesterolMmol: Double = 1.55
    }

    /// The risk-factor set a heart age is computed from — everything the two
    /// equations need except age, which is what gets solved for.
    public struct Subject: Sendable, Equatable {
        public var sex: BiologicalSex
        public var race: ASCVDRaceGroup
        public var region: SCORE2RiskRegion
        public var systolicBP: Double
        public var totalCholesterolMmol: Double
        public var hdlCholesterolMmol: Double
        public var isSmoker: Bool
        public var hasDiabetes: Bool
        public var treatedForBP: Bool

        public init(sex: BiologicalSex, race: ASCVDRaceGroup, region: SCORE2RiskRegion,
                    systolicBP: Double, totalCholesterolMmol: Double,
                    hdlCholesterolMmol: Double, isSmoker: Bool,
                    hasDiabetes: Bool, treatedForBP: Bool) {
            self.sex = sex
            self.race = race
            self.region = region
            self.systolicBP = systolicBP
            self.totalCholesterolMmol = totalCholesterolMmol
            self.hdlCholesterolMmol = hdlCholesterolMmol
            self.isSmoker = isSmoker
            self.hasDiabetes = hasDiabetes
            self.treatedForBP = treatedForBP
        }

        /// The same person with every *modifiable* factor at its optimal value.
        /// Sex, race group and region stay put — they are not modifiable, and
        /// swapping them would compare you against a different person entirely.
        public var withOptimalFactors: Subject {
            var copy = self
            copy.systolicBP = OptimalReference.systolicBP
            copy.totalCholesterolMmol = OptimalReference.totalCholesterolMmol
            copy.hdlCholesterolMmol = OptimalReference.hdlCholesterolMmol
            copy.isSmoker = false
            copy.hasDiabetes = false
            copy.treatedForBP = false
            return copy
        }
    }

    /// Both equations start at 40, so this is the floor for every heart age. The
    /// ceiling is per-engine (`Engine.validatedAgeRange`): SCORE2 stops at 69,
    /// ASCVD at 79, and solving past either would mean reading a reference age
    /// off a curve the equation was never fitted to.
    public static let youngestReportable: Double = 40

    /// 10-year risk as a percentage (0…100) for one engine at a given age.
    public static func riskPercent(_ engine: Engine, subject: Subject, age: Double) -> Double {
        switch engine {
        case .score2:
            return CardiovascularRiskModel.score2Risk(.init(
                age: age, sex: subject.sex, isSmoker: subject.isSmoker,
                systolicBP: subject.systolicBP,
                totalCholesterol: subject.totalCholesterolMmol,
                hdlCholesterol: subject.hdlCholesterolMmol,
                region: subject.region)) * 100
        case .ascvd:
            return CardiovascularRiskModel.ascvdRisk(.init(
                age: age, sex: subject.sex, race: subject.race,
                totalCholesterol: CardiovascularRiskModel.mgdL(fromMmolPerL: subject.totalCholesterolMmol),
                hdlCholesterol: CardiovascularRiskModel.mgdL(fromMmolPerL: subject.hdlCholesterolMmol),
                systolicBP: subject.systolicBP, treatedForBP: subject.treatedForBP,
                isSmoker: subject.isSmoker, hasDiabetes: subject.hasDiabetes)) * 100
        }
    }

    /// One engine's answer.
    public struct Reading: Sendable, Equatable {
        public let engine: Engine
        public let heartAge: Double
        public let excessYears: Double
        /// True when the solution ran into an end of this engine's validated band,
        /// i.e. the honest answer is "at least 69" (SCORE2) or "at least 79"
        /// (ASCVD) rather than the number itself.
        public let isCapped: Bool
        public let riskPercent: Double
        /// What an optimal-factor person of the same real age would carry.
        public let optimalRiskPercent: Double

        public init(engine: Engine, heartAge: Double, excessYears: Double,
                    isCapped: Bool, riskPercent: Double, optimalRiskPercent: Double) {
            self.engine = engine
            self.heartAge = heartAge
            self.excessYears = excessYears
            self.isCapped = isCapped
            self.riskPercent = riskPercent
            self.optimalRiskPercent = optimalRiskPercent
        }
    }

    /// Solve `curve(age) = riskPercent` inside `range`.
    ///
    /// A stepped scan with linear interpolation rather than bisection: the
    /// optimal-factor reference curve is monotone across 40–79 for every
    /// sub-model, but the ASCVD female coefficients include a log-age quadratic
    /// that turns over below 30, so a running maximum keeps the inversion
    /// single-valued even if the band is ever widened.
    static func solveAge(riskPercent target: Double, in range: ClosedRange<Double>,
                         curve: (Double) -> Double) -> (age: Double, capped: Bool) {
        let step = 0.25
        var previousAge = range.lowerBound
        var previousRisk = curve(range.lowerBound)
        if target <= previousRisk {
            return (range.lowerBound, target < previousRisk)
        }
        var age = range.lowerBound + step
        while age <= range.upperBound {
            let risk = Swift.max(previousRisk, curve(age))
            if risk >= target {
                let span = risk - previousRisk
                let fraction = span > 0 ? (target - previousRisk) / span : 0
                return (previousAge + fraction * (age - previousAge), false)
            }
            previousRisk = risk
            previousAge = age
            age += step
        }
        return (range.upperBound, true)
    }

    public static func reading(_ engine: Engine, subject: Subject, age: Double) -> Reading {
        let own = riskPercent(engine, subject: subject, age: age)
        let optimal = subject.withOptimalFactors
        let solved = solveAge(riskPercent: own, in: engine.validatedAgeRange) {
            riskPercent(engine, subject: optimal, age: $0)
        }
        return Reading(engine: engine, heartAge: solved.age,
                       excessYears: solved.age - age, isCapped: solved.capped,
                       riskPercent: own,
                       optimalRiskPercent: riskPercent(engine, subject: optimal, age: age))
    }

    /// Consensus across the engines whose validated band contains the person's
    /// real age — the same "both models, reported as a range" discipline the risk
    /// insight uses, since neither equation is authoritative on its own.
    public struct Output: Sendable, Equatable {
        public let chronologicalAge: Double
        public let readings: [Reading]

        public init(chronologicalAge: Double, readings: [Reading]) {
            self.chronologicalAge = chronologicalAge
            self.readings = readings
        }

        public var heartAge: Double? {
            guard !readings.isEmpty else { return nil }
            return readings.map(\.heartAge).reduce(0, +) / Double(readings.count)
        }
        public var excessYears: Double? { heartAge.map { $0 - chronologicalAge } }
        public var lowestHeartAge: Double? { readings.map(\.heartAge).min() }
        public var highestHeartAge: Double? { readings.map(\.heartAge).max() }
        public var isCapped: Bool { readings.contains { $0.isCapped } }
        public var riskPercent: Double? {
            guard !readings.isEmpty else { return nil }
            return readings.map(\.riskPercent).reduce(0, +) / Double(readings.count)
        }
        public var optimalRiskPercent: Double? {
            guard !readings.isEmpty else { return nil }
            return readings.map(\.optimalRiskPercent).reduce(0, +) / Double(readings.count)
        }
    }

    public static func evaluate(subject: Subject, age: Double) -> Output? {
        let engines = Engine.allCases.filter { $0.validatedAgeRange.contains(age) }
        guard !engines.isEmpty else { return nil }
        return Output(chronologicalAge: age,
                      readings: engines.map { reading($0, subject: subject, age: age) })
    }

    // MARK: - Lifetime framing

    /// Risk at a future age with today's numbers held constant.
    ///
    /// Deliberately *not* a lifetime-risk model: no equation here is validated
    /// past 79, and compounding decades of 10-year risk would be inventing a
    /// number. Instead the same published equations are run at ages they *are*
    /// validated for, which answers the question people actually mean — "where
    /// is this heading if nothing changes?" — without fabricating anything.
    public struct Projection: Sendable, Equatable {
        public let age: Double
        public let percent: Double
        public let engines: [Engine]

        public init(age: Double, percent: Double, engines: [Engine]) {
            self.age = age
            self.percent = percent
            self.engines = engines
        }
    }

    public static func projection(subject: Subject, currentAge: Double,
                                  atAges candidates: [Double] = [50, 60, 70, 79]) -> [Projection] {
        candidates.compactMap { age -> Projection? in
            // Only look far enough ahead to be a different answer.
            guard age >= currentAge + 5 else { return nil }
            let engines = Engine.allCases.filter { $0.validatedAgeRange.contains(age) }
            guard !engines.isEmpty else { return nil }
            let percents = engines.map { riskPercent($0, subject: subject, age: age) }
            return Projection(age: age,
                              percent: percents.reduce(0, +) / Double(percents.count),
                              engines: engines)
        }
    }
}
