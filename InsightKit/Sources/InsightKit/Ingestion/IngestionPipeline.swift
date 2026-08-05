import Foundation

/// What one ingestion pass produced, including what it chose not to keep.
public struct IngestionResult: Sendable {
    /// Every field from every payload, typed and timestamped.
    public var raw: [RawMetricSample] = []
    /// Fields a promotion rule authorised as canonical vitals.
    public var promoted: [HealthMetricSample] = []
    /// Identifiers seen for the first time ever.
    public var newFields: [FieldDescriptor] = []
    /// Fields that look like a vital but have no rule — awaiting approval.
    public var proposals: [FieldDescriptor] = []
    /// Everything deliberately not stored, with a reason.
    public var skipped: [SkippedField] = []
    public var documentCount = 0
    public var payloadCount = 0
    /// Payloads no ingestor claimed, or that yielded nothing.
    public var unreadablePayloads: [String] = []

    /// Explicit and public: the synthesised memberwise initialiser is internal,
    /// and the app target needs to construct an empty result.
    public init() {}

    public var fieldCount: Int { raw.count }

    /// Skip reasons rolled up for the diagnostics log.
    public var skipSummary: [(reason: SkippedField.Reason, count: Int)] {
        Dictionary(grouping: skipped, by: \.reason)
            .map { (reason: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
}

/// Turns raw connector payloads into the vitals layer.
///
/// The pipeline is the only thing that decides what a payload means, and it
/// decides generically: walk everything, type it honestly, name it stably,
/// register it, and promote only what a rule authorises. Connectors contribute
/// an `EnvelopeSpec`; nothing here knows a provider by name.
public struct IngestionPipeline: Sendable {
    private let ingestors: [String: any PayloadIngestor]
    public let rules: PromotionRuleSet
    /// Only a rule whose interpretation resolves a *time of day* consults this —
    /// `.sleepOnset` is the one such metric. Injectable so a test can pin a zone
    /// rather than inherit the runner's, which decides whether 23:30 is last
    /// night or tonight.
    private let calendar: Calendar

    public init(ingestors: [any PayloadIngestor], rules: PromotionRuleSet = .default,
                calendar: Calendar = .current) {
        self.ingestors = Dictionary(ingestors.map { ($0.sourceID, $0) }, uniquingKeysWith: { _, new in new })
        self.rules = rules
        self.calendar = calendar
    }

    /// Ingest a batch of payloads, updating the catalogue in place.
    ///
    /// Runs to completion before insights are computed: a field discovered here
    /// is available to the engine in the same pass, not the next one.
    public func ingest(_ payloads: [IngestPayload],
                       into catalogue: inout FieldCatalogue,
                       now: Date = Date()) -> IngestionResult {
        var result = IngestionResult()
        result.payloadCount = payloads.count

        for payload in payloads {
            guard let ingestor = ingestors[payload.source.id] else {
                result.unreadablePayloads.append("\(payload.source.id).\(payload.endpoint) — no ingestor registered")
                continue
            }
            let documents = ingestor.documents(from: payload, calendar: calendar)
            if documents.isEmpty {
                result.unreadablePayloads.append("\(payload.source.id).\(payload.endpoint) — no dated records found")
                continue
            }
            result.documentCount += documents.count

            for document in documents {
                result.skipped += document.skipped
                for field in document.fields {
                    absorb(field, from: payload, document: document,
                           into: &catalogue, result: &result, now: now)
                }
            }
        }
        return result
    }

    private func absorb(_ field: FlatField,
                        from payload: IngestPayload,
                        document: IngestedDocument,
                        into catalogue: inout FieldCatalogue,
                        result: inout IngestionResult,
                        now: Date) {
        let identifier = "\(payload.source.id).\(payload.endpoint).\(field.path)"
        let rule = rules.rule(forIdentifier: identifier, sourceID: payload.source.id)
        let proposal = rule == nil ? rules.proposal(forIdentifier: identifier) : nil
        let displayName = Self.displayName(for: field.path, source: payload.source, endpoint: payload.endpoint)
        let unit = rule?.metric.unit ?? ""

        let isNew = catalogue.observe(identifier: identifier,
                                      displayName: displayName,
                                      sourceID: payload.source.id,
                                      endpoint: payload.endpoint,
                                      value: field.value,
                                      unit: unit,
                                      at: document.start,
                                      promotedTo: rule?.metric,
                                      proposedMetric: proposal)
        if isNew, let descriptor = catalogue.fields[identifier] {
            result.newFields.append(descriptor)
            if descriptor.proposedMetric != nil { result.proposals.append(descriptor) }
        }

        result.raw.append(RawMetricSample(identifier: identifier,
                                          displayName: displayName,
                                          value: field.value,
                                          unit: unit,
                                          start: document.start,
                                          end: document.end,
                                          source: payload.source))

        // The canonical layer is numbers, but the *field* need not be one: the
        // rule says how to read it. That indirection exists for `.sleepOnset`,
        // which is derived from an ISO-8601 timestamp — under the old
        // `doubleValue` guard a rule pointed at a text field matched and then
        // promoted nothing, with no error anywhere.
        if let rule, let promotion = rule.promotion(of: field.value, calendar: calendar) {
            // A rule may know better than the document which instant the reading
            // belongs to. A bedtime does: `SleepOnset` dates a night by the
            // morning it ends on, so 23:30 on Monday and the record Oura files
            // under Tuesday are one night, and stamping it at `document.start`
            // would make them two.
            let start = promotion.date ?? document.start
            let end = promotion.date ?? document.end
            result.promoted.append(HealthMetricSample(type: rule.metric,
                                                      value: promotion.value,
                                                      start: start,
                                                      end: end,
                                                      source: payload.source))
        }
    }

    /// "contributors.sleep_recovery" → "Resilience · Contributors: Sleep recovery (Oura)".
    static func displayName(for path: String, source: MetricSource, endpoint: String) -> String {
        let parts = path.split(separator: ".").map { humanize(String($0)) }
        let field = parts.joined(separator: ": ")
        return "\(humanize(endpoint)) · \(field) (\(source.displayName))"
    }

    /// `daily_cardiovascular_age` → `Daily cardiovascular age`; leaves numeric
    /// path components (array indices) alone.
    static func humanize(_ raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
        guard let first = spaced.first else { return spaced }
        return first.uppercased() + spaced.dropFirst()
    }
}

public extension IngestionPipeline {
    /// The connectors shipped today. Adding one is a line here plus its spec —
    /// no change to the flattener, the catalogue, the store or the engine.
    static let shipped = IngestionPipeline(ingestors: [
        GenericJSONIngestor(sourceID: MetricSource.oura.id, spec: .oura),
        GenericJSONIngestor(sourceID: MetricSource.whoop.id, spec: .whoop),
        WithingsMeasureIngestor()
    ])
}

public extension EnvelopeSpec {
    /// Oura v2: `{"data": [...], "next_token": ...}`, records dated by
    /// `bedtime_start`/`timestamp` (sessions) or `day` (daily summaries).
    ///
    /// **The order of `startDateKeys` is the fix for a shipped defect, not a
    /// detail.** `day` used to come first, and it is the *wake* date — so every
    /// Oura sleep session, its five-minute stage string included, was stamped at
    /// midnight UTC. All 15,604 Oura raw rows in the reader's export sit at
    /// exactly `T00:00:00Z`. On their UTC+8 phone that renders at 08:00, which
    /// is why the sleep chart showed a night beginning at half past seven in the
    /// morning. A precise instant must always beat a date-only field.
    ///
    /// Four further faults collapse out of the same cause, which is why this is
    /// one line rather than four fixes: 58 of 178 records shared a single
    /// instant (so hypnograms overdrew and the type join kept an arbitrary
    /// first record); `localStartHour` was *always* 8, so **naps passed the
    /// night filter**; 125 of 178 raw spans ended before they started.
    ///
    /// No migration. A returning source's cache is replaced wholesale on sync,
    /// and Oura's OAuth window is a rolling 730 days, so one re-sync re-dates
    /// everything within reach of any chart. A parallel analysis of the same
    /// export found the misregistration from the other end — sleep correlating
    /// with the cardiac signals at +0.79 one day out of step, against ≤0.44 at
    /// every other lag — so multi-signal statistics were mixing two nights.
    static let oura = EnvelopeSpec(
        recordsKeyPath: ["data"],
        startDateKeys: ["bedtime_start", "timestamp", "start_datetime", "day"],
        endDateKeys: ["bedtime_end", "end_datetime"],
        ignoredKeys: ["id"])

    /// Whoop v2: `{"records": [...], "next_token": ...}`.
    static let whoop = EnvelopeSpec(
        recordsKeyPath: ["records"],
        startDateKeys: ["start", "created_at", "updated_at"],
        endDateKeys: ["end"],
        ignoredKeys: ["id", "user_id", "cycle_id", "sleep_id"])
}
