import Foundation

/// The registry + evaluator for all insights. The app holds one of these,
/// feeds it canonical samples and the user profile, and renders the results.
///
/// Extensibility: register a new `InsightModel` here (or via `init(models:)`)
/// and it automatically participates in evaluation and grounding collection.
public struct InsightEngine: Sendable {
    public let models: [any InsightModel]

    public init(models: [any InsightModel]? = nil) {
        self.models = models ?? [
            ReadinessInsight(),
            VitalSignsInsight(),
            SleepQualityInsight(),
            HeartHealthInsight(),
            CardioFitnessInsight(),
            CardioTrajectoryInsight(),
            CardiovascularRiskInsight(preferredEngine: .combined),
            HeartAgeInsight(),
            BloodPressureInsight(),
            RestingHeartRateTrendInsight(),
            BodyCompositionInsight()
        ]
    }

    /// Evaluate every registered insight.
    public func evaluateAll(samples: [HealthMetricSample], profile: UserHealthProfile, now: Date = Date()) -> [InsightResult] {
        models.map { $0.evaluate(samples: samples, profile: profile, now: now) }
    }

    public func result(for id: InsightID, samples: [HealthMetricSample], profile: UserHealthProfile, now: Date = Date()) -> InsightResult? {
        models.first { $0.id == id }?.evaluate(samples: samples, profile: profile, now: now)
    }

    /// The union of grounding requirements the user should be prompted for,
    /// de-duplicated by kind and annotated with current status. Drives the
    /// "grounding data needed" section of the UI.
    public func outstandingGrounding(profile: UserHealthProfile, now: Date = Date()) -> [(requirement: GroundingRequirement, status: RequirementStatus)] {
        var byKind: [GroundingKind: (GroundingRequirement, RequirementStatus)] = [:]
        for model in models {
            for (req, status) in model.requirementStatuses(profile: profile, now: now) where status != .satisfied {
                // Keep the strongest (mandatory beats optional) requirement per kind.
                if let existing = byKind[req.kind] {
                    if req.isMandatory && !existing.0.isMandatory { byKind[req.kind] = (req, status) }
                } else {
                    byKind[req.kind] = (req, status)
                }
            }
        }
        return byKind.values
            .map { (requirement: $0.0, status: $0.1) }
            .sorted { lhs, rhs in
                if lhs.requirement.isMandatory != rhs.requirement.isMandatory {
                    return lhs.requirement.isMandatory
                }
                return lhs.requirement.kind.rawValue < rhs.requirement.kind.rawValue
            }
    }
}
