import Foundation

/// **A nutrient a supplement label can declare**, in the identity the published
/// intake limits are stated against.
///
/// ## Why this is not `MetricType`
///
/// A `MetricType` is a measured series. This is a *substance*: the thing a label
/// lists and a limit is published for. Several of these do have a dietary metric
/// (`dietaryCalcium`, `dietaryIron`, …) and `dietaryMetric` names it — but most
/// have none, nothing on a phone measures any of them in a *supplement*, and the
/// upper limits below are keyed by nutrient rather than by series.
///
/// ## The unit trap this type exists to hold
///
/// Supplement labels are not written in the units the limits are published in.
/// A multivitamin lists vitamin A in IU, vitamin E in IU, and folate in µg DFE;
/// the Tolerable Upper Intake Levels are stated in µg of *preformed* vitamin A,
/// mg of *supplemental α-tocopherol*, and µg of *folic acid*. Two of those three
/// conversions are genuinely ambiguous unless the label says which form it is —
/// see `NutrientAmount.converted(to:)`, which refuses rather than guesses.
///
/// ⚠️ **`limitBasis` is the other half, and it is what makes this card honest at
/// all.** Several upper limits apply *only* to the supplemental or fortified
/// form — magnesium, niacin, folate, vitamin E, and preformed vitamin A — which
/// is exactly why a supplement stack can be weighed against them without knowing
/// anything about the reader's diet. The rest are limits on **total** intake, and
/// there the stack alone is a floor rather than the figure. Nothing here is
/// allowed to blur the two.
public enum Nutrient: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    // Fat-soluble vitamins
    case vitaminA
    case vitaminD
    case vitaminE
    case vitaminK
    // Water-soluble vitamins
    case vitaminC
    case thiamin
    case riboflavin
    case niacin
    case vitaminB6
    case folate
    case vitaminB12
    case pantothenicAcid
    case biotin
    case choline
    // Minerals
    case calcium
    case chromium
    case copper
    case fluoride
    case iodine
    case iron
    case magnesium
    case manganese
    case molybdenum
    case phosphorus
    case selenium
    case zinc
    // Minerals with an upper limit and no intake recommendation at all
    case boron
    case nickel
    case vanadium

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vitaminA: return "Vitamin A"
        case .vitaminD: return "Vitamin D"
        case .vitaminE: return "Vitamin E"
        case .vitaminK: return "Vitamin K"
        case .vitaminC: return "Vitamin C"
        case .thiamin: return "Thiamin (B1)"
        case .riboflavin: return "Riboflavin (B2)"
        case .niacin: return "Niacin (B3)"
        case .vitaminB6: return "Vitamin B6"
        case .folate: return "Folate"
        case .vitaminB12: return "Vitamin B12"
        case .pantothenicAcid: return "Pantothenic acid (B5)"
        case .biotin: return "Biotin"
        case .choline: return "Choline"
        case .calcium: return "Calcium"
        case .chromium: return "Chromium"
        case .copper: return "Copper"
        case .fluoride: return "Fluoride"
        case .iodine: return "Iodine"
        case .iron: return "Iron"
        case .magnesium: return "Magnesium"
        case .manganese: return "Manganese"
        case .molybdenum: return "Molybdenum"
        case .phosphorus: return "Phosphorus"
        case .selenium: return "Selenium"
        case .zinc: return "Zinc"
        case .boron: return "Boron"
        case .nickel: return "Nickel"
        case .vanadium: return "Vanadium"
        }
    }

    /// The unit every figure for this nutrient is normalised to before anything
    /// is added up or compared. Chosen to be the unit its **limit** is published
    /// in, so the comparison never has to convert.
    public var canonicalUnit: NutrientUnit {
        switch self {
        case .vitaminA: return .microgramsRAE
        case .folate: return .microgramsFolicAcid
        case .vitaminD, .vitaminK, .biotin, .vitaminB12, .chromium, .copper,
             .iodine, .molybdenum, .selenium:
            return .micrograms
        case .vitaminE, .vitaminC, .thiamin, .riboflavin, .niacin, .vitaminB6,
             .pantothenicAcid, .choline, .calcium, .fluoride, .iron, .magnesium,
             .manganese, .phosphorus, .zinc, .boron, .nickel, .vanadium:
            return .milligrams
        }
    }

    /// **Whose intake the published upper limit is a limit on.**
    ///
    /// The single most load-bearing property in this file. It decides whether a
    /// stack total is *the* number or merely a floor, and the card says a
    /// different sentence for each.
    public var limitBasis: UpperLimitBasis {
        switch self {
        // ⚠️ The five where the limit is written against the supplemental or
        // fortified form specifically. Adding food to these would be adding a
        // quantity the limit was never about.
        case .magnesium:
            return .supplementalOnly("The magnesium upper limit is a limit on "
                + "magnesium from supplements and medicines. Magnesium in food "
                + "is not counted toward it.")
        case .niacin:
            return .supplementalOnly("The niacin upper limit is written against "
                + "synthetic niacin from supplements and fortified food, not "
                + "the niacin in an ordinary diet.")
        case .folate:
            return .supplementalOnly("The folate upper limit is a limit on "
                + "folic acid from supplements and fortified food. Folate "
                + "occurring in food is not counted toward it.")
        case .vitaminE:
            return .supplementalOnly("The vitamin E upper limit is a limit on "
                + "supplemental alpha-tocopherol, in any form.")
        case .vitaminA:
            return .supplementalOnly("The vitamin A upper limit is a limit on "
                + "preformed vitamin A — retinol and retinyl esters. "
                + "Beta-carotene is not counted toward it, and a label giving "
                + "only IU does not say which it is.")
        case .vitaminD, .vitaminC, .calcium, .copper, .fluoride, .iodine, .iron,
             .manganese, .molybdenum, .phosphorus, .selenium, .zinc, .choline,
             .vitaminB6, .boron, .nickel, .vanadium:
            return .totalIntake
        // No upper limit has been published for these at all — see
        // `NutrientUpperLimits`, which says what that does and does not mean.
        case .vitaminK, .thiamin, .riboflavin, .vitaminB12, .pantothenicAcid,
             .biotin, .chromium:
            return .noLimitPublished
        }
    }

    /// The dietary series this app already holds for the same substance, where
    /// one exists.
    ///
    /// Read **only** where `limitBasis == .totalIntake`: for the supplemental
    /// limits above, food is deliberately not added, and for the rest there is
    /// no series. Declared here rather than in the card so the two cannot
    /// disagree about which nutrients have a food half.
    public var dietaryMetric: MetricType? {
        switch self {
        case .calcium: return .dietaryCalcium
        case .iron: return .dietaryIron
        case .zinc: return .dietaryZinc
        case .vitaminC: return .dietaryVitaminC
        case .vitaminD: return .dietaryVitaminD
        // ⚠️ Named, and deliberately **not** added. `.dietaryVitaminA` is
        // reported in µg RAE, which includes carotenoids — and the vitamin A
        // upper limit is on preformed vitamin A alone. Adding it would put
        // carrots into a retinol total.
        case .vitaminA: return .dietaryVitaminA
        // Named, not added, for the reason `limitBasis` gives: this limit is on
        // supplemental magnesium only.
        case .magnesium: return .dietaryMagnesium
        case .vitaminB12: return .dietaryVitaminB12
        default: return nil
        }
    }

    /// Whether this app adds the reader's logged food intake into the total it
    /// weighs against the limit. True only where both halves line up: a limit on
    /// *total* intake, and a series measuring the same thing the limit is about.
    public var countsFoodTowardTheLimit: Bool {
        guard case .totalIntake = limitBasis, let metric = dietaryMetric else { return false }
        // Vitamin A's series is RAE-including-carotenoids against a
        // preformed-only limit, so it is excluded by `limitBasis` above and
        // never reaches here. The guard is written out because the pairing is
        // the trap.
        return metric != .dietaryVitaminA
    }
}

/// Whose intake a published upper limit is a limit on.
public enum UpperLimitBasis: Sendable, Equatable, Hashable {
    /// The limit covers intake from every source — supplements, food, water.
    /// A stack total is a **floor**, and the card must say so.
    case totalIntake
    /// The limit is written against supplemental or fortified forms only, with
    /// the reason. A stack total *is* the quantity the limit is about.
    case supplementalOnly(String)
    /// None has been published.
    case noLimitPublished
}

/// The units a supplement label and an intake table are written in.
///
/// ⚠️ **`internationalUnits` is not a unit of mass and cannot be converted to one
/// without knowing the substance and its chemical form.** It is here because
/// labels use it, and it is kept distinct so a conversion has to be asked for
/// rather than assumed.
public enum NutrientUnit: String, Codable, Sendable, Hashable, CaseIterable {
    case grams
    case milligrams
    case micrograms
    /// µg of retinol activity equivalents — the unit the vitamin A limit uses.
    case microgramsRAE
    /// µg of folic acid, which is what the folate limit is written in.
    case microgramsFolicAcid
    /// µg of dietary folate equivalents, which is what a label often prints.
    /// **1 µg of folic acid taken as a supplement counts as 2 µg DFE**, so the
    /// two are not interchangeable and the conversion halves the number.
    case microgramsDFE
    case internationalUnits

    public var symbol: String {
        switch self {
        case .grams: return "g"
        case .milligrams: return "mg"
        case .micrograms: return "mcg"
        case .microgramsRAE: return "mcg RAE"
        case .microgramsFolicAcid: return "mcg"
        case .microgramsDFE: return "mcg DFE"
        case .internationalUnits: return "IU"
        }
    }

    /// Mass in micrograms, for the units that are masses. `nil` for IU and for
    /// the two equivalence units, which are not plain masses of one substance.
    var microgramsPerUnit: Double? {
        switch self {
        case .grams: return 1_000_000
        case .milligrams: return 1_000
        case .micrograms, .microgramsRAE, .microgramsFolicAcid: return 1
        case .microgramsDFE, .internationalUnits: return nil
        }
    }
}

/// **The chemical form a label declared**, where the conversion depends on it.
///
/// Every case here exists because a real label is ambiguous without it, and the
/// ambiguity is large: natural and synthetic vitamin E differ by a factor of
/// 1.49, and an IU of retinol is six times an IU of beta-carotene in RAE terms.
public enum NutrientForm: String, Codable, Sendable, Hashable, CaseIterable {
    /// Retinol or a retinyl ester — the form the vitamin A limit is about.
    case preformedVitaminA
    /// Beta-carotene, which carries **no** share of the vitamin A upper limit.
    case betaCarotene
    /// d-alpha-tocopherol and its esters: 1 mg = 1.49 IU.
    case naturalVitaminE
    /// dl-alpha-tocopherol and its esters: 1 mg = 2.22 IU.
    case syntheticVitaminE
    /// Cholecalciferol or ergocalciferol: 1 µg = 40 IU either way.
    case vitaminD

    public var displayName: String {
        switch self {
        case .preformedVitaminA: return "Preformed (retinol/retinyl)"
        case .betaCarotene: return "Beta-carotene"
        case .naturalVitaminE: return "Natural (d-alpha-tocopherol)"
        case .syntheticVitaminE: return "Synthetic (dl-alpha-tocopherol)"
        case .vitaminD: return "Cholecalciferol or ergocalciferol"
        }
    }
}

/// One declared quantity on a label, with the unit and — where it matters — the
/// form it was declared in.
public struct NutrientAmount: Codable, Sendable, Hashable {
    public let value: Double
    public let unit: NutrientUnit
    /// `nil` when the label did not say, which is the common case and the reason
    /// `converted(to:)` can fail.
    public let form: NutrientForm?

    public init(value: Double, unit: NutrientUnit, form: NutrientForm? = nil) {
        self.value = value
        self.unit = unit
        self.form = form
    }

    /// Why a declared quantity could not be turned into the unit its limit is
    /// published in.
    ///
    /// **Never a zero and never a guess.** An unconvertible amount is carried
    /// through the whole summation as an unknown — see
    /// `NutrientTotal.unresolved` — because a supplement that silently became
    /// nought is worse than one that was never entered.
    public enum ConversionFailure: Error, Sendable, Equatable, Hashable {
        /// IU, and the label did not say which form — so the factor is unknown
        /// and the two candidates differ materially.
        case formNotStated(Nutrient, betweenFactors: String)
        /// IU for a nutrient with no defined IU conversion at all.
        case noDefinedConversion(Nutrient)
    }

    /// The same quantity in the nutrient's `canonicalUnit`, or the reason it
    /// cannot be expressed there.
    ///
    /// The three interesting conversions, and all three are here rather than at
    /// a call site because getting one wrong is invisible in the output:
    ///
    /// - **Vitamin D**: 1 µg = 40 IU, for cholecalciferol and ergocalciferol
    ///   alike, so IU converts without knowing the form.
    /// - **Vitamin E**: 1 mg = 1.49 IU natural, 2.22 IU synthetic. An unlabelled
    ///   IU figure is ambiguous by 49%, which is more than enough to move a
    ///   1,000 mg limit, so it refuses.
    /// - **Vitamin A**: 1 IU = 0.3 µg RAE as retinol, 0.05 µg RAE as
    ///   beta-carotene — and beta-carotene carries **none** of the upper limit.
    ///   An unlabelled IU figure is not merely imprecise here, it is a different
    ///   question, so it refuses.
    /// - **Folate**: µg DFE ÷ 2 gives µg of folic acid, because a supplement's
    ///   folic acid is counted as twice its mass in DFE.
    public func converted(to nutrient: Nutrient) -> Result<Double, ConversionFailure> {
        let target = nutrient.canonicalUnit

        // Folate's two equivalence units, in both directions.
        if nutrient == .folate {
            switch unit {
            case .microgramsDFE: return .success(value / 2)
            case .microgramsFolicAcid, .micrograms: return .success(value)
            case .milligrams: return .success(value * 1_000)
            case .grams: return .success(value * 1_000_000)
            case .internationalUnits, .microgramsRAE:
                return .failure(.noDefinedConversion(nutrient))
            }
        }

        if unit == .internationalUnits {
            switch nutrient {
            case .vitaminD:
                return .success(value / 40)
            case .vitaminE:
                switch form {
                case .naturalVitaminE: return .success(value / 1.49)
                case .syntheticVitaminE: return .success(value / 2.22)
                default:
                    return .failure(.formNotStated(
                        nutrient,
                        betweenFactors: "1 mg is 1.49 IU as natural "
                            + "d-alpha-tocopherol and 2.22 IU as synthetic "
                            + "dl-alpha-tocopherol"))
                }
            case .vitaminA:
                switch form {
                case .preformedVitaminA: return .success(value * 0.3)
                // Beta-carotene is vitamin A activity and carries none of the
                // preformed upper limit. Zero is the *right* answer here and is
                // not a guess — the limit is defined to exclude it.
                case .betaCarotene: return .success(0)
                default:
                    return .failure(.formNotStated(
                        nutrient,
                        betweenFactors: "1 IU is 0.3 mcg RAE as retinol and "
                            + "0.05 mcg RAE as beta-carotene, and only the "
                            + "first counts toward the upper limit"))
                }
            default:
                return .failure(.noDefinedConversion(nutrient))
            }
        }

        // Vitamin A declared as a mass: µg RAE is the canonical unit, and a
        // label giving mg or µg of retinol is the same mass.
        guard let from = unit.microgramsPerUnit,
              let to = target.microgramsPerUnit else {
            return .failure(.noDefinedConversion(nutrient))
        }
        return .success(value * from / to)
    }
}
