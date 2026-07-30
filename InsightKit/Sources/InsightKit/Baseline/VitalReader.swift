import Foundation

/// One metric reduced to what an insight should actually reason about: a day's
/// representative value, judged against a windowed personal baseline.
///
/// Every insight used to do this by hand as `series.last` plus
/// `Array(series.dropLast())`, which has four defects and had them everywhere:
///
/// 1. **The newest raw sample isn't the day's value.** For a continuously
///    sampled vital that's one minute of one afternoon — a reading taken during
///    a run reported as the day's heart rate.
/// 2. **The baseline was every reading ever taken**, so it adapts to a real
///    change far too slowly, and for high-frequency metrics it was actually the
///    last few *hours* — a baseline that moves with the thing it should be
///    detecting.
/// 3. **Duplicates counted twice.** The same ring arriving directly and through
///    Apple Health both survived, so inter-device disagreement rather than
///    physiology set the standard deviation, and departures never cleared it.
/// 4. **No reading was ever too old to use.** A months-old value was reported as
///    today's.
///
/// Vitals Check was fixed first; this is that fix made shared, so the rest of the
/// app stops repeating the mistake.
public struct VitalReading: Sendable, Equatable {
    public let metric: MetricType
    /// The day's representative value, using the metric's own bucketing rule
    /// (median for weight, sum for step-like totals, mean otherwise).
    public let value: Double
    /// Start of the day this value represents.
    public let date: Date
    /// Rolling baseline the value is judged against.
    public let baseline: Double?
    public let zScore: Double?
    /// Daily values behind the baseline, oldest first, excluding today.
    public let history: [Double]
    /// Which device's series this came from.
    public let sourceName: String
    /// Whether the reading is recent enough to describe now.
    public let isFresh: Bool

    /// Whether there was enough history to judge the value at all. A single
    /// reading is not a clean bill of health, and shouldn't read as one.
    public var isJudged: Bool { zScore != nil }
}

public enum VitalReader {

    /// Days of history a baseline is built from.
    public static let defaultWindowDays = 28
    /// Daily values needed before any z-score is offered.
    public static let defaultMinimumDays = 4
    /// How recent a reading must be to describe now.
    public static let defaultFreshness: TimeInterval = 36 * 3600

    /// The day's reading for one metric, or nil when the metric has no data.
    ///
    /// Returns the reading even when stale or unjudged — the caller decides what
    /// to do about that, because "we have a number but can't judge it" and "we
    /// have nothing" deserve different words.
    public static func reading(_ metric: MetricType,
                               from samples: [HealthMetricSample],
                               now: Date = Date(),
                               windowDays: Int = defaultWindowDays,
                               minimumDays: Int = defaultMinimumDays,
                               freshWithin: TimeInterval = defaultFreshness,
                               calendar: Calendar = .current) -> VitalReading? {
        // One series per physical device, de-duplicated: the same ring arriving
        // twice is one instrument.
        let breakdown = MultiSource.breakdown(metric, from: samples)
        guard !breakdown.sources.isEmpty else { return nil }

        var best: (reading: VitalReading, historyCount: Int)?
        for series in breakdown.sources {
            let daily = series.bucketed(by: .day, for: metric, calendar: calendar)
            guard let today = daily.last else { continue }

            let cutoff = today.date.addingTimeInterval(-Double(windowDays) * 86_400)
            let history = daily.dropLast().filter { $0.date >= cutoff }.map(\.value)
            let deviation = history.count >= minimumDays
                ? Baseline.deviation(latest: today.value, history: history)
                : nil

            let reading = VitalReading(
                metric: metric, value: today.value, date: today.date,
                baseline: deviation?.baseline, zScore: deviation?.zScore,
                history: history, sourceName: series.displayName,
                isFresh: now.timeIntervalSince(today.date) <= freshWithin)

            // The device with the most history has the best-established spread,
            // so its z is the one worth trusting. Pooling them instead — which is
            // what the old code did — let the gap between two miscalibrated
            // instruments become the variance.
            if best == nil || history.count > best!.historyCount {
                best = (reading, history.count)
            }
        }
        return best?.reading
    }

    /// Daily values for a metric over a window, oldest first, de-duplicated.
    ///
    /// For the things that need the series rather than a single day — sleep
    /// consistency being the night-to-night spread, for instance.
    public static func dailyValues(_ metric: MetricType,
                                   from samples: [HealthMetricSample],
                                   days: Int,
                                   now: Date = Date(),
                                   calendar: Calendar = .current) -> [Double] {
        let breakdown = MultiSource.breakdown(metric, from: samples)
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        // Merged across devices by day so two sources reporting the same night
        // contribute one value, not two.
        var byDay: [Date: [Double]] = [:]
        for series in breakdown.sources {
            for point in series.bucketed(by: .day, for: metric, calendar: calendar)
            where point.date >= cutoff {
                byDay[point.date, default: []].append(point.value)
            }
        }
        return byDay.keys.sorted().compactMap { day in
            byDay[day].flatMap { Baseline.mean($0) }
        }
    }
}
