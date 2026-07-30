import Foundation

// Two age-framings of data the app already holds. A percentage is easy to shrug
// off; "your heart is running eight years ahead of you" is not. Both numbers are
// derived from models already in the app — nothing new is invented here, the
// existing outputs are re-expressed on the axis people actually feel: years.

// MARK: - Fitness age (from VO₂max)

/// The age at which your VO₂max would be the reference value for your sex.
///
/// This inverts the *same* age/sex cardiorespiratory-fitness norms
/// `HeartHealthScore.vo2Score` already scores against, rather than importing a
/// separate published fitness-age regression (e.g. HUNT), so the two numbers can
/// never disagree about what "average for your age" means.
public enum FitnessAgeModel {

    /// Reporting bounds. Outside them the norm table is extrapolation, so the
    /// result is clamped and flagged rather than quietly extended.
    public static let youngestReportable: Double = 20
    public static let oldestReportable: Double = 75

    /// The norm table's reference VO₂max at the midpoint of each of its age
    /// bands. `HeartHealthScore` uses the bands; interpolating between their
    /// midpoints gives the same curve as a continuous, invertible line.
    static func anchors(for sex: BiologicalSex) -> [(age: Double, vo2: Double)] {
        switch sex {
        case .male:   return [(25, 48), (35, 44), (45, 40), (55, 36), (65, 32)]
        case .female: return [(25, 41), (35, 38), (45, 34), (55, 31), (65, 28)]
        }
    }

    /// Reference VO₂max for an age: piecewise-linear between the anchors,
    /// continuing the adjacent slope beyond the first and last of them.
    ///
    /// Strictly decreasing everywhere, which is what makes it invertible.
    public static func referenceVO2(age: Double, sex: BiologicalSex) -> Double {
        let points = anchors(for: sex)
        if age <= points[0].age {
            let slope = (points[1].vo2 - points[0].vo2) / (points[1].age - points[0].age)
            return points[0].vo2 + slope * (age - points[0].age)
        }
        for index in 1..<points.count where age <= points[index].age {
            let low = points[index - 1]
            let high = points[index]
            let fraction = (age - low.age) / (high.age - low.age)
            return low.vo2 + (high.vo2 - low.vo2) * fraction
        }
        let last = points[points.count - 1]
        let previous = points[points.count - 2]
        let slope = (last.vo2 - previous.vo2) / (last.age - previous.age)
        return last.vo2 + slope * (age - last.age)
    }

    public struct Output: Sendable, Equatable {
        public let fitnessAge: Double
        public let vo2: Double
        /// The reference VO₂max for the person's real age, when it is known.
        public let referenceForOwnAge: Double?
        /// Chronological age − fitness age: positive means fitter than your years.
        public let yearsYounger: Double?
        /// True when the VO₂max sits outside the reportable band and the age was
        /// clamped to it ("20 or younger", "75 or older").
        public let isCapped: Bool

        public init(fitnessAge: Double, vo2: Double, referenceForOwnAge: Double?,
                    yearsYounger: Double?, isCapped: Bool) {
            self.fitnessAge = fitnessAge
            self.vo2 = vo2
            self.referenceForOwnAge = referenceForOwnAge
            self.yearsYounger = yearsYounger
            self.isCapped = isCapped
        }
    }

    public static func evaluate(vo2: Double, sex: BiologicalSex,
                               chronologicalAge: Double? = nil) -> Output {
        let fittest = referenceVO2(age: youngestReportable, sex: sex)
        let least = referenceVO2(age: oldestReportable, sex: sex)

        var age = youngestReportable
        var capped = false
        if vo2 >= fittest {
            capped = vo2 > fittest
        } else if vo2 <= least {
            age = oldestReportable
            capped = vo2 < least
        } else {
            // Monotone decreasing between the bounds, so bisection converges.
            var low = youngestReportable
            var high = oldestReportable
            for _ in 0..<50 {
                let mid = (low + high) / 2
                if referenceVO2(age: mid, sex: sex) > vo2 { low = mid } else { high = mid }
            }
            age = (low + high) / 2
        }

        return Output(
            fitnessAge: age,
            vo2: vo2,
            referenceForOwnAge: chronologicalAge.map { referenceVO2(age: $0, sex: sex) },
            yearsYounger: chronologicalAge.map { $0 - age },
            isCapped: capped)
    }
}

// MARK: - Heart age (vascular age from the risk equations)

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

// MARK: - Insight

/// Heart age + fitness age as one card.
///
/// They degrade independently and that is the point: fitness age needs only a
/// VO₂max reading (which an Apple Watch supplies unprompted), while heart age
/// needs the grounding facts the risk equations require. Someone who has
/// entered nothing still gets a real number as soon as their watch reports.
public struct HeartAgeInsight: InsightModel {
    public let id: InsightID = .heartAge
    public let title = "Heart & Fitness Age"

    public init() {}

    // Same population-average fallbacks the risk insight uses, so the two cards
    // can never quietly disagree about what was assumed.
    static let defaultTotalCholesterol = 5.2
    static let defaultHDLCholesterol = 1.3

    public var requirements: [GroundingRequirement] {
        [
            .init(kind: .dateOfBirth, isMandatory: true,
                  rationale: "Both ages are read against your real one."),
            .init(kind: .biologicalSex, isMandatory: true,
                  rationale: "Fitness norms and the risk equations are sex-specific."),
            .init(kind: .cuffSystolic, isMandatory: false,
                  rationale: "A blood-pressure reading is what turns risk into a heart age."),
            .init(kind: .totalCholesterol, isMandatory: false,
                  rationale: "From a blood test — sharpens the heart age (an average is assumed until then)."),
            .init(kind: .hdlCholesterol, isMandatory: false,
                  rationale: "'Good' cholesterol; sharpens the heart age."),
            .init(kind: .currentSmoker, isMandatory: false,
                  rationale: "Smoking is one of the largest single contributors to heart age.")
        ]
    }

    /// Everything the screen needs, computed once. The view renders this rather
    /// than parsing the driver strings back into numbers.
    public struct Analysis: Sendable, Equatable {
        public let chronologicalAge: Double?
        public let heart: HeartAgeModel.Output?
        public let fitness: FitnessAgeModel.Output?
        public let projections: [HeartAgeModel.Projection]
        public let assumedCholesterol: Bool
        /// The blood pressure the heart age was computed from. Its absence is why
        /// there is no heart age; so is an age outside 40–79, and the two need
        /// different things said about them.
        public let systolicUsed: Double?

        public init(chronologicalAge: Double?, heart: HeartAgeModel.Output?,
                    fitness: FitnessAgeModel.Output?,
                    projections: [HeartAgeModel.Projection], assumedCholesterol: Bool,
                    systolicUsed: Double? = nil) {
            self.chronologicalAge = chronologicalAge
            self.heart = heart
            self.fitness = fitness
            self.projections = projections
            self.assumedCholesterol = assumedCholesterol
            self.systolicUsed = systolicUsed
        }

        /// The age we lead with: the clinical one when it exists, else fitness.
        public var headlineAge: Double? { heart?.heartAge ?? fitness?.fitnessAge }
        public var headlineExcessYears: Double? {
            if let excess = heart?.excessYears { return excess }
            guard let younger = fitness?.yearsYounger else { return nil }
            return -younger
        }
    }

    public func analyse(samples: [HealthMetricSample], profile: UserHealthProfile,
                        now: Date) -> Analysis {
        let age = profile.age(asOf: now)
        guard let sex = profile.sex else {
            return Analysis(chronologicalAge: age, heart: nil, fitness: nil,
                            projections: [], assumedCholesterol: false)
        }

        let fitness = samples.latestValue(.vo2Max).map {
            FitnessAgeModel.evaluate(vo2: $0, sex: sex, chronologicalAge: age)
        }

        // Heart age needs a blood pressure and a real age; everything else falls
        // back to the same averages the risk card assumes.
        let systolic = profile.cuffSystolic ?? samples.latestValue(.bloodPressureSystolic)
        guard let age, let systolic else {
            return Analysis(chronologicalAge: age, heart: nil, fitness: fitness,
                            projections: [], assumedCholesterol: false)
        }
        let assumed = profile.totalCholesterol == nil || profile.hdlCholesterol == nil
        let subject = HeartAgeModel.Subject(
            sex: sex, race: profile.raceGroup, region: profile.score2Region,
            systolicBP: systolic,
            totalCholesterolMmol: profile.totalCholesterol ?? Self.defaultTotalCholesterol,
            hdlCholesterolMmol: profile.hdlCholesterol ?? Self.defaultHDLCholesterol,
            isSmoker: profile.isSmoker, hasDiabetes: profile.hasDiabetes,
            treatedForBP: profile.onBPMedication)

        return Analysis(
            chronologicalAge: age,
            heart: HeartAgeModel.evaluate(subject: subject, age: age),
            fitness: fitness,
            projections: HeartAgeModel.projection(subject: subject, currentAge: age),
            assumedCholesterol: assumed,
            systolicUsed: systolic)
    }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                         now: Date) -> InsightResult {
        let unmet = unmetRequirements(profile: profile, now: now)
        let analysis = analyse(samples: samples, profile: profile, now: now)

        guard analysis.headlineAge != nil else {
            return InsightResult(
                id: id, title: title, primaryValue: nil, headline: "Add your details",
                score: nil, confidence: .low,
                explanation: "Add your date of birth and sex, and this turns your numbers into two ages you can feel: how old your heart is behaving, and how old your fitness is.",
                drivers: [], unmetRequirements: unmet)
        }

        var drivers: [String] = []
        if let age = analysis.chronologicalAge {
            drivers.append("Your age: \(Int(age.rounded()))")
        }

        if let heart = analysis.heart, let heartAge = heart.heartAge,
           let excess = heart.excessYears {
            drivers.append("Heart age: \(Self.heartAgePhrase(heartAge, capped: heart.isCapped)) — \(Self.excessPhrase(excess))")
            if heart.readings.count > 1 {
                for reading in heart.readings {
                    drivers.append(String(format: "%@ puts it at %@", reading.engine.rawValue,
                                          Self.heartAgePhrase(reading.heartAge, capped: reading.isCapped)))
                }
            }
            if let mine = heart.riskPercent, let optimal = heart.optimalRiskPercent {
                drivers.append(String(format: "10-year risk %.1f%% vs %.1f%% at optimal levels — that gap is the modifiable part",
                                      mine, optimal))
            }
        }

        if let fitness = analysis.fitness {
            drivers.append(String(format: "Fitness age: %@ (VO₂max %.0f mL/kg·min)",
                                  Self.fitnessAgePhrase(fitness.fitnessAge, capped: fitness.isCapped),
                                  fitness.vo2))
            if let reference = fitness.referenceForOwnAge {
                drivers.append(String(format: "Reference for your age: %.0f mL/kg·min", reference))
            }
        } else {
            drivers.append("No cardio-fitness reading yet — an Apple Watch estimates VO₂max on outdoor walks and runs, and Oura reports one too")
        }

        // A provider's own vascular-age estimate, shown beside ours rather than
        // folded into it. Two models built on different inputs disagreeing is
        // information; averaging them away is not.
        if let vascular = samples.samples(of: .vascularAge).last {
            var line = String(format: "%@ estimates your vascular age at %.0f",
                              vascular.source.displayName, vascular.value)
            if let age = analysis.chronologicalAge {
                let gap = vascular.value - age
                if abs(gap) < 1 {
                    line += " — level with your actual age"
                } else {
                    line += String(format: " — %.0f year%@ %@ your actual age",
                                   abs(gap), abs(gap) < 1.5 ? "" : "s", gap > 0 ? "above" : "below")
                }
            }
            drivers.append(line)
        }

        for projection in analysis.projections {
            drivers.append(String(format: "At %.0f, if today's numbers hold: about %.1f%%",
                                  projection.age, projection.percent))
        }
        if analysis.assumedCholesterol && analysis.heart != nil {
            drivers.append("Cholesterol assumed average — add a blood test to sharpen the heart age")
        }

        return InsightResult(
            id: id, title: title,
            primaryValue: analysis.headlineAge,
            headline: Self.headline(analysis),
            score: Self.score(analysis),
            confidence: Self.confidence(analysis, profile: profile, now: now),
            explanation: Self.explanation(analysis),
            drivers: drivers, unmetRequirements: unmet)
    }

    // MARK: - Presentation helpers

    /// "52", or "80 or older" when the solution hit a reporting bound. `floor` is
    /// the model's own lower bound, which is what says whether a capped answer
    /// ran off the young end or the old end.
    static func agePhrase(_ age: Double, capped: Bool, floor: Double) -> String {
        let rounded = Int(age.rounded())
        guard capped else { return "\(rounded)" }
        return age <= floor ? "\(rounded) or younger" : "\(rounded) or older"
    }

    static func heartAgePhrase(_ age: Double, capped: Bool) -> String {
        agePhrase(age, capped: capped, floor: HeartAgeModel.youngestReportable)
    }

    static func fitnessAgePhrase(_ age: Double, capped: Bool) -> String {
        agePhrase(age, capped: capped, floor: FitnessAgeModel.youngestReportable)
    }

    static func excessPhrase(_ excess: Double) -> String {
        let years = abs(excess)
        if years < 1 { return "about the same as your real age" }
        let unit = years < 2 ? "year" : "years"
        return excess > 0
            ? String(format: "%.0f %@ older than you are", years, unit)
            : String(format: "%.0f %@ younger than you are", years, unit)
    }

    static func headline(_ analysis: Analysis) -> String {
        if let heart = analysis.heart, let heartAge = heart.heartAge {
            return "Heart age \(heartAgePhrase(heartAge, capped: heart.isCapped))"
        }
        if let fitness = analysis.fitness {
            return "Fitness age \(fitnessAgePhrase(fitness.fitnessAge, capped: fitness.isCapped))"
        }
        return "Add your details"
    }

    /// Dial score: level with your real age reads 75, every excess year costs 5,
    /// every year in hand earns 5. Lower age = better, so the dial is inverted
    /// relative to the raw number.
    static func score(_ analysis: Analysis) -> Double? {
        guard let excess = analysis.headlineExcessYears else { return nil }
        return Swift.max(0, Swift.min(100, 75 - excess * 5))
    }

    static func confidence(_ analysis: Analysis, profile: UserHealthProfile,
                           now: Date) -> InsightConfidence {
        guard analysis.heart != nil else { return .low }
        let freshCuff = profile.input(.cuffSystolic)?.isFresh(asOf: now) ?? false
        if analysis.assumedCholesterol || !freshCuff { return .moderate }
        return .high
    }

    static func explanation(_ analysis: Analysis) -> String {
        var parts: [String] = []
        if let heart = analysis.heart, let heartAge = heart.heartAge,
           let excess = heart.excessYears {
            let engines = heart.readings.map(\.engine.rawValue).joined(separator: " and ")
            parts.append(String(format: "Your heart is behaving like someone aged %@ — %@. That's the age at which a person with optimal blood pressure, cholesterol and no smoking would carry your current 10-year risk, solved from the %@ %@.",
                                heartAgePhrase(heartAge, capped: heart.isCapped),
                                excessPhrase(excess), engines,
                                heart.readings.count > 1 ? "equations" : "equation"))
        }
        if let fitness = analysis.fitness {
            if let younger = fitness.yearsYounger, abs(younger) >= 1 {
                parts.append(String(format: "Your cardio fitness matches the average %@-year-old for your sex — %.0f years %@ than you are.",
                                    fitnessAgePhrase(fitness.fitnessAge, capped: fitness.isCapped),
                                    abs(younger), younger > 0 ? "younger" : "older"))
            } else {
                parts.append("Your cardio fitness is about average for your age.")
            }
        }
        if analysis.heart == nil {
            // Two different reasons, and blaming the wrong one sends people off to
            // enter data that won't change anything.
            parts.append(analysis.systolicUsed == nil
                ? "Add a blood-pressure reading to get the clinical half of this — your heart age."
                : "Heart age comes from risk equations validated for ages 40–79, so that half isn't shown at your age; the fitness half is the honest one for now.")
        }
        if !analysis.projections.isEmpty {
            parts.append("The projections below run the same validated equations at future ages with today's numbers unchanged; they show where this is heading, not what will happen.")
        }
        return parts.joined(separator: " ")
    }
}
