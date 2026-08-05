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
                               gapDays: Int = 0,
                               calendar: Calendar = .current) -> VitalReading? {
        // One series per physical device, de-duplicated: the same ring arriving
        // twice is one instrument.
        let breakdown = MultiSource.breakdown(metric, from: samples)
        guard !breakdown.sources.isEmpty else { return nil }
        let buckets = dailyBuckets(metric, breakdown: breakdown, from: samples, calendar: calendar)

        var best: (reading: VitalReading, historyCount: Int)?
        for (series, daily) in zip(breakdown.sources, buckets) {
            guard let today = daily.last else { continue }

            // **A gap, so the last few days cannot set the bar they are judged
            // against.** `dropLast()` alone removes only *today*, which is what
            // let a departure age into its own baseline — the reader caught it
            // twice on 2026-08-05 ("still the same value.. but no longer in
            // danger?"). Robust spread removed the dominant term; this removes
            // the rest of it, and it is the same device `HealthWatchModel` has
            // always had (`referenceGapDays`).
            //
            // Zero by default: a caller that wants "how does today compare with
            // the recent past" — a trend, a chart's own mean — is asking a
            // different question and must not silently lose its newest days.
            let earlier = daily.dropLast()
            func window(gap: Int) -> [Double] {
                let gapEnd = today.date.addingTimeInterval(-Double(gap) * 86_400)
                let cutoff = gapEnd.addingTimeInterval(-Double(windowDays) * 86_400)
                return earlier.filter { $0.date >= cutoff && $0.date < gapEnd }.map(\.value)
            }
            // **The gap is affordable, not mandatory.** It costs `gapDays` of
            // history, and a reader who has just started has none to spare —
            // holding the line strictly would leave them with no judgement at
            // all for their first week and a half, which is worse than the
            // weakness the gap exists to remove. So: take the gap when the
            // window can still clear its own minimum without those days, and
            // fall back to today's behaviour when it cannot.
            let gapped = window(gap: gapDays)
            let history = gapped.count >= minimumDays ? gapped : window(gap: 0)
            let deviation = history.count >= minimumDays
                ? Baseline.deviation(latest: today.value, history: history)
                : nil

            let reading = VitalReading(
                metric: metric, value: today.value, date: today.date,
                baseline: deviation?.baseline, zScore: deviation?.zScore,
                history: history, sourceName: series.displayName,
                isFresh: now.timeIntervalSince(today.date) <= freshWithin)

            // Freshness decides first, and then the tie-break depends on which
            // side of it we're on.
            //
            // History alone used to be the whole rule, and it had this backwards
            // at the top: a device that stopped reporting a week ago has the
            // *most* established baseline and the *weakest* claim on describing
            // today. A user with a quiet ring and an active watch got the ring's
            // stale value, correctly labelled `isFresh: false` — and callers that
            // drop a stale component, as Readiness does, lost the signal
            // altogether rather than reading it off the watch. `VitalSignsCheck`
            // had always dropped stale sources *before* choosing; this is that
            // rule, made shared.
            //
            // Among fresh sources, the best-established spread wins: its z is the
            // one worth trusting, and that half of the old rule was right.
            // Among stale ones, the most recent wins instead — the caller's
            // honest sentence is "last measured N days ago", and N has to be the
            // true minimum, not whichever quiet device happens to have the
            // longest memory.
            //
            // The winner is always one series, never a blend: pooling them is
            // what let the gap between two miscalibrated instruments become the
            // variance, so nothing ever cleared a threshold.
            let wins: Bool = {
                guard let best else { return true }
                if reading.isFresh != best.reading.isFresh { return reading.isFresh }
                if reading.isFresh {
                    if history.count != best.historyCount { return history.count > best.historyCount }
                    return reading.date > best.reading.date
                }
                if reading.date != best.reading.date { return reading.date > best.reading.date }
                return history.count > best.historyCount
            }()
            if wins { best = (reading, history.count) }
        }
        return best?.reading
    }

    /// One day's representative value, with the day it represents.
    public struct DailyValue: Sendable, Equatable {
        public let date: Date
        public let value: Double

        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// Daily values with their dates, oldest first, merged across devices.
    ///
    /// `dailyValues` is this with the dates thrown away. Anything fitting a line
    /// needs them: a series with a twenty-week silence in the middle is not
    /// evenly spaced, and regressing it against `0, 1, 2, …` does not produce a
    /// slightly wrong slope — it produces a different quantity. Measured on a
    /// real VO₂max series with such a gap: 160 mL/kg·min per year against a true
    /// 10.1. Nothing at the type level catches that, which is why this exists.
    public static func dailySeries(_ metric: MetricType,
                                   from samples: [HealthMetricSample],
                                   days: Int? = nil,
                                   now: Date = Date(),
                                   calendar: Calendar = .current) -> [DailyValue] {
        let breakdown = MultiSource.breakdown(metric, from: samples)
        let cutoff = days.map { now.addingTimeInterval(-Double($0) * 86_400) } ?? .distantPast
        var byDay: [Date: [Double]] = [:]
        for daily in dailyBuckets(metric, breakdown: breakdown, from: samples, calendar: calendar) {
            for point in daily where point.date >= cutoff {
                byDay[point.date, default: []].append(point.value)
            }
        }
        return byDay.keys.sorted().compactMap { day in
            byDay[day].flatMap { Baseline.mean($0) }.map { DailyValue(date: day, value: $0) }
        }
    }

    /// The day-bucketed series for each source of a metric, in `breakdown.sources`
    /// order. Both `reading` and `dailySeries` are built on exactly this.
    ///
    /// Memoised for the length of an evaluation pass, because bucketing walks
    /// every reading and asks the calendar for a day boundary — and seven of the
    /// seventeen insight models ask for resting heart rate, each of which used to
    /// redo the whole thing. Falls through to computing it when there is no memo
    /// (a chart, a one-off read) or when `samples` isn't the array the memo was
    /// opened for.
    static func dailyBuckets(_ metric: MetricType,
                             breakdown: MultiSourceBreakdown,
                             from samples: [HealthMetricSample],
                             calendar: Calendar) -> [[AggregatedPoint]] {
        let compute = {
            breakdown.sources.map { $0.bucketed(by: .day, for: metric, calendar: calendar) }
        }
        guard let memo = MultiSource.memo, memo.covers(samples) else { return compute() }
        return memo.daily(.init(metric: metric, calendar: calendar), compute: compute)
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
        dailySeries(metric, from: samples, days: days, now: now, calendar: calendar)
            .map(\.value)
    }
}
