import Foundation

/// **"What is actually in your stack"** — backlog B3-25, answering Q8.
///
/// The reader asked whether supplements were *"worth the one-time capture?"* and
/// answered their own question with *"Yes? From where?"*. From them, off the
/// label — and then, which is the part nobody ships, **summed ingredient by
/// ingredient across every bottle and weighed against the published upper
/// limits**. See `SupplementStackModel` for the arithmetic and the three
/// honesty rules it holds.
///
/// ## Bound rather than sampled
///
/// `readsOnlySamples` is false. A supplement stack lives in SwiftData and is
/// rebound on every recompute by `InsightEngine.withSupplements(_:)` — the same
/// contract as the substance log and the calendar, and for the same reason: it
/// is not a `HealthMetricSample` and never will be.
///
/// It *does* read samples, for one thing only. Where a limit is a limit on
/// **total** intake and this app holds a dietary series for the same substance,
/// logged food is added to the stack total, because that is what the limit is
/// about. Where the limit is written against supplemental forms alone —
/// magnesium, niacin, folic acid, vitamin E, preformed vitamin A — food is
/// charted and deliberately not added. `Nutrient.limitBasis` is the one place
/// that call is made.
///
/// ## ⚠️ It states numbers and never gives an instruction
///
/// Exceeding a Tolerable Upper Intake Level is information. This card reports
/// the total, names the published figure, and stops. It does not say to reduce
/// anything, does not rank a stack as good or bad behaviour, and carries no
/// threshold for action — `SupplementStackWordingTests` holds that against every
/// string this file can produce, because it is the one property of this card
/// that would be harmful to lose in a later edit.
public struct SupplementStackInsight: InsightModel {
    public let id: InsightID = .supplementStack
    public let title = "What is actually in your stack"

    /// The reader's stack, bound at construction. Empty until the app rebinds.
    public let entries: [SupplementEntry]

    public init(entries: [SupplementEntry] = []) {
        self.entries = entries
    }

    /// Its input is a stack, not a series — so a samples-only fixture leaves it
    /// empty through no fault of its own, and the guards derive that from here
    /// rather than from a hard-coded list.
    public var readsOnlySamples: Bool { false }

    /// The dietary micronutrient series, which are the food half of the
    /// total-intake limits.
    ///
    /// ⚠️ **Two of these are declared and deliberately never added**, and both
    /// are read and reported rather than dropped — a declared metric with data
    /// that reaches no contributor charts nowhere. Magnesium's limit is on
    /// supplemental forms only; vitamin A's series is in RAE and includes
    /// carotenoids while its limit is on preformed vitamin A alone. Each gets a
    /// weight-0 row saying so.
    public var candidateMetrics: [MetricType] {
        [.dietaryCalcium, .dietaryIron, .dietaryZinc, .dietaryVitaminC,
         .dietaryVitaminD, .dietaryVitaminA, .dietaryMagnesium]
    }

    /// **Both mandatory, and this is the card that most needs saying why.**
    ///
    /// The upper limits are published per age band, and the recommended intakes
    /// they are shown beside are sex-specific — iron is 18 mg for a woman of 30
    /// and 8 mg for a man of the same age. Without both, every comparison on
    /// this card would be against a figure the app picked for the reader.
    public var requirements: [GroundingRequirement] {
        [GroundingRequirement(
            kind: .dateOfBirth, isMandatory: true,
            rationale: "Upper intake limits are published per age band, and two "
                + "of them change at 51 and 71."),
         GroundingRequirement(
            kind: .biologicalSex, isMandatory: true,
            rationale: "Recommended intakes are sex-specific — iron is more than "
                + "twice as high for women under 51 — so a total shown without "
                + "it would be beside the wrong figure.")]
    }

    /// A dated list of what the reader is taking is not a profile fact, so this
    /// overrides the derived default. One route, several inputs, on the pattern
    /// `.medication` set: a bottle, its ingredients and how many servings are
    /// one conversation.
    public var contributions: [ContributionRoute] {
        [.supplementStack, .groundingFacts(requirements.map(\.kind))]
    }

    public func evaluate(samples: [HealthMetricSample],
                         profile: UserHealthProfile, now: Date) -> InsightResult {
        let unmet = unmetRequirements(profile: profile, now: now)

        guard let out = SupplementStackModel.evaluate(
            entries: entries, samples: samples, profile: profile, now: now) else {
            return invitingInput(
                id, title,
                action: "Add what you take",
                message: "Nothing on this phone knows what is in a supplement "
                    + "bottle — no wearable senses it and Apple Health has no "
                    + "record of it, so this is the one thing the app can only "
                    + "get from you. Add a bottle by typing its Supplement Facts "
                    + "panel or scanning it, and everything you take is then "
                    + "added up ingredient by ingredient and shown against the "
                    + "published upper intake limits for your age. It works with "
                    + "no network at all.")
        }

        var drivers: [InsightDriver] = []

        // The lead line. Which line leads depends on what the stack actually
        // shows — a nutrient over its limit outranks everything, and an
        // unresolvable profile outranks the arithmetic because without it there
        // is nothing to compare against.
        if out.score == nil {
            drivers.append(.notable(profileGapLine(out: out, unmet: unmet)))
        } else if let highest = out.highest, let share = highest.shareOfLimit {
            drivers.append(InsightDriver(text: headlineLine(highest, share: share),
                                         isNotable: share >= 1))
        }

        for total in out.atOrOverLimit.dropFirst() {
            drivers.append(.notable(headlineLine(total, share: total.shareOfLimit ?? 0)))
        }

        // ⚠️ The unknowns line, and it is notable whenever there are any: a
        // total with an unresolved contributor is a floor, and a reader who
        // does not know that has been handed a precise-looking wrong number.
        if out.unresolvedCount > 0 {
            drivers.append(.notable(unresolvedLine(out)))
        }

        // The nutrients with no published limit, said once rather than per row.
        let unlimited = out.totals.filter {
            if case .noLimitPublished = $0.limit { return true }
            return false
        }
        if !unlimited.isEmpty {
            drivers.append(.routine(
                "\(list(unlimited.map(\.nutrient.displayName))) "
                + "\(unlimited.count == 1 ? "is" : "are") in your stack and "
                + "\(unlimited.count == 1 ? "has" : "have") no published upper "
                + "limit. \(NutrientUpperLimits.noLimitCaution)"))
        }

        if out.unrecognisedIngredientCount > 0 {
            drivers.append(.routine(
                "\(out.unrecognisedIngredientCount) other "
                + "\(SectionCaveat.plural(out.unrecognisedIngredientCount, "ingredient")) "
                + "in your stack — herbs, amino acids, probiotics — are kept as "
                + "you entered them and are not weighed here. There are no "
                + "published upper intake levels for them to be weighed against."))
        }

        drivers.append(.routine(scopeCaveat(out)))

        let contributions = foodContributions(samples: samples, totals: out.totals, now: now)

        guard let score = out.score, let highest = out.highest,
              let share = highest.shareOfLimit else {
            // A stack the app holds and cannot weigh. It still shows everything
            // it has — the products, the totals, the unknowns — and says what is
            // missing, rather than disappearing or scoring on a guess.
            return InsightResult(
                id: id, title: title,
                primaryValue: nil,
                headline: unmet.isEmpty ? "Nothing to compare against" : "Add your details",
                subheadline: "\(out.products.count) "
                    + "\(SectionCaveat.plural(out.products.count, "product")), "
                    + "\(out.totals.count) "
                    + "\(SectionCaveat.plural(out.totals.count, "nutrient"))",
                score: nil, confidence: .low,
                explanation: explanation(out),
                driverLines: drivers,
                unmetRequirements: unmet,
                contributors: contributions,
                invitesInput: !unmet.isEmpty)
        }

        return InsightResult(
            id: id, title: title,
            primaryValue: share * 100,
            headline: SupplementStackModel.band(score),
            subheadline: "\(highest.nutrient.displayName) is at "
                + "\(SupplementFormatting.percent(share)) of its published limit",
            score: score,
            // Never high. The stack is what the reader typed, the limits are
            // population reference values, and where anything is unresolved the
            // total is a floor.
            confidence: out.unresolvedCount == 0 ? .moderate : .low,
            explanation: explanation(out),
            driverLines: drivers.filter { $0.isNotable == true }
                + drivers.filter { $0.isNotable != true },
            unmetRequirements: unmet,
            contributors: contributions,
            weighting: .worstOffender,
            otherFactors: Self.factors(out),
            derivedOutputs: Self.derivedOutputs(out))
    }

    // MARK: - Lines

    private func headlineLine(_ total: SupplementStackModel.NutrientTotal,
                              share: Double) -> String {
        guard case .limit(let limit) = total.limit else { return "" }
        let unit = total.nutrient.canonicalUnit
        var text = "\(total.nutrient.displayName): "
            + "\(total.isComplete ? "" : "at least ")"
            + "\(SupplementFormatting.amount(total.countedTotal, unit: unit)) a day"
        if total.contributingProducts.count > 1 {
            text += " across \(total.contributingProducts.count) products"
        }
        text += ", against a published upper limit of "
            + "\(SupplementFormatting.amount(limit, unit: unit)) — "
            + "\(SupplementFormatting.percent(share)) of it."
        if case .supplementalOnly(let why) = total.nutrient.limitBasis {
            text += " \(why)"
        } else if total.countsFood {
            text += " That includes "
                + "\(SupplementFormatting.amount(total.fromFood, unit: unit)) a day "
                + "from food you logged, averaged over the "
                + "\(total.foodDaysLogged) "
                + "\(SectionCaveat.plural(total.foodDaysLogged, "day")) that "
                + "carried anything, because this limit is a limit on intake "
                + "from every source."
        } else if total.nutrient.countsFoodTowardTheLimit {
            text += " This limit covers food as well as supplements, and you "
                + "have logged too little food for the app to add a figure for "
                + "it — so this is your supplements alone."
        }
        if let reference = total.recommended.value, let label = total.recommended.label {
            text += " The \(label) for your age and sex is "
                + "\(SupplementFormatting.amount(reference, unit: unit))."
        }
        return text
    }

    private func unresolvedLine(_ out: SupplementStackModel.Output) -> String {
        let affected = out.totals.filter { !$0.isComplete }
        return "\(out.unresolvedCount) "
            + "\(SectionCaveat.plural(out.unresolvedCount, "ingredient")) in your "
            + "stack name a nutrient with no usable amount — a proprietary blend, "
            + "or a unit that cannot be converted without knowing the form. So "
            + "\(list(affected.map(\.nutrient.displayName))) "
            + "\(affected.count == 1 ? "is" : "are") shown as \"at least\" the "
            + "figure above rather than as the figure. An unknown amount is not "
            + "nought here, and it is never treated as one."
    }

    private func profileGapLine(out: SupplementStackModel.Output,
                                unmet: [GroundingRequirement]) -> String {
        guard !unmet.isEmpty else {
            return "Your stack names \(out.totals.count) "
                + "\(SectionCaveat.plural(out.totals.count, "nutrient")), and no "
                + "upper intake limit has been published for any of them. "
                + NutrientUpperLimits.noLimitCaution
        }
        return "Your stack is recorded and adds up, but the published limits are "
            + "written per age band and the intakes beside them are sex-specific. "
            + "Until \(list(unmet.map { $0.kind.displayName.lowercased() })) "
            + "\(unmet.count == 1 ? "is" : "are") set, the app will not pick a "
            + "band for you — the totals below are yours, the comparison is not "
            + "made."
    }

    private func scopeCaveat(_ out: SupplementStackModel.Output) -> String {
        var text = "These are the labels as you entered them, added up per "
            + "ingredient and shown against the Dietary Reference Intakes "
            + "published by the US National Academies"
        if let stage = out.lifeStage {
            text += " for ages \(stage.displayName)"
        }
        text += ". They are population reference values for a person who is not "
            + "pregnant or breastfeeding, and this app knows about neither. "
            + "Nothing here is medical advice: it reports what your stack "
            + "contains and what the published figure is, and that is all it "
            + "does."
        let caveats = Set(out.products.compactMap { $0.source.caveat })
        if !caveats.isEmpty {
            text += " " + caveats.sorted().joined(separator: " ")
        }
        return text
    }

    private func explanation(_ out: SupplementStackModel.Output) -> String {
        "Every bottle in your stack, added up ingredient by ingredient and "
            + "weighed against the published upper intake limits for your age. "
            + "A single label rarely says anything; the sum across "
            + "\(out.products.count) of them can. Where an amount is not "
            + "declared — a proprietary blend, or IU with no form named — it is "
            + "carried through as unknown rather than as nought, so a total that "
            + "cannot be complete is shown as a floor."
    }

    private func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            return items.dropLast().joined(separator: ", ") + " and \(items.last ?? "")"
        }
    }

    // MARK: - The food half, as contributors

    /// One row per dietary series with data, weight 0 throughout.
    ///
    /// ⚠️ **Zero, and the reason is on every row.** These series are not what
    /// this card scores: the score comes from the stack's share of a published
    /// limit, and food either is already inside that total (where the limit
    /// covers it) or is excluded by the limit's own definition. Either way it
    /// carries no separate share, and each row says which of the two it is.
    private func foodContributions(samples: [HealthMetricSample],
                                   totals: [SupplementStackModel.NutrientTotal],
                                   now: Date) -> [MetricContribution] {
        var out: [MetricContribution] = []
        let byMetric = Dictionary(uniqueKeysWithValues:
            totals.compactMap { total -> (MetricType, SupplementStackModel.NutrientTotal)? in
                total.nutrient.dietaryMetric.map { ($0, total) }
            })

        for metric in candidateMetrics {
            let logged = samples.samples(of: metric)
            guard !logged.isEmpty else { continue }
            let nutrient = Nutrient.allCases.first { $0.dietaryMetric == metric }
            let total = byMetric[metric]
            let detail: String

            if let nutrient, case .supplementalOnly(let why) = nutrient.limitBasis {
                detail = "Charted, never added — \(why)"
            } else if metric == .dietaryVitaminA {
                detail = "Charted, never added — this series is in RAE and "
                    + "includes carotenoids, while the vitamin A upper limit is "
                    + "on preformed vitamin A alone, so adding it would put "
                    + "vegetables into a retinol total."
            } else if let total, total.countsFood {
                detail = "\(SupplementFormatting.amount(total.fromFood, unit: total.nutrient.canonicalUnit)) "
                    + "a day, already inside the total above — it carries no "
                    + "separate share because it is part of the one figure this "
                    + "card scores."
            } else {
                detail = "Logged, and left out of the total — a fortnight with "
                    + "fewer than \(SupplementStackModel.minimumFoodDays) logged "
                    + "days cannot stand in for a daily intake, so it carries no "
                    + "share and nothing was assumed for the days you did not log."
            }

            out.append(MetricContribution(metric: metric, higherIsBetter: nil,
                                          weight: 0, detail: detail))
        }
        return out
    }

    // MARK: - What this card works out (add-insight §5a)
    //
    // **(b) Produced figures, both of them, and one series per nutrient.**
    //
    // `highestShareOfLimit` is a function of the whole stack against a table
    // indexed by the reader's age — it moves on a birthday without a single
    // label changing, which is the test that separates a produced figure from a
    // pass-through. Series.
    //
    // `unresolvedIngredients` is the count of ingredients naming a nutrient with
    // no usable amount. **It is the one number here that nothing else in the app
    // could ever hold**, and it is what makes every other figure on this card
    // readable: a total is a floor exactly while this is above nought. Series.
    //
    // Each nutrient's own share of its limit is also a series, keyed by the
    // nutrient. Not a pass-through: the numerator is a sum across products in a
    // converted unit and the denominator is an age-indexed published figure, and
    // neither is a metric this app holds.
    //
    // ⚠️ The dietary series get none. Each is one metric at face value — the
    // reader's own pass-through rule (c) — and their departures are harvested
    // from `MetricContribution` for nothing.

    static let highestShareKey = "highestShareOfUpperLimit"
    static let unresolvedKey = "unresolvedIngredients"

    static func shareKey(_ nutrient: Nutrient) -> String {
        "share.\(nutrient.rawValue)"
    }

    static func derivedOutputs(_ out: SupplementStackModel.Output) -> [DerivedOutput] {
        var outputs: [DerivedOutput] = [
            .init(key: unresolvedKey,
                  displayName: "Stack ingredients with no stated amount",
                  unit: "", value: Double(out.unresolvedCount),
                  higherIsBetter: false, precision: 0),
        ]
        if let share = out.highestShare {
            outputs.append(.init(
                key: highestShareKey,
                displayName: "Highest share of a published upper limit",
                unit: "%", value: share * 100,
                higherIsBetter: false, precision: 0))
        }
        for total in out.totals {
            guard let share = total.shareOfLimit else { continue }
            outputs.append(.init(
                key: shareKey(total.nutrient),
                displayName: "\(total.nutrient.displayName), share of upper limit",
                unit: "%", value: share * 100,
                higherIsBetter: false, precision: 0))
        }
        return outputs
    }

    /// The weighting rows: each nutrient's part of the deduction, on the
    /// `.worstOffender` basis, plus the two produced figures at weight 0.
    static func factors(_ out: SupplementStackModel.Output) -> [ScoreFactor] {
        var factors: [ScoreFactor] = []

        for total in out.totals {
            guard let share = total.shareOfLimit else { continue }
            let deduction = 100 - SupplementStackModel.curve(share: share)
            guard deduction > 0 else {
                factors.append(.producedFigure(
                    DerivedSeriesID(.supplementStack, shareKey(total.nutrient)),
                    name: total.nutrient.displayName,
                    detail: "\(SupplementFormatting.percent(share)) of its "
                        + "published upper limit — far enough under it to take "
                        + "nothing off this card's number, which is set by "
                        + "whichever nutrient sits nearest its own limit."))
                continue
            }
            factors.append(.derived(
                DerivedSeriesID(.supplementStack, shareKey(total.nutrient)),
                name: total.nutrient.displayName,
                weight: deduction,
                detail: "\(total.isComplete ? "" : "At least ")"
                    + "\(SupplementFormatting.amount(total.countedTotal, unit: total.nutrient.canonicalUnit))"
                    + " a day, \(SupplementFormatting.percent(share)) of its published upper limit."))
        }

        factors.append(.producedFigure(
            DerivedSeriesID(.supplementStack, unresolvedKey),
            name: "Ingredients with no stated amount",
            detail: "\(out.unresolvedCount) of them — it carries no share "
                + "because it is not a quantity of anything, it is how much of "
                + "the stack could not be counted, and every total above is a "
                + "floor while it is above nought."))

        if let share = out.highestShare {
            factors.append(.producedFigure(
                DerivedSeriesID(.supplementStack, highestShareKey),
                name: "Highest share of a published upper limit",
                detail: "\(SupplementFormatting.percent(share)) — this is itself "
                    + "card's number rather than an input to it, so it carries "
                    + "no share of itself."))
        }
        return factors
    }
}
