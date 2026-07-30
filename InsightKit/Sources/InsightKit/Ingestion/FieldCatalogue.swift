import Foundation

/// What the app knows about one field it has seen in a provider payload.
///
/// The catalogue is the app's memory of provider schemas. It is what makes a
/// new field an *event* — "Oura started returning `daily_sleep.algorithm_version`
/// today" — rather than something that either silently appears in a list of
/// thousands or silently doesn't.
public struct FieldDescriptor: Codable, Sendable, Hashable, Identifiable {
    /// Namespaced and stable: `oura.daily_resilience.contributors.stress`.
    public let identifier: String
    public var displayName: String
    public var sourceID: String
    public var endpoint: String
    public var kind: RawValue.Kind
    public var unit: String
    public var firstSeen: Date
    public var lastSeen: Date
    public var observationCount: Int
    /// Distinct values seen for a text field, capped. A short list means the
    /// field is categorical (Oura resilience: limited/adequate/solid/strong)
    /// and can be charted as states; a full list means it's free text.
    public var observedTextValues: [String]
    /// Set when a promotion rule fires: this field also feeds a canonical vital.
    public var promotedTo: MetricType?
    /// Set when the field looks like a known vital but no rule authorises it.
    /// Surfaced for approval rather than acted on.
    public var proposedMetric: MetricType?

    public var id: String { identifier }

    /// Low-cardinality text is a state machine, not prose.
    public var isCategorical: Bool {
        kind == .text && !observedTextValues.isEmpty && observedTextValues.count <= FieldCatalogue.categoricalLimit
    }

    public init(identifier: String, displayName: String, sourceID: String, endpoint: String,
                kind: RawValue.Kind, unit: String = "", firstSeen: Date, lastSeen: Date,
                observationCount: Int = 0, observedTextValues: [String] = [],
                promotedTo: MetricType? = nil, proposedMetric: MetricType? = nil) {
        self.identifier = identifier
        self.displayName = displayName
        self.sourceID = sourceID
        self.endpoint = endpoint
        self.kind = kind
        self.unit = unit
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.observationCount = observationCount
        self.observedTextValues = observedTextValues
        self.promotedTo = promotedTo
        self.proposedMetric = proposedMetric
    }
}

/// The registry of every field the app has ever ingested, persisted between
/// launches so "new" means new to the app, not new to this sync.
public struct FieldCatalogue: Codable, Sendable {
    /// Above this many distinct strings, a text field stops being a category.
    public static let categoricalLimit = 24

    public private(set) var fields: [String: FieldDescriptor]

    public init(fields: [String: FieldDescriptor] = [:]) {
        self.fields = fields
    }

    public var all: [FieldDescriptor] {
        fields.values.sorted { $0.identifier < $1.identifier }
    }

    public var promoted: [FieldDescriptor] { all.filter { $0.promotedTo != nil } }
    public var proposals: [FieldDescriptor] { all.filter { $0.promotedTo == nil && $0.proposedMetric != nil } }

    /// Record one observation. Returns `true` the first time an identifier is
    /// seen, so the caller can report newly-discovered schema.
    @discardableResult
    public mutating func observe(identifier: String,
                                 displayName: String,
                                 sourceID: String,
                                 endpoint: String,
                                 value: RawValue,
                                 unit: String,
                                 at date: Date,
                                 promotedTo: MetricType?,
                                 proposedMetric: MetricType?) -> Bool {
        if var existing = fields[identifier] {
            existing.observationCount += 1
            existing.lastSeen = Swift.max(existing.lastSeen, date)
            existing.firstSeen = Swift.min(existing.firstSeen, date)
            // A provider can change a field's type between releases; the newest
            // observation wins so the UI renders what's actually arriving.
            existing.kind = value.kind
            existing.promotedTo = promotedTo
            existing.proposedMetric = proposedMetric
            if !unit.isEmpty { existing.unit = unit }
            if case .text(let s) = value,
               existing.observedTextValues.count <= Self.categoricalLimit,
               !existing.observedTextValues.contains(s) {
                existing.observedTextValues.append(s)
                existing.observedTextValues.sort()
            }
            fields[identifier] = existing
            return false
        }

        var texts: [String] = []
        if case .text(let s) = value { texts = [s] }
        fields[identifier] = FieldDescriptor(
            identifier: identifier, displayName: displayName, sourceID: sourceID,
            endpoint: endpoint, kind: value.kind, unit: unit,
            firstSeen: date, lastSeen: date, observationCount: 1,
            observedTextValues: texts, promotedTo: promotedTo, proposedMetric: proposedMetric)
        return true
    }

    /// Forget fields no provider has produced for a long time, so a connector
    /// the user removed doesn't clutter the catalogue forever.
    public mutating func prune(notSeenSince cutoff: Date) {
        fields = fields.filter { $0.value.lastSeen >= cutoff }
    }
}
