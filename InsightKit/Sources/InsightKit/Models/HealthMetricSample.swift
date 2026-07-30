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
    public static let whoop = MetricSource(id: "whoop", displayName: "Whoop")
    public static let hume = MetricSource(id: "hume", displayName: "Hume")
    public static let manual = MetricSource(id: "manual", displayName: "Manual entry")
    public static let document = MetricSource(id: "document", displayName: "Imported document")

    /// A specific device *within* Apple Health (e.g. "Apple Watch", "Oura",
    /// "iPhone"). Apple Health mixes many devices; preserving the underlying
    /// device name is what lets us overlay and de-duplicate sources.
    public static func appleHealthDevice(_ name: String) -> MetricSource {
        let slug = name.lowercased().replacingOccurrences(of: " ", with: "_")
        // Clarify provenance: this data reached us through Apple Health, even
        // though it originated in another app/device (e.g. "MyFitnessPal via
        // Apple Health"). Avoid a redundant suffix if the name already says so.
        let label = name.localizedCaseInsensitiveContains("apple health")
            ? name : "\(name) via Apple Health"
        return MetricSource(id: "apple_health/\(slug)", displayName: label)
    }

    /// Which path a reading travelled to reach us.
    ///
    /// Distinct from `deviceFamily`, which deliberately collapses paths so the
    /// same physical reading isn't counted twice. This says *how* it arrived, so
    /// the UI can label "Oura (Direct API)" versus "Oura (via Apple Health)"
    /// without splitting them into competing series.
    ///
    /// Derived from `id`, not `displayName`, because persistence round-trips
    /// preserve the id but rebuild the display name.
    public var origin: SourceOrigin {
        if id == "manual" { return .manual }
        if id == "document" { return .document }
        guard id.hasPrefix("apple_health") else { return .directAPI }
        let name = "\(id) \(displayName)".lowercased()
        return name.contains("watch") ? .appleWatch : .appleHealth
    }

    /// A normalised device identity used to de-duplicate the same physical
    /// device arriving through more than one path — e.g. Oura synced directly
    /// via its API *and* mirrored into Apple Health both collapse to "oura".
    public var deviceFamily: String {
        let n = displayName.lowercased()
        if n.contains("watch") { return "apple_watch" }
        if n.contains("oura") { return "oura" }
        if n.contains("whoop") { return "whoop" }
        if n.contains("withings") { return "withings" }
        if n.contains("hume") { return "hume" }
        if n.contains("iphone") { return "iphone" }
        if id == "manual" || n.contains("manual") { return "manual" }
        if id.hasPrefix("apple_health") || n.contains("apple health") { return "apple_health" }
        return id
    }
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
