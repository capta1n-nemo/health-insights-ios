import Foundation

/// How a card's number is formed from its inputs — and therefore what a share
/// of it *means*.
///
/// ## Why this exists
///
/// "How this is weighted" used to have exactly two states: a card either
/// reported weighted contributors, or it said **"Not a weighted average"** and
/// pointed elsewhere. Four of the nine cards took the second branch, and on
/// three of them it was wrong rather than merely unhelpful:
///
/// - **Body Composition** scores body fat against a published healthy range.
///   That one measurement *is* the whole number, so "no signal has a percentage
///   share of it" describes a card that does not exist.
/// - **Substance Impact** builds a worst-offender-dominant penalty pool. Each
///   signal's part of the deduction is exactly computable — see
///   `SubstanceResponseAnalyzer.attribution`.
/// - **Heart Attack & Stroke Risk** runs published equations, which is a reason
///   the shares are not *proportions somebody chose* — not a reason they cannot
///   be reported. Holding one factor at its optimal value and re-running the
///   same equation is how the vascular-age literature already attributes risk,
///   and this app already ships that machinery.
///
/// Only Blood Pressure's cuff route was genuinely unweighted, and even there
/// "not a weighted average" is a weaker statement than the true one: *this is a
/// measurement, taken at face value.*
///
/// So the basis is stated by the model rather than inferred from whether the
/// weights happen to be zero, and the section says what that basis means.
public enum ScoreWeighting: Sendable, Equatable {

    /// Components blended in fixed proportions, renormalised over the ones that
    /// had data. Readiness, Sleep, Heart Health, Energy.
    case weightedAverage

    /// One measurement carries the whole number, scored against a published
    /// range. Fitness (VO₂max) and Body Composition (body fat, or BMI where no
    /// scale reports a fat fraction).
    ///
    /// Distinct from `weightedAverage` with a single 100% row, because that
    /// case's sentence — *"a signal missing today isn't counted as zero, the
    /// others simply carry more"* — describes a renormalisation over other
    /// components, and here there are none to carry it.
    case singleMeasure(String)

    /// A published equation. Shares are each input's own effect on the result —
    /// measured by holding it at its reference value and re-running the
    /// equation — rather than proportions anyone chose.
    case equation(String)

    /// A regression fitted to the reader's own paired readings. Shares come from
    /// the fitted coefficients, so they change as the fit does.
    case fit(String)

    /// A measurement taken at face value. There is no share to divide, and
    /// saying so is the honest answer rather than a gap.
    case measurement(String)

    /// The largest single response sets the number and the rest add to it.
    /// Shares are each one's part of the deduction.
    case worstOffender

    /// Votes accumulate: each signal leaning in the concerning direction adds
    /// its weight, scaled by how far it leans, and nothing is averaged away.
    /// Several small agreeing moves outrank one large one. The symptom radar —
    /// deliberately the opposite of `worstOffender`, because agreement is the
    /// finding there and a single outlier is an ordinary Tuesday.
    case accumulative

    /// The model has not said. The default, so a new insight is silent rather
    /// than claiming a basis nobody chose for it.
    case unstated

    /// What a share on this card means, in one sentence, above the bars.
    ///
    /// In InsightKit because it is the honesty claim rather than decoration, and
    /// the app target has no test target. Each sentence has to be true of the
    /// arithmetic directly above it: the renormalisation note belongs only to
    /// the weighted average, and printing it over an equation's held-at-optimal
    /// shares would describe a calculation nobody ran.
    public var explanation: String {
        switch self {
        case .weightedAverage:
            return "The share each signal has of the score, after dividing over "
                + "the ones that had data today. A signal missing today isn't "
                + "counted as zero — the others simply carry more."
        case .singleMeasure(let against):
            return "One measurement carries the whole number here, scored "
                + "against \(against). The other signals below are charted "
                + "rather than scored: they say what has been changing, not "
                + "what the number is."
        case .equation(let name):
            // Phrased so it reads for one engine or two without a plural
            // agreement to get wrong: the caller passes "SCORE2" or
            // "SCORE2 and ASCVD" and neither needs a verb from this sentence.
            return "Nobody chose these proportions — they come out of \(name). "
                + "Each share below is what that input is doing to your number, "
                + "measured by holding it at its optimal value and running the "
                + "same equation again. They are shares of one result rather "
                + "than separate additions to it, so they interact."
        case .fit(let what):
            return "These shares come from \(what), so they describe your own "
                + "readings rather than a rule. They move as the fit does — a "
                + "new cuff reading can change them."
        case .measurement(let what):
            return "\(what) There is no share to divide up: the number is the "
                + "reading, not a blend of the signals below."
        case .worstOffender:
            return "The largest single response sets this number and the rest "
                + "add to it, so one strong effect is not averaged away by "
                + "several that didn't move. Each share below is that signal's "
                + "part of what came off the score."
        case .accumulative:
            return "Votes accumulate here rather than average out: each signal "
                + "leaning in the concerning direction adds its own weight, "
                + "scaled by how far it leans, so several small agreeing moves "
                + "outrank one dramatic number. Each share below is the weight "
                + "that signal's vote carries."
        case .unstated:
            return "This card hasn't published how much each of its inputs "
                + "counts toward its number, so there is nothing to divide up "
                + "here. What it reads is charted below."
        }
    }

    /// Whether shares are meaningful at all on this basis. `.measurement` and
    /// `.unstated` are the two where a bar chart would be an invention.
    public var carriesShares: Bool {
        switch self {
        case .weightedAverage, .singleMeasure, .equation, .fit, .worstOffender,
             .accumulative:
            return true
        case .measurement, .unstated:
            return false
        }
    }
}

/// One input's share of a card's number, where the input is not necessarily
/// something the app measures.
///
/// `MetricContribution` is the contract for measured inputs and stays that way —
/// the overlay chart, its legend and this section all read it, so a metric's
/// share cannot be stated twice and drift.
///
/// The risk card is why this type exists beside it. Its number is produced
/// mostly by things no sensor reports — your age, your sex, a blood test,
/// whether you smoke — and those carry most of the weight. A weighting section
/// that could only hold metrics would show blood pressure at 100% of a number it
/// is a fraction of, which is a worse answer than the "not weighted" it replaced.
public struct ScoreFactor: Sendable, Hashable {

    /// Where the factor comes from, so the section can link a metric to its
    /// history and a grounding fact to the place it is entered.
    public enum Source: Sendable, Hashable {
        case metric(MetricType)
        case grounding(GroundingKind)
        /// Neither — something the model worked out, named by the series it
        /// keeps.
        ///
        /// ⚠️ **The id is the whole point, and it used to be absent.** This case
        /// carried no payload until 2026-08-06, so a row could say "Recent
        /// substance load — 42%" and nothing on the phone could answer "what has
        /// that been doing all month". The reader's complaint, verbatim: *"the
        /// metrics we are deriving from each card, are still not being turned
        /// into their own individual data sources, and used, especially in
        /// weightings."* A `.metric` row links to a history; a `.grounding` row
        /// links to where the fact is entered; the derived row linked nowhere
        /// because it could not say which derived thing it was.
        ///
        /// The id must name a series the same result actually produces — either
        /// a `DerivedOutput` key or one of the harvested component tiers — and
        /// `DerivedFactorIdentityTests` fails the build otherwise. An id nothing
        /// produces is a link to an empty page, which is worse than no link.
        case derived(DerivedSeriesID)
    }

    public let source: Source
    public let name: String
    /// Share of the number, on the same 0…1 scale as `MetricContribution.weight`
    /// and renormalised together with it, so a card's factors sum to 1.
    public let weight: Double
    /// The value as the model already formatted it.
    public let detail: String
    /// Whether the reader could change it.
    ///
    /// Age and sex cannot be, and a bar chart that ranks them beside cholesterol
    /// without saying so reads as a list of things to work on — with the largest
    /// bar on the one nobody can move. The risk card's own copy already makes
    /// this distinction ("that gap is the modifiable part") and the picture has
    /// to agree with it.
    public let isModifiable: Bool

    public init(source: Source, name: String, weight: Double,
                detail: String, isModifiable: Bool) {
        self.source = source
        self.name = name
        self.weight = weight
        self.detail = detail
        self.isModifiable = isModifiable
    }

    public var metric: MetricType? {
        if case .metric(let m) = source { return m }
        return nil
    }

    /// The series behind a derived factor, so a row can link through to its
    /// history in the Data tab exactly as a metric row links to its chart.
    public var derivedSeries: DerivedSeriesID? {
        if case .derived(let id) = source { return id }
        return nil
    }

    // MARK: Constructors for the two shapes a derived factor comes in
    //
    // Both exist so the *decision* is made at the call site and is visible in
    // the diff. The distinction is the one thing about this that is easy to get
    // wrong, and getting it wrong puts a second 100% on a card.

    /// **A figure that enters the number beside the other inputs, carrying its
    /// own share.** The substance card's decaying load is the standing example:
    /// it is a penalty term in the same pool as each measured response, so it
    /// genuinely divides the score with them.
    public static func derived(_ id: DerivedSeriesID, name: String, weight: Double,
                               detail: String, isModifiable: Bool = true) -> ScoreFactor {
        ScoreFactor(source: .derived(id), name: name, weight: weight,
                    detail: detail, isModifiable: isModifiable)
    }

    /// **A figure the card produces rather than consumes — an aggregate of the
    /// rows below it, or the thing that decides which days those rows compare.**
    ///
    /// ⚠️ **Weight 0, and the zero is the honest answer rather than a gap.** A
    /// pooled departure, a combined biological age, an observed TDEE: each is a
    /// function *of* the contributors, so handing it a share would count the same
    /// evidence twice and put 140% on a card whose bars are supposed to sum to
    /// one. It still belongs on both sections — the reader asked for exactly
    /// that — so it renders in "What goes into this" and in the weighting
    /// section's *charted, not scored* group, where every row states why it
    /// carries nothing.
    ///
    /// ⚠️ **`detail` must contain an em-dash clause giving that reason.** It is
    /// the reader's own rule — an input either carries a share or says on its
    /// own row why it doesn't — and `ScoreAttributionTests
    /// .testAnUnweightedRowAlwaysSaysWhy` enforces it over every registered
    /// model, so a bare figure here fails the build rather than shipping as a
    /// naked zero.
    public static func producedFigure(_ id: DerivedSeriesID, name: String,
                                      detail: String) -> ScoreFactor {
        ScoreFactor(source: .derived(id), name: name, weight: 0,
                    detail: detail, isModifiable: true)
    }
}

public extension MetricContribution {
    /// The same contribution as a factor, so one renderer draws both.
    ///
    /// Measured signals are all modifiable in the sense this flag means — the
    /// reader can go for a run or sleep longer. It marks the risk card's age and
    /// sex, which nothing else here produces.
    var factor: ScoreFactor {
        ScoreFactor(source: .metric(metric), name: metric.displayName,
                    weight: weight, detail: detail, isModifiable: true)
    }
}

public extension Array where Element == ScoreFactor {
    /// Heaviest first, ties broken by name so a tie is not a ranking.
    var byInfluence: [ScoreFactor] {
        sorted { $0.weight == $1.weight ? $0.name < $1.name : $0.weight > $1.weight }
    }

    var weighted: [ScoreFactor] { filter { $0.weight > 0 }.byInfluence }

    /// Shares renormalised to sum to 1, dropping anything at zero.
    ///
    /// Every producer here divides by its own total already; this is the guard
    /// that keeps a rounding drift or a dropped term from putting bars on screen
    /// that sum to 94%. Returns `[]` rather than dividing by zero.
    var normalised: [ScoreFactor] {
        let kept = filter { $0.weight > 0 }
        let total = kept.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return [] }
        return kept.map {
            ScoreFactor(source: $0.source, name: $0.name, weight: $0.weight / total,
                        detail: $0.detail, isModifiable: $0.isModifiable)
        }.byInfluence
    }

    /// One line naming the heaviest factor, for a collapsed section to preview.
    ///
    /// Refuses the superlative on a tie, for `[MetricContribution]
    /// .weightingPreview`'s reason: `byInfluence` breaks ties by name, so on a
    /// tie the first is not the largest and saying so would be false.
    var weightingPreview: String? {
        let ranked = weighted
        guard let top = ranked.first else { return nil }
        let share = Int((top.weight * 100).rounded())
        let magnitude = share == 0 ? "under 1%" : "\(share)%"
        guard ranked.count > 1 else {
            return "\(top.name) is the whole of it, at \(magnitude)."
        }
        let tied = ranked.filter { $0.weight == top.weight }.count
        if tied == ranked.count {
            return "All \(ranked.count) inputs count equally, at \(magnitude) each."
        }
        if tied > 1 {
            return "\(tied) inputs lead jointly at \(magnitude) each, "
                + "across \(ranked.count) in total."
        }
        return "\(top.name) carries the most, at \(magnitude) of "
            + "\(ranked.count) inputs."
    }
}
