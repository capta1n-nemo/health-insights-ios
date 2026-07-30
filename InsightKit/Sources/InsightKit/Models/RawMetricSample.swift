import Foundation

/// A measurement the app has imported but does **not** yet model as a canonical
/// `MetricType`. Every connected platform can produce data we haven't wired into
/// insights or the vitals catalogue yet (new HealthKit types, extra Oura/Withings
/// fields, and — in future — nutrition, medication, environment). Rather than
/// dropping it, we keep it verbatim here so it shows in the Vitals ▸ "Other data"
/// section for review, and is available to power more accurate insights later.
///
/// `value` is a `RawValue`, not a `Double`: providers send strings and booleans
/// as well as numbers, and the string ones are often the most meaningful field
/// in the payload (Oura's resilience `level`, its sleep-phase hypnogram). It
/// encodes as a bare JSON scalar, so caches written when this was a `Double`
/// still decode.
public struct RawMetricSample: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    /// Stable native identifier, e.g. "HKQuantityTypeIdentifierDietaryCaffeine"
    /// or "oura.daily_activity.equivalent_walking_distance".
    public let identifier: String
    /// Human-readable name derived from the identifier.
    public let displayName: String
    public let value: RawValue
    public let unit: String
    public let start: Date
    public let end: Date
    public let source: MetricSource

    /// The number to plot, or nil for free text.
    public var numericValue: Double? { value.doubleValue }

    public init(id: UUID = UUID(), identifier: String, displayName: String,
                value: RawValue, unit: String, start: Date, end: Date? = nil,
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

    /// Numeric convenience for the many call sites that genuinely do have a
    /// number in hand (HealthKit quantities, Withings measures).
    public init(id: UUID = UUID(), identifier: String, displayName: String,
                value: Double, unit: String, start: Date, end: Date? = nil,
                source: MetricSource) {
        self.init(id: id, identifier: identifier, displayName: displayName,
                  value: .number(value), unit: unit, start: start, end: end, source: source)
    }

    /// A value ready for a list row, with its unit where it has one.
    public var formattedValue: String {
        let text = value.displayString
        return unit.isEmpty ? text : "\(text) \(unit)"
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

    /// Whether this group can be drawn as a line. Text groups are listed, not
    /// charted; a categorical one is shown as its sequence of states.
    public var isPlottable: Bool { samples.contains { $0.numericValue != nil } }

    /// Distinct text values, newest first — the state history of a categorical
    /// field such as Oura's resilience level.
    public var distinctTextValues: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for sample in samples {
            guard case .text(let s) = sample.value, !seen.contains(s) else { continue }
            seen.insert(s)
            out.append(s)
        }
        return out
    }

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
