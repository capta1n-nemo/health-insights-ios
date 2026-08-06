import Foundation

/// **What each calendar item actually was**, on the six axes the reader asked
/// for (2026-08-06):
///
/// > *"Was this work or personal? Was this actually a meeting, or just something
/// > like a reminder? Did it have a location (meaning I had to be somewhere), or
/// > did it include a remote meeting link? How long was the meeting? Was it a
/// > marathon workshop? Was it travel? … The sentiment of the meeting — is it a
/// > chill catchup or a formal meeting with a client?"*
///
/// ## Why the rules exist even though the reader asked for AI
///
/// They asked for the on-device model to read the events, and it does — but the
/// model is the **refinement**, not the floor. Three reasons, and the third is
/// the one that matters:
///
/// 1. `SystemLanguageModel` is unavailable on a lot of hardware, and
///    `FoundationModelSummarizer` already carries a fallback for exactly that.
/// 2. It is unavailable in every test, and a classifier that cannot be tested on
///    Linux cannot be tested at all in this project.
/// 3. **Half of these six axes are not judgement calls.** Duration is
///    arithmetic. "Did it have a location" is a field being present. "Was there
///    a video link" is a boolean the app already derived. Asking a language
///    model to decide those would be slower, non-deterministic, and *less*
///    accurate than reading them — and it would put a hallucination between the
///    reader and a fact their own calendar already stated.
///
/// So the rules answer everything they can answer exactly, the model is asked
/// only about the genuinely interpretive axes — work-versus-personal on an
/// ambiguous title, travel, and sentiment — and every field records **who
/// decided it**. That last part is what makes the reader's corrections
/// meaningful: a correction against a rule is a bug report, and a correction
/// against the model is training signal.
public struct CalendarEventClassification: Sendable, Equatable, Codable, Hashable {

    /// Who decided a field. Carried per classification rather than per app run,
    /// because one event can be part rule and part model and part reader.
    public enum Decider: String, Sendable, Codable, CaseIterable {
        /// Read straight off the event. Not a guess.
        case fact
        /// Deterministic rules over the title and calendar name.
        case rules
        /// The on-device language model.
        case model
        /// The reader corrected it. **Outranks everything and is never
        /// overwritten** — see `CalendarEventJudgement`.
        case reader

        public var title: String {
            switch self {
            case .fact: return "From the event"
            case .rules: return "Worked out"
            case .model: return "Read by the on-device model"
            case .reader: return "You said so"
            }
        }
    }

    public enum Context: String, Sendable, Codable, CaseIterable, Identifiable {
        case work, personal, unknown
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .work: return "Work"
            case .personal: return "Personal"
            case .unknown: return "Not sure"
            }
        }
    }

    /// What kind of thing it was — the reader's "actually a meeting, or just
    /// something like a reminder".
    public enum Occasion: String, Sendable, Codable, CaseIterable, Identifiable {
        /// People, at a time, together.
        case meeting
        /// A marker with no attendance: a birthday, a bin day, a note to self.
        case reminder
        /// Time the reader blocked out for themselves — focus time, gym, lunch.
        case blockedTime
        /// A flight, a drive, a trip. The reader's travel placeholders.
        case travel
        /// **The reader's own leave** — their OOO block, their "Annual leave",
        /// their holiday. B7 H2/H3: this is the outcome that feeds the holiday
        /// ledger, and it exists as a classification rather than a bucket
        /// because whose absence a block records decides everything about it.
        case leave
        /// **Someone's absence, not established as the reader's** — a
        /// colleague's OOO, or an absence marker no identity can resolve.
        /// One case for both readings on purpose: they behave identically
        /// everywhere downstream (never a meeting, never load, never the
        /// ledger), and the boundary that matters — mine or not mine — is
        /// exactly the boundary between this case and `.leave`. The review
        /// sheet offers both, so "that's actually mine" is a one-tap
        /// correction that reaches the ledger.
        case absence
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .meeting: return "Meeting"
            case .reminder: return "Reminder"
            case .blockedTime: return "Blocked time"
            case .travel: return "Travel"
            case .leave: return "Your leave"
            case .absence: return "Someone away"
            }
        }
    }

    /// Where the reader had to be — the axis that decides whether an hour cost
    /// them a commute as well as an hour.
    public enum Presence: String, Sendable, Codable, CaseIterable, Identifiable {
        /// A place was named and no link was attached.
        case inPerson
        /// A video link was attached.
        case remote
        /// Both — a room with people dialling in.
        case hybrid
        /// Neither was stated.
        case unstated
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .inPerson: return "In person"
            case .remote: return "Remote"
            case .hybrid: return "Hybrid"
            case .unstated: return "Not stated"
            }
        }
    }

    /// The reader's "chill catchup or a formal meeting with a client".
    public enum Formality: String, Sendable, Codable, CaseIterable, Identifiable {
        case casual, standard, formal
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .casual: return "Casual"
            case .standard: return "Standard"
            case .formal: return "Formal"
            }
        }
        /// How much a meeting of this kind is assumed to cost, relative to a
        /// standard one. **Not a measurement** — it is the app's stated
        /// assumption, and the card that uses it says so.
        public var loadMultiplier: Double {
            switch self {
            case .casual: return 0.6
            case .standard: return 1.0
            case .formal: return 1.4
            }
        }
    }

    public let context: Context
    public let occasion: Occasion
    public let presence: Presence
    public let formality: Formality
    /// Hours, straight off the event. Always a `fact`.
    public let hours: Double
    /// A single stretch long enough to be a day rather than a slot.
    public var isMarathon: Bool { hours >= CalendarEventClassifier.marathonHours }

    /// Who decided each interpretive axis. Duration and presence are facts and
    /// carry no entry — there is nothing to attribute.
    public let deciders: [String: Decider]

    public init(context: Context, occasion: Occasion, presence: Presence,
                formality: Formality, hours: Double,
                deciders: [String: Decider] = [:]) {
        self.context = context
        self.occasion = occasion
        self.presence = presence
        self.formality = formality
        self.hours = hours
        self.deciders = deciders
    }

    public static let contextKey = "context"
    public static let occasionKey = "occasion"
    public static let formalityKey = "formality"

    public func decider(for key: String) -> Decider { deciders[key] ?? .rules }

    /// **How much of the reader's day this actually took**, which is what feeds
    /// a card's score rather than a raw hour count.
    ///
    /// A two-hour formal client meeting in a room is not the same load as two
    /// hours of blocked focus time, and counting them equally is what makes
    /// every "how busy were you" number useless. Reminders cost nothing — they
    /// are markers, not commitments.
    public var loadHours: Double {
        switch occasion {
        case .reminder: return 0
        // An absence is not a commitment, whoever it belongs to. The reader's
        // own leave feeds the *holiday ledger*, never the meeting load; a
        // colleague's OOO is if anything a lighter week — the backlog notes
        // "possibly reduced load", which is H6's call to make when the cards
        // read the ledger, and zero is the honest floor until then.
        case .leave, .absence: return 0
        case .travel: return hours
        case .blockedTime: return hours * 0.5
        case .meeting:
            // In-person costs more than remote for the same hour: somebody had
            // to get there. A stated assumption, and the card says so.
            let presenceCost: Double
            switch presence {
            case .inPerson: presenceCost = 1.25
            case .hybrid: presenceCost = 1.1
            case .remote, .unstated: presenceCost = 1.0
            }
            return hours * formality.loadMultiplier * presenceCost
        }
    }
}

/// One event, its classification, and any correction the reader has made.
///
/// **The reader's correction is stored separately from the classification, not
/// merged into it**, and that is the whole design of the learning loop they
/// asked for: *"an opportunity to correct them or confirm, which the model can
/// learn from."*
///
/// Merged, a correction would be indistinguishable from a good guess the next
/// time anything ran — so the app could never tell how often it was right, and
/// re-classifying would silently overwrite the reader. Kept apart, the app has a
/// growing labelled set: the guess, the truth, and the gap between them.
public struct CalendarEventJudgement: Sendable, Equatable, Codable, Identifiable {
    public let eventID: String
    /// What the app worked out, untouched by any correction.
    public let classification: CalendarEventClassification
    /// What the reader said, where they said anything.
    public let correction: CalendarEventClassification?
    /// True where the reader looked at it and agreed. **Different from an
    /// absent correction** — "confirmed correct" is a label and "not yet looked
    /// at" is not, and treating them as one would inflate any accuracy figure
    /// the app ever computes.
    public let isConfirmed: Bool
    public let reviewedAt: Date?

    public var id: String { eventID }

    /// What the rest of the app should use.
    public var effective: CalendarEventClassification { correction ?? classification }

    /// Whether the reader disagreed on any axis — the training signal.
    public var wasCorrected: Bool {
        guard let correction else { return false }
        return correction.context != classification.context
            || correction.occasion != classification.occasion
            || correction.formality != classification.formality
            || correction.presence != classification.presence
    }

    public init(eventID: String, classification: CalendarEventClassification,
                correction: CalendarEventClassification? = nil,
                isConfirmed: Bool = false, reviewedAt: Date? = nil) {
        self.eventID = eventID
        self.classification = classification
        self.correction = correction
        self.isConfirmed = isConfirmed
        self.reviewedAt = reviewedAt
    }
}

/// How the app is doing at this, from the reader's own corrections.
///
/// The figure the learning loop exists to move, and it can only be computed
/// because corrections are kept apart from guesses.
public struct CalendarClassifierAccuracy: Sendable, Equatable {
    public let reviewed: Int
    public let agreed: Int
    /// Nil until enough has been reviewed to mean anything — the same refusal
    /// `CycleSummary.lengthRange` makes, for the same reason.
    public var rate: Double? {
        reviewed >= CalendarEventClassifier.minimumReviewedForAccuracy
            ? Double(agreed) / Double(reviewed) : nil
    }

    public static func measure(_ judgements: [CalendarEventJudgement]) -> CalendarClassifierAccuracy {
        let reviewed = judgements.filter { $0.isConfirmed || $0.correction != nil }
        return CalendarClassifierAccuracy(
            reviewed: reviewed.count,
            agreed: reviewed.filter { !$0.wasCorrected }.count)
    }
}
