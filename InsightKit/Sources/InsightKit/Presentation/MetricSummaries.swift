import Foundation

// MARK: - Cumulative trend (weight, body composition)

/// Where a slow-moving measurement started, where it is now, and how fast it is
/// actually moving.
public struct TrendSummary: Sendable, Equatable {
    public let start: HealthMetricSample
    public let current: HealthMetricSample
    public let delta: Double
    /// nil when the starting value is zero, where a percentage is meaningless.
    public let percentChange: Double?
    /// Change per week. nil below two readings or across no elapsed time.
    public let velocityPerWeek: Double?
    /// The smoothed curve, so a chart can show the trend under the noise.
    public let smoothed: [HealthMetricSample]

    public init(start: HealthMetricSample, current: HealthMetricSample,
                delta: Double, percentChange: Double?,
                velocityPerWeek: Double?, smoothed: [HealthMetricSample]) {
        self.start = start
        self.current = current
        self.delta = delta
        self.percentChange = percentChange
        self.velocityPerWeek = velocityPerWeek
        self.smoothed = smoothed
    }

    /// Built from readings in chronological order.
    ///
    /// Velocity is a least-squares slope over the whole window rather than
    /// (last − start) / weeks, so one unusual final weigh-in can't swing the
    /// headline figure.
    public static func make(from samples: [HealthMetricSample],
                            alpha: Double = 0.2) -> TrendSummary? {
        let ordered = samples.sorted { $0.start < $1.start }
        guard let first = ordered.first, let last = ordered.last else { return nil }

        let delta = last.value - first.value
        let percent = first.value == 0 ? nil : (delta / abs(first.value)) * 100

        var velocity: Double?
        if ordered.count >= 2 {
            let reference = first.start.timeIntervalSince1970
            let weeks = ordered.map { ($0.start.timeIntervalSince1970 - reference) / (7 * 24 * 3600) }
            if let fit = Baseline.linearRegression(x: weeks, y: ordered.map(\.value)) {
                velocity = fit.slope
            }
        }

        let smoothedValues = Baseline.ewmaSeries(ordered.map(\.value), alpha: alpha)
        let smoothed = zip(ordered, smoothedValues).map { sample, value in
            HealthMetricSample(id: sample.id, type: sample.type, value: value,
                               start: sample.start, end: sample.end,
                               source: sample.source)
        }

        return TrendSummary(start: first, current: last, delta: delta,
                            percentChange: percent, velocityPerWeek: velocity,
                            smoothed: smoothed)
    }
}

// MARK: - Fluctuating range (heart rate, HRV, SpO2, sleep)

/// The spread of a signal that varies constantly, plus where the newest reading
/// sits inside it.
public struct RangeSummary: Sendable, Equatable {
    public let min, max, mean, median: Double
    public let p10, p25, p75, p90: Double
    public let count: Int
    public let latest: HealthMetricSample?
    /// 0…1 — where the newest reading ranks against the rest of the window.
    public let latestPercentile: Double?

    public init(min: Double, max: Double, mean: Double, median: Double,
                p10: Double, p25: Double, p75: Double, p90: Double,
                count: Int, latest: HealthMetricSample?, latestPercentile: Double?) {
        self.min = min
        self.max = max
        self.mean = mean
        self.median = median
        self.p10 = p10
        self.p25 = p25
        self.p75 = p75
        self.p90 = p90
        self.count = count
        self.latest = latest
        self.latestPercentile = latestPercentile
    }

    public static func make(from samples: [HealthMetricSample]) -> RangeSummary? {
        guard !samples.isEmpty else { return nil }
        let values = samples.map(\.value)
        let sorted = values.sorted()
        let latest = samples.max { $0.start < $1.start }
        return RangeSummary(
            min: sorted[0],
            max: sorted[sorted.count - 1],
            mean: Baseline.mean(values) ?? sorted[0],
            median: Baseline.quantile(0.5, of: sorted) ?? sorted[0],
            p10: Baseline.quantile(0.10, of: sorted) ?? sorted[0],
            p25: Baseline.quantile(0.25, of: sorted) ?? sorted[0],
            p75: Baseline.quantile(0.75, of: sorted) ?? sorted[0],
            p90: Baseline.quantile(0.90, of: sorted) ?? sorted[0],
            count: values.count,
            latest: latest,
            latestPercentile: latest.flatMap { Baseline.percentile($0.value, history: values) })
    }
}

// MARK: - Cumulative totals (steps, active energy)

/// One day's total for a metric that only means anything added up.
public struct DailyTotal: Sendable, Equatable, Identifiable {
    public let day: Date
    public let total: Double
    public var id: Date { day }

    public init(day: Date, total: Double) {
        self.day = day
        self.total = total
    }
}

public enum DailyTotals {
    /// Sums one source's readings per calendar day.
    ///
    /// Deliberately takes a single series: summing across sources double-counts
    /// a step taken with a Watch on your wrist and a phone in your pocket.
    public static func bucket(_ series: SourceSeries,
                              calendar: Calendar = .current) -> [DailyTotal] {
        series.bucketed(by: .day, statistic: .sum, calendar: calendar)
            .map { DailyTotal(day: $0.date, total: $0.value) }
    }

    /// Headline figures for a totals screen.
    public static func summary(_ totals: [DailyTotal], now: Date = Date(),
                               calendar: Calendar = .current)
        -> (today: Double?, dailyAverage: Double?, windowTotal: Double, best: DailyTotal?) {
        let windowTotal = totals.reduce(0) { $0 + $1.total }
        let today = totals.first { calendar.isDate($0.day, inSameDayAs: now) }?.total
        let average = totals.isEmpty ? nil : windowTotal / Double(totals.count)
        let best = totals.max { $0.total < $1.total }
        return (today, average, windowTotal, best)
    }
}
