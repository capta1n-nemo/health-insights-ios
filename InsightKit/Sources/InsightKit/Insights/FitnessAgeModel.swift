import Foundation

// Two age-framings of data the app already holds. A percentage is easy to shrug
// off; "your heart is running eight years ahead of you" is not. Both numbers are
// derived from models already in the app — nothing new is invented here, the
// existing outputs are re-expressed on the axis people actually feel: years.
//
// Split out of `HeartAge.swift`, which carried two independent models and their
// shared card in 713 lines, following the `CardiovascularRiskModel` /
// `CardiovascularRiskInsight` precedent already in the tree.

/// The age at which your VO₂max would be the reference value for your sex.
///
/// This inverts the *same* age/sex cardiorespiratory-fitness norms
/// `HeartHealthScore.vo2Score` already scores against, rather than importing a
/// separate published fitness-age regression (e.g. HUNT), so the two numbers can
/// never disagree about what "average for your age" means.
public enum FitnessAgeModel {

    /// Reporting bounds. Outside them the norm table is extrapolation, so the
    /// result is clamped and flagged rather than quietly extended.
    public static let youngestReportable: Double = 20
    public static let oldestReportable: Double = 75

    /// The norm table's reference VO₂max at the midpoint of each of its age
    /// bands. `HeartHealthScore` uses the bands; interpolating between their
    /// midpoints gives the same curve as a continuous, invertible line.
    static func anchors(for sex: BiologicalSex) -> [(age: Double, vo2: Double)] {
        switch sex {
        case .male:   return [(25, 48), (35, 44), (45, 40), (55, 36), (65, 32)]
        case .female: return [(25, 41), (35, 38), (45, 34), (55, 31), (65, 28)]
        }
    }

    /// Reference VO₂max for an age: piecewise-linear between the anchors,
    /// continuing the adjacent slope beyond the first and last of them.
    ///
    /// Strictly decreasing everywhere, which is what makes it invertible.
    public static func referenceVO2(age: Double, sex: BiologicalSex) -> Double {
        let points = anchors(for: sex)
        if age <= points[0].age {
            let slope = (points[1].vo2 - points[0].vo2) / (points[1].age - points[0].age)
            return points[0].vo2 + slope * (age - points[0].age)
        }
        for index in 1..<points.count where age <= points[index].age {
            let low = points[index - 1]
            let high = points[index]
            let fraction = (age - low.age) / (high.age - low.age)
            return low.vo2 + (high.vo2 - low.vo2) * fraction
        }
        let last = points[points.count - 1]
        let previous = points[points.count - 2]
        let slope = (last.vo2 - previous.vo2) / (last.age - previous.age)
        return last.vo2 + slope * (age - last.age)
    }

    public struct Output: Sendable, Equatable {
        public let fitnessAge: Double
        public let vo2: Double
        /// The reference VO₂max for the person's real age, when it is known.
        public let referenceForOwnAge: Double?
        /// Chronological age − fitness age: positive means fitter than your years.
        public let yearsYounger: Double?
        /// True when the VO₂max sits outside the reportable band and the age was
        /// clamped to it ("20 or younger", "75 or older").
        public let isCapped: Bool

        /// **The fitness age at each end of the VO₂max's own error bar** — the
        /// honest width of this answer, and added because the point estimate on
        /// its own was misleading (backlog Q3).
        ///
        /// The reader, 2026-08-06, on a VO₂max of 30 reading as a 68-year-old's
        /// fitness: *"honestly doesn't seem right."* Their instinct is picking
        /// up something real, and it is **not** an arithmetic error — 68 is what
        /// the norm table says. It is these two things:
        ///
        /// 1. **A wrist estimate is being inverted through a laboratory-measured
        ///    norm table.** Every figure in `anchors` comes from people breathing
        ///    into a mask on a treadmill. The input comes from heart rate during
        ///    an outdoor walk. Comparing them is defensible only with the error
        ///    attached.
        /// 2. **The curve is flat, so the inversion is violent.** Reference VO₂max
        ///    falls about 0.4 mL/kg·min per year, so the ±3.5 the wrist estimate
        ///    carries is **±9 years** — and near the bottom of the table it is
        ///    worse still, because the clamp at `oldestReportable` swallows the
        ///    upper end. A single number cannot carry that and stay honest.
        ///
        /// So the range is the answer and the point is the midpoint of it. Where
        /// it spans more than a decade the card must lead with the span.
        public let ageRange: ClosedRange<Double>?

        /// Whether the reader's VO₂max sits below the norm table's lowest
        /// anchor, where the reference line is the adjacent slope continued
        /// rather than anything anybody measured.
        public let isExtrapolated: Bool

        public init(fitnessAge: Double, vo2: Double, referenceForOwnAge: Double?,
                    yearsYounger: Double?, isCapped: Bool,
                    ageRange: ClosedRange<Double>? = nil,
                    isExtrapolated: Bool = false) {
            self.fitnessAge = fitnessAge
            self.vo2 = vo2
            self.referenceForOwnAge = referenceForOwnAge
            self.yearsYounger = yearsYounger
            self.isCapped = isCapped
            self.ageRange = ageRange
            self.isExtrapolated = isExtrapolated
        }

        /// The span in years, when there is one.
        public var rangeWidth: Double? {
            ageRange.map { $0.upperBound - $0.lowerBound }
        }
    }

    /// Invert the norm line: the age whose reference VO₂max is this one.
    ///
    /// Split out of `evaluate` so the error bar can be inverted through exactly
    /// the same path as the point estimate. Two inversions that disagree about
    /// the clamp would print a range that does not contain its own midpoint.
    static func solve(vo2: Double, sex: BiologicalSex) -> (age: Double, capped: Bool) {
        let fittest = referenceVO2(age: youngestReportable, sex: sex)
        let least = referenceVO2(age: oldestReportable, sex: sex)

        if vo2 >= fittest { return (youngestReportable, vo2 > fittest) }
        if vo2 <= least { return (oldestReportable, vo2 < least) }

        // Monotone decreasing between the bounds, so bisection converges.
        var low = youngestReportable
        var high = oldestReportable
        for _ in 0..<50 {
            let mid = (low + high) / 2
            if referenceVO2(age: mid, sex: sex) > vo2 { low = mid } else { high = mid }
        }
        return ((low + high) / 2, false)
    }

    public static func evaluate(vo2: Double, sex: BiologicalSex,
                                chronologicalAge: Double? = nil,
                                vo2Error: Double = AgeComparison.vo2EstimateError) -> Output {
        let solved = solve(vo2: vo2, sex: sex)

        // A *higher* VO₂max is a *younger* age, so the fit end of the error bar
        // gives the lower bound. Getting this the wrong way round builds an
        // invalid `ClosedRange` and traps at runtime, which is why it is written
        // out rather than assumed.
        let younger = solve(vo2: vo2 + vo2Error, sex: sex).age
        let older = solve(vo2: vo2 - vo2Error, sex: sex).age

        // Below the table's last anchor the reference line is the previous
        // slope continued into territory the norms do not cover.
        let lowestAnchor = anchors(for: sex).last?.vo2 ?? 0

        return Output(
            fitnessAge: solved.age,
            vo2: vo2,
            referenceForOwnAge: chronologicalAge.map { referenceVO2(age: $0, sex: sex) },
            yearsYounger: chronologicalAge.map { $0 - solved.age },
            isCapped: solved.capped,
            ageRange: Swift.min(younger, older)...Swift.max(younger, older),
            isExtrapolated: vo2 < lowestAnchor)
    }
}
