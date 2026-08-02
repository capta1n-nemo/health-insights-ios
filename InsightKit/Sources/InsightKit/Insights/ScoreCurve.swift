import Foundation

/// Turning a published band table into a score without putting a step in it.
///
/// ## Why this exists
///
/// Clinical guidance arrives as bands — the NSF panel says 7–9 hours is
/// recommended, 6–7 and 9–10 may be appropriate, outside that is not — and the
/// obvious way to score a band table is a `switch` over ranges. Several of these
/// were written that way, and each one put a **step** in a card's score:
///
/// ```swift
/// case 6..<7:   return 65      //  6.999 h → 65
/// case 7..<7.5: return 85      //  7.000 h → 85
/// ```
///
/// Twenty points for a wearable disagreeing with itself by four seconds. A
/// reader who sleeps about seven hours sees the Sleep card move several points
/// on consecutive nights and nothing in the app can explain why, because nothing
/// happened.
///
/// **The bands are real; the cliff at their edges is not.** A band edge is a
/// convention drawn through a continuum — nobody claims 6 h 59 m is materially
/// worse than 7 h 1 m — so the honest reading of a band table is the curve
/// through its breakpoints, which is what this builds.
///
/// ## What it does not fix
///
/// A genuinely discrete input — a stated goal, a category somebody chose, a
/// count of days of data — has no continuum to interpolate along and should stay
/// a `switch`. `ScoreContinuityTests` sweeps the curves that read measurements,
/// and only those.
public enum ScoreCurve {

    /// The piecewise-linear curve through `anchors`, flat outside them.
    ///
    /// Anchors are `(input, score)` pairs and **must be sorted by input**;
    /// unsorted anchors are a programming error rather than a runtime case, and
    /// `ScoreCurveTests` pins that every shipped curve is ordered.
    ///
    /// Flat rather than extrapolated beyond the ends, because extrapolating a
    /// clinical band table past its own evidence is how a score reaches −40.
    public static func through(_ anchors: [(input: Double, score: Double)],
                               at value: Double) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        if value <= first.input { return first.score }
        if value >= last.input { return last.score }
        for (low, high) in zip(anchors, anchors.dropFirst()) where value <= high.input {
            let span = high.input - low.input
            // Two anchors at one input would be a step by construction; take the
            // earlier score rather than dividing by zero.
            guard span > 0 else { return low.score }
            let progress = (value - low.input) / span
            return low.score + (high.score - low.score) * progress
        }
        return last.score
    }
}
