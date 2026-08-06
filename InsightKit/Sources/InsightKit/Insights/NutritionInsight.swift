import Foundation

/// What the reader eats, against what the published guidance actually says.
///
/// **Every term here rests on a named body's figure, and the row says which.**
/// That is the user's decision of 2026-08-03 — *"I am happy with all dietary
/// guidelines"* — and the rule it licenses is precise: a band from WHO, EFSA or
/// SACN with its provenance on the row is evidence, and a target this app
/// invented would not be. So there is no calorie score here and never will be:
/// no published figure says what one person should eat, and a deficit is the
/// point for a reader losing weight.
///
/// Four of the figures live on the metrics themselves as `referenceRange`s
/// (fibre, potassium, sodium, caffeine). The other four cannot: protein is per
/// kilogram of body mass, saturated fat and total fat are percentages of energy,
/// and water is sex-specific — they need the reader, so they live here. Same
/// division, same reason, as `HeartHealthScore` holding the age-and-sex VO₂max
/// tables while `MetricType.vo2Max` returns nil.
public enum NutritionModel {

    /// Two weeks. Long enough that one takeaway does not decide the number,
    /// short enough to still describe how the reader eats now.
    public static let windowDays = 14

    /// Days of the window that must carry a logged day's energy before any of
    /// this is offered. Below it the card says it cannot judge rather than
    /// scoring three days as though they were a fortnight — the same floor
    /// `ActivityDoseModel` uses, for the same reason.
    public static let minimumLoggedDays = 3

    /// Where logging stops being complete enough to describe a diet.
    /// `NutritionLogging` owns the figure; this is the alias the card reads.
    public static var completeEnough: Double { NutritionLogging.completeEnough }

    /// kcal per gram, for the two terms the guidance states as a share of
    /// energy. Atwater factors, which is what the guidance itself assumes.
    public static let kcalPerGramFat = 9.0

    public struct Output: Sendable, Equatable {
        public let score: Double
        /// Days in the window with a logged energy figure.
        public let loggedDays: Int
        /// `loggedDays / windowDays`.
        public let completeness: Double
        /// Mean over *logged* days, per metric. A day with no log is a day the
        /// reader did not write down, not a day they ate nothing, so it is
        /// absent rather than zero.
        public let means: [MetricType: Double]
        public let proteinPerKg: Double?
        public let saturatedFatPercent: Double?
        public let fatPercent: Double?
        public let contributions: [MetricContribution]
        public let drivers: [InsightDriver]
        /// The eight vitamins and minerals, each either logged or modelled from
        /// energy. Nil when neither sex nor age is known — which is what makes
        /// this card's mandatory ask for both of them true rather than
        /// aspirational (backlog Q4).
        public let micronutrients: MicronutrientEstimate.Output?

        public init(score: Double, loggedDays: Int, completeness: Double,
                    means: [MetricType: Double], proteinPerKg: Double?,
                    saturatedFatPercent: Double?, fatPercent: Double?,
                    contributions: [MetricContribution], drivers: [InsightDriver],
                    micronutrients: MicronutrientEstimate.Output? = nil) {
            self.score = score
            self.loggedDays = loggedDays
            self.completeness = completeness
            self.means = means
            self.proteinPerKg = proteinPerKg
            self.saturatedFatPercent = saturatedFatPercent
            self.fatPercent = fatPercent
            self.contributions = contributions
            self.drivers = drivers
            self.micronutrients = micronutrients
        }
    }

    // MARK: - The curves

    /// WHO/FAO/UNU 2007 puts safe intake at 0.83 g/kg. The 1.2–1.6 g/kg band is
    /// the range cited for preserving lean mass during rapid weight loss, which
    /// is the situation a reader on a GLP-1 is in — and the reason the user
    /// asked for a floor here rather than a target.
    ///
    /// Flat above 1.6: more protein is not better in any figure this app can
    /// cite, and a slope up there would be drawn from nothing.
    public static func proteinScore(gramsPerKilogram value: Double) -> Double {
        ScoreCurve.through([(0.4, 20), (0.83, 65), (1.2, 90), (1.6, 100)], at: value)
    }

    /// EFSA's adequate intake is 25 g; SACN's UK figure is 30 g. A floor, so the
    /// curve holds at 100 above it rather than penalising more.
    public static func fibreScore(grams value: Double) -> Double {
        ScoreCurve.through([(5, 20), (25, 80), (30, 100)], at: value)
    }

    /// WHO 2023: less than 10% of energy from saturated fat.
    public static func saturatedFatScore(percentOfEnergy value: Double) -> Double {
        ScoreCurve.through([(5, 100), (10, 75), (15, 40), (25, 20)], at: value)
    }

    /// WHO: total fat at or below 30% of energy. A softer curve than saturated
    /// fat's because the guidance itself is softer — the composition of the fat
    /// carries most of the claim, and that is the term above.
    public static func fatScore(percentOfEnergy value: Double) -> Double {
        ScoreCurve.through([(15, 100), (30, 80), (40, 45), (55, 20)], at: value)
    }

    /// WHO 2012: less than 2 g of sodium a day, about 5 g of salt.
    public static func sodiumScore(milligrams value: Double) -> Double {
        ScoreCurve.through([(1_000, 100), (2_000, 75), (3_500, 40), (6_000, 20)], at: value)
    }

    /// WHO 2012: at least 3.51 g of potassium a day. A floor, like fibre.
    public static func potassiumScore(milligrams value: Double) -> Double {
        ScoreCurve.through([(1_000, 20), (2_500, 60), (3_510, 95), (4_700, 100)], at: value)
    }

    /// EFSA 2010: 2.5 L of total water a day for men, 2.0 L for women, food
    /// included. Scored as a fraction of the reader's own figure, because the
    /// two differ by a quarter and drawing one line for both would be wrong for
    /// half the people who see it.
    ///
    /// **Total water includes what food carries — roughly a fifth of it — and a
    /// drinks log does not.** So the fraction is against 80% of the published
    /// figure, and the card says so; scoring a logged litre count straight
    /// against a total-water figure would mark a well-hydrated reader down for
    /// the water in their dinner.
    public static func waterScore(litres value: Double, sex: BiologicalSex?) -> Double {
        let published = sex == .female ? 2.0 : 2.5
        let fromDrinks = published * 0.8
        return ScoreCurve.through([(0.3, 20), (0.7, 60), (1.0, 95), (1.2, 100)],
                                  at: value / fromDrinks)
    }

    /// EFSA 2015: up to 400 mg a day is not a safety concern for a healthy
    /// adult. Nothing below that is scored down — the guidance sets no floor and
    /// this app is not going to invent one for coffee.
    public static func caffeineScore(milligrams value: Double) -> Double {
        ScoreCurve.through([(0, 100), (400, 80), (600, 50), (1_000, 20)], at: value)
    }

    // MARK: - Evaluation

    /// Nil when there are too few logged days to describe anything.
    public static func evaluate(samples: [HealthMetricSample],
                                profile: UserHealthProfile,
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        // One figure, one place — see `NutritionLogging`. The metabolism card
        // gates on the same number, and two cards computing "how well do you
        // log" separately would eventually disagree in front of the reader.
        let energyDays = NutritionLogging.loggedDays(samples, days: windowDays,
                                                     now: now, calendar: calendar)
        guard energyDays.count >= minimumLoggedDays else { return nil }
        let completeness = Double(energyDays.count) / Double(windowDays)

        func mean(_ metric: MetricType) -> Double? {
            let days = VitalReader.dailyValues(metric, from: samples, days: windowDays,
                                               now: now, calendar: calendar)
            guard !days.isEmpty else { return nil }
            return days.reduce(0, +) / Double(days.count)
        }

        var means: [MetricType: Double] = [:]
        for metric in NutritionInsight.allNutritionMetrics + MicronutrientTargets.targetable {
            if let value = mean(metric) { means[metric] = value }
        }
        let energy = energyDays.reduce(0, +) / Double(energyDays.count)
        means[.dietaryEnergy] = energy

        // The divisor for the per-kilogram figure. Read but **not declared as a
        // candidate metric**: it is not an input this card scores, it is the
        // scale protein is measured against, and declaring it would put weight
        // on a nutrition card's chart.
        let bodyMass = samples.latestValue(.bodyMass)
        let proteinPerKg = zip2(means[.dietaryProtein], bodyMass).map { $0 / $1 }
        let satFatPercent = means[.dietarySaturatedFat].map { $0 * kcalPerGramFat / energy * 100 }
        let fatPercent = means[.dietaryFat].map { $0 * kcalPerGramFat / energy * 100 }

        /// One scored term, before renormalisation. A named type rather than
        /// a tuple because three anonymous `Double`s in a `reduce` is exactly
        /// the shape a wrong one hides in.
        struct Term {
            let row: MetricContribution
            let score: Double
            let weight: Double
        }
        var terms: [Term] = []
        var drivers: [InsightDriver] = []

        // `value` is the daily mean in the metric's own unit — the measured
        // figure each curve was fed, directly (fibre, sodium) or through the
        // stated transformation (protein per kg, fat as a share of energy),
        // which the detail spells out. No baseline/z anywhere on this card:
        // every term is judged against a published figure, never the reader's
        // own history.
        func add(_ metric: MetricType, score: Double, weight: Double,
                 higherIsBetter: Bool?, detail: String, driver: String,
                 value: Double? = nil) {
            terms.append(Term(row: MetricContribution(metric: metric,
                                                      higherIsBetter: higherIsBetter,
                                                      weight: weight, detail: detail,
                                                      componentScore: score,
                                                      value: value),
                              score: score, weight: weight))
            drivers.append(.component(driver, score: score))
        }

        if let perKg = proteinPerKg, let grams = means[.dietaryProtein] {
            let score = proteinScore(gramsPerKilogram: perKg)
            add(.dietaryProtein, score: score, weight: 0.25, higherIsBetter: true,
                detail: String(format: "%.0f g a day — %.2f g per kg of your body weight", grams, perKg),
                driver: String(format: "Protein %.2f g/kg — the floor for holding on to lean mass while losing weight is about 1.2 g/kg (WHO/FAO safe intake is 0.83)", perKg),
                value: grams)
        }
        if let fibre = means[.dietaryFibre] {
            let score = fibreScore(grams: fibre)
            add(.dietaryFibre, score: score, weight: 0.20, higherIsBetter: true,
                detail: String(format: "%.0f g a day against a 25 g floor", fibre),
                driver: String(format: "Fibre %.0f g a day — EFSA's adequate intake is 25 g and the UK figure is 30 g", fibre),
                value: fibre)
        }
        if let percent = satFatPercent, let grams = means[.dietarySaturatedFat] {
            let score = saturatedFatScore(percentOfEnergy: percent)
            add(.dietarySaturatedFat, score: score, weight: 0.20, higherIsBetter: false,
                detail: String(format: "%.0f g a day — %.0f%% of what you ate", grams, percent),
                driver: String(format: "Saturated fat %.0f%% of energy — WHO's figure is below 10%%", percent),
                value: grams)
        }
        if let sodium = means[.dietarySodium] {
            let score = sodiumScore(milligrams: sodium)
            add(.dietarySodium, score: score, weight: 0.15, higherIsBetter: false,
                detail: String(format: "%.0f mg a day against a 2,000 mg ceiling", sodium),
                driver: String(format: "Sodium %.0f mg a day — WHO's figure is under 2,000 mg, about 5 g of salt", sodium),
                value: sodium)
        }
        if let potassium = means[.dietaryPotassium] {
            let score = potassiumScore(milligrams: potassium)
            add(.dietaryPotassium, score: score, weight: 0.05, higherIsBetter: true,
                detail: String(format: "%.0f mg a day against a 3,510 mg floor", potassium),
                driver: String(format: "Potassium %.0f mg a day — WHO's figure is at least 3,510 mg", potassium),
                value: potassium)
        }
        if let percent = fatPercent, let grams = means[.dietaryFat] {
            let score = fatScore(percentOfEnergy: percent)
            add(.dietaryFat, score: score, weight: 0.05, higherIsBetter: false,
                detail: String(format: "%.0f g a day — %.0f%% of what you ate", grams, percent),
                driver: String(format: "Total fat %.0f%% of energy — WHO's figure is at or below 30%%", percent),
                value: grams)
        }
        if let water = means[.dietaryWater] {
            let score = waterScore(litres: water, sex: profile.sex)
            add(.dietaryWater, score: score, weight: 0.05, higherIsBetter: true,
                detail: String(format: "%.1f L logged a day — EFSA's total-water figure is %@, and food carries about a fifth of it",
                               water, profile.sex == .female ? "2.0 L" : "2.5 L"),
                driver: String(format: "Water %.1f L a day from what you logged — EFSA's total figure is %@ including the water in food",
                               water, profile.sex == .female ? "2.0 L" : "2.5 L"),
                value: water)
        }
        if let caffeine = means[.dietaryCaffeine] {
            let score = caffeineScore(milligrams: caffeine)
            add(.dietaryCaffeine, score: score, weight: 0.05, higherIsBetter: false,
                detail: String(format: "%.0f mg a day against a 400 mg ceiling", caffeine),
                driver: String(format: "Caffeine %.0f mg a day — EFSA calls up to 400 mg no safety concern for a healthy adult", caffeine),
                value: caffeine)
        }

        // MARK: The eight vitamins and minerals
        //
        // Backlog Q4. `MicronutrientTargets` has held published, sex-and-age
        // resolved figures since it was written and nothing had ever called it,
        // while this card made both facts *mandatory* on the stated grounds
        // that the micronutrients could not be scored without them. Wiring it
        // up is what makes that sentence true.
        //
        // ⚠️ **Only a logged nutrient votes.** An estimated one is modelled from
        // calories and a population density — it is a fair answer to "what would
        // an ordinary diet this size carry", and no answer at all to "what did
        // *you* eat". Scoring it would let the reader's calorie count decide
        // their vitamin score, which is a number pretending to be a measurement.
        let micronutrients = MicronutrientEstimate.evaluate(
            means: means, energy: energy, sex: profile.sex,
            age: profile.age(asOf: now).map { Int($0) })

        var estimatedRows: [MetricContribution] = []
        if let micronutrients {
            for row in micronutrients.rows {
                let detail = MicronutrientEstimate.rowDetail(row)
                guard !row.isEstimated else {
                    // No `value` either: the intake here is modelled from
                    // calories and a population density, and the decomposition
                    // printing it as a raw value would launder an estimate
                    // into a measurement — the same reason it is not scored.
                    estimatedRows.append(MetricContribution(
                        metric: row.metric, higherIsBetter: nil, weight: 0,
                        detail: detail + " — not scored, because a modelled intake cannot be evidence about you"))
                    continue
                }
                add(row.metric, score: micronutrientScore(row.intake, target: row.target),
                    weight: 0.02,
                    higherIsBetter: row.standing == .aboveUpperLimit ? false : true,
                    detail: detail,
                    driver: "\(row.metric.displayName) \(detail). \(row.target.provenance)",
                    value: row.intake)
            }
        }

        guard !terms.isEmpty else { return nil }
        let totalWeight = terms.reduce(0.0) { $0 + $1.weight }
        let score = terms.reduce(0.0) { $0 + $1.score * $1.weight } / totalWeight
        // Renormalised over what was actually present, so a legend saying "25%
        // of this" is telling the truth on a reader who logs no water.
        var contributions = terms.map { term in
            MetricContribution(metric: term.row.metric,
                               higherIsBetter: term.row.higherIsBetter,
                               weight: term.weight / totalWeight, detail: term.row.detail,
                               // Carried over from the un-renormalised row —
                               // renormalising a weight does not change what
                               // the component itself scored or read.
                               componentScore: term.row.componentScore,
                               value: term.row.value)
        }
        contributions += trackedNotScored(means: means, energy: energy)
        contributions += estimatedRows

        // The caveat travels with the rows, always, and leads them when every
        // one of the eight is modelled — which is the state the reader is
        // actually in today, with no micronutrient rows in their log at all.
        if let micronutrients {
            let caveat = MicronutrientEstimate.caveat(
                estimatedCount: micronutrients.estimatedCount,
                of: micronutrients.rows.count)
            let short = micronutrients.flagged.filter { $0.standing == .below }
            if short.isEmpty {
                drivers.append(.routine("Vitamins and minerals: all \(micronutrients.rows.count) reach their published floor. \(caveat)"))
            } else {
                let names = short.map(\.metric.displayName).joined(separator: ", ")
                drivers.append(InsightDriver(
                    text: "Under the published figure: \(names). \(caveat)",
                    isNotable: micronutrients.loggedCount > 0))
            }
            for row in micronutrients.rows where row.standing == .aboveUpperLimit {
                drivers.append(.notable("\(row.metric.displayName) is over its tolerable upper intake — \(MicronutrientEstimate.rowDetail(row))"))
            }
        }

        return Output(score: score, loggedDays: energyDays.count, completeness: completeness,
                      means: means, proteinPerKg: proteinPerKg,
                      saturatedFatPercent: satFatPercent, fatPercent: fatPercent,
                      contributions: contributions, drivers: drivers,
                      micronutrients: micronutrients)
    }

    /// A logged micronutrient against its published figures.
    ///
    /// Two different quantities, and they are not the ends of one band: the
    /// recommended intake is a floor, the tolerable upper intake comes from a
    /// separate body of evidence about harm. So over the ceiling scores *down*,
    /// and there is no reward for being far above the floor — the evidence for
    /// "more is better" above an RDA does not exist for any of these eight.
    public static func micronutrientScore(_ intake: Double,
                                          target: MicronutrientTargets.Target) -> Double {
        if let ceiling = target.upperLimit, intake > ceiling {
            return ScoreCurve.through([(1.0, 60), (1.5, 35), (3.0, 20)], at: intake / ceiling)
        }
        return ScoreCurve.through([(0, 20), (0.5, 50), (1.0, 95), (1.3, 100)],
                                  at: intake / target.recommended)
    }

    /// The three rows this card draws and refuses to score, each for its own
    /// reason — and each reason is on the row, because a bare zero weight is
    /// what `testAnUnweightedRowAlwaysSaysWhy` exists to catch.
    static func trackedNotScored(means: [MetricType: Double], energy: Double) -> [MetricContribution] {
        // `value` filled, `componentScore` deliberately not: the readings are
        // real and "not scored" is each row's whole statement.
        var out: [MetricContribution] = [
            MetricContribution(
                metric: .dietaryEnergy, higherIsBetter: nil, weight: 0,
                detail: String(format: "%.0f kcal a day — tracked, not scored: no published figure says what one person should eat, and for a reader losing weight a deficit is the point", energy),
                value: energy)
        ]
        if let carbs = means[.dietaryCarbohydrates] {
            out.append(MetricContribution(
                metric: .dietaryCarbohydrates, higherIsBetter: nil, weight: 0,
                detail: String(format: "%.0f g a day — tracked, not scored: the guidance here is about which carbohydrates rather than how many grams, and this app is not going to invent a gram figure", carbs),
                value: carbs))
        }
        if let sugar = means[.dietarySugar] {
            // The honest one, and the reason it is not simply scored against
            // WHO's 10%: the guideline limits *free* sugars, and this metric is
            // total sugars — the sugar in fruit and milk is in it. Scoring one
            // against the other would mark down an apple.
            out.append(MetricContribution(
                metric: .dietarySugar, higherIsBetter: nil, weight: 0,
                detail: String(format: "%.0f g a day — tracked, not scored: WHO's under-10%% figure is for *free* sugars, and this number is total sugars, so it counts the sugar in fruit and milk too", sugar),
                value: sugar))
        }
        return out
    }

    /// `zip` for two optionals, which Swift has no shorthand for and which this
    /// file needs three times.
    static func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
        guard let a, let b else { return nil }
        return (a, b)
    }
}

/// The card.
public struct NutritionInsight: InsightModel {
    public let id: InsightID = .nutrition
    public let title = "Nutrition"
    public init() {}

    /// Everything the card reads. Body mass is deliberately absent: protein is
    /// scored per kilogram, so weight is the scale rather than an input, and
    /// declaring it would draw a body-weight line on a nutrition chart.
    static let allNutritionMetrics: [MetricType] = [
        .dietaryProtein, .dietaryCarbohydrates, .dietaryFat, .dietarySaturatedFat,
        .dietarySugar, .dietaryFibre, .dietarySodium, .dietaryPotassium,
        .dietaryWater, .dietaryCaffeine
    ]

    /// Declared inputs, which is also what the detail screen lists back to the
    /// reader. The eight micronutrients are genuinely inputs now (backlog Q4) —
    /// they were readable from HealthKit all along and read by nothing.
    public var candidateMetrics: [MetricType] {
        [.dietaryEnergy] + Self.allNutritionMetrics + MicronutrientTargets.targetable
    }

    /// Sex changes the water figure by a quarter, and nothing else here. Not
    /// mandatory: without it the card scores everything else and the water row
    /// uses the higher figure, which is stated on the row.
    /// **Mandatory as of 2026-08-05, at the reader's instruction**, and the
    /// reason is the eleven micronutrients rather than the water figure it used
    /// to cite.
    ///
    /// Every published micronutrient intake moves with sex and several move
    /// with age — iron is 18 mg for a menstruating reader against 8 for a man,
    /// more than twofold. Without both facts the card cannot score any of them,
    /// and scoring them against the wrong row is worse than not scoring them:
    /// it tells someone who is deficient that they are fine.
    ///
    /// `isMandatory` is what carries this to the reader — it is what makes the
    /// setup flow insist rather than offer, and what puts the ask on the front
    /// page when it is still missing.
    ///
    /// ⚠️ **This rationale was untrue from the day it shipped until 2026-08-06.**
    /// It demanded both facts *because* the eleven micronutrients could not be
    /// scored without them, and then scored none of them —
    /// `MicronutrientTargets` was dead code. `MicronutrientEstimate` closes it,
    /// and the ask is now paid for. **An ask whose stated reason does not
    /// happen is the worst kind of ask**: the reader hands over a fact about
    /// their body and gets nothing back, and has no way to know.
    public var requirements: [GroundingRequirement] {
        [.init(kind: .biologicalSex, isMandatory: true,
               rationale: "Every published vitamin and mineral figure differs by sex — iron alone is 18 mg a day against 8. Without it none of them can be scored."),
         .init(kind: .dateOfBirth, isMandatory: true,
               rationale: "Calcium, iron, magnesium and vitamin D all change with age, so the target has to know how old you are.")]
    }

    /// Which of the two profile facts are still missing.
    ///
    /// Each reports itself. The old rule was `profile.sex == nil ? requirements
    /// : []`, which hid the date-of-birth ask entirely for anyone who had
    /// already set a sex — so half the micronutrient targets stayed
    /// unresolvable with nothing on screen saying why.
    func unmet(for profile: UserHealthProfile, now: Date) -> [GroundingRequirement] {
        requirements.filter { requirement in
            switch requirement.kind {
            case .biologicalSex: return profile.sex == nil
            case .dateOfBirth: return profile.age(asOf: now) == nil
            default: return false
            }
        }
    }

    public func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile,
                         now: Date) -> InsightResult {
        guard let out = NutritionModel.evaluate(samples: samples, profile: profile, now: now) else {
            // `invitesInput` because the missing thing is a food log, which
            // the reader can supply — without it this card is filtered off the
            // tab and cannot ask.
            // **The profile ask travels with the empty state.** It used to be
            // reported only once a food log existed, so a reader with neither
            // was asked for the log and never for the two facts every vitamin
            // and mineral target needs — and then the first day they logged
            // anything, half the card could not be scored for a reason nobody
            // had mentioned. Ask for both at once.
            return InsightResult(
                id: id, title: title, primaryValue: nil,
                headline: "Log what you eat",
                score: nil, confidence: .low,
                explanation: "Log what you eat — through Apple Health, MyFitnessPal or any app that writes to it, or by sharing a Shotsy backup — and this card scores it against published guidance from WHO, EFSA and SACN. It needs \(NutritionModel.minimumLoggedDays) days of logging before it will say anything.",
                drivers: [],
                unmetRequirements: unmet(for: profile, now: now),
                invitesInput: true)
        }

        // Completeness first, because every number under it is a mean over the
        // days the reader chose to log, and that is the one caveat which
        // changes how the rest should be read.
        var drivers: [InsightDriver] = []
        let loggedLine = "Logged \(out.loggedDays) of the last \(NutritionModel.windowDays) days"
        if out.completeness < NutritionModel.completeEnough {
            drivers.append(.notable(loggedLine + " — everything below is an average of those days, so it describes the days you wrote down rather than how you eat"))
        } else {
            drivers.append(.routine(loggedLine))
        }
        drivers += out.drivers.filter { $0.isNotable == true }
        drivers += out.drivers.filter { $0.isNotable != true }

        return InsightResult(
            id: id, title: title,
            primaryValue: out.score,
            headline: headline(out.score),
            score: out.score,
            confidence: out.completeness >= NutritionModel.completeEnough ? .moderate : .low,
            explanation: "Your last \(NutritionModel.windowDays) days of food logging, scored against published guidance — WHO, EFSA and SACN — with each figure named on its own row. Calories are charted and never scored: no published number says what one person should eat.",
            driverLines: drivers,
            unmetRequirements: unmet(for: profile, now: now),
            contributors: out.contributions,
            weighting: .weightedAverage)
    }

    private func headline(_ score: Double) -> String {
        switch score {
        case 85...: return "In line with the guidance"
        case 70..<85: return "Mostly in line"
        case 50..<70: return "Some way off"
        default: return "Well off the published figures"
        }
    }
}
