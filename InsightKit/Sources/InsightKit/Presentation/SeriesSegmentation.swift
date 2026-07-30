import Foundation

/// When a chart line may be drawn as continuous, and when a gap may be crossed
/// with an inferred, dashed connector.
///
/// This lives in InsightKit rather than in a view because it decides whether the
/// chart asserts a trend nobody measured — a correctness question, not a styling
/// one. The evidence is that it was wrong for its entire life *because* it lived
/// in a view: the app target has no test target, so `MultiSourceChart`'s private
/// copy of the rule was only ever checked by eye, and it broke the line between
/// every pair of adjacent points at every zoom past three days.
///
/// There were four copies of one loop under two different rules. That
/// duplication was the defect.

public extension BucketSize {
    /// Nominal width of one bucket, in seconds.
    ///
    /// Nominal because a month is not a fixed length: this is the spacing the gap
    /// rule reasons about, not a calendar calculation. The *longest* month is
    /// used, so a monthly grid can never split itself inside a 31-day month.
    var nominalDuration: TimeInterval {
        switch self {
        case .raw:   return 0
        case .hour:  return 3600
        case .day:   return 86_400
        case .week:  return 7 * 86_400
        case .month: return 31 * 86_400
        }
    }
}

public extension MetricType {
    /// Longest gap that may be drawn as one continuous line **once readings have
    /// been bucketed to `bucket`**.
    ///
    /// `maxValidInterval` is a *sample*-scale rule — thirty minutes for heart
    /// rate. Compared against bucket *starts* it breaks the line between every
    /// pair of adjacent buckets, which is what shattered the metric-detail chart
    /// into single points at every zoom past three days.
    ///
    /// Floored at two bucket widths: neighbours always join, one missing bucket
    /// still joins, two do not. Two and not one, because adjacent buckets are
    /// exactly one width apart and a one-width floor would break on a single
    /// absence. At `.day` this reproduces the two-day floor `NormalizedSeries`
    /// already carried, which is why moving that file onto this rule changes
    /// nothing.
    func maxPlottableGap(bucket: BucketSize) -> TimeInterval {
        Swift.max(maxValidInterval, 2 * bucket.nominalDuration)
    }
}

public enum SeriesSegmentation {
    /// Split a date-ordered array wherever the gap exceeds `maxGap`.
    ///
    /// One implementation for the four that existed.
    public static func split<T>(_ points: [T], maxGap: TimeInterval,
                                date: (T) -> Date) -> [[T]] {
        guard !points.isEmpty else { return [] }
        var out: [[T]] = []
        var run: [T] = [points[0]]
        for point in points.dropFirst() {
            if let previous = run.last,
               date(point).timeIntervalSince(date(previous)) > maxGap {
                out.append(run)
                run = [point]
            } else {
                run.append(point)
            }
        }
        out.append(run)
        return out
    }
}

public extension Array where Element == AggregatedPoint {
    /// Contiguous runs of buckets under the rule for this metric *at this bucket
    /// width* — the call a chart should make after bucketing.
    func segments(for metric: MetricType, bucket: BucketSize) -> [[AggregatedPoint]] {
        SeriesSegmentation.split(self, maxGap: metric.maxPlottableGap(bucket: bucket),
                                 date: \.date)
    }
}

/// One connector across a gap, in the terms a chart needs to draw it: two dates
/// and two values.
///
/// Deliberately not generic over the point type — two ends are all a dashed
/// two-point `LineMark` consumes.
public struct GapBridge: Sendable, Equatable, Identifiable {
    public let start: Date
    public let end: Date
    public let startValue: Double
    public let endValue: Double

    public init(start: Date, end: Date, startValue: Double, endValue: Double) {
        self.start = start
        self.end = end
        self.startValue = startValue
        self.endValue = endValue
    }

    public var id: String { "\(start.timeIntervalSince1970)>\(end.timeIntervalSince1970)" }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Which gaps a chart may cross with an inferred, dashed line.
///
/// A bridge is a claim that nothing interesting happened in between, so it is
/// bounded twice: by a small multiple of the metric's own honest join distance,
/// and by a fraction of the visible window — so a zoomed-out chart can never be
/// mostly inference.
///
/// **The connector is straight, and that is deliberate.** The roadmap asked for
/// "smoothed predicted values across data gaps", and a curve is exactly what must
/// not be drawn here: a Catmull-Rom bridge overshoots outside the measured range
/// and invents a local extremum in the one stretch where nothing is known. The
/// smoothing that was actually wanted has already happened — the endpoints are
/// *bucket aggregates* (median for weight, mean for the rest), not raw single
/// readings, so the line is drawn between two smoothed values.
public enum SeriesBridging {
    /// How many join-distances a gap may span and still be inferred across.
    public static let bridgeFactor: Double = 3
    /// And how much of the visible chart an inference may occupy.
    public static let maxWindowFraction: Double = 0.25

    public static func maxBridgeableGap(for metric: MetricType, bucket: BucketSize,
                                        window: TimeInterval) -> TimeInterval {
        Swift.min(bridgeFactor * metric.maxPlottableGap(bucket: bucket),
                  maxWindowFraction * window)
    }

    /// A gap is bridgeable when it is a real break *and* still short enough to
    /// infer across. When the window clause falls below the join rule nothing
    /// bridges, which is self-consistent and needs no special case.
    public static func isBridgeable(gap: TimeInterval, metric: MetricType,
                                    bucket: BucketSize, window: TimeInterval) -> Bool {
        gap > metric.maxPlottableGap(bucket: bucket)
            && gap <= maxBridgeableGap(for: metric, bucket: bucket, window: window)
    }

    /// The connectors to draw between consecutive runs from
    /// `segments(for:bucket:)`. Straight, endpoint to endpoint, no invented
    /// intermediate values.
    ///
    /// Computed between *adjacent* runs only, so a bridge can never overlap a
    /// drawn segment.
    ///
    /// Which pairs of adjacent runs may be joined, **returning the endpoints
    /// themselves** rather than a flattened two-dates-two-values struct.
    ///
    /// Generic, and returning the caller's own point type, because the two
    /// charts that bridge need different things out of the endpoints. The
    /// metric-detail chart wants only a date and a value, which is what
    /// `GapBridge` carries. The insight overlay encodes *anomaly as opacity*,
    /// so it needs the z-score of both ends to know how loudly to draw the
    /// connector — information `GapBridge` cannot hold and should not grow.
    ///
    /// The alternative was a second copy of this pairing loop in the view. That
    /// is the exact mistake this file exists to undo: there were four copies of
    /// the segmentation loop under two different rules, the app target has no
    /// test target, and the duplication *was* the defect.
    public static func bridgePairs<Point>(across runs: [[Point]], metric: MetricType,
                                          bucket: BucketSize, window: TimeInterval,
                                          date: (Point) -> Date) -> [(from: Point, to: Point)] {
        zip(runs, runs.dropFirst()).compactMap { left, right in
            guard let from = left.last, let to = right.first else { return nil }
            let gap = date(to).timeIntervalSince(date(from))
            guard isBridgeable(gap: gap, metric: metric, bucket: bucket, window: window) else {
                return nil
            }
            return (from, to)
        }
    }

    /// The bucketed-series call, unchanged for its callers.
    public static func bridges(across runs: [[AggregatedPoint]], metric: MetricType,
                               bucket: BucketSize, window: TimeInterval) -> [GapBridge] {
        bridgePairs(across: runs, metric: metric, bucket: bucket, window: window,
                    date: \.date)
            .map { GapBridge(start: $0.from.date, end: $0.to.date,
                             startValue: $0.from.value, endValue: $0.to.value) }
    }

    /// How prominent an inferred connector may be, given the two measurements
    /// it joins.
    ///
    /// **The quieter end wins, not the louder one.** Everywhere else on the
    /// overlay a span is as prominent as its more anomalous end, because both
    /// of its endpoints were measured and the louder one is the finding. A
    /// bridge has no measurement anywhere along it, so taking the maximum would
    /// let a single spike pull a whole week of silence forward as though
    /// something had been observed there. Taking the minimum says the weakest
    /// thing the two ends jointly support, which is all an inference is entitled
    /// to claim.
    ///
    /// Then halved again, because dash alone is not enough separation when the
    /// same hue is already on screen at full strength.
    public static func bridgeProminence(from: Double, to: Double) -> Double {
        Swift.min(from, to) / 2
    }
}
