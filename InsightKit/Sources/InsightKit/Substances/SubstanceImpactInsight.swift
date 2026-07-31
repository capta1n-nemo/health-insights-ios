import Foundation

/// Substance Impact as a first-class `InsightModel`.
///
/// It shipped as a free function on `SubstanceResponseAnalyzer` because its
/// input is the one thing the engine does not carry: the user's own log, which
/// lives in the app's store rather than in `samples`. The consequence was
/// invisible and total — everything applied "to every insight" iterates
/// `InsightEngine.models`, so score recording, `ScoreHistory` replay, the
/// cross-insight comparison chart and grounding collection all skipped this card
/// silently, for as long as it has existed.
///
/// The log is held here rather than passed to `evaluate`, so the protocol keeps
/// one shape for twelve models instead of growing a third overload for one of
/// them. `InsightEngine.withSubstanceLog(_:)` rebinds it.
public struct SubstanceImpactInsight: InsightModel {
    public let id: InsightID = .substanceImpact
    public let title = "Substance Impact"

    /// The user's log. Events after `now` are dropped inside `evaluate`:
    /// `ScoreHistory` replays a past day by handing the model that day as `now`,
    /// and a log entry from next week must not set last month's baseline.
    public let events: [SubstanceEvent]

    public init(events: [SubstanceEvent] = []) { self.events = events }

    /// The six signals the before/after comparison is measured on — the same
    /// list the analyser compares, so the detail screen's chart no longer needs
    /// the hand-written fallback it used to carry.
    public var candidateMetrics: [MetricType] { SubstanceResponseAnalyzer.comparedMetrics }

    /// None. This insight is built entirely from sensed data plus the user's own
    /// log; there is no fact it needs anyone to type in.
    public var requirements: [GroundingRequirement] { [] }

    /// The log itself. Without this override the derived default would return
    /// nothing — `requirements` is empty — and the one card whose whole input is
    /// something the user types would be the one card with no way to type it.
    /// It was reachable only from a toolbar button on a different tab.
    public var contributions: [ContributionRoute] { [.substanceLog] }

    /// `profile` is deliberately unused — no arm of this analysis is age- or
    /// sex-adjusted, and a reader should not have to work that out.
    public func evaluate(samples: [HealthMetricSample],
                         profile: UserHealthProfile, now: Date) -> InsightResult {
        SubstanceResponseAnalyzer.insightResult(
            events: events.filter { $0.timestamp <= now }, samples: samples, now: now)
    }
}
