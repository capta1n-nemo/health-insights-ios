import Foundation

/// **What may leave the phone to make the models better, in two tiers.**
///
/// Backlog B8 R5, and the reader's instruction verbatim (2026-08-06):
///
/// > *"I understand this will contradict the 'stuff never leaves your device',
/// > maybe we update that to read something like a 2-tier opt out (both opted in
/// > by default). E.g. Full - is share both Full Data (e.g. FUll Calendar plus
/// > before and after categories, Meta Data only - sharing just share the
/// > correction metadata (e.g. Blood pressure esitmate is 13 BP above actual
/// > cuff)"*
///
/// ## ⚠️ Nothing is sent. There is no endpoint, no networking, no upload.
///
/// This file is the **preference and the shaping only**. It exists ahead of any
/// transmission on purpose: the shape of what would leave has to be inspectable,
/// testable and switchable *before* anything can go, or the first send is also
/// the first time anybody looks at it.
///
/// ## Why a tier is a function and not a boolean
///
/// A boolean somebody has to remember to consult is the failure mode this app
/// has already recorded elsewhere: a rule held in prose rather than in a type
/// survives exactly as long as the session that wrote it. So the tier is not
/// consulted at each call site — it is the thing that *builds* the record.
/// `shape(kind:changes:fields:)` is the only way a `SharedRecord` comes into
/// existence outside this module, and it is where `.metadataOnly` drops every
/// free-text value. A new shareable record cannot leak content by forgetting a
/// check, because there is no check to forget.
public enum SharingTier: String, Sendable, Codable, CaseIterable, Identifiable {

    /// **Everything about the correction, including its content** — the event's
    /// title, location and calendar; the estimate and the reading it was checked
    /// against; and the before/after categories. The reader's "Full Data (e.g.
    /// FUll Calendar plus before and after categories)".
    case full

    /// **The correction's shape, with none of its content** — how long, how
    /// many, which axis moved and which way, and how far an estimate ran from a
    /// measurement. The reader's *"Blood pressure esitmate is 13 BP above actual
    /// cuff"*: a fact about the model, carrying nothing about the person.
    ///
    /// ⚠️ **The 13 goes; the 122 does not.** A residual describes the model, an
    /// absolute reading describes a body — and the test that separates them is
    /// whether somebody holding the record could reconstruct a reading about
    /// this person. `SharedValue.isContent` is where that question is answered,
    /// once.
    case metadataOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .full: return "Full"
        case .metadataOnly: return "Metadata only"
        }
    }

    /// One line for the Settings row — what this tier includes, not what it is
    /// for.
    public var summary: String {
        switch self {
        case .full:
            return "The corrected item itself — an event's title, place and calendar, or the reading you measured — with what the app guessed and what you said."
        case .metadataOnly:
            return "The shape of the correction only: which way it was wrong, and by how much. No titles, no places, and no readings — a difference, never a value."
        }
    }

    /// Whether this tier carries anything that says something about the
    /// *person* — words they wrote, or a measurement of them. The distinction
    /// the whole two-tier design turns on.
    public var carriesContent: Bool {
        switch self {
        case .full: return true
        case .metadataOnly: return false
        }
    }

    // MARK: - The choke point

    /// Build a shareable record under this tier.
    ///
    /// **The single place a tier is applied.** `.metadataOnly` drops every field
    /// whose value `SharedValue.isContent` — the words somebody wrote and the
    /// readings taken off their body — and keeps everything that describes the
    /// model instead.
    ///
    /// `changes` are never filtered: a change is always a move between cases of
    /// a closed enum the app defined, and "work became personal" names nobody,
    /// reconstructs nothing, and is the whole substance of a calendar
    /// correction.
    public func shape(kind: SharedRecord.Kind,
                      changes: [SharedChange],
                      fields: [SharedField]) -> SharedRecord {
        SharedRecord(kind: kind, tier: self, changes: changes,
                     fields: carriesContent ? fields : fields.filter { !$0.value.isContent })
    }
}

/// Which tiers the reader has left on.
///
/// **Both default to on, at the reader's explicit instruction** — *"both opted
/// in by default"* — and each switches off independently, which is what makes it
/// a two-tier opt *out* rather than one three-position setting.
///
/// ⚠️ `UserDefaults.bool(forKey:)` answers `false` for a key that was never
/// written, so a store-backed implementation of this must read `object(forKey:)`
/// first. Defaulting the wrong way here would silently make the app quieter than
/// the reader asked for, which is the one direction of error that never
/// complains.
public struct SharingPreferences: Sendable, Equatable, Codable {
    public var isFullEnabled: Bool
    public var isMetadataOnlyEnabled: Bool

    public init(isFullEnabled: Bool = true, isMetadataOnlyEnabled: Bool = true) {
        self.isFullEnabled = isFullEnabled
        self.isMetadataOnlyEnabled = isMetadataOnlyEnabled
    }

    /// Both on. The reader's stated default, in one place so a caller cannot
    /// invent a different one.
    public static let standard = SharingPreferences()

    public func isEnabled(_ tier: SharingTier) -> Bool {
        switch tier {
        case .full: return isFullEnabled
        case .metadataOnly: return isMetadataOnlyEnabled
        }
    }

    public mutating func setEnabled(_ enabled: Bool, for tier: SharingTier) {
        switch tier {
        case .full: isFullEnabled = enabled
        case .metadataOnly: isMetadataOnlyEnabled = enabled
        }
    }

    /// The tiers in force, most-inclusive first.
    public var enabledTiers: [SharingTier] {
        SharingTier.allCases.filter(isEnabled)
    }

    /// Whether anything at all would be shared. Both off is a legitimate state
    /// and means exactly what the old single toggle meant when off.
    public var sharesNothing: Bool { enabledTiers.isEmpty }

    /// **The tier a given record would actually go out under**, which is the
    /// question every caller has and none should answer by hand.
    ///
    /// `.full` wins where it is on, because it is a superset. Where only
    /// `.metadataOnly` is on, a record still goes — stripped. Where neither is
    /// on, nothing does, and the `nil` is the refusal.
    public var effectiveTier: SharingTier? {
        if isFullEnabled { return .full }
        if isMetadataOnlyEnabled { return .metadataOnly }
        return nil
    }
}

// MARK: - The shape of a shared record

/// One value in a shared record, tagged with what *kind* of thing it is.
///
/// The tag is the whole mechanism. Two cases are **content** — they say
/// something about the person — and `SharingTier.metadataOnly` refuses both. The
/// rest are **shape**: they describe the model's behaviour and could not be used
/// to reconstruct a reading or name an appointment.
///
/// ## The boundary, as a question
///
/// *Could somebody holding this reconstruct a reading about this person?* If
/// yes, it is content. That is why `.residual` is shape and `.reading` is not:
/// "the estimate ran 13 mmHg high" describes the model, while the 122 it ran
/// high **of** describes a body — and the reader's own example for this tier is
/// the first sentence, not the second.
public enum SharedValue: Sendable, Equatable, Codable, Hashable {

    /// **Content.** Words a person wrote — an event title, a place, a note.
    case freeText(String)

    /// **Content.** An absolute measurement of the reader: a cuff systolic, a
    /// weight, a heart rate. A raw value is content whatever its unit, and no
    /// tier below `.full` carries one.
    case reading(Double)

    /// **Shape.** A difference, an error, a delta — the gap between what the app
    /// said and what turned out to be true. It describes the model, not the
    /// person, and it is the entire point of the metadata tier.
    case residual(Double)

    /// **Shape.** A case of a closed set the app defined — `work`, `personal`,
    /// `formal`, a `MetricType` raw value, a coarse cohort band. It names an app
    /// concept, never a person, a place or an appointment.
    case category(String)

    /// **Shape.** A structural count or duration that is not a measurement of
    /// the reader: how many people were invited, how many hours an event ran.
    case number(Double)

    /// **Shape.** A derived yes/no the app already reduced from something
    /// larger — was there a video link, did you organise it.
    case flag(Bool)

    public var isFreeText: Bool {
        if case .freeText = self { return true }
        return false
    }

    /// Whether this says something about the *person* rather than about the
    /// model. **The one predicate `SharingTier.metadataOnly` filters on**, so
    /// adding a case forces the question to be answered here rather than at
    /// whatever call site happens to build a payload.
    public var isContent: Bool {
        switch self {
        case .freeText, .reading: return true
        case .residual, .category, .number, .flag: return false
        }
    }

    /// For display, and for a test that wants to read the record back.
    public var display: String {
        switch self {
        case .freeText(let text): return text
        case .category(let raw): return raw
        case .reading(let value), .residual(let value), .number(let value):
            return value == value.rounded()
                ? String(Int(value))
                : String(format: "%.1f", value)
        case .flag(let on): return on ? "yes" : "no"
        }
    }

    /// The number behind a `.reading`, `.residual` or `.number`, for callers
    /// composing a sentence out of a record's own fields.
    public var numericValue: Double? {
        switch self {
        case .reading(let value), .residual(let value), .number(let value): return value
        case .freeText, .category, .flag: return nil
        }
    }
}

public struct SharedField: Sendable, Equatable, Codable, Hashable {
    /// A stable machine name — `title`, `attendees`, `durationHours`.
    public let name: String
    /// What a reader should see it called.
    public let label: String
    public let value: SharedValue

    public init(name: String, label: String, value: SharedValue) {
        self.name = name
        self.label = label
        self.value = value
    }
}

/// One axis the reader moved: what the app guessed, and what was actually true.
///
/// Always categories, never free text — which is why it survives both tiers
/// intact and is the entirety of what `.metadataOnly` has to say about a
/// calendar correction.
public struct SharedChange: Sendable, Equatable, Codable, Hashable {
    public let axis: String
    public let axisLabel: String
    public let from: String
    public let to: String

    public init(axis: String, axisLabel: String, from: String, to: String) {
        self.axis = axis
        self.axisLabel = axisLabel
        self.from = from
        self.to = to
    }
}

/// A correction, shaped by a tier, in the form it would leave the phone.
///
/// ⚠️ **It has no public memberwise initialiser.** The only way to *assemble*
/// one from an app's data is `SharingTier.shape(kind:changes:fields:)`, so every
/// record built anywhere in this app has been through the tier filter. That is
/// the difference between a rule and a habit.
///
/// (`Codable`'s synthesised `init(from:)` is public, as it must be for a record
/// to survive a round trip. Decoding one reconstitutes text somebody already
/// had; it cannot extract text from a judgement, which is the leak this design
/// is about.)
public struct SharedRecord: Sendable, Equatable, Codable {

    public enum Kind: String, Sendable, Codable, CaseIterable {
        /// The app read a calendar event and said what it was; the reader said
        /// otherwise.
        case calendarClassification
        /// The app estimated a measurement; a real instrument disagreed. The
        /// reader's blood-pressure example.
        case estimateError
    }

    public let kind: Kind
    public let tier: SharingTier
    public let changes: [SharedChange]
    public let fields: [SharedField]

    init(kind: Kind, tier: SharingTier, changes: [SharedChange], fields: [SharedField]) {
        self.kind = kind
        self.tier = tier
        self.changes = changes
        self.fields = fields
    }

    /// **Every word a person wrote that this record carries.** Empty under
    /// `.metadataOnly`, by construction — and the assertion a test makes rather
    /// than a promise a doc comment makes.
    public var freeText: [String] {
        fields.compactMap {
            if case .freeText(let text) = $0.value { return text }
            return nil
        }
    }

    /// **Every absolute measurement of the reader this record carries.** Also
    /// empty under `.metadataOnly`, and for the same reason: a recipient must
    /// not be able to reconstruct a reading about this person from a record
    /// that claims to be about the model.
    public var readings: [Double] {
        fields.compactMap {
            if case .reading(let value) = $0.value { return value }
            return nil
        }
    }

    /// Anything at all that describes the person rather than the model.
    public var content: [SharedField] { fields.filter(\.value.isContent) }

    public func field(_ name: String) -> SharedValue? {
        fields.first { $0.name == name }?.value
    }

    /// One sentence for the reader, **assembled only from `fields` and
    /// `changes`** — so it cannot name anything the tier has already dropped.
    /// A summary written independently of the payload is how the two drift, and
    /// on this screen a drift is a false privacy claim.
    public var summary: String {
        switch kind {
        case .calendarClassification:
            return "\(subject). \(movement)."
        case .estimateError:
            return estimateSentence
        }
    }

    /// What the record is about, in whatever detail the tier left behind.
    private var subject: String {
        var parts: [String] = []
        if case .freeText(let title)? = field("title"), !title.isEmpty {
            parts.append("“\(title)”")
        }
        if case .freeText(let calendar)? = field("calendarName") {
            parts.append("in your \(calendar) calendar")
        }
        if case .freeText(let place)? = field("location") {
            parts.append("at \(place)")
        }
        if case .number(let hours)? = field("durationHours") {
            parts.append("\(SharedValue.number(hours).display) h")
        }
        if case .number(let people)? = field("attendeeCount") {
            parts.append("\(Int(people)) people")
        }
        if case .flag(true)? = field("hasVideoLink") {
            parts.append("with a video link")
        }
        return parts.isEmpty ? "An event" : parts.joined(separator: ", ")
    }

    private var movement: String {
        guard !changes.isEmpty else { return "You confirmed the app read it correctly" }
        return changes
            .map { "a \($0.from) \($0.axisLabel) guess was corrected to \($0.to)" }
            .joined(separator: "; ")
    }

    private var estimateSentence: String {
        let metric = (field("metric").map(\.display).flatMap { MetricType(rawValue: $0)?.displayName })
            ?? field("metric")?.display ?? "estimate"
        guard case .residual(let difference)? = field("difference") else {
            return "The \(metric) estimate was compared against a measurement."
        }
        let unit = field("unit")?.display ?? ""
        let magnitude = SharedValue.residual(abs(difference)).display
        let direction = difference >= 0 ? "above" : "below"
        let suffix = unit.isEmpty ? "" : " \(unit)"
        return "The \(metric) estimate ran \(magnitude)\(suffix) \(direction) the measured value."
    }
}

// MARK: - What can be shared

/// Something the reader has corrected, which therefore has a shareable shape.
///
/// The protocol exists so "what may leave under tier X" is answered by the type
/// that owns the data, once, rather than by whatever screen happens to be
/// building a payload.
public protocol SharedCorrectionConvertible {
    /// `nil` where there is nothing to share — an item nobody has reviewed is
    /// not a correction, and shipping it as one would inflate any accuracy
    /// figure computed downstream.
    func sharedRecord(under tier: SharingTier) -> SharedRecord?
}

extension CalendarEventJudgement: SharedCorrectionConvertible {

    /// The three layers, shaped: the artifact's fields, and the guess → truth
    /// move on each axis the reader disagreed about.
    ///
    /// A confirmation (`isConfirmed`, no correction) is shared too and carries
    /// no changes — "the app got this one right" is a label in its own right and
    /// the accuracy figure is meaningless without it.
    public func sharedRecord(under tier: SharingTier) -> SharedRecord? {
        guard isConfirmed || correction != nil else { return nil }

        var fields: [SharedField] = []
        if let artifact {
            fields = [
                SharedField(name: "title", label: "Title",
                            value: .freeText(artifact.title)),
                SharedField(name: "calendarName", label: "Calendar",
                            value: .freeText(artifact.calendarName)),
                SharedField(name: "durationHours", label: "Duration",
                            value: .number(artifact.durationHours)),
                SharedField(name: "isAllDay", label: "All day",
                            value: .flag(artifact.isAllDay)),
                SharedField(name: "hasVideoLink", label: "Video link",
                            value: .flag(artifact.hasVideoLink)),
            ]
            if let location = artifact.location {
                fields.append(SharedField(name: "location", label: "Place",
                                          value: .freeText(location)))
            }
            if let attendees = artifact.attendeeCount {
                fields.append(SharedField(name: "attendeeCount", label: "People",
                                          value: .number(Double(attendees))))
            }
            if let organiser = artifact.organizerIsReader {
                fields.append(SharedField(name: "organizerIsReader", label: "You organised it",
                                          value: .flag(organiser)))
            }
        }

        var changes: [SharedChange] = []
        if let correction {
            if correction.context != classification.context {
                changes.append(SharedChange(axis: CalendarEventClassification.contextKey,
                                            axisLabel: "context",
                                            from: classification.context.rawValue,
                                            to: correction.context.rawValue))
            }
            if correction.occasion != classification.occasion {
                changes.append(SharedChange(axis: CalendarEventClassification.occasionKey,
                                            axisLabel: "occasion",
                                            from: classification.occasion.rawValue,
                                            to: correction.occasion.rawValue))
            }
            if correction.formality != classification.formality {
                changes.append(SharedChange(axis: CalendarEventClassification.formalityKey,
                                            axisLabel: "formality",
                                            from: classification.formality.rawValue,
                                            to: correction.formality.rawValue))
            }
            if correction.presence != classification.presence {
                changes.append(SharedChange(axis: "presence", axisLabel: "presence",
                                            from: classification.presence.rawValue,
                                            to: correction.presence.rawValue))
            }
        }

        return tier.shape(kind: .calendarClassification, changes: changes, fields: fields)
    }
}

extension PredictionOutcome: SharedCorrectionConvertible {

    /// The reader's own example — *"Blood pressure esitmate is 13 BP above
    /// actual cuff"*.
    ///
    /// ⚠️ **The two absolute numbers are `.reading`s and the difference is a
    /// `.residual`**, which is the whole distinction under this tier. The
    /// reader's sentence contains the 13 and not the 122: a residual describes
    /// how wrong the model was, while the cuff value it was wrong about is a
    /// measurement of a person and could be reconstructed from nothing else in
    /// the record. So `.full` carries both readings and `.metadataOnly` carries
    /// only the gap — and the sentence the reader wrote is still exactly what
    /// comes out.
    public func sharedRecord(under tier: SharingTier) -> SharedRecord? {
        tier.shape(kind: .estimateError, changes: [], fields: [
            SharedField(name: "metric", label: "Measurement",
                        value: .category(metric.rawValue)),
            SharedField(name: "estimated", label: "The app's estimate",
                        value: .reading(predicted)),
            SharedField(name: "measured", label: "What you measured",
                        value: .reading(actual)),
            SharedField(name: "difference", label: "How far off it was",
                        value: .residual(absoluteError)),
            SharedField(name: "unit", label: "Unit", value: .category(metric.unit)),
            SharedField(name: "modelVersion", label: "Model version",
                        value: .category(modelVersion)),
            // Coarse bands only, exactly as `Cohort` already builds them —
            // `docs/norms-and-telemetry.md` allows a cohort and nothing finer,
            // because a norm needs strata and a person does not need naming.
            SharedField(name: "cohortSex", label: "Group — sex",
                        value: .category(cohort.sex)),
            SharedField(name: "cohortAgeBand", label: "Group — age band",
                        value: .category(cohort.ageBand)),
        ])
    }
}

// MARK: - Worked examples for the Settings screen

/// **What each tier looks like, built by the code that would actually build
/// it.**
///
/// The reader is entitled to see the difference concretely rather than read two
/// category names, and a hand-written example on a settings screen is a promise
/// about the shaper rather than a demonstration of it — the two drift, and here
/// a drift is a false privacy claim. So these are real records, put through
/// `SharingTier.shape` like everything else.
///
/// ⚠️ **The event is invented.** "Quarterly review with Northwind" is not
/// anybody's meeting; using a real one would put the reader's own calendar in a
/// screenshot of a privacy screen.
public enum SharingExample {

    public static let eventTitle = "Quarterly review with Northwind"

    /// A work guess corrected to personal, on a fictional event.
    public static func calendarCorrection(under tier: SharingTier) -> SharedRecord {
        let guess = CalendarEventClassification(
            context: .work, occasion: .meeting, presence: .inPerson,
            formality: .formal, hours: 1.5)
        let truth = CalendarEventClassification(
            context: .personal, occasion: .meeting, presence: .inPerson,
            formality: .casual, hours: 1.5)
        let artifact = CalendarEventArtifact(
            title: eventTitle, location: "Level 3, 200 Example St",
            attendeeCount: 6, durationHours: 1.5, isAllDay: false,
            calendarName: "Work", hasVideoLink: true, organizerIsReader: false,
            capturedAt: Date(timeIntervalSince1970: 0))
        let judgement = CalendarEventJudgement(
            eventID: "example", classification: guess, correction: truth,
            isConfirmed: true, reviewedAt: Date(timeIntervalSince1970: 0),
            artifact: artifact)
        // Force-unwrapped deliberately: the fixture has a correction, so a nil
        // here means `sharedRecord` stopped honouring its own contract and the
        // crash belongs in the test suite rather than in a shipped screen that
        // quietly shows nothing.
        return judgement.sharedRecord(under: tier)!
    }

    /// The reader's blood-pressure example, at their own figure.
    public static func estimateCorrection(under tier: SharingTier) -> SharedRecord {
        let outcome = PredictionOutcome(
            insightID: .bloodPressure, metric: .bloodPressureSystolic,
            predicted: 131, actual: 118, modelVersion: "example",
            cohort: Cohort(sex: "unspecified", ageBand: "unspecified",
                           ethnicity: "unspecified", region: "unspecified"),
            recordedAt: Date(timeIntervalSince1970: 0))
        return outcome.sharedRecord(under: tier)!
    }
}
