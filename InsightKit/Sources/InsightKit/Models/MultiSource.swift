import Foundation

/// One device's stream of a single metric, ready to plot as its own line and
/// summarise ("Apple Watch: 62 bpm").
public struct SourceSeries: Sendable, Identifiable, Equatable {
    public let source: MetricSource
    public let samples: [HealthMetricSample]   // sorted oldest → newest

    public var id: String { source.deviceFamily }
    public var displayName: String { source.displayName }

    public var latest: Double? { samples.last?.value }

    /// Every path that fed this series. More than one is normal and worth
    /// showing: the same ring can report directly and through Apple Health.
    public var origins: Set<SourceOrigin> {
        Set(samples.map(\.source.origin))
    }

    /// The path the newest reading took.
    public var latestOrigin: SourceOrigin? { samples.last?.source.origin }
    public var mean: Double? {
        guard !samples.isEmpty else { return nil }
        return samples.map(\.value).reduce(0, +) / Double(samples.count)
    }

    public init(source: MetricSource, samples: [HealthMetricSample]) {
        self.source = source
        self.samples = samples.sorted { $0.start < $1.start }
    }

    /// This series limited to a date range.
    ///
    /// Binary-searched rather than filtered: panning a chart re-slices the
    /// series continuously, and a linear scan of a long history on every frame
    /// is what makes it stutter. Relies on `samples` being sorted, which the
    /// initialiser guarantees.
    public func restricted(to range: ClosedRange<Date>) -> SourceSeries {
        let lower = firstIndex(atOrAfter: range.lowerBound)
        let upper = firstIndex(atOrAfter: range.upperBound.addingTimeInterval(1))
        guard lower < upper else { return SourceSeries(source: source, samples: []) }
        return SourceSeries(source: source, samples: Array(samples[lower..<upper]))
    }

    /// Index of the first sample starting at or after `date`, or `endIndex`.
    private func firstIndex(atOrAfter date: Date) -> Int {
        var low = 0
        var high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].start < date { low = mid + 1 } else { high = mid }
        }
        return low
    }

    /// An evenly-spaced subsample of at most `limit` readings, always keeping the
    /// first and last. Charting a decade of high-frequency data point-for-point
    /// is what makes the UI hang; the shape of the line survives thinning.
    public func downsampled(to limit: Int) -> SourceSeries {
        guard limit > 2, samples.count > limit else { return self }
        let stride = Double(samples.count - 1) / Double(limit - 1)
        var kept: [HealthMetricSample] = []
        kept.reserveCapacity(limit)
        for i in 0..<limit {
            kept.append(samples[Int((Double(i) * stride).rounded())])
        }
        return SourceSeries(source: source, samples: kept)
    }
}

/// Sources divided into those describing the present and those that have gone
/// quiet, so stale readings can be shown as history without polluting "now".
public struct SourceActivity: Sendable {
    public struct Stale: Sendable {
        public let series: SourceSeries
        public let lastActive: Date

        public init(series: SourceSeries, lastActive: Date) {
            self.series = series
            self.lastActive = lastActive
        }
    }

    public let active: [SourceSeries]
    public let inactive: [Stale]

    public init(active: [SourceSeries], inactive: [Stale]) {
        self.active = active
        self.inactive = inactive
    }

    /// A discrepancy is only worth reporting between sources that are both
    /// currently reporting.
    public var canCompare: Bool { active.count >= 2 }
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

    /// The single newest reading across every source.
    ///
    /// This is what a glanceable "current value" should show. `consensusLatest`
    /// averages each source's most recent value, which drifts far from today's
    /// number when sources last reported at very different times — a scale that
    /// weighed you this morning averaged with an app that last logged a year ago
    /// reads like a long-run average rather than a current one.
    public var mostRecent: HealthMetricSample? {
        sources.compactMap(\.samples.last).max { $0.start < $1.start }
    }

    /// Consensus = mean of each source's latest value, so a device isn't
    /// over-counted just because it sampled more often.
    public var consensusLatest: Double? {
        let values = latestBySource.map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// This breakdown limited to a date range, without re-scanning the full
    /// sample set. Sources left with nothing in the window are dropped, so
    /// read-outs never show a value from outside it.
    public func restricted(to range: ClosedRange<Date>) -> MultiSourceBreakdown {
        MultiSourceBreakdown(
            type: type,
            sources: sources.map { $0.restricted(to: range) }.filter { !$0.samples.isEmpty })
    }

    /// Each series thinned for plotting. See `SourceSeries.downsampled(to:)`.
    public func downsampled(to limit: Int) -> MultiSourceBreakdown {
        MultiSourceBreakdown(type: type, sources: sources.map { $0.downsampled(to: limit) })
    }

    /// Oldest → newest extent across every source; nil when there is no data.
    /// The chart derives its scroll domain and its `.all` window from this.
    public var dateSpan: ClosedRange<Date>? {
        let starts = sources.compactMap(\.samples.first?.start)
        let ends = sources.compactMap(\.samples.last?.start)
        guard let first = starts.min(), let last = ends.max(), first <= last else { return nil }
        return first...last
    }

    /// Sources split by whether they reported recently enough to describe "now".
    ///
    /// A phone that last logged a weight in 2022 still belongs on the chart, but
    /// letting it into the current average invents a discrepancy that doesn't
    /// exist today.
    public func activity(in range: ClosedRange<Date>,
                         recencyWindow: TimeInterval) -> SourceActivity {
        let cutoff = range.upperBound.addingTimeInterval(-recencyWindow)
        var active: [SourceSeries] = []
        var inactive: [SourceActivity.Stale] = []
        for series in sources {
            let inRange = series.restricted(to: range)
            guard let lastSeen = inRange.samples.last?.start
                    ?? series.samples.last?.start else { continue }
            if !inRange.samples.isEmpty && lastSeen >= cutoff {
                active.append(inRange)
            } else {
                inactive.append(.init(series: inRange.samples.isEmpty ? series : inRange,
                                      lastActive: lastSeen))
            }
        }
        return SourceActivity(active: active, inactive: inactive)
    }

    /// Mean of the given sources' latest values — the honest "average right now"
    /// when passed only the active ones.
    public func consensus(over series: [SourceSeries]) -> Double? {
        let values = series.compactMap(\.latest)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Disagreement between the given sources' latest values.
    public func spread(over series: [SourceSeries]) -> Double? {
        let values = series.compactMap(\.latest)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        return hi - lo
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
        // A struct key rather than an interpolated string: this runs once per
        // sample and string formatting dominated the cost on large histories.
        struct Key: Hashable {
            let family: String
            let minute: Int
            let hundredths: Int
        }
        var seen = Set<Key>()
        var out: [HealthMetricSample] = []
        out.reserveCapacity(samples.count)
        seen.reserveCapacity(samples.count)
        // deviceFamily lowercases and scans the display name, so memoise it —
        // there are only a handful of distinct sources but a great many samples.
        var families: [MetricSource: String] = [:]
        for s in samples.sorted(by: { $0.start < $1.start }) {
            let family = families[s.source] ?? {
                let f = s.source.deviceFamily
                families[s.source] = f
                return f
            }()
            let key = Key(family: family,
                          minute: Int(s.start.timeIntervalSince1970 / 60),
                          hundredths: Int((s.value * 100).rounded()))
            if seen.insert(key).inserted { out.append(s) }
        }
        return out
    }

    /// Build the per-source breakdown for a metric from a mixed sample set.
    public static func breakdown(_ type: MetricType, from samples: [HealthMetricSample]) -> MultiSourceBreakdown {
        let ofType = deduplicate(samples.filter { $0.type == type })
        var families: [MetricSource: String] = [:]
        let groups = Dictionary(grouping: ofType) { sample -> String in
            if let known = families[sample.source] { return known }
            let family = sample.source.deviceFamily
            families[sample.source] = family
            return family
        }
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
