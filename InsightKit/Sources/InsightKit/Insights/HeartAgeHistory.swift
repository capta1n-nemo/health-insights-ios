import Foundation

/// The two ages on one day, beside the real one.
public struct AgePoint: Sendable, Equatable, Identifiable {
    public let date: Date
    /// Your actual age that day. Carried per point rather than assumed constant
    /// because over a long window it isn't.
    public let chronological: Double
    public let heart: Double?
    public let fitness: Double?

    public var id: Date { date }

    public init(date: Date, chronological: Double, heart: Double?, fitness: Double?) {
        self.date = date
        self.chronological = chronological
        self.heart = heart
        self.fitness = fitness
    }

    /// Years the leading age runs ahead of your real one. Positive is bad news.
    public var excessYears: Double? {
        (heart ?? fitness).map { $0 - chronological }
    }
}

/// Heart age and fitness age over time.
///
/// The Heart & Fitness Age card had two numbers and a dial, which answers "where
/// am I" and nothing about "which way is this going" — and the direction is the
/// part you can act on. A heart age of 46 means one thing after a year at 50 and
/// something else entirely after a year at 42.
///
/// Rebuilt the same way `ScoreHistory` rebuilds a score: by **truncation**, not
/// by passing a past `now`. `HeartAgeAnalyser.analyse` reads the latest value of
/// each series, so replaying a past day means handing it only the samples that
/// existed by then. Grounding facts (cholesterol, smoking, a cuff reading) are
/// taken as they stand today — the profile has no history to replay, and saying
/// so here is better than pretending the reconstruction is exact.
public enum HeartAgeHistory {

    /// Both ages move in steps as slow inputs land, so a daily replay would draw
    /// a staircase of duplicates. Weekly is the honest resolution.
    public static let strideDays = 7

    public static func replay(samples: [HealthMetricSample],
                              profile: UserHealthProfile,
                              days: Int = 365,
                              calendar: Calendar = .current,
                              now: Date = Date()) -> [AgePoint] {
        guard days > 0 else { return [] }
        let insight = HeartAgeAnalyser()
        let relevant = Set(insight.candidateMetrics)
        let sorted = samples.filter { relevant.contains($0.type) }
            .sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        let today = calendar.startOfDay(for: now)
        var points: [AgePoint] = []
        for offset in stride(from: days - 1, through: 0, by: -strideDays) {
            guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let asOf = Swift.min(dayEnd, now)
            guard asOf > dayStart else { continue }

            let cut = ScoreHistory.firstIndex(in: sorted, atOrAfter: asOf)
            guard cut > 0 else { continue }

            let analysis = insight.analyse(samples: Array(sorted[..<cut]),
                                           profile: profile, now: asOf)
            guard let age = analysis.chronologicalAge,
                  analysis.heart != nil || analysis.fitness != nil else { continue }
            points.append(AgePoint(date: dayStart, chronological: age,
                                   heart: analysis.heart?.heartAge,
                                   fitness: analysis.fitness?.fitnessAge))
        }
        return points
    }
}

public extension Array where Element == AgePoint {

    /// Change in the leading age per year, over the points present.
    ///
    /// Reported against the *pace of time itself*: your chronological age climbs
    /// one year per year no matter what, so a heart age climbing at 1.0 is
    /// standing still and one climbing at 2.0 is losing a year every year. A
    /// bare slope would read as good news at 0.9.
    var yearsPerYear: Double? {
        let usable = compactMap { point -> (Double, Double)? in
            (point.heart ?? point.fitness).map { (point.date.timeIntervalSince1970, $0) }
        }
        guard usable.count >= 3 else { return nil }
        let fit = Baseline.linearRegression(x: usable.map { $0.0 }, y: usable.map { $0.1 })
        return fit.map { $0.slope * 365.25 * 86_400 }
    }
}
