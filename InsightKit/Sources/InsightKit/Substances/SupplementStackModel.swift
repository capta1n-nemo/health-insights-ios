import Foundation

/// **Summing a stack ingredient by ingredient, against the published upper
/// limits** — backlog Q8 / B3-25.
///
/// ## What this does that a bottle count does not
///
/// Two multivitamins, a zinc capsule and an "immune support" blend can each be
/// unremarkable and together carry more zinc than the published Tolerable Upper
/// Intake Level. Nothing tells the reader that, because nothing adds the labels
/// up: the arithmetic is per-nutrient, across products, in units the labels do
/// not use. That sum is the whole feature.
///
/// ## The three honesty rules, each enforced by a type rather than a convention
///
/// 1. **An unknown amount is never nought.** A proprietary blend declares a
///    total and withholds the split, which is legal and common. Every such
///    ingredient lands in `NutrientTotal.unresolved`, `isComplete` goes false,
///    and the card says "at least X" rather than "X". `IngredientAmount` has no
///    case that can quietly become a number.
/// 2. **An unconvertible unit is never guessed.** An IU figure for vitamin E
///    with no form declared is ambiguous by 49%; for vitamin A it is ambiguous
///    between two substances, only one of which counts. `NutrientAmount
///    .converted(to:)` refuses both, and the refusal travels here as an
///    unresolved contributor rather than as a silent omission.
/// 3. **A limit is never resolved against a profile the app does not have.**
///    `NutrientUpperLimits.limit(for:sex:age:)` returns `.outsideTable` with
///    what is missing, and the card renders that instead of a comparison.
///
/// ## ⚠️ The wording rule
///
/// **Exceeding an upper limit is information, not medical advice.** Everything
/// this type produces states a number and the published figure it is being
/// compared with. It contains no instruction, no "consider reducing", and no
/// threshold for action. That constraint is in `SupplementStackWordingTests`
/// rather than in a reviewer's memory, because it is the one thing about this
/// card that would be actively harmful to get wrong.
public enum SupplementStackModel {

    // MARK: - One nutrient's total

    /// **Everything the stack contributes of one nutrient, and everything it
    /// could not resolve.**
    public struct NutrientTotal: Sendable, Equatable, Identifiable {
        public let nutrient: Nutrient
        /// Daily total from the stack, in `nutrient.canonicalUnit`. A **floor**
        /// wherever `unresolved` is non-empty.
        public let fromSupplements: Double
        /// Daily total from logged food, where the limit is a limit on total
        /// intake *and* this app holds a series for it. Zero elsewhere, and
        /// `countsFood` says which case a zero is.
        public let fromFood: Double
        /// Whether food was added at all — so "0 mg from food" and "food is not
        /// counted toward this limit" can never render the same.
        public let countsFood: Bool
        /// Days in the food window that carried any logged intake of this
        /// nutrient. The denominator of the food half's honesty.
        public let foodDaysLogged: Int
        /// Ingredients that name this nutrient and carry no usable number, with
        /// the reason for each. **The reason this total may be a floor.**
        public let unresolved: [UnresolvedContribution]
        /// Which products contributed, for the row's detail line.
        public let contributingProducts: [String]
        public let limit: NutrientUpperLimits.LimitResolution
        public let recommended: NutrientUpperLimits.IntakeReference

        public var id: Nutrient { nutrient }

        /// Everything counted toward the limit: supplements always, food only
        /// where the limit is about food too.
        public var countedTotal: Double { fromSupplements + fromFood }

        /// Whether every ingredient naming this nutrient produced a number.
        public var isComplete: Bool { unresolved.isEmpty }

        /// Share of the published upper limit, or `nil` where there is no limit
        /// to take a share of.
        ///
        /// ⚠️ A share computed from an incomplete total is a **lower bound** on
        /// the real share, and every caller has to treat it as one — which is
        /// why `isComplete` sits beside it rather than being folded in.
        public var shareOfLimit: Double? {
            guard case .limit(let value) = limit, value > 0 else { return nil }
            return countedTotal / value
        }

        /// Share of the recommended intake, where one is published.
        public var shareOfRecommended: Double? {
            guard let reference = recommended.value, reference > 0 else { return nil }
            return countedTotal / reference
        }

        /// Whether the counted total is at or above the published limit.
        /// `false` where there is no limit — never `true` by default.
        public var isAtOrOverLimit: Bool { (shareOfLimit ?? 0) >= 1 }
    }

    /// One ingredient that names a nutrient and could not be turned into a
    /// number, with the reason in the reader's terms.
    public struct UnresolvedContribution: Sendable, Equatable, Hashable {
        public let productName: String
        public let labelText: String
        /// Why. Written to be printed, because an unexplained "unknown" is the
        /// thing this whole type exists to avoid.
        public let reason: String

        public init(productName: String, labelText: String, reason: String) {
            self.productName = productName
            self.labelText = labelText
            self.reason = reason
        }
    }

    // MARK: - The whole stack

    public struct Output: Sendable, Equatable {
        /// Every nutrient the stack names, heaviest share of its limit first,
        /// then the ones with no limit, alphabetically.
        public let totals: [NutrientTotal]
        /// Products taken into account.
        public let products: [SupplementProduct]
        /// Ingredients the reader captured that this app cannot weigh at all —
        /// a herb, an amino acid, a probiotic. Counted, never scored, and named
        /// so the stack the reader sees is the stack they entered.
        public let unrecognisedIngredientCount: Int
        /// Ingredients naming a nutrient with no usable amount, across the whole
        /// stack. **The headline honesty figure.**
        public let unresolvedCount: Int
        /// `nil` when the profile could not resolve any limit — the card then
        /// reports the stack and says what it is missing rather than scoring.
        public let score: Double?
        /// The life stage every limit was read from, for the caveat.
        public let lifeStage: NutrientUpperLimits.LifeStage?

        /// Nutrients at or over their published limit, worst first.
        public var atOrOverLimit: [NutrientTotal] { totals.filter(\.isAtOrOverLimit) }

        /// The nutrient carrying the largest share of its limit, where any has
        /// a limit at all.
        public var highest: NutrientTotal? {
            totals.filter { $0.shareOfLimit != nil }
                .max { ($0.shareOfLimit ?? 0) < ($1.shareOfLimit ?? 0) }
        }

        /// The largest share of any published limit. The card's number.
        public var highestShare: Double? { highest?.shareOfLimit }
    }

    /// How far back logged food intake is read, for the total-intake limits.
    ///
    /// Fourteen days rather than one: a food log is sparse, and a single day
    /// would make the food half swing between a full day's intake and nought
    /// depending on whether the reader happened to log lunch. The mean is taken
    /// over the days that carried *anything*, and `foodDaysLogged` reports how
    /// many those were, because a mean over two days is not a habit.
    public static let foodWindowDays = 14

    /// Fewest logged days before the food half is added at all.
    ///
    /// ⚠️ Below this the food total is **not** counted and the card says the
    /// limit is being compared against supplements alone. Adding a two-day
    /// average as though it were a daily intake would be inventing a diet.
    public static let minimumFoodDays = 3

    // MARK: - Summation

    /// Sum the stack, ingredient by ingredient.
    ///
    /// - Parameters:
    ///   - entries: The reader's stack. Entries not active on `now` are ignored.
    ///   - samples: Canonical samples, for the food half of the total-intake
    ///     limits. Pass `[]` and the food half is simply absent.
    ///   - profile: Age and sex. Without them no limit resolves and the card
    ///     says which fact it needs.
    public static func evaluate(entries: [SupplementEntry],
                                samples: [HealthMetricSample] = [],
                                profile: UserHealthProfile,
                                now: Date = Date(),
                                calendar: Calendar = .current) -> Output? {
        let active = entries.filter { $0.isActive(on: now) }
        guard !active.isEmpty else { return nil }

        let age = profile.age(asOf: now)
        let sex = profile.sex
        let stage = age.flatMap(NutrientUpperLimits.LifeStage.containing(age:))

        // Accumulators, per nutrient.
        var supplementTotals: [Nutrient: Double] = [:]
        var unresolved: [Nutrient: [UnresolvedContribution]] = [:]
        var products: [Nutrient: [String]] = [:]
        var unrecognised = 0

        for entry in active {
            let servings = max(0, entry.servingsPerDay)
            for ingredient in entry.product.ingredients {
                guard let nutrient = ingredient.nutrient else {
                    unrecognised += 1
                    continue
                }
                products[nutrient, default: []].append(entry.product.name)

                switch ingredient.amount {
                case .stated(let amount):
                    switch amount.converted(to: nutrient) {
                    case .success(let value):
                        supplementTotals[nutrient, default: 0] += value * servings
                    case .failure(let failure):
                        unresolved[nutrient, default: []].append(
                            UnresolvedContribution(
                                productName: entry.product.name,
                                labelText: ingredient.labelText,
                                reason: reason(for: failure)))
                    }
                case .withinProprietaryBlend(let blendName, let blendTotal):
                    unresolved[nutrient, default: []].append(
                        UnresolvedContribution(
                            productName: entry.product.name,
                            labelText: ingredient.labelText,
                            reason: blendReason(blendName: blendName,
                                                blendTotal: blendTotal)))
                case .notStated:
                    unresolved[nutrient, default: []].append(
                        UnresolvedContribution(
                            productName: entry.product.name,
                            labelText: ingredient.labelText,
                            reason: "The label lists it with no amount, so this "
                                + "total does not include it."))
                }
            }
        }

        let named = Set(supplementTotals.keys).union(unresolved.keys)
        var totals: [NutrientTotal] = []

        for nutrient in named.sorted(by: { $0.rawValue < $1.rawValue }) {
            let food = nutrient.countsFoodTowardTheLimit
                ? dailyFood(nutrient, samples: samples, now: now, calendar: calendar)
                : (mean: 0.0, days: 0)
            let counted = food.days >= minimumFoodDays
            totals.append(NutrientTotal(
                nutrient: nutrient,
                fromSupplements: supplementTotals[nutrient] ?? 0,
                fromFood: counted ? food.mean : 0,
                countsFood: counted,
                foodDaysLogged: food.days,
                unresolved: unresolved[nutrient] ?? [],
                contributingProducts: Array(Set(products[nutrient] ?? [])).sorted(),
                limit: NutrientUpperLimits.limit(for: nutrient, sex: sex, age: age),
                recommended: NutrientUpperLimits.recommendedIntake(
                    for: nutrient, sex: sex, age: age)))
        }

        // Heaviest share of a limit first; nutrients with no limit after them,
        // by name. A reader opening this wants the one nearest its ceiling.
        totals.sort { a, b in
            switch (a.shareOfLimit, b.shareOfLimit) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.displayNameForSort < b.displayNameForSort
            }
        }

        return Output(
            totals: totals,
            products: active.map(\.product),
            unrecognisedIngredientCount: unrecognised,
            unresolvedCount: totals.reduce(0) { $0 + $1.unresolved.count },
            score: score(totals: totals),
            lifeStage: stage)
    }

    /// Mean daily intake of a nutrient from logged food, over the window, and
    /// how many days carried anything.
    static func dailyFood(_ nutrient: Nutrient, samples: [HealthMetricSample],
                          now: Date, calendar: Calendar) -> (mean: Double, days: Int) {
        guard let metric = nutrient.dietaryMetric else { return (0, 0) }
        guard let start = calendar.date(byAdding: .day, value: -foodWindowDays, to: now)
        else { return (0, 0) }

        var byDay: [Date: Double] = [:]
        for sample in samples.samples(of: metric)
        where sample.start >= start && sample.start <= now {
            byDay[calendar.startOfDay(for: sample.start), default: 0] += sample.value
        }
        guard !byDay.isEmpty else { return (0, 0) }

        // Unit reconciliation: the app's dietary series are in mg for calcium,
        // iron and zinc and mcg for the vitamins, which is the same canonical
        // unit each nutrient uses. Asserted rather than assumed —
        // `SupplementStackTests.testFoodSeriesAreInTheCanonicalUnit` pins it,
        // because a factor of a thousand here would be invisible on the card.
        let mean = byDay.values.reduce(0, +) / Double(byDay.count)
        return (mean, byDay.count)
    }

    // MARK: - Scoring

    /// 0–100 for the stack, from the **largest** share of any published limit.
    ///
    /// `nil` where nothing has a resolvable limit — no profile, or a stack of
    /// nutrients the tables set no limit for. A card scoring a stack it could
    /// not weigh would be inventing the comparison.
    ///
    /// ## Why the worst nutrient sets it
    ///
    /// Averaging shares would let nine unremarkable nutrients bury one at three
    /// times its ceiling, which is the only finding this card exists to
    /// surface. The rest add to the deduction rather than diluting it — the
    /// `.worstOffender` basis, same as the substance card.
    ///
    /// ## Why it is a curve and not a table
    ///
    /// A share of a limit wanders: a reader who takes a half serving some days
    /// crosses 1.0 and back. `ScoreCurve.through` is anchored on the shares the
    /// published figures make meaningful — the limit itself, and multiples of
    /// it — with no step at any of them, so a stack does not lurch twenty points
    /// for a rounding.
    ///
    /// The anchors, and the judgement in each:
    ///
    /// - **0 → 100.** Nothing near any ceiling.
    /// - **0.5 → 92.** Half the published limit is unremarkable.
    /// - **1.0 → 62.** *At* the limit is deliberately below `ScoreBand.goodFloor`
    ///   and inside `fair`: the upper limit is the highest daily intake likely
    ///   to pose no risk, so sitting exactly on it leaves no headroom, and a card
    ///   drawing that green would be congratulating somebody at the ceiling. The
    ///   same call `SoundExposureModel` makes about the WHO allowance.
    /// - **1.5 → 40**, **2 → 25**, **3 → 12**, **5 → 0.** Above the limit the
    ///   published tables say nothing further — there is no second threshold to
    ///   anchor on — so the curve simply keeps falling and flattens at the end
    ///   rather than pretending to grade a region nobody has graded.
    public static func score(totals: [NutrientTotal]) -> Double? {
        let shares = totals.compactMap(\.shareOfLimit)
        guard !shares.isEmpty else { return nil }
        let worst = shares.max() ?? 0
        let base = curve(share: worst)

        // The rest add to the deduction, at a fifth of their own — enough that
        // three nutrients each at 90% of their limit does not read the same as
        // one, and small enough that the worst one still sets the number.
        let others = shares.filter { $0 != worst }
        let extra = others.reduce(0.0) { $0 + (100 - curve(share: $1)) * 0.2 }
        return Swift.max(0, Swift.min(100, base - extra))
    }

    /// One share of one limit → 0–100. Separated so both halves of `score` and
    /// the tests read the same curve.
    public static func curve(share: Double) -> Double {
        guard share.isFinite, share > 0 else { return 100 }
        return ScoreCurve.through([
            (0, 100),
            (0.5, 92),
            (1.0, 62),
            (1.5, 40),
            (2.0, 25),
            (3.0, 12),
            (5.0, 0),
        ], at: share)
    }

    /// The word for a score, shared so a headline and a chart cannot disagree.
    ///
    /// ⚠️ **Every one of these is a description, not an instruction.** "Over a
    /// published limit" states where the number sits; it does not say to stop,
    /// and nothing in this app does.
    public static func band(_ score: Double) -> String {
        switch ScoreBand(score: score) {
        case .good: return "Comfortably under the published limits"
        case .fair: return "At or near a published limit"
        case .poor: return "Over a published limit"
        }
    }

    // MARK: - Reasons

    static func reason(for failure: NutrientAmount.ConversionFailure) -> String {
        switch failure {
        case .formNotStated(let nutrient, let factors):
            return "The label gives \(nutrient.displayName) in IU without saying "
                + "which form, and \(factors). Rather than pick one, this is left "
                + "out of the total."
        case .noDefinedConversion(let nutrient):
            return "There is no defined conversion from the unit on the label to "
                + "the unit \(nutrient.displayName) limits are published in, so "
                + "this is left out of the total."
        }
    }

    static func blendReason(blendName: String, blendTotal: NutrientAmount?) -> String {
        let head = "It is inside the \(blendName) proprietary blend, which "
        guard let blendTotal else {
            return head + "declares no per-ingredient amounts. The total below is "
                + "therefore a floor, not a figure."
        }
        return head + "declares "
            + "\(SupplementFormatting.amount(blendTotal.value, unit: blendTotal.unit)) "
            + "across all of its ingredients and no split between them. The total "
            + "below is therefore a floor, not a figure."
    }
}

extension SupplementStackModel.NutrientTotal {
    /// Sort key for the no-limit tail, kept off the public surface.
    var displayNameForSort: String { nutrient.displayName }
}
