import Foundation

/// **Why is this score what it is.**
///
/// Backlog #38 / section S2 — described in the competitive research as the
/// single highest-value idea in the whole scan, and as Oura's number one
/// unfixable complaint. The reader placed it themselves on 2026-08-06: *"I don't
/// want this to be a card, I want this to be part of the deep dive under the
/// insight web."*
///
/// ## Why it could not be built before today
///
/// A `MetricContribution` carried a **share** and no sub-score, and
/// `ScoreBlend.blend` computed every component's own 0–100 and then dropped all
/// of them the moment it had the weighted mean. So the app could say "resting
/// heart rate is 22% of your Readiness" and could not say *"and it scored 41,
/// while everything else scored 80"* — which is the only version of the question
/// anyone actually asks. The numeric fields on `MetricContribution` are the fix;
/// this is what reads them.
///
/// ## The counterfactual, and why it is arithmetic rather than a re-run
///
/// A weighted mean is linear in each of its terms, so
///
///     Δscore = (target − componentScore) × weight
///
/// is **exact** for `.weightedAverage`, with nothing simulated and nothing
/// re-evaluated. That is worth insisting on: the obvious implementation — re-run
/// the model with one input replaced — would be slower, would need a fabricated
/// input value, and would silently include every interaction the model has,
/// producing a number nobody could check.
///
/// ## ⚠️ Where it refuses
///
/// **Only `.weightedAverage` gets a counterfactual**, and every other weighting
/// gets a stated refusal instead of a plausible number:
///
/// - `.equation` — SCORE2 and ASCVD are non-linear in every input, and
///   `RiskAttribution` already answers this properly by *re-running the
///   published equation*, which is the only honest way. Deferred to it.
/// - `.fit` — the blood-pressure regression's inputs move together, so holding
///   one at its mean is not a state this reader can be in.
/// - `.worstOffender` / `.accumulative` — the score is not a weighted mean of
///   its parts at all, so the arithmetic above does not apply.
/// - `.singleMeasure` / `.measurement` — there is one input; "what if it were
///   different" is just "what if the reading were different".
/// - `.unstated` — the card has not said how its number is formed, which is
///   exactly the case where inventing a decomposition would be worst.
///
/// A refusal that names its reason is the product here as much as the number is.
public enum ScoreDecomposition {

    /// One component, with everything needed to say what it did to the score.
    public struct Row: Sendable, Equatable, Identifiable {
        public let metric: MetricType
        public let label: String
        /// Share of the final number, already renormalised by the model.
        public let weight: Double
        /// This component's own 0–100, where the model reports one.
        public let componentScore: Double?
        public let value: Double?
        public let baseline: Double?
        public let z: Double?
        public let detail: String
        public let higherIsBetter: Bool?
        /// Points the whole score would gain if this component were perfect.
        /// Nil where the model reports no sub-score.
        public let headroom: Double?

        public var id: String { metric.rawValue }

        /// Whether this row is worth leading with: it has both a meaningful
        /// share and somewhere to go.
        public var isLever: Bool { (headroom ?? 0) >= 1 }
    }

    public struct Output: Sendable, Equatable {
        public let insight: InsightID
        public let title: String
        public let score: Double
        public let weighting: ScoreWeighting
        /// Weighted components, largest headroom first — *not* largest weight.
        /// The reader is asking what to do, and the biggest share is often
        /// already at its ceiling.
        public let rows: [Row]
        /// Rows the card charts and does not score, each carrying its stated
        /// reason in `detail`.
        public let unscored: [Row]
        /// Set when this weighting does not support a counterfactual, and says
        /// which and why.
        public let refusal: String?

        /// The single sentence the section leads with.
        public var headline: String {
            if let refusal { return refusal }
            guard let best = rows.first, let headroom = best.headroom, headroom >= 1 else {
                return "Every part of this is at or near its ceiling. There is no single thing here to move."
            }
            return String(format: "%@ is holding this back the most — %.0f of the %.0f points missing from 100 are its.",
                          best.label, headroom, 100 - score)
        }

        /// How much of the gap to 100 the listed levers actually account for.
        ///
        /// **Printed, because it is usually less than all of it** and a reader
        /// adding the rows up will notice. The remainder is rounding plus any
        /// component whose model reports no sub-score.
        public var accountedFor: Double? {
            let sum = rows.compactMap(\.headroom).reduce(0, +)
            return sum > 0 ? sum : nil
        }
    }

    /// Build the decomposition for one scored result.
    ///
    /// Nil when the card has no score at all — there is nothing to explain.
    public static func evaluate(_ result: InsightResult) -> Output? {
        guard let score = result.score else { return nil }

        let refusal = refusalReason(for: result.weighting)
        let supportsCounterfactual = refusal == nil

        func row(_ contribution: MetricContribution) -> Row {
            Row(metric: contribution.metric,
                label: contribution.metric.displayName,
                weight: contribution.weight,
                componentScore: contribution.componentScore,
                value: contribution.value,
                baseline: contribution.baseline,
                z: contribution.z,
                detail: contribution.detail,
                higherIsBetter: contribution.higherIsBetter,
                headroom: supportsCounterfactual ? contribution.counterfactual() : nil)
        }

        let weighted = result.contributors.filter { $0.weight > 0 }.map(row)
        let unscored = result.contributors.filter { $0.weight <= 0 }.map(row)

        return Output(
            insight: result.id, title: result.title, score: score,
            weighting: result.weighting,
            // Largest headroom first, falling back to weight where no model
            // reports a sub-score, so the ordering never collapses to arbitrary.
            rows: weighted.sorted {
                ($0.headroom ?? -1, $0.weight) > ($1.headroom ?? -1, $1.weight)
            },
            unscored: unscored.sorted { $0.label < $1.label },
            refusal: refusal)
    }

    /// Why this weighting cannot be decomposed arithmetically, or nil when it
    /// can.
    ///
    /// Exhaustive on purpose. A new `ScoreWeighting` case must decide whether it
    /// is linear in its parts, and a wrong default here would print a confident
    /// counterfactual for a model that does not support one.
    public static func refusalReason(for weighting: ScoreWeighting) -> String? {
        switch weighting {
        case .weightedAverage:
            return nil
        case .equation(let name):
            return "This score comes out of \(name), which is not a weighted average — its inputs multiply rather than add, so \"what if this one were better\" cannot be worked out on paper. The card's own attribution section answers it properly, by running the published equation again with one input changed."
        case .fit(let what):
            return "This score comes from \(what). The inputs of a fit move together, so holding one at its average describes a person who does not exist — a counterfactual here would be a confident number about nothing."
        case .singleMeasure(let against):
            return "There is one measurement behind this, judged against \(against). \"What if a different part were better\" has no other part to ask about."
        case .measurement(let what):
            return "This is \(what) — a reading rather than a blend, so there is nothing to decompose."
        case .worstOffender:
            return "This score is set by whichever signal is furthest out of range, not by an average of all of them. Improving anything other than the worst one would not move it at all, which is the point of scoring it that way."
        case .accumulative:
            return "This score accumulates over time rather than averaging what is true today, so a single component has no fixed share to hand back."
        case .unstated:
            return "This card has not stated how its number is formed, so anything here would be guesswork. That is a gap in the card, not in your data."
        }
    }
}
