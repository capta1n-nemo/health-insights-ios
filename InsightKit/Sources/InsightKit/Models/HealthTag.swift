import Foundation

/// **The high-level thing a tag is *about*.**
///
/// The reader's own framing, 2026-08-07: *"if we see a sport related tag, it
/// will live primarily in its tags section, and whatever it is (eg Kayaking)
/// will have an 'applicability' of 'Activity & mobility'"*.
///
/// So an applicability is not a card and not a metric — it is a **statement
/// about the subject** of a word the reader typed. `.activity`'s raw value is
/// `"Activity & mobility"` verbatim, and deliberately the same string as
/// `MetricDataCategory.activity`: a reader who has learnt that heading in the
/// Data tab should meet the same words here rather than a synonym.
///
/// ⚠️ **A closed set over an open input.** Tags are unbounded — Oura lets a
/// person invent one — so the *categories* are the only part that can be fixed,
/// and everything unbounded has to be resolved onto them. That is what
/// `TagLexicon` and the on-device model do, and it is why `.unclassified`
/// exists as a first-class answer rather than a failure: "we have not worked
/// out what this is about" is true, useful and honest, and printing a guess in
/// its place would be none of the three.
public enum TagApplicability: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case activity = "Activity & mobility"
    case sleepRecovery = "Sleep & recovery"
    case mentalHealth = "Mental health"
    case illness = "Illness & symptoms"
    case substances = "Substances"
    case nutrition = "Nutrition"
    case medication = "Medication"
    case social = "Life events & social"
    case travel = "Travel"
    case work = "Work & study"
    /// **Not a failure state.** A tag whose subject the app cannot place, said
    /// plainly. It still lives in the Tags section, still carries its dates and
    /// still counts — it simply makes no claim about what it is about.
    case unclassified = "Not yet classified"

    public var id: String { rawValue }

    /// Everything except `.unclassified`, which is what a classifier is allowed
    /// to *choose from*. `.unclassified` is what it returns when it cannot.
    public static var classifiable: [TagApplicability] {
        allCases.filter { $0 != .unclassified }
    }

    /// **What this applicability means** — standing rule 11, every data entry
    /// carries a "what this is" description. Rendered under each group in the
    /// Tags data page, so a reader never meets a bare heading.
    public var summary: String {
        switch self {
        case .activity:
            return "Something you did with your body — a sport, a session, a walk, a climb. The same heading the Data tab uses for movement metrics."
        case .sleepRecovery:
            return "About the night, or about deliberately recovering — naps, a bad night, a sauna, a rest day."
        case .mentalHealth:
            return "How you were feeling rather than what you did — stress, mood, calm, a meditation."
        case .illness:
            return "Being unwell, or a symptom you noticed. Kept apart from mental health because a fever and a bad mood are not the same finding."
        case .substances:
            return "Alcohol, caffeine, nicotine and the rest — what you took in that the app already tracks a cardiovascular load for."
        case .nutrition:
            return "Food and drink as food: a meal, a fast, a diet you were following, how much water you had."
        case .medication:
            return "A dose, a supplement, a vaccination — something taken for its effect rather than for pleasure."
        case .social:
            return "The day's shape rather than the body's: people, occasions, an argument, a celebration."
        case .travel:
            return "Being somewhere else — a flight, a time zone, a hotel, a long drive."
        case .work:
            return "Work and study — a deadline, a shift, an exam, a day in the office."
        case .unclassified:
            return "The app has not worked out what this tag is about. It is kept exactly as you wrote it, and nothing is inferred from it."
        }
    }

    /// **Where a tag of this kind *could* contribute, at the next review.**
    ///
    /// ⚠️ **Nothing here is wired, and that is the reader's own instruction**,
    /// 2026-08-07: activity tags *"become candidates for cards at the next
    /// review"* — not inputs. This property is therefore prose the Tags page
    /// prints, not an `InsightID` something could switch on: a typed link to a
    /// card is an invitation to quietly start feeding it, and a tag is
    /// self-reported free text that has never been validated against anything.
    ///
    /// The gap between "we can see this is about kayaking" and "kayaking should
    /// move your fitness score" is a decision the reader makes, once, looking at
    /// their own tags.
    public var candidateNote: String? {
        switch self {
        case .activity: return "Candidate for Fitness — not used yet."
        case .illness: return "Candidate for Symptom radar — not used yet."
        case .mentalHealth: return "Candidate for Stress and Mental health — not used yet."
        case .sleepRecovery: return "Candidate for Sleep and Readiness — not used yet."
        case .substances: return "Candidate for the substance log — not used yet."
        case .medication: return "Candidate for Medication — not used yet."
        case .nutrition, .social, .travel, .work: return nil
        case .unclassified: return nil
        }
    }

    /// A symbol for the group heading. SF Symbols only, so an unseen tag never
    /// needs artwork.
    public var symbolName: String {
        switch self {
        case .activity: return "figure.run"
        case .sleepRecovery: return "bed.double"
        case .mentalHealth: return "brain.head.profile"
        case .illness: return "thermometer.medium"
        case .substances: return "wineglass"
        case .nutrition: return "fork.knife"
        case .medication: return "pills"
        case .social: return "person.2"
        case .travel: return "airplane"
        case .work: return "briefcase"
        case .unclassified: return "questionmark.circle"
        }
    }
}

/// **How a tag's applicability was decided.** Carried on every mapping, because
/// the three are not equally trustworthy and a reader is entitled to know which
/// one they are looking at.
public enum TagMappingMethod: String, Codable, Sendable, Hashable, CaseIterable {
    /// The provider's own machine code said so — Oura's `tag_type_code`
    /// (`tag_generic_alcohol`). The strongest of the three: it is the vendor
    /// naming its own concept, not anybody's inference.
    case providerCode
    /// `TagLexicon` matched a word stem. Deterministic, works with no model and
    /// no network, and is the path that has to hold on a device where Apple
    /// Intelligence is unavailable.
    case lexicon
    /// The **on-device** language model was asked. Never leaves the phone; see
    /// `TagApplicabilityPrompt`.
    case onDeviceModel
    /// The reader corrected it. Beats everything else, permanently.
    case reader
    /// Nothing placed it.
    case unresolved

    public var title: String {
        switch self {
        case .providerCode: return "From the tag's own type"
        case .lexicon: return "Matched on this device"
        case .onDeviceModel: return "Worked out on this device"
        case .reader: return "You said so"
        case .unresolved: return "Not worked out"
        }
    }
}

/// One decision about what a tag is about, **with its own uncertainty attached**.
///
/// Standing rule 6: every estimate states its own uncertainty. An applicability
/// is an estimate — nothing measured it — so it travels with the method that
/// produced it, a 0–1 confidence and the evidence in words.
public struct TagApplicabilityMapping: Codable, Sendable, Hashable {
    public let applicability: TagApplicability
    public let method: TagMappingMethod
    /// 0–1. **Never 1 except for `.reader`**: the reader saying what their own
    /// word meant is the only certainty available here.
    public let confidence: Double
    /// Why, in the app's own words — "matched 'kayak'", "Oura calls this
    /// `tag_generic_alcohol`". Shown on the row, so a reader can disagree with
    /// the reasoning rather than only with the answer.
    public let rationale: String

    public init(applicability: TagApplicability, method: TagMappingMethod,
                confidence: Double, rationale: String) {
        self.applicability = applicability
        self.method = method
        self.confidence = min(max(confidence, 0), 1)
        self.rationale = rationale
    }

    /// The honest answer when nothing placed a tag.
    public static let unresolved = TagApplicabilityMapping(
        applicability: .unclassified, method: .unresolved, confidence: 0,
        rationale: "No word in this tag matched anything the app knows, and the on-device model was not able to place it.")

    /// Whether this is worth asking the on-device model about.
    ///
    /// Unresolved always; a low-confidence lexicon hit as well — a single stem
    /// match on a long tag is thin evidence, and the model is the cheaper of the
    /// two ways to improve it (the other being asking the reader).
    public var wantsModelReview: Bool {
        switch method {
        case .reader, .providerCode, .onDeviceModel: return false
        case .unresolved: return true
        case .lexicon: return confidence < 0.5
        }
    }
}

/// **One tag, applied once.**
///
/// The occurrence, not the vocabulary: three kayaking sessions are three of
/// these. `TagSummary` is the grouped view, and the Tags page shows both — the
/// distinct tags a reader has, and every time each was used.
public struct HealthTag: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// **The reader's own words**, as close to verbatim as the provider gives
    /// them — "Kayaking", "Late night", "Big client meeting".
    public let name: String
    /// The provider's machine code where there is one — Oura's
    /// `tag_generic_alcohol`. `nil` for a custom tag, which is exactly the case
    /// a lookup table cannot serve and the reason the lexicon and the model
    /// exist.
    public let code: String?
    public let date: Date
    public let source: MetricSource
    public let mapping: TagApplicabilityMapping

    public init(id: UUID = UUID(), name: String, code: String? = nil, date: Date,
                source: MetricSource, mapping: TagApplicabilityMapping) {
        self.id = id
        self.name = name
        self.code = code
        self.date = date
        self.source = source
        self.mapping = mapping
    }

    /// The grouping key: case- and punctuation-insensitive, so "Kayaking",
    /// "kayaking" and "kayaking!" are one tag rather than three.
    public var key: String { HealthTag.key(for: name) }

    public static func key(for name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
        let cleaned = folded.map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : " "
        }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }
}

/// One distinct tag and everything the reader has done with it.
public struct TagSummary: Sendable, Hashable, Identifiable {
    public let key: String
    /// The spelling to show — the most recent one the reader used, so a tag they
    /// have since renamed reads the way they last wrote it.
    public let name: String
    public let code: String?
    public let mapping: TagApplicabilityMapping
    public let count: Int
    public let firstUsed: Date
    public let lastUsed: Date

    public var id: String { key }

    public init(key: String, name: String, code: String?,
                mapping: TagApplicabilityMapping, count: Int,
                firstUsed: Date, lastUsed: Date) {
        self.key = key
        self.name = name
        self.code = code
        self.mapping = mapping
        self.count = count
        self.firstUsed = firstUsed
        self.lastUsed = lastUsed
    }
}

public extension Array where Element == HealthTag {
    /// The distinct tags, newest-used first.
    ///
    /// The mapping shown for a group is the **best-evidenced** one across its
    /// occurrences, not the newest: a reader override recorded once must not be
    /// undone by the next sync re-importing the same word with a lexicon guess
    /// on it.
    func distinctTags() -> [TagSummary] {
        Dictionary(grouping: self, by: \.key).values.compactMap { group -> TagSummary? in
            guard let newest = group.max(by: { $0.date < $1.date }),
                  let oldest = group.min(by: { $0.date < $1.date }) else { return nil }
            let best = group.map(\.mapping).max {
                TagMappingRank.rank($0) < TagMappingRank.rank($1)
            } ?? newest.mapping
            return TagSummary(key: newest.key, name: newest.name,
                              code: group.compactMap(\.code).first,
                              mapping: best, count: group.count,
                              firstUsed: oldest.date, lastUsed: newest.date)
        }
        .sorted { $0.lastUsed > $1.lastUsed }
    }

    /// Grouped by what they are about, in `TagApplicability` order, with
    /// `.unclassified` always last so an unplaced tag is never the first thing
    /// on the page.
    func groupedByApplicability() -> [(applicability: TagApplicability, tags: [TagSummary])] {
        let summaries = distinctTags()
        return TagApplicability.allCases.compactMap { applicability in
            let matching = summaries.filter { $0.mapping.applicability == applicability }
            guard !matching.isEmpty else { return nil }
            return (applicability, matching)
        }
    }
}

/// Which of two mappings is better evidenced. A free function rather than
/// `Comparable` on the mapping, because "better evidenced" is not the only order
/// anyone would want and a `<` that silently means this one is a trap.
public enum TagMappingRank {
    public static func rank(_ mapping: TagApplicabilityMapping) -> Double {
        let base: Double
        switch mapping.method {
        case .reader: base = 400
        case .providerCode: base = 300
        case .onDeviceModel: base = 200
        case .lexicon: base = 100
        case .unresolved: base = 0
        }
        return base + mapping.confidence
    }
}
