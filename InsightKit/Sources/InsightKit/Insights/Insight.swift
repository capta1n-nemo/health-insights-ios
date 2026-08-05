import Foundation

/// Stable identifiers for the insight cards.
///
/// **Nine, consolidated from seventeen.** The seventeen overlapped heavily —
/// three cards were built on VO₂max, three on sleep duration, and three did the
/// same "scan my signals against my own baseline" job — which made the app read
/// as a list of metrics rather than a set of answers.
///
/// The maths behind the merged cards was **kept**, as components: `VO2Trajectory`,
/// `FitnessAgeModel`, `HeartAgeModel`, `SleepDebtModel`,
/// `CircadianConsistencyModel`, `VitalSignsCheck`, `HealthWatchModel` and
/// `PeerStandingModel` all still exist with their tests. Only the card wrappers
/// and their identifiers went.
public enum InsightID: String, Codable, Sendable, CaseIterable {
    case cardiovascularRisk
    case heartHealth
    case bloodPressure
    case bodyComposition
    /// VO₂max level, its trajectory against the age norm, and fitness age.
    /// Absorbed Cardio Fitness, Fitness Trajectory and the fitness half of
    /// Heart & Fitness Age.
    case fitness
    /// Last night and the pattern behind it. Absorbed Sleep Quality, Sleep Debt
    /// and Sleep Regularity.
    case sleep
    /// The morning score, plus the vitals scan and the early warning that used
    /// to be two more cards reading the same signals.
    case readiness
    case energy
    case substanceImpact
    /// What the reader eats, against published guidance. Its own card rather
    /// than a section of Body Composition: the guidance it scores against is
    /// nothing to do with weight, and it applies to a reader who is not trying
    /// to change their weight at all.
    case nutrition
    /// How fast the reader's metabolism is running, from their own energy
    /// balance rather than a wearable's estimate.
    case metabolism
    /// Whether several vitals are leaning the illness way at once, graded
    /// against the reader's own symptom tags. Renders `HealthWatchModel`
    /// directly — the early warning got its own card back (roadmap #31)
    /// because *which signals moved* is more actionable than a score.
    case symptomRadar
    /// **How long the reader has been running hot** — sustained autonomic load
    /// over weeks, which is the one question about stress that Readiness and
    /// the symptom radar both leave unanswered.
    ///
    /// The reader asked for a stress card on 2026-08-03, and the roadmap note
    /// written then names the trap precisely: *"the risk is overlap — Readiness
    /// absorbed the vitals scan and the early warning for exactly this reason —
    /// so the honest version needs to answer a question Readiness does not,
    /// most likely sustained load rather than today."*
    ///
    /// So the three do not compete: Readiness answers *this morning*, the radar
    /// answers *is something acute converging right now*, and this answers *has
    /// this been going on for weeks*. Same signals, three different windows, and
    /// only the third can see a slow drift that never trips an acute threshold.
    case sustainedLoad
    /// **How you walk, against how you used to walk.**
    ///
    /// The one card here built on nothing the reader has to wear. Speed, step
    /// length and double support come off the phone in a pocket, and on the
    /// reader's own record that means 1,093 days and 91 of the last 90 — so it
    /// is also the only card with something to say on a week the ring spent on
    /// charge and the watch spent in a drawer.
    ///
    /// What it says that a number alone cannot: speed is step length times
    /// cadence, so when speed changes this card can name *which half moved*.
    /// Shorter steps at the same rhythm is a different story from the same
    /// steps taken less often, and no product in the field draws that line.
    case gait
    /// **The age this body's measurements are typical of** — this app's own,
    /// not a vendor's relayed.
    ///
    /// Refused twice on the grounds that a house biological age would be "a
    /// worse black box with a smaller *n*", and reversed by the reader on
    /// 2026-08-06: *"these sorts of things are the ENTIRE POINT OF THE APP."*
    /// They were right, and the refusal had assumed the only way to build one is
    /// the way Whoop and Oura build theirs — fit to a cohort nobody can see,
    /// print one number, publish no error.
    ///
    /// `BiologicalAgeModel` is built the other way round: nothing is fitted to
    /// anything, every marker is inverted through a published age norm, and the
    /// weights come from how precisely each marker can pin an age rather than
    /// from a choice. There is no tunable number in it. It costs a wide error
    /// bar — around a decade — and prints it, which is the trade every
    /// commercial version declines to make.
    case biologicalAge
    /// **How the last fortnight has gone, from behaviour rather than mood.**
    ///
    /// Refused after nine adversarial attacks, every one of which read
    /// HealthKit's mood surfaces and found zero rows. Reversed by the reader on
    /// 2026-08-06: *"I want a mental health card. Figure it out, creative
    /// licence + data science."* The answer to "there is no mood data" is this
    /// app's own thesis — use the data people already have — and behaviour is
    /// the most replicated correlate there is.
    ///
    /// ⚠️ The one attack that survives is a design constraint, not an objection:
    /// **this card never reassures.** Its top band means four numbers have not
    /// moved, and says so in those words.
    case mentalHealth
}

/// Where an insight belongs in the app's navigation. `daily` insights answer
/// "how am I *today*?" (shown on the Today tab); `trend` insights need analysis
/// over time and live on the Insights tab.
public enum InsightCadence: Sendable { case daily, trend }

public extension InsightID {
    var cadence: InsightCadence {
        switch self {
        // Energy is a *right now* number and changes hour to hour. Readiness is
        // a claim about today. Sleep now leads with last night — which is why it
        // moved here: its ancestor `circadianConsistency` was a trend card
        // because a fortnight's spread is not a statement about today, but the
        // merged card opens with how you actually slept, and that is the first
        // thing anyone checks in the morning.
        // The radar is a claim about today for the same reason Readiness is.
        //
        // **Substance Impact moved to `trend` on 2026-08-05, at the reader's
        // instruction:** *"that isn't something I'm just worried about day to
        // day, it's something I want to look at more long term."* It was daily
        // because a dose is a thing that happened today — but the card does not
        // report the dose, it reports the *response*, which is measured by
        // comparing windows across a 90-day pool and only becomes trustworthy
        // once several exposures agree. A number built from months of history
        // answering "what does this do to me" is a trend card by the definition
        // at the top of this file, whatever the cadence of the events under it.
        case .readiness, .sleep, .energy, .symptomRadar:
            return .daily
        // VO₂max, body composition, risk and blood pressure all move over
        // months. `default:` is deliberate rather than exhaustive here — a new
        // insight is far more often a trend than a daily one.
        default: return .trend
        }
    }
}

/// How much confidence to attach to a computed insight, so the UI can be honest
/// about uncertainty rather than presenting every number as a hard fact.
public enum InsightConfidence: String, Codable, Sendable {
    case high        // validated model with all required inputs present & fresh
    case moderate    // validated model but some inputs estimated / stale
    case low         // sparse data
    case experimental // research-grade estimate (e.g. cuffless BP)
}

/// A requirement an insight has for a grounding fact it cannot sense.
public struct GroundingRequirement: Sendable, Hashable, Identifiable {
    public let kind: GroundingKind
    public let isMandatory: Bool
    /// User-facing reason we ask, e.g. "Needed to estimate 10-year heart risk".
    public let rationale: String

    public var id: GroundingKind { kind }

    public init(kind: GroundingKind, isMandatory: Bool, rationale: String) {
        self.kind = kind
        self.isMandatory = isMandatory
        self.rationale = rationale
    }
}

/// The status of a requirement given the current profile.
public enum RequirementStatus: Sendable, Equatable {
    case satisfied
    case stale        // present but past its freshness window
    case missing
}

/// One line of "what's driving this".
///
/// Carries whether the line is worth looking at, so a detail screen can lead
/// with the departures and keep the reassuring majority one tap away. Vitals
/// Check is why: it scans seventeen signals, and on an ordinary day sixteen of
/// them say "normal" — which buries the one that doesn't.
public struct InsightDriver: Sendable, Equatable {
    public let text: String
    /// `true` for something to look at, `false` for the reassuring background.
    ///
    /// `nil` means this insight doesn't draw the distinction — and that is not
    /// the same as "everything is routine". A screen must show an unclassified
    /// list in full rather than hiding all of it behind a disclosure, so the
    /// two cases have to stay distinguishable.
    public let isNotable: Bool?

    public init(text: String, isNotable: Bool? = nil) {
        self.text = text
        self.isNotable = isNotable
    }
}

/// A finished insight ready for display.
public struct InsightResult: Sendable, Equatable {
    public let id: InsightID
    public let title: String
    /// Primary number for the headline (e.g. risk %). nil if not computable yet.
    public let primaryValue: Double?
    /// Preformatted headline, e.g. "5.2%" or "Good".
    public let headline: String
    /// A second figure the card is also about, shown beneath the headline.
    ///
    /// **Added because one number was hiding another.** Blood Pressure is
    /// badged "Experimental" and led with a *cuff* reading — the badge and the
    /// number disagreed, the reading carried no date, and the experimental
    /// estimate the badge referred to could never reach the headline at all.
    /// The reader asked to see both: what was actually measured and when,
    /// alongside what the model currently thinks.
    ///
    /// Optional and defaulted, so no other card changes. A card with one number
    /// leaves it nil rather than inventing a second.
    public let subheadline: String?
    /// A 0…100 score for dial rendering, when meaningful.
    public let score: Double?
    public let confidence: InsightConfidence
    /// Short, plain-language explanation of what drove the result.
    public let explanation: String
    /// Machine-readable drivers, for detail views and the on-device summariser.
    ///
    /// Notable lines first, where an insight distinguishes them — the card
    /// preview on Today shows `drivers.first`, so the ordering is load-bearing.
    public let driverLines: [InsightDriver]
    /// The same lines as plain text, which is all most callers want.
    public var drivers: [String] { driverLines.map(\.text) }

    /// Whether a tab should list this card at all.
    ///
    /// **One rule for both tabs.** Today filtered on `primaryValue != nil` and
    /// Insights filtered on nothing, so an ungrounded trend insight showed an
    /// "Add your details" placeholder while an ungrounded daily one silently
    /// vanished — two answers to one question.
    ///
    /// The rule is not "whichever tab was right": it is that a card with no
    /// number earns its place only when there is something the user can *do*
    /// about it. Simply dropping Today's filter would have put up to seven dead
    /// cards on a fresh install, because the daily insights declare no grounding
    /// requirements at all — their empty state is "connect a wearable", which a
    /// placeholder card cannot help with.
    public var isWorthShowing: Bool {
        primaryValue != nil || !unmetRequirements.isEmpty || isAwaitingTodaysData
            || invitesInput
    }
    /// A daily card that has real history and is only waiting for today's sync.
    ///
    /// Readiness and Energy score *today*, so a morning on which the wearable
    /// hasn't synced yet leaves them with no number — which is not the same
    /// state as never having recorded a night, and it used to be rendered as
    /// exactly that: both cards vanished from Today until the sync landed, and
    /// their empty copy told a user with months of nights to "record a night".
    /// This flag keeps the card on the tab with a waiting headline instead. A
    /// genuinely fresh install (no history at all) leaves it false, so the
    /// original rule — a card with no number earns its place only when there is
    /// something the user can do — still holds there.
    public let isAwaitingTodaysData: Bool
    /// Grounding requirements still unmet, so the UI can prompt.
    public let unmetRequirements: [GroundingRequirement]
    /// The card has no number **and** the thing it is missing is something the
    /// reader can hand it — a food log, a reading, a scan.
    ///
    /// **This exists because two cards shipped invisible on 2026-08-03.**
    /// Nutrition and Metabolism both need logged intake, and with none they
    /// returned `notReady`, which sets no `primaryValue` and no unmet
    /// requirement — so `isWorthShowing` filtered them off the Insights tab
    /// entirely. A card the reader cannot see cannot tell them what it needs,
    /// and the user found two features missing from a build that contained
    /// them.
    ///
    /// The rule below was already right — a card with no number earns its place
    /// only when there is something the reader can *do* — and grounding facts
    /// were simply not the only kind of "something". An input is the other.
    public let invitesInput: Bool
    /// The metrics that actually fed this result, emitted by the scoring code as
    /// it builds each component. This is what the detail screen charts, so it
    /// cannot drift from the maths the way a hand-written list does.
    public let contributors: [MetricContribution]
    /// How the number is formed, so "How this is weighted" can say what a share
    /// *means* rather than reporting its absence. See `ScoreWeighting`.
    public let weighting: ScoreWeighting
    /// Inputs with a share of the number that are **not** metrics — a date of
    /// birth, a blood test, a decaying substance load. Empty on every card whose
    /// inputs are all sensed, which is most of them.
    ///
    /// Renormalised *together* with `contributors`' weights rather than beside
    /// them: they are shares of one number, and two lists each summing to 1
    /// would put two 100%s on one card.
    public let otherFactors: [ScoreFactor]

    /// Every input carrying a share, metric-backed or not, heaviest first.
    ///
    /// The single thing the weighting section draws. Building it here rather
    /// than in the view is what stops the two lists being merged differently on
    /// two screens — and the app target has no test target.
    public var weightedFactors: [ScoreFactor] {
        (contributors.weighted.map(\.factor) + otherFactors).normalised
    }

    /// Signals the card charts but deliberately does not score.
    ///
    /// Named rather than counted, because a count cannot answer the question a
    /// reader actually has — *which* of these moved my number and which did the
    /// app merely draw. Fitness reports five of them, Readiness eleven.
    public var unscoredContributors: [MetricContribution] {
        contributors.filter { $0.weight == 0 }
            .sorted { $0.metric.displayName < $1.metric.displayName }
    }

    /// Everything the card named that carries no share of the number: signals it
    /// charts without scoring, and factors already at or better than the value
    /// they are measured against.
    ///
    /// The second kind is why this is not simply `unscoredContributors`. "Your
    /// cholesterol is carrying none of your risk" and "we didn't look at your
    /// cholesterol" are opposite statements, and a row missing says the second.
    public var unweightedFactors: [ScoreFactor] {
        (unscoredContributors.map(\.factor) + otherFactors.filter { $0.weight <= 0 })
            .sorted { $0.name < $1.name }
    }

    /// The same result with more lines, notable ones still first.
    ///
    /// Exists for the merged cards: Readiness computes its score, then appends
    /// what the vitals scan and the early warning found. Re-partitioning here
    /// rather than at the call site is what keeps the ordering invariant — the
    /// card preview shows `drivers.first`, so a routine line arriving after a
    /// notable one must not be able to reach the front.
    public func appending(driverLines extra: [InsightDriver]) -> InsightResult {
        let all = driverLines + extra
        return InsightResult(
            id: id, title: title, primaryValue: primaryValue, headline: headline,
            score: score, confidence: confidence, explanation: explanation,
            driverLines: all.filter { $0.isNotable == true }
                + all.filter { $0.isNotable != true },
            unmetRequirements: unmetRequirements, contributors: contributors,
            weighting: weighting, otherFactors: otherFactors,
            isAwaitingTodaysData: isAwaitingTodaysData, invitesInput: invitesInput)
    }

    /// For insights that don't distinguish notable lines from routine ones.
    public init(
        id: InsightID,
        title: String,
        primaryValue: Double?,
        headline: String,
        subheadline: String? = nil,
        score: Double?,
        confidence: InsightConfidence,
        explanation: String,
        drivers: [String],
        unmetRequirements: [GroundingRequirement],
        contributors: [MetricContribution] = [],
        weighting: ScoreWeighting = .unstated,
        otherFactors: [ScoreFactor] = [],
        isAwaitingTodaysData: Bool = false,
        invitesInput: Bool = false
    ) {
        self.init(id: id, title: title, primaryValue: primaryValue, headline: headline,
                  subheadline: subheadline,
                  score: score, confidence: confidence, explanation: explanation,
                  driverLines: drivers.map { InsightDriver(text: $0) },
                  unmetRequirements: unmetRequirements, contributors: contributors,
                  weighting: weighting, otherFactors: otherFactors,
                  isAwaitingTodaysData: isAwaitingTodaysData, invitesInput: invitesInput)
    }

    public init(
        id: InsightID,
        title: String,
        primaryValue: Double?,
        headline: String,
        subheadline: String? = nil,
        score: Double?,
        confidence: InsightConfidence,
        explanation: String,
        driverLines: [InsightDriver],
        unmetRequirements: [GroundingRequirement],
        contributors: [MetricContribution] = [],
        weighting: ScoreWeighting = .unstated,
        otherFactors: [ScoreFactor] = [],
        isAwaitingTodaysData: Bool = false,
        invitesInput: Bool = false
    ) {
        self.invitesInput = invitesInput
        self.subheadline = subheadline
        self.id = id
        self.title = title
        self.primaryValue = primaryValue
        self.headline = headline
        self.score = score
        self.confidence = confidence
        self.explanation = explanation
        self.driverLines = driverLines
        self.unmetRequirements = unmetRequirements
        self.contributors = contributors
        self.weighting = weighting
        self.otherFactors = otherFactors
        self.isAwaitingTodaysData = isAwaitingTodaysData
    }
}

/// The contract every insight implements. Insights are pure functions of the
/// canonical samples + the user profile, which is exactly what makes them
/// unit-testable and portable. Adding a new insight = add a type conforming here
/// and register it in `InsightEngine`.
public protocol InsightModel: Sendable {
    var id: InsightID { get }
    var title: String { get }
    /// Everything this insight might ask the user for.
    var requirements: [GroundingRequirement] { get }
    /// Every metric this insight can read, whether or not there is data for it
    /// today. The superset of `InsightResult.contributors`, used to show a
    /// "no data yet" row rather than silently omitting an input the user could
    /// start collecting.
    ///
    /// Deliberately has **no default implementation**: a new insight must say
    /// what it reads or it won't compile, the same way `MetricType.presentation`
    /// refuses to let a new metric go uncategorised.
    var candidateMetrics: [MetricType] { get }
    /// What the user can view and add for this insight — see
    /// `ContributionRoute`, which also carries the default implementation.
    ///
    /// **A protocol requirement, not merely an extension member.** Callers hold
    /// `any InsightModel`, and a member that existed only in an extension would
    /// dispatch statically — every model would silently get the default and the
    /// two overrides below would never run.
    var contributions: [ContributionRoute] { get }
    /// Compute the result from current data. Never throws — degrades gracefully
    /// to a low-confidence / not-yet-available result and reports what's missing.
    func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult

    /// The same, for insights that also read device-raised events.
    ///
    /// Has a default implementation that ignores the events, so adding this did
    /// not touch the other ten models. Only Vitals Check overrides it — an
    /// irregular-rhythm notification is a judgement Apple already made, with no
    /// unit and no baseline, so it could not be modelled as a `MetricType`
    /// without inventing both.
    func evaluate(samples: [HealthMetricSample], events: [VitalEvent],
                  profile: UserHealthProfile, now: Date) -> InsightResult
}

public extension InsightModel {
    /// Most insights read measurements only.
    func evaluate(samples: [HealthMetricSample], events: [VitalEvent],
                  profile: UserHealthProfile, now: Date) -> InsightResult {
        evaluate(samples: samples, profile: profile, now: now)
    }

    /// Status of each requirement against the profile — shared helper.
    func requirementStatuses(profile: UserHealthProfile, now: Date) -> [(GroundingRequirement, RequirementStatus)] {
        requirements.map { req in
            guard let input = profile.input(req.kind) else { return (req, .missing) }
            return (req, input.isFresh(asOf: now) ? .satisfied : .stale)
        }
    }

    func unmetRequirements(profile: UserHealthProfile, now: Date) -> [GroundingRequirement] {
        requirementStatuses(profile: profile, now: now).compactMap { req, status in
            status == .satisfied ? nil : req
        }
    }
}
