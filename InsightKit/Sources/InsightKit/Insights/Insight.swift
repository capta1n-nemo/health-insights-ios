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
}

/// Where an insight belongs in the app's navigation. `daily` insights answer
/// "how am I *today*?" (shown on the Today tab); `trend` insights need analysis
/// over time and live on the Insights tab.
public enum InsightCadence: Sendable { case daily, trend }

public extension InsightID {
    var cadence: InsightCadence {
        switch self {
        case .readiness, .substanceImpact, .sleepQuality, .vitalSigns: return .daily
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
    public let drivers: [String]
    /// Grounding requirements still unmet, so the UI can prompt.
    public let unmetRequirements: [GroundingRequirement]

    public init(
        id: InsightID,
        title: String,
        primaryValue: Double?,
        headline: String,
        score: Double?,
        confidence: InsightConfidence,
        explanation: String,
        drivers: [String],
        unmetRequirements: [GroundingRequirement]
    ) {
        self.id = id
        self.title = title
        self.primaryValue = primaryValue
        self.headline = headline
        self.score = score
        self.confidence = confidence
        self.explanation = explanation
        self.drivers = drivers
        self.unmetRequirements = unmetRequirements
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
    /// Compute the result from current data. Never throws — degrades gracefully
    /// to a low-confidence / not-yet-available result and reports what's missing.
    func evaluate(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date) -> InsightResult
}

public extension InsightModel {
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
