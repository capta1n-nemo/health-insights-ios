import Foundation

/// A measurement the app has imported but does **not** yet model as a canonical
/// `MetricType`. Every connected platform can produce data we haven't wired into
/// insights or the vitals catalogue yet (new HealthKit types, extra Oura/Withings
/// fields, and — in future — nutrition, medication, environment). Rather than
/// dropping it, we keep it verbatim here so it shows in the Vitals ▸ "Other data"
/// section for review, and is available to power more accurate insights later.
public struct RawMetricSample: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    /// Stable native identifier, e.g. "HKQuantityTypeIdentifierDietaryCaffeine"
    /// or "oura.daily_activity.equivalent_walking_distance".
    public let identifier: String
    /// Human-readable name derived from the identifier.
    public let displayName: String
    public let value: Double
    public let unit: String
    public let start: Date
    public let end: Date
    public let source: MetricSource

    public init(id: UUID = UUID(), identifier: String, displayName: String,
                value: Double, unit: String, start: Date, end: Date? = nil,
                source: MetricSource) {
        self.id = id
        self.identifier = identifier
        self.displayName = displayName
        self.value = value
        self.unit = unit
        self.start = start
        self.end = end ?? start
        self.source = source
    }
}

/// A group of raw samples sharing one identifier, for the "Other data" browser.
public struct RawMetricGroup: Identifiable, Sendable {
    public let id: String            // the identifier
    public let displayName: String
    public let unit: String
    public let samples: [RawMetricSample]   // newest first
    public var latest: RawMetricSample? { samples.first }
    public var sources: Set<String> { Set(samples.map(\.source.displayName)) }

    public init(id: String, displayName: String, unit: String, samples: [RawMetricSample]) {
        self.id = id; self.displayName = displayName; self.unit = unit; self.samples = samples
    }
}

public extension Array where Element == RawMetricSample {
    /// Group by identifier, each group's samples newest-first, groups sorted by
    /// display name.
    func groupedByIdentifier() -> [RawMetricGroup] {
        Dictionary(grouping: self, by: \.identifier).map { key, value in
            let sorted = value.sorted { $0.start > $1.start }
            return RawMetricGroup(id: key,
                                  displayName: sorted.first?.displayName ?? key,
                                  unit: sorted.first?.unit ?? "",
                                  samples: sorted)
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Samples within a timeframe (nil window = all).
    func within(_ timeframe: Timeframe, now: Date = Date()) -> [RawMetricSample] {
        guard let start = timeframe.startDate(from: now) else { return self }
        return filter { $0.start >= start }
    }
}
