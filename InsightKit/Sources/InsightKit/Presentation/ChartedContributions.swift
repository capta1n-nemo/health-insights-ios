import Foundation

/// The inputs a card charts, and whether the model actually reported them.
///
/// ## Why the flag matters
///
/// A detail screen charts `InsightResult.contributors`. Where a model reports
/// none, the screen falls back to its *declared* inputs so the card shows a
/// chart rather than an empty box — and those stand-ins are built with
/// `weight: 0` and `higherIsBetter: nil`, because there is nothing to put there.
///
/// Those two values are also perfectly legitimate *findings*. Fitness reports
/// `dayStrain` at weight 0 on purpose: a real signal worth charting with no
/// validated 0–100 curve behind it. Sleep reports a temperature deviation with
/// `higherIsBetter: nil` on purpose: neither direction is the good one.
///
/// So the same zero means "we decided this doesn't count" in one card and "we
/// don't know" in another, and a legend that reads them as facts prints two
/// claims nobody made. Substance Impact is the live case — it reports one
/// contributor per measured effect of a logged event, so before the first log
/// it reports none, and every row of its legend would announce itself as
/// unscored with no preferred direction.
///
/// The absence is therefore carried alongside the values rather than encoded
/// *in* them, and `areReported` is the only thing a caller has to check.
public struct ChartedContributions: Sendable, Equatable {

    public let contributions: [MetricContribution]

    /// `false` when these are stand-ins for a model that reported nothing, in
    /// which case every `weight` and every `higherIsBetter` in them is an
    /// absence rather than an answer.
    public let areReported: Bool

    public init(contributions: [MetricContribution], areReported: Bool) {
        self.contributions = contributions
        self.areReported = areReported
    }

    public var metrics: [MetricType] { contributions.metrics }
    public var isEmpty: Bool { contributions.isEmpty }

    /// What the model said, or its declared inputs where it said nothing.
    ///
    /// `declaredInputs` is an autoclosure because reaching an insight's
    /// `candidateMetrics` means finding the model in the engine, and the common
    /// path never needs it.
    public static func resolve(
        reported: [MetricContribution],
        declaredInputs: @autoclosure () -> [MetricType]
    ) -> ChartedContributions {
        guard reported.isEmpty else {
            return ChartedContributions(contributions: reported, areReported: true)
        }
        return ChartedContributions(
            contributions: declaredInputs().map {
                MetricContribution(metric: $0, higherIsBetter: nil, weight: 0, detail: "")
            },
            areReported: false)
    }
}
