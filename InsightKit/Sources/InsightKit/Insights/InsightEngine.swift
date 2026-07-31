import Foundation

/// The registry + evaluator for all insights. The app holds one of these,
/// feeds it canonical samples and the user profile, and renders the results.
///
/// Extensibility: register a new `InsightModel` here (or via `init(models:)`)
/// and it automatically participates in evaluation and grounding collection.
public struct InsightEngine: Sendable {
    public let models: [any InsightModel]

    public init(models: [any InsightModel]? = nil) {
        // Nine, consolidated from seventeen — see `InsightID`. The daily block
        // first, in the order Today shows them.
        self.models = models ?? [
            ReadinessInsight(),
            SleepInsight(),
            EnergyInsight(),
            // Bound to an empty log; the app rebinds it on every recompute via
            // `withSubstanceLog(_:)`. Registering it here is what finally puts it
            // in front of everything that iterates `models` — score recording,
            // score replay, the comparison chart — all of which skipped it
            // silently while it was built by a free function.
            SubstanceImpactInsight(),
            HeartHealthInsight(),
            FitnessInsight(),
            CardiovascularRiskInsight(preferredEngine: .combined),
            BloodPressureInsight(),
            BodyCompositionInsight()
        ]
    }

    /// The same registry with the substance model bound to a log.
    ///
    /// Idempotent — it *replaces* the substance model rather than appending one —
    /// so a caller may apply it on every recompute without compounding. A caller
    /// that injected its own `SubstanceImpactInsight` will have it rebound.
    public func withSubstanceLog(_ events: [SubstanceEvent]) -> InsightEngine {
        InsightEngine(models: models.map { model in
            model is SubstanceImpactInsight ? SubstanceImpactInsight(events: events) : model
        })
    }

    /// Evaluate every registered insight.
    ///
    /// `events` are device-raised notifications rather than measurements; models
    /// that don't read them get the defaulted overload and are unaffected.
    public func evaluateAll(samples: [HealthMetricSample], events: [VitalEvent] = [],
                            profile: UserHealthProfile, now: Date = Date()) -> [InsightResult] {
        // Every model below is handed the same array, and many read the same
        // metrics — resting heart rate is read by seven of them. The memo makes
        // the second and later reads of a metric dictionary hits instead of
        // another filter-deduplicate-bucket pass over the whole history. It is
        // scoped to this call, so it cannot go stale against changed data.
        MultiSource.withMemo(for: samples) {
            models.map { $0.evaluate(samples: samples, events: events, profile: profile, now: now) }
        }
    }

    public func result(for id: InsightID, samples: [HealthMetricSample], profile: UserHealthProfile, now: Date = Date()) -> InsightResult? {
        MultiSource.withMemo(for: samples) {
            models.first { $0.id == id }?.evaluate(samples: samples, profile: profile, now: now)
        }
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
