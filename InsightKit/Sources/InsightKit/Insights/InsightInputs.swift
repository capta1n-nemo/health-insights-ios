import Foundation

/// One metric that actually fed a computed insight, with enough context for a
/// chart legend to explain it without re-deriving anything.
///
/// This exists because the detail screen used to chart a single metric chosen by
/// a hand-maintained switch in the app target, which drifted from what the score
/// really used. A contribution is emitted *by the scoring code itself*, at the
/// point the component is built, so a new input to a score becomes a new line on
/// the chart with no second edit anywhere.
public struct MetricContribution: Sendable, Hashable {
    public let metric: MetricType
    /// Which direction is the good one. `nil` means neither is: skin-temperature
    /// deviation is best near zero, so calling "up" good or bad would be wrong.
    public let higherIsBetter: Bool?
    /// Share of the final score, **after** the model renormalises over the
    /// components it actually had data for — so the legend can say "40% of this"
    /// and be telling the truth. Zero for insights that don't weight (a vitals
    /// scan reports outliers rather than averaging them).
    public let weight: Double
    /// The value as the model already formatted it, e.g. "48 ms".
    public let detail: String

    public init(metric: MetricType, higherIsBetter: Bool?, weight: Double, detail: String) {
        self.metric = metric
        self.higherIsBetter = higherIsBetter
        self.weight = weight
        self.detail = detail
    }
}

public extension InsightDriver {
    /// A line from a weighted component, notable when it is the reason the score
    /// isn't higher.
    ///
    /// One rule across every composite — readiness, sleep, heart health — so the
    /// detail cards agree about what "worth seeing" means instead of each
    /// inventing a threshold. 65 is where the app's own bands stop saying
    /// "good".
    static func component(_ text: String, score: Double,
                          concernBelow: Double = 65) -> InsightDriver {
        InsightDriver(text: text, isNotable: score < concernBelow)
    }

    /// A line that is always worth seeing.
    static func notable(_ text: String) -> InsightDriver {
        InsightDriver(text: text, isNotable: true)
    }

    /// A line that is context rather than a finding.
    static func routine(_ text: String) -> InsightDriver {
        InsightDriver(text: text, isNotable: false)
    }
}

public extension Array where Element == MetricContribution {
    /// Heaviest first, so a legend and an overlay agree on which line matters.
    var byInfluence: [MetricContribution] {
        sorted {
            $0.weight == $1.weight
                ? $0.metric.displayName < $1.metric.displayName
                : $0.weight > $1.weight
        }
    }

    var metrics: [MetricType] { map(\.metric) }
}
