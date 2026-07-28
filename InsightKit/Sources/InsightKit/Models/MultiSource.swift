import Foundation

/// One device's stream of a single metric, ready to plot as its own line and
/// summarise ("Apple Watch: 62 bpm").
public struct SourceSeries: Sendable, Identifiable, Equatable {
    public let source: MetricSource
    public let samples: [HealthMetricSample]   // sorted oldest → newest

    public var id: String { source.deviceFamily }
    public var displayName: String { source.displayName }

    public var latest: Double? { samples.last?.value }
    public var mean: Double? {
        guard !samples.isEmpty else { return nil }
        return samples.map(\.value).reduce(0, +) / Double(samples.count)
    }

    public init(source: MetricSource, samples: [HealthMetricSample]) {
        self.source = source
        self.samples = samples.sorted { $0.start < $1.start }
    }
}

/// A metric split by the device that produced it, so the UI can overlay each
/// source on one chart and show "Apple said X, Oura said Y, average Z". This is
/// the universal building block every card uses to be honest about multiple,
/// sometimes-disagreeing sources.
public struct MultiSourceBreakdown: Sendable, Equatable {
    public let type: MetricType
    /// One entry per distinct device, most-data first.
    public let sources: [SourceSeries]

    public var hasMultipleSources: Bool { sources.count > 1 }

    /// The latest value from each source (for the "Apple: X, Oura: Y" line).
    public var latestBySource: [(source: MetricSource, value: Double)] {
        sources.compactMap { s in s.latest.map { (s.source, $0) } }
    }

    /// Consensus = mean of each source's latest value, so a device isn't
    /// over-counted just because it sampled more often.
    public var consensusLatest: Double? {
        let values = latestBySource.map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// The spread between sources' latest values (0 when they agree / single).
    public var latestSpread: Double? {
        let values = latestBySource.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        return hi - lo
    }
}

public enum MultiSource {

    /// Collapse the same physical device arriving twice (e.g. Oura via its API
    /// and Oura mirrored into Apple Health) into one sample. Two samples match
    /// when they share a device family, the same minute, and the same value.
    public static func deduplicate(_ samples: [HealthMetricSample]) -> [HealthMetricSample] {
        var seen = Set<String>()
        var out: [HealthMetricSample] = []
        for s in samples.sorted(by: { $0.start < $1.start }) {
            let minute = Int(s.start.timeIntervalSince1970 / 60)
            let key = "\(s.source.deviceFamily)|\(minute)|\(String(format: "%.2f", s.value))"
            if seen.insert(key).inserted { out.append(s) }
        }
        return out
    }

    /// Build the per-source breakdown for a metric from a mixed sample set.
    public static func breakdown(_ type: MetricType, from samples: [HealthMetricSample]) -> MultiSourceBreakdown {
        let ofType = deduplicate(samples.filter { $0.type == type })
        let groups = Dictionary(grouping: ofType) { $0.source.deviceFamily }
        let series: [SourceSeries] = groups.map { _, arr in
            // Represent the group by its most recent sample's source label.
            let sorted = arr.sorted { $0.start < $1.start }
            return SourceSeries(source: sorted.last!.source, samples: sorted)
        }
        // Most data first, then alphabetical for stability.
        .sorted { a, b in
            a.samples.count != b.samples.count
                ? a.samples.count > b.samples.count
                : a.displayName < b.displayName
        }
        return MultiSourceBreakdown(type: type, sources: series)
    }
}
