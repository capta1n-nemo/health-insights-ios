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
