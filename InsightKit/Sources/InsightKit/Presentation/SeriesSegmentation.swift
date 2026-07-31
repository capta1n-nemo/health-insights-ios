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
/// **The connector is a curve, and specifically a monotone one.** The brief asked
/// for "smoothed predicted values across data gaps" and first got a straight
/// line, with the argument that a curve invents a local extremum in the one
/// stretch where nothing is known. That is true of a Catmull-Rom or natural
/// cubic, which overshoot outside the range of the values they join — and it is
/// an objection to *those* curves rather than to curvature. `GapBridge.smoothed`
/// uses a monotone cubic Hermite, which cannot have an interior extremum at all.
/// It is still dashed: smoothing changes nothing about the fact that nobody
/// measured it.
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

public extension GapBridge {

    /// Intermediate points along the bridge, so a chart can draw it as a curve
    /// rather than a straight segment.
    ///
    /// ## Why this exists, and why it took a second attempt
    ///
    /// The brief asked for "smoothed predicted values" across data gaps. The
    /// first answer was a straight dashed line and a written argument for it: a
    /// Catmull-Rom or natural cubic through the endpoints **overshoots** outside
    /// the range of the values it joins, inventing a local maximum or minimum in
    /// the one stretch where nothing was measured. Drawing a peak nobody
    /// recorded is worse than drawing a line nobody recorded.
    ///
    /// That objection is real, and it is an objection to *those* curves, not to
    /// curvature. A **monotone cubic Hermite** — the Fritsch–Carlson construction
    /// behind PCHIP — is built to guarantee exactly the property that was
    /// missing: with tangents limited as below, the interpolant is monotone
    /// between the two endpoints, so it has **no interior extremum at all** and
    /// never leaves the interval `[startValue, endValue]`. It reads as a smooth
    /// prediction and it cannot claim a peak.
    ///
    /// So the shape is a curve now, and it is still dashed, because dash means
    /// "not measured" and nothing about smoothing changes that.
    ///
    /// - Parameter tangentScale: how much of the endpoint-to-endpoint slope the
    ///   ends inherit. Zero is a flat-ended S; one is the straight line. The
    ///   default eases out of one reading and into the next.
    func smoothed(steps: Int = 12, tangentScale: Double = 0.6) -> [(date: Date, value: Double)] {
        guard steps > 1, duration > 0 else { return [] }
        let secant = (endValue - startValue) / duration
        // Fritsch–Carlson in the two-point case reduces to this: both tangents
        // take the sign and a bounded fraction of the one secant, which is what
        // makes an interior extremum impossible.
        let tangent = secant * tangentScale

        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            let seconds = t * duration
            // Cubic Hermite basis.
            let h00 = 2 * t * t * t - 3 * t * t + 1
            let h10 = t * t * t - 2 * t * t + t
            let h01 = -2 * t * t * t + 3 * t * t
            let h11 = t * t * t - t * t
            let value = h00 * startValue
                + h10 * duration * tangent
                + h01 * endValue
                + h11 * duration * tangent
            return (start.addingTimeInterval(seconds), value)
        }
    }
}
