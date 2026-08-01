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

    /// The ones that actually count toward the score.
    ///
    /// A weight of zero is a deliberate statement — `dayStrain` is charted and
    /// not scored, because no validated 0–100 curve for it exists here — so
    /// these are filtered out of the weighting picture rather than drawn as
    /// zero-width bars, which would say they were weighed and found irrelevant.
    var weighted: [MetricContribution] { filter { $0.weight > 0 }.byInfluence }

    /// One line naming the heaviest signal, for a collapsed "How this is
    /// weighted" to show in place of its bars.
    ///
    /// `nil` when nothing is weighted — the caller has a `SectionPlaceholder`
    /// for that, and this returning a cheerful sentence about a 0% share is the
    /// failure mode worth designing out.
    ///
    /// Says "carries the most" only when it genuinely does. `byInfluence`
    /// breaks ties by name, so on a two-way tie the first is not the largest,
    /// and claiming a superlative there would be false — a Readiness card with
    /// six equal components is a real shape, not a contrived one.
    var weightingPreview: String? {
        let ranked = weighted
        guard let top = ranked.first else { return nil }
        let share = Int((top.weight * 100).rounded())
        let magnitude = share == 0 ? "under 1%" : "\(share)%"
        guard ranked.count > 1 else {
            return "\(top.metric.displayName) is the whole of it, at \(magnitude)."
        }
        let tied = ranked.filter { $0.weight == top.weight }.count
        if tied == ranked.count {
            return "All \(ranked.count) signals count equally, at \(magnitude) each."
        }
        if tied > 1 {
            return "\(tied) signals lead jointly at \(magnitude) each, "
                + "across \(ranked.count) in total."
        }
        return "\(top.metric.displayName) carries the most, at \(magnitude) "
            + "of \(ranked.count) signals."
    }
}
