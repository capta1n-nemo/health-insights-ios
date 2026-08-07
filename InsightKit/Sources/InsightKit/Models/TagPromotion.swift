import Foundation

/// **Lifting tags out of the raw catalogue into first-class `HealthTag`s.**
///
/// The same shape as `SymptomPromotion`, and for the same reason: promotion
/// *reads* rather than moves, so the raw rows stay exactly where they are, the
/// "Other data" browser is unchanged, and a bug in here cannot cost the reader
/// data that was already in the file.
///
/// ## What a tag looks like once it has been through the pipeline
///
/// `GenericJSONIngestor` flattens one Oura record into one `RawMetricSample`
/// **per field**, all sharing the record's timestamp. So an `enhanced_tag`
/// record arrives here as two or three separate rows:
///
/// ```
/// oura.enhanced_tag.tag_type_code = "tag_generic_alcohol"   @ 2026-08-01T19:00Z
/// oura.enhanced_tag.custom_name   = "Kayaking"              @ 2026-08-01T19:00Z
/// oura.enhanced_tag.comment       = "…"                     @ 2026-08-01T19:00Z
/// ```
///
/// **Re-assembling the record is therefore this type's actual job**, and it is
/// done by grouping on `(source, endpoint, instant)` — which is what a record
/// is, once its fields have been scattered.
///
/// ⚠️ **`comment` and `text` are deliberately not read.** They are the reader's
/// free-form note *about* a tag, not the tag; treating a sentence as a tag name
/// would fill the Tags section with one-off strings that group with nothing and
/// classify as nothing. They remain in the raw catalogue, where free text from a
/// provider has always lived.
public enum TagPromotion {

    /// Endpoint components that carry tags, whatever provider they came from.
    static let tagEndpoints: Set<String> = ["tag", "tags", "enhanced_tag", "enhanced_tags"]

    /// Leaves that hold a provider's machine code for the tag.
    static let codeLeaves: Set<String> = ["tag_type_code", "tag_type", "type", "code"]

    /// Leaves that hold the reader's own words.
    static let nameLeaves: Set<String> = ["custom_name", "tag_name", "name", "label"]

    /// One reassembled tag record, before it has been classified.
    struct Record {
        var code: String?
        var name: String?
        /// Oura's legacy `tag` endpoint carries an *array* of codes on one
        /// record (`tags: ["tag_generic_stress", "tag_generic_travel"]`), which
        /// the flattener turns into `tags.0`, `tags.1`. One record, several tags.
        var listedCodes: [String] = []
    }

    /// Every tag in the raw catalogue, newest first, each already classified by
    /// the deterministic tiers.
    ///
    /// - Parameter resolved: mappings that beat the deterministic ones — the
    ///   on-device model's answers and the reader's own corrections, held by
    ///   `TagMappingStore`. Anything absent falls back to `TagLexicon`, so the
    ///   feature works in full on a device with no language model at all.
    public static func tags(from raw: [RawMetricSample],
                            resolved: TagMappingStore = TagMappingStore()) -> [HealthTag] {
        var records: [RecordKey: Record] = [:]
        var order: [RecordKey] = []

        for sample in raw {
            guard let parts = Self.parts(of: sample.identifier) else { continue }
            let key = RecordKey(source: sample.source, endpoint: parts.endpoint,
                                instant: sample.start)
            guard case .text(let text) = sample.value else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if records[key] == nil {
                records[key] = Record()
                order.append(key)
            }
            let leaf = parts.leaf
            if codeLeaves.contains(leaf) {
                records[key]?.code = trimmed
            } else if nameLeaves.contains(leaf) {
                records[key]?.name = trimmed
            } else if parts.isListedTag {
                records[key]?.listedCodes.append(trimmed)
            }
        }

        var out: [HealthTag] = []
        for key in order {
            guard let record = records[key] else { continue }
            let source = key.source
            // The array form first: one record can hold several tags, and each
            // is its own occurrence.
            for code in record.listedCodes {
                out.append(tag(name: record.name ?? displayName(forCode: code),
                               code: code, date: key.instant, source: source,
                               resolved: resolved))
            }
            guard record.listedCodes.isEmpty else { continue }
            // A record with neither a name nor a code is not a tag; a record
            // with only a code is a stock tag and its name comes from the code.
            let name = record.name ?? record.code.map(displayName(forCode:))
            guard let name, !name.isEmpty else { continue }
            out.append(tag(name: name, code: record.code, date: key.instant,
                           source: source, resolved: resolved))
        }
        return out.sorted { $0.date > $1.date }
    }

    /// Classify one tag, letting a stored answer win where there is one.
    static func tag(name: String, code: String?, date: Date, source: MetricSource,
                    resolved: TagMappingStore) -> HealthTag {
        let deterministic = TagLexicon.classify(name: name, code: code)
        let stored = resolved.mapping(for: HealthTag.key(for: name))
        let mapping = [deterministic, stored].compactMap { $0 }
            .max { TagMappingRank.rank($0) < TagMappingRank.rank($1) } ?? deterministic
        return HealthTag(name: name, code: code, date: date, source: source, mapping: mapping)
    }

    /// `tag_generic_late_night` → `Late night`. The reader never chose these
    /// words, so they are shown the way a person would write them rather than
    /// the way an API does.
    public static func displayName(forCode code: String) -> String {
        let bare = TagLexicon.meaningfulCode(code) ?? code
        let spaced = bare.replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard let first = spaced.first else { return code }
        return first.uppercased() + spaced.dropFirst()
    }

    // MARK: - Identifier shape

    struct RecordKey: Hashable {
        let source: MetricSource
        let endpoint: String
        let instant: Date
    }

    struct Parts {
        let endpoint: String
        let leaf: String
        /// `tags.0` — an element of a code array rather than a named field.
        let isListedTag: Bool
    }

    /// Split `oura.enhanced_tag.tag_type_code` into its endpoint and its leaf,
    /// or return `nil` when this identifier is not a tag field at all.
    ///
    /// The endpoint is the **second** component, because
    /// `IngestionPipeline.absorb` builds every raw identifier as
    /// `<source>.<endpoint>.<path>` — see that function; nothing else in the app
    /// needs to know the shape, which is why this is the only other place that
    /// takes it apart.
    static func parts(of identifier: String) -> Parts? {
        let components = identifier.split(separator: ".").map(String.init)
        guard components.count >= 3 else { return nil }
        let endpoint = components[1]
        guard tagEndpoints.contains(endpoint) else { return nil }
        let path = Array(components.dropFirst(2))
        // `tags.0` under any tag endpoint: an array of codes.
        if path.count == 2, path[0] == "tags", Int(path[1]) != nil {
            return Parts(endpoint: endpoint, leaf: path[0], isListedTag: true)
        }
        guard let leaf = path.last else { return nil }
        return Parts(endpoint: endpoint, leaf: leaf, isListedTag: false)
    }
}

/// **Answers that beat the deterministic classifier** — the on-device model's,
/// and the reader's own corrections — keyed by `HealthTag.key`.
///
/// Persisted by the app (UserDefaults, like `TypeSightingLedger`) rather than
/// recomputed, for two reasons that are not the same:
///
/// - the **reader's** corrections are data, and losing them on a resync would
///   be losing something they typed;
/// - the **model's** answers are expensive and non-deterministic. Asking again
///   on every launch would burn battery to get a possibly *different* heading
///   over the same word, which reads as the app changing its mind at random.
///
/// It stores by tag key rather than by occurrence, so classifying "Kayaking"
/// once places every kayaking session the reader has ever logged, including the
/// ones that arrive next month.
public struct TagMappingStore: Codable, Sendable, Equatable {
    private var mappings: [String: TagApplicabilityMapping]

    /// **Tags the on-device model was asked about and could not place.**
    ///
    /// Not a cache of an answer — there is no answer — but a record that the
    /// question has already been put. It exists because of a starvation bug that
    /// only shows up on a real library of tags: `TagApplicabilityModel` asks
    /// about at most a dozen tags per pass, most-used first, and re-asks anything
    /// still unplaced. A tag the model *cannot* place therefore stays at the head
    /// of that queue for ever, and the thirteenth tag is never asked at all. On a
    /// reader with twenty invented tags, eight of them would never have been seen
    /// by the model on any launch.
    ///
    /// ⚠️ **Only a settled "I don't know" belongs in here** — the model replied
    /// and named no category. A *thrown* call (Apple Intelligence switched off
    /// mid-flight, a guardrail, a timeout) must never land here, because that is
    /// a transient condition and recording it would permanently retire a tag over
    /// a momentary failure. `TagApplicabilityModel.Outcome` is what keeps the two
    /// apart.
    private var declinedByModel: Set<String>

    public init(mappings: [String: TagApplicabilityMapping] = [:],
                declinedByModel: Set<String> = []) {
        self.mappings = mappings
        self.declinedByModel = declinedByModel
    }

    /// Hand-written so a store persisted before `declinedByModel` existed still
    /// decodes. The synthesized initialiser throws on a missing key, and the
    /// thing that would be lost is every correction the reader has ever made.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mappings = try container.decodeIfPresent([String: TagApplicabilityMapping].self,
                                                 forKey: .mappings) ?? [:]
        declinedByModel = try container.decodeIfPresent(Set<String>.self,
                                                        forKey: .declinedByModel) ?? []
    }

    public var keys: Set<String> { Set(mappings.keys) }
    public var isEmpty: Bool { mappings.isEmpty && declinedByModel.isEmpty }
    public var count: Int { mappings.count }

    public func mapping(for key: String) -> TagApplicabilityMapping? { mappings[key] }

    /// Whether the model has already been asked about this tag and said nothing.
    public func modelHasDeclined(_ key: String) -> Bool { declinedByModel.contains(key) }

    /// Record that the model answered and named no category this app has.
    public mutating func recordModelDeclined(_ key: String) {
        declinedByModel.insert(key)
    }

    /// Record an answer, **keeping the better-evidenced one — except that the
    /// reader always wins.**
    ///
    /// ⚠️ Not a plain assignment, and that is the whole safety property here: a
    /// later, weaker answer must not overwrite a stronger earlier one. The case
    /// this protects is concrete — the reader corrects "Sauna" to Sleep &
    /// recovery, and the next sync hands the model the same word and gets
    /// Activity back. Ranking rather than recency means the reader's correction
    /// stands until the reader changes it.
    ///
    /// ⚠️ **And the reader changing it is the case a rank comparison alone gets
    /// wrong.** Two `.reader` mappings rank identically (400 + 1.0), so a strict
    /// `>` silently discarded the second one: a reader who corrected "Sauna" to
    /// Sleep & recovery and then decided it was really Activity tapped the menu,
    /// watched the row snap back, and had no way to tell the app was refusing
    /// them. A correction is not evidence to be weighed against the previous
    /// correction — it is the reader saying what their own word meant, which is
    /// the one thing in here that is not an inference at all.
    public mutating func record(_ mapping: TagApplicabilityMapping, for key: String) {
        // A tag the reader has just placed themselves is settled; if the model
        // had previously given up on it, that fact is now irrelevant and keeping
        // it would only stop a future pass ever re-examining a re-cleared tag.
        if mapping.method == .reader {
            mappings[key] = mapping
            declinedByModel.remove(key)
            return
        }
        guard let existing = mappings[key] else {
            mappings[key] = mapping
            return
        }
        if TagMappingRank.rank(mapping) > TagMappingRank.rank(existing) {
            mappings[key] = mapping
        }
    }

    /// Drop everything stored about a tag, ignoring rank. **The reader taking
    /// their own correction back**, which is the one case where a weaker mapping
    /// is the right one — the deterministic classifier's answer returns, and the
    /// model is free to be asked again.
    public mutating func clear(_ key: String) {
        mappings.removeValue(forKey: key)
        declinedByModel.remove(key)
    }

    private enum CodingKeys: String, CodingKey {
        case mappings, declinedByModel
    }
}
