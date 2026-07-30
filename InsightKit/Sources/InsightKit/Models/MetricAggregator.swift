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
        for sample in samples {
            let start = calendar.dateInterval(of: component, for: sample.start)?.start
                ?? sample.start
            if groups[start] == nil { order.append(start) }
            groups[start, default: []].append(sample.value)
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
            case .sum: value = values.reduce(0, +)
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
        guard !samples.isEmpty else { return [] }
        var out: [[HealthMetricSample]] = []
        var current: [HealthMetricSample] = [samples[0]]
        for sample in samples.dropFirst() {
            if let previous = current.last,
               sample.start.timeIntervalSince(previous.start) > maxGap {
                out.append(current)
                current = [sample]
            } else {
                current.append(sample)
            }
        }
        out.append(current)
        return out
    }
}

public extension Array where Element == AggregatedPoint {
    /// Contiguous runs of buckets, split on gaps — the aggregated equivalent of
    /// `SourceSeries.segments(maxGap:)`.
    func segments(maxGap: TimeInterval) -> [[AggregatedPoint]] {
        guard !isEmpty else { return [] }
        var out: [[AggregatedPoint]] = []
        var current: [AggregatedPoint] = [self[0]]
        for point in dropFirst() {
            if let previous = current.last,
               point.date.timeIntervalSince(previous.date) > maxGap {
                out.append(current)
                current = [point]
            } else {
                current.append(point)
            }
        }
        out.append(current)
        return out
    }
}
