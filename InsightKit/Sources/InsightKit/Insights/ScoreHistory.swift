import Foundation

/// One day's score for one insight.
public struct ScorePoint: Sendable, Equatable, Identifiable {
    public let date: Date
    public let score: Double
    public let confidence: InsightConfidence
    /// How many metrics fed this day's score. A readiness score built from two
    /// signals is a different animal from one built from six, and the chart
    /// should be able to say so rather than drawing both as the same line.
    public let contributorCount: Int

    public var id: Date { date }

    public init(date: Date, score: Double, confidence: InsightConfidence, contributorCount: Int) {
        self.date = date
        self.score = score
        self.confidence = confidence
        self.contributorCount = contributorCount
    }
}

/// Rebuilds an insight's score for each day in the recent past.
///
/// Nothing has ever persisted a score, so a chart of "readiness over time" would
/// otherwise start empty and take months to become useful. Insights are pure
/// functions of `(samples, profile, now)`, so the history can simply be
/// recomputed — the same model, run against the data as it stood on each day.
///
/// The mechanism is **truncation, not the `now` argument**. `ReadinessScore`
/// (and others) read `history.last` and ignore `now` entirely, so replaying a
/// past day means handing the model only the samples that existed by then. That
/// is the contract this type enforces, and `ScoreHistoryTests` pins it.
///
/// Replayed early points legitimately used a thinner baseline than today's does,
/// because that is what the user would have been shown at the time. The scoring
/// maths is deliberately left alone here.
public enum ScoreHistory {

    /// Days with fewer than this many contributing metrics are skipped rather
    /// than plotted: a "score" resting on one signal is noise with a number on it.
    public static let minimumContributors = 2

    public static func replay(model: any InsightModel,
                              samples: [HealthMetricSample],
                              events: [VitalEvent] = [],
                              profile: UserHealthProfile,
                              days: Int = 90,
                              calendar: Calendar = .current,
                              now: Date = Date()) -> [ScorePoint] {
        guard days > 0 else { return [] }

        // Pre-filter to what this model can actually read. This is what makes
        // the replay affordable: a readiness replay drops a six-figure sample
        // set to a few thousand daily-cadence readings, and every day of the
        // loop pays for the difference.
        let relevant = Set(model.candidateMetrics)
        guard !relevant.isEmpty else { return [] }
        let sorted = samples.filter { relevant.contains($0.type) }
            .sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        var points: [ScorePoint] = []
        points.reserveCapacity(days)

        let today = calendar.startOfDay(for: now)
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let dayStart = calendar.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            // Never replay past the real present: a partial day would report a
            // score the user hasn't earned yet.
            let asOf = min(dayEnd, now)
            guard asOf > dayStart else { continue }

            let cut = firstIndex(in: sorted, atOrAfter: asOf)
            guard cut > 0 else { continue }

            let visible = Array(sorted[..<cut])
            // A cheap pre-check on the samples, so a day with nothing to say
            // never pays for a full evaluation.
            let present = Set(visible.map(\.type)).count
            guard present >= minimumContributors else { continue }

            // Events are truncated on the same contract as samples: a
            // notification raised after the day being replayed cannot have
            // affected the score the user was shown on it.
            let result = model.evaluate(samples: visible,
                                        events: events.filter { $0.date < asOf },
                                        profile: profile, now: asOf)
            guard let score = result.score else { continue }

            // Having the data isn't the same as having *used* it: readiness needs
            // four nights before its HRV component fires at all, so early days
            // can hold three metrics and still be scored off sleep alone. Where
            // the model reports its components, that count is the honest one.
            let used = result.contributors.isEmpty ? present : result.contributors.count
            guard used >= minimumContributors else { continue }

            points.append(ScorePoint(date: dayStart, score: score,
                                     confidence: result.confidence,
                                     contributorCount: used))
        }
        return points
    }

    /// Index of the first sample starting at or after `date`, or `endIndex`.
    /// Same technique as `SourceSeries.restricted(to:)` and for the same reason:
    /// re-scanning the whole history once per replayed day is the difference
    /// between a chart that opens and one that stalls.
    static func firstIndex(in samples: [HealthMetricSample], atOrAfter date: Date) -> Int {
        var low = 0
        var high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].start < date { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// Replayed history with stored points laid over it.
    ///
    /// A stored point is what the app actually told the user that day, so it
    /// wins over a recomputation — which would otherwise quietly rewrite the
    /// past whenever a scoring weight changed.
    public static func merging(replayed: [ScorePoint],
                               stored: [ScorePoint],
                               calendar: Calendar = .current) -> [ScorePoint] {
        var byDay: [Date: ScorePoint] = [:]
        for point in replayed { byDay[calendar.startOfDay(for: point.date)] = point }
        for point in stored { byDay[calendar.startOfDay(for: point.date)] = point }
        return byDay.values.sorted { $0.date < $1.date }
    }
}

public extension Array where Element == ScorePoint {
    /// Least-squares change per week, in score points. Used for the one-line
    /// trend sentence above the chart — a slope over the window rather than
    /// last-minus-first, which one bad night can swing.
    var trendPerWeek: Double? {
        guard count >= 4, let first = self.first?.date else { return nil }
        let x = map { $0.date.timeIntervalSince(first) / 86_400 }
        let y = map(\.score)
        guard let fit = Baseline.linearRegression(x: x, y: y) else { return nil }
        return fit.slope * 7
    }
}
