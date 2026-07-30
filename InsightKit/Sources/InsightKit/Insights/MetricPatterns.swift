import Foundation

/// What kind of relationship a pattern describes.
public enum PatternKind: String, Sendable, Equatable {
    /// Two signals heading in opposite directions over the window. This is the
    /// "you're sleeping more but your blood oxygen is falling" observation.
    case divergence
    /// Two signals that rise and fall together day to day.
    case coMovement
    /// A metric that tracks the score itself — what is actually moving the
    /// number, for this person, over this window.
    case driver
}

/// One readable observation drawn from the overlay's series.
public struct MetricPattern: Sendable, Equatable, Identifiable {
    public let kind: PatternKind
    public let a: MetricType
    /// nil for a `driver` pattern, where the second series is the score.
    public let b: MetricType?
    /// Pearson r for co-movement and driver patterns; the difference in weekly
    /// slopes (in SD/week) for a divergence.
    public let statistic: Double
    /// Paired days the statistic rests on.
    public let sampleCount: Int
    public let sentence: String

    public var id: String { "\(kind.rawValue)-\(a.rawValue)-\(b?.rawValue ?? "score")" }

    public init(kind: PatternKind, a: MetricType, b: MetricType?,
                statistic: Double, sampleCount: Int, sentence: String) {
        self.kind = kind
        self.a = a
        self.b = b
        self.statistic = statistic
        self.sampleCount = sampleCount
        self.sentence = sentence
    }
}

/// Reads the overlay's own series against each other and says what it finds.
///
/// Deliberately conservative, in the same spirit as the rest of the app: a
/// relationship is only reported when there are enough paired days to mean
/// anything and the effect is big enough to see. Every sentence is phrased as an
/// association, never a cause — "tracked with", not "caused". Correlation on
/// this much data is a prompt to look, not a finding.
public enum PatternFinder {

    /// Below this many paired days, nothing is reported at all.
    public static let defaultMinimumPairs = 14
    /// |r| below this is noise on a series this short.
    public static let defaultMinimumMagnitude = 0.3
    /// A weekly slope smaller than this (in SD/week) is not a direction.
    public static let minimumSlope = 0.05

    public static func patterns(in series: [NormalizedSeries],
                                against score: [ScorePoint]? = nil,
                                minimumPairs: Int = defaultMinimumPairs,
                                minimumMagnitude: Double = defaultMinimumMagnitude,
                                limit: Int = 4,
                                calendar: Calendar = .current) -> [MetricPattern] {
        var found: [MetricPattern] = []

        // Divergence: opposite directions over the window. Reported first
        // because it's the observation that isn't visible any other way — each
        // metric alone looks unremarkable.
        for i in series.indices {
            for j in series.indices where j > i {
                let left = series[i]
                let right = series[j]
                // Two readings of the same measurement always diverge when one
                // is the inverse of the other. That is arithmetic, not a
                // finding — and it had no guard here at all.
                guard !left.metric.sharesMeasurementBasis(with: right.metric) else { continue }
                guard let s1 = left.trendPerWeek, let s2 = right.trendPerWeek,
                      abs(s1) >= minimumSlope, abs(s2) >= minimumSlope,
                      s1.sign != s2.sign else { continue }
                let pairs = Swift.min(left.points.count, right.points.count)
                guard pairs >= minimumPairs else { continue }
                let rising = s1 > 0 ? left : right
                let falling = s1 > 0 ? right : left
                found.append(MetricPattern(
                    kind: .divergence, a: rising.metric, b: falling.metric,
                    statistic: abs(s1 - s2), sampleCount: pairs,
                    sentence: divergenceSentence(rising: rising, falling: falling)))
            }
        }

        // Co-movement between two metrics — but never between two readings of
        // the same measurement. "On days when heart rate changes, resting heart
        // rate tends to as well (r = 0.75)" is a fact about how resting heart
        // rate is derived, and it crowded genuine cross-system observations off
        // the card. Family alone wasn't enough: HRV and resting heart rate sit
        // in different families and still come off the same interval stream.
        for i in series.indices {
            for j in series.indices where j > i {
                guard !series[i].metric.sharesMeasurementBasis(with: series[j].metric)
                else { continue }
                let paired = align(series[i], series[j], calendar: calendar)
                guard paired.count >= minimumPairs,
                      let r = Baseline.correlation(x: paired.map { $0.0 }, y: paired.map { $0.1 }),
                      abs(r) >= minimumMagnitude else { continue }
                found.append(MetricPattern(
                    kind: .coMovement, a: series[i].metric, b: series[j].metric,
                    statistic: r, sampleCount: paired.count,
                    sentence: coMovementSentence(series[i].metric, series[j].metric,
                                                 r: r, n: paired.count)))
            }
        }

        // What moves the score itself. Only the strongest is reported: the
        // sentence claims a superlative ("more closely than the others"), and
        // emitting it per metric put two signals on screen both claiming to be
        // the closest, with the same r.
        if let score, score.count >= minimumPairs {
            let scoreSeries = score.map { (calendar.startOfDay(for: $0.date), $0.score) }
            var best: (metric: MetricType, r: Double, n: Int)?
            for one in series {
                let paired = align(one, to: scoreSeries, calendar: calendar)
                guard paired.count >= minimumPairs,
                      let r = Baseline.correlation(x: paired.map { $0.0 }, y: paired.map { $0.1 }),
                      abs(r) >= minimumMagnitude else { continue }
                if best == nil || abs(r) > abs(best!.r) {
                    best = (one.metric, r, paired.count)
                }
            }
            if let best {
                found.append(MetricPattern(
                    kind: .driver, a: best.metric, b: nil,
                    statistic: best.r, sampleCount: best.n,
                    sentence: driverSentence(best.metric, r: best.r, n: best.n)))
            }
        }

        // Strongest first, and only a handful: a wall of weak correlations reads
        // as noise and buries the one observation worth acting on.
        return Array(found.sorted { abs($0.statistic) > abs($1.statistic) }.prefix(limit))
    }

    // MARK: - Pairing

    /// Day-aligned value pairs. Two metrics rarely have readings on exactly the
    /// same days, and correlating unaligned series is meaningless.
    static func align(_ a: NormalizedSeries, _ b: NormalizedSeries,
                      calendar: Calendar = .current) -> [(Double, Double)] {
        var byDay: [Date: Double] = [:]
        for point in b.points { byDay[calendar.startOfDay(for: point.date)] = point.z }
        return a.points.compactMap { point in
            byDay[calendar.startOfDay(for: point.date)].map { (point.z, $0) }
        }
    }

    static func align(_ a: NormalizedSeries, to other: [(Date, Double)],
                      calendar: Calendar = .current) -> [(Double, Double)] {
        var byDay: [Date: Double] = [:]
        for (date, value) in other { byDay[calendar.startOfDay(for: date)] = value }
        return a.points.compactMap { point in
            byDay[calendar.startOfDay(for: point.date)].map { (point.z, $0) }
        }
    }

    // MARK: - Wording

    static func divergenceSentence(rising: NormalizedSeries, falling: NormalizedSeries) -> String {
        let up = changePhrase(rising, rising: true)
        let down = changePhrase(falling, rising: false)
        return "\(rising.metric.displayName) has been \(up) while \(falling.metric.inSentence) has been \(down)."
    }

    /// Describes a trend in the metric's own units, because "+0.4 SD a week"
    /// means nothing to anyone. `baseline * sd`-free: the raw points already
    /// carry real values, so the phrasing is drawn from those.
    static func changePhrase(_ series: NormalizedSeries, rising: Bool) -> String {
        let direction = rising ? "rising" : "falling"
        guard let start = series.points.first?.raw,
              let end = series.points.last?.raw else { return direction }
        let delta = abs(end - start)
        let unit = series.metric.unit
        let formatted = unit.isEmpty
            ? String(format: "%.1f", delta)
            : String(format: "%.1f %@", delta, unit)
        return "\(direction) (about \(formatted) across the window)"
    }

    static func coMovementSentence(_ a: MetricType, _ b: MetricType, r: Double, n: Int) -> String {
        let together = r > 0 ? "rise and fall together" : "move in opposite directions"
        return "On days when \(a.inSentence) changes, \(b.inSentence) tends to as well — they \(together) (r = \(formatR(r)) over \(n) days). That's an association, not a cause."
    }

    static func driverSentence(_ metric: MetricType, r: Double, n: Int) -> String {
        let direction = r > 0 ? "higher" : "lower"
        return "\(metric.displayName) tracks this score more closely than any other signal — \(direction) \(metric.inSentence) days tend to be better ones (r = \(formatR(r)) over \(n) days)."
    }

    static func formatR(_ r: Double) -> String {
        String(format: "%.2f", r)
    }
}
