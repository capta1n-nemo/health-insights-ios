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

        public init(fitnessAge: Double, vo2: Double, referenceForOwnAge: Double?,
                    yearsYounger: Double?, isCapped: Bool) {
            self.fitnessAge = fitnessAge
            self.vo2 = vo2
            self.referenceForOwnAge = referenceForOwnAge
            self.yearsYounger = yearsYounger
            self.isCapped = isCapped
        }
    }

    public static func evaluate(vo2: Double, sex: BiologicalSex,
                               chronologicalAge: Double? = nil) -> Output {
        let fittest = referenceVO2(age: youngestReportable, sex: sex)
        let least = referenceVO2(age: oldestReportable, sex: sex)

        var age = youngestReportable
        var capped = false
        if vo2 >= fittest {
            capped = vo2 > fittest
        } else if vo2 <= least {
            age = oldestReportable
            capped = vo2 < least
        } else {
            // Monotone decreasing between the bounds, so bisection converges.
            var low = youngestReportable
            var high = oldestReportable
            for _ in 0..<50 {
                let mid = (low + high) / 2
                if referenceVO2(age: mid, sex: sex) > vo2 { low = mid } else { high = mid }
            }
            age = (low + high) / 2
        }

        return Output(
            fitnessAge: age,
            vo2: vo2,
            referenceForOwnAge: chronologicalAge.map { referenceVO2(age: $0, sex: sex) },
            yearsYounger: chronologicalAge.map { $0 - age },
            isCapped: capped)
    }
}
