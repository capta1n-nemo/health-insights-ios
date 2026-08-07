import Foundation

/// The heart-age and fitness-age analysis, shared by two cards.
///
/// **No longer a card of its own.** Heart & Fitness Age computed two numbers
/// that belong in different places: the heart age inverts the same SCORE2/ASCVD
/// equations `CardiovascularRiskInsight` already runs, and the fitness age is
/// `FitnessInsight`'s subject. Keeping it as a third card meant a screen whose
/// two halves had different owners, different inputs and different failure
/// modes.
///
/// They degrade independently and that is still the point: fitness age needs
/// only a VO₂max reading (which an Apple Watch supplies unprompted), while heart
/// age needs the grounding facts the risk equations require.
///
/// *What was lost*: the three-age row that put your real age, heart age and
/// fitness age side by side. It cannot survive the split, and the sentence it
/// carried — that a fit heart can still run high blood pressure — now sits on
/// the risk card.
public struct HeartAgeAnalyser {

    public init() {}

    // Same population-average fallbacks the risk insight uses, so the two cards
    // can never quietly disagree about what was assumed.
    static let defaultTotalCholesterol = 5.2
    static let defaultHDLCholesterol = 1.3

    /// `.vascularAge` is the provider's own estimate, reported beside ours
    /// rather than merged into it — see `docs/architecture.md`.
    public var candidateMetrics: [MetricType] {
        [.bloodPressureSystolic, .vo2Max, .vascularAge]
    }

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
        /// The VO₂max and provider vascular age the analysis actually read.
        ///
        /// Carried here for the reason `systolicUsed` already was: `contributors`
        /// used to re-read the samples with its own `latestValue` calls, which
        /// could plot a different number than the card computed from. One read,
        /// one answer.
        public let vo2Used: Double?
        public let vascularAgeUsed: Double?
        public let vascularAgeSource: String?
        /// The risk-factor set the heart age was solved from, everything except
        /// the age itself.
        ///
        /// Carried out of here so `AgeComparison` can re-solve the same equations
        /// **once per blood-pressure instrument** without rebuilding the subject
        /// from a profile it does not see. Before this it could not, so the one
        /// section in the app whose subject is that instruments disagree printed
        /// a single heart age off whichever systolic source `VitalReader` had
        /// picked — see `AgeComparison.heartEstimates`.
        ///
        /// Nil for every early return here: without a sex, an age or a blood
        /// pressure there is no subject to carry.
        public let subject: HeartAgeModel.Subject?

        public init(chronologicalAge: Double?, heart: HeartAgeModel.Output?,
                    fitness: FitnessAgeModel.Output?,
                    projections: [HeartAgeModel.Projection], assumedCholesterol: Bool,
                    systolicUsed: Double? = nil, vo2Used: Double? = nil,
                    vascularAgeUsed: Double? = nil, vascularAgeSource: String? = nil,
                    subject: HeartAgeModel.Subject? = nil) {
            self.chronologicalAge = chronologicalAge
            self.heart = heart
            self.fitness = fitness
            self.projections = projections
            self.assumedCholesterol = assumedCholesterol
            self.systolicUsed = systolicUsed
            self.vo2Used = vo2Used
            self.vascularAgeUsed = vascularAgeUsed
            self.vascularAgeSource = vascularAgeSource
            self.subject = subject
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

        // Read through `VitalReader`, with per-metric freshness windows: 45 days
        // for VO₂max (Apple publishes one per outdoor walk or run), 14 for a cuff
        // reading (matching `GroundingKind.cuffSystolic.freshness`), 60 for a
        // provider's vascular age. `latestValue` gave the newest raw sample and
        // asked nothing about its age or whether the same reading had arrived
        // twice.
        // `.none` for all three: every one is a level fed into an age equation
        // built on population norms, so the reader's own recent days are not a
        // bar to clear and holding them out would only shorten the history.
        let vo2Reading = VitalReader.reading(.vo2Max, from: samples, now: now,
                                             freshWithin: 45 * 86_400, gap: .none)
        let fitness = vo2Reading.map {
            FitnessAgeModel.evaluate(vo2: $0.value, sex: sex, chronologicalAge: age)
        }
        let vascularReading = VitalReader.reading(.vascularAge, from: samples, now: now,
                                                  freshWithin: 60 * 86_400, gap: .none)

        // Heart age needs a blood pressure and a real age; everything else falls
        // back to the same averages the risk card assumes.
        let systolicReading = VitalReader.reading(.bloodPressureSystolic, from: samples,
                                                   now: now, freshWithin: 14 * 86_400,
                                                   gap: .none)
        let systolic = profile.cuffSystolic ?? systolicReading?.value
        guard let age, let systolic else {
            return Analysis(chronologicalAge: age, heart: nil, fitness: fitness,
                            projections: [], assumedCholesterol: false,
                            systolicUsed: systolic, vo2Used: vo2Reading?.value,
                            vascularAgeUsed: vascularReading?.value,
                            vascularAgeSource: vascularReading?.sourceName)
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
            systolicUsed: systolic, vo2Used: vo2Reading?.value,
            vascularAgeUsed: vascularReading?.value,
            vascularAgeSource: vascularReading?.sourceName,
            subject: subject)
    }

    /// The sensed metrics behind the two ages, so the detail chart plots what
    /// the calculation read. Weight 0 throughout: these ages come from published
    /// equations over grounding facts, not a weighted blend of these series, and
    /// claiming a share of them would be inventing one.
    ///
    /// Reads the analysis, never the samples. It used to re-read them with its
    /// own `latestValue` calls, which could plot a different number than the card
    /// computed from — the chart and the headline disagreeing about the same
    /// measurement, silently.
    static func contributors(_ analysis: HeartAgeAnalyser.Analysis) -> [MetricContribution] {
        // `value` mirrors the figure each detail prints, so the decomposition
        // and the row cannot quote different numbers. No componentScore on any
        // of them: these feed equations and age solves, which own no 0–100.
        var out: [MetricContribution] = []
        if let systolic = analysis.systolicUsed {
            out.append(.init(metric: .bloodPressureSystolic, higherIsBetter: false, weight: 0,
                             detail: "\(Int(systolic.rounded())) mmHg",
                             value: systolic))
        }
        if let fitness = analysis.fitness {
            out.append(.init(metric: .vo2Max, higherIsBetter: true, weight: 0,
                             detail: String(format: "%.0f", fitness.vo2),
                             value: fitness.vo2))
        }
        if let vascular = analysis.vascularAgeUsed {
            out.append(.init(metric: .vascularAge, higherIsBetter: false, weight: 0,
                             detail: String(format: "%.0f years", vascular),
                             value: vascular))
        }
        return out
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

    /// The dial figure, from how far the age runs ahead of your real one.
    /// Lower age = better, so the dial is inverted relative to the raw number.
    ///
    /// Was `75 - excess * 5`, which hits exactly zero at a fifteen-year excess
    /// and stays there. Two problems with that: fifteen years ahead is bad but
    /// it is not "nothing measurable is working", and a *capped* fitness age
    /// makes it trivial to reach — the model bounds its answer at 75, so a
    /// 35-year-old with a low VO₂max can produce a forty-year excess on the
    /// strength of the bound alone and floor the dial.
    ///
    /// A logistic instead: 0 excess still reads 75, but both ends are asymptotic,
    /// so neither a perfect nor a hopeless score is reachable. That matches how
    /// the rest of the app is scored — a 100 has to be earned, and a 0 should
    /// have to be too.
    static func score(_ analysis: Analysis) -> Double? {
        guard let excess = analysis.headlineExcessYears else { return nil }
        // Centre and steepness chosen so f(0) = 75; f(10) ≈ 50, f(30) ≈ 10.
        let steepness = 9.0
        let centre = 9.89
        return Swift.max(1, Swift.min(99, 100 / (1 + exp((excess - centre) / steepness))))
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
