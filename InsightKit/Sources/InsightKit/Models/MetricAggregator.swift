import Foundation

/// How several readings inside one time bucket collapse to one plotted value.
public enum BucketStatistic: String, Sendable, Equatable {
    case mean, median, sum
}

/// The width of one aggregation bucket.
public enum BucketSize: String, Sendable, Equatable, CaseIterable {
    /// No aggregation — plot the readings as they were measured.
    case raw, hour, day, week, month

    /// Calendar component used to snap a date to its bucket start.
    var component: Calendar.Component? {
        switch self {
        case .raw: return nil
        case .hour: return .hour
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
}

/// One bucket's worth of readings, reduced to the numbers a chart needs.
///
/// Carries min and max as well as the central value so a long-range chart can
/// draw the spread it is hiding, rather than implying the day was one flat number.
public struct AggregatedPoint: Sendable, Identifiable, Equatable {
    /// Start of the bucket this summarises.
    public let date: Date
    public let value: Double      // the statistic this metric aggregates by
    public let mean: Double
    public let median: Double
    public let min: Double
    public let max: Double
    public let count: Int

    public var id: Date { date }

    public init(date: Date, value: Double, mean: Double, median: Double,
                min: Double, max: Double, count: Int) {
        self.date = date
        self.value = value
        self.mean = mean
        self.median = median
        self.min = min
        self.max = max
        self.count = count
    }
}

public extension BucketSize {
    /// Bucket width for an arbitrary visible window.
    ///
    /// Charts are handed a window in seconds rather than a `Timeframe` (panning
    /// and the data-derived `.all` window both produce values that match no
    /// case), so the choice is made from the span itself. The thresholds mirror
    /// `Timeframe.bucket`.
    static func forWindow(_ window: TimeInterval) -> BucketSize {
        let day: TimeInterval = 24 * 3600
        if window > 300 * day { return .month }
        if window > 45 * day { return .week }
        if window > 3 * day { return .day }
        if window > 1.5 * day { return .hour }
        return .raw
    }
}

public extension Timeframe {
    /// Bucket width for this zoom level.
    ///
    /// Plotting thousands of raw readings across a year is both illegible and
    /// slow; at that range a weekly summary carries the same information.
    var bucket: BucketSize {
        switch self {
        case .day: return .raw
        case .week: return .hour
        case .month: return .day
        case .sixMonths, .year: return .week
        case .all: return .month
        }
    }
}

public extension SourceSeries {
    /// Readings grouped into time buckets and reduced to one point each.
    ///
    /// Unlike `downsampled(to:)`, which decimates by keeping every Nth reading
    /// and so can alias, this summarises every reading in the range.
    func bucketed(by size: BucketSize,
                  statistic: BucketStatistic,
                  calendar: Calendar = .current) -> [AggregatedPoint] {
        guard !samples.isEmpty else { return [] }
        guard let component = size.component else {
            return samples.map {
                AggregatedPoint(date: $0.start, value: $0.value, mean: $0.value,
                                median: $0.value, min: $0.value, max: $0.value,
                                count: 1)
            }
        }

        var order: [Date] = []
        var groups: [Date: [Double]] = [:]
        // Per-path totals, for `.sum` only — see the `.sum` case below.
        var totalsByPath: [Date: [String: Double]] = [:]
        // `Calendar.dateInterval(of:for:)` resolves timezone and DST rules, and
        // calling it once per sample was by far the most expensive thing in this
        // function: on a three-year heart-rate series (~78k readings) it was
        // ~400 ms of a ~470 ms `VitalReader.reading`, and every insight that
        // reads a vital pays it again.
        //
        // Series arrive sorted, so consecutive readings nearly always land in the
        // bucket the previous one did — hold that interval and reuse it while it
        // still contains the sample. Correctness does not depend on the input
        // being sorted: a miss simply asks the calendar again. And it is DST-safe,
        // because the only interval ever reused is one the calendar itself
        // produced, for an instant inside it.
        //
        // The bounds are compared explicitly rather than with
        // `DateInterval.contains`, which is closed at the end — a reading at
        // exactly midnight would be attributed to the day before.
        var cachedBucket: DateInterval?
        for sample in samples {
            let start: Date
            if let cachedBucket, sample.start >= cachedBucket.start, sample.start < cachedBucket.end {
                start = cachedBucket.start
            } else if let interval = calendar.dateInterval(of: component, for: sample.start) {
                cachedBucket = interval
                start = interval.start
            } else {
                start = sample.start
            }
            if groups[start] == nil { order.append(start) }
            groups[start, default: []].append(sample.value)
            if statistic == .sum {
                totalsByPath[start, default: [:]][sample.source.id, default: 0] += sample.value
            }
        }

        return order.compactMap { start in
            guard let values = groups[start], !values.isEmpty else { return nil }
            let sorted = values.sorted()
            let mean = values.reduce(0, +) / Double(values.count)
            let median = Baseline.quantile(0.5, of: sorted) ?? mean
            let value: Double
            switch statistic {
            case .mean: value = mean
            case .median: value = median
            // **The largest single path's total, not the sum of every reading.**
            //
            // A `SourceSeries` is one *device family*, and `deviceFamily`
            // deliberately collapses the paths a device arrives by — so the
            // "oura" series holds both Oura's own daily step total (one reading
            // of ~4,400) and the same day mirrored into Apple Health as ~300
            // interval readings that add to the same ~4,400. Adding them
            // reported roughly double the steps the user took, and the same for
            // active energy. Found 2026-08-02 in an outside analysis of the
            // user's export, which spotted one path's median of 7 beside
            // another's median of 4,435 for one metric.
            //
            // The max rather than a preferred path: when both paths are
            // complete they agree, and when one is mid-sync it is short, so the
            // larger is the more complete account of the day. Deduplication
            // cannot catch this — the readings are neither the same minute nor
            // the same value, they are a total and its parts.
            case .sum: value = totalsByPath[start]?.values.max() ?? values.reduce(0, +)
            }
            return AggregatedPoint(date: start, value: value, mean: mean,
                                   median: median, min: sorted[0],
                                   max: sorted[sorted.count - 1],
                                   count: values.count)
        }
    }

    /// Bucketed using the metric's own rule (median for weight, sum for steps).
    func bucketed(by size: BucketSize,
                  for type: MetricType,
                  calendar: Calendar = .current) -> [AggregatedPoint] {
        bucketed(by: size, statistic: type.bucketStatistic, calendar: calendar)
    }

    /// Contiguous runs, split wherever the gap between readings exceeds `maxGap`.
    ///
    /// Each run is drawn as its own line, so nothing bridges a period when
    /// nothing was measured.
    func segments(maxGap: TimeInterval) -> [[HealthMetricSample]] {
        SeriesSegmentation.split(samples, maxGap: maxGap, date: \.start)
    }
}

public extension Array where Element == AggregatedPoint {
    /// Contiguous runs of buckets under an explicit gap.
    ///
    /// Prefer `segments(for:bucket:)`, which derives the gap from the metric and
    /// the bucket width instead of asking the caller to get it right. This is the
    /// escape hatch, and passing a *sample*-scale interval here against bucketed
    /// dates is exactly the mistake that shattered the metric-detail chart.
    func segments(maxGap: TimeInterval) -> [[AggregatedPoint]] {
        SeriesSegmentation.split(self, maxGap: maxGap, date: \.date)
    }
}
