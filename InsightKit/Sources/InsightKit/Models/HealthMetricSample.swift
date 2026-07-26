import Foundation

/// The source that produced a sample. Used for provenance, de-duplication and
/// to let the UI show "from Oura" / "from Withings" badges.
public struct MetricSource: Codable, Sendable, Hashable {
    public let id: String        // stable integration id, e.g. "apple_health"
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    public static let appleHealth = MetricSource(id: "apple_health", displayName: "Apple Health")
    public static let oura = MetricSource(id: "oura", displayName: "Oura")
    public static let withings = MetricSource(id: "withings", displayName: "Withings")
    public static let manual = MetricSource(id: "manual", displayName: "Manual entry")
}

/// A single normalised measurement. All values are stored in the canonical unit
/// declared by `MetricType.unit`.
public struct HealthMetricSample: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let type: MetricType
    public let value: Double
    public let start: Date
    public let end: Date
    public let source: MetricSource

    public init(
        id: UUID = UUID(),
        type: MetricType,
        value: Double,
        start: Date,
        end: Date? = nil,
        source: MetricSource
    ) {
        self.id = id
        self.type = type
        self.value = value
        self.start = start
        self.end = end ?? start
        self.source = source
    }
}

public extension Array where Element == HealthMetricSample {
    /// Samples of a given type, oldest → newest.
    func samples(of type: MetricType) -> [HealthMetricSample] {
        filter { $0.type == type }.sorted { $0.start < $1.start }
    }

    /// Most recent sample of a type, if any.
    func latest(_ type: MetricType) -> HealthMetricSample? {
        samples(of: type).last
    }

    /// Most recent value of a type, if any.
    func latestValue(_ type: MetricType) -> Double? {
        latest(type)?.value
    }

    /// Mean value of a type over the samples present, if any.
    func meanValue(_ type: MetricType) -> Double? {
        let values = samples(of: type).map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
