import Foundation

/// Stable identifiers for the insights shipped in the MVP.
public enum InsightID: String, Codable, Sendable, CaseIterable {
    case cardiovascularRisk
    case heartHealth
    case heartAge
    case bloodPressure
    case readiness
    case substanceImpact
    case sleepQuality
    case cardioFitness
    case cardioTrajectory
    case bodyComposition
    case restingHeartRateTrend
    case vitalSigns
    case energy
    case healthWatch
    case sleepDebt
    case peerStanding
}

/// Where an insight belongs in the app's navigation. `daily` insights answer
/// "how am I *today*?" (shown on the Today tab); `trend` insights need analysis
/// over time and live on the Insights tab.
public enum InsightCadence: Sendable { case daily, trend }

public extension InsightID {
    var cadence: InsightCadence {
        switch self {
        case .readiness, .substanceImpact, .sleepQuality, .vitalSigns,
             // Energy is a *right now* number and changes hour to hour; Health
             // Watch and Sleep Debt are both claims about today.
             .energy, .healthWatch, .sleepDebt:
            return .daily
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
    /// Grounding requirements still unmet, so the UI can prompt.
    public let unmetRequirements: [GroundingRequirement]
    /// The metrics that actually fed this result, emitted by the scoring code as
    /// it builds each component. This is what the detail screen charts, so it
    /// cannot drift from the maths the way a hand-written list does.
    public let contributors: [MetricContribution]

    /// For insights that don't distinguish notable lines from routine ones.
    public init(
        id: InsightID,
        title: String,
        primaryValue: Double?,
        headline: String,
        score: Double?,
        confidence: InsightConfidence,
        explanation: String,
        drivers: [String],
        unmetRequirements: [GroundingRequirement],
        contributors: [MetricContribution] = []
    ) {
        self.init(id: id, title: title, primaryValue: primaryValue, headline: headline,
                  score: score, confidence: confidence, explanation: explanation,
                  driverLines: drivers.map { InsightDriver(text: $0) },
                  unmetRequirements: unmetRequirements, contributors: contributors)
    }

    public init(
        id: InsightID,
        title: String,
        primaryValue: Double?,
        headline: String,
        score: Double?,
        confidence: InsightConfidence,
        explanation: String,
        driverLines: [InsightDriver],
        unmetRequirements: [GroundingRequirement],
        contributors: [MetricContribution] = []
    ) {
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
