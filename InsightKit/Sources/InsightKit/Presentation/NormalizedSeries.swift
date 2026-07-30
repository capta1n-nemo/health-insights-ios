import Foundation

/// How an overlay of several metrics puts them on one axis.
public enum SeriesScale: String, Sendable, CaseIterable, Identifiable {
    /// Standard deviations from the user's own typical value over the window.
    /// The only mode in which unlike units are genuinely comparable.
    case zScore
    /// The measured values, in their own units.
    case raw

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .zScore: return "Compare"
        case .raw: return "Raw"
        }
    }
}

public struct NormalizedPoint: Sendable, Equatable, Identifiable {
    public let date: Date
    /// Standard deviations from the window's mean for this metric.
    public let z: Double
    /// The measured value, kept so the chart can switch to real units and the
    /// legend can print "7.4 h" rather than "+1.2".
    public let raw: Double

    public var id: Date { date }

    public init(date: Date, z: Double, raw: Double) {
        self.date = date
        self.z = z
        self.raw = raw
    }

    public func value(_ scale: SeriesScale) -> Double {
        switch scale {
        case .zScore: return z
        case .raw: return raw
        }
    }
}

/// One metric resampled to a daily grid and standardised, ready to be drawn on
/// the same axis as metrics measured in completely different units.
///
/// Why z-scores and not a log axis: taking the log of blood oxygen (95–99%)
/// produces a dead-flat line while the log of sleep (5–9 h) still swings, so the
/// two shapes stay incomparable and the whole point of overlaying them is lost.
/// Standardising each series against its own spread is what makes "sleep is up
/// while oxygen is down" legible. It is also how the app already thinks —
/// `ReadinessScore` scores every component off `Baseline.zScore`.
public struct NormalizedSeries: Sendable, Equatable, Identifiable {
    public let metric: MetricType
    /// Which direction is the good one; nil where neither is.
    public let higherIsBetter: Bool?
    public let points: [NormalizedPoint]
    /// The window mean in real units — what "0" on the z axis means.
    public let baseline: Double

    public var id: MetricType { metric }
    public var latest: NormalizedPoint? { points.last }

    public init(metric: MetricType, higherIsBetter: Bool?,
                points: [NormalizedPoint], baseline: Double) {
        self.metric = metric
        self.higherIsBetter = higherIsBetter
        self.points = points
        self.baseline = baseline
    }

    /// Least-squares change per week in standard deviations. The basis for
    /// "trending up / drifting down" without letting one outlier day decide it.
    public var trendPerWeek: Double? {
        guard points.count >= 4, let first = points.first?.date else { return nil }
        let x = points.map { $0.date.timeIntervalSince(first) / 86_400 }
        let y = points.map(\.z)
        return Baseline.linearRegression(x: x, y: y).map { $0.slope * 7 }
    }

    /// Contiguous runs, broken wherever too many days are missing to honestly
    /// join them with a line. Purely interval-based, so no calendar is needed —
    /// the points are already snapped to day boundaries by the bucketing.
    public func segments() -> [[NormalizedPoint]] {
        // A daily grid needs a daily-scale gap rule — `maxValidInterval` is
        // thirty minutes for heart rate, which shatters a daily series into
        // single points. This file already knew that and carried its own two-day
        // floor; `maxPlottableGap(bucket:)` is that floor, generalised to every
        // bucket width and shared with the charts that didn't have it.
        SeriesSegmentation.split(points,
                                 maxGap: metric.maxPlottableGap(bucket: .day),
                                 date: \.date)
    }
}

public enum SeriesNormalizer {

    /// Build one standardised daily series per metric over `range`.
    ///
    /// Standardisation uses the whole visible window as the baseline, not a
    /// trailing one. The question this chart answers is "how did these signals
    /// move relative to each other over this period", and a trailing baseline
    /// would give each series a different, drifting zero — making the shapes
    /// incomparable, which is exactly what the chart exists to fix.
    public static func series(for contributions: [MetricContribution],
                              samples: [HealthMetricSample],
                              range: ClosedRange<Date>,
                              calendar: Calendar = .current) -> [NormalizedSeries] {
        contributions.byInfluence.compactMap { contribution in
            series(for: contribution.metric,
                   higherIsBetter: contribution.higherIsBetter,
                   samples: samples, range: range, calendar: calendar)
        }
    }

    public static func series(for metric: MetricType,
                              higherIsBetter: Bool?,
                              samples: [HealthMetricSample],
                              range: ClosedRange<Date>,
                              calendar: Calendar = .current) -> NormalizedSeries? {
        let ofType = MultiSource.deduplicate(
            samples.filter { $0.type == metric && range.contains($0.start) })
        guard let representative = ofType.last else { return nil }

        // Merged into one line per metric rather than one per source: this chart
        // compares metrics with each other, and splitting by device would draw
        // the same signal twice. `MultiSource.deduplicate` above is what stops a
        // ring reporting through two paths being counted twice. The source label
        // is carried only because `SourceSeries` needs one — nothing reads it.
        let daily = SourceSeries(source: representative.source, samples: ofType)
            .bucketed(by: .day, for: metric, calendar: calendar)
        guard daily.count >= 2 else { return nil }

        let values = daily.map(\.value)
        guard let mean = Baseline.mean(values) else { return nil }
        // No spread means every day was identical: there is no shape to compare,
        // and dividing by zero would invent one.
        guard let sd = Baseline.standardDeviation(values), sd > 0 else { return nil }

        let points = daily.map {
            NormalizedPoint(date: $0.date, z: ($0.value - mean) / sd, raw: $0.value)
        }
        return NormalizedSeries(metric: metric, higherIsBetter: higherIsBetter,
                                points: points, baseline: mean)
    }
}

public extension Array where Element == NormalizedSeries {
    /// Whether every series can honestly share a log axis. Log needs strictly
    /// positive values, and a deviation metric that swings through zero can't
    /// have one.
    var supportsLogScale: Bool {
        !isEmpty && allSatisfy { series in
            series.metric.presentation.allowsLogScale
                && series.points.allSatisfy { $0.raw > 0 }
        }
    }
}
