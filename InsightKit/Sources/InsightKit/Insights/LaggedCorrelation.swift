import Foundation

/// Whether a signal *leads* a score, rather than merely moving with it.
///
/// This is the one thing the Today tab structurally cannot do. Today compares
/// today with yesterday, so every relationship it can see is same-day: sleep was
/// short and readiness is low, both facts about this morning. Shifting one series
/// against the other asks a different and more useful question — does last
/// night's sleep predict *tomorrow's* readiness, for this person?
///
/// A lag is only reported when it genuinely beats same-day, because most of the
/// time it doesn't, and a lagged correlation that is merely a weaker echo of a
/// same-day one is not a finding.
public struct LaggedRelationship: Sendable, Equatable, Identifiable {
    public let metric: MetricType
    /// Days the metric leads the score by. Always ≥ 1 here.
    public let lag: Int
    public let r: Double
    /// The same-day correlation it had to beat.
    public let sameDayR: Double
    public let sampleCount: Int
    public let sentence: String

    public var id: String { "\(metric.rawValue)-\(lag)" }
}

public enum LagFinder {

    /// Lags worth testing. Beyond about three days any physiological story is
    /// speculative, and testing more lags on the same data mostly buys noise —
    /// every extra lag is another chance for chance to clear the bar.
    public static let maximumLag = 3
    /// A lagged relationship must beat same-day by this much to be reported.
    /// Without it, a signal that simply persists across days would surface a
    /// lagged "finding" that is just its own same-day correlation, blurred.
    public static let requiredImprovement = 0.12

    public static func relationships(between series: [NormalizedSeries],
                                     and score: [ScorePoint],
                                     minimumPairs: Int = PatternFinder.defaultMinimumPairs,
                                     minimumMagnitude: Double = PatternFinder.defaultMinimumMagnitude,
                                     limit: Int = 3,
                                     calendar: Calendar = .current) -> [LaggedRelationship] {
        guard score.count >= minimumPairs else { return [] }
        var scoreByDay: [Date: Double] = [:]
        for point in score { scoreByDay[calendar.startOfDay(for: point.date)] = point.score }

        var found: [LaggedRelationship] = []
        for one in series {
            guard let sameDay = correlation(one, scoreByDay, lag: 0,
                                            minimumPairs: minimumPairs, calendar: calendar)
            else { continue }

            var best: (lag: Int, r: Double, n: Int)?
            for lag in 1...maximumLag {
                guard let candidate = correlation(one, scoreByDay, lag: lag,
                                                  minimumPairs: minimumPairs, calendar: calendar)
                else { continue }
                if best == nil || abs(candidate.r) > abs(best!.r) {
                    best = (lag, candidate.r, candidate.n)
                }
            }

            guard let best,
                  abs(best.r) >= minimumMagnitude,
                  abs(best.r) - abs(sameDay.r) >= requiredImprovement else { continue }

            found.append(LaggedRelationship(
                metric: one.metric, lag: best.lag, r: best.r, sameDayR: sameDay.r,
                sampleCount: best.n,
                sentence: sentence(metric: one.metric, lag: best.lag, r: best.r, n: best.n)))
        }
        return Array(found.sorted { abs($0.r) > abs($1.r) }.prefix(limit))
    }

    /// Correlate the metric on day *d* against the score on day *d + lag*.
    static func correlation(_ series: NormalizedSeries,
                            _ scoreByDay: [Date: Double],
                            lag: Int,
                            minimumPairs: Int,
                            calendar: Calendar) -> (r: Double, n: Int)? {
        var xs: [Double] = []
        var ys: [Double] = []
        for point in series.points {
            let day = calendar.startOfDay(for: point.date)
            guard let target = calendar.date(byAdding: .day, value: lag, to: day),
                  let score = scoreByDay[target] else { continue }
            xs.append(point.z)
            ys.append(score)
        }
        guard xs.count >= minimumPairs, let r = Baseline.correlation(x: xs, y: ys) else {
            return nil
        }
        return (r, xs.count)
    }

    static func sentence(metric: MetricType, lag: Int, r: Double, n: Int) -> String {
        let when = lag == 1 ? "the next day" : "\(lag) days later"
        let direction = r > 0 ? "better" : "worse"
        return "Your \(metric.inSentence) looks like a leading signal: higher days are followed by a \(direction) score \(when) more often than not (r = \(String(format: "%.2f", r)) over \(n) days). Same-day it explains less, which is what makes the lag interesting — though on \(n) days this is a lead to watch, not a finding."
    }
}
