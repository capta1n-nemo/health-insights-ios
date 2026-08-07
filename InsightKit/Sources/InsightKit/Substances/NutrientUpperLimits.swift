import Foundation

/// **The published intake figures a supplement stack is weighed against.**
///
/// Source: the US National Academies of Sciences, Engineering, and Medicine
/// Dietary Reference Intakes — the UL tables (Tolerable Upper Intake Levels) and
/// the RDA/AI tables for vitamins and elements, as consolidated in the 2019 DRI
/// summary tables. They are the tables the NIH Office of Dietary Supplements
/// publishes its fact sheets against, which matters because DSLD — the label
/// source this feature is designed around — is published by the same office.
///
/// ## What is age-specific, what is sex-specific, and the claim that was wrong
///
/// The brief for this work said the limits are *"sex- and age-specific"*. Half
/// of that is right and the half that is wrong matters, so it is written down
/// here rather than quietly implemented differently:
///
/// - **The upper limits are age-specific and not sex-specific.** For every
///   nutrient in the DRI tables, adult males and adult females share one UL.
///   What changes it is the life stage: 14–18 is lower than adult for a dozen
///   nutrients, calcium drops at 51 and phosphorus at 71.
/// - **The intake recommendations *are* sex-specific**, and substantially — iron
///   is 18 mg for women 19–50 and 8 mg for men. So sex is genuinely required,
///   just for the RDA half rather than the limit half, and the card would be
///   wrong without it.
/// - **Pregnancy and lactation change several ULs**, and nothing in this app
///   knows about either. Every figure here is the non-pregnant, non-lactating
///   column and `LimitResolution` says so out loud rather than in a footnote.
///
/// ## Where the table stops, and why it refuses rather than extrapolates
///
/// It starts at 14. Below that the DRI bands are 1–3, 4–8 and 9–13 with
/// materially lower limits, and a reader under 14 is not who this app is for —
/// so `limit(for:sex:age:)` returns `.outsideTable` rather than handing a child
/// an adult's ceiling. The same refusal covers a missing age or a missing sex:
/// **a limit resolved against a guessed profile is a number with a false
/// authority**, and the card prints what it is missing instead.
///
/// ## ⚠️ Absence of a limit is not a statement of safety
///
/// Seven nutrients here have no published UL. The NAM's own text is explicit
/// that this means the evidence was insufficient to set one — not that intake at
/// any level is without risk. `noLimitPublished` carries that sentence to the
/// card, because "no upper limit" rendered bare reads as the opposite of what it
/// means.
///
/// ## Nothing here is advice
///
/// These are published population reference values. This type reports a number
/// and the figure it is being compared with. It contains no recommendation, no
/// threshold for action, and no instruction — see `SupplementStackModel` for the
/// wording rule that follows from it.
public enum NutrientUpperLimits {

    /// The DRI life-stage bands this table covers, for a non-pregnant,
    /// non-lactating reader.
    public enum LifeStage: String, Sendable, CaseIterable, Hashable {
        case teen14to18
        case adult19to50
        case adult51to70
        case adult71plus

        public var displayName: String {
            switch self {
            case .teen14to18: return "14–18"
            case .adult19to50: return "19–50"
            case .adult51to70: return "51–70"
            case .adult71plus: return "71 and over"
            }
        }

        /// `nil` below 14 — see the type comment.
        public static func containing(age: Double) -> LifeStage? {
            switch age {
            case ..<14: return nil
            case ..<19: return .teen14to18
            case ..<51: return .adult19to50
            case ..<71: return .adult51to70
            default: return .adult71plus
            }
        }
    }

    /// What a lookup produced — a figure, or a stated reason there is none.
    ///
    /// A `Result`-shaped answer rather than an optional, for the reason
    /// `CoverageGate` is a type: a caller cannot render "no limit" without
    /// saying which kind of "no limit" it is, and the three kinds mean opposite
    /// things to a reader.
    public enum LimitResolution: Sendable, Equatable, Hashable {
        /// The published Tolerable Upper Intake Level, in the nutrient's
        /// `canonicalUnit`.
        case limit(Double)
        /// The DRI tables publish none. Carries the NAM's own caution.
        case noLimitPublished(String)
        /// The reader's life stage is not in this table — too young, or the
        /// profile does not say. Carries what is missing.
        case outsideTable(String)
    }

    // MARK: - Upper limits

    /// The Tolerable Upper Intake Level, in the nutrient's `canonicalUnit`.
    ///
    /// - Parameters:
    ///   - sex: Required, though no adult UL varies by it. Taken so the call
    ///     site cannot resolve a limit against a profile it has not checked —
    ///     the same profile it needs for `recommendedIntake` — and so this
    ///     signature does not have to change if a future table splits.
    ///   - age: In years.
    public static func limit(for nutrient: Nutrient, sex: BiologicalSex?,
                             age: Double?) -> LimitResolution {
        guard let age else {
            return .outsideTable("Your date of birth. Upper limits are published "
                + "per age band and the app will not pick one for you.")
        }
        guard sex != nil else {
            return .outsideTable("Your sex. It does not change the upper limit "
                + "itself, but it changes the recommended intake this is shown "
                + "beside, and a limit without it would be half an answer.")
        }
        guard let stage = LifeStage.containing(age: age) else {
            return .outsideTable("This app's intake tables start at 14. Below "
                + "that the published limits are materially lower, and handing "
                + "a younger reader an adult ceiling is the one error worth "
                + "refusing outright.")
        }
        if case .noLimitPublished = nutrient.limitBasis {
            return .noLimitPublished(noLimitCaution)
        }
        guard let value = upperLimits[nutrient]?[stage] else {
            return .noLimitPublished(noLimitCaution)
        }
        return .limit(value)
    }

    /// The sentence that goes wherever a nutrient has no published limit.
    ///
    /// ⚠️ Never shortened to "no upper limit". That phrase reads as a licence,
    /// and it is the opposite of what the tables mean by it.
    public static let noLimitCaution =
        "No upper limit has been published for this. In the Dietary Reference "
        + "Intakes that means there was not enough evidence to set one — it is "
        + "not a finding that any amount is safe."

    /// Tolerable Upper Intake Levels, in each nutrient's `canonicalUnit`
    /// (mg, mcg, or mcg RAE / mcg folic acid).
    ///
    /// Only nutrients with a published UL appear. A nutrient absent here resolves
    /// to `.noLimitPublished`, which is checked against `Nutrient.limitBasis` so
    /// the two cannot disagree — `NutrientLimitTests` pins that agreement.
    static let upperLimits: [Nutrient: [LifeStage: Double]] = [
        // Preformed vitamin A, mcg RAE.
        .vitaminA: [.teen14to18: 2_800, .adult19to50: 3_000,
                    .adult51to70: 3_000, .adult71plus: 3_000],
        // mcg. 100 mcg is 4,000 IU.
        .vitaminD: [.teen14to18: 100, .adult19to50: 100,
                    .adult51to70: 100, .adult71plus: 100],
        // mg of supplemental alpha-tocopherol.
        .vitaminE: [.teen14to18: 800, .adult19to50: 1_000,
                    .adult51to70: 1_000, .adult71plus: 1_000],
        .vitaminC: [.teen14to18: 1_800, .adult19to50: 2_000,
                    .adult51to70: 2_000, .adult71plus: 2_000],
        // mg of synthetic niacin.
        .niacin: [.teen14to18: 30, .adult19to50: 35,
                  .adult51to70: 35, .adult71plus: 35],
        .vitaminB6: [.teen14to18: 80, .adult19to50: 100,
                     .adult51to70: 100, .adult71plus: 100],
        // mcg of folic acid, not DFE.
        .folate: [.teen14to18: 800, .adult19to50: 1_000,
                  .adult51to70: 1_000, .adult71plus: 1_000],
        .choline: [.teen14to18: 3_000, .adult19to50: 3_500,
                   .adult51to70: 3_500, .adult71plus: 3_500],
        // Drops at 51 — one of the two genuinely age-varying adult limits.
        .calcium: [.teen14to18: 3_000, .adult19to50: 2_500,
                   .adult51to70: 2_000, .adult71plus: 2_000],
        .copper: [.teen14to18: 8_000, .adult19to50: 10_000,
                  .adult51to70: 10_000, .adult71plus: 10_000],
        .fluoride: [.teen14to18: 10, .adult19to50: 10,
                    .adult51to70: 10, .adult71plus: 10],
        .iodine: [.teen14to18: 900, .adult19to50: 1_100,
                  .adult51to70: 1_100, .adult71plus: 1_100],
        .iron: [.teen14to18: 45, .adult19to50: 45,
                .adult51to70: 45, .adult71plus: 45],
        // mg of supplemental magnesium only.
        .magnesium: [.teen14to18: 350, .adult19to50: 350,
                     .adult51to70: 350, .adult71plus: 350],
        .manganese: [.teen14to18: 9, .adult19to50: 11,
                     .adult51to70: 11, .adult71plus: 11],
        .molybdenum: [.teen14to18: 1_700, .adult19to50: 2_000,
                      .adult51to70: 2_000, .adult71plus: 2_000],
        // The other genuinely age-varying adult limit: drops at 71.
        .phosphorus: [.teen14to18: 4_000, .adult19to50: 4_000,
                      .adult51to70: 4_000, .adult71plus: 3_000],
        .selenium: [.teen14to18: 400, .adult19to50: 400,
                    .adult51to70: 400, .adult71plus: 400],
        .zinc: [.teen14to18: 34, .adult19to50: 40,
                .adult51to70: 40, .adult71plus: 40],
        .boron: [.teen14to18: 17, .adult19to50: 20,
                 .adult51to70: 20, .adult71plus: 20],
        .nickel: [.teen14to18: 1.0, .adult19to50: 1.0,
                  .adult51to70: 1.0, .adult71plus: 1.0],
        // No UL is set for teenagers; the adult figure is for adults only.
        .vanadium: [.adult19to50: 1.8, .adult51to70: 1.8, .adult71plus: 1.8],
    ]

    // MARK: - Recommended intake

    /// What an RDA or AI lookup produced.
    public enum IntakeReference: Sendable, Equatable, Hashable {
        /// A Recommended Dietary Allowance — the intake meeting the needs of
        /// almost everyone in the group.
        case rda(Double)
        /// An Adequate Intake — used where the evidence could not support an
        /// RDA, which is a weaker claim and is labelled as one.
        case ai(Double)
        /// Neither is published. The three elements with a limit and no
        /// recommendation are the whole list.
        case none

        public var value: Double? {
            switch self {
            case .rda(let v), .ai(let v): return v
            case .none: return nil
            }
        }

        /// What to call it on a row, so an AI is never shown as an RDA.
        public var label: String? {
            switch self {
            case .rda: return "recommended intake"
            case .ai: return "adequate intake"
            case .none: return nil
            }
        }
    }

    /// The RDA or AI for this reader, in the nutrient's `canonicalUnit`.
    ///
    /// **This is the sex-specific half**, and it is why the profile is mandatory
    /// on the card rather than merely useful.
    public static func recommendedIntake(for nutrient: Nutrient, sex: BiologicalSex?,
                                         age: Double?) -> IntakeReference {
        guard let sex, let age, let stage = LifeStage.containing(age: age) else { return .none }
        guard let byStage = recommendations[nutrient], let bySex = byStage[stage] else {
            return .none
        }
        return sex == .male ? bySex.male : bySex.female
    }

    struct SexPair: Sendable {
        let male: IntakeReference
        let female: IntakeReference
        init(_ male: IntakeReference, _ female: IntakeReference) {
            self.male = male
            self.female = female
        }
        /// Both sexes on one figure.
        init(both value: IntakeReference) {
            self.male = value
            self.female = value
        }
    }

    /// RDA (or AI where the evidence could not support an RDA), by life stage
    /// and sex, in each nutrient's `canonicalUnit`.
    ///
    /// ⚠️ **Folate's RDA is published in mcg DFE and this table holds mcg of
    /// folic acid**, which is the unit its *limit* is in and therefore the unit
    /// everything here is normalised to. 400 mcg DFE of folic acid taken as a
    /// supplement is 200 mcg of folic acid, so that is the figure. The
    /// halving is stated here because it looks like a typo otherwise.
    static let recommendations: [Nutrient: [LifeStage: SexPair]] = [
        .vitaminA: [
            .teen14to18: SexPair(.rda(900), .rda(700)),
            .adult19to50: SexPair(.rda(900), .rda(700)),
            .adult51to70: SexPair(.rda(900), .rda(700)),
            .adult71plus: SexPair(.rda(900), .rda(700))],
        .vitaminD: [
            .teen14to18: SexPair(both: .rda(15)),
            .adult19to50: SexPair(both: .rda(15)),
            .adult51to70: SexPair(both: .rda(15)),
            .adult71plus: SexPair(both: .rda(20))],
        .vitaminE: [
            .teen14to18: SexPair(both: .rda(15)),
            .adult19to50: SexPair(both: .rda(15)),
            .adult51to70: SexPair(both: .rda(15)),
            .adult71plus: SexPair(both: .rda(15))],
        .vitaminK: [
            .teen14to18: SexPair(.ai(75), .ai(75)),
            .adult19to50: SexPair(.ai(120), .ai(90)),
            .adult51to70: SexPair(.ai(120), .ai(90)),
            .adult71plus: SexPair(.ai(120), .ai(90))],
        .vitaminC: [
            .teen14to18: SexPair(.rda(75), .rda(65)),
            .adult19to50: SexPair(.rda(90), .rda(75)),
            .adult51to70: SexPair(.rda(90), .rda(75)),
            .adult71plus: SexPair(.rda(90), .rda(75))],
        .thiamin: [
            .teen14to18: SexPair(.rda(1.2), .rda(1.0)),
            .adult19to50: SexPair(.rda(1.2), .rda(1.1)),
            .adult51to70: SexPair(.rda(1.2), .rda(1.1)),
            .adult71plus: SexPair(.rda(1.2), .rda(1.1))],
        .riboflavin: [
            .teen14to18: SexPair(.rda(1.3), .rda(1.0)),
            .adult19to50: SexPair(.rda(1.3), .rda(1.1)),
            .adult51to70: SexPair(.rda(1.3), .rda(1.1)),
            .adult71plus: SexPair(.rda(1.3), .rda(1.1))],
        .niacin: [
            .teen14to18: SexPair(.rda(16), .rda(14)),
            .adult19to50: SexPair(.rda(16), .rda(14)),
            .adult51to70: SexPair(.rda(16), .rda(14)),
            .adult71plus: SexPair(.rda(16), .rda(14))],
        .vitaminB6: [
            .teen14to18: SexPair(.rda(1.3), .rda(1.2)),
            .adult19to50: SexPair(.rda(1.3), .rda(1.3)),
            .adult51to70: SexPair(.rda(1.7), .rda(1.5)),
            .adult71plus: SexPair(.rda(1.7), .rda(1.5))],
        // 400 mcg DFE, expressed as folic acid — see the note above.
        .folate: [
            .teen14to18: SexPair(both: .rda(200)),
            .adult19to50: SexPair(both: .rda(200)),
            .adult51to70: SexPair(both: .rda(200)),
            .adult71plus: SexPair(both: .rda(200))],
        .vitaminB12: [
            .teen14to18: SexPair(both: .rda(2.4)),
            .adult19to50: SexPair(both: .rda(2.4)),
            .adult51to70: SexPair(both: .rda(2.4)),
            .adult71plus: SexPair(both: .rda(2.4))],
        .pantothenicAcid: [
            .teen14to18: SexPair(both: .ai(5)),
            .adult19to50: SexPair(both: .ai(5)),
            .adult51to70: SexPair(both: .ai(5)),
            .adult71plus: SexPair(both: .ai(5))],
        .biotin: [
            .teen14to18: SexPair(both: .ai(25)),
            .adult19to50: SexPair(both: .ai(30)),
            .adult51to70: SexPair(both: .ai(30)),
            .adult71plus: SexPair(both: .ai(30))],
        .choline: [
            .teen14to18: SexPair(.ai(550), .ai(400)),
            .adult19to50: SexPair(.ai(550), .ai(425)),
            .adult51to70: SexPair(.ai(550), .ai(425)),
            .adult71plus: SexPair(.ai(550), .ai(425))],
        .calcium: [
            .teen14to18: SexPair(both: .rda(1_300)),
            .adult19to50: SexPair(both: .rda(1_000)),
            .adult51to70: SexPair(.rda(1_000), .rda(1_200)),
            .adult71plus: SexPair(both: .rda(1_200))],
        .chromium: [
            .teen14to18: SexPair(.ai(35), .ai(24)),
            .adult19to50: SexPair(.ai(35), .ai(25)),
            .adult51to70: SexPair(.ai(30), .ai(20)),
            .adult71plus: SexPair(.ai(30), .ai(20))],
        .copper: [
            .teen14to18: SexPair(both: .rda(890)),
            .adult19to50: SexPair(both: .rda(900)),
            .adult51to70: SexPair(both: .rda(900)),
            .adult71plus: SexPair(both: .rda(900))],
        .fluoride: [
            .teen14to18: SexPair(.ai(3), .ai(3)),
            .adult19to50: SexPair(.ai(4), .ai(3)),
            .adult51to70: SexPair(.ai(4), .ai(3)),
            .adult71plus: SexPair(.ai(4), .ai(3))],
        .iodine: [
            .teen14to18: SexPair(both: .rda(150)),
            .adult19to50: SexPair(both: .rda(150)),
            .adult51to70: SexPair(both: .rda(150)),
            .adult71plus: SexPair(both: .rda(150))],
        // The starkest sex difference in the table, and the reason this card
        // cannot run on age alone.
        .iron: [
            .teen14to18: SexPair(.rda(11), .rda(15)),
            .adult19to50: SexPair(.rda(8), .rda(18)),
            .adult51to70: SexPair(.rda(8), .rda(8)),
            .adult71plus: SexPair(.rda(8), .rda(8))],
        .magnesium: [
            .teen14to18: SexPair(.rda(410), .rda(360)),
            .adult19to50: SexPair(.rda(420), .rda(320)),
            .adult51to70: SexPair(.rda(420), .rda(320)),
            .adult71plus: SexPair(.rda(420), .rda(320))],
        .manganese: [
            .teen14to18: SexPair(.ai(2.2), .ai(1.6)),
            .adult19to50: SexPair(.ai(2.3), .ai(1.8)),
            .adult51to70: SexPair(.ai(2.3), .ai(1.8)),
            .adult71plus: SexPair(.ai(2.3), .ai(1.8))],
        .molybdenum: [
            .teen14to18: SexPair(both: .rda(43)),
            .adult19to50: SexPair(both: .rda(45)),
            .adult51to70: SexPair(both: .rda(45)),
            .adult71plus: SexPair(both: .rda(45))],
        .phosphorus: [
            .teen14to18: SexPair(both: .rda(1_250)),
            .adult19to50: SexPair(both: .rda(700)),
            .adult51to70: SexPair(both: .rda(700)),
            .adult71plus: SexPair(both: .rda(700))],
        .selenium: [
            .teen14to18: SexPair(both: .rda(55)),
            .adult19to50: SexPair(both: .rda(55)),
            .adult51to70: SexPair(both: .rda(55)),
            .adult71plus: SexPair(both: .rda(55))],
        .zinc: [
            .teen14to18: SexPair(.rda(11), .rda(9)),
            .adult19to50: SexPair(.rda(11), .rda(8)),
            .adult51to70: SexPair(.rda(11), .rda(8)),
            .adult71plus: SexPair(.rda(11), .rda(8))],
        // Boron, nickel and vanadium have an upper limit and no published
        // requirement — the body has no established need for supplemental
        // intake of any of them. Absent here on purpose.
    ]
}
