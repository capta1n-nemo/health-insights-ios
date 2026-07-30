import Foundation

/// Transparent, training-free personalisation. Rather than a black-box model,
/// we characterise each signal by the user's own recent history and flag how far
/// today sits from that personal baseline. This is the "on-device data science"
/// layer used by the Heart Health score and anomaly surfacing.
public enum Baseline {

    /// Simple arithmetic mean.
    public static func mean(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        return xs.reduce(0, +) / Double(xs.count)
    }

    /// Sample standard deviation (n-1). Returns nil for fewer than 2 points.
    public static func standardDeviation(_ xs: [Double]) -> Double? {
        guard xs.count >= 2, let m = mean(xs) else { return nil }
        let ss = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        return (ss / Double(xs.count - 1)).squareRoot()
    }

    /// Exponentially weighted moving average. `alpha` in (0,1]; higher = more
    /// weight on recent samples. Input is oldest → newest.
    public static func ewma(_ xs: [Double], alpha: Double = 0.3) -> Double? {
        guard let first = xs.first else { return nil }
        var acc = first
        for x in xs.dropFirst() {
            acc = alpha * x + (1 - alpha) * acc
        }
        return acc
    }

    /// Z-score of `value` against a history. Positive = above personal baseline.
    /// Returns nil when the history is too small or has no spread.
    public static func zScore(_ value: Double, history: [Double]) -> Double? {
        guard let m = mean(history), let sd = standardDeviation(history), sd > 0 else {
            return nil
        }
        return (value - m) / sd
    }

    /// Percentile (0…1) of `value` within `history` using the empirical CDF.
    public static func percentile(_ value: Double, history: [Double]) -> Double? {
        guard !history.isEmpty else { return nil }
        let below = history.filter { $0 <= value }.count
        return Double(below) / Double(history.count)
    }

    /// The whole EWMA curve rather than just its final value — the smoothed
    /// line a trend chart draws. Input and output are oldest → newest.
    public static func ewmaSeries(_ xs: [Double], alpha: Double = 0.3) -> [Double] {
        guard let first = xs.first else { return [] }
        var acc = first
        var out: [Double] = [first]
        out.reserveCapacity(xs.count)
        for x in xs.dropFirst() {
            acc = alpha * x + (1 - alpha) * acc
            out.append(acc)
        }
        return out
    }

    /// The value at quantile `q` (0…1), linearly interpolated.
    ///
    /// The inverse of `percentile(_:history:)`: that answers "how high does this
    /// value rank?", this answers "what value sits at that rank?" — which is
    /// what a p10–p90 range needs.
    public static func quantile(_ q: Double, of xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let sorted = xs.sorted()
        if sorted.count == 1 { return sorted[0] }
        let clamped = Swift.min(Swift.max(q, 0), 1)
        let position = clamped * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    /// Ordinary least-squares fit of y on x.
    ///
    /// Used for trend velocity: a slope over the whole window is far less jumpy
    /// than (last − first), which one noisy final reading can swing.
    public static func linearRegression(x: [Double], y: [Double])
        -> (slope: Double, intercept: Double, residualSD: Double)? {
        guard x.count == y.count, x.count >= 2,
              let mx = mean(x), let my = mean(y) else { return nil }
        var sxx = 0.0
        var sxy = 0.0
        for i in x.indices {
            let dx = x[i] - mx
            sxx += dx * dx
            sxy += dx * (y[i] - my)
        }
        guard sxx > 0 else { return nil }   // no spread in x: slope undefined
        let slope = sxy / sxx
        let intercept = my - slope * mx
        let residuals = x.indices.map { y[$0] - (slope * x[$0] + intercept) }
        return (slope, intercept, standardDeviation(residuals) ?? 0)
    }

    /// Pearson correlation of two paired series, in -1…1.
    ///
    /// Answers "do these two move together?", which `linearRegression` only
    /// answers in the units of `y` — a slope of 3 says nothing about how tightly
    /// the points hug the line. Returns nil when either series has no spread,
    /// because a flat series correlates with nothing.
    public static func correlation(x: [Double], y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 3,
              let mx = mean(x), let my = mean(y) else { return nil }
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for i in x.indices {
            let dx = x[i] - mx
            let dy = y[i] - my
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }
        guard sxx > 0, syy > 0 else { return nil }
        // Clamped because accumulated floating-point error can push a perfect
        // relation a hair past ±1, and a correlation outside that range is
        // nonsense to anything reading it.
        return Swift.max(-1, Swift.min(1, sxy / (sxx * syy).squareRoot()))
    }

    /// A compact description of where a fresh value sits relative to baseline.
    public struct Deviation: Sendable, Equatable {
        public let value: Double
        public let baseline: Double
        public let zScore: Double?
        /// -1 well below, 0 typical, +1 well above baseline (|z| > 1.5 threshold).
        public let direction: Int

        public init(value: Double, baseline: Double, zScore: Double?, direction: Int) {
            self.value = value
            self.baseline = baseline
            self.zScore = zScore
            self.direction = direction
        }
    }

    /// Compare the latest value to a rolling baseline built from `history`.
    public static func deviation(latest: Double, history: [Double], threshold: Double = 1.5) -> Deviation? {
        guard let base = ewma(history) ?? mean(history) else { return nil }
        let z = zScore(latest, history: history)
        var direction = 0
        if let z, abs(z) >= threshold { direction = z > 0 ? 1 : -1 }
        return Deviation(value: latest, baseline: base, zScore: z, direction: direction)
    }
}
