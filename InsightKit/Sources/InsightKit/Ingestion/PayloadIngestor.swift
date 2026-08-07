import Foundation

/// A raw response captured from a connector, handed to the pipeline verbatim.
///
/// Providers no longer decide what is worth keeping — they hand over the bytes
/// and the pipeline decides. That inversion is what makes a schema change a
/// non-event: a field the provider added this morning is in these bytes whether
/// or not anyone has written code for it.
public struct IngestPayload: Sendable {
    public let source: MetricSource
    public let endpoint: String
    public let data: Data

    public init(source: MetricSource, endpoint: String, data: Data) {
        self.source = source
        self.endpoint = endpoint
        self.data = data
    }
}

/// One timestamped record extracted from a payload, already flattened.
public struct IngestedDocument: Sendable {
    public let start: Date
    public let end: Date
    public let fields: [FlatField]
    public let skipped: [SkippedField]

    public init(start: Date, end: Date, fields: [FlatField], skipped: [SkippedField] = []) {
        self.start = start
        self.end = end
        self.fields = fields
        self.skipped = skipped
    }
}

/// The connector abstraction. A new provider supplies one of these — in the
/// common case by describing its envelope rather than writing any code.
public protocol PayloadIngestor: Sendable {
    var sourceID: String { get }
    /// The calendar is a parameter, not a `.current` read, because a bare
    /// `yyyy-MM-dd` field names a calendar day and a calendar day is only
    /// meaningful in a zone — see `DayStamp`. Reading `.current` here is what
    /// left the ingestion side pinned to UTC while every other day in the app
    /// was local, and made the disagreement untestable.
    func documents(from payload: IngestPayload, calendar: Calendar) -> [IngestedDocument]
}

/// Describes where a provider's records live inside its response and how each
/// one is dated. This is the whole of a typical connector's configuration.
public struct EnvelopeSpec: Sendable {
    /// Keys to walk from the response root to the array of records.
    /// Oura: `["data"]`. A response that *is* an array: `[]`. A single object:
    /// `[]` as well — it's treated as one record.
    public let recordsKeyPath: [String]
    /// Candidate keys for a record's timestamp, in preference order.
    public let startDateKeys: [String]
    public let endDateKeys: [String]
    /// Keys carrying no measurement — identifiers and the date fields
    /// themselves, which are recorded as the sample's timestamp instead.
    public let ignoredKeys: Set<String>
    public let policy: FlattenPolicy

    public init(recordsKeyPath: [String],
                startDateKeys: [String],
                endDateKeys: [String] = [],
                ignoredKeys: Set<String> = [],
                policy: FlattenPolicy = .default) {
        self.recordsKeyPath = recordsKeyPath
        self.startDateKeys = startDateKeys
        self.endDateKeys = endDateKeys
        self.ignoredKeys = ignoredKeys
        self.policy = policy
    }
}

/// Unpacks any JSON envelope described by an `EnvelopeSpec`. Handles Oura today
/// and is expected to handle most future connectors without subclassing.
public struct GenericJSONIngestor: PayloadIngestor {
    public let sourceID: String
    public let spec: EnvelopeSpec

    public init(sourceID: String, spec: EnvelopeSpec) {
        self.sourceID = sourceID
        self.spec = spec
    }

    public func documents(from payload: IngestPayload, calendar: Calendar) -> [IngestedDocument] {
        guard let root = try? JSONSerialization.jsonObject(with: payload.data) else { return [] }
        var out: [IngestedDocument] = []
        for record in Self.records(in: root, at: spec.recordsKeyPath) {
            guard let start = PayloadDate.firstDate(in: record, keys: spec.startDateKeys,
                                                    calendar: calendar) else { continue }
            let end = PayloadDate.firstDate(in: record, keys: spec.endDateKeys,
                                            calendar: calendar) ?? start
            // The date keys are consumed as the timestamp, so exclude them from
            // the field sweep rather than storing them twice.
            let ignored = spec.ignoredKeys
                .union(spec.startDateKeys)
                .union(spec.endDateKeys)
            let flattened = JSONFlattener.flatten(record, policy: spec.policy, skipping: ignored)
            // …but the *zone* on those keys is not a duplicate of the timestamp,
            // and until 2026-08-07 this line was the only place it ever existed.
            //
            // Oura stamps `bedtime_start` as `2026-08-06T23:10:00+08:00`. The
            // instant survives; `+08:00` does not — `ISO8601DateFormatter`
            // resolves and discards it, and because the date keys are excluded
            // from the sweep above the string never reaches the raw catalogue
            // either. So the app held **no time zone on any health reading**,
            // and the one provider that sends one had it deleted at the door.
            //
            // That is the whole of the reader's 2026-08-07 report: they flew
            // Manila → Sydney and slept across the change. Whether a night
            // crossed zones is a fact only these two fields know.
            //
            // Emitted as ordinary flat fields rather than as a new column on
            // `IngestedDocument`, so they land in the raw catalogue beside the
            // record they describe (`oura.sleep.zone_offset_seconds`) with no
            // model change and no promotion rule — the same shape
            // `NightSleepDetail` already joins `oura.sleep.type` by.
            //
            // The path names the *role*, not the provider's key, because the
            // only consumer question is "which end of the record is this?" and
            // that must be answerable without knowing whether the provider
            // called it `bedtime_start`, `start` or `start_datetime`.
            var fields = flattened.fields
            if let seconds = Self.offsetSeconds(in: record, keys: spec.startDateKeys,
                                                calendar: calendar) {
                fields.append(FlatField(path: PayloadDate.startZoneOffsetField,
                                        value: .number(Double(seconds))))
            }
            if let seconds = Self.offsetSeconds(in: record, keys: spec.endDateKeys,
                                                calendar: calendar) {
                fields.append(FlatField(path: PayloadDate.endZoneOffsetField,
                                        value: .number(Double(seconds))))
            }
            out.append(IngestedDocument(start: start, end: end,
                                        fields: fields, skipped: flattened.skipped))
        }
        return out
    }

    /// Which key actually supplied the timestamp — the same preference order
    /// `PayloadDate.firstDate` walks, so the offset can never be attributed to a
    /// different field than the instant it belongs to.
    static func datingKey(in record: [String: Any], keys: [String],
                          calendar: Calendar) -> String? {
        keys.first { key in
            guard let raw = record[key] else { return false }
            return PayloadDate.parse(raw, calendar: calendar) != nil
        }
    }

    /// The UTC offset stamped on the dating key, or nil when it carries none —
    /// a bare `2026-08-06` names a day and says nothing about a zone, and
    /// inventing one for it is exactly the accident `DayStamp` documents.
    static func offsetSeconds(in record: [String: Any], keys: [String],
                              calendar: Calendar) -> Int? {
        guard let key = datingKey(in: record, keys: keys, calendar: calendar),
              let raw = record[key] else { return nil }
        return PayloadDate.utcOffsetSeconds(raw)
    }

    /// Navigate to the record array, tolerating the three shapes a provider
    /// realistically returns: `{key: [...]}`, a bare array, or a single object.
    static func records(in root: Any, at keyPath: [String]) -> [[String: Any]] {
        var node: Any = root
        for key in keyPath {
            guard let object = node as? [String: Any], let next = object[key] else { return [] }
            node = next
        }
        if let array = node as? [[String: Any]] { return array }
        if let single = node as? [String: Any] { return [single] }
        return []
    }
}

/// Withings encodes measurements as `(type, value, unit)` triples inside dated
/// groups rather than as named fields, so the generic sweep would record
/// `measures.0.type = 1` and lose the meaning. This gives each measure type a
/// stable path and applies Withings' base-10 exponent, then hands the rest of
/// the group to the generic flattener so nothing else is lost either.
public struct WithingsMeasureIngestor: PayloadIngestor {
    public let sourceID: String
    private let policy: FlattenPolicy

    public init(sourceID: String = MetricSource.withings.id, policy: FlattenPolicy = .default) {
        self.sourceID = sourceID
        self.policy = policy
    }

    /// Device metadata the sweep must not turn into "signals".
    ///
    /// The first data export showed why this list exists: of the 232
    /// "unmodelled signals" in the Vitals ▸ Other data browser, **~80 were
    /// Withings bookkeeping** — a `.algo` and `.fm` row for every measure
    /// type, record ids, sync timestamps. None is a measurement of a person,
    /// and together they buried the rows that are (see
    /// `docs/data-opportunities.md` ▸ "Housekeeping the export exposed").
    /// Dropped by the same mechanism as the date keys — before the catalogue,
    /// so they stop being "discovered fields" at all.
    ///
    /// `attrib`, `category` and `comment` are deliberately *kept*: the first
    /// two say whether a reading was measured or typed in, and the comment is
    /// the user's own words. Those are facts about the measurement, not about
    /// the sync.
    static let measureMetadataKeys: Set<String> = ["algo", "fm", "position", "apppfmid"]
    static let groupMetadataKeys: Set<String> = [
        "deviceid", "hash_deviceid", "created", "modified", "grpid", "timezone",
        "apppfmid",
    ]

    public func documents(from payload: IngestPayload, calendar: Calendar) -> [IngestedDocument] {
        guard let root = try? JSONSerialization.jsonObject(with: payload.data) as? [String: Any],
              let body = root["body"] as? [String: Any],
              let groups = body["measuregrps"] as? [[String: Any]] else { return [] }

        var out: [IngestedDocument] = []
        for group in groups {
            // Withings dates are epoch seconds, so the calendar is inert here —
            // passed for the protocol, not because this path can drift.
            guard let start = PayloadDate.firstDate(in: group, keys: ["date"],
                                                    calendar: calendar) else { continue }
            var fields: [FlatField] = []
            var skipped: [SkippedField] = []

            for measure in (group["measures"] as? [[String: Any]]) ?? [] {
                guard let type = (measure["type"] as? NSNumber)?.intValue,
                      let value = (measure["value"] as? NSNumber)?.doubleValue else { continue }
                // A type the typed parser already promotes to a canonical
                // metric (weight, body fat, blood pressure, …) must not also
                // arrive here: the same scale reading was showing once in
                // Vitals and again as `withings.measure.1` in Other data, and
                // the raw copy can only ever agree with or contradict the
                // promoted one. Asking the parser's own map — rather than
                // keeping a second list of type numbers — is what stops the
                // two drifting when a new type is promoted.
                guard WithingsResponseParser.metricType(for: type) == nil else { continue }
                let exponent = (measure["unit"] as? NSNumber)?.doubleValue ?? 0
                // Path is the bare type number: the endpoint name already
                // supplies the "measure" namespace, giving `withings.measure.12`.
                fields.append(FlatField(path: "\(type)",
                                        value: .number(value * pow(10, exponent))))
                // Any future per-measure fields, minus the bookkeeping above.
                for (key, raw) in measure
                where !["type", "value", "unit"].contains(key)
                    && !Self.measureMetadataKeys.contains(key) {
                    guard let scalar = RawValue(json: raw) else { continue }
                    fields.append(FlatField(path: "\(type).\(key)", value: scalar))
                }
            }

            // Group-level fields worth keeping: attrib, category, and
            // `comment`, which is free text and previously had nowhere to go.
            let rest = JSONFlattener.flatten(
                group, policy: policy,
                skipping: Set(["date", "measures"]).union(Self.groupMetadataKeys))
            fields += rest.fields
            skipped += rest.skipped

            out.append(IngestedDocument(start: start, end: start, fields: fields, skipped: skipped))
        }
        return out
    }
}

/// Date parsing across the formats connectors actually use: a plain day, an
/// ISO-8601 instant with or without fractional seconds, or epoch seconds.
public enum PayloadDate {
    public static func firstDate(in record: [String: Any], keys: [String],
                                 calendar: Calendar = .current) -> Date? {
        for key in keys {
            if let raw = record[key], let date = parse(raw, calendar: calendar) { return date }
        }
        return nil
    }

    /// The bare form, for the callers that hold no calendar and parse only
    /// instants — `WhoopResponseParser`, `ShotsyImport`, `OuraResponseParser`'s
    /// bedtimes. A day string reaching *this* overload resolves in the device's
    /// own zone, which is the same answer the calendar-taking one gives for
    /// `.current`.
    public static func parse(_ any: Any) -> Date? { parse(any, calendar: .current) }

    public static func parse(_ any: Any, calendar: Calendar) -> Date? {
        if let n = any as? NSNumber, !isJSONBoolean(n) {
            let seconds = n.doubleValue
            // Reject obvious non-timestamps so a numeric field named like a date
            // can't produce a sample in 1970 or the year 5000.
            guard seconds > 631_152_000, seconds < 4_102_444_800 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        guard let s = any as? String, !s.isEmpty else { return nil }
        // A ten-character field is a *day*, and this is the only branch that can
        // see one — which is what makes `DayStamp` safe to apply here and
        // nowhere else. A rule phrased over the resulting `Date` ("if it is
        // midnight UTC, shift it") would corrupt the 109 HealthKit samples in
        // the reader's export that genuinely land at T00:00:00Z. See `DayStamp`.
        if s.count == 10, let day = DayStamp.local(s, calendar: calendar) { return day }
        if let d = isoWithFraction.date(from: s) { return d }
        if let d = isoPlain.date(from: s) { return d }
        return nil
    }

    /// Field paths under which a captured zone offset is catalogued, giving
    /// `oura.sleep.zone_offset_seconds` and `oura.sleep.zone_offset_seconds_at_end`.
    ///
    /// Named so they can never collide with a promotion alias —
    /// `PromotionRuleSet.proposal(forIdentifier:)` matches on the *leaf*, and no
    /// vital is called `zone_offset_seconds`. They stay raw on purpose: a UTC
    /// offset is a fact about the recording, not a measurement of the reader.
    public static let startZoneOffsetField = "zone_offset_seconds"
    public static let endZoneOffsetField = "zone_offset_seconds_at_end"

    /// The UTC offset an ISO-8601 instant was written in, in seconds, or nil if
    /// the value carries none.
    ///
    /// **This is the only measurement of the reader's time zone the app has
    /// ever received.** No health reading in this codebase stores a zone;
    /// `CalendarModel.timeZoneChanges` infers travel from calendar events, which
    /// is an inference. `2026-08-06T23:10:00+08:00` is not an inference: the
    /// ring recorded it from the phone that was in Manila.
    ///
    /// Parsed by hand rather than by `ISO8601DateFormatter`, for two reasons and
    /// both of them are already precedents in this file. Foundation's formatter
    /// *resolves* the offset into an instant and then has no API to tell you
    /// what it was — the information is gone by the time you hold the `Date`.
    /// And this package's suite runs on Linux, where several formatter paths are
    /// Darwin-only; the same rationale as `DayStamp` and `ShortcutIngest.parseDate`.
    ///
    /// Returns 0 for `Z`, which is a real answer — the writer said UTC — and
    /// nil for a bare day or a naive local timestamp, which said nothing.
    /// **Nil and zero must not be conflated**: a naive timestamp treated as UTC
    /// is the shape `verify.sh` bans and the shear `DayStamp` exists to describe.
    public static func utcOffsetSeconds(_ any: Any) -> Int? {
        guard let s = any as? String else { return nil }
        // Only an instant carries a zone. A ten-character day never does, and a
        // date's own hyphens must not be mistaken for a negative offset — which
        // is why everything below is read from *after* the date/time separator.
        guard let separator = s.firstIndex(where: { $0 == "T" || $0 == "t" || $0 == " " })
        else { return nil }
        let time = s[s.index(after: separator)...]
        guard !time.isEmpty else { return nil }
        if time.hasSuffix("Z") || time.hasSuffix("z") { return 0 }
        guard let signIndex = time.lastIndex(where: { $0 == "+" || $0 == "-" })
        else { return nil }
        let sign = time[signIndex] == "-" ? -1 : 1
        let digits = String(time[time.index(after: signIndex)...].filter(\.isNumber))
        // `+08:00` and `+0800` are the same offset; `+08` is the bare-hour form.
        // Anything else is not a zone designator and is refused rather than guessed.
        let hourText: Substring
        let minuteText: Substring
        switch digits.count {
        case 4: hourText = digits.prefix(2); minuteText = digits.suffix(2)
        case 2: hourText = digits.prefix(2); minuteText = ""
        default: return nil
        }
        guard let hours = Int(hourText), hours <= 14 else { return nil }
        let minutes = minuteText.isEmpty ? 0 : Int(minuteText) ?? -1
        // Real zones run to ±14:00, and 45-minute offsets exist (Nepal, Chatham).
        guard minutes >= 0, minutes < 60 else { return nil }
        return sign * (hours * 3600 + minutes * 60)
    }

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain = ISO8601DateFormatter()
}
